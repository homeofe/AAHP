#!/usr/bin/env bats
# archive.bats - Tests for scripts/aahp-archive.sh

setup() {
    load test_helper
    setup
    mkdir -p "$TEST_TMPDIR/.ai/handoff"
}

teardown() {
    teardown
}

_write_log_entries() {
    cat > "$TEST_TMPDIR/.ai/handoff/LOG.md" <<'EOF'
# AAHP: Agent Journal

> Append-only. Never delete or edit past entries.

---

## [2026-06-26] Agent: newest

newest body

---

## [2026-06-25] Agent: middle

middle body

---

## [2026-06-24] Agent: oldest

oldest body
EOF
}

@test "archive rotates older entries into LOG-ARCHIVE.md" {
    _write_log_entries
    run bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1
    [ "$status" -eq 0 ]
    grep -q "newest" "$TEST_TMPDIR/.ai/handoff/LOG.md"
    ! grep -q "middle" "$TEST_TMPDIR/.ai/handoff/LOG.md"
    grep -q "middle" "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
    grep -q "oldest" "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
}

@test "archive verify fails when rotation is still required" {
    _write_log_entries
    run bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1 --verify
    [ "$status" -eq 1 ]
    [[ "$output" == *"archive rotation required"* ]]
}

@test "archive verify passes after rotation" {
    _write_log_entries
    bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1
    run bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1 --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG archive verify passed"* ]]
}

@test "archive rotation is idempotent" {
    _write_log_entries
    bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1
    before=$(sha256sum "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md" | awk '{print $1}')
    bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1
    after=$(sha256sum "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md" | awk '{print $1}')
    [ "$before" = "$after" ]
}

@test "archive verify fails when LOG-ARCHIVE.md is truncated" {
    _write_log_entries
    bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1
    echo "# truncated" > "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
    run bash "$SCRIPTS_DIR/aahp-archive.sh" "$TEST_TMPDIR" --keep 1 --verify
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing indexed archived entries"* ]]
}

@test "manifest indexes LOG-ARCHIVE.md when present" {
    create_status_md
    create_next_actions_md
    create_log_md
    echo "# Archive" > "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
    echo '{"version":1,"entries":[]}' > "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.index.json"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    grep -q '"LOG-ARCHIVE.md"' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    grep -q '"LOG-ARCHIVE.index.json"' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}
