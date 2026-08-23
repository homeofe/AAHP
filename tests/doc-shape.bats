#!/usr/bin/env bats
# doc-shape.bats - scripts/check-doc-shape.mjs, the gate behind issue #74 and
# ADR-022: a repo-relative path a document tells you to use has to resolve
# against this repository, and the setup heading a newcomer needs has to exist
# and come before the rationale material.
#
# Every test below names the exact thing a reviewer deletes to turn it red, and
# the file carries a CONTROL for each group so that a suite failing everything is
# distinguishable from a suite catching something. The three exit codes are
# asserted by number, never as "non-zero": this gate's whole point is that
# "could not assess" (2) is a different answer from "assessed and found a
# problem" (1), and a test that accepted either would not notice them swapping.

load test_helper

GATE="$SCRIPTS_DIR/check-doc-shape.mjs"

# A tracked fixture repository shaped like the real one at the point the defect
# existed: assets/governance/aahp-govern.yml is the real governance workflow, and
# .github/workflows/ holds aahp-verify.yml and NOT aahp-govern.yml. The .github
# entry has to be tracked or the whole class is out of scope by the first filter,
# and the tests that assert a finding would pass vacuously.
# TEST_TMPDIR is already a git repo with one empty commit (test_helper.bash), so
# tracked-ness here means `git add`.
seed_repo() {
    mkdir -p "$TEST_TMPDIR/assets/governance" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/.github/workflows"
    echo "name: govern" > "$TEST_TMPDIR/assets/governance/aahp-govern.yml"
    echo "name: verify" > "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    echo "echo hi" > "$TEST_TMPDIR/scripts/real-script.sh"
    git -C "$TEST_TMPDIR" add -A
}

mkconfig() {
    cat > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add aahp.config.json
}

mkreadme() {
    cat > "$TEST_TMPDIR/README.md"
    git -C "$TEST_TMPDIR" add README.md
}

# ─── control: the gate is inert without configuration ───────────────────────

@test "doc-shape: no docPaths config is a clean no-op" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `nowhere/at/all.yml` into place.
EOF
    mkconfig <<'EOF'
{ "docLinks": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not configured"* ]]
}

# ─── assertion 1: a path presented as this repository's must resolve ─────────

@test "doc-shape CONTROL: a path that resolves passes" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `assets/governance/aahp-govern.yml` into place.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Doc shape OK"* ]]
}

@test "doc-shape: reproduces issue #74 - a copy source that does not exist is a finding" {
    # The defect verbatim: assets/governance/aahp-govern.yml is the real file, and
    # the README named a .github/workflows/ path that this repository does not have.
    seed_repo
    mkreadme <<'EOF'
# Fixture
For governance copy the portable `.github/workflows/aahp-govern.yml` beside it.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *".github/workflows/aahp-govern.yml"* ]]
    [[ "$output" == *"git does not track it"* ]]
}

@test "doc-shape: a directory that is only a prefix of tracked files resolves" {
    # `assets/governance` is not itself a tracked object; it is the parent of one.
    # Without the prefix set this test is red, which is the anchor: delete the
    # trackedDirs loop in the gate and only this test goes red.
    seed_repo
    mkreadme <<'EOF'
# Fixture
The workflow lives under `assets/governance`.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "doc-shape: a path whose first segment is not tracked here is out of scope" {
    # The filter that makes this gate usable at all. `packages/` and `.claude/`
    # describe an ADOPTER's tree, and 46 of 78 path-shaped spans in the real
    # README are of that kind. Anchor: the trackedTopLevel guard in candidatePath.
    seed_repo
    mkreadme <<'EOF'
# Fixture
Your harness prompt lives at `.claude/CLAUDE.md` and your app at `packages/api/src`.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "doc-shape: globs and fenced code are not paths" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
Lint `scripts/*.sh` before committing.

```bash
cp scripts/not-a-real-file.sh /somewhere
ls `scripts/also-not-real.sh`
```
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── the counted exception list ─────────────────────────────────────────────

@test "doc-shape CONTROL: a declared exception with the recorded count passes and is reported" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
`aahp init --gates` writes `.github/workflows/aahp-govern.yml` into your repository.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "destination in an adopting repository" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not assessed"* ]]
    [[ "$output" == *"destination in an adopting repository"* ]]
}

@test "doc-shape: a SECOND, unreviewed mention of a declared path is a finding" {
    # This is the test that stops the exception list from disarming the gate. A
    # bare allowlist would exempt the re-introduced defect below, because it is
    # the same string as the legitimate destination mention above it.
    seed_repo
    mkreadme <<'EOF'
# Fixture
`aahp init --gates` writes `.github/workflows/aahp-govern.yml` into your repository.
For governance copy `.github/workflows/aahp-govern.yml` from this repository.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "destination in an adopting repository" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"records 1 occurrence(s)"* ]]
    [[ "$output" == *"contain 2"* ]]
}

@test "doc-shape: an exception matching nothing is a finding" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
Nothing to see here.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "destination in an adopting repository" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dead exception"* ]]
}

