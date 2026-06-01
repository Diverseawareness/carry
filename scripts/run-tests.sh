#!/usr/bin/env bash
# run-tests.sh
#
# Runs the CarryTests unit suite. Single source of truth for "run the tests"
# — invoked by the pre-push hook (scripts/pre-push) locally, and callable
# verbatim by CI later (a GitHub Actions macOS job would just run this).
#
# Usage:
#   ./scripts/run-tests.sh             # run the full suite
#   ./scripts/run-tests.sh --quiet     # suppress xcodebuild noise, print only result
#
# Exit codes:
#   0  all tests passed
#   1  one or more tests failed (or the build/test command errored)
#
# Notes:
#   - Uses the "Carry" scheme (the "Carry dev" scheme is NOT configured for the
#     test action — only "Carry" carries the CarryTests TestableReference).
#   - -enableCodeCoverage NO works around the PLCrashReporter linker bug
#     (Undefined symbol ___llvm_profile_runtime with coverage on). See MEMORY.
#   - Picks the first available booted-or-shutdown iPhone simulator so this
#     doesn't hard-code a device name that may not exist on every machine.
#   - Date.now()/Math.random() etc. are irrelevant here; this is a plain shell
#     wrapper around xcodebuild.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

SCHEME="Carry"

# Pick an available iPhone simulator by name (newest-listed first). Falls back
# to a generic destination if none is found (xcodebuild will still resolve it).
SIM_NAME="$(xcrun simctl list devices available 2>/dev/null \
  | grep -oE 'iPhone [0-9]+[^(]*' \
  | head -1 \
  | sed 's/[[:space:]]*$//')"

if [[ -n "$SIM_NAME" ]]; then
  DEST="platform=iOS Simulator,name=$SIM_NAME"
else
  DEST="generic/platform=iOS Simulator"
fi

echo "▶︎ Running CarryTests on: ${SIM_NAME:-generic simulator}"

# Run. Capture output so --quiet can summarize; stream otherwise.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if [[ "$QUIET" == "1" ]]; then
  if xcodebuild test \
      -scheme "$SCHEME" \
      -destination "$DEST" \
      -enableCodeCoverage NO \
      >"$LOG" 2>&1; then
    PASSED=1
  else
    PASSED=0
  fi
else
  if xcodebuild test \
      -scheme "$SCHEME" \
      -destination "$DEST" \
      -enableCodeCoverage NO \
      2>&1 | tee "$LOG" | grep -E "Test case.*(passed|failed)|Executed|TEST (SUCCEEDED|FAILED)"; then
    :
  fi
  # PIPESTATUS[0] is xcodebuild's real exit code (grep's would mask it).
  PASSED=$([[ "${PIPESTATUS[0]:-1}" == "0" ]] && echo 1 || echo 0)
fi

echo ""
if [[ "$PASSED" == "1" ]]; then
  echo "✅ All tests passed."
  exit 0
else
  echo "❌ Tests FAILED. Failing cases:"
  grep -E "Test case.*failed" "$LOG" | sed 's/^/   /' || true
  echo ""
  echo "Full log was at: $LOG (deleted on exit; re-run without --quiet to stream)."
  exit 1
fi
