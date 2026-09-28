#!/usr/bin/env bash
# propagate.sh - Sync the canonical AAHP verify gate into a target repo.
#
# Copies the gate from THIS AAHP tree (a checkout, or the installed package at
# node_modules/@elvatis_com/aahp) into <target-repo>: the gate scripts AND every
# file they execute, the git hooks, and the canonical consumer CI workflow. It
# then installs the hooks, stamps STATUS.md, regenerates MANIFEST.json, stages
# the change set, and verifies the staged baseline. The caller commits + pushes,
# so the commit message and push stay under human/agent control.
#
# The CI workflow is assets/governance/aahp-verify.yml, installed as
# .github/workflows/aahp-verify.yml. It runs the @elvatis_com/aahp dependency
# that `npm ci` places from the target's lockfile, so the target must declare
# that dependency and track a package-lock.json that locks it. That is checked
# BEFORE anything is written, and a target that fails it is refused (exit 3),
# because the workflow would otherwise fail on its first run. Earlier versions
# copied AAHP's own .github/workflows/aahp-verify.yml instead, whose
# `node bin/aahp.js` exists only in an AAHP checkout, so the CI of every
# propagated repository died with MODULE_NOT_FOUND.
#
# Usage: bash scripts/propagate.sh <path-to-target-repo>
#
# Exit codes:
#   0 = synced, staged, and the staged baseline passed `verify --level precommit`
#   1 = other error, INCLUDING a staged baseline that does not pass. Nothing is
#       committed; the change set stays staged so the failure can be inspected.
#   2 = target has no .ai/handoff (run `aahp init` there first)
#   3 = target cannot run the CI workflow: package.json declares no
#       @elvatis_com/aahp dependency, or no package-lock.json in the git index
#       locks it
set -euo pipefail

AAHP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_IN="${1:?usage: propagate.sh <path-to-target-repo>}"
TARGET="$(cd "$TARGET_IN" && pwd)"

die() {
    local code="$1"
    shift
    echo "Error: $*" >&2
    exit "$code"
}

# The gate and everything it executes. verify-handoff.sh sources _aahp-lib.sh
# and runs lint-handoff.sh; lint-handoff.sh runs check-conflict-markers.mjs and
# validate-pii-allowlist.py. Leaving one of those two out does not fail loudly:
# node's MODULE_NOT_FOUND exits 1, lint reads exit 1 as "conflict markers
# found", and every commit in the target then failed its hook for a reason that
# was not true. The closure check after the copy re-derives this list from the
# scripts themselves, so a helper added to a script later cannot be missed here.
VENDORED_SCRIPTS=(
    verify-handoff.sh
    _aahp-lib.sh
    lint-handoff.sh
    check-conflict-markers.mjs
    validate-pii-allowlist.py
    aahp-manifest.sh
    install-hooks.sh
)
HOOKS=(pre-commit pre-push)
WORKFLOW_SRC="assets/governance/aahp-verify.yml"
WORKFLOW_DEST=".github/workflows/aahp-verify.yml"

# --- 0. Preconditions. Nothing below writes until all of them hold. ----------

