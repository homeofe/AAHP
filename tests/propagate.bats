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
    cmp "$AAHP_ROOT/scripts/verify-handoff.sh" "$TEST_TMPDIR/scripts/verify-handoff.sh"
    cmp "$AAHP_ROOT/scripts/_aahp-lib.sh" "$TEST_TMPDIR/scripts/_aahp-lib.sh"
    cmp "$AAHP_ROOT/.github/workflows/aahp-verify.yml" \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}

@test "the packed npm artifact propagates byte-identical gate files and workflow" {
    local pack_dir install_dir tarball installed_root
    pack_dir="$TEST_TMPDIR/pack"
    install_dir="$TEST_TMPDIR/install"
    mkdir -p "$pack_dir" "$install_dir"

    run npm pack "$AAHP_ROOT" --silent --pack-destination "$pack_dir"
    [ "$status" -eq 0 ]
    tarball="$pack_dir/$(printf '%s\n' "$output" | tail -1)"
    [ -f "$tarball" ]

    run npm install --silent --ignore-scripts --no-audit --no-fund --no-package-lock \
        --prefix "$install_dir" "$tarball"
    [ "$status" -eq 0 ]
    installed_root="$install_dir/node_modules/@elvatis_com/aahp"
    [ -f "$installed_root/.github/workflows/aahp-verify.yml" ]

    run bash "$installed_root/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    cmp "$AAHP_ROOT/scripts/verify-handoff.sh" "$TEST_TMPDIR/scripts/verify-handoff.sh"
    cmp "$AAHP_ROOT/scripts/_aahp-lib.sh" "$TEST_TMPDIR/scripts/_aahp-lib.sh"
    cmp "$AAHP_ROOT/.github/workflows/aahp-verify.yml" \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}
