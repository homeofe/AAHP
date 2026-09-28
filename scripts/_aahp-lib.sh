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

# Get line count
aahp_line_count() {
    wc -l < "$1" | tr -d ' '
}

# The per-file MANIFEST helpers that used to live here (aahp_file_mtime,
# aahp_auto_summary, aahp_estimate_tokens, aahp_file_entry_json) are gone.
# Their only consumer was the old heredoc generator, and between them they
# built JSON by string concatenation: a failed checksum became
# `"checksum": ""` with exit 0, a TAB or a quote produced invalid JSON, and a
# byte-based `cut` split multi-byte characters. scripts/aahp-manifest.sh now
# builds the whole document in one node process.

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
m = json.load(open(sys.argv[1], encoding='utf-8'))
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
            if (impactKeys.some((key) => key !== "nonImpactingModifiedFiles" && key !== "npmDevDependencyUpdates")) {
              fail("handoffImpact contains an unknown property");
            }
            if (impactKeys.length === 0) {
              fail("handoffImpact must declare nonImpactingModifiedFiles or npmDevDependencyUpdates");
            }
            if (Object.prototype.hasOwnProperty.call(impact, "npmDevDependencyUpdates")) {
              // Shape only. What the opt-in asserts about the repository (the
              // scanner job exists and runs on pull_request) is proven by the
              // caller against the inspected snapshot, not by this parser.
              const npm = impact.npmDevDependencyUpdates;
              const label = "handoffImpact.npmDevDependencyUpdates";
              if (!npm || typeof npm !== "object" || Array.isArray(npm)) fail(`${label} must be an object`);
              const npmKeys = Object.keys(npm);
              if (npmKeys.length !== 2 || !npmKeys.includes("reason") || !npmKeys.includes("supplyChainScan")) {
                fail(`${label} must contain exactly reason and supplyChainScan`);
              }
              if (typeof npm.reason !== "string" || !/[\p{L}\p{N}]/u.test(npm.reason) || /[\p{Cc}\p{Cf}]/u.test(npm.reason)) {
                fail(`${label}.reason must contain a letter or number and no control or format characters`);
              }
              const scan = npm.supplyChainScan;
              if (!scan || typeof scan !== "object" || Array.isArray(scan)) fail(`${label}.supplyChainScan must be an object`);
              const scanKeys = Object.keys(scan);
              if (scanKeys.length !== 2 || !scanKeys.includes("workflow") || !scanKeys.includes("job")) {
                fail(`${label}.supplyChainScan must contain exactly workflow and job`);
              }
              if (typeof scan.workflow !== "string" || !/^\.github\/workflows\/[A-Za-z0-9_-][A-Za-z0-9._-]*\.ya?ml$/.test(scan.workflow)) {
                fail(`${label}.supplyChainScan.workflow must name a file directly under .github/workflows/ ending in .yml or .yaml`);
              }
              if (typeof scan.job !== "string" || !/^[A-Za-z_][A-Za-z0-9_-]{0,99}$/.test(scan.job)) {
                fail(`${label}.supplyChainScan.job must be a GitHub Actions job id`);
              }
            }
            const entries = Object.prototype.hasOwnProperty.call(impact, "nonImpactingModifiedFiles")
              ? impact.nonImpactingModifiedFiles : [];
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
if any(key not in ("nonImpactingModifiedFiles", "npmDevDependencyUpdates") for key in impact):
    fail("handoffImpact contains an unknown property")
if not impact:
    fail("handoffImpact must declare nonImpactingModifiedFiles or npmDevDependencyUpdates")
if "npmDevDependencyUpdates" in impact:
    npm = impact["npmDevDependencyUpdates"]
    label = "handoffImpact.npmDevDependencyUpdates"
    if not isinstance(npm, dict):
        fail(label + " must be an object")
    if set(npm) != {"reason", "supplyChainScan"}:
        fail(label + " must contain exactly reason and supplyChainScan")
    npm_reason = npm["reason"]
    if (
        not isinstance(npm_reason, str)
        or not any(char.isalnum() for char in npm_reason)
        or any(unicodedata.category(char) in ("Cc", "Cf") for char in npm_reason)
    ):
        fail(label + ".reason must contain a letter or number and no control or format characters")
    scan = npm["supplyChainScan"]
    if not isinstance(scan, dict):
        fail(label + ".supplyChainScan must be an object")
    if set(scan) != {"workflow", "job"}:
        fail(label + ".supplyChainScan must contain exactly workflow and job")
    if not isinstance(scan["workflow"], str) or not re.fullmatch(r"\.github/workflows/[A-Za-z0-9_-][A-Za-z0-9._-]*\.ya?ml", scan["workflow"]):
        fail(label + ".supplyChainScan.workflow must name a file directly under .github/workflows/ ending in .yml or .yaml")
    if not isinstance(scan["job"], str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]{0,99}", scan["job"]):
        fail(label + ".supplyChainScan.job must be a GitHub Actions job id")
