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
    # Write every present handoff file BEFORE create_manifest_json so the
    # handoff-set gate (which fails on a partial index) sees a complete index.
    echo "# GROUNDING" > "$h/GROUNDING.md"
    cat > "$h/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Provenance | Notes |
|----------|--------|------------|-------|
| build passes | verified | test_verified | ok |
EOF
    create_manifest_json "$h"
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
        if (r.schemaVersion !== 2) process.exit(2);
        const keys = ["handoff-set","manifest-schema","grounding","pinned-dep","changelog-format","version-sync","verify-workflow"];
        for (const k of keys) if (!(k in r.gates)) process.exit(3);
        if (typeof r.checkedAt !== "string") process.exit(4);
        if (typeof r.aahpVersion !== "string") process.exit(5);
        // schemaVersion 2 additions. `gates` above is unchanged from 1.
        for (const k of keys) {
          if (!(k in r.gateOutcomes)) process.exit(6);
          if (typeof r.gateOutcomes[k].outcome !== "string") process.exit(7);
          if (typeof r.gateOutcomes[k].reason !== "string") process.exit(8);
        }
        if (typeof r.evaluated !== "number") process.exit(9);
        if (r.total !== keys.length) process.exit(10);
      });
    '
}

# --- the summary counts gates that RAN, not gates that exist ------------------
#
# `Conformance OK: 7 gate(s), no failures.` was printed over seven skips and
# zero evaluations. README positions that line, and the record beside it, as the
# conformance evidence a fleet dashboard and a consumer's own pull request read.

@test "doctor: a tree where every gate skips reports NOT EVALUATED, never a count" {
    # Nothing here for any gate: no config, no CHANGELOG, no workflows, no
    # .ai/handoff. The old build printed 'Conformance OK: 7 gate(s)' and exit 0.
    rm -rf "$TEST_TMPDIR/.ai"
    printf '{"name":"empty","version":"1.0.0","private":true}\n' > "$TEST_TMPDIR/package.json"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conformance NOT EVALUATED: 0 of 7 gate(s) ran. This is not a pass."* ]]
    [[ "$output" != *"Conformance OK"* ]]
}

@test "doctor: the OK summary names how many gates ran, not how many exist" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # MEASURED on Linux, not guessed: the three handoff gates plus pinned-dep
    # evaluate; changelog-format, version-sync and verify-workflow have nothing
    # to check in this fixture.
    [[ "$output" == *"Conformance OK: 4 of 7 gate(s) ran, no failures."* ]]
    [[ "$output" != *"Conformance OK: 7 gate(s)"* ]]
}

@test "doctor --json: zero evaluated exits 1, the same verdict as the text path" {
    # The two paths must not disagree about one tree. --json is the one CI and a
    # dashboard consume, so it is the wrong half to leave green.
    rm -rf "$TEST_TMPDIR/.ai"
    printf '{"name":"empty","version":"1.0.0","private":true}\n' > "$TEST_TMPDIR/package.json"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"evaluated": 0'* ]]
}

@test "doctor --quiet: an all-skipped tree still states the result, never zero bytes" {
    # A quiet CI run that printed nothing and exited 0 is an empty log under a
    # green tick, which is the shape of the whole defect.
    rm -rf "$TEST_TMPDIR/.ai"
    printf '{"name":"empty","version":"1.0.0","private":true}\n' > "$TEST_TMPDIR/package.json"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --quiet
    [ "$status" -eq 1 ]
    [ -n "$output" ]
    [[ "$output" == *"NOT EVALUATED"* ]]
}

@test "doctor --quiet: a passing run states the result too" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR" --quiet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conformance OK: 4 of 7 gate(s) ran, no failures."* ]]
}

