#!/usr/bin/env node
// aahp-manifest-placeholders.mjs - find, and with --apply remove, task fields in
// MANIFEST.json that still hold an unreplaced TEMPLATE PLACEHOLDER.
//
// WHY THIS EXISTS
// ---------------
// Since `aahp doctor` validates MANIFEST.json against the whole schema, a manifest
// that still carries a placeholder from an earlier template fails doctor after an
// upgrade, although nothing in the repository changed. Two shapes occur in adopter
// manifests: `"created": "[ISO-8601]"`, which templates/MANIFEST.json itself
// shipped for its example tasks until the template stopped carrying `created`, and
// the literal `"created": "YYYY-MM-DDT00:00:00Z"`. `aahp manifest` carries tasks
// over unchanged, so regenerating never clears them. `aahp migrate` runs this
// module to give adopters one explicit fix.
//
// WHAT COUNTS AS A PLACEHOLDER, and why the rule has two halves
// -------------------------------------------------------------
// A task field is reported only when BOTH hold:
//   1. its value has a template placeholder SHAPE, derived from templates/: the
//      whole string is one bracketed token (`[ISO-8601]`, `[model-name]`,
//      `[research|architecture|...]`), or the literal date pattern `YYYY-MM-DD`
//      optionally followed by a time part (`YYYY-MM-DDT00:00:00Z`); and
//   2. schema/aahp-manifest.schema.json REJECTS that value for that field, as
//      decided by the same validator `aahp doctor` runs (scripts/aahp-schema.mjs).
// The second half is what keeps real data out of reach. A free-text field whose
// value happens to be bracketed (`"title": "[WIP] parser"` is not even the shape;
// `"assigned_to": "[unassigned]"` is, and is a valid string) is valid data and is
// never touched: only a value that makes the manifest fail its schema is a
// candidate, so a removal can only ever take a failing manifest closer to valid.
// A value with the shape that the schema accepts is not a problem doctor reports,
// and so not one this module is entitled to fix.
//
// WHAT HAPPENS TO A FINDING
// -------------------------
// The schema decides that too. A field the task schema does not list as `required`
// (created, completed, priority, depends_on, ...) is removed: absent is valid, and a
// placeholder carries no information to keep. A REQUIRED field (title, status)
// cannot be removed without making the task invalid in a different way, and a
// value for it cannot be invented, so the whole run is refused and nothing is
// written; the message names the task and the field to set by hand.
//
// Usage: node scripts/aahp-manifest-placeholders.mjs <path/to/MANIFEST.json> [--apply]
//   without --apply  report only; writes nothing
//   --apply          remove every optional finding, atomically (temp file + rename)
// Exit:  0 nothing blocks (with --apply: the removals, if any, are written)
//        1 a REQUIRED task field holds a placeholder; nothing was written
//        2 the manifest could not be read, parsed or validated; nothing was written
//
// Idempotent: a second --apply finds nothing, because every removed field is gone
// and every refused one stops the run before any write.

import { readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { MANIFEST_SCHEMA_PATH, validateManifestObject } from "./aahp-schema.mjs";

// The two placeholder shapes. Whole-value anchors on purpose: `sha256:[hash]` and
// `[WIP] parser` contain a bracket without being one bracketed token.
const BRACKETED = /^\[[^[\]\r\n]+\]$/;
const LITERAL_DATE = /^YYYY-MM-DD(?:[Tt ][^\r\n]*)?$/;

export function isTemplatePlaceholder(value) {
  return typeof value === "string" && (BRACKETED.test(value) || LITERAL_DATE.test(value));
}

// The task subschema: `required` and `properties` of the single patternProperties
// entry under properties.tasks. Read from the schema file rather than restated
// here, so a field made required (or optional) there changes this module's answer
// with it. A schema of another shape is an error, never an empty answer.
function taskSchema(schemaPath) {
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  const pp = schema && schema.properties && schema.properties.tasks && schema.properties.tasks.patternProperties;
  const subs = pp && typeof pp === "object" ? Object.values(pp) : [];
  if (subs.length !== 1 || !subs[0] || typeof subs[0] !== "object" || typeof subs[0].properties !== "object") {
    throw new Error(`${schemaPath}: properties.tasks.patternProperties does not hold exactly one task schema`);
  }
  return { required: new Set(Array.isArray(subs[0].required) ? subs[0].required : []), properties: subs[0].properties };
}

/**
 * Every task field holding a placeholder the schema rejects.
 * Returns [{ task, field, value, required, problem }]; [] for a manifest with no
 * tasks. Throws when the schema cannot be read or the validator cannot run.
 */
export function findTaskPlaceholders(manifest, schemaPath = MANIFEST_SCHEMA_PATH) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) return [];
  const tasks = manifest.tasks;
  if (!tasks || typeof tasks !== "object" || Array.isArray(tasks)) return [];
  const { required, properties } = taskSchema(schemaPath);

  // Field paths the validator rejects, e.g. "/tasks/T-001/created". A task id
  // matches ^T-\d{3,}$, so it never contains the "/" that separates the parts.
  const rejected = new Map();
  for (const e of validateManifestObject(manifest, schemaPath)) {
    if (!rejected.has(e.path)) rejected.set(e.path, e.message);
  }

  const found = [];
  for (const [id, task] of Object.entries(tasks)) {
    if (!task || typeof task !== "object" || Array.isArray(task)) continue;
    for (const [field, value] of Object.entries(task)) {
      if (!Object.prototype.hasOwnProperty.call(properties, field)) continue;
      if (!isTemplatePlaceholder(value)) continue;
      const problem = rejected.get(`/tasks/${id}/${field}`);
      if (problem === undefined) continue; // the schema accepts it: data, not a leftover
      found.push({ task: id, field, value, required: required.has(field), problem });
    }
  }
  return found;
}

function describe(f) {
  return `${f.task}.${f.field} = ${JSON.stringify(f.value)}`;
}

export function main(argv = process.argv.slice(2)) {
  const apply = argv.includes("--apply");
  const target = argv.find((a) => !a.startsWith("--"));
  if (!target) {
    console.error("Usage: aahp-manifest-placeholders.mjs <path/to/MANIFEST.json> [--apply]");
    return 2;
  }
  const manifestPath = resolve(target);

  let manifest;
  let findings;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    findings = findTaskPlaceholders(manifest);
  } catch (err) {
    console.error(`  -> Could not inspect MANIFEST.json tasks for template placeholders: ${err.message}`);
    console.error("     Nothing was changed by this step.");
    return 2;
  }

  if (findings.length === 0) {
    console.log("  -> No task field holds an unreplaced template placeholder.");
    return 0;
  }

  const blocking = findings.filter((f) => f.required);
  if (blocking.length > 0) {
    console.error("Error: a REQUIRED task field in MANIFEST.json holds an unreplaced template placeholder:");
    for (const f of blocking) {
      console.error(`  - ${describe(f)}: "${f.field}" is required by schema/aahp-manifest.schema.json (${f.problem})`);
    }
    console.error("  A required field cannot be removed, and its value cannot be guessed. Set it by hand in");
    console.error("  .ai/handoff/MANIFEST.json, then run aahp migrate again. Nothing was changed.");
    return 1;
  }

  if (!apply) {
    for (const f of findings) {
      console.log(`  -> ${describe(f)} is an unreplaced template placeholder (optional field: step 1 removes it)`);
    }
    return 0;
  }

  for (const f of findings) delete manifest.tasks[f.task][f.field];
  const rendered = JSON.stringify(manifest, null, 2) + "\n";
  const tmp = join(dirname(manifestPath), `.MANIFEST.json.${process.pid}.placeholders.tmp`);
  try {
    writeFileSync(tmp, rendered);
    renameSync(tmp, manifestPath);
  } catch (err) {
    try {
      unlinkSync(tmp);
    } catch {
      // nothing to clean up
    }
    console.error(`  -> Could not write MANIFEST.json: ${err.message}. Nothing was changed.`);
    return 2;
  }
  for (const f of findings) {
    console.log(`  -> removed ${f.task}.${f.field} (was ${JSON.stringify(f.value)}; an optional field the schema rejects)`);
  }
  return 0;
}

const isMain = process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
if (isMain) process.exit(main());