entries = impact.get("nonImpactingModifiedFiles", [])
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

# --- Layer 2: content-verified npm devDependency updates ---------------------
#
# `handoffImpact.npmDevDependencyUpdates` is an OPT-IN, CONTENT-based
# classification. Nothing here looks at who made a change (no actor, bot name
# or author field is ever read); it looks at what the change set contains. The
# two helpers below are the two halves of the owner's condition: the change
# itself must be a registry-pinned devDependency-only lockfile update, and the
# repository must run a supply-chain scanner on pull requests.

# Prove, from a GitHub Actions workflow on stdin, that job <job> exists and is
# triggered on pull_request. Echoes the reason and exits 1 when that cannot be
# shown; exits 0 when it can.
#
# Reads the block-YAML subset workflows use: a top-level `on:` (scalar, flow
# list, block list or block mapping) and a top-level `jobs:` mapping. It proves
# less than it might look like, and says so in README 2.8:
#   - it cannot see repository settings, so it cannot prove the job is a
#     REQUIRED status check (that is a branch-protection setting);
#   - a job-level `if:` must name pull_request, but the expression itself is not
#     evaluated;
#   - a job with `continue-on-error` other than false is refused, because its
#     failure could not block a merge;
#   - `paths:` filters are not evaluated; a required check that never reports
#     leaves a pull request pending, which fails closed.
# Anything it cannot read (tabs in indentation, flow-style jobs) is "not proven".
aahp_workflow_job_on_pull_request() {
    local job="$1"
    awk -v job="$job" -v sq="'" '
        function tok(s) { s = " " s " "; return (s ~ /[^A-Za-z0-9_]pull_request[^A-Za-z0-9_]/) }
        function unq(s) { gsub(/"/, "", s); gsub(sq, "", s); return s }
        BEGIN { on_seen = 0; on_pr = 0; in_on = 0; in_jobs = 0; found = 0; in_target = 0
                on_ci = -1; jobs_ci = -1; job_ci = -1; job_if = ""; coe = ""; collect_if = 0; bad = "" }
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
            if (line ~ /^ *\t/) { bad = "tab characters in indentation"; next }
            match(line, /^ */)
            ind = RLENGTH
            body = substr(line, ind + 1)
            sub(/[ \t]+#.*$/, "", body)
            sub(/[ \t]+$/, "", body)
            key = ""; val = ""
            if (substr(body, 1, 2) != "- ") {
                if (match(body, /^[^:]+: /)) {
                    key = substr(body, 1, RLENGTH - 2)
                    val = substr(body, RLENGTH + 1)
                } else if (match(body, /^[^:]+:$/)) {
                    key = substr(body, 1, RLENGTH - 1)
                }
                sub(/[ \t]+$/, "", key)
                key = unq(key)
                sub(/^[ \t]+/, "", val)
            }

            if (collect_if) {
                if (ind > job_ci) { job_if = job_if " " body; next }
                collect_if = 0
            }

            if (ind == 0) {
                if (substr(body, 1, 2) == "- " && in_on) {
                    item = unq(substr(body, 3))
                    if (item == "pull_request") on_pr = 1
                    next
                }
                in_on = 0; in_jobs = 0; in_target = 0
                if (key == "on" || key == "true") {
                    in_on = 1; on_seen = 1
                    if (val != "" && tok(val)) on_pr = 1
                } else if (key == "jobs") {
                    in_jobs = 1
                    if (val != "") bad = "jobs is not a block mapping"
                }
                next
            }

            if (in_on) {
                if (on_ci < 0) on_ci = ind
                if (ind == on_ci) {
                    if (substr(body, 1, 2) == "- ") {
                        if (unq(substr(body, 3)) == "pull_request") on_pr = 1
                    } else if (key == "pull_request") {
                        on_pr = 1
                    }
                }
                next
            }

            if (in_jobs) {
                if (jobs_ci < 0) jobs_ci = ind
                if (ind == jobs_ci) {
                    in_target = (key == job)
                    if (in_target) { found = 1; job_ci = -1 }
                    next
                }
                if (in_target && ind > jobs_ci) {
                    if (job_ci < 0) job_ci = ind
                    if (ind == job_ci) {
                        if (key == "if") {
                            job_if = val
                            if (val ~ /^[|>]/) { job_if = ""; collect_if = 1 }
                            if (job_if == "" && !collect_if) job_if = "(empty)"
                        } else if (key == "continue-on-error") {
                            coe = val
                        }
                    }
                }
            }
        }
        END {
            if (bad != "") { print "the workflow could not be read (" bad ")"; exit 1 }
            if (!on_seen) { print "the workflow has no top-level on: trigger"; exit 1 }
            if (!on_pr) { print "the workflow is not triggered by pull_request"; exit 1 }
            if (!found) { print "job " job " is not defined under jobs:"; exit 1 }
            if (job_if != "" && !tok(job_if)) {
                print "job " job " has an if: condition that does not name pull_request, so it cannot be shown to run on pull requests"
                exit 1
            }
            if (coe != "" && unq(coe) != "false") {
                print "job " job " sets continue-on-error, so its failure could not block a merge"
                exit 1
            }
            exit 0
        }
    '
}

# Decide whether a lockfile change is a registry-pinned devDependency update.
#
#   aahp_npm_dev_update_verdict <old-rev> <path-prefix> <with-package-json 0|1>
#
# Compares `<old-rev>:<prefix>package-lock.json` with the INDEX copy
# `:<prefix>package-lock.json` (and the same for package.json when the change
# set includes it). The index is the inspected snapshot at every level: staged
# changes at precommit, the checked-out HEAD in CI.
#
# Conforms only when ALL of these hold, and echoes one line per violation:
#   - every top-level lockfile key except `packages` is unchanged;
#   - at least one installed package entry (`node_modules/...`) changed;
#   - every changed entry is `node_modules/...`, is `dev: true` before AND
#     after (a removed entry must have been dev: true), is not a link, has no
#     install script (`hasInstallScript: true`, whether new or kept), carries a
#     sha256/384/512 `integrity`, and is `resolved` under
#     https://registry.npmjs.org/;
#   - the root entry `packages[""]` and package.json differ, if at all, only in
#     devDependencies VALUES that are plain registry version specifiers on both
#     sides (same package names in the same order).
#
# Node only: the parse needs a JSON interpreter and this classification is an
# opt-in exemption, so without Node it is simply not applied (the change stays
# impacting). Exit codes: 0 conforms, 1 violations echoed, 2 no node,
# 3 a blob could not be read.
aahp_npm_dev_update_verdict() {
    local old_rev="$1" prefix="$2" with_pkg="$3"
    command -v node &>/dev/null || { echo "node is not available to parse package-lock.json"; return 2; }
    # shellcheck disable=SC2016
    node -e '
        const { execFileSync } = require("child_process");
        const [oldRev, prefix, withPkg] = process.argv.slice(1);
        const violations = [];
        const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
        const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
        const SPEC = /^(?:\^|~|>=|=)?v?(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
        const load = (spec, label) => {
          let text;
          try {
            text = execFileSync("git", ["cat-file", "blob", spec], {
              encoding: "utf8", maxBuffer: 512 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"],
            });
          } catch (e) {
            process.stdout.write("could not read " + label + " (" + spec + ")\n");
            process.exit(3);
          }
          try { return JSON.parse(text); } catch (e) {
            violations.push(label + " is not valid JSON");
            return undefined;
          }
        };
        const devSpecOnly = (a, b, label) => {
          if (!isObj(a) || !isObj(b)) { violations.push(label + " is not a JSON object on both sides"); return; }
          const rest = (o) => { const c = Object.assign({}, o); delete c.devDependencies; return c; };
          if (!same(rest(a), rest(b))) {
            const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
            const changed = keys.filter((k) => k !== "devDependencies" && !same(a[k], b[k]));
            violations.push(label + " changed outside devDependencies: " + (changed.join(", ") || "key order"));
          }
          const od = a.devDependencies;
          const nd = b.devDependencies;
          if (od === undefined && nd === undefined) return;
          if (!isObj(od) || !isObj(nd) || !same(Object.keys(od), Object.keys(nd))) {
            violations.push(label + " devDependencies added, removed or reordered a package");
            return;
          }
          for (const name of Object.keys(nd)) {
            if (od[name] === nd[name]) continue;
            if (typeof od[name] !== "string" || typeof nd[name] !== "string" || !SPEC.test(od[name]) || !SPEC.test(nd[name])) {
              violations.push(label + " devDependencies " + JSON.stringify(name) + " is not a registry version specifier on both sides");
            }
          }
        };

        const oldLock = load(oldRev + ":" + prefix + "package-lock.json", "the base package-lock.json");
        const newLock = load(":" + prefix + "package-lock.json", "the new package-lock.json");
        if (isObj(oldLock) && isObj(newLock)) {
          const top = Array.from(new Set(Object.keys(oldLock).concat(Object.keys(newLock))));
          for (const key of top) {
            if (key !== "packages" && !same(oldLock[key], newLock[key])) {
              violations.push("package-lock.json top-level " + JSON.stringify(key) + " changed; only the packages map may change");
            }
          }
          const op = oldLock.packages;
          const np = newLock.packages;
          if (!isObj(op) || !isObj(np)) {
            violations.push("package-lock.json has no packages map on both sides (lockfileVersion 2 or 3 is required)");
          } else {
            let changed = 0;
            const keys = Array.from(new Set(Object.keys(op).concat(Object.keys(np))));
            for (const key of keys) {
              const before = op[key];
              const after = np[key];
              if (same(before, after)) continue;
              if (key === "") { devSpecOnly(before, after, "package-lock.json root entry"); continue; }
              changed += 1;
              const label = "package-lock.json entry " + JSON.stringify(key);
              if (!key.startsWith("node_modules/")) { violations.push(label + " is not an installed package (workspace or link)"); continue; }
              if (after === undefined) {
                if (!isObj(before) || before.dev !== true) violations.push(label + " was removed but was not dev: true");
                continue;
              }
              if (!isObj(after)) { violations.push(label + " is not an object"); continue; }
              if (before !== undefined && (!isObj(before) || before.dev !== true)) violations.push(label + " was not dev: true before this change (a runtime dependency changed)");
              if (after.dev !== true) violations.push(label + " is not dev: true");
              if (after.link === true) violations.push(label + " is a link, not a registry package");
              // An install script runs on every `npm ci` without --ignore-scripts,
              // developer machines included. An update that introduces or keeps
              // one is exactly what must not pass without a handoff record.
              if (after.hasInstallScript === true) violations.push(label + " has an install script (hasInstallScript: true)");
              if (typeof after.integrity !== "string" || !/^sha(?:512|384|256)-[A-Za-z0-9+/]+={0,2}$/.test(after.integrity)) violations.push(label + " has no sha256/384/512 integrity");
              if (typeof after.resolved !== "string" || !after.resolved.startsWith("https://registry.npmjs.org/")) violations.push(label + " is not resolved under https://registry.npmjs.org/");
            }
            if (changed === 0) violations.push("package-lock.json changed no installed package entry, so this is not a dependency update");
            else if (violations.length === 0) process.stdout.write(changed + " lock entr(ies) checked\n");
          }
        } else {
          violations.push("package-lock.json is not a JSON object on both sides");
        }
        if (withPkg === "1") {
          const oldPkg = load(oldRev + ":" + prefix + "package.json", "the base package.json");
          const newPkg = load(":" + prefix + "package.json", "the new package.json");
          devSpecOnly(oldPkg, newPkg, "package.json");
        }
        if (violations.length) {
          process.stdout.write(violations.join("\n") + "\n");
          process.exit(1);
        }
    ' "$old_rev" "$prefix" "$with_pkg"
}

# --- Layer 4: trust policy, trust rows, and executable trust checks ----------
#
# Handoff files are untrusted, agent-written DATA (CONSTITUTION 5). A TRUST.md
# row may NAME a check, but nothing read from TRUST.md is ever executed or put
# on a command line: the name is looked up in a fixed table of built-in checks
# (implemented in verify-handoff.sh) and in `trustTtl.checks` of
# aahp.config.json, which is code-reviewed configuration. A name found in
# neither place is a failed check, never a command.

# Built-in check ids. Config-declared checks may not reuse them, so an id always
# means exactly one thing.
# shellcheck disable=SC2034
AAHP_TRUST_BUILTIN_CHECKS="license-matches manifest-integrity"

# Days an expired, date-judged `verified` row stays a WARNING before it can
# block under trustTtl.enforce. 14 days: the measured failure (2026-09-22) was a
# required check turning red on a calendar date with no code change and no
# scheduled run to warn first. Fourteen days is two weekly Dependabot cycles, so
# even a quiet repository gets at least two routine pull-request runs that print
# the expiry before it blocks, and it is shorter than half of the 30-day tier
# README 2.5 gives stable facts. 0 restores block-on-expiry.
# shellcheck disable=SC2034
AAHP_TRUST_DEFAULT_GRACE_DAYS=14

# Read the trustTtl section of aahp.config.json.
# Echoes TAB-separated "key<TAB>value" lines:
#   enforce<TAB>0|1
#   graceDays<TAB><integer>
#   check<TAB><id>          (one per config-declared check)
#
# Opt-in, on the same pattern as pinnedDep: absent config, absent section, or
# enforce:false all mean 0, so a repository that has never heard of this setting
# keeps the advisory behaviour it has always had.
#
# Fails closed on a config it cannot read. A required CI gate must not silently
# fall back to "not enforcing" because the policy file is broken, since that
# turns a malformed config into a way to switch the gate off.
#
# DUPLICATE KEYS. Every JSON parser here keeps the LAST duplicate object key, so
# a reviewer reading `"enforce": true` near the top can be looking at a file
# whose effective value is a `false` further down. Both readers below walk the
# raw JSON and refuse ANY duplicate key, at any depth (Node: a small scanner over
# text already proven to be valid JSON; Python: object_pairs_hook). That replaces
# an earlier textual count of `"trustTtl"`, which refused valid configs that
# merely mentioned the key in a string and missed `{"enforce":true,"enforce":false}`.
#
# Exit codes:
#   0 = policy determined (echoed)
#   1 = config unreadable, malformed, ambiguous, or invalid
#   2 = no JSON interpreter available (neither node nor python)
aahp_trust_policy() {
    local config="$1"
    if [ ! -e "$config" ] && [ ! -L "$config" ]; then
        printf 'enforce\t0\ngraceDays\t%s\n' "$AAHP_TRUST_DEFAULT_GRACE_DAYS"
        return 0
    fi
    if [ ! -f "$config" ] || [ ! -r "$config" ]; then
        echo "aahp.config.json is not a readable regular file" >&2
        return 1
    fi

    local py
    if command -v node &>/dev/null; then
        # shellcheck disable=SC2016
        node -e '
            const fs = require("fs");
            const fail = (m) => { process.stderr.write("aahp.config.json: " + m + "\n"); process.exit(1); };
            const text = fs.readFileSync(process.argv[1], "utf8");
            let cfg;
            try { cfg = JSON.parse(text); } catch (e) { fail("not valid JSON (" + e.message + ")"); }
            let cursor = 0;
            const ws = () => { while (/\s/.test(text[cursor] || "")) cursor += 1; };
            const str = () => {
              const start = cursor; cursor += 1;
              while (cursor < text.length) {
                if (text[cursor] === "\\") { cursor += 2; continue; }
                if (text[cursor] === "\"") { cursor += 1; return JSON.parse(text.slice(start, cursor)); }
                cursor += 1;
              }
              fail("unterminated JSON string");
            };
            const value = () => {
              ws();
              if (text[cursor] === "{") return object();
              if (text[cursor] === "[") {
                cursor += 1; ws();
                if (text[cursor] === "]") { cursor += 1; return; }
                while (true) { value(); ws(); if (text[cursor] === "]") { cursor += 1; return; } cursor += 1; }
              }
              if (text[cursor] === "\"") { str(); return; }
              while (cursor < text.length && !/[\s,}\]]/.test(text[cursor])) cursor += 1;
            };
            const object = () => {
              cursor += 1; ws();
              const keys = new Set();
              if (text[cursor] === "}") { cursor += 1; return; }
              while (true) {
                const key = str();
                if (keys.has(key)) fail("duplicate JSON object key: " + key);
                keys.add(key);
                ws(); cursor += 1; value(); ws();
                if (text[cursor] === "}") { cursor += 1; return; }
                cursor += 1; ws();
              }
            };
            value();
            if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) fail("top level must be an object");
            const builtins = process.argv[3].split(" ");
            const out = [];
            const section = cfg.trustTtl;
            let enforce = false;
            let grace = Number(process.argv[2]);
            if (section !== undefined) {
              if (section === null || typeof section !== "object" || Array.isArray(section)) fail("trustTtl must be an object");
              for (const key of Object.keys(section)) {
                if (!["enforce", "graceDays", "checks"].includes(key)) fail("trustTtl contains an unknown property: " + key);
              }
              if (section.enforce !== undefined && typeof section.enforce !== "boolean") fail("trustTtl.enforce must be true or false");
              enforce = section.enforce === true;
              if (section.graceDays !== undefined) {
                if (!Number.isInteger(section.graceDays) || section.graceDays < 0 || section.graceDays > 365) fail("trustTtl.graceDays must be an integer from 0 to 365");
                grace = section.graceDays;
              }
              if (section.checks !== undefined) {
                if (!Array.isArray(section.checks)) fail("trustTtl.checks must be an array");
                const seen = new Set();
                section.checks.forEach((entry, index) => {
                  const label = "trustTtl.checks[" + index + "]";
                  if (!entry || typeof entry !== "object" || Array.isArray(entry)) fail(label + " must be an object");
                  const keys = Object.keys(entry);
                  if (keys.length !== 3 || !["id", "run", "reason"].every((k) => keys.includes(k))) fail(label + " must contain exactly id, run and reason");
                  if (typeof entry.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(entry.id)) fail(label + ".id must be 1-64 lowercase letters, digits or hyphens, starting with a letter or digit");
                  if (builtins.includes(entry.id)) fail(label + ".id reuses the built-in check id " + entry.id);
                  if (seen.has(entry.id)) fail(label + ".id duplicates another check: " + entry.id);
                  seen.add(entry.id);
                  if (!Array.isArray(entry.run) || entry.run.length === 0) fail(label + ".run must be a non-empty array of strings (argv, no shell)");
                  entry.run.forEach((arg, argIndex) => {
                    if (typeof arg !== "string" || arg.length === 0 || /[\p{Cc}]/u.test(arg)) fail(label + ".run[" + argIndex + "] must be a non-empty string without control characters");
                  });
                  if (typeof entry.reason !== "string" || !/[\p{L}\p{N}]/u.test(entry.reason) || /[\p{Cc}\p{Cf}]/u.test(entry.reason)) fail(label + ".reason must contain a letter or number and no control or format characters");
                  out.push("check\t" + entry.id);
                });
              }
            }
            process.stdout.write("enforce\t" + (enforce ? "1" : "0") + "\ngraceDays\t" + grace + "\n" + out.map((l) => l + "\n").join(""));
        ' "$config" "$AAHP_TRUST_DEFAULT_GRACE_DAYS" "$AAHP_TRUST_BUILTIN_CHECKS" || return 1
        return 0
    fi

    py=$(aahp_python_cmd)
    if [ -z "$py" ]; then
        echo "no JSON interpreter available (neither node nor python)" >&2
        return 2
    fi
    "$py" -c '
import json, re, sys, unicodedata

def fail(message):
    sys.stderr.write("aahp.config.json: " + message + "\n")
    raise SystemExit(1)

def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            fail("duplicate JSON object key: " + key)
        result[key] = value
    return result

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        cfg = json.load(handle, object_pairs_hook=pairs,
                        parse_constant=lambda c: fail("non-standard JSON constant: " + c))
except ValueError as exc:
    fail("not valid JSON (%s)" % exc)
if not isinstance(cfg, dict):
    fail("top level must be an object")
builtins = sys.argv[3].split(" ")
enforce = False
grace = int(sys.argv[2])
checks = []
section = cfg.get("trustTtl")
if "trustTtl" in cfg:
    if not isinstance(section, dict):
        fail("trustTtl must be an object")
    for key in section:
        if key not in ("enforce", "graceDays", "checks"):
            fail("trustTtl contains an unknown property: " + key)
    value = section.get("enforce")
    if "enforce" in section and not isinstance(value, bool):
        fail("trustTtl.enforce must be true or false")
    enforce = value is True
    if "graceDays" in section:
        g = section["graceDays"]
        if isinstance(g, bool) or not isinstance(g, int) or g < 0 or g > 365:
            fail("trustTtl.graceDays must be an integer from 0 to 365")
        grace = g
    if "checks" in section:
        if not isinstance(section["checks"], list):
            fail("trustTtl.checks must be an array")
        seen = set()
        for index, entry in enumerate(section["checks"]):
            label = "trustTtl.checks[%d]" % index
            if not isinstance(entry, dict):
                fail(label + " must be an object")
            if set(entry) != {"id", "run", "reason"}:
                fail(label + " must contain exactly id, run and reason")
            cid = entry["id"]
            if not isinstance(cid, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", cid):
                fail(label + ".id must be 1-64 lowercase letters, digits or hyphens, starting with a letter or digit")
            if cid in builtins:
                fail(label + ".id reuses the built-in check id " + cid)
            if cid in seen:
                fail(label + ".id duplicates another check: " + cid)
            seen.add(cid)
            run = entry["run"]
            if not isinstance(run, list) or not run:
                fail(label + ".run must be a non-empty array of strings (argv, no shell)")
            for arg_index, arg in enumerate(run):
                if (not isinstance(arg, str) or not arg
                        or any(unicodedata.category(ch) == "Cc" for ch in arg)):
                    fail(label + ".run[%d] must be a non-empty string without control characters" % arg_index)
            reason = entry["reason"]
            if (not isinstance(reason, str) or not any(ch.isalnum() for ch in reason)
                    or any(unicodedata.category(ch) in ("Cc", "Cf") for ch in reason)):
                fail(label + ".reason must contain a letter or number and no control or format characters")
            checks.append(cid)
out = sys.stdout.buffer
out.write(("enforce\t%s\ngraceDays\t%d\n" % ("1" if enforce else "0", grace)).encode("utf-8"))
for cid in checks:
    out.write(("check\t%s\n" % cid).encode("utf-8"))
out.flush()
' "$config" "$AAHP_TRUST_DEFAULT_GRACE_DAYS" "$AAHP_TRUST_BUILTIN_CHECKS" || return 1
}

# Read trustTtl.enforce from aahp.config.json. Echoes "1" or "0".
# Kept for callers that only need the switch; it applies the full validation of
# aahp_trust_policy, so it fails (exit 1) or reports no interpreter (exit 2)
# exactly when that helper does.
aahp_trust_enforce() {
    local policy rc=0
    policy=$(aahp_trust_policy "$1") || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    printf '%s\n' "$policy" | awk -F '\t' '$1 == "enforce" { print $2 }'
}

# Run ONE config-declared trust check by id, from aahp.config.json.
#
# The argv comes from trustTtl.checks[].run in the reviewed config and is
# executed WITHOUT a shell, in the current directory (the project root), with
# stdin closed and a 120-second timeout. The id argument is only a lookup key:
# callers pass what a TRUST.md row names, and that text never reaches argv.
# On failure the last lines of the check's output are echoed for the log.
#
# Exit codes:
#   0 = the check ran and exited 0
#   1 = the check ran and failed, timed out, or could not be started
#   2 = no interpreter available to run it (neither node nor python)
#   3 = no check with that id is declared
aahp_trust_run_check() {
    local config="$1" id="$2" py
    [ -f "$config" ] || { echo "no aahp.config.json, so no declared checks"; return 3; }
    if command -v node &>/dev/null; then
        # shellcheck disable=SC2016
        node -e '
            const fs = require("fs");
            const { spawnSync } = require("child_process");
            const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
            const checks = (cfg && cfg.trustTtl && Array.isArray(cfg.trustTtl.checks)) ? cfg.trustTtl.checks : [];
            const entry = checks.find((c) => c && c.id === process.argv[2]);
            if (!entry || !Array.isArray(entry.run) || entry.run.length === 0) {
              process.stdout.write("not declared in trustTtl.checks\n");
              process.exit(3);
            }
            const r = spawnSync(entry.run[0], entry.run.slice(1), {
              cwd: process.cwd(), shell: false, windowsHide: true, encoding: "utf8",
              stdio: ["ignore", "pipe", "pipe"], timeout: 120000, maxBuffer: 16 * 1024 * 1024,
            });
            const tail = () => ((r.stdout || "") + (r.stderr || "")).split(/\r?\n/).filter((l) => l.trim()).slice(-5);
            if (r.error) {
              process.stdout.write("could not run " + JSON.stringify(entry.run[0]) + ": " + (r.error.code || r.error.message) + "\n");
              process.exit(1);
            }
            if (r.status !== 0) {
              const why = r.signal ? "was stopped by " + r.signal + " (the limit is 120 s)" : "exited " + r.status;
              process.stdout.write([why].concat(tail()).join("\n") + "\n");
              process.exit(1);
            }
        ' "$config" "$id"
        return $?
    fi
    py=$(aahp_python_cmd)
    [ -n "$py" ] || { echo "no interpreter available to run the check"; return 2; }
    "$py" -c '
import json, subprocess, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = json.load(handle)
section = cfg.get("trustTtl") if isinstance(cfg, dict) else None
checks = section.get("checks", []) if isinstance(section, dict) else []
entry = next((c for c in checks if isinstance(c, dict) and c.get("id") == sys.argv[2]), None)
if not entry or not isinstance(entry.get("run"), list) or not entry["run"]:
    print("not declared in trustTtl.checks")
    raise SystemExit(3)
try:
    r = subprocess.run(entry["run"], cwd=".", shell=False, stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
except subprocess.TimeoutExpired:
    print("was stopped after 120 s")
    raise SystemExit(1)
except OSError as exc:
    print("could not run %r: %s" % (entry["run"][0], exc))
    raise SystemExit(1)
if r.returncode != 0:
    lines = [l for l in r.stdout.decode("utf-8", "replace").splitlines() if l.strip()][-5:]
    print("\n".join(["exited %d" % r.returncode] + lines))
    raise SystemExit(1)
' "$config" "$id"
}

# Read every trust row out of a TRUST.md, one line per data row, with the
# fields separated by "|" (a table cell can never contain one, because cells
# are split on it; a TAB separator would silently collapse empty fields in
# `read`):
#
#   <status>|<days-past-expiry>|<expires>|<check>|<property>
#
#   status           the Status cell lower-cased ("" when the table has none)
#   days-past-expiry today minus the Expires date in days: positive = expired,
#                    0 = expires today, negative = still valid. "" when the
#                    Expires cell is not a real YYYY-MM-DD date.
#   expires          the Expires cell as written
#   check            the Check cell with backticks removed, "" when absent or "-"
#   property         the first cell of the row
#
# A table is read when its header row names a `Status` or an `Expires` column;
# an optional `Check` column is picked up from the same header. Rows of any
# other table are not emitted, so the number of lines printed is the census
# denominator: zero lines means there is no trust table here at all, which the
# caller must never report as "no expired entries".
#
# WHY THE CENSUS MATTERS. An earlier reader printed nothing both when nothing was
# expired and when not one row was parsed, and the gate called both clean.
# Measured 2026-08-23 across the nine consuming repositories in this estate: SIX
# had a TRUST.md in which that reader saw zero decidable rows, one of them a real
# `| Property | Value | Verified | TTL | Expires | Provenance |` table (no Status
# column) holding a row 8 days past its expiry, reported as clean.
#
# PORTABILITY. No regex interval expressions (`{4}`): mawk before 1.3.4-20200120
# (Debian and Ubuntu shipped 1.3.3 for years) treats the braces literally, so a
# date pattern written with them matches nothing and every row silently becomes
# undecidable. Bracket repetition and integer arithmetic only.
aahp_trust_rows() {
    local trust_file="$1"
    local today="$2"
    [ -f "$trust_file" ] || return 0

    awk -v today="$today" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function isdate(s,    m, d) {
            if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
            m = substr(s, 6, 2) + 0
            d = substr(s, 9, 2) + 0
            return (m >= 1 && m <= 12 && d >= 1 && d <= 31)
        }
        # Day number of a proleptic Gregorian date (Julian Day Number formula,
        # integer arithmetic only). Only differences are used.
        function dayno(s,    y, m, d, a, yy, mm) {
            y = substr(s, 1, 4) + 0
            m = substr(s, 6, 2) + 0
            d = substr(s, 9, 2) + 0
            a = int((14 - m) / 12)
            yy = y + 4800 - a
            mm = m + 12 * a - 3
            return d + int((153 * mm + 2) / 5) + 365 * yy + int(yy / 4) - int(yy / 100) + int(yy / 400) - 32045
        }
        BEGIN { today_n = isdate(today) ? dayno(today) : "" }
        { sub(/\r$/, "") }
        /^[ \t]*\|/ {
            n = split($0, cell, "|")
            for (i = 1; i <= n; i++) { cell[i] = trim(cell[i]); gsub(/\t/, " ", cell[i]) }

            # Separator row like | --- | --- | : skip it.
            sep = 1
            for (i = 2; i < n; i++) {
                if (cell[i] != "" && cell[i] !~ /^:?-+:?$/) { sep = 0; break }
            }
            if (sep) next

            # Header row: names Status and/or Expires. Every header resets all
            # three positions, so each table is read with its own layout.
            is_header = 0
            for (i = 2; i < n; i++) {
                lc = tolower(cell[i])
                if (lc == "status" || lc == "expires") is_header = 1
            }
            if (is_header) {
                status_col = 0; expires_col = 0; check_col = 0
                for (i = 2; i < n; i++) {
                    lc = tolower(cell[i])
                    if (lc == "status")  status_col = i
                    if (lc == "expires") expires_col = i
                    if (lc == "check")   check_col = i
                }
                next
            }

            if (status_col == 0 && expires_col == 0) next

            st = status_col ? tolower(cell[status_col]) : ""
            ex = expires_col ? cell[expires_col] : ""
            ck = check_col ? cell[check_col] : ""
            gsub(/`/, "", ck)
            ck = trim(ck)
            if (ck == "-") ck = ""
            past = ""
            if (today_n != "" && isdate(ex)) past = today_n - dayno(ex)
            print st "|" past "|" ex "|" ck "|" cell[2]
        }
        # A blank line ends a table, so a stray table without a header does not
        # reuse stale column positions.
        /^[ \t]*$/ { status_col = 0; expires_col = 0; check_col = 0 }
    ' "$trust_file"
}
