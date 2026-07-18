#!/usr/bin/env node

// aahp -AI-to-AI Handoff Protocol CLI
// Usage: npx aahp <command> [path] [options]
//
// Commands:
//   init [path]       Initialize .ai/handoff/ directory with AAHP templates
//   manifest [path]   (Re)generate MANIFEST.json from existing handoff files
//   lint [path]       Validate handoff files for safety violations
//   migrate [path]    Migrate an AAHP v1 project to v2/v3
//   migrate-grounding [path]  Add the Grounded Reflection Layer to an existing project
//   verify [path]     Run the canonical handoff gate (checksum + drift + TTL)
//   archive [path]    Rotate or verify LOG.md -> LOG-ARCHIVE.md

//   status [path]     Show a quick state summary from MANIFEST.json
//   doctor [path]     Conformance self-check; emits a JSON conformance record

//
// Options:
//   --help, -h        Show this help message
//   --version, -v     Show version number

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve, relative, isAbsolute } from 'node:path'
import { existsSync, mkdirSync, copyFileSync, readdirSync, readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'

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
  archive [path]    Rotate or verify LOG.md -> LOG-ARCHIVE.md
  status [path]     Show a quick state summary from MANIFEST.json
  doctor [path]     Conformance self-check; emits a JSON conformance record

Init options:
  --force           Overwrite existing files (default: skip existing)
  --with-pii-allowlist  Copy pii-allowlist.json template when needed

Manifest options:
  --agent NAME      Agent identifier (default: "cli-tool")
  --session-id ID   Session identifier (default: auto-generated)
  --phase PHASE     Pipeline phase: research|architecture|implementation|review|fix|idle|documentation
  --context "TEXT"  Quick context string
  --duration MIN    Session duration in minutes
  --quiet           Suppress output except errors

Verify options:
  --level LEVEL     Layers to run: precommit|prepush|full|ci (default: full)
  --quiet           Suppress per-check OK output, keep failures

Doctor options:
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

  const statusPriority = ['ready', 'in_progress', 'blocked', 'done', 'cancelled', 'stale']
  const taskStatusCounts = {
    ready: 0,
    in_progress: 0,
    blocked: 0,
    done: 0,
    cancelled: 0,
    stale: 0,
    other: 0,
  }

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

function firstLine(text) {
  return String(text || '')
    .split('\n')
    .map((l) => l.trim())
    .find((l) => l.length > 0) || 'gate failed'
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

function gateHandoffSet(handoffDir) {
  const manifestPath = join(handoffDir, 'MANIFEST.json')
  if (!existsSync(manifestPath)) return { status: 'fail', reason: 'MANIFEST.json not found' }
  const manifest = readJsonSafe(manifestPath)
  if (!manifest) return { status: 'fail', reason: 'MANIFEST.json is not valid JSON' }
  const canonical = new Set(handoffFileSet())
  const files = manifest.files || {}
  const missing = Object.keys(files).filter((f) => !existsSync(join(handoffDir, f)))
  if (missing.length) return { status: 'fail', reason: `indexed file(s) missing on disk: ${missing.join(', ')}` }
  let entries = []
  try {
    entries = readdirSync(handoffDir)
  } catch {
    // handoff dir unreadable is already covered by the MANIFEST check above
  }
  const strays = entries.filter((f) => /\.(md|json)$/.test(f) && f !== 'MANIFEST.json' && !canonical.has(f))
  if (strays.length) return { status: 'fail', reason: `untracked stray handoff file(s): ${strays.join(', ')}` }
  return { status: 'pass', reason: `${Object.keys(files).length} indexed files present, no strays` }
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

function gatePinnedDep(pkg) {
  if (pkg && pkg.name === '@elvatis_com/aahp') return { status: 'self', reason: 'this repo is the aahp package itself' }
  const dev = (pkg && pkg.devDependencies) || {}
  const reg = (pkg && pkg.dependencies) || {}
  const spec = dev['@elvatis_com/aahp'] !== undefined ? dev['@elvatis_com/aahp'] : reg['@elvatis_com/aahp']
  if (spec === undefined) return { status: 'missing', reason: '@elvatis_com/aahp not pinned in devDependencies' }
  if (/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(spec)) return { status: 'pass', reason: `pinned exact: ${spec}` }
  return { status: 'fail', reason: `not an exact pin: "${spec}" (use an exact version, no range operator)` }
}

function gateChangelogFormat(targetPath) {
  if (!existsSync(join(targetPath, 'CHANGELOG.md'))) return { status: 'skip', reason: 'no CHANGELOG.md' }
  const r = runGate('check-changelog-format.mjs', targetPath)
  if (r.status === 0) return { status: 'pass', reason: 'Keep a Changelog format valid' }
  return { status: 'fail', reason: firstLine(r.stderr || r.stdout) }
}

function gateVersionSync(targetPath) {
  const cfg = readJsonSafe(join(targetPath, 'aahp.config.json'))
  const sites = cfg && Array.isArray(cfg.versionSites) ? cfg.versionSites : []
  if (sites.length === 0) return { status: 'skip', reason: 'no versionSites configured' }
  const r = runGate('check-version-sync.mjs', targetPath)
  if (r.status === 0) return { status: 'pass', reason: `version matches ${sites.length} site(s)` }
  return { status: 'fail', reason: firstLine(r.stderr || r.stdout) }
}

function cmdDoctor(targetPath, flags) {
  const jsonOnly = flags.includes('--json')
  const quiet = flags.includes('--quiet')
  const handoffDir = join(targetPath, '.ai', 'handoff')
  const pkg = readJsonSafe(join(targetPath, 'package.json')) || {}

  const results = {
    'handoff-set': gateHandoffSet(handoffDir),
    'manifest-schema': gateManifestSchema(handoffDir),
    grounding: gateGrounding(handoffDir),
    'pinned-dep': gatePinnedDep(pkg),
    'changelog-format': gateChangelogFormat(targetPath),
    'version-sync': gateVersionSync(targetPath),
  }

  const gates = {}
  for (const [k, v] of Object.entries(results)) gates[k] = v.status

  const record = {
    schemaVersion: 1,
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

// Shell script commands -spawn bash scripts
//
// The bash scripts already handle their own argument parsing, including
// the optional [path] first positional argument and all --flags.
// We pass the arguments through directly so the scripts see them unchanged.
// ---------------------------------------------------------------------------

function toBashScriptArg(scriptPath) {
  if (process.platform !== 'win32') {
    return scriptPath
  }

  const relativePath = relative(process.cwd(), scriptPath)
  if (relativePath && !relativePath.startsWith('..') && !isAbsolute(relativePath)) {
    return relativePath.replace(/\\/g, '/')
  }

  const drivePath = scriptPath.match(/^([A-Za-z]):\\(.*)$/)
  if (drivePath) {
    return `/${drivePath[1].toLowerCase()}/${drivePath[2].replace(/\\/g, '/')}`
  }

  return scriptPath.replace(/\\/g, '/')
}

function findBashExecutable() {
  if (process.platform !== 'win32') {
    return 'bash'
  }

  const candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files\\Git\\usr\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
  ]
  return candidates.find((candidate) => existsSync(candidate)) ?? 'bash'
}

function runScript(scriptName, rest) {
  const scriptPath = join(PACKAGE_ROOT, 'scripts', scriptName)

  if (!existsSync(scriptPath)) {
    console.error(`Error: script not found: ${scriptPath}`)
    process.exit(1)
  }

  // Pass all arguments after the subcommand directly to the bash script.
  // On Windows, prefer Git Bash over the WSL bash shim and avoid raw C:\... script arguments.
  const args = [toBashScriptArg(scriptPath), ...rest]
  const bashExecutable = findBashExecutable()

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
    cmdInit(targetPath, flags)
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
