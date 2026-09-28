#!/usr/bin/env bats
# handoff-impact-npm.bats - Layer 2 opt-in: content-verified npm devDependency
# updates (handoffImpact.npmDevDependencyUpdates).
#
# The exemption is decided by the CONTENT of the change set, never by who made
# it. Every guard below has a test that turns red when that guard is removed:
# a lock entry without dev:true, a resolved URL off the public registry, a
# missing integrity, any other file in the change set, a runtime dependency in
# package.json, the opt-in absent, and the scanner assertion missing or naming a
# job that does not exist or does not run on pull requests.

setup() {
    load test_helper
    setup
    create_full_handoff
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "seed handoff"
    bash "$SCRIPTS_DIR/aahp-manifest.sh" "$TEST_TMPDIR" --quiet --phase implementation
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "manifest"

    write_package_fixture
    write_workflow
    write_optin_config
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "npm fixture"
    NPM_BASE="$(git -C "$TEST_TMPDIR" rev-parse HEAD)"
}

teardown() {
    teardown
}

# package.json + a lockfileVersion 3 lock with one devDependency and one
# runtime dependency, both resolved from the public registry.
write_package_fixture() {
    node -e '
const fs = require("fs");
const dir = process.argv[1];
const pkg = {
  name: "fixture", version: "1.0.0", license: "MIT",
  dependencies: { "rt-lib": "1.0.0" },
  devDependencies: { "dev-tool": "^1.0.0" }
};
const lock = {
  name: "fixture", version: "1.0.0", lockfileVersion: 3, requires: true,
  packages: {
    "": { name: "fixture", version: "1.0.0", license: "MIT",
          dependencies: { "rt-lib": "1.0.0" }, devDependencies: { "dev-tool": "^1.0.0" } },
    "node_modules/dev-tool": { version: "1.0.0",
      resolved: "https://registry.npmjs.org/dev-tool/-/dev-tool-1.0.0.tgz",
      integrity: "sha512-" + "A".repeat(86) + "==", dev: true },
    "node_modules/rt-lib": { version: "1.0.0",
      resolved: "https://registry.npmjs.org/rt-lib/-/rt-lib-1.0.0.tgz",
      integrity: "sha512-" + "B".repeat(86) + "==" }
  }
};
fs.writeFileSync(dir + "/package.json", JSON.stringify(pkg, null, 2) + "\n");
fs.writeFileSync(dir + "/package-lock.json", JSON.stringify(lock, null, 2) + "\n");
' "$TEST_TMPDIR"
}

write_workflow() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cat > "$TEST_TMPDIR/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo test
  supply-chain-guard:
    name: Supply chain guard
    if: github.event_name == 'pull_request' || github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000 # v0
      - run: |
          if: this line is inside a block scalar and is not the job condition
          echo scan
EOF
}

# $1 = job id (default supply-chain-guard), $2 = workflow path
write_optin_config() {
    local job="${1:-supply-chain-guard}"
    local workflow="${2:-.github/workflows/ci.yml}"
    node -e '
const fs = require("fs");
const cfg = { handoffImpact: { npmDevDependencyUpdates: {
  reason: "Registry-pinned devDependency lockfile updates change no shipped file and no runtime dependency.",
  supplyChainScan: { workflow: process.argv[3], job: process.argv[2] } } } };
fs.writeFileSync(process.argv[1] + "/aahp.config.json", JSON.stringify(cfg, null, 2) + "\n");
' "$TEST_TMPDIR" "$job" "$workflow"
}

