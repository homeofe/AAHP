# [PROJECT]: Trust Register

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

## Provenance (Draft v0.1, proposed)

The Grounded Reflection Layer adds an orthogonal *provenance* field recording HOW a
claim was checked, separate from the Status columns below. Provenance tokens, weakest
to strongest: `model_claim`, `self_reviewed`, `cross_model_reviewed`,
`source_verified`, `tool_verified`, `test_verified`, `runtime_observed`,
`human_confirmed`. `cross_model_reviewed` maps to status `assumed`, never `verified`;
only `source_verified` / `tool_verified` / `test_verified` / `runtime_observed` /
`human_confirmed` can support `verified` (grounded). Record it in the Provenance column
of the tables below, using `-` when unknown. TTL and expiry stay governed by the Trust
Decay rule (README section 2.5). See GROUNDING.md for the task-type anchor matrix and
README section 2.10 for the doctrine.

---

## Build System

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| `build` passes | untested | - | - | - | - | - | |
| `test` passes | untested | - | - | - | - | - | |
| `lint` passes | untested | - | - | - | - | - | |
| `type-check` passes | untested | - | - | - | - | - | |

---

## Infrastructure

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| Local dev stack boots | untested | - | - | - | - | - | |
| All health endpoints respond | untested | - | - | - | - | - | |
| Database connection works | untested | - | - | - | - | - | |
| Auth flow completes | untested | - | - | - | - | - | |

---

## Integrations

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| External API A reachable | untested | - | - | - | - | - | |
| Webhook delivery confirmed | untested | - | - | - | - | - | |

---

## Security

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| No secrets in source | assumed | - | - | - | - | - | Pre-commit hooks configured |
| Auth tokens expire correctly | untested | - | - | - | - | - | |
| PII not logged | untested | - | - | - | - | - | |

---

## Update Rules (for agents)

- Change `untested` → `verified` only after **running actual code/tests**
- Change `assumed` → `verified` after direct confirmation
- Never downgrade `verified` without explaining why in `LOG.md`
- Add new rows when new system properties become critical

---

*Trust degrades over time. Re-verify periodically, especially after major refactors.*
