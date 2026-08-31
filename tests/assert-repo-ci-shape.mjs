#!/usr/bin/env node
// assert-repo-ci-shape.mjs - repository-shape assertions for runtime-support.bats.
//
// Kept as a file rather than inlined into `node -e` on purpose: under Git Bash
// (MSYS) a POSIX-looking path INSIDE a quoted -e string is not converted for the
// native node binary, so `require('/c/Users/.../package.json')` fails with
// MODULE_NOT_FOUND and the test reports a defect that does not exist. A path
// passed as an argv element IS converted, so the repo root arrives here intact.
//
// Five things are asserted, and none of them is about a gate's own logic:
//
//   1. The runtime-support gate is actually INVOKED by the aggregate `check`
//      chain. A gate that exists but never runs protects nothing.
//   2. The required status check keeps its literal name. 'lint-and-validate' is
//      required by exact name on main; giving that job a strategy.matrix renames
//      its checks to 'lint-and-validate (22)' and the required context then never
//      reports again - every pull request blocked, with zero red checks to
//      explain why. The second runtime therefore belongs in runtime-matrix.
//   3. The two release-critical jobs in ci.yml share ONE definition of "this ref
//      is a release", and the publish job carries no unrecorded permission to run
//      beyond it. See section 3 below for why, and for what is deliberately left
//      open.
//   4. The three jobs that need MORE than the top-level `contents: read` still
//      declare it. A job-level `permissions:` REPLACES the top-level block
//      rather than merging with it, so once ci.yml and codeql.yml gained a
//      top-level `contents: read`, deleting a job-level block as "redundant"
//      would silently strip an elevation. Each of the three is listed with the
//      step that stops working without it. The root is an argument, so a root
//      that does not contain one of those workflows gets that elevation named
//      on stderr as NOT asserted; see the comment above the loop in section 4.
//   5. The list in section 3 and the ADR that DOCUMENTS it say the same thing.
//      Section 3 pinned publish authorization to a literal list inside this test
//      file; the record a reader actually reaches for is ADR-019 in README.md,
//      and nothing compared the two. Either could be edited alone. Section 5
//      compares them as SETS, in both directions, so a change to publish
//      authorization is a three-part edit - the workflow, the list, the ADR -
//      that a reviewer meets in one diff. It changes no workflow behaviour.
//
// Assertions 3 and 4 were written on two branches that never saw each other,
// each growing this same region out of one 63-line ancestor. Both are here. The
// count above is the thing a reader checks first: if this file ever says five
// and holds four, one of them was dropped in a reconciliation.
//
// Exit codes: 0 when every assertion holds, 1 when at least one does not. There
// is no third code. An input this file can SEE but cannot trust is a FAILURE -
// present and unreadable, not valid YAML, or parsing to an empty document -
// because "I could not look" must never read as "I looked and it was fine".
// The single state that is neither pass nor fail is a recorded workflow the
// given root does not contain AT ALL. That elevation is named on stderr as not
// asserted (section 4) instead of being guessed in either direction, and it
// cannot hollow this gate out: ci.yml is mandatory below and carries two of the
// three recorded elevations, so a root that asserts nothing at all has already
// failed on the ci.yml finding.
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

// ─── 3. One definition of a release, and no unrecorded path to npm publish ───
//
// ci.yml has two release-critical jobs. `publish` runs `npm publish --access
// public --provenance` with `id-token: write`; `release` creates the GitHub
// Release for the same ref. Each carried its own hand-written `if:`, and the two
// drifted: `publish` additionally accepted `workflow_dispatch`, an operand that
// constrains no ref at all, so two jobs in one file answered "is this a release?"
// differently and the looser answer was the one wired to the public registry.
//
// The drift is not the part that mattered. NOTHING in this repository read either
// condition, so the disagreement was invisible and any future edit to publish
// authorization would have been equally silent. This section is the missing
// reader. Reported at https://github.com/homeofe/AAHP/issues/69.
//
// SETTLED 2026-08-23 as ADR-019 option A. The operand is removed and this list is
// empty; the assertion below now proves the two conditions are identical, and that
// re-adding any operand requires editing this file and ADR-019 in the same commit.
//
// It is a CHANGE DETECTOR for the settled policy. It pins both conditions to the
// state this repository recorded, so changing either one becomes a two-part edit -
// the workflow and ADR-019 - that a reviewer meets in a single diff.
//
// It reads the PARSED condition from the YAML, never a substring of the file, so
// reformatting the workflow cannot turn the assertion green or red on its own.

