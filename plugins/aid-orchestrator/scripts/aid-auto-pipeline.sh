#!/usr/bin/env bash
# =============================================================================
# aid-auto-pipeline.sh — Master orchestration: Plan -> EPIC -> JSON -> Run -> Queue
#
# Usage:
#   ./aid-auto-pipeline.sh \
#     --plan <path> [--queue-mode <chain|separate|custom>] \
#     [--plugin-dir <path>] [--depends-on <E-xxx,E-yyy>] [--streamlined]
#
# --streamlined (optional, default off): passthrough forwarded to every
# aid-json-to-run.sh invocation (Phase N.c), which in turn forwards it to
# aid-fsm.sh init so each EPIC's FSM carries streamlined_mode: true
# (P040 Component D activation; CP3 gap fix).
#
# Runs the full Plan-to-Queue pipeline for all phases of a plan. This is the
# single entry point called by the /aid-plan-epic command. For each phase it:
#   1. aid-plan-to-epic.sh  — Plan.md  -> EPIC.md
#   2. aid-epic-to-json.sh  — EPIC.md  -> plan.json + state.yaml
#   3. aid-json-to-run.sh   — plan.json -> run.md
#   4. aid-queue-add.sh     — EPIC     -> queue.yaml entry
#
# stdout: JSON manifest { plan_id, plan_path, epics, queue_mode, duration_ms }
# stderr: JSON error on failure; progress messages prefixed with [INFO]
#
# Exit codes: 0=success, 1=validation, 2=dependency/missing sub-script, 3=I/O
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites

# =============================================================================
# Parse CLI arguments
# =============================================================================
plan=""
queue_mode="chain"
plugin_dir=""
custom_depends=""
streamlined=false   # P040 Component D passthrough → aid-json-to-run.sh → aid-fsm.sh init (CP3 gap fix)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)        plan="$2";           shift 2 ;;
    --queue-mode)  queue_mode="$2";     shift 2 ;;
    --plugin-dir)  plugin_dir="$2";     shift 2 ;;
    --depends-on)  custom_depends="$2"; shift 2 ;;
    --streamlined) streamlined=true;    shift 1 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# =============================================================================
# Validate required arguments
# =============================================================================
[[ -z "$plan" ]] && error_exit "Missing required argument: --plan" 1
[[ ! -f "$plan" ]] && error_exit "Plan file not found: $plan" 3

# Validate queue mode
case "$queue_mode" in
  chain|separate|custom) ;;
  *) error_exit "Invalid queue mode: $queue_mode (must be chain, separate, or custom)" 1 ;;
esac

# Custom mode with empty --depends-on is treated as separate
if [[ "$queue_mode" == "custom" && -z "$custom_depends" ]]; then
  queue_mode="separate"
fi

# =============================================================================
# Verify all 4 sub-scripts exist and are executable
# =============================================================================
sub_scripts=(
  "aid-plan-to-epic.sh"
  "aid-epic-to-json.sh"
  "aid-json-to-run.sh"
  "aid-queue-add.sh"
)

for script_name in "${sub_scripts[@]}"; do
  script_path="${SCRIPT_DIR}/${script_name}"
  if [[ ! -f "$script_path" ]]; then
    error_exit "Sub-script not found: $script_path" 2
  fi
  if [[ ! -x "$script_path" ]]; then
    error_exit "Sub-script not executable: $script_path (run: chmod +x $script_path)" 2
  fi
done

# =============================================================================
# Resolve plugin directory
# =============================================================================
if [[ -z "$plugin_dir" ]]; then
  # Auto-detect: walk up from SCRIPT_DIR to find the plugin root
  # SCRIPT_DIR is .../plugins/aid-orchestrator/scripts, so parent is the plugin dir
  plugin_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ ! -d "$plugin_dir" ]]; then
  error_exit "Plugin directory not found: $plugin_dir" 3
fi

# =============================================================================
# Resolve template and config paths
# =============================================================================
epic_template="${plugin_dir}/defaults/templates/epic.md"
plan_schema="${plugin_dir}/defaults/templates/plan.schema.json"

