#!/usr/bin/env bash
# =============================================================================
# lib/aid-plugin-issues.sh — the project's record of AID's OWN defects
#
# One file per project: <state root>/.aid-o/work/aid-plugin-issues.md. Agents
# and the controller write to it when AID misbehaves (rule: skills/agent-
# protocol.md §"Problems with AID itself"); the plugin owner collects the files
# across projects. Nothing here enforces writing — a missed entry costs nothing.
# What this lib does:
#   aid_plugin_issues_ensure  — the file EXISTS (created from the template with
#                               the rules in its header) at plan-start and at
#                               every EPIC init; an existing file gets used, a
#                               missing one does not.
#   aid_plugin_issues_count   — how many numbered entries the file carries.
#   aid_hook_rule_plugin_issues_reminder — Stop-hook REMINDER (degree 3, never
#                               a refusal): when this session saw AID refuse
#                               or get bypassed (force / amend-scope / a
#                               precondition failure in a timeline) and the
#                               file has not changed since the session began,
#                               say so once — and again only if more happened.
# =============================================================================
[[ -n "${_AID_PLUGIN_ISSUES_SH_LOADED:-}" ]] && return 0
_AID_PLUGIN_ISSUES_SH_LOADED=1

_AID_PI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_PI_LIB_DIR}/aid-roots.sh"

AID_PLUGIN_ISSUES_REL=".aid-o/work/aid-plugin-issues.md"

# aid_plugin_issues_path [root] — the file, state-root resolved.
aid_plugin_issues_path() {
  if [[ -n "${1:-}" ]]; then printf '%s/%s' "${1%/}" "$AID_PLUGIN_ISSUES_REL"; return 0; fi
  aid_state_path "$AID_PLUGIN_ISSUES_REL" 2>/dev/null || printf '%s' "$AID_PLUGIN_ISSUES_REL"
}

# aid_plugin_issues_ensure [root] — create the file from the template when
# absent. Prints one line on stderr when it creates; never fails the caller.
aid_plugin_issues_ensure() {
  local f; f="$(aid_plugin_issues_path "${1:-}")"
  [[ -f "$f" ]] && return 0
  local tpl="${_AID_PI_LIB_DIR}/../../defaults/templates/aid-plugin-issues.md"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  if [[ -r "$tpl" ]]; then cp "$tpl" "$f" 2>/dev/null || return 0
  else printf '# Problems with the AID plugin\n\n<!-- entries below, newest last -->\n' > "$f" 2>/dev/null || return 0
  fi
  echo "aid-plugin-issues: created ${f} — AID's own defects go there, not into the project backlog (rules in its header)" >&2
  return 0
}

# aid_plugin_issues_count <file> — numbered entries ("## 3." or "### 3.").
aid_plugin_issues_count() {
  [[ -f "${1:-}" ]] || { echo 0; return 0; }
  grep -cE '^#{2,3} [0-9]+\. ' "$1" 2>/dev/null || echo 0
}

# _aid_pi_signals <root> <since_epoch> — how many times AID refused or was
# bypassed since <since>: force/amend records in the audit log, and
# precondition/advance failures in every run timeline. Read-only.
_aid_pi_signals() {
  local root="$1" since="$2" n=0 f
  local audit="${root}/.aid-o/work/audit-log.jsonl"
  # Bypasses come from the audit log ONLY and refusals from the timelines ONLY:
  # force/amend are written to both, and counting both counted them twice.
  local q_audit='select((.event // "") | (. == "fsm_force_override" or . == "scope_amended" or . == "plan_force"))
      | ((.ts // "1970-01-01T00:00:00Z") | (try fromdateiso8601 catch 0)) | select(. >= $s) | 1'
  local q_timeline='select((.event // "") | (test("^fsm_.*(fail|blocked)$") or . == "plan_readiness_blocked"))
      | ((.ts // "1970-01-01T00:00:00Z") | (try fromdateiso8601 catch 0)) | select(. >= $s) | 1'
  if [[ -f "$audit" ]]; then
    n=$(( n + $(jq -r --argjson s "$since" "$q_audit" "$audit" 2>/dev/null | wc -l) ))
  fi
  while IFS= read -r f; do
    n=$(( n + $(jq -r --argjson s "$since" "$q_timeline" "$f" 2>/dev/null | wc -l) ))
  done < <(find "${root}/.aid-o/work/evidence" -mindepth 3 -maxdepth 3 -name timeline.jsonl 2>/dev/null)
  echo "$n"
}

# aid_hook_rule_plugin_issues_reminder — Stop handler (see header).
aid_hook_rule_plugin_issues_reminder() {
  local input; input="$(cat)"
  local cwd transcript session
  IFS=$'\x1f' read -r cwd transcript session < <(jq -r '[.cwd // "", .transcript_path // "", .session_id // ""] | join("")' <<< "$input" 2>/dev/null)
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  local root; root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }
  local since=0
  if [[ -n "$transcript" && -r "$transcript" ]]; then
    local ts; ts="$(head -c 65536 "$transcript" 2>/dev/null | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | head -1)"
    [[ -n "$ts" ]] && since="$(date -u -d "$ts" +%s 2>/dev/null || echo 0)"
  fi
  local n; n="$(_aid_pi_signals "$root" "$since")"
  [[ "$n" -gt 0 ]] || return 0
  local f; f="$(aid_plugin_issues_path "$root")"
  if [[ -f "$f" && "$since" -gt 0 ]]; then
    local mtime; mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    [[ "$mtime" -ge "$since" ]] && return 0   # written this session — no nagging
  fi
  # once per session per count: a later refusal re-opens the reminder
  local mark=""
  if declare -F aid_session_store_dir >/dev/null 2>&1 || source "${_AID_PI_LIB_DIR}/aid-session-store.sh" 2>/dev/null; then
    local dir; dir="$(aid_session_store_dir plugin-issues 2>/dev/null)" || dir=""
    [[ -n "$dir" ]] && mark="${dir}/reminded-${session:-nosession}-${n}"
    [[ -n "$mark" && -f "$mark" ]] && return 0
  fi
  # "since this session began", not "this session did": a parallel session on
  # the same project is counted too — the reminder is a nudge, not a charge.
  printf 'AID: since this session began, AID refused or was bypassed %s time(s) in this project (force, amend-scope, or a precondition failure) and %s has no new entry. If any of that was a defect of the PLUGIN — a valid state refused, a crash, a misleading message — record it there (format in its header). A defect of the project is not one; then nothing to do.\n' \
    "$n" "${f#"${root}"/}"
  [[ -n "$mark" ]] && : > "$mark" 2>/dev/null
  return 0
}
