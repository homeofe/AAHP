#!/usr/bin/env bats
# init-gates.bats - Integration tests for `aahp init --gates`.
#
# `aahp init --gates` scaffolds governance-only adoption at the project root:
# a trimmed aahp.config.json (em-dash ban + internal doc-link check), a `govern`
# npm script wired into an EXISTING package.json, and a portable
# .github/workflows/aahp-govern.yml. It never touches .ai/handoff/. These tests
# assert those artifacts, that the emitted config validates against the config
# schema and is accepted by `aahp check`, and that skip/force/no-package.json
# paths behave. All paths are absolute and no test changes cwd, so teardown can
# remove TEST_TMPDIR on every platform (Windows locks a process cwd).

setup() {
    load test_helper
    setup

    AAHP_BIN="$AAHP_ROOT/bin/aahp.js"
    export AAHP_BIN
}

teardown() {
    teardown
}

# --- Helpers -----------------------------------------------------------------

# Create a package.json (without a govern script) at the repo root so the
# `govern` wiring path is exercised. init --gates never creates one itself.
make_pkg() {
    cat > "$TEST_TMPDIR/package.json" <<'EOF'
{
  "name": "demo-consumer",
  "version": "1.0.0",
  "scripts": {
    "test": "echo test"
  }
}
EOF
}

# Resolve ajv-cli's JS entrypoint via Node module resolution rooted at the repo.
# Prints an absolute path, or nothing when ajv-cli is not installed (the schema
# test then skips rather than triggering a network install).
_ajv_entry() {
    ( cd "$AAHP_ROOT" && node -e '
try {
  const path = require("path");
  const pkg = require("ajv-cli/package.json");
  const dir = path.dirname(require.resolve("ajv-cli/package.json"));
  const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin.ajv;
  process.stdout.write(path.resolve(dir, bin));
} catch (e) {}
' ) 2>/dev/null
}

# --- scaffolding: writes config + govern script + workflow -------------------

@test "init --gates scaffolds config, govern script, and workflow" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/aahp.config.json" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    [[ "$output" == *"write: aahp.config.json"* ]]
    [[ "$output" == *"update: package.json (added govern script)"* ]]
    [[ "$output" == *"write: .github/workflows/aahp-govern.yml"* ]]
    [[ "$output" == *"Done. 3 written/updated, 0 skipped."* ]]
}

@test "init --gates copies the workflow from the packaged asset verbatim" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    diff "$AAHP_ROOT/assets/governance/aahp-govern.yml" \
         "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
}

# --- never touches the handoff protocol --------------------------------------

@test "init --gates never creates .ai/handoff" {
    make_pkg
    # setup() pre-creates TEST_TMPDIR/.ai/handoff; remove it so a recreation
    # would be unambiguous, then assert init --gates does not bring it back.
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/.ai" ]
}

# --- emitted config: schema + shape ------------------------------------------

@test "init --gates config validates against aahp-config.schema.json" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    local entry
    entry="$(_ajv_entry)"
    [ -n "$entry" ] || skip "ajv-cli not installed"

    run node "$entry" validate --spec=draft2020 -c ajv-formats \
        -s "$AAHP_ROOT/schema/aahp-config.schema.json" \
        -d "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid"* ]]
}

@test "init --gates config carries only forbiddenPatterns + docLinks (plus schema ref)" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(Object.keys(c).sort().join(","))' \
        "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = '$schema,docLinks,forbiddenPatterns' ]
}

@test "init --gates stores the em-dash ban as an escape, not a literal U+2014" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # The scaffolded config must not match its own forbidden-pattern rule.
    grep -q 'u2014' "$TEST_TMPDIR/aahp.config.json"
    run node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8");process.exit(t.includes(String.fromCharCode(0x2014))?1:0)' \
        "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
}

# --- emitted config: accepted by `aahp check` --------------------------------

@test "init --gates config passes aahp check on a git repo" {
    make_pkg
    printf '# Demo\n\nNo broken internal links here.\n' > "$TEST_TMPDIR/README.md"
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    git -C "$TEST_TMPDIR" add -A

    run node "$AAHP_BIN" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Governance OK"* ]]
    [[ "$output" == *"forbidden-patterns"* ]]
    [[ "$output" == *"doc-links"* ]]
}

# --- govern script value -----------------------------------------------------

@test "init --gates sets the govern script to 'aahp check .'" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(p.scripts.govern)' \
        "$TEST_TMPDIR/package.json"
    [ "$status" -eq 0 ]
    [ "$output" = "aahp check ." ]
}

@test "init --gates preserves existing package.json scripts" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(p.scripts.test||"")' \
        "$TEST_TMPDIR/package.json"
    [ "$output" = "echo test" ]
}

# --- idempotency / force -----------------------------------------------------

@test "init --gates re-run skips existing files" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip"* ]]
    [[ "$output" == *"skip: aahp.config.json"* ]]
    [[ "$output" == *"Done. 0 written/updated, 3 skipped."* ]]
}

@test "init --gates --force overwrites the config" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    # Replace the scaffolded config with a stripped-down sentinel.
    echo '{"forbiddenPatterns":[]}' > "$TEST_TMPDIR/aahp.config.json"

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"write: aahp.config.json"* ]]
    # The scaffolded sections are restored.
    grep -q '"docLinks"' "$TEST_TMPDIR/aahp.config.json"
    grep -q '"em-dash"' "$TEST_TMPDIR/aahp.config.json"
}

# --- no package.json ---------------------------------------------------------

@test "init --gates without package.json writes config + workflow and notes the skip" {
    # setup() does not create a package.json; assert the precondition holds.
    [ ! -f "$TEST_TMPDIR/package.json" ]

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/aahp.config.json" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    # It must not fabricate a package.json.
    [ ! -f "$TEST_TMPDIR/package.json" ]
    [[ "$output" == *"no package.json"* ]]
    [[ "$output" == *"Done. 2 written/updated, 0 skipped."* ]]
}
