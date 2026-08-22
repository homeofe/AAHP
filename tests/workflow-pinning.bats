#!/usr/bin/env bats
# workflow-pinning.bats - whatever a workflow installs and then executes must
# come from the committed lockfile, and the lockfile must pin it by hash.
#
# Every rule is asserted in BOTH directions: it holds on the real repository,
# and each separate way of breaking it turns the gate red with the EXACT exit
# code the gate documents. A gate proved only in the passing direction is
# indistinguishable from a gate that cannot fail.
#
# Exit codes are compared with -eq, never with "not zero". Exit 1 (a finding)
# and exit 2 (the gate could not evaluate) are different answers, and a mutation
# that reaches the wrong one has not proved what the test claims.

load test_helper

GATE="$SCRIPTS_DIR/check-workflow-pinning.mjs"

# NOTE: TEST_TMPDIR is created by setup(), which runs AFTER this file is sourced,
# so the workflow directory cannot be a top-level variable - it would expand to
# "/.github/workflows" here. Every test calls this instead.
wf_dir() {
    printf '%s/.github/workflows' "$TEST_TMPDIR"
}

# package.json for a fixture project. $1 is the devDependencies body; omitting it
# declares the one package the baseline workflow executes, at an exact version.
write_pkg() {
    local deps="${1:-\"fx-tool\": \"1.2.3\"}"
    cat > "$TEST_TMPDIR/package.json" <<EOF
{ "name": "fx", "version": "1.0.0", "devDependencies": { $deps } }
EOF
}

# package-lock.json for a fixture project. $1 is the packages body for the one
# dependency; omitting it writes a complete, correctly pinned entry.
write_lock() {
    local entry="${1:-\"version\": \"1.2.3\", \"resolved\": \"https://registry.npmjs.org/fx-tool/-/fx-tool-1.2.3.tgz\", \"integrity\": \"sha512-deadbeef\"}"
    cat > "$TEST_TMPDIR/package-lock.json" <<EOF
{
  "name": "fx",
  "lockfileVersion": 3,
  "packages": {
    "": { "name": "fx", "devDependencies": { "fx-tool": "1.2.3" } },
    "node_modules/fx-tool": { $entry }
  }
}
EOF
}

# The baseline fixture: install the locked closure, then execute a pinned tool
# offline. Every mutation test below starts from this and breaks ONE thing, so a
# red result can only have been caused by that one change.
write_good_workflow() {
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Install dependencies
        run: npm ci --ignore-scripts
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
EOF
}

# Everything a passing fixture needs, in one call.
write_good_fixture() {
    write_pkg
    write_lock
    write_good_workflow
}

# ─── The load-bearing assertion: the real repository ────────────────────────

@test "the real repository satisfies every pinning rule" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Workflow pinning OK"* ]]
}

# The finding this gate was written for, asserted directly on the two workflow
# files rather than through the gate. This is deliberately NOT a restatement of
# the test above: that one passes whenever the gate is satisfied, including if
# the gate were later weakened. This one reads the workflow text itself, so it
# still fails if the gate stops looking.
@test "neither MANIFEST validation step can reach the registry" {
    local ci="$AAHP_ROOT/.github/workflows/ci.yml"
    local manifest="$AAHP_ROOT/.github/workflows/aahp-manifest.yml"

    # The original defect: an unconstrained install of two undeclared packages.
    run grep -c -- "--no-save" "$ci" "$manifest"
    [ "$status" -eq 1 ]

    # The fix, in both host jobs.
    run grep -c -- "npx --no-install ajv-cli validate" "$ci"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -c -- "npx --no-install ajv-cli validate" "$manifest"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    # And the packages the two steps execute are declared here at exact versions.
    run node "$AAHP_ROOT/tests/assert-pinning-gate-wired.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinning gate wiring OK"* ]]
}

@test "the baseline fixture is clean" {
    write_good_fixture

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Workflow pinning OK"* ]]
}

# ─── Rule A: no project-level npm install in a workflow ─────────────────────

