#!/usr/bin/env bash
# dg15-route-resolve.sh — detect literal links that don't resolve to declared routes
#
# Scope: LITERAL LINKS ONLY. Dynamic links (variable interpolation, template literals)
# are outside scope — no false-negative claim is made for those.
#
# Exit: 0=pass, 1=fail, 2=config_missing/unverifiable
# Args: [<command> <args>...] — override command (if any); if provided, run it
# Env:  AID_PROJECT_ROOT   — project root directory
#       AID_CHANGED_PATHS  — path to file with one changed path per line
#       AID_BASE_SHA       — base commit SHA
# Requires: delivery-map.yaml with routes section (framework + route_files + link_globs)
#
# Supported frameworks: react-router, express

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# Source delivery-map accessor
source "${SCRIPT_DIR}/../aid-delivery-map.sh"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg15: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg15: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg15: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: get routes section from delivery-map
# ---------------------------------------------------------------------------
routes_json=""
if ! routes_json="$(get_section routes 2>/dev/null)"; then
  echo "dg15: config_missing — no routes section in delivery-map (or delivery-map not found)"
  exit 2
fi

if [[ -z "$routes_json" ]]; then
  echo "dg15: config_missing — routes section is empty in delivery-map"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 3: validate framework
# ---------------------------------------------------------------------------
SUPPORTED_FRAMEWORKS=("react-router" "express")

framework=""
framework="$(echo "$routes_json" | jq -r '.framework // empty' 2>/dev/null || true)"

if [[ -z "$framework" ]]; then
  echo "dg15: config_missing — routes.framework not set in delivery-map (supported: react-router, express)"
  exit 2
fi

is_supported=0
for f in "${SUPPORTED_FRAMEWORKS[@]}"; do
  if [[ "$framework" == "$f" ]]; then
    is_supported=1
    break
  fi
done

if [[ $is_supported -eq 0 ]]; then
  echo "dg15: config_missing — unsupported framework '${framework}' (supported: react-router, express)"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 4: extract route_files globs
# ---------------------------------------------------------------------------
mapfile -t ROUTE_FILE_GLOBS < <(echo "$routes_json" | jq -r '.route_files[]? // empty' 2>/dev/null || true)

