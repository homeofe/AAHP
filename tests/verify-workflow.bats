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

# --- reported always, blocking only where a repository asked for it ----------
#
# This gate's finding is correct wherever it fires, and it fires on a deliberate,
# documented configuration that no pull-request author can clear from their own
# pull request. Measured before the default was chosen: `aahp doctor . --json`, the
# exact command every consuming repository runs as a CI step, went from exit 0 under
# the published 3.10.0 to exit 1 in 8 of 10 of them with nothing changed on their
# side, and neither `--governance` nor `check: { only: [] }` could switch it off.
#
# So it reports by default and blocks on opt-in, the same shape trustTtl.enforce
# uses. The two tests below are a pair on purpose: the first alone would also pass
# for an implementation that ignores the config and fails everywhere, which is the
# version that reds the fleet.

@test "doctor: FAILS the conformance record when the gate can be skipped AND enforce is on" {
    install_workflow bypass-step-conditional.yml
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "verifyWorkflow": { "enforce": true }
}
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conformance FAILED"* ]]
    [[ "$output" == *"verify-workflow"* ]]
}

@test "doctor: the SAME workflow is reported and not blocking without enforce" {
    # The other half. Three assertions, because "not enforced" must stay
    # distinguishable from "nothing found": the run passes, the token is
    # `advisory` rather than `pass`, and the finding is still named.
    install_workflow bypass-step-conditional.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verify-workflow": "advisory"'* ]]
    [[ "$output" != *'"verify-workflow": "pass"'* ]]
    [[ "$output" == *"ci-step-conditional"* ]]
    [[ "$output" == *"NOT ENFORCED"* ]]
}


@test "doctor: an undecidable verify workflow fails closed, it does not skip" {
    install_workflow undecidable-indirect.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"verify-workflow": "fail"'* ]]
}

@test "doctor: a repo with no workflows skips the gate rather than failing it" {
    # RE-GROUNDED, not relaxed. The subject is the gate STATUS: absence of a
    # workflow is `skip` ("there is nothing here to weaken"), never `fail`. The
    # exit code used to be 0 and is now 1, because this fixture is also a
    # repository in which doctor evaluates ZERO gates, and zero evaluated is NOT
    # EVALUATED. Both halves are asserted so neither can drift unnoticed.
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"verify-workflow": "skip"'* ]]
    [[ "$output" != *'"verify-workflow": "fail"'* ]]
    [[ "$output" == *'"evaluated": 0'* ]]
}

@test "doctor: AAHP's own workflow passes its own gate (dogfood)" {
    run node "$AAHP" doctor "$AAHP_ROOT" --json
    [[ "$output" == *'"verify-workflow": "pass"'* ]]
}

# ─── the governance workflow, which this gate used to skip entirely ──────────
#
# assets/governance/aahp-govern.yml is what `aahp init --gates` writes into an
# adopting repository, and a governance-only adopter has no aahp-verify.yml at
# all, so it is their whole CI backstop. Before these tests the audit did not
# look at it: `if: false` on its gate step left `aahp doctor` reporting
# `SKIP verify-workflow: no workflow here runs the AAHP verify gate`, exit 0.

install_govern_workflow() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$FIXTURES/$1" "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
}

@test "govern: the scaffolded governance workflow is recognised, exit 0" {
    install_govern_workflow govern-enforced.yml
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verdict": "governance-only"'* ]]
    [[ "$output" == *'"job": "govern"'* ]]
}

@test "govern: governance-only is NOT reported as enforced" {
    # The two verdicts answer different questions. `enforced` means the verify
    # gate runs at --level ci, which is the only thing that compares a handoff
    # checksum. Collapsing them would let a repository with no handoff integrity
    # checking anywhere emit the same token as one that has it.
    install_govern_workflow govern-enforced.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unconditionally at --level ci"* ]]
    [[ "$output" == *"nothing in this repository compares a handoff checksum"* ]]
}

@test "govern: an if: on the step that runs aahp check is reported, exit 1" {
    # The finding from the issue. The record step below it is unconditional, so
    # a per-JOB test reads this file as enforced; the audit is per subcommand.
    install_govern_workflow govern-bypass-step-conditional.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"govern-step-conditional"* ]]
    [[ "$output" == *'aahp check'* ]]
}

@test "govern: a job-level if: over the governance job is reported, exit 1" {
    install_govern_workflow govern-bypass-job-conditional.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"govern-job-conditional"* ]]
}

@test "govern: continue-on-error on the governance gate step is reported, exit 1" {
    install_govern_workflow govern-bypass-soft-failing.yml
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"govern-step-soft-failing"* ]]
}

@test "govern: an explicit continue-on-error: false is not itself a finding" {
    # govern-bypass-soft-failing.yml sets it on the record step. Exactly one
    # finding must come out of that file, and it must be about the gate step.
    install_govern_workflow govern-bypass-soft-failing.yml
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    # Exactly ONE finding out of that file, and it is the one about the gate
    # step. Two would mean the explicit `false` on the record step was read as a
    # bypass, which is the false positive this asserts against.
    [ "$(printf '%s\n' "$output" | grep -c '"id":')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c 'govern-step-soft-failing')" -eq 1 ]
}

@test "govern: the SHIPPED assets/governance/aahp-govern.yml passes its own gate" {
    # Dogfood on the real file, not on a copy of it: this is the document with
    # the widest blast radius in the package, and a fixture cannot prove the
    # shipped bytes are clean.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/assets/governance/aahp-govern.yml" "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verdict": "governance-only"'* ]]
}

@test "govern: doctor FAILS the record when the governance gate can be skipped AND enforce is on" {
    install_govern_workflow govern-bypass-step-conditional.yml
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "verifyWorkflow": { "enforce": true }
}
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conformance FAILED"* ]]
    [[ "$output" == *"verify-workflow"* ]]
}

@test "govern: doctor's pass line says no handoff checksum is compared" {
    # A green `verify-workflow` line in a governance-only repository must not be
    # readable as a handoff-integrity statement. Nothing there hashes a file.
    install_govern_workflow govern-enforced.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"no handoff checksum is compared"* ]]
}

@test "govern: a workflow named as the governance one that this reader cannot follow is undecidable" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    printf 'name: AAHP Govern\non:\n  pull_request:\njobs:\n  govern:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: ./.github/actions/run-governance\n' \
        > "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNDECIDED"* ]]
}

@test "govern: a verify workflow alongside a clean governance one stays enforced" {
    # Adopting both must not degrade the stronger verdict.
    install_workflow enforced-canonical.yml
    install_govern_workflow govern-enforced.yml
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verdict": "enforced"'* ]]
}

@test "govern: npm run govern is deliberately NOT treated as a gate invocation" {
    # What the script expands to is not readable from the workflow. Guessing
    # would be a finding this reader cannot support, and a false positive here
    # is what gets the whole gate switched off.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    printf 'name: CI\non:\n  pull_request:\njobs:\n  build:\n    if: false\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm run govern\n' \
        > "$TEST_TMPDIR/.github/workflows/ci.yml"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}
