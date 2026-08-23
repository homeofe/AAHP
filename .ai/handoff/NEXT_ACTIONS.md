# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".
> Acceptance criteria use the canonical heading and task boxes (README Section 8.7):
> `- [ ]` while unresolved, `- [x]` only on evidence; before a task is `done` every
> criterion is checked, waived `(waived: rationale)`, or moved `(follow-up: ref)`.

Current version: **v3.11.0**

---

## Status Summary

Counts mirror the `tasks` registry in `MANIFEST.json`.

| Status | Count |
|--------|-------|
| Done | 5 |
| Ready | 0 |
| Blocked | 0 |

---

## Recently Completed

### 2026-08-20: v3.10.0 prepared - fail-closed CI base + reviewed M-only impact

- Added explicit `--base SHA` / `AAHP_BASE_SHA` anchoring. CI rejects missing, zero,
  invalid, unreadable, HEAD-equal, and undiffable bases.
- Added exact regular tracked-file `handoffImpact.nonImpactingModifiedFiles` entries with
  required reasons. Only `M` can be non-impacting; A/D/R/C and mixed source changes
  remain impacting.
- Removed the actor-wide dependency-bot workflow bypass, so Layer 1 always runs.
- Added focused mutation, schema, workflow, CLI, and propagation coverage.
- Prepared version 3.10.0 without tagging, publishing, or merging it.

### 2026-08-05: v3.9.2 - Windows bash portability + MANIFEST project-name preservation (#63, #64)

- #63: unified bash interpreter resolution / Windows path handling into one implementation
  (`resolveBash`/`toBashPath` in `aahp-config.mjs`), used by both `bin/aahp.js` and
  `scripts/aahp-dashboard.mjs`; fixed a Windows-only `handoff-refresh` crash.
- #64: `aahp-manifest.sh` no longer clobbers an existing MANIFEST `project` value with the
  checkout's basename on regeneration; also fixed a latent tab/IFS field-misalignment bug
  in the same tasks/next_task_id/cross_repo_ref preservation mechanism.
- Both found while auditing AAHP-vs-supply-chain-guard divergence; full detail and open
  decisions in STATUS.md.

### 2026-08-03: Handoff hygiene + doctor partial-index alignment (issues #56-#61)

