#!/usr/bin/env bats
# runtime-support.bats - the runtimes CI exercises and the runtimes package.json
# publishes must be the same set, and the floor of that set must still receive
# security patches.
#
# Every test here asserts in BOTH directions: the relation holds on the real
# repository, and each way of breaking it turns the gate red. A gate proved only
# in the passing direction is indistinguishable from a gate that cannot fail.

load test_helper

GATE="$SCRIPTS_DIR/check-runtime-support.mjs"

# NOTE: TEST_TMPDIR is created by setup(), which runs AFTER this file is sourced,
# so the workflow directory cannot be a top-level variable - it would expand to
# "/.github/workflows" here. Every test calls this instead.
wf_dir() {
    printf '%s/.github/workflows' "$TEST_TMPDIR"
}

# package.json for a fixture project. $1 is the engines.node range; omitting it
# writes no engines block at all.
write_pkg() {
    if [ $# -eq 0 ]; then
        printf '{ "name": "fx", "version": "1.0.0" }\n' > "$TEST_TMPDIR/package.json"
    else
        printf '{ "name": "fx", "version": "1.0.0", "engines": { "node": "%s" } }\n' "$1" \
            > "$TEST_TMPDIR/package.json"
    fi
}

# The baseline fixture: a two-runtime matrix and a release job on the newer
# runtime. Every mutation test below starts from this and breaks ONE thing, so a
# red result can only be caused by that one change.
write_good_workflow() {
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [22, 24]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
EOF
}

# assets/governance is the SECOND scan root: the workflow template
# `aahp init --gates` copies into a consumer repository. $1 is the Node major
# it pins. A file here never runs in this repository, so these tests are the
# only thing that exercises the shipped-template half of the gate.
tpl_dir() {
    printf '%s/assets/governance' "$TEST_TMPDIR"
}

write_template() {
    mkdir -p "$(tpl_dir)"
    cat > "$(tpl_dir)/aahp-govern.yml" <<EOF
name: AAHP Govern
on: [push]
jobs:
  govern:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '$1'
EOF
}

# ─── The load-bearing assertion: the real repository ────────────────────────

@test "this repository's own workflows satisfy the runtime relation" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Runtime support OK"* ]]
}

@test "the gate actually reads the shipped template, not just what runs here" {
    # The scan root is OPTIONAL - a project that ships no template is not a
    # finding - so nothing in the gate can prove the root is still wired up.
    # This does, against the real tree: the summary names every file scanned,
    # so renaming assets/governance, dropping it from SCAN_ROOTS, or filtering
    # it out all turn this red. Without it the widened scope could silently
    # revert to reading one directory, which is the exact defect it fixed.
    #
    # Measured 2026-08-23: assets/governance/aahp-govern.yml pinned Node 20
    # against engines.node '>=22' and this gate was green on every commit,
    # because it scanned .github/workflows only.
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"assets/governance/aahp-govern.yml:govern"* ]]
}

@test "the baseline fixture passes, so every mutation below starts from green" {
    write_pkg ">=22"
    write_good_workflow
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# ─── Mutation: a runtime CI exercises that the package does not claim ───────

@test "a CI pin below the published floor is a failure" {
    write_pkg ">=22"
    write_good_workflow
    # Drop the release job back to a runtime the package no longer claims.
    sed -i "s/node-version: '24'/node-version: '20'/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"below the engines.node floor of 22"* ]]
}

@test "a shipped-template pin below the published floor is a failure" {
    # The defect this scan root exists for. Every LOCAL pin clears the floor
    # here, so the only thing that can turn this red is the template - which
    # this repository never executes and, before 2026-08-23, never read either.
    write_pkg ">=22"
    write_good_workflow
    write_template 20

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"assets/governance/aahp-govern.yml:govern scaffolds consumers onto Node 20"* ]]
    [[ "$output" == *"EBADENGINE"* ]]
}

