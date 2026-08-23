#!/usr/bin/env bats
# workflow-hardening.bats - every workflow this repository runs, and every
# workflow it SHIPS, declares its own GITHUB_TOKEN permissions and keeps that
# token out of the job workspace.
#
# Every test asserts in BOTH directions: the property holds on the real
# repository, and each way of breaking it turns the gate red with an EXACT exit
# code. A gate proved only in the passing direction is indistinguishable from a
# gate that cannot fail, and "non-zero" hides the difference between "found a
# problem" (1) and "could not decide" (2).
#
# The load-bearing test is the first one. It runs the gate over the real
# repository, so deleting the `permissions:` block from
# assets/governance/aahp-govern.yml - the file adopters actually receive - is
# what turns it red.

load test_helper

GATE="$AAHP_ROOT/tests/assert-workflow-hardening.mjs"
SHAPE_GATE="$AAHP_ROOT/tests/assert-repo-ci-shape.mjs"

# The gate scans two roots. Both must exist and hold at least one document, so
# every fixture writes both.
wf_dir() { printf '%s/.github/workflows' "$TEST_TMPDIR"; }
asset_dir() { printf '%s/assets/governance' "$TEST_TMPDIR"; }

# The baseline fixture: one compliant document in each scan root. Every mutation
# below starts from this and breaks exactly ONE thing, so a red result can only
# have been caused by that one change.
write_good_tree() {
    mkdir -p "$(wf_dir)" "$(asset_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
permissions:
  contents: read
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - run: echo build
EOF
    cat > "$(asset_dir)/shipped.yml" <<'EOF'
name: fx shipped
permissions:
  contents: read
on: [push]
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - run: echo govern
EOF
}

# --- The load-bearing assertions: the real repository -----------------------

@test "this repository's own workflows and its shipped template are hardened" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow hardening gate OK"* ]]
    # The counts are printed so a CI log carries the evidence, not just a verdict.
    [[ "$output" == *"without top-level permissions : 0"* ]]
}

@test "every checkout in this repository is counted, and every one is hardened" {
    # Guards the vacuity trap: a gate that found zero checkouts would also print
    # "OK". The two numbers must be equal AND non-zero.
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    total="$(printf '%s\n' "$output" | sed -n 's/^actions\/checkout steps *: //p')"
    hardened="$(printf '%s\n' "$output" | sed -n 's/^  persist-credentials: false *: //p')"
    [ -n "$total" ]
    [ "$total" -gt 0 ]
    [ "$total" -eq "$hardened" ]
}

@test "the shipped governance template carries both properties" {
    # Asserted directly against the asset, not through the gate, so a gate that
    # stopped looking at assets/governance/ cannot hide the regression here.
    asset="$AAHP_ROOT/assets/governance/aahp-govern.yml"
    [ "$(grep -c '^permissions:' "$asset")" -eq 1 ]
    # Leading-whitespace anchor, so the header comment that EXPLAINS the setting
    # is not counted as the setting. No trailing '$': a Windows working tree has
    # CRLF here and an end anchor would match nothing while still matching on CI.
    [ "$(grep -c '^ *persist-credentials: false' "$asset")" -eq 1 ]
}

@test "what aahp init --gates writes into a consumer is the hardened template" {
    # The end of the delivery path: this is the file an adopter actually runs.
    run node "$AAHP_ROOT/bin/aahp.js" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    written="$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
    [ -f "$written" ]
    [ "$(grep -c '^permissions:' "$written")" -eq 1 ]
    [ "$(grep -c '^ *persist-credentials: false' "$written")" -eq 1 ]
}

@test "the baseline fixture passes, so every mutation below starts from green" {
    write_good_tree
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow hardening gate OK"* ]]
}

# --- Mutation: the top-level permissions block ------------------------------

@test "a workflow with no top-level permissions block exits 1" {
    write_good_tree
    # Remove the two-line block from the .github/workflows document only.
    sed -i '/^permissions:$/,+1d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no top-level 'permissions:' block"* ]]
    [[ "$output" == *"ci.yml"* ]]
}

@test "a SHIPPED workflow with no top-level permissions block exits 1" {
    # The same mutation on the other scan root. Without this the gate could be
    # narrowed to .github/workflows/ and every test above would still pass.
    write_good_tree
    sed -i '/^permissions:$/,+1d' "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"assets/governance/shipped.yml"* ]]
    [[ "$output" == *"no top-level 'permissions:' block"* ]]
}

@test "the string form 'permissions: write-all' exits 1, it is not a declaration" {
    write_good_tree
    sed -i 's/^permissions:$/permissions: write-all/; /^  contents: read$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is the string form"* ]]
}

@test "a top-level write grant exits 1: elevation belongs on the job that needs it" {
    write_good_tree
    sed -i 's/^  contents: read$/  contents: write/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"grants write to every job in the"* ]]
}

# --- Mutation: the persisted checkout credential ----------------------------

@test "a checkout that omits persist-credentials exits 1" {
    write_good_tree
    sed -i '/persist-credentials: false/d; /^        with:$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not set 'persist-credentials: false'"* ]]
}

@test "a checkout that sets persist-credentials: true exits 1" {
    write_good_tree
    sed -i 's/persist-credentials: false/persist-credentials: true/' "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"so the token is persisted"* ]]
}

