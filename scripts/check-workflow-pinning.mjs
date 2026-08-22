#!/usr/bin/env node
// check-workflow-pinning.mjs - Whatever a workflow installs and then executes
// must come from the committed lockfile, and the lockfile must pin it by hash.
//
// WHY THIS GATE EXISTS
// ---------------------------------------------------------------------------
// Measured 2026-08-22. Two of the six required status checks on `main` ran
//
//     npm install --no-save ajv-cli ajv-formats
//     npx ajv-cli validate ... .ai/handoff/MANIFEST.json
//
// on every push and every pull request. `--no-save` guarantees the resolution
// is never written to package-lock.json, so 27 packages were downloaded and
// executed with nothing in the repository constraining any of them, and the
// next line executed the result by design. One compromised release anywhere in
// that closure was arbitrary code execution inside the checks whose verdict
// certifies a change. This repository publishes those gates for other
// repositories to install and trust, so the failure propagated outward.
//
// The packages are pinned now. This gate is why they stay pinned.
//
// THE ROOT CAUSE IS NOT "SOMEONE FORGOT TO PIN"
// ---------------------------------------------------------------------------
// The repository already knew how to do this correctly and already documented
// it. assets/governance/aahp-govern.yml - the workflow template this package
// ships to consumers - has always used `npm ci --ignore-scripts` followed by
// `npx --no-install`, and .github/workflows/aahp-verify.yml pins its actions to
// full commit SHAs. Both are files strangers read. The workflows that only ever
// ran here did not follow the same rule, because nothing made them.
//
// So the defect was not the missing pin, it was that pinning was a convention
// applied by hand where it would be seen. A convention has no failure mode: it
// simply stops being applied, silently, the first time someone rewrites a file.
// This gate turns it into a property of the repository, which does have one.
//
// WHAT IS ASSERTED, AND THE MUTATION THAT TURNS EACH ONE RED
// ---------------------------------------------------------------------------
//   A. No workflow performs a project-level `npm install` / `npm i` / `npm add`.
//      The reproducible form is `npm ci`, which installs the locked closure and
//      nothing else. MUTATION: put `npm install --no-save ajv-cli ajv-formats`
//      back into any scanned workflow.
//
//   B. Every `npx` in a workflow carries `--no-install`. This is the load
//      bearing half, and leaving it out is the failure that looks fixed:
//      without `--no-install`, npx silently falls back to fetching from the
//      registry whenever the local resolution misses, and the pin buys nothing.
//      MUTATION: drop `--no-install` from either validate step.
//
//   C. Every package a workflow executes with `npx --no-install` is declared in
//      package.json at an EXACT version. A range is reproducible through the
//      lockfile but not reviewable in the diff, which is where a supply-chain
//      change has to be visible. MUTATION: change "ajv-cli": "5.0.0" to
//      "^5.0.0", or remove the declaration entirely.
//      Asked only of workflows that run HERE, not of the shipped templates:
//      a template runs against a CONSUMER package.json, so this one is not
//      the file that declares its npx target.
//
//   D. Every direct dependency and devDependency has a package-lock.json entry
//      carrying both `resolved` and `integrity`. This is the "by hash" half: a
//      declaration alone says which version, the lockfile says which BYTES.
//      MUTATION: delete the `integrity` field from any locked direct dependency.
//
// DELIBERATELY OUT OF SCOPE, so the hole is visible here rather than invisible
// in CI: `npm install -g <pkg>` (ci.yml, publish job). It is a different risk
// class - the package manager itself, published by the registry operator,
// inside the only job holding `id-token: write` - and there is an open owner
// decision on whether that step should exist at all rather than be pinned. See
// https://github.com/homeofe/AAHP/issues/68. Extending this gate to global
// installs is a few lines once that decision lands. It is named here instead of
// being quietly allowed by an exemption list that nobody would ever re-read.
//
// WHICH FILES ARE SCANNED
// ---------------------------------------------------------------------------
// .github/workflows (what runs here) and assets/governance (workflow templates
// consumers copy into their own .github/workflows). Both are files that execute
// on somebody's CI. tests/fixtures/workflows is NOT scanned: those files are
// deliberately malformed inputs to another gate's tests.
//
// EXIT CODES
//   0  every rule holds across every scanned file
//   1  a rule is violated - a real finding
//   2  the gate could not evaluate (no YAML parser, no workflow directory, no
//      workflow files, unparseable workflow, unreadable package.json or
//      package-lock.json). Never 0: "I could not look" must not read as
//      "I looked and it was fine".
//
// DELIBERATELY NOT IN bin/aahp.js CHECK_GATES
// ---------------------------------------------------------------------------
// The gates in CHECK_GATES run against an arbitrary CONSUMER project via
// `aahp check`. Turning this one on there would go red on the first run in most
// consumer repositories, which is a fleet-wide breaking change and an owner
// decision, not a side effect of fixing this repository. It is wired into
// `npm run check` instead, which is what the required lint-and-validate job
// executes, and tests/workflow-pinning.bats asserts that wiring so the gate
// cannot quietly stop being invoked.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadPkg } from "./aahp-config.mjs";

