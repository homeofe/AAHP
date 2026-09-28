#!/usr/bin/env bats
# workflow-hardening.bats - every workflow this repository runs, and every
# workflow it SHIPS, declares its own GITHUB_TOKEN permissions and keeps that
# token out of the job workspace.
#
# Every test asserts in BOTH directions: the property holds on the real
# repository, and each way of breaking it turns the gate red with an EXACT exit
# code. A gate proved only in the passing direction is indistinguishable from a
# gate that cannot fail, and "non-zero" hides the difference between "found a
# problem" (1) and "could not decide" (2).
#
# The load-bearing test is the first one. It runs the gate over the real
# repository, so deleting the `permissions:` block from
# assets/governance/aahp-govern.yml - the file adopters actually receive - is
# what turns it red.

load test_helper

GATE="$AAHP_ROOT/tests/assert-workflow-hardening.mjs"
SHAPE_GATE="$AAHP_ROOT/tests/assert-repo-ci-shape.mjs"

# The gate scans two roots. Both must exist and hold at least one document, so
# every fixture writes both.
wf_dir() { printf '%s/.github/workflows' "$TEST_TMPDIR"; }
asset_dir() { printf '%s/assets/governance' "$TEST_TMPDIR"; }

# The baseline fixture: one compliant document in each scan root. Every mutation
# below starts from this and breaks exactly ONE thing, so a red result can only
# have been caused by that one change.
write_good_tree() {
    mkdir -p "$(wf_dir)" "$(asset_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
permissions:
  contents: read
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - run: echo build
EOF
    cat > "$(asset_dir)/shipped.yml" <<'EOF'
name: fx shipped
permissions:
  contents: read
on: [push]
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - run: echo govern
EOF
}

# --- The load-bearing assertions: the real repository -----------------------

@test "this repository's own workflows and its shipped template are hardened" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow hardening gate OK"* ]]
    # The counts are printed so a CI log carries the evidence, not just a verdict.
    [[ "$output" == *"without top-level permissions : 0"* ]]
}

@test "every checkout in this repository is counted, and every one is hardened" {
    # Guards the vacuity trap: a gate that found zero checkouts would also print
    # "OK". The two numbers must be equal AND non-zero.
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    total="$(printf '%s\n' "$output" | sed -n 's/^actions\/checkout steps *: //p')"
    hardened="$(printf '%s\n' "$output" | sed -n 's/^  persist-credentials: false *: //p')"
    [ -n "$total" ]
    [ "$total" -gt 0 ]
    [ "$total" -eq "$hardened" ]
}

@test "the shipped governance template carries both properties" {
    # Asserted directly against the asset, not through the gate, so a gate that
    # stopped looking at assets/governance/ cannot hide the regression here.
    asset="$AAHP_ROOT/assets/governance/aahp-govern.yml"
    [ "$(grep -c '^permissions:' "$asset")" -eq 1 ]
    # Leading-whitespace anchor, so the header comment that EXPLAINS the setting
    # is not counted as the setting. No trailing '$': a Windows working tree has
    # CRLF here and an end anchor would match nothing while still matching on CI.
    [ "$(grep -c '^ *persist-credentials: false' "$asset")" -eq 1 ]
}

@test "what aahp init --gates writes into a consumer is the hardened template" {
    # The end of the delivery path: this is the file an adopter actually runs.
    run node "$AAHP_ROOT/bin/aahp.js" init --gates "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    written="$TEST_TMPDIR/.github/workflows/aahp-govern.yml"
    [ -f "$written" ]
    [ "$(grep -c '^permissions:' "$written")" -eq 1 ]
    [ "$(grep -c '^ *persist-credentials: false' "$written")" -eq 1 ]
}

@test "the baseline fixture passes, so every mutation below starts from green" {
    write_good_tree
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow hardening gate OK"* ]]
}

# --- Mutation: the top-level permissions block ------------------------------

@test "a workflow with no top-level permissions block exits 1" {
    write_good_tree
    # Remove the two-line block from the .github/workflows document only.
    sed -i '/^permissions:$/,+1d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no top-level 'permissions:' block"* ]]
    [[ "$output" == *"ci.yml"* ]]
}

@test "a SHIPPED workflow with no top-level permissions block exits 1" {
    # The same mutation on the other scan root. Without this the gate could be
    # narrowed to .github/workflows/ and every test above would still pass.
    write_good_tree
    sed -i '/^permissions:$/,+1d' "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"assets/governance/shipped.yml"* ]]
    [[ "$output" == *"no top-level 'permissions:' block"* ]]
}

