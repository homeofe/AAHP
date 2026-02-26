# AAHP: Current State of the Nation

> Last updated: 2026-02-26 by Claude Opus 4.6
> Commit: bfa882e
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP v3 implemented. Task IDs (T-xxx format) and dependency graphs added to the
protocol. Schema extended, templates updated, manifest generator preserves task data.
All v2 tooling still works. 3 remaining tasks: CI pipeline (T-003), npm CLI (T-004),
automated tests (T-005).
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `scripts pass` | ✅ | aahp-manifest.sh tested with task preservation |
| `lint-handoff.sh` | ✅ | All 6 checks implemented |
| `schema valid` | ✅ | Extended with v3 tasks + next_task_id |
| `shellcheck` | untested | Scripts not yet linted with shellcheck |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| v2/v3 Specification | `README.md` | ✅ Complete | 8 sections, v3 adds task IDs + deps |
| Templates (10 files) | `templates/` | ✅ Complete | Updated with T-xxx ID format |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ Complete | v3: preserves tasks on regen |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ Complete | Checksum, mtime, summary, tokens |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ Complete | Delegates to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | ✅ Complete | 6 checks |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ Complete | v3: tasks + next_task_id fields |
| .aiignore Template | `templates/.aiignore` | ✅ Complete | Secrets, PII, injection patterns |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | ID | Description |
|-----|----------|----|-------------|
| CI pipeline | MEDIUM | T-003 | No GitHub Actions workflow for automated validation |
| npm package | MEDIUM | T-004 | No `npx aahp` CLI distribution |
| Test suite | MEDIUM | T-005 | No automated tests for scripts |
| shellcheck | LOW | - | Scripts not validated with shellcheck |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved

| ID | Item | Resolution |
|----|------|-----------|
| T-001 | v3 task dependency graph schema | Schema extended, README Section 8 written |
| T-002 | Task IDs in templates | T-xxx format in headings and tables |
| - | Open questions 1-4 | All resolved with tooling and documentation |
| - | AAHP-v2-PROPOSAL.md merge | Consolidated into README.md |

---

## Trust Levels

- **(Verified)**: manifest generator produces valid JSON, preserves tasks on regen, lint runs 6 checks
- **(Assumed)**: v3 schema validates correctly (no ajv on this machine), v2 backward compat works
- **(Unknown)**: shellcheck compliance, cross-platform portability (macOS shasum fallback)
