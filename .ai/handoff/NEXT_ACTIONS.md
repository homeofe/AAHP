# AAHP: Next Actions for Incoming Agent

> The MANIFEST task graph is authoritative. Owner decisions below are not autonomous
> tasks and therefore do not appear as ready or blocked task entries.

Current version: **v3.12.0**

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 5 |
| Ready | 0 |
| Blocked | 0 |

---

## Recently Completed

### 2026-09-28: Manifest generator, lint and CLI

- The manifest generator can no longer write invalid JSON or drop data silently; lint
  scans bytes as text and covers every handoff file.
- Doctor validates the full manifest schema; the CLI no longer exits 0 on a signal.

### 2026-09-28: Test-suite integrity

- Dead negations, fail-open skips and negative-only assertions now fail; a guard in `npm
  run check` and a CI skip audit keep them out.
- Tests are isolated from global git config and build their fixture once per run.

### 2026-09-28: Consumer install path

- Shipped an adopter verify workflow that runs the lockfile-pinned CLI; the previous
  one could not run in any consumer.
- propagate vendors the full helper closure, fails on a failed baseline, and supports
  linked worktrees; install-hooks installs where git actually runs hooks.

### 2026-09-28: Dependabot integration and scanner v6.3.1

- Integrated #112, #113, #115 and #117 unchanged in #119 and closed them, together with
  #118, as superseded.
- Moved supply-chain-guard to the signed v6.3.1 release commit (current release) instead
  of #118's v6.2.0, with the pinned bats contract and policy schema anchor.
- Re-verified the two TRUST rows whose expiry on 2026-09-22 had turned `aahp-verify` red
  on every pull request.

### 2026-08-31: v3.12.0 release candidate

- Merged fully green PR #110 and closed Dependabot PR #109 as superseded.
- Prepared the 3.12.0 changelog, package metadata, lockfile metadata, and handoff state.
- Excluded generated Python bytecode from git and npm package contents.
- Recorded the first successful supply-chain-guard GitHub Actions run in TRUST.md.

---

## Owner Decisions (not task registry entries)

Decided 2026-09-28 and being implemented by the audit fix programme (see STATUS.md): full
ASCII with a gate; grouped Dependabot updates plus a content-based Layer 2 exemption for
dev-only lockfile changes; executable TRUST claims with a grace period; STATUS.md as a
snapshot; README split; redaction of internal details; the scanner as a required check.

Open:

- Is a consumer without an npm lockfile a supported propagate target (it now exits 3)?
- Should `aahp init` scaffold the adopter verify workflow?
- Keep the dogfood verify workflow out of the npm package?
- Choose whether legacy governance workflows need doctor detection or forced migration.
- Plan a future replacement for the deprecated transitive dependencies of ajv-cli 5.
- Coordinate the supply-chain-guard test that expects the old STATUS.md summary before its
  next aahp bump.
- Decide whether the three consumer manifests with template placeholder dates are fixed
  before the release.

---

## Blocked

None.

---

## Reference: Key File Locations

| What | Where |
|------|-------|
| Specification | `README.md` |
| Templates | `templates/` |
| Scripts | `scripts/` |
| Manifest schema | `schema/aahp-manifest.schema.json` |
| CLI entry point | `bin/aahp.js` |
| CI workflow | `.github/workflows/ci.yml` |
| Test suite | `tests/` |
| Current status | `.ai/handoff/STATUS.md` |
