#!/usr/bin/env bash
# aid-fsm.sh — AID Orchestrator 6-state FSM controller
# Mechanically enforced: precondition-verified transitions + audit trail
#
# Usage:
#   aid-fsm.sh init <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file> [--force]
#   aid-fsm.sh transition <from> <to> <state_file> [--force]
#   aid-fsm.sh advance-to-gates <state_file>
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

# True if the working tree is a git worktree (git_dir under .git/worktrees/).
# Used by PRE-FLIGHT branch enforcement to skip auto-checkout in worktree mode
# where the caller (e.g., superpowers:using-git-worktrees) controls the branch.
is_worktree() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  [[ "$git_dir" == *.git/worktrees/* ]]
}

# Print a multi-line error to stderr and exit 1.
# Use for unrecoverable PRE-FLIGHT / precondition failures with copy-paste fix.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# ─── P032 Step 3: Grandfather + Repeated-Fail Helpers ────────────────────
# All three read $state_file / $evidence_dir / $epic_id from caller scope
# (matches existing derive_timeline / check_preconditions convention).

# True if state.yaml.created_at predates the current AID deploy threshold.
# Threshold sources (first non-empty wins):
#   1. AID_DEPLOY_DATE env var (set by PM shell rc or per-invocation)
#   2. ${AID_PLUGIN_PATH}/DEPLOY_DATE file (created in Step 9 release)
# If no marker / no threshold → return 1 (fail-safe to post-deploy strict).
# ISO 8601 UTC lex compare works here because both fields use the same
# `date -u +%Y-%m-%dT%H:%M:%SZ` format (Step 2 cmd_init / Step 9 release).
fsm_check_grandfather() {
  local created_at
  created_at=$(grep '^created_at:' "$state_file" 2>/dev/null | awk '{print $2}')
  [[ -z "$created_at" ]] && return 1
  local deploy_date="${AID_DEPLOY_DATE:-}"
  if [[ -z "$deploy_date" && -n "${AID_PLUGIN_PATH:-}" && -f "${AID_PLUGIN_PATH}/DEPLOY_DATE" ]]; then
    deploy_date=$(<"${AID_PLUGIN_PATH}/DEPLOY_DATE")
  fi
  if [[ -z "$deploy_date" && -f "${SCRIPT_DIR}/../DEPLOY_DATE" ]]; then
    deploy_date=$(<"${SCRIPT_DIR}/../DEPLOY_DATE")
  fi
  [[ -z "$deploy_date" ]] && return 1
  [[ "$created_at" < "$deploy_date" ]]
}

# Count prior fsm_precondition_fail events on this EPIC matching from/to/reason.
# Returns 0 (and echoes 0) when timeline is missing — first-attempt safe.
fsm_count_recent_fails() {
  local from=$1 to=$2 reason=$3
  local timeline="${evidence_dir}/timeline.jsonl"
  [[ ! -f "$timeline" ]] && { echo 0; return 0; }
  jq -r --arg f "$from" --arg t "$to" --arg r "$reason" \
     '[inputs | select(.event=="fsm_precondition_fail" and .from==$f and .to==$t and .reason==$r)] | length' \
     -n < "$timeline" 2>/dev/null || echo 0
}

# Count fsm_precondition_fail events for (same step + same reason) — detects
# "this step is structurally problematic" pattern (≥ 3 = step-level repeated fail).
fsm_count_recent_fails_step() {
  local step=$1 reason=$2
  local timeline="${evidence_dir}/timeline.jsonl"
  [[ ! -f "$timeline" ]] && { echo 0; return 0; }
  jq -r --arg s "$step" --arg r "$reason" \
     '[inputs | select(.event=="fsm_precondition_fail" and .step==$s and .reason==$r)] | length' \
     -n < "$timeline" 2>/dev/null || echo 0
}

# Count fsm_precondition_fail events for (same reason, any step) — detects
# "agent systematically bypasses this check across steps" pattern (≥ 3 = EPIC-level).
fsm_count_recent_fails_epic() {
  local reason=$1
  local timeline="${evidence_dir}/timeline.jsonl"
  [[ ! -f "$timeline" ]] && { echo 0; return 0; }
  jq -r --arg r "$reason" \
     '[inputs | select(.event=="fsm_precondition_fail" and .reason==$r)] | length' \
     -n < "$timeline" 2>/dev/null || echo 0
}

# Validate a verifier-output-step-N.md or verifier-output-cp3-{focus}.md file.
# Returns 0 (pass) if file exists + has _generated_by + classification fields.
# For RUN/FAIL classification also requires verdict != "pending" (verifier ran).
fsm_check_verifier_output() {
  local file=$1
  [[ -f "$file" ]] || return 1
  grep -q '^_generated_by:' "$file" || return 1
  grep -q '^classification:' "$file" || return 1

  local classification
  classification=$(grep '^classification:' "$file" | awk '{print $2}')
  case "$classification" in
    SKIP)
      grep -q '^reason:' "$file" || return 1
      ;;
    RUN|FAIL|FULL_REVIEW)
      grep -q '^verdict:' "$file" || return 1
      local verdict
      verdict=$(grep '^verdict:' "$file" | awk '{print $2}')
      [[ "$verdict" == "pending" ]] && return 1  # pre-filter wrote pending; verifier not dispatched
      ;;
    *)
      return 1  # unknown classification
      ;;
  esac
  return 0
}

# Unified dispatcher for --force handling across cmd_init / cmd_transition /
# cmd_increment_step / cmd_done_advance. Validates reason, emits extended
# fsm_force_override timeline event with caller field, and writes persistent
# audit log entry. Reads epic_id, run_id, evidence_dir from caller scope.
fsm_handle_force_override() {
  local from="$1" to="$2" state_file="$3" caller_cmd="$4"
  shift 4
  local reason="" blocked_checks=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --blocked-checks) blocked_checks="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Normalize blocked_checks: strip surrounding commas + whitespace (comma-only delimiter)
  blocked_checks="${blocked_checks// /}"
  blocked_checks="${blocked_checks#,}"
  blocked_checks="${blocked_checks%,}"

  if [[ ${#reason} -lt 20 ]]; then
    die "ERROR: --force requires --reason argument with min 20 characters (got ${#reason}).

Reason: AID v3 telemetry needs forensic-grade audit trail of why FSM was bypassed.
        Empty or short reasons defeat the audit purpose.

Examples:
  aid-fsm.sh transition EXECUTE GATES \$state_file --force --reason \\
    'plan.json bug — step 3 AC has typo blocking gates_no_generated_by check, fix in next EPIC'
  aid-fsm.sh transition GATES DONE \$state_file --force --reason \\
    'security_scan false positive on test fixture, manually verified safe in commit abc1234'
  aid-fsm.sh increment-step \$state_file --force --reason \\
    'step verifier dispatch unavailable due to MCP outage, manually reviewed diff in PR #42'
  aid-fsm.sh done-advance review release \$state_file --force --reason \\
    'auditor agent dispatch failed retry-3, applying P1 finding fix manually'

Then retry with --reason."
  fi

  local timeline="${evidence_dir}/timeline.jsonl"
  local operator="${USER:-unknown}"

  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_force_override" \
    from="$from" to="$to" reason="$reason" \
    caller="$caller_cmd" operator="$operator" \
    blocked_checks="$blocked_checks"

  fsm_emit_audit_log "fsm_force_override" \
    --from "$from" --to "$to" \
    --reason "$reason" --caller "$caller_cmd" --operator "$operator" \
    --blocked-checks-array "$blocked_checks"
}

# Write a single entry to the cross-EPIC audit-log.jsonl (append-only).
# Audit log write failure is best-effort — never aborts primary FSM operation.
fsm_emit_audit_log() {
  local event_type="$1"; shift
  local audit_log_file="${project_root}/.aid-o/work/audit-log.jsonl"
  # project_root may be unset in early init paths — derive from CWD
  audit_log_file="${project_root:-.}/.aid-o/work/audit-log.jsonl"
  bash "${SCRIPT_DIR}/aid-audit-log.sh" append \
    --epic-id "${epic_id:-unknown}" \
    --run-id  "${run_id:-unknown}" \
    --event   "$event_type" \
    "$@" \
    --output  "$audit_log_file" 2>/dev/null || true
}

# P038 Step 3: pure helper that maps a flat checks{} JSON object to a
# failures[] array, looking up severity in the project-level severity
# registry (check-severity.yaml). Returns "[]" when no failures detected or
# yq unavailable / registry file missing — all paths fall through to
# advisory defaults so missing-config is a safe no-op.
#
# Inputs:
#   $1 — checks_json (the JSON object produced by evaluate_compliance_checks)
#   $2 — severity_yaml (absolute path to .aid-o/config/check-severity.yaml)
#
# Behavior:
#   - When checks_json has a .verifier_outputs.provenance_aggregate == "fabricated"
#     marker, a synthetic verifier_provenance failure entry is prepended.
#   - Each boolean-false top-level scalar in checks_json yields one entry.
#   - severity + promoted_at are enriched from the registry; missing keys
#     default to {severity: "advisory", promoted_at: null}.
#   - Output is always a JSON array (even on internal jq error → "[]").
fsm_build_failures() {
  local checks_json="$1" severity_yaml="$2"
  local registry_json='{}'
  local prov_agg_value
  local failures_json='[]'

  # Step A: load registry into a JSON object (best-effort).
  if [[ -f "$severity_yaml" ]]; then
    if command -v yq >/dev/null 2>&1; then
      registry_json=$(yq -o=json eval '.checks // {}' "$severity_yaml" 2>/dev/null || echo '{}')
      # Guard against yq emitting non-JSON on malformed input.
      if ! echo "$registry_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        log_warn "check-severity.yaml parse error — falling back to advisory defaults"
        registry_json='{}'
      fi
    else
      log_warn "yq not installed — failures[] severities default to advisory (install yq to enable per-check severity)"
    fi
  fi

  # Extract provenance_aggregate marker (synthetic verifier_provenance failure trigger).
  prov_agg_value=$(echo "$checks_json" | jq -r '.verifier_outputs.provenance_aggregate // empty' 2>/dev/null || echo "")

  # Step B: build failures[] from boolean-false top-level checks +
  # provenance_aggregate fabricated marker; enrich each entry's severity +
  # promoted_at from the registry, defaulting to advisory when absent.
  failures_json=$(echo "$checks_json" | jq -c \
    --argjson reg "$registry_json" \
    --arg prov_agg "$prov_agg_value" \
    '
    def enrich(entry):
      ($reg[entry.check] // null) as $r |
      entry
      | .severity    = (if $r then ($r.severity    // "advisory") else "advisory" end)
      | .promoted_at = (if $r then ($r.promoted_at // null)       else null       end);

    [
      (to_entries[]
        | select(.value == false)
        | {check: .key,
           severity: "advisory",
           evidence: ("\(.key) returned false"),
           promoted_at: null}
        | enrich(.)),
      (if $prov_agg == "fabricated" then
        {check: "verifier_provenance",
         severity: "advisory",
         evidence: "provenance_aggregate=fabricated (1+ verifier outputs unverifiable)",
         promoted_at: null}
        | enrich(.)
       else empty end)
    ]
    ' 2>/dev/null || echo '[]')

  # Final safety net: if anything went sideways, force empty array.
  if ! echo "$failures_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    failures_json='[]'
  fi

  printf '%s\n' "$failures_json"
}

# Best-effort Telegram alert via svc-mcp-tg-bot HTTP transport (port 8817 —
# replaces the legacy svc-mcp-telegram MCP that previously held this port).
# Never fails — if MCP service is unavailable, log info and continue.
# Service deployed in Step 6; this helper works pre-deploy as a no-op.
#
# Test-mode guard: bats fixtures and other test contexts export AID_TEST_MODE=1
# in their setup() to suppress real-world side effects. The same guard pattern
# should be added to any future side-effect helpers (mail, Slack, webhook).
try_telegram_alert() {
  [[ "${AID_TEST_MODE:-0}" == "1" ]] && return 0
  local message=$1
  local payload
  payload=$(jq -nc --arg t "$message" '{text:$t, parse_mode:"HTML"}')
  if curl -fsS -X POST http://localhost:8817/send_message \
       -H "Content-Type: application/json" \
       --data "$payload" \
       --max-time 3 \
       > /dev/null 2>&1; then
    return 0
  fi
  log_info "Telegram alert skipped (svc-mcp-tg-bot not available — non-fatal)"
  return 0
}

# ─── P032 Step 4: Compliance.json Helpers ────────────────────────────────
# evaluate_compliance_checks emits the 6-dimension `checks` object.
# write_compliance_json wraps it with run metadata + overall verdict + writes
# the per-EPIC compliance.json + emits the `compliance_written` timeline event.

# ─── P037 Step 3: Provenance Verification Helper ──────────────────────────
# verify_provenance cross-references a verifier output's _generated_by/_generated_at
# metadata against the actual dispatch evidence:
#   - subagent mode: timeline.jsonl must show verifier_dispatch_start +
#     verifier_dispatch_complete events for this focus within ±window_s of
#     the claimed _generated_at timestamp.
#   - inline mode: _generated_by must match main-context@<sha>, and the SHA
#     must resolve in the project's git object database.
# Returns one of: "verified", "inline", "fabricated", "unknown".
verify_provenance() {
  # IMP-103 (v2.20.2): $3 (step_n) is intentionally unused — kept in signature for
  # API stability and future per-step forensics (e.g. error-path attribution by
  # step index). Renamed to _step_n to mark unused without shifting positional args
  # at the 3 call sites (CP2 loop + CP3 code-review + CP3 security).
  local verifier_output_file=$1 focus=$2 _step_n=$3 dispatch_mode=$4 timeline_file=$5 window_s=$6

  local generated_by generated_at
  generated_by=$(grep '^_generated_by:' "$verifier_output_file" 2>/dev/null | awk '{print $2}' || echo "")
  generated_at=$(grep '^_generated_at:' "$verifier_output_file" 2>/dev/null | awk '{print $2}' || echo "")

  [[ -z "$generated_by" || -z "$generated_at" ]] && { echo "fabricated"; return; }

  case "$dispatch_mode" in
    subagent)
      # Cross-reference timeline ±window_s
      [[ ! -f "$timeline_file" ]] && { echo "fabricated"; return; }
      local gen_epoch
      gen_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo "0")
      [[ "$gen_epoch" == "0" ]] && { echo "fabricated"; return; }
      local min_epoch=$((gen_epoch - window_s))
      local max_epoch=$((gen_epoch + window_s))

      # TZ=UTC required: jq <1.7 fromdateiso8601 silently honors local TZ even with Z
      # suffix, producing 1-3600s offset on non-UTC hosts (CEST/PST/etc). Discovered
      # during P037 Step 5 bats smoke test (jq 1.6 on CEST host). $min/$max are UTC
      # epochs from `date -d`; force jq to match.
      local start_found complete_found
      start_found=$(TZ=UTC jq -s --arg f "$focus" --argjson min "$min_epoch" --argjson max "$max_epoch" '
        [.[] | select(.event == "verifier_dispatch_start" and .focus == $f and ((.ts | fromdateiso8601) | (. >= $min and . <= $max)))] | length' "$timeline_file" 2>/dev/null || echo "0")
      complete_found=$(TZ=UTC jq -s --arg f "$focus" --argjson min "$min_epoch" --argjson max "$max_epoch" '
        [.[] | select(.event == "verifier_dispatch_complete" and .focus == $f and ((.ts | fromdateiso8601) | (. >= $min and . <= $max)))] | length' "$timeline_file" 2>/dev/null || echo "0")

      if [[ "$start_found" -ge 1 && "$complete_found" -ge 1 ]]; then
        echo "verified"
      else
        echo "fabricated"
      fi
      ;;
    inline)
      # Validate main-context@<sha> format + SHA exists in repo
      if [[ "$generated_by" =~ ^main-context@([a-f0-9]{7,40})$ ]]; then
        local sha="${BASH_REMATCH[1]}"
        if command -v git >/dev/null 2>&1 && git -C "$project_root" cat-file -e "$sha" 2>/dev/null; then
          echo "inline"
        else
          echo "fabricated"
        fi
      else
        echo "fabricated"
      fi
      ;;
    *)
      echo "fabricated"
      ;;
  esac
}

evaluate_compliance_checks() {
  local epic_id=$1 state_file=$2 evidence_dir=$3 project_root=$4

  # P037 Step 3: dispatch_mode resolution (used by verify_provenance below).
  # Defaults: subagent + 60s window if yq missing or fields absent.
  local dispatch_mode timeline_window_s
  dispatch_mode=$(yq -r '.dispatch_mode // "subagent"' "${project_root}/.aid-o/config/plugin.yaml" 2>/dev/null || echo "subagent")
  [[ -z "$dispatch_mode" || "$dispatch_mode" == "null" ]] && dispatch_mode="subagent"
  timeline_window_s=$(yq -r '.dispatch.timeline_window_seconds // 60' "${SCRIPT_DIR}/../defaults/orchestration.yaml" 2>/dev/null || echo "60")
  [[ -z "$timeline_window_s" || "$timeline_window_s" == "null" ]] && timeline_window_s=60

  # branch_correct: state.yaml.branch matches Session A naming convention
  # (^task/E-...). Cross-prefix EPICs (B-051, etc.) report false here — out of
  # Session A scope; Sessions B/C may relax the regex.
  local branch_value branch_correct
  branch_value=$(grep '^branch:' "$state_file" 2>/dev/null | awk '{print $2}')
  if [[ "$branch_value" =~ ^task/E- ]]; then
    branch_correct=true
  else
    branch_correct=false
  fi

  # execution_yaml_present: project-level config exists (eager-created by
  # /aid-init or auto-recovered by aid-fsm.sh init in Step 1).
  local exec_yaml_present
  if [[ -f "${project_root}/.aid-o/config/execution.yaml" ]]; then
    exec_yaml_present=true
  else
    exec_yaml_present=false
  fi

  # gates_generated_by: gates_report.json carries the runner's provenance.
  # Hand-written reports (pre-Session-A pattern) lack this field.
  local gates_report="${evidence_dir}/gates/gates_report.json"
  local gates_genby
  if [[ -f "$gates_report" ]] && jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
    gates_genby=true
  else
    gates_genby=false
  fi

  # Session B: verifier_outputs object schema (CP2 per-step + CP3 code-review + security)
  local cp2_dispatched cp2_verdict cp3_cr_d cp3_cr_v cp3_sec_d cp3_sec_v aggregate

  # P037 Step 3: per-step provenance tracking (parallel to dispatched/verdict).
  local -a cp2_provenances=()
  local cp3_cr_provenance="unknown" cp3_sec_provenance="unknown"

  # CP2 per-step: ALL step-*-verify.md must have a valid verifier-output-step-N.md
  local total_steps cp2_passed cp2_failed
  total_steps=$(find "$evidence_dir" -maxdepth 1 -name "step-*-verify.md" 2>/dev/null | wc -l)
  cp2_passed=0; cp2_failed=0
  for v in "$evidence_dir"/step-*-verify.md; do
    [[ -f "$v" ]] || continue
    local step_n
    step_n=$(basename "$v" | grep -oP '\d+' || true)
    [[ -z "$step_n" ]] && continue
    local vo="${evidence_dir}/verifier-output-step-${step_n}.md"
    if [[ -f "$vo" ]] && grep -q '^_generated_by:' "$vo" 2>/dev/null && grep -q '^classification:' "$vo" 2>/dev/null; then
      cp2_passed=$((cp2_passed + 1))
      local _v_status
      _v_status=$(grep '^verdict:' "$vo" 2>/dev/null | awk '{print $2}' || true)
      [[ "$_v_status" == "fail" ]] && cp2_failed=$((cp2_failed + 1))
      # P037 Step 3: provenance cross-reference for this verifier output
      local _prov
      _prov=$(verify_provenance "$vo" "cp2-step-${step_n}" "$step_n" "$dispatch_mode" "${evidence_dir}/timeline.jsonl" "$timeline_window_s")
      cp2_provenances+=("$_prov")
    else
      # Missing or incomplete verifier output → unknown provenance for this step
      cp2_provenances+=("unknown")
    fi
  done

  if (( total_steps == 0 )); then
    cp2_dispatched=null; cp2_verdict=null
  elif (( cp2_passed == total_steps )); then
    cp2_dispatched=true
    if   (( cp2_failed == 0 ));           then cp2_verdict='"pass"'
    elif (( cp2_failed == total_steps )); then cp2_verdict='"fail"'
    else                                       cp2_verdict='"mixed"'; fi
  else
    cp2_dispatched=false; cp2_verdict=null
  fi

  # CP3 code-review verifier output
  local cp3_cr_file="${evidence_dir}/verifier-output-cp3-code-review.md"
  if [[ -f "$cp3_cr_file" ]] && grep -q '^_generated_by:' "$cp3_cr_file" 2>/dev/null; then
    cp3_cr_d=true
    local _cp3_cr_v
    _cp3_cr_v=$(grep '^verdict:' "$cp3_cr_file" 2>/dev/null | awk '{print $2}' || true)
    cp3_cr_v="\"${_cp3_cr_v:-unknown}\""
    # P037 Step 3: provenance cross-reference
    cp3_cr_provenance=$(verify_provenance "$cp3_cr_file" "cp3-code-review" "null" "$dispatch_mode" "${evidence_dir}/timeline.jsonl" "$timeline_window_s")
  else
    cp3_cr_d=false; cp3_cr_v=null
    cp3_cr_provenance="unknown"
  fi

  # CP3 security verifier output
  local cp3_sec_file="${evidence_dir}/verifier-output-cp3-security.md"
  if [[ -f "$cp3_sec_file" ]] && grep -q '^_generated_by:' "$cp3_sec_file" 2>/dev/null; then
    cp3_sec_d=true
    local _cp3_sec_v
    _cp3_sec_v=$(grep '^verdict:' "$cp3_sec_file" 2>/dev/null | awk '{print $2}' || true)
    cp3_sec_v="\"${_cp3_sec_v:-unknown}\""
    # P037 Step 3: provenance cross-reference
    cp3_sec_provenance=$(verify_provenance "$cp3_sec_file" "cp3-security" "null" "$dispatch_mode" "${evidence_dir}/timeline.jsonl" "$timeline_window_s")
  else
    cp3_sec_d=false; cp3_sec_v=null
    cp3_sec_provenance="unknown"
  fi

  # aggregate: all three dispatched = true; null if CP2 is N/A (0 steps)
  if [[ "$cp2_dispatched" == "true" && "$cp3_cr_d" == "true" && "$cp3_sec_d" == "true" ]]; then
    aggregate=true
  elif [[ "$cp2_dispatched" == "null" ]]; then
    aggregate=null
  else
    aggregate=false
  fi

  # P037 Step 3: per-step CP2 provenance as a JSON array (auditable per step).
  local cp2_prov_array_json
  if (( ${#cp2_provenances[@]} == 0 )); then
    cp2_prov_array_json='[]'
  else
    cp2_prov_array_json=$(printf '%s\n' "${cp2_provenances[@]}" | jq -R . | jq -sc .)
  fi

  # P037 Step 3: provenance_aggregate — worst-of summary across all dispatches.
  #   fabricated > mixed > all_inline > all_verified > all_fabricated (impossible if any verified/inline)
  # Semantics: if any single provenance is "fabricated", aggregate is "fabricated".
  # Else if all non-unknown are "verified" → "all_verified".
  # Else if all non-unknown are "inline" → "all_inline".
  # Else "mixed". If everything is unknown → "unknown".
  local all_verified=true all_inline=true any_fabricated=false any_known=false
  local p
  for p in "${cp2_provenances[@]}" "$cp3_cr_provenance" "$cp3_sec_provenance"; do
    [[ -z "$p" || "$p" == "unknown" ]] && continue
    any_known=true
    [[ "$p" == "fabricated" ]] && any_fabricated=true
    [[ "$p" != "verified" ]] && all_verified=false
    [[ "$p" != "inline" ]] && all_inline=false
  done

  local prov_agg
  if $any_fabricated; then
    prov_agg='"fabricated"'
  elif ! $any_known; then
    prov_agg='"unknown"'
  elif $all_verified; then
    prov_agg='"all_verified"'
  elif $all_inline; then
    prov_agg='"all_inline"'
  else
    prov_agg='"mixed"'
  fi

  # Phase 2 (P037) — plan_ac_match dimension
  local plan_ac_match
  local plan_diff_file="${evidence_dir}/plan-diff.json"

  if [[ -f "$plan_diff_file" ]]; then
    # Single jq read for both fields — /simplify efficiency finding (was 2 forks).
    local overall_verdict ac_count
    IFS=$'\t' read -r overall_verdict ac_count < <(
      jq -r '[(.overall_verdict // ""), (.ac_count // 0)] | @tsv' "$plan_diff_file" 2>/dev/null \
        || printf '\t0'
    )

    if [[ "$ac_count" -eq 0 || "$overall_verdict" == "skipped" ]]; then
      plan_ac_match=null  # graceful skip — legacy plan or no AC patterns
    elif [[ "$overall_verdict" == "pass" ]]; then
      plan_ac_match=true
    elif [[ "$overall_verdict" == "fail" ]]; then
      plan_ac_match=false
    else
      plan_ac_match=null  # unknown verdict — conservative skip
    fi
  else
    plan_ac_match=null  # plan-diff.json missing — backward compat, treated as skip
  fi

  jq -nc \
    --argjson bc          "$branch_correct" \
    --argjson eyp         "$exec_yaml_present" \
    --argjson ggb         "$gates_genby" \
    --argjson pam         "$plan_ac_match" \
    --argjson cp2_d       "$cp2_dispatched" \
    --argjson cp2_v       "$cp2_verdict" \
    --argjson cp2_prov    "$cp2_prov_array_json" \
    --argjson cp3crd      "$cp3_cr_d" \
    --argjson cp3crv      "$cp3_cr_v" \
    --arg     cp3cr_prov  "$cp3_cr_provenance" \
    --argjson cp3secd     "$cp3_sec_d" \
    --argjson cp3secv     "$cp3_sec_v" \
    --arg     cp3sec_prov "$cp3_sec_provenance" \
    --argjson agg         "$aggregate" \
    --argjson prov_agg    "$prov_agg" \
    '{
      branch_correct:         $bc,
      execution_yaml_present: $eyp,
      gates_generated_by:     $ggb,
      plan_ac_match:          $pam,
      memory_substantive:     null,
      verifier_outputs: {
        cp2_per_step_dispatched:    $cp2_d,
        cp2_per_step_verdict:       $cp2_v,
        cp2_per_step_provenance:    $cp2_prov,
        cp3_code_review_dispatched: $cp3crd,
        cp3_code_review_verdict:    $cp3crv,
        cp3_code_review_provenance: $cp3cr_prov,
        cp3_security_dispatched:    $cp3secd,
        cp3_security_verdict:       $cp3secv,
        cp3_security_provenance:    $cp3sec_prov,
        aggregate:                  $agg,
        provenance_aggregate:       $prov_agg
      },
      dod_present: null
    }'
}

write_compliance_json() {
  local epic_id=$1 run_id=$2 state_file=$3 evidence_dir=$4 project_root=$5
  local compliance_file="${evidence_dir}/compliance.json"
  local _timeline="${evidence_dir}/timeline.jsonl"

  # Session B: three-tier deploy_era enum (pre-session-a | post-session-a | post-session-b).
  # Session A hardcoded deploy date; Session B date read from DEPLOY_DATE file (Step 10),
  # far-future fallback until that file is written.
  local deploy_era
  local _created_at _session_a_deploy _session_b_deploy
  _created_at=$(grep '^created_at:' "$state_file" 2>/dev/null | awk '{print $2}')
  _session_a_deploy="2026-05-05T16:37:52Z"
  if [[ -f "${SCRIPT_DIR}/../DEPLOY_DATE" ]]; then
    _session_b_deploy=$(cat "${SCRIPT_DIR}/../DEPLOY_DATE" 2>/dev/null || echo "2099-01-01T00:00:00Z")
  else
    _session_b_deploy="2099-01-01T00:00:00Z"
  fi

  if [[ -z "$_created_at" || "$_created_at" < "$_session_a_deploy" ]]; then
    deploy_era="pre-session-a"
  elif [[ "$_created_at" < "$_session_b_deploy" ]]; then
    deploy_era="post-session-a"
  else
    deploy_era="post-session-b"
  fi

  # force_override fields: count + reasons from this EPIC's timeline.jsonl.
  # M6 fallback: pre-Session-B events have no .reason field → substitute marker
  # string so aggregator can identify them as historical noise (not actionable).
  local force_count force_reasons
  if [[ -f "$_timeline" ]]; then
    force_count=$(jq -s '[.[] | select(.event=="fsm_force_override")] | length' "$_timeline" 2>/dev/null || echo "0")
    force_reasons=$(jq -s '[.[] | select(.event=="fsm_force_override") | (.reason // "<pre-session-b legacy>")]' "$_timeline" 2>/dev/null || echo "[]")
  else
    force_count=0
    force_reasons='[]'
  fi

  local checks
  if ! checks=$(evaluate_compliance_checks "$epic_id" "$state_file" "$evidence_dir" "$project_root" 2>&1); then
    # Fallback: write skeleton so the aggregator can still see this EPIC ran;
    # never abort done-advance because of telemetry — primary release path is
    # what matters.
    log_warn "compliance.json evaluation failed: ${checks}"
    jq -nc \
      --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
      --arg era "$deploy_era" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg note "evaluation failed: ${checks}" \
      --argjson fc "$force_count" \
      --argjson fr "$force_reasons" \
      '{
        epic_id: $epic, run_id: $run, aid_version: $ver,
        deploy_era: $era, evaluated_at: $ts,
        checks: {
          branch_correct: null, execution_yaml_present: null, gates_generated_by: null,
          memory_substantive: null, verifier_outputs: null, dod_present: null
        },
        force_override_count: $fc,
        force_override_reasons: $fr,
        overall: "fail",
        notes: [$note]
      }' > "$compliance_file"
    log_event "$_timeline" "compliance_written" deploy_era="$deploy_era" overall="fail" checks_passed="0" checks_failed="0"
    return 0
  fi

  # overall: check the top-level scalar dimensions + verifier_outputs.aggregate.
  # verifier_outputs is now an object — use type-aware extraction for backward compat
  # with any pre-Session-B compliance.json files that have boolean/null there.
  # null counts as pass (= "not yet measured in this era").
  # Phase 2 (P037): plan_ac_match contributes to overall, null = no impact (skip).
  local overall_pre notes_json
  overall_pre=$(echo "$checks" | jq -r '
    [.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match,
     (.verifier_outputs | if type == "object" then .aggregate else . end)]
    | all(. == true or . == null)
    | if . then "pass" else "fail" end' 2>/dev/null || echo "fail")
  notes_json='[]'

  # P037 Step 3: provenance_aggregate fabricated override — if any verifier output
  # has unverifiable _generated_by metadata, force overall=fail with explanation.
  local prov_agg_value
  prov_agg_value=$(echo "$checks" | jq -r '.verifier_outputs.provenance_aggregate // empty' 2>/dev/null || echo "")
  if [[ "$prov_agg_value" == "fabricated" ]]; then
    overall_pre="fail"
    notes_json=$(jq -nc --arg n "provenance_aggregate: fabricated — at least one verifier output has unverifiable _generated_by metadata" '[$n]')
  fi

  # P038 Step 3: failures[] is built by the shared fsm_build_failures helper
  # so the cmd_done_advance precondition and write_compliance_json share one
  # implementation. Helper is defensive against missing yq / missing registry /
  # malformed yaml — all paths fall through to advisory defaults.
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
  local failures_json
  failures_json=$(fsm_build_failures "$checks" "$severity_yaml")

  jq -nc \
    --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
    --arg era "$deploy_era" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson chks "$checks" \
    --argjson fc "$force_count" \
    --argjson fr "$force_reasons" \
    --argjson fls "$failures_json" \
    --arg     ovr "$overall_pre" \
    --argjson nts "$notes_json" \
    '{
      epic_id: $epic, run_id: $run, aid_version: $ver,
      deploy_era: $era, evaluated_at: $ts,
      checks: $chks,
      failures: $fls,
      force_override_count: $fc,
      force_override_reasons: $fr,
      overall: $ovr,
      notes: $nts
    }' > "$compliance_file" || {
    log_warn "compliance.json write failed for ${compliance_file} — skipping (telemetry is best-effort)"
    return 0
  }

  # Read back overall for the timeline event (avoid duplicate jq computation)
  local overall
  overall=$(jq -r '.overall' "$compliance_file" 2>/dev/null || echo "unknown")

  local checks_passed checks_failed
  checks_passed=$(echo "$checks" | jq '[.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match, (.verifier_outputs | if type == "object" then .aggregate else . end)] | [.[] | select(. == true)] | length')
  checks_failed=$(echo "$checks" | jq '[.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match, (.verifier_outputs | if type == "object" then .aggregate else . end)] | [.[] | select(. == false)] | length')

  log_event "$_timeline" "compliance_written" \
    deploy_era="$deploy_era" overall="$overall" \
    checks_passed="$checks_passed" checks_failed="$checks_failed"
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
        _PRECONDITION_FAIL_REASON="steps_incomplete"
        echo "PRECONDITION FAIL: current_step=${current} < total_steps=${total}. Not all steps completed." >&2
        return 1
      }

      # P032 Step 3: enforce that gates_report.json was produced by aid-run-gates.sh.
      # Hand-written reports lack `_generated_by` and are rejected — closes AID-005
      # (99% of pre-Session-A reports were hand-written with no proof of execution).
      # Pre-deploy EPICs (state.yaml.created_at < AID_DEPLOY_DATE) skip this check
      # via fsm_check_grandfather().
      if ! fsm_check_grandfather; then
        local gates_report="${evidence_dir}/gates/gates_report.json"
        if [[ ! -f "$gates_report" ]] || ! jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
          _PRECONDITION_FAIL_REASON="gates_no_generated_by"
          local attempt_count
          attempt_count=$(fsm_count_recent_fails "$from" "$to" "gates_no_generated_by")
          if (( attempt_count >= 3 )); then
            local timeline="${evidence_dir}/timeline.jsonl"
            log_event "$timeline" "fsm_precondition_repeated_fail" \
              from="$from" to="$to" reason="gates_no_generated_by" attempt_count="$attempt_count"
            try_telegram_alert "Repeated precondition fail (×${attempt_count}): EPIC=${epic_id}, transition=${from}→${to}, reason=gates_no_generated_by"
          fi
          cat <<EOF >&2
PRECONDITION FAIL: gates_report.json missing _generated_by field.

Reason: AID v3 requires gates to be executed by aid-run-gates.sh, not
        hand-written. The _generated_by/_generated_at/_command_log fields
        produced by the runner are forensic evidence the gates actually ran.

Recommended fix (v2.18.3+): use the atomic advance-to-gates command which runs
gates and commits the transition in a single step:

  rm ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates ${state_file}

Manual two-step alternative (debugging / crash recovery):

  rm ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all \\
    \$AID_PROJECT_ROOT/.aid-o/config/execution.yaml ${epic_id} ${run_id} \\
    --state-file ${state_file} \\
    --report-file ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh transition EXECUTE GATES ${state_file}
EOF
          return 1
        fi

        # Session B CP3: verifier-output-cp3 preconditions (file presence + valid _generated_by)
        local cp3_code_review="${evidence_dir}/verifier-output-cp3-code-review.md"
        local cp3_security="${evidence_dir}/verifier-output-cp3-security.md"

        if ! fsm_check_verifier_output "$cp3_code_review"; then
          _PRECONDITION_FAIL_REASON="missing_cp3_code_review"
          cat <<EOF >&2
PRECONDITION FAIL: verifier-output-cp3-code-review.md missing or invalid.

Reason: AID v3 Session B requires CP3 integration review before EXECUTE→GATES.
        Both verifiers (code-review + security) must review the full EPIC diff.

Fix: Dispatch TWO verifiers in parallel (single message, two Agent tool calls):
     a. subagent_type: aid-orchestrator:verifier, focus: code-review
     b. subagent_type: aid-orchestrator:verifier, focus: security
     Each writes its verifier-output-cp3-{focus}.md with _generated_by + verdict.
Then retry: aid-fsm.sh transition EXECUTE GATES ${state_file}
EOF
          return 1
        fi

        if ! fsm_check_verifier_output "$cp3_security"; then
          _PRECONDITION_FAIL_REASON="missing_cp3_security"
          cat <<EOF >&2
PRECONDITION FAIL: verifier-output-cp3-security.md missing or invalid.

Reason: CP3 requires BOTH code-review AND security verifier outputs.
        Security verifier must also be dispatched (mandatory).
Fix: dispatch security verifier (see code-review error above for full instructions).
EOF
          return 1
        fi
      fi
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

  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

  # Phase 2 (P037) — parse optional named flags after 7 positional args.
  # Detect --plan <path> and --force in either order ($8/$9). Both are optional.
  local plan_path_arg=""
  local force="false"
  local i=8
  while [[ $i -le $# ]]; do
    case "${!i}" in
      --plan)
        i=$((i + 1))
        plan_path_arg="${!i:-}"
        ;;
      --plan=*)
        plan_path_arg="${!i#--plan=}"
        ;;
      --force)
        # Forwards ${@:i+1}; callers must pass --plan before --force when both present
        # (fsm_handle_force_override consumes remaining args as reason payload).
        fsm_handle_force_override "plan-gate" "skip" "$state_file" "init" "${@:i+1}"
        force="true"
        ;;
      *)
        # Unknown flag at this position — preserved as before; existing callers don't
        # pass anything past $8 unless it's --force, so safe to ignore here.
        ;;
    esac
    i=$((i + 1))
  done

  # P032 Step 9 (deps doc layer extension): preflight guard for jq + git.
  # cmd_init writes JSON timeline events (jq) and runs PRE-FLIGHT branch
  # enforcement (git). Without these, downstream calls fail with cryptic
  # messages; fail fast with concrete install hint.
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git not installed. Install: apt install git / brew install git" >&2
    echo "Run: bash \$AID_PLUGIN_PATH/scripts/aid-check-deps.sh  for full dependency report." >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not installed. Install: apt install jq / brew install jq" >&2
    echo "Run: bash \$AID_PLUGIN_PATH/scripts/aid-check-deps.sh  for full dependency report." >&2
    exit 1
  fi

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

  # ─── PRE-FLIGHT: Branch Enforcement (P032 Step 2) ────────────────────
  # Closes AID-001 (65% of pre-Session-A state.yaml claimed branch=main with
  # no actual task branch, breaking done-advance git merge audit trail).
  #
  # Five HEAD states handled:
  #   worktree    → skip enforcement (caller controls branch)
  #   resume      → HEAD == task/E-{epic_id}/main → log_info, accept
  #   fresh init  → HEAD ∈ {main, master, develop} → auto-checkout
  #   mismatch    → HEAD == task/<other_epic>/main → emit event, hard fail
  #   unusual     → anything else (feat/*, detached, ...) → warn, accept
  #
  # Timeline events for forensic visibility:
  #   fsm_branch_mismatch_detected (hard fail case)
  #   fsm_branch_unusual_detected  (warn case)
  local timeline_path=".aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl"
  mkdir -p "$(dirname "$timeline_path")"

  if is_worktree; then
    log_info "Worktree mode detected (git_dir under .git/worktrees/) — skipping branch enforcement"
  else
    local current_branch expected_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "Not in a git repository"
    expected_branch="task/${epic_id}/main"

    case "$current_branch" in
      "$expected_branch")
        log_info "Resume case: HEAD already on $expected_branch"
        ;;
      main|master|develop)
        log_info "Auto-creating branch: $expected_branch"
        git checkout -b "$expected_branch" >/dev/null 2>&1 \
          || die "Failed to create branch $expected_branch (check 'git status' for details)"
        ;;
      task/E-*)
        # Different EPIC's task branch — stale workspace from prior session.
        log_event "$timeline_path" "fsm_branch_mismatch_detected" \
          current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
        die "ERROR: Currently on $current_branch, expected $expected_branch.

Reason: AID v3 requires one task branch per EPIC for clean audit trail.
        Different-EPIC branches indicate stale workspace from prior session.

Fix: git checkout main && git branch -d $current_branch
Then retry: aid-fsm.sh init ${epic_id} ..."
        ;;
      *)
        # feat/*, refactor/*, detached HEAD, any non-task pattern.
        # PM context-aware (e.g., manual exploration on feat/ branch) — accept with warning.
        log_event "$timeline_path" "fsm_branch_unusual_detected" \
          current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
        log_warn "Unusual branch: $current_branch (expected $expected_branch). Continuing — PM-controlled context assumed."
        ;;
    esac
  fi

  # Uncommitted changes guard (always runs, even in worktree mode).
  # PRE-FLIGHT must start from clean tree so done-advance merge has a clear
  # diff to attribute to the EPIC.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "Uncommitted changes present. Commit or stash before init:
       git status   # review
       git stash    # or commit"
  fi

  # C3 (PM-authorized): override caller's branch param ($5) with actual git
  # state. Caller convention is to pass 'main' as a placeholder; what matters
  # downstream is the branch we actually ended up on (after auto-checkout or
  # in worktree mode). state.yaml.branch reflects post-enforcement reality.
  local actual_branch
  actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$branch")
  branch="$actual_branch"

  # Auto-recover execution.yaml if missing (P032 Step 1).
  # Empty-stacks fallback is harmless and idempotent — pre-deploy projects keep
  # their custom config (the [[ ! -f ... ]] guard ensures we never overwrite).
  if [[ ! -f .aid-o/config/execution.yaml ]] && [[ -f "${SCRIPT_DIR}/lib/aid-init-execution-yaml.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/aid-init-execution-yaml.sh"
    local -a _aid_stacks=()
    mapfile -t _aid_stacks < <(detect_stacks "$PWD")
    if compose_execution_yaml "$PWD" ".aid-o/config/execution.yaml" "${_aid_stacks[@]}"; then
      log_info "Lazy-created .aid-o/config/execution.yaml with stacks: ${_aid_stacks[*]:-none}"
    fi
  fi

  mkdir -p "$(dirname "$state_file")"
  local _now_iso
  _now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
started_at: "${_now_iso}"
created_at: ${_now_iso}
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

  # Session B: stamp plan.json sha256 for mid-EPIC tampering detection.
  # Additive key — existing readers tolerate unknown keys via grep-awk pattern.
  if [[ -f "${evidence_dir}/plan.json" ]]; then
    local plan_hash
    plan_hash=$(sha256sum "${evidence_dir}/plan.json" | awk '{print $1}')
    echo "plan_json_hash: $plan_hash" >> "$state_file"
  fi

  # Phase 2 (P037) — write plan_path field with realpath-normalized absolute path or null.
  # Gate command runs via bash -c from unknown cwd; we need absolute paths so
  # aid-plan-diff.sh receives a usable --plan argument. "null" = Fast Mode (no plan).
  local plan_path_value="null"
  if [[ -n "$plan_path_arg" ]]; then
    plan_path_value=$(realpath "$plan_path_arg" 2>/dev/null || echo "$plan_path_arg")
  fi
  echo "plan_path: $plan_path_value" >> "$state_file"

  echo "Initialized state: READY" >&2
}

cmd_transition() {
  local from="$1" to="$2" state_file="$3"
  local force="false"
  if [[ "${4:-}" == "--force" ]]; then
    local epic_id run_id evidence_dir
    epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
    run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    fsm_handle_force_override "$from" "$to" "$state_file" "transition" "${@:5}"
    force="true"
  fi

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
    echo "WARNING: --force used, skipping precondition checks for $from → $to" >&2
  else
    # P032 Step 3: check_preconditions sets _PRECONDITION_FAIL_REASON before
    # returning 1; we surface it in the timeline event so fsm_count_recent_fails
    # can group repeated failures by reason.
    _PRECONDITION_FAIL_REASON=""
    if ! check_preconditions "$from" "$to" "$state_file"; then
      local timeline reason
      timeline=$(derive_timeline "$state_file") || true
      reason="${_PRECONDITION_FAIL_REASON:-unspecified}"
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_fail" \
        from="$from" to="$to" reason="$reason"
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

# Atomic gates run + EXECUTE→GATES transition (P035 Phase 1, v2.18.3).
# Eliminates the chicken-egg precondition fail mode (gates_no_generated_by)
# observed in P020 (8×) and P021 (4×). Routes through cmd_transition for full
# precondition validation — single source of truth remains check_preconditions.
# Atomicity: state changes only on full success path; gates failure leaves
# state at EXECUTE (never modified).
cmd_advance_to_gates() {
  local state_file="${1:?state_file required}"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state file not found: $state_file" >&2; exit 1; }

  local epic_id run_id current_state current_step total_steps evidence_dir timeline
  epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
  run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
  current_state=$(grep '^state:' "$state_file" | awk '{print $2}')
  current_step=$(grep '^current_step:' "$state_file" | awk '{print $2}')
  total_steps=$(grep '^total_steps:' "$state_file" | awk '{print $2}')
  evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  timeline=$(derive_timeline "$state_file") || true

  # Validate numeric step fields (defensive — malformed state.yaml caught early).
  if [[ ! "$current_step" =~ ^[0-9]+$ ]] || [[ ! "$total_steps" =~ ^[0-9]+$ ]]; then
    echo "ERROR: malformed state.yaml — current_step=$current_step total_steps=$total_steps must be integers" >&2
    exit 1
  fi

  # Cheap pre-flight guards (avoid invoking runner if obvious mismatch).
  if [[ "$current_state" != "EXECUTE" ]]; then
    echo "ERROR: advance-to-gates requires state==EXECUTE, found: $current_state" >&2
    exit 1
  fi
  if (( current_step < total_steps )); then
    echo "ERROR: advance-to-gates requires current_step ($current_step) >= total_steps ($total_steps). Not all steps completed." >&2
    exit 1
  fi

  # Resolve execution.yaml + report path (matches /aid-run gate dispatch convention).
  local execution_yaml="${AID_PROJECT_ROOT:-$(pwd)}/.aid-o/config/execution.yaml"
  if [[ ! -f "$execution_yaml" ]]; then
    echo "ERROR: execution.yaml not found at $execution_yaml. Set AID_PROJECT_ROOT or cd to project root." >&2
    exit 1
  fi
  local report_file="${evidence_dir}/gates/gates_report.json"

  # Emit pre-gates audit event (gate runner is about to start).
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_pre_gates" \
    epic_id="$epic_id" run_id="$run_id" \
    execution_yaml="$execution_yaml" report_file="$report_file"

  # Invoke runner with explicit FSM signal — Step 2 makes runner accept this.
  local rc=0
  AID_GATES_TRIGGERED_BY_FSM=1 \
    "${SCRIPT_DIR}/aid-run-gates.sh" run-all \
      "$execution_yaml" "$epic_id" "$run_id" \
      --state-file "$state_file" \
      --report-file "$report_file" \
    || rc=$?

  if (( rc == 0 )); then
    # Gates passed — route through cmd_transition for full precondition validation.
    # check_preconditions re-validates _generated_by, CP3 outputs, grandfather logic.
    # The runner just wrote gates_report.json with _generated_by, so the check passes.
    if cmd_transition EXECUTE GATES "$state_file"; then
      echo "advance-to-gates: SUCCESS — gates passed, state=GATES"
      return 0
    else
      # Surface cmd_transition error to user; state stays EXECUTE (transition didn't commit).
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_advance_to_gates_fail" \
        reason="transition_check_failed_after_gates_pass" runner_exit="$rc"
      echo "ERROR: advance-to-gates: gates passed but cmd_transition refused — see error above" >&2
      return 1
    fi
  else
    # Gates failed — state was never modified, leave at EXECUTE.
    [[ -n "$timeline" ]] && log_event "$timeline" "fsm_advance_to_gates_fail" \
      reason="gates_runner_exit_${rc}" runner_exit="$rc"
    echo "advance-to-gates: FAIL — gates runner exit=$rc, state unchanged (EXECUTE)" >&2
    return "$rc"
  fi
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

    # Session B CP2: verifier-output-step-N.md precondition
    if ! fsm_check_grandfather; then
      local verifier_output="${evidence_dir}/verifier-output-step-${step}.md"

      if ! fsm_check_verifier_output "$verifier_output"; then
        local timeline
        timeline=$(derive_timeline "$state_file") || true

        # Repeated-fail telemetry (step-level and epic-level)
        local attempt_step attempt_epic
        attempt_step=$(fsm_count_recent_fails_step "$step" "missing_verifier_output")
        attempt_epic=$(fsm_count_recent_fails_epic "missing_verifier_output")

        if (( attempt_step >= 3 )); then
          [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_repeated_fail_step" \
            step="$step" precondition="missing_verifier_output" attempt_count="$attempt_step"
          try_telegram_alert "Repeated step-level precondition fail (×${attempt_step}): EPIC=${epic_id}, step=${step}, precondition=missing_verifier_output"
        fi
        if (( attempt_epic >= 3 )); then
          [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_repeated_fail_epic" \
            precondition="missing_verifier_output" attempt_count="$attempt_epic"
          try_telegram_alert "Systematic precondition bypass (×${attempt_epic}): EPIC=${epic_id}, precondition=missing_verifier_output across multiple steps"
        fi

        [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_fail" \
          step="$step" reason="missing_verifier_output"

        die "ERROR: verifier-output-step-${step}.md missing or invalid.

Reason: AID v3 Session B requires per-step verifier dispatch (CP2). The pre-filter
        classifies the step diff as SKIP/RUN/FAIL; for RUN/FAIL a verifier subagent
        must run and update the output file before this increment.

Fix:
  1. bash \$AID_PLUGIN_PATH/scripts/aid-prefilter.sh classify ${step} ${evidence_dir}
  2. Based on exit code: 0=skip (already done), 10=run code-review verifier, 20=run security verifier
  3. If RUN/FAIL, dispatch: subagent_type=aid-orchestrator:verifier with appropriate focus
     Verifier writes verdict + findings to ${verifier_output}
  4. Retry: aid-fsm.sh increment-step ${state_file}"
      fi
    fi

    # Session B: mid-EPIC plan.json tampering check (PM Q2 refinement #2)
    local stored_hash current_hash
    stored_hash=$(grep '^plan_json_hash:' "$state_file" | awk '{print $2}') || true
    if [[ -n "$stored_hash" && -f "${evidence_dir}/plan.json" ]]; then
      current_hash=$(sha256sum "${evidence_dir}/plan.json" | awk '{print $1}')
      if [[ "$stored_hash" != "$current_hash" ]]; then
        die "ERROR: plan.json hash mismatch — modified mid-EPIC.
Reason: Mid-EPIC plan.json edits could expand step.outputs to allow scope creep.
        plan.json hash at init: ${stored_hash}
        plan.json hash now:     ${current_hash}
Fix: revert plan.json to init state, OR re-init EPIC if changes are legitimate."
      fi
    fi
  else
    local epic_id run_id evidence_dir
    epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
    run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    fsm_handle_force_override "step-${step}" "step-$((step + 1))" "$state_file" "increment-step" "${@:3}"
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
    local epic_id run_id evidence_dir
    local project_root="$PWD"
    epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
    run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    fsm_handle_force_override "$from_phase" "$to_phase" "$state_file" "done-advance" "${@:5}"
    echo "WARNING: --force used, skipping precondition checks for done-advance $from_phase → $to_phase" >&2
  else
    # Check preconditions for review → release
    if [[ "$from_phase" == "review" && "$to_phase" == "release" ]]; then
      local epic_id run_id evidence_dir errors=0
      local project_root="$PWD"
      epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
      run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
      evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

      # P038 Step 3: tiered severity blocking precondition.
      # Runs ONLY for review→release transition (other done-advance phases unchanged).
      # Evaluates compliance checks inline (no file write), filters severity:blocking
      # failures via the shared fsm_build_failures helper, and aborts with exit 2 +
      # structured error message when any blocking failure is detected.
      # Soft-fail design: missing check-severity.yaml / missing yq / telemetry
      # crash all degrade to "no blocking failures detected" — release proceeds.
      # See AID-v3-principles.md §1 (Detector without Enforcement is Decoration).
      local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
      local _checks_json _failures_json _blocking_count
      if _checks_json=$(evaluate_compliance_checks "$epic_id" "$state_file" "$evidence_dir" "$project_root" 2>/dev/null); then
        _failures_json=$(fsm_build_failures "$_checks_json" "$severity_yaml")
        _blocking_count=$(echo "$_failures_json" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo "0")

        if [[ "${_blocking_count:-0}" -gt 0 ]]; then
          # Persist compliance.json so the failed release leaves an audit trail.
          # Best-effort: write failure is non-fatal (telemetry over correctness).
          write_compliance_json "$epic_id" "$run_id" "$state_file" "$evidence_dir" "$project_root" 2>/dev/null || true

          local _blocking_list _blocking_names
          # MEDIUM-2 trust boundary: _blocking_names and _blocking_list derive from
          # failures[] in compliance.json (generated by FSM, not user input). Safe to echo.
          # Registry key names are constrained by the alphanumeric+underscore pattern
          # validated in cmd_promote_check. If future check names flow from user input,
          # this heredoc would need printf '%q' escaping.
          _blocking_list=$(echo "$_failures_json" | jq -r '
            [.[] | select(.severity == "blocking")] |
            to_entries[] |
            "  [\(.key + 1)] check=\(.value.check) severity=\(.value.severity)\n      evidence: \(.value.evidence)\n      promoted_at: \(.value.promoted_at // "unknown")"' 2>/dev/null || echo "  (failure list unavailable)")
          _blocking_names=$(echo "$_failures_json" | jq -r '[.[] | select(.severity == "blocking") | .check] | join(",")' 2>/dev/null || echo "")

          cat >&2 <<EOF
ERROR: ${_blocking_count} blocking compliance failure(s) detected — cannot advance to release.

${_blocking_list}

Fix: address root cause (re-dispatch verifier subagents OR fix dispatch_mode config OR
correct missing AC evidence), then retry:
  aid-fsm.sh done-advance review release ${state_file}

OR (PM-authorized override, audited):
  aid-fsm.sh done-advance review release ${state_file} \\
    --force \\
    --reason '<≥20 chars explaining why this is acceptable>' \\
    --blocked-checks '${_blocking_names}'

Audit log entry will be appended to .aid-o/work/audit-log.jsonl with the full reason
and blocked_checks list. See AID-v3-principles.md §1 for the enforcement contract.
EOF

          try_telegram_alert "🛑 ${epic_id}: ${_blocking_count} blocking compliance failure(s) — release blocked. Checks: ${_blocking_names}"

          local _timeline="${evidence_dir}/timeline.jsonl"
          [[ -f "$_timeline" ]] && log_event "$_timeline" "fsm_done_advance_blocked" \
            blocking_count="$_blocking_count" blocked_checks="$_blocking_names"

          exit 2
        fi
      fi
      # End P038 Step 3 block. Falls through to existing curator/auditor checks.

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
        # Use `|| true` to prevent set -euo pipefail from aborting on grep exit 1 (0 matches).
        # grep -c exits 1 and prints "0" when no lines match; || true ensures compound exits 0.
        # The ${:-0} guard covers any edge case where grep produces empty output.
        p1_count=$(grep -ciE 'P1.*security|security.*P1|kritick.*security|critical.*security' "$audit_file" 2>/dev/null || true)
        p1_count="${p1_count:-0}"
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

  # P032 Step 4 (PM-authorized C4): write compliance.json after sed updates
  # done_phase=release. evaluate_compliance_checks reads post-enforcement
  # state.yaml.branch (set by Step 2 cmd_init) and the gate runner's
  # provenance fields (set by Step 3 aid-run-gates.sh). Hook is best-effort
  # — failures inside write_compliance_json log_warn but never abort the
  # release path.
  if [[ "$to_phase" == "release" ]]; then
    local epic_id run_id evidence_dir project_root
    epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}')
    run_id=$(grep '^run_id:' "$state_file" | awk '{print $2}')
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    project_root="$PWD"
    write_compliance_json "$epic_id" "$run_id" "$state_file" "$evidence_dir" "$project_root"

    # IMP-090: best-effort epic-summary.md generation after compliance write.
    # Failure logs a warning but never aborts the release path.
    bash "$SCRIPT_DIR/aid-epic-summary.sh" generate "$evidence_dir" \
      2>/dev/null || log_warn "epic-summary.md generation failed (non-fatal)"
  fi

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_done_advance" from_phase="$from_phase" to_phase="$to_phase"

  echo "Done phase: $from_phase → $to_phase" >&2
}

# ─── Severity promotion (P038 Step 4) ───────────────────────────────────
# Closes the loop on AID-v3-principles.md §1 tiered-severity caveat:
# advisory checks may be promoted to blocking once they demonstrate clean
# operation. `promote-check` is the auditable mutator (writes the registry
# + appends a check_promoted audit-log event). `check-promotion-candidates`
# is the read-only observer (deterministic table; PM judgment input).
# Both touch project-level state (.aid-o/config/check-severity.yaml +
# .aid-o/work/audit-log.jsonl) — NOT FSM state.

# Promote a check from advisory → blocking severity.
# Writes .aid-o/config/check-severity.yaml in place via `yq -i`, appends a
# check_promoted event to audit-log.jsonl. Exits 0 if already blocking
# (idempotent). Requires --reason flag with min 20 characters.
cmd_promote_check() {
  local check_name="${1:-}" flag="${2:-}" reason="${3:-}"

  [[ -z "$check_name" ]] && {
    echo "Usage: aid-fsm.sh promote-check <check_name> --reason '<text ≥20 chars>'" >&2
    exit 1
  }
  [[ "$flag" != "--reason" ]] && {
    echo "ERROR: missing --reason flag" >&2
    exit 1
  }
  [[ ${#reason} -lt 20 ]] && {
    echo "ERROR: --reason must be ≥20 characters (got ${#reason})" >&2
    exit 2
  }

  # Validate check_name against alphanumeric+underscore pattern (defense in depth).
  # Registry keys must be stable identifiers; reject path traversal or shell metacharacters.
  [[ "$check_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
    echo "ERROR: check_name must match ^[a-zA-Z_][a-zA-Z0-9_]*$ (got '$check_name')" >&2
    exit 1
  }

  local project_root="$PWD"
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"

  [[ -f "$severity_yaml" ]] || {
    echo "ERROR: $severity_yaml not found — run /aid-init upgrade first" >&2
    exit 1
  }
  command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq required for promote-check" >&2
    exit 1
  }

  # Escape reason for safe yq interpolation: replace backslash, double-quote, newline.
  # P038 CP3 security finding CRITICAL-1: Prevent yq expression injection via --reason.
  # check_name is already validated against ^[a-zA-Z_][a-zA-Z0-9_]*$, so safe for interpolation.
  local reason_escaped="${reason//\\/\\\\}"  # Escape backslash first
  reason_escaped="${reason_escaped//\"/\\\"}"  # Escape double-quote
  reason_escaped="${reason_escaped//$'\n'/\\n}"  # Escape newline

  local exists
  exists=$(yq -r ".checks | has(\"${check_name}\")" "$severity_yaml" 2>/dev/null || echo "false")
  [[ "$exists" == "true" ]] || {
    echo "ERROR: check '${check_name}' not in registry. Add to ${severity_yaml} first." >&2
    exit 1
  }

  local previous_severity today
  previous_severity=$(yq -r ".checks.${check_name}.severity" "$severity_yaml" 2>/dev/null || echo "advisory")
  today=$(date -u +%Y-%m-%d)

  if [[ "$previous_severity" == "blocking" ]]; then
    local already_at
    already_at=$(yq -r ".checks.${check_name}.promoted_at // \"unknown\"" "$severity_yaml" 2>/dev/null || echo "unknown")
    echo "INFO: ${check_name} is already severity:blocking (promoted_at: ${already_at})" >&2
    exit 0
  fi

  # Update registry with escaped reason.
  # TOCTOU note (MEDIUM-1): yq -i is not atomic; concurrent promote-check invocations
  # on the same check can race. Mitigate via single-operator convention + audit-log.
  # Future: wrap under flock(3) on severity.yaml.lock if multi-operator concurrency required.
  yq -i ".checks.${check_name}.severity = \"blocking\" |
         .checks.${check_name}.promoted_at = \"${today}\" |
         .checks.${check_name}.promoted_reason = \"${reason_escaped}\"" "$severity_yaml" || {
    echo "ERROR: yq write to ${severity_yaml} failed" >&2
    exit 1
  }

  local operator="${USER:-unknown}"
  fsm_emit_audit_log "check_promoted" \
    --check "$check_name" \
    --previous-severity "$previous_severity" \
    --new-severity "blocking" \
    --reason "$reason" \
    --operator "$operator"

  echo "Promoted: ${check_name} severity ${previous_severity} → blocking (reason logged to audit-log.jsonl)" >&2
}

# Scan audit-log.jsonl + compliance.json across EPICs to identify advisory
# checks that meet the AID-v3-principles.md §1 promotion criterion:
#   epic_count >= 5 AND force_override_rate < 0.05
# Read-only: prints a text table. PM eyes-on input for `promote-check`.
cmd_check_promotion_candidates() {
  local project_root="$PWD"
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
  local audit_log="${project_root}/.aid-o/work/audit-log.jsonl"

  [[ -f "$severity_yaml" ]] || {
    echo "ERROR: $severity_yaml not found" >&2
    exit 0
  }

  command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq required" >&2
    exit 0
  }
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq required" >&2
    exit 0
  }

  local advisory_checks
  advisory_checks=$(yq -r '.checks | to_entries | map(select(.value.severity == "advisory")) | .[].key' "$severity_yaml" 2>/dev/null || true)

  printf "%-40s %12s %16s %8s %s\n" "check" "epic_count" "override_count" "rate" "candidate"
  printf "%-40s %12s %16s %8s %s\n" "----------------------------------------" "------------" "----------------" "--------" "---------"

  if [[ -z "$advisory_checks" ]]; then
    echo
    echo "(no advisory checks in registry — nothing to evaluate)"
    echo
    echo "Promotion criterion: epic_count >= 5 AND rate < 0.05 (per AID-v3-principles.md §1)"
    echo "To promote: aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'"
    return 0
  fi

  while IFS= read -r check; do
    [[ -z "$check" ]] && continue

    # epic_count = distinct EPICs whose compliance.json failures[] contains $check
    local epic_count=0
    if [[ -d ".aid-o/work/evidence" ]]; then
      epic_count=$(find .aid-o/work/evidence -maxdepth 3 -name 'compliance.json' 2>/dev/null \
        | while read -r f; do
            jq -r --arg c "$check" 'select((.failures // []) | map(.check) | index($c)) | .epic_id // empty' "$f" 2>/dev/null || true
          done \
        | sort -u | grep -c -v '^$' || true)
      epic_count="${epic_count:-0}"
    fi

    # override_count = audit-log.jsonl entries with event=fsm_force_override AND blocked_checks contains $check
    local override_count=0
    if [[ -f "$audit_log" ]]; then
      override_count=$(jq -s --arg c "$check" '[.[] | select(.event == "fsm_force_override" and ((.blocked_checks // []) | index($c)))] | length' "$audit_log" 2>/dev/null || echo "0")
      override_count="${override_count:-0}"
    fi

    local rate="0.00"
    local candidate="no"
    if [[ "$epic_count" -ge 5 ]]; then
      rate=$(awk -v o="$override_count" -v e="$epic_count" 'BEGIN { printf "%.2f", o/e }')
      if awk -v r="$rate" 'BEGIN { exit !(r < 0.05) }'; then
        candidate="yes"
      fi
    fi

    printf "%-40s %12s %16s %8s %s\n" "$check" "$epic_count" "$override_count" "$rate" "$candidate"
  done <<< "$advisory_checks"

  echo
  echo "Promotion criterion: epic_count >= 5 AND rate < 0.05 (per AID-v3-principles.md §1)"
  echo "To promote: aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'"
}

# ─── Dispatch ───────────────────────────────────────────────────────────
# BASH_SOURCE guard (v2.20.2 — IMP-followup, same pattern as aid-stage-log.sh:78):
# only dispatch when invoked directly (`bash aid-fsm.sh <cmd>`). When sourced
# (`source aid-fsm.sh`), skip the case so test fixtures (e.g. test-anti-
# fabrication.bats `_load_aid_fsm` shim) can pull in cmd_* + verify_provenance
# functions without the unknown-arg exit 1 killing the test process.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    init)              shift; cmd_init "$@" ;;
    transition)        shift; cmd_transition "$@" ;;
    advance-to-gates)  shift; cmd_advance_to_gates "$@" ;;
    get-state)         shift; cmd_get_state "$@" ;;
    verify-state)      shift; cmd_verify_state "$@" ;;
    increment-step)    shift; cmd_increment_step "$@" ;;
    get-field)         shift; cmd_get_field "$@" ;;
    set-field)         shift; cmd_set_field "$@" ;;
    done-advance)               shift; cmd_done_advance "$@" ;;
    promote-check)              shift; cmd_promote_check "$@" ;;
    check-promotion-candidates) shift; cmd_check_promotion_candidates "$@" ;;
    *)
      echo "Usage: aid-fsm.sh <init|transition|advance-to-gates|get-state|verify-state|increment-step|get-field|set-field|done-advance|promote-check|check-promotion-candidates> [args...]" >&2
      exit 1 ;;
  esac
fi
