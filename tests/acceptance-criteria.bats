#!/usr/bin/env bats
# acceptance-criteria.bats - the ADVISORY acceptance-criteria lifecycle report.
#
# The contract under test has three parts:
#   1. DETECTION: legacy heading aliases, plain bullets where task boxes belong,
#      and criteria left unresolved on a task the manifest calls "done" (unless
#      the criterion is waived or moved to a follow-up).
#   2. COMPREHENSION: the report never presents a document it could not read as
#      a clean one. A configured pathspec that matches nothing, a criteria
#      section with no recognized criterion, a section that binds to no
#      registered task, a code fence left open at end of file, and an unusable
#      task registry are all findings.
#   3. NO AUTHORITY: the report ALWAYS exits 0, findings or not. It has no
#      enforcing mode, and it is not in the `aahp check` gate list, so the gate
#      set and the `aahp check --json` record stay the eight keys they have
#      always been, configured or not. The only non-zero exit is the report
#      failing to run at all (no git work tree). There are deliberately NO
#      strict-mode tests: strict mode does not exist.
#
# The KNOWN BLIND SPOTS block at the end asserts the CURRENT, MISSING behaviour
# on shapes the report cannot read. Those tests document limitations; they are
# not bugs waiting to be fixed. See README Section 8.7 and ADR-017.
#
# The report enumerates TRACKED files via `git ls-files`, so every fixture is
# `git add`ed before it runs (same convention as check.bats).

load test_helper

AC="$SCRIPTS_DIR/report-acceptance-criteria.mjs"
AAHP="$AAHP_ROOT/bin/aahp.js"

gadd() { git -C "$TEST_TMPDIR" add -A; }
mkconfig() { cat > "$TEST_TMPDIR/aahp.config.json"; }
# The `handoff` gate in `aahp check` applies as soon as a MANIFEST.json exists
# and reads package.json, so fixtures that carry a manifest carry a package too.
mkpkg() { echo '{ "name": "fx", "version": "1.0.0" }' > "$TEST_TMPDIR/package.json"; }
next_actions() { cat > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"; }
ungit() { rm -rf "$TEST_TMPDIR/.git"; }

# Point the report at the default include/manifest paths.
enable_gate() {
    mkconfig <<'EOF'
{ "acceptanceCriteria": {} }
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
    [[ "$output" == *"no findings"* ]]
    [[ "$output" != *"finding(s)"* ]]
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
    [[ "$output" == *"finding(s)"* ]]
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
    [[ "$output" == *"no findings"* ]]
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
    [[ "$output" == *"2 plain list item(s)"* ]]
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
    [[ "$output" == *"no findings"* ]]
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
    [[ "$output" == *"no findings"* ]]
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
    [[ "$output" == *"no findings"* ]]
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
    [[ "$output" == *"no findings"* ]]
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

# --- offline determinism -----------------------------------------------------

@test "acceptance-criteria: linked GitHub issues do not make the report reach the network" {
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
    [[ "$output" == *"offline report"* ]]
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

# --- no authority: the report can never change an exit code ------------------
#
# This is the whole point of the demotion (ADR-017). A heuristic over
# hand-written Markdown cannot be sound, so it must not be able to fail a build.

@test "acceptance-criteria: findings are reported and the exit code is still 0" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
- plain bullet
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"finding(s)"* ]]
    [[ "$output" == *"legacy-heading"* ]]
    [[ "$output" == *"plain-bullets"* ]]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"ADVISORY"* ]]
    [[ "$output" == *"must not be used as a merge"* ]]
}

@test "acceptance-criteria: a clean report still says it is not proof" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
    [[ "$output" == *"NOT proof"* ]]
}

@test "criteria: the aahp criteria command reports findings and exits 0" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Definition of done:**
- [ ] Docs updated
EOF
    gadd
    run node "$AAHP" criteria "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy-heading"* ]]
    [[ "$output" == *"unresolved-on-done"* ]]
}

# --- aahp check integration: the report is NOT a gate ------------------------

@test "check: the gate set is eight ids and acceptance-criteria is not one of them" {
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

@test "check: configuring acceptanceCriteria still does not add a gate" {
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
        const ids=["changelog","changelog-format","version-sync","claims",
                   "forbidden-patterns","schema-doc-sync","doc-links","handoff"];
        const keys=Object.keys(r.gates);
        if (keys.length!==ids.length) process.exit(2);
        for (const id of ids) if (!(id in r.gates)) process.exit(3);
        if ("acceptance-criteria" in r.gates) process.exit(4);
        if (Object.values(r.gates).some((x)=>x==="warn")) process.exit(5);
      });
    '
}

