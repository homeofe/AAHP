#!/usr/bin/env bats
# handoff-impact.bats - Layer 2 reviewed exceptions and fail-closed base tests.

setup() {
    load test_helper
    setup
}

teardown() {
    teardown
}

write_impact_config() {
    local file="$1"
    local reason="${2:-Reviewed maintenance-only file.}"
    node -e '
const fs = require("fs");
const config = {handoffImpact:{nonImpactingModifiedFiles:[{file:process.argv[2],reason:process.argv[3]}]}};
fs.writeFileSync(process.argv[1], JSON.stringify(config, null, 2) + "\n");
' "$TEST_TMPDIR/aahp.config.json" "$file" "$reason"
}

parse_impact_config() {
    bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ \
        "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
}

make_python_fallback_lib() {
    local fallback_lib="$TEST_TMPDIR/fallback-lib.sh"
    cp "$SCRIPTS_DIR/_aahp-lib.sh" "$fallback_lib"
    sed '0,/if command -v node .*then/s//if false; then/' "$fallback_lib" > "$fallback_lib.tmp"
    mv "$fallback_lib.tmp" "$fallback_lib"
    printf '%s\n' "$fallback_lib"
}

parse_impact_config_with_lib() {
    bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ \
        "$1" "$TEST_TMPDIR/aahp.config.json"
}

prepare_gate_baseline() {
    create_full_handoff
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "seed handoff"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "manifest"
    CI_BASE="$(git -C "$TEST_TMPDIR" rev-parse HEAD~1)"
}

commit_reviewed_file() {
    local file="$1"
    mkdir -p "$(dirname "$TEST_TMPDIR/$file")"
    printf 'baseline\n' > "$TEST_TMPDIR/$file"
    write_impact_config "$file"
    git -C "$TEST_TMPDIR" add "$file" aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure reviewed file"
}

@test "config parser accepts one exact file and emits its trimmed reason" {
    write_impact_config "docs/maintenance.md" "  Reviewed maintenance-only file.  "
    run parse_impact_config
    [ "$status" -eq 0 ]
    [ "$output" = $'docs/maintenance.md\tReviewed maintenance-only file.' ]
}

@test "config parser rejects malformed shapes, unsafe paths, and ambiguous entries" {
    local cases=(
        '{'
        '[]'
        '{"handoffImpact":[]}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":{}}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[[]]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"   "}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"/tmp/a","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"C:/tmp/a","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"../a","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/*.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a?.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":".ai/handoff/STATUS.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"aahp.config.json","reason":"x"}]}}'
        '{"handoffImpact":{"unknown":[],"nonImpactingModifiedFiles":[]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[]},"handoffImpact":{"nonImpactingModifiedFiles":[]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","file":"docs/b.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"x","reason":"y"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"x"},{"file":"DOCS/A.MD","reason":"y"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a","reason":"x"},{"file":"docs/a.md","reason":"y"}]}}'
    )
    local value
    for value in "${cases[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/aahp.config.json"
        run parse_impact_config
        [ "$status" -ne 0 ]
    done
}

@test "Python fallback also rejects duplicate JSON keys" {
    local fallback_lib
    fallback_lib="$(make_python_fallback_lib)"
    printf '%s\n' '{"handoffImpact":{"nonImpactingModifiedFiles":[]},"handoffImpact":{"nonImpactingModifiedFiles":[]}}' \
        > "$TEST_TMPDIR/aahp.config.json"

    run bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ \
        "$fallback_lib" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"duplicate JSON object key: handoffImpact"* ]]
}

@test "Node and Python parsers reject non-standard constants and invisible reasons" {
    local fallback_lib value
    fallback_lib="$(make_python_fallback_lib)"
    local cases=(
        '{"handoffImpact":NaN}'
        '{"handoffImpact":Infinity}'
        '{"handoffImpact":-Infinity}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"\u200B"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"reviewed \u202E rationale"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"\uFEFF"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"..."}]}}'
    )
    for value in "${cases[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/aahp.config.json"

        run parse_impact_config
        [ "$status" -ne 0 ] || { echo "Node accepted invalid policy: $value"; false; }

        run parse_impact_config_with_lib "$fallback_lib"
        [ "$status" -ne 0 ] || { echo "Python accepted invalid policy: $value"; false; }
    done
}

