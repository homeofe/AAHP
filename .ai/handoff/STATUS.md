# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; pre-4.0.0 work; this change is the adopter upgrade path (branch fix/migration-and-legacy)

## Current objective

On 2026-09-28 the owner asked for everything a full audit of the repository found to be
fixed: scripts, gates, tests, CI and documentation. The findings were split into
workstreams with disjoint file scopes. Each lands as its own pull request, one at a
time, with CI settling between merges. Nothing is released until the owner decides, after
all fixes are in.

## Audit fix programme

| Workstream | Scope | State |
|------------|-------|-------|
| Dependency integration | five Dependabot PRs, scanner v6.3.1, expired TRUST rows | merged, #119 (`1917ca8`) |
| Consumer install path | adopter verify workflow, propagate, install-hooks | merged, #120 (`3e8e8d7`) |
| Test-suite integrity | vacuous assertions, fail-open skips, git isolation, fixture speed | merged, #121 (`1e3fd4a`) |
| CLI | signal exit codes, doctor schema validation, migrate, help | merged, #122 (`d27db82`) |
| Manifest, lint and shared lib | JSON generation, binary-safe scans, injection scan scope, template | merged, #122 (`d27db82`) |
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | merged, #124 (`9416ed0`) |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | merged, #125 (`f9b12ca`) |
| Documentation | README split, ADR fixes, redaction of internal details | merged, #126 (`aa17c1f`) |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | merged, #127 (`21a2ac7`) |

## This change: adopter upgrade path to 4.0.0

Closes the last open technical items before 4.0.0: what an existing adopter needs to
upgrade without a red CI it cannot fix.

- `aahp migrate` removes optional MANIFEST.json task fields that still hold a template
  placeholder the schema rejects (`"[ISO-8601]"`, `"YYYY-MM-DDT00:00:00Z"`), printing
  task, field and old value; valid data is never touched, a required field holding one
  stops the run with nothing changed, and a refused regeneration restores the original
  bytes. Doctor's manifest-schema failure names this fix, and only when it applies.
- New doctor gate `cli-source` (ADR-025) reports workflow steps that run the aahp CLI in a
  legacy way: fetched from the registry at run time, the unscoped name `aahp` through a
  package runner, `node bin/aahp.js` in a repository without that file, or a
  node_modules call with no install before it. Each fails, except `npx --no-install aahp`
  after an install, which fails closed and is advisory. The package itself reports
  `self`. The record keeps schemaVersion 2 and gains the `cli-source` key.
- `aahp init --gates --workflows` rewrites only the managed workflow files and leaves
  `aahp.config.json` and `package.json` untouched, the targeted remediation for
  `cli-source`; `--force` stays the full re-scaffold.
- README 5.1 documents the upgrade, including the one-time step measured on a real
  adopter: `handoffImpact.npmDevDependencyUpdates` cannot be added before the upgrade
  (3.12.0 rejects the key), so the upgrade lands as one reviewed pull request with the
  bump, the opt-in, a STATUS entry and a regenerated MANIFEST.json.
- README 2.8 now states exactly what the exemption's scan-job check proves: the workflow
  triggers include `pull_request`, and a job-level `if:`, when present, names it.

Measured against supply-chain-guard (pinned to 3.12.0) with this tree: doctor passes 8 of
8 with three advisory `cli-source` findings (`npx --no-install aahp` after an install).

## Validation

- Workstream tree on a Linux runner, rebased onto `2764794`: `CI=true npm test` 929 of
  929; `npm run check` (ADR refs 25 files, 271 citations), `doctor` (8 of 8), lint and
  archive verify exit 0; mutation proofs for the placeholder predicate, required-field
  refusal, rollback, doctor hint, every cli-source finding class, the self guard, the
  exemption's trigger checks and each `--workflows` property.
- Integrated onto `2764794`: `CI=true npm test` 929 of 929, 0 skipped; `npm run check`,
  `doctor`, lint, archive verify, the schema validation and the PII validator exit 0.

## Owner decisions

Decided on 2026-09-28:

- Full ASCII in tracked text, enforced by a gate (supersedes the U+2014-only question).
- Dependabot: grouped updates plus an opt-in, content-based Layer 2 exemption for
  dev-only lockfile changes. Never actor-based.
- TRUST-TTL: executable claims checked on every run, and a grace period for judgment rows.
- STATUS.md is a bounded snapshot; LOG.md is the only journal.
- README split into quickstart and normative spec, with ADRs and governance moved to
  `docs/`.
- Internal hostnames and estate figures are removed from public files.
- Repository settings applied: `Supply chain guard` is a required check on main, an active
  ruleset protects `refs/tags/v*`, and `sha_pinning_required` is on.
- No release until the owner decides, after all workstreams have landed.

Open:

1. Release: the programme is complete on main. Everything under CHANGELOG `##
   [Unreleased]` is unreleased; whether and when to release (and which version: the
   content includes breaking changes for adopters, see the Migration notes) is the owner's
   decision.
2. supply-chain-guard follow-ups, for that repository: homeofe/supply-chain-guard#354
   awaits its maintainer's merge; still open there are content-scanning extensionless
   shebang scripts and `.bats` files, installing the scanner by integrity rather than by
   version in its Action, its actor-based Dependabot exemption from `aahp-verify` (the
   content-based `npmDevDependencyUpdates` exemption can replace it), and its STATUS.md,
   still a prepend log.
3. Owner, on npmjs.com: set the trusted-publisher Environment name of @elvatis_com/aahp to
   `npm-publish` (confirmed empty on 2026-09-28), so a workflow edited to drop the binding
   cannot publish either.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
