#!/usr/bin/env bats
# inert-controls.bats - one suite for one class of defect: a control that does
# not do what it says.
#
# Issues #84, #82 and #80 are the same shape. In each, something published as a
# guarantee could not fail:
#
#   #84  aahp.config.json was never validated against its own schema, so
#        `forbiddenPatterns` misspelled by one letter read as an absent section,
#        an absent section is "not applicable", and "not applicable" is a clean
#        SKIP. A failing gate reported `Governance OK`, exit 0.
#   #82  `npx --no-install <name>` does not prevent a registry fetch. npx is
#        npm exec, which has no such option and ignores it silently. The shipped
#        workflow and the shipped git hooks resolved the UNSCOPED public name
#        `aahp`, which this project does not own.
#   #80  `.ai/handoff/.aiignore` is read by nothing, while the README and the
#        shipped template said CI validates its patterns.
#
# WHAT THIS FILE ASSERTS, AND WHY IT IS NOT THREE HAPPY-PATH TESTS
# ---------------------------------------------------------------
# Three tests each asserting "the control passes today" would close nothing:
# every one of these defects passed on the day it shipped. So every test below
# asserts that a control CAN FAIL, against a fixture that is really in violation,
# and each failing assertion is paired with a positive control proving the
# harness is live. Where a green run is genuinely correct, the test additionally
# asserts the run says which question was NOT asked, because "not assessed"
# reported as "passed" is the defect, not a presentation detail.
#
# MUTATION ANCHORS - the exact line a reviewer deletes to turn each test red is
# named in the test body. Every one was checked by deleting it.
#
# ASCII-only, like check.bats: the em-dash CHAR used as the violation fixture is
# written with octal printf (\342\200\224), and the em-dash REGEX inside
# aahp.config.json as a JSON unicode escape whose backslash is octal (\134).

load test_helper

AAHP="$AAHP_ROOT/bin/aahp.js"

# A fixture repo that is REALLY in violation: README.md carries a genuine U+2014
# and the config bans it. Every #84 test runs against this, so a green result is
# always a green result over a live violation.
scaffold_violating_repo() {
    printf '{ "name": "fx", "version": "1.0.0", "private": true }\n' > "$TEST_TMPDIR/package.json"
    printf '# fx\n\na \342\200\224 b\n' > "$TEST_TMPDIR/README.md"
    printf '{ "forbiddenPatterns": [ { "id": "em-dash", "pattern": "\134u2014", "message": "em dash banned" } ] }\n' > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add -A
}

# Overwrite the config and re-stage, so the tracked-file gates still enumerate.
# `%b` (not `%s`) so a caller can write the em-dash regex's leading backslash as
# octal \134 and keep this file pure ASCII, exactly as check.bats does.
put_config() {
    printf '%b\n' "$1" > "$TEST_TMPDIR/aahp.config.json"
    git -C "$TEST_TMPDIR" add -A
}

# Put a recording stub for `npx` at the front of PATH. Any invocation appends a
# line to $NPX_LOG and EXITS 0 printing a version, i.e. the stub behaves like a
# registry fetch that SUCCEEDED. A hook that still consults npx therefore takes
# the CLI branch and the log is non-empty; the assertion is about the log, not
# about the hook's exit code, so it cannot be satisfied by a lucky failure.
install_npx_spy() {
    NPX_LOG="$TEST_TMPDIR/npx-invocations.log"
    export NPX_LOG
    mkdir -p "$TEST_TMPDIR/spybin"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "%%s\\n" "npx $*" >> "$NPX_LOG"\n'
        printf 'echo 3.10.0\n'
        printf 'exit 0\n'
    } > "$TEST_TMPDIR/spybin/npx"
    chmod +x "$TEST_TMPDIR/spybin/npx"
    : > "$NPX_LOG"
    # PATH entries are colon-separated, so a Windows drive path (C:/...) splits
    # into "C" and "/...", the stub is never found, and every assertion below
    # would pass vacuously. TEST_TMPDIR is a mixed-mode path on Git Bash, so
    # convert it back to a POSIX path before prepending. The "spy control" test
    # asserts the conversion actually worked.
    local spydir="$TEST_TMPDIR/spybin"
    if command -v cygpath >/dev/null 2>&1; then
        spydir="$(cygpath -u "$spydir")"
    fi
    PATH="$spydir:$PATH"
    export PATH
}

