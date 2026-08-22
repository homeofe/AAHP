#!/usr/bin/env node
// assert-pinning-gate-wired.mjs - repository-shape assertions for
// workflow-pinning.bats.
//
// Kept as a file rather than inlined into `node -e` on purpose: under Git Bash
// (MSYS) a POSIX-looking path INSIDE a quoted -e string is not converted for the
// native node binary, so the repo root arrives mangled and the test reports a
// defect that does not exist. A path passed as an argv element IS converted.
// Same reasoning as tests/assert-repo-ci-shape.mjs.
//
// Two things are asserted, and neither is about the gate's own logic:
//
//   1. The workflow-pinning gate is actually INVOKED by the aggregate `check`
//      chain, which is what the required lint-and-validate job runs. A gate that
//      exists but never runs protects nothing, and nothing else in the
//      repository would notice it had been dropped from the chain.
//   2. The two packages the required checks execute are pinned the way the gate
//      requires: declared at an exact version and locked with an integrity hash.
//      The gate derives this from the workflow files; this derives it from the
//      package names directly, so a change that stopped the gate from seeing
//      those steps cannot also silence this.

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(process.argv[2] || ".");
const problems = [];

const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const lock = JSON.parse(readFileSync(join(root, "package-lock.json"), "utf8"));

if (!pkg.scripts?.["check:workflow-pinning"]) {
  problems.push("package.json defines no check:workflow-pinning script");
}
if (!pkg.scripts?.check?.includes("check:workflow-pinning")) {
  problems.push(
    "check:workflow-pinning is not part of the aggregate `check` chain, which is " +
      "what the required lint-and-validate job runs. The gate would never execute.",
  );
}

// The packages the required lint-and-validate and aahp-manifest checks execute.
const EXECUTED_IN_REQUIRED_CHECKS = ["ajv-cli", "ajv-formats"];
const EXACT = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.]+)?$/;

for (const name of EXECUTED_IN_REQUIRED_CHECKS) {
  const spec = pkg.devDependencies?.[name] ?? pkg.dependencies?.[name];
  if (spec === undefined) {
    problems.push(`${name} is executed by a required status check but is not declared in package.json`);
    continue;
  }
  if (!EXACT.test(spec)) {
    problems.push(`${name} is declared as ${JSON.stringify(spec)}, which is not an exact version`);
  }
  const entry = lock.packages?.[`node_modules/${name}`];
  if (!entry) {
    problems.push(`${name} has no package-lock.json entry, so npm ci cannot install it`);
    continue;
  }
  if (typeof entry.integrity !== "string" || entry.integrity === "") {
    problems.push(`${name} has no integrity hash in package-lock.json`);
  }
  if (entry.version !== spec) {
    problems.push(`${name} is declared as ${spec} but locked at ${entry.version}`);
  }
}

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("pinning gate wiring OK");
