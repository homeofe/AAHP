# Grounding Register

> Defines which task types require which external anchors before a claim may be
> recorded as grounded (status `verified`). Part of the Grounded Reflection Layer
> (README section 2.10). Complements TRUST.md.
> Draft v0.1 - proposed.

This register EXTENDS existing AAHP machinery; it does not fork or replace it. It
reuses the confidence register in TRUST.md, the Trust Decay rule (README section
2.5), Agent Identity and Provenance (README section 2.4), and the Verify Gate
(README section 2.8). Where those already define a mechanism, this file points to
them instead of restating it.

Placement note: `aahp init` scaffolds this file into `.ai/handoff/GROUNDING.md`, so
it is part of the MANIFEST checksum set and is covered by the verify gate like any
other handoff file. Existing projects can add it in place with
`aahp migrate-grounding`.

---

## 1. The Two Axes

A claim is described on two orthogonal axes. Keep them in separate fields.

### Axis A - Status (grounding confidence). Reused from TRUST.md, not new.

The only status vocabulary is `verified`, `assumed`, `untested` - the same three
levels the TRUST.md Confidence Levels table already defines. In STATUS.md these
render inline as `(Verified)`, `(Assumed)`, `(Unknown)`; treat register `untested`
and STATUS.md `(Unknown)` as the same level.

Grounding shorthand names points on this SAME axis; it does not add levels:

- `grounded` is status `verified` (at least one external anchor confirms it)
- `partially_grounded` is status `assumed` (cross-model reviewed or weak evidence; no external anchor yet)
- `ungrounded` is status `untested` (model-only; nothing external has checked it)

Two lifecycle markers are applied by the Trust Decay rule (README section 2.5); they
are orthogonal to the three levels and are not provenance values: `expired` (TTL
lapsed; the row counts as `assumed` when read, but nothing rewrites it: `aahp verify`
Layer 4 reports it and an agent re-verifies or downgrades it) and `rejected` (claim
withdrawn; never reuse).

### Axis B - Provenance (how a claim was produced or checked). New, orthogonal field.

Provenance is recorded as a SEPARATE field (`provenance:` or a TRUST.md column),
never mixed into the status. The only provenance vocabulary, weakest to strongest:

`model_claim` < `self_reviewed` < `cross_model_reviewed` < `source_verified` <
`tool_verified` < `test_verified` < `runtime_observed` < `human_confirmed`

- `model_claim` means a model produced it and nothing has checked it. It
  corresponds to status `untested`.
- `self_reviewed` is never final verification for high-impact work.
- `cross_model_reviewed` is provenance only; it maps to status `assumed`, not
  `verified` (consensus is not grounding).
- Only `source_verified`, `tool_verified`, `test_verified`, `runtime_observed`,
  or `human_confirmed` can support status `verified`.

### Axis crosswalk

| Grounding term | Status (register) | STATUS.md tag | Typical provenance |
|---|---|---|---|
| grounded | verified | (Verified) | test_verified / tool_verified / source_verified / runtime_observed / human_confirmed |
| partially_grounded | assumed | (Assumed) | cross_model_reviewed / self_reviewed |
| ungrounded | untested | (Unknown) | model_claim |

---

## 2. Grounding Anchors

A claim may reach status `verified` (grounded) only with at least one external
anchor - something outside the model's own assertion:

- passing tests
- passing build
- passing type-check
- passing lint or static analysis
- schema validation
- a verified external source
- runtime observation
- a deterministic calculation
- human domain-owner confirmation

With no anchor, a claim stays at status `untested` (provenance `model_claim`) or,
if a different provider reviewed it, at status `assumed` (provenance
`cross_model_reviewed`). Model output on its own is not verification.

---

## 3. Task-Type Grounding Matrix

Which anchor a task needs before its central claim can be recorded as grounded
(status `verified`). "Min provenance for verified" is the weakest provenance on
Axis B that can carry that task to `verified`; anything weaker keeps it at
`assumed` or `untested`.

| Task type | Minimum external anchor | Min provenance for verified | Stays below verified if |
|---|---|---|---|
| Code implementation | Passing tests + build + type-check/lint on the change | test_verified | Only self-reviewed, or no tests were actually run |
| Documentation | Doc checked against the source or config it describes | source_verified | Describes code that was never read; model_claim only |
| Architecture decisions | ADR recording alternatives considered, plus human sign-off | human_confirmed | No alternatives weighed; single-model reasoning only |
| Security-sensitive changes | Security scanner or static-analysis output, cross-provider review, human sign-off | human_confirmed | Same model generated and approved it; model reasoning only |
| Compliance or legal claims | Verified external source and human domain-owner confirmation | human_confirmed | No human_confirmed; source not cited or not current |
| External factual research | Two or more independent verified external sources | source_verified | No current source; model_claim only |
| Strategic/business analysis | Human domain-owner confirmation; assumptions labelled | human_confirmed | Rests on model reasoning alone (holds at assumed until a human confirms) |
| Agent-governance changes | The verify gate passes, cross-model review, human sign-off | human_confirmed | Gate not run; change self-approved by its author |

Notes:

