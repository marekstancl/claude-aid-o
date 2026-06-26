#!/usr/bin/env bash
# dg01-dependency-consistency.sh — manifest/lock agreement check
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — project's consistency check command (from policy profile)
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. If argv provided: run it; non-0 exit → fail
#   2. Static check: package.json + lockfile present → verify deps appear in lockfile
#   3. package.json without lockfile → fail (lockfile required when manifest exists)
#   4. No package.json → unverifiable
#
# Both argv command and static check are evaluated independently;
# fail from either → overall fail.

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
STATIC_RESULT=0   # 0=pass/na, 1=fail, 2=unverifiable
CMD_RESULT=0      # 0=pass/na, 1=fail

# ---------------------------------------------------------------------------
# Step 1: Run argv command if provided
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg01: running command: $*"
  if "$@"; then
    echo "dg01: command passed"
    CMD_RESULT=0
  else
    echo "dg01: command failed (exit $?)"
    CMD_RESULT=1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Static JSON comparison of package.json vs lockfile
# ---------------------------------------------------------------------------

MANIFEST="${ROOT}/package.json"
LOCKFILE=""

if [[ -f "${ROOT}/package-lock.json" ]]; then
  LOCKFILE="${ROOT}/package-lock.json"
elif [[ -f "${ROOT}/yarn.lock" ]]; then
  LOCKFILE="${ROOT}/yarn.lock"
elif [[ -f "${ROOT}/pnpm-lock.yaml" ]]; then
  LOCKFILE="${ROOT}/pnpm-lock.yaml"
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "dg01: no package.json found in ${ROOT}"
  if [[ "$CMD_RESULT" -eq 1 ]]; then
    echo "dg01: fail (command failed)"
    exit 1
  fi
  echo "dg01: unverifiable (no package.json)"
  STATIC_RESULT=2
else
  # package.json exists
  if [[ -z "$LOCKFILE" ]]; then
    echo "dg01: fail — package.json exists but no lockfile found (package-lock.json / yarn.lock / pnpm-lock.yaml)"
    STATIC_RESULT=1
  else
    # Check that jq is available for static analysis
    if ! command -v jq >/dev/null 2>&1; then
      echo "dg01: warn — jq not found; skipping static manifest/lock comparison"
      STATIC_RESULT=2
    elif [[ "$LOCKFILE" == "${ROOT}/package-lock.json" ]]; then
      # npm lockfile v2/v3: has .packages key
      # Extract all declared deps from package.json
      MISSING_DEPS=()
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        # Check presence in lockfile .packages (v2/v3 format)
        if ! jq -e --arg dep "node_modules/${dep}" '.packages | has($dep)' "$LOCKFILE" >/dev/null 2>&1; then
          # Fallback: check .dependencies key (v1 format)
          if ! jq -e --arg dep "$dep" '.dependencies | has($dep)' "$LOCKFILE" >/dev/null 2>&1; then
            MISSING_DEPS+=("$dep")
          fi
        fi
      done < <(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$MANIFEST" 2>/dev/null)

      if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
        echo "dg01: fail — ${#MISSING_DEPS[@]} dependency/dependencies in package.json missing from lockfile:"
        for dep in "${MISSING_DEPS[@]}"; do
          echo "  - ${dep}  (package.json:dependencies/devDependencies)"
        done
        STATIC_RESULT=1
      else
        echo "dg01: pass — all package.json dependencies found in lockfile"
        STATIC_RESULT=0
      fi
    elif [[ "$LOCKFILE" == "${ROOT}/pnpm-lock.yaml" ]]; then
      # pnpm lockfile: use yq if available
      if ! command -v yq >/dev/null 2>&1; then
        echo "dg01: warn — yq not found; cannot parse pnpm-lock.yaml statically"
        STATIC_RESULT=2
      else
        MISSING_DEPS=()
        while IFS= read -r dep; do
          [[ -z "$dep" ]] && continue
          if ! yq e ".packages | has(\"/${dep}@\")" "$LOCKFILE" 2>/dev/null | grep -q "true"; then
            # Accept if any key starts with the package name
            if ! yq e '.packages | keys | .[]' "$LOCKFILE" 2>/dev/null | grep -q "^/${dep}@"; then
              MISSING_DEPS+=("$dep")
            fi
          fi
        done < <(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$MANIFEST" 2>/dev/null)

        if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
          echo "dg01: fail — ${#MISSING_DEPS[@]} dependency/dependencies missing from pnpm-lock.yaml:"
          for dep in "${MISSING_DEPS[@]}"; do
            echo "  - ${dep}"
          done
          STATIC_RESULT=1
        else
          echo "dg01: pass — all package.json dependencies found in pnpm-lock.yaml"
          STATIC_RESULT=0
        fi
      fi
    else
      # yarn.lock: text format, do a simple grep check
      MISSING_DEPS=()
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if ! grep -q "^\"${dep}@\|^${dep}@" "$LOCKFILE" 2>/dev/null; then
          MISSING_DEPS+=("$dep")
        fi
      done < <(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$MANIFEST" 2>/dev/null)

      if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
        echo "dg01: fail — ${#MISSING_DEPS[@]} dependency/dependencies missing from yarn.lock:"
        for dep in "${MISSING_DEPS[@]}"; do
          echo "  - ${dep}"
        done
        STATIC_RESULT=1
      else
        echo "dg01: pass — all package.json dependencies found in yarn.lock"
        STATIC_RESULT=0
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Aggregate results
# ---------------------------------------------------------------------------
# fail from either command or static → fail
if [[ "$CMD_RESULT" -eq 1 || "$STATIC_RESULT" -eq 1 ]]; then
  exit 1
fi

# Both unverifiable
if [[ "$CMD_RESULT" -eq 0 && "$STATIC_RESULT" -eq 2 ]]; then
  exit 2
fi

# pass (0) wins over unverifiable
exit 0