# Find a run template: prefer run-new-feature.md, fall back to any run-*.md
run_template="${plugin_dir}/defaults/templates/run-new-feature.md"
if [[ ! -f "$run_template" ]]; then
  # Find the first available run-*.md template
  run_template=""
  for candidate in "${plugin_dir}"/defaults/templates/run-*.md; do
    if [[ -f "$candidate" ]]; then
      run_template="$candidate"
      break
    fi
  done
  if [[ -z "$run_template" ]]; then
    error_exit "No run template found in ${plugin_dir}/defaults/templates/run-*.md" 2
  fi
fi

# Validate required templates exist
[[ ! -f "$epic_template" ]] && error_exit "EPIC template not found: $epic_template. Run /aid-init to deploy templates." 2
[[ ! -f "$plan_schema" ]]   && error_exit "Plan schema not found: $plan_schema" 2

# Config paths (in the workspace, not the plugin)
counter_yaml=".aid-o/config/counter.yaml"
queue_yaml=".aid-o/config/queue.yaml"

# Ensure workspace directories exist
mkdir -p ".aid-o/tasks" 2>/dev/null || error_exit "Cannot create .aid-o/tasks directory" 3
mkdir -p ".aid-o/work/evidence" 2>/dev/null || error_exit "Cannot create .aid-o/work/evidence directory" 3
mkdir -p ".aid-o/work/runs" 2>/dev/null || error_exit "Cannot create .aid-o/work/runs directory" 3
mkdir -p "$(dirname "$queue_yaml")" 2>/dev/null || error_exit "Cannot create queue directory" 3

# =============================================================================
# Parse plan frontmatter — extract plan_id
# =============================================================================
frontmatter="$(parse_frontmatter "$plan")"

plan_id=""
while IFS='=' read -r key val; do
  case "$key" in
    id) plan_id="$val" ;;
  esac
done <<< "$frontmatter"

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1

# =============================================================================
# Detect phase count from plan
#
# Strategy:
#   1. Search for explicit EPIC/Phase markers: **EPIC N:...** or **Phase N...**
#   2. If markers found: count them -> total phases
#   3. If no markers: count ### Step headers, divide into groups of ~5-7
# =============================================================================

# Count explicit EPIC/Phase markers
marker_count=0
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^\*\*EPIC[[:space:]]+[0-9]+ ]] || [[ "$line" =~ ^\*\*Phase[[:space:]]+[0-9]+ ]]; then
    marker_count=$(( marker_count + 1 ))
  fi
done < "$plan"

# Count step headers — accept multiple formats:
#   ### Step N: ...       (preferred, level 3)
#   ## Task N: ...        (common alternative, level 2)
#   ## Step N: ...        (level 2 variant)
step_count=0
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+ ]]; then
    step_count=$(( step_count + 1 ))
  fi
done < "$plan"

# Determine total phases
total_phases=0
if [[ "$marker_count" -gt 0 ]]; then
  total_phases="$marker_count"
  echo "[INFO] Detected $total_phases phase(s) from explicit EPIC/Phase markers" >&2
elif [[ "$step_count" -gt 0 ]]; then
  # Divide steps into groups of ~5-7 (target 6 steps per phase)
  steps_per_phase=6
  total_phases=$(( (step_count + steps_per_phase - 1) / steps_per_phase ))
  # Ensure at least 1 phase
  [[ "$total_phases" -lt 1 ]] && total_phases=1
  echo "[INFO] No phase markers found. $step_count steps divided into $total_phases phase(s) (~$steps_per_phase steps each)" >&2
