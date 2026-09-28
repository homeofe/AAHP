#!/usr/bin/env bash
# verify-handoff.sh - The single canonical AAHP handoff gate ("aahp verify")
#
# Runs up to 4 layers that together stop staled handoff state from being
# committed or pushed:
#   1. MANIFEST integrity: every file MANIFEST.json indexes must exist and
#      must still match its recorded checksum, AND every canonical handoff
#      file present on disk must be indexed. All three are checked here,
#      against MANIFEST.json and the bytes on disk. lint-handoff.sh also runs
#      and its exit code still blocks, but no Layer 1 verdict is read out of
#      it.
#   2. Content-drift gate (THE key check): if a commit/push changes any source
#      file OUTSIDE .ai/handoff/, it MUST also include STATUS.md AND a
#      regenerated MANIFEST.json. Otherwise FAIL.
#   3. Commit-pointer freshness (MANIFEST.last_session.commit vs HEAD)
#   4. TRUST-TTL (TRUST.md): executable checks, expiry, and a grace period
#
# This gate is VERIFY-ONLY. It never regenerates MANIFEST.json itself; that
# stays a separate step (`aahp manifest`). The gate only reports drift and
# names the command that fixes it.
#
# Usage: ./scripts/verify-handoff.sh [path-to-project] [options]
#        Defaults to current directory if no path given.
#
# Options:
#   --level LEVEL   Which layers to run (default: full):
#                     precommit - fast: checksum + drift gate (layers 1-2)
#                     prepush   - full verify + TTL (layers 1-4)
#                     full      - all layers (alias for prepush)
#                     ci        - all layers, no escape hatch honoured
#   --base SHA      Exact base commit for the Layer 2 diff. Required at level
#                   ci; optional at other non-precommit levels. The equivalent
#                   environment variable is AAHP_BASE_SHA.
#   --quiet         Suppress per-check OK output, keep failures
#   --help, -h      Show this help
#
# Escape hatch:
#   AAHP_SKIP_VERIFY=1   Skip local verification. This is caught by the
#                        required CI check (aahp verify --level ci); do NOT
#                        use it to bypass CI. Ignored when --level ci.
#
# Exit codes:
#   0 = all selected layers passed (or skipped via escape hatch)
#   1 = at least one layer failed
#
# Defaults (documented):
#   - The drift gate HARD-FAILS (exit 1), it does not warn.
#   - Commit-pointer freshness is advisory at prepush/full/ci (not run at precommit).
#   - TRUST-TTL is advisory (warn) unless trustTtl.enforce is set; it never blocks a commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

# --- Defaults --------------------------------------------------

LEVEL="full"
QUIET=false
BASE_SHA="${AAHP_BASE_SHA:-}"
BASE_EXPLICIT=false
[ -n "$BASE_SHA" ] && BASE_EXPLICIT=true

# First positional arg is project root (if it does not start with --)
PROJECT_ROOT="."
if [ $# -gt 0 ] && [[ ! "$1" == --* ]]; then
    PROJECT_ROOT="$1"
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --level)
            [ $# -ge 2 ] || { echo "Error: --level requires a value" >&2; exit 1; }
            LEVEL="$2"; shift 2
            ;;
        --base)
            [ $# -ge 2 ] || { echo "Error: --base requires a SHA" >&2; exit 1; }
            BASE_SHA="$2"; BASE_EXPLICIT=true; shift 2
            ;;
        --quiet)  QUIET=true; shift ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: verify-handoff.sh [path-to-project] [--level precommit|prepush|full|ci] [--base SHA] [--quiet]" >&2
            exit 1
            ;;
    esac
done

case "$LEVEL" in
    precommit|prepush|full|ci) ;;
    *)
        echo "Error: Invalid --level '$LEVEL'. Must be one of: precommit, prepush, full, ci" >&2
        exit 1
        ;;
esac

if [ "$BASE_EXPLICIT" = true ] && [ -z "$BASE_SHA" ]; then
    echo "Error: --base requires a non-empty commit SHA" >&2
    exit 1
fi

# Path-format-agnostic file access (cross-platform fix).
# Windows-native Python/Node cannot open an absolute MSYS path like
# /c/Users/...; helpers that read MANIFEST.json (aahp_manifest_field) would
# fail. Change into the project root once, then drive everything off RELATIVE
# paths (lint-handoff.sh ".", git -C ".", '.ai/handoff/...'); these resolve
# identically on Windows git-bash and Linux CI. SCRIPT_DIR was already resolved
# above against $0, so sourcing/exec of sibling scripts is unaffected by the cd.
cd "$PROJECT_ROOT" || { echo -e "${RED}Error: cannot cd into project root: $PROJECT_ROOT${NC}" >&2; exit 1; }
PROJECT_ROOT="."
HANDOFF_DIR=".ai/handoff"

if [ ! -d "$HANDOFF_DIR" ]; then
    echo -e "${RED}Error: $HANDOFF_DIR not found.${NC}" >&2
    exit 1
fi

# --- Escape hatch ----------------------------------------------
# Honoured everywhere EXCEPT --level ci (the required off-machine check).

if [ "${AAHP_SKIP_VERIFY:-0}" = "1" ] && [ "$LEVEL" != "ci" ]; then
    echo -e "${YELLOW}AAHP_SKIP_VERIFY=1 set: skipping local handoff verification.${NC}"
    echo "  This is caught by the required CI check (aahp verify --level ci)."
    echo "  Do NOT use it to bypass CI."
    exit 0
fi

log_ok()   { [ "$QUIET" = true ] || echo -e "  ${GREEN}OK:${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}WARN:${NC} $1"; }
log_fail() { echo -e "  ${RED}FAIL:${NC} $1"; }

FAILURES=0

# The one command that regenerates MANIFEST.json, spelled the way it runs HERE.
# `/handoff` is not an AAHP command (README 9.1: AAHP ships no agent commands),
# and `npx aahp` is not offered because npx resolves the unscoped, unowned name
# `aahp` from the public registry when the package is not installed (ADR-013).
if [ -f "scripts/aahp-manifest.sh" ]; then
    REGEN_CMD="bash scripts/aahp-manifest.sh ."
elif [ -f "node_modules/@elvatis_com/aahp/bin/aahp.js" ]; then
    REGEN_CMD="node node_modules/@elvatis_com/aahp/bin/aahp.js manifest ."
else
    REGEN_CMD="aahp manifest ."
fi

# Remedies, per layer, collected where the failure is found and printed in the
# summary. "Regenerate the manifest" is the right answer for Layer 2 drift and
# the WRONG one for Layer 1 tampering or a Layer 4 register, so the footer names
# the failing layer and its own fix instead of one generic line.
L1_REMEDY=""
L2_REMEDY=""
L3_REMEDY=""
L4_REMEDY=""
add_remedy() {
    # $1 = layer number, $2 = one remedy line
    case "$1" in
        1) case $'\n'"$L1_REMEDY" in *$'\n'"$2"$'\n'*) ;; *) L1_REMEDY="${L1_REMEDY}$2"$'\n' ;; esac ;;
        2) case $'\n'"$L2_REMEDY" in *$'\n'"$2"$'\n'*) ;; *) L2_REMEDY="${L2_REMEDY}$2"$'\n' ;; esac ;;
        3) case $'\n'"$L3_REMEDY" in *$'\n'"$2"$'\n'*) ;; *) L3_REMEDY="${L3_REMEDY}$2"$'\n' ;; esac ;;
        4) case $'\n'"$L4_REMEDY" in *$'\n'"$2"$'\n'*) ;; *) L4_REMEDY="${L4_REMEDY}$2"$'\n' ;; esac ;;
    esac
}

echo ""
echo "========================================="
echo "  AAHP Verify (level: $LEVEL)"
echo "========================================="

# --- Layer 1: MANIFEST integrity -------------------------------
# Three distinct failures, reported separately because the fixes differ:
#   - an indexed file is MISSING     -> restore it, or regenerate the manifest
#   - an indexed file MISMATCHES     -> it changed outside the protocol
#   - a present file is NOT INDEXED  -> the index is partial, so that file was
#                                       never compared at all
# All are decided by this script, from MANIFEST.json and the bytes on disk.
# Anything that leaves integrity unproven (no JSON interpreter, an unparseable
# manifest, an empty or partial index, no checksum tool) is a FAILURE here,
# not a note:
# "could not check" is never allowed to read as "checked and clean".
# lint-handoff.sh still runs for the checks Layer 1 does not cover, and its
# exit code still blocks, but no Layer 1 verdict depends on its output.

echo ""
echo -e "${GREEN}[Layer 1]${NC} MANIFEST integrity: indexed files present and unchanged"

