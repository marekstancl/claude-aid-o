#!/usr/bin/env bash
# =============================================================================
# aid-hook.sh — the one place AID talks to a harness hook (P086 Step 1)
#
#   aid-hook.sh <event>              run every rule registered for <event>
#                                    (event JSON on stdin)
#   aid-hook.sh --run-rule <id> <event>
#                                    run ONE rule; the form the dispatcher
#                                    itself uses so `timeout` can wrap a rule
#                                    that is otherwise just a bash function
#   aid-hook.sh --self-test          dispatch a built-in fixture end to end
#
# WHY THIS EXISTS
#   AID had 31 harness events available and used none of them: everything it
#   "enforced" on the model side was enforced by asking. This is the layer
#   that gives a rule a mechanism. It sits BESIDE the FSM, not inside it — a
#   hook runs in the hot path of every turn, must not write into the
#   repository (/ecosystem/specs/agent-hooks/ rule 6), and must stay dumb and
#   fast. It reads decision data from the workspace and changes no state.
#
# THE OUTPUT CONTRACT, WHICH IS THE HARNESS'S AND NOT OURS
#   stdout        injected into the model's prompt (degree 3 — delivery)
#   exit 0        proceed
#   exit 2        refuse, reason on stderr (degree 2 — the answer is checked)
#   anything else a broken hook. Claude Code does NOT block on it; the tool
#                 call proceeds. That is why a fail-closed rule denies with
#                 exit 2 rather than dying.
#
# WHAT IT DELIBERATELY DOES NOT DO
#   It never writes to `.aid-o/` or to any working tree. Its audit trail and
#   the canary verdict live in the session store (lib/aid-session-store.sh).
#   It never calls a model and never reaches the network.
#
# UNKNOWN EVENTS EXIT 0 AND SAY NOTHING. A harness must never break because
# AID does not know one of its events.
#
# CONTEXT DETECTION AND ITS MEASURED LIMIT
#   A rule declares an `owner` because plugin hooks run INSIDE subagents too.
#   Context is read as `agent` when the event JSON carries a non-empty
#   `agent_type`, when the event name starts with `Subagent`, or when
#   AID_HOOK_CONTEXT says so; otherwise `controller`. Known limit, stated
#   rather than hidden: a subagent invocation supplying neither signal is
#   indistinguishable from the controller here. The exposure is bounded —
#   controller-owned rules are read-only checks whose worst case in a
#   subagent is a redundant check — and fail-closed rules need the canary on
#   top.
#
# THE CANARY BINDING (Step 2)
#   `failure: closed` rows take effect only while the trust file records a
#   successful canary for this tool and version. Otherwise they degrade to
#   fail-open and the degradation is audited. See defaults/hook-registry.yaml.
#
# DEPENDENCIES: yq (registry), jq (event JSON). Either missing means no rule
# runs — never that all of them do.
#
# **Last Updated:** 2026-08-24
# =============================================================================
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/aid-session-store.sh
source "${PLUGIN_ROOT}/scripts/lib/aid-session-store.sh"

REGISTRY="${AID_HOOK_REGISTRY:-${PLUGIN_ROOT}/defaults/hook-registry.yaml}"

# --------------------------------------------------------------------------
# Audit. Append-only JSONL in the session store. Best effort by definition:
# a hook that cannot write its own audit line still must not break the turn.
# --------------------------------------------------------------------------
_hook_esc() {
  local s="${1-}"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"
  printf '%s' "$s"
}

