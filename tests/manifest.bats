#!/usr/bin/env bats
# manifest.bats -Tests for scripts/aahp-manifest.sh

bats_require_minimum_version 1.5.0

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

# --- Helper: detect a working python command -----------------
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

# --- Basic generation ----------------------------------------

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

# --- CLI flag: --phase ---------------------------------------

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

# --- CLI flag: --context -------------------------------------

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

# --- Task preservation on regeneration -----------------------
# These three used to `skip` exactly when the field was NOT preserved, on the
# theory that node could not resolve the tmpdir path on Windows. That turned
# the regression they exist for into a green skip on every platform. The path
# is handed to node through MSYS argument conversion, so a platform that cannot
# resolve it is a defect to fix, not a reason to pass.

# Read one value out of MANIFEST.json with node, as JSON, so an assertion sees
# the parsed value and its type rather than a substring of the text. The path
# separator is "/" because handoff file names contain dots (files/STATUS.md/updated).
_manifest_value() {
    node -e '
        const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        const v = process.argv[2].split("/").reduce((o, k) => (o == null ? o : o[k]), m);
        process.stdout.write(JSON.stringify(v === undefined ? null : v));
    ' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$1"
}

@test "preserves existing tasks field on regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    run _manifest_value tasks
    [ "$status" -eq 0 ]
    [[ "$output" == *'"T-001"'* ]]
    [[ "$output" == *'"T-002"'* ]]
    [[ "$output" == *'"Implement feature X"'* ]]
}

@test "preserves next_task_id on regeneration" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]

    # A number, not the string "3" (ADR-009).
    run _manifest_value next_task_id
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
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

    run _manifest_value project
    [ "$status" -eq 0 ]
    [ "$output" = '"TestProject"' ]
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

# --- Project name comes from repository identity, not from cwd ---
#
# An agent working in a `git worktree` often has a directory named after the
# BRANCH, and CI unpacks into a workdir named after the job. A
# cwd-derived project name therefore rewrites MANIFEST.json's "project" to the
# checkout's name on every regeneration, and the rewrite is invisible unless
# somebody re-reads the file afterwards, so such a value can reach a main
# branch unnoticed. Each test below runs the generator from a
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

@test "without node, regeneration refuses and leaves MANIFEST.json byte-identical" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks
    git -C "$TEST_TMPDIR" remote add origin https://github.com/homeofe/aahp-consumer.git
    cp "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/manifest.before"

    # Where node is missing (a stripped hook PATH, a slim CI image) the old
    # generator skipped reading the existing manifest SILENTLY and rewrote it
    # without tasks, next_task_id, cross_repo_ref and the recorded project name,
    # exit 0. Node is now a hard requirement: no node means no write at all.
    # Simulate a missing node through BASH_ENV instead of deleting PATH entries.
    # On many Linux systems node, git, bash, sed, and coreutils all live in
    # /usr/bin, so removing every directory that contains node also removes the
    # tools the manifest generator legitimately needs. The child shell below
    # makes both the guard and an accidental direct invocation fail while
    # preserving the real platform PATH.
    cat > "$TEST_TMPDIR/no-node.bash" <<'EOF'
node() { return 127; }
command() {
    if [ "${1:-}" = "-v" ] && [ "${2:-}" = "node" ]; then return 1; fi
    builtin command "$@"
}
EOF

    run env BASH_ENV="$TEST_TMPDIR/no-node.bash" bash -c 'command -v node'
    [ "$status" -ne 0 ]
    run -127 env BASH_ENV="$TEST_TMPDIR/no-node.bash" bash -c 'node --version'
    [ "$status" -eq 127 ]
    run env BASH_ENV="$TEST_TMPDIR/no-node.bash" git --version
    [ "$status" -eq 0 ]
    run env BASH_ENV="$TEST_TMPDIR/no-node.bash" bash -c 'exit 7'
    [ "$status" -eq 7 ]

    run env BASH_ENV="$TEST_TMPDIR/no-node.bash" bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Node.js was not found"* ]]
    [[ "$output" == *"nothing was written"* ]]
    # --force cannot talk it into writing either: there is nothing to write with.
    run env BASH_ENV="$TEST_TMPDIR/no-node.bash" bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --force
    [ "$status" -eq 1 ]
    cmp "$TEST_TMPDIR/manifest.before" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

