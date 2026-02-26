# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## T-003: Add GitHub Actions CI Pipeline

**Goal:** Automate validation of AAHP handoff files on every push.

**Context:**
- lint-handoff.sh exists but is only run manually
- Schema validation requires ajv (npm) or Python jsonschema
- No CI pipeline exists yet

**What to do:**
1. Create `.github/workflows/lint.yml`
2. Run `lint-handoff.sh` on the project's own `.ai/handoff/`
3. Validate `schema/aahp-manifest.schema.json` with ajv
4. Run shellcheck on all scripts

**Files:**
- `.github/workflows/lint.yml`: new CI workflow
- `scripts/`: all scripts validated by shellcheck

**Definition of done:**
- [ ] GitHub Actions workflow passes
- [ ] All scripts pass shellcheck
- [ ] Schema validation runs in CI

---

## T-004: Create npx-distributable CLI

**Goal:** Allow users to run `npx aahp init`, `npx aahp manifest`, `npx aahp lint` from any project.

**Context:**
- Currently scripts must be copied or the AAHP repo cloned
- npm distribution would make adoption easier
- Thin wrapper around existing bash scripts

**What to do:**
1. Create `package.json` with bin entries
2. Create `bin/aahp.js` dispatcher
3. Wrap existing bash scripts as subcommands: init, manifest, migrate, lint
4. Publish to npm as `@aahp/cli` or `aahp`

**Files:**
- `package.json`: new
- `bin/aahp.js`: new CLI entry point

**Definition of done:**
- [ ] `npx aahp init` copies templates to `.ai/handoff/`
- [ ] `npx aahp manifest` generates MANIFEST.json
- [ ] `npx aahp lint` runs validation

---

## T-005: Add Automated Script Tests

**Goal:** Create a test harness for all bash scripts to prevent regressions.

**Context:**
- Scripts are tested manually but have no automated test suite
- Edge cases (missing files, corrupted JSON, macOS vs Linux) untested
- Could use bats (Bash Automated Testing System) or simple bash assertions

**What to do:**
1. Install or vendor bats-core
2. Write tests for aahp-manifest.sh (valid output, missing dir, custom flags, task preservation)
3. Write tests for lint-handoff.sh (injection detection, secret detection, checksum validation)
4. Write tests for aahp-migrate-v2.sh (v1 to v2 migration)
5. Add test runner to CI pipeline

**Files:**
- `tests/`: new test directory
- `tests/manifest.bats`: manifest generator tests
- `tests/lint.bats`: lint script tests
- `tests/migrate.bats`: migration script tests

**Definition of done:**
- [ ] All scripts have test coverage
- [ ] Tests run in CI

---

## Recently Completed

| ID | Item | Resolution |
|----|------|-----------|
| T-001 | Design v3 task dependency graph schema | Schema extended, README Section 8 added, manifest generator updated |
| T-002 | Add task IDs to templates | T-xxx format in NEXT_ACTIONS.md headings and DASHBOARD.md tables |
| - | Resolve open questions 1-4 | Implemented aahp-manifest.sh, lint Check 6, documented decisions |
| - | Merge AAHP-v2-PROPOSAL.md | Merged into README.md, deleted duplicate |
| - | Dogfood AAHP protocol | Implemented .ai/handoff/ for the AAHP project itself |

---

## Reference: Key File Locations

| What | Where |
|------|-------|
| v2/v3 Specification | `README.md` |
| Templates | `templates/` |
| Scripts | `scripts/` |
| JSON Schema | `schema/aahp-manifest.schema.json` |
| License | `LICENSE` (MIT) |
| Own handoff files | `.ai/handoff/` |
