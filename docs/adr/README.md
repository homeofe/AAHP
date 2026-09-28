# Architectural Decision Log

The canonical record of load-bearing decisions: the ones agents keep re-deriving, or
could reverse by accident while "improving" the code. The non-negotiable subset is
indexed in [CONSTITUTION.md](../../CONSTITUTION.md); the protocol itself is specified
in [README.md](../../README.md). Until 2026-09-28 this log was Section 7 of the README.

**One file per decision.** `ADR-NNN.md` holds exactly one decision under the heading
`# ADR-NNN: <title>`. The file is named by the number alone, so correcting a title
never breaks a link, and a reference written as `ADR-NNN` anywhere in the repository
maps to exactly one path.

**Numbers are permanent.** A new decision takes the next free number. An ADR is never
renumbered: when the provenance and doc-path decisions were renumbered to 022 and 023
in the 3.11.0 cycle, references in the templates, the changelog, the tests and a gate
comment kept citing the old numbers until 2026-09-28. A change to a settled
decision is recorded inside its file as a dated **Amended** paragraph, so the original
reasoning stays readable next to the change. `npm run check:adr-refs`
(`scripts/check-adr-refs.mjs`) fails when a tracked file cites an ADR number that has
no file here, or when a file's heading or this index disagrees with the file name. It
cannot tell whether a citation names the RIGHT decision; that stays a review
responsibility.

**Promotion rule:** when a decision recorded in `.ai/handoff/LOG.md` is load-bearing
AND reversible-by-accident, lift its rationale here before `aahp archive` rotates the
LOG entry out of the working set. That is what stops settled decisions from being
re-litigated once they fall out of the default read set.

| ADR | Decision |
|-----|----------|
| [ADR-001](ADR-001.md) | verify is verify-only; regeneration is a separate step |
| [ADR-002](ADR-002.md) | zero runtime dependencies |
| [ADR-003](ADR-003.md) | checksums strip CR (CRLF-agnostic whole-file SHA-256) |
| [ADR-004](ADR-004.md) | LOG.md is an append-only agent journal, not a release journal |
| [ADR-005](ADR-005.md) | the PII allowlist is PII-only and never a verify bypass |
| [ADR-006](ADR-006.md) | TRUST-TTL lives in TRUST.md, not MANIFEST.json |
| [ADR-007](ADR-007.md) | gate severities are fixed (drift blocks, TTL warns, escape hatch is local-only) |
| [ADR-008](ADR-008.md) | aahp_version is independent of the npm version |
| [ADR-009](ADR-009.md) | next_task_id is an unquoted integer and monotonic |
| [ADR-010](ADR-010.md) | CI runs on GitHub-hosted runners only (public repo) |
| [ADR-011](ADR-011.md) | aahp check is the consumer-facing governance aggregator |
| [ADR-012](ADR-012.md) | doctor records conformance, check runs the gates |
| [ADR-013](ADR-013.md) | git hooks resolve the vendored script first, then the local package by PATH |
| [ADR-014](ADR-014.md) | enumerating gates scan git-tracked files and fail loud off-tree |
| [ADR-015](ADR-015.md) | the pinned-dep gate is opt-in and config-driven |
| [ADR-016](ADR-016.md) | aahp-govern.yml is portable, opt-in, and verify-only |
| [ADR-017](ADR-017.md) | a heuristic over hand-written prose is a report, never a gate |
| [ADR-018](ADR-018.md) | Layer 2 exceptions are exact, reviewed, M-only, and CI is base-anchored |
| [ADR-019](ADR-019.md) | one release definition, and publish authorization is machine-asserted |
| [ADR-020](ADR-020.md) | anything AAHP runs or ships declares its permissions and refuses the persisted checkout credential |
| [ADR-021](ADR-021.md) | every action reference is a commit, and an update lane keeps it current |
| [ADR-022](ADR-022.md) | section 2.4 provenance is a convention, and the audit-trail claim is withdrawn |
| [ADR-023](ADR-023.md) | a path a document tells you to copy is a path a gate resolves |
| [ADR-024](ADR-024.md) | trust decay can block, and each repository decides whether it does |