# The target must be the top level of a git work tree. A linked worktree, whose
# .git is a FILE, is one; an earlier `[ -d "$TARGET/.git" ]` refused it.
if [ "$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then
    die 1 "not a git work tree: $TARGET"
fi
PREFIX="$(git -C "$TARGET" rev-parse --show-prefix)"
if [ -n "$PREFIX" ]; then
    die 1 "$TARGET is the subdirectory '$PREFIX' of a git work tree. Run propagate on the repository root; the workflow has to land in the root's .github/workflows/."
fi
if [ ! -d "$TARGET/.ai/handoff" ]; then
    die 2 "$TARGET has no .ai/handoff. Run 'aahp init' there first, then re-run."
fi

command -v node >/dev/null 2>&1 \
    || die 1 "node is required: the vendored conflict-marker check and the CI workflow both run on it."

for f in "${VENDORED_SCRIPTS[@]}"; do
    [ -f "$AAHP_DIR/scripts/$f" ] || die 1 "this AAHP tree is incomplete: scripts/$f is missing from $AAHP_DIR"
done
for h in "${HOOKS[@]}"; do
    [ -f "$AAHP_DIR/scripts/hooks/$h" ] || die 1 "this AAHP tree is incomplete: scripts/hooks/$h is missing from $AAHP_DIR"
done
[ -f "$AAHP_DIR/$WORKFLOW_SRC" ] || die 1 "this AAHP tree is incomplete: $WORKFLOW_SRC is missing from $AAHP_DIR"

# Read with node from inside each directory, so no path has to cross the
# Git Bash / native-node boundary.
PKG_NAME="$(cd "$AAHP_DIR" && node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync("package.json", "utf8")).name)')"
VERSION="$(cd "$AAHP_DIR" && node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync("package.json", "utf8")).version)')"

# The workflow runs `npm ci --ignore-scripts` and then the CLI by its path in
# node_modules. Both need the dependency declared AND locked; the lockfile
# version is what CI will run.
LOCKED_VERSION="$(cd "$TARGET" && node -e '
const fs = require("fs");
const name = process.argv[1];
const fail = (why) => { process.stderr.write("  " + why + "\n"); process.exit(3); };
let pkg;
let lock;
try { pkg = JSON.parse(fs.readFileSync("package.json", "utf8")); }
catch (e) { fail("no readable package.json (" + e.code + ")"); }
const declared = (pkg.devDependencies || {})[name] || (pkg.dependencies || {})[name];
if (typeof declared !== "string") fail("package.json declares no " + name + " dependency");
try { lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8")); }
catch (e) { fail("no readable package-lock.json (" + e.code + ")"); }
const entry = (lock.packages || {})["node_modules/" + name] || (lock.dependencies || {})[name];
if (!entry || typeof entry.version !== "string") fail("package-lock.json does not lock " + name);
process.stdout.write(entry.version);
' "$PKG_NAME")" || die 3 "$TARGET cannot run the CI workflow propagate installs. It executes $PKG_NAME from node_modules after 'npm ci', so declare and lock it first:
  (cd \"$TARGET\" && npm install --save-dev --save-exact $PKG_NAME@$VERSION)
then commit package.json and package-lock.json and re-run."

for f in package.json package-lock.json; do
    git -C "$TARGET" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 \
        || die 3 "$f is not in the git index of $TARGET. The workflow's checkout sees only committed files, so 'npm ci' would fail there. git add it, then re-run."
done

TODAY="$(date -u +%Y-%m-%d)"
echo "==> Syncing AAHP gate v$VERSION into $TARGET"
if [ "$LOCKED_VERSION" != "$VERSION" ]; then
    echo "==> NOTE: $TARGET locks $PKG_NAME $LOCKED_VERSION. CI will run $LOCKED_VERSION while the hooks run the vendored $VERSION."
    echo "    To align them: npm install --save-dev --save-exact $PKG_NAME@$VERSION"
fi

# --- 1. Copy the gate, its closure, the hooks and the consumer workflow. -----
mkdir -p "$TARGET/scripts/hooks" "$TARGET/.github/workflows"
STAGE=()
for f in "${VENDORED_SCRIPTS[@]}"; do
    cp "$AAHP_DIR/scripts/$f" "$TARGET/scripts/$f"
    STAGE+=("scripts/$f")
done
for h in "${HOOKS[@]}"; do
    cp "$AAHP_DIR/scripts/hooks/$h" "$TARGET/scripts/hooks/$h"
    STAGE+=("scripts/hooks/$h")
done
cp "$AAHP_DIR/$WORKFLOW_SRC" "$TARGET/$WORKFLOW_DEST"
STAGE+=("$WORKFLOW_DEST")

# Closure check: every sibling file a vendored script names must now exist next
# to it. Shell scripts name siblings as $SCRIPT_DIR/<file>; ES modules import
# them as "./<file>". Anything found and not copied is a propagation that would
# pass here and fail at the target's first commit.
MISSING=""
for f in "${VENDORED_SCRIPTS[@]}"; do
    case "$f" in
        *.mjs) deps="$({ grep -oE "[\"']\./[A-Za-z0-9_.-]+[\"']" "$TARGET/scripts/$f" || true; } | tr -d "\"'" | sed 's|^\./||' | sort -u)" ;;
        *) deps="$({ grep -oE '\$\{?SCRIPT_DIR\}?/[A-Za-z0-9_.-]+' "$TARGET/scripts/$f" || true; } | sed -E 's|^\$\{?SCRIPT_DIR\}?/||' | sort -u)" ;;
    esac
    for dep in $deps; do
        [ -e "$TARGET/scripts/$dep" ] || MISSING="$MISSING scripts/$dep (named by scripts/$f)"
    done
done
[ -z "$MISSING" ] || die 1 "the vendored gate names files this propagation did not copy:$MISSING"

# --- 2. Install the local pre-commit + pre-push hooks. -----------------------
bash "$TARGET/scripts/install-hooks.sh" "$TARGET"

# --- 3. Stamp STATUS.md so the content-drift gate sees handoff state move. ---
STATUS="$TARGET/.ai/handoff/STATUS.md"
if [ -f "$STATUS" ] && ! grep -q "AAHP verify gate: v$VERSION" "$STATUS"; then
    printf '\n<!-- aahp-gate -->\n_AAHP verify gate: v%s synced %s._\n' "$VERSION" "$TODAY" >> "$STATUS"
fi

# --- 4. Regenerate MANIFEST.json (clean baseline incl. the stamped STATUS.md).
bash "$TARGET/scripts/aahp-manifest.sh" "$TARGET" --phase fix --quiet

# --- 5. Stage the gate files + the WHOLE .ai/handoff dir. Staging all of
#    .ai/handoff (not just STATUS + MANIFEST) keeps the committed handoff
#    consistent with the regenerated manifest even when the repo had
#    uncommitted handoff edits. Otherwise the manifest checksums a worktree
#    file the commit never includes, and CI fails with a checksum mismatch.
git -C "$TARGET" add -- "${STAGE[@]}" .ai/handoff

# --- 6. Verify the staged baseline. FATAL: exit 0 promises a verified change
#    set, so a baseline that fails is a failed propagation, not a note. The
#    escape hatch is cleared for this one call: it is honoured at precommit
#    level, and a caller's AAHP_SKIP_VERIFY=1 must not turn this into a pass.
if ! AAHP_SKIP_VERIFY=0 bash "$TARGET/scripts/verify-handoff.sh" "$TARGET" --level precommit; then
    die 1 "the staged baseline in $TARGET does not pass 'verify --level precommit' (output above). Nothing was committed; the change set is left staged for inspection."
fi

echo "==> Done. AAHP gate v$VERSION staged and verified in $TARGET. Commit + push to finish."
