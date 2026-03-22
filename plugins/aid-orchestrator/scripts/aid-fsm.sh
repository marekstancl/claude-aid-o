#!/usr/bin/env bash
# aid-fsm.sh — AID Orchestrator 6-state FSM controller
# Mechanically enforced: precondition-verified transitions + audit trail
#
# Usage:
#   aid-fsm.sh init <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file> [--force]
#   aid-fsm.sh transition <from> <to> <state_file> [--force]
#   aid-fsm.sh get-state <state_file>
#   aid-fsm.sh verify-state <state_file>
#   aid-fsm.sh increment-step <state_file> [--force]
#   aid-fsm.sh get-field <field> <state_file>
#   aid-fsm.sh set-field <field> <value> <state_file>
#   aid-fsm.sh done-advance <from_phase> <to_phase> <state_file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

VALID_STATES="READY EXECUTE GATES ESCALATION DONE ERROR"

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
  "READY:ERROR"
  "EXECUTE:ERROR"
  "GATES:ERROR"
  "ESCALATION:ERROR"
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

# Derive timeline.jsonl path from state_file fields (best-effort, never fails)
derive_timeline() {
  local state_file="$1"
  local epic_id run_id
  epic_id=$(grep '^epic_id:' "$state_file" 2>/dev/null | awk '{print $2}') || true
  run_id=$(grep '^run_id:' "$state_file" 2>/dev/null | awk '{print $2}') || true
  if [[ -n "$epic_id" && -n "$run_id" ]]; then
    echo ".aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl"
  fi
}

# ─── Precondition Checks ───────────────────────────────────────────────
# Called inside cmd_transition() AFTER whitelist check, BEFORE state update.
# Returns 0 if preconditions met, 1 with error message if not.

check_preconditions() {
  local from="$1" to="$2" state_file="$3"
  local run_dir epic_id run_id
  run_dir="$(dirname "$state_file")"
  epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
  run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

  case "${from}:${to}" in
    READY:EXECUTE)
      # PRE-FLIGHT must have run: plan.json exists + total_steps >= 1
      local plan_json="${run_dir}/plan.json"
      [[ -f "$plan_json" ]] || {
        echo "PRECONDITION FAIL: plan.json not found at ${plan_json}. Run PRE-FLIGHT first." >&2
        return 1
      }
      local total
      total=$(grep '^total_steps:' "$state_file" | awk '{print $2}')
      [[ "$total" -ge 1 ]] || {
        echo "PRECONDITION FAIL: total_steps=${total}, must be >= 1." >&2
        return 1
      }
      ;;

    EXECUTE:EXECUTE)
      # More steps must remain
      local current total
      current=$(grep '^current_step:' "$state_file" | awk '{print $2}')
      total=$(grep '^total_steps:' "$state_file" | awk '{print $2}')
      [[ "$current" -lt "$total" ]] || {
        echo "PRECONDITION FAIL: current_step=${current} == total_steps=${total}. All steps done — use EXECUTE→GATES." >&2
        return 1
      }
      ;;

    EXECUTE:GATES)
      # All steps must be completed
      local current total
      current=$(grep '^current_step:' "$state_file" | awk '{print $2}')
      total=$(grep '^total_steps:' "$state_file" | awk '{print $2}')
      [[ "$current" -ge "$total" ]] || {
        echo "PRECONDITION FAIL: current_step=${current} < total_steps=${total}. Not all steps completed." >&2
        return 1
      }
      ;;

    GATES:DONE)
      # gates_report.json must exist with overall: pass
      local report="${evidence_dir}/gates/gates_report.json"
      [[ -f "$report" ]] || {
        echo "PRECONDITION FAIL: gates_report.json not found at ${report}. Run gates first." >&2
        return 1
      }
      if command -v jq &>/dev/null; then
        local overall
        overall=$(jq -r '.overall' "$report" 2>/dev/null)
        [[ "$overall" == "pass" ]] || {
          echo "PRECONDITION FAIL: gates overall=${overall}, must be 'pass' for DONE transition." >&2
          return 1
        }
      fi
      ;;

    ESCALATION:EXECUTE|ESCALATION:GATES)
      # PM must have recorded a decision
      local decision
      decision=$(grep '^escalation_decision:' "$state_file" | awk '{print $2}' || true)
      [[ -n "$decision" ]] || {
        echo "PRECONDITION FAIL: escalation_decision not set in state.yaml. PM must decide first." >&2
        return 1
      }
      ;;

    # Failure/retry paths — always allowed
    EXECUTE:ESCALATION|GATES:ESCALATION|GATES:EXECUTE) : ;;

    # ERROR transitions — always allowed
    *:ERROR) : ;;
  esac
  return 0
}

