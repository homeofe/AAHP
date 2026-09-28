#!/usr/bin/env bash
# aahp-migrate-v2.sh - Migrate an AAHP v1 handoff directory to v2/v3
#
# Usage: ./scripts/aahp-migrate-v2.sh [path-to-project] [--yes]
#        Defaults to current directory if no path given.
#
# Options:
#   --yes, -y   Change an existing MANIFEST.json (step 1 and the regeneration)
#               without asking. Without it the answer is read from stdin; a stdin
#               that yields no answer (not a terminal and nothing piped in) is an
#               error, exit 1.
#   --help, -h  Show this help
#
# What it CHANGES:
#   1. In an existing MANIFEST.json, removes every OPTIONAL task field whose value
#      is an unreplaced template placeholder the schema rejects (such as
#      "created": "[ISO-8601]" or "YYYY-MM-DDT00:00:00Z"), printing task, field and
#      old value. A REQUIRED field holding one stops the run before anything is
#      changed. Any other value, placeholder-shaped or not, is left alone.
#   2. Generates MANIFEST.json from the existing handoff files
#   3. Copies the .aiignore template into .ai/handoff/ if none is present
#
# What it only REPORTS (manual steps; this script does not edit these files):
#   - whether STATUS.md has the optional summary marker (README section 1.2)
#   - whether LOG.md holds more than 10 entries; rotate them with `aahp archive`
#     (README section 2.9)
#   - whether TRUST.md has TTL columns (README section 2.5)
#
# It ends with a summary that keeps the two lists apart, so a recommendation is
# never reported as something that was done.

set -euo pipefail

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

PROJECT_ROOT="."
PATH_SET=false
ASSUME_YES=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=true; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "Error: unknown option: $1" >&2; echo "Usage: aahp-migrate-v2.sh [path] [--yes]" >&2; exit 1 ;;
        *)
            if [ "$PATH_SET" = true ]; then
                echo "Error: unexpected extra argument: $1" >&2
                exit 1
            fi
            PROJECT_ROOT="$1"; PATH_SET=true; shift ;;
    esac
done

HANDOFF_DIR="$PROJECT_ROOT/.ai/handoff"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

echo ""
echo "========================================="
echo "  AAHP v1 -> v2/v3 Migration"
echo "========================================="
echo ""

# Check handoff directory exists
if [ ! -d "$HANDOFF_DIR" ]; then
    echo -e "${RED}Error: $HANDOFF_DIR not found.${NC}"
    echo "Is this an AAHP project? Run from the project root or pass the path."
    exit 1
fi

# Template placeholders in task fields (step 1). Since aahp doctor validates
# MANIFEST.json against the whole schema, a task that still says
# "created": "[ISO-8601]" fails doctor after an upgrade, and aahp manifest carries
# tasks over unchanged, so regenerating alone never clears it. The rule for what
# counts, and the edit itself, live in aahp-manifest-placeholders.mjs (see its
# header). It runs twice: read-only BEFORE the prompt, so a REQUIRED field that
# holds a placeholder refuses the run before anything is asked or changed, and
# with --apply after consent.
PLACEHOLDER_SCRIPT="$SCRIPT_DIR/aahp-manifest-placeholders.mjs"
PH_RC=0
NODE_BIN=""
if command -v node >/dev/null 2>&1; then
    NODE_BIN="node"
elif command -v node.exe >/dev/null 2>&1; then
    NODE_BIN="node.exe"
fi

