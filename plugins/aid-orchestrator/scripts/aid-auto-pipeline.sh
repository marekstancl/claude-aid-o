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
#   2. aid-epic-to-json.sh  — EPIC.md  -> plan.json
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
force_init_reason="" # PM-authorized, audited cross-plan force-init reason → aid-json-to-run.sh → aid-fsm.sh init (waives ONLY the false-positive cross-plan ca-review-complete precondition)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)         plan="$2";           shift 2 ;;
    --queue-mode)   queue_mode="$2";     shift 2 ;;
    --plugin-dir)   plugin_dir="$2";     shift 2 ;;
    --depends-on)   custom_depends="$2"; shift 2 ;;
    --streamlined)  streamlined=true;    shift 1 ;;
    --force-init-reason) force_init_reason="$2"; shift 2 ;;
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

# =============================================================================
# P073 Step 11 — committed-source preflight (P083)
# =============================================================================
# The only check here used to be "the file exists on disk", and cmd_plan_start
# never sees a path at all. The clean-worktree preflight runs with
# `--untracked-files=no`, so a plan that was never `git add`ed is invisible to
# it too. Generation therefore created a plan branch, task branches and a
# lifecycle manifest from bytes that exist ONLY in one worktree — and the
# manifest's source_plan_sha then bound the whole plan to a source nobody else
# could ever read. That is P083.
#
# SCOPE, learned the hard way: the check is about THIS WORKSPACE's repository
# and the plan's relationship to its target branch. A first cut resolved the
# repo from the plan's own directory and hard-failed when no target branch
# resolved, which refused every plan living outside the workspace (the test
# fixtures, and any shared plan library) — an over-block the loosening
# directive forbids. Three cases are therefore skipped WITH A LOG LINE rather
# than refused, because none of them has a target-branch relationship to
# verify: the workspace is not a git repo, the plan is not inside it, or the
# plan is gitignored. In each the manifest's source_plan_sha IS the binding.
_p083_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
_p083_plan_abs="$(realpath -m -- "$plan" 2>/dev/null || echo "$plan")"
if [[ -z "$_p083_repo_root" ]]; then
  echo "[INFO] plan_source_binding: source_plan_sha (this workspace is not a git repository)" >&2
