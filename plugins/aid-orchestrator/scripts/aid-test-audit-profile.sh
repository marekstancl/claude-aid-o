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

run_unit_id="" catalog_path="" approved_catalog="" execution_yaml="" output_dir="" audit_id=""
target_root="" project_root="" budget_minutes="" contains_json="[]"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-unit-id)   [[ $# -ge 2 ]] || _die 2 "--run-unit-id requires a value"; run_unit_id="$2"; shift 2 ;;
    --catalog)       [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --approved-catalog) [[ $# -ge 2 ]] || _die 2 "--approved-catalog requires a value"; approved_catalog="$2"; shift 2 ;;
    --execution-yaml)[[ $# -ge 2 ]] || _die 2 "--execution-yaml requires a value"; execution_yaml="$2"; shift 2 ;;
    --output-dir)    [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --audit-id)      [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
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
# Where the command comes FROM and what may approve it are two different
# questions. During an audit the command is read from the catalog under
# discussion — which may be `test-catalog.proposed.yaml`, a file the audit
# itself produced — while approval must come from the APPROVED catalog. They
# are the same file in the ordinary case, and defaulting keeps that simple,
# but conflating them would let an audit approve its own proposals.
[[ -n "$approved_catalog" ]] || approved_catalog="$catalog_path"
[[ -f "$approved_catalog" ]] || _die 2 "--approved-catalog '$approved_catalog' does not exist"
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

# The timing flag is added ONLY when the installed runner is known to honour
# it. An unsupported runner produces a file-level lower bound instead of a
# fabricated per-case breakdown.
runner="$(jq -r '.runner' <<<"$unit_json")"
timing_supported="false"
command_is_shell_form="false"
mapfile -t argv < <(jq -r '(.argv // [])[]' <<<"$command_json")
if [[ "${#argv[@]}" -eq 0 ]]; then
  # shell-form command: what actually runs is `bash -c <string>`.
  command_is_shell_form="true"
  mapfile -t argv < <(printf '%s\n' "bash" "-c" "$(jq -r '.shell // ""' <<<"$command_json")")
fi
# `--timing` goes to the RUNNER, and for a shell-form command argv[0] is `bash`,
# not the runner. Inserting it there produced `bash --timing -c '<command>'`,
# which is not a thing bash accepts — a per-case breakdown request that could
# only ever fail. A shell-form unit gets a file-level lower bound instead, which
# is the same honest fallback used for any runner that cannot report per case.
if [[ "$runner" == "bats" && "$command_is_shell_form" == "false" ]] && bats_timing_supported; then
  timing_supported="true"
  argv=("${argv[0]}" "--timing" "${argv[@]:1}")
fi

# The allowlist must approve the command that will ACTUALLY RUN, not the one
# it was derived from. Checking before the `--timing` insertion approved a
# different argv than the one executed — a small gap, but the whole point of
# the allowlist is that the thing measured is the thing the project runs.
effective_command_json="$(jq -nc --args '{type:"argv", argv:$ARGS.positional}' -- "${argv[@]}")"
if ! aid_test_audit_check_allowed "full" "$effective_command_json" "$execution_yaml" "$approved_catalog" 2>/dev/null; then
  # One narrow exemption, and it is checked rather than assumed: `--timing` is
  # a read-only observation of an otherwise approved command. It is permitted
  # only when (a) the command WITHOUT it is approved, and (b) the executed
  # argv differs from that approved argv by exactly that one token. Anything
  # else — a second flag, a changed target, a reordered argument — is refused
  # before a process starts.
  _timing_exempt="false"
  if [[ "$timing_supported" == "true" ]] \
     && aid_test_audit_check_allowed "full" "$command_json" "$execution_yaml" "$approved_catalog" 2>/dev/null; then
    _stripped_json="$(jq -nc --args '{type:"argv", argv:$ARGS.positional}' -- \
      "${argv[0]}" "${argv[@]:2}")"
    if [[ "${argv[1]}" == "--timing" ]] \
       && [[ "$(jq -cS '.argv' <<<"$_stripped_json")" == "$(jq -cS '.argv' <<<"$command_json")" ]]; then
      _timing_exempt="true"
    fi
  fi
  if [[ "$_timing_exempt" != "true" ]]; then
    _die 11 "the command that would run for '$run_unit_id' is not in the approved allowlist — refused before any process started: $(printf '%s ' "${argv[@]}")"
  fi
fi

# ─── Run it, through the job supervisor ─────────────────────────────────────
#
# NOT a bare `timeout`. The first cut ran the command directly, which bypassed
# the contract every other long-running command in this system already obeys:
# process-group ownership so children die with the job, a durable terminal
# receipt, an explicit `lost` state distinguishable from a crash, and cancel.
# A profiler that can strand a process group inside a disposable clone leaves
# the machine dirtier than it found it.
#
# The argv handed to `--` is EXACTLY the argv the allowlist approved above:
# the working directory comes from the subshell (a detached child inherits
# cwd), never from wrapping the command in `env -C`, which would mean the
# thing approved and the thing recorded were different strings.
jobs_dir="${output_dir%/}/profile-jobs"
mkdir -p "$jobs_dir"

# Job ids are [A-Za-z0-9._-] and <=128. A run unit id can exceed that and can
# repeat across runs, and `run` refuses an id that already exists — so the id
# is a readable tail plus a digest of the full id, made unique per attempt.
_id_slug="$(printf '%s' "$run_unit_id" | tr -c 'A-Za-z0-9._-' '_')"
_id_slug="${_id_slug: -60}"
_id_hash="$(printf '%s' "$run_unit_id" | sha256sum | cut -c1-8)"
job_id="profile-${_id_hash}-${_id_slug}"
_n=0
while [[ -e "${jobs_dir}/${job_id}" ]]; do
  _n=$(( _n + 1 ))
  job_id="profile-${_id_hash}-${_n}-${_id_slug}"
done

started_ms=$(( $(date +%s%N) / 1000000 ))
if ! ( cd "$target_canon" && bash "${SCRIPT_DIR}/aid-job.sh" run \
        --jobs-dir "$jobs_dir" --id "$job_id" \
        --label "profile:${run_unit_id}" \
        --repo "$target_canon" \
        --deadline "$deadline_s" --expect-p95 "$deadline_s" \
        -- "${argv[@]}" ) >/dev/null 2>&1; then
  _die 12 "could not start the profiling job through aid-job.sh"
fi

# The live log, while the job runs. aid-job.sh writes it INCREMENTALLY, so a
# suite that will exceed an hour is observable here long before its deadline.
# The path is named in the receipt so that is possible without knowing the
# job layout.
live_log="${jobs_dir}/${job_id}/stdout.log"

# Wait for a terminal result. `collect` exits 3 while the job is in flight —
# an in-flight job is explicitly not evidence, so polling for the terminal
# record is the contract rather than a workaround.
collect_json=""; collect_rc=3
_waited=0
_grace=$(( deadline_s + 60 ))
while (( _waited <= _grace )); do
  set +e
  collect_json="$(bash "${SCRIPT_DIR}/aid-job.sh" collect --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null)"
  collect_rc=$?
  set -e
  [[ "$collect_rc" -ne 3 ]] && break
  sleep 2; _waited=$(( _waited + 2 ))
done
ended_ms=$(( $(date +%s%N) / 1000000 ))
elapsed_ms=$(( ended_ms - started_ms ))

: > "$log_path"
if [[ -f "$live_log" ]]; then cat "$live_log" >> "$log_path"; fi

job_state="$(jq -r '.state // "unknown"' <<<"${collect_json:-null}" 2>/dev/null || echo unknown)"
run_rc="$(jq -r '.exit_code // 1' <<<"${collect_json:-null}" 2>/dev/null || echo 1)"
[[ "$run_rc" =~ ^-?[0-9]+$ ]] || run_rc=1

# Map on the job STATE, never on the exit code. A deadline kill arrives as
# SIGTERM and exits 143 — the same code a `kill` from an operator produces —
# so classifying by exit code would file every timeout as "someone stopped it".
complete="true"; incomplete_reason="null"; cancelled="false"
case "$job_state" in
  terminal_pass|terminal_fail)
    complete="true" ;;
  timed_out)
    complete="false"; incomplete_reason='"deadline"' ;;
  cancelled)
    # An operator stopped the run. A different fact from "this suite is too
    # slow", and conflating them would let a keyboard interrupt masquerade as
    # a measurement.
    complete="false"; incomplete_reason='"cancelled"'; cancelled="true" ;;
  lost|*)
    # No terminal record after the deadline plus grace, or the supervisor
    # itself reported the job lost. Either way nothing here is a measurement.
    complete="false"; incomplete_reason='"lost"'; job_state="lost" ;;
