#!/usr/bin/env bats
# validate-json-schema.bats - scripts/validate-json-schema.mjs, the ajv-based
# schema validator CI runs over MANIFEST.json and aahp.config.json. It replaced
# `ajv-cli validate --spec=draft2020 -c ajv-formats`, so the tests below pin the
# three properties that invocation had: the draft 2020-12 dialect, ajv-formats in
# FULL mode, and ajv's default strict mode. Each would pass on a validator that
# silently accepted everything if only the green direction were tested, so every
# verdict is asserted with its exact exit code (0 valid, 1 invalid, 2 could not
# evaluate) and, for 1, with the error line that explains it.

load test_helper

VALIDATOR="$SCRIPTS_DIR/validate-json-schema.mjs"
MANIFEST_SCHEMA="$AAHP_ROOT/schema/aahp-manifest.schema.json"
CONFIG_SCHEMA="$AAHP_ROOT/schema/aahp-config.schema.json"

# A schema file under the test directory. $1 is the file name, $2 the body.
write_json() {
    printf '%s\n' "$2" > "$TEST_TMPDIR/$1"
}

# --- This repository's own files: what CI validates -------------------------

@test "this repository's MANIFEST.json is valid" {
    run node "$VALIDATOR" "$MANIFEST_SCHEMA" "$AAHP_ROOT/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$output" = "$AAHP_ROOT/.ai/handoff/MANIFEST.json valid" ]
}

@test "this repository's config and the shipped example are valid, one line each" {
    run node "$VALIDATOR" "$CONFIG_SCHEMA" "$AAHP_ROOT/aahp.config.json" "$AAHP_ROOT/aahp.config.example.json"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"aahp.config.json valid"* ]]
    [[ "$output" == *"aahp.config.example.json valid"* ]]
}

# --- Invalid documents: exit 1, and the message says where and why ----------

@test "a manifest task date left as the template placeholder is invalid, with the path and the format" {
    node -e '
      const fs = require("fs");
      const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      m.next_task_id = 2;
      m.tasks = { "T-001": { title: "t", status: "ready", created: "[ISO-8601]" } };
      fs.writeFileSync(process.argv[2], JSON.stringify(m, null, 2) + "\n");
    ' "$AAHP_ROOT/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/MANIFEST.json"
    grep -q '"created": "\[ISO-8601\]"' "$TEST_TMPDIR/MANIFEST.json"

    run node "$VALIDATOR" "$MANIFEST_SCHEMA" "$TEST_TMPDIR/MANIFEST.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$TEST_TMPDIR/MANIFEST.json invalid"* ]]
    [[ "$output" == *'/tasks/T-001/created must match format "date-time"'* ]]
}

@test "an unknown top-level manifest key is invalid and names the key" {
    node -e '
      const fs = require("fs");
      const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      m.project_name = "typo of project";
      fs.writeFileSync(process.argv[2], JSON.stringify(m, null, 2) + "\n");
    ' "$AAHP_ROOT/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/MANIFEST.json"

    run node "$VALIDATOR" "$MANIFEST_SCHEMA" "$TEST_TMPDIR/MANIFEST.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *'(root) must NOT have additional properties {"additionalProperty":"project_name"}'* ]]
}

@test "every error is listed, not only the first" {
    write_json schema.json '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"a":{"type":"string"},"b":{"type":"string"}}}'
    write_json data.json '{"a":1,"b":2}'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/data.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"/a must be string"* ]]
    [[ "$output" == *"/b must be string"* ]]
}

@test "one invalid file among valid ones is exit 1, and each file gets its own verdict" {
    write_json schema.json '{"type":"object","required":["a"]}'
    write_json good.json '{"a":1}'
    write_json bad.json '{}'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/good.json" "$TEST_TMPDIR/bad.json" "$TEST_TMPDIR/good.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"good.json valid"* ]]
    [[ "$output" == *"bad.json invalid"* ]]
    [[ "$output" == *"must have required property 'a'"* ]]
}

# --- The three properties of the replaced invocation ------------------------

@test "draft 2020-12: prefixItems is enforced" {
    # prefixItems exists only from 2020-12 on. A draft-07 ajv refuses this
    # schema (exit 2) or, non-strict, ignores the keyword (exit 0). Only a
    # 2020-12 validator rejects this document with exit 1.
    write_json schema.json '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"array","prefixItems":[{"type":"string"}]}'
    write_json data.json '[1]'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/data.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"/0 must be string"* ]]
}

