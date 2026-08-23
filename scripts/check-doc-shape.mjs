#!/usr/bin/env node
// check-doc-shape.mjs - two assertions about the documents an adopter lands on:
// a repo-relative path this repository tells you to use resolves against this
// repository, and the setup heading a newcomer needs is present and comes before
// the rationale material. Config-driven under "docPaths"; a clean no-op when the
// key is absent.
//
// WHY THIS GATE EXISTS
// ---------------------------------------------------------------------------
// check-doc-links.mjs resolves Markdown links of the form [text](target) and
// nothing else. Every other path in this README is an inline code span in prose,
// which that gate structurally cannot see. So README.md told adopters to copy
// `.github/workflows/aahp-govern.yml`, a file that does not exist in this
// repository and is not in the published package - the file is at
// `assets/governance/aahp-govern.yml` - and every gate stayed green. Measured
// across the nine consumer checkouts in this estate: 9 of 9 carry
// .github/workflows/aahp-verify.yml, so the neighbouring copy instruction was
// right, and 0 of 9 carry an aahp-govern.yml at all. Reported at
// https://github.com/homeofe/AAHP/issues/74. See ADR-022.
//
// WHY THIS IS NOT A BLANKET RULE OVER EVERY BACKTICKED SPAN
// ---------------------------------------------------------------------------
// Measured on README.md before this gate was written: 78 distinct path-shaped
// backticked spans, 46 of which do not resolve against this tree. Almost all of
// those 46 are correct: they name a file in an ADOPTER's repository
// (`.claude/CLAUDE.md`, `packages/api/.ai/handoff/`), a bare handoff filename
// (`STATUS.md`), a glob (`scripts/*.sh`), or a slash command (`/handoff`). A gate
// that failed on all of them would be switched off within a day.
//
// Two filters narrow it to the class where being wrong is a defect:
//
//   1. The first path segment must be a tracked top-level entry of THIS
//      repository. `packages/...` and `.claude/...` are therefore never
//      considered, and neither is anything without a slash in it.
//   2. Anything left over that is intentionally an adopter-tree path is declared
//      in docPaths.adopterPaths with a reason and an exact occurrence COUNT, and
//      reviewed as a code change.
//
// THE COUNT IS THE POINT, and it is why a bare allowlist was rejected. The
// defect this gate exists for and the correct uses of the same string are the
// SAME STRING in different sentences: `.github/workflows/aahp-govern.yml` is
// right where the README describes what `aahp init --gates` writes into YOUR
// repository, and wrong where it says "copy this from here". A path-level
// allowlist would have exempted both, so declaring the path would have made this
// gate unable to fail on the very defect it was written for. Pinning the number
// of occurrences instead means a NEW mention - which is what re-introducing the
// defect looks like - moves the count and turns the gate red, and the editor
// meets the recorded reason in the same diff. A count that no longer matches in
// EITHER direction is a finding: an entry matching nothing protects nothing, and
// an entry matching more than it recorded has stopped being reviewed. The
// declared entries are printed on every run as NOT ASSESSED, so "we chose not to
// resolve this one" never reads as "we resolved it".
//
// This is a CHANGE DETECTOR over a small reviewed list, not a rule that
// understands prose. ADR-017 is why it is not the latter.
//
//   "docPaths": {
//     "include": ["README.md"],
//     "adopterPaths": [ { "path": ".claude/CLAUDE.md", "occurrences": 2, "reason": "..." } ],
//     "requiredHeadings": [
//       { "id": "setup", "file": "README.md",
//         "pattern": "^#{1,3} .*(Install|Quickstart)",
//         "before": "^## 7\\. Architectural Decision Log" }
//     ]
//   }
//
// EXIT CODES
//   0  every assertion held
//   1  at least one finding
//   2  could not assess (not a git work tree, no document enumerated, a
//      configured file that cannot be read, an invalid configured pattern)
//
// Exit 2 exists so that "I could not look" is never reported as "I looked and it
// was fine". A caller that treats non-zero as failure loses nothing; a caller
// that wants to tell the two apart can.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadConfig, isInsideWorkTree, listTrackedFiles } from "./aahp-config.mjs";

const EXIT_OK = 0;
const EXIT_FINDING = 1;
const EXIT_UNASSESSED = 2;

const root = resolveRoot();

let config;
try {
  config = loadConfig(root);
} catch (err) {
  console.error(`  doc-shape: ${err.message}`);
  process.exit(EXIT_UNASSESSED);
}

if (!config.docPaths) {
  console.log("Doc shape: not configured; nothing to check.");
  process.exit(EXIT_OK);
}