// The single definition of "this ref is a release", written once. Both jobs must
// use exactly this expression. That is the half of issue 69 which is not a policy
// question: two jobs in one file must not disagree about what a release is.
const RELEASE_REF_CONDITION =
  "startsWith(github.ref, 'refs/tags/v') && contains(github.ref, '.')";

// Top-level `||` operands that jobs.publish.if carries BEYOND the shared release
// definition, written exactly as recorded in the comment above that condition in
// ci.yml. Each entry is a standing permission to publish to npm on something that
// is not a release tag, so this list is deliberately literal: no patterns, no
// wildcard entry, and an empty list is a meaningful state rather than "unchecked".
//
// Settled as ADR-019 option A on 2026-08-23: the operand is gone and the two
// conditions are identical, so there is nothing beyond the release definition to
// record. The list stays, and stays asserted in both directions, because it is what
// makes re-adding a path to npm publish a visible edit rather than a quiet one.
const PUBLISH_CONDITIONS_BEYOND_RELEASE = [];

/**
 * Collapse every run of whitespace outside single-quoted literals to one space.
 * Actions expressions quote with `'` and escape a quote by doubling it, so a
 * literal is left byte-for-byte intact; collapsing inside one would change what
 * the expression means. Returns null on an unterminated literal.
 */
function collapseOutsideLiterals(expr) {
  let out = "";
  let inLiteral = false;
  for (let i = 0; i < expr.length; i += 1) {
    const c = expr[i];
    if (inLiteral) {
      out += c;
      if (c === "'") {
        if (expr[i + 1] === "'") {
          out += "'";
          i += 1;
        } else {
          inLiteral = false;
        }
      }
      continue;
    }
    if (c === "'") {
      inLiteral = true;
      out += c;
      continue;
    }
    if (c === " " || c === "\t" || c === "\n" || c === "\r") {
      if (out.length > 0 && !out.endsWith(" ")) out += " ";
      continue;
    }
    out += c;
  }
  return inLiteral ? null : out.trim();
}

/**
 * True when the whole expression is one parenthesised group, so that dropping the
 * first and last character cannot change how it binds. `(a) || (b)` is not, and
 * must keep its parentheses.
 */
function isSingleParenthesisedGroup(expr) {
  let depth = 0;
  let inLiteral = false;
  for (let i = 0; i < expr.length; i += 1) {
    const c = expr[i];
    if (inLiteral) {
      if (c === "'") {
        if (expr[i + 1] === "'") i += 1;
        else inLiteral = false;
      }
      continue;
    }
    if (c === "'") {
      inLiteral = true;
      continue;
    }
    if (c === "(") {
      depth += 1;
    } else if (c === ")") {
      depth -= 1;
      if (depth < 0) return false;
      if (depth === 0) return i === expr.length - 1;
    }
  }
  return false;
}

/** Drop redundant enclosing parentheses: `(a && b)` becomes `a && b`. */
function stripEnclosingParens(expr) {
  let s = expr.trim();
  while (s.startsWith("(") && s.endsWith(")") && isSingleParenthesisedGroup(s)) {
    s = s.slice(1, -1).trim();
  }
  return s;
}

/**
 * The `[start, end)` spans of the top-level `||` operands, or null when the
 * expression is malformed (unbalanced parentheses, unterminated literal). `||`
 * inside a parenthesised group or a quoted literal is not a top-level operator.
 */
