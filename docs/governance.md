# AAHP governance gates

The handoff protocol in [README.md](../README.md) gates *handoff* state: `aahp verify`
decides whether `.ai/handoff/` is intact and current. This document covers the other,
separately adoptable half: the conformance record (`aahp doctor`), the governance gate
runner (`aahp check`), and the config-driven release gates behind both. README Section
2.11 is the short summary; the decisions behind the split are
[ADR-011](adr/ADR-011.md), [ADR-012](adr/ADR-012.md) and [ADR-016](adr/ADR-016.md).
Until 2026-09-28 this text was README Sections 2.11 and 11.1.

Release hygiene (a well-formed changelog, a version bumped everywhere, honest
capability numbers) is a separate concern from handoff state, so it lives in a
separate command and a set of config-driven gates that ship in the package and run
against any consumer project.

## `aahp doctor`: the conformance record

**`aahp doctor`** is a conformance self-check. It asserts that a repo actually
follows the protocol and emits a machine-readable JSON record a fleet dashboard
can ingest:

```bash
aahp doctor              # human-readable summary plus the JSON record
aahp doctor --json       # only the JSON record, on stdout
aahp doctor --governance # governance-only record; skip the 3 handoff gates (alias --no-handoff)
```

It checks seven gates: the handoff file set matches `AAHP_HANDOFF_FILES` (indexed
files present, no strays, file content not compared); `MANIFEST.json` conforms to
the schema; `GROUNDING.md` is present and `TRUST.md` carries a Provenance column;
`@elvatis_com/aahp` is pinned to an exact version in `devDependencies` (`self` for
this repo; the gate reports `skip` unless `pinnedDep` is configured, which
`aahp init --gates` does, see below); the
`CHANGELOG.md` matches the Keep a Changelog grammar; the version
is in sync across configured sites; and the workflow that runs the AAHP gate
cannot skip it (`verify-workflow`, below). The record:

```json
{ "schemaVersion": 2, "repo": "homeofe/AAHP", "aahpVersion": "3.12.0",
  "gates": { "handoff-set": "pass", "manifest-schema": "pass", "grounding": "pass",
             "pinned-dep": "self", "changelog-format": "pass", "version-sync": "pass",
             "verify-workflow": "pass" },
  "gateOutcomes": { "pinned-dep": { "outcome": "self", "reason": "this repo is @elvatis_com/aahp itself" } },
  "evaluated": 7, "total": 7,
  "checkedAt": "2026-07-18T00:00:00Z" }
```

`gateOutcomes` is abbreviated above; the real record carries one entry per gate.

**Reading the summary line, and `schemaVersion` 2.** The human footer counts
gates that RAN, not gates that exist: `Conformance OK: 5 of 7 gate(s) ran, no
failures.` A run in which nothing was evaluated is a third outcome, not a pass:
it prints `Conformance NOT EVALUATED: 0 of 7 gate(s) ran. This is not a pass.`
and exits 1, on the text path, under `--quiet`, and under `--json` alike. Before
version 2 the footer read `Conformance OK: 7 gate(s), no failures.` over seven
skips and zero evaluations, and `--quiet` printed nothing at all.

`schemaVersion` 2 adds three fields and changes none. `gates` is byte-for-byte
what version 1 emitted, with the same keys and the same status tokens, so a
reader that switches on `gates` needs no change. What is new is `gateOutcomes`
(a refined `outcome` and the human `reason`, per gate), `evaluated` and `total`.
The refinement matters because version 1's `skip` stood for four different
states at once, so a repository that has adopted governance and one that has
switched every gate off through `config.check` emitted identical records. The
`outcome` values are `pass`, `fail`, `missing`, `self`, `not-applicable`,
`deselected` and `unevaluated`. A reader asserting `schemaVersion === 1` must
widen to `>= 1`; a reader that ignores unknown fields needs nothing.

## The `verify-workflow` gate: can the workflow that runs the gate skip it?

Every other gate asks whether the repository is in a good state. This one asks
whether the required check that ENFORCES that state can be made to report success
without running, which no amount of repository state can reveal.

