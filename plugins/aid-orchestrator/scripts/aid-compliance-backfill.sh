#!/usr/bin/env bash
# aid-compliance-backfill.sh — One-shot post-Session-A telemetry backfill.
#
# Walks all EPIC evidence dirs across ekosystem projects (or --evidence-roots
# arg list) and performs two retro operations:
#
#   1. Stamp state.yaml.created_at  (CP1 M2 unblock — without this field,
#      Step 3 fsm_check_grandfather() returns false and mid-FSM EPICs become
#      unresumable post-deploy because new EXECUTE→GATES enforcement kicks in.)
#      Source priority: earliest timeline.jsonl event ts → state.yaml file mtime.
#
#   2. Write per-run compliance.json  (deploy_era="pre-session-a") with the
#      3 retro-evaluable dimensions (branch_correct, execution_yaml_present,
#      gates_generated_by). Sessions B/C dimensions stay null per schema.
#
# Idempotent: skips state.yaml that already has created_at; skips run dirs
# that already have compliance.json. Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") --deploy-date YYYY-MM-DDTHH:MM:SSZ [--evidence-roots "path1 path2 ..."]

One-shot post-Session-A deploy backfill. For each EPIC run dir under each
evidence root:
  • If state.yaml lacks 'created_at:', stamp it from the earliest timeline
    event ts (or file mtime fallback). Required for fsm_check_grandfather()
    to recognize mid-FSM EPICs as pre-deploy.
  • If compliance.json is missing, write a pre-Session-A skeleton with
    3 retro-evaluable dimensions; others stay null.

Default --evidence-roots covers ekosystem projects:
  /opt/eco/projects/{vulcan,sousto-na-miru,krok,wan,aid-orchestrator}/.aid-o/work/evidence

Examples:
  $(basename "$0") --deploy-date 2026-05-15T00:00:00Z
  $(basename "$0") --deploy-date 2026-05-15T00:00:00Z --evidence-roots "/tmp/p1/.aid-o/work/evidence"
EOF
}

# CP1 M2: stamp created_at into a state.yaml that lacks it.
# Sources, in priority order:
#   1. Earliest .ts from timeline.jsonl  (most accurate — actual init moment)
#   2. state.yaml file mtime              (less accurate, post-migration safe)
#   3. Current UTC time                   (last-resort fallback, never empty)
backfill_state_created_at() {
  local state_file=$1 timeline_file=$2

  if grep -q '^created_at:' "$state_file" 2>/dev/null; then
    return 0
  fi

  local earliest_ts=""
  if [[ -f "$timeline_file" ]]; then
    earliest_ts=$(jq -r '.ts // empty' "$timeline_file" 2>/dev/null | sort | head -1)
  fi
  if [[ -z "$earliest_ts" ]]; then
    earliest_ts=$(date -u -r "$state_file" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                  || date -u +%Y-%m-%dT%H:%M:%SZ)
  fi

  echo "created_at: $earliest_ts" >> "$state_file"
  log_info "Backfilled created_at=$earliest_ts into $state_file"
}

# Build a pre-Session-A compliance.json for a single EPIC run dir.
# DUPLICATES (intentionally) the runtime evaluate_compliance_checks logic
# from aid-fsm.sh::write_compliance_json — backfill operates outside the
# FSM runtime context (no $state_file/$evidence_dir scope), per Step 5
# Dependencies note in the plan.
generate_pre_compliance() {
  local run_dir=$1 deploy_date=$2

  local epic_id run_id state_file gates_report project_root
  epic_id=$(basename "$(dirname "$run_dir")")
  run_id=$(basename "$run_dir")
  state_file="${run_dir}/state.yaml"
  gates_report="${run_dir}/gates/gates_report.json"
  project_root=$(echo "$run_dir" | sed 's|/.aid-o/work/evidence/.*||')

  # branch_correct
  local branch_value="" branch_correct=false
  [[ -f "$state_file" ]] && branch_value=$(grep '^branch:' "$state_file" 2>/dev/null | awk '{print $2}')
  [[ "$branch_value" =~ ^task/E- ]] && branch_correct=true

  # execution_yaml_present (project-level)
  local exec_yaml_present=false
  [[ -f "${project_root}/.aid-o/config/execution.yaml" ]] && exec_yaml_present=true

  # gates_generated_by (provenance from Step 3 runner)
  local gates_genby=false
  if [[ -f "$gates_report" ]] && jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
    gates_genby=true
  fi

  jq -nc \
    --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
    --arg era "pre-session-a" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson bc  "$branch_correct" \
    --argjson eyp "$exec_yaml_present" \
    --argjson ggb "$gates_genby" \
    --arg note "Backfilled ${deploy_date} — pre-Session-A run, retro-evaluated 3 dimensions only" \
    '{
      epic_id: $epic, run_id: $run, aid_version: $ver,
      deploy_era: $era, evaluated_at: $ts,
      checks: {
        branch_correct:         $bc,
        execution_yaml_present: $eyp,
        gates_generated_by:     $ggb,
        memory_substantive:     null,
        verifier_outputs:       null,
        dod_present:            null
      },
      overall: ([$bc, $eyp, $ggb] | all | if . then "pass" else "fail" end),
      notes: [$note]
    }'
}

main() {
  local deploy_date=""
  local -a evidence_roots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy-date)    deploy_date="$2"; shift 2 ;;
      --evidence-roots) read -ra evidence_roots <<< "$2"; shift 2 ;;
      -h|--help)        usage; exit 0 ;;
      *)                echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  if [[ -z "$deploy_date" ]]; then
    echo "ERROR: --deploy-date REQUIRED" >&2
    usage >&2
    exit 1
  fi

  if (( ${#evidence_roots[@]} == 0 )); then
    evidence_roots=(
      "/opt/eco/projects/vulcan/.aid-o/work/evidence"
      "/opt/eco/projects/sousto-na-miru/.aid-o/work/evidence"
      "/opt/eco/projects/krok/.aid-o/work/evidence"
      "/opt/eco/projects/wan/.aid-o/work/evidence"
      "/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence"
    )
  fi

  local count=0 skipped=0 stamped=0

  for root in "${evidence_roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      log_warn "Evidence root not found, skipping: $root"
      continue
    fi
    while IFS= read -r epic_dir; do
      [[ ! -d "$epic_dir" ]] && continue
      local -a run_dirs=()
      mapfile -t run_dirs < <(find "$epic_dir" -maxdepth 1 -mindepth 1 -type d -name "R-*")
      for run_dir in "${run_dirs[@]}"; do
        local state_file="${run_dir}/state.yaml"
        local timeline_file="${run_dir}/timeline.jsonl"

        # Step A: stamp created_at if missing (CP1 M2)
        if [[ -f "$state_file" ]] && ! grep -q '^created_at:' "$state_file" 2>/dev/null; then
          backfill_state_created_at "$state_file" "$timeline_file"
          stamped=$((stamped + 1))
        fi

        # Step B: write compliance.json if missing
        local compliance="${run_dir}/compliance.json"
        if [[ -f "$compliance" ]]; then
          skipped=$((skipped + 1))
          continue
        fi
        generate_pre_compliance "$run_dir" "$deploy_date" > "$compliance"
        count=$((count + 1))
      done
    done < <(find "$root" -maxdepth 1 -mindepth 1 -type d -name "E-*")
  done

  cat <<EOF
Backfill complete:
  ${count} compliance.json generated (deploy_era=pre-session-a)
  ${skipped} already present (skipped, idempotent)
  ${stamped} state.yaml stamped with created_at (mid-FSM unblock per CP1 M2)
EOF
}

main "$@"
