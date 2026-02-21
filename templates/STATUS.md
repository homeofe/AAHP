# [PROJECT] — Current State of the Nation

> Last updated: [DATE] by [Agent/Human]
> Commit: [hash]
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality — not history. History lives in LOG.md.

---

## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `build` | ✅ / ❌ | |
| `test` | ✅ / ❌ | X/X passing |
| `lint` | ✅ / ❌ | |
| `type-check` | ✅ / ❌ | |

---

## Infrastructure

| Component | Location | State |
|-----------|----------|-------|
| Local dev stack | `docker-compose.yml` | ✅ Running / ⏳ Not started |
| Staging | — | ⏳ Not deployed |
| Production | — | ⏳ Not deployed |

---

## Services / Components

| Service | Port | State | Notes |
|---------|------|-------|-------|
| service-a | 3000 | ✅ Implemented | |
| service-b | 8080 | 🔵 Stubbed | Mock responses only |
| service-c | — | ❌ Not started | |

---

## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| Feature X | HIGH | Not yet implemented |
| Integration Y | MEDIUM | Exists but untested |
| Deployment | LOW | Needs cloud credentials |

---

## Recently Resolved

| Item | Resolution |
|------|-----------|
| Bug Z | Fixed in commit abc123 |

---

## Trust Levels

- **(Verified)** — confirmed by running code/tests
- **(Assumed)** — derived from docs/config, not directly tested
- **(Unknown)** — needs verification
