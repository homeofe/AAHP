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
//      step that stops working without it. The root is an argument, so a root
//      that does not contain one of those workflows gets that elevation named
//      on stderr as NOT asserted; see the comment above the loop.
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

// --- Reading an input, without a thrown exception standing in for a finding.
//
// The root is an ARGUMENT, so this gate does not always get this repository.
// `npm test` passes the repository; the fixture tests in
// tests/runtime-support.bats pass a partial copy that holds package.json and
// .github/workflows/ci.yml and nothing else. An unguarded readFileSync on a
// file such a copy does not have throws ENOENT, node exits 1 with a stack
// trace, and NONE of the findings below are printed. A caller asserting an exit
// code cannot tell that apart from a real finding, and a caller asserting a
// message sees neither - the gate reports a defect it never looked for and
// stays silent about the ones it did. Every read below is therefore guarded,
// and a file this gate cannot read is a finding in the same shape as the rest.

/** Read a file under the root. Returns { text } or { absent } or { problem }. */
function readUnder(label, ...segments) {
  const path = join(root, ...segments);
  try {
    return { text: readFileSync(path, "utf8") };
  } catch (err) {
    if (err.code === "ENOENT") return { absent: true };
    return { problem: `${label} exists under ${root} but could not be read (${err.code ?? err.message}).` };
  }
}

/** Parse a workflow under .github/workflows/. Returns { doc } or { absent } or { problem }. */
function loadWorkflow(file) {
  const read = readUnder(file, ".github", "workflows", file);
  if (read.absent || read.problem) return read;
  let doc;
  try {
    doc = parse(read.text);
  } catch (err) {
    return { problem: `.github/workflows/${file} is not valid YAML (${err.message.split("\n")[0]}).` };
  }
  // An empty file parses to null without throwing. Returning it as a document
  // would make every job in it read as "gone" instead of "the file says nothing".
  if (doc === null || doc === undefined) {
    return { problem: `.github/workflows/${file} is present but parses to an empty document.` };
  }
  return { doc };
}

const pkgRead = readUnder("package.json", "package.json");
let pkg = null;
if (pkgRead.absent) {
  problems.push(`package.json is not present under ${root}, so nothing here can be asserted.`);
} else if (pkgRead.problem) {
  problems.push(pkgRead.problem);
} else {
  try {
    pkg = JSON.parse(pkgRead.text);
  } catch (err) {
    problems.push(`package.json is not valid JSON (${err.message}).`);
  }
}

if (pkg === null) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}

if (!pkg.scripts?.["check:runtime-support"]) {
  problems.push("package.json defines no check:runtime-support script");
}
if (!pkg.scripts?.check?.includes("check:runtime-support")) {
  problems.push(
    "check:runtime-support is not part of the aggregate `check` chain, which is " +
      "what the required lint-and-validate job runs. The gate would never execute.",
  );
}

// ci.yml is mandatory: every remaining assertion in this file is about it or
// about a job inside it, so a root whose ci.yml cannot be read has nothing left
// to assert. Reported and exited here rather than carried forward, so the output
// says "ci.yml is not there" instead of a cascade of "this job is gone" lines
// that name the wrong cause.
const ciRead = loadWorkflow("ci.yml");
if (ciRead.absent) {
  problems.push(`.github/workflows/ci.yml is not present under ${root}, so no job in it can be asserted.`);
} else if (ciRead.problem) {
  problems.push(ciRead.problem);
}
if (!ciRead.doc) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
const ci = ciRead.doc;

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

// A recorded elevation whose workflow this root does not contain at all is NOT
// asserted, and that is SAID on every run rather than passed over: the root is
// an argument, so an absent codeql.yml is either an elevation someone deleted or
// a fixture that never had one, and this gate cannot tell those two apart from
// the file alone. It does not guess in either direction. Everything it can see
// and cannot trust is a failure instead: a workflow that exists and cannot be
// read, one that is not valid YAML, a job that is gone, a permissions block that
// no longer carries the scope.
//
// The gate cannot end up asserting nothing and still report success: ci.yml
// carries two of the three recorded elevations and is mandatory above, so a root
// that yields no assertion at all has already failed on the ci.yml finding.
const workflowCache = { "ci.yml": { doc: ci } };
const notAsserted = [];
for (const req of REQUIRED_JOB_PERMISSIONS) {
  if (!workflowCache[req.file]) workflowCache[req.file] = loadWorkflow(req.file);
  const loaded = workflowCache[req.file];
  if (loaded.absent) {
    notAsserted.push(
      `${req.file}: job '${req.job}' ${req.scope}: ${req.value} - that workflow is not present under ${root}.`,
    );
    continue;
  }
  if (loaded.problem) {
    // Once per unreadable file, not once per elevation recorded against it.
    if (!loaded.reported) {
      loaded.reported = true;
      problems.push(`${loaded.problem} The elevations recorded against it cannot be asserted.`);
    }
    continue;
  }
  const job = loaded.doc?.jobs?.[req.job];
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

for (const n of notAsserted) console.error(`  ~ not asserted here: ${n}`);

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("repo CI shape OK");