# ─── Commands ───────────────────────────────────────────────────────────

cmd_init() {
  local epic_id="$1" run_id="$2" total_steps="$3" mode="$4"
  local branch="$5" base_commit="$6" state_file="$7"

  local force="false"
  [[ "${8:-}" == "--force" ]] && force="true"

  if [[ -f "$state_file" ]]; then
    echo "ERROR: state_file already exists: $state_file (prevent duplicate init)" >&2
    exit 1
  fi

  # Plan-level DONE gate: block cross-plan init if previous plan has unreviewed C+A findings
  if [[ "$force" != "true" && -d ".aid-o/work/evidence" ]]; then
    local current_plan_prefix
    current_plan_prefix=$(echo "$epic_id" | grep -oP '^P\d+' || true)

    if [[ -n "$current_plan_prefix" ]]; then
      while IFS= read -r prev_state; do
        local prev_epic prev_plan prev_done_phase prev_dir
        prev_epic=$(grep '^epic_id:' "$prev_state" | awk '{print $2}')
        prev_plan=$(echo "$prev_epic" | grep -oP '^P\d+' || true)
        prev_done_phase=$(grep '^done_phase:' "$prev_state" | awk '{print $2}')
        prev_dir=$(dirname "$prev_state")

        # Only check EPICs from DIFFERENT completed plans
        if [[ -n "$prev_plan" && "$prev_plan" != "$current_plan_prefix" && "$prev_done_phase" == "review" ]]; then
          if [[ -f "${prev_dir}/audit-report.md" && ! -f "${prev_dir}/ca-review-complete" ]]; then
            echo "PRECONDITION FAIL: Plan $prev_plan has unreviewed Curator/Auditor findings." >&2
            echo "EPIC $prev_epic: audit-report exists but ca-review-complete marker missing." >&2
            echo "Review findings, apply S+M+L fixes, then: touch ${prev_dir}/ca-review-complete" >&2
            local timeline
            timeline=$(derive_timeline "$state_file") || true
            [[ -n "$timeline" ]] && log_event "$timeline" "fsm_init_blocked" reason="unreviewed_ca" blocking_epic="$prev_epic" blocking_plan="$prev_plan"
            exit 1
          fi
        fi
      done < <(find .aid-o/work/evidence -name "fsm-state.yaml" 2>/dev/null)
    fi
  fi

  if [[ "$force" == "true" ]]; then
    echo "WARNING: --force used, skipping plan-level DONE gate check" >&2
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

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  if [[ -n "$timeline" ]]; then
    mkdir -p "$(dirname "$timeline")"
    log_event "$timeline" "fsm_init" epic_id="$epic_id" run_id="$run_id" total_steps="$total_steps" mode="$mode"
  fi

  # Validate plan.json step content (warning only)
  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  local plan_json="${evidence_dir}/plan.json"
  if [[ -f "$plan_json" ]] && command -v python3 &>/dev/null; then
    local empty_steps
    empty_steps=$(python3 -c "
import json, sys
try:
    d = json.load(open('$plan_json'))
    steps = d.get('steps', [])
    empty = [s.get('id','?') for s in steps if 'objective' not in s or not s.get('objective')]
    if empty: print(','.join(str(e) for e in empty))
except: pass
" 2>/dev/null || true)
    if [[ -n "$empty_steps" ]]; then
      echo "WARNING: plan.json has steps without 'objective': $empty_steps" >&2
    fi
  fi

  echo "Initialized state: READY" >&2
}

cmd_transition() {
  local from="$1" to="$2" state_file="$3"
  local force="false"
  [[ "${4:-}" == "--force" ]] && force="true"

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

  # Precondition checks (skip with --force)
  if [[ "$force" == "true" ]]; then
    local timeline
    timeline=$(derive_timeline "$state_file") || true
    [[ -n "$timeline" ]] && log_event "$timeline" "fsm_force_override" from="$from" to="$to"
    echo "WARNING: --force used, skipping precondition checks for $from → $to" >&2
  else
    if ! check_preconditions "$from" "$to" "$state_file"; then
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_fail" from="$from" to="$to"
      exit 1
    fi
  fi

  # Increment escalation_count when entering ESCALATION
  if [[ "$to" == "ESCALATION" ]]; then
    local count
    count=$(grep '^escalation_count:' "$state_file" | awk '{print $2}')
    sed -i "s/^escalation_count: .*/escalation_count: $((count + 1))/" "$state_file"
  fi

  # Clear escalation_decision when leaving ESCALATION
  if [[ "$from" == "ESCALATION" ]]; then
    sed -i '/^escalation_decision:/d' "$state_file"
  fi

  # Auto-set done_phase when entering DONE
  if [[ "$to" == "DONE" ]]; then
    # Remove any stale done_phase, then set to review
    sed -i '/^done_phase:/d' "$state_file"
    echo "done_phase: review" >> "$state_file"
  fi

  # Update state (atomic via temp file + mv)
  local tmp_file="${state_file}.tmp"
  sed "s/^state: .*/state: $to/" "$state_file" > "$tmp_file"
  mv "$tmp_file" "$state_file"

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_transition" from="$from" to="$to"

  echo "Transition: $from → $to" >&2
}

cmd_get_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  grep '^state:' "$state_file" | awk '{print $2}'
}

