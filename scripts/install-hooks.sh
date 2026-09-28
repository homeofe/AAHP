#!/usr/bin/env bash
# install-hooks.sh - Install the AAHP git hooks (pre-commit + pre-push) into a
# target repository so the canonical "aahp verify" gate runs locally.
#
# Usage: ./scripts/install-hooks.sh [path-to-target-repo]
#        Defaults to the repo this script lives in.
#
# What it does:
#   - Copies scripts/hooks/pre-commit and scripts/hooks/pre-push into the
#     directory git actually runs hooks from, as `git rev-parse --git-path
#     hooks` reports it. That honours core.hooksPath (relative, absolute or
#     `~/`), and in a linked worktree it is the COMMON hooks directory. An
#     earlier version used `$(git rev-parse --git-dir)/hooks`, which in a linked
#     worktree is .git/worktrees/<name>/hooks: git never runs anything from
#     there, so the hooks were installed, reported as installed, and inert.
#   - Strips CR while copying, so a CRLF checkout (Windows, core.autocrlf)
#     cannot install a hook that Linux bash rejects.
#   - Makes them executable.
#   - Does NOT overwrite a non-AAHP hook without backing it up first, and never
#     overwrites an earlier backup: a second foreign hook goes to
#     <hook>.pre-aahp.bak.1, .2, and so on.
#
# The hooks resolve the "aahp verify" gate two ways: they prefer the vendored
# <target>/scripts/verify-handoff.sh when it is present (a full AAHP checkout
# that also ships scripts/_aahp-lib.sh + lint-handoff.sh via AAHP propagation),
# and otherwise fall back to the locally installed package at
# <target>/node_modules/@elvatis_com/aahp/bin/aahp.js. So a consumer that only
# "npm install"ed @elvatis_com/aahp no longer needs a full AAHP checkout for the
# hooks to work. When neither resolves the hooks SKIP, and that skip is now a
# filesystem test rather than an `npx` invocation, so it costs no network call
# and cannot execute a package resolved from the public registry.
#
# A GLOBAL install (`npm i -g @elvatis_com/aahp`) is deliberately not one of the
# two: the hooks never search PATH. A repository whose only aahp is global gets
# a one-line skip on stderr at every commit and push, exits 0, and is gated by
# nothing but CI. Install the package as a devDependency of the repository.
#
# If the hooks already in your .git/hooks/ still contain `npx`, re-run this
# script: those copies are what execute, and fixing the sources here does not
# fix them.
#
# Exit codes:
#   0 = hooks installed
#   1 = error (not a git repo, source hooks missing, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_HOOKS="$SCRIPT_DIR/hooks"

TARGET="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [ ! -d "$SRC_HOOKS" ]; then
    echo "Error: source hooks dir not found: $SRC_HOOKS" >&2
    exit 1
fi

if ! git -C "$TARGET" rev-parse --git-dir &>/dev/null 2>&1; then
    echo "Error: $TARGET is not a git repository." >&2
    exit 1
fi

# Ask git where it runs hooks from, instead of reconstructing the answer.
# `--git-path hooks` applies core.hooksPath (and resolves a relative value the
# way git does when it runs a hook), and maps a linked worktree onto the common
# directory. A relative answer is relative to the directory `-C` named.
HOOKS_DIR=$(git -C "$TARGET" rev-parse --git-path hooks)
case "$HOOKS_DIR" in
    /* | [A-Za-z]:*) : ;;  # POSIX-absolute or Windows drive-letter (C:/...) path
    *) HOOKS_DIR="$TARGET/$HOOKS_DIR" ;;
esac

mkdir -p "$HOOKS_DIR"

install_one() {
    local name="$1"
    local src="$SRC_HOOKS/$name"
    local dest="$HOOKS_DIR/$name"

    if [ ! -f "$src" ]; then
        echo "  skip: $name (source missing)" >&2
        return 0
    fi

    # If an existing hook is present and is NOT an AAHP hook, back it up. An
    # identical backup is already a backup; a different one is someone else's
    # hook from an earlier run and is never overwritten.
    if [ -f "$dest" ] && ! grep -q "AAHP pre-" "$dest" 2>/dev/null; then
        local bak="$dest.pre-aahp.bak" n=0
        while [ -e "$bak" ] && ! cmp -s "$dest" "$bak"; do
            n=$((n + 1))
            bak="$dest.pre-aahp.bak.$n"
        done
        if [ ! -e "$bak" ]; then
            cp -p "$dest" "$bak"
        fi
        echo "  note: backed up existing $name to ${bak##*/}"
    fi

    # `tr -d '\r'`, not `cp`: see the header. The hooks are bash scripts, and a
    # carriage return is never meaningful in one. The old hook is removed first
    # (it is backed up above when it is not ours), so a symlinked hook is
    # replaced rather than written through, into whatever file it points at.
    rm -f "$dest"
    tr -d '\r' < "$src" > "$dest"
    chmod +x "$dest"
    echo "  installed: $name"
}

echo "Installing AAHP hooks into: $HOOKS_DIR"
install_one "pre-commit"
install_one "pre-push"
echo "Done. The 'aahp verify' gate now runs on commit (fast) and push (full)."
echo "Escape hatch: AAHP_SKIP_VERIFY=1 (caught by the required CI check; do NOT use to bypass CI)."
