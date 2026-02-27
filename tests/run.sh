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

# Detect bats: prefer local npx, fall back to global
if command -v bats &>/dev/null; then
    BATS="bats"
elif command -v npx &>/dev/null; then
    BATS="npx bats"
else
    echo "Error: bats not found. Install with: npm install -g bats" >&2
    echo "  Or:  brew install bats-core" >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    # Run a specific test suite
    suite="$1"
    case "$suite" in
        manifest|lint|migrate)
            echo "Running $suite tests..."
            $BATS "$SCRIPT_DIR/${suite}.bats"
            ;;
        *)
            echo "Unknown suite: $suite" >&2
            echo "Available: manifest, lint, migrate" >&2
            exit 1
            ;;
    esac
else
    # Run all test suites
    echo "Running all AAHP bats tests..."
    echo ""
    $BATS "$SCRIPT_DIR"/*.bats
fi