cmd_verify_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo '{"error":"state_file not found"}'; exit 1; }

  local state epic_id run_id current_step total_steps
  state=$(grep '^state:' "$state_file" | awk '{print $2}')
  epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
  run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
  current_step=$(grep '^current_step:' "$state_file" | awk '{print $2}')
  total_steps=$(grep '^total_steps:' "$state_file" | awk '{print $2}')

  # Compute allowed transitions from current state
  local allowed=()
  for t in "${VALID_TRANSITIONS[@]}"; do
    local t_from="${t%%:*}" t_to="${t##*:}"
    [[ "$t_from" == "$state" ]] && allowed+=("\"${t_to}\"")
  done
  local allowed_json="[$(IFS=,; echo "${allowed[*]}")]"

  # Include done_phase if in DONE state
  local done_phase_json=""
  if [[ "$state" == "DONE" ]]; then
    local done_phase
    done_phase=$(grep '^done_phase:' "$state_file" | awk '{print $2}' || echo "unknown")
    done_phase_json=",\"done_phase\":\"${done_phase}\""
  fi

  echo "{\"state\":\"${state}\",\"epic_id\":\"${epic_id}\",\"run_id\":\"${run_id}\",\"current_step\":${current_step},\"total_steps\":${total_steps},\"allowed_transitions\":${allowed_json}${done_phase_json}}"
}

