#!/usr/bin/env bats
# verify.bats -Tests for scripts/verify-handoff.sh (the canonical aahp gate)

# The fixture every test starts from is built ONCE per file and copied per test.
# It used to be rebuilt in setup() for every test: a git init, the handoff set,
# a manifest regeneration and two commits, about 0.4 s each on Linux and far
# more on Windows, spent identically 31 times. A copy of the finished repository
# is byte-identical (same objects, same SHAs, so CI_BASE stays valid) and costs
# one cp.
setup_file() {
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
    VERIFY_FIXTURE="$TEST_TMPDIR"
    VERIFY_CI_BASE="$(git -C "$TEST_TMPDIR" rev-parse HEAD~1)"
    export VERIFY_FIXTURE VERIFY_CI_BASE
}

teardown_file() {
    if [ -n "${VERIFY_FIXTURE:-}" ] && [ -d "$VERIFY_FIXTURE" ]; then
        rm -rf "$VERIFY_FIXTURE"
    fi
}

setup() {
    load test_helper
    TEST_TMPDIR="$(_make_tmpdir)"
    export TEST_TMPDIR
    cp -R "$VERIFY_FIXTURE/." "$TEST_TMPDIR/"
    CI_BASE="$VERIFY_CI_BASE"
}

teardown() {
    teardown
}

# Commit the working tree as one change set in which handoff state moves with
# it. aahp.config.json and every other root file are handoff-impacting, so
# without the STATUS.md note and the regenerated manifest the exit code of a
# Layer 4 test would be Layer 2's, and an assertion on a non-zero status would
# pass whether or not the layer under test works at all.
commit_with_handoff() {
    printf '\n<!-- fixture: %s -->\n' "$1" >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "$1"
}

write_trust() { cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md"; }
write_config() { cat > "$TEST_TMPDIR/aahp.config.json"; }

# The UTC calendar date N days before today, as the gate computes "today".
days_ago() {
    node -e 'process.stdout.write(new Date(Date.now() - Number(process.argv[1]) * 864e5).toISOString().slice(0, 10))' "$1"
}

# A lib copy in which every helper takes its Python path.
python_only_lib() {
    local lib="$TEST_TMPDIR/python-only-lib.sh"
    sed 's/command -v node &>\/dev\/null/false/g' "$SCRIPTS_DIR/_aahp-lib.sh" > "$lib"
    printf '%s\n' "$lib"
}

write_mit_license_fixture() {
    printf '{ "name": "fixture", "version": "1.0.0", "license": "%s" }\n' "$1" > "$TEST_TMPDIR/package.json"
    cat > "$TEST_TMPDIR/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026 Fixture

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.
EOF
}

# --- Happy path ----------------------------------------------

@test "passes on a clean handoff repo at level full" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"aahp verify passed"* ]]
}

@test "passes at level precommit with no changes" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
}

# --- Layer 2: content-drift gate (the key check) -------------

@test "drift gate FAILS when code changes but handoff does not (precommit)" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not."* ]]
}

@test "drift gate PASSES when code + STATUS.md + MANIFEST.json change together" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    printf '\n<!-- session note -->\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Handoff-impacting files changed and handoff state (STATUS.md + MANIFEST.json) changed with them"* ]]
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

# --- Escape hatch --------------------------------------------

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

    AAHP_SKIP_VERIFY=1 run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
}

# --- Layer 1: checksum integrity -----------------------------

@test "FAILS when a handoff file is modified outside the protocol (checksum mismatch)" {
    # Mutate STATUS.md without regenerating the manifest.
    printf '\nunmanaged edit\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksums do not match"* || "$output" == *"Checksum mismatch"* ]]
}

@test "FAILS when a file indexed by MANIFEST.json is deleted (level ci)" {
    rm "$TEST_TMPDIR/.ai/handoff/LOG.md"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "delete an indexed handoff file"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing indexed file: LOG.md"* ]]
    [[ "$output" == *"indexes file(s) that are not present"* ]]
    # A deletion must not be reported as if it were a tampered file.
    [[ "$output" != *"checksums do not match"* ]]
}

# Layer 1 must reach BOTH integrity verdicts on its own. The stub below is a
# lint-handoff.sh that prints NOTHING and exits 0, which is what a lint that
# dies early looks like from the outside. Nothing in the stub's output can be
# grepped, and its exit code says "clean", so any failure the gate reports has
# to have been computed by Layer 1 itself. A stub that prints the literal
# string Layer 1 used to grep for would only prove the grep works.

