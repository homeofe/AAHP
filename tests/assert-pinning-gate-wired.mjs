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
//   2. The packages the required checks execute are pinned the way the gate
//      requires of an npx target: declared at an exact version and locked with
//      an integrity hash. The required lint-and-validate and aahp-manifest
//      checks run scripts/validate-json-schema.mjs with `node`, not `npx`, so
//      the gate's rule C (which reads npx targets out of the workflows) no
//      longer sees these packages at all; this is what holds them now. The list
//      is written out below AND compared with the packages that script actually
//      loads, in both directions: a new package in the validator is red until it
//      is listed (and so pinned), and an extraction that found nothing cannot
//      pass as "nothing to pin".

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

// The packages the required lint-and-validate and aahp-manifest checks execute,
// through scripts/validate-json-schema.mjs.
const EXECUTED_IN_REQUIRED_CHECKS = ["ajv", "ajv-formats"];
const VALIDATOR = "scripts/validate-json-schema.mjs";
const EXACT = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.]+)?$/;

// The package part of a bare module specifier, or null for a builtin or a
// relative path: `ajv/dist/2020` -> `ajv`, `@scope/name/x` -> `@scope/name`.
function packageOf(specifier) {
  if (specifier.startsWith("node:") || specifier.startsWith(".") || specifier.startsWith("/")) return null;
  const parts = specifier.split("/");
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
}

let validatorText = null;
try {
  validatorText = readFileSync(join(root, VALIDATOR), "utf8");
} catch (err) {
  problems.push(`${VALIDATOR} cannot be read (${err.code ?? err.message}), so what it loads cannot be compared`);
}
if (validatorText !== null) {
  // Code only: a module named in a comment is not loaded.
  const code = validatorText
    .split(/\r?\n/)
    .filter((line) => !line.trim().startsWith("//"))
    .join("\n");
  const loaded = new Set();
  const specifiers = /\brequire\(\s*["']([^"']+)["']\s*\)|\bimport\(\s*["']([^"']+)["']\s*\)|\bfrom\s+["']([^"']+)["']/g;
  for (const m of code.matchAll(specifiers)) {
    const name = packageOf(m[1] ?? m[2] ?? m[3]);
    if (name !== null) loaded.add(name);
  }
  for (const name of loaded) {
    if (!EXECUTED_IN_REQUIRED_CHECKS.includes(name)) {
      problems.push(
        `${VALIDATOR} loads ${name}, which EXECUTED_IN_REQUIRED_CHECKS in this file does not list, ` +
          "so nothing asserts it is pinned. Add it here and declare it as an exact devDependency.",
      );
    }
  }
  for (const name of EXECUTED_IN_REQUIRED_CHECKS) {
    if (!loaded.has(name)) {
      problems.push(
        `${VALIDATOR} no longer loads ${name}, which EXECUTED_IN_REQUIRED_CHECKS lists. Either the ` +
          "list is stale or this file can no longer see what the validator loads.",
      );
    }
  }
}

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