@test "reintroducing the original unpinned install is red" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Validate MANIFEST schema
        run: |
          npm install --no-save ajv-cli ajv-formats
          npx --no-install fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"installs packages outside the committed lockfile"* ]]
}

@test "a bare npm install is red too, not only --no-save" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Sneak it in
        run: npm install
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"installs packages outside the committed lockfile"* ]]
}

@test "an install hidden behind a shell separator is still found" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Sneak it in
        run: echo hello && npm i fx-tool ; echo done
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"installs packages outside the committed lockfile"* ]]
}

@test "a global install is deliberately NOT a finding of this gate" {
    # Scope, recorded in the gate header and on
    # https://github.com/homeofe/AAHP/issues/68: `npm install -g` is a different
    # risk class with an owner decision still open on it. This test exists so the
    # exemption is a stated property with a test behind it rather than an
    # accident of the regex, and so it fails loudly if the scope ever changes.
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Upgrade npm
        run: npm install -g npm@latest
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── Rule B: npx must carry --no-install ────────────────────────────────────

@test "dropping --no-install from npx is red" {
    write_good_fixture
    # The ONLY difference from the baseline: --no-install is gone.
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Install dependencies
        run: npm ci --ignore-scripts
      - name: Validate
        run: npx fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"without \`--no-install\`"* ]]
}

@test "npx -y is red, because -y is the opposite of a pin" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Fetch and run
        run: npx -y fx-tool validate
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"without \`--no-install\`"* ]]
}

# ─── Rule C: what npx executes must be declared here, at an exact version ───

@test "executing a package this repository does not declare is red" {
    write_pkg '"something-else": "1.2.3"'
    write_lock
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"which package.json does not declare"* ]]
}

@test "a range instead of an exact version is red" {
    write_pkg '"fx-tool": "^1.2.3"'
    write_lock
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Declare an exact version"* ]]
}

@test "an exact version carrying a prerelease and build suffix is accepted" {
    # Guards the shape of the version regex, which was rewritten after CodeQL
    # reported js/redos against the first form. A repeated group whose character
    # class also contains its own delimiter is exponentially ambiguous, and
    # package.json is attacker-supplied on a fork pull request. The rewrite must
    # not have narrowed what counts as an exact version.
    write_pkg '"fx-tool": "1.2.3-beta.1+build.5"'
    write_lock '"version": "1.2.3-beta.1+build.5", "resolved": "https://registry.npmjs.org/fx-tool/-/fx-tool-1.2.3.tgz", "integrity": "sha512-deadbeef"'
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── Rule D: the lockfile pins every direct dependency by hash ──────────────

@test "a lockfile entry without an integrity hash is red" {
    write_pkg
    write_lock '"version": "1.2.3", "resolved": "https://registry.npmjs.org/fx-tool/-/fx-tool-1.2.3.tgz"'
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no \`integrity\` hash in the lockfile"* ]]
}

@test "a declared dependency with no lockfile entry at all is red" {
    write_pkg
    cat > "$TEST_TMPDIR/package-lock.json" <<'EOF'
{ "name": "fx", "lockfileVersion": 3, "packages": { "": { "name": "fx" } } }
EOF
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no lockfile entry"* ]]
}

# ─── Exit 2: what the gate could not evaluate is never reported as clean ────

@test "no workflow directory exits 2, not 0" {
    write_pkg
    write_lock

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no workflow directory"* ]]
}

@test "an empty workflow directory exits 2, not 0" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"contains no workflow files"* ]]
}

@test "unparseable YAML exits 2, not 0" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not valid YAML"* ]]
}

@test "a missing lockfile exits 2, not 0" {
    write_pkg
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no package-lock.json"* ]]
}

# ─── The gate has to actually RUN ───────────────────────────────────────────

@test "the gate is wired into the aggregate check chain" {
    # A gate that exists but is never invoked protects nothing. The assertion
    # lives in tests/assert-pinning-gate-wired.mjs - see the header there for why
    # this is a file and not an inline `node -e`.
    run node "$AAHP_ROOT/tests/assert-pinning-gate-wired.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinning gate wiring OK"* ]]
}