- Cross-model review (see the Reviewer role in WORKFLOW.md Phase 4) raises
  provenance to `cross_model_reviewed`, which maps to status `assumed` - it never
  reaches `verified` on its own.
- For agent-governance changes the deterministic gate is the AAHP verify gate
  (README section 2.8); grounding reasoning sits on top of it and does not restate
  its checks.

---

## 4. Confidence Bands

Confidence is advisory. The load-bearing fields are `status`, `provenance`, and
`evidence`; a number never substitutes for an anchor. When confidence is recorded,
it must carry a `confidence_source`.

| Confidence | Typical status | Typical provenance |
|---|---|---|
| 0.20 - 0.40 | untested | model_claim (model output only, no anchor) |
| 0.40 - 0.60 | assumed | self_reviewed (plausible, limited evidence) |
| 0.60 - 0.75 | assumed | cross_model_reviewed (no deterministic anchor yet) |
| 0.75 - 0.90 | verified | source_verified / tool_verified / test_verified |
| 0.90 - 0.98 | verified | multiple independent anchors |
| 0.99+ | verified | formal proofs or deterministic calculations only |

A confidence above 0.75 that lacks a matching anchor is a provenance gap: lower the
number or add the anchor. A passing test suite does not qualify for the `0.99+`
band: it shows the absence of caught failures, not proof of correctness. Reserve
`0.99+` for formal proofs or deterministic calculations only. Runtime observation (the
0.90-0.98 band) does not compound toward `0.99+`; that top band is for mathematical or
logical proof.

---

## 5. Required TRUST Fields

A trust record that participates in the Grounded Reflection Layer should carry these
fields. They are a convention: they extend the existing TRUST.md register rather than
replacing its table, and no AAHP gate reads them. What code reads is narrower: verify
Layer 4 reads the Status, Expires and Check columns, and `aahp doctor` checks only that
TRUST.md has a Provenance column (README sections 2.5 and 2.10).

The ten recommended fields (the list README section 2.10 names), with the TRUST.md
column each one maps onto:

- `id` - stable identifier; never reused (the Property cell)
- `claim` - the assertion in one sentence (the Property cell)
- `status` - `verified` / `assumed` / `untested`, Axis A (Status)
- `provenance` - strongest achieved value on Axis B (Provenance)
- `generated_by` - agent or model that produced the claim (Agent)
- `verified_by` - the anchor or agent that verified it, or null (Agent, or Notes)
- `evidence` - pointer to the anchor: test run, source, scan, sign-off (Notes, or a
  check named in the Check column)
- `ttl` - time-to-live (TTL)
- `expires` - expiry date (Expires)
- `owner` - accountable agent or human (Notes)

Five optional fields for high-impact work, recorded in Notes or in a separate record:

- `reviewed_by` - reviewing agent or model (a different provider for high-impact work)
- `confidence` - numeric estimate (see Section 4)
- `confidence_source` - required whenever `confidence` is present
- `remaining_uncertainty` - what is still open
- `next_verification_step` - what the next agent should check first

---

## 6. Provenance Invalidation (downgrade)

Provenance can move down, not only up. If the external anchor that supported a
`verified` claim is removed, retracted, deprecated, or found to be incorrect, the
claim reverts: to `assumed` if an independent cross-provider review still stands
(provenance `cross_model_reviewed`), otherwise to `untested` (provenance
`model_claim`). Update the affected row in TRUST.md when this happens. This is
distinct from TTL expiry (README section 2.5 Trust Decay): expiry is about age;
invalidation is about the anchor no longer being valid.

---

## 7. TTL and Expiry

This file defines no TTL tables of its own. Time-to-live and expiry are governed by
a single authority: the Trust Decay rule (README section 2.5) sets the day tiers
(high-churn build/test properties get short TTLs; stable properties such as
architecture and conventions get long TTLs) and the rule that an expired `verified`
claim counts as `assumed` until it is re-verified. Nothing downgrades the row
automatically: the verify gate (README section 2.8, Layer 4) reports it, and the
agent re-verifies or downgrades it. The per-row TTL and Expires columns in TRUST.md
carry the actual values, and an optional Check column lets a row be re-proven by a
reviewed check on every run instead of by its date. Layer 4 is advisory by default;
it blocks only in a repository that sets `trustTtl.enforce`, and then only for a
failing check or a row more than `trustTtl.graceDays` (default 14) past its expiry.

---

## 8. Verdicts

Audit and review decisions use the reviewer vocabulary only: `SHIP`,
`NEEDS_CHANGES`, `BLOCK`. This register does not define its own outcome tokens.

---

## Cross-References

- TRUST.md - the confidence register (verified/assumed/untested) and per-row TTL + Expires columns
- README section 2.4 - Agent Identity and Provenance (a convention; ADR-022 withdrew its audit-trail claim)
- README section 2.5 - Trust Decay (sole TTL authority)
- README section 2.8 - The Verify Gate
- README section 2.10 - Grounded Reflection Layer (the doctrine)
- WORKFLOW.md Phase 4 - cross-model review; optional Phase 4.5 grounding audit

---

*Grounding degrades over time. Re-verify against a live anchor, especially after major changes.*
