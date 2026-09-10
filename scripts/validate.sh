#!/usr/bin/env bash
# TetraVim test suite orchestrator
# Runs the native Plenary busted test suite across lua/tetravim/tests/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== TetraVim Test Suite Orchestrator ==="

TMP_LOG="$(mktemp)"
trap 'rm -f "$TMP_LOG"' EXIT

echo "Running Plenary busted test suite..."
nvim --headless -u init.lua \
  -c "Lazy! load plenary.nvim" \
  -c "PlenaryBustedDirectory lua/tetravim/tests/" \
  -c "qa" 2>&1 | sed -r 's/\x1b\[[0-9;]*m//g' | tee "$TMP_LOG"

if grep -Eq '^(Failed|Errors) :[[:space:]]+[1-9]' "$TMP_LOG"; then
  echo "✖ Plenary busted reported test failures."
  exit 1
fi

if ! grep -Eq '^Success:?[[:space:]]' "$TMP_LOG"; then
  echo "✖ Plenary busted produced no summary -- the suite did not run."
  exit 1
fi

echo "✔ All tests passed successfully."

