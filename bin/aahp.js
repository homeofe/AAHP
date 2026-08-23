#!/usr/bin/env node

// aahp -AI-to-AI Handoff Protocol CLI
// Usage: npx aahp <command> [path] [options]
//
// Commands:
//   init [path]       Initialize .ai/handoff/ directory with AAHP templates
//                     (init --gates scaffolds governance-only config, no handoff)
//   manifest [path]   (Re)generate MANIFEST.json from existing handoff files
//   lint [path]       Validate handoff files for safety violations
//   migrate [path]    Migrate an AAHP v1 project to v2/v3
//   migrate-grounding [path]  Add the Grounded Reflection Layer to an existing project
//   verify [path]     Run the canonical handoff gate (checksum + drift + TTL)
//   check [path]      Run the config-driven governance gates as one aggregate
//   archive [path]    Rotate or verify LOG.md -> LOG-ARCHIVE.md

//   status [path]     Show a quick state summary from MANIFEST.json
//   doctor [path]     Conformance self-check; emits a JSON conformance record

//
// Options:
//   --help, -h        Show this help message
//   --version, -v     Show version number

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'
import { existsSync, mkdirSync, copyFileSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import { resolveBash, toBashPath } from '../scripts/aahp-config.mjs'
import { validateConfigObject, formatConfigErrors } from '../scripts/aahp-schema.mjs'
import { audit as auditVerifyWorkflow } from '../scripts/check-verify-workflow.mjs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)
const PACKAGE_ROOT = resolve(__dirname, '..')

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getVersion() {
  const pkgPath = join(PACKAGE_ROOT, 'package.json')
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'))
  return pkg.version
}

function printHelp() {
  const version = getVersion()
  console.log(`
aahp v${version} -AI-to-AI Handoff Protocol CLI

Usage:
  aahp <command> [path] [options]

Commands:
  init [path]       Initialize .ai/handoff/ directory with AAHP templates
  manifest [path]   (Re)generate MANIFEST.json from existing handoff files
  lint [path]       Validate handoff files for safety violations
  migrate [path]    Migrate an AAHP v1 project to v2/v3
  migrate-grounding [path]  Add the Grounded Reflection Layer to an existing project
  verify [path]     Run the canonical handoff gate (checksum + drift + TTL)
  check [path]      Run the config-driven governance gates as one aggregate
  criteria [path]   ADVISORY report on the acceptance-criteria lifecycle.
                    Not a gate: it is not part of the check command and always
                    exits 0 unless the report itself cannot run. A clean report
                    is not proof; see the blind spots in README Section 8.7.
  archive [path]    Rotate or verify LOG.md -> LOG-ARCHIVE.md
  status [path]     Show a quick state summary from MANIFEST.json
  doctor [path]     Conformance self-check; emits a JSON conformance record

Init options:
  --gates           Scaffold governance-only config (aahp.config.json + a
                    govern npm script + .github/workflows/aahp-govern.yml);
                    does NOT create .ai/handoff/
  --force           Overwrite existing files (default: skip existing)
  --with-pii-allowlist  Copy pii-allowlist.json template when needed

Check options:
  --json            Print only the JSON governance record to stdout
  --quiet           Print only failing gates (plus the summary)

Manifest options:
  --agent NAME      Agent identifier (default: "cli-tool")
  --session-id ID   Session identifier (default: auto-generated)
  --phase PHASE     Pipeline phase: research|architecture|implementation|review|fix|idle|documentation
  --context "TEXT"  Quick context string
  --duration MIN    Session duration in minutes
  --quiet           Suppress output except errors

Verify options:
  --level LEVEL     Layers to run: precommit|prepush|full|ci (default: full)
  --base SHA        Exact Layer 2 base commit (required at --level ci)
  --quiet           Suppress per-check OK output, keep failures

Doctor options:
  --governance      Governance-only record; skips the 3 handoff gates without
                    evaluating them (alias: --no-handoff). Lets a repo with no
                    .ai/handoff emit a green conformance record.
  --json            Print only the JSON conformance record to stdout
  --quiet           Print only failing gates (plus the record)

Global options:
  --help, -h        Show this help message
  --version, -v     Show version number

Examples:
  npx aahp init                    # Initialize in current directory
  npx aahp init ./my-project       # Initialize in a specific project
  npx aahp manifest --phase implementation --agent claude-sonnet
  npx aahp lint ./my-project
  npx aahp migrate
  npx aahp migrate-grounding       # Add the Grounded Reflection Layer to an existing project
  npx aahp verify --level ci      # CI gate (no escape hatch)
  npx aahp archive --verify       # Verify LOG archive integrity
`)
}

// ---------------------------------------------------------------------------
// Parse the first positional argument as a path (same logic as the bash scripts)
//
// The bash scripts expect: script.sh [path] [--flags...]
// The path is the first argument that does not start with "--".
// We replicate that here so we can resolve it for the init command.
// ---------------------------------------------------------------------------

function extractPathAndFlags(rest) {
  // Flags that take a following value (paired flags from aahp-manifest.sh)
  const pairedFlags = new Set([
    '--agent',
    '--session-id',
    '--phase',
    '--context',
    '--duration',
  ])

  let targetPath = '.'
  let pathFound = false
  const flags = []

  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i]

    if (arg.startsWith('--')) {
      flags.push(arg)
      // If this is a paired flag, consume the next argument too
      if (pairedFlags.has(arg) && i + 1 < rest.length) {
        i++
        flags.push(rest[i])
      }
    } else if (!pathFound) {
      targetPath = arg
      pathFound = true
    } else {
      // Extra positional arg -pass through as-is
      flags.push(arg)
    }
  }

  return { targetPath: resolve(targetPath), flags }
}

// ---------------------------------------------------------------------------
// init command -implemented in Node.js
// ---------------------------------------------------------------------------

