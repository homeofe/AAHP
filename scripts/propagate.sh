#!/usr/bin/env bash
# propagate.sh - Sync the canonical AAHP verify gate into a target repo.
#
# Copies the gate files from THIS AAHP checkout into <target-repo>, installs the
# git hooks, stamps STATUS.md, regenerates MANIFEST.json, stages the change set,
# and verifies a clean baseline. The caller commits + pushes, so the commit
# message and push stay under human/agent control.
#
# Usage: bash scripts/propagate.sh <path-to-target-repo>
#
# Exit codes:
#   0 = synced, staged, and verified (ready to commit)
#   2 = target has no .ai/handoff (run `aahp init` there first)
#   1 = other error
set -euo pipefail

AAHP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_IN="${1:?usage: propagate.sh <path-to-target-repo>}"
TARGET="$(cd "$TARGET_IN" && pwd)"

[ -d "$TARGET/.git" ] || { echo "Error: not a git repo: $TARGET" >&2; exit 1; }
if [ ! -d "$TARGET/.ai/handoff" ]; then
    echo "Error: $TARGET has no .ai/handoff. Run 'aahp init' there first, then re-run." >&2
    exit 2
fi

VERSION="$(grep -m1 '"version"' "$AAHP_DIR/package.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
TODAY="$(date -u +%Y-%m-%d)"
echo "==> Syncing AAHP gate v$VERSION into $TARGET"

# 1. Copy the canonical gate files (refresh lib/lint/manifest, add verify/hooks/CI).
mkdir -p "$TARGET/scripts/hooks" "$TARGET/.github/workflows"
for f in verify-handoff.sh _aahp-lib.sh lint-handoff.sh aahp-manifest.sh install-hooks.sh; do
    cp "$AAHP_DIR/scripts/$f" "$TARGET/scripts/$f"
done
cp "$AAHP_DIR/scripts/hooks/pre-commit" "$TARGET/scripts/hooks/pre-commit"
cp "$AAHP_DIR/scripts/hooks/pre-push" "$TARGET/scripts/hooks/pre-push"
cp "$AAHP_DIR/.github/workflows/aahp-verify.yml" "$TARGET/.github/workflows/aahp-verify.yml"

# 2. Install the local pre-commit + pre-push hooks.
bash "$TARGET/scripts/install-hooks.sh" "$TARGET"

# 3. Stamp STATUS.md so the content-drift gate sees handoff state move with the code.
STATUS="$TARGET/.ai/handoff/STATUS.md"
if [ -f "$STATUS" ] && ! grep -q "AAHP verify gate: v$VERSION" "$STATUS"; then
    printf '\n<!-- aahp-gate -->\n_AAHP verify gate: v%s synced %s._\n' "$VERSION" "$TODAY" >> "$STATUS"
fi

# 4. Regenerate MANIFEST.json (clean baseline incl. the stamped STATUS.md).
bash "$TARGET/scripts/aahp-manifest.sh" "$TARGET" --phase fix --quiet

# 5. Stage just the gate files + the handoff state that moved with them.
git -C "$TARGET" add \
    scripts/verify-handoff.sh scripts/_aahp-lib.sh scripts/lint-handoff.sh \
    scripts/aahp-manifest.sh scripts/install-hooks.sh \
    scripts/hooks/pre-commit scripts/hooks/pre-push \
    .github/workflows/aahp-verify.yml \
    .ai/handoff/STATUS.md .ai/handoff/MANIFEST.json

# 6. Verify a clean baseline against the staged set.
bash "$TARGET/scripts/verify-handoff.sh" "$TARGET" --level precommit

echo "==> Done. AAHP gate v$VERSION staged in $TARGET. Commit + push to finish."
