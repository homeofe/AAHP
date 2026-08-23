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
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

/**
 * A conflict FENCE, not a separator.
 *
 * `s === "======="` used to be a third arm here. It cannot survive a whole-tree
 * scan: seven equals signs is a Markdown setext heading underline and a Python
 * docstring section header. Measured across the 48 AAHP adopter roots on one
 * machine, that arm alone flips 2 of them red on files containing no conflict.
 * Seven `<` or `>` at the start of a line is not ordinary content in any format,
 * so those two arms stay.
 *
 * Making the separator conditional on an open `<<<<<<<` block is the obvious
 * repair and produces DEAD CODE, because the opening line already returns true.
 * A check that cannot fire is worse than no check, so the arm is gone.
 *
 * The cost, stated rather than buried: a conflict whose `<<<<<<<` AND `>>>>>>>`
 * lines were BOTH hand-deleted while the separator was left is no longer seen.
 * Git never writes that state.
 *
 * @param {string} text
 */
export function hasMarkers(text) {
  const normalized = text.replace(/\r/g, "");
  for (const line of normalized.split("\n")) {
    const s = line.trim();
    if (s.startsWith("<<<<<<<") || s.startsWith(">>>>>>>")) {
      return true;
    }
  }
  return false;
}

export function main(argv = process.argv.slice(2)) {
  const root = resolve(argv[0] || ".");
  const handoff = join(root, ".ai", "handoff");

  // Handoff state is read first and only as a PRECONDITION. An unreadable handoff
  // directory is exit 2, not a clean scan of everything else: this gate's original
  // job is refusing a handoff rewrite over unresolved markers, and it cannot report
  // on a directory it could not open.
  try {
    readdirSync(handoff);
  } catch (err) {
    console.error(`check-conflict-markers: cannot read ${handoff}: ${err.message}`);
    return 2;
  }

  // Everything below the root, not just the root. #105 scanned `.ai/handoff/` plus
  // root-level *.md and left 50 of the 53 files npm ships unscanned, `templates/`
  // among them: a marker there ships AND `aahp init` copies it into every adopting
  // repository. Reproduced on a clean copy of that commit before this was written.
  //
  // A directory read rather than `git ls-files`, because a project root need not be
  // a git repository, and an untracked file at any depth is still a file this gate
  // should see. `.git` and `node_modules` are pruned because neither is project
  // content; nothing else is excluded, and nothing needs to be, because the
  // predicate no longer fires on ordinary text.
  const PRUNE = new Set([".git", "node_modules"]);
  const paths = [];

  /** @param {string} dir */
  function collect(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (PRUNE.has(entry.name)) continue;
        collect(full);
      } else if (entry.isFile()) {
        paths.push(full);
      }
    }
  }

  try {
    collect(root);
  } catch (err) {
    // Fail closed. A partial walk reported as OK would be the same false green
    // this gate exists to remove, one level further out.
    console.error(`check-conflict-markers: cannot walk ${root}: ${err.message}`);
    console.error("The project tree was NOT scanned, so this is not a clean result.");
    return 2;
  }

  const bad = [];
  let scanned = 0;
  let skipped = 0;
  for (const path of paths) {
    let buf;
    try {
      buf = readFileSync(path);
    } catch (err) {
      console.error(`check-conflict-markers: cannot read ${path}: ${err.message}`);
      return 2;
    }
    // A NUL byte in the first 8 KiB means binary. Decoding one as UTF-8 cannot
    // produce a line-anchored fence, so reading it would only cost time, but the
    // count below reports the skips rather than hiding them.
    if (buf.subarray(0, 8192).includes(0)) {
      skipped += 1;
      continue;
    }
    scanned += 1;
    if (hasMarkers(buf.toString("utf8"))) bad.push(path);
  }
  if (bad.length) {
    console.error("check-conflict-markers: FAIL - git conflict markers present:");
    for (const p of bad) console.error(`  ${p}`);
    console.error(
      "Resolve or restore these files before /handoff, any rewrite tool, or a push.",
    );
    return 1;
  }

  // The counts are printed on a passing run on purpose. A walk that reached
  // nothing and a walk that found nothing both print OK otherwise, and this gate
  // has already shipped one version of that mistake.
  console.log(
    `check-conflict-markers: OK - no conflict markers in ${scanned} file(s) scanned` +
      `${skipped > 0 ? `, ${skipped} binary file(s) skipped` : ""}.`,
  );
  return 0;
}

const isMain =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMain) {
  process.exit(main());
}
