#!/usr/bin/env bats
# migrate.bats -Tests for scripts/aahp-migrate-v2.sh

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

# ─── Basic migration ────────────────────────────────────────

@test "creates MANIFEST.json from v1 handoff files" {
    # Set up a v1-style handoff directory (has .md files but no MANIFEST.json)
    create_status_md
    create_next_actions_md
    create_log_md

    # Verify MANIFEST.json does not exist yet
    [ ! -f "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" ]

    # Run the migration -pipe 'y' to handle the prompt if MANIFEST already exists
    # (shouldn't be needed here but safe)
    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    # Verify MANIFEST.json was created
    [ -f "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" ]

    # Verify it contains valid JSON
    PYTHON_CMD=""
    if python3 -c "pass" &>/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif python -c "pass" &>/dev/null 2>&1; then
        PYTHON_CMD="python"
    fi

    if [ -n "$PYTHON_CMD" ]; then
        run $PYTHON_CMD -c "import json; json.load(open('$TEST_TMPDIR/.ai/handoff/MANIFEST.json'))"
        [ "$status" -eq 0 ]
    fi
}

@test "migration output mentions MANIFEST.json creation" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST.json"* ]]
}

@test "migration sets agent to migration-script" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"agent": "migration-script"'* ]]
}

@test "migration sets phase to idle" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"phase": "idle"'* ]]
}

@test "migration sets migration context message" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *"Migrated from AAHP v1"* ]]
}

# ─── Missing handoff directory ───────────────────────────────

@test "handles missing handoff directory" {
    local empty_dir
    empty_dir="$(_make_tmpdir)"
    # Initialise git so the script doesn't fail on that
    git init -q "$empty_dir"
    git -C "$empty_dir" config user.name "test"
    git -C "$empty_dir" config user.email "test@test.local"
    git -C "$empty_dir" commit --allow-empty -m "init" -q

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$empty_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]

    rm -rf "$empty_dir"
}

# ─── Re-migration prompt ────────────────────────────────────

@test "prompts before overwriting existing MANIFEST.json" {
    create_full_handoff

    # Send 'n' to decline regeneration
    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [[ "$output" == *"already exists"* ]]
}

@test "regenerates MANIFEST.json when user confirms" {
    create_full_handoff
    # Record the original content
    local original_content
    original_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")

    # Send 'y' to confirm regeneration
    run bash -c "echo y | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    # MANIFEST.json should now have migration-script as agent
    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"agent": "migration-script"'* ]]
}

# ─── LOG.md entry check ─────────────────────────────────────

@test "reports LOG.md entry count" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG.md has"* ]]
}

# ─── .aiignore handling ─────────────────────────────────────

@test "copies .aiignore template if missing" {
    create_status_md
    create_next_actions_md
    create_log_md

    # Ensure .aiignore does not exist
    rm -f "$TEST_TMPDIR/.ai/handoff/.aiignore"

    # The script looks for templates/.aiignore relative to REPO_ROOT (parent of scripts/)
    # Our temp dir won't have it, so it should report template not found
    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    # Since AAHP has templates/.aiignore, the script's REPO_ROOT points to real AAHP
    # so it should actually copy it
    if [ -f "$AAHP_ROOT/templates/.aiignore" ]; then
        [ -f "$TEST_TMPDIR/.ai/handoff/.aiignore" ]
    fi
}

@test "skips .aiignore copy when already present" {
    create_status_md
    create_next_actions_md
    create_log_md
    echo "# existing aiignore" > "$TEST_TMPDIR/.ai/handoff/.aiignore"

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *".aiignore already present"* ]]
}

# ─── Migration summary ──────────────────────────────────────

@test "prints migration summary" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration Summary"* ]]
}
