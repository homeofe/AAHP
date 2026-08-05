# AAHP: Current State of the Nation

> Last updated: 2026-08-05 by claude-sonnet-5
> Commit: (pending merge to main)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP **v3.9.2** (npm `@elvatis_com/aahp`), CHANGELOG cut and version bumped on this branch,
release tag pending merge to main. File-based AI-to-AI handoff protocol plus CLI for init,
lint, migrate, verify, check, doctor, status, archive, criteria, and manifest regeneration.

Shipped surface (high level):
- **Integrity:** `aahp verify` (4 layers), `aahp lint` (7 checks including conflict-marker
  refuse), MANIFEST checksums, LOG archive integrity index
- **Governance:** config-driven gates via `aahp check`, `aahp doctor` conformance record,
  CONSTITUTION.md, portable `init --gates`
- **Lifecycle:** acceptance-criteria advisory report (`aahp criteria`), Grounded Reflection
  Layer (TRUST provenance + GROUNDING.md), optional Phase 4.5 in WORKFLOW
- **Ops:** `aahp status`, `aahp archive`, OIDC npm publish on semver tags, badge workflows

This session (2026-08-05) is an AAHP-vs-supply-chain-guard (SCG) divergence audit and two
independent bug fixes, both now merged to `main` per Emre's "no divergence within my
projects" instruction:

- **PR #63:** fixed a Windows-only defect in `handoff-refresh`. `aahp-dashboard.mjs`
  shelled out to a bare `bash` with native backslash paths, which fails on Windows two
  independent ways: bash eats the backslashes as escapes, and a bare `bash` can resolve to
  the WSL launcher, which has no `C:` drive. Root cause was a second implementation -
  `bin/aahp.js` already solved this with its own `findBashExecutable()`/`toBashScriptArg()`,
  and the dashboard call site had neither. There is now ONE implementation,
  `resolveBash()`/`toBashPath()` in `aahp-config.mjs`, used by both, with a test that fails
  if a copy reappears. Found while fixing the identical pattern in supply-chain-guard's
  divergent fork, then reproduced and fixed upstream directly (not a field report).
- **PR #64:** fixed `aahp-manifest.sh` unconditionally overwriting MANIFEST `project` with
  the directory basename on every regeneration, clobbering a consumer's real project name
  whenever regenerated inside a differently-named checkout. Full detail in the audit section
  below.