@test "absent handoffImpact config preserves the original impacting behavior" {
    prepare_gate_baseline
    printf 'source\n' > "$TEST_TMPDIR/source.js"
    git -C "$TEST_TMPDIR" add source.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
}

@test "an exact M-only reviewed file passes and logs file plus reason" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    printf 'modified\n' >> "$TEST_TMPDIR/docs/maintenance.md"
    git -C "$TEST_TMPDIR" add docs/maintenance.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reviewed non-impacting modification: docs/maintenance.md"* ]]
    [[ "$output" == *"Reason: Reviewed maintenance-only file."* ]]
}

@test "a mixed reviewed modification and source change still triggers drift" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    printf 'modified\n' >> "$TEST_TMPDIR/docs/maintenance.md"
    printf 'source\n' > "$TEST_TMPDIR/source.js"
    git -C "$TEST_TMPDIR" add docs/maintenance.md source.js

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Reviewed non-impacting modification: docs/maintenance.md"* ]]
    [[ "$output" == *"A source.js"* ]]
}

@test "an untracked working-tree config cannot authorize a staged modification" {
    prepare_gate_baseline
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'baseline\n' > "$TEST_TMPDIR/docs/sensitive.md"
    git -C "$TEST_TMPDIR" add docs/sensitive.md
    git -C "$TEST_TMPDIR" commit -q -m "tracked source"
    printf 'modified\n' >> "$TEST_TMPDIR/docs/sensitive.md"
    git -C "$TEST_TMPDIR" add docs/sensitive.md
    write_impact_config "docs/sensitive.md"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"exists in the working tree but is not tracked in the index"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]
}

@test "an unstaged exception in a tracked config cannot authorize a staged modification" {
    prepare_gate_baseline
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'baseline\n' > "$TEST_TMPDIR/docs/sensitive.md"
    printf '{"handoffImpact":{"nonImpactingModifiedFiles":[]}}\n' > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add docs/sensitive.md aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "tracked source and policy"
    printf 'modified\n' >> "$TEST_TMPDIR/docs/sensitive.md"
    git -C "$TEST_TMPDIR" add docs/sensitive.md
    write_impact_config "docs/sensitive.md"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"aahp.config.json has unstaged changes"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]
}

@test "a configured added file remains impacting" {
    prepare_gate_baseline
    write_impact_config "docs/new.md"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure future file"
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'new\n' > "$TEST_TMPDIR/docs/new.md"
    git -C "$TEST_TMPDIR" add docs/new.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"A docs/new.md"* ]]
}

@test "a configured deleted file remains impacting" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    git -C "$TEST_TMPDIR" rm -q docs/maintenance.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"D docs/maintenance.md"* ]]
}

@test "a configured renamed file remains impacting" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    git -C "$TEST_TMPDIR" mv docs/maintenance.md docs/renamed.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"R100 docs/maintenance.md -> docs/renamed.md"* ]]
}

@test "a configured copied file remains impacting" {
    prepare_gate_baseline
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'same content\n' > "$TEST_TMPDIR/docs/source.md"
    write_impact_config "docs/copy.md"
    git -C "$TEST_TMPDIR" add docs/source.md aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure future copy"
    cp "$TEST_TMPDIR/docs/source.md" "$TEST_TMPDIR/docs/copy.md"
    git -C "$TEST_TMPDIR" add docs/copy.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"C100 docs/source.md -> docs/copy.md"* ]]
}

@test "a configured directory is rejected even when it contains tracked files" {
    prepare_gate_baseline
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'tracked\n' > "$TEST_TMPDIR/docs/a.md"
    write_impact_config "docs"
    git -C "$TEST_TMPDIR" add docs/a.md aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure invalid directory"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"is a directory, not an exact file"* ]]
}

@test "tracked symlink and gitlink modes cannot receive the M-only classification" {
    prepare_gate_baseline
    local blob head
    blob="$(printf 'target\n' | git -C "$TEST_TMPDIR" hash-object -w --stdin)"
    head="$(git -C "$TEST_TMPDIR" rev-parse HEAD)"

    write_impact_config "docs/link"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure symlink path"
    git -C "$TEST_TMPDIR" update-index --add --cacheinfo "120000,$blob,docs/link"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a regular tracked file: docs/link (mode 120000)"* ]]

    git -C "$TEST_TMPDIR" update-index --force-remove docs/link
    write_impact_config "modules/component"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "configure gitlink path"
    git -C "$TEST_TMPDIR" update-index --add --cacheinfo "160000,$head,modules/component"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a regular tracked file: modules/component (mode 160000)"* ]]
}

