#!/usr/bin/env bash
# =============================================================================
# lib/aid-plan-json.sh — THE plan.json builder and THE per-step plan reader (P111)
#
# One builder for both roads to a run until P112 removes the old one:
#   * the direct run (`aid-plan-fsm.sh plan-run`) reads the WHOLE plan through
#     aid_plan_json_steps_from_plan and builds with aid_plan_json_build --direct;
#   * the EPIC path keeps its own table parser (the EPIC-to-plan.json converter) and hands
#     the parsed rows over as a step list; the plan-to-EPIC generator reads its phase's
#     steps through aid_plan_json_steps_from_plan and only formats the EPIC.
# The builder body is the EPIC converter's former "Step 4 .. Step 14"
# moved here unchanged, so the EPIC path's golden output is byte-identical
# (scripts/tests/test-epic-to-json-regression.sh).
#
# Callers source lib/common.sh first (error_exit, extract_section).
# =============================================================================

_AID_PJ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
source "${_AID_PJ_LIB_DIR}/aid-scoping.sh"
# shellcheck source=aid-ac-extract.sh
source "${_AID_PJ_LIB_DIR}/aid-ac-extract.sh"
# shellcheck source=aid-roots.sh
source "${_AID_PJ_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-plan-graph.sh
source "${_AID_PJ_LIB_DIR}/aid-plan-graph.sh"

AID_PLAN_JSON_ROLES="backend frontend qa security docs docs-writer release e2e"   # one list; must match plan.schema.json (P107)

_aid_pj_valid_role() {
  local r
  for r in $AID_PLAN_JSON_ROLES; do [[ "$r" == "$1" ]] && return 0; done
  return 1
}

_aid_pj_is_none() {
  case "$1" in ""|"—"|"–"|"---"|"-") return 0 ;; esac
  return 1
}

# =============================================================================
# The per-step plan reader (moved from the plan-to-EPIC generator, P111 Step 1)
# =============================================================================