L1_START=$FAILURES
# Read by Layer 4's built-in `manifest-integrity` check. Only the OK line below
# sets it, so every path that does not reach a clean verdict leaves it failed.
LAYER1_VERDICT="fail"

if [ ! -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    log_fail "MANIFEST.json not found. Generate it: $REGEN_CMD"
    add_remedy 1 "Generate .ai/handoff/MANIFEST.json: $REGEN_CMD"
    FAILURES=$((FAILURES + 1))
else
    LINT_OUT=""
    LINT_RC=0
    LINT_OUT=$(bash "$SCRIPT_DIR/lint-handoff.sh" "$PROJECT_ROOT" 2>&1) || LINT_RC=$?
    LAYER1_FAILED=0

    # BOTH integrity verdicts are reached HERE, directly against MANIFEST.json
    # and the bytes on disk. Nothing in this layer is inferred from another
    # script's exit code or from string-matching its stdout, so a lint that
    # dies early, prints nothing, or exits 0 cannot make Layer 1 report clean.
    # lint-handoff.sh still runs, and its exit code still blocks, because it
    # covers checks Layer 1 does not (injection, secrets, PII, stale lock) and
    # because a second, independently written verifier is a useful cross-check.
    if ! declare -F aahp_manifest_index >/dev/null 2>&1; then
        log_fail "scripts/_aahp-lib.sh is out of date: helper 'aahp_manifest_index' is missing."
        echo "    Layer 1 cannot verify MANIFEST integrity without it, so nothing is proven."
        echo "    Fix: re-sync scripts/_aahp-lib.sh from the AAHP release that ships this gate."
        add_remedy 1 "Re-sync scripts/_aahp-lib.sh from the AAHP release that ships this gate."
        FAILURES=$((FAILURES + 1))
        LAYER1_FAILED=1
    else
        INDEX_RC=0
        MANIFEST_INDEX=$(aahp_manifest_index "$HANDOFF_DIR/MANIFEST.json") || INDEX_RC=$?

        if [ "$INDEX_RC" -eq 2 ]; then
            log_fail "No JSON interpreter available (need node or python)."
            echo "    MANIFEST integrity could not be checked, so it is NOT verified."
            add_remedy 1 "Install node (or python) so MANIFEST.json can be read."
            FAILURES=$((FAILURES + 1))
            LAYER1_FAILED=1
        elif [ "$INDEX_RC" -ne 0 ]; then
            log_fail "MANIFEST.json could not be read or parsed (helper exit $INDEX_RC)."
            echo "    Fix: repair the file, or regenerate it: $REGEN_CMD"
            add_remedy 1 "Repair .ai/handoff/MANIFEST.json, or regenerate it: $REGEN_CMD"
            FAILURES=$((FAILURES + 1))
            LAYER1_FAILED=1
        elif [ -z "${MANIFEST_INDEX//[[:space:]]/}" ]; then
            log_fail "MANIFEST.json indexes no files, so nothing was verified."
            echo "    An empty 'files' index proves nothing about the handoff set."
            echo "    Fix: regenerate the manifest: $REGEN_CMD"
            add_remedy 1 "Regenerate the manifest so it indexes the handoff files: $REGEN_CMD"
            FAILURES=$((FAILURES + 1))
            LAYER1_FAILED=1
        else
            MISSING_INDEXED=""
            MISMATCHED_INDEXED=""
            UNVERIFIABLE_INDEXED=""
            INDEXED_NAMES=""
            while IFS=$'\t' read -r idx_name idx_sum; do
                # Tolerate a CR-terminated index line. The helper writes LF
                # only, but a stale or third-party emitter on Windows can hand
                # back CRLF, and a CR left on the recorded checksum would make
                # every single file look tampered with.
                idx_name="${idx_name%$'\r'}"
                idx_sum="${idx_sum%$'\r'}"
                [ -n "$idx_name" ] || continue
                INDEXED_NAMES="${INDEXED_NAMES}${idx_name}"$'\n'
                if [ ! -f "$HANDOFF_DIR/$idx_name" ]; then
                    MISSING_INDEXED="${MISSING_INDEXED}${idx_name}"$'\n'
                    continue
                fi
                SUM_RC=0
                ACTUAL_SUM=$(aahp_checksum "$HANDOFF_DIR/$idx_name" 2>/dev/null) || SUM_RC=$?
                if [ "$SUM_RC" -ne 0 ] || [ -z "$ACTUAL_SUM" ]; then
                    UNVERIFIABLE_INDEXED="${UNVERIFIABLE_INDEXED}${idx_name}"$'\n'
                elif [ "$ACTUAL_SUM" != "$idx_sum" ]; then
                    MISMATCHED_INDEXED="${MISMATCHED_INDEXED}${idx_name}"$'\t'"${idx_sum}"$'\t'"${ACTUAL_SUM}"$'\n'
                fi
            done <<< "$MANIFEST_INDEX"

            # A PARTIAL index proves as little as an empty one. Comparing the
            # entries that are there says nothing about a canonical handoff
            # file that was dropped from "files" and then rewritten: zero
            # comparisons ran for it. The manifest generator indexes exactly
            # the canonical files present on disk, so anything present but not
            # indexed means the manifest is stale or was edited by hand.
            UNINDEXED_PRESENT=""
            for canon_name in "${AAHP_HANDOFF_FILES[@]}"; do
                [ -f "$HANDOFF_DIR/$canon_name" ] || continue
                case $'\n'"$INDEXED_NAMES" in
                    *$'\n'"$canon_name"$'\n'*) continue ;;
                esac
                UNINDEXED_PRESENT="${UNINDEXED_PRESENT}${canon_name}"$'\n'
            done

            if [ -n "$UNINDEXED_PRESENT" ]; then
                log_fail "Handoff file(s) present on disk but NOT indexed by MANIFEST.json."
                while IFS= read -r unindexed_file; do
                    [ -n "$unindexed_file" ] || continue
                    echo "    Unindexed handoff file: $unindexed_file"
                done <<< "$UNINDEXED_PRESENT"
                echo "    Nothing was verified for those files, so their contents are unproven."
                echo "    Fix: review them (git diff -- .ai/handoff), then regenerate the manifest: $REGEN_CMD"
                add_remedy 1 "Review the unindexed handoff file(s) (git diff -- .ai/handoff), then regenerate the manifest: $REGEN_CMD"
                FAILURES=$((FAILURES + 1))
                LAYER1_FAILED=1
            fi

            if [ -n "$MISSING_INDEXED" ]; then
                log_fail "MANIFEST.json indexes file(s) that are not present in the working tree."
                while IFS= read -r missing_file; do
                    [ -n "$missing_file" ] || continue
                    echo "    Missing indexed file: $missing_file"
                done <<< "$MISSING_INDEXED"
                echo "    Fix: restore the file(s), or regenerate the manifest: $REGEN_CMD"
                add_remedy 1 "Restore the missing handoff file(s), or regenerate the manifest if the deletion was intended: $REGEN_CMD"
                FAILURES=$((FAILURES + 1))
                LAYER1_FAILED=1
            fi

            if [ -n "$MISMATCHED_INDEXED" ]; then
                log_fail "MANIFEST.json checksums do not match file contents."
                while IFS=$'\t' read -r bad_name bad_expected bad_actual; do
                    [ -n "$bad_name" ] || continue
                    echo "    Checksum mismatch: $bad_name"
                    echo "      Expected: $bad_expected"
                    echo "      Actual:   $bad_actual"
                done <<< "$MISMATCHED_INDEXED"
                # Regenerating is the fix for an honest edit and the cover for a
                # dishonest one: it re-baselines whatever changed. Look first.
                echo "    Inspect the change BEFORE regenerating: git diff -- .ai/handoff"
                echo "    Regenerating re-baselines whatever changed, including tampering."
                echo "    Only if every change is legitimate: $REGEN_CMD"
                add_remedy 1 "A handoff file changed without its manifest. Inspect git diff -- .ai/handoff FIRST: regenerating re-baselines whatever changed, including tampering. Only if every change is legitimate: $REGEN_CMD"
                FAILURES=$((FAILURES + 1))
                LAYER1_FAILED=1
            fi

            if [ -n "$UNVERIFIABLE_INDEXED" ]; then
                log_fail "Could not compute a checksum for indexed file(s); integrity is UNPROVEN."
                while IFS= read -r bad_file; do
                    [ -n "$bad_file" ] || continue
                    echo "    Unverifiable indexed file: $bad_file"
                done <<< "$UNVERIFIABLE_INDEXED"
                echo "    Fix: install sha256sum or shasum, and make the file readable."
                add_remedy 1 "Install sha256sum or shasum and make the handoff files readable."
                FAILURES=$((FAILURES + 1))
                LAYER1_FAILED=1
            fi
        fi
    fi

    if [ "$LINT_RC" -ne 0 ] && [ "$LAYER1_FAILED" -eq 0 ]; then
        log_fail "lint-handoff.sh reported violations (exit $LINT_RC). Run: aahp lint"
        echo "$LINT_OUT" | tail -4 | sed 's/^/    /'
        add_remedy 1 "Run aahp lint (bash scripts/lint-handoff.sh .) and fix what it reports."
        FAILURES=$((FAILURES + 1))
        LAYER1_FAILED=1
    fi

    if [ "$LAYER1_FAILED" -eq 0 ]; then
        log_ok "Checksums and handoff lint pass."
        LAYER1_VERDICT="pass"
    fi