function cmdInit(targetPath, flags) {
  const force = flags.includes('--force')
  const includePiiAllowlist = flags.includes('--with-pii-allowlist')
  const handoffDir = join(targetPath, '.ai', 'handoff')
  const templatesDir = join(PACKAGE_ROOT, 'templates')

  if (!existsSync(templatesDir)) {
    console.error('Error: templates/ directory not found in the aahp package.')
    console.error(`Expected at: ${templatesDir}`)
    process.exit(1)
  }

  // Verify target path exists and is accessible
  if (!existsSync(targetPath)) {
    console.error(`Error: target directory does not exist: ${targetPath}`)
    process.exit(1)
  }

  // Create .ai/handoff/ if it does not exist
  if (!existsSync(handoffDir)) {
    try {
      mkdirSync(handoffDir, { recursive: true })
    } catch (err) {
      if (err.code === 'EACCES' || err.code === 'EPERM') {
        console.error(`Error: permission denied creating ${handoffDir}`)
        console.error('Check that you have write access to the target directory.')
      } else {
        console.error(`Error: failed to create ${handoffDir}: ${err.message}`)
      }
      process.exit(1)
    }
    console.log(`Created ${handoffDir}`)
  }

  // Enumerate template files
  const templateFiles = readdirSync(templatesDir)
  let copied = 0
  let skipped = 0

  for (const file of templateFiles) {
    const src = join(templatesDir, file)
    const dest = join(handoffDir, file)

    if (file === 'pii-allowlist.json' && !includePiiAllowlist) {
      console.log(`  skip: ${file} (optional; use --with-pii-allowlist to include)`)
      skipped++
      continue
    }

    if (existsSync(dest) && !force) {
      console.log(`  skip: ${file} (already exists, use --force to overwrite)`)
      skipped++
      continue
    }

    try {
      copyFileSync(src, dest)
    } catch (err) {
      if (err.code === 'EACCES' || err.code === 'EPERM') {
        console.error(`Error: permission denied writing ${dest}`)
        process.exit(1)
      }
      throw err
    }
    console.log(`  copy: ${file}`)
    copied++
  }

  console.log()

  if (copied === 0 && skipped > 0) {
    console.log(`Already initialized. ${skipped} file(s) already exist in ${handoffDir}`)
    console.log('Use --force to overwrite existing files.')
  } else {
    console.log(`Done. ${copied} file(s) copied, ${skipped} skipped.`)
  }

  if (copied > 0) {
    console.log()
    console.log('Next steps:')
    console.log('  1. Replace [PROJECT] placeholders in the template files')
    console.log('  2. Edit CONVENTIONS.md with your project-specific rules')
    console.log('  3. Run: aahp manifest --phase idle')
    console.log('  4. Commit: git add .ai/handoff/ && git commit -m "chore: init AAHP handoff files"')
  }
}

// ---------------------------------------------------------------------------
// init --gates - scaffold governance-only adoption (no handoff protocol).
//
// Writes three things at the project root, each skip-if-exists (--force to
// overwrite): a trimmed aahp.config.json, a `govern` npm script (only when a
// package.json exists), and the portable .github/workflows/aahp-govern.yml
// copied from the packaged asset. It never touches .ai/handoff/. The scaffolded
// config enables the two gates that are green on any git repo out of the box
// (the em-dash ban + internal doc-link check); versionSites/claims/docSync are
// left for the adopter to add once they have the matching files.
// ---------------------------------------------------------------------------

const GATES_CONFIG = {
  $schema: './node_modules/@elvatis_com/aahp/schema/aahp-config.schema.json',
  forbiddenPatterns: [
    // Store the ban as an escape so this config file never matches its own rule.
    { id: 'em-dash', pattern: '\\u2014', message: 'em dash (U+2014) is banned; use a hyphen' },
  ],
  docLinks: {
    include: ['README.md', 'CONTRIBUTING.md', 'docs/*.md'],
  },
}

function cmdInitGates(targetPath, flags) {
  const force = flags.includes('--force')

  if (!existsSync(targetPath)) {
    console.error(`Error: target directory does not exist: ${targetPath}`)
    process.exit(1)
  }

  let wrote = 0
  let skipped = 0

  // All filesystem writes run under one guard so a permission (EACCES/EPERM) or
  // other I/O error exits cleanly with a message instead of a raw stack trace,
  // matching cmdInit's handling.
  try {
    // 1. aahp.config.json (inlined; ASCII; em-dash stored as an escape)
    const configPath = join(targetPath, 'aahp.config.json')
    if (existsSync(configPath) && !force) {
      console.log('  skip: aahp.config.json (already exists, use --force to overwrite)')
      skipped++
    } else {
      writeFileSync(configPath, JSON.stringify(GATES_CONFIG, null, 2) + '\n')
      console.log('  write: aahp.config.json')
      wrote++
    }

    // 2. govern npm script - only when a package.json already exists (never create one)
    const pkgPath = join(targetPath, 'package.json')
    if (existsSync(pkgPath)) {
      const pkg = readJsonSafe(pkgPath)
      if (!pkg) {
        console.log('  skip: package.json present but not valid JSON; not adding a govern script')
        skipped++
      } else if (pkg.scripts && pkg.scripts.govern && !force) {
        console.log('  skip: package.json govern script (already present, use --force to overwrite)')
        skipped++
      } else {
        pkg.scripts = pkg.scripts || {}
        pkg.scripts.govern = 'aahp check .'
        writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n')
        console.log('  update: package.json (added govern script)')
        wrote++
      }
    } else {
      console.log('  note: no package.json; skipped the govern script (add one, then set "govern": "aahp check .")')
    }

    // 3. .github/workflows/aahp-govern.yml (copied from the packaged asset)
    const asset = join(PACKAGE_ROOT, 'assets', 'governance', 'aahp-govern.yml')
    const wfDir = join(targetPath, '.github', 'workflows')
    const wfDest = join(wfDir, 'aahp-govern.yml')
    if (!existsSync(asset)) {
      console.log('  skip: aahp-govern.yml (packaged asset not found)')
      skipped++
    } else if (existsSync(wfDest) && !force) {
      console.log('  skip: .github/workflows/aahp-govern.yml (already exists, use --force to overwrite)')
      skipped++
    } else {
      mkdirSync(wfDir, { recursive: true })
      copyFileSync(asset, wfDest)
      console.log('  write: .github/workflows/aahp-govern.yml')
      wrote++
    }
  } catch (err) {
    if (err.code === 'EACCES' || err.code === 'EPERM') {
      console.error(`Error: permission denied during init --gates: ${err.message}`)
    } else {
      console.error(`Error: init --gates failed: ${err.message}`)
    }
    process.exit(1)
  }

  console.log()
  console.log(`Done. ${wrote} written/updated, ${skipped} skipped.`)
  console.log()
  console.log('Next steps:')
  console.log('  1. Pin aahp exactly: npm install --save-dev --save-exact @elvatis_com/aahp')
  console.log('  2. Tune aahp.config.json (docLinks.include; add versionSites once you keep a CHANGELOG).')
  console.log('  3. Run: npm run govern   (or: npx aahp check .)')
}

// ---------------------------------------------------------------------------

