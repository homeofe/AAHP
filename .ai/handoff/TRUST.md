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
| aahp-manifest.sh generates valid JSON | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | Re-verified via manifest.bats |
| aahp-migrate-v2.sh delegates correctly | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | Re-verified: delegates to aahp-manifest.sh |
| lint-handoff.sh runs all 6 checks | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | Re-verified via lint.bats 31/31 |
| verify-handoff.sh runs all 4 layers | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | verify.bats 13/13 incl Layer 3 warn on orphaned pointer |
| Content-drift gate hard-fails | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | Code-without-handoff commit physically blocked |
| Config gates + aahp doctor pass | verified | test_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | gates.bats 20/20 + doctor.bats 10/10; doctor green on AAHP |
| Escape hatch ignored at level ci | verified | test_verified | 2026-06-20 | claude-opus-4-8 | 30d | 2026-07-20 | AAHP_SKIP_VERIFY=1 honoured locally, not at ci |
| _aahp-lib.sh functions portable | assumed | - | 2026-06-20 | claude-opus-4-8 | 3d | 2026-06-23 | Only tested on Git Bash (Windows) |
| Scripts pass shellcheck | assumed | - | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | bash -n clean locally; full shellcheck runs in CI (not installable offline here) |

---

## Schema & Validation

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | - | 2026-06-20 | claude-opus-4-8 | 30d | 2026-08-17 | Stable, rarely changes |
| Generated MANIFEST.json passes schema | assumed | - | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | No ajv on this machine; ajv runs in CI |
| Checksums match file contents | verified | tool_verified | 2026-07-18 | claude-opus-4-8 | 3d | 2026-07-21 | Re-verified via lint-handoff.sh plus verify Layer 1 |
| aahp-config.schema.json valid JSON Schema | assumed | - | 2026-07-18 | claude-opus-4-8 | 30d | 2026-08-17 | New in 3.6.0; consumed by the config-driven gates |

---

## Templates

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| All 12 templates present | verified | source_verified | 2026-07-18 | claude-opus-4-8 | 30d | 2026-08-17 | 12 files in templates/ (incl .aiignore, GROUNDING.md) |
| Templates match v2 spec | assumed | - | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Reviewed but not formally validated |
| .aiignore covers OWASP patterns | assumed | - | 2026-02-26 | Claude Opus 4.6 | 30d | 2026-03-28 | Comprehensive but not audited |

---

## Repository

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | - | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | lint-handoff.sh checks this |
| LICENSE matches declared license | verified | source_verified | 2026-06-20 | claude-opus-4-8 | 30d | 2026-07-20 | Resolved: Apache-2.0 across LICENSE, package.json, and README |
| README.md is single source of truth | verified | source_verified | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | Re-verified: README present, Section 2.11 + release ceremony added |

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