@test "the string form 'permissions: write-all' exits 1, it is not a declaration" {
    write_good_tree
    sed -i 's/^permissions:$/permissions: write-all/; /^  contents: read$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is the string form"* ]]
}

@test "a top-level write grant exits 1: elevation belongs on the job that needs it" {
    write_good_tree
    sed -i 's/^  contents: read$/  contents: write/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"grants write to every job in the"* ]]
}

# --- Mutation: the persisted checkout credential ----------------------------

@test "a checkout that omits persist-credentials exits 1" {
    write_good_tree
    sed -i '/persist-credentials: false/d; /^        with:$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not set 'persist-credentials: false'"* ]]
}

@test "a checkout that sets persist-credentials: true exits 1" {
    write_good_tree
    sed -i 's/persist-credentials: false/persist-credentials: true/' "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"so the token is persisted"* ]]
}

@test "a forked checkout action is still a checkout" {
    # Matched on the last path segment, so renaming the publisher does not walk
    # the step out of the gate.
    write_good_tree
    sed -i 's|actions/checkout@v4|someorg/checkout@v4|; /persist-credentials: false/d; /^        with:$/d' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"someorg/checkout@v4"* ]]
}

# --- Undecidable states exit 2, never 0 -------------------------------------

@test "a persist-credentials expression the gate cannot evaluate exits 2, not 0" {
    write_good_tree
    sed -i 's/persist-credentials: false/persist-credentials: ${{ github.event_name == '"'"'push'"'"' }}/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot evaluate"* ]]
}

@test "unparseable YAML exits 2, not 0" {
    write_good_tree
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$(wf_dir)/broken.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"is not valid YAML"* ]]
}

@test "a missing scan root exits 2: the shipped template is not silently dropped" {
    write_good_tree
    rm -rf "$TEST_TMPDIR/assets"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"assets/governance/ does not exist"* ]]
}

@test "an empty scan root exits 2: scanning nothing is not the same as finding nothing" {
    write_good_tree
    rm -f "$(asset_dir)/shipped.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"holds no .yml or .yaml document"* ]]
}

@test "a job delegating to a reusable workflow exits 2, not 0" {
    write_good_tree
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
permissions:
  contents: read
on: [push]
jobs:
  build:
    uses: someorg/somerepo/.github/workflows/reusable.yml@v1
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not visible from this file"* ]]
}

# --- The elevations the top-level block must not swallow --------------------
#
# A job-level `permissions:` REPLACES the top-level one rather than merging with
# it. Now that ci.yml and codeql.yml carry a top-level `contents: read`, deleting
# a job-level block as "redundant" would silently strip an elevation, and the
# failure would only appear on a release tag. assert-repo-ci-shape.mjs holds all
# three; this is the direction test for it.

@test "the release-path elevations are still declared on this repository" {
    run node "$SHAPE_GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

@test "deleting the publish job's id-token grant is caught" {
    # Copy the repository's workflow set, break one block, and re-run the gate
    # against the copy. The real repository is never modified.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT"/.github/workflows/*.yml "$TEST_TMPDIR/.github/workflows/"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    # No '$' anchor: a Windows working tree checks these files out with CRLF, and
    # an anchored pattern would silently match nothing there while still matching
    # on Linux CI. The string occurs exactly once in the file either way.
    sed -i '/id-token: write/d' "$TEST_TMPDIR/.github/workflows/ci.yml"
    [ "$(grep -c 'id-token: write' "$TEST_TMPDIR/.github/workflows/ci.yml")" -eq 0 ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"job 'publish' no longer declares 'id-token: write'"* ]]
}

@test "deleting the codeql job's security-events grant is caught" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT"/.github/workflows/*.yml "$TEST_TMPDIR/.github/workflows/"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    # Unanchored for the CRLF reason recorded in the test above.
    sed -i '/security-events: write/d' "$TEST_TMPDIR/.github/workflows/codeql.yml"
    [ "$(grep -c 'security-events: write' "$TEST_TMPDIR/.github/workflows/codeql.yml")" -eq 0 ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"job 'analyze' no longer declares 'security-events: write'"* ]]
}

