#!/usr/bin/env bats
# gates.bats - the config-driven release gates: version-sync, changelog presence,
# changelog-format, claims, and the LOG/freshness generator.

load test_helper

VS="$SCRIPTS_DIR/check-version-sync.mjs"
CL="$SCRIPTS_DIR/check-changelog.mjs"
CLF="$SCRIPTS_DIR/check-changelog-format.mjs"
CLAIMS="$SCRIPTS_DIR/check-claims.mjs"
DASH="$SCRIPTS_DIR/aahp-dashboard.mjs"

mkpkg() {
    echo "{ \"name\": \"fx\", \"version\": \"$1\" }" > "$TEST_TMPDIR/package.json"
}

mkconfig() {
    cat > "$TEST_TMPDIR/aahp.config.json"
}

# --- version-sync ------------------------------------------------------------

@test "version-sync: no config is a clean no-op" {
    mkpkg "1.0.0"
    run node "$VS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no versionSites configured"* ]]
}

@test "version-sync: passes when the version is present in a site" {
    mkpkg "1.2.3"
    echo "release 1.2.3 shipped" > "$TEST_TMPDIR/VERSION.txt"
    mkconfig <<'EOF'
{ "versionSites": [ { "file": "VERSION.txt", "minOccurrences": 1 } ] }
EOF
    run node "$VS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version sync OK"* ]]
}

@test "version-sync: fails when a site is missing the version" {
    mkpkg "1.2.3"
    echo "this file has version 1.0.0 only" > "$TEST_TMPDIR/VERSION.txt"
    mkconfig <<'EOF'
{ "versionSites": [ { "file": "VERSION.txt", "minOccurrences": 1 } ] }
EOF
    run node "$VS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Version sync check failed"* ]]
    [[ "$output" == *"stale versions"* ]]
}

@test "version-sync: reports a missing site file cleanly (no stack trace)" {
    mkpkg "1.2.3"
    mkconfig <<'EOF'
{ "versionSites": [ { "file": "does-not-exist.txt" } ] }
EOF
    run node "$VS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"file not found"* ]]
    [[ "$output" != *"Error: ENOENT"* ]]
}

@test "version-sync: boundary avoids matching inside a longer version" {
    mkpkg "3.3.0"
    echo "3.3.09" > "$TEST_TMPDIR/VERSION.txt"
    mkconfig <<'EOF'
{ "versionSites": [ { "file": "VERSION.txt", "minOccurrences": 1, "boundary": true } ] }
EOF
    run node "$VS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

# --- changelog presence ------------------------------------------------------

@test "changelog presence: no CHANGELOG.md is a clean skip" {
    mkpkg "1.0.0"
    run node "$CL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "changelog presence: passes when the current version has an entry" {
    mkpkg "1.0.0"
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n**init**\n' > "$TEST_TMPDIR/CHANGELOG.md"
    run node "$CL" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"contains an entry for 1.0.0"* ]]
}

@test "changelog presence: fails when the current version has no entry" {
    mkpkg "2.0.0"
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n**init**\n' > "$TEST_TMPDIR/CHANGELOG.md"
    run node "$CL" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing an entry for 2.0.0"* ]]
}

# --- changelog-format --------------------------------------------------------

valid_changelog() {
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [2.0.0] - 2026-02-01
**second**

### Added
- a thing

## [1.0.0] - 2026-01-01
**first**

[Unreleased]: https://github.com/x/y/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/x/y/releases/tag/v2.0.0
[1.0.0]: https://github.com/x/y/releases/tag/v1.0.0
EOF
}

@test "changelog-format: accepts a well-formed Keep a Changelog file" {
    mkpkg "2.0.0"
    valid_changelog
    run node "$CLF" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Changelog format OK"* ]]
}

@test "changelog-format: R1 rejects a 'v'-prefixed heading" {
    mkpkg "2.0.0"
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [v2.0.0] - 2026-02-01
**bad heading**

[Unreleased]: https://github.com/x/y
[v2.0.0]: https://github.com/x/y
EOF
    run node "$CLF" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R1"* ]]
}

@test "changelog-format: R5 rejects out-of-order releases" {
    mkpkg "1.0.0"
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01
**older on top**

## [2.0.0] - 2026-02-01
**newer below**

[Unreleased]: https://github.com/x/y
[1.0.0]: https://github.com/x/y
[2.0.0]: https://github.com/x/y
EOF
    run node "$CLF" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R5"* ]]
}

@test "changelog-format: R6 rejects a top release that is not package.json" {
    mkpkg "9.9.9"
    valid_changelog
    run node "$CLF" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R6"* ]]
}

@test "changelog-format: R7 rejects a missing reference link" {
    mkpkg "1.0.0"
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01
**no reflink**
EOF
    run node "$CLF" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R7"* ]]
}

# --- claims ------------------------------------------------------------------