if (!isInsideWorkTree(root)) {
  console.error(
    `  doc-shape: not inside a git work tree at ${root}; cannot enumerate files - ` +
      "run this gate inside a git checkout (in CI use actions/checkout)",
  );
  process.exit(EXIT_UNASSESSED);
}

const DEFAULT_INCLUDE = ["README.md", "CLAUDE.md", "CONTRIBUTING.md"];
const cfg = config.docPaths;
const include = Array.isArray(cfg.include) && cfg.include.length ? cfg.include : DEFAULT_INCLUDE;
const adopterPaths = Array.isArray(cfg.adopterPaths) ? cfg.adopterPaths : [];
const requiredHeadings = Array.isArray(cfg.requiredHeadings) ? cfg.requiredHeadings : [];

const findings = [];
const unassessed = [];

// --- the index this gate resolves against -----------------------------------
// git ls-files, not the filesystem: node_modules/ and .git/ are then not paths
// this repository "has", which is the right answer for a document telling a
// reader what is in the repository, and it makes the verdict independent of
// whether anyone has run npm ci.
const trackedFiles = new Set(listTrackedFiles(root, []));
const trackedDirs = new Set();
for (const f of trackedFiles) {
  const parts = f.split("/");
  for (let i = 1; i < parts.length; i += 1) trackedDirs.add(parts.slice(0, i).join("/"));
}
const trackedTopLevel = new Set();
for (const f of trackedFiles) trackedTopLevel.add(f.split("/")[0]);

if (trackedFiles.size === 0) {
  console.error(`  doc-shape: git ls-files enumerated nothing under ${root}; there is no index to resolve against.`);
  process.exit(EXIT_UNASSESSED);
}

const docs = listTrackedFiles(root, include);
if (docs.length === 0) {
  console.error(
    `  doc-shape: docPaths.include matched no tracked file (${include.join(", ")}). ` +
      "A gate that scanned no document must not report clean.",
  );
  process.exit(EXIT_UNASSESSED);
}

/** Read a tracked document, or record why it could not be read. */
function readDoc(rel) {
  try {
    return readFileSync(join(root, rel), "utf8");
  } catch (err) {
    unassessed.push(`${rel} is tracked but could not be read (${err.code || err.message}).`);
    return null;
  }
}

