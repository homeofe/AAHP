# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0 (released 2026-08-31); unreleased changes: CHANGELOG.md `## [Unreleased]`
Protocol version: 3.0
Working state: audit fix programme in progress; this change is CI, release and dependency automation (`fix/ci-release-automation`)

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
| CI and release | scanner on tags, publish guard, Dependabot grouping and cooldown | this change |
| Documentation | README split, ADR fixes, redaction of internal details | next, after this change |
| Full ASCII | replace non-ASCII in tracked text, widen the gate | last |

## This change: CI, release and dependency automation

- Supply-chain scan: the job now also runs on release tags and dispatches, and both
  `publish` and `release` need it. It consults the historical threat catalog
  (`refresh-catalog: true`; PR #119's run had used bundled indicators only). The
  contract test asserts invariants instead of one literal SHA: a 40-hex pin with a
  `# v6.x.y` comment, the policy `$schema` anchor on the same commit, least privilege, no
  policy input. A v6 Dependabot bump no longer fails by construction; a v7 bump still
  does, on purpose.
- Publish guard: a new step refuses any ref that is not a `vMAJOR.MINOR.PATCH` tag equal
  to the package.json version whose commit is reachable from `main`. The publish job
  installs nothing, restores no cache and runs `npm publish --ignore-scripts`, so no
  dependency or lifecycle code runs while it holds `id-token: write` (the tarball is
  byte-identical without `node_modules`). `prepublishOnly` therefore no longer runs in
  CI; the required jobs on the same commit run the same checks.
- Required jobs install with `npm ci --ignore-scripts`, and ShellCheck is a pinned v0.9.0
  release verified by sha256 instead of whatever apt ships with the runner image.
- Dependabot (owner decision "group"): one grouped version-update PR per ecosystem with
  a 7-day cooldown; security updates are neither grouped nor delayed.
- `check-workflow-pinning.mjs` gains rules H (the shipped governance template pins the
  same SHAs as the workflows), I (`npm ci --ignore-scripts`), J (an `npx` only after
  `npm ci` in the same job) and K (grouped, cooled-down Dependabot lanes); rule B also
  rejects `npm exec` and `npm x`.
- `npx --no-install` documentation now matches the measurement on npm 10, 11 and 12:
  `npx` sends one metadata request for a missing package and then refuses; `npm exec
  --no-install` on npm 10 and 11 downloads and runs it. Corrected in ADR-013, README 2.1
  and 11.1, CLAUDE.md, both hooks, both shipped workflow templates and a test comment.
- The bats suite runs once per Node runtime per push instead of three times.
- Includes Dependabot #123 unchanged (CodeQL v4.37.9 to v4.38.2; pin `2892aa5` is the
  commit the v4.38.2 tag resolves to).

## Validation

- Workstream tree on a Linux runner: `npm test` 659 of 659; 26 mutation proofs, each red
  with its fix reverted and green restored. npx behaviour measured against a logging
  local registry on npm 10.9.9, 11.20.0 and 12.0.2.
- Integrated onto `9416ed0` with #123 and the corrected comments: `CI=true npm test` 812
  of 812 after the rebase, 0 skipped; `npm run check`, `doctor`, lint,
  archive verify, ajv and the PII validator exit 0.
- Only a real GitHub run proves: the ShellCheck download and its sha256 (the step fails
  closed on a mismatch, so this pull request's own run is the proof), `refresh-catalog`
  inside the Action, Dependabot accepting `groups` and `cooldown`, and the publish guard
  on a real tag. No tag, release or publish was made.

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
10. Publish environment: a GitHub environment (for example `npm-publish`) with a tag
   deployment rule, bound in the npm trusted-publisher config, would also stop a workflow
   that was edited at the tagged commit, which the new guard step cannot. Needs a
   repository setting and the npm-side binding.
11. `refresh-catalog: true` merges the scanner's live feed for 24 hours, so the required
   scanner check can turn red with no AAHP diff when a new indicator matches. Keep it, or
   pin the catalog?
12. Upstream, for supply-chain-guard: its Action does not content-scan extensionless shell
   files (the shipped git hooks) or `.bats` files, and installs
   `supply-chain-guard@<version>` by version rather than by integrity.

## Constraints for the next agent

- Integrate one workstream per pull request and let CI settle before the next merge.
- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a new
  check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
