#!/usr/bin/env node
// check-runtime-support.mjs - The runtimes CI exercises and the runtimes the
// package CLAIMS to support must be the same set, and the floor of that set must
// still be receiving security patches.
//
// WHY THIS GATE EXISTS
// ---------------------------------------------------------------------------
// Measured 2026-08-21. AAHP published `engines.node: ">=18"` while Node 18 had
// been end-of-life since 2025-04-30, and validated on Node 20, end-of-life since
// 2026-04-30. Every repository in the estate consumes this package and inherits
// that support claim, and the workflow this package PROPAGATES to consumers
// (.github/workflows/aahp-verify.yml) pinned the same dead runtime, so the claim
// spread on install. Nothing in CI could ever have gone red about it: the pins
// were internally consistent, just uniformly dead.
//
// The same class of defect broke a release elsewhere in the estate on the same
// day: a publish job ran `npm install -g npm@latest` on Node 20, npm 12 had
// dropped Node 20, and the step that exists to make publishing possible was the
// step that refused. Build was green on a newer runtime; publish died on the old
// one; every check passed and nothing shipped.
//
// WHY THIS IS A RELATION AND NOT A LIST OF DEAD VERSIONS
// ---------------------------------------------------------------------------
// A hardcoded list of forbidden versions is correct on the day it is written and
// wrong every day after. The durable half is a RELATION - every runtime CI
// exercises must satisfy the range the package publishes - because both sides
// then move together or this gate goes red. Exactly ONE dated fact is kept, in
// SUPPORTED_FLOOR below, with the date it was measured next to it.
//
// WHAT EACH CHECK GUARDS, AND THE MUTATION THAT TURNS IT RED
// ---------------------------------------------------------------------------
//   - "the matrix still exercises more than one runtime": empty
//     strategy.matrix.node-version, or cut it to a single entry. Every other
//     check here is vacuously true over an empty pin list, so this one comes
//     first.
//
//     THE TRAP THIS SHAPE AVOIDS, recorded because a sibling gate in this estate
//     fell into it the same week: its vacuity guard asserted that the GLOBAL pin
//     list was non-empty. Emptying the matrix left it GREEN, because the
//     standalone `node-version:` pins in the other jobs kept the global list
//     populated on their own. The multi-runtime coverage vanished and nothing
//     went red. So this binds the MATRIX ITSELF, not the union it contributes to.
//
//   - "every pinned runtime satisfies engines.node": set any job back to '20'
//     while engines stays '>=22', or widen engines to '>=18' while CI stays on 22.
//   - "the published floor is not end-of-life": set engines.node to '>=20'.
//   - "the release path only uses runtimes the build path proved": point the
//     publish job at a major no build or test job runs. Note this is a MEMBERSHIP
//     test, not "release >= lowest build". The ordering version could never fire
//     here - the lowest build pin IS the floor, so beating it also trips the
//     floor check - and a predicate that cannot fire on its own is decoration.
//     The mutation proof caught that; the membership form fires in both
//     directions, for a release pinned below OR above the tested set.
//   - "no pin is unevaluatable": replace a literal with `node-version-file:` or a
//     non-matrix `${{ }}` expression. A gate that silently drops what it cannot
//     parse reports a clean repo it never read, so an unreadable pin FAILS.
//
// EXIT CODES
//   0  every relation holds
//   1  a relation is violated - a real finding
//   2  the gate could not evaluate (no workflows, unreadable engines, no YAML
//      parser). Never 0: "I could not look" must not read as "I looked and it
//      was fine".
//
// DELIBERATELY NOT IN bin/aahp.js CHECK_GATES
// ---------------------------------------------------------------------------
// The gates in CHECK_GATES run against an arbitrary CONSUMER project via
// `aahp check`. This one is not portable in that position yet, and adding it
// there would break consumers rather than protect them:
//
//   - Not every consumer is an npm package. At least one is a Python project with
//     no package.json engines.node at all, so this gate would exit 2 on every run.
//   - The `yaml` parser it needs is a devDependency of THIS package, so it is
//     absent from a consumer install.
//
// It is wired into `npm run check` instead, which is what the required
// lint-and-validate job executes, and tests/runtime-support.bats asserts that
// wiring so the gate cannot quietly stop being invoked. Making it consumer-facing
// is a real option, but it needs an applicability predicate and a shipped parser
// first - do not simply append it to CHECK_GATES.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadPkg } from "./aahp-config.mjs";

// The oldest Node major still receiving security patches.
//
// Measured 2026-08-21: 18.x EOL 2025-04-30, 20.x EOL 2026-04-30, 22.x Active LTS
// until 2027-04, 24.x Active LTS. When 22 reaches end of life this constant is
// the ONE thing to change, and this gate going red is the reminder to change it.
const SUPPORTED_FLOOR = 22;

