#!/usr/bin/env node
// aahp-dashboard.mjs - Generic handoff generator + freshness gate.
//
// Two portable mechanisms, both config-driven and opt-in so this never clobbers
// a project that has not asked for them:
//
//   1. LOG release-journal generator (config.generate.log): renders a Markdown
//      release table from CHANGELOG.md into a target file, using the SINGLE
//      grammar in changelog-grammar.mjs (so generator and validator cannot
//      diverge). Opt-in on purpose: .ai/handoff/LOG.md is the append-only agent
//      journal, NOT a release journal (README ADR-004), so AAHP does not
//      configure log generation and its journal is left untouched.
//
//      The target is REQUIRED and may never be the agent journal. It used to
//      default to .ai/handoff/LOG.md, and aahp.config.example.json pointed it
//      there too, so an adopter who copied the example had every session entry
//      replaced by a release table on the first handoff-refresh (writeFileSync,
//      no merge). resolveLogTarget() now refuses LOG.md, LOG-ARCHIVE.md and
//      LOG-ARCHIVE.index.json in both modes, and an unset target, before any
//      file is read or written.
//   2. NEXT_ACTIONS current-version freshness gate: the hand-curated backlog's
//      stated "Current version: **vX.Y.Z**" must equal package.json. This is the
//      ungated hand-doc drift that lets a backlog sit on an old version while the
//      repo ships a newer one. Runs by default against .ai/handoff/NEXT_ACTIONS.md;
//      silently skips when the file or the header line is absent.
//
// The root package.json is OPTIONAL. A polyglot project can adopt AAHP at a root
// that has none (a Python service whose only package.json lives in a frontend
// subdirectory) and still keep a perfectly valid handoff set at .ai/handoff/.
// Without one there is no version to compare against, so the freshness gate
// skips and the LOG title falls back to the root directory name, rather than the
// whole gate exiting 1 before it does any work.
//
// Modes:
//   node scripts/aahp-dashboard.mjs [path]           -> WRITE (regenerate the LOG)
//   node scripts/aahp-dashboard.mjs [path] --check    -> GATE (fail if stale)
//
// Config (aahp.config.json):
//   "generate": {
//     "log": { "source": "CHANGELOG.md", "target": "docs/RELEASES.md",
//              "title": "My Project: Release Journal" },
//     "freshness": { "file": ".ai/handoff/NEXT_ACTIONS.md" }
//   }

import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { basename, dirname, join, resolve } from "node:path";
import { resolveRoot, loadPkg, loadConfig, resolveBash, toBashPath } from "./aahp-config.mjs";
import { parseReleases } from "./changelog-grammar.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolveRoot();
const isCheck = process.argv.includes("--check");

// Absence of a root package.json makes the version-derived half of this gate
// inapplicable, and a gate that cannot apply must not fail. A package.json that
// IS present but malformed still throws, so a real defect stays loud.
function loadPkgOptional(dir) {
  try {
    return loadPkg(dir);
  } catch (err) {
    if (err.code === "AAHP_NO_PKG") return null;
    throw err;
  }
}

let pkg;
let config;
try {
  pkg = loadPkgOptional(root);
  config = loadConfig(root);
} catch (err) {
  console.error(`  handoff generator: ${err.message}`);
  process.exit(1);
}

const gen = config.generate || {};
const norm = (s) => s.replace(/\r/g, ""); // CRLF-agnostic (Windows working tree)

// --- where the release journal may be written ---------------------------------

// The agent journal and its archive. Overwriting any of them destroys session
// history that exists nowhere else (README ADR-004 and section 2.9).
const REFUSED_TARGETS = [".ai/handoff/LOG.md", ".ai/handoff/LOG-ARCHIVE.md", ".ai/handoff/LOG-ARCHIVE.index.json"];

// Same file? Compared case-insensitively on the resolved path (Windows and
// macOS default to case-insensitive filesystems, so "log.md" IS "LOG.md"
// there), and through realpath when both exist, so a symlink or a directory
// alias cannot smuggle the journal past the check.
function sameFile(a, b) {
  const key = (p) => p.replace(/\\/g, "/").toLowerCase();
  if (key(a) === key(b)) return true;
  try {
    return realpathSync(a) === realpathSync(b);
  } catch {
    return false;
  }
}

// Returns { rel, abs } for a permitted target, or { error } for a refused one.
function resolveLogTarget(logCfg) {
  const rel = logCfg.target;
  if (typeof rel !== "string" || rel.trim() === "") {
    return {
      error:
        "generate.log.target is not set. It used to default to .ai/handoff/LOG.md, the append-only " +
        "agent journal, which this generator must never overwrite (README ADR-004). Set " +
        'generate.log.target to a separate file, for example "docs/RELEASES.md".',
    };
  }
  const abs = resolve(root, rel);
  const hit = REFUSED_TARGETS.find((r) => sameFile(resolve(root, r), abs));
  if (hit) {
    return {
      error:
        `generate.log.target "${rel}" is ${hit}, part of the append-only agent journal, and this ` +
        "generator overwrites its target, so it refuses to write there (README ADR-004). Point " +
        'generate.log.target at a separate file, for example "docs/RELEASES.md".',
    };
  }
  return { rel, abs };
}

let logTarget = null;
if (gen.log) {
  logTarget = resolveLogTarget(gen.log);
  if (logTarget.error) {
    console.error(`  handoff generator: ${logTarget.error}`);
    process.exit(1);
  }
}