function cmdStatus(targetPath) {
  const handoffDir = join(targetPath, '.ai', 'handoff')
  const manifestPath = join(handoffDir, 'MANIFEST.json')

  if (!existsSync(manifestPath)) {
    console.error(`Error: MANIFEST.json not found at ${manifestPath}`)
    console.error('Run `aahp init` or `aahp manifest` first.')
    process.exit(1)
  }

  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch (err) {
    console.error(`Error: MANIFEST.json parse failed: ${err.message}`)
    process.exit(1)
  }

  const project = manifest.project ?? '(unknown)'
  const lastSession = manifest.last_session ?? {}
  const phase = lastSession.phase ?? '(unknown)'
  const agent = lastSession.agent ?? '(unknown)'
  const sessionId = lastSession.session_id ?? '(unknown)'
  const timestamp = lastSession.timestamp ?? '(unknown)'
  const quickContext = String(manifest.quick_context ?? '').trim() || '(no quick_context)'
  const files = manifest.files ?? {}
  const tasks = manifest.tasks ?? {}

  // Status vocabulary is the schema's task-status enum (schema/aahp-manifest.schema.json).
  // Any value outside it falls into the `other` bucket.
  const statusPriority = ['ready', 'in_progress', 'blocked', 'done', 'cancelled']
  // Null-prototype so a task status like "toString"/"valueOf" cannot match the
  // `in` check below via the prototype chain.
  const taskStatusCounts = Object.assign(Object.create(null), {
    ready: 0,
    in_progress: 0,
    blocked: 0,
    done: 0,
    cancelled: 0,
    other: 0,
  })

  for (const task of Object.values(tasks)) {
    const currentStatus = typeof task === 'object' && task !== null && 'status' in task ? String(task.status) : 'other'
    if (currentStatus in taskStatusCounts) {
      taskStatusCounts[currentStatus] += 1
    } else {
      taskStatusCounts.other += 1
    }
  }

  const manifestPathLines = files['MANIFEST.json']?.lines
  const nextActionsLines = files['NEXT_ACTIONS.md']?.lines

  let previewTasks = Object.entries(tasks)
    .filter(([, task]) => typeof task === 'object' && task !== null && ['ready', 'in_progress'].includes(String(task.status)))
    .slice(0, 5)
    .map(([id, task]) => `  ${id}: ${String(task.title ?? '(no title)')} (${String(task.status)})`)

  const statusLines = statusPriority
    .filter((status) => taskStatusCounts[status] > 0)
    .map((status) => `${status}: ${taskStatusCounts[status]}`)

  if (statusLines.length === 0 && taskStatusCounts.other > 0) {
    statusLines.push(`other: ${taskStatusCounts.other}`)
  } else if (statusLines.length === 0) {
    statusLines.push('none')
  }

  if (previewTasks.length === 0) {
    previewTasks = ['  (no ready or in_progress tasks)']
  }

  console.log(`Project: ${project}`)
  console.log(`Path: ${targetPath}`)
  console.log(`Phase: ${phase}`)
  console.log(`Agent: ${agent}`)
  console.log(`Session: ${timestamp}`)
  console.log(`Session ID: ${sessionId}`)
  console.log(`Commit: ${lastSession.commit ?? '(none)'}`)
  console.log(`Manifest lines: ${manifestPathLines ?? '?'}`)
  console.log(`Next actions lines: ${nextActionsLines ?? '?'}`)
  console.log(`Task counts: ${statusLines.join(', ')}`)
  console.log(`Quick context: ${quickContext}`)
  console.log('Open ready/in_progress tasks:')
  for (const line of previewTasks) {
    console.log(line)
  }
}

// ---------------------------------------------------------------------------
// doctor command -conformance self-check emitting a machine-readable JSON record
//
// Asserts CONFORMANCE (not just drift) against the AAHP contract and emits a
// record aahp-hub can ingest to render a fleet matrix. Implemented Node-native
// (like status) because it must assemble JSON and stay cross-platform (the bash
// path has documented MSYS/Windows fragility). Gate statuses:
//   pass    -conforms
//   fail    -present but wrong
//   missing -a required thing is absent (e.g. an unpinned/absent dep)
//   skip    -not applicable here (e.g. no CHANGELOG.md, no versionSites)
//   self    -this repo IS @elvatis_com/aahp, so it does not pin itself
// ---------------------------------------------------------------------------

