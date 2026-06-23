#!/usr/bin/env bash
# dg10-startup-smoke.sh — startup smoke test (built entry point import/start)
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — start command (or node <entry>)
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. argv provided → run it with a 10s timeout
#      - Timeout treated as pass (server successfully started and stayed up)
#      - Non-0 exit → fail
#      - Output containing Error/Cannot find module/ENOENT → fail
#   2. No argv → look for common entry points in $AID_PROJECT_ROOT:
#      dist/index.js, dist/main.js, build/index.js, lib/index.js
#      If found: node --check <entry> (syntax-only check)
#      If not found → unverifiable
#   3. node not in PATH and no entry found → unverifiable

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Helper: check output for error patterns
# ---------------------------------------------------------------------------
_output_has_error() {
  local out="$1"
  # Catch common Node.js startup errors
  if printf '%s\n' "$out" | grep -qE '(^|[[:space:]])(throw |Error:|Cannot find module|SyntaxError:|TypeError:|ReferenceError:|ENOENT:)'; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Step 1: argv provided → run it with timeout
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg10: running startup command: $*"

  cmd_output=""
  cmd_exit=0

  # Use timeout(1) if available, else run directly
  if command -v timeout >/dev/null 2>&1; then
    cmd_output="$(cd "$ROOT" && timeout 10 "$@" 2>&1)" || cmd_exit=$?
    # timeout exits 124 when time limit is hit — treat as successful start
    if [[ "$cmd_exit" -eq 124 ]]; then
      echo "dg10: pass — command hit 10s timeout (server started and remained running)"
      exit 0
    fi
  else
    cmd_output="$(cd "$ROOT" && "$@" 2>&1)" || cmd_exit=$?
  fi

  # Non-0 exit → potential fail, but first check output for startup errors
  if [[ "$cmd_exit" -ne 0 ]] || _output_has_error "$cmd_output"; then
    echo "dg10: fail — startup command indicated an error (exit ${cmd_exit})"
    echo "--- command output ---"
    echo "$cmd_output"
    echo "--- end output ---"
    exit 1
  fi

  echo "dg10: pass — startup command exited 0 without error patterns"
  echo "$cmd_output"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: No argv → look for common entry points
# ---------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "dg10: unverifiable — node not in PATH and no startup command provided"
  echo "dg10: configure dg10.cmd in the policy profile to specify the startup command"
  exit 2
fi

ENTRY_CANDIDATES=(
  "dist/index.js"
  "dist/main.js"
  "build/index.js"
  "lib/index.js"
)

FOUND_ENTRY=""
for candidate in "${ENTRY_CANDIDATES[@]}"; do
  if [[ -f "${ROOT}/${candidate}" ]]; then
    FOUND_ENTRY="${ROOT}/${candidate}"
    echo "dg10: found built entry point: ${candidate}"
    break
  fi
done

if [[ -z "$FOUND_ENTRY" ]]; then
  echo "dg10: unverifiable — no built entry points found in ${ROOT}"
  echo "dg10: searched: ${ENTRY_CANDIDATES[*]}"
  echo "dg10: configure dg10.cmd in the policy profile if the entry point is elsewhere"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 3: Run node --check (syntax check without execution)
# ---------------------------------------------------------------------------
echo "dg10: running: node --check ${FOUND_ENTRY}"
check_output=""
check_exit=0

check_output="$(node --check "$FOUND_ENTRY" 2>&1)" || check_exit=$?

if [[ "$check_exit" -ne 0 ]] || _output_has_error "$check_output"; then
  echo "dg10: fail — node --check failed (exit ${check_exit})"
  echo "--- output ---"
  echo "$check_output"
  echo "--- end output ---"
  exit 1
fi

echo "dg10: pass — node --check passed for ${FOUND_ENTRY#"$ROOT/"}"
exit 0
