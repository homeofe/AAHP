# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change implements the owner's follow-up decisions (branch fix/owner-decisions-followup)

## Current objective

On 2026-09-28 the owner asked for everything a full audit of the repository found to be
fixed: scripts, gates, tests, CI and documentation. The findings were split into
workstreams with disjoint file scopes. Each lands as its own pull request, one at a
time, with CI settling between merges. Nothing is released until the owner decides, after
all fixes are in.

## Audit fix programme

| Workstream | Scope | State |
|------------|-------|-------|
| Dependency integration | five Dependabot PRs, scanner v6.3.1, expired TRUST rows | merged, #119 (`1917ca8`) |
| Consumer install path | adopter verify workflow, propagate, install-hooks | merged, #120 (`3e8e8d7`) |
| Test-suite integrity | vacuous assertions, fail-open skips, git isolation, fixture speed | merged, #121 (`1e3fd4a`) |
| CLI | signal exit codes, doctor schema validation, migrate, help | merged, #122 (`d27db82`) |
| Manifest, lint and shared lib | JSON generation, binary-safe scans, injection scan scope, template | merged, #122 (`d27db82`) |
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | merged, #124 (`9416ed0`) |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | merged, #125 (`f9b12ca`) |
| Documentation | README split, ADR fixes, redaction of internal details | merged, #126 (`aa17c1f`) |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | merged, #127 (`21a2ac7`) |

## This change: owner follow-up decisions

The owner answered the open questions of the audit fix programme on 2026-09-28 and
asked for the rest to be decided on technical grounds. This change implements both.

Decided by the owner:

- `aahp init --gates` scaffolds `"pinnedDep": {}` and the adopter verify workflow
  (`.github/workflows/aahp-verify.yml`, copied from `assets/governance/aahp-verify.yml`)
  when `.ai/handoff/` exists; without a handoff set it prints how to add it later. It
  never writes the workflow into this package itself, whose own workflow runs the
  working-tree gate.
- Lint's PII check also reads the decoded string values of the JSON handoff files
  (`MANIFEST.json`, `LOG-ARCHIVE.index.json`), names the JSON path of a finding, and
  still excludes `pii-allowlist.json`.
- `docs/` stays out of the npm package.

Decided on technical grounds, as the owner asked:

- `propagate.sh` keeps refusing a target without a lockfile that pins
  `@elvatis_com/aahp` (exit 3): the tool needs Node anyway, and a lockfile-pinned
  devDependency is the only install with integrity. The message now lists the exact fix,
  and README/ROLLOUT state that non-JavaScript repositories adopt AAHP with a
  `package.json` that only pins the tool.
- The test runner keeps refusing a bash older than 4.1, where a failing non-final `[[ ]]`
  cannot fail a bats test, so a green run proves nothing; the message names the macOS fix.
- `refresh-catalog: true` stays: a newly listed indicator matching an existing dependency
  is the information the scan exists for, and a failed download reports a finding
  instead of failing the check.
- LOG redaction is a protocol rule with a visible marker `[redacted: <reason>]`; a
  redaction inside LOG-ARCHIVE.md is recorded with the new `aahp archive --reindex`,
  which prints every hash it drops and records. The two bare markers in this
  repository's archive were normalised and re-indexed.
- The dogfood verify workflow stays out of the npm package: it runs the gate from an
  AAHP checkout and cannot run anywhere else.

Also: supply-chain-guard received homeofe/supply-chain-guard#354 (the section-number
false positive and a handoff test that no longer pins aahp 3.12.0 summaries); it is open
for that repository's maintainer to merge before its 6.3.2 release.

## Validation

- Workstream tree on a Linux runner: `CI=true npm test` 872 of 872; mutation proofs for every item (pinnedDep, verify workflow with and without
  a handoff set, the PII JSON scan, allowlist exclusion, JSON path label, the propagate
  and run-bats messages, `--reindex` printing and writing).
- A scaffolded adopter (registry install of 3.12.0 overlaid with this tree, `init`,
  `manifest`, `init --gates`) passes `aahp doctor` and `aahp check`; a caret range fails
  the pinned-dep gate.
- Integrated onto `21a2ac7`: `CI=true npm test` 872 of 872, 0 skipped; `npm run check`,
  `doctor`, lint, archive verify, ajv and the PII validator exit 0.

## Owner decisions

Decided on 2026-09-28:

- Full ASCII in tracked text, enforced by a gate (supersedes the U+2014-only question).
- Dependabot: grouped updates plus an opt-in, content-based Layer 2 exemption for
  dev-only lockfile changes. Never actor-based.
- TRUST-TTL: executable claims checked on every run, and a grace period for judgment rows.
- STATUS.md is a bounded snapshot; LOG.md is the only journal.
- README split into quickstart and normative spec, with ADRs and governance moved to
  `docs/`.
- Internal hostnames and estate figures are removed from public files.
- Repository settings applied: `Supply chain guard` is a required check on main, an active
  ruleset protects `refs/tags/v*`, and `sha_pinning_required` is on.
- No release until the owner decides, after all workstreams have landed.

Open:

1. Legacy adopter copies of the governance workflow: doctor detection or a force-upgrade
   path beyond the migration note.
2. Replacement of `ajv-cli@5.0.0`, whose transitive tree emits deprecation warnings for
   `glob@7.2.3` and `inflight@1.0.6` (no vulnerability reported, no newer release).
3. Publish environment: a GitHub environment (for example `npm-publish`) with a tag
   deployment rule, bound in the npm trusted-publisher config, would also stop a workflow
   that was edited at the tagged commit, which the new guard step cannot. Needs a
   repository setting and the npm-side binding.
4. Consumer manifests that still carry template placeholder dates will fail `aahp doctor`
   after upgrading. The CHANGELOG carries the migration note; should those repositories be
   fixed before the release?
5. Release: the programme is complete on main. Everything under CHANGELOG `##
   [Unreleased]` is unreleased; whether and when to release (and which version: the
   content includes breaking changes for adopters, see the Migration notes) is the owner's
   decision.
6. supply-chain-guard follow-ups, for that repository: homeofe/supply-chain-guard#354
   awaits its maintainer's merge; still open there are content-scanning extensionless
   shebang scripts and `.bats` files, installing the scanner by integrity rather than by
   version in its Action, its actor-based Dependabot exemption from `aahp-verify` (the
   content-based `npmDevDependencyUpdates` exemption can replace it), and its STATUS.md,
   still a prepend log.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
