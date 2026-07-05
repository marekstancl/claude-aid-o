#!/usr/bin/env bash
# =============================================================================
# aid-epic-to-json.sh — Convert an EPIC.md into plan.json
#
# Usage:
#   ./aid-epic-to-json.sh \
#     --epic <path> --schema <path> --output-dir <path> \
#     [--plan-source <path>]
#
# Parses the EPIC, extracts steps/dependencies/parallel groups, auto-generates
# analysis groups, builds a plan.json conforming to plan.schema.json, creates
# an evidence directory.
#
# stdout: JSON manifest { plan_json, run_id, evidence_dir }
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
epic=""
schema=""
output_dir=""
plan_source=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic)         epic="$2";         shift 2 ;;
    --schema)       schema="$2";       shift 2 ;;
    --output-dir)   output_dir="$2";   shift 2 ;;
    --plan-source)  plan_source="$2";  shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# =============================================================================
# Validate required arguments
# =============================================================================
[[ -z "$epic" ]]       && error_exit "Missing required argument: --epic" 1
[[ -z "$schema" ]]     && error_exit "Missing required argument: --schema" 1
[[ -z "$output_dir" ]] && error_exit "Missing required argument: --output-dir" 1

[[ ! -f "$epic" ]]   && error_exit "EPIC file not found: $epic" 3
[[ ! -f "$schema" ]] && error_exit "Schema file not found: $schema" 3

# Create output directory if it does not exist
mkdir -p "$output_dir" 2>/dev/null || error_exit "Cannot create output directory: $output_dir" 3

# =============================================================================
# Valid roles enum (must match plan.schema.json)
# =============================================================================
VALID_ROLES="architect domain backend frontend qa security observability docs-writer release e2e"

validate_role() {
  local role="$1"
  local r
  for r in $VALID_ROLES; do
    [[ "$r" == "$role" ]] && return 0
  done
  return 1
}

# =============================================================================
# Step 1: Parse EPIC frontmatter
# =============================================================================
frontmatter="$(parse_frontmatter "$epic")"

fm_plan_ref=""
fm_plan_epics_total=""
fm_status=""

while IFS='=' read -r key val; do
  case "$key" in
    plan_ref)          fm_plan_ref="$val" ;;
    plan_epics_total)  fm_plan_epics_total="$val" ;;
    status)            fm_status="$val" ;;
  esac
done <<< "$frontmatter"

# Use --plan-source if provided, otherwise fall back to frontmatter plan_ref
if [[ -z "$plan_source" ]]; then
  if [[ -n "$fm_plan_ref" && "$fm_plan_ref" != "null" ]]; then
    plan_source="$fm_plan_ref"
  fi
fi

# =============================================================================
# Step 2: Extract epic_id from filename
# =============================================================================
epic_basename="$(basename "$epic")"

# Try standard format: E-NNN-N_N (e.g., E-018-1_3)
if [[ "$epic_basename" =~ (E-[0-9]{3,}-[0-9]+_[0-9]+) ]]; then
  epic_id="${BASH_REMATCH[1]}"
# Try legacy format: E-YYYYMMDD-XXXX
elif [[ "$epic_basename" =~ (E-[0-9]{8}-[0-9]{4}) ]]; then
  epic_id="${BASH_REMATCH[1]}"
  echo "WARNING: Legacy EPIC ID format detected: $epic_id" >&2