fi
L1_FAILS=$((FAILURES - L1_START))

# --- Layer 2: Content-drift gate (THE key check) ---------------
# If the change set touches any source file OUTSIDE .ai/handoff/, then the
# same change set MUST also include STATUS.md AND a regenerated MANIFEST.json.
#
# Change set selection by level:
#   precommit -> staged changes (git diff --cached)
#   prepush/full -> explicit --base/AAHP_BASE_SHA when supplied, else committed
#                   changes not yet on the upstream/base (fallback to staged +
#                   last commit if no upstream)
#   ci -> explicit --base/AAHP_BASE_SHA, with every missing, zero, unreadable,
#         self-referential, or failed diff treated as a blocking failure
#
# PROJECT ROOT, NOT REPOSITORY ROOT. Every diff below runs with --relative, so
# it is limited to the project directory and its paths are relative to it. A
# project that lives in a subdirectory of its repository used to get paths
# relative to the repository top level, so `.ai/handoff/STATUS.md` never
# matched and every change failed the gate however the handoff was updated.

echo ""
echo -e "${GREEN}[Layer 2]${NC} Content-drift gate (code changed => handoff must change)"

L2_START=$FAILURES

git_in_repo() { git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null 2>&1; }

CHANGED_RECORDS=""
DIFF_FAILED=0
DIFF_OLD_TREE="HEAD"
if git_in_repo; then
    if [ "$LEVEL" = "precommit" ]; then
        if ! CHANGED_RECORDS=$(git -C "$PROJECT_ROOT" diff --cached --relative --name-status --find-renames --find-copies --find-copies-harder 2>&1); then
            log_fail "Could not compute the staged Layer 2 diff."
            echo "$CHANGED_RECORDS" | sed '/^$/d' | sed 's/^/    /' | head -10
            add_remedy 2 "Make the staged diff computable (git diff --cached must succeed)."
            FAILURES=$((FAILURES + 1))
            DIFF_FAILED=1
            CHANGED_RECORDS=""
        fi
    else
        BASE_REF=""
        if [ "$BASE_EXPLICIT" = true ]; then
            BASE_REF="$BASE_SHA"
        elif [ "$LEVEL" = "ci" ]; then
            log_fail "Level ci requires an explicit base commit via --base SHA or AAHP_BASE_SHA."
            echo "    CI must pass the pull request base SHA or push event before SHA."
            add_remedy 2 "Pass the pull request base SHA (or the push event's before SHA) via --base or AAHP_BASE_SHA."
            FAILURES=$((FAILURES + 1))
            DIFF_FAILED=1
        # Prefer the upstream tracking branch; fall back to origin/main; then
        # fall back to the last commit so local full/prepush runs still work.
        elif git -C "$PROJECT_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null 2>&1; then
            BASE_REF=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}')
        elif git -C "$PROJECT_ROOT" rev-parse --verify origin/main &>/dev/null 2>&1; then
            BASE_REF="origin/main"
        fi

        if [ -n "$BASE_REF" ]; then
            BASE_COMMIT=""
            if [ "$BASE_EXPLICIT" = true ] && [[ ! "$BASE_REF" =~ ^[0-9A-Fa-f]{7,40}$ ]]; then
                log_fail "The explicit Layer 2 base must be a hexadecimal commit SHA."
                add_remedy 2 "Pass a hexadecimal commit SHA as the Layer 2 base."
                FAILURES=$((FAILURES + 1))
                DIFF_FAILED=1
            elif [ "$BASE_EXPLICIT" = true ] && [[ "$BASE_REF" =~ ^0+$ ]]; then
                log_fail "The explicit Layer 2 base cannot be the all-zero SHA."
                add_remedy 2 "Pass a real base commit; the all-zero SHA names no commit."
                FAILURES=$((FAILURES + 1))
                DIFF_FAILED=1
            elif ! BASE_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_REF^{commit}" 2>/dev/null); then
                log_fail "The Layer 2 base commit is missing, unreadable, or invalid: $BASE_REF"
                add_remedy 2 "Fetch enough history for the base commit (fetch-depth: 0) or pass one that exists."
                FAILURES=$((FAILURES + 1))
                DIFF_FAILED=1
            else
                HEAD_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)
                if [ "$LEVEL" = "ci" ] && [ "$BASE_COMMIT" = "$HEAD_COMMIT" ]; then
                    log_fail "The required CI base resolves to HEAD, which would make Layer 2 vacuous."
                    echo "    Pull requests must pass the base SHA; pushes must pass the event before SHA."
                    add_remedy 2 "Pass the pull request base SHA or the push event's before SHA, not HEAD."
                    FAILURES=$((FAILURES + 1))
                    DIFF_FAILED=1
                # Compare the two endpoint trees, not merge-base...HEAD. A push
                # can move a branch backwards or across histories; in that
                # case three-dot diff can select HEAD itself as the merge base
                # and return an empty, vacuous change set for a real rollback.
                elif ! CHANGED_RECORDS=$(git -C "$PROJECT_ROOT" diff --relative --name-status --find-renames --find-copies --find-copies-harder "$BASE_COMMIT" HEAD 2>&1); then
                    log_fail "Could not compute the Layer 2 diff from base $BASE_REF to HEAD."
                    echo "$CHANGED_RECORDS" | sed '/^$/d' | sed 's/^/    /' | head -10
                    add_remedy 2 "Make the base-to-HEAD diff computable (check the base commit and the checkout depth)."
                    FAILURES=$((FAILURES + 1))
                    DIFF_FAILED=1
                    CHANGED_RECORDS=""
                else
                    DIFF_OLD_TREE="$BASE_COMMIT"
                fi
            fi
        elif [ "$DIFF_FAILED" -eq 0 ]; then
            if ! CHANGED_RECORDS=$(git -C "$PROJECT_ROOT" diff --relative --name-status --find-renames --find-copies --find-copies-harder HEAD~1...HEAD 2>&1); then
                if ! CHANGED_RECORDS=$(git -C "$PROJECT_ROOT" show --relative --name-status --find-renames --find-copies --find-copies-harder --pretty=format: HEAD 2>&1); then
                    log_fail "Could not compute a fallback Layer 2 diff."
                    echo "$CHANGED_RECORDS" | sed '/^$/d' | sed 's/^/    /' | head -10
                    add_remedy 2 "Pass an explicit base with --base SHA."
                    FAILURES=$((FAILURES + 1))
                    DIFF_FAILED=1
                    CHANGED_RECORDS=""
                fi
            else
                DIFF_OLD_TREE=$(git -C "$PROJECT_ROOT" rev-parse --verify 'HEAD~1^{commit}' 2>/dev/null || printf 'HEAD')
            fi
        fi

        # Include staged-but-uncommitted changes too, so a "full" run in a dirty
        # tree still sees pending source edits.
        if [ "$DIFF_FAILED" -eq 0 ]; then
            if ! STAGED=$(git -C "$PROJECT_ROOT" diff --cached --relative --name-status --find-renames --find-copies --find-copies-harder 2>&1); then
                log_fail "Could not compute the staged Layer 2 diff."
                echo "$STAGED" | sed '/^$/d' | sed 's/^/    /' | head -10
                add_remedy 2 "Make the staged diff computable (git diff --cached must succeed)."
                FAILURES=$((FAILURES + 1))
                DIFF_FAILED=1
            else
                CHANGED_RECORDS=$(printf '%s\n%s\n' "$CHANGED_RECORDS" "$STAGED" | sort -u | sed '/^$/d')
            fi
        fi
    fi
else
    log_fail "Not a git repository. Layer 2 cannot compute a diff."
    add_remedy 2 "Run the gate inside the project's git repository."
    FAILURES=$((FAILURES + 1))
    DIFF_FAILED=1
fi