/** Lines outside fenced code blocks, as [lineNumber, text] pairs. */
function proseLines(text) {
  const out = [];
  let inFence = false;
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    if (/^\s*(```|~~~)/.test(lines[i])) {
      inFence = !inFence;
      continue;
    }
    if (!inFence) out.push([i + 1, lines[i]]);
  }
  return out;
}

/**
 * Normalise a backticked span into a repo-relative path this gate is willing to
 * resolve, or null when the span is out of scope. Out of scope is the common
 * case and is deliberately silent: see the header for the measurement.
 */
function candidatePath(raw) {
  const span = raw.trim();
  if (!span.includes("/")) return null;              // bare filenames name no location
  if (/\s/.test(span)) return null;                  // a phrase, not a path
  if (/^[a-z0-9+.-]+:\/\//i.test(span)) return null; // URL
  if (/^(?:\/\/|[-$@<])/.test(span)) return null;    // flag, variable, placeholder, protocol-relative
  if (/[*?[\]{}<>]/.test(span)) return null;         // glob or placeholder
  const cleaned = span.replace(/^\.\//, "").replace(/\/+$/, "");
  if (!cleaned || cleaned.startsWith("/")) return null; // absolute paths are not repo-relative
  if (cleaned.split("/").some((s) => s === "." || s === "..")) return null;
  if (!trackedTopLevel.has(cleaned.split("/")[0])) return null; // adopter tree, not this one
  return cleaned;
}

// --- assertion 1: declared paths resolve ------------------------------------

const declared = new Map();
for (const entry of adopterPaths) {
  const path = entry && typeof entry.path === "string" ? entry.path : null;
  const reason = entry && typeof entry.reason === "string" ? entry.reason.trim() : "";
  const occurrences = entry && Number.isInteger(entry.occurrences) ? entry.occurrences : null;
  if (!path || !reason || occurrences === null || occurrences < 1) {
    findings.push(
      `docPaths.adopterPaths entry ${JSON.stringify(entry)} needs a path, a non-empty reason and an ` +
        "integer occurrences of at least 1. An exception with no reason is indistinguishable from an " +
        "oversight, and one with no count exempts every future mention of the same string.",
    );
    continue;
  }
  if (declared.has(path)) {
    findings.push(`docPaths.adopterPaths declares ${path} twice; one of the two reasons is dead text.`);
    continue;
  }
  declared.set(path, { reason, occurrences, seen: 0 });
}

const SPAN_RE = /`([^`\n]+)`/g;
let checked = 0;

for (const rel of docs) {
  const text = readDoc(rel);
  if (text === null) continue;
  for (const [lineNo, line] of proseLines(text)) {
    for (const m of line.matchAll(SPAN_RE)) {
      const path = candidatePath(m[1]);
      if (path === null) continue;
      const exception = declared.get(path);
      if (exception) {
        exception.seen += 1;
        continue;
      }
      checked += 1;
      if (trackedFiles.has(path) || trackedDirs.has(path)) continue;
      findings.push(
        `${rel}:${lineNo}: \`${path}\` is presented as a path in this repository, and git does not track it. ` +
          "Correct the path, or declare it in docPaths.adopterPaths with the reason it names a consumer's tree.",
      );
    }
  }
}

for (const [path, state] of declared) {
  if (state.seen === state.occurrences) continue;
  findings.push(
    `docPaths.adopterPaths records ${state.occurrences} occurrence(s) of \`${path}\` and the scanned ` +
      `documents contain ${state.seen}. ` +
      (state.seen > state.occurrences
        ? "A mention that was never reviewed is exempt right now; that is how this path became wrong the " +
          "first time. Read the new one, then update the count."
        : state.seen === 0
          ? "A dead exception protects nothing and hides the next one; remove the entry."
          : "Mentions were removed. Lower the count so the exemption keeps covering only what was reviewed."),
  );
}

// --- assertion 2: the required headings exist, in the required order ---------

const headingTexts = new Map();
for (const req of requiredHeadings) {
  const id = req && typeof req.id === "string" ? req.id : "(unnamed)";
  const file = req && typeof req.file === "string" ? req.file : null;
  if (!file || typeof req.pattern !== "string") {
    findings.push(`docPaths.requiredHeadings[${id}] needs a file and a pattern.`);
    continue;
  }
  if (!headingTexts.has(file)) {
    if (!trackedFiles.has(file)) {
      unassessed.push(`requiredHeadings[${id}]: ${file} is not tracked, so its headings were not assessed.`);
      headingTexts.set(file, null);
    } else {
      headingTexts.set(file, readDoc(file));
    }
  }
  const text = headingTexts.get(file);
  if (text === null || text === undefined) continue;

  let re;
  let beforeRe = null;
  try {
    re = new RegExp(req.pattern, "m");
    if (typeof req.before === "string") beforeRe = new RegExp(req.before, "m");
  } catch (err) {
    unassessed.push(`requiredHeadings[${id}]: invalid pattern (${err.message}); nothing was assessed for it.`);
    continue;
  }

  const lines = text.split(/\r?\n/);
  const at = lines.findIndex((l) => re.test(l));
  if (at === -1) {
    findings.push(
      `${file}: no line matches the required heading [${id}] /${req.pattern}/. ` +
        (req.note ? req.note : "The document lost a heading a reader is sent to."),
    );
    continue;
  }
  if (beforeRe) {
    const anchor = lines.findIndex((l) => beforeRe.test(l));
    if (anchor === -1) {
      findings.push(
        `${file}: required heading [${id}] must precede /${req.before}/, and no line matches that anchor. ` +
          "The ordering cannot be judged, and an unjudgeable ordering is not a pass.",
      );
      continue;
    }
    if (at >= anchor) {
      findings.push(
        `${file}: required heading [${id}] is at line ${at + 1}, at or after its anchor /${req.before}/ ` +
          `at line ${anchor + 1}. It is meant to come first.`,
      );
    }
  }
}

// --- report ------------------------------------------------------------------

for (const [path, state] of declared) {
  console.error(`  ~ not assessed: \`${path}\` x${state.seen} (recorded ${state.occurrences}) - ${state.reason}`);
}
for (const u of unassessed) console.error(`  ~ not assessed: ${u}`);

if (findings.length > 0) {
  console.error(`\n  Doc-shape check failed: ${findings.length} finding(s).\n`);
  for (const f of findings) console.error(`  - ${f}`);
  console.error("");
  process.exit(EXIT_FINDING);
}

if (unassessed.length > 0) {
  console.error(
    `\n  Doc-shape could not assess ${unassessed.length} configured input(s), listed above. ` +
      "That is not a pass.\n",
  );
  process.exit(EXIT_UNASSESSED);
}

console.log(
  `Doc shape OK: ${checked} repo-relative path(s) resolve across ${docs.length} document(s), ` +
    `${declared.size} declared as adopter-tree paths, ${requiredHeadings.length} required heading(s) present.`,
);
