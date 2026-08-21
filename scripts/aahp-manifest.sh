#!/usr/bin/env bash
# aahp-manifest.sh -(Re)generate MANIFEST.json from existing handoff files
#
# Usage: ./scripts/aahp-manifest.sh [path-to-project] [options]
#        Defaults to current directory if no path given.
#
# Options:
#   --agent NAME       Agent identifier (default: "cli-tool")
#   --session-id ID    Session identifier (default: auto-generated)
#   --phase PHASE      Pipeline phase: research|architecture|implementation|review|fix|idle|documentation (default: "idle")
#   --context "TEXT"    Quick context string (default: auto-generated from file summaries)
#   --duration MIN     Session duration in minutes (default: 0)
#   --quiet            Suppress output except errors
#
# Exit codes:
#   0 = manifest generated successfully
#   1 = error (no handoff directory, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

# ─── Defaults ─────────────────────────────────────────────────

AGENT="cli-tool"
SESSION_ID="cli-$(date +%s)"
PHASE="idle"
CONTEXT=""
DURATION=0
QUIET=false

# ─── Parse arguments ──────────────────────────────────────────

# First positional arg is project root (if it doesn't start with --)
PROJECT_ROOT="."
if [ $# -gt 0 ] && [[ ! "$1" == --* ]]; then
    PROJECT_ROOT="$1"
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --agent)      AGENT="$2"; shift 2 ;;
        --session-id) SESSION_ID="$2"; shift 2 ;;
        --phase)      PHASE="$2"; shift 2 ;;
        --context)    CONTEXT="$2"; shift 2 ;;
        --duration)   DURATION="$2"; shift 2 ;;
        --quiet)      QUIET=true; shift ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: aahp-manifest.sh [path-to-project] [--agent NAME] [--phase PHASE] [--context TEXT] [--duration MIN] [--session-id ID] [--quiet]" >&2
            exit 1
            ;;
    esac
done

HANDOFF_DIR="$PROJECT_ROOT/.ai/handoff"

# ─── Validate ─────────────────────────────────────────────────

if [ ! -d "$HANDOFF_DIR" ]; then
    echo "Error: $HANDOFF_DIR not found." >&2
    exit 1
fi

# Validate phase
case "$PHASE" in
    research|architecture|implementation|review|fix|idle|documentation) ;;
    *)
        echo "Error: Invalid phase '$PHASE'. Must be one of: research, architecture, implementation, review, fix, idle, documentation" >&2
        exit 1
        ;;
esac

# ─── Detect project metadata ─────────────────────────────────

# The project name must come from the repository's IDENTITY, never from the
# directory the generator happens to run in. Agents work in `git worktree`
# checkouts whose directory is named after the BRANCH, and CI unpacks into a
# workdir named after the job, so a cwd-derived name silently rewrites
# "project" to something like "myrepo-some-branch" and that lands on main.
# It is invisible unless somebody re-reads the file after regenerating.
# Resolution order, strongest evidence first:
#
#   1. the "project" already on record in MANIFEST.json (applied further down,
#      once that file has been read) - a name a human set always wins;
#   2. the git remote's repository name - stable across worktrees, temp dirs,
#      CI workdirs and tarballs, and available without node;
#   3. the directory basename - only for a genuinely new manifest in a repo
#      with no remote, which is the original behaviour.

# A recorded name is usable if it is non-empty and is not the placeholder that
# `aahp init` copies in from templates/MANIFEST.json. "[PROJECT]" on record
# means nobody ever substituted a name, so it must not suppress steps 2 and 3.
aahp_project_name_usable() {
    case "$1" in
        ''|'[PROJECT]') return 1 ;;
        *) return 0 ;;
    esac
}

