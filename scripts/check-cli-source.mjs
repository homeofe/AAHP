#!/usr/bin/env node
/**
 * check-cli-source.mjs - where does each workflow step get the aahp CLI it runs?
 *
 * `aahp doctor` runs this as the `cli-source` gate. The verify-workflow gate
 * (check-verify-workflow.mjs) asks whether a workflow can SKIP the AAHP gate; this
 * one asks whether the CLI a workflow runs is the package the repository pinned,
 * installed from its lockfile. Different question, different severity, different
 * remedy, so a different gate id: a dashboard must be able to tell them apart.
 *
 * WHY IT EXISTS. Adopters copied earlier versions of the shipped workflows and
 * edited them, and those copies do not update when the package does. Four legacy
 * shapes occur in adopter workflows, and each is a finding here:
 *
 *   id               severity  shape and consequence
 *   ---------------  --------  ----------------------------------------------------
 *   registry-fetch   fail      `npx -y @elvatis_com/aahp@<version> ...`, `npx` without
 *                              --no-install, `npm exec`, `pnpm dlx`, `yarn dlx`,
 *                              `bunx`, or `npm install <the package>`: the gate is
 *                              fetched from the registry at run time, with no
 *                              lockfile integrity check, at whatever version that
 *                              spec resolves to rather than the reviewed pin.
 *   unowned-name     fail      the same runners with the UNSCOPED name `aahp`, which
 *                              this project does not own: on any local miss they
 *                              download and execute whatever the registry returns
 *                              for it (docs/adr/ADR-013.md).
 *   unowned-name     advisory  `npx --no-install aahp ...`: the npx binary stops on a
 *                              local miss instead of executing (measured, ADR-013),
 *                              so this fails CLOSED. It still asks the registry about
 *                              an unowned name, and the same line spelled `npm exec`
 *                              executes the answer, so it is reported; it does not
 *                              fail doctor.
 *   checkout-path    fail      `node bin/aahp.js ...` in a repository that has no
 *                              bin/aahp.js: a path that exists only in an AAHP
 *                              checkout. The step exits MODULE_NOT_FOUND every run.
 *   no-install       fail      the CLI is run from node_modules (by path, or with
 *                              `npx --no-install`) but no earlier step in the same job
 *                              installs packages: on a fresh runner the step fails,
 *                              and from a restored cache it runs whatever the cache
 *                              holds instead of what the lockfile pins.
 *
 * THE SEVERITY RULE. A shape FAILS when it can execute code the lockfile did not
 * pin, or when it can never succeed. A shape that fails closed and only costs a
 * request is ADVISORY. That is a technical line, not a comfort one: the first class
 * is a supply-chain path into a required check, the second is broken on every run,
 * and neither is a deliberate configuration an adopter could want to keep.
 *
 * WHAT IS NOT FLAGGED, on purpose, because a false positive gets a gate switched
 * off:
 *   - this package itself (the doctor gate reports `self` before calling this);
 *   - `node bin/aahp.js` where bin/aahp.js EXISTS in the repository (a fork, or a
 *     vendored copy), or where the working directory is not the repository root
 *     (a `working-directory:` or a `cd` earlier in the step);
 *   - a missing install when an earlier step `uses:` an action other than
 *     actions/checkout, actions/setup-node or actions/setup-python: a composite or
 *     cache action may install or restore node_modules, and this reader cannot see
 *     inside it;
 *   - `npm run <script>` and other indirections whose expansion is not in the file.
 *
 * Usage: node scripts/check-cli-source.mjs [path-to-project] [--json] [--package NAME]
 * Exit:  0 no finding, only advisory findings, or no workflow invokes the CLI
 *        1 a failing finding
 *        2 a workflow that mentions aahp could not be parsed, or IO error
 *
 * The YAML is read by the zero-dependency reader in check-verify-workflow.mjs, and
 * tests/assert-workflow-parser-parity.mjs holds this audit's findings on every
 * fixture to the same answer under a real YAML parser.
 */
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseYamlSubset, stripComment } from "./check-verify-workflow.mjs";

export const DEFAULT_PACKAGE = "@elvatis_com/aahp";

// Actions known not to install packages or restore node_modules. Any other `uses:`
// before the CLI step makes "was anything installed?" undecidable.
const INERT_ACTIONS = /^actions\/(checkout|setup-node|setup-python)@/;

