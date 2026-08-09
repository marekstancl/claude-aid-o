#!/usr/bin/env bats
# test-recovery-ladder.bats — P076 EPIC 2, Step 13.
#
# `lib/aid-recovery-ladder.sh` is the runtime the recovery policy shipped
# without: the loader, the per-run record, the budget refusals and the terminus.
# The properties that matter are the ones that could quietly fail OPEN, so this
# suite spends itself on those rather than on the happy path:
#
#   1  within budget: the attempt is RECORDED and returns 0
#   2  the budget-th + 1 attempt refuses with `budget_exhausted` + adjudicate
#   3  an action the class does not allow is refused BY NAME
#   4  the wall clock refuses even with attempts remaining
#   5  THE EMITTER, A/B: a timeout fixture writes a GATE_TIMEOUT ladder entry
#      while the gate verdict stays byte-identical to the same fixture run by
#      the same runner with the ladder lib ABSENT
#   6  escalate lands `blocked_for_pm` on the map, and leaving ESCALATION still
#      requires `escalation_decision` (regression)
#   7  the reader honours `revoked_unrecorded` — the Step-12 carried obligation
#   8  the other two mechanical emitters (JOB_LOST, SERVICE_UNHEALTHY) really
#      write, from real code paths
#   9  the closed sets are lib == policy == schema, and the loader's NAME and
#      PATH are the ones loader_contract declares
#  10  two concurrent attempts of a 1-attempt class spend it ONCE (the TOCTOU
#      the single critical section closes)
#  11  fail-closed: an unreadable policy adjudicates, it never permits a retry
#  12  the ladder cannot smuggle restart authority — it executes nothing, and
#      aid-service still gates its one restart on the declaration
#
# Nothing here stubs the ladder. Cases 5 and 8 drive the REAL aid-run-gates.sh
# and the REAL aid-service.sh over real fixtures.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  LIB="$PLUGIN_ROOT/scripts/lib/aid-recovery-ladder.sh"
  export LIB
  POLICY="$PLUGIN_ROOT/defaults/policies/auto-recovery.yaml"
  export POLICY
  SCHEMA="$PLUGIN_ROOT/defaults/schemas/auto-recovery.schema.json"
  export SCHEMA
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  export RUN_GATES
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  export FSM

  WORK="$(mktemp -d)"
  export WORK
  PROJ="$WORK/project"
  EVID_REL=".aid-o/work/evidence/E-LAD-1/R-1"
  EVID="$PROJ/$EVID_REL"
  export PROJ EVID EVID_REL
  mkdir -p "$EVID"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1

  REC="$EVID/recovery-ladder.jsonl"
  export REC
}

