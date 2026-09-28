#!/usr/bin/env node
// assert-ascii-gate-wired.mjs - the ASCII gate has to actually RUN, over the
// whole tree.
//
// scripts/check-ascii.mjs is not in CHECK_GATES in bin/aahp.js: it enforces this
// repository's own rule (owner decision 2026-09-28), and a consumer project that
// writes German prose or ships emoji in its README must not inherit it. So the
// ONLY thing that executes it is the aggregate `check` chain in package.json,
// which the required lint-and-validate job runs. If someone rebuilds that chain
// and drops the entry, nothing else notices.
//
// SCOPE, not just wiring. The gate accepts --path=<pathspec> to narrow what it
// reads. A check:ascii script carrying one would still run, still print
// "ASCII OK", and read a fraction of the tree: an exemption list by another
// name. So the script has to be exactly the gate with no arguments.
//
// Kept as a file rather than inlined into `node -e`, for the same reason
// tests/assert-doc-shape-wired.mjs is: under Git Bash a POSIX-looking path inside
// a quoted -e string is not converted for the native node binary.
//
// Usage: node tests/assert-ascii-gate-wired.mjs [repo-root]
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

const EXPECTED = "node scripts/check-ascii.mjs";
const script = pkg.scripts?.["check:ascii"];
if (!script) {
  problems.push("package.json defines no check:ascii script.");
} else if (script.trim() !== EXPECTED) {
  problems.push(
    `the check:ascii script must be exactly \`${EXPECTED}\`, so the required run reads every ` +
      `tracked file (found: \`${script}\`). A path argument or --path filter narrows the gate.`,
  );
}

const chain = (pkg.scripts?.check ?? "").split("&&").map((s) => s.trim());
if (!chain.includes("npm run check:ascii")) {
  problems.push(
    "check:ascii is not part of the aggregate `check` chain, which is what the required " +
      "lint-and-validate job runs. The gate would never execute.",
  );
}

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("ascii gate wiring OK");
