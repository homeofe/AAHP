#!/usr/bin/env node
// assert-doc-shape-wired.mjs - the doc-shape gate has to actually RUN.
//
// A gate that exists but is never invoked protects nothing, and this one is easy
// to orphan: it is deliberately NOT in CHECK_GATES in bin/aahp.js (see ADR-022,
// it is repository-local and no consumer should inherit it), so the ONLY thing
// that executes it is the aggregate `check` chain in package.json, which the
// required lint-and-validate job runs. If someone rebuilds that chain and drops
// the entry, nothing else notices.
//
// Kept as a file rather than inlined into `node -e`, for the same reason
// tests/assert-repo-ci-shape.mjs is: under Git Bash a POSIX-looking path inside a
// quoted -e string is not converted for the native node binary, so the read fails
// with MODULE_NOT_FOUND and the test reports a defect that does not exist. A path
// passed as an argv element IS converted.
//
// Usage: node tests/assert-doc-shape-wired.mjs [repo-root]
// Exit:  0 wiring holds, 1 it does not.

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(process.argv[2] || ".");
const problems = [];

let pkg = null;
try {
  pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
} catch (err) {
  console.error(`  - package.json under ${root} could not be read as JSON (${err.code || err.message}).`);
  process.exit(1);
}

if (!pkg.scripts?.["check:doc-shape"]) {
  problems.push("package.json defines no check:doc-shape script.");
} else if (!pkg.scripts["check:doc-shape"].includes("check-doc-shape.mjs")) {
  problems.push(
    `the check:doc-shape script does not invoke check-doc-shape.mjs (found: ${pkg.scripts["check:doc-shape"]}).`,
  );
}

if (!pkg.scripts?.check?.includes("check:doc-shape")) {
  problems.push(
    "check:doc-shape is not part of the aggregate `check` chain, which is what the required " +
      "lint-and-validate job runs. The gate would never execute.",
  );
}

// SCOPE, not just wiring. Proving the gate runs says nothing about what it reads:
// narrowing docPaths.include back to the four adopter documents drops nine files
// from coverage with every check still green.
//
// Stated as a RELATIONSHIP rather than a literal list, so it does not go stale the
// next time either list grows: whatever docLinks reads, docPaths reads too.
// docLinks already covered .ai/handoff/*.md while docPaths did not, which is how
// nine files sat outside the path check while the config looked complete.
let cfg = null;
try {
  cfg = JSON.parse(readFileSync(join(root, "aahp.config.json"), "utf8"));
} catch (err) {
  console.error(
    `  - aahp.config.json under ${root} could not be read as JSON (${err.code || err.message}).`,
  );
  process.exit(1);
}

// Optional on BOTH sides. `cfg.docLinks.include?.length` throws a TypeError when
// the section is absent, and a gate that dies with a stack trace where it should
// report a finding is the failure mode this repository pins elsewhere.
const linkDocs = cfg.docLinks?.include ?? [];
const pathDocs = cfg.docPaths?.include ?? [];
const uncovered = linkDocs.filter((entry) => !pathDocs.includes(entry));
if (uncovered.length > 0) {
  problems.push(
    `docPaths must cover everything docLinks reads; in docLinks.include but not in ` +
      `docPaths.include: ${uncovered.join(", ")}. The link checker resolves Markdown ` +
      `links in those documents while the path check never opens them.`,
  );
}

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("doc-shape gate wiring OK");
