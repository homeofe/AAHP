#!/usr/bin/env node
// check-workflow-pinning.mjs - Whatever a workflow installs and then executes
// must come from the committed lockfile, and the lockfile must pin it by hash.
// Whatever a workflow USES must name a commit its author cannot repoint, and an
// update lane must exist to move that pin forward.
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
// AND THE SECOND TIME, THE GATE ITSELF WAS THE CONVENTION
// ---------------------------------------------------------------------------
// Measured 2026-08-23 on `main` at 2cdaf48. This file was named
// check-workflow-PINNING, ran inside the required `lint-and-validate` check on
// every pull request, and exited 0 - while 22 of this repository's 25 `uses:`
// references ran on mutable major tags (`actions/checkout@v4` and friends). A
// tag is whatever its owner last pointed it at, so those 22 lines were
// "pinned-looking" and not pinned.
//
// The gate did not miss them. It never looked at them. Rules A to D read only
// `step.run`, the shell text of a step; the scan loop skips every step without
// one, which is every `uses:` step there is. So the gate's SCOPE was npm
// packages inside workflows, while its NAME promised workflow pinning, and the
// difference was invisible from a green check. That is the same failure shape as
// the one above, one level up: a convention (pin your actions, as
// aahp-verify.yml did) applied by hand in the one file where it would be seen.
//
// Rules E and F below are the missing reader. Rule F is the half that is easy to
// leave out: `.github/dependabot.yml` named only the npm ecosystem, and an
// ecosystem that is not named is not scanned - which produces no pull request,
// exactly like an ecosystem that is up to date. The pull-request count therefore
// could not distinguish "nothing to update" from "nothing is looking", and a pin
// with nothing offering to move it stops at whatever the pinned commit turns out
// to contain.
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
//   E. Every `uses:` in a scanned workflow names an immutable reference, and
//      says in a trailing comment which release that is. For an action or a
//      reusable workflow that means a full 40-character commit SHA; for a
//      `docker://` image it means an `@sha256:` digest. A tag - `@v4`, `@main`,
//      `@latest` - is a pointer its owner can move at any time, with no diff
//      here to review, so a tag reference is not a pin no matter how stable the
//      tag has been. The trailing `# vX.Y.Z` is not decoration: a bare SHA is
//      unreadable in review, and Dependabot rewrites the SHA and that comment
//      together, so the comment stays true rather than rotting.
//      MUTATION: change any `uses:` back to `@v4`, or delete its trailing
//      comment.
//      A local action (`uses: ./path`) is exempt and counted separately: it has
//      no ref to pin, because its bytes are the bytes of this commit.
//
//   F. `.github/dependabot.yml` declares a `github-actions` ecosystem covering
//      the workflow directory. Rule E freezes the references; this is what
//      thaws them on purpose. Asked only when the LOCAL workflow directory
//      actually contains a remote `uses:` - with none there is nothing for the
//      lane to update, and the summary line says so rather than counting it as
//      a pass. MUTATION: delete the `github-actions` entry from
//      .github/dependabot.yml, or point its `directory` somewhere else.
//
//   G. An action repository used through more than one SUB-PATH is covered by a
//      `groups:` entry in that lane. Dependabot resolves each sub-path as its own
//      dependency, so an ungrouped multi-path action arrives as one pull request
//      per path. For github/codeql-action that has no green state at all: the
//      action refuses to run when init, autobuild and analyze are on different
//      versions, so every single-path pull request fails with "Not all workflow
//      steps that use github/codeql-action actions use the same version". The
//      three refs have to move in one commit, and only a group makes Dependabot
//      produce one. Stated as a property of multi-path actions, not as a codeql
//      special case, so the next action shipped this way is covered too.
//      MUTATION: delete the `groups:` block from the `github-actions` lane in
//      .github/dependabot.yml, or narrow its pattern so it stops matching.
//      NOT asserted, and said out loud rather than implied: whether Dependabot
//      is enabled for the repository at all, and whether it has ever opened a
//      pull request. Both are off-machine facts this gate cannot read from the
//      tree. Measure them with
//      `gh pr list -R <repo> --author app/dependabot --state all`.
//
// Global installs are covered too. The repository used to run
// `npm install -g npm@latest` immediately before publishing while holding
// `id-token: write`. Node 24 already ships an npm version new enough for trusted
// publishing, so that install was deleted and global installs are now rejected
// by the same lockfile rule instead of remaining a permanent exception.
//
// ALSO OUT OF SCOPE, for the same reason: whether a pinned SHA is STALE. Rule E
// proves the reference cannot be repointed, not that it is current, and those
// are different properties. Rule F is the answer to staleness, and it is an
// update lane rather than an assertion because "current" is a fact about the
// upstream repository, not about this tree.
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
//      package-lock.json, unreadable or unparseable .github/dependabot.yml).
//      Never 0: "I could not look" must not read as "I looked and it was fine".
//
// A dependabot.yml that is ABSENT is exit 1, not exit 2. That is not a state
// this gate failed to read; it is the finding itself, and it is the exact state
// this repository was in.
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

