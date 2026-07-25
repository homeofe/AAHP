#!/usr/bin/env bats
# acceptance-criteria.bats - the acceptance-criteria lifecycle gate.
#
# The contract under test has two halves:
#   1. DETECTION: legacy heading aliases, plain bullets where task boxes belong,
#      and criteria left unresolved on a task the manifest calls "done" (unless
#      the criterion is waived or moved to a follow-up).
#   2. SEVERITY: findings are WARN by default (exit 0, gate absent from the
#      `aahp check` record unless configured) and only fail when a project opts
#      into "strict": true. That is what keeps a newer aahp release from turning
#      a green consumer repository red.
#
# The gate enumerates TRACKED files via `git ls-files`, so every fixture is
# `git add`ed before the gate runs (same convention as check.bats).

load test_helper

AC="$SCRIPTS_DIR/check-acceptance-criteria.mjs"
AAHP="$AAHP_ROOT/bin/aahp.js"

gadd() { git -C "$TEST_TMPDIR" add -A; }
mkconfig() { cat > "$TEST_TMPDIR/aahp.config.json"; }
# The `handoff` gate in `aahp check` applies as soon as a MANIFEST.json exists
# and reads package.json, so fixtures that carry a manifest carry a package too.
mkpkg() { echo '{ "name": "fx", "version": "1.0.0" }' > "$TEST_TMPDIR/package.json"; }
next_actions() { cat > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"; }
ungit() { rm -rf "$TEST_TMPDIR/.git"; }

# Enable the gate with default include/manifest paths.
enable_gate() {
    mkconfig <<'EOF'
{ "acceptanceCriteria": {} }
EOF
}

enable_gate_strict() {
    mkconfig <<'EOF'
{ "acceptanceCriteria": { "strict": true } }
EOF
}

# T-007 is done, T-008 is ready. The GitHub linkage fields mirror what real
# projects carry; the gate must ignore them and stay offline.
manifest_with_tasks() {
    cat > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'EOF'
{
  "aahp_version": "3.0",
  "project": "fixture",
  "last_session": {
    "agent": "test-agent",
    "session_id": "test-001",
    "timestamp": "2026-01-01T00:00:00Z",
    "phase": "idle"
  },
  "files": {},
  "quick_context": "fixture",
  "next_task_id": 9,
  "tasks": {
    "T-007": { "title": "Closed task", "status": "done", "github_issue": 42, "github_repo": "example/example" },
    "T-008": { "title": "Open task", "status": "ready" }
  }
}
EOF
}

# --- no config: clean no-op --------------------------------------------------

@test "acceptance-criteria: no config section is a clean no-op" {
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- plain bullet that would otherwise warn
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not configured"* ]]
}

# --- canonical, well-formed section -----------------------------------------

@test "acceptance-criteria: canonical heading with task boxes on an open task passes" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] Tests pass
- [x] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
    [[ "$output" != *"WARN"* ]]
}

# --- legacy heading aliases --------------------------------------------------

@test "acceptance-criteria: legacy 'Definition of done' warns and still exits 0" {
    enable_gate
    next_actions <<'EOF'
## T-008: Open task

**Definition of done:**
- [ ] Tests pass
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN acceptance-criteria"* ]]
    [[ "$output" == *"legacy-heading"* ]]
    [[ "$output" == *"Acceptance criteria"* ]]
}

@test "acceptance-criteria: legacy 'Completion criteria' warns and still exits 0" {
    enable_gate
    next_actions <<'EOF'
## Completion criteria

- [ ] Tests pass
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy-heading"* ]]
}

@test "acceptance-criteria: renaming the legacy heading stops the warning" {
    enable_gate
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] Tests pass
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"legacy-heading"* ]]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

# --- plain bullets -----------------------------------------------------------

@test "acceptance-criteria: plain bullets under the canonical heading warn" {
    enable_gate
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- Tests pass
- Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"plain-bullets"* ]]
    [[ "$output" == *"2 plain bullet(s)"* ]]
}

