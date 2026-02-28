# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 9 |
| Ready | 2 |
| Blocked | 0 |

---

## Ready - Work These Next

### T-010: T-007: Fix shellcheck warnings in CI
**Priority:** high

**Goal:** Ensure all scripts pass shellcheck when CI runs.

**Context:**
- CI workflow (`.github/workflows/ci.yml`) runs shellcheck on all scripts
- Common issues: unquoted variables, unused vars, non-portable constructs

**What to do:**
1. Run `shellcheck scripts/*.sh scripts/_aahp-lib.sh tests/run.sh tests/test_helper.bash` locally
2. Fix all warnings (SC2034, SC2086, etc.)
3. Verify CI passes after fixes

**Files:** `scripts/*.sh`, `scripts/_aahp-lib.sh`, `tests/run.sh`, `tests/test_helper.bash`

**Definition of done:**
- [ ] All scripts pass shellcheck with no warnings
- [ ] CI pipeline is green

---

### T-011: T-006: Publish npm package
**Priority:** medium

**Goal:** Publish the `aahp` CLI to the npm registry so users can `npx aahp init`.

**Context:**
- `package.json` fully prepared: `test` and `prepublishOnly` scripts added
- `npm pack --dry-run` verified: 19 files, 26.2 kB tarball, correct contents
- Package name `aahp` confirmed available on npm
- All 48 bats tests pass
- **Blocked on human action:** npm requires interactive browser authentication (`npm login`)

**What to do:**
1. Run `npm login` in an interactive terminal (opens browser for auth)
2. Run `npm publish --access public` (prepublishOnly will run tests first)
3. Test with `npx aahp --version` from a clean directory

**Files:** `package.json`, `bin/aahp.js`

**Definition of done:**
- [ ] Package published to npm
- [ ] `npx aahp init` works from any directory

---

## Blocked

(No blocked tasks)

---

## Recently Completed

| ID | Item | Date |
|----|------|------|
| T-009 | Add bats tests to CI pipeline | 2026-02-28 |
| T-008 | Add bats tests to CI pipeline (original) | 2026-02-27 |
| T-007 | Fix shellcheck warnings in CI | 2026-02-27 |
| T-006 | Publish npm package (preparation) | 2026-02-27 |
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
| Test suite | `tests/` |
| License | `LICENSE` (CC BY 4.0) |
| Own handoff files | `.ai/handoff/` |
