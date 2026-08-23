## 2026-08-23 - three inert controls, one regression suite (#84, #82, #80)

Three HIGH issues, one shape: a control that could not fail. Fixed together
because a shared suite that proves each one CAN fail closes the class, where
three tests proving each one currently passes would close nothing - every one of
these passed on the day it shipped.

All three reproduced first on `origin/main` at `b67b3cc`, each against a positive
control proving the harness was live.

- **#84** `aahp.config.json` was never validated against its own schema.
  `gateApplies` decides applicability from the PRESENCE of a key, so
  `forbiddenPaterns` read as an absent section and a FAILING gate reported
  `Governance OK`, exit 0, over a live em-dash violation. A config that was not
  even JSON was worse: `readJsonSafe` returned null, the caller substituted `{}`,
  and all eight gates skipped. Now validated before any gate is evaluated, by
  `check`, by `doctor`, and inside `loadConfig` so the direct `npm run check:*`
  path is covered too. `scripts/aahp-schema.mjs` is dependency-free (ADR-002) and
  throws on any schema keyword it does not implement, so it cannot report "valid"
  for a document it did not fully examine. CI cross-checks with AJV.
- **#82** `npx --no-install` does not prevent a registry fetch: `npx` is
  `npm exec`, which has no such option and ignores it silently. Five shipped call
  sites resolved the UNSCOPED, unowned name `aahp`. Replaced with an explicit path
  into the scoped package. Measured today: `GET registry.npmjs.org/aahp` still
  returns 404, so the old behaviour was still correct by accident, not by
  construction.
- **#80** `.ai/handoff/.aiignore` is read by nothing. Both claims that CI validates
  it are withdrawn, and `aahp lint` now names how many patterns it is NOT applying.

**What this did NOT do, and it is an owner decision, not an oversight.** The
firewall was not made real. Making it live would newly fail adopters' builds on
patterns they never chose: the glob vocabulary cannot express what the enforced
regexes do, and the template's `sk-*` (no length floor) matches the word
"task-type" inside AAHP's own shipped templates, so `aahp init` followed by
enforcement is red on an untouched repository - measured, 3 lines in
`GROUNDING.md`, `TRUST.md` and `WORKFLOW.md`. Recommendation in the pull request:
enforce, but as a NEW opt-in section with an empty default, not by activating the
copy every adopter already committed.

**Found while fixing, same class, fixed here.** Four of the thirteen enforced
secret patterns matched nothing: `grep` runs in BRE, where the bare `?` in
`['\"]?` is a literal question mark. `_KEY=`, `_SECRET=`, `_TOKEN=` and
`_PASSWORD=` scored zero on a fixture containing all four. Adding `_CREDENTIALS=`
to that list without escaping the quantifier would have been an anchor that
anchors nothing.

**Still open after this.** The repository's OWN workflows keep
`npx --no-install ajv-cli`, and `scripts/check-workflow-pinning.mjs` Rule B still
requires that spelling while describing it as the load-bearing guard. That claim
is now known to be false. It is left alone deliberately: issue #68 owns the
repository's own workflows, and #82 is scoped to code that ships to consumers.
Named in the pull request as not done.

**Environment note for the next agent.** `tests/lint.bats` test 32 fails on this
Windows machine on unmodified `origin/main` as well - it builds a fake interpreter
directory and prepends it with `PATH="$fake:$PATH"`, and a `C:/...` path splits on
the colon so the fake is never found. Verified against a clean baseline worktree
before concluding it was not a regression. The same trap bit the new suite's npx
spy and is handled there with `cygpath -u`.

## 2026-08-23 - declare merge=union for the handoff append-log

`.ai/handoff/STATUS.md` is prepend-only, so two branches almost always differ by
one block and nothing else. Eight sibling repositories in this estate already
declare `merge=union` for it; this one did not, and the two that lacked it are
exactly the two where twenty-two rebases on 2026-08-23 each resolved this file by
hand.