# ---------------------------------------------------------------------------
# #84 - the gate over the gates
# ---------------------------------------------------------------------------

@test "84 positive control: with the config spelled correctly the gate really fails" {
    # Without this the next tests prove nothing: a green run on a fixture that is
    # not in violation is not evidence of anything.
    scaffold_violating_repo
    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Governance FAILED: forbidden-patterns"* ]]
}

@test "84 check: a one-letter typo in a gate key is an error, not a skip" {
    # THE class test. Anchor: the `if (configProblem)` block in cmdCheck
    # (bin/aahp.js). Delete it and this goes back to `Governance OK`, exit 0.
    scaffold_violating_repo
    put_config '{ "forbiddenPaterns": [ { "id": "em-dash", "pattern": "\134u2014" } ] }'

    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    # Not merely non-zero: it must NOT read as a pass, and it must name the key.
    [[ "$output" != *"Governance OK"* ]]
    [[ "$output" == *"forbiddenPaterns"* ]]
    [[ "$output" == *"did you mean"* ]]
    [[ "$output" == *"forbiddenPatterns"* ]]
}

@test "84 check: the summary distinguishes NOT EVALUATED from passed and from failed" {
    # "could not answer" must be a third outcome. Anchor: the
    # 'Governance NOT EVALUATED' console.log in cmdCheck.
    scaffold_violating_repo
    put_config '{ "docLinks": {}, "nonsenseKey": 1 }'

    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOT EVALUATED"* ]]
    [[ "$output" == *"no gate ran"* ]]
    [[ "$output" != *"Governance FAILED"* ]]
}

@test "84 check: an unparseable config is an error, not eight skips" {
    # readJsonSafe returned null and the caller substituted {}, so a config that
    # was not even JSON produced "Governance OK: 0 gate(s) ran". Anchor: the
    # JSON.parse catch inside readConfigOrExplain.
    scaffold_violating_repo
    put_config '{ this is not json'

    run node "$AAHP" check "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" != *"Governance OK"* ]]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "84 check --json: an unvalidated gate is 'unevaluated', never 'skip'" {
    # A dashboard reading the record must be able to tell "asked, not applicable"
    # from "never asked". Anchor: the `gates[gate.id] = 'unevaluated'` loop.
    scaffold_violating_repo
    put_config '{ "forbiddenPaterns": [ { "id": "em-dash", "pattern": "\134u2014" } ] }'

    node "$AAHP" check "$TEST_TMPDIR" --json > "$TEST_TMPDIR/record.json" || true
    run node -e '
      const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      if (r.config.valid !== false) { console.error("config.valid not false"); process.exit(1); }
      const vals = Object.values(r.gates);
      if (vals.length === 0) { console.error("no gates in record"); process.exit(1); }
      if (vals.includes("skip")) { console.error("a gate collapsed into skip"); process.exit(1); }
      if (!vals.every(function (v) { return v === "unevaluated"; })) { console.error("not all unevaluated: " + vals.join(",")); process.exit(1); }
      console.log("ok");
    ' "$TEST_TMPDIR/record.json"
    [ "$status" -eq 0 ]
}

@test "84 doctor: an invalid config is an error there too" {
    # check and doctor must not disagree about a config neither can read.
    scaffold_violating_repo
    put_config '{ "pinnedDeps": { "name": "x" } }'

    run node "$AAHP" doctor "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" != *"Conformance OK"* ]]
    [[ "$output" == *"pinnedDeps"* ]]
}

@test "84 doctor: the unevaluated record names exactly the gates the real record names" {
    # The invalid-config path in cmdDoctor writes its own gate-id list, and a
    # gate added to the real record but not to that list would vanish from the
    # record precisely when the config is broken - a gate silently absent from a
    # record is this whole class of defect again, one level down. This binds the
    # two lists by comparing the KEY SETS of the two records.
    scaffold_violating_repo
    printf '{ "name": "fx", "version": "1.0.0", "devDependencies": { "@elvatis_com/aahp": "3.10.0" } }\n' > "$TEST_TMPDIR/package.json"
    put_config '{ "docLinks": { "include": ["README.md"] } }'
    node "$AAHP" doctor "$TEST_TMPDIR" --json > "$TEST_TMPDIR/valid.json" || true

    put_config '{ "docLinks": { "include": ["README.md"] }, "bogusKey": 1 }'
    node "$AAHP" doctor "$TEST_TMPDIR" --json > "$TEST_TMPDIR/invalid.json" || true

    run node -e '
      const fs = require("fs");
      const a = Object.keys(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).gates).sort();
      const b = Object.keys(JSON.parse(fs.readFileSync(process.argv[2], "utf8")).gates).sort();
      if (a.length === 0) { console.error("valid record has no gates"); process.exit(1); }
      if (a.join(",") !== b.join(",")) {
        console.error("gate sets differ\n  valid:   " + a.join(",") + "\n  invalid: " + b.join(","));
        process.exit(1);
      }
      console.log("gate sets identical: " + a.join(","));
    ' "$TEST_TMPDIR/valid.json" "$TEST_TMPDIR/invalid.json"
    [ "$status" -eq 0 ]
}

