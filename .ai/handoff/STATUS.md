# AAHP: Current State of the Nation

> Last updated: 2026-08-05 by claude-opus-5
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

This session (2026-08-05) fixes a Windows-only defect in `handoff-refresh` and removes the
duplication that caused it. `aahp-dashboard.mjs` shelled out to a bare `bash` with native
backslash paths. Both halves fail on Windows: bash eats the backslashes as escapes, and a
bare `bash` can resolve to the WSL launcher, which has no `C:` drive. `LOG.md` is written
before the regen, so the failure leaves MANIFEST checksums stale against the file just
produced.

The root cause was a second implementation: `bin/aahp.js` already solved this (its comment
reads "prefer Git Bash over the WSL bash shim and avoid raw C:\... script arguments") with
its own `findBashExecutable()`/`toBashScriptArg()`, and the dashboard call site had neither
and knew nothing of them. There is now ONE implementation in `aahp-config.mjs`, used by
both, merging what each side got right, plus a test that fails if a copy reappears.

Provenance, stated precisely: found while fixing the identical pattern in
supply-chain-guard, which runs a **divergent local fork** of this script whose bash call
has no `generate.log` guard and is therefore always reachable. SCG does not configure
`generate.log` and does not consume the packaged dashboard in write mode, so it is not a
consumer of this fix. The upstream defect was reproduced directly against a
consumer-shaped fixture. Upstream the call is reached only in write mode by a consumer
that configures `generate.log`; `--check` exits before it. This is therefore a correctness
fix ahead of a field report, not a response to one.
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
| `nonnpm-root.bats` | OK | 11 tests; fixtures write handoff files before indexing (partial-index alignment) |
| `lint.bats` | OK | 39 tests incl conflict-marker coverage (CI green on #55) |
| `verify.bats` | OK | 22 tests (CI authoritative for full suite) |
| `gates.bats` | OK | 22 tests; re-run this session (test 22 exercises the dashboard write path) |
| `bash-portability.bats` | OK | 13 tests, new; 12 pass + 1 skip on Git Bash (stand-in interpreter needs a POSIX shebang) |
| `aahp manifest` / `lint` / `verify` | OK | re-run after routing `bin/aahp.js` through the shared helpers; all exit 0 on Windows |
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
| Dashboard check | `scripts/aahp-dashboard.mjs` | Complete | handoff freshness; bash call goes through `resolveBash`/`toBashPath` |
| Shared config lib | `scripts/aahp-config.mjs` | Complete | root/pkg/config resolution, git enumeration, bash interpreter + path portability |
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
| No Windows CI runner | MEDIUM | CI is `ubuntu-latest` only, so no job executes the shipped bash tooling under Git Bash. This is how the `handoff-refresh` interpreter defect reached a consumer. Mitigated but not closed: `resolveBash`/`toBashPath` take `platform`/`env` as parameters, so their win32 behaviour is asserted on the Linux runner. A `windows-latest` bats job would cover the remaining surface (`_aahp-lib.sh`, `verify-handoff.sh`, `lint-handoff.sh`), and is a larger change than this fix. |
| Consumer-only code paths untested | MEDIUM | AAHP configures only `generate.freshness`, so `writeLog()` returns before the bash call and AAHP's own dogfooding never executes it. Any AAHP-only gate run, on any platform, is blind to that branch. Coverage has to come from a consumer-shaped fixture. |
| `aahp-manifest.sh` clobbers `project` on regeneration | MEDIUM | `PROJECT_NAME=$(basename ...)` is unconditional (`scripts/aahp-manifest.sh`), so regenerating inside a differently-named checkout (temp dir, CI dir, tarball) overwrites a consumer's real project name. supply-chain-guard already carries the fix (preserve the existing MANIFEST `project`, derive from basename only on first generation) and it was never upstreamed. The estate's most-depended-upon repo is the one carrying the bug. Not fixed here to keep this PR to one concern. |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved (this session)

| Item | Resolution |
|------|------------|
| `handoff-refresh` MANIFEST regen fails on Windows | `resolveBash()` prefers an installed Git Bash over a bare PATH lookup; `toBashPath()` normalises separators. `AAHP_BASH` still overrides both. |
| Windows behaviour untestable on Linux CI | Helpers take `platform`/`env` as parameters, so `tests/bash-portability.bats` asserts the win32 paths deterministically on `ubuntu-latest`. |

---

## Trust Levels

- **(Verified):** the defect reproduces on Windows with unmodified 3.9.1 against a consumer-shaped config (`generate.log` set). Observed: `/bin/bash: C:UsersrootworkspaceAAHPscriptsaahp-manifest.sh: No such file or directory`, with the separators stripped and the interpreter resolved to WSL.
- **(Verified):** mutation proof on the new suite. Reverting both helpers to their pre-fix behaviour turns exactly the two defect-specific tests red; restoring turns them green.
- **(Verified):** `gates.bats` 22/22 and `npm run check` green after the change; `handoff-refresh` completes end-to-end on the consumer fixture and now resolves an absolute Git Bash rather than relying on PATH order.
- **(Assumed):** full suite green on Linux CI after push (only the two affected suites were run locally).
- **(Known gap):** no Windows CI runner, and AAHP's own config cannot reach the fixed code path (see What is Missing).
- **(Known gap):** delete-both-sides Layer 1 hole remains (see What is Missing).
