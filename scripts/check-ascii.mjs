#!/usr/bin/env node
// check-ascii.mjs - every tracked text file is pure ASCII: no code point above
// U+007F, and no byte order mark.
//
// WHY THIS GATE EXISTS
// ---------------------------------------------------------------------------
// Owner decision, 2026-09-28: full ASCII, enforced by a gate. The rule this
// replaces banned one code point (U+2014, via forbiddenPatterns in
// aahp.config.json) and let every other one through. Measured on the tree this
// gate landed on: 26 tracked files carried 2,753 non-ASCII code points (box
// drawing rulers, check marks, arrows, emoji, a literal BOM inside a regex), and
// none of them was an em dash, so the em-dash rule was green over all of them.
// The cost is concrete, not stylistic: a Windows console on code page cp1252
// cannot encode U+2705 or U+2192 at all (Python raises UnicodeEncodeError on
// both, measured), and scripts/lint-handoff.sh printed U+2713 / U+2717 / U+26A0
// to exactly such consoles. A denylist of the characters somebody has already
// been bitten by is always one character behind; an allowlist of 0x00-0x7F is
// not.
//
// WHAT IT READS
// ---------------------------------------------------------------------------
// Every path `git ls-files` lists under the target root: tracked files only, so
// an untracked scratch file never fails the build and a new file counts from the
// moment it is added. The working-tree content is what is read.
//
//   - A file containing a NUL byte is binary and exempt (images, archives). That
//     is the same test git and grep use; it is counted and printed, never silent.
//   - A UTF-8 byte order mark is a finding (U+FEFF at 1:1). TextDecoder strips
//     a leading BOM by default, which would have hidden exactly this case, so
//     the decoder is built with ignoreBOM: true.
//   - Bytes that are not valid UTF-8 are findings too, reported as raw bytes.
//   - A tracked symlink is checked as what git stores for it: the link text.
//   - A submodule (gitlink) is another repository and is not read.
//   - File NAMES are not checked; this is a content rule.
//
// Every line this gate prints is itself ASCII: the offending character is named
// by its code point, never echoed, for the same console reason.
//
// USAGE
//   node scripts/check-ascii.mjs [path] [--path=<pathspec>]...
//
// --path narrows the scan to git pathspecs (repeatable). The aggregate `check`
// chain passes none, and tests/assert-ascii-gate-wired.mjs fails if it ever
// does: the required gate reads the whole tree, and there is no exemption list.
// The flag exists for fixtures and for asking about one part of a tree.
//
// EXIT CODES
//   0  every tracked text file is pure ASCII
//   1  at least one non-ASCII code point or byte (wins over 2 when both apply)
//   2  could not assess: git missing, not a git work tree, nothing enumerated,
//      a tracked file that cannot be read, or an unknown argument
//
// Exit 2 exists so that "I could not look" is never reported as "I looked and it
// was fine".

import { lstatSync, readFileSync, readlinkSync } from "node:fs";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const EXIT_OK = 0;
const EXIT_FINDING = 1;
const EXIT_UNASSESSED = 2;

// Findings printed per file before the rest is summarised. The count is always
// exact; only the listing is capped.
const MAX_PER_FILE = 20;

function unassessed(msg) {
  console.error(`  ascii: ${ascii(msg)}`);
  process.exit(EXIT_UNASSESSED);
}

/** Render any string printable on an ASCII-only console. */
function ascii(s) {
  return String(s).replace(/[^\x00-\x7f]/gu, (ch) => `\\u{${ch.codePointAt(0).toString(16).toUpperCase()}}`);
}

function hex(cp, width) {
  return cp.toString(16).toUpperCase().padStart(width, "0");
}

// --- arguments ---------------------------------------------------------------
let rootArg = null;
const pathspecs = [];
for (const arg of process.argv.slice(2)) {
  if (arg.startsWith("--path=")) {
    const spec = arg.slice("--path=".length);
    if (!spec) unassessed("--path= needs a pathspec");
    pathspecs.push(spec);
  } else if (arg.startsWith("--")) {
    unassessed(`unknown argument ${arg}; usage: check-ascii.mjs [path] [--path=<pathspec>]...`);
  } else if (rootArg === null) {
    rootArg = arg;
  } else {
    unassessed(`more than one path given (${rootArg}, ${arg}); use --path=<pathspec> to narrow the scan`);
  }
}
const root = resolve(rootArg || ".");

