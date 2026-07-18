#!/usr/bin/env bats
# anti-entropy.bats - the governance gates: forbidden-patterns, schema-doc-sync,
# doc-links. These enumerate tracked files via `git ls-files`, so fixtures are
# staged with `git add` before each gate runs.

load test_helper

FP="$SCRIPTS_DIR/check-forbidden-patterns.mjs"
SDS="$SCRIPTS_DIR/check-schema-doc-sync.mjs"
DL="$SCRIPTS_DIR/check-doc-links.mjs"

mkpkg() { echo "{ \"name\": \"fx\", \"version\": \"1.0.0\" }" > "$TEST_TMPDIR/package.json"; }
mkconfig() { cat > "$TEST_TMPDIR/aahp.config.json"; }
gadd() { git -C "$TEST_TMPDIR" add -A; }

# --- forbidden-patterns ------------------------------------------------------

@test "forbidden-patterns: no config is a clean no-op" {
    mkpkg
    run node "$FP" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"none configured"* ]]
}

@test "forbidden-patterns: fails on a match, reporting file and message" {
    mkpkg
    printf 'has an em dash — here\n' > "$TEST_TMPDIR/doc.md"
    mkconfig <<'EOF'
{ "forbiddenPatterns": [ { "id": "em-dash", "pattern": "\\u2014", "message": "no em dash" } ] }
EOF
    gadd
    run node "$FP" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"doc.md"* ]]
    [[ "$output" == *"no em dash"* ]]
}

@test "forbidden-patterns: passes when clean (config file does not self-match)" {
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

# --- schema-doc-sync ---------------------------------------------------------

@test "schema-doc-sync: no config is a clean no-op" {
    mkpkg
    run node "$SDS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"none configured"* ]]
}

@test "schema-doc-sync: passes when the sources agree" {
    mkpkg
    printf 'enum: "a" "b" "c"\n' > "$TEST_TMPDIR/schema.txt"
    printf 'doc: `a` `b` `c`\n' > "$TEST_TMPDIR/doc.md"
    mkconfig <<'EOF'
{ "docSync": [ { "id": "e", "sources": [
  { "file": "schema.txt", "pattern": "\"(a|b|c)\"" },
  { "file": "doc.md", "pattern": "`(a|b|c)`" } ] } ] }
EOF
    gadd
    run node "$SDS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"consistent"* ]]
}

@test "schema-doc-sync: fails when a source drops a value" {
    mkpkg
    printf 'enum: "a" "b" "c"\n' > "$TEST_TMPDIR/schema.txt"
    printf 'doc: `a` `b`\n' > "$TEST_TMPDIR/doc.md"
    mkconfig <<'EOF'
{ "docSync": [ { "id": "e", "sources": [
  { "file": "schema.txt", "pattern": "\"(a|b|c)\"" },
  { "file": "doc.md", "pattern": "`(a|b|c)`" } ] } ] }
EOF
    gadd
    run node "$SDS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"disagrees"* ]]
    [[ "$output" == *"missing [c]"* ]]
}

# --- doc-links ---------------------------------------------------------------

@test "doc-links: no config is a clean no-op" {
    mkpkg
    run node "$DL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not configured"* ]]
}

@test "doc-links: passes when internal links resolve (external skipped)" {
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

@test "doc-links: fails on a broken internal link" {
    mkpkg
    printf 'see [gone](MISSING.md)\n' > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "docLinks": { "include": ["README.md"] } }
EOF
    gadd
    run node "$DL" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING.md"* ]]
}