if git_in_repo && [ "$DIFF_FAILED" -eq 0 ]; then
    NON_IMPACTING_CONFIG=""
    CONFIG_VALID=1
    # Layer 2 must classify a change against policy from the SAME snapshot.
    # Reading an untracked or unstaged working-tree config while inspecting the
    # staged/index diff would let a policy that is not in the commit authorize
    # that commit. Fail closed instead; a fully staged config matches the index.
    if [ -e "aahp.config.json" ] || [ -L "aahp.config.json" ]; then
        CONFIG_INDEX_MATCH=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-files --error-unmatch -- "aahp.config.json" 2>/dev/null || true)
        if [ "$CONFIG_INDEX_MATCH" != "aahp.config.json" ]; then
            log_fail "aahp.config.json exists in the working tree but is not tracked in the index."
            echo "    Layer 2 will not apply policy that is absent from the change snapshot."
            add_remedy 2 "Track aahp.config.json (git add it) or remove it."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        fi
        CONFIG_INDEX_ENTRY=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-files -s -- "aahp.config.json" 2>/dev/null || true)
        CONFIG_INDEX_MODE=$(printf '%s\n' "$CONFIG_INDEX_ENTRY" | sed -n '1s/ .*//p')
        if [ "$CONFIG_INDEX_MODE" != "100644" ] && [ "$CONFIG_INDEX_MODE" != "100755" ]; then
            log_fail "aahp.config.json is not a regular tracked file (mode ${CONFIG_INDEX_MODE:-unknown})."
            echo "    Layer 2 will not follow a symlink or read policy from another Git object type."
            add_remedy 2 "Make aahp.config.json a regular tracked file."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        fi
        CONFIG_DIFF_RC=0
        git -C "$PROJECT_ROOT" diff --quiet -- "aahp.config.json" || CONFIG_DIFF_RC=$?
        if [ "$CONFIG_DIFF_RC" -eq 1 ]; then
            log_fail "aahp.config.json has unstaged changes."
            echo "    Stage or discard them so Layer 2 policy matches the inspected change snapshot."
            add_remedy 2 "Stage or discard the unstaged aahp.config.json changes."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        elif [ "$CONFIG_DIFF_RC" -gt 1 ]; then
            log_fail "Could not prove aahp.config.json matches the inspected change snapshot."
            add_remedy 2 "Make aahp.config.json readable to git."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        fi
    fi

    if ! declare -F aahp_non_impacting_modified_files >/dev/null 2>&1; then
        log_fail "scripts/_aahp-lib.sh is out of date: helper 'aahp_non_impacting_modified_files' is missing."
        add_remedy 2 "Re-sync scripts/_aahp-lib.sh from the AAHP release that ships this gate."
        FAILURES=$((FAILURES + 1))
        CONFIG_VALID=0
    elif [ "$CONFIG_VALID" -eq 1 ]; then
        CONFIG_RC=0
        NON_IMPACTING_CONFIG=$(aahp_non_impacting_modified_files "aahp.config.json" 2>&1) || CONFIG_RC=$?
        if [ "$CONFIG_RC" -eq 2 ]; then
            log_fail "No JSON interpreter available to validate handoffImpact configuration."
            add_remedy 2 "Install node (or python) so aahp.config.json can be validated."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        elif [ "$CONFIG_RC" -ne 0 ]; then
            log_fail "aahp.config.json has invalid handoffImpact configuration."
            echo "$NON_IMPACTING_CONFIG" | sed '/^$/d' | sed 's/^/    /' | head -10
            add_remedy 2 "Fix handoffImpact in aahp.config.json as reported above."
            FAILURES=$((FAILURES + 1))
            CONFIG_VALID=0
        fi
    fi

    if [ "$CONFIG_VALID" -eq 1 ] && [ -n "$NON_IMPACTING_CONFIG" ]; then
        while IFS=$'\t' read -r configured_file configured_reason; do
            [ -n "$configured_file" ] || continue
            if [ -d "$configured_file" ]; then
                log_fail "Configured non-impacting path is a directory, not an exact file: $configured_file"
                add_remedy 2 "List exact files, not directories, in handoffImpact.nonImpactingModifiedFiles."
                FAILURES=$((FAILURES + 1))
                CONFIG_VALID=0
                continue
            fi
            TRACKED_MATCH=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-files --error-unmatch -- "$configured_file" 2>/dev/null || true)
            HEAD_MATCH=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-tree -r --name-only HEAD -- "$configured_file" 2>/dev/null || true)
            if [ "$TRACKED_MATCH" != "$configured_file" ] && [ "$HEAD_MATCH" != "$configured_file" ]; then
                log_fail "Configured non-impacting path is not one exact tracked file: $configured_file"
                add_remedy 2 "List only exact tracked files in handoffImpact.nonImpactingModifiedFiles."
                FAILURES=$((FAILURES + 1))
                CONFIG_VALID=0
            fi
            INDEX_MODE_RC=0
            OLD_MODE_RC=0
            INDEX_MODE_ENTRY=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-files -s -- "$configured_file" 2>/dev/null) || INDEX_MODE_RC=$?
            OLD_MODE_ENTRY=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-tree "$DIFF_OLD_TREE" -- "$configured_file" 2>/dev/null) || OLD_MODE_RC=$?
            INDEX_MODE=$(printf '%s\n' "$INDEX_MODE_ENTRY" | sed -n '1s/ .*//p')
            OLD_MODE=$(printf '%s\n' "$OLD_MODE_ENTRY" | sed -n '1s/ .*//p')
            if [ "$INDEX_MODE_RC" -ne 0 ] || [ "$OLD_MODE_RC" -ne 0 ] || { [ -z "$INDEX_MODE" ] && [ -z "$OLD_MODE" ]; }; then
                log_fail "Could not prove configured non-impacting path is a regular tracked file: $configured_file"
                add_remedy 2 "List only regular tracked files in handoffImpact.nonImpactingModifiedFiles."
                FAILURES=$((FAILURES + 1))
                CONFIG_VALID=0
            fi
            for tracked_mode in "$INDEX_MODE" "$OLD_MODE"; do
                [ -n "$tracked_mode" ] || continue
                case "$tracked_mode" in
                    100644|100755) ;;
                    *)
                        log_fail "Configured non-impacting path is not a regular tracked file: $configured_file (mode $tracked_mode)"
                        echo "    Symlinks, gitlinks, and unexpected file modes remain handoff-impacting."
                        add_remedy 2 "List only regular tracked files in handoffImpact.nonImpactingModifiedFiles."
                        FAILURES=$((FAILURES + 1))
                        CONFIG_VALID=0
                        ;;
                esac
            done
            if [ -n "$INDEX_MODE" ] && [ -n "$OLD_MODE" ] && [ "$INDEX_MODE" != "$OLD_MODE" ]; then
                log_fail "Configured non-impacting path changed Git mode: $configured_file ($OLD_MODE -> $INDEX_MODE)"
                echo "    The reviewed M-only exception permits content changes, not executable-bit changes."
                add_remedy 2 "Revert the mode change, or treat the change as impacting and update the handoff."
                FAILURES=$((FAILURES + 1))
                CONFIG_VALID=0
            fi
        done <<< "$NON_IMPACTING_CONFIG"
    fi

    # --- Opt-in: content-verified npm devDependency updates -------------
    # handoffImpact.npmDevDependencyUpdates classifies a change set by its
    # CONTENT (see aahp_npm_dev_update_verdict), never by its author. The
    # owner tied it to a supply-chain scanner that runs on pull requests, so
    # the opt-in carries a claim about the workflow and that claim is proven
    # here, against the inspected snapshot (the index), on EVERY run: deleting
    # or disabling the scanner job while the opt-in stays is a failure in the
    # very change that does it, not a silent loss of the precondition.
    NPM_OPTIN=0
    NPM_REASON=""
    if [ "$CONFIG_VALID" -eq 1 ] && [ -f "aahp.config.json" ]; then
        NPM_REASON=$(aahp_manifest_field "aahp.config.json" "handoffImpact.npmDevDependencyUpdates.reason")
    fi
    if [ -n "$NPM_REASON" ]; then
        NPM_WORKFLOW=$(aahp_manifest_field "aahp.config.json" "handoffImpact.npmDevDependencyUpdates.supplyChainScan.workflow")
        NPM_JOB=$(aahp_manifest_field "aahp.config.json" "handoffImpact.npmDevDependencyUpdates.supplyChainScan.job")
        NPM_SCAN_PROBLEM=""
        # GitHub reads workflows at the REPOSITORY top level, so the workflow
        # path is resolved there even when this project is a subdirectory.
        REPO_TOP=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
        WF_ENTRY=""
        [ -n "$REPO_TOP" ] && WF_ENTRY=$(git -C "$REPO_TOP" --literal-pathspecs ls-files -s -- "$NPM_WORKFLOW" 2>/dev/null || true)
        WF_MODE=$(printf '%s\n' "$WF_ENTRY" | sed -n '1s/ .*//p')
        if [ -z "$NPM_WORKFLOW" ] || [ -z "$NPM_JOB" ]; then
            NPM_SCAN_PROBLEM="supplyChainScan.workflow and supplyChainScan.job could not be read"
        elif [ "$WF_MODE" != "100644" ] && [ "$WF_MODE" != "100755" ]; then
            NPM_SCAN_PROBLEM="$NPM_WORKFLOW is not a regular file tracked in the inspected snapshot"
        elif ! WF_TEXT=$(git -C "$PROJECT_ROOT" cat-file blob ":$NPM_WORKFLOW" 2>/dev/null); then
            NPM_SCAN_PROBLEM="$NPM_WORKFLOW could not be read from the inspected snapshot"
        else
            WF_RC=0
            WF_OUT=$(printf '%s\n' "$WF_TEXT" | aahp_workflow_job_on_pull_request "$NPM_JOB") || WF_RC=$?
            [ "$WF_RC" -eq 0 ] || NPM_SCAN_PROBLEM="$NPM_WORKFLOW: ${WF_OUT:-not proven}"
        fi
        if [ -n "$NPM_SCAN_PROBLEM" ]; then
            log_fail "handoffImpact.npmDevDependencyUpdates requires a supply-chain scan on pull requests, and the inspected snapshot does not show one."
            echo "    $NPM_SCAN_PROBLEM"
            echo "    The exemption is not applied while its precondition is unproven."
            add_remedy 2 "Point handoffImpact.npmDevDependencyUpdates.supplyChainScan at a job that exists and runs on pull_request, or remove the opt-in."
            FAILURES=$((FAILURES + 1))
        else
            NPM_OPTIN=1
            log_ok "npm devDependency exemption configured: job '$NPM_JOB' in $NPM_WORKFLOW runs on pull_request."
            echo "    Whether that job is a REQUIRED check is a repository setting this gate cannot read."
        fi
    fi

    IMPACTING_CHANGED=""
    STATUS_TOUCHED=""
    MANIFEST_TOUCHED=""
    # Shape of the impacting set, for the npm devDependency opt-in: it may only
    # ever hold a content modification of package-lock.json, optionally with
    # package.json. Anything else anywhere in the set disqualifies it.
    NPM_SHAPE_OK=1
    NPM_HAS_LOCK=""
    NPM_HAS_PKG=""
    while IFS=$'\t' read -r change_status path_one path_two; do
        [ -n "$change_status" ] || continue

        # A rename or copy has two paths and always remains impacting. Added,
        # deleted, renamed, copied, type-changed, and unmerged states can never
        # use the reviewed M-only exception.
        if [[ "$change_status" == R* || "$change_status" == C* ]]; then
            DISPLAY_CHANGE="$change_status $path_one -> $path_two"
            CHANGE_PATHS=$(printf '%s\n%s\n' "$path_one" "$path_two")
        else
            DISPLAY_CHANGE="$change_status $path_one"
            CHANGE_PATHS="$path_one"
        fi

        OUTSIDE_HANDOFF=""
        while IFS= read -r changed_path; do
            [ -n "$changed_path" ] || continue
            case "$changed_path" in
                .ai/handoff/STATUS.md) STATUS_TOUCHED=1 ;;
                .ai/handoff/MANIFEST.json) MANIFEST_TOUCHED=1 ;;
            esac
            case "$changed_path" in
                .ai/handoff/*) ;;
                *) OUTSIDE_HANDOFF=1 ;;
            esac
        done <<< "$CHANGE_PATHS"
        [ -n "$OUTSIDE_HANDOFF" ] || continue

        CLASSIFIED_REASON=""
        if [ "$CONFIG_VALID" -eq 1 ] && [ "$change_status" = "M" ] && [ -z "$path_two" ]; then
            while IFS=$'\t' read -r configured_file configured_reason; do
                if [ "$configured_file" = "$path_one" ]; then
                    CLASSIFIED_REASON="$configured_reason"
                    break
                fi
            done <<< "$NON_IMPACTING_CONFIG"
        fi

        if [ -n "$CLASSIFIED_REASON" ]; then
            log_ok "Reviewed non-impacting modification: $path_one"
            echo "    Reason: $CLASSIFIED_REASON"
            # A reviewed file in the same change set is still "any other file"
            # for the npm opt-in, which covers lockfile updates and nothing else.
            NPM_SHAPE_OK=0
        else
            IMPACTING_CHANGED="${IMPACTING_CHANGED}${DISPLAY_CHANGE}"$'\n'
            if [ "$change_status" = "M" ] && [ -z "$path_two" ] && [ "$path_one" = "package-lock.json" ]; then
                NPM_HAS_LOCK=1
            elif [ "$change_status" = "M" ] && [ -z "$path_two" ] && [ "$path_one" = "package.json" ]; then
                NPM_HAS_PKG=1
            else
                NPM_SHAPE_OK=0
            fi
        fi
    done <<< "$CHANGED_RECORDS"

    NPM_NOTE=""
    # Only a change set that modifies package-lock.json is a candidate. Anything
    # else is not a dependency update, and saying why the exemption did not apply
    # to it would print on every ordinary change.
    if [ -n "$IMPACTING_CHANGED" ] && [ "$NPM_OPTIN" -eq 1 ] && [ -n "$NPM_HAS_LOCK" ] && { [ -z "$STATUS_TOUCHED" ] || [ -z "$MANIFEST_TOUCHED" ]; }; then
        if [ "$NPM_SHAPE_OK" -ne 1 ]; then
            NPM_NOTE="the change set is not a modification of package-lock.json (optionally with package.json) and nothing else"
        else
            NPM_MODE_PROBLEM=""
            for npm_file in package-lock.json package.json; do
                if [ "$npm_file" = "package.json" ] && [ -z "$NPM_HAS_PKG" ]; then
                    continue
                fi
                NPM_NEW_MODE=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-files -s -- "$npm_file" 2>/dev/null | sed -n '1s/ .*//p')
                NPM_OLD_MODE=$(git -C "$PROJECT_ROOT" --literal-pathspecs ls-tree "$DIFF_OLD_TREE" -- "$npm_file" 2>/dev/null | sed -n '1s/ .*//p')
                if [ "$NPM_NEW_MODE" != "100644" ] || [ "$NPM_OLD_MODE" != "100644" ]; then
                    NPM_MODE_PROBLEM="$npm_file is not a regular non-executable file on both sides (${NPM_OLD_MODE:-none} -> ${NPM_NEW_MODE:-none})"
                fi
            done
            if [ -n "$NPM_MODE_PROBLEM" ]; then
                NPM_NOTE="$NPM_MODE_PROBLEM"
            else
                NPM_PREFIX=$(git -C "$PROJECT_ROOT" rev-parse --show-prefix 2>/dev/null || true)
                NPM_RC=0
                NPM_OUT=$(aahp_npm_dev_update_verdict "$DIFF_OLD_TREE" "$NPM_PREFIX" "$([ -n "$NPM_HAS_PKG" ] && echo 1 || echo 0)" 2>&1) || NPM_RC=$?
                if [ "$NPM_RC" -eq 0 ]; then
                    NPM_FILES="package-lock.json"
                    [ -n "$NPM_HAS_PKG" ] && NPM_FILES="package-lock.json, package.json"
                    log_ok "Content-verified npm devDependency update: $NPM_FILES (${NPM_OUT:-entries checked}: every one dev-only, registry-resolved, integrity-pinned)."
                    echo "    Reason: $NPM_REASON"
                    IMPACTING_CHANGED=""
                else
                    NPM_NOTE="$NPM_OUT"
                fi
            fi
        fi
    fi

    if [ -z "$IMPACTING_CHANGED" ]; then
        log_ok "No handoff-impacting files changed outside .ai/handoff/. Drift gate not triggered."
    else
        if [ -n "$STATUS_TOUCHED" ] && [ -n "$MANIFEST_TOUCHED" ]; then
            log_ok "Handoff-impacting files changed and handoff state (STATUS.md + MANIFEST.json) changed with them."
        else
            log_fail "Handoff-impacting files changed but handoff state did not."
            echo "    Impacting changes outside .ai/handoff/:"
            echo "$IMPACTING_CHANGED" | sed '/^$/d' | sed 's/^/      - /' | head -20
            [ -z "$STATUS_TOUCHED" ]   && echo "    Missing: .ai/handoff/STATUS.md update"
            [ -z "$MANIFEST_TOUCHED" ] && echo "    Missing: regenerated .ai/handoff/MANIFEST.json"
            if [ -n "$NPM_NOTE" ]; then
                echo "    npm devDependency exemption not applied:"
                printf '%s\n' "$NPM_NOTE" | sed '/^$/d' | sed 's/^/      - /' | head -20
            fi
            echo "    Fix: describe the change in .ai/handoff/STATUS.md, then regenerate the manifest"
            echo "    ($REGEN_CMD) and include both in the same change set."
            add_remedy 2 "Describe the change in .ai/handoff/STATUS.md, regenerate the manifest ($REGEN_CMD), and include both in the same change set."
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi
L2_FAILS=$((FAILURES - L2_START))