// Jobs that publish or tag, as opposed to jobs that build and test.
const RELEASE_JOB = /^(publish|release|version-guard)$/;

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
    "Runtime support: no YAML parser available.",
    "This gate parses .github/workflows/*.yml with the `yaml` devDependency",
    "rather than matching text, because a regex over YAML silently misreads",
    "block scalars, anchors and quoting - and would then report a clean repo",
    "it never actually read.",
    "",
    "Fix: run `npm ci` (or `npm install`) so devDependencies are present.",
  ]);
}

let pkg;
try {
  pkg = loadPkg(root);
} catch (err) {
  bail(2, [`Runtime support: ${err.message}`]);
}

// ---------------------------------------------------------------------------
// The support claim the package publishes.
// ---------------------------------------------------------------------------
function enginesFloor() {
  const range = pkg?.engines?.node;
  if (typeof range !== "string") {
    bail(2, [
      "Runtime support: package.json declares no engines.node.",
      "Without it the package makes no support claim at all, and this gate has",
      "nothing to compare the CI pins against.",
      "",
      `Fix: add "engines": { "node": ">=${SUPPORTED_FLOOR}" } to package.json.`,
    ]);
  }
  const m = /^>=\s*v?(\d+)/.exec(range.trim());
  if (!m) {
    bail(2, [
      `Runtime support: engines.node is ${JSON.stringify(range)}, which this gate`,
      "cannot read as a floor. It understands '>=N' only.",
      "",
      "Fix: use a '>=N' range, or teach this gate the richer syntax. Do not",
      "loosen the gate to skip what it cannot parse - that is how a support",
      "claim rots unobserved.",
    ]);
  }
  return Number(m[1]);
}

// ---------------------------------------------------------------------------
// Every Node major any workflow asks for, and where it came from.
//
// SCOPE, and why it is two directories and not one
//
//   .github/workflows/  - what this repository RUNS. A pin below the floor
//                         here means CI proves the package on a runtime the
//                         package does not claim to support.
//   assets/governance/  - what this repository SHIPS. `aahp init --gates`
//                         copies aahp-govern.yml from here into a consumer
//                         repository and `npm pack` puts it in the published
//                         tarball, so a pin below the floor here is a support
//                         claim that breaks on install, in repositories this
//                         gate will never run in.
//
// Measured 2026-08-23: the shipped template pinned Node 20 while engines.node
// said '>=22', and had done so while this gate ran green on every commit -
// because the gate read one directory and the defect sat in the other. The
// header above blames this exact class of defect on the file the package
// propagates, and then scanned only the copy that propagates via propagate.sh.
// The consumer-facing copy travels a second route (`aahp init --gates`) that
// nothing here was looking at.
//
// Two sibling gates already hold the shipped template to the same bar as the
// local workflows - tests/assert-workflow-hardening.mjs (SCAN_ROOTS) and
// scripts/check-workflow-pinning.mjs (TEMPLATE_DIRS). This list is the third,
// and the divergence is the reason to keep all three named together: a new
// gate over workflows is wrong by default until it states which route it
// covers.
//
// WHAT AN ABSENT ROOT MEANS, and why the two answers differ
//
// For .github/workflows absence is exit 2. This gate asserts a relation
// between runtime pins and a support claim; with no workflows the relation is
// UNTESTED, not satisfied, and "I could not look" must never read as "I looked
// and it was fine".
//
// For assets/governance absence is not a finding at all, because the gate also
// runs against roots that legitimately ship nothing - every fixture in
// tests/runtime-support.bats is such a root, and so is any consumer project if
// this gate ever becomes portable. A package that ships no template has no
// template to get wrong.
//
// That asymmetry is a real hole: silently dropping the root by renaming or
// deleting the directory would return this gate to the blindness described
// above, and nothing would go red. It is closed on the OTHER side - the summary
// below names every file actually scanned, and tests/runtime-support.bats
// asserts that the real repository's shipped template appears in it. Coverage
// is therefore proved by observation of the real tree, not assumed from a flag.
// ---------------------------------------------------------------------------
const SCAN_ROOTS = [
  {
    dir: [".github", "workflows"],
    label: ".github/workflows",
    why: "what this repository runs",
    required: true,
    shipped: false,
  },
  {
    dir: ["assets", "governance"],
    label: "assets/governance",
    why: "the workflow template `aahp init --gates` copies into consumer repositories",
    required: false,
    shipped: true,
  },
];