_hook_audit() {
  local event="$1" rule="$2" outcome="$3" reason="${4-}"
  local file="${AID_HOOK_AUDIT:-}"
  if [[ -z "$file" ]]; then
    local dir; dir="$(aid_session_store_dir hooks)" || return 0
    file="${dir}/audit.jsonl"
  fi
  printf '{"ts":"%s","event":"%s","session_id":"%s","context":"%s","rule":"%s","outcome":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(_hook_esc "$event")" \
    "$(_hook_esc "${HOOK_SESSION_ID:-}")" "${HOOK_CONTEXT:-unknown}/${HOOK_CONTEXT_SOURCE:-unknown}" \
    "$(_hook_esc "$rule")" "$outcome" "$(_hook_esc "$reason")" \
    >> "$file" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# Trust: has the canary shown that hooks actually run here? (Step 2 writes
# the file; this only reads it, so Step 1 is complete on its own.)
# --------------------------------------------------------------------------
# A verdict is good for a bounded time, and here is the honest reason: this
# process cannot tell WHICH harness is calling it, so it cannot check that the
# tool and version in the verdict are still the ones running. What it can do is
# refuse to trust an old measurement indefinitely — a tool upgrade or a switch
# between harnesses stops being covered within the window rather than never.
# The residual gap is recorded in defaults/hook-registry.yaml; closing it needs
# a harness marker in the event payload that neither tool sends today.
_AID_HOOK_TRUST_TTL_DAYS_DEFAULT=7

_hook_trust_ok() {
  local file="${AID_HOOK_TRUST_FILE:-}"
  if [[ -z "$file" ]]; then
    local dir; dir="$(aid_session_store_dir hooks)" || return 1
    file="${dir}/trust.json"
  fi
  [[ -f "$file" ]] || return 1
  [[ "$(jq -r '.verified // false' "$file" 2>/dev/null)" == "true" ]] || return 1

  local ttl checked_at w now
  ttl="$(yq -r ".trust_ttl_days // ${_AID_HOOK_TRUST_TTL_DAYS_DEFAULT}" "$REGISTRY" 2>/dev/null)"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl="$_AID_HOOK_TRUST_TTL_DAYS_DEFAULT"
  checked_at="$(jq -r '.checked_at // ""' "$file" 2>/dev/null)"
  [[ -n "$checked_at" ]] || return 1
  w="$(date -u -d "$checked_at" +%s 2>/dev/null)" || return 1
  now="$(date -u +%s)"
  (( now - w <= ttl * 86400 ))
}

# --------------------------------------------------------------------------
# Context
# --------------------------------------------------------------------------
# Prints "<context>\t<how it was decided>". The second half is audited, so a
# context that was ASSUMED rather than read is visible in the trail instead of
# looking like a measurement.
_hook_detect_context() {
  local event="$1" input="$2" agent_type=""
  case "${AID_HOOK_CONTEXT:-}" in
    agent|controller) printf '%s\tenv' "$AID_HOOK_CONTEXT"; return 0 ;;
  esac
  [[ "$event" == Subagent* ]] && { printf 'agent\tevent'; return 0; }
  agent_type="$(printf '%s' "$input" | jq -r '.agent_type // .subagent_type // ""' 2>/dev/null)"
  [[ -n "$agent_type" ]] && { printf 'agent\tagent_type'; return 0; }
  printf 'controller\tassumed'
}

# --------------------------------------------------------------------------
# _hook_run_deadline <seconds> <out_file> <err_file> <cmd...>
#
# Runs one rule with a real clock and returns 124 when it overran, the rule's
# own exit code otherwise. Deliberately NOT `timeout(1)`:
#
#   - it is coreutils, and a host without it (stock macOS) would otherwise run
#     rules with no clock at all — a hot-path dispatcher cannot have that as a
#     supported mode;
#   - `timeout 0` DISABLES the timeout, so a malformed row would buy a rule
#     unlimited time (the seconds are validated by the caller, and this is the
#     second line of that defence);
#   - it kills the process it started, not the process group, so a handler that
#     leaves a background child holding the pipe hangs the reader for as long
#     as that child lives. Output goes to FILES here for exactly that reason:
#     a leaked child holding a file descriptor cannot keep the dispatcher
#     waiting for EOF.
#
# The child is killed with TERM and then, after a second's grace, with KILL.
# --------------------------------------------------------------------------
_hook_run_deadline() {
  local secs="$1" out="$2" err="$3"; shift 3
  "$@" > "$out" 2> "$err" &
  local pid=$!
  local waited=0
  # Tenth-of-a-second polling: a rule's budget is whole seconds, and a hook in
  # the hot path must not add a second of latency to a rule that returns at
  # once.
  while (( waited < secs * 10 )); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null
    sleep 1
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  local rc=0
  wait "$pid" || rc=$?
  return "$rc"
}

