#!/usr/bin/env bash
# aahp-migrate-grounding.sh - Add the Grounded Reflection Layer to an existing
# AAHP project in place (README section 2.10).
#
# Usage: ./scripts/aahp-migrate-grounding.sh [path-to-project] [--force]
#        Defaults to current directory if no path given.
#
# What it does (idempotent, non-interactive, stages nothing to git):
#   1. Adds a "Provenance (Draft v0.1)" section to TRUST.md if absent
#   2. Copies templates/GROUNDING.md into .ai/handoff/GROUNDING.md if absent
#   3. Regenerates MANIFEST.json so it indexes GROUNDING.md and re-checksums TRUST.md
#   4. Reports what was changed
#
# The migration only touches files under .ai/handoff/, so it does not trip the
# content-drift gate. It never overwrites an edited GROUNDING.md and never rewrites
# existing TRUST.md rows. Re-running it is safe.

set -euo pipefail

# Parse args: first non-flag argument is the project root; flags are accepted and
# ignored (the script is already non-destructive and idempotent).
PROJECT_ROOT="."
for arg in "$@"; do
    case "$arg" in
        --*) : ;;
        *) PROJECT_ROOT="$arg"; break ;;
    esac
done

HANDOFF_DIR="$PROJECT_ROOT/.ai/handoff"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

echo ""
echo "========================================="
echo "  AAHP Grounded Reflection Migration"
echo "========================================="
echo ""

if [ ! -d "$HANDOFF_DIR" ]; then
    echo -e "${RED}Error: $HANDOFF_DIR not found.${NC}"
    echo "Is this an AAHP project? Run from the project root or pass the path."
    exit 1
fi

CHANGES=()

# --- Step 1: Add a Provenance section to TRUST.md ----------------------------

echo -e "${GREEN}[1/3]${NC} Checking TRUST.md for a Provenance section..."

if [ -f "$HANDOFF_DIR/TRUST.md" ]; then
    if ! grep -q "## Provenance" "$HANDOFF_DIR/TRUST.md"; then
        cat >> "$HANDOFF_DIR/TRUST.md" <<'PROVENANCE'

---

## Provenance (Draft v0.1, proposed)

The Grounded Reflection Layer adds an orthogonal *provenance* field recording HOW a
claim was checked, separate from the Status above. Provenance tokens, weakest to
strongest: `model_claim`, `self_reviewed`, `cross_model_reviewed`, `source_verified`,
`tool_verified`, `test_verified`, `runtime_observed`, `human_confirmed`.
`cross_model_reviewed` maps to status `assumed`, never `verified`; only
`source_verified` / `tool_verified` / `test_verified` / `runtime_observed` /
`human_confirmed` can support `verified` (grounded). To record it in this register, add
a `Provenance` column to the tables above and use `-` when it is unknown. TTL and expiry
stay governed by the Trust Decay rule (README section 2.5). See GROUNDING.md for the anchor
matrix and README section 2.10 for the doctrine.
PROVENANCE
        CHANGES+=("Added a Provenance section to TRUST.md")
        echo "  -> Provenance section added."
    else
        echo "  -> Provenance already present. Skipping."
    fi
else
    echo -e "${YELLOW}  -> TRUST.md not found. Skipping.${NC}"
fi

# --- Step 2: Copy GROUNDING.md if missing ------------------------------------

echo -e "${GREEN}[2/3]${NC} Checking for .ai/handoff/GROUNDING.md..."

if [ ! -f "$HANDOFF_DIR/GROUNDING.md" ]; then
    if [ -f "$REPO_ROOT/templates/GROUNDING.md" ]; then
        cp "$REPO_ROOT/templates/GROUNDING.md" "$HANDOFF_DIR/GROUNDING.md"
        CHANGES+=("Copied GROUNDING.md template")
        echo "  -> Copied GROUNDING.md."
    else
        echo -e "${RED}Error: template not found at $REPO_ROOT/templates/GROUNDING.md${NC}"
        echo "The aahp package looks incomplete. Aborting to avoid a partial migration."
        exit 1
    fi
else
    echo "  -> GROUNDING.md already present (left untouched)."
fi

# --- Step 3: Regenerate MANIFEST.json ----------------------------------------

echo -e "${GREEN}[3/3]${NC} Regenerating MANIFEST.json..."

if [ -f "$HANDOFF_DIR/MANIFEST.json" ]; then
    bash "$SCRIPT_DIR/aahp-manifest.sh" "$PROJECT_ROOT" \
        --agent "grounding-migration" \
        --session-id "ground-$(date +%s)" \
        --phase fix \
        --quiet
    CHANGES+=("Regenerated MANIFEST.json (indexes GROUNDING.md, re-checksums TRUST.md)")
    echo "  -> MANIFEST.json regenerated."
else
    echo -e "${YELLOW}  -> No MANIFEST.json found. Run 'aahp manifest' after this.${NC}"
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "========================================="
echo "  Migration Summary"
echo "========================================="
echo ""

if [ ${#CHANGES[@]} -eq 0 ]; then
    echo -e "${GREEN}No changes needed. Grounded Reflection Layer already present.${NC}"
else
    for change in "${CHANGES[@]}"; do
        echo -e "  ${GREEN}[ok]${NC} $change"
    done
    echo ""
    echo "Next steps:"
    echo "  1. Review the Provenance section in TRUST.md and .ai/handoff/GROUNDING.md"
    echo "  2. Read README section 2.10 for the Grounded Reflection doctrine"
    echo "  3. Commit: git add .ai/handoff/ && git commit -m 'feat(grounding): adopt Grounded Reflection Layer'"
fi

echo ""