// --- enumerate ---------------------------------------------------------------
function git(args) {
  return execFileSync("git", ["-C", root, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

try {
  execFileSync("git", ["--version"], { stdio: "ignore" });
} catch (err) {
  unassessed(`git could not be run (${err.code || err.message}); tracked files cannot be enumerated`);
}

let inside = "";
try {
  inside = git(["rev-parse", "--is-inside-work-tree"]).trim();
} catch {
  inside = "";
}
if (inside !== "true") {
  unassessed(
    `not inside a git work tree at ${root}; cannot enumerate tracked files - ` +
      "run this gate inside a git checkout (in CI use actions/checkout)",
  );
}

// --stage gives the mode, which is how a symlink (120000) and a submodule
// (160000) are told apart from a regular file. A path in a merge conflict is
// listed once per stage, hence the Map.
const entries = new Map();
for (const rec of git(["ls-files", "-z", "--stage", "--", ...pathspecs]).split("\0")) {
  if (!rec) continue;
  const tab = rec.indexOf("\t");
  const mode = rec.slice(0, rec.indexOf(" "));
  entries.set(rec.slice(tab + 1), mode);
}

if (entries.size === 0) {
  unassessed(
    pathspecs.length
      ? `no tracked file matches ${pathspecs.join(", ")} under ${root}. A gate that read nothing must not report clean.`
      : `git ls-files enumerated nothing under ${root}. A gate that read nothing must not report clean.`,
  );
}

// --- scan --------------------------------------------------------------------
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** Every non-ASCII code point (or invalid byte) in buf, with 1-based line/column. */
function scan(buf) {
  const found = [];
  if (!buf.some((b) => b > 0x7f)) return found;
  let text = null;
  try {
    text = decoder.decode(buf);
  } catch {
    text = null;
  }
  let line = 1;
  let col = 0;
  if (text !== null) {
    for (const ch of text) {
      const cp = ch.codePointAt(0);
      if (cp === 0x0a) {
        line += 1;
        col = 0;
        continue;
      }
      col += 1;
      if (cp > 0x7f) found.push({ line, col, what: `U+${hex(cp, 4)}${cp === 0xfeff ? " (byte order mark)" : ""}` });
    }
    return found;
  }
  // Not valid UTF-8: report the bytes themselves, columns counted in bytes.
  for (const b of buf) {
    if (b === 0x0a) {
      line += 1;
      col = 0;
      continue;
    }
    col += 1;
    if (b > 0x7f) found.push({ line, col, what: `byte 0x${hex(b, 2)} (not valid UTF-8)` });
  }
  return found;
}

const failures = [];
const unreadable = [];
const binary = [];
let textFiles = 0;

for (const [rel, mode] of [...entries].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))) {
  if (mode === "160000") continue; // submodule: another repository's content
  const abs = join(root, rel);
  let buf;
  try {
    if (mode === "120000" && lstatSync(abs).isSymbolicLink()) {
      buf = Buffer.from(readlinkSync(abs), "utf8");
    } else {
      buf = readFileSync(abs);
    }
  } catch (err) {
    unreadable.push(
      err.code === "ENOENT"
        ? `${rel}: tracked but missing from the working tree (restore it, or git rm it)`
        : `${rel}: tracked but could not be read (${err.code || err.message})`,
    );
    continue;
  }
  if (buf.includes(0)) {
    binary.push(rel);
    continue;
  }
  textFiles += 1;
  const found = scan(buf);
  if (found.length) failures.push({ rel, found });
}

if (failures.length) {
  const total = failures.reduce((n, f) => n + f.found.length, 0);
  console.error(`\n  ASCII check failed: ${total} non-ASCII code point(s) in ${failures.length} tracked file(s).\n`);
  for (const { rel, found } of failures) {
    console.error(`  ${ascii(rel)}: ${found.length}`);
    for (const f of found.slice(0, MAX_PER_FILE)) console.error(`    ${ascii(rel)}:${f.line}:${f.col} ${f.what}`);
    if (found.length > MAX_PER_FILE) console.error(`    ... and ${found.length - MAX_PER_FILE} more in this file`);
  }
  console.error(
    "\n  Every tracked text file must be pure ASCII (owner decision 2026-09-28). Use a plain" +
      "\n  equivalent: '-' for dashes and rulers, '->' for arrows, 'OK' / 'x' / '!' for status" +
      "\n  marks. Never an em dash; use a comma, colon, full stop or brackets. A test that needs" +
      "\n  non-ASCII input generates the bytes at runtime (printf '\\303\\274') instead.\n",
  );
}
if (unreadable.length) {
  console.error(`\n  ASCII check could not read ${unreadable.length} tracked file(s). That is not a pass:`);
  for (const u of unreadable) console.error(`    ${ascii(u)}`);
  console.error("");
}

// A finding is a definite answer and wins; otherwise an unread file means the
// question was not fully asked.
if (failures.length) process.exit(EXIT_FINDING);
if (unreadable.length) process.exit(EXIT_UNASSESSED);

const scope = pathspecs.length ? ` matching ${ascii(pathspecs.join(", "))}` : "";
console.log(
  `ASCII OK: ${textFiles} tracked text file(s)${scope} are pure ASCII` +
    (binary.length ? `; ${binary.length} binary file(s) exempt (NUL byte): ${ascii(binary.join(", "))}` : "") +
    ".",
);
process.exit(EXIT_OK);
