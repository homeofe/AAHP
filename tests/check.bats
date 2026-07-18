#!/usr/bin/env bats
# check.bats - the `aahp check` aggregate: run every APPLICABLE governance gate
# against [path], continue past a failure so one run surfaces them all, and exit
# non-zero iff any gate fails. A repo with no package.json / no config / no
# .ai/handoff must stay green (every gate self-skips).
#
# NOTE: the tracked-file gates (forbidden-patterns, doc-links) enumerate via
# `git ls-files`, so each fixture must `git add -A` inside TEST_TMPDIR before the
# check runs. This file is ASCII-only. The em-dash CHAR used as a forbidden-hit
# fixture is written with octal printf (\342\200\224). The em-dash REGEX stored
# in aahp.config.json is written as a JSON unicode escape whose leading backslash
# is emitted via octal printf (\134), so the config file stays pure ASCII and
# never matches its own rule.

load test_helper

AAHP="$AAHP_ROOT/bin/aahp.js"

gadd() {
    git -C "$TEST_TMPDIR" add -A
}

# Write an aahp.config.json whose forbiddenPatterns rule bans the em-dash. The
# pattern is emitted as a JSON unicode escape (leading backslash via octal \134),
# so the config file is pure ASCII and does not trip its own rule. $1 is any
# extra top-level JSON members to splice in (e.g. a docLinks or check block), or
# an empty string for none.
write_emdash_config() {
    printf '{ "forbiddenPatterns": [ { "id": "em-dash", "pattern": "\134u2014", "message": "em dash banned; use a hyphen" } ]%s }\n' "$1" > "$TEST_TMPDIR/aahp.config.json"
}

# A version-sync mismatch fixture: package.json + a valid CHANGELOG (so the two
# changelog gates PASS) plus a versionSite file that does NOT carry the version
# (so version-sync is the single failing gate).
scaffold_version_mismatch() {
    echo '{ "name": "fx", "version": "1.0.0" }' > "$TEST_TMPDIR/package.json"
    cat > "$TEST_TMPDIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01
**first**

### Added
- a thing

[Unreleased]: https://github.com/x/y/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/x/y/releases/tag/v1.0.0
EOF
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "versionSites": [ { "file": "VERSION.txt", "minOccurrences": 1 } ] }
EOF
    echo "shipped 0.9.0" > "$TEST_TMPDIR/VERSION.txt"
    gadd
}

# --- bare repo: everything skips, exit 0 -------------------------------------

@test "check: bare repo (no pkg/config/changelog) exits 0 with all 8 gates skipped" {
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        const ids=["changelog","changelog-format","version-sync","claims",
                   "forbidden-patterns","schema-doc-sync","doc-links","handoff"];
        if (Object.keys(r.gates).length!==ids.length) process.exit(2);
        for (const id of ids) if (r.gates[id]!=="skip") process.exit(3);
      });
    '
}

# --- a single failing gate is named -----------------------------------------

@test "check: a versionSites mismatch fails and names version-sync" {
    scaffold_version_mismatch
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"version-sync"* ]]
    [[ "$output" == *"Governance FAILED"* ]]
}

# --- aggregation: both failing gates appear in one run ----------------------

@test "check: two failing gates are BOTH reported (no short-circuit)" {
    write_emdash_config ', "docLinks": { "include": ["DOCS.md"] }'
    # em-dash hit for forbidden-patterns (octal printf keeps this source ASCII).
    printf 'bad \342\200\224 dash\n' > "$TEST_TMPDIR/bad.md"
    # broken internal link for doc-links.
    printf '# Docs\n\n[missing](./nope.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden-patterns"* ]]
    [[ "$output" == *"doc-links"* ]]
}

# --- --json: parseable record; exit 0 iff no gate fails ---------------------

@test "check --json: emits {schemaVersion:1, command:check, gates} and exit 0 on a pass" {
    # pattern requires 99 consecutive "z"s: present in no tracked file, and the
    # literal source "z{99}" in this config does not satisfy the regex, so the
    # gate does not match its own config file. forbidden-patterns therefore PASS.
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "forbiddenPatterns": [ { "id": "nope", "pattern": "z{99}", "message": "x" } ] }
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        if (r.schemaVersion!==1) process.exit(2);
        if (r.command!=="check") process.exit(3);
        if (typeof r.gates!=="object" || r.gates===null) process.exit(4);
        if (r.gates["forbidden-patterns"]!=="pass") process.exit(5);
        if (Object.values(r.gates).some((x)=>x==="fail")) process.exit(6);
      });
    '
}

@test "check --json: a failing gate marks fail and exits 1" {
    write_emdash_config ''
    printf 'bad \342\200\224 dash\n' > "$TEST_TMPDIR/bad.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        process.exit(r.gates["forbidden-patterns"]==="fail"?0:1);
      });
    '
}

# --- --quiet: only failing gate lines plus the footer -----------------------

@test "check --quiet: prints only failing gate lines and the footer" {
    scaffold_version_mismatch
    run node "$AAHP" check "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"version-sync"* ]]
    [[ "$output" == *"Governance FAILED"* ]]
    # header, passing PASS lines, and the OK footer are all suppressed in quiet.
    [[ "$output" != *"governance gates for"* ]]
    [[ "$output" != *"Governance OK"* ]]
    [[ "$output" != *"PASS"* ]]
}

# --- config.check.skip: a deselected gate does not run ----------------------

@test "check: config.check.skip omits doc-links so a broken link is not caught" {
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "docLinks": { "include": ["DOCS.md"] },
  "check": { "skip": ["doc-links"] }
}
EOF
    printf '# Docs\n\n[missing](./nope.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deselected by config.check"* ]]
}

# --- config.check.only: run ONLY the named gate(s) --------------------------

@test "check: config.check.only runs only the named gate; others are skipped" {
    # forbidden-patterns "z{99}" matches nothing (see the --json pass test), so
    # the only gate that runs here passes; doc-links is the one that would fail.
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "forbiddenPatterns": [ { "id": "nope", "pattern": "z{99}", "message": "x" } ],
  "docLinks": { "include": ["DOCS.md"] },
  "check": { "only": ["forbidden-patterns"] }
}
EOF
    # doc-links WOULD fail here, but it is deselected by config.check.only.
    printf '# Docs\n\n[missing](./nope.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        if (r.gates["forbidden-patterns"]!=="pass") process.exit(2);
        for (const [k,v] of Object.entries(r.gates)) {
          if (k!=="forbidden-patterns" && v!=="skip") process.exit(3);
        }
      });
    '
}

# --- applicability: versionSites but NO package.json -> version-sync skips ---

@test "check: versionSites without package.json skips version-sync and exits 0" {
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{ "versionSites": [ { "file": "VERSION.txt", "minOccurrences": 1 } ] }
EOF
    echo "shipped 0.9.0" > "$TEST_TMPDIR/VERSION.txt"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        process.exit(r.gates["version-sync"]==="skip"?0:1);
      });
    '
}
