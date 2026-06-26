# AAHP: Agent Journal

> **Append-only.** Never delete or edit past entries.
> Every agent session adds a new entry at the top.
> This file is the immutable history of decisions and work done.

---

## [2026-06-26] Codex: Gemini review fixes for AAHP PR #13

**Agent:** Codex
**Phase:** fix
**Branch:** codex/issue-21-pii-allowlist
**Tasks:** AAHP PR #13 review follow-up

### What was done

- Fixed `bin/aahp.js` top-of-file help syntax so the CLI no longer crashes on parse.
- Registered the `archive` command in CLI dispatch.
- Hardened the Node CLI wrapper on Windows to prefer Git Bash over the WSL `bash.exe` shim when available.
- Adjusted LOG archive rendering to preserve clean separators and newest-first archive order.
- Kept allowlist TSV stdout clean by separating validator stderr from successful parser output.

### Validation

- `node --check bin/aahp.js`
- `node bin/aahp.js --help`
- `bash scripts/aahp-archive.sh . --verify`
- `bash scripts/lint-handoff.sh .`
- `bash node_modules/bats/bin/bats tests/archive.bats tests/lint.bats tests/manifest.bats tests/verify.bats` (67 checks; 2 pre-existing manifest skips)
- `bash scripts/verify-handoff.sh . --level full`
- `git diff --check`

---

## [2026-06-26] Codex: LOG archive flow and reusable badge workflows

**Agent:** Codex
**Phase:** implementation
**Branch:** codex/issue-21-pii-allowlist
**Tasks:** AAHP issues #11 and #12

### What was done

- Added `aahp archive` with the canonical default flow: keep the 10 newest `LOG.md` entries and move entry 11+ to `LOG-ARCHIVE.md`.
- Added `aahp archive --verify` for CI and local checks.
- Added archive regression tests for rotation, missing rotation, verification, truncation detection, idempotency, and MANIFEST archive/index coverage.
- Added stable per-check workflows: AAHP Lint, Manifest, Archive, and PII Allowlist; AAHP Verify remains the umbrella gate.
- Documented reusable README badge snippets for downstream repos.

---

## [2026-06-26] Codex: Reviewed, expiring PII allowlist (issue #21)

**Agent:** Codex
**Phase:** implementation
**Branch:** codex/issue-21-pii-allowlist
**Task:** T-031

### What was done

- Added `pii-allowlist.json` schema, template, and cross-platform validator.
- Allowed only exact, non-expired email matches with a reason and accountable owner.
- Kept the optional allowlist in MANIFEST checksum coverage.
- Added regression tests for valid, expired, malformed, wildcard, and secret non-suppression cases.
- Documented rollout owners for the currently blocked consumer repositories.

### Security decision

An allowlist suppresses only the matching PII finding. Secret detection and every other AAHP verify layer remain non-bypassable.

---

## [2026-06-20] Claude Opus 4.8 (1M context): Canonical handoff gate (aahp verify)

**Agent:** Claude Opus 4.8 (1M context)
**Phase:** implementation
**Branch:** main
**Tasks:** T-018, T-019, T-020, T-021

### What was done

- Built `scripts/verify-handoff.sh` (`aahp verify`), the single canonical gate
  with 4 layers: MANIFEST checksum integrity (reuses lint-handoff.sh), the
  content-drift gate (code outside .ai/handoff/ requires STATUS.md plus a
  regenerated MANIFEST.json, else hard-fail), commit-pointer freshness, and
  TRUST-TTL expiry (advisory).
- Added helpers to `_aahp-lib.sh`: `aahp_manifest_field` (dotted JSON read via
  node or python), `aahp_trust_expired` (header-aware Markdown column parse for
  the Expires column), `aahp_python_cmd`.
- Registered the `verify` command in `bin/aahp.js` plus help text and examples.
- Wired hooks: `scripts/hooks/pre-commit` (fast: layers 1-2), `pre-push`
  (full: layers 1-4), and `scripts/install-hooks.sh` to install them
  (core.hooksPath aware; backs up non-AAHP hooks). Installed into AAHP itself.
