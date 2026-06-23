#!/usr/bin/env bash
# dg08-runtime-env.sh — runtime environment consistency check
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — optional override command
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. argv provided → run it; map exit code; skip native logic
#   2. Collect Node baseline from .nvmrc or .node-version
#   3. No runtime pin files found → exit 2 (unverifiable — no baseline)
#   4. Read package.json engines.node if present
#   5. Check Dockerfile FROM lines for node version
#   6. Check .github/workflows/*.yml for node-version: pins
#   7. If all found versions share the same major → exit 0 (pass)
#   8. Any mismatch → exit 1 (fail) with details

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg08: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg08: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg08: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Helper: extract major version from a version string
# Handles: "20", "20.11.0", ">=18", ">=18 <20", "^20", "~20.1", "lts/iron"
# Returns: numeric major, or empty string if unparseable
# ---------------------------------------------------------------------------
extract_major() {
  local raw="$1"
  # Strip leading specifiers (>=, <=, ~, ^, =, v)
  local stripped
  stripped="$(printf '%s' "$raw" | sed 's/^[>=<~^v]*//' | sed 's/[[:space:]].*$//')"
  # Extract numeric prefix
  local major
  major="$(printf '%s' "$stripped" | grep -oE '^[0-9]+')"
  printf '%s' "$major"
}

# ---------------------------------------------------------------------------
# Step 2: Collect baseline from .nvmrc or .node-version
# ---------------------------------------------------------------------------
BASELINE_FILE=""
BASELINE_RAW=""

if [[ -f "${ROOT}/.nvmrc" ]]; then
  BASELINE_FILE=".nvmrc"
  BASELINE_RAW="$(cat "${ROOT}/.nvmrc" | tr -d '[:space:]')"
elif [[ -f "${ROOT}/.node-version" ]]; then
  BASELINE_FILE=".node-version"
  BASELINE_RAW="$(cat "${ROOT}/.node-version" | tr -d '[:space:]')"
fi

# ---------------------------------------------------------------------------
# Step 3: No baseline → unverifiable
# ---------------------------------------------------------------------------
if [[ -z "$BASELINE_RAW" ]]; then
  echo "dg08: unverifiable — no .nvmrc or .node-version found in ${ROOT}"
  echo "dg08: cannot check runtime consistency without a pinned version baseline"
  exit 2
fi

BASELINE_MAJOR="$(extract_major "$BASELINE_RAW")"
if [[ -z "$BASELINE_MAJOR" ]]; then
  echo "dg08: unverifiable — could not parse major version from ${BASELINE_FILE}: '${BASELINE_RAW}'"
  exit 2
fi

echo "dg08: baseline from ${BASELINE_FILE}: '${BASELINE_RAW}' → major=${BASELINE_MAJOR}"

FAIL=0
FAIL_DETAILS=()

# ---------------------------------------------------------------------------
# Step 4: Check package.json engines.node
# ---------------------------------------------------------------------------
PKG="${ROOT}/package.json"
if [[ -f "$PKG" ]]; then
  if command -v jq >/dev/null 2>&1; then
    engines_node="$(jq -r '.engines.node // empty' "$PKG" 2>/dev/null || true)"
    if [[ -n "$engines_node" ]]; then
      pkg_major="$(extract_major "$engines_node")"
      echo "dg08: package.json engines.node: '${engines_node}' → major=${pkg_major:-?}"
      if [[ -n "$pkg_major" && "$pkg_major" != "$BASELINE_MAJOR" ]]; then
        FAIL=1
        FAIL_DETAILS+=("package.json engines.node '${engines_node}' (major ${pkg_major}) conflicts with ${BASELINE_FILE} '${BASELINE_RAW}' (major ${BASELINE_MAJOR})")
      fi
    fi
  else
    # No jq: try basic grep
    engines_node="$(grep -oP '"node"\s*:\s*"\K[^"]+' "$PKG" 2>/dev/null || true)"
    if [[ -n "$engines_node" ]]; then
      pkg_major="$(extract_major "$engines_node")"
      echo "dg08: package.json engines.node (grep): '${engines_node}' → major=${pkg_major:-?}"
      if [[ -n "$pkg_major" && "$pkg_major" != "$BASELINE_MAJOR" ]]; then
        FAIL=1
        FAIL_DETAILS+=("package.json engines.node '${engines_node}' (major ${pkg_major}) conflicts with ${BASELINE_FILE} '${BASELINE_RAW}' (major ${BASELINE_MAJOR})")
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 5: Check Dockerfile FROM lines for node image
# ---------------------------------------------------------------------------
shopt -s nullglob
for df in "${ROOT}/Dockerfile" "${ROOT}/Dockerfile."* "${ROOT}/"*/Dockerfile "${ROOT}/"*/Dockerfile.*; do
  [[ -f "$df" ]] || continue
  while IFS= read -r line; do
    # Match: FROM node:20, FROM node:20.11.0, FROM node:lts-alpine, etc.
    if [[ "$line" =~ ^[[:space:]]*FROM[[:space:]]+node:([^[:space:]@-]+) ]]; then
      img_tag="${BASH_REMATCH[1]}"
      df_major="$(extract_major "$img_tag")"
      rel_df="${df#"$ROOT/"}"
      echo "dg08: ${rel_df}: FROM node:${img_tag} → major=${df_major:-?}"
      if [[ -n "$df_major" && "$df_major" != "$BASELINE_MAJOR" ]]; then
        FAIL=1
        FAIL_DETAILS+=("${rel_df}: FROM node:${img_tag} (major ${df_major}) conflicts with ${BASELINE_FILE} '${BASELINE_RAW}' (major ${BASELINE_MAJOR})")
      fi
    fi
  done < "$df"
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# Step 6: Check .github/workflows/*.yml for node-version: pins
# ---------------------------------------------------------------------------
WORKFLOW_DIR="${ROOT}/.github/workflows"
if [[ -d "$WORKFLOW_DIR" ]]; then
  shopt -s nullglob
  for wf in "${WORKFLOW_DIR}"/*.yml "${WORKFLOW_DIR}"/*.yaml; do
    [[ -f "$wf" ]] || continue
    rel_wf="${wf#"$ROOT/"}"
    while IFS= read -r line; do
      # Match: node-version: '20', node-version: "20.11", node-version: 20
      if [[ "$line" =~ node-version:[[:space:]]*[\'\"]?([0-9][^\'\"[:space:]]*) ]]; then
        wf_ver="${BASH_REMATCH[1]}"
        wf_major="$(extract_major "$wf_ver")"
        echo "dg08: ${rel_wf}: node-version: ${wf_ver} → major=${wf_major:-?}"
        if [[ -n "$wf_major" && "$wf_major" != "$BASELINE_MAJOR" ]]; then
          FAIL=1
          FAIL_DETAILS+=("${rel_wf}: node-version: ${wf_ver} (major ${wf_major}) conflicts with ${BASELINE_FILE} '${BASELINE_RAW}' (major ${BASELINE_MAJOR})")
        fi
      fi
    done < "$wf"
  done
  shopt -u nullglob
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "$FAIL" -eq 0 ]]; then
  echo "dg08: pass — all node version pins consistent with ${BASELINE_FILE} major=${BASELINE_MAJOR}"
  exit 0
else
  echo "dg08: fail — runtime version conflicts detected:"
  for detail in "${FAIL_DETAILS[@]}"; do
    echo "  - ${detail}"
  done
  exit 1
fi
