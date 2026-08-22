#!/usr/bin/env node
// assert-workflow-hardening.mjs - every workflow this repository runs, and every
// workflow this repository SHIPS, must declare its own GITHUB_TOKEN permissions
// and must not leave that token in the job workspace.
//
// WHY THIS GATE EXISTS
//
// Before it, exactly one workflow in this repository had been through a
// hardening pass. It was the only one with a top-level `permissions:` block and
// the only one with `persist-credentials: false`. The other seven documents,
// including the governance workflow AAHP ships to adopters, still carried the
// shape they were first written in. Nothing was red, because nothing checked. A
// convention that lives in one exemplary file and nowhere else is not a
// convention; it is a coincidence that survived.
//
// THE TWO PROPERTIES, and why each is worth a gate rather than a review habit
//
//   1. A top-level `permissions:` mapping. A workflow without one inherits the
//      repository's `default_workflow_permissions`. That default is a setting,
//      not a file: flipping it from `read` to `write` widens every inheriting
//      job at once, with no diff in this repository and nothing to review. A
//      declared block is immune to that flip. It is also strictly narrower than
//      inheriting TODAY, not only after a hypothetical change: an inheriting job
//      in this repository is granted `Packages: read` on top of `Contents` and
//      `Metadata`, and a job declaring `contents: read` is not.
//
//   2. `persist-credentials: false` on every checkout. `actions/checkout`
//      defaults to `persist-credentials: true` (verified against the action's
//      own action.yml at v4 and at the SHA this repository pins, rather than
//      from memory), which writes the job's `GITHUB_TOKEN` into `.git/config` as
//      an `http.<host>/.extraheader` value. Every later step in the same job can
//      read it, including anything a dependency lifecycle script executes.
//
// SCOPE, and why it is two directories and not one
//
//   .github/workflows/  - what this repository runs.
//   assets/governance/  - what this repository SHIPS. `aahp init --gates` copies
//                         aahp-govern.yml from here into a consumer repository,
//                         and `npm pack` puts it in the published tarball. The
//                         containment argument that makes the local workflows
//                         low-impact (public repository, `default_workflow_
//                         permissions: read`, throwaway hosted runners, no
//                         organization layer) is a set of facts about THIS
//                         repository. None of it travels with a file handed to
//                         an adopter whose visibility, defaults and organization
//                         settings are unknown. So the shipped template is held
//                         to the same bar, permanently, by the same gate.
//
// Both roots must exist and must contain at least one workflow document. A gate
// that scans zero files reports success, and this repository has already been
// bitten once by a gate that stayed green after the thing it measured was
// removed. Zero scanned is exit 2, not exit 0.
//
// Usage: node tests/assert-workflow-hardening.mjs [repo-root]
// Exit:  0 every scanned document satisfies both properties
//        1 at least one does not (every problem is printed, not just the first)
//        2 the question could not be decided: a scan root is missing or empty, a
//          file cannot be read, a document is not valid YAML, a value is a
//          `${{ }}` expression this gate cannot evaluate, or a job delegates to
//          a reusable workflow whose steps are not visible from here. "I could
//          not look" must never read as "I looked and it was fine".
//
// `yaml` is a devDependency, so this runs in CI and never inside a consumer.
// Kept as a file rather than an inline `node -e` for the reason recorded in
// tests/assert-repo-ci-shape.mjs: under Git Bash a POSIX path inside a quoted
// -e string is not converted for the native node binary.

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parse } from "yaml";
import { pathToFileURL } from "node:url";

// The two roots, relative to the repository root. Adding a third belongs here,
// not in a caller: the point of the list is that it is the single place that
// answers "what counts as a workflow this project is responsible for".
export const SCAN_ROOTS = [
  { dir: [".github", "workflows"], label: ".github/workflows", why: "what this repository runs" },
  { dir: ["assets", "governance"], label: "assets/governance", why: "what this repository ships to adopters" },
];

// ---------------------------------------------------------------------------
// Checkout credential exemptions
//
// A job that genuinely needs the checkout credential in `.git/config` (one that
// pushes a commit or a tag with plain `git`, for example) cannot set
// `persist-credentials: false`. Rather than let such a job silently drop out of
// the gate behind a YAML comment, the exemption is recorded HERE, is reviewed as
// a code change, and its reason is printed on every run so it shows up in the
// CI log of every pull request.
//
// The list is EMPTY today, and that is a measured fact rather than an omission:
// no workflow in this repository runs `git push`, `git commit`, `git fetch`,
// `git pull` or `git remote`, and none uses a credential-writing action. The
// single `secrets.` reference in the whole set passes `GITHUB_TOKEN` to
// `gh release create` as an environment variable, and `gh` does not read
// `.git/config` for it.
//
// Shape: { file: "<root-relative path>", job: "<job id>", reason: "<why>" }
// The reason must name the step that needs the credential.
export const CHECKOUT_CREDENTIAL_EXEMPTIONS = [];

