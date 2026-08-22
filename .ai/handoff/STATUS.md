# AAHP: Current State of the Nation

> Last updated: 2026-08-22 by claude (workflow hardening: declared permissions + no persisted checkout credential, in CI and in the shipped template)
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
| `tests/workflow-hardening.bats` | FOCUSED PASS | run under Git Bash filtered to the two load-bearing assertions (the repository's own workflows and its shipped template), green before the mutation and red after deleting the `permissions:` block from `assets/governance/aahp-govern.yml`. The file's thirteen fixture expectations were additionally exercised in-process against the gate's `audit()`, all thirteen returning the exact expected exit code (1 for a real problem, 2 for a state the gate cannot decide). The file holds **24** tests, not the 21 an earlier revision of this row claimed: it carried 20 when that row was written, and the four listed next were added afterwards. Those four were then run under Git Bash and are green, `1..4`, exit 0: they pin what `tests/assert-repo-ci-shape.mjs` does with a root that does not hold every workflow it records (green, and the elevation it could not check named on stderr) and with one that holds an unreadable, unparseable or missing file (exit 1 with a stated finding, never a thrown `ENOENT`). The rest of the file is left to Linux CI, which is authoritative here: a Windows box running many suites at once takes hours per pass. |
| full Bats suite | CI | deliberately not run on Windows; Linux CI is authoritative |
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
| Workflow-hardening gate | `tests/assert-workflow-hardening.mjs` | New | every document under `.github/workflows/` AND `assets/governance/` must declare a top-level `permissions:` mapping and set `persist-credentials: false` on every checkout; scanning zero files exits 2, never 0 |
| Shipped governance template | `assets/governance/aahp-govern.yml` | Changed | declares `contents: read` and refuses the persisted checkout credential; this is the only file in the change with reach beyond this repository |
| Repository workflows | `.github/workflows/*.yml` | Changed | six gained a top-level `contents: read`; the nine remaining checkouts IN THIS DIRECTORY set `persist-credentials: false`, and the tenth this branch sets is in the shipped template, row above. Nine is the `.github/workflows`-only figure, never the repository total: measured 2026-08-22 there are eleven checkout steps across both locations, one of which (`aahp-verify.yml`) already set the flag, so all eleven set it after this change. The three job-level elevations are unchanged and now pinned by name in `tests/assert-repo-ci-shape.mjs` |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency |
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
| Adopters keep an unhardened `aahp-govern.yml` | MEDIUM | OWNER DECISION. `aahp init --gates` skips a workflow that already exists (`bin/aahp.js`), so a repository that scaffolded the governance workflow before this change keeps the copy with no `permissions:` block and a persisted checkout credential, and will keep it forever unless somebody re-runs with `--force`. The CHANGELOG says so, which reaches people who read release notes and nobody else. Options: (a) leave it as a release note, (b) have `aahp doctor` report a scaffolded `aahp-govern.yml` that lacks either property, so an adopter sees it on their own pull requests, (c) make `init --gates` upgrade this specific file in place. (b) is the one that matches how `verify-workflow` already reports a weakened gate from inside the consumer. Not taken here: it changes `doctor`'s output contract, which is a separate decision from hardening the file. |
| `persist-credentials: false` on the release path unproven in a real tag run | NORMAL | OWNER CONFIRMATION. The evidence that the change is behaviour-preserving is direct: no workflow in this repository runs `git push`, `git commit`, `git fetch`, `git pull` or `git remote`, none uses a credential-writing action, and the only `secrets.` reference passes `GITHUB_TOKEN` to `gh release create` as an environment variable, which does not read `.git/config`. The `publish` job authenticates to npm by OIDC, which is delivered through environment variables and is unaffected by checkout options. But `publish` and `release` only ever run on a version tag, so no pull-request CI run exercises them. Confirm on the first tag build after this merges. |
| Mutable action tags and `sha_pinning_required` | NORMAL | Out of scope here and deliberately not bundled: TEN of the eleven `actions/checkout` references use the mutable `@v4` tag rather than an immutable SHA, and the repository setting `sha_pinning_required` is `false`. Re-measured 2026-08-22 over `.github/workflows/*.yml` and `assets/governance/*.yml` together, exactly one reference is pinned to a 40-hex commit SHA, in `aahp-verify.yml`; the earlier figure of nine counted `.github/workflows/` only while stating a total of eleven that includes the shipped template, so it understated the exposure by one, and by the file that reaches consumers. Same class of exposure as this change, different fix, tracked at https://github.com/homeofe/AAHP/issues/68 and https://github.com/homeofe/AAHP/issues/71. |
| npm lifecycle scripts in CI | NORMAL | Not addressed by this change and should not be read as closed by it: `npm ci` in `ci.yml` runs without `--ignore-scripts`, so lifecycle scripts from the whole dependency tree execute in the same job as the checkout. Removing the persisted credential removes what those scripts could have read from `.git/config`; it does not stop them running. The shipped template already uses `npm ci --ignore-scripts`. |
| Merge order against https://github.com/homeofe/AAHP/pull/89 | HIGH | MEASURED. The two changes are each green on their own CI and jointly red, and neither pull request's CI can see it because each was tested against a base that lacked the other. Both edit `tests/assert-repo-ci-shape.mjs`; #89 adds fixture tests that run that gate against a root holding only `package.json` and `ci.yml`, and this change had it read `codeql.yml` unguarded, so on the merged tree the read threw `ENOENT` and all eight of #89's release-authorization tests were red - two on the exit code (expected 0, got 1) and six on the message, having got exit 1 from a stack trace instead of a finding. Fixed here by guarding every read; the merged tree now runs those eight green, and reverting the guard turns all eight red again. Both also claimed ADR-019, so this change moved to **ADR-020**, which is why the README jumps from 018 to 020 until #89 lands. **This branch must merge AFTER #89**, and whichever merges second resolves the three shared files by keeping both sides. |
| Consumer manifests already rewritten | MEDIUM | The generator no longer writes a checkout's directory name into `project`, but repositories whose committed `MANIFEST.json` already carries such a name keep it, because a recorded name is preserved by design. Those values need correcting in the consumer repositories. |
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
6. Merge https://github.com/homeofe/AAHP/pull/89 BEFORE this branch, and resolve
   `tests/assert-repo-ci-shape.mjs`, `README.md` and `CHANGELOG.md` by keeping both
   sides. The row in "What is Missing" above records the measurement behind that order.