function readJsonSafe(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

// ---------------------------------------------------------------------------
// The gate over the gates: aahp.config.json must match its own schema.
//
// `gateApplies` below decides whether a gate runs from the PRESENCE of a config
// key. That makes a misspelled key indistinguishable from an absent section, and
// an absent section is a clean `skip`. So `forbiddenPatterns` written as
// `forbiddenPaterns` turned a FAILING gate into `Governance OK`, exit 0, with the
// violation still in the tree. `readJsonSafe` made the unparseable case worse
// still: it returned null, the caller substituted {}, and every gate skipped.
//
// This reads the config ONCE for check and doctor and reports three outcomes
// that must never be collapsed into each other:
//   absent   -> {} and no problem; an unconfigured repo is legitimately a no-op
//   invalid  -> a problem; NO gate is evaluated and the command exits non-zero
//   valid    -> the parsed config
//
// The `unevaluated` status the callers emit for every gate in the invalid case
// is deliberately NOT `skip`: `skip` means "asked, not applicable here", and a
// dashboard that cannot tell those apart is what let this go unnoticed.
// ---------------------------------------------------------------------------
function readConfigOrExplain(targetPath) {
  const p = join(targetPath, 'aahp.config.json')
  if (!existsSync(p)) return { config: {}, problem: null, errors: [] }
  let parsed
  try {
    parsed = JSON.parse(readFileSync(p, 'utf8'))
  } catch (err) {
    return {
      config: {},
      problem: `aahp.config.json is not valid JSON: ${err.message}`,
      // The parser's own message is carried into the record, not just the
      // category: under --json this record is the ONLY output, so dropping it
      // would leave a machine-readable "invalid" that nobody can act on.
      errors: [{ path: '', message: `not valid JSON: ${err.message}` }],
    }
  }
  try {
    const errors = validateConfigObject(parsed)
    if (errors.length === 0) return { config: parsed, problem: null, errors: [] }
    return { config: parsed, problem: formatConfigErrors(errors), errors }
  } catch (err) {
    // The question could not be ASKED (schema absent from the installed
    // package, or the schema uses a keyword the validator does not implement).
    // Reporting that as a pass is the exact defect being fixed, so it is an
    // error with its own wording.
    return {
      config: parsed,
      problem: `aahp.config.json could not be validated: ${err.message}`,
      errors: [{ path: '', message: `could not be validated: ${err.message}` }],
    }
  }
}

function firstLine(text) {
  return String(text || '')
    .split('\n')
    .map((l) => l.trim())
    .find((l) => l.length > 0) || 'gate failed'
}

// ---------------------------------------------------------------------------
// Gate applicability - ONE predicate, shared by `doctor` and `check`.
//
// A gate that cannot apply must SKIP, never FAIL: a structural absence (no root
// package.json, no config section, no adopted handoff set) is not a governance
// violation. This lives in one place because the alternative was three commands
// holding three different opinions about the same repository - `doctor` failed
// changelog-format on a root with no package.json while `check` skipped it, and
// `verify` was green throughout.
//
// The version-derived gates (changelog, changelog-format, version-sync) and the
// distribution-pin gate need a root package.json: it is the single version
// source and the only place a pin can be declared. A polyglot project can adopt
// AAHP at a root that has none (a Python service whose only package.json lives
// in a frontend subdirectory, say) and still keep a valid handoff set.
//
// Applicability is decided on the PRESENCE of package.json, never on it parsing.
// A file that exists but is not valid JSON keeps its gates applicable, so they
// run and fail loudly with the parse error instead of vanishing into a skip.
// ---------------------------------------------------------------------------

function gateApplies(id, targetPath, config) {
  const has = (...p) => existsSync(join(targetPath, ...p))
  const cfg = config || {}
  switch (id) {
    case 'changelog':
    case 'changelog-format':
      return has('package.json') && has('CHANGELOG.md')
    case 'version-sync':
      return has('package.json') && Array.isArray(cfg.versionSites) && cfg.versionSites.length > 0
    case 'pinned-dep':
      return has('package.json')
    case 'claims':
      return Array.isArray(cfg.claims) && cfg.claims.length > 0
    case 'forbidden-patterns':
      return Array.isArray(cfg.forbiddenPatterns) && cfg.forbiddenPatterns.length > 0
    case 'schema-doc-sync':
      return Array.isArray(cfg.docSync) && cfg.docSync.length > 0
    case 'doc-links':
      return !!cfg.docLinks
    case 'handoff':
      return has('.ai', 'handoff', 'MANIFEST.json')
    default:
      return false
  }
}

// Why a gate did not apply, phrased for a human reading `doctor` output. The
// most specific missing precondition wins, so "no CHANGELOG.md" is preferred
// over the generic version-source message when both are absent.
function notApplicableReason(id, targetPath, config) {
  const has = (...p) => existsSync(join(targetPath, ...p))
  const cfg = config || {}
  if ((id === 'changelog' || id === 'changelog-format') && !has('CHANGELOG.md')) return 'no CHANGELOG.md'
  if (id === 'version-sync' && !(Array.isArray(cfg.versionSites) && cfg.versionSites.length > 0)) return 'no versionSites configured'
  if (!has('package.json')) return 'no root package.json, so this gate has nothing to check against'
  return 'not applicable here'
}

// Parse the canonical handoff file list from the bash source of truth so the
// Node tooling never drifts from _aahp-lib.sh.
function handoffFileSet() {
  try {
    const lib = readFileSync(join(PACKAGE_ROOT, 'scripts', '_aahp-lib.sh'), 'utf8')
    const m = lib.match(/AAHP_HANDOFF_FILES=\(([^)]*)\)/)
    return m ? m[1].split(/\s+/).map((s) => s.trim()).filter(Boolean) : []
  } catch {
    return []
  }
}

function deriveRepo(targetPath, pkg) {
  const repoField = pkg && pkg.repository
  const url = typeof repoField === 'string' ? repoField : repoField && repoField.url
  const fromPkg = url && String(url).match(/github\.com[/:]([^/]+\/[^/.]+?)(?:\.git)?$/)
  if (fromPkg) return fromPkg[1]
  const git = spawnSync('git', ['-C', targetPath, 'remote', 'get-url', 'origin'], { encoding: 'utf8' })
  const m = git.status === 0 && git.stdout.match(/github\.com[/:]([^/]+\/[^/.]+?)(?:\.git)?\s*$/)
  return m ? m[1] : 'unknown'
}

function runGate(scriptName, targetPath) {
  return spawnSync(process.execPath, [join(PACKAGE_ROOT, 'scripts', scriptName), targetPath], { encoding: 'utf8' })
}

// ---------------------------------------------------------------------------
// handoff-set gate - the file SET and the INDEX, never the file CONTENT.
//
// This gate hashes nothing. It answers three questions: is every indexed file
// on disk, is every canonical file on disk also in files{}, and is anything
// untracked lying next to them. Whether the bytes still match the recorded
// checksum is `aahp verify` Layer 1's question. ADR-011 assigns handoff drift
// to `aahp verify`; the comparison itself lives in scripts/verify-handoff.sh,
// which hashes each indexed file against its recorded checksum and additionally
// runs scripts/lint-handoff.sh, which compares them again. lint is NOT a
// substitute for Layer 1: its comparison runs only under a Python interpreter,
// and with none on PATH lint reports that MANIFEST integrity was NOT verified
// and still exits 0. Layer 1 fails outright when no interpreter is available.
// Neither `aahp doctor` nor `aahp check` compares content, so neither can
// observe drift. The pass reason below says so out loud rather than leaving a
// green line to imply otherwise, the same way scripts/lint-handoff.sh reports a
// clean run whose MANIFEST integrity it could not verify.
//
// LIMIT OF THIS WORDING, deliberate, and the thing to know before relying on
// it: only the DEFAULT human-readable `aahp doctor` output carries the reason.
// `--json` carries gate statuses and no reasons, `--quiet` prints nothing for a
// passing gate, and `--governance` marks this gate `skip` without evaluating
// it. Those three are the invocations wired into CI and hooks
// (.github/workflows/aahp-verify.yml, assets/governance/aahp-govern.yml,
// scripts/hooks/pre-push), so a repository that reads the schemaVersion 1
// record as a handoff-integrity signal is told exactly what it was told before.
// Holding that record byte-identical is a compatibility choice for dashboards
// that already ingest it; changing it is a schemaVersion decision, not taken
// here.
//
// The one configuration where that matters to an adopter: when the
// `verify-workflow` gate reports `skip` (no workflow in this repository runs
// the AAHP verify gate) and the handoff gates are still evaluated, NO automated
// gate in that repository compares a handoff checksum. The record is green and honest
// about what it measured, and it is not a statement about handoff integrity.
// Adopt .github/workflows/aahp-verify.yml, which runs `aahp verify --level ci`
// before `aahp doctor` in the same job, or run `aahp verify` some other way.
function gateHandoffSet(handoffDir) {
  const manifestPath = join(handoffDir, 'MANIFEST.json')
  if (!existsSync(manifestPath)) return { status: 'fail', reason: 'MANIFEST.json not found' }
  const manifest = readJsonSafe(manifestPath)
  if (!manifest) return { status: 'fail', reason: 'MANIFEST.json is not valid JSON' }
  const canonical = new Set(handoffFileSet())
  const files = manifest.files || {}
  const missing = Object.keys(files).filter((f) => !existsSync(join(handoffDir, f)))
  if (missing.length) return { status: 'fail', reason: `indexed file(s) missing on disk: ${missing.join(', ')}` }
  // Partial index: a canonical handoff file is on disk but missing from files{}.
  // Mirrors Layer 1 / lint-handoff so doctor cannot green-wash a partial index.
  const unindexed = [...canonical].filter(
    (f) => existsSync(join(handoffDir, f)) && !Object.prototype.hasOwnProperty.call(files, f)
  )
  if (unindexed.length) {
    return {
      status: 'fail',
      reason: `canonical file(s) present but not indexed: ${unindexed.join(', ')}`
    }
  }
  let entries = []
  try {
    entries = readdirSync(handoffDir)
  } catch {
    // handoff dir unreadable is already covered by the MANIFEST check above
  }
  const strays = entries.filter((f) => /\.(md|json)$/.test(f) && f !== 'MANIFEST.json' && !canonical.has(f))
  if (strays.length) return { status: 'fail', reason: `untracked stray handoff file(s): ${strays.join(', ')}` }
  // Name what was NOT compared. A bare "no strays" reads as an integrity
  // verdict to anyone who has not read ADR-011; this gate never hashed a byte.
  return {
    status: 'pass',
    reason:
      `${Object.keys(files).length} indexed files present, no strays` +
      ' (content not compared; aahp verify Layer 1 owns checksum integrity)'
  }
}

