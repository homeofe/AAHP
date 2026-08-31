#!/usr/bin/env bash
# lint-handoff.sh -Validate AAHP handoff files for safety violations
#
# Usage: ./scripts/lint-handoff.sh [path-to-project]
#        Defaults to current directory if no path given.
#
# Checks:
#   1. Prompt injection patterns
#   2. Secrets & API keys
#   3. PII patterns (emails)
#   4. MANIFEST.json schema (basic)
#   5. HANDOFF.lock stale check
#   6. Parallel agent detection (advisory)
#   7. Git conflict markers in handoff files 
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

# ─── Check 1: Prompt Injection Patterns ──────────────────────

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

for pattern in "${INJECTION_PATTERNS[@]}"; do
    MATCHES=$(grep -rnil "$pattern" "$HANDOFF_DIR"/*.md 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        echo -e "  ${RED}✗ Injection pattern '$pattern' found in:${NC}"
        echo "    $MATCHES"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

if [ "$VIOLATIONS" -eq 0 ]; then
    echo -e "  ${GREEN}✓ No injection patterns found.${NC}"
fi

# ─── Check 2: Secrets & API Keys ─────────────────────────────

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
# Measured, before the floor was added, against the ten handoff directories in
# this project's own consumer estate: one consumer went from `All checks passed`
# exit 0 to `1 violation(s) found` exit 1 on a single committed line, and that
# line was a note DESCRIBING a security finding - it quoted the placeholder
# `API_KEY=your-api-key-here` from an .env.example the note was arguing against.
# Its `aahp verify --level ci` gate is REQUIRED and branch-protected, so the
# upgrade alone would have turned a green protected branch red with nothing in
# that repository changed. On a twelve-line prose corpus the unfloored spelling
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
    MATCHES=$(grep -rn --exclude='.aiignore' -- "$pattern" "$HANDOFF_DIR" 2>/dev/null | cut -d: -f1,2 || true)
    if [ -n "$MATCHES" ]; then
        echo -e "  ${RED}✗ Possible secret pattern '$pattern' found in:${NC}"
        echo "    $MATCHES"
        SECRET_FOUND=$((SECRET_FOUND + 1))
    fi
done

if [ "$SECRET_FOUND" -eq 0 ]; then
    echo -e "  ${GREEN}✓ No secrets detected.${NC}"
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
    AIIGNORE_RULES=$(grep -c -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$AIIGNORE_FILE" || true)
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

EMAIL_MATCHES=$(LC_ALL=C.UTF-8 grep -rHnoE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$HANDOFF_DIR"/*.md 2>/dev/null | awk -F: '{ addr=$NF; if (addr ~ /\.noreply\./ || addr ~ /^no-?reply@/ || index(addr,"example.com") || index(addr,"placeholder")) next; print }' || true)
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
        [ "$allowed" -eq 1 ] || UNAPPROVED="${UNAPPROVED}${UNAPPROVED:+$'\n'}$match"
    done <<< "$EMAIL_MATCHES"
fi
if [ -n "$UNAPPROVED" ]; then
    echo -e "  ${YELLOW}Possible email addresses found:${NC}"
    echo "    $UNAPPROVED"
    VIOLATIONS=$((VIOLATIONS + 1))
else
    echo -e "  ${GREEN}OK No unapproved PII detected.${NC}"
fi

# ─── Check 4: MANIFEST.json Basic Validation ─────────────────

echo -e "${GREEN}[4/7]${NC} Validating MANIFEST.json..."

# Python command was detected before the PII allowlist check.

if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    if [ -z "$PYTHON_CMD" ]; then
        echo -e "  ${YELLOW}⚠ Python not found. MANIFEST.json integrity NOT verified here.${NC}"
        echo "    The blocking check is 'aahp verify' Layer 1, which uses node or"
        echo "    python and FAILS outright when neither is available."
        # Deliberately a warning, not a violation: making it one would turn
        # currently green node-only environments red without catching anything
        # Layer 1 does not already catch. The summary below must therefore not
        # claim that all checks passed, because this one did not run.
        INTEGRITY_UNVERIFIED=1
    elif "$PYTHON_CMD" -c "import json; json.load(open('$HANDOFF_DIR/MANIFEST.json'))" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Valid JSON.${NC}"

        # Check required fields
        REQUIRED_FIELDS=("aahp_version" "project" "last_session" "files" "quick_context")
        for field in "${REQUIRED_FIELDS[@]}"; do
            if ! "$PYTHON_CMD" -c "import json; d=json.load(open('$HANDOFF_DIR/MANIFEST.json')); assert '$field' in d" 2>/dev/null; then
                echo -e "  ${RED}✗ Missing required field: $field${NC}"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        done

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
        # Exit contract of the embedded script: 0 = clean, 3 = findings,
        # anything else = the interpreter itself failed, and that ALSO counts
        # as a violation. If the tool cannot tell whether the files match,
        # integrity is unproven, and unproven must not print "All checks
        # passed". stderr is deliberately not discarded so the real cause of
        # an interpreter failure is visible in the gate log.
        echo "  Verifying indexed files..."
        CHECKSUM_RC=0
        AAHP_CANONICAL_HANDOFF_FILES="${AAHP_HANDOFF_FILES[*]}" \
        "$PYTHON_CMD" -c "
import json, hashlib, os, sys
sys.stdout.reconfigure(errors='replace')
manifest = json.load(open('$HANDOFF_DIR/MANIFEST.json'))
findings = 0
indexed = manifest.get('files') or {}
if not indexed:
    print('  ! MANIFEST.json indexes no files.')
    print('    Nothing could be verified, so nothing is verified.')
    print('    Fix: regenerate the manifest (aahp manifest).')
    sys.exit(3)
for fname, meta in indexed.items():
    fpath = os.path.join('$HANDOFF_DIR', fname)
    if not os.path.exists(fpath):
        print(f'  ! Missing indexed file: {fname}')
        print('    Indexed by MANIFEST.json but not present in the working tree.')
        print('    Fix: restore the file, or regenerate the manifest (aahp manifest).')
        findings += 1
        continue
    actual = 'sha256:' + hashlib.sha256(open(fpath, 'rb').read().replace(b'\r', b'')).hexdigest()
    expected = meta.get('checksum', '')
    if actual != expected:
        print(f'  ! Checksum mismatch: {fname}')
        print(f'    Expected: {expected}')
        print(f'    Actual:   {actual}')
        findings += 1
    else:
        print(f'  OK: {fname}')
for fname in os.environ.get('AAHP_CANONICAL_HANDOFF_FILES', '').split():
    if fname in indexed:
        continue
    if not os.path.exists(os.path.join('$HANDOFF_DIR', fname)):
        continue
    print(f'  ! Not indexed by MANIFEST.json: {fname}')
    print('    The file is present but has no entry, so it was never compared.')
    print('    Fix: regenerate the manifest (aahp manifest).')
    findings += 1
sys.exit(3 if findings else 0)
" || CHECKSUM_RC=$?
        if [ "$CHECKSUM_RC" -eq 3 ]; then
            VIOLATIONS=$((VIOLATIONS + 1))
        elif [ "$CHECKSUM_RC" -ne 0 ]; then
            echo -e "  ${RED}✗ Could not verify indexed files (verifier exited $CHECKSUM_RC).${NC}"
            echo "    Integrity is UNPROVEN. That counts as a violation, not a note."
            VIOLATIONS=$((VIOLATIONS + 1))
        fi

    else
        echo -e "  ${RED}✗ Invalid JSON.${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
else
    # A deleted manifest is the maximal "integrity unproven" state: there is
    # no index at all, so not one handoff file was compared. It used to print
    # a yellow note and let the run end with "All checks passed", which made
    # the blocking aahp-lint job green on a repository whose manifest was
    # gone. aahp verify Layer 1 has always failed here; both gates now agree.
    echo -e "  ${RED}✗ MANIFEST.json not found. Nothing about the handoff set is verified.${NC}"
    echo "    Fix: generate it with /handoff (aahp manifest)."
    VIOLATIONS=$((VIOLATIONS + 1))
fi

# ─── Check 5: Stale HANDOFF.lock ─────────────────────────────

echo -e "${GREEN}[5/7]${NC} Checking for stale HANDOFF.lock..."

if [ -f "$HANDOFF_DIR/HANDOFF.lock" ]; then
    echo -e "  ${RED}✗ HANDOFF.lock exists! Previous session may not have completed cleanly.${NC}"
    echo "    Review the lock file and delete it if the session is no longer active."
    cat "$HANDOFF_DIR/HANDOFF.lock" 2>/dev/null
    VIOLATIONS=$((VIOLATIONS + 1))
else
    echo -e "  ${GREEN}✓ No stale lock.${NC}"
fi

# ─── Check 6: Parallel Agent Detection ────────────────────────

echo -e "${GREEN}[6/7]${NC} Checking for parallel agent sessions..."

if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
    LOCK_BRANCHES=()
    while IFS= read -r branch; do
        if git -C "$PROJECT_ROOT" show "$branch:.ai/handoff/HANDOFF.lock" &>/dev/null 2>&1; then
            LOCK_BRANCHES+=("$branch")
        fi
    done < <(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' refs/heads/)

    if [ ${#LOCK_BRANCHES[@]} -gt 1 ]; then
        echo -e "  ${YELLOW}⚠ HANDOFF.lock found on multiple branches:${NC}"
        for b in "${LOCK_BRANCHES[@]}"; do
            echo "    - $b"
        done
        echo "  AAHP is designed for sequential handoff. Ensure agents are working in isolated branches."
    elif [ ${#LOCK_BRANCHES[@]} -eq 1 ]; then
        echo -e "  ${YELLOW}⚠ Active session on branch: ${LOCK_BRANCHES[0]}${NC}"
    else
        echo -e "  ${GREEN}✓ No active sessions detected across branches.${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Not a git repo. Skipping parallel agent check.${NC}"
fi

# ─── Check 7: Git conflict markers ───────────────────────────
# Refuse clean status when markers remain (nested-marker damage).

echo -e "${GREEN}[7/7]${NC} Checking for git conflict markers..."

MARKER_RC=0
# Prefer node (CI/Linux). On some Windows git-bash installs `node` is not on
# PATH even though Node exists for the package; fall back to absolute `node.exe`
# discovery is unnecessary - use the same interpreter helper pattern as _aahp-lib.
if command -v node &>/dev/null; then
    node "$SCRIPT_DIR/check-conflict-markers.mjs" "$PROJECT_ROOT" || MARKER_RC=$?
elif command -v node.exe &>/dev/null; then
    node.exe "$SCRIPT_DIR/check-conflict-markers.mjs" "$PROJECT_ROOT" || MARKER_RC=$?
else
    # Pure-bash fallback: strip CR and match markers without node.
    #
    # Same two changes as the node path AND the same predicate shape. An earlier
    # version of this comment claimed the two could not disagree while they did, on
    # three of six cases: node trims the line before testing and this anchored `^`,
    # so an INDENTED marker was caught there and missed here; and node uses
    # startsWith, so eight angle brackets matched there and not here. Measured, then
    # aligned to node's predicate, because an indented marker is still a marker. It walks the whole tree rather than the handoff directory, and the
    # `=======` alternative is gone: seven equals signs is a Markdown setext
    # underline and a Python docstring header, and it flipped 2 of 48 real adopter
    # roots red on files with no conflict in them.
    MARKER_FOUND=0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if tr -d '\r' < "$f" | grep -E '^[[:space:]]*(<<<<<<<|>>>>>>>)' -q; then
            echo -e "  ${RED}✗ Conflict markers present in: $f${NC}"
            MARKER_FOUND=1
        fi
    done < <(find "$PROJECT_ROOT" \( -name .git -o -name node_modules \) -prune \
        -o -type f -print 2>/dev/null)
    if [ "$MARKER_FOUND" -eq 1 ]; then
        MARKER_RC=1
    fi
fi
if [ "$MARKER_RC" -eq 1 ]; then
    VIOLATIONS=$((VIOLATIONS + 1))
elif [ "$MARKER_RC" -ne 0 ]; then
    echo -e "  ${RED}✗ conflict-marker check could not run (exit $MARKER_RC).${NC}"
    VIOLATIONS=$((VIOLATIONS + 1))
fi

# ─── Summary ──────────────────────────────────────────────────

echo ""
echo "========================================="
if [ "$VIOLATIONS" -eq 0 ] && [ "$INTEGRITY_UNVERIFIED" -eq 1 ]; then
    echo -e "  ${YELLOW}No violations found, but MANIFEST integrity was NOT verified here.${NC}"
    echo "  Run 'aahp verify', which blocks when integrity cannot be established."
    echo "========================================="
    exit 0
elif [ "$VIOLATIONS" -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed. ✓${NC}"
    echo "========================================="
    exit 0
else
    echo -e "  ${RED}$VIOLATIONS violation(s) found.${NC}"
    echo "========================================="
    exit 1
fi
