# Changelog

All notable changes to `@elvatis_com/aahp` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses semantic
versioning (`aahp_version` in `MANIFEST.json` tracks the file-format contract and moves
independently of the npm version).

> Publishing note: npm releases lapsed after `3.2.1` because the CI publish workflow was
> disabled, so `3.3.0` and `3.4.0` were developed in the repository but never published.
> `3.5.0` is the first npm release since `3.2.1` and ships everything below it.

## [Unreleased]

### Added
- `aahp doctor` gains a `verify-workflow` gate that answers, from inside a consumer,
  whether the workflow hosting the AAHP gate can skip it. Wrapping the `aahp-verify`
  job in an `if:`, or wrapping the gate step inside it, leaves a REQUIRED status check
  that keeps its name and reports success having evaluated nothing: Layer 1 MANIFEST
  checksum integrity is skipped along with the Layer 2 drift gate, and branch
  protection is satisfied by a verdict nobody produced. AAHP could not see this
  before, because the workflow it ships and `propagate.sh` copies is unconditional,
  so the weakening only ever exists in the consumer's copy. Since the canonical
  workflow's last step runs `aahp doctor`, a repository that has weakened its gate
  now reports it on its own pull requests.
  What is asserted is the consequence ("there exists an event on which this workflow
  concludes success without having run the gate at `--level ci`"), not the file's
  shape. Five findings cover it: `job-conditional`, `job-soft-failing`,
  `ci-step-conditional`, `ci-step-soft-failing` and `no-ci-level`. A repository whose
  workflows never run the gate reports `skip`; one whose workflow hosts the gate but
  cannot be classified reports `fail`, because undecided is not clean. Two shapes are
  deliberately not findings because they fail CLOSED, not green: an `if:` on the
  checkout step alone, and `paths:` filters that stop the workflow triggering.
  The gate ships no YAML dependency, because AAHP has no runtime dependencies, so
  `tests/assert-workflow-parser-parity.mjs` holds its block-YAML reader against a real
  parser on every workflow and fixture in this repository, on the fields the audit
  reads and on the resulting findings.
- `npm run check:runtime-support` asserts that the runtimes CI exercises and the
  runtimes `engines.node` publishes are the same set, and that the floor of that set
  still receives security patches. It is a RELATION rather than a list of dead
  versions, so it cannot rot: both sides move together or the gate goes red. Exactly
  one dated constant is kept (`SUPPORTED_FLOOR`, measured 2026-08-21). Pins it cannot
  evaluate - a non-matrix `${{ }}` expression, or `node-version-file` - fail rather
  than being skipped, and a state it cannot classify at all exits 2 rather than 0, so
  "I could not look" never reads as "I looked and it was fine".
- A `runtime-matrix` CI job exercises the whole published range (Node 22 and 24), not
  only its floor. The gate binds that matrix directly: emptying it or cutting it to a
  single entry is red even though the standalone pins in the other jobs would keep a
  global pin list populated.

- `tests/assert-workflow-hardening.mjs` asserts both properties over
  `.github/workflows/` **and** `assets/governance/`, so a workflow added without them is
  a red required check rather than a note in a review. It runs under `npm test`, which
  the required `lint-and-validate` job executes, so it has teeth on every pull request
  with no new CI wiring. It exits 2 rather than 0 on anything it cannot decide: a
  `${{ }}` expression it cannot evaluate, a job delegating to a reusable workflow whose
  steps are not visible, or a scan root that is missing or empty. Scanning zero files is
  reported, never treated as finding nothing wrong. Exemptions for a job that genuinely
  needs the checkout credential live in `CHECKOUT_CREDENTIAL_EXEMPTIONS` inside the
  gate, are reviewed as a code change, and print their reason on every run; the list is
  empty, and that is measured rather than assumed, since no workflow here runs
  `git push`, `git commit`, `git fetch`, `git pull` or `git remote`. See ADR-020.
- `tests/assert-repo-ci-shape.mjs` additionally pins the three job-level elevations by
  name. A job-level `permissions:` REPLACES the top-level block rather than merging with
  it, so once `ci.yml` and `codeql.yml` gained a top-level `contents: read`, deleting a
  job block as redundant would silently strip an elevation whose failure would only
  surface on a release tag. That gate takes the root to assert as an argument, and it no
  longer reads any file unguarded: a recorded workflow the given root does not contain is
  named on stderr as NOT asserted, and a workflow that is present but unreadable,
  unparseable or empty is a failure. Previously an absent workflow threw `ENOENT`, so the
  process exited 1 with a stack trace and none of the gate's own findings - the right
  exit code for the wrong reason, and no message to tell the two apart.

### Changed
- `engines.node` is now `>=22`, was `>=18`. Node 18 reached end of life on 2025-04-30
  and Node 20 on 2026-04-30, so the package publicly claimed support for a runtime it
  could not have security-patched, and every repository in the estate inherited that
  claim on install. Consumers still running Node 18 or 20 will now see an engine
  warning, which is the intended signal.
- CI validates on Node 22 instead of Node 20, in `ci.yml`, `aahp-manifest.yml` and the
  `aahp-verify.yml` reference workflow that `propagate.sh` installs into consumers. The
  publish job stays on Node 24, and the gate now enforces that the release path is
  never older than the build path.
- `yaml` is added as a devDependency (zero transitive dependencies) so the new gate
  PARSES the workflow files. Matching YAML with a regex misreads quoting and block
  scalars, and would report a clean repository it never actually read.

### Fixed
- `MANIFEST.json`'s `project` no longer takes the name of the directory the generator
  ran in. It resolves the repository's identity instead: the name already on record in
  `MANIFEST.json` first, then the git remote's repository name, and the directory
  basename only for a genuinely new manifest in a repository with no remote. A
  `git worktree` checkout is named after the branch and a CI workdir after the job, so
  the old behaviour rewrote `project` to that name on every regeneration, silently,
  unless somebody re-read the file afterwards. Two such names reached consumer main
  branches.
- An unsubstituted `[PROJECT]` placeholder, which `aahp init` copies in from
  `templates/MANIFEST.json`, is no longer carried forward as though it were a chosen
  name. It falls through to the remote-derived name.
- The remote-derived name needs only `git`, so the project name is now correct where
  `node` is absent (a stripped hook `PATH`, a slim CI image). That path previously fell
  back to the directory basename with no diagnostic, because the warning about failing
  to read the existing manifest sits inside the `command -v node` guard.
- The `project` value is escaped for JSON on write, as the quick context already was, so
  a quote or backslash in a preserved name or a directory basename cannot emit a
  `MANIFEST.json` that no longer parses.
- Committed handoff state and one gate comment no longer name private repositories. This
  repository is public and ships to npm, so naming consumer repositories here published
  a list of them to anyone reading the repository or the package. The `What is Missing`
  row keeps every measurement it carried (six consumers report `bypassable`, three
  report `enforced`, and one of the six is only partly corrected) and now states those
  counts without identities. `.ai/handoff/` is outside the `files` list, so the row
  itself never reached the npm tarball, but `scripts/` is inside it, so the comment in
  `check-runtime-support.mjs` would have shipped on the next publish.
- A `no-private-repo-names` forbidden-pattern rule keeps most such names out. The same
  names had already been removed once, from the propagation playbook, and returned in a
  later change because nothing gated them. The rule matches on shape rather than on a
  list, so the gate does not itself have to enumerate the repositories it protects - but
  the shape it matches is one naming prefix, and that covers seven of the eight consumer
  identities the row was built from, not all eight. The eighth is a bare product word
  carrying no shared prefix, and nothing in its shape separates it from ordinary prose.
  Measured on this branch: a tracked file reintroducing that eighth name leaves the gate
  reporting `Forbidden patterns OK: 2 rule(s), no matches.` and exiting 0, while the same
  file carrying a prefixed name exits 1. It was removed from the row by hand and stays
  out by review, not by the gate. Adding it to the rule is not the fix, because the rule
  lives in a tracked config file in this public repository and would then publish the one
  identity this change exists to withhold.

### Security
- The portable governance workflow AAHP ships, `assets/governance/aahp-govern.yml`, now
  declares `permissions: contents: read` and sets `persist-credentials: false` on its
  checkout. This is the change with reach beyond this repository: `aahp init --gates`
  copies that file into a consumer repository and `npm pack` puts it in the published
  tarball, so until now every adopter received a workflow that inherited whatever
  `default_workflow_permissions` their repository was set to and left the job's
  `GITHUB_TOKEN` in `.git/config` for every later step to read, including everything
  `npm ci` and `aahp` execute. AAHP cannot see an adopter's repository visibility, their
  default, or an organization default that grants `write`, so the workflow now states
  what it needs instead of inheriting it. The header explains both lines in place.
  **Adopters who already scaffolded the file keep their old copy:** `aahp init --gates`
  skips a workflow that already exists. Re-run it with `--force`, or add the two lines
  by hand, to pick this up.
- The six repository workflows that had no top-level `permissions:` block now declare
  `contents: read` (`aahp-archive.yml`, `aahp-lint.yml`, `aahp-manifest.yml`,
  `aahp-pii-allowlist.yml`, `ci.yml`, `codeql.yml`), and ten more `actions/checkout`
  steps set `persist-credentials: false`: the nine in `.github/workflows/` plus the one
  in `assets/governance/aahp-govern.yml`, the template this package ships to consumers.
  Nine is the `.github/workflows`-only figure and leaves out that template, which is the
  file in this change with reach beyond this repository. Counted across both locations
  the repository holds eleven checkout steps; exactly one, in `aahp-verify.yml`, already
  set the flag, so after this change all eleven set it. The job-level elevations
  are unchanged and still override the top-level block: `publish` keeps
  `id-token: write` for OIDC trusted publishing, `release` keeps `contents: write` for
  `gh release create`, and the CodeQL `analyze` job keeps `security-events: write` for
  its SARIF upload.
  Stated plainly, because the change should not be read as fixing an exploitable defect
  in this repository: it is not. This repository is public, its
  `default_workflow_permissions` is `read`, every job runs on a throwaway hosted runner,
  and the owner is a user account with no organization layer, so a read-only token in a
  public repository's workspace grants nothing an anonymous clone does not. The value is
  that a declared block cannot be widened by a settings change with no diff to review,
  and that it is measurably narrower even today: an inheriting job here is granted
  `Packages: read` on top of `Contents` and `Metadata`, and a declaring job is not.

## [3.10.0] - 2026-08-20
**Fail-closed Layer 2 base selection and reviewed exact-file impact classification**

### Added
- `handoffImpact.nonImpactingModifiedFiles` provides an optional, reviewed Layer 2
  classification for maintenance-only files. Each entry requires one exact
  repo-relative regular tracked `file` and a reviewable `reason` containing a visible
  letter or number. Only a content-only modification (`M`) whose old and new regular-file
  modes match can be non-impacting; additions, deletions, renames, copies, type changes, and
  mixed source changes remain impacting. Every applied classification logs the file and
  reason.
- `aahp verify --base SHA` and its `AAHP_BASE_SHA` environment equivalent anchor the
  Layer 2 diff explicitly. The required workflow passes the pull request base SHA for a
  pull request, the event `before` SHA for a push, and a required input for a manual run.

### Fixed
- `--level ci` no longer guesses a base or permits a vacuous HEAD-versus-HEAD diff.
  Missing, all-zero, malformed, unreadable, HEAD-equal bases and any git diff failure
  are blocking findings rather than empty change sets that can report green. The gate
  compares base and HEAD endpoint trees so a rollback or force-push cannot collapse to
  an empty merge-base-to-HEAD diff.
- The required workflow no longer bypasses verification for an actor. Layer 1 now runs
  for every change, including automated dependency updates.
- The optional impact parser fails closed without relying on an external schema command:
  malformed JSON and types, non-standard numeric constants, empty or invisible reasons,
  control or format characters, absolute or traversal paths, globs and
  metacharacters, directories, untracked paths, symlinks, gitlinks, handoff paths,
  the config itself, duplicate JSON keys, duplicate entries, and prefix-like ambiguity
  are rejected. The policy file itself must be a regular tracked Git object; a symlink
  cannot delegate policy to a mutable referent. Untracked or unstaged working-tree policy
  cannot authorize an index change, and mode-only or content-plus-mode changes cannot use
  the content-only exception.

### Changed
- The config schema, example, specification, architectural decision log, and rollout
  guidance now define the exact-file M-only contract and explicit CI base requirement.
- The required workflow declares read-only contents permission, disables persisted
  checkout credentials, and pins every third-party action to an immutable commit.
- Documentation now states the pull-request trust boundary explicitly: requiring the
  status is not sufficient unless repository rules also require trusted review for the
  workflow and the gate/parser paths it executes.
- Propagation coverage proves the workflow and shared parser travel together.
- The npm artifact now includes the canonical verify workflow consumed by
  `scripts/propagate.sh`; packed-artifact coverage installs the tarball and proves the
  propagated gate, parser, and workflow are byte-identical to the release sources.

## [3.9.2] - 2026-08-05
**Windows bash portability, one resolver; MANIFEST project-name preservation**

### Fixed
- `handoff-refresh` no longer fails on Windows when it regenerates `MANIFEST.json`.
  `aahp-dashboard.mjs` shelled out to a bare `bash` with native backslash paths, which
  breaks in two independent ways: bash consumes each backslash as an escape, and a bare
  `bash` on Windows can resolve to `C:\Windows\System32\bash.exe` (the WSL launcher),
  whose filesystem has no `C:` drive. `LOG.md` is written before the regen, so the failure
  left the manifest checksums stale against the file just produced. Only a project that
  configures `generate.log` reaches this code path, and only in write mode (`--check` exits
  before it), which is why AAHP's own dogfooding never hit it.
- `aahp-manifest.sh` no longer overwrites an existing MANIFEST.json `project` value with
  the checkout's directory basename on regeneration. Only a first-ever generation (no
  `MANIFEST.json` on disk yet) derives `project` from the basename; every regeneration
  after that preserves the recorded name. Previously, regenerating inside a
  differently-named checkout (a temp dir, a CI working directory, a tarball extraction)
  silently clobbered a consumer's real project name. Regression coverage in
  `tests/manifest.bats`.
