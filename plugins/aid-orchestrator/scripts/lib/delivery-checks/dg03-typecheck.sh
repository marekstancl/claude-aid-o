#!/usr/bin/env bash
# dg03-typecheck.sh — run typecheck
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — typecheck command (from policy profile)
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. Check for .ts files in project root (up to depth 5, excluding node_modules/.git)
#   2. No .ts files → unverifiable (not applicable)
#   3. .ts files exist + argv → run typecheck command; non-0 = fail
#   4. .ts files exist + no argv → unverifiable (profile must specify command)

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Step 1: Detect TypeScript files
# ---------------------------------------------------------------------------
ts_file="$(find "$ROOT" -name "*.ts" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -maxdepth 5 \
  -print -quit 2>/dev/null)"

if [[ -z "$ts_file" ]]; then
  echo "dg03: unverifiable — no TypeScript files found in ${ROOT} (depth ≤5, excluding node_modules)"
  exit 2
fi

echo "dg03: TypeScript files detected (e.g. ${ts_file})"

# ---------------------------------------------------------------------------
# Step 2: argv provided → run typecheck
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg03: running typecheck command: $*"
  tc_output=""
  tc_exit=0

  if tc_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg03: typecheck passed"
    echo "$tc_output"
    exit 0
  else
    tc_exit=$?
    echo "dg03: typecheck failed (exit ${tc_exit})"
    echo "$tc_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: No argv, but .ts files exist → unverifiable
# ---------------------------------------------------------------------------
echo "dg03: unverifiable — TypeScript files found but no typecheck command provided in policy profile"
echo "dg03: configure dg03.cmd in the policy profile to run 'tsc --noEmit' or equivalent"
exit 2
