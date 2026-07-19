# Changelog

All notable changes to `@elvatis_com/aahp` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses semantic
versioning (`aahp_version` in `MANIFEST.json` tracks the file-format contract and moves
independently of the npm version).

> Publishing note: npm releases lapsed after `3.2.1` because the CI publish workflow was
> disabled, so `3.3.0` and `3.4.0` were developed in the repository but never published.
> `3.5.0` is the first npm release since `3.2.1` and ships everything below it.

## [Unreleased]

## [3.8.1] - 2026-07-19

### Fixed
- `scripts/aahp-manifest.sh` now passes the manifest path to its Node helpers as an
  argument (`process.argv[1]`) instead of interpolating `$HANDOFF_DIR` into the inline
  script. On Windows and MSYS checkouts the interpolated path was not readable by native
  Node, so the preservation helpers failed silently and `tasks`, `next_task_id`, and
  `cross_repo_ref` were dropped from MANIFEST.json on regeneration. Linux and CI were
  unaffected. Regeneration now preserves those optional fields on every platform.
## [3.8.0] - 2026-07-18
**Portable Governance: one aggregate governance gate, a governance-only conformance record, and a drop-in CI workflow**

### Added
- `aahp check [path]`: a consumer-facing governance aggregator that runs the
  config-driven gates (changelog, changelog-format, version-sync, claims,
  forbidden-patterns, schema-doc-sync, doc-links, handoff) as one run. Each gate reports
  pass, fail, or skip, and the exit code is 0 only when no gate fails (a skipped gate
  never fails). `--json` emits a `schemaVersion: 1` record; `--quiet` prints only
  failures; `config.check.only` / `config.check.skip` select which gates run.
- `aahp doctor --governance` (alias `--no-handoff`): a governance-only conformance record
  that forces the three handoff gates to `skip` without evaluating them, so a repo with no
  `.ai/handoff/` can still emit a green record. The default mode is unchanged and
  byte-identical to prior versions.
- `aahp init --gates`: scaffolds governance-only config without creating `.ai/handoff/`
  (writes `aahp.config.json`, adds a `govern` script to an existing `package.json`, and
  writes `.github/workflows/aahp-govern.yml`).
- An opt-in, config-driven pinned-dep gate for `aahp doctor`: `pinnedDep`
  (`name` / `location` / `allowRange`) asserts the distribution pin. Absent config reports
  `skip`; the defaults reproduce the prior exact-pin behavior; a repo whose own package
  name matches reports `self`.
- `assets/governance/aahp-govern.yml`: a portable, opt-in, verify-only governance workflow
  that invokes `aahp check` and `aahp doctor --governance` through the pinned
  devDependency via `npx --no-install` (no vendored script paths).
- New `check` (`only` / `skip`) and `pinnedDep` (`name` / `location` / `allowRange`) keys
  in `schema/aahp-config.schema.json` and `aahp.config.example.json`.
- README: ADR-011 through ADR-016 in Section 7, plus `aahp check` and
  `aahp doctor --governance` coverage in Sections 2.11 and 9.2.

### Changed
- Git hooks are de-vendored: they resolve `scripts/verify-handoff.sh` when it is vendored,
  else the installed `aahp` CLI via `npx --no-install`, and skip when neither resolves. The
  required CI check remains the non-bypassable authority.
- The enumerating governance gates (`check-forbidden-patterns.mjs`, `check-doc-links.mjs`)
  fail loud outside a git work tree instead of silently scanning zero files: file
  enumeration goes through a shared `git ls-files` helper that throws when the project root
  is not a git checkout.

## [3.7.0] - 2026-07-18
**Anti-entropy: enforcement gates, a constitution, and an ADR log**

