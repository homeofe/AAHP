# AAHP: Next Actions for Incoming Agent

> Priority order. Work top-down.
> Each item should be self-contained, the agent must be able to start without asking questions.
> Blocked tasks go to the bottom. Completed tasks move to "Recently Completed".

---

## Status Summary

| Status | Count |
|--------|-------|
| Done | 10 |
| Ready | 1 |
| Blocked | 0 |

---

## Ready - Work These Next

### T-011: Publish npm package
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

## Blocked

(No blocked tasks)

---

## Recently Completed

| ID | Item | Date |
|----|------|------|
| T-010 | Fix shellcheck warnings in CI | 2026-02-28 |
| T-009 | Add bats tests to CI pipeline | 2026-02-28 |
| T-008 | Add bats tests to CI pipeline (original) | 2026-02-27 |
| T-007 | Fix shellcheck warnings in CI | 2026-02-27 |
| T-006 | Publish npm package (preparation) | 2026-02-27 |

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
