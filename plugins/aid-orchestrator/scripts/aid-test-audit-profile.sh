#!/usr/bin/env bash
# aid-test-audit-profile.sh — P072 Step 12.
#
# Bounded cost diagnosis for one run unit: WHERE the time goes, not merely how
# much of it there was. A file-level timeout tells nobody what to do; "this
# suite's per-case cost grows as it runs" tells them the state accumulates and
# that splitting the file would move the growth rather than remove it.
#
# WHAT IT WILL NOT DO
#   * It never runs against the live checkout. Diagnostic runs mutate temp
#     trees, spawn process groups and can be killed mid-write; sharing a
#     checkout with a real gate run is how a "measurement" becomes an outage.
#   * It never constructs a command. Every command passes the audit's existing
#     allowlist before a process starts, so the thing measured is the thing the
#     project actually runs.
#   * It never pads a partial result. A run killed at its deadline reports the
#     prefix it observed and a LOWER BOUND, never an extrapolation.
#
# WHAT IT HONESTLY CANNOT SPLIT
#   Bats reports one duration per case and does not separate setup, body and
#   teardown (see lib/aid-test-timing-bats.sh's capability record). So the
#   timing signal alone can distinguish accumulation-over-time from flat cost,
#   and everything finer comes from reading the source. Buckets that need a
#   distinction the runner cannot make are reported as `undecidable` with the
#   probe that would settle them — not guessed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/aid-test-timing-bats.sh
source "${SCRIPT_DIR}/lib/aid-test-timing-bats.sh"
# shellcheck source=lib/aid-test-audit-command-allowlist.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-command-allowlist.sh"
# shellcheck source=lib/aid-test-audit-config.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-config.sh"

_die() { echo "aid-test-audit-profile.sh: $2" >&2; exit "$1"; }

