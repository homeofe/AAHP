# [PROJECT]: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".
> Every task carries one **Acceptance criteria** section written as task boxes:
> `- [ ]` while unresolved, `- [x]` only on evidence. Before a task becomes `done`,
> every criterion is checked, waived `(waived: rationale)`, or moved
> `(follow-up: T-042 or #123)`. See README Section 8.7.

Current version: **v[VERSION]**

---

## T-001: [Task Title]

**Goal:** One sentence describing the desired outcome.

**Context:**
- What is the current state?
- What has already been tried or decided?

**What to do:**
1. Step one, be specific (file path, command, expected output)
2. Step two
3. Step three

**Files:**
- `path/to/relevant/file.ts`: what it does
- `path/to/config.yml`: what it configures

**Acceptance criteria:**
- [ ] Tests pass
- [ ] Type-check passes
- [ ] `STATUS.md` updated

---

## T-002: [Task Title] ⏳ Blocked

**Goal:** ...

**Blocked by:** Waiting for [credential / decision / external dependency]

**What to do once unblocked:**
1. ...

---

## Recently Completed

> Resolution records the closure evidence: the commit, PR, test run, or live
> verification that satisfied the criteria, plus any waiver or follow-up reference.

| Item | Resolution |
|------|-----------|
| Example task | Implemented in feat/example, 42/42 tests ✅ |

---

## Reference: Key File Locations

| What | Where |
|------|-------|
| Main config | `config/app.yml` |
| Docker Compose | `docker-compose.yml` |
| Environment template | `.env.example` |
