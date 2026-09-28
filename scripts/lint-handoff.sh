#!/usr/bin/env bash
# lint-handoff.sh -Validate AAHP handoff files for safety violations
#
# Usage: ./scripts/lint-handoff.sh [path-to-project]
#        Defaults to current directory if no path given.
#
# Checks:
#   1. Prompt injection patterns (every handoff file except .aiignore, plus the
#      decoded string values of every JSON file)
#   2. Secrets & API keys (same scope as check 1)
#   3. PII patterns (emails: every *.md file, plus the decoded string values of
#      every *.json file except pii-allowlist.json, which holds the approved
#      addresses by design)
#   4. MANIFEST.json schema (basic) and checksum integrity
#   5. HANDOFF.lock stale check
#   6. Parallel agent detection (advisory)
#   7. Git conflict markers (tracked and unignored files, plus the handoff dir)
#
# Exit codes (this script DECIDES, it does not merely report):
#   0 = all checks passed
#   1 = violations found
#
# Check 4 covers every kind of MANIFEST.json integrity failure, and each one
# counts as a violation, so a hook or a CI job can trust this exit code:
#   - a checksum mismatch (an indexed file changed outside the protocol)
#   - a missing indexed file (the manifest indexes a path that is gone)
#   - a handoff file present on disk with no entry in "files" (a partial index
#     compares everything except the file that was tampered with)
#   - an absent MANIFEST.json, an empty index, or a verifier that started and
#     then failed: integrity is UNPROVEN, and unproven counts as a violation
#
# ONE case is deliberately NOT a violation: no Python interpreter at all. That
# environment cannot run this check, and failing it would turn currently green
# node-only environments red without catching anything 'aahp verify' Layer 1
# does not already catch (Layer 1 hard-fails when no interpreter is present).
# The run then exits 0 but does NOT print "All checks passed"; it says plainly
# that integrity was not verified here.
#
# aahp verify Layer 1 computes its verdicts itself, from MANIFEST.json and the
# bytes on disk, so blocking never depends on this script's exit code or on
# its output text. The two implementations are deliberately different
# (embedded Python here, shell plus sha256sum there) so they cross-check.
#
# CONTENT SCANS READ BYTES AS TEXT, AND A SCAN THAT COULD NOT RUN IS A FINDING.
# Checks 1-3 grep with `-a` under LC_ALL=C. Without them, GNU grep 3.5 and
# later treats a file holding one NUL byte as binary and suppresses every
# matching line (its notice goes to stderr, which used to be discarded), and in
# a UTF-8 locale it suppresses any output line holding an invalid byte.
# Measured on Ubuntu 24.04 with grep 3.11: with one NUL in STATUS.md, a fake
# `sk-` key and an email address both passed this lint with exit 0; with one
# invalid byte on the line, the key passed. The patterns are ASCII, so the C
# locale loses nothing. grep exit status 2 (an unreadable file, a vanished
# file) is reported and counted as a violation instead of being folded into
# "nothing found".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

PROJECT_ROOT="${1:-.}"
PYTHON_CMD="$(aahp_python_cmd)"

# Path-format-agnostic file access (cross-platform fix).
# Windows-native Python/Node cannot open an absolute MSYS path like
# /c/Users/...; open() raises FileNotFoundError, which the 2>/dev/null below
# silently turns into a bogus "Invalid JSON". Resolving by changing into the
# project root once and then using RELATIVE paths sidesteps the issue: every
# tool opens '.ai/handoff/...' relative to the cwd, which works identically on
# Windows git-bash and Linux CI. cd failure is fatal (clear error).
cd "$PROJECT_ROOT" || { echo "Error: cannot cd into project root: $PROJECT_ROOT" >&2; exit 1; }
PROJECT_ROOT="."
HANDOFF_DIR=".ai/handoff"
VIOLATIONS=0
# Set when a check was skipped rather than passed, so the summary can say so
# instead of printing "All checks passed" over an integrity check that never ran.
INTEGRITY_UNVERIFIED=0
# Same idea for the decoded scan of JSON string values in check 1.
JSON_DECODE_UNVERIFIED=0

# Scratch space for scan diagnostics and decoded JSON. Removed on every exit.
SCAN_TMP="$(mktemp -d)"
trap 'rm -rf "$SCAN_TMP"' EXIT
JSON_DECODED_DIR="$SCAN_TMP/json"
# One line per line of the matching decoded dump, naming where in the JSON document
# that line came from ("value at /tasks/T-001/notes"). Kept OUTSIDE JSON_DECODED_DIR,
# because checks 1 and 2 grep that directory recursively and a key name echoed here
# would be scanned twice.
JSON_WHERE_DIR="$SCAN_TMP/json-where"
mkdir -p "$JSON_DECODED_DIR" "$JSON_WHERE_DIR"

# Print grep's diagnostics for a scan that exited 2 and count it. Reading "could
# not scan" as "nothing found" is exactly the false green the text-mode switch
# above exists to remove, one failure mode further out.
# Usage: scan_failed <check-label> <grep-exit-status> <stderr-file>
scan_failed() {
    echo -e "  ${RED}x $1: grep could not scan every file (exit $2). This is NOT a clean result.${NC}"
    if [ -s "$3" ]; then
        sed 's/^/    /' "$3"
    fi
    VIOLATIONS=$((VIOLATIONS + 1))
}