# --- Layer 3: Commit-pointer freshness -------------------------
# MANIFEST.last_session.commit should describe the code at HEAD.
# Not run at precommit (HEAD is about to move); advisory at prepush/full/ci.
#
# A manifest can never record the commit that contains it, so "pointer ==
# HEAD" is unreachable after any committed handoff and this layer used to
# warn forever. The precise rule instead: OK when the recorded commit is an
# ancestor of HEAD and HEAD's tree differs from it ONLY under .ai/handoff/
# (within the project root). That is the case after the documented flow
# (commit the code, regenerate the manifest, commit the handoff), and it is
# exactly the statement "the manifest was generated against the code at HEAD".
# Anything else warns: code moved since the pointer, or the pointer is not in
# HEAD's history (a squash-merge or rebase-merge orphans a branch-local one;
# Layers 1-2 gate real staleness in that case).

L3_FAILS=0
if [ "$LEVEL" != "precommit" ]; then
    echo ""
    echo -e "${GREEN}[Layer 3]${NC} Commit-pointer freshness (MANIFEST.last_session.commit vs HEAD)"
    L3_START=$FAILURES

    if ! git_in_repo; then
        log_warn "Not a git repo. Skipping commit-pointer check."
    elif [ ! -f "$HANDOFF_DIR/MANIFEST.json" ]; then
        log_fail "MANIFEST.json missing; cannot check commit pointer."
        add_remedy 3 "Generate .ai/handoff/MANIFEST.json: $REGEN_CMD"
        FAILURES=$((FAILURES + 1))
    else
        HEAD_FULL=$(git -C "$PROJECT_ROOT" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null || echo "")
        HEAD_SHORT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "")
        MANIFEST_COMMIT=$(aahp_manifest_field "$HANDOFF_DIR/MANIFEST.json" "last_session.commit")
        POINTER_FULL=""
        # The pointer is handoff DATA. Only a plain hex SHA ever reaches git.
        if [[ "$MANIFEST_COMMIT" =~ ^[0-9A-Fa-f]+$ ]] && [ "${#MANIFEST_COMMIT}" -ge 4 ] && [ "${#MANIFEST_COMMIT}" -le 64 ]; then
            POINTER_FULL=$(git -C "$PROJECT_ROOT" rev-parse --verify -q "${MANIFEST_COMMIT}^{commit}" 2>/dev/null || echo "")
        fi
        if [ -z "$MANIFEST_COMMIT" ] || [ "$MANIFEST_COMMIT" = "unknown" ]; then
            log_warn "MANIFEST.last_session.commit is unset. Regenerate the manifest after the first commit: $REGEN_CMD"
        elif [ -z "$HEAD_FULL" ]; then
            log_warn "Could not resolve HEAD. Skipping."
        elif [ -z "$POINTER_FULL" ]; then
            log_warn "MANIFEST commit ($MANIFEST_COMMIT) is not a commit in this repository. A squash-merge or rebase-merge orphans the branch-local pointer; Layers 1-2 gate real staleness. Regenerate the manifest if code changed: $REGEN_CMD"
        elif [ "$POINTER_FULL" = "$HEAD_FULL" ]; then
            log_ok "MANIFEST commit ($MANIFEST_COMMIT) matches HEAD ($HEAD_SHORT)."
        elif ! git -C "$PROJECT_ROOT" merge-base --is-ancestor "$POINTER_FULL" "$HEAD_FULL" &>/dev/null; then
            log_warn "MANIFEST commit ($MANIFEST_COMMIT) is not an ancestor of HEAD ($HEAD_SHORT). A squash-merge or rebase-merge orphans the branch-local pointer; Layers 1-2 gate real staleness. Regenerate the manifest if code changed: $REGEN_CMD"
        elif ! POINTER_DIFF=$(git -C "$PROJECT_ROOT" diff --relative --no-renames --name-only "$POINTER_FULL" "$HEAD_FULL" 2>/dev/null); then
            log_warn "MANIFEST commit ($MANIFEST_COMMIT) is behind HEAD ($HEAD_SHORT), and the change since it could not be computed."
        else
            POINTER_OUTSIDE=$(printf '%s\n' "$POINTER_DIFF" | sed '/^$/d' | grep -v '^\.ai/handoff/' || true)
            if [ -z "$POINTER_OUTSIDE" ]; then
                log_ok "MANIFEST commit ($MANIFEST_COMMIT) is an ancestor of HEAD ($HEAD_SHORT) and everything since it changed only .ai/handoff/."
            else
                POINTER_OUTSIDE_COUNT=$(printf '%s\n' "$POINTER_OUTSIDE" | wc -l | tr -d ' ')
                log_warn "MANIFEST commit ($MANIFEST_COMMIT) is behind HEAD ($HEAD_SHORT): $POINTER_OUTSIDE_COUNT file(s) outside .ai/handoff/ changed since. If the handoff does not describe them yet, update STATUS.md and regenerate: $REGEN_CMD"
            fi
        fi
    fi
    L3_FAILS=$((FAILURES - L3_START))
