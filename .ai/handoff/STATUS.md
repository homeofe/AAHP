# AAHP: Current State of the Nation

> Last updated: 2026-06-20 by Claude Opus 4.8 (1M context)
> Commit: (pending)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP v3 plus the new canonical handoff gate. `aahp verify`
(`scripts/verify-handoff.sh`) is now the single gate against staled handoff
state. It runs 4 layers: (1) MANIFEST checksum integrity via lint-handoff.sh,
(2) the content-drift gate (code changed outside .ai/handoff/ requires STATUS.md
plus a regenerated MANIFEST.json, else HARD-FAIL), (3) commit-pointer freshness,
(4) TRUST-TTL expiry (advisory). It is wired via a git pre-commit hook (fast:
checksum plus drift) and a pre-push hook (full plus TTL), installable with
`scripts/install-hooks.sh`, plus a CI workflow `.github/workflows/aahp-verify.yml`
running `aahp verify --level ci` as the intended REQUIRED check (committed now;
GitHub Actions is OFF org-wide for a cost sweep, so it activates when Actions is
re-enabled). The gate is verify-only: it never regenerates MANIFEST.json, that
stays a separate /handoff step. Escape hatch `AAHP_SKIP_VERIFY=1` skips local
verification only and is ignored at `--level ci`.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `scripts pass` | OK | All scripts syntax-checked (bash -n) |
| `lint-handoff.sh` | OK | All 6 checks pass |
| `aahp verify` | OK | New gate: 4 layers, verified end-to-end on a temp repo |
| `verify.bats` | OK | 12/12 pass |
| `lint.bats` | OK | 26 ok, 1 pre-existing skip (added 5 PII line-granularity tests, T-029) |
| `manifest.bats` | OK | 18/18 pass |
| `cli.bats` | OK | verify help test added; 2 pre-existing Windows-only failures (version-capture flake, read-only-dir) pass on Linux CI |
| `npx aahp` CLI | OK | init, manifest, lint, migrate, verify commands work |
| `shellcheck` | PENDING | Not installable offline on this machine; runs in CI (ci.yml extended to cover the new scripts) |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| Verify Gate | `scripts/verify-handoff.sh` | Complete | 4 layers, `--level precommit/prepush/full/ci` |
| Shared Library | `scripts/_aahp-lib.sh` | Complete | Added aahp_manifest_field, aahp_trust_expired, aahp_python_cmd |
| Pre-commit Hook | `scripts/hooks/pre-commit` | Complete | Fast: checksum plus drift gate |
| Pre-push Hook | `scripts/hooks/pre-push` | Complete | Full verify plus TTL |
| Hook Installer | `scripts/install-hooks.sh` | Complete | Respects core.hooksPath; backs up non-AAHP hooks |
| Verify CI | `.github/workflows/aahp-verify.yml` | Complete | Intended REQUIRED check; activates when Actions re-enabled |
| Rollout Plan | `scripts/ROLLOUT.md` | Complete | ~10 active Elvatis repos, ordered |
| Verify Tests | `tests/verify.bats` | Complete | 12 tests covering all layers plus escape hatch |
| Manifest Generator | `scripts/aahp-manifest.sh` | Complete | v3: preserves tasks on regen |
| Migration Script | `scripts/aahp-migrate-v2.sh` | Complete | Delegates to aahp-manifest.sh |
| Lint Script | `scripts/lint-handoff.sh` | Complete | 6 checks, cross-platform Python; PII email scan locale-robust (grep -E, T-027) and per-match filtered (grep -rHnoE + awk, T-029) |
| JSON Schema | `schema/aahp-manifest.schema.json` | Complete | v3: tasks plus next_task_id |
| CLI (npx aahp) | `bin/aahp.js` | Complete | verify command registered |
| CI Pipeline | `.github/workflows/ci.yml` | Complete | shellcheck now covers verify/hooks/installer |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| Actions disabled | LOW | aahp-verify.yml committed but inert until GitHub Actions is re-enabled org-wide; local hooks enforce in the meantime |
| Propagation | MEDIUM | Gate applied to AAHP plus improvements; ~9 more active repos queued in ROLLOUT.md |
| shellcheck local | LOW | Not run on this machine (offline); CI covers it |
<!-- /SECTION: what_is_missing -->

---

## Recently Resolved

