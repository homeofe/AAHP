## Trust Decay could not decay, and the fix had to not break nine repositories

**Correction, and the correction found a worse one.** The fixture for the enforce-false test added
`aahp.config.json` at the repository root and never moved handoff state, so Layer 2
failed it. Layer 4 had warned exactly as intended. The same flaw sat under the three
tests asserting a NON-zero exit, and those were passing: Layer 2 was supplying the
failure, so they would have passed with the enforcement code deleted. One of them
asserted only `TTL was NOT evaluated`, which the advisory branch prints too, so
nothing in it distinguished the two branches at all. Every fixture now moves handoff
state, and that assertion names the wording only the failing branch produces.
Layer 4 reads the trust register, finds expired `verified` rows and prints them.
Nothing in the block increments `FAILURES`, so no number of expired rows could
ever change the exit code. Eight of this repository's own ten verified rows sat
past expiry, one by 16 days, with every gate on `main` green. One of the expired
rows asserted `verify-handoff.sh runs all 4 layers`, and two of those four could
not produce a verdict.

The obvious fix is the wrong one, and the original comment said so with a
measurement behind it: across the nine consuming repositories two hold registers
with 24 of 25 and 20 of 21 rows already expired, so a blocking Layer 4 turns them
red on their next commit for a file their pull requests never touch. A gate that
fires on repositories which changed nothing gets switched off, and a gate that is
off is worse than one that warns.

So enforcement is opt-in, on the same pattern `pinnedDep` already uses.
`trustTtl.enforce` absent or false is the historical behaviour to the byte, which
is what all nine consumers get. True, and expired rows fail the run. This
repository sets it to true.

Two properties that took more thought than the switch itself:

A register that cannot be CLASSIFIED fails under enforcement as well. The census
already refused to call that state clean; if it stayed a pass under enforcement,
the gate could be switched off by breaking the table instead of by editing the
reviewed config line, which is the class of evasion this repository keeps
finding.

The reader fails closed. An unparseable config is a blocking finding rather than
a silent fall back to `not enforcing`, and a config mentioning `trustTtl` or
`enforce` twice is refused outright, because every JSON parser here keeps the LAST
duplicate key and a reviewer reading the first one would be looking at a value
that never takes effect.

Five tests, and it is worth naming what each one owns. One proves an expired row
now fails. One proves the same register still only warns with enforcement off,
which is the half that would catch an implementation that ignores the config and
fails everywhere. The other three close the three ways the control could be
disabled without touching the line that enables it: an unreadable register, an
unparseable config, a duplicated key.

The deadlock the original comment worried about does not apply to this shape.
Layer 4 does not run at `precommit`, so no local commit is blocked, and the pull
request that refreshes `TRUST.md` carries the refreshed rows, so CI reads a
register that is already clean.

NOT covered: this does not re-verify anything. The two rows this repository still
carries as `verified` expire on 2026-09-02, and when they do, enforcement will
turn CI red until somebody actually re-runs the checks behind them. That is the
intended behaviour and it will be inconvenient on the day.

## A HIGH advisory whose only offered fix was a five-major downgrade

`fast-json-patch` below 3.1.1 carries GHSA-8gh8-hqwg-xf34, prototype pollution,
rated HIGH. It reaches this repository through `ajv-cli@5.0.0`, which requires
`^2.0.0` and therefore cannot take the fix inside its own range. `npm audit fix`
offers exactly one remedy: `ajv-cli@0.6.0`, five majors back, which predates
`--spec=draft2020` and so would take both schema validation steps in `ci.yml`
with it. That is the shape worth naming: an advisory where the tool's suggested
fix costs more than the finding.

Resolved with an `overrides` entry pinning `fast-json-patch` to `^3.1.1`.
`npm audit` goes from 2 HIGH to 0 across every severity.

An override is a claim that the new major still works, so it was measured rather
than assumed. `ajv-cli` touches exactly one symbol, `jsonPatch.compare(a, b)`, in
`validate.js` and `migrate.js`, and v3 keeps it unchanged. All three commands
were then run against this tree: the MANIFEST schema step, the config step with
both documents, and `--changes=json`, which is the branch that actually calls
`compare` and which neither CI step exercises. All exit 0. A deliberately
invalid MANIFEST, with `aahp_version` removed and `files` replaced by a string,
still exits 1, so the validator was proved to be doing work rather than passing
everything.

There are no runtime dependencies in this package, so no adopter ever received
the vulnerable code; the exposure was this repository's own CI and any
contributor's `npm ci`. That makes it lower impact than the severity suggests
and does not make it acceptable to leave.

NOT covered: the override applies to whatever else in the tree may later ask for
`fast-json-patch@2`. Nothing does today, and if something does, npm will resolve
it to 3.1.1 silently rather than warn.
## Three pull requests, each correct, none of them mergeable

Dependabot opened #96, #98 and #99 to move `github/codeql-action` from v3.37.8
to v4.37.7: one per sub-path, `init`, `autobuild` and `analyze`, all three
pointing at the SAME commit `ff2f1c62`. Each is correct in isolation and none of
them has a green state. The action refuses to run when its steps are on
different versions, so every single-path change fails with "Not all workflow
steps that use github/codeql-action actions use the same version" and "Loaded a
configuration file for version '4.37.7', but running version '3.37.8'". Merging
them in some order does not help either, because the tree stays mixed until the
last one lands and each run gates on the state before it.

Fixed by moving all three refs in one commit, which is what the action requires.
#96, #98 and #99 are closed as superseded rather than merged, since their
branches each carry the split that caused this.

The split is the defect worth fixing, not the version. Dependabot resolves every
SUB-PATH of an action repository as a separate dependency, so the next
codeql-action release arrives the same way unless something changes.
`.github/dependabot.yml` now carries a `groups:` entry covering
`github/codeql-action*`, and `check-workflow-pinning.mjs` gains rule G, which
fails when ANY action used through more than one sub-path is left ungrouped. It
is written as a property of multi-path actions rather than as a codeql special
case, so the next action shipped this way is covered without another change.
Green on this tree, red with the `groups:` block deleted, green again once it is
restored.

Same investigation, second finding, and it is the one that explains a symptom
nobody had traced: `labels: ["dependencies"]` in both Dependabot lanes names a
label this repository did not have. Dependabot applies configured labels but
never creates them, so all four of its pull requests arrived unlabelled while
every human pull request carried labels. The label exists now. That is
repository state and not tree state, so nothing in this commit proves it and no
gate here can.

NOT covered: whether v4.37.7 changes any CodeQL result. This moves three pins
and nothing else. The first analysis run on the new major is the only thing that
answers that, and it has not run yet at the time of writing.

## Three verdicts nobody produced: a count, a record, and a register nobody read

Three issues, one shape, and it is the shape the two entries below this one
already named: a control that publishes a result it did not earn. The vocabulary
is reused rather than reinvented - NOT EVALUATED and `unevaluated`, which this
CLI already emitted for an invalid config.

REPRODUCED FIRST, each against a positive control proving the harness was live.

**doctor counted gates, not gates that ran.** On a fixture built exactly as an
adopter would (`aahp init --gates` into an empty repository) it printed
`Conformance OK: 7 gate(s), no failures.` over seven skips and zero evaluations,
exit 0, and `--quiet` printed zero bytes and exited 0. Now
`Conformance OK: N of 7 gate(s) ran`, and zero evaluated is
`Conformance NOT EVALUATED: 0 of 7 gate(s) ran. This is not a pass.`, exit 1, on
the text path, under `--quiet` and under `--json` alike.

**The record collapsed four states into `skip`.** A repository that had adopted
governance and one that had switched every gate off through `config.check`
emitted byte-identical `gates` objects. `schemaVersion` is now 2: `gates` is
UNCHANGED, and `gateOutcomes` (refined outcome plus the human reason, per gate),
`evaluated` and `total` are added. Surveyed across the nine consuming
repositories in this estate: none parses the record, every one runs
`aahp doctor . --json` as a CI step and reads only the exit code, so the bump
reaches no parser. The one breaking edge, a reader asserting
`schemaVersion === 1`, is named in the CHANGELOG.

**`aahp check --json` disagreed with `aahp check` about the same tree.** Measured
on `origin/main` at `2cdaf48`: text `NOT EVALUATED, exit 1`, JSON `exit 0, every
gate skip`, because the JSON branch returned above the zero-gate test. That was
recorded here as STILL OPEN and read as a commitment about bare repositories.
It is not: the commitment was made when the text path shipped, and the JSON path
was simply left on the other side of a `return`. One verdict is now computed once
and used by both.

