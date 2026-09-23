#!/usr/bin/env bats
# aid-tier: t0
# test-queue-continuation.bats — P090 Step 5, P099 Step 5.
#
# SessionStart names what an autonomous plan has left, and never touches the
# queue. Stop keeps the session that drives an autonomous plan working: it
# refuses a turn that ends with work left, up to a budget the PM's reply
# resets, and lets it end on a card, on a declared wait for a live background
# job, or at the budget — the last two cases with one "agent is waiting"
# message.

load test-helpers.bash
load p090-fixture.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  HOOK="$AID_PLUGIN_PATH/scripts/aid-hook.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-queue-continuation.sh"
  TMP="$(mktemp -d)"
  # Each case gets its own session store: the rule remembers what it has
  # already said (per session at Stop, per workspace at SessionStart), so a
  # shared store would let one case silence the next.
  export AID_SESSION_STORE="$TMP/session-store"
  ROOT="$TMP/repo"
  p090_mk_workspace "$ROOT"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  export AID_HOOK_AUDIT="$TMP/audit.jsonl" AID_SESSION_STORE="$TMP/store"
}
teardown() { rm -rf "$TMP"; }

_plan() { p090_plan_state "$ROOT" "$1" "$2" "${3:-OPEN}"; }

_event() { jq -n --arg c "$ROOT" '{session_id:"s",cwd:$c,stop_hook_active:false}'; }

_q_merged() {
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: merged_to_plan
    plan_id: "P090"
    depends_on: []
YAML
}

_queue_ready() { p090_queue "$QUEUE" P090 "E-090-2_2:pending"; }

@test "AC13: a plan with a ready EPIC is named — and the queue is byte-identical afterwards" {
  _plan P090 auto
  _queue_ready
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090 (OPEN): E-090-2_2 is ready to be claimed"* ]]
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
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"every EPIC is accounted for"* ]]
  [[ "$output" == *"plan-close"* ]]
}

@test "a plan with nothing in its queue is before generation, not finished" {
  # `peek-next` answers `none` for both, and the hook used to render both as
  # "every EPIC is accounted for; the plan still needs closing" — advice that,
  # taken literally two minutes after plan-start, closes a plan in which
  # nothing was done. (ACTA, 2026-09-02.)
  _plan P090 auto
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue: []
YAML
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no EPIC is recorded in this plan queue yet"* ]]
  [[ "$output" != *"every EPIC is accounted for"* ]]
  [[ "$output" != *"plan-close"* ]]
}

@test "an entry belonging to another plan does not vouch for this one" {
  # Matching on plan_id alone is not enough: a queue file copied from another
  # plan would make an ungenerated plan look generated.
  _plan P090 auto
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-077-1_2
    status: merged_to_plan
    plan_id: "P090"
    depends_on: []
YAML
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no EPIC is recorded in this plan queue yet"* ]]
}

@test "SessionStart says it once per WORKSPACE, not once per window" {
  # The PM had five terminals open on one project and heard about the same
  # open plan five times. Stop was already filtered to its own transcript;
  # SessionStart was not, and its "once" marker was keyed per session — so
  # every new window was a new first time.
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
  local ev_a ev_b
  ev_a="$(jq -n --arg c "$ROOT" '{session_id:"window-A",cwd:$c}')"
  ev_b="$(jq -n --arg c "$ROOT" '{session_id:"window-B",cwd:$c}')"

  run aid_hook_rule_queue_continuation_start <<< "$ev_a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090"* ]]

  # A different window, same workspace, same plan in the same state. Silence
  # here must be the once-marker doing its job — asserted by the exit code and
  # the "nothing to say" line, not merely by P090 being absent, which an error
  # would also satisfy.
  run aid_hook_rule_queue_continuation_start <<< "$ev_b"
  [ "$status" -eq 3 ]
  [[ "$output" != *"P090"* ]]
  [[ "$output" == *"no open autonomous plan"* ]]
}