// ---------------------------------------------------------------------------

const isPlainObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

/** A `${{ ... }}` expression cannot be evaluated here, so it cannot be cleared. */
const isExpression = (v) => typeof v === "string" && v.includes("${{");

/**
 * Does this `uses:` reference a checkout action?
 *
 * Matched on the last path segment rather than on the literal string
 * "actions/checkout", so a fork or a mirror (`someorg/checkout@v4`) is caught
 * too. The cost of the wider match is that an unrelated action whose name
 * happens to end in `checkout` would be flagged; the exemption list above is
 * where that would be settled, with a stated reason, in one place.
 */
export function isCheckoutUses(uses) {
  if (typeof uses !== "string") return false;
  const ref = uses.trim().split("@")[0].trim();
  if (ref === "") return false;
  return ref.split("/").pop().toLowerCase() === "checkout";
}

/**
 * Audit one parsed workflow document.
 * Returns { problems, undecidable, checkouts, hardened, exempt, missingPermissions }.
 */
export function auditDoc(doc, file, exemptions = CHECKOUT_CREDENTIAL_EXEMPTIONS) {
  const problems = [];
  const undecidable = [];
  let checkouts = 0;
  let hardened = 0;
  let exempt = 0;
  let missingPermissions = 0;

  if (!isPlainObject(doc)) {
    undecidable.push(`${file}: does not parse to a mapping, so it is not a workflow document this gate can read`);
    return { problems, undecidable, checkouts, hardened, exempt, missingPermissions };
  }

  // --- Property 1: a top-level permissions mapping --------------------------
  if (!("permissions" in doc)) {
    missingPermissions++;
    problems.push(
      `${file}: no top-level 'permissions:' block. Every job in this file inherits the ` +
        "repository's default_workflow_permissions, which is a setting rather than a file: " +
        "flipping that default widens this workflow with no diff here to review.",
    );
  } else if (typeof doc.permissions === "string") {
    problems.push(
      `${file}: top-level 'permissions: ${doc.permissions}' is the string form, which sets ` +
        "every scope at once. Declare the scopes this workflow actually needs as a mapping, " +
        "for example 'permissions:\\n  contents: read'.",
    );
  } else if (!isPlainObject(doc.permissions)) {
    problems.push(
      `${file}: top-level 'permissions:' is present but has no mapping value, so it grants ` +
        "nothing readable and GitHub will not accept it. Write the scopes explicitly.",
    );
  } else {
    // Elevation belongs on the job that needs it, not at the top of the file,
    // where it is handed to every job including any job added later. This is
    // already how this repository is shaped: ci.yml elevates `publish` and
    // `release` at job level, and codeql.yml elevates `analyze` at job level.
    for (const [scope, value] of Object.entries(doc.permissions)) {
      if (isExpression(value)) {
        undecidable.push(`${file}: top-level permissions.${scope} is a \${{ }} expression this gate cannot evaluate`);
      } else if (String(value) === "write") {
        problems.push(
          `${file}: top-level 'permissions.${scope}: write' grants write to every job in the ` +
            "file, including jobs added later. Put the elevation on the job that needs it.",
        );
      }
    }
  }

  // --- Property 2: no persisted checkout credential -------------------------
  const jobs = isPlainObject(doc.jobs) ? doc.jobs : null;
  if (!jobs) {
    undecidable.push(`${file}: no 'jobs:' mapping, so there is nothing here this gate can classify`);
    return { problems, undecidable, checkouts, hardened, exempt, missingPermissions };
  }

  for (const [jobId, job] of Object.entries(jobs)) {
    if (!isPlainObject(job)) {
      undecidable.push(`${file}: job '${jobId}' is not a mapping`);
      continue;
    }

    if (typeof job.permissions === "string") {
      problems.push(
        `${file}: job '${jobId}' uses 'permissions: ${job.permissions}', the string form, which ` +
          "sets every scope at once. Declare the scopes the job needs as a mapping.",
      );
    }

    if (!Array.isArray(job.steps)) {
      if (typeof job.uses === "string") {
        undecidable.push(
          `${file}: job '${jobId}' delegates to the reusable workflow '${job.uses}'. Whether it ` +
            "checks out with a persisted credential is not visible from this file.",
        );
      } else {
        undecidable.push(`${file}: job '${jobId}' has no 'steps:' list and no 'uses:'`);
      }
      continue;
    }

    for (const [index, step] of job.steps.entries()) {
      if (!isPlainObject(step)) continue;
      if (!isCheckoutUses(step.uses)) continue;
      checkouts++;

      const where = `${file}: job '${jobId}', step ${index + 1} (${step.uses})`;
      const exemption = exemptions.find((e) => e.file === file && e.job === jobId);
      if (exemption) {
        exempt++;
        continue;
      }

      const withBlock = isPlainObject(step.with) ? step.with : {};
      const value = withBlock["persist-credentials"];

      if (value === undefined) {
        problems.push(
          `${where} does not set 'persist-credentials: false'. actions/checkout defaults it to ` +
            "true, which writes the job's GITHUB_TOKEN into .git/config where every later step " +
            "in the job can read it.",
        );
        continue;
      }
      if (isExpression(value)) {
        undecidable.push(`${where} sets persist-credentials to a \${{ }} expression this gate cannot evaluate`);
        continue;
      }
      if (value === false || String(value).trim().toLowerCase() === "false") {
        hardened++;
        continue;
      }
      problems.push(`${where} sets 'persist-credentials: ${String(value)}', so the token is persisted.`);
    }
  }

  return { problems, undecidable, checkouts, hardened, exempt, missingPermissions };
}