# Check if already v2. The prompt used to be a bare `read` under `set -e`: with
# no terminal and nothing piped in, `read` hit end of input, returned 1, and the
# script exited 1 without a word, not even the "Aborted." a declined prompt
# prints. A piped answer (`echo y | ...`) still works; no answer is now an
# explicit error that names --yes.
if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    echo -e "${YELLOW}MANIFEST.json already exists. This looks like a v2 project.${NC}"
    if [ -z "$NODE_BIN" ]; then
        echo -e "${RED}Error: Node.js was not found on PATH.${NC} Reading and regenerating MANIFEST.json needs node. Nothing was changed." >&2
        exit 1
    fi
    echo "Checking MANIFEST.json tasks for unreplaced template placeholders (read-only)..."
    "$NODE_BIN" "$PLACEHOLDER_SCRIPT" "$HANDOFF_DIR/MANIFEST.json" || PH_RC=$?
    # 1: a required field holds a placeholder; the script named it and changed
    # nothing. 2: the manifest could not be inspected (not valid JSON, say); the
    # generator in step 2 then decides what happens to that file and says why.
    if [ "$PH_RC" -eq 1 ]; then
        exit 1
    fi
    if [ "$ASSUME_YES" = true ]; then
        echo "--yes given: updating MANIFEST.json (step 1 and regeneration)."
    else
        REPLY=""
        if ! read -r -p "Update MANIFEST.json (remove any placeholders listed above, then regenerate)? (y/N) " -n 1 REPLY && [ -z "$REPLY" ]; then
            echo
            echo -e "${RED}Error: no answer could be read from stdin (it is not a terminal and nothing was piped in).${NC}" >&2
            echo "Nothing was changed. Re-run with --yes to update MANIFEST.json non-interactively." >&2
            exit 1
        fi
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
fi

CHANGES=()
TODO=()

# --- Step 1: Remove template placeholders from MANIFEST.json tasks ------------
#
# The original bytes are kept until the regeneration in step 2 has succeeded, so
# the two edits land together or not at all: a generator that refuses the file
# (an unknown top-level field, say) leaves MANIFEST.json exactly as it was found.

echo -e "${GREEN}[1/6]${NC} Removing template placeholders from MANIFEST.json tasks..."

MANIFEST_BACKUP=""
if [ -f "$HANDOFF_DIR/MANIFEST.json" ] && [ "$PH_RC" -eq 0 ]; then
    MANIFEST_BACKUP="$(mktemp)"
    trap 'rm -f "$MANIFEST_BACKUP"' EXIT
    cp "$HANDOFF_DIR/MANIFEST.json" "$MANIFEST_BACKUP"
    PH_OUT=""
    PH_APPLY_RC=0
    PH_OUT="$("$NODE_BIN" "$PLACEHOLDER_SCRIPT" "$HANDOFF_DIR/MANIFEST.json" --apply)" || PH_APPLY_RC=$?
    if [ -n "$PH_OUT" ]; then
        printf '%s\n' "$PH_OUT"
    fi
    if [ "$PH_APPLY_RC" -ne 0 ]; then
        cp "$MANIFEST_BACKUP" "$HANDOFF_DIR/MANIFEST.json"
        echo -e "${RED}Error: removing the placeholders failed (see above). MANIFEST.json is unchanged.${NC}" >&2
        exit 1
    fi
    while IFS= read -r line; do
        case "$line" in
            *"-> removed "*) CHANGES+=("MANIFEST.json: ${line#*-> }") ;;
        esac
    done <<< "$PH_OUT"
