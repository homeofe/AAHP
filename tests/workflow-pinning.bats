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

    # The fix, in both host jobs. Asserted as a RELATION - every `ajv-cli
    # validate` invocation carries `--no-install` - and not as "there is exactly
    # one". A fixed count is an anchor that a legitimate second validation step
    # breaks, and the obvious repair is to raise the number, which silently
    # exempts the new step from the property the count existed to protect. That
    # is what happened when the aahp.config.json validation step was added.
    # Written this way the file may grow further validation steps and each one is
    # still held to the rule; a step added WITHOUT the flag is red.
    local total flagged
    for f in "$ci" "$manifest"; do
        total="$(grep -c -- "ajv-cli validate" "$f" || true)"
        flagged="$(grep -c -- "npx --no-install ajv-cli validate" "$f" || true)"
        [ "$total" -ge 1 ] || { echo "no ajv-cli validate step in $f"; false; }
        [ "$flagged" -eq "$total" ] || {
            echo "$f: $total ajv-cli validate step(s), only $flagged carry --no-install"
            false
        }
    done

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

@test "a global install is red, including npm@latest in the publish job" {
    # The former publish step ran this immediately before npm publish while the
    # job held id-token: write. Node 24 already carries a qualifying npm, so the
    # step is gone and this mutation proves it cannot quietly return.
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Upgrade npm
        run: npm install -g npm@latest
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"installs packages outside the committed lockfile"* ]]
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

