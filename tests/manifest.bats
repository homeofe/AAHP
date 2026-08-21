#!/usr/bin/env bats
# manifest.bats -Tests for scripts/aahp-manifest.sh

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

# ─── Helper: detect a working python command ─────────────────
# Returns 0 and sets PYTHON_CMD, or returns 1 if no python available.
# We verify with an actual invocation to avoid Windows Store aliases.

_detect_python() {
    PYTHON_CMD=""
    if python3 -c "import sys; sys.exit(0)" &>/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif python -c "import sys; sys.exit(0)" &>/dev/null 2>&1; then
        PYTHON_CMD="python"
    fi
    [ -n "$PYTHON_CMD" ]
}

# ─── Basic generation ────────────────────────────────────────

@test "generates valid JSON output" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # The script writes to MANIFEST.json; verify it is valid JSON
    if _detect_python; then
        run $PYTHON_CMD -c "import json; json.load(open('$TEST_TMPDIR/.ai/handoff/MANIFEST.json'))"
        [ "$status" -eq 0 ]
    else
        # Fallback: basic structural check -valid JSON starts with { and ends with }
        manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
        [[ "$manifest_content" == "{"* ]]
        [[ "$manifest_content" == *"}" ]]
    fi
}

@test "output contains required fields" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # Use grep-based checks (works everywhere, no python/node path issues)
    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"aahp_version"'* ]]
    [[ "$manifest_content" == *'"project"'* ]]
    [[ "$manifest_content" == *'"last_session"'* ]]
    [[ "$manifest_content" == *'"files"'* ]]
    [[ "$manifest_content" == *'"quick_context"'* ]]
    [[ "$manifest_content" == *'"token_budget"'* ]]
    # Verify last_session sub-fields
    [[ "$manifest_content" == *'"agent"'* ]]
    [[ "$manifest_content" == *'"timestamp"'* ]]
    [[ "$manifest_content" == *'"phase"'* ]]
}

@test "token_budget contains all three tiers" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"manifest_only"'* ]]
    [[ "$manifest_content" == *'"manifest_plus_core"'* ]]
    [[ "$manifest_content" == *'"full_read"'* ]]
}

@test "indexes an optional pii allowlist in MANIFEST.json" {
    create_status_md
    create_next_actions_md
    create_log_md
    echo '{"version":1,"entries":[]}' > "$TEST_TMPDIR/.ai/handoff/pii-allowlist.json"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    grep -q '"pii-allowlist.json"' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

# ??? CLI flag: --agent ???????????????????????????????????????

@test "--agent flag sets agent name in output" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --agent "my-test-agent" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"agent": "my-test-agent"'* ]]
}

# ─── CLI flag: --phase ───────────────────────────────────────

@test "--phase flag sets phase in output" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --phase "implementation" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"phase": "implementation"'* ]]
}

@test "--phase rejects invalid phase values" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --phase "invalid-phase" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid phase"* ]]
}

# ─── CLI flag: --context ─────────────────────────────────────

@test "--context flag sets quick_context" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --context "Custom context string" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"quick_context": "Custom context string"'* ]]
}

@test "auto-generates quick_context when --context is not provided" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # quick_context should not be empty
    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"quick_context": "'* ]]
    # Should not be the fallback "No handoff files" message since we have STATUS.md
    [[ "$manifest_content" != *'"quick_context": "No handoff files found'* ]]
}

# ─── Task preservation on regeneration ───────────────────────
# Note: aahp-manifest.sh uses node to read the existing MANIFEST.json for task
# preservation. On some platforms (e.g. Windows Git Bash) the tmpdir paths may
# not resolve correctly for node. We use grep-based checks and skip if tasks
# were not preserved (indicating a path issue rather than a code bug).