@test "formats in full mode: a date-time on a day that does not exist is invalid" {
    # ajv-formats' "fast" mode checks only the shape of a date-time, so
    # 2023-02-29 passes there. The full mode CI used checks the calendar, and
    # scripts/aahp-schema.mjs (aahp doctor) mirrors that mode.
    write_json schema.json '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","format":"date-time"}'
    write_json leap.json '"2024-02-29T00:00:00Z"'
    write_json noleap.json '"2023-02-29T00:00:00Z"'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/leap.json"
    [ "$status" -eq 0 ]
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/noleap.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *'must match format "date-time"'* ]]
}

@test "strict mode: an unknown keyword in the schema is exit 2, never ignored" {
    # ajv's default strictSchema, which `ajv-cli validate` ran with. A typo such
    # as `requird` would otherwise make the schema accept what it meant to
    # reject, with every validation green.
    write_json schema.json '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","requird":["a"]}'
    write_json data.json '{}'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/data.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"schema $TEST_TMPDIR/schema.json is invalid"* ]]
    [[ "$output" == *'unknown keyword: "requird"'* ]]
}

@test "strict mode: an unknown format in the schema is exit 2, never ignored" {
    write_json schema.json '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","format":"no-such-format"}'
    write_json data.json '"x"'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/data.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *'unknown format "no-such-format"'* ]]
}

# --- Exit 2: could not evaluate ---------------------------------------------

@test "no arguments, or only a schema, is a usage error (exit 2)" {
    run node "$VALIDATOR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage: node scripts/validate-json-schema.mjs"* ]]
    run node "$VALIDATOR" "$MANIFEST_SCHEMA"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

@test "an ajv-cli flag is refused, not read as a file name" {
    run node "$VALIDATOR" -s "$MANIFEST_SCHEMA" -d "$AAHP_ROOT/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option -s"* ]]
}

@test "a data file that does not exist is exit 2, not a verdict" {
    run node "$VALIDATOR" "$MANIFEST_SCHEMA" "$TEST_TMPDIR/absent.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read data file $TEST_TMPDIR/absent.json (ENOENT)"* ]]
}

@test "a data file that is not JSON is exit 2, even next to a valid one" {
    printf '{ not json\n' > "$TEST_TMPDIR/broken.json"
    run node "$VALIDATOR" "$MANIFEST_SCHEMA" "$AAHP_ROOT/.ai/handoff/MANIFEST.json" "$TEST_TMPDIR/broken.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"MANIFEST.json valid"* ]]
    [[ "$output" == *"data file $TEST_TMPDIR/broken.json is not valid JSON"* ]]
}

@test "a schema file that does not exist is exit 2" {
    run node "$VALIDATOR" "$TEST_TMPDIR/absent-schema.json" "$AAHP_ROOT/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read schema $TEST_TMPDIR/absent-schema.json"* ]]
}

@test "without ajv installed it is exit 2 and names the install, never a pass" {
    # A copy outside any node_modules tree: module resolution from there finds
    # no ajv. NODE_PATH is cleared so a global path cannot supply one.
    mkdir -p "$TEST_TMPDIR/isolated/scripts"
    cp "$VALIDATOR" "$TEST_TMPDIR/isolated/scripts/"
    run env NODE_PATH= node "$TEST_TMPDIR/isolated/scripts/validate-json-schema.mjs" \
        "$MANIFEST_SCHEMA" "$AAHP_ROOT/.ai/handoff/MANIFEST.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot load ajv or ajv-formats"* ]]
    [[ "$output" == *"npm ci --ignore-scripts"* ]]
}

@test "a byte-order mark before the JSON is accepted, as Node's JSON loader does" {
    printf '\357\273\277{"a":"x"}\n' > "$TEST_TMPDIR/bom.json"
    write_json schema.json '{"type":"object","properties":{"a":{"type":"string"}}}'
    run node "$VALIDATOR" "$TEST_TMPDIR/schema.json" "$TEST_TMPDIR/bom.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bom.json valid"* ]]
}

# --- Importing it runs nothing ----------------------------------------------

@test "importing the module exposes createAjv and does not run the CLI" {
    run node --input-type=module -e '
      import { pathToFileURL } from "node:url";
      const mod = await import(pathToFileURL(process.argv[1]).href);
      const ajv = mod.createAjv();
      console.log("engine=" + ajv.constructor.name + " exitCode=" + (process.exitCode ?? "unset"));
    ' "$VALIDATOR"
    [ "$status" -eq 0 ]
    [ "$output" = "engine=Ajv2020 exitCode=unset" ]
}