const NPM_INSTALL_CMDS = new Set([
  "ci", "clean-install", "ic", "install-clean", "isntall-clean",
  "install", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta", "isntal", "isntall", "add",
]);

function unquote(tok) {
  if (tok.length >= 2 && (tok[0] === '"' || tok[0] === "'") && tok[tok.length - 1] === tok[0]) return tok.slice(1, -1);
  return tok;
}

// Shell text to command segments, each a token array plus its source text. This is
// not a shell parser: it splits on the control operators and whitespace, which is
// what the invocations above need, and quoting only survives as token trimming.
export function segments(run) {
  const out = [];
  const text = String(run).replace(/\\\r?\n/g, " ");
  for (const rawLine of text.split(/\r?\n/)) {
    const line = stripComment(rawLine);
    for (const part of line.split(/&&|\|\||[;|()`]|\$\(/)) {
      const src = part.trim();
      if (src === "") continue;
      const tokens = src.split(/\s+/).map(unquote).filter((t) => t !== "");
      // Leading VAR=value assignments and transparent prefixes do not change the
      // command that runs.
      while (tokens.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[0]) || ["env", "exec", "time", "command", "sudo"].includes(tokens[0]))) {
        tokens.shift();
      }
      if (tokens.length) out.push({ tokens, src });
    }
  }
  return out;
}

function aahpTarget(tok, pkgName) {
  if (typeof tok !== "string") return null;
  if (tok === pkgName || tok.startsWith(pkgName + "@")) return "scoped";
  if (tok === "aahp" || tok.startsWith("aahp@")) return "unscoped";
  return null;
}

// npx / npm exec argument parsing: the flags that decide whether a miss fetches,
// the --package values, and the first positional (the command or package spec).
function parseRunnerArgs(args) {
  let noInstall = false;
  let yes = false;
  const packages = [];
  let command = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--") { command = args[i + 1] || null; break; }
    if (a === "--no-install" || a === "--yes=false" || a === "--no-yes") { noInstall = true; continue; }
    if (a === "-y" || a === "--yes" || a === "--yes=true") { yes = true; continue; }
    if (a === "-p" || a === "--package") { if (args[i + 1]) packages.push(args[++i]); continue; }
    if (a.startsWith("--package=")) { packages.push(a.slice("--package=".length)); continue; }
    if (a === "-c" || a === "--call") { i++; continue; }
    if (a.startsWith("-")) continue;
    command = a;
    break;
  }
  return { noInstall, yes, packages, command };
}

/**
 * Classify one command segment. Returns null, { kind: "install" }, { kind: "cd" },
 * or { kind: "cli", form, target, fetches, needsInstall } for an aahp invocation.
 *   form: "runner" | "checkout-path" | "local-path" | "registry-install"
 */
export function classify(tokens, pkgName = DEFAULT_PACKAGE) {
  const [t0, t1] = tokens;
  if (t0 === "cd" || t0 === "pushd") return { kind: "cd" };

  if (t0 === "npm" && NPM_INSTALL_CMDS.has(t1)) {
    const rest = tokens.slice(2);
    if (rest.some((t) => t === "-g" || t === "--global" || t === "--location=global")) return null;
    const named = rest.filter((t) => !t.startsWith("-")).map((t) => aahpTarget(t, pkgName)).find(Boolean);
    if (named) return { kind: "cli", form: "registry-install", target: named, fetches: true, needsInstall: false };
    return { kind: "install" };
  }
  if ((t0 === "pnpm" || t0 === "bun") && ["install", "i", "add"].includes(t1)) return { kind: "install" };
  if (t0 === "yarn" && (t1 === undefined || t1 === "install" || t1 === "add" || (t1 && t1.startsWith("--")))) {
    return { kind: "install" };
  }

  // Runners that fetch on a miss whatever flags they are given.
  let fetchRunnerArgs = null;
  if (t0 === "npm" && (t1 === "exec" || t1 === "x")) fetchRunnerArgs = tokens.slice(2);
  else if ((t0 === "pnpm" || t0 === "yarn") && t1 === "dlx") fetchRunnerArgs = tokens.slice(2);
  else if (t0 === "bunx" || (t0 === "bun" && t1 === "x")) fetchRunnerArgs = tokens.slice(t0 === "bunx" ? 1 : 2);
  if (fetchRunnerArgs) {
    const p = parseRunnerArgs(fetchRunnerArgs);
    const target = [...p.packages, p.command].map((t) => aahpTarget(t, pkgName)).find(Boolean);
    return target ? { kind: "cli", form: "runner", target, fetches: true, needsInstall: false } : null;
  }

  if (t0 === "npx") {
    const p = parseRunnerArgs(tokens.slice(1));
    const target = [...p.packages, p.command].map((t) => aahpTarget(t, pkgName)).find(Boolean);
    if (!target) return null;
    // Measured in ADR-013: without --no-install a miss downloads and runs the
    // package; with it, the npx binary cancels. An explicit --yes overrides.
    const fetches = p.yes || !p.noInstall;
    return { kind: "cli", form: "runner", target, fetches, needsInstall: !fetches };
  }

  if (t0 === "node" || t0 === "node.exe") {
    const script = tokens.slice(1).find((t) => !t.startsWith("-"));
    if (!script) return null;
    if (/^(\.\/)?bin\/aahp\.js$/.test(script)) {
      return { kind: "cli", form: "checkout-path", target: "path", fetches: false, needsInstall: false };
    }
    const esc = pkgName.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
    if (new RegExp(`(^|/)node_modules/${esc}/bin/aahp\\.js$`).test(script)) {
      return { kind: "cli", form: "local-path", target: "path", fetches: false, needsInstall: true };
    }
    return null;
  }
  if (/(^|\/)node_modules\/\.bin\/aahp$/.test(t0)) {
    return { kind: "cli", form: "local-path", target: "path", fetches: false, needsInstall: true };
  }
  return null;
}

function hasWorkingDirectory(scope) {
  const d = scope && typeof scope === "object" ? scope.defaults : null;
  const run = d && typeof d === "object" ? d.run : null;
  return !!(run && typeof run === "object" && run["working-directory"] !== undefined && run["working-directory"] !== null);
}

function short(src) {
  return src.length > 100 ? `${src.slice(0, 97)}...` : src;
}

/**
 * Audit one parsed workflow document.
 * ctx: { pkgName, checkoutCli } where checkoutCli says bin/aahp.js exists in the
 * repository. Returns { invocations, findings }.
 */
export function auditCliDoc(doc, file, ctx = {}) {
  const pkgName = ctx.pkgName || DEFAULT_PACKAGE;
  const findings = [];
  let invocations = 0;
  const jobs = doc && typeof doc === "object" && doc.jobs && typeof doc.jobs === "object" ? doc.jobs : null;
  if (!jobs) return { invocations, findings };
  const docWd = hasWorkingDirectory(doc);

  for (const [jobId, job] of Object.entries(jobs)) {
    if (!job || typeof job !== "object" || !Array.isArray(job.steps)) continue;
    const jobWd = docWd || hasWorkingDirectory(job);
    let installed = false;
    let undecidable = false;
    job.steps.forEach((step, index) => {
      if (!step || typeof step !== "object") return;
      if (typeof step.uses === "string" && !INERT_ACTIONS.test(step.uses.trim())) undecidable = true;
      if (typeof step.run !== "string") return;
      const name = typeof step.name === "string" && step.name ? step.name : `step ${index + 1}`;
      const at = `${file}: job "${jobId}", step "${name}"`;
      let cwdKnown = !jobWd && (step["working-directory"] === undefined || step["working-directory"] === null);
      for (const seg of segments(step.run)) {
        const c = classify(seg.tokens, pkgName);
        if (!c) continue;
        if (c.kind === "cd") { cwdKnown = false; continue; }
        if (c.kind === "install") { installed = true; continue; }
        invocations++;
        const cmd = short(seg.src);
        const add = (id, severity, detail) => findings.push({ id, severity, file, job: jobId, step: name, command: cmd, detail });
        if (c.form === "checkout-path") {
          if (!ctx.checkoutCli && cwdKnown) {
            add("checkout-path", "fail",
              `${at} runs \`${cmd}\`: bin/aahp.js exists only in an AAHP checkout and not in this repository, ` +
                "so the step exits with MODULE_NOT_FOUND on every run.");
          }
          continue;
        }
        if (c.target === "unscoped") {
          if (c.fetches) {
            add("unowned-name", "fail",
              `${at} runs \`${cmd}\`, which resolves the UNSCOPED name aahp. This project does not own that name, ` +
                "and on any local miss this command downloads and executes whatever the registry returns for it " +
                "(docs/adr/ADR-013.md in the AAHP repository).");
          } else {
            add("unowned-name", "advisory",
              `${at} runs \`${cmd}\`, which names the UNSCOPED aahp. With --no-install the npx binary stops on a ` +
                "local miss instead of executing (ADR-013), so this fails closed; it still asks the registry about " +
                "a name this project does not own, and the same line spelled npm exec executes the answer.");
          }
        } else if (c.fetches) {
          add("registry-fetch", "fail",
            `${at} runs \`${cmd}\`, which fetches ${pkgName} from the registry at run time: nothing checks it ` +
              "against the lockfile, and the version that runs is whatever that spec resolves to, not the " +
              "devDependency pin this repository reviewed.");
        }
        if (c.needsInstall && !installed && !undecidable) {
          add("no-install", "fail",
            `${at} runs \`${cmd}\` from node_modules, but no earlier step in job "${jobId}" installs packages ` +
              "(npm ci): on a fresh runner node_modules is empty and the step fails, and restored from a cache it " +
              "runs whatever the cache holds instead of what the lockfile pins.");
        }
      }
    });
  }
  return { invocations, findings };
}

