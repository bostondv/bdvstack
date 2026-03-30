#!/usr/bin/env bash
# check-quality-gates.sh — Quality verification script.
# Detects available tools in the project and runs all applicable checks.
# Exit 0 if all pass, exit 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source state management
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"

# ---------------------------------------------------------------------------
# Track results
# ---------------------------------------------------------------------------
FAILURES=0
PASSES=0
RESULTS=""

run_check() {
  local name="$1"
  shift
  echo "[quality-gate] Running: ${name}" >&2
  local output
  if output=$("$@" 2>&1); then
    PASSES=$((PASSES + 1))
    RESULTS="${RESULTS}\n  PASS: ${name}"
    echo "[quality-gate] PASS: ${name}" >&2
  else
    FAILURES=$((FAILURES + 1))
    RESULTS="${RESULTS}\n  FAIL: ${name}"
    echo "[quality-gate] FAIL: ${name}" >&2
    echo "$output" >&2
  fi
}

# ---------------------------------------------------------------------------
# Detect and run checks
# ---------------------------------------------------------------------------

# TypeScript
if [[ -f "tsconfig.json" ]]; then
  run_check "TypeScript (tsc)" npx tsc --noEmit
fi

# ESLint
if ls .eslintrc* eslint.config.* 2>/dev/null | grep -q . || \
   ([ -f "package.json" ] && grep -q '"eslintConfig"' package.json 2>/dev/null); then
  run_check "ESLint" npx eslint .
fi

# Prettier
if ls .prettierrc* prettier.config.* 2>/dev/null | grep -q .; then
  run_check "Prettier" npx prettier --check .
fi

# Jest
if ls jest.config* 2>/dev/null | grep -q .; then
  run_check "Jest" npx jest --passWithNoTests
fi

# Vitest
if ls vitest.config* 2>/dev/null | grep -q .; then
  run_check "Vitest" npx vitest run
fi

# Pytest
if [[ -f "pytest.ini" ]] || [[ -f "conftest.py" ]]; then
  run_check "Pytest" pytest
fi

# RSpec
if [[ -f ".rspec" ]] || [[ -d "spec" ]]; then
  if [[ -f "Gemfile" ]]; then
    run_check "RSpec" bundle exec rspec
  fi
fi

# Go
if [[ -f "go.mod" ]]; then
  run_check "Go test" go test ./...
  run_check "Go vet" go vet ./...
fi

# Rust
if [[ -f "Cargo.toml" ]]; then
  run_check "Cargo test" cargo test
  run_check "Cargo clippy" cargo clippy -- -D warnings
fi

# Rubocop
if [[ -f "Gemfile" ]] && grep -q 'rubocop' Gemfile 2>/dev/null; then
  run_check "RuboCop" bundle exec rubocop
fi

# Ruff (Python)
if [[ -f "pyproject.toml" ]] && grep -q 'ruff' pyproject.toml 2>/dev/null; then
  run_check "Ruff" ruff check .
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASSES + FAILURES))

if [[ $TOTAL -eq 0 ]]; then
  echo "No quality gates detected in this project."
  exit 0
fi

echo ""
echo "Quality Gates Summary: ${PASSES}/${TOTAL} passed"
printf '%b\n' "$RESULTS"
echo ""

# Update state if in an active session
SESSION_ID="$(get_active_session_id)" || true
if [[ -n "$SESSION_ID" ]]; then
  if [[ $FAILURES -gt 0 ]]; then
    # Save failure output for FIX phase
    printf '%b\n' "$RESULTS" > "$(get_session_dir "$SESSION_ID")/quality-gate-results.txt"
  fi
fi

if [[ $FAILURES -gt 0 ]]; then
  echo "RESULT: FAIL (${FAILURES} check(s) failed)"
  exit 1
else
  echo "RESULT: PASS (all ${TOTAL} check(s) passed)"
  exit 0
fi