esac

# ─── Evidence log size cap ──────────────────────────────────────────────────
# A profile of a pathological suite can produce an unbounded log. Truncating
# from the MIDDLE keeps both the beginning (the plan line and the early, fast
# cases) and the tail (where a failure or the deadline lands) — dropping the
# tail would discard exactly the part a reader needs.
log_cap="$(test_audit_decision_key profile_log_max_bytes "$project_root" 2>/dev/null || echo 10485760)"
[[ "$log_cap" =~ ^[0-9]+$ && "$log_cap" -gt 0 ]] || log_cap=10485760
log_bytes="$(wc -c < "$log_path" | tr -d ' ')"
log_truncated="false"; log_dropped_bytes=0
if [[ "$log_bytes" -gt "$log_cap" ]]; then
  keep=$(( log_cap / 2 ))
  log_dropped_bytes=$(( log_bytes - log_cap ))
  {
    head -c "$keep" "$log_path"
    printf '\n... [%s bytes dropped from the middle to stay under decision.profile_log_max_bytes=%s] ...\n' \
      "$log_dropped_bytes" "$log_cap"
    tail -c "$keep" "$log_path"
  } > "${log_path}.capped"
  mv "${log_path}.capped" "$log_path"
  log_truncated="true"
fi

# ─── Attribution ────────────────────────────────────────────────────────────
timing_doc='{}'
if [[ "$timing_supported" == "true" ]]; then
  timing_doc="$(bats_timing_parse "$(cat "$log_path")" "$run_unit_id" "$(bats_timing_version || true)")"