# Repository name from the remote URL. Handles https, scp-style
# (host:org/repo), ssh:// and local-path remotes, with or without a .git suffix
# or a trailing slash. Only the last path segment is kept, so any credentials
# embedded in the URL are discarded with the rest of it and cannot reach
# MANIFEST.json. The result must still look like a repository name; anything
# else is rejected rather than interpolated into the JSON written below.
aahp_project_from_remote() {
    local root="$1" remote url name
    if git -C "$root" remote get-url origin >/dev/null 2>&1; then
        remote=origin
    else
        remote=$(git -C "$root" remote 2>/dev/null | head -n 1)
    fi
    [ -n "$remote" ] || return 1
    url=$(git -C "$root" remote get-url "$remote" 2>/dev/null) || return 1
    name="${url%/}"       # drop a trailing slash
    name="${name##*/}"    # keep the last path segment
    name="${name##*:}"    # scp-style remote with no slash after the colon
    name="${name%.git}"   # drop the .git suffix
    case "$name" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    printf '%s' "$name"
}

PROJECT_ABS=$(cd "$PROJECT_ROOT" && pwd)
if ! PROJECT_NAME=$(aahp_project_from_remote "$PROJECT_ABS"); then
    PROJECT_NAME=$(basename "$PROJECT_ABS")
