#!/usr/bin/env bash
# aid-test-adapter-package-script.sh — P066 Step 3.
#
# Proves the catalog contract is not Bats-specific: reads package.json's
# scripts.*test* entries and CI workflow `run:` lines invoking a recognizable
# runner (vitest, jest, playwright test, pytest, go test). Emits ONE
# run_units[] entry per discovered script/job command — never split
# per-test; a runner's own internal test enumeration (where it exists) would
# populate that entry's test_cases[] diagnostic sub-array in a future
# iteration, never a new run_unit_id.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header).

_PKGSCRIPT_ADAPTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_PKGSCRIPT_ADAPTER_LIB_DIR}/aid-test-adapter-contract.sh"
# shellcheck source=aid-gate-runtime-baseline.sh
source "${_PKGSCRIPT_ADAPTER_LIB_DIR}/aid-gate-runtime-baseline.sh"

_PKGSCRIPT_RUNNER_KEYWORDS='vitest|jest|playwright[[:space:]]+test|pytest|go[[:space:]]+test'

# package_script_adapter_discover <project_root>
#   Emits a JSON array of run_units[] entries: one per package.json test-
#   shaped script, plus one per recognizable CI workflow `run:` line.
package_script_adapter_discover() {
  local project_root="$1"
  local units_json="[]"

  units_json="$(_pkgscript_from_package_json "$project_root" "$units_json")"
  units_json="$(_pkgscript_from_ci_workflows "$project_root" "$units_json")"

  printf '%s\n' "$units_json"
}

# _pkgscript_from_package_json <project_root> <units_json_in>
_pkgscript_from_package_json() {
  local project_root="$1" units_json="$2"
  local pkg="${project_root%/}/package.json"
  [[ -f "$pkg" ]] || { printf '%s\n' "$units_json"; return 0; }

  local names
  names="$(jq -r '.scripts // {} | keys[] | select(test("test"; "i"))' "$pkg" 2>/dev/null)" || {
    printf '%s\n' "$units_json"
    return 0
  }

  local name script_value run_unit_id command_json unit_json
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    script_value="$(jq -r --arg n "$name" '.scripts[$n]' "$pkg")"
    run_unit_id="npm:${name}"
    command_json="$(_pkgscript_command_json "npm" "run" "$name")"
    unit_json="$(adapter_run_unit_json "$run_unit_id" "package-script" "$command_json" "[]" \
      "$(jq -n --arg p "package.json" '[$p]')" "medium" '["package-script"]')" || continue
    units_json="$(jq -c --argjson u "$unit_json" '. + [$u]' <<<"$units_json")"
  done <<<"$names"

  printf '%s\n' "$units_json"
}

# _pkgscript_command_json <argv...> — always argv-type for npm-run invocations
# (npm/the script name never need shell interpretation at this level).
_pkgscript_command_json() {
  jq -n --args '{type:"argv", argv:$ARGS.positional}' "$@"
}

# _pkgscript_extract_run_entries <workflow_file>
#   Emits one line per `run:` step — inline single-line commands as-is;
#   YAML block-scalar bodies (`run: |`, `run: >`, etc.) are collected across
#   their indented continuation lines and joined with a \x01 unit separator
#   so the whole block still reaches the caller as ONE read() line (decoded
#   back to real newlines by the caller before use as a shell command).
_pkgscript_extract_run_entries() {
  local file="$1"
  awk '
    function lead_ws(s,   i) {
      i = 0
      while (i < length(s) && (substr(s, i + 1, 1) == " " || substr(s, i + 1, 1) == "\t")) i++
      return i
    }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN { in_block = 0; block_indent = -1; body = "" }
    {
      line = $0
      if (in_block) {
        if (line ~ /^[ \t]*$/) { next }
        ind = lead_ws(line)
        if (ind > block_indent) {
          stripped = line
          sub(/^[ \t]+/, "", stripped)
          body = (body == "" ? stripped : body "\x01" stripped)
          next
        } else {
          if (body != "") print body
          in_block = 0
        }
      }
      stripped_line = line
      sub(/^[ \t]*-?[ \t]*/, "", stripped_line)
      if (stripped_line ~ /^run:/) {
        val = stripped_line
        sub(/^run:[ \t]*/, "", val)
        val = trim(val)
        if (val == "" || val == "|" || val == ">" || val == "|-" || val == ">-" || val == "|+" || val == ">+") {
          in_block = 1
          block_indent = lead_ws(line)
          body = ""
        } else {
          print val
        }
      }
    }
    END { if (in_block && body != "") print body }
  ' "$file" 2>/dev/null
}

# _pkgscript_from_ci_workflows <project_root> <units_json_in>
#   Scans .github/workflows/*.y*ml `run:` entries (single-line or YAML
#   block-scalar) for a recognizable runner keyword. An entry matching
#   multiple runner keywords splits into multiple entries (edge case from
#   Step 3's plan text).
_pkgscript_from_ci_workflows() {
  local project_root="$1" units_json="$2"
  local wf_dir="${project_root%/}/.github/workflows"
  [[ -d "$wf_dir" ]] || { printf '%s\n' "$units_json"; return 0; }

  local file rel job_index=0 line line_real run_unit_id command_json unit_json rel_json

  while IFS= read -r -d '' file; do
    rel="${file#"${project_root%/}"/}"
    while IFS= read -r line; do
      local matched_kw
      while IFS= read -r matched_kw; do
        [[ -n "$matched_kw" ]] || continue
        job_index=$((job_index + 1))
        run_unit_id="ci:$(basename "$rel" | sed -E 's/\.ya?ml$//'):${job_index}"
        line_real="${line//$'\x01'/$'\n'}"
        command_json="$(jq -n --arg s "$line_real" '{type:"shell", shell:$s}')"
        rel_json="$(jq -n --arg r "$rel" '[$r]')"
        unit_json="$(adapter_run_unit_json "$run_unit_id" "ci" "$command_json" "[]" \
          "$rel_json" "low" '["package-script"]')" || continue
        units_json="$(jq -c --argjson u "$unit_json" '. + [$u]' <<<"$units_json")"
      done < <(grep -oE "$_PKGSCRIPT_RUNNER_KEYWORDS" <<<"$line" | sort -u)
    done < <(_pkgscript_extract_run_entries "$file")
  done < <(find "$wf_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

  printf '%s\n' "$units_json"
}
