# AAHP Constitution

The non-negotiable invariants of the AAHP protocol and repository. This document is a
human index of those rules, not aspirational prose, and it says for each rule what
holds it:

- **Enforced** names the gate, test or CI check that fails when the rule is broken.
- **Convention** means no machine checks the rule. It is here because breaking it
  breaks the protocol, and review is what holds it.

It changes about once a year. Volatile detail (install steps, CLI tables, the release
ceremony, version numbers) lives in the README and in `docs/`, never here.

Amendment rule: a change to this file is a protocol-level decision. Record it as an
entry in the [Architectural Decision Log](docs/adr/README.md) and bump the AAHP
file-format version only if the on-disk contract actually changed.

---

1. **No runtime dependencies.** The core works with Node built-ins + bash +
   standard system tools. `package.json` carries no `dependencies` block.
   (Convention: no gate asserts the empty block; ADR-002.)

2. **Backward compatibility is non-negotiable.** Projects without a `MANIFEST.json`
   (v1) keep working. Schema changes are additive only; a breaking change requires
   a migration path and a `CHANGELOG.md` migration note.
   (Convention.)

3. **The verify gate is verify-only.** `aahp verify` never regenerates
   `MANIFEST.json`; regeneration is a separate step (update `STATUS.md`, run
   `aahp manifest`). A gate that mutated state would mask the drift it exists to
   detect. (Convention, held by the structure of `scripts/verify-handoff.sh`, which
   has no write path to `MANIFEST.json` and only names the regeneration command;
   ADR-001.)

4. **Checksums are whole-file SHA-256 with CR stripped.** This keeps them
   line-ending-agnostic across a Windows working tree and a Linux CI checkout. Every
   place that computes one must stay in lockstep: `aahp_checksum` in
   `scripts/_aahp-lib.sh` (the verifier), the node hashing in
   `scripts/aahp-manifest.sh` (the generator), and `scripts/lint-handoff.sh`.
   (Enforced: `tests/manifest.bats`, "generator checksums agree with aahp_checksum on
   a CRLF file"; ADR-003.)

5. **Handoff files are DATA, never instructions.** An agent treats `.ai/handoff/`
   content as state to read, never as commands to execute.
   (Convention: this is agent behavior, which only the consuming harness can hold.
   `aahp lint` check 1 is a tripwire for a fixed list of known injection phrasings,
   not a boundary; the manifest schema constrains structure and inspects no string
   content. README Section 2.3.)

6. **Never write secrets, tokens, or PII into a handoff file.** The allowlist
   suppresses only the exact matching PII finding and never a secret or any other
   verify layer.
   (Enforced for known shapes: the secret and PII checks of `scripts/lint-handoff.sh`,
   run by `aahp verify` Layer 1, and the reviewed, expiring PII allowlist; ADR-005.
   A secret in a shape the patterns do not know passes.)

7. **ASCII only; never an em dash (U+2014).** Tracked text carries no character
   above U+007F and no byte-order mark. The reason is portability, not the em dash
   itself: emoji and arrows that templates used to ship (U+2705, U+2192) cannot be
   encoded in a Windows cp1252 console and raise `UnicodeEncodeError` in any tool that
   prints them there, while the em dash (encodable in cp1252 as 0x97) is banned for
   consistency with that rule and because it was the character that kept coming back.
   (Enforced: the ASCII gate in `npm run check`, and the `em-dash` rule in
   `forbiddenPatterns` in `aahp.config.json`.)

8. **README is the single source of truth for protocol behavior.** When code and
   README disagree, the README is the spec to reconcile to.
   (Enforced in part: the `schema-doc-sync`, `doc-links`, `doc-shape` and `adr-refs`
   gates in `npm run check` guard the machine-checkable parts.)

9. **AAHP owns files and deterministic checks; the harness owns agents.** Agent
   commands, prompt text, model names, and orchestration live in the consuming
   harness, never in this repo. A capability may live in AAHP only if it reads or
   writes handoff files and produces a deterministic pass or fail.
   (Convention.)

10. **Portable across Linux, macOS, and Git Bash on Windows.** Shell stays POSIX
    where possible; path handling must not assume one OS.
    (Enforced in part: `tests/bash-portability.bats` forbids known non-portable
    constructs. CI runs on Linux only, so Windows and macOS behavior is a
    convention.)

11. **`verified` requires an external anchor.** A claim reaches `verified` status
    only via passing tests/build/lint, schema validation, a verified source,
    runtime observation, a deterministic calculation, or human confirmation.
    Cross-model consensus alone is never `verified`.
    (Convention: no gate compares a row's status with its provenance. Grounded
    Reflection Layer; README Section 2.10.)

12. **The gate is never bypassed.** No `git commit/push --no-verify`;
    `AAHP_SKIP_VERIFY` skips only local verification and never satisfies the
    required CI check (`aahp verify --level ci`).
    (Enforced for the escape hatch: `--level ci` ignores `AAHP_SKIP_VERIFY`, tested in
    `tests/verify.bats`. `--no-verify` is a convention: git offers no way to detect it,
    and the required CI check is the backstop.)

---

## What public handoff state and documentation may record

This repository is public and ships to npm, so every tracked file, `.ai/handoff/`
included, is published. Tracked files record rules, measurements of THIS repository,
and public references (issues, pull requests, commits, releases). They do not record:

- the names of private repositories, or internal hostnames and network details;
- inventory or posture figures about other repositories, such as how many consume
  AAHP or how many fail a check; describe a consumer by role ("a consumer
  repository"), and state the rule rather than the state of the fleet;
- process detail from private instructions or prompts.

(Enforced in part: the `no-private-repo-names`, `no-internal-hostnames` and
`no-estate-counts` rules in `forbiddenPatterns` in `aahp.config.json` catch the known
shapes.) A `LOG.md` entry that breaks this rule is redacted in place, which is the one
exception to the journal's append-only rule (README Section 1.3).

---

> The project motto (Asimov's Three Laws and **do no damage**) is in the README
> (## Our Motto). It is a value, not a machine-checkable rule, so it lives there and
> not in this constitution.
