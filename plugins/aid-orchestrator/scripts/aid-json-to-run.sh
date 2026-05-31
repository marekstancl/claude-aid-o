#!/usr/bin/env bash
# =============================================================================
# aid-json-to-run.sh -- Generate a run.md file from plan.json + EPIC
#
# Usage:
#   ./aid-json-to-run.sh \
#     --plan-json <path> --run-template <path> --epic <path> \
#     --output-dir <path> --run-id <R-xxx>
#
# Reads plan.json (steps, dependencies, gates, budget) and the EPIC file
# (Goal, Context, Scope), then assembles a complete run.md matching the
# run template structure with populated frontmatter, phases, dependencies,
# and quality gates.
#
# stdout: Absolute path to the generated run file
# stderr: JSON error on failure (see Exit Codes in README.md)
#
# Exit codes: 0=success, 1=validation, 2=dependency, 3=I/O
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites

# =============================================================================
# Parse CLI arguments
# =============================================================================
plan_json_path=""
run_template=""
epic=""
output_dir=""
run_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-json)     plan_json_path="$2";  shift 2 ;;
    --run-template)  run_template="$2";    shift 2 ;;
    --epic)          epic="$2";            shift 2 ;;
    --output-dir)    output_dir="$2";      shift 2 ;;
    --run-id)        run_id="$2";          shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# =============================================================================
# Validate required arguments
# =============================================================================
[[ -z "$plan_json_path" ]] && error_exit "Missing required argument: --plan-json" 1
[[ -z "$run_template" ]]   && error_exit "Missing required argument: --run-template" 1
[[ -z "$epic" ]]           && error_exit "Missing required argument: --epic" 1
[[ -z "$output_dir" ]]     && error_exit "Missing required argument: --output-dir" 1
[[ -z "$run_id" ]]         && error_exit "Missing required argument: --run-id" 1

# =============================================================================
# Validate input files exist
# =============================================================================
[[ ! -f "$plan_json_path" ]] && error_exit "plan.json not found: $plan_json_path" 1
[[ ! -f "$run_template" ]]   && error_exit "Run template not found: $run_template" 2
[[ ! -f "$epic" ]]           && error_exit "EPIC file not found: $epic" 3

# Validate output directory is writable (create if needed)
mkdir -p "$output_dir" 2>/dev/null || error_exit "Cannot create output directory: $output_dir" 3
if [[ ! -w "$output_dir" ]]; then
  error_exit "Output directory not writable: $output_dir" 3
fi

# =============================================================================
# Step 1: Validate plan.json structure
# =============================================================================
if ! jq empty "$plan_json_path" 2>/dev/null; then
  error_exit "plan.json is not valid JSON: $plan_json_path" 1
fi

step_count="$(jq '.steps | length' "$plan_json_path")"
if [[ "$step_count" -eq 0 ]]; then
  error_exit "plan.json contains zero steps" 1
fi

# =============================================================================
# Step 2: Extract fields from plan.json
# =============================================================================
epic_id="$(jq -r '.epic_id // ""' "$plan_json_path")"
source_plan="$(jq -r '.source_plan // ""' "$plan_json_path")"

[[ -z "$epic_id" ]] && error_exit "plan.json missing epic_id field" 1

# =============================================================================
# Step 3: Extract context from EPIC file
# =============================================================================
epic_goal_raw="$(extract_section "$epic" "Goal")"
epic_context_raw="$(extract_section "$epic" "Context")"
epic_scope_allowed="$(extract_subsection "$epic" "Scope" "Allowed files/paths")"
epic_scope_forbidden="$(extract_subsection "$epic" "Scope" "Forbidden zones")"

# Extract first sentence of Goal for the run title
# Take the first line that has content, strip leading whitespace
goal_first_sentence="$(echo "$epic_goal_raw" | sed '/^[[:space:]]*$/d' | head -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

