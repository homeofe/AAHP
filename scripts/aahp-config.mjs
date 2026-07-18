// aahp-config.mjs - Shared helpers for the config-driven AAHP release gates.
//
// These gates ship INSIDE the @elvatis_com/aahp package and run against a
// CONSUMER project, so - unlike a vendored copy - they must resolve the target
// project root from the CLI argument (or cwd), NOT from the script's own
// location. Every gate imports resolveRoot/loadPkg/loadConfig from here so the
// resolution rules stay identical across gates and match the CLI convention
// used by the bash tooling: an optional [path] first positional, default ".".

import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

// Resolve the target project root: the first non-flag positional argument,
// else the current working directory. Mirrors the [path] convention in the
// bash scripts (path is the first arg that does not start with "--").
export function resolveRoot(argv = process.argv.slice(2)) {
  const positional = argv.find((a) => !a.startsWith("--"));
  return resolve(positional || ".");
}

// Read and parse the target package.json. Throws a labelled error if absent or
// invalid so a gate can report it cleanly instead of dumping a stack trace.
export function loadPkg(root) {
  const p = join(root, "package.json");
  if (!existsSync(p)) {
    const e = new Error(`package.json not found at ${p}`);
    e.code = "AAHP_NO_PKG";
    throw e;
  }
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch (err) {
    const e = new Error(`package.json is not valid JSON: ${err.message}`);
    e.code = "AAHP_PKG_INVALID";
    throw e;
  }
}

// Load aahp.config.json from the project root. Returns {} when absent so every
// gate degrades to a clean no-op on a repo that ships no config - AAHP must keep
// working for projects that never adopt one. Throws only on malformed JSON.
export function loadConfig(root) {
  const p = join(root, "aahp.config.json");
  if (!existsSync(p)) return {};
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch (err) {
    const e = new Error(`aahp.config.json is not valid JSON: ${err.message}`);
    e.code = "AAHP_CONFIG_INVALID";
    throw e;
  }
}

// Standard AAHP handoff files, parsed from the canonical bash source of truth
// (_aahp-lib.sh -> AAHP_HANDOFF_FILES) so the Node tooling can never drift from
// the shell tooling. packageRoot is the directory that contains scripts/.
export function handoffFiles(packageRoot) {
  const lib = readFileSync(join(packageRoot, "scripts", "_aahp-lib.sh"), "utf8");
  const m = lib.match(/AAHP_HANDOFF_FILES=\(([^)]*)\)/);
  if (!m) throw new Error("could not parse AAHP_HANDOFF_FILES from scripts/_aahp-lib.sh");
  return m[1].split(/\s+/).map((s) => s.trim()).filter(Boolean);
}
