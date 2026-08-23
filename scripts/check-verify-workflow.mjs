#!/usr/bin/env node
/**
 * check-verify-workflow.mjs - can the workflow that runs the AAHP gate skip it?
 *
 * The required status check named after the AAHP verify job is the off-machine
 * backstop for the whole protocol. A consumer that wraps that job (or the step
 * inside it) in an `if:` keeps the check NAME, keeps it required, and keeps it
 * green - while the job evaluates nothing at all. Branch protection is then
 * satisfied by a check that never ran, and Layer 1 MANIFEST checksum integrity
 * is skipped along with the Layer 2 drift gate.
 *
 * That defect is invisible from inside AAHP: the canonical workflow AAHP ships
 * is unconditional, and propagate.sh copies it verbatim. It only exists in a
 * consumer's copy, and only a check that runs INSIDE the consumer can see it.
 * This gate is that check. `aahp doctor` runs it, so every consumer that runs
 * doctor reports whether the workflow hosting the gate can skip the gate.
 *
 * WHAT IS ASSERTED IS THE CONSEQUENCE, not the file's shape: "there exists an
 * event on which this workflow concludes SUCCESS without having executed the
 * AAHP verify gate at --level ci". Each finding below names one way to reach
 * that state.
 *
 * Deliberately NOT flagged, because they fail CLOSED (a blocked pull request,
 * never a false green): an `if:` on the checkout step alone (the gate then runs
 * against an empty workspace and exits non-zero), and `paths:` filters that stop
 * the workflow from triggering (a required check that never reports leaves the
 * pull request pending).
 *
 * BOTH SHIPPED WORKFLOWS ARE IN SCOPE. `aahp-verify.yml` gates handoff state and
 * `aahp-govern.yml` gates governance (ADR-016). The audit originally covered only
 * the first, so a governance-only adopter - exactly the audience `aahp init
 * --gates` and the "Portable Governance" positioning target, and an adopter with
 * no `aahp-verify.yml` at all - could wrap their one CI backstop in `if: false`
 * and still read `SKIP: no workflow here runs the AAHP verify gate`, exit 0. The
 * verdicts stay separate (see `governance-only` below), because the two files
 * answer different questions and one is not evidence for the other.
 *
 * Usage: node scripts/check-verify-workflow.mjs [path-to-project] [--json]
 * Exit:  0 enforced, governance-only, or not adopted here
 *        1 the gate can be skipped (findings printed)
 *        2 a workflow hosts the gate but its shape cannot be classified, or IO
 *          error. Never silently 0: unclassifiable is not clean.
 *
 * No runtime dependencies (AAHP ships none), so the YAML needed here is parsed
 * by the small block-subset reader below. tests/verify-workflow.bats cross-checks
 * that reader against the real `yaml` package on every workflow in this repo and
 * on every fixture, so a divergence fails the suite rather than this gate.
 */
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve, basename } from "node:path";
import { pathToFileURL } from "node:url";

// ---------------------------------------------------------------------------
// Minimal block-YAML reader
//
// Covers the subset GitHub workflow files actually use: block mappings, block
// sequences, plain/quoted scalars, block scalars (| and >), flow collections,
// and comments. Anything it cannot read raises, and the caller turns that into
// exit 2 rather than a pass.
// ---------------------------------------------------------------------------

export class YamlSubsetError extends Error {}

function toLines(text) {
  return text
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((raw, n) => {
      const m = /^([ \t]*)(.*)$/.exec(raw);
      return { n: n + 1, indent: m[1].replace(/\t/g, "  ").length, body: m[2] };
    });
}

/** Strip a trailing `# comment`, honouring quotes so a `#` inside a string survives. */
export function stripComment(s) {
  let out = "";
  let quote = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quote) {
      out += c;
      if (c === quote) {
        if (quote === "'" && s[i + 1] === "'") {
          out += s[++i];
          continue;
        }
        if (quote === '"' && s[i - 1] === "\\") continue;
        quote = null;
      }
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      out += c;
      continue;
    }
    if (c === "#" && (i === 0 || /\s/.test(s[i - 1]))) break;
    out += c;
  }
  return out;
}