# aid_plan_step_content <plan> <n> — everything between `### Step N` and the
# next step header (or the next **EPIC M:** marker), header excluded. Fence
# lines inside the body are printed; headers inside fences are ignored (F13).
aid_plan_step_content() {
  local plan="$1" step_num="$2"
  awk -v snum="$step_num" '
    BEGIN { found = 0; in_fence = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^[[:space:]]*```/) {
        in_fence = 1 - in_fence
        if (found) print
        next
      }
      if (!in_fence) {
        if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+/) {
          line = $0
          sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", line)
          sub(/:.*/, "", line)
          sub(/[^0-9].*/, "", line)
          if (found) exit
          if (line == snum) { found = 1; next }
        }
        if (found && $0 ~ /^\*\*EPIC[[:space:]]+[0-9]+/) exit
      }
      if (found) print
    }
  ' "$plan"
}

# aid_plan_parse_step_deps <raw> — "Step 1, Steps 3-5 — why" -> "1, 3, 4, 5".
# One dependency grammar, shared with lib/aid-source-plan-graph.sh (P073 Step 5):
# prose after the first annotation separator is dropped, `none`/`---` mean no
# dependency, every remaining token must be recognised in full or the call
# fails naming it (a typo must never become "no dependency"). The message names
# ${step_counter} (the caller's step label).
aid_plan_parse_step_deps() {
  local raw="$1"
  local result=()
  raw="$(printf '%s' "$raw" | sed 's/[—–].*$//; s/ - .*$//; s/ (.*$//')"
  case "$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in
    ---|none|'') return 0 ;;
  esac
  local tokens token i range_start range_end
  tokens="$(echo "$raw" | sed 's/,/\n/g')"
  while IFS= read -r token; do
    token="$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$token" ]] && continue
    if [[ "$token" =~ ^[Ss]teps?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      range_start="${BASH_REMATCH[1]}"; range_end="${BASH_REMATCH[2]}"
      if [[ "$range_start" -gt "$range_end" ]]; then
        echo "WARNING: Reversed range Steps ${range_start}-${range_end} — skipping" >&2
        continue
      fi
      for (( i=range_start; i<=range_end; i++ )); do result+=("$i"); done
    elif [[ "$token" =~ ^[Ss]teps?[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")
    elif [[ "$token" =~ ^[Tt]asks?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      range_start="${BASH_REMATCH[1]}"; range_end="${BASH_REMATCH[2]}"
      if [[ "$range_start" -gt "$range_end" ]]; then
        echo "WARNING: Reversed range Tasks ${range_start}-${range_end} — skipping" >&2
        continue
      fi
      for (( i=range_start; i<=range_end; i++ )); do result+=("$i"); done
    elif [[ "$token" =~ ^[Tt]asks?[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")
    elif [[ "$token" =~ ^([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")
    else
      echo "ERROR: step ${step_counter:-?}: unrecognised dependency token '${token}' — accepted: 'Step N', 'Steps N-M', 'none', '---', comma-separated, optionally followed by an annotation after ' — ', ' – ', ' - ' or ' ('" >&2
      return 1
    fi
  done <<< "$tokens"
  if [[ "${#result[@]}" -gt 0 ]]; then
    printf '%s\n' "${result[@]}" | sort -n -u | paste -sd ',' - | sed 's/,/, /g'
  fi
}

# aid_plan_step_numbers <plan> — the plan's step numbers in document order
# (`### Step N`, `## Task N`, `## Step N`; headers inside fences ignored).
aid_plan_step_numbers() {
  awk '
    BEGIN { f = 0 }
    { gsub(/\r$/, "") }
    /^[[:space:]]*```/ { f = 1 - f; next }
    f { next }
    /^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+/ {
      l = $0; sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", l); sub(/[^0-9].*/, "", l); print l
    }
  ' "$1"
}

# aid_plan_json_steps_from_plan <plan> [<n> ...] — the per-step facts of the
# named steps (default: every step, document order) as one JSON array:
#   number, role ("" when the step names none), objective (raw, may span lines),
#   depends_on ("1, 3" global step numbers, "" for none), parallel_group ("---"
#   for none), zavira ([AC..]), section_start, section_end, files (top-level
#   Files bullets, verbatim, without "- "), artifacts (every Files bullet as
#   "- <text>"), acceptance_criteria (raw criteria), allowed_paths (the cleaned
#   paths of `files`), ui_change_mode, ui_change_path/sha256/schema_version.
# Exit: 0; error_exit 1 on an unparseable Files bullet (the plan names it);
# 5 after an unrecognised dependency token (the reader printed the token).
aid_plan_json_steps_from_plan() {
  local plan="$1"; shift
  local -a nums=("$@")
  [[ "${#nums[@]}" -gt 0 ]] || mapfile -t nums < <(aid_plan_step_numbers "$plan")
  local bounds out="[]" sn step_counter=0
  bounds="$(_aid_plan_step_bounds "$plan")"
  for sn in "${nums[@]}"; do
    step_counter=$(( step_counter + 1 ))
    local content objective role ac_raw artifacts top raw_dep deps="" pg="---" s="" e="" closes_json="[]"
    content="$(aid_plan_step_content "$plan" "$sn")"

    # Objective — **Objective:** field, else the header text, else the first line.
    objective="$(echo "$content" | awk '
      BEGIN { found = 0 }
      {
        gsub(/\r$/, "")
        if ($0 ~ /^\*\*Objective:\*\*/) { sub(/^\*\*Objective:\*\*[[:space:]]*/, "", $0); print; found = 1; next }
        if (found && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^\*\*[A-Z]/)) exit
        if (found) print
      }
    ')"
    if [[ -z "$objective" ]]; then
      objective="$(awk -v snum="$sn" '
        BEGIN { in_fence = 0 }
        {
          gsub(/\r$/, "")
          if ($0 ~ /^[[:space:]]*```/) { in_fence = 1 - in_fence; next }
          if (in_fence) next
          if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+/) {
            line = $0
            sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", line)
            num = line; sub(/:.*/, "", num); sub(/[^0-9].*/, "", num)
            if (num == snum) {
              sub(/^[0-9]+[[:space:]]*[:—–-][[:space:]]*/, "", line)
              if (line != "" && line != num) print line
              exit
            }
          }
        }
      ' "$plan")"
    fi
    [[ -n "$objective" ]] || objective="$(echo "$content" | awk 'NF { print; exit }')"

    # AID Role, with or without the colon.
    role="$(echo "$content" | awk '
      /^\*\*AID Role:?\*\*/ { sub(/^\*\*AID Role:?\*\*[[:space:]]*/, ""); gsub(/[[:space:]]+$/, ""); print tolower($0); exit }
    ')"

    ac_raw="$(echo "$content" | aid_ac_extract_criteria)"

    artifacts="$(echo "$content" | awk '
      BEGIN { in_files = 0 }
      {
        gsub(/\r$/, "")
        if ($0 ~ /^\*\*Files:\*\*/) { in_files = 1; next }
        if (in_files && $0 ~ /^\*\*/) { in_files = 0 }
        if (in_files && $0 ~ /^[[:space:]]*-/) { sub(/^[[:space:]]*-[[:space:]]*/, "", $0); if ($0 != "") print "- " $0 }
      }
    ')"
    top="$(printf '%s\n' "$content" | _aid_extract_files_bullets)"

    # Allowed paths: every top-level bullet must parse (P079 Step 5, IMP-480 —
    # a parser may refuse, it may not narrow silently).
    local step_files="" dropped="" raw_file split p tier_finding
    while IFS= read -r raw_file; do
      [[ -n "${raw_file// /}" ]] || continue
      raw_file="${raw_file#- }"
      if [[ ! "$raw_file" =~ $_AID_FILES_VERB_RE ]]; then
        dropped+="  step ${sn}: unparseable Files bullet dropped: \"${raw_file}\""$'\n'; continue
      fi
      if [[ -z "${BASH_REMATCH[2]//[[:space:]]/}" ]]; then
        dropped+="  step ${sn}: Files bullet has a verb but no path: \"${raw_file}\""$'\n'; continue
      fi
      if ! split="$(_aid_split_path_entry "${BASH_REMATCH[2]}")"; then
        error_exit "Invalid Files entry in step ${sn}: ${raw_file}. Canonical multi-path form: \`a\` + \`b\` — description." 1
      fi
      tier_finding="$(_aid_test_bullet_tier_finding "$raw_file" .)" \
        || dropped+="  step ${sn}: ${tier_finding}: \"${raw_file}\""$'\n'
      while IFS= read -r p; do [[ -n "$p" ]] && step_files+="${p}"$'\n'; done <<< "$split"
    done <<< "$top"
    if [[ -n "$dropped" ]]; then
      error_exit "Files block in ${plan} has bullets this generator cannot parse:
