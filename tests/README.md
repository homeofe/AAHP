# AAHP test suite

Bats suites for the AAHP scripts and CLI. The rules below exist because each of
them was, at some point, a test in this directory that could not fail. A test
that cannot fail is worse than no test: it looks like cover.

## Running

```bash
npm test                                   # whole suite
node scripts/run-bats.mjs tests/lint.bats  # one file (Linux, macOS, Windows)
node scripts/run-bats.mjs -f "archive" tests/archive.bats
```

`scripts/run-bats.mjs` launches the locked `bats` devDependency with the right
bash on every platform. Use it rather than a global `bats`.

The suite is slow on Windows, where every process costs 0.1 s or more. When
iterating locally, run only the file that covers your change and let CI run the
whole suite.

## Rule 1: no bare `!` before the last line of a test

Bats runs a test body under `set -e`, and bash exempts a command negated with
`!` from `set -e`. A negation that is not the last command of a test (or of a
helper function) can therefore never fail it:

```bash
@test "example" {
    run some-command
    ! grep -q "must be gone" out.txt    # decoration: never fails the test
    [ "$status" -eq 0 ]
}
```

Write the expectation as a status instead:

```bash
    run grep -q "must be gone" out.txt
    [ "$status" -eq 1 ]                 # 1 = no match; 2 (unreadable) is red too
```

`run ! cmd` (with `bats_require_minimum_version 1.5.0`) and `! cmd || false`
also work. `tests/assert-bats-negations.mjs` enforces this over every
`tests/*.bats` and `tests/*.bash` file; it runs in `npm run check`
(`check:bats-negations`) and in `tests/bats-hygiene.bats`.

## Rule 2: bash 4.1 or newer

Before bash 4.1, a failing `[[ ]]` or `(( ))` does not trigger `set -e` either,
unless it is the last command of the test. The bats-core documentation lists
this under its gotchas; macOS `/bin/bash` is 3.2. This suite has hundreds of
`[[ ... ]]` assertions, so on bash 3.2 most of it cannot go red.

Bats runs each test through `#!/usr/bin/env bash`, which means the first `bash`
on `PATH`. `scripts/run-bats.mjs` probes that bash and refuses to run when it is
older than 4.1. On macOS, install a current bash (`brew install bash`) and put
it first on `PATH`. `AAHP_ALLOW_OLD_BASH=1` runs anyway; treat a green result
from such a run as partial.

## Rule 3: a skip on CI is a failure

`[ -n "$tool" ] || skip "tool not installed"` fails open: if the lookup itself
breaks, the test becomes a green skip that asserted nothing. A developer machine
may legitimately lack python or symlink support; the CI runner must not.

- Use `require_tool` from `test_helper.bash` for a prerequisite:

  ```bash
  require_tool "no working python interpreter" [ -n "$py" ]
  ```

  The first argument is the skip reason, the rest is a command that must
  succeed. Without `CI` it skips; with `CI` set (GitHub Actions sets
  `CI=true`) it fails the test.
- `scripts/run-bats.mjs` audits every other skip. With `CI` set it writes a TAP
  report next to the normal output and fails the run on any skip that is not
  listed in `ALLOWED_SKIPS` in that file, by exact test name and reason. Only
  skips that are correct on some platform belong there.

## Rule 4: an assertion script needs a red control

The `tests/assert-*.mjs` scripts check repository shape (gate wiring, parser
parity, CI shape). Each one needs a test that runs it against a copy of the
real files with ONE thing broken and expects a non-zero exit, next to the test
that expects it to pass. Prove the mutation landed (re-read the file) before
asserting on the result. `tests/runtime-support.bats` (release authorization)
and the `red control` tests in `workflow-pinning.bats`, `doc-shape.bats` and
`verify-workflow.bats` show the pattern.

A negative-only assertion (`[[ "$output" != *"finding"* ]]`) passes when the
command crashed before printing anything. Pair it with the exit status and a
positive line that proves the check ran.

## Rule 5: test sources are ASCII; non-ASCII input is generated

Every tracked text file is pure ASCII (`scripts/check-ascii.mjs`, run by
`npm run check`), and that includes this directory. A test that needs a
non-ASCII byte generates it at runtime with an octal escape, so the source stays
ASCII and the behavior under test is unchanged:

```bash
printf 'caf\303\251\n' > "$TEST_TMPDIR/doc.md"   # U+00E9
printf 'a \342\200\224 b\n'                       # U+2014, the em dash
```

In a `node -e` body use a JavaScript escape (`"\u00e9"`, `"\u{1F680}"`). Section
rulers in comments are plain `# --- Title ---`.

## The fixture and git isolation

`setup()` in `test_helper.bash` gives every test its own `TEST_TMPDIR` holding
`.ai/handoff/` and a git repository with one empty `init` commit. The repository
is built once per bats run and copied per test, which saves four git processes
per test (about 0.4 s per test on Windows).

It also isolates git from the machine running the suite:

| Variable | Why |
|----------|-----|
| `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` | a global `core.hooksPath` would receive the hooks `install-hooks.sh` writes; a global `commit.gpgsign` breaks commits; a system config (Git for Windows ships `core.autocrlf`) changes behaviour per machine |
| `GIT_AUTHOR_*`, `GIT_COMMITTER_*` | identity for every repository a test creates |
| `GIT_DIR`, `GIT_INDEX_FILE`, ... unset | set when the suite runs inside a git hook, they would point `git add` at the outer repository |
| `GIT_CEILING_DIRECTORIES` = the temp base | a repository above the temp directory (a dotfiles repo in `$HOME`) is never discovered, so removing `.git` really puts a target outside any work tree |

`GIT_CONFIG_GLOBAL` needs git 2.32 or newer; older git ignores it.
