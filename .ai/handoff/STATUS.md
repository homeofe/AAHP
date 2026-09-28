# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; pre-4.0.0 work; this change binds publishing to a protected environment and replaces ajv-cli (branch fix/release-env-and-ajv)

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

## This change: protected publish environment, ajv-cli replaced

The owner decided on 2026-09-28 to fix and implement everything still open before
releasing 4.0.0. This change closes two of the open items.

- Publish environment: the GitHub environment `npm-publish` exists (created and read back
  through the API on 2026-09-28): the owner is the required reviewer, only tags matching
  `v*` may deploy, and administrators cannot bypass it (`can_admins_bypass` false). The
  publish job names it, so every npm publish waits for the owner's approval on the run
  page. The release job stays unbound on purpose (it needs `publish`, holds no OIDC
  grant; binding it would ask for a second approval). A test fails when the binding is
  removed or renamed. ADR-019 is amended, and CONTRIBUTING's release ceremony has an
  approval step. The npm-side trusted-publisher Environment field was confirmed empty by
  the owner, who sets it to `npm-publish` once this is on main.
- ajv-cli replaced: `scripts/validate-json-schema.mjs` validates with the `ajv` and
  `ajv-formats` libraries (draft 2020-12, formats in full mode, ajv's strict mode) and
  gives the same verdict as ajv-cli 5.0.0 on a 27-case corpus. The locked devDependency
  closure goes from 28 to 8 packages and `npm ci` prints no deprecation warning (it
  printed two: glob 7.2.3 and inflight 1.0.6). No workflow runs `npx` any more. The unused
  `fast-json-patch` override is removed.

## Validation

- Workstream tree on a Linux runner: `CI=true npm test` 899 of 899, 0 skipped; `npm run
  check` (14 gates), `doctor`, lint and archive verify exit 0; mutation proofs for the
  environment binding and each validator property (formats mode, strict mode, 2020-12,
  exit codes, BOM handling, import side effect, the pinning of ajv).
- Not proven here: a real publish through the environment happens only on a tag.
- Integrated onto `f37a89a`: `CI=true npm test` 899 of 899, 0 skipped; `npm run check`,
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

1. Legacy adopter copies of the governance workflow: doctor detection or a force-upgrade
   path beyond the migration note.
2. Consumer manifests that still carry template placeholder dates will fail `aahp doctor`
   after upgrading. The CHANGELOG carries the migration note; should those repositories be
   fixed before the release?
3. Release: the programme is complete on main. Everything under CHANGELOG `##
   [Unreleased]` is unreleased; whether and when to release (and which version: the
   content includes breaking changes for adopters, see the Migration notes) is the owner's
   decision.
4. supply-chain-guard follow-ups, for that repository: homeofe/supply-chain-guard#354
   awaits its maintainer's merge; still open there are content-scanning extensionless
   shebang scripts and `.bats` files, installing the scanner by integrity rather than by
   version in its Action, its actor-based Dependabot exemption from `aahp-verify` (the
   content-based `npmDevDependencyUpdates` exemption can replace it), and its STATUS.md,
   still a prepend log.
5. Owner, on npmjs.com: set the trusted-publisher Environment name of @elvatis_com/aahp to
   `npm-publish` (confirmed empty on 2026-09-28), so a workflow edited to drop the binding
   cannot publish either.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
