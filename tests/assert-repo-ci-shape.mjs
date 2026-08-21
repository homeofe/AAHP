#!/usr/bin/env node
// assert-repo-ci-shape.mjs - repository-shape assertions for runtime-support.bats.
//
// Kept as a file rather than inlined into `node -e` on purpose: under Git Bash
// (MSYS) a POSIX-looking path INSIDE a quoted -e string is not converted for the
// native node binary, so `require('/c/Users/.../package.json')` fails with
// MODULE_NOT_FOUND and the test reports a defect that does not exist. A path
// passed as an argv element IS converted, so the repo root arrives here intact.
//
// Two things are asserted, and neither is about the gate's own logic:
//
//   1. The runtime-support gate is actually INVOKED by the aggregate `check`
//      chain. A gate that exists but never runs protects nothing.
//   2. The required status check keeps its literal name. 'lint-and-validate' is
//      required by exact name on main; giving that job a strategy.matrix renames
//      its checks to 'lint-and-validate (22)' and the required context then never
//      reports again - every pull request blocked, with zero red checks to
//      explain why. The second runtime therefore belongs in runtime-matrix.

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parse } from "yaml";

const root = resolve(process.argv[2] || ".");
const problems = [];

const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));

if (!pkg.scripts?.["check:runtime-support"]) {
  problems.push("package.json defines no check:runtime-support script");
}
if (!pkg.scripts?.check?.includes("check:runtime-support")) {
  problems.push(
    "check:runtime-support is not part of the aggregate `check` chain, which is " +
      "what the required lint-and-validate job runs. The gate would never execute.",
  );
}

const ci = parse(readFileSync(join(root, ".github", "workflows", "ci.yml"), "utf8"));

const required = ci?.jobs?.["lint-and-validate"];
if (!required) {
  problems.push("the required job 'lint-and-validate' is gone from ci.yml");
} else if (required.strategy?.matrix) {
  problems.push(
    "'lint-and-validate' gained a strategy.matrix. Its check name would become " +
      "'lint-and-validate (<value>)', and the required context 'lint-and-validate' " +
      "would never report again - blocking every pull request with no red check.",
  );
}

if (!ci?.jobs?.["runtime-matrix"]) {
  problems.push(
    "the runtime-matrix job is gone; the published engines.node range would no " +
      "longer be exercised at more than one point.",
  );
}

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("repo CI shape OK");
