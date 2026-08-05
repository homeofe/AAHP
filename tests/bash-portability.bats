#!/usr/bin/env bats
# bash-portability.bats - Windows-safe resolution of the bash interpreter and
# of the paths handed to it.
#
# aahp-dashboard.mjs is the ONLY place in AAHP that shells out to bash (every
# other execFileSync runs `git` or process.execPath, both native binaries that
# accept Windows paths as-is). It ran `process.env.AAHP_BASH || "bash"` with
# raw join() paths, which fails on Windows in two independent ways:
#
#   1. A native path is backslash-separated and bash consumes each backslash as
#      an escape, so "C:\Users\x\s.sh" arrives as "C:Usersxs.sh".
#   2. A bare "bash" is not reliably a POSIX shell. A default Git for Windows
#      install puts only Git's cmd/ on PATH (git.exe, not bash.exe), while
#      Windows ships C:\Windows\System32\bash.exe: the WSL launcher. PATH order
#      then selects WSL, which has no C: drive and cannot open the script at
#      all, however the path is spelled.
#
# Observed failure, AAHP 3.9.1 on Windows against a consumer-shaped config:
#   /bin/bash: C:UsersrootworkspaceAAHPscriptsaahp-manifest.sh:
#   No such file or directory
#   .ai/handoff/LOG.md was written, but MANIFEST.json regen failed
# Note both defects are visible at once: the separators are gone AND the
# interpreter is WSL's /bin/bash.
#
# This never surfaced in AAHP's own dogfooding because AAHP sets only
# generate.freshness, so writeLog() returns at the "no generate.log configured"
# early exit (aahp-dashboard.mjs) BEFORE reaching the bash call. Only a consumer
# that configures generate.log executes it. A Windows CI job on AAHP alone would
# therefore still not cover this, which is why resolveBash/toBashPath take
# platform and env as parameters: the win32 behaviour is asserted here
# deterministically on the Linux runner.

load test_helper

CFG="$SCRIPTS_DIR/aahp-config.mjs"
DASH="$SCRIPTS_DIR/aahp-dashboard.mjs"

# Evaluate an expression against the exported helpers and print the result.
#
# The body is written to a file and the module path is passed as argv, then
# converted with pathToFileURL. Passing it as an import specifier would break
# under Git Bash, where $SCRIPTS_DIR is a POSIX path that node cannot resolve;
# argv is mangled to a native path by MSYS, and pathToFileURL normalises both.
#
# Backslashes are produced with String.fromCharCode(92) rather than written
# literally so that no shell or heredoc layer can reinterpret them.
probe() {
    {
        echo "import { pathToFileURL } from 'node:url';"
        echo "const { toBashPath, resolveBash } = await import(pathToFileURL(process.argv[2]).href);"
        echo "const BS = String.fromCharCode(92);"
        echo "$1"
    } > "$TEST_TMPDIR/probe.mjs"
    node "$TEST_TMPDIR/probe.mjs" "$CFG"
}

# --- toBashPath --------------------------------------------------------------

# Every toBashPath test passes an explicit cwd. relative()/isAbsolute() use the
# HOST's path semantics regardless of the `platform` argument, so an implicit
# cwd makes the chosen strategy depend on where the suite runs. Each test below
# pins one strategy with a cwd that selects it identically on Linux and Windows.

@test "toBashPath: strategy 1 prefers a relative path, which needs no drive letter" {
    run probe 'console.log(toBashPath("/repo/scripts/m.sh", "win32", "/repo"));'
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/m.sh" ]
}

@test "toBashPath: strategy 2 converts a drive path to the MSYS form bash understands" {
    run probe 'console.log(toBashPath("C:" + BS + "Users" + BS + "x" + BS + "s.sh", "win32", "C:" + BS + "Other"));'
    [ "$status" -eq 0 ]
    [ "$output" = "/c/Users/x/s.sh" ]
}

@test "toBashPath: strategy 3 leaves an already-forward-slashed path untouched" {
    run probe 'console.log(toBashPath("C:/already/forward.sh", "win32", "C:" + BS + "Other"));'
    [ "$status" -eq 0 ]
    [ "$output" = "C:/already/forward.sh" ]
}

@test "toBashPath: is a no-op off win32, where a backslash is a legal filename character" {
    run probe 'console.log(toBashPath("/tmp/odd" + BS + "name.sh", "linux", "/tmp"));'
    [ "$status" -eq 0 ]
    [ "$output" = '/tmp/odd\name.sh' ]
}

# --- resolveBash -------------------------------------------------------------

@test "resolveBash: AAHP_BASH wins on win32" {
    run probe 'console.log(resolveBash({ AAHP_BASH: "/custom/bash" }, "win32"));'
    [ "$status" -eq 0 ]
    [ "$output" = "/custom/bash" ]
}

@test "resolveBash: AAHP_BASH wins off win32" {
    run probe 'console.log(resolveBash({ AAHP_BASH: "/custom/bash" }, "linux"));'
    [ "$status" -eq 0 ]
    [ "$output" = "/custom/bash" ]
}

