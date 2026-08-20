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
    CI_BASE="$(git -C "$TEST_TMPDIR" rev-parse HEAD~1)"
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
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not. Run /handoff."* ]]
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

    AAHP_SKIP_VERIFY=1 run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
}

# ─── Layer 1: checksum integrity ─────────────────────────────

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

# ─── Layer 1 must not fail open when it cannot check ─────────

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
    [ -n "$py" ] || skip "no working python interpreter"
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
    [ -n "$py" ] || skip "no working python interpreter"
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
    [ -n "$py" ] || skip "no working python interpreter"
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

# ─── Layer 3: commit-pointer freshness (warn, never blocks) ──

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