// Returns { dir, file, label } for every YAML file under every scan root.
// `label` is what findings name, so a message reads
// `assets/governance/aahp-govern.yml:govern` rather than a bare filename - two
// roots can hold files of the same name, and the route a file travels is the
// whole point of scanning it.
function workflowFiles() {
  const found = [];
  for (const scan of SCAN_ROOTS) {
    const dir = join(root, ...scan.dir);
    if (!existsSync(dir)) {
      if (!scan.required) continue;
      bail(2, [
        `Runtime support: no workflow directory at ${dir}.`,
        "This gate asserts a relation between CI pins and the published support",
        "claim. With no workflows there are no pins, so the relation is untested",
        "rather than satisfied.",
      ]);
    }
    const files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f)).sort();
    if (files.length === 0) {
      if (!scan.required) continue;
      bail(2, [`Runtime support: ${dir} contains no workflow files.`]);
    }
    for (const file of files) {
      found.push({ dir, file, label: `${scan.label}/${file}`, shipped: scan.shipped });
    }
  }
  return found;
}

function majorOf(value, where) {
  const m = /^v?(\d+)/.exec(String(value).trim());
  if (!m) {
    bail(1, [
      `Runtime support: ${where} pins node-version to ${JSON.stringify(String(value))},`,
      "which does not begin with a Node major.",
    ]);
  }
  return Number(m[1]);
}

function parseWorkflow({ dir, file, label }) {
  const text = readFileSync(join(dir, file), "utf8");
  try {
    return YAML.parse(text) ?? {};
  } catch (err) {
    bail(2, [
      `Runtime support: ${label} is not valid YAML (${err.message}).`,
      "The gate refuses to guess at a file it cannot parse.",
    ]);
  }
}

// Pins contributed by a job's strategy matrix, kept SEPARATE from the step pins
// on purpose - see the trap recorded in the header. The union of the two cannot
// answer "did the matrix survive", which is the question the vacuity guard asks.
function matrixMajors(job, where) {
  const matrix = job?.strategy?.matrix?.["node-version"];
  if (!Array.isArray(matrix)) return [];
  return matrix.map((v) => majorOf(v, `${where} matrix`));
}