# --- The shape gate is handed a ROOT, so it must survive a partial one ---
#
# tests/assert-repo-ci-shape.mjs takes the root to assert as argv[1]. `npm test`
# passes this repository, which holds every workflow the gate records. Other
# callers pass a copy that holds only what THEY need - the release-authorization
# fixtures in tests/runtime-support.bats copy package.json and ci.yml and nothing
# else - and an unguarded readFileSync on a workflow such a copy does not have
# throws ENOENT: node exits 1 with a stack trace and not one of the gate's own
# findings is printed. A caller asserting exit 0 sees a failure that is not
# there; a caller asserting exit 1 sees the right code for the wrong reason and
# no message at all. Both are worse than either true answer.
#
# So the reads are guarded, and the four tests below fix the behaviour in both
# directions: what the root does not contain is NAMED and not asserted, and
# everything the gate can see but cannot trust is a failure with an exact code.

@test "a root with only package.json and ci.yml is green, and says what it did not assert" {
    # This is exactly the fixture shape the release-authorization tests build.
    # Before the reads were guarded this exited 1 with an ENOENT stack trace.
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
    [ ! -f "$TEST_TMPDIR/.github/workflows/codeql.yml" ]

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
    # Not asserted is SAID, so a root that cannot answer for an elevation never
    # passes over it in silence.
    [[ "$output" == *"not asserted here: codeql.yml"* ]]
    [[ "$output" != *"ENOENT"* ]]
}

@test "a recorded workflow that is present and unparseable is a failure, never a skip" {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
    printf 'jobs:\n  analyze:\n   permissions:\n  - [unclosed\n' \
        > "$TEST_TMPDIR/.github/workflows/codeql.yml"

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"codeql.yml is not valid YAML"* ]]
    [[ "$output" == *"cannot be asserted"* ]]
}

@test "a root with no ci.yml is a stated failure, not a stack trace" {
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"

    run node "$SHAPE_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ci.yml is not present"* ]]
    [[ "$output" != *"ENOENT"* ]]
}

@test "a root with no package.json is a stated failure, not a stack trace" {
    run node "$SHAPE_GATE" "$TEST_TMPDIR/nowhere"
    [ "$status" -eq 1 ]
    [[ "$output" == *"package.json is not present"* ]]
    [[ "$output" != *"ENOENT"* ]]
}

# --- The publish job: a narrow release guard, and nothing third-party ---------
#
# jobs.publish holds `id-token: write`, so every step in it can mint the OIDC
# token npm trusts for this package. Its `if:` is the shared release DEFINITION
# and is deliberately loose (any `v*` tag containing a dot). The narrow check is
# the "Verify the release ref" step. The tests below run THAT step, extracted
# from the parsed workflow, against fixture repositories, so what is tested is
# the text the job runs.

# Print the run text of the named publish-job step from ci.yml under root $1.
publish_step_run() {
    node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const [root, name] = process.argv.slice(1);
      const job = YAML.parse(readFileSync(join(root, ".github/workflows/ci.yml"), "utf8")).jobs.publish;
      const step = (job.steps ?? []).find((s) => s.name === name);
      if (!step) { console.error("no publish step named " + name); process.exit(3); }
      process.stdout.write(step.run);
    ' "$1" "$2"
}

# A remote whose main carries package.json at version $1, cloned into
# $TEST_TMPDIR/work. Nothing is tagged yet; each test places its own tag.
release_fixture() {
    local version="$1" seed="$TEST_TMPDIR/seed"
    # symbolic-ref rather than `init -b`: it works on every git that has
    # worktrees, and it does not depend on init.defaultBranch.
    git init -q --bare "$TEST_TMPDIR/origin.git"
    git -C "$TEST_TMPDIR/origin.git" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" symbolic-ref HEAD refs/heads/main
    printf '{ "name": "fx", "version": "%s" }\n' "$version" > "$seed/package.json"
    git -C "$seed" add package.json
    git -C "$seed" -c user.name=t -c user.email=t@example.invalid commit -q -m "release $version"
    git -C "$seed" push -q "$TEST_TMPDIR/origin.git" main
    git clone -q -b main "$TEST_TMPDIR/origin.git" "$TEST_TMPDIR/work"
    publish_step_run "$AAHP_ROOT" "Verify the release ref" > "$TEST_TMPDIR/guard.sh"
    [ -s "$TEST_TMPDIR/guard.sh" ]
}

