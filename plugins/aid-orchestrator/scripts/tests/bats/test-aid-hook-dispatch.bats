#!/usr/bin/env bats
# aid-tier: t1
#   MEASURED, not wished: one case waits out a real per-rule clock (a rule that
#   overruns must actually overrun), which puts this suite's slowest case above
#   the t0 ceiling. It stays on the merge path either way.
# test-aid-hook-dispatch.bats — the harness hook layer (P086 Step 1).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   Nothing here runs a harness. Whether Claude Code or Codex actually calls
#   `aid-hook.sh` is what the canary (scripts/aid-hook-verify.sh, Step 2)
#   answers, and no assertion in this file may be read as evidence that it
#   does. What is proved HERE is the dispatcher's own contract: which rows it
#   selects, whose rules it refuses to run, what it does when a rule breaks or
#   overruns, and that every escape hatch works.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  HOOK="$PLUGIN_ROOT/scripts/aid-hook.sh"
  TMP="$(mktemp -d)"
  AUDIT="$TMP/audit.jsonl"
  export AID_HOOK_AUDIT="$AUDIT"
  # No canary verdict in the fixture store: fail-closed rows must degrade
  # unless a test writes one deliberately.
  export AID_SESSION_STORE="$TMP/state"
  cat > "$TMP/rules.sh" <<'RULES'
rule_ok()      { cat > /dev/null; echo "OK-INJECTED"; }
rule_deny()    { cat > /dev/null; echo "refused: no options offered" >&2; exit 2; }
rule_broken()  { cat > /dev/null; echo "boom" >&2; exit 7; }
rule_slow()    { cat > /dev/null; sleep 3; }
rule_context() { cat > /dev/null; echo "CONTROLLER-ONLY"; }
RULES
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# write_registry <rows-yaml> [budget_s]
#   Rows are indented two spaces under `rules:`.
write_registry() {
  local rows="$1" budget="${2:-15}"
  cat > "$TMP/registry.yaml" <<YAML
version: 1
defaults:
  timeout_s: 5
budget:
  total_s: ${budget}
rules:
${rows}
YAML
  export AID_HOOK_REGISTRY="$TMP/registry.yaml"
}

row() { # row <id> <event> <owner> <handler> [failure] [timeout_s]
  cat <<YAML
  - id: $1
    event: $2
    owner: $3
    degree: 2
    failure: ${5:-open}
    timeout_s: ${6:-5}
    lib: ${TMP}/rules.sh
    handler: $4
    description: fixture row
YAML
}

run_hook() { # run_hook <event> [json]
  run bash -c "printf '%s' '${2:-{\"session_id\":\"s1\"}}' | bash '$HOOK' '$1'"
}

@test "self-test dispatches a registered rule end to end (SC1)" {
  unset AID_HOOK_REGISTRY
  run bash "$HOOK" --self-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-test OK"* ]]
}

@test "AC1: a rule for a new event is picked up from the registry alone" {
  write_registry "$(row brand_new NeverSeenBefore any rule_ok)"
  run_hook NeverSeenBefore
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK-INJECTED"* ]]
  # The claim is not just "it ran" but "aid-hook.sh knows nothing about it":
  # the event name appears nowhere in the entry point.
  run grep -c "NeverSeenBefore" "$HOOK"
  [ "$output" = "0" ]
}

@test "AC12: the third shipped rule arrived as a registry row, with the entry point untouched" {
  # The layer's reuse test, and the reason Step 4 exists where it does. If a
  # new rule had needed aid-hook.sh edited, the dispatcher would have been
  # built for its first consumer rather than for rules in general.
  unset AID_HOOK_REGISTRY
  run yq -r '.rules[] | select(.id == "plan_artifact_rendered") | .lib' "$PLUGIN_ROOT/defaults/hook-registry.yaml"
  [ "$output" = "scripts/lib/aid-artifact-obligation.sh" ]
  run grep -c "plan_artifact_rendered\|aid-artifact-obligation" "$HOOK"
  [ "$output" = "0" ]
}

@test "a rule registered for another event does not run" {
  write_registry "$(row only_stop Stop any rule_ok)"
  run_hook SessionStart
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
}

@test "AC2: a broken fail-open rule neither blocks the turn nor stays silent" {
  write_registry "$(row breaks Stop any rule_broken)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"error"' "$AUDIT"
  grep -q 'boom' "$AUDIT"
}

@test "a fail-closed rule denies with the reason on stderr — once the canary allows it" {
  mkdir -p "$TMP/state/hooks"
  echo "{\"verified\":true,\"tool\":\"bats\",\"version\":\"fixture\",\"checked_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$TMP/state/hooks/trust.json"
  write_registry "$(row card Stop any rule_deny closed)"
  run_hook Stop
  [ "$status" -eq 2 ]
  [[ "$output" == *"no options offered"* ]]
}