@test "84 direct gate: a gate run outside the aggregate also refuses the config" {
    # package.json's "check" script chain invokes the gates directly, not through
    # `aahp check`, so validating only in the CLI would leave that path open.
    # Anchor: the `if (strict)` block in loadConfig (scripts/aahp-config.mjs).
    scaffold_violating_repo
    put_config '{ "forbiddenPatterns": [ { "id": "x", "patern": "\134u2014" } ] }'

    run node "$AAHP_ROOT/scripts/check-forbidden-patterns.mjs" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
    # Assert the SCHEMA refusal, not merely a non-zero exit and not merely the
    # string "patern" anywhere in the output. Without the loader validation this
    # gate still exits 1, because `new RegExp(undefined)` matches broadly and
    # produces a wall of false positives - which is the OTHER half of #84 - and
    # one of those false positives quotes the config line containing "patern".
    # An assertion on that substring alone was green under the mutation.
    [[ "$output" == *'missing required key "pattern"'* ]]
    [[ "$output" != *"Forbidden-pattern check failed"* ]]
}

@test "84 criteria: the advisory report REPORTS the invalid config and still exits 0" {
    # The report has no authority by design (README 8.7): it is not in
    # CHECK_GATES, it has no enforcing mode, and it exits 0 whatever it finds.
    # Making it hard-fail on a schema problem would hand it authority through the
    # back door, over a property it does not even read. So it loads the config
    # NON-strict and reports the schema errors as findings.
    # Anchor: the `config-schema` findings.push in report-acceptance-criteria.mjs.
    scaffold_violating_repo
    mkdir -p "$TEST_TMPDIR/.ai/handoff"
    printf '# t\n' > "$TEST_TMPDIR/.ai/handoff/NEXT_ACTIONS.md"
    put_config '{ "acceptanceCriteria": { "includ": [".ai/handoff/NEXT_ACTIONS.md"] } }'

    run node "$AAHP" criteria "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"config-schema"* ]]
    [[ "$output" == *"includ"* ]]
}

@test "84 validator: an unimplemented schema keyword is loud, not silently skipped" {
    # A partial validator that ignores what it does not implement reports "valid"
    # for a document it never fully examined - the same defect one level up.
    # Anchor: the `throw` inside assertSupported (scripts/aahp-schema.mjs).
    run node -e '
      const url = require("url");
      import(url.pathToFileURL(process.argv[1]).href).then(function (m) {
        try {
          m.assertSupported({ type: "object", properties: { a: { oneOf: [{ type: "string" }] } } });
          console.error("assertSupported accepted an unimplemented keyword");
          process.exit(1);
        } catch (e) {
          if (e.code !== "AAHP_SCHEMA_UNSUPPORTED") { console.error("wrong code " + e.code); process.exit(1); }
          console.log("refused-unsupported");
        }
      });
    ' "$AAHP_ROOT/scripts/aahp-schema.mjs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"refused-unsupported"* ]]
}

@test "84 validator: a missing schema file is an error, never a pass" {
    # An incomplete install must not read as a clean config.
    run node -e '
      const url = require("url");
      import(url.pathToFileURL(process.argv[1]).href).then(function (m) {
        try {
          m.validateConfigObject({}, "definitely-not-here.json");
          console.error("validated against a schema that does not exist");
          process.exit(1);
        } catch (e) {
          if (e.code !== "AAHP_SCHEMA_MISSING") { console.error("wrong code " + e.code); process.exit(1); }
          console.log("refused-missing");
        }
      });
    ' "$AAHP_ROOT/scripts/aahp-schema.mjs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"refused-missing"* ]]
}