@test "a shipped template on the floor keeps the fixture green" {
    # The control for the test above: same fixture, compliant pin. Without it a
    # red result there could just mean "any template at all breaks the gate".
    write_pkg ">=22"
    write_good_workflow
    write_template 22

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "a shipped template does not vouch for an untested release runtime" {
    # Widening a gate's scope must not make it assert LESS. The release check is
    # a membership test against the runtimes this repository's build jobs prove;
    # a template job counted as a build job would supply Node 26 to that set and
    # silence the finding below. It runs in the adopter's CI, never in ours, so
    # it proves nothing about our release path.
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version: '26'/" "$(wf_dir)/ci.yml"
    write_template 26

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release path runs on Node 26, which no build or test job exercises"* ]]
}

@test "a project that ships no template is not a finding" {
    # The asymmetry between the two scan roots, asserted rather than assumed.
    # A missing .github/workflows is exit 2; a missing assets/governance is a
    # package with nothing to ship, which is the shape of every other fixture
    # in this file and of every consumer project.
    write_pkg ">=22"
    write_good_workflow
    [ ! -d "$(tpl_dir)" ]

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "widening the published range below what CI proves is a failure" {
    # The mirror image: CI stays on 22/24 but the package claims >=18, so it
    # advertises support for runtimes nothing ever exercised.
    write_pkg ">=18"
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"oldest runtime still receiving"* ]]
}

# ─── Mutation: the published floor goes end-of-life ─────────────────────────

@test "an end-of-life published floor is a failure even when CI agrees with it" {
    # CI and engines are perfectly consistent here - consistently dead. This is
    # the exact state this repository shipped in: engines '>=18', CI on Node 20,
    # nothing red. Only the dated SUPPORTED_FLOOR constant can catch it.
    write_pkg ">=20"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [20, 21]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"still receiving"* ]]
}

# ─── Mutation: the vacuity trap this gate was shaped to avoid ───────────────

@test "emptying the matrix is a failure even while standalone pins remain" {
    # THE RECORDED TRAP. A sibling gate in this estate asserted only that the
    # GLOBAL pin list was non-empty. Removing the matrix left it green, because
    # the standalone `node-version:` pins in the other jobs kept that list
    # populated on their own - the multi-runtime coverage vanished silently.
    #
    # So this fixture deliberately KEEPS two standalone pins. The generic "no
    # pins at all" guard therefore cannot fire, and only the assertion bound to
    # the matrix itself can turn this red.
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"matrix exercises 0 runtime(s)"* ]]
}

@test "cutting the matrix to a single runtime is a failure" {
    write_pkg ">=22"
    write_good_workflow
    sed -i 's/node-version: \[22, 24\]/node-version: [22]/' "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"matrix exercises 1 runtime(s)"* ]]
}

@test "no node-version pin anywhere is a failure, not a clean skip" {
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"vacuously true"* ]]
}

# ─── Mutation: releasing on a runtime nothing tested ───────────────────────

@test "a release runtime that no build job exercises is a failure" {
    # Every pin here satisfies engines and the matrix is intact, so this can only
    # be caught by the build-vs-release MEMBERSHIP test. Node 22 clears the floor,
    # so the floor check provably is not what turns this red.
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    cat > "$(wf_dir)/ci.yml" <<'EOF'
name: fx
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [24, 26]
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
EOF

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release path runs on Node 22, which no build or test job exercises"* ]]
}

@test "a release runtime NEWER than anything tested is also a failure" {
    # The mirror image, and the case an ordering comparison ("release major >=
    # lowest build major") cannot see at all: publishing on 26 while CI only ever
    # ran 22 and 24 makes the publish step the first thing to touch that runtime.
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version: '26'/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release path runs on Node 26, which no build or test job exercises"* ]]
}

# ─── Mutation: pins the gate cannot read must FAIL, never be skipped ────────

@test "a non-matrix expression pin fails rather than being silently dropped" {
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version: \${{ env.NODE_MAJOR }}/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot evaluate"* ]]
}