# Try extracting from H1 header inside the file
else
  epic_id="$(awk '
    {
      gsub(/\r$/, "")
      if ($0 ~ /^# EPIC:/) {
        sub(/^# EPIC:[[:space:]]*/, "", $0)
        sub(/[[:space:]]*---.*/, "", $0)
        sub(/[[:space:]]*\xe2\x80\x94.*/, "", $0)
        gsub(/[[:space:]]+$/, "", $0)
        print
        exit
      }
    }
  ' "$epic")"
  [[ -z "$epic_id" ]] && error_exit "Cannot extract EPIC ID from filename or H1 header: $epic_basename" 1
fi

# =============================================================================
# Step 3: Parse Steps table from EPIC
# =============================================================================
steps_section="$(extract_section "$epic" "Steps (Role Pipeline)")"

if [[ -z "$steps_section" ]]; then
  error_exit "EPIC missing 'Steps (Role Pipeline)' section" 1
fi

# Find and parse the table rows (skip header and separator lines)
# Table format: | # | Role | Objective | Depends On | Parallel Group |
declare -a step_nums=()
declare -a step_roles=()
declare -a step_objectives=()
declare -a step_depends=()
declare -a step_parallel=()

# Parse table using awk — extract data rows (skip header/separator)
table_data="$(echo "$steps_section" | awk '
  BEGIN { header_found = 0; sep_found = 0 }
  {
    gsub(/\r$/, "")
    # Skip non-table lines
    if ($0 !~ /^\|/) next
    # Detect header line (contains "Role" or "#")
    if (!header_found && ($0 ~ /Role/ || $0 ~ /Objective/)) {
      header_found = 1
      next
    }
    # Detect separator line (contains ---)
    if (header_found && !sep_found && $0 ~ /\|[[:space:]]*-/) {
      sep_found = 1
      next
    }
    # Data rows
    if (sep_found) {
      print
    }
  }
')"

if [[ -z "$table_data" ]]; then
  error_exit "EPIC Steps table has no data rows" 1
fi

row_count=0
while IFS= read -r row; do
  [[ -z "$row" ]] && continue

  # Split on | — row looks like: | 1 | backend | Objective text | 1, 2 | group-1 |
  # Remove leading/trailing |
  stripped="$(echo "$row" | sed 's/^[[:space:]]*|//; s/|[[:space:]]*$//')"

  # Split into fields on |
  IFS='|' read -ra fields <<< "$stripped"

  # We need at least 5 fields
  if [[ "${#fields[@]}" -lt 5 ]]; then
    # Try with fewer fields; pad with dashes
    while [[ "${#fields[@]}" -lt 5 ]]; do
      fields+=("---")
    done
  fi

  # Trim whitespace from each field
  num="$(echo "${fields[0]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  role="$(echo "${fields[1]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
  objective="$(echo "${fields[2]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  depends_on="$(echo "${fields[3]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  parallel_group="$(echo "${fields[4]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  # Skip if num is not a number (might be a malformed row)
  if [[ ! "$num" =~ ^[0-9]+$ ]]; then
    continue
  fi

  # Validate role
  if ! validate_role "$role"; then
    error_exit "Invalid role '$role' in step $num. Valid roles: $VALID_ROLES" 1
  fi

  # Validate objective length (schema requires minLength: 10)
  if [[ "${#objective}" -lt 10 ]]; then
    error_exit "Step $num objective too short (min 10 chars): '$objective'" 1
  fi

  step_nums+=("$num")
  step_roles+=("$role")
  step_objectives+=("$objective")
  step_depends+=("$depends_on")
  step_parallel+=("$parallel_group")
  row_count=$(( row_count + 1 ))
done <<< "$table_data"

if [[ "$row_count" -eq 0 ]]; then
  error_exit "No valid steps found in EPIC Steps table" 1
fi

# =============================================================================
# Step 3b: Per-step Acceptance Criteria pre-flight (E-047-4_7 REOPEN, AID-v3 §1)
# -----------------------------------------------------------------------------
# Root cause of the E-047-4_7 REOPEN: an auto-generated multi-step EPIC carried
# Acceptance Criteria for STEP 1 ONLY, so the CP2/CP3/CP4 chain had no contract
# to verify steps 2..N against and managerial-read-model bugs shipped. A
# detector without enforcement is decoration (AID-v3-principles §1) — so this is
# an OUT-OF-BAND HARD FAIL, not a warning: a multi-step EPIC must carry at least
# one acceptance criterion per step. Escape hatch for the rare legitimately
# sparse EPIC: AID_ALLOW_SPARSE_AC=1 (logged, intentional).
# =============================================================================
ac_section="$(extract_section "$epic" "Acceptance Criteria")"
# Count real AC checkboxes: lines like `- [ ]` / `- [x]` that are not the
# template's `<!-- e.g. ... -->` placeholder comments.
ac_count=0
if [[ -n "$ac_section" ]]; then
  ac_count="$(printf '%s\n' "$ac_section" \
    | grep -E '^[[:space:]]*-[[:space:]]+\[[ xX]\]' \
    | grep -cvE '<!--' || true)"
fi
if [[ "$row_count" -gt 1 && "$ac_count" -lt "$row_count" ]]; then
  if [[ "${AID_ALLOW_SPARSE_AC:-0}" == "1" ]]; then
    echo "WARNING: EPIC has $row_count steps but only $ac_count acceptance criteria — proceeding (AID_ALLOW_SPARSE_AC=1)." >&2
  else
    error_exit "EPIC has $row_count steps but only $ac_count acceptance criteria. A multi-step EPIC needs >= 1 testable acceptance criterion per step so every step has a contract the CP chain can verify (AID-v3 §1). Add per-step AC, or set AID_ALLOW_SPARSE_AC=1 to override deliberately." 1
  fi
fi

# =============================================================================
# Step 4: Generate step IDs
# =============================================================================
declare -a step_ids=()
for i in "${!step_nums[@]}"; do
  # Sanitize the role for use in the step ID: the plan.schema step.id pattern
  # (^step_[a-z0-9_]+$) forbids hyphens, but valid roles like "docs-writer"
  # contain one. Map hyphens to underscores so the generated ID validates while
  # the step.role field below keeps its canonical hyphenated value.
  role_id="${step_roles[$i]//-/_}"
  step_ids+=("step_${step_nums[$i]}_${role_id}")
done

# Build lookup: step number -> index for dependency resolution
declare -A num_to_idx=()
declare -A role_to_idx=()
for i in "${!step_nums[@]}"; do
  num_to_idx["${step_nums[$i]}"]="$i"
  # For role-based deps, store the first (or only) step with that role
  # If multiple steps share a role, the last one wins (consistent with EPIC intent)
  role_to_idx["${step_roles[$i]}"]="$i"
done

# =============================================================================
# Step 5: Build dependencies array
# =============================================================================
deps_json="[]"
declare -A dep_edges=()  # for cycle detection: "before_idx->after_idx"

for i in "${!step_nums[@]}"; do
  dep_val="${step_depends[$i]}"
  step_id="${step_ids[$i]}"

  # Normalize dashes (em-dash, en-dash, triple-dash, single-dash)
  # These all mean "no dependency"
  if [[ "$dep_val" == "—" || "$dep_val" == "–" || "$dep_val" == "---" || "$dep_val" == "-" || "$dep_val" == "—" || -z "$dep_val" ]]; then
    continue
  fi

  # Split on comma for multiple dependencies
  IFS=',' read -ra dep_parts <<< "$dep_val"

  for dep_part in "${dep_parts[@]}"; do
    dep_part="$(echo "$dep_part" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$dep_part" ]] && continue

    dep_step_id=""

    # Try to resolve: is it a step number?
    if [[ "$dep_part" =~ ^[0-9]+$ ]]; then
      dep_num="$dep_part"
      if [[ -n "${num_to_idx[$dep_num]+_}" ]]; then
        dep_idx="${num_to_idx[$dep_num]}"
        dep_step_id="${step_ids[$dep_idx]}"
      else
        error_exit "Step ${step_nums[$i]} depends on step $dep_num which does not exist" 1
      fi
    # Try to resolve: is it a role name?
    elif validate_role "$dep_part"; then
      if [[ -n "${role_to_idx[$dep_part]+_}" ]]; then
        dep_idx="${role_to_idx[$dep_part]}"
        dep_step_id="${step_ids[$dep_idx]}"
      else
        error_exit "Step ${step_nums[$i]} depends on role '$dep_part' which has no matching step" 1
      fi
    else
      error_exit "Step ${step_nums[$i]} has unresolvable dependency: '$dep_part'" 1
    fi

    # Add dependency edge
    deps_json="$(echo "$deps_json" | jq \
      --arg before "$dep_step_id" \
      --arg after "$step_id" \
      --arg reason "Declared in EPIC steps table" \
      '. + [{"before": $before, "after": $after, "reason": $reason}]')"

    # Record edge for cycle detection
    dep_edges["${dep_step_id}->${step_id}"]=1
  done
done

# =============================================================================
# Step 6: Cycle detection — via shared lib
# =============================================================================
# Source shared lib and call build_plan_graph
# shellcheck source=lib/aid-plan-graph.sh
source "${SCRIPT_DIR}/lib/aid-plan-graph.sh"

# Build newline-joined inputs for build_plan_graph
step_ids_nl="$(printf '%s\n' "${step_ids[@]}")"
edges_nl="$(printf '%s\n' "${!dep_edges[@]}")"

pg_result="$(build_plan_graph "$step_ids_nl" "$edges_nl")"
pg_status=$?

if [[ $pg_status -ne 0 ]]; then
  error_exit "build_plan_graph failed (exit $pg_status)" 1
fi

# Check for cycles in the result
cycles_count="$(echo "$pg_result" | jq '.cycles | length')"
if [[ "$cycles_count" -gt 0 ]]; then
  cycle_nodes="$(echo "$pg_result" | jq -r '.cycles | join(", ")')"
  error_exit "Circular dependency detected among steps: $cycle_nodes" 1
fi

# =============================================================================
# Step 7: Build parallel_groups array
# =============================================================================
declare -A pg_members=()  # group_name -> space-separated step_ids

for i in "${!step_nums[@]}"; do
  pg="${step_parallel[$i]}"
  # Normalize dashes
  if [[ "$pg" == "—" || "$pg" == "–" || "$pg" == "---" || "$pg" == "-" || -z "$pg" ]]; then
    continue
  fi
  pg_members["$pg"]="${pg_members[$pg]:-} ${step_ids[$i]}"
done

parallel_json="[]"
for group_name in "${!pg_members[@]}"; do
  members="${pg_members[$group_name]}"
  # Trim leading space
  members="$(echo "$members" | sed 's/^[[:space:]]+//')"

  # Count members — only include groups with 2+
  member_count=$(echo "$members" | wc -w | tr -d ' ')
  if [[ "$member_count" -ge 2 ]]; then
    # Build JSON array of step IDs
    member_arr="[]"
    for mid in $members; do
      member_arr="$(echo "$member_arr" | jq --arg m "$mid" '. + [$m]')"
    done
    parallel_json="$(echo "$parallel_json" | jq --argjson arr "$member_arr" '. + [$arr]')"
  fi
done

# =============================================================================
# Step 8: Build analysis_groups array (auto-trigger rules)
# =============================================================================
analysis_json="[]"
analysis_counter=0

for i in "${!step_nums[@]}"; do
  objective_lower="$(echo "${step_objectives[$i]}" | tr '[:upper:]' '[:lower:]')"
  step_role="${step_roles[$i]}"
  step_id="${step_ids[$i]}"

  # Rule 1: Security patterns trigger security review
  if echo "$objective_lower" | grep -qE '(auth|token|encrypt|sql|inject|secret|password|credential)'; then
    if [[ "$step_role" != "security" ]]; then
      analysis_counter=$(( analysis_counter + 1 ))
      analysis_json="$(echo "$analysis_json" | jq \
        --arg id "analysis_${analysis_counter}_security_review" \
        --arg target "$step_id" \
        '. + [{"id": $id, "target": $target, "agents": ["security"], "mode": "review", "merge_strategy": "union", "trigger": "auto"}]')"
    fi
  fi

  # Rule 2: Migration/schema/database patterns trigger backend+security validation
  if echo "$objective_lower" | grep -qE '(migrat|schema|database|model)'; then
    agents="[]"
    if [[ "$step_role" != "backend" ]]; then
      agents="$(echo "$agents" | jq '. + ["backend"]')"
    fi
    if [[ "$step_role" != "security" ]]; then
      agents="$(echo "$agents" | jq '. + ["security"]')"
    fi
    agent_count="$(echo "$agents" | jq 'length')"
    if [[ "$agent_count" -gt 0 ]]; then
      analysis_counter=$(( analysis_counter + 1 ))
      analysis_json="$(echo "$analysis_json" | jq \
        --arg id "analysis_${analysis_counter}_db_validation" \
        --arg target "$step_id" \
        --argjson agents "$agents" \
        '. + [{"id": $id, "target": $target, "agents": $agents, "mode": "validation", "merge_strategy": "consensus", "trigger": "auto"}]')"
    fi
  fi

  # Rule 3: Contract/ADR patterns trigger backend+frontend validation
  if echo "$objective_lower" | grep -qE '(contract|adr|api design|interface)'; then
    agents="[]"
    if [[ "$step_role" != "backend" ]]; then
      agents="$(echo "$agents" | jq '. + ["backend"]')"
    fi
    if [[ "$step_role" != "frontend" ]]; then
      agents="$(echo "$agents" | jq '. + ["frontend"]')"
    fi
    agent_count="$(echo "$agents" | jq 'length')"
    if [[ "$agent_count" -gt 0 ]]; then
      analysis_counter=$(( analysis_counter + 1 ))
      analysis_json="$(echo "$analysis_json" | jq \
        --arg id "analysis_${analysis_counter}_contract_validation" \
        --arg target "$step_id" \
        --argjson agents "$agents" \
        '. + [{"id": $id, "target": $target, "agents": $agents, "mode": "validation", "merge_strategy": "union", "trigger": "auto"}]')"
    fi
  fi

  # Rule 4: Complex outputs (objective mentions 5+ distinct items) trigger architect review
  # Count items separated by +, commas, or "and"
  item_count="$(echo "${step_objectives[$i]}" | { grep -oE '[+,]|( and )' || true; } | wc -l | tr -d ' ')"
  if [[ "$item_count" -ge 4 && "$step_role" != "architect" ]]; then
    analysis_counter=$(( analysis_counter + 1 ))
    analysis_json="$(echo "$analysis_json" | jq \
      --arg id "analysis_${analysis_counter}_complexity_review" \
      --arg target "$step_id" \
      '. + [{"id": $id, "target": $target, "agents": ["architect"], "mode": "review", "merge_strategy": "union", "trigger": "auto"}]')"
  fi
done

# =============================================================================
# Step 9: Extract per-step detail from EPIC sections
# =============================================================================

# Helper: parse Step UI Contracts section from EPIC
# Returns the raw content of the ## Step UI Contracts section
parse_step_ui_contracts() {
  local epic_content="$1"
  echo "$epic_content" | awk '
    /^## Step UI Contracts/ { found=1; next }
    found && /^## / { exit }
    found { print }
  '
}

# Extract the Step UI Contracts section once (used per-step in the loop below)
ui_contracts_section="$(parse_step_ui_contracts "$(cat "$epic")")"

# =============================================================================
# _aid_parse_scoping_line — split a per-step scoping HTML-comment line into
# its files=[...] and ac=[...] JSON-array substrings (D2).
#
# Shape (frozen by aid-plan-to-epic.sh / E-TEST-005 fixture, P058 Step 2):
#   <!-- step-N: files=["Create: `path` — desc", ...]; ac=["AC text", ...] -->
#
# Both files=/ac= values are `jq -R -s -c` compact JSON arrays of strings. A
# literal ";" or "|" inside a string value is NOT JSON-escaped, so this
# function anchors the split on the literal boundary "]; ac=[" (the files
# array's closing bracket immediately followed by the ac array's opening
# bracket) rather than the first "|" or ";" found anywhere in the line —
# that boundary is far less likely to appear inside prose/AC text than a
# bare ";" or "|" alone (verified against the E-TEST-005 fixture, whose
# qa-step AC deliberately embeds a literal "|" and whose backend-step AC
# deliberately embeds a literal, non-sentinel-encoded "-->").
#
# Args: $1 = raw matched line (e.g. from `grep "<!-- step-N: files="`)
#       $2 = step number N (used only to build the fixed prefix to strip)
# Output (stdout, on success): 2 lines — files-JSON then ac-JSON.
# Returns: 1 if the line does not match the expected shape (caller must
#          treat this as "no block for this step" and fall back to broadcast).
# =============================================================================
_aid_parse_scoping_line() {
  local line="$1"
  local step_n="$2"
  local prefix="<!-- step-${step_n}: files="

  [[ "$line" == "$prefix"* ]] || return 1
  local body="${line#"$prefix"}"

  [[ "$body" == *" -->" ]] || return 1
  body="${body% -->}"

  [[ "$body" == *"]; ac=["* ]] || return 1
  # Anchor on the LAST occurrence of "; ac=[", not the first: a files[] value
  # can itself contain that literal substring (e.g. prose describing this
  # very block syntax — this is exactly what happens when P058's own plan
  # text is regenerated through this parser, a real self-consistency
  # failure caught during Step 5). `%` (shortest-suffix removal) and `##`
  # (longest-prefix removal) both anchor on the rightmost match, unlike the
  # previous `%%`/`#` pairing which anchored on the leftmost (first) one.
  local files_part="${body%; ac=[*}"
  local ac_part="${body##*; ac=}"

  printf '%s\n%s\n' "$files_part" "$ac_part"
}

# =============================================================================
# _aid_split_path_entry — D4 cleaner for a single RAW Files bullet (label
# already stripped). PORTED from scripts/aid-plan-to-epic.sh's function of
# the same name — aid-epic-to-json.sh does not source that script (only
# lib/common.sh is shared between the two CLI entry points), so this exact
# algorithm is reimplemented here rather than called cross-script. See the
# source function's comment for the full rationale; summary:
#   - The path declaration always sits immediately after the "Create:"/
#     "Modify:" label, as ONE backtick-wrapped span, or several joined by
#     literal " + `" (the "`a.md` + `b.md`" dual-file convention).
#   - Anything else (a "(...)" parenthetical, an em-dash/"--" description, or
#     any other backtick span later in a prose-heavy bullet) stops the run
#     and is discarded as prose, not consumed as a path.
#   - No leading backtick span found -> fall back to stripping the entry
#     after the first "--"/em-dash separator, then removing stray backticks.
#
# Args: $1 = one RAW Files bullet with the "Create:"/"Modify:" label already
#            stripped (e.g. "`CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (identical)")
# Output (stdout): one cleaned path per line (may be more than one line).
# =============================================================================
_aid_split_path_entry() {
  local entry="$1"
  local rest="$entry"
  local candidate found_backtick_path=0 first_span=1

  while true; do
    if [[ "$first_span" -eq 1 ]]; then
      [[ "$rest" == '`'* ]] || break
    else
      [[ "$rest" == ' + `'* ]] || break
      rest="${rest# + }"
    fi
    rest="${rest#\`}"           # drop the opening backtick
    candidate="${rest%%\`*}"    # everything up to the next backtick
    rest="${rest#*\`}"          # drop through the closing backtick
    if [[ -n "$candidate" && "$candidate" != *[[:space:]]* ]]; then
      printf '%s\n' "$candidate"
      found_backtick_path=1
      first_span=0
    else
      break
    fi
  done

  if [[ "$found_backtick_path" -eq 0 ]]; then
    local fallback="$entry"
    fallback="${fallback%%--[[:space:]]*}"
    fallback="$(printf '%s' "$fallback" | sed 's/[[:space:]]*\xe2\x80\x94[[:space:]].*//')"
    fallback="${fallback//\`/}"
    fallback="$(printf '%s' "$fallback" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$fallback" ]] && printf '%s\n' "$fallback"
  fi
}

# =============================================================================
# _aid_allowed_paths_from_files_json — derive a step's cleaned allowed_paths
# JSON array from its RAW files[] JSON array (per D2/D4: outputs = files
# verbatim, allowed_paths = cleaned path(s) from the SAME files entries).
# Strips the "Create:"/"Modify:" label from each entry, then runs the
# remainder through _aid_split_path_entry (handles the multi-path
# "`a` + `b`" join and drops trailing prose). Order-preserving de-dup.
# Args: $1 = compact JSON array of RAW files[] strings.
# Output (stdout): compact JSON array of cleaned path strings.
# =============================================================================
_aid_allowed_paths_from_files_json() {
  local files_json="$1"
  local out_json="[]"
  local n idx entry stripped p
  n="$(echo "$files_json" | jq 'length')"
  for (( idx=0; idx<n; idx++ )); do
    entry="$(echo "$files_json" | jq -r --argjson i "$idx" '.[$i]')"
    stripped="$(printf '%s' "$entry" | sed -E 's/^(Create|Modify):[[:space:]]*//')"
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      out_json="$(echo "$out_json" | jq --arg p "$p" 'if index($p) then . else . + [$p] end')"
    done < <(_aid_split_path_entry "$stripped")
  done
  echo "$out_json"
}

# Extract Scope sections
scope_allowed_raw="$(extract_subsection "$epic" "Scope" "Allowed files/paths")"
scope_forbidden_raw="$(extract_subsection "$epic" "Scope" "Forbidden zones")"

# Parse allowed paths into array
allowed_paths_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  # Match lines starting with - that contain a path (not HTML comments)
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    path_val="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    # Remove backticks
    path_val="${path_val//\`/}"
    # Skip HTML comments and empty
    [[ "$path_val" == "<!--"* ]] && continue
    [[ -z "$path_val" ]] && continue
    allowed_paths_json="$(echo "$allowed_paths_json" | jq --arg p "$path_val" '. + [$p]')"
  fi
done <<< "$scope_allowed_raw"

# Parse forbidden paths into array
forbidden_paths_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    path_val="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    path_val="${path_val//\`/}"
    [[ "$path_val" == "<!--"* ]] && continue
    [[ -z "$path_val" ]] && continue
    # Strip trailing comment like " (command rewrites are EPIC 2)"
    path_val="$(echo "$path_val" | sed 's/[[:space:]]*(.*)[[:space:]]*$//')"
    forbidden_paths_json="$(echo "$forbidden_paths_json" | jq --arg p "$path_val" '. + [$p]')"
  fi
done <<< "$scope_forbidden_raw"

# Extract constraints
constraints_raw="$(extract_section "$epic" "Constraints")"
constraints_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    cval="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    [[ "$cval" == "<!--"* ]] && continue
    [[ -z "$cval" ]] && continue
    constraints_json="$(echo "$constraints_json" | jq --arg c "$cval" '. + [$c]')"
  fi
done <<< "$constraints_raw"

# Extract acceptance criteria (grouped by role prefix)
ac_raw="$(extract_section "$epic" "Acceptance Criteria")"
declare -A ac_by_role=()

while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  # Match lines like: - [ ] [role] criterion text
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*\[([a-z]+)\][[:space:]]*(.*) ]]; then
    ac_role="${BASH_REMATCH[1]}"
    ac_text="${BASH_REMATCH[2]}"
    # D3: join with the unit-separator sentinel (0x1f), NOT the literal "|||"
    # string — bash's IFS is a character CLASS, not a multi-char literal, so
    # IFS='|||' on the split side collapses to IFS='|' and fragments any AC
    # text containing a literal "|" (e.g. a jq expression). 0x1f cannot
    # appear in normal markdown/AC text and splits unambiguously as a single
    # character class.
    ac_by_role["$ac_role"]="${ac_by_role[$ac_role]:-}"$'\x1f'"$ac_text"
  elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*(.*) ]]; then
    # AC without role prefix — assign to all roles
    ac_text="${BASH_REMATCH[1]}"
    [[ "$ac_text" == "<!--"* ]] && continue
    [[ -z "$ac_text" ]] && continue
    ac_by_role["_global"]="${ac_by_role[_global]:-}"$'\x1f'"$ac_text"
  fi