`aahp-verify.yml` is meant to be a required status check. Wrap the job in an `if:`,
or wrap the gate step inside it, and the check keeps its name, keeps being required,
and keeps reporting success while it evaluates nothing. Branch protection is then
satisfied by a verdict nobody produced. This is not only the Layer 2 drift gate
going missing: Layer 1 MANIFEST checksum integrity is skipped with it.

The defect cannot be seen from inside AAHP. The workflow AAHP ships is
unconditional and `propagate.sh` copies it verbatim, so the weakening only ever
exists in the consumer's copy. `aahp doctor` therefore audits the consumer's own
`.github/workflows/`, and because the canonical workflow's last step runs
`aahp doctor`, a repository that has weakened its gate now says so on its own
pull requests.

What is asserted is the CONSEQUENCE, "there exists an event on which this workflow
concludes success without having run the gate at `--level ci`", not the file's
shape. The findings:

| Finding | The state it can reach |
|---------|------------------------|
| `job-conditional` | the hosting job carries an `if:`; when it is false the job is skipped and the required check is satisfied having run nothing |
| `job-soft-failing` | the job sets `continue-on-error`, so it reports success when the gate fails |
| `ci-step-conditional` | no step runs the gate at `--level ci` unconditionally, so on some events the job succeeds having verified nothing |
| `ci-step-soft-failing` | the gate runs unconditionally and its result is discarded |
| `no-ci-level` | the gate never runs at `--level ci`, so `AAHP_SKIP_VERIFY=1` is honoured and a workflow-level `env:` can set it |
| `govern-job-conditional` | the job hosting the GOVERNANCE gate carries an `if:`; when it is false the job is skipped having run no gate |
| `govern-job-soft-failing` | that job sets `continue-on-error`, so it reports success when a governance gate fails |
| `govern-step-conditional` | every step running `aahp check` (or every step running `aahp doctor`) carries an `if:`, so on some events the job succeeds having evaluated nothing |
| `govern-step-soft-failing` | the governance gate runs unconditionally and its result is discarded |

**Both shipped workflows are audited.** ADR-016 splits them deliberately:
`aahp-verify.yml` gates handoff state, `aahp-govern.yml` gates governance. The
audit originally covered only the first, which left the wider blast radius
uncovered: `aahp-govern.yml` is what `aahp init --gates` writes into an adopting
repository, and a governance-only adopter has no `aahp-verify.yml` at all, so it
is their entire CI backstop. Wrapping its `Run governance gates` step in
`if: false` left `aahp doctor` reporting `SKIP: no workflow here runs the AAHP
verify gate` and exiting 0.

The governance findings are judged per SUBCOMMAND, not per job. `aahp check` and
`aahp doctor` are different gates, and the shipped template runs both, so a
per-job test ("some governance step is unconditional") reads a file whose
`aahp check` step alone is wrapped as enforced. `npm run govern` is deliberately
not recognised as a gate invocation: what that script expands to is not readable
from the workflow, and a guess would be a finding this reader cannot support.

A repository whose workflows never run either gate reports `skip`: there is no CI
backstop to weaken. A repository that runs the governance gate unconditionally
and no verify gate is a distinct verdict, `governance-only`, which exits 0 and
whose pass reason says out loud that nothing there compares a handoff checksum,
so a green line cannot be read as an integrity statement. A workflow that clearly
hosts a gate but whose shape cannot be decided (the gate reached through a
composite action, or a file that will not parse) reports `fail`, because undecided
is not clean. Two shapes are deliberately NOT findings, because they fail closed
rather than green: an `if:` on the checkout step alone (the gate then runs against
an empty workspace and exits non-zero), and `paths:` filters that stop the
workflow triggering (a required check that never reports leaves the pull request
pending). One more is named rather than hidden: where `aahp verify` and
`aahp doctor` run in the SAME job, that job's skippability is decided by the
verify audit, so an `if:` on the record step alone (with the verify step
unconditional) is not reported. The gate still runs all four layers there; only
the record is lost.

If a class of change genuinely does not need the handoff gate, put that exemption
INSIDE the gate, keyed on the change, where it is visible and testable. Do not put
it around the step, keyed on who pushed it.