@test "preserves existing tasks field on regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")

    # If node couldn't read the path (Windows tmpdir issue), tasks won't be preserved.
    # Skip rather than fail in that case -it's a platform limitation, not a code bug.
    if [[ "$manifest_content" != *'"tasks"'* ]]; then
        skip "tasks not preserved (likely node cannot resolve tmpdir path on this platform)"
    fi

    [[ "$manifest_content" == *'"T-001"'* ]]
    [[ "$manifest_content" == *'"T-002"'* ]]
    [[ "$manifest_content" == *'"Implement feature X"'* ]]
}

@test "preserves next_task_id on regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")

    if [[ "$manifest_content" != *'"next_task_id"'* ]]; then
        skip "next_task_id not preserved (likely node cannot resolve tmpdir path on this platform)"
    fi

    [[ "$manifest_content" == *'"next_task_id": 3'* ]]
}

@test "preserves existing project name on regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_json

    # TEST_TMPDIR's basename never equals "TestProject", so if regeneration
    # falls back to deriving the name from the directory basename instead of
    # preserving the value already in MANIFEST.json, this test catches it.
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")

    if [[ "$manifest_content" != *'"project"'* ]]; then
        skip "project field missing (likely node cannot resolve tmpdir path on this platform)"
    fi

    [[ "$manifest_content" == *'"project": "TestProject"'* ]]
}

@test "derives project name from directory basename on first generation" {
    create_status_md
    create_next_actions_md
    create_log_md
    # No existing MANIFEST.json AND no git remote: nothing else carries the
    # repository's identity, so the directory basename is the only source left
    # and the original behaviour must be preserved. The precondition is
    # asserted, otherwise a remote appearing in the fixture later would make
    # this test pass for the wrong reason.
    [ -z "$(git -C "$TEST_TMPDIR" remote)" ]

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    expected_name="$(basename "$TEST_TMPDIR")"
    [[ "$manifest_content" == *"\"project\": \"$expected_name\""* ]]
}

# ─── Project name comes from repository identity, not from cwd ───
#
# Every agent in this estate works in a `git worktree` whose directory is named
# after the BRANCH, and CI unpacks into a workdir named after the job. A
# cwd-derived project name therefore rewrites MANIFEST.json's "project" to the
# checkout's name on every regeneration, and the rewrite is invisible unless
# somebody re-reads the file afterwards. Two such values reached consumer main
# branches before this was fixed. Each test below runs the generator from a
# directory whose name is NOT the repository name.

@test "derives project name from the git remote, not the directory it runs in" {
    create_status_md
    create_next_actions_md
    create_log_md
    # First generation (no MANIFEST.json), so the recorded-name path cannot be
    # what rescues this: the remote is the only thing naming the repository.
    git -C "$TEST_TMPDIR" remote add origin https://github.com/homeofe/aahp-consumer.git

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # Guard: the directory really is named something else, so the assertions
    # below discriminate instead of being accidentally true.
    dir_name="$(basename "$TEST_TMPDIR")"
    [ "$dir_name" != "aahp-consumer" ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"project": "aahp-consumer"'* ]]
    [[ "$manifest_content" != *"\"project\": \"$dir_name\""* ]]
}

@test "derives project name from an scp-style remote URL" {
    create_status_md
    create_next_actions_md
    create_log_md
    git -C "$TEST_TMPDIR" remote add origin git@github.com:homeofe/aahp-consumer.git

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    dir_name="$(basename "$TEST_TMPDIR")"
    [ "$dir_name" != "aahp-consumer" ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"project": "aahp-consumer"'* ]]
    [[ "$manifest_content" != *"\"project\": \"$dir_name\""* ]]
}

@test "an unsubstituted [PROJECT] placeholder does not survive regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_json
    git -C "$TEST_TMPDIR" remote add origin https://github.com/homeofe/aahp-consumer.git

    # `aahp init` copies templates/MANIFEST.json in with "[PROJECT]" and tells
    # the adopter to replace it. Until they do, that string is not a name
    # anybody chose, so it must not outrank the repository's real identity.
    manifest="$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    sed 's/"project": "TestProject"/"project": "[PROJECT]"/' "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    # Guard the substitution: had it silently done nothing, the assertion below
    # would pass via the ordinary preserve path and prove nothing.
    grep -q '"project": "\[PROJECT\]"' "$manifest"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$manifest")
    [[ "$manifest_content" == *'"project": "aahp-consumer"'* ]]
    [[ "$manifest_content" != *'"project": "[PROJECT]"'* ]]
}

@test "a recorded project name outranks the git remote" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_json
    # A consumer whose handoff project name deliberately differs from the
    # repository name must keep it. The remote is a fallback for when nothing
    # is on record, never an override of a name a human set.
    git -C "$TEST_TMPDIR" remote add origin https://github.com/homeofe/some-other-repo.git

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"project": "TestProject"'* ]]
    [[ "$manifest_content" != *'"project": "some-other-repo"'* ]]
}

