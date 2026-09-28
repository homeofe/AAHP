// aahp-schema.mjs - validate aahp.config.json against schema/aahp-config.schema.json,
// and MANIFEST.json against schema/aahp-manifest.schema.json (used by `aahp doctor`).
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
//   - the `format` branch in validateNode           -> "[ISO-8601]" passes as a date-time
//   - the `$ref` branch in validateNode             -> a malformed files{} entry validates
//
// THE MANIFEST SCHEMA USES MORE KEYWORDS THAN THE CONFIG SCHEMA ($defs, $ref,
// patternProperties, maxLength, format). They are implemented here rather than
// skipped, under the same rule: `format` accepts only the formats listed in
// SUPPORTED_FORMATS and `$ref` only a local "#/$defs/<name>" pointer, and
// anything else throws AAHP_SCHEMA_UNSUPPORTED instead of validating quietly.
// `date-time` mirrors ajv-formats' full mode (RFC 3339), which is what CI runs
// against the same schema; tests/doctor.bats holds the two in lockstep.

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PACKAGE_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

export const CONFIG_SCHEMA_PATH = join(PACKAGE_ROOT, "schema", "aahp-config.schema.json");
export const MANIFEST_SCHEMA_PATH = join(PACKAGE_ROOT, "schema", "aahp-manifest.schema.json");

// Every keyword this validator understands. Annotations carry no assertion and
// are listed so they do not trip assertSupported. `$defs` holds no assertion of
// its own either; its members are walked below and reached through `$ref`.
const ANNOTATIONS = new Set(["$schema", "$id", "$defs", "title", "description", "default", "examples"]);
const ASSERTIONS = new Set([
  "type",
  "properties",
  "patternProperties",
  "additionalProperties",
  "required",
  "items",
  "enum",
  "minimum",
  "minLength",
  "maxLength",
  "pattern",
  "format",
  "$ref",
  "not",
  "anyOf",
]);
const SUPPORTED_KEYWORDS = new Set([...ANNOTATIONS, ...ASSERTIONS]);

// Formats this validator can assert. A schema naming any other format is
// refused, because an unknown format is exactly a keyword that would otherwise
// be skipped silently.
const SUPPORTED_FORMATS = new Set(["date-time"]);

function unsupported(message) {
  const e = new Error(message);
  e.code = "AAHP_SCHEMA_UNSUPPORTED";
  return e;
}

// Resolve a local "#/$defs/<name>" reference against the root schema. Anything
// else (a remote URI, a JSON pointer into some other section) is refused.
function resolveRef(ref, root, pointer) {
  const m = typeof ref === "string" ? /^#\/\$defs\/([^/]+)$/.exec(ref) : null;
  const target = m && root && root.$defs && Object.prototype.hasOwnProperty.call(root.$defs, m[1]) ? root.$defs[m[1]] : undefined;
  if (target === undefined) {
    throw unsupported(
      `schema at ${pointer} uses $ref ${JSON.stringify(ref)}, which this validator cannot resolve ` +
        `(only local "#/$defs/<name>" references are implemented).`,
    );
  }
  return target;
}

// Walk the schema and refuse to run against one that uses a keyword this
// validator does not implement. Without this, an unimplemented keyword would be
// skipped and its documents would be reported valid without ever being checked.
export function assertSupported(schema, pointer = "#", root = schema) {
  if (schema === true || schema === false) return;
  if (schema === null || typeof schema !== "object" || Array.isArray(schema)) {
    throw unsupported(`schema at ${pointer} is not an object`);
  }
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED_KEYWORDS.has(key)) {
      throw unsupported(
        `schema at ${pointer} uses "${key}", which this validator does not implement. ` +
          `Implement it in scripts/aahp-schema.mjs (and add a test) before using it in the schema - ` +
          `a keyword that is silently skipped makes "valid" mean "not fully checked".`,
      );
    }
  }
  if ("format" in schema && !SUPPORTED_FORMATS.has(schema.format)) {
    throw unsupported(
      `schema at ${pointer} uses format ${JSON.stringify(schema.format)}, which this validator does not implement ` +
        `(supported: ${[...SUPPORTED_FORMATS].join(", ")}).`,
    );
  }
  if ("$ref" in schema) resolveRef(schema.$ref, root, pointer);
  if (schema.$defs) {
    for (const [k, sub] of Object.entries(schema.$defs)) assertSupported(sub, `${pointer}/$defs/${k}`, root);
  }
  if (schema.properties) {
    for (const [k, sub] of Object.entries(schema.properties)) assertSupported(sub, `${pointer}/properties/${k}`, root);
  }
  if (schema.patternProperties) {
    for (const [k, sub] of Object.entries(schema.patternProperties)) {
      assertSupported(sub, `${pointer}/patternProperties/${k}`, root);
    }
  }
  if (typeof schema.additionalProperties === "object") {
    assertSupported(schema.additionalProperties, `${pointer}/additionalProperties`, root);
  }
  if (schema.items) assertSupported(schema.items, `${pointer}/items`, root);
  if (schema.not) assertSupported(schema.not, `${pointer}/not`, root);
  if (Array.isArray(schema.anyOf)) {
    schema.anyOf.forEach((sub, i) => assertSupported(sub, `${pointer}/anyOf/${i}`, root));
  }
}

