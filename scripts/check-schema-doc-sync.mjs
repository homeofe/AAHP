#!/usr/bin/env node
// check-schema-doc-sync.mjs - Config-driven consistency gate. For each docSync
// group, extract a SET of values from every source (regex capture group 1) and
// fail if the sets are not all identical. Catches copy-paste drift between a
// schema enum and its doc copies, config keys vs examples, or a list duplicated
// across docs (e.g. the task-status enum that drifted across schema/README/CLI).
// A clean no-op when docSync is absent.
//
//   "docSync": [
//     { "id": "task-status-enum",
//       "sources": [
//         { "file": "schema/aahp-manifest.schema.json",
//           "pattern": "\"(ready|in_progress|blocked|done|cancelled)\"" },
//         { "file": "README.md",
//           "pattern": "`(ready|in_progress|blocked|done|cancelled)`" }
//       ] }
//   ]
// Each source's pattern captures ONE token per match in group 1; the SET of
// distinct group-1 values must be identical across all sources in the group.
//
// Scope (be honest about what this catches): when a source pattern hard-codes the
// token alternation (the common case), the gate reliably catches a source that
// DROPS a token entirely - the disagreement drift that bit us in v3.6.1. It does
// NOT catch a brand-new token added to one source only (no pattern captures it),
// nor a token that lingers in unrelated prose while its authoritative use is
// removed. Keep one source authoritative and point patterns at that source's
// canonical location for the strongest guarantee.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadConfig } from "./aahp-config.mjs";

const root = resolveRoot();

let config;
try {
  config = loadConfig(root);
} catch (err) {
  console.error(`  schema-doc-sync: ${err.message}`);
  process.exit(1);
}

const groups = Array.isArray(config.docSync) ? config.docSync : [];
if (groups.length === 0) {
  console.log("Schema-doc sync: none configured; nothing to check.");
  process.exit(0);
}

const failures = [];

for (const group of groups) {
  const { id = "(unnamed)", sources = [] } = group;
  const extracted = [];
  for (const src of sources) {
    let text;
    try {
      text = readFileSync(join(root, src.file), "utf8");
    } catch (err) {
      failures.push({ id, msg: `source not readable: ${src.file} (${err.code || err.message})` });
      continue;
    }
    let re;
    try {
      re = new RegExp(src.pattern, "g");
    } catch (err) {
      failures.push({ id, msg: `invalid pattern for ${src.file}: ${err.message}` });
      continue;
    }
    const vals = new Set();
    for (const m of text.matchAll(re)) if (m[1] !== undefined) vals.add(m[1]);
    if (vals.size === 0) {
      failures.push({ id, msg: `${src.file}: pattern extracted 0 values (check the regex)` });
      continue;
    }
    extracted.push({ file: src.file, vals });
  }
  if (extracted.length >= 2) {
    const ref = extracted[0];
    for (let i = 1; i < extracted.length; i++) {
      const missing = [...ref.vals].filter((x) => !extracted[i].vals.has(x));
      const extra = [...extracted[i].vals].filter((x) => !ref.vals.has(x));
      if (missing.length || extra.length) {
        failures.push({
          id,
          msg: `${extracted[i].file} disagrees with ${ref.file}: ` +
            (missing.length ? `missing [${missing.join(", ")}] ` : "") +
            (extra.length ? `extra [${extra.join(", ")}]` : ""),
        });
      }
    }
  }
}

if (failures.length > 0) {
  console.error(`\n  Schema-doc sync check failed.\n`);
  for (const f of failures) console.error(`  - [${f.id}] ${f.msg}`);
  console.error("");
  process.exit(1);
}

console.log(`Schema-doc sync OK: ${groups.length} group(s) consistent.`);