# A commit on a pushed side branch, NOT on main, carrying the same version.
# Prints its SHA.
side_commit() {
    local seed="$TEST_TMPDIR/seed"
    git -C "$seed" checkout -q -b side
    printf 'side\n' > "$seed/side.txt"
    git -C "$seed" add side.txt
    git -C "$seed" -c user.name=t -c user.email=t@example.invalid commit -q -m "side"
    git -C "$seed" push -q "$TEST_TMPDIR/origin.git" side
    git -C "$TEST_TMPDIR/work" fetch -q origin side
    git -C "$TEST_TMPDIR/work" rev-parse FETCH_HEAD
}

# Run the guard in the fixture checkout the way the publish job runs a step,
# with GITHUB_REF=$1 and GITHUB_REF_NAME=$2.
run_guard() {
    run bash -c 'cd "$1" && GITHUB_REF="$2" GITHUB_REF_NAME="$3" bash --noprofile --norc -eo pipefail "$4"' \
        _ "$TEST_TMPDIR/work" "$1" "$2" "$TEST_TMPDIR/guard.sh"
}

@test "release guard: a vX.Y.Z tag on main matching package.json passes" {
    release_fixture 1.2.3
    git -C "$TEST_TMPDIR/work" tag v1.2.3
    git -C "$TEST_TMPDIR/work" checkout -q --detach v1.2.3

    run_guard refs/tags/v1.2.3 v1.2.3
    [ "$status" -eq 0 ]
    [[ "$output" == *"release guard OK: v1.2.3 = package.json 1.2.3"* ]]
}

@test "release guard: a branch ref is refused" {
    release_fixture 1.2.3
    run_guard refs/heads/main main
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a tag"* ]]
}

@test "release guard: a tag the job condition admits but that is not vX.Y.Z is refused" {
    # `startsWith(github.ref, 'refs/tags/v') && contains(github.ref, '.')`
    # admits all three of these.
    release_fixture 1.2.3
    local t
    for t in v1.2 v1.2.3-rc.1 v1.2.3.4; do
        git -C "$TEST_TMPDIR/work" tag "$t"
        git -C "$TEST_TMPDIR/work" checkout -q --detach "$t"
        run_guard "refs/tags/$t" "$t"
        [ "$status" -eq 1 ] || { echo "$t was not refused: $output"; false; }
        [[ "$output" == *"is not vMAJOR.MINOR.PATCH"* ]]
    done
}

@test "release guard: a tag that names another version than package.json is refused" {
    release_fixture 1.2.3
    git -C "$TEST_TMPDIR/work" tag v1.2.4
    git -C "$TEST_TMPDIR/work" checkout -q --detach v1.2.4

    run_guard refs/tags/v1.2.4 v1.2.4
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not match package.json version '1.2.3'"* ]]
}

@test "release guard: GITHUB_REF_NAME that does not name GITHUB_REF is refused" {
    release_fixture 1.2.3
    git -C "$TEST_TMPDIR/work" tag v1.2.3
    git -C "$TEST_TMPDIR/work" checkout -q --detach v1.2.3

    run_guard refs/tags/v1.2.3 v9.9.9
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not name 'refs/tags/v1.2.3'"* ]]
}

@test "release guard: a tag on a commit that is not on main is refused" {
    # The case the job condition cannot see at all: a correctly named tag with
    # the right version, pushed at a commit from a branch that never merged.
    release_fixture 1.2.3
    local side
    side="$(side_commit)"
    git -C "$TEST_TMPDIR/work" tag v1.2.3 "$side"
    git -C "$TEST_TMPDIR/work" checkout -q --detach v1.2.3

    run_guard refs/tags/v1.2.3 v1.2.3
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not reachable from origin/main"* ]]
}

@test "release guard: main is fetched from origin, not trusted from the checkout" {
    # Point the checkout's own origin/main at the side commit. A guard that
    # trusted the local ref would pass; this one fetches main and refuses.
    release_fixture 1.2.3
    local side
    side="$(side_commit)"
    git -C "$TEST_TMPDIR/work" update-ref refs/remotes/origin/main "$side"
    git -C "$TEST_TMPDIR/work" tag v1.2.3 "$side"
    git -C "$TEST_TMPDIR/work" checkout -q --detach v1.2.3

    run_guard refs/tags/v1.2.3 v1.2.3
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not reachable from origin/main"* ]]
}

