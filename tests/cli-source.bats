#!/usr/bin/env bats
# cli-source.bats - the doctor gate that asks where a workflow gets the aahp CLI.
#
# Adopters copied earlier versions of the shipped workflows, and a copy does not
# update with the package. scripts/check-cli-source.mjs (its header lists the
# shapes and the severity rule) finds the legacy ones; `aahp doctor` reports them
# as the `cli-source` gate with the remediation `aahp init --gates --workflows`.
# Every legacy shape is asserted red, the shipped templates and the package
# itself are asserted clean, and the remediation is run end to end.

load test_helper

GATE="$AAHP_ROOT/scripts/check-cli-source.mjs"
AAHP="$AAHP_ROOT/bin/aahp.js"
FIXTURES="$AAHP_ROOT/tests/fixtures/workflows"

# Install fixture $1 as .github/workflows/$2.
install_as() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$FIXTURES/$1" "$TEST_TMPDIR/.github/workflows/$2"
}

# Write workflow $1 (a file name) with the literal body on stdin.
write_workflow() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cat > "$TEST_TMPDIR/.github/workflows/$1"
}

# An adopter: a root package.json that is NOT the package itself.
consumer_pkg() {
    printf '{"name":"consumer-app","version":"1.0.0","devDependencies":{"@elvatis_com/aahp":"4.0.0"}}\n' \
        > "$TEST_TMPDIR/package.json"
}

# --- the current adopter workflows pass ---------------------------------------

@test "cli-source: the SHIPPED aahp-verify.yml and aahp-govern.yml pass in an adopter" {
    consumer_pkg
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/assets/governance/aahp-verify.yml" "$AAHP_ROOT/assets/governance/aahp-govern.yml" \
        "$TEST_TMPDIR/.github/workflows/"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "pass"'* ]]
    [[ "$output" == *"4 aahp CLI invocation(s) in workflows, none of a legacy shape"* ]]
}

# --- each legacy shape is reported, with the remediation ---------------------

@test "cli-source: npx -y @elvatis_com/aahp@<version> is a registry fetch and FAILS doctor" {
    consumer_pkg
    install_as legacy-npx-version.yml aahp-verify.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"legacy workflow [registry-fetch]"* ]]
    [[ "$output" == *"npx -y @elvatis_com/aahp@3.10.0 verify . --level ci"* ]]
    [[ "$output" == *"REMEDIATION: run aahp init --gates --workflows"* ]]
    # The skippability gate has nothing to say about this file: different question.
    [[ "$output" == *'"verify-workflow": "pass"'* ]]
}

@test "cli-source: npx aahp without --no-install is the unowned name and FAILS doctor" {
    consumer_pkg
    write_workflow aahp-govern.yml <<'EOF'
name: AAHP Govern
on:
  pull_request:
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci --ignore-scripts
      - run: npx aahp check .
      - run: npx aahp doctor --governance --json .
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"legacy workflow [unowned-name]"* ]]
    [[ "$output" == *"downloads and executes whatever the registry returns"* ]]
}

@test "cli-source: npm exec --no-install aahp FAILS too, because npm exec ignores the flag" {
    consumer_pkg
    write_workflow aahp-govern.yml <<'EOF'
name: AAHP Govern
on:
  pull_request:
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci --ignore-scripts
      - run: npm exec --no-install aahp -- check .
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"[unowned-name]"* ]]
}

@test "cli-source: npx --no-install aahp after npm ci is ADVISORY: named, remediated, not failing" {
    consumer_pkg
    install_as legacy-npx-unscoped.yml aahp-govern.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "advisory"'* ]]
    [[ "$output" != *'"cli-source": "pass"'* ]]
    [[ "$output" == *"legacy workflow [unowned-name]"* ]]
    [[ "$output" == *"fails closed"* ]]
    [[ "$output" == *"REMEDIATION: run aahp init --gates --workflows"* ]]
    # The gate script's own summary must not read OK under those findings.
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"check-cli-source: ADVISORY - 2 advisory finding(s) in 2 invocation(s)"* ]]
    [[ "$output" != *"check-cli-source: OK"* ]]
}

@test "cli-source: the CLI from node_modules with no install step before it FAILS doctor" {
    consumer_pkg
    install_as legacy-no-install.yml aahp-govern.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"legacy workflow [no-install]"* ]]
    [[ "$output" == *"no earlier step in job"* ]]
}