_stub_scripts_dir_with_silent_passing_lint() {
    local stub="$TEST_TMPDIR/stub-scripts"
    rm -rf "$stub"
    cp -r "$SCRIPTS_DIR" "$stub"
    cat > "$stub/lint-handoff.sh" <<'STUB'
#!/usr/bin/env bash
# Stub: prints nothing at all and exits 0.
exit 0
STUB
    echo "$stub"
}

@test "Layer 1 blocks a checksum mismatch when lint is silent and exits 0" {
    local stub
    stub="$(_stub_scripts_dir_with_silent_passing_lint)"
    # Real tampering, not a stubbed message.
    printf '\nunmanaged edit\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"

    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksums do not match"* ]]
    [[ "$output" == *"Checksum mismatch: STATUS.md"* ]]
}

@test "Layer 1 blocks a deleted indexed file when lint is silent and exits 0" {
    local stub
    stub="$(_stub_scripts_dir_with_silent_passing_lint)"
    rm "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"

    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing indexed file: NEXT_ACTIONS.md"* ]]
}

# --- Layer 1 must not fail open when it cannot check ---------

@test "Layer 1 FAILS with a named helper when _aahp-lib.sh is out of date" {
    # A partially synced repository: the gate scripts are new, the shared
    # library is old and does not carry the helper Layer 1 needs. Without a
    # guard this aborts at exit 127 with no diagnostic.
    local stub="$TEST_TMPDIR/stub-oldlib"
    rm -rf "$stub"
    cp -r "$SCRIPTS_DIR" "$stub"
    printf '\nunset -f aahp_manifest_index\n' >> "$stub/_aahp-lib.sh"

    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"aahp_manifest_index"* ]]
    [[ "$output" == *"out of date"* ]]
    [[ "$output" != *"aahp verify passed"* ]]
}

@test "Layer 1 FAILS when no JSON interpreter is available" {
    # The helper signals "I could not answer" with exit 2. That must block,
    # not read as an empty (and therefore innocent) index.
    local stub="$TEST_TMPDIR/stub-nointerp"
    rm -rf "$stub"
    cp -r "$SCRIPTS_DIR" "$stub"
    printf '\naahp_manifest_index() { return 2; }\n' >> "$stub/_aahp-lib.sh"

    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No JSON interpreter available"* ]]
    [[ "$output" != *"aahp verify passed"* ]]
}

@test "Layer 1 FAILS when MANIFEST.json indexes nothing" {
    local py
    py="$(bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'; aahp_python_cmd")"
    require_tool "no working python interpreter" [ -n "$py" ]
    "$py" - "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'PY'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path, encoding="utf-8"))
manifest["files"] = {}
json.dump(manifest, open(path, "w", encoding="utf-8"), indent=2)
PY

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"indexes no files"* ]]
    [[ "$output" != *"aahp verify passed"* ]]
}

@test "Layer 1 FAILS when a present handoff file is not indexed at all" {
    # A PARTIAL index defeats the whole guard: drop a file's entry, rewrite the
    # file, and every remaining comparison still matches. Zero comparisons ran
    # for the one file that changed, which is the empty-index defect at N-1
    # iterations. The deletion check cannot see it (the file is present) and
    # the checksum check cannot see it (there is nothing to compare against).
    local py
    py="$(bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'; aahp_python_cmd")"
    require_tool "no working python interpreter" [ -n "$py" ]
    printf 'MALICIOUS CONTENT\n' > "$TEST_TMPDIR/.ai/handoff/LOG.md"
    "$py" - "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'PY'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path, encoding="utf-8"))
manifest["files"].pop("LOG.md", None)
json.dump(manifest, open(path, "w", encoding="utf-8"), indent=2)
PY
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "drop one entry from the index"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unindexed handoff file: LOG.md"* ]]
    [[ "$output" == *"present on disk but NOT indexed"* ]]
    [[ "$output" != *"aahp verify passed"* ]]
}

@test "Layer 1 tolerates a CRLF-terminated index on an intact handoff set" {
    # The python fallback used to write the index through text-mode stdout, so
    # on Windows every line came back CRLF and the trailing CR was carried into
    # the recorded checksum, making every file mismatch. The emitter now writes
    # bytes; the reader additionally strips a trailing CR, so a stale or
    # third-party emitter cannot resurrect the false mismatch.
    local stub="$TEST_TMPDIR/stub-crlf"
    rm -rf "$stub"
    cp -r "$SCRIPTS_DIR" "$stub"
    local py
    py="$(bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'; aahp_python_cmd")"
    require_tool "no working python interpreter" [ -n "$py" ]
    cat >> "$stub/_aahp-lib.sh" <<LIBSTUB

