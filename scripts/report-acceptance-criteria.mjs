#!/usr/bin/env node
// report-acceptance-criteria.mjs - ADVISORY acceptance-criteria lifecycle
// report. This is NOT a gate and it has no enforcing mode.
//
// WHY IT IS ADVISORY. Acceptance criteria live in hand-written Markdown, whose
// shapes are unbounded, so recognizing them is a heuristic and a heuristic
// cannot be sound. Three rounds of adversarial review against an enforcing
// version of this code each fixed real defects and each found new document
// shapes that still slipped through: ordered lists, indented lists, empty
// sections, setext headings, bold-label tasks, an indented closing fence, a
// bold line in the middle of a criteria section, and more. The pattern is not
// "five more shapes to fix"; it is that no fixed set of patterns closes the
// space.
//
// A gate's entire value is that green means safe. Tie an unsound heuristic to
// an exit code and a clean result manufactures false confidence: people stop
// reading the document because the build was green, which is worse than having
// no check at all. So the authority is removed and the detection is kept. The
// report prints what it found, for a human to read, and ALWAYS exits 0.
//
// There is deliberately no strict/enforce option. An option to make findings
// fail would be switched on somewhere, and then the first unanticipated
// document shape turns into a red build in a consumer repo. It is not
// configurable off-by-default; it does not exist.
//
// PUBLISHED BLIND SPOTS. An honest tool names what it misses. README Section
// 8.7 carries the authoritative list; the headline case is that a bold line
// inside a criteria section ends the section, so criteria written after it are
// invisible:
//
//   ### Acceptance criteria
//   - [x] done
//
//   **Note:** the rest follow.
//
//   - [ ] NOT SEEN
//
// The most reachable one is simpler still: the heading must match a recognized
// phrase EXACTLY after normalization, so "### Acceptance criteria for release"
// or "**Acceptance criteria:** (v2)" opens no section at all and everything
// under it is invisible.
//
// Do not read "no findings" as "the criteria are resolved".
//
// EXIT CODE. 0, always, whatever it finds. The only non-zero exit is the report
// failing to run at all: an unparseable aahp config, or no git work tree to
// enumerate tracked files from. Both are properties of the environment, never
// of a document's shape, so neither can be triggered by writing Markdown.
// Everything else that goes wrong while the report runs, including a pathspec
// git refuses and a manifest path that escapes the root, is a finding.
//
// WHAT IT REPORTS, in two families.
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
// COMPREHENSION DEFECTS - the report could not do its job and says so rather
// than falling silent. Silence is the failure mode that made an enforcing
// version untrustworthy, so anything unreadable is reported:
//   config-unusable           the acceptanceCriteria config, or one of its
//                             members, is not the shape it must be, so a
//                             default was used instead of what was written
//   include-unusable          git rejected the include pathspecs (an unknown
//                             pathspec magic word, a path outside the
//                             repository), so no file could be enumerated
//   no-files-matched          the include pathspecs matched zero tracked
//                             files, so the report covered nothing
//   file-unreadable           a tracked file matched but could not be read
//   manifest-missing          a task registry path was configured explicitly
//                             and does not exist, so no done-state check ran
//   manifest-outside-root     the configured task registry path resolves
//                             outside the project root, so it was not read
//                             and no done-state check ran
//   manifest-unreadable       the task registry is present but unusable: not
//                             valid JSON, or a "tasks" member that is not a
//                             plain object. Either way "done" cannot be
//                             resolved for any task.
//   unparsed-criteria-section a recognized criteria heading whose body yields
//                             zero recognized criterion items: an empty
//                             section, a table, prose, an indented list, or a
//                             list form nobody has invented yet
//   unbound-criteria-section  a criteria section that could not be attributed
//                             to a task id present in the registry, so the
//                             done-state rule cannot be applied to it
//   unterminated-fence        a code fence still open at end of file, with the
//                             number of lines that were skipped as a result
//
// Configuration is optional. Absent, the defaults below are used, because the
// report only runs when a human asked for it by name.
//
//   "acceptanceCriteria": {
//     "include": [".ai/handoff/NEXT_ACTIONS.md"],
//     "manifest": ".ai/handoff/MANIFEST.json"
//   }
//
// OFFLINE BY CONSTRUCTION. It reads tracked files and the manifest task
// registry only. It opens no socket, so a run is deterministic and complete
// without network access. Reconciling linked GitHub issues is an adapter
// concern documented in the README.
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
// criteria. A section written that way yields zero items and is reported as
// unparsed-criteria-section.
//
// WHICH HEADING FORMS BIND A TASK ID. Task scope is opened by an ATX heading
// ("### T-007: ..."), a setext heading (a line underlined with "===" or "---"),
// or a bold label ("**T-007: ...**"), because all three appear in hand-written
// handoff files. Any form not supported is reported as unbound.
//
// FENCED CODE BLOCKS ARE NOT CONTENT. Lines inside a ``` or ~~~ fence are
// skipped, so documentation that SHOWS the criteria format is not mistaken for
// criteria that exist. Fence closing follows CommonMark: a closing fence
// indented by four or more spaces is content, not a fence, so the block
// legitimately runs to end of file. An open fence at end of file is reported
// with the number of lines it swallowed.
//
// Recognized resolution markers on an unchecked criterion (case-insensitive):
//   (waived: rationale)      an accepted, justified exception
//   (follow-up: T-042)       moved to a linked follow-up task or issue
//
// Files are enumerated with `git ls-files` through the shared helper, so only
// tracked files are read.
//
// The module has no import-time side effects: the report runs only when this
// file is the process entry point, so parseCriteriaSections and
// findSectionDefects can be imported and unit-tested without it exiting the
// test process.

