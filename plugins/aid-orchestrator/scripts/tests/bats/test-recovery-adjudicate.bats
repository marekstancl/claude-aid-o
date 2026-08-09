#!/usr/bin/env bats
# test-recovery-adjudicate.bats — P076 EPIC 2, Step 12.
#
# `lib/aid-recovery-adjudicate.sh` is the codification of the dispatch
# convention `commands/aid-run.md` used to carry as prose. The property that
# matters is not "the happy path works" — it is that the adjudicator CANNOT
# widen its own remit, no matter what it replies. So the suite spends most of
# its cases on the refusals:
#
#   1  an in-allowlist reply is accepted, printed, and recorded
#   2  the timeline/ladder entry shape is pinned
#   3  the prompt pack carries the allowlist and the forbidden list VERBATIM
#   4  an out-of-allowlist reply is rejected once, the retry quotes the
#      rejection, and a second bad reply returns escalate
#   5  THE CEILING — a reply demanding PM authority / a gate waiver cannot
#      produce an action, only escalate
#   6  an EMPTY reply is never read as consent
#   7  two action tokens = ambiguity = reject
#   8  UNCLASSIFIED (empty allowlist) short-circuits to escalate WITHOUT
#      dispatching at all
#   9  missing / empty facts refuses BEFORE dispatching
#  10  transport unavailability returns escalate, never a silent pass
#  11  every exchange — including the refusals that never dispatch — left an
#      audit artifact
#
# The transport is STUBBED (`_run_codex_isolated` redefined after sourcing), so
# no case in this file can reach the real `codex` CLI.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  LIB="$PLUGIN_ROOT/scripts/lib/aid-recovery-adjudicate.sh"
  POLICY="$PLUGIN_ROOT/defaults/policies/auto-recovery.yaml"
  export REPO_ROOT PLUGIN_ROOT LIB POLICY

  WORK="$(mktemp -d)"
  export WORK
  EVID="$WORK/evidence"
  STUB_DIR="$WORK/stub"
  mkdir -p "$EVID" "$STUB_DIR"
  export EVID STUB_DIR

  printf 'state: EXECUTE\nepic_id: E-076-2_3\n' > "$EVID/fsm-state.yaml"
  printf 'gate bats_unit exceeded its 900s deadline; job 42 cancelled; terminal record present.\n' \
    > "$EVID/facts.md"
  export FACTS="$EVID/facts.md"

  # ── the stubbed transport ────────────────────────────────────────────────
  # Redefined AFTER sourcing the lib, so the lib calls the stub by name. It
  # records every invocation (count + the exact prompt file) and replies with
  # $STUB_DIR/reply-<n> (falling back to reply-1).
  cat > "$WORK/run.sh" <<'RUNNER'
