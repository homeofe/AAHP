#!/usr/bin/env bats
# ascii.bats - scripts/check-ascii.mjs, the full-ASCII gate (owner decision
# 2026-09-28): every tracked text file is pure ASCII, no code point above U+007F
# and no byte order mark.
#
# Every non-ASCII input below is generated at runtime with octal printf
# (\303\251 is U+00E9, \342\200\224 is U+2014, \357\273\277 is the UTF-8 BOM,
# \360\237\232\200 is U+1F680), so this file is itself pure ASCII and passes the
# gate it tests. Exit codes are asserted by number, never as "non-zero": "could
# not assess" (2) is a different answer from "assessed and found a problem" (1),
# and a test that accepted either would not notice them swapping.

load test_helper

GATE="$SCRIPTS_DIR/check-ascii.mjs"

# Write $2 (printf format, octal escapes allowed) to $1 under TEST_TMPDIR and
# track it. Tracked-ness is `git add`: the gate reads the index, not commits.
put() {
    mkdir -p "$(dirname "$TEST_TMPDIR/$1")"
    printf "$2" > "$TEST_TMPDIR/$1"
    git -C "$TEST_TMPDIR" add -- "$1"
}

# Count the bytes above 0x7F on stdin.
high_bytes() {
    node -e 'let n = 0; for (const b of require("fs").readFileSync(0)) if (b > 127) n++; process.stdout.write(String(n))'
}

# --- control: a clean tree is green --------------------------------------------

@test "ascii CONTROL: a tree of ASCII files passes and says how many it read" {
    put README.md '# Fixture\n\nplain text, a hyphen - and a comma.\n'
    put scripts/run.sh '#!/usr/bin/env bash\necho ok\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASCII OK: 2 tracked text file(s) are pure ASCII."* ]]
}

# --- findings: file:line:column and the code point ------------------------------

@test "ascii: one non-ASCII character is exit 1, located by line and column" {
    put doc.md 'line one\ncaf\303\251 two\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"doc.md:2:4 U+00E9"* ]]
    [[ "$output" == *"1 non-ASCII code point(s) in 1 tracked file(s)"* ]]
}

@test "ascii: columns count code points and survive CRLF line endings" {
    # Two non-ASCII characters before the target on the same line: a byte
    # column would say 9, a UTF-16 column would say 8 for the astral one.
    put crlf.txt 'ab\r\n\303\251\360\237\232\200x\342\200\224\r\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"crlf.txt:2:1 U+00E9"* ]]
    [[ "$output" == *"crlf.txt:2:2 U+1F680"* ]]
    [[ "$output" == *"crlf.txt:2:4 U+2014"* ]]
    [[ "$output" == *"crlf.txt: 3"* ]]
}

@test "ascii: an em dash is a finding, so the gate subsumes the old U+2014 rule" {
    put doc.md 'a \342\200\224 b\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"doc.md:1:3 U+2014"* ]]
}

@test "ascii: a UTF-8 byte order mark is a finding at 1:1" {
    # TextDecoder drops a leading BOM unless told not to. Anchor: ignoreBOM: true
    # in scripts/check-ascii.mjs. Without it this file decodes to plain ASCII.
    put bom.json '\357\273\277{ "a": 1 }\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bom.json:1:1 U+FEFF (byte order mark)"* ]]
}

@test "ascii: bytes that are not valid UTF-8 are findings, reported as bytes" {
    put latin1.txt 'caf\351\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"latin1.txt:1:4 byte 0xE9 (not valid UTF-8)"* ]]
}

@test "ascii: the listing is capped per file but the count is exact" {
    put many.txt "$(printf '\342\206\222%.0s' $(seq 1 25))\n"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"many.txt: 25"* ]]
    [[ "$output" == *"many.txt:1:20 U+2192"* ]]
    [[ "$output" == *"... and 5 more in this file"* ]]
}

@test "ascii: the gate's own output is ASCII, even for a non-ASCII file name" {
    put "caf$(printf '\303\251').md" 'x\342\200\224\n'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *'caf\u{E9}.md:1:2 U+2014'* ]]
    run high_bytes <<<"$output"
    [ "$output" = "0" ]
    # Control: the counter does see high bytes, so the 0 above is a measurement.
    run high_bytes <<<"caf$(printf '\303\251')"
    [ "$output" = "2" ]
}

# --- scope: tracked text files only ----------------------------------------------

@test "ascii: a binary file (NUL byte) is exempt and named as exempt" {
    put README.md '# ok\n'
    put assets/logo.png 'PNG\000\303\251\377'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 binary file(s) exempt (NUL byte): assets/logo.png"* ]]
}

@test "ascii: the binary exemption is the NUL byte, not the extension" {
    # Control for the test above: the same bytes without the NUL are text, so
    # a gate that skipped by name or extension would pass here and must not.
    put README.md '# ok\n'
    put assets/logo.png 'PNG\303\251'
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"assets/logo.png:1:4 U+00E9"* ]]
}

@test "ascii: an untracked file is not read, and the same file once added is" {
    put README.md '# ok\n'
    printf 'scratch \342\200\224 note\n' > "$TEST_TMPDIR/notes.txt"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASCII OK: 1 tracked text file(s)"* ]]
    git -C "$TEST_TMPDIR" add notes.txt
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"notes.txt:1:9 U+2014"* ]]
}

