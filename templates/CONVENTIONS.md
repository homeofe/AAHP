# [PROJECT]: Agent Conventions

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

- Example: **Zero-Persistence**, no PII written to disk
- Example: **Human-in-the-Loop**, AI assists, humans decide
- Example: **Open Source First**, evaluate OSS before building custom

## Testing

- All new code must have unit tests
- `pnpm test` / `go test ./...` must pass before every commit
- Type-check must pass before every commit

## Acceptance Criteria Lifecycle

Every implementation task, and every issue an adapter links to one, carries a single
canonical **Acceptance criteria** section written as task boxes.

1. **One canonical heading.** Use `Acceptance criteria` (as a Markdown heading or a bold
   label). `Completion criteria` and `Definition of done` are legacy aliases: readers and
   tooling still accept them, new content does not use them.
2. **Task boxes, not bullets.** `- [ ]` while a criterion is unresolved. A plain bullet is
   not a criterion, because nothing can tell resolved from unresolved.
3. **Check on evidence only.** `- [x]` requires evidence: a commit, a PR, a test run, or a
   live verification. Bulk-checking a list to close something is invalid.
4. **Closure is complete or explicit.** Before a task becomes `done` (or a linked issue is
   closed), every remaining criterion is one of:
   - completed and checked;
   - explicitly waived: `- [ ] Criterion (waived: rationale)`;
   - moved to a linked open follow-up: `- [ ] Criterion (follow-up: T-042)` or `(follow-up: #123)`.
5. **Record the evidence.** Closure notes name the commit, PR, tests, live verification,
   waiver rationale, or follow-up reference. An unchecked box with no marker is unfinished
   work, not a formatting detail.
6. **GitHub is optional.** The lifecycle is an AAHP task rule. Where a project syncs tasks
   to issues, the adapter mirrors the same boxes onto the issue and reconciles them before
   the issue closes.
7. **Tooling is advisory.** `aahp criteria` prints a best-effort report over these
   documents. It is not a gate, it always exits 0, and a clean report is not proof that
   the criteria are resolved: the shapes it is known to miss are listed in README
   Section 8.7. The lifecycle is upheld by review, not by an exit code.

## Formatting

- **No em dashes (U+2014)**: Never use Unicode em dashes in any file (code, docs, comments, templates). They break shell scripts, cause encoding errors on Windows (cp1252), and corrupt JSON. Use a regular hyphen (`-`) instead.

## What Agents Must NOT Do

- **Violate the Three Laws** - never cause damage to data, systems, or people; never act beyond delegated scope
- Push directly to `main`
- Install new dependencies without documenting the reason
- Write secrets or credentials into source files
- Delete existing tests (fix or replace instead)
- Use em dashes (U+2014) anywhere in the codebase

---

*This file is maintained by agents and humans together. Update it when conventions evolve.*
