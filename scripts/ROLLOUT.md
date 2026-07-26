# AAHP Verify - Rollout Plan

The canonical handoff gate (`aahp verify`, `scripts/verify-handoff.sh`) stops
agents from leaving staled handoff state. This document is the playbook for
propagating that gate across a fleet of consumer repositories.

It describes consumers by ROLE, not by name. The concrete fleet list is
operator-specific, so it belongs in your own private configuration (see
[Where the fleet list lives](#where-the-fleet-list-lives)). What is portable,
and what this playbook provides, is the wave ordering, the rationale for
anchoring in the protocol repo first, the CI activation strategy, the
reviewed-allowlist discipline, and the rules that must not be bypassed.

## What gets propagated

Each target repo needs, copied from AAHP:

- `scripts/verify-handoff.sh` - the gate (4 layers)
- `scripts/_aahp-lib.sh` - shared helpers (already present in AAHP-enabled repos; refresh it)
- `scripts/lint-handoff.sh` - checksum/lint layer (already present; refresh it)
- `scripts/hooks/pre-commit`, `scripts/hooks/pre-push` - the hook scripts
- `scripts/install-hooks.sh` - installs the hooks into the repo's `.git/hooks/`
- `.github/workflows/aahp-verify.yml` - the intended REQUIRED CI check

Then, in the target repo:

```bash
bash scripts/install-hooks.sh .     # wire local pre-commit + pre-push
bash scripts/verify-handoff.sh . --level full   # confirm a clean baseline
```

The gate is verify-only. It never regenerates `MANIFEST.json`; that stays a
separate `/handoff` step. If the baseline run reports drift, run `/handoff`
first so the repo starts from a clean, in-sync state.

## The 4 layers (recap)

1. MANIFEST integrity: indexed files present and matching their checksums
   (the checksum comparison reuses `lint-handoff.sh`).
2. Content-drift gate (THE key check): if a commit/push changes any source file
   OUTSIDE `.ai/handoff/`, it MUST also include `STATUS.md` AND a regenerated
   `MANIFEST.json`, else FAIL: "Code changed but handoff state did not. Run /handoff."
3. Commit-pointer freshness (`MANIFEST.last_session.commit` vs HEAD).
4. TRUST-TTL expiry (advisory).

## Defaults (do not change without an ADR)

- Drift gate HARD-FAILS (exit 1). It does not warn.
- TRUST-TTL expiry is advisory (warn) and never blocks a commit on its own.
- Escape hatch `AAHP_SKIP_VERIFY=1` skips LOCAL verification only. It is caught
  by the required CI check (`aahp verify --level ci`, which ignores the hatch).
  Do NOT use it to bypass CI. Never use `git commit/push --no-verify`.
- CI activation: if hosted CI is currently unavailable to you (cost controls, a
  paused plan, a migration to self-hosted runners), commit the workflow anyway.
  It activates by itself the moment CI is switched back on, and until then the
  local hooks are the live enforcement. Do not delete the workflow "because it
  cannot run yet"; a repo that never gains the file never gains the backstop.

## Reviewed allowlist triage

Use `.ai/handoff/pii-allowlist.json` only for reviewed operational context. It
is not a bypass: entries are exact, expiring, and MANIFEST-indexed.

Most consumers that fail the PII layer fail for the same reason: a real
operational address (a support alias, an on-call escalation contact, a
demo or training account, a scan/report recipient) has been quoted inside
handoff prose. Triage every finding the same way:

1. **Read the exact finding, not the repo.** Run `aahp verify --level full` in
   the consumer and treat the output as a list of individual strings needing a
   decision, not as a verdict on the repository.
2. **Prefer redaction.** If the address is not load-bearing for understanding
   the handoff state, delete or generalise it. Redaction is always the cheaper
   outcome: no entry to review, no expiry to renew.
3. **Otherwise approve it exactly, one address at a time.** An entry is an exact
   value plus `reason`, `owner`, and a future `expires` date. Wildcards, bare
   domains, regular expressions, duplicates, and past expiry dates all fail
   validation by design. Never approve a batch with a single wildcard entry.
4. **Name the accountable owner per entry, not per repo.** The owner is whoever
   can answer "is this still the right address?" on the expiry date.
5. **Regenerate, then re-verify.** `aahp manifest`, then
   `aahp verify --level full`.

Track the per-consumer triage state (which consumer, which blocker class, who
decides, what action, target date) in your own private rollout tracker. A
public specification repo is the wrong place for an inventory of which of your
systems holds operational addresses; publishing that table tells a reader where
to go looking. Keep the columns, keep the contents private.

Consumer upgrade sequence: propagate the validator, schema, template, and
refreshed scripts; add reviewed exact entries; run `aahp manifest`; then run
`aahp verify --level full`. Do not use `AAHP_SKIP_VERIFY` or `--no-verify`. Run
`aahp archive` before `/handoff` whenever `LOG.md` grows past 10 active entries.

## CI strategy per wave

- Wave 1 consumers: commit the workflow now; once CI is available, mark
  `aahp-verify` as a REQUIRED status check in branch protection.
- Until CI is on, the gate runs report-and-block locally via the hooks.
- Do not promote the check to REQUIRED before at least one consumer in the wave
  has a green baseline run, or the first red build will be the gate itself
  rather than a real drift.

## Propagation targets (by role)

Status legend: anchor = built here; done = hooks installed + workflow committed;
queued = AAHP-enabled, awaiting propagation; not-yet = no `.ai/handoff/` present.

| Wave | Consumer role | Why it sits in this wave |
|------|---------------|--------------------------|
| 0 | The protocol repo itself (anchor) | The gate is built and dogfooded here, so there is one source of truth to copy from |
| 1 | The framework repo that seeds other repos | Whatever it carries ships into every future install automatically, so the gate propagates itself |
| 2 | The headless pipeline runner | Highest leverage: it spawns the agent pipeline and therefore produces the most unattended commits |
| 2 | The orchestration layer above the runner | Same commit profile, one level up |
| 2 | The scheduler that triggers unattended runs | A scheduled run must not be able to push staled state while nobody is watching |
| 2 | The dashboard that reads handoff state | It renders the state, so it should be held to the state's own integrity rules |
| 3 | Control-plane and tool-surface integration services | Many agent-driven commits, moderate blast radius |
| 3 | Editor or client extensions | Developer-facing, frequent small commits |
| 4 | Product services | Lower handoff churn, higher deploy caution |

A repo with no `.ai/handoff/` directory is not a propagation target yet: run
`aahp init` there first if the gate is wanted, or skip it deliberately (a
low-churn static asset repo is a reasonable skip). Record the skip decision in
the fleet list so it is not rediscovered from scratch every wave.

## Rollout order rationale

1. Anchor in the protocol repo so the gate has a single source of truth.
2. The seeding framework next: it is copied into every other repo, so the gate
   ships with future installs automatically.
3. The agent toolchain: these repos generate the most autonomous, agent-driven
   commits, so they are where staled handoff state is most likely.
4. The integration and developer-tooling repos.
5. Product services last (lower handoff churn, higher deploy caution; never
   couple this gate to a deploy step).

## Where the fleet list lives

The mapping from the roles above to actual repositories is operator-specific and
frequently sensitive: it is an inventory of what you run, who owns it, and what
is not yet protected. Keep it in your own private configuration, not in a public
repo. Expected shape, one row per consumer:

```json
{
  "waves": [
    {
      "wave": 1,
      "role": "framework repo that seeds other repos",
      "consumers": [
        {
          "repo": "acme/example-app",
          "aahpEnabled": true,
          "status": "queued",
          "owner": "<accountable team or person>",
          "notes": "<why this consumer sits in this wave>"
        }
      ]
    }
  ]
}
```

Nothing in this repository reads that file. It exists so the operator running
the rollout can answer "what is left" without the answer living in public.

## Per-consumer checklist

- [ ] Copy the files listed under "What gets propagated".
- [ ] `bash scripts/install-hooks.sh .`
- [ ] Run `/handoff` if `aahp verify --level full` reports drift.
- [ ] Confirm `aahp verify --level full` is green.
- [ ] Commit (the gate will enforce that STATUS.md + MANIFEST.json move with it).
- [ ] When CI is available: set `aahp-verify` as a required check.
- [ ] Record the outcome in the private fleet list, including deliberate skips.