@test "a forked checkout action is still a checkout" {
    # Matched on the last path segment, so renaming the publisher does not walk
    # the step out of the gate.
    write_good_tree
    sed -i 's|actions/checkout@v4|someorg/checkout@v4|; /persist-credentials: false/d; /^        with:$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"someorg/checkout@v4"* ]]
}

# --- Undecidable states exit 2, never 0 -------------------------------------

@test "a persist-credentials expression the gate cannot evaluate exits 2, not 0" {
    write_good_tree
    sed -i 's/persist-credentials: false/persist-credentials: ${{ github.event_name == '"'"'push'"'"' }}/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot evaluate"* ]]
}

@test "unparseable YAML exits 2, not 0" {
    write_good_tree
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$(wf_dir)/broken.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"is not valid YAML"* ]]
}

@test "a missing scan root exits 2: the shipped template is not silently dropped" {
    write_good_tree
    rm -rf "$TEST_TMPDIR/assets"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"assets/governance/ does not exist"* ]]
}

@test "an empty scan root exits 2: scanning nothing is not the same as finding nothing" {
    write_good_tree
    rm -f "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"holds no .yml or .yaml document"* ]]
}

@test "a job delegating to a reusable workflow exits 2, not 0" {
    write_good_tree
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
permissions:
  contents: read
on: [push]
jobs:
  build:
    uses: someorg/somerepo/.github/workflows/reusable.yml@v1
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not visible from this file"* ]]
}

# --- The elevations the top-level block must not swallow --------------------
#
# A job-level `permissions:` REPLACES the top-level one rather than merging with
# it. Now that ci.yml and codeql.yml carry a top-level `contents: read`, deleting
# a job-level block as "redundant" would silently strip an elevation, and the
# failure would only appear on a release tag. assert-repo-ci-shape.mjs holds all
# three; this is the direction test for it.

@test "the release-path elevations are still declared on this repository" {
    run node "$SHAPE_GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

@test "deleting the publish job's id-token grant is caught" {
    # Copy the repository's workflow set, break one block, and re-run the gate
    # against the copy. The real repository is never modified.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT"/.github/workflows/*.yml "$TEST_TMPDIR/.github/workflows/"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    # No '$' anchor: a Windows working tree checks these files out with CRLF, and
    # an anchored pattern would silently match nothing there while still matching
    # on Linux CI. The string occurs exactly once in the file either way.
    sed -i '/id-token: write/d' "$TEST_TMPDIR/.github/workflows/ci.yml"
    [ "$(grep -c 'id-token: write' "$TEST_TMPDIR/.github/workflows/ci.yml")" -eq 0 ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"job 'publish' no longer declares 'id-token: write'"* ]]
}

@test "deleting the codeql job's security-events grant is caught" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT"/.github/workflows/*.yml "$TEST_TMPDIR/.github/workflows/"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    # Unanchored for the CRLF reason recorded in the test above.
    sed -i '/security-events: write/d' "$TEST_TMPDIR/.github/workflows/codeql.yml"
    [ "$(grep -c 'security-events: write' "$TEST_TMPDIR/.github/workflows/codeql.yml")" -eq 0 ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"job 'analyze' no longer declares 'security-events: write'"* ]]
}

# ─── The shape gate is handed a ROOT, so it must survive a partial one ───
#
# tests/assert-repo-ci-shape.mjs takes the root to assert as argv[1]. `npm test`
# passes this repository, which holds every workflow the gate records. Other
# callers pass a copy that holds only what THEY need - the release-authorization
# fixtures in tests/runtime-support.bats copy package.json and ci.yml and nothing
# else - and an unguarded readFileSync on a workflow such a copy does not have
# throws ENOENT: node exits 1 with a stack trace and not one of the gate's own
# findings is printed. A caller asserting exit 0 sees a failure that is not
# there; a caller asserting exit 1 sees the right code for the wrong reason and
# no message at all. Both are worse than either true answer.
#
# So the reads are guarded, and the four tests below fix the behaviour in both
# directions: what the root does not contain is NAMED and not asserted, and
# everything the gate can see but cannot trust is a failure with an exact code.

@test "a root with only package.json and ci.yml is green, and says what it did not assert" {
    # This is exactly the fixture shape the release-authorization tests build.
    # Before the reads were guarded this exited 1 with an ENOENT stack trace.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
    [ ! -f "$TEST_TMPDIR/.github/workflows/codeql.yml" ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
    # Not asserted is SAID, so a root that cannot answer for an elevation never
    # passes over it in silence.
    [[ "$output" == *"not asserted here: codeql.yml"* ]]
    [[ "$output" != *"ENOENT"* ]]
}

@test "a recorded workflow that is present and unparseable is a failure, never a skip" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
    printf 'jobs:\n  analyze:\n   permissions:\n  - [unclosed\n' \
        > "$TEST_TMPDIR/.github/workflows/codeql.yml"

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"codeql.yml is not valid YAML"* ]]
    [[ "$output" == *"cannot be asserted"* ]]
}

@test "a root with no ci.yml is a stated failure, not a stack trace" {
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci.yml is not present"* ]]
    [[ "$output" != *"ENOENT"* ]]
}

@test "a root with no package.json is a stated failure, not a stack trace" {
    run node "$SHAPE_GATE" "$TEST_TMPDIR/nowhere"
    [ "$status" -eq 1 ]
    [[ "$output" == *"package.json is not present"* ]]
    [[ "$output" != *"ENOENT"* ]]
}