Both fixes were found independently while investigating the same underlying problem (AAHP
vs. SCG divergence); #63's own "What is Missing" already flagged the `project`-clobber bug
by name and deliberately left it for a separate PR, which is what #64 became.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| npm version | OK | 3.9.2 cut on this branch (CHANGELOG + package.json); tag/publish pending merge |
| `bash-portability.bats` | OK (#63) | 13 tests, new; 12 pass + 1 skip on Git Bash (stand-in interpreter needs a POSIX shebang); CI green |
| `tests/manifest.bats` (#64) | OK | 21/21 local, incl. 2 new project-preservation tests; CI green |
| Real-consumer verification (#64) | OK | Fixed script run against a copy of SCG's actual `.ai/handoff/` from a differently-named directory; preserved `"project": "supply-chain-guard"` |
| `check-changelog-format.mjs` / `check-forbidden-patterns.mjs` | OK | ran locally for #64 |
| `aahp doctor` | OK (pre-existing) | handoff-set fails on partial index (aligned with verify Layer 1 / lint) |
| `doctor.bats` / `lint.bats` / `verify.bats` / `gates.bats` / `acceptance-criteria.bats` | OK (CI, pre-existing) | untouched by #63/#64; CI is authoritative |
| `cli.bats` | PARTIAL local | known Windows-only flakes; green on Linux CI |
| `npm run check` | OK | 8 config-driven gates |
| shellcheck | CI | not installed offline on this Windows host; CI covers shipped scripts, incl. both branches' changes |
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
| Dashboard check | `scripts/aahp-dashboard.mjs` | Complete | handoff freshness; bash call goes through `resolveBash`/`toBashPath` |
| Shared config lib | `scripts/aahp-config.mjs` | Complete | root/pkg/config resolution, git enumeration, bash interpreter + path portability |
| Manifest gen | `scripts/aahp-manifest.sh` | Complete | preserves tasks / next_task_id / cross_repo_ref / project |
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
| No Windows CI runner | MEDIUM | CI is `ubuntu-latest` only, so no job executes the shipped bash tooling under Git Bash. This is how the `handoff-refresh` interpreter defect (fixed in #63) reached a consumer. Mitigated but not closed: `resolveBash`/`toBashPath` take `platform`/`env` as parameters, so their win32 behaviour is asserted on the Linux runner. A `windows-latest` bats job would cover the remaining surface (`_aahp-lib.sh`, `verify-handoff.sh`, `lint-handoff.sh`), and is a larger change than either #63 or #64. |
| Consumer-only code paths untested | MEDIUM | AAHP configures only `generate.freshness`, so `writeLog()` returns before the bash call and AAHP's own dogfooding never executes it. Any AAHP-only gate run, on any platform, is blind to that branch. Coverage has to come from a consumer-shaped fixture. |
| AAHP/SCG shared-primitive duplication | MEDIUM | `_aahp-lib.sh` and `aahp-manifest.sh` are hand-copied into `homeofe/supply-chain-guard` because SCG's fork `aahp-dashboard.mjs` calls the local copies. See "AAHP vs supply-chain-guard divergence audit" below. Decision needed from Emre before Step 3 (SCG-side) can land. |
<!-- /SECTION: what_is_missing -->

---

## AAHP vs supply-chain-guard divergence audit (2026-08-05)

Emre asked to eliminate divergence between AAHP and its consumer `homeofe/supply-chain-guard`
(SCG, v5.25.4, pins `@elvatis_com/aahp` at exact 3.9.1). Audited by execution (diffs, greps,
functional tests, live gate runs), not by reading claims. Full per-claim evidence lives in
this session's transcript; summary below.

**Confirmed:** SCG shadows exactly three AAHP-published files (`_aahp-lib.sh`,
`aahp-manifest.sh`, `aahp-dashboard.mjs`) because SCG's fork dashboard calls the local
`aahp-manifest.sh`, which sources the local `_aahp-lib.sh`. `propagate.sh` (AAHP's
anti-divergence mechanism) copies the first two but not the third by design.
`aahp-dashboard.mjs` is architecturally a different program in each repo (AAHP: generic,
config-driven, arbitrary consumer root via `resolveRoot()`; SCG: hardcoded to itself,
generates DASHBOARD.md/TRUST.md/LOG.md from `src/`, `tsconfig.json`, a dependency table).
`scripts/` is published with no `package.json` `exports` map, so a consumer can deep-import
`@elvatis_com/aahp/scripts/*.mjs` today with zero AAHP change; adding an `exports` map later
is a breaking-shaped change (allowlists every unlisted deep import).

**Fixed this session (Step 1):** `aahp-manifest.sh` unconditionally overwrote MANIFEST
`project` with the directory basename on every regeneration - confirmed by a functional
test (not just a code read), including against a real copy of SCG's own `.ai/handoff/`.
Fixed to preserve the existing value except on first-ever generation. Also fixed a latent
bug this uncovered in the *same* preservation mechanism added in 3.9.1: the tasks/
`next_task_id`/`cross_repo_ref` fields were tab-joined and split with `IFS=$'\t' read`, but
tab is IFS whitespace, so bash silently strips/collapses leading empty fields whenever an
earlier field is empty and a later one isn't (e.g. no tasks but a `cross_repo_ref` present).
Switched the delimiter to `\x1f` (Unit Separator). Bats coverage added; merged to main as #64.

**Corrections to the pre-session brief (verify before trusting a summary of this audit -
these were wrong or overstated in the original working notes, don't re-propagate them):**
- SCG's `aahp.config.json` `check.skip: ["handoff"]` does **not** disable the real 4-layer
  handoff gate. It only skips one narrow sub-check inside `aahp check`. The actual gate
  (`aahp verify . --level ci`) runs unconditionally in SCG's `aahp-verify.yml`, no escape
  hatch. SCG's handoff protocol enforcement is intact.
- SCG's TRUST records are **not** stale/expired. All 5 rows are within TTL as of
  2026-08-05 (2 of them expire *today* and need refreshing by 2026-08-06, but that is a
  same-day risk, not an active false-pass).
- No gate named or shaped like "schema-doc-sync" enforces "new `aahp.config.json` key needs
  a schema + README update." `check-schema-doc-sync.mjs` is an unrelated generic value-set
  comparator. `additionalProperties: false` is real in the schema but is only exercised by
  one bats test on `aahp init --gates` output, not on hand-edited configs.
- SCG's CHANGELOG-heading and NEXT_ACTIONS-freshness regexes in SCG's fork dashboard **do**
  silently drop SemVer prerelease/build-metadata versions (confirmed, both instances) - this
  is a real latent bug in SCG's fork, not currently observable (no prerelease headings exist
  yet), out of scope for this AAHP session, worth a note in SCG's own backlog.

## Decisions from Emre

1. **Step 2 - primitive-sharing mechanism: resolved.** Emre approved merging #63 and #64
   and cutting a release, 2026-08-05. Both merged to `main`. Recommendation carried forward:
   SCG deep-imports `resolveBash`/`toBashPath` (and similar shared primitives) from
   `@elvatis_com/aahp/scripts/aahp-config.mjs` - this works today with zero further AAHP
   change. A declared `exports` map is cleaner but is a breaking-shaped change (allowlists
   every unlisted deep import) and was not added.
2. **Step 4 - generalize SCG's generators into AAHP?: still open.** Emre pushed back on the
   "logic only, stop at Step 3" recommendation, asking for the actual argument against fully
   upstreaming rather than a restatement of "it's a lot of work." Answered in-session:
   (a) after Step 3 there is no *shared* logic left to diverge - the two vendored bash files
   are deleted outright, and what remains in SCG imports AAHP rather than duplicating it,
   structurally the same as any consumer importing a library and writing its own code on
   top; (b) AAHP's own CLAUDE.md commits it to being stack-agnostic (Node + bash + standard
   tools only), while SCG's generator is Node/TypeScript-shaped (`tsconfig.json`, `src/`
   layout, a `commander` pin) - absorbing it means redesigning it as config-driven, not
   moving code, which is the actual multi-session cost; (c) blast radius is asymmetric - a
   bug in SCG's generator today (two were found this session, see corrections above) affects
   only SCG, but the same bug upstreamed ships to every AAHP consumer; (d) renaming/moving
   the generator changes its AUTO-GENERATED banner, which changes DASHBOARD/TRUST/LOG
   content, which changes MANIFEST checksums - not additive, a breaking change needing its
   own migration. A middle path (AAHP owns a plugin mechanism, consumers register their own
   sections) was floated as worth scoping separately rather than deciding by default. Emre
   has not yet picked an option pending this answer - revisit before starting Step 4.
3. **Step 3 - SCG-side changes** (bump pin, delete SCG's duplicated primitives, pull
   `aahp_manifest_index()` down, delete the two stale bash copies, rename
   `aahp-dashboard.mjs`) can now start: the release exists to pin to. Not started this
   session - next incoming agent or session should pick this up in supply-chain-guard.

---

## Recently Resolved (this session)

| Item | Resolution |
|------|------------|
| `handoff-refresh` MANIFEST regen fails on Windows (#63) | `resolveBash()` prefers an installed Git Bash over a bare PATH lookup; `toBashPath()` normalises separators. `AAHP_BASH` still overrides both. |
| Windows behaviour untestable on Linux CI (#63) | Helpers take `platform`/`env` as parameters, so `tests/bash-portability.bats` asserts the win32 paths deterministically on `ubuntu-latest`. |
| AAHP/SCG divergence audit | Verified by execution; several pre-session claims corrected (see section above) |
| MANIFEST `project` clobber bug (#64) | Fixed; preserves existing value except on first-ever generation |
| Latent tab/IFS field-misalignment bug (#64) | Found while fixing the above (same code block, added in 3.9.1); fixed by switching the field delimiter to `\x1f` |

Prior sessions' resolved items (#55-#61, 2026-08-03 handoff hygiene sweep) are in LOG.md
and CHANGELOG.md; not repeated here per this file's own "current reality, not history" rule.

---

## Trust Levels

- **(Verified):** #63's defect reproduces on Windows with unmodified 3.9.1 against a consumer-shaped config (`generate.log` set); mutation proof on `tests/bash-portability.bats` (revert turns the two defect-specific tests red).
- **(Verified):** #64's MANIFEST `project`-preservation fix, by functional test plus a real-consumer run against a copy of SCG's actual `.ai/handoff/`.
- **(Verified):** `gates.bats` 22/22, `npm run check`, and `tests/manifest.bats` 21/21 green locally; both PRs' CI (10 checks each) green before merge.
- **(Assumed):** full suite green on Linux CI after push (not re-run locally end-to-end on Windows; shellcheck unavailable on this host).
- **(Known gap):** no Windows CI runner, and AAHP's own config cannot reach the `writeLog()` bash-call path (see What is Missing).
- **(Known gap):** delete-both-sides Layer 1 hole remains (see What is Missing).
- **(Known gap):** AAHP/SCG shared-primitive duplication remains until Emre decides Step 2/4
  (see "Decisions needed from Emre" above).