@test "a workspace reminder returns when the plan actually moves" {
  _plan P090 auto
  _q_merged
  local ev; ev="$(jq -n --arg c "$ROOT" '{session_id:"w1",cwd:$c}')"
  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [[ "$output" == *"P090"* ]]

  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [ "$status" -eq 3 ]
  [[ "$output" != *"P090"* ]]

  # The state moves: the item carries it, so it is said again. The remembered
  # item is plan:state:result, so a change in EITHER the plan state or what
  # the queue offers brings the reminder back. What does not bring it back is
  # merely opening another window — which was the whole complaint. A dormant
  # plan is announced once and then left alone; the window working on it still
  # hears about it at Stop.
  _plan P090 auto PLAN_REVIEW
  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [[ "$output" == *"P090"* ]]
}

@test "the same checkout reached through a symlink shares one memory" {
  # Without canonicalising the root, /tmp/link and /tmp/real would each get
  # their own marker and the reminder would come twice.
  _plan P090 auto
  _q_merged
  local link="${BATS_TEST_TMPDIR}/link"
  ln -sfn "$ROOT" "$link"
  run aid_hook_rule_queue_continuation_start <<< "$(jq -n --arg c "$ROOT" '{session_id:"w1",cwd:$c}')"
  [[ "$output" == *"P090"* ]]
  run aid_hook_rule_queue_continuation_start <<< "$(jq -n --arg c "$link" '{session_id:"w2",cwd:$c}')"
  [ "$status" -eq 3 ]
  [[ "$output" != *"P090"* ]]
}

@test "two different workspaces never share one memory" {
  # `workspace:${root}` is non-empty even when root is not a usable path, and
  # that string would hash every project on the machine onto ONE marker file —
  # a plan in project A silencing a plan in project B. The key is built only
  # from a canonicalised directory that exists; anything else falls back to
  # the per-session key, which merely repeats.
  _plan P090 auto
  _q_merged

  local other="${TMP}/other"
  p090_mk_workspace "$other"
  p090_plan_state "$other" P091 auto
  cat > "$other/.aid-o/config/queue.yaml" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-091-1_2
    status: merged_to_plan
    plan_id: "P091"
    depends_on: []
YAML

  run aid_hook_rule_queue_continuation_start <<< "$(jq -n --arg c "$ROOT" '{session_id:"w1",cwd:$c}')"
  [[ "$output" == *"P090"* ]]

  # A different project must still be heard.
  run aid_hook_rule_queue_continuation_start <<< "$(jq -n --arg c "$other" '{session_id:"w2",cwd:$c}')"
  [[ "$output" == *"P091"* ]]
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
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"blocked:E-090-2_2:dependency_unmerged:E-090-1_2"* ]]
}

@test "AC14: a manual plan is silent" {
  _plan P090 manual
  _queue_ready
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no open autonomous plan"* ]]

  # A plan with no `autonomy` field at all — every plan created before P090 —
  # reads as manual. Fail-closed: the cost of the other direction is a plan
  # continuing itself when nobody asked.
  sed -i '/^autonomy:/d' "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
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
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
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
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090 (OPEN): E-090-2_2"* ]]
  [[ "$output" == *"P091 (OPEN): E-091-2_2"* ]]
}

@test "a closed plan owes nothing and is not mentioned" {
  _plan P090 auto CLOSED
  _queue_ready
  run aid_hook_rule_queue_continuation_start <<< "$(_event)"
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
  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=1 run aid_hook_rule_queue_continuation_start <<< "$(_event)"
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
  [[ "$output" == *"Continue it with /aid-run --auto"* ]]
}

@test "no AID workspace, or no cwd at all, is 'not applicable' — never an opinion" {
  run aid_hook_rule_queue_continuation_stop <<< '{"session_id":"s"}'
  [ "$status" -eq 3 ]
  run aid_hook_rule_queue_continuation_start <<< '{"session_id":"s"}'
  [ "$status" -eq 3 ]
}

# --- the failure paths Codex named, 2026-08-30 ----------------------------

@test "memory: an empty transcript_path falls back to session_id, not to a shared key" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-session-store.sh'
    AID_SESSION_STORE='$TMP/s2' aid_session_once ns 'sid-a' 'item' && echo first-said
    AID_SESSION_STORE='$TMP/s2' aid_session_once ns 'sid-a' 'item' || echo second-silent
    AID_SESSION_STORE='$TMP/s2' aid_session_once ns 'sid-b' 'item' && echo other-session-said"
  [[ "$output" == *"first-said"* ]]
  [[ "$output" == *"second-silent"* ]]
  [[ "$output" == *"other-session-said"* ]]
}

