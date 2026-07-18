#!/usr/bin/env bats
# doctor.bats - the `aahp doctor` conformance self-check and its JSON record.

load test_helper

AAHP="$AAHP_ROOT/bin/aahp.js"

# Build a fully conformant consumer fixture: package.json with an exact-version
# pin, an aahp.config.json that opts the pinned-dep gate in (C-7), a valid
# MANIFEST.json, GROUNDING.md, and a TRUST.md with a Provenance column. No
# CHANGELOG.md and no versionSites, so changelog-format and version-sync SKIP.
scaffold_conformant() {
    local root="$TEST_TMPDIR"
    local h="$root/.ai/handoff"
    cat > "$root/package.json" <<'EOF'
{
  "name": "consumer-app",
  "version": "1.2.3",
  "devDependencies": { "@elvatis_com/aahp": "3.4.0" }
}
EOF
    # C-7: pinned-dep is opt-in. An empty pinnedDep object asserts the default
    # pin (@elvatis_com/aahp in devDependencies) so the gate is evaluated, not
    # skipped, and the exact/range/missing tests still exercise it.
    cat > "$root/aahp.config.json" <<'EOF'
{
  "pinnedDep": {}
}
EOF
    create_manifest_json "$h"
    echo "# GROUNDING" > "$h/GROUNDING.md"
    cat > "$h/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Provenance | Notes |
|----------|--------|------------|-------|
| build passes | verified | test_verified | ok |
EOF
}

@test "doctor: conformant fixture passes with no failing gates" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conformance OK"* ]]
    [[ "$output" == *"pinned-dep: pinned exact: 3.4.0"* ]]
    [[ "$output" == *"changelog-format"* ]]
}

@test "doctor --json: emits a valid conformance record with the agreed shape" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    # Parse the JSON and assert the shape via node.
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        if (r.schemaVersion !== 1) process.exit(2);
        const keys = ["handoff-set","manifest-schema","grounding","pinned-dep","changelog-format","version-sync"];
        for (const k of keys) if (!(k in r.gates)) process.exit(3);
        if (typeof r.checkedAt !== "string") process.exit(4);
        if (typeof r.aahpVersion !== "string") process.exit(5);
      });
    '
}

@test "doctor: SELF when the repo is the aahp package itself" {
    run node "$AAHP" doctor "$AAHP_ROOT" --json
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        process.exit(r.gates["pinned-dep"]==="self"?0:1);
      });
    '
}

@test "doctor: fails when the aahp dep is a range, not an exact pin" {
    scaffold_conformant
    cat > "$TEST_TMPDIR/package.json" <<'EOF'
{ "name": "consumer-app", "version": "1.2.3", "devDependencies": { "@elvatis_com/aahp": "^3.4.0" } }
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not an exact pin"* ]]
}

@test "doctor: reports missing when the aahp dep is absent" {
    scaffold_conformant
    cat > "$TEST_TMPDIR/package.json" <<'EOF'
{ "name": "consumer-app", "version": "1.2.3" }
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING"* ]]
    [[ "$output" == *"not pinned"* ]]
}

@test "doctor: grounding fails when TRUST.md has no Provenance column" {
    scaffold_conformant
    cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Notes |
|----------|--------|-------|
| build passes | verified | ok |
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no Provenance column"* ]]
}

@test "doctor: grounding fails when GROUNDING.md is missing" {
    scaffold_conformant
    rm -f "$TEST_TMPDIR/.ai/handoff/GROUNDING.md"
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GROUNDING.md not found"* ]]
}

@test "doctor: handoff-set fails when an indexed file is missing on disk" {
    scaffold_conformant
    # Point MANIFEST at a file that does not exist.
    cat > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'EOF'
{
  "aahp_version": "3.0",
  "project": "consumer-app",
  "last_session": { "agent": "x", "timestamp": "2026-01-01T00:00:00Z", "phase": "idle" },
  "files": { "STATUS.md": { "checksum": "sha256:0000000000000000000000000000000000000000000000000000000000000000", "updated": "2026-01-01T00:00:00Z", "lines": 1, "summary": "s" } },
  "quick_context": "x"
}
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing on disk"* ]]
}

@test "doctor: manifest-schema fails on a malformed manifest" {
    scaffold_conformant
    cat > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'EOF'
{ "aahp_version": "nope", "files": {}, "quick_context": "x" }
EOF
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"manifest-schema"* ]]
    [[ "$output" == *"FAIL"* ]]
}

@test "doctor: --quiet prints only failing gates" {
    scaffold_conformant
    rm -f "$TEST_TMPDIR/.ai/handoff/GROUNDING.md"
    run node "$AAHP" doctor "$TEST_TMPDIR" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"grounding"* ]]
    [[ "$output" != *"handoff-set"* ]]
}

# --- Governance mode (A-2): --governance / --no-handoff -----------------------

@test "doctor --governance on a repo without .ai/handoff exits 0 with the 3 handoff gates skip" {
    scaffold_conformant
    # A governance-only consumer never adopts the handoff protocol.
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        for (const k of ["handoff-set", "manifest-schema", "grounding"]) {
          if (r.gates[k] !== "skip") process.exit(2);
        }
      });
    '
}

@test "doctor: --no-handoff is an exact alias for --governance" {
    scaffold_conformant
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    local gov="$output"
    run node "$AAHP" doctor "$TEST_TMPDIR" --no-handoff --json
    [ "$status" -eq 0 ]
    local nh="$output"
    # Identical gate maps and mode; only the checkedAt timestamp may differ.
    node -e '
      const a = JSON.parse(process.argv[1]);
      const b = JSON.parse(process.argv[2]);
      if (a.mode !== b.mode) process.exit(2);
      const ka = Object.keys(a.gates).sort();
      const kb = Object.keys(b.gates).sort();
      if (JSON.stringify(ka) !== JSON.stringify(kb)) process.exit(3);
      for (const k of ka) if (a.gates[k] !== b.gates[k]) process.exit(4);
    ' "$gov" "$nh"
}

@test "doctor --governance --json emits mode:governance with all six gate keys and the 3 handoff gates skip" {
    scaffold_conformant
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        if (r.mode !== "governance") process.exit(2);
        const keys = ["handoff-set","manifest-schema","grounding","pinned-dep","changelog-format","version-sync"];
        for (const k of keys) if (!(k in r.gates)) process.exit(3);
        for (const k of ["handoff-set", "manifest-schema", "grounding"]) {
          if (r.gates[k] !== "skip") process.exit(4);
        }
      });
    '
}

@test "doctor: default (no flag) still hard-fails on a repo without .ai/handoff" {
    scaffold_conformant
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conformance FAILED"* ]]
}

@test "doctor --json: default record has NO mode key (backward compat)" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        if ("mode" in r) process.exit(2);
      });
    '
}