@test "84 dogfood: this repository's own configs match the schema it ships" {
    run node -e '
      const url = require("url");
      const fs = require("fs");
      import(url.pathToFileURL(process.argv[1]).href).then(function (m) {
        let bad = 0;
        for (const f of [process.argv[2], process.argv[3]]) {
          const errs = m.validateConfigObject(JSON.parse(fs.readFileSync(f, "utf8")));
          if (errs.length) { console.error(m.formatConfigErrors(errs, f)); bad++; }
        }
        process.exit(bad === 0 ? 0 : 1);
      });
    ' "$AAHP_ROOT/scripts/aahp-schema.mjs" "$AAHP_ROOT/aahp.config.json" "$AAHP_ROOT/aahp.config.example.json"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# #82 - no shipped code path may reach the registry
# ---------------------------------------------------------------------------

@test "82 spy control: the npx stub is on PATH and does get recorded when called" {
    # Positive control for the three tests below. Without it, an empty log would
    # be consistent with a spy that was never reachable, and all of them would
    # pass vacuously on any machine where `command -v npx` misses the stub.
    install_npx_spy
    run command -v npx
    [ "$status" -eq 0 ]
    [[ "$output" == *"spybin"* ]]
    npx --no-install aahp --version >/dev/null 2>&1 || true
    run cat "$NPX_LOG"
    [[ "$output" == *"aahp"* ]]
}

@test "82 pre-commit: with nothing installed the hook skips and never calls npx" {
    # Anchor: the `[ -f "$AAHP_CLI" ]` guard in scripts/hooks/pre-commit. Restore
    # the old `npx --no-install aahp --version` guard and the log is non-empty.
    install_npx_spy
    cd "$TEST_TMPDIR"
    run bash "$AAHP_ROOT/scripts/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping gate"* ]]
    [ ! -s "$NPX_LOG" ]
}

@test "82 pre-push: with nothing installed the hook skips and never calls npx" {
    # Anchor: the `[ -f "$AAHP_CLI" ]` guards in scripts/hooks/pre-push (both the
    # verify branch and the doctor branch).
    install_npx_spy
    cd "$TEST_TMPDIR"
    run bash "$AAHP_ROOT/scripts/hooks/pre-push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping gate"* ]]
    [ ! -s "$NPX_LOG" ]
}

@test "82 pre-commit: with the package installed the hook runs it BY PATH, still no npx" {
    # The skip must not be the only way to avoid npx: the WORKING path must avoid
    # it too, or the fix would just be a disabled feature.
    install_npx_spy
    mkdir -p "$TEST_TMPDIR/node_modules/@elvatis_com/aahp/bin"
    printf 'console.log("STUB-CLI " + process.argv.slice(2).join(" "));\n' \
        > "$TEST_TMPDIR/node_modules/@elvatis_com/aahp/bin/aahp.js"

    cd "$TEST_TMPDIR"
    run bash "$AAHP_ROOT/scripts/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STUB-CLI"* ]]
    [[ "$output" == *"verify"* ]]
    [[ "$output" == *"--level precommit"* ]]
    [ ! -s "$NPX_LOG" ]
}

@test "82 no EXECUTABLE line in shipped code invokes npx" {
    # The hooks and the govern workflow are COPIED into adopter repositories, so
    # the text is the artefact here: whatever these files say is what runs on
    # somebody else's machine, months after this repository was fixed.
    #
    # Whole-line comments are dropped first, because both files now explain in
    # prose WHY npx is absent - a grep that could not tell an explanation from an
    # invocation would force the explanation out, and the explanation is the part
    # that stops someone reinstating the old line.
    cat "$AAHP_ROOT/assets/governance/aahp-govern.yml" \
        "$AAHP_ROOT/scripts/hooks/pre-commit" \
        "$AAHP_ROOT/scripts/hooks/pre-push" > "$TEST_TMPDIR/shipped.txt"
    grep -v '^[[:space:]]*#' "$TEST_TMPDIR/shipped.txt" > "$TEST_TMPDIR/shipped-code.txt" || true
    # The stripped file must not be empty, or this test asserts nothing.
    [ -s "$TEST_TMPDIR/shipped-code.txt" ]

    run grep -n "npx" "$TEST_TMPDIR/shipped-code.txt"
    [ "$status" -ne 0 ]
}