function readQuoted(s, start) {
  const q = s[start];
  let out = "";
  for (let i = start + 1; i < s.length; i++) {
    const c = s[i];
    if (q === "'" ) {
      if (c === "'") {
        if (s[i + 1] === "'") { out += "'"; i++; continue; }
        return [out, i + 1];
      }
      out += c;
      continue;
    }
    if (c === "\\") {
      const nxt = s[++i];
      out += nxt === "n" ? "\n" : nxt === "t" ? "\t" : nxt;
      continue;
    }
    if (c === '"') return [out, i + 1];
    out += c;
  }
  throw new YamlSubsetError(`unterminated quoted scalar: ${s}`);
}

/** Split `key: rest` at the first structural colon. Returns null when there is none. */
export function splitKey(body) {
  if (body[0] === '"' || body[0] === "'") {
    const [key, idx] = readQuoted(body, 0);
    const tail = body.slice(idx);
    if (!tail.startsWith(":")) return null;
    return { key, rest: tail.slice(1).trim() };
  }
  for (let i = 0; i < body.length; i++) {
    if (body[i] === ":" && (i + 1 === body.length || /\s/.test(body[i + 1]))) {
      return { key: body.slice(0, i).trim(), rest: body.slice(i + 1).trim() };
    }
  }
  return null;
}

function parseScalar(raw) {
  const s = raw.trim();
  if (s === "") return null;
  if (s[0] === '"' || s[0] === "'") return readQuoted(s, 0)[0];
  if (s === "null" || s === "~") return null;
  if (s === "true") return true;
  if (s === "false") return false;
  if (/^-?\d+$/.test(s)) return Number(s);
  return s;
}

function splitFlow(inner) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let cur = "";
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (quote) {
      cur += c;
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; cur += c; continue; }
    if (c === "[" || c === "{") depth++;
    if (c === "]" || c === "}") depth--;
    if (c === "," && depth === 0) { parts.push(cur); cur = ""; continue; }
    cur += c;
  }
  if (cur.trim() !== "") parts.push(cur);
  return parts;
}

function parseFlow(s) {
  const t = s.trim();
  if (t.startsWith("[")) {
    if (!t.endsWith("]")) throw new YamlSubsetError(`unterminated flow sequence: ${s}`);
    return splitFlow(t.slice(1, -1)).map((p) => parseFlowItem(p));
  }
  if (!t.endsWith("}")) throw new YamlSubsetError(`unterminated flow mapping: ${s}`);
  const out = {};
  for (const p of splitFlow(t.slice(1, -1))) {
    const kv = splitKey(p.trim());
    if (!kv) throw new YamlSubsetError(`flow mapping entry without a key: ${p}`);
    out[kv.key] = parseFlowItem(kv.rest);
  }
  return out;
}

function parseFlowItem(p) {
  const t = p.trim();
  if (t.startsWith("[") || t.startsWith("{")) return parseFlow(t);
  return parseScalar(t);
}

function skipIgnorable(lines, cur) {
  while (cur.i < lines.length) {
    const t = lines[cur.i].body.trim();
    if (t === "" || t.startsWith("#") || t === "---" || t === "...") { cur.i++; continue; }
    break;
  }
}

function parseBlockScalar(lines, cur, parentIndent, header) {
  const style = header[0];
  const chomp = /-/.test(header) ? "strip" : /\+/.test(header) ? "keep" : "clip";
  const collected = [];
  let contentIndent = null;
  while (cur.i < lines.length) {
    const ln = lines[cur.i];
    if (ln.body.trim() === "") { collected.push(""); cur.i++; continue; }
    if (ln.indent <= parentIndent) break;
    if (contentIndent === null) contentIndent = ln.indent;
    // Keep indentation RELATIVE to the block's own first line, so nesting inside
    // the scalar survives while the block's base indent is removed.
    collected.push(" ".repeat(Math.max(0, ln.indent - contentIndent)) + ln.body);
    cur.i++;
  }
  while (collected.length && collected[collected.length - 1] === "") collected.pop();
  let text;
  if (style === "|") {
    text = collected.join("\n");
  } else {
    // Folded (`>`) is NOT "join every line with a space". A line indented deeper
    // than the block's first content line is "more indented": YAML keeps its
    // line break and its extra indentation instead of folding it. A wrapped
    // `if:` written as a folded scalar is exactly that shape, and folding it
    // anyway produced text no reference parser agrees with.
    let out = "";
    let started = false;
    let prevMore = false;
    let blanks = 0;
    for (const line of collected) {
      if (line === "") { blanks++; continue; }
      const more = /^\s/.test(line);
      if (!started) {
        out = line;
        started = true;
      } else if (blanks > 0) {
        out += "\n".repeat(blanks) + line;
      } else {
        out += (more || prevMore ? "\n" : " ") + line;
      }
      prevMore = more;
      blanks = 0;
    }
    text = out;
  }
  if (chomp === "clip" && text !== "") text += "\n";
  if (chomp === "keep") text += "\n";
  return text;
}

