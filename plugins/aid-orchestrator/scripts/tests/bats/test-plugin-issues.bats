#!/usr/bin/env bats
# aid-tier: t0
# The project's record of AID's own defects: the file exists from the first
# run on, the Stop-hook reminder speaks only when AID refused or was bypassed
# and nothing was written, and the owner's collector takes unmarked entries
# once and marks them.

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

@test "collector: takes unmarked entries once, marks them in place, skips marked ones, deletes nothing" {
  mkdir -p "$T/projects/alpha/.aid-o/work" "$T/projects/beta/.aid-o/work"
  cat > "$T/projects/alpha/.aid-o/work/aid-plugin-issues.md" <<'EOF'
# Problems

## 2026-08-27, run

### 1. gate refused a valid plan
> **HOTOVO v2.95.2 (2026-08-29):** fixed

### 2. init crashed on $6
**Date:** 2026-08-27
what happened here

### 3. message lied
body three
EOF
  printf '# Problems\n\n## 1. only one, at level two\nbody\n' > "$T/projects/beta/.aid-o/work/aid-plugin-issues.md"
  HOME_INBOX="$T/repo"; mkdir -p "$HOME_INBOX/bin" "$HOME_INBOX/docs/plans"
  cp "$REPO/bin/aid-plugin-issues-collect.sh" "$HOME_INBOX/bin/"
  run bash "$HOME_INBOX/bin/aid-plugin-issues-collect.sh" --root "$T/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha: 2 entries taken"* && "$output" == *"beta: 1 entry taken"* ]]
  grep -c 'PŘEVZATO' "$T/projects/alpha/.aid-o/work/aid-plugin-issues.md" | grep -qx 2
  grep -q '^### 1. gate refused' "$T/projects/alpha/.aid-o/work/aid-plugin-issues.md"   # nothing deleted
  grep -q 'HOTOVO v2.95.2' "$T/projects/alpha/.aid-o/work/aid-plugin-issues.md"
  grep -q '#### alpha — 2. init crashed' "$HOME_INBOX/docs/plans/plugin-issues-inbox.md"
  grep -q '#### beta — 1. only one' "$HOME_INBOX/docs/plans/plugin-issues-inbox.md"
  grep -q 'what happened here' "$HOME_INBOX/docs/plans/plugin-issues-inbox.md"
  run bash "$HOME_INBOX/bin/aid-plugin-issues-collect.sh" --root "$T/projects"
  [[ "$output" == *"nothing new across 2 project(s)"* ]]
}

@test "collector: an entry that is only a heading at the end of the file is taken once, not on every run" {
  mkdir -p "$T/projects/gamma/.aid-o/work" "$T/repo/bin" "$T/repo/docs/plans"
  printf '# Problems\n\n### 1. bare heading at EOF' > "$T/projects/gamma/.aid-o/work/aid-plugin-issues.md"
  cp "$REPO/bin/aid-plugin-issues-collect.sh" "$T/repo/bin/"
  run bash "$T/repo/bin/aid-plugin-issues-collect.sh" --root "$T/projects"
  [[ "$output" == *"gamma: 1 entry taken"* ]]
  grep -q 'PŘEVZATO' "$T/projects/gamma/.aid-o/work/aid-plugin-issues.md"
  run bash "$T/repo/bin/aid-plugin-issues-collect.sh" --root "$T/projects"
  [[ "$output" == *"nothing new"* ]]
}