@test "doctor --json: the record separates governance-mode skips from not-applicable" {
    # The defect: `gates` said `skip` for both, so a dashboard could not tell a
    # gate that was DECLINED from one whose precondition was absent.
    scaffold_conformant
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        // Unchanged from schemaVersion 1: both are still `skip` in `gates`.
        for (const k of ["handoff-set", "changelog-format"]) {
          if (r.gates[k] !== "skip") process.exit(2);
        }
        // New in 2: they are no longer the same token.
        if (r.gateOutcomes["handoff-set"].outcome !== "unevaluated") process.exit(3);
        if (r.gateOutcomes["changelog-format"].outcome !== "not-applicable") process.exit(4);
        if (r.gateOutcomes["handoff-set"].outcome === r.gateOutcomes["changelog-format"].outcome) process.exit(5);
        if (r.evaluated !== 1) process.exit(6);
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

@test "doctor: handoff-set fails when a canonical file is present but not indexed" {
    scaffold_conformant
    local h="$TEST_TMPDIR/.ai/handoff"
    # Leave TRUST.md on disk, drop it from the MANIFEST files index only.
    echo "# STATUS" > "$h/STATUS.md"
    create_manifest_json "$h"
    node -e '
      const fs = require("fs");
      const p = process.argv[1];
      const m = JSON.parse(fs.readFileSync(p, "utf8"));
      delete m.files["TRUST.md"];
      fs.writeFileSync(p, JSON.stringify(m, null, 2) + "\n");
    ' "$h/MANIFEST.json"
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not indexed"* ]]
    [[ "$output" == *"TRUST.md"* ]]
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

# --- manifest-schema: the WHOLE schema, not a structural subset ---------------
#
# The gate used to hand-check a subset (required keys, the phase enum, the
# checksum pattern) and print "structural checks against
# aahp-manifest.schema.json pass". Measured at 1917ca8: `aahp init` followed by
# `aahp manifest` leaves the template's example tasks with
# "created": "[ISO-8601]" in MANIFEST.json, doctor printed that PASS line, and
# ajv (what CI runs against the same schema) rejected the file with
# 'must match format "date-time"'.

# Merge JSON $1 into the fixture's MANIFEST.json (shallow, top level).
_manifest_merge() {
    node -e '
      const fs = require("fs");
      const p = process.argv[1];
      const m = JSON.parse(fs.readFileSync(p, "utf8"));
      Object.assign(m, JSON.parse(process.argv[2]));
      fs.writeFileSync(p, JSON.stringify(m, null, 2) + "\n");
    ' "$TEST_TMPDIR/.ai/handoff/MANIFEST.json" "$1"
}

@test "doctor: manifest-schema FAILS a task date left as the template placeholder" {
    scaffold_conformant
    _manifest_merge '{ "next_task_id": 2, "tasks": { "T-001": { "title": "t", "status": "ready", "created": "[ISO-8601]" } } }'
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL     manifest-schema: /tasks/T-001/created"* ]]
    [[ "$output" == *"unreplaced template placeholder"* ]]
    [[ "$output" == *"Conformance FAILED: manifest-schema."* ]]
}

@test "doctor: manifest-schema FAILS a task priority outside the schema enum" {
    scaffold_conformant
    _manifest_merge '{ "tasks": { "T-001": { "title": "t", "status": "ready", "priority": "urgent" } } }'
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"manifest-schema": "fail"'* ]]
    [[ "$output" == *"/tasks/T-001/priority"* ]]
}

@test "doctor: manifest-schema FAILS an unknown top-level key (additionalProperties)" {
    scaffold_conformant
    _manifest_merge '{ "project_name": "typo of project" }'
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *'unknown key "project_name"'* ]]
}

@test "doctor: manifest-schema PASSES valid tasks and says it checked the whole schema" {
    scaffold_conformant
    _manifest_merge '{ "next_task_id": 3, "tasks": {
        "T-001": { "title": "a", "status": "done", "priority": "high", "created": "2026-01-01T00:00:00Z", "completed": "2026-01-02T10:30:00.5+02:00" },
        "T-002": { "title": "b", "status": "ready", "depends_on": ["T-001"], "created": "2026-01-03t00:00:00z" } } }'
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS     manifest-schema: MANIFEST.json validates against schema/aahp-manifest.schema.json"* ]]
    [[ "$output" != *"structural checks"* ]]
}