done <<< "$ac_raw"

# Extract artifacts section
artifacts_raw="$(extract_section "$epic" "Artifacts")"
artifacts_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    aval="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    [[ "$aval" == "<!--"* ]] && continue
    [[ -z "$aval" ]] && continue
    artifacts_json="$(echo "$artifacts_json" | jq --arg a "$aval" '. + [$a]')"
  fi
done <<< "$artifacts_raw"

# =============================================================================
# Step 10: Build steps array
# =============================================================================
steps_json="[]"

for i in "${!step_nums[@]}"; do
  step_id="${step_ids[$i]}"
  step_role="${step_roles[$i]}"
  step_objective="${step_objectives[$i]}"
  step_n="${step_nums[$i]}"

  # Build inputs: EPIC spec + outputs from dependency steps
  inputs_json='["EPIC specification"]'
  dep_val="${step_depends[$i]}"
  if [[ "$dep_val" != "—" && "$dep_val" != "–" && "$dep_val" != "---" && "$dep_val" != "-" && -n "$dep_val" ]]; then
    IFS=',' read -ra dep_parts <<< "$dep_val"
    for dp in "${dep_parts[@]}"; do
      dp="$(echo "$dp" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$dp" ]] && continue
      if [[ "$dp" =~ ^[0-9]+$ ]]; then
        if [[ -n "${num_to_idx[$dp]+_}" ]]; then
          dep_idx="${num_to_idx[$dp]}"
          dep_sid="${step_ids[$dep_idx]}"
          inputs_json="$(echo "$inputs_json" | jq --arg s "Output from $dep_sid" '. + [$s]')"
        fi
      elif validate_role "$dp"; then
        if [[ -n "${role_to_idx[$dp]+_}" ]]; then
          dep_idx="${role_to_idx[$dp]}"
          dep_sid="${step_ids[$dep_idx]}"
          inputs_json="$(echo "$inputs_json" | jq --arg s "Output from $dep_sid" '. + [$s]')"
        fi
      fi
    done
  fi

  # ---------------------------------------------------------------------
  # D2 — per-step scoping block lookup (Step UI Contracts section). This is
  # a SEPARATE "<!-- step-N: files=...; ac=... -->" line from the
  # "ui_change_mode=" line handled below (Step 2 of P058 emits it as its
  # own line, not merged). If found and it parses cleanly, THIS step's
  # outputs/acceptance_criteria/allowed_paths come from the block — files[]
  # verbatim as outputs, ac[] verbatim as acceptance_criteria, and files[]
  # run through the ported D4 cleaner for allowed_paths. If no block exists
  # for this step, or it fails to parse, fall back to TODAY's exact
  # broadcast behavior (never emit an empty array just because the block is
  # absent/malformed — that would be a regression, not a fix; contract
  # enforcement belongs to a later step's gate, not this parser).
  # ---------------------------------------------------------------------
  step_has_block=0
  outputs_json="[]"
  step_ac_json="[]"
  step_allowed_paths_json="[]"

  if [[ -n "$ui_contracts_section" ]]; then
    # -m1 -F: match aid-contract-validate.sh's _ac_block_count() convention
    # (fixed-string, first-match-only) — without them, a self-referential
    # prose line elsewhere in the section that happens to contain this
    # exact literal prefix (e.g. text describing this very block syntax)
    # could make this grep return multiple/wrong lines, diverging from the
    # gate's own lookup for the same step (CP3 code-review finding).
    scoping_line="$(echo "$ui_contracts_section" | grep -m1 -F "<!-- step-${step_n}: files=" || true)"
    if [[ -n "$scoping_line" ]]; then
      scoping_parsed="$(_aid_parse_scoping_line "$scoping_line" "$step_n" || true)"
      if [[ -n "$scoping_parsed" ]]; then
        files_json_raw="$(echo "$scoping_parsed" | sed -n '1p')"
        ac_json_raw="$(echo "$scoping_parsed" | sed -n '2p')"
        # Reverse the @@AID_ARROW@@ sentinel encoding aid-plan-to-epic.sh
        # applies before JSON-encoding, so a literal "-->" inside a value
        # (e.g. an AC describing a "start --> middle --> end" flow) can
        # never truncate the HTML comment block early.
        files_json_decoded="$(echo "$files_json_raw" | sed 's/@@AID_ARROW@@/-->/g')"
        ac_json_decoded="$(echo "$ac_json_raw" | sed 's/@@AID_ARROW@@/-->/g')"
        if files_json_valid="$(echo "$files_json_decoded" | jq -c . 2>/dev/null)" \
           && ac_json_valid="$(echo "$ac_json_decoded" | jq -c . 2>/dev/null)"; then
          outputs_json="$files_json_valid"
          step_ac_json="$ac_json_valid"
          step_allowed_paths_json="$(_aid_allowed_paths_from_files_json "$files_json_valid")"
          step_has_block=1
        fi
      fi
    fi
  fi

  if [[ "$step_has_block" -eq 0 ]]; then
    # No-block fallback — preserve today's exact broadcast behavior for
    # backward compatibility with legacy/hand-authored EPICs and the
    # existing goldens (minimal-plan.golden.json, ui-contract-plan), which
    # predate this feature and carry no scoping block at all.
    outputs_json="$(echo "$artifacts_json" | jq '.')"

    # Add role-specific AC
    if [[ -n "${ac_by_role[$step_role]+_}" ]]; then
      IFS=$'\x1f' read -ra ac_items <<< "${ac_by_role[$step_role]}"
      for ac_item in "${ac_items[@]}"; do
        ac_item="$(echo "$ac_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -z "$ac_item" ]] && continue
        step_ac_json="$(echo "$step_ac_json" | jq --arg a "$ac_item" '. + [$a]')"
      done
    fi
    # Add global AC
    if [[ -n "${ac_by_role[_global]+_}" ]]; then
      IFS=$'\x1f' read -ra ac_items <<< "${ac_by_role[_global]}"
      for ac_item in "${ac_items[@]}"; do
        ac_item="$(echo "$ac_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -z "$ac_item" ]] && continue
        step_ac_json="$(echo "$step_ac_json" | jq --arg a "$ac_item" '. + [$a]')"
      done
    fi

    step_allowed_paths_json="$allowed_paths_json"
  fi

  # Extract ui_change fields for this step from the Step UI Contracts section
  step_ui_mode="null"
  step_ui_contract="null"

  if [[ -n "$ui_contracts_section" ]]; then
    ui_meta_line="$(echo "$ui_contracts_section" | grep "<!-- step-${step_n}:" || true)"
    if [[ -n "$ui_meta_line" ]]; then
      ui_mode="$(echo "$ui_meta_line" | sed -n "s/.*ui_change_mode=\([a-z_]*\).*/\1/p")"
      if [[ -n "$ui_mode" && "$ui_mode" != "null" ]]; then
        step_ui_mode="\"$ui_mode\""
        ui_path="$(echo "$ui_meta_line" | sed -n "s/.*| path=\([^|]*\).*/\1/p" | tr -d ' ')"
        ui_sha256="$(echo "$ui_meta_line" | sed -n "s/.*| sha256=\([^|]*\).*/\1/p" | tr -d ' ')"
        ui_schema_v="$(echo "$ui_meta_line" | sed -n "s/.*| schema_version=\([^| >]*\).*/\1/p" | tr -d ' ')"
        if [[ -n "$ui_path" ]]; then
          step_ui_contract="$(jq -n \
            --arg path "$ui_path" \
            --arg sha256 "$ui_sha256" \
            --arg schema_version "$ui_schema_v" \
            '{path: $path, sha256: $sha256, schema_version: $schema_version}')"
        fi
      fi
    fi
  fi

  # Assemble step object
  step_obj="$(jq -n \
    --arg id "$step_id" \
    --arg role "$step_role" \
    --arg objective "$step_objective" \
    --argjson inputs "$inputs_json" \
    --argjson outputs "$outputs_json" \
    --argjson constraints "$constraints_json" \
    --argjson allowed_paths "$step_allowed_paths_json" \
    --argjson forbidden_paths "$forbidden_paths_json" \
    --argjson acceptance_criteria "$step_ac_json" \
    --argjson ui_change_mode "$step_ui_mode" \
    --argjson ui_change_contract "$step_ui_contract" \
    '{
      id: $id,
      role: $role,
      objective: $objective,
      inputs: $inputs,
      outputs: $outputs,
      constraints: $constraints,
      allowed_paths: $allowed_paths,
      forbidden_paths: $forbidden_paths,
      acceptance_criteria: $acceptance_criteria,
      ui_change_mode: $ui_change_mode,
      ui_change_contract: $ui_change_contract
    }')"

  steps_json="$(echo "$steps_json" | jq --argjson step "$step_obj" '. + [$step]')"