@test "ascii: a tracked symlink is checked as its link text" {
    put README.md '# ok\n'
    ln -s "caf$(printf '\303\251').md" "$TEST_TMPDIR/link.md" 2>/dev/null || true
    require_tool "requires filesystem symlink support" [ -L "$TEST_TMPDIR/link.md" ]
    git -C "$TEST_TMPDIR" add link.md
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"link.md:1:4 U+00E9"* ]]
}

@test "ascii: --path narrows the scan to a pathspec" {
    put scripts/ok.sh 'echo ok\n'
    put docs/bad.md 'a \342\200\224 b\n'
    run node "$GATE" "$TEST_TMPDIR" --path=scripts
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASCII OK: 1 tracked text file(s) matching scripts are pure ASCII."* ]]
    run node "$GATE" "$TEST_TMPDIR" --path=scripts --path=docs
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/bad.md:1:3 U+2014"* ]]
}

# --- could not assess is exit 2, and is never a pass -------------------------------

@test "ascii: outside a git work tree is exit 2" {
    put README.md '# ok\n'
    rm -rf "$TEST_TMPDIR/.git"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not inside a git work tree"* ]]
}

@test "ascii: git missing is exit 2" {
    put README.md '# ok\n'
    local node_bin
    node_bin="$(command -v node)"
    mkdir -p "$TEST_TMPDIR/empty-path"
    # Control: the same invocation with git reachable is green.
    run env PATH="$PATH" "$node_bin" "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run env PATH="$TEST_TMPDIR/empty-path" "$node_bin" "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"git could not be run"* ]]
}

@test "ascii: nothing tracked is exit 2, not a vacuous pass" {
    printf 'untracked\n' > "$TEST_TMPDIR/a.txt"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"enumerated nothing"* ]]
}

@test "ascii: a --path that matches nothing is exit 2" {
    put README.md '# ok\n'
    run node "$GATE" "$TEST_TMPDIR" --path=no-such-dir
    [ "$status" -eq 2 ]
    [[ "$output" == *"no tracked file matches no-such-dir"* ]]
}

@test "ascii: a tracked file missing from the working tree is exit 2" {
    put README.md '# ok\n'
    put gone.md 'text\n'
    rm "$TEST_TMPDIR/gone.md"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"gone.md: tracked but missing from the working tree"* ]]
}

@test "ascii: a finding wins over an unread file (exit 1, both reported)" {
    put gone.md 'text\n'
    put bad.md '\342\200\224\n'
    rm "$TEST_TMPDIR/gone.md"
    run node "$GATE" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.md:1:1 U+2014"* ]]
    [[ "$output" == *"gone.md: tracked but missing from the working tree"* ]]
}

@test "ascii: an unknown argument is exit 2" {
    put README.md '# ok\n'
    run node "$GATE" "$TEST_TMPDIR" --exclude=README.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown argument --exclude=README.md"* ]]
}

# --- the gate has to actually RUN, over the whole tree ------------------------------

@test "ascii: the gate is wired into the aggregate check chain with no filter" {
    run node "$AAHP_ROOT/tests/assert-ascii-gate-wired.mjs" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ascii gate wiring OK"* ]]
}

# Red controls for the wiring assertion. Each mutates ONE field of a copy of the
# real package.json via node on parsed JSON, proves it landed, and expects exit 1.
ascii_wiring_mutate() {
    cp "$AAHP_ROOT/package.json" "$TEST_TMPDIR/package.json"
    node -e '
      const fs = require("fs"), p = process.argv[1] + "/package.json";
      const doc = JSON.parse(fs.readFileSync(p, "utf8"));
      new Function("doc", process.argv[2])(doc);
      fs.writeFileSync(p, JSON.stringify(doc, null, 2) + "\n");
    ' "$TEST_TMPDIR" "$1"
}

@test "ascii wiring red control: the untouched copy is green" {
    ascii_wiring_mutate ''
    run node "$AAHP_ROOT/tests/assert-ascii-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ascii gate wiring OK"* ]]
}

@test "ascii wiring red control: dropping the gate from the check chain is red" {
    ascii_wiring_mutate 'doc.scripts.check = doc.scripts.check.replace(" && npm run check:ascii", "")'
    run grep -c "npm run check:ascii" "$TEST_TMPDIR/package.json"
    [ "$output" = "0" ]
    run node "$AAHP_ROOT/tests/assert-ascii-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"check:ascii is not part of the aggregate"* ]]
}

@test "ascii wiring red control: narrowing the required run with --path is red" {
    ascii_wiring_mutate 'doc.scripts["check:ascii"] += " --path=scripts"'
    run grep -c "check-ascii.mjs --path=scripts" "$TEST_TMPDIR/package.json"
    [ "$output" = "1" ]
    run node "$AAHP_ROOT/tests/assert-ascii-gate-wired.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be exactly"* ]]
}

# The same whole-tree run the required `npm run check` makes (no filter, pinned
# by the wiring test above), so a non-ASCII character anywhere is also red under
# `npm test`.
@test "ascii dogfood: every tracked text file in this repository is pure ASCII" {
    run node "$GATE" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASCII OK:"*"tracked text file(s) are pure ASCII"* ]]
}