// Directories whose YAML files are workflows. The first is required to exist
// and to be non-empty; a missing optional directory is simply not scanned.
const WORKFLOW_DIR = join(".github", "workflows");
const TEMPLATE_DIRS = [join("assets", "governance")];

// `npm install` and every alias npm accepts for it. `ci` is deliberately absent:
// it is the form this gate exists to require.
const INSTALL_VERBS = new Set(["install", "i", "in", "ins", "inst", "insta", "instal", "isntall", "add"]);

// Flags that make an install global. Global installs are out of scope (header).
const GLOBAL_FLAGS = /^(?:-g|--global|--location=global)$/;

// An exact version: no caret, tilde, range, tag, URL or git ref.
const EXACT_VERSION = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)*$/;

const root = resolveRoot();

function bail(code, lines) {
  console.error("");
  for (const line of lines) console.error(`  ${line}`);
  console.error("");
  process.exit(code);
}

let YAML;
try {
  YAML = await import("yaml");
} catch {
  bail(2, [
    "Workflow pinning: no YAML parser available.",
    "This gate parses workflow files with the `yaml` devDependency rather than",
    "matching text, because a regex over YAML silently misreads block scalars,",
    "anchors and quoting - and would then report a clean repository it never",
    "actually read.",
    "",
    "Fix: run `npm ci` so devDependencies are present.",
  ]);
}

let pkg;
try {
  pkg = loadPkg(root);
} catch (err) {
  bail(2, [`Workflow pinning: ${err.message}`]);
}

const lockPath = join(root, "package-lock.json");
if (!existsSync(lockPath)) {
  bail(2, [
    `Workflow pinning: no package-lock.json at ${lockPath}.`,
    "Without a lockfile there is nothing that pins anything by hash, so the",
    "relation this gate asserts is untested rather than satisfied.",
  ]);
}
let lock;
try {
  lock = JSON.parse(readFileSync(lockPath, "utf8"));
} catch (err) {
  bail(2, [`Workflow pinning: package-lock.json is not valid JSON (${err.message}).`]);
}

// ---------------------------------------------------------------------------
// The files to scan.
// ---------------------------------------------------------------------------
function yamlFilesIn(relDir, { required }) {
  const abs = join(root, relDir);
  if (!existsSync(abs)) {
    if (!required) return [];
    bail(2, [
      `Workflow pinning: no workflow directory at ${abs}.`,
      "This gate asserts a property of the workflows that run here. With no",
      "workflows there is nothing to assert it over, so the answer is unknown",
      "rather than clean.",
    ]);
  }
  const files = readdirSync(abs)
    .filter((f) => /\.ya?ml$/.test(f))
    .sort()
    .map((f) => ({ rel: `${relDir.replace(/\\/g, "/")}/${f}`, abs: join(abs, f), local: required }));
  if (required && files.length === 0) {
    bail(2, [`Workflow pinning: ${abs} contains no workflow files.`]);
  }
  return files;
}

const scanned = [
  ...yamlFilesIn(WORKFLOW_DIR, { required: true }),
  ...TEMPLATE_DIRS.flatMap((d) => yamlFilesIn(d, { required: false })),
];

// ---------------------------------------------------------------------------
// Shell-command extraction from a `run:` block.
//
// The block is split into individual commands so a violation cannot hide behind
// a separator: `foo && npm install bar` is two commands, not one. Splitting can
// only ever produce MORE fragments to inspect, never fewer, so an odd quoting
// case costs a harmless extra fragment rather than a missed finding.
// ---------------------------------------------------------------------------
export function commandsIn(runText) {
  const joined = String(runText).replace(/\\\r?\n/g, " ");
  const commands = [];
  for (const rawLine of joined.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;
    for (const part of line.split(/(?:&&|\|\||[|;])/)) {
      const cmd = part.trim();
      if (cmd !== "") commands.push(cmd);
    }
  }
  return commands;
}

function tokenize(command) {
  return command.split(/\s+/).filter((t) => t !== "");
}

