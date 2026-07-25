#!/usr/bin/env node
// check-acceptance-criteria.mjs - Config-driven acceptance-criteria lifecycle
// gate. It reads the acceptance-criteria sections of the configured Markdown
// files and reports three lifecycle defects:
//
//   legacy-heading      a section titled with a legacy alias ("Completion
//                       criteria" / "Definition of done") instead of the
//                       canonical "Acceptance criteria"
//   plain-bullets       a recognized criteria section whose criteria are plain
//                       bullets instead of task boxes, so no reader (human,
//                       agent, or GitHub) can tell resolved from unresolved
//   unresolved-on-done  a task whose manifest status is "done" while criteria
//                       in its section are still unresolved: not checked, not
//                       waived, and not moved to a follow-up
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
// Recognized resolution markers on an unchecked criterion (case-insensitive):
//   (waived: rationale)      an accepted, justified exception
//   (follow-up: T-042)       moved to a linked follow-up task or issue
//
// Files are enumerated with `git ls-files` through the shared helper, so only
// tracked files are read and the gate fails loud outside a git work tree
// instead of vacuously passing on an empty file list.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
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
const LIST_RE = /^(\s*)[-*+]\s+(.*)$/;
const BOX_RE = /^\[([ xX])\]\s*(.*)$/;
const TASK_ID_RE = /\bT-\d{3,}\b/;

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

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const headingMatch = line.match(HEADING_RE);
    const labelMatch = headingMatch ? null : line.match(BOLD_LABEL_RE);
    const rawLabel = headingMatch ? headingMatch[2] : labelMatch ? labelMatch[1] : null;
    const kind = rawLabel === null ? undefined : CRITERIA_HEADINGS.get(normalizeLabel(rawLabel));

    if (headingMatch) {
      const id = headingMatch[2].match(TASK_ID_RE);
      // A heading that names a task opens that task's scope; any other heading
      // closes it. A criteria heading itself never closes the scope, so
      // "### T-007: title" + "#### Acceptance criteria" still binds to T-007.
      if (id) currentTask = id[0];
      else if (!kind) currentTask = null;
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
      message: `${plain.length} plain bullet(s) under "${section.display}"; acceptance criteria must be task boxes ("- [ ] ...") so unresolved work stays visible`,
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
// truth (MANIFEST.json), not from prose. Returns an empty map when there is no
// manifest, which disables only the unresolved-on-done rule.
function loadTaskStatus(root, relPath) {
  const p = join(root, relPath);
  if (!existsSync(p)) return { statuses: new Map(), present: false };
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(p, "utf8"));
  } catch {
    return { statuses: new Map(), present: false };
  }
  const statuses = new Map();
  const tasks = manifest && typeof manifest.tasks === "object" && manifest.tasks ? manifest.tasks : {};
  for (const [id, task] of Object.entries(tasks)) {
    if (task && typeof task === "object" && typeof task.status === "string") statuses.set(id, task.status);
  }
  return { statuses, present: true };
}

// --- gate ------------------------------------------------------------------

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

const { statuses, present: manifestPresent } = loadTaskStatus(root, manifestPath);

const findings = [];
let sectionCount = 0;
let fileCount = 0;

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

const manifestNote = manifestPresent
  ? `${statuses.size} task(s) in ${manifestPath}`
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