@test "cli-source: node bin/aahp.js in an adopter is a checkout path and FAILS doctor" {
    consumer_pkg
    install_as legacy-checkout-cli.yml aahp-verify.yml
    [ ! -e "$TEST_TMPDIR/bin/aahp.js" ]
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"legacy workflow [checkout-path]"* ]]
    [[ "$output" == *"MODULE_NOT_FOUND"* ]]
}

# --- what must NOT be flagged -------------------------------------------------

@test "cli-source: the SAME checkout-path workflow in the package itself is self, not a finding" {
    install_as legacy-checkout-cli.yml aahp-verify.yml
    printf '{"name":"@elvatis_com/aahp","version":"0.0.0"}\n' > "$TEST_TMPDIR/package.json"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "self"'* ]]
    [[ "$output" != *"checkout-path"* ]]
}

@test "cli-source: AAHP's own workflows are self (dogfood)" {
    run node "$AAHP" doctor "$AAHP_ROOT" --json
    [[ "$output" == *'"cli-source": "self"'* ]]
}

@test "cli-source: a repository that HAS bin/aahp.js (a fork, a vendored copy) is not flagged" {
    consumer_pkg
    install_as legacy-checkout-cli.yml aahp-verify.yml
    mkdir -p "$TEST_TMPDIR/bin"
    printf '// vendored\n' > "$TEST_TMPDIR/bin/aahp.js"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "pass"'* ]]
}

@test "cli-source: npx --no-install with the SCOPED name after npm ci is clean" {
    consumer_pkg
    write_workflow aahp-govern.yml <<'EOF'
name: AAHP Govern
on:
  pull_request:
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci --ignore-scripts
      - run: npx --no-install @elvatis_com/aahp check .
      - run: npx --no-install @elvatis_com/aahp doctor --governance --json .
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "pass"'* ]]
}

@test "cli-source: pnpm install counts as the install step" {
    consumer_pkg
    write_workflow aahp-govern.yml <<'EOF'
name: AAHP Govern
on:
  pull_request:
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pnpm install --frozen-lockfile
      - run: node ./node_modules/@elvatis_com/aahp/bin/aahp.js check .
      - run: node ./node_modules/@elvatis_com/aahp/bin/aahp.js doctor --governance --json .
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"cli-source": "pass"'* ]]
}

@test "cli-source: an install that may happen inside an action is undecidable, never a no-install finding" {
    consumer_pkg
    write_workflow aahp-govern.yml <<'EOF'
name: AAHP Govern
on:
  pull_request:
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup
      - run: node ./node_modules/@elvatis_com/aahp/bin/aahp.js check .
      - run: node ./node_modules/@elvatis_com/aahp/bin/aahp.js doctor --governance --json .
EOF
    run node "$GATE" "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"invocations": 2'* ]]
    [[ "$output" != *"no-install"* ]]
}

@test "cli-source: no workflow invokes the CLI (npm run govern) is skip, not pass" {
    consumer_pkg
    write_workflow ci.yml <<'EOF'
name: CI
on:
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: npm ci --ignore-scripts
      - run: npm run govern
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [[ "$output" == *'"cli-source": "skip"'* ]]
}

@test "cli-source: a workflow that mentions aahp and cannot be parsed fails, it does not skip" {
    consumer_pkg
    printf '# runs aahp\nname: broken\njobs: {unterminated\n' > "$TEST_TMPDIR/aahp-broken.yml"
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    mv "$TEST_TMPDIR/aahp-broken.yml" "$TEST_TMPDIR/.github/workflows/"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNDECIDED"* ]]
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
}

# --- the remediation, end to end ---------------------------------------------

@test "cli-source: the named remediation, aahp init --gates --workflows, clears the finding" {
    consumer_pkg
    install_as legacy-no-install.yml aahp-govern.yml
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cli-source": "fail"'* ]]
    [[ "$output" == *"REMEDIATION: run aahp init --gates --workflows"* ]]

    run node "$AAHP" init "$TEST_TMPDIR" --gates --workflows
    [ "$status" -eq 0 ]
    cmp -s "$AAHP_ROOT/assets/governance/aahp-govern.yml" "$TEST_TMPDIR/.github/workflows/aahp-govern.yml"

    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [[ "$output" == *'"cli-source": "pass"'* ]]
    [[ "$output" != *"legacy workflow"* ]]
}
