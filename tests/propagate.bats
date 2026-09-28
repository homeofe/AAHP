#!/usr/bin/env bats
# propagate.bats - propagate.sh vendors the gate together with everything the
# gate executes, installs a CI workflow that can actually run in the target,
# and fails closed.
#
# The last tests in this file do not inspect the installed workflow, they RUN
# it: every `run:` step, in order, in a consumer whose node_modules comes from
# `npm ci` over a lockfile that points at this checkout's packed tarball. That
# is the check that was missing when propagate installed a workflow calling
# `node bin/aahp.js`, a path that exists only in an AAHP checkout: `cmp` of the
# file said it was copied faithfully, and it failed on its first run anywhere
# else.

setup_file() {
    load test_helper
    AAHP_PACK_DIR="$(_make_tmpdir)"
    export AAHP_PACK_DIR
    AAHP_TGZ="$AAHP_PACK_DIR/$(npm pack "$AAHP_ROOT" --silent --pack-destination "$AAHP_PACK_DIR" | tail -1)"
    export AAHP_TGZ
}

teardown_file() {
    if [ -n "${AAHP_PACK_DIR:-}" ] && [ -d "$AAHP_PACK_DIR" ]; then
        rm -rf "$AAHP_PACK_DIR"
    fi
}

setup() {
    load test_helper
    setup
    # Nothing here may reach the registry: audit and fund are network calls.
    export npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
    PKG_NAME="$(node -p 'require(process.argv[1]).name' "$AAHP_ROOT/package.json")"
    PKG_VERSION="$(node -p 'require(process.argv[1]).version' "$AAHP_ROOT/package.json")"
    create_full_handoff
    make_npm_adopter "$TEST_TMPDIR"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "seed handoff"
}

teardown() {
    teardown
}

# The files propagate must vendor: the gate plus everything it executes.
VENDORED="verify-handoff.sh _aahp-lib.sh lint-handoff.sh check-conflict-markers.mjs validate-pii-allowlist.py aahp-manifest.sh install-hooks.sh hooks/pre-commit hooks/pre-push"

# A package.json that declares the dependency and a lockfile that locks it. The
# lock is a stub: propagate only reads it. The tests at the end of this file
# use a real one.
make_npm_adopter() {
    local dir="$1"
    cat > "$dir/package.json" <<EOF
{
  "name": "demo-consumer",
  "version": "1.0.0",
  "private": true,
  "devDependencies": {
    "$PKG_NAME": "$PKG_VERSION"
  }
}
EOF
    cat > "$dir/package-lock.json" <<EOF
{
  "name": "demo-consumer",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "demo-consumer",
      "version": "1.0.0",
      "devDependencies": {
        "$PKG_NAME": "$PKG_VERSION"
      }
    },
    "node_modules/$PKG_NAME": {
      "version": "$PKG_VERSION",
      "dev": true
    }
  }
}
EOF
}

@test "propagation vendors the gate, its whole closure, the hooks and the adopter workflow, all staged" {
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"staged and verified"* ]]
    [[ "$output" != *"NOTE: baseline"* ]]

    local f
    for f in $VENDORED; do
        cmp "$AAHP_ROOT/scripts/$f" "$TEST_TMPDIR/scripts/$f"
    done
    cmp "$AAHP_ROOT/assets/governance/aahp-verify.yml" "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    grep -q 'aahp_non_impacting_modified_files' "$TEST_TMPDIR/scripts/_aahp-lib.sh"

    run git -C "$TEST_TMPDIR" diff --cached --name-only
    [ "$status" -eq 0 ]
    for f in $VENDORED; do
        [[ "$output" == *"scripts/$f"* ]]
    done
    [[ "$output" == *".github/workflows/aahp-verify.yml"* ]]
    [[ "$output" == *".ai/handoff/MANIFEST.json"* ]]
}

@test "the propagated workflow passes the event base and names no actor" {
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    grep -q 'AAHP_BASE_SHA.*pull_request.base.sha.*event.before.*inputs.base' \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    # `run` + status, not a bare `! grep`: bats never fails a test on a negated
    # command that is not the last line, so the bare form asserted nothing.
    # `-i` because GitHub expression contexts are case-insensitive.
    run grep -Eni 'dependabot|author\.username|github\.actor' \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
    [ "$status" -eq 1 ]
}