@test "acceptance-criteria: ordered-list task boxes are criteria (unresolved-on-done fires)" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
1. [x] Tests pass
2. [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"T-007"* ]]
    [[ "$output" == *"1 criterion/criteria are unresolved"* ]]
}

@test "acceptance-criteria: ordered-list plain items are criteria (plain-bullets fires)" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
1. Tests pass
2. Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"plain-bullets"* ]]
    [[ "$output" == *"2 plain list item(s)"* ]]
}

@test "acceptance-criteria: ordered-list criteria resolve the same way bullets do" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
1. [x] Tests pass
2. [ ] Docs updated (waived: docs live downstream)
3. [ ] Benchmark rerun (follow-up: T-008)
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

# --- fenced code blocks are not content --------------------------------------

@test "acceptance-criteria: criteria shown inside a fenced block are not live criteria" {
    # The fence sits inside a live criteria section whose one real criterion is
    # checked. If fenced lines counted, the unchecked boxes and the plain bullet
    # inside the block would fire plain-bullets and unresolved-on-done on a task
    # the registry calls done.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass

The format, for reference:

```markdown
- [ ] Something not yet done
1. [ ] Another thing not yet done
- A plain bullet nobody can track
```
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

@test "acceptance-criteria: a criteria heading holding only a fence is reported" {
    # The other half of the rule above. A documentation section that titles a
    # fenced example "Acceptance criteria" yields zero recognized criteria, and
    # under the fail-loud contract that is a finding rather than a clean pass:
    # from the outside it is indistinguishable from criteria the parser missed.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## How to write criteria

**Acceptance criteria:**

```markdown
- [ ] Something not yet done
```
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparsed-criteria-section"* ]]
}

@test "acceptance-criteria: a tilde fence is skipped too" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [x] Tests pass

~~~
- [ ] Example criterion inside a tilde fence
~~~
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

# --- corrupt task registry ---------------------------------------------------
#
# An unparseable MANIFEST.json used to be reported as an ABSENT one, which
# silently disabled the unresolved-on-done rule, while the
# message asserted the registry was missing when it was actually corrupt.

@test "acceptance-criteria: an unparseable manifest is a finding, not a silent skip" {
    enable_gate
    printf '{ "tasks": { "T-007": ' > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest-unreadable"* ]]
    [[ "$output" == *"present but unusable: not valid JSON"* ]]
    [[ "$output" != *"no task registry at"* ]]
}

@test "acceptance-criteria: a genuinely absent manifest still reports as absent" {
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
    [[ "$output" == *"no task registry at"* ]]
    [[ "$output" != *"manifest-unreadable"* ]]
}

# --- task scope across intervening headings ----------------------------------
#
# Real documents put prose headings between a task heading and its criteria.
# Resetting task scope on ANY other heading meant unresolved-on-done could never
# fire for those tasks. Scope now closes on a SIBLING or ANCESTOR heading only.

@test "acceptance-criteria: an intervening deeper heading does not drop task scope" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

### Context

Some prose about what was decided.

### Files

- `src/thing.ts`: the thing

### Acceptance criteria

- [ ] Docs updated
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"T-007"* ]]
}

@test "acceptance-criteria: a sibling heading does close task scope" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

Prose only.

## Appendix

**Acceptance criteria:**
- [ ] Not attached to any task
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # Scope closed, so the done rule of T-007 must not reach this section - but
    # the section is now reported as unbound rather than passed over in silence.
    [[ "$output" != *"unresolved-on-done"* ]]
    [[ "$output" == *"unbound-criteria-section"* ]]
}

# --- the shipped scaffolding passes its own gate -----------------------------