fi

# cost_curve — do per-case durations rise with ordinal? This is the one thing
# the timing signal can establish on its own, and the field is named for the
# measurement rather than for a cause. It was called `fixture_growth`, which
# asserted accumulating fixtures — a mechanism the timing data cannot see, and
# one that turned out not to exist in the first suite it was pointed at.
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
# ─── Root cause, or an honest refusal to name one ───────────────────────────
#
# WHAT THE TIMING SIGNAL CAN AND CANNOT SAY.
#
# A rising per-case duration means later cases were more expensive than earlier
# ones. It does NOT mean state accumulated. In this repository every Bats case
# runs `setup_test_evidence_dir`, which mktemp's a fresh root and git-inits a
# fresh repository per test — so there is no shared fixture to grow, and the
# same pattern is produced just as well by later cases being substantively
# heavier work. The first cut of this script called that `fixture_growth` with
# `confidence: high` and the words "state accumulates", and mapped it straight
# to `fix`. That is a plausible cause attached to a timing shape: exactly the
# defect this whole capability exists to remove, committed by the tool meant to
# remove it.
#
# So the bucket is `cost_rises_across_run` — a description of the measurement —
# and it is never more than a SIGNAL. Deciding between accumulation and
# intrinsically heavier cases requires the fresh-root/reordered probe named
# below, and until that runs the action is `measure`.
#
# An INCOMPLETE run can never carry high confidence about anything, because the
# cases it never reached are exactly the ones that would settle the question.
tie_tolerance="$(test_audit_decision_key rootcause_tie_tolerance "$project_root" 2>/dev/null || echo 0.1)"
[[ "$tie_tolerance" =~ ^[0-9]*\.?[0-9]+$ ]] || tie_tolerance="0.1"

