#!/usr/bin/env bash
# =============================================================================
# aid-epic-to-json.sh — Convert an EPIC.md into plan.json
#
# Usage:
#   ./aid-epic-to-json.sh \
#     --epic <path> --schema <path> --output-dir <aid-workspace-root, i.e. .aid-o> \
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
source "${SCRIPT_DIR}/lib/aid-scoping.sh"  # _aid_parse_scoping_line, _aid_split_path_entry, _aid_allowed_paths_from_files_json (shared with gates/aid-contract-validate.sh, v2.58.0 IMP-232)
source "${SCRIPT_DIR}/lib/aid-roots.sh"   # _aid_fm_get, aid_state_root — the source plan's brief binding (P109)
source "${SCRIPT_DIR}/lib/aid-generation-ids.sh"  # aid_gen_run_id — THE run_id derivation, shared with aid-auto-pipeline.sh (which seals it into the transaction) and aid-plan-to-epic.sh (which re-derives and verifies it)
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
[[ -z "$output_dir" ]] && error_exit "Missing required argument: --output-dir (the AID workspace root, normally .aid-o — evidence goes under <it>/work/evidence)" 1

[[ ! -f "$epic" ]]   && error_exit "EPIC file not found: $epic" 3
[[ ! -f "$schema" ]] && error_exit "Schema file not found: $schema" 3

# Create output directory if it does not exist
mkdir -p "$output_dir" 2>/dev/null || error_exit "Cannot create output directory: $output_dir" 3

# =============================================================================
# Valid roles enum (must match plan.schema.json)
# =============================================================================
VALID_ROLES="backend frontend qa security docs docs-writer release e2e"   # one list; the jq validation below reads it too (P107)

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
fm_source_step_ids=""

while IFS='=' read -r key val; do
  case "$key" in
    plan_ref)          fm_plan_ref="$val" ;;
    source_step_ids)   fm_source_step_ids="${val//\"/}" ;;
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
declare -a step_closes=()

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

# _split_table_row <stripped-row> — character-walk splitter honouring the
# producer's two-rule escape grammar (aid-plan-to-epic.sh, P074 Step 17):
# `\\` decodes to a literal backslash, `\|` to a literal pipe; an unescaped
# `|` is the field delimiter. A backslash before any other character (and a
# field-final backslash) is plain data and passes through verbatim, so legacy
# rows containing neither escape decode byte-identically to the old IFS split.
# Populates the global `fields` array.
_split_table_row() {
  local s="$1" ch="" cur="" i esc=0
  fields=()
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    if (( esc )); then
      case "$ch" in
        '|'|'\') cur+="$ch" ;;
        *)       cur+="\\$ch" ;;
      esac
      esc=0
    elif [[ "$ch" == '\' ]]; then
      esc=1
    elif [[ "$ch" == '|' ]]; then
      fields+=("$cur"); cur=""
    else
      cur+="$ch"
    fi
  done
  (( esc )) && cur+='\'
  fields+=("$cur")
}

row_count=0
while IFS= read -r row; do
  [[ -z "$row" ]] && continue

  # Split on unescaped | — row looks like: | 1 | backend | Objective text | 1, 2 | group-1 |
  # Remove leading/trailing |
  stripped="$(echo "$row" | sed 's/^[[:space:]]*|//; s/|[[:space:]]*$//')"

  declare -a fields=()
  _split_table_row "$stripped"

  # Hard arity check (P074 Step 17). The old path silently padded short rows
  # with `---`, which masked genuinely broken rows as no-dependency steps.
  # Five fields = an EPIC generated before P109 (no Closes column, zavira []).
  case "${#fields[@]}" in
    5) closes="—" ;;
    6) closes="$(echo "${fields[5]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" ;;
    *) error_exit "EPIC Steps table row has ${#fields[@]} fields, expected 5 or 6 (| # | Role | Objective | Depends On | Parallel Group | Closes |): ${row}" 1 ;;
  esac

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
    error_exit "Invalid role '$role' in step $num. Valid roles: $VALID_ROLES (a step that is both backend and frontend — 'fullstack' — is two steps; architect, domain and observability were removed in 2.112.0: use backend)" 1
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
  step_closes+=("$closes")
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
# Step 4: Per-step detail from the EPIC's own sections — the prepared fields of
# the step list handed to the shared builder (lib/aid-plan-json.sh, P111).
# =============================================================================

# The ## Step UI Contracts section (per-step scoping and ui_change blocks).
ui_contracts_section="$(echo "$(cat "$epic")" | awk '
  /^## Step UI Contracts/ { found=1; next }
  found && /^## / { exit }
  found { print }
')"

