// aahp-schema.mjs - validate aahp.config.json against schema/aahp-config.schema.json.
//
// WHY THIS EXISTS
// ---------------
// aahp.config.json is the file through which an adopter turns gates ON. Nothing
// validated it, so a key misspelled by one letter was indistinguishable from a
// key that was never written: `gateApplies` in bin/aahp.js decides applicability
// from the PRESENCE of a config key, an absent key is "not applicable", and "not
// applicable" is a clean skip. One dropped letter therefore turned a FAILING
// gate into `Governance OK`, exit 0. This is the gate over the gates: if the
// config can be malformed unnoticed, every gate it declares is optional in
// practice.
//
// WHY IT IS HAND-WRITTEN
// ----------------------
// ADR-002: the core runs on Node built-ins only, `package.json` has no
// `dependencies`, and a gate must not need a network install at gate time. AJV
// is a devDependency used by CI; it is not available inside a consumer's
// installed copy of this package. So this module implements the SUBSET of JSON
// Schema that schema/aahp-config.schema.json actually uses.
//
// WHY A SUBSET IS SAFE HERE, AND THE ONE RULE THAT MAKES IT SO
// ------------------------------------------------------------
// A partial validator that silently ignores the keywords it does not implement
// is worse than no validator: it reports "valid" for a document it never fully
// examined, which is the exact failure class this module was written to close.
// So `assertSupported` walks the SCHEMA first and THROWS on any keyword outside
// SUPPORTED_KEYWORDS. Adding an unimplemented keyword to the schema turns the
// validator loud, never quiet. "Could not evaluate" is a distinct, non-zero
// outcome here - never a pass.
//
// MUTATION ANCHORS (delete one line, one test goes red):
//   - the `throw` inside assertSupported            -> unsupported keywords pass silently
//   - the `additionalProperties === false` branch   -> a misspelled key validates
//   - the `required` loop                           -> a rule with no `pattern` validates

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PACKAGE_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

export const CONFIG_SCHEMA_PATH = join(PACKAGE_ROOT, "schema", "aahp-config.schema.json");

// Every keyword this validator understands. Annotations carry no assertion and
// are listed so they do not trip assertSupported.
const ANNOTATIONS = new Set(["$schema", "$id", "title", "description", "default", "examples"]);
const ASSERTIONS = new Set([
  "type",
  "properties",
  "additionalProperties",
  "required",
  "items",
  "enum",
  "minimum",
  "minLength",
  "pattern",
  "not",
  "anyOf",
]);
const SUPPORTED_KEYWORDS = new Set([...ANNOTATIONS, ...ASSERTIONS]);

// Walk the schema and refuse to run against one that uses a keyword this
// validator does not implement. Without this, an unimplemented keyword would be
// skipped and its documents would be reported valid without ever being checked.
export function assertSupported(schema, pointer = "#") {
  if (schema === true || schema === false) return;
  if (schema === null || typeof schema !== "object" || Array.isArray(schema)) {
    const e = new Error(`schema at ${pointer} is not an object`);
    e.code = "AAHP_SCHEMA_UNSUPPORTED";
    throw e;
  }
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED_KEYWORDS.has(key)) {
      const e = new Error(
        `schema at ${pointer} uses "${key}", which this validator does not implement. ` +
          `Implement it in scripts/aahp-schema.mjs (and add a test) before using it in the schema - ` +
          `a keyword that is silently skipped makes "valid" mean "not fully checked".`,
      );
      e.code = "AAHP_SCHEMA_UNSUPPORTED";
      throw e;
    }
  }
  if (schema.properties) {
    for (const [k, sub] of Object.entries(schema.properties)) assertSupported(sub, `${pointer}/properties/${k}`);
  }
  if (typeof schema.additionalProperties === "object") {
    assertSupported(schema.additionalProperties, `${pointer}/additionalProperties`);
  }
  if (schema.items) assertSupported(schema.items, `${pointer}/items`);
  if (schema.not) assertSupported(schema.not, `${pointer}/not`);
  if (Array.isArray(schema.anyOf)) {
    schema.anyOf.forEach((sub, i) => assertSupported(sub, `${pointer}/anyOf/${i}`));
  }
}