aahp_manifest_index() {
    "$py" -c '
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
for name, meta in (m.get("files") or {}).items():
    sys.stdout.buffer.write(("%s\t%s\r\n" % (name, meta.get("checksum", ""))).encode("utf-8"))
' "\$1"
}
LIBSTUB

    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"checksums do not match"* ]]
}

@test "aahp_checksum fails instead of returning an empty digest" {
    # When the checksum tool produces nothing, returning success with "sha256:"
    # and nothing after it sends the operator to the wrong fix: regenerating
    # the manifest bakes the empty digest in, after which the broken toolchain
    # reports a clean handoff set forever.
    run bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'
                 sha256sum() { :; }
                 shasum() { :; }
                 aahp_checksum '$TEST_TMPDIR/.ai/handoff/STATUS.md'"
    [ "$status" -ne 0 ]
    [[ "$output" != "sha256:" ]]
    [[ "$output" == *"Could not compute a checksum"* ]]
}

# --- Messages: concrete commands, the failing layer, its own remedy ---------
#
# `/handoff` is not an AAHP command (README 9.1 lists none), and one footer line
# ("refresh STATUS.md + MANIFEST.json") was printed whatever failed, including
# failures that regenerating the manifest does not fix or actively hides.

@test "messages: a drift failure names the concrete command and Layer 2, never /handoff" {
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" != *"Run /handoff"* ]]
    [[ "$output" != *"/handoff to"* ]]
    [[ "$output" == *"aahp manifest"* ]]
    [[ "$output" == *"Failing: Layer 2 (content drift)"* ]]
    [[ "$output" == *"Layer 2 fix: Describe the change in .ai/handoff/STATUS.md"* ]]
    [[ "$output" != *"Layer 1 fix"* ]]
    [[ "$output" != *"Layer 4 fix"* ]]
}

@test "messages: a checksum mismatch says to inspect git diff BEFORE regenerating" {
    # Regenerating the manifest re-baselines whatever changed. For an honest
    # edit that is the fix; for tampering it is the cover-up.
    printf '\nunmanaged edit\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"Inspect the change BEFORE regenerating: git diff -- .ai/handoff"* ]]
    [[ "$output" == *"re-baselines whatever changed, including tampering"* ]]
    [[ "$output" == *"Failing: Layer 1 (MANIFEST integrity)"* ]]
    [[ "$output" == *"Layer 1 fix: A handoff file changed without its manifest. Inspect git diff -- .ai/handoff FIRST"* ]]
    [[ "$output" != *"Layer 2 fix"* ]]
    [[ "$output" != *"Run /handoff"* ]]
}

@test "messages: the vendored manifest script is named when it is present" {
    mkdir -p "$TEST_TMPDIR/scripts"
    cp "$SCRIPTS_DIR/aahp-manifest.sh" "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/scripts/"
    commit_with_handoff "vendor the manifest script"
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    git -C "$TEST_TMPDIR" add feature.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"bash scripts/aahp-manifest.sh ."* ]]
}

# --- Argument handling ---------------------------------------

@test "rejects an invalid --level" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid --level"* ]]
}

@test "rejects --level without a value" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level
    [ "$status" -eq 1 ]
    [[ "$output" == *"--level requires a value"* ]]
    [[ "$output" != *"AAHP Verify"* ]]
}

@test "rejects --base without a SHA" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a SHA"* ]]
    [[ "$output" != *"AAHP Verify"* ]]
}

@test "rejects an unknown option with the usage line" {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --bogus"* ]]
    [[ "$output" == *"Usage: verify-handoff.sh"* ]]
}

@test "errors when no handoff directory exists" {
    EMPTY="$(_make_tmpdir)"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$EMPTY" --level full
    rm -rf "$EMPTY"
    [ "$status" -eq 1 ]
    [[ "$output" == *".ai/handoff not found"* ]]
    [[ "$output" != *"AAHP Verify"* ]]
}

# --- Layer 3: commit-pointer freshness (warn, never blocks) --

