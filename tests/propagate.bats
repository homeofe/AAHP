#!/usr/bin/env bats
# propagate.bats - The fail-closed gate and its parser travel together.

setup() {
    load test_helper
    setup
    create_full_handoff
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "seed handoff"
}

teardown() {
    teardown
}

@test "propagation copies the parser and explicit-base workflow together" {
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    grep -q 'aahp_non_impacting_modified_files' "$TEST_TMPDIR/scripts/_aahp-lib.sh"
    grep -q 'AAHP_BASE_SHA.*pull_request.base.sha.*event.before.*inputs.base' \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    ! grep -Eqi 'dependabot|author\.username|github\.actor' \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}
