#!/usr/bin/env node
// assert-repo-ci-shape.mjs - repository-shape assertions for runtime-support.bats.
//
// Kept as a file rather than inlined into `node -e` on purpose: under Git Bash
// (MSYS) a POSIX-looking path INSIDE a quoted -e string is not converted for the
// native node binary, so `require('/c/Users/.../package.json')` fails with
// MODULE_NOT_FOUND and the test reports a defect that does not exist. A path
// passed as an argv element IS converted, so the repo root arrives here intact.
//
// Three things are asserted, and none of them is about a gate's own logic:
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
//
// Exit codes: 0 when every assertion holds, 1 when at least one does not. There
// is no third code and no skip: an input this file cannot read is reported as a
// failure, because "I could not look" must never read as "I looked and it was
// fine".

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
// It is a CHANGE DETECTOR, not a policy. It does not decide whether a manual
// publish path should exist; that question is recorded as open in ADR-019 in
// README.md. What it does is pin both conditions to the state this repository has
// recorded, so changing either one becomes a two-part edit - the workflow and the
// record below - that a reviewer meets in a single diff.
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
// One entry today, and it is an OPEN owner decision rather than a settled one.
// A manual run publishes from whatever ref it was started on, producing no tag and
// no GitHub Release; none of this workflow's 147 runs, measured 2026-08-22, was a
// manual dispatch. The options for settling it, and what each one requires, are in
// ADR-019. Adopting any of them means editing ci.yml and this list in the same
// commit, which is the entire point of the list.
const PUBLISH_CONDITIONS_BEYOND_RELEASE = [
  "github.event_name == 'workflow_dispatch'",
];

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

if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("repo CI shape OK");