- Added `.github/workflows/aahp-verify.yml` running `aahp verify --level ci` as
  the intended REQUIRED check. Committed despite Actions being OFF org-wide
  (cost sweep); a comment documents that it activates when Actions returns.
- Extended `ci.yml` shellcheck to cover the new scripts.
- Wrote `scripts/ROLLOUT.md` (10 active Elvatis repos, ordered) and a README 2.7
  section documenting the gate.
- Tests: `tests/verify.bats` (12, all pass) plus a verify help test in cli.bats.

### Decisions made

- Drift gate HARD-FAILS (exit 1), per the Folgeplanung point-3 default.
- TRUST-TTL stays advisory (warn), never blocks a commit on its own.
- Escape hatch `AAHP_SKIP_VERIFY=1` kept, honoured locally, ignored at
  `--level ci`, documented as "caught by the required CI check, do not use to
  bypass CI".
- MANIFEST regeneration stays a separate /handoff step; the gate is verify-only.
- TTL parsed from TRUST.md (Markdown), not restructured into MANIFEST.json, to
  avoid a schema change in this pass.

### Open items

- Propagate the gate to the ~9 remaining active repos in ROLLOUT.md (improvements
  done as the first target).
- Mark `aahp-verify` as a REQUIRED status check once Actions is re-enabled.

---

## [2026-02-27] Claude Opus 4.6: T-006 npm publish preparation

**Agent:** Claude Opus 4.6
**Phase:** fix
**Branch:** main
**Tasks:** T-006

### What was done

- Verified package name `aahp` is available on npm registry (404)
- Verified `npm pack --dry-run` produces correct tarball: 19 files, 26.2 kB, all expected contents
- Added `scripts.test` and `scripts.prepublishOnly` to `package.json` (test-before-publish)
- Ran all 48 bats tests - all passing
- Attempted `npm publish --access public` - blocked by npm authentication (ENEEDAUTH)
- Attempted `npm login` - requires interactive browser authentication
- Updated all handoff files to reflect current state

### Decisions made

- Added `prepublishOnly` script to prevent publishing with failing tests
- T-006 marked as blocked: package fully prepared, npm login requires human interaction
- Remaining steps for human: `npm login` then `npm publish --access public`

### Blockers

- npm authentication requires interactive browser login - cannot be completed by agent

---

## [2026-02-26] Claude Opus 4.6: Complete T-003, T-004, T-005 -CI, CLI, Tests

**Agent:** Claude Opus 4.6
**Phase:** 3 (Implementer)
**Branch:** main
**Tasks:** T-003, T-004, T-005

### What was done

- **T-003**: Created `.github/workflows/ci.yml` -GitHub Actions CI pipeline with shellcheck, lint-handoff.sh, and ajv schema validation
- **T-004**: Created `bin/aahp.js` + `package.json` -npx-distributable CLI with subcommands: init, manifest, lint, migrate. Pure Node.js, no dependencies. ESM module.
- **T-005**: Created 48 bats tests across 3 suites: `tests/manifest.bats` (18), `tests/lint.bats` (18), `tests/migrate.bats` (12). All passing. Cross-platform temp dir handling for Windows Git Bash.
- Fixed `lint-handoff.sh` Python detection: Windows `python3` Store alias passes `command -v` but doesn't work; now tries actual invocation before trusting
- Fixed Unicode encoding in Python checksum output (cp1252 on Windows)
- Updated README.md: title "AAHP v2 Proposal" → "AAHP: AI-to-AI Handoff Protocol (v2/v3)", version refs, agent names
- Added `bats` as devDependency for local test running
- Created `tests/run.sh` convenience runner
- Created `tests/test_helper.bash` shared test fixtures
- All 48 tests pass, CLI verified, lint passes

### Decisions made

- CLI uses ESM (`"type": "module"`) with zero external dependencies -only Node.js built-ins
- `aahp init` implemented in pure Node.js (file copy), other commands spawn bash scripts
- bats-core via npm (`npx bats`) rather than system install
- Tests create isolated temp fixtures -no dependency on project's own `.ai/handoff/`
- New follow-up tasks created: T-006 (npm publish), T-007 (shellcheck fixes), T-008 (bats in CI)

---

## [2026-02-26] Claude Opus 4.6: AAHP v3 -Task IDs & Dependency Graphs

