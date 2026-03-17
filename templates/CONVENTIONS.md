# [PROJECT]: Agent Conventions

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
- i18n/translation keys in camelCase English

## Code Style

<!-- Replace with your project's language/framework conventions -->

- **TypeScript:** strict mode, Zod for I/O validation, Prettier formatting
- **Python:** black + isort, type annotations required
- **Go:** `gofmt`, `golangci-lint`, idiomatic error handling

## Branching & Commits

```
feat/<scope>-<short-name>    → new feature
fix/<scope>-<short-name>     → bug fix
docs/<scope>-<short-name>    → documentation only
refactor/<scope>-<name>      → no behaviour change

Commit format:
  feat(scope): add description [AAHP-auto]
  fix(scope): resolve issue [AAHP-auto]
```

## Architecture Principles

<!-- Document your non-negotiable design rules here -->

- Example: **Zero-Persistence**, no PII written to disk
- Example: **Human-in-the-Loop**, AI assists, humans decide
- Example: **Open Source First**, evaluate OSS before building custom

## Testing

- All new code must have unit tests
- `pnpm test` / `go test ./...` must pass before every commit
- Type-check must pass before every commit

## Formatting

- **No em dashes (`-`)**: Never use Unicode em dashes in any file (code, docs, comments, templates). They break shell scripts, cause encoding errors on Windows (cp1252), and corrupt JSON. Use a regular hyphen (`-`) instead.

## What Agents Must NOT Do

- **Violate the Three Laws** - never cause damage to data, systems, or people; never act beyond delegated scope
- Push directly to `main`
- Install new dependencies without documenting the reason
- Write secrets or credentials into source files
- Delete existing tests (fix or replace instead)
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
