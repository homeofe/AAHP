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

## Provenance (Grounded Reflection Layer)

Each table below carries a `Provenance` column recording HOW a claim was checked,
orthogonal to Status. Tokens, weakest to strongest: `model_claim`, `self_reviewed`,
`cross_model_reviewed`, `source_verified`, `tool_verified`, `test_verified`,
`runtime_observed`, `human_confirmed`. `cross_model_reviewed` maps to status
`assumed`, never `verified`; only `source_verified` / `tool_verified` /
`test_verified` / `runtime_observed` / `human_confirmed` can support `verified`
(grounded). Use `-` when provenance was not recorded. TTL and expiry stay governed
by the Trust Decay rule (README section 2.5). See GROUNDING.md for the task-type
anchor matrix and README section 2.10 for the doctrine.

---

## Scripts & Tooling

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| aahp-manifest.sh generates valid JSON | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| aahp-migrate-v2.sh delegates correctly | assumed | - | 2026-07-25 | claude-opus-5 | 7d | 2026-08-10 | Deferred full migrate.bats this session; prior test_verified evidence kept as assumed after TTL |
| lint-handoff.sh runs all 7 checks | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| verify-handoff.sh runs all 4 layers | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Content-drift gate hard-fails | assumed | - | 2026-07-25 | claude-opus-5 | 7d | 2026-08-10 | Deferred throwaway-repo re-proof this session; prior behavioral proof retained as assumed |
| Config gates + aahp doctor pass | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Escape hatch ignored at level ci | assumed | - | 2026-07-25 | claude-opus-5 | 30d | 2026-08-24 | Prior behavioral proof; TTL still valid on 30d row |
| _aahp-lib.sh functions portable | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Exercised on Windows + Git Bash this session; not re-proven on macOS/Linux host here |
| Scripts pass shellcheck | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | shellcheck not installable offline here; CI shellcheck job remains the authority |

---

## Schema & Validation

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | Stable; doctor manifest-schema structural check green |
| Generated MANIFEST.json passes schema | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Checksums match file contents | assumed | - | 2026-08-03 | grok-4.5 | 3d | 2026-08-06 | Downgraded 2026-08-23: TTL lapsed on 2026-08-06 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| aahp-config.schema.json valid JSON Schema | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | Consumed by config-driven gates; check suite green |

---

## Templates

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| All 12 templates present | verified | source_verified | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | 12 files in templates/ (incl .aiignore, GROUNDING.md) |
| Templates match v2/v3 spec | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | WORKFLOW task-selection updated to MANIFEST authority this session |
| .aiignore covers OWASP patterns | assumed | - | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-09-02 | Comprehensive but not formally audited this session; TTL refreshed only for bookkeeping |

---

## Repository

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| LICENSE matches declared license | verified | source_verified | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | Apache-2.0 in LICENSE, package.json, README |
| README.md is single source of truth | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |

---

## Update Rules (for agents)

- Change `untested` -> `verified` only after **running actual code/tests**
- Change `assumed` -> `verified` after direct confirmation
- Never downgrade `verified` without explaining why in `LOG.md`
- Expired `verified` automatically downgrades to `assumed`
- High-churn properties (scripts, checksums): 1-3 day TTL
- Stable properties (schema, templates, architecture): 30 day TTL
- Record `Provenance` for every row; only a grounded anchor supports `verified`
- Add new rows when new system properties become critical

---

*Trust degrades over time. Re-verify periodically, especially after major changes.*
