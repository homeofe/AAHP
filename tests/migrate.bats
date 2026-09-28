#!/usr/bin/env bats
# migrate.bats -Tests for scripts/aahp-migrate-v2.sh

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

# --- Basic migration ----------------------------------------

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

# --- Missing handoff directory -------------------------------

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

# --- Re-migration prompt ------------------------------------

@test "prompts before overwriting existing MANIFEST.json" {
    create_full_handoff
    cp "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/manifest.before"

    # Send 'n' to decline regeneration
    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"Aborted."* ]]
    cmp -s "$TEST_TMPDIR/manifest.before" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

# --- Non-interactive use (R11) -----------------------------------------------
#
# The prompt was a bare `read` under `set -e`. With no terminal and nothing
# piped in, `read` hit end of input and the script exited 1 WITHOUT a word:
# measured at 1917ca8, `aahp-migrate-v2.sh <dir> </dev/null` printed the
# "already exists" line, then exit 1, and "Aborted." appeared 0 times.

@test "no answer on stdin is an explicit error that names --yes, and changes nothing" {
    create_full_handoff
    cp "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/manifest.before"

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"no answer could be read from stdin"* ]]
    [[ "$output" == *"--yes"* ]]
    cmp -s "$TEST_TMPDIR/manifest.before" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

@test "--yes regenerates an existing MANIFEST.json without reading stdin" {
    create_full_handoff

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" --yes </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration Summary"* ]]
    grep -q '"agent": "migration-script"' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

@test "-y is accepted before the path, too" {
    create_full_handoff

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" -y "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 0 ]
    grep -q '"agent": "migration-script"' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

@test "an unknown option is refused before anything is written" {
    create_status_md
    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" --bogus </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
    [ ! -f "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" ]
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

# --- LOG.md entry check -------------------------------------

@test "reports LOG.md entry count" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG.md has 1 entries"* ]]
}

@test "a LOG.md with zero entries is counted as 0, not as a broken integer" {
    # grep -c prints 0 AND exits 1 on no match, so `$(grep -c ... || echo 0)`
    # captured "0\n0". Measured at 1917ca8: "[: 0\n0: integer expression
    # expected", then "LOG.md has 0" with a stray second 0 on the next line.
    create_status_md
    create_next_actions_md
    printf '# TestProject: Agent Journal\n\nNo entries yet.\n' > "$TEST_TMPDIR/.ai/handoff/LOG.md"

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"integer expression expected"* ]]
    [[ "$output" == *"LOG.md has 0 entries. No rotation needed."* ]]
}

# --- It reports the manual steps; it does not perform them -------------------
#
# The header and README section 5 used to say this script "Splits LOG.md",
# "Adds section markers" and adds a TTL column. It does none of the three: it
# prints advice. These tests pin what it really does, so a future claim in
# either place has an artifact to be checked against.

@test "the manual steps are reported as TODO, and their files are left byte-identical" {
    create_status_md          # no <!-- SECTION: --> markers
    create_next_actions_md
    {
        printf '# TestProject: Agent Journal\n'
        local i
        for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
            printf '\n## [2025-06-%s] agent: entry %s\n\nbody\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/.ai/handoff/LOG.md"
    printf '# Trust\n\n| Property | Status |\n|---|---|\n| build | verified |\n' > "$TEST_TMPDIR/.ai/handoff/TRUST.md"
    local f
    for f in STATUS.md LOG.md TRUST.md; do
        cp "$TEST_TMPDIR/.ai/handoff/$f" "$TEST_TMPDIR/$f.before"
    done

    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 0 ]
    for f in STATUS.md LOG.md TRUST.md; do
        cmp -s "$TEST_TMPDIR/$f.before" "$TEST_TMPDIR/.ai/handoff/$f" || { echo "$f was modified"; false; }
    done
    [ ! -f "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md" ]
    [[ "$output" == *"LOG.md has 12 entries"* ]]
    [[ "$output" == *"aahp archive"* ]]
    # The summary keeps what was done apart from what was only recommended.
    local changed todo
    changed="$(printf '%s\n' "$output" | sed -n '/^Changed:/,/^Left for you/p')"
    todo="$(printf '%s\n' "$output" | sed -n '/^Left for you/,/^Next steps:/p')"
    [[ "$changed" == *"Generated MANIFEST.json"* ]]
    [[ "$changed" != *"LOG.md"* ]]
    [[ "$changed" != *"TTL"* ]]
    [[ "$todo" == *"NOT changed"* ]]
    [[ "$todo" == *"LOG.md has 12 entries"* ]]
    [[ "$todo" == *"Optional: add a <!-- SECTION: summary --> block to STATUS.md"* ]]
    [[ "$todo" == *"TTL"* ]]
}

# README section 1.2: the only marker AAHP reads is `summary`. Any other name is
# a convention, so it must not satisfy the check, and a summary marker must.
# Anchor: the summary-only grep in step 2 of scripts/aahp-migrate-v2.sh.

@test "migrate: a STATUS.md with only other section markers still gets the optional summary note" {
    printf '# Status\n\n<!-- SECTION: build -->\nBuild green.\n<!-- /SECTION: build -->\n' \
        > "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_next_actions_md
    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"No <!-- SECTION: summary --> marker"* ]]
    [[ "$output" == *"Optional: add a <!-- SECTION: summary --> block to STATUS.md"* ]]
}

@test "migrate: a STATUS.md with a summary marker gets no marker note" {
    printf '# Status\n\n<!-- SECTION: summary -->\nBuild green.\n<!-- /SECTION: summary -->\n' \
        > "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_next_actions_md
    run bash "$SCRIPTS_DIR/aahp-migrate-v2.sh" "$TEST_TMPDIR" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary marker present"* ]]
    run grep -c "SECTION: summary --> block" <<<"$output"
    [ "$output" = "0" ]
}

# --- .aiignore handling -------------------------------------

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

# --- Migration summary --------------------------------------

@test "prints migration summary" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash -c "echo n | bash '$SCRIPTS_DIR/aahp-migrate-v2.sh' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration Summary"* ]]
}
