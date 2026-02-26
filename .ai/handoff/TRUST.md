# AAHP: Trust Register

> Tracks verification status of critical system properties.
> In multi-agent pipelines, hallucinations and drift are real risks.
> Every claim here has a confidence level tied to how it was verified.

---

## Confidence Levels

| Level | Meaning |
|-------|---------|
| **verified** | An agent executed code, ran tests, or observed output to confirm this |
| **assumed** | Derived from docs, config files, or chat, not directly tested |
| **untested** | Status unknown; needs verification |

---

## Scripts & Tooling

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| aahp-manifest.sh generates valid JSON | verified | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | Tested against temp handoff dir |
| aahp-migrate-v2.sh delegates correctly | verified | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | Tested end-to-end |
| lint-handoff.sh runs all 6 checks | verified | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | Check 4 needs Python |
| _aahp-lib.sh functions portable | assumed | 2026-02-26 | Claude Opus 4.6 | 3d | 2026-03-01 | Only tested on Git Bash (Windows) |
| Scripts pass shellcheck | untested | - | - | 3d | - | Not yet run |

---

## Schema & Validation

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Stable, rarely changes |
| Generated MANIFEST.json passes schema | assumed | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | No ajv available on this machine |
| Checksums match file contents | verified | 2026-02-26 | Claude Opus 4.6 | 3d | 2026-03-01 | Verified via lint script |

---

## Templates

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| All 10 templates present | verified | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Stable |
| Templates match v2 spec | assumed | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Reviewed but not formally validated |
| .aiignore covers OWASP patterns | assumed | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Comprehensive but not audited |

---

## Repository

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | lint-handoff.sh checks this |
| CC BY 4.0 LICENSE correct | verified | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Changed from MIT |
| README.md is single source of truth | verified | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | AAHP-v2-PROPOSAL.md merged |

---

## Update Rules (for agents)

- Change `untested` → `verified` only after **running actual code/tests**
- Change `assumed` → `verified` after direct confirmation
- Never downgrade `verified` without explaining why in `LOG.md`
- Expired `verified` automatically downgrades to `assumed`
- High-churn properties (scripts, checksums): 1-3 day TTL
- Stable properties (schema, templates, architecture): 30 day TTL
- Add new rows when new system properties become critical

---

*Trust degrades over time. Re-verify periodically, especially after major changes.*
