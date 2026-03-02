# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 9 |
| Ready | 4 |
| Blocked | 1 |

---

## Ready - Work These Next

### T-014: Add CLI integration tests for bin/aahp.js [high] (issue #7)
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

**Definition of done:**
- [ ] `tests/cli.bats` exists with 10+ tests covering all subcommands
- [ ] All tests pass locally and in CI
- [ ] Init command tested: creates correct files, handles --force, custom paths

---

### T-015: Add `aahp status` quick-look command [medium] (issue #8)
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

**Definition of done:**
- [ ] `aahp status` reads MANIFEST.json and prints a human-readable summary
- [ ] Shows task breakdown (ready/blocked/done counts)
- [ ] Graceful error when no MANIFEST.json exists
- [ ] Tests cover the happy path and missing-manifest case

---

### T-016: Add `aahp archive` command for LOG.md rotation [medium] (issue #9)
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

**Definition of done:**
- [ ] `aahp archive` splits LOG.md entries into LOG.md (recent) + LOG-ARCHIVE.md (older)
- [ ] `--keep N` flag controls retention count (default 5)
- [ ] Idempotent - running twice produces the same result
- [ ] Bats tests cover all edge cases

---

### T-017: Add project-level CLAUDE.md [low] (issue #10)
**Priority:** low

**Goal:** Create an AAHP-specific CLAUDE.md so AI agents working on this project get correct conventions without relying solely on the workspace-level file.

**Context:**
- The workspace-level `CLAUDE.md` (parent directory) provides general conventions
- AAHP has project-specific patterns: zero-dependency Node.js, bash scripts sourcing `_aahp-lib.sh`, bats testing, shellcheck compliance, the AAHP v3 format itself
- Other projects in the workspace (AEGIS) already have project-level CLAUDE.md files
- This helps new agents contribute correctly on the first attempt

**What to do:**
1. Create `CLAUDE.md` in the AAHP project root
2. Document: project overview, tech stack (Node.js ESM + bash, zero npm deps), directory layout
3. Document: how to run tests (`npm test`), how to lint (`bash scripts/lint-handoff.sh .`), how to validate schema
4. Document: conventions - scripts source `_aahp-lib.sh`, CLI dispatches to bash scripts, templates use `[PLACEHOLDER]` syntax
5. Document: shellcheck must pass on all `.sh` files, bats tests required for new scripts
6. Keep it concise (under 80 lines)

**Files:** `CLAUDE.md` (new file in project root)

**Definition of done:**
- [ ] `CLAUDE.md` exists in project root with build/test/lint commands
- [ ] Covers project-specific conventions not in workspace CLAUDE.md
- [ ] Under 80 lines

---

## Blocked

### T-006: Publish npm package (issue #2)
**Priority:** medium

**Goal:** Publish the `aahp` CLI to the npm registry so users can `npx aahp init`.

**Context:**
- `package.json` fully prepared: `test` and `prepublishOnly` scripts configured
- `npm pack --dry-run` verified: 19 files, 26.5 kB tarball, correct contents
- Package name `aahp` confirmed available on npm
- All 48 bats tests pass
- GitHub Actions publish workflow added at `.github/workflows/publish.yml`
- **Blocked on human action:** npm auth token expired, interactive browser login required

**What to do (two options):**

Option A - CI publish (recommended):
1. Go to npmjs.com > Settings > Access Tokens > Generate New Token (type: Automation)
2. Add the token as a GitHub secret named `NPM_TOKEN` in the repo settings
3. Go to Actions > "Publish to npm" > Run workflow (optionally do a dry run first)
4. Verify with `npx aahp --version` from a clean directory

Option B - Local publish:
1. Run `npm login` in an interactive terminal (opens browser for auth)
2. Run `npm publish --access public` (prepublishOnly will run tests first)
3. Verify with `npx aahp --version` from a clean directory

**Files:** `package.json`, `bin/aahp.js`, `.github/workflows/publish.yml`

**Definition of done:**
- [ ] Package published to npm registry
- [ ] `npx aahp init` works from any directory

---

## Recently Completed

| ID | Item | Date |
|----|------|------|
| T-010 | Fix shellcheck warnings in CI | 2026-02-28 |
| T-009 | Add bats tests to CI pipeline | 2026-02-28 |
| T-008 | Add bats tests to CI pipeline (original) | 2026-02-27 |
| T-007 | Fix shellcheck warnings in CI | 2026-02-27 |
| T-005 | Add automated script tests (bats) | 2026-02-26 |

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
| Publish workflow | `.github/workflows/publish.yml` |
| Test suite | `tests/` |
| License | `LICENSE` (CC BY 4.0) |
| Own handoff files | `.ai/handoff/` |