function topLevelOrSpans(expr) {
  const spans = [];
  let depth = 0;
  let inLiteral = false;
  let start = 0;
  for (let i = 0; i < expr.length; i += 1) {
    const c = expr[i];
    if (inLiteral) {
      if (c === "'") {
        if (expr[i + 1] === "'") i += 1;
        else inLiteral = false;
      }
      continue;
    }
    if (c === "'") {
      inLiteral = true;
      continue;
    }
    if (c === "(") {
      depth += 1;
    } else if (c === ")") {
      depth -= 1;
      if (depth < 0) return null;
    } else if (c === "|" && expr[i + 1] === "|" && depth === 0) {
      spans.push([start, i]);
      start = i + 2;
      i += 1;
    }
  }
  if (inLiteral || depth !== 0) return null;
  spans.push([start, expr.length]);
  return spans;
}

/**
 * Split a GitHub Actions `if:` condition into its normalised top-level `||`
 * operands, or null when it cannot be read. An empty operand (`a || || b`) is
 * malformed and also yields null.
 */
function splitTopLevelOr(expr) {
  const collapsed = collapseOutsideLiterals(expr);
  if (collapsed === null) return null;
  const spans = topLevelOrSpans(collapsed);
  if (spans === null) return null;
  const operands = [];
  for (const [from, to] of spans) {
    const operand = stripEnclosingParens(collapsed.slice(from, to));
    if (operand === "") return null;
    operands.push(operand);
  }
  return operands;
}

/** Normalise a whole condition for comparison, or null when it cannot be read. */
function normaliseCondition(expr) {
  const collapsed = collapseOutsideLiterals(expr);
  if (collapsed === null) return null;
  return stripEnclosingParens(collapsed);
}

/** Message for a release job that has stopped using the shared definition. */
function releaseDefinitionMessage(found) {
  return (
    "jobs.release.if is not the recorded release definition.\n" +
    `      recorded: ${RELEASE_REF_CONDITION}\n` +
    `      found:    ${found ?? "(unreadable: unterminated quoted literal)"}\n` +
    "      Both release-critical jobs must answer 'is this a release?' with one " +
    "expression. If the definition itself is meant to change, change " +
    "RELEASE_REF_CONDITION in this file and both jobs in ci.yml together."
  );
}

/** Message for a publish condition that no longer states the shared definition. */
function publishShapeMessage(count, operands) {
  return (
    "jobs.publish.if does not carry the shared release definition exactly once as " +
    `a top-level '||' operand (found it ${count} time(s)).\n` +
    `      recorded: ${RELEASE_REF_CONDITION}\n` +
    `      found:    ${operands.join("  ||  ")}\n` +
    "      The publish job is the one that reaches the public registry, so it must " +
    "state the same release definition the release job states. A differently shaped " +
    "condition, for example one that ANDs the tag test with an event test, is a " +
    "deliberate change of policy: make it, then record it here and in ADR-019 in the " +
    "same commit."
  );
}

/** Message for a publish operand this repository has never recorded. */
function unrecordedOperandMessage(operand) {
  return (
    "jobs.publish.if grants a publish on a condition this repository has not " +
    `recorded: ${operand}\n` +
    "      Every operand beyond the release definition is a standing permission to " +
    "publish to npm without a release tag. If it is intended, add it to " +
    "PUBLISH_CONDITIONS_BEYOND_RELEASE in this file, say in the comment above the " +
    "condition in ci.yml what compensates for it, and update ADR-019."
  );
}

/** Message for a recorded operand the publish condition no longer carries. */
function recordedOperandGoneMessage(operand) {
  return (
    `jobs.publish.if no longer carries a recorded condition: ${operand}\n` +
    "      Removing it is a tightening, not a defect, but the record has to stay " +
    "true or the next reader is back to guessing. Delete the entry from " +
    "PUBLISH_CONDITIONS_BEYOND_RELEASE in this file and settle ADR-019 in the same " +
    "commit."
  );
}

const UNREADABLE_PUBLISH_CONDITION =
  "jobs.publish.if could not be read: unbalanced parentheses, an unterminated " +
  "quoted literal, or an empty `||` operand. An unreadable publish condition is a " +
  "failure here, never a skip.";

const publishJob = ci?.jobs?.publish;
const releaseJob = ci?.jobs?.release;

