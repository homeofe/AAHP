# AAHP: Build Dashboard

> Single source of truth for build health, test coverage, and pipeline state.
> Updated by agents at the end of every completed task.

---

## Components

| Name | Path | Build | Tests | Status | Notes |
|------|------|-------|-------|--------|-------|
| v2/v3 Specification | `README.md` | ✅ | n/a | ✅ | Updated title/refs for v3 |
| Templates (10) | `templates/` | ✅ | n/a | ✅ | T-xxx ID format |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ | ✅ 18 | ✅ | Tested via manifest.bats |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ | ✅ 18 | ✅ | 18 bats tests |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ | ✅ 12 | ✅ | 12 bats tests |
| Lint Script | `scripts/lint-handoff.sh` | ✅ | ✅ 18 | ✅ | 18 bats tests |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ | n/a | ✅ | v3: tasks + next_task_id |
| .aiignore Template | `templates/.aiignore` | ✅ | n/a | ✅ | Secrets, PII patterns |
| CLI (npx aahp) | `bin/aahp.js` | ✅ | manual | ✅ | init, manifest, lint, migrate |
| CI Pipeline | `.github/workflows/ci.yml` | ✅ | n/a | ✅ | shellcheck + lint + schema |

**Legend:** ✅ passing / complete · ❌ failing · ⏳ pending · manual = tested manually only

---

## Test Coverage

| Suite | Tests | Status | Last Run |
|-------|-------|--------|----------|
| manifest.bats | 18 | ✅ All pass | 2026-02-26 |
| lint.bats | 18 | ✅ All pass | 2026-02-26 |
| migrate.bats | 12 | ✅ All pass | 2026-02-26 |
| shellcheck | - | ⏳ In CI | Not yet run |
| schema validation | manual | ✅ | 2026-02-26 |

**Total: 48 tests, 48 passing**

---

## Infrastructure / Deployment

| Component | Status | Blocker |
|-----------|--------|---------|
| GitHub repo | ✅ | - |
| GitHub Actions CI | ✅ Created | Not yet triggered (T-007) |
| npm package | ⏳ Ready to publish | Needs `npm login` then `npm publish --access public` (T-006) |

---

## Pipeline State

| Field | Value |
|-------|-------|
| Current task | All tasks complete |
| Phase | done |
| Last completed | T-008: Add bats tests to CI (2026-02-27) |
| Rate limit | None |

---

## Open Tasks (strategic priority)

| ID | Task | Priority | Depends on | Ready? |
|----|------|----------|-----------|--------|
| - | (no open tasks) | - | - | - |

## Completed Tasks

| ID | Task | Completed |
|----|------|-----------|
| T-001 | Design v3 task dependency graph schema | 2026-02-26 |
| T-002 | Add task IDs to templates | 2026-02-26 |
| T-003 | Add GitHub Actions CI pipeline | 2026-02-26 |
| T-004 | Create npx-distributable CLI | 2026-02-26 |
| T-005 | Add automated script tests (bats) | 2026-02-26 |
| T-006 | Publish npm package | 2026-02-27 |
| T-007 | Fix shellcheck warnings in CI | 2026-02-27 |
| T-008 | Add bats tests to CI pipeline | 2026-02-27 |

---

## Update Instructions (for agents)

After completing any task:

1. Update the relevant row in Open/Completed Tasks
2. Update component status table
3. Update "Pipeline State"
4. Add newly discovered tasks with correct priority and task ID

**Pipeline rules:**
- Blocked task → skip, take next unblocked
- All tasks blocked → notify the project owner
- Notify project owner only on **fully completed tasks**
- Check `depends_on` in MANIFEST.json before starting a task
