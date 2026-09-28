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

### 2026-09-28: Owner follow-up decisions

- `init --gates` scaffolds `pinnedDep` and the adopter verify workflow; lint's PII check
  reads JSON values.
- LOG redaction has a marker and `aahp archive --reindex`; the propagate and old-bash
  refusals name their fix.

### 2026-09-28: Full ASCII and remaining redaction

- Every tracked text file is ASCII, enforced by `check:ascii` in `npm run check`.
- No figures about other repositories remain in any tracked file; the rule now covers them
  all.

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

---

## Owner Decisions (not task registry entries)

Decided 2026-09-28 and being implemented by the audit fix programme (see STATUS.md): full
ASCII with a gate; grouped Dependabot updates plus a content-based Layer 2 exemption for
dev-only lockfile changes; executable TRUST claims with a grace period; STATUS.md as a
snapshot; README split; redaction of internal details; the scanner as a required check.

Open:

- Choose whether legacy governance workflows need doctor detection or forced migration.
- Plan a future replacement for the deprecated transitive dependencies of ajv-cli 5.
- Decide on a protected publish environment bound in the npm trusted-publisher config.
- Decide whether consumer manifests with template placeholder dates are fixed before the
  release.
- Decide whether and when to release the unreleased changes, and the version number.
- Track homeofe/supply-chain-guard#354 and its remaining follow-ups in that repository.

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