@test "Layer 3 is OK when only .ai/handoff/ changed since the manifest commit" {
    # The documented flow, which is exactly the fixture: commit, regenerate the
    # manifest (it records that commit), commit the handoff. A manifest cannot
    # record the commit that contains it, so "pointer == HEAD" never holds after
    # a committed handoff and this layer used to warn on every run.
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"is an ancestor of HEAD"*"and everything since it changed only .ai/handoff/."* ]]
    [[ "$output" != *"is behind HEAD"* ]]
}

@test "Layer 3 WARNS when code changed since the manifest commit" {
    # The manifest is regenerated BEFORE the commit that adds feature.js, so it
    # records the previous commit and the code at HEAD is newer than it.
    echo "console.log('x')" > "$TEST_TMPDIR/feature.js"
    commit_with_handoff "code after the pointer"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"is behind HEAD"*"1 file(s) outside .ai/handoff/ changed since"* ]]
    [[ "$output" != *"changed only .ai/handoff/"* ]]
}

@test "Layer 3 WARNS (never fails) when the manifest commit is not an ancestor of HEAD" {
    # Simulate a squash-merge / rebase-merge: the manifest records a commit that
    # is not in HEAD's history (an orphaned root commit). Layers 1-2 still pass,
    # so the gate must WARN and still succeed rather than hard-fail.
    local orphan orphan_short mfile
    mfile="$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    orphan=$(git -C "$TEST_TMPDIR" commit-tree "$(git -C "$TEST_TMPDIR" rev-parse 'HEAD^{tree}')" -m orphan)
    orphan_short=$(git -C "$TEST_TMPDIR" rev-parse --short "$orphan")
    node -e 'const fs=require("fs");const p=process.argv[1];const c=process.argv[2];const m=JSON.parse(fs.readFileSync(p,"utf8"));m.last_session.commit=c;fs.writeFileSync(p,JSON.stringify(m,null,2)+"\n");' "$mfile" "$orphan_short"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not an ancestor of HEAD"* ]]
    [[ "$output" == *"squash-merge or rebase-merge"* ]]
    [[ "$output" == *"aahp verify passed"* ]]
}

@test "Layer 3 never hands a non-SHA pointer to git" {
    # last_session.commit is handoff DATA. An option-shaped value must be
    # reported, not passed to git rev-parse.
    local mfile="$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    node -e 'const fs=require("fs");const p=process.argv[1];const m=JSON.parse(fs.readFileSync(p,"utf8"));m.last_session.commit="--output=pwned";fs.writeFileSync(p,JSON.stringify(m,null,2)+"\n");' "$mfile"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [[ "$output" == *"is not a commit in this repository"* ]]
    [ ! -e "$TEST_TMPDIR/pwned" ]
}

# --- Layer 4: TRUST-TTL, advisory by default -----------------

@test "reports expired verified trust rows as a warning (non-blocking)" {
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Stale claim | verified | 2026-01-01 | tester | 7d | 2026-01-08 | should be expired |
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    # Expired trust is advisory: it warns but does not fail the gate on its own.
    [ "$status" -eq 0 ]
    [[ "$output" == *"'verified' trust entr(ies) expired"* ]]
    [[ "$output" == *"Stale claim"* ]]
    # The count carries its denominator, so "1" is readable as 1 of 1 rather
    # than as a bare number over an unknown register size.
    [[ "$output" == *"1 of 1"* ]]
    [[ "$output" == *"aahp verify passed"* ]]
}

# --- Layer 4 must not report a clean register it could not read --------------
#
# The old reader printed nothing both when nothing was expired and when not one
# row was parsed, and this layer called both of them clean. A real, populated
# register with an Expires column and no Status column is such a table: that
# reader saw zero decidable rows in it, so a row past its expiry was reported
# as clean.

@test "Layer 4: a trust table with no Status column is NOT EVALUATED, not clean" {
    write_trust <<'EOF'
# Trust Register

## Verified Properties

| Property | Value | Verified | TTL | Expires | Provenance |
|----------|-------|----------|-----|---------|------------|
| Test count | 1953 passing | 2026-01-01 | 3 days | 2026-01-04 | tool_verified |
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [[ "$output" == *"TTL was NOT evaluated"* ]]
    [[ "$output" == *"this is not 'no expired entries'"* ]]
    [[ "$output" == *"Status"* ]]
    [[ "$output" != *"No expired 'verified' trust entries"* ]]
}

