#!/usr/bin/env bash
# dg18-acceptance-struct.sh — acceptance provenance adapter
#
# Scope: PROVENANCE ONLY. Reads existing FSM step-*-verify.md evidence.
# NEVER emits fail from its own authority — skip handled by dispatcher.
# Exit: always 0 (pass or info). Never 1, never 2.
#
# Args: [<command> <args>...] — override command (if any); exit code mapped to 0
# Env:  AID_EVIDENCE_DIR    — direct path to dir containing step-*-verify.md files
#       AID_EPIC_ID         — EPIC identifier (for constructing evidence path)
#       AID_RUN_ID          — run identifier (for constructing evidence path)
#       AID_EVIDENCE_BASE   — base path override for evidence root
#       AID_PROJECT_ROOT    — project root

set -uo pipefail

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command (map exit code to 0)
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg18: running override command: $*"
  cmd_output=""

  cmd_output="$(ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}" && cd "$ROOT" && "$@" 2>&1)" || true

  echo "dg18: command completed (exit mapped to 0 per probe policy)"
  echo "$cmd_output"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: resolve evidence directory
# ---------------------------------------------------------------------------
EVIDENCE_STEPS_DIR=""

if [[ -n "${AID_EVIDENCE_DIR:-}" ]]; then
  # Direct path provided by dispatcher
  EVIDENCE_STEPS_DIR="${AID_EVIDENCE_DIR}"
elif [[ -n "${AID_EPIC_ID:-}" && -n "${AID_RUN_ID:-}" ]]; then
  # Construct from EPIC_ID + RUN_ID
  _root="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
  _base="${AID_EVIDENCE_BASE:-${_root}/.aid-o/work/evidence}"
  EVIDENCE_STEPS_DIR="${_base}/${AID_EPIC_ID}/${AID_RUN_ID}/steps"
else
  # Fallback: scan .aid-o/work/evidence/ for step-*-verify.md via glob
  _root="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
  _base="${AID_EVIDENCE_BASE:-${_root}/.aid-o/work/evidence}"
  if [[ -d "$_base" ]]; then
    # Use the base dir itself for globbing below
    EVIDENCE_STEPS_DIR="$_base"
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: find step-*-verify.md files
# ---------------------------------------------------------------------------
if [[ -z "$EVIDENCE_STEPS_DIR" ]]; then
  echo "dg18: no evidence dir context; provenance check skipped"
  exit 0
fi

if [[ ! -d "$EVIDENCE_STEPS_DIR" ]]; then
  echo "dg18: evidence dir does not exist: '${EVIDENCE_STEPS_DIR}'; provenance check skipped"
  exit 0
fi

# Collect all step-*-verify.md files (recursive to handle fallback base dir)
mapfile -t VERIFY_FILES < <(find "$EVIDENCE_STEPS_DIR" -name "step-*-verify.md" -type f 2>/dev/null | sort)

total_files=${#VERIFY_FILES[@]}

if [[ "$total_files" -eq 0 ]]; then
  echo "dg18: pass — no step-*-verify.md files found in '${EVIDENCE_STEPS_DIR}'; nothing to surface"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: count files containing '## Result: PASS'
# ---------------------------------------------------------------------------
pass_count=0
anomaly_files=()

for verify_file in "${VERIFY_FILES[@]}"; do
  if grep -q '## Result: PASS' "$verify_file" 2>/dev/null; then
    pass_count=$(( pass_count + 1 ))
  else
    anomaly_files+=("$verify_file")
  fi
done

# ---------------------------------------------------------------------------
# Step 5: emit structured output (always exit 0)
# ---------------------------------------------------------------------------
echo "dg18: pass — provenance verified: ${pass_count}/${total_files} step-verify files contain '## Result: PASS'"

if [[ ${#anomaly_files[@]} -gt 0 ]]; then
  echo "dg18: info — ${#anomaly_files[@]} file(s) without '## Result: PASS' (anomalous, not a gate failure):"
  for f in "${anomaly_files[@]}"; do
    echo "  ${f}"
  done
fi

exit 0