fi
COMMIT=$(cd "$PROJECT_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── Build files object ──────────────────────────────────────

FILES_JSON=""
FILES_FOUND=0
TOTAL_TOKENS=0

for file in "${AAHP_HANDOFF_FILES[@]}"; do
    filepath="$HANDOFF_DIR/$file"
    if [ -f "$filepath" ]; then
        if [ "$FILES_FOUND" -gt 0 ]; then
            FILES_JSON="${FILES_JSON},"
        fi
        FILES_JSON="${FILES_JSON}
$(aahp_file_entry_json "$file" "$filepath")"
        FILES_FOUND=$((FILES_FOUND + 1))
        TOTAL_TOKENS=$((TOTAL_TOKENS + $(aahp_estimate_tokens "$filepath")))
    fi
done

# ─── Auto-generate context if not provided ────────────────────

if [ -z "$CONTEXT" ]; then
    # Build context from file summaries
    CONTEXT_PARTS=()
    for file in STATUS.md NEXT_ACTIONS.md; do
        filepath="$HANDOFF_DIR/$file"
        if [ -f "$filepath" ]; then
            CONTEXT_PARTS+=("$(aahp_auto_summary "$filepath")")
        fi
    done
    if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
        CONTEXT=$(printf '%s ' "${CONTEXT_PARTS[@]}" | cut -c1-500)
    else
        CONTEXT="No handoff files found with content summaries."
    fi
fi

# Escape context for JSON
CONTEXT=$(echo "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# ─── Compute token budgets ────────────────────────────────────

# Estimate manifest itself at ~80-100 tokens
MANIFEST_TOKENS=85

# Core = STATUS.md + NEXT_ACTIONS.md
CORE_TOKENS=$MANIFEST_TOKENS
for file in STATUS.md NEXT_ACTIONS.md; do
    filepath="$HANDOFF_DIR/$file"
    if [ -f "$filepath" ]; then
        CORE_TOKENS=$((CORE_TOKENS + $(aahp_estimate_tokens "$filepath")))
    fi
done

FULL_TOKENS=$((MANIFEST_TOKENS + TOTAL_TOKENS))

# ─── Preserve v3 task data from existing manifest ─────────────

TASKS_JSON=""
NEXT_TASK_ID=""
CROSS_REPO_REF=""

if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    # Extract tasks block and next_task_id if they exist
    if command -v node &>/dev/null; then
        # Read tasks, next_task_id, cross_repo_ref, and project in a SINGLE node
        # process (not four) and emit them separated by \x1f (Unit Separator).
        # Fewer spawns matter on Windows, where process creation is slow.
        # Capture stderr separately so an interpreter warning cannot corrupt the
        # record, and surface a read/parse error on stderr instead of silently
        # dropping the fields. The path is passed as argv (process.argv[1]) so
        # native Node can read it on Windows and MSYS, not only on Linux.
        # JSON.stringify emits a single line with no literal \x1f, so the split
        # is safe. \x1f is used instead of a tab because tab is IFS whitespace:
        # bash's `read` collapses runs of IFS-whitespace delimiters and strips
        # leading/trailing ones even with a custom single-character IFS, which
        # silently misaligns every field once an earlier one is empty (e.g. no
        # tasks but a project name present). \x1f is not whitespace, so empty
        # fields are preserved positionally. The command substitution sits in
        # an if-condition, which is exempt from 'set -e', so a missing or corrupt
        # MANIFEST is non-fatal: regeneration continues without the preserved
        # fields rather than aborting.
        ERR_FILE=$(mktemp)
        if MANIFEST_FIELDS=$(node -e "
            try {
                const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
                process.stdout.write([
                    m.tasks ? JSON.stringify(m.tasks) : '',
                    m.next_task_id !== undefined ? String(m.next_task_id) : '',
                    m.cross_repo_ref ? JSON.stringify(m.cross_repo_ref) : '',
                    m.project ? String(m.project) : ''
                ].join('\x1f'));
            } catch (e) {
                console.error(e.message);
                process.exit(1);
            }
        " "$HANDOFF_DIR/MANIFEST.json" 2>"$ERR_FILE"); then
            IFS=$'\x1f' read -r EXISTING EXISTING_ID EXISTING_CRR EXISTING_PROJECT <<< "$MANIFEST_FIELDS" || true
            if [ -n "$EXISTING" ]; then
                TASKS_JSON="$EXISTING"
            fi
            if [ -n "$EXISTING_ID" ] && [[ "$EXISTING_ID" =~ ^[0-9]+$ ]]; then
                NEXT_TASK_ID="$EXISTING_ID"
            fi
            if [ -n "$EXISTING_CRR" ]; then
                CROSS_REPO_REF="$EXISTING_CRR"
            fi
            if aahp_project_name_usable "$EXISTING_PROJECT"; then
                # Preserve the project name already on record instead of
                # re-deriving it: regenerating inside a differently-named
                # checkout (a worktree, a temp dir, a CI workdir, a tarball)
                # must not overwrite a consumer's real project name. An
                # unsubstituted "[PROJECT]" placeholder is not a name that
                # anybody chose, so it falls through to the remote-derived
                # value resolved above instead of being carried forward.
                PROJECT_NAME="$EXISTING_PROJECT"
            fi
        else
            echo "aahp-manifest: could not read the existing MANIFEST.json to preserve tasks/next_task_id/cross_repo_ref/project; regenerating without them." >&2
            cat "$ERR_FILE" >&2
        fi
        rm -f "$ERR_FILE"
    fi
fi

# ─── Write MANIFEST.json ─────────────────────────────────────

# Escape the project name the same way the quick context is escaped above. The
# remote-derived name is already restricted to safe characters, but a preserved
# name and a directory basename are not: an unescaped quote or backslash in
# either would emit a MANIFEST.json that no longer parses, which then fails the
# integrity layer for a reason that points nowhere near the real cause.
PROJECT_NAME=${PROJECT_NAME//\\/\\\\}
PROJECT_NAME=${PROJECT_NAME//\"/\\\"}

{
    cat <<MANIFEST
{
  "aahp_version": "3.0",
  "project": "$PROJECT_NAME",
  "last_session": {
    "agent": "$AGENT",
    "session_id": "$SESSION_ID",
    "timestamp": "$TIMESTAMP",
    "commit": "$COMMIT",
    "phase": "$PHASE",
    "duration_minutes": $DURATION
  },
  "files": {$FILES_JSON
  },
  "quick_context": "$CONTEXT",
  "token_budget": {
    "manifest_only": $MANIFEST_TOKENS,
    "manifest_plus_core": $CORE_TOKENS,
    "full_read": $FULL_TOKENS
  }
MANIFEST

    # Append v3 task fields if they exist
    if [ -n "$NEXT_TASK_ID" ]; then
        echo "  ,\"next_task_id\": $NEXT_TASK_ID"
    fi
    if [ -n "$TASKS_JSON" ]; then
        echo "  ,\"tasks\": $TASKS_JSON"
    fi
    if [ -n "$CROSS_REPO_REF" ]; then
        echo "  ,\"cross_repo_ref\": $CROSS_REPO_REF"
    fi

    echo "}"
} > "$HANDOFF_DIR/MANIFEST.json"

# ─── Output ───────────────────────────────────────────────────

if [ "$QUIET" = false ]; then
    echo "MANIFEST.json generated: $FILES_FOUND files indexed, checksums current."
    echo "  Token budget: manifest=$MANIFEST_TOKENS, core=$CORE_TOKENS, full=$FULL_TOKENS"
fi


