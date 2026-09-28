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

### 2026-09-28: Documentation, spec split and redaction

- README is quickstart plus specification; the decision log lives in `docs/adr/`, the gate
  reference in `docs/governance.md`.
- Internal names and figures about other repositories are removed and guarded by
  forbidden-pattern rules; STATUS.md is a snapshot, LOG.md the journal.

### 2026-09-28: CI, release and dependency automation

- The scanner gates publishing and runs on tags; the publish job refuses tags off `main`
  or off the package version and runs no third-party code with the OIDC token.
- Dependabot is grouped with a cooldown; ShellCheck and installs in required jobs are
  pinned and script-free.

### 2026-09-28: Verify gate semantics

- TRUST rows can be check-backed and are re-proven on every run; dated rows get a 14-day
  grace period before blocking.
- Dev-only, integrity-pinned lockfile updates without install scripts are exempt from
  Layer 2 when a supply-chain scan is asserted; Layer 3 can report OK.

### 2026-09-28: Manifest generator, lint and CLI

- The manifest generator can no longer write invalid JSON or drop data silently; lint
  scans bytes as text and covers every handoff file.
- Doctor validates the full manifest schema; the CLI no longer exits 0 on a signal.

### 2026-09-28: Test-suite integrity

- Dead negations, fail-open skips and negative-only assertions now fail; a guard in `npm
  run check` and a CI skip audit keep them out.
- Tests are isolated from global git config and build their fixture once per run.

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
- Decide on a protected publish environment bound in the npm trusted-publisher config.
- Report the scanner coverage gaps (extensionless shell, .bats, install by version) to
  supply-chain-guard.
- Decide whether consumer manifests with template placeholder dates are fixed before the
  release.
- Decide whether `docs/` ships to npm and whether `init --gates` writes `pinnedDep`.

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
