# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes are listed under
`## [Unreleased]` in CHANGELOG.md
Protocol version: 3.0
Working state: audit fix programme in progress; this change is test-suite integrity
(`fix/test-suite-integrity`)

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
| Test-suite integrity | vacuous assertions, fail-open skips, git isolation, fixture speed | this change |
| CLI | signal exit codes, doctor schema validation, migrate, help | ready; lands with the manifest workstream (template dependency) |
| Manifest, lint and shared lib | JSON generation, binary-safe scans, injection scan scope, template | ready, next |
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | ready |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | ready |
| Documentation | README split, ADR fixes, redaction of internal details | after the code workstreams |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | last |

## This change: test-suite integrity

A read-only review of the bats suite found tests that could not fail. This change makes
them fail, and adds guards so the patterns cannot come back.

- Dead negations: in bats a bare `! cmd` that is not the last command of a test never
  fails it. `tests/archive.bats` and two `tests/migrate-grounding.bats` preconditions
  used it; they now assert the exit status. `npm run check` runs a new
  `check:bats-negations` guard (`tests/assert-bats-negations.mjs`) over every test file.
- Fail-open skips: prerequisite checks for ajv-cli, python and symlinks skipped when the
  lookup broke, so a broken lookup looked green. `require_tool` skips locally and fails
  when `CI` is set, and `scripts/run-bats.mjs` fails a CI run on any skip not in its
  explicit allowlist.
- Wiring checks that were only ever run green now have red controls.
- Assertions that only checked for missing output also require exit 0 and a positive
  result, so a crash cannot pass them.
- Isolation: tests no longer read the machine's global or system git config, repository
  variables leaked by git hooks, or repositories above the temp directory.
- Speed: the git fixture is built once per run and copied per test (setup cost per test
  about 22 to 7 ms on Linux, about 595 to 201 ms on Windows, measured by micro-benchmark).
- `scripts/run-bats.mjs` refuses a first-on-PATH bash older than 4.1, where a failing
  `[[ ]]` that is not the last command does not fail a test; `AAHP_ALLOW_OLD_BASH=1`
  overrides.

## Validation

- Workstream tree on a Linux runner: `npm test` 627 of 627 passed, 0 skipped; mutation
  proofs for each item (the old tests stayed green against a mutated implementation, the
  new ones went red).
- Rebased onto `3e8e8d7`: the negation guard reported its only exemption, for
  `tests/propagate.bats`, as stale (#120 fixed that line). With nothing left to exempt,
  the exemption mechanism and its test were removed, so a dead negation can only be
  fixed, never listed. It scans 28 files clean, including `tests/install-hooks.bats`.
- Not measured: macOS. The full-suite wall time on the shared runner was dominated by
  load from parallel work, so the speed claim rests on the micro-benchmarks. The GitHub
  Actions run on this pull request is the CI verdict.

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

1. `propagate.sh` now refuses a target that does not lock `@elvatis_com/aahp` (exit 3),
   because the installed workflow cannot run without it. Is a non-npm consumer a supported
   case?
2. Should `aahp init` gain an option to scaffold the adopter verify workflow?
3. Keep the dogfood workflow out of the npm package (this change removes it)?
4. Legacy adopter copies of the governance workflow: doctor detection or a force-upgrade
   path beyond the migration note.
5. Replacement of `ajv-cli@5.0.0`, whose transitive tree emits deprecation warnings for
   `glob@7.2.3` and `inflight@1.0.6` (no vulnerability reported, no newer release).
6. The test runner now refuses a first-on-PATH bash older than 4.1 (macOS `/bin/bash` is
   3.2), because bats cannot fail a non-final `[[ ]]` there. Keep the refusal (override
   `AAHP_ALLOW_OLD_BASH=1`), or convert assertions instead?

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