### Added
- Three config-driven enforcement gates (a clean no-op without config), folded into
  `npm run check`: `check-forbidden-patterns.mjs` (bans configured regexes such as em
  dashes or model names in tracked files), `check-schema-doc-sync.mjs` (asserts an
  extracted value-set is identical across sources, e.g. an enum in the schema vs its
  doc copies), and `check-doc-links.mjs` (resolves internal Markdown file links). Their
  config keys (`forbiddenPatterns`, `docSync`, `docLinks`) are documented in
  `schema/aahp-config.schema.json` and `aahp.config.example.json`.
- `CONSTITUTION.md`: a short, stable index of the project's non-negotiable invariants
  (each already enforced by a gate, test, or CI), linked from the README and CLAUDE.md.
- README Section 7 reframed as an Architectural Decision Log: 10 ADRs with stable
  `ADR-NNN` anchors and a LOG-to-ADR promotion rule.

### Changed
- The ci.yml ShellCheck step uses a `git ls-files` glob instead of a hand-maintained
  list, so new scripts are covered automatically (`scripts/propagate.sh` had been
  missed).
- Removed the stale German release runbook from the CONVENTIONS template and the
  dogfood, and collapsed the duplicated Three Laws motto to a single home (README).

## [3.6.1] - 2026-07-18
**Security: harden the claims floorCmd; fix shipped documentation drift**