# --- Refuse to drop data it cannot carry over (R5) ---

@test "an unparseable MANIFEST.json is not overwritten without --force" {
    create_status_md
    create_next_actions_md
    printf '{ "tasks": { "T-001": { "title": "keep me", ' > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    cp "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/manifest.before"

    # The old generator printed a warning on stderr, dropped tasks and the
    # rest, and exited 0 - the half-written task registry was simply gone.
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to overwrite"* ]]
    [[ "$output" == *"not valid JSON"* ]]
    cmp "$TEST_TMPDIR/manifest.before" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"

    # An explicit --force regenerates, says what it dropped, and writes JSON.
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: --force"* ]]
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

@test "a field that cannot be carried over blocks regeneration without --force" {
    create_status_md
    create_manifest_json
    local manifest="$TEST_TMPDIR/.ai/handoff/MANIFEST.json"

    # A next_task_id that is not a whole number used to be dropped silently.
    node -e '
        const fs = require("fs"); const p = process.argv[1];
        const m = JSON.parse(fs.readFileSync(p, "utf8"));
        m.next_task_id = "seven"; m.handoff_notes = "agent-added";
        fs.writeFileSync(p, JSON.stringify(m, null, 2));
    ' "$manifest"
    cp "$manifest" "$TEST_TMPDIR/manifest.before"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *'next_task_id "seven" is not a whole number'* ]]
    [[ "$output" == *"handoff_notes"* ]]
    cmp "$TEST_TMPDIR/manifest.before" "$manifest"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --force
    [ "$status" -eq 0 ]
    run _manifest_value next_task_id
    [ "$output" = "null" ]
    run _manifest_value handoff_notes
    [ "$output" = "null" ]
    # The recorded project name is still carried: only what could not be is dropped.
    run _manifest_value project
    [ "$output" = '"TestProject"' ]
}

# --- The document is built by JSON.stringify, not by heredoc (R3/R10) ---

@test "hostile input still yields valid JSON and valid UTF-8, and regenerates cleanly" {
    # Each of these wrote an unparseable or mis-encoded MANIFEST.json with exit 0:
    # a TAB in the first content line, a quote and a backslash in --agent, and a
    # multi-byte character straddling the 150-character summary cut and the
    # 500-character quick_context cut (both were byte-based `cut -c`).
    #
    # The generator clips at max - 3 code points and appends "...", so the
    # multi-byte run has to sit ACROSS that point, and the result is compared
    # exactly. A length check alone cannot see a wrong cut: it yields a string
    # that is still short enough and still decodes (a split U+00FC comes back as
    # U+00C3 plus a stray byte, a split surrogate pair as U+FFFD). Summary: the
    # 31-character prefix plus 101 'a' puts ten U+00FC at code points 133-142
    # but at bytes 133-152, across the 147 cut (catches a byte-based cut).
    # Context: 490 'b' puts ten U+1F680 at code points 491-500 but at UTF-16
    # units 491-510 and bytes 491-530, across the 497 cut (catches a byte-based
    # AND a UTF-16-unit cut). All non-ASCII bytes are generated here, so this
    # file stays ASCII.
    local pad101 pad490 uuml10 rocket10
    pad101="$(printf 'a%.0s' $(seq 1 101))"
    pad490="$(printf 'b%.0s' $(seq 1 490))"
    uuml10="$(printf '\303\274%.0s' $(seq 1 10))"
    rocket10="$(printf '\360\237\232\200%.0s' $(seq 1 10))"
    printf '# Status\n\nBuild\tis "green" and C:\\path\\x %s%s tail end of the line\n' "$pad101" "$uuml10" \
        > "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_next_actions_md

    local run_no
    for run_no in 1 2; do
        run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet \
            --agent 'agent "quoted" \ back' --context "${pad490}${rocket10} end"
        [ "$status" -eq 0 ]
        run node -e '
            const buf = require("fs").readFileSync(process.argv[1]);
            const text = new TextDecoder("utf-8", { fatal: true }).decode(buf);
            const m = JSON.parse(text);
            const cps = (s) => Array.from(s).length;
            if (m.last_session.agent !== "agent \"quoted\" \\ back") throw new Error("agent: " + m.last_session.agent);
            const s = m.files["STATUS.md"].summary;
            if (/\t/.test(s)) throw new Error("tab survived in summary");
            if (!s.includes("\"green\"") || !s.includes("C:\\path")) throw new Error("summary: " + s);
            if (cps(s) > 200) throw new Error("summary too long: " + cps(s));
            if (cps(m.quick_context) > 500) throw new Error("quick_context too long: " + cps(m.quick_context));
            const wantSummary = "Build is \"green\" and C:\\path\\x " + "a".repeat(101) + "\u00fc".repeat(10) + "...";
            if (s !== wantSummary) throw new Error("summary cut is not by code point: " + JSON.stringify(s));
            const wantContext = "b".repeat(490) + "\u{1F680}".repeat(7) + "...";
            if (m.quick_context !== wantContext) throw new Error("quick_context cut is not by code point: " + JSON.stringify(m.quick_context.slice(485)));
            console.log("VALID");
        ' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
        [ "$status" -eq 0 ]
        [ "$output" = "VALID" ]
    done
}