_hook_owner_matches() {
  local owner="$1"
  [[ "$owner" == "any" || "$owner" == "$HOOK_CONTEXT" ]]
}

# --------------------------------------------------------------------------
# Run one rule. Separate process so the dispatcher can put a real clock on it.
# Exit: 0 pass/inject, 2 deny, 3 not applicable, 1 broken.
# --------------------------------------------------------------------------
run_rule() {
  local rule_id="$1" event="$2" input=""
  input="$(cat)"

  local lib handler
  lib="$(yq -r ".rules[] | select(.id == \"${rule_id}\") | .lib // \"\"" "$REGISTRY" 2>/dev/null)"
  handler="$(yq -r ".rules[] | select(.id == \"${rule_id}\") | .handler // \"\"" "$REGISTRY" 2>/dev/null)"
  if [[ -z "$handler" ]]; then
    echo "rule '${rule_id}' declares no handler" >&2
    return 1
  fi
  if [[ -n "$lib" ]]; then
    # A `lib` is SOURCED, so the registry is executable code and its paths are
    # treated as such. Traversal is refused outright, and the SHIPPED registry
    # may only name paths inside the plugin — an absolute path is honoured only
    # from an explicitly overridden registry, which is a deliberate act by
    # whoever set AID_HOOK_REGISTRY (and per /ecosystem/specs/agent-hooks/
    # rule 3, anyone who can do that can already run code).
    if [[ "$lib" == *".."* ]]; then
      echo "rule '${rule_id}': lib path '${lib}' traverses upward — refused" >&2
      return 1
    fi
    if [[ "$lib" == /* ]]; then
      if [[ "$REGISTRY" == "${PLUGIN_ROOT}/defaults/hook-registry.yaml" ]]; then
        echo "rule '${rule_id}': the shipped registry may only name paths inside the plugin, not '${lib}'" >&2
        return 1
      fi
    else
      lib="${PLUGIN_ROOT}/${lib}"
    fi
    # shellcheck disable=SC1090
    source "$lib" || { echo "rule '${rule_id}': cannot source ${lib}" >&2; return 1; }
  fi
  if ! declare -F "$handler" >/dev/null; then
    echo "rule '${rule_id}': handler '${handler}' is not defined" >&2
    return 1
  fi
  AID_HOOK_EVENT="$event" "$handler" <<< "$input"
}

# --------------------------------------------------------------------------
# Dispatch every rule registered for one event.
# --------------------------------------------------------------------------
dispatch() {
  local event="$1" input="" ; input="$(cat)"
  HOOK_SESSION_ID="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"
  local _ctx; _ctx="$(_hook_detect_context "$event" "$input")"
  HOOK_CONTEXT="${_ctx%%$'\t'*}"
  HOOK_CONTEXT_SOURCE="${_ctx##*$'\t'}"

  if [[ "${AID_HOOKS_OFF:-}" == "1" ]]; then
    _hook_audit "$event" "*" hooks_off "AID_HOOKS_OFF=1"
    return 0
  fi
  if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    _hook_audit "$event" "*" error "yq or jq missing — no rule ran"
    return 0
  fi
  if [[ ! -r "$REGISTRY" ]] || ! yq -e '.rules' "$REGISTRY" >/dev/null 2>&1; then
    _hook_audit "$event" "*" error "registry unreadable at ${REGISTRY} — no rule ran"
    return 0
  fi

  local ids
  ids="$(yq -r ".rules[] | select(.event == \"${event}\") | .id" "$REGISTRY" 2>/dev/null)"
  [[ -n "$ids" ]] || return 0

  local default_timeout budget_total
  default_timeout="$(yq -r '.defaults.timeout_s // 5' "$REGISTRY")"
  budget_total="$(yq -r '.budget.total_s // 15' "$REGISTRY")"

  local trust_ok=0; _hook_trust_ok && trust_ok=1
  local injections="" denials="" denied=0
  local started=$SECONDS

  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue

    if (( SECONDS - started >= budget_total )); then
      _hook_audit "$event" "$id" skip "dispatch budget ${budget_total}s spent"
      continue
    fi

    local owner failure timeout_s disabled
    owner="$(yq -r ".rules[] | select(.id == \"${id}\") | .owner // \"\"" "$REGISTRY")"
    failure="$(yq -r ".rules[] | select(.id == \"${id}\") | .failure // \"open\"" "$REGISTRY")"
    timeout_s="$(yq -r ".rules[] | select(.id == \"${id}\") | .timeout_s // ${default_timeout}" "$REGISTRY")"
    # A row's clock is data, so it is checked like data. Non-numeric or zero
    # would buy the rule unlimited time; and no rule may outlive what is left
    # of the whole dispatch, or the total budget would be a number the code
    # prints rather than one it keeps.
    [[ "$timeout_s" =~ ^[0-9]+$ ]] && (( timeout_s >= 1 )) || timeout_s=1
    local remaining=$(( budget_total - (SECONDS - started) ))
    (( remaining < 1 )) && remaining=1
    (( timeout_s > remaining )) && timeout_s="$remaining"
    disabled="$(yq -r ".rules[] | select(.id == \"${id}\") | .disabled // false" "$REGISTRY")"

    if [[ "$disabled" == "true" ]]; then
      _hook_audit "$event" "$id" disabled "disabled: true in registry"; continue
    fi
    if [[ ",${AID_HOOKS_OFF_RULES:-}," == *",${id},"* ]]; then
      _hook_audit "$event" "$id" disabled "AID_HOOKS_OFF_RULES"; continue
    fi
    if [[ -z "$owner" ]]; then
      _hook_audit "$event" "$id" error "row declares no owner"; continue
    fi
    if ! _hook_owner_matches "$owner"; then
      _hook_audit "$event" "$id" skip "owner=${owner}, context=${HOOK_CONTEXT}"; continue
    fi
    # WHO MAY STOP A TURN, decided once per rule. `failure: closed` is the
    # ONLY declaration that can block, and only while the canary says hooks
    # demonstrably run here. A `failure: open` rule that exits 2 is a
    # misdeclaration, not a veto — it is recorded and ignored, because a rule
    # that can stop work has to say so in the registry where it can be read.
    local may_block=0
    if [[ "$failure" == "closed" ]]; then
      if (( trust_ok )); then
        may_block=1
      else
        _hook_audit "$event" "$id" degraded "fail-closed rule degraded to fail-open — no canary verdict"
      fi
    fi

    local tmpd="" out_f="" err_f="" out="" reason="" rc=0
    tmpd="$(mktemp -d)" || { _hook_audit "$event" "$id" error "no temp dir for the rule run"; continue; }
    out_f="${tmpd}/out"; err_f="${tmpd}/err"
    printf '%s' "$input" > "${tmpd}/in"
    _hook_run_deadline "$timeout_s" "$out_f" "$err_f" \
      bash "${BASH_SOURCE[0]}" --run-rule "$id" "$event" < "${tmpd}/in" || rc=$?
    [[ -s "$out_f" ]] && out="$(cat "$out_f")"
    [[ -s "$err_f" ]] && reason="$(tr '\n' ' ' < "$err_f")"
    rm -rf "$tmpd"

    case "$rc" in
      0)
        # A rule that succeeded may still have something to record — a capsule
        # it wrote, a path it chose. Its stderr is the audit reason, which is
        # why it is read on the success path too and not only on refusals.
        if [[ -n "$out" ]]; then
          injections+="${out}"$'\n'
          _hook_audit "$event" "$id" inject "$reason"
        else
          _hook_audit "$event" "$id" pass "$reason"
        fi
        ;;
      2)
        if (( may_block )); then
          denied=1; denials+="${reason}"$'\n'
          _hook_audit "$event" "$id" deny "$reason"
        elif [[ "$failure" == "closed" ]]; then
          _hook_audit "$event" "$id" deny_suppressed "no canary verdict — would have refused: ${reason}"
        else
          _hook_audit "$event" "$id" deny_ignored "rule is declared failure: open and may not refuse a turn — would have refused: ${reason}"
        fi
        ;;
      3)
        _hook_audit "$event" "$id" skip "$reason"
        ;;
      124)
        _hook_audit "$event" "$id" timeout "exceeded ${timeout_s}s"
        if (( may_block )); then
          denied=1; denials+="rule ${id} exceeded its ${timeout_s}s budget and is fail-closed"$'\n'
        fi
        ;;
      *)
        _hook_audit "$event" "$id" error "$reason"
        if (( may_block )); then
          denied=1; denials+="rule ${id} failed (${reason}) and is fail-closed"$'\n'
        fi
        ;;
    esac
  done <<< "$ids"

  if (( denied )); then
    printf '%s' "$denials" >&2
    return 2
  fi
  if [[ -n "$injections" ]]; then
    # THE ENVELOPE IS MEASURED, NOT ASSUMED (P086 Step 10, Claude Code 2.1.238).
    # A SubagentStart hook printing its text on BARE STDOUT ran, succeeded, and
    # delivered nothing — the subagent asked about the injected marker answered
    # NO-MARKER. The same run's SessionStart hook delivered its text through
    # `hookSpecificOutput.additionalContext`, and repeating the probe with that
    # envelope returned the marker. So every injection this dispatcher emits is
    # wrapped, once, here — not by each handler, because two handlers each
    # emitting their own JSON object would concatenate into nothing valid.
    #
    # An event that does not read `additionalContext` will show the JSON as
    # text: degraded, visible, and never a silent loss.
    jq -n --arg e "$event" --arg c "$injections" \
      '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
  fi
  return 0
}

# --------------------------------------------------------------------------
# Self-test (SC1): a throwaway registry and a throwaway rule, dispatched
# through the real path. It proves the layer runs; it says nothing about the
# rules that ship — those have their own suites.
# --------------------------------------------------------------------------
self_test() {
  local tmp; tmp="$(mktemp -d)" || return 1

  cat > "${tmp}/lib.sh" <<'RULE'
aid_hook_selftest_rule() { cat > /dev/null; echo "aid-hook self-test"; }
RULE
  cat > "${tmp}/registry.yaml" <<RULES
version: 1
defaults: { timeout_s: 5 }
budget: { total_s: 15 }
rules:
  - id: self_test
    event: SelfTest
    owner: any
    degree: 3
    failure: open
    lib: ${tmp}/lib.sh
    description: proves the dispatcher runs a registered rule
    handler: aid_hook_selftest_rule
RULES

  local out rc=0
  out="$(printf '{"session_id":"self-test"}' \
    | AID_HOOK_REGISTRY="${tmp}/registry.yaml" AID_HOOK_AUDIT="${tmp}/audit.jsonl" \
      bash "${BASH_SOURCE[0]}" SelfTest)" || rc=$?
  rm -rf "$tmp"
  if (( rc != 0 )); then
    echo "self-test: dispatch failed (exit ${rc})" >&2
    return 1
  fi
  if [[ "$out" != *"aid-hook self-test"* ]]; then
    echo "self-test: rule did not run (output: ${out})" >&2
    return 1
  fi
  echo "aid-hook.sh self-test OK"
}

main() {
  case "${1:-}" in
    "")           echo "Usage: aid-hook.sh <event> | --run-rule <id> <event> | --self-test" >&2; exit 1 ;;
    --self-test)  self_test ;;
    --run-rule)   shift; run_rule "${1:?rule id required}" "${2:?event required}" ;;
    *)            dispatch "$1" ;;
  esac
}

main "$@"
