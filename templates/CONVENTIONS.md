# [PROJECT] — Agent Conventions

> Every agent working on this project must read and follow these conventions.
> Update this file whenever a new standard is established.

---

## Language

- All code, comments, commits, and documentation in **English only**
- i18n/translation keys in camelCase English

## Code Style

<!-- Replace with your project's language/framework conventions -->

- **TypeScript:** strict mode, Zod for I/O validation, Prettier formatting
- **Python:** black + isort, type annotations required
- **Go:** `gofmt`, `golangci-lint`, idiomatic error handling

## Branching & Commits

```
feat/<scope>-<short-name>    → new feature
fix/<scope>-<short-name>     → bug fix
docs/<scope>-<short-name>    → documentation only
refactor/<scope>-<name>      → no behaviour change

Commit format:
  feat(scope): add description [AAHP-auto]
  fix(scope): resolve issue [AAHP-auto]
```

## Architecture Principles

<!-- Document your non-negotiable design rules here -->

- Example: **Zero-Persistence** — no PII written to disk
- Example: **Human-in-the-Loop** — AI assists, humans decide
- Example: **Open Source First** — evaluate OSS before building custom

## Testing

- All new code must have unit tests
- `pnpm test` / `go test ./...` must pass before every commit
- Type-check must pass before every commit

## What Agents Must NOT Do

- Push directly to `main`
- Install new dependencies without documenting the reason
- Write secrets or credentials into source files
- Delete existing tests (fix or replace instead)

---

*This file is maintained by agents and humans together. Update it when conventions evolve.*