@test "acceptance-criteria: the shipped templates are clean under the report" {
    enable_gate
    cp "$AAHP_ROOT/templates/NEXT_ACTIONS.md" "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"
    cp "$AAHP_ROOT/templates/MANIFEST.json" "$TEST_TMPDIR/.ai/handoff/MANIFEST.json"
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

# --- importable without side effects -----------------------------------------

@test "acceptance-criteria: importing the module runs no report and exits nothing" {
    # The path travels in the environment, not in argv, so this process is not
    # the report's entry point and the guard in the module must keep it inert.
    run env AC_PATH="$AC" node -e "const { pathToFileURL } = require('node:url'); import(pathToFileURL(process.env.AC_PATH).href).then((m) => { const r = m.parseCriteriaSections('x.md', '## T-007: t\n\n**Acceptance criteria:**\n1. [ ] a\n'); const s = r.sections; if (s.length !== 1) throw new Error('sections ' + s.length); if (s[0].items.length !== 1) throw new Error('items ' + s[0].items.length); if (r.defects.length !== 0) throw new Error('defects ' + r.defects.length); console.log('IMPORT_OK'); });"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMPORT_OK"* ]]
    [[ "$output" != *"section(s)"* ]]
}

# --- offline by construction, proved statically ------------------------------
#
# Stronger than asserting the word "Offline" appears in the output: this walks
# the report's transitive relative-import graph and asserts no module in it can
# reach the network at all.

@test "acceptance-criteria: the report's module graph contains no network capability" {
    run node -e "const { readFileSync } = require('node:fs'); const { dirname, resolve } = require('node:path'); const seen = new Set(); const stack = [process.argv[1]]; const banned = /(?:node:)?(?:net|tls|http|https|http2|dgram|dns)['\"]|fetch\s*\(|XMLHttpRequest|WebSocket/; while (stack.length) { const f = resolve(stack.pop()); if (seen.has(f)) continue; seen.add(f); const src = readFileSync(f, 'utf8'); if (banned.test(src)) throw new Error('network capability in ' + f); for (const m of src.matchAll(/from\s+['\"](\.[^'\"]+)['\"]/g)) stack.push(resolve(dirname(f), m[1])); } console.log('OFFLINE_OK modules=' + seen.size);" "$AC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OFFLINE_OK"* ]]
}
# --- comprehension: the report refuses to pass on input it could not read ------
#
# Every test in this block was a silent "no findings" before the fail-loud
# redesign. Each fixture keeps a real, unresolved criterion on a task the
# registry marks `done`, so a clean verdict would be a false negative and not
# merely a missing nicety. They are still worth reporting now that the report
# has no authority over an exit code: a human reads them.

@test "acceptance-criteria: an include pathspec matching zero tracked files is a finding" {
    # The pathspec is one character off from the file that exists. Without this
    # finding the report says "0 section(s) in 0 file(s), no findings".
    mkconfig <<'EOF'
{ "acceptanceCriteria": { "include": [".ai/handoff/NEXT-ACTIONS.md"] } }
EOF
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] first thing
- [ ] second thing
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no-files-matched"* ]]
    [[ "$output" != *"no findings"* ]]
}

@test "acceptance-criteria: a matching pathspec does not report no-files-matched" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] still open, and that is fine
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

@test "acceptance-criteria: a code fence left open at end of file is a finding" {
    # CommonMark-correct behaviour: the closing fence is indented four spaces, so
    # it is content and the block runs to end of file. That is kept. What changes
    # is that the consequence is reported instead of silently swallowing the
    # criteria that follow.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

```
example block
    ```

**Acceptance criteria:**
- [ ] still unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unterminated-fence"* ]]
    [[ "$output" == *"line(s) after it were skipped"* ]]
}

@test "acceptance-criteria: the same document with the fence closed reports the real defect" {
    # The twin of the fixture above, one character different: the closing fence
    # is not indented. The criteria become visible and the done rule fires. This
    # is what proves the fence finding is about the skipped lines, not noise.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

```
example block
```

**Acceptance criteria:**
- [ ] still unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unterminated-fence"* ]]
    [[ "$output" == *"unresolved-on-done"* ]]
}

@test "acceptance-criteria: an empty criteria section is a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**

## Something else
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparsed-criteria-section"* ]]
}

@test "acceptance-criteria: criteria written as a table are a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**

| Criterion | Met |
|-----------|-----|
| ships     | no  |
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparsed-criteria-section"* ]]
}

@test "acceptance-criteria: criteria written as prose are a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**

The feature ships and the tests pass.
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparsed-criteria-section"* ]]
}

@test "acceptance-criteria: an indented criteria list is a finding, not silence" {
    # Indented items are detail lines by design. A section made only of them has
    # no criterion the report can read, which is the case this finding exists for.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**

  - [ ] indented and unresolved
  - [ ] also unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparsed-criteria-section"* ]]
}

@test "acceptance-criteria: a section with real criteria and nested detail is clean" {
    # The guard on the finding above: nested detail lines under a real criterion
    # must not make the section look unparsed.
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-008: Open task

**Acceptance criteria:**
- [ ] the criterion
  - a detail line
  - another detail line
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
}

@test "acceptance-criteria: a criteria section outside any task is a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## Appendix

**Acceptance criteria:**
- [ ] belongs to nothing
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unbound-criteria-section"* ]]
    [[ "$output" == *"not inside any task section"* ]]
}

