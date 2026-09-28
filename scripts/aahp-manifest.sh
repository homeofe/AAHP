#!/usr/bin/env bash
# aahp-manifest.sh - (Re)generate MANIFEST.json from existing handoff files
#
# Usage: ./scripts/aahp-manifest.sh [path-to-project] [options]
#        Defaults to current directory if no path given.
#
# Options:
#   --agent NAME       Agent identifier (default: "cli-tool")
#   --session-id ID    Session identifier (default: auto-generated)
#   --phase PHASE      Pipeline phase: research|architecture|implementation|review|fix|idle|documentation (default: "idle")
#   --context "TEXT"   Quick context string, at most 500 characters (default: auto-generated from file summaries)
#   --duration MIN     Session duration in whole minutes (default: 0)
#   --force            Regenerate even when the existing MANIFEST.json cannot be read
#                      or holds a field that cannot be carried over; that data is DROPPED
#   --quiet            Suppress output except errors
#
# Requires bash and Node.js (the runtime the aahp CLI itself needs). git is
# optional: it supplies the project name and the commit when present.
#
# Exit codes:
#   0 = manifest generated successfully
#   1 = error; MANIFEST.json was NOT modified
#
# WHY THE DOCUMENT IS BUILT IN NODE. This script used to assemble MANIFEST.json
# from heredocs and sed. That produced invalid JSON with exit 0 for ordinary
# input: a TAB in STATUS.md's first content line, a `"` in --agent, and a
# non-ASCII character straddling a byte-based `cut` each wrote a file that no
# parser accepts, and regenerating reproduced the same bytes. The whole document
# is now built by ONE node process with JSON.stringify, values arrive on stdin
# (NUL-separated, so no shell or MSYS argument conversion touches them), text is
# truncated by code point, and the file is replaced atomically. Anything that
# fails before the rename leaves the existing MANIFEST.json byte-identical.
# One process instead of ~25 fork/exec per file also takes regeneration on
# Windows from seconds to well under one.
#
# Node is a hard requirement, not an optional speed-up: the previous no-node
# path silently dropped tasks, next_task_id, cross_repo_ref and the recorded
# project name. A generator that cannot carry the existing data over must not
# overwrite it (see --force above).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"

# --- Defaults ------------------------------------------------------------------

AGENT="cli-tool"
SESSION_ID=""
PHASE="idle"
CONTEXT=""
DURATION=0
QUIET=false
FORCE=false

USAGE="Usage: aahp-manifest.sh [path-to-project] [--agent NAME] [--phase PHASE] [--context TEXT] [--duration MIN] [--session-id ID] [--force] [--quiet]"

# --- Parse arguments -----------------------------------------------------------

# First positional arg is project root (if it doesn't start with --)
PROJECT_ROOT="."
if [ $# -gt 0 ] && [[ ! "$1" == --* ]]; then
    PROJECT_ROOT="$1"
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --agent|--session-id|--phase|--context|--duration)
            if [ $# -lt 2 ]; then
                echo "Error: $1 needs a value." >&2
                echo "$USAGE" >&2
                exit 1
            fi
            case "$1" in
                --agent)      AGENT="$2" ;;
                --session-id) SESSION_ID="$2" ;;
                --phase)      PHASE="$2" ;;
                --context)    CONTEXT="$2" ;;
                --duration)   DURATION="$2" ;;
            esac
            shift 2
            ;;
        --force)      FORCE=true; shift ;;
        --quiet)      QUIET=true; shift ;;
        *)
            echo "Unknown option: $1" >&2
            echo "$USAGE" >&2
            exit 1
            ;;
    esac
done

HANDOFF_DIR="$PROJECT_ROOT/.ai/handoff"

# --- Validate ------------------------------------------------------------------

if [ ! -d "$HANDOFF_DIR" ]; then
    echo "Error: $HANDOFF_DIR not found." >&2
    exit 1
fi

# Validate phase
case "$PHASE" in
    research|architecture|implementation|review|fix|idle|documentation) ;;
    *)
        echo "Error: Invalid phase '$PHASE'. Must be one of: research, architecture, implementation, review, fix, idle, documentation" >&2
        exit 1
        ;;
esac