@test "release guard: a checkout that is not the tagged commit is refused" {
    # The tag moved after the event: the job checked out one commit and the tag
    # now names another.
    release_fixture 1.2.3
    local side
    side="$(side_commit)"
    git -C "$TEST_TMPDIR/work" tag v1.2.3 "$side"
    git -C "$TEST_TMPDIR/work" checkout -q --detach origin/main

    run_guard refs/tags/v1.2.3 v1.2.3
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not the commit tag 'v1.2.3' points at"* ]]
}

# The shape of the publish job, read from a ROOT so each clause is mutated
# below against a copy.
publish_job_shape() {
    node --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { join } from "node:path";
      import YAML from "yaml";
      const job = YAML.parse(readFileSync(join(process.argv[1], ".github/workflows/ci.yml"), "utf8")).jobs.publish;
      const problems = [];
      const steps = job.steps ?? [];
      const at = (pred) => steps.findIndex(pred);
      const checkout = at((s) => String(s.uses ?? "").startsWith("actions/checkout@"));
      const setup = at((s) => String(s.uses ?? "").startsWith("actions/setup-node@"));
      const guard = at((s) => s.name === "Verify the release ref");
      const publish = at((s) => /\bnpm publish\b/.test(String(s.run ?? "")));
      if (guard === -1) problems.push("the release guard step is gone");
      if (publish === -1) problems.push("no npm publish step");
      if (guard !== -1 && publish !== -1 && guard > publish) problems.push("the release guard runs after npm publish");
      if (steps[checkout]?.with?.["fetch-depth"] !== 0) problems.push("the checkout is shallow, so reachability from main cannot be decided");
      if (setup !== -1 && Object.hasOwn(steps[setup].with ?? {}, "cache")) problems.push("setup-node restores a cache in the job that publishes");
      const cmd = String(steps[publish]?.run ?? "");
      if (!/--ignore-scripts\b/.test(cmd)) problems.push("npm publish runs lifecycle scripts (prepublishOnly) with id-token: write");
      if (!/--provenance\b/.test(cmd)) problems.push("npm publish lost --provenance");
      for (const [i, s] of steps.entries()) {
        if (i === guard || i === publish || typeof s.run !== "string") continue;
        problems.push("an extra run step executes in the publish job: " + JSON.stringify(s.name ?? s.run));
      }
      for (const p of problems) console.error("  - " + p);
      if (problems.length > 0) process.exit(1);
      console.log("publish job shape OK");
    ' "$1"
}

copy_ci() {
    mkdir -p "$TEST_TMPDIR/.github/workflows"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$TEST_TMPDIR/.github/workflows/ci.yml"
}

# Replace the first line matching awk regex $1 inside the publish job of the
# copied ci.yml with $2 (awk -v expands \n; empty deletes). Exits 3 when nothing
# matched, so a mutation that applied to nothing is never a green test. Lines
# are compared with any trailing CR removed, for a CRLF checkout.
mutate_publish() {
    local file="$TEST_TMPDIR/.github/workflows/ci.yml"
    awk -v re="$1" -v repl="$2" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/) injob = (line == "  publish:")
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

@test "publish job: this repository's shape holds" {
    run publish_job_shape "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"publish job shape OK"* ]]
}

@test "publish job: an npm ci step in the publish job is red" {
    copy_ci
    mutate_publish '^      - name: Publish to npm' '      - run: npm ci --ignore-scripts\n      - name: Publish to npm (OIDC trusted publishing, no token)'
    run publish_job_shape "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"an extra run step executes in the publish job"* ]]
}

@test "publish job: npm publish without --ignore-scripts is red" {
    copy_ci
    mutate_publish 'run: npm publish' '        run: npm publish --access public --provenance'
    run publish_job_shape "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runs lifecycle scripts (prepublishOnly)"* ]]
}

@test "publish job: a restored npm cache is red" {
    copy_ci
    mutate_publish "registry-url: 'https://registry.npmjs.org'" "          registry-url: 'https://registry.npmjs.org'\n          cache: 'npm'"
    run publish_job_shape "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"restores a cache in the job that publishes"* ]]
}

@test "publish job: a shallow checkout is red" {
    copy_ci
    mutate_publish 'fetch-depth: 0' ''
    run publish_job_shape "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the checkout is shallow"* ]]
}

@test "publish job: deleting the release guard is red" {
    copy_ci
    mutate_publish '^      - name: Verify the release ref' '      - name: Renamed step'
    run publish_job_shape "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the release guard step is gone"* ]]
}