@test "quick_context is escaped once, not twice" {
    create_next_actions_md
    printf '# Status\n\nThe "fast" path now handles a C:\\temp path correctly.\n' > "$TEST_TMPDIR/.ai/handoff/STATUS.md"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run node -e '
        const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(m.quick_context);
    ' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    [[ "$output" == 'The "fast" path now handles a C:\temp path correctly.'* ]]
    [[ "$output" != *'\"'* ]]

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --context 'say "hi" \ now'
    [ "$status" -eq 0 ]
    run _manifest_value quick_context
    [ "$output" = '"say \"hi\" \\ now"' ]
}

@test "--duration must be a whole number of minutes" {
    create_status_md
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --duration soon
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid duration"* ]]
    [ ! -f "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" ]

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --duration 45
    [ "$status" -eq 0 ]
    run _manifest_value last_session/duration_minutes
    [ "$output" = "45" ]
}

# --- A failure mid-generation never writes (R4) ---

@test "a checksum that cannot be computed aborts and leaves MANIFEST.json untouched" {
    create_status_md
    create_next_actions_md
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    cp "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/manifest.before"

    # The old path ran aahp_checksum inside $(...) and carried on, so an empty
    # digest became `"checksum": ""` and the run still printed "checksums
    # current" with exit 0. Simulate a hash that yields nothing.
    cat > "$TEST_TMPDIR/empty-digest.cjs" <<'CJS'
const crypto = require('crypto');
const real = crypto.createHash;
crypto.createHash = function (...args) {
  const hash = real.apply(this, args);
  hash.digest = () => '';
  return hash;
};
CJS
    echo "changed" >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    NODE_OPTIONS="--require $TEST_TMPDIR/empty-digest.cjs" run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not compute a SHA-256 checksum for STATUS.md"* ]]
    [[ "$output" != *"checksums current"* ]]
    cmp "$TEST_TMPDIR/manifest.before" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
}

