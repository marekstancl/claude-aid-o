#!/usr/bin/env bash
# dg17-independent-oracle-nodrop.sh — verify analytics output meets declared cardinality baseline
#
# Exit: 0=pass, 1=fail, 2=config_missing
# Requires: delivery-map.yaml with oracle_baselines section
# Each baseline must declare analytics_output_file + expected_cardinality.
# Missing file or config → config_missing (exit 2), NOT a fake pass.
#
# Args: [<command> <args>...] — override command (if any); if provided, run it
# Env:  AID_PROJECT_ROOT   — project root directory
#       AID_CHANGED_PATHS  — path to file with one changed path per line (checked but not used in core logic)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
CHANGED_PATHS_FILE="${AID_CHANGED_PATHS:-}"

# Source delivery-map accessor
source "${SCRIPT_DIR}/../aid-delivery-map.sh"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg17: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg17: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg17: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: get oracle_baselines section from delivery-map
# ---------------------------------------------------------------------------
baselines_json=""
if ! baselines_json="$(get_section oracle_baselines 2>/dev/null)"; then
  echo "dg17: config_missing — no oracle_baselines section in delivery-map (or delivery-map not found)"
  exit 2
fi

if [[ -z "$baselines_json" ]]; then
  echo "dg17: config_missing — oracle_baselines section is empty in delivery-map"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 3: extract baseline names
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "dg17: config_missing — jq not found; cannot parse oracle_baselines"
  exit 2
fi

mapfile -t BASELINE_NAMES < <(echo "$baselines_json" | jq -r 'keys[]' 2>/dev/null)

if [[ ${#BASELINE_NAMES[@]} -eq 0 ]]; then
  echo "dg17: config_missing — oracle_baselines is present but has no entries"
  exit 2
fi

echo "dg17: found ${#BASELINE_NAMES[@]} baseline(s): ${BASELINE_NAMES[*]}"

# ---------------------------------------------------------------------------
# Step 4: check each baseline
# ---------------------------------------------------------------------------
FAILURES=()

for baseline in "${BASELINE_NAMES[@]}"; do
  # 4a: read analytics_output_file
  analytics_output_file="$(echo "$baselines_json" | jq -r ".${baseline}.analytics_output_file // empty" 2>/dev/null)"
  if [[ -z "$analytics_output_file" ]]; then
    echo "dg17: config_missing — baseline '${baseline}' missing analytics_output_file"
    exit 2
  fi

  # 4b: read expected_cardinality
  expected_cardinality="$(echo "$baselines_json" | jq -r ".${baseline}.expected_cardinality // empty" 2>/dev/null)"
  if [[ -z "$expected_cardinality" ]]; then
    echo "dg17: config_missing — baseline '${baseline}' missing expected_cardinality"
    exit 2
  fi

  # 4c: validate expected_cardinality is numeric
  if ! [[ "$expected_cardinality" =~ ^[0-9]+$ ]]; then
    echo "dg17: config_missing — baseline '${baseline}' expected_cardinality is not a non-negative integer: '${expected_cardinality}'"
    exit 2
  fi

  # 4d: read cardinality_method (default: jq_length)
  cardinality_method="$(echo "$baselines_json" | jq -r ".${baseline}.cardinality_method // \"jq_length\"" 2>/dev/null)"

  # Resolve path relative to ROOT if not absolute
  if [[ "$analytics_output_file" != /* ]]; then
    analytics_output_file="${ROOT}/${analytics_output_file}"
  fi

  # 4e: check file exists — missing file is config_missing, not a fake pass
  if [[ ! -f "$analytics_output_file" ]]; then
    echo "dg17: config_missing — baseline '${baseline}' analytics_output_file not accessible: '${analytics_output_file}'"
    exit 2
  fi

  # 4f: count items using declared method
  actual_count=0
  case "$cardinality_method" in
    jq_length)
      if ! command -v jq >/dev/null 2>&1; then
        echo "dg17: config_missing — jq not found; required for cardinality_method=jq_length"
        exit 2
      fi
      actual_count_raw="$(jq 'length' "$analytics_output_file" 2>/dev/null)"
      if [[ -z "$actual_count_raw" ]]; then
        echo "dg17: config_missing — baseline '${baseline}' jq could not parse '${analytics_output_file}'"
        exit 2
      fi
      actual_count="$actual_count_raw"
      ;;
    grep_count)
      actual_count="$(grep -c '' "$analytics_output_file" 2>/dev/null || echo 0)"
      ;;
    *)
      echo "dg17: config_missing — baseline '${baseline}' unknown cardinality_method: '${cardinality_method}' (supported: jq_length, grep_count)"
      exit 2
      ;;
  esac

  # Validate actual_count is numeric
  if ! [[ "$actual_count" =~ ^[0-9]+$ ]]; then
    echo "dg17: config_missing — baseline '${baseline}' could not determine actual count (got: '${actual_count}')"
    exit 2
  fi

  echo "dg17: baseline '${baseline}' — method=${cardinality_method} actual=${actual_count} expected>=${expected_cardinality}"

  # 4g: compare
  if [[ "$actual_count" -lt "$expected_cardinality" ]]; then
    FAILURES+=("${baseline}: actual=${actual_count} < expected=${expected_cardinality} (${analytics_output_file})")
  fi
done

# ---------------------------------------------------------------------------
# Step 5: report results
# ---------------------------------------------------------------------------
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "dg17: fail — ${#FAILURES[@]} baseline(s) below declared cardinality:"
  for f in "${FAILURES[@]}"; do
    echo "  ${f}"
  done
  exit 1
fi

echo "dg17: pass — all ${#BASELINE_NAMES[@]} baseline(s) meet declared cardinality"
exit 0
