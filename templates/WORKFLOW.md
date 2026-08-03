# [PROJECT]: Autonomous Multi-Agent Workflow

> Based on the [AAHP Protocol](https://github.com/homeofe/AAHP).
> No manual triggers. Agents orient from MANIFEST.json, then work autonomously.
> Model routing is owned by the consuming harness (README Section 9.1).

---

## Agent Roles

| Agent | Model | Role | Responsibility |
|-------|-------|------|---------------|
| 🔭 Researcher | e.g. perplexity/sonar-pro | Researcher | OSS research, compliance checks, doc review |
| 🏛️ Architect | e.g. claude-opus | Architect | System design, ADRs, interface definitions |
| ⚙️ Implementer | e.g. claude-sonnet | Implementer | Code, tests, refactoring, commits |
| 💬 Reviewer | e.g. gpt-4 / second model | Reviewer | Second opinion, edge cases, security review |

> Adapt roles and models to your team's tooling.

---

## The Pipeline

### Phase 1: Research & Context

```
Reads:   MANIFEST.json (tasks + quick_context), then STATUS.md
         NEXT_ACTIONS.md for human-readable task detail when needed

Does:    Researches relevant OSS libraries / APIs / compliance requirements
         Checks whether similar solutions already exist in the project
         Clarifies ambiguities in the task

Writes:  handoff/LOG.md -research findings + sources + recommendation
```

### Phase 2: Architecture Decision

```
Reads:   Research output from LOG.md
         handoff/STATUS.md
         Relevant source files, config, docs

Does:    Decides architecture and interface design
         Chooses branch name
         Defines exactly what the Implementer should build

Writes:  handoff/LOG.md -ADR (Architecture Decision Record)

ADR format:
  ## [DATE] ADR: [Feature Name]
  **Decision:** ...
  **Rationale:** ...
  **Consequences:** ...
  **Branch:** feat/...
  **Instructions for Implementer:** [numbered steps]
```

### Phase 3: Implementation

```
Reads:   ADR from LOG.md
         CONTRIBUTING.md / CONVENTIONS.md (MANDATORY before first commit)

Does:    Creates feature branch: git checkout -b feat/<scope>-<name>
         Writes code + unit tests
         Runs tests and type-check
         Commits and pushes branch

Branch convention:
  feat/<scope>-<short-name>    → new feature
  fix/<scope>-<short-name>     → bug fix
  docs/<scope>-<name>          → documentation only

Commit format:
  feat(scope): description [AAHP-auto]
  fix(scope): description [AAHP-fix]
```

### Phase 4: Discussion Round

```
All agents review the completed code on the feature branch.

Architect  → "Does the implementation match the ADR?"
Reviewer   → "What could be more robust, simpler, or more secure?"
Researcher → "Were all task items fulfilled? Any compliance concerns?"

Outcome:
  - Minor fixes → Implementer fixes in the same branch
  - Larger issues → New tasks added to NEXT_ACTIONS.md / DASHBOARD.md
  - Everything documented in LOG.md
```

### Phase 4.5 (optional): Grounding Audit

```
Runs:    On demand, or before handoff for high-impact tasks. Advisory, not a gate.
Scope:   Grounding and trust-of-claims only - are STATUS.md / TRUST.md assertions
         actually grounded? provenance gaps? circular review? expired trust?
         NOT code review (that is Phase 4).
Emits:   An advisory verdict SHIP / NEEDS_CHANGES / BLOCK, before the terminal
         Phase 5 handoff. Never a "Phase 6": Phase 5 is the final atomic step (the
         branch is pushed there), so an audit after it could not gate the commit.
```

> Draft v0.1. See GROUNDING.md and README section 2.10. The audit reasons on top of
> the verify gate; it does not restate its checks.

### Phase 5: Completion & Handoff

```
DASHBOARD.md:    Update build status, test counts, pipeline state
STATUS.md:       Update changed system state (Verified / Assumed / Unknown)
LOG.md:          Append session summary
NEXT_ACTIONS.md: Check off completed task, add newly discovered tasks

Git:     Branch pushed, PR-ready
Notify:  Project owner -only on fully completed tasks, not phase transitions
         Format: "✅ [Feature] done -Branch: feat/... -Tests: X/X"
```

---

## Autonomy Boundaries

| Allowed ✅ | Not allowed ❌ |
|-----------|--------------|
| Write & commit code | Push directly to `main` |
| Write & run tests | Install new dependencies without documenting |
| Push feature branches | Write secrets or PII into source |
| Research & propose OSS libraries | Call external APIs without credentials |
| Make architecture decisions | Perform production deployments |
| Break tests (when fixing identified bugs) | Delete tests without replacement |

---

## Task Selection Rules

Authoritative source: **MANIFEST.json `tasks` graph** (README Section 8.4).

1. Read `MANIFEST.json`
2. Filter tasks where `status = "ready"`
3. For each ready task, require every `depends_on` entry to have `status = "done"`
4. Sort by priority; pick the top task
5. Never start a task without reading `STATUS.md` first
6. After completing a task, update MANIFEST tasks / NEXT_ACTIONS.md and regenerate the manifest

`DASHBOARD.md` is a **derived display surface** for humans. It is not the task-selection
authority. If DASHBOARD and MANIFEST disagree, MANIFEST wins.

---

## Error Handling

If an agent fails or is uncertain:
- Mark task as `(Unknown)` in `STATUS.md`
- Document the specific blocker in `LOG.md`
- Notify the project owner
- **Never proceed on assumptions when certainty is missing**

---

## Open Source First

Before any custom implementation:
1. Researcher searches for existing OSS solutions
2. Architect evaluates: build vs. OSS vs. fork
3. Decision is documented in the ADR
4. Custom builds must be: clean abstraction, testable, documented

---

*This document lives in the repo and is continuously refined by the agents themselves.*