@test "generator checksums agree with aahp_checksum on a CRLF file" {
    # CONSTITUTION rule 4: whole-file SHA-256 with CR stripped. The generator now
    # hashes in node and Layer 1 hashes with aahp_checksum; the two must agree.
    printf '# Status\r\n\r\nLine one with CRLF.\r\n' > "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    expected="$(bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'; aahp_checksum '$TEST_TMPDIR/.ai/handoff/STATUS.md'")"
    run _manifest_value files/STATUS.md
    [[ "$output" == *"\"checksum\":\"$expected\""* ]]
}

# --- files.*.updated survives a checkout ---

@test "updated keeps the recorded date while the content is unchanged" {
    create_status_md
    create_next_actions_md
    touch -t 200101010000 "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run _manifest_value files/STATUS.md/updated
    first="$output"
    [[ "$first" == '"2000-12-3'* || "$first" == '"2001-01-01'* ]]

    # A fresh checkout gives every file a new mtime with identical bytes. That
    # used to re-date every unchanged file on the next regeneration.
    touch -t 203001010000 "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run _manifest_value files/STATUS.md/updated
    [ "$output" = "$first" ]

    # A real change takes the file's own modification time.
    echo "new line" >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run _manifest_value files/STATUS.md/updated
    [ "$output" != "$first" ]
    [[ "$output" != '"2030-'* ]]
}

# --- Summaries and token budget (D5) ---

@test "summaries skip tables, JSON punctuation, bookkeeping labels and comments" {
    local h="$TEST_TMPDIR/.ai/handoff"
    cat > "$h/TRUST.md" <<'EOF'
# Trust Register

> Tracks verification status.

## Confidence Levels

| Level | Meaning |
|-------|---------|
| verified | An agent ran it |

Each claim here carries a provenance token. More text follows.
EOF
    cat > "$h/STATUS.md" <<'EOF'
# Status

<!--
  generated block, not content
-->
Last updated: 2026-09-28
**Agent:** codex
**Phase:** implementation

Auth service deployed; CORS fix is next.
EOF
    cat > "$h/LOG.md" <<'EOF'
# Journal

> Append-only.

## [2026-09-28] codex: auth middleware landed

**Agent:** codex

- did things
EOF
    cat > "$h/DASHBOARD.md" <<'EOF'
# Dashboard

| Service | State |
|---------|-------|
| api | green |
EOF
    printf '{\n  "version": 1,\n  "entries": []\n}\n' > "$h/pii-allowlist.json"

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run _manifest_value files/TRUST.md/summary
    [ "$output" = '"Each claim here carries a provenance token."' ]
    run _manifest_value files/STATUS.md/summary
    [ "$output" = '"Auth service deployed; CORS fix is next."' ]
    run _manifest_value files/LOG.md/summary
    [ "$output" = '"Latest entry: [2026-09-28] codex: auth middleware landed"' ]
    # A file that is only a table still gets a summary, not "(no summary available)".
    run _manifest_value files/DASHBOARD.md/summary
    [ "$output" = '"Table with columns: Service, State"' ]
    run _manifest_value files/pii-allowlist.json/summary
    [ "$output" = '"PII allowlist: 0 entries."' ]
}

@test "manifest_only is the estimate of the generated file itself" {
    create_status_md
    create_next_actions_md
    create_log_md
    create_manifest_with_tasks

    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    # Same estimator the generator documents: max(1.3 x words, UTF-8 bytes / 4),
    # CR stripped. It used to be the constant 85 whatever the file held.
    run node -e '
        const buf = require("fs").readFileSync(process.argv[1]);
        const lf = Buffer.from(buf.toString("latin1").replace(/\r/g, ""), "latin1");
        const words = (lf.toString("utf8").match(/\S+/g) || []).length;
        const est = Math.max(Math.ceil(words * 13 / 10), Math.ceil(lf.length / 4));
        const b = JSON.parse(buf.toString("utf8")).token_budget;
        if (b.manifest_only !== est) throw new Error("manifest_only " + b.manifest_only + " != estimate " + est);
        if (!(b.manifest_plus_core > b.manifest_only && b.full_read >= b.manifest_plus_core)) throw new Error(JSON.stringify(b));
        console.log("OK " + est);
    ' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK "* ]]
    [ "$output" != "OK 85" ]
}

# --- The shipped template round-trips through the schema (D2) ---

@test "aahp init then aahp manifest produces a schema-valid MANIFEST.json" {
    # templates/MANIFEST.json shipped example tasks with "created": "[ISO-8601]".
    # The generator carries tasks over verbatim, so every fresh adopter got a
    # manifest that fails the schema (format date-time) while verify and doctor
    # stayed green. Validated with CI's ajv validator; not a skip when ajv is
    # missing: it is a pinned devDependency, so the validator exits 2 on a
    # broken install and that fails here, instead of hiding the regression.
    run node "$AAHP_ROOT/bin/aahp.js" init "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    run node "$SCRIPTS_DIR/validate-json-schema.mjs" \
        "$AAHP_ROOT/schema/aahp-manifest.schema.json" \
        "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"MANIFEST.json valid"* ]]
}

# --- File indexing -------------------------------------------

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

# --- Error handling ------------------------------------------

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
