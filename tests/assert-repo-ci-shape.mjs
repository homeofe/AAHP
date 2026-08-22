#!/usr/bin/env node
// assert-repo-ci-shape.mjs - repository-shape assertions for runtime-support.bats.
//
// Kept as a file rather than inlined into `node -e` on purpose: under Git Bash
// (MSYS) a POSIX-looking path INSIDE a quoted -e string is not converted for the
// native node binary, so `require('/c/Users/.../package.json')` fails with
// MODULE_NOT_FOUND and the test reports a defect that does not exist. A path
// passed as an argv element IS converted, so the repo root arrives here intact.
//
// Three things are asserted, and none is about the gate's own logic:
//
//   1. The runtime-support gate is actually INVOKED by the aggregate `check`
//      chain. A gate that exists but never runs protects nothing.
//   2. The required status check keeps its literal name. 'lint-and-validate' is
//      required by exact name on main; giving that job a strategy.matrix renames
//      its checks to 'lint-and-validate (22)' and the required context then never
//      reports again - every pull request blocked, with zero red checks to
//      explain why. The second runtime therefore belongs in runtime-matrix.
//   3. The three jobs that need MORE than the top-level `contents: read` still
//      declare it. A job-level `permissions:` REPLACES the top-level block
//      rather than merging with it, so once ci.yml and codeql.yml gained a
//      top-level `contents: read`, deleting a job-level block as "redundant"
//      would silently strip an elevation. Each of the three is listed with the
//      step that stops working without it.
//
// The two general workflow-hardening properties (every document declares a
// top-level `permissions:` mapping, and every checkout sets
// `persist-credentials: false`) are asserted separately, over both
// .github/workflows/ and the shipped assets/governance/, by
// tests/assert-workflow-hardening.mjs.

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

// --- Job-level elevations that the top-level `contents: read` must not swallow.
//
// `scope` is the permission, `needed_by` names what stops working without it,
// so a future reader who wants to delete the block can see what it costs before
// deleting it. `file` is the workflow the job lives in.
const REQUIRED_JOB_PERMISSIONS = [
  {
    file: "ci.yml",
    job: "publish",
    scope: "id-token",
    value: "write",
    needed_by: "npm publish --provenance cannot mint its OIDC token",
  },
  {
    file: "ci.yml",
    job: "release",
    scope: "contents",
    value: "write",
    needed_by: "gh release create cannot create the release object",
  },
  {
    file: "codeql.yml",
    job: "analyze",
    scope: "security-events",
    value: "write",
    needed_by: "github/codeql-action/analyze cannot upload its SARIF result",
  },
];

const workflowCache = { "ci.yml": ci };
for (const req of REQUIRED_JOB_PERMISSIONS) {
  if (!workflowCache[req.file]) {
    workflowCache[req.file] = parse(readFileSync(join(root, ".github", "workflows", req.file), "utf8"));
  }
  const job = workflowCache[req.file]?.jobs?.[req.job];
  if (!job) {
    problems.push(`${req.file}: job '${req.job}' is gone, and with it the ${req.scope}: ${req.value} grant.`);
    continue;
  }
  const perms = job.permissions;
  if (!perms || typeof perms !== "object" || Array.isArray(perms) || String(perms[req.scope]) !== req.value) {
    problems.push(
      `${req.file}: job '${req.job}' no longer declares '${req.scope}: ${req.value}'. A job-level ` +
        "permissions block REPLACES the top-level one rather than merging with it, so the top-level " +
        `'contents: read' does not supply this. Without it, ${req.needed_by}.`,
    );
  }
}

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("repo CI shape OK");
