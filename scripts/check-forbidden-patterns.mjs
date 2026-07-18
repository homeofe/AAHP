#!/usr/bin/env node
// check-forbidden-patterns.mjs - Config-driven denylist gate. Fails if any
// configured regex matches in a tracked file, giving the repo's stated hard
// rules (no em dashes, no model names / prompt text where banned) real teeth.
// A clean no-op when forbiddenPatterns is absent, like the other gates.
//
//   "forbiddenPatterns": [
//     { "id": "em-dash", "pattern": "\\u2014",
//       "message": "em dash (U+2014) is banned; use a hyphen" },
//     { "id": "no-model-names", "pattern": "\\b(?:claude-|gpt-|gemini|sonnet|opus)\\b",
//       "flags": "gim", "include": ["scripts/*", "schema/*"],
//       "message": "no model names in scripts/ or schema/" }
//   ]
//
// pattern is a regex source; flags default "gm". include/exclude are git
// pathspecs (default: common text files). Files are enumerated with
// `git ls-files` via execFileSync (NO shell) so only tracked files are scanned
// and a config string cannot inject shell metacharacters. Store literal-unicode
// bans as an escape (e.g. "\\u2014") so the config file itself does not match.

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { resolveRoot, loadConfig } from "./aahp-config.mjs";

const root = resolveRoot();

let config;
try {
  config = loadConfig(root);
} catch (err) {
  console.error(`  forbidden-patterns: ${err.message}`);
  process.exit(1);
}

const rules = Array.isArray(config.forbiddenPatterns) ? config.forbiddenPatterns : [];
if (rules.length === 0) {
  console.log("Forbidden patterns: none configured; nothing to check.");
  process.exit(0);
}

const DEFAULT_INCLUDE = ["*.md", "*.mjs", "*.js", "*.json", "*.sh", "*.bash", "*.yml", "*.yaml", "*.txt"];

function gitLsFiles(specs) {
  try {
    const out = execFileSync("git", ["-C", root, "ls-files", "-z", "--", ...specs], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    return out.split("\0").filter(Boolean);
  } catch {
    return [];
  }
}

const failures = [];

for (const rule of rules) {
  const { id = "(unnamed)", pattern, flags, message, include, exclude } = rule;
  let re;
  try {
    re = new RegExp(pattern, flags || "gm");
  } catch (err) {
    failures.push({ id, msg: `invalid pattern ${JSON.stringify(pattern)}: ${err.message}` });
    continue;
  }
  const includeSpecs = Array.isArray(include) && include.length ? include : DEFAULT_INCLUDE;
  const files = new Set(gitLsFiles(includeSpecs));
  if (Array.isArray(exclude) && exclude.length) {
    for (const f of gitLsFiles(exclude)) files.delete(f);
  }
  for (const rel of files) {
    let text;
    try {
      text = readFileSync(join(root, rel), "utf8");
    } catch {
      continue;
    }
    text.split(/\r?\n/).forEach((line, i) => {
      re.lastIndex = 0;
      if (re.test(line)) {
        failures.push({ id, file: rel, line: i + 1, message: message || "forbidden pattern", snippet: line.trim().slice(0, 100) });
      }
    });
  }
}

if (failures.length > 0) {
  console.error(`\n  Forbidden-pattern check failed (${failures.length} match(es)).\n`);
  for (const f of failures) {
    if (f.file) console.error(`  - ${f.file}:${f.line} [${f.id}] ${f.message}\n      ${f.snippet}`);
    else console.error(`  - [${f.id}] ${f.msg}`);
  }
  console.error("");
  process.exit(1);
}

console.log(`Forbidden patterns OK: ${rules.length} rule(s), no matches.`);
