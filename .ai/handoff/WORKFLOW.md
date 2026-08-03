# AAHP: Autonomous Multi-Agent Workflow

> Based on the [AAHP Protocol](https://github.com/homeofe/AAHP).
> No manual triggers. Agents orient from MANIFEST.json, then work autonomously.

---

## Agent Roles

| Agent | Model | Role | Responsibility |
|-------|-------|------|---------------|
| Researcher | e.g. research harness model | Researcher | OSS research, compliance checks, doc review |
| Architect | e.g. strong reasoning model | Architect | System design, ADRs, interface definitions |
| Implementer | e.g. coding model | Implementer | Code, tests, refactoring, commits |
| Reviewer | e.g. second model / peer | Reviewer | Second opinion, edge cases, security review |

> Model routing is owned by the consuming harness (README Section 9.1). Do not hard-code
> vendor model IDs in this protocol document; the table above is role labels only.
> AAHP is a specification project: most work is documentation, schema design, and bash.

---

## The Pipeline

### Phase 1: Research & Context

```
Reads:   MANIFEST.json (tasks + quick_context), then STATUS.md
         NEXT_ACTIONS.md for human-readable task detail when needed

Does:    Researches relevant standards, protocols, prior art
         Checks compatibility with existing AAHP tooling
         Clarifies ambiguities in the task

Writes:  handoff/LOG.md - research findings + sources + recommendation
```

### Phase 2: Architecture Decision

```
Reads:   Research output from LOG.md
         handoff/STATUS.md
         README.md (spec), schema/, templates/

Does:    Decides on schema extensions, template changes, script modifications
         Chooses branch name
         Defines exactly what the Implementer should build

Writes:  handoff/LOG.md - ADR (Architecture Decision Record)
```

### Phase 3: Implementation

```
Reads:   ADR from LOG.md
         CONVENTIONS.md (MANDATORY before first commit)

Does:    Creates feature branch
         Writes/modifies scripts, templates, schema, docs
         Tests scripts against temp handoff directories
         Commits and pushes branch

Branch convention:
  feat/<scope>-<short-name>    -> new feature
  fix/<scope>-<short-name>     -> bug fix
  docs/<scope>-<name>          -> documentation only

Commit format:
  feat(scope): description [AAHP-auto]
  fix(scope): description [AAHP-auto]
```

### Phase 4: Discussion Round

```
All agents review the completed work.

Architect  -> "Does the implementation match the ADR?"
Reviewer   -> "Is it portable? Does it break backward compat?"
Researcher -> "Were all task items fulfilled?"

Outcome:
  - Minor fixes -> Implementer fixes in the same branch
  - Larger issues -> New tasks added to MANIFEST tasks / NEXT_ACTIONS.md
```

### Phase 4.5 (optional): Grounding Audit

```
Runs:    On demand, or before handoff for high-impact tasks. Advisory, not a gate.
Trigger: security-sensitive, agent-governance, or compliance task types
         (see GROUNDING.md task-type anchor matrix).
Scope:   Grounding and trust-of-claims only - are STATUS.md / TRUST.md assertions
         actually grounded? provenance gaps? circular review? expired trust?
         NOT code review (that is Phase 4).
Emits:   An advisory verdict SHIP / NEEDS_CHANGES / BLOCK, before the terminal
         Phase 5 handoff. Never a "Phase 6": Phase 5 is the final atomic step.
```

> Draft v0.1. See GROUNDING.md and README sections 2.10 and 9.4. The audit reasons
> on top of the verify gate; it does not restate its checks.

### Phase 5: Completion & Handoff

```
STATUS.md:       Rewrite current state (not append)
LOG.md:          Append session summary (rotate if entry count exceeds 10)
NEXT_ACTIONS.md: Check off completed task, add newly discovered tasks
MANIFEST.json:   Regenerate (aahp manifest) with accurate quick_context
DASHBOARD.md:    Optional human display surface only (derived, not authoritative)

Git:     Branch pushed, PR-ready
Notify:  Project owner - only on fully completed tasks
```

---

## Autonomy Boundaries

| Allowed | Not allowed |
|---------|-------------|
| Write & commit scripts, templates, schemas | Push directly to `main` without approval |
| Write & run script tests | Modify LICENSE or project metadata without review |
| Push feature branches | Write secrets or PII into any file |
| Research & propose protocol extensions | Break backward compatibility with v1 without ADR |
| Make architecture decisions | Delete existing templates without replacement |

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
- Mark affected component as `(Unknown)` in `STATUS.md`
- Document the specific blocker in `LOG.md`
- Notify the project owner
- **Never proceed on assumptions when certainty is missing**

---

*This document lives in the repo and is continuously refined by the agents themselves.*
