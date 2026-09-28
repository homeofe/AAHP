# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 4.0.0 (released 2026-09-28: npm `latest` with provenance, GitHub Release v4.0.0); previous release 3.12.0
Protocol version: 3.0
Working state: 4.0.0 released; supply-chain-guard's upgrade pull request is open for that repository's maintainer

## Current objective

4.0.0 is released. On 2026-09-28 the owner asked for every finding of a full audit to
be fixed and every open item to be implemented before going to 4.0.0. That work is on
main (#119 to #130), and #131 cut the release.

How it shipped:

- Tag `v4.0.0` on `8ba12ba`, the merge commit of #131 on main.
- The owner set the npm trusted-publisher Environment name to `npm-publish` and
  approved the deployment of the tag run in that environment.
- `@elvatis_com/aahp@4.0.0` is on npm with dist-tag `latest` and a provenance
  attestation of type `https://slsa.dev/provenance/v1`. A fresh install reports a
  verified registry signature and a verified attestation, and the installed CLI
  prints 4.0.0.
- GitHub Release `v4.0.0` was published at 09:14 UTC and is the repository's latest
  release.

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

## First adopter: supply-chain-guard

homeofe/supply-chain-guard#357 is the one reviewed upgrade README 5.1 describes: the
exact pin 3.12.0 to 4.0.0, `handoffImpact.npmDevDependencyUpdates` tied to its `compat`
job, a STATUS entry and the regenerated manifest. Measured on a Linux runner against
the published 4.0.0:

- verify at level ci, lint, doctor (8 of 8 ran, `cli-source` advisory) and that
  repository's build gates pass.
- A simulated devDependency update on top passes Layer 2 through the exemption; the same
  update of a runtime dependency fails it.
- The scan the exemption names fails on a known-malicious dev-only lock entry.
- Its full suite passes once homeofe/supply-chain-guard#354 is merged. Before that, one
  test that expects the 3.12.0 manifest summary fails, so the upgrade merges after #354.

Merging is that repository's maintainer's step. #355 (Dependabot cooldown and groups,
the CLI by path) and #356 (scanner coverage) are independent of the upgrade.

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

1. supply-chain-guard, for that repository's maintainer: merge #354, then the upgrade
   #357 (after updating its branch); #355 and #356 in any order. Its own follow-ups:
   pin its npm dependencies with a shrinkwrap, read extensionless scripts in its PyPI and
   VSIX scanners, POD-aware internal-disclosure handling, and its STATUS.md, still a
   prepend log.

## Constraints for the next agent

- Tag only a commit on main whose CI passed, and only as `vX.Y.Z` equal to `package.json`.
- Integrate one change per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Re-verify a TRUST row against the tree before moving its date.
- Regenerate MANIFEST.json after every handoff-file change.