# Bump dev-tool to 1.0.1 in the lock, staged. Options (any order):
#   pkg        also bump the package.json and lock-root devDependency specifier
#   nodev      drop dev:true from the bumped entry
#   offreg     resolve the bumped entry from a non-registry URL
#   nointeg    drop the integrity of the bumped entry
#   install    give the bumped entry hasInstallScript: true
#   noinstall  give the bumped entry an explicit hasInstallScript: false
#   runtime    bump the runtime dependency rt-lib instead
#   runtimepkg change package.json runtime "dependencies" as well
bump() {
    node -e '
const fs = require("fs");
const dir = process.argv[1];
const opts = new Set(process.argv.slice(2));
const lock = JSON.parse(fs.readFileSync(dir + "/package-lock.json", "utf8"));
const pkg = JSON.parse(fs.readFileSync(dir + "/package.json", "utf8"));
const name = opts.has("runtime") ? "rt-lib" : "dev-tool";
const entry = lock.packages["node_modules/" + name];
entry.version = "1.0.1";
entry.resolved = "https://registry.npmjs.org/" + name + "/-/" + name + "-1.0.1.tgz";
entry.integrity = "sha512-" + "C".repeat(86) + "==";
if (opts.has("nodev")) delete entry.dev;
if (opts.has("offreg")) entry.resolved = "https://evil.example.com/" + name + "-1.0.1.tgz";
if (opts.has("nointeg")) delete entry.integrity;
if (opts.has("install")) entry.hasInstallScript = true;
if (opts.has("noinstall")) entry.hasInstallScript = false;
if (opts.has("pkg")) {
  pkg.devDependencies["dev-tool"] = "^1.0.1";
  lock.packages[""].devDependencies["dev-tool"] = "^1.0.1";
}
if (opts.has("runtimepkg")) {
  pkg.dependencies["rt-lib"] = "1.0.1";
  lock.packages[""].dependencies["rt-lib"] = "1.0.1";
}
fs.writeFileSync(dir + "/package-lock.json", JSON.stringify(lock, null, 2) + "\n");
fs.writeFileSync(dir + "/package.json", JSON.stringify(pkg, null, 2) + "\n");
' "$TEST_TMPDIR" "$@"
    git -C "$TEST_TMPDIR" add package-lock.json package.json
}

verify_precommit() {
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
}

# --- The exemption applies -----------------------------------

@test "npm opt-in: a registry-pinned devDependency lock update is non-impacting" {
    bump
    verify_precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"npm devDependency exemption configured: job 'supply-chain-guard' in .github/workflows/ci.yml runs on pull_request."* ]]
    [[ "$output" == *"Content-verified npm devDependency update: package-lock.json (1 lock entr(ies) checked"* ]]
    [[ "$output" == *"Reason: Registry-pinned devDependency lockfile updates"* ]]
    [[ "$output" == *"Drift gate not triggered"* ]]
}

@test "npm opt-in: lock plus a devDependencies version specifier in package.json is non-impacting" {
    bump pkg
    verify_precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Content-verified npm devDependency update: package-lock.json, package.json"* ]]
}

@test "npm opt-in: CI compares the base commit with HEAD" {
    bump pkg
    git -C "$TEST_TMPDIR" commit -q -m "bump dev-tool"
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level ci --base "$NPM_BASE"
    [[ "$output" == *"Content-verified npm devDependency update: package-lock.json, package.json"* ]]
    [[ "$output" != *"Handoff-impacting files changed but handoff state did not"* ]]
}

# --- Each guard, mutated -------------------------------------

@test "npm opt-in guard: a changed lock entry without dev:true stays impacting" {
    bump nodev
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"npm devDependency exemption not applied"* ]]
    [[ "$output" == *"\"node_modules/dev-tool\" is not dev: true"* ]]
}

@test "npm opt-in guard: a resolved URL off the public registry stays impacting" {
    bump offreg
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"\"node_modules/dev-tool\" is not resolved under https://registry.npmjs.org/"* ]]
}

@test "npm opt-in guard: a missing integrity stays impacting" {
    bump nointeg
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"\"node_modules/dev-tool\" has no sha256/384/512 integrity"* ]]
}

@test "npm opt-in guard: an update that INTRODUCES an install script stays impacting" {
    # hasInstallScript flips from absent to true. `npm ci` without
    # --ignore-scripts would run it, on developer machines too.
    bump install
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"\"node_modules/dev-tool\" has an install script (hasInstallScript: true)"* ]]
    [[ "$output" != *"Content-verified npm devDependency update"* ]]
}