function gateManifestSchema(handoffDir) {
  const manifest = readJsonSafe(join(handoffDir, 'MANIFEST.json'))
  if (!manifest) return { status: 'fail', reason: 'MANIFEST.json missing or invalid JSON' }
  const isStr = (v) => typeof v === 'string'
  const errs = []
  if (!isStr(manifest.aahp_version) || !/^\d+\.\d+$/.test(manifest.aahp_version)) errs.push('aahp_version must match \\d+.\\d+')
  if (!isStr(manifest.project) || !manifest.project) errs.push('project must be a non-empty string')
  const ls = manifest.last_session
  if (!ls || typeof ls !== 'object') {
    errs.push('last_session missing')
  } else {
    if (!isStr(ls.agent)) errs.push('last_session.agent missing')
    if (!isStr(ls.timestamp)) errs.push('last_session.timestamp missing')
    if (!['research', 'architecture', 'implementation', 'review', 'fix', 'idle', 'documentation'].includes(ls.phase)) errs.push('last_session.phase invalid')
  }
  if (!isStr(manifest.quick_context)) errs.push('quick_context must be a string')
  const files = manifest.files
  if (!files || typeof files !== 'object') {
    errs.push('files object missing')
  } else {
    for (const [name, e] of Object.entries(files)) {
      if (!e || typeof e !== 'object') { errs.push(`files.${name} malformed`); continue }
      if (!isStr(e.checksum) || !/^sha256:[a-f0-9]{64}$/.test(e.checksum)) errs.push(`files.${name}.checksum invalid`)
      if (!isStr(e.updated)) errs.push(`files.${name}.updated missing`)
      if (!Number.isInteger(e.lines) || e.lines < 0) errs.push(`files.${name}.lines invalid`)
      if (!isStr(e.summary)) errs.push(`files.${name}.summary missing`)
    }
  }
  if ('next_task_id' in manifest && (!Number.isInteger(manifest.next_task_id) || manifest.next_task_id < 1)) errs.push('next_task_id must be an integer >= 1')
  if (manifest.tasks && typeof manifest.tasks === 'object') {
    for (const [id, t] of Object.entries(manifest.tasks)) {
      if (!/^T-\d{3,}$/.test(id)) errs.push(`task id "${id}" invalid`)
      else if (!t || !isStr(t.title) || !isStr(t.status)) errs.push(`task ${id} missing title/status`)
    }
  }
  if (errs.length) return { status: 'fail', reason: errs.slice(0, 5).join('; ') + (errs.length > 5 ? ` (+${errs.length - 5} more)` : '') }
  return { status: 'pass', reason: 'structural checks against aahp-manifest.schema.json pass' }
}

function gateGrounding(handoffDir) {
  if (!existsSync(join(handoffDir, 'GROUNDING.md'))) return { status: 'fail', reason: 'GROUNDING.md not found' }
  const trustPath = join(handoffDir, 'TRUST.md')
  if (!existsSync(trustPath)) return { status: 'fail', reason: 'TRUST.md not found' }
  const trust = readFileSync(trustPath, 'utf8')
  if (!/^\|[^\n]*\bProvenance\b[^\n]*\|/im.test(trust)) return { status: 'fail', reason: 'TRUST.md has no Provenance column' }
  return { status: 'pass', reason: 'GROUNDING.md present; TRUST.md has a Provenance column' }
}

// Distribution-pin gate. Config-driven and opt-in (C-7): the package name, the
// dependency block, and whether a range is acceptable all come from the optional
// pinnedDep config. A repo with no root package.json has nowhere to declare a
// pin, so the gate skips before anything else. A repo whose own name equals the
// target name is `self` (checked before config so AAHP stays self with no
// config). When pinnedDep is absent the gate is `skip` - it never forces an
// unrelated consumer red.
function gatePinnedDep(targetPath, pkg, config) {
  if (!gateApplies('pinned-dep', targetPath, config)) {
    return { status: 'skip', reason: notApplicableReason('pinned-dep', targetPath, config) }
  }
  const cfg = (config && typeof config.pinnedDep === 'object' && config.pinnedDep) || null
  const name = (cfg && typeof cfg.name === 'string' && cfg.name) || '@elvatis_com/aahp'
  if (pkg && pkg.name === name) return { status: 'self', reason: `this repo is ${name} itself` }
  if (!cfg) return { status: 'skip', reason: 'distribution pin not asserted (set pinnedDep to enable)' }
  const location = cfg.location === 'dependencies' || cfg.location === 'any' ? cfg.location : 'devDependencies'
  const dev = (pkg && pkg.devDependencies) || {}
  const reg = (pkg && pkg.dependencies) || {}
  let spec
  if (location === 'dependencies') spec = reg[name]
  else if (location === 'any') spec = dev[name] !== undefined ? dev[name] : reg[name]
  else spec = dev[name]
  if (spec === undefined) return { status: 'missing', reason: `${name} not pinned in ${location}` }
  if (/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(spec)) return { status: 'pass', reason: `pinned exact: ${spec}` }
  if (cfg.allowRange === true) return { status: 'pass', reason: `pinned (range allowed): ${spec}` }
  return { status: 'fail', reason: `not an exact pin: "${spec}" (use an exact version, or set pinnedDep.allowRange:true)` }
}

