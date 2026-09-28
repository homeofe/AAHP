# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change is the verify gate semantics (`fix/verify-gate-semantics`)

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
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | this change |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | ready, next |
| Documentation | README split, ADR fixes, redaction of internal details | after the code workstreams |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | last |

## This change: verify gate semantics

This change implements the owner decisions of 2026-09-28 on Layer 4 and Layer 2, and
fixes Layer 3 and the verify messages.

- Layer 4, executable claims: a `TRUST.md` row can name a check in a new `Check`
  column. The built-in checks are `license-matches` and `manifest-integrity`; more are
  declared as argv arrays in `aahp.config.json` `trustTtl.checks` (no shell, 120 s
  limit). A check-backed `verified` row is judged by its check on every run, not by a
  date. Nothing read from TRUST.md is ever executed.
- Layer 4, grace period: a date-judged `verified` row warns from its expiry and blocks
  under `trustTtl.enforce` only after `trustTtl.graceDays` (default 14). An empty or
  all-`assumed` register stays as visible as before, and Layer 4 prints a census.
- Layer 2, opt-in `handoffImpact.npmDevDependencyUpdates`: a lockfile-only change (plus
  devDependency specifiers) is non-impacting when every changed entry is `dev: true`,
  integrity-pinned, resolved from registry.npmjs.org and carries no install script. It
  is decided by content, never by author, and needs a `supplyChainScan` assertion that
  the gate re-proves on every run. Enabled here: the scanner job is a required check.
- Layer 3 reports OK when the recorded commit is an ancestor of HEAD and everything since
  changed only `.ai/handoff/`; before, it could never report OK after a commit.
- Layer 2 in a project that sits in a subdirectory of its repository compared paths
  from the repository root, so every change failed; paths are now project-relative.
- Messages name the concrete regeneration command instead of `/handoff`, the footer
  names the failing layer and its remedy, and a checksum mismatch advises inspecting
  `git diff -- .ai/handoff` before regenerating, because regenerating re-baselines
  tampering.
- This repository's TRUST.md gains the `Check` column; the template, license and
  checksum rows are now check-backed and carry no date. `tests/verify.bats` builds its
  fixture once (about 36% faster on Linux) and its python skips use `require_tool`.

## Validation

- Workstream tree on a Linux runner: `npm test` 648 of 648; 23 mutation proofs plus two
  for the install-script rule, each red with its guard removed and green restored (two
  inject a vulnerability instead: executing TRUST.md text, and running a declared check
  through a shell).
- Rebased onto `d27db82` by the integrator; the README Quickstart conflict with #120 was
  resolved to the new Layer 3 text and then measured: the Quickstart run end to end from
  a packed tarball in a fresh repository reports Layers 1, 2 and 3 OK and a Layer 4
  WARN, exit 0.
- Found during integration, on Windows only: the new `license-matches` check used
  `grep -qiF`, and the GNU grep 3.0 of Git for Windows aborts (exit 134) on any
  ignore-case plus fixed-string combination, so the check reported a correct LICENSE as
  wrong. It now lower-cases both sides and uses `grep -qF`; a static test forbids the
  flag combination in shipped scripts (mutation-proven). `verify --level ci` passes on
  Windows with all three check-backed rows re-proven.
- Not measured: macOS (bash 3.2). Portability is by construction: no mapfile, no
  associative arrays, no awk intervals.

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
7. Release train: the new manifest summaries break one assertion in supply-chain-guard
   (`src/__tests__/handoff-gate.test.ts` line 256 expects the old table-header summary `|
   Field | Value |` for STATUS.md). That test needs a one-line update when
   supply-chain-guard next bumps @elvatis_com/aahp.
8. Three consumer manifests will fail `aahp doctor` after upgrading, because they still
   carry template placeholder dates. The CHANGELOG carries the migration note; should
   those repos be fixed before the release?
9. Should lint's PII scan also read JSON string values (task notes, `assigned_to`)? It
   currently scans Markdown only, to avoid new failures in consumers.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