@test "claims: no config is a clean no-op" {
    mkpkg "1.0.0"
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"none configured"* ]]
}

@test "claims: passes when every surface carries the canonical number" {
    mkpkg "1.0.0"
    echo "We ship 350+ detection rules across the board." > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "claims": [ { "id": "rules", "canonical": "350+", "advertised": 350,
  "phrase": "(\\d+)\\+\\s*(?:detection rules|rules)\\b",
  "surfaces": [ { "file": "README.md" } ] } ] }
EOF
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Capability claims OK"* ]]
}

@test "claims: fails on a mismatched surface number" {
    mkpkg "1.0.0"
    echo "We ship 200+ detection rules." > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "claims": [ { "id": "rules", "canonical": "350+", "advertised": 350,
  "phrase": "(\\d+)\\+\\s*(?:detection rules|rules)\\b",
  "surfaces": [ { "file": "README.md" } ] } ] }
EOF
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"canonical is \"350+\""* ]]
}

@test "claims: floorCmd overstate fails the honesty check" {
    mkpkg "1.0.0"
    echo "We ship 350+ rules." > "$TEST_TMPDIR/README.md"
    echo 'console.log(12)' > "$TEST_TMPDIR/floor.mjs"
    mkconfig <<'EOF'
{ "claims": [ { "id": "rules", "canonical": "350+", "advertised": 350,
  "phrase": "(\\d+)\\+\\s*rules\\b", "floorCmd": "floor.mjs",
  "surfaces": [ { "file": "README.md" } ] } ] }
EOF
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"exceeds ground truth"* ]]
}

@test "claims: floorCmd rejects a path escaping the project root (no shell exec)" {
    mkpkg "1.0.0"
    echo "We ship 350+ rules." > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "claims": [ { "id": "rules", "canonical": "350+", "advertised": 350,
  "phrase": "(\\d+)\\+\\s*rules\\b", "floorCmd": "../evil.mjs",
  "surfaces": [ { "file": "README.md" } ] } ] }
EOF
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"repo-relative script path"* ]]
}

@test "claims: floorCmd rejects an absolute path" {
    mkpkg "1.0.0"
    echo "We ship 350+ rules." > "$TEST_TMPDIR/README.md"
    mkconfig <<'EOF'
{ "claims": [ { "id": "rules", "canonical": "350+", "advertised": 350,
  "phrase": "(\\d+)\\+\\s*rules\\b", "floorCmd": "/tmp/evil.mjs",
  "surfaces": [ { "file": "README.md" } ] } ] }
EOF
    run node "$CLAIMS" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"repo-relative script path"* ]]
}

# --- generator / freshness ---------------------------------------------------

@test "generator: freshness passes when NEXT_ACTIONS matches package.json" {
    mkpkg "1.2.3"
    printf 'Current version: **v1.2.3**\n' > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"
    run node "$DASH" "$TEST_TMPDIR" --check
    [ "$status" -eq 0 ]
}

@test "generator: freshness fails when NEXT_ACTIONS lags package.json" {
    mkpkg "1.2.3"
    printf 'Current version: **v1.0.0**\n' > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"
    run node "$DASH" "$TEST_TMPDIR" --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Current version"* ]]
}

@test "generator: writes the release journal to its own file, --check agrees, LOG.md is untouched" {
    mkpkg "2.0.0"
    valid_changelog
    mkconfig <<'EOF'
{ "generate": { "log": { "source": "CHANGELOG.md", "target": "docs/RELEASES.md", "title": "Fx: Release Journal" } } }
EOF
    # aahp-manifest.sh regen needs the standard handoff files present.
    create_full_handoff "$TEST_TMPDIR/.ai/handoff"
    cp "$TEST_TMPDIR/.ai/handoff/LOG.md" "$TEST_TMPDIR/journal.before"
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # docs/ did not exist; the generator creates the directory.
    grep -q "Fx: Release Journal" "$TEST_TMPDIR/docs/RELEASES.md"
    grep -q "| v2.0.0 | 2026-02-01 | second |" "$TEST_TMPDIR/docs/RELEASES.md"
    grep -q "| v1.0.0 | 2026-01-01 | first |" "$TEST_TMPDIR/docs/RELEASES.md"
    cmp -s "$TEST_TMPDIR/journal.before" "$TEST_TMPDIR/.ai/handoff/LOG.md"
    run node "$DASH" "$TEST_TMPDIR" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/RELEASES.md in sync with CHANGELOG.md"* ]]
}

# --- generator: the agent journal is never a release-journal target (ADR-004) --
#
# The generator overwrites its target with writeFileSync. The target used to
# default to .ai/handoff/LOG.md and aahp.config.example.json pointed it there,
# so an adopter who copied the example lost every session entry in LOG.md on the
# first handoff-refresh. Measured at 1917ca8 with that config: exit 0,
# "handoff-refresh OK: regenerated .ai/handoff/LOG.md", journal sentinel gone.

