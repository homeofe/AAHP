#!/usr/bin/env bash
# aahp-migrate-v2.sh - Migrate an AAHP v1 handoff directory to v2/v3
#
# Usage: ./scripts/aahp-migrate-v2.sh [path-to-project] [--yes]
#        Defaults to current directory if no path given.
#
# Options:
#   --yes, -y   Regenerate an existing MANIFEST.json without asking. Without it
#               the answer is read from stdin; a stdin that yields no answer
#               (not a terminal and nothing piped in) is an error, exit 1.
#   --help, -h  Show this help
#
# What it CHANGES:
#   1. Generates MANIFEST.json from the existing handoff files
#   2. Copies the .aiignore template into .ai/handoff/ if none is present
#
# What it only REPORTS (manual steps; this script does not edit these files):
#   - whether STATUS.md carries <!-- SECTION: --> markers (README section 1.2)
#   - whether LOG.md holds more than 10 entries; rotate them with `aahp archive`
#     (README section 2.9)
#   - whether TRUST.md has TTL columns (README section 2.5)
#
# It ends with a summary that keeps the two lists apart, so a recommendation is
# never reported as something that was done.

set -euo pipefail

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
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

# Check if already v2. The prompt used to be a bare `read` under `set -e`: with
# no terminal and nothing piped in, `read` hit end of input, returned 1, and the
# script exited 1 without a word, not even the "Aborted." a declined prompt
# prints. A piped answer (`echo y | ...`) still works; no answer is now an
# explicit error that names --yes.
if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    echo -e "${YELLOW}MANIFEST.json already exists. This looks like a v2 project.${NC}"
    if [ "$ASSUME_YES" = true ]; then
        echo "--yes given: regenerating MANIFEST.json."
    else
        REPLY=""
        if ! read -r -p "Regenerate MANIFEST.json? (y/N) " -n 1 REPLY && [ -z "$REPLY" ]; then
            echo
            echo -e "${RED}Error: no answer could be read from stdin (it is not a terminal and nothing was piped in).${NC}" >&2
            echo "Nothing was changed. Re-run with --yes to regenerate MANIFEST.json non-interactively." >&2
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

# --- Step 1: Generate MANIFEST.json -----------------------------------------

echo -e "${GREEN}[1/5]${NC} Generating MANIFEST.json..."

bash "$SCRIPT_DIR/aahp-manifest.sh" "$PROJECT_ROOT" \
    --agent "migration-script" \
    --session-id "migrate-$(date +%s)" \
    --phase idle \
    --context "Migrated from AAHP v1. Review STATUS.md and NEXT_ACTIONS.md for current state." \
    --quiet

CHANGES+=("Generated MANIFEST.json")

# --- Step 2: Report STATUS.md section markers (not edited) ------------------

echo -e "${GREEN}[2/5]${NC} Checking STATUS.md for section markers (report only)..."

if [ -f "$HANDOFF_DIR/STATUS.md" ]; then
    if ! grep -q "<!-- SECTION:" "$HANDOFF_DIR/STATUS.md"; then
        echo -e "${YELLOW}  -> No section markers found. Not changed: adding them is a manual edit.${NC}"
        echo "  -> See README.md section 1.2 for the marker format."
        TODO+=("Add <!-- SECTION: name --> markers to STATUS.md (README section 1.2)")
    else
        echo "  -> Section markers already present."
    fi
else
    echo -e "${YELLOW}  -> STATUS.md not found. Skipping.${NC}"
fi

# --- Step 3: Report LOG.md size (not edited) --------------------------------

echo -e "${GREEN}[3/5]${NC} Checking LOG.md size (report only)..."

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

# --- Step 4: Copy .aiignore if missing --------------------------------------

echo -e "${GREEN}[4/5]${NC} Checking .aiignore..."

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

# --- Step 5: Report TRUST.md TTL columns (not edited) -----------------------

echo -e "${GREEN}[5/5]${NC} Checking TRUST.md for TTL columns (report only)..."

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