@test "level ci rejects missing, zero, unreadable, and HEAD-equal bases" {
    prepare_gate_baseline
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an explicit base commit"* ]]

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base 0000000000000000000000000000000000000000
    [ "$status" -eq 1 ]
    [[ "$output" == *"all-zero SHA"* ]]

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base ffffffffffffffffffffffffffffffffffffffff
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing, unreadable, or invalid"* ]]

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$(git -C "$TEST_TMPDIR" rev-parse HEAD)"
    [ "$status" -eq 1 ]
    [[ "$output" == *"base resolves to HEAD"* ]]
}

@test "an explicit empty base is rejected instead of using the local fallback" {
    prepare_gate_baseline

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a non-empty commit SHA"* ]]
    [[ "$output" != *"aahp verify passed"* ]]
}

@test "a symlinked config cannot supply Layer 2 policy" {
    prepare_gate_baseline
    mkdir -p "$TEST_TMPDIR/docs"
    printf 'baseline\n' > "$TEST_TMPDIR/docs/sensitive.md"
    printf '%s\n' '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/sensitive.md","reason":"Policy reached through a symlink."}]}}' \
        > "$TEST_TMPDIR/policy.json"
    ln -s policy.json "$TEST_TMPDIR/aahp.config.json"
    [ -L "$TEST_TMPDIR/aahp.config.json" ] || skip "requires filesystem symlink support"
    git -C "$TEST_TMPDIR" add docs/sensitive.md policy.json aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "track a symlinked policy"
    printf 'modified\n' >> "$TEST_TMPDIR/docs/sensitive.md"
    git -C "$TEST_TMPDIR" add docs/sensitive.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"aahp.config.json is not a regular tracked file (mode 120000)"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]
}

@test "reviewed modifications reject mode-only and content-plus-mode changes" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    git -C "$TEST_TMPDIR" update-index --chmod=+x docs/maintenance.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"changed Git mode: docs/maintenance.md (100644 -> 100755)"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]

    git -C "$TEST_TMPDIR" reset -q HEAD -- docs/maintenance.md
    git -C "$TEST_TMPDIR" checkout -q -- docs/maintenance.md
    printf 'modified\n' >> "$TEST_TMPDIR/docs/maintenance.md"
    git -C "$TEST_TMPDIR" add docs/maintenance.md
    git -C "$TEST_TMPDIR" update-index --chmod=+x docs/maintenance.md

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"changed Git mode: docs/maintenance.md (100644 -> 100755)"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]
}

@test "CI compares reviewed file modes across the base and HEAD endpoints" {
    prepare_gate_baseline
    commit_reviewed_file "docs/maintenance.md"
    local base
    base="$(git -C "$TEST_TMPDIR" rev-parse HEAD)"

    git -C "$TEST_TMPDIR" update-index --chmod=+x docs/maintenance.md
    git -C "$TEST_TMPDIR" commit -q -m "mode-only change"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"changed Git mode: docs/maintenance.md (100644 -> 100755)"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]

    printf 'modified\n' >> "$TEST_TMPDIR/docs/maintenance.md"
    git -C "$TEST_TMPDIR" add docs/maintenance.md
    git -C "$TEST_TMPDIR" update-index --chmod=+x docs/maintenance.md
    git -C "$TEST_TMPDIR" commit -q -m "content plus mode change"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"changed Git mode: docs/maintenance.md (100644 -> 100755)"* ]]
    [[ "$output" != *"Reviewed non-impacting modification"* ]]
}

@test "AAHP_BASE_SHA supplies a valid non-vacuous CI base" {
    prepare_gate_baseline
    AAHP_BASE_SHA="$CI_BASE" run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci
    [ "$status" -eq 0 ]
    [[ "$output" == *"aahp verify passed"* ]]
}

