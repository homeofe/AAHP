#!/usr/bin/env node
// validate-json-schema.mjs - validate JSON documents against a JSON Schema with
// ajv, the reference implementation, configured the way this repository's CI
// validates MANIFEST.json and aahp.config.json.
//
//   node scripts/validate-json-schema.mjs <schema.json> <data.json> [<data.json> ...]
//
// WHY THIS FILE EXISTS
// ---------------------------------------------------------------------------
// CI used to run `npx --no-install ajv-cli validate --spec=draft2020 -c
// ajv-formats`. ajv-cli 5.0.0 is still its latest release (registry metadata
// last modified 2023-04-28, measured 2026-09-28) and it depends on glob@7.2.3,
// which depends on inflight@1.0.6. npm marks both deprecated, so every `npm ci`
// of this repository printed two deprecation warnings. The CLI also carried 20
// of the 28 locked packages (glob, js-yaml, json5, minimist, fast-json-patch,
// json-schema-migrate and their dependencies), none of which the validation
// needs: with it gone the closure is 8 packages. The library that does the
// validating is `ajv`; this file is the few lines of CLI around it that CI used.
//
// THE CONFIGURATION IS THE ONE THE CLI USED
// ---------------------------------------------------------------------------
// `ajv validate --spec=draft2020 -c ajv-formats` (ajv-cli 5.0.0,
// dist/commands/ajv.js) constructs Ajv2020 with ajv's default options, adds the
// draft-06 meta-schema, and applies ajv-formats with ITS default options. This
// file does exactly that, so:
//   - the dialect is JSON Schema draft 2020-12;
//   - strict mode is ajv's default: strictSchema and strictNumbers are on, so an
//     unknown keyword or an unknown format in the SCHEMA is an error that stops
//     the run, never a keyword that is silently ignored;
//   - formats run in ajv-formats' "full" mode, so a `date-time` must be a real
//     calendar date (2023-02-29 is rejected), which is also what
//     scripts/aahp-schema.mjs mirrors for `aahp doctor`.
// One deliberate difference: `allErrors: true`, so a document with several
// defects lists all of them instead of the first. It changes which errors are
// REPORTED, never the verdict.
//
// createAjv() is exported so tests/doctor.bats compares the in-repo validator
// against THIS configuration, the one CI runs, rather than a second copy of it.
//
// OUTPUT
//   <file> valid                       on stdout, per valid document
//   <file> invalid                     on stderr, per invalid document, followed
//     <instancePath> <message> <params> (schema <schemaPath>)
//                                      one line per error, the fields of ajv's
//                                      error objects that ajv-cli printed
//
// EXIT CODES
//   0  every data file is valid
//   1  at least one data file is invalid - a real finding
//   2  could not evaluate: wrong usage, ajv or ajv-formats not installed, a file
//      that cannot be read or is not JSON, or a schema ajv refuses to compile.
//      Never 0: "I could not look" must not read as "I looked and it was fine".
//
// NOT A RUNTIME DEPENDENCY
// ---------------------------------------------------------------------------
// ajv and ajv-formats are exact devDependencies (ADR-002: the package has no
// `dependencies`). This file ships in the package because scripts/ does, and a
// consumer that wants the same check declares both packages as exact
// devDependencies of its own (README Section 2.1). Without them it exits 2 and
// says which install is missing; it never reaches the network.

import { readFileSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);

/** A condition under which no verdict can be given (exit 2). */
export class CannotRun extends Error {}

/**
 * The ajv instance CI validates with. Throws CannotRun when ajv or ajv-formats
 * cannot be loaded from the node_modules this file resolves against.
 */
