#!/usr/bin/env node
// check-doc-links.mjs - Config-driven broken-link gate. Resolves internal
// Markdown links in the configured files against the filesystem and fails if a
// file target does not exist. Skips links with any URI scheme (http/https/ftp/
// mailto/...), protocol-relative "//host" links, and same-file "#anchor" links
// (anchor validation is intentionally out of scope - low value, brittle across
// renderers). Root-relative ("/x") targets resolve against the repo root; others
// against the linking file's directory. Percent-encoded targets are decoded. A
// clean no-op when docLinks is absent.
//
//   "docLinks": {
//     "include": ["README.md", "CLAUDE.md", ".ai/handoff/*.md"]
//   }
// include is a list of git pathspecs (default: README.md + CLAUDE.md +
// CONTRIBUTING.md + .ai/handoff/*.md). Files are enumerated with git ls-files
// via execFileSync (no shell).

import { existsSync, readFileSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { resolveRoot, loadConfig, isInsideWorkTree, listTrackedFiles } from "./aahp-config.mjs";

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

// Fail loud outside a git work tree: `git ls-files` would enumerate zero files
// and the gate would vacuously pass, so a broken link could ship undetected.
if (!isInsideWorkTree(root)) {
  console.error(
    `  doc-links: not inside a git work tree at ${root}; cannot enumerate files - run this gate inside a git checkout (in CI use actions/checkout)`,
  );
  process.exit(1);
}

const DEFAULT_INCLUDE = ["README.md", "CLAUDE.md", "CONTRIBUTING.md", ".ai/handoff/*.md"];
const include = Array.isArray(config.docLinks.include) && config.docLinks.include.length ? config.docLinks.include : DEFAULT_INCLUDE;

// Markdown inline link: [text](target). Capture the target (group 1).
const LINK_RE = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
const failures = [];
let checked = 0;

for (const rel of listTrackedFiles(root, include)) {
  let text;
  try {
    text = readFileSync(join(root, rel), "utf8");
  } catch {
    continue;
  }
  const dir = dirname(join(root, rel));
  for (const m of text.matchAll(LINK_RE)) {
    let target = m[1];
    // Skip external links (any URI scheme like http:/ftp:/git:), protocol-relative
    // ("//host/x"), and same-file anchors ("#x").
    if (/^(?:[a-z0-9+.-]+:|\/\/|#)/i.test(target)) continue;
    // Strip a trailing #anchor and any ?query from the file portion.
    target = target.split("#")[0].split("?")[0];
    if (!target) continue;
    checked++;
    // Percent-decode ("my%20file.md" -> "my file.md"); tolerate a stray "%".
    let decoded;
    try {
      decoded = decodeURIComponent(target);
    } catch {
      decoded = target;
    }
    // A root-relative link ("/x") resolves against the REPO root; others against
    // the linking file's directory.
    const resolved = decoded.startsWith("/") ? join(root, decoded) : resolve(dir, decoded);
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
