#!/usr/bin/env node
// check-acceptance-criteria.mjs - Config-driven acceptance-criteria lifecycle
// gate.
//
// THE CONTRACT: THIS GATE NEVER CONVERTS "I DO NOT UNDERSTAND THIS INPUT" INTO
// A PASS. Handoff documents are hand-written and their shapes are unbounded, so
// any parser will meet a shape it cannot read. When that happens the gate says
// so instead of falling silent, because a silent pass is indistinguishable from
// a clean document and that is the failure mode this gate exists to prevent.
// Everything it cannot interpret is a finding. Findings are warnings by
// default, so the cost of a shape the parser does not know is a line of noise a
// human can dismiss, never an undetected defect.
//
// Findings, in two families.
//
// LIFECYCLE DEFECTS - the document was understood and it is wrong:
//   legacy-heading      a section titled with a legacy alias ("Completion
//                       criteria" / "Definition of done") instead of the
//                       canonical "Acceptance criteria"
//   plain-bullets       a recognized criteria section whose criteria are plain
//                       list items instead of task boxes, so no reader (human,
//                       agent, or GitHub) can tell resolved from unresolved
//   unresolved-on-done  a task whose registry status is "done" while criteria
//                       in its section are still unresolved: not checked, not
//                       waived, and not moved to a follow-up
//
// COMPREHENSION DEFECTS - the gate could not do its job and refuses to pretend
// otherwise:
//   no-files-matched          the gate is configured but its include pathspec
//                             matched zero tracked files. A renamed file or a
//                             config typo would otherwise disable the gate
//                             wholesale while it reported success.
//   unparsed-criteria-section a recognized criteria heading whose body yields
//                             zero recognized criterion items. A human wrote
//                             "Acceptance criteria" and the parser found
//                             nothing under it, so the parser is wrong, not the
//                             document. This one finding covers the empty
//                             section, the table form, the prose form, the
//                             indented list, and every list form nobody has
//                             invented yet.
//   unbound-criteria-section  a criteria section the parser could not attribute
//                             to a task id present in the registry, so the
//                             done-state rule cannot be applied to it.
//   unterminated-fence        a code fence still open at end of file, with the
//                             number of lines that were skipped as a result.
//   manifest-unreadable       the configured task registry is present but
//                             unusable: not valid JSON, or a "tasks" member
//                             that is not a plain object. Either way "done"
//                             cannot be resolved for any task.
//
// SEVERITY IS WARN BY DEFAULT. With findings the gate prints them and still
// exits 0, so adopting a newer aahp release can never turn a green repository
// red. Enforcement is opt-in per project: "strict": true makes findings fail
// the gate (exit 1). This mirrors the staged rollout the protocol asks for -
// warn first, enforce when the project has migrated.
//
//   "acceptanceCriteria": {
//     "include": [".ai/handoff/NEXT_ACTIONS.md"],
//     "manifest": ".ai/handoff/MANIFEST.json",
//     "strict": false
//   }
//
// The whole section is optional; absent, the gate is a clean no-op, and
// `aahp check` does not even list it (see bin/aahp.js OPTIONAL_CHECK_GATES).
//
// OFFLINE BY CONSTRUCTION. The gate reads tracked files and the manifest task
// registry only. It opens no socket, so a run is deterministic and complete
// without network access. Reconciling linked GitHub issues is an adapter
// concern documented in the README, never a precondition for a clean run.
//
// WHICH LIST FORMS COUNT AS CRITERIA:
//
//   - [ ] / - [x]   bullet task box            criterion, resolution readable
//   - plain          bullet list item          criterion, reported as plain
//   1. [ ] / 1. [x]  ordered task box          criterion, resolution readable
//   1. plain         ordered list item         criterion, reported as plain
//
// Nested items (indent >= 2) are detail lines belonging to the criterion above
// them, in either list form. Tables, definition lists and prose are not
// criteria. A section written that way now yields zero items and reports
// unparsed-criteria-section rather than passing clean.
//
// WHICH HEADING FORMS BIND A TASK ID. Task scope is opened by an ATX heading
// ("### T-007: ..."), a setext heading (a line underlined with "===" or "---"),
// or a bold label ("**T-007: ...**"). All three are supported rather than left
// to the comprehension defects, because all three appear in hand-written
// handoff files and a document written that way would otherwise report an
// unbound section on every task. Any form still unsupported is caught by
// unbound-criteria-section.
//
// FENCED CODE BLOCKS ARE NOT CONTENT. Lines inside a ``` or ~~~ fence are
// skipped, so documentation that SHOWS the criteria format is not mistaken for
// criteria that exist. Fence closing follows CommonMark: a closing fence
// indented by four or more spaces is content, not a fence, so the block
// legitimately runs to end of file. That behaviour is correct and is kept. What
// changes is that the consequence is no longer silent - an open fence at end of
// file is reported with the number of lines it swallowed.
//
// Recognized resolution markers on an unchecked criterion (case-insensitive):
//   (waived: rationale)      an accepted, justified exception
//   (follow-up: T-042)       moved to a linked follow-up task or issue
//
// Files are enumerated with `git ls-files` through the shared helper, so only
// tracked files are read and the gate fails loud outside a git work tree
// instead of vacuously passing on an empty file list.
//
// The module has no import-time side effects: the gate runs only when this file
// is the process entry point, so parseCriteriaSections and findSectionDefects
// can be imported and unit-tested without the gate exiting the test process.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resolveRoot, loadConfig, isInsideWorkTree, listTrackedFiles } from "./aahp-config.mjs";

