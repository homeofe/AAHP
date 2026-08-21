#!/usr/bin/env bats
# runtime-support.bats - the runtimes CI exercises and the runtimes package.json
# publishes must be the same set, and the floor of that set must still receive
# security patches.
#
# Every test here asserts in BOTH directions: the relation holds on the real
# repository, and each way of breaking it turns the gate red. A gate proved only
# in the passing direction is indistinguishable from a gate that cannot fail.

load test_helper

GATE="$SCRIPTS_DIR/check-runtime-support.mjs"

# NOTE: TEST_TMPDIR is created by setup(), which runs AFTER this file is sourced,
# so the workflow directory cannot be a top-level variable - it would expand to
# "/.github/workflows" here. Every test calls this instead.
wf_dir() {
    printf '%s/.github/workflows' "$TEST_TMPDIR"
}

# package.json for a fixture project. $1 is the engines.node range; omitting it
# writes no engines block at all.
write_pkg() {
    if [ $# -eq 0 ]; then
        printf '{ "name": "fx", "version": "1.0.0" }\n' > "$TEST_TMPDIR/package.json"
    else
        printf '{ "name": "fx", "version": "1.0.0", "engines": { "node": "%s" } }\n' "$1" \
            > "$TEST_TMPDIR/package.json"
    fi
}

# The baseline fixture: a two-runtime matrix and a release job on the newer
# runtime. Every mutation test below starts from this and breaks ONE thing, so a
# red result can only be caused by that one change.
write_good_workflow() {
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [22, 24]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
EOF
}

# ─── The load-bearing assertion: the real repository ────────────────────────

@test "this repository's own workflows satisfy the runtime relation" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Runtime support OK"* ]]
}

@test "the baseline fixture passes, so every mutation below starts from green" {
    write_pkg ">=22"
    write_good_workflow
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── Mutation: a runtime CI exercises that the package does not claim ───────

@test "a CI pin below the published floor is a failure" {
    write_pkg ">=22"
    write_good_workflow
    # Drop the release job back to a runtime the package no longer claims.
    sed -i "s/node-version: '24'/node-version: '20'/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"below the engines.node floor of 22"* ]]
}

@test "widening the published range below what CI proves is a failure" {
    # The mirror image: CI stays on 22/24 but the package claims >=18, so it
    # advertises support for runtimes nothing ever exercised.
    write_pkg ">=18"
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"oldest runtime still receiving"* ]]
}

# ─── Mutation: the published floor goes end-of-life ─────────────────────────

@test "an end-of-life published floor is a failure even when CI agrees with it" {
    # CI and engines are perfectly consistent here - consistently dead. This is
    # the exact state this repository shipped in: engines '>=18', CI on Node 20,
    # nothing red. Only the dated SUPPORTED_FLOOR constant can catch it.
    write_pkg ">=20"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [20, 21]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"still receiving"* ]]
}

# ─── Mutation: the vacuity trap this gate was shaped to avoid ───────────────

@test "emptying the matrix is a failure even while standalone pins remain" {
    # THE RECORDED TRAP. A sibling gate in this estate asserted only that the
    # GLOBAL pin list was non-empty. Removing the matrix left it green, because
    # the standalone `node-version:` pins in the other jobs kept that list
    # populated on their own - the multi-runtime coverage vanished silently.
    #
    # So this fixture deliberately KEEPS two standalone pins. The generic "no
    # pins at all" guard therefore cannot fire, and only the assertion bound to
    # the matrix itself can turn this red.
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"matrix exercises 0 runtime(s)"* ]]
}

@test "cutting the matrix to a single runtime is a failure" {
    write_pkg ">=22"
    write_good_workflow
    sed -i 's/node-version: \[22, 24\]/node-version: [22]/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"matrix exercises 1 runtime(s)"* ]]
}

@test "no node-version pin anywhere is a failure, not a clean skip" {
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"vacuously true"* ]]
}

# ─── Mutation: releasing on a runtime nothing tested ───────────────────────

@test "a release runtime that no build job exercises is a failure" {
    # Every pin here satisfies engines and the matrix is intact, so this can only
    # be caught by the build-vs-release MEMBERSHIP test. Node 22 clears the floor,
    # so the floor check provably is not what turns this red.
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [24, 26]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release path runs on Node 22, which no build or test job exercises"* ]]
}

@test "a release runtime NEWER than anything tested is also a failure" {
    # The mirror image, and the case an ordering comparison ("release major >=
    # lowest build major") cannot see at all: publishing on 26 while CI only ever
    # ran 22 and 24 makes the publish step the first thing to touch that runtime.
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version: '26'/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release path runs on Node 26, which no build or test job exercises"* ]]
}

# ─── Mutation: pins the gate cannot read must FAIL, never be skipped ────────

@test "a non-matrix expression pin fails rather than being silently dropped" {
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version: \${{ env.NODE_MAJOR }}/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot evaluate"* ]]
}

@test "node-version-file fails rather than being silently dropped" {
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version-file: .nvmrc/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"node-version-file"* ]]
}

# ─── "I could not look" must never read as "I looked and it was fine" ──────

@test "a missing engines.node exits 2, not 0" {
    write_pkg
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no engines.node"* ]]
}

@test "an engines range the gate cannot read exits 2, not 0" {
    write_pkg "^22 || ^24"
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read as a floor"* ]]
}

@test "a project with no workflows exits 2, not 0" {
    write_pkg ">=22"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no workflow directory"* ]]
}

@test "unparseable YAML exits 2, not 0" {
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not valid YAML"* ]]
}

# ─── The gate has to actually RUN, and the required check has to keep its name ─

@test "the gate is wired into the check chain, and the required check keeps its name" {
    # Both assertions live in tests/assert-repo-ci-shape.mjs - see the header
    # there for why this is a file and not an inline `node -e`.
    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}
