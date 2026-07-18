#!/usr/bin/env node
// check-claims.mjs - Config-driven capability-claim gate (the ENGINE; the claims
// themselves are repo-supplied). Pins each hand-authored capability number to
// ONE canonical value across every live surface, and optionally honesty-checks
// the advertised floor against a ground-truth count so a release cannot boast a
// bigger number than reality.
//
// This is the capability-number analogue of check-version-sync.mjs. It is the
// most repo-specific gate, so nothing is hardcoded: claims live in
// aahp.config.json under "claims". A repo with none configured is a clean no-op.
//
//   "claims": [
//     {
//       "id": "rule count",
//       "canonical": "350+",           // token shown to humans
//       "advertised": 350,             // the number every surface must carry
//       "phrase": "(\\d+)\\+\\s*rules\\b",  // regex source; capture group 1 = number
//       "flags": "gi",                 // optional (default "gi")
//       "floorCmd": "node scripts/count-rules.mjs",  // optional: stdout -> integer floor
//       "joinTsConcat": true,          // optional: join "a" + "b" JS literal splits
//       "surfaces": [ { "file": "README.md", "note": "intro" } ]
//     }
//   ]
//
// floorCmd runs in the project root (same trust boundary as an npm script). If
// omitted, the claim is editorial and the honesty check is skipped.

import { readFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";
import { resolveRoot, loadConfig } from "./aahp-config.mjs";

const root = resolveRoot();

let config;
try {
  config = loadConfig(root);
} catch (err) {
  console.error(`  claims: ${err.message}`);
  process.exit(1);
}

const claims = Array.isArray(config.claims) ? config.claims : [];
if (claims.length === 0) {
  console.log("Capability claims: none configured; nothing to check.");
  process.exit(0);
}

const read = (rel) => readFileSync(join(root, rel), "utf8");
const failures = [];

for (const claim of claims) {
  const { id, canonical, advertised, phrase, flags, floorCmd, joinTsConcat, surfaces = [] } = claim;

  // Honesty check: the advertised floor must not exceed ground truth.
  if (floorCmd) {
    let floor = null;
    try {
      const out = execSync(floorCmd, { cwd: root, encoding: "utf8" });
      const m = out.match(/-?\d+/);
      floor = m ? Number(m[0]) : null;
    } catch (err) {
      failures.push({ id, msg: `floorCmd failed (${floorCmd}): ${err.message.split("\n")[0]}` });
    }
    if (floor !== null && advertised > floor) {
      failures.push({
        id,
        msg: `advertised "${canonical}" exceeds ground truth (${floor} from floorCmd). Lower the canonical value or the count regressed.`,
      });
    }
  }

  let re;
  try {
    re = new RegExp(phrase, flags || "gi");
  } catch (err) {
    failures.push({ id, msg: `invalid phrase regex ${JSON.stringify(phrase)}: ${err.message}` });
    continue;
  }

  for (const { file, note } of surfaces) {
    let contents;
    try {
      contents = read(file);
    } catch (err) {
      failures.push({ id, file, msg: err.code === "ENOENT" ? `surface not found (${note || file})` : err.message });
      continue;
    }
    // Join adjacent JS string-literal concatenations ("...a " + "b...") so a
    // phrase split across two literals is still matched.
    if (joinTsConcat) contents = contents.replace(/"\s*\+\s*\n?\s*"/g, "");

    re.lastIndex = 0;
    const nums = [...contents.matchAll(re)].map((m) => Number(m[1]));
    if (nums.length === 0) {
      failures.push({ id, file, msg: `expected the ${id} claim "${canonical}"${note ? ` (${note})` : ""} - found no matching phrase` });
      continue;
    }
    const wrong = [...new Set(nums.filter((n) => n !== advertised))];
    if (wrong.length > 0) {
      failures.push({ id, file, msg: `${id} on this surface says ${wrong.map((n) => `"${n}"`).join(", ")}${note ? ` (${note})` : ""}; canonical is "${canonical}"` });
    }
  }
}

if (failures.length > 0) {
  console.error(
    `\n  Capability-claim check failed.\n` +
      `  Every capability number must match ONE canonical value across all live\n` +
      `  surfaces. A copy left behind ships a project that boasts a different\n` +
      `  number in different places.\n`,
  );
  for (const f of failures) {
    if (f.file) console.error(`  - ${f.file}: ${f.msg}`);
    else console.error(`  - [${f.id}]: ${f.msg}`);
  }
  console.error("");
  process.exit(1);
}

console.log(`Capability claims OK: ${claims.length} claim(s) agree across all surfaces.`);