- The same fix corrected a latent misalignment bug in the tasks/`next_task_id`/
  `cross_repo_ref` preservation added in 3.9.1: the single-node-process read joined
  fields with a tab and split them with `IFS=$'\t' read`, but tab is IFS whitespace, so
  bash silently collapses and strips leading empty fields. Any manifest with an empty
  earlier field and a non-empty later one (e.g. no `tasks` but a `cross_repo_ref`) had its
  fields shifted into the wrong variables. The delimiter is now `\x1f` (Unit Separator),
  which is not IFS whitespace.

### Changed
- Bash interpreter resolution and Windows path conversion now have a single implementation,
  `resolveBash()` and `toBashPath()` in `aahp-config.mjs`, used by both `bin/aahp.js` and
  `scripts/aahp-dashboard.mjs`. `bin/aahp.js` previously carried its own
  `findBashExecutable()`/`toBashScriptArg()` pair; the dashboard call site had neither, so
  the same Windows defect had to be found a second time. The merged helper keeps what each
  side got right: the relative-path and `/c/` MSYS strategies from the CLI, and the
  `AAHP_BASH` override plus environment-driven candidate paths (including Git's `usr/bin`
  layout and per-user `LOCALAPPDATA` installs) from the new one. `platform`, `env` and `cwd`
  are injectable, so the win32 behaviour is asserted on the Linux CI runner
  (`tests/bash-portability.bats`), and a test fails if a second copy is reintroduced.