@test "node-version-file fails rather than being silently dropped" {
    write_pkg ">=22"
    write_good_workflow
    sed -i "s/node-version: '24'/node-version-file: .nvmrc/" "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"node-version-file"* ]]
}

# ─── "I could not look" must never read as "I looked and it was fine" ──────

@test "a missing engines.node exits 2, not 0" {
    write_pkg
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no engines.node"* ]]
}

@test "an engines range the gate cannot read exits 2, not 0" {
    write_pkg "^22 || ^24"
    write_good_workflow

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read as a floor"* ]]
}

@test "a project with no workflows exits 2, not 0" {
    write_pkg ">=22"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no workflow directory"* ]]
}

@test "unparseable YAML exits 2, not 0" {
    write_pkg ">=22"
    mkdir -p "$(wf_dir)"
    printf 'jobs:\n  build:\n   steps:\n  - bad: [unclosed\n' > "$(wf_dir)/ci.yml"

    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not valid YAML"* ]]
}

# ─── The gate has to actually RUN, and the required check has to keep its name ─

@test "the gate is wired into the check chain, and the required check keeps its name" {
    # Both assertions live in tests/assert-repo-ci-shape.mjs - see the header
    # there for why this is a file and not an inline `node -e`.
    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

# ─── Release authorization: one definition of a release, nothing beyond it that
# ─── is not recorded (https://github.com/homeofe/AAHP/issues/69) ──────────────
#
# The third assertion in tests/assert-repo-ci-shape.mjs is the only thing in this
# repository that reads either release-critical job condition. It is worth exactly
# as much as its ability to go red, so every test below mutates ONE line of a copy
# of the REAL ci.yml and asserts the exact exit code. The control test proves the
# untouched copy is green, so a red result can only be caused by the mutation.

# Copy the real repository shape (package.json and ci.yml) into TEST_TMPDIR. The
# assertion takes a root as argv[1], so it runs against the copy without the
# mutations ever touching the working tree.
copy_repo_shape() {
    mkdir -p "$(wf_dir)"
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    cp "$AAHP_ROOT/.github/workflows/ci.yml" "$(wf_dir)/ci.yml"
}

# Replace the `if:` line of job $1 in the fixture ci.yml with $2; an empty $2
# deletes the line. awk rather than `sed -i` on purpose: these conditions contain
# `&&`, and a bare `&` in a sed replacement means "the whole match", so the sed
# form would silently write something other than what the test says it writes.
# Exits non-zero when the job has no `if:` line, so a mutation that quietly
# applied to nothing cannot pass as a green test. The job header is compared with
# any trailing CR removed: ci.yml is not covered by .gitattributes, so a Windows
# checkout has CRLF endings and a byte comparison would silently match nothing.
set_job_if() {
    local job="$1" repl="$2" file
    file="$(wf_dir)/ci.yml"
    awk -v job="$job" -v repl="$repl" '
        /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ {
            hdr = $0
            sub(/\r$/, "", hdr)
            injob = (hdr == "  " job ":")
        }
        {
            if (injob && !done && $0 ~ /^    if:/) {
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

@test "release authorization: the untouched repository shape is green" {
    copy_repo_shape

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

@test "release authorization: a publish job with no if: at all is red" {
    # The mutation that a test matching an expected string would sail past. A
    # publish job with no condition runs on every event ci.yml accepts, which is
    # strictly worse than any condition it could carry.
    copy_repo_shape
    set_job_if publish ""

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"jobs.publish has no \`if:\` condition"* ]]
}

@test "release authorization: changing only the release job's condition is red" {
    # The two jobs must share ONE definition of a release. Moving one of them is
    # the drift this assertion exists to catch, so it has to be red even though
    # the publish condition is untouched and still matches its record.
    copy_repo_shape
    set_job_if release "    if: startsWith(github.ref, 'refs/tags/')"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"jobs.release.if is not the recorded release definition"* ]]
}

@test "release authorization: an unrecorded operand on the publish condition is red" {
    copy_repo_shape
    set_job_if publish "    if: (startsWith(github.ref, 'refs/tags/v') && contains(github.ref, '.')) || github.event_name == 'workflow_dispatch' || github.ref == 'refs/heads/main'"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has not recorded: github.ref == 'refs/heads/main'"* ]]
}


# --- two tests retired here on purpose, and what brings them back ------------
#
# `release authorization: removing a recorded operand is red until the record is
# updated` and `publish record: writing (none) while the code records an operand
# is red` both required PUBLISH_CONDITIONS_BEYOND_RELEASE to be NON-empty: each
# asserted that dropping a recorded operand from one of the two records is caught.
#
# ADR-019 was settled as option A, so that list is now `[]` and the ADR block reads
# `(none)`. The list is a constant inside the assertion under test, so no fixture
# can make it non-empty, and neither scenario can be built.
#
# The `recordedButGone` branch they covered is UNCHANGED and still runs on every
# invocation. It has nothing to find while the record is empty. The first commit
# that records an operand again makes both tests constructible, and they should
# come back in that commit. They are removed rather than left red, and named here
# rather than deleted silently, because a test that cannot fail is not coverage and
# a deletion nobody can find is not a decision.
@test "release authorization: an AND-shaped publish condition is red, not silently accepted" {
    # Requiring a tag ref on the dispatch path too is one of the options open in
    # ADR-019. It is a policy change, so it must be recorded rather than absorbed.
    copy_repo_shape
    set_job_if publish "    if: (startsWith(github.ref, 'refs/tags/v') && contains(github.ref, '.')) && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not carry the shared release definition exactly once"* ]]
}