elif [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    echo -e "${YELLOW}  -> Skipped: MANIFEST.json could not be inspected (see above).${NC}"
else
    echo "  -> No MANIFEST.json yet; nothing to check."
fi

# --- Step 2: Generate MANIFEST.json -----------------------------------------

echo -e "${GREEN}[2/6]${NC} Generating MANIFEST.json..."

if ! bash "$SCRIPT_DIR/aahp-manifest.sh" "$PROJECT_ROOT" \
    --agent "migration-script" \
    --session-id "migrate-$(date +%s)" \
    --phase idle \
    --context "Migrated from AAHP v1. Review STATUS.md and NEXT_ACTIONS.md for current state." \
    --quiet; then
    if [ -n "$MANIFEST_BACKUP" ]; then
        cp "$MANIFEST_BACKUP" "$HANDOFF_DIR/MANIFEST.json"
        echo -e "${RED}Error: MANIFEST.json could not be regenerated (see above). It was restored to the bytes it had before this run, placeholders included.${NC}" >&2
    fi
    exit 1
fi

CHANGES+=("Generated MANIFEST.json")

# --- Step 3: Report the optional STATUS.md summary marker (not edited) -------
#
# README section 1.2: markers are optional, and the only one AAHP reads is
# `<!-- SECTION: summary -->`, from which aahp manifest takes the file's summary.
# Any other section name is a convention AAHP never reads, so its presence says
# nothing here. The pattern is the one scripts/aahp-manifest.sh matches.

echo -e "${GREEN}[3/6]${NC} Checking STATUS.md for the optional summary marker (report only)..."

if [ -f "$HANDOFF_DIR/STATUS.md" ]; then
    if grep -Eiq '<!--[[:space:]]*SECTION:[[:space:]]*summary[[:space:]]*-->' "$HANDOFF_DIR/STATUS.md"; then
        echo "  -> Summary marker present: aahp manifest reads the STATUS.md summary from it."
    else
        echo -e "${YELLOW}  -> No <!-- SECTION: summary --> marker. Optional: without it, aahp manifest uses the first prose sentence.${NC}"
        echo "  -> See README.md section 1.2. Other section names are a convention AAHP does not read."
        TODO+=("Optional: add a <!-- SECTION: summary --> block to STATUS.md (README section 1.2)")
    fi
else
    echo -e "${YELLOW}  -> STATUS.md not found. Skipping.${NC}"
fi

# --- Step 4: Report LOG.md size (not edited) --------------------------------

echo -e "${GREEN}[4/6]${NC} Checking LOG.md size (report only)..."

if [ -f "$HANDOFF_DIR/LOG.md" ]; then
    # grep -c prints its count AND exits 1 when the count is 0, so the old
    # `$(grep -c ... || echo 0)` captured "0" twice ("0\n0") and the test below
    # failed with "integer expression expected". Take grep's own count and fall
    # back to 0 only when it printed nothing (an unreadable file).
    ENTRY_COUNT="$(grep -c '^## \[' "$HANDOFF_DIR/LOG.md" 2>/dev/null)" || true
    ENTRY_COUNT="${ENTRY_COUNT:-0}"
    if [ "$ENTRY_COUNT" -gt 10 ]; then
        echo -e "${YELLOW}  -> LOG.md has $ENTRY_COUNT entries (the active log keeps 10). Not changed.${NC}"
        echo "  -> Rotate the older entries into LOG-ARCHIVE.md with: aahp archive (README section 2.9)"
        TODO+=("LOG.md has $ENTRY_COUNT entries: rotate the older ones with 'aahp archive'")
    else
        echo "  -> LOG.md has $ENTRY_COUNT entries. No rotation needed."
    fi
else
    echo -e "${YELLOW}  -> LOG.md not found. Skipping.${NC}"
fi

# --- Step 5: Copy .aiignore if missing --------------------------------------

echo -e "${GREEN}[5/6]${NC} Checking .aiignore..."

if [ ! -f "$HANDOFF_DIR/.aiignore" ]; then
    if [ -f "$REPO_ROOT/templates/.aiignore" ]; then
        cp "$REPO_ROOT/templates/.aiignore" "$HANDOFF_DIR/.aiignore"
        CHANGES+=("Copied .aiignore template")
        echo "  -> Copied .aiignore template."
    else
        echo -e "${YELLOW}  -> Template not found at $REPO_ROOT/templates/.aiignore${NC}"
    fi
else
    echo "  -> .aiignore already present."
fi

# --- Step 6: Report TRUST.md TTL columns (not edited) -----------------------

echo -e "${GREEN}[6/6]${NC} Checking TRUST.md for TTL columns (report only)..."

if [ -f "$HANDOFF_DIR/TRUST.md" ]; then
    if ! grep -q "TTL" "$HANDOFF_DIR/TRUST.md"; then
        echo -e "${YELLOW}  -> No TTL columns found. Not changed: adding them is a manual edit.${NC}"
        echo "  -> See README.md section 2.5 for the TTL format."
        TODO+=("Add TTL columns to TRUST.md (README section 2.5)")
    else
        echo "  -> TTL columns already present."
    fi
else
    echo "  -> TRUST.md not found. Skipping."
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "========================================="
echo "  Migration Summary"
echo "========================================="
echo ""

echo "Changed:"
for change in "${CHANGES[@]}"; do
    echo -e "  ${GREEN}[ok]${NC} $change"
done

if [ ${#TODO[@]} -gt 0 ]; then
    echo ""
    echo "Left for you (reported only, NOT changed by this script):"
    for item in "${TODO[@]}"; do
        echo -e "  ${YELLOW}[todo]${NC} $item"
    done
fi

echo ""
echo "Next steps:"
echo "  1. Review the generated MANIFEST.json"
echo "  2. Update quick_context with actual project state"
echo "  3. Work through the [todo] items above, if any"
echo "  4. Commit: git add .ai/handoff/ && git commit -m 'chore: migrate AAHP v1 -> v2/v3'"

echo ""