## [3.9.1] - 2026-08-03
**Doctor handoff-set matches Layer 1 on partial indexes; handoff hygiene**

### Fixed
- `aahp doctor` `handoff-set` gate now fails when a canonical handoff file is present on
  disk but missing from `MANIFEST.json` `files{}` (partial index). Previously doctor could
  report PASS while `aahp verify` Layer 1 / `lint-handoff.sh` already failed the same state.
  Regression coverage in `tests/doctor.bats`.
- `aahp_auto_summary` looks past title/blockquote/header chrome (first 40 content lines)
  so regenerating a manifest no longer collapses every summary to `(no summary available)`
  on normal handoff files.

### Changed
- Dogfooded handoff hygiene: STATUS.md rewritten to a current-state snapshot (no session
  append log), WORKFLOW.md aligned with Phase 4.5 + MANIFEST task selection + harness-owned
  model routing, NEXT_ACTIONS.md single Recently Completed section, TRUST.md re-verified.
- Template `WORKFLOW.md` task-selection rules now point at MANIFEST.json as authority
  (DASHBOARD is display-only), matching README Section 8.4.

## [3.9.0] - 2026-07-26
**Acceptance-criteria lifecycle, plus an advisory report that is deliberately not a gate**

### Added
- Specification Section 8.7 defines the acceptance-criteria lifecycle: one canonical
  `Acceptance criteria` section per task, `- [ ]` while a criterion is unresolved, `- [x]`
  only on evidence, and, before a task becomes `done` or a linked issue closes, every
  remaining criterion completed, explicitly waived (`(waived: rationale)`), or moved to a
  linked open follow-up (`(follow-up: T-042)`). `Completion criteria` and
  `Definition of done` stay recognized as legacy aliases with a documented rename path.