@test "memory: with no session identity at all the reminder is SAID, never assumed said" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-session-store.sh'
    AID_SESSION_STORE='$TMP/s3' aid_session_once ns '' 'item' && echo said-1
    AID_SESSION_STORE='$TMP/s3' aid_session_once ns '' 'item' && echo said-2"
  [[ "$output" == *"said-1"* ]]
  [[ "$output" == *"said-2"* ]]
}

@test "memory: a store that cannot be written does not silence — it reports" {
  local ro="$TMP/ro"
  mkdir -p "$ro/ns"
  printf 'item\n' > "$ro/ns/seen-$(printf '%s' sid | sha256sum | cut -c1-16)"
  chmod -w "$ro/ns/seen-$(printf '%s' sid | sha256sum | cut -c1-16)"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-session-store.sh'
    AID_SESSION_STORE='$ro' aid_session_once ns sid item && echo said-despite-marker"
  chmod +w "$ro/ns/"* 2>/dev/null || true
  [[ "$output" == *"said-despite-marker"* ]]
}

# --- P099 Step 5: the bound session keeps going ---------------------------

# _bind <plan> <session> — the plan-state record `/aid-run --auto` leaves.
_bind() { printf 'auto_session: %s\n' "$2" >> "$ROOT/.aid-o/work/plan-state/$1/plan-state.yaml"; }
# _turn <last message> — a transcript whose last assistant message is that text.
_turn() {
  jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$TMP/t.jsonl"
  printf '%s' "$TMP/t.jsonl"
}
# _stop <session> <last message> [stop_hook_active] — a Stop event.
_stop() {
  jq -n --arg c "$ROOT" --arg s "$1" --arg t "$(_turn "$2")" --argjson a "${3:-false}" \
    '{session_id:$s,cwd:$c,transcript_path:$t,stop_hook_active:$a}'
}
_sink() {
  printf 'send_alert() { echo "$3" >> "%s/sent"; }\n' "$TMP" > "$TMP/tg.sh"
  export AID_TELEGRAM_LIB="$TMP/tg.sh"
}
_sent() { grep -c "${1:-agent-waiting}" "$TMP/sent" 2>/dev/null || echo 0; }

@test "the bound session is refused while work is left, a second time too, and another session never" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "Krok 2 hotový, pokračuji.")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outcome=refused plan=P090"* ]]
  [[ "$output" == *"continuation 1 of 40"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "Pokračuji." true)"
  [ "$status" -eq 2 ]; [[ "$output" == *"continuation 2 of 40"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop T9 "Hotovo.")"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=not_auto"* ]]
  [ "$(_sent)" -eq 0 ]
}

@test "a Blocked card ends the turn with one waiting message; the PM's reply re-arms it and resets the count" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "Pokračuji.")" 2>/dev/null || true
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'Zastaveno: brána padá\nDůvod: x')"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=handed_over"* ]]
  aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'Zastaveno: brána padá')" 2>/dev/null || true
  [ "$(_sent)" -eq 1 ]
  run aid_hook_rule_pm_reply_marker <<< "$(jq -n --arg c "$ROOT" '{session_id:"S1",cwd:$c}')"
  [[ "$output" == *"1 plan(s) re-armed"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "Pokračuji.")"
  [[ "$output" == *"continuation 1 of 40"* ]]
  aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'Zastaveno: znovu')" 2>/dev/null || true
  [ "$(_sent)" -eq 2 ]
}

@test "AID-WAIT ends the turn uncounted only while an AID background job is live" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local jd="$ROOT/.aid-o/work/evidence/E-090-1_2/R-1/jobs/j1"; mkdir -p "$jd"
  sleep 30 & local pid=$!
  jq -n --argjson p "$pid" --arg st "$(awk '{print $22}' /proc/$pid/stat)" '{pid:$p, proc_starttime:$st}' > "$jd/job.json"
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'Brány běží.\nAID-WAIT: bats_all')"
  kill "$pid"; wait "$pid" 2>/dev/null || true
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=wait"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'AID-WAIT: bats_all')"
  [ "$status" -eq 2 ]; [[ "$output" == *"continuation 1 of 40"* ]]
}

