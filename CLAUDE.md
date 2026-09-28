# AAHP: Claude Project Instructions

## Project Overview

- AAHP is a file-based AI-to-AI handoff protocol plus a small CLI for initializing, linting, migrating, and regenerating handoff state.
- Treat [README.md](README.md) as the specification and single source of truth for protocol behavior.
- The repo dogfoods AAHP in [`.ai/handoff/`](.ai/handoff).

## Tech Stack

- Node.js 22+ with ESM for [`bin/aahp.js`](bin/aahp.js).
- Bash for the core tooling in [`scripts/`](scripts/).
- No runtime npm dependencies; core behavior must keep working with Node + bash + standard system tools.
- Bats is used for automated tests.

## Directory Layout

- [`bin/`](bin/) - CLI entrypoint. `init` is implemented in Node; `manifest`, `lint`, and `migrate` dispatch to bash scripts.
- [`scripts/`](scripts/) - Shipped tooling. Shared shell helpers live in [`scripts/_aahp-lib.sh`](scripts/_aahp-lib.sh) and should be sourced, not duplicated.
- [`templates/`](templates/) - Files copied into a user's `.ai/handoff/` directory. Templates use `[PLACEHOLDER]` syntax.
- [`schema/`](schema/) - JSON Schema for `MANIFEST.json`.
- [`tests/`](tests/) - Bats suites for the CLI, scripts and gates. Read [`tests/README.md`](tests/README.md) before adding a test: it states the rules the suite enforces on itself.
- [`docs/`](docs/) - The [Architectural Decision Log](docs/adr/README.md) (one file per ADR) and the [governance-gate reference](docs/governance.md).

## Build & Test Commands

```bash
# Run all tests
npm test
bash tests/run.sh

# Run a single test file (portable across Linux, macOS, and Windows)
node scripts/run-bats.mjs tests/cli.bats
node scripts/run-bats.mjs tests/manifest.bats
node scripts/run-bats.mjs tests/lint.bats
node scripts/run-bats.mjs tests/migrate.bats

# Lint handoff files
bash scripts/lint-handoff.sh .

# Schema validation with ajv (draft 2020-12, ajv-formats in full mode, ajv's
# default strict mode), the same command CI runs. ajv and ajv-formats are exact
# devDependencies that `npm ci` places from the lockfile, and the script loads
# them with `node`, never `npx`, so nothing here can reach the registry; without
# the install it exits 2. Exit 0 valid, 1 invalid, 2 could not evaluate.
# (It replaced ajv-cli 5.0.0, whose dependency tree is deprecated.) If you do
# run npx in a workflow: check-workflow-pinning.mjs requires `npm ci
# --ignore-scripts` before it in the same job and `--no-install` on it, and
# rejects `npm exec`, which ignores that flag on npm 10 and 11
# (docs/adr/ADR-013.md).
npm ci --ignore-scripts
node scripts/validate-json-schema.mjs schema/aahp-manifest.schema.json .ai/handoff/MANIFEST.json
node scripts/validate-json-schema.mjs schema/aahp-config.schema.json aahp.config.json aahp.config.example.json

# ShellCheck all shipped scripts before finishing shell changes
shellcheck scripts/_aahp-lib.sh
shellcheck -x -P scripts/ scripts/aahp-manifest.sh
shellcheck -x -P scripts/ scripts/aahp-migrate-v2.sh
shellcheck scripts/lint-handoff.sh
```

## How to Add a New CLI Command

AAHP commands come in two flavors: **Node-native** (like `init`) and **bash-delegated** (like `manifest`, `lint`, `migrate`).

### Option A: Bash script command (recommended for most new commands)

1. **Create the script** in `scripts/aahp-<command>.sh`:
   ```bash
   #!/usr/bin/env bash
   # aahp-<command>.sh - description
   set -euo pipefail
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "$SCRIPT_DIR/_aahp-lib.sh"
   # ... your logic
   ```
   - Source `_aahp-lib.sh` for shared helpers; do not duplicate them.
   - Accept an optional `[path]` as the first positional argument (before flags).
   - Use `--flag value` style options parsed with a `while [[ $# -gt 0 ]]` loop.
   - Exit 0 on success, 1 on error.

2. **Register it in `bin/aahp.js`**:
   - Add a `case` entry in the `switch (command)` block:
     ```js
     case 'yourcommand':
       runScript('aahp-yourcommand.sh', rest)
       break
     ```
   - Update `printHelp()` to document the new command.

3. **Add Bats tests** in `tests/<yourcommand>.bats` covering the happy path and error cases.

4. **ShellCheck** the new script before committing.

### Option B: Node-native command (for commands needing Node.js APIs)

1. Implement the function in `bin/aahp.js` following the pattern of `cmdInit`.
2. Add a `case` in the `switch` block and update `printHelp()`.
3. Add or extend Bats tests; use `node` invocations if shell testing is insufficient.

### Command conventions

- All commands accept an optional `[path]` first positional argument (defaults to `.`).
- Keep commands composable: one command does one thing.
- Do not add new npm runtime dependencies without documenting the reason.
- Update `README.md`, affected templates, and tests together when behavior changes.

## Working Rules

> These operationalize [CONSTITUTION.md](CONSTITUTION.md), the non-negotiable invariants. When in doubt, the constitution wins.

- Read [`.ai/handoff/MANIFEST.json`](.ai/handoff/MANIFEST.json) and relevant handoff files before making larger changes.
- Keep bash portable across Linux, macOS, and Git Bash on Windows.
- Use ASCII only. Do not introduce Unicode em dashes.
- Keep JSON at 2-space indentation with no trailing commas.
- If behavior changes, update `README.md`, affected templates, and tests together.
- Maintain backward compatibility for projects without `MANIFEST.json`.

## Change Expectations

- Add or extend Bats coverage for new script behavior.
- Do not edit generated or copied handoff examples without checking the matching template.
- Do not add new dependencies unless the benefit is clear and documented in the repo.

## Style Rules

- Never use em dashes (U+2014) in any content: documentation, markdown, README, code comments, GitHub issue titles, or handoff files. Use a plain hyphen (-) instead.
- When reviewing existing files, scan for em dashes and replace them.
- Applies to all .md files, HTML templates, comments, and .ai/handoff files.
- If an AI tool auto-inserts em dashes (e.g. "Title - Subtitle"), fix before committing.
