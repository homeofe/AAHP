# [PROJECT]: Agent Journal

> **Append-only.** Never delete or edit past entries.
> Every agent session adds a new entry at the top.
> This file is the immutable history of decisions and work done.

---

<!-- EXAMPLE ENTRIES, delete these before using in production -->

<!--
  The blockquote at the top of the first entry is the provenance block from
  README Section 2.4. It is a CONVENTION: no AAHP gate reads these five fields,
  and no gate fails when an entry omits them (ADR-021). It ships here so that a
  repository following the template produces entries that can be traced back to
  an agent and a session. If your project needs that trail to be complete, you
  have to enforce it yourself; AAHP will not tell you when it is missing.
-->

## [YYYY-MM-DD] [Agent]: [Task Name]

> **Agent:** claude-opus-4.6
> **Session ID:** sess_abc123
> **Timestamp:** 2026-02-26T14:30:00Z
> **Commit before:** abc1234
> **Commit after:** def5678

**Phase:** 3 (Implementer)
**Branch:** feat/example-feature

### What was done

- Created `src/feature.ts` with XYZ logic
- Added 12 unit tests, all passing
- Updated `STATUS.md` and `NEXT_ACTIONS.md`

### Decisions made

- Chose library A over B because of smaller bundle size
- Deferred feature X to next session (see NEXT_ACTIONS.md)

---

## [YYYY-MM-DD] ADR: [Architecture Decision Record Title]

**Status:** Proposed / Accepted / Superseded

**Context:**
What problem are we solving? What constraints exist?

**Decision:**
What did we decide to do?

**Rationale:**
Why this option over the alternatives?

**Consequences:**
What becomes easier? What becomes harder?

**Branch:** feat/...

**Instructions for Implementer:**
1. Step one
2. Step two
3. ...

---

## [YYYY-MM-DD] Research: [Topic]

**Agent:** Sonar / Researcher
**Task:** [What was researched]

**Findings:**
- Finding 1
- Finding 2

**Recommendation for Architect:**
...

**Sources:**
- https://...
- https://...

---

<!-- END EXAMPLE ENTRIES -->