// A plain scalar may continue on the following, MORE indented lines; YAML folds
// them with a single space. A long `if:` is written this way in real workflows,
// so reading only the first line would compare the wrong text (or, worse, treat
// the continuation as an unexpected indent and give up on the whole file).
// Once a value starts on the key's own line, every more-indented line belongs
// to it: a nested block cannot follow a key that already has a value.
function foldPlainContinuation(lines, cur, indent, first) {
  let text = first;
  while (cur.i < lines.length) {
    const ln = lines[cur.i];
    if (ln.body.trim() === "") {
      // Peek: a blank line only continues the scalar if more indented text follows.
      let j = cur.i;
      while (j < lines.length && lines[j].body.trim() === "") j++;
      if (j >= lines.length || lines[j].indent <= indent) break;
      text += "\n";
      cur.i = j;
      continue;
    }
    if (ln.indent <= indent) break;
    text += (text.endsWith("\n") ? "" : " ") + stripComment(ln.body).trim();
    cur.i++;
  }
  return text;
}

function parseValueAfterKey(lines, cur, indent, rest) {
  const trimmed = stripComment(rest).trim();
  if (trimmed !== "") {
    if (/^[|>][-+]?$/.test(trimmed) || /^[|>][-+]?\d+$/.test(trimmed)) {
      return parseBlockScalar(lines, cur, indent, trimmed);
    }
    if (trimmed.startsWith("[") || trimmed.startsWith("{")) return parseFlow(trimmed);
    if (trimmed[0] === '"' || trimmed[0] === "'") return parseScalar(trimmed);
    return parseScalar(foldPlainContinuation(lines, cur, indent, trimmed));
  }
  skipIgnorable(lines, cur);
  if (cur.i >= lines.length) return null;
  const nxt = lines[cur.i];
  if (nxt.indent > indent) return parseBlock(lines, cur, nxt.indent);
  if (nxt.indent === indent && /^-(\s|$)/.test(nxt.body)) return parseSeq(lines, cur, indent);
  return null;
}

function parseMap(lines, cur, indent) {
  const out = {};
  for (;;) {
    skipIgnorable(lines, cur);
    if (cur.i >= lines.length) break;
    const ln = lines[cur.i];
    if (ln.indent < indent) break;
    if (/^-(\s|$)/.test(ln.body)) break;
    if (ln.indent > indent) {
      throw new YamlSubsetError(`unexpected indentation on line ${ln.n}: ${ln.body}`);
    }
    const kv = splitKey(ln.body);
    if (!kv) throw new YamlSubsetError(`line ${ln.n} is not a mapping entry: ${ln.body}`);
    cur.i++;
    out[kv.key] = parseValueAfterKey(lines, cur, indent, kv.rest);
  }
  return out;
}

function parseSeq(lines, cur, indent) {
  const out = [];
  for (;;) {
    skipIgnorable(lines, cur);
    if (cur.i >= lines.length) break;
    const ln = lines[cur.i];
    if (ln.indent !== indent || !/^-(\s|$)/.test(ln.body)) break;
    const after = ln.body.slice(1);
    const lead = after.length - after.replace(/^\s+/, "").length;
    const content = after.trim();
    if (content === "" || content.startsWith("#")) {
      cur.i++;
      out.push(parseBlock(lines, cur, indent + 1));
      continue;
    }
    const contentIndent = indent + 1 + lead;
    lines[cur.i] = { n: ln.n, indent: contentIndent, body: content };
    if (/^-(\s|$)/.test(content)) {
      out.push(parseSeq(lines, cur, contentIndent));
    } else if (splitKey(content)) {
      out.push(parseMap(lines, cur, contentIndent));
    } else {
      out.push(parseScalar(stripComment(content)));
      cur.i++;
    }
  }
  return out;
}