- `aahp criteria [path]`, an ADVISORY report over the lifecycle, backed by
  `scripts/report-acceptance-criteria.mjs`. It is not part of `aahp check`, it has no
  enforcing mode, and it always exits 0 whatever it finds; the known non-zero exits are the
  report failing to run at all (an unparseable config, or no git work tree). Best effort
  by construction, which is why it is advisory and gates nothing. It reports
  three lifecycle defects (`legacy-heading`, `plain-bullets`, `unresolved-on-done`) and
  ten comprehension defects so that input it could not read is never presented as a
  clean document: `config-unusable`, `include-unusable`, `no-files-matched`,
  `file-unreadable`, `manifest-missing`, `manifest-outside-root`, `manifest-unreadable`,
  `unparsed-criteria-section`, `unbound-criteria-section`, and `unterminated-fence`. It
  reads tracked files plus the `MANIFEST.json` task registry and makes no network calls,
  so a run is complete and deterministic offline.
- The always-exits-0 guarantee holds for every input the report accepts. A syntactically
  valid `acceptanceCriteria.include` pathspec that git nonetheless refuses (an unknown
  pathspec magic word, a path outside the repository) is reported as `include-unusable`
  rather than throwing out of the process, so the documented pair of non-zero exits is the
  complete list. The same holds at every level of the configuration: an `aahp.config.json`
  that parses but is not a JSON object (`null`, a string, a number, a boolean, an array) is
  reported as `config-unusable` and the report continues on its defaults. A file containing
  only `null` previously threw a `TypeError` out of the process on a config that parses
  perfectly well, and the other non-object shapes read as no configuration at all without
  saying so. The same shapes are covered for `acceptanceCriteria`, for
  `acceptanceCriteria.include`, and for `acceptanceCriteria.manifest`.
- Every configuration finding names `aahp.config.json`, the only file `loadConfig` reads.
  When no config file existed they named `package.json`, which the loader never opens, so a
  reader was sent to correct `acceptanceCriteria.include` in the wrong file.
- `acceptanceCriteria.manifest` is required to resolve inside the project root. A value
  containing `..` used to be joined to the root and read from outside the work tree; it is
  now reported as `manifest-outside-root` and the file is never opened.
- README Section 8.7 publishes the report's known blind spots by name, starting with the
  most reachable one: the criteria heading must match a recognized phrase exactly after
  normalization, so `## Acceptance criteria for release` opens no section and everything
  under it is missed in silence. The list also covers the case where a bold line inside a
  criteria section ends the section and hides every criterion after it. It states in plain
  words that the report is best effort, that a clean report is not proof the criteria are
  resolved, and that it must not be used as a merge gate.
- Task ids bind from ATX headings, setext headings, and bold labels, so the three heading
  forms that appear in hand-written handoff files all scope a criteria section. Anything
  still unattributable is reported as `unbound-criteria-section` instead of being exempted
  from the done-state rule in silence.
- `acceptanceCriteria` (`include` / `manifest`) in `schema/aahp-config.schema.json` and
  `aahp.config.example.json`. It supplies the report's input paths only; it configures no
  gate and it cannot enable one.
- Acceptance-criteria task boxes in both `.github/ISSUE_TEMPLATE` files, the lifecycle rule
  in `templates/CONVENTIONS.md`, and `tests/acceptance-criteria.bats` covering canonical,
  legacy-heading, plain-bullet, waived, follow-up, invalid-closure, and offline cases, the
  comprehension defects above, the exit-0-with-findings guarantee, the unchanged `aahp
  check` gate set, and the published blind spots as explicit known-limitation tests.
- ADR-017: a heuristic over hand-written prose is a report, never a gate. It records the
  three adversarial review rounds that produced the decision and why an opt-in enforcing
  mode is not a sufficient safeguard.

### Changed
- `aahp check` is untouched by this release. The acceptance-criteria detection is a
  standalone command, so the gate list, the `aahp check --json` record shape and its exit
  code are exactly what they were in 3.8.2: the same eight gate ids with the same statuses,
  verified by running both the 3.8.2 and the 3.9.0 CLI against the same tree.