// Levenshtein distance, iterative, two rows. Only ever run over short key names.
function distance(a, b) {
  if (a === b) return 0;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

// Closest known key, when one is close enough to be worth printing. The
// threshold scales with the key length so "check" does not get suggested for an
// unrelated three-letter key.
function suggest(unknown, known) {
  let best = null;
  let bestDist = Infinity;
  for (const k of known) {
    const d = distance(unknown.toLowerCase(), k.toLowerCase());
    if (d < bestDist) {
      bestDist = d;
      best = k;
    }
  }
  const limit = Math.max(1, Math.min(3, Math.floor(unknown.length / 3)));
  return best !== null && bestDist <= limit ? best : null;
}

// Compile a JSON Schema `pattern`. The config schema uses Unicode property
// escapes (\p{L}), which JS only accepts with the `u` flag, while other
// patterns may use escapes that `u` rejects. Try `u` first, fall back.
function compilePattern(source) {
  try {
    return new RegExp(source, "u");
  } catch {
    return new RegExp(source);
  }
}

function typeOf(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function typeMatches(expected, value) {
  switch (expected) {
    case "object":
      return typeOf(value) === "object";
    case "array":
      return Array.isArray(value);
    case "string":
      return typeof value === "string";
    case "boolean":
      return typeof value === "boolean";
    case "integer":
      return typeof value === "number" && Number.isInteger(value);
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "null":
      return value === null;
    default:
      return true;
  }
}

// Validate `data` against `schema`, appending {path, message} to `errors`.
// `path` is a JSON-Pointer-ish location an adopter can find in their file.
function validateNode(schema, data, path, errors) {
  if (schema === true) return;
  if (schema === false) {
    errors.push({ path, message: "no value is allowed here" });
    return;
  }

  if (typeof schema.type === "string" && !typeMatches(schema.type, data)) {
    errors.push({ path, message: `expected ${schema.type}, got ${typeOf(data)}` });
    return; // every further assertion would just restate the type error
  }

  if (Array.isArray(schema.enum) && !schema.enum.some((v) => v === data)) {
    errors.push({
      path,
      message: `${JSON.stringify(data)} is not one of ${schema.enum.map((v) => JSON.stringify(v)).join(", ")}`,
    });
  }

  if (typeof schema.minimum === "number" && typeof data === "number" && data < schema.minimum) {
    errors.push({ path, message: `${data} is below the minimum ${schema.minimum}` });
  }

  if (typeof schema.minLength === "number" && typeof data === "string" && data.length < schema.minLength) {
    errors.push({ path, message: `string is shorter than the minimum length ${schema.minLength}` });
  }

  if (typeof schema.pattern === "string" && typeof data === "string") {
    if (!compilePattern(schema.pattern).test(data)) {
      errors.push({ path, message: `${JSON.stringify(data)} does not match ${JSON.stringify(schema.pattern)}` });
    }
  }

  if (schema.not) {
    const sub = [];
    validateNode(schema.not, data, path, sub);
    if (sub.length === 0) {
      errors.push({ path, message: `${JSON.stringify(data)} matches a form this schema forbids` });
    }
  }

  if (Array.isArray(schema.anyOf)) {
    const ok = schema.anyOf.some((s) => {
      const sub = [];
      validateNode(s, data, path, sub);
      return sub.length === 0;
    });
    if (!ok) errors.push({ path, message: "matches none of the permitted forms" });
  }

  if (typeOf(data) === "object") {
    const props = schema.properties || {};

    if (Array.isArray(schema.required)) {
      for (const key of schema.required) {
        if (!Object.prototype.hasOwnProperty.call(data, key)) {
          errors.push({ path, message: `missing required key "${key}"` });
        }
      }
    }

    if (schema.additionalProperties === false) {
      const known = Object.keys(props);
      for (const key of Object.keys(data)) {
        if (Object.prototype.hasOwnProperty.call(props, key)) continue;
        const hint = suggest(key, known);
        errors.push({
          path,
          message: `unknown key "${key}"${hint ? ` (did you mean "${hint}"?)` : ""}`,
        });
      }
    } else if (typeof schema.additionalProperties === "object") {
      for (const [key, value] of Object.entries(data)) {
        if (Object.prototype.hasOwnProperty.call(props, key)) continue;
        validateNode(schema.additionalProperties, value, `${path}/${key}`, errors);
      }
    }

    for (const [key, sub] of Object.entries(props)) {
      if (Object.prototype.hasOwnProperty.call(data, key)) {
        validateNode(sub, data[key], `${path}/${key}`, errors);
      }
    }
  }

  if (Array.isArray(data) && schema.items) {
    data.forEach((item, i) => validateNode(schema.items, item, `${path}/${i}`, errors));
  }
}

// Read schema/aahp-config.schema.json from the installed package. A missing or
// unreadable schema is an ERROR, never a pass: the whole point is that this
// check cannot be absent without saying so.
export function loadConfigSchema(schemaPath = CONFIG_SCHEMA_PATH) {
  if (!existsSync(schemaPath)) {
    const e = new Error(
      `config schema not found at ${schemaPath}; cannot validate aahp.config.json. ` +
        `This is an incomplete installation of the aahp package, not a clean config.`,
    );
    e.code = "AAHP_SCHEMA_MISSING";
    throw e;
  }
  let schema;
  try {
    schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  } catch (err) {
    const e = new Error(`config schema at ${schemaPath} is not valid JSON: ${err.message}`);
    e.code = "AAHP_SCHEMA_MISSING";
    throw e;
  }
  assertSupported(schema);
  return schema;
}

// Validate a parsed config object. Returns an array of {path, message}; empty
// means valid. Throws (AAHP_SCHEMA_MISSING / AAHP_SCHEMA_UNSUPPORTED) when the
// question could not be ASKED, which callers must not treat as a pass.
export function validateConfigObject(config, schemaPath = CONFIG_SCHEMA_PATH) {
  const schema = loadConfigSchema(schemaPath);
  const errors = [];
  validateNode(schema, config, "", errors);
  return errors;
}

// One human-readable block, stable enough for a test to match on.
export function formatConfigErrors(errors, file = "aahp.config.json") {
  const lines = [`${file} does not match schema/aahp-config.schema.json (${errors.length} problem(s)):`];
  for (const e of errors) lines.push(`  - ${e.path === "" ? "(root)" : e.path}: ${e.message}`);
  lines.push(
    "A gate whose config key is misspelled reports SKIP, not FAIL, so this would otherwise have been reported as passing.",
  );
  return lines.join("\n");
}
