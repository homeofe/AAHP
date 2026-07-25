#!/usr/bin/env bats
# nonnpm-root.bats - gate applicability on a root with NO package.json.
#
# A polyglot repository can adopt AAHP at a root that has no package.json of its
# own (for example a Python service whose only package.json lives in a frontend
# subdirectory) and still keep a valid handoff set at .ai/handoff/. The three
# gate commands used to disagree about such a repository: `verify` was green,
# `doctor` reported changelog-format = fail (structurally, on the missing version
# source, before it ever read the changelog) and `check` reported handoff = fail
# with "package.json not found". A gate that cannot apply must SKIP, not FAIL.
#
# These tests pin BOTH directions: a non-npm root reaches a clean state in doctor
# AND check, and a root that DOES have a package.json still fails when it should.
#
# setup() (test_helper) creates no package.json, so "non-npm" is the default
# state of TEST_TMPDIR and the npm fixtures add one explicitly.

load test_helper

AAHP="$AAHP_ROOT/bin/aahp.js"

gadd() {
    git -C "$TEST_TMPDIR" add -A
}

# Valid Keep a Changelog content whose top release is 1.0.0 and whose
# reference-link footer is complete, so any failure here is structural.
write_changelog() {
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01
**first**

### Added
- a thing

[Unreleased]: https://example.invalid/x/y/compare/v1.0.0...HEAD
[1.0.0]: https://example.invalid/x/y/releases/tag/v1.0.0
EOF
}

# A handoff set good enough for doctor's three handoff gates: a MANIFEST.json
# with no dangling indexed files, GROUNDING.md, and a TRUST.md that carries a
# Provenance column. Every file here is in the canonical handoff file list, so
# handoff-set reports no strays.
write_handoff_set() {
    local h="$TEST_TMPDIR/.ai/handoff"
    create_manifest_json "$h"
    echo "# GROUNDING" > "$h/GROUNDING.md"
    cat > "$h/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Provenance | Notes |
|----------|--------|------------|-------|
| build passes | verified | test_verified | ok |
EOF
}

# The issue fixture: no root package.json, a valid handoff set, a CHANGELOG.md.
scaffold_nonnpm_root() {
    write_changelog
    write_handoff_set
    gadd
}

# assert_gate <json-record> <gate-id> <expected-status>
assert_gate() {
    node -e '
      const r = JSON.parse(process.argv[1]);
      const got = r.gates[process.argv[2]];
      if (got !== process.argv[3]) {
        console.error(`gate ${process.argv[2]}: expected ${process.argv[3]}, got ${got}`);
        process.exit(1);
      }
    ' "$1" "$2" "$3"
}

# --- non-npm root: the gates that cannot apply must skip ---------------------

@test "doctor: non-npm root with a CHANGELOG.md skips changelog-format instead of failing" {
    scaffold_nonnpm_root
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    assert_gate "$output" "changelog-format" "skip"
}

@test "doctor: non-npm root reaches a fully clean conformance record" {
    scaffold_nonnpm_root
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conformance OK"* ]]
    [[ "$output" != *"package.json not found"* ]]
}

@test "doctor: non-npm root skips version-sync even when versionSites are configured" {
    scaffold_nonnpm_root
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "versionSites": [ { "file": "CHANGELOG.md", "minOccurrences": 1 } ] }
EOF
    gadd
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    assert_gate "$output" "version-sync" "skip"
}

@test "doctor: non-npm root skips pinned-dep instead of reporting it missing" {
    scaffold_nonnpm_root
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "pinnedDep": {} }
EOF
    gadd
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    assert_gate "$output" "pinned-dep" "skip"
}

@test "check: non-npm root with a valid handoff set does not fail the handoff gate" {
    scaffold_nonnpm_root
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" != *"package.json not found"* ]]
    node -e '
      const r = JSON.parse(process.argv[1]);
      if (r.gates["handoff"] === "fail") process.exit(1);
    ' "$output"
}

@test "check: non-npm root exits 0 with no gate reported as failed" {
    scaffold_nonnpm_root
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Governance OK"* ]]
    [[ "$output" != *"Governance FAILED"* ]]
}

@test "doctor and check agree on the same non-npm root (both clean)" {
    scaffold_nonnpm_root
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
}

# --- npm roots: the same gates must still bite ------------------------------

@test "doctor: npm root whose CHANGELOG top release is stale still FAILS changelog-format" {
    echo '{ "name": "fx", "version": "9.9.9" }' > "$TEST_TMPDIR/package.json"
    write_changelog
    write_handoff_set
    gadd
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    assert_gate "$output" "changelog-format" "fail"
}

@test "check: npm root whose CHANGELOG top release is stale still FAILS changelog-format" {
    echo '{ "name": "fx", "version": "9.9.9" }' > "$TEST_TMPDIR/package.json"
    write_changelog
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    assert_gate "$output" "changelog-format" "fail"
}

@test "check: npm root with a stale NEXT_ACTIONS version still FAILS the handoff gate" {
    echo '{ "name": "fx", "version": "1.2.3" }' > "$TEST_TMPDIR/package.json"
    write_handoff_set
    printf 'Current version: **v1.0.0**\n' > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    assert_gate "$output" "handoff" "fail"
}

@test "check: a present-but-malformed package.json still RUNS changelog-format" {
    # Applicability is decided on the PRESENCE of package.json, never on it
    # parsing, so a broken manifest fails loudly instead of disappearing into a
    # skip. This is the guard against fixing the non-npm case by making every
    # unreadable package.json invisible.
    printf 'this is not json\n' > "$TEST_TMPDIR/package.json"
    write_changelog
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    assert_gate "$output" "changelog-format" "fail"
}