@test "the rule never refuses without knowing: an unparsable transcript or plan-state, or another plan's live job" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  printf 'not json\n' > "$TMP/bad.jsonl"
  run aid_hook_rule_queue_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$TMP/bad.jsonl" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [ "$status" -eq 3 ]; [[ "$output" == *"transcript does not parse"* ]]
  # another plan's live job does not excuse this plan's AID-WAIT
  local jd="$ROOT/.aid-o/work/evidence/E-091-1_2/R-1/jobs/j1"; mkdir -p "$jd"
  sleep 30 & local pid=$!
  jq -n --argjson p "$pid" --arg st "$(awk '{print $22}' /proc/$pid/stat)" '{pid:$p, proc_starttime:$st}' > "$jd/job.json"
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 $'AID-WAIT: bats_all')"
  kill "$pid"; wait "$pid" 2>/dev/null || true
  [ "$status" -eq 2 ]
  printf 'plan_id: [broken\nautonomy: auto\nplan_state: EPIC_INTEGRATION\nauto_session: S1\n' > "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")"
  [ "$status" -eq 3 ]; [[ "$output" == *"does not parse"* ]]
}

@test "at the budget the turn ends with one waiting message; budget 0 disables the refusal" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  mkdir -p "$ROOT/.aid-o/config"; printf 'autonomy:\n  continuation_budget: 1\n' > "$ROOT/.aid-o/config/orchestration.yaml"
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 2 ]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=budget_spent"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 3 ]
  [ "$(_sent)" -eq 1 ]
  printf 'autonomy:\n  continuation_budget: 0\n' > "$ROOT/.aid-o/config/orchestration.yaml"
  rm -rf "$AID_SESSION_STORE/continuation"
  run aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 3 ]
}

@test "two workspaces with the same plan id keep separate counters" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local other="$TMP/other"; p090_mk_workspace "$other"; p090_plan_state "$other" P090 auto EPIC_INTEGRATION
  printf 'auto_session: S1\n' >> "$other/.aid-o/work/plan-state/P090/plan-state.yaml"
  aid_hook_rule_queue_continuation_stop <<< "$(_stop S1 "x")" 2>/dev/null || true
  run aid_hook_rule_queue_continuation_stop <<< "$(jq -n --arg c "$other" --arg t "$(_turn x)" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"continuation 1 of 40"* ]]
}

@test "through the real dispatcher the refusal holds under stop_hook_active, and neither event writes into the tree" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  mkdir -p "$TMP/store/hooks"
  printf '{"verified":true,"tool":"bats","version":"fixture","checked_at":"%s"}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/store/hooks/trust.json"
  local before; before="$(find "$ROOT/.aid-o" -type f -exec sha256sum {} + | sort)"
  run bash "$HOOK" Stop <<< "$(_stop S1 "x" true)"
  [ "$status" -eq 2 ]; [[ "$output" == *"Continue the /aid-run --auto procedure"* ]]
  grep -q '"rule":"queue_continuation_notice","outcome":"deny","reason":"outcome=refused plan=P090' "$AID_HOOK_AUDIT"
  # The PM's prompt is audited too, and neither event writes into the tree.
  run bash "$HOOK" UserPromptSubmit <<< "$(jq -n --arg c "$ROOT" '{session_id:"S1",cwd:$c,prompt:"ok"}')"
  [ "$status" -eq 0 ]
  grep -q '"event":"UserPromptSubmit","session_id":"S1".*"rule":"pm_reply_marker"' "$AID_HOOK_AUDIT"
  [ "$(find "$ROOT/.aid-o" -type f -exec sha256sum {} + | sort)" = "$before" ]
}

@test "the registry row refuses (degree 2, closed) and bounds its own loop" {
  run yq -r '.rules[] | select(.id == "queue_continuation_notice") | "\(.event) \(.degree) \(.failure) \(.blocks_when_active)"' "$AID_PLUGIN_PATH/defaults/hook-registry.yaml"
  [ "$output" = "Stop 2 closed true" ]
}

