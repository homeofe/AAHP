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

//
// Options:
//   --help, -h        Show this help message
//   --version, -v     Show version number

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve, relative, isAbsolute } from 'node:path'
import { existsSync, mkdirSync, copyFileSync, readdirSync, readFileSync } from 'node:fs'
import { spawn } from 'node:child_process'

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

  default:
    console.error(`Unknown command: ${command}`)
    console.error('Run "aahp --help" for usage information.')
    process.exit(1)
}