# duration_minutes is a JSON integer (schema: integer, minimum 0). The value
# used to be interpolated into the document unquoted, so `--duration soon`
# wrote a bare word into MANIFEST.json and still exited 0.
case "$DURATION" in
    ''|*[!0-9]*)
        echo "Error: Invalid duration '$DURATION'. Must be a whole number of minutes (0 or more)." >&2
        exit 1
        ;;
esac
if [ "${#DURATION}" -gt 9 ]; then
    echo "Error: Invalid duration '$DURATION'. At most 9 digits." >&2
    exit 1
fi

NODE_BIN=""
if command -v node >/dev/null 2>&1; then
    NODE_BIN="node"
elif command -v node.exe >/dev/null 2>&1; then
    NODE_BIN="node.exe"
fi
if [ -z "$NODE_BIN" ]; then
    echo "aahp-manifest: Node.js was not found on PATH. Generating MANIFEST.json requires node" >&2
    echo "  (the same runtime the aahp CLI needs); nothing was written." >&2
    exit 1
fi

# --- Detect project metadata ---------------------------------------------------

# The project name must come from the repository's IDENTITY, never from the
# directory the generator happens to run in. Agents work in `git worktree`
# checkouts whose directory is named after the BRANCH, and CI unpacks into a
# workdir named after the job, so a cwd-derived name silently rewrites
# "project" to something like "myrepo-some-branch" and that lands on main.
# It is invisible unless somebody re-reads the file after regenerating.
# Resolution order, strongest evidence first:
#
#   1. the "project" already on record in MANIFEST.json (applied in the node
#      program below, once that file has been read) - a name a human set
#      always wins; the "[PROJECT]" placeholder that `aahp init` copies in
#      from templates/MANIFEST.json is not a name anybody chose and is skipped;
#   2. the git remote's repository name - stable across worktrees, temp dirs,
#      CI workdirs and tarballs;
#   3. the directory basename - only for a genuinely new manifest in a repo
#      with no remote, which is the original behaviour.

# Repository name from the remote URL. Handles https, scp-style
# (host:org/repo), ssh:// and local-path remotes, with or without a .git suffix
# or a trailing slash. Only the last path segment is kept, so any credentials
# embedded in the URL are discarded with the rest of it and cannot reach
# MANIFEST.json. The result must still look like a repository name; anything
# else is rejected.
aahp_project_from_remote() {
    local root="$1" remote url name
    if git -C "$root" remote get-url origin >/dev/null 2>&1; then
        remote=origin
    else
        remote=$(git -C "$root" remote 2>/dev/null | head -n 1)
    fi
    [ -n "$remote" ] || return 1
    url=$(git -C "$root" remote get-url "$remote" 2>/dev/null) || return 1
    name="${url%/}"       # drop a trailing slash
    name="${name##*/}"    # keep the last path segment
    name="${name##*:}"    # scp-style remote with no slash after the colon
    name="${name%.git}"   # drop the .git suffix
    case "$name" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    printf '%s' "$name"
}

PROJECT_ABS=$(cd "$PROJECT_ROOT" && pwd)
if ! PROJECT_NAME=$(aahp_project_from_remote "$PROJECT_ABS"); then
    PROJECT_NAME=$(basename "$PROJECT_ABS")
fi
COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

# --- Build and write MANIFEST.json (one node process) ---------------------------
#
# stdin carries the values as NUL-terminated fields, in this order:
#   0 canonical handoff file names (space-separated, AAHP_HANDOFF_FILES)
#   1 agent  2 session id ("" = auto)  3 phase  4 quick context ("" = auto)
#   5 duration minutes  6 project name fallback  7 commit  8 force (1/0)
#   9 quiet (1/0)
# argv[1] is the handoff directory; a path is the one value that MUST go
# through MSYS argument conversion so native Windows node can open it.
#
# The program text must not start with "/" and its first "=" must not be
# followed by "/", or Git Bash would treat the whole -e argument as a path.
IFS= read -r -d '' AAHP_MANIFEST_JS <<'JS' || true
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const NO_SUMMARY = '(no summary available)';
const SUMMARY_MAX = 150;       // code points; the schema allows 200
const CONTEXT_MAX = 500;       // code points; the schema's maxLength
const KNOWN_TOP_LEVEL = ['aahp_version', 'project', 'last_session', 'files', 'quick_context',
  'token_budget', 'next_task_id', 'tasks', 'cross_repo_ref'];
