# AAHP: Agent Journal

> **Append-only.** Never delete or edit past entries.
> Every agent session adds a new entry at the top.
> This file is the immutable history of decisions and work done.

---

## [2026-07-25] claude-opus-5: Trust register re-verification (10 rows re-established, 0 downgraded)

**Agent:** claude-opus-5
**Phase:** review
**Branch:** chore/trust-reverification
**Tasks:** TRUST.md re-verification sweep

### What was done

- Layer 4 was reporting 3 expired `verified` rows: escape hatch ignored at level ci (expired 2026-07-20), checksums match file contents (expired 2026-07-21), LICENSE matches declared license (expired 2026-07-20). A further 7 `verified` rows carried Expires 2026-07-25 and would have raised the same warning the next morning, so all 10 were handled in one sweep. Each was re-established by running something, not re-stamped, and every Notes cell now records the anchor that backs it.
- Suites backing the rows, every count taken from a run in this session: manifest.bats 19/19, migrate.bats 12/12, lint.bats 31 ok / 0 fail (1 pre-existing skip covering a grep leading-dash limitation), verify.bats 13/13, gates.bats 22/22, doctor.bats 15/15. `npm run check` passed all 8 gates; `aahp doctor .` passed its 6 gates with pinned-dep reported as `self`.
- Honest note on the full-suite run: `npm test` over all 222 tests was started and reached test 169 with only 3 failures, all of them the known cli.bats cases that fail on a Windows-style shell and pass on Linux CI (version capture, read-only-directory permissions, and a path-separator assumption in `aahp status`). The run was cut short by a runner time limit, not by a test failure, so the suites it had not yet reached were run separately to completion. None of the 3 known failures touches any row in this register. Whole-suite green remains CI's call, which is the correct division of labour.
- The content-drift and escape-hatch rows were re-established behaviourally rather than by reading the source. A throwaway repository was driven into the drift state (a source file committed with no handoff update). Verify hard-failed Layer 2 and exited 1. With AAHP_SKIP_VERIFY=1 the same repository exited 0 at `--level prepush` (hatch honoured, verification skipped entirely) and exited 1 at `--level ci` (hatch ignored, Layer 2 still failing). Those two different outcomes are exactly what the row asserts.
- Checksums were recomputed independently of the lint script across all 11 indexed handoff files (0 mismatches), then confirmed again through lint-handoff.sh and verify Layer 1. A negative control (one appended line in a copied STATUS.md) made Layer 1 fail with the expected mismatch, which shows the detector is live rather than passing vacuously. Worth knowing for future readers: lint-handoff.sh prints a checksum mismatch but does not raise its own exit code for it, so verify Layer 1 (which greps the lint output) is the layer that actually blocks.
- LICENSE was re-read against package.json and README: Apache-2.0 in the LICENSE body and its copyright line, in the package.json license field, and in both the README badge and the License section, with no competing license string in tracked sources.
- Two stale test counts that had been carried forward were corrected in the register and in STATUS.md Build Health: gates.bats is 22 tests (recorded as 20) and doctor.bats is 15 (recorded as 10). The suites grew and the notes did not follow, which is the same drift the register exists to catch.

### Decisions

- No row was downgraded, so no downgrade explanation is owed here. Every one of the 10 rows reached a real external anchor in this session.
- TTL values were deliberately left unchanged. Recomputing Expires from an unchanged TTL is re-verification; lengthening a TTL because the warning is tiresome would be gaming the gate. The structural problem is real and is being raised for the maintainer instead of patched silently: six script rows on a 7-day TTL guarantee a Layer 4 warning every week, which is exactly the cadence that teaches readers to skim past it. Note also that this register's own policy puts script and checksum rows at a 1 to 3 day TTL, so the current 7-day values are already looser than the stated rule. Both halves of that tension belong to the maintainer, not to a passing agent.
- Package version deliberately not bumped. This change touches only the handoff register, its log, and the status file.

---

## [2026-07-18] claude-opus-4-8: Anti-entropy initiative (gates + constitution + ADR log, v3.7.0)

**Agent:** claude-opus-4-8
**Phase:** implementation
**Branch:** feat/anti-entropy
**Tasks:** anti-entropy strategy (steps 3-6)

### What was done

- Added 3 config-driven enforcement gates (no-op without config), wired into `npm run check`: check-forbidden-patterns.mjs (regex denylist over `git ls-files`; AAHP bans em dashes), check-schema-doc-sync.mjs (extract-and-compare value-sets across sources; AAHP pins the task-status + phase enums), check-doc-links.mjs (internal markdown file-link resolver). Config keys forbiddenPatterns/docSync/docLinks in the schema + example. 9 bats tests.
- Added CONSTITUTION.md (12 non-negotiable invariants, each already enforced), linked from README + CLAUDE.md and tied into the doc-links + forbidden-patterns gates.
- Reframed README Section 7 as an Architectural Decision Log (10 ADRs with stable anchors + the LOG-to-ADR promotion rule).
- Free win: ci.yml shellcheck globs `git ls-files` (auto-covers new scripts). De-dup: removed the rotted German runbook from the CONVENTIONS template + dogfood; collapsed the duplicate Three Laws.