@test "Layer 4: a TRUST.md with no table at all is NOT EVALUATED, not clean" {
    write_trust <<'EOF'
# Trust and Scope Boundaries

## Agents May

- Read and write files in this project

## Agents Must Not

- Publish releases without approval
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [[ "$output" == *"no trust table this reader recognises"* ]]
    [[ "$output" == *"TTL was NOT evaluated"* ]]
    [[ "$output" != *"No expired 'verified' trust entries"* ]]
}

@test "Layer 4: a readable register with nothing expired still reports clean, with a count and a census" {
    # The CONTROL. Without it the two tests above would be satisfied by a Layer 4
    # that had simply stopped saying anything is clean. The setup register has
    # one verified row expiring in 2099.
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [[ "$output" == *"No expired 'verified' trust entries (1 checked)"* ]]
    [[ "$output" == *"Census: 1 trust row(s) read: 1 verified (0 check-backed, 1 dated, 0 with neither), 0 assumed, 0 untested, 0 other."* ]]
    [[ "$output" != *"TTL was NOT evaluated"* ]]
}

@test "Layer 4: stays advisory - an unreadable register does not fail the gate" {
    write_trust <<'EOF'
# Trust Register

no table here
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"TTL was NOT evaluated"* ]]
}

# --- Layer 4 can fail, but only where a repository asked for it -------------
#
# Making it blocking for everyone is the wrong fix. A register whose rows have
# mostly expired already would turn a repository red for a file its pull
# requests never touch. Hence opt-in, and hence pairs of tests: one proves it can fail,
# the other proves the default did not move.

@test "Layer 4: trustTtl.enforce makes a row expired past the grace period BLOCKING, and says so" {
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Stale claim | verified | 2026-01-01 | tester | 7d | 2026-01-08 | should be expired |
EOF
    write_config <<'EOF'
{
  "trustTtl": { "enforce": true }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    [[ "$output" == *"Stale claim"* ]]
    # The reason must be the trust register, not some other layer that happens to
    # be red in the same run. Without this the test would pass for any failure.
    [[ "$output" == *"'verified' trust entr(ies) expired more than 14 day(s) ago and trustTtl.enforce is on"* ]]
    # The footer names Layer 4 and ITS remedy. Regenerating the manifest does not
    # clear an expired register, so the old generic line sent people the wrong way.
    [[ "$output" == *"Failing: Layer 4 (TRUST-TTL)"* ]]
    [[ "$output" == *"Layer 4 fix: Re-verify the listed TRUST.md rows"* ]]
    [[ "$output" != *"Layer 2 fix"* ]]
    [[ "$output" != *"refresh STATUS.md + MANIFEST.json"* ]]
}

@test "Layer 4: with enforce false the SAME register only warns" {
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Stale claim | verified | 2026-01-01 | tester | 7d | 2026-01-08 | should be expired |
EOF
    write_config <<'EOF'
{
  "trustTtl": { "enforce": false }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"'verified' trust entr(ies) expired"* ]]
    [[ "$output" != *"trustTtl.enforce is on"* ]]
}