It does not stop a pull request going CONFLICTING - GitHub does not honour merge
drivers server-side, measured 2026-07-31 - so this removes the hand resolution,
not the merge. `MANIFEST.json` is deliberately left without a driver: it is
generated state, and the correct resolution is to take main's copy and recompute
the changed entries, which no driver can do.

# AAHP: Current State of the Nation

> Last updated: 2026-08-23 by claude (workflow hardening: declared permissions + no persisted checkout credential, in CI and in the shipped template; reconciled with main, which had meanwhile taken the doctor content check, the verify-workflow gate and the release-authorization assertions)
> Commit: (review branch, pending commit)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP **v3.10.0** (npm `@elvatis_com/aahp`) is prepared on a review branch. It has not
been tagged, published, or merged. The release changes Layer 2 in two bounded ways:

- CI diffs are anchored to an explicit base commit. Pull requests pass their base SHA,
  pushes pass the event `before` SHA, and manual runs require an input. Missing, zero,
  invalid, unreadable, HEAD-equal, and undiffable bases fail closed.
- An optional `handoffImpact.nonImpactingModifiedFiles` list can classify one exact
  content-only regular tracked-file modification (`M`) as non-impacting when the old and
  new Git modes match and it carries a visible review reason. A/D/R/C, mode changes,
  mixed source changes, config changes, and handoff changes remain impacting. The
  Node/Python runtime parser and schema reject unsafe, invisible, or ambiguous policy.

The actor-wide dependency-bot workflow bypass is removed. Layer 1 now runs for every
actor. The package now includes the workflow that `propagate.sh` installs. The gate
remains verify-only and never regenerates handoff state.

Separately, the published RUNTIME SUPPORT CLAIM is corrected. `engines.node` was
`>=18` (end of life 2025-04-30) while CI validated on Node 20 (end of life
2026-04-30), and the `aahp-verify.yml` that `propagate.sh` installs carried the same
dead pin, so every consumer inherited the claim on install. Nothing could go red
about it: the pins were internally consistent, just uniformly dead. `engines.node` is
now `>=22`, CI validates on 22 and 24, and `check:runtime-support` asserts the
RELATION between the two so neither side can rot alone.

