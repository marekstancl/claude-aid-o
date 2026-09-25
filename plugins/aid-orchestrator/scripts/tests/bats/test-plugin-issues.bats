#!/usr/bin/env bats
# aid-tier: t0
# The project's record of AID's own defects: the file exists from the first
# run on, the Stop-hook reminder speaks only when AID refused or was bypassed
# and nothing was written, and the owner's collector lists the entries nobody
# has decided — and writes nothing.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  REPO="$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  T="$(mktemp -d)"; export AID_SESSION_STORE="$T/store"
  mkdir -p "$T/proj/.aid-o/work/plan-state" "$T/proj/.aid-o/work/evidence/E-1/R-1"
  git -C "$T/proj" init -q   # a real workspace is a git checkout; aid_state_root resolves from it
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plugin-issues.sh"
}
teardown() { rm -rf "$T"; }

_stop() { jq -n --arg c "$T/proj" --arg t "$T/transcript.jsonl" '{session_id:"s1",cwd:$c,transcript_path:$t,stop_hook_active:false}'; }
_transcript_started_at() { printf '{"type":"user","timestamp":"%s"}\n' "$1" > "$T/transcript.jsonl"; }

@test "ensure creates the file from the template with the rules in its header, and leaves an existing file alone" {
  run aid_plugin_issues_ensure "$T/proj"
  [ "$status" -eq 0 ]; [[ "$output" == *"created"* ]]
  grep -q '^# Problems with the AID plugin' "$T/proj/.aid-o/work/aid-plugin-issues.md"
  grep -q 'When to write here' "$T/proj/.aid-o/work/aid-plugin-issues.md"
  local v; v="$(jq -r .version "$AID_PLUGIN_PATH/.claude-plugin/plugin.json")"
  grep -q "created by aid-orchestrator v${v} on $(date -u +%Y-%m-%d)" "$T/proj/.aid-o/work/aid-plugin-issues.md"
  ! grep -q '{{PLUGIN_VERSION}}' "$T/proj/.aid-o/work/aid-plugin-issues.md"
  printf '### 1. something\n' >> "$T/proj/.aid-o/work/aid-plugin-issues.md"
  run aid_plugin_issues_ensure "$T/proj"
  [ -z "$output" ]
  [ "$(aid_plugin_issues_count "$T/proj/.aid-o/work/aid-plugin-issues.md")" = "1" ]
}

@test "reminder: silent when nothing was refused this session" {
  aid_plugin_issues_ensure "$T/proj" 2>/dev/null
  _transcript_started_at "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "reminder: speaks once when AID was bypassed and the file did not change; a new refusal re-opens it; a write silences it" {
  aid_plugin_issues_ensure "$T/proj" 2>/dev/null
  touch -d '-2 hours' "$T/proj/.aid-o/work/aid-plugin-issues.md"
  _transcript_started_at "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"fsm_force_override","epic_id":"E-1"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/proj/.aid-o/work/audit-log.jsonl"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [ "$status" -eq 0 ]; [[ "$output" == *"1 time(s)"* && "$output" == *"aid-plugin-issues.md has no new entry"* ]]
  [[ "$output" == *"this is plugin v$(jq -r .version "$AID_PLUGIN_PATH/.claude-plugin/plugin.json")"* ]]
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [ -z "$output" ]                                                     # said once
  printf '{"ts":"%s","event":"fsm_increment_fail","step":"2"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/proj/.aid-o/work/evidence/E-1/R-1/timeline.jsonl"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [[ "$output" == *"2 time(s)"* ]]                                     # more happened → again
  printf '### 1. the FSM refused a valid step\n' >> "$T/proj/.aid-o/work/aid-plugin-issues.md"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [ -z "$output" ]                                                     # written this session
}

@test "reminder: a force written to BOTH the audit log and a timeline counts once" {
  aid_plugin_issues_ensure "$T/proj" 2>/dev/null
  touch -d '-2 hours' "$T/proj/.aid-o/work/aid-plugin-issues.md"
  _transcript_started_at "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"fsm_force_override"}\n' "$now" > "$T/proj/.aid-o/work/audit-log.jsonl"
  printf '{"ts":"%s","event":"fsm_force_override"}\n' "$now" > "$T/proj/.aid-o/work/evidence/E-1/R-1/timeline.jsonl"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [[ "$output" == *" 1 time(s)"* ]]
}

@test "reminder: an old refusal from before this session does not count" {
  aid_plugin_issues_ensure "$T/proj" 2>/dev/null
  _transcript_started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"fsm_force_override"}\n' "$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ)" > "$T/proj/.aid-o/work/audit-log.jsonl"
  run aid_hook_rule_plugin_issues_reminder <<< "$(_stop)"
  [ -z "$output" ]
}

@test "the hook registry carries the reminder rule pointing at this lib" {
  run yq -r '.rules[] | select(.id == "plugin_issues_reminder") | .lib + " " + .handler + " " + (.degree|tostring)' "$AID_PLUGIN_PATH/defaults/hook-registry.yaml"
  [ "$output" = "scripts/lib/aid-plugin-issues.sh aid_hook_rule_plugin_issues_reminder 3" ]
}

@test "collector: lists every open entry per project with its line, and writes no file anywhere" {
  mkdir -p "$T/projects/alpha/.aid-o/work" "$T/projects/beta/.aid-o/work" "$T/projects/gamma/.aid-o/work"
  cat > "$T/projects/alpha/.aid-o/work/aid-plugin-issues.md" <<'EOF'
# Problems

## 2026-08-27, run

### 1. gate refused a valid plan
> **HOTOVO v2.95.2 (2026-08-29):** fixed

### 2. init crashed on $6
> **PŘEVZATO 2026-09-01 (aid-orchestrator)**

what happened here

### 3. message lied
body three

### 4. review took a third round
> **ČEKÁ NA DŮKAZ (2026-09-25):** guess · proof needed · when

**Další výskyt:** 2026-09-30 · beta · again
EOF
  printf '# Problems\n\n## 1. only one, at level two\nbody\n' > "$T/projects/beta/.aid-o/work/aid-plugin-issues.md"
  printf '# Problems\n\nno headings at all\n' > "$T/projects/gamma/.aid-o/work/aid-plugin-issues.md"
  local before; before="$(find "$T/projects" -type f -exec sha256sum {} + | sort)"
  run bash "$REPO/bin/aid-plugin-issues-collect.sh" --root "$T/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line 8: 2. init crashed on \$6"* ]]      # PŘEVZATO alone is still open
  [[ "$output" == *"line 13: 3. message lied"* ]]
  [[ "$output" != *"gate refused"* ]]                          # decided
  [[ "$output" != *"2026-08-27, run"* ]]                       # a container, not an entry
  [[ "$output" == *"line 3: 1. only one, at level two"* ]]
  [[ "$output" == *"gamma: nothing open"* ]]
  [[ "$output" == *"open entries: 3, waiting for evidence: 1"* ]]
  [[ "$output" == *"čeká na důkaz:"*"line 16: 4. review took a third round (výskytů: 2) -> posoudit znovu"* ]]
  [ "$(find "$T/projects" -type f -exec sha256sum {} + | sort)" = "$before" ]
}