- This repository's own handoff is conformant under the report. `MANIFEST.json` task keys
  now match the ids used in `NEXT_ACTIONS.md` (the two entries whose titles carried a
  different id in brackets were re-keyed), and the criteria of the completed tasks are
  resolved individually: checked with the evidence named inline, or left unchecked with a
  stated waiver where the criterion was superseded. The npm publish task is recorded `done`
  with the registry as its evidence, and its stale "blocked on human npm auth" note is
  removed; its second criterion is waived because the package shipped under a scoped name,
  so the bare `npx aahp` form the criterion names cannot resolve to it.
- `templates/NEXT_ACTIONS.md` uses the canonical `Acceptance criteria` heading instead of
  `Definition of done`, and states the lifecycle rule in its header.
- The shipped scaffolding is self-consistent. `templates/MANIFEST.json` marked the example
  `T-001` as `done` while `templates/NEXT_ACTIONS.md` carried unchecked criteria for it.
  `T-001` is now `in_progress`, which is what the template document actually shows.

### Fixed
- Criteria written as an ordered list (`1.`, `2)`) are recognized. They were invisible to
  every rule, so a task marked `done` with unresolved numbered criteria reported completely
  clean. Both list forms now count, and README Section 8.7 states which forms are criteria
  and which are not.
- Fenced code blocks are skipped. The parser carried no fence state, so documentation that
  SHOWS an example of the criteria format was read as criteria that exist, which fired
  hardest on the projects most likely to document the convention.
- A `MANIFEST.json` that is present but unparseable is reported as `manifest-unreadable`
  instead of being treated as an absent one, and a task registry path that was configured
  explicitly but does not exist is reported as `manifest-missing`. Both used to disable the
  `unresolved-on-done` rule in silence.
- A config value of the wrong shape is reported as `config-unusable` instead of being
  replaced by a default without a word, and a tracked file that cannot be read is reported
  as `file-unreadable` instead of being skipped silently.
- Task scope survives an intervening heading. Any non-task heading between a task heading
  and its criteria heading used to reset scope to null, so `unresolved-on-done` could never
  fire for a task whose document puts a `### Context` or `### Files` subsection in between.
  Scope now closes only on a sibling or ancestor heading.
- `scripts/report-acceptance-criteria.mjs` has no import-time side effects. It runs only
  when the module is the process entry point, so `parseCriteriaSections` and
  `findSectionDefects` can be imported without it reading the filesystem, printing, or
  calling `process.exit`.
- `package-lock.json` is regenerated so its root name and version match `package.json`
  (it had drifted to the pre-scope name at `3.5.0`).

### Removed
- The `acceptanceCriteria.strict` config key, and with it every way to make an
  acceptance-criteria finding fail a build. It never shipped in a release. An enforcing
  option would be switched on somewhere, and then a document shape nobody anticipated
  becomes a red build in a consumer repo, so the option does not exist rather than
  defaulting to off. See ADR-017.

## [3.8.3] - 2026-07-26

### Fixed
- `aahp verify` Layer 1 now fails when `MANIFEST.json` indexes a file that is not present
  in the working tree. Deleting an indexed handoff file used to pass both `aahp lint` and
  `aahp verify --level ci` silently: the checksum comparison answers "does this file still
  match what the manifest recorded", and a deleted file has no content to mismatch, so the
  comparison never fired for it. The manifest could therefore keep advertising an artefact
  that no longer existed while the blocking gate stayed green. A missing indexed file is
  now reported by name and with its own message, separately from a checksum mismatch,
  because the two need different fixes: restore the file, or regenerate the manifest.
- `aahp doctor`'s `handoff-set` gate already caught this case, so the two gates disagreed
  about the same repository state. They now agree.
- `scripts/lint-handoff.sh` raises its own exit code for a failed integrity check. It
  previously printed `! Checksum mismatch` and still exited 0, and still printed
  "All checks passed", because the comparison runs in an embedded interpreter that cannot
  write to the calling shell's violation counter. Two CI workflows and the documented exit
  contract already trusted that exit code, so a hook or a job wired to it got a pass on a
  corrupted handoff set. Both integrity failures now count as violations.
- `scripts/lint-handoff.sh` no longer converts an unexpected exit code from the checksum
  verifier into a yellow note. Any exit code other than "clean" or "findings" means the
  tool could not establish integrity, and unproven integrity is now a violation. Before
  this, an interpreter that died inside the loop produced "All checks passed" and exit 0
  over a tampered handoff set, which is the same fail-open the rest of this release cures.
- `scripts/verify-handoff.sh` guards the shared library helper it depends on. Under
  `set -euo pipefail` an absent helper aborted the gate at exit 127 with no diagnostic;
  a partially synced repository now gets a message that names the missing helper and says
  the library is out of date.
- A `MANIFEST.json` whose `files` index is empty is now a finding in both scripts. Zero
  indexed files means zero comparisons ran, which is not the same as everything matching.
- The manifest-reading helper no longer turns its own failures into "nothing is missing".
  A manifest that is absent, unreadable, or unparseable, and the case where neither node
  nor python is available, are each reported with a distinct exit code, and Layer 1 fails
  on all of them rather than printing an affirmative pass.