@test "Layer 4: under enforcement an UNREADABLE register fails, it is not clean" {
    write_trust <<'EOF'
# Trust Register

| Property | Value | Verified | TTL | Expires |
|----------|-------|----------|-----|---------|
| Stale claim | yes | 2026-01-01 | 7d | 2026-01-08 |
EOF
    write_config <<'EOF'
{
  "trustTtl": { "enforce": true }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    # The advisory branch prints "TTL was NOT evaluated" as well, so asserting
    # that alone would pass with enforcement deleted. Assert the wording only the
    # failing branch can produce.
    [[ "$output" == *"trustTtl.enforce is on and TTL was NOT evaluated"* ]]
    [[ "$output" != *"No expired 'verified' trust entries"* ]]
}

@test "Layer 4: under enforcement an ALL-ASSUMED register fails, it is not a silent green" {
    # Downgrading every row to assumed must not be a quieter way to switch
    # enforcement off than editing the reviewed config.
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|---------------|-------|-----|---------|-------|-------|
| Build passes | assumed | 2026-01-01 | tester | 7d | 2026-01-08 | - | downgraded |
| Tests pass | untested | - | - | - | - | - | |
EOF
    write_config <<'EOF'
{
  "trustTtl": { "enforce": true }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    [[ "$output" == *"none could be judged"* ]]
    [[ "$output" == *"trustTtl.enforce is on and TTL was NOT evaluated"* ]]
    [[ "$output" == *"Census: 2 trust row(s) read: 0 verified"*"1 assumed, 1 untested"* ]]
}

@test "Layer 4: an unparseable config fails rather than defaulting to not-enforcing" {
    # Fail closed. A required gate must not read a broken policy file as
    # permission to stop checking, or corrupting the config becomes the cheapest
    # way to disable it.
    write_config <<'EOF'
{ "trustTtl": { "enforce": true },
EOF
    commit_with_handoff "config"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    [[ "$output" == *"trustTtl configuration could not be read"* ]]
}

@test "Layer 4: a duplicated trustTtl key is refused, not silently resolved" {
    # Every JSON parser here keeps the LAST duplicate key, so a reviewer reading
    # the first one can be looking at a value that never takes effect. The reader
    # refuses the file instead of picking a winner.
    write_config <<'EOF'
{
  "trustTtl": { "enforce": true },
  "trustTtl": { "enforce": false }
}
EOF
    commit_with_handoff "config"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    # Layer 2's handoffImpact parser refuses duplicate keys as well, so the
    # assertion is pinned to Layer 4's own line: without that, this test stays
    # green with the Layer 4 reader's duplicate scan deleted (measured).
    [[ "$output" == *"trustTtl configuration could not be read: aahp.config.json: duplicate JSON object key: trustTtl"* ]]
}

@test "Layer 4: a duplicated enforce key INSIDE trustTtl is refused too" {
    # The earlier guard counted "trustTtl" in the raw text and could not see
    # this shape, which every parser resolves to the last value (false).
    write_config <<'EOF'
{ "trustTtl": { "enforce": true, "enforce": false } }
EOF
    commit_with_handoff "config"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -ne 0 ]
    [[ "$output" == *"trustTtl configuration could not be read: aahp.config.json: duplicate JSON object key: enforce"* ]]
}

# --- Layer 4: grace period for judgment rows -----------------
#
# On 2026-09-22 a required check turned red on every pull request with no code
# change, because two dated rows expired and the workflow has no schedule to
# warn first. A judgment row now WARNS from its expiry date and blocks under
# enforce only after trustTtl.graceDays (default 14).

@test "Layer 4 grace: a row expired INSIDE the grace period warns under enforce" {
    local expired
    expired="$(days_ago 3)"
    write_trust <<EOF
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Recently lapsed | verified | 2026-01-01 | tester | 7d | $expired | three days over |
EOF
    write_config <<'EOF'
{ "trustTtl": { "enforce": true } }
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"expired within the 14-day grace period"* ]]
    [[ "$output" == *"Recently lapsed (expired $expired, 3 day(s) ago; grace ends in 11 day(s))"* ]]
    [[ "$output" == *"aahp verify passed"* ]]
}

@test "Layer 4 grace: the same row one day past the grace period blocks under enforce" {
    local expired
    expired="$(days_ago 15)"
    write_trust <<EOF
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Long lapsed | verified | 2026-01-01 | tester | 7d | $expired | fifteen days over |
EOF
    write_config <<'EOF'
{ "trustTtl": { "enforce": true } }
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"expired more than 14 day(s) ago and trustTtl.enforce is on"* ]]
    [[ "$output" == *"Long lapsed (expired $expired, 15 day(s) ago)"* ]]
}

@test "Layer 4 grace: graceDays 0 restores block-on-expiry" {
    local expired
    expired="$(days_ago 1)"
    write_trust <<EOF
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Just lapsed | verified | 2026-01-01 | tester | 7d | $expired | one day over |
EOF
    write_config <<'EOF'
{ "trustTtl": { "enforce": true, "graceDays": 0 } }
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"expired more than 0 day(s) ago and trustTtl.enforce is on"* ]]
}

# --- Layer 4: executable claims (check-backed rows) ----------

@test "Layer 4 checks: a check-backed row is judged by its check, not by its date" {
    # The row's date is long past, and under enforce a date-judged row would
    # block. The built-in license check re-proves the claim on this run.
    write_mit_license_fixture "MIT"
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|---------------|-------|-----|---------|-------|-------|
| LICENSE matches declared license | verified | 2026-01-01 | tester | 30d | 2026-01-08 | `license-matches` | re-proven each run |
| Checksums match file contents | verified | 2026-01-01 | tester | 3d | 2026-01-04 | manifest-integrity | Layer 1 |
EOF
    write_config <<'EOF'
{ "trustTtl": { "enforce": true } }
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 check-backed 'verified' row(s) re-proven by their check(s): license-matches manifest-integrity."* ]]
    [[ "$output" == *"(2 check-backed, 0 dated, 0 with neither)"* ]]
    [[ "$output" != *"entr(ies) expired"* ]]
    [[ "$output" == *"No expired 'verified' trust entries (2 checked)"* ]]
}

