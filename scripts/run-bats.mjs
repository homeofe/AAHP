#!/usr/bin/env node
// run-bats.mjs - Launch the locked bats dependency with the correct bash and
// path spelling on Linux, macOS, and Windows.

import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveBash, toBashPath } from "./aahp-config.mjs";

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
const args = [toBashPath(bats, process.platform, root), ...batsArgs];
const result = spawnSync(bash, args, { cwd: root, stdio: "inherit" });

if (result.error) {
  console.error(`Could not start Bats with ${bash}: ${result.error.message}`);
  process.exit(2);
}
process.exit(result.status ?? 2);
