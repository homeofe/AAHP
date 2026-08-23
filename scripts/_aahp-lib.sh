#!/usr/bin/env bash
# _aahp-lib.sh -Shared functions for AAHP tooling
# Not intended to be run directly. Source this from other scripts.

# Standard AAHP handoff files, in canonical order
# shellcheck disable=SC2034
AAHP_HANDOFF_FILES=(STATUS.md NEXT_ACTIONS.md LOG.md LOG-ARCHIVE.md LOG-ARCHIVE.index.json DASHBOARD.md TRUST.md CONVENTIONS.md WORKFLOW.md GROUNDING.md pii-allowlist.json)

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
#
# Returns non-zero when no digest could be produced. An empty digest must
# never be reported as success: callers write the result into MANIFEST.json or
# compare it against a recorded checksum, and "sha256:" with nothing after it
# would be baked in as if it were a real hash, after which a broken toolchain
# reports a clean handoff set forever.
aahp_checksum() {
    local filepath="$1"
    local hash
    # Strip CR before hashing so a file checksums identically regardless of
    # CRLF vs LF line endings (Windows working tree vs Linux CI checkout).
    # Must stay in lockstep with the verifier in lint-handoff.sh.
    if command -v sha256sum &>/dev/null; then
        hash=$(tr -d '\r' < "$filepath" | sha256sum | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        hash=$(tr -d '\r' < "$filepath" | shasum -a 256 | awk '{print $1}')
    else
        echo "ERROR: No SHA-256 tool found (need sha256sum or shasum)" >&2
        return 1
    fi
    if [ -z "$hash" ]; then
        echo "ERROR: Could not compute a checksum for: $filepath" >&2
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
    # Look past title/blockquote/header chrome (handoff files often start with
    # # headings and > rules). First 40 content lines is enough for a one-liner.
    summary=$(head -40 "$filepath" \
        | tr -d '\r' \
        | grep -v '^#' | grep -v '^>' | grep -v '^---' | grep -v '^$' \
        | grep -v '^<!--' | grep -v '^|[-:| ]*$' \
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

# Detect a working Python interpreter (python3 preferred, then python).
# The Windows Store python3 alias passes `command -v` but does not run, so we
# verify with an actual invocation. Echoes the command name or empty string.
aahp_python_cmd() {
    if python3 -c "pass" &>/dev/null 2>&1; then
        echo "python3"
    elif python -c "pass" &>/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

# Read a dotted field from a MANIFEST.json file (e.g. "last_session.commit").
# Echoes the value or empty string. Uses node if present, else python.
aahp_manifest_field() {
    local manifest="$1"
    local dotted="$2"
    [ -f "$manifest" ] || { echo ""; return 0; }

    if command -v node &>/dev/null; then
        node -e "
            const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
            const v = process.argv[2].split('.').reduce((o, k) => (o == null ? o : o[k]), m);
            if (v !== undefined && v !== null) process.stdout.write(String(v));
        " "$manifest" "$dotted" 2>/dev/null || true
        return 0
    fi

    local py
    py=$(aahp_python_cmd)
    if [ -n "$py" ]; then
        "$py" -c "
import json, sys
m = json.load(open(sys.argv[1]))
cur = m
for k in sys.argv[2].split('.'):
    if isinstance(cur, dict) and k in cur:
        cur = cur[k]
    else:
        cur = None
        break
if cur is not None:
    sys.stdout.write(str(cur))
" "$manifest" "$dotted" 2>/dev/null || true
    fi
}

# Read the file index out of a MANIFEST.json.
# Echoes one TAB-separated "<name>\t<recorded-checksum>" line per indexed file.
#
# This exists so aahp verify Layer 1 can reach its OWN verdict on both
# MANIFEST integrity failures (a missing indexed file and a checksum mismatch)
# without reading another script's exit code or string-matching its stdout.
# The caller does the existence test and the checksum comparison itself, so a
# helper that cannot answer must SAY SO rather than echo an empty, innocent
# looking index. Hence the exit codes below: every failure mode is
# distinguishable from "the manifest indexes nothing", and none of them is
# silently converted into a pass.
#
# Exit codes:
#   0 = index read successfully (zero output lines = the manifest indexes
#       nothing, which is a finding for the caller, not a clean result)
#   1 = MANIFEST.json is absent, unreadable, or not valid JSON
#   2 = no JSON interpreter available (neither node nor python)
aahp_manifest_index() {
    local manifest="$1"
    [ -f "$manifest" ] && [ -r "$manifest" ] || return 1

    if command -v node &>/dev/null; then
        node -e '
            const fs = require("fs");
            const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
            const files = (m && typeof m === "object" && m.files) || {};
            for (const name of Object.keys(files)) {
                const meta = files[name];
                const sum = (meta && typeof meta === "object" && meta.checksum) || "";
                process.stdout.write(name + "\t" + String(sum) + "\n");
            }
        ' "$manifest" || return 1
        return 0
    fi

    local py
    py=$(aahp_python_cmd)
    [ -n "$py" ] || return 2

    # Written through the BINARY stdout buffer on purpose. Text-mode stdout
    # translates "\n" into CRLF on Windows, the trailing CR is then read back
    # into the recorded-checksum field, and every comparison mismatches on a
    # machine that takes this fallback. Bytes out, exactly what was written.
    "$py" -c '
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
files = (m.get("files") or {}) if isinstance(m, dict) else {}
out = sys.stdout.buffer
for name, meta in files.items():
    checksum = meta.get("checksum", "") if isinstance(meta, dict) else ""
    out.write(("%s\t%s\n" % (name, checksum)).encode("utf-8"))
out.flush()
' "$manifest" || return 1
}

# Read and validate the reviewed Layer 2 exception list from aahp.config.json.
# Echoes one TAB-separated "<file>\t<reason>" line per exact file entry.
#
# The parser deliberately validates the complete handoffImpact shape here,
# rather than trusting an optional external schema command. verify-handoff.sh
# is propagated into repositories that may have only Node or Python available,
# and a required CI gate must fail closed on malformed configuration.
#
# Paths use a conservative, cross-platform repo-relative grammar. This keeps
# every entry literal and reviewable: no pathspec magic, globbing, traversal,
# control characters, or platform-dependent separators can enter the git
# classifier. The caller separately proves each returned path is a tracked
# file, not a directory.
#
# Exit codes:
#   0 = config absent, section absent, or section valid
#   1 = config unreadable, malformed, or invalid
#   2 = no JSON interpreter available (neither node nor python)
aahp_non_impacting_modified_files() {
    local config="$1"
    if [ ! -e "$config" ] && [ ! -L "$config" ]; then
        return 0
    fi
    if [ ! -f "$config" ] || [ ! -r "$config" ]; then
        echo "aahp.config.json is not a readable regular file" >&2
        return 1
    fi

    if command -v node &>/dev/null; then
        # Single quotes are intentional: the embedded JavaScript contains
        # template literals whose ${...} expressions belong to Node, not bash.
        # shellcheck disable=SC2016
        node -e '
            const fs = require("fs");
            const fail = (message) => { throw new Error(message); };
            const text = fs.readFileSync(process.argv[1], "utf8");
            const cfg = JSON.parse(text);

            // JSON.parse silently keeps the last duplicate object key. That is
            // unsafe for a reviewed policy file: the key a reviewer sees first
            // may not be the value the gate enforces. The input is known-valid
            // JSON at this point, so a small recursive scanner can reject every
            // duplicate key without becoming a second permissive parser.
            let cursor = 0;
            const whitespace = () => { while (/\s/.test(text[cursor] || "")) cursor += 1; };
            const stringToken = () => {
              const start = cursor;
              cursor += 1;
              while (cursor < text.length) {
                if (text[cursor] === "\\") { cursor += 2; continue; }
                if (text[cursor] === "\"") { cursor += 1; return JSON.parse(text.slice(start, cursor)); }
                cursor += 1;
              }
              fail("unterminated JSON string");
            };
            const value = () => {
              whitespace();
              if (text[cursor] === "{") return object();
              if (text[cursor] === "[") {
                cursor += 1; whitespace();
                if (text[cursor] === "]") { cursor += 1; return; }
                while (true) {
                  value(); whitespace();
                  if (text[cursor] === "]") { cursor += 1; return; }
                  cursor += 1;
                }
              }
              if (text[cursor] === "\"") { stringToken(); return; }
              while (cursor < text.length && !/[\s,}\]]/.test(text[cursor])) cursor += 1;
            };
            const object = () => {
              cursor += 1; whitespace();
              const keys = new Set();
              if (text[cursor] === "}") { cursor += 1; return; }
              while (true) {
                const key = stringToken();
                if (keys.has(key)) fail(`duplicate JSON object key: ${key}`);
                keys.add(key);
                whitespace(); cursor += 1; value(); whitespace();
                if (text[cursor] === "}") { cursor += 1; return; }
                cursor += 1; whitespace();
              }
            };
            value();
            if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) {
              fail("top level must be an object");
            }
            if (!Object.prototype.hasOwnProperty.call(cfg, "handoffImpact")) process.exit(0);
            const impact = cfg.handoffImpact;
            if (!impact || typeof impact !== "object" || Array.isArray(impact)) {
              fail("handoffImpact must be an object");
            }
            const impactKeys = Object.keys(impact);
            if (impactKeys.some((key) => key !== "nonImpactingModifiedFiles")) {
              fail("handoffImpact contains an unknown property");
            }
            const entries = impact.nonImpactingModifiedFiles;
            if (!Array.isArray(entries)) {
              fail("handoffImpact.nonImpactingModifiedFiles must be an array");
            }
            const seen = [];
            for (let index = 0; index < entries.length; index += 1) {
              const entry = entries[index];
              const label = `handoffImpact.nonImpactingModifiedFiles[${index}]`;
              if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                fail(`${label} must be an object`);
              }
              const keys = Object.keys(entry);
              if (keys.length !== 2 || !keys.includes("file") || !keys.includes("reason")) {
                fail(`${label} must contain exactly file and reason`);
              }
              const file = entry.file;
              const reason = entry.reason;
              if (typeof file !== "string" || file.length === 0 || file.trim() !== file) {
                fail(`${label}.file must be a non-empty, trimmed string`);
              }
              if (typeof reason !== "string" || !/[\p{L}\p{N}]/u.test(reason) || /[\p{Cc}\p{Cf}]/u.test(reason)) {
                fail(`${label}.reason must contain a letter or number and no control or format characters`);
              }
              if (/^[\\/]/.test(file) || /^[A-Za-z]:/.test(file) || file.includes("\\")) {
                fail(`${label}.file must be repo-relative and use forward slashes`);
              }
              if (!/^[A-Za-z0-9._@+ -]+(?:\/[A-Za-z0-9._@+ -]+)*$/.test(file)) {
                fail(`${label}.file contains a glob or unsupported metacharacter`);
              }
              const parts = file.split("/");
              if (parts.some((part) => part === "." || part === "..")) {
                fail(`${label}.file must not contain dot or traversal segments`);
              }
              const folded = file.toLowerCase();
              if (folded === "aahp.config.json" || folded === ".ai/handoff" || folded.startsWith(".ai/handoff/")) {
                fail(`${label}.file cannot classify the config or handoff state as non-impacting`);
              }
              if (seen.some((prior) => prior === folded || prior.startsWith(folded) || folded.startsWith(prior))) {
                fail(`${label}.file duplicates or ambiguously prefixes another entry`);
              }
              seen.push(folded);
              process.stdout.write(file + "\t" + reason.trim() + "\n");
            }
        ' "$config" || return 1
        return 0
    fi

    local py
    py=$(aahp_python_cmd)
    [ -n "$py" ] || return 2
    "$py" -c '
import json, re, sys, unicodedata

def fail(message):
    raise ValueError(message)

def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("duplicate JSON object key: " + key)
        result[key] = value
    return result

with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = json.load(
        handle,
        object_pairs_hook=no_duplicate_keys,
        parse_constant=lambda value: fail("non-standard JSON constant: " + value),
    )
if not isinstance(cfg, dict):
    fail("top level must be an object")
if "handoffImpact" not in cfg:
    raise SystemExit(0)
impact = cfg["handoffImpact"]
if not isinstance(impact, dict):
    fail("handoffImpact must be an object")
if any(key != "nonImpactingModifiedFiles" for key in impact):
    fail("handoffImpact contains an unknown property")
entries = impact.get("nonImpactingModifiedFiles")
if not isinstance(entries, list):
    fail("handoffImpact.nonImpactingModifiedFiles must be an array")
seen = []
for index, entry in enumerate(entries):
    label = "handoffImpact.nonImpactingModifiedFiles[%d]" % index
    if not isinstance(entry, dict):
        fail(label + " must be an object")
    if set(entry) != {"file", "reason"}:
        fail(label + " must contain exactly file and reason")
    file = entry["file"]
    reason = entry["reason"]
    if not isinstance(file, str) or not file or file.strip() != file:
        fail(label + ".file must be a non-empty, trimmed string")
    if (
        not isinstance(reason, str)
        or not any(char.isalnum() for char in reason)
        or any(unicodedata.category(char) in ("Cc", "Cf") for char in reason)
    ):
        fail(label + ".reason must contain a letter or number and no control or format characters")
    if file.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", file) or "\\" in file:
        fail(label + ".file must be repo-relative and use forward slashes")
    if not re.fullmatch(r"[A-Za-z0-9._@+ -]+(?:/[A-Za-z0-9._@+ -]+)*", file):
        fail(label + ".file contains a glob or unsupported metacharacter")
    if any(part in (".", "..") for part in file.split("/")):
        fail(label + ".file must not contain dot or traversal segments")
    folded = file.lower()
    if folded == "aahp.config.json" or folded == ".ai/handoff" or folded.startswith(".ai/handoff/"):
        fail(label + ".file cannot classify the config or handoff state as non-impacting")
    if any(prior == folded or prior.startswith(folded) or folded.startswith(prior) for prior in seen):
        fail(label + ".file duplicates or ambiguously prefixes another entry")
    seen.append(folded)
    sys.stdout.buffer.write((file + "\t" + reason.strip() + "\n").encode("utf-8"))
' "$config" || return 1
}

