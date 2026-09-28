#!/usr/bin/env bash
# test_helper.bash -Shared setup/teardown for AAHP bats tests

# Resolve the repo root (parent of tests/)
# Exported because .bats test files consume these after sourcing this helper
AAHP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AAHP_ROOT
SCRIPTS_DIR="$AAHP_ROOT/scripts"
export SCRIPTS_DIR

# --- Cross-platform path helper -----------------------------
# On Windows Git Bash, mktemp returns /tmp/... which native tools (python, node)
# cannot resolve. We create temp dirs under USERPROFILE on Windows and use
# cygpath -m to get a mixed-mode path (C:/Users/...) that works everywhere.

_make_tmpdir() {
    local tmpdir
    if command -v cygpath &>/dev/null; then
        # Windows Git Bash: create in a location that native tools can read.
        # Every process costs 0.1 s or more under MSYS, so the spelling is done
        # in bash: ${USERPROFILE//\\//} is what `cygpath -m "$USERPROFILE"`
        # returns for a drive or UNC path, and mktemp given a mixed-mode template
        # already answers in mixed mode (both measured, Git for Windows 2.53).
        local base="${USERPROFILE//\\//}/AppData/Local/Temp"
        [ -d "$base" ] || mkdir -p "$base"
        tmpdir=$(mktemp -d "$base/aahp-test.XXXXXX")
        # Return mixed-mode path (C:/...) that bash AND python/node can use
        case "$tmpdir" in
            [A-Za-z]:/*) ;;
            *) tmpdir=$(cygpath -m "$tmpdir") ;;
        esac
    else
        tmpdir=$(mktemp -d)
    fi
    echo "$tmpdir"
}

# --- Git isolation -------------------------------------------
# Every test drives git against a throwaway repository, so nothing from the
# machine running the suite may reach it:
#   - a global core.hooksPath would RECEIVE the hooks install-hooks.sh and
#     propagate.sh write (install-hooks.sh honours core.hooksPath), and a global
#     commit.gpgsign=true fails the fixture commit in setup();
#   - a system config (Git for Windows ships core.autocrlf, init.defaultBranch,
#     filter.lfs.*) makes the same test behave differently per machine;
#   - GIT_DIR / GIT_INDEX_FILE and friends are set when the suite runs from a
#     git hook, and would point every `git -C "$TEST_TMPDIR" add` at the OUTER
#     repository's index;
#   - GIT_CONFIG_PARAMETERS carries `git -c` settings from a parent git.
# GIT_CONFIG_GLOBAL needs git 2.32+; /dev/null is the value git documents for
# "read no global config" and is honoured by Git for Windows from both Git Bash
# and a native node spawn (measured, 2.53). The identity is exported rather than
# written per repository, so repositories a test creates itself get it too.
_aahp_isolate_git() {
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX \
        GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
    export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"
}

# Build (once per bats run) the fixture every test starts from: .ai/handoff/
# plus a git repository with one empty "init" commit. Each test gets its own
# COPY, so isolation is unchanged; what is saved is four git processes per test
# (init, two config, commit), which is most of setup() on Windows.
# Sets AAHP_FIXTURE_TEMPLATE; returns 1 when there is no run directory to hold
# it (bats < 1.4), and setup() then builds the fixture in place as before.
_aahp_fixture_template() {
    AAHP_FIXTURE_TEMPLATE=""
    [ -n "${BATS_RUN_TMPDIR:-}" ] && [ -d "$BATS_RUN_TMPDIR" ] || return 1
    local tpl="$BATS_RUN_TMPDIR/aahp-fixture-template"
    if [ ! -d "$tpl/.git" ]; then
        local build="$tpl.$$"
        rm -rf "$build"
        if ! { mkdir -p "$build/.ai/handoff" &&
            git init -q "$build" &&
            git -C "$build" config user.name "test" &&
            git -C "$build" config user.email "test@test.local" &&
            git -C "$build" commit --allow-empty -m "init" -q; }; then
            rm -rf "$build"
            return 1
        fi
        # A directory rename is atomic, so a concurrent test (bats --jobs) sees
        # either no template or a complete one. If another test won the race,
        # mv moves this build INSIDE the winner, where nothing ever copies it.
        mv "$build" "$tpl" 2>/dev/null || rm -rf "$build"
    fi
    [ -d "$tpl/.git" ] || return 1
    AAHP_FIXTURE_TEMPLATE="$tpl"
}

# --- Prerequisites: skip locally, FAIL on CI -----------------
# `[ -n "$py" ] || skip "..."` fails OPEN: if the lookup itself breaks, the
# test turns into a green skip and nothing asserts anything. A developer machine
# may legitimately lack python or symlink support; the CI runner must not, so
# with CI set (GitHub Actions sets CI=true) a missing prerequisite is a failure.
#
#   require_tool "no working python interpreter" [ -n "$py" ]
#
# The first argument is the skip reason, the rest is the command that must
# succeed. scripts/run-bats.mjs enforces the same rule for every other skip.
_aahp_ci() {
    case "${CI:-}" in
        "" | 0 | false | FALSE | False | no) return 1 ;;
    esac
    return 0
}

require_tool() {
    local reason="$1"
    shift
    if "$@"; then
        return 0
    fi
    if _aahp_ci; then
        echo "require_tool: $reason" >&2
        echo "require_tool: CI=${CI} - a missing prerequisite FAILS here instead of skipping (tests/README.md)" >&2
        return 1
    fi
    skip "$reason"
}

# --- Setup / Teardown ----------------------------------------

setup() {
    _aahp_isolate_git

    # Create a unique temporary directory for each test
    TEST_TMPDIR="$(_make_tmpdir)"
    export TEST_TMPDIR

    # Git must never discover a repository ABOVE the temp base (a dotfiles repo
    # in $HOME, a checkout that holds $TMPDIR): tests that remove .git to put a
    # target "outside any work tree" rely on it. TEST_TMPDIR itself is still found.
    GIT_CEILING_DIRECTORIES="${TEST_TMPDIR%/*}"
    export GIT_CEILING_DIRECTORIES

    # The handoff directory structure plus a git repo with an initial commit, so
    # scripts that call git don't fail and HEAD exists.
    if _aahp_fixture_template; then
        cp -R "$AAHP_FIXTURE_TEMPLATE/.git" "$AAHP_FIXTURE_TEMPLATE/.ai" "$TEST_TMPDIR/"
    else
        mkdir -p "$TEST_TMPDIR/.ai/handoff"
        git init -q "$TEST_TMPDIR"
        git -C "$TEST_TMPDIR" config user.name "test"
        git -C "$TEST_TMPDIR" config user.email "test@test.local"
        git -C "$TEST_TMPDIR" commit --allow-empty -m "init" -q
    fi
}

teardown() {
    # Clean up the temporary directory
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# --- Fixture Helpers -----------------------------------------

# Create a minimal STATUS.md
create_status_md() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    cat > "$dir/STATUS.md" <<'EOF'
# TestProject: Current State of the Nation

> Last updated: 2025-06-01 by test-agent

## Build Health

| Check | Result | Notes |
|-------|--------|-------|
| `build` | pass | All good |
| `test`  | pass | 10/10 |
EOF
}

# Create a minimal NEXT_ACTIONS.md
create_next_actions_md() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    cat > "$dir/NEXT_ACTIONS.md" <<'EOF'
# TestProject: Next Actions for Incoming Agent

> Priority order. Work top-down.

---

## T-001: Implement feature X

**Goal:** Build the widget.

**What to do:**
1. Create src/widget.ts
2. Add tests
EOF
}

# Create a minimal LOG.md
create_log_md() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    cat > "$dir/LOG.md" <<'EOF'
# TestProject: Agent Journal

> Append-only. Never delete or edit past entries.

---

## [2025-06-01] test-agent: Initial setup

**Agent:** test-agent
**Phase:** 1 (Research)

### What was done

- Initialised project structure
- Created handoff files
EOF
}

# Create a minimal valid MANIFEST.json (v3-compatible).
#
# The index covers EVERY canonical handoff file that exists in $dir RIGHT NOW,
# with its real checksum, exactly like the generator in aahp-manifest.sh. It
# used to be hard-coded to `"files": {}`, and then to three files out of the
# eleven canonical ones, which is a partial index: both gates now treat that as
# a finding, because a file with no entry is never compared to anything. A
# fixture whose baseline is partial could never catch a partial-index defect.
# Files absent from $dir are not indexed, so a fixture that seeds no handoff
# files still gets a manifest with no dangling entries.
#
# Call this AGAIN after editing a handoff file if the test expects lint or
# verify to pass; otherwise the edit is a genuine integrity violation and the
# gate is right to say so.
create_manifest_json() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    # shellcheck source=../scripts/_aahp-lib.sh
    source "$SCRIPTS_DIR/_aahp-lib.sh"

    local entries="" f sum lines
    for f in "${AAHP_HANDOFF_FILES[@]}"; do
        [ -f "$dir/$f" ] || continue
        sum="$(aahp_checksum "$dir/$f")"
        lines="$(aahp_line_count "$dir/$f")"
        entries="${entries}${entries:+,}
    \"$f\": {
      \"checksum\": \"$sum\",
      \"updated\": \"2025-06-01T00:00:00Z\",
      \"lines\": $lines,
      \"summary\": \"test fixture\"
    }"
    done

    cat > "$dir/MANIFEST.json" <<MANIFEST
{
  "aahp_version": "3.0",
  "project": "TestProject",
  "last_session": {
    "agent": "test-agent",
    "session_id": "test-001",
    "timestamp": "2025-06-01T00:00:00Z",
    "commit": "abc1234",
    "phase": "idle",
    "duration_minutes": 0
  },
  "files": {$entries
  },
  "quick_context": "Test fixture project.",
  "token_budget": {
    "manifest_only": 85,
    "manifest_plus_core": 85,
    "full_read": 85
  }
}
MANIFEST
}

# Create a MANIFEST.json that includes tasks and next_task_id (v3 fields)
create_manifest_with_tasks() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    cat > "$dir/MANIFEST.json" <<'MANIFEST'
{
  "aahp_version": "3.0",
  "project": "TestProject",
  "last_session": {
    "agent": "test-agent",
    "session_id": "test-001",
    "timestamp": "2025-06-01T00:00:00Z",
    "commit": "abc1234",
    "phase": "idle",
    "duration_minutes": 0
  },
  "files": {},
  "quick_context": "Test fixture project.",
  "token_budget": {
    "manifest_only": 85,
    "manifest_plus_core": 85,
    "full_read": 85
  },
  "next_task_id": 3,
  "tasks": {
    "T-001": {
      "title": "Implement feature X",
      "status": "done",
      "priority": "high"
    },
    "T-002": {
      "title": "Add tests for feature X",
      "status": "ready",
      "priority": "high",
      "depends_on": ["T-001"]
    }
  }
}
MANIFEST
}

# Create all standard handoff files for a "clean" handoff directory
create_full_handoff() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    create_status_md "$dir"
    create_next_actions_md "$dir"
    create_log_md "$dir"
    create_manifest_json "$dir"
}

# Create a HANDOFF.lock file
create_lock_file() {
    local dir="${1:-$TEST_TMPDIR/.ai/handoff}"
    cat > "$dir/HANDOFF.lock" <<'EOF'
agent: stale-agent
session_id: stale-session-123
started: 2025-01-01T00:00:00Z
EOF
}