const ISO_SECONDS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
// Labels whose value is bookkeeping, not a statement about the project. A line
// such as "**Agent:** codex" or "Last updated: 2026-09-28" is skipped when a
// summary is chosen; any other "Label: value" line counts as content.
const META_LABELS = new Set(['agent', 'session', 'session id', 'timestamp', 'commit',
  'commit before', 'commit after', 'phase', 'branch', 'task', 'tasks', 'date', 'status',
  'priority', 'owner', 'legend', 'model', 'last updated', 'updated', 'version',
  'current version', 'current package version', 'package version', 'protocol version',
  'expires', 'ttl', 'provenance']);

function warn(message) {
  process.stderr.write('aahp-manifest: WARNING: ' + message + '\n');
}

function isoSeconds(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function codePoints(text) {
  return Array.from(text);
}

// Truncate by CODE POINT, never by byte or UTF-16 unit, so a multi-byte
// character is never cut in half; prefer a word boundary and mark the cut.
function clip(text, max) {
  const cps = codePoints(text);
  if (cps.length <= max) return text;
  let cut = cps.slice(0, max - 3).join('');
  const space = cut.lastIndexOf(' ');
  if (space > (max - 3) / 2) cut = cut.slice(0, space);
  return cut.replace(/[\s,;:.-]+$/, '') + '...';
}

function stripCR(buf) {
  if (!buf.includes(13)) return buf;
  const out = Buffer.allocUnsafe(buf.length);
  let j = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] !== 13) out[j++] = buf[i];
  }
  return out.subarray(0, j);
}

function countNewlines(buf) {
  let n = 0;
  let at = buf.indexOf(10);
  while (at !== -1) {
    n++;
    at = buf.indexOf(10, at + 1);
  }
  return n;
}

// One documented estimator for every tier: the larger of 1.3 tokens per
// whitespace-separated word and 1 token per 4 bytes of UTF-8 (CR stripped,
// so a CRLF checkout estimates like an LF one). The word rule alone rates
// hash-, table- and JSON-heavy text far too low: it put this repository's own
// 4.9 KB MANIFEST.json at ~410 tokens. It is an estimate, not a tokenizer count.
function estimateTokens(buf) {
  const words = (buf.toString('utf8').match(/\S+/g) || []).length;
  return Math.max(Math.ceil((words * 13) / 10), Math.ceil(buf.length / 4));
}

