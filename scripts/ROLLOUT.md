# AAHP Verify - Rollout Plan

The canonical handoff gate (`aahp verify`, `scripts/verify-handoff.sh`) stops
agents from leaving staled handoff state. This doc tracks propagating it across
the active Elvatis repos.

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

1. MANIFEST checksum integrity (reuses `lint-handoff.sh`).
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
- CI activation: GitHub Actions is OFF org-wide (cost sweep). The workflow is
  committed so it activates when Actions is re-enabled. Until then, the local
  hooks are the live enforcement.

## Reviewed PII allowlist rollout

Use `.ai/handoff/pii-allowlist.json` only for reviewed operational context. It
is not a bypass: entries are exact, expiring, and MANIFEST-indexed.

| Repository | Current blocker | Accountable owner | Required action |
|---|---|---|---|
| `atlas` | Scan/report operational addresses | Atlas product team | Redact or approve exact expiring entries, then regenerate MANIFEST. |
| `elvatis-security-platform` | Shield support/operator addresses | Shield product team | Redact or approve each address individually. |
| `elvatis-client-portal` | Customer-portal operational addresses | Client Portal team | Redact or approve each address individually. |
| `elvatis-awareness` | Training/demo operational addresses | Awareness product team | Redact or approve each address individually. |

Consumer upgrade: propagate the validator, schema, template, and refreshed
scripts; add reviewed exact entries; run `aahp manifest`; then run
`aahp verify --level full`. Do not use `AAHP_SKIP_VERIFY` or `--no-verify`. Run `aahp archive` before `/handoff` whenever `LOG.md` grows past 10 active entries.

## CI strategy per wave

- Wave 1 repos: commit the workflow now; once Actions is re-enabled, mark
  `aahp-verify` as a REQUIRED status check in branch protection.
- Until Actions is on, the gate runs report-and-block locally via the hooks.

## Propagation targets (active Elvatis repos)

Status legend: anchor = built here; done = hooks installed + workflow committed;
queued = AAHP-enabled, awaiting propagation.

| # | Repo | AAHP-enabled | Status | Notes |
|---|------|--------------|--------|-------|
| 0 | AAHP | yes | anchor | Gate built and dogfooded here |
| 1 | improvements | yes | done | First propagation target (framework that seeds every other repo) |
| 2 | aahp-runner | yes | queued | Headless pipeline runner; highest leverage (spawns the 5-agent pipeline) |
| 3 | aahp-orchestrator | yes | queued | Orchestration layer |
| 4 | aahp-cron | yes | queued | Schedules runs; should not push staled state |
| 5 | aahp-hub | yes | queued | Dashboard over handoff state |
| 6 | akido-mcp | yes | queued | Control-plane MCP; many agent-driven commits |
| 7 | elvatis-mcp | yes | queued | Tool-surface MCP |
| 8 | conduit-bridge | yes | queued | Provider bridge |
| 9 | conduit-vscode | yes | queued | VS Code extension |
| 10 | atlas | yes | queued | Product service (Express) |

Secondary product services to follow once the toolchain wave lands
(all AAHP-enabled): elvatis-security-platform (Shield), elvatis-client-portal
(Portal), elvatis-defense (Defense), elvatis-awareness (Awareness),
elvatis-homepage.

> `elvatis-landings` has no `.ai/handoff/` yet; run `aahp init` there first if
> the gate is wanted, otherwise skip it (static landing assets, low churn).

## Rollout order rationale

1. Anchor in AAHP (the protocol repo) so the gate has a single source of truth.
2. improvements next: it is the framework copied into every other repo, so the
   gate ships with future installs automatically.
3. The aahp-* toolchain: these repos generate the most autonomous, agent-driven
   commits, so they are where staled handoff state is most likely.
4. The MCP / bridge dev repos.
5. Product services last (lower handoff churn, higher deploy caution; never
   couple this gate to a deploy step).

## Per-repo checklist

- [ ] Copy the files listed under "What gets propagated".
- [ ] `bash scripts/install-hooks.sh .`
- [ ] Run `/handoff` if `aahp verify --level full` reports drift.
- [ ] Confirm `aahp verify --level full` is green.
- [ ] Commit (the gate will enforce that STATUS.md + MANIFEST.json move with it).
- [ ] When Actions is re-enabled: set `aahp-verify` as a required check.
