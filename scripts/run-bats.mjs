#!/usr/bin/env node
// run-bats.mjs - Launch the locked bats dependency with the correct bash and
// path spelling on Linux, macOS, and Windows.
//
// Two guards run around bats, because a suite can be green without asserting:
//
// 1. Bash older than 4.1 (macOS /bin/bash is 3.2) does not apply `set -e` to a
//    failing `[[ ]]` or `(( ))` unless it is the last command of the test, so
//    most assertions in this suite could never fail there (bats-core documents
//    this as a gotcha). Bats runs each test through `#!/usr/bin/env bash`, i.e.
//    the FIRST bash on PATH, so that is the one probed. An old one is refused,
//    and the refusal names the fix (on macOS: `brew install bash`, then put that
//    bash first on PATH); AAHP_ALLOW_OLD_BASH=1 runs anyway, for someone who
//    knows the verdict is partial.
// 2. With CI set, a skipped test is a failure unless it is listed in
//    ALLOWED_SKIPS below. `[ -n "$tool" ] || skip` fails open: a broken lookup
//    turns the test into a green skip. tests/test_helper.bash `require_tool`
//    fails such tests on CI directly; this catches every other skip, including
//    ones added later. The verdict is read from a TAP report bats writes next to
//    its normal output, so what the console shows is unchanged.

import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveBash, toBashPath } from "./aahp-config.mjs";

// Skips that are CORRECT on some platform, by exact test name and reason. Both
// are Windows-only (uname MINGW/MSYS/CYGWIN), so on the Linux CI runner neither
// fires; they are listed so a Windows CI job would not need a code change.
const ALLOWED_SKIPS = [
  {
    test: "aahp init fails with permission error on read-only directory",
    reason: "chmod does not model Windows directory ACLs",
  },
  {
    test: "handoff-refresh: passes a resolvable script path and root to the interpreter",
    reason: "stand-in interpreter relies on a POSIX shebang",
  },
];

function isCi(env = process.env) {
  const v = env.CI;
  return v !== undefined && !["", "0", "false", "FALSE", "False", "no"].includes(v);
}

// Every `ok N name # skip [reason]` line in a TAP stream, as { test, reason }.
function tapSkips(tap) {
  const out = [];
  for (const line of tap.split(/\r?\n/)) {
    const m = /^ok \d+ (.*?) # skip(?: (.*))?$/.exec(line);
    if (!m) continue;
    let reason = (m[2] ?? "").trim();
    if (reason.startsWith("(") && reason.endsWith(")")) reason = reason.slice(1, -1);
    out.push({ test: m[1], reason });
  }
  return out;
}

function unexpectedSkips(tap, allowed = ALLOWED_SKIPS) {
  return tapSkips(tap).filter(
    (s) => !allowed.some((a) => a.test === s.test && a.reason === s.reason),
  );
}

