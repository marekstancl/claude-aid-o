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
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
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
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
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

@test "Stop is still per-session — a second window working on the plan hears it" {
  # The workspace marker must not silence the window that is actually in the
  # plan; that would trade one complaint for a worse one.
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
  local ev; ev="$(jq -n --arg c "$ROOT" '{session_id:"w1",cwd:$c}')"
  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [[ "$output" == *"P090"* ]]

  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P090"* ]]
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
  # The once-per-session memory is cleared between the two, because what is
  # under test here is the DISPATCHER, not the memory: leaving it would make
  # the second call silent for the right reason and prove nothing about the
  # wrong one.
  rm -rf "${AID_SESSION_STORE:?}/queue-continuation"
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

# --- said once, not at every turn -----------------------------------------
# 2026-08-30, a consumer project: this rule reads EVERY plan-state record in the
# workspace, so four open plans were named at every single turn — including
# plans the session was not working on. The agent answered "čekám na tebe" to
# each one, which is what a rule that repeats teaches a reader to do.

@test "at Stop, an open plan is named once per session, not at every turn" {
  _plan P020 auto EPIC_INTEGRATION
  _queue_ready
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" == *"P020"* ]]

  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" != *"P020"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" != *"P020"* ]]
}

@test "a plan that MOVES is named again — that is news, standing still is not" {
  _plan P020 auto EPIC_INTEGRATION
  _queue_ready
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" == *"P020"* ]]
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" != *"P020"* ]]

  _plan P020 auto PLAN_GATES
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" == *"P020"* ]]
}

@test "two open plans are both named, and both fall silent together" {
  _plan P018 auto EPIC_INTEGRATION
  _plan P020 auto EPIC_INTEGRATION
  _queue_ready
  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" == *"P018"* ]]
  [[ "$output" == *"P020"* ]]

  run aid_hook_rule_queue_continuation_stop <<< "$(_event)"
  [[ "$output" != *"P018"* ]]
  [[ "$output" != *"P020"* ]]
}

# --- the failure paths Codex named, 2026-08-30 ----------------------------

@test "memory: two sessions do not silence each other" {
  _plan P020 auto EPIC_INTEGRATION
  _queue_ready
  local a="$TMP/ta.jsonl" b="$TMP/tb.jsonl"
  printf 'P020\n' > "$a"; printf 'P020\n' > "$b"

  run aid_hook_rule_queue_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$a" '{cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"P020"* ]]
  # A DIFFERENT session must still hear it, even for the same plan and state.
  run aid_hook_rule_queue_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$b" '{cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"P020"* ]]
}

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

@test "a plan this session has never been in is not named at all" {
  _plan P018 auto EPIC_INTEGRATION     # the session's own
  _plan P077 auto EPIC_INTEGRATION     # somebody else's
  _queue_ready
  local t="$TMP/tc.jsonl"; printf 'pracuji na P018\n' > "$t"
  run aid_hook_rule_queue_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$t" '{cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"P018"* ]]
  [[ "$output" != *"P077"* ]]
}

@test "SessionStart names a plan this session has never been in — Stop does not" {
  # Codex, 2026-08-30: filtering by transcript at Stop could bury a plan nobody
  # has mentioned. The start of a session is where the whole workspace belongs.
  _plan P018 auto EPIC_INTEGRATION
  _plan P077 auto EPIC_INTEGRATION
  _queue_ready
  local t="$TMP/td.jsonl"; printf 'pracuji na P018\n' > "$t"
  local ev; ev="$(jq -n --arg c "$ROOT" --arg t "$t" '{cwd:$c,transcript_path:$t}')"

  run aid_hook_rule_queue_continuation_stop <<< "$ev"
  [[ "$output" != *"P077"* ]]

  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [[ "$output" == *"P077"* ]]
}

@test "a plan opened mid-session is not lost — the next SessionStart names it" {
  # The accepted limit, pinned: a plan that opens during a session this one
  # never mentions is silent at Stop, and the NEXT SessionStart says it. The
  # loss is bounded by one session, never permanent.
  _plan P018 auto EPIC_INTEGRATION
  _queue_ready
  local t="$TMP/te.jsonl"; printf 'pracuji na P018\n' > "$t"
  local ev; ev="$(jq -n --arg c "$ROOT" --arg t "$t" '{cwd:$c,transcript_path:$t}')"

  run aid_hook_rule_queue_continuation_start <<< "$ev"
  [[ "$output" != *"P077"* ]]              # not open yet

  _plan P077 auto EPIC_INTEGRATION         # …another actor opens it mid-session
  run aid_hook_rule_queue_continuation_stop <<< "$ev"
  [[ "$output" != *"P077"* ]]              # this session is not told — by design

  local t2="$TMP/tf.jsonl"; printf 'nova session\n' > "$t2"
  run aid_hook_rule_queue_continuation_start <<< "$(jq -n --arg c "$ROOT" --arg t "$t2" '{cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"P077"* ]]              # …the next session start is
}