teardown() {
  # Nothing this suite starts may outlive it. The gate fixtures supervise real
  # processes; a leaked `sleep 60` would be exactly the failure the background
  # machinery exists to prevent.
  local d pgid
  for d in "$WORK"/*/.aid-o/work/evidence/*/*/jobs/*/ ; do
    [[ -f "$d/job.json" ]] || continue
    pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
  done
  [[ -n "${BG_PID:-}" ]] && kill -KILL "$BG_PID" 2>/dev/null || true
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# ── driving the lib ─────────────────────────────────────────────────────────
# Always through a fresh `bash -c` under `set -euo pipefail`: a lib that only
# behaves when the caller is lax is not a lib the AUTO controller can use.
ladder() {
  bash -c 'set -euo pipefail; source "$LIB"; "$@"' _ "$@"
}

# seed_record <json...> — append raw lines to the record, bypassing the writer,
# so a case can construct a history the writer would have taken minutes to
# produce (an exhausted budget, an old first timestamp, a revoked decision).
seed_record() {
  local l
  for l in "$@"; do printf '%s\n' "$l" >> "$REC"; done
}

attempt_line() { # attempt_line <class> <action> <outcome> <n> [ts]
  jq -nc --arg c "$1" --arg a "$2" --arg o "$3" --argjson n "$4" \
         --arg ts "${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
    '{ts:$ts, event:"recovery_attempt", class:$c, outcome:$o, action:$a, attempt_n:$n, auto:true}'
}

init_git_project() {
  local root="$1"
  git -C "$root" init -q
  git -C "$root" config user.email ladder@example.com
  git -C "$root" config user.name Ladder
  printf 'ladder fixture\n' > "$root/README.md"
  printf '.aid-o/\n' > "$root/.gitignore"
  git -C "$root" add README.md .gitignore
  git -C "$root" commit -qm "ladder fixture base"
}

# Volatile fields of a gates report — the same list the P076 golden normalizer
# uses, for the same reasons (wall clock, fresh commit sha).
normalize_report() {
  jq -S '
      .completed_at = "NORMALIZED"
    | ._generated_at = "NORMALIZED"
    | .revision.head_sha = "NORMALIZED"
    | .run_id = "NORMALIZED" | .epic_id = "NORMALIZED"
    | .gates |= with_entries(
        if (.value | type) == "object" then
          .value |= (
              (if has("duration_ms") then .duration_ms = 0 else . end)
            | (if has("output") then .output = "NORMALIZED" else . end)
            | (if (.runtime_baseline | type) == "object"
               then .runtime_baseline.p95_ms = 0 | .runtime_baseline.mean_ms = 0
               else . end)
          )
        else . end)
    | (if has("_command_log") then ._command_log |= map(.duration_ms = 0) else . end)
  ' "$1"
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: an attempt within budget is recorded and returns 0" {
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "proceed 1" ]

  [ -f "$REC" ]
  run jq -r -s 'length' "$REC"
  [ "$output" = "1" ]
  run jq -r '[.event, .class, .action, .outcome, (.attempt_n|tostring)] | join("|")' "$REC"
  [ "$output" = "recovery_attempt|GATE_TIMEOUT|rerun_targeted|started|1" ]
  run jq -r 'has("ts")' "$REC"
  [ "$output" = "true" ]

  # the caller reports back; the outcome line never consumes budget
  run ladder aid_ladder_outcome "$EVID" GATE_TIMEOUT rerun_targeted 1 failed
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run jq -r -s '[.[] | select(.event=="recovery_outcome")] | length' "$REC"
  [ "$output" = "1" ]

  # BUDGETS ARE PER CLASS: a second class in the same run has its own thread,
  # and every line names its own class so both stay legible.
  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "proceed 1" ]
  run jq -r -s '[.[] | .class] | unique | join(",")' "$REC"
  [ "$output" = "GATE_TIMEOUT,TRANSIENT_INFRA" ]
}

@test "case 2: the budget-th + 1 attempt refuses with budget_exhausted and the adjudicate signal" {
  # GATE_TIMEOUT ships attempts: 1. The first attempt is granted...
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 0 ]
  [ "$output" = "proceed 1" ]

  # ...and the second is not, in the same second, so the wall clock is not what
  # refused it.
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [ "$output" = "adjudicate budget_exhausted" ]

  # The refusal is RECORDED, and it did not spend an attempt of its own.
  run jq -r -s '[.[] | .outcome] | join(",")' "$REC"
  [ "$output" = "started,budget_exhausted" ]
  run jq -r -s '.[1].detail' "$REC"
  [[ "$output" == *"spent 1 of 1 attempts"* ]] || { echo "$output"; false; }

  # TRANSIENT_INFRA ships attempts: 3 — the boundary is the declared number,
  # not a constant in the lib.
  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$output" = "proceed 1" ]
  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$output" = "proceed 2" ]
  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$output" = "proceed 3" ]
  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$status" -eq 4 ]
  [ "$output" = "adjudicate budget_exhausted" ]
}

@test "case 3: an action the class does not allow is refused, and the refusal names it" {
  # `restart_service_once` is a real vocabulary action — but not one GATE_TIMEOUT
  # is allowed to take. Membership of the vocabulary is not membership of the
  # class's allowlist.
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT restart_service_once
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [ "$output" = "adjudicate refused_action_not_allowed" ]
  run jq -r '.detail' "$REC"
  [ "$output" = "action 'restart_service_once' is not in allowed_actions for class GATE_TIMEOUT" ]

  # An action outside the vocabulary entirely is refused the same way, and no
  # attempt was spent by either refusal.
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT waive_gate
  [ "$status" -eq 4 ]
  [ "$output" = "adjudicate refused_action_not_allowed" ]
  run jq -r -s '[.[] | select(.outcome=="started")] | length' "$REC"
  [ "$output" = "0" ]

  # And REVIEW_EXHAUSTED, whose allowlist is empty by policy, can take nothing
  # at all — every action is refused for it.
  run ladder aid_ladder_attempt "$EVID" REVIEW_EXHAUSTED collect_and_continue
  [ "$status" -eq 4 ]
  [ "$output" = "adjudicate refused_action_not_allowed" ]

  # An undeclared class routes to adjudication rather than inventing a budget.
  run ladder aid_ladder_attempt "$EVID" TOTALLY_MADE_UP rerun_targeted
  [ "$status" -eq 4 ]
  [ "$output" = "adjudicate refused_unknown_class" ]
}

@test "case 4: the wall clock refuses even with attempts remaining" {
  # TRANSIENT_INFRA: attempts 3, wall_clock_seconds 3600. One attempt spent,
  # two remaining — but the class was first seen two hours ago.
  local old
  old="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  seed_record "$(attempt_line TRANSIENT_INFRA retry_once started 1 "$old")"

  run ladder aid_ladder_attempt "$EVID" TRANSIENT_INFRA retry_once
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [ "$output" = "adjudicate wall_clock_exhausted" ]
  run jq -r -s '.[-1].detail' "$REC"
  [[ "$output" == *"wall_clock_seconds budget is 3600"* ]] || { echo "$output"; false; }
  [[ "$output" == *"attempts used 1 of 3"* ]] || { echo "$output"; false; }

  # The clock runs from the class's FIRST line — which an EMITTER line can be,
  # not only an attempt: the budget starts when the stop was first seen.
  rm -f "$REC"
  seed_record "$(jq -nc --arg ts "$old" '{ts:$ts, event:"recovery_stop", class:"JOB_LOST", outcome:"detected", auto:true}')"
  run ladder aid_ladder_attempt "$EVID" JOB_LOST collect_and_continue
  [ "$status" -eq 4 ]
  [ "$output" = "adjudicate wall_clock_exhausted" ]

  # ...and it is per class: GATE_TIMEOUT's own clock has not started.
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "proceed 1" ]
}

@test "case 5: A/B — the GATE_TIMEOUT emitter records, and the gate verdict is byte-identical without it" {
  # THE INVARIANCE PROOF. Not "the row still looks right" — the SAME runner is
  # run twice over the SAME fixture, once with lib/aid-recovery-ladder.sh
  # present and once with it absent from an otherwise identical copy of the
  # plugin, and the two normalized gates reports are diffed. Anything the ladder
  # changed about the verdict would show up here.
  local ladder_report noladder_report

  _timeout_fixture() { # _timeout_fixture <root>
    local root="$1"
    mkdir -p "$root/$EVID_REL/gates"
    init_git_project "$root"
    cat > "$root/exec.yaml" <<'YAML'
gates:
  slow:
    command: "sleep 60"
    required: false
    timeout_seconds: 2
    max_retries: 2
    run_mode: background
YAML
  }

  # ── A: the shipped runner, ladder present ────────────────────────────────
  local a="$WORK/a"
  mkdir -p "$a"
  _timeout_fixture "$a"
  ( cd "$a" && AID_GATE_BASELINE_FILE="$WORK/baseline-a.yaml" \
      "$RUN_GATES" run-all exec.yaml E-LAD-1 R-1 \
      --report-file "$EVID_REL/gates/gates_report.json" >"$WORK/a.out" 2>"$WORK/a.err" )
  ladder_report="$a/$EVID_REL/gates/gates_report.json"
  [ -f "$ladder_report" ] || { cat "$WORK/a.err"; false; }

  # the ladder entry really was written, by the emitter this case is about
  local arec="$a/$EVID_REL/recovery-ladder.jsonl"
  [ -f "$arec" ] || { echo "no ladder record"; ls -la "$a/$EVID_REL"; false; }
  run jq -r -s '[.[] | select(.class=="GATE_TIMEOUT" and .emitter=="timeout_policy_block")] | length' "$arec"
  [ "$output" -ge 1 ] || { cat "$arec"; false; }
  run jq -r -s '.[0] | [.event, .class, .outcome] | join("|")' "$arec"
  [ "$output" = "recovery_stop|GATE_TIMEOUT|detected" ]

  # ── B: the same runner from a plugin copy with the ladder lib REMOVED ─────
  local plug="$WORK/plugin-noladder"
  mkdir -p "$plug"
  cp -a "$PLUGIN_ROOT/defaults" "$plug/defaults"
  mkdir -p "$plug/scripts"
  ( cd "$PLUGIN_ROOT/scripts" && tar cf - --exclude=tests . ) | ( cd "$plug/scripts" && tar xf - )
  rm -f "$plug/scripts/lib/aid-recovery-ladder.sh"
  [ ! -f "$plug/scripts/lib/aid-recovery-ladder.sh" ]

  local b="$WORK/b"
  mkdir -p "$b"
  _timeout_fixture "$b"
  ( cd "$b" && AID_GATE_BASELINE_FILE="$WORK/baseline-b.yaml" \
      "$plug/scripts/aid-run-gates.sh" run-all exec.yaml E-LAD-1 R-1 \
      --report-file "$EVID_REL/gates/gates_report.json" >"$WORK/b.out" 2>"$WORK/b.err" )
  noladder_report="$b/$EVID_REL/gates/gates_report.json"
  [ -f "$noladder_report" ] || { cat "$WORK/b.err"; false; }
  [ ! -f "$b/$EVID_REL/recovery-ladder.jsonl" ]

  # ── THE DIFF ─────────────────────────────────────────────────────────────
  normalize_report "$ladder_report"   > "$WORK/a.json"
  normalize_report "$noladder_report" > "$WORK/b.json"
  run diff -u "$WORK/b.json" "$WORK/a.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  # and, said explicitly, the verdict this fixture exists to protect
  run jq -r '[.gates.slow.result, (.gates.slow.exit_code|tostring), .gates.slow.reason,
              (.gates.slow.runtime_baseline.samples_count|tostring),
              (.gates.slow.runtime_baseline.non_censored_samples_count|tostring)] | join("|")' "$ladder_report"
  [ "$output" = "fail|124|timeout_policy_block|3|0" ] || { echo "$output"; false; }
}

@test "case 6: escalate lands blocked_for_pm, and leaving ESCALATION still needs the decision field" {
  export AID_PROJECT_ROOT="$PROJ"
  init_git_project "$PROJ"
  mkdir -p "$PROJ/.aid-o/work"
  jq -n '{"E-LAD-1":{run_id:"R-1", state:"GATES", branch:"task/E-LAD-1/main",
                     auto_controller:"active", resume_artifact:null,
                     updated_at:"2026-08-09T00:00:00Z"}}' \
    > "$PROJ/.aid-o/work/active-runs.json"
  printf 'epic_id: E-LAD-1\nrun_id: R-1\nstate: ESCALATION\n' > "$EVID/fsm-state.yaml"

  run bash -c 'set -euo pipefail; cd "$PROJ"; source "$LIB"; aid_ladder_escalate "$EVID" GATE_TIMEOUT'
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  # the map now says a person owns this run — through aid-fsm.sh's ONE writer
  run jq -r '.["E-LAD-1"].auto_controller' "$PROJ/.aid-o/work/active-runs.json"
  [ "$output" = "blocked_for_pm" ]
  # and the terminus is in the record
  run jq -r -s '[.[] | select(.event=="recovery_terminus")] | .[0] | [.class, .outcome] | join("|")' "$REC"
  [ "$output" = "GATE_TIMEOUT|escalated" ]

  # REGRESSION — the ladder did NOT make ESCALATION leavable. The transition
  # still refuses without escalation_decision.
  run bash -c 'cd "$PROJ" && bash "$FSM" transition ESCALATION GATES "'"$EVID"'/fsm-state.yaml"'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"escalation_decision"* ]] || { echo "$output"; false; }

  # ...and the ladder ships no function that continues past a refused terminal
  # state. Continuation is the audited PM `--force` surface, and nothing else.
  # (comment lines excluded: the header DESCRIBES the force surface at length,
  # which is the point — the CODE must not reach for it.)
  run bash -c 'grep -vE "^[[:space:]]*#" "$LIB" | grep -nE "\-\-force|--blocked-checks|increment-step"'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "case 7: the reader honours revoked_unrecorded — a revoked decision is never returned" {
  # The adjudication lib appends the ladder line BEFORE the timeline line and
  # revokes it if the timeline append then fails; that compensating append is
  # itself best-effort, so a bare `accepted` can outlive an outcome nobody
  # returned. A "last accepted wins" reader would hand back a revoked action.
  seed_record \
    "$(jq -nc '{ts:"2026-08-09T10:00:00Z", event:"recovery_adjudication", class:"GATE_TIMEOUT",
                action:"collect_and_continue", verdict:"accepted", attempt:1}')" \
    "$(jq -nc '{ts:"2026-08-09T10:00:05Z", event:"recovery_adjudication", class:"GATE_TIMEOUT",
                action:"rerun_targeted", verdict:"accepted", attempt:2}')" \
    "$(jq -nc '{ts:"2026-08-09T10:00:06Z", event:"recovery_adjudication", class:"GATE_TIMEOUT",
                action:"escalate", verdict:"revoked_unrecorded", attempt:2}')"

  # the naive query returns the revoked one — pinned here so the difference is
  # a demonstrated fact rather than an assertion in a comment
  run jq -r -s '[.[] | select(.verdict=="accepted")] | last | .action' "$REC"
  [ "$output" = "rerun_targeted" ]

  # the ladder's reader does not
  run ladder aid_ladder_last_accepted_action "$EVID" GATE_TIMEOUT
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "collect_and_continue" ]

  # revoke the survivor too and there is nothing to return at all
  seed_record "$(jq -nc '{ts:"2026-08-09T10:00:07Z", event:"recovery_adjudication", class:"GATE_TIMEOUT",
                          action:"escalate", verdict:"revoked_unrecorded", attempt:1}')"
  run ladder aid_ladder_last_accepted_action "$EVID" GATE_TIMEOUT
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }

  # another class's accepted decision is not borrowed
  run ladder aid_ladder_last_accepted_action "$EVID" JOB_LOST
  [ -z "$output" ]
}

@test "case 8: the other two mechanical emitters write from real code paths" {
  # ── JOB_LOST: a supervised gate job whose process group is SIGKILLed leaves
  #    no terminal record, so the runner maps it to the `job_lost` row — and
  #    that mapping is where the ladder entry is written.
  local j="$WORK/j"
  mkdir -p "$j/$EVID_REL/gates"
  init_git_project "$j"
  cat > "$j/exec.yaml" <<'YAML'
gates:
  vanish:
    command: "sleep 120"
    required: false
    timeout_seconds: 120
    max_retries: 0
    run_mode: background
YAML
  ( cd "$j" && AID_GATE_BASELINE_FILE="$WORK/baseline-j.yaml" \
      "$RUN_GATES" run-all exec.yaml E-LAD-1 R-1 \
      --report-file "$EVID_REL/gates/gates_report.json" >"$WORK/j.out" 2>"$WORK/j.err" ) &
  BG_PID=$!

  local i pgid="" jd="$j/$EVID_REL/jobs"
  for i in $(seq 1 200); do
    pgid="$(jq -r '.pgid // empty' "$jd"/*/job.json 2>/dev/null | head -1 || true)"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && break
    sleep 0.1
  done
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || { echo "no job pgid appeared"; cat "$WORK/j.err"; false; }
  kill -KILL -"$pgid" 2>/dev/null || true
  wait "$BG_PID" 2>/dev/null || true
  BG_PID=""

  run jq -r '.gates.vanish.reason' "$j/$EVID_REL/gates/gates_report.json"
  [ "$output" = "job_lost" ] || { cat "$WORK/j.err"; false; }
  run jq -r '.gates.vanish.result' "$j/$EVID_REL/gates/gates_report.json"
  [ "$output" = "fail" ]
  run jq -r -s '[.[] | select(.class=="JOB_LOST" and .emitter=="gate_job_lost")] | length' \
    "$j/$EVID_REL/recovery-ladder.jsonl"
  [ "$output" = "1" ] || { cat "$j/$EVID_REL/recovery-ladder.jsonl"; false; }

  # ── SERVICE_UNHEALTHY: a declared service whose probe never passes exhausts
  #    what its declaration authorised. The registry verdict and rc are the
  #    same; the ladder entry is additive.
  local s="$WORK/s"
  mkdir -p "$s/$EVID_REL"
  cat > "$s/exec.yaml" <<'YAML'
