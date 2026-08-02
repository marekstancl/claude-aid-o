#!/usr/bin/env bash
# aid-execution-unit-membership.sh — P069 Step 2.
#
# Proves a catalog run_units[].run_unit_id and a schedulable execution unit
# (Step 1's shape) are NOT automatically the same thing (Constraint 7):
# every requested run_unit_id must resolve to EXACTLY ONE catalog run_unit,
# and two DIFFERENT run_unit_ids resolving to a byte-identical command is
# ambiguous duplication unless both are explicitly annotated dedup:true
# (Step 1's own field — never inferred here).
#
# Implementation Detail (per the plan): pure resolution logic against an
# already-loaded catalog document — no test is ever executed by this file.
# A run_unit_id whose --filter pattern now matches zero current tests (a
# stale reference after a source file changed) is a known edge case this
# step does NOT detect — that would require executing or statically
# re-parsing the target file, which is out of scope for pure resolution;
# left as a documented gap, not silently claimed as handled.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-bats.sh's own header for the same idiom).

# execution_unit_membership_verify <units_json> <catalog_json> <verifier_run_id>
#   units_json:   JSON array of execution-unit objects (Step 1 schema), each
#                 with at least unit_id (+ dedup, defaulting to false).
#   catalog_json: the FULL test-catalog document, ALREADY converted to JSON
#                 by the caller (e.g. `yq -o=json '.' .aid-o/config/test-catalog.yaml`)
#                 — this function never reads a file itself.
#   verifier_run_id: opaque id stamped into every membership_binding, naming
#                 the verification pass that produced it.
#
#   On success: emits the array on stdout with membership_verified:true and a
#   freshly-written membership_binding {catalog_fingerprint, verified_at,
#   verifier_run_id} stamped onto every unit. `command` is ALSO overwritten
#   with the CATALOG's own resolved command (Codex review — the catalog is
#   the authoritative source of "what this unit_id actually runs"; a caller-
#   supplied `command` that merely happens to carry a matching unit_id and a
#   valid-looking fingerprint must never be trusted as-is, since nothing
#   upstream of this function checked it against the catalog at all). On any
#   ambiguous resolution or malformed input: nothing on stdout, a message on
#   stderr, return 1.
execution_unit_membership_verify() {
  local units_json="$1" catalog_json="$2" verifier_run_id="$3"
  local now_iso; now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -e 'type == "array" and length > 0' <<<"$units_json" >/dev/null 2>&1 || {
    echo "execution_unit_membership_verify: units_json must be a non-empty JSON array" >&2
    return 1
  }

  local -a unit_ids=()
  mapfile -t unit_ids < <(jq -r '.[].unit_id' <<<"$units_json") || {
    echo "execution_unit_membership_verify: failed to extract unit_id from units_json" >&2
    return 1
  }

  local -A resolved_fp=() resolved_cmd=()
  local id count fingerprint command_json
  for id in "${unit_ids[@]}"; do
    count="$(jq --arg id "$id" '[.run_units[] | select(.run_unit_id == $id)] | length' <<<"$catalog_json")"
    if [[ "$count" -ne 1 ]]; then
      echo "execution_unit_membership_verify: run_unit_id '$id' resolved to $count candidates in the catalog (expected exactly 1)" >&2
      return 1
    fi
    fingerprint="$(jq -r --arg id "$id" '.run_units[] | select(.run_unit_id == $id) | .runtime.fingerprint' <<<"$catalog_json")"
    command_json="$(jq -cS --arg id "$id" '.run_units[] | select(.run_unit_id == $id) | .command' <<<"$catalog_json")"
    resolved_fp["$id"]="$fingerprint"
    resolved_cmd["$id"]="$command_json"
  done

  # Cross-id duplicate-command check: iterate every distinct PAIR of
  # requested unit_ids — O(n^2) but n is a small selected set, never the
  # whole portfolio.
  local i j id_i id_j dedup_i dedup_j
  for ((i = 0; i < ${#unit_ids[@]}; i++)); do
    id_i="${unit_ids[$i]}"
    for ((j = i + 1; j < ${#unit_ids[@]}; j++)); do
      id_j="${unit_ids[$j]}"
      [[ "$id_i" != "$id_j" ]] || continue
      [[ "${resolved_cmd[$id_i]}" == "${resolved_cmd[$id_j]}" ]] || continue
      dedup_i="$(jq -r --arg id "$id_i" '.[] | select(.unit_id == $id) | .dedup // false' <<<"$units_json")"
      dedup_j="$(jq -r --arg id "$id_j" '.[] | select(.unit_id == $id) | .dedup // false' <<<"$units_json")"
      if [[ "$dedup_i" != "true" || "$dedup_j" != "true" ]]; then
        echo "execution_unit_membership_verify: run_unit_id '$id_i' and '$id_j' resolve to byte-identical commands without an explicit dedup:true annotation on both" >&2
        return 1
      fi
    done
  done

  local out="$units_json"
  for id in "${unit_ids[@]}"; do
    out="$(jq -c --arg id "$id" --arg fp "${resolved_fp[$id]}" --arg va "$now_iso" --arg vr "$verifier_run_id" \
      --argjson cmd "${resolved_cmd[$id]}" \
      'map(if .unit_id == $id then . + {command:$cmd, membership_verified:true, membership_binding:{catalog_fingerprint:$fp, verified_at:$va, verifier_run_id:$vr}} else . end)' \
      <<<"$out")" || {
      echo "execution_unit_membership_verify: jq transform failed while stamping '$id'" >&2
      return 1
    }
  done
  printf '%s\n' "$out"
}