@test "npm exec is red even with --no-install, because npm exec ignores that flag" {
    # Measured 2026-09-28 (rule B in the gate): `npm exec --no-install` on npm 10
    # and 11 downloads and runs a missing package; only the `npx` binary rewrites
    # the flag to --yes=false. The spelling that looks equally careful is the one
    # that is not.
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Validate again
        run: npm exec --no-install -- fx-tool validate
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runs \`npm exec\`, which has no \`--no-install\`"* ]]
}

@test "the npm x alias of npm exec is red too" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Validate again
        run: npm x fx-tool validate
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runs \`npm exec\`"* ]]
}

# --- Rule I: npm ci runs no lifecycle script ---------------------------------

@test "npm ci without --ignore-scripts is red" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Install dependencies
        run: npm ci
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"installs the locked closure with lifecycle scripts enabled"* ]]
}

@test "an npm ci alias without --ignore-scripts is red, and =false is not the flag" {
    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Reinstall
        run: npm clean-install
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"npm clean-install"* ]]
    [[ "$output" == *"lifecycle scripts enabled"* ]]

    write_good_fixture
    cat >> "$(wf_dir)/ci.yml" <<'EOF'
      - name: Reinstall
        run: npm ci --ignore-scripts=false
EOF
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lifecycle scripts enabled"* ]]
}

# --- Rule J: npx only after npm ci, in the same job ---------------------------

@test "npx in a job that never ran npm ci is red" {
    # --no-install is present, so rule B is satisfied; what is missing is the
    # install that makes npx resolve locally instead of asking the registry.
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has not run \`npm ci\` before it"* ]]
}

@test "npm ci AFTER the npx step is red: order matters" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
      - name: Install dependencies
        run: npm ci --ignore-scripts
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has not run \`npm ci\` before it"* ]]
}

@test "npm ci in a DIFFERENT job does not count: jobs share no node_modules" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - name: Install dependencies
        run: npm ci --ignore-scripts
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci.yml:validate:Validate"* ]]
    [[ "$output" == *"has not run \`npm ci\` before it"* ]]
}

@test "npm ci earlier in the same run block satisfies rule J" {
    write_pkg
    write_lock
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Install and validate
        run: npm ci --ignore-scripts && npx --no-install fx-tool validate -s schema.json -d data.json
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Workflow pinning OK"* ]]
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
    # package.json is attacker-supplied on a fork pull request.
    #
    # The rewrite DID narrow what counts as an exact version, and this test
    # cannot see it. The new build class is `[0-9A-Za-z.]`, which drops the `-`
    # the prerelease class still allows, so build metadata containing a hyphen -
    # `1.0.0+21AF26D3----117B344092BD`, the SemVer specification's own example -
    # is now reported as a range. The fixture below carries `+build.5`, no
    # hyphen, so it is green under both forms and proves only that a prerelease
    # and a dot-separated build survive. The narrowing is fail-closed and
    # unreachable for the two packages this gate governs; if it is ever hit, put
    # the hyphen back in the build class (still linear, `+` cannot appear inside
    # it) and add the hyphen case here.
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

# ─── Rules E and F: what a workflow USES, and what moves those pins ─────────
#
# Rules A to D read `step.run`, the shell text of a step. Every `uses:` step has
# no `run:` at all, so before rule E this gate skipped all of them - and exited 0
# on this repository while 22 of its 25 action references sat on mutable major
# tags. The fixtures below therefore start from a workflow that HAS a `uses:`,
# because the rule-A-to-D fixtures have none and could never have detected this.

# .github/dependabot.yml for a fixture project. With no argument it writes the
# lane rule F requires, carrying the cooldown and the "*" group rule K requires;
# with one, that argument is the whole `updates:` body.
# Written as a branch rather than a defaulted variable on purpose: the default is
# multi-line and contains quotes, and a `${1:-...}` carrying both is the kind of
# expression that breaks silently and takes a test's meaning with it.
write_dependabot() {
    mkdir -p "$TEST_TMPDIR/.github"
    if [ "$#" -eq 0 ]; then
        cat > "$TEST_TMPDIR/.github/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      all:
        applies-to: version-updates
        patterns:
          - "*"
EOF
        return
    fi
    cat > "$TEST_TMPDIR/.github/dependabot.yml" <<EOF
version: 2
updates:
$1
EOF
}

# A workflow with one action reference. With one argument that argument replaces
# the reference line, so every mutation below differs from the passing fixture by
# exactly that one line.
write_uses_workflow() {
    local ref='      - uses: actions/checkout@1111111111111111111111111111111111111111 # v4.2.2'
    if [ "$#" -ge 1 ]; then
        ref="$1"
    fi
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<EOF
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
$ref
      - name: Install dependencies
        run: npm ci --ignore-scripts
      - name: Validate
        run: npx --no-install fx-tool validate -s schema.json -d data.json
EOF
}

# The passing fixture for rules E and F: one pinned reference, one lane.
write_pinned_fixture() {
    write_pkg
    write_lock
    write_uses_workflow
    write_dependabot
}

@test "the pinned baseline fixture is clean" {
    write_pinned_fixture

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 action reference(s) pinned to an immutable ref"* ]]
}

@test "an action on a mutable major tag is red" {
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout@v4"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolves the mutable ref \"v4\""* ]]
}

@test "an action on a branch is red, not only a version tag" {
    # `@main` is the same defect with a friendlier name: whoever can push to that
    # branch chooses what runs here, and needs no release to do it.
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout@main"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolves the mutable ref \"main\""* ]]
}

@test "a reference with no ref at all is red" {
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolves the mutable ref \"(none)\""* ]]
}

@test "a 39-character hex ref is red, so the length is actually checked" {
    # An anchored fixed-length pattern is the point: a prefix that merely LOOKS
    # like a commit is not one, and git would not resolve it as this action.
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout@111111111111111111111111111111111111111 # v4.2.2"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolves the mutable ref"* ]]
}

@test "a pinned SHA with no trailing version comment is red" {
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout@1111111111111111111111111111111111111111"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no trailing comment naming the release"* ]]
}

@test "a trailing comment that names no version is red" {
    # "has a comment" is not the property. The comment has to say WHICH release,
    # because that is the half a reviewer reads and the half Dependabot rewrites.
    write_pinned_fixture
    write_uses_workflow "      - uses: actions/checkout@1111111111111111111111111111111111111111 # pinned"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no trailing comment naming the release"* ]]
}

@test "a reusable workflow call outside steps is checked too" {
    # jobs.<id>.uses is not a step and has no `run:`. A gate that walked only
    # jobs.*.steps would report this file clean.
    write_pkg
    write_lock
    write_dependabot
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  call:
    uses: some-org/some-repo/.github/workflows/shared.yml@v1
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolves the mutable ref \"v1\""* ]]
}

@test "a local action reference is exempt, and said so rather than counted as pinned" {
    # `./path` has no ref to pin: its bytes are the bytes of this commit.
    # Reported separately so the pinned count stays a count of real pins.
    write_pinned_fixture
    write_uses_workflow "      - uses: ./.github/actions/local-thing"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 local action reference(s) exempt"* ]]
    [[ "$output" == *"0 action reference(s) pinned"* ]]
}

@test "a container image on a tag is red, and on a digest is green" {
    write_pinned_fixture
    write_uses_workflow "      - uses: docker://alpine:3.20"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runs a container image by tag"* ]]

    write_uses_workflow "      - uses: docker://alpine@sha256:1111111111111111111111111111111111111111111111111111111111111111"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "a uses: whose value is not a plain string is red" {
    write_pkg
    write_lock
    write_dependabot
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: [actions/checkout, v4]
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a plain string"* ]]
}

@test "the shipped template directory is held to rule E as well" {
    # assets/governance/aahp-govern.yml is copied into consumer repositories, so
    # a mutable tag there is a mutable tag on somebody else's CI.
    write_pinned_fixture
    mkdir -p "$TEST_TMPDIR/assets/governance"
    cat > "$TEST_TMPDIR/assets/governance/aahp-govern.yml" <<'EOF'
name: govern
on: [push]
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"assets/governance/aahp-govern.yml"* ]]
    [[ "$output" == *"resolves the mutable ref \"v4\""* ]]
}

# --- Rule H: the shipped template moves with the workflows ------------------
#
# Dependabot reads only .github/workflows, so before rule H a bump moved every
# workflow here and left the file adopters copy on the old commit, green.

# A template using one action. $1 replaces the reference line; with no argument
# it is the exact reference write_uses_workflow pins, so the fixture is green.
write_govern_template() {
    local ref='      - uses: actions/checkout@1111111111111111111111111111111111111111 # v4.2.2'
    if [ "$#" -ge 1 ]; then
        ref="$1"
    fi
    mkdir -p "$TEST_TMPDIR/assets/governance"
    cat > "$TEST_TMPDIR/assets/governance/aahp-govern.yml" <<EOF
name: govern
on: [push]
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
$ref
EOF
}

@test "rule H: a template on the workflows' commit and version is green, and counted" {
    write_pinned_fixture
    write_govern_template

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Template pins: 1 action reference(s) in shipped templates match"* ]]
}

@test "rule H: a template left on the old commit after a bump is red" {
    # Exactly what a Dependabot bump of the workflows produced: the workflow
    # moved, the template did not.
    write_pinned_fixture
    write_govern_template '      - uses: actions/checkout@2222222222222222222222222222222222222222 # v4.2.2'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has drifted from .github/workflows"* ]]
    [[ "$output" == *"1111111111111111111111111111111111111111 # v4.2.2"* ]]
}

@test "rule H: the right commit with the wrong version comment is red" {
    write_pinned_fixture
    write_govern_template '      - uses: actions/checkout@1111111111111111111111111111111111111111 # v4.2.1'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has drifted from .github/workflows"* ]]
}

@test "rule H: an action only the template uses is red, because nothing moves it" {
    write_pinned_fixture
    write_govern_template '      - uses: actions/setup-node@3333333333333333333333333333333333333333 # v4.0.0'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is used by a shipped template and by no workflow"* ]]
}

@test "rule H: this repository's template matches its workflows" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Template pins: "*" action reference(s) in shipped templates match .github/workflows"* ]]
    # And the count is not zero: a gate that compared nothing would print a pass.
    [[ "$output" != *"Template pins: not asserted"* ]]
}

# ─── Rule F: the pins have to be able to move ───────────────────────────────

@test "pinned actions with no Dependabot configuration at all is red" {
    write_pkg
    write_lock
    write_uses_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"there is no Dependabot configuration at all"* ]]
}

@test "a Dependabot configuration naming only npm is red" {
    # The exact state of this repository before the fix: a visibly working npm
    # lane, and no lane at all for the 22 floating action references.
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not declared, so Dependabot never scans"* ]]
}

@test "a github-actions lane pointed at another directory is red" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/tools"
    schedule:
      interval: "weekly"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no lane covers \"/\""* ]]
}

@test "a lane declared with directories: instead of directory: is accepted" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directories:
      - "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      all:
        patterns:
          - "*"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "with no action references the lane is reported NOT ASSERTED, not as a pass" {
    # The third state. A tree with nothing to update is not a tree whose update
    # lane was checked, and printing "OK" without saying which of the two it was
    # is how a gate stops meaning anything.
    write_good_fixture

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not asserted: no remote \`uses:\` in the workflow directory"* ]]
}

@test "an unparseable dependabot.yml exits 2, not 1" {
    # GitHub rejects the whole file, so EVERY lane stops, including npm. That is
    # a state the gate could not evaluate, which is not the same answer as a
    # missing lane, and the exit code has to say which one it is.
    write_pinned_fixture
    printf 'version: 2\nupdates: [unclosed\n' > "$TEST_TMPDIR/.github/dependabot.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"is not valid YAML"* ]]
}

@test "a dependabot.yml with no updates list exits 2, not 0" {
    write_pinned_fixture
    printf 'version: 1\n' > "$TEST_TMPDIR/.github/dependabot.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no \`updates\` list"* ]]
}

# --- Rule K: every lane is grouped and cooled down ---------------------------

@test "rule K: a lane with no cooldown is red" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      all:
        patterns:
          - "*"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cooldown: default-days"* ]]
    [[ "$output" == *"is missing, so this lane proposes a release the moment it is published"* ]]
}

@test "rule K: a zero-day cooldown is red, it is not a cooldown" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 0
    groups:
      all:
        patterns:
          - "*"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is 0, so this lane proposes a release"* ]]
}

@test "rule K: a lane with no catch-all group is red" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"opens one pull request per dependency"* ]]
}

@test "rule K: a catch-all group for SECURITY updates only does not group version updates" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      all:
        applies-to: security-updates
        patterns:
          - "*"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"opens one pull request per dependency"* ]]
}

@test "rule K: it holds for the npm lane too, not only github-actions" {
    write_pinned_fixture
    write_dependabot '  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      all:
        patterns:
          - "*"
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"'

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"updates[1] (npm)"* ]]
}

# ─── The finding itself, read off the repository rather than through the gate ─

@test "every action reference in this repository is a commit SHA with a version" {
    # Deliberately NOT a restatement of "the real repository satisfies every
    # pinning rule": that test passes whenever the gate is satisfied, including
    # if rule E were later weakened or deleted. This one reads the workflow text
    # itself, so it stays red if the gate stops looking.
    #
    # `tr -d '\r'` first, and this is not defensive noise: on a Windows checkout
    # these files are CRLF, and a shell regex anchored with `$` then reports a
    # correctly pinned reference as unpinned. Issue 71 was written with that
    # warning in it.
    local total pinned
    total=0
    pinned=0
    while IFS= read -r file; do
        local t p
        t="$(tr -d '\r' < "$file" | grep -cE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]+[A-Za-z]' || true)"
        p="$(tr -d '\r' < "$file" | grep -E '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]+[A-Za-z]' \
            | grep -cE '@[0-9a-f]{40} # v?[0-9]' || true)"
        total=$((total + t))
        pinned=$((pinned + p))
    done < <(find "$AAHP_ROOT/.github/workflows" "$AAHP_ROOT/assets/governance" -name '*.yml' -o -name '*.yaml')

    # A relation, not a fixed count: the file may grow more references and each
    # new one is still held to the rule. A fixed number would be an anchor whose
    # obvious repair is to raise it.
    [ "$total" -ge 25 ] || { echo "only $total action references found; the scan is not reading the files"; false; }
    [ "$pinned" -eq "$total" ] || {
        echo "$pinned of $total action references carry a 40-character SHA and a version comment"
        false
    }
}

@test "this repository declares a github-actions Dependabot lane" {
    # Measured on the configuration, because the pull-request COUNT cannot
    # answer it: an ecosystem that is absent and an ecosystem that is up to date
    # both produce zero pull requests.
    run grep -c 'package-ecosystem: "github-actions"' "$AAHP_ROOT/.github/dependabot.yml"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "this repository's Dependabot lanes are grouped and cooled down" {
    # Read off the configuration directly, not through the gate, so weakening
    # rule K cannot also silence this.
    run node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const cfg = YAML.parse(readFileSync(join(process.argv[1], ".github/dependabot.yml"), "utf8"));
      const lanes = cfg.updates ?? [];
      const names = lanes.map((l) => l["package-ecosystem"]).sort().join(",");
      if (names !== "github-actions,npm") throw new Error("expected exactly the npm and github-actions lanes, got " + names);
      for (const lane of lanes) {
        const eco = lane["package-ecosystem"];
        if (!(Number.isInteger(lane.cooldown?.["default-days"]) && lane.cooldown["default-days"] >= 1)) {
          throw new Error(eco + " lane has no cooldown of at least one day");
        }
        const all = Object.values(lane.groups ?? {}).filter((g) =>
          (g["applies-to"] ?? "version-updates") === "version-updates" && (g.patterns ?? []).includes("*"));
        if (all.length !== 1) throw new Error(eco + " lane does not group every version update into one pull request");
        if (String(lane.directory) !== "/") throw new Error(eco + " lane no longer covers /");
      }
      console.log("dependabot lanes OK");
    ' "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dependabot lanes OK"* ]]
}

# --- The supply-chain scanner: pinned by invariant, not by literal ------------
#
# This used to compare the action reference with one literal SHA, so every
# Dependabot bump of the scanner was red by construction: #114, #116 and #118
# (6.0.12, 6.0.19, 6.2.0) all failed on exactly that test and were closed. The contract below states what
# has to stay true across bumps instead: an immutable ref, the v6 major (a v7
# bump is red ON PURPOSE, because a major is a contract change to review), the
# policy schema anchor on the same commit the scanner runs, least privilege, and
# that the scanner gates both release jobs.
#
# It reads a ROOT, so every clause is mutation-tested below against a copy.
scanner_contract() {
    node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const root = process.argv[1];
      const problems = [];
      const doc = YAML.parseDocument(readFileSync(join(root, ".github/workflows/ci.yml"), "utf8"));
      const workflow = doc.toJS();
      const job = workflow.jobs?.["supply-chain-guard"];
      if (!job) { console.error("supply-chain-guard job is missing"); process.exit(1); }

      // The scan step, and the trailing comment on its `uses:` scalar.
      const steps = doc.getIn(["jobs", "supply-chain-guard", "steps"]);
      const scanNode = (steps?.items ?? []).find((s) => String(s.get?.("uses") ?? "").startsWith("homeofe/supply-chain-guard@"));
      const scan = scanNode ? scanNode.toJSON() : null;
      const usesNode = scanNode ? scanNode.get("uses", true) : null;
      const uses = String(scan?.uses ?? "");
      const sha = (uses.match(/^homeofe\/supply-chain-guard@([0-9a-f]{40})$/) ?? [])[1];
      if (!sha) problems.push("the scanner is not pinned to a 40-hex commit: " + JSON.stringify(uses));
      const comment = String(usesNode?.comment ?? "").trim();
      if (!/^v6\.\d+\.\d+$/.test(comment)) problems.push("the scanner version comment is not a v6.x.y release: " + JSON.stringify(comment));

      // The editor schema anchor in the policy file names the same commit.
      const policyText = readFileSync(join(root, ".supply-chain-guard.yml"), "utf8");
      const anchor = (policyText.match(/\$schema=https:\/\/raw\.githubusercontent\.com\/homeofe\/supply-chain-guard\/([0-9a-f]{40})\/policy-schema\.json/) ?? [])[1];
      if (!anchor || anchor !== sha) {
        problems.push("the .supply-chain-guard.yml $schema anchor (" + anchor + ") is not the commit the scanner runs (" + sha + "); move it with the action and re-check that the policy still validates");
      }

      // Least privilege and the action contract.
      if (JSON.stringify(job.permissions) !== JSON.stringify({ contents: "read" })) problems.push("scanner permissions are not exactly contents: read");
      const checkout = (job.steps ?? []).find((s) => String(s.uses ?? "").startsWith("actions/checkout@"));
      if (checkout?.with?.["persist-credentials"] !== false) problems.push("scanner checkout persists credentials");
      if (scan?.with?.["comment-on-pr"] !== false) problems.push("scanner comment-on-pr is not false");
      if (Object.hasOwn(scan?.with ?? {}, "policy")) problems.push("scanner has a policy input the action does not define");
      if (scan?.with?.["refresh-catalog"] !== true) problems.push("scanner refresh-catalog is not true, so the historical catalog is not consulted");
      const policy = YAML.parse(policyText);
      if (!policy || Array.isArray(policy) || typeof policy !== "object" || Object.keys(policy).length !== 0) problems.push("scanner policy is not an empty object");

      // It runs on release events and gates both release jobs.
      if (Object.hasOwn(job, "if")) problems.push("the scanner job has an if: condition, so some event this workflow accepts is not scanned: " + JSON.stringify(job.if));
      const needs = (j) => [].concat(workflow.jobs?.[j]?.needs ?? []);
      if (!needs("publish").includes("supply-chain-guard")) problems.push("publish does not need supply-chain-guard");
      if (!needs("release").includes("supply-chain-guard")) problems.push("release does not need supply-chain-guard");

      for (const p of problems) console.error("  - " + p);
      if (problems.length > 0) process.exit(1);
      console.log("scanner contract OK (" + comment + ")");
    ' "$1"
}

# Copy what the contract reads, so a mutation never touches the working tree.
copy_scanner_shape() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
    cp "$AAHP_ROOT/.supply-chain-guard.yml" "$TEST_TMPDIR/.supply-chain-guard.yml"
}

# Replace the first line matching awk regex $3 inside job $2 of file $1 with $4
# (awk -v expands \n, so $4 may be several lines; empty deletes the line). Exits
# 3 when nothing matched, so a mutation that applied to nothing is never a green
# test. Lines are compared with any trailing CR removed, for a CRLF checkout.
mutate_in_job() {
    local file="$1" job="$2" re="$3" repl="$4"
    awk -v job="$job" -v re="$re" -v repl="$repl" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/) injob = (line == "  " job ":")
            if (injob && !done && line ~ re) {
                done = 1
                if (repl != "") print repl
                next
            }
            print
        }
        END { if (!done) exit 3 }
    ' "$file" > "$file.new" || { rm -f "$file.new"; return 3; }
    mv "$file.new" "$file"
}

@test "scanner contract: this repository satisfies it" {
    run scanner_contract "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scanner contract OK (v6."* ]]
}

@test "scanner contract: an untouched copy is green, so each mutation below starts there" {
    copy_scanner_shape
    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "scanner contract: a Dependabot-style bump to another v6 commit stays green" {
    # The case the old literal-SHA test got wrong: the SHA and the comment move,
    # the anchor moves with them, and nothing else changes.
    copy_scanner_shape
    local new=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    sed -i "s|homeofe/supply-chain-guard@[0-9a-f]\{40\} # v6\.[0-9.]*|homeofe/supply-chain-guard@$new # v6.9.9|" \
        "$TEST_TMPDIR/.github/workflows/ci.yml"
    sed -i "s|supply-chain-guard/[0-9a-f]\{40\}/policy-schema|supply-chain-guard/$new/policy-schema|" \
        "$TEST_TMPDIR/.supply-chain-guard.yml"
    grep -q "supply-chain-guard@$new # v6.9.9" "$TEST_TMPDIR/.github/workflows/ci.yml"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(v6.9.9)"* ]]
}

@test "scanner contract: a tag instead of a commit is red" {
    copy_scanner_shape
    sed -i 's|homeofe/supply-chain-guard@[0-9a-f]\{40\}|homeofe/supply-chain-guard@v6|' "$TEST_TMPDIR/.github/workflows/ci.yml"
    grep -q 'homeofe/supply-chain-guard@v6 ' "$TEST_TMPDIR/.github/workflows/ci.yml"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not pinned to a 40-hex commit"* ]]
}

@test "scanner contract: a major bump to v7 is red on purpose" {
    copy_scanner_shape
    sed -i '/homeofe\/supply-chain-guard@/s|# v6\.[0-9.]*|# v7.0.0|' "$TEST_TMPDIR/.github/workflows/ci.yml"
    grep -q 'supply-chain-guard@[0-9a-f]* # v7.0.0' "$TEST_TMPDIR/.github/workflows/ci.yml"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a v6.x.y release"* ]]
}

@test "scanner contract: a policy schema anchor on another commit is red" {
    copy_scanner_shape
    sed -i 's|supply-chain-guard/[0-9a-f]\{40\}/policy-schema|supply-chain-guard/0000000000000000000000000000000000000000/policy-schema|' \
        "$TEST_TMPDIR/.supply-chain-guard.yml"
    grep -q '/0000000000000000000000000000000000000000/policy-schema' "$TEST_TMPDIR/.supply-chain-guard.yml"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"anchor"*"is not the commit the scanner runs"* ]]
}

@test "scanner contract: a write permission on the scanner job is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard '^      contents: read$' '      contents: write'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not exactly contents: read"* ]]
}

@test "scanner contract: a persisted checkout credential is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard 'persist-credentials: false' '          persist-credentials: true'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"persists credentials"* ]]
}

@test "scanner contract: commenting on pull requests is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard 'comment-on-pr: false' '          comment-on-pr: true'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"comment-on-pr is not false"* ]]
}

@test "scanner contract: a policy input is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard 'comment-on-pr: false' \
        '          comment-on-pr: false\n          policy: .other-policy.yml'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"policy input the action does not define"* ]]
}

@test "scanner contract: dropping refresh-catalog is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard 'refresh-catalog: true' ''

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refresh-catalog is not true"* ]]
}

@test "scanner contract: a non-empty policy is red" {
    copy_scanner_shape
    sed -i 's|^{}|ignore: ["tests/**"]|' "$TEST_TMPDIR/.supply-chain-guard.yml"
    grep -q '^ignore:' "$TEST_TMPDIR/.supply-chain-guard.yml"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"policy is not an empty object"* ]]
}

@test "scanner contract: restoring the old tag-skipping if: is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" supply-chain-guard '^    name: Supply chain guard$' \
        "    name: Supply chain guard\n    if: github.event_name == 'pull_request' || (github.event_name == 'push' && github.ref == 'refs/heads/main')"

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has an if: condition"* ]]
}

@test "scanner contract: publish not needing the scanner is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" publish '^    needs:' '    needs: [lint-and-validate, runtime-matrix]'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"publish does not need supply-chain-guard"* ]]
}

@test "scanner contract: the GitHub Release not needing the scanner is red" {
    copy_scanner_shape
    mutate_in_job "$TEST_TMPDIR/.github/workflows/ci.yml" release '^    needs:' '    needs: publish'

    run scanner_contract "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release does not need supply-chain-guard"* ]]
}

# --- The required check's shellcheck is a pinned, verified release ------------

@test "lint-and-validate installs shellcheck from a pinned, sha256-verified release" {
    run node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const job = YAML.parse(readFileSync(join(process.argv[1], ".github/workflows/ci.yml"), "utf8")).jobs["lint-and-validate"];
      const runs = (job.steps ?? []).map((s) => String(s.run ?? ""));
      const problems = [];
      if (runs.some((r) => /apt(-get)?\s+install[^\n]*shellcheck/.test(r))) problems.push("shellcheck is installed from apt again");
      if (!/^v\d+\.\d+\.\d+$/.test(String(job.env?.SHELLCHECK_VERSION))) problems.push("SHELLCHECK_VERSION is not an exact vX.Y.Z");
      if (!/^[0-9a-f]{64}$/.test(String(job.env?.SHELLCHECK_SHA256))) problems.push("SHELLCHECK_SHA256 is not a sha256");
      const install = runs.findIndex((r) => r.includes("SHELLCHECK_SHA256") && /sha256sum -c/.test(r));
      const lint = runs.findIndex((r) => /shellcheck -x/.test(r));
      if (install === -1) problems.push("no step verifies the downloaded shellcheck against SHELLCHECK_SHA256");
      if (lint === -1 || lint < install) problems.push("the ShellCheck step does not run after the verified install");
      if (lint !== -1 && !/command -v shellcheck/.test(runs[lint])) problems.push("the ShellCheck step does not prove it runs the pinned binary");
      for (const p of problems) console.error("  - " + p);
      process.exit(problems.length > 0 ? 1 : 0);
    ' "$AAHP_ROOT"
    [ "$status" -eq 0 ]
}

# The install step, extracted from the parsed workflow and run with `curl`
# stubbed, so its fail-closed behaviour is tested without the network.
shellcheck_install_step() {
    node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const job = YAML.parse(readFileSync(join(process.argv[1], ".github/workflows/ci.yml"), "utf8")).jobs["lint-and-validate"];
      const step = job.steps.find((s) => String(s.run ?? "").includes("sha256sum -c"));
      process.stdout.write(step.run);
    ' "$AAHP_ROOT"
}

# A fake release asset laid out like the upstream one, and a `curl` that serves
# it for any URL. Prints the asset path.
stub_shellcheck_download() {
    local stage="$TEST_TMPDIR/stage" bin="$TEST_TMPDIR/stubbin"
    mkdir -p "$stage/shellcheck-v0.0.0" "$bin" "$TEST_TMPDIR/runner-temp"
    printf '#!/bin/sh\necho "version: 0.0.0"\n' > "$stage/shellcheck-v0.0.0/shellcheck"
    chmod +x "$stage/shellcheck-v0.0.0/shellcheck"
    tar -cJf "$TEST_TMPDIR/fake.tar.xz" -C "$stage" shellcheck-v0.0.0
    cat > "$bin/curl" <<EOF
#!/bin/sh
# Serve the fake asset to whatever -o names.
while [ \$# -gt 0 ]; do
    if [ "\$1" = "-o" ]; then cp "$TEST_TMPDIR/fake.tar.xz" "\$2"; fi
    shift
done
EOF
    chmod +x "$bin/curl"
}

@test "the shellcheck install fails closed on a hash mismatch, before extracting" {
    command -v xz >/dev/null 2>&1 || skip "xz is not installed"
    stub_shellcheck_download
    shellcheck_install_step > "$TEST_TMPDIR/install.sh"
    : > "$TEST_TMPDIR/github-path"

    run env PATH="$TEST_TMPDIR/stubbin:$PATH" RUNNER_TEMP="$TEST_TMPDIR/runner-temp" \
        GITHUB_PATH="$TEST_TMPDIR/github-path" SHELLCHECK_VERSION=v0.0.0 \
        SHELLCHECK_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
        bash --noprofile --norc -eo pipefail "$TEST_TMPDIR/install.sh"
    [ "$status" -ne 0 ]
    [ ! -s "$TEST_TMPDIR/github-path" ]
    [ ! -e "$TEST_TMPDIR/runner-temp/shellcheck-bin/shellcheck" ]
}

@test "the shellcheck install extracts the verified binary and puts it first on PATH" {
    command -v xz >/dev/null 2>&1 || skip "xz is not installed"
    stub_shellcheck_download
    shellcheck_install_step > "$TEST_TMPDIR/install.sh"
    : > "$TEST_TMPDIR/github-path"
    local sum
    sum="$(sha256sum "$TEST_TMPDIR/fake.tar.xz" | cut -c1-64)"

    run env PATH="$TEST_TMPDIR/stubbin:$PATH" RUNNER_TEMP="$TEST_TMPDIR/runner-temp" \
        GITHUB_PATH="$TEST_TMPDIR/github-path" SHELLCHECK_VERSION=v0.0.0 SHELLCHECK_SHA256="$sum" \
        bash --noprofile --norc -eo pipefail "$TEST_TMPDIR/install.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/github-path")" = "$TEST_TMPDIR/runner-temp/shellcheck-bin" ]
    run "$TEST_TMPDIR/runner-temp/shellcheck-bin/shellcheck"
    [ "$output" = "version: 0.0.0" ]
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

# Red controls for the assertion above. It was only ever run in the green
# direction, so an assertion that always printed OK would have passed too. Each
# test mutates ONE thing in a copy of the real package.json (node on parsed
# JSON), proves the mutation landed, and expects exit 1.
pinning_wiring_copy() {
    cp "$AAHP_ROOT/package.json" "$AAHP_ROOT/package-lock.json" "$TEST_TMPDIR/"
}
pinning_wiring_mutate() {
    node -e '
      const fs = require("fs"), p = process.argv[1] + "/package.json";
      const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
      new Function("pkg", process.argv[2])(pkg);
      fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
    ' "$TEST_TMPDIR" "$1"
}

@test "wiring red control: the untouched copy is green" {
    pinning_wiring_copy
    run node "$AAHP_ROOT/tests/assert-pinning-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinning gate wiring OK"* ]]
}

@test "wiring red control: dropping the gate from the check chain is red" {
    pinning_wiring_copy
    pinning_wiring_mutate 'pkg.scripts.check = pkg.scripts.check.replace(" && npm run check:workflow-pinning", "")'
    # Landed: only the script's own key still names the gate.
    run grep -c "check:workflow-pinning" "$TEST_TMPDIR/package.json"
    [ "$output" = "1" ]
    run node "$AAHP_ROOT/tests/assert-pinning-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not part of the aggregate"* ]]
}

@test "wiring red control: a range instead of an exact ajv-cli pin is red" {
    pinning_wiring_copy
    pinning_wiring_mutate 'pkg.devDependencies["ajv-cli"] = "^" + pkg.devDependencies["ajv-cli"]'
    grep -q '"ajv-cli": "\^' "$TEST_TMPDIR/package.json"
    run node "$AAHP_ROOT/tests/assert-pinning-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ajv-cli is declared as"*"not an exact version"* ]]
}
