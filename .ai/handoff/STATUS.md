# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change is full ASCII (branch fix/full-ascii), the last workstream; with it the audit fix programme is complete

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
| Full ASCII | replace non-ASCII in tracked text, widen the gate | this change |

## This change: full ASCII and the remaining redaction in code

Implements the owner decision "full ASCII + gate" of 2026-09-28 and finishes the
redaction in files the documentation change did not own.

- New gate `scripts/check-ascii.mjs`, run as `check:ascii` at the end of `npm run check`:
  every tracked text file must be pure ASCII (no code point above U+007F, no byte order
  mark). It reports `file:line:column` and the code point, exempts binary files (NUL
  byte), ignores untracked files, and exits 2 when it cannot assess. It is repository
  local, not one of the gates consumers inherit. The whole tree passes: 169 tracked text
  files.
- About 2,550 non-ASCII characters removed from scripts and tests, almost all box-drawing
  rulers in comments. `lint-handoff.sh` prints `OK`, `x` and `!` instead of check marks,
  crosses and a warning sign; message text is unchanged. Tests that exercise Unicode
  already generated their bytes at runtime; the manifest truncation test now puts
  multi-byte characters across the real cut point (before, a byte-based or UTF-16 cut
  passed it).
- A JSON Schema section number in a comment that the supply-chain scanner reported as a
  private IPv4 address (a false positive since #122) is reworded.
- Figures about other repositories removed from code comments, one printed message and
  tests; the `no-estate-counts` rule now reads every tracked file, not only Markdown.
- References to README ADR sections now point at the per-decision files in `docs/adr/` (in shipped
  templates and hooks as "AAHP docs/adr/..."); provenance tests cite ADR-022 and doc-shape
  tests ADR-023; `aahp migrate` reports only the `summary` section marker AAHP reads.

## Validation

- Workstream tree on a Linux runner (base `eaa6aac`, the tree of `aa17c1f`): `CI=true npm
  test` 851 of 851, 0 skipped; `npm run check` with all 14 gates, `doctor`, lint,
  archive verify and ShellCheck over every tracked shell file exit 0. Mutation proofs
  for the gate (BOM, binary exemption, threshold, unreadable file, empty enumeration,
  invalid UTF-8, git missing, the real tree), the widened estate rule, the doctor
  reason assertion and the migrate marker check.
- Integrated onto `aa17c1f`: `CI=true npm test` 851 of 851, 0 skipped; `npm run check`
  (14 gates, 169 files ASCII), `doctor`, lint, archive verify, ajv and the PII validator
  exit 0.
- Not measured: macOS.

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
16. Release: the programme is complete on main. Everything under CHANGELOG `##
   [Unreleased]` is unreleased; whether and when to release (and which version: the
   content includes breaking changes for adopters, see the Migration notes) is the owner's
   decision.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