elif [[ "$_p083_plan_abs" != "$_p083_repo_root"/* ]]; then
  echo "[INFO] plan_source_binding: source_plan_sha (${plan} lives outside this workspace's repository, so it has no target-branch relationship to verify)" >&2
elif git check-ignore -q -- "$_p083_plan_abs" 2>/dev/null; then
  # DELIBERATE, not a loophole: this very repository gitignores `.aid-o/plans/`,
  # so a hard tracked-only rule would break the plugin's own dogfood workflow.
  echo "[INFO] plan_source_binding: source_plan_sha (${plan} is gitignored — the committed manifest's source_plan_sha is the binding, not a tracked blob)" >&2
else
  _p083_target="$(aid_target_branch 2>/dev/null || echo "")"
  _p083_rel="${_p083_plan_abs#"$_p083_repo_root"/}"
  if [[ -z "$_p083_target" ]] || ! git rev-parse --verify --quiet "$_p083_target" >/dev/null 2>&1; then
    # No integration branch exists to verify against. Refuse only when the plan
    # is already TRACKED — then it is genuinely part of the repository's history
    # and a missing target branch is the fresh-repo case the plan names. An
    # UNTRACKED plan in a workspace with no target branch has nothing to be
    # checked against at all, and refusing it would block every such workspace
    # (found when this broke the branch-restore fixtures).
    if git ls-files --error-unmatch -- "$_p083_plan_abs" >/dev/null 2>&1; then
      error_exit "PRECONDITION FAIL: source plan ${_p083_rel} is tracked but the target branch '${_p083_target:-<unresolved>}' does not exist — create and commit the target branch first, or gitignore the plan if it is deliberately unshared." 1
    fi
    echo "[INFO] plan_source_binding: source_plan_sha (no target branch '${_p083_target:-<unresolved>}' exists to verify ${_p083_rel} against)" >&2
    _p083_target=""
  fi
  if [[ -n "$_p083_target" ]]; then
    if ! git cat-file -e "${_p083_target}:${_p083_rel}" 2>/dev/null \
       || ! git show "${_p083_target}:${_p083_rel}" 2>/dev/null | cmp -s - "$_p083_plan_abs"; then
      error_exit "PRECONDITION FAIL: source plan is not committed on ${_p083_target} (or differs from the worktree copy) — commit the plan on ${_p083_target} and rerun generation." 1
    fi
    echo "[INFO] plan_source_binding: committed blob ${_p083_target}:${_p083_rel} matches the worktree copy byte for byte" >&2
  fi
fi

# =============================================================================
# Verify all 4 sub-scripts exist and are executable
# =============================================================================
sub_scripts=(
  "aid-plan-to-epic.sh"
  "aid-epic-to-json.sh"
  "aid-generation-finalize.sh"
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

# P074 generation-integrity: the default path is two-stage.  A complete EPIC
# package is generated and sealed before any FSM init or queue mutation. The
# old interleaved behavior remains opt-in solely for legacy recovery; it is not
# selected by normal callers.
two_stage=true
[[ "${AID_PIPELINE_LEGACY_INTERLEAVED:-0}" == "1" ]] && two_stage=false

_generation_depends_for_epic() {
  local epic_file="$1" previous="$2" result="" raw ext
  case "$queue_mode" in
    chain) result="$previous" ;;
    separate) result="" ;;
    custom) result="$custom_depends" ;;
  esac
  raw="$(awk '
    BEGIN { in_qi = 0 }
    { gsub(/\r$/, ""); if ($0 ~ /^### Queue Implications/) { in_qi=1; next }
      if (in_qi && ($0 ~ /^##/ || $0 ~ /^---/)) exit
      if (in_qi && $0 ~ /^depends_on:/) { sub(/^depends_on:[[:space:]]*/, "", $0); gsub(/[\[\]]/, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if ($0 != "") print; exit } }
  ' "$epic_file" 2>/dev/null || true)"
  if [[ -n "$raw" ]]; then
    IFS=',' read -ra _generation_exts <<< "$raw"
    for ext in "${_generation_exts[@]}"; do
      ext="$(echo "$ext" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$ext" || "$ext" == "$previous" ]] && continue
      if [[ -z "$result" ]]; then result="$ext"; elif ! echo ",$result," | grep -q ",$ext,"; then result="${result},${ext}"; fi
    done
  fi
  printf '%s\n' "$result"
}

