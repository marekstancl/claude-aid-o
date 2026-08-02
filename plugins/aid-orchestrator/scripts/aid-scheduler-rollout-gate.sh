#!/usr/bin/env bash
# aid-scheduler-rollout-gate.sh — P069 Step 13.
#
# Pure resolver, called directly by aid-run-gates.sh (Step 14) BEFORE it
# decides whether to invoke the scheduler for a run. Reads the CONFIGURED
# mode from the ONE authoritative source, execution.yaml's
# test_audit.scheduler.mode (P066's test-audit.yaml reserves its own
# scheduler/resource_locks fields for its own audit-time settings only —
# never read here, never authoritative for this key), and every
# divergence-evidence artifact under
# .aid-o/work/evidence/scheduler-divergence/, and resolves the EFFECTIVE
# mode this run is actually allowed to use — staged rollout (Constraint 8):
#   - observe_parallel requires 3 qualifying artifacts with
#     mode_tested: observe_parallel
#   - parallel requires BOTH those same 3 qualifying observe_parallel
#     artifacts (proving the prior stage already passed) AND 3 SEPARATE
#     qualifying artifacts with mode_tested: parallel — observe_parallel
#     evidence alone never unlocks parallel, and parallel-tested evidence
#     without qualifying observe_parallel evidence is also insufficient
#     (cross-mode evidence substitution is rejected)
#
# A qualifying artifact must: parse as valid JSON with every field this
# check reads; have commit_sha == the project's CURRENT HEAD; have
# worktree_kind: disposable_clone (schema already enforces this at write
# time — re-verified here, defense in depth); have pass:true; and its
# recorded catalog_fingerprint_set must still match a FRESH recomputation,
# over the SAME selected_unit_ids, against the project's CURRENT
# .aid-o/config/test-catalog.yaml (the exact same sha256-over-sorted-
# newline-joined-fingerprints formula aid-test-schedule-divergence-check.sh
# itself uses) — a catalog change since the evidence was captured
# invalidates it entirely; never "stale but still partially acceptable".
#
# Missing/stale/insufficient evidence for the target CONFIGURED mode fails
# CLOSED to sequential, never fails open. A single pass:false artifact
# among otherwise-qualifying candidates disqualifies ONLY that artifact
# from the count — it is never averaged in with the passing ones.
#
# Usage:
#   aid-scheduler-rollout-gate.sh --project-root <path>
#
# Output: one JSON object on stdout —
#   {configured_mode, effective_mode, forced, reason,
#    observe_parallel_qualifying_count, parallel_qualifying_count}
# Always exits 0 — this is a resolver, never a hard gate failure in its own
# right; the CALLER (Step 14) decides what to do with effective_mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_die() { echo "aid-scheduler-rollout-gate.sh: $2" >&2; exit "$1"; }

project_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$project_root" ]] || _die 2 "--project-root is required"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

execution_yaml="${project_root}/.aid-o/config/execution.yaml"
configured_mode="sequential"
if [[ -f "$execution_yaml" ]]; then
  configured_mode="$(yq -r '.test_audit.scheduler.mode // "sequential"' "$execution_yaml" 2>/dev/null || echo "sequential")"
fi

_emit() {
  jq -n \
    --arg cm "$configured_mode" --arg em "$1" --argjson forced "$2" --arg reason "$3" \
    --argjson opc "$4" --argjson pc "$5" \
    '{configured_mode:$cm, effective_mode:$em, forced:$forced, reason:$reason,
      observe_parallel_qualifying_count:$opc, parallel_qualifying_count:$pc}'
}

# sequential is always allowed unconditionally — nothing to gate.
if [[ "$configured_mode" == "sequential" ]]; then
  _emit "sequential" false "configured as sequential — no rollout evidence required" 0 0
  exit 0
fi

if [[ "$configured_mode" != "observe_parallel" && "$configured_mode" != "parallel" ]]; then
  _emit "sequential" true "unrecognized test_audit.scheduler.mode value '${configured_mode}' — failing closed to sequential" 0 0
  exit 0
fi

commit_sha=""
if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  commit_sha="$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo "")"
fi
if [[ -z "$commit_sha" ]]; then
  _emit "sequential" true "no resolvable commit_sha (not a git repository, or no HEAD yet) — no divergence evidence can ever match — failing closed to sequential" 0 0
  exit 0
fi

catalog_path="${project_root}/.aid-o/config/test-catalog.yaml"
catalog_json="{}"
if [[ -f "$catalog_path" ]]; then
  catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null || echo '{}')"
fi

evidence_dir="${project_root}/.aid-o/work/evidence/scheduler-divergence"
observe_parallel_count=0
parallel_count=0
# Codex review (HIGH): 3 artifact FILES is not the same guarantee as 3
# DISTINCT evidence runs — copying one qualifying artifact to several
# filenames must never count as 3 separate proofs. Dedup by run_id,
# per mode, before counting.
declare -A seen_run_ids_observe_parallel=()
declare -A seen_run_ids_parallel=()