To remediate a `bypassable` result, remove `if:` and `continue-on-error` from the
job that hosts the gate and from the gate step itself. Ensure at least one
unconditional step runs `aahp verify --level ci`; for the governance workflow,
ensure both `aahp check` and `aahp doctor` run unconditionally. Keep
`verifyWorkflow.enforce` opt-in: it decides whether the reported finding blocks,
not whether the unsafe workflow shape is reported.

AAHP ships no runtime dependencies, so this gate carries a small block-YAML reader
rather than importing a parser. A hand-written parser that quietly disagrees with
real YAML would be the worst possible engine for a security gate, so
`tests/assert-workflow-parser-parity.mjs` compares it against a real YAML parser on
every workflow in this repository and every fixture, on exactly the fields the
audit reads and on the resulting findings.

## What `doctor` does not check: handoff file content

`doctor` never hashes a handoff file, and neither does `aahp check`. The
`handoff-set` gate compares the file SET and the INDEX. `manifest-schema`
compares `MANIFEST.json` against the schema, which rejects a MALFORMED checksum
but says nothing about a well-formed one that no longer matches the bytes.
Comparing recorded checksums against file content belongs to `aahp verify`
Layer 1, which ADR-011 makes the owner of handoff drift. Layer 1 hashes each
indexed file itself and additionally runs `aahp lint`, which compares them
again. Do not substitute `aahp lint` for that gate: its comparison runs only
under a Python interpreter, and with none on `PATH` it prints that MANIFEST
integrity was NOT verified and still exits 0, so it reports nothing on a
drifted tree. Layer 1 fails outright when no interpreter is available. The
`handoff-set` pass reason therefore names the boundary instead of leaving a
green line to imply integrity:

```text
  PASS     handoff-set: 3 indexed files present, no strays (content not compared; aahp verify Layer 1 owns checksum integrity)
```

That reason is emitted on one line by the DEFAULT human-readable output, and
from `schemaVersion` 2 it is in the record as well:
`gateOutcomes["handoff-set"].reason` carries the same sentence, so a dashboard
reads the limit rather than only a green token. `aahp doctor --quiet` still
prints nothing for a passing gate, though it now always states the overall
result, and `aahp doctor --governance` still marks the gate `skip` without
evaluating it, distinguished in the record as `outcome: "unevaluated"` rather
than as the same `skip` a gate with no inputs receives.

One configuration deserves an explicit warning. When `verify-workflow` reports
`skip`, meaning no workflow in the repository runs the AAHP verify gate, and the
handoff gates are still evaluated, then no automated gate in that repository
compares a handoff checksum. `aahp doctor` exits 0, `aahp check` exits 0, and a
handoff file edited outside the protocol is invisible to both. The record is
accurate about what it measured and it is not an integrity signal. Fix it by
adopting the shipped `assets/governance/aahp-verify.yml` as your
`.github/workflows/aahp-verify.yml` (README Quickstart step 5, or `aahp init --gates`
in a repository that has `.ai/handoff/`), which runs
`aahp verify --level ci` before `aahp doctor` in the same job, or by running
`aahp verify` some other way.

In this repository, and in any repository whose `aahp-verify.yml` matches the
shipped one, that ordering is already in place: a checksum drift fails the job at the verify step
and the `doctor` step never runs, so a green record cannot mask the drift.

## `aahp check`: the governance gate runner

**`aahp check`** is the pass/fail counterpart to that record. Where `doctor` emits a
conformance snapshot, `check` runs the config-driven governance gates as one aggregate
and its exit code drives CI (0 only when no gate fails AND at least one gate ran;
a skipped gate never fails):

```bash
aahp check             # run every applicable gate; per-gate PASS/FAIL/SKIP plus a footer
aahp check --json      # a { schemaVersion: 2, gates, gateOutcomes, evaluated, total } record
aahp check --quiet     # only failing gate lines plus the footer, which is always printed
```