@test "doctor: the text header reads 'aahp doctor: conformance for', not '-conformance'" {
    scaffold_conformant
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aahp doctor: conformance for "* ]]
    [[ "$output" != *"doctor -conformance"* ]]
}

@test "manifest validator: same verdict as ajv (CI's validator) on every case in the corpus" {
    # The doctor gate and the ajv validation in CI read the same schema. If they
    # could disagree, doctor would be green on a manifest CI rejects (or the
    # reverse). This runs both over the same corpus and fails on any split.
    # The ajv side is createAjv() from scripts/validate-json-schema.mjs, the
    # exact instance CI validates with (draft 2020-12, ajv-formats full mode,
    # ajv's default strict mode), not a second hand-built copy of it.
    [ -d "$AAHP_ROOT/node_modules/ajv" ] || { echo "ajv devDependency missing: run npm ci"; false; }
    run node -e '
      const path = require("path");
      const fs = require("fs");
      const url = require("url");
      const root = process.argv[1];
      const load = (rel) => import(url.pathToFileURL(path.join(root, rel)).href);
      Promise.all([load("scripts/validate-json-schema.mjs"), load("scripts/aahp-schema.mjs")]).then(([ci, mod]) => {
      const ajv = ci.createAjv();
      console.log("oracle=" + ajv.constructor.name);
      const schema = JSON.parse(fs.readFileSync(path.join(root, "schema/aahp-manifest.schema.json"), "utf8"));
      const ajvValid = ajv.compile(schema);
      const sum = "sha256:" + "a".repeat(64);
      const file = { checksum: sum, updated: "2026-01-01T00:00:00Z", lines: 1, summary: "s" };
      const base = () => ({
        aahp_version: "3.0", project: "p",
        last_session: { agent: "a", timestamp: "2026-01-01T00:00:00Z", phase: "idle" },
        files: { "STATUS.md": { ...file }, "pii-allowlist.json": { ...file } },
        quick_context: "q", next_task_id: 2,
        tasks: { "T-001": { title: "t", status: "ready", created: "2026-01-01T00:00:00Z" } },
      });
      const cases = {
        baseline: (m) => m,
        placeholderCreated: (m) => { m.tasks["T-001"].created = "[ISO-8601]"; },
        dateOnly: (m) => { m.tasks["T-001"].created = "2026-01-01"; },
        noOffset: (m) => { m.tasks["T-001"].created = "2026-01-01T00:00:00"; },
        offsetNoColon: (m) => { m.tasks["T-001"].created = "2026-01-01T00:00:00+0100"; },
        offsetHoursOnly: (m) => { m.tasks["T-001"].created = "2026-01-01T00:00:00+01"; },
        spaceSeparator: (m) => { m.tasks["T-001"].created = "2026-01-01 00:00:00Z"; },
        lowercase: (m) => { m.tasks["T-001"].created = "2026-01-01t00:00:00z"; },
        fraction: (m) => { m.tasks["T-001"].created = "2026-01-01T00:00:00.123456Z"; },
        leapSecondUtc: (m) => { m.tasks["T-001"].created = "2016-12-31T23:59:60Z"; },
        leapSecondOffset: (m) => { m.tasks["T-001"].created = "2016-12-31T15:59:60-08:00"; },
        leapSecondWrongHour: (m) => { m.tasks["T-001"].created = "2016-12-31T22:59:60Z"; },
        feb29Leap: (m) => { m.tasks["T-001"].created = "2024-02-29T00:00:00Z"; },
        feb29NonLeap: (m) => { m.tasks["T-001"].created = "2023-02-29T00:00:00Z"; },
        feb29Century: (m) => { m.tasks["T-001"].created = "1900-02-29T00:00:00Z"; },
        month13: (m) => { m.tasks["T-001"].created = "2026-13-01T00:00:00Z"; },
        hour24: (m) => { m.tasks["T-001"].created = "2026-01-01T24:00:00Z"; },
        tzHour24: (m) => { m.tasks["T-001"].created = "2026-01-01T00:00:00+24:00"; },
        timestampWords: (m) => { m.last_session.timestamp = "yesterday"; },
        fileUpdatedPlaceholder: (m) => { m.files["STATUS.md"].updated = "[ISO-8601]"; },
        badStatus: (m) => { m.tasks["T-001"].status = "todo"; },
        badPriority: (m) => { m.tasks["T-001"].priority = "urgent"; },
        badPhase: (m) => { m.last_session.phase = "coding"; },
        badTaskId: (m) => { m.tasks["T-1"] = { title: "x", status: "ready" }; },
        badDependsOn: (m) => { m.tasks["T-001"].depends_on = ["task-1"]; },
        extraTaskKeyAllowed: (m) => { m.tasks["T-001"].notes = "free text"; },
        titleTooLong: (m) => { m.tasks["T-001"].title = "x".repeat(201); },
        titleAtLimit: (m) => { m.tasks["T-001"].title = "x".repeat(200); },
        quickContextTooLong: (m) => { m.quick_context = "q".repeat(501); },
        summaryAstralAtLimit: (m) => { m.files["STATUS.md"].summary = "\u{1F600}".repeat(200); },
        unknownTopKey: (m) => { m.project_name = "x"; },
        missingProject: (m) => { delete m.project; },
        fileNotMdOrJson: (m) => { m.files["notes.txt"] = { ...file }; },
        otherJsonFile: (m) => { m.files["other.json"] = { ...file }; },
        fileMissingSummary: (m) => { delete m.files["STATUS.md"].summary; },
        badChecksum: (m) => { m.files["STATUS.md"].checksum = "sha256:[hash]"; },
        negativeLines: (m) => { m.files["STATUS.md"].lines = -1; },
        nextTaskIdString: (m) => { m.next_task_id = "2"; },
        nextTaskIdZero: (m) => { m.next_task_id = 0; },
        crossRepoOk: (m) => { m.cross_repo_ref = { repo: "o/r", commit: "abc", relation: "extends" }; },
        crossRepoMissingRelation: (m) => { m.cross_repo_ref = { repo: "o/r", commit: "abc" }; },
        crossRepoBadRelation: (m) => { m.cross_repo_ref = { repo: "o/r", commit: "abc", relation: "copies" }; },
        tokenBudgetNegative: (m) => { m.token_budget = { full_read: -1 }; },
        durationFloat: (m) => { m.last_session.duration_minutes = 1.5; },
      };
        let splits = 0, accepted = 0, rejected = 0;
        for (const [name, mutate] of Object.entries(cases)) {
          const m = base();
          mutate(m);
          const a = ajvValid(m);
          const mine = mod.validateManifestObject(m).length === 0;
          if (a !== mine) { splits++; console.log("SPLIT " + name + ": ajv=" + a + " in-repo=" + mine); }
          if (a) accepted++; else rejected++;
        }
        console.log("cases=" + Object.keys(cases).length + " accepted=" + accepted + " rejected=" + rejected + " splits=" + splits);
        process.exit(splits === 0 ? 0 : 1);
      });
    ' "$AAHP_ROOT"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"oracle=Ajv2020"* ]]
    [[ "$output" == *"splits=0"* ]]
    # Both verdicts are exercised, so agreement is not agreement on "all valid".
    [[ "$output" != *"accepted=0 "* ]]
    [[ "$output" != *"rejected=0 "* ]]
}

