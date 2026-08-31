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
# lane rule F requires; with one, that argument is the whole `updates:` body.
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
      interval: "weekly"'

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

@test "the supply-chain scanner is least-privilege and its policy starts empty" {
    run node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const root = process.argv[1];
      const workflow = YAML.parse(readFileSync(join(root, ".github/workflows/ci.yml"), "utf8"));
      const job = workflow.jobs?.["supply-chain-guard"];
      if (!job) throw new Error("supply-chain-guard job is missing");
      if (JSON.stringify(job.permissions) !== JSON.stringify({ contents: "read" })) {
        throw new Error("scanner permissions are not exactly contents: read");
      }
      const checkout = job.steps?.find((step) => String(step.uses ?? "").startsWith("actions/checkout@"));
      if (checkout?.with?.["persist-credentials"] !== false) {
        throw new Error("scanner checkout persists credentials");
      }
      const scan = job.steps?.find((step) => String(step.uses ?? "").startsWith("homeofe/supply-chain-guard@"));
      if (scan?.uses !== "homeofe/supply-chain-guard@2ba749d08e19b4d5c75c71467233987748f8e8c7") {
        throw new Error("scanner is not pinned to the reviewed v6.0.8 release commit");
      }
      if (scan.with?.["comment-on-pr"] !== false || Object.hasOwn(scan.with ?? {}, "policy")) {
        throw new Error("scanner inputs do not match the action contract");
      }
      const policy = YAML.parse(readFileSync(join(root, ".supply-chain-guard.yml"), "utf8"));
      if (!policy || Array.isArray(policy) || Object.keys(policy).length !== 0) {
        throw new Error("initial scanner policy is not an empty object");
      }
    ' "$AAHP_ROOT"
    [ "$status" -eq 0 ]
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
