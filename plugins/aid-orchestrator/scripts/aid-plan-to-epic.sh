#!/usr/bin/env bash
# =============================================================================
# aid-plan-to-epic.sh — Convert a Plan.md file into an EPIC.md for a given phase
#
# Usage:
#   ./aid-plan-to-epic.sh \
#     --plan <path> --phase <N> --total <T> \
#     --epic-template <path> --output-dir <path> --counter-yaml <path>
#
# Reads the plan, extracts phase-specific steps, fills the EPIC template,
# and writes the completed EPIC to the output directory.
#
# stdout: Absolute path to the generated EPIC file
# stderr: JSON error on failure (see Exit Codes in README.md)
#
# Exit codes: 0=success, 1=validation, 2=dependency, 3=I/O
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
plan=""
phase=""
total=""
epic_template=""
output_dir=""
counter_yaml=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)        plan="$2";          shift 2 ;;
    --phase)       phase="$2";         shift 2 ;;
    --total)       total="$2";         shift 2 ;;
    --epic-template) epic_template="$2"; shift 2 ;;
    --output-dir)  output_dir="$2";    shift 2 ;;
    --counter-yaml) counter_yaml="$2"; shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -z "$plan" ]]          && error_exit "Missing required argument: --plan" 1
[[ -z "$phase" ]]         && error_exit "Missing required argument: --phase" 1
[[ -z "$total" ]]         && error_exit "Missing required argument: --total" 1
[[ -z "$epic_template" ]] && error_exit "Missing required argument: --epic-template" 1
[[ -z "$output_dir" ]]    && error_exit "Missing required argument: --output-dir" 1
[[ -z "$counter_yaml" ]]  && error_exit "Missing required argument: --counter-yaml" 1

# Validate files exist
[[ ! -f "$plan" ]]          && error_exit "Plan file not found: $plan" 3
[[ ! -f "$epic_template" ]] && error_exit "EPIC template not found: $epic_template. Run /aid-init to deploy templates." 2
[[ ! -d "$output_dir" ]]    && error_exit "Output directory not found: $output_dir" 3

# Validate phase/total are positive integers
[[ ! "$phase" =~ ^[0-9]+$ ]] && error_exit "Phase must be a positive integer, got: $phase" 1
[[ ! "$total" =~ ^[0-9]+$ ]] && error_exit "Total must be a positive integer, got: $total" 1
[[ "$phase" -lt 1 || "$phase" -gt "$total" ]] && error_exit "Phase $phase out of range (1-$total)" 1

# ---------------------------------------------------------------------------
# Step 1: Parse plan frontmatter — extract plan ID
# ---------------------------------------------------------------------------
frontmatter="$(parse_frontmatter "$plan")"

plan_id=""
while IFS='=' read -r key val; do
  case "$key" in
    id) plan_id="$val" ;;
  esac
done <<< "$frontmatter"

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1

# Extract plan number (strip leading P)
plan_num="$(echo "$plan_id" | sed 's/^P//')"

# ---------------------------------------------------------------------------
# Step 2: Generate EPIC ID and slug
# ---------------------------------------------------------------------------
epic_id="E-${plan_num}-${phase}_${total}"

# Extract plan title from H1 header
title="$(awk '
  { gsub(/\r$/, "") }
  /^# Plan:/ {
    sub(/^# Plan:[[:space:]]*/, "")
    print
    exit
  }
' "$plan")"

[[ -z "$title" ]] && title="untitled"
slug="$(slugify "$title")"

# ---------------------------------------------------------------------------
# Step 3: Verify Implementation Steps section exists
#
# NOTE: We scan the ENTIRE plan file (not just the extracted section) for
# step headers and EPIC markers. This is because plans may contain fenced
# code blocks with ## headers that create false section boundaries, causing
# extract_section to miss steps in later phases. By scanning the whole file,
# we reliably find all ### Step N: headers and **EPIC N:** markers regardless
# of intervening ## headers inside code blocks.
# ---------------------------------------------------------------------------

# Quick check that a steps section exists (supports both formats)
# Plans use either "## Implementation Steps" (detailed) or "## High-Level Steps" (standard template)
has_impl_steps="$(awk '
  { gsub(/\r$/, "") }
  /^## (Implementation Steps|High-Level Steps)/ { print "yes"; exit }
' "$plan")"
[[ "$has_impl_steps" != "yes" ]] && error_exit "Plan file missing '## Implementation Steps' or '## High-Level Steps' section" 1

