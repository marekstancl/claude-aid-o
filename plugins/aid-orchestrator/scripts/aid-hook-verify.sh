#!/usr/bin/env bash
# =============================================================================
# aid-hook-verify.sh — the only thing allowed to say "AID's hooks run here"
# (P086 Step 2)
#
#   aid-hook-verify.sh --canary [--tool auto|claude-code|codex] [--timeout <s>]
#   aid-hook-verify.sh --status [--json]
#   aid-hook-verify.sh --seed-trust            (Codex only)
#
# WHY THIS EXISTS
#   /ecosystem/specs/agent-hooks/ opens with "ověření, ne víra": a hook is not
#   deployed when its file is in place, it is deployed when the tool has been
#   asked and answered. Both tools fail SILENTLY and in opposite directions —
#   Codex skips an unapproved hook without a word, Claude Code runs a broken
#   one and continues as if nothing happened. Either way the layer looks fine
#   from outside.
#
#   So this runs a real session, requires AID's own canary rule to have LEFT
#   ITS RECORD, and writes the verdict where the dispatcher reads it. Nothing
#   else in AID may claim hooks are in force; everything else cites this.
#
# THE VERDICT HAS A MECHANICAL EFFECT, NOT A RHETORICAL ONE
#   `scripts/aid-hook.sh` reads the verdict file and degrades EVERY fail-closed
#   rule to fail-open while it says anything other than verified. A negative
#   canary therefore un-blocks work rather than blocking it: refusing to run
#   because a mechanism could not be shown to work is the worse failure.
#
# THE VERSION IS PART OF THE CLAIM
#   The tool version is recorded with every verdict. When it is not the version
#   the ecosystem sheet was measured on, the verdict still stands for what this
#   run OBSERVED — it just may not borrow the rest of the sheet's matrix (which
#   run modes send which events), and says so.
#
# WHAT IT COSTS
#   One short non-interactive session of the tool. This is a deployment check
#   an operator runs, not something in any turn's hot path — the hook itself
#   never calls a model (/ecosystem/specs/agent-hooks/ rule 6).
#
# EXIT CODES
#   0  verified — a hook of AID's really ran and succeeded
#   1  not verified — measured and negative, or not measurable here. The
#      verdict is written either way; a missing tool is this, never a crash.
#   2  usage error
#
# **Last Updated:** 2026-08-24
# =============================================================================
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/aid-session-store.sh
source "${PLUGIN_ROOT}/scripts/lib/aid-session-store.sh"

REGISTRY="${AID_HOOK_REGISTRY:-${PLUGIN_ROOT}/defaults/hook-registry.yaml}"
CANARY_RULE="hook_canary"

trust_file() {
  if [[ -n "${AID_HOOK_TRUST_FILE:-}" ]]; then
    printf '%s\n' "$AID_HOOK_TRUST_FILE"; return 0
  fi
  local dir; dir="$(aid_session_store_dir hooks)" || return 1
  printf '%s/trust.json\n' "$dir"
}

# write_verdict <verified> <tool> <version> <state> <detail> [sources_json] [events_json]
#
# One writer, so no caller can invent a verdict shape. `state` is the honest
# distinction the plan asks for: "not measurable here" and "measured and
# negative" are different facts and must not collapse into one word.
write_verdict() {
  local verified="$1" tool="$2" version="$3" state="$4" detail="$5"
  local sources="${6:-[]}" events="${7:-[]}"
  local file; file="$(trust_file)" || return 1
  local measured unmeasured=false
  measured="$(yq -r ".measured_versions.\"${tool}\" // \"\"" "$REGISTRY" 2>/dev/null)"
  [[ -n "$measured" && "$measured" != "$version" ]] && unmeasured=true
  jq -n --argjson verified "$verified" --arg tool "$tool" --arg version "$version" \
        --arg state "$state" --arg detail "$detail" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg measured "$measured" --argjson unmeasured "$unmeasured" \
        --argjson sources "$sources" --argjson events "$events" \
    '{verified: $verified, tool: $tool, version: $version, state: $state,
      detail: $detail, checked_at: $at,
      measured_version: $measured, unmeasured_version: $unmeasured,
      config_sources: $sources, covered_events: $events}' > "$file"
}

tool_version() { # tool_version <binary> — first version-looking token, or "unknown"
  local v; v="$("$1" --version 2>/dev/null | head -1)"
  v="$(printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  printf '%s' "${v:-unknown}"
}

detect_tool() {
  case "${AID_HOOK_TOOL:-auto}" in
    claude-code|codex) printf '%s' "$AID_HOOK_TOOL"; return 0 ;;
  esac
  command -v claude >/dev/null 2>&1 && { printf 'claude-code'; return 0; }
  command -v codex  >/dev/null 2>&1 && { printf 'codex'; return 0; }
  printf 'none'
}