if (!publishJob) {
  problems.push(
    "the 'publish' job is gone from ci.yml. Publish authorization is asserted here " +
      "by job name, so renaming or removing that job removes the assertion with it. " +
      "Rename it here in the same commit.",
  );
}
if (!releaseJob) {
  problems.push(
    "the 'release' job is gone from ci.yml. It is the second half of the release " +
      "definition asserted here; without it nothing holds the publish condition to a " +
      "shared meaning of 'release'.",
  );
}

const publishIf = typeof publishJob?.if === "string" ? publishJob.if : null;
const releaseIf = typeof releaseJob?.if === "string" ? releaseJob.if : null;

if (publishJob && publishIf === null) {
  problems.push(
    "jobs.publish has no `if:` condition. That job runs `npm publish --access " +
      "public --provenance` with id-token: write, and a job with no condition runs on " +
      "every event ci.yml accepts, which includes every push to main and every " +
      "pull_request. Restore the condition, and record any operand beyond the release " +
      "definition in PUBLISH_CONDITIONS_BEYOND_RELEASE in this file.",
  );
}
if (releaseJob && releaseIf === null) {
  problems.push(
    "jobs.release has no `if:` condition, so it would attempt a GitHub Release on " +
      "every event ci.yml accepts. It is also the job the publish condition is held " +
      "against, so with no condition there is nothing to hold it to.",
  );
}

const releaseCondition = releaseIf === null ? null : normaliseCondition(releaseIf);
const publishOperands = publishIf === null ? null : splitTopLevelOr(publishIf);
const beyondRelease = (publishOperands ?? []).filter((o) => o !== RELEASE_REF_CONDITION);
const releaseOperandCount = (publishOperands ?? []).filter((o) => o === RELEASE_REF_CONDITION).length;
const unrecorded = beyondRelease.filter((o) => !PUBLISH_CONDITIONS_BEYOND_RELEASE.includes(o));
const recordedButGone = PUBLISH_CONDITIONS_BEYOND_RELEASE.filter((o) => !beyondRelease.includes(o));

// The guards. Each is deliberately ONE line: the mutation tests in
// tests/runtime-support.bats delete one of them at a time, and deleting any single
// guard must turn exactly one of those tests red while the rest stay green. A guard
// that cannot be removed in isolation cannot be proved to be doing anything.
if (releaseIf !== null && releaseCondition !== RELEASE_REF_CONDITION) problems.push(releaseDefinitionMessage(releaseCondition));
if (publishIf !== null && publishOperands === null) problems.push(UNREADABLE_PUBLISH_CONDITION);
if (publishOperands !== null && releaseOperandCount !== 1) problems.push(publishShapeMessage(releaseOperandCount, publishOperands));
for (const operand of publishOperands === null ? [] : unrecorded) problems.push(unrecordedOperandMessage(operand));
for (const operand of publishOperands === null ? [] : recordedButGone) problems.push(recordedOperandGoneMessage(operand));

// ─── 4. Job-level elevations that the top-level `contents: read` must not swallow ───
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

// ─── 5. The code record and the DOCUMENTED record say the same thing ────────
//
// Section 3 holds ci.yml to PUBLISH_CONDITIONS_BEYOND_RELEASE, a literal list in
// this test file. That is one record. The other is ADR-019 in README.md, which
// is what a person reads when they want to know who may publish - and until this
// section existed, nothing compared the two. Editing either one alone left the
// repository stating two different publish policies with every check green.
//
// So this compares them as SETS, in both directions. A dropped operand and an
// added one are different findings with different messages, because the fix
// differs: one is a tightening whose record went stale, the other is a widening
// that was never written down.
//
// It reads a FENCED BLOCK rather than the prose around it. Prose in that ADR is
// line-wrapped and rewritten freely; a block is an enumeration, and an
// enumeration is the only shape a set comparison can be made against without
// guessing where a sentence ends. `(none)` is how the empty set is written,
// because a block with nothing in it cannot be told apart from a block someone
// emptied by accident.
const ADR_HEADING = "### ADR-019:";
const ADR_MARKER = "**Recorded operands beyond the release definition.**";
const ADR_EMPTY = "(none)";

