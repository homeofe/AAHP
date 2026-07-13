#!/usr/bin/env bats
# migrate-grounding.bats - Tests for scripts/aahp-migrate-grounding.sh

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

# Minimal TRUST.md fixture (test_helper does not provide one).
_create_trust_md() {
    cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md" <<'EOF'
# TestProject: Trust Register

## Confidence Levels

| Level | Meaning |
|-------|---------|
| verified | An agent ran code or observed output |
| assumed | Derived from docs, not tested |
| untested | Status unknown |

## Build System

| Property | Status | Last Verified | Agent | Notes |
|----------|--------|---------------|-------|-------|
| build passes | untested | - | - | |
EOF
}

# --- Happy path -------------------------------------------------------------

@test "runs and prints a migration summary" {
    create_full_handoff
    _create_trust_md

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration Summary"* ]]
}

# --- GROUNDING.md ------------------------------------------------------------

@test "copies GROUNDING.md when absent" {
    create_full_handoff
    _create_trust_md
    [ ! -f "$TEST_TMPDIR/.ai/handoff/GROUNDING.md" ]

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/.ai/handoff/GROUNDING.md" ]
}

@test "preserves an existing edited GROUNDING.md" {
    create_full_handoff
    _create_trust_md
    echo "SENTINEL-consumer-edit" > "$TEST_TMPDIR/.ai/handoff/GROUNDING.md"

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    grep -q "SENTINEL-consumer-edit" "$TEST_TMPDIR/.ai/handoff/GROUNDING.md"
}

# --- TRUST.md provenance -----------------------------------------------------

@test "adds a Provenance section to TRUST.md" {
    create_full_handoff
    _create_trust_md
    ! grep -q "Provenance" "$TEST_TMPDIR/.ai/handoff/TRUST.md"

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    grep -q "Provenance" "$TEST_TMPDIR/.ai/handoff/TRUST.md"
}

@test "is idempotent: re-run does not duplicate the Provenance section" {
    create_full_handoff
    _create_trust_md

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    count=$(grep -c "## Provenance" "$TEST_TMPDIR/.ai/handoff/TRUST.md")
    [ "$count" -eq 1 ]
    [[ "$output" == *"already present"* ]]
}

# --- Missing handoff directory ----------------------------------------------

@test "handles a missing handoff directory" {
    local empty_dir
    empty_dir="$(_make_tmpdir)"

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$empty_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]

    rm -rf "$empty_dir"
}

# --- Non-interactive --------------------------------------------------------

@test "is non-interactive: does not hang with no stdin and accepts --force" {
    create_full_handoff
    _create_trust_md

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR" --force </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration Summary"* ]]
}

# --- MANIFEST regeneration --------------------------------------------------

@test "regenerated MANIFEST.json indexes GROUNDING.md" {
    create_full_handoff
    _create_trust_md

    run bash "$SCRIPTS_DIR/aahp-migrate-grounding.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    # aahp-manifest.sh builds the files map without python/node, so this holds
    # on every platform (mirrors manifest.bats' optional-file assertion).
    grep -q "GROUNDING.md" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}