# _aid_append_ac_items <raw \x1f-joined AC text> — appends each trimmed,
# non-empty AC item to the caller's $step_ac_json (shared scope, not local).
_aid_append_ac_items() {
  local raw="$1" ac_item
  IFS=$'\x1f' read -ra ac_items <<< "$raw"
  for ac_item in "${ac_items[@]}"; do
    ac_item="$(echo "$ac_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$ac_item" ]] && continue
    step_ac_json="$(echo "$step_ac_json" | jq --arg a "$ac_item" '. + [$a]')"
  done
}

# Scope sections. Allowed paths go through the same D4 cleaner as the per-step
# block — an ambiguous multi-path entry fails loudly instead of authorizing
# only its first path.
scope_allowed_raw="$(extract_subsection "$epic" "Scope" "Allowed files/paths")"
scope_forbidden_raw="$(extract_subsection "$epic" "Scope" "Forbidden zones")"
allowed_paths_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
    path_entry="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    [[ "$path_entry" == "<!--"* ]] && continue
    [[ -z "$path_entry" ]] && continue
    if ! parsed_scope_paths="$(_aid_split_path_entry "$path_entry")"; then
      error_exit "Invalid Allowed files/paths entry: ${path_entry}. Canonical multi-path form: \`a\` + \`b\` — description." 1
    fi
    while IFS= read -r path_val; do
      [[ -z "$path_val" ]] && continue
      allowed_paths_json="$(echo "$allowed_paths_json" | jq --arg p "$path_val" \
        'if index($p) then . else . + [$p] end')"
    done <<< "$parsed_scope_paths"
  fi
done <<< "$scope_allowed_raw"

forbidden_paths_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    path_val="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    path_val="${path_val//\`/}"
    [[ "$path_val" == "<!--"* ]] && continue
    [[ -z "$path_val" ]] && continue
    path_val="$(echo "$path_val" | sed 's/[[:space:]]*(.*)[[:space:]]*$//')"
    forbidden_paths_json="$(echo "$forbidden_paths_json" | jq --arg p "$path_val" '. + [$p]')"
  fi
done <<< "$scope_forbidden_raw"

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

# Acceptance criteria grouped by role prefix. Joined with 0x1f, not "|||":
# bash's IFS is a character class, so "|||" would split on every "|" (D3).
ac_raw="$(extract_section "$epic" "Acceptance Criteria")"
declare -A ac_by_role=()
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*\[([a-z]+)\][[:space:]]*(.*) ]]; then
    ac_by_role["${BASH_REMATCH[1]}"]="${ac_by_role[${BASH_REMATCH[1]}]:-}"$'\x1f'"${BASH_REMATCH[2]}"
  elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*(.*) ]]; then
    ac_text="${BASH_REMATCH[1]}"
    [[ "$ac_text" == "<!--"* ]] && continue
    [[ -z "$ac_text" ]] && continue
    ac_by_role["_global"]="${ac_by_role[_global]:-}"$'\x1f'"$ac_text"
  fi
done <<< "$ac_raw"

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