done

# =============================================================================
# Step 11: Extract DoD Gates
# =============================================================================
gates_raw="$(extract_section "$epic" "DoD Gates")"
gates_json="[]"
valid_gates="tests_pass lint_pass security_scan_pass docs_updated"

while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    gate="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$gate" ]] && continue
    # Validate gate is in the enum
    is_valid=0
    for vg in $valid_gates; do
      [[ "$vg" == "$gate" ]] && is_valid=1
    done
    if [[ "$is_valid" -eq 1 ]]; then
      gates_json="$(echo "$gates_json" | jq --arg g "$gate" '. + [$g]')"
    fi
  fi
done <<< "$gates_raw"

# =============================================================================
# Step 12: Build budget
# =============================================================================
budget_json='{"max_retries_per_gate": 3}'

# =============================================================================
# Step 13: Assemble full plan.json
# =============================================================================
plan_source_arg="null"
if [[ -n "$plan_source" && "$plan_source" != "null" ]]; then
  plan_source_arg="$(jq -n --arg s "$plan_source" '$s')"
fi

# NOTE: large structured pieces (steps especially) are passed to jq via temp
# files + --slurpfile, NOT via --argjson on the command line. A fully-detailed
# plan can make $steps_json exceed the per-argument limit (MAX_ARG_STRLEN, 128KB
# on Linux), which fails with "jq: Argument list too long". --slurpfile reads the
# file's single JSON value into an array, so we dereference $var[0].
__pj_tmp="$(mktemp -d)"
printf '%s' "$steps_json"    > "${__pj_tmp}/steps.json"
printf '%s' "$deps_json"     > "${__pj_tmp}/deps.json"
printf '%s' "$parallel_json" > "${__pj_tmp}/parallel.json"
printf '%s' "$analysis_json" > "${__pj_tmp}/analysis.json"
printf '%s' "$gates_json"    > "${__pj_tmp}/gates.json"
printf '%s' "$budget_json"   > "${__pj_tmp}/budget.json"
plan_json="$(jq -n \
  --arg epic_id "$epic_id" \
  --argjson source_plan "$plan_source_arg" \
  --slurpfile steps "${__pj_tmp}/steps.json" \
  --slurpfile deps "${__pj_tmp}/deps.json" \
  --slurpfile parallel "${__pj_tmp}/parallel.json" \
  --slurpfile analysis "${__pj_tmp}/analysis.json" \
  --slurpfile gates "${__pj_tmp}/gates.json" \
  --slurpfile budget "${__pj_tmp}/budget.json" \
  '{
    epic_id: $epic_id,
    source_plan: $source_plan,
    version: 1,
    created_at: (now | todate),
    steps: $steps[0],
    dependencies: $deps[0],
    parallel_groups: $parallel[0],
    analysis_groups: $analysis[0],
    gates: $gates[0],
    budget: $budget[0]
  }')"