# ---------------------------------------------------------------------------
# Step 4: Detect phase boundaries and extract steps for this phase
#
# Scan the ENTIRE plan file for:
#   - **EPIC N: Steps M-P** markers (phase boundaries)
#   - ### Step N: headers (step definitions)
#
# Plans use markers like:
#   **EPIC 1: Steps 1-6 — Scripts**
#   **EPIC 1**
#   **Phase 1**
# If no markers found, divide steps evenly across phases.
# ---------------------------------------------------------------------------

# Get all step numbers and EPIC markers from the entire plan file
step_numbers=()
declare -A phase_start_step
declare -A phase_end_step
declare -A step_to_phase
found_markers=0
current_marker_phase=0

while IFS= read -r line; do
  line="${line//$'\r'/}"
  # Match EPIC markers: **EPIC N: Steps M-P — Title** or **EPIC N**
  if [[ "$line" =~ ^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))? ]]; then
    current_marker_phase="${BASH_REMATCH[1]}"
    if [[ -n "${BASH_REMATCH[3]:-}" && -n "${BASH_REMATCH[4]:-}" ]]; then
      phase_start_step[$current_marker_phase]="${BASH_REMATCH[3]}"
      phase_end_step[$current_marker_phase]="${BASH_REMATCH[4]}"
    fi
    found_markers=1
  fi
  # Match step headers: ### Step N: ...
  if [[ "$line" =~ ^###[[:space:]]+Step[[:space:]]+([0-9]+) ]]; then
    step_numbers+=("${BASH_REMATCH[1]}")
    if [[ "$current_marker_phase" -gt 0 ]]; then
      step_to_phase["${BASH_REMATCH[1]}"]="$current_marker_phase"
    fi
  fi
done < "$plan"

total_steps="${#step_numbers[@]}"
[[ "$total_steps" -eq 0 ]] && error_exit "No steps found in plan file" 1

# Determine which steps belong to the requested phase
phase_steps=()
if [[ "$found_markers" -eq 1 ]]; then
  if [[ -n "${phase_start_step[$phase]+_}" && -n "${phase_end_step[$phase]+_}" ]]; then
    # We have explicit step ranges from markers
    start="${phase_start_step[$phase]}"
    end="${phase_end_step[$phase]}"
    for sn in "${step_numbers[@]}"; do
      if [[ "$sn" -ge "$start" && "$sn" -le "$end" ]]; then
        phase_steps+=("$sn")
      fi
    done
  else
    # Markers found but without explicit ranges for this phase —
    # use step-to-phase mapping from document order
    for sn in "${step_numbers[@]}"; do
      if [[ "${step_to_phase[$sn]:-0}" == "$phase" ]]; then
        phase_steps+=("$sn")
      fi
    done
  fi
else
  # No explicit markers — divide steps evenly across phases
  steps_per_phase=$(( total_steps / total ))
  remainder=$(( total_steps % total ))

  offset=0
  for p in $(seq 1 "$total"); do
    count="$steps_per_phase"
    # Distribute remainder to earlier phases (3,2,2 for 7 steps across 3 phases)
    if [[ "$remainder" -gt 0 ]]; then
      count=$(( count + 1 ))
      remainder=$(( remainder - 1 ))
    fi
    if [[ "$p" -eq "$phase" ]]; then
      for i in $(seq 0 $(( count - 1 ))); do
        idx=$(( offset + i ))
        phase_steps+=("${step_numbers[$idx]}")
      done
      break
    fi
    offset=$(( offset + count ))
  done
fi

[[ "${#phase_steps[@]}" -eq 0 ]] && error_exit "No steps found for phase $phase" 1

# ---------------------------------------------------------------------------
# Step 5: Extract data from each phase step
# ---------------------------------------------------------------------------

# Helper: extract content for a given step number directly from the plan file.
# Returns everything between ### Step N and the next ### Step header (or the
# next **EPIC M:** marker, or section boundary), excluding the header itself.
extract_step_content() {
  local step_num="$1"
  awk -v snum="$step_num" '
    BEGIN { found = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^###[[:space:]]+Step[[:space:]]+/ ) {
        # Extract step number from this header
        line = $0
        sub(/^###[[:space:]]+Step[[:space:]]+/, "", line)
        sub(/:.*/, "", line)
        sub(/[^0-9].*/, "", line)
        if (found) exit
        if (line == snum) { found = 1; next }
      }
      # Stop at EPIC markers (they separate step groups)
      if (found && $0 ~ /^\*\*EPIC[[:space:]]+[0-9]+/) exit
      if (found) print
    }
  ' "$plan"
}

# Helper: extract a bold-prefixed field value from step content
# e.g., **Objective:** value
extract_bold_field() {
  local content="$1"
  local field="$2"
  echo "$content" | awk -v field="$field" '
    BEGIN { found = 0; val = "" }
    {
      gsub(/\r$/, "")
      # Match **Field:** or **Field :** patterns
      if ($0 ~ "^\\*\\*" field "(\\s*):") {
        sub("^\\*\\*" field "[[:space:]]*:[[:space:]]*\\*\\*[[:space:]]*", "", $0)
        sub("^\\*\\*" field ":[[:space:]]*\\*\\*[[:space:]]*", "", $0)
        # Handle case where value is on same line as field name
        sub("^.*\\*\\*[[:space:]]*", "", $0)
        if ($0 != "") val = $0
        found = 1
        next
      }
      # Stop at next bold field or section header
      if (found && ($0 ~ /^\*\*[A-Z]/ || $0 ~ /^###/)) exit
      if (found && $0 !~ /^[[:space:]]*$/) {
        if (val != "") val = val "\n" $0
        else val = $0
      }
    }
    END { print val }
  '
}

# Collect per-step data
steps_table_rows=""
all_ac=""
all_allowed_paths=""
all_forbidden_paths=""
all_artifacts=""
step_objectives=""
step_counter=0

for sn in "${phase_steps[@]}"; do
  step_counter=$(( step_counter + 1 ))
  step_content="$(extract_step_content "$sn")"

  # Extract objective (first line after **Objective:** or first paragraph)
  # Stops at blank line OR next **BoldField:** marker
  objective="$(echo "$step_content" | awk '
    BEGIN { found = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Objective:\*\*/) {
        sub(/^\*\*Objective:\*\*[[:space:]]*/, "", $0)
        print
        found = 1
        next
      }
      if (found && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^\*\*[A-Z]/)) exit
      if (found) print
    }
  ')"
  # Fallback: use step header description
  if [[ -z "$objective" ]]; then
    objective="$(echo "$step_content" | head -1)"
  fi

  # Extract AID Role
  role="$(echo "$step_content" | awk '
    /^\*\*AID Role:\*\*/ {
      sub(/^\*\*AID Role:\*\*[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
      print tolower($0)
      exit
    }
  ')"
  [[ -z "$role" ]] && role="backend"

  # Extract acceptance criteria (lines starting with - [ ])
  step_ac="$(echo "$step_content" | awk -v role="$role" '
    BEGIN { in_ac = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Acceptance Criteria:\*\*/) { in_ac = 1; next }
      if (in_ac && $0 ~ /^\*\*/) { in_ac = 0 }
      if (in_ac && $0 ~ /^- \[/) {
        # Check if it already has a [role] prefix
        if ($0 ~ /\[.+\].*\[/) {
          print
        } else {
          # Add [role] prefix after checkbox
          sub(/^- \[ \][[:space:]]*/, "", $0)
          printf "- [ ] [%s] %s\n", role, $0
        }
      }
    }
  ')"
  if [[ -n "$step_ac" ]]; then
    all_ac="${all_ac}${step_ac}"$'\n'
  fi

  # Extract files (Create/Modify paths)
  step_files="$(echo "$step_content" | awk '
    BEGIN { in_files = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Files:\*\*/) { in_files = 1; next }
      if (in_files && $0 ~ /^\*\*/) { in_files = 0 }
      if (in_files && ($0 ~ /Create:/ || $0 ~ /Modify:/)) {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        sub(/^Create:[[:space:]]*/, "", $0)
        sub(/^Modify:[[:space:]]*/, "", $0)
        # Extract just the path (before any description after " — ")
        sub(/[[:space:]]*--[[:space:]].*/, "", $0)
        sub(/[[:space:]]*\xe2\x80\x94[[:space:]].*/, "", $0)
        # Handle backtick-wrapped paths
        gsub(/`/, "", $0)
        # Trim whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 != "") print
      }
    }
  ')"
  if [[ -n "$step_files" ]]; then
    all_allowed_paths="${all_allowed_paths}${step_files}"$'\n'
  fi

  # Extract artifacts from step files and description
  step_artifacts="$(echo "$step_content" | awk '
    BEGIN { in_files = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Files:\*\*/) { in_files = 1; next }
      if (in_files && $0 ~ /^\*\*/) { in_files = 0 }
      if (in_files && $0 ~ /^[[:space:]]*-/) {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        if ($0 != "") print "- " $0
      }
    }
  ')"
  if [[ -n "$step_artifacts" ]]; then
    all_artifacts="${all_artifacts}${step_artifacts}"$'\n'
  fi

  # Build step objectives list for Goal section
  step_objectives="${step_objectives}- Step ${sn}: ${objective}"$'\n'

  # Extract dependencies from step content
  step_deps="$(echo "$step_content" | awk '
    BEGIN { in_deps = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps = 1; next }
      if (in_deps && $0 ~ /^\*\*/) { in_deps = 0 }
      if (in_deps && $0 ~ /Depends on:/) {
        sub(/.*Depends on:[[:space:]]*/, "", $0)
        # Extract step references: "Step 1" → "1"
        gsub(/Step /, "", $0)
        gsub(/[()]/, "", $0)
        print
      }
    }
  ')"

  # Build Steps table row
  # Collapse multi-line objective to single line for table
  safe_objective="$(echo "$objective" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  # Escape pipe characters in objective
  safe_objective="${safe_objective//|/\\|}"
  # Truncate to reasonable length for table
  if [[ "${#safe_objective}" -gt 100 ]]; then
    safe_objective="${safe_objective:0:97}..."
  fi

  # Determine depends_on for this step within the phase
  depends_on_str="---"
  if [[ -n "$step_deps" ]]; then
    # Convert step references to the format expected in EPIC table
    depends_on_str="$(echo "$step_deps" | sed 's/,/, /g' | head -1)"
    [[ -z "$depends_on_str" ]] && depends_on_str="---"
  fi

  steps_table_rows="${steps_table_rows}| ${step_counter} | ${role} | ${safe_objective} | ${depends_on_str} | --- |"$'\n'
done

# ---------------------------------------------------------------------------
# Step 6: Extract plan-level sections for the EPIC
# ---------------------------------------------------------------------------

# Context
plan_context="$(extract_section "$plan" "Context")"
# Trim trailing whitespace/newlines
plan_context="$(echo "$plan_context" | sed '/^[[:space:]]*$/d')"
epic_context="${plan_context}

This EPIC covers Phase ${phase} of ${total} from plan ${plan_id}."

# Goal — scope to this phase's deliverables
plan_goal="$(extract_section "$plan" "Goal")"
plan_goal="$(echo "$plan_goal" | sed '/^[[:space:]]*$/d')"

if [[ "$total" -eq 1 ]]; then
  epic_goal="$plan_goal"
else
  epic_goal="${plan_goal}

Phase ${phase}/${total} deliverables:
${step_objectives}"
fi

# Scope Allowed — aggregate from phase steps' files, deduplicate directories
scope_allowed=""
if [[ -n "$all_allowed_paths" ]]; then
  # Extract unique directory paths and file paths
  scope_allowed="$(echo "$all_allowed_paths" | sort -u | awk '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 != "") printf "- `%s`\n", $0
    }
  ')"
fi
[[ -z "$scope_allowed" ]] && scope_allowed="- <!-- No specific paths identified from plan steps -->"

# Scope Forbidden — extract from plan "Out of scope" items
plan_scope="$(extract_section "$plan" "Scope")"
scope_forbidden="$(echo "$plan_scope" | awk '
  BEGIN { in_out = 0 }
  {
    gsub(/\r$/, "")
    if ($0 ~ /^\*\*Out of scope:\*\*/ || $0 ~ /^Out of scope:/) { in_out = 1; next }
    if (in_out && ($0 ~ /^\*\*/ || $0 ~ /^##/)) { in_out = 0 }
    if (in_out && $0 ~ /^-/) {
      print
    }
  }
')"
[[ -z "$scope_forbidden" ]] && scope_forbidden="- <!-- No forbidden zones specified in plan -->"

# Artifacts
if [[ -z "$all_artifacts" ]]; then
  all_artifacts="- <!-- Auto-generated from plan step files -->"
fi

# Constraints
plan_constraints="$(extract_section "$plan" "Constraints")"
plan_constraints="$(echo "$plan_constraints" | sed '/^[[:space:]]*$/d')"
[[ -z "$plan_constraints" ]] && plan_constraints="- <!-- No constraints specified in plan -->"

# DoD Gates — use defaults
dod_gates="- docs_updated"

# Dependencies section
internal_deps=""
if [[ "$phase" -gt 1 ]]; then
  prev_phase=$(( phase - 1 ))
  prev_epic_id="E-${plan_num}-${prev_phase}_${total}"
  internal_deps="- ${prev_epic_id} — Previous phase must complete first"
else
  internal_deps="<!-- First phase --- no internal dependencies -->"
fi

# External dependencies — parse plan for dependency references
#
# Plans may declare dependencies in two places:
#   1. **Dependencies:** bold field within ## Scope section
#   2. ## Dependencies section (if present as a real H2)
# We check both, but filter out self-references to the current plan_id.
plan_deps=""
# First try: look for **Dependencies:** within the Scope section
plan_scope_full="$(extract_section "$plan" "Scope")"
scope_deps="$(echo "$plan_scope_full" | awk '
  BEGIN { in_deps = 0 }
  {
    gsub(/\r$/, "")
    if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps = 1; next }
    if (in_deps && ($0 ~ /^\*\*/ || $0 ~ /^##/ || $0 ~ /^$/)) { in_deps = 0 }
    if (in_deps) print
  }
')"
if [[ -n "$scope_deps" ]]; then
  plan_deps="$scope_deps"
fi

external_deps=""
if [[ -n "$plan_deps" ]]; then
  # Look for references to other plans (P###) or EPICs (E-###-N_M)
  # Filter out self-references to the current plan
  ext_refs="$(echo "$plan_deps" | grep -oE '(P[0-9]{3}|E-[0-9]{3}-[0-9]+_[0-9]+)' 2>/dev/null | grep -v "^${plan_id}$" || true)"
  if [[ -n "$ext_refs" ]]; then
    while IFS= read -r ref; do
      [[ -n "$ref" ]] && external_deps="${external_deps}- ${ref}"$'\n'
    done <<< "$ext_refs"
  fi
fi
if [[ -z "$external_deps" ]]; then
  external_deps="<!-- No external dependencies -->"
fi

# Queue Implications — depends_on list
depends_on_list="[]"
dep_items=()
if [[ "$phase" -gt 1 ]]; then
  prev_phase=$(( phase - 1 ))
  dep_items+=("E-${plan_num}-${prev_phase}_${total}")
fi
# Add external EPIC deps (only fully-qualified EPIC IDs, not plan IDs)
if [[ -n "$plan_deps" ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && dep_items+=("$ref")
  done <<< "$(echo "$plan_deps" | grep -oE 'E-[0-9]{3}-[0-9]+_[0-9]+' 2>/dev/null || true)"
fi

if [[ "${#dep_items[@]}" -gt 0 ]]; then
  # Build JSON-style list
  dep_str=""
  for item in "${dep_items[@]}"; do
    [[ -n "$dep_str" ]] && dep_str="${dep_str}, "
    dep_str="${dep_str}${item}"
  done
  depends_on_list="[${dep_str}]"
fi

# Hints
hints="- expected_steps: ${#phase_steps[@]}
- complexity: medium
- parallelism_potential: low"

# ---------------------------------------------------------------------------
# Step 7: Build the EPIC from template
# ---------------------------------------------------------------------------

# Read the template
template_content="$(cat "$epic_template")"

# We build the EPIC by constructing it section-by-section rather than doing
# sed-based placeholder replacement (which is fragile with multiline content
# and special characters). Instead, we emit the EPIC directly.

plan_filename="$(basename "$plan")"

# Build the steps table
steps_table_header="| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|"
steps_table="${steps_table_header}
${steps_table_rows}"

# Write the full EPIC
cat > "${output_dir}/${epic_id}-${slug}.md" << EPICEOF
---
status: active
plan_ref: ${plan}
plan_epics_total: ${total}
runs_total: 1
runs_completed: 0
---

# EPIC: ${epic_id} --- ${title}

## Context

${epic_context}

## Goal

${epic_goal}

## Scope

### Allowed files/paths
${scope_allowed}

### Forbidden zones
${scope_forbidden}

## Artifacts

${all_artifacts}

## Constraints

${plan_constraints}

## DoD Gates

${dod_gates}

## Acceptance Criteria

${all_ac}

## Dependencies

### Internal (same plan)
${internal_deps}

### External (other plans/EPICs)
${external_deps}

### Queue Implications
depends_on: ${depends_on_list}

## Steps (Role Pipeline)

${steps_table}

## Run Breakdown

### Run 1: Phase ${phase}
**Goal:** ${plan_goal}
**Deliverables:** Phase ${phase} of ${total} from plan ${plan_id}

## Hints

${hints}

## Notes

<!-- Auto-generated by aid-plan-to-epic.sh from ${plan_filename} on $(date -u +%Y-%m-%d) -->
EPICEOF

# ---------------------------------------------------------------------------
# Step 8: Output the absolute path to the generated file
# ---------------------------------------------------------------------------
output_file="${output_dir}/${epic_id}-${slug}.md"

# Resolve to absolute path if not already
if [[ "${output_file:0:1}" != "/" ]]; then
  output_file="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
fi

echo "$output_file"