export function createAjv() {
  let Ajv2020;
  let addFormats;
  let draft06MetaSchema;
  try {
    Ajv2020 = require("ajv/dist/2020").default;
    addFormats = require("ajv-formats").default;
    draft06MetaSchema = require("ajv/lib/refs/json-schema-draft-06.json");
  } catch (err) {
    if (err?.code === "MODULE_NOT_FOUND") {
      throw new CannotRun(
        `cannot load ajv or ajv-formats (${String(err.message).split("\n")[0]}). ` +
          "In an AAHP checkout both are exact devDependencies: run `npm ci --ignore-scripts` " +
          "first. A project using the installed package declares them itself: " +
          "`npm i -D -E ajv ajv-formats`, commit the lockfile, then `npm ci --ignore-scripts`.",
      );
    }
    throw err;
  }
  const ajv = new Ajv2020({ allErrors: true });
  ajv.addMetaSchema(draft06MetaSchema);
  addFormats(ajv);
  return ajv;
}

/** One ajv error object as one line. */
export function formatError(error) {
  const where = error.instancePath === "" ? "(root)" : error.instancePath;
  return `${where} ${error.message} ${JSON.stringify(error.params)} (schema ${error.schemaPath})`;
}

/** Read and parse a JSON file. Returns { value } or { problem }. */
function readJson(file, role) {
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (err) {
    return { problem: `error: cannot read ${role} ${file} (${err.code ?? err.message})` };
  }
  try {
    // A leading byte-order mark is not JSON, but Node's own JSON loader (which
    // ajv-cli fell back to) strips it, so this does too.
    return { value: JSON.parse(text.charCodeAt(0) === 0xfeff ? text.slice(1) : text) };
  } catch (err) {
    return { problem: `error: ${role} ${file} is not valid JSON (${err.message})` };
  }
}

const USAGE = "usage: node scripts/validate-json-schema.mjs <schema.json> <data.json> [<data.json> ...]";

/** Run the CLI over argv (without node and the script path). Returns the exit code. */
export function main(argv) {
  // No options are accepted. A flag carried over from an ajv-cli invocation
  // (`-s`, `--spec=...`) is refused rather than read as a file name.
  const flag = argv.find((a) => a.startsWith("-"));
  if (argv.length < 2 || flag !== undefined) {
    if (flag !== undefined) console.error(`error: unknown option ${flag}; this command takes file paths only`);
    console.error(USAGE);
    return 2;
  }
  const [schemaFile, ...dataFiles] = argv;

  let ajv;
  try {
    ajv = createAjv();
  } catch (err) {
    if (!(err instanceof CannotRun)) throw err;
    console.error(`error: ${err.message}`);
    return 2;
  }

  const schema = readJson(schemaFile, "schema");
  if (schema.problem) {
    console.error(schema.problem);
    return 2;
  }
  let validate;
  try {
    validate = ajv.compile(schema.value);
  } catch (err) {
    console.error(`schema ${schemaFile} is invalid`);
    console.error(`error: ${err.message}`);
    return 2;
  }

  let invalid = 0;
  let unreadable = 0;
  for (const file of dataFiles) {
    const data = readJson(file, "data file");
    if (data.problem) {
      console.error(data.problem);
      unreadable += 1;
      continue;
    }
    if (validate(data.value)) {
      console.log(`${file} valid`);
    } else {
      invalid += 1;
      console.error(`${file} invalid`);
      for (const error of validate.errors ?? []) console.error(`  ${formatError(error)}`);
    }
  }
  if (unreadable > 0) return 2;
  return invalid > 0 ? 1 : 0;
}

// Run only when executed, not when imported (tests/doctor.bats imports
// createAjv). Compared through realpath so a symlinked or relative invocation
// still counts as "executed". Under `node -e` / `node -p` there is no entry
// file and argv[1] is merely the first argument, which may well be the path of
// this file (tests/validate-json-schema.bats passes it that way), so an eval
// flag means "imported". import.meta.main would say this directly, but Node
// 22.12 does not have it and engines.node admits 22.
function isMain() {
  if (!process.argv[1]) return false;
  if (process.execArgv.some((a) => /^-(?:e|p|pe|ep)$|^--(?:eval|print)(?:=|$)/.test(a))) return false;
  try {
    return realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  process.exitCode = main(process.argv.slice(2));
}
