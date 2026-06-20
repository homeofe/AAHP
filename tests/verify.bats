#!/usr/bin/env bats
# verify.bats -Tests for scripts/verify-handoff.sh (the canonical aahp gate)

setup() {
    load test_helper
    setup

    # The verify script reuses lint-handoff.sh and _aahp-lib.sh from SCRIPTS_DIR.
    # Seed a clean handoff dir and a current MANIFEST so layers 1 and 3 pass.
    create_full_handoff
    # Add a TRUST.md with no expired verified rows by default.
    cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Example future row | verified | 2026-01-01 | tester | 30d | 2099-01-01 | not expired |
EOF
    # Commit the seed so HEAD reflects the handoff state.
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "seed handoff"
    # Regenerate the manifest against that commit, then commit it.
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "manifest"
}

teardown() {
    teardown
}

# ─── Happy path ──────────────────────────────────────────────

@test "passes on a clean handoff repo at level full" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"aahp verify passed"* ]]
}

@test "passes at level precommit with no changes" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
}

# ─── Layer 2: content-drift gate (the key check) ─────────────

@test "drift gate FAILS when code changes but handoff does not (precommit)" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Code changed but handoff state did not. Run /handoff."* ]]
}

@test "drift gate PASSES when code + STATUS.md + MANIFEST.json change together" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    printf '\n<!-- session note -->\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"handoff state (STATUS.md + MANIFEST.json) changed with it"* ]]
}

@test "drift gate FAILS when code + MANIFEST change but STATUS.md does not" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add feature.js .ai/handoff/MANIFEST.json

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing: .ai/handoff/STATUS.md update"* ]]
}

@test "handoff-only changes never trigger the drift gate" {
    # A proper handoff-only change: edit a handoff file AND regenerate the
    # manifest (so layer 1 checksums stay valid). No source file outside
    # .ai/handoff/ is touched, so layer 2 must not fire.
    printf '\n<!-- doc tweak -->\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add .ai/handoff/

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Drift gate not triggered"* ]]
}

# ─── Escape hatch ────────────────────────────────────────────

@test "AAHP_SKIP_VERIFY=1 skips local verification at precommit" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    AAHP_SKIP_VERIFY=1 run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping local handoff verification"* ]]
}

@test "AAHP_SKIP_VERIFY=1 is IGNORED at level ci" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    AAHP_SKIP_VERIFY=1 run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci
    [ "$status" -eq 1 ]
    [[ "$output" == *"Code changed but handoff state did not"* ]]
}

# ─── Layer 1: checksum integrity ─────────────────────────────

@test "FAILS when a handoff file is modified outside the protocol (checksum mismatch)" {
    # Mutate STATUS.md without regenerating the manifest.
    printf '\nunmanaged edit\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksums do not match"* || "$output" == *"Checksum mismatch"* ]]
}

# ─── Layer 4: TRUST-TTL (advisory) ───────────────────────────

@test "reports expired verified trust rows as a warning (non-blocking)" {
    cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Stale claim | verified | 2026-01-01 | tester | 7d | 2026-01-08 | should be expired |
EOF
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    # Expired trust is advisory: it warns but does not fail the gate on its own.
    [[ "$output" == *"expired 'verified' trust"* ]]
    [[ "$output" == *"Stale claim"* ]]
}

# ─── Argument handling ───────────────────────────────────────

@test "rejects an invalid --level" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid --level"* ]]
}

@test "errors when no handoff directory exists" {
    EMPTY="$(_make_tmpdir)"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$EMPTY" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
    rm -rf "$EMPTY"
}
