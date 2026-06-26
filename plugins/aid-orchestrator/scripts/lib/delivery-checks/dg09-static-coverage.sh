#!/usr/bin/env bash
# dg09-static-coverage.sh — typecheck/lint coverage integrity (vacuous shim detector)
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — typecheck/lint command to run and inspect
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. No argv → unverifiable (no command to check)
#   2. Run argv command; capture stdout+stderr
#   3. Command exits non-0 → fail
#   4. Command exits 0 but output shows vacuous patterns → unverifiable
#      Vacuous: "0 files checked", "0 errors (0 warnings)", "Files: 0", etc.
#      with no evidence that any files were processed
#   5. Command exits 0 AND output shows files processed → pass
#   6. Command exits 0 with no output at all → unverifiable

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Step 1: No argv → unverifiable
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  echo "dg09: unverifiable — no command provided"
  echo "dg09: configure dg09.cmd in the policy profile to specify the typecheck/lint command"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 2: Run the command; capture output
# ---------------------------------------------------------------------------
echo "dg09: running command: $*"
cmd_output=""
cmd_exit=0

cmd_output="$(cd "$ROOT" && "$@" 2>&1)" || cmd_exit=$?

# ---------------------------------------------------------------------------
# Step 3: Command exits non-0 → fail
# ---------------------------------------------------------------------------
if [[ "$cmd_exit" -ne 0 ]]; then
  echo "dg09: fail — command exited ${cmd_exit} (typecheck/lint errors)"
  echo "$cmd_output"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Command exits 0 — inspect output for vacuous patterns
# ---------------------------------------------------------------------------

# Helper: returns 0 (true) if output is vacuous
_is_vacuous() {
  local out="$1"

  # No output at all → vacuous
  if [[ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]]; then
    return 0
  fi

  # TypeScript: "Files: 0" line (tsc --noEmit diagnostics)
  if printf '%s\n' "$out" | grep -qiE '^[[:space:]]*Files:[[:space:]]*0[[:space:]]*$'; then
    return 0
  fi

  # ESLint: "0 problems", "0 files checked"
  if printf '%s\n' "$out" | grep -qiE '0[[:space:]]+(problems?|files?[[:space:]]+checked)'; then
    return 0
  fi

  # Generic: "no files", "nothing to check", "Linting 0 files"
  if printf '%s\n' "$out" | grep -qiE '(linting|checking|processing)[[:space:]]+0[[:space:]]+files?'; then
    return 0
  fi
  if printf '%s\n' "$out" | grep -qiE '(no files|nothing to (check|lint|type[- ]?check))'; then
    return 0
  fi

  # "0 errors, 0 warnings" with no file mention → vacuous
  # But only flag if there's no file path mentioned (heuristic: no path separators)
  if printf '%s\n' "$out" | grep -qiE '0[[:space:]]+errors?[,[:space:]]+(0[[:space:]]+warnings?)?'; then
    # Check if any file paths appear (lines with / or \)
    if ! printf '%s\n' "$out" | grep -qE '([a-zA-Z0-9_./\\-]+\.(ts|js|tsx|jsx|mjs|cjs))'; then
      return 0
    fi
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Step 5: Check output and decide
# ---------------------------------------------------------------------------
if _is_vacuous "$cmd_output"; then
  echo "dg09: unverifiable — command exited 0 but output shows vacuous check (0 files processed)"
  echo "--- command output ---"
  echo "$cmd_output"
  echo "--- end output ---"
  echo "dg09: this likely means the typecheck/lint command is a shim or has no included files"
  exit 2
fi

# Command passed and output shows real work done
echo "dg09: pass — command exited 0 with file-processing evidence"
echo "$cmd_output"
exit 0