export function auditCliSource(root, opts = {}) {
  const pkgName = opts.pkgName || DEFAULT_PACKAGE;
  const ctx = { pkgName, checkoutCli: existsSync(join(root, "bin", "aahp.js")) };
  const result = { invocations: 0, findings: [], unassessed: [] };
  const dir = join(root, ".github", "workflows");
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return result;
  }
  for (const entry of entries.sort()) {
    if (!/\.ya?ml$/i.test(entry)) continue;
    const file = `.github/workflows/${entry}`;
    let text;
    try {
      text = readFileSync(join(dir, entry), "utf8");
    } catch (err) {
      result.unassessed.push(`${file}: cannot read (${err.message})`);
      continue;
    }
    let doc;
    try {
      doc = parseYamlSubset(text);
    } catch (err) {
      // Only a file that could run the CLI matters. Undecided is not clean there.
      if (/aahp/.test(text)) result.unassessed.push(`${file}: cannot be parsed (${err.message})`);
      continue;
    }
    const r = auditCliDoc(doc, file, ctx);
    result.invocations += r.invocations;
    result.findings.push(...r.findings);
  }
  return result;
}

export function main(argv = process.argv.slice(2)) {
  const json = argv.includes("--json");
  const pi = argv.indexOf("--package");
  const pkgName = pi >= 0 && argv[pi + 1] ? argv[pi + 1] : DEFAULT_PACKAGE;
  const positional = argv.filter((a, i) => !a.startsWith("--") && !(pi >= 0 && i === pi + 1));
  const root = resolve(positional[0] || ".");
  if (!existsSync(root)) {
    console.error(`check-cli-source: no such path: ${root}`);
    return 2;
  }
  const r = auditCliSource(root, { pkgName });
  const failing = r.findings.filter((f) => f.severity === "fail");
  const code = r.unassessed.length ? 2 : failing.length ? 1 : 0;
  if (json) {
    process.stdout.write(JSON.stringify(r, null, 2) + "\n");
    return code;
  }
  for (const u of r.unassessed) console.error(`check-cli-source: UNDECIDED - ${u}`);
  for (const f of r.findings) console.log(`  ${f.severity === "fail" ? "FAIL" : "ADVISORY"} [${f.id}] ${f.detail}`);
  if (code === 0 && r.invocations === 0) console.log("check-cli-source: SKIP - no workflow here invokes the aahp CLI.");
  else if (code === 0 && r.findings.length > 0) {
    // Advisory findings only. Not an OK line: the findings above are real, they
    // just fail closed, and a summary that said OK under them would contradict them.
    console.log(
      `check-cli-source: ADVISORY - ${r.findings.length} advisory finding(s) in ${r.invocations} invocation(s), ` +
        "none failing. Fix: aahp init --gates --workflows, or edit the step.",
    );
  } else if (code === 0) console.log(`check-cli-source: OK - ${r.invocations} invocation(s), none of a legacy shape.`);
  return code;
}

const isMain = process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
if (isMain) process.exit(main());
