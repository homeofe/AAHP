# [PROJECT]: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## 1. [Task Title]

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

**Definition of done:**
- [ ] Tests pass
- [ ] Type-check passes
- [ ] `STATUS.md` updated

---

## 2. [Task Title] ⏳ Blocked

**Goal:** ...

**Blocked by:** Waiting for [credential / decision / external dependency]

**What to do once unblocked:**
1. ...

---

## Recently Completed

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
