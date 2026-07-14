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
| aahp-manifest.sh generates valid JSON | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | Re-verified via manifest.bats 18/18; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| aahp-migrate-v2.sh delegates correctly | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | Re-verified: delegates to aahp-manifest.sh; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| lint-handoff.sh runs all 6 checks | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | Re-verified via lint.bats 18/18; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| verify-handoff.sh runs all 4 layers | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | verify.bats 12/12 plus end-to-end pre-commit block; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| Content-drift gate hard-fails | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | Code-without-handoff commit physically blocked; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| Escape hatch ignored at level ci | verified | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | AAHP_SKIP_VERIFY=1 honoured locally, not at ci |
| _aahp-lib.sh functions portable | assumed | 2026-06-20 | Claude Opus 4.8 | 3d | 2026-06-23 | Only tested on Git Bash (Windows) |
| Scripts pass shellcheck | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | bash -n clean; full shellcheck runs in CI; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |

---

## Schema & Validation

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | Stable, rarely changes |
| Generated MANIFEST.json passes schema | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | No ajv on this machine; ajv runs in CI; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| Checksums match file contents | verified | 2026-07-14 | claude-opus-4-8 | 3d | 2026-07-17 | Re-verified via lint-handoff.sh plus verify Layer 1; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |

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
| No secrets in source | assumed | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | lint-handoff.sh checks this; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |
| LICENSE matches declared license | verified | 2026-06-20 | Claude Opus 4.8 | 30d | 2026-07-20 | Resolved: Apache-2.0 across LICENSE, package.json, and README (Emre decided 2026-06-20) |
| README.md is single source of truth | verified | 2026-07-14 | claude-opus-4-8 | 7d | 2026-07-21 | Re-verified: 645-line README present; re-verified 2026-07-14 (CI green: ci.yml + aahp-* workflows) |

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

---

## Provenance (Draft v0.1, proposed)

The Grounded Reflection Layer adds an orthogonal *provenance* field recording HOW a
claim was checked, separate from the Status above. Provenance tokens, weakest to
strongest: `model_claim`, `self_reviewed`, `cross_model_reviewed`, `source_verified`,
`tool_verified`, `test_verified`, `runtime_observed`, `human_confirmed`.
`cross_model_reviewed` maps to status `assumed`, never `verified`; only
`source_verified` / `tool_verified` / `test_verified` / `runtime_observed` /
`human_confirmed` can support `verified` (grounded). To record it in this register, add
a `Provenance` column to the tables above and use `-` when it is unknown. TTL and expiry
stay governed by the Trust Decay rule (README section 2.5). See GROUNDING.md for the anchor
matrix and README section 2.10 for the doctrine.
