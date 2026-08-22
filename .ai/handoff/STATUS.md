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

> Last updated: 2026-08-22 by claude (verify-workflow gate: can the workflow that runs the gate skip it?)
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
| `npm run check` | PASS | changelog, version sync, claims, forbidden patterns, schema/doc sync, doc links, runtime support, and handoff freshness |
| `tests/runtime-support.bats` | FOCUSED PASS | 16/16; the relation holds on this repo and each of nine mutations turns it red, including the emptied-matrix trap |
| shellcheck | LINUX PASS | replacement head `c332a23` reached the full Bats step after shellcheck |
| hosted Linux suite | REPLACEMENT REQUIRED | `c332a23` passed 361/362; the CI mode fixture let `git add` restore mode 100644 on Linux, so it now reasserts 100755 before its content-plus-mode commit |
| full Bats suite | CI | deliberately not run on Windows; Linux CI is authoritative |
| `tests/runtime-support.bats` (release authorization) | FOCUSED PASS | 8/8 added; the untouched repository shape is green, six one-line mutations of the REAL `ci.yml` each turn it red at exit 1 (including a publish job with no `if:` at all), and a reformat of the same expression stays green |
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
| Specification | `README.md` | Changed | Section 2.8 and ADR-018 define the contract |
| Rollout | `scripts/ROLLOUT.md` | Changed | consumer propagation and mutation checks documented |
| Manifest generator | `scripts/aahp-manifest.sh` | Changed | `project` resolves from repository identity (recorded name, then git remote), not from the directory it runs in |
| Runtime-support gate | `scripts/check-runtime-support.mjs` | New | relation between CI pins and `engines.node`; one dated constant; exits 2 when it cannot evaluate |
| Runtime matrix | `.github/workflows/ci.yml` | Changed | new `runtime-matrix` job on Node 22 and 24; `lint-and-validate` deliberately left unmatrixed so the required check keeps its literal name |
| verify-workflow gate | `scripts/check-verify-workflow.mjs` | New | audits the consumer's workflows for a gate that can skip itself; zero runtime dependencies, so it carries its own block-YAML reader, held against a real parser by `tests/assert-workflow-parser-parity.mjs` |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency |
| Repo-shape assertion | `tests/assert-repo-ci-shape.mjs` | Changed | third assertion: `publish` and `release` share ONE release definition, and every publish operand beyond it is recorded literally; reads the parsed condition, runs inside the required `lint-and-validate` |
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
| Consumer manifests already rewritten | MEDIUM | The generator no longer writes a checkout's directory name into `project`, but repositories whose committed `MANIFEST.json` already carries such a name keep it, because a recorded name is preserved by design. Those values need correcting in the consumer repositories. |
| Manual publish path on the `ci.yml` `publish` job | NORMAL | OPEN OWNER DECISION, deliberately not taken here. The publish condition still accepts `workflow_dispatch`, which constrains no ref, so a manual run publishes from whichever ref it started on with no tag and no GitHub Release. Options A, B and C, and what each one requires, are in ADR-019. The condition is now pinned, so adopting any of them is a visible two-part edit rather than a silent one. |
<!-- /SECTION: what_is_missing -->

---

## Next Actions

1. Regenerate `MANIFEST.json` and run the focused repository gates.
2. Push the review pull request replacement head and let hosted Linux CI run the full suite and shellcheck.
3. Do not tag, publish, or merge from this session.
