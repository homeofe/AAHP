#!/usr/bin/env bash
# run.sh -Run all AAHP bats test suites
#
# Usage:
#   ./tests/run.sh              # Run all tests
#   ./tests/run.sh manifest     # Run only manifest tests
#   ./tests/run.sh lint         # Run only lint tests
#   ./tests/run.sh migrate      # Run only migrate tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use the repository's locked Bats dependency and the same cross-platform Bash
# resolution as `npm test`. This avoids an unpinned global install and prevents
# Windows from selecting the WSL launcher for a Git-Bash-shaped path.
RUNNER="$SCRIPT_DIR/../scripts/run-bats.mjs"

if [ $# -gt 0 ]; then
    # Run a specific test suite
    suite="$1"
    suite_file="$SCRIPT_DIR/${suite}.bats"
    if [ ! -f "$suite_file" ]; then
        echo "Unknown suite: $suite" >&2
        exit 1
    fi
    echo "Running $suite tests..."
    node "$RUNNER" "$suite_file"
else
    # Run all test suites
    echo "Running all AAHP bats tests..."
    echo ""
    node "$RUNNER" "$SCRIPT_DIR"
fi