@test "the vendored closure is derived from the scripts, and every file in it arrives" {
    # Computed here independently of propagate.sh's own list: start from the
    # entry points and follow what each script names ($SCRIPT_DIR/<file> in
    # shell, "./<file>" in an ES module) until nothing new appears.
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    local todo="verify-handoff.sh aahp-manifest.sh install-hooks.sh" seen=" " f dep
    while [ -n "$todo" ]; do
        set -- $todo
        f="$1"
        shift
        todo="$*"
        case "$seen" in *" $f "*) continue ;; esac
        seen="$seen$f "
        [ -f "$AAHP_ROOT/scripts/$f" ] || continue
        case "$f" in
            *.mjs) deps="$(grep -oE "[\"']\./[A-Za-z0-9_.-]+[\"']" "$AAHP_ROOT/scripts/$f" | tr -d "\"'" | sed 's|^\./||' || true)" ;;
            *.sh) deps="$(grep -oE '\$\{?SCRIPT_DIR\}?/[A-Za-z0-9_.-]+' "$AAHP_ROOT/scripts/$f" | sed -E 's|^\$\{?SCRIPT_DIR\}?/||' || true)" ;;
            *) deps="" ;;
        esac
        for dep in $deps; do
            if [ -f "$AAHP_ROOT/scripts/$dep" ]; then
                todo="$todo $dep"
            fi
        done
    done
    # The closure is not trivially small: the two helpers lint-handoff.sh runs
    # are in it, which is the finding this test was written for.
    [[ "$seen" == *" check-conflict-markers.mjs "* ]]
    [[ "$seen" == *" validate-pii-allowlist.py "* ]]
    for f in $seen; do
        [ -f "$TEST_TMPDIR/scripts/$f" ] || { echo "not vendored: scripts/$f"; false; }
    done
}

@test "the vendored lint runs its conflict-marker check for real, both ways" {
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    run bash "$TEST_TMPDIR/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"could not run"* ]]
    [[ "$output" != *"Cannot find module"* ]]

    # And it can go red: the vendored copy finds a marker outside .ai/handoff.
    printf '%s\n' 'notes' '<<<<<<< HEAD' 'ours' > "$TEST_TMPDIR/notes.txt"
    run bash "$TEST_TMPDIR/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"notes.txt"* ]]
}

@test "a staged baseline that does not verify is a failed propagation, exit 1" {
    # A conflict marker anywhere in the tree fails Layer 1's lint. propagate
    # used to print a NOTE here and exit 0, the code that means "verified".
    printf '%s\n' 'intro' '>>>>>>> topic' > "$TEST_TMPDIR/README.md"
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not pass 'verify --level precommit'"* ]]
    [[ "$output" != *"staged and verified"* ]]
}

@test "a caller's AAHP_SKIP_VERIFY=1 cannot turn the baseline check into a pass" {
    printf '%s\n' 'intro' '>>>>>>> topic' > "$TEST_TMPDIR/README.md"
    run env AAHP_SKIP_VERIFY=1 bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not pass"* ]]
}

@test "a target that does not declare the aahp dependency is refused before anything is written, exit 3" {
    printf '{\n  "name": "demo-consumer",\n  "version": "1.0.0"\n}\n' > "$TEST_TMPDIR/package.json"
    git -C "$TEST_TMPDIR" commit -q -am "drop the dependency"

    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 3 ]
    [[ "$output" == *"declares no $PKG_NAME dependency"* ]]
    [[ "$output" == *"npm install --save-dev --save-exact $PKG_NAME@$PKG_VERSION"* ]]
    [ ! -e "$TEST_TMPDIR/scripts" ]
    [ ! -e "$TEST_TMPDIR/.github" ]
    run git -C "$TEST_TMPDIR" status --porcelain
    [ -z "$output" ]
}

@test "a lockfile that is not in the git index is refused, exit 3" {
    # CI checks out committed files only, so `npm ci` there would have no lock.
    git -C "$TEST_TMPDIR" rm -q --cached package-lock.json
    git -C "$TEST_TMPDIR" commit -q -m "untrack the lockfile"
    [ -f "$TEST_TMPDIR/package-lock.json" ]

    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 3 ]
    [[ "$output" == *"package-lock.json is not in the git index"* ]]
    [ ! -e "$TEST_TMPDIR/.github" ]
}

@test "a linked worktree is a valid target" {
    git -C "$TEST_TMPDIR" worktree add -q "$TEST_TMPDIR/wt" -b wt-branch
    [ -f "$TEST_TMPDIR/wt/.git" ]

    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR/wt"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/wt/.github/workflows/aahp-verify.yml" ]
    # The hooks went where git runs them for that worktree: the common dir.
    grep -q "AAHP pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit"
}

@test "a subdirectory of a work tree is refused, exit 1, nothing written" {
    mkdir -p "$TEST_TMPDIR/pkg/.ai/handoff"
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR/pkg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is the subdirectory 'pkg/'"* ]]
    [ ! -e "$TEST_TMPDIR/pkg/scripts" ]
    [ ! -e "$TEST_TMPDIR/pkg/.github" ]
}

@test "a target without .ai/handoff is refused, exit 2" {
    rm -rf "$TEST_TMPDIR/.ai"
    run bash "$AAHP_ROOT/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Run 'aahp init' there first"* ]]
}

