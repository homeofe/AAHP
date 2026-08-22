#!/usr/bin/env bats
# verify-workflow.bats - "can the workflow that runs the AAHP gate skip it?"
#
# The gate under test answers one question about a CONSUMER: does there exist an
# event on which the required AAHP check concludes SUCCESS without having run the
# gate at --level ci? Both directions are asserted here. A gate that only ever
# says "bypassable" would be as useless as one that only ever says "enforced",
# and the enforced fixtures are what keep the failing ones meaningful.

load test_helper

GATE="$AAHP_ROOT/scripts/check-verify-workflow.mjs"
AAHP="$AAHP_ROOT/bin/aahp.js"
FIXTURES="$AAHP_ROOT/tests/fixtures/workflows"

# Install one fixture as the repo's only workflow.
install_workflow() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$FIXTURES/$1" "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}

# ─── enforced: the gate cannot be skipped ────────────────────────────────────

@test "enforced: the canonical workflow propagate.sh installs exits 0" {
    install_workflow enforced-canonical.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" == *"unconditionally at --level ci"* ]]
}

@test "enforced: the published CLI invoked by exact version is recognised" {
    # Regression: `npx -y @scope/aahp@3.10.0 verify . --level ci` is a gate run.
    # A pattern that missed the @version suffix called two live consumers
    # undecidable and never named their bypass.
    install_workflow enforced-npx-package-spec.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unconditionally at --level ci"* ]]
}

@test "enforced: an if: on a job that does NOT host the gate is not a finding" {
    # enforced-npx-package-spec.yml carries a second, conditional job. Only the
    # job that runs the gate is this gate's business; flagging the rest would be
    # the false positive that gets a tool switched off.
    install_workflow enforced-npx-package-spec.yml
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verdict": "enforced"'* ]]
    [[ "$output" != *"advisory"* ]]
}

@test "enforced: an explicit continue-on-error: false is not a bypass" {
    install_workflow enforced-npx-package-spec.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "enforced: paths filters and a checkout-only if: are NOT findings" {
    # Both fail CLOSED, so neither can produce a green tick over an unrun gate:
    # a `paths:` filter leaves a required check pending (the pull request is
    # blocked), and skipping only the checkout leaves the gate running against an
    # empty workspace, where it exits non-zero. Pinned as a test because a
    # documented-but-untested exemption is how the original defect got in.
    install_workflow enforced-fails-closed-shapes.yml
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verdict": "enforced"'* ]]
    [[ "$output" != *"job-conditional"* ]]
}

# ─── bypassable: each way the check can go green having run nothing ──────────

@test "bypassable: a step-level if: on the gate step is reported, exit 1" {
    install_workflow bypass-step-conditional.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci-step-conditional"* ]]
    [[ "$output" == *"Layer 1 MANIFEST checksum integrity is skipped too"* ]]
}

@test "bypassable: a job-level if: on the hosting job is reported, exit 1" {
    install_workflow bypass-job-conditional.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"job-conditional"* ]]
}

@test "bypassable: a partial exemption that keeps a weaker level still fails" {
    # A run that only reaches --level prepush honours AAHP_SKIP_VERIFY and skips
    # the drift gate, yet reports under the same required check name.
    install_workflow bypass-partial-layer1.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci-step-conditional"* ]]
}

@test "bypassable: continue-on-error on the gate step is reported, exit 1" {
    install_workflow bypass-soft-failing.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci-step-soft-failing"* ]]
}

@test "bypassable: running the gate below --level ci is reported, exit 1" {
    install_workflow bypass-no-ci-level.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no-ci-level"* ]]
    [[ "$output" == *"AAHP_SKIP_VERIFY"* ]]
}

# ─── neither: absent, and undecidable ────────────────────────────────────────

@test "absent: a repo with no workflows exits 0 and says there is no backstop" {
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
    [[ "$output" == *"no CI backstop"* ]]
}

@test "absent: workflows that never run the gate are not this gate's business" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    printf 'name: Build\non:\n  push:\njobs:\n  build:\n    if: github.ref == \x27refs/heads/main\x27\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm test\n' \
        > "$TEST_TMPDIR/.github/workflows/ci.yml"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}

@test "undecidable: the gate reached through an action exits 2, never 0" {
    install_workflow undecidable-indirect.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNDECIDED"* ]]
    [[ "$output" == *"Undecided is not clean"* ]]
}

@test "undecidable: an unparseable verify workflow exits 2, never 0" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    printf 'name: AAHP Verify\njobs:\n  aahp-verify:\n   steps:\n  - run: bash scripts/verify-handoff.sh . --level ci\n     bad: [unclosed\n' \
        > "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNDECIDED"* ]]
}

@test "a broken workflow that has nothing to do with AAHP does not fail the gate" {
    install_workflow enforced-canonical.yml
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$TEST_TMPDIR/.github/workflows/other.yml"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── the reader must agree with real YAML ────────────────────────────────────

@test "the zero-dependency YAML reader agrees with a real parser on every workflow" {
    # See tests/assert-workflow-parser-parity.mjs: the gate ships without a YAML
    # dependency, so this is what stops its reader from drifting into misreading
    # a workflow and calling it enforced.
    run node "$AAHP_ROOT/tests/assert-workflow-parser-parity.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow parser parity OK"* ]]
}

# ─── wiring: doctor must actually run it ─────────────────────────────────────

@test "doctor: reports verify-workflow pass on the canonical workflow" {
    install_workflow enforced-canonical.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verify-workflow": "pass"'* ]]
}

@test "doctor: FAILS the conformance record when the gate can be skipped" {
    install_workflow bypass-step-conditional.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conformance FAILED"* ]]
    [[ "$output" == *"verify-workflow"* ]]
}

@test "doctor: an undecidable verify workflow fails closed, it does not skip" {
    install_workflow undecidable-indirect.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"verify-workflow": "fail"'* ]]
}

@test "doctor: a repo with no workflows skips the gate rather than failing it" {
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verify-workflow": "skip"'* ]]
}

@test "doctor: AAHP's own workflow passes its own gate (dogfood)" {
    run node "$AAHP" doctor "$AAHP_ROOT" --json
    [[ "$output" == *'"verify-workflow": "pass"'* ]]
}
