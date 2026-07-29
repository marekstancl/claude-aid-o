#!/usr/bin/env bash
# aid-test-adapter-bats.sh — P066 Step 2.
#
# discover() returns exactly ONE run_units[] entry per .bats FILE — never per
# @test. Rewritten after PM feedback found an earlier draft creating one
# catalog entry PER @test (~1,610 in this repo), contradicting the 88-
# run_units count promised elsewhere in this plan.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header).

_BATS_ADAPTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_BATS_ADAPTER_LIB_DIR}/aid-test-adapter-contract.sh"
# shellcheck source=aid-gate-runtime-baseline.sh
source "${_BATS_ADAPTER_LIB_DIR}/aid-gate-runtime-baseline.sh"

# bats_adapter_discover <project_root> [search_subdir]
#   Emits a JSON array of run_units[] entries to stdout, one per discovered
#   .bats file under <project_root>/[search_subdir] (default: whole tree).
#   For each file, also statically greps every `@test "..."` line and
#   populates that SAME run_unit's test_cases[] diagnostic sub-array — never
#   a second, competing identity.
bats_adapter_discover() {
  local project_root="$1" search_subdir="${2:-.}"
  local search_root="$project_root"
  if [[ "$search_subdir" != "." ]]; then
    search_root="${project_root%/}/${search_subdir#./}"
  fi
  search_root="${search_root%/}"
  [[ -d "$search_root" ]] || { echo "[]"; return 0; }

  local units_json="[]"
  local file rel run_unit_id command_json test_cases_json source_paths_json unit_json

  while IFS= read -r -d '' file; do
    rel="${file#"${project_root%/}"/}"
    run_unit_id="bats:${rel%.bats}"
    command_json="$(jq -n --arg f "$rel" '{type:"argv", argv:["bats", $f]}')"
    test_cases_json="$(_bats_adapter_test_cases "$file")"
    source_paths_json="$(jq -n --arg f "$rel" '[$f]')"
    unit_json="$(adapter_run_unit_json "$run_unit_id" "bats" "$command_json" "$test_cases_json" "$source_paths_json" "medium" '["bats"]')" || {
      echo "bats_adapter_discover: fingerprint computation failed for $rel" >&2
      return 1
    }
    units_json="$(jq -c --argjson u "$unit_json" '. + [$u]' <<<"$units_json")"
  done < <(find "$search_root" -type f -name '*.bats' -print0 | sort -z)

  printf '%s\n' "$units_json"
}

# _bats_adapter_test_cases <bats_file>
#   Statically greps every `@test "..."` line and emits a JSON array of
#   {test_case_id, name, filter_expression} — diagnostic-only, never used to
#   compute run_unit_id/fingerprint/selection.
_bats_adapter_test_cases() {
  local file="$1"
  local cases_json="[]"
  local line name slug

  while IFS= read -r line; do
    name="$(sed -E 's/^[[:space:]]*@test[[:space:]]*"(.*)"[[:space:]]*\{[[:space:]]*$/\1/' <<<"$line")"
    [[ -n "$name" ]] || continue
    slug="$(adapter_slug "$name")"
    cases_json="$(jq -c --arg id "$slug" --arg name "$name" \
      '. + [{test_case_id: $id, name: $name, filter_expression: $name}]' <<<"$cases_json")"
  done < <(grep -E '^[[:space:]]*@test[[:space:]]*".*"[[:space:]]*\{[[:space:]]*$' "$file" 2>/dev/null)

  printf '%s\n' "$cases_json"
}
