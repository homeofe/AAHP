# AAHP: Next Actions for Incoming Agent

> The MANIFEST task graph is authoritative. Owner decisions below are not autonomous
> tasks and therefore do not appear as ready or blocked task entries.

Current version: **v3.11.0**

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 5 |
| Ready | 0 |
| Blocked | 0 |

---

## Recently Completed

### 2026-08-31: PR #109 integration and scanner v6.0.8 refresh

- Integrated the three CodeQL v4.37.8 pins from Dependabot PR #109.
- Updated supply-chain-guard to the signed v6.0.8 release commit and kept the policy
  schema pinned to the same immutable source.
- Confirmed the README already carries the `aahp-verify` workflow badge; added an
  availability badge for the shipped governance template and a dynamic Node badge.

### 2026-08-31: Third-party prompt audit and cross-platform hardening

- Reconciled every recommendation with the current repository and rejected stale or
  technically incorrect instructions.
- Added an immutable, least-privilege supply-chain scan and its runtime-compatible empty
  policy.
- Removed the unpinned npm self-update from trusted publishing.
- Added a locked, portable Bats runner and repaired Windows/Linux test assumptions.
- Fixed private-key header detection and added regression coverage.
- Added adopter remediation for verify-workflow bypasses and pre-3.9.2 project-name
  corruption.
- Verified the patched tree on Windows and in a fresh Linux clone under `/tmp`.

### 2026-08-20: v3.10.0 prepared - fail-closed CI base + reviewed M-only impact

- Added explicit `--base SHA` / `AAHP_BASE_SHA` anchoring and strict invalid-base checks.
- Added exact, reasoned non-impacting modified-file entries; only `M` can be exempted.
- Removed the actor-wide dependency-bot workflow bypass.

### 2026-08-05: v3.9.2 - Windows bash portability + project-name preservation

- Unified Bash resolution and Windows path conversion.
- Preserved existing MANIFEST project names during regeneration.

### 2026-08-03: Handoff hygiene + doctor partial-index alignment

- Aligned the workflow, status snapshot, manifest summaries, and partial-index behavior.

### T-033: Reusable AAHP badge workflows

- Added stable AAHP Verify, Lint, Manifest, Archive, and PII Allowlist badge workflows.

### T-032: LOG archive integrity

- Added `aahp archive`, integrity verification, and regression tests.

### T-031: Reviewed, expiring PII allowlist

- Added a strict allowlist with owner, reason, expiry, schema, and tests.

### T-014 through T-017 and T-006

- CLI integration coverage, `aahp status`, `aahp archive`, project guidance, and npm
  publication were completed in earlier releases. Closure evidence remains in git
  history and the archived handoff journal.

---

## Owner Decisions (not task registry entries)

- Reconcile the full-ASCII wording with the implemented U+2014-only gate.
- Choose manual repair or bot-authored handoff updates for future Dependabot action bumps.
- Choose whether legacy governance workflows need doctor detection or forced migration.
- After a real CI run, consider a scanner TRUST row and required status check.
- Plan a future replacement for the deprecated transitive dependencies of ajv-cli 5.

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