@test "resolveBash: returns PATH bash off win32" {
    run probe 'console.log(resolveBash({}, "linux"));'
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

# The candidates are built with join(), which emits the HOST separator, so the
# raw result differs between a Linux runner and Git Bash. These compare with
# separators normalised on BOTH sides rather than pinning one spelling, and
# print the actual value on mismatch.

@test "resolveBash: on win32 prefers an installed Git Bash over the PATH lookup" {
    mkdir -p "$TEST_TMPDIR/Git/bin"
    : > "$TEST_TMPDIR/Git/bin/bash.exe"
    run probe "const got = resolveBash({ ProgramFiles: '$TEST_TMPDIR' }, 'win32');
const fwd = (s) => s.split(BS).join('/');
console.log(fwd(got) === fwd('$TEST_TMPDIR/Git/bin/bash.exe') ? 'MATCH' : 'MISMATCH: ' + got);"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCH" ]
}

@test "resolveBash: on win32 finds Git's usr/bin layout too" {
    mkdir -p "$TEST_TMPDIR/Git/usr/bin"
    : > "$TEST_TMPDIR/Git/usr/bin/bash.exe"
    run probe "const got = resolveBash({ ProgramFiles: '$TEST_TMPDIR' }, 'win32');
const fwd = (s) => s.split(BS).join('/');
console.log(fwd(got) === fwd('$TEST_TMPDIR/Git/usr/bin/bash.exe') ? 'MATCH' : 'MISMATCH: ' + got);"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCH" ]
}

@test "resolveBash: on win32 finds a per-user Git install via LOCALAPPDATA" {
    mkdir -p "$TEST_TMPDIR/Programs/Git/bin"
    : > "$TEST_TMPDIR/Programs/Git/bin/bash.exe"
    run probe "const got = resolveBash({ ProgramFiles: '$TEST_TMPDIR/absent', LOCALAPPDATA: '$TEST_TMPDIR' }, 'win32');
const fwd = (s) => s.split(BS).join('/');
console.log(fwd(got) === fwd('$TEST_TMPDIR/Programs/Git/bin/bash.exe') ? 'MATCH' : 'MISMATCH: ' + got);"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCH" ]
}

@test "resolveBash: on win32 falls back to bash when no Git Bash is installed" {
    run probe "console.log(resolveBash({ ProgramFiles: '$TEST_TMPDIR/absent' }, 'win32'));"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

# --- de-duplication guard ----------------------------------------------------

# bin/aahp.js used to carry its OWN toBashScriptArg/findBashExecutable. That
# second implementation is why the same Windows defect had to be found twice:
# the CLI knew about relative paths and the /c/ form, the dashboard call site
# knew neither, and neither knew about the other. Both now share one
# implementation, and this test fails if a copy is reintroduced.
@test "bin/aahp.js does not reimplement bash resolution" {
    run grep -nE "function (findBashExecutable|toBashScriptArg)" "$AAHP_ROOT/bin/aahp.js"
    [ "$status" -ne 0 ]
    run grep -c "from '../scripts/aahp-config.mjs'" "$AAHP_ROOT/bin/aahp.js"
    [ "$output" -ge 1 ]
}

# --- wiring: the dashboard actually uses them --------------------------------

# Asserts the argv the dashboard hands to the interpreter. On Linux this pins
# the wiring (script path and root arrive as two separate, resolvable
# arguments); run under Git Bash on Windows the same assertions become a direct
# regression test for defect 1, because an unconverted path would arrive with
# its separators stripped.
@test "handoff-refresh: passes a resolvable script path and root to the interpreter" {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) skip "stand-in interpreter relies on a POSIX shebang" ;;
    esac

    echo '{ "name": "fx", "version": "1.0.0" }' > "$TEST_TMPDIR/package.json"
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "generate": { "log": { "source": "CHANGELOG.md", "target": ".ai/handoff/LOG.md" } } }
EOF
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01
**First release**

### Added
- Initial cut.
EOF

    # Stand-in interpreter: records argv instead of running the script.
    cat > "$TEST_TMPDIR/fakebash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$AAHP_ARGV_OUT"
EOF
    chmod +x "$TEST_TMPDIR/fakebash"

    export AAHP_BASH="$TEST_TMPDIR/fakebash"
    export AAHP_ARGV_OUT="$TEST_TMPDIR/argv.txt"
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    local script_arg root_arg
    script_arg="$(sed -n '1p' "$TEST_TMPDIR/argv.txt")"
    root_arg="$(sed -n '2p' "$TEST_TMPDIR/argv.txt")"

    # Both paths must survive the trip intact, not merely be non-empty.
    [ -f "$script_arg" ]
    [ -d "$root_arg" ]
    [[ "$script_arg" == *"aahp-manifest.sh" ]]
    # The remaining flags stay in order after the two positionals.
    [ "$(sed -n '3p' "$TEST_TMPDIR/argv.txt")" = "--agent" ]
    [ "$(sed -n '7p' "$TEST_TMPDIR/argv.txt")" = "--quiet" ]
}