rm -rf "${__pj_tmp}"

# =============================================================================
# Step 14: Validate against schema (structural jq-based check)
#
# We validate the critical structural requirements from plan.schema.json:
#   - Required top-level fields: epic_id, version, steps, dependencies
#   - steps[].id pattern: ^step_[a-z0-9_]+$
#   - steps[].role in enum
#   - steps[].objective minLength 10
#   - dependencies[].before and .after reference existing step IDs
#   - parallel_groups items have minItems 2
#   - analysis_groups required fields and patterns
# =============================================================================
validation_errors="$(echo "$plan_json" | jq -r '
  def valid_roles: ["architect","domain","backend","frontend","qa","security","observability","docs-writer","release","e2e"];
  def valid_gates: ["tests_pass","lint_pass","security_scan_pass","docs_updated"];

  . as $root |
  [
    # Required top-level fields
    (if .epic_id == null or (.epic_id | type) != "string" then "missing or invalid epic_id" else empty end),
    (if .version == null or (.version | type) != "number" then "missing or invalid version" else empty end),
    (if .steps == null or (.steps | type) != "array" or (.steps | length) == 0 then "steps must be non-empty array" else empty end),
    (if .dependencies == null or (.dependencies | type) != "array" then "dependencies must be array" else empty end),

    # Step validation
    (.steps // [] | to_entries[] |
      .value as $step | .key as $idx |
      (
        (if ($step.id | test("^step_[a-z0-9_]+$") | not) then "step[\($idx)].id invalid: \($step.id)" else empty end),
        (if ([valid_roles[] | select(. == $step.role)] | length) == 0 then "step[\($idx)].role invalid: \($step.role)" else empty end),
        (if ($step.objective | length) < 10 then "step[\($idx)].objective too short" else empty end)
      )
    ),

    # Step IDs collection for reference validation
    (.steps | map(.id)) as $step_ids |

    # Dependency validation
    (.dependencies // [] | to_entries[] |
      .value as $dep | .key as $idx |
      (
        (if ($step_ids | index($dep.before)) == null then "dependencies[\($idx)].before references unknown step: \($dep.before)" else empty end),
        (if ($step_ids | index($dep.after)) == null then "dependencies[\($idx)].after references unknown step: \($dep.after)" else empty end)
      )
    ),

    # Parallel groups validation
    (.parallel_groups // [] | to_entries[] |
      .value as $pg | .key as $idx |
      (if ($pg | length) < 2 then "parallel_groups[\($idx)] must have at least 2 items" else empty end)
    ),

    # Analysis groups validation
    (.analysis_groups // [] | to_entries[] |
      .value as $ag | .key as $idx |
      (
        (if ($ag.id | test("^analysis_[0-9]+_[a-z_]+$") | not) then "analysis_groups[\($idx)].id invalid: \($ag.id)" else empty end),
        (if ($step_ids | index($ag.target)) == null then "analysis_groups[\($idx)].target references unknown step: \($ag.target)" else empty end)
      )
    ),

    # Gates validation
    (.gates // [] | .[] |
      if ([valid_gates[] | select(. == .)] | length) == 0 then "invalid gate: \(.)" else empty end
    )
  ] | if length > 0 then join("; ") else empty end