# IMP-232 v2.58.1: create the plan lifecycle manifest at the official scaffold, as
# part of the normal commit flow (repo identity + manifest committed together via
# an isolated index — the user's index is never touched). This is what makes the
# durable denominator exist BEFORE closure, so a new plan never waits for a manual
# reconcile to have a lifecycle manifest. Enforcement is split by plan opt-in:
# lifecycle_strict plans FAIL-CLOSED if the manifest is not durable; legacy plans
# proceed under a loud, audited migration (never a silent skip).
if [[ -f "${SCRIPT_DIR}/lib/aid-lifecycle.sh" ]]; then
  # shellcheck source=lib/aid-lifecycle.sh
  source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"
  # P068 Step 7 — the mode a NEW plan is created with, resolved from
  # defaults/policies/plan-boundary-policy.yaml and GUARDED on the project's
  # gate_profiles table existing. Resolved BEFORE the manifest write, from the
  # policy rather than from the manifest, which avoids the chicken-and-egg of
  # asking a file that has not been written yet what mode it declares.
  _pb_mode_row="$(bash "${SCRIPT_DIR}/aid-plan-fsm.sh" __default-mode --project-root "." 2>/dev/null || true)"
  _pb_default_mode="${_pb_mode_row%%$'\t'*}"
  _pb_mode_reason="${_pb_mode_row#*$'\t'}"
  [[ -z "$_pb_default_mode" ]] && { _pb_default_mode="legacy_epic_release_mode"; _pb_mode_reason="resolver_unavailable"; }
  if [[ "$_pb_default_mode" == "legacy_epic_release_mode" && "$_pb_mode_reason" == *"no_gate_profiles"* ]]; then
    echo "[INFO] plan_branch_unavailable: no_gate_profiles — $plan_id is created in legacy_epic_release_mode. Run the gate-profile bootstrap to enable the plan-final model." >&2
    mkdir -p ".aid-o/work" 2>/dev/null \
      && printf '{"plan_id":"%s","event":"plan_branch_unavailable","reason":"no_gate_profiles"}\n' "$plan_id" >> ".aid-o/work/lifecycle-migration.log" 2>/dev/null || true
  fi

  _lc_rc=0; aid_lifecycle_ensure_manifest "$plan_id" "." >/dev/null 2>&1 || _lc_rc=$?
  if [[ "$_lc_rc" -eq 0 ]]; then
    # Stamp the resolved mode into the manifest that was just made durable, then
    # make the STAMP durable too. ensure_manifest commits what it wrote, so a
    # bare `yq -i` here would leave the mode in the worktree only while the
    # COMMITTED copy — the authority every later reader consults, including
    # _fsm_declared_plan_mode, which reads target_branch's tree — carried none.
    # A mode that exists only in an uncommitted file is not a declaration.
    if ! yq -i ".mode = \"${_pb_default_mode}\"" ".aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null; then
      error_exit "Lifecycle manifest for $plan_id was created but its mode could not be stamped — a manifest with no declared mode cannot prove which release model the plan follows." 6
    fi
    # ensure_manifest returns early once the manifest is durable, and rebuilds
    # it from the plan when it is not — either way it neither knows nor preserves
    # `mode`. The stamp therefore has to be committed here, on its own, through
    # the same isolated-index path the lifecycle layer uses (the caller's index
    # is never touched). Verified by reading the committed copy back: a stamp
    # that cannot be read from target_branch's tree is not a declaration.
    _lc_rc2=0
    _aid_lc_isolated_commit "." "lifecycle: declare mode ${_pb_default_mode} for ${plan_id}" \
      ".aid-lifecycle/manifests/${plan_id}.yaml" >/dev/null 2>&1 || _lc_rc2=$?
    _pb_committed_mode="$(git show "$(aid_target_branch):.aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null | yq -r '.mode // ""' 2>/dev/null || true)"
    if [[ "$_pb_committed_mode" != "$_pb_default_mode" ]]; then
      if [[ "$_pb_default_mode" == "plan_branch" && "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
        error_exit "The mode stamp for $plan_id is not readable from $(aid_target_branch)'s committed manifest (rc=$_lc_rc2, read='${_pb_committed_mode:-<none>}') — under plan_branch an undeclared mode in the committed manifest is exactly the silent downgrade this boundary exists to prevent." 6
      fi
      echo "[WARN] lifecycle: the mode stamp for $plan_id is not committed (rc=$_lc_rc2) — the plan runs legacy, which is what the uncommitted state already implies." >&2
    fi
    echo "[INFO] lifecycle manifest ensured for $plan_id (.aid-lifecycle/manifests/${plan_id}.yaml), mode=${_pb_default_mode} (${_pb_mode_reason})" >&2
  elif [[ "$_pb_default_mode" == "plan_branch" && "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
    # P068 Step 7 — THE ESCAPE HATCH IS CLOSED UNDER plan_branch.
    # This path used to WARN and proceed whenever the plan did not opt into
    # lifecycle_strict. That is defensible for a legacy plan, but once the
    # default mode is plan_branch it becomes the silent downgrade the whole
    # boundary exists to prevent: no manifest means no mode declaration, which
    # means the plan runs legacy while everyone believes it is plan-branch.
    error_exit "Lifecycle manifest could not be created for $plan_id (rc=$_lc_rc) and the resolved default mode is plan_branch — proceeding would run the plan under the legacy model while its mode is undeclared. Fix the plan's EPIC declaration (strict '**EPIC N: …**' / '**EPIC N / Backlog: …**' grammar) and run on target_branch — or set AID_LIFECYCLE_MIGRATION=1 for an explicit, audited legacy run." 6
  elif grep -qE '^lifecycle_strict:[[:space:]]*true' "$plan" 2>/dev/null && [[ "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
    # NEW-MODEL plan (opted into strict lifecycle via frontmatter) MUST have a
    # durable, committed manifest before EPIC scaffolding -> FAIL-CLOSED.
    error_exit "Lifecycle manifest could not be created for strict plan $plan_id (rc=$_lc_rc). A lifecycle_strict plan MUST have a durable, committed manifest before EPIC scaffolding. Fix the plan's EPIC declaration (strict '**EPIC N: …**' / '**EPIC N / Backlog: …**' grammar) and run on target_branch — or set AID_LIFECYCLE_MIGRATION=1 for an explicit, audited legacy run." 6
  else
    # Reached by a LEGACY plan (no lifecycle_strict) OR a strict plan explicitly
    # overridden with AID_LIFECYCLE_MIGRATION=1 -> explicit, AUDITED migration: a
    # loud WARN + a logged marker (never a silent skip). Reconcilable after
    # delivery. Message must NOT assert "legacy" — it may be a strict override.
    _lc_mode="legacy"; [[ "${AID_LIFECYCLE_MIGRATION:-}" == "1" ]] && _lc_mode="strict-override"
    echo "[WARN] lifecycle: no durable manifest for plan $plan_id (mode=$_lc_mode, rc=$_lc_rc) — proceeding in AUDITED migration mode; run 'aid-fsm.sh plan-reconcile $plan_id --apply' after delivery. (New plans use the plan template's 'lifecycle_strict: true' + the strict '**EPIC N:**' grammar for fail-closed guarantees.)" >&2
    mkdir -p ".aid-o/work" 2>/dev/null \
      && printf '{"plan_id":"%s","rc":%s,"mode":"lifecycle-migration-pending","migration_mode":"%s"}\n' "$plan_id" "$_lc_rc" "$_lc_mode" >> ".aid-o/work/lifecycle-migration.log" 2>/dev/null || true
  fi

  # The parent-plan state machine belongs exclusively to plan_branch mode.
  # A legacy plan deliberately retains the pre-P064 EPIC-by-EPIC lifecycle;
  # attempting plan-start without its durable plan-boundary manifest turns a
  # compatible ordinary pipeline into a false blocker. Do not "migrate" it as
  # a side effect of generation. plan_branch remains fail-closed above.
  #
  # Only when a plan-branch plan has no state: an existing plan is never
  # migrated mid-run, and plan-start is a no-op guard rather than a
  # re-initialisation.
  if [[ "$_pb_default_mode" == "plan_branch" && ! -f ".aid-o/work/plan-state/${plan_id}/plan-state.yaml" ]]; then
    _ps_rc=0
    # P073 Step 11: pass the source plan through so plan-start can verify it is
    # committed and stamp its path. The pipeline's own preflight above already
    # ran the same check, so this is the second, closer-to-the-mutation layer
    # rather than the first line of defence.
    bash "${SCRIPT_DIR}/aid-plan-fsm.sh" plan-start "$plan_id" \
      --mode "$_pb_default_mode" --project-root "." --plan-file "$plan" >/dev/null 2>&1 || _ps_rc=$?
    if [[ "$_ps_rc" -eq 0 ]]; then
      echo "[INFO] plan state initialised for $plan_id (mode=${_pb_default_mode})" >&2
    else
      echo "[WARN] plan-start could not initialise plan state for $plan_id (rc=$_ps_rc) — the lifecycle manifest still carries the declared mode, which is the authority; run 'aid-plan-fsm.sh plan-start $plan_id --mode ${_pb_default_mode}' before the plan boundary." >&2
    fi
  fi
fi

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
    --counter-yaml "$counter_yaml" \
    --project-root "$(pwd)")"

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
  # Phase N.b5: Contract Validation Gate (blocking, D5) + C0 Plan Contract
  # Gate (observe). Runs after plan.json exists; before FSM init. The
  # contract-validate sub-block below is the one BLOCKING exception in this
  # phase — everything else here is plan-level observe-only evidence.
  # -------------------------------------------------------------------------
  {
    # Determine plan_id from plan filename
    _c0_plan_id="$(basename "$plan" .md)"
    # Each generated EPIC owns its own C0 contract graph and validation
    # evidence. A shared plan-level c0/ directory made phase N overwrite phase
    # N-1, leaving the last graph to masquerade as evidence for the whole plan.
    # The plan-global source graph and C0 bridge remain at their own named
    # generation/ and c0/ paths respectively.
    _c0_dir=".aid-o/work/evidence/${_c0_plan_id}/generation/epics/${epic_id}/c0"
    mkdir -p "$_c0_dir"

    # -------------------------------------------------------------------------
    # D5: Contract Validation Gate (BLOCKING — deliberately NOT part of the
    # observe-only C0 block below). A malformed generator contract (broadcast
    # outputs/allowed_paths, `|`-split AC fragments, prose leaking into
    # allowed_paths) is a hard error per plan D5 ("Contract-gate blocking +
    # C0 evidence — malformed = hard-fail před /aid-run") and must stop the
    # pipeline before json-to-run / queue-add / branch creation happen below.
    #
    # Persist-before-abort: evidence is keyed by plan AND EPIC, so every
    # generated phase retains its own result. The complete-package finalizer
    # can therefore reason about all phases rather than a misleading final
    # overwrite from the last phase.
    # -------------------------------------------------------------------------
    _cv_exit=0
    _cv_json="$("${SCRIPT_DIR}/gates/aid-contract-validate.sh" "$plan_json_path" "$epic_path" \
      2>>"$_c0_dir/c0-producer.log")" || _cv_exit=$?
    printf '%s\n' "$_cv_json" > "${_c0_dir}/contract-validate.json"

    if [[ "$_cv_exit" -ne 0 ]]; then
      error_exit "Contract validation failed for phase ${phase} (${_c0_plan_id}): malformed plan.json/EPIC.md contract — see ${_c0_dir}/contract-validate.json" 4
    fi

    # Read enforcement policy (fail-safe: default to observe)
    _c0_policy="observe"
    _c0_policy_file="${SCRIPT_DIR}/../defaults/policies/c0-contract.yaml"
    if [[ -n "${C0_CONTRACT_POLICY:-}" ]]; then
      _c0_policy="$C0_CONTRACT_POLICY"
    elif [[ -f "$_c0_policy_file" ]] && command -v yq &>/dev/null; then
      _c0_policy_val="$(yq '.enforcement // "observe"' "$_c0_policy_file" 2>/dev/null)"
      [[ -n "$_c0_policy_val" && "$_c0_policy_val" != "null" ]] && _c0_policy="$_c0_policy_val"
    fi

    # Run C0 contract producer
    _c0_contract_exit=0
    "${SCRIPT_DIR}/aid-c0-contract.sh" contract "$plan_json_path" "$_c0_dir" \
      2>>"$_c0_dir/c0-producer.log" || _c0_contract_exit=$?

    if [[ $_c0_contract_exit -ne 0 ]]; then
      _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_producer_error\",\"plan_id\":\"${_c0_plan_id}\",\"exit\":${_c0_contract_exit}}" \
        >> "$_c0_dir/c0-observe.jsonl"
    fi

    # Run C0 review checker
    _c0_review_exit=0
    "${SCRIPT_DIR}/aid-c0-contract.sh" review "$plan" "$_c0_dir" \
      2>>"$_c0_dir/c0-producer.log" || _c0_review_exit=$?

    if [[ $_c0_review_exit -ne 0 ]]; then
      _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_review_error\",\"plan_id\":\"${_c0_plan_id}\",\"exit\":${_c0_review_exit}}" \
        >> "$_c0_dir/c0-observe.jsonl"
    fi

    # Log c0_would_block if any structural or lens findings
    _c0_would_block=false
    if [[ -f "$_c0_dir/plan-review.json" ]]; then
      _c0_finding_count="$(jq '
        ((.plan_review.structural_checks // []) | map(select(.status != "pass")) | length) +
        ((.plan_review.lens_findings // []) | map(select(.verdict == "found")) | length)
      ' "$_c0_dir/plan-review.json" 2>/dev/null || echo 0)"
      if [[ "$_c0_finding_count" -gt 0 ]]; then
        _c0_would_block=true
        _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_would_block\",\"plan_id\":\"${_c0_plan_id}\",\"finding_count\":${_c0_finding_count},\"policy\":\"${_c0_policy}\"}" \
          >> "$_c0_dir/c0-observe.jsonl"
        echo "[C0] would_block: ${_c0_finding_count} findings (policy=${_c0_policy})" >&2
      fi
    fi

    # Enforce policy (blocking mode — E10 / tests only; default is observe)
    if [[ "$_c0_policy" == "blocking" && "$_c0_would_block" == "true" ]]; then
      error_exit "C0 Plan Contract Gate: blocking policy activated with ${_c0_finding_count} findings" 2
    fi

    # NEVER propagate non-zero from C0 block in observe mode
  }

  # Stage 1 ends here on the normal path: no run/FSM/queue state exists until
  # the finalizer has verified every generated phase against the source graph.
  if [[ "$two_stage" == true ]]; then
    _stage_depends="$(_generation_depends_for_epic "$epic_path" "$prev_epic_id")"
    _stage_depends_json="[]"
    if [[ -n "$_stage_depends" ]]; then
      _stage_depends_json="$(printf '%s' "$_stage_depends" | tr ',' '\n' | jq -R . | jq -s .)"
    fi
    epics_json="$(echo "$epics_json" | jq \
      --argjson phase "$phase" --arg epic_id "$epic_id" --arg epic_path "$epic_path" \
      --arg plan_json "$plan_json_path" --arg run_id "$run_id" --arg contract_validate "${_c0_dir}/contract-validate.json" --argjson depends_on "$_stage_depends_json" \
      '. + [{phase:$phase, epic_id:$epic_id, epic_path:$epic_path, plan_json:$plan_json, contract_validate:$contract_validate, run_id:$run_id, queue_status:"pending_receipt", depends_on:$depends_on}]')"
    prev_epic_id="$epic_id"
    echo "[INFO] Phase ${phase}/${total_phases}: ${epic_id} generated; waiting for complete-package receipt" >&2
    continue
  fi

  # -------------------------------------------------------------------------
  # Phase N.c: plan.json -> run.md
  # -------------------------------------------------------------------------
  run_output_dir=".aid-o/work/runs/${run_id}"
  mkdir -p "$run_output_dir" 2>/dev/null || true

  json_to_run_args=(
    --plan-json "$plan_json_path"
    --run-template "$run_template"
    --epic "$epic_path"
    --output-dir "$run_output_dir"
    --run-id "$run_id"
  )
  [[ "$streamlined" == "true" ]] && json_to_run_args+=(--streamlined)
  [[ -n "$force_init_reason" ]] && json_to_run_args+=(--force-init-reason "$force_init_reason")
  # P073 Step 6: exit 4 from aid-json-to-run.sh means generation SUCCEEDED but
  # the checkout could not be restored to the branch this run started on.
  # (4, not 3 — that script already uses 3 for ordinary I/O failures.)
  # Every remaining phase (queue, report, a further EPIC) would otherwise run
  # against a branch the operator never chose, so stop here and pass the
  # recovery instruction through. Any other non-zero status is an ordinary
  # generation failure and keeps its existing meaning.
  _j2r_rc=0
  run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" "${json_to_run_args[@]}")" || _j2r_rc=$?
  if [[ "$_j2r_rc" -eq 4 ]]; then
    echo "[ERROR] Branch restore failed after EPIC generation — the remaining pipeline phases (queue, report) were NOT run. Follow the 'git checkout' instruction above, then rerun." >&2
    exit 4
  fi
  [[ "$_j2r_rc" -eq 0 ]] || exit "$_j2r_rc"

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
    --argjson phase "$phase" \
    --arg epic_id "$epic_id" \
    --arg epic_path "$epic_path" \
    --arg plan_json "$plan_json_path" \
    --arg run_path "$run_path" \
    --arg run_id "$run_id" \
    --arg queue_status "pending" \
    --argjson depends_on "$depends_on_json" \
    '. + [{
      phase: $phase,
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
# Stage 2 — seal the complete package, then initialise and queue it
# =============================================================================
generation_receipt=""
if [[ "$two_stage" == true ]]; then
  _generation_dir=".aid-o/work/evidence/${plan_id}/generation"
  mkdir -p "$_generation_dir"
  _generation_manifest="$_generation_dir/generated-epics.json"
  _generation_tmp="${_generation_manifest}.tmp.$$"
  printf '%s\n' "$epics_json" > "$_generation_tmp"
  mv "$_generation_tmp" "$_generation_manifest"
  generation_receipt="$_generation_dir/receipt.json"
  "${SCRIPT_DIR}/aid-generation-finalize.sh" --plan "$plan" --total "$total_phases" \
    --epics-json "$_generation_manifest" --output "$generation_receipt" >/dev/null

  for phase in $(seq 1 "$total_phases"); do
    _entry="$(jq -c --argjson p "$phase" '.[] | select(.phase == $p)' <<< "$epics_json")"
    _epic_id="$(jq -r '.epic_id' <<< "$_entry")"
    _epic_path="$(jq -r '.epic_path' <<< "$_entry")"
    _plan_json_path="$(jq -r '.plan_json' <<< "$_entry")"
    _run_id="$(jq -r '.run_id' <<< "$_entry")"
    _run_output_dir=".aid-o/work/runs/${_run_id}"
    mkdir -p "$_run_output_dir"
    _j2r_args=(--plan-json "$_plan_json_path" --run-template "$run_template" --epic "$_epic_path" --output-dir "$_run_output_dir" --run-id "$_run_id" --generation-receipt "$generation_receipt")
    [[ "$streamlined" == true ]] && _j2r_args+=(--streamlined)
    [[ -n "$force_init_reason" ]] && _j2r_args+=(--force-init-reason "$force_init_reason")
    # P073 Step 6: same hard stop in the batch (post-receipt) loop — a failed
    # restore must not let the NEXT phase initialise on the wrong branch.
    _j2r_rc=0
    _run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" "${_j2r_args[@]}")" || _j2r_rc=$?
    if [[ "$_j2r_rc" -eq 4 ]]; then
      echo "[ERROR] Branch restore failed after phase ${phase}/${total_phases} (${_epic_id}) — no queue entry was written for it and no further phase was initialised. Follow the 'git checkout' instruction above, then rerun." >&2
      exit 4
    fi
    [[ "$_j2r_rc" -eq 0 ]] || exit "$_j2r_rc"

    _queue_args=(--epic-id "$_epic_id" --epic-path "$_epic_path" --priority medium --queue-yaml "$queue_yaml" --plan-ref "$plan")
    _depends_csv="$(jq -r '.depends_on | join(",")' <<< "$_entry")"
    [[ -n "$_depends_csv" ]] && _queue_args+=(--depends-on "$_depends_csv")
    "${SCRIPT_DIR}/aid-queue-add.sh" "${_queue_args[@]}" >/dev/null
    epics_json="$(jq --argjson p "$phase" --arg rp "$_run_path" 'map(if .phase == $p then . + {run_path:$rp, queue_status:"pending"} else . end)' <<< "$epics_json")"
    echo "[INFO] Phase ${phase}/${total_phases}: ${_epic_id} initialised and queued after receipt" >&2
  done
fi

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
