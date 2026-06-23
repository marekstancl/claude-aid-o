#!/usr/bin/env bash
# dg02-build.sh — run declared build command
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — build command (from policy profile)
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. If argv provided: run it. Non-0 exit → fail. Exit 0 → pass.
#      For workspace builds, root failure = overall failure even if leaves pass.
#   2. No argv: check if package.json has build script → unverifiable
#      (should have been configured in profile command).
#   3. No package.json → unverifiable.

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# argv provided: run the build command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg02: running build command: $*"
  build_output=""
  build_exit=0

  # Run in project root; capture combined stdout+stderr
  if build_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg02: build passed"
    echo "$build_output"
    exit 0
  else
    build_exit=$?
    echo "dg02: build failed (exit ${build_exit})"
    echo "$build_output"
    # Leaf-pass-root-fail: even if individual workspace leaves reported success,
    # the overall command exit code governs. Non-zero = fail.
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# No argv: static inspection for diagnostics
# ---------------------------------------------------------------------------
MANIFEST="${ROOT}/package.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "dg02: unverifiable — no package.json found in ${ROOT}; cannot determine build command"
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "dg02: unverifiable — jq not found; cannot parse package.json"
  exit 2
fi

build_script="$(jq -r '.scripts.build // empty' "$MANIFEST" 2>/dev/null)"

if [[ -n "$build_script" ]]; then
  echo "dg02: unverifiable — package.json has build script '${build_script}' but no build command was provided in the policy profile"
  echo "dg02: configure dg02.cmd in the policy profile to run this check"
else
  echo "dg02: unverifiable — no build script defined in package.json"
fi

exit 2
