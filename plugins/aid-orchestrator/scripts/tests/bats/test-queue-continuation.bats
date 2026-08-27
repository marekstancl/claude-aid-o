#!/usr/bin/env bats
# aid-tier: t0
# test-queue-continuation.bats — P090 Step 5.
#
# The reminder. It is degree 3 and the cases below say so out loud, because the
# risk this rule carries is not that it fails — it is that somebody reads it as
# a guarantee. `aid-hook.sh` strips any refusal from a Stop rule the moment the
# harness reports `stop_hook_active`, so a barrier built here would hold exactly
# once. What it does instead: it names what is left, and it never touches the
# queue.

load test-helpers.bash
load p090-fixture.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  HOOK="$AID_PLUGIN_PATH/scripts/aid-hook.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-queue-continuation.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/repo"
  p090_mk_workspace "$ROOT"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  export AID_HOOK_AUDIT="$TMP/audit.jsonl" AID_SESSION_STORE="$TMP/store"
}
teardown() { rm -rf "$TMP"; }

_plan() { p090_plan_state "$ROOT" "$1" "$2" "${3:-OPEN}"; }

_event() { jq -n --arg c "$ROOT" '{session_id:"s",cwd:$c,stop_hook_active:false}'; }

_queue_ready() { p090_queue "$QUEUE" P090 "E-090-2_2:pending"; }

@test "AC13: a plan with a ready EPIC is named — and the queue is byte-identical afterwards" {
  _plan P090 auto
  _queue_ready
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090 (OPEN): E-090-2_2 is ready to be claimed"* ]]
  [[ "$output" == *"cannot stop a turn"* ]]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]

  # The proof that it asked rather than took: `claim-next` would have written
  # `running`, `peek-next` writes nothing.
  [ "$(bash "$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh" get E-090-2_2 status --queue "$QUEUE" --project-root "$ROOT")" = "pending" ]
  grep -q 'peek-next' "$AID_PLUGIN_PATH/scripts/lib/aid-queue-continuation.sh"
  # …and no line of CODE mentions claim-next. (The comment that explains why
  # does, which is why this strips comments rather than grepping the file.)
  run bash -c 'grep -v "^[[:space:]]*#" "$1" | grep -c "claim-next" || true' _       "$AID_PLUGIN_PATH/scripts/lib/aid-queue-continuation.sh"
  [ "$output" = "0" ]
}

@test "AC13: an exhausted plan is named too, with the closing it still owes" {
  _plan P090 auto
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: merged_to_plan
    plan_id: "P090"
    depends_on: []
YAML
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"every EPIC is accounted for"* ]]
  [[ "$output" == *"plan-close"* ]]
}

@test "AC13: a blocked queue says what is being waited on" {
  _plan P090 auto
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: ["E-090-1_2"]
YAML
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"blocked:E-090-2_2:dependency_unmerged:E-090-1_2"* ]]
}

@test "AC14: a manual plan is silent, and a manual turn is not held up by somebody else's autonomous plan" {
  _plan P090 manual
  _queue_ready
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no open autonomous plan"* ]]

  # A plan with no `autonomy` field at all — every plan created before P090 —
  # reads as manual. Fail-closed: the cost of the other direction is a plan
  # continuing itself when nobody asked.
  sed -i '/^autonomy:/d' "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 3 ]
}

@test "AC14: two plans, one autonomous and one manual — only the autonomous one is named" {
  _plan P090 auto
  _plan P091 manual
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: []

  - epic_id: E-091-2_2
    status: pending
    plan_id: "P091"
    depends_on: []
YAML
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090"* ]]
  [[ "$output" != *"P091"* ]]
}

@test "two autonomous plans are BOTH named — nothing is blocked, so silence about one would be the only mistake" {
  _plan P090 auto
  _plan P091 auto
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: []

  - epic_id: E-091-2_2
    status: pending
    plan_id: "P091"
    depends_on: []
YAML
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090 (OPEN): E-090-2_2"* ]]
  [[ "$output" == *"P091 (OPEN): E-091-2_2"* ]]
}

@test "a closed plan owes nothing and is not mentioned" {
  _plan P090 auto CLOSED
  _queue_ready
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 3 ]
}

