#!/usr/bin/env bash
# test_helper.bash -Shared setup/teardown for AAHP bats tests

# Resolve the repo root (parent of tests/)
AAHP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$AAHP_ROOT/scripts"

# ─── Cross-platform path helper ─────────────────────────────
# On Windows Git Bash, mktemp returns /tmp/... which native tools (python, node)
# cannot resolve. We create temp dirs under USERPROFILE on Windows and use
# cygpath -m to get a mixed-mode path (C:/Users/...) that works everywhere.

_make_tmpdir() {
    local tmpdir
    if command -v cygpath &>/dev/null; then
        # Windows Git Bash: create in a location that native tools can read
        local base
        base="$(cygpath -m "$USERPROFILE")/AppData/Local/Temp"
        mkdir -p "$base"
        tmpdir=$(mktemp -d "$base/aahp-test.XXXXXX")
        # Return mixed-mode path (C:/...) that bash AND python/node can use
        tmpdir=$(cygpath -m "$tmpdir")
    else
        tmpdir=$(mktemp -d)
    fi
    echo "$tmpdir"
}

# ─── Setup / Teardown ────────────────────────────────────────

setup() {
    # Create a unique temporary directory for each test
    TEST_TMPDIR="$(_make_tmpdir)"
    export TEST_TMPDIR

    # Create the handoff directory structure
    mkdir -p "$TEST_TMPDIR/.ai/handoff"

    # Initialise a git repo so scripts that call git don't fail
    git init -q "$TEST_TMPDIR"
    # Configure user identity (required on CI where global config may be absent)
    git -C "$TEST_TMPDIR" config user.name "test"
    git -C "$TEST_TMPDIR" config user.email "test@test.local"
    # Create an initial commit so HEAD exists
    git -C "$TEST_TMPDIR" commit --allow-empty -m "init" -q
}

teardown() {
    # Clean up the temporary directory
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# ─── Fixture Helpers ─────────────────────────────────────────

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

# Create a minimal valid MANIFEST.json (v3-compatible)
create_manifest_json() {
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