cmd_increment_step() {
  local state_file="$1"
  local force="false"
  [[ "${2:-}" == "--force" ]] && force="true"

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  local step
  step=$(grep '^current_step:' "$state_file" | awk '{print $2}')

  # Precondition: step verification evidence must exist
  if [[ "$force" != "true" ]]; then
    local epic_id run_id evidence_dir
    epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
    run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

    local verify_file="${evidence_dir}/step-${step}-verify.md"
    if [[ ! -f "$verify_file" ]]; then
      echo "PRECONDITION FAIL: Step verification evidence not found." >&2
      echo "Expected: ${verify_file}" >&2
      echo "Write verification (AC checklist + result) before advancing to next step." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="missing_step_verify"
      exit 1
    fi

    # Validate content — must contain explicit PASS result
    if ! grep -q '## Result: PASS' "$verify_file" 2>/dev/null; then
      echo "PRECONDITION FAIL: Step verification does not contain '## Result: PASS'." >&2
      echo "File: ${verify_file}" >&2
      echo "Fix failing AC or mark '## Result: PASS' when all criteria met." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="step_verify_not_pass"
      exit 1
    fi

    # Validate content quality — must contain AC checklist and commit reference
    local ac_count=0 commit_found=0
    ac_count=$(grep -c '\- \[x\]' "$verify_file" 2>/dev/null) || ac_count=0
    commit_found=$(grep -cE '[a-f0-9]{7,}' "$verify_file" 2>/dev/null) || commit_found=0

    if [[ "$ac_count" -lt 1 ]]; then
      echo "PRECONDITION FAIL: Step verification has no acceptance criteria checklist." >&2
      echo "File: ${verify_file}" >&2
      echo "Must contain at least one '- [x] ...' item matching plan AC." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_ac_checklist"
      exit 1
    fi

    if [[ "$commit_found" -lt 1 ]]; then
      echo "PRECONDITION FAIL: Step verification has no commit reference." >&2
      echo "File: ${verify_file}" >&2
      echo "Must contain at least one commit hash (7+ hex chars)." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_commit_ref"
      exit 1
    fi

    # Memory sections — must contain ## Memory Used and ## Memory Written
    if ! grep -qE '^## Memory Used' "$verify_file" 2>/dev/null; then
      echo "PRECONDITION FAIL: Step verification missing '## Memory Used' section." >&2
      echo "File: ${verify_file}" >&2
      echo "List memory entries used (or 'N/A — <reason>' if none applicable)." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_memory_used"
      exit 1
    fi

    if ! grep -qE '^## Memory Written' "$verify_file" 2>/dev/null; then
      echo "PRECONDITION FAIL: Step verification missing '## Memory Written' section." >&2
      echo "File: ${verify_file}" >&2
      echo "List new memory entries proposed (or 'N/A — <reason>' if none applicable)." >&2
      local timeline
      timeline=$(derive_timeline "$state_file") || true
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_memory_written"
      exit 1
    fi
  else
    local timeline
    timeline=$(derive_timeline "$state_file") || true
    [[ -n "$timeline" ]] && log_event "$timeline" "fsm_force_override" action="increment-step" step="$step"
    echo "WARNING: --force used, skipping step verification check" >&2
  fi

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

cmd_set_field() {
  local field="$1" value="$2" state_file="$3"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }

  # Reserved fields — managed by dedicated commands only
  case "$field" in
    state) echo "ERROR: 'state' is reserved — use 'transition' command" >&2; exit 1 ;;
    done_phase) echo "ERROR: 'done_phase' is reserved — use 'done-advance' command" >&2; exit 1 ;;
  esac

  if grep -q "^${field}:" "$state_file"; then
    sed -i "s/^${field}: .*/${field}: ${value}/" "$state_file"
  else
    echo "${field}: ${value}" >> "$state_file"
  fi
}

# ─── DONE Sub-Phase Advancement ─────────────────────────────────────────
# Phases within DONE: review → release
# Preconditions for review → release:
#   - curator-report exists (curator agent ran)
#   - audit-report exists (auditor agent ran)
#   - pm_decision field set to "merge"

VALID_DONE_PHASES="review release"