@test "release authorization: reformatting the condition does not change the verdict" {
    # Proves the assertion reads the PARSED condition rather than a substring of
    # the file: redundant parentheses and extra spaces are the same expression, so
    # they must stay green, or the gate would be a formatting rule wearing a
    # security rule's clothes.
    copy_repo_shape
    # Reformats the RELEASE definition itself. It used to reformat a condition
    # carrying the dispatch operand, which was green while that operand was
    # recorded; with option A adopted it would now be an unrecorded permission, so
    # the expectation would be wrong for a reason that has nothing to do with
    # formatting. The property under test is unchanged.
    set_job_if publish "    if: ((  startsWith(github.ref, 'refs/tags/v')   &&   contains(github.ref, '.')  ))"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

@test "release authorization: a publish condition that cannot be read is red, never a skip" {
    copy_repo_shape
    set_job_if publish "    if: \"(startsWith(github.ref, 'refs/tags/v') && contains(github.ref, '.') || github.event_name == 'workflow_dispatch'\""

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"jobs.publish.if could not be read"* ]]
}

# ─── Section 5: the code record and the DOCUMENTED record have to agree ─────
#
# Section 3 above holds ci.yml to a literal list inside assert-repo-ci-shape.mjs.
# ADR-019 in README.md is the record a person reads, and until section 5 nothing
# compared the two, so either could be edited alone and every check stayed green.
# The tests below mutate the README copy only; ci.yml is untouched in all of them,
# which is what makes a red result attributable to the documentation drifting
# rather than to the workflow.

# Delete every line containing a fixed substring, and FAIL if there was none to
# delete. A mutation that quietly applied to nothing would otherwise pass as a
# green test, which is the failure mode these tests exist to rule out.
drop_line() {
    local file="$1" needle="$2" before after
    before="$(grep -c -F -- "$needle" "$file" || true)"
    [ "$before" -ge 1 ] || { echo "mutation did not apply: no line matching '$needle'"; return 3; }
    grep -v -F -- "$needle" "$file" > "$file.new"
    mv "$file.new" "$file"
    after="$(grep -c -F -- "$needle" "$file" || true)"
    [ "$after" -eq 0 ] || { echo "mutation did not remove all matches"; return 3; }
}