run_unit_id="" catalog_path="" execution_yaml="" output_dir=""
target_root="" project_root="" budget_minutes="" contains_json="[]"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-unit-id)   [[ $# -ge 2 ]] || _die 2 "--run-unit-id requires a value"; run_unit_id="$2"; shift 2 ;;
    --catalog)       [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --execution-yaml)[[ $# -ge 2 ]] || _die 2 "--execution-yaml requires a value"; execution_yaml="$2"; shift 2 ;;
    --output-dir)    [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --target-root)   [[ $# -ge 2 ]] || _die 2 "--target-root requires a value"; target_root="$2"; shift 2 ;;
    --project-root)  [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --budget-minutes)[[ $# -ge 2 ]] || _die 2 "--budget-minutes requires a value"; budget_minutes="$2"; shift 2 ;;
    --contains)      [[ $# -ge 2 ]] || _die 2 "--contains requires a value"; contains_json="$(cat "$2")"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$run_unit_id"  ]] || _die 2 "--run-unit-id is required"
[[ -n "$catalog_path" && -f "$catalog_path" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$output_dir"   ]] || _die 2 "--output-dir is required"
[[ -n "$target_root"  && -d "$target_root"  ]] || _die 2 "--target-root is required and must exist"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"

# ─── The disposable-root refusal ────────────────────────────────────────────
# Same rule and same exit code as the parallel pilot: a diagnostic run must not
# share a checkout with the project it is diagnosing.
_canon() { (cd "$1" && pwd -P); }
target_canon="$(_canon "$target_root")"
project_canon="$(_canon "$project_root")"
if [[ "$target_canon" == "$project_canon" ]]; then
  _die 10 "refusing to profile against the live checkout ('$target_canon' is --project-root) — a diagnostic run mutates temp trees and can be killed mid-write; use a disposable clone"
fi
# A linked worktree shares the object store, so a mutation there is not
# contained either.
if git -C "$target_canon" rev-parse --git-common-dir >/dev/null 2>&1; then
  _common="$(cd "$target_canon" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  _project_common="$(cd "$project_canon" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)"
  if [[ "$_common" == "$_project_common" ]]; then
    _die 10 "refusing to profile in a linked worktree of --project-root (shared git object store at '$_common') — mutations are not contained"
  fi
fi

# ─── Budget ─────────────────────────────────────────────────────────────────
if [[ -z "$budget_minutes" ]]; then
  budget_minutes="$(test_audit_decision_key profile_budget_minutes "$project_root" 2>/dev/null || echo 20)"
fi
[[ "$budget_minutes" =~ ^[0-9]+$ && "$budget_minutes" -ge 1 ]] \
  || _die 2 "--budget-minutes must be a positive integer (got '$budget_minutes')"
deadline_s=$(( budget_minutes * 60 ))

# Output is created only after every argument has been validated: a refusal
# that has already made directories has produced side effects for a run that
# never legitimately started.
mkdir -p "${output_dir%/}/profiles"
log_path="${output_dir%/}/profiles/$(printf '%s' "$run_unit_id" | tr '/:' '__').log"
receipt_path="${output_dir%/}/profiles/$(printf '%s' "$run_unit_id" | tr '/:' '__').json"

# ─── The command comes from the catalog, never from here ────────────────────
unit_json="$(yq -o=json '.' "$catalog_path" \
  | jq -c --arg id "$run_unit_id" '.run_units[] | select(.run_unit_id == $id)')" \
  || _die 3 "could not read the catalog"
[[ -n "$unit_json" ]] || _die 3 "run unit '$run_unit_id' is not in the catalog — this script never invents a command for a unit it cannot find"

command_json="$(jq -c '.command' <<<"$unit_json")"
[[ -n "$execution_yaml" ]] || execution_yaml="${project_root%/}/.aid-o/config/execution.yaml"
if ! aid_test_audit_check_allowed "full" "$command_json" "$execution_yaml" "$catalog_path"; then
  _die 11 "command for '$run_unit_id' is not in the approved allowlist — refused before any process started"
fi

# The timing flag is added ONLY when the installed runner is known to honour
# it. An unsupported runner produces a file-level lower bound instead of a
# fabricated per-case breakdown.
runner="$(jq -r '.runner' <<<"$unit_json")"
timing_supported="false"
mapfile -t argv < <(jq -r '(.argv // [])[]' <<<"$command_json")
if [[ "${#argv[@]}" -eq 0 ]]; then
  # shell-form command
  mapfile -t argv < <(printf '%s\n' "bash" "-c" "$(jq -r '.shell // ""' <<<"$command_json")")
fi
if [[ "$runner" == "bats" ]] && bats_timing_supported; then
  timing_supported="true"
  argv=("${argv[0]}" "--timing" "${argv[@]:1}")
fi

# ─── Run it, streaming ──────────────────────────────────────────────────────
# The log is written INCREMENTALLY. A suite that will exceed an hour must be
# observable long before its deadline; a log that only appears at the end is
# indistinguishable from a hung process.
: > "$log_path"
started_ms=$(( $(date +%s%N) / 1000000 ))
set +e
( cd "$target_canon" && timeout --signal=TERM --kill-after=10s "$deadline_s" "${argv[@]}" ) \
  > >(stdbuf -oL tee -a "$log_path" >/dev/null) 2>&1
run_rc=$?
set -e
wait 2>/dev/null || true
ended_ms=$(( $(date +%s%N) / 1000000 ))
elapsed_ms=$(( ended_ms - started_ms ))

complete="true"; incomplete_reason="null"
if [[ "$run_rc" -eq 124 || "$run_rc" -eq 137 ]]; then
  complete="false"; incomplete_reason='"deadline"'
fi

# ─── Attribution ────────────────────────────────────────────────────────────
timing_doc='{}'
if [[ "$timing_supported" == "true" ]]; then
  timing_doc="$(bats_timing_parse "$(cat "$log_path")" "$run_unit_id" "$(bats_timing_version || true)")"
fi

# fixture_growth — per-case durations rising with ordinal. This is the one
# thing the timing signal can establish on its own, and it is exactly the
# signal that makes "split the file" the wrong answer: the growth follows the
# accumulated state, not the file boundary.
growth_json='{"detected":false,"first_quartile_ms":null,"last_quartile_ms":null,"ratio":null}'
if [[ "$timing_supported" == "true" ]]; then
  growth_json="$(jq -c '
    [ .cases[] | select(.duration_ms != null) | .duration_ms ] as $d
    | if ($d | length) < 8 then
        {detected:false, first_quartile_ms:null, last_quartile_ms:null, ratio:null,
         note:"too few timed cases to distinguish growth from noise"}
      else
        (($d | length) / 4 | floor) as $q
        | (($d[0:$q] | add) / $q) as $first
        | (($d[-$q:] | add) / $q) as $last
        | {detected: ($first > 0 and ($last / $first) >= 2),
           first_quartile_ms: ($first | floor),
           last_quartile_ms: ($last | floor),
           ratio: (if $first > 0 then (($last / $first) * 100 | floor) / 100 else null end)}
      end' <<<"$timing_doc")"
fi

# Source-level signals. These are the buckets the RUNNER cannot distinguish,
# so they are read rather than timed — and reported as signals present, never
# as an attributed share of the duration.
source_path="$(jq -r '.source_paths[0] // empty' <<<"$unit_json")"
signals_json='{}'
if [[ -n "$source_path" && -f "${target_canon}/${source_path}" ]]; then
  f="${target_canon}/${source_path}"
  # `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` appends
  # a second zero and the result is no longer a number. One helper, one value.
  _count() { local n; n="$(grep -cE "$1" "$2" 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0; printf '%s' "$n"; }
  _counti() { local n; n="$(grep -ciE "$1" "$2" 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0; printf '%s' "$n"; }
  signals_json="$(jq -nc \
    --argjson git      "$(_count '(^|[^a-z])git ' "$f")" \
    --argjson sleep    "$(_count '(^|[^a-z])sleep ' "$f")" \
    --argjson retry    "$(_counti 'retry|backoff|until .*do' "$f")" \
    --argjson subproc  "$(_count '\$\(|`' "$f")" \
    '{git_invocations:$git, explicit_sleeps:$sleep, retry_or_wait_loops:$retry, subprocess_substitutions:$subproc}')"
fi

# duplicate_membership — consumed from the inventory's contains[] relation,
# never re-derived here. Only an EXACT membership counts: a runtime-partitioned
# candidate set says nothing about whether this unit really ran twice.
dup_json="$(jq -c --arg id "$run_unit_id" '
  [ .[] | select(.membership == "exact") | select(.run_unit_ids | index($id)) | .gate ]
  | {gates: ., duplicated: ((. | length) > 1)}' <<<"$contains_json")"

# ─── Root cause, or an honest refusal to name one ───────────────────────────
tie_tolerance="$(test_audit_decision_key rootcause_tie_tolerance "$project_root" 2>/dev/null || echo 0.1)"
root_cause_json="$(jq -nc \
  --argjson growth "$growth_json" --argjson signals "$signals_json" --argjson dup "$dup_json" \
  --arg complete "$complete" --arg timing "$timing_supported" '
  if $timing != "true" then
    {bucket:"undecidable", confidence:"low",
     reason:"the installed runner exposes no per-test timing, so only a file-level lower bound is available",
     next_probe:"re-run under a runner build that supports per-test timing, or wrap the suite to time each case"}
  elif ($dup.duplicated // false) then
    {bucket:"duplicate_membership", confidence:"high",
     reason:("this unit is dispatched by more than one gate with exact membership: " + ($dup.gates | join(", "))),
     next_probe:null}
  elif ($growth.detected // false) then
    {bucket:"fixture_growth", confidence:"high",
     reason:("per-case cost rises from " + ($growth.first_quartile_ms|tostring) + "ms to " + ($growth.last_quartile_ms|tostring) + "ms across the run (x" + ($growth.ratio|tostring) + ") — state accumulates, so splitting the file moves the growth rather than removing it"),
     next_probe:null}
  elif (($signals.explicit_sleeps // 0) > 0 or ($signals.retry_or_wait_loops // 0) > 0) then
    {bucket:"undecidable", confidence:"low",
     reason:("the source contains " + (($signals.explicit_sleeps // 0)|tostring) + " explicit sleeps and " + (($signals.retry_or_wait_loops // 0)|tostring) + " retry/wait constructs, but the runner reports one duration per case and cannot separate waiting from working"),
     next_probe:"re-run the slowest cases with the waits instrumented, or time the suite with the waits stubbed out, and compare"}
  elif $complete != "true" then
    {bucket:"undecidable", confidence:"low",
     reason:"the run did not complete within its budget, so no bucket holds a citable majority of the time",
     next_probe:"re-run the slowest observed cases alone with a larger budget"}
  else
    {bucket:"test_body", confidence:"medium",
     reason:"no accumulation, no duplicate membership and no wait constructs — the cost appears to be the behaviour under test",
     next_probe:null}
  end')"

# ─── Receipt ────────────────────────────────────────────────────────────────
jq -nc \
  --arg id "$run_unit_id" --arg runner "$runner" \
  --argjson complete "$([[ "$complete" == "true" ]] && echo true || echo false)" \
  --argjson reason "$incomplete_reason" \
  --argjson elapsed "$elapsed_ms" --argjson rc "$run_rc" \
  --argjson budget "$deadline_s" \
  --argjson timing "$timing_doc" --argjson growth "$growth_json" \
  --argjson signals "$signals_json" --argjson dup "$dup_json" \
  --argjson root "$root_cause_json" \
  --arg log "$(basename "$log_path")" \
  '{schema_version:"aid-test-profile-v1", run_unit_id:$id, runner:$runner,
    complete:$complete, incomplete_reason:$reason,
    elapsed_ms:$elapsed, exit_code:$rc, budget_seconds:$budget,
    lower_bound_ms: (if $complete then null else $elapsed end),
    timing:$timing, fixture_growth:$growth, source_signals:$signals,
    duplicate_membership:$dup, root_cause:$root, evidence_log:$log}' \
  > "$receipt_path"

echo "$receipt_path"