fi

# --- Layer 4: TRUST-TTL -----------------------------------------
# Reads every row of TRUST.md and judges each `verified` row one of two ways:
#
#   CHECK-BACKED. The row names a check in a `Check` column. The check runs on
#   every verify and the row is judged by its result, not by its date: a fact a
#   machine can re-prove does not need a calendar, and a calendar alone turned
#   every pull request red on 2026-09-22 with no code change. Only built-in
#   checks and checks declared in aahp.config.json (trustTtl.checks, reviewed
#   configuration) can run. TRUST.md is agent-written data and nothing read
#   from it is ever executed; an id that is neither is a failed check.
#
#   JUDGMENT (no check). Judged by its Expires date. Past it, the row WARNS for
#   trustTtl.graceDays (default 14); after that it is a blocking failure when
#   trustTtl.enforce is on. Without enforce every Layer 4 finding warns, which
#   is the historical default (ADR-007, ADR-024).
#
# Nothing here rewrites TRUST.md: an expired `verified` row is REPORTED, it is
# not downgraded (the gate is verify-only). Downgrading or re-verifying it is
# the agent's edit.
#
# NO SILENT GREEN. A register with no row this layer can judge (no trust table,
# a table without a Status column, or only assumed/untested rows) is reported
# as NOT EVALUATED, and under enforce it fails, exactly as before: otherwise
# enforcement could be switched off by breaking the table, or by downgrading
# every row, instead of by editing the reviewed config. The census line says
# what was read.
#
# Layer 4 does not run at precommit, so no local commit is blocked, and the
# pull request that refreshes TRUST.md carries the refreshed rows with it.