services:
  api:
    start_cmd: "sleep 30"
    probe_cmd: "false"
    startup_deadline_seconds: 2
YAML
  run bash -c 'set -euo pipefail
    cd "'"$s"'"
    source "$PLUGIN_ROOT/scripts/lib/aid-service.sh"
    aid_service_up_all "'"$s/$EVID_REL"'" "'"$s"'/exec.yaml"'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  run jq -r '.services.api.state // .api.state // empty' "$s/$EVID_REL/services.json"
  [ -n "$output" ] || { cat "$s/$EVID_REL/services.json"; false; }
  run jq -r -s '[.[] | select(.class=="SERVICE_UNHEALTHY" and .emitter=="service_restart_exhausted")] | length' \
    "$s/$EVID_REL/recovery-ladder.jsonl"
  [ "$output" = "1" ] || { cat "$s/$EVID_REL/recovery-ladder.jsonl" 2>/dev/null || echo "(no record)"; false; }
}

@test "case 9: the closed sets are lib == policy == schema, and the loader is where the contract says" {
  # The lib compiles the six action names and the seven class names as literals
  # on purpose (the policy is the thing being bounded). That only stays safe
  # while the three agree, so the agreement is pinned rather than assumed.
  local lib_actions policy_actions schema_actions
  lib_actions="$(bash -c 'source "$LIB"; _aid_ladder_action_constants' | LC_ALL=C sort | tr '\n' ',')"
  policy_actions="$(yq -r '.action_vocabulary | keys | .[]' "$POLICY" | LC_ALL=C sort | tr '\n' ',')"
  schema_actions="$(jq -r '.["$defs"].allowed_actions.items.enum[]' "$SCHEMA" | LC_ALL=C sort | tr '\n' ',')"
  [ "$lib_actions" = "$policy_actions" ] || { echo "lib=$lib_actions policy=$policy_actions"; false; }
  [ "$lib_actions" = "$schema_actions" ] || { echo "lib=$lib_actions schema=$schema_actions"; false; }

  local lib_classes policy_classes schema_classes
  lib_classes="$(bash -c 'source "$LIB"; _aid_ladder_class_constants' | LC_ALL=C sort | tr '\n' ',')"
  policy_classes="$(yq -r '.stop_classes | keys | .[]' "$POLICY" | LC_ALL=C sort | tr '\n' ',')"
  schema_classes="$(jq -r '.properties.stop_classes.required[]' "$SCHEMA" | LC_ALL=C sort | tr '\n' ',')"
  [ "$lib_classes" = "$policy_classes" ] || { echo "lib=$lib_classes policy=$policy_classes"; false; }
  [ "$lib_classes" = "$schema_classes" ] || { echo "lib=$lib_classes schema=$schema_classes"; false; }

  # The loader's PATH and NAME are not free choices — auto-recovery.yaml's
  # loader_contract declares both, and test-auto-recovery-policy.bats derives
  # "is the ladder wired" from them. Renaming either without editing the policy
  # is a lie in one direction or the other.
  local lp la
  lp="$(yq -r '.loader_contract.loader_path' "$POLICY")"
  la="$(yq -r '.loader_contract.loader_anchor' "$POLICY")"
  [ "$lp" = "plugins/aid-orchestrator/scripts/lib/aid-recovery-ladder.sh" ]
  [ "$REPO_ROOT/$lp" = "$LIB" ]
  grep -qE "^${la}\(\)" "$LIB" || { echo "no ${la}() in $LIB"; false; }
  grep -qF 'auto-recovery.yaml' "$LIB"

  # ...and the loader really resolves the shipped policy.
  run ladder aid_recovery_policy_load
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$POLICY" ]

  # A project override is used when it is usable, and REFUSED-with-fallback
  # when it is not — never silently accepted (loader_contract.malformed_override).
  mkdir -p "$PROJ/.aid-o/config/policies"
  cp "$POLICY" "$PROJ/.aid-o/config/policies/auto-recovery.yaml"
  run bash -c 'set -euo pipefail; cd "$PROJ"; source "$LIB"; AID_PROJECT_ROOT="$PROJ" aid_recovery_policy_load'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$PROJ/.aid-o/config/policies/auto-recovery.yaml" ]

  yq -i '.stop_classes.GATE_TIMEOUT.terminus = ["pm_force","adjudicate","escalation"]' \
    "$PROJ/.aid-o/config/policies/auto-recovery.yaml"
  run bash -c 'set -euo pipefail; cd "$PROJ"; source "$LIB"; AID_PROJECT_ROOT="$PROJ" aid_recovery_policy_load'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[-1]}" = "$POLICY" ] || { echo "$output"; false; }
  [[ "$output" == *"terminus other than adjudicate>escalation>pm_force"* ]] || { echo "$output"; false; }

  # The policy is PROJECT-scoped: a per-plan override is refused BY NAME.
  run bash -c 'set -euo pipefail; source "$LIB"; AID_RECOVERY_POLICY_PER_PLAN=1 aid_recovery_policy_load'
  [ "$status" -eq 3 ]
  [[ "$output" == *"PROJECT-scoped"* ]] || { echo "$output"; false; }
}

