#!/usr/bin/env bash
# aid-gate-runtime-report.sh — proposed vs configured `timeout_seconds` per
# gate (P097 Step 5).
#
# WHY THIS FILE EXISTS: a maintainer who wants to know whether a gate's
# configured deadline still matches what the gate takes has to read many
# `gates_rows/<gate>.json` files by hand. This prints, for every gate in
# execution.yaml (or the one named), the number the written derivation rule
# proposes from the recorded history next to the number configured. It never
# writes anything: the deadline changes only when a person edits the file.
#
# Usage:
#   aid-gate-runtime-report.sh [--project-root <path>] [gate_name]
#
#   --project-root <path>   project root containing .aid-o/ (default: cwd)
#   [gate_name]             optional; omit to list every configured gate
#
# Exit codes: 0 success (incl. no history yet), 1 usage / not an AID project,
# 2 yq/jq missing.

usage() {
  cat >&2 <<'EOF'
Usage: aid-gate-runtime-report.sh [--project-root <path>] [gate_name]

  --project-root <path>   project root containing .aid-o/ (default: cwd)
  [gate_name]             optional; omit to list every configured gate

Exit codes: 0 success (incl. no history yet), 1 usage/not-an-AID-project,
2 yq/jq missing.
EOF
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/aid-gate-runtime-baseline.sh"

PROJECT_ROOT="$(pwd)"
GATE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      [[ $# -ge 2 ]] || usage
      PROJECT_ROOT="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    -*) echo "Unknown flag: $1" >&2; usage ;;
    *)
      [[ -z "$GATE_NAME" ]] || usage
      GATE_NAME="$1"
      shift
      ;;
  esac
done

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required (mikefarah/yq v4)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[[ -f "$LIB" ]] || { echo "ERROR: aid-gate-runtime-baseline.sh not found at $LIB" >&2; exit 2; }

cd "$PROJECT_ROOT" || { echo "ERROR: cannot cd into --project-root '$PROJECT_ROOT'" >&2; exit 1; }
if [[ ! -d ".aid-o" ]]; then
  echo "ERROR: '$PROJECT_ROOT' has no .aid-o/ workspace — not an AID project (run /aid-init first)" >&2
  exit 1
fi

# shellcheck source=lib/aid-gate-runtime-baseline.sh
source "$LIB"

EXEC_YAML=".aid-o/config/execution.yaml"
EVIDENCE_ROOT=".aid-o/work/evidence"

# _configured <gate> — the configured timeout, or the template default 60.
_configured() {
  [[ -f "$EXEC_YAML" ]] || { echo 60; return 0; }
  GATE="$1" yq '.gates[strenv(GATE)].timeout_seconds // 60' "$EXEC_YAML" 2>/dev/null || echo 60
}

_report_one_gate() {
  echo "$(gate_baseline_propose "$EVIDENCE_ROOT" "$1") configured_timeout_seconds=$(_configured "$1")"
}

if [[ -n "$GATE_NAME" ]]; then
  _report_one_gate "$GATE_NAME"
  exit 0
fi

if [[ ! -f "$EXEC_YAML" ]]; then
  echo "No gates configured — ${EXEC_YAML} does not exist under ${PROJECT_ROOT}."
  exit 0
fi
while IFS= read -r gate; do
  [[ -n "$gate" ]] || continue
  _report_one_gate "$gate"
done < <(yq '.gates // {} | keys | .[]' "$EXEC_YAML" 2>/dev/null | sort)
exit 0