export function audit(root, { roots = SCAN_ROOTS, exemptions = CHECKOUT_CREDENTIAL_EXEMPTIONS } = {}) {
  const result = {
    documents: 0,
    checkouts: 0,
    hardened: 0,
    exempt: 0,
    missingPermissions: 0,
    problems: [],
    undecidable: [],
  };

  for (const scan of roots) {
    const dir = join(root, ...scan.dir);
    if (!existsSync(dir)) {
      result.undecidable.push(
        `${scan.label}/ does not exist. It is a scan root of this gate (${scan.why}); a missing ` +
          "root means the gate measured nothing there, which is not the same as finding nothing wrong.",
      );
      continue;
    }

    let entries;
    try {
      entries = readdirSync(dir);
    } catch (err) {
      result.undecidable.push(`${scan.label}/ cannot be read (${err.message})`);
      continue;
    }

    let seen = 0;
    for (const entry of entries.sort()) {
      if (!/\.ya?ml$/i.test(entry)) continue;
      const file = `${scan.label}/${entry}`;
      let text;
      try {
        text = readFileSync(join(dir, entry), "utf8");
      } catch (err) {
        result.undecidable.push(`${file}: cannot be read (${err.message})`);
        continue;
      }
      let doc;
      try {
        doc = parse(text);
      } catch (err) {
        result.undecidable.push(`${file}: is not valid YAML (${err.message})`);
        continue;
      }
      seen++;
      result.documents++;
      const one = auditDoc(doc, file, exemptions);
      result.problems.push(...one.problems);
      result.undecidable.push(...one.undecidable);
      result.checkouts += one.checkouts;
      result.hardened += one.hardened;
      result.exempt += one.exempt;
      result.missingPermissions += one.missingPermissions;
    }

    if (seen === 0) {
      result.undecidable.push(
        `${scan.label}/ holds no .yml or .yaml document. A scan root with nothing in it makes ` +
          "this gate pass vacuously, so it is reported rather than skipped.",
      );
    }
  }

  return result;
}

export function main(argv = process.argv.slice(2)) {
  const root = resolve(argv[0] || ".");
  const result = audit(root);

  console.log(`workflow documents            : ${result.documents}`);
  console.log(`without top-level permissions : ${result.missingPermissions}`);
  console.log(`actions/checkout steps        : ${result.checkouts}`);
  console.log(`  persist-credentials: false  : ${result.hardened}`);
  console.log(`credential exemptions in force: ${result.exempt}`);
  for (const e of CHECKOUT_CREDENTIAL_EXEMPTIONS) {
    console.log(`  exemption ${e.file} job '${e.job}': ${e.reason}`);
  }

  // Problems are printed whenever there are any, even alongside an undecidable
  // state. Reporting only the undecidable one would hide real findings behind a
  // shape the gate could not read, which is the failure mode this gate exists to
  // prevent in the first place. The EXIT CODE is what "undecided dominates"
  // means: 2 outranks 1, because a run that could not look everywhere must not
  // be reported as a run that looked and found only these.
  if (result.problems.length > 0) {
    console.error("workflow hardening gate FAIL");
    for (const p of result.problems) console.error(`  - ${p}`);
  }

  if (result.undecidable.length > 0) {
    console.error("workflow hardening gate UNDECIDED:");
    for (const u of result.undecidable) console.error(`  - ${u}`);
    console.error("Undecided is not clean. Resolve the shape, or record an exemption with a reason.");
    return 2;
  }

  if (result.problems.length > 0) return 1;

  console.log("workflow hardening gate OK");
  return 0;
}

const isMain = process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  process.exit(main());
}
