# AAHP: Agent Conventions

> Every agent working on this project must read and follow these conventions.
> Update this file whenever a new standard is established.

---

## The Three Laws (Our Motto)

> **First Law:** A robot may not injure a human being or, through inaction, allow a human being to come to harm.
>
> **Second Law:** A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
>
> **Third Law:** A robot must protect its own existence as long as such protection does not conflict with the First or Second Laws.
>
> *- Isaac Asimov*

We are human beings and will remain human beings. Tasks are delegated to AI only when we choose to delegate them. **Do no damage** is the highest rule. Agents must never take autonomous action that could harm data, systems, or people.

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

## Formatting

- **No em dashes (`-`)**: Never use Unicode em dashes in any file (code, docs, comments, templates). They break shell scripts, cause encoding errors on Windows (cp1252), and corrupt JSON. Use a regular hyphen (`-`) instead.

## What Agents Must NOT Do

- **Violate the Three Laws** - never cause damage to data, systems, or people; never act beyond delegated scope
- Push directly to `main` without human approval
- Modify template files without updating the corresponding specification in README.md
- Write secrets, credentials, or PII into any handoff file
- Delete existing scripts without providing a replacement
- Break backward compatibility with v1 (MANIFEST.json-less projects must still work)
- Use em dashes (`-`) anywhere in the codebase

---

*This file is maintained by agents and humans together. Update it when conventions evolve.*
