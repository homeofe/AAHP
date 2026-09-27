# AAHP: Current Status

Last updated: 2026-09-28
Current package version: 3.12.0
Protocol version: 3.0
Working state: v3.12.0 released; dependency integration on `chore/deps-2026-09`, pending CI and merge

## Current objective

Integrate the five Dependabot pull requests that had been open for up to four weeks
(#112, #113, #115, #117, #118) through one replacement pull request, and restore
`aahp-verify`, which was failing on every pull request for two independent reasons.

## Why aahp-verify was red on every pull request

1. **Layer 2 (content drift), Dependabot only.** Dependabot does not write handoff
   state, so each of its pull requests changes a tracked file outside `.ai/handoff/`
   without moving STATUS.md and MANIFEST.json. The gate is correct; this is the
   recurring case first recorded for #97, and the owner decision on it is still open
   (item 2 below).
2. **Layer 4 (TRUST-TTL), every pull request.** Two `verified` rows in TRUST.md expired
   on 2026-09-22 and `trustTtl.enforce` is on, so from that day the required check
   failed on any pull request regardless of its content. Measured on 2026-09-28 with
   `bash scripts/verify-handoff.sh . --level ci`: "2 of 3 'verified' trust entr(ies)
   expired". The third row, the scanner, would have expired on 2026-09-30.

## Implemented in this working tree

- Cherry-picked unchanged, keeping Dependabot as author: `yaml` 2.9.0 to 2.9.1 (#117),
  `js-yaml` 3.15.1 to 3.15.2 (#115), the CodeQL `init`/`autobuild`/`analyze` group
  v4.37.8 to v4.37.9 (#113), and `fast-uri` 3.1.5 to 3.1.7 (#112). All three lockfile
  integrity hashes equal `npm view <pkg>@<version> dist.integrity`, and the CodeQL pin
  `cdf488f595d80d6e07e03d4674febd5ab45fa938` is the commit the v4.37.9 tag resolves to.
- Advanced supply-chain-guard from v6.0.8 to v6.3.1 instead of #118's v6.2.0, because
  v6.3.1 is the current release (2026-09-26). The signed annotated tag v6.3.1
  (`verified=true`) resolves to `013febcb8447107bcf9d82e400d5b492d44bb10f`. The
  `action.yml` diff from v6.0.8 adds one optional input, `refresh-catalog` (default
  `"false"`); `comment-on-pr` is unchanged and there is still no `policy` input. The
  `policy-schema.json` diff adds only an optional `catalog` key, so the empty `{}` policy
  stays valid. Workflow pin, policy schema anchor and the pinned bats contract moved
  together.
- Re-verified both expired TRUST rows against the tree instead of re-stamping their
  dates: `templates/` holds exactly the 12 listed files (tracked and on disk), and
  `package.json` still declares `Apache-2.0`, matching LICENSE.
- Re-anchored the scanner TRUST row (due 2026-09-30) to this pull request's own
  `Supply chain guard` run 36356352306 on v6.3.1: risk 10/100 (LOW), the two known
  medium heuristics on the release workflow, bundled indicators only.

## Validation

Run locally on Windows in this worktree:

- `npm ci` resolves `yaml@2.9.1`, `js-yaml@3.15.2` and `fast-uri@3.1.7`.
- `node scripts/check-workflow-pinning.mjs` exits 0.
- Mutation proof for the scanner contract, with only that bats test selected: the new
  pin passes; reverting `ci.yml` to the v6.0.8 pin fails it at
  `tests/workflow-pinning.bats` (line 704); restoring it passes again.

NOT run locally: the full bats suite (80+ minutes on this machine) and ShellCheck (no
shell script changed). The Linux CI run on the replacement pull request is the full-suite
verdict: every check on #119 at `fb51113` passed, including both runtime-matrix legs, `aahp-verify`
and `Supply chain guard`.

## Pull request and release state

- v3.12.0 is released: tag `v3.12.0` is `a56df50`, the GitHub Release was published
  2026-08-31T11:27:06Z, and npm reports 3.12.0 as the current version.
- Dependabot #112, #113, #115, #117 and #118 are to be closed as superseded once the
  replacement pull request is merged, following the #109 / #110 precedent.
- No release is planned for this change. Every bump is a devDependency or a CI workflow
  pin, so the published package's behavior does not change.

## Owner decisions and follow-up

These are decisions, not ready autonomous tasks, so the MANIFEST task graph remains at
5 done, 0 ready, and 0 blocked.

1. Decide whether the documented invariant should prohibit only U+2014 (the implemented
   gate) or require full ASCII. Thirty tracked files currently contain non-ASCII text, so
   claiming full ASCII and enforcing only one character are inconsistent.
2. Decide whether future Dependabot action bumps should be repaired manually or receive
   a bot-authored handoff update. Do not bypass Layer 2 merely because a change is
   action-only. Still open: #112 to #118 were again repaired by hand, after sitting red
   for up to four weeks.
3. Decide whether old adopter copies of the governance workflow need doctor detection or
   a targeted force-upgrade path beyond release-note remediation.
4. Decide whether the now-proven scanner job should become a required status check. Its
   first real CI success is recorded as a time-bounded `verified` TRUST row.
5. Track replacement of `ajv-cli@5.0.0`. Its current transitive tree emits deprecation
   warnings for `glob@7.2.3` and `inflight@1.0.6`, although npm reports no vulnerability
   and no newer `ajv-cli` release is available.
6. Decide how an enforced TRUST-TTL should behave in an idle repository. With
   `trustTtl.enforce` on, a required check turns red on a calendar date with no code
   change, as it did here on 2026-09-22. Rows whose verification is a deterministic
   command (template count, license match) could be re-verified by the gate itself.

## Constraints for the next agent

- Preserve the scanner job's read-only permissions and immutable pins.
- Do not add a broad scanner suppression merely to make low-severity output empty.
- Re-verify a TRUST row against the tree before moving its date; a new date without a
  new check is a verdict nobody produced.
- Regenerate MANIFEST.json after every handoff-file change.
