#!/usr/bin/env node
// check-adr-refs.mjs - the Architectural Decision Log in docs/adr/ is consistent,
// and every ADR number cited anywhere in the repository names a decision that exists.
//
// WHAT IT ASSERTS
//   1. Every tracked docs/adr/ADR-NNN.md starts with the heading `# ADR-NNN: <title>`,
//      with the same NNN as its file name and a non-empty title.
//   2. docs/adr/README.md (the index) lists every ADR file exactly once, as a table row
//      `| [ADR-NNN](ADR-NNN.md) | <title> |` whose title equals the file's heading,
//      and lists nothing that has no file.
//   3. Every `ADR-NNN` token in a tracked text file names an ADR that has a file.
//
// WHAT IT DOES NOT ASSERT, stated so a green run is not over-read: that a citation
// names the RIGHT decision. When two decisions were renumbered in the 3.11.0 cycle,
// references kept citing the old numbers, and every one of them still resolved to an
// existing ADR about something else. Deciding whether "ADR-021" in a sentence about
// provenance is the right number needs a reader; a keyword heuristic over prose would
// be a gate that cannot be sound (ADR-017). Numbers are never reused or renumbered
// (docs/adr/README.md), which is what keeps that class from recurring.
//
// Repository-local, like check-doc-shape.mjs: it is in the `check` npm-script chain
// and deliberately NOT in CHECK_GATES, so no consumer inherits it. Config-free.
//
// Usage: node scripts/check-adr-refs.mjs [root]
// Exit:  0 consistent, 1 at least one finding, 2 could not assess (not a git work
//        tree, no ADR file tracked, no index, an unreadable file).

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, isInsideWorkTree, listTrackedFiles } from "./aahp-config.mjs";

const EXIT_OK = 0;
const EXIT_FINDING = 1;
const EXIT_UNASSESSED = 2;

const root = resolveRoot();
const ADR_DIR = "docs/adr";
const INDEX = `${ADR_DIR}/README.md`;
const FILE_RE = /^docs\/adr\/(ADR-\d{3})\.md$/;
const HEADING_RE = /^# (ADR-\d{3}): (.*\S)\s*$/;
const ROW_RE = /^\|\s*\[(ADR-\d{3})\]\(([^)]+)\)\s*\|\s*(.*?)\s*\|\s*$/;
const REF_RE = /\bADR-(\d{3})\b/g;
// Text files worth scanning for citations. Anything else git tracks (images, the
// lockfile's integrity blobs) cannot carry a meaningful citation.
const TEXT_SPECS = [
  "*.md", "*.mjs", "*.js", "*.json", "*.sh", "*.bash", "*.bats", "*.yml", "*.yaml",
  "*.txt", "*.py", "scripts/hooks/*",
];

function unassessed(msg) {
  console.error(`  adr-refs: ${msg}`);
  process.exit(EXIT_UNASSESSED);
}

if (!isInsideWorkTree(root)) {
  unassessed(`not inside a git work tree at ${root}; cannot enumerate tracked files`);
}

function read(rel) {
  try {
    return readFileSync(join(root, rel), "utf8");
  } catch (err) {
    unassessed(`${rel} is tracked but could not be read (${err.code || err.message})`);
  }
  return "";
}

const findings = [];
const adrFiles = listTrackedFiles(root, [`${ADR_DIR}/ADR-*.md`]).filter((f) => FILE_RE.test(f));
if (adrFiles.length === 0) unassessed(`no ${ADR_DIR}/ADR-NNN.md file is tracked; there is no log to check against`);
if (listTrackedFiles(root, [INDEX]).length === 0) unassessed(`${INDEX} (the index) is not tracked`);

// --- 1. file name and heading agree -----------------------------------------
const titles = new Map();
for (const f of adrFiles) {
  const id = f.match(FILE_RE)[1];
  const first = read(f).split(/\r?\n/).find((l) => l.trim() !== "") || "";
  const m = first.match(HEADING_RE);
  if (!m) {
    findings.push(`${f}: the first line must be '# ${id}: <title>', found ${JSON.stringify(first.slice(0, 80))}.`);
    continue;
  }
  if (m[1] !== id) {
    findings.push(`${f}: the heading says ${m[1]} but the file is ${id}. An ADR is never renumbered.`);
    continue;
  }
  titles.set(id, m[2]);
}

// --- 2. the index lists every ADR once, with the file's title ----------------
const listed = new Map();
for (const [n, line] of read(INDEX).split(/\r?\n/).entries()) {
  const m = line.match(ROW_RE);
  if (!m) continue;
  const [, id, target, title] = m;
  if (listed.has(id)) {
    findings.push(`${INDEX}:${n + 1}: ${id} is listed twice.`);
    continue;
  }
  listed.set(id, true);
  if (target !== `${id}.md`) findings.push(`${INDEX}:${n + 1}: ${id} links to ${target}, not ${id}.md.`);
  if (!titles.has(id) && !adrFiles.includes(`${ADR_DIR}/${id}.md`)) {
    findings.push(`${INDEX}:${n + 1}: ${id} is listed but ${ADR_DIR}/${id}.md is not tracked.`);
  } else if (titles.has(id) && titles.get(id) !== title) {
    findings.push(
      `${INDEX}:${n + 1}: ${id} is titled ${JSON.stringify(title)} here and ` +
        `${JSON.stringify(titles.get(id))} in its file. Keep the two identical.`,
    );
  }
}
for (const f of adrFiles) {
  const id = f.match(FILE_RE)[1];
  if (!listed.has(id)) findings.push(`${INDEX}: ${id} has a file (${f}) but no row in the index.`);
}

// --- 3. every cited number exists --------------------------------------------
const known = new Set(adrFiles.map((f) => f.match(FILE_RE)[1]));
let citations = 0;
for (const rel of listTrackedFiles(root, TEXT_SPECS)) {
  const lines = read(rel).split(/\r?\n/);
  lines.forEach((line, i) => {
    for (const m of line.matchAll(REF_RE)) {
      citations += 1;
      const id = `ADR-${m[1]}`;
      if (!known.has(id)) {
        findings.push(`${rel}:${i + 1}: cites ${id}, which has no ${ADR_DIR}/${id}.md.`);
      }
    }
  });
}

if (findings.length > 0) {
  console.error(`\n  ADR reference check failed: ${findings.length} finding(s).\n`);
  for (const f of findings) console.error(`  - ${f}`);
  console.error("");
  process.exit(EXIT_FINDING);
}

console.log(
  `ADR references OK: ${adrFiles.length} ADR file(s) match their headings and the index; ` +
    `${citations} citation(s) resolve. Not asserted: that each citation names the right decision.`,
);
process.exit(EXIT_OK);