@test "doc-shape: an exception with no occurrences count is refused by the schema, at exit 2" {
    # occurrences is required in schema/aahp-config.schema.json, so this is caught
    # before the gate runs a single assertion. Exit 2, because nothing was
    # assessed - not exit 0, which is the failure mode this whole file is about.
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `.github/workflows/aahp-govern.yml`.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml",
                      "reason": "no count" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"occurrences"* ]]
}

@test "doc-shape: a whitespace-only reason is a finding" {
    # The schema's minLength: 1 accepts a single space, so this is the runtime
    # guard's own reachable case, not a duplicate of the schema. Anchor: the
    # `reason.trim()` in the declared loop. Replace it with `entry.reason` and
    # only this test goes red.
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `.github/workflows/aahp-govern.yml`.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "   " } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-empty reason"* ]]
}

@test "doc-shape: the same path declared twice is a finding" {
    # JSON Schema cannot express uniqueness over an object array by one key, so
    # this is the runtime guard's second reachable case. Two entries means one
    # reason is dead text, and a reader cannot tell which one is live.
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `.github/workflows/aahp-govern.yml`.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "adopterPaths": [ { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "first reason" },
                    { "path": ".github/workflows/aahp-govern.yml", "occurrences": 1,
                      "reason": "second reason" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"twice"* ]]
}

# ─── assertion 2: the required setup heading ────────────────────────────────

@test "doc-shape CONTROL: the required heading present before its anchor passes" {
    seed_repo
    mkreadme <<'EOF'
# Fixture

## Installation and Quickstart

Install it.

## 7. Architectural Decision Log

Rationale.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "requiredHeadings": [ { "id": "setup", "file": "README.md",
    "pattern": "^#{1,3} .*(Install|Quickstart)",
    "before": "^## 7. Architectural Decision Log" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "doc-shape: reproduces issue #74 part 2 - no setup heading is a finding" {
    seed_repo
    mkreadme <<'EOF'
# Fixture

## 7. Architectural Decision Log

Rationale, and buried inside it: npm i -g the-package.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "requiredHeadings": [ { "id": "setup", "file": "README.md",
    "pattern": "^#{1,3} .*(Install|Quickstart)",
    "before": "^## 7. Architectural Decision Log",
    "note": "A new adopter cannot find install." } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no line matches the required heading [setup]"* ]]
    [[ "$output" == *"A new adopter cannot find install."* ]]
}

@test "doc-shape: a setup heading AFTER its anchor is a finding" {
    # The defect issue #74 actually described: the install command existed, at 58%
    # depth, under a heading about decisions. Present is not the same as findable.
    seed_repo
    mkreadme <<'EOF'
# Fixture

## 7. Architectural Decision Log

Rationale.

## Installation and Quickstart

Install it.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "requiredHeadings": [ { "id": "setup", "file": "README.md",
    "pattern": "^#{1,3} .*(Install|Quickstart)",
    "before": "^## 7. Architectural Decision Log" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"at or after its anchor"* ]]
}

@test "doc-shape: an anchor that cannot be found is a finding, not a pass" {
    # An ordering that cannot be judged must not read as an ordering that holds.
    seed_repo
    mkreadme <<'EOF'
# Fixture

## Installation and Quickstart

Install it.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "requiredHeadings": [ { "id": "setup", "file": "README.md",
    "pattern": "^#{1,3} .*(Install|Quickstart)",
    "before": "^## 7. Architectural Decision Log" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no line matches that anchor"* ]]
}

# ─── could-not-assess is exit 2, and is never a pass ────────────────────────

@test "doc-shape: outside a git work tree the gate exits 2" {
    # Same technique as gates-portability.bats: setup() git-inits TEST_TMPDIR and
    # the mktemp base has no git-repo ancestor, so removing .git puts the target
    # genuinely outside any work tree. The sibling gates exit 1 there; this one
    # exits 2, because "I could not enumerate" is not "I enumerated and found
    # nothing wrong" and it is not "I found something wrong" either.
    seed_repo
    mkreadme <<'EOF'
# Fixture
Copy `assets/governance/aahp-govern.yml` into place.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"] } }
EOF
    rm -rf "$TEST_TMPDIR/.git"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"work tree"* ]]
}

@test "doc-shape: an include that matches no tracked file exits 2, never 0" {
    seed_repo
    mkconfig <<'EOF'
{ "docPaths": { "include": ["DOES-NOT-EXIST.md"] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must not report clean"* ]]
}

@test "doc-shape: a required heading in an untracked file exits 2, never 0" {
    seed_repo
    mkreadme <<'EOF'
# Fixture
Nothing here.
EOF
    mkconfig <<'EOF'
{ "docPaths": { "include": ["README.md"],
  "requiredHeadings": [ { "id": "setup", "file": "GUIDE.md",
    "pattern": "^## Install" } ] } }
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not tracked"* ]]
}

# ─── the gate has to actually RUN, and this repository has to pass it ───────

@test "doc-shape: the gate is wired into the aggregate check chain" {
    run node "$AAHP_ROOT/tests/assert-doc-shape-wired.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-shape gate wiring OK"* ]]
}

@test "doc-shape dogfood: this repository passes its own gate" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Doc shape OK"* ]]
}