# Report expired "verified" trust rows from a TRUST.md file.
# Trust tables are Markdown with a header row that includes "Status" and
# "Expires" columns. We locate those columns from the header, then for each
# data row treat it as expired when its Status cell is "verified" and its
# Expires cell is a YYYY-MM-DD date strictly before the given today.
# The first cell of the row is reported as the property name.
# Echoes one "Property (expired Expires)" line per expired row.
aahp_trust_expired() {
    local trust_file="$1"
    local today="$2"
    [ -f "$trust_file" ] || return 0

    # Implemented in awk for portability (no python dependency).
    awk -v today="$today" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        # A markdown table row starts with a pipe.
        /^[ \t]*\|/ {
            n = split($0, cell, "|")
            for (i = 1; i <= n; i++) cell[i] = trim(cell[i])

            # Separator row like | --- | --- | : skip it.
            sep = 1
            for (i = 2; i < n; i++) {
                if (cell[i] != "" && cell[i] !~ /^:?-+:?$/) { sep = 0; break }
            }
            if (sep) next

            # Header row: it names the Status and Expires columns. Record their
            # positions, then move on. Reset on every header so multiple tables
            # in one file are each handled with their own column layout.
            is_header = 0
            for (i = 2; i < n; i++) {
                lc = tolower(cell[i])
                if (lc == "status")  { status_col = i; is_header = 1 }
                if (lc == "expires") { expires_col = i; is_header = 1 }
            }
            if (is_header) next

            # Data row: need both columns known.
            if (status_col == 0 || expires_col == 0) next
            if (tolower(cell[status_col]) != "verified") next
            expiry = cell[expires_col]
            if (expiry !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) next
            if (expiry < today) {
                print cell[2] " (expired " expiry ")"
            }
        }
        # Reset column tracking at horizontal rules / blank-ish boundaries so a
        # stray table without a header does not reuse stale column indices.
        /^[ \t]*$/ { status_col = 0; expires_col = 0 }
    ' "$trust_file"
}