function stepMajors(job, where) {
  const majors = [];
  for (const step of Array.isArray(job?.steps) ? job.steps : []) {
    const w = step?.with;
    if (!w || typeof w !== "object") continue;

    if (w["node-version-file"] !== undefined) {
      bail(1, [
        `Runtime support: ${where} selects its runtime with node-version-file`,
        `(${JSON.stringify(String(w["node-version-file"]))}), which this gate cannot`,
        "evaluate. An unreadable pin must fail rather than be skipped, because a",
        "gate that drops what it cannot parse reports a repo it never read.",
        "",
        "Fix: pin a literal major here, or teach this gate to resolve the file.",
      ]);
    }

    const raw = w["node-version"];
    if (raw === undefined || raw === null) continue;
    const text = String(raw);

    // A matrix reference is already accounted for by matrixMajors().
    if (/\$\{\{\s*matrix\./.test(text)) continue;

    if (text.includes("${{")) {
      bail(1, [
        `Runtime support: ${where} pins node-version to an expression this gate`,
        `cannot evaluate (${text}).`,
        "",
        "Fix: use a literal major, or a matrix reference.",
      ]);
    }
    majors.push(majorOf(text, `${where} step`));
  }
  return majors;
}

const pins = [];
const allMatrixMajors = [];

for (const entry of workflowFiles()) {
  const doc = parseWorkflow(entry);
  const jobs = doc?.jobs;
  if (!jobs || typeof jobs !== "object") continue;
  for (const [jobName, job] of Object.entries(jobs)) {
    const where = `${entry.label}:${jobName}`;
    const fromMatrix = matrixMajors(job, where);
    const fromSteps = stepMajors(job, where);
    allMatrixMajors.push(...fromMatrix);
    const majors = [...fromMatrix, ...fromSteps];
    if (majors.length > 0) pins.push({ where, job: jobName, majors, shipped: entry.shipped });
  }
}

const floor = enginesFloor();
const failures = [];

// --- 1. Vacuity guards, first, because everything below is vacuously true over
// --- an empty pin list.
if (pins.length === 0) {
  bail(1, [
    "Runtime support: no node-version pin found in any workflow.",
    "Every other check in this gate is vacuously true over an empty list, so",
    "this means the gate is asserting nothing at all.",
  ]);
}

// Bind the MATRIX, not the union it feeds. Emptying the matrix while standalone
// step pins remain is the exact mutation that left a sibling gate green.
if (allMatrixMajors.length < 2) {
  failures.push(
    `the build matrix exercises ${allMatrixMajors.length} runtime(s) ` +
      `(${allMatrixMajors.join(", ") || "none"}), but engines.node publishes a RANGE (>=${floor}). ` +
      `A package that claims a range and tests one point of it is asserting compatibility ` +
      `it never checked. Emptying or single-valuing strategy.matrix.node-version must not be silent.`,
  );
}

// --- 2. Every runtime a scanned workflow asks for satisfies the published range.
//
// The relation is the same for both scan roots; the CONSEQUENCE is not, so the
// message is not. A local pin below the floor means this repository's own CI
// vouches for a runtime the package disclaims. A shipped pin below the floor
// means every adopter that scaffolds the template runs the published CLI below
// its own engine floor - and npm reports that as EBADENGINE and keeps going, so
// nothing in the adopter's CI turns red either.
for (const { where, majors, shipped } of pins) {
  for (const major of majors) {
    if (major < floor) {
      failures.push(
        shipped
          ? `${where} scaffolds consumers onto Node ${major}, below the engines.node floor ` +
            `of ${floor}. This file is copied into adopting repositories verbatim, so the ` +
            `pin runs the published CLI under its own engine floor there. npm answers an ` +
            `unmet engines range with EBADENGINE and continues, so the adopter's CI stays ` +
            `green while running unsupported - the defect is invisible at both ends.`
          : `${where} runs on Node ${major}, below the engines.node floor of ${floor}. ` +
            `CI would prove the package works on a runtime it does not claim to support, ` +
            `or on one that tooling has already dropped.`,
      );
    }
  }
}

// --- 3. The published floor is a runtime that still gets security patches.
if (floor < SUPPORTED_FLOOR) {
  failures.push(
    `engines.node claims support from Node ${floor}, but the oldest runtime still receiving ` +
      `security patches is ${SUPPORTED_FLOOR} (measured 2026-08-21). Every repository in the ` +
      `estate consumes this package and inherits this claim, so publishing support for an ` +
      `unpatched runtime advertises it fleet-wide.`,
  );
}

// --- 4. The release path only runs on runtimes the build path actually proved.
//
// This started as "release major >= lowest build major" and that version was
// DEAD ON ARRIVAL here: the lowest build pin is the floor itself, so the only way
// to get a lower release pin was to drop it below the floor - which check 2
// already catches. The predicate could never fire on its own, which is the same
// defect as a gate that cannot go red. The mutation proof is what surfaced it.
//
// The invariant that actually matters is MEMBERSHIP, not ordering: the runtime
// that publishes must be one some build or test job really ran. That fires
// independently in both directions - a release pinned BELOW the tested set and a
// release pinned ABOVE it are both untested release paths.
// SHIPPED PINS ARE EXCLUDED HERE, and only here. Check 2 applies to every
// pin the gate can see, because a runtime below the published floor is wrong
// wherever it appears. Check 4 is different: it asks whether THIS
// repository's release path runs on a runtime THIS repository's build path
// proved. A job in assets/governance never runs here at all, so counting it
// as a build job would let the shipped template vouch for a release runtime
// nothing ever executed - the template would widen buildMajors and silence a
// real finding. A gate scoped wider must not become a gate that asserts less.
const majorsOf = (predicate) =>
  new Set(pins.filter((p) => !p.shipped && predicate(p.job)).flatMap((p) => p.majors));

const buildMajors = majorsOf((j) => !RELEASE_JOB.test(j));
const releaseMajors = majorsOf((j) => RELEASE_JOB.test(j));
const buildList = [...buildMajors].sort((a, b) => a - b);

if (buildMajors.size > 0) {
  for (const major of [...releaseMajors].sort((a, b) => a - b)) {
    if (!buildMajors.has(major)) {
      failures.push(
        `the release path runs on Node ${major}, which no build or test job exercises ` +
          `(they run ${buildList.join(", ")}). A release then happens on a runtime nothing ` +
          `proved the package works on: every check passes and the publish step is the ` +
          `first thing to ever touch that runtime.`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error("\n  Runtime support check failed.\n");
  for (const f of failures) console.error(`  - ${f}\n`);
  console.error(
    "  The runtimes CI exercises and the runtimes package.json publishes must be\n" +
      "  the same set, and its floor must still be supported upstream.\n",
  );
  process.exit(1);
}

const summary = pins
  .map(({ where, majors }) => `${where} -> ${[...new Set(majors)].sort((a, b) => a - b).join(", ")}`)
  .join("\n    ");
console.log(
  `Runtime support OK: engines.node >=${floor} (supported floor ${SUPPORTED_FLOOR}), ` +
    `matrix exercises ${[...new Set(allMatrixMajors)].sort((a, b) => a - b).join(" and ")}.\n    ${summary}`,
);