On top of that, `aahp doctor` gains a **`verify-workflow`** gate: it audits the
consumer's own `.github/workflows/` and reports whether the workflow that hosts the
AAHP gate can SKIP it. A job-level or step-level `if:` around the gate leaves a
required status check that keeps its name and reports success having evaluated
nothing, so branch protection is satisfied by a verdict nobody produced, and Layer 1
MANIFEST checksum integrity goes missing along with the Layer 2 drift gate. AAHP
could not see this from inside itself: the workflow it ships is unconditional and
`propagate.sh` copies it verbatim, so the weakening only ever exists downstream. The
canonical workflow's last step runs `aahp doctor`, so a consumer that has weakened
its gate now reports it on its own pull requests. It is asserted as a CONSEQUENCE
("there exists an event on which this workflow concludes success without having run
the gate at `--level ci`"), it fails closed on a shape it cannot classify, and it was
measured against every consumer of this protocol before shipping.

Release authorization in `ci.yml` is now asserted. The `publish` job (npm,
`id-token: write`) and the `release` job (the GitHub Release) each carried a
hand-written `if:`, the two disagreed about what counts as a release, and nothing in
this repository read either one, so the drift was invisible and any later edit to
publish authorization would have been equally silent. The release definition is now
written once and both jobs must use exactly it; every additional top-level `||`
operand on the publish condition must appear in a literal recorded list. No workflow
behaviour changes: whether the `workflow_dispatch` operand should exist at all is the
owner's decision and is recorded as open, with its options, in ADR-019.
`aahp doctor` also stops letting a green `handoff-set` line read as an integrity
verdict. That gate compares the file SET and the INDEX and hashes nothing, which is
the documented split: ADR-011 makes `aahp verify` the owner of handoff drift, and
Layer 1 hashes each indexed file itself. Layer 1 also runs `aahp lint`, which
compares them again, but only under a Python interpreter and exiting 0 when there is
none, so lint is not a substitute for the gate. The pass reason said only "N indexed
files present, no strays", so a reader who had not read the ADR could take a green
line for an integrity verdict. It now adds "(content not compared; aahp verify
Layer 1 owns checksum integrity)", the same honest-summary treatment
`scripts/lint-handoff.sh` received in 3.9.0 (the CHANGELOG records it under 3.8.3,
a version number that was never published). No gate changed behaviour and no exit
code moved. The LIMIT is now stated in the source comment, in the README and in the
CHANGELOG rather than only in the pull request: only the default human-readable
`doctor` output carries the new reason, while `--json`, `--quiet` and `--governance`
do not, and those three are the invocations consumers wire into CI and hooks, so the
`schemaVersion: 1` record a dashboard ingests says exactly what it said before.
README also names the one configuration where the split has consequences for an
adopter: `verify-workflow` reporting `skip` while the handoff gates are evaluated
means no automated gate in that repository compares a handoff checksum.
Separately, the two required status checks that validate `MANIFEST.json` no longer
download and execute unpinned third-party code. `lint-and-validate` and
`aahp-manifest` ran `npm install --no-save ajv-cli ajv-formats` and executed the
result on the next line, on every push and every pull request, so 27 packages
arrived with nothing in this repository constraining any of them and one
compromised release anywhere in that closure was arbitrary code execution inside
the checks whose verdict certifies a change. Both packages are now exact
devDependencies locked by integrity hash, both jobs install that closure with
`npm ci`, and both invoke the tool with `npx --no-install`. The root cause was not
the forgotten pin: the workflow template this package ships to consumers
(`assets/governance/aahp-govern.yml`) has always used the correct form, and the
workflows that only ever ran here did not, because nothing made them.
`check:workflow-pinning` is that something.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| npm version | READY | package, lockfile, changelog, CLI help, and handoff surfaces set to 3.10.0 |
| `tests/handoff-impact.bats` | FOCUSED PASS | 24 pass + 3 Windows skips; empty base, staged/CI endpoint modes, parser parity, M-only, A/D/R/C, mixed and diff failures pass; schema passed separately; symlink case awaits Linux CI |
| `tests/propagate.bats` | FOCUSED PASS | 2/2; source checkout and installed npm tarball propagate byte-identical gate, parser, and workflow |
| `tests/verify.bats` | FOCUSED PASS | 22/22 under Git Bash with explicit CI bases |
| schema validation | FOCUSED PASS | example and repository config both validate against the updated schema |
| shell syntax | FOCUSED PASS | changed shell scripts parse under Git Bash |
| `tests/verify-workflow.bats` | FOCUSED PASS | 21/21; both directions, the two fail-closed shapes that must NOT be findings, plus parser parity against a real YAML parser on 16 workflow files |
| `npm run check` | PASS | changelog, version sync, claims, forbidden patterns, schema/doc sync, doc links, runtime support, workflow pinning, and handoff freshness |
| `tests/runtime-support.bats` | FOCUSED PASS | 16/16; the relation holds on this repo and each of nine mutations turns it red, including the emptied-matrix trap |
| `tests/workflow-pinning.bats` | FOCUSED PASS | 19/19; every rule holds on this repository and each way of breaking one turns the gate red at the exact documented exit code, 1 for a finding and 2 for a state it cannot evaluate |
| shellcheck | LINUX PASS | replacement head `c332a23` reached the full Bats step after shellcheck |
| hosted Linux suite | REPLACEMENT REQUIRED | `c332a23` passed 361/362; the CI mode fixture let `git add` restore mode 100644 on Linux, so it now reasserts 100755 before its content-plus-mode commit |
| `tests/doctor.bats` (3 new tests) | FOCUSED PASS | the three content-drift tests pass under Git Bash; two were mutated red and restored green. The other 16 tests in the file were not run on Windows; Linux CI is authoritative |
| `tests/workflow-hardening.bats` | FOCUSED PASS | run under Git Bash filtered to the two load-bearing assertions (the repository's own workflows and its shipped template), green before the mutation and red after deleting the `permissions:` block from `assets/governance/aahp-govern.yml`. The file's thirteen fixture expectations were additionally exercised in-process against the gate's `audit()`, all thirteen returning the exact expected exit code (1 for a real problem, 2 for a state the gate cannot decide). The file holds **24** tests, not the 21 an earlier revision of this row claimed: it carried 20 when that row was written, and the four listed next were added afterwards. Those four were then run under Git Bash and are green, `1..4`, exit 0: they pin what `tests/assert-repo-ci-shape.mjs` does with a root that does not hold every workflow it records (green, and the elevation it could not check named on stderr) and with one that holds an unreadable, unparseable or missing file (exit 1 with a stated finding, never a thrown `ENOENT`). The rest of the file is left to Linux CI, which is authoritative here: a Windows box running many suites at once takes hours per pass. |
| `tests/assert-repo-ci-shape.mjs` (reconciled) | FOCUSED PASS, BOTH DIRECTIONS | The authored reconciliation of the three-way divergence described in What is Missing. Baseline on the merged tree: 8/8 release-authorization tests in `tests/runtime-support.bats` and 7/7 elevation-and-guard tests in `tests/workflow-hardening.bats`, 15 across the two pull requests, all green. Each family was then mutated on the real workflow it guards, with the mutation verified on disk before anything was run and the untouched neighbours counted, so a mutation that failed to apply could not be reported as a proof. **A**: `jobs.release.if` in `ci.yml` changed to `startsWith(github.ref, 'refs/tags/')`. The gate emits exactly one finding, `jobs.release.if is not the recorded release definition`, `EXIT=1`; the two release-authorization tests that require exit 0 (1 and 7) go red, `BATS_EXIT=1`. The permission family is NOT untouched by this mutation and an earlier version of this row said it was: two of the seven tests in `tests/workflow-hardening.bats` go red as well (`the release-path elevations are still declared on this repository` and `a root with only package.json and ci.yml is green`), because those two invoke the SHAPE gate rather than `assert-workflow-hardening.mjs`, and one copies the real `ci.yml` into its fixture. The asymmetry belongs to **B** alone: `codeql.yml` appears in no fixture, so mutating it cannot reach the release-authorization family. **B**: `security-events: write` deleted from the `analyze` job in `codeql.yml` - an anchored count, because the same string also appears in a comment on line 10, so the naive count reads 2 and 1 rather than 1 and 0. The gate emits exactly one finding, `job 'analyze' no longer declares 'security-events: write'`, `EXIT=1`; `the release-path elevations are still declared on this repository` goes red, `BATS_EXIT=1`, while all EIGHT release-authorization tests stay green, which is the cross-check that the two sections are independent and both live. The **A** direction was re-measured after review, at the GATE level: with the release condition mutated, `assert-repo-ci-shape.mjs` exits 1 and `assert-workflow-hardening.mjs` exits 0, file restored md5-identical. That re-measurement was of the GATES only. It does not carry over to the bats families, which is what the sentence above now records instead. Both files restored byte-identical by md5 to their pre-mutation backup, gate back to `repo CI shape OK` `EXIT=0`, and both families re-run green. The full suite is left to Linux CI, which is authoritative here. |
| full Bats suite | CI | deliberately not run on Windows; Linux CI is authoritative |
| `tests/runtime-support.bats` (release authorization) | FOCUSED PASS | 8/8 added; the untouched repository shape is green, six one-line mutations of the REAL `ci.yml` each turn it red at exit 1 (including a publish job with no `if:` at all), and a reformat of the same expression stays green |
| `tests/cli.bats` injection block | FOCUSED PASS | 3/3; the CLI injection test now asserts the detector fired, on a checksum-clean tree, and covers all ten patterns by name. Emptying `INJECTION_PATTERNS` turns it red; the previous test reported ok under that same mutation |
| injection mutation proof | RE-VERIFIED | independently re-run. Under `INJECTION_PATTERNS=()`, one bats process reports `ok` for the pre-fix test body and `not ok` for the replacement, exit 1; restored, both `ok`, exit 0. With only the check 4 checksum comparison disarmed the replacement still passes, so its status comes from the injection check and not from the setup |
| injection pattern coverage count | CORRECTED | six of ten patterns were uncovered before this branch, not five. The safety-override entry, sixth in `INJECTION_PATTERNS`, was missed by counting bare substrings: `tests/lint.bats` contains the bare word `override` in a line the pattern itself does not match. This row deliberately does not quote the pattern, because writing it here makes the linter flag this file, which is the detector working |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| Verify gate | `scripts/verify-handoff.sh` | Changed | explicit base, fail-closed diff, name-status classifier |
| Shared library | `scripts/_aahp-lib.sh` | Changed | Node/Python runtime parser for reviewed impact config |
| Required workflow | `.github/workflows/aahp-verify.yml` | Changed | no actor bypass; explicit base; read-only token; immutable action pins; evaluator-path trust boundary documented |
| Config schema/example | `schema/aahp-config.schema.json`, `aahp.config.example.json` | Changed | additive `handoffImpact` contract |
| CLI | `bin/aahp.js` | Changed | verify help documents `--base SHA` |
| Conformance gate | `bin/aahp.js` (`gateHandoffSet`) | Changed | pass reason names the content check it does not run, and a header comment states the ADR-011 boundary; behaviour, gate statuses and the JSON record are unchanged |
| Scaffolded governance workflow | `assets/governance/aahp-govern.yml` | Changed | header now states that it runs no handoff-integrity gate and that a repository keeping `.ai/handoff/` needs `aahp-verify.yml` beside it; comment only |
| Specification | `README.md` | Changed | Section 2.8 and ADR-018 define the contract |
| Rollout | `scripts/ROLLOUT.md` | Changed | consumer propagation and mutation checks documented |
| Manifest generator | `scripts/aahp-manifest.sh` | Changed | `project` resolves from repository identity (recorded name, then git remote), not from the directory it runs in |
| Runtime-support gate | `scripts/check-runtime-support.mjs` | New | relation between CI pins and `engines.node`; one dated constant; exits 2 when it cannot evaluate |
| Runtime matrix | `.github/workflows/ci.yml` | Changed | new `runtime-matrix` job on Node 22 and 24; `lint-and-validate` deliberately left unmatrixed so the required check keeps its literal name |
| verify-workflow gate | `scripts/check-verify-workflow.mjs` | New | audits the consumer's workflows for a gate that can skip itself; zero runtime dependencies, so it carries its own block-YAML reader, held against a real parser by `tests/assert-workflow-parser-parity.mjs` |
| Workflow-hardening gate | `tests/assert-workflow-hardening.mjs` | New | every document under `.github/workflows/` AND `assets/governance/` must declare a top-level `permissions:` mapping and set `persist-credentials: false` on every checkout; scanning zero files exits 2, never 0 |
| Shipped governance template | `assets/governance/aahp-govern.yml` | Changed | declares `contents: read` and refuses the persisted checkout credential; this is the only file in the change with reach beyond this repository |
| Repository workflows | `.github/workflows/*.yml` | Changed | six gained a top-level `contents: read`; the nine remaining checkouts IN THIS DIRECTORY set `persist-credentials: false`, and the tenth this branch sets is in the shipped template, row above. Nine is the `.github/workflows`-only figure, never the repository total: measured 2026-08-22 there are eleven checkout steps across both locations, one of which (`aahp-verify.yml`) already set the flag, so all eleven set it after this change. The three job-level elevations are unchanged and now pinned by name in `tests/assert-repo-ci-shape.mjs` |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency |
| Repo-shape assertion | `tests/assert-repo-ci-shape.mjs` | Changed | third assertion: `publish` and `release` share ONE release definition, and every publish operand beyond it is recorded literally; reads the parsed condition, runs inside the required `lint-and-validate` |
| Workflow-pinning gate | `scripts/check-workflow-pinning.mjs` | New | no project-level `npm install` in a workflow, every `npx` carries `--no-install`, every package a workflow executes is declared here at an exact version, every direct dependency is locked with `resolved` and `integrity`; exits 2 on a state it cannot evaluate |
| Schema validation steps | `.github/workflows/ci.yml`, `.github/workflows/aahp-manifest.yml` | Changed | install the locked closure and run `ajv-cli` with `npx --no-install` instead of installing two undeclared packages from the registry on every run |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency, `ajv-cli` 5.0.0 and `ajv-formats` 3.0.1 pinned exactly |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| Linux CI evidence | HIGH | Required before merge; the full suite and shellcheck belong on the hosted Linux runner. |
| Release | NORMAL | Do not tag or publish until review is merged and the release ceremony is explicitly authorized. |
| Evaluator path protection | HIGH | The supplied `pull_request` workflow executes proposed workflow and gate code. A consumer must require trusted review for evaluator paths or supply a default-branch evaluator; v3.10.0 cannot configure repository rules. |
| Delete-both-sides Layer 1 hole | MEDIUM | Pre-existing: removing a canonical handoff file and its index entry still needs a required-set protocol decision. |
| Windows CI runner | MEDIUM | Pre-existing: Git Bash behavior is locally focused-tested, but CI remains Linux-only. |
| `runtime-matrix` not a required check | HIGH | The new job reports `Runtime matrix (22)` and `Runtime matrix (24)`. Until an owner adds them to branch protection they can go red without blocking a merge. The relation gate itself runs inside the required `lint-and-validate`, so the claim is still enforced. |
| SemVer call for `engines.node` | NORMAL | Narrowing `>=18` to `>=22` is a support-surface reduction. Whether it ships inside 3.10.0 or forces 4.0.0 is an owner decision, not one this branch takes. |
| `aahp-verify` can skip itself in six consumers | HIGH | ORIGINATED HERE. `458dbbd` (2026-06-30) added the dependency-bot exemption to this repository's own reference workflow, gating Checkout and every gate step; it shipped that way in v3.6.0 and propagated. `#65` removed it here on 2026-08-21. MEASURED 2026-08-22 with the new `verify-workflow` gate, against every consumer: six report `bypassable`, three report `enforced`. Five of the six report success having checked out nothing, so Layer 1 never runs either. The sixth was previously recorded here as corrected and is only PARTLY so: its checkout is unconditional and a bot change does get a Layer 1 run, but `--level ci` is still gated on the author, so the same required check name means all four layers for one author and Layer 1 for another. Only the owning repositories can re-propagate; this branch cannot fix any of them. Consumer identities are tracked privately and deliberately not recorded in this public repository. |
| No drift check between a consumer's propagated workflow and the installed package | PARTLY CLOSED | `aahp doctor` still never compares `.github/workflows/aahp-verify.yml` on disk against the one in the installed package, so a consumer can pin 3.10.0 and run the v3.6.0 workflow. The designed predicate this row asked for now exists for the case that matters: `verify-workflow` asks whether the hosting workflow can skip the gate, which tolerates deliberate divergence (a consumer may restructure the file freely) while catching the divergence that voids the check. General byte-level drift, for example an older action pin or a dropped `fetch-depth: 0`, is still unmeasured. |
| `npm install -g npm@latest` in the publish job | HIGH | Left in place deliberately. It is the only unpinned install inside the job that holds `id-token: write` immediately before `npm publish --provenance`, and it is a different risk class from the `ajv` path: the supplier is the package manager itself. The open question is whether the step should be DELETED rather than pinned, because its comment asserts that OIDC trusted publishing needs npm >= 12 while the pinned Node 24 line already ships npm 11.12.1, and that assertion is unverified. Owner decision, tracked at https://github.com/homeofe/AAHP/issues/68. The pinning gate names this exclusion in its header rather than hiding it in an exemption list. |
| No dependency-scanning workflow | HIGH | No workflow here performs a dependency or supply-chain scan, and `.github/dependabot.yml` has no `github-actions` ecosystem entry. Which scanner to adopt, and whether to make it a seventh required status check, is an owner decision: adding a required context blocks every pull request until the check reports at least once. Tracked at https://github.com/homeofe/AAHP/issues/68. |
| `ajv-cli` depends on `fast-json-patch` 2.2.1 | MEDIUM | GHSA-8gh8-hqwg-xf34, prototype pollution, fixed in 3.1.1. `ajv-cli` 5.0.0 requires `^2.0.0`, so the advisory cannot be resolved without an `overrides` entry that crosses a major version of a transitive dependency. This exposure is not new: the same closure was already being downloaded and executed on every CI run. Declaring the packages is what made it visible to `npm audit` and to Dependabot. |
| Adopters keep an unhardened `aahp-govern.yml` | MEDIUM | OWNER DECISION. `aahp init --gates` skips a workflow that already exists (`bin/aahp.js`), so a repository that scaffolded the governance workflow before this change keeps the copy with no `permissions:` block and a persisted checkout credential, and will keep it forever unless somebody re-runs with `--force`. The CHANGELOG says so, which reaches people who read release notes and nobody else. Options: (a) leave it as a release note, (b) have `aahp doctor` report a scaffolded `aahp-govern.yml` that lacks either property, so an adopter sees it on their own pull requests, (c) make `init --gates` upgrade this specific file in place. (b) is the one that matches how `verify-workflow` already reports a weakened gate from inside the consumer. Not taken here: it changes `doctor`'s output contract, which is a separate decision from hardening the file. |
| `persist-credentials: false` on the release path unproven in a real tag run | NORMAL | OWNER CONFIRMATION. The evidence that the change is behaviour-preserving is direct: no workflow in this repository runs `git push`, `git commit`, `git fetch`, `git pull` or `git remote`, none uses a credential-writing action, and the only `secrets.` reference passes `GITHUB_TOKEN` to `gh release create` as an environment variable, which does not read `.git/config`. The `publish` job authenticates to npm by OIDC, which is delivered through environment variables and is unaffected by checkout options. But `publish` and `release` only ever run on a version tag, so no pull-request CI run exercises them. Confirm on the first tag build after this merges. |
| Mutable action tags and `sha_pinning_required` | NORMAL | Out of scope here and deliberately not bundled: TEN of the eleven `actions/checkout` references use the mutable `@v4` tag rather than an immutable SHA, and the repository setting `sha_pinning_required` is `false`. Re-measured 2026-08-22 over `.github/workflows/*.yml` and `assets/governance/*.yml` together, exactly one reference is pinned to a 40-hex commit SHA, in `aahp-verify.yml`; the earlier figure of nine counted `.github/workflows/` only while stating a total of eleven that includes the shipped template, so it understated the exposure by one, and by the file that reaches consumers. Same class of exposure as this change, different fix, tracked at https://github.com/homeofe/AAHP/issues/68 and https://github.com/homeofe/AAHP/issues/71. |
| npm lifecycle scripts in CI | NORMAL | Not addressed by this change and should not be read as closed by it: `npm ci` in `ci.yml` runs without `--ignore-scripts`, so lifecycle scripts from the whole dependency tree execute in the same job as the checkout. Removing the persisted credential removes what those scripts could have read from `.git/config`; it does not stop them running. The shipped template already uses `npm ci --ignore-scripts`. |
| Reconciliation with https://github.com/homeofe/AAHP/pull/89 | DISCHARGED ON THIS BRANCH | #89 merged 2026-08-22 as `20ab708`; `origin/main` is merged into this branch as of this commit. The two changes were each green on their own CI and jointly red, and neither pull request's CI could see it because each was tested against a base that lacked the other. The resolution was AUTHORED rather than merged, because no merge rule could have produced it: `tests/assert-repo-ci-shape.mjs` diverged THREE ways from a common 63-line ancestor - main grew the same region to 370 lines, this branch to 228, and neither side contained a single line of the other. Taking `theirs` would have deleted this branch's permission assertions; taking `ours` would have deleted a gate already merged on main and left #89's eight tests either red or, worse, green and vacuous. The file now carries BOTH sections on top of this branch's guarded reads: main's release-authorization section as section 3 (`RELEASE_REF_CONDITION`, 7 occurrences, matching main exactly) and this branch's job-permission section as section 4 (`REQUIRED_JOB_PERMISSIONS`, 2 occurrences, matching this branch exactly). The guards are what let #89's fixture root, which holds only `package.json` and `ci.yml`, stay green instead of throwing `ENOENT`. Both gate families were then proved non-vacuous by mutating the REAL workflows rather than the gate: see the build-health row. README carries ADR-019 and ADR-020 in order with no gap, so the numbering gap noted earlier is closed. |
| Consumer manifests already rewritten | MEDIUM | The generator no longer writes a checkout's directory name into `project`, but repositories whose committed `MANIFEST.json` already carries such a name keep it, because a recorded name is preserved by design. Those values need correcting in the consumer repositories. |
| Manual publish path on the `ci.yml` `publish` job | NORMAL | OPEN OWNER DECISION, deliberately not taken here. The publish condition still accepts `workflow_dispatch`, which constrains no ref, so a manual run publishes from whichever ref it started on with no tag and no GitHub Release. Options A, B and C, and what each one requires, are in ADR-019. The condition is now pinned, so adopting any of them is a visible two-part edit rather than a silent one. |
<!-- /SECTION: what_is_missing -->

---

## Next Actions

1. Regenerate `MANIFEST.json` and run the focused repository gates.
2. Push the review pull request replacement head and let hosted Linux CI run the full suite and shellcheck.
3. Do not tag, publish, or merge from this session.
4. Decide the three owner questions in "What is Missing" above: how adopters holding an
   unhardened `aahp-govern.yml` are reached, confirmation of the release-path checkout
   change on the first tag build, and whether the mutable action tags are taken next.
5. The hardened `assets/governance/aahp-govern.yml` reaches adopters only when a version
   is published. Nothing in this change bumps the version, because the release ceremony
   is a separate, authorized step in this repository and several changes share the
   `[Unreleased]` block.
6. DONE, recorded here because the instruction that stood in its place was wrong in
   two ways and a later reader would otherwise repeat it. https://github.com/homeofe/AAHP/pull/89
   is merged (`20ab708`) and `origin/main` is merged into this branch, so the ordering
   it demanded is already satisfied - the "What is Missing" row above records it as
   DISCHARGED. And the resolution it prescribed, keeping both sides of
   `tests/assert-repo-ci-shape.mjs`, does NOT work for that file: the two sides overlap
   on the header, the `package.json` read and the `ci.yml` read, so keeping both yields
   duplicate declarations rather than a union. The file was authored into one text
   carrying both the release-authorization section and the job-permission section.
   `README.md` and `CHANGELOG.md` were keep-both, which is correct for those two.