# Replace every line containing a fixed substring with $3. awk with index()
# rather than sed: these strings contain `&`, `/` and quotes, and a bare `&` in a
# sed replacement means "the whole match", so the sed form would silently write
# something other than what the test says it writes.
replace_line() {
    local file="$1" needle="$2" repl="$3"
    grep -q -F -- "$needle" "$file" || { echo "mutation did not apply: no line matching '$needle'"; return 3; }
    awk -v needle="$needle" -v repl="$repl" 'index($0, needle) { print repl; next } { print }' \
        "$file" > "$file.new"
    mv "$file.new" "$file"
}

# The section-3 fixture plus the README, so section 5 has both records to compare.
copy_repo_shape_with_readme() {
    copy_repo_shape
    cp "$AAHP_ROOT/README.md" "$TEST_TMPDIR/README.md"
}

@test "publish record: this repository's ADR-019 and recorded list agree" {
    # Run against the real root, not a copy. This is the assertion that has to
    # hold on main; everything below only proves it can fail.
    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
    [[ "$output" != *"README.md is not present"* ]]
}

@test "publish record: the copy carrying a README is green, so every mutation starts there" {
    copy_repo_shape_with_readme

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}

@test "publish record: a root with no README is NOT asserted, and says so" {
    # The third state. A fixture that never had a README is not a repository whose
    # ADR was deleted, and reporting either as the other would be a guess. Every
    # section-3 test above lands here, which is why they stayed green.
    copy_repo_shape

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not asserted here: README.md is not present"* ]]
}

@test "publish record: documenting an operand the code does not record is red" {
    copy_repo_shape_with_readme
    replace_line "$TEST_TMPDIR/README.md" \
        "(none)" \
        "github.actor == 'some-bot'"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADR-019 documents a publish condition this file no longer records"* ]]
    [[ "$output" == *"ADR-019 does not document"* ]]
}

@test "publish record: an emptied operand block is red, not an empty set" {
    # Deleting the last line of the block is the edit that would otherwise read as
    # "there are no extra operands", which is the opposite of what ci.yml says.
    copy_repo_shape_with_readme
    drop_line "$TEST_TMPDIR/README.md" "(none)"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"recorded-operands block in ADR-019 is empty"* ]]
}


@test "publish record: deleting the marker line is red" {
    # The single line a reviewer deletes to disarm section 5. Named here and
    # deleted here, so the claim is checked rather than asserted.
    copy_repo_shape_with_readme
    drop_line "$TEST_TMPDIR/README.md" "**Recorded operands beyond the release definition.**"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no longer carries the line"* ]]
}

@test "publish record: deleting the ADR-019 heading is red" {
    copy_repo_shape_with_readme
    drop_line "$TEST_TMPDIR/README.md" "### ADR-019: one release definition"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no '### ADR-019:' section"* ]]
}

@test "publish record: an ADR that stops stating the release definition is red" {
    copy_repo_shape_with_readme
    replace_line "$TEST_TMPDIR/README.md" \
        "**Decision:** the release definition \`startsWith(github.ref, 'refs/tags/v') &&" \
        "**Decision:** the release definition is written ONCE, as \`RELEASE_REF_CONDITION\` in"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no longer states the release definition verbatim"* ]]
}

@test "publish record: rewrapping the ADR prose does not change the verdict" {
    # The release definition is line-wrapped in README.md, so the comparison
    # collapses whitespace. This proves that is a real property and not an
    # accident of where the current line break happens to fall: joining those two
    # lines must stay green.
    copy_repo_shape_with_readme
    awk '
        index($0, "**Decision:** the release definition `startsWith(github.ref, '\''refs/tags/v'\'') &&") {
            line = $0
            sub(/\r$/, "", line)
            getline nxt
            sub(/\r$/, "", nxt)
            print line " " nxt
            next
        }
        { print }
    ' "$TEST_TMPDIR/README.md" > "$TEST_TMPDIR/README.new"
    mv "$TEST_TMPDIR/README.new" "$TEST_TMPDIR/README.md"

    run node "$AAHP_ROOT/tests/assert-repo-ci-shape.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo CI shape OK"* ]]
}
