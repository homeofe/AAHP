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


**TTL review, 2026-08-23.** The defect this register showed was not the length of any
interval. Eleven rows were stamped on one day with the same interval, so they expired on
one day, and a wall of identical warnings is the state in which a new one goes unread.
That is how eight rows sat expired for over two weeks while the control printed them on
every run.

Intervals are therefore set per row against how fast the underlying fact can change, not
as a house cadence. A fact that only moves when a tracked file moves gets 30d, because
Layer 2 already fails any commit that moves such a file without moving handoff state, so
the TTL is a backstop. **Amended 2026-09-28:** a fact a machine can re-prove does not
need a calendar at all. Such a row names a check in the Check column and carries no
date: `Checksums match file contents` (built-in `manifest-integrity`), `All 12 templates
present` (the reviewed `templates-present` check) and `LICENSE matches declared license`
(built-in `license-matches`) are judged on every verify. TTLs remain for judgment rows.

`trustTtl.enforce` is on for this repository (ADR-024), so an expired `verified` row fails
CI once it is more than 14 days past expiry (`graceDays`); before that it warns.
Check-backed rows are re-proven on every run and carry no date.

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|-------|
| aahp-manifest.sh generates valid JSON | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| aahp-migrate-v2.sh delegates correctly | assumed | - | 2026-07-25 | claude-opus-5 | 7d | 2026-08-10 | - | Deferred full migrate.bats this session; prior test_verified evidence kept as assumed after TTL |
| lint-handoff.sh runs all 7 checks | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| verify-handoff.sh runs all 4 layers | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Content-drift gate hard-fails | assumed | - | 2026-07-25 | claude-opus-5 | 7d | 2026-08-10 | - | Deferred throwaway-repo re-proof this session; prior behavioral proof retained as assumed |
| Config gates + aahp doctor pass | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Escape hatch ignored at level ci | assumed | - | 2026-07-25 | claude-opus-5 | 30d | 2026-08-24 | - | Prior behavioral proof; TTL still valid on 30d row |
| _aahp-lib.sh functions portable | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Exercised on Windows + Git Bash this session; not re-proven on macOS/Linux host here |
| Scripts pass shellcheck | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | shellcheck not installable offline here; CI shellcheck job remains the authority |

---

## Schema & Validation

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | - | Stable; doctor manifest-schema structural check green |
| Generated MANIFEST.json passes schema | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| Checksums match file contents | verified | tool_verified | 2026-09-28 | claude-opus-5.5 | - | - | manifest-integrity | Re-proven on every verify: Layer 1 recomputes every indexed checksum and the built-in check reads that verdict, so no calendar interval applies |
| aahp-config.schema.json valid JSON Schema | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | - | Consumed by config-driven gates; check suite green |

---

## Templates

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|-------|
| All 12 templates present | verified | tool_verified | 2026-09-28 | claude-opus-5.5 | - | - | templates-present | Re-proven on every verify by the reviewed trustTtl.checks entry templates-present in aahp.config.json: git ls-files --error-unmatch over the 12 files aahp init copies |
| Templates match v2/v3 spec | assumed | - | 2026-08-03 | grok-4.5 | 30d | 2026-09-02 | - | WORKFLOW task-selection updated to MANIFEST authority this session |
| .aiignore covers OWASP patterns | assumed | - | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-09-02 | - | Comprehensive but not formally audited this session; TTL refreshed only for bookkeeping |

---

## Repository

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|-------|
| No secrets in source | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |
| LICENSE matches declared license | verified | tool_verified | 2026-09-28 | claude-opus-5.5 | - | - | license-matches | Re-proven on every verify by the built-in license-matches check: package.json declares Apache-2.0 and LICENSE carries the Apache License Version 2.0 text |
| Supply-chain scanner workflow passes | verified | runtime_observed | 2026-09-28 | claude-opus-5.5 | 30d | 2026-10-28 | - | GitHub Actions job `Supply chain guard` passed on the push to main at f9b12ca (run 36378741428) with the v6.3.1 action pinned to `013febcb8447107bcf9d82e400d5b492d44bb10f` and `refresh-catalog: true`: historical catalog consulted (86,885 indicators beyond the bundled set), risk 15/100, three medium findings: `GHA_OIDC_WRITE_PERM` and `WORKFLOW_SECRET_TO_UPLOAD_PATH` on the release workflow (known), and `INTERNAL_PRIVATE_IP` on a JSON Schema section number in a comment (a scanner false positive; the comment is reworded in the full-ASCII change). 103 of 138 files scanned. |
| README.md is single source of truth | assumed | - | 2026-08-03 | grok-4.5 | 7d | 2026-08-10 | - | Downgraded 2026-08-23: TTL lapsed on 2026-08-10 and nothing re-ran it. `assumed` is what this register's own table calls an unverified claim; a fresh date would have been a verdict nobody produced |

---

## Update Rules (for agents)

- Change `untested` -> `verified` only after **running actual code/tests**
- Change `assumed` -> `verified` after direct confirmation
- Never downgrade `verified` without explaining why in `LOG.md`
- An expired `verified` row counts as `assumed` when you read it, but nothing rewrites it:
  `aahp verify` Layer 4 reports it. Re-verify it (new Last Verified and Expires) or
  downgrade it yourself
- A row a machine can re-prove names a check in the Check column (`license-matches`,
  `manifest-integrity`, or an id from `trustTtl.checks` in aahp.config.json) and is
  judged on every verify instead of by its date
- A property a machine can re-prove gets a check, not a TTL
- A judgment row gets a TTL set by how fast its fact changes: 7 days for something
  that moves with most changes, 30 days for schema, templates and architecture
- Record `Provenance` for every row; only a grounded anchor supports `verified`
- Add new rows when new system properties become critical

---

*Trust degrades over time. Re-verify periodically, especially after major changes.*