- A PARTIAL `files` index is now a finding in both scripts, exactly like an empty one.
  Removing one entry and rewriting that file used to pass both gates: every remaining
  entry still matched, and the file that changed had nothing to be compared against. The
  missing-file check could not see it either, because the file is present. Both scripts
  now fail when a canonical handoff file exists in `.ai/handoff/` and has no entry in
  `files`, which is the invariant the manifest generator already produces.
- The python fallback in the manifest-reading helper wrote the file index through
  text-mode stdout, so on Windows every line came back CRLF. The trailing carriage return
  was carried into the recorded checksum and every comparison mismatched, which would have
  reported a false integrity failure in every repository on any machine that takes that
  fallback (that is, any machine without node). The helper now writes bytes, and the
  reader additionally strips a trailing carriage return so a stale emitter cannot bring
  the false mismatch back.
- A deleted `.ai/handoff/MANIFEST.json` is a violation in `scripts/lint-handoff.sh`
  instead of a yellow note. With no manifest there is no index, so not one handoff file
  was compared, which is the maximal unproven state; lint nevertheless printed
  "All checks passed" and exited 0, and the `aahp-lint` workflow job runs that exit code
  as its own blocking check. `aahp verify` Layer 1 already failed here, so the two gates
  now agree.
- `aahp_checksum` returns non-zero instead of succeeding with an empty digest. When the
  checksum tool produced no output the function reported success with `sha256:` and
  nothing after it, so the branch written for "could not compute a checksum" was
  unreachable and the operator was sent to the wrong fix: regenerating the manifest baked
  the empty digest in, after which a broken toolchain reported a clean handoff set.

### Changed
- Consequence of the exit-code fix, worth knowing before upgrading: `aahp lint` now exits 1
  on a repository that has run `aahp init` but not yet `aahp manifest`, because the
  scaffolded manifest still carries the template placeholder `sha256:[hash]` for every
  file. `aahp verify` has always refused that state, so no blocking verdict changes; only
  lint stops disagreeing with what it prints. Run `aahp manifest` after `aahp init`.
- `aahp verify` Layer 1 reaches BOTH integrity verdicts itself: it reads the file index out
  of `MANIFEST.json` and hashes each indexed file, instead of inferring existence or a
  mismatch from another script's output. Blocking no longer rests on string-matching
  between two scripts, and it survives `lint-handoff.sh` being unavailable, changing its
  wording, or dying before it prints anything. `lint-handoff.sh` still runs for the checks
  Layer 1 does not cover, and its non-zero exit is still honoured.
- `scripts/lint-handoff.sh` no longer ends with "All checks passed" when it skipped its
  integrity check because no Python interpreter is available. That single case stays a
  warning with exit 0 on purpose, since making it a violation would turn currently green
  node-only environments red without catching anything `aahp verify` Layer 1 does not
  already catch; the summary now says that MANIFEST integrity was not verified, and the
  README documents the exception instead of claiming that every unverifiable state exits
  1.

## [3.8.2] - 2026-07-25

### Fixed
- Gate applicability on a project root with no `package.json` is now decided by a single
  predicate shared by `aahp doctor` and `aahp check`, so the two commands can no longer
  hold different opinions about the same repository. A polyglot root (for example a Python
  service whose only `package.json` lives in a frontend subdirectory) with a valid
  `.ai/handoff/` set and a `CHANGELOG.md` used to be green under `aahp verify` but red
  under both diagnostics: `doctor` reported `changelog-format = fail` because the gate
  loaded the root `package.json` for a version before it ever opened the changelog, and
  `check` reported `handoff = fail` with "package.json not found". A gate that cannot
  apply now skips instead of failing.
- `scripts/aahp-dashboard.mjs` treats the root `package.json` as optional. Without one it
  skips the `NEXT_ACTIONS` current-version comparison (there is no version to compare
  against) and falls back to the root directory name for a generated LOG title, instead of
  exiting 1 before doing any work. A `package.json` that is present but malformed still
  fails loudly.
- `aahp doctor` also skips `version-sync` and `pinned-dep` on a root with no
  `package.json`, for the same reason: neither gate has anything to check against.

### Changed
- Applicability of the version-derived gates is decided on the PRESENCE of a root
  `package.json`, not on it parsing. A `package.json` that exists but is not valid JSON no
  longer makes `changelog`, `changelog-format` and `version-sync` skip silently in
  `aahp check`; the gates run and fail with the parse error, so a broken manifest is loud
  rather than invisible.

## [3.8.1] - 2026-07-19

### Fixed
- `scripts/aahp-manifest.sh` now passes the manifest path to its Node helpers as an
  argument (`process.argv[1]`) instead of interpolating `$HANDOFF_DIR` into the inline
  script. On Windows and MSYS checkouts the interpolated path was not readable by native
  Node, so the preservation helpers failed silently and `tasks`, `next_task_id`, and
  `cross_repo_ref` were dropped from MANIFEST.json on regeneration. Linux and CI were
  unaffected. Regeneration now preserves those optional fields on every platform.
## [3.8.0] - 2026-07-18
**Portable Governance: one aggregate governance gate, a governance-only conformance record, and a drop-in CI workflow**

### Added
- `aahp check [path]`: a consumer-facing governance aggregator that runs the
  config-driven gates (changelog, changelog-format, version-sync, claims,
  forbidden-patterns, schema-doc-sync, doc-links, handoff) as one run. Each gate reports
  pass, fail, or skip, and the exit code is 0 only when no gate fails (a skipped gate
  never fails). `--json` emits a `schemaVersion: 1` record; `--quiet` prints only
  failures; `config.check.only` / `config.check.skip` select which gates run.