function tidy(text) {
  return text
    .replace(/<!--.*?-->/g, ' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\*\*|__/g, '')
    .replace(/[\u0000-\u001f\u007f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function firstSentence(text) {
  const m = /^(.{20,}?[.!?])(?=\s|$)/.exec(text);
  return m ? m[1] : text;
}

function labelOf(line) {
  const m = /^(?:\*\*|__)([^*_:]{1,40}?):(?:\*\*|__)\s*(.*)$/.exec(line)
    || /^(?:\*\*|__)([^*_:]{1,40}?)(?:\*\*|__):\s*(.*)$/.exec(line)
    || /^([A-Za-z][A-Za-z0-9 ()/-]{0,40}?):(?:\s+(.*))?$/.exec(line);
  return m ? { label: m[1].trim().toLowerCase(), value: (m[2] || '').trim() } : null;
}

// Classify one trimmed Markdown line. Returns 'skip', 'table', 'list' or 'text'.
function kindOf(line, next) {
  if (line === '') return 'skip';
  if (/^#/.test(line)) return 'skip';                              // ATX heading
  if (/^>/.test(line)) return 'skip';                              // blockquote
  if (/^(?:-{3,}|\*{3,}|_{3,}|={3,})$/.test(line)) return 'skip';  // rule / setext underline
  if (/^\|/.test(line)) return 'table';
  if (/^[\[\]{}(),:;"'`\s]+$/.test(line)) return 'skip';           // JSON / code punctuation
  if (/^<\/?[A-Za-z][^>]*>$/.test(line)) return 'skip';            // lone HTML tag
  if (/^!?\[!\[/.test(line) || /^!\[/.test(line)) return 'skip';   // badge / image
  if (/^(?:=+|-+)$/.test(next || '')) return 'skip';                // setext heading text
  const label = labelOf(line);
  if (label && (META_LABELS.has(label.label) || label.value === '')) return 'skip';
  if (/^(?:[-*+]|\d+[.)])\s+/.test(line)) return 'list';
  return 'text';
}

function tableColumns(line) {
  const cells = line.replace(/^\|/, '').replace(/\|$/, '').split('|')
    .map((cell) => tidy(cell)).filter((cell) => cell !== '');
  if (cells.length === 0 || cells.every((cell) => /^:?-+:?$/.test(cell))) return null;
  return 'Table with columns: ' + cells.join(', ');
}

// The first prose sentence of a Markdown file, ignoring document chrome:
// headings, blockquotes, rules, tables, fenced code, HTML comments, JSON
// punctuation and bookkeeping labels. A `<!-- SECTION: summary -->` block, the
// protocol's own summary convention (README Section 1.2), is read first.
function markdownSummary(name, text) {
  const lines = text.split('\n');
  let firstTable = null;

  // A journal is summarized by its newest entry heading ("## [date] agent:
  // title"), which is what an incoming agent wants to know about it.
  const logPrefix = name === 'LOG.md' ? 'Latest entry: '
    : name === 'LOG-ARCHIVE.md' ? 'Newest archived entry: ' : null;
  if (logPrefix) {
    let fence = null;
    for (const raw of lines) {
      const line = raw.trim();
      if (fence) { if (line.startsWith(fence)) fence = null; continue; }
      const open = /^(```+|~~~+)/.exec(line);
      if (open) { fence = open[1]; continue; }
      const entry = /^##\s+(\[.+)$/.exec(line);
      if (entry) return clip(tidy(logPrefix + entry[1]), SUMMARY_MAX);
    }
  }

  function scan(start) {
    let fence = null;
    let inComment = false;
    let parts = null;
    let listMode = false;
    for (let i = start; i < lines.length; i++) {
      const raw = lines[i];
      let line = raw.trim();
      if (inComment) {
        const end = line.indexOf('-->');
        if (end === -1) { if (parts) break; continue; }
        inComment = false;
        line = line.slice(end + 3).trim();
      }
      if (fence) {
        if (line.startsWith(fence)) fence = null;
        if (parts) break;
        continue;
      }
      const fenceOpen = /^(```+|~~~+)/.exec(line);
      if (fenceOpen) { if (parts) break; fence = fenceOpen[1]; continue; }
      if (line.startsWith('<!--')) {
        if (parts) break;
        if (line.indexOf('-->') === -1) inComment = true;
        continue;
      }
      const next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      const kind = kindOf(line, next);
      if (parts) {
        // Continue a paragraph with plain text lines; continue a list item only
        // with its indented continuation lines.
        if (kind === 'text' && (!listMode || /^\s/.test(raw))) { parts.push(line); continue; }
        break;
      }
      if (kind === 'table') { if (firstTable === null) firstTable = tableColumns(line); continue; }
      if (kind === 'skip') continue;
      listMode = kind === 'list';
      parts = [listMode ? line.replace(/^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?/, '') : line];
    }
    if (!parts) return null;
    const joined = tidy(parts.join(' '));
    return joined === '' ? null : clip(firstSentence(joined), SUMMARY_MAX);
  }

  const marker = lines.findIndex((l) => /<!--\s*SECTION:\s*summary\s*-->/i.test(l));
  const fromSection = marker === -1 ? null : scan(marker + 1);
  const summary = fromSection || scan(0);
  if (summary) return summary;
  if (firstTable) return clip(firstTable, SUMMARY_MAX);
  return NO_SUMMARY;
}

function jsonSummary(name, text) {
  let doc;
  try {
    doc = JSON.parse(text.charCodeAt(0) === 0xfeff ? text.slice(1) : text);
  } catch (err) {
    return '(not valid JSON)';
  }
  const label = name === 'pii-allowlist.json' ? 'PII allowlist'
    : name === 'LOG-ARCHIVE.index.json' ? 'LOG archive index' : 'JSON document';
  if (Array.isArray(doc)) return label + ': array of ' + doc.length;
  if (doc && typeof doc === 'object') {
    if (Array.isArray(doc.entries)) {
      const n = doc.entries.length;
      return label + ': ' + n + (n === 1 ? ' entry' : ' entries') + '.';
    }
    return clip(label + ' with keys: ' + Object.keys(doc).join(', '), SUMMARY_MAX);
  }
  return label;
}

function main() {
  const handoffDir = process.argv[1];
  const fields = fs.readFileSync(0).toString('utf8').split('\0');
  if (fields.length < 10) throw new Error('internal: expected 10 input fields, got ' + fields.length);
  const [fileList, agent, sessionArg, phase, contextArg, durationArg, fallbackProject,
    commit, forceArg, quietArg] = fields;
  const force = forceArg === '1';
  const quiet = quietArg === '1';
  const canonical = fileList.split(' ').filter(Boolean);
  const manifestPath = path.join(handoffDir, 'MANIFEST.json');

  // --- What must survive regeneration -------------------------------------
  const problems = [];
  let previous = null;
  if (fs.existsSync(manifestPath)) {
    let text = null;
    try {
      text = fs.readFileSync(manifestPath, 'utf8');
    } catch (err) {
      problems.push('it could not be read (' + err.message + ')');
    }
    if (text !== null) {
      try {
        previous = JSON.parse(text);
      } catch (err) {
        problems.push('it is not valid JSON (' + err.message + ')');
      }
      if (previous !== null && (typeof previous !== 'object' || Array.isArray(previous))) {
        problems.push('its top level is not a JSON object');
        previous = null;
      }
    }
  }

  const carried = {};
  let project = fallbackProject;
  if (previous) {
    const unknown = Object.keys(previous).filter((k) => !KNOWN_TOP_LEVEL.includes(k));
    if (unknown.length) problems.push('it has top-level field(s) the manifest schema does not define: ' + unknown.join(', '));
    if (previous.tasks !== undefined && previous.tasks !== null) carried.tasks = previous.tasks;
    if (previous.cross_repo_ref !== undefined && previous.cross_repo_ref !== null) carried.cross_repo_ref = previous.cross_repo_ref;
    const id = previous.next_task_id;
    if (id !== undefined && id !== null) {
      if (Number.isInteger(id) && id >= 0) carried.next_task_id = id;
      else if (typeof id === 'string' && /^[0-9]+$/.test(id)) carried.next_task_id = Number(id);
      else problems.push('next_task_id ' + JSON.stringify(id) + ' is not a whole number');
    }
    const recorded = previous.project;
    if (typeof recorded === 'string') {
      if (recorded !== '' && recorded !== '[PROJECT]') project = recorded;
    } else if (recorded !== undefined && recorded !== null) {
      problems.push('project ' + JSON.stringify(recorded) + ' is not a string');
    }
  }
  if (problems.length) {
    if (!force) {
      process.stderr.write('aahp-manifest: refusing to overwrite ' + manifestPath + ':\n');
      for (const p of problems) process.stderr.write('  - ' + p + '\n');
      process.stderr.write('  Regenerating now would lose data this generator cannot carry over.\n' +
        '  Fix the file, or re-run with --force to regenerate without it. Nothing was written.\n');
      return 1;
    }
    for (const p of problems) warn('--force: ' + p + '; that data is dropped.');
  }

  // --- File index ---------------------------------------------------------
  const prevFiles = previous && previous.files && typeof previous.files === 'object'
    && !Array.isArray(previous.files) ? previous.files : {};
  const files = {};
  const tokens = {};
  for (const name of canonical) {
    const filePath = path.join(handoffDir, name);
    let st;
    try {
      st = fs.statSync(filePath);
    } catch (err) {
      if (err.code === 'ENOENT' || err.code === 'ENOTDIR') continue;
      throw err;
    }
    if (!st.isFile()) continue;
    const bytes = fs.readFileSync(filePath);
    const lf = stripCR(bytes);
    // Whole-file SHA-256 with CR stripped: CONSTITUTION rule 4, the same
    // contract as aahp_checksum in _aahp-lib.sh and the lint/verify gates.
    const digest = crypto.createHash('sha256').update(lf).digest('hex');
    if (!/^[0-9a-f]{64}$/.test(digest)) {
      throw new Error('could not compute a SHA-256 checksum for ' + name);
    }
    const checksum = 'sha256:' + digest;
    // A checkout sets every mtime to the checkout time. Keep the recorded
    // date while the content is unchanged, so a fresh clone does not re-date
    // files nobody touched; a new or changed file takes its own mtime.
    const prev = prevFiles[name];
    const updated = prev && typeof prev === 'object' && prev.checksum === checksum
      && typeof prev.updated === 'string' && ISO_SECONDS.test(prev.updated)
      ? prev.updated
      : isoSeconds(Number.isNaN(st.mtime.getTime()) ? new Date() : st.mtime);
    const text = lf.toString('utf8');
    files[name] = {
      checksum,
      updated,
      lines: countNewlines(bytes),
      summary: name.endsWith('.json') ? jsonSummary(name, text) : markdownSummary(name, text),
    };
    tokens[name] = estimateTokens(lf);
  }

  // --- Quick context --------------------------------------------------------
  let context = contextArg;
  if (context === '') {
    const parts = [];
    for (const name of ['STATUS.md', 'NEXT_ACTIONS.md']) {
      const entry = files[name];
      if (!entry || entry.summary === NO_SUMMARY) continue;
      parts.push(/[.!?]$/.test(entry.summary) ? entry.summary : entry.summary + '.');
    }
    context = parts.length ? parts.join(' ') : 'No handoff files found with content summaries.';
  }
  if (codePoints(context).length > CONTEXT_MAX) {
    if (contextArg !== '') {
      warn('--context is ' + codePoints(context).length + ' characters; quick_context is truncated to ' + CONTEXT_MAX + '.');
    }
    context = clip(context, CONTEXT_MAX);
  }

  // --- Document -------------------------------------------------------------
  const doc = {
    aahp_version: '3.0',
    project,
    last_session: {
      agent,
      session_id: sessionArg !== '' ? sessionArg : 'cli-' + Math.floor(Date.now() / 1000),
      timestamp: isoSeconds(new Date()),
      commit,
      phase,
      duration_minutes: Number(durationArg),
    },
    files,
    quick_context: context,
    token_budget: { manifest_only: 0, manifest_plus_core: 0, full_read: 0 },
  };
  if (Object.prototype.hasOwnProperty.call(carried, 'next_task_id')) doc.next_task_id = carried.next_task_id;
  if (Object.prototype.hasOwnProperty.call(carried, 'tasks')) doc.tasks = carried.tasks;
  if (Object.prototype.hasOwnProperty.call(carried, 'cross_repo_ref')) doc.cross_repo_ref = carried.cross_repo_ref;

  // manifest_only is the estimate of THIS file, so it is solved as a fixed
  // point: the three numbers are part of the text being estimated. The
  // sequence never decreases and is bounded, so it settles in a few rounds.
  const core = ['STATUS.md', 'NEXT_ACTIONS.md'].reduce((sum, n) => sum + (tokens[n] || 0), 0);
  const all = Object.values(tokens).reduce((sum, n) => sum + n, 0);
  let own = 0;
  let rendered = '';
  for (let round = 0; round < 20; round++) {
    doc.token_budget = { manifest_only: own, manifest_plus_core: own + core, full_read: own + all };
    rendered = JSON.stringify(doc, null, 2) + '\n';
    const estimate = estimateTokens(Buffer.from(rendered, 'utf8'));
    if (estimate === own) break;
    own = estimate;
  }

  // --- Atomic replace ---------------------------------------------------------
  const tmp = path.join(handoffDir, '.MANIFEST.json.' + process.pid + '.tmp');
  try {
    fs.writeFileSync(tmp, rendered);
    fs.renameSync(tmp, manifestPath);
  } catch (err) {
    try { fs.unlinkSync(tmp); } catch (ignored) { /* nothing to clean up */ }
    throw err;
  }

  if (!quiet) {
    const b = doc.token_budget;
    process.stdout.write('MANIFEST.json generated: ' + Object.keys(files).length +
      ' files indexed, checksums current.\n' +
      '  Token budget: manifest=' + b.manifest_only + ', core=' + b.manifest_plus_core +
      ', full=' + b.full_read + '\n');
  }
  return 0;
}

let status;
try {
  status = main();
} catch (err) {
  process.stderr.write('aahp-manifest: ' + (err && err.message ? err.message : String(err)) +
    '\n  MANIFEST.json was not modified.\n');
  status = 1;
}
process.exitCode = status;
JS

FORCE_FLAG=0; [ "$FORCE" = true ] && FORCE_FLAG=1
QUIET_FLAG=0; [ "$QUIET" = true ] && QUIET_FLAG=1

if ! printf '%s\0' "${AAHP_HANDOFF_FILES[*]}" "$AGENT" "$SESSION_ID" "$PHASE" "$CONTEXT" \
        "$DURATION" "$PROJECT_NAME" "$COMMIT" "$FORCE_FLAG" "$QUIET_FLAG" \
        | "$NODE_BIN" -e "$AAHP_MANIFEST_JS" "$HANDOFF_DIR"; then
    exit 1
fi
