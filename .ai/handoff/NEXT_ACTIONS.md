# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## T-006: Publish npm package (BLOCKED - needs npm login)

**Goal:** Publish the `aahp` CLI to the npm registry so users can `npx aahp init`.

**Context:**
- `package.json` fully prepared: `test` and `prepublishOnly` scripts added
- `npm pack --dry-run` verified: 19 files, 26.2 kB tarball, correct contents
- Package name `aahp` confirmed available on npm (404 on registry)
- All 48 bats tests pass
- **Blocked:** npm requires interactive browser authentication (`npm login`)

**What remains (manual steps):**
1. Run `npm login` in an interactive terminal (opens browser for auth)
2. Run `npm publish --access public` (prepublishOnly will run tests first)
3. Test with `npx aahp --version` from a clean directory

**Definition of done:**
- [ ] Package published to npm
- [ ] `npx aahp init` works from any directory

---

## T-007: Fix shellcheck warnings in CI

**Goal:** Ensure all scripts pass shellcheck when CI runs.

**Context:**
- CI workflow (`.github/workflows/ci.yml`) runs shellcheck on all 4 scripts
- Scripts have not been validated with shellcheck locally
- Common issues: unquoted variables, unused vars, non-portable constructs

**What to do:**
1. Run `shellcheck scripts/*.sh` locally
2. Fix all warnings (SC2034, SC2086, etc.)
3. Verify CI passes after fixes

**Definition of done:**
- [ ] All scripts pass shellcheck
- [ ] CI pipeline is green

---

## T-008: Add bats tests to CI pipeline

**Goal:** Run the 48 bats tests as part of CI.

**Context:**
- Tests exist in `tests/` (manifest.bats, lint.bats, migrate.bats)
- CI workflow currently runs shellcheck + lint + schema validation
- Tests need `bats` installed (available via npm: `npx bats`)

**What to do:**
1. Add a step to `.github/workflows/ci.yml` to install and run bats tests
2. Verify tests pass in Ubuntu CI environment

**Definition of done:**
- [ ] Bats tests run in CI
- [ ] All 48 tests pass

---

## Recently Completed

| ID | Item | Resolution |
|----|------|-----------|
| T-003 | Add GitHub Actions CI pipeline | `.github/workflows/ci.yml` with shellcheck, lint, schema validation |
| T-004 | Create npx-distributable CLI | `bin/aahp.js` + `package.json` -init, manifest, lint, migrate subcommands |
| T-005 | Add automated script tests (bats) | 48 tests: 18 lint + 18 manifest + 12 migrate, all passing |
| T-001 | Design v3 task dependency graph schema | Schema extended, README Section 8 added |
| T-002 | Add task IDs to templates | T-xxx format in NEXT_ACTIONS.md headings and DASHBOARD.md tables |
| - | Update README for v3 | Title, version refs, agent names, section headers updated |
| - | Fix cross-platform issues | Python detection (Windows Store alias), Unicode encoding (cp1252) |

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
| Test suite | `tests/` |
| License | `LICENSE` (CC BY 4.0) |
| Own handoff files | `.ai/handoff/` |
