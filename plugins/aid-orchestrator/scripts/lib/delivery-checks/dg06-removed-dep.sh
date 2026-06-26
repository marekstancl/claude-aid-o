#!/usr/bin/env bash
# dg06-removed-dep.sh — detect removed deps with remaining production imports
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — override command (if any); if provided, run it
# Env:  AID_PROJECT_ROOT — project root directory
#       AID_CHANGED_PATHS — path to file with one changed path per line
#       AID_BASE_SHA — base commit for comparing package.json
#
# Logic:
#   1. argv provided → run it; map exit code; skip native logic
#   2. No AID_BASE_SHA → unverifiable (cannot diff package.json)
#   3. Check changed paths: if package.json not touched → unverifiable (nothing to check)
#   4. git show base:package.json to get old deps; diff against current
#   5. For each removed dep: grep production source for require/import
#   6. Any hit → fail with file:line output
#   7. No removed deps with imports → pass

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
CHANGED_PATHS_FILE="${AID_CHANGED_PATHS:-}"
BASE_SHA="${AID_BASE_SHA:-}"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg06: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg06: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg06: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Require git and base SHA for native analysis
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "dg06: unverifiable — git not found"
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "dg06: unverifiable — jq not found; cannot parse package.json"
  exit 2
fi

if [[ -z "$BASE_SHA" ]]; then
  echo "dg06: unverifiable — AID_BASE_SHA not set; cannot compare package.json against base commit"
  echo "dg06: set AID_BASE_SHA to the base commit SHA for dep-removal detection"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 3: Check if package.json was in changed paths (quick early exit)
# ---------------------------------------------------------------------------
if [[ -n "$CHANGED_PATHS_FILE" && -f "$CHANGED_PATHS_FILE" ]]; then
  if ! grep -q "package.json" "$CHANGED_PATHS_FILE" 2>/dev/null; then
    echo "dg06: pass — package.json not in changed paths; no dependency removal to check"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Get old deps from base commit
# ---------------------------------------------------------------------------
MANIFEST="${ROOT}/package.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "dg06: unverifiable — no package.json in ${ROOT}"
  exit 2
fi

# Get old deps (at base_sha)
old_deps_output="$(git -C "$ROOT" show "${BASE_SHA}:package.json" 2>/dev/null)"
if [[ -z "$old_deps_output" ]]; then
  echo "dg06: unverifiable — cannot read package.json at ${BASE_SHA} (commit not accessible or file not present)"
  exit 2
fi

# Extract old dep names
# Use jq exit code to distinguish parse failure from empty result
if ! echo "$old_deps_output" | jq -e '.' >/dev/null 2>&1; then
  echo "dg06: unverifiable — could not parse JSON from package.json at ${BASE_SHA}"
  exit 2
fi

mapfile -t OLD_DEPS < <(echo "$old_deps_output" | jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' 2>/dev/null)

if [[ ${#OLD_DEPS[@]} -eq 0 ]]; then
  # 0 deps at base is valid — means nothing was declared to remove
  echo "dg06: pass — package.json at ${BASE_SHA} had no declared dependencies; nothing to remove"
  exit 0
fi

# Extract current dep names
mapfile -t CURRENT_DEPS < <(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$MANIFEST" 2>/dev/null)

# Compute removed deps: OLD_DEPS - CURRENT_DEPS
declare -A current_dep_set
for dep in "${CURRENT_DEPS[@]}"; do
  current_dep_set["$dep"]=1
done

REMOVED_DEPS=()
for dep in "${OLD_DEPS[@]}"; do
  if [[ -z "${current_dep_set[$dep]+_}" ]]; then
    REMOVED_DEPS+=("$dep")
  fi
done

if [[ ${#REMOVED_DEPS[@]} -eq 0 ]]; then
  echo "dg06: pass — no dependencies removed from package.json (compared ${BASE_SHA}..HEAD)"
  exit 0
fi

echo "dg06: detected ${#REMOVED_DEPS[@]} removed dependency/dependencies: ${REMOVED_DEPS[*]}"

# ---------------------------------------------------------------------------
# Step 5: Grep production source for remaining imports of removed deps
# ---------------------------------------------------------------------------

# Production source directories to search
SEARCH_DIRS=()
for d in src lib; do
  [[ -d "${ROOT}/${d}" ]] && SEARCH_DIRS+=("${ROOT}/${d}")
done
# Also search root index files
ROOT_INDEX_GLOB=("${ROOT}"/index.*)

VIOLATIONS=()

for dep in "${REMOVED_DEPS[@]}"; do
  # Escape dep name for use in grep (handle scoped packages like @org/pkg)
  escaped_dep="$(printf '%s\n' "$dep" | sed 's/[[\.*^$()+?{|]/\\&/g')"

  # Search for require('dep') and from 'dep'
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    VIOLATIONS+=("$hit")
  done < <(
    # Use grep -rn for file:line output
    grep -rn \
      -e "require(['\"]${escaped_dep}['\"]" \
      -e "require(['\"]${escaped_dep}/" \
      -e "from ['\"]${escaped_dep}['\"]" \
      -e "from ['\"]${escaped_dep}/" \
      --include="*.js" \
      --include="*.ts" \
      --include="*.mjs" \
      --include="*.cjs" \
      --include="*.jsx" \
      --include="*.tsx" \
      "${SEARCH_DIRS[@]}" \
      "${ROOT_INDEX_GLOB[@]}" \
      2>/dev/null || true
  )
done

# ---------------------------------------------------------------------------
# Step 6: Report results
# ---------------------------------------------------------------------------
if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "dg06: fail — removed dependency/dependencies still imported in production source:"
  for v in "${VIOLATIONS[@]}"; do
    echo "  ${v}"
  done
  exit 1
fi

echo "dg06: pass — removed dependencies (${REMOVED_DEPS[*]}) have no remaining production imports"
exit 0