root_cause_json="$(jq -nc \
  --argjson growth "$growth_json" --argjson signals "$signals_json" --argjson dup "$dup_json" \
  --arg complete "$complete" --arg timing "$timing_supported" \
  --arg cancelled "$cancelled" --argjson tie "$tie_tolerance" '
  ($growth.detected // false) as $rises
  | (($signals.explicit_sleeps // 0) > 0 or ($signals.retry_or_wait_loops // 0) > 0) as $waits
  | if $cancelled == "true" then
      {bucket:"undecidable", confidence:"low",
       reason:"the run was cancelled by an operator before it finished, so nothing was measured to completion",
       next_probe:"re-run without cancelling"}
    elif $timing != "true" then
      {bucket:"undecidable", confidence:"low",
       reason:"the installed runner exposes no per-test timing, so only a file-level lower bound is available",
       next_probe:"re-run under a runner build that supports per-test timing, or wrap the suite to time each case"}
    elif ($dup.duplicated // false) then
      # The one cause that is decidable WITHOUT timing: the same unit really is
      # dispatched by two gates, which is a fact about configuration.
      {bucket:"duplicate_membership", confidence:"high",
       reason:("this unit is dispatched by more than one gate with exact membership: " + ($dup.gates | join(", "))),
       next_probe:null}
    elif $rises and $waits then
      # Two candidate explanations within tolerance of each other, and no way
      # to rank them from one duration per case. Naming one would be a coin
      # toss with a citation.
      {bucket:"undecidable", confidence:"low",
       reason:("later cases cost " + ($growth.ratio|tostring) + "x the earliest ones AND the source contains "
               + (($signals.explicit_sleeps // 0)|tostring) + " explicit sleeps with "
               + (($signals.retry_or_wait_loops // 0)|tostring) + " retry/wait constructs — the runner reports one duration per case and cannot rank waiting against heavier work"),
       next_probe:"re-run the slowest and fastest bands each from a FRESH fixture root, and again in reversed order; if the slow band is fast from clean, the cost is accumulated state, otherwise it is intrinsic to those cases"}
    elif $rises then
      {bucket:"cost_rises_across_run",
       confidence:(if $complete == "true" then "medium" else "low" end),
       reason:("per-case cost rises from " + ($growth.first_quartile_ms|tostring) + "ms to "
               + ($growth.last_quartile_ms|tostring) + "ms across the observed cases (x" + ($growth.ratio|tostring)
               + "). This is a SIGNAL, not a cause: later cases may be accumulating state, or may simply be heavier work"
               + (if $complete == "true" then "" else ", and the run did not finish, so the cases that would distinguish them were never reached" end)),
       next_probe:"re-run the slowest and fastest bands each from a FRESH fixture root, and again in reversed order; if the slow band is fast from clean, the cost is accumulated state, otherwise it is intrinsic to those cases"}
    elif $waits then
      {bucket:"undecidable", confidence:"low",
       reason:("the source contains " + (($signals.explicit_sleeps // 0)|tostring) + " explicit sleeps and "
               + (($signals.retry_or_wait_loops // 0)|tostring) + " retry/wait constructs, but the runner reports one duration per case and cannot separate waiting from working"),
       next_probe:"re-run the slowest cases with the waits instrumented, or time the suite with the waits stubbed out, and compare"}
    elif $complete != "true" then
      {bucket:"undecidable", confidence:"low",
       reason:"the run did not complete within its budget, so no bucket holds a citable majority of the time",
       next_probe:"re-run the slowest observed cases alone with a larger budget"}
    else
      {bucket:"test_body", confidence:"medium",
       reason:"no rising cost, no duplicate membership and no wait constructs — the cost appears to be the behaviour under test",
       next_probe:null}
    end')"

# ─── Bindings ───────────────────────────────────────────────────────────────
#
# Two of them, and both are re-checked by the consolidator rather than trusted:
#
#   * `audit_id` — which audit this receipt belongs to. A profiles directory
#     is just a directory; without this, a receipt left behind by an earlier
#     audit would be read as evidence for the current one.
#   * `evidence_log_sha256` — the bytes the claims were derived from. If the
#     log is edited, replaced or truncated after the fact, the receipt no
#     longer matches it and finalization stops.
evidence_log_sha256="$(sha256sum "$log_path" | cut -d" " -f1)"

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
  --argjson log_truncated "$([[ "$log_truncated" == "true" ]] && echo true || echo false)" \
  --argjson log_dropped "$log_dropped_bytes" \
  --argjson cancelled "$([[ "$cancelled" == "true" ]] && echo true || echo false)" \
  --arg job_id "$job_id" --arg job_state "$job_state" --arg live_log "$live_log" \
  --arg audit_id "$audit_id" --arg log_sha "$evidence_log_sha256" \
  '{schema_version:"aid-test-profile-v1", run_unit_id:$id, runner:$runner,
    complete:$complete, incomplete_reason:$reason,
    elapsed_ms:$elapsed, exit_code:$rc, budget_seconds:$budget,
    lower_bound_ms: (if $complete then null else $elapsed end),
    timing:$timing, cost_curve:$growth, source_signals:$signals,
    duplicate_membership:$dup, root_cause:$root, evidence_log:$log,
    evidence_log_sha256:$log_sha,
    audit_id: (if $audit_id == "" then null else $audit_id end),
    cancelled:$cancelled,
    job: {id:$job_id, state:$job_state, live_log:$live_log},
    evidence_log_truncated:$log_truncated, evidence_log_dropped_bytes:$log_dropped}' \
  > "$receipt_path"

echo "$receipt_path"