@test "npm opt-in guard: an update that KEEPS an existing install script stays impacting" {
    # The baseline entry already carries an install script; a plain version bump
    # that keeps it is still an update to code that runs at install time.
    node -e '
const fs = require("fs");
const p = process.argv[1] + "/package-lock.json";
const lock = JSON.parse(fs.readFileSync(p, "utf8"));
lock.packages["node_modules/dev-tool"].hasInstallScript = true;
fs.writeFileSync(p, JSON.stringify(lock, null, 2) + "\n");
' "$TEST_TMPDIR"
    git -C "$TEST_TMPDIR" add package-lock.json
    git -C "$TEST_TMPDIR" commit -q -m "baseline dev entry with an install script"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"\"node_modules/dev-tool\" has an install script (hasInstallScript: true)"* ]]
}

@test "npm opt-in: an explicit hasInstallScript false does not block the exemption" {
    # The other direction: only a TRUE flag disqualifies an entry.
    bump noinstall
    verify_precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Content-verified npm devDependency update: package-lock.json"* ]]
}

@test "npm opt-in guard: a runtime dependency lock entry stays impacting" {
    bump runtime
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"\"node_modules/rt-lib\" was not dev: true before this change"* ]]
}

@test "npm opt-in guard: a package.json runtime dependencies change stays impacting" {
    bump pkg runtimepkg
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"package.json changed outside devDependencies: dependencies"* ]]
}

@test "npm opt-in guard: any other file in the change set stays impacting" {
    bump
    printf 'docs\n' > "$TEST_TMPDIR/README.md"
    git -C "$TEST_TMPDIR" add README.md
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a modification of package-lock.json (optionally with package.json) and nothing else"* ]]
    [[ "$output" == *"A README.md"* ]]
    [[ "$output" == *"M package-lock.json"* ]]
}

@test "npm opt-in: an ordinary change that does not touch the lockfile gets no exemption note" {
    printf 'docs\n' > "$TEST_TMPDIR/README.md"
    git -C "$TEST_TMPDIR" add README.md
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
    [[ "$output" != *"exemption not applied"* ]]
}

@test "npm opt-in guard: a workflow file in the change set stays impacting" {
    bump
    printf '# edited\n' >> "$TEST_TMPDIR/.github/workflows/ci.yml"
    git -C "$TEST_TMPDIR" add .github/workflows/ci.yml
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"M .github/workflows/ci.yml"* ]]
    [[ "$output" != *"Content-verified npm devDependency update"* ]]
}

@test "npm opt-in guard: without the opt-in key the same lock update stays impacting" {
    printf '{ "handoffImpact": { "nonImpactingModifiedFiles": [] } }\n' > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "drop the opt-in"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
    [[ "$output" != *"npm devDependency exemption"* ]]
}

@test "npm opt-in guard: an opt-in without the scanner assertion is invalid configuration" {
    printf '%s\n' '{ "handoffImpact": { "npmDevDependencyUpdates": { "reason": "Lockfile-only updates." } } }' \
        > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "opt-in without a scanner"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid handoffImpact configuration"* ]]
    [[ "$output" == *"must contain exactly reason and supplyChainScan"* ]]
    [[ "$output" != *"Content-verified npm devDependency update"* ]]
}

@test "npm opt-in guard: a scanner assertion naming a job that does not exist fails" {
    write_optin_config "no-such-job"
    git -C "$TEST_TMPDIR" add aahp.config.json
    git -C "$TEST_TMPDIR" commit -q -m "point at a missing job"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a supply-chain scan on pull requests, and the inspected snapshot does not show one"* ]]
    [[ "$output" == *"job no-such-job is not defined under jobs:"* ]]
    [[ "$output" != *"Content-verified npm devDependency update"* ]]
}

@test "npm opt-in guard: the assertion is checked on every run, not only on lock updates" {
    # Deleting the scanner while the opt-in stays must fail in that very change.
    write_optin_config "no-such-job"
    git -C "$TEST_TMPDIR" add aahp.config.json
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"job no-such-job is not defined under jobs:"* ]]
}

