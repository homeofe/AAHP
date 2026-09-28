# AAHP: Build Dashboard

> A derived display surface for humans, not an authority. This repository keeps it
> deliberately small: every number it used to carry (test counts, pass states, dates)
> went stale because nothing regenerates it. The authoritative sources are listed
> below; read those instead of copying their state here.

---

## Where the current state lives

| Question | Authoritative source |
|----------|----------------------|
| What is the current state? | `STATUS.md` (a snapshot, rewritten each session) |
| What should the next agent do? | `NEXT_ACTIONS.md`, and the `tasks` graph in `MANIFEST.json` |
| Does the build pass? | GitHub Actions (`ci.yml` job `lint-and-validate`, required) |
| Is handoff state intact? | `aahp verify` (the `aahp-verify` check on every pull request) |
| What changed and when? | `LOG.md` (the journal) and `CHANGELOG.md` (releases) |

---

## Components

| Name | Path | Tests |
|------|------|-------|
| Specification | `README.md`, `docs/` | doc gates in `npm run check` |
| CLI | `bin/aahp.js` (installed as `@elvatis_com/aahp`) | `tests/cli.bats` and others |
| Shared library | `scripts/_aahp-lib.sh` | via the script suites |
| Manifest generator | `scripts/aahp-manifest.sh` | `tests/manifest.bats` |
| Lint | `scripts/lint-handoff.sh` | `tests/lint.bats` |
| Verify gate | `scripts/verify-handoff.sh` | `tests/verify.bats` |
| Governance gates | `scripts/check-*.mjs` | `tests/gates.bats`, `tests/check.bats` |
| Templates | `templates/` | `tests/cli.bats` (init) |
| JSON Schemas | `schema/` | `tests/doctor.bats` (manifest-schema) |
| Adopter workflows | `assets/governance/` | `tests/propagate.bats`, `tests/verify-workflow.bats` |

Test counts are not kept here. `npm test` runs every suite; CI is the record.

---

## Update Instructions (for agents)

- Update this file only when a component is added, moved or removed.
- Do not record test counts, pass states or task status here: they belong to the
  sources in the first table, which are regenerated or checked on every change.
