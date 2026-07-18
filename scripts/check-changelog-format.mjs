#!/usr/bin/env node
// check-changelog-format.mjs - Enforce ONE machine-checkable CHANGELOG grammar
// so the release / LOG / downstream parsers can never break on a hand-formatted
// entry. Standard: Keep a Changelog 1.1.0 + SemVer.
//
// The release-heading grammar is imported from changelog-grammar.mjs - the SAME
// module the LOG generator (aahp-dashboard.mjs) parses with - so the validator
// and the generator cannot diverge (that is the invariant, not a convention).
//
// A repo with no CHANGELOG.md is a clean skip (exit 0). When the file exists the
// STRUCTURE is enforced strictly (headings, dates, ordering, links, top==version,
// no BOM) and the section vocabulary WHERE ### sections are used. Historical
// prose entries are not forced into a taxonomy; new entries accumulate under
// ## [Unreleased] in full Keep a Changelog form.
//
// Rules (contiguous R1..R8):
//   R1 every non-Unreleased H2 is a valid "## [X.Y.Z] - YYYY-MM-DD" heading
//   R2 "## [Unreleased]" is optional; if present it is the first H2 and unique
//   R3 every release date is a real ISO calendar date, not in the future
//   R4 every "### " section heading is from the allowed vocabulary
//   R5 releases strictly descend by SemVer with no duplicates
//   R6 the topmost release equals package.json version
//   R7 every "## [label]" has a reference-link definition at the file foot
//   R8 the file is UTF-8 without a BOM

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadPkg } from "./aahp-config.mjs";
import { RELEASE_RE, UNRELEASED_RE, SECTIONS, REFLINK_RE, cmpVersion } from "./changelog-grammar.mjs";

const root = resolveRoot();

let pkg;
try {
  pkg = loadPkg(root);
} catch (err) {
  console.error(`  changelog-format: ${err.message}`);
  process.exit(1);
}

const changelogPath = join(root, "CHANGELOG.md");
if (!existsSync(changelogPath)) {
  console.log("Changelog format: no CHANGELOG.md found; skipping (add one to enable this gate).");
  process.exit(0);
}

const raw = readFileSync(changelogPath, "utf8");
const fail = [];

// R8: UTF-8 without BOM.
if (raw.charCodeAt(0) === 0xfeff) fail.push("R8: file starts with a UTF-8 BOM - save as UTF-8 without a BOM.");
const lines = raw.replace(/^﻿/, "").split(/\r?\n/);

const today = new Date().toISOString().slice(0, 10);

const releases = []; // { version, date, line }
const bracketLabels = []; // every "## [label]" for R7
let unreleasedCount = 0;
let firstH2Index = -1;

lines.forEach((line, i) => {
  if (/^## /.test(line)) {
    if (firstH2Index === -1) firstH2Index = i;
    if (UNRELEASED_RE.test(line)) {
      unreleasedCount++;
      bracketLabels.push("Unreleased");
      if (i !== firstH2Index) fail.push(`R2: "## [Unreleased]" (line ${i + 1}) must be the first H2 heading.`);
      return;
    }
    const m = line.match(RELEASE_RE);
    if (!m) {
      fail.push(`R1: H2 heading (line ${i + 1}) is not a valid release heading "## [X.Y.Z] - YYYY-MM-DD": ${JSON.stringify(line)}`);
      return;
    }
    const [, version, date] = m;
    const d = new Date(date + "T00:00:00Z");
    if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== date) {
      fail.push(`R3: ${version} has an invalid calendar date "${date}".`);
    } else if (date > today) {
      fail.push(`R3: ${version} is dated "${date}", in the future (today is ${today}).`);
    }
    releases.push({ version, date, line: i + 1 });
    bracketLabels.push(version);
  } else if (/^### /.test(line)) {
    const s = line.slice(4).trim();
    if (!SECTIONS.has(s)) fail.push(`R4: invalid section heading "### ${s}" (line ${i + 1}). Allowed: ${[...SECTIONS].join(", ")}.`);
  }
});

if (unreleasedCount > 1) fail.push(`R2: "## [Unreleased]" appears ${unreleasedCount} times; it must appear at most once.`);

if (releases.length === 0) {
  fail.push("R1: no valid release headings found.");
} else {
  if (releases[0].version !== pkg.version) {
    fail.push(`R6: topmost release is [${releases[0].version}] but package.json is ${pkg.version} - the newest entry must match the release.`);
  }
  for (let i = 1; i < releases.length; i++) {
    const c = cmpVersion(releases[i - 1].version, releases[i].version);
    if (c === 0) fail.push(`R5: duplicate version [${releases[i].version}] (line ${releases[i].line}).`);
    else if (c < 0) fail.push(`R5: [${releases[i - 1].version}] then [${releases[i].version}] is out of order - releases must strictly descend by SemVer.`);
  }
}

// R7: every bracket label has a reference-link definition at the foot.
const defined = new Set([...raw.matchAll(REFLINK_RE)].map((m) => m[1]));
for (const label of bracketLabels) {
  if (!defined.has(label)) fail.push(`R7: "[${label}]" has no reference-link definition (add "[${label}]: https://..." at the file foot).`);
}

if (fail.length > 0) {
  console.error(
    `\n  CHANGELOG.md does not match the Keep a Changelog format standard.\n` +
      `  One grammar is what keeps the release / LOG parsers from breaking.\n` +
      `  Canonical shape: "## [X.Y.Z] - YYYY-MM-DD" (no 'v' in brackets), sections\n` +
      `  from {${[...SECTIONS].join(", ")}}, a reference-link footer, no BOM.\n`,
  );
  for (const f of fail) console.error(`  - ${f}`);
  console.error("");
  process.exit(1);
}

console.log(`Changelog format OK: ${releases.length} release(s), Keep a Changelog + SemVer, top=[${releases[0].version}] matches package.json.`);
