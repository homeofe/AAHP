#!/usr/bin/env node
/**
 * check-conflict-markers.mjs - Refuse markers in handoff state and in the
 * documents this repository publishes.
 *
 * Tools that rewrite STATUS.md while git conflict markers remain produce nested
 * markers. This gate fails closed.
 *
 * Usage: node scripts/check-conflict-markers.mjs [path-to-project]
 * Exit: 0 clean, 1 markers found, 2 usage/IO error
 *
 * Detection is line-ending agnostic: CR is stripped before matching so
 * `=======\r` is still seen.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

/** @param {string} text */
export function hasMarkers(text) {
  const normalized = text.replace(/\r/g, "");
  for (const line of normalized.split("\n")) {
    const s = line.trim();
    if (s.startsWith("<<<<<<<") || s.startsWith(">>>>>>>") || s === "=======") {
      return true;
    }
  }
  return false;
}

export function main(argv = process.argv.slice(2)) {
  const root = resolve(argv[0] || ".");
  const handoff = join(root, ".ai", "handoff");

  let files;
  try {
    files = readdirSync(handoff).filter((f) => f.endsWith(".md") || f.endsWith(".json"));
  } catch (err) {
    console.error(`check-conflict-markers: cannot read ${handoff}: ${err.message}`);
    return 2;
  }

  // The root Markdown documents are scanned as well as handoff state. A merge
  // conflict lands in release notes and the README at least as often as in
  // STATUS.md, and those are the files an adopter and npm actually receive.
  // Measured on this repository: a `<<<<<<< HEAD` reached a pushed branch inside
  // CHANGELOG.md while the pre-commit hook, `aahp verify --level ci` and this gate
  // all reported clean, because none of them looked outside `.ai/handoff/`.
  //
  // Read with a directory listing rather than `git ls-files`, for two reasons. A
  // project root need not be a git repository, which this protocol supports, and a
  // gate that errors there would be worse than the gap it closes. And an UNTRACKED
  // root document is still a document at the root; there is no version of this
  // check that should ignore one.
  //
  // Only the root level. `tests/` ships fixtures that contain marker lines on
  // purpose, and a gate that fails on its own test data gets bypassed.
  let rootDocs = [];
  try {
    rootDocs = readdirSync(root)
      .filter((f) => f.endsWith(".md"))
      .map((f) => join(root, f));
  } catch (err) {
    // Fail closed. Scanning the handoff directory alone and printing OK would be
    // the same false green this widening exists to remove, in a new place.
    console.error(`check-conflict-markers: cannot read ${root}: ${err.message}`);
    console.error("The root documents were NOT scanned, so this is not a clean result.");
    return 2;
  }

  const bad = [];
  for (const path of rootDocs) {
    try {
      if (!statSync(path).isFile()) continue;
      if (hasMarkers(readFileSync(path, "utf8"))) bad.push(path);
    } catch (err) {
      console.error(`check-conflict-markers: cannot read ${path}: ${err.message}`);
      return 2;
    }
  }

  for (const f of files) {
    const path = join(handoff, f);
    try {
      if (!statSync(path).isFile()) continue;
      const text = readFileSync(path, "utf8");
      if (hasMarkers(text)) bad.push(path);
    } catch (err) {
      console.error(`check-conflict-markers: cannot read ${path}: ${err.message}`);
      return 2;
    }
  }

  if (bad.length) {
    console.error("check-conflict-markers: FAIL - git conflict markers present:");
    for (const p of bad) console.error(`  ${p}`);
    console.error(
      "Resolve or restore these files before /handoff, any rewrite tool, or a push.",
    );
    return 1;
  }

  console.log(
    `check-conflict-markers: OK - no conflict markers in ${files.length} handoff file(s) ` +
      `and ${rootDocs.length} root document(s).`,
  );
  return 0;
}

const isMain =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMain) {
  process.exit(main());
}