### Decisions

- Per the strategy, deliberately did NOT build a separate governance system/command, a docs/adr/ directory (README Section 7 IS the log), any per-PR LLM gate, or the swarm self-governance runtime. Gates extend the existing deterministic machinery.
- Deferred AAHP's own `claims` config (prose capability numbers are false-positive-prone) and aggressive README/CLAUDE de-dup (kept operational how-to; the constitution is the invariant index).

---

## [2026-07-18] claude-opus-4-8: Security hardening + doc-drift fixes (v3.6.1)

**Agent:** claude-opus-4-8
**Phase:** fix
**Branch:** fix/floorcmd-security-and-drift
**Tasks:** anti-entropy audit follow-up (security + live drift bugs)

### What was done

- SECURITY: `check-claims.mjs` `floorCmd` now runs a repo-relative Node script via `execFileSync` (no shell), replacing `execSync` on an arbitrary config string. Closes a command-injection path from a PR-editable `aahp.config.json`. Schema + example updated; a path escaping the project root is rejected. New bats path-escape-rejection test.
- Fixed live documentation drift found by the anti-entropy audit: README Section 4 canonical handoff-file list, Section 7.1 command table (+`doctor`), Section 8.3 task-status enum (+`cancelled`), removed the phantom `stale` bucket from `aahp status` (never in the schema), and stripped em dashes (U+2014) from the CONVENTIONS templates and CLAUDE.md.

### Decisions

- Scoped to the security fix + the four live drift bugs only. Deferred the broader anti-entropy strategy (constitution, ADR-log reframing, new deterministic gates, de-duplicating the 5x provenance scale, excising the rotted German runbook) to a separate initiative for maintainer review.

---

## [2026-07-18] claude-opus-4-8: Upstreaming release (aahp doctor + config-driven gates, v3.6.0)

**Agent:** claude-opus-4-8
**Phase:** implementation
**Branch:** feat/aahp-doctor-and-gates
**Tasks:** AAHP upstreaming spec (aahp doctor + generic gates)

### What was done

- Added `aahp doctor`: a Node-native conformance self-check emitting a schemaVersion:1 JSON record across six gates (handoff-set, manifest-schema, grounding, pinned-dep, changelog-format, version-sync). Self-aware pinned-dep (returns `self` on this repo).
- Added four config-driven release gates that ship in the package and run against any consumer via an optional `aahp.config.json`: check-version-sync, check-changelog, check-changelog-format, check-claims, plus the aahp-dashboard.mjs LOG-from-CHANGELOG generator and NEXT_ACTIONS current-version freshness gate. Every gate is a clean no-op when its config section is absent.
- Extracted changelog-grammar.mjs as the single release-heading grammar imported by both the format validator and the LOG generator, so they cannot diverge (the divergence the upstreaming spec called out).
- Wired gates + doctor into ci.yml, aahp-verify.yml, the pre-push hook, and npm scripts; added schema/aahp-config.schema.json, aahp.config.example.json, README 2.11 + Section 11.

### Decisions

- Verified npm latest was 3.5.0 (local checkout was 13 commits stale); reconciled onto origin/main and bumped 3.5.0 -> 3.6.0. An early 3.4.0 target would have collided with a published version.
- REJECTED the SCG lint-handoff relative PII-path change: it is a Windows regression here (breaks lint.bats 20-24) and main correctly uses the absolute path. The Layer 3 warn fix was already merged on main (#27).
- Kept AAHP's LOG.md as an append-only agent journal (did NOT point the LOG generator at it); the generator ships as an opt-in consumer capability.

---

## [2026-06-26] Codex: Fix manifest badge schema for AAHP JSON files

**Agent:** Codex
**Phase:** fix
**Branch:** codex/issue-21-pii-allowlist
**Tasks:** AAHP PR #13 merge blocker

### What was done

- Fixed `schema/aahp-manifest.schema.json` so MANIFEST file entries can include AAHP-owned JSON handoff files.
- Allowed `pii-allowlist.json` and `LOG-ARCHIVE.index.json` while keeping unknown JSON files rejected.
- Reproduced the GitHub Actions `AAHP Manifest` validation locally with `ajv-cli` and confirmed `.ai/handoff/MANIFEST.json valid`.

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
- `bash node_modules/bats/bin/bats tests/archive.bats tests/lint.bats tests/manifest.bats tests/verify.bats` (68 checks; 2 pre-existing manifest skips)
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
- Wrote `scripts/ROLLOUT.md` (role-based consumer waves, ordered) and a README
  2.7 section documenting the gate.
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

- Propagate the gate to the remaining consumer waves in ROLLOUT.md (the wave-1
  seeding framework is done as the first target).
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