// RFC 3339 date-time, mirroring ajv-formats 3.x in its default ("full") mode:
// a full-date and a full-time with a REQUIRED offset, separated by "T", "t" or
// whitespace; calendar-valid days (leap years included); a leap second only at
// 23:59:60 UTC. Kept deliberately identical to what CI's ajv accepts so the
// doctor gate and `ajv validate` cannot disagree about the same manifest.
const DATE_RE = /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
const TIME_RE = /^(\d\d):(\d\d):(\d\d(?:\.\d+)?)(z|([+-])(\d\d)(?::?(\d\d))?)?$/i;
const DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function isLeapYear(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function isFullDate(str) {
  const m = DATE_RE.exec(str);
  if (!m) return false;
  const year = +m[1];
  const month = +m[2];
  const day = +m[3];
  return month >= 1 && month <= 12 && day >= 1 && day <= (month === 2 && isLeapYear(year) ? 29 : DAYS[month]);
}

function isFullTime(str) {
  const m = TIME_RE.exec(str);
  if (!m) return false;
  const hr = +m[1];
  const min = +m[2];
  const sec = +m[3];
  const tz = m[4];
  const tzSign = m[5] === "-" ? -1 : 1;
  const tzH = +(m[6] || 0);
  const tzM = +(m[7] || 0);
  if (tzH > 23 || tzM > 59 || !tz) return false;
  if (hr <= 23 && min <= 59 && sec < 60) return true;
  // Leap second: only at 23:59 UTC once the offset is applied.
  const utcMin = min - tzM * tzSign;
  const utcHr = hr - tzH * tzSign - (utcMin < 0 ? 1 : 0);
  return (utcHr === 23 || utcHr === -1) && (utcMin === 59 || utcMin === -1) && sec < 61;
}

export function isDateTime(str) {
  const parts = String(str).split(/t|\s/i);
  return parts.length === 2 && isFullDate(parts[0]) && isFullTime(parts[1]);
}

// JSON Schema lengths count Unicode code points, not UTF-16 units.
function codePointLength(str) {
  return [...str].length;
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
// `root` is the document schema, against which `$ref` is resolved.
function validateNode(schema, data, path, errors, root = schema) {
  if (schema === true) return;
  if (schema === false) {
    errors.push({ path, message: "no value is allowed here" });
    return;
  }

  // In draft 2020-12 a $ref applies IN ADDITION to its sibling keywords.
  if ("$ref" in schema) {
    validateNode(resolveRef(schema.$ref, root, path || "#"), data, path, errors, root);
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

  if (typeof schema.maxLength === "number" && typeof data === "string" && codePointLength(data) > schema.maxLength) {
    errors.push({ path, message: `string is longer than the maximum length ${schema.maxLength}` });
  }

  if (typeof schema.pattern === "string" && typeof data === "string") {
    if (!compilePattern(schema.pattern).test(data)) {
      errors.push({ path, message: `${JSON.stringify(data)} does not match ${JSON.stringify(schema.pattern)}` });
    }
  }

  // assertSupported has already refused every format outside SUPPORTED_FORMATS.
  if (schema.format === "date-time" && typeof data === "string" && !isDateTime(data)) {
    const placeholder = /^\[.*\]$/.test(data) ? " (an unreplaced template placeholder)" : "";
    errors.push({
      path,
      message: `${JSON.stringify(data)} is not an RFC 3339 date-time such as "2026-01-31T12:00:00Z"${placeholder}`,
    });
  }

  if (schema.not) {
    const sub = [];
    validateNode(schema.not, data, path, sub, root);
    if (sub.length === 0) {
      errors.push({ path, message: `${JSON.stringify(data)} matches a form this schema forbids` });
    }
  }

  if (Array.isArray(schema.anyOf)) {
    const ok = schema.anyOf.some((s) => {
      const sub = [];
      validateNode(s, data, path, sub, root);
      return sub.length === 0;
    });
    if (!ok) errors.push({ path, message: "matches none of the permitted forms" });
  }

  if (typeOf(data) === "object") {
    const props = schema.properties || {};
    const patternProps = Object.entries(schema.patternProperties || {}).map(([p, sub]) => [compilePattern(p), sub]);
    // A key is "additional" only when neither `properties` nor any
    // `patternProperties` entry claims it (JSON Schema 2020-12 Core, the
    // `additionalProperties` keyword).
    const claimedByPattern = (key) => patternProps.some(([re]) => re.test(key));

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
        if (Object.prototype.hasOwnProperty.call(props, key) || claimedByPattern(key)) continue;
        const hint = suggest(key, known);
        errors.push({
          path,
          message: `unknown key "${key}"${hint ? ` (did you mean "${hint}"?)` : ""}`,
        });
      }
    } else if (typeof schema.additionalProperties === "object") {
      for (const [key, value] of Object.entries(data)) {
        if (Object.prototype.hasOwnProperty.call(props, key) || claimedByPattern(key)) continue;
        validateNode(schema.additionalProperties, value, `${path}/${key}`, errors, root);
      }
    }

    for (const [key, value] of Object.entries(data)) {
      for (const [re, sub] of patternProps) {
        if (re.test(key)) validateNode(sub, value, `${path}/${key}`, errors, root);
      }
    }

    for (const [key, sub] of Object.entries(props)) {
      if (Object.prototype.hasOwnProperty.call(data, key)) {
        validateNode(sub, data[key], `${path}/${key}`, errors, root);
      }
    }
  }

  if (Array.isArray(data) && schema.items) {
    data.forEach((item, i) => validateNode(schema.items, item, `${path}/${i}`, errors, root));
  }
}

// Read a schema shipped in the installed package. A missing or unreadable
// schema is an ERROR, never a pass: the whole point is that this check cannot
// be absent without saying so. `subject` names what could not be validated.
function loadSchemaFile(schemaPath, label, subject, noun) {
  if (!existsSync(schemaPath)) {
    const e = new Error(
      `${label} not found at ${schemaPath}; cannot validate ${subject}. ` +
        `This is an incomplete installation of the aahp package, not a clean ${noun}.`,
    );
    e.code = "AAHP_SCHEMA_MISSING";
    throw e;
  }
  let schema;
  try {
    schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  } catch (err) {
    const e = new Error(`${label} at ${schemaPath} is not valid JSON: ${err.message}`);
    e.code = "AAHP_SCHEMA_MISSING";
    throw e;
  }
  assertSupported(schema);
  return schema;
}

// Read schema/aahp-config.schema.json from the installed package.
export function loadConfigSchema(schemaPath = CONFIG_SCHEMA_PATH) {
  return loadSchemaFile(schemaPath, "config schema", "aahp.config.json", "config");
}

// Validate a parsed config object. Returns an array of {path, message}; empty
// means valid. Throws (AAHP_SCHEMA_MISSING / AAHP_SCHEMA_UNSUPPORTED) when the
// question could not be ASKED, which callers must not treat as a pass.
export function validateConfigObject(config, schemaPath = CONFIG_SCHEMA_PATH) {
  const schema = loadConfigSchema(schemaPath);
  const errors = [];
  validateNode(schema, config, "", errors, schema);
  return errors;
}

// Validate a parsed MANIFEST.json against schema/aahp-manifest.schema.json, the
// whole schema: types, required keys, enums, patterns, lengths and date-time
// formats. Same contract as validateConfigObject: [] means valid, a throw means
// the question could not be asked.
export function validateManifestObject(manifest, schemaPath = MANIFEST_SCHEMA_PATH) {
  const schema = loadSchemaFile(schemaPath, "manifest schema", "MANIFEST.json", "manifest");
  const errors = [];
  validateNode(schema, manifest, "", errors, schema);
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