@test "a descendant base exposes rollback changes instead of a vacuous three-dot diff" {
    prepare_gate_baseline
    local original descendant
    original="$(git -C "$TEST_TMPDIR" rev-parse HEAD)"
    printf 'rolled back source\n' > "$TEST_TMPDIR/rollback.js"
    git -C "$TEST_TMPDIR" add rollback.js
    git -C "$TEST_TMPDIR" commit -q -m "future commit"
    descendant="$(git -C "$TEST_TMPDIR" rev-parse HEAD)"
    git -C "$TEST_TMPDIR" checkout -q --detach "$original"

    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$descendant"
    [ "$status" -eq 1 ]
    [[ "$output" == *"D rollback.js"* ]]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
}

@test "a git diff failure is a blocking CI failure" {
    prepare_gate_baseline
    local real_git stub_bin stub_path
    real_git="$(command -v git)"
    stub_bin="$TEST_TMPDIR/stub-bin"
    mkdir -p "$stub_bin"
    stub_path="$stub_bin"
    if command -v cygpath &>/dev/null; then
        stub_path="$(cygpath -u "$stub_bin")"
    fi
    cat > "$stub_bin/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    if [ "\$arg" = "diff" ]; then
        echo "forced diff failure" >&2
        exit 42
    fi
done
exec "$real_git" "\$@"
EOF
    chmod +x "$stub_bin/git"

    run env PATH="$stub_path:$PATH" bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$CI_BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not compute the Layer 2 diff"* ]]
    [[ "$output" == *"forced diff failure"* ]]
}

@test "required workflow always runs and passes event base SHA" {
    run grep -n -E 'dependabot|author\.username|github\.actor' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 1 ]

    run grep -n 'AAHP_BASE_SHA.*pull_request.base.sha.*event.before.*inputs.base' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 0 ]

    run grep -Ec 'uses: actions/(checkout|setup-node|setup-python)@[0-9a-f]{40} # v' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
    run grep -nE 'uses: .*@v[0-9]' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 1 ]
    grep -q 'permissions:' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    grep -q 'contents: read' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    grep -q 'persist-credentials: false' "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
}

@test "CLI help documents the explicit verify base" {
    run node "$AAHP_ROOT/bin/aahp.js" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--base SHA"* ]]
    [[ "$output" == *"required at --level ci"* ]]
}

@test "config example validates against the config schema" {
    local entry
    entry="$(cd "$AAHP_ROOT" && node -e '
try {
  const path = require("path");
  const pkg = require("ajv-cli/package.json");
  const dir = path.dirname(require.resolve("ajv-cli/package.json"));
  const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin.ajv;
  process.stdout.write(path.resolve(dir, bin));
} catch (e) {}
' 2>/dev/null)"
    [ -n "$entry" ] || skip "ajv-cli not installed"

    run node "$entry" validate --spec=draft2020 -c ajv-formats \
        -s "$AAHP_ROOT/schema/aahp-config.schema.json" \
        -d "$AAHP_ROOT/aahp.config.example.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid"* ]]
}

@test "config schema rejects malformed impact entries and unsafe path shapes" {
    local entry
    entry="$(cd "$AAHP_ROOT" && node -e '
try {
  const path = require("path");
  const pkg = require("ajv-cli/package.json");
  const dir = path.dirname(require.resolve("ajv-cli/package.json"));
  const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin.ajv;
  process.stdout.write(path.resolve(dir, bin));
} catch (e) {}
' 2>/dev/null)"
    [ -n "$entry" ] || skip "ajv-cli not installed"

    local cases=(
        '{"handoffImpact":{"nonImpactingModifiedFiles":{}}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"   "}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"\u200B"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"reviewed \u202E rationale"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"\uFEFF"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/a.md","reason":"..."}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"/tmp/a","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"../a","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"docs/*.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":".ai/handoff/STATUS.md","reason":"x"}]}}'
        '{"handoffImpact":{"nonImpactingModifiedFiles":[{"file":"aahp.config.json","reason":"x"}]}}'
    )
    local value
    for value in "${cases[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/invalid-config.json"
        run node "$entry" validate --spec=draft2020 -c ajv-formats \
            -s "$AAHP_ROOT/schema/aahp-config.schema.json" \
            -d "$TEST_TMPDIR/invalid-config.json"
        [ "$status" -ne 0 ]
        [[ "$output" == *"invalid"* ]]
    done
}
