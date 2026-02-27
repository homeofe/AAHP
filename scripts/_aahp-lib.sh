#!/usr/bin/env bash
# _aahp-lib.sh -Shared functions for AAHP tooling
# Not intended to be run directly. Source this from other scripts.

# Standard AAHP handoff files, in canonical order
# shellcheck disable=SC2034
AAHP_HANDOFF_FILES=(STATUS.md NEXT_ACTIONS.md LOG.md DASHBOARD.md TRUST.md CONVENTIONS.md WORKFLOW.md)

# Colors (safe to re-source -same variable names used across scripts)
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
NC='\033[0m'

# Compute SHA-256 checksum for a file, output as "sha256:<hash>"
aahp_checksum() {
    local filepath="$1"
    local hash
    if command -v sha256sum &>/dev/null; then
        hash=$(sha256sum "$filepath" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        hash=$(shasum -a 256 "$filepath" | awk '{print $1}')
    else
        echo "ERROR: No SHA-256 tool found (need sha256sum or shasum)" >&2
        return 1
    fi
    echo "sha256:$hash"
}

# Get file modification time in ISO 8601 UTC
aahp_file_mtime() {
    local filepath="$1"
    date -r "$filepath" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
        stat -c '%y' "$filepath" 2>/dev/null | head -c 19
}

# Get line count
aahp_line_count() {
    wc -l < "$1" | tr -d ' '
}

# Extract a one-line summary from a handoff file (first non-header, non-empty line)
aahp_auto_summary() {
    local filepath="$1"
    local summary
    summary=$(head -5 "$filepath" \
        | grep -v '^#' | grep -v '^>' | grep -v '^---' | grep -v '^$' \
        | head -1 | cut -c1-150 || true)
    [ -z "$summary" ] && summary="(no summary available)"
    # Escape double quotes and backslashes for JSON safety
    summary=$(echo "$summary" | sed 's/\\/\\\\/g; s/"/\\"/g')
    echo "$summary"
}

# Estimate token count from a file (rough: word_count * 1.3)
aahp_estimate_tokens() {
    local filepath="$1"
    local words
    words=$(wc -w < "$filepath" | tr -d ' ')
    echo $(( (words * 13 + 9) / 10 ))
}

# Generate a JSON file entry block for MANIFEST.json
# Outputs raw JSON (no trailing comma -caller handles commas)
aahp_file_entry_json() {
    local file="$1"
    local filepath="$2"
    local checksum updated lines summary

    checksum=$(aahp_checksum "$filepath")
    updated=$(aahp_file_mtime "$filepath")
    lines=$(aahp_line_count "$filepath")
    summary=$(aahp_auto_summary "$filepath")

    cat <<ENTRY
    "$file": {
      "checksum": "$checksum",
      "updated": "$updated",
      "lines": $lines,
      "summary": "$summary"
    }
ENTRY
}