@test "the packed npm artifact ships the adopter workflow, not this repository's own, and propagates it byte-identical" {
    local install_dir installed_root f
    install_dir="$TEST_TMPDIR/install"
    mkdir -p "$install_dir"
    run npm install --silent --ignore-scripts --no-package-lock \
        --prefix "$install_dir" "$AAHP_TGZ"
    [ "$status" -eq 0 ]
    installed_root="$install_dir/node_modules/$PKG_NAME"
    [ -f "$installed_root/assets/governance/aahp-verify.yml" ]
    # AAHP's own workflow runs `node bin/aahp.js`, which resolves only in an
    # AAHP checkout. Shipping it put a broken copy one `cp` away from adopters.
    [ ! -e "$installed_root/.github/workflows/aahp-verify.yml" ]

    run bash "$installed_root/scripts/propagate.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    for f in $VENDORED; do
        cmp "$AAHP_ROOT/scripts/$f" "$TEST_TMPDIR/scripts/$f"
    done
    cmp "$AAHP_ROOT/assets/governance/aahp-verify.yml" \
        "$TEST_TMPDIR/.github/workflows/aahp-verify.yml"
}

# ---------------------------------------------------------------------------
# Executing the shipped consumer workflow
# ---------------------------------------------------------------------------

# A consumer as the README Quickstart builds one: an npm project with this
# checkout's packed tarball as an exact devDependency (so `npm ci` can restore
# it offline from the committed lockfile), then `aahp init` and `aahp manifest`
# run through the INSTALLED CLI, committed.
make_consumer() {
    local dir="$1"
    mkdir -p "$dir"
    git init -q "$dir"
    git -C "$dir" config user.name "test"
    git -C "$dir" config user.email "test@test.local"
    printf '{\n  "name": "demo-consumer",\n  "version": "1.0.0",\n  "private": true\n}\n' > "$dir/package.json"
    printf 'node_modules/\n' > "$dir/.gitignore"
    (cd "$dir" && npm install --save-dev --save-exact --ignore-scripts --silent "$AAHP_TGZ") || return 1
    (cd "$dir" && node "node_modules/$PKG_NAME/bin/aahp.js" init . >/dev/null) || return 1
    (cd "$dir" && node "node_modules/$PKG_NAME/bin/aahp.js" manifest . --phase idle --quiet) || return 1
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "chore: init AAHP handoff files"
}

# One /handoff-shaped change: a source file plus STATUS.md and a regenerated
# manifest, committed through the installed hooks.
commit_with_handoff() {
    local dir="$1" msg="$2"
    mkdir -p "$dir/src"
    printf 'export const n = %s;\n' "$RANDOM" > "$dir/src/app.js"
    printf '\n- %s\n' "$msg" >> "$dir/.ai/handoff/STATUS.md"
    (cd "$dir" && node "node_modules/$PKG_NAME/bin/aahp.js" manifest . --phase fix --quiet) || return 1
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "$msg"
}

