# AAHP: Build Dashboard

> Single source of truth for build health, test coverage, and pipeline state.
> Updated by agents at the end of every completed task.

---

## Components

| Name | Path | Build | Tests | Status | Notes |
|------|------|-------|-------|--------|-------|
| v2/v3 Specification | `README.md` | ✅ | n/a | ✅ | v3 task IDs + dependency graphs added |
| Templates (10) | `templates/` | ✅ | n/a | ✅ | Updated with task ID format |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ | manual | ✅ | Checksum, mtime, summary, tokens |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ | manual | ✅ | v3: preserves tasks on regeneration |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ | manual | ✅ | Delegates to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | ✅ | manual | ✅ | 6 checks |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ | n/a | ✅ | v3: tasks + next_task_id fields |
| .aiignore Template | `templates/.aiignore` | ✅ | n/a | ✅ | Secrets, PII, injection patterns |

**Legend:** ✅ passing / complete · ❌ failing · ⏳ pending · manual = tested manually only

---

## Test Coverage

| Suite | Tests | Status | Last Run |
|-------|-------|--------|----------|
| script tests | 0 | ⏳ Not created | - |
| shellcheck | 0 | ⏳ Not run | - |
| schema validation | manual | ✅ | 2026-02-26 |

---

## Infrastructure / Deployment

| Component | Status | Blocker |
|-----------|--------|---------|
| GitHub repo | ✅ | - |
| GitHub Actions CI | ⏳ Not created | Needs workflow file (T-003) |
| npm package | ⏳ Not created | Needs package.json (T-004) |

---

## Pipeline State

| Field | Value |
|-------|-------|
| Current task | T-001 + T-002 (v3 implementation) |
| Phase | implementation |
| Last completed | T-001, T-002 |
| Rate limit | None |

---

## Open Tasks (strategic priority)

| ID | Task | Priority | Depends on | Ready? |
|----|------|----------|-----------|--------|
| T-003 | Add GitHub Actions CI pipeline | MEDIUM | - | ✅ Ready |
| T-004 | Create npx-distributable CLI | MEDIUM | - | ✅ Ready |
| T-005 | Add automated script tests (bats) | MEDIUM | - | ✅ Ready |

## Completed Tasks

| ID | Task | Completed |
|----|------|-----------|
| T-001 | Design v3 task dependency graph schema | 2026-02-26 |
| T-002 | Add task IDs to templates | 2026-02-26 |

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
