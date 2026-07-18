#!/usr/bin/env node
// check-changelog.mjs - Presence gate: CHANGELOG.md must carry an entry for the
// current package.json version. The full structural grammar is enforced
// separately by check-changelog-format.mjs; this gate just guarantees the
// release being shipped has a changelog section at all.
//
// A repo with no CHANGELOG.md is a clean skip (exit 0): the changelog gates are
// opt-in by simply keeping a CHANGELOG.md. Once the file exists, a release
// whose version has no "## [X.Y.Z] - ..." heading fails.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRoot, loadPkg } from "./aahp-config.mjs";

const root = resolveRoot();

let pkg;
try {
  pkg = loadPkg(root);
} catch (err) {
  console.error(`  changelog: ${err.message}`);
  process.exit(1);
}

const changelogPath = join(root, "CHANGELOG.md");
if (!existsSync(changelogPath)) {
  console.log("Changelog presence: no CHANGELOG.md found; skipping (add one to enable this gate).");
  process.exit(0);
}

const changelog = readFileSync(changelogPath, "utf8");
const version = pkg.version;
// Keep a Changelog heading, no 'v' inside the brackets. Escape every regex
// metacharacter (not just dots) so a version string can never be mis-parsed as
// a pattern - complete escaping, not just the common case.
const escapedVersion = version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const heading = new RegExp(`^## \\[${escapedVersion}\\] - `, "m");

if (!heading.test(changelog)) {
  console.error(
    `\n  CHANGELOG.md is missing an entry for ${version}.\n` +
      `  Add a section below "## [Unreleased]" in Keep a Changelog form:\n\n` +
      `    ## [${version}] - YYYY-MM-DD\n` +
      `    ### Added\n` +
      `    - what changed\n\n` +
      `  and a reference-link line at the file foot. A release cannot ship without this.\n`,
  );
  process.exit(1);
}

console.log(`Changelog presence OK: CHANGELOG.md contains an entry for ${version}.`);
