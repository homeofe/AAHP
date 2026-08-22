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
 * Usage: node scripts/check-verify-workflow.mjs [path-to-project] [--json]
 * Exit:  0 enforced or not adopted here
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

export function runsVerify(run) {
  return typeof run === "string" && RUNS_VERIFY.some((re) => re.test(run));
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
 * Returns { hosts, findings } where hosts is the list of jobs that run the gate.
 */
export function auditDoc(doc, file) {
  const findings = [];
  const hosts = [];
  const jobs = doc && typeof doc === "object" && doc.jobs && typeof doc.jobs === "object" ? doc.jobs : null;
  if (!jobs) return { hosts, findings };

  for (const [jobId, job] of Object.entries(jobs)) {
    if (!job || typeof job !== "object") continue;
    const steps = Array.isArray(job.steps) ? job.steps.filter((s) => s && typeof s === "object") : [];
    const verifySteps = steps
      .map((s, i) => ({ step: s, i }))
      .filter(({ step }) => runsVerify(step.run));
    if (verifySteps.length === 0) continue;
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

  return { hosts, findings };
}

// A workflow file that is clearly the AAHP verify workflow but exposes no `run:`
// invoking the gate is UNCLASSIFIABLE, not clean: the gate may be reached through
// a composite action or a reusable workflow this reader cannot follow.
function looksLikeVerifyWorkflow(file, doc) {
  if (basename(file) === "aahp-verify.yml" || basename(file) === "aahp-verify.yaml") return true;
  const name = doc && typeof doc === "object" ? doc.name : null;
  return typeof name === "string" && /^aahp\s+verify$/i.test(name.trim());
}

export function audit(root) {
  const dir = join(root, ".github", "workflows");
  const result = { verdict: "absent", hosts: [], findings: [], unclassifiable: [] };
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
      if (looksLikeVerifyWorkflow(file, null) || /verify-handoff\.sh|aahp\s+verify/.test(text)) {
        result.unclassifiable.push(`${file}: cannot be parsed (${err.message})`);
      }
      continue;
    }
    const { hosts, findings } = auditDoc(doc, file);
    result.hosts.push(...hosts);
    result.findings.push(...findings);
    if (hosts.length === 0 && looksLikeVerifyWorkflow(file, doc)) {
      result.unclassifiable.push(
        `${file}: no step runs the AAHP verify gate directly, so whether the gate can be ` +
          "skipped cannot be decided from this file (a composite action or reusable workflow?).",
      );
    }
  }

  if (result.unclassifiable.length > 0) result.verdict = "unclassifiable";
  else if (result.findings.length > 0) result.verdict = "bypassable";
  else if (result.hosts.length > 0) result.verdict = "enforced";
  else result.verdict = "absent";
  return result;
}

const EXIT = { enforced: 0, absent: 0, bypassable: 1, unclassifiable: 2 };

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
