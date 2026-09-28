#!/usr/bin/env bats
# init-gates.bats - Integration tests for `aahp init --gates`.
#
# `aahp init --gates` scaffolds governance adoption at the project root: a
# trimmed aahp.config.json (em-dash ban + internal doc-link check + pinnedDep),
# a `govern` npm script wired into an EXISTING package.json, a portable
# .github/workflows/aahp-govern.yml, and, only when .ai/handoff/ exists, the
# adopter verify workflow .github/workflows/aahp-verify.yml. It never creates
# .ai/handoff/. These tests assert those artifacts, that the emitted config
# validates against the config schema and is accepted by `aahp check`, that the
# scaffolded pinnedDep makes `aahp doctor` hold the exact pin, and that
# skip/force/no-package.json/no-handoff paths behave. All paths are absolute and
# no test changes cwd, so teardown can remove TEST_TMPDIR on every platform
# (Windows locks a process cwd).
#
# setup() creates TEST_TMPDIR/.ai/handoff/, so every test that does not remove
# it exercises the handoff-set branch, where the verify workflow is written.

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

# --- scaffolding: writes config + govern script + both workflows -------------

@test "init --gates scaffolds config, govern script, and both workflows" {
    make_pkg
    [ -d "$TEST_TMPDIR/.ai/handoff" ]
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/aahp.config.json" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" ]
    [[ "$output" == *"write: aahp.config.json"* ]]
    [[ "$output" == *"update: package.json (added govern script)"* ]]
    [[ "$output" == *"write: .github/workflows/aahp-govern.yml"* ]]
    [[ "$output" == *"write: .github/workflows/aahp-verify.yml"* ]]
    [[ "$output" == *"Done. 4 written/updated, 0 skipped."* ]]
    [[ "$output" == *"aahp-verify job (AAHP Verify) a required status check"* ]]
}

@test "init --gates copies both workflows from the packaged assets verbatim" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    diff "$AAHP_ROOT/assets/governance/aahp-govern.yml" \
         "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
    # The ADOPTER copy, not this repository's own .github/workflows/aahp-verify.yml,
    # which runs `node bin/aahp.js` and fails anywhere but an AAHP checkout.
    diff "$AAHP_ROOT/assets/governance/aahp-verify.yml" \
         "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
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

@test "init --gates without .ai/handoff writes no verify workflow and says how to add it" {
    make_pkg
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # The governance workflow is written; the verify workflow is not, because
    # `aahp verify` gates a handoff set and would be red on its first run here.
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    [ ! -e "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" ]
    [[ "$output" == *"note: no .ai/handoff/; skipped .github/workflows/aahp-verify.yml"* ]]
    [[ "$output" == *"run aahp init and aahp manifest"* ]]
    [[ "$output" == *"then aahp init --gates again"* ]]
    [[ "$output" == *"assets/governance/aahp-verify.yml into .github/workflows/"* ]]
    # A note, not a skip: nothing was declined, so the counters do not move.
    [[ "$output" == *"Done. 3 written/updated, 0 skipped."* ]]
    [[ "$output" == *"Make the govern job (AAHP Govern) a required status check"* ]]
}

@test "init --gates after aahp init adds the verify workflow it skipped before" {
    make_pkg
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" ]

    # The path the note names: aahp init, then init --gates again.
    run node "$AAHP_BIN" init "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"write: .github/workflows/aahp-verify.yml"* ]]
    [[ "$output" == *"Done. 1 written/updated, 3 skipped."* ]]
    diff "$AAHP_ROOT/assets/governance/aahp-verify.yml" \
         "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}

# --- emitted config: schema + shape ------------------------------------------

@test "init --gates config validates against aahp-config.schema.json" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    # CI's ajv validator. It exits 2 when ajv is not installed, so a broken
    # install is red here rather than a skip; it never installs anything.
    run node "$SCRIPTS_DIR/validate-json-schema.mjs" \
        "$AAHP_ROOT/schema/aahp-config.schema.json" \
        "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"aahp.config.json valid"* ]]
}

@test "init --gates config carries only forbiddenPatterns + docLinks + pinnedDep (plus schema ref)" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(Object.keys(c).sort().join(","))' \
        "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = '$schema,docLinks,forbiddenPatterns,pinnedDep' ]
}

@test "init --gates config sets pinnedDep to the defaults (an empty object)" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # {} means @elvatis_com/aahp, devDependencies, exact version, no range.
    run node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(JSON.stringify(c.pinnedDep))' \
        "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = '{}' ]
}

# --- emitted config: aahp doctor holds the exact pin --------------------------

# Write the given devDependencies spec for @elvatis_com/aahp into
# TEST_TMPDIR/package.json ("" = no such dependency).
_set_pin() {
    node -e '
const fs = require("fs");
const [pkgPath, spec] = process.argv.slice(1);
const p = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
p.devDependencies = spec ? { "@elvatis_com/aahp": spec } : {};
fs.writeFileSync(pkgPath, JSON.stringify(p, null, 2) + "\n");
' "$TEST_TMPDIR/package.json" "$1"
}