### Security
- `check-claims.mjs` now runs `floorCmd` as a repo-relative Node script via
  `execFileSync` (no shell), instead of `execSync` on an arbitrary config string.
  This closes a command-injection path from a PR-editable `aahp.config.json`
  (a contributor could otherwise gain code execution in a consumer's CI). The
  schema and example are updated to match; a path escaping the project is rejected,
  including Windows cross-drive and absolute paths.
- Hardened `aahp status`: the task-status counter uses a null-prototype object so a
  crafted status like `toString` cannot match via the prototype chain.

### Fixed
- Documentation drift: README Section 4 now lists the full canonical handoff set
  (adds `GROUNDING.md`, `pii-allowlist.json`, `LOG-ARCHIVE.index.json`); the
  Section 7.1 command table adds `aahp doctor`; the Section 8.3 task-status enum
  adds `cancelled`; and the phantom `stale` bucket (never in the schema) is
  removed from `aahp status`.
- Removed em dashes (U+2014) from the CONVENTIONS templates and CLAUDE.md.

## [3.6.0] - 2026-07-18

### Added
- `aahp doctor`: a conformance self-check that emits a machine-readable JSON record
  (`schemaVersion: 1`) covering the handoff file set, MANIFEST schema conformance,
  GROUNDING/TRUST provenance, an exact-version dependency pin, changelog format, and
  version sync. `--json` prints the record to stdout.
- Config-driven release gates that ship in the package and run against any consumer
  project via `aahp.config.json`: `check-version-sync.mjs`, `check-changelog.mjs`,
  `check-changelog-format.mjs`, and `check-claims.mjs`. Each is a no-op until a repo opts
  in, so projects without config keep working.
- A single shared changelog grammar (`changelog-grammar.mjs`) imported by both the format
  validator and the optional LOG release-journal generator (`aahp-dashboard.mjs`), so the
  two cannot diverge.
- `schema/aahp-config.schema.json` and `aahp.config.example.json` documenting the config
  shape (`versionSites`, `claims`, `generate`), plus a `NEXT_ACTIONS.md` current-version
  freshness gate.
- README Section 2.11 (conformance and the config-driven gates) and a documented release
  ceremony. A `Provenance` column was adopted in the dogfooded `.ai/handoff/TRUST.md`.

### Changed
- `check-changelog-format.mjs` enforces the Keep a Changelog grammar (R1-R8, with
  `## [Unreleased]` optional); this CHANGELOG was normalized to conform (gave `3.1.0` a
  full ISO date and collapsed the `3.0.1-3.0.5` range into a single dated entry).

## [3.5.0] - 2026-07-14

### Added
- `documentation` pipeline phase, accepted by `aahp manifest --phase documentation`, the
  schema `last_session.phase` enum, the manifest generator, and the CLI help.
- This CHANGELOG. The GitHub release job references it.

### Fixed
- `aahp-manifest.sh` now preserves the optional `cross_repo_ref` field across
  regeneration (previously it was dropped), the same way it preserves `project`,
  `tasks`, and `next_task_id`.

## [3.4.0] - 2026-07-14

### Added
- README Section 9, Consuming Harness Integration: the harness-vs-AAHP boundary and
  decision matrix, a reference Claude Code `.claude/` layout, the minimal harness
  bootstrap, and grounding-audit integration.
- README Section 10, Multi-Repo and Cross-Repo Handoff, including the optional additive
  `cross_repo_ref` MANIFEST field (`repo` / `commit` / `handoff_file` / `relation`) and
  its schema entry, plus monorepo and version-skew doctrine.
- `aahp status` command documentation and an eight-command CLI reference table (7.1).
- A condensed inline Grounding reference in Section 2.10 (task-type anchor matrix,
  confidence bands, minimum TRUST fields).

## [3.3.0] - 2026-07-13

### Added
- Grounded Reflection Layer (Draft v0.1, README Section 2.10): an orthogonal provenance
  axis (`model_claim` to `human_confirmed`) recorded as a TRUST.md column, a
  `templates/GROUNDING.md` task-type anchor matrix scaffolded by `aahp init`, an optional
  pre-handoff Phase 4.5 grounding audit, and the `aahp migrate-grounding` verb. Additive
  and backward compatible: no MANIFEST field or schema change.

## [3.2.1] - 2026-06-26

### Fixed
- Follow-up fixes to the LOG archive flow and the verify gate. Last version published to
  npm before the 3.5.0 catch-up release.

## [3.2.0] - 2026-06-26

### Added
- Canonical LOG archive flow: `LOG.md` keeps the 10 newest entries and older entries
  rotate into `LOG-ARCHIVE.md`; `LOG-ARCHIVE.index.json` records archived-entry hashes so
  `aahp archive --verify` detects truncation or tampering. Reusable per-check badge
  workflows were split out for downstream repos.

## [3.1.0] - 2026-06-26

### Added
- Reviewed, exact-value, expiring PII email allowlist (`pii-allowlist.json`),
  MANIFEST-indexed so it cannot suppress secrets. Shipped to npm as part of the 3.2.0
  release.

## [3.0.5] - 2026-06-20

### Added
- AAHP v3 (v3.0.1 through v3.0.5): stable task IDs (`T-001` and up), a machine-readable
  dependency graph in `MANIFEST.json`, the `aahp` CLI, the verify gate (`aahp verify`),
  checksum integrity, the prompt-injection and secrets/PII firewalls, and OIDC trusted
  publishing to npm.

### Changed
- Relicensed to Apache-2.0 (earlier commits carried MIT, then CC BY 4.0, headers).

[Unreleased]: https://github.com/homeofe/AAHP/compare/v3.8.1...HEAD
[3.8.1]: https://github.com/homeofe/AAHP/compare/v3.8.0...v3.8.1
[3.8.0]: https://github.com/homeofe/AAHP/compare/v3.7.0...v3.8.0
[3.7.0]: https://github.com/homeofe/AAHP/compare/v3.6.1...v3.7.0
[3.6.1]: https://github.com/homeofe/AAHP/compare/v3.6.0...v3.6.1
[3.6.0]: https://github.com/homeofe/AAHP/compare/v3.5.0...v3.6.0
[3.5.0]: https://github.com/homeofe/AAHP/releases/tag/v3.5.0
[3.4.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.4.0
[3.3.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.3.0
[3.2.1]: https://github.com/homeofe/AAHP/releases/tag/v3.2.1
[3.2.0]: https://github.com/homeofe/AAHP/releases/tag/v3.2.0
[3.1.0]: https://github.com/homeofe/AAHP/compare/v3.0.5...v3.1.0
[3.0.5]: https://github.com/homeofe/AAHP/releases/tag/v3.0.5
