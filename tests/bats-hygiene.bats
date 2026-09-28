#!/usr/bin/env bats
# bats-hygiene.bats - the suite's own guards against tests that cannot fail.
#
# Every guard here is proven in BOTH directions: green on the real tree, red on
# a synthetic offender. A guard that is only ever seen green looks exactly like
# one that cannot go red. See tests/README.md for the rules they enforce.

load test_helper

NEG="$AAHP_ROOT/tests/assert-bats-negations.mjs"
RUNBATS="$AAHP_ROOT/scripts/run-bats.mjs"

# Write stdin to $1, turning a leading %TEST% into @test. Bats' preprocessor
# rewrites every line that starts with @test, heredoc bodies included, so a
# synthetic test file written literally would not contain what it shows.
synth() {
    sed 's/^%TEST%/@test/' > "$1"
}

# A scratch root with a tests/ directory, for the negation checker.
negroot() {
    mkdir -p "$TEST_TMPDIR/negroot/tests"
    synth "$TEST_TMPDIR/negroot/tests/sample.bats"
}

# --- dead `!` negations ------------------------------------------------------

@test "negations: the real suite has no dead negation" {
    run node "$NEG" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bats negations OK"* ]]
}

@test "negations: a bare ! that is not the last command is red" {
    negroot <<'EOF'
%TEST% "t" {
    run true
    ! grep -q gone out.txt
    [ "$status" -eq 0 ]
}
EOF
    run node "$NEG" "$TEST_TMPDIR/negroot"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tests/sample.bats:3:"*"! grep -q gone out.txt"* ]]
}

@test "negations: && ! and a negation inside a helper function are red too" {
    negroot <<'EOF'
helper() {
    ! test -e x
    echo after
}
%TEST% "t" {
    cd . && ! test -e y
    true
}
EOF
    run node "$NEG" "$TEST_TMPDIR/negroot"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sample.bats:2:"* ]]
    [[ "$output" == *"sample.bats:6:"* ]]
}

@test "negations: the forms that CAN fail are accepted" {
    # Last command (its status is the test's), `|| false`, `run !`, a `[ ! ]`
    # test expression, and heredoc text that merely starts with `!`.
    negroot <<'EOF'
%TEST% "last" {
    run true
    ! grep -q gone out.txt
}
%TEST% "restored" {
    ! grep -q gone out.txt || false
    true
}
%TEST% "run-bang" {
    run ! grep -q gone out.txt
    [ ! -e out.txt ]
    cat > f <<'DOC'
! not a command
DOC
    true
}
EOF
    run node "$NEG" "$TEST_TMPDIR/negroot"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bats negations OK (1 file(s) scanned)"* ]]
}

@test "negations: an empty tree is exit 2, never a pass" {
    mkdir -p "$TEST_TMPDIR/negroot/tests"
    run node "$NEG" "$TEST_TMPDIR/negroot"
    [ "$status" -eq 2 ]
    [[ "$output" == *"nothing was scanned"* ]]
}

# --- skips on CI (scripts/run-bats.mjs) and require_tool (test_helper) --------

@test "run-bats: with CI set, an unlisted skip fails the run" {
    printf '@test "a skipper" {\n    skip "no reason worth having"\n}\n' > "$TEST_TMPDIR/skip.bats"
    CI=true run node "$RUNBATS" "$TEST_TMPDIR/skip.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 unexpected skip(s) with CI set"* ]]
    [[ "$output" == *"a skipper # skip no reason worth having"* ]]
}

@test "run-bats: without CI the same skip is a skip, not a failure" {
    printf '@test "a skipper" {\n    skip "no reason worth having"\n}\n' > "$TEST_TMPDIR/skip.bats"
    CI= run node "$RUNBATS" "$TEST_TMPDIR/skip.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# skip"* ]]
    [[ "$output" != *"unexpected skip"* ]]
}

@test "run-bats: with CI set, an ALLOWED_SKIPS entry passes" {
    synth "$TEST_TMPDIR/allowed.bats" <<'EOF'
%TEST% "aahp init fails with permission error on read-only directory" {
    skip "chmod does not model Windows directory ACLs"
}
EOF
    CI=true run node "$RUNBATS" "$TEST_TMPDIR/allowed.bats"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unexpected skip"* ]]
}

@test "require_tool: skips locally and FAILS with CI set" {
    synth "$TEST_TMPDIR/req.bats" <<'EOF'
load "$AAHP_ROOT/tests/test_helper"
%TEST% "needs a missing tool" {
    require_tool "probe tool missing" false
    echo "unreachable"
}
EOF
    CI= run node "$RUNBATS" "$TEST_TMPDIR/req.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# skip"*"probe tool missing"* ]]

    CI=true run node "$RUNBATS" "$TEST_TMPDIR/req.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok 1 needs a missing tool"* ]]
    [[ "$output" == *"require_tool: probe tool missing"* ]]
}

# --- bash older than 4.1 -----------------------------------------------------