@test "acceptance-criteria: nested detail lines under a task box are not criteria" {
    enable_gate
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] Tests pass
  - covers the parser
  - covers the CLI
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"plain-bullets"* ]]
}

# --- unresolved criteria on a done task --------------------------------------

@test "acceptance-criteria: a done task with an unresolved criterion warns" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"T-007"* ]]
}

@test "acceptance-criteria: checking the criterion clears the done-task finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass
- [x] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

@test "acceptance-criteria: a waived criterion is an accepted closure state" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass
- [ ] Load test at 10k rps (waived: no load rig in this environment, agreed in review)
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

@test "acceptance-criteria: a criterion moved to a follow-up is an accepted closure state" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass
- [ ] Migrate the legacy importer (follow-up: T-008)
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

@test "acceptance-criteria: an open task with unchecked criteria is not a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] Tests pass
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

@test "acceptance-criteria: without a manifest the done-state rule is skipped, not guessed" {
    enable_gate
    rm -f "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"done-state checks were skipped"* ]]
    [[ "$output" != *"unresolved-on-done"* ]]
}

# --- strict mode -------------------------------------------------------------

@test "acceptance-criteria: strict turns the same finding into a failure" {
    enable_gate_strict
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Acceptance-criteria check failed"* ]]
    [[ "$output" == *"legacy-heading"* ]]
    [[ "$output" == *"unresolved-on-done"* ]]
}

@test "acceptance-criteria: strict on a clean fixture still passes" {
    enable_gate_strict
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance criteria OK"* ]]
}

# --- offline determinism -----------------------------------------------------

@test "acceptance-criteria: linked GitHub issues do not make the gate reach the network" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    first="$output"
    [[ "$output" == *"Offline check"* ]]
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$first" ]
}

# --- work-tree guard (C-6 contract, same as the other enumerating gates) -----

@test "acceptance-criteria: fails loud outside a git work tree when configured" {
    enable_gate
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] Tests pass
EOF
    ungit
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"work tree"* ]]
    [[ "$output" == *"git checkout"* ]]
}

# --- aahp check integration: opt-in, warn-first ------------------------------

@test "check: without acceptanceCriteria the gate set is unchanged (8 gates, no new key)" {
    next_actions <<'EOF'
## T-008: Open task

**Definition of done:**
- plain bullet
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        const ids=["changelog","changelog-format","version-sync","claims",
                   "forbidden-patterns","schema-doc-sync","doc-links","handoff"];
        const keys=Object.keys(r.gates);
        if (keys.length!==ids.length) process.exit(2);
        for (const id of ids) if (!(id in r.gates)) process.exit(3);
        if ("acceptance-criteria" in r.gates) process.exit(4);
      });
    '
}

@test "check: with acceptanceCriteria the gate reports warn and the run still exits 0" {
    enable_gate
    mkpkg
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const r=JSON.parse(s);
        if (r.gates["acceptance-criteria"]!=="warn") process.exit(2);
        if (Object.values(r.gates).some((x)=>x==="fail")) process.exit(3);
      });
    '
}

@test "check: a warn gate is printed with a WARN label and the footer stays OK" {
    enable_gate
    mkpkg
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"acceptance-criteria"* ]]
    [[ "$output" == *"Governance OK"* ]]
    [[ "$output" == *"warning(s)"* ]]
}

@test "check --quiet: a warn gate is still surfaced" {
    enable_gate
    mkpkg
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    [[ "$output" == *"acceptance-criteria"* ]]
}

@test "check: acceptanceCriteria.strict makes the aggregate fail" {
    enable_gate_strict
    mkpkg
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Governance FAILED"* ]]
    [[ "$output" == *"acceptance-criteria"* ]]
}

@test "check: config.check.skip deselects the acceptance-criteria gate" {
    mkconfig <<'EOF'
{
  "acceptanceCriteria": { "strict": true },
  "check": { "skip": ["acceptance-criteria"] }
}
EOF
    mkpkg
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deselected by config.check"* ]]
}
