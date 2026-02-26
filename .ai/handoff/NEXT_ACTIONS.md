# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## 1. Design v3 Task Dependency Graph Schema

**Goal:** Extend the MANIFEST.json schema to support task dependency graphs for autonomous parallel task selection.

**Context:**
- v2 resolved this as "deferred to v3" (README.md section 7.4)
- Current task model: ordered list in NEXT_ACTIONS.md, dashboard in DASHBOARD.md
- v3 should allow agents to identify parallelizable tasks automatically

**What to do:**
1. Design a `task_dependencies` field for MANIFEST.json mapping task IDs to prerequisites
2. Update `schema/aahp-manifest.schema.json` with the new optional field
3. Create a template example showing task dependencies
4. Update README.md with v3 dependency graph specification

**Files:**
- `schema/aahp-manifest.schema.json`: extend with task_dependencies
- `templates/MANIFEST.json`: add example dependency field
- `README.md`: add v3 section

**Definition of done:**
- [ ] Schema extended with optional task_dependencies field
- [ ] Template updated with example
- [ ] README documents the feature

---

## 2. Add Task IDs to NEXT_ACTIONS.md and DASHBOARD.md

**Goal:** Give each task a stable identifier so dependency graphs can reference them.

**Context:**
- Tasks are currently identified by position (1, 2, 3...) which changes as tasks complete
- Stable IDs needed for dependency graph references
- Format suggestion: `AAHP-001`, `AAHP-002`, etc. or short slugs

**What to do:**
1. Define a task ID format in CONVENTIONS.md
2. Update NEXT_ACTIONS.md template with ID column
3. Update DASHBOARD.md template with ID column
4. Update aahp-manifest.sh to auto-assign IDs if missing

**Files:**
- `templates/NEXT_ACTIONS.md`: add ID field
- `templates/DASHBOARD.md`: add ID column
- `templates/CONVENTIONS.md`: document ID format

**Definition of done:**
- [ ] Task ID format defined
- [ ] Templates updated
- [ ] Manifest generator handles IDs

---

## 3. Add GitHub Actions CI Pipeline

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

## 4. Create npx-distributable CLI

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

## 5. Add Automated Script Tests

**Goal:** Create a test harness for all bash scripts to prevent regressions.

**Context:**
- Scripts are tested manually but have no automated test suite
- Edge cases (missing files, corrupted JSON, macOS vs Linux) untested
- Could use bats (Bash Automated Testing System) or simple bash assertions

**What to do:**
1. Install or vendor bats-core
2. Write tests for aahp-manifest.sh (valid output, missing dir, custom flags)
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

| Item | Resolution |
|------|-----------|
| Resolve open questions 1-4 | Implemented aahp-manifest.sh, updated lint with Check 6, documented decisions |
| Merge AAHP-v2-PROPOSAL.md | Merged into README.md, deleted duplicate, updated script references |
| Dogfood AAHP protocol | Implemented .ai/handoff/ for the AAHP project itself |

---

## Reference: Key File Locations

| What | Where |
|------|-------|
| v2 Specification | `README.md` |
| Templates | `templates/` |
| Scripts | `scripts/` |
| JSON Schema | `schema/aahp-manifest.schema.json` |
| License | `LICENSE` (MIT) |
| Own handoff files | `.ai/handoff/` |
