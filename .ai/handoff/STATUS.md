# AAHP: Current State of the Nation

> Last updated: 2026-02-27 by Claude Opus 4.6
> Commit: (pending)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP v3 complete. All 5 original tasks done. T-006 (npm publish) prepared: package.json
has test/prepublishOnly scripts, `npm pack --dry-run` verified 19 files, name `aahp`
available on npm. Blocked on npm authentication (requires `npm login` in interactive
terminal). 48 bats tests passing. Next: user runs `npm login` then `npm publish --access public`.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `scripts pass` | ✅ | All scripts tested, 48 bats tests pass |
| `lint-handoff.sh` | ✅ | All 6 checks pass, cross-platform Python detection |
| `schema valid` | ✅ | v3 schema with tasks + next_task_id |
| `shellcheck` | ⏳ | Configured in CI, not yet run remotely |
| `npx aahp` CLI | ✅ | init, manifest, lint, migrate commands work |
| `bats tests` | ✅ | 48/48 pass (18 lint + 18 manifest + 12 migrate) |
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
| CI Pipeline | `.github/workflows/ci.yml` | ✅ Complete | shellcheck, lint, schema validation |
| Test Suite | `tests/*.bats` | ✅ Complete | 48 tests across 3 suites |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| npm publish | LOW | Package verified and ready; needs `npm login` then `npm publish --access public` |
| shellcheck fixes | LOW | Scripts may need fixes once shellcheck runs in CI |
| CI run | LOW | Workflow created but not yet triggered on GitHub |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved

| ID | Item | Resolution |
|----|------|-----------|
| T-003 | GitHub Actions CI pipeline | `.github/workflows/ci.yml` -shellcheck, lint, schema validation |
| T-004 | npx-distributable CLI | `bin/aahp.js` + `package.json` -init, manifest, lint, migrate |
| T-005 | Automated script tests | 48 bats tests: `tests/manifest.bats`, `tests/lint.bats`, `tests/migrate.bats` |
| T-001 | v3 task dependency graph schema | Schema extended, README Section 8 written |
| T-002 | Task IDs in templates | T-xxx format in headings and tables |

---

## Trust Levels

- **(Verified)**: All scripts produce correct output, 48/48 bats tests pass, lint passes, CLI works
- **(Verified)**: `npm pack --dry-run` produces correct tarball (19 files, 26.2 kB), name `aahp` available on npm
- **(Assumed)**: CI pipeline will pass on GitHub (created but not yet triggered)
- **(Unknown)**: shellcheck compliance (may require script fixes), macOS shasum fallback