**The tamper gate did not look at the file with the widest blast radius.**
`assets/governance/aahp-govern.yml` is what `aahp init --gates` writes into an
adopting repository, and a governance-only adopter has no `aahp-verify.yml` at
all. `if: false` on its `Run governance gates` step left doctor reporting
`SKIP: no workflow here runs the AAHP verify gate`, exit 0. Now four
`govern-*` findings, and a distinct `governance-only` verdict whose pass reason
says out loud that nothing there compares a handoff checksum.
FOUND WHILE FIXING, in the fix: the first draft tested skippability per JOB, and
the shipped template runs `check` AND `doctor`, so wrapping only the gate step
still read as enforced. The audit is per SUBCOMMAND for that reason, and the
fixture that caught it is in the test set.

**Layer 4 called a register clean that it never managed to read.**
`aahp_trust_expired` prints nothing both when nothing is expired and when not one
row was parsed. Measured across the nine consuming repositories: SIX have a
`TRUST.md` in which this reader sees zero decidable rows, and in one the register
is a real, populated `Verified Properties` table with an `Expires` column and no
`Status` column, holding a row eight days past expiry, reported as clean. The new
census separates "no trust table here" from "a table this reader cannot classify"
from "N checked, none expired".

**WHAT THIS DOES NOT COVER, and it is deliberate.**
- Layer 4 is still ADVISORY. It increments no failure count and cannot fail a
  build, whatever it finds. Making it fail is an OWNER DECISION and is named in
  the pull request with the measurement that argues against doing it silently:
  two consuming repositories hold registers with 24 of 25 and 20 of 21 verified
  rows already expired, so a blocking Layer 4 turns them red on their next commit
  for a file none of their pull requests touch.
- Layer 3 has the same all-warnings shape and is untouched here.
- Where `aahp verify` and `aahp doctor` run in the SAME job, an `if:` on the
  doctor step alone is still not a finding. The gate runs all four layers there;
  only the record is lost. Flagging it would fire on the legitimate
  `if: github.event_name == 'pull_request'`, and a false positive is what gets a
  gate switched off.
- The expired rows in this repository's own register are re-dated only where
  something was actually re-run on Linux this session; the rest are downgraded to
  `assumed` rather than given a date nobody earned.
- No consumer repository is changed. Six of the nine report `bypassable` against
  their own `aahp-verify.yml` and only the owning repositories can fix that.

MEASURED AGAINST REAL CONSUMERS, at their `origin/main` rather than a local
working copy: the `verify-workflow` verdict and exit code are identical for all
nine before and after, and `doctor`/`check` exit codes are identical for all nine.

TWO FIXTURES RE-GROUNDED AFTER THE FIRST LINUX RUN, and the reason is worth
keeping. Three tests went red on bats 1.10.0 and none of the three was a defect
in the change:
- Two doctor tests asserted `Conformance OK: 5 of 7`. The real number is 4: the
  three handoff gates plus `pinned-dep` evaluate, and `verify-workflow` does not,
  because the fixture holds no workflows. The 5 was WRITTEN, not measured, which
  is exactly the failure mode this branch is about. Corrected against the Linux
  run, and the comment now says where the number came from.
- `check: versionSites without package.json skips version-sync and exits 0`
  configured `versionSites` and nothing else, so NO gate ran and the test pinned
  exit 0 over a run that had assessed nothing - the same defect written down as
  an expectation, surviving only because it used `--json`. Re-grounded the way
  the doc-links deselection test above it already was: the applicability
  assertion is unchanged, and a gate that really runs was added beside it so the
  exit code means "no gate failed" rather than "nothing ran".

THE FULL SUITE THEN FOUND TWO MORE OF THE SAME, and they are worth naming
because they are the same pattern a third and fourth time:
- `acceptance-criteria.bats` "the gate set is eight ids" configured nothing, so
  it too pinned exit 0 over a run that assessed nothing. Its subject is the gate
  SET, which is unchanged; the exit assertion is now 1 with `evaluated === 0`
  asserted beside it, so the test states WHY rather than leaving the number to
  be guessed.
- `inert-controls.bats` "84 zero gates ran" asserted the substring
  `0 gate(s) ran`, which the new denominator form does not contain. Asserted as
  `0 of 8 gate(s) ran` instead, which is strictly stronger, and a second test was
  added beside it for the `--json` half that was still open.

ONE FULL-SUITE FAILURE IS NOT MINE, AND IT IS NOT THE REPOSITORY'S EITHER.
`tests/manifest.bats` "project name survives regeneration when node is
unavailable" fails IDENTICALLY on unmodified `main` at `2cdaf48`, on the same
remote Linux runner, checked before concluding anything. It builds a PATH without
an interpreter and `bats` reports `exited with code 127` for `node --version`
inside it.
The first version of this note stopped there and called it pre-existing, which is
true and still understates the result. Hosted CI on this branch runs the same
527 tests on three runners and reports 527 passed, 0 failed, 1581 `ok` lines and
ZERO `not ok` - that test included. So it is an artefact of ONE machine, not a
standing red test in this repository. Worth remembering next time: "fails on main
too" rules out a regression, it does not establish that the suite is broken.

HOSTED CI, this branch: all twelve checks green, mergeStateStatus CLEAN, the
`ShellCheck scripts` step included, which is what covers `verify-handoff.sh`
because shellcheck is not installed on the remote Linux runner used here.

MUTATION PROOFS: eight, each with a control that stayed green, each restored to
an md5-identical file. One of them is recorded rather than quietly corrected: the
first version of the `--json` exit proof named the wrong `process.exit` call.
`cmdDoctor` has TWO, and the one it named was the text path's, so the mutation
landed, the file really changed, and the `--json` test stayed GREEN. A named
anchor that turns nothing red is worth no more than no anchor at all. Split into
two proofs, one per exit call, and both go red.
## Two published guarantees with nothing behind them: one withdrawn, one given a gate

Section 2.4 stated a provenance MUST and an audit trail. Both are withdrawn
(ADR-021). Enforcement was measured before it was rejected, not after: across the
nine repositories in this estate that consume the protocol, LOG.md holds 100
level-2 entries and 8 carry all five fields (agent 64, session id 27, timestamp
31, commit-before 10, commit-after 8). Every one of the nine has at least one
entry that would fail, so a retroactive MUST reddens 9 of 9 over history none of
them can change, and this repository's own LOG fails it too (10 entries, 0 with
all five). Reproduced the non-enforcement independently on a throwaway repo:
after stripping every provenance line and appending an entry with none,
lint / verify --level ci / doctor all exit 0. No gate was added and none was
added off-by-default either, for ADR-017's reason. What ships instead: the five
fields now sit in templates/LOG.md and templates/STATUS.md, bound to Section 2.4
by a provenance-block docSync group, so the shipped example and the stated
recommendation cannot drift apart.

The README told adopters to copy a .github/workflows/ path this repository does
not have; the real file is assets/governance/aahp-govern.yml. Fixed, and gated:
scripts/check-doc-shape.mjs resolves backticked repo-relative paths against the
git index and asserts a setup heading exists before the ADR log. Not a blanket
rule - 46 of 78 path-shaped spans in this README correctly name a file in an
ADOPTER's tree - so it only resolves spans whose first segment is tracked here,
and exceptions carry an exact occurrence COUNT rather than being allowlisted. A
path-level allowlist would have exempted the very defect it exists for, because
the wrong sentence and the right ones use the same string. It exits 2 on anything
it could not assess. The README also gained an Installation and Quickstart
section; every command in it was run against a throwaway repository first.

Found by running the suite on Linux rather than by reading it: the doc-shape
fixture repository did not track a .github/ entry, so four tests that assert a
FINDING passed vacuously - the first filter put the whole class out of scope
before any assertion ran. The fixture now carries .github/workflows/aahp-verify.yml
and no aahp-govern.yml, which is the shape the real defect had. A fifth test
claimed the runtime guard rejects a missing occurrences count; the schema rejects
it first, at exit 2, so that test now asserts the path that actually executes and
the runtime guard is tested on the case only it can catch (a reason that is
present and blank).

