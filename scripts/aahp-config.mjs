// aahp-config.mjs - Shared helpers for the config-driven AAHP release gates.
//
// These gates ship INSIDE the @elvatis_com/aahp package and run against a
// CONSUMER project, so - unlike a vendored copy - they must resolve the target
// project root from the CLI argument (or cwd), NOT from the script's own
// location. Every gate imports resolveRoot/loadPkg/loadConfig from here so the
// resolution rules stay identical across gates and match the CLI convention
// used by the bash tooling: an optional [path] first positional, default ".".

import { existsSync, readFileSync } from "node:fs";
import { join, resolve, relative, isAbsolute } from "node:path";
import { execFileSync } from "node:child_process";

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

// Return true iff root is inside a git work tree. Uses `git rev-parse
// --is-inside-work-tree`, which correctly reports true for linked worktrees and
// submodules (not only the primary checkout). Returns false on any throw (git
// missing, or not a repo) so callers can fail loud with an actionable message
// instead of silently scanning zero files.
export function isInsideWorkTree(root) {
  try {
    const out = execFileSync("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], {
      encoding: "utf8",
    });
    return out.trim() === "true";
  } catch {
    return false;
  }
}

// Enumerate tracked files under root matching the given git pathspecs, using
// `git ls-files` via execFileSync (NO shell) so only tracked files are scanned
// and a pathspec cannot inject shell metacharacters. Throws AAHP_NO_GIT when
// root is not inside a git work tree, so an enumerating gate fails loud instead
// of vacuously passing on an empty file list outside a checkout.
export function listTrackedFiles(root, specs) {
  if (!isInsideWorkTree(root)) {
    const e = new Error(
      `not inside a git work tree at ${root}; cannot enumerate files - run this gate inside a git checkout (in CI use actions/checkout)`,
    );
    e.code = "AAHP_NO_GIT";
    throw e;
  }
  const out = execFileSync("git", ["-C", root, "ls-files", "-z", "--", ...specs], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  return out.split("\0").filter(Boolean);
}

// Convert a filesystem path into a form a POSIX shell reads correctly.
//
// On Windows a native path is backslash-separated, and bash consumes each
// backslash as an escape character: "C:\Users\x\s.sh" reaches the interpreter
// as "C:Usersxs.sh" and fails with "No such file or directory".
//
// Three strategies, most robust first:
//   1. A path under `cwd` becomes relative, which sidesteps the drive-letter
//      question entirely and so works under any bash flavour.
//   2. An absolute drive path becomes the MSYS form Git Bash understands
//      (C:\x -> /c/x).
//   3. Anything else has its separators swapped.
//
// Off win32 this is a no-op, because a backslash is a legal character in a
// POSIX filename and rewriting it would corrupt a valid path.
//
// `cwd` MUST be the working directory the child process will run in, which is
// not always process.cwd(). Pass it explicitly when they differ, or strategy 1
// yields a path relative to the wrong directory.
//
// Caveat for callers passing an explicit `platform`: the relative/absolute
// tests use the HOST's path semantics, so on a non-Windows host strategy 1 can
// engage where a real Windows run would fall through to strategy 2. Tests that
// need a specific strategy should pass a `cwd` that forces it.
export function toBashPath(p, platform = process.platform, cwd = process.cwd()) {
  if (platform !== "win32") return String(p);
  const s = String(p);
  const rel = relative(cwd, s);
  if (rel && !rel.startsWith("..") && !isAbsolute(rel)) return rel.replace(/\\/g, "/");
  const drive = s.match(/^([A-Za-z]):\\(.*)$/);
  if (drive) return `/${drive[1].toLowerCase()}/${drive[2].replace(/\\/g, "/")}`;
  return s.replace(/\\/g, "/");
}

// Resolve the bash interpreter used to run the POSIX helper scripts.
//
// AAHP_BASH always wins, so a consumer can pin a specific interpreter.
// Off win32, "bash" from PATH is correct and is returned unchanged.
//
// On Windows, "bash" from PATH is NOT reliably a POSIX shell. A default Git for
// Windows install puts only Git's cmd/ directory on PATH, which carries git.exe
// but not bash.exe, while Windows itself ships C:\Windows\System32\bash.exe:
// the WSL launcher. PATH order then resolves a bare "bash" to WSL, whose root
// filesystem has no C: drive, so a Windows-shaped script path cannot be opened
// at all and the call fails no matter how the path is spelled. Prefer an
// explicit Git Bash, and fall back to "bash" when none is found so the failure
// stays the caller's to report rather than being masked here.
//
// The candidate list is driven by environment variables rather than hardcoded
// to "C:\Program Files", so a Git install on another drive is still found, and
// covers both the machine-wide and the per-user (LOCALAPPDATA) install layouts
// as well as Git's usr/bin location.
//
// env and platform are injectable so the win32 behaviour is testable on any
// host, including the Linux CI runner.
export function resolveBash(env = process.env, platform = process.platform) {
  if (env.AAHP_BASH) return env.AAHP_BASH;
  if (platform !== "win32") return "bash";
  const pf = env.ProgramFiles || "C:\\Program Files";
  const pf86 = env["ProgramFiles(x86)"] || "C:\\Program Files (x86)";
  const candidates = [
    join(pf, "Git", "bin", "bash.exe"),
    join(pf, "Git", "usr", "bin", "bash.exe"),
    join(pf86, "Git", "bin", "bash.exe"),
    ...(env.LOCALAPPDATA ? [join(env.LOCALAPPDATA, "Programs", "Git", "bin", "bash.exe")] : []),
  ];
  return candidates.find((c) => existsSync(c)) || "bash";
}
