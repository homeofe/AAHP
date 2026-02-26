# AAHP: Build Dashboard

> Single source of truth for build health, test coverage, and pipeline state.
> Updated by agents at the end of every completed task.

---

## Components

| Name | Path | Build | Tests | Status | Notes |
|------|------|-------|-------|--------|-------|
| v2 Specification | `README.md` | ✅ | n/a | ✅ | 413 lines, all sections complete |
| Templates (10) | `templates/` | ✅ | n/a | ✅ | All handoff file templates ready |
| Shared Library | `scripts/_aahp-lib.sh` | ✅ | manual | ✅ | Checksum, mtime, summary, tokens |
| Manifest Generator | `scripts/aahp-manifest.sh` | ✅ | manual | ✅ | CLI with full option set |
| Migration Script | `scripts/aahp-migrate-v2.sh` | ✅ | manual | ✅ | Delegates to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | ✅ | manual | ✅ | 6 checks |
| JSON Schema | `schema/aahp-manifest.schema.json` | ✅ | n/a | ✅ | JSON Schema Draft 2020-12 |
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
| GitHub Actions CI | ⏳ Not created | Needs workflow file |
| npm package | ⏳ Not created | Needs package.json |

---

## Pipeline State

| Field | Value |
|-------|-------|
| Current task | Dogfooding: bootstrap .ai/handoff/ |
| Phase | implementation |
| Last completed | Resolve open questions 1-4 |
| Rate limit | None |

---

## Open Tasks (strategic priority)

| # | Task | Priority | Blocked by | Ready? |
|---|------|----------|-----------|--------|
| 1 | Design v3 task dependency graph schema | HIGH | - | ✅ Ready |
| 2 | Add task IDs to NEXT_ACTIONS.md and DASHBOARD.md | HIGH | - | ✅ Ready |
| 3 | Add GitHub Actions CI pipeline | MEDIUM | - | ✅ Ready |
| 4 | Create npx-distributable CLI | MEDIUM | - | ✅ Ready |
| 5 | Add automated script tests (bats) | MEDIUM | - | ✅ Ready |

---

## Update Instructions (for agents)

After completing any task:

1. Update the relevant row to ✅ with current date
2. Update test counts
3. Update "Pipeline State"
4. Move completed task out of "Open Tasks"
5. Add newly discovered tasks with correct priority

**Pipeline rules:**
- Blocked task → skip, take next unblocked
- All tasks blocked → notify the project owner
- Notify project owner only on **fully completed tasks**