// An exact version: no caret, tilde, range, tag, URL or git ref.
// At most ONE prerelease run and at most ONE build run, deliberately: a
// repeated group whose character class also contains its own delimiter is
// exponentially ambiguous, and package.json is attacker-supplied on a fork
// pull request. Reported by CodeQL js/redos against the earlier form.
const EXACT_VERSION = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.]+)?$/;

// The immutable forms of a `uses:` reference. Anchored and fixed-length on both
// sides, so neither can walk: a git commit is exactly 40 lowercase hex, a
// registry digest exactly 64 after `sha256:`.
const COMMIT_SHA = /^[0-9a-f]{40}$/;
const IMAGE_DIGEST = /^sha256:[0-9a-f]{64}$/;

// The trailing comment must say which release the SHA is, and be checkable as
// such. Dependabot writes `# v4.2.2`; a lone word would satisfy "has a comment"
// while telling a reviewer nothing.
const VERSION_COMMENT = /(?:^|\s)v?\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.-]+)?(?:\s|$)/;

// The ecosystem name Dependabot uses for `uses:` references, and the directory
// value that covers `.github/workflows`.
const ACTIONS_ECOSYSTEM = "github-actions";
const WORKFLOW_ROOT_DIRECTORY = "/";

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
// Rules A, B, C and E, over every scanned workflow.
// ---------------------------------------------------------------------------
const findings = [];
const npxTargets = [];
const usesRefs = [];
let localActionRefs = 0;

// Parsed once as a DOCUMENT rather than twice: rules A to D need the plain
// JavaScript value, and rule E needs the trailing comment on the `uses:` scalar,
// which the plain value does not carry. `parseDocument` collects errors instead
// of throwing, so the error check below is explicit rather than a caught
// exception - a document with errors would otherwise return a half-read tree
// that reads as clean.
function parseWorkflow(file) {
  let text;
  try {
    text = readFileSync(file.abs, "utf8");
  } catch (err) {
    bail(2, [`Workflow pinning: cannot read ${file.rel} (${err.message}).`]);
  }
  const lineCounter = new YAML.LineCounter();
  let doc;
  try {
    doc = YAML.parseDocument(text, { lineCounter });
  } catch (err) {
    bail(2, [
      `Workflow pinning: ${file.rel} is not valid YAML (${err.message}).`,
      "The gate refuses to guess at a file it cannot parse.",
    ]);
  }
  if (doc.errors.length > 0) {
    bail(2, [
      `Workflow pinning: ${file.rel} is not valid YAML (${doc.errors[0].message}).`,
      "The gate refuses to guess at a file it cannot parse.",
    ]);
  }
  return { doc, lineCounter, value: doc.toJS() ?? {} };
}

// Rule E, over the parsed document. Every `uses:` anywhere in the file is
// collected, not only the ones under `jobs.*.steps`: a reusable-workflow call
// sits at `jobs.<id>.uses`, and a `uses:` this gate does not recognise the
// position of is still a reference GitHub will resolve and run.
function collectUses(file, { doc, lineCounter }) {
  YAML.visit(doc, {
    Pair(_index, pair) {
      if (!pair.key || pair.key.value !== "uses") return;
      const node = pair.value;
      const line = node?.range ? lineCounter.linePos(node.range[0]).line : 0;
      const where = `${file.rel}:${line}`;
      if (typeof node?.value !== "string") {
        findings.push({
          where,
          command: "uses:",
          message:
            "has a `uses:` whose value is not a plain string, so nothing here can say " +
            "which commit it resolves to. Write the reference literally.",
        });
        return;
      }
      usesRefs.push({ where, ref: node.value, comment: typeof node.comment === "string" ? node.comment : null });
    },
  });
}