@test "case 10: two concurrent attempts of a 1-attempt class spend it exactly once" {
  # The TOCTOU the single critical section closes: counting outside the lock let
  # both racers read "0 used" and both write a `started` line.
  local i
  for i in 1 2 3 4 5 6; do
    ( ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted > "$WORK/out-$i" 2>/dev/null ) &
  done
  wait

  run jq -r -s '[.[] | select(.outcome=="started")] | length' "$REC"
  [ "$output" = "1" ] || { cat "$REC"; false; }
  run jq -r -s '[.[] | select(.outcome=="budget_exhausted")] | length' "$REC"
  [ "$output" = "5" ] || { cat "$REC"; false; }
  # every line is still one whole JSON object — no interleaved partial write
  run jq -r -s 'length' "$REC"
  [ "$output" = "6" ]
  # exactly one racer was told to proceed
  run bash -c 'cat "$WORK"/out-* | grep -c "^proceed 1$"'
  [ "$output" = "1" ]
}

@test "case 11: fail closed — an unreadable policy adjudicates, it never permits a retry" {
  printf 'this: is: not: valid: yaml: [\n' > "$WORK/broken.yaml"
  run bash -c 'set -euo pipefail; source "$LIB"; AID_RECOVERY_POLICY="'"$WORK"'/broken.yaml" aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted'
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [ "${lines[-1]}" = "adjudicate refused_policy_unreadable" ]
  run jq -r '.outcome' "$REC"
  [ "$output" = "refused_policy_unreadable" ]

  # A policy that declares an action outside the vocabulary is a load-time
  # refusal too, not a permission.
  local p="$WORK/bad-vocab.yaml"
  cp "$POLICY" "$p"
  yq -i '.stop_classes.GATE_TIMEOUT.allowed_actions = ["waive_gate"]' "$p"
  rm -f "$REC"
  run bash -c 'set -euo pipefail; source "$LIB"; AID_RECOVERY_POLICY="'"$p"'" aid_ladder_attempt "$EVID" GATE_TIMEOUT waive_gate'
  [ "$status" -eq 4 ]
  [ "${lines[-1]}" = "adjudicate refused_policy_unreadable" ]

  # A missing evidence directory is refused rather than created — the ladder
  # writes into evidence, it never invents it.
  run bash -c 'set -euo pipefail; source "$LIB"; aid_ladder_attempt "'"$WORK"'/nope" GATE_TIMEOUT rerun_targeted'
  [ "$status" -eq 4 ]
  [ "${lines[-1]}" = "adjudicate unrecordable" ]
  [ ! -d "$WORK/nope" ]

  # An unparseable RECORD is refused too: with the spent budget unknown, "no
  # attempts used" is the one answer that must not be assumed.
  printf 'not json at all\n' > "$REC"
  run ladder aid_ladder_attempt "$EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 4 ]
  [ "${lines[-1]}" = "adjudicate refused_unreadable_record" ]
}