const readmeRead = readUnder("README.md", "README.md");
if (readmeRead.absent) {
  // The root is an argument. A fixture that never had a README is not a
  // repository whose ADR was deleted, and this file does not guess between them.
  // It cannot hollow out the assertion: section 3 still holds ci.yml to the code
  // record, and in this repository README.md is present, so the pair IS compared
  // on every pull request.
  notAsserted.push(
    `README.md is not present under ${root}, so ADR-019 cannot be compared with ` +
      "PUBLISH_CONDITIONS_BEYOND_RELEASE.",
  );
} else if (readmeRead.problem) {
  problems.push(`${readmeRead.problem} ADR-019 cannot be compared with the recorded list.`);
} else {
  const lines = readmeRead.text.split(/\r?\n/);
  const headingAt = lines.findIndex((l) => l.startsWith(ADR_HEADING));
  if (headingAt === -1) {
    problems.push(
      `README.md has no '${ADR_HEADING}' section. That ADR is the documented half of publish ` +
        "authorization; deleting it leaves the recorded list in this file with nothing stating " +
        "what it means or why it is open.",
    );
  } else {
    let endAt = lines.findIndex((l, i) => i > headingAt && l.startsWith("### "));
    if (endAt === -1) endAt = lines.length;
    const section = lines.slice(headingAt, endAt);
    const markerAt = section.findIndex((l) => l.startsWith(ADR_MARKER));
    if (markerAt === -1) {
      problems.push(
        `ADR-019 in README.md no longer carries the line '${ADR_MARKER}'. That marker is what ` +
          "locates the documented operand list; without it the ADR can say anything at all about " +
          "publish authorization and nothing here would disagree.",
      );
    } else {
      const fenceAt = section.findIndex((l, i) => i > markerAt && l.trim() === "```");
      const closeAt =
        fenceAt === -1 ? -1 : section.findIndex((l, i) => i > fenceAt && l.trim() === "```");
      if (fenceAt === -1 || closeAt === -1) {
        problems.push(
          "ADR-019 in README.md has the recorded-operands marker but no closed ``` block after " +
            "it. The block is the enumeration this assertion reads; prose cannot be compared as a set.",
        );
      } else {
        const documented = section
          .slice(fenceAt + 1, closeAt)
          .map((l) => l.trim())
          .filter((l) => l !== "");
        if (documented.length === 0) {
          problems.push(
            `The recorded-operands block in ADR-019 is empty. Write '${ADR_EMPTY}' when the list ` +
              "is empty: an empty block reads the same whether it was emptied on purpose or by accident.",
          );
        } else {
          const documentedSet =
            documented.length === 1 && documented[0] === ADR_EMPTY ? [] : documented;
          for (const operand of PUBLISH_CONDITIONS_BEYOND_RELEASE) {
            if (!documentedSet.includes(operand)) {
              problems.push(
                `PUBLISH_CONDITIONS_BEYOND_RELEASE records a publish condition that ADR-019 does ` +
                  `not document: ${operand}\n` +
                  "      Every operand there is a standing permission to publish to npm without a " +
                  "release tag, and the ADR is where a reader looks for it. Add it to the recorded " +
                  "operands block in README.md.",
              );
            }
          }
          for (const operand of documentedSet) {
            if (!PUBLISH_CONDITIONS_BEYOND_RELEASE.includes(operand)) {
              problems.push(
                `ADR-019 documents a publish condition this file no longer records: ${operand}\n` +
                  "      Either the operand was removed from ci.yml and the ADR was not updated, in " +
                  "which case delete it there and settle the open decision in the same commit, or " +
                  "the ADR is describing a policy that is not in force.",
              );
            }
          }
          if (!section.join(" ").replace(/\s+/g, " ").includes(RELEASE_REF_CONDITION)) {
            problems.push(
              "ADR-019 in README.md no longer states the release definition verbatim.\n" +
                `      recorded: ${RELEASE_REF_CONDITION}\n` +
                "      The ADR and RELEASE_REF_CONDITION in this file are the two written records " +
                "of what counts as a release. They have to agree.",
            );
          }
        }
      }
    }
  }
}

for (const n of notAsserted) console.error(`  ~ not asserted here: ${n}`);

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("repo CI shape OK");