- Rewrote STATUS.md to a current-state snapshot; fixed MANIFEST summaries / quick_context.
- Aligned WORKFLOW.md (Phase 4.5, harness-owned models, MANIFEST task selection).
- doctor `handoff-set` now fails on a partial index (matches Layer 1 / lint).
- Closed false LOG "exceeds 10" claim (#58) and Perplexity meta-stamp (#61).

### T-033: Reusable AAHP badge workflows [medium] (issue #12)

- Added stable per-check workflows for AAHP Verify, Lint, Manifest, Archive, and PII Allowlist.
- Documented badge snippets for downstream repositories.

### T-032: LOG archive integrity [medium] (issue #11)

- Added `aahp archive` with default keep=10 behavior and `--verify`.
- Added archive tests and MANIFEST coverage for `LOG-ARCHIVE.md`.

### T-031: Reviewed, expiring PII allowlist [high] (external backlog item)

- Added a strict exact-email allowlist with owner, reason, and expiry fields.
- Integrated it into `aahp lint` and MANIFEST integrity; it cannot suppress secrets.
- Added schema, template, rollout owners, and regression tests.

### T-014 / T-015 / T-016 / T-017 / T-006 (CLI, status, archive, CLAUDE.md, npm)

- Closed via prior releases; detail and criteria evidence remain in the section below.

---

## Completed - Detail and Closure Evidence

### T-014: Add CLI integration tests for bin/aahp.js [high] (issue #14)
**Priority:** high

**Goal:** Test the Node.js CLI entry point end-to-end so the primary user interface has automated coverage.

**Context:**
- All 48 existing bats tests cover the bash scripts (manifest, lint, migrate) - none test `bin/aahp.js` itself
- The `init` command (pure Node.js file copy) has zero automated tests
- CLI argument parsing, `--help`, `--version`, error messages, and subcommand dispatch are untested
- This is the main entry point users interact with via `npx aahp`

**What to do:**
1. Create `tests/cli.bats` with integration tests for the CLI
2. Test `aahp --version` outputs the correct version (3.0.0)
3. Test `aahp --help` outputs usage information
4. Test `aahp init` creates `.ai/handoff/` with all expected template files
5. Test `aahp init --force` overwrites existing files
6. Test `aahp init <path>` initializes at a custom directory
7. Test `aahp` with no arguments shows help or usage
8. Test `aahp unknown-command` exits with an error
9. Test that `aahp manifest`, `aahp lint`, `aahp migrate` dispatch correctly (at minimum, verify they don't crash with `--help` or on a valid handoff directory)
10. Add the new test file to CI (it should already run via `npx bats tests/`)

**Files:** `bin/aahp.js`, `tests/cli.bats`, `tests/test_helper.bash`

**Acceptance criteria:**
- [x] `tests/cli.bats` exists with 10+ tests covering all subcommands (57 tests; `--help`, `init`, `manifest`, `lint`, `migrate`, `verify`, `check`, `archive`, `status`, unknown-command)
- [x] All tests pass locally and in CI (`tests/cli.bats` runs in the `lint-and-validate` job on every push)
- [x] Init command tested: creates correct files, handles --force, custom paths (`aahp init --force overwrites existing files`, `aahp init with absolute path works regardless of cwd`, `aahp init with relative path resolves from cwd`)

---

### T-015: Add `aahp status` quick-look command [medium] (issue #22)
**Priority:** medium

**Goal:** Add a `status` subcommand that reads MANIFEST.json and prints a concise project summary, so agents and humans can orient instantly without opening files manually.

**Context:**
- Currently, getting project state requires reading MANIFEST.json or STATUS.md manually
- The layered read strategy (Section 1 of the spec) says agents should read the manifest first - a CLI command makes this even easier
- This is a natural companion to the existing `init`, `manifest`, `lint`, `migrate` commands

**What to do:**
1. Add a `status` case to `bin/aahp.js` command dispatch
2. Implement in pure Node.js (no bash dependency) - read and parse `.ai/handoff/MANIFEST.json`
3. Print a formatted summary: project name, last agent, phase, quick_context, task counts by status, file list with line counts
4. If MANIFEST.json is missing, print a helpful message suggesting `aahp init` or `aahp manifest`
5. Add tests in `tests/cli.bats` for the new command
6. Update `--help` output to include the new command

**Files:** `bin/aahp.js`, `tests/cli.bats`

**Acceptance criteria:**
- [x] `aahp status` reads MANIFEST.json and prints a human-readable summary (`status` case in `bin/aahp.js`; test `aahp status prints project, phase, and task counts`)
- [x] Shows task breakdown (ready/blocked/done counts) (same test; open ready/in_progress tasks are listed separately)
- [x] Graceful error when no MANIFEST.json exists (tests `aahp status fails when MANIFEST.json is missing` and `aahp status hint mentions init or manifest when MANIFEST is missing`)
- [x] Tests cover the happy path and missing-manifest case (`aahp status exits 0 on a generated manifest` plus the two missing-manifest tests above)

---

### T-016: Add `aahp archive` command for LOG.md rotation [medium] (issue #23)
**Priority:** medium

**Goal:** Automate the LOG.md to LOG-ARCHIVE.md split described in README Section 1.3, keeping LOG.md lean for token efficiency.

**Context:**
- README Section 1.3 specifies: "Keep only the last N entries in LOG.md. Move older entries to LOG-ARCHIVE.md"
- A LOG-ARCHIVE.md template already exists in `templates/`
- Currently there is no tooling to perform this split - agents or humans must do it manually
- The project's own LOG.md is at 161 lines and growing

**What to do:**
1. Create `scripts/aahp-archive.sh` that:
   - Reads LOG.md and counts entries (delimited by `---` separators or `## Entry` headers)
   - Accepts a `--keep N` flag (default: 5) for how many recent entries to retain
   - Moves older entries to LOG-ARCHIVE.md (append, preserving chronological order)
   - Updates LOG.md to contain only the N most recent entries
   - Is idempotent (safe to run multiple times)
2. Add `archive` case to `bin/aahp.js` that dispatches to the script
3. Add `tests/archive.bats` with tests for: basic split, --keep flag, idempotency, missing LOG.md, empty LOG.md
4. Source `_aahp-lib.sh` for shared utilities

**Files:** `scripts/aahp-archive.sh`, `bin/aahp.js`, `tests/archive.bats`, `templates/LOG-ARCHIVE.md`

**Acceptance criteria:**
- [x] `aahp archive` splits LOG.md entries into LOG.md (recent) + LOG-ARCHIVE.md (older) (`scripts/aahp-archive.sh`, dispatched from `bin/aahp.js`)
- [ ] `--keep N` flag controls retention count (default 5) (waived: the flag ships and controls retention, but the default landed at 10, not 5, because the archive integrity work in T-032 set the retention floor there; the "5" in this criterion was superseded, not skipped)
- [x] Idempotent - running twice produces the same result (covered by `tests/archive.bats`, 7 tests)
- [x] Bats tests cover all edge cases (`tests/archive.bats` plus the `aahp archive` cases in `tests/cli.bats`)

---

### T-017: Add project-level CLAUDE.md [low] (issue #24)
**Priority:** low

**Goal:** Create an AAHP-specific CLAUDE.md so AI agents working on this project get correct conventions without relying solely on the workspace-level file.

**Context:**
- The workspace-level `CLAUDE.md` (parent directory) provides general conventions
- AAHP has project-specific patterns: zero-dependency Node.js, bash scripts sourcing `_aahp-lib.sh`, bats testing, shellcheck compliance, the AAHP v3 format itself
- Other projects in the same workspace already have project-level CLAUDE.md files
- This helps new agents contribute correctly on the first attempt

**What to do:**
1. Create `CLAUDE.md` in the AAHP project root
2. Document: project overview, tech stack (Node.js ESM + bash, zero npm deps), directory layout
3. Document: how to run tests (`npm test`), how to lint (`bash scripts/lint-handoff.sh .`), how to validate schema
4. Document: conventions - scripts source `_aahp-lib.sh`, CLI dispatches to bash scripts, templates use `[PLACEHOLDER]` syntax
5. Document: shellcheck must pass on all `.sh` files, bats tests required for new scripts
6. Keep it concise (under 80 lines)

**Files:** `CLAUDE.md` (new file in project root)

**Acceptance criteria:**
- [x] `CLAUDE.md` exists in project root with build/test/lint commands
- [x] Covers project-specific conventions not in workspace CLAUDE.md (zero-dependency Node ESM plus bash, `_aahp-lib.sh` sourcing, bats, shellcheck, the v3 handoff format)
- [ ] Under 80 lines (waived: the file is 121 lines. The governance gates and the archive command arrived after this criterion was written and both need documenting; cutting back to 80 would remove instructions an incoming agent needs. The length target is dropped rather than met)

---

### T-006: Publish npm package (issue #18)
**Priority:** medium

**Goal:** Publish the AAHP CLI to the npm registry so it can be run with `npx`.

**Resolution:** shipped. The package is on the public npm registry as
`@elvatis_com/aahp`, first published 2026-03-19 and continuously since; the registry
lists eleven versions with `latest` at 3.8.1 (2026-07-19). CI publishes it, so the
"blocked on human npm auth" note that stood in this file was years of releases out of
date. The registry itself is the evidence: `npm view @elvatis_com/aahp version`.

**Files:** `package.json`, `bin/aahp.js`, `.github/workflows/ci.yml` (`publish` job)

**Acceptance criteria:**
- [x] Package published to npm registry (public registry, `@elvatis_com/aahp`, `latest` 3.8.1, eleven versions since 2026-03-19)
- [ ] `npx aahp init` works from any directory (waived: the package shipped under the scoped name `@elvatis_com/aahp`, so the bare `npx aahp` form this criterion names resolves to a different package and always will. The intent, runnable without a global install, is met by `npx @elvatis_com/aahp init`. The criterion was superseded by the naming decision rather than met)

---

## Blocked

None.

---

## Reference: Key File Locations

| What | Where |
|------|-------|
| v2/v3 Specification | `README.md` |
| Templates | `templates/` |
| Scripts | `scripts/` |
| JSON Schema | `schema/aahp-manifest.schema.json` |
| CLI entry point | `bin/aahp.js` |
| CI workflow | `.github/workflows/ci.yml` |
| Publish job | `.github/workflows/ci.yml` (`publish`) |
| Test suite | `tests/` |
| License | `LICENSE` (Apache-2.0) |
| Own handoff files | `.ai/handoff/` |