# $1 = the generate.log.target value, written into the config verbatim.
_journal_target_fixture() {
    mkpkg "2.0.0"
    valid_changelog
    create_full_handoff "$TEST_TMPDIR/.ai/handoff"
    echo "SENTINEL-agent-journal-entry" >> "$TEST_TMPDIR/.ai/handoff/LOG.md"
    printf '# Archived Agent Journal\n\nSENTINEL-archive\n' > "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
    printf '{ "generate": { "log": { "source": "CHANGELOG.md", "target": "%s" } } }\n' "$1" \
        > "$TEST_TMPDIR/aahp.config.json"
}

@test "generator: refuses to write the release journal over LOG.md, and LOG.md survives" {
    _journal_target_fixture ".ai/handoff/LOG.md"
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refuses to write there"* ]]
    [[ "$output" == *"ADR-004"* ]]
    grep -q "SENTINEL-agent-journal-entry" "$TEST_TMPDIR/.ai/handoff/LOG.md"
    # `! grep` alone never fails a bats test (errexit ignores a negated command).
    if grep -q "Release Journal" "$TEST_TMPDIR/.ai/handoff/LOG.md"; then false; fi
}

@test "generator: --check refuses a LOG.md target too, instead of calling the journal stale" {
    _journal_target_fixture ".ai/handoff/LOG.md"
    run node "$DASH" "$TEST_TMPDIR" --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"refuses to write there"* ]]
    [[ "$output" != *"is stale"* ]]
}

@test "generator: refuses LOG-ARCHIVE.md, LOG-ARCHIVE.index.json and spellings that reach LOG.md" {
    local t
    for t in ".ai/handoff/LOG-ARCHIVE.md" ".ai/handoff/LOG-ARCHIVE.index.json" \
             "docs/../.ai/handoff/LOG.md" "./.ai/handoff/LOG.md" ".ai/handoff/log.md"; do
        _journal_target_fixture "$t"
        run node "$DASH" "$TEST_TMPDIR"
        [ "$status" -eq 1 ] || { echo "target '$t' was not refused: $output"; false; }
        [[ "$output" == *"refuses to write there"* ]] || { echo "target '$t': $output"; false; }
        grep -q "SENTINEL-agent-journal-entry" "$TEST_TMPDIR/.ai/handoff/LOG.md"
        grep -q "SENTINEL-archive" "$TEST_TMPDIR/.ai/handoff/LOG-ARCHIVE.md"
    done
}

@test "generator: a symlink onto LOG.md is refused" {
    _journal_target_fixture "docs/RELEASES.md"
    mkdir -p "$TEST_TMPDIR/docs"
    ln -s "../.ai/handoff/LOG.md" "$TEST_TMPDIR/docs/RELEASES.md" 2>/dev/null \
        && [ -L "$TEST_TMPDIR/docs/RELEASES.md" ] || skip "symlinks are not available here"
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refuses to write there"* ]]
    grep -q "SENTINEL-agent-journal-entry" "$TEST_TMPDIR/.ai/handoff/LOG.md"
}

@test "generator: an unset target is refused; it no longer defaults to LOG.md" {
    mkpkg "2.0.0"
    valid_changelog
    create_full_handoff "$TEST_TMPDIR/.ai/handoff"
    echo "SENTINEL-agent-journal-entry" >> "$TEST_TMPDIR/.ai/handoff/LOG.md"
    mkconfig <<'EOF'
{ "generate": { "log": { "source": "CHANGELOG.md" } } }
EOF
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"generate.log.target is not set"* ]]
    grep -q "SENTINEL-agent-journal-entry" "$TEST_TMPDIR/.ai/handoff/LOG.md"
}

@test "generator: the shipped aahp.config.example.json release-journal target is accepted and spares LOG.md" {
    # Binds the example to the guard: copying the example's generate.log block
    # into a project must work, and must leave the agent journal alone.
    mkpkg "2.0.0"
    valid_changelog
    create_full_handoff "$TEST_TMPDIR/.ai/handoff"
    echo "SENTINEL-agent-journal-entry" >> "$TEST_TMPDIR/.ai/handoff/LOG.md"
    node -e '
      const fs = require("fs");
      const ex = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      fs.writeFileSync(process.argv[2], JSON.stringify({ generate: { log: ex.generate.log } }, null, 2) + "\n");
    ' "$AAHP_ROOT/aahp.config.example.json" "$TEST_TMPDIR/aahp.config.json"
    run node "$DASH" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    grep -q "SENTINEL-agent-journal-entry" "$TEST_TMPDIR/.ai/handoff/LOG.md"
    # `! grep` alone never fails a bats test (errexit ignores a negated command).
    if grep -q "Release Journal" "$TEST_TMPDIR/.ai/handoff/LOG.md"; then false; fi
}
