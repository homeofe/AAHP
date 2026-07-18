#!/usr/bin/env node
// check-doc-links.mjs - Config-driven broken-link gate. Resolves internal
// Markdown links in the configured files against the filesystem and fails if a
// relative file target does not exist. Skips external (http/https/mailto) links
// and same-file "#anchor" links (anchor validation is intentionally out of
// scope - low value, brittle across renderers). A clean no-op when docLinks is
// absent.
//
//   "docLinks": {
//     "include": ["README.md", "CLAUDE.md", ".ai/handoff/*.md"]
//   }
// include is a list of git pathspecs (default: README.md + CLAUDE.md +
// CONTRIBUTING.md + .ai/handoff/*.md). Files are enumerated with git ls-files
// via execFileSync (no shell).

import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, dirname, resolve } from "node:path";
import { resolveRoot, loadConfig } from "./aahp-config.mjs";

const root = resolveRoot();

let config;
try {
  config = loadConfig(root);
} catch (err) {
  console.error(`  doc-links: ${err.message}`);
  process.exit(1);
}

if (!config.docLinks) {
  console.log("Doc links: not configured; nothing to check.");
  process.exit(0);
}

const DEFAULT_INCLUDE = ["README.md", "CLAUDE.md", "CONTRIBUTING.md", ".ai/handoff/*.md"];
const include = Array.isArray(config.docLinks.include) && config.docLinks.include.length ? config.docLinks.include : DEFAULT_INCLUDE;

function gitLsFiles(specs) {
  try {
    const out = execFileSync("git", ["-C", root, "ls-files", "-z", "--", ...specs], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    return out.split("\0").filter(Boolean);
  } catch {
    return [];
  }
}

// Markdown inline link: [text](target). Capture the target (group 1).
const LINK_RE = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
const failures = [];
let checked = 0;

for (const rel of gitLsFiles(include)) {
  let text;
  try {
    text = readFileSync(join(root, rel), "utf8");
  } catch {
    continue;
  }
  const dir = dirname(join(root, rel));
  for (const m of text.matchAll(LINK_RE)) {
    let target = m[1];
    if (/^(https?:|mailto:|#)/i.test(target)) continue; // external or same-file anchor
    // Strip a trailing #anchor and any ?query from the file portion.
    target = target.split("#")[0].split("?")[0];
    if (!target) continue;
    checked++;
    const resolved = resolve(dir, target);
    if (!existsSync(resolved)) {
      failures.push({ file: rel, target: m[1] });
    }
  }
}

if (failures.length > 0) {
  console.error(`\n  Doc-links check failed: ${failures.length} broken internal link(s).\n`);
  for (const f of failures) console.error(`  - ${f.file}: broken link to "${f.target}"`);
  console.error("");
  process.exit(1);
}

console.log(`Doc links OK: ${checked} internal file link(s) resolve.`);
