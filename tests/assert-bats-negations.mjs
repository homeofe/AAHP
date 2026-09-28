#!/usr/bin/env node
// assert-bats-negations.mjs - no dead `!` assertions in the bats suite.
//
// Bats runs a test body under `set -e`, and bash deliberately exempts a
// command negated with `!` from errexit. So in
//
//     @test "..." {
//         run some-command
//         ! grep -q "must be gone" out.txt     <- can never fail the test
//         grep -q "must be there" out.txt
//     }
//
// the middle line is decoration: the test passes whether or not the text is
// there. Only the LAST command of a function counts, because its status becomes
// the function's return value. bats-core documents this as a gotcha; under the
// repository's own bats 1.13.0 a probe `@test { ! true; true; }` passes.
// tests/archive.bats and tests/migrate-grounding.bats both carried the pattern.
//
// This scans every tests/*.bats and tests/*.bash file and reports each `!`
// statement (leading `!`, or `&& !`, `|| !`, `; !`) that is not the last command
// of its @test or function body, unless it ends in `|| false` (or `|| return`,
// `|| exit`, `|| fail`), which restores the failure. Write instead:
//
//     run grep -q "must be gone" out.txt
//     [ "$status" -eq 1 ]                   # 1 = no match; 2 = error, also red
//
// or `run ! cmd` after `bats_require_minimum_version 1.5.0`.
//
// It enumerates files with readdirSync, not `git ls-files`, so a new file is
// covered before it is committed. Heredoc bodies are skipped.
//
// Usage: node tests/assert-bats-negations.mjs [repo-root]
// Exit:  0 clean, 1 dead negation(s), 2 nothing scanned.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(process.argv[2] || ".");
const testsDir = join(root, "tests");

// There is no exemption list: a dead negation is fixed, never listed. (The one
// offender that existed when this guard landed was fixed in #120.)

const BLOCK_START = /^(?:@test\s.*|(?:function\s+)?[A-Za-z_][A-Za-z0-9_:.-]*\s*\(\)\s*|function\s+[A-Za-z_][A-Za-z0-9_:.-]*\s*)\{\s*$/;
const BLOCK_END = /^\}\s*$/;
const HEREDOC = /(?<!<)<<(-?)\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2/g;
const NEGATION = /^\s*!\s|(?:&&|\|\||;)\s*!\s/;
const RESTORED = /\|\|\s*(?:false|return|exit|fail)\b[^|&;]*$/;
const IGNORABLE = /^\s*(?:#.*)?$/;

function scan(rel, text) {
  const lines = text.split(/\r?\n/);
  const findings = [];
  const negations = [];
  let inBlock = false;
  let heredocs = [];

  // First pass: mark heredoc bodies and statement extents inside blocks.
  const kind = new Array(lines.length).fill("code");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (heredocs.length > 0) {
      kind[i] = "heredoc";
      const { dash, word } = heredocs[0];
      const candidate = dash ? line.replace(/^\t+/, "") : line;
      if (candidate === word) heredocs.shift();
      continue;
    }
    for (const m of line.matchAll(HEREDOC)) {
      heredocs.push({ dash: m[1] === "-", word: m[3] });
    }
    if (!inBlock) {
      if (BLOCK_START.test(line)) {
        inBlock = true;
        kind[i] = "start";
      } else {
        kind[i] = "outside";
      }
      continue;
    }
    if (BLOCK_END.test(line)) {
      inBlock = false;
      kind[i] = "end";
    }
  }

  for (let i = 0; i < lines.length; i++) {
    if (kind[i] !== "code") continue;
    // Join continuation lines into one statement.
    let j = i;
    let stmt = lines[i];
    while (/\\$/.test(lines[j]) && j + 1 < lines.length && kind[j + 1] === "code") {
      j++;
      stmt = stmt.replace(/\\$/, " ") + lines[j];
    }
    if (NEGATION.test(stmt) && !RESTORED.test(stmt)) {
      // Is anything but blanks/comments left before the block closes?
      let k = j + 1;
      let last = true;
      for (; k < lines.length && kind[k] !== "end"; k++) {
        if (kind[k] === "heredoc" || !IGNORABLE.test(lines[k])) {
          last = false;
          break;
        }
      }
      if (!last) negations.push({ line: i + 1, text: lines[i].trim() });
    }
    i = j;
  }

  for (const n of negations) {
    findings.push(
      `${rel}:${n.line}: \`${n.text}\` is a negation that is not the last command of its ` +
        `test or function, so bash's errexit exemption means it can never fail. ` +
        `Use \`run CMD\` + \`[ "$status" -eq 1 ]\`, \`run ! CMD\`, or append \`|| false\`.`,
    );
  }
  return findings;
}

if (!existsSync(testsDir)) {
  console.error(`bats negations: ${testsDir} does not exist; nothing was scanned.`);
  process.exit(2);
}

const files = readdirSync(testsDir)
  .filter((f) => /\.(bats|bash)$/.test(f))
  .sort();
if (files.length === 0) {
  console.error(`bats negations: no .bats or .bash file under ${testsDir}; nothing was scanned.`);
  process.exit(2);
}

const problems = [];
for (const f of files) {
  const rel = `tests/${f}`;
  problems.push(...scan(rel, readFileSync(join(testsDir, f), "utf8")));
}
if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log(`bats negations OK (${files.length} file(s) scanned)`);