# _canary_hits <audit_file> — how many times AID's canary rule ran AND
# SUCCEEDED. The distinction matters more than it looks: the dispatcher writes
# an audit line for a canary that CRASHED too, so counting lines would let a
# broken hook layer certify itself. The canary's contract is exit 3, which the
# dispatcher records as `skip`; anything else (error, timeout, disabled) is
# a canary that did not do its job.
_canary_hits() {
  local file="$1"
  [[ -r "$file" ]] || { printf '0'; return 0; }
  local n
  n="$(jq -rs --arg r "$CANARY_RULE" \
        '[.[] | select(.rule == $r and .outcome == "skip")] | length' "$file" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# --------------------------------------------------------------------------
# Claude Code. Two independent pieces of evidence, because either alone lies:
# the event stream says a hook ran and did not error, and AID's own audit line
# says the hook that ran was OURS. The stream is available because
# `--include-hook-events` emits hook_started/hook_response pairs; the audit
# line is available because a hook inherits the caller's environment
# (/ecosystem/specs/agent-hooks/ rule 9), so AID_HOOK_AUDIT reaches it.
# --------------------------------------------------------------------------
canary_claude_code() {
  local timeout_s="$1" version; version="$(tool_version claude)"
  local tmp; tmp="$(mktemp -d)" || { write_verdict false claude-code "$version" failed "no temp dir for the canary run"; return 1; }
  local audit="${tmp}/canary.jsonl" stream="${tmp}/stream.jsonl" rc=0

  AID_HOOK_AUDIT="$audit" timeout "$timeout_s" \
    claude -p "Reply with the single word: ok" \
      --output-format stream-json --include-hook-events --verbose \
      > "$stream" 2>"${tmp}/err" || rc=$?

  if [[ "$rc" -ne 0 && ! -s "$stream" ]]; then
    write_verdict false claude-code "$version" failed \
      "the canary session did not run (exit ${rc}): $(tr '\n' ' ' < "${tmp}/err" | cut -c1-200)"
    rm -rf "$tmp"; return 1
  fi

  local ran_ok errored ours events
  ran_ok="$(jq -rs '[.[] | select(.subtype=="hook_response" and .outcome=="success")] | length' "$stream" 2>/dev/null || echo 0)"
  errored="$(jq -rs '[.[] | select(.subtype=="hook_response" and .outcome!="success") | .hook_name] | unique | join(", ")' "$stream" 2>/dev/null || echo "")"
  ours="$(_canary_hits "$audit")"
  events="$(jq -rs '[.[] | select(.subtype=="hook_response") | .hook_name] | unique' "$stream" 2>/dev/null || echo '[]')"
  [[ -n "$events" ]] || events='[]'

  # Which configuration sources this installation actually reads. Claude Code
  # SUMS them rather than letting one win, so naming them is part of the
  # verdict: a hook can arrive from a repository someone else wrote.
  local sources; sources="$(claude_config_sources)"

  if (( ours == 0 )); then
    if (( ran_ok > 0 )); then
      write_verdict false claude-code "$version" not_covered \
        "hooks run here, but no AID rule was among them — the plugin's hooks/hooks.json is not loaded in this installation" \
        "$sources" "$events"
    else
      write_verdict false claude-code "$version" not_covered \
        "the canary session produced no successful hook at all${errored:+ (errored: ${errored})}" \
        "$sources" "$events"
    fi
    rm -rf "$tmp"; return 1
  fi

  write_verdict true claude-code "$version" verified \
    "AID's canary rule ran and the session reported ${ran_ok} successful hook response(s)" \
    "$sources" "$events"
  rm -rf "$tmp"
  return 0
}

# Which settings files this installation would read. Presence, not contents —
# the verdict names where a hook could come from, it does not audit them.
claude_config_sources() {
  local -a found=()
  local user_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [[ -f "${user_dir}/settings.json" ]] && found+=("user:${user_dir}/settings.json")
  local repo; repo="$(git rev-parse --show-toplevel 2>/dev/null)" || repo=""
  if [[ -n "$repo" ]]; then
    [[ -f "${repo}/.claude/settings.json" ]] && found+=("project:${repo}/.claude/settings.json")
    [[ -f "${repo}/.claude/settings.local.json" ]] && found+=("local:${repo}/.claude/settings.local.json")
  fi
  if [[ ${#found[@]} -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${found[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# --------------------------------------------------------------------------
# Codex. Trust FIRST — an unapproved hook is skipped without a word, so a
# session that "worked" proves nothing until the trust states are known — then
# the same two-evidence run as above.
#
# `untrusted` AND `modified` are both refused. Checking only `untrusted` lets
# an EDITED hook through, which is the trap the ecosystem sheet names.
# `--dangerously-bypass-hook-trust` is never used (rule 4).
# --------------------------------------------------------------------------
canary_codex() {
  local timeout_s="$1" version; version="$(tool_version codex)"
  local helper="${PLUGIN_ROOT}/scripts/lib/aid-codex-hook-trust.py"

  if ! command -v python3 >/dev/null 2>&1; then
    write_verdict false codex "$version" failed "python3 is required to ask Codex for its hook trust states"
    return 1
  fi

  local states rc=0
  states="$(python3 "$helper" check 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    write_verdict false codex "$version" failed "could not read Codex hook trust: $(printf '%s' "$states" | tr '\n' ' ' | cut -c1-200)"
    return 1
  fi

  local bad; bad="$(printf '%s' "$states" | jq -r '[.[] | select(.trustStatus=="untrusted" or .trustStatus=="modified") | "\(.key)=\(.trustStatus)"] | join(", ")')"
  if [[ -n "$bad" ]]; then
    write_verdict false codex "$version" "$( [[ "$bad" == *modified* ]] && echo modified || echo untrusted )" \
      "Codex will silently skip these hooks until they are approved: ${bad}. Approve them with: aid-hook-verify.sh --seed-trust"
    return 1
  fi

  local tmp; tmp="$(mktemp -d)" || { write_verdict false codex "$version" failed "no temp dir for the canary run"; return 1; }
  local audit="${tmp}/canary.jsonl" erc=0
  AID_HOOK_AUDIT="$audit" timeout "$timeout_s" \
    codex exec "Reply with the single word: ok" > "${tmp}/out" 2>"${tmp}/err" || erc=$?

  local ours; ours="$(_canary_hits "$audit")"
  if (( ours == 0 )); then
    write_verdict false codex "$version" not_covered \
      "every declared hook is trusted, but no AID rule left a record in this run (exit ${erc}) — AID's hooks are not among the ones this installation loads"
    rm -rf "$tmp"; return 1
  fi

  write_verdict true codex "$version" verified \
    "every declared hook is trusted or managed, and AID's canary rule left its record" \
    '[]' '["SessionStart"]'
  rm -rf "$tmp"
  return 0
}

cmd_canary() {
  local timeout_s="${1:-120}"
  local tool; tool="$(detect_tool)"
  case "$tool" in
    claude-code) canary_claude_code "$timeout_s" ;;
    codex)       canary_codex "$timeout_s" ;;
    *)
      # A missing tool is a verdict, not a crash: the layer degrades and work
      # continues.
      write_verdict false none unknown tool_missing \
        "neither 'claude' nor 'codex' is on PATH here — nothing could be measured, so no fail-closed rule is in force"
      return 1
      ;;
  esac
}

cmd_status() {
  local file; file="$(trust_file)" || return 1
  if [[ ! -f "$file" ]]; then
    echo "NO VERDICT — the canary has never run here. Every fail-closed hook rule is degraded to fail-open." >&2
    echo "Run: aid-hook-verify.sh --canary" >&2
    return 1
  fi
  if [[ "${1:-}" == "--json" ]]; then
    cat "$file"; [[ "$(jq -r '.verified' "$file")" == "true" ]]; return $?
  fi
  jq -r '"tool:      \(.tool) \(.version)\nverdict:   \(if .verified then "VERIFIED" else "NOT VERIFIED" end) (\(.state))\ndetail:    \(.detail)\nchecked:   \(.checked_at)\nmeasured:  \(if .unmeasured_version then "this version is NOT the one the ecosystem sheet was measured on (\(.measured_version)) — the run modes and events beyond the one observed here are unverified for it" else "matches the measured ecosystem sheet" end)"' "$file"
  [[ "$(jq -r '.verified' "$file")" == "true" ]]
}

cmd_seed_trust() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: --seed-trust is a Codex operation and 'codex' is not on PATH." >&2
    return 2
  fi
  python3 "${PLUGIN_ROOT}/scripts/lib/aid-codex-hook-trust.py" seed
}

main() {
  local timeout_s=120 action="" json_out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --canary)     action=canary; shift ;;
      --status)     action=status; shift ;;
      --seed-trust) action=seed; shift ;;
      --json)       json_out=--json; shift ;;
      --tool)       AID_HOOK_TOOL="${2:-}"; export AID_HOOK_TOOL; shift 2 ;;
      --timeout)    timeout_s="${2:-120}"; shift 2 ;;
      *) echo "Usage: aid-hook-verify.sh --canary [--tool auto|claude-code|codex] [--timeout <s>] | --status [--json] | --seed-trust" >&2; return 2 ;;
    esac
  done
  case "$action" in
    canary) cmd_canary "$timeout_s" ;;
    status) cmd_status "$json_out" ;;
    seed)   cmd_seed_trust ;;
    *) echo "Usage: aid-hook-verify.sh --canary [--tool auto|claude-code|codex] [--timeout <s>] | --status [--json] | --seed-trust" >&2; return 2 ;;
  esac
}

main "$@"