- `aahp doctor --governance` (alias `--no-handoff`): a governance-only conformance record
  that forces the three handoff gates to `skip` without evaluating them, so a repo with no
  `.ai/handoff/` can still emit a green record. The default mode is unchanged and
  byte-identical to prior versions.
- `aahp init --gates`: scaffolds governance-only config without creating `.ai/handoff/`
  (writes `aahp.config.json`, adds a `govern` script to an existing `package.json`, and
  writes `.github/workflows/aahp-govern.yml`).
- An opt-in, config-driven pinned-dep gate for `aahp doctor`: `pinnedDep`
  (`name` / `location` / `allowRange`) asserts the distribution pin. Absent config reports
  `skip`; the defaults reproduce the prior exact-pin behavior; a repo whose own package
  name matches reports `self`.
- `assets/governance/aahp-govern.yml`: a portable, opt-in, verify-only governance workflow
  that invokes `aahp check` and `aahp doctor --governance` through the pinned
  devDependency via `npx --no-install` (no vendored script paths).
- New `check` (`only` / `skip`) and `pinnedDep` (`name` / `location` / `allowRange`) keys
  in `schema/aahp-config.schema.json` and `aahp.config.example.json`.
- README: ADR-011 through ADR-016 in Section 7, plus `aahp check` and
  `aahp doctor --governance` coverage in Sections 2.11 and 9.2.

### Changed
- Git hooks are de-vendored: they resolve `scripts/verify-handoff.sh` when it is vendored,
  else the installed `aahp` CLI via `npx --no-install`, and skip when neither resolves. The
  required CI check remains the off-machine authority (the evaluator-path trust boundary
  is clarified in 3.10.0).
- The enumerating governance gates (`check-forbidden-patterns.mjs`, `check-doc-links.mjs`)
  fail loud outside a git work tree instead of silently scanning zero files: file
  enumeration goes through a shared `git ls-files` helper that throws when the project root
  is not a git checkout.

## [3.7.0] - 2026-07-18
**Anti-entropy: enforcement gates, a constitution, and an ADR log**

### Added
- Three config-driven enforcement gates (a clean no-op without config), folded into
  `npm run check`: `check-forbidden-patterns.mjs` (bans configured regexes such as em
  dashes or model names in tracked files), `check-schema-doc-sync.mjs` (asserts an
  extracted value-set is identical across sources, e.g. an enum in the schema vs its
  doc copies), and `check-doc-links.mjs` (resolves internal Markdown file links). Their
  config keys (`forbiddenPatterns`, `docSync`, `docLinks`) are documented in
  `schema/aahp-config.schema.json` and `aahp.config.example.json`.
- `CONSTITUTION.md`: a short, stable index of the project's non-negotiable invariants
  (each already enforced by a gate, test, or CI), linked from the README and CLAUDE.md.
- README Section 7 reframed as an Architectural Decision Log: 10 ADRs with stable
  `ADR-NNN` anchors and a LOG-to-ADR promotion rule.

### Changed
- The ci.yml ShellCheck step uses a `git ls-files` glob instead of a hand-maintained
  list, so new scripts are covered automatically (`scripts/propagate.sh` had been
  missed).
- Removed the stale German release runbook from the CONVENTIONS template and the
  dogfood, and collapsed the duplicated Three Laws motto to a single home (README).

## [3.6.1] - 2026-07-18
**Security: harden the claims floorCmd; fix shipped documentation drift**