// The underlying gate reads the top release heading and compares it with the
// package.json version, so without a root package.json it exits on the missing
// version source before it ever opens the changelog. That is inapplicability,
// not a format violation, so it skips here exactly as it does in `check`.
function gateChangelogFormat(targetPath, config) {
  if (!gateApplies('changelog-format', targetPath, config)) {
    return { status: 'skip', reason: notApplicableReason('changelog-format', targetPath, config) }
  }
  const r = runGate('check-changelog-format.mjs', targetPath)
  if (r.status === 0) return { status: 'pass', reason: 'Keep a Changelog format valid' }
  return { status: 'fail', reason: firstLine(r.stderr || r.stdout) }
}

function gateVersionSync(targetPath, config) {
  const sites = Array.isArray(config && config.versionSites) ? config.versionSites : []
  if (!gateApplies('version-sync', targetPath, config)) {
    return { status: 'skip', reason: notApplicableReason('version-sync', targetPath, config) }
  }
  const r = runGate('check-version-sync.mjs', targetPath)
  if (r.status === 0) return { status: 'pass', reason: `version matches ${sites.length} site(s)` }
  return { status: 'fail', reason: firstLine(r.stderr || r.stdout) }
}

// ---------------------------------------------------------------------------
// verify-workflow gate - "can the workflow that runs me skip me?"
//
// Every other gate here asks whether the repository is in a good state. This one
// asks whether the CHECK THAT ENFORCES that state can be made to report success
// without running, which no amount of repository state can reveal. A consumer
// that wraps the AAHP verify job (or the gate step inside it) in an `if:` keeps
// the required check's name and its green tick while it evaluates nothing: Layer
// 1 MANIFEST checksum integrity is skipped along with the Layer 2 drift gate.
//
// It cannot be caught inside AAHP, because the workflow AAHP ships and
// propagate.sh copies is unconditional. It only exists in the consumer's copy,
// so only a check running inside the consumer can see it. That is why it lives
// in `doctor`: the canonical workflow's last step runs `aahp doctor`, so a
// consumer that has weakened the gate now says so on its own pull requests.
//
// A repository with no such workflow SKIPs (nothing to weaken). A workflow that
// hosts the gate but cannot be classified FAILs, because undecided is not clean.
function gateVerifyWorkflow(targetPath) {
  let result
  try {
    result = auditVerifyWorkflow(targetPath)
  } catch (err) {
    return { status: 'fail', reason: `could not audit the verify workflow: ${err.message}` }
  }
  if (result.verdict === 'absent') {
    return { status: 'skip', reason: 'no workflow here runs the AAHP verify gate' }
  }
  if (result.verdict === 'enforced') {
    const where = result.hosts.map((h) => `${h.file}:${h.job}`).join(', ')
    return { status: 'pass', reason: `the gate runs unconditionally at --level ci (${where})` }
  }
  if (result.verdict === 'unclassifiable') {
    return { status: 'fail', reason: `undecidable verify workflow: ${result.unclassifiable[0]}` }
  }
  const first = result.findings[0]
  const more = result.findings.length > 1 ? ` (+${result.findings.length - 1} more)` : ''
  return { status: 'fail', reason: `the gate can be skipped [${first.id}] ${first.detail}${more}` }
}

function cmdDoctor(targetPath, flags) {
  const jsonOnly = flags.includes('--json')
  const quiet = flags.includes('--quiet')
  // Governance mode (A-2): skip the 3 handoff gates WITHOUT evaluating them, so
  // a repo with no .ai/handoff can still emit a green conformance record.
  const governance = flags.includes('--governance') || flags.includes('--no-handoff')
  const handoffDir = join(targetPath, '.ai', 'handoff')
  const pkg = readJsonSafe(join(targetPath, 'package.json')) || {}
  const { config, problem: configProblem, errors: configErrors } = readConfigOrExplain(targetPath)

  // Same rule as `check`: a config that does not match its own schema is an
  // error, and the record says which gates were never evaluated because of it.
  if (configProblem) {
    const gateIds = ['handoff-set', 'manifest-schema', 'grounding', 'pinned-dep', 'changelog-format', 'version-sync', 'verify-workflow']
    const gates = {}
    for (const id of gateIds) gates[id] = 'unevaluated'
    const record = {
      schemaVersion: 1,
      ...(governance ? { mode: 'governance' } : {}),
      repo: deriveRepo(targetPath, pkg),
      aahpVersion: getVersion(),
      config: { valid: false, errors: configErrors },
      gates,
      checkedAt: new Date().toISOString(),
    }
    if (jsonOnly) {
      process.stdout.write(JSON.stringify(record, null, 2) + '\n')
      process.exit(1)
    }
    if (!quiet) {
      console.log(`\naahp doctor -conformance for ${record.repo} (aahp v${record.aahpVersion})`)
      console.log('=========================================')
    }
    console.error(configProblem)
    if (!quiet) console.log('=========================================')
    console.log(
      'Conformance NOT EVALUATED: aahp.config.json is invalid, so no gate ran. This is not a pass.',
    )
    process.exit(1)
  }

  const handoffSkip = { status: 'skip', reason: 'governance mode: handoff gate not evaluated' }
  const results = {
    'handoff-set': governance ? handoffSkip : gateHandoffSet(handoffDir),
    'manifest-schema': governance ? handoffSkip : gateManifestSchema(handoffDir),
    grounding: governance ? handoffSkip : gateGrounding(handoffDir),
    'pinned-dep': gatePinnedDep(targetPath, pkg, config),
    'changelog-format': gateChangelogFormat(targetPath, config),
    'version-sync': gateVersionSync(targetPath, config),
    // Evaluated in governance mode too: a repo can adopt the CI backstop
    // without adopting the handoff files, and weakening it matters either way.
    'verify-workflow': gateVerifyWorkflow(targetPath),
  }

  const gates = {}
  for (const [k, v] of Object.entries(results)) gates[k] = v.status

  // `mode` is additive and present ONLY in governance mode, so the default
  // record stays byte-for-byte identical to prior versions (backward compat).
  const record = {
    schemaVersion: 1,
    ...(governance ? { mode: 'governance' } : {}),
    repo: deriveRepo(targetPath, pkg),
    aahpVersion: getVersion(),
    gates,
    checkedAt: new Date().toISOString(),
  }

  const failing = Object.entries(gates).filter(([, s]) => s === 'fail' || s === 'missing')

  if (jsonOnly) {
    process.stdout.write(JSON.stringify(record, null, 2) + '\n')
    process.exit(failing.length === 0 ? 0 : 1)
  }

  const labels = { pass: 'PASS', fail: 'FAIL', missing: 'MISSING', skip: 'SKIP', self: 'SELF' }
  if (!quiet) {
    console.log(`\naahp doctor -conformance for ${record.repo} (aahp v${record.aahpVersion})`)
    console.log('=========================================')
  }
  for (const [k, v] of Object.entries(results)) {
    const tag = labels[v.status] || v.status.toUpperCase()
    const ok = v.status === 'pass' || v.status === 'skip' || v.status === 'self'
    if (!ok || !quiet) console.log(`  ${tag.padEnd(8)} ${k}: ${v.reason}`)
  }
  if (!quiet) console.log('=========================================')
  if (failing.length === 0) {
    if (!quiet) console.log(`Conformance OK: ${Object.keys(gates).length} gate(s), no failures.`)
  } else {
    console.log(`Conformance FAILED: ${failing.map(([k]) => k).join(', ')}.`)
  }
  if (!quiet) {
    console.log('\nJSON record:')
    console.log(JSON.stringify(record))
  }

  process.exit(failing.length === 0 ? 0 : 1)
}

