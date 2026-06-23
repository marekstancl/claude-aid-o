#!/usr/bin/env bash
# dg12-authority.sh — authority/acceptance consistency check
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — optional authority validator command
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. argv provided → run it; map exit code; skip native logic
#   2. Look for authority surface files:
#        .aid-o/config/permissions.yaml
#        .aid-o/config/execution.yaml
#        plugins/*/defaults/policies/*.yaml
#        any *-policy.yaml or *-authority.yaml in root
#   3. None found → exit 2 (unverifiable — no authority surface)
#   4. yq not available → exit 2 (cannot parse YAML)
#   5. For each file:
#        - yq e '.' parses successfully
#        - Check for enforcement:blocking + status:planned contradiction (same block)
#        - Check enforcement enum: only 'observe' or 'blocking' are valid
#   6. Exit 0 if clean, exit 1 if any contradiction, exit 2 if unparseable

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg12: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg12: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg12: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Check yq availability
# ---------------------------------------------------------------------------
if ! command -v yq >/dev/null 2>&1; then
  echo "dg12: unverifiable — yq not found; cannot parse YAML authority files"
  echo "dg12: install yq (https://github.com/mikefarah/yq) to enable native analysis"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 3: Discover authority surface files
# ---------------------------------------------------------------------------
AUTH_FILES=()

# AID workspace config files
for f in \
  "${ROOT}/.aid-o/config/permissions.yaml" \
  "${ROOT}/.aid-o/config/execution.yaml"; do
  [[ -f "$f" ]] && AUTH_FILES+=("$f")
done

# Plugin defaults/policies/*.yaml
shopt -s nullglob globstar
for f in "${ROOT}"/plugins/*/defaults/policies/*.yaml; do
  [[ -f "$f" ]] && AUTH_FILES+=("$f")
done
# Root-level *-policy.yaml and *-authority.yaml
for f in "${ROOT}"/*-policy.yaml "${ROOT}"/*-authority.yaml; do
  [[ -f "$f" ]] && AUTH_FILES+=("$f")
done
shopt -u nullglob globstar

if [[ ${#AUTH_FILES[@]} -eq 0 ]]; then
  echo "dg12: unverifiable — no authority surface files found in ${ROOT}"
  echo "dg12: searched: .aid-o/config/*.yaml, plugins/*/defaults/policies/*.yaml, *-policy.yaml, *-authority.yaml"
  exit 2
fi

echo "dg12: found ${#AUTH_FILES[@]} authority file(s)"

FAIL=0
FAIL_DETAILS=()
PARSE_ERRORS=0

# ---------------------------------------------------------------------------
# Helper: extract flat field value from a YAML file using yq
# Usage: yq_field <file> <expression>
# ---------------------------------------------------------------------------
yq_field() {
  yq e "$2" "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Step 4: Check each authority file
# ---------------------------------------------------------------------------
for auth_file in "${AUTH_FILES[@]}"; do
  rel_file="${auth_file#"$ROOT/"}"
  echo "dg12: checking ${rel_file}"

  # 4a: Verify YAML parses successfully
  if ! yq e '.' "$auth_file" >/dev/null 2>&1; then
    FAIL=1
    PARSE_ERRORS=$((PARSE_ERRORS + 1))
    FAIL_DETAILS+=("${rel_file}: YAML parse error")
    echo "dg12: FAIL — ${rel_file}: cannot parse YAML"
    continue
  fi

  # 4b: Check enforcement enum validity (only 'observe' or 'blocking' allowed)
  # Extract all 'enforcement:' values anywhere in the file
  while IFS= read -r enforcement_val; do
    [[ -z "$enforcement_val" ]] && continue
    [[ "$enforcement_val" == "null" ]] && continue
    case "$enforcement_val" in
      observe|blocking) ;;
      *)
        FAIL=1
        FAIL_DETAILS+=("${rel_file}: invalid enforcement value '${enforcement_val}' (must be 'observe' or 'blocking')")
        echo "dg12: FAIL — ${rel_file}: invalid enforcement value '${enforcement_val}'"
        ;;
    esac
  done < <(yq e '.. | select(has("enforcement")) | .enforcement' "$auth_file" 2>/dev/null || true)

  # 4c: Check enforcement:blocking + status:planned contradiction
  # For each object that has both enforcement and status, check for the contradiction
  # We extract pairs of (enforcement, status) from each map node that has both
  while IFS=$'\t' read -r enf_val stat_val; do
    [[ -z "$enf_val" || -z "$stat_val" ]] && continue
    [[ "$enf_val" == "null" || "$stat_val" == "null" ]] && continue
    if [[ "$enf_val" == "blocking" && "$stat_val" == "planned" ]]; then
      FAIL=1
      FAIL_DETAILS+=("${rel_file}: contradiction — enforcement: blocking with status: planned in the same block")
      echo "dg12: FAIL — ${rel_file}: enforcement: blocking with status: planned (planned enforcement cannot be blocking now)"
    fi
  done < <(
    # yq: find all maps with both enforcement and status; print tab-separated pairs
    yq e '
      .. | select(
        type == "!!map" and
        has("enforcement") and
        has("status")
      ) | [.enforcement, .status] | join("\t")
    ' "$auth_file" 2>/dev/null || true
  )
done

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "$FAIL" -eq 0 ]]; then
  echo "dg12: pass — all authority files are self-consistent (no contradictions, valid enforcement enum)"
  exit 0
else
  echo "dg12: fail — authority consistency issues detected:"
  for detail in "${FAIL_DETAILS[@]}"; do
    echo "  - ${detail}"
  done
  exit 1
fi