# If goal section is empty, fall back to EPIC H1 header
if [[ -z "$goal_first_sentence" ]]; then
  goal_first_sentence="$(awk '
    { gsub(/\r$/, "")
      if ($0 ~ /^# /) {
        sub(/^# (EPIC:[[:space:]]*)?/, "", $0)
        sub(/[[:space:]]*$/, "", $0)
        print
        exit
      }
    }
  ' "$epic")"
fi

# Truncate to first sentence (stop at period followed by space or end)
if echo "$goal_first_sentence" | grep -q '\. '; then
  goal_first_sentence="$(echo "$goal_first_sentence" | sed 's/\. .*/\./')"
fi

# =============================================================================
# Step 4: Build Objective (3-5 sentences from Goal + key scope items)
# =============================================================================
# Collect non-empty goal lines (up to 5)
objective_text=""
line_count=0
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  # Skip empty lines, HTML comments, and markdown bullets for objective prose
  [[ -z "$line" ]] && continue
  [[ "$line" == "<!--"* ]] && continue
  objective_text="${objective_text}${line} "
  line_count=$(( line_count + 1 ))
  [[ "$line_count" -ge 5 ]] && break
done <<< "$epic_goal_raw"

# Trim trailing space
objective_text="$(echo "$objective_text" | sed 's/[[:space:]]*$//')"

# If objective is still empty, use the goal first sentence
if [[ -z "$objective_text" ]]; then
  objective_text="$goal_first_sentence"
fi

# =============================================================================
# Step 5: Build Scope IN/OUT lists
# =============================================================================
scope_in=""
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    item="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')"
    item="${item//\`/}"
    [[ -z "$item" ]] && continue
    [[ "$item" == "<!--"* ]] && continue
    scope_in="${scope_in}- ${item}
"
  fi
done <<< "$epic_scope_allowed"

scope_out=""
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    item="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')"
    item="${item//\`/}"
    [[ -z "$item" ]] && continue
    [[ "$item" == "<!--"* ]] && continue
    scope_out="${scope_out}- ${item}
"
  fi
done <<< "$epic_scope_forbidden"

# Default scope items if empty
if [[ -z "$scope_in" ]]; then
  scope_in="- See plan.json steps for per-phase allowed paths
"
fi
if [[ -z "$scope_out" ]]; then
  scope_out="- See plan.json steps for per-phase forbidden paths
"
fi

# =============================================================================
# Step 6: Detect run type from template filename
# =============================================================================
template_basename="$(basename "$run_template")"
# Extract type from template name: run-new-feature.md -> new-feature
run_type="$(echo "$template_basename" | sed 's/^run-//; s/\.md$//')"
if [[ -z "$run_type" ]]; then
  run_type="new-feature"
fi

# =============================================================================
# Step 7: Build frontmatter
# =============================================================================
today="$(date -u +%Y-%m-%d)"
now_full="$(date -u +"%Y-%m-%d %H:%M UTC")"

# Determine epic_run (extract phase number from epic_id if available)
epic_run="1"
epic_total=""
if [[ "$epic_id" =~ ^E-[0-9]+-([0-9]+)_([0-9]+)$ ]]; then
  epic_run="${BASH_REMATCH[1]}"
  epic_total="${BASH_REMATCH[2]}"
fi

# Build run_id slug for the filename
goal_slug="$(slugify "$goal_first_sentence")"

frontmatter="---
id: ${run_id}
run_id: ${today}-${run_type}-${goal_slug}
type: ${run_type}
status: active
priority: medium
started: ${now_full}
epic_id: ${epic_id}"

if [[ -n "$epic_total" ]]; then
  frontmatter="${frontmatter}
epic_run: ${epic_run} of ${epic_total}"
else
  frontmatter="${frontmatter}
epic_run: ${epic_run}"
fi

frontmatter="${frontmatter}
epic_file: ${epic}
plan_ref: ${plan_json_path}"

if [[ -n "$source_plan" && "$source_plan" != "null" ]]; then
  frontmatter="${frontmatter}
source_plan: ${source_plan}"
fi

frontmatter="${frontmatter}
orchestrated: true
---"

# =============================================================================
# Step 8: Build run title
# =============================================================================
# Determine title prefix from run type
title_prefix="Run"
case "$run_type" in
  new-feature)   title_prefix="New Feature" ;;
  bug-fix)       title_prefix="Bug Fix" ;;
  refactoring)   title_prefix="Refactoring" ;;
  exploration)   title_prefix="Exploration" ;;
esac

run_title="# ${title_prefix}: ${run_id} -- ${goal_first_sentence}"

# =============================================================================
# Step 9: Build Context section
# =============================================================================
context_text="Generated from EPIC ${epic_id}, plan ${plan_json_path}. ${step_count} phases planned."