// ---------------------------------------------------------------------------
// check command - run the config-driven governance gates as one aggregate.
//
// Unlike `doctor` (a conformance RECORD over handoff + release gates), `check`
// is the pass/fail RUN a consumer wires into CI. It executes every APPLICABLE
// governance gate against [path], continues past a failure so one run surfaces
// them all, and exits non-zero iff any gate fails. Each gate is a clean no-op
// when its precondition is absent, so an unconfigured repo exits 0 with skips.
// This is the SINGLE definition of the gate set; keep it in step with the
// package.json "check" script chain (a test asserts dogfood parity).
// ---------------------------------------------------------------------------

const CHECK_GATES = [
  { id: 'changelog', script: 'check-changelog.mjs', args: [] },
  { id: 'changelog-format', script: 'check-changelog-format.mjs', args: [] },
  { id: 'version-sync', script: 'check-version-sync.mjs', args: [] },
  { id: 'claims', script: 'check-claims.mjs', args: [] },
  { id: 'forbidden-patterns', script: 'check-forbidden-patterns.mjs', args: [] },
  { id: 'schema-doc-sync', script: 'check-schema-doc-sync.mjs', args: [] },
  { id: 'doc-links', script: 'check-doc-links.mjs', args: [] },
  { id: 'handoff', script: 'aahp-dashboard.mjs', args: ['--check'] },
]

// Applicability comes from the shared gateApplies predicate defined above, which
// `doctor` consults too, so the two commands cannot disagree about which gates a
// given repository is subject to.

function cmdCheck(targetPath, flags) {
  const jsonOnly = flags.includes('--json')
  const quiet = flags.includes('--quiet')
  const pkg = readJsonSafe(join(targetPath, 'package.json'))
  const { config, problem: configProblem, errors: configErrors } = readConfigOrExplain(targetPath)

  // An invalid config is an ERROR, not a set of skips. Returning here means no
  // gate is evaluated and the summary says so, which is a third outcome distinct
  // from "every gate passed" and from "a gate failed".
  if (configProblem) {
    const gates = {}
    for (const gate of CHECK_GATES) gates[gate.id] = 'unevaluated'
    const record = {
      schemaVersion: 1,
      command: 'check',
      repo: deriveRepo(targetPath, pkg || {}),
      aahpVersion: getVersion(),
      config: { valid: false, errors: configErrors },
      gates,
      checkedAt: new Date().toISOString(),
    }
    if (jsonOnly) {
      process.stdout.write(JSON.stringify(record, null, 2) + '\n')
      process.exit(1)
    }
    if (!quiet) {
      console.log(`\naahp check - governance gates for ${record.repo} (aahp v${record.aahpVersion})`)
      console.log('=========================================')
    }
    console.error(configProblem)
    if (!quiet) console.log('=========================================')
    console.log(
      'Governance NOT EVALUATED: aahp.config.json is invalid, so no gate ran. This is not a pass.',
    )
    process.exit(1)
  }

  const sel = (config && typeof config.check === 'object' && config.check) || {}
  const only = Array.isArray(sel.only) ? sel.only : null
  const skip = Array.isArray(sel.skip) ? sel.skip : []

  // A gate id that does not exist is a typo, and a typo here WAS the defect:
  // check.only: ['forbidden-paterns'] deselected every gate, printed
  // 'Governance OK: 0 gate(s) ran, no failures.' and exited 0 with the violation
  // still in the tree. Validated against CHECK_GATES rather than against an enum
  // in the schema on purpose: a second copy of the gate ids drifts the moment a
  // gate is added, and drift here brings the defect back with nothing turning
  // red. The list that runs the gates cannot disagree with itself.
  const knownGateIds = CHECK_GATES.map((g) => g.id)
  const unknownIds = [...(only || []), ...skip].filter((id) => !knownGateIds.includes(id))
  if (unknownIds.length > 0) {
    console.log('=========================================')
    console.log(
      `Governance NOT EVALUATED: aahp.config.json selects gate id(s) that do not exist: ${unknownIds.join(', ')}.`,
    )
    console.log(`Known gate ids: ${knownGateIds.join(', ')}.`)
    console.log('No gate ran. This is not a pass.')
    process.exit(1)
  }

  const results = {}
  for (const gate of CHECK_GATES) {
    let status, reason
    if ((only && !only.includes(gate.id)) || skip.includes(gate.id)) {
      status = 'skip'
      reason = 'deselected by config.check'
    } else if (!gateApplies(gate.id, targetPath, config)) {
      status = 'skip'
      reason = 'not applicable here'
    } else {
      const r = spawnSync(process.execPath, [join(PACKAGE_ROOT, 'scripts', gate.script), ...gate.args, targetPath], { encoding: 'utf8' })
      if (r.error) {
        // The gate process could not be spawned at all (e.g. missing interpreter).
        status = 'fail'
        reason = `failed to run gate: ${r.error.message}`
      } else if (r.status === 0) {
        status = 'pass'
        reason = firstLine(r.stdout)
      } else {
        // Non-zero exit, or r.status === null when the gate was killed by a signal.
        status = 'fail'
        reason = r.signal ? `gate killed by signal ${r.signal}` : firstLine(r.stderr || r.stdout)
      }
    }
    results[gate.id] = { status, reason }
  }

  const gates = {}
  for (const [k, v] of Object.entries(results)) gates[k] = v.status
  const failing = Object.entries(gates).filter(([, s]) => s === 'fail')

  const record = {
    schemaVersion: 1,
    command: 'check',
    repo: deriveRepo(targetPath, pkg || {}),
    aahpVersion: getVersion(),
    gates,
    checkedAt: new Date().toISOString(),
  }

  if (jsonOnly) {
    process.stdout.write(JSON.stringify(record, null, 2) + '\n')
    process.exit(failing.length === 0 ? 0 : 1)
  }

  const labels = { pass: 'PASS', fail: 'FAIL', skip: 'SKIP' }
  if (!quiet) {
    console.log(`\naahp check - governance gates for ${record.repo} (aahp v${record.aahpVersion})`)
    console.log('=========================================')
  }
  for (const [k, v] of Object.entries(results)) {
    const ok = v.status !== 'fail'
    if (!ok || !quiet) console.log(`  ${(labels[v.status] || v.status).padEnd(6)} ${k}: ${v.reason}`)
  }
  if (!quiet) console.log('=========================================')
  const ranCount = Object.values(gates).filter((s) => s !== 'skip').length
  if (failing.length === 0 && ranCount === 0) {
    // Nothing was examined. 'No failures' is true here and useless: it is the
    // same false green as an unparseable config, reached by a different route.
    console.log('Governance NOT EVALUATED: 0 gate(s) ran. This is not a pass.')
    process.exit(1)
  }
  if (failing.length === 0) {
    if (!quiet) {
      console.log(`Governance OK: ${ranCount} gate(s) ran, no failures.`)
    }
  } else {
    console.log(`Governance FAILED: ${failing.map(([k]) => k).join(', ')}.`)
  }

  process.exit(failing.length === 0 ? 0 : 1)
}