@test "a queue it cannot read makes the rule SILENT, and the reason is recorded" {
  # Step 5's error handling, and the right call: this rule speaks into a
  # prompt, and a reminder built on "I do not know" is noise that teaches a
  # reader to skim past the ones that mean something. Silence is not a claim
  # that the plan is finished — nothing is claimed at all — and the reason
  # still goes on stderr where an operator and the audit log find it.
  _plan P090 auto
  _queue_ready
  : > "${QUEUE}.lock"
  flock -x "${QUEUE}.lock" -c 'sleep 5' &
  local holder=$!
  sleep 0.3
  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=1 run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  # 3 == "not applicable": there was nothing it could truthfully say.
  [ "$status" -eq 3 ]
  [[ "$output" != *"every EPIC is accounted for"* ]]
  [[ "$output" != *"is ready to be claimed"* ]]
  # …and it said WHY, rather than going quiet without a trace.
  [[ "$output" == *"could not be read"* ]]
}

@test "a guidance copied from ANOTHER plan is not read as this plan's" {
  # Same failure the continuation script was hardened against: the schema name
  # alone is not enough, because a file carrying another plan's in-flight EPIC
  # would be announced as this one's.
  _plan P090 auto
  _queue_ready
  mkdir -p "$ROOT/.aid-o/work/evidence/P090"
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P091", last_completed_epic:"E-091-1_2",
          last_result:"E-091-2_2", next_epic:"E-091-2_2", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:0}' \
     > "$ROOT/.aid-o/work/evidence/P090/continue-state.json"

  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"E-090-2_2 is ready to be claimed"* ]]
  [[ "$output" != *"E-091-2_2"* ]]
  [[ "$output" != *"in flight"* ]]
}

@test "AC13b: on SessionStart the guidance an interrupted run left is read back, with what the queue has next" {
  # The event that actually rescues a lost chain: after a controller dies the
  # `epic-merge-to-plan` that would have continued the plan never happens, so
  # this is the only reader the guidance has.
  _plan P090 auto
  _queue_ready
  mkdir -p "$ROOT/.aid-o/work/evidence/P090"
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P090", last_completed_epic:"E-090-1_2",
          last_result:"E-090-2_2", next_epic:"E-090-2_2", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:0}' \
     > "$ROOT/.aid-o/work/evidence/P090/continue-state.json"

  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"from an earlier session is still open"* ]]
  [[ "$output" == *"The last continuation left E-090-2_2 in flight"* ]]
  [[ "$output" == *"E-090-2_2 is ready to be claimed"* ]]
  [[ "$output" == *"aid-plan-continue.sh <plan_id>"* ]]
}

@test "no AID workspace, or no cwd at all, is 'not applicable' — never an opinion" {
  run aid_hook_rule_queue_continuation_stop <<< '{"session_id":"s"}'
  [ "$status" -eq 3 ]
  run aid_hook_rule_queue_continuation_start <<< '{"session_id":"s"}'
  [ "$status" -eq 3 ]
}

@test "AC15: through the real dispatcher the rule SPEAKS on stop_hook_active and never blocks" {
  # Both halves, because the plan's whole argument for degree 3 rests on them:
  # the message is still delivered, and the exit code never stops the turn —
  # even with a canary verdict present, which is what lets other rules refuse.
  _plan P090 auto
  _queue_ready
  mkdir -p "$TMP/store/hooks"
  printf '{"verified":true,"tool":"bats","version":"fixture","checked_at":"%s"}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/store/hooks/trust.json"

  run bash "$HOOK" Stop <<< "$(_event | jq '.stop_hook_active = true')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"E-090-2_2"* ]]

  # …and without the flag it is still 0: this rule has no refusal to strip.
  run bash "$HOOK" Stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"E-090-2_2"* ]]
}

@test "the registry declares both rows at degree 3 and failure: open" {
  # `failure: open` is the declaration that a rule may not stop a turn; a row
  # saying `closed` here would be a promise this rule cannot keep.
  local reg="$AID_PLUGIN_PATH/defaults/hook-registry.yaml"
  run yq -r '.rules[] | select(.id == "queue_continuation_notice") | "\(.event) \(.degree) \(.failure) \(.owner) \(.handler)"' "$reg"
  [ "$output" = "Stop 3 open controller aid_hook_rule_queue_continuation_stop" ]
  run yq -r '.rules[] | select(.id == "queue_continuation_resume") | "\(.event) \(.degree) \(.failure) \(.owner) \(.handler)"' "$reg"
  [ "$output" = "SessionStart 3 open controller aid_hook_rule_queue_continuation_start" ]
}
