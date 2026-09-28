#!/usr/bin/env bats
# install-hooks.bats - where install-hooks.sh puts the hooks, and whether git
# then runs them.
#
# "Installed" is asserted as the property that matters: git EXECUTES the hook.
# In a repository with neither a vendored gate nor a local package, the
# installed pre-commit prints a fixed skip line and exits 0, so that line
# appearing on a real `git commit` proves git ran the file this script wrote.
# A hook written to a directory git never reads (the linked-worktree defect)
# passes every file-existence check and prints nothing here, which is why the
# existence checks alone were never enough.

setup() {
    load test_helper
    setup
    INSTALL="$AAHP_ROOT/scripts/install-hooks.sh"
    SKIP_LINE="AAHP pre-commit: no verify-handoff.sh and no locally installed aahp package"
}

teardown() {
    teardown
}

# Commit in $1 so its pre-commit hook runs; git's output lands in $output.
commit_in() {
    run git -C "$1" commit --allow-empty -q -m "probe"
}

# The bytes install-hooks.sh must have written for hook $1: the source, minus CR.
expected_hook() {
    tr -d '\r' < "$AAHP_ROOT/scripts/hooks/$1" > "$TEST_TMPDIR/expected-$1"
    printf '%s' "$TEST_TMPDIR/expected-$1"
}

@test "fresh repo: both hooks land in .git/hooks, executable, and git runs them" {
    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    local h
    for h in pre-commit pre-push; do
        [ -x "$TEST_TMPDIR/.git/hooks/$h" ]
        cmp "$(expected_hook "$h")" "$TEST_TMPDIR/.git/hooks/$h"
        [ ! -e "$TEST_TMPDIR/.git/hooks/$h.pre-aahp.bak" ]
    done

    commit_in "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SKIP_LINE"* ]]
}

@test "an existing foreign hook is backed up byte-for-byte, and a re-run does not touch the backup" {
    mkdir -p "$TEST_TMPDIR/.git/hooks"
    printf '#!/bin/sh\n# team hook, not ours\necho foreign-hook-ran\n' > "$TEST_TMPDIR/.git/hooks/pre-commit"
    chmod +x "$TEST_TMPDIR/.git/hooks/pre-commit"
    cp -p "$TEST_TMPDIR/.git/hooks/pre-commit" "$TEST_TMPDIR/original-pre-commit"

    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"backed up existing pre-commit to pre-commit.pre-aahp.bak"* ]]
    cmp "$TEST_TMPDIR/original-pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak"
    [ -x "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak" ]
    grep -q "AAHP pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit"

    # Our own hook is not "foreign": a second run makes no second backup.
    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"backed up"* ]]
    [ ! -e "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak.1" ]
    cmp "$TEST_TMPDIR/original-pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak"
}

@test "a second, different foreign hook never overwrites the first backup" {
    mkdir -p "$TEST_TMPDIR/.git/hooks"
    printf '#!/bin/sh\necho first-foreign\n' > "$TEST_TMPDIR/first"
    printf '#!/bin/sh\necho second-foreign\n' > "$TEST_TMPDIR/second"

    cp "$TEST_TMPDIR/first" "$TEST_TMPDIR/.git/hooks/pre-commit"
    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]

    # Something replaces our hook with another foreign one; install again.
    cp "$TEST_TMPDIR/second" "$TEST_TMPDIR/.git/hooks/pre-commit"
    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"to pre-commit.pre-aahp.bak.1"* ]]
    cmp "$TEST_TMPDIR/first" "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak"
    cmp "$TEST_TMPDIR/second" "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak.1"
}

@test "a symlinked foreign hook is replaced, never written through into the file it points at" {
    # Hook managers commonly symlink .git/hooks/<name> to a tracked script. A
    # plain `cp` over that link would overwrite the tracked script itself.
    mkdir -p "$TEST_TMPDIR/.git/hooks" "$TEST_TMPDIR/tools"
    printf '#!/bin/sh\necho team-script\n' > "$TEST_TMPDIR/tools/team-pre-commit"
    cp -p "$TEST_TMPDIR/tools/team-pre-commit" "$TEST_TMPDIR/original-team"
    ln -s "$TEST_TMPDIR/tools/team-pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit"
    # Git Bash without symlink support makes `ln -s` a copy; nothing to test then.
    [ -L "$TEST_TMPDIR/.git/hooks/pre-commit" ] || skip "ln -s did not create a symlink on this platform"

    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # The link target is untouched, the hook is now a regular AAHP file, and
    # the backup holds what the link resolved to.
    cmp "$TEST_TMPDIR/original-team" "$TEST_TMPDIR/tools/team-pre-commit"
    [ ! -L "$TEST_TMPDIR/.git/hooks/pre-commit" ]
    grep -q "AAHP pre-commit" "$TEST_TMPDIR/.git/hooks/pre-commit"
    cmp "$TEST_TMPDIR/original-team" "$TEST_TMPDIR/.git/hooks/pre-commit.pre-aahp.bak"
}

