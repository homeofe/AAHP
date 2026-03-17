# AAHP: Agent Conventions

> Every agent working on this project must read and follow these conventions.
> Update this file whenever a new standard is established.

---

## The Three Laws (Our Motto)

> **First Law:** A robot may not injure a human being or, through inaction, allow a human being to come to harm.
>
> **Second Law:** A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
>
> **Third Law:** A robot must protect its own existence as long as such protection does not conflict with the First or Second Laws.
>
> *- Isaac Asimov*

We are human beings and will remain human beings. Tasks are delegated to AI only when we choose to delegate them. **Do no damage** is the highest rule. Agents must never take autonomous action that could harm data, systems, or people.

---

## Language

- All code, comments, commits, and documentation in **English only**
- Use clear, direct language in handoff files (agents are the primary readers)

## Code Style

- **Bash scripts:** POSIX-compatible where possible, `set -euo pipefail` always
- **JSON:** 2-space indentation, no trailing commas
- **Markdown:** ATX headers, tables with alignment, code blocks with language tags
- Scripts should handle both Linux (`sha256sum`) and macOS (`shasum -a 256`) tools

## Branching & Commits

```
feat/<scope>-<short-name>    → new feature
fix/<scope>-<short-name>     → bug fix
docs/<scope>-<short-name>    → documentation only
refactor/<scope>-<name>      → no behaviour change

Commit format:
  feat(scope): description [AAHP-auto]
  fix(scope): description [AAHP-auto]
  docs(scope): description [AAHP-auto]
```

## File Organization

- `templates/` -Handoff file templates (users copy these to their projects)
- `scripts/` -CLI tools (aahp-manifest.sh, aahp-migrate-v2.sh, lint-handoff.sh)
- `scripts/_aahp-lib.sh` -Shared functions (sourced, not executed directly)
- `schema/` -JSON Schema files for validation
- `.ai/handoff/` -AAHP's own handoff files (dogfooding)

## Architecture Principles

- **Bash-Only Core:** No Node.js or Python required for core tooling
- **Portable:** Scripts must work on Linux, macOS, and Git Bash (Windows)
- **Git-Native:** Everything lives in the repo, recoverable via git history
- **Layered Protocol:** Core files (STATUS, NEXT_ACTIONS, LOG) are mandatory; extended files (DASHBOARD, TRUST, CONVENTIONS, WORKFLOW) are optional

## Testing

- Test scripts manually against a temp `.ai/handoff/` directory before committing
- Validate generated JSON with `python3 -c "import json; json.load(open(...))"` or `jq .`
- Run `lint-handoff.sh` against the project's own `.ai/handoff/` directory

## Formatting

- **No em dashes (`-`)**: Never use Unicode em dashes in any file (code, docs, comments, templates). They break shell scripts, cause encoding errors on Windows (cp1252), and corrupt JSON. Use a regular hyphen (`-`) instead.

## What Agents Must NOT Do

- **Violate the Three Laws** - never cause damage to data, systems, or people; never act beyond delegated scope
- Push directly to `main` without human approval
- Modify template files without updating the corresponding specification in README.md
- Write secrets, credentials, or PII into any handoff file
- Delete existing scripts without providing a replacement
- Break backward compatibility with v1 (MANIFEST.json-less projects must still work)
- Use em dashes (`-`) anywhere in the codebase

---

*This file is maintained by agents and humans together. Update it when conventions evolve.*

---

## 🚨 Release-Regel: Erst fertig, dann publishen (gilt für ALLE Plattformen)

**IMMER erst alles fertigstellen, danach publishen. Kein einziger Commit mehr dazwischen.**
Gilt für GitHub, npm, ClawHub, PyPI — egal ob ein Projekt auf einer oder mehreren Plattformen ist.
Sonst divergieren die Tarballs/Releases zwangsläufig.

### Reihenfolge (nie abweichen)
1. Alle Änderungen + Versionsbumps in **einem einzigen Commit** abschließen
2. `git push` → Plattform 1 (z.B. GitHub)
3. `npm publish` / `clawhub publish` / etc. — alle weiteren Plattformen
4. Kein weiterer Commit bis zum nächsten Release (außer reine interne Doku)

### Vor jedem Release: Alle Versionsstellen prüfen
```bash
grep -rn "X\.Y\.Z\|Current version\|Version:" \
  --include="*.md" --include="*.json" \
  --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.git
```
Typische vergessene Stellen: `README.md` Header, `SKILL.md` Footer, `package.json`,
`openclaw.plugin.json`, `.ai/handoff/STATUS.md` (Header + Plattform-Zeilen), Changelog-Eintrag.

### Secrets & private Pfade — NIEMALS in Repos
- Keine API Keys, Tokens, Passwörter, Secrets in Code oder Docs
- Keine absoluten lokalen Pfade (`/home/user/...`) in publizierten Dateien
- Keine `.env`-Dateien committen — immer in `.gitignore`
- Vor jedem Push: `git diff --staged` auf Secrets prüfen