@test "82 the shipped path matches package.json name + bin, so a rename cannot orphan it" {
    # `node ./node_modules/@elvatis_com/aahp/bin/aahp.js` is a hard-coded path in
    # files that ship. If the package name or the bin entry ever changes and this
    # is not updated, the invocation silently stops resolving. This binds them.
    run node -e 'const p = require(process.argv[1]); process.stdout.write("node_modules/" + p.name + "/" + p.bin.aahp);' "$AAHP_ROOT/package.json"
    [ "$status" -eq 0 ]
    expected="$output"
    [ -n "$expected" ]

    run grep -c -F "$expected" "$AAHP_ROOT/assets/governance/aahp-govern.yml"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
    run grep -c -F "$expected" "$AAHP_ROOT/scripts/hooks/pre-commit"
    [ "$status" -eq 0 ]
    run grep -c -F "$expected" "$AAHP_ROOT/scripts/hooks/pre-push"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# #80 - the firewall must say what it does not do
# ---------------------------------------------------------------------------

@test "80 positive control: a real secret in a handoff file is still detected" {
    # Guard for the tests below: proves the lint harness is live in this fixture,
    # so a clean result elsewhere is an observation and not a no-op. The manifest
    # is regenerated after the edit so the ONLY finding is the secret.
    create_full_handoff
    printf '\nghp_abcdefghijklmnopqrstuvwxyz012345\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_manifest_json
    run bash "$AAHP_ROOT/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ghp_"* ]]
}

@test "80 lint says out loud that .aiignore patterns are NOT enforced" {
    # The damage in #80 is the belief, and the belief came from a green run that
    # never looked at the file. Anchor: the `if [ -f "$AIIGNORE_FILE" ]` block in
    # scripts/lint-handoff.sh. Delete it and an adopter's internal hostname
    # passes silently again, with nothing on screen to say it was never checked.
    create_full_handoff
    printf '10.0.0.*\n*.internal.example.com\n' > "$TEST_TMPDIR/.ai/handoff/.aiignore"
    printf '\nDeploy target: db.internal.example.com at 10.0.0.5\n' >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_manifest_json

    run bash "$AAHP_ROOT/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    # The run is green - that is the point, and it is why it must SAY so.
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT ENFORCED"* ]]
    [[ "$output" == *".aiignore"* ]]
    [[ "$output" == *"2 pattern(s)"* ]]
    [[ "$output" == *"NOT checked"* ]]
}

@test "80 lint stays silent about .aiignore when there is no such file" {
    # A notice that fires unconditionally would be noise, and noise gets the tool
    # switched off. It must be tied to the file actually being present.
    create_full_handoff
    rm -f "$TEST_TMPDIR/.ai/handoff/.aiignore"
    run bash "$AAHP_ROOT/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    [[ "$output" != *"NOT ENFORCED"* ]]
}

@test "80 every =assignment secret pattern actually matches an assignment" {
    # Two defects in one place. templates/.aiignore ships `*_CREDENTIALS=*` while
    # SECRET_PATTERNS had no counterpart - AND the four counterparts it did have
    # could not match anything: `grep` runs in BRE, where the bare `?` in
    # `['\"]?` is a LITERAL question mark, so the pattern demanded a quote
    # followed by an actual `?`. Adding `_CREDENTIALS=` to a list of patterns
    # that match nothing would have been an anchor that anchors nothing.
    #
    # Anchors: the five `['\"]\?` quantifiers in SECRET_PATTERNS. Unescape any
    # one of them (back to `['\"]?`) and the corresponding line below survives.
    create_full_handoff
    {
        printf '\n'
        printf 'API_KEY=abc123def456\n'
        printf 'X_SECRET=s3cretvalue\n'
        printf 'GH_TOKEN=ghtokenvalue\n'
        printf 'DB_PASSWORD=hunter2value\n'
        printf 'DB_CREDENTIALS=hunter2abcdef\n'
    } >> "$TEST_TMPDIR/.ai/handoff/STATUS.md"
    create_manifest_json

    run bash "$AAHP_ROOT/scripts/lint-handoff.sh" "$TEST_TMPDIR"
    [ "$status" -ne 0 ]
    for suffix in _KEY _SECRET _TOKEN _PASSWORD _CREDENTIALS; do
        [[ "$output" == *"${suffix}="* ]] || {
            echo "pattern for ${suffix}= did not fire; output was:"
            echo "$output"
            false
        }
    done
}