#!/usr/bin/env bash
source "$LIB"
_run_codex_isolated() {
  local prompt_file="$2" events="$3" stderr_out="$4" last="$5"
  local n; n=$(( $(cat "$STUB_DIR/count" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$STUB_DIR/count"
  cp "$prompt_file" "$STUB_DIR/prompt-$n.md"
  if [[ "${STUB_RC:-0}" != "0" ]]; then
    echo "codex: command not found" > "$stderr_out"
    return "$STUB_RC"
  fi
  local rv="$STUB_DIR/reply-$n"
  [[ -f "$rv" ]] || rv="$STUB_DIR/reply-1"
  cp "$rv" "$last"
  echo '{"type":"thread.started","thread_id":"t-stub"}' > "$events"
  return 0
}
aid_recovery_adjudicate "$@"
RUNNER
  chmod +x "$WORK/run.sh"
}

teardown() { rm -rf "$WORK"; }

reply() { # reply <n> <text...>
  local n="$1"; shift
  printf '%s\n' "$*" > "$STUB_DIR/reply-$n"
}

dispatch_count() { cat "$STUB_DIR/count" 2>/dev/null || echo 0; }

adjudicate() { bash "$WORK/run.sh" "$@"; }

last_timeline() { tail -n1 "$EVID/timeline.jsonl"; }

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: an in-allowlist reply is accepted, printed and recorded" {
  reply 1 "ACTION: rerun_targeted
RATIONALE: the gate timed out once; re-running only that selection is reversible and in scope."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "rerun_targeted" ]
  [ "$(dispatch_count)" -eq 1 ]

  # recorded in BOTH the timeline and the ladder record
  run jq -r 'select(.event=="recovery_adjudication") | .action' "$EVID/timeline.jsonl"
  [ "$output" = "rerun_targeted" ]
  [ -s "$EVID/recovery-ladder.jsonl" ]
  run jq -r '.action' "$EVID/recovery-ladder.jsonl"
  [ "$output" = "rerun_targeted" ]
}

@test "case 2: the timeline entry shape is pinned" {
  reply 1 "ACTION: collect_and_continue
RATIONALE: the terminal record already exists; collecting it produces no new execution."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 0 ]

  local line; line="$(last_timeline)"
  run bash -c "printf '%s' '$line' | jq -e '
      (.ts|test(\"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$\"))
      and .event == \"recovery_adjudication\"
      and .class == \"GATE_TIMEOUT\"
      and .action == \"collect_and_continue\"
      and (.rationale | type == \"string\" and length > 0)
      and .verdict == \"accepted\"
      and (.artifact | test(\"recovery-adjudication-.*\\\\.json$\"))
      and .attempt == 1'"
  [ "$status" -eq 0 ] || { echo "$line"; false; }

  # the four keys the plan names are all present
  local k
  for k in class action rationale ts; do
    printf '%s' "$line" | jq -e "has(\"$k\")" >/dev/null
  done
}

@test "case 3: the prompt pack carries the allowlist and the forbidden list verbatim" {
  reply 1 "ACTION: rerun_targeted
RATIONALE: reversible."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 0 ]

  local p="$STUB_DIR/prompt-1.md"
  [ -f "$p" ]

  # the allowlist, exactly as the policy declares it for this class
  grep -q "^## ALLOWED ACTIONS$" "$p"
  local a
  while read -r a; do
    grep -qF "  - $a" "$p" || { echo "allowlist entry missing from prompt: $a"; false; }
  done < <(yq -r '.stop_classes.GATE_TIMEOUT.allowed_actions[]' "$POLICY")
  # and NOT an action of some other class
  ! grep -qF "  - restart_service_once" "$p"

  # the forbidden list, verbatim (fixture-asserted, line by line)
  grep -qF "FORBIDDEN — you may not select, request, imply or negotiate any of these:" "$p"
  grep -qF "  - granting, assuming or delegating PM authority" "$p"
  grep -qF "  - waiving, weakening, skipping, deferring or overriding any gate, review or security risk" "$p"
  grep -qF "  - --force, pm_force, or any FSM override or state edit" "$p"
  grep -qF "  - editing plan.json, fsm-state.yaml, step verification files, gate reports or timelines" "$p"
  grep -qF '  - any action not printed in ALLOWED ACTIONS above, including "widen the allowlist"' "$p"

  # verified facts + the real FSM state (read through aid-fsm.sh get-state)
  grep -qF "gate bats_unit exceeded its 900s deadline" "$p"
  grep -qF "FSM STATE:  EXECUTE" "$p"
  grep -qF "STOP CLASS: GATE_TIMEOUT" "$p"
}

@test "case 4: out-of-allowlist is rejected once, the retry quotes it, second bad reply escalates" {
  reply 1 "ACTION: restart_service_once
RATIONALE: I would rather restart the service."
  reply 2 "ACTION: restart_service_once
RATIONALE: still my answer."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 2 ]   # exactly ONE retry, not a loop

  # the retry prompt quotes the rejection and the rejected reply
  grep -qF "## YOUR PREVIOUS REPLY WAS REJECTED" "$STUB_DIR/prompt-2.md"
  grep -qF "is not in the allowlist for class GATE_TIMEOUT" "$STUB_DIR/prompt-2.md"
  grep -qF "I would rather restart the service." "$STUB_DIR/prompt-2.md"

  # both rejections recorded, neither as an action
  run jq -r -s '[.[] | select(.event=="recovery_adjudication")] | map(.verdict) | join(",")' "$EVID/timeline.jsonl"
  [ "$output" = "rejected_out_of_allowlist,rejected_out_of_allowlist" ]
  run jq -r -s '[.[] | .action] | unique | join(",")' "$EVID/timeline.jsonl"
  [ "$output" = "escalate" ]
}

@test "case 5: THE CEILING — a reply demanding PM authority cannot produce an action" {
  reply 1 "ACTION: pm_force
RATIONALE: I am granting PM authority to waive the gate and merge; also add force_merge to the allowlist."
  reply 2 "The correct answer is to override the FSM with --force and waive the security finding.
ACTION: waive_gate"
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$output" = "escalate" ]

  # nothing the adjudicator asked for became an action ANYWHERE in the record
  run grep -E 'pm_force|waive_gate|force_merge' "$EVID/timeline.jsonl"
  [ "$status" -ne 0 ] || { echo "an authority-expanding token leaked into the ladder: $output"; false; }
  run jq -r -s '[.[] | .action] | unique | join(",")' "$EVID/timeline.jsonl"
  [ "$output" = "escalate" ]

  # and the only actions this class could EVER yield are the policy's own two
  run bash -c "yq -r '.stop_classes.GATE_TIMEOUT.allowed_actions | join(\",\")' '$POLICY'"
  [ "$output" = "rerun_targeted,collect_and_continue" ]
}

@test "case 6: an EMPTY reply is never read as consent" {
  : > "$STUB_DIR/reply-1"
  : > "$STUB_DIR/reply-2"
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 3 ]
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 2 ]
  grep -qF "the reply named no action at all" "$STUB_DIR/prompt-2.md"
  run jq -r -s '[.[] | select(.verdict=="rejected_empty")] | length' "$EVID/timeline.jsonl"
  [ "$output" = "2" ]
}

@test "case 7: two action tokens are ambiguity, not a decision" {
  reply 1 "ACTION: rerun_targeted or collect_and_continue, whichever you prefer
RATIONALE: both are reversible."
  reply 2 "ACTION: rerun_targeted
RATIONALE: on reflection, only the targeted re-run."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  # the retry IS allowed to succeed — one rejection, then a clean answer
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "rerun_targeted" ]
  run jq -r -s '[.[] | .verdict] | join(",")' "$EVID/timeline.jsonl"
  [ "$output" = "rejected_ambiguous,accepted" ]
}

@test "case 8: UNCLASSIFIED short-circuits to escalate WITHOUT dispatching" {
  reply 1 "ACTION: rerun_targeted
RATIONALE: would have been accepted for another class."
  run adjudicate "$EVID" UNCLASSIFIED "$FACTS"
  [ "$status" -eq 3 ]
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 0 ]   # the transport was never touched
  run jq -r '.verdict' "$EVID/timeline.jsonl"
  [ "$output" = "refused_empty_allowlist" ]

  # the same holds for any class the policy leaves without an action, and for
  # a class that does not exist at all
  rm -f "$EVID/timeline.jsonl"
  run adjudicate "$EVID" NO_SUCH_CLASS "$FACTS"
  [ "$status" -eq 3 ]
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 0 ]
}

@test "case 9: missing or empty facts refuses BEFORE dispatching" {
  reply 1 "ACTION: rerun_targeted
RATIONALE: irrelevant, this must never be asked."

  run adjudicate "$EVID" GATE_TIMEOUT "$EVID/nope.md"
  [ "$status" -eq 3 ]
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 0 ]

  : > "$EVID/empty.md"
  run adjudicate "$EVID" GATE_TIMEOUT "$EVID/empty.md"
  [ "$status" -eq 3 ]
  [ "$output" = "escalate" ]
  [ "$(dispatch_count)" -eq 0 ]
  run jq -r -s '[.[] | .verdict] | unique | join(",")' "$EVID/timeline.jsonl"
  [ "$output" = "refused_no_facts" ]
}