@test "acceptance-criteria: a task id absent from the registry is a finding" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-999: A task the registry has never heard of

**Acceptance criteria:**
- [ ] unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unbound-criteria-section"* ]]
    [[ "$output" == *"T-999"* ]]
}

@test "acceptance-criteria: with no task registry at all binding is not judged" {
    # Absent registry means the done rule genuinely does not apply, so unbound is
    # not a defect - reporting it there would be noise with no possible fix.
    enable_gate
    next_actions <<'EOF'
## Appendix

**Acceptance criteria:**
- [ ] belongs to nothing
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
    [[ "$output" != *"unbound-criteria-section"* ]]
}

@test "acceptance-criteria: a tasks array is an unusable registry, not one task" {
    # An array satisfies `typeof x === "object"`. Treating it as a registry
    # reported a reassuring task count while no task id could ever match.
    enable_gate
    cat > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'EOF'
{
  "aahp_version": "3.0",
  "project": "fixture",
  "last_session": { "agent": "t", "session_id": "s", "timestamp": "2026-01-01T00:00:00Z", "phase": "idle" },
  "files": {},
  "quick_context": "fixture",
  "next_task_id": 9,
  "tasks": [ { "id": "T-007", "status": "done" } ]
}
EOF
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest-unreadable"* ]]
    [[ "$output" == *"is an array"* ]]
    [[ "$output" != *"1 task(s)"* ]]
}

@test "acceptance-criteria: a null tasks member is an unusable registry" {
    enable_gate
    cat > "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" <<'EOF'
{
  "aahp_version": "3.0",
  "project": "fixture",
  "last_session": { "agent": "t", "session_id": "s", "timestamp": "2026-01-01T00:00:00Z", "phase": "idle" },
  "files": {},
  "quick_context": "fixture",
  "next_task_id": 9,
  "tasks": null
}
EOF
    next_actions <<'EOF'
## T-007: Closed task

**Acceptance criteria:**
- [ ] unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest-unreadable"* ]]
}

# --- parser coverage: the heading forms that bind a task id ------------------

@test "acceptance-criteria: a setext heading binds a task id" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
T-007: Closed task
==================

Acceptance criteria
-------------------

- [ ] unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"T-007"* ]]
}

@test "acceptance-criteria: a bold label binds a task id" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
**T-007: Closed task**

**Acceptance criteria:**
- [ ] unresolved
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved-on-done"* ]]
    [[ "$output" == *"T-007"* ]]
}

# --- the reference implementation is conformant under its own gate -----------

@test "acceptance-criteria: this repository is clean under its own report" {
    run node "$AC" "$AAHP_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
    [[ "$output" != *"finding(s)"* ]]
}

# --- KNOWN BLIND SPOTS -------------------------------------------------------
#
# These tests assert what the report CURRENTLY DOES, which is to miss the
# criteria below. They are documented limitations, not bugs waiting on a fix,
# and they are the reason this code is a report and not a gate: no fixed set of
# patterns closes the space of shapes a human can write in Markdown. Each shape
# here is listed by name in README Section 8.7.
#
# If a future change makes one of these visible, that is an improvement: update
# the test AND the published blind-spot table together, and do NOT take it as
# licence to give the report authority over an exit code (ADR-017).

@test "acceptance-criteria: KNOWN BLIND SPOT - a bold line ends the criteria section" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007 Closed task
### Acceptance criteria
- [x] this one really is done

**Note:** the rest of the criteria follow.

- [ ] NOT DONE AND INVISIBLE
- [ ] ALSO NOT DONE AND INVISIBLE
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    # DOCUMENTED LIMITATION: the bold line closes the section, so the two
    # unresolved criteria after it are never seen and the done task reports
    # clean. A gate saying "OK" here is exactly the false confidence ADR-017
    # refuses to ship.
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
    [[ "$output" != *"unresolved-on-done"* ]]
}

@test "acceptance-criteria: KNOWN BLIND SPOT - a thematic break ends the criteria section" {
    enable_gate
    manifest_with_tasks
    next_actions <<'EOF'
## T-007 Closed task
### Acceptance criteria
- [x] this one really is done

***

- [ ] NOT DONE AND INVISIBLE
EOF
    gadd
    run node "$AC" "$TEST_TMPDIR"
    # DOCUMENTED LIMITATION: same shape, different terminator.
    [ "$status" -eq 0 ]
    [[ "$output" == *"no findings"* ]]
    [[ "$output" != *"unresolved-on-done"* ]]
}
