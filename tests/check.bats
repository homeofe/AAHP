#!/usr/bin/env bats
# check.bats - the `aahp check` aggregate: run every APPLICABLE governance gate
# against [path], continue past a failure so one run surfaces them all, and exit
# non-zero iff any gate fails OR no gate ran at all.
#
# THE HEADER USED TO SAY a repo with no package.json / no config / no
# .ai/handoff "must stay green (every gate self-skips)". That stopped being true
# when the zero-gate branch shipped: such a repo reports
# `Governance NOT EVALUATED: 0 gate(s) ran.` and exits 1 on the text path.
# Measured on origin/main at 2cdaf48, the --json path on the SAME tree still
# exited 0 with every gate `skip`, because the JSON branch returned above the
# zero-gate test. The two halves are now one verdict, computed once.
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

# --- bare repo: everything skips, so nothing was evaluated -------------------

@test "check: bare repo (no pkg/config/changelog) is NOT EVALUATED, all 8 skipped" {
    # RE-GROUNDED, not relaxed. The subject is still the gate MAP: all eight
    # gates self-skip on a repository with nothing to check, and that assertion
    # is unchanged and strengthened with a count. What changed is the exit code,
    # from 0 to 1, and it changed on the TEXT path when the zero-gate branch
    # shipped. This test asserted 0 only because it used --json, which returned
    # before that branch. Asserting the map and the verdict separately is what
    # keeps it from re-acquiring the defect it used to encode.
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        const ids=["changelog","changelog-format","version-sync","claims",
                   "forbidden-patterns","schema-doc-sync","doc-links","handoff"];
        if (Object.keys(r.gates).length!==ids.length) process.exit(2);
        for (const id of ids) if (r.gates[id]!=="skip") process.exit(3);
        if (r.evaluated!==0) process.exit(4);
        if (r.total!==ids.length) process.exit(5);
      });
    '
}

@test "check: --json and the text path reach the SAME verdict on a bare repo" {
    # The defect, stated as a test. On origin/main at 2cdaf48 this one tree gave
    # `NOT EVALUATED, exit 1` in text and `exit 0, every gate skip` in JSON, and
    # the machine-readable half is the one a CI tick and a dashboard consume.
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    local text_status="$status"
    [[ "$output" == *"Governance NOT EVALUATED: 0 of 8 gate(s) ran. This is not a pass."* ]]
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq "$text_status" ]
    [ "$status" -eq 1 ]
}

@test "check --quiet: an all-skipped tree states the result, never zero bytes" {
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [ -n "$output" ]
    [[ "$output" == *"NOT EVALUATED"* ]]
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
        if (r.schemaVersion!==2) process.exit(2);
        if (r.command!=="check") process.exit(3);
        if (typeof r.gates!=="object" || r.gates===null) process.exit(4);
        if (r.gates["forbidden-patterns"]!=="pass") process.exit(5);
        if (Object.values(r.gates).some((x)=>x==="fail")) process.exit(6);
        if (r.evaluated!==1) process.exit(7);
        if (r.total!==8) process.exit(8);
        if (r.gateOutcomes["forbidden-patterns"].outcome!=="pass") process.exit(9);
      });
    '
}

@test "check --json: the record tells 'deselected by config' from 'not applicable'" {
    # THE DEFECT. Both were the token `skip`, so a repository that has switched
    # a gate off through config.check and one that simply has no such files
    # emitted byte-identical `gates` objects. README offers this record to a
    # fleet dashboard, and the dashboard could not tell them apart.
    #
    # `changelog` is not applicable (no CHANGELOG.md here); `forbidden-patterns`
    # is configured, applicable, and deselected. A gate that really runs is left
    # in so this is not also a zero-gate run.
    write_emdash_config ', "docLinks": { "include": ["DOCS.md"] }, "check": { "skip": ["forbidden-patterns"] }'
    printf 'bad \342\200\224 dash\n' > "$TEST_TMPDIR/bad.md"
    printf '# Docs\n\n[readme](./bad.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        // Unchanged from schemaVersion 1: both are still `skip` in `gates`.
        if (r.gates["forbidden-patterns"]!=="skip") process.exit(2);
        if (r.gates["changelog"]!=="skip") process.exit(3);
        // New in 2: the two are no longer the same token.
        if (r.gateOutcomes["forbidden-patterns"].outcome!=="deselected") process.exit(4);
        if (r.gateOutcomes["changelog"].outcome!=="not-applicable") process.exit(5);
        if (r.gateOutcomes["forbidden-patterns"].outcome===r.gateOutcomes["changelog"].outcome) process.exit(6);
        // and the run is not vacuous: doc-links really ran.
        if (r.evaluated!==1) process.exit(7);
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
    # RE-GROUNDED, not relaxed. This fixture used to configure `docLinks` and
    # nothing else, then skip `doc-links` - so NO gate ran, and the test asserted
    # exit 0 for a run that had assessed nothing. That is the #84 defect written
    # down as an expectation, and the fix on this branch (zero gates ran reports
    # NOT EVALUATED and exits 1) correctly turned it red. Changing the 0 to a 1
    # would have been the wrong repair: it would pin the aggregate verdict, which
    # is not what this test is about.
    #
    # The subject here is the DESELECTION: a skipped gate must not run, so its
    # broken link must go unreported. The fixture therefore also carries a gate
    # that really runs and really passes, which makes the exit 0 a genuine pass
    # rather than a vacuous one. `z{99}` needs 99 consecutive `z` to match, so
    # forbidden-patterns runs and finds nothing - the same device the
    # `config.check.only` test below already uses.
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "forbiddenPatterns": [ { "id": "nope", "pattern": "z{99}", "message": "x" } ],
  "docLinks": { "include": ["DOCS.md"] },
  "check": { "skip": ["doc-links"] }
}
EOF
    printf '# Docs\n\n[missing](./nope.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deselected by config.check"* ]]
    # A gate really ran, so this is a pass and not "nothing was assessed".
    [[ "$output" != *"NOT EVALUATED"* ]]
    # The actual property: the deselected gate never evaluated the broken link.
    [[ "$output" != *"nope.md"* ]]
}

@test "check: skipping the ONLY configured gate is NOT EVALUATED, never a pass" {
    # The other half of the test above, and the reason it was re-grounded rather
    # than have its 0 changed to a 1. `check.skip` can empty the run entirely,
    # and a run that evaluated nothing must not report a pass - precisely the
    # shape #84 was filed for ("Governance OK: 0 gate(s) ran, no failures").
    # Anchor: the zero-gate branch of the summary in cmdCheck.
    cat > "$TEST_TMPDIR/aahp.config.json" <<'EOF'
{
  "docLinks": { "include": ["DOCS.md"] },
  "check": { "skip": ["doc-links"] }
}
EOF
    printf '# Docs\n\n[missing](./nope.md)\n' > "$TEST_TMPDIR/DOCS.md"
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOT EVALUATED"* ]]
    [[ "$output" != *"Governance OK"* ]]
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
