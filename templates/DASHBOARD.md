# [PROJECT] — Build Dashboard

> Single source of truth for build health, test coverage, and pipeline state.
> Updated by agents at the end of every completed task.

---

## 🏗️ Services / Components

| Name | Version | Build | Tests | Status | Notes |
|------|---------|-------|-------|--------|-------|
| service-a | — | ✅ | — | ✅ | |
| service-b | — | ✅ | 42/42 ✅ | ✅ | |
| service-c | — | ❌ | — | 🔴 Broken | See LOG.md |

**Legend:** ✅ passing · ❌ failing · 🔵 stub/mock · ⏳ pending · 🔴 blocked

---

## 🧪 Test Coverage

| Suite | Tests | Status | Last Run |
|-------|-------|--------|----------|
| unit | — | — | — |
| integration | — | — | — |
| e2e | — | — | — |

---

## 🚀 Infrastructure / Deployment

| Component | Status | Blocker |
|-----------|--------|---------|
| Local dev stack | ✅ | — |
| Staging | ⏳ Not deployed | Needs credentials |
| Production | ⏳ Not deployed | Needs credentials |

---

## 🤖 Pipeline State

| Field | Value |
|-------|-------|
| Current task | — |
| Phase | idle |
| Last completed | — |
| Rate limit | None |

---

## 📋 Open Tasks (strategic priority)

| # | Task | Priority | Blocked by | Ready? |
|---|------|----------|-----------|--------|
| 1 | Describe task here | 🔴 HIGH | — | ✅ Ready |
| 2 | Another task | 🟠 MEDIUM | Waiting for X | 🔴 Blocked |

---

## 🔄 Update Instructions (for agents)

After completing any task:

1. Update the relevant row to ✅ with current date
2. Update test counts
3. Update "Pipeline State"
4. Move completed task out of "Open Tasks"
5. Add newly discovered tasks with correct priority

**Pipeline rules:**
- Blocked task → skip, take next unblocked
- All tasks blocked → notify the project owner
- Notify project owner only on **fully completed tasks**, not phase transitions
- On test failures: attempt 1–2 self-fixes before escalating