${dropped}Every top-level Files bullet must read \`- <Create|Modify|Test|Rewrite>: <path> — <why>\`, and a \`Test:\` bullet naming a suite that does not exist yet must state its tier: \`- Test: \\\`path\\\` (tier: t1) — <what it proves>\`. See skills/plan-writing.md (Files block grammar). Fix the plan and re-run generation." 1
    fi

    # UI change fields.
    local ui_mode ui_raw
    ui_mode="$(echo "$content" | awk '
      /^\*\*UI Change Mode:\*\*/ { sub(/^\*\*UI Change Mode:\*\*[[:space:]]*`?/, ""); sub(/`.*/, ""); gsub(/[[:space:]]/, ""); if ($0 == "existing_ui" || $0 == "new_ui") print $0; exit }
    ')"
    ui_raw="$(echo "$content" | awk '
      /^\*\*UI Change Contract:\*\*/ { sub(/^\*\*UI Change Contract:\*\*[[:space:]]*`?/, ""); sub(/`.*/, ""); print; exit }
    ')"

    raw_dep="$(echo "$content" | awk '
      BEGIN { in_deps = 0 }
      {
        gsub(/\r$/, "")
        if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps = 1; next }
        if (in_deps && $0 ~ /^\*\*/) { in_deps = 0 }
        if (in_deps && $0 ~ /Depends on:/) { sub(/.*Depends on:[[:space:]]*/, "", $0); print }
      }
    ')"
    if [[ -n "$raw_dep" ]]; then
      deps="$(aid_plan_parse_step_deps "$raw_dep")" || return 5
    fi

    read -r s e _ < <(awk -F'\t' -v n="$sn" '$3 ~ "^### Step " n ":" { print; exit }' <<< "$bounds") || true
    if [[ -n "$s" ]]; then
      pg="$(_aid_plan_step_field "$plan" "$s" "$e" "Parallel group")" || pg="---"
      pg="${pg%%[[:space:]]*}"
      local closes
      if closes="$(_aid_plan_step_field "$plan" "$s" "$e" "Zavírá")"; then
        closes_json="$( { grep -oE '\bAC[0-9]+\b' <<< "$closes" || true; } | jq -R . | jq -sc .)"
      fi
    fi

    local files_json="[]" ac_json="[]" allowed_json="[]" artifacts_json="[]"
    [[ -n "$top" ]] && files_json="$(printf '%s\n' "$top" | sed 's/^- //' | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    [[ -n "$ac_raw" ]] && ac_json="$(printf '%s\n' "$ac_raw" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    [[ -n "$artifacts" ]] && artifacts_json="$(printf '%s\n' "$artifacts" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    if [[ "$files_json" != "[]" ]]; then
      allowed_json="$(_aid_allowed_paths_from_files_json "$files_json")" \
        || error_exit "Invalid Files entry in step ${sn}. Canonical multi-path form: \`a\` + \`b\` — description." 1
    fi

    out="$(jq -c \
      --argjson number "$sn" --arg role "$role" --arg objective "$objective" \
      --arg depends_on "$deps" --arg parallel_group "$pg" --argjson zavira "$closes_json" \
      --arg s "${s:-0}" --arg e "${e:-0}" \
      --argjson files "$files_json" --argjson artifacts "$artifacts_json" \
      --argjson ac "$ac_json" --argjson allowed "$allowed_json" \
      --arg ui_mode "$ui_mode" \
      --arg ui_path "$(echo "$ui_raw" | sed -n "s/.*path:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')" \
      --arg ui_sha "$(echo "$ui_raw" | sed -n "s/.*sha256:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')" \
      --arg ui_sv "$(echo "$ui_raw" | sed -n "s/.*schema_version:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')" \
      '. + [{number: $number, role: $role, objective: $objective, depends_on: $depends_on,
             parallel_group: $parallel_group, zavira: $zavira, plan_step: $number,
             section_start: ($s | tonumber), section_end: ($e | tonumber),
             files: $files, artifacts: $artifacts, outputs: $files,
             acceptance_criteria: $ac, allowed_paths: $allowed,
             ui_change_mode: $ui_mode, ui_change_path: $ui_path,
             ui_change_sha256: $ui_sha, ui_change_schema_version: $ui_sv}]' <<< "$out")"
  done
  printf '%s\n' "$out"
}

# =============================================================================
# DoD gates from the project's execution.yaml (moved from the plan-to-EPIC generator)
# =============================================================================

AID_PLAN_JSON_DOD_CANDIDATES=("docs_updated" "check_docs_updated")

# aid_plan_json_gate_name <execution.yaml> — the DoD gate this project defines
# (first of AID_PLAN_JSON_DOD_CANDIDATES under `gates:`), or nothing when it
# defines none. Never invents a gate (IMP-503); refuses (error_exit) when the
# config cannot be read, because "could not determine" is not "chose none", and
# when an auto-resolvable gate profile excludes the gate it would name.
aid_plan_json_gate_name() {
  local _exec_yaml="$1" _cand name="" _dod_bad="" _prof
  if [[ -z "$_exec_yaml" || ! -f "$_exec_yaml" ]]; then
    error_exit "DoD gates: cannot resolve the project's execution.yaml (looked for '${_exec_yaml:-<no state root>}'). Generation refuses rather than emitting an empty gate list that would look like a deliberate choice." 3
  fi
  command -v yq >/dev/null 2>&1 || \
    error_exit "DoD gates: yq is required to read ${_exec_yaml} — the gate runner requires it too, so a missing yq is a broken environment, not a project without gates." 2
  if ! yq -e '.' "$_exec_yaml" >/dev/null 2>&1; then
    error_exit "DoD gates: ${_exec_yaml} is not parseable YAML. Refusing to infer 'no gates' from a file that could not be read." 1
  fi
  if [[ "$(yq -r 'has("gates")' "$_exec_yaml" 2>/dev/null)" != "true" ]]; then
    error_exit "DoD gates: ${_exec_yaml} has no 'gates:' key at all. The runner reads '.gates | keys'; an absent map is a malformed config, not an empty one." 1
  fi
  for _cand in "${AID_PLAN_JSON_DOD_CANDIDATES[@]}"; do
    if [[ "$(yq -r ".gates.\"${_cand}\" != null" "$_exec_yaml" 2>/dev/null)" == "true" ]]; then
      name="$_cand"; break
    fi
  done
  [[ -n "$name" ]] || return 0
  # gates: and gate_profiles: must agree on what the resolver can land on
  # without anybody choosing (every profile with when_paths, plus
  # default_profile) — else every such run passes its gates and is refused at
  # GATES -> DONE (plan_gate_profile_excluded). P097 Step 4.
  if [[ "$(yq -r '.gate_profiles != null' "$_exec_yaml" 2>/dev/null)" == "true" ]]; then
    while IFS= read -r _prof; do
      [[ -n "$_prof" ]] || continue
      if [[ "$(P="$_prof" G="$name" yq -r '[.gate_profiles[strenv(P)].include[]? | select(. == strenv(G))] | length' "$_exec_yaml" 2>/dev/null)" == "0" ]]; then
        _dod_bad="${_dod_bad:+${_dod_bad}, }${_prof}"
      fi
    done < <(yq -r '[(.gate_profiles | to_entries[] | select(.value.when_paths != null) | .key), (.default_profile | select(. != null))] | unique | .[]' "$_exec_yaml" 2>/dev/null)
  fi
  if [[ -n "$_dod_bad" ]]; then
    error_exit "DoD gate '${name}' is defined in ${_exec_yaml} under gates: and would be written into this EPIC's plan.json, but the auto-resolvable profile(s) [${_dod_bad}] do not include it. Every run the FSM resolves to one of those would pass its gates and then be refused at GATES -> DONE (plan_gate_profile_excluded). Fix one of the two: add '${name}' to those profiles' include[] in gate_profiles, or remove it from gates:." 1
  fi
  printf '%s\n' "$name"
}

# aid_plan_json_gates <execution.yaml> — the same as a JSON array ([] or [name]).
aid_plan_json_gates() {
  local name
  name="$(aid_plan_json_gate_name "$1")" || return $?
  if [[ -n "$name" ]]; then jq -nc --arg g "$name" '[$g]'; else echo '[]'; fi
}

# =============================================================================
# repo_roots (P111 Step 1/4): foreign repositories a plan works in, as worktrees
# =============================================================================

# aid_plan_repo_roots_raw <plan> — the frontmatter `repo_roots` list as JSON
# ([] when absent).
aid_plan_repo_roots_raw() {
  local out
  out="$(yq --front-matter=extract -o=json '.repo_roots // []' "$1" 2>/dev/null)" || out="[]"
  [[ -n "$out" && "$out" != "null" ]] || out="[]"
  jq -c 'if type == "array" then . else [] end' <<< "$out" 2>/dev/null || echo '[]'
}

# aid_plan_repo_base_branch <path> [<base_branch>] — the foreign base branch:
# the declared one, else what origin/HEAD points at, else main.
aid_plan_repo_base_branch() {
  local path="$1" bb="${2:-}"
  if [[ -z "$bb" ]]; then
    bb="$(git -C "$path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || bb=""
    [[ -n "$bb" ]] || bb="main"
  fi
  printf '%s\n' "$bb"
}

# aid_plan_repo_roots_json <plan> <plan_id> <project> — the closed plan.json
# entries {name, path, worktree, branch, base}: path is physical (realpath),
# worktree `<path>/.aid-worktrees/plan-<id>--<name>`, branch
# `plan/<id>-<project>` (plan ids are per project), base the head of the
# foreign base branch. Refuses repo_root_invalid (error_exit 1) on an entry it
# cannot resolve; the plan lint reports the same entries before CP1.
aid_plan_repo_roots_json() {
  local plan="$1" plan_id="$2" project="$3" raw n i name path bb base out="[]" own
  raw="$(aid_plan_repo_roots_raw "$plan")"
  own="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || own=""
  n="$(jq 'length' <<< "$raw")"
  for (( i=0; i<n; i++ )); do
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<< "$raw")"
    path="$(jq -r --argjson i "$i" '.[$i].path // ""' <<< "$raw")"
    bb="$(jq -r --argjson i "$i" '.[$i].base_branch // ""' <<< "$raw")"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
      || error_exit "repo_root_invalid: repo_roots[$i].name '${name}' must be a slug ([a-z0-9_-]). next: fix the plan's repo_roots frontmatter (pipeline.md §When AID refuses: repo_root_invalid)" 1
    path="$(realpath -e "$path" 2>/dev/null)" && git -C "$path" rev-parse --git-dir >/dev/null 2>&1 \
      || error_exit "repo_root_invalid: repo_roots[$i] '${name}' path is not a git repository. next: fix the plan's repo_roots frontmatter (pipeline.md §When AID refuses: repo_root_invalid)" 1
    [[ -z "$own" || "$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$own" ]] \
      || error_exit "repo_root_invalid: repo_roots[$i] '${name}' is the project itself (or one of its worktrees) — repo_roots names OTHER repositories. next: fix the plan's repo_roots frontmatter (pipeline.md §When AID refuses: repo_root_invalid)" 1
    bb="$(aid_plan_repo_base_branch "$path" "$bb")"
    base="$(git -C "$path" rev-parse --verify --quiet "${bb}^{commit}" 2>/dev/null)" \
      || error_exit "repo_root_invalid: repo_roots[$i] '${name}' base branch '${bb}' does not resolve in ${path}. next: set base_branch in the plan's repo_roots entry (pipeline.md §When AID refuses: repo_root_invalid)" 1
    out="$(jq -c --arg name "$name" --arg path "$path" \
      --arg wt "${path}/.aid-worktrees/plan-${plan_id}--${name}" \
      --arg br "plan/${plan_id}-${project}" --arg base "$base" \
      '. + [{name: $name, path: $path, worktree: $wt, branch: $br, base: $base}]' <<< "$out")"
  done
  printf '%s\n' "$out"
}

# =============================================================================
# The builder (moved from the EPIC-to-plan.json converter, P111 Step 1)
# =============================================================================

# aid_plan_json_build --steps-json <file> --out <file> --epic-id <id>
#     [--plan <plan ref>] [--gates-json <file>]
#     [--direct --execution <execution.yaml> [--repo-roots-json <file>]]
#
# The step list is a JSON array of {number, role, objective, depends_on,
# parallel_group, zavira, plan_step, outputs, acceptance_criteria,
# allowed_paths} plus the optional EPIC-path fields forbidden_paths,
# constraints, ui_change_mode, ui_change_contract; aid_plan_json_steps_from_plan
# supplies it on the direct path. Builds step ids, the dependency array, the
# cycle check, the parallel groups, the analysis groups, validates and writes
# `--out` atomically. --direct adds `direct: true`, `repo_roots` and gates
# derived from the execution.yaml (the EPIC path passes the EPIC's DoD gates).
# Exit codes: 0 ok, 1 validation, 2 no steps, 3 I/O.
aid_plan_json_build() {
  local steps_file="" out="" epic_id="" plan_source="" gates_file="" direct=0 exec_yaml="" rr_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --steps-json) steps_file="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --epic-id) epic_id="$2"; shift 2 ;;
      --plan) plan_source="$2"; shift 2 ;;
      --gates-json) gates_file="$2"; shift 2 ;;
      --direct) direct=1; shift ;;
      --execution) exec_yaml="$2"; shift 2 ;;
      --repo-roots-json) rr_file="$2"; shift 2 ;;
      *) error_exit "aid_plan_json_build: unknown argument: $1" 1 ;;
    esac
  done
  [[ -f "$steps_file" ]] || error_exit "aid_plan_json_build: --steps-json file not found: ${steps_file}" 3
  [[ -n "$out" ]] || error_exit "aid_plan_json_build: missing --out" 1
  [[ -n "$epic_id" ]] || error_exit "aid_plan_json_build: missing --epic-id" 1

  local n i
  n="$(jq 'length' "$steps_file")" || error_exit "aid_plan_json_build: step list is not JSON: ${steps_file}" 1
  [[ "$n" -gt 0 ]] || error_exit "no steps" 2
  if [[ "$(jq '[.[].number] | length != (unique | length)' "$steps_file")" == "true" ]]; then
    error_exit "aid_plan_json_build: duplicate step number in the step list: $(jq -r '[.[].number] | group_by(.) | map(select(length > 1) | .[0]) | map(tostring) | join(", ")' "$steps_file")" 1
  fi

  local -a step_nums=() step_roles=() step_objectives=() step_depends=() step_parallel=()
  for (( i=0; i<n; i++ )); do
    local st num role objective
    st="$(jq -c --argjson i "$i" '.[$i]' "$steps_file")"
    num="$(jq -r '.number' <<< "$st")"
    role="$(jq -r '.role // ""' <<< "$st")"
    objective="$(jq -r '.objective // ""' <<< "$st")"
    if [[ "$direct" -eq 1 ]]; then
      [[ -n "$role" ]] || error_exit "Step ${num} names no **AID Role:** — every step of a directly run plan names its role (${AID_PLAN_JSON_ROLES})" 1
      _aid_pj_valid_role "$role" || error_exit "Invalid role '$role' in step $num. Valid roles: $AID_PLAN_JSON_ROLES" 1
      objective="$(printf '%s' "$objective" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
      [[ "${#objective}" -ge 10 ]] || error_exit "Step $num objective too short (min 10 chars): '$objective'" 1
    fi
    step_nums+=("$num")
    step_roles+=("$role")
    step_objectives+=("$objective")
    step_depends+=("$(jq -r '.depends_on // ""' <<< "$st")")
    step_parallel+=("$(jq -r '.parallel_group // ""' <<< "$st")")
  done

  # Step ids — the schema's id pattern forbids hyphens, roles like docs-writer carry one.
  local -a step_ids=()
  for i in "${!step_nums[@]}"; do
    step_ids+=("step_${step_nums[$i]}_${step_roles[$i]//-/_}")
  done
  local -A num_to_idx=() role_to_idx=()
  for i in "${!step_nums[@]}"; do
    num_to_idx["${step_nums[$i]}"]="$i"
    role_to_idx["${step_roles[$i]}"]="$i"   # several steps of one role: the last one wins
  done

  # Dependencies.
  local deps_json="[]" dep_reason="Declared in EPIC steps table"
  [[ "$direct" -eq 1 ]] && dep_reason="Declared in the plan step's Dependencies"
  local -A dep_edges=()
  local dep_val step_id dep_part dep_step_id dep_idx
  local -a dep_parts=()
  for i in "${!step_nums[@]}"; do
    dep_val="${step_depends[$i]}"
    step_id="${step_ids[$i]}"
    _aid_pj_is_none "$dep_val" && continue
    IFS=',' read -ra dep_parts <<< "$dep_val"
    for dep_part in "${dep_parts[@]}"; do
      dep_part="$(echo "$dep_part" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$dep_part" ]] && continue
      dep_step_id=""
      if [[ "$dep_part" =~ ^[0-9]+$ ]]; then
        if [[ -n "${num_to_idx[$dep_part]+_}" ]]; then
          dep_idx="${num_to_idx[$dep_part]}"; dep_step_id="${step_ids[$dep_idx]}"
        else
          error_exit "Step ${step_nums[$i]} depends on step $dep_part which does not exist" 1
        fi
      elif _aid_pj_valid_role "$dep_part"; then
        if [[ -n "${role_to_idx[$dep_part]+_}" ]]; then
          dep_idx="${role_to_idx[$dep_part]}"; dep_step_id="${step_ids[$dep_idx]}"
        else
          error_exit "Step ${step_nums[$i]} depends on role '$dep_part' which has no matching step" 1
        fi
      else
        error_exit "Step ${step_nums[$i]} has unresolvable dependency: '$dep_part'" 1
      fi
      deps_json="$(echo "$deps_json" | jq \
        --arg before "$dep_step_id" --arg after "$step_id" --arg reason "$dep_reason" \
        '. + [{"before": $before, "after": $after, "reason": $reason}]')"
      dep_edges["${dep_step_id}->${step_id}"]=1
    done
  done

  # Cycle detection — the shared graph lib.
  local pg_result cycles_count
  pg_result="$(build_plan_graph "$(printf '%s\n' "${step_ids[@]}")" "$(printf '%s\n' "${!dep_edges[@]}")")" \
    || error_exit "build_plan_graph failed" 1
  cycles_count="$(echo "$pg_result" | jq '.cycles | length')"
  if [[ "$cycles_count" -gt 0 ]]; then
    error_exit "Circular dependency detected among steps: $(echo "$pg_result" | jq -r '.cycles | join(", ")')" 1
  fi

  # Parallel groups (2+ members).
  local -A pg_members=()
  local pg group_name members member_count member_arr mid parallel_json="[]"
  for i in "${!step_nums[@]}"; do
    pg="${step_parallel[$i]}"
    _aid_pj_is_none "$pg" && continue
    pg_members["$pg"]="${pg_members[$pg]:-} ${step_ids[$i]}"
  done
  for group_name in "${!pg_members[@]}"; do
    members="$(echo "${pg_members[$group_name]}" | sed 's/^[[:space:]]+//')"
    member_count=$(echo "$members" | wc -w | tr -d ' ')
    if [[ "$member_count" -ge 2 ]]; then
      member_arr="[]"
      for mid in $members; do member_arr="$(echo "$member_arr" | jq --arg m "$mid" '. + [$m]')"; done
      parallel_json="$(echo "$parallel_json" | jq --argjson arr "$member_arr" '. + [$arr]')"
    fi
  done

  # Analysis groups (auto-trigger rules).
  local analysis_json="[]" analysis_counter=0 objective_lower step_role agents agent_count
  for i in "${!step_nums[@]}"; do
    objective_lower="$(echo "${step_objectives[$i]}" | tr '[:upper:]' '[:lower:]')"
    step_role="${step_roles[$i]}"
    step_id="${step_ids[$i]}"
    if echo "$objective_lower" | grep -qE '(auth|token|encrypt|sql|inject|secret|password|credential)'; then
      if [[ "$step_role" != "security" ]]; then
        analysis_counter=$(( analysis_counter + 1 ))
        analysis_json="$(echo "$analysis_json" | jq \
          --arg id "analysis_${analysis_counter}_security_review" --arg target "$step_id" \
          '. + [{"id": $id, "target": $target, "agents": ["security"], "mode": "review", "merge_strategy": "union", "trigger": "auto"}]')"
      fi
    fi
    if echo "$objective_lower" | grep -qE '(migrat|schema|database|model)'; then
      agents="[]"
      [[ "$step_role" != "backend" ]] && agents="$(echo "$agents" | jq '. + ["backend"]')"
      [[ "$step_role" != "security" ]] && agents="$(echo "$agents" | jq '. + ["security"]')"
      agent_count="$(echo "$agents" | jq 'length')"
      if [[ "$agent_count" -gt 0 ]]; then
        analysis_counter=$(( analysis_counter + 1 ))
        analysis_json="$(echo "$analysis_json" | jq \
          --arg id "analysis_${analysis_counter}_db_validation" --arg target "$step_id" --argjson agents "$agents" \
          '. + [{"id": $id, "target": $target, "agents": $agents, "mode": "validation", "merge_strategy": "consensus", "trigger": "auto"}]')"
      fi
    fi
    if echo "$objective_lower" | grep -qE '(contract|adr|api design|interface)'; then
      agents="[]"
      [[ "$step_role" != "backend" ]] && agents="$(echo "$agents" | jq '. + ["backend"]')"
      [[ "$step_role" != "frontend" ]] && agents="$(echo "$agents" | jq '. + ["frontend"]')"
      agent_count="$(echo "$agents" | jq 'length')"
      if [[ "$agent_count" -gt 0 ]]; then
        analysis_counter=$(( analysis_counter + 1 ))
        analysis_json="$(echo "$analysis_json" | jq \
          --arg id "analysis_${analysis_counter}_contract_validation" --arg target "$step_id" --argjson agents "$agents" \
          '. + [{"id": $id, "target": $target, "agents": $agents, "mode": "validation", "merge_strategy": "union", "trigger": "auto"}]')"
      fi
    fi
  done

  # Steps.
  local steps_json="[]" spec_label="EPIC specification" st inputs_json dp dep_sid step_obj src_plan_file="" sr
  [[ "$direct" -eq 1 ]] && spec_label="Plan specification"
  if [[ -n "$plan_source" && "$plan_source" != "null" ]]; then
    if [[ -f "$plan_source" ]]; then src_plan_file="$plan_source"
    elif sr="$(aid_state_root 2>/dev/null)" && [[ -f "${sr}/${plan_source}" ]]; then src_plan_file="${sr}/${plan_source}"
    fi
  fi
  for i in "${!step_nums[@]}"; do
    st="$(jq -c --argjson i "$i" '.[$i]' "$steps_file")"
    # A step list without its prepared Files/criteria fields: derive them from
    # the plan's own step section through the shared reader.
    if [[ -n "$src_plan_file" ]] && ! jq -e 'has("outputs") and has("acceptance_criteria") and has("allowed_paths")' <<< "$st" >/dev/null; then
      local derived
      derived="$(aid_plan_json_steps_from_plan "$src_plan_file" "${step_nums[$i]}")" || exit $?
      st="$(jq -c --argjson d "$derived" '. as $s | $d[0] as $p
        | $s + {outputs: ($s.outputs // $p.outputs), acceptance_criteria: ($s.acceptance_criteria // $p.acceptance_criteria), allowed_paths: ($s.allowed_paths // $p.allowed_paths)}' <<< "$st")"
    fi
    inputs_json="$(jq -nc --arg s "$spec_label" '[$s]')"
    dep_val="${step_depends[$i]}"
    if ! _aid_pj_is_none "$dep_val"; then
      IFS=',' read -ra dep_parts <<< "$dep_val"
      for dp in "${dep_parts[@]}"; do
        dp="$(echo "$dp" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -z "$dp" ]] && continue
        if [[ "$dp" =~ ^[0-9]+$ ]]; then
          if [[ -n "${num_to_idx[$dp]+_}" ]]; then
            dep_sid="${step_ids[${num_to_idx[$dp]}]}"
            inputs_json="$(echo "$inputs_json" | jq --arg s "Output from $dep_sid" '. + [$s]')"
          fi
        elif _aid_pj_valid_role "$dp"; then
          if [[ -n "${role_to_idx[$dp]+_}" ]]; then
            dep_sid="${step_ids[${role_to_idx[$dp]}]}"
            inputs_json="$(echo "$inputs_json" | jq --arg s "Output from $dep_sid" '. + [$s]')"
          fi
        fi
      done
    fi
    step_obj="$(jq -n \
      --arg id "${step_ids[$i]}" --arg role "${step_roles[$i]}" --arg objective "${step_objectives[$i]}" \
      --argjson inputs "$inputs_json" --argjson st "$st" \
      '{
        id: $id,
        role: $role,
        objective: $objective,
        inputs: $inputs,
        outputs: ($st.outputs // []),
        constraints: ($st.constraints // []),
        allowed_paths: ($st.allowed_paths // []),
        forbidden_paths: ($st.forbidden_paths // []),
        acceptance_criteria: ($st.acceptance_criteria // []),
        ui_change_mode: (if ($st.ui_change_mode // "") == "" then null else $st.ui_change_mode end),
        ui_change_contract: ($st.ui_change_contract // (if ($st.ui_change_path // "") == "" then null else {path: $st.ui_change_path, sha256: ($st.ui_change_sha256 // ""), schema_version: ($st.ui_change_schema_version // "")} end)),
        zavira: ($st.zavira // []),
        plan_step: ($st.plan_step // null)
      }')"
    steps_json="$(echo "$steps_json" | jq --argjson step "$step_obj" '. + [$step]')"
  done

  # Gates: the EPIC's DoD Gates, or (direct) what the project's execution.yaml defines.
  local gates_json="[]"
  if [[ "$direct" -eq 1 ]]; then
    gates_json="$(aid_plan_json_gates "$exec_yaml")" || exit $?
  elif [[ -n "$gates_file" ]]; then
    gates_json="$(cat "$gates_file")"
  fi

  local plan_source_arg="null" zadani_json='{}' z zs
  [[ -n "$plan_source" && "$plan_source" != "null" ]] && plan_source_arg="$(jq -n --arg s "$plan_source" '$s')"
  if [[ -n "$src_plan_file" ]]; then
    z="$(_aid_fm_get "$src_plan_file" zadani)"; zs="$(_aid_fm_get "$src_plan_file" zadani_sha256)"
    zadani_json="$(jq -nc --arg z "$z" --arg s "$zs" --arg p "$(sha256sum "$src_plan_file" | cut -d' ' -f1)" '(if $z == "" then {} else {zadani: $z} end) + (if $s == "" then {} else {zadani_sha256: $s} end) + {source_plan_sha256: $p}')"   # P110: the step measurement reads this plan
  fi
  local direct_json='{}'
  if [[ "$direct" -eq 1 ]]; then
    local rr='[]' pid proj
    if [[ -n "$rr_file" ]]; then
      rr="$(cat "$rr_file")"
    elif [[ -n "$src_plan_file" ]]; then
      # The plan's own repo_roots frontmatter; the branch carries the project name.
      pid="$(_aid_fm_get "$src_plan_file" id)"
      proj="$(basename "$(aid_state_root 2>/dev/null || pwd)")"
      rr="$(aid_plan_repo_roots_json "$src_plan_file" "$pid" "$proj")" || exit $?
    fi
    direct_json="$(jq -nc --argjson rr "$rr" '{direct: true, repo_roots: $rr}')"
  fi

  # Large pieces go to jq through files (--slurpfile), not --argjson: a detailed
  # plan exceeds the per-argument limit (MAX_ARG_STRLEN, 128 KB on Linux).
  local tmp plan_json
  tmp="$(mktemp -d)"
  printf '%s' "$steps_json"    > "${tmp}/steps.json"
  printf '%s' "$deps_json"     > "${tmp}/deps.json"
  printf '%s' "$parallel_json" > "${tmp}/parallel.json"
  printf '%s' "$analysis_json" > "${tmp}/analysis.json"
  printf '%s' "$gates_json"    > "${tmp}/gates.json"
  printf '%s' '{"max_retries_per_gate": 3}' > "${tmp}/budget.json"
  plan_json="$(jq -n \
    --arg epic_id "$epic_id" \
    --argjson source_plan "$plan_source_arg" \
    --argjson zadani "$zadani_json" \
    --argjson direct "$direct_json" \
    --slurpfile steps "${tmp}/steps.json" \
    --slurpfile deps "${tmp}/deps.json" \
    --slurpfile parallel "${tmp}/parallel.json" \
    --slurpfile analysis "${tmp}/analysis.json" \
    --slurpfile gates "${tmp}/gates.json" \
    --slurpfile budget "${tmp}/budget.json" \
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
    } + $zadani + $direct')"
  rm -rf "$tmp"

  # Structural validation of plan.schema.json's critical requirements; gate
  # names are only checked for shape — whether execution.yaml defines them is
  # aid-run-gates.sh's dynamic reconciliation.
  local validation_errors
  validation_errors="$(echo "$plan_json" | jq -r --arg roles "$AID_PLAN_JSON_ROLES" '
    def valid_roles: ($roles | split(" "));
    def valid_gate_name($g): ($g | type) == "string" and ($g | test("^[A-Za-z][A-Za-z0-9_-]*$"));
    . as $root |
    [
      (if .epic_id == null or (.epic_id | type) != "string" then "missing or invalid epic_id" else empty end),
      (if .version == null or (.version | type) != "number" then "missing or invalid version" else empty end),
      (if .steps == null or (.steps | type) != "array" or (.steps | length) == 0 then "steps must be non-empty array" else empty end),
      (if .dependencies == null or (.dependencies | type) != "array" then "dependencies must be array" else empty end),
      (.steps // [] | to_entries[] |
        .value as $step | .key as $idx |
        (
          (if ($step.id | test("^step_[a-z0-9_]+$") | not) then "step[\($idx)].id invalid: \($step.id)" else empty end),
          (if ([valid_roles[] | select(. == $step.role)] | length) == 0 then "step[\($idx)].role invalid: \($step.role)" else empty end),
          (if ($step.objective | length) < 10 then "step[\($idx)].objective too short" else empty end)
        )
      ),
      (.steps | map(.id)) as $step_ids |
      (.dependencies // [] | to_entries[] |
        .value as $dep | .key as $idx |
        (
          (if ($step_ids | index($dep.before)) == null then "dependencies[\($idx)].before references unknown step: \($dep.before)" else empty end),
          (if ($step_ids | index($dep.after)) == null then "dependencies[\($idx)].after references unknown step: \($dep.after)" else empty end)
        )
      ),
      (.parallel_groups // [] | to_entries[] |
        .value as $pg | .key as $idx |
        (if ($pg | length) < 2 then "parallel_groups[\($idx)] must have at least 2 items" else empty end)
      ),
      (.analysis_groups // [] | to_entries[] |
        .value as $ag | .key as $idx |
        (
          (if ($ag.id | test("^analysis_[0-9]+_[a-z_]+$") | not) then "analysis_groups[\($idx)].id invalid: \($ag.id)" else empty end),
          (if ($step_ids | index($ag.target)) == null then "analysis_groups[\($idx)].target references unknown step: \($ag.target)" else empty end)
        )
      ),
      (.gates // [] | to_entries[] |
        .value as $gate | .key as $idx |
        if (valid_gate_name($gate) | not) then "gates[\($idx)] invalid gate name: \($gate)" else empty end
      ),
      (.repo_roots // [] | to_entries[] |
        .value as $r | .key as $idx |
        if ($r | type) != "object" or ([$r | keys[] | select(IN("name","path","worktree","branch","base") | not)] | length) > 0
           or ([("name","path","worktree","branch","base") | select(($r[.] // "") | type != "string" or . == "")] | length) > 0
        then "repo_roots[\($idx)] must be {name, path, worktree, branch, base}" else empty end
      )
    ] | if length > 0 then join("; ") else empty end
  ')"
  [[ -z "$validation_errors" ]] || error_exit "Schema validation failed: $validation_errors" 1

  local tmp_out="${out}.tmp.$$"
  mkdir -p "$(dirname "$out")" 2>/dev/null || error_exit "Cannot create directory for $out" 3
  echo "$plan_json" > "$tmp_out" && mv -f "$tmp_out" "$out" || { rm -f "$tmp_out"; error_exit "Cannot write plan.json to $out" 3; }
}
