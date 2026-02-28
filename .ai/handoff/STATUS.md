# AAHP: Current State of the Nation

> Last updated: 2026-02-28 by Claude Opus 4.6
> Commit: (pending)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP v3 complete. All 10 tasks (T-001 through T-010) done. T-011 (npm publish) blocked on
npm auth - token expired, interactive login required. Added GitHub Actions publish workflow
(`.github/workflows/publish.yml`) with manual trigger and dry-run option. Package fully
ready: 48 bats tests pass, `npm pack --dry-run` verified 19 files (26.5 kB), name `aahp`
available on npm. User can publish via CI (create npm Automation token, add as `NPM_TOKEN`
secret, trigger workflow) or locally (`npm login` then `npm publish --access public`).
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `scripts pass` | ✅ | All scripts tested, 48 bats tests pass |
| `lint-handoff.sh` | ✅ | All 6 checks pass, cross-platform Python detection |
| `schema valid` | ✅ | v3 schema with tasks + next_task_id |
| `shellcheck` | ✅ | All 6 scripts pass (info-level, zero warnings) |
| `npx aahp` CLI | ✅ | init, manifest, lint, migrate commands work |
| `bats tests` | ✅ | 48/48 pass (18 lint + 18 manifest + 12 migrate) |
| `npm publish` | ❌ | Blocked on expired npm auth token |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| v2/v3 Specification | `README.md` | ✅ Complete | 8 sections, updated title/refs for v3 |
| Templates (10 files) | `templates/` | ✅ Complete | T-xxx ID format |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ Complete | v3: preserves tasks on regen |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ Complete | Checksum, mtime, summary, tokens |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ Complete | Delegates to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | ✅ Complete | 6 checks, cross-platform Python |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ Complete | v3: tasks + next_task_id fields |
| .aiignore Template | `templates/.aiignore` | ✅ Complete | Secrets, PII, injection patterns |
| CLI (npx aahp) | `bin/aahp.js` + `package.json` | ✅ Complete | init, manifest, lint, migrate |
| CI Pipeline | `.github/workflows/ci.yml` | ✅ Complete | shellcheck, lint, schema, bats tests |
| Publish Workflow | `.github/workflows/publish.yml` | ✅ Complete | Manual trigger, dry-run option |
| Test Suite | `tests/*.bats` | ✅ Complete | 48 tests across 3 suites |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| npm publish | LOW | Package ready; needs npm auth token then publish via CI or local |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved

| ID | Item | Resolution |
|----|------|-----------|
| T-010 | Fix shellcheck warnings in CI | All 6 scripts pass shellcheck |
| T-009 | Add bats tests to CI pipeline | 48/48 bats tests run in CI |
| T-003 | GitHub Actions CI pipeline | `.github/workflows/ci.yml` - shellcheck, lint, schema, tests |
| T-004 | npx-distributable CLI | `bin/aahp.js` + `package.json` - init, manifest, lint, migrate |
| T-005 | Automated script tests | 48 bats tests across 3 suites |

---

## Trust Levels

- **(Verified)**: All scripts produce correct output, 48/48 bats tests pass, lint passes, CLI works
- **(Verified)**: `npm pack --dry-run` produces correct tarball (19 files, 26.5 kB), name `aahp` available on npm
- **(Verified)**: CI pipeline passes (shellcheck, lint, schema validation, bats tests)
- **(Verified)**: Publish workflow created with manual trigger and dry-run support
- **(Blocked)**: npm auth token expired, cannot publish without human intervention