@test "without a canary verdict a fail-closed rule degrades to fail-open and says so" {
  write_registry "$(row breaks Stop any rule_broken closed)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"degraded"' "$AUDIT"
}

@test "a fail-open rule may not refuse a turn — the refusal is recorded and ignored" {
  mkdir -p "$TMP/state/hooks"
  echo "{\"verified\":true,\"tool\":\"bats\",\"version\":\"fixture\",\"checked_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$TMP/state/hooks/trust.json"
  write_registry "$(row card Stop any rule_deny open)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"deny_ignored"' "$AUDIT"
}

@test "a degraded fail-closed rule records the refusal it would have made" {
  write_registry "$(row card Stop any rule_deny closed)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"deny_suppressed"' "$AUDIT"
}

@test "a canary verdict that has gone stale stops unlocking fail-closed rules" {
  # The dispatcher cannot tell which harness is calling it, so it cannot check
  # that the tool and version in the verdict are still the ones running. What
  # it can refuse to do is trust a measurement forever.
  mkdir -p "$TMP/state/hooks"
  echo '{"verified":true,"tool":"bats","version":"fixture","checked_at":"2020-01-01T00:00:00Z"}' \
    > "$TMP/state/hooks/trust.json"
  write_registry "$(row card Stop any rule_deny closed)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"degraded"' "$AUDIT"
}

@test "AC3: a controller-owned rule does not run inside a subagent" {
  write_registry "$(row controller_only Stop controller rule_context)"
  run_hook Stop '{"session_id":"s1","agent_type":"aid-orchestrator:implementer"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CONTROLLER-ONLY"* ]]
  grep -q '"outcome":"skip"' "$AUDIT"
}

@test "AID_HOOK_CONTEXT narrows the context a harness did not declare" {
  # The mitigation the registry cites for the measured ownership limit: an event
  # carrying neither agent_type nor a Subagent* name is read as controller, and
  # this is the way a dispatcher of subagents says otherwise.
  write_registry "$(row controller_only Stop controller rule_context)"
  AID_HOOK_CONTEXT=agent run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"CONTROLLER-ONLY"* ]]
  grep -q '"context":"agent/env"' "$AUDIT"
}

@test "the audit says whether the context was read or assumed" {
  write_registry "$(row any_one Stop any rule_ok)"
  run_hook Stop
  grep -q '"context":"controller/assumed"' "$AUDIT"
  run_hook Stop '{"session_id":"s1","agent_type":"aid-orchestrator:implementer"}'
  grep -q '"context":"agent/agent_type"' "$AUDIT"
}

@test "a rule that overruns its clock is stopped and audited" {
  write_registry "$(row slow Stop any rule_slow open 1)"
  run_hook Stop
  [ "$status" -eq 0 ]
  grep -q '"outcome":"timeout"' "$AUDIT"
}

@test "the dispatch budget stops rules that have not started" {
  write_registry "$(row never Stop any rule_ok)" 0
  run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  grep -q 'budget' "$AUDIT"
}

@test "AC4: AID_HOOKS_OFF=1 switches everything off and leaves an audit line" {
  write_registry "$(row card Stop any rule_ok)"
  AID_HOOKS_OFF=1 run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  grep -q '"outcome":"hooks_off"' "$AUDIT"
}

@test "AID_HOOKS_OFF_RULES switches off one row and leaves the others running" {
  write_registry "$(row one Stop any rule_ok
row two Stop any rule_context)"
  AID_HOOKS_OFF_RULES=one run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  [[ "$output" == *"CONTROLLER-ONLY"* ]]
}

@test "disabled: true switches a row off permanently" {
  write_registry "$(row card Stop any rule_ok | sed 's/^    description:/    disabled: true\n    description:/')"
  run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  grep -q '"outcome":"disabled"' "$AUDIT"
}

@test "an unknown event exits 0 and prints nothing" {
  write_registry "$(row card Stop any rule_ok)"
  run_hook TotallyUnknownEvent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unreadable registry runs no rule at all" {
  write_registry "$(row card Stop any rule_ok)"
  printf 'this: is: not: yaml: [\n' > "$TMP/registry.yaml"
  run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  grep -q 'registry unreadable' "$AUDIT"
}

@test "a row without an owner is refused rather than run" {
  write_registry "$(row card Stop any rule_ok | sed '/^    owner:/d')"
  run_hook Stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK-INJECTED"* ]]
  grep -q 'no owner' "$AUDIT"
}
