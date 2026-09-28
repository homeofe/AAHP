# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change is the manifest, lint and CLI workstreams (`fix/manifest-lint-cli`)

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
| CLI | signal exit codes, doctor schema validation, migrate, help | this change (together with the manifest workstream) |
| Manifest, lint and shared lib | JSON generation, binary-safe scans, injection scan scope, template | this change |
| Verify gate semantics | executable TRUST claims with grace, content-based Layer 2 exemption, Layer 3 | ready, next |
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | ready |
| Documentation | README split, ADR fixes, redaction of internal details | after the code workstreams |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | last |

## This change: manifest generator, lint and CLI

Two workstreams in one pull request, because the stricter doctor gate below needs the
corrected MANIFEST template to keep a fresh adopter green.

Manifest and lint:

- `aahp manifest` builds MANIFEST.json in one node process with `JSON.stringify` and
  replaces it atomically. A TAB, a quote in `--agent` or a multi-byte character at a
  truncation point used to write invalid JSON or invalid UTF-8 with exit 0. Checksum
  failures, a missing node, and an existing manifest whose fields cannot be carried over
  now exit 1 with the file unchanged (`--force` overrides the last case).
- `files.*.updated` keeps its date while the checksum is unchanged; summaries skip
  tables, JSON punctuation and labels; `token_budget.manifest_only` is measured instead of
  the constant 85. Generation for this repository on Windows: 9.3 s to 0.8 s.
- `aahp lint` scans bytes as text (`grep -a`, `LC_ALL=C`): one NUL byte used to hide a
  secret and an email address from the scan on GNU grep 3.5 or later. A scan that cannot
  complete is a violation. The injection scan covers every handoff file and the decoded
  JSON string values, including MANIFEST.json, which agents read first.
- The conflict-marker check reads git-listed files and exits 2 when it cannot run, which
  lint no longer reports as "markers found".
- `templates/MANIFEST.json` validates against the schema after `init` + `manifest`: the
  example tasks lost their `"created": "[ISO-8601]"` placeholder, `aahp_version` is 3.0
  and the phase list is complete.

CLI:

- A gate script killed by a signal made the CLI exit 0; it now exits 128 plus the signal
  number.
- `aahp doctor`'s manifest-schema gate validates the whole schema (enums, lengths, extra
  keys, RFC 3339 dates) with the in-repo validator instead of a structural subset
  reported as conformance; a parity test runs 45 manifests through ajv and the validator.
- `check --json` stays JSON for an unknown gate id; `status` counts manifest lines;
  `migrate` gains `--yes` and no longer claims to split LOG.md; the release-journal
  generator refuses the agent journal and the example points at `docs/RELEASES.md`.
- Help and README document archive's Python requirement, `--keep`, `--force` and every
  `--level`.

## Validation

- Each workstream on a Linux runner: manifest 631 of 631 with mutation proofs M1 to M7;
  CLI 635 of 635 with 22 of 22 mutation proofs.
- Combined and rebased onto `1e3fd4a`, integrator run on a Linux runner: `CI=true npm
  test` 709 of 709 after the rebase, 0 skipped; `npm run check`, `doctor`, lint, archive
  verify, ajv and the PII validator exit 0.
- This repository's MANIFEST.json is regenerated with the new generator in this change.
- Estate impact, measured read-only on 30 consumer manifests: ajv and the new validator
  agree on all 30; three manifests newly fail doctor because they still carry template
  placeholder dates.
- Not measured: macOS, and the rewritten `aahp-migrate-v2.sh` under bash 3.2.

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
8. Three consumer manifests will fail `aahp doctor` after upgrading, because they still
   carry template placeholder dates. The CHANGELOG carries the migration note; should
   those repos be fixed before the release?
9. Should lint's PII scan also read JSON string values (task notes, `assigned_to`)? It
   currently scans Markdown only, to avoid new failures in consumers.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