if [[ -d "$evidence_dir" ]]; then
  shopt -s nullglob
  for artifact in "${evidence_dir}"/*.json; do
    artifact_json="$(jq -c '.' "$artifact" 2>/dev/null || echo "")"
    [[ -n "$artifact_json" ]] || continue
    # Codex review (HIGH): a syntactically-valid but wrong-SHAPE JSON
    # document (an array, a scalar, or an object missing required fields)
    # must never crash field extraction under `set -e` — reject anything
    # that isn't an object with every field this check reads, up front, in
    # ONE guarded call, before any bare `.field` access is ever attempted.
    is_well_shaped="$(jq -r '
      (type == "object")
      and (.commit_sha | type == "string")
      and (.worktree_kind | type == "string")
      and (.mode_tested | type == "string")
      and (.pass | type == "boolean")
      and (.catalog_fingerprint_set | type == "string")
      and (.selected_unit_ids | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      and (.run_id | type == "string" and length > 0)
    ' <<<"$artifact_json" 2>/dev/null || echo "false")"
    [[ "$is_well_shaped" == "true" ]] || continue

    a_commit="$(jq -r '.commit_sha' <<<"$artifact_json")"
    a_worktree="$(jq -r '.worktree_kind' <<<"$artifact_json")"
    a_pass="$(jq -r '.pass' <<<"$artifact_json")"
    a_mode="$(jq -r '.mode_tested' <<<"$artifact_json")"
    a_fp_set="$(jq -r '.catalog_fingerprint_set' <<<"$artifact_json")"
    a_run_id="$(jq -r '.run_id' <<<"$artifact_json")"

    [[ "$a_commit" == "$commit_sha" ]] || continue
    [[ "$a_worktree" == "disposable_clone" ]] || continue
    [[ "$a_pass" == "true" ]] || continue
    [[ "$a_mode" == "observe_parallel" || "$a_mode" == "parallel" ]] || continue

    # Recompute catalog_fingerprint_set fresh against the CURRENT catalog,
    # over the SAME selected_unit_ids this artifact recorded — the exact
    # same sha256-over-sorted-newline-joined-fingerprints formula
    # aid-test-schedule-divergence-check.sh itself uses. Any unit_id no
    # longer present in the current catalog, or any fingerprint drift (or
    # a missing/null fingerprint — Codex review: jq -r renders a JSON null
    # as the literal text "null", which would otherwise pass a bare -z
    # check and hash as if it were a real value), invalidates this
    # artifact entirely (never stale-but-acceptable).
    mapfile -t a_unit_ids < <(jq -r '.selected_unit_ids[]' <<<"$artifact_json")

    fp_list=""
    stale=false
    for uid in "${a_unit_ids[@]}"; do
      fp="$(jq -r --arg id "$uid" '[.run_units[]? | select(.run_unit_id == $id)] | if length == 1 then .[0].runtime.fingerprint else empty end' <<<"$catalog_json" 2>/dev/null || echo "")"
      if [[ -z "$fp" || "$fp" == "null" || ! "$fp" =~ ^sha256:[0-9a-f]{12}$ ]]; then
        stale=true
        break
      fi
      fp_list+="${fp}"$'\n'
    done
    $stale && continue

    current_fp_set="sha256:$(printf '%s' "$fp_list" | sort | sha256sum | cut -d' ' -f1)"
    [[ "$current_fp_set" == "$a_fp_set" ]] || continue

    if [[ "$a_mode" == "observe_parallel" ]]; then
      [[ -n "${seen_run_ids_observe_parallel[$a_run_id]:-}" ]] && continue
      seen_run_ids_observe_parallel["$a_run_id"]=1
      observe_parallel_count=$((observe_parallel_count + 1))
    else
      [[ -n "${seen_run_ids_parallel[$a_run_id]:-}" ]] && continue
      seen_run_ids_parallel["$a_run_id"]=1
      parallel_count=$((parallel_count + 1))
    fi
  done
  shopt -u nullglob
fi

if [[ "$configured_mode" == "observe_parallel" ]]; then
  if (( observe_parallel_count >= 3 )); then
    _emit "observe_parallel" false "3+ qualifying observe_parallel-tested divergence artifacts found (${observe_parallel_count})" "$observe_parallel_count" "$parallel_count"
  else
    _emit "sequential" true "only ${observe_parallel_count} qualifying observe_parallel-tested divergence artifact(s) found (3 required) — failing closed to sequential" "$observe_parallel_count" "$parallel_count"
  fi
  exit 0
fi

# configured_mode == "parallel"
if (( observe_parallel_count >= 3 && parallel_count >= 3 )); then
  _emit "parallel" false "3+ qualifying observe_parallel AND 3+ qualifying parallel-tested divergence artifacts found (${observe_parallel_count}/${parallel_count})" "$observe_parallel_count" "$parallel_count"
elif (( observe_parallel_count >= 3 )); then
  _emit "observe_parallel" true "parallel requires 3 qualifying parallel-tested artifacts IN ADDITION to the 3 observe_parallel ones already satisfied — only ${parallel_count} parallel-tested found — staged down to observe_parallel" "$observe_parallel_count" "$parallel_count"
else
  _emit "sequential" true "neither stage's evidence requirement is met (observe_parallel: ${observe_parallel_count}/3, parallel: ${parallel_count}/3) — failing closed to sequential" "$observe_parallel_count" "$parallel_count"
fi
exit 0