# Split workflow $1 into one script per `run:` step under $2 (NN.sh, NN.name,
# NN.env), in order, with the event base $3 substituted for the one GitHub
# expression the workflow is allowed to carry. Anything this harness cannot
# reproduce faithfully (another action, a job or workflow `env:`, a `shell:`,
# an `if:`, an unknown expression) is exit 3, never silently skipped: a step
# the harness drops is a step this test no longer covers.
extract_steps() {
    local wf="$1" out="$2" base="$3"
    mkdir -p "$out"
    (cd "$AAHP_ROOT" && node -e '
const fs = require("fs");
const path = require("path");
const YAML = require("yaml");
const [wf, out, base] = process.argv.slice(1);
const die = (m) => { console.error("extract_steps: " + m); process.exit(3); };
const doc = YAML.parse(fs.readFileSync(wf, "utf8"));
if (doc.env || doc.defaults) die("workflow-level env/defaults are not reproduced");
const jobs = Object.entries(doc.jobs || {});
if (jobs.length !== 1) die("expected one job, found " + jobs.length);
const job = jobs[0][1];
for (const k of ["env", "defaults", "container", "services", "if", "strategy"]) {
  if (job[k] !== undefined) die("job-level " + k + " is not reproduced");
}
const EMULATED = /^actions\/(checkout|setup-node|setup-python)@[0-9a-f]{40}$/;
const BASE_EXPR = "${{ github.event.pull_request.base.sha || github.event.before || inputs.base }}";
let n = 0;
for (const step of job.steps) {
  if (step.uses !== undefined) {
    if (!EMULATED.test(step.uses)) die("action this harness does not emulate: " + step.uses);
    continue;
  }
  if (typeof step.run !== "string") die("a step with neither run nor uses");
  for (const k of Object.keys(step)) {
    if (!["name", "run", "env"].includes(k)) die("step key not reproduced: " + k);
  }
  const env = [];
  for (const [k, v] of Object.entries(step.env || {})) {
    if (v === BASE_EXPR) env.push(k + "=" + base);
    else if (String(v).includes("${{")) die("unknown expression in " + k + ": " + v);
    else env.push(k + "=" + v);
  }
  n += 1;
  const stem = path.join(out, String(n).padStart(2, "0"));
  fs.writeFileSync(stem + ".sh", step.run);
  fs.writeFileSync(stem + ".name", step.name || "step " + n);
  fs.writeFileSync(stem + ".env", env.join("\n"));
}
if (n === 0) die("no run: steps");
process.stdout.write(String(n));
' "$wf" "$out" "$base")
}

# Run the extracted steps in order in $1, as a GitHub-hosted runner runs a
# `run:` with no `shell:` (bash -e). Stops at the first failing step, as the
# job does, and names it.
run_steps() {
    local dir="$1" steps="$2" f name rc line
    for f in "$steps"/*.sh; do
        name="$(cat "${f%.sh}.name")"
        echo "::step:: $name"
        local envs=()
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "$line" ] && envs+=("$line")
        done < "${f%.sh}.env"
        rc=0
        (cd "$dir" && env ${envs[@]+"${envs[@]}"} bash -e "$f") || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "::failed:: $name (exit $rc)"
            return "$rc"
        fi
    done
}

@test "the propagated workflow RUNS green in a real npm consumer, and red on drift" {
    local consumer="$TEST_TMPDIR/consumer" init_sha adopt_sha
    make_consumer "$consumer"
    init_sha="$(git -C "$consumer" rev-parse HEAD)"

    # Propagate from the INSTALLED package, as an adopter would.
    run bash "$consumer/node_modules/$PKG_NAME/scripts/propagate.sh" "$consumer"
    [ "$status" -eq 0 ]
    # The commit goes through the hooks propagate just installed.
    run git -C "$consumer" commit -q -m "chore: adopt the AAHP verify gate"
    [ "$status" -eq 0 ]
    adopt_sha="$(git -C "$consumer" rev-parse HEAD)"

    # A push of that commit: the event's `before` is the init commit.
    run extract_steps "$consumer/.github/workflows/aahp-verify.yml" "$TEST_TMPDIR/steps-1" "$init_sha"
    [ "$status" -eq 0 ]
    run run_steps "$consumer" "$TEST_TMPDIR/steps-1"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"::failed::"* ]]
    [[ "$output" == *"aahp verify passed (level: ci)"* ]]
    # doctor's own verify-workflow gate, run by the workflow on itself.
    [[ "$output" == *'"verify-workflow": "pass"'* ]]

    # Now drift: code changes, handoff state does not. The local hook is skipped
    # with the escape hatch, which is exactly what the CI check exists to catch.
    mkdir -p "$consumer/src"
    printf 'export const drift = true;\n' > "$consumer/src/drift.js"
    git -C "$consumer" add -A
    AAHP_SKIP_VERIFY=1 git -C "$consumer" commit -q -m "feat: code without a handoff"

    run extract_steps "$consumer/.github/workflows/aahp-verify.yml" "$TEST_TMPDIR/steps-2" "$adopt_sha"
    [ "$status" -eq 0 ]
    run run_steps "$consumer" "$TEST_TMPDIR/steps-2"
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"::failed:: Run aahp verify (CI level, no escape hatch)"* ]]
    [[ "$output" == *"Handoff-impacting files changed but handoff state did not"* ]]
}

@test "Quickstart path: the workflow copied from the installed package runs green without propagate" {
    local consumer="$TEST_TMPDIR/consumer" init_sha
    make_consumer "$consumer"
    init_sha="$(git -C "$consumer" rev-parse HEAD)"

    # README Quickstart step 5, verbatim in substance: hooks from the package,
    # the workflow copied out of the package. No vendored scripts anywhere.
    (cd "$consumer" && bash "node_modules/$PKG_NAME/scripts/install-hooks.sh" .)
    mkdir -p "$consumer/.github/workflows"
    cp "$consumer/node_modules/$PKG_NAME/assets/governance/aahp-verify.yml" "$consumer/.github/workflows/"
    [ ! -e "$consumer/scripts" ]
    run commit_with_handoff "$consumer" "chore: add the AAHP verify workflow"
    [ "$status" -eq 0 ]

    run extract_steps "$consumer/.github/workflows/aahp-verify.yml" "$TEST_TMPDIR/steps" "$init_sha"
    [ "$status" -eq 0 ]
    run run_steps "$consumer" "$TEST_TMPDIR/steps"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aahp verify passed (level: ci)"* ]]
    [[ "$output" == *'"verify-workflow": "pass"'* ]]
}
