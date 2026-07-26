# AAHP: Agent Conventions

> Every agent working on this project must read and follow these conventions.
> Update this file whenever a new standard is established.

---

## The Three Laws (Our Motto)

The project motto (Asimov's Three Laws) and the **do no damage** principle live once, in README (## Our Motto: The Three Laws). Agents must never take autonomous action that could harm data, systems, or people, or act beyond their delegated scope.

---

## Language

- All code, comments, commits, and documentation in **English only**
- Use clear, direct language in handoff files (agents are the primary readers)

## Code Style

- **Bash scripts:** POSIX-compatible where possible, `set -euo pipefail` always
- **JSON:** 2-space indentation, no trailing commas
- **Markdown:** ATX headers, tables with alignment, code blocks with language tags
- Scripts should handle both Linux (`sha256sum`) and macOS (`shasum -a 256`) tools

## Branching & Commits

```
feat/<scope>-<short-name>    → new feature
fix/<scope>-<short-name>     → bug fix
docs/<scope>-<short-name>    → documentation only
refactor/<scope>-<name>      → no behaviour change

Commit format:
  feat(scope): description [AAHP-auto]
  fix(scope): description [AAHP-auto]
  docs(scope): description [AAHP-auto]
```

## File Organization

- `templates/` -Handoff file templates (users copy these to their projects)
- `scripts/` -CLI tools (aahp-manifest.sh, aahp-migrate-v2.sh, lint-handoff.sh)
- `scripts/_aahp-lib.sh` -Shared functions (sourced, not executed directly)
- `schema/` -JSON Schema files for validation
- `.ai/handoff/` -AAHP's own handoff files (dogfooding)

## Architecture Principles

- **Bash-Only Core:** No Node.js or Python required for core tooling
- **Portable:** Scripts must work on Linux, macOS, and Git Bash (Windows)
- **Git-Native:** Everything lives in the repo, recoverable via git history
- **Layered Protocol:** Core files (STATUS, NEXT_ACTIONS, LOG) are mandatory; extended files (DASHBOARD, TRUST, CONVENTIONS, WORKFLOW) are optional

## Testing

- Test scripts manually against a temp `.ai/handoff/` directory before committing
- Validate generated JSON with `python3 -c "import json; json.load(open(...))"` or `jq .`
- Run `lint-handoff.sh` against the project's own `.ai/handoff/` directory

## Acceptance Criteria Lifecycle

Specified in README Section 8.7. Every task carries one canonical **Acceptance criteria**
section written as task boxes.

- `Acceptance criteria` is the canonical heading. `Completion criteria` and
  `Definition of done` are legacy aliases: still recognized, never written in new content.
- `- [ ]` while a criterion is unresolved; `- [x]` only with evidence (commit, PR, test
  run, live verification). Bulk-checking to close something out is invalid.
- Before a task becomes `done`, every remaining criterion is checked, waived
  (`(waived: rationale)`), or moved to a linked open follow-up (`(follow-up: T-042)`).
- `aahp criteria` prints an ADVISORY report over this file's sibling `NEXT_ACTIONS.md`.
  It is not a gate: it is not part of `aahp check` and always exits 0. Its findings are
  still defects to fix, and a clean report is not proof that the criteria are resolved
  (README Section 8.7 lists the shapes it is known to miss).

## Formatting

- **No em dashes (U+2014)**: Never use Unicode em dashes in any file (code, docs, comments, templates). They break shell scripts, cause encoding errors on Windows (cp1252), and corrupt JSON. Use a regular hyphen (`-`) instead.

## What Agents Must NOT Do

- **Violate the Three Laws** - never cause damage to data, systems, or people; never act beyond delegated scope
- Push directly to `main` without human approval
- Modify template files without updating the corresponding specification in README.md
- Write secrets, credentials, or PII into any handoff file
- Delete existing scripts without providing a replacement
- Break backward compatibility with v1 (MANIFEST.json-less projects must still work)
- Use em dashes (U+2014) anywhere in the codebase

---

*This file is maintained by agents and humans together. Update it when conventions evolve.*