const CANONICAL_HEADING = "Acceptance criteria";

// Canonical heading plus the legacy aliases readers must keep accepting.
const CRITERIA_HEADINGS = new Map([
  ["acceptance criteria", "canonical"],
  ["completion criteria", "legacy"],
  ["definition of done", "legacy"],
]);

const DEFAULT_INCLUDE = [".ai/handoff/NEXT_ACTIONS.md"];
const DEFAULT_MANIFEST = ".ai/handoff/MANIFEST.json";

// A criteria section opens on a Markdown heading ("## Acceptance criteria") or
// on a bold label ("**Acceptance criteria:**"), because handoff files use the
// label form and GitHub issues use the heading form. It closes on the next
// heading, the next bold label, a thematic break, or end of file.
const HEADING_RE = /^\s{0,3}(#{1,6})\s+(.+?)\s*$/;
const BOLD_LABEL_RE = /^\s{0,3}\*\*\s*([^*]+?)\s*\*\*\s*:?\s*$/;
const BOLD_START_RE = /^\s{0,3}\*\*/;
const BREAK_RE = /^\s{0,3}(-{3,}|={3,}|\*{3,})\s*$/;
// A setext underline: a run of "=" (level 1) or "-" (level 2) under a paragraph
// line. CommonMark resolves the "---" ambiguity in favour of the heading when
// the preceding line is paragraph content, which is what the lookahead below
// reproduces.
const SETEXT_UNDERLINE_RE = /^\s{0,3}(=+|-+)\s*$/;
// Bullet and ordered list items are both criteria. "- item", "* item",
// "+ item", "1. item", "2) item".
const LIST_RE = /^(\s*)(?:[-*+]|\d{1,9}[.)])\s+(.*)$/;
const BOX_RE = /^\[([ xX])\]\s*(.*)$/;
const TASK_ID_RE = /\bT-\d{3,}\b/;
// A fence opens with at least three backticks or tildes and closes with a run
// of the same character that is at least as long.
const FENCE_RE = /^(\s{0,3})(`{3,}|~{3,})(.*)$/;

const WAIVED_RE = /\((?:waived|waiver)\s*:\s*\S[^)]*\)/i;
const FOLLOWUP_RE = /\((?:follow-?up|moved)\s*:\s*\S[^)]*\)/i;

// A bold label deeper than any ATX heading level, so the first heading of any
// depth closes a task scope that a bold label opened.
const BOLD_LABEL_DEPTH = 7;

function normalizeLabel(text) {
  return String(text)
    .replace(/^[*\s]+|[*\s]+$/g, "")
    .replace(/\s*:\s*$/, "")
    .replace(/\s+/g, " ")
    .toLowerCase();
}

// True when `line` is a paragraph line that `next` underlines as a setext
// heading. Blank lines, list items, fences, ATX headings and thematic-break
// candidates are excluded so an existing "---" separator is not reinterpreted
// as a heading for the paragraph above it.
function setextLevel(line, next) {
  if (next === undefined) return 0;
  if (!SETEXT_UNDERLINE_RE.test(next)) return 0;
  if (line.trim() === "") return 0;
  if (/^\s{4,}/.test(line)) return 0;
  if (HEADING_RE.test(line) || LIST_RE.test(line) || FENCE_RE.test(line) || BREAK_RE.test(line)) return 0;
  return next.trim()[0] === "=" ? 1 : 2;
}

// Parse one Markdown file into the criteria sections it contains, plus the
// file-level defects found while reading it. Only top-level list items
// (indent < 2) are criteria; deeper items are detail lines belonging to the
// criterion above them.
export function parseCriteriaSections(rel, text) {
  const lines = String(text).split(/\r?\n/);
  const sections = [];
  const defects = [];
  let current = null;
  let currentTask = null;
  // Depth of the heading that opened the current task scope. Only a heading at
  // the same or a shallower depth closes it, so prose subsections between a
  // task heading and its criteria heading stay inside the task.
  let currentTaskDepth = 0;
  let fence = null; // { char, len, line }
  let fenceSkipped = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // --- fenced code blocks: never content -----------------------------
    const fenceMatch = line.match(FENCE_RE);
    if (fence) {
      fenceSkipped++;
      if (fenceMatch && fenceMatch[2][0] === fence.char && fenceMatch[2].length >= fence.len && fenceMatch[3].trim() === "") {
        fence = null;
      }
      continue;
    }
    if (fenceMatch) {
      // An info string may not contain a backtick when the fence is backticks.
      if (!(fenceMatch[2][0] === "`" && fenceMatch[3].includes("`"))) {
        fence = { char: fenceMatch[2][0], len: fenceMatch[2].length, line: i + 1 };
        fenceSkipped = 0;
        continue;
      }
    }

    // --- headings, in all three binding forms --------------------------
    const atxMatch = line.match(HEADING_RE);
    const setext = atxMatch ? 0 : setextLevel(line, lines[i + 1]);
    const labelMatch = atxMatch || setext ? null : line.match(BOLD_LABEL_RE);

    const headingText = atxMatch ? atxMatch[2] : setext ? line.trim() : null;
    const headingDepth = atxMatch ? atxMatch[1].length : setext;
    const rawLabel = headingText !== null ? headingText : labelMatch ? labelMatch[1] : null;
    const kind = rawLabel === null ? undefined : CRITERIA_HEADINGS.get(normalizeLabel(rawLabel));

    if (headingText !== null) {
      const id = headingText.match(TASK_ID_RE);
      // A heading that names a task opens that task's scope. Any OTHER heading
      // closes it only when it is a sibling or an ancestor (depth <= the task
      // heading's depth). A deeper heading is a subsection of the task, so
      // "## T-007" + "### Design notes" + "### Acceptance criteria" still binds
      // to T-007. Without the depth rule any prose subsection reset the scope
      // and unresolved-on-done could never fire for that task.
      if (id) {
        currentTask = id[0];
        currentTaskDepth = headingDepth;
      } else if (currentTask && headingDepth <= currentTaskDepth) {
        currentTask = null;
        currentTaskDepth = 0;
      }
    } else if (labelMatch && !kind) {
      // A bold label is how handoff files title a task inline. It binds only
      // when it names a task id; other labels are ordinary section labels.
      const id = labelMatch[1].match(TASK_ID_RE);
      if (id) {
        currentTask = id[0];
        currentTaskDepth = BOLD_LABEL_DEPTH;
      }
    }

    if (kind) {
      current = {
        file: rel,
        line: i + 1,
        heading: normalizeLabel(rawLabel),
        display: String(rawLabel).replace(/\s*:\s*$/, ""),
        kind,
        taskId: currentTask,
        items: [],
      };
      sections.push(current);
      if (setext) i++; // consume the underline
      continue;
    }

    if (setext) i++; // consume the underline

    if (!current) continue;

    if (headingText !== null || BOLD_START_RE.test(line) || BREAK_RE.test(line)) {
      current = null;
      continue;
    }

    const listMatch = line.match(LIST_RE);
    if (!listMatch) continue;
    if (listMatch[1].length >= 2) continue;

    const body = listMatch[2];
    const box = body.match(BOX_RE);
    if (box) {
      current.items.push({ line: i + 1, plain: false, checked: box[1].toLowerCase() === "x", text: box[2] });
    } else {
      current.items.push({ line: i + 1, plain: true, checked: false, text: body });
    }
  }

  // An open fence at end of file is CommonMark-correct (a closing fence
  // indented four or more spaces is content), but its consequence must not be
  // silent: everything after it was skipped and could contain criteria.
  if (fence) {
    defects.push({
      id: "unterminated-fence",
      line: fence.line,
      message: `code fence opened here is still open at end of file, so ${fenceSkipped} line(s) after it were skipped and any acceptance criteria among them were not checked; close the fence with an unindented "${fence.char.repeat(fence.len)}"`,
    });
  }

  return { sections, defects };
}

// Classify one parsed section. `taskStatus` is the registry map; `registryKnown`
// says whether that map is trustworthy, because binding cannot be judged
// against a registry that could not be read.
export function findSectionDefects(section, taskStatus, registryKnown = true) {
  const defects = [];
  const plain = section.items.filter((item) => item.plain);
  const boxes = section.items.filter((item) => !item.plain);

  if (section.kind === "legacy") {
    defects.push({
      id: "legacy-heading",
      line: section.line,
      message: `"${section.display}" is a legacy alias; rename it to "${CANONICAL_HEADING}" (readers still accept the alias)`,
    });
  }

  // Zero recognized items is the catch-all for every shape the parser cannot
  // read: an empty section, a table, prose, an indented list, or a list form
  // that does not exist yet. Reporting it is the whole point of the gate: a
  // human wrote the heading, so criteria were meant to be there.
  if (section.items.length === 0) {
    defects.push({
      id: "unparsed-criteria-section",
      line: section.line,
      message: `"${section.display}" contains no recognized criterion; acceptance criteria must be top-level task boxes ("- [ ] ..." or "1. [ ] ..."), and a section stating them as a table, as prose, as an indented list, or not at all cannot be verified`,
    });
  }

  if (plain.length > 0) {
    defects.push({
      id: "plain-bullets",
      line: plain[0].line,
      message: `${plain.length} plain list item(s) under "${section.display}"; acceptance criteria must be task boxes ("- [ ] ..." or "1. [ ] ...") so unresolved work stays visible`,
    });
  }

  if (!registryKnown) return defects;

  const status = section.taskId ? taskStatus.get(section.taskId) : undefined;

  // A section nobody can attribute to a registered task silently escapes the
  // done rule. Say so.
  if (status === undefined) {
    defects.push({
      id: "unbound-criteria-section",
      line: section.line,
      message: section.taskId
        ? `"${section.display}" binds to ${section.taskId}, which is not a key in the task registry, so its done-state cannot be checked; register the task under that id or correct the heading`
        : `"${section.display}" is not inside any task section, so its done-state cannot be checked; put it under a heading or bold label naming the task ("### T-042: ...")`,
    });
    return defects;
  }

  if (status === "done") {
    const unresolved = boxes.filter(
      (item) => !item.checked && !WAIVED_RE.test(item.text) && !FOLLOWUP_RE.test(item.text),
    );
    if (unresolved.length > 0) {
      defects.push({
        id: "unresolved-on-done",
        line: unresolved[0].line,
        message: `${section.taskId} is "done" but ${unresolved.length} criterion/criteria are unresolved; check with evidence, waive with "(waived: reason)", or move with "(follow-up: ref)"`,
      });
    }
  }

  return defects;
}

// Read the task registry so "done" is taken from the machine-readable source of
// truth (MANIFEST.json), not from prose.
//
// Three outcomes, deliberately distinguished, because collapsing the last two
// silently disables the unresolved-on-done rule while asserting the registry is
// missing:
//   absent   -> the rule genuinely does not apply, report that and move on
//   parsed   -> the rule applies
//   corrupt  -> a real error: the registry is there and unusable
//
// "Unusable" includes a `tasks` member that is not a plain object. An array
// passes `typeof x === "object"`, and treating it as a registry produced a
// reassuring task count from index keys while no task id could ever match.
export function loadTaskStatus(root, relPath) {
  const p = join(root, relPath);
  if (!existsSync(p)) return { statuses: new Map(), state: "absent", error: null };
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(p, "utf8"));
  } catch (err) {
    return { statuses: new Map(), state: "corrupt", error: `not valid JSON (${err.message})` };
  }
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    return { statuses: new Map(), state: "corrupt", error: "the top-level value is not a JSON object" };
  }
  const tasks = manifest.tasks;
  if (tasks !== undefined && (tasks === null || typeof tasks !== "object" || Array.isArray(tasks))) {
    return {
      statuses: new Map(),
      state: "corrupt",
      error: `"tasks" is ${Array.isArray(tasks) ? "an array" : tasks === null ? "null" : `a ${typeof tasks}`}, not an object keyed by task id`,
    };
  }
  const statuses = new Map();
  for (const [id, task] of Object.entries(tasks || {})) {
    if (task && typeof task === "object" && typeof task.status === "string") statuses.set(id, task.status);
  }
  return { statuses, state: "parsed", error: null };
}

// --- gate ------------------------------------------------------------------

function main() {
  const root = resolveRoot();

  let config;
  try {
    config = loadConfig(root);
  } catch (err) {
    console.error(`  acceptance-criteria: ${err.message}`);
    process.exit(1);
  }

  const section = config.acceptanceCriteria;
  if (!section || typeof section !== "object") {
    console.log("Acceptance criteria: not configured; nothing to check.");
    process.exit(0);
  }

  // Fail loud outside a git work tree: `git ls-files` would enumerate zero files
  // and the gate would vacuously pass, so a lifecycle defect could ship unseen.
  if (!isInsideWorkTree(root)) {
    console.error(
      `  acceptance-criteria: not inside a git work tree at ${root}; cannot enumerate files - run this gate inside a git checkout (in CI use actions/checkout)`,
    );
    process.exit(1);
  }

  const include = Array.isArray(section.include) && section.include.length ? section.include : DEFAULT_INCLUDE;
  const manifestPath = typeof section.manifest === "string" && section.manifest ? section.manifest : DEFAULT_MANIFEST;
  const strict = section.strict === true;
  const configFile = existsSync(join(root, "aahp.config.json")) ? "aahp.config.json" : "package.json";

  const { statuses, state: manifestState, error: manifestError } = loadTaskStatus(root, manifestPath);
  const registryKnown = manifestState === "parsed";

  const findings = [];
  let sectionCount = 0;
  let fileCount = 0;

  // A registry that exists but cannot be used is a finding in its own right,
  // not a silent skip. It is listed first because every done-state verdict below
  // it would be unreliable while it stands.
  if (manifestState === "corrupt") {
    findings.push({
      file: manifestPath,
      line: 1,
      id: "manifest-unreadable",
      message: `task registry is present but unusable: ${manifestError}; done-state checks cannot run until it is fixed`,
    });
  }

  const tracked = listTrackedFiles(root, include);

  for (const rel of tracked) {
    let text;
    try {
      text = readFileSync(join(root, rel), "utf8");
    } catch {
      continue;
    }
    fileCount++;
    const { sections, defects } = parseCriteriaSections(rel, text);
    for (const defect of defects) findings.push({ file: rel, ...defect });
    for (const parsed of sections) {
      sectionCount++;
      for (const defect of findSectionDefects(parsed, statuses, registryKnown)) {
        findings.push({ file: rel, ...defect });
      }
    }
  }

  // Configured but pointed at nothing. Without this the gate reports success on
  // a renamed file or a mistyped pathspec, which is the loudest possible way to
  // be quiet: the project believes it is covered and it is not.
  if (fileCount === 0) {
    findings.push({
      file: configFile,
      line: 1,
      id: "no-files-matched",
      message: `acceptanceCriteria.include matched zero tracked files (${include.join(", ")}); the gate is enabled but checking nothing - correct the pathspec, track the file, or remove the config section`,
    });
  }

  findings.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));

  const manifestNote =
    manifestState === "parsed"
      ? `${statuses.size} task(s) in ${manifestPath}`
      : manifestState === "corrupt"
        ? `${manifestPath} is present but unusable, so done-state checks could not run`
        : `no task registry at ${manifestPath}, so done-state checks were skipped`;

  if (findings.length === 0) {
    console.log(
      `Acceptance criteria OK: ${sectionCount} section(s) in ${fileCount} file(s), no findings (offline check; ${manifestNote}).`,
    );
    process.exit(0);
  }

  if (strict) {
    console.error(`\n  Acceptance-criteria check failed (${findings.length} finding(s), strict mode).\n`);
    for (const f of findings) console.error(`  - ${f.file}:${f.line} [${f.id}] ${f.message}`);
    console.error("");
    console.error(`  Lifecycle: one "${CANONICAL_HEADING}" section, "- [ ]" while unresolved, "- [x]" only on`);
    console.error("  evidence. Before a task is done, every criterion is checked, waived, or moved.");
    console.error("  A finding also fires when the gate cannot read the input: that is deliberate, because");
    console.error("  an unreadable document must never be reported as a clean one.\n");
    process.exit(1);
  }

  // Warn severity: report everything, change nothing about the exit code. The
  // leading "WARN " token is the contract `aahp check` reads to report this gate
  // as WARN rather than PASS.
  console.log(
    `WARN acceptance-criteria: ${findings.length} finding(s) in ${sectionCount} section(s) (advisory; set acceptanceCriteria.strict to enforce).`,
  );
  for (const f of findings) console.log(`  - ${f.file}:${f.line} [${f.id}] ${f.message}`);
  console.log(`  Offline check; ${manifestNote}.`);
  process.exit(0);
}

// Run only as the process entry point. Importing this module for its exported
// helpers must not run the gate, read the filesystem, or exit the process.
const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : null;
if (invokedPath && invokedPath === import.meta.url) main();
else if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