# Census of what the TTL reader above could actually READ in a TRUST.md.
# Echoes two integers on one line: "<decidable> <candidate>".
#
#   decidable - rows that reached the expiry comparison: the row sits in a table
#               with both a Status and an Expires header column, its Status cell
#               says `verified`, and its Expires cell is a YYYY-MM-DD date.
#               This is the DENOMINATOR of aahp_trust_expired.
#   candidate - data rows in any table that names a Status OR an Expires column.
#               A register this reader cannot classify still lands here.
#
# WHY THIS EXISTS. aahp_trust_expired prints nothing in two completely different
# situations: no verified row is expired, and no verified row was READ AT ALL.
# Its caller could not tell them apart, so it reported "No expired 'verified'
# trust entries." for a register it never managed to parse - a control
# announcing a clean result over a file it did not read.
#
# This is not hypothetical and not a Windows artefact. Measured 2026-08-23
# across the nine consuming repositories in this estate: SIX have a TRUST.md in
# which this reader sees zero decidable rows. In one of them the register is a
# real, populated `Verified Properties` table whose header is
# `| Property | Value | Verified | TTL | Expires | Provenance |` - an Expires
# column and no Status column, because the section heading carries the status.
# Every row is skipped for want of status_col, one of them was 8 days past its
# expiry on the day this was measured, and Layer 4 called the register clean.
#
# Splitting `candidate` from `decidable` is what turns that into a report a
# reader can act on: candidate == 0 means there is no trust table here at all,
# while candidate > 0 with decidable == 0 means there IS one and this reader
# could not classify a single row of it. Those need different answers, and
# neither of them is "no expired entries".
aahp_trust_census() {
    local trust_file="$1"
    [ -f "$trust_file" ] || { echo "0 0"; return 0; }

    awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        BEGIN { decidable = 0; candidate = 0 }
        /^[ \t]*\|/ {
            n = split($0, cell, "|")
            for (i = 1; i <= n; i++) cell[i] = trim(cell[i])

            sep = 1
            for (i = 2; i < n; i++) {
                if (cell[i] != "" && cell[i] !~ /^:?-+:?$/) { sep = 0; break }
            }
            if (sep) next

            is_header = 0
            for (i = 2; i < n; i++) {
                lc = tolower(cell[i])
                if (lc == "status")  { status_col = i; is_header = 1 }
                if (lc == "expires") { expires_col = i; is_header = 1 }
            }
            if (is_header) next

            # A data row under a header that named either column is a row this
            # register meant to be read, whether or not it can be decided.
            if (status_col == 0 && expires_col == 0) next
            candidate++

            if (status_col == 0 || expires_col == 0) next
            if (tolower(cell[status_col]) != "verified") next
            if (cell[expires_col] !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) next
            decidable++
        }
        /^[ \t]*$/ { status_col = 0; expires_col = 0 }
        END { print decidable + 0, candidate + 0 }
    ' "$trust_file"
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