import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
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
  // that does not exist yet. Reporting it is the whole point of this report: a
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

// True when `relPath` resolves inside `root`. The manifest path comes from
// configuration and is joined to the repository root, so without this a value
// containing ".." (or an absolute path) reads a task registry from outside the
// work tree entirely.
export function isInsideRoot(root, relPath) {
  const base = resolve(root);
  const target = resolve(base, relPath);
  const rel = relative(base, target);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

// Read the task registry so "done" is taken from the machine-readable source of
// truth (MANIFEST.json), not from prose.
//
// Four outcomes, deliberately distinguished, because collapsing them silently
// disables the unresolved-on-done rule while asserting the registry is missing:
//   absent   -> the rule genuinely does not apply, report that and move on
//   parsed   -> the rule applies
//   corrupt  -> a real error: the registry is there and unusable
//   escaped  -> the configured path leaves the work tree, so it is not read
//
// "Unusable" includes a `tasks` member that is not a plain object. An array
// passes `typeof x === "object"`, and treating it as a registry produced a
// reassuring task count from index keys while no task id could ever match.
export function loadTaskStatus(root, relPath) {
  // Containment first: a path that escapes the root is never opened, so this
  // report cannot be pointed at a file outside the repository it was run in.
  if (!isInsideRoot(root, relPath)) {
    return { statuses: new Map(), state: "escaped", error: "resolves outside the project root" };
  }
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

// --- report ----------------------------------------------------------------

// The human-readable half of a failed `git ls-files`. execFileSync builds a
// message that repeats the whole command line, including the absolute root
// path; git's own first stderr line ("fatal: ...") is what a reader needs.
function gitReason(err) {
  const stderr = String(err && err.stderr ? err.stderr : "");
  const line = stderr.split(/\r?\n/).find((l) => l.trim() !== "");
  if (line) return line.trim();
  return String((err && err.message) || "unknown error").split(/\r?\n/)[0].trim();
}

function main() {
  const root = resolveRoot();

  let config;
  try {
    config = loadConfig(root);
  } catch (err) {
    console.error(`  acceptance-criteria report: ${err.message}`);
    process.exit(1);
  }

  // One of the report's only two non-zero exits. Outside a git work tree
  // `git ls-files` enumerates nothing and the report would be empty for a
  // reason that has nothing to do with the documents.
  if (!isInsideWorkTree(root)) {
    console.error(
      `  acceptance-criteria report: not inside a git work tree at ${root}; cannot enumerate files - run this report inside a git checkout (in CI use actions/checkout)`,
    );
    process.exit(1);
  }

  const configFile = existsSync(join(root, "aahp.config.json")) ? "aahp.config.json" : "package.json";
  const findings = [];

  // Configuration is optional, but a value of the WRONG SHAPE must not be
  // indistinguishable from no value at all. Each fallback below is reported,
  // because silently using a default while the project believes its own
  // setting is in force is exactly the kind of quiet this report exists to
  // avoid.
  const raw = config.acceptanceCriteria;
  const sectionUsable = !!raw && typeof raw === "object" && !Array.isArray(raw);
  const section = sectionUsable ? raw : {};
  if (raw !== undefined && !sectionUsable) {
    findings.push({
      file: configFile,
      line: 1,
      id: "config-unusable",
      message: `"acceptanceCriteria" is ${Array.isArray(raw) ? "an array" : raw === null ? "null" : `a ${typeof raw}`}, not an object, so the report used its defaults instead of what is configured`,
    });
  }

  const includeRaw = section.include;
  const includeUsable =
    Array.isArray(includeRaw) && includeRaw.length > 0 && includeRaw.every((p) => typeof p === "string" && p.trim() !== "");
  const include = includeUsable ? includeRaw : DEFAULT_INCLUDE;
  if (includeRaw !== undefined && !includeUsable) {
    findings.push({
      file: configFile,
      line: 1,
      id: "config-unusable",
      message: `"acceptanceCriteria.include" is not a non-empty array of pathspec strings, so the report scanned the default (${DEFAULT_INCLUDE.join(", ")}) instead`,
    });
  }

  const manifestRaw = section.manifest;
  const manifestConfigured = typeof manifestRaw === "string" && manifestRaw.trim() !== "";
  const manifestPath = manifestConfigured ? manifestRaw : DEFAULT_MANIFEST;
  if (manifestRaw !== undefined && !manifestConfigured) {
    findings.push({
      file: configFile,
      line: 1,
      id: "config-unusable",
      message: `"acceptanceCriteria.manifest" is not a non-empty string, so the report read the default (${DEFAULT_MANIFEST}) instead`,
    });
  }

  const { statuses, state: manifestState, error: manifestError } = loadTaskStatus(root, manifestPath);
  const registryKnown = manifestState === "parsed";

  let sectionCount = 0;
  let fileCount = 0;

  // A registry that exists but cannot be used is a finding in its own right,
  // not a silent skip. Every done-state verdict below it would be unreliable.
  if (manifestState === "corrupt") {
    findings.push({
      file: manifestPath,
      line: 1,
      id: "manifest-unreadable",
      message: `task registry is present but unusable: ${manifestError}; no done-state check could run`,
    });
  }

  // An ABSENT registry at the default path means the done-state rule genuinely
  // does not apply here. An absent registry at a path the project wrote down
  // itself is a typo or a rename, and it disables the done-state rule
  // completely, so it is reported.
  if (manifestState === "absent" && manifestConfigured) {
    findings.push({
      file: manifestPath,
      line: 1,
      id: "manifest-missing",
      message: `the configured task registry does not exist, so no done-state check ran at all; correct acceptanceCriteria.manifest or drop it to accept the default (${DEFAULT_MANIFEST})`,
    });
  }

  // A configured path that leaves the work tree is not read at all. Reading it
  // would let a config value pull a task registry in from anywhere on the
  // machine, and staying silent about it would disable the done-state rule
  // while the project believes its setting is in force.
  if (manifestState === "escaped") {
    findings.push({
      file: configFile,
      line: 1,
      id: "manifest-outside-root",
      message: `"acceptanceCriteria.manifest" (${manifestPath}) ${manifestError}, so it was not read and no done-state check ran; the task registry must live inside the work tree`,
    });
  }

  // The one call in this function that hands input to git. A pathspec can be a
  // perfectly well-formed string and still be rejected (an unknown pathspec
  // magic word, a path outside the repository), and an unguarded throw here
  // would break the always-exits-0 promise with a stack trace. A rejected
  // pathspec is a configuration problem for a human to read, so it is a
  // finding like every other input this report cannot use.
  let tracked = [];
  let enumerationFailed = false;
  try {
    tracked = listTrackedFiles(root, include);
  } catch (err) {
    enumerationFailed = true;
    findings.push({
      file: configFile,
      line: 1,
      id: "include-unusable",
      message: `git rejected the include pathspecs (${include.join(", ")}), so no file could be enumerated and this report covered nothing: ${gitReason(err)}`,
    });
  }

  for (const rel of tracked) {
    let text;
    try {
      text = readFileSync(join(root, rel), "utf8");
    } catch (err) {
      // Skipping a file in silence would shrink the report without saying so.
      findings.push({
        file: rel,
        line: 1,
        id: "file-unreadable",
        message: `tracked file matched the include pathspecs but could not be read (${err.message}), so nothing in it was reported on`,
      });
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

  // Pointed at nothing. Without this the report says "no findings" on a renamed
  // file or a mistyped pathspec, which is the loudest possible way to be quiet.
  // Suppressed when enumeration itself failed: include-unusable already said
  // so, and "matched zero tracked files" would misdescribe what happened.
  if (fileCount === 0 && !enumerationFailed) {
    findings.push({
      file: configFile,
      line: 1,
      id: "no-files-matched",
      message: `the include pathspecs matched zero tracked files (${include.join(", ")}), so this report covered nothing - correct acceptanceCriteria.include or track the documents`,
    });
  }

  findings.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));

  const manifestNote =
    manifestState === "parsed"
      ? `${statuses.size} task(s) in ${manifestPath}`
      : manifestState === "corrupt"
        ? `${manifestPath} is present but unusable, so done-state checks could not run`
        : manifestState === "escaped"
          ? `${manifestPath} resolves outside the project root, so done-state checks could not run`
          : `no task registry at ${manifestPath}, so done-state checks were skipped`;

  if (findings.length === 0) {
    console.log(
      `Acceptance criteria: no findings in ${sectionCount} section(s) across ${fileCount} file(s) (offline report; ${manifestNote}).`,
    );
  } else {
    console.log(
      `Acceptance criteria: ${findings.length} finding(s) in ${sectionCount} section(s) across ${fileCount} file(s) (offline report; ${manifestNote}).`,
    );
    for (const f of findings) console.log(`  - ${f.file}:${f.line} [${f.id}] ${f.message}`);
    console.log("");
    console.log(`  Lifecycle: one "${CANONICAL_HEADING}" section, "- [ ]" while unresolved, "- [x]" only on`);
    console.log("  evidence. Before a task is done, every criterion is checked, waived, or moved.");
  }

  // The same closing note in both cases, because the clean case is the one
  // that misleads. This report is a heuristic over hand-written Markdown with
  // published blind spots; it must never be read as a proof or used as a gate.
  console.log("");
  console.log("  ADVISORY: this report is best effort and always exits 0. No findings is NOT proof");
  console.log("  that the acceptance criteria are resolved, and this must not be used as a merge");
  console.log("  gate. Known blind spots are listed by name in README Section 8.7.");
  process.exit(0);
}

// Run only as the process entry point. Importing this module for its exported
// helpers must not run the report, read the filesystem, or exit the process.
const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : null;
if (invokedPath && invokedPath === import.meta.url) main();
else if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
