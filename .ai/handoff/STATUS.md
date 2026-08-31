# AAHP: Current Status

Last updated: 2026-08-31
Current package version: 3.11.0
Protocol version: 3.0
Working state: implementation complete on `codex/prompt-audit-supply-chain-guard`, not released

## Current objective

Audit the repository against the supplied third-party review prompt, correct stale or
unsafe recommendations, implement the valid findings, and verify the result on Windows
and Linux. No commit, push, merge, tag, npm publish, or GitHub issue mutation is part of
this working state.

## Implemented in this working tree

- Added a pull-request and main-branch supply-chain scan to CI, pinned to the peeled
  supply-chain-guard v6.0.8 commit. The job has read-only contents permission, disables
  checkout credential persistence, and does not request PR comment permission.
- Added `.supply-chain-guard.yml`. The v6.0.8 runtime rejects the schema-valid
  `suppress: []` spelling, so the effective empty policy is `{}` with the incompatibility
  documented in comments.
- Removed the unpinned global `npm install -g npm@latest` from trusted publishing. The
  existing Node 24 / npm 11 toolchain already meets npm's trusted-publishing minimum.
- Made the repository test entry point portable: `npm test` now uses the locked local
  Bats dependency through the new Node launcher; `tests/run.sh` delegates to the same
  runner and no longer depends on global Bats or `npx` downloads.
- Fixed Windows-specific assumptions in CLI, lint, and manifest tests while preserving
  the Linux behavior they exercise.
- Fixed private-key detection in `scripts/lint-handoff.sh`: grep now receives `--`
  before a pattern beginning with hyphens. The previous command could parse a real
  private-key header as an option instead of detecting it.
- Strengthened workflow pinning tests so global npm installs are rejected too, and added
  exact tests for the scanner job, permissions, immutable references, policy, and event
  scope.
- Expanded doctor and README remediation for bypassable adopter verify workflows, and
  documented how adopters can detect and repair a project name written by versions
  before 3.9.2.
- Corrected project guidance from Node 18+ to Node 22+ and removed stale, contradictory
  trusted-publishing comments.
- Integrated Dependabot PR #109's three CodeQL action updates from v4.37.7 to v4.37.8,
  retaining immutable commit pins.
- Confirmed the `aahp-verify` workflow badge is already present in the README. Added an
  honest `AAHP Govern - available` badge linked to the shipped consumer template instead
  of inventing a workflow status, plus a dynamic Node compatibility badge.

## Prompt reconciliation

Several recommendations in the supplied prompt were already complete or stale:

- `fast-json-patch` is already overridden to 3.1.1 and `npm audit` reports zero
  vulnerabilities.
- Handoff document paths, the hardened governance template, immutable action pins, and
  Dependabot's GitHub Actions lane already exist.
- The TRUST register had already been reviewed; unverifiable assertions were previously
  downgraded to `assumed`.
- Issues 68 and 71 are closed, and project-name preservation shipped in 3.9.2.
- The root scanner policy must not be added to `MANIFEST.json.files`; that index is the
  handoff integrity set, not a repository-wide file inventory.
- A TRUST `verified` row for the scanner would be premature until the workflow has run
  in GitHub Actions.

## Validation

Windows validation covers dependency installation, schemas, all deterministic checks,
doctor, package packing, the repository test suites, the policy schema, and a clean
snapshot scan. Linux validation runs from a fresh clone under `/tmp` on `openclaw` with
the same working-tree patch, ShellCheck, Python compilation, schemas, deterministic
checks, doctor, npm audit, supply-chain-guard, and the complete Bats suite.

The scanner's low-severity mode reports two expected medium heuristic findings in the
release workflow (OIDC publishing and secret-bearing upload behavior). At the configured
high threshold the repository is clean. These are not suppressed in policy because the
empty policy keeps future findings visible.

## Pull request state

- Dependabot PR #109's exact CodeQL changes are integrated in this branch. The old PR can
  be closed as superseded after the replacement pull request exists.
- No open GitHub issues were found during this audit.
- No tag, release, package publication, or merge was performed.

## Owner decisions and follow-up

These are decisions, not ready autonomous tasks, so the MANIFEST task graph remains at
5 done, 0 ready, and 0 blocked.

1. Decide whether the documented invariant should prohibit only U+2014 (the implemented
   gate) or require full ASCII. Thirty tracked files currently contain non-ASCII text, so
   claiming full ASCII and enforcing only one character are inconsistent.
2. Decide whether future Dependabot action bumps should be repaired manually or receive
   a bot-authored handoff update. Do not bypass Layer 2 merely because a change is
   action-only.
3. Decide whether old adopter copies of the governance workflow need doctor detection or
   a targeted force-upgrade path beyond release-note remediation.
4. After the first real scanner CI run, decide whether to add a time-bounded `verified`
   TRUST row and make the scanner a required status check.
5. Track replacement of `ajv-cli@5.0.0`. Its current transitive tree emits deprecation
   warnings for `glob@7.2.3` and `inflight@1.0.6`, although npm reports no vulnerability
   and no newer `ajv-cli` release is available.

## Constraints for the next agent

- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Do not merge the replacement pull request or cut a release until all required checks are
  green and the owner authorizes the external mutation.
- Regenerate MANIFEST.json after every handoff-file change.
