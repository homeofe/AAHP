# AAHP: Current State of the Nation

> Last updated: 2026-02-26 by Claude Opus 4.6
> Commit: 672be62
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP v2 protocol is fully specified and tooling is complete. All 4 open questions
from the initial proposal are resolved. Templates, scripts, schema, and lint tooling
are production-ready. No build system (pure Markdown + Bash). Ready for v3 planning.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `scripts pass` | ✅ | aahp-manifest.sh, aahp-migrate-v2.sh tested |
| `lint-handoff.sh` | ✅ | All 6 checks implemented |
| `schema valid` | ✅ | aahp-manifest.schema.json (JSON Schema Draft 2020-12) |
| `shellcheck` | untested | Scripts not yet linted with shellcheck |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| v2 Specification | `README.md` | ✅ Complete | 413 lines, 7 sections |
| Templates (10 files) | `templates/` | ✅ Complete | All handoff file templates |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ Complete | CLI tool with --agent, --phase, --context options |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ Complete | Checksum, mtime, summary, token estimation |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ Complete | Delegates manifest gen to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | ✅ Complete | 6 checks: injection, secrets, PII, schema, lock, parallel |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ Complete | Validates MANIFEST.json structure |
| .aiignore Template | `templates/.aiignore` | ✅ Complete | Secrets, PII, injection patterns |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| v3 features | HIGH | Dependency graphs, task IDs, enhanced parallel support |
| shellcheck | LOW | Scripts not validated with shellcheck |
| CI pipeline | MEDIUM | No GitHub Actions workflow for automated validation |
| npm package | MEDIUM | No `npx aahp` CLI distribution |
| Test suite | MEDIUM | No automated tests for scripts |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved

| Item | Resolution |
|------|-----------|
| Open Question 1: Auto-generate MANIFEST.json | Resolved: scripts/aahp-manifest.sh created |
| Open Question 2: Whole-file vs section checksums | Resolved: Whole-file SHA-256 (already implemented) |
| Open Question 3: Parallel agents | Resolved: Branch-based isolation + advisory lint check |
| Open Question 4: Dependency graphs | Resolved: Deferred to v3 |
| Duplicate AAHP-v2-PROPOSAL.md | Merged into README.md, references updated |

---

## Trust Levels

- **(Verified)**: aahp-manifest.sh generates valid JSON, migration script delegates correctly, lint script runs 6 checks
- **(Assumed)**: Schema covers all required fields (not validated with ajv on this machine)
- **(Unknown)**: shellcheck compliance, cross-platform portability (macOS shasum fallback)