@test "npm opt-in guard: a workflow that is not triggered by pull_request fails" {
    cat > "$TEST_TMPDIR/.github/workflows/ci.yml" <<'EOF'
on:
  push:
    branches: [main]
  pull_request_target:
    branches: [main]
jobs:
  supply-chain-guard:
    runs-on: ubuntu-latest
    steps:
      - run: echo scan
EOF
    git -C "$TEST_TMPDIR" add .github/workflows/ci.yml
    git -C "$TEST_TMPDIR" commit -q -m "scanner only on push"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"the workflow is not triggered by pull_request"* ]]
}

@test "npm opt-in guard: a job condition that does not name pull_request fails" {
    cat > "$TEST_TMPDIR/.github/workflows/ci.yml" <<'EOF'
on: [push, pull_request]
jobs:
  supply-chain-guard:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - run: echo scan
EOF
    git -C "$TEST_TMPDIR" add .github/workflows/ci.yml
    git -C "$TEST_TMPDIR" commit -q -m "scanner skipped on pull requests"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"has an if: condition that does not name pull_request"* ]]
}

@test "npm opt-in guard: a continue-on-error scanner job fails" {
    cat > "$TEST_TMPDIR/.github/workflows/ci.yml" <<'EOF'
on:
  - push
  - pull_request
jobs:
  "supply-chain-guard":
    continue-on-error: true
    runs-on: ubuntu-latest
    steps:
      - run: echo scan
EOF
    git -C "$TEST_TMPDIR" add .github/workflows/ci.yml
    git -C "$TEST_TMPDIR" commit -q -m "scanner cannot fail"
    bump
    verify_precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"sets continue-on-error, so its failure could not block a merge"* ]]
}

@test "npm opt-in: without node the exemption is not applied (fail closed)" {
    local stub="$TEST_TMPDIR/stub-nonode"
    rm -rf "$stub"
    cp -r "$SCRIPTS_DIR" "$stub"
    sed 's/command -v node &>\/dev\/null/false/g' "$SCRIPTS_DIR/_aahp-lib.sh" > "$stub/_aahp-lib.sh"
    local py
    py="$(bash -c "source '$SCRIPTS_DIR/_aahp-lib.sh'; aahp_python_cmd")"
    [ -n "$py" ] || skip "no working python interpreter"
    bump
    run bash "$stub/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"node is not available to parse package-lock.json"* ]]
}

# --- Parsers and the workflow reader -------------------------

@test "npm opt-in: both config parsers refuse malformed npmDevDependencyUpdates shapes" {
    local fallback_lib value
    fallback_lib="$TEST_TMPDIR/python-lib.sh"
    sed 's/command -v node &>\/dev\/null/false/g' "$SCRIPTS_DIR/_aahp-lib.sh" > "$fallback_lib"
    local cases=(
        '{"handoffImpact":{}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":true}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"x"},"extra":1}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"...","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":"ci.yml","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/../x.yml","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.json","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"1bad"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"x","actor":"dependabot"}}}}'
    )
    for value in "${cases[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/aahp.config.json"
        run bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
        [ "$status" -ne 0 ] || { echo "Node accepted: $value"; false; }
        run bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ "$fallback_lib" "$TEST_TMPDIR/aahp.config.json"
        [ "$status" -ne 0 ] || { echo "Python accepted: $value"; false; }
    done

    # The valid shape, alone (no nonImpactingModifiedFiles), is accepted by both.
    write_optin_config
    run bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ "$SCRIPTS_DIR/_aahp-lib.sh" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
    run bash -c 'source "$1"; aahp_non_impacting_modified_files "$2"' _ "$fallback_lib" "$TEST_TMPDIR/aahp.config.json"
    [ "$status" -eq 0 ]
}

