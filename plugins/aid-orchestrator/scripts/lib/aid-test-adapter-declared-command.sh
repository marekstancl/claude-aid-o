#!/usr/bin/env bash
# aid-test-adapter-declared-command.sh — P066 Step 3.
#
# Any command already registered as a gate in the target project's real
# execution.yaml becomes one run_units[] entry keyed by gate name — always
# {type:"shell", shell:"<verbatim execution.yaml command>"} (gate strings
# routinely use &&/pipes/{placeholder} templating, never tokenized).
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header).

_DECLCMD_ADAPTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_DECLCMD_ADAPTER_LIB_DIR}/aid-test-adapter-contract.sh"
# shellcheck source=aid-gate-runtime-baseline.sh
source "${_DECLCMD_ADAPTER_LIB_DIR}/aid-gate-runtime-baseline.sh"

# declared_command_adapter_discover <execution_yaml_path> [existing_run_units_json] [project_root]
#   Emits a JSON array of run_units[] entries, one per gate in
#   <execution_yaml_path>'s top-level `gates:` map. If <existing_run_units_json>
#   (e.g. package-script's own discovery output) already contains a run_unit
#   whose command exactly matches (type-aware: argv array equality or shell
#   string equality) a gate's command, that EXISTING entry is tagged with
#   both provenances instead of emitting a duplicate — dedup by command
#   equality alone (never merely by run_unit_id, and never re-duplicated on a
#   re-run where the existing entry is already tagged declared-command).
#   [project_root], if given, makes source_paths/production_surfaces record
#   the config file's path relative to the project root (never a bare
#   basename) so a later changed-path analysis can associate an edit to the
#   real execution.yaml with the gates it declares.
declared_command_adapter_discover() {
  local execution_yaml="$1" existing_json="${2:-[]}" project_root="${3:-}"
  [[ -f "$execution_yaml" ]] || { printf '%s\n' "$existing_json"; return 0; }
  command -v yq >/dev/null 2>&1 || { printf '%s\n' "$existing_json"; return 0; }

  local gates_json
  gates_json="$(yq -o=json '.gates // {}' "$execution_yaml" 2>/dev/null)" || gates_json="{}"
  [[ "$gates_json" != "null" ]] || gates_json="{}"

  local config_rel_path="$execution_yaml"
  if [[ -n "$project_root" ]]; then
    config_rel_path="${execution_yaml#"${project_root%/}"/}"
  fi

  # Normalize to compact form on entry: the "does a matching entry already
  # exist" check below is a string comparison against jq -c output, which
  # would false-positive on the very first non-matching gate if the caller
  # passed pretty-printed JSON (jq's default -n output).
  local result_json
  result_json="$(jq -c '.' <<<"$existing_json" 2>/dev/null)" || result_json="$existing_json"
  local new_units_ndjson
  new_units_ndjson="$(adapter_ndjson_start)"
  local gate_name gate_command run_unit_id command_json unit_json has_match

  # while-read (not `for x in $(...)`) — a gate name is a valid YAML map key
  # and may legitimately contain whitespace (e.g. "lint pass"); word-splitting
  # via `for` would silently truncate it to its first word, and the ensuing
  # lookup would find no command, silently omitting the gate entirely.
  while IFS= read -r gate_name; do
    [[ -n "$gate_name" ]] || continue
    gate_command="$(jq -r --arg g "$gate_name" '.[$g].command // empty' <<<"$gates_json")"
    [[ -n "$gate_command" ]] || continue
    run_unit_id="gate:${gate_name}"
    command_json="$(jq -n --arg s "$gate_command" '{type:"shell", shell:$s}')"

    # Dedup by COMMAND equality, not by whether tagging changed anything —
    # an already-tagged match (idempotent re-run) must still be recognized
    # as a match, never fall through to appending a second gate:<name> unit.
    has_match="$(jq --argjson cmd "$command_json" 'any(.[]; .command == $cmd)' <<<"$result_json")"
    if [[ "$has_match" == "true" ]]; then
      result_json="$(jq -c --argjson cmd "$command_json" '
        map(if (.command == $cmd) then . + {provenance: ((.provenance // []) + ["declared-command"] | unique)} else . end)
      ' <<<"$result_json")"
      continue
    fi

    unit_json="$(adapter_run_unit_json "$run_unit_id" "declared-command" "$command_json" "[]" \
      "$(jq -n --arg f "$config_rel_path" '[$f]')" "high" '["declared-command"]')" || continue
    adapter_ndjson_append "$new_units_ndjson" "$unit_json"
  done < <(jq -r 'keys[]' <<<"$gates_json" 2>/dev/null)

  local new_units_json
  new_units_json="$(adapter_ndjson_finish "$new_units_ndjson")"
  jq -c -s 'add' <(printf '%s' "$result_json") <(printf '%s' "$new_units_json")
}
