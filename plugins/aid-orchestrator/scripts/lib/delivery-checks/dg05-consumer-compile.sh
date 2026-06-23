#!/usr/bin/env bash
# dg05-consumer-compile.sh — verify consumers compile after export changes
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — consumer compile command (from policy profile)
# Env:  AID_PROJECT_ROOT — project root directory
#       AID_CHANGED_PATHS — path to file with one changed path per line
#
# Logic:
#   1. Read AID_CHANGED_PATHS. Absent/empty → unverifiable (no change context)
#   2. Check if any changed path is a public export (src/**/*.ts, lib/**/*.ts,
#      index.*, *.d.ts). No match → pass (not applicable to consumers)
#   3. argv provided → run consumer compile command; map exit code
#   4. No argv + applicable changes → unverifiable (profile must specify command)

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
CHANGED_PATHS_FILE="${AID_CHANGED_PATHS:-}"

# ---------------------------------------------------------------------------
# Step 1: Read changed paths
# ---------------------------------------------------------------------------
if [[ -z "$CHANGED_PATHS_FILE" || ! -f "$CHANGED_PATHS_FILE" ]]; then
  echo "dg05: unverifiable — AID_CHANGED_PATHS not set or file not found"
  echo "dg05: cannot determine if public exports changed without changed-paths context"
  exit 2
fi

if [[ ! -s "$CHANGED_PATHS_FILE" ]]; then
  echo "dg05: unverifiable — AID_CHANGED_PATHS file is empty (no changed paths)"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 2: Check applicability — any change to public export files?
# ---------------------------------------------------------------------------
_is_public_export_path() {
  local path="$1"
  case "$path" in
    src/*.ts|src/**/*.ts)           return 0 ;;
    lib/*.ts|lib/**/*.ts)           return 0 ;;
    index.*)                        return 0 ;;
    *.d.ts)                         return 0 ;;
    src/*)
      # catch nested src paths via substring
      [[ "$path" == *.ts ]] && return 0
      ;;
  esac
  return 1
}

applicable=false
while IFS= read -r changed_path; do
  [[ -z "$changed_path" ]] && continue
  if _is_public_export_path "$changed_path"; then
    applicable=true
    echo "dg05: public export change detected: ${changed_path}"
    break
  fi
done < "$CHANGED_PATHS_FILE"

if [[ "$applicable" == "false" ]]; then
  echo "dg05: pass — no changed paths match public export patterns (src/**/*.ts, lib/**/*.ts, index.*, *.d.ts)"
  echo "dg05: consumer compile check not applicable to this change set"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3: argv provided → run consumer compile command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg05: running consumer compile command: $*"
  cc_output=""
  cc_exit=0

  if cc_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg05: consumer compile passed"
    echo "$cc_output"
    exit 0
  else
    cc_exit=$?
    echo "dg05: consumer compile failed (exit ${cc_exit})"
    echo "$cc_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: No argv but applicable → unverifiable
# ---------------------------------------------------------------------------
echo "dg05: unverifiable — public export changes detected but no consumer compile command provided in policy profile"
echo "dg05: configure dg05.cmd in the policy profile to run consumer compilation"
exit 2
