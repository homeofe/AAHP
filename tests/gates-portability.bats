#!/usr/bin/env bats
# gates-portability.bats - C-6 fail-loud behavior of the enumerating gates.
#
# check-forbidden-patterns and check-doc-links enumerate TRACKED files via
# `git ls-files`. Outside a git work tree that command yields zero files, so a
# gate would vacuously pass (exit 0) and a real violation could ship undetected.
# The C-6 contract makes both gates FAIL LOUD (exit 1 with an actionable "work
# tree" message) when their config section is present but the target is not
# inside a git checkout. These tests pin that behavior and prove the guard did
# not change in-tree behavior, nor the section-absent no-op.
#
# setup() (in test_helper) git-inits TEST_TMPDIR. To exercise the non-git path
# we `ungit` (rm the .git dir); the mktemp base has no git-repo ancestor, so the
# target is then genuinely outside any work tree. In-tree fixtures are staged
# with `git add` before the gate runs, matching anti-entropy.bats.

load test_helper

FP="$SCRIPTS_DIR/check-forbidden-patterns.mjs"
DL="$SCRIPTS_DIR/check-doc-links.mjs"

mkpkg() { echo "{ \"name\": \"fx\", \"version\": \"1.0.0\" }" > "$TEST_TMPDIR/package.json"; }
mkconfig() { cat > "$TEST_TMPDIR/aahp.config.json"; }
gadd() { git -C "$TEST_TMPDIR" add -A; }
ungit() { rm -rf "$TEST_TMPDIR/.git"; }

# --- non-git: fail loud ------------------------------------------------------

@test "forbidden-patterns: fails loud outside a git work tree when configured" {
    ungit
    mkpkg
    printf 'bad \342\200\224 dash\n' > "$TEST_TMPDIR/doc.md"  # octal U+2014, so this .bats file stays em-dash-free
    mkconfig <<'EOF'
{ "forbiddenPatterns": [ { "id": "em-dash", "pattern": "\\u2014", "message": "no em dash" } ] }
EOF
    run node "$FP" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"work tree"* ]]
    [[ "$output" == *"git checkout"* ]]
}

@test "doc-links: fails loud outside a git work tree when configured" {
    ungit
    mkpkg
    echo "target" > "$TEST_TMPDIR/TARGET.md"
    printf 'see [t](TARGET.md)\n' > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "docLinks": { "include": ["README.md"] } }
EOF
    run node "$DL" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"work tree"* ]]
    [[ "$output" == *"git checkout"* ]]
}

# --- in-tree: guard did not change normal behavior ---------------------------

@test "forbidden-patterns: still passes in-tree on a clean fixture" {
    mkpkg
    printf 'clean hyphen - only\n' > "$TEST_TMPDIR/doc.md"
    mkconfig <<'EOF'
{ "forbiddenPatterns": [ { "id": "em-dash", "pattern": "\\u2014" } ] }
EOF
    gadd
    run node "$FP" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no matches"* ]]
}

@test "doc-links: still passes in-tree when internal links resolve" {
    mkpkg
    echo "target" > "$TEST_TMPDIR/TARGET.md"
    printf 'see [t](TARGET.md) and [ext](https://x.com) and [a](#anchor)\n' > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "docLinks": { "include": ["README.md"] } }
EOF
    gadd
    run node "$DL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolve"* ]]
}

# --- section-absent no-op happens before the work-tree guard -----------------

@test "forbidden-patterns: no config section is a clean no-op even outside a git work tree" {
    ungit
    mkpkg
    mkconfig <<'EOF'
{ "docLinks": { "include": ["README.md"] } }
EOF
    run node "$FP" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"none configured"* ]]
}

@test "doc-links: no config section is a clean no-op even outside a git work tree" {
    ungit
    mkpkg
    mkconfig <<'EOF'
{ "forbiddenPatterns": [] }
EOF
    run node "$DL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not configured"* ]]
}