// The package npx is asked to run: the first argument that is not a flag and is
// not the value consumed by a flag that takes one.
export function npxTarget(tokens) {
  for (let i = 1; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "-p" || t === "--package" || t === "-c" || t === "--call") {
      i++;
      continue;
    }
    if (t.startsWith("-")) continue;
    return t;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Rules A, B and C, over every `run:` in every scanned workflow.
// ---------------------------------------------------------------------------
const findings = [];
const npxTargets = [];

function parseWorkflow(file) {
  let text;
  try {
    text = readFileSync(file.abs, "utf8");
  } catch (err) {
    bail(2, [`Workflow pinning: cannot read ${file.rel} (${err.message}).`]);
  }
  try {
    return YAML.parse(text) ?? {};
  } catch (err) {
    bail(2, [
      `Workflow pinning: ${file.rel} is not valid YAML (${err.message}).`,
      "The gate refuses to guess at a file it cannot parse.",
    ]);
  }
}

for (const file of scanned) {
  const doc = parseWorkflow(file);
  const jobs = doc?.jobs;
  if (!jobs || typeof jobs !== "object") continue;

  for (const [jobName, job] of Object.entries(jobs)) {
    const steps = Array.isArray(job?.steps) ? job.steps : [];
    for (let i = 0; i < steps.length; i++) {
      const step = steps[i];
      if (typeof step?.run !== "string") continue;
      const where = `${file.rel}:${jobName}:${step.name || `step ${i + 1}`}`;

      for (const command of commandsIn(step.run)) {
        const tokens = tokenize(command);
        if (tokens.length === 0) continue;

        if (tokens[0] === "npm" && INSTALL_VERBS.has(tokens[1] ?? "")) {
          if (tokens.some((t) => GLOBAL_FLAGS.test(t))) continue; // out of scope, see header
          findings.push({
            where,
            command,
            message:
              "installs packages outside the committed lockfile. Use `npm ci`, which " +
              "installs exactly the locked closure. `--no-save` in particular guarantees " +
              "the resolution is never recorded anywhere.",
          });
          continue;
        }

        if (tokens[0] === "npx") {
          if (!tokens.includes("--no-install")) {
            findings.push({
              where,
              command,
              message:
                "runs npx without `--no-install`, so npx falls back to fetching from the " +
                "registry whenever the local resolution misses. Any pin upstream of this " +
                "line buys nothing while this line can reach the network.",
            });
            continue;
          }
          // Rule C is asked only of workflows that run HERE. A shipped
          // template runs in a consumer repository against a consumer
          // package.json, so this package.json is not the file that would
          // declare its npx target - `aahp` itself being the obvious case.
          const target = file.local ? npxTarget(tokens) : null;
          if (target !== null) npxTargets.push({ target, where });
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Rule C: what npx executes must be declared here, at an exact version.
// ---------------------------------------------------------------------------
const declared = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };

for (const { target, where } of npxTargets) {
  const spec = declared[target];
  if (spec === undefined) {
    findings.push({
      where,
      command: `npx --no-install ${target}`,
      message:
        `executes "${target}", which package.json does not declare. Nothing in this ` +
        "repository states which version that is, so nothing can pin it. Declare it as " +
        "an exact devDependency and commit the regenerated package-lock.json.",
    });
    continue;
  }
  if (!EXACT_VERSION.test(spec)) {
    findings.push({
      where,
      command: `npx --no-install ${target}`,
      message:
        `executes "${target}", declared as ${JSON.stringify(spec)}. A range resolves ` +
        "through the lockfile but is not visible in the diff, which is where a " +
        "supply-chain change has to be reviewable. Declare an exact version.",
    });
  }
}

// ---------------------------------------------------------------------------
// Rule D: the lockfile pins every direct dependency by hash.
// ---------------------------------------------------------------------------
const lockPackages = lock?.packages;
if (!lockPackages || typeof lockPackages !== "object") {
  bail(2, [
    "Workflow pinning: package-lock.json has no `packages` map.",
    `This gate reads lockfileVersion 2 or 3; this file reports ${JSON.stringify(lock?.lockfileVersion)}.`,
    "It refuses to report a clean result over a shape it cannot read.",
  ]);
}

for (const [name, spec] of Object.entries(declared)) {
  const entry = lockPackages[`node_modules/${name}`];
  if (!entry) {
    findings.push({
      where: "package-lock.json",
      command: `${name}@${spec}`,
      message:
        "is declared in package.json but has no lockfile entry, so `npm ci` cannot " +
        "install it and nothing pins its bytes. Run `npm install` and commit the lockfile.",
    });
    continue;
  }
  if (typeof entry.integrity !== "string" || entry.integrity === "") {
    findings.push({
      where: "package-lock.json",
      command: `${name}@${entry.version ?? "?"}`,
      message:
        "has no `integrity` hash in the lockfile. The version says which release; the " +
        "integrity hash says which bytes. Without it a republished tarball installs clean.",
    });
  }
  if (typeof entry.resolved !== "string" || entry.resolved === "") {
    findings.push({
      where: "package-lock.json",
      command: `${name}@${entry.version ?? "?"}`,
      message: "has no `resolved` URL in the lockfile, so its origin is unrecorded.",
    });
  }
}

// ---------------------------------------------------------------------------
if (findings.length > 0) {
  console.error(`\n  Workflow pinning failed (${findings.length} finding(s)).\n`);
  for (const f of findings) {
    console.error(`  - ${f.where}`);
    console.error(`      ${f.command}`);
    console.error(`      ${f.message}`);
  }
  console.error("");
  process.exit(1);
}

console.log(
  `Workflow pinning OK: ${scanned.length} workflow file(s), ` +
    `${npxTargets.length} pinned npx invocation(s), ` +
    `${Object.keys(declared).length} direct dependencies locked by hash.`,
);
for (const file of scanned) console.log(`    ${file.rel}`);