if [[ ${#ROUTE_FILE_GLOBS[@]} -eq 0 ]]; then
  echo "dg15: config_missing — routes.route_files is empty or missing in delivery-map"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 5: extract link_globs — if empty, no links to check → pass
# ---------------------------------------------------------------------------
mapfile -t LINK_GLOBS < <(echo "$routes_json" | jq -r '.link_globs[]? // empty' 2>/dev/null || true)

if [[ ${#LINK_GLOBS[@]} -eq 0 ]]; then
  echo "dg15: pass — routes.link_globs is empty; no links to check"
  exit 0
fi

# express has no client-side links — nothing to resolve
if [[ "$framework" == "express" ]]; then
  if [[ ${#LINK_GLOBS[@]} -gt 0 ]]; then
    echo "dg15: pass — framework '${framework}' has no client-side routing; link_globs present but skipped"
  else
    echo "dg15: pass — framework '${framework}' has no client-side links to resolve"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: expand globs relative to ROOT, print matching files
# ---------------------------------------------------------------------------
expand_globs() {
  local root="$1"
  shift
  for pattern in "$@"; do
    # Use find with -path to match glob patterns safely (no eval)
    find "$root" -type f -path "${root}/${pattern}" 2>/dev/null
  done | sort -u
}

# ---------------------------------------------------------------------------
# Step 6: collect declared routes from route_files
# ---------------------------------------------------------------------------
DECLARED_ROUTES=()

while IFS= read -r route_file; do
  [[ -f "$route_file" ]] || continue

  if [[ "$framework" == "react-router" ]]; then
    # Extract path="..." or path='...' from JSX/TSX route declarations
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      DECLARED_ROUTES+=("$match")
    done < <(
      grep -oE 'path=["'"'"'][^"'"'"']+["'"'"']' "$route_file" 2>/dev/null \
        | sed "s/path=[\"']//;s/[\"']\$//" \
        || true
    )
  fi
done < <(expand_globs "$ROOT" "${ROUTE_FILE_GLOBS[@]}")

# ---------------------------------------------------------------------------
# Step 7: collect link references from link_globs
# ---------------------------------------------------------------------------
# link_files: prefer changed paths if available, else all matching files
declare -a LINK_FILES=()

if [[ -n "${AID_CHANGED_PATHS:-}" && -f "${AID_CHANGED_PATHS}" ]]; then
  # Filter changed paths to those matching link_globs
  while IFS= read -r changed_file; do
    [[ -z "$changed_file" ]] && continue
    abs_changed="${ROOT}/${changed_file}"
    [[ -f "$abs_changed" ]] || abs_changed="$changed_file"
    [[ -f "$abs_changed" ]] || continue

    for pattern in "${LINK_GLOBS[@]}"; do
      # Simple suffix/extension matching: check if filename matches glob pattern loosely
      # Use case statement for glob matching
      rel="${abs_changed#"${ROOT}/"}"
      if [[ "$rel" == $pattern ]]; then
        LINK_FILES+=("$abs_changed")
        break
      fi
    done
  done < "${AID_CHANGED_PATHS}"
fi

# If no changed link files found (or no CHANGED_PATHS set), scan all matching files
# AID_CHANGED_PATHS absent or no matches → full codebase scan (expected on fresh run)
if [[ ${#LINK_FILES[@]} -eq 0 ]]; then
  echo "dg15: AID_CHANGED_PATHS absent or no matching changes — scanning all link_globs files"
  while IFS= read -r lf; do
    [[ -f "$lf" ]] && LINK_FILES+=("$lf")
  done < <(expand_globs "$ROOT" "${LINK_GLOBS[@]}")
fi

if [[ ${#LINK_FILES[@]} -eq 0 ]]; then
  echo "dg15: pass — no link files found matching link_globs; nothing to check"
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: strip query string and fragment from a path
# ---------------------------------------------------------------------------
strip_query_fragment() {
  local path="$1"
  # Remove ?... and #...
  path="${path%%?*}"
  path="${path%%#*}"
  echo "$path"
}

# ---------------------------------------------------------------------------
# Helper: check if a link matches any declared route
# For parameterized routes (:id), replace :param with [^/]+ pattern
# ---------------------------------------------------------------------------
link_matches_route() {
  local link="$1"
  shift
  local routes=("$@")

  for route in "${routes[@]}"; do
    # Exact match
    if [[ "$link" == "$route" ]]; then
      return 0
    fi

    # Build regex from parameterized route: /users/:id → ^/users/[^/]+$
    local regex
    regex="$(echo "$route" | sed 's|:[^/]*|[^/]+|g')"
    regex="^${regex}$"

    if echo "$link" | grep -qE "$regex" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# Step 8-10: for each link found, check against declared routes
# ---------------------------------------------------------------------------
VIOLATIONS=()

for link_file in "${LINK_FILES[@]}"; do
  [[ -f "$link_file" ]] || continue

  if [[ "$framework" == "react-router" ]]; then
    # Grep for to="..." or to='...' in Link/NavLink
    while IFS= read -r raw_link; do
      [[ -z "$raw_link" ]] && continue

      # Strip query string and fragment
      clean_link="$(strip_query_fragment "$raw_link")"
      [[ -z "$clean_link" ]] && continue

      # Skip relative links (no leading /)
      [[ "$clean_link" != /* ]] && continue

      if [[ ${#DECLARED_ROUTES[@]} -eq 0 ]]; then
        rel_file="${link_file#"${ROOT}/"}"
        VIOLATIONS+=("${rel_file}: unresolved link '${clean_link}' (no routes declared in route_files)")
      elif ! link_matches_route "$clean_link" "${DECLARED_ROUTES[@]}"; then
        rel_file="${link_file#"${ROOT}/"}"
        VIOLATIONS+=("${rel_file}: unresolved link '${clean_link}'")
      fi
    done < <(
      grep -oE 'to=["'"'"'][^"'"'"']+["'"'"']' "$link_file" 2>/dev/null \
        | sed "s/to=[\"']//;s/[\"']\$//" \
        || true
    )
  fi
done

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "dg15: fail — literal links not resolved to any declared route:"
  for v in "${VIOLATIONS[@]}"; do
    echo "  ${v}"
  done
  echo ""
  echo "  Note: LITERAL LINKS ONLY checked. Dynamic links (variable interpolation,"
  echo "  template literals) are outside scope — no false-negative claim for those."
  exit 1
fi

echo "dg15: pass — all literal links resolve to declared routes"
echo "  (${#LINK_FILES[@]} link file(s) checked against ${#DECLARED_ROUTES[@]} declared route(s))"
exit 0