# Map a path in the decoded-JSON scratch directory back to the handoff file it
# came from, so a finding names the real file.
display_path() {
    case "$1" in
        "$JSON_DECODED_DIR"/*)
            # A line number in the decoded dump points nowhere real; drop it.
            local rest="${1#"$JSON_DECODED_DIR"/}"
            printf '%s/%s (decoded JSON string values)' "$HANDOFF_DIR" "${rest%%:*}"
            ;;
        *) printf '%s' "$1" ;;
    esac
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "========================================="
echo "  AAHP Handoff Lint"
echo "========================================="
echo ""

if [ ! -d "$HANDOFF_DIR" ]; then
    echo -e "${RED}Error: $HANDOFF_DIR not found.${NC}"
    exit 1
fi

# --- Check 1: Prompt Injection Patterns ----------------------

echo -e "${GREEN}[1/7]${NC} Checking for prompt injection patterns..."

INJECTION_PATTERNS=(
    "ignore all previous"
    "ignore prior"
    "disregard.*instructions"
    "you are now"
    "new system prompt"
    "override.*safety"
    "act as.*unrestricted"
    "jailbreak"
    "ADMIN_OVERRIDE"
    "sudo mode"
)

# SCOPE: every file in the handoff directory, not only *.md. MANIFEST.json is
# the file an incoming agent reads FIRST, and its quick_context and task text
# were never scanned; neither were pii-allowlist.json or
# LOG-ARCHIVE.index.json. JSON is scanned twice: as raw bytes, and as its
# DECODED string values (keys included), because an agent reads
# "ignore all previous" as "ignore all previous" while a byte grep does not.
#
# .aiignore is excluded, exactly as check 2 excludes it: the shipped template
# LISTS these phrases as patterns (templates/.aiignore), so scanning it would
# turn every adopter that keeps the shipped template red on its own ignore list.
#
# Decoding needs an interpreter (python, else node). With neither, the raw scan
# still runs and the summary says the decoded scan did not; a JSON file that
# cannot be decoded at all is a violation, since its escaped text was not read.
#
# Each decoder also writes, per JSON file, a "where" file into JSON_WHERE_DIR with
# one line per line of the decoded dump: "value at <JSON Pointer>" or "key at
# <JSON Pointer>". Check 3 uses it to name the place in MANIFEST.json a finding
# came from. The dump itself is unchanged, so checks 1 and 2 read what they read
# before. A string with N newlines fills N+1 dump lines, so its label is written
# N+1 times; a newline inside a label is escaped so it cannot shift the lines.
IFS= read -r -d '' JSON_STRINGS_PY <<'PY' || true
import json, os, sys
src, dst, where = sys.argv[1], sys.argv[2], sys.argv[3]
failed = []
def pointer(parts):
    text = ''.join('/' + str(p).replace('~', '~0').replace('/', '~1') for p in parts)
    return (text or '(root)').replace('\r', '\\r').replace('\n', '\\n')
for base, dirs, names in os.walk(src):
    dirs.sort()
    for name in sorted(names):
        if not name.endswith('.json'):
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, src).replace(os.sep, '/')
        try:
            with open(path, encoding='utf-8') as handle:
                doc = json.load(handle)
        except Exception as exc:
            failed.append('%s (%s)' % (rel, exc.__class__.__name__))
            continue
        out, labels, stack = [], [], [(doc, [])]
        while stack:
            value, parts = stack.pop()
            if isinstance(value, str):
                out.append(value)
                labels.extend(['value at ' + pointer(parts)] * (value.count('\n') + 1))
            elif isinstance(value, dict):
                for key, item in value.items():
                    out.append(key)
                    labels.extend(['key at ' + pointer(parts + [key])] * (key.count('\n') + 1))
                    stack.append((item, parts + [key]))
            elif isinstance(value, list):
                stack.extend((item, parts + [i]) for i, item in enumerate(value))
        target = rel.replace('/', '__')
        with open(os.path.join(dst, target), 'w', encoding='utf-8', newline='\n') as handle:
            handle.write('\n'.join(out) + '\n')
        with open(os.path.join(where, target), 'w', encoding='utf-8', newline='\n') as handle:
            handle.write('\n'.join(labels) + '\n')
for item in failed:
    print(item)
sys.exit(3 if failed else 0)
PY
IFS= read -r -d '' JSON_STRINGS_JS <<'JS' || true
'use strict';
const fs = require('fs');
const path = require('path');
const [src, dst, where] = process.argv.slice(1);
const failed = [];
const pointer = (parts) =>
  (parts.map((p) => '/' + String(p).replace(/~/g, '~0').replace(/\//g, '~1')).join('') || '(root)')
    .replace(/\r/g, '\\r').replace(/\n/g, '\\n');
const lineCount = (s) => s.split('\n').length;
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) { walk(full); continue; }
    if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
    const rel = path.relative(src, full).split(path.sep).join('/');
    let doc;
    try { doc = JSON.parse(fs.readFileSync(full, 'utf8')); } catch (err) { failed.push(rel + ' (' + err.name + ')'); continue; }
    const out = [];
    const labels = [];
    const stack = [[doc, []]];
    while (stack.length) {
      const [value, parts] = stack.pop();
      if (typeof value === 'string') {
        out.push(value);
        for (let i = 0; i < lineCount(value); i++) labels.push('value at ' + pointer(parts));
      } else if (Array.isArray(value)) stack.push(...value.map((item, i) => [item, parts.concat(i)]));
      else if (value && typeof value === 'object') {
        for (const [key, item] of Object.entries(value)) {
          out.push(key);
          for (let i = 0; i < lineCount(key); i++) labels.push('key at ' + pointer(parts.concat(key)));
          stack.push([item, parts.concat(key)]);
        }
      }
    }
    const target = rel.split('/').join('__');
    fs.writeFileSync(path.join(dst, target), out.join('\n') + '\n');
    fs.writeFileSync(path.join(where, target), labels.join('\n') + '\n');
  }
}
walk(src);
for (const item of failed) console.log(item);
process.exitCode = failed.length ? 3 : 0;
JS

HAS_JSON=0
for json_file in "$HANDOFF_DIR"/*.json; do
    if [ -f "$json_file" ]; then HAS_JSON=1; break; fi
done
if [ "$HAS_JSON" -eq 1 ]; then
    DECODE_RC=0
    DECODE_OUT=""
    if [ -n "$PYTHON_CMD" ]; then
        DECODE_OUT=$("$PYTHON_CMD" -c "$JSON_STRINGS_PY" "$HANDOFF_DIR" "$JSON_DECODED_DIR" "$JSON_WHERE_DIR") || DECODE_RC=$?
    elif command -v node >/dev/null 2>&1; then
        DECODE_OUT=$(node -e "$JSON_STRINGS_JS" "$HANDOFF_DIR" "$JSON_DECODED_DIR" "$JSON_WHERE_DIR") || DECODE_RC=$?
    else
        JSON_DECODE_UNVERIFIED=1
        echo -e "  ${YELLOW}! No python or node: JSON string values were scanned as raw bytes only.${NC}"
        echo "    Escaped text such as \\u0069gnore in a .json file was NOT decoded and NOT scanned."
    fi
    if [ "$DECODE_RC" -eq 3 ]; then
        echo -e "  ${RED}x Could not decode as JSON, so escaped text in it was not scanned:${NC}"
        printf '%s\n' "$DECODE_OUT" | tr -d '\r' | sed 's/^/    /'
        VIOLATIONS=$((VIOLATIONS + 1))
    elif [ "$DECODE_RC" -ne 0 ]; then
        echo -e "  ${RED}x Decoding the JSON string values failed (exit $DECODE_RC); they were not scanned.${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
fi

INJECTION_START=$VIOLATIONS
for pattern in "${INJECTION_PATTERNS[@]}"; do
    SCAN_RC=0
    MATCHES=$(LC_ALL=C grep -rila --exclude='.aiignore' -- "$pattern" "$HANDOFF_DIR" "$JSON_DECODED_DIR" 2>"$SCAN_TMP/grep.err") || SCAN_RC=$?
    if [ "$SCAN_RC" -gt 1 ]; then
        scan_failed "Injection scan for '$pattern'" "$SCAN_RC" "$SCAN_TMP/grep.err"
    fi
    if [ -n "$MATCHES" ]; then
        echo -e "  ${RED}x Injection pattern '$pattern' found in:${NC}"
        while IFS= read -r hit; do
            echo "    $(display_path "$hit")"
        done <<< "$MATCHES"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

if [ "$VIOLATIONS" -eq "$INJECTION_START" ]; then
    echo -e "  ${GREEN}OK No injection patterns found.${NC}"
fi

# --- Check 2: Secrets & API Keys -----------------------------

echo -e "${GREEN}[2/7]${NC} Checking for secrets and API keys..."

# Prefix patterns carry a length floor (\{16,\}) so they only match a
# realistic key-length run, not a "sk-"/"AKIA" prefix glued to one or two
# ordinary characters (e.g. the "sk-to" inside "task-to-model"). Real keys
# are far longer than 16 chars. Note: grep below runs in BRE mode, so the
# interval must be escaped as \{16,\}.
#
# THE QUANTIFIER MUST BE ESCAPED. grep below runs in BRE, where a bare `?` is a
# LITERAL question mark, not "optional". Every "=assignment" entry here used to
# read `['\"]?`, which demanded a quote followed by an actual `?` character, so
# `API_KEY=abc123`, `DB_PASSWORD=hunter2`, `GH_TOKEN=...` and `X_SECRET=...` in a
# handoff file matched NOTHING. Measured: four of the thirteen shipped patterns
# scored 0 on a fixture containing all four, and scored 1-2 each once the
# quantifier was escaped. The same trap is already documented one comment up for
# the `\{16,\}` interval; it was applied to the intervals and missed here.
#
# `_CREDENTIALS=` is in the list because templates/.aiignore ships it. The
# shipped template and this enforced list must not disagree: a pattern listed in
# the template but absent here is a rule an adopter believes is on and is not.
#
# THE "=assignment" PATTERNS CARRY THE SAME LENGTH FLOOR AS THE PREFIX ONES, and
# for the same reason the comment at the top of this block gives. Escaping the
# quantifier without also applying the floor produced a half-fixed pattern: the
# first version of this fix read `_KEY=['\"]\?[a-zA-Z0-9]`, which matches a
# `*_KEY=` assignment of ANY value, one character upwards. That is not a secret
# detector, it is a detector for the SHAPE of a configuration line, and handoff
# files are full of prose that describes configuration.
#
# The failure mode before the floor was added: a single committed handoff note
# DESCRIBING a security finding, which quoted the placeholder
# `API_KEY=your-api-key-here` from an .env.example it was arguing against,
# turned `All checks passed` exit 0 into `1 violation(s) found` exit 1. Where
# `aahp verify --level ci` is a required, branch-protected check, an AAHP
# upgrade alone would turn a green protected branch red with nothing in that
# repository changed. On a twelve-line prose corpus the unfloored spelling
# scored EIGHT false positives; with the floor it scores zero and still matches
# all eight entries of a real-secret corpus. A control that fails ordinary use
# gets switched off, and it takes the nine prefix patterns down with it.
#
# The floor is expressed as "somewhere in the value token there is an unbroken
# run of 16+ alphanumerics", not "the value STARTS with such a run". The absorb class carries `+`, `/`
#   and `=` as well as word characters, because without them a base64 secret is
#   broken by its own padding and the floor silently misses it - measured on the
#   canonical AWS example key, which this pattern missed until that was fixed: modern
# tokens are segmented (`sk-proj-...`, `github_pat_11...`, `rk_live_51...`) and
# anchoring at `=` misses all three. Placeholder prose is word-shaped - hyphen
# or underscore separated dictionary words, each far short of 16 - so the two
# populations separate cleanly on exactly this property. `[-_.a-zA-Z0-9]*`
# keeps `-` first in the bracket so BRE reads it as a literal.
#
# What this deliberately does NOT catch: a short real password such as
# `DB_PASSWORD=hunter2`. Nothing distinguishes that from prose by inspection,
# and guessing costs more than it buys here - a repository that wants it should
# run a purpose-built entropy scanner. The nine prefixed patterns above are
# unchanged and still block every well-known credential format.
SECRET_PATTERNS=(
    "sk-[a-zA-Z0-9]\{16,\}"
    "ghp_[a-zA-Z0-9]\{16,\}"
    "gho_[a-zA-Z0-9]\{16,\}"
    "glpat-"
    "xoxb-"
    "xoxp-"
    "AKIA[A-Z0-9]\{16,\}"
    "Bearer [a-zA-Z0-9]"
    "-----BEGIN.*PRIVATE KEY"
    "_KEY=['\"]\?[-_.+/=a-zA-Z0-9]*[a-zA-Z0-9]\{16,\}"
    "_SECRET=['\"]\?[-_.+/=a-zA-Z0-9]*[a-zA-Z0-9]\{16,\}"
    "_TOKEN=['\"]\?[-_.+/=a-zA-Z0-9]*[a-zA-Z0-9]\{16,\}"
    "_PASSWORD=['\"]\?[-_.+/=a-zA-Z0-9]*[a-zA-Z0-9]\{16,\}"
    "_CREDENTIALS=['\"]\?[-_.+/=a-zA-Z0-9]*[a-zA-Z0-9]\{16,\}"
)

SECRET_FOUND=0
SECRET_SCAN_FAILED=0
for pattern in "${SECRET_PATTERNS[@]}"; do
    # `path:line`, never the matched text. A reader who goes red needs to reach
    # the line to judge it - a bare filename against a 4,000-line STATUS.md is
    # what makes a finding look arbitrary and gets the gate switched off. The
    # matched text is deliberately NOT printed: if it really is a secret, echoing
    # it into a CI log republishes it somewhere with a different retention
    # policy. `cut` is safe here because HANDOFF_DIR is relative (the script
    # cd'd into the project root above), so no Windows drive-letter colon.
    #
    # The ignore file is excluded by grep itself, NOT by filtering grep's
    # output. An earlier revision piped `-n` output through `grep -v '.aiignore'`,
    # which had been correct when the source was `-nl` and emitted bare paths. With
    # line output it filters the MATCHED TEXT instead, so a real secret sitting on
    # a line that merely mentions .aiignore was dropped and the gate printed
    # "No secrets detected". Excluding at the source means no content can
    # subvert the exclusion, because nothing downstream reads the match.
    #
    # `-a` under LC_ALL=C reads every file as text (see the header); the exit
    # status of grep itself is taken from PIPESTATUS inside the substitution, so
    # a scan that could not run is not mistaken for one that found nothing. The
    # decoded JSON string values from check 1 are scanned too, which is what
    # finds a key hidden behind a JSON escape.
    SCAN_RC=0
    MATCHES=$(LC_ALL=C grep -rna --exclude='.aiignore' -- "$pattern" "$HANDOFF_DIR" "$JSON_DECODED_DIR" 2>"$SCAN_TMP/grep.err" | cut -d: -f1,2; exit "${PIPESTATUS[0]}") || SCAN_RC=$?
    if [ "$SCAN_RC" -gt 1 ]; then
        scan_failed "Secret scan for '$pattern'" "$SCAN_RC" "$SCAN_TMP/grep.err"
        SECRET_SCAN_FAILED=1
    fi
    if [ -n "$MATCHES" ]; then
        echo -e "  ${RED}x Possible secret pattern '$pattern' found in:${NC}"
        while IFS= read -r hit; do
            echo "    $(display_path "$hit")"
        done <<< "$MATCHES"
        SECRET_FOUND=$((SECRET_FOUND + 1))
    fi
done

if [ "$SECRET_FOUND" -eq 0 ] && [ "$SECRET_SCAN_FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}OK No secrets detected.${NC}"
else
    VIOLATIONS=$((VIOLATIONS + SECRET_FOUND))
fi

# --- .aiignore: say out loud that it is NOT a rule source --------------------
#
# `.ai/handoff/.aiignore` reads like a firewall an adopter can extend, and the
# shipped template used to close with an invitation to add internal hostnames
# and IP ranges. Nothing has ever parsed it. The list above is the entire
# enforced set, and the `--exclude='.aiignore'` above only keeps the file from
# matching its OWN patterns - it is not a rule reader.
#
# An adopter who adds `10.0.0.*` and `*.internal.example.com` here, commits an
# internal hostname into STATUS.md and watches this script exit 0 concludes the
# control ran and cleared them. It did not: it never looked. So when the file is
# present and carries patterns, this prints what was NOT assessed, by name and
# by count. Silence here is what made the promise credible.
#
# This is deliberately advisory: it does not change the exit code, because
# turning every adopter's committed `.aiignore` into live rules overnight would
# fail builds on patterns nobody chose (`sk-*` with no length floor matches the
# word "task-type" in AAHP's own shipped templates). Whether to enforce the file
# is tracked as an owner decision; see README Section 2.6.
AIIGNORE_FILE="$HANDOFF_DIR/.aiignore"
if [ -f "$AIIGNORE_FILE" ]; then
    AIIGNORE_RULES=$(LC_ALL=C grep -a -c -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$AIIGNORE_FILE" || true)
    echo -e "  ${YELLOW}NOT ENFORCED: $AIIGNORE_FILE lists ${AIIGNORE_RULES} pattern(s); no gate reads them.${NC}"
    echo "    The enforced set is the ${#SECRET_PATTERNS[@]} built-in secret patterns above, plus the"
    echo "    injection patterns in check 1 and the PII patterns in check 3. A pattern you add"
    echo "    to .aiignore is NOT checked by this script, by 'aahp verify', or by any CI gate."
fi

# --- Check 3: PII Patterns and Reviewed Allowlist ----------------

echo -e "${GREEN}[3/7]${NC} Checking for PII..."

ALLOWLIST_FILE="$HANDOFF_DIR/pii-allowlist.json"
ALLOWLIST_ENTRIES=""
if [ -f "$ALLOWLIST_FILE" ]; then
    if [ -z "$PYTHON_CMD" ]; then
        echo -e "  ${RED}x PII allowlist exists but Python is unavailable for validation.${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    else
        ALLOWLIST_ERR="$(mktemp)"
        if ALLOWLIST_ENTRIES=$("$PYTHON_CMD" "$SCRIPT_DIR/validate-pii-allowlist.py" "$ALLOWLIST_FILE" --format tsv 2>"$ALLOWLIST_ERR"); then
            echo -e "  ${GREEN}OK Valid PII allowlist.${NC}"
        else
            ALLOWLIST_MESSAGE="$ALLOWLIST_ENTRIES"
            if [ -s "$ALLOWLIST_ERR" ]; then
                ALLOWLIST_MESSAGE="${ALLOWLIST_MESSAGE}${ALLOWLIST_MESSAGE:+$'\n'}$(cat "$ALLOWLIST_ERR")"
            fi
            echo -e "  ${RED}x $ALLOWLIST_MESSAGE${NC}"
            ALLOWLIST_ENTRIES=""
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
        rm -f "$ALLOWLIST_ERR"
    fi
else
    echo -e "  ${GREEN}OK No PII allowlist configured.${NC}"
fi

if [ -f "$ALLOWLIST_FILE" ] && [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    if [ -z "$PYTHON_CMD" ] || ! EXPECTED_CHECKSUM=$("$PYTHON_CMD" - "$HANDOFF_DIR/MANIFEST.json" <<'PY'
import json, sys
entry = json.load(open(sys.argv[1], encoding="utf-8")).get("files", {}).get("pii-allowlist.json")
if not isinstance(entry, dict) or not isinstance(entry.get("checksum"), str):
    raise SystemExit(1)
print(entry["checksum"])
PY
); then
        echo -e "  ${RED}x pii-allowlist.json is not indexed by MANIFEST.json. Run /handoff.${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    elif [ "$EXPECTED_CHECKSUM" != "$(aahp_checksum "$ALLOWLIST_FILE")" ]; then
        echo -e "  ${RED}x pii-allowlist.json checksum does not match MANIFEST.json. Run /handoff.${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
fi

# The scan pins LC_ALL=C and reads bytes as text (-a). It used to pin
# LC_ALL=C.UTF-8 without -a, which kept grep -E working under an empty locale
# (T-027) but let one NUL byte anywhere in a file hide every address in it:
# measured with GNU grep 3.11, the old invocation printed nothing and exited 0
# for a file holding a NUL and an address. (An invalid UTF-8 byte did not hide
# an address here, because -o prints only the ASCII match; it did hide the
# secret-scan line in check 2.) The pattern is ASCII, so C matches exactly the
# same addresses. An absent file set is not a scan failure; grep exit 2 is.
#
# SCOPE: every *.md file, plus every *.json file except pii-allowlist.json. The
# scan used to read *.md only, so an address in MANIFEST.json (a task's notes,
# `assigned_to`, `quick_context`, the per-file summaries) or in
# LOG-ARCHIVE.index.json passed, although MANIFEST.json is the file an incoming
# agent reads FIRST. JSON is read through the decoded dump check 1 already wrote,
# so an address behind a \u0040 escape is seen the way an agent reads it, and a
# finding names the JSON Pointer of its value. Where no dump exists (no python
# or node, or a file that is not valid JSON, already a violation above) the raw
# file is scanned instead, so the address is still found, by line.
# pii-allowlist.json is excluded because it holds the approved addresses by
# design: scanning it would report every approved address as unapproved PII.
PII_FILES=()
for md_file in "$HANDOFF_DIR"/*.md; do
    [ -f "$md_file" ] && PII_FILES+=("$md_file")
done
for json_file in "$HANDOFF_DIR"/*.json; do
    [ -f "$json_file" ] || continue
    json_name="${json_file##*/}"
    [ "$json_name" = "pii-allowlist.json" ] && continue
    if [ -f "$JSON_DECODED_DIR/$json_name" ]; then
        PII_FILES+=("$JSON_DECODED_DIR/$json_name")
    else
        PII_FILES+=("$json_file")
    fi