@test "Layer 4 checks: a failing check blocks under enforce even when the date is fresh" {
    # package.json says Apache-2.0, the LICENSE file is MIT. The row's date runs
    # to 2099, so only the check can catch this.
    write_mit_license_fixture "Apache-2.0"
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|---------------|-------|-----|---------|-------|-------|
| LICENSE matches declared license | verified | 2026-01-01 | tester | 30d | 2099-01-01 | license-matches | |
EOF
    write_config <<'EOF'
{ "trustTtl": { "enforce": true } }
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 of 1 check-backed 'verified' row(s) failed their check and trustTtl.enforce is on"* ]]
    [[ "$output" == *"package.json says Apache-2.0 but LICENSE does not contain"* ]]
    [[ "$output" == *"Failing: Layer 4 (TRUST-TTL)"* ]]
}

@test "Layer 4 checks: a config-declared check runs its reviewed argv, without a shell" {
    printf 'tracked\n' > "$TEST_TMPDIR/fixture.txt"
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|---------------|-------|-----|---------|-------|-------|
| Fixture file is tracked | verified | 2026-01-01 | tester | 7d | 2026-01-08 | fixture-tracked | |
EOF
    write_config <<'EOF'
{
  "trustTtl": {
    "enforce": true,
    "checks": [
      {
        "id": "fixture-tracked",
        "run": ["git", "ls-files", "--error-unmatch", "--", "fixture.txt"],
        "reason": "The fixture file must stay tracked."
      }
    ]
  }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 0 ]
    [[ "$output" == *"re-proven by their check(s): fixture-tracked."* ]]

    # Same row, same config: once the fact stops being true the claim fails,
    # whatever its date says.
    git -C "$TEST_TMPDIR" rm -q fixture.txt
    commit_with_handoff "untrack the fixture"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fixture file is tracked [check fixture-tracked]: exited 1"* ]]
}

@test "Layer 4 SECURITY: nothing written into TRUST.md is ever executed" {
    # TRUST.md is agent-written data. A Check cell is a lookup key into the
    # built-ins and the reviewed config, never a command. A declared argv is
    # not handed to a shell either, so its metacharacters stay literal.
    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Check | Notes |
|----------|--------|---------------|-------|-----|---------|-------|-------|
| Injected command | verified | 2026-01-01 | agent | 7d | 2099-01-01 | touch pwned-1 | |
| Injected substitution | verified | 2026-01-01 | agent | 7d | 2099-01-01 | $(touch pwned-2) | |
| Injected sequence | verified | 2026-01-01 | agent | 7d | 2099-01-01 | x; touch pwned-3 | |
| Plausible id, undeclared | verified | 2026-01-01 | agent | 7d | 2099-01-01 | touch | |
| Declared, with metacharacters | verified | 2026-01-01 | agent | 7d | 2099-01-01 | literal-args | |
EOF
    write_config <<'EOF'
{
  "trustTtl": {
    "enforce": true,
    "checks": [
      {
        "id": "literal-args",
        "run": ["git", "ls-files", "--error-unmatch", "--", "x; touch pwned-4", "$(touch pwned-5)"],
        "reason": "Proves argv reaches git verbatim."
      }
    ]
  }
}
EOF
    commit_with_handoff "trust"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [ "$status" -eq 1 ]
    local n
    for n in 1 2 3 4 5; do
        [ ! -e "$TEST_TMPDIR/pwned-$n" ] || { echo "pwned-$n was created"; false; }
    done
    [[ "$output" == *"5 of 5 check-backed 'verified' row(s) failed their check"* ]]
    [[ "$output" == *"not a valid check id"*"nothing was run"* ]]
    [[ "$output" == *"Plausible id, undeclared [check touch]: not a built-in check"*"nothing was run"* ]]
}