function parseBlock(lines, cur, indent) {
  skipIgnorable(lines, cur);
  if (cur.i >= lines.length) return null;
  const ln = lines[cur.i];
  if (ln.indent < indent) return null;
  if (/^-(\s|$)/.test(ln.body)) return parseSeq(lines, cur, ln.indent);
  return parseMap(lines, cur, ln.indent);
}

/** Parse the block-YAML subset GitHub workflow files use. Throws YamlSubsetError. */
export function parseYamlSubset(text) {
  const lines = toLines(text);
  const cur = { i: 0 };
  const value = parseBlock(lines, cur, 0);
  skipIgnorable(lines, cur);
  if (cur.i < lines.length) {
    throw new YamlSubsetError(`trailing content at line ${lines[cur.i].n}: ${lines[cur.i].body}`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// The audit
// ---------------------------------------------------------------------------

// A step runs the AAHP gate when its `run:` invokes the vendored script or the
// CLI. Anchored on the INVOCATION, not on a file name or a job id, so renaming
// the workflow cannot hide the job from this gate.
//
// The CLI form must tolerate a package SPEC, not just the bare binary name: a
// consumer that runs `npx -y @scope/aahp@3.10.0 verify . --level ci` is running
// the gate, and an earlier draft of this pattern missed exactly that shape in
// two live consumers. `aahp-verify` (the job id) cannot match, because what
// follows `aahp` must be whitespace or an `@version`.
const RUNS_VERIFY = [
  /verify-handoff\.sh/,
  /(^|[\s"'/@])aahp(@[^\s"']*)?\s+verify(\s|$)/,
  /aahp\.js\s+verify(\s|$)/,
];
const CI_LEVEL = /--level[\s=]+ci\b/;

// The GOVERNANCE gate: the other workflow this package ships, and the only CI
// backstop a governance-only adopter has.
//
// `aahp init --gates` writes assets/governance/aahp-govern.yml into an adopting
// repository. That file runs `aahp check` and `aahp doctor --governance`, and an
// adopter who never keeps .ai/handoff/ has no aahp-verify.yml at all. Until this
// list existed, wrapping its `Run governance gates` step in `if: false` left
// `aahp doctor` reporting `SKIP verify-workflow: no workflow here runs the AAHP
// verify gate` and exiting 0 - the same false green this gate exists to stop,
// one file over, in the file with the wider blast radius.
//
// `doctor` counts for the same reason `check` does: it is not a report, it exits
// non-zero when a conformance gate fails. Skipping it removes a verdict.
//
// The `aahp.js` path form is load-bearing, not a nicety. The shipped template
// invokes `node ./node_modules/@elvatis_com/aahp/bin/aahp.js check .`, so a
// pattern that only knew the bare binary name would miss the exact file this was
// added for. `npm run govern` is deliberately NOT matched: what that script
// expands to is not readable from the workflow, and a guess is a finding this
// reader cannot support.
const RUNS_GOVERN = [
  /(^|[\s"'/@])aahp(@[^\s"']*)?\s+(check|doctor)(\s|$)/,
  /aahp\.js\s+(check|doctor)(\s|$)/,
];

export function runsVerify(run) {
  return typeof run === "string" && RUNS_VERIFY.some((re) => re.test(run));
}

export function runsGovern(run) {
  return governSubcommands(run).length > 0;
}

// Which governance SUBCOMMANDS a `run:` invokes, as a sorted list.
//
// The split matters and the first draft of this file got it wrong. `aahp check`
// and `aahp doctor` are different gates, not two spellings of one, so "some step
// in this job runs unconditionally" is the wrong test: the shipped
// aahp-govern.yml runs both, and wrapping ONLY `Run governance gates` in
// `if: false` leaves the doctor step unconditional. Under a per-job test that
// tamper reads as enforced, which is the finding this gate was extended to
// catch, surviving inside the fix for it. Each subcommand is therefore required
// to have an unconditional instance of its own.
export function governSubcommands(run) {
  if (typeof run !== "string") return [];
  const found = new Set();
  for (const re of RUNS_GOVERN) {
    const g = new RegExp(re.source, "g");
    let m;
    while ((m = g.exec(run)) !== null) {
      // Read the subcommand out of whichever capture group holds it rather than
      // by index: the two patterns have different group counts, and indexing by
      // position picked up the trailing-whitespace group in an earlier draft.
      for (const group of m.slice(1)) {
        if (group === "check" || group === "doctor") found.add(group);
      }
      if (g.lastIndex === m.index) g.lastIndex++;
    }
  }
  return [...found].sort();
}

export function isCiLevel(run) {
  return typeof run === "string" && CI_LEVEL.test(run);
}

// `continue-on-error` is a bypass unless it is literally false. An expression
// (`${{ ... }}`) can evaluate true, and this gate cannot evaluate it, so it
// counts as reachable.
function softFailing(value) {
  if (value === undefined || value === null || value === false) return false;
  if (typeof value === "string" && value.trim().toLowerCase() === "false") return false;
  return true;
}

function describeStep(step, index) {
  const name = typeof step.name === "string" && step.name ? step.name : `step ${index + 1}`;
  return name;
}

/**
 * Audit one parsed workflow document.
 * Returns { hosts, governHosts, findings }: `hosts` are jobs that run the verify
 * gate, `governHosts` are jobs that run the governance gate.
 */
export function auditDoc(doc, file) {
  const findings = [];
  const hosts = [];
  const governHosts = [];
  const jobs = doc && typeof doc === "object" && doc.jobs && typeof doc.jobs === "object" ? doc.jobs : null;
  if (!jobs) return { hosts, governHosts, findings };

  for (const [jobId, job] of Object.entries(jobs)) {
    if (!job || typeof job !== "object") continue;
    const steps = Array.isArray(job.steps) ? job.steps.filter((s) => s && typeof s === "object") : [];
    const verifySteps = steps
      .map((s, i) => ({ step: s, i }))
      .filter(({ step }) => runsVerify(step.run));
    const governSteps = steps
      .map((s, i) => ({ step: s, i }))
      .filter(({ step }) => runsGovern(step.run));
    if (verifySteps.length === 0) {
      if (governSteps.length > 0) auditGovernJob(findings, governHosts, file, jobId, job, governSteps);
      continue;
    }
    hosts.push({ file, job: jobId });
    const at = `${file}: job "${jobId}"`;

    if (job.if !== undefined && job.if !== null) {
      findings.push({
        id: "job-conditional",
        detail:
          `${at} carries a job-level \`if:\` (${String(job.if).trim()}). ` +
          "When it evaluates false the job is skipped, the required check reports " +
          "success or is treated as satisfied, and no layer of the gate ran.",
      });
    }
    if (softFailing(job["continue-on-error"])) {
      findings.push({
        id: "job-soft-failing",
        detail: `${at} sets continue-on-error, so the job reports success even when the gate fails.`,
      });
    }

    const ciSteps = verifySteps.filter(({ step }) => isCiLevel(step.run));
    if (ciSteps.length === 0) {
      findings.push({
        id: "no-ci-level",
        detail:
          `${at} runs the gate but never at \`--level ci\`. Every other level honours ` +
          "AAHP_SKIP_VERIFY=1, so the off-machine backstop has an environment-variable bypass.",
      });
      continue;
    }

    const unconditional = ciSteps.filter(({ step }) => step.if === undefined || step.if === null);
    if (unconditional.length === 0) {
      const conds = ciSteps
        .map(({ step, i }) => `"${describeStep(step, i)}" if: ${String(step.if).trim()}`)
        .join("; ");
      findings.push({
        id: "ci-step-conditional",
        detail:
          `${at} runs the gate at --level ci only under a condition (${conds}). ` +
          "On the events where that condition is false the job still reports success, " +
          "having verified nothing: Layer 1 MANIFEST checksum integrity is skipped too, " +
          "not only the Layer 2 drift gate. Put the exemption INSIDE the gate, keyed on " +
          "the change, not around the step, keyed on who pushed it.",
      });
      continue;
    }

    const hard = unconditional.filter(({ step }) => !softFailing(step["continue-on-error"]));
    if (hard.length === 0) {
      findings.push({
        id: "ci-step-soft-failing",
        detail:
          `${at} runs the gate at --level ci unconditionally, but every such step sets ` +
          "continue-on-error, so a failing gate still leaves the check green.",
      });
    }
  }

  return { hosts, governHosts, findings };
}

// Audit a job whose only AAHP invocation is the governance gate.
//
// SCOPE, and why it is narrower than it looks. This runs only for jobs that host
// NO verify step. Where `aahp verify` and `aahp doctor` sit in the same job -
// the shape of every consumer measured on 2026-08-23, 8 of 9 of which run
// `aahp doctor . --json` immediately after the verify step - that job's
// skippability is already decided above, and a second verdict over the same
// `if:` would double-report one condition. The uncovered case is therefore
// narrow and named rather than hidden: a job whose verify step is unconditional
// while its doctor step alone carries an `if:`. There the gate still runs all
// four layers and only the conformance record is lost, which is a smaller
// finding than this gate is built to make, and flagging the common and
// legitimate `if: github.event_name == 'pull_request'` on a record-emitting step
// would be a false positive. A false positive here gets the gate switched off.
//
// There is no --level to test: neither `aahp check` nor `aahp doctor` takes one,
// so the `no-ci-level` finding has no counterpart. Everything else does.
function auditGovernJob(findings, governHosts, file, jobId, job, governSteps) {
  governHosts.push({ file, job: jobId });
  const at = `${file}: job "${jobId}"`;

  if (job.if !== undefined && job.if !== null) {
    findings.push({
      id: "govern-job-conditional",
      detail:
        `${at} runs the AAHP governance gate under a job-level \`if:\` (${String(job.if).trim()}). ` +
        "When it evaluates false the job is skipped and reports success, having run no gate. " +
        "For a repository whose only AAHP workflow is the governance one, that is the whole backstop.",
    });
  }
  if (softFailing(job["continue-on-error"])) {
    findings.push({
      id: "govern-job-soft-failing",
      detail: `${at} runs the AAHP governance gate but sets continue-on-error, so the job reports success even when a gate fails.`,
    });
  }

  // Per SUBCOMMAND, never per job: see governSubcommands above for why a
  // job-wide "some step is unconditional" test lets the real tamper through.
  for (const sub of ["check", "doctor"]) {
    const subSteps = governSteps.filter(({ step }) => governSubcommands(step.run).includes(sub));
    if (subSteps.length === 0) continue;

    const unconditional = subSteps.filter(({ step }) => step.if === undefined || step.if === null);
    if (unconditional.length === 0) {
      const conds = subSteps
        .map(({ step, i }) => `"${describeStep(step, i)}" if: ${String(step.if).trim()}`)
        .join("; ");
      findings.push({
        id: "govern-step-conditional",
        detail:
          `${at} runs \`aahp ${sub}\` only under a condition (${conds}). ` +
          "On the events where that condition is false the job still reports success, " +
          `having run no ${sub === "check" ? "governance gate" : "conformance gate"}.`,
      });
      continue;
    }

    const hard = unconditional.filter(({ step }) => !softFailing(step["continue-on-error"]));
    if (hard.length === 0) {
      findings.push({
        id: "govern-step-soft-failing",
        detail:
          `${at} runs \`aahp ${sub}\` unconditionally, but every such step sets ` +
          "continue-on-error, so a failing gate still leaves the check green.",
      });
    }
  }
}

// A workflow file that is clearly the AAHP verify workflow but exposes no `run:`
// invoking the gate is UNCLASSIFIABLE, not clean: the gate may be reached through
// a composite action or a reusable workflow this reader cannot follow.
function looksLikeVerifyWorkflow(file, doc) {
  if (basename(file) === "aahp-verify.yml" || basename(file) === "aahp-verify.yaml") return true;
  const name = doc && typeof doc === "object" ? doc.name : null;
  return typeof name === "string" && /^aahp\s+verify$/i.test(name.trim());
}

// Same argument for the governance workflow: a file named or titled as the one
// `aahp init --gates` scaffolds, which exposes no `run:` this reader recognises,
// is undecidable rather than absent.
function looksLikeGovernWorkflow(file, doc) {
  if (basename(file) === "aahp-govern.yml" || basename(file) === "aahp-govern.yaml") return true;
  const name = doc && typeof doc === "object" ? doc.name : null;
  return typeof name === "string" && /^aahp\s+govern$/i.test(name.trim());
}

export function audit(root) {
  const dir = join(root, ".github", "workflows");
  const result = { verdict: "absent", hosts: [], governHosts: [], findings: [], unclassifiable: [] };
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return result; // no workflows directory: the CI backstop is not adopted here
  }

  for (const entry of entries.sort()) {
    if (!/\.ya?ml$/i.test(entry)) continue;
    const file = `.github/workflows/${entry}`;
    const path = join(dir, entry);
    let text;
    try {
      text = readFileSync(path, "utf8");
    } catch (err) {
      result.unclassifiable.push(`${file}: cannot read (${err.message})`);
      continue;
    }
    let doc;
    try {
      doc = parseYamlSubset(text);
    } catch (err) {
      // Only a workflow that plausibly hosts the gate matters here. An unrelated
      // workflow this reader cannot parse is not this gate's business.
      if (
        looksLikeVerifyWorkflow(file, null) ||
        looksLikeGovernWorkflow(file, null) ||
        /verify-handoff\.sh|aahp\s+verify|aahp\s+(check|doctor)/.test(text)
      ) {
        result.unclassifiable.push(`${file}: cannot be parsed (${err.message})`);
      }
      continue;
    }
    const { hosts, governHosts, findings } = auditDoc(doc, file);
    result.hosts.push(...hosts);
    result.governHosts.push(...governHosts);
    result.findings.push(...findings);
    if (hosts.length === 0 && looksLikeVerifyWorkflow(file, doc)) {
      result.unclassifiable.push(
        `${file}: no step runs the AAHP verify gate directly, so whether the gate can be ` +
          "skipped cannot be decided from this file (a composite action or reusable workflow?).",
      );
    }
    if (hosts.length === 0 && governHosts.length === 0 && looksLikeGovernWorkflow(file, doc)) {
      result.unclassifiable.push(
        `${file}: no step runs the AAHP governance gate directly, so whether the gate can be ` +
          "skipped cannot be decided from this file (an `npm run` indirection, a composite " +
          "action or a reusable workflow?).",
      );
    }
  }

  if (result.unclassifiable.length > 0) result.verdict = "unclassifiable";
  else if (result.findings.length > 0) result.verdict = "bypassable";
  else if (result.hosts.length > 0) result.verdict = "enforced";
  else if (result.governHosts.length > 0) result.verdict = "governance-only";
  else result.verdict = "absent";
  return result;
}

// `governance-only` is deliberately NOT folded into `enforced`. Both exit 0 and
// both mean "nothing here can skip the AAHP gate this repository runs", but they
// are answers about different gates: `enforced` says the verify gate runs at
// --level ci, which is the one that compares a handoff checksum, and
// `governance-only` says the repository runs the governance gates and no verify
// gate at all. Collapsing them would let a repository with no handoff integrity
// checking anywhere report the same token as one that has it.
const EXIT = { enforced: 0, absent: 0, "governance-only": 0, bypassable: 1, unclassifiable: 2 };

export function main(argv = process.argv.slice(2)) {
  const flags = argv.filter((a) => a.startsWith("--"));
  const root = resolve(argv.find((a) => !a.startsWith("--")) || ".");
  if (!existsSync(root)) {
    console.error(`check-verify-workflow: no such path: ${root}`);
    return 2;
  }
  const result = audit(root);

  if (flags.includes("--json")) {
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    return EXIT[result.verdict];
  }

  if (result.verdict === "absent") {
    console.log(
      "check-verify-workflow: SKIP - no workflow here runs the AAHP verify gate, so there is no CI backstop to weaken.",
    );
    return 0;
  }
  if (result.verdict === "enforced") {
    const where = result.hosts.map((h) => `${h.file}:${h.job}`).join(", ");
    console.log(`check-verify-workflow: OK - the gate runs unconditionally at --level ci (${where}).`);
    return 0;
  }
  if (result.verdict === "governance-only") {
    const where = result.governHosts.map((h) => `${h.file}:${h.job}`).join(", ");
    console.log(
      `check-verify-workflow: OK - the AAHP governance gate runs unconditionally (${where}). ` +
        "No workflow here runs `aahp verify`, so nothing in this repository compares a handoff checksum.",
    );
    return 0;
  }
  if (result.verdict === "unclassifiable") {
    console.error("check-verify-workflow: UNDECIDED - the gate's workflow could not be classified:");
    for (const u of result.unclassifiable) console.error(`  ${u}`);
    console.error("Undecided is not clean. Resolve the shape, or run the gate from a plain `run:` step.");
    return 2;
  }

  console.error("check-verify-workflow: FAIL - the workflow that runs the AAHP gate can skip it:");
  for (const f of result.findings) console.error(`  [${f.id}] ${f.detail}`);
  console.error(
    "A required check that reports success without running is worse than no check: it is " +
      "branch protection reporting a verdict nobody produced.",
  );
  return 1;
}

const isMain =
  process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMain) {
  process.exit(main());
}
