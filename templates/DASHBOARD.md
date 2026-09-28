# [PROJECT]: Build Dashboard

> A derived display surface for humans: build health, test coverage, and pipeline
> state at a glance. It is not authoritative. Task selection reads the `tasks` graph in
> MANIFEST.json (WORKFLOW.md, Task Selection Rules); when this file and MANIFEST
> disagree, MANIFEST wins. Updated by agents at the end of every completed task.

---

## Services / Components

| Name | Version | Build | Tests | Status | Notes |
|------|---------|-------|-------|--------|-------|
| service-a | - | pass | - | ok | |
| service-b | - | pass | 42/42 pass | ok | |
| service-c | - | fail | - | blocked | See LOG.md |

**Legend:** pass / fail = last run; ok, stub, pending, blocked = component state

---

## Test Coverage

| Suite | Tests | Status | Last Run |
|-------|-------|--------|----------|
| unit | - | - | - |
| integration | - | - | - |
| e2e | - | - | - |

---

## Infrastructure / Deployment

| Component | Status | Blocker |
|-----------|--------|---------|
| Local dev stack | ok | - |
| Staging | pending: not deployed | Needs credentials |
| Production | pending: not deployed | Needs credentials |

---

## Pipeline State

| Field | Value |
|-------|-------|
| Current task | - |
| Phase | idle |
| Last completed | - |
| Rate limit | None |

---

## Open Tasks (strategic priority)

| ID | Task | Priority | Blocked by | Ready? |
|----|------|----------|-----------|--------|
| T-001 | Describe task here | HIGH | - | Ready |
| T-002 | Another task | MEDIUM | Waiting for X | Blocked |

---

## Update Instructions (for agents)

After completing any task:

1. Update the relevant row with the current state and date
2. Update test counts
3. Update "Pipeline State"
4. Move completed task out of "Open Tasks"
5. Add newly discovered tasks with correct priority

**Pipeline rules:**
- Blocked task -> skip, take next unblocked
- All tasks blocked -> notify the project owner
- Notify project owner only on **fully completed tasks**, not phase transitions
- On test failures: attempt 1-2 self-fixes before escalating