// --- render the LOG release journal from CHANGELOG (if configured) ----------

function renderLog(logCfg) {
  const source = join(root, logCfg.source || "CHANGELOG.md");
  if (!existsSync(source)) {
    throw new Error(`generate.log.source not found: ${logCfg.source || "CHANGELOG.md"}`);
  }
  const releases = parseReleases(readFileSync(source, "utf8"));
  const rows = releases.map((r) => `| v${r.version} | ${r.date || "-"} | ${r.headline} |`).join("\n");
  const title = logCfg.title || `${pkg ? pkg.name : basename(root)}: Release Journal`;
  return (
    `# ${title}\n\n` +
    `> AUTO-GENERATED by aahp (scripts/aahp-dashboard.mjs) from ${logCfg.source || "CHANGELOG.md"}. Do NOT hand-edit.\n` +
    `> Regenerate with the handoff-refresh step; the --check gate fails the build\n` +
    `> if this file is stale, so it cannot silently drift.\n\n` +
    `---\n\n` +
    `## Releases (${releases.length}, newest first)\n\n` +
    `| Version | Date | Headline |\n` +
    `|---------|------|----------|\n` +
    `${rows}\n`
  );
}

// --- freshness gate ----------------------------------------------------------

function freshnessTarget() {
  const rel = gen.freshness && gen.freshness.file ? gen.freshness.file : ".ai/handoff/NEXT_ACTIONS.md";
  return join(root, rel);
}

function checkFreshness() {
  const p = freshnessTarget();
  if (!existsSync(p)) return { status: "skip", reason: "no freshness file" };
  if (!pkg) return { status: "skip", reason: "no root package.json to compare the stated version against" };
  const m = readFileSync(p, "utf8").match(/Current version:\s*\*\*v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\*\*/i);
  if (!m) return { status: "skip", reason: "no 'Current version' header line" };
  if (m[1] !== pkg.version) return { status: "fail", found: m[1] };
  return { status: "pass" };
}

// --- run ---------------------------------------------------------------------

if (isCheck) {
  const problems = [];

  if (gen.log) {
    const target = logTarget.abs;
    let expected;
    try {
      expected = renderLog(gen.log);
    } catch (err) {
      console.error(`  handoff generator: ${err.message}`);
      process.exit(1);
    }
    const current = existsSync(target) ? readFileSync(target, "utf8") : "";
    if (norm(current) !== norm(expected)) {
      problems.push(`${logTarget.rel} is stale - run the handoff-refresh step to regenerate it from CHANGELOG.md.`);
    }
  }

  const fresh = checkFreshness();
  if (fresh.status === "fail") {
    problems.push(`NEXT_ACTIONS "Current version" is v${fresh.found} but package.json is v${pkg.version} - update the header line.`);
  }

  if (problems.length > 0) {
    console.error("\n  Handoff generator check failed:\n");
    for (const p of problems) console.error(`  - ${p}`);
    console.error("");
    process.exit(1);
  }

  const parts = [];
  parts.push(gen.log ? `${logTarget.rel} in sync with ${gen.log.source || "CHANGELOG.md"}` : "no LOG generation configured");
  parts.push(
    fresh.status === "pass"
      ? "NEXT_ACTIONS current-version matches package.json"
      : `freshness ${fresh.status}${fresh.reason ? ` (${fresh.reason})` : ""}`,
  );
  console.log(`Handoff generator OK: ${parts.join("; ")}.`);
} else {
  if (!gen.log) {
    console.log("Handoff generator: no generate.log configured; nothing to write.");
    process.exit(0);
  }
  const target = logTarget.abs;
  let content;
  try {
    content = renderLog(gen.log);
  } catch (err) {
    console.error(`  handoff generator: ${err.message}`);
    process.exit(1);
  }
  try {
    // The target is now a separate file (docs/RELEASES.md in the example), so
    // its directory may not exist yet.
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, content);
  } catch (err) {
    console.error(`  handoff generator: could not write ${logTarget.rel}: ${err.message}`);
    process.exit(1);
  }
  // Regenerate MANIFEST.json so its checksums match the file we just wrote
  // (unchanged behaviour: it runs whatever the target, and a target outside
  // .ai/handoff/ is simply not indexed).
  // Delegate to the canonical writer (sibling script), overridable via AAHP_BASH.
  //
  // The interpreter and both path arguments go through the helpers rather than
  // being passed raw: on Windows a bare "bash" can resolve to the WSL launcher,
  // which cannot see the C: drive, and native backslash paths are eaten as
  // escapes by any bash. See resolveBash/toBashPath in aahp-config.mjs.
  try {
    execFileSync(
      resolveBash(),
      [
        // The child spawns with cwd: root below, so root - not process.cwd() -
        // is the base a relative path must be computed against.
        toBashPath(join(scriptDir, "aahp-manifest.sh"), process.platform, root),
        toBashPath(root, process.platform, root),
        "--agent",
        "handoff-refresh",
        "--phase",
        "idle",
        "--quiet",
      ],
      { stdio: "inherit", cwd: root },
    );
  } catch (err) {
    console.error(
      `\n  ${logTarget.rel} was written, but MANIFEST.json regen failed:\n` +
        `  ${err.message}\n` +
        `  Run manually: aahp manifest . --quiet\n`,
    );
    process.exit(1);
  }
  console.log(`handoff-refresh OK: regenerated ${logTarget.rel} + MANIFEST.json.`);
}