@test "case 12: the ladder cannot smuggle restart authority" {
  # The ladder GRANTS `restart_service_once` for SERVICE_UNHEALTHY...
  run ladder aid_ladder_attempt "$EVID" SERVICE_UNHEALTHY restart_service_once
  [ "$status" -eq 0 ]
  [ "$output" = "proceed 1" ]

  # ...and executes nothing. There is no process control in this file at all:
  # no supervisor invocation, no signal, no session/process-group arithmetic.
  run grep -nE '\b(setsid|kill|pkill|nohup|disown)\b|aid-job\.sh|start_cmd|aid_service_up' "$LIB"
  [ "$status" -ne 0 ] || { echo "$output"; false; }

  # So the only code that can restart a service is aid-service's own path, and
  # that path still spends its ONE restart only when the DECLARATION authorises
  # it and only once — which is what makes the grant above unable to exceed it.
  run grep -cE '^[[:space:]]*if \[\[ "\$restart_auth" == "true" \]\] && \(\( restart_used == 0 \)\); then$' \
    "$PLUGIN_ROOT/scripts/lib/aid-service.sh"
  [ "$output" = "1" ] || { echo "the one-restart gate in aid-service.sh has moved or changed"; false; }
}

@test "case 13: the terminus the ladder READS cannot be reordered behind a broken validator" {
  # THE STEP-12 CARRIED OBLIGATION (AC4). The adjudication lib's JSON Schema
  # check is optional equipment: it is skipped when python3 is missing AND when
  # python3 is BROKEN. Under that skip, an invented stop class and a
  # `pm_force`-first terminus were both accepted. The ACTIONS stayed inside the
  # six either way — but THIS lib reads `terminus`, so the reorder mattered to
  # the one consumer that acts on it. Both are now structural bash+yq refusals,
  # which nothing can skip.
  local broken="$WORK/bin"
  mkdir -p "$broken"
  printf '#!/bin/sh\nexit 127\n' > "$broken/python3"
  chmod +x "$broken/python3"

  local ev="$WORK/adj-evidence"
  mkdir -p "$ev"
  printf 'gate bats_unit blew its deadline.\n' > "$ev/facts.md"

  _adj() { # _adj <policy> <class>
    PATH="$broken:$PATH" bash -c '
      set -euo pipefail
      source "$PLUGIN_ROOT/scripts/lib/aid-recovery-adjudicate.sh"
      _run_codex_isolated() { printf "ACTION: rerun_targeted\nRATIONALE: x\n" > "$5"; return 0; }
      AID_RECOVERY_POLICY="'"$1"'" aid_recovery_adjudicate "'"$ev"'" "'"$2"'" "'"$ev"'/facts.md"'
  }

  # the broken interpreter really is what the lib would reach for
  run bash -c 'PATH="'"$broken"':$PATH" python3 -c "import jsonschema"'
  [ "$status" -ne 0 ]

  # (a) a reordered terminus — refused, and the record says why
  local p1="$WORK/pol-terminus.yaml"
  cp "$POLICY" "$p1"
  yq -i '.stop_classes.GATE_TIMEOUT.terminus = ["pm_force","adjudicate","escalation"]' "$p1"
  run _adj "$p1" GATE_TIMEOUT
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "${lines[-1]}" = "escalate" ]
  run jq -r -s '[.[] | .verdict] | unique | join(",")' "$ev/timeline.jsonl"
  [ "$output" = "refused_invalid_policy" ] || { cat "$ev/timeline.jsonl"; false; }

  # (b) an invented stop class in the policy — refused before any dispatch
  rm -f "$ev/timeline.jsonl" "$ev/recovery-ladder.jsonl"
  local p2="$WORK/pol-class.yaml"
  cp "$POLICY" "$p2"
  yq -i '.stop_classes.ATTACKER_CLASS = .stop_classes.GATE_TIMEOUT' "$p2"
  run _adj "$p2" ATTACKER_CLASS
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "${lines[-1]}" = "escalate" ]
  run jq -r -s '[.[] | .verdict] | unique | join(",")' "$ev/timeline.jsonl"
  [ "$output" = "refused_invalid_policy" ]

  # (c) and the ladder itself refuses the same two policies, for the same
  #     reasons — it never inherits a terminus the adjudicator would not accept
  run bash -c 'set -euo pipefail; source "$LIB"; AID_RECOVERY_POLICY="'"$p1"'" aid_recovery_policy_load'
  [ "$status" -eq 3 ]
  [[ "$output" == *"terminus other than adjudicate>escalation>pm_force"* ]] || { echo "$output"; false; }
  run bash -c 'set -euo pipefail; source "$LIB"; AID_RECOVERY_POLICY="'"$p2"'" aid_recovery_policy_load'
  [ "$status" -eq 3 ]
  [[ "$output" == *"closed set of seven"* ]] || { echo "$output"; false; }
}