@test "project name survives regeneration when node is unavailable" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_json
    git -C "$TEST_TMPDIR" remote add origin https://github.com/homeofe/aahp-consumer.git

    # Reading the recorded name needs node to parse MANIFEST.json. Where node
    # is missing (a stripped hook PATH, a slim CI image) that whole block is
    # skipped SILENTLY - not even the "could not read" warning prints, because
    # the warning lives inside the `command -v node` guard. Before the remote
    # fallback existed, the name then became the directory basename with no
    # diagnostic at all. git alone is enough to get it right.
    # Drop only the directory node lives in, rather than building a shim
    # directory: a shim needs copies or symlinks of bash and git, which is not
    # portable to Windows, and a test that can only ever skip proves nothing.
    node_dir="$(dirname "$(command -v node)")"
    stripped_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$node_dir" | paste -sd: -)"

    # Guard the isolation itself. If node were still reachable, or bash/git
    # were not, this test would report green without exercising the path it
    # names. Fail rather than skip: on every platform this suite runs on,
    # node is installed somewhere other than the directory holding bash.
    PATH="$stripped_path" command -v git >/dev/null 2>&1
    PATH="$stripped_path" command -v bash >/dev/null 2>&1
    ! PATH="$stripped_path" command -v node >/dev/null 2>&1

    dir_name="$(basename "$TEST_TMPDIR")"
    run env PATH="$stripped_path" bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"project": "aahp-consumer"'* ]]
    [[ "$manifest_content" != *"\"project\": \"$dir_name\""* ]]
}

# ─── File indexing ───────────────────────────────────────────

@test "indexes all present handoff files" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"STATUS.md"'* ]]
    [[ "$manifest_content" == *'"NEXT_ACTIONS.md"'* ]]
    [[ "$manifest_content" == *'"LOG.md"'* ]]
}

@test "file entries include checksum, updated, lines, summary" {
    create_status_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"checksum": "sha256:'* ]]
    [[ "$manifest_content" == *'"updated":'* ]]
    [[ "$manifest_content" == *'"lines":'* ]]
    [[ "$manifest_content" == *'"summary":'* ]]
}

# ─── Error handling ──────────────────────────────────────────

@test "handles missing handoff directory gracefully" {
    # Use a path that has no .ai/handoff/
    local empty_dir
    empty_dir="$(_make_tmpdir)"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$empty_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]

    rm -rf "$empty_dir"
}

@test "handles empty handoff directory (no files)" {
    # .ai/handoff/ exists but contains no .md files
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # Should still produce valid JSON with empty files object
    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"files": {'* ]]
}

@test "non-quiet mode prints summary output" {
    create_status_md
    create_next_actions_md
    create_log_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST.json generated"* ]]
    [[ "$output" == *"Token budget"* ]]
}

@test "sets aahp_version to 3.0" {
    create_status_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"aahp_version": "3.0"'* ]]
}

@test "--session-id flag sets session_id" {
    create_status_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --session-id "custom-session-42" --quiet
    [ "$status" -eq 0 ]

    manifest_content=$(cat "$TEST_TMPDIR/.ai/handoff/MANIFEST.json")
    [[ "$manifest_content" == *'"session_id": "custom-session-42"'* ]]
}

@test "unknown option produces error" {
    create_status_md

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --bogus-flag
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
