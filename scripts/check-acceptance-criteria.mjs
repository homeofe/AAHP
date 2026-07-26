#!/usr/bin/env node
// check-acceptance-criteria.mjs - Config-driven acceptance-criteria lifecycle
// gate. It reads the acceptance-criteria sections of the configured Markdown
// files and reports four lifecycle defects:
//
//   legacy-heading      a section titled with a legacy alias ("Completion
//                       criteria" / "Definition of done") instead of the
//                       canonical "Acceptance criteria"
//   plain-bullets       a recognized criteria section whose criteria are plain
//                       list items instead of task boxes, so no reader (human,
//                       agent, or GitHub) can tell resolved from unresolved
//   unresolved-on-done  a task whose manifest status is "done" while criteria
//                       in its section are still unresolved: not checked, not
//                       waived, and not moved to a follow-up
//   manifest-unreadable the configured task registry exists but is not valid
//                       JSON, so "done" cannot be resolved for any task
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
// WHICH LIST FORMS COUNT AS CRITERIA (a deliberate decision, not an accident):
//
//   - [ ] / - [x]   bullet task box            criterion, resolution readable
//   - plain          bullet list item          criterion, reported as plain
//   1. [ ] / 1. [x]  ordered task box          criterion, resolution readable
//   1. plain         ordered list item         criterion, reported as plain
//
// Ordered items count because "1." is the form a human reaches for when the
// criteria are a sequence, and a rule that cannot see them lets a `done` task
// with unresolved numbered criteria pass completely clean. A gate that silently
// under-reports is worse than no gate, so both list forms are criteria.
//
// Nested items (indent >= 2) are detail lines belonging to the criterion above
// them, in either list form. Definition lists, tables, and prose lines are not
// criteria: a section that states its criteria that way reports zero items,
// which is visible in the section/finding counts rather than silently clean.
//
// FENCED CODE BLOCKS ARE NOT CONTENT. Lines inside a ``` or ~~~ fence are
// skipped entirely, so documentation that SHOWS the criteria format is not
// mistaken for criteria that exist. Without this the gate fires hardest on the
// projects that document the convention properly.
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

function normalizeLabel(text) {
  return String(text)
    .replace(/^[*\s]+|[*\s]+$/g, "")
    .replace(/\s*:\s*$/, "")
    .replace(/\s+/g, " ")
    .toLowerCase();
}

// Parse one Markdown file into the criteria sections it contains. Only
// top-level list items (indent < 2) are criteria; deeper items are treated as
// detail lines belonging to the criterion above them.
export function parseCriteriaSections(rel, text) {
  const lines = String(text).split(/\r?\n/);
  const sections = [];
  let current = null;
  let currentTask = null;
  // Depth of the heading that opened the current task scope. Only a heading at
  // the same or a shallower depth closes it, so prose subsections between a
  // task heading and its criteria heading stay inside the task.
  let currentTaskDepth = 0;
  let fence = null; // { char: "`" | "~", len: number }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // --- fenced code blocks: never content -----------------------------
    const fenceMatch = line.match(FENCE_RE);
    if (fence) {
      if (fenceMatch && fenceMatch[2][0] === fence.char && fenceMatch[2].length >= fence.len && fenceMatch[3].trim() === "") {
        fence = null;
      }
      continue;
    }
    if (fenceMatch) {
      // An info string may not contain a backtick when the fence is backticks.
      if (!(fenceMatch[2][0] === "`" && fenceMatch[3].includes("`"))) {
        fence = { char: fenceMatch[2][0], len: fenceMatch[2].length };
        continue;
      }
    }

    const headingMatch = line.match(HEADING_RE);
    const labelMatch = headingMatch ? null : line.match(BOLD_LABEL_RE);
    const rawLabel = headingMatch ? headingMatch[2] : labelMatch ? labelMatch[1] : null;
    const kind = rawLabel === null ? undefined : CRITERIA_HEADINGS.get(normalizeLabel(rawLabel));

    if (headingMatch) {
      const depth = headingMatch[1].length;
      const id = headingMatch[2].match(TASK_ID_RE);
      // A heading that names a task opens that task's scope. Any OTHER heading
      // closes it only when it is a sibling or an ancestor (depth <= the task
      // heading's depth). A deeper heading is a subsection of the task, so
      // "## T-007" + "### Design notes" + "### Acceptance criteria" still binds
      // to T-007. Without the depth rule any prose subsection reset the scope
      // and unresolved-on-done could never fire for that task.
      if (id) {
        currentTask = id[0];
        currentTaskDepth = depth;
      } else if (currentTask && depth <= currentTaskDepth) {
        currentTask = null;
        currentTaskDepth = 0;
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
      continue;
    }

    if (!current) continue;

    if (headingMatch || BOLD_START_RE.test(line) || BREAK_RE.test(line)) {
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

  return sections;
}

// Classify one parsed section. Exported so the lifecycle rules have one
// implementation that both the gate and any future fixer share.
export function findSectionDefects(section, taskStatus) {
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

  if (plain.length > 0) {
    defects.push({
      id: "plain-bullets",
      line: plain[0].line,
      message: `${plain.length} plain list item(s) under "${section.display}"; acceptance criteria must be task boxes ("- [ ] ..." or "1. [ ] ...") so unresolved work stays visible`,
    });
  }

  const status = section.taskId ? taskStatus.get(section.taskId) : undefined;
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
//   corrupt  -> a real error: the registry is there and unreadable
export function loadTaskStatus(root, relPath) {
  const p = join(root, relPath);
  if (!existsSync(p)) return { statuses: new Map(), state: "absent", error: null };
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(p, "utf8"));
  } catch (err) {
    return { statuses: new Map(), state: "corrupt", error: err.message };
  }
  const statuses = new Map();
  const tasks = manifest && typeof manifest.tasks === "object" && manifest.tasks ? manifest.tasks : {};
  for (const [id, task] of Object.entries(tasks)) {
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

  const { statuses, state: manifestState, error: manifestError } = loadTaskStatus(root, manifestPath);

  const findings = [];
  let sectionCount = 0;
  let fileCount = 0;

  // A registry that exists but cannot be parsed is a finding in its own right,
  // not a silent skip. It is listed first because every unresolved-on-done
  // verdict below it is unreliable while it stands.
  if (manifestState === "corrupt") {
    findings.push({
      file: manifestPath,
      line: 1,
      id: "manifest-unreadable",
      message: `task registry is present but not valid JSON (${manifestError}); done-state checks cannot run until it parses`,
    });
  }

  for (const rel of listTrackedFiles(root, include)) {
    let text;
    try {
      text = readFileSync(join(root, rel), "utf8");
    } catch {
      continue;
    }
    fileCount++;
    for (const parsed of parseCriteriaSections(rel, text)) {
      sectionCount++;
      for (const defect of findSectionDefects(parsed, statuses)) {
        findings.push({ file: rel, ...defect });
      }
    }
  }

  findings.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));

  const manifestNote =
    manifestState === "parsed"
      ? `${statuses.size} task(s) in ${manifestPath}`
      : manifestState === "corrupt"
        ? `${manifestPath} is present but unparseable, so done-state checks could not run`
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
    console.error("  evidence. Before a task is done, every criterion is checked, waived, or moved.\n");
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
