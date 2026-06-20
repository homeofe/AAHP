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
| aahp-manifest.sh generates valid JSON | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | Re-verified via manifest.bats 18/18 |
| aahp-migrate-v2.sh delegates correctly | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | Re-verified: delegates to aahp-manifest.sh |
| lint-handoff.sh runs all 6 checks | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | Re-verified via lint.bats 18/18 |
| verify-handoff.sh runs all 4 layers | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | verify.bats 12/12 plus end-to-end pre-commit block |
| Content-drift gate hard-fails | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | Code-without-handoff commit physically blocked |
| Escape hatch ignored at level ci | verified | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | AAHP_SKIP_VERIFY=1 honoured locally, not at ci |
| _aahp-lib.sh functions portable | assumed | 2026-06-20 | Claude Opus 4.8 | 3d | 2026-06-23 | Only tested on Git Bash (Windows) |
| Scripts pass shellcheck | assumed | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | bash -n clean; full shellcheck runs in CI |

---

## Schema & Validation

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | Stable, rarely changes |
| Generated MANIFEST.json passes schema | assumed | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | No ajv on this machine; ajv runs in CI |
| Checksums match file contents | verified | 2026-06-20 | Claude Opus 4.8 | 3d | 2026-06-23 | Re-verified via lint-handoff.sh plus verify Layer 1 |

---

## Templates

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| All 10 templates present | verified | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | Re-verified: 10 files in templates/ (incl .aiignore) |
| Templates match v2 spec | assumed | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Reviewed but not formally validated |
| .aiignore covers OWASP patterns | assumed | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Comprehensive but not audited |

---

## Repository

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | 2026-02-26 | Claude Opus 4.6 | 7d | 2026-03-05 | lint-handoff.sh checks this |
| LICENSE matches declared license | verified | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | Resolved: Apache-2.0 across LICENSE, package.json, and README (Emre decided 2026-06-20) |
| README.md is single source of truth | verified | 2026-06-20 | Claude Opus 4.8 | 7d | 2026-06-27 | Re-verified: 645-line README present |

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
