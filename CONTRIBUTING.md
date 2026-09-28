# Contributing

Thanks for your interest in contributing! AAHP is a protocol that other repositories
build on, so most of this file is about the gates a change has to pass and why.
[CONSTITUTION.md](CONSTITUTION.md) lists the invariants; [CLAUDE.md](CLAUDE.md) has the
project layout and command reference; [README.md](README.md) is the specification.

## Getting Started

1. Fork the repository and create a feature branch from `main`.
2. Install the pinned development tools: `npm ci`.
3. Keep changes focused and small. For major changes, open an issue first to discuss
   design and scope.

## Every pull request carries its handoff state

This repository dogfoods AAHP, and its required `aahp-verify` check runs
`aahp verify --level ci` on every pull request. Layer 2 of that gate fails a change set
that touches any tracked file outside `.ai/handoff/` unless the same change also
updates `.ai/handoff/STATUS.md` and regenerates `.ai/handoff/MANIFEST.json` (README
Section 2.8). So, before you push:

1. Rewrite `.ai/handoff/STATUS.md` to describe the state after your change. It is a
   snapshot, not a log (README Section 1.3); add a session entry at the top of
   `.ai/handoff/LOG.md` if the change is worth recording.
2. Regenerate the index: `node bin/aahp.js manifest .` (or `bash scripts/aahp-manifest.sh .`).
3. Run `node bin/aahp.js verify . --level prepush` locally. `bash scripts/install-hooks.sh .`
   installs the same check as pre-commit and pre-push hooks.

A change that touches only `.ai/handoff/` needs none of this.

### Dependabot pull requests

Dependabot opens one grouped version-update pull request per ecosystem (`npm` and
`github-actions`) with a 7-day cooldown; security updates are neither grouped nor
delayed (`.github/dependabot.yml`).

- An `npm` update that changes only `package-lock.json` (and at most devDependency
  specifiers in `package.json`), where every changed entry is dev-only, resolved from
  registry.npmjs.org, integrity-pinned and free of install scripts, is classified
  non-impacting by the content-based `handoffImpact.npmDevDependencyUpdates` exemption
  in `aahp.config.json`, so it passes Layer 2 without a handoff update. The exemption
  is decided by what the change contains, never by who opened it (ADR-018).
- Any other Dependabot change, including every `github-actions` bump (it edits files
  under `.github/workflows/`), is handoff-impacting like any other change: before it
  can merge, push a commit to its branch that updates `STATUS.md` and regenerates
  `MANIFEST.json`. An action bump may also need the pins that follow it by hand: the
  governance template `assets/governance/aahp-govern.yml` (rule H of
  `scripts/check-workflow-pinning.mjs`) and the `$schema` anchor in
  `.supply-chain-guard.yml` (ADR-021).

## Tests

Read [tests/README.md](tests/README.md) before writing a test: it lists the rules the
suite enforces on itself (no bare `!` before the last line, bash 4.1 or newer, a skip on
CI is a failure, a red control for every assertion script).

- Run the one file that covers your change: `node scripts/run-bats.mjs tests/<file>.bats`.
  `scripts/run-bats.mjs` launches the locked `bats` devDependency on Linux, macOS and
  Windows.
- `npm test` runs the whole suite. It is fast on Linux and slow on Windows, where every
  process spawn is expensive; on Windows, run the single file and let CI decide.
- CI (`.github/workflows/ci.yml`) runs the full suite and is the verdict for a pull
  request.
- `npm run check` runs the repository's gates (changelog, forbidden patterns, doc links,
  doc paths, ADR references, workflow pinning and more), and `npm run doctor` the
  conformance check. Both run in the required `lint-and-validate` job.
- ShellCheck every shell script you change (see [CLAUDE.md](CLAUDE.md) for the
  commands).

## Pull Request Process

1. Open a Pull Request against `main` with a clear description.
2. Link any relevant issues.
3. Ensure the required checks pass and documentation is updated with the behavior:
   when behavior changes, update `README.md`, the affected templates and the tests
   together.
4. Record a user-visible change under `## [Unreleased]` in `CHANGELOG.md`, using the
   Keep a Changelog sections (Added, Changed, Deprecated, Removed, Fixed, Security).

## Code and Documentation Style

- Follow existing patterns in the codebase.
- ASCII only in every tracked file: no emoji, no arrows, no em dashes (CONSTITUTION
  rule 7). Use `-`, `->`, a colon or brackets.
- This repository is public and ships to npm. Do not name private repositories,
  internal hosts, or figures about other repositories in any tracked file, handoff
  files included (CONSTITUTION.md, "What public handoff state and documentation may
  record").
- A decision that someone could reverse by accident belongs in the
  [Architectural Decision Log](docs/adr/README.md): add a file `ADR-NNN.md` under
  `docs/adr/` with the next free number, never renumber an existing one, and add it to
  the index (`npm run check:adr-refs` checks the two agree).

## Releasing AAHP

Releases follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SemVer,
and the grammar is machine-checked by `aahp doctor` / `check:changelog-format`.

**Release ceremony:**

1. Move the accumulated `## [Unreleased]` notes into a new `## [X.Y.Z] - YYYY-MM-DD`
   section (leaving `## [Unreleased]` empty above it) and add its reference link at the
   file foot.
2. Bump `version` in `package.json` to `X.Y.Z`; the top changelog release must equal it.
3. Run the gates and conformance check: `npm run check && npm run doctor`.
4. Regenerate handoff state: update `STATUS.md`, the `NEXT_ACTIONS.md` `Current version`
   line, and `MANIFEST.json` (`aahp manifest`).
5. `npm test` (bats green), commit, and push the `vX.Y.Z` tag at a commit that is on
   `main`, with `X.Y.Z` equal to the `package.json` version. CI runs the gates and the
   supply-chain scan on the tagged commit, then publishes to npm (OIDC trusted
   publishing) and creates the GitHub Release, which links to `CHANGELOG.md`. The publish
   job refuses a tag that is not exactly `vX.Y.Z`, does not match `package.json`, or is
   not reachable from `main` ([ADR-019](docs/adr/ADR-019.md)).

Step 4 is the same handoff update every change makes; a release additionally cuts a
changelog entry and a version tag.