// ---------------------------------------------------------------------------
// criteria command - an ADVISORY report, deliberately not a gate.
//
// Detection over hand-written Markdown is a heuristic, and a heuristic cannot
// be sound: there is always another document shape it does not recognize. A
// gate's whole value is that green means safe, so a heuristic wired to an exit
// code manufactures false confidence and people stop reading the document. This
// command therefore has NO authority. It is absent from CHECK_GATES, it has no
// enforcing mode to switch on, and it exits 0 whether or not it found anything.
// The only non-zero exit is the report failing to run at all (an unparseable
// config, or no git work tree to enumerate files from), which is a property of
// the environment and never of a document's shape.
//
// Output is inherited rather than captured: this is text for a human to read.
// ---------------------------------------------------------------------------

function cmdCriteria(targetPath) {
  const r = spawnSync(process.execPath, [join(PACKAGE_ROOT, 'scripts', 'report-acceptance-criteria.mjs'), targetPath], {
    stdio: 'inherit',
  })
  if (r.error) {
    console.error(`Error running the acceptance-criteria report: ${r.error.message}`)
    process.exit(1)
  }
  process.exit(r.status ?? 1)
}

// Shell script commands -spawn bash scripts
//
// The bash scripts already handle their own argument parsing, including
// the optional [path] first positional argument and all --flags.
// We pass the arguments through directly so the scripts see them unchanged.
// ---------------------------------------------------------------------------

// Path conversion and bash resolution live in scripts/aahp-config.mjs so this
// file and scripts/aahp-dashboard.mjs cannot drift apart. They used to be two
// separate implementations: this one knew about relative paths and the /c/ MSYS
// form but not AAHP_BASH, while the dashboard call site knew neither. The same
// Windows defect then had to be found twice.

function runScript(scriptName, rest) {
  const scriptPath = join(PACKAGE_ROOT, 'scripts', scriptName)

  if (!existsSync(scriptPath)) {
    console.error(`Error: script not found: ${scriptPath}`)
    process.exit(1)
  }

  // Pass all arguments after the subcommand directly to the bash script.
  // On Windows, prefer Git Bash over the WSL bash shim and avoid raw C:\... script arguments.
  // The child spawns with cwd: process.cwd() below, so toBashPath's default cwd
  // is the right one here and must not be overridden.
  const args = [toBashPath(scriptPath), ...rest]
  const bashExecutable = resolveBash()

  const child = spawn(bashExecutable, args, {
    stdio: 'inherit',
    cwd: process.cwd(),
  })

  child.on('error', (err) => {
    if (err.code === 'ENOENT') {
      console.error('Error: bash is not available on this system.')
      console.error('The manifest, lint, migrate, verify, and archive commands require bash.')
      console.error('On Windows, install Git for Windows or WSL.')
    } else {
      console.error(`Error spawning script: ${err.message}`)
    }
    process.exit(1)
  })

  child.on('close', (code) => {
    process.exit(code ?? 0)
  })
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const rawArgs = process.argv.slice(2)

// Handle --version / -v anywhere in args
if (rawArgs.includes('--version') || rawArgs.includes('-v')) {
  console.log(getVersion())
  process.exit(0)
}

// Handle --help / -h anywhere in args, or no arguments at all
if (rawArgs.includes('--help') || rawArgs.includes('-h') || rawArgs.length === 0) {
  printHelp()
  process.exit(0)
}

const command = rawArgs[0]
const rest = rawArgs.slice(1)

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

switch (command) {
  case 'init': {
    const { targetPath, flags } = extractPathAndFlags(rest)
    if (flags.includes('--gates')) cmdInitGates(targetPath, flags)
    else cmdInit(targetPath, flags)
    break
  }

  case 'manifest':
    // Pass all remaining args directly to the bash script
    runScript('aahp-manifest.sh', rest)
    break

  case 'lint':
    runScript('lint-handoff.sh', rest)
    break

  case 'migrate':
    runScript('aahp-migrate-v2.sh', rest)
    break

  case 'migrate-grounding':
    runScript('aahp-migrate-grounding.sh', rest)
    break

  case 'verify':
    runScript('verify-handoff.sh', rest)
    break

  case 'check': {
    const { targetPath, flags } = extractPathAndFlags(rest)
    cmdCheck(targetPath, flags)
    break
  }

  case 'criteria': {
    const { targetPath } = extractPathAndFlags(rest)
    cmdCriteria(targetPath)
    break
  }

  case 'archive':
    runScript('aahp-archive.sh', rest)
    break

  case 'status': {
    const { targetPath } = extractPathAndFlags(rest)
    cmdStatus(targetPath)
    break
  }

  case 'doctor': {
    const { targetPath, flags } = extractPathAndFlags(rest)
    cmdDoctor(targetPath, flags)
    break
  }

  default:
    console.error(`Unknown command: ${command}`)
    console.error('Run "aahp --help" for usage information.')
    process.exit(1)
}