')"

if [[ -n "$validation_errors" ]]; then
  error_exit "Schema validation failed: $validation_errors" 1
fi

# =============================================================================
# Step 15: Generate run_id and evidence directory
# =============================================================================
# Build run_id from epic_id: E-018-1_3 -> R-E018-1
# Format: R-E{plan_num}-{phase} (matches README directory convention)
if [[ "$epic_id" =~ ^E-([0-9]+)-([0-9]+)_([0-9]+)$ ]]; then
  run_id="R-E${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
else
  # Fallback for legacy/non-standard IDs: sanitize and append run counter
  run_epic_part="$(echo "$epic_id" | sed 's/[^a-zA-Z0-9]//g')"
  run_id="R-${run_epic_part}-1"
fi

evidence_dir="${output_dir}/work/evidence/${epic_id}/${run_id}"
mkdir -p "$evidence_dir" 2>/dev/null || error_exit "Cannot create evidence directory: $evidence_dir" 3

# =============================================================================
# Step 16: Save plan.json
# =============================================================================
plan_json_path="${evidence_dir}/plan.json"
echo "$plan_json" > "$plan_json_path" || error_exit "Cannot write plan.json to $plan_json_path" 3

# =============================================================================
# Step 18: Copy EPIC to evidence as epic_input.md
# =============================================================================
cp "$epic" "${evidence_dir}/epic_input.md" 2>/dev/null || error_exit "Cannot copy EPIC to evidence directory" 3

# =============================================================================
# Step 19: Output JSON manifest to stdout
# =============================================================================
jq -n \
  --arg plan_json "$plan_json_path" \
  --arg run_id "$run_id" \
  --arg evidence_dir "$evidence_dir" \
  '{
    plan_json: $plan_json,
    run_id: $run_id,
    evidence_dir: $evidence_dir
  }'