NOT covered: no gate anywhere checks whether an adopting repository's LOG entries
carry provenance, and after ADR-021 none is intended to. check-doc-shape is
repository-local, absent from CHECK_GATES, so no consumer inherits it, and it
still cannot see a path written without backticks or one whose first segment is
not tracked here. Nothing here touches the nine consumer repositories.

OPEN, found by this work and deliberately NOT fixed here. docPaths.include is the
docLinks set minus .ai/handoff/*.md. Widening it to the full docLinks set was
tried and is red: NEXT_ACTIONS.md names .github/workflows/publish.yml twice, and
there is no such workflow in this repository - publish is a JOB inside ci.yml.
Same defect class as issue #74, in the document that tells the next agent what to
do. Left alone because handoff files collide across concurrent branches and this
change set does not need them. The scope choice itself is recorded in ADR-022: an
append-only STATUS.md quotes paths that WERE wrong on purpose, so a counted
exception list over it churns every session and gets switched off.
## A pinning gate that never read a single `uses:`, and a record only a test file kept

22 of 25 action references under `.github/workflows/` ran on mutable major tags,
plus 2 more in the template adopters copy. A tag is a pointer its owner repoints
at will, with no diff here, and 5 of the 6 required checks on `main` ran on those
references. All 27 now name a 40-character commit SHA with the release in a
trailing comment. SHAs resolved through the GitHub API, dereferencing annotated
tag objects: checkout v7.0.1, setup-node v7.0.0, setup-python v6.0.0 (the three
`aahp-verify.yml` already ran green here), codeql-action v3.37.8, which is what
the `v3` tag currently points at.
The part worth carrying forward is not the 22 lines. `check-workflow-pinning.mjs`
already existed, already ran inside the required check, and exited 0 over every
one of them: its rules read only `step.run`, and a `uses:` step has no `run:` at
all. The NAME promised workflow pinning; the SCOPE was npm packages inside
workflows, and nothing said so. Rules E and F close it - every `uses:` immutable
with a version comment, and a `github-actions` Dependabot lane that keeps the
pins moving. Both halves, because a pin nothing updates stops at whatever the
pinned commit turns out to contain, and a missing lane is invisible from the
pull-request count: an unscanned ecosystem and an up-to-date one both produce
zero. ADR-021 records it.
Also here, and touching NO workflow behaviour: `assert-repo-ci-shape.mjs` gained
a fifth assertion comparing its own `PUBLISH_CONDITIONS_BEYOND_RELEASE` against
ADR-019 in README.md, as sets, both directions. The code record existed; the
record a person reads was prose anyone could edit alone.
DOES NOT COVER, and none of it is implied by a green check here: whether
Dependabot is enabled on this repository or has ever opened a pull request (an
off-machine fact, measure with `gh pr list --author app/dependabot`); whether any
pinned SHA is CURRENT, which is what the lane is for and not something the gate
asserts; `assets/governance/aahp-govern.yml`, whose pins the lane does not reach
because Dependabot reads `.github/workflows/` under the configured directory;
`npm install -g npm@latest` in the publish job, still out of scope per issue 68;
and the `workflow_dispatch` operand on the publish condition, which is measured
and written up but deliberately UNCHANGED - it is the owner's call, tracked at
issue 69.
The publish job's steps do not run on a pull request, so the checkout and
setup-node bump inside it is evidenced by the same SHAs running green in
`aahp-verify.yml` and by reading `action.yml` at each pinned SHA for the inputs
this repository passes, NOT by a green run of that job.
VERIFIED ON LINUX, bats 1.10.0: see the pull request body for the transcripts.

## The class test could not detect its own class, and the README described a workflow that changed

The test "every *_SUFFIX= rule in the shipped template has an enforced
counterpart" derived the expected set from the template, which is the right
shape, then looked for each suffix ANYWHERE in scripts/lint-handoff.sh. The same
commit added a block comment naming all five suffixes in prose, so a sentence
about a pattern stood in for the pattern:
  line 130 [COMMENT]  `_CREDENTIALS=` is in the list because ...
  line 184 [CODE]     "_CREDENTIALS=['\"]?..."
Deleting the code entry left the test green. A class test that cannot detect its
own class is the defect this suite exists to close, inside the suite.
Now scoped to the SECRET_PATTERNS array, with an assertion that the extraction
found the array at all so a rename cannot turn the test into a silent no-op.
Proved: with the code entry deleted and the COMMENT still present, the test goes
red. That comment is what made the old version pass.
Separately, four README statements still described the shipped governance
workflow as npx-based after it was changed to invoke the CLI by path. Those are
corrected. The other npx mentions in the README are prose ABOUT the npx defect
and are left alone - they are accurate.
VERIFIED ON LINUX, bats 1.10.0: inert-controls 34 passed, 0 failed.

## The length floor spared real credentials, and the count justifying it was wrong

Two review findings on the secret patterns, both confirmed by measurement, plus
one that did NOT survive checking.
CONFIRMED, and the more serious: the five =assignment patterns absorbed a
leading segment with `[-_.a-zA-Z0-9]*` before requiring a 16-run. `+`, `/` and
`=` are not in that class, so the run is broken by exactly the characters base64
uses. The canonical AWS example secret key was MISSED. Narrowing the patterns to
spare prose also spared real credentials, which is the worse direction of error:
a false positive is noisy, a false negative is the thing the gate exists to
stop. The absorb class now carries `+/=`, which recovers every missed shape
while all four prose cases the narrowing was for still miss.
CONFIRMED: the comment claimed these five carry "the same length floor as the
nine prefix patterns". Counted in the array: 14 patterns, 9 with a floor, and
only FOUR of the nine prefix patterns have one. The other five carry none, by
design, because their prefixes are specific enough alone. The corrected sentence
still supports the change; the original was an argument resting on a number
nobody had counted.
REFUTED, recorded because a reviewer being wrong is worth the same care as a
reviewer being right: a third finding said the consumer survey published in the
CHANGELOG was "wrong on every count". Re-measured against the REMOTES rather
than local checkouts: 10 of 10 consumers have aahp-verify.yml, 0 of 10 have
aahp-govern.yml. The survey is correct and was left as written.
VERIFIED ON LINUX, bats 1.10.0: 73 passed, 0 failed across inert-controls and
lint.

## A usability change turned the .aiignore exclusion into a content filter

Adding `path:line` to the secret message changed `grep -rnl` to `grep -rn`. The
`grep -v '.aiignore'` that followed had been filtering bare PATHS and silently
became a filter on `path:line:MATCHED TEXT`.
Measured: a real token shape on a line reading "note: excluded via .aiignore,
token ghp_..." was reported by the previous form and DROPPED by the new one,
with the gate printing "No secrets detected". That is a weakening of a security
control, introduced inside a change whose stated purpose is to fix controls that
report success without doing the work.
Nobody wrote a bad filter. The filter was correct against `-l` output and became
wrong when the shape of its input changed. That is the failure mode to remember:
a pipeline stage is only as correct as the format of what feeds it, and changing
the producer is a change to every consumer downstream.
Fixed at the source with `--exclude='.aiignore'`, so nothing downstream reads
the matched text and no content can subvert the exclusion. Both comments that
described the old mechanism were corrected in the same edit.
VERIFIED ON LINUX, bats 1.10.0: 34/34 green. The mutation proof discriminates
rather than merely failing - restoring the previous form turns the
secret-on-a-mentioning-line test RED while the ignore-file-still-skipped test
stays GREEN, which is what shows the two tests measure different properties.

## The required check was already red, and --json still reports a zero-gate run as a pass

FOUND WHILE FIXING THE ABOVE, NOT FIXED, needs the owner's call.

The branch arrived with `lint-and-validate` (REQUIRED) red. Same single failure
on cd247ce, before this session pushed anything:
  not ok 103 check: config.check.skip omits doc-links so a broken link is not caught
Cause: that fixture configured `docLinks` and nothing else, then skipped
`doc-links`, so ZERO gates ran and the test asserted exit 0 for a run that had
assessed nothing. The zero-gate fix on this branch correctly turned it red - the
test had the #84 defect written down as an expectation.
RE-GROUNDED, NOT RELAXED: changing the 0 to a 1 would pin the aggregate verdict,
which is not what the test is about. Its subject is the DESELECTION, so the
fixture now also carries a gate that really runs and passes, and it additionally
asserts the deselected gate never evaluated the broken link. A second test pins
the other half: skipping the only configured gate is NOT EVALUATED, exit 1.

STILL OPEN, and it is the same class one level down. The zero-gate branch lives
in the text summary only, and `--json` returns before it:
  aahp check .          -> "Governance NOT EVALUATED: 0 gate(s) ran."  exit 1
  aahp check . --json   -> exit 0, every gate "skip"
Same tree, same run, opposite verdicts, and the machine-readable path is the one
a dashboard consumes. The JSON record marks the gates `skip` here, although the
PR body's own argument for the invalid-config case is that `skip` ("asked, not
applicable here") must never stand in for "never asked".
NOT CHANGED HERE because the two intents on this branch genuinely conflict and
the resolution is a commitment, not a defect fix: `tests/check.bats` states in
its header that a repo with no package.json, no config and no `.ai/handoff` must
stay green, and test 1 asserts exactly that - it passes today only because it
uses `--json` and so misses the new branch. Deciding whether a bare repo is green
or NOT EVALUATED changes `aahp check` for every adopter who runs it without a
config.
MEASURED, so the decision is not urgent: of the ten consuming repositories, the
eight that can run `aahp check` all ship an `aahp.config.json` with at least one
applicable gate, and the two without a config never invoke `check` at all. No
consumer changes state either way today.

## The live secret patterns turned a real consumer's protected branch red

Escaping the BRE quantifier made five `=assignment` secret patterns live for the
first time. Live and unfloored, `_KEY=['"]\?[a-zA-Z0-9]` matches a `*_KEY=`
assignment of ANY value from one character up: a detector for the SHAPE of a
configuration line, in files that are mostly prose ABOUT configuration.
Reproduced against a real consumer checkout, whole-script exit code, not piped:
  origin/main  -> "All checks passed."      exit 0
  this branch  -> "1 violation(s) found."   exit 1
One committed line caused it, and it was a handoff note DESCRIBING a security
finding: it quoted the placeholder `API_KEY=your-api-key-here` from an
.env.example the note was arguing against. That repository's
`aahp verify --level ci` is a REQUIRED, branch-protected check, so the upgrade
alone would have turned a green protected branch red with nothing of its own
changed. This is the fleet-wide case: every consumer carries these gates.

CHOSEN: narrow the patterns (option a), not opt-in-with-an-empty-default.
Opt-in-empty would have disabled the NINE prefix patterns that do work and do
block today, trading a false positive for a real regression, and a default that
cannot fail is the exact disease this branch exists to cure. The floor is not a
new heuristic either: the comment three lines above SECRET_PATTERNS has always
stated it, for exactly this failure mode, and it was applied to nine of the
fourteen patterns and missed on these five. Same defect class as the rest of the
branch - a rule written down and not applied.

Expressed as "an unbroken run of 16+ alphanumerics ANYWHERE in the value token",
not "the value starts with one": modern tokens are segmented (`sk-proj-`,
`github_pat_`, `rk_live_`) and anchoring at `=` misses all three. Placeholder
prose is word-shaped, every segment far short of 16, so the two populations
separate on precisely this property.
MEASURED: real-secret corpus 8/8 matched, prose corpus 0/12 false positives
(unfloored: 8/12 false positives). All eleven handoff directories available to
measure: zero patterns fire, before and after, so no adopter changes state.
Positive control on the real consumer content: unmodified -> 0 findings exit 0;
same file plus four genuine secrets -> 4 findings exit 1.
GIVEN UP DELIBERATELY: a short real password such as `DB_PASSWORD=hunter2`.
Nothing separates that from prose by inspection; an entropy scanner is the right
layer. A finding now prints `path:line` and never the matched text.

## The prescribed remediation reached none of the affected repositories

CHANGELOG told adopters to run `aahp init --gates --force`. That writes exactly
one file, `.github/workflows/aahp-govern.yml`. SURVEYED, ten consuming
repositories: ten have `aahp-verify.yml`, ZERO have `aahp-govern.yml`, and zero
have vendored hooks under `scripts/hooks/` for `install-hooks.sh` to refresh.
Running it would have added a second unreferenced workflow beside the one that
gates the branch and left the vulnerable line in the file that runs. The
vulnerable text lives in a hand-held `aahp-verify.yml` that AAHP does not
generate and therefore cannot rewrite. CHANGELOG and README now say that
plainly, with the per-shape manual edit, instead of naming a command that
appears to fix it. Eight of the ten carry `npx --no-install aahp` (unscoped, the
vulnerable spelling); two carry `npx -y @elvatis_com/aahp@<version>`, which is
scoped and exact and needs no change.

## The false sentence was fixed in the template and left in the live copy

`templates/.aiignore` dropped "Validated by CI hooks and agents before
committing" and the "add your internal hostnames" invitation; `.ai/handoff/
.aiignore` kept BOTH, in the same commit - and that is the copy the new lint
notice names. The live copy is now byte-identical to the template. The test that
missed it named one path; it now DERIVES the copy list from `git ls-files
'*.aiignore'`, so a third copy is covered without anyone remembering, and a
second test fails if template and live copy ever diverge. NOT COVERED: copies
already committed in adopter repositories. Nine of the ten still carry the false
header; CHANGELOG says so and tells them to replace it.

## Shipped code still told users to run the unscoped public name

`bin/aahp.js` closed `aahp init --gates` with "(or: npx aahp check .)" and its
`--help` printed eight more `npx aahp ...` lines. `bin/` is in package.json
`files`, so that shipped to every adopter, naming the one unowned name issue 82
is about. README had a tenth. All corrected.
WHY THE EXISTING CONTROL MISSED THEM: it concatenates three files and all three
are files COPIED into an adopter repo. `bin/aahp.js` is not copied, it is
EXECUTED there and prints instructions. The new control covers `bin/`, with a
deliberately different rule: npx is legitimate for a human running an
uninstalled CLI, but only under the scoped name, so it bans the unscoped
spelling rather than npx as such, and it does NOT strip comments because bin/
has no reason to explain the npx hazard. Scoped name derived from package.json
so a rename cannot leave it asserting a stale string.

## Two ticked acceptance boxes cited test ordinals that did not match

The box claimed the notice turns test 18 red and a quantifier turns test 20 red.
Re-derived by running it: the notice turns test 20 red (18 stays green) and the
quantifier turns test 22 red (20 stays green). A reviewer following that box
mutates the code, watches a test the mutation cannot touch, sees green and
concludes the coverage is real. Every ticked box on the pull request has been
re-derived and the mutation table now names tests, never numbers them; the suite
grew from 24 to 28 to 32 tests during this work and every ordinal shifted twice.

## The gate id itself was never validated, which is the case issue 84 puts in its title

This branch validated the config document and still let the defect through by the
route the issue names. Measured on it before this commit:
  check.only ["forbidden-patterns"] -> exit 1, the violation is caught
  check.only ["forbidden-paterns"]  -> exit 0, "Governance OK: 0 gate(s) ran"
  check.only ["totally-made-up"]    -> exit 0
  check.only []                     -> exit 0
In each of the last three the violation was still in the tree. `check.only` and
`check.skip` items were typed as bare strings with no enum, while
`pinnedDep.location` two sections away had one, and BOTH the new hand validator
and AJV reported the typo config as valid.
That falsified a sentence this branch ships in scripts/aahp-config.mjs: "Every
gate reads its config through here, so validating here means no gate can be
silently switched off by a typo."
Ids are now checked against CHECK_GATES at the point of use, and zero gates ran
no longer prints "Governance OK" - it reports NOT EVALUATED and exits 1, reusing
the words this file already had for an unparseable config rather than inventing
a second vocabulary for the same state.
WHY NOT A SCHEMA ENUM: a copy of the gate ids in the schema is a second source
that drifts the moment a gate is added, and drift there restores the defect with
nothing turning red. The list that runs the gates cannot disagree with itself.
VERIFIED ON LINUX, not on Windows: bats 1.10.0, 28/28 green. Mutation proof:
restoring the unfixed bin/aahp.js turns tests 26, 27 and 28 red while the
control at 25 stays green, BATS_EXIT=1.

## 2026-08-23 - three inert controls, one regression suite (#84, #82, #80)

Three HIGH issues, one shape: a control that could not fail. Fixed together
because a shared suite that proves each one CAN fail closes the class, where
three tests proving each one currently passes would close nothing - every one of
these passed on the day it shipped.

All three reproduced first on `origin/main` at `b67b3cc`, each against a positive
control proving the harness was live.

- **#84** `aahp.config.json` was never validated against its own schema.
  `gateApplies` decides applicability from the PRESENCE of a key, so
  `forbiddenPaterns` read as an absent section and a FAILING gate reported
  `Governance OK`, exit 0, over a live em-dash violation. A config that was not
  even JSON was worse: `readJsonSafe` returned null, the caller substituted `{}`,
  and all eight gates skipped. Now validated before any gate is evaluated, by
  `check`, by `doctor`, and inside `loadConfig` so the direct `npm run check:*`
  path is covered too. `scripts/aahp-schema.mjs` is dependency-free (ADR-002) and
  throws on any schema keyword it does not implement, so it cannot report "valid"
  for a document it did not fully examine. CI cross-checks with AJV.
- **#82** `npx --no-install` does not prevent a registry fetch: `npx` is
  `npm exec`, which has no such option and ignores it silently. Five shipped call
  sites resolved the UNSCOPED, unowned name `aahp`. Replaced with an explicit path
  into the scoped package. Measured today: `GET registry.npmjs.org/aahp` still
  returns 404, so the old behaviour was still correct by accident, not by
  construction.
- **#80** `.ai/handoff/.aiignore` is read by nothing. Both claims that CI validates
  it are withdrawn, and `aahp lint` now names how many patterns it is NOT applying.

**What this did NOT do, and it is an owner decision, not an oversight.** The
firewall was not made real. Making it live would newly fail adopters' builds on
patterns they never chose: the glob vocabulary cannot express what the enforced
regexes do, and the template's `sk-*` (no length floor) matches the word
"task-type" inside AAHP's own shipped templates, so `aahp init` followed by
enforcement is red on an untouched repository - measured, 3 lines in
`GROUNDING.md`, `TRUST.md` and `WORKFLOW.md`. Recommendation in the pull request:
enforce, but as a NEW opt-in section with an empty default, not by activating the
copy every adopter already committed.

**Found while fixing, same class, fixed here.** Four of the thirteen enforced
secret patterns matched nothing: `grep` runs in BRE, where the bare `?` in
`['\"]?` is a literal question mark. `_KEY=`, `_SECRET=`, `_TOKEN=` and
`_PASSWORD=` scored zero on a fixture containing all four. Adding `_CREDENTIALS=`
to that list without escaping the quantifier would have been an anchor that
anchors nothing.

**Still open after this.** The repository's OWN workflows keep
`npx --no-install ajv-cli`, and `scripts/check-workflow-pinning.mjs` Rule B still
requires that spelling while describing it as the load-bearing guard. That claim
is now known to be false. It is left alone deliberately: issue #68 owns the
repository's own workflows, and #82 is scoped to code that ships to consumers.
Named in the pull request as not done.

**Environment note for the next agent.** `tests/lint.bats` test 32 fails on this
Windows machine on unmodified `origin/main` as well - it builds a fake interpreter
directory and prepends it with `PATH="$fake:$PATH"`, and a `C:/...` path splits on
the colon so the fake is never found. Verified against a clean baseline worktree
before concluding it was not a regression. The same trap bit the new suite's npx
spy and is handled there with `cygpath -u`.

## 2026-08-23 - the shipped governance workflow pinned Node 20 against a >=22 floor

`assets/governance/aahp-govern.yml` - the workflow `aahp init --gates` scaffolds
into a consumer repository - pinned `node-version: '20'` while `package.json`
declared `engines.node: ">=22"`. Every repository that scaffolded it installed and
ran the AAHP CLI below the CLI's own engine floor, on a runtime end-of-life since
2026-04-30. It was silent at both ends: npm answers an unmet `engines` range with
an `EBADENGINE` warning and exits 0, so the adopter's gate stayed green while
running unsupported.

The interesting half is why it lasted. `scripts/check-runtime-support.mjs` exists
to assert exactly this relation, and its own header names the file this package
propagates as the reason it was written - but it scanned `.github/workflows/`
only. AAHP propagates by TWO routes: `propagate.sh` copies `aahp-verify.yml`, and
`aahp init --gates` copies `aahp-govern.yml`. The gate covered the first and was
green on every commit while the second violated it. Its two sibling gates,
`tests/assert-workflow-hardening.mjs` and `scripts/check-workflow-pinning.mjs`,
already scanned both directories; the runtime gate was the odd one out.

So the pin is corrected AND the gate now reads `assets/governance/` too, with the
shipped root excluded from the release-vs-build membership check - a job that never
runs here must not vouch for a release runtime nothing proved. Widening a gate's
scope must not let it assert less.

The scan root is OPTIONAL rather than required, unlike its sibling in
`assert-workflow-hardening.mjs`, because this gate also runs against fixture roots
that legitimately ship no template. That leaves a hole - dropping the root would be
silent - and it is closed from the other side: the gate's summary names every file
it scanned, and `tests/runtime-support.bats` asserts the real tree's shipped
template appears in it. Coverage is proved by observation, not assumed from a flag.

Verified locally: `tests/runtime-support.bats` 30/30, `tests/init-gates.bats` and
`tests/workflow-hardening.bats` green, `npm run check` green (10 gates). Mutation
proof both ways - narrowing the gate back to one directory turns the two new
coverage tests red; removing the shipped exclusion turns the membership test red.
Per repository policy the full Bats suite is left to Linux CI, not run on Windows.

Not touched: the template still uses `actions/checkout@v4` and
`actions/setup-node@v4` by tag while this repository's own workflows pin action
SHAs. That is a separate decision about what adopters should read, and
`check-workflow-pinning.mjs` currently passes it, so it is recorded here rather
than changed in a pin fix.
## 2026-08-23 - declare merge=union for the handoff append-log

`.ai/handoff/STATUS.md` is prepend-only, so two branches almost always differ by
one block and nothing else. Eight sibling repositories in this estate already
declare `merge=union` for it; this one did not, and the two that lacked it are
exactly the two where twenty-two rebases on 2026-08-23 each resolved this file by
hand.

It does not stop a pull request going CONFLICTING - GitHub does not honour merge
drivers server-side, measured 2026-07-31 - so this removes the hand resolution,
not the merge. `MANIFEST.json` is deliberately left without a driver: it is
generated state, and the correct resolution is to take main's copy and recompute
the changed entries, which no driver can do.

# AAHP: Current State of the Nation

> Last updated: 2026-08-23 by claude (workflow hardening: declared permissions + no persisted checkout credential, in CI and in the shipped template; reconciled with main, which had meanwhile taken the doctor content check, the verify-workflow gate and the release-authorization assertions)
> Commit: (review branch, pending commit)
>
> **Rule:** This file is rewritten (not appended) at the end of every session.
> It reflects the *current* reality, not history. History lives in LOG.md.

---

<!-- SECTION: summary -->
AAHP **v3.10.0** (npm `@elvatis_com/aahp`) is prepared on a review branch. It has not
been tagged, published, or merged. The release changes Layer 2 in two bounded ways:

- CI diffs are anchored to an explicit base commit. Pull requests pass their base SHA,
  pushes pass the event `before` SHA, and manual runs require an input. Missing, zero,
  invalid, unreadable, HEAD-equal, and undiffable bases fail closed.
- An optional `handoffImpact.nonImpactingModifiedFiles` list can classify one exact
  content-only regular tracked-file modification (`M`) as non-impacting when the old and
  new Git modes match and it carries a visible review reason. A/D/R/C, mode changes,
  mixed source changes, config changes, and handoff changes remain impacting. The
  Node/Python runtime parser and schema reject unsafe, invisible, or ambiguous policy.

The actor-wide dependency-bot workflow bypass is removed. Layer 1 now runs for every
actor. The package now includes the workflow that `propagate.sh` installs. The gate
remains verify-only and never regenerates handoff state.

Separately, the published RUNTIME SUPPORT CLAIM is corrected. `engines.node` was
`>=18` (end of life 2025-04-30) while CI validated on Node 20 (end of life
2026-04-30), and the `aahp-verify.yml` that `propagate.sh` installs carried the same
dead pin, so every consumer inherited the claim on install. Nothing could go red
about it: the pins were internally consistent, just uniformly dead. `engines.node` is
now `>=22`, CI validates on 22 and 24, and `check:runtime-support` asserts the
RELATION between the two so neither side can rot alone.

On top of that, `aahp doctor` gains a **`verify-workflow`** gate: it audits the
consumer's own `.github/workflows/` and reports whether the workflow that hosts the
AAHP gate can SKIP it. A job-level or step-level `if:` around the gate leaves a
required status check that keeps its name and reports success having evaluated
nothing, so branch protection is satisfied by a verdict nobody produced, and Layer 1
MANIFEST checksum integrity goes missing along with the Layer 2 drift gate. AAHP
could not see this from inside itself: the workflow it ships is unconditional and
`propagate.sh` copies it verbatim, so the weakening only ever exists downstream. The
canonical workflow's last step runs `aahp doctor`, so a consumer that has weakened
its gate now reports it on its own pull requests. It is asserted as a CONSEQUENCE
("there exists an event on which this workflow concludes success without having run
the gate at `--level ci`"), it fails closed on a shape it cannot classify, and it was
measured against every consumer of this protocol before shipping.

Release authorization in `ci.yml` is now asserted. The `publish` job (npm,
`id-token: write`) and the `release` job (the GitHub Release) each carried a
hand-written `if:`, the two disagreed about what counts as a release, and nothing in
this repository read either one, so the drift was invisible and any later edit to
publish authorization would have been equally silent. The release definition is now
written once and both jobs must use exactly it; every additional top-level `||`
operand on the publish condition must appear in a literal recorded list. No workflow
behaviour changes: whether the `workflow_dispatch` operand should exist at all is the
owner's decision and is recorded as open, with its options, in ADR-019.
`aahp doctor` also stops letting a green `handoff-set` line read as an integrity
verdict. That gate compares the file SET and the INDEX and hashes nothing, which is
the documented split: ADR-011 makes `aahp verify` the owner of handoff drift, and
Layer 1 hashes each indexed file itself. Layer 1 also runs `aahp lint`, which
compares them again, but only under a Python interpreter and exiting 0 when there is
none, so lint is not a substitute for the gate. The pass reason said only "N indexed
files present, no strays", so a reader who had not read the ADR could take a green
line for an integrity verdict. It now adds "(content not compared; aahp verify
Layer 1 owns checksum integrity)", the same honest-summary treatment
`scripts/lint-handoff.sh` received in 3.9.0 (the CHANGELOG records it under 3.8.3,
a version number that was never published). No gate changed behaviour and no exit
code moved. The LIMIT is now stated in the source comment, in the README and in the
CHANGELOG rather than only in the pull request: only the default human-readable
`doctor` output carries the new reason, while `--json`, `--quiet` and `--governance`
do not, and those three are the invocations consumers wire into CI and hooks, so the
`schemaVersion: 1` record a dashboard ingests says exactly what it said before.
README also names the one configuration where the split has consequences for an
adopter: `verify-workflow` reporting `skip` while the handoff gates are evaluated
means no automated gate in that repository compares a handoff checksum.
Separately, the two required status checks that validate `MANIFEST.json` no longer
download and execute unpinned third-party code. `lint-and-validate` and
`aahp-manifest` ran `npm install --no-save ajv-cli ajv-formats` and executed the
result on the next line, on every push and every pull request, so 27 packages
arrived with nothing in this repository constraining any of them and one
compromised release anywhere in that closure was arbitrary code execution inside
the checks whose verdict certifies a change. Both packages are now exact
devDependencies locked by integrity hash, both jobs install that closure with
`npm ci`, and both invoke the tool with `npx --no-install`. The root cause was not
the forgotten pin: the workflow template this package ships to consumers
(`assets/governance/aahp-govern.yml`) has always used the correct form, and the
workflows that only ever ran here did not, because nothing made them.
`check:workflow-pinning` is that something.
<!-- /SECTION: summary -->

---

<!-- SECTION: build_health -->
## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| npm version | READY | package, lockfile, changelog, CLI help, and handoff surfaces set to 3.10.0 |
| `tests/handoff-impact.bats` | FOCUSED PASS | 24 pass + 3 Windows skips; empty base, staged/CI endpoint modes, parser parity, M-only, A/D/R/C, mixed and diff failures pass; schema passed separately; symlink case awaits Linux CI |
| `tests/propagate.bats` | FOCUSED PASS | 2/2; source checkout and installed npm tarball propagate byte-identical gate, parser, and workflow |
| `tests/verify.bats` | FOCUSED PASS | 22/22 under Git Bash with explicit CI bases |
| schema validation | FOCUSED PASS | example and repository config both validate against the updated schema |
| shell syntax | FOCUSED PASS | changed shell scripts parse under Git Bash |
| `tests/verify-workflow.bats` | FOCUSED PASS | 21/21; both directions, the two fail-closed shapes that must NOT be findings, plus parser parity against a real YAML parser on 16 workflow files |
| `npm run check` | PASS | changelog, version sync, claims, forbidden patterns, schema/doc sync, doc links, runtime support, workflow pinning, and handoff freshness |
| `tests/runtime-support.bats` | FOCUSED PASS | 16/16; the relation holds on this repo and each of nine mutations turns it red, including the emptied-matrix trap |
| `tests/workflow-pinning.bats` | FOCUSED PASS | 19/19; every rule holds on this repository and each way of breaking one turns the gate red at the exact documented exit code, 1 for a finding and 2 for a state it cannot evaluate |
| shellcheck | LINUX PASS | replacement head `c332a23` reached the full Bats step after shellcheck |
| hosted Linux suite | REPLACEMENT REQUIRED | `c332a23` passed 361/362; the CI mode fixture let `git add` restore mode 100644 on Linux, so it now reasserts 100755 before its content-plus-mode commit |
| `tests/doctor.bats` (3 new tests) | FOCUSED PASS | the three content-drift tests pass under Git Bash; two were mutated red and restored green. The other 16 tests in the file were not run on Windows; Linux CI is authoritative |
| `tests/workflow-hardening.bats` | FOCUSED PASS | run under Git Bash filtered to the two load-bearing assertions (the repository's own workflows and its shipped template), green before the mutation and red after deleting the `permissions:` block from `assets/governance/aahp-govern.yml`. The file's thirteen fixture expectations were additionally exercised in-process against the gate's `audit()`, all thirteen returning the exact expected exit code (1 for a real problem, 2 for a state the gate cannot decide). The file holds **24** tests, not the 21 an earlier revision of this row claimed: it carried 20 when that row was written, and the four listed next were added afterwards. Those four were then run under Git Bash and are green, `1..4`, exit 0: they pin what `tests/assert-repo-ci-shape.mjs` does with a root that does not hold every workflow it records (green, and the elevation it could not check named on stderr) and with one that holds an unreadable, unparseable or missing file (exit 1 with a stated finding, never a thrown `ENOENT`). The rest of the file is left to Linux CI, which is authoritative here: a Windows box running many suites at once takes hours per pass. |
| `tests/assert-repo-ci-shape.mjs` (reconciled) | FOCUSED PASS, BOTH DIRECTIONS | The authored reconciliation of the three-way divergence described in What is Missing. Baseline on the merged tree: 8/8 release-authorization tests in `tests/runtime-support.bats` and 7/7 elevation-and-guard tests in `tests/workflow-hardening.bats`, 15 across the two pull requests, all green. Each family was then mutated on the real workflow it guards, with the mutation verified on disk before anything was run and the untouched neighbours counted, so a mutation that failed to apply could not be reported as a proof. **A**: `jobs.release.if` in `ci.yml` changed to `startsWith(github.ref, 'refs/tags/')`. The gate emits exactly one finding, `jobs.release.if is not the recorded release definition`, `EXIT=1`; the two release-authorization tests that require exit 0 (1 and 7) go red, `BATS_EXIT=1`. The permission family is NOT untouched by this mutation and an earlier version of this row said it was: two of the seven tests in `tests/workflow-hardening.bats` go red as well (`the release-path elevations are still declared on this repository` and `a root with only package.json and ci.yml is green`), because those two invoke the SHAPE gate rather than `assert-workflow-hardening.mjs`, and one copies the real `ci.yml` into its fixture. The asymmetry belongs to **B** alone: `codeql.yml` appears in no fixture, so mutating it cannot reach the release-authorization family. **B**: `security-events: write` deleted from the `analyze` job in `codeql.yml` - an anchored count, because the same string also appears in a comment on line 10, so the naive count reads 2 and 1 rather than 1 and 0. The gate emits exactly one finding, `job 'analyze' no longer declares 'security-events: write'`, `EXIT=1`; `the release-path elevations are still declared on this repository` goes red, `BATS_EXIT=1`, while all EIGHT release-authorization tests stay green, which is the cross-check that the two sections are independent and both live. The **A** direction was re-measured after review, at the GATE level: with the release condition mutated, `assert-repo-ci-shape.mjs` exits 1 and `assert-workflow-hardening.mjs` exits 0, file restored md5-identical. That re-measurement was of the GATES only. It does not carry over to the bats families, which is what the sentence above now records instead. Both files restored byte-identical by md5 to their pre-mutation backup, gate back to `repo CI shape OK` `EXIT=0`, and both families re-run green. The full suite is left to Linux CI, which is authoritative here. |
| full Bats suite | CI | deliberately not run on Windows; Linux CI is authoritative |
| `tests/runtime-support.bats` (release authorization) | FOCUSED PASS | 8/8 added; the untouched repository shape is green, six one-line mutations of the REAL `ci.yml` each turn it red at exit 1 (including a publish job with no `if:` at all), and a reformat of the same expression stays green |
| `tests/cli.bats` injection block | FOCUSED PASS | 3/3; the CLI injection test now asserts the detector fired, on a checksum-clean tree, and covers all ten patterns by name. Emptying `INJECTION_PATTERNS` turns it red; the previous test reported ok under that same mutation |
| injection mutation proof | RE-VERIFIED | independently re-run. Under `INJECTION_PATTERNS=()`, one bats process reports `ok` for the pre-fix test body and `not ok` for the replacement, exit 1; restored, both `ok`, exit 0. With only the check 4 checksum comparison disarmed the replacement still passes, so its status comes from the injection check and not from the setup |
| injection pattern coverage count | CORRECTED | six of ten patterns were uncovered before this branch, not five. The safety-override entry, sixth in `INJECTION_PATTERNS`, was missed by counting bare substrings: `tests/lint.bats` contains the bare word `override` in a line the pattern itself does not match. This row deliberately does not quote the pattern, because writing it here makes the linter flag this file, which is the detector working |
<!-- /SECTION: build_health -->

---

<!-- SECTION: components -->
## Components

| Component | Path | State | Notes |
|-----------|------|-------|-------|
| Verify gate | `scripts/verify-handoff.sh` | Changed | explicit base, fail-closed diff, name-status classifier |
| Shared library | `scripts/_aahp-lib.sh` | Changed | Node/Python runtime parser for reviewed impact config |
| Required workflow | `.github/workflows/aahp-verify.yml` | Changed | no actor bypass; explicit base; read-only token; immutable action pins; evaluator-path trust boundary documented |
| Config schema/example | `schema/aahp-config.schema.json`, `aahp.config.example.json` | Changed | additive `handoffImpact` contract |
| CLI | `bin/aahp.js` | Changed | verify help documents `--base SHA` |
| Conformance gate | `bin/aahp.js` (`gateHandoffSet`) | Changed | pass reason names the content check it does not run, and a header comment states the ADR-011 boundary; behaviour, gate statuses and the JSON record are unchanged |
| Scaffolded governance workflow | `assets/governance/aahp-govern.yml` | Changed | header now states that it runs no handoff-integrity gate and that a repository keeping `.ai/handoff/` needs `aahp-verify.yml` beside it; comment only |
| Specification | `README.md` | Changed | Section 2.8 and ADR-018 define the contract |
| Rollout | `scripts/ROLLOUT.md` | Changed | consumer propagation and mutation checks documented |
| Manifest generator | `scripts/aahp-manifest.sh` | Changed | `project` resolves from repository identity (recorded name, then git remote), not from the directory it runs in |
| Runtime-support gate | `scripts/check-runtime-support.mjs` | New | relation between CI pins and `engines.node`; one dated constant; exits 2 when it cannot evaluate |
| Runtime matrix | `.github/workflows/ci.yml` | Changed | new `runtime-matrix` job on Node 22 and 24; `lint-and-validate` deliberately left unmatrixed so the required check keeps its literal name |
| verify-workflow gate | `scripts/check-verify-workflow.mjs` | New | audits the consumer's workflows for a gate that can skip itself; zero runtime dependencies, so it carries its own block-YAML reader, held against a real parser by `tests/assert-workflow-parser-parity.mjs` |
| Workflow-hardening gate | `tests/assert-workflow-hardening.mjs` | New | every document under `.github/workflows/` AND `assets/governance/` must declare a top-level `permissions:` mapping and set `persist-credentials: false` on every checkout; scanning zero files exits 2, never 0 |
| Shipped governance template | `assets/governance/aahp-govern.yml` | Changed | declares `contents: read` and refuses the persisted checkout credential; this is the only file in the change with reach beyond this repository |
| Repository workflows | `.github/workflows/*.yml` | Changed | six gained a top-level `contents: read`; the nine remaining checkouts IN THIS DIRECTORY set `persist-credentials: false`, and the tenth this branch sets is in the shipped template, row above. Nine is the `.github/workflows`-only figure, never the repository total: measured 2026-08-22 there are eleven checkout steps across both locations, one of which (`aahp-verify.yml`) already set the flag, so all eleven set it after this change. The three job-level elevations are unchanged and now pinned by name in `tests/assert-repo-ci-shape.mjs` |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency |
| Repo-shape assertion | `tests/assert-repo-ci-shape.mjs` | Changed | third assertion: `publish` and `release` share ONE release definition, and every publish operand beyond it is recorded literally; reads the parsed condition, runs inside the required `lint-and-validate` |
| Workflow-pinning gate | `scripts/check-workflow-pinning.mjs` | New | no project-level `npm install` in a workflow, every `npx` carries `--no-install`, every package a workflow executes is declared here at an exact version, every direct dependency is locked with `resolved` and `integrity`; exits 2 on a state it cannot evaluate |
| Schema validation steps | `.github/workflows/ci.yml`, `.github/workflows/aahp-manifest.yml` | Changed | install the locked closure and run `ajv-cli` with `npx --no-install` instead of installing two undeclared packages from the registry on every run |
| Release surfaces | `package*.json`, `CHANGELOG.md` | Changed | v3.10.0 prepared, workflow included in npm artifact, not released; `engines.node` now `>=22`, `yaml` added as a devDependency, `ajv-cli` 5.0.0 and `ajv-formats` 3.0.1 pinned exactly |
<!-- /SECTION: components -->

---

<!-- SECTION: what_is_missing -->
## What is Missing

| Gap | Severity | Description |
|-----|----------|-------------|
| Linux CI evidence | HIGH | Required before merge; the full suite and shellcheck belong on the hosted Linux runner. |
| Release | NORMAL | Do not tag or publish until review is merged and the release ceremony is explicitly authorized. |
| Evaluator path protection | HIGH | The supplied `pull_request` workflow executes proposed workflow and gate code. A consumer must require trusted review for evaluator paths or supply a default-branch evaluator; v3.10.0 cannot configure repository rules. |
| Delete-both-sides Layer 1 hole | MEDIUM | Pre-existing: removing a canonical handoff file and its index entry still needs a required-set protocol decision. |
| Windows CI runner | MEDIUM | Pre-existing: Git Bash behavior is locally focused-tested, but CI remains Linux-only. |
| `runtime-matrix` not a required check | HIGH | The new job reports `Runtime matrix (22)` and `Runtime matrix (24)`. Until an owner adds them to branch protection they can go red without blocking a merge. The relation gate itself runs inside the required `lint-and-validate`, so the claim is still enforced. |
| SemVer call for `engines.node` | NORMAL | Narrowing `>=18` to `>=22` is a support-surface reduction. Whether it ships inside 3.10.0 or forces 4.0.0 is an owner decision, not one this branch takes. |
| `aahp-verify` can skip itself in six consumers | HIGH | ORIGINATED HERE. `458dbbd` (2026-06-30) added the dependency-bot exemption to this repository's own reference workflow, gating Checkout and every gate step; it shipped that way in v3.6.0 and propagated. `#65` removed it here on 2026-08-21. MEASURED 2026-08-22 with the new `verify-workflow` gate, against every consumer: six report `bypassable`, three report `enforced`. Five of the six report success having checked out nothing, so Layer 1 never runs either. The sixth was previously recorded here as corrected and is only PARTLY so: its checkout is unconditional and a bot change does get a Layer 1 run, but `--level ci` is still gated on the author, so the same required check name means all four layers for one author and Layer 1 for another. Only the owning repositories can re-propagate; this branch cannot fix any of them. Consumer identities are tracked privately and deliberately not recorded in this public repository. |
| No drift check between a consumer's propagated workflow and the installed package | PARTLY CLOSED | `aahp doctor` still never compares `.github/workflows/aahp-verify.yml` on disk against the one in the installed package, so a consumer can pin 3.10.0 and run the v3.6.0 workflow. The designed predicate this row asked for now exists for the case that matters: `verify-workflow` asks whether the hosting workflow can skip the gate, which tolerates deliberate divergence (a consumer may restructure the file freely) while catching the divergence that voids the check. General byte-level drift, for example an older action pin or a dropped `fetch-depth: 0`, is still unmeasured. |
| `npm install -g npm@latest` in the publish job | HIGH | Left in place deliberately. It is the only unpinned install inside the job that holds `id-token: write` immediately before `npm publish --provenance`, and it is a different risk class from the `ajv` path: the supplier is the package manager itself. The open question is whether the step should be DELETED rather than pinned, because its comment asserts that OIDC trusted publishing needs npm >= 12 while the pinned Node 24 line already ships npm 11.12.1, and that assertion is unverified. Owner decision, tracked at https://github.com/homeofe/AAHP/issues/68. The pinning gate names this exclusion in its header rather than hiding it in an exemption list. |
| No dependency-scanning workflow | HIGH | No workflow here performs a dependency or supply-chain scan, and `.github/dependabot.yml` has no `github-actions` ecosystem entry. Which scanner to adopt, and whether to make it a seventh required status check, is an owner decision: adding a required context blocks every pull request until the check reports at least once. Tracked at https://github.com/homeofe/AAHP/issues/68. |
| `ajv-cli` depends on `fast-json-patch` 2.2.1 | MEDIUM | GHSA-8gh8-hqwg-xf34, prototype pollution, fixed in 3.1.1. `ajv-cli` 5.0.0 requires `^2.0.0`, so the advisory cannot be resolved without an `overrides` entry that crosses a major version of a transitive dependency. This exposure is not new: the same closure was already being downloaded and executed on every CI run. Declaring the packages is what made it visible to `npm audit` and to Dependabot. |
| Adopters keep an unhardened `aahp-govern.yml` | MEDIUM | OWNER DECISION. `aahp init --gates` skips a workflow that already exists (`bin/aahp.js`), so a repository that scaffolded the governance workflow before this change keeps the copy with no `permissions:` block and a persisted checkout credential, and will keep it forever unless somebody re-runs with `--force`. The CHANGELOG says so, which reaches people who read release notes and nobody else. Options: (a) leave it as a release note, (b) have `aahp doctor` report a scaffolded `aahp-govern.yml` that lacks either property, so an adopter sees it on their own pull requests, (c) make `init --gates` upgrade this specific file in place. (b) is the one that matches how `verify-workflow` already reports a weakened gate from inside the consumer. Not taken here: it changes `doctor`'s output contract, which is a separate decision from hardening the file. |
| `persist-credentials: false` on the release path unproven in a real tag run | NORMAL | OWNER CONFIRMATION. The evidence that the change is behaviour-preserving is direct: no workflow in this repository runs `git push`, `git commit`, `git fetch`, `git pull` or `git remote`, none uses a credential-writing action, and the only `secrets.` reference passes `GITHUB_TOKEN` to `gh release create` as an environment variable, which does not read `.git/config`. The `publish` job authenticates to npm by OIDC, which is delivered through environment variables and is unaffected by checkout options. But `publish` and `release` only ever run on a version tag, so no pull-request CI run exercises them. Confirm on the first tag build after this merges. |
| Mutable action tags and `sha_pinning_required` | NORMAL | Out of scope here and deliberately not bundled: TEN of the eleven `actions/checkout` references use the mutable `@v4` tag rather than an immutable SHA, and the repository setting `sha_pinning_required` is `false`. Re-measured 2026-08-22 over `.github/workflows/*.yml` and `assets/governance/*.yml` together, exactly one reference is pinned to a 40-hex commit SHA, in `aahp-verify.yml`; the earlier figure of nine counted `.github/workflows/` only while stating a total of eleven that includes the shipped template, so it understated the exposure by one, and by the file that reaches consumers. Same class of exposure as this change, different fix, tracked at https://github.com/homeofe/AAHP/issues/68 and https://github.com/homeofe/AAHP/issues/71. |
| npm lifecycle scripts in CI | NORMAL | Not addressed by this change and should not be read as closed by it: `npm ci` in `ci.yml` runs without `--ignore-scripts`, so lifecycle scripts from the whole dependency tree execute in the same job as the checkout. Removing the persisted credential removes what those scripts could have read from `.git/config`; it does not stop them running. The shipped template already uses `npm ci --ignore-scripts`. |
| Reconciliation with https://github.com/homeofe/AAHP/pull/89 | DISCHARGED ON THIS BRANCH | #89 merged 2026-08-22 as `20ab708`; `origin/main` is merged into this branch as of this commit. The two changes were each green on their own CI and jointly red, and neither pull request's CI could see it because each was tested against a base that lacked the other. The resolution was AUTHORED rather than merged, because no merge rule could have produced it: `tests/assert-repo-ci-shape.mjs` diverged THREE ways from a common 63-line ancestor - main grew the same region to 370 lines, this branch to 228, and neither side contained a single line of the other. Taking `theirs` would have deleted this branch's permission assertions; taking `ours` would have deleted a gate already merged on main and left #89's eight tests either red or, worse, green and vacuous. The file now carries BOTH sections on top of this branch's guarded reads: main's release-authorization section as section 3 (`RELEASE_REF_CONDITION`, 7 occurrences, matching main exactly) and this branch's job-permission section as section 4 (`REQUIRED_JOB_PERMISSIONS`, 2 occurrences, matching this branch exactly). The guards are what let #89's fixture root, which holds only `package.json` and `ci.yml`, stay green instead of throwing `ENOENT`. Both gate families were then proved non-vacuous by mutating the REAL workflows rather than the gate: see the build-health row. README carries ADR-019 and ADR-020 in order with no gap, so the numbering gap noted earlier is closed. |
| Consumer manifests already rewritten | MEDIUM | The generator no longer writes a checkout's directory name into `project`, but repositories whose committed `MANIFEST.json` already carries such a name keep it, because a recorded name is preserved by design. Those values need correcting in the consumer repositories. |
| Manual publish path on the `ci.yml` `publish` job | NORMAL | OPEN OWNER DECISION, deliberately not taken here. The publish condition still accepts `workflow_dispatch`, which constrains no ref, so a manual run publishes from whichever ref it started on with no tag and no GitHub Release. Options A, B and C, and what each one requires, are in ADR-019. The condition is now pinned, so adopting any of them is a visible two-part edit rather than a silent one. |
<!-- /SECTION: what_is_missing -->

---

## Next Actions

1. Regenerate `MANIFEST.json` and run the focused repository gates.
2. Push the review pull request replacement head and let hosted Linux CI run the full suite and shellcheck.
3. Do not tag, publish, or merge from this session.
4. Decide the three owner questions in "What is Missing" above: how adopters holding an
   unhardened `aahp-govern.yml` are reached, confirmation of the release-path checkout
   change on the first tag build, and whether the mutable action tags are taken next.
5. The hardened `assets/governance/aahp-govern.yml` reaches adopters only when a version
   is published. Nothing in this change bumps the version, because the release ceremony
   is a separate, authorized step in this repository and several changes share the
   `[Unreleased]` block.
6. DONE, recorded here because the instruction that stood in its place was wrong in
   two ways and a later reader would otherwise repeat it. https://github.com/homeofe/AAHP/pull/89
   is merged (`20ab708`) and `origin/main` is merged into this branch, so the ordering
   it demanded is already satisfied - the "What is Missing" row above records it as
   DISCHARGED. And the resolution it prescribed, keeping both sides of
   `tests/assert-repo-ci-shape.mjs`, does NOT work for that file: the two sides overlap
   on the header, the `package.json` read and the `ci.yml` read, so keeping both yields
   duplicate declarations rather than a union. The file was authored into one text
   carrying both the release-authorization section and the job-permission section.
   `README.md` and `CHANGELOG.md` were keep-both, which is correct for those two.