@test "manifest validator: a schema format it does not implement is refused, never skipped" {
    run node -e '
      const url = require("url");
      import(url.pathToFileURL(process.argv[1]).href).then(function (m) {
        try {
          m.assertSupported({ type: "object", properties: { a: { type: "string", format: "email" } } });
          console.error("assertSupported accepted an unimplemented format");
          process.exit(1);
        } catch (e) {
          if (e.code !== "AAHP_SCHEMA_UNSUPPORTED") { console.error("wrong code " + e.code); process.exit(1); }
          console.log("refused-format");
        }
        try {
          m.assertSupported({ type: "object", properties: { a: { $ref: "https://example.com/s.json" } } });
          console.error("assertSupported accepted a remote $ref");
          process.exit(1);
        } catch (e) {
          if (e.code !== "AAHP_SCHEMA_UNSUPPORTED") { console.error("wrong code " + e.code); process.exit(1); }
          console.log("refused-ref");
        }
      });
    ' "$AAHP_ROOT/scripts/aahp-schema.mjs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"refused-format"* ]]
    [[ "$output" == *"refused-ref"* ]]
}

@test "doctor: --quiet prints only failing gates" {
    scaffold_conformant
    # Fail grounding only (no Provenance column). Do not delete an indexed file:
    # that would also fail handoff-set after the partial-index alignment.
    cat > "$TEST_TMPDIR/.ai/handoff/TRUST.md" <<'EOF'
# Trust Register

| Property | Status | Notes |
|----------|--------|-------|
| build passes | verified | ok |
EOF
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

@test "doctor --governance --json emits mode:governance with all seven gate keys and the 3 handoff gates skip" {
    scaffold_conformant
    rm -rf "$TEST_TMPDIR/.ai"
    run node "$AAHP" doctor "$TEST_TMPDIR" --governance --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        if (r.mode !== "governance") process.exit(2);
        const keys = ["handoff-set","manifest-schema","grounding","pinned-dep","changelog-format","version-sync","verify-workflow"];
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

# --- Handoff content drift: the boundary doctor does NOT cross (issue 72) -----
#
# `gateHandoffSet` compares the file SET and the INDEX and hashes nothing.
# Comparing a recorded checksum against the bytes on disk is `aahp verify`
# Layer 1's job, by ADR-011. These three tests hold that boundary from both
# sides: doctor stays green AND says what it did not compare, and the drift the
# other two rely on is proved to be real drift.

# Conformant fixture, then STATUS.md content changed WITHOUT regenerating
# MANIFEST.json. Byte length and line count are preserved on purpose, so the
# content hash is the only thing that differs from the recorded entry and no
# other gate has a second reason to notice.
scaffold_drifted_handoff() {
    scaffold_conformant
    local h="$TEST_TMPDIR/.ai/handoff"
    printf '# STATUS\n\nrecorded body aaaa\n' > "$h/STATUS.md"
    create_manifest_json "$h"
    printf '# STATUS\n\ndrifted body bbbbb\n' > "$h/STATUS.md"
}

@test "doctor: the handoff-set pass reason names the content check it did not run" {
    scaffold_drifted_handoff
    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no strays (content not compared; aahp verify Layer 1 owns checksum integrity)"* ]]
}

@test "doctor --json: handoff-set stays pass on content drift (ADR-011 boundary, not scope creep)" {
    scaffold_drifted_handoff
    run node "$AAHP" doctor "$TEST_TMPDIR" --json
    [ "$status" -eq 0 ]
    echo "$output" | node -e '
      let s = "";
      process.stdin.on("data", (d) => (s += d)).on("end", () => {
        const r = JSON.parse(s);
        if (r.gates["handoff-set"] !== "pass") process.exit(2);
        if (r.gates["manifest-schema"] !== "pass") process.exit(3);
        // The --json record carries the same caveat the text output prints
        // (bin/aahp.js, the LIMIT OF THIS WORDING note above gateHandoffSet).
        const why = r.gateOutcomes && r.gateOutcomes["handoff-set"] && r.gateOutcomes["handoff-set"].reason;
        if (!/content not compared; aahp verify Layer 1 owns checksum integrity/.test(why || "")) process.exit(4);
      });
    '
}

@test "doctor drift fixture: aahp verify DOES see the drift (guard for the two tests above)" {
    scaffold_drifted_handoff
    run bash "$SCRIPTS_DIR/verify-handoff.sh" "$TEST_TMPDIR" --level precommit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Checksum mismatch: STATUS.md"* ]]
}
