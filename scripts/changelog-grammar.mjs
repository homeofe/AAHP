// changelog-grammar.mjs - The ONE Keep a Changelog release-heading grammar.
//
// This module is the single source of the release-heading grammar. Both the
// format validator (check-changelog-format.mjs) and the LOG release-journal
// generator (aahp-dashboard.mjs) import RELEASE_RE / parseReleases from here, so
// the validator and the generator provably cannot diverge. That divergence is
// exactly the bug the upstreaming spec called out: a hand-duplicated regex where
// the validator accepted a SemVer pre-release suffix the generator silently
// dropped, so a validated "## [1.2.3-rc.1]" entry never reached LOG.md. One
// grammar, imported twice, closes that gap by construction.
//
// Standard: Keep a Changelog 1.1.0 + SemVer. Canonical release heading:
//   ## [X.Y.Z] - YYYY-MM-DD           (no 'v' inside the brackets)
//   ## [X.Y.Z-rc.1] - YYYY-MM-DD      (optional SemVer pre-release suffix)

export const RELEASE_RE = /^## \[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\] - (\d{4}-\d{2}-\d{2})\s*$/;
export const UNRELEASED_RE = /^## \[Unreleased\]\s*$/;
export const SECTIONS = new Set(["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]);
// Reference-link definition at the file foot: "[label]: https://...". Accepts
// http or https (scheme-checked only; the URL body is not validated).
export const REFLINK_RE = /^\[([^\]]+)\]:\s*https?:\/\/\S+$/gm;

// Compare two "X.Y.Z" core versions numerically. Pre-release suffixes are
// ignored for ordering (sufficient for the strictly-descending release check).
export function cmpVersion(a, b) {
  const core = (v) => v.split("-")[0].split(".").map(Number);
  const pa = core(a);
  const pb = core(b);
  for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] - pb[i];
  return 0;
}

// Parse release blocks from a CHANGELOG string using the single RELEASE_RE.
// Returns [{ version, date, line, headline }] newest-first (source order).
// headline = first non-empty body line of the block, stripped of markdown
// emphasis/bullets/code, collapsed whitespace, non-ASCII dropped, pipes escaped,
// capped at 120 chars - ready to drop into a Markdown table cell.
export function parseReleases(changelogText) {
  const lines = changelogText.replace(/^﻿/, "").split(/\r?\n/);
  const heads = [];
  lines.forEach((l, i) => {
    const m = l.match(RELEASE_RE);
    if (m) heads.push({ i, version: m[1], date: m[2] || "" });
  });
  return heads.map((h, k) => {
    const end = k + 1 < heads.length ? heads[k + 1].i : lines.length;
    let headline = (lines.slice(h.i + 1, end).find((l) => l.trim()) || "")
      .replace(/\*\*/g, "") // strip bold markers FIRST so a "**headline**" prefix
      .replace(/^[-*]\s*/, "") // is not mistaken for a leading bullet by this strip
      .replace(/`/g, "");
    headline = headline
      .replace(/\s+/g, " ")
      .replace(/[^\x20-\x7E]/g, "")
      .replace(/\\/g, "\\\\") // escape backslashes FIRST so the pipe-escape below is not incomplete
      .replace(/\|/g, "\\|")
      .trim();
    if (headline.length > 120) headline = headline.slice(0, 117).trimEnd() + "...";
    return { version: h.version, date: h.date, line: h.i + 1, headline };
  });
}