done

# Where a PII match was found, for a human: "file:line" for a file read as
# bytes, "file (value at /json/pointer)" for a decoded JSON value, whose dump line
# number points nowhere real.
pii_location() {
    local file="${1%%:*}" rest="${1#*:}" line name label
    line="${rest%%:*}"
    case "$file" in
        "$JSON_DECODED_DIR"/*)
            name="${file#"$JSON_DECODED_DIR"/}"
            label="$(sed -n "${line}p" "$JSON_WHERE_DIR/$name" 2>/dev/null || true)"
            printf '%s/%s (%s)' "$HANDOFF_DIR" "$name" "${label:-decoded JSON string value}"
            ;;
        *) printf '%s:%s' "$file" "$line" ;;
    esac
}

EMAIL_MATCHES=""
PII_SCAN_FAILED=0
if [ "${#PII_FILES[@]}" -gt 0 ]; then
    SCAN_RC=0
    EMAIL_MATCHES=$(LC_ALL=C grep -HnoEa '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "${PII_FILES[@]}" 2>"$SCAN_TMP/grep.err" | awk -F: '{ addr=$NF; if (addr ~ /\.noreply\./ || addr ~ /^no-?reply@/ || index(addr,"example.com") || index(addr,"placeholder")) next; print }'; exit "${PIPESTATUS[0]}") || SCAN_RC=$?
    if [ "$SCAN_RC" -gt 1 ]; then
        scan_failed "PII scan" "$SCAN_RC" "$SCAN_TMP/grep.err"
        PII_SCAN_FAILED=1
    fi
fi
UNAPPROVED=""
if [ -n "$EMAIL_MATCHES" ]; then
    while IFS= read -r match; do
        address="${match##*:}"
        allowed=0
        while IFS=$'\t' read -r value owner expires _; do
            [ -z "$value" ] && continue
            if [ "$address" = "$value" ]; then
                echo -e "  ${GREEN}OK Allowed PII email '$address' via pii-allowlist.json (owner: $owner, expires: $expires).${NC}"
                allowed=1
                break
            fi
        done <<< "$ALLOWLIST_ENTRIES"
        [ "$allowed" -eq 1 ] || UNAPPROVED="${UNAPPROVED}${UNAPPROVED:+$'\n'}$(pii_location "$match"): $address"
    done <<< "$EMAIL_MATCHES"
fi
if [ -n "$UNAPPROVED" ]; then
    echo -e "  ${YELLOW}Possible email addresses found:${NC}"
    printf '%s\n' "$UNAPPROVED" | sed 's/^/    /'
    VIOLATIONS=$((VIOLATIONS + 1))
elif [ "$PII_SCAN_FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}OK No unapproved PII detected.${NC}"
fi

# --- Check 4: MANIFEST.json Basic Validation -----------------

echo -e "${GREEN}[4/7]${NC} Validating MANIFEST.json..."

# Python command was detected before the PII allowlist check.

if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    if [ -z "$PYTHON_CMD" ]; then
        echo -e "  ${YELLOW}! Python not found. MANIFEST.json integrity NOT verified here.${NC}"
        echo "    The blocking check is 'aahp verify' Layer 1, which uses node or"
        echo "    python and FAILS outright when neither is available."
        # Deliberately a warning, not a violation: making it one would turn
        # currently green node-only environments red without catching anything
        # Layer 1 does not already catch. The summary below must therefore not
        # claim that all checks passed, because this one did not run.
        INTEGRITY_UNVERIFIED=1
    else
        # ONE interpreter pass for the whole check: JSON validity, required
        # fields, and the integrity comparison. It used to start Python seven
        # times to parse the same file (validity, one run per required field,
        # then integrity), which is most of this check's wall time on Windows.
        #
        # The file is opened as UTF-8 explicitly. A bare open() decodes with
        # the locale's code page, so on a Windows cp1252 console a valid UTF-8
        # MANIFEST.json holding one non-ASCII character was reported as
        # "Invalid JSON".
        #
        # Verify the existence AND the checksum of every indexed file.
        #
        # Existence is asserted FIRST and reported separately. A deleted file
        # has no content to compare, so the checksum comparison alone can never
        # see it; and the two failures need different fixes (restore the file
        # vs. regenerate the manifest), so they must not share a message.
        #
        # An empty index is a finding too: zero iterations means nothing was
        # compared, which is not the same as everything matching. A PARTIAL
        # index is the same defect at N-1 iterations, so a canonical handoff
        # file that is present on disk but absent from "files" is a finding as
        # well: dropping its entry and rewriting the file would otherwise pass
        # both gates untouched.
        #
        # Exit contract of the embedded script:
        #   0      = valid JSON, every required field present, integrity clean
        #   4      = not valid JSON (or not a JSON object)
        #   64+N   = valid JSON with N violations (one per missing required
        #            field, plus one when the integrity comparison found anything)
        #   other  = the interpreter itself failed, and that ALSO counts as a
        #            violation. If the tool cannot tell whether the files match,
        #            integrity is unproven, and unproven must not print "All
        #            checks passed". stderr is deliberately not discarded so the
        #            real cause of an interpreter failure is visible in the log.
        IFS= read -r -d '' CHECK4_PY <<'PY' || true
import hashlib, json, os, sys
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass
handoff, required, canonical = sys.argv[1], sys.argv[2].split(), sys.argv[3].split()
try:
    with open(os.path.join(handoff, 'MANIFEST.json'), encoding='utf-8') as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as exc:
    print('    %s' % exc)
    sys.exit(4)
if not isinstance(manifest, dict):
    print('    the top level is not a JSON object')
    sys.exit(4)
violations = 0
for field in required:
    if field not in manifest:
        print('  x Missing required field: %s' % field)
        violations += 1
print('  Verifying indexed files...')
findings = 0
indexed = manifest.get('files') or {}
if not isinstance(indexed, dict):
    indexed = {}
if not indexed:
    print('  ! MANIFEST.json indexes no files.')
    print('    Nothing could be verified, so nothing is verified.')
    print('    Fix: regenerate the manifest (aahp manifest).')
    findings += 1
for fname, meta in indexed.items():
    fpath = os.path.join(handoff, fname)
    if not os.path.exists(fpath):
        print('  ! Missing indexed file: %s' % fname)
        print('    Indexed by MANIFEST.json but not present in the working tree.')
        print('    Fix: restore the file, or regenerate the manifest (aahp manifest).')
        findings += 1
        continue
    with open(fpath, 'rb') as handle:
        actual = 'sha256:' + hashlib.sha256(handle.read().replace(b'\r', b'')).hexdigest()
    expected = meta.get('checksum', '') if isinstance(meta, dict) else ''
    if actual != expected:
        print('  ! Checksum mismatch: %s' % fname)
        print('    Expected: %s' % expected)
        print('    Actual:   %s' % actual)
        findings += 1
    else:
        print('  OK: %s' % fname)
if indexed:
    for fname in canonical:
        if fname in indexed or not os.path.exists(os.path.join(handoff, fname)):
            continue
        print('  ! Not indexed by MANIFEST.json: %s' % fname)
        print('    The file is present but has no entry, so it was never compared.')
        print('    Fix: regenerate the manifest (aahp manifest).')
        findings += 1
if findings:
    violations += 1
sys.exit(64 + min(violations, 63) if violations else 0)
PY
        REQUIRED_FIELDS=("aahp_version" "project" "last_session" "files" "quick_context")
        CHECK4_RC=0
        CHECK4_OUT=$("$PYTHON_CMD" -c "$CHECK4_PY" "$HANDOFF_DIR" "${REQUIRED_FIELDS[*]}" "${AAHP_HANDOFF_FILES[*]}") || CHECK4_RC=$?
        if [ "$CHECK4_RC" -eq 4 ]; then
            echo -e "  ${RED}x Invalid JSON.${NC}"
            printf '%s\n' "$CHECK4_OUT" | tr -d '\r'
            VIOLATIONS=$((VIOLATIONS + 1))
        elif [ "$CHECK4_RC" -eq 0 ] || { [ "$CHECK4_RC" -ge 65 ] && [ "$CHECK4_RC" -le 127 ]; }; then
            echo -e "  ${GREEN}OK Valid JSON.${NC}"
            printf '%s\n' "$CHECK4_OUT" | tr -d '\r'
            if [ "$CHECK4_RC" -ne 0 ]; then
                VIOLATIONS=$((VIOLATIONS + CHECK4_RC - 64))
            fi
        else
            if [ -n "$CHECK4_OUT" ]; then
                printf '%s\n' "$CHECK4_OUT" | tr -d '\r'
            fi
            echo -e "  ${RED}x Could not verify indexed files (verifier exited $CHECK4_RC).${NC}"
            echo "    Integrity is UNPROVEN. That counts as a violation, not a note."
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
else
    # A deleted manifest is the maximal "integrity unproven" state: there is
    # no index at all, so not one handoff file was compared. It used to print
    # a yellow note and let the run end with "All checks passed", which made
    # the blocking aahp-lint job green on a repository whose manifest was
    # gone. aahp verify Layer 1 has always failed here; both gates now agree.
    echo -e "  ${RED}x MANIFEST.json not found. Nothing about the handoff set is verified.${NC}"
    echo "    Fix: generate it with /handoff (aahp manifest)."
    VIOLATIONS=$((VIOLATIONS + 1))
fi

# --- Check 5: Stale HANDOFF.lock -----------------------------

echo -e "${GREEN}[5/7]${NC} Checking for stale HANDOFF.lock..."

if [ -f "$HANDOFF_DIR/HANDOFF.lock" ]; then
    echo -e "  ${RED}x HANDOFF.lock exists! Previous session may not have completed cleanly.${NC}"
    echo "    Review the lock file and delete it if the session is no longer active."
    cat "$HANDOFF_DIR/HANDOFF.lock" 2>/dev/null
    VIOLATIONS=$((VIOLATIONS + 1))
else
    echo -e "  ${GREEN}OK No stale lock.${NC}"
fi

# --- Check 6: Parallel Agent Detection ------------------------

echo -e "${GREEN}[6/7]${NC} Checking for parallel agent sessions..."

if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
    LOCK_BRANCHES=()
    while IFS= read -r branch; do
        if git -C "$PROJECT_ROOT" show "$branch:.ai/handoff/HANDOFF.lock" &>/dev/null 2>&1; then
            LOCK_BRANCHES+=("$branch")
        fi
    done < <(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' refs/heads/)

    if [ ${#LOCK_BRANCHES[@]} -gt 1 ]; then
        echo -e "  ${YELLOW}! HANDOFF.lock found on multiple branches:${NC}"
        for b in "${LOCK_BRANCHES[@]}"; do
            echo "    - $b"
        done
        echo "  AAHP is designed for sequential handoff. Ensure agents are working in isolated branches."
    elif [ ${#LOCK_BRANCHES[@]} -eq 1 ]; then
        echo -e "  ${YELLOW}! Active session on branch: ${LOCK_BRANCHES[0]}${NC}"
    else
        echo -e "  ${GREEN}OK No active sessions detected across branches.${NC}"
    fi
else
    echo -e "  ${YELLOW}! Not a git repo. Skipping parallel agent check.${NC}"
fi

# --- Check 7: Git conflict markers ---------------------------
# Refuse clean status when markers remain (nested-marker damage).

echo -e "${GREEN}[7/7]${NC} Checking for git conflict markers..."

MARKER_RC=0
MARKER_SCRIPT="$SCRIPT_DIR/check-conflict-markers.mjs"
MARKER_NODE=""
if command -v node &>/dev/null; then
    MARKER_NODE="node"
elif command -v node.exe &>/dev/null; then
    MARKER_NODE="node.exe"
fi
# The node gate is used only when it is actually next to this script.
# scripts/propagate.sh copies this file into consumer repositories WITHOUT
# check-conflict-markers.mjs; node then died with "Cannot find module", exit 1,
# and exit 1 is this check's "markers found" code, so every such consumer got a
# conflict-marker violation with no file named. A missing gate script is not a
# reason to skip the check either: the shell fallback below runs instead.
if [ -n "$MARKER_NODE" ] && [ -f "$MARKER_SCRIPT" ]; then
    "$MARKER_NODE" "$MARKER_SCRIPT" "$PROJECT_ROOT" 2>"$SCAN_TMP/markers.err" || MARKER_RC=$?
    if [ -s "$SCAN_TMP/markers.err" ]; then
        cat "$SCAN_TMP/markers.err" >&2
    fi
    # Exit 1 means "markers found" ONLY together with the gate's own FAIL line.
    # Node exits 1 for its own failures too (a crash, a module it cannot load),
    # and those are "could not run", never a verdict about the tree.
    if [ "$MARKER_RC" -eq 1 ] && ! grep -q 'check-conflict-markers: FAIL' "$SCAN_TMP/markers.err"; then
        MARKER_RC=2
    fi
else
    # Pure-bash fallback: strip CR and match markers without node.
    #
    # Same two changes as the node path AND the same predicate shape. An earlier
    # version of this comment claimed the two could not disagree while they did, on
    # three of six cases: node trims the line before testing and this anchored `^`,
    # so an INDENTED marker was caught there and missed here; and node uses
    # startsWith, so eight angle brackets matched there and not here. Measured, then
    # aligned to node's predicate, because an indented marker is still a marker. The
    # `=======` alternative is gone: seven equals signs is a Markdown setext
    # underline and a Python docstring header, and it turned real adopter roots
    # red on files with no conflict in them.
    #
    # The file set matches the node gate: inside a git work tree, the tracked
    # files plus the untracked files git does not ignore, plus everything in the
    # handoff directory (scanned even if an adopter ignores it); outside one, a
    # walk of the tree with .git and node_modules pruned.
    if [ -z "$MARKER_NODE" ]; then
        echo "  (node not found; using the shell fallback)"
    else
        echo "  (check-conflict-markers.mjs is not next to this script; using the shell fallback)"
    fi
    MARKER_FOUND=0
    MARKER_LIST="$SCAN_TMP/marker-files"
    MARKER_LIST_RC=0
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        {
            git -C "$PROJECT_ROOT" ls-files -z -co --exclude-standard &&
                git -C "$PROJECT_ROOT" ls-files -z -oi --exclude-standard -- "$HANDOFF_DIR"
        } > "$MARKER_LIST" || MARKER_LIST_RC=$?
    else
        find "$PROJECT_ROOT" \( -name .git -o -name node_modules \) -prune \
            -o -type f -print0 > "$MARKER_LIST" || MARKER_LIST_RC=$?
    fi
    if [ "$MARKER_LIST_RC" -ne 0 ]; then
        MARKER_RC=2
    else
        while IFS= read -r -d '' f; do
            if [ ! -f "$f" ] || [ -L "$f" ]; then continue; fi
            if tr -d '\r' < "$f" | LC_ALL=C grep -a -E '^[[:space:]]*(<<<<<<<|>>>>>>>)' -q; then
                echo -e "  ${RED}x Conflict markers present in: $f${NC}"
                MARKER_FOUND=1
            fi
        done < "$MARKER_LIST"
        if [ "$MARKER_FOUND" -eq 1 ]; then
            MARKER_RC=1
        fi
    fi
fi
if [ "$MARKER_RC" -eq 1 ]; then
    VIOLATIONS=$((VIOLATIONS + 1))
elif [ "$MARKER_RC" -ne 0 ]; then
    echo -e "  ${RED}x conflict-marker check could not run (exit $MARKER_RC).${NC}"
    VIOLATIONS=$((VIOLATIONS + 1))
fi

# --- Summary --------------------------------------------------

echo ""
echo "========================================="
if [ "$VIOLATIONS" -eq 0 ] && { [ "$INTEGRITY_UNVERIFIED" -eq 1 ] || [ "$JSON_DECODE_UNVERIFIED" -eq 1 ]; }; then
    if [ "$INTEGRITY_UNVERIFIED" -eq 1 ]; then
        echo -e "  ${YELLOW}No violations found, but MANIFEST integrity was NOT verified here.${NC}"
        echo "  Run 'aahp verify', which blocks when integrity cannot be established."
    fi
    if [ "$JSON_DECODE_UNVERIFIED" -eq 1 ]; then
        echo -e "  ${YELLOW}No violations found, but JSON string values were NOT decoded and scanned here.${NC}"
    fi
    echo "========================================="
    exit 0
elif [ "$VIOLATIONS" -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed.${NC}"
    echo "========================================="
    exit 0
else
    echo -e "  ${RED}$VIOLATIONS violation(s) found.${NC}"
    echo "========================================="
    exit 1
fi