@test "the config schema agrees with the runtime parsers on the new keys" {
    # CI's ajv validator (scripts/validate-json-schema.mjs). It exits 2 when ajv
    # is not installed, so a broken install is red here rather than a skip.
    local validator="$SCRIPTS_DIR/validate-json-schema.mjs"
    local value
    local invalid=(
        '{"handoffImpact":{}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r"}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"...","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":"ci.yml","job":"x"}}}}'
        '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"1bad"}}}}'
        '{"trustTtl":{"graceDays":-1}}'
        '{"trustTtl":{"graceDays":366}}'
        '{"trustTtl":{"graceDays":1.5}}'
        '{"trustTtl":{"checks":[{"id":"license-matches","run":["git"],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git",""],"reason":"r"}]}}'
        '{"trustTtl":{"checks":[{"id":"a","run":["git"]}]}}'
    )
    for value in "${invalid[@]}"; do
        printf '%s\n' "$value" > "$TEST_TMPDIR/candidate.json"
        run node "$validator" "$AAHP_ROOT/schema/aahp-config.schema.json" "$TEST_TMPDIR/candidate.json"
        [ "$status" -eq 1 ] || { echo "ajv did not reject ($status): $value $output"; false; }
        # The zero-dependency validator doctor and check run must agree.
        run node --input-type=module -e '
import { pathToFileURL } from "node:url";
import { readFileSync } from "node:fs";
const { validateConfigObject } = await import(pathToFileURL(process.argv[1]).href);
let errors;
try { errors = validateConfigObject(JSON.parse(readFileSync(process.argv[2], "utf8"))); }
catch (e) { console.log(e.message); process.exit(2); }
process.exit(errors.length ? 1 : 0);
' "$AAHP_ROOT/scripts/aahp-schema.mjs" "$TEST_TMPDIR/candidate.json"
        [ "$status" -eq 1 ] || { echo "aahp-schema accepted (or threw): $value ($status) $output"; false; }
    done
    # And both validators accept this repository's own config and the example.
    local cfg
    for cfg in "$AAHP_ROOT/aahp.config.json" "$AAHP_ROOT/aahp.config.example.json"; do
        run node --input-type=module -e '
import { pathToFileURL } from "node:url";
import { readFileSync } from "node:fs";
const { validateConfigObject } = await import(pathToFileURL(process.argv[1]).href);
const errors = validateConfigObject(JSON.parse(readFileSync(process.argv[2], "utf8")));
if (errors.length) { console.log(JSON.stringify(errors)); process.exit(1); }
' "$AAHP_ROOT/scripts/aahp-schema.mjs" "$cfg"
        [ "$status" -eq 0 ] || { echo "$cfg: $output"; false; }
    done
    printf '%s\n' '{"handoffImpact":{"npmDevDependencyUpdates":{"reason":"r","supplyChainScan":{"workflow":".github/workflows/ci.yml","job":"supply-chain-guard"}}},"trustTtl":{"enforce":true,"graceDays":0,"checks":[{"id":"a-b","run":["git","status"],"reason":"Reviewed."}]}}' \
        > "$TEST_TMPDIR/candidate.json"
    run node "$validator" "$AAHP_ROOT/schema/aahp-config.schema.json" "$TEST_TMPDIR/candidate.json"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"candidate.json valid"* ]]
}

@test "workflow reader: this repository's own scanner and verify jobs are proven to run on pull_request" {
    run bash -c 'source "$1"; aahp_workflow_job_on_pull_request supply-chain-guard < "$2"' _ \
        "$SCRIPTS_DIR/_aahp-lib.sh" "$AAHP_ROOT/.github/workflows/ci.yml"
    [ "$status" -eq 0 ]
    run bash -c 'source "$1"; aahp_workflow_job_on_pull_request aahp-verify < "$2"' _ \
        "$SCRIPTS_DIR/_aahp-lib.sh" "$AAHP_ROOT/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 0 ]
    # And a job that ci.yml does not define is not.
    run bash -c 'source "$1"; aahp_workflow_job_on_pull_request supply-chain-guardx < "$2"' _ \
        "$SCRIPTS_DIR/_aahp-lib.sh" "$AAHP_ROOT/.github/workflows/ci.yml"
    [ "$status" -eq 1 ]
}

@test "this repository opts in, and its opt-in validates against the live workflow" {
    run node -e '
const cfg = require(process.argv[1]);
const npm = cfg.handoffImpact && cfg.handoffImpact.npmDevDependencyUpdates;
if (!npm) { console.log("absent"); process.exit(1); }
console.log(npm.supplyChainScan.workflow + " " + npm.supplyChainScan.job);
' "$AAHP_ROOT/aahp.config.json"
    [ "$status" -eq 0 ]
    [ "$output" = ".github/workflows/ci.yml supply-chain-guard" ]
}
