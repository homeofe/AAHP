# AAHP: Next Actions for Incoming Agent

> The MANIFEST task graph is authoritative. Owner decisions below are not autonomous
> tasks and therefore do not appear as ready or blocked task entries.

Current version: **v4.0.0**

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 5 |
| Ready | 0 |
| Blocked | 0 |

---

## Recently Completed

### 2026-09-28: Release 4.0.0 prepared

- CHANGELOG `[4.0.0]`, `package.json` and lockfile at 4.0.0; STATUS.md lists the remaining
  release steps.
- Tag `v4.0.0` and the `npm-publish` approval are the owner's steps; supply-chain-guard's
  upgrade follows the release.

### 2026-09-28: Adopter upgrade path to 4.0.0

- `aahp migrate` removes template placeholders from task fields; doctor gains the
  `cli-source` gate (ADR-025) with `aahp init --gates --workflows` as its fix.
- README 5.1 documents the upgrade, including the one-time handoff step for the npm
  devDependency exemption.

### 2026-09-28: Protected publish environment, ajv-cli replaced

- npm publishing waits for the owner's approval in the `npm-publish` environment (tags
  `v*` only, no admin bypass).
- Schema validation runs on the ajv library through `scripts/validate-json-schema.mjs`;
  ajv-cli and its deprecated dependencies are gone.

### 2026-09-28: Owner follow-up decisions

- `init --gates` scaffolds `pinnedDep` and the adopter verify workflow; lint's PII check
  reads JSON values.
- LOG redaction has a marker and `aahp archive --reindex`; the propagate and old-bash
  refusals name their fix.

### 2026-09-28: Full ASCII and remaining redaction

- Every tracked text file is ASCII, enforced by `check:ascii` in `npm run check`.
- No figures about other repositories remain in any tracked file; the rule now covers them
  all.

---

## Owner Decisions (not task registry entries)

Decided 2026-09-28 and being implemented by the audit fix programme (see STATUS.md): full
ASCII with a gate; grouped Dependabot updates plus a content-based Layer 2 exemption for
dev-only lockfile changes; executable TRUST claims with a grace period; STATUS.md as a
snapshot; README split; redaction of internal details; the scanner as a required check.

Open:

- Track homeofe/supply-chain-guard#354 and its remaining follow-ups in that repository.
- Owner: set the npm trusted-publisher Environment name to `npm-publish`.
- Release 4.0.0: npm Environment field, tag `v4.0.0` on main, approve the `npm-publish`
  deployment, verify npm and the GitHub Release.

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
