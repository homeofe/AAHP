# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes are listed under
`## [Unreleased]` in CHANGELOG.md
Protocol version: 3.0
Working state: audit fix programme in progress; this change is the consumer install path
(`fix/consumer-install-path`)

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
| Consumer install path | adopter verify workflow, propagate, install-hooks | this change |
| Test-suite integrity | vacuous assertions, fail-open skips, git isolation, fixture speed | ready, next |
| CLI | signal exit codes, doctor schema validation, migrate, help | ready; lands with or after the manifest workstream (template dependency) |
| Manifest, lint and shared lib | JSON generation, binary-safe scans, injection scan scope, template | in progress |
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | in progress |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | in progress |
| Documentation | README split, ADR fixes, redaction of internal details | after the code workstreams |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | last |

## This change: consumer install path

The shipped verify workflow could not run in any consumer. Measured on 2026-09-28 across
24 consumer repositories: none ran it unchanged. Each had replaced its steps, in three
different ways, and six fetched the CLI at runtime without a lockfile.

- New adopter workflow `assets/governance/aahp-verify.yml`: `npm ci --ignore-scripts`, then
  the lockfile-pinned CLI by path for `verify --level ci` and `doctor`. AAHP's own
  `.github/workflows/aahp-verify.yml` keeps running the working-tree gate, is no longer
  shipped in the npm package, and a parity test holds the two files to the same shape.
- `scripts/propagate.sh` installs the adopter workflow, vendors the complete helper
  closure (`check-conflict-markers.mjs` and `validate-pii-allowlist.py` were missing, so
  every vendored lint reported conflict markers), checks that closure after copying,
  makes a failed baseline verification fatal, accepts linked worktrees, and exits 3 before
  writing anything when the target does not lock `@elvatis_com/aahp`.
- `scripts/install-hooks.sh` resolves the hooks directory with `git rev-parse --git-path
  hooks` (hooks installed from a linked worktree were inert), strips CR, replaces a
  symlinked hook instead of writing through it, and never overwrites an earlier backup.
  `.gitattributes` checks out `scripts/hooks/*` with LF.
- README Quickstart re-measured end to end; the global-install option is replaced by what
  it loses.

## Validation

- Workstream tree on a Linux runner: `npm test` 629 of 629 passed, 0 skipped; 20 mutation
  proofs, each red with its fix reverted and green restored; ShellCheck clean on
  propagate, install-hooks and both hooks; `npm pack --dry-run` lists the adopter
  workflow and no longer the dogfood one.
- New tests execute every `run:` step of the installed workflow in a real npm consumer
  built from the packed tarball, green on an adopt commit and red on a drifted one.
- Not measured: macOS (bash 3.2, BSD tools) and Windows Git Bash runs of the changed
  scripts. The GitHub Actions run on this pull request is the CI verdict.

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
   because the installed workflow cannot run without it. Is a non-npm consumer a
   supported case?
2. Should `aahp init` gain an option to scaffold the adopter verify workflow?
3. Keep the dogfood workflow out of the npm package (this change removes it)?
4. Legacy adopter copies of the governance workflow: doctor detection or a force-upgrade
   path beyond the migration note.
5. Replacement of `ajv-cli@5.0.0`, whose transitive tree emits deprecation warnings for
   `glob@7.2.3` and `inflight@1.0.6` (no vulnerability reported, no newer release).

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