# The pinned-dep status in the `aahp doctor --governance --json` record.
_pin_status() {
    node "$AAHP_BIN" doctor --governance --json "$TEST_TMPDIR" |
        node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).gates["pinned-dep"]))'
}

@test "init --gates makes aahp doctor hold the exact pin: exact passes, range fails, absent is missing" {
    make_pkg
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    _set_pin "3.12.0"
    run _pin_status
    [ "$output" = "pass" ]
    _set_pin "^3.12.0"
    run _pin_status
    [ "$output" = "fail" ]
    _set_pin ""
    run _pin_status
    [ "$output" = "missing" ]

    # And the verdict reaches the exit code, not only the record.
    _set_pin "^3.12.0"
    run node "$AAHP_BIN" doctor --governance "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not an exact pin"* ]]
}

@test "a repo scaffolded with init, manifest and init --gates passes aahp doctor and aahp check" {
    make_pkg
    _set_pin "3.12.0"
    printf '# Demo\n\nNo broken internal links here.\n' > "$TEST_TMPDIR/README.md"
    run node "$AAHP_BIN" init "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run node "$AAHP_BIN" manifest "$TEST_TMPDIR" --phase idle --quiet
    [ "$status" -eq 0 ]
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    git -C "$TEST_TMPDIR" add -A

    # Full conformance, handoff gates included: no --governance.
    run node "$AAHP_BIN" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"PASS     pinned-dep: pinned exact: 3.12.0"* ]]
    [[ "$output" == *"PASS     verify-workflow: the gate runs unconditionally at --level ci (.github/workflows/aahp-verify.yml:aahp-verify)"* ]]
    [[ "$output" == *"Conformance OK"* ]]

    run node "$AAHP_BIN" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"Governance OK"* ]]
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
    [[ "$output" == *"skip: .github/workflows/aahp-verify.yml (already exists, use --force to overwrite)"* ]]
    [[ "$output" == *"Done. 0 written/updated, 4 skipped."* ]]
}

@test "init --gates keeps an existing aahp-verify.yml unless --force" {
    make_pkg
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    printf 'name: My own verify\n' > "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip: .github/workflows/aahp-verify.yml (already exists"* ]]
    [ "$(cat "$TEST_TMPDIR/.github/workflows/aahp-verify.yml")" = "name: My own verify" ]

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"write: .github/workflows/aahp-verify.yml"* ]]
    diff "$AAHP_ROOT/assets/governance/aahp-verify.yml" \
         "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
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

# --- the aahp package itself -------------------------------------------------

@test "init --gates in the aahp package itself never writes its verify workflow, even with --force" {
    # A target whose root package.json names @elvatis_com/aahp is this package:
    # its own aahp-verify.yml runs the gate from the working tree, and the
    # adopter copy would replace that with the last published CLI.
    printf '{\n  "name": "@elvatis_com/aahp",\n  "version": "3.12.0"\n}\n' > "$TEST_TMPDIR/package.json"
    [ -d "$TEST_TMPDIR/.ai/handoff" ]

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    [[ "$output" == *"note: this is @elvatis_com/aahp itself; .github/workflows/aahp-verify.yml is not written"* ]]
    [[ "$output" == *"README Section 9.2"* ]]
    [[ "$output" == *"Done. 3 written/updated, 0 skipped."* ]]
    # pinnedDep is still written for uniformity; the gate reports self before reading it.
    grep -q '"pinnedDep"' "$TEST_TMPDIR/aahp.config.json"

    # The package's own workflow survives --force byte for byte.
    printf 'name: AAHP Verify\n# runs node bin/aahp.js from the working tree\n' \
        > "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    cp "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" "$TEST_TMPDIR/own-verify.yml"
    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not written or"* ]]
    cmp "$TEST_TMPDIR/own-verify.yml" "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    # --force did act on the other files, so the preservation above is specific.
    [[ "$output" == *"write: .github/workflows/aahp-govern.yml"* ]]
}

# --- no package.json ---------------------------------------------------------

@test "init --gates without package.json writes config + workflows and notes the skip" {
    # setup() does not create a package.json; assert the precondition holds.
    [ ! -f "$TEST_TMPDIR/package.json" ]

    run node "$AAHP_BIN" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/aahp.config.json" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-govern.yml" ]
    [ -f "$TEST_TMPDIR/.github/workflows/aahp-verify.yml" ]
    # It must not fabricate a package.json.
    [ ! -f "$TEST_TMPDIR/package.json" ]
    [[ "$output" == *"no package.json"* ]]
    [[ "$output" == *"Done. 3 written/updated, 0 skipped."* ]]
}
