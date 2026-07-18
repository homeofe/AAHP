#!/usr/bin/env node
// check-version-sync.mjs - Assert that package.json's version string appears in
// every configured "version site" file at least minOccurrences times. Exits 1
// if any site falls short, 0 on success or when nothing is configured.
//
// Config-driven: the list of files lives in aahp.config.json under
// "versionSites" (the SCG original hardcoded this list for its own layout). A
// repo with no aahp.config.json - or no versionSites - is a clean no-op, so this
// gate never breaks a project that has not opted in.
//
//   "versionSites": [
//     { "file": "bin/cli.js", "minOccurrences": 1, "note": "--version banner" },
//     { "file": "README.md",  "minOccurrences": 1, "boundary": true }
//   ]
//
// minOccurrences defaults to 1. boundary:true wraps the search in word
// boundaries so "3.3.0" does not match inside "3.3.09"; default is a literal
// substring count (dots are literal, matching the SCG behavior).

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadPkg, loadConfig } from "./aahp-config.mjs";

const root = resolveRoot();

let pkg;
let config;
try {
  pkg = loadPkg(root);
  config = loadConfig(root);
} catch (err) {
  console.error(`  version-sync: ${err.message}`);
  process.exit(1);
}

const version = pkg.version;
const sites = Array.isArray(config.versionSites) ? config.versionSites : [];

if (sites.length === 0) {
  console.log(`Version sync: no versionSites configured; nothing to check (v${version}).`);
  process.exit(0);
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const failures = [];

for (const site of sites) {
  const file = site.file;
  const minOccurrences = Number.isInteger(site.minOccurrences) ? site.minOccurrences : 1;
  const note = site.note || "";

  let contents;
  try {
    contents = readFileSync(join(root, file), "utf8");
  } catch (err) {
    failures.push({ file, found: 0, expected: minOccurrences, note, stale: [], error: err.code === "ENOENT" ? "file not found" : err.message });
    continue;
  }

  let count = 0;
  if (site.boundary) {
    const re = new RegExp(`\\b${escapeRe(version)}\\b`, "g");
    count = (contents.match(re) || []).length;
  } else {
    // Literal substring count so dots stay literal (matches SCG semantics).
    let idx = 0;
    while ((idx = contents.indexOf(version, idx)) !== -1) {
      count++;
      idx += version.length;
    }
  }

  if (count < minOccurrences) {
    const stale = [...new Set(Array.from(contents.matchAll(/\b\d+\.\d+\.\d+\b/g), (m) => m[0]))].filter((v) => v !== version);
    failures.push({ file, found: count, expected: minOccurrences, note, stale });
  }
}

if (failures.length > 0) {
  console.error(
    `\n  Version sync check failed for v${version}.\n` +
      `  Every release must bump the version in package.json AND in each\n` +
      `  configured version site below. Forgetting one ships stale version\n` +
      `  strings in the published output.\n`,
  );
  for (const { file, found, expected, note, stale, error } of failures) {
    console.error(`  - ${file}`);
    if (error) {
      console.error(`      ${error}`);
    } else {
      console.error(`      expected: at least ${expected} occurrence(s) of "${version}"${note ? ` (${note})` : ""}`);
      console.error(`      found:    ${found}`);
      if (stale.length > 0) console.error(`      stale versions still in file: ${stale.join(", ")}`);
    }
  }
  console.error("\n  Fix: bump the version everywhere it is pinned, then re-run the gate.\n");
  process.exit(1);
}

console.log(`Version sync OK: package.json v${version} matches all ${sites.length} configured version site(s).`);
