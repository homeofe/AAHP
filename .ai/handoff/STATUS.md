# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 4.0.0 (release candidate on branch release/4.0.0; not tagged, not published); previous release 3.12.0
Protocol version: 3.0
Working state: release 4.0.0 prepared; tagging and the publish approval are the owner's steps

## Current objective

Release 4.0.0. On 2026-09-28 the owner asked for every finding of a full audit to be
fixed and every open item to be implemented before going to 4.0.0. That work is on
main (#119 to #130). This change cuts the release: the `[4.0.0]` CHANGELOG section,
`package.json` and lockfile at 4.0.0, and this handoff state.

The remaining steps, in order:

1. Merge this pull request once CI is green.
2. Owner, on npmjs.com: set the trusted-publisher Environment name of
   `@elvatis_com/aahp` to `npm-publish` (confirmed empty on 2026-09-28).
3. Push the tag `v4.0.0` on the merge commit on main (the tag ruleset admits
   administrators only).
4. Owner: approve the `npm-publish` deployment in the Actions run (required reviewer,
   no admin bypass). Then verify the npm version, its provenance and the GitHub Release.
5. supply-chain-guard, the first adopter to move: open its upgrade pull request right
   away (bump, `handoffImpact.npmDevDependencyUpdates` with `supplyChainScan`, STATUS
   entry, regenerated MANIFEST.json), as README 5.1 describes.

## What 4.0.0 contains

- Consumer install path (#120): a shipped adopter verify workflow that runs the
  lockfile-pinned CLI; propagate vendors its full closure; install-hooks works in
  linked worktrees.
- Test integrity (#121): vacuous assertions and fail-open skips removed and guarded.
- Manifest, lint and CLI (#122): valid JSON always, binary-safe lint over every handoff
  file, full-schema doctor, signal exit codes.
- Verify semantics (#124): check-backed TRUST claims with a grace period, a
  content-based Layer 2 exemption for dev-only lockfile updates, Layer 3 that can pass.
- CI and release (#125, #129): scanner gates publishing, guarded release ref, grouped
  Dependabot with cooldown, publishing through a protected environment, ajv-cli
  replaced (no deprecated dependencies left).
- Documentation (#126), full ASCII (#127), owner follow-ups (#128: `init --gates`
  scaffolds `pinnedDep` and the adopter workflow, PII scan over JSON values, LOG
  redaction marker with `aahp archive --reindex`).
- Adopter upgrade path (#130): `aahp migrate` removes template placeholders, the doctor
  gate `cli-source` flags legacy CLI invocations, `aahp init --gates --workflows`.

Why a major version: an upgrade can turn an adopter's CI red until it acts. Doctor
validates the full manifest schema and adds `cli-source`, `propagate.sh` refuses targets
without a pinned lockfile, lint prints ASCII marks, the dogfood verify workflow left the
package, and `generate.log.target` is required. Each has a Migration note in the
CHANGELOG, and README 5.1 walks through the upgrade.

## Validation

- Every pull request of the programme ran the full suite on Linux before merge and all
  required checks on GitHub; main at `5d80088` passed CI.
- This change, on a Linux runner on top of `5d80088`: `npm run check` (changelog format,
  version sync and presence included), `doctor`, lint, archive verify, the schema
  validation and the PII validator exit 0; `CI=true npm test` 929 of 929, 0 skipped;
  `npm pack --dry-run` gives `@elvatis_com/aahp` 4.0.0 with 59 files.
- A real adopter still on 3.12.0 was tested against the 4.0.0 content: with the upgrade
  pull request described above, verify, doctor and check pass.

## Owner decisions

Decided on 2026-09-28:

- Release as 4.0.0 once everything open is fixed and implemented.
- Full ASCII in tracked text, enforced by a gate.
- Dependabot: grouped updates, a 7-day cooldown, and an opt-in, content-based Layer 2
  exemption for dev-only lockfile changes. Never actor-based.
- TRUST-TTL: executable claims checked on every run, and a grace period for judgment rows.
- STATUS.md is a bounded snapshot; LOG.md is the only journal.
- README split into quickstart and normative spec, with ADRs and governance in `docs/`;
  `docs/` is not shipped to npm.
- Internal hostnames and figures about other repositories are removed from public files.
- Repository settings: `Supply chain guard` is a required check on main, a ruleset
  protects `refs/tags/v*`, `sha_pinning_required` is on, and the `npm-publish`
  environment requires the owner's approval for `v*` tags without admin bypass.

Open:

1. The release steps above (npm Environment field, tag, deployment approval).
2. supply-chain-guard, for that repository's maintainer: homeofe/supply-chain-guard#354,
   #355 and #356 are open and green; after the 4.0.0 release its upgrade pull request follows. Its own follow-ups:
   pin its npm dependencies with a shrinkwrap, read extensionless scripts in its PyPI and
   VSIX scanners, POD-aware internal-disclosure handling, and its STATUS.md, still a
   prepend log.

## Constraints for the next agent

- Tag only a commit on main whose CI passed, and only as `vX.Y.Z` equal to `package.json`.
- Integrate one change per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Re-verify a TRUST row against the tree before moving its date.
- Regenerate MANIFEST.json after every handoff-file change.
