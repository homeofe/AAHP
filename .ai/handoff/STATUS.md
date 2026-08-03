# AAHP: Current State of the Nation

> Last updated: 2026-08-03 by grok-4.5
> Commit: (pending this branch)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP **v3.9.1** (npm `@elvatis_com/aahp`). File-based AI-to-AI handoff protocol plus CLI
for init, lint, migrate, verify, check, doctor, status, archive, criteria, and
manifest regeneration.

Shipped surface (high level):
- **Integrity:** `aahp verify` (4 layers), `aahp lint` (7 checks including conflict-marker
  refuse), MANIFEST checksums, LOG archive integrity index
- **Governance:** config-driven gates via `aahp check`, `aahp doctor` conformance record,
  CONSTITUTION.md, portable `init --gates`
- **Lifecycle:** acceptance-criteria advisory report (`aahp criteria`), Grounded Reflection
  Layer (TRUST provenance + GROUNDING.md), optional Phase 4.5 in WORKFLOW
- **Ops:** `aahp status`, `aahp archive`, OIDC npm publish on semver tags, badge workflows

This session (2026-08-03) closes handoff hygiene drift found by a flawed external
"cross-check": STATUS rewrite, MANIFEST summaries, WORKFLOW alignment, TRUST re-verify,
NEXT_ACTIONS dedupe, and doctor `handoff-set` alignment with Layer 1 on partial indexes.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| npm version | OK | 3.9.1 (doctor partial-index alignment + handoff hygiene) |
| `aahp doctor` | OK | handoff-set now fails on partial index (aligned with verify Layer 1 / lint) |
| `aahp verify --level prepush` | OK | re-run after handoff rewrite this session |
| `doctor.bats` | OK | 16 tests (added partial-index regression); run locally via Git Bash |
| `lint.bats` | OK | 39 tests incl conflict-marker coverage (CI green on #55) |
| `verify.bats` | OK | 22 tests (CI authoritative for full suite) |
| `gates.bats` | OK | 22 tests |
| `acceptance-criteria.bats` | OK | 66 tests |
| `cli.bats` | PARTIAL local | known Windows-only flakes; green on Linux CI |
| `npm run check` | OK | 8 config-driven gates |
| shellcheck | CI | not installed offline on this Windows host; CI covers shipped scripts |
| Full bats suite | CI | do not run full suite on this Windows host (~hours); push and let GHA decide |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| CLI | `bin/aahp.js` | Complete | init, manifest, lint, migrate, verify, check, doctor, status, archive, criteria, migrate-grounding |
| Shared lib | `scripts/_aahp-lib.sh` | Complete | checksum, trust TTL, auto_summary (scans past header chrome) |
| Verify gate | `scripts/verify-handoff.sh` | Complete | 4 layers; Layer 1 catches missing + partial index |
| Lint | `scripts/lint-handoff.sh` | Complete | 7 checks; check 7 = conflict markers |
| Conflict markers | `scripts/check-conflict-markers.mjs` | Complete | CRLF-safe; bash/grep fallback |
| Doctor | `bin/aahp.js` cmdDoctor | Complete | handoff-set matches Layer 1 partial-index rule |
| Release gates | `scripts/check-*.mjs` | Complete | version-sync, changelog, claims, forbidden-patterns, schema-doc-sync, doc-links |
| Dashboard check | `scripts/aahp-dashboard.mjs` | Complete | handoff freshness |
| Manifest gen | `scripts/aahp-manifest.sh` | Complete | preserves tasks / next_task_id / cross_repo_ref |
| Archive | archive command | Complete | keep 10 newest LOG entries |
| Schemas | `schema/` | Complete | manifest, config, pii-allowlist |
| Templates | `templates/` | Complete | 12 files incl GROUNDING.md |
| CI | `.github/workflows/` | Complete | ci, verify, lint, manifest, archive, pii, CodeQL; Actions active |
| Hooks | `scripts/hooks/` + install-hooks.sh | Complete | pre-commit / pre-push |
| Rollout | `scripts/ROLLOUT.md` | Complete | project-agnostic wave playbook |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| Delete-both-sides Layer 1 hole | MEDIUM | Removing a canonical handoff file **and** its `files` entry still passes Layer 1 (no required-set assertion). Fix needs a protocol decision on the minimal required set (STATUS + MANIFEST candidates). |
| Template/dogfood DASHBOARD staleness | LOW | DASHBOARD.md still shows early v2 task rows; selection authority is MANIFEST `tasks` (see WORKFLOW). Cosmetic. |
| Long LOG entry bodies | LOW | LOG.md is at the 10-entry cap with long bodies (~250 lines). Protocol entry count is satisfied; optional future trim of body length only. |
| Windows full-suite speed | LOW | Full bats is hours on this host; Linux CI / openclaw is the full-suite authority. |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved (this session)

| Item | Resolution |
|------|------------|
| PR #55 conflict markers | Merged: lint check 7 fails closed on `<<<<<<<` / `=======` / `>>>>>>>` |
| STATUS append-log drift (#56) | Rewrote to current-state snapshot (this file) |
| MANIFEST null summaries (#57) | Regenerated with meaningful quick_context + auto_summary depth fix |
| LOG "exceeds 10" claim (#58) | Closed as incorrect: exactly 10 entries (at cap, not over) |
| WORKFLOW drift (#59) | Phase 4.5, harness-owned models, MANIFEST task selection |
| Doctor partial index (#60.1) | handoff-set fails when canonical file present but not indexed |
| TRUST TTL drift (#60.2) | Re-verification sweep 2026-08-03 |
| NEXT_ACTIONS duplicate sections (#60.3) | Single Recently Completed section, max 5 |
| Perplexity meta-audit (#61) | Closed as non-evidence (model identity faked; rubber-stamped false #58) |

---

## Trust Levels

- **(Verified):** doctor handoff-set fails on partial index (new doctor.bats regression); conflict-marker check shipped in #55.
- **(Verified):** handoff rewrite + MANIFEST regeneration + `aahp verify --level prepush` this session.
- **(Assumed):** full suite green on Linux CI after push (not re-run locally end-to-end).
- **(Known gap):** delete-both-sides Layer 1 hole remains (see What is Missing).