@test "Layer 4 policy: both parsers refuse invalid trustTtl shapes and agree on a valid one" {
    local pylib value
    pylib="$(python_only_lib)"
    local cases=(
        '{"trustTtl":{"graceDays":-1}}'
        '{"trustTtl":{"graceDays":366}}'
        '{"trustTtl":{"graceDays":"14"}}'
        '{"trustTtl":{"graceDays":1.5}}'
        '{"trustTtl":{"graceDays":true}}'
        '{"trustTtl":{"enforce":"yes"}}'
        '{"trustTtl":{"unknown":1}}'
        '{"trustTtl":[]}'
        '{"trustTtl":{"checks":{}}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git"]}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git"],"reason":"r","extra":1}]}}'
        '{"trustTtl":{"checks":[{"id":"license-matches","run":["git"],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"Bad_Id","run":["git"],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":[],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":"git status","reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":[""],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git",""],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git"],"reason":"..."}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git"],"reason":"r"},{"id":"a","run":["git"],"reason":"r"}]}}'
        '{"trustTtl":{"enforce":true,"enforce":false}}'
        '[]'
    )
    for value in "${cases[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/aahp.config.json"
        run bash -c 'source "$1"; aahp_trust_policy "$2"' _ "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
        [ "$status" -ne 0 ] || { echo "Node accepted: $value"; false; }
        run bash -c 'source "$1"; aahp_trust_policy "$2"' _ "$pylib" "$TEST_TMPDIR/aahp.config.json"
        [ "$status" -ne 0 ] || { echo "Python accepted: $value"; false; }
    done

    printf '%s\n' '{"trustTtl":{"enforce":true,"graceDays":0,"checks":[{"id":"a-b","run":["git","status"],"reason":"Reviewed."}]}}' \
        > "$TEST_TMPDIR/aahp.config.json"
    local expected=$'enforce\t1\ngraceDays\t0\ncheck\ta-b'
    run bash -c 'source "$1"; aahp_trust_policy "$2"' _ "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    run bash -c 'source "$1"; aahp_trust_policy "$2"' _ "$pylib" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]

    # Absent config: advisory, with the documented default grace.
    rm -f "$TEST_TMPDIR/aahp.config.json"
    run bash -c 'source "$1"; aahp_trust_policy "$2"' _ "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = $'enforce\t0\ngraceDays\t14' ]
}

@test "Layer 4 portability: expiry dates are read without regex intervals (old mawk)" {
    # mawk before 1.3.4-20200120 treats `{4}` as literal braces. This stub awk
    # reproduces exactly that on any modern awk, and proves it does before it
    # is trusted: the old interval pattern must stop matching under it.
    local stub="$TEST_TMPDIR/old-awk"
    mkdir -p "$stub"
    cat > "$stub/awk" <<'STUB'
#!/usr/bin/env bash
out=()
seen_prog=0
expect_val=0
for a in "$@"; do
    if [ "$expect_val" -eq 1 ]; then out+=("$a"); expect_val=0; continue; fi
    if [ "$seen_prog" -eq 0 ]; then
        case "$a" in
            -v|-F|-f) out+=("$a"); expect_val=1; continue ;;
            -v?*|-F?*) out+=("$a"); continue ;;
        esac
        a=$(printf '%s' "$a" | sed -E 's/[{]([0-9]+(,[0-9]*)?)[}]/[{]\1[}]/g')
        seen_prog=1
    fi
    out+=("$a")
done
exec "$AAHP_TEST_REAL_AWK" "${out[@]}"
STUB
    chmod +x "$stub/awk"
    local real_awk
    real_awk="$(command -v awk)"

    run env AAHP_TEST_REAL_AWK="$real_awk" PATH="$stub:$PATH" \
        bash -c 'echo 2026-01-08 | awk "/^[0-9]{4}-[0-9]{2}-[0-9]{2}\$/ { print \"interval\" }"; echo 2026-01-08 | awk "/^[0-9][0-9][0-9][0-9]-/ { print \"bracket\" }"'
    [ "$status" -eq 0 ]
    [ "$output" = "bracket" ]

    write_trust <<'EOF'
# Trust Register

| Property | Status | Last Verified | Agent | TTL | Expires | Notes |
|----------|--------|---------------|-------|-----|---------|-------|
| Stale claim | verified | 2026-01-01 | tester | 7d | 2026-01-08 | should be expired |
EOF
    commit_with_handoff "trust"

    run env AAHP_TEST_REAL_AWK="$real_awk" PATH="$stub:$PATH" \
        bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level full
    [[ "$output" == *"1 of 1 dated 'verified' trust entr(ies) expired"* ]]
    [[ "$output" == *"Stale claim (expired 2026-01-08"* ]]
    [[ "$output" != *"TTL was NOT evaluated"* ]]
}
