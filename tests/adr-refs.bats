#!/usr/bin/env bats
# adr-refs.bats - scripts/check-adr-refs.mjs: the decision log in docs/adr/ agrees
# with itself, and every ADR number cited in a tracked file has a file.
#
# The exit codes are asserted by number: 1 is "assessed and found a problem", 2 is
# "could not assess", and a test that accepted either would not notice them swapping.
# Every red test first proves its mutation landed, then expects the finding by text.

load test_helper

GATE="$SCRIPTS_DIR/check-adr-refs.mjs"

# A tracked fixture log: two ADRs, an index, and one document citing both.
# TEST_TMPDIR is already a git repo with one empty commit (test_helper.bash).
seed_log() {
    mkdir -p "$TEST_TMPDIR/docs/adr"
    printf '# ADR-001: first decision\n\nBody.\n' > "$TEST_TMPDIR/docs/adr/ADR-001.md"
    printf '# ADR-002: second decision\n\nBody.\n' > "$TEST_TMPDIR/docs/adr/ADR-002.md"
    cat > "$TEST_TMPDIR/docs/adr/README.md" <<'EOF'
# Architectural Decision Log

| ADR | Decision |
|-----|----------|
| [ADR-001](ADR-001.md) | first decision |
| [ADR-002](ADR-002.md) | second decision |
EOF
    printf 'See ADR-001 and ADR-002.\n' > "$TEST_TMPDIR/NOTES.md"
    git -C "$TEST_TMPDIR" add -A
}

@test "adr-refs: this repository's own log and citations are consistent" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADR references OK"* ]]
}

@test "adr-refs CONTROL: the fixture log is green, so every mutation starts there" {
    seed_log
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 ADR file(s)"* ]]
    [[ "$output" == *"citation(s) resolve"* ]]
}

@test "adr-refs: citing an ADR number that has no file is red" {
    seed_log
    printf 'Renumbered away: ADR-003.\n' >> "$TEST_TMPDIR/NOTES.md"
    git -C "$TEST_TMPDIR" add NOTES.md
    run grep -c "ADR-003" "$TEST_TMPDIR/NOTES.md"
    [ "$output" = "1" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOTES.md:2: cites ADR-003"* ]]
}

@test "adr-refs: a heading that disagrees with its file name is red" {
    seed_log
    printf '# ADR-003: second decision\n\nBody.\n' > "$TEST_TMPDIR/docs/adr/ADR-002.md"
    git -C "$TEST_TMPDIR" add -A
    run grep -c "^# ADR-003:" "$TEST_TMPDIR/docs/adr/ADR-002.md"
    [ "$output" = "1" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the heading says ADR-003 but the file is ADR-002"* ]]
}

@test "adr-refs: an ADR file missing from the index is red" {
    seed_log
    grep -v "ADR-002" "$TEST_TMPDIR/docs/adr/README.md" > "$TEST_TMPDIR/idx.tmp"
    mv "$TEST_TMPDIR/idx.tmp" "$TEST_TMPDIR/docs/adr/README.md"
    git -C "$TEST_TMPDIR" add -A
    run grep -c "ADR-002" "$TEST_TMPDIR/docs/adr/README.md"
    [ "$output" = "0" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADR-002 has a file"*"but no row in the index"* ]]
}

@test "adr-refs: an index title that drifted from the file's heading is red" {
    seed_log
    sed 's/| second decision |/| a retitled decision |/' "$TEST_TMPDIR/docs/adr/README.md" > "$TEST_TMPDIR/idx.tmp"
    mv "$TEST_TMPDIR/idx.tmp" "$TEST_TMPDIR/docs/adr/README.md"
    git -C "$TEST_TMPDIR" add -A
    run grep -c "a retitled decision" "$TEST_TMPDIR/docs/adr/README.md"
    [ "$output" = "1" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADR-002 is titled \"a retitled decision\" here"* ]]
}

@test "adr-refs: an index row whose file is not tracked is red" {
    seed_log
    git -C "$TEST_TMPDIR" rm -q --cached docs/adr/ADR-002.md
    rm "$TEST_TMPDIR/docs/adr/ADR-002.md"
    printf 'See ADR-001.\n' > "$TEST_TMPDIR/NOTES.md"
    git -C "$TEST_TMPDIR" add -A
    run git -C "$TEST_TMPDIR" ls-files docs/adr/ADR-002.md
    [ -z "$output" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADR-002 is listed but docs/adr/ADR-002.md is not tracked"* ]]
}

@test "adr-refs: no tracked log is 'could not assess' (2), never a pass" {
    printf 'See ADR-001.\n' > "$TEST_TMPDIR/NOTES.md"
    git -C "$TEST_TMPDIR" add -A
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no docs/adr/ADR-NNN.md file is tracked"* ]]
}

@test "adr-refs: outside a git work tree is 'could not assess' (2)" {
    seed_log
    rm -rf "$TEST_TMPDIR/.git"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not inside a git work tree"* ]]
}

@test "adr-refs: the gate is wired into the aggregate check chain" {
    run node -e '
      const p = require(process.argv[1]);
      const ok = p.scripts["check:adr-refs"] === "node scripts/check-adr-refs.mjs"
        && p.scripts.check.includes("npm run check:adr-refs");
      process.exit(ok ? 0 : 1);
    ' "$AAHP_ROOT/package.json"
    [ "$status" -eq 0 ]
}