if [[ -n "$source_plan" && "$source_plan" != "null" ]]; then
  context_text="${context_text} Source plan: ${source_plan}."
fi

# =============================================================================
# Step 10: Build Phase sections from plan.json steps
# =============================================================================
phases_text=""
phase_num=0

while IFS= read -r step_json; do
  phase_num=$(( phase_num + 1 ))

  step_id="$(echo "$step_json" | jq -r '.id')"
  step_role="$(echo "$step_json" | jq -r '.role')"
  step_objective="$(echo "$step_json" | jq -r '.objective')"

  # Truncate objective to 60 chars for phase title
  if [[ "${#step_objective}" -gt 60 ]]; then
    phase_title="$(echo "$step_objective" | cut -c1-57)..."
  else
    phase_title="$step_objective"
  fi

  # Build Inputs list
  inputs_text=""
  input_count="$(echo "$step_json" | jq '.inputs // [] | length')"
  if [[ "$input_count" -gt 0 ]]; then
    while IFS= read -r input_item; do
      inputs_text="${inputs_text}- ${input_item}
"
    done < <(echo "$step_json" | jq -r '.inputs[]')
  else
    inputs_text="- EPIC specification
"
  fi

  # Build Outputs list
  outputs_text=""
  output_count="$(echo "$step_json" | jq '.outputs // [] | length')"
  if [[ "$output_count" -gt 0 ]]; then
    while IFS= read -r output_item; do
      outputs_text="${outputs_text}- ${output_item}
"
    done < <(echo "$step_json" | jq -r '.outputs[]')
  else
    outputs_text="- Step ${step_id} deliverables
"
  fi

  # Build Constraints list
  constraints_text=""
  constraint_count="$(echo "$step_json" | jq '.constraints // [] | length')"
  if [[ "$constraint_count" -gt 0 ]]; then
    while IFS= read -r constraint_item; do
      constraints_text="${constraints_text}- ${constraint_item}
"
    done < <(echo "$step_json" | jq -r '.constraints[]')
  fi

  # Add allowed/forbidden paths as constraints
  allowed_count="$(echo "$step_json" | jq '.allowed_paths // [] | length')"
  if [[ "$allowed_count" -gt 0 ]]; then
    allowed_list="$(echo "$step_json" | jq -r '.allowed_paths | join(", ")')"
    constraints_text="${constraints_text}- Allowed paths: ${allowed_list}
"
  fi

  forbidden_count="$(echo "$step_json" | jq '.forbidden_paths // [] | length')"
  if [[ "$forbidden_count" -gt 0 ]]; then
    forbidden_list="$(echo "$step_json" | jq -r '.forbidden_paths | join(", ")')"
    constraints_text="${constraints_text}- Forbidden paths: ${forbidden_list}
"
  fi

  # Default if no constraints at all
  if [[ -z "$constraints_text" ]]; then
    constraints_text="- No specific constraints
"
  fi

  # Build Acceptance criteria
  acceptance_text=""
  ac_count="$(echo "$step_json" | jq '.acceptance_criteria // [] | length')"
  if [[ "$ac_count" -gt 0 ]]; then
    while IFS= read -r ac_item; do
      acceptance_text="${acceptance_text}- [ ] ${ac_item}
"
    done < <(echo "$step_json" | jq -r '.acceptance_criteria[]')
  else
    # Auto-generate from objective when acceptance_criteria is empty
    acceptance_text="- [ ] ${step_objective} -- completed successfully
- [ ] Output artifacts produced and valid
- [ ] No regressions introduced
"
  fi

  # Assemble phase section
  phases_text="${phases_text}
### Phase ${phase_num}: ${phase_title}

**Goal:**
${step_objective}

**Agent / Role:** ${step_role}

**Inputs:**
${inputs_text}
**Outputs:**
${outputs_text}
**Constraints:**
${constraints_text}
**Acceptance:**
${acceptance_text}"

done < <(jq -c '.steps[]' "$plan_json_path")

# =============================================================================
# Step 11: Build Dependencies table
# =============================================================================
dep_count="$(jq '.dependencies | length' "$plan_json_path")"

deps_table=""
if [[ "$dep_count" -eq 0 || "$step_count" -eq 1 ]]; then
  deps_table="No inter-phase dependencies."
else
  deps_table="| Phase | Depends On | Reason |
