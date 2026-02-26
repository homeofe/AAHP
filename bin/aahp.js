#!/usr/bin/env node

// aahp — AI-to-AI Handoff Protocol CLI
// Usage: npx aahp <command> [path] [options]
//
// Commands:
//   init [path]       Initialize .ai/handoff/ directory with AAHP templates
//   manifest [path]   (Re)generate MANIFEST.json from existing handoff files
//   lint [path]       Validate handoff files for safety violations
//   migrate [path]    Migrate an AAHP v1 project to v2/v3
//
// Options:
//   --help, -h        Show this help message
//   --version, -v     Show version number

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'
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
aahp v${version} — AI-to-AI Handoff Protocol CLI

Usage:
  aahp <command> [path] [options]

Commands:
  init [path]       Initialize .ai/handoff/ directory with AAHP templates
  manifest [path]   (Re)generate MANIFEST.json from existing handoff files
  lint [path]       Validate handoff files for safety violations
  migrate [path]    Migrate an AAHP v1 project to v2/v3

Init options:
  --force           Overwrite existing files (default: skip existing)

Manifest options:
  --agent NAME      Agent identifier (default: "cli-tool")
  --session-id ID   Session identifier (default: auto-generated)
  --phase PHASE     Pipeline phase: research|architecture|implementation|review|fix|idle
  --context "TEXT"  Quick context string
  --duration MIN    Session duration in minutes
  --quiet           Suppress output except errors

Global options:
  --help, -h        Show this help message
  --version, -v     Show version number

Examples:
  npx aahp init                    # Initialize in current directory
  npx aahp init ./my-project       # Initialize in a specific project
  npx aahp manifest --phase implementation --agent claude-sonnet
  npx aahp lint ./my-project
  npx aahp migrate
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
      // Extra positional arg — pass through as-is
      flags.push(arg)
    }
  }

  return { targetPath: resolve(targetPath), flags }
}

// ---------------------------------------------------------------------------
// init command — implemented in Node.js
// ---------------------------------------------------------------------------

function cmdInit(targetPath, flags) {
  const force = flags.includes('--force')
  const handoffDir = join(targetPath, '.ai', 'handoff')
  const templatesDir = join(PACKAGE_ROOT, 'templates')

  if (!existsSync(templatesDir)) {
    console.error('Error: templates/ directory not found in the aahp package.')
    console.error(`Expected at: ${templatesDir}`)
    process.exit(1)
  }

  // Create .ai/handoff/ if it does not exist
  if (!existsSync(handoffDir)) {
    mkdirSync(handoffDir, { recursive: true })
    console.log(`Created ${handoffDir}`)
  }

  // Enumerate template files
  const templateFiles = readdirSync(templatesDir)
  let copied = 0
  let skipped = 0

  for (const file of templateFiles) {
    const src = join(templatesDir, file)
    const dest = join(handoffDir, file)

    if (existsSync(dest) && !force) {
      console.log(`  skip: ${file} (already exists, use --force to overwrite)`)
      skipped++
      continue
    }

    copyFileSync(src, dest)
    console.log(`  copy: ${file}`)
    copied++
  }

  console.log()
  console.log(`Done. ${copied} file(s) copied, ${skipped} skipped.`)

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
// Shell script commands — spawn bash scripts
//
// The bash scripts already handle their own argument parsing, including
// the optional [path] first positional argument and all --flags.
// We pass the arguments through directly so the scripts see them unchanged.
// ---------------------------------------------------------------------------

function runScript(scriptName, rest) {
  const scriptPath = join(PACKAGE_ROOT, 'scripts', scriptName)

  if (!existsSync(scriptPath)) {
    console.error(`Error: script not found: ${scriptPath}`)
    process.exit(1)
  }

  // Pass all arguments after the subcommand directly to the bash script
  const args = [scriptPath, ...rest]

  const child = spawn('bash', args, {
    stdio: 'inherit',
    cwd: process.cwd(),
  })

  child.on('error', (err) => {
    if (err.code === 'ENOENT') {
      console.error('Error: bash is not available on this system.')
      console.error('The manifest, lint, and migrate commands require bash.')
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

  default:
    console.error(`Unknown command: ${command}`)
    console.error('Run "aahp --help" for usage information.')
    process.exit(1)
}