function main() {
  const scriptDir = dirname(fileURLToPath(import.meta.url));
  const root = resolve(scriptDir, "..");
  const bats = join(root, "node_modules", "bats", "bin", "bats");
  const requested = process.argv.slice(2);
  const batsArgs = requested.length > 0
    ? requested.map((arg) => {
        // Keep Bats options and their values untouched. Only absolute filesystem
        // arguments need translation for the selected Bash on Windows.
        // A leading slash is already Bash-native on Windows and may also be a
        // regex value for --filter, so only translate native drive paths there.
        const absolutePath = process.platform === "win32"
          ? /^[A-Za-z]:[\\/]/.test(arg)
          : arg.startsWith("/");
        return absolutePath ? toBashPath(resolve(arg), process.platform, root) : arg;
      })
    : [toBashPath(join(root, "tests"), process.platform, root)];

  if (!existsSync(bats)) {
    console.error("Bats is not installed. Run `npm ci` first.");
    process.exit(2);
  }

  const bash = resolveBash();

  // Guard 1: the bash that will run the test bodies. $BASH names which one, so
  // the refusal can say which file on PATH is the problem.
  const probe = spawnSync(bash, ["-c", "env bash -c 'echo \"${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]} $BASH\"'"], {
    cwd: root,
    encoding: "utf8",
  });
  const probed = String(probe.stdout || "").trim().split(/\s+/);
  const [major, minor] = probed.slice(0, 2).map(Number);
  const probedPath = probed.slice(2).join(" ");
  if (Number.isInteger(major) && Number.isInteger(minor) && (major < 4 || (major === 4 && minor < 1))) {
    const where = probedPath ? ` (${probedPath})` : "";
    const msg = [
      `run-bats: the first bash on PATH${where} is ${major}.${minor}. Before 4.1, a failing [[ ]] or (( )) ` +
        `that is not a test's last command does not fail the test, so most assertions in this ` +
        `suite cannot go red.`,
      "run-bats: to fix it on macOS, whose /bin/bash is 3.2:",
      "  1. brew install bash",
      "  2. make sure that bash is first on PATH: Homebrew puts it in $(brew --prefix)/bin",
      "     (/opt/homebrew/bin on Apple silicon, /usr/local/bin on Intel), so add",
      '     export PATH="$(brew --prefix)/bin:$PATH" to your shell profile and open a new shell',
      "  3. check: env bash --version must report 4.1 or newer",
      "run-bats: on any other system, install bash 4.1 or newer and put it first on PATH.",
    ].join("\n");
    if (process.env.AAHP_ALLOW_OLD_BASH === "1") {
      console.error(`${msg}\nrun-bats: AAHP_ALLOW_OLD_BASH=1 - running anyway; a green result here is partial.`);
    } else {
      console.error(
        `${msg}\nrun-bats: refusing to run. AAHP_ALLOW_OLD_BASH=1 overrides and runs the suite on this bash ` +
          "anyway; treat a green result from such a run as partial, because most assertions could not fail.",
      );
      process.exit(2);
    }
  }

  // Guard 2: under CI, collect a TAP report to audit skips. Not when the caller
  // manages reports or only counts tests.
  const ownsReport = requested.some((a) =>
    ["--report-formatter", "-o", "--output", "-c", "--count"].includes(a),
  );
  let reportDir = null;
  const extra = [];
  if (isCi() && !ownsReport) {
    reportDir = mkdtempSync(join(tmpdir(), "aahp-bats-report-"));
    extra.push("--report-formatter", "tap", "--output", toBashPath(reportDir, process.platform, root));
  }

  const args = [toBashPath(bats, process.platform, root), ...extra, ...batsArgs];
  const result = spawnSync(bash, args, { cwd: root, stdio: "inherit" });

  if (result.error) {
    console.error(`Could not start Bats with ${bash}: ${result.error.message}`);
    process.exit(2);
  }
  let status = result.status ?? 2;

  if (reportDir) {
    const report = join(reportDir, "report.tap");
    if (!existsSync(report)) {
      console.error("run-bats: CI is set but bats wrote no TAP report, so skips could not be audited.");
      if (status === 0) status = 2;
    } else {
      const bad = unexpectedSkips(readFileSync(report, "utf8"));
      if (bad.length > 0) {
        console.error(`run-bats: ${bad.length} unexpected skip(s) with CI set. A skip on CI is a test that asserted nothing:`);
        for (const s of bad) console.error(`  - ${s.test} # skip ${s.reason}`);
        console.error("run-bats: fix the prerequisite, or add the skip to ALLOWED_SKIPS in scripts/run-bats.mjs with a reason it is correct.");
        if (status === 0) status = 1;
      }
    }
    rmSync(reportDir, { recursive: true, force: true });
  }
  process.exit(status);
}

// Unconditionally: a "run only when executed directly" guard that misjudged a
// symlinked or differently-cased path would make `npm test` exit 0 having run
// nothing. The helpers are exercised end to end by tests/bats-hygiene.bats.
main();