|-------|-----------|--------|"

  # Build a lookup from step_id to phase number
  # We need to read step IDs in order and map them
  declare -A step_id_to_phase=()
  phase_idx=0
  while IFS= read -r sid; do
    phase_idx=$(( phase_idx + 1 ))
    step_id_to_phase["$sid"]="$phase_idx"
  done < <(jq -r '.steps[].id' "$plan_json_path")

  while IFS= read -r dep_json; do
    dep_before="$(echo "$dep_json" | jq -r '.before')"
    dep_after="$(echo "$dep_json" | jq -r '.after')"
    dep_reason="$(echo "$dep_json" | jq -r '.reason // "Declared dependency"')"

    before_phase="${step_id_to_phase[$dep_before]:-?}"
    after_phase="${step_id_to_phase[$dep_after]:-?}"

    deps_table="${deps_table}
| Phase ${after_phase} | Phase ${before_phase} | ${dep_reason} |"
  done < <(jq -c '.dependencies[]' "$plan_json_path")
fi

# =============================================================================
# Step 12: Build Quality Gates section
# =============================================================================
gates_count="$(jq '.gates // [] | length' "$plan_json_path")"
gates_text=""

if [[ "$gates_count" -gt 0 ]]; then
  while IFS= read -r gate; do
    case "$gate" in
      tests_pass)          gate_desc="All test suites pass (unit + integration)" ;;
      lint_pass)           gate_desc="Linting and code style checks pass" ;;
      security_scan_pass)  gate_desc="Security scanning finds no critical issues" ;;
      docs_updated)        gate_desc="Documentation is up to date with changes" ;;
      *)                   gate_desc="Quality gate check" ;;
    esac
    gates_text="${gates_text}- **${gate}** -- ${gate_desc}
"
  done < <(jq -r '.gates[]' "$plan_json_path")
else
  gates_text="- No quality gates configured for this run.
"
fi

# =============================================================================
# Step 13: Build Budget section (if present)
# =============================================================================
budget_text=""
has_budget="$(jq 'has("budget")' "$plan_json_path")"
if [[ "$has_budget" == "true" ]]; then
  max_retries="$(jq '.budget.max_retries_per_gate // 3' "$plan_json_path")"
  budget_text="- Max retries per gate: ${max_retries}"

  max_cost="$(jq -r '.budget.max_llm_cost_usd // empty' "$plan_json_path")"
  if [[ -n "$max_cost" ]]; then
    budget_text="${budget_text}
- Max LLM cost: \$${max_cost}"
  fi
fi

# =============================================================================
# Step 14: Build Run Log with creation entry
# =============================================================================
timestamp="$(iso_timestamp)"
run_log="**${timestamp}** - Run file generated from plan.json (${step_count} phases, ${dep_count} dependencies)"

# =============================================================================
# Step 15: Assemble the full run.md
# =============================================================================
run_content="${frontmatter}

${run_title}

## Objective

${objective_text}

## Context

**Previous work:** Generated from EPIC ${epic_id}
**Current state:** ${context_text}
**Dependencies:** See Dependencies table below

## Scope

**In Scope:**
${scope_in}
**Out of Scope:**
${scope_out}
---

## Phases
${phases_text}
---

## Dependencies

${deps_table}

---

## Quality Gates

${gates_text}"

if [[ -n "$budget_text" ]]; then
  run_content="${run_content}
### Budget

${budget_text}
"
fi

run_content="${run_content}
---

## Testing

### Test Plan
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Edge cases covered

### Test Results
_To be filled during execution._

---

## Impact

- **Lines of Code:** _TBD_
- **Test Coverage:** _TBD_

---

## Documentation Updates

- [ ] Relevant docs updated
- [ ] CHANGELOG.md entry added

---

## References

**EPIC:** [${epic_id}](${epic})
**Plan:** [plan.json](${plan_json_path})
**Run ID:** ${run_id}

---

## AI Run Log

${run_log}

---

## Completion Checklist

### Pre-Completion:
- [ ] All phases completed
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] No TODO/FIXME left in code

### Run Closure:
- [ ] Commit messages follow conventions
- [ ] Run file archived to completed/
- [ ] Handoff protocol executed
- [ ] Run log updated

---

## Next Steps

**For Human Review:**
- Review delivered artifacts
- Validate against acceptance criteria

