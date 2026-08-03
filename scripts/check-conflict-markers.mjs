#!/usr/bin/env node
/**
 * check-conflict-markers.mjs - Refuse handoff rewrites when markers are present.
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

  const bad = [];
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
      "Resolve or restore these files before /handoff or any rewrite tool runs.",
    );
    return 1;
  }

  console.log("check-conflict-markers: OK - no conflict markers in handoff files.");
  return 0;
}

const isMain =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMain) {
  process.exit(main());
}