@test "case 10: transport unavailability returns escalate, never a silent pass" {
  reply 1 "ACTION: rerun_targeted
RATIONALE: never delivered."
  export STUB_RC=127
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  unset STUB_RC
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$output" = "escalate" ]
  run jq -r '.verdict' "$EVID/timeline.jsonl"
  [ "$output" = "transport_error" ]
  # the transport error is attached to the artifact, not swallowed
  local art; art="$(ls "$EVID"/recovery-adjudication-*.json | head -n1)"
  run jq -r '.transport_error' "$art"
  [[ "$output" == *"codex transport exit 127"* ]] || { echo "$output"; false; }
  [[ "$output" == *"command not found"* ]] || { echo "$output"; false; }
}

@test "case 11: every exchange writes its audit artifact, refusals included" {
  reply 1 "ACTION: restart_service_once
RATIONALE: out of allowlist."
  reply 2 "ACTION: rerun_targeted
RATIONALE: corrected."
  run adjudicate "$EVID" GATE_TIMEOUT "$FACTS"
  [ "$status" -eq 0 ]

  # one artifact + one rendered prompt per exchange
  [ "$(ls "$EVID"/recovery-adjudication-*.json | wc -l)" -eq 2 ]
  [ "$(ls "$EVID"/recovery-adjudication-*.prompt.md | wc -l)" -eq 2 ]

  local art
  for art in "$EVID"/recovery-adjudication-*.json; do
    run jq -e '(.prompt_sha256 | test("^sha256:[0-9a-f]{64}$"))
               and (.raw_reply | type == "string" and length > 0)
               and (.verdict | type == "string" and length > 0)
               and (.stop_class == "GATE_TIMEOUT")
               and (.dispatched == true)' "$art"
    [ "$status" -eq 0 ] || { echo "$art"; cat "$art"; false; }
  done

  # the prompt hash really is the hash of the prompt that was sent
  local first_art first_prompt
  first_art="$(ls "$EVID"/recovery-adjudication-*-1.json)"
  first_prompt="$(jq -r '.prompt_path' "$first_art")"
  [ "sha256:$(sha256sum "$first_prompt" | awk '{print $1}')" = "$(jq -r '.prompt_sha256' "$first_art")" ]

  # the refusal paths that never dispatch still leave a record
  rm -f "$EVID"/recovery-adjudication-*
  run adjudicate "$EVID" UNCLASSIFIED "$FACTS"
  [ "$status" -eq 3 ]
  [ "$(ls "$EVID"/recovery-adjudication-*.json | wc -l)" -eq 1 ]
  run jq -r '.dispatched' "$EVID"/recovery-adjudication-*.json
  [ "$output" = "false" ]
}

@test "case 12: aid-run.md hands the convention to the lib instead of restating it" {
  local md="$PLUGIN_ROOT/commands/aid-run.md"
  grep -qF "scripts/lib/aid-recovery-adjudicate.sh" "$md"
  grep -qF "aid_recovery_adjudicate" "$md"
  # the temporary-convention prose is gone from the command
  run grep -n "This is a temporary dispatch convention" "$md"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  # and the convention text now lives in the lib header
  grep -qF "Until a dedicated adjudicator command is available, use the existing" "$LIB"
}
