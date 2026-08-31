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


**TTL review, 2026-08-23.** Intervals in use: 3d on 1 row, 7d on 11, 30d on 7. The defect this
register showed was not the length of any interval. Eleven rows were stamped on one day
with the same interval, so they expired on one day, and a wall of identical warnings is
the state in which a new one goes unread. That is how eight rows sat expired for over two
weeks while the control printed them on every run.

Intervals are therefore set per row against how fast the underlying fact can change, not
as a house cadence. A fact that only moves when a tracked file moves gets 30d, because
Layer 2 already fails any commit that moves such a file without moving handoff state, so
the TTL is a backstop. A fact a gate recomputes on every run does not need a calendar at
all: `Checksums match file contents` carries 3d and Layer 1 proves it continuously, so the
short interval reads as a stronger claim than it is and the row stays `assumed`.

`trustTtl.enforce` is on for this repository (ADR-024), so an expired `verified` row now
fails CI rather than printing into the wall.
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
| Checksums match file contents | assumed | - | 2026-08-03 | grok-4.5 | 3d | 2026-08-06 | Downgraded 2026-08-23: TTL lapsed and nothing re-ran it. Left `assumed` deliberately after the 2026-08-23 TTL review: Layer 1 recomputes this on EVERY run, so a calendar interval records nothing the gate is not already proving continuously, and a short interval here reads as a stronger claim than it is |
| aahp-config.schema.json valid JSON Schema | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | Consumed by config-driven gates; check suite green |

---

## Templates

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| All 12 templates present | verified | source_verified | 2026-08-23 | cli-tool | 30d | 2026-09-22 | Re-verified 2026-08-23: templates/ holds exactly 12 entries (.aiignore, CONVENTIONS.md, DASHBOARD.md, GROUNDING.md, LOG-ARCHIVE.md, LOG.md, MANIFEST.json, NEXT_ACTIONS.md, STATUS.md, TRUST.md, WORKFLOW.md, pii-allowlist.json). 30d because this only moves when a tracked file moves, and Layer 2 already fails a commit that moves one without handoff state |
| Templates match v2/v3 spec | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | WORKFLOW task-selection updated to MANIFEST authority this session |
| .aiignore covers OWASP patterns | assumed | - | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-09-02 | Comprehensive but not formally audited this session; TTL refreshed only for bookkeeping |

---

## Repository

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| LICENSE matches declared license | verified | source_verified | 2026-08-23 | cli-tool | 30d | 2026-09-22 | Re-verified 2026-08-23: package.json declares `"license": "Apache-2.0"` and LICENSE opens `Apache License / Version 2.0, January 2004`. 30d for the same reason as the row above |
| Supply-chain scanner workflow passes | verified | runtime_observed | 2026-08-31 | codex | 30d | 2026-09-30 | GitHub Actions job `Supply chain guard` passed on PR #110 at run 33385292682 with the v6.0.8 action pinned to commit `2ba749d08e19b4d5c75c71467233987748f8e8c7`; the same release scanned the isolated Linux tree with 0 findings and risk 0. |
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