cmd_done_advance() {
  local from_phase="$1" to_phase="$2" state_file="$3"
  local force="false"
  [[ "${4:-}" == "--force" ]] && force="true"

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found: $state_file" >&2; exit 1; }

  # Must be in DONE state
  local current_state
  current_state=$(grep '^state:' "$state_file" | awk '{print $2}')
  [[ "$current_state" == "DONE" ]] || {
    echo "ERROR: done-advance requires state DONE, found: $current_state" >&2
    exit 1
  }

  # Validate current phase matches
  local current_phase
  current_phase=$(grep '^done_phase:' "$state_file" | awk '{print $2}')
  [[ "$current_phase" == "$from_phase" ]] || {
    echo "ERROR: expected done_phase=$from_phase but found $current_phase" >&2
    exit 1
  }

  # Validate phases
  [[ " $VALID_DONE_PHASES " =~ " $to_phase " ]] || {
    echo "ERROR: invalid done_phase: $to_phase (valid: $VALID_DONE_PHASES)" >&2
    exit 1
  }

  # Precondition checks (skip with --force)
  if [[ "$force" == "true" ]]; then
    local timeline
    timeline=$(derive_timeline "$state_file") || true
    [[ -n "$timeline" ]] && log_event "$timeline" "fsm_force_override" action="done-advance" from_phase="$from_phase" to_phase="$to_phase"
    echo "WARNING: --force used, skipping precondition checks for done-advance $from_phase → $to_phase" >&2
  else
    # Check preconditions for review → release
    if [[ "$from_phase" == "review" && "$to_phase" == "release" ]]; then
      local epic_id run_id evidence_dir errors=0
      epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
      run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
      evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

      # Curator report must exist
      if [[ ! -f "${evidence_dir}/curator-report.yaml" && ! -f "${evidence_dir}/curator-report.md" ]]; then
        echo "PRECONDITION FAIL: Curator report not found in ${evidence_dir}/. Curator agent must run first." >&2
        errors=$((errors + 1))
      fi

      # Auditor report must exist
      if [[ ! -f "${evidence_dir}/audit-report.yaml" && ! -f "${evidence_dir}/audit-report.md" ]]; then
        echo "PRECONDITION FAIL: Auditor report not found in ${evidence_dir}/. Auditor agent must run first." >&2
        errors=$((errors + 1))
      fi

      # PM decision must be set to merge
      local pm_decision
      pm_decision=$(grep '^pm_decision:' "$state_file" | awk '{print $2}' || true)
      [[ "$pm_decision" == "merge" ]] || {
        echo "PRECONDITION FAIL: pm_decision must be 'merge', found: '${pm_decision:-<not set>}'." >&2
        errors=$((errors + 1))
      }

      # EPIC task file must be archived (moved to tasks/archive/)
      local task_file
      task_file=$(find .aid-o/tasks/ -maxdepth 1 -name "${epic_id}*" 2>/dev/null | head -1)
      if [[ -n "$task_file" ]]; then
        echo "PRECONDITION FAIL: EPIC task file still in tasks/ (not archived): $(basename "$task_file")" >&2
        echo "Move to tasks/archive/ before advancing: mv $task_file .aid-o/tasks/archive/" >&2
        errors=$((errors + 1))
      fi

      # Check for P1 security findings in auditor report (blocking)
      local audit_file=""
      [[ -f "${evidence_dir}/audit-report.md" ]] && audit_file="${evidence_dir}/audit-report.md"
      [[ -f "${evidence_dir}/audit-report.yaml" ]] && audit_file="${evidence_dir}/audit-report.yaml"
      if [[ -n "$audit_file" ]]; then
        local p1_count
        p1_count=$(grep -ciE 'P1.*security|security.*P1|kritick.*security|critical.*security' "$audit_file" 2>/dev/null || echo "0")
        if [[ "$p1_count" -gt 0 ]]; then
          echo "PRECONDITION FAIL: Auditor report contains $p1_count P1/critical security finding(s)." >&2
          echo "Address security findings before release. See: $audit_file" >&2
          errors=$((errors + 1))
        fi
      fi

      if [[ $errors -gt 0 ]]; then
        local timeline
        timeline=$(derive_timeline "$state_file") || true
        [[ -n "$timeline" ]] && log_event "$timeline" "fsm_done_advance_fail" from_phase="$from_phase" to_phase="$to_phase" errors="$errors"
        echo "ERROR: ${errors} precondition(s) failed for done-advance $from_phase → $to_phase." >&2
        exit 1
      fi
    fi
  fi

  # Advance phase
  sed -i "s/^done_phase: .*/done_phase: ${to_phase}/" "$state_file"

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_done_advance" from_phase="$from_phase" to_phase="$to_phase"

  echo "Done phase: $from_phase → $to_phase" >&2
}

# ─── Dispatch ───────────────────────────────────────────────────────────
case "${1:-}" in
  init)           shift; cmd_init "$@" ;;
  transition)     shift; cmd_transition "$@" ;;
  get-state)      shift; cmd_get_state "$@" ;;
  verify-state)   shift; cmd_verify_state "$@" ;;
  increment-step) shift; cmd_increment_step "$@" ;;
  get-field)      shift; cmd_get_field "$@" ;;
  set-field)      shift; cmd_set_field "$@" ;;
  done-advance)   shift; cmd_done_advance "$@" ;;
  *)
    echo "Usage: aid-fsm.sh <init|transition|get-state|verify-state|increment-step|get-field|set-field|done-advance> [args...]" >&2
    exit 1 ;;
esac
