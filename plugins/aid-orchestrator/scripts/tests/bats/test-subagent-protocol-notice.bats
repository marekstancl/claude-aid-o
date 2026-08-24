#!/usr/bin/env bats
# aid-tier: t0
# test-subagent-protocol-notice.bats — telling a role agent its protocol is
# stale (P086 Step 10).
#
# THE GROUNDED FAILURE MODE: IMP-179, three separate occurrences. A subagent's
# system prompt comes from the INSTALLED plugin, not the checkout it works in,
# so an Auditor and a Curator both acted on a protocol the repository had
# already changed — and neither could have known.
#
# WHAT MADE THIS RULE ALLOWED TO EXIST: a measurement, not the documentation.
# Claude Code 2.1.238, bare stdout from a SubagentStart hook → the subagent
# answered NO-MARKER; the same text in hookSpecificOutput.additionalContext →
# the marker came back. See docs/plans/P086-subagent-protocol-probe.md.
#
# WHAT IS NOT PROVED HERE: that the subagent acts on the notice. Degree 3 is a
# delivery, and no test can turn one into a guarantee.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TMP="$(mktemp -d)"
  ROOT="$TMP/checkout"
  mkdir -p "$ROOT/plugins/aid-orchestrator/agents"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf 'seed\n' > README.md
    git add -A && git commit -q -m seed
  )
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/scripts/lib/aid-subagent-protocol.sh"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

live_role() { printf '%s' "$1" > "$ROOT/plugins/aid-orchestrator/agents/auditor.md"; }

rule() { run bash -c "printf '%s' '$1' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-subagent-protocol.sh\"; aid_hook_rule_subagent_protocol'"; }

@test "a diverged protocol produces the notice, with both paths" {
  live_role "# Auditor — this checkout's version, which differs"
  rule "{\"agent_type\":\"aid-orchestrator:auditor\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIFFER from this repository's copy"* ]]
  [[ "$output" == *"$PLUGIN_ROOT/agents/auditor.md"* ]]
  [[ "$output" == *"$ROOT/plugins/aid-orchestrator/agents/auditor.md"* ]]
}

@test "the notice is a POINTER — the role file's contents are never injected" {
  # Not a style preference: injecting a working tree's file into an agent's
  # instructions would let a checkout write them.
  live_role "# Auditor
SECRET-SENTINEL-DO-NOT-INJECT: this line must never reach a prompt."
  rule "{\"agent_type\":\"aid-orchestrator:auditor\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SECRET-SENTINEL-DO-NOT-INJECT"* ]]
}

@test "identical copies say nothing at all" {
  cp "$PLUGIN_ROOT/agents/auditor.md" "$ROOT/plugins/aid-orchestrator/agents/auditor.md"
  rule "{\"agent_type\":\"aid-orchestrator:auditor\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"matches the repository's"* ]]
}

@test "a checkout with no agents directory is not a divergence" {
  rm -rf "$ROOT/plugins"
  rule "{\"agent_type\":\"aid-orchestrator:auditor\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"carries no plugins/aid-orchestrator/agents"* ]]
}

@test "a subagent that is not one of AID's roles is left alone" {
  live_role "# different"
  rule "{\"agent_type\":\"general-purpose\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not an AID role agent"* ]]
}

@test "a role name that is not a role name is refused, not looked up" {
  rule "{\"agent_type\":\"aid-orchestrator:../../etc/passwd\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"unusable role name"* ]]
}

@test "an unknown role has no installed protocol to compare" {
  mkdir -p "$ROOT/plugins/aid-orchestrator/agents"
  printf 'x\n' > "$ROOT/plugins/aid-orchestrator/agents/nosuchrole.md"
  rule "{\"agent_type\":\"aid-orchestrator:nosuchrole\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no installed protocol"* ]]
}

@test "a cwd outside any checkout is not applicable" {
  rule "{\"agent_type\":\"aid-orchestrator:auditor\",\"cwd\":\"$TMP\"}"
  [ "$status" -eq 3 ]
}

@test "the dispatcher wraps an injection in the envelope the probe measured" {
  # Bare stdout from SubagentStart ran, succeeded and delivered nothing. This
  # asserts the wrapping, since that is what makes the rule worth having.
  live_role "# Auditor — diverged"
  printf '{"agent_type":"aid-orchestrator:auditor","cwd":"%s"}' "$ROOT" > "$TMP/event.json"
  run bash -c "AID_HOOK_AUDIT='$TMP/a.jsonl' bash '$PLUGIN_ROOT/scripts/aid-hook.sh' SubagentStart < '$TMP/event.json' > '$TMP/out.json'"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' "$TMP/out.json")" = "SubagentStart" ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' "$TMP/out.json")" == *"DIFFER from this repository"* ]]
}