### Security
- `check-claims.mjs` now runs `floorCmd` as a repo-relative Node script via
  `execFileSync` (no shell), instead of `execSync` on an arbitrary config string.
  This closes a command-injection path from a PR-editable `aahp.config.json`
  (a contributor could otherwise gain code execution in a consumer's CI). The
  schema and example are updated to match; a path escaping the project is rejected,
  including Windows cross-drive and absolute paths.
- Hardened `aahp status`: the task-status counter uses a null-prototype object so a
  crafted status like `toString` cannot match via the prototype chain.

### Fixed
- Documentation drift: README Section 4 now lists the full canonical handoff set
  (adds `GROUNDING.md`, `pii-allowlist.json`, `LOG-ARCHIVE.index.json`); the
  Section 7.1 command table adds `aahp doctor`; the Section 8.3 task-status enum
  adds `cancelled`; and the phantom `stale` bucket (never in the schema) is
  removed from `aahp status`.
- Removed em dashes (U+2014) from the CONVENTIONS templates and CLAUDE.md.

## [3.6.0] - 2026-07-18

### Added
- `aahp doctor`: a conformance self-check that emits a machine-readable JSON record
  (`schemaVersion: 1`) covering the handoff file set, MANIFEST schema conformance,
  GROUNDING/TRUST provenance, an exact-version dependency pin, changelog format, and
  version sync. `--json` prints the record to stdout.
- Config-driven release gates that ship in the package and run against any consumer
  project via `aahp.config.json`: `check-version-sync.mjs`, `check-changelog.mjs`,
  `check-changelog-format.mjs`, and `check-claims.mjs`. Each is a no-op until a repo opts
  in, so projects without config keep working.
- A single shared changelog grammar (`changelog-grammar.mjs`) imported by both the format
  validator and the optional LOG release-journal generator (`aahp-dashboard.mjs`), so the
  two cannot diverge.
- `schema/aahp-config.schema.json` and `aahp.config.example.json` documenting the config
  shape (`versionSites`, `claims`, `generate`), plus a `NEXT_ACTIONS.md` current-version
  freshness gate.
- README Section 2.11 (conformance and the config-driven gates) and a documented release
  ceremony. A `Provenance` column was adopted in the dogfooded `.ai/handoff/TRUST.md`.

### Changed
- `check-changelog-format.mjs` enforces the Keep a Changelog grammar (R1-R8, with
  `## [Unreleased]` optional); this CHANGELOG was normalized to conform (gave `3.1.0` a
  full ISO date and collapsed the `3.0.1-3.0.5` range into a single dated entry).

## [3.5.0] - 2026-07-14

### Added
- `documentation` pipeline phase, accepted by `aahp manifest --phase documentation`, the
  schema `last_session.phase` enum, the manifest generator, and the CLI help.
- This CHANGELOG. The GitHub release job references it.

### Fixed
- `aahp-manifest.sh` now preserves the optional `cross_repo_ref` field across
  regeneration (previously it was dropped), the same way it preserves `project`,
  `tasks`, and `next_task_id`.

## [3.4.0] - 2026-07-14

### Added
- README Section 9, Consuming Harness Integration: the harness-vs-AAHP boundary and
  decision matrix, a reference Claude Code `.claude/` layout, the minimal harness
  bootstrap, and grounding-audit integration.
- README Section 10, Multi-Repo and Cross-Repo Handoff, including the optional additive
  `cross_repo_ref` MANIFEST field (`repo` / `commit` / `handoff_file` / `relation`) and
  its schema entry, plus monorepo and version-skew doctrine.
- `aahp status` command documentation and an eight-command CLI reference table (7.1).
- A condensed inline Grounding reference in Section 2.10 (task-type anchor matrix,
  confidence bands, minimum TRUST fields).

## [3.3.0] - 2026-07-13

### Added
- Grounded Reflection Layer (Draft v0.1, README Section 2.10): an orthogonal provenance
  axis (`model_claim` to `human_confirmed`) recorded as a TRUST.md column, a
  `templates/GROUNDING.md` task-type anchor matrix scaffolded by `aahp init`, an optional
  pre-handoff Phase 4.5 grounding audit, and the `aahp migrate-grounding` verb. Additive
  and backward compatible: no MANIFEST field or schema change.

## [3.2.1] - 2026-06-26

### Fixed
- Follow-up fixes to the LOG archive flow and the verify gate. Last version published to
  npm before the 3.5.0 catch-up release.

## [3.2.0] - 2026-06-26

### Added
- Canonical LOG archive flow: `LOG.md` keeps the 10 newest entries and older entries
  rotate into `LOG-ARCHIVE.md`; `LOG-ARCHIVE.index.json` records archived-entry hashes so
  `aahp archive --verify` detects truncation or tampering. Reusable per-check badge
  workflows were split out for downstream repos.

## [3.1.0] - 2026-06-26

### Added
- Reviewed, exact-value, expiring PII email allowlist (`pii-allowlist.json`),
  MANIFEST-indexed so it cannot suppress secrets. Shipped to npm as part of the 3.2.0
  release.

## [3.0.5] - 2026-06-20

### Added
- AAHP v3 (v3.0.1 through v3.0.5): stable task IDs (`T-001` and up), a machine-readable
  dependency graph in `MANIFEST.json`, the `aahp` CLI, the verify gate (`aahp verify`),
  checksum integrity, the prompt-injection and secrets/PII firewalls, and OIDC trusted
  publishing to npm.

### Changed
- Relicensed to Apache-2.0 (earlier commits carried MIT, then CC BY 4.0, headers).

[Unreleased]: https://github.com/homeofe/AAHP/compare/v3.10.0...HEAD
[3.10.0]: https://github.com/homeofe/AAHP/compare/v3.9.2...v3.10.0
[3.9.2]: https://github.com/homeofe/AAHP/compare/v3.9.1...v3.9.2
[3.9.1]: https://github.com/homeofe/AAHP/compare/v3.9.0...v3.9.1
[3.9.0]: https://github.com/homeofe/AAHP/compare/v3.8.3...v3.9.0
[3.8.3]: https://github.com/homeofe/AAHP/compare/v3.8.2...v3.8.3
[3.8.2]: https://github.com/homeofe/AAHP/compare/v3.8.1...v3.8.2
[3.8.1]: https://github.com/homeofe/AAHP/compare/v3.8.0...v3.8.1
[3.8.0]: https://github.com/homeofe/AAHP/compare/v3.7.0...v3.8.0
[3.7.0]: https://github.com/homeofe/AAHP/compare/v3.6.1...v3.7.0
[3.6.1]: https://github.com/homeofe/AAHP/compare/v3.6.0...v3.6.1
[3.6.0]: https://github.com/homeofe/AAHP/compare/v3.5.0...v3.6.0
[3.5.0]: https://github.com/homeofe/AAHP/releases/tag/v3.5.0
[3.4.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.4.0
[3.3.0]: https://github.com/homeofe/AAHP/compare/v3.2.1...v3.3.0
[3.2.1]: https://github.com/homeofe/AAHP/releases/tag/v3.2.1
[3.2.0]: https://github.com/homeofe/AAHP/releases/tag/v3.2.0
[3.1.0]: https://github.com/homeofe/AAHP/compare/v3.0.5...v3.1.0
[3.0.5]: https://github.com/homeofe/AAHP/releases/tag/v3.0.5