steps_list="[]"
for i in "${!step_nums[@]}"; do
  step_role="${step_roles[$i]}"
  step_n="${step_nums[$i]}"
  # P109: the brief points this step closes, from the table's Closes column
  step_zavira_json="$( { grep -oE '\bAC[0-9]+\b' <<< "${step_closes[$i]:-}" || true; } | jq -R . | jq -sc .)"
  # P110: the plan's global step number — source_step_ids at the local index;
  # null for an EPIC generated before 2.116.0.
  step_plan_step=null
  if [[ -n "$fm_source_step_ids" ]]; then
    IFS=',' read -ra __ssids <<< "$fm_source_step_ids"
    [[ "${__ssids[$i]:-}" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]] && step_plan_step="${BASH_REMATCH[1]}"
  fi

  # D2 — the per-step scoping block (`<!-- step-N: files=...; ac=... -->`):
  # files[] verbatim as outputs, ac[] as acceptance_criteria, files[] through
  # the D4 cleaner for allowed_paths. No block, or one that does not parse →
  # today's broadcast (never an empty array just because the block is absent).
  step_has_block=0
  outputs_json="[]"
  step_ac_json="[]"
  step_allowed_paths_json="[]"
  if [[ -n "$ui_contracts_section" ]]; then
    # -m1 -F: the same first-match fixed-string lookup aid-contract-validate.sh uses.
    scoping_line="$(echo "$ui_contracts_section" | grep -m1 -F "<!-- step-${step_n}: files=" || true)"
    if [[ -n "$scoping_line" ]]; then
      scoping_parsed="$(_aid_parse_scoping_line "$scoping_line" "$step_n" || true)"
      if [[ -n "$scoping_parsed" ]]; then
        # Reverse the @@AID_ARROW@@ encoding aid-plan-to-epic.sh applies so a
        # literal "-->" in a value cannot close the comment early.
        files_json_decoded="$(echo "$scoping_parsed" | sed -n '1p' | sed 's/@@AID_ARROW@@/-->/g')"
        ac_json_decoded="$(echo "$scoping_parsed" | sed -n '2p' | sed 's/@@AID_ARROW@@/-->/g')"
        if files_json_valid="$(echo "$files_json_decoded" | jq -c . 2>/dev/null)" \
           && ac_json_valid="$(echo "$ac_json_decoded" | jq -c . 2>/dev/null)"; then
          outputs_json="$files_json_valid"
          step_ac_json="$ac_json_valid"
          if ! step_allowed_paths_json="$(_aid_allowed_paths_from_files_json "$files_json_valid")"; then
            error_exit "Invalid Files entry in step ${step_n} scoping block. Canonical multi-path form: \`a\` + \`b\` — description." 1
          fi
          step_has_block=1
        fi
      fi
    fi
  fi
  if [[ "$step_has_block" -eq 0 ]]; then
    outputs_json="$artifacts_json"
    [[ -n "${ac_by_role[$step_role]+_}" ]] && _aid_append_ac_items "${ac_by_role[$step_role]}"
    [[ -n "${ac_by_role[_global]+_}" ]] && _aid_append_ac_items "${ac_by_role[_global]}"
    step_allowed_paths_json="$allowed_paths_json"
  fi

  # ui_change fields from the Step UI Contracts section.
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
          step_ui_contract="$(jq -n --arg path "$ui_path" --arg sha256 "$ui_sha256" --arg schema_version "$ui_schema_v" \
            '{path: $path, sha256: $sha256, schema_version: $schema_version}')"
        fi
      fi
    fi
  fi

  steps_list="$(jq -c \
    --argjson number "$step_n" --arg role "$step_role" --arg objective "${step_objectives[$i]}" \
    --arg depends_on "${step_depends[$i]}" --arg parallel_group "${step_parallel[$i]}" \
    --argjson zavira "$step_zavira_json" --argjson plan_step "$step_plan_step" \
    --argjson outputs "$outputs_json" --argjson ac "$step_ac_json" \
    --argjson allowed "$step_allowed_paths_json" --argjson forbidden "$forbidden_paths_json" \
    --argjson constraints "$constraints_json" \
    --argjson ui_mode "$step_ui_mode" --argjson ui_contract "$step_ui_contract" \
    '. + [{number: $number, role: $role, objective: $objective, depends_on: $depends_on,
           parallel_group: $parallel_group, zavira: $zavira, plan_step: $plan_step,
           outputs: $outputs, acceptance_criteria: $ac, allowed_paths: $allowed,
           forbidden_paths: $forbidden, constraints: $constraints,
           ui_change_mode: $ui_mode, ui_change_contract: $ui_contract}]' <<< "$steps_list")"
done

# =============================================================================
# Step 5: DoD Gates — not filtered against a fixed list (P061 E1 Step 1); the
# builder checks the names' shape, aid-run-gates.sh reconciles them against
# execution.yaml at run time (undefined_gate).
# =============================================================================
gates_raw="$(extract_section "$epic" "DoD Gates")"
gates_json="[]"
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/\r$//')"
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
    gate="$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$gate" ]] && continue
    gates_json="$(echo "$gates_json" | jq --arg g "$gate" '. + [$g]')"
  fi
done <<< "$gates_raw"

# =============================================================================
# Step 6: Build plan.json through the shared builder (lib/aid-plan-json.sh)
# =============================================================================
source "${SCRIPT_DIR}/lib/aid-plan-json.sh"
__pj_tmp="$(mktemp -d)"
trap 'rm -rf "$__pj_tmp"' EXIT
printf '%s' "$steps_list" > "${__pj_tmp}/steps.json"
printf '%s' "$gates_json" > "${__pj_tmp}/gates.json"
aid_plan_json_build --steps-json "${__pj_tmp}/steps.json" --out "${__pj_tmp}/plan.json" \
  --epic-id "$epic_id" --plan "$plan_source" --gates-json "${__pj_tmp}/gates.json"

# =============================================================================
# Step 7: run_id, evidence directory, plan.json, epic_input.md, manifest
# =============================================================================
run_id="$(aid_gen_run_id "$epic_id")"

evidence_dir="${output_dir}/work/evidence/${epic_id}/${run_id}"
mkdir -p "$evidence_dir" 2>/dev/null || error_exit "Cannot create evidence directory: $evidence_dir" 3

plan_json_path="${evidence_dir}/plan.json"
cat "${__pj_tmp}/plan.json" > "$plan_json_path" || error_exit "Cannot write plan.json to $plan_json_path" 3

cp "$epic" "${evidence_dir}/epic_input.md" 2>/dev/null || error_exit "Cannot copy EPIC to evidence directory" 3

jq -n \
  --arg plan_json "$plan_json_path" \
  --arg run_id "$run_id" \
  --arg evidence_dir "$evidence_dir" \
  '{
    plan_json: $plan_json,
    run_id: $run_id,
    evidence_dir: $evidence_dir
  }'
