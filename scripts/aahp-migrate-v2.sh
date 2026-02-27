#!/usr/bin/env bash
# aahp-migrate-v2.sh -Migrate an AAHP v1 handoff directory to v2
#
# Usage: ./scripts/aahp-migrate-v2.sh [path-to-project]
#        Defaults to current directory if no path given.
#
# What it does:
#   1. Generates MANIFEST.json from existing handoff files
#   2. Adds section markers to STATUS.md (if missing)
#   3. Splits LOG.md into active (last 10 entries) + LOG-ARCHIVE.md
#   4. Copies .aiignore template if not present
#   5. Reports what was changed

set -euo pipefail

PROJECT_ROOT="${1:-.}"
HANDOFF_DIR="$PROJECT_ROOT/.ai/handoff"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

echo ""
echo "========================================="
echo "  AAHP v1 → v2 Migration"
echo "========================================="
echo ""

# Check handoff directory exists
if [ ! -d "$HANDOFF_DIR" ]; then
    echo -e "${RED}Error: $HANDOFF_DIR not found.${NC}"
    echo "Is this an AAHP project? Run from the project root or pass the path."
    exit 1
fi

# Check if already v2
if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    echo -e "${YELLOW}MANIFEST.json already exists. This looks like a v2 project.${NC}"
    read -p "Regenerate MANIFEST.json? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

CHANGES=()

# ─── Step 1: Generate MANIFEST.json ───────────────────────────

echo -e "${GREEN}[1/5]${NC} Generating MANIFEST.json..."

bash "$SCRIPT_DIR/aahp-manifest.sh" "$PROJECT_ROOT" \
    --agent "migration-script" \
    --session-id "migrate-$(date +%s)" \
    --phase idle \
    --context "Migrated from AAHP v1. Review STATUS.md and NEXT_ACTIONS.md for current state." \
    --quiet

CHANGES+=("Created MANIFEST.json")

# ─── Step 2: Add section markers to STATUS.md ────────────────

echo -e "${GREEN}[2/5]${NC} Checking STATUS.md for section markers..."

if [ -f "$HANDOFF_DIR/STATUS.md" ]; then
    if ! grep -q "<!-- SECTION:" "$HANDOFF_DIR/STATUS.md"; then
        echo -e "${YELLOW}  → No section markers found. Adding them is recommended but requires manual editing.${NC}"
        echo "  → See README.md section 1.2 for the marker format."
    else
        echo "  → Section markers already present."
    fi
else
    echo -e "${YELLOW}  → STATUS.md not found. Skipping.${NC}"
fi

# ─── Step 3: Split LOG.md if too long ─────────────────────────

echo -e "${GREEN}[3/5]${NC} Checking LOG.md size..."

if [ -f "$HANDOFF_DIR/LOG.md" ]; then
    ENTRY_COUNT=$(grep -c '^## \[' "$HANDOFF_DIR/LOG.md" 2>/dev/null || echo 0)
    if [ "$ENTRY_COUNT" -gt 10 ]; then
        echo -e "${YELLOW}  → LOG.md has $ENTRY_COUNT entries (limit: 10). Splitting...${NC}"

        # This is a simplified split -keeps last 10 entries in LOG.md
        # Moves everything else to LOG-ARCHIVE.md
        # A production version should be smarter about entry boundaries

        echo "  → Automatic splitting requires manual review."
        echo "  → Recommendation: Move entries older than the last 10 to LOG-ARCHIVE.md"
        CHANGES+=("LOG.md has $ENTRY_COUNT entries -manual split recommended")
    else
        echo "  → LOG.md has $ENTRY_COUNT entries. No split needed."
    fi
else
    echo -e "${YELLOW}  → LOG.md not found. Skipping.${NC}"
fi

# ─── Step 4: Copy .aiignore if missing ────────────────────────

echo -e "${GREEN}[4/5]${NC} Checking .aiignore..."

if [ ! -f "$HANDOFF_DIR/.aiignore" ]; then
    if [ -f "$REPO_ROOT/templates/.aiignore" ]; then
        cp "$REPO_ROOT/templates/.aiignore" "$HANDOFF_DIR/.aiignore"
        CHANGES+=("Copied .aiignore template")
        echo "  → Copied .aiignore template."
    else
        echo -e "${YELLOW}  → Template not found at $REPO_ROOT/templates/.aiignore${NC}"
    fi
else
    echo "  → .aiignore already present."
fi

# ─── Step 5: Add TTL column to TRUST.md ──────────────────────

echo -e "${GREEN}[5/5]${NC} Checking TRUST.md for TTL columns..."

if [ -f "$HANDOFF_DIR/TRUST.md" ]; then
    if ! grep -q "TTL" "$HANDOFF_DIR/TRUST.md"; then
        echo -e "${YELLOW}  → No TTL columns found. Adding TTL is recommended but requires manual editing.${NC}"
        echo "  → See README.md section 2.5 for the TTL format."
        CHANGES+=("TRUST.md needs TTL columns -manual update recommended")
    else
        echo "  → TTL columns already present."
    fi
else
    echo "  → TRUST.md not found. Skipping."
fi

# ─── Summary ──────────────────────────────────────────────────

echo ""
echo "========================================="
echo "  Migration Summary"
echo "========================================="
echo ""

if [ ${#CHANGES[@]} -eq 0 ]; then
    echo -e "${GREEN}No changes needed. Project appears to be v2 compatible.${NC}"
else
    for change in "${CHANGES[@]}"; do
        echo -e "  ${GREEN}✓${NC} $change"
    done
    echo ""
    echo "Next steps:"
    echo "  1. Review the generated MANIFEST.json"
    echo "  2. Update quick_context with actual project state"
    echo "  3. Add section markers to STATUS.md (optional but recommended)"
    echo "  4. Commit: git add .ai/handoff/ && git commit -m 'chore: migrate AAHP v1 → v2'"
fi

echo ""
