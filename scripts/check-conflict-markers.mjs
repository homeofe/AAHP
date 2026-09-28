#!/usr/bin/env node
/**
 * check-conflict-markers.mjs - Refuse markers in handoff state and in the
 * documents this repository publishes.
 *
 * Tools that rewrite STATUS.md while git conflict markers remain produce nested
 * markers. This gate fails closed.
 *
 * Usage: node scripts/check-conflict-markers.mjs [path-to-project]
 * Exit: 0 clean, 1 markers found, 2 could not run (usage, IO, or any
 * unexpected error). Exit 1 is ALWAYS accompanied by the
 * "check-conflict-markers: FAIL" line on stderr, which is how
 * scripts/lint-handoff.sh tells it apart from node dying with its own exit 1.
 *
 * Detection is line-ending agnostic: CR is stripped before matching so
 * `=======\r` is still seen.
 */
import { execFileSync } from "node:child_process";
import { closeSync, lstatSync, openSync, readdirSync, readFileSync, readSync } from "node:fs";
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

/**
 * The files git would show for this tree: tracked, plus untracked-and-not-
 * ignored, plus EVERYTHING under the handoff directory, ignored or not (an
 * adopter who ignores it still gets it scanned). Returns null when `root` is
 * not inside a git work tree or git is unavailable; the caller then walks.
 *
 * Why git and not only a walk: the walk pruned .git and node_modules and read
 * every other file in full, including .venv, dist, target and a gitignored
 * `*.orig` that a merge tool leaves behind. That is both slow and a false
 * positive waiting to happen, on files that never ship.
 *
 * @param {string} root
 * @returns {string[] | null} paths relative to root
 */
export function gitFileList(root) {
  const git = (args) =>
    execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      maxBuffer: 256 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"],
    });
  try {
    if (git(["rev-parse", "--is-inside-work-tree"]).trim() !== "true") return null;
    const listed = git(["ls-files", "-z", "-co", "--exclude-standard"]);
    const ignoredHandoff = git(["ls-files", "-z", "-oi", "--exclude-standard", "--", ".ai/handoff"]);
    return [...new Set((listed + ignoredHandoff).split("\0").filter(Boolean))];
  } catch {
    return null;
  }
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
  // Inside a git work tree the file set is git's (see gitFileList): an untracked
  // file at any depth is still seen unless the project ignores it, and the
  // handoff directory is always seen. A project root need not be a git
  // repository, so outside one this falls back to a directory walk with `.git`
  // and `node_modules` pruned, because neither is project content. Nothing else
  // needs excluding for correctness, because the predicate no longer fires on
  // ordinary text.
  const PRUNE = new Set([".git", "node_modules"]);
  let paths = [];
  let source = "walk";

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

  const listed = gitFileList(root);
  if (listed) {
    source = "git";
    paths = listed.map((rel) => join(root, rel));
  } else {
    try {
      collect(root);
    } catch (err) {
      // Fail closed. A partial walk reported as OK would be the same false green
      // this gate exists to remove, one level further out.
      console.error(`check-conflict-markers: cannot walk ${root}: ${err.message}`);
      console.error("The project tree was NOT scanned, so this is not a clean result.");
      return 2;
    }
  }

  const bad = [];
  let scanned = 0;
  let skipped = 0;
  const head = Buffer.alloc(8192);
  for (const path of paths) {
    let st;
    try {
      st = lstatSync(path);
    } catch (err) {
      // git lists a tracked file that was deleted from the working tree; there
      // is nothing on disk to scan. Any other error is a failure to read.
      if (source === "git" && err.code === "ENOENT") continue;
      console.error(`check-conflict-markers: cannot read ${path}: ${err.message}`);
      return 2;
    }
    // Symlinks, submodule directories (gitlinks) and anything else that is not
    // a regular file are not content this gate reads, matching the walk.
    if (!st.isFile()) continue;
    let buf;
    try {
      // A NUL byte in the first 8 KiB means binary. Decoding one as UTF-8
      // cannot produce a line-anchored fence, so only that head is read before
      // deciding, and the count below reports the skips rather than hiding them.
      const fd = openSync(path, "r");
      let got;
      try {
        got = readSync(fd, head, 0, head.length, 0);
      } finally {
        closeSync(fd);
      }
      if (head.subarray(0, got).includes(0)) {
        skipped += 1;
        continue;
      }
      buf = readFileSync(path);
    } catch (err) {
      console.error(`check-conflict-markers: cannot read ${path}: ${err.message}`);
      return 2;
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
      `${skipped > 0 ? `, ${skipped} binary file(s) skipped` : ""}` +
      ` (${source === "git" ? "git-listed files plus the handoff directory" : "directory walk"}).`,
  );
  return 0;
}

const isMain =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMain) {
  // Any unexpected error is "could not run" (2), never node's default exit 1,
  // which is this gate's "markers found" code.
  let code;
  try {
    code = main();
  } catch (err) {
    console.error(`check-conflict-markers: could not run: ${err && err.message ? err.message : err}`);
    code = 2;
  }
  process.exit(code);
}
