#!/usr/bin/env bash
# aid-fsm.sh — AID Orchestrator 6-state FSM controller
# Usage:
#   aid-fsm.sh init <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file>
#   aid-fsm.sh transition <from> <to> <state_file>
#   aid-fsm.sh get-state <state_file>
#   aid-fsm.sh increment-step <state_file>
#   aid-fsm.sh get-field <field> <state_file>

set -euo pipefail

VALID_STATES="READY EXECUTE GATES ESCALATION DONE"

# Valid transitions map: "FROM:TO" pairs
VALID_TRANSITIONS=(
  "READY:EXECUTE"
  "EXECUTE:EXECUTE"
  "EXECUTE:GATES"
  "EXECUTE:ESCALATION"
  "GATES:DONE"
  "GATES:EXECUTE"
  "GATES:ESCALATION"
  "ESCALATION:EXECUTE"
  "ESCALATION:GATES"
)

is_valid_state() {
  local state="$1"
  [[ " $VALID_STATES " =~ " $state " ]]
}

is_valid_transition() {
  local from="$1" to="$2"
  local pair="${from}:${to}"
  for t in "${VALID_TRANSITIONS[@]}"; do
    [[ "$t" == "$pair" ]] && return 0
  done
  return 1
}

cmd_init() {
  local epic_id="$1" run_id="$2" total_steps="$3" mode="$4"
  local branch="$5" base_commit="$6" state_file="$7"

  if [[ -f "$state_file" ]]; then
    echo "ERROR: state_file already exists: $state_file (prevent duplicate init)" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" << EOF
epic_id: $epic_id
run_id: $run_id
state: READY
current_step: 0
total_steps: $total_steps
mode: $mode
branch: $branch
base_commit: $base_commit
gate_retries: 0
escalation_count: 0
started_at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
  echo "Initialized state: READY" >&2
}

cmd_transition() {
  local from="$1" to="$2" state_file="$3"

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found: $state_file" >&2; exit 1; }

  local current_state
  current_state=$(grep '^state:' "$state_file" | awk '{print $2}')

  if [[ "$current_state" != "$from" ]]; then
    echo "ERROR: expected state $from but found $current_state" >&2
    exit 1
  fi

  if ! is_valid_state "$to"; then
    echo "ERROR: invalid target state: $to" >&2
    exit 1
  fi

  if ! is_valid_transition "$from" "$to"; then
    echo "ERROR: invalid transition $from → $to" >&2
    exit 1
  fi

  # Increment escalation_count when entering ESCALATION
  if [[ "$to" == "ESCALATION" ]]; then
    local count
    count=$(grep '^escalation_count:' "$state_file" | awk '{print $2}')
    sed -i "s/^escalation_count: .*/escalation_count: $((count + 1))/" "$state_file"
  fi

  # Update state (atomic via temp file + mv)
  local tmp_file="${state_file}.tmp"
  sed "s/^state: .*/state: $to/" "$state_file" > "$tmp_file"
  mv "$tmp_file" "$state_file"

  echo "Transition: $from → $to" >&2
}

cmd_get_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  grep '^state:' "$state_file" | awk '{print $2}'
}

cmd_increment_step() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  local step
  step=$(grep '^current_step:' "$state_file" | awk '{print $2}')
  local tmp="${state_file}.tmp"
  sed "s/^current_step: .*/current_step: $((step + 1))/" "$state_file" > "$tmp"
  mv "$tmp" "$state_file"
  echo "$((step + 1))"
}

cmd_get_field() {
  local field="$1" state_file="$2"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  grep "^${field}:" "$state_file" | awk '{print $2}' | tr -d '"'
}

# Dispatch
case "${1:-}" in
  init)           shift; cmd_init "$@" ;;
  transition)     shift; cmd_transition "$@" ;;
  get-state)      shift; cmd_get_state "$@" ;;
  increment-step) shift; cmd_increment_step "$@" ;;
  get-field)      shift; cmd_get_field "$@" ;;
  *)
    echo "Usage: aid-fsm.sh <init|transition|get-state|increment-step|get-field> [args...]" >&2
    exit 1 ;;
esac