else
  # Check for a high-level steps table (rows in a markdown table under ## High-Level Steps)
  table_row_count="$(awk '
    BEGIN { in_table = 0; count = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^## (High-Level Steps|Implementation Steps)/) { in_table = 1; next }
      if (in_table && $0 ~ /^##[^#]/) exit
      if (in_table && $0 ~ /^\|/ && $0 !~ /^\|[[:space:]]*[-]+/ && $0 !~ /^\|[[:space:]]*(#|Phase|Step)/) {
        count++
      }
    }
    END { print count }
  ' "$plan")"

  if [[ "$table_row_count" -gt 0 ]]; then
    # Each table row = 1 phase (if rows are phase-level) or group them
    if [[ "$table_row_count" -le 7 ]]; then
      total_phases="$table_row_count"
    else
      total_phases=$(( (table_row_count + 5) / 6 ))
    fi
    echo "[INFO] Detected $total_phases phase(s) from $table_row_count table rows" >&2
  fi
fi

if [[ "$total_phases" -eq 0 ]]; then
  error_exit "Cannot detect any phases in plan file. Expected EPIC/Phase markers, ### Step N:, or ## Task N: headers." 1
fi

# =============================================================================
# Start timer
#
# Portable millisecond timing: try date +%s%3N (GNU coreutils), fall back to
# SECONDS variable with second precision.
# =============================================================================
use_ms_timer=true
start_ms="$(date +%s%3N 2>/dev/null)" || use_ms_timer=false

if [[ "$use_ms_timer" == false ]] || [[ ! "$start_ms" =~ ^[0-9]+$ ]]; then
  # Fallback: use bash SECONDS variable (second precision)
  use_ms_timer=false
  SECONDS=0
fi

# =============================================================================
# Main pipeline loop — process each phase
# =============================================================================
epics_json="[]"
prev_epic_id=""

echo "[INFO] Starting pipeline for plan $plan_id ($total_phases phase(s), queue-mode: $queue_mode)" >&2

for phase in $(seq 1 "$total_phases"); do

  # -------------------------------------------------------------------------
  # Phase N.a: Plan -> EPIC
  # -------------------------------------------------------------------------
  epic_path="$("${SCRIPT_DIR}/aid-plan-to-epic.sh" \
    --plan "$plan" \
    --phase "$phase" \
    --total "$total_phases" \
    --epic-template "$epic_template" \
    --output-dir ".aid-o/tasks" \
    --counter-yaml "$counter_yaml")"

  # Extract epic_id from the generated filename
  epic_basename="$(basename "$epic_path")"
  if [[ "$epic_basename" =~ (E-[A-Za-z0-9][A-Za-z0-9-]*[0-9]+_[0-9]+) ]]; then
    epic_id="${BASH_REMATCH[1]}"
  else
    error_exit "Cannot extract EPIC ID from generated file: $epic_basename" 1
  fi

  # -------------------------------------------------------------------------
  # Phase N.b: EPIC -> plan.json
  # -------------------------------------------------------------------------
  json_result="$("${SCRIPT_DIR}/aid-epic-to-json.sh" \
    --epic "$epic_path" \
    --schema "$plan_schema" \
    --output-dir ".aid-o" \
    --plan-source "$plan")"

  # Extract plan_json path and run_id from the JSON manifest on stdout
  plan_json_path="$(echo "$json_result" | jq -r '.plan_json')"
  run_id="$(echo "$json_result" | jq -r '.run_id')"

  if [[ -z "$plan_json_path" || "$plan_json_path" == "null" ]]; then
    error_exit "aid-epic-to-json.sh did not return plan_json path for phase $phase" 1
  fi
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    error_exit "aid-epic-to-json.sh did not return run_id for phase $phase" 1
  fi

  # -------------------------------------------------------------------------
  # Phase N.c: plan.json -> run.md
  # -------------------------------------------------------------------------
  run_output_dir=".aid-o/work/runs/${run_id}"
  mkdir -p "$run_output_dir" 2>/dev/null || true

  if [[ "$streamlined" == "true" ]]; then
    run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" \
      --plan-json "$plan_json_path" \
      --run-template "$run_template" \
      --epic "$epic_path" \
      --output-dir "$run_output_dir" \
      --run-id "$run_id" \
      --streamlined)"
  else
    run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" \
      --plan-json "$plan_json_path" \
      --run-template "$run_template" \
      --epic "$epic_path" \
      --output-dir "$run_output_dir" \
      --run-id "$run_id")"
  fi

  # -------------------------------------------------------------------------
  # Phase N.d: Determine depends_on for queue entry
  # -------------------------------------------------------------------------
  depends_on=""
  case "$queue_mode" in
    chain)
      depends_on="$prev_epic_id"
      ;;
    separate)
      depends_on=""
      ;;
    custom)
      depends_on="$custom_depends"
      ;;
  esac

  # Parse EPIC Dependencies -> Queue Implications section for external deps
  # Look for: depends_on: [E-xxx, E-yyy] in the generated EPIC
  queue_deps_raw="$(awk '
    BEGIN { in_qi = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^### Queue Implications/) { in_qi = 1; next }
      if (in_qi && ($0 ~ /^##/ || $0 ~ /^---/)) exit
      if (in_qi && $0 ~ /^depends_on:/) {
        sub(/^depends_on:[[:space:]]*/, "", $0)
        # Remove brackets
        gsub(/[\[\]]/, "", $0)
        # Trim
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 != "") print
        exit
      }
    }
  ' "$epic_path" 2>/dev/null || true)"

  if [[ -n "$queue_deps_raw" ]]; then
    # Merge external deps with existing depends_on (avoid duplicates)
    IFS=',' read -ra ext_deps <<< "$queue_deps_raw"
    for ext_dep in "${ext_deps[@]}"; do
      ext_dep="$(echo "$ext_dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$ext_dep" ]] && continue
      # Skip if it is the same as prev_epic_id (already handled by chain mode)
      [[ "$ext_dep" == "$prev_epic_id" ]] && continue
      # Skip self-references
      [[ "$ext_dep" == "$epic_id" ]] && continue
      if [[ -n "$depends_on" ]]; then
        # Check for duplicates before appending
        if ! echo ",$depends_on," | grep -q ",$ext_dep,"; then
          depends_on="${depends_on},${ext_dep}"
        fi
      else
        depends_on="$ext_dep"
      fi
    done
  fi

  # -------------------------------------------------------------------------
  # Phase N.e: EPIC -> queue
  # -------------------------------------------------------------------------
  queue_args=(
    --epic-id "$epic_id"
    --epic-path "$epic_path"
    --priority medium
    --queue-yaml "$queue_yaml"
    --plan-ref "$plan"
  )
  if [[ -n "$depends_on" ]]; then
    queue_args+=(--depends-on "$depends_on")
  fi

  "${SCRIPT_DIR}/aid-queue-add.sh" "${queue_args[@]}" >/dev/null

  # -------------------------------------------------------------------------
  # Phase N.f: Update tracking state
  # -------------------------------------------------------------------------
  prev_epic_id="$epic_id"

  # Build depends_on JSON array for the manifest
  depends_on_json="[]"
  if [[ -n "$depends_on" ]]; then
    IFS=',' read -ra dep_parts <<< "$depends_on"
    for dp in "${dep_parts[@]}"; do
      dp="$(echo "$dp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$dp" ]] && continue
      depends_on_json="$(echo "$depends_on_json" | jq --arg d "$dp" '. + [$d]')"
    done
  fi

  # Append entry to epics manifest
  epics_json="$(echo "$epics_json" | jq \
    --arg epic_id "$epic_id" \
    --arg epic_path "$epic_path" \
    --arg plan_json "$plan_json_path" \
    --arg run_path "$run_path" \
    --arg run_id "$run_id" \
    --arg queue_status "queued" \
    --argjson depends_on "$depends_on_json" \
    '. + [{
      epic_id: $epic_id,
      epic_path: $epic_path,
      plan_json: $plan_json,
      run_path: $run_path,
      run_id: $run_id,
      queue_status: $queue_status,
      depends_on: $depends_on
    }]')"

  echo "[INFO] Phase ${phase}/${total_phases}: ${epic_id} -- done" >&2

done

# =============================================================================
# Compute duration
# =============================================================================
duration_ms=0
if [[ "$use_ms_timer" == true ]]; then
  end_ms="$(date +%s%3N 2>/dev/null)" || end_ms=0
  if [[ "$end_ms" =~ ^[0-9]+$ && "$start_ms" =~ ^[0-9]+$ ]]; then
    duration_ms=$(( end_ms - start_ms ))
  fi
else
  duration_ms=$(( SECONDS * 1000 ))
fi

# =============================================================================
# Output JSON manifest to stdout
# =============================================================================
jq -n \
  --arg plan_id "$plan_id" \
  --arg plan_path "$plan" \
  --argjson epics "$epics_json" \
  --arg queue_mode "$queue_mode" \
  --argjson duration_ms "$duration_ms" \
  '{
    plan_id: $plan_id,
    plan_path: $plan_path,
    epics: $epics,
    queue_mode: $queue_mode,
    duration_ms: $duration_ms
  }'