**Agent:** Claude Opus 4.6
**Phase:** 3 (Implementer)
**Branch:** main
**Tasks:** T-001, T-002

### What was done

- Extended `schema/aahp-manifest.schema.json` with optional `tasks` and `next_task_id` fields
- Defined task ID format: `T-001`, `T-002`, etc. (stable, never reused, zero-padded)
- Added dependency graph structure to MANIFEST.json (`depends_on` array per task)
- Updated `templates/MANIFEST.json` with example task entries
- Updated `templates/NEXT_ACTIONS.md` with `T-xxx:` heading format
- Updated `templates/DASHBOARD.md` with `ID` column in tasks table
- Updated `scripts/aahp-manifest.sh` to preserve `tasks` and `next_task_id` on regeneration (uses Node.js for JSON parsing)
- Added README.md Section 8: full v3 specification (task IDs, schema, agent algorithm, backward compat)
- Dogfooded v3 on AAHP's own `.ai/handoff/` files with 5 tasks (T-001 through T-005)

### Decisions made

- Task IDs use `T-xxx` format (short, readable, sortable) over `AAHP-xxx` (too project-specific)
- Dependency graph lives in MANIFEST.json (structured data) not in Markdown (human text)
- `tasks` and `next_task_id` are optional -v2 projects continue to work without them
- `aahp-manifest.sh` preserves task data using Node.js JSON parsing (available on most systems)
- `aahp_version` bumped to `"3.0"` in generated manifests

---

## [2026-02-26] Claude Opus 4.6: Resolve Open Questions & Dogfood Protocol

**Agent:** Claude Opus 4.6
**Phase:** 3 (Implementer)
**Branch:** main

### What was done

- Resolved all 4 open questions from README.md Section 7
- Created `scripts/_aahp-lib.sh` (shared function library with portable SHA-256, mtime, token estimation)
- Created `scripts/aahp-manifest.sh` (standalone manifest generator with --agent, --phase, --context CLI options)
- Refactored `scripts/aahp-migrate-v2.sh` to source shared lib and delegate manifest generation
- Extended `scripts/lint-handoff.sh` with Check 6: parallel agent detection across git branches
- Replaced README.md Section 7 "Open Questions" with "Resolved Decisions"
- Bootstrapped `.ai/handoff/` for the AAHP project itself (dogfooding)

### Decisions made

- Q1: MANIFEST.json is auto-generated by outgoing agent + CLI tool
- Q2: Whole-file SHA-256 checksums (already implemented, doc-only update)
- Q3: Branch-based isolation for parallel agents, advisory lint warning
- Q4: Dependency graphs deferred to v3
- Extracted shared functions into `_aahp-lib.sh` instead of duplicating between scripts
- Used standalone `aahp-manifest.sh` rather than a unified `aahp.sh` CLI (keeps toolbox pattern)

---

## [2026-02-26] Claude Opus 4.6: Merge v2 Proposal into README

**Agent:** Claude Opus 4.6
**Phase:** 3 (Implementer)
**Branch:** main

### What was done

- Deleted `AAHP-v2-PROPOSAL.md` (content was identical to README.md)
- Updated `scripts/aahp-migrate-v2.sh` references from `AAHP-v2-PROPOSAL.md` to `README.md`
- Committed and pushed to GitHub (commit 672be62)

### Decisions made

- Single source of truth: README.md is the v2 specification document

---

## [2026-02-26] Previous: AAHP v2 Tooling Implementation

**Agent:** (prior session)
**Phase:** 3 (Implementer)
**Branch:** main

### What was done

- Created all 10 template files in `templates/`
- Created `scripts/aahp-migrate-v2.sh` (v1 to v2 migration)
- Created `scripts/lint-handoff.sh` (5 validation checks)
- Created `schema/aahp-manifest.schema.json` (JSON Schema Draft 2020-12)
- Created `AAHP-v2-PROPOSAL.md` with full v2 specification
- Set up LICENSE (now CC BY 4.0, originally MIT), .gitignore

### Decisions made

- Bash-only tooling (no Node.js/Python dependency for core scripts)
- JSON Schema Draft 2020-12 for manifest validation
- Pre-commit hook pattern for safety linting
