# AAHP: Claude Project Instructions

## Project Overview

- AAHP is a file-based AI-to-AI handoff protocol plus a small CLI for initializing, linting, migrating, and regenerating handoff state.
- Treat [README.md](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/README.md) as the specification and single source of truth for protocol behavior.
- The repo dogfoods AAHP in [`.ai/handoff/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/.ai/handoff).

## Tech Stack

- Node.js 18+ with ESM for [`bin/aahp.js`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/bin/aahp.js).
- Bash for the core tooling in [`scripts/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/scripts).
- No runtime npm dependencies; core behavior must keep working with Node + bash + standard system tools.
- Bats is used for automated tests.

## Directory Layout

- [`bin/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/bin) contains the CLI entrypoint. `init` is implemented in Node; `manifest`, `lint`, and `migrate` dispatch to bash scripts.
- [`scripts/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/scripts) contains the shipped tooling. Shared shell helpers live in [`scripts/_aahp-lib.sh`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/scripts/_aahp-lib.sh) and should be sourced, not duplicated.
- [`templates/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/templates) contains the files copied into a user's `.ai/handoff/` directory. Templates use `[PLACEHOLDER]` syntax.
- [`schema/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/schema) contains JSON Schema for `MANIFEST.json`.
- [`tests/`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/tests) contains Bats suites for manifest, lint, and migration flows.

## Working Rules

- Read [`.ai/handoff/MANIFEST.json`](/C:/Users/kohlere/Nextcloud/_Data/_Development/AAHP/.ai/handoff/MANIFEST.json) and relevant handoff files before making larger changes.
- Keep bash portable across Linux, macOS, and Git Bash on Windows.
- Use ASCII only. Do not introduce Unicode em dashes.
- Keep JSON at 2-space indentation with no trailing commas.
- If behavior changes, update `README.md`, affected templates, and tests together.
- Maintain backward compatibility for projects without `MANIFEST.json`.

## Verification Commands

```bash
npm test
bash tests/run.sh
bash scripts/lint-handoff.sh .
```

Schema validation:

```bash
npm install --no-save ajv-cli ajv-formats
npx ajv-cli validate --spec=draft2020 -c ajv-formats -s schema/aahp-manifest.schema.json -d .ai/handoff/MANIFEST.json
```

ShellCheck the shipped scripts before finishing shell changes:

```bash
shellcheck scripts/_aahp-lib.sh
shellcheck -x -P scripts/ scripts/aahp-manifest.sh
shellcheck -x -P scripts/ scripts/aahp-migrate-v2.sh
shellcheck scripts/lint-handoff.sh
```

## Change Expectations

- Add or extend Bats coverage for new script behavior.
- Do not edit generated or copied handoff examples without checking the matching template.
- Do not add new dependencies unless the benefit is clear and documented in the repo.