L4_FAILS=0
if [ "$LEVEL" != "precommit" ]; then
    echo ""
    echo -e "${GREEN}[Layer 4]${NC} TRUST-TTL (TRUST.md): checks, expiry and grace period"
    L4_START=$FAILURES

    # Read the policy before anything else, so a config this gate cannot read is
    # reported as a failure rather than resolved to "not enforcing".
    TRUST_ENFORCE=0
    TRUST_GRACE="$AAHP_TRUST_DEFAULT_GRACE_DAYS"
    TRUST_DECLARED=""
    if TRUST_POLICY_OUT=$(aahp_trust_policy "$PROJECT_ROOT/aahp.config.json" 2>&1); then
        while IFS=$'\t' read -r policy_key policy_value; do
            case "$policy_key" in
                enforce) TRUST_ENFORCE="$policy_value" ;;
                graceDays) TRUST_GRACE="$policy_value" ;;
                check) TRUST_DECLARED="${TRUST_DECLARED}${policy_value}"$'\n' ;;
            esac
        done <<< "$TRUST_POLICY_OUT"
    else
        TRUST_POLICY_RC=$?
        if [ "$TRUST_POLICY_RC" -eq 2 ]; then
            log_warn "trustTtl configuration could not be read: $TRUST_POLICY_OUT"
        else
            log_fail "trustTtl configuration could not be read: $TRUST_POLICY_OUT"
            add_remedy 4 "Fix trustTtl in aahp.config.json as reported above."
            FAILURES=$((FAILURES + 1))
        fi
    fi
    ENFORCE_NOTE=""
    [ "$TRUST_ENFORCE" = "1" ] && ENFORCE_NOTE=" and trustTtl.enforce is on"

    # One verdict per check id per run, whatever number of rows name it.
    TRUST_CHECK_CACHE=""
    TC_VERDICT=""
    TC_DETAIL=""
    trust_builtin_license_matches() {
        local spdx lic="" f must1="" must2="" not1="" not2=""
        if [ ! -f "package.json" ]; then
            TC_VERDICT="fail"; TC_DETAIL="no package.json at the project root to declare a license"; return
        fi
        spdx=$(aahp_manifest_field "package.json" "license")
        for f in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md; do
            if [ -f "$f" ]; then lic="$f"; break; fi
        done
        if [ -z "$spdx" ]; then
            TC_VERDICT="fail"; TC_DETAIL="package.json declares no license string"; return
        fi
        if [ -z "$lic" ]; then
            TC_VERDICT="fail"; TC_DETAIL="no LICENSE file at the project root"; return
        fi
        case "$spdx" in
            MIT) must1="Permission is hereby granted, free of charge" ;;
            Apache-2.0) must1="Apache License"; must2="Version 2.0" ;;
            ISC) must1="Permission to use, copy, modify, and/or distribute this software" ;;
            BSD-2-Clause) must1="Redistribution and use in source and binary forms"; not1="Neither the name" ;;
            BSD-3-Clause) must1="Redistribution and use in source and binary forms"; must2="Neither the name" ;;
            GPL-2.0|GPL-2.0-only|GPL-2.0-or-later) must1="GNU GENERAL PUBLIC LICENSE"; must2="Version 2,"; not1="LESSER GENERAL PUBLIC"; not2="AFFERO GENERAL PUBLIC" ;;
            GPL-3.0|GPL-3.0-only|GPL-3.0-or-later) must1="GNU GENERAL PUBLIC LICENSE"; must2="Version 3,"; not1="LESSER GENERAL PUBLIC"; not2="AFFERO GENERAL PUBLIC" ;;
            LGPL-3.0|LGPL-3.0-only|LGPL-3.0-or-later) must1="GNU LESSER GENERAL PUBLIC LICENSE"; must2="Version 3," ;;
            AGPL-3.0|AGPL-3.0-only|AGPL-3.0-or-later) must1="GNU AFFERO GENERAL PUBLIC LICENSE"; must2="Version 3," ;;
            MPL-2.0) must1="Mozilla Public License"; must2="Version 2.0" ;;
            Unlicense) must1="This is free and unencumbered software released into the public domain" ;;
            *)
                TC_VERDICT="fail"
                TC_DETAIL="package.json license is not an SPDX id this check recognises; declare a trustTtl.checks entry instead"
                return
                ;;
        esac
        for f in "$must1" "$must2"; do
            [ -n "$f" ] || continue
            if ! grep -qiF -- "$f" "$lic"; then
                TC_VERDICT="fail"; TC_DETAIL="package.json says $spdx but $lic does not contain \"$f\""; return
            fi
        done
        for f in "$not1" "$not2"; do
            [ -n "$f" ] || continue
            if grep -qiF -- "$f" "$lic"; then
                TC_VERDICT="fail"; TC_DETAIL="package.json says $spdx but $lic contains \"$f\""; return
            fi
        done
        TC_VERDICT="pass"; TC_DETAIL="package.json $spdx matches $lic"
    }
    trust_check() {
        local id="$1" cached rc out
        cached=$(printf '%s' "$TRUST_CHECK_CACHE" | awk -F '|' -v id="$id" '$1 == id { print; exit }')
        if [ -n "$cached" ]; then
            TC_VERDICT=$(printf '%s' "$cached" | cut -d '|' -f 2)
            TC_DETAIL=$(printf '%s' "$cached" | cut -d '|' -f 3-)
            return
        fi
        if [[ ! "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || [ "${#id}" -gt 64 ]; then
            TC_VERDICT="fail"
            TC_DETAIL="not a valid check id (lowercase letters, digits and hyphens); nothing was run"
        else
            case "$id" in
                license-matches) trust_builtin_license_matches ;;
                manifest-integrity)
                    if [ "$LAYER1_VERDICT" = "pass" ]; then
                        TC_VERDICT="pass"; TC_DETAIL="Layer 1 passed in this run"
                    else
                        TC_VERDICT="fail"; TC_DETAIL="Layer 1 failed in this run"
                    fi
                    ;;
                *)
                    case $'\n'"$TRUST_DECLARED" in
                        *$'\n'"$id"$'\n'*)
                            rc=0
                            out=$(aahp_trust_run_check "$PROJECT_ROOT/aahp.config.json" "$id" 2>&1) || rc=$?
                            if [ "$rc" -eq 0 ]; then
                                TC_VERDICT="pass"; TC_DETAIL="declared check exited 0"
                            else
                                TC_VERDICT="fail"; TC_DETAIL=$(printf '%s' "$out" | sed '/^$/d' | tr '\n|' ';/')
                                [ -n "$TC_DETAIL" ] || TC_DETAIL="declared check failed (exit $rc)"
                            fi
                            ;;
                        *)
                            TC_VERDICT="fail"
                            TC_DETAIL="not a built-in check ($AAHP_TRUST_BUILTIN_CHECKS) and not declared in aahp.config.json trustTtl.checks; nothing was run"
                            ;;
                    esac
                    ;;
            esac
        fi
        TRUST_CHECK_CACHE="${TRUST_CHECK_CACHE}${id}|${TC_VERDICT}|${TC_DETAIL}"$'\n'
    }
    # Print untrusted cell text safely: never at the start of a line (so it
    # cannot become a CI workflow command), and with control characters removed.
    trust_safe() { printf '%s' "$1" | tr -d '\000-\037\177' | cut -c1-160; }

    TRUST_FILE="$HANDOFF_DIR/TRUST.md"
    if [ ! -f "$TRUST_FILE" ]; then
        if [ "$TRUST_ENFORCE" = "1" ]; then
            log_fail "TRUST.md not found and trustTtl.enforce is on. TTL was NOT evaluated, which is not a pass."
            add_remedy 4 "Add .ai/handoff/TRUST.md with a trust table (see templates/TRUST.md), or turn trustTtl.enforce off."
            FAILURES=$((FAILURES + 1))
        else
            log_warn "TRUST.md not found. TTL was NOT evaluated."
        fi
    else
        TODAY=$(date -u +"%Y-%m-%d")
        TRUST_ROWS=$(aahp_trust_rows "$TRUST_FILE" "$TODAY")
        T_ROWS=0; T_VERIFIED=0; T_ASSUMED=0; T_UNTESTED=0; T_OTHER=0
        T_CHECKED=0; T_CHECK_PASS=0; T_DATED=0; T_UNDATED=0
        CHECK_FAILED_LINES=""; CHECK_PASSED_IDS=""
        IN_GRACE_LINES=""; PAST_GRACE_LINES=""; UNDATED_LINES=""
        IN_GRACE_COUNT=0; PAST_GRACE_COUNT=0
        while IFS='|' read -r t_status t_past t_expires t_check t_property; do
            [ -n "$t_status$t_past$t_expires$t_check$t_property" ] || continue
            T_ROWS=$((T_ROWS + 1))
            case "$t_status" in
                verified) T_VERIFIED=$((T_VERIFIED + 1)) ;;
                assumed) T_ASSUMED=$((T_ASSUMED + 1)); continue ;;
                untested) T_UNTESTED=$((T_UNTESTED + 1)); continue ;;
                *) T_OTHER=$((T_OTHER + 1)); continue ;;
            esac
            t_label=$(trust_safe "$t_property")
            if [ -n "$t_check" ]; then
                T_CHECKED=$((T_CHECKED + 1))
                trust_check "$t_check"
                t_id=$(trust_safe "$t_check" | tr -c 'A-Za-z0-9._\n-' '?')
                if [ "$TC_VERDICT" = "pass" ]; then
                    T_CHECK_PASS=$((T_CHECK_PASS + 1))
                    case " $CHECK_PASSED_IDS " in *" $t_id "*) ;; *) CHECK_PASSED_IDS="${CHECK_PASSED_IDS:+$CHECK_PASSED_IDS }$t_id" ;; esac
                else
                    CHECK_FAILED_LINES="${CHECK_FAILED_LINES}${t_label} [check $t_id]: $(trust_safe "$TC_DETAIL")"$'\n'
                fi
            elif [ -n "$t_past" ]; then
                T_DATED=$((T_DATED + 1))
                if [ "$t_past" -le 0 ]; then
                    :
                elif [ "$t_past" -le "$TRUST_GRACE" ]; then
                    IN_GRACE_COUNT=$((IN_GRACE_COUNT + 1))
                    IN_GRACE_LINES="${IN_GRACE_LINES}${t_label} (expired $(trust_safe "$t_expires"), ${t_past} day(s) ago; grace ends in $((TRUST_GRACE - t_past)) day(s))"$'\n'
                else
                    PAST_GRACE_COUNT=$((PAST_GRACE_COUNT + 1))
                    PAST_GRACE_LINES="${PAST_GRACE_LINES}${t_label} (expired $(trust_safe "$t_expires"), ${t_past} day(s) ago)"$'\n'
                fi
            else
                T_UNDATED=$((T_UNDATED + 1))
                UNDATED_LINES="${UNDATED_LINES}${t_label}"$'\n'
            fi
        done <<< "$TRUST_ROWS"

        T_DECIDABLE=$((T_CHECKED + T_DATED))
        if [ "$T_ROWS" -gt 0 ]; then
            echo "    Census: $T_ROWS trust row(s) read: $T_VERIFIED verified ($T_CHECKED check-backed, $T_DATED dated, $T_UNDATED with neither), $T_ASSUMED assumed, $T_UNTESTED untested, $T_OTHER other."
        fi

        if [ "$T_DECIDABLE" -eq 0 ]; then
            # No row reached a verdict. Reporting "no expired entries" here
            # would be a verdict over nothing.
            if [ "$T_ROWS" -eq 0 ]; then
                if [ "$TRUST_ENFORCE" = "1" ]; then
                    log_fail "TRUST.md holds no trust table this reader recognises and trustTtl.enforce is on. TTL was NOT evaluated, which is not a pass."
                    add_remedy 4 "Give TRUST.md a trust table with Status and Expires (or Check) columns (see templates/TRUST.md)."
                    FAILURES=$((FAILURES + 1))
                else
                    log_warn "TRUST.md holds no trust table this reader recognises. TTL was NOT evaluated (this is not 'no expired entries')."
                fi
            else
                if [ "$TRUST_ENFORCE" = "1" ]; then
                    log_fail "TRUST.md holds $T_ROWS trust row(s), but none could be judged: a judged row is 'verified' and has a 'Status' column plus a dated 'Expires' or a 'Check' cell. trustTtl.enforce is on and TTL was NOT evaluated, which is not a pass."
                    add_remedy 4 "Re-verify at least one TRUST.md row (Status verified, with a dated Expires or a Check), or turn trustTtl.enforce off."
                    FAILURES=$((FAILURES + 1))
                else
                    log_warn "TRUST.md holds $T_ROWS trust row(s), but none could be judged: a judged row is 'verified' and has a 'Status' column plus a dated 'Expires' or a 'Check' cell. TTL was NOT evaluated (this is not 'no expired entries')."
                fi
            fi
        else
            if [ "$T_CHECK_PASS" -gt 0 ]; then
                log_ok "$T_CHECK_PASS check-backed 'verified' row(s) re-proven by their check(s): $CHECK_PASSED_IDS."
            fi
            if [ -n "$CHECK_FAILED_LINES" ]; then
                CHECK_FAILED_COUNT=$(printf '%s' "$CHECK_FAILED_LINES" | sed '/^$/d' | wc -l | tr -d ' ')
                if [ "$TRUST_ENFORCE" = "1" ]; then
                    log_fail "$CHECK_FAILED_COUNT of $T_CHECKED check-backed 'verified' row(s) failed their check$ENFORCE_NOTE. The claim is false now, whatever its date:"
                    add_remedy 4 "Fix what the failing trust check(s) report, or downgrade those TRUST.md rows to assumed. Regenerating MANIFEST.json does not clear this."
                    FAILURES=$((FAILURES + 1))
                else
                    log_warn "$CHECK_FAILED_COUNT of $T_CHECKED check-backed 'verified' row(s) failed their check. The claim is false now, whatever its date:"
                fi
                printf '%s' "$CHECK_FAILED_LINES" | sed '/^$/d' | sed 's/^/      - /' | head -20
            fi
            if [ "$PAST_GRACE_COUNT" -gt 0 ]; then
                if [ "$TRUST_ENFORCE" = "1" ]; then
                    log_fail "$PAST_GRACE_COUNT of $T_DATED dated 'verified' trust entr(ies) expired more than $TRUST_GRACE day(s) ago$ENFORCE_NOTE. Re-verify and reset TTL, or downgrade to assumed:"
                    add_remedy 4 "Re-verify the listed TRUST.md rows and reset Last Verified and Expires, or downgrade them to assumed (or give a row a Check). Regenerating MANIFEST.json does not clear this."
                    FAILURES=$((FAILURES + 1))
                else
                    log_warn "$PAST_GRACE_COUNT of $T_DATED dated 'verified' trust entr(ies) expired more than $TRUST_GRACE day(s) ago. Re-verify and reset TTL:"
                fi
                printf '%s' "$PAST_GRACE_LINES" | sed '/^$/d' | sed 's/^/      - /' | head -20
            fi
            if [ "$IN_GRACE_COUNT" -gt 0 ]; then
                if [ "$TRUST_ENFORCE" = "1" ]; then
                    log_warn "$IN_GRACE_COUNT of $T_DATED dated 'verified' trust entr(ies) expired within the $TRUST_GRACE-day grace period; each blocks once its grace ends. Re-verify and reset TTL:"
                else
                    log_warn "$IN_GRACE_COUNT of $T_DATED dated 'verified' trust entr(ies) expired within the last $TRUST_GRACE day(s). Re-verify and reset TTL:"
                fi
                printf '%s' "$IN_GRACE_LINES" | sed '/^$/d' | sed 's/^/      - /' | head -20
            fi
            if [ "$T_UNDATED" -gt 0 ]; then
                log_warn "$T_UNDATED 'verified' row(s) carry neither a dated Expires nor a Check, so they were not judged:"
                printf '%s' "$UNDATED_LINES" | sed '/^$/d' | sed 's/^/      - /' | head -20
            fi
            if [ -z "$CHECK_FAILED_LINES" ] && [ "$PAST_GRACE_COUNT" -eq 0 ] && [ "$IN_GRACE_COUNT" -eq 0 ]; then
                log_ok "No expired 'verified' trust entries ($T_DECIDABLE checked)."
            fi
        fi
    fi
    L4_FAILS=$((FAILURES - L4_START))
