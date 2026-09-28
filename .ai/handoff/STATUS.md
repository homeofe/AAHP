# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change is the documentation workstream (branch docs/spec-split-and-redaction)

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
| Documentation | README split, ADR fixes, redaction of internal details | this change |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | ready, next (its gate needs this change first) |

## This change: documentation, specification split and redaction

Implements the owner's documentation decisions of 2026-09-28 and corrects the docs to
what the code does after #119 to #125.

- README split: README keeps the quickstart and the normative specification (sections 1
  to 10, numbers unchanged because code and templates cite them). The decision log moved
  to `docs/adr/` (one file per ADR plus an index), the governance-gate reference to
  `docs/governance.md`, and the release ceremony to CONTRIBUTING.md. Moved text is
  verbatim except for the corrections below. `docs/` is not shipped to npm (open item).
- STATUS.md is a bounded snapshot and LOG.md the only journal: README, templates and
  ADR-023 agree, merge rules are stated, and `.gitattributes` no longer sets
  `merge=union` for STATUS.md.
- Redaction: an internal hostname and figures about other repositories were removed
  from README, ADRs, CHANGELOG history and LOG.md (redacted in place, with a header note;
  LOG entries are otherwise never rewritten). New forbidden-pattern rules
  `no-internal-hostnames` (all text files) and `no-estate-counts` (Markdown), and a
  CONSTITUTION section on what public files may record.
- Claims without a mechanism or measurement removed or corrected: the schema as a "hard
  security boundary", a structural HTML-comment check, a nonexistent hook path, vendor
  pricing and reduction percentages, HANDOFF.lock "enforcing" single-writer access,
  "the counter increments automatically", `/handoff` as an AAHP command.
- CONSTITUTION marks each rule Enforced (naming its gate or test) or Convention, with
  the corrected ASCII rationale. CONTRIBUTING explains the per-PR handoff update,
  Dependabot handling and how to run tests. CHANGELOG discloses the versions never
  tagged or published, and its reference links now resolve.
- ADR cross-references corrected (provenance ADR-022, doc paths ADR-023) and guarded by a
  new `check:adr-refs` gate. Templates are ASCII and match the spec.
- Integrator: the scanner TRUST row is re-anchored to the push run on main at `f9b12ca`
  (catalog consulted); MANIFEST task notes are ASCII.

## Validation

- Workstream tree on a Linux runner: `npm test` 822 of 822; `npm run check` (13 gates,
  doc shape over 39 documents), `doctor`, lint and archive verify exit 0 once the two
  integrator lines the new `no-estate-counts` rule flagged were rewritten (they are, in
  this change). Every CHANGELOG release link returned HTTP 200 (20 of 20); behaviour
  claims (pinned-dep, acceptance-criteria binding, lint, generator field handling, init
  next steps) were checked by running the commands.
- Integrated onto `f9b12ca`: `CI=true npm test` 822 of 822, 0 skipped; `npm run check`,
  `doctor`, lint, archive verify, ajv and the PII validator exit 0.
- Not done here: shipped scripts, tests and hooks still cite "README ADR-NNN" and carry a
  few figures about other repositories in comments; they are corrected in the full-ASCII
  change, which owns those files.

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

1. `propagate.sh` now refuses a target that does not lock `@elvatis_com/aahp` (exit 3),
   because the installed workflow cannot run without it. Is a non-npm consumer a supported
   case?
2. Should `aahp init` gain an option to scaffold the adopter verify workflow?
3. Keep the dogfood workflow out of the npm package (this change removes it)?
4. Legacy adopter copies of the governance workflow: doctor detection or a force-upgrade
   path beyond the migration note.
5. Replacement of `ajv-cli@5.0.0`, whose transitive tree emits deprecation warnings for
   `glob@7.2.3` and `inflight@1.0.6` (no vulnerability reported, no newer release).
6. The test runner now refuses a first-on-PATH bash older than 4.1 (macOS `/bin/bash` is
   3.2), because bats cannot fail a non-final `[[ ]]` there. Keep the refusal (override
   `AAHP_ALLOW_OLD_BASH=1`), or convert assertions instead?
7. Release train: the new manifest summaries break one assertion in supply-chain-guard
   (`src/__tests__/handoff-gate.test.ts` line 256 expects the old table-header summary `|
   Field | Value |` for STATUS.md). That test needs a one-line update when
   supply-chain-guard next bumps @elvatis_com/aahp.
8. Should lint's PII scan also read JSON string values (task notes, `assigned_to`)? It
   currently scans Markdown only, to avoid new failures in consumers.
9. Publish environment: a GitHub environment (for example `npm-publish`) with a tag
   deployment rule, bound in the npm trusted-publisher config, would also stop a workflow
   that was edited at the tagged commit, which the new guard step cannot. Needs a
   repository setting and the npm-side binding.
10. `refresh-catalog: true` merges the scanner's live feed for 24 hours, so the required
   scanner check can turn red with no AAHP diff when a new indicator matches. Keep it, or
   pin the catalog?
11. Upstream, for supply-chain-guard: its Action does not content-scan extensionless shell
   files (the shipped git hooks) or `.bats` files, and installs
   `supply-chain-guard@<version>` by version rather than by integrity.
12. Consumer manifests that still carry template placeholder dates will fail `aahp doctor`
   after upgrading. The CHANGELOG carries the migration note; should those repositories be
   fixed before the release?
13. `docs/` (the ADR log and the governance reference) is not shipped to npm, so messages
   in shipped code that cite an ADR point at a file that exists in the repository but not
   in `node_modules`. Ship `docs/`, or cite repository URLs?
14. LOG.md may now be redacted for confidentiality as a protocol rule (README 1.3,
   templates/LOG.md), and LOG-ARCHIVE.md was ASCII-normalised with a re-hashed index
   entry. Confirm both as protocol rules.
15. Should `aahp init --gates` write `"pinnedDep": {}` so the exact-pin advice is enforced
   by default? Today the pinned-dep gate reports skip until it is configured.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
