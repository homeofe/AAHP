# Changelog

All notable changes to `@elvatis_com/aahp` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses semantic
versioning (`aahp_version` in `MANIFEST.json` tracks the file-format contract and moves
independently of the npm version).

> Publishing note: npm releases lapsed after `3.2.1` because the CI publish workflow was
> disabled, so `3.3.0` and `3.4.0` were developed in the repository but never published.
> `3.5.0` is the first npm release since `3.2.1` and ships everything below it.

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

## [3.1.0] - 2026-06

### Added
- Reviewed, exact-value, expiring PII email allowlist (`pii-allowlist.json`),
  MANIFEST-indexed so it cannot suppress secrets. Shipped to npm as part of the 3.2.0
  release.

## [3.0.1] to [3.0.5] - 2026-04-12 to 2026-06-20

### Added
- AAHP v3: stable task IDs (`T-001` and up), a machine-readable dependency graph in
  `MANIFEST.json`, the `aahp` CLI, the verify gate (`aahp verify`), checksum integrity,
  the prompt-injection and secrets/PII firewalls, and OIDC trusted publishing to npm.

### Changed
- Relicensed to Apache-2.0 (earlier commits carried MIT, then CC BY 4.0, headers).

[3.5.0]: https://github.com/homeofe/AAHP/releases/tag/v3.5.0
[3.4.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.4.0
[3.3.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.3.0
[3.2.1]: https://github.com/homeofe/AAHP/releases/tag/v3.2.1
[3.2.0]: https://github.com/homeofe/AAHP/releases/tag/v3.2.0