@test "relative core.hooksPath: the hooks land where git runs them, not in .git/hooks" {
    git -C "$TEST_TMPDIR" config core.hooksPath .githooks
    run bash "$INSTALL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -x "$TEST_TMPDIR/.githooks/pre-commit" ]
    [ -x "$TEST_TMPDIR/.githooks/pre-push" ]
    [ ! -e "$TEST_TMPDIR/.git/hooks/pre-commit" ]

    commit_in "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SKIP_LINE"* ]]
}

@test "relative core.hooksPath, target named by a subdirectory: resolved against the work tree root" {
    # git resolves a relative core.hooksPath against the root of the work tree it
    # runs the hook in. Joining it onto the path the caller typed put the hooks
    # in <subdir>/.githooks, where git never looks.
    mkdir -p "$TEST_TMPDIR/pkg"
    git -C "$TEST_TMPDIR" config core.hooksPath .githooks
    run bash "$INSTALL" "$TEST_TMPDIR/pkg"
    [ "$status" -eq 0 ]
    [ -x "$TEST_TMPDIR/.githooks/pre-commit" ]
    [ ! -e "$TEST_TMPDIR/pkg/.githooks" ]

    commit_in "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SKIP_LINE"* ]]
}

@test "linked worktree: the hooks land in the common hooks directory, and git runs them there" {
    git -C "$TEST_TMPDIR" worktree add -q "$TEST_TMPDIR/wt" -b wt-branch
    # Precondition: this is the shape the defect needs, a .git FILE.
    [ -f "$TEST_TMPDIR/wt/.git" ]

    run bash "$INSTALL" "$TEST_TMPDIR/wt"
    [ "$status" -eq 0 ]
    [ -x "$TEST_TMPDIR/.git/hooks/pre-commit" ]
    [ ! -e "$TEST_TMPDIR/.git/worktrees/wt/hooks/pre-commit" ]

    commit_in "$TEST_TMPDIR/wt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SKIP_LINE"* ]]
}

@test "a CRLF source hook is installed LF, and Linux bash can run it" {
    # A Windows checkout with core.autocrlf produces exactly this source tree.
    local src="$TEST_TMPDIR/crlf-src/scripts" h
    mkdir -p "$src/hooks"
    cp "$INSTALL" "$src/install-hooks.sh"
    for h in pre-commit pre-push; do
        awk '{ printf "%s\r\n", $0 }' "$AAHP_ROOT/scripts/hooks/$h" > "$src/hooks/$h"
    done
    # Precondition: the source really is CRLF, or this test proves nothing.
    run grep -c $'\r' "$src/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]

    run bash "$src/install-hooks.sh" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    for h in pre-commit pre-push; do
        run grep -c $'\r' "$TEST_TMPDIR/.git/hooks/$h"
        [ "$status" -eq 1 ]
    done

    commit_in "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SKIP_LINE"* ]]
}

@test "a directory that is not a git repository is refused, exit 1" {
    local outside
    outside="$(_make_tmpdir)"
    run bash "$INSTALL" "$outside"
    rm -rf "$outside"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a git repository"* ]]
}

@test ".gitattributes checks every hook out LF, since *.sh does not match an extensionless file" {
    local files f n=0
    files="$(git -C "$AAHP_ROOT" ls-files scripts/hooks)"
    [ -n "$files" ]
    for f in $files; do
        run git -C "$AAHP_ROOT" check-attr eol -- "$f"
        [ "$status" -eq 0 ]
        [[ "$output" == *": eol: lf" ]]
        n=$((n + 1))
    done
    # Both shipped hooks were examined, not zero of them.
    [ "$n" -ge 2 ]
}