**For AI (if run continues):**
- Monitor for related issues
- Consider optimization opportunities

---

**Status:** active
**Last Updated:** ${now_full}
**Completion:** 0%"

# =============================================================================
# Step 16: Write run.md to output directory
# =============================================================================
output_filename="${run_id}-${goal_slug}.md"
# Ensure filename is not too long (max 200 chars for the filename part)
if [[ "${#output_filename}" -gt 200 ]]; then
  output_filename="$(echo "$output_filename" | cut -c1-196).md"
fi

output_path="${output_dir}/${output_filename}"

# Write via temp file + mv for atomic write (prevents partial writes on failure)
tmp_file="$(mktemp "${output_dir}/.run-XXXXXX")" || error_exit "Cannot create temp file in: $output_dir" 3

printf '%s\n' "$run_content" > "$tmp_file" || {
  rm -f "$tmp_file"
  error_exit "Cannot write run file content" 3
}

mv "$tmp_file" "$output_path" || {
  rm -f "$tmp_file"
  error_exit "Cannot move temp file to: $output_path" 3
}

# =============================================================================
# Step 17: Resolve absolute run.md path
# =============================================================================
# Resolve to absolute path (do NOT echo yet — Step 18 runs first; the absolute
# path MUST remain the FINAL stdout line for aid-auto-pipeline.sh capture).
if [[ "$output_path" == /* ]]; then
  abs_run_path="$output_path"
else
  abs_run_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"
fi

# =============================================================================
# Step 18: P040 Component E — Auto-init FSM state (idempotent)
# =============================================================================
# Eliminates state.yaml vs fsm-state.yaml schema confusion (NR 10/12/14):
# aid-json-to-run.sh now initializes the FSM directly so no manual
# `aid-fsm.sh init` call is required before /aid-run.
# Compute FSM init parameters from in-scope variables.
fsm_evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"  # MUST match aid-fsm.sh cmd_init evidence_dir derivation
mkdir -p "$fsm_evidence_dir"
fsm_state_file="${fsm_evidence_dir}/fsm-state.yaml"
fsm_mode="full"
fsm_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fsm_base_commit="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$fsm_branch" || "$fsm_branch" == "HEAD" ]] && error_exit "aid-json-to-run.sh Step 18: cannot determine current git branch (detached HEAD?)" 1
[[ -z "$fsm_base_commit" ]] && error_exit "aid-json-to-run.sh Step 18: cannot read git HEAD SHA for base_commit" 1

if [[ ! -f "$fsm_state_file" ]]; then
  echo "P040 Component E: initializing FSM state at $fsm_state_file" >&2
  # aid-fsm.sh init runs branch enforcement and may auto-checkout
  # task/<epic_id>/main. aid-json-to-run.sh is a GENERATION-phase tool:
  # aid-auto-pipeline.sh calls it once per EPIC in a single batch, so leaving
  # the workdir on a per-EPIC task branch would make the NEXT EPIC's init see a
  # cross-EPIC mismatch and hard-fail. We therefore restore the original branch
  # after init (the EPIC's task branch is recreated at execution time via the
  # FSM resume case). Restore is a no-op for non-batch single-EPIC callers.
  bash "${SCRIPT_DIR}/aid-fsm.sh" init \
    "$epic_id" "$run_id" "$step_count" "$fsm_mode" \
    "$fsm_branch" "$fsm_base_commit" \
    "$fsm_state_file"
  fsm_after_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$fsm_branch" && "$fsm_branch" != "HEAD" && "$fsm_after_branch" != "$fsm_branch" ]]; then
    if git checkout "$fsm_branch" >/dev/null 2>&1; then
      echo "P040 Component E: restored generation branch '$fsm_branch' after FSM init (was on '$fsm_after_branch')" >&2
    else
      echo "P040 Component E: WARNING — could not restore branch '$fsm_branch' after FSM init (now on '$fsm_after_branch')" >&2
    fi
  fi
else
  echo "P040 Component E: fsm-state.yaml already exists at $fsm_state_file; skipping init (idempotent)" >&2
fi

# =============================================================================
# Step 19: Output absolute run.md path to stdout (MUST be final stdout line)
# =============================================================================
# aid-auto-pipeline.sh captures this stdout into $run_path. aid-fsm.sh init
# above writes only to stderr / its own state file, so stdout is clean here.
echo "$abs_run_path"
