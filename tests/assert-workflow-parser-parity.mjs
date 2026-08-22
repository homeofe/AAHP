#!/usr/bin/env node
// assert-workflow-parser-parity.mjs - the zero-dependency reader must agree
// with a real YAML parser.
//
// check-verify-workflow.mjs cannot depend on a YAML package: AAHP ships no
// runtime dependencies, and the gate has to run inside a consumer that only
// installed the CLI. So it carries a small block-YAML reader. A hand-written
// parser that quietly disagrees with real YAML is the worst possible engine for
// a security gate - it would report "enforced" on a workflow it misread.
//
// This asserts the disagreement cannot happen unnoticed, over every workflow in
// this repository plus every fixture under tests/fixtures/workflows/, on exactly
// the fields the audit consumes (job `if`, job `continue-on-error`, and each
// step's name/run/uses/if/continue-on-error) AND on the resulting finding ids.
// `yaml` is a devDependency, so this runs in CI and never in a consumer.
//
// Both DIRECTIONS matter and both are covered by the fixture set: workflows that
// must come out enforced, and workflows that must come out bypassable.
//
// Kept as a file rather than an inline `node -e` for the reason recorded in
// tests/assert-repo-ci-shape.mjs: under Git Bash a POSIX path inside a quoted
// -e string is not converted for the native node binary.
//
// Usage: node tests/assert-workflow-parser-parity.mjs [repo-root]
// Exit:  0 parity holds, 1 a divergence was found, 2 nothing was compared.

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve, relative } from "node:path";
import { parse } from "yaml";
import { parseYamlSubset, auditDoc } from "../scripts/check-verify-workflow.mjs";

const root = resolve(process.argv[2] || ".");

// Project a parsed document down to the fields the audit reads. Everything else
// is free to differ: this gate never looks at it.
function projection(doc) {
  const jobs = doc && typeof doc === "object" && doc.jobs && typeof doc.jobs === "object" ? doc.jobs : {};
  const str = (v) => (v === undefined ? null : String(v));
  const out = {};
  for (const [id, job] of Object.entries(jobs)) {
    if (!job || typeof job !== "object") continue;
    const steps = Array.isArray(job.steps) ? job.steps : [];
    out[id] = {
      if: str(job.if),
      coe: str(job["continue-on-error"]),
      steps: steps.map((s) =>
        s && typeof s === "object"
          ? { name: str(s.name), run: str(s.run), uses: str(s.uses), if: str(s.if), coe: str(s["continue-on-error"]) }
          : null,
      ),
    };
  }
  return out;
}

const dirs = [join(root, ".github", "workflows"), join(root, "tests", "fixtures", "workflows")];
const problems = [];
let compared = 0;

for (const dir of dirs) {
  if (!existsSync(dir)) continue;
  for (const entry of readdirSync(dir).sort()) {
    if (!/\.ya?ml$/i.test(entry)) continue;
    const path = join(dir, entry);
    const label = relative(root, path).replace(/\\/g, "/");
    const text = readFileSync(path, "utf8");

    let reference;
    try {
      reference = parse(text);
    } catch (err) {
      problems.push(`${label}: the reference parser rejects this fixture (${err.message}); fix the fixture`);
      continue;
    }

    let mine;
    try {
      mine = parseYamlSubset(text);
    } catch (err) {
      problems.push(`${label}: the AAHP reader cannot parse a file real YAML accepts (${err.message})`);
      continue;
    }

    compared++;
    const a = JSON.stringify(projection(reference));
    const b = JSON.stringify(projection(mine));
    if (a !== b) {
      problems.push(`${label}: the AAHP reader disagrees with real YAML on the audited fields\n      yaml: ${a.slice(0, 400)}\n      aahp: ${b.slice(0, 400)}`);
      continue;
    }

    const fa = auditDoc(reference, label).findings.map((f) => f.id).sort().join(",");
    const fb = auditDoc(mine, label).findings.map((f) => f.id).sort().join(",");
    if (fa !== fb) {
      problems.push(`${label}: same file, different verdict: yaml=[${fa}] aahp=[${fb}]`);
    }
  }
}

if (compared === 0) {
  console.error("workflow parser parity: nothing was compared. A green run here would mean nothing.");
  process.exit(2);
}
if (problems.length > 0) {
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log(`workflow parser parity OK (${compared} workflow file(s))`);