for (const file of scanned) {
  const parsed = parseWorkflow(file);
  collectUses(file, parsed);
  const doc = parsed.value;
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
// Rule E: every `uses:` names a commit its owner cannot repoint, and says which
// release that commit is.
//
// The reference is split at the LAST `@`, because the path half may legitimately
// contain none and the ref half never contains one:
// `github/codeql-action/init@<sha>`.
// ---------------------------------------------------------------------------
let remoteUsesRefs = 0;

for (const { where, ref, comment } of usesRefs) {
  if (ref.startsWith("./") || ref.startsWith(".\\")) {
    // A local action is the bytes of this commit. There is no ref to pin, and
    // counting it as pinned would overstate what was checked.
    localActionRefs += 1;
    continue;
  }

  remoteUsesRefs += 1;
  const at = ref.lastIndexOf("@");
  const target = at === -1 ? "" : ref.slice(at + 1);

  if (ref.startsWith("docker://")) {
    if (!IMAGE_DIGEST.test(target)) {
      findings.push({
        where,
        command: `uses: ${ref}`,
        message:
          "runs a container image by tag. A registry tag is repointable by whoever " +
          "owns the repository, so it names no particular bytes. Pin it to an " +
          "`@sha256:` digest.",
      });
    }
    continue;
  }

  if (!COMMIT_SHA.test(target)) {
    findings.push({
      where,
      command: `uses: ${ref}`,
      message:
        `resolves the mutable ref ${JSON.stringify(at === -1 ? "(none)" : target)} at run time. ` +
        "Whoever owns that action chooses which commit a tag or branch points at, and can " +
        "repoint it with no diff here to review, so this is not pinned. Use the full " +
        "40-character commit SHA with the release in a trailing comment.",
    });
    continue;
  }

  if (comment === null || !VERSION_COMMENT.test(comment)) {
    findings.push({
      where,
      command: `uses: ${ref}`,
      message:
        "is pinned to a commit but carries no trailing comment naming the release. A bare " +
        "SHA is unreviewable, and Dependabot rewrites the SHA and the comment together, so " +
        "the comment is what keeps the version readable AND true. Add `# vX.Y.Z`.",
    });
  }
}

// ---------------------------------------------------------------------------
// Rule F: something has to offer to move those pins.
//
// Asked only when the LOCAL workflow directory holds at least one remote `uses:`.
// A tree with none has nothing for the lane to update, and that is reported on
// the summary line as not asserted rather than counted as a pass.
// ---------------------------------------------------------------------------
const localUsesCount = usesRefs.filter(
  ({ where, ref }) =>
    where.startsWith(`${WORKFLOW_DIR.replace(/\\/g, "/")}/`) && !ref.startsWith("./") && !ref.startsWith(".\\"),
).length;

let dependabotVerdict = "not asserted: no remote `uses:` in the workflow directory";

if (localUsesCount > 0) {
  const candidates = [join(".github", "dependabot.yml"), join(".github", "dependabot.yaml")];
  const present = candidates.filter((rel) => existsSync(join(root, rel)));

  if (present.length === 0) {
    findings.push({
      where: ".github/dependabot.yml",
      command: `package-ecosystem: "${ACTIONS_ECOSYSTEM}"`,
      message:
        `is missing: there is no Dependabot configuration at all, so nothing offers to move ` +
        `the ${localUsesCount} pinned action reference(s) in ${WORKFLOW_DIR.replace(/\\/g, "/")}. ` +
        "A pin with no update lane stops at whatever the pinned commit turns out to contain, " +
        "and the absence looks exactly like an ecosystem with nothing to update: no pull " +
        "request either way.",
    });
  } else {
    const rel = present[0].replace(/\\/g, "/");
    let cfg;
    try {
      cfg = YAML.parse(readFileSync(join(root, present[0]), "utf8"));
    } catch (err) {
      bail(2, [
        `Workflow pinning: ${rel} is not valid YAML (${err.message}).`,
        "A Dependabot configuration that does not parse is not a configuration: GitHub",
        "rejects the whole file, so EVERY lane in it stops, including the npm one. The",
        "gate refuses to guess at it.",
      ]);
    }
    const updates = Array.isArray(cfg?.updates) ? cfg.updates : null;
    if (updates === null) {
      bail(2, [
        `Workflow pinning: ${rel} has no \`updates\` list.`,
        `This gate reads the Dependabot v2 shape; this file reports version ${JSON.stringify(cfg?.version)}.`,
        "It refuses to report a clean result over a shape it cannot read.",
      ]);
    }
    const actionsLanes = updates.filter((u) => u?.["package-ecosystem"] === ACTIONS_ECOSYSTEM);
    if (actionsLanes.length === 0) {
      findings.push({
        where: rel,
        command: `package-ecosystem: "${ACTIONS_ECOSYSTEM}"`,
        message:
          `is not declared, so Dependabot never scans the ${localUsesCount} action reference(s) ` +
          `in ${WORKFLOW_DIR.replace(/\\/g, "/")}. An ecosystem that is not named here produces ` +
          "no pull request, which is indistinguishable from an ecosystem that is up to date - " +
          "so the pull-request count cannot tell you this lane is missing. Measure the " +
          "ecosystem list.",
      });
    } else {
      // `directory` (one path) and `directories` (a list) are both accepted by
      // Dependabot. Either has to cover the workflow root, or the lane exists
      // and looks somewhere else, which is a lane that reads no workflow here.
      const covers = actionsLanes.some((lane) => {
        const dirs = Array.isArray(lane.directories)
          ? lane.directories
          : lane.directory !== undefined
            ? [lane.directory]
            : [];
        return dirs.some((d) => String(d) === WORKFLOW_ROOT_DIRECTORY);
      });
      if (!covers) {
        findings.push({
          where: rel,
          command: `package-ecosystem: "${ACTIONS_ECOSYSTEM}"`,
          message:
            `is declared but no lane covers ${JSON.stringify(WORKFLOW_ROOT_DIRECTORY)}. For this ` +
            `ecosystem Dependabot reads ${WORKFLOW_DIR.replace(/\\/g, "/")} under the named ` +
            "directory, so a lane pointed elsewhere scans no workflow in this repository while " +
            "still appearing in the configuration.",
        });
      } else {
        dependabotVerdict = `${rel} declares a ${ACTIONS_ECOSYSTEM} lane covering ${WORKFLOW_ROOT_DIRECTORY}`;
      }

      // Rule G. Which action repositories does this tree use through more than one
      // sub-path? Those are the ones Dependabot will split, so those are the ones a
      // group has to cover. Derived from the refs actually present rather than from
      // a hardcoded list, so it does not go stale when the workflows change.
      const subPathsByRepo = new Map();
      for (const { ref } of usesRefs) {
        if (typeof ref !== "string") continue;
        if (ref.startsWith("./") || ref.startsWith("docker://")) continue;
        const at = ref.lastIndexOf("@");
        const path = at === -1 ? ref : ref.slice(0, at);
        const parts = path.split("/");
        if (parts.length < 3) continue;
        const repo = `${parts[0]}/${parts[1]}`;
        if (!subPathsByRepo.has(repo)) subPathsByRepo.set(repo, new Set());
        subPathsByRepo.get(repo).add(path);
      }
      const multiPath = [...subPathsByRepo.entries()].filter(([, s]) => s.size > 1);

      // Dependabot's group patterns are globs over the dependency NAME, which for
      // this ecosystem is the full `owner/repo/sub/path`. A group matching any one
      // of an action's sub-paths does not help, so every sub-path must match.
      const groupPatterns = [];
      for (const lane of actionsLanes) {
        for (const g of Object.values(lane.groups ?? {})) {
          for (const pat of g?.patterns ?? []) groupPatterns.push(String(pat));
        }
      }
      const globToRe = (pattern) =>
        new RegExp(
          "^" +
            pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") +
            "$",
        );
      const groupRes = groupPatterns.map(globToRe);

      for (const [repo, paths] of multiPath) {
        const uncovered = [...paths].filter((p) => !groupRes.some((re) => re.test(p)));
        if (uncovered.length > 0) {
          findings.push({
            where: rel,
            command: `groups: (covering ${repo})`,
            message:
              `is missing: ${repo} is used through ${paths.size} sub-paths ` +
              `(${[...paths].sort().join(", ")}) and Dependabot resolves each as its own ` +
              "dependency, so it opens one pull request per path. An action that requires " +
              "its steps to be on the same version then has NO green single-path change: " +
              "each pull request is correct and each one fails. Add a `groups:` entry " +
              `matching all of them, for example \`"${repo}*"\`. ` +
              `Not matched by any current pattern: ${uncovered.sort().join(", ")}.`,
          });
        }
      }
    }
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
    `${Object.keys(declared).length} direct dependencies locked by hash, ` +
    `${remoteUsesRefs} action reference(s) pinned to an immutable ref` +
    `${localActionRefs > 0 ? `, ${localActionRefs} local action reference(s) exempt` : ""}.`,
);
// Printed on a PASSING run on purpose. Rule F is the one whose satisfied state
// is invisible - a working lane and a missing lane both look like an inbox with
// no Dependabot pull request in it - so the verdict is stated rather than left
// to be inferred from the absence of a finding.
console.log(`    Dependabot lane: ${dependabotVerdict}`);
console.log(
  "    Not asserted here: whether Dependabot is enabled for this repository, and whether it has",
);
console.log(
  "    ever opened a pull request. Measure with `gh pr list --author app/dependabot --state all`.",
);
for (const file of scanned) console.log(`    ${file.rel}`);
