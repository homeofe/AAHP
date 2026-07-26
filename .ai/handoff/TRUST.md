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
| aahp-manifest.sh generates valid JSON | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: manifest.bats 19/19 |
| aahp-migrate-v2.sh delegates correctly | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: migrate.bats 12/12; delegation to aahp-manifest.sh confirmed at source |
| lint-handoff.sh runs all 6 checks | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: lint.bats 31 ok / 0 fail (1 known skip); all 6 numbered checks observed on this repo |
| verify-handoff.sh runs all 4 layers | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: verify.bats 13/13; all 4 layers observed in a prepush run |
| Content-drift gate hard-fails | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: throwaway repo, code-only commit gave Layer 2 FAIL and exit 1 |
| Config gates + aahp doctor pass | verified | test_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: gates.bats 22/22 + doctor.bats 15/15; npm run check 8/8 green; doctor 6 gates, no failures |
| Escape hatch ignored at level ci | verified | test_verified | 2026-07-25 | claude-opus-5 | 30d | 2026-08-24 | Re-verified 2026-07-25: on a drifted throwaway repo AAHP_SKIP_VERIFY=1 exits 0 at prepush and is ignored at level ci (exit 1) |
| _aahp-lib.sh functions portable | assumed | - | 2026-06-20 | claude-opus-4-8 | 3d | 2026-06-23 | Only tested on Git Bash (Windows) |
| Scripts pass shellcheck | assumed | - | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | bash -n clean locally; full shellcheck runs in CI (not installable offline here) |

---

## Schema & Validation

| Property | Status | Provenance | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|------------|---------------|-------|-----|---------|-------|
| aahp-manifest.schema.json valid JSON Schema | assumed | - | 2026-06-20 | claude-opus-4-8 | 30d | 2026-08-17 | Stable, rarely changes |
| Generated MANIFEST.json passes schema | assumed | - | 2026-07-18 | claude-opus-4-8 | 7d | 2026-07-25 | No ajv on this machine; ajv runs in CI |
| Checksums match file contents | verified | tool_verified | 2026-07-25 | claude-opus-5 | 3d | 2026-07-28 | Re-verified 2026-07-25: 11/11 indexed files recomputed independently (0 mismatches), lint-handoff.sh plus verify Layer 1 green, and a deliberately tampered copy correctly fails Layer 1 |
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
| LICENSE matches declared license | verified | source_verified | 2026-07-25 | claude-opus-5 | 30d | 2026-08-24 | Re-verified 2026-07-25: Apache-2.0 in the LICENSE body, the package.json license field, and both the README badge and License section; no competing license string anywhere in tracked sources |
| README.md is single source of truth | verified | source_verified | 2026-07-25 | claude-opus-5 | 7d | 2026-08-01 | Re-verified 2026-07-25: designation read at source (CONSTITUTION invariant 8, CLAUDE.md); machine-checkable subset green (doc-links 17/17 resolve, schema-doc-sync 2/2 groups consistent). Full README-to-code agreement is guarded only for the pinned enums and links, not exhaustively audited |

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