fi

# --- Summary ---------------------------------------------------

echo ""
echo "========================================="
if [ "$FAILURES" -eq 0 ]; then
    echo -e "  ${GREEN}aahp verify passed (level: $LEVEL).${NC}"
    echo "========================================="
    exit 0
else
    echo -e "  ${RED}aahp verify FAILED: $FAILURES blocking issue(s) (level: $LEVEL).${NC}"
    FAILED_LAYERS=""
    [ "$L1_FAILS" -gt 0 ] && FAILED_LAYERS="${FAILED_LAYERS:+$FAILED_LAYERS, }Layer 1 (MANIFEST integrity)"
    [ "$L2_FAILS" -gt 0 ] && FAILED_LAYERS="${FAILED_LAYERS:+$FAILED_LAYERS, }Layer 2 (content drift)"
    [ "$L3_FAILS" -gt 0 ] && FAILED_LAYERS="${FAILED_LAYERS:+$FAILED_LAYERS, }Layer 3 (commit pointer)"
    [ "$L4_FAILS" -gt 0 ] && FAILED_LAYERS="${FAILED_LAYERS:+$FAILED_LAYERS, }Layer 4 (TRUST-TTL)"
    echo "  Failing: ${FAILED_LAYERS:-unattributed}"
    for footer_layer in 1 2 3 4; do
        case "$footer_layer" in
            1) footer_fails=$L1_FAILS; footer_remedy=$L1_REMEDY ;;
            2) footer_fails=$L2_FAILS; footer_remedy=$L2_REMEDY ;;
            3) footer_fails=$L3_FAILS; footer_remedy=$L3_REMEDY ;;
            4) footer_fails=$L4_FAILS; footer_remedy=$L4_REMEDY ;;
        esac
        [ "$footer_fails" -gt 0 ] || continue
        printf '%s' "$footer_remedy" | sed '/^$/d' | sed "s/^/  Layer $footer_layer fix: /"
    done
    echo "========================================="
    exit 1
fi