| ID | Item | Resolution |
|----|------|-----------|
| T-018 | Build canonical aahp verify gate | scripts/verify-handoff.sh, 4 layers, 12 bats tests |
| T-019 | Wire pre-commit and pre-push hooks | scripts/hooks/ plus install-hooks.sh, verified end-to-end |
| T-020 | Add aahp-verify CI workflow | .github/workflows/aahp-verify.yml (level ci) |
| T-021 | Write rollout plan | scripts/ROLLOUT.md |
| T-022 | Fix over-broad secret patterns in lint-handoff.sh | Length floor {16,} on sk-/ghp_/gho_/AKIA; killed the "sk-to" false positive (e.g. inside "task-to-model"); propagated to improvements; lint.bats 18/18 |
| T-023 | CRLF/LF checksum mismatch broke AAHP Verify CI | Strip CR before hashing in aahp_checksum (_aahp-lib.sh) + lint-handoff.sh so checksums are line-ending-agnostic (Windows working tree vs Linux CI checkout); bats 48/48 |
| T-024 | Cut v3.0.2 release + add propagate.sh | License unified to Apache-2.0 (README fixed to match LICENSE + package.json); scripts/propagate.sh added as the reusable gate-sync function; version 3.0.1 -> 3.0.2; full-landscape rollout |
| T-025 | Harden propagate.sh (canary findings) | Stage the whole .ai/handoff (so a repo with uncommitted handoff edits stays consistent with the regenerated manifest, else CI fails on a checksum the commit never includes); make the baseline pre-check non-fatal (commit hook is the real gate). Validated on aahp-runner, CI green. |
| T-026 | Windows-path false-positive in lint-handoff.sh | Gate handed an absolute MSYS path (/c/Users/...) to Windows-native Python's open(), which raised FileNotFoundError; swallowed by 2>/dev/null and mislabeled "Invalid JSON", blocking Layer 1 on 6 repos. Fixed by cd into PROJECT_ROOT once and using relative paths (PROJECT_ROOT=".", HANDOFF_DIR=".ai/handoff") in lint-handoff.sh + verify-handoff.sh, so the path format no longer matters. Reproduced with /c/ path (false-fail before, passes after); bats green; v3.0.3. |
| T-027 | PII check locale-robust + GitHub noreply exclusion | Check 3 email scan used `grep -rnP` (PCRE); under an empty/non-UTF-8 locale on Windows git-bash GNU grep -P aborts ("supports only unibyte and UTF-8 locales") and the pipeline silently passed (false PASS), while the UTF-8 locale `git commit` sets made it fire -non-deterministic by locale. Switched to `grep -rnE` (POSIX-ERE, no PCRE locale fail-open) with an internal LC_ALL=C.UTF-8 pin, so detection is byte-identical under LC_ALL= (empty), C.UTF-8, and en_US.UTF-8. Added two narrow exclusions (users.noreply.github.com co-author trailers + any *.noreply.* domain); real human/customer emails stay a HARD-FAIL, no allowlist file. 3 new lint.bats tests; bats green; v3.0.4. |
| T-029 | PII check switched to per-match filtering (line-granularity false-negative) | Check 3 extracted whole matched lines and dropped any line containing an excluded token via a line-level `grep -v`, so a genuine external email sharing a single line with an excluded token (a `.noreply.` co-author trailer, `example.com`, or the word `placeholder`) was silently suppressed -a real PII false negative. Switched to per-MATCH filtering: extract each address with `grep -rHnoE` and exclude per ADDRESS in `awk`, so an excluded token elsewhere on the same line can no longer mask a separate real address. Locale-determinism preserved (`grep -E` not `-P`, LC_ALL=C.UTF-8 pin); detection stays byte-identical across locales. 5 new lint.bats T-029 regression tests; bats green; v3.0.5. |
| T-030 | Add README status-badge block (2026-06-21) | Inserted auto-detected badges after the H1: CI (ci.yml), AAHP Verify (aahp-verify.yml), Security (codeql.yml), npm (@elvatis_com/aahp, published v3.0.5), License Apache-2.0. README change is code outside .ai/handoff, so routed through the drift gate (STATUS.md note + regenerated MANIFEST.json). |

---

## Trust Levels

- **(Verified)**: `aahp verify` runs all 4 layers correctly; drift gate hard-fails, escape hatch skips locally and is ignored at level ci (tested on a temp consumer repo and end-to-end via the installed pre-commit hook).
- **(Verified)**: verify.bats 12/12, lint.bats 26 ok plus 1 pre-existing skip, manifest.bats 18/18 pass locally.
- **(Verified)**: No em-dashes (U+2014) in any file touched this session.
- **(Assumed)**: shellcheck clean for the new scripts (syntax-checked with bash -n; full shellcheck runs in CI).