Each gate is applicable only when its inputs exist (for example the `handoff` gate runs
only when `.ai/handoff/MANIFEST.json` is present); otherwise it is reported `skip`, not
run. `config.check.only` (a whitelist) and `config.check.skip` (a blacklist) narrow the
set explicitly, and the record tells the two kinds of skip apart:
`outcome: "deselected"` for a gate the config switched off, `"not-applicable"`
for one with nothing to check.

A run in which NO gate ran is a third outcome, neither pass nor fail:
`Governance NOT EVALUATED: 0 of 8 gate(s) ran. This is not a pass.`, exit 1. The
text path, `--quiet` and `--json` all reach that same verdict on the same tree;
until this was fixed `--json` returned above the test and exited 0 with every
gate `skip`.

The same governance-only stance is available from the record side:
`aahp doctor --governance` (alias `--no-handoff`) forces the three handoff gates to
`skip` without evaluating them, so a repo with no `.ai/handoff/` still emits a
conformance record over the remaining gates; the default mode is unchanged.

## Config-driven gates

These gates read an optional `aahp.config.json` at the
project root and are a clean no-op when it (or the relevant section) is absent, so
a repo that never opts in keeps working:

| Gate | Script | Config key | Checks |
|------|--------|-----------|--------|
| version-sync | `check-version-sync.mjs` | `versionSites` | the package version appears in each listed file |
| changelog presence | `check-changelog.mjs` | uses `CHANGELOG.md` | the current version has a changelog entry |
| changelog format | `check-changelog-format.mjs` | uses `CHANGELOG.md` | Keep a Changelog 1.1.0 + SemVer grammar |
| claims | `check-claims.mjs` | `claims` | capability numbers agree across surfaces and do not exceed a ground-truth floor |
| generator + freshness | `aahp-dashboard.mjs` | `generate` | an optional release journal (never the agent's `LOG.md`, ADR-004) stays in sync; a `Current version` header matches the package |

The acceptance-criteria lifecycle of README Section 8.7 is deliberately **not** in this table.
It ships as `aahp criteria`, an advisory report with no exit-code authority, for the
reason ADR-017 records.

The changelog validator and the release-journal generator import the release-heading grammar
from a single module (`scripts/changelog-grammar.mjs`), so the two cannot diverge.
The config shape is described by `schema/aahp-config.schema.json`; see
`aahp.config.example.json` for a worked example. Two more optional keys tune the
commands rather than an individual gate: `check` (`only` / `skip`) selects which gates
`aahp check` runs, and `pinnedDep` (`name` / `location` / `allowRange`) opts a repo into
the doctor pinned-dep gate (absent, it reports `skip`; `"pinnedDep": {}` asserts an
exact pin of `@elvatis_com/aahp` in `devDependencies`, and is what `aahp init --gates`
writes). The gates that enumerate tracked
files (`forbidden-patterns`, `doc-links`) fail loud outside a git work tree rather than
silently scanning zero files, so a misconfigured CI job cannot pass vacuously. `npm run
check` runs the gates and `npm run doctor` runs the conformance check; both run in CI.
The release ceremony these gates protect is in
[CONTRIBUTING.md](../CONTRIBUTING.md#releasing-aahp).

## Configuring the gates in a consumer repository

A consumer that pins `@elvatis_com/aahp` (README Section 10.4) also gets the config-driven gates by
adding an `aahp.config.json` (see `schema/aahp-config.schema.json` and
`aahp.config.example.json`). `versionSites` pins the package version across files, `claims`
pins capability numbers across surfaces, `forbiddenPatterns` denylists text (for example the
em-dash ban), `docSync` keeps duplicated value-sets in step, `docLinks` checks internal
Markdown links, and `generate` drives an optional release journal (a file such as
`docs/RELEASES.md`; the generator refuses `LOG.md`, `LOG-ARCHIVE.md`,
`LOG-ARCHIVE.index.json` and an unset target, ADR-004) plus a
`NEXT_ACTIONS.md` current-version freshness gate. `handoffImpact` carries the reviewed,
exact-file, M-only Layer 2 classifications (`nonImpactingModifiedFiles`) and the opt-in,
content-verified npm devDependency classification (`npmDevDependencyUpdates`, with its
mandatory `supplyChainScan`) described in README Section 2.8. Two selection keys
tune the surface:
`check` (`only`/`skip`) chooses which gates `aahp check` runs, and `pinnedDep`
(`name`/`location`/`allowRange`) opts the `doctor` pinned-dep gate in (absent, it is a clean
skip). `trustTtl` (`enforce`) opts verify Layer 4 in the same way: absent or false, expired
`verified` rows warn and the run still passes, which is what every existing repository
gets; true, and a failing check or a row expired past `graceDays` (default 14) fails it.
`trustTtl.checks` declares the executable checks a `TRUST.md` row may name (README Section 2.5). `acceptanceCriteria`
(`include`/`manifest`) supplies the input paths for the advisory `aahp criteria` report
of README Section 8.7; it configures no gate, because that report
is not one. Every section is optional.

One key is deliberately NOT part of `aahp check` and so is not inherited by a consumer
that runs it: `docPaths` configures `scripts/check-doc-shape.mjs`, which resolves
backticked repo-relative paths in the configured documents against the git index and
asserts that a required heading appears before a named anchor (ADR-023). It is a
repository-local gate in AAHP's own `check` npm-script chain, alongside
`check:runtime-support` and `check:workflow-pinning`. A consumer that wants it runs the
script by path. It exits 2, not 0 and not 1, on anything it could not assess.

**The config is validated against its own schema before any gate is evaluated.** This
matters more than it sounds: applicability is decided on the PRESENCE of a config key, so
a key misspelled by one letter used to be indistinguishable from a section that was never
written, and an absent section is a clean `SKIP`. `forbiddenPatterns` typed as
`forbiddenPaterns` therefore turned a FAILING gate into `Governance OK`, exit 0. An
invalid config is now an error: it names the offending key, suggests the closest valid one,
evaluates no gate, and the JSON record marks every gate `unevaluated` rather than `skip`,
so a dashboard can tell "asked, not applicable here" from "never asked". The validator is
dependency-free and ships in the package (ADR-002), and it REFUSES to run against a schema
keyword it does not implement rather than skipping it, because a validator that silently
ignores what it cannot evaluate reports "valid" for a document it never examined.

Run the gates two ways, invoking the pinned devDependency by path rather than by name -
`npx --no-install <name>` still asks the registry about a name that is not installed before
it refuses (ADR-013).
`node ./node_modules/@elvatis_com/aahp/bin/aahp.js check .` is the pass/fail RUN whose exit code
gates CI: it aggregates every applicable gate and continues past failures so one run surfaces
them all. The same binary with `doctor --json` emits the conformance RECORD a fleet
dashboard can aggregate. On a repo that does not use the handoff protocol, add `--governance`
(alias `--no-handoff`) so the three handoff gates skip and the record can still be green. The
tracked-file gates (`forbidden-patterns`, `doc-links`) scan git-tracked files and fail loud
outside a git work tree, so run them in a checkout (in CI, `actions/checkout`).

The fastest way to adopt all of this is `aahp init --gates`, which scaffolds a trimmed
`aahp.config.json` (the em-dash ban, internal doc links, and `"pinnedDep": {}`, so
`doctor` holds the exact pin from the first run), a `govern` npm script (`aahp check .`), and a portable
`.github/workflows/aahp-govern.yml` (verify-only, invoked by path, no vendored copy of the CLI) without
touching `.ai/handoff/`. Where `.ai/handoff/` already exists it also copies the adopter
`assets/governance/aahp-verify.yml` into the repository's workflows, so the handoff gate
and the governance gate arrive together. Without a handoff set it writes no verify
workflow, because `aahp verify` fails where there is no handoff set to gate, and prints
how to add it later: run `aahp init` and `aahp manifest`, then `aahp init --gates` again,
or copy the file. Every file that already exists is skipped unless `--force` is given,
and `--force` replaces a workflow wholesale. The one exception is this package itself (a
root `package.json` named `@elvatis_com/aahp`, the pinned-dep gate's `self`): there the
verify workflow is never written or replaced, because the package's own runs the gate
from the working tree (README Section 9.2).