@test "case 14: the DISPATCH_ORPHANED die names the ladder entry command, and the checklist names the instruction classes" {
  # DISPATCH_ORPHANED is `ladder_entry: instruction` — no code writes its entry,
  # so what has to be true is that the die MESSAGE names the command that does.
  # Asserted against the real function's real output, not against its source.
  local ev="$WORK/orphan"
  mkdir -p "$ev"
  local old
  old="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  jq -nc --arg ts "$old" \
    '{event:"start", focus:"step-3-verify", ts:$ts, expected_duration_max:60}' \
    > "$ev/pending-dispatches.jsonl"

  run bash -c 'set -euo pipefail; source "$FSM"; fsm_check_orphan_dispatches "'"$ev"'"'
  [ "$status" -ne 0 ] || { echo "$output"; false; }

  # the refusal itself is UNCHANGED — same headline, same fix command, same
  # audited PM override
  [[ "$output" == *"Orphan dispatch(es) detected — cannot advance step."* ]] || { echo "$output"; false; }
  [[ "$output" == *"aid-emit-dispatch.sh complete"* ]]
  [[ "$output" == *"--blocked-checks 'dispatch_orphan_complete'"* ]]

  # ...and it now also names the ladder entry, by class and by command
  [[ "$output" == *"DISPATCH_ORPHANED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"aid_ladder_emit"* ]] || { echo "$output"; false; }
  [[ "$output" == *"lib/aid-recovery-ladder.sh"* ]]

  # and the AUTO-loop checklist really carries every instruction-routed class,
  # which is the only place their entry can come from
  local md="$PLUGIN_ROOT/skills/pipeline.md"
  local block c
  block="$(awk '/AUTO-loop ladder checklist/,/^Test evidence is immutable/' "$md")"
  [[ -n "$block" ]] || { echo "no AUTO-loop ladder checklist in pipeline.md"; false; }
  for c in TRANSIENT_INFRA DISPATCH_ORPHANED REVIEW_EXHAUSTED UNCLASSIFIED; do
    [[ "$block" == *"$c"* ]] || { echo "checklist does not name $c"; false; }
  done
  # every class the policy marks `ladder_entry: instruction` is in that list —
  # derived from the policy, so a new instruction class cannot be forgotten
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    [[ "$block" == *"$c"* ]] || { echo "policy declares ${c} as instruction-routed, the checklist does not name it"; false; }
  done < <(yq -r '.stop_classes | to_entries[] | select(.value.ladder_entry == "instruction") | .key' "$POLICY")
  [[ "$block" == *"aid_ladder_attempt"* ]]
  [[ "$block" == *"aid_recovery_adjudicate"* ]]
  [[ "$block" == *"aid_ladder_escalate"* ]]
}