@test "run-bats: refuses a pre-4.1 bash, whose [[ ]] cannot fail a test" {
    # Stand-in: the first `bash` on PATH reports 3.2, like macOS /bin/bash.
    mkdir -p "$TEST_TMPDIR/oldbash"
    printf '#!/bin/sh\necho "3 2"\n' > "$TEST_TMPDIR/oldbash/bash"
    chmod +x "$TEST_TMPDIR/oldbash/bash"
    printf '@test "never runs" { true; }\n' > "$TEST_TMPDIR/ok.bats"
    PATH="$TEST_TMPDIR/oldbash:$PATH" run node "$RUNBATS" "$TEST_TMPDIR/ok.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"the first bash on PATH is 3.2"* ]]
    [[ "$output" == *"refusing to run"* ]]
    # The refusal names the fix, not only the fault: the macOS install, the PATH
    # step that makes it the bash bats runs, and how to check it.
    [[ "$output" == *"to fix it on macOS"* ]]
    [[ "$output" == *"brew install bash"* ]]
    [[ "$output" == *"make sure that bash is first on PATH"* ]]
    [[ "$output" == *"env bash --version"* ]]
    # And the override, with what it costs.
    [[ "$output" == *"AAHP_ALLOW_OLD_BASH=1 overrides"* ]]
    [[ "$output" == *"partial"* ]]
}

# --- git isolation (test_helper) ---------------------------------------------

@test "git isolation: the machine's global config does not reach the fixture repo" {
    local home="$TEST_TMPDIR/fakehome"
    mkdir -p "$home/elsewhere"
    # What a developer machine may carry: a shared hooks dir, mandatory signing
    # (with a signer that always fails, so an unisolated commit would break).
    printf '[core]\n\thooksPath = %s\n[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = false\n' \
        "$home/elsewhere" > "$home/.gitconfig"

    # Control: without the helper's isolation, git DOES read this file.
    run env -u GIT_CONFIG_GLOBAL HOME="$home" XDG_CONFIG_HOME="$home" \
        git -C "$TEST_TMPDIR" config --get core.hooksPath
    [ "$status" -eq 0 ]
    [ "$output" = "$home/elsewhere" ]

    # Under the helper's environment it does not.
    HOME="$home" XDG_CONFIG_HOME="$home" run git -C "$TEST_TMPDIR" config --get core.hooksPath
    [ "$status" -eq 1 ]
    HOME="$home" XDG_CONFIG_HOME="$home" run git -C "$TEST_TMPDIR" commit --allow-empty -q -m probe
    [ "$status" -eq 0 ]

    # And the hooks install-hooks.sh writes land in the fixture, not in $home.
    HOME="$home" XDG_CONFIG_HOME="$home" run bash "$SCRIPTS_DIR/install-hooks.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/.git/hooks/pre-commit" ]
    [ -z "$(ls -A "$home/elsewhere")" ]
}

@test "git isolation: no repository above the temp base is discovered" {
    # Read back through a child process: the value only protects anything if it
    # is EXPORTED to the git and node processes the tests start.
    run bash -c 'printf "%s" "$GIT_CEILING_DIRECTORIES"'
    [ "$output" = "${TEST_TMPDIR%/*}" ]

    # The hazard, modelled one level down: an outer repository that holds the
    # base, and a case directory under the base with no .git of its own.
    git init -q "$TEST_TMPDIR/outer"
    mkdir -p "$TEST_TMPDIR/outer/base/case"
    GIT_CEILING_DIRECTORIES= run git -C "$TEST_TMPDIR/outer/base/case" rev-parse --show-toplevel
    [ "$status" -eq 0 ]
    GIT_CEILING_DIRECTORIES="$TEST_TMPDIR/outer/base" \
        run git -C "$TEST_TMPDIR/outer/base/case" rev-parse --show-toplevel
    [ "$status" -ne 0 ]
}

@test "fixture: every test starts from a repo with one commit and an empty handoff dir" {
    [ -d "$TEST_TMPDIR/.ai/handoff" ]
    [ -z "$(ls -A "$TEST_TMPDIR/.ai/handoff")" ]
    run git -C "$TEST_TMPDIR" rev-list --count HEAD
    [ "$output" = "1" ]
    run git -C "$TEST_TMPDIR" log -1 --format='%an <%ae> %s'
    [ "$output" = "test <test@test.local> init" ]
    run git -C "$TEST_TMPDIR" status --porcelain
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # The per-run template is what built it (the fast path is live), and each
    # test owns a COPY: a commit here does not reach the template.
    [ -n "$AAHP_FIXTURE_TEMPLATE" ]
    git -C "$TEST_TMPDIR" commit --allow-empty -q -m "second"
    run git -C "$TEST_TMPDIR" rev-list --count HEAD
    [ "$output" = "2" ]
    run git -C "$AAHP_FIXTURE_TEMPLATE" rev-list --count HEAD
    [ "$output" = "1" ]
}