@test "80 every *_SUFFIX= rule in the shipped template has an enforced counterpart" {
    # The class test for "the template and the enforced list disagree". It does
    # not check that one string is present: it DERIVES the expected set from
    # templates/.aiignore and fails naming any suffix rule with no counterpart,
    # so the next such divergence is caught too. CR is stripped because the
    # template is CRLF in a Windows working tree and `$` would never anchor.
    tr -d '\r' < "$AAHP_ROOT/templates/.aiignore" > "$TEST_TMPDIR/aiignore.lf"
    grep -o '^\*_[A-Z]*=\*$' "$TEST_TMPDIR/aiignore.lf" | sed 's/^\*_//; s/=\*$//' > "$TEST_TMPDIR/suffixes.txt"
    # The derivation itself must not be empty, or the test asserts nothing.
    [ -s "$TEST_TMPDIR/suffixes.txt" ]

    missing=""
    while read -r suffix; do
        [ -n "$suffix" ] || continue
        grep -q -- "_${suffix}=" "$AAHP_ROOT/scripts/lint-handoff.sh" || missing="$missing $suffix"
    done < "$TEST_TMPDIR/suffixes.txt"

    if [ -n "$missing" ]; then
        echo "template rules with no counterpart in SECRET_PATTERNS:$missing"
        false
    fi
}

@test "80 the shipped template no longer claims CI validates it" {
    # The exact false sentence. templates/.aiignore is what an adopter reads
    # before deciding whether to write an internal hostname into a committed file.
    run grep -niE "validated by ci|ci hook validates" "$AAHP_ROOT/templates/.aiignore"
    [ "$status" -ne 0 ]
    # ... and it must say the opposite, so the reader is not left to infer it.
    run grep -c "NOT ENFORCED" "$AAHP_ROOT/templates/.aiignore"
    [ "$status" -eq 0 ]
}

# --- 84, the case in the issue title: a typo in a GATE ID -------------------
#
# `check.only` and `check.skip` were typed as bare strings with no enum, while
# `pinnedDep.location` two sections away had one. So a gate id misspelled by one
# letter matched no gate, every gate was deselected, and the run reported
# `Governance OK: 0 gate(s) ran, no failures.` exit 0 with the violation still in
# the tree. Both AJV and the hand validator called that config valid.
#
# The ids are checked against CHECK_GATES rather than against an enum in the
# schema: a second copy of the list drifts the moment a gate is added, and drift
# there restores the defect with nothing turning red.

setup_gate_id_fixture() {
  FIXDIR="$BATS_TEST_TMPDIR/gate-id"
  mkdir -p "$FIXDIR"
  cd "$FIXDIR" || return 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf '{"name":"fx","version":"1.0.0"}' > package.json
  # A real U+2014, written by code point so this file needs none of its own.
  printf 'a real em dash \u2014 right here\n' > DOC.md
  git add -A && git commit -qm init
}

write_only_config() {
  printf '{"forbiddenPatterns":[{"id":"em-dash","pattern":"\\u2014","message":"no em dash"}],"check":{"only":%s}}' \
    "$1" > "$FIXDIR/aahp.config.json"
}

@test "84 control: the correctly spelled gate id catches the violation" {
  setup_gate_id_fixture
  write_only_config '["forbidden-patterns"]'
  run node "$AAHP_ROOT/bin/aahp.js" check "$FIXDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Governance FAILED"* ]]
}

@test "84 an unknown gate id is refused, not silently treated as deselect-all" {
  setup_gate_id_fixture
  write_only_config '["forbidden-paterns"]'
  run node "$AAHP_ROOT/bin/aahp.js" check "$FIXDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT EVALUATED"* ]]
  [[ "$output" == *"forbidden-paterns"* ]]
  # The distinction the defect erased: this must not read as a pass.
  [[ "$output" != *"Governance OK"* ]]
}

@test "84 the refusal names the ids that DO exist, so the typo is fixable" {
  setup_gate_id_fixture
  write_only_config '["totally-made-up"]'
  run node "$AAHP_ROOT/bin/aahp.js" check "$FIXDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Known gate ids"* ]]
  [[ "$output" == *"forbidden-patterns"* ]]
}

@test "84 zero gates ran is reported as not evaluated, never as OK" {
  setup_gate_id_fixture
  write_only_config '[]'
  run node "$AAHP_ROOT/bin/aahp.js" check "$FIXDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0 gate(s) ran"* ]]
  [[ "$output" == *"not a pass"* ]]
  [[ "$output" != *"Governance OK"* ]]
}
