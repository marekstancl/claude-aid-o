#!/usr/bin/env bash
# =============================================================================
# aid-test-quarantine.sh — the flaky record (P081 Step 7).
#
# WHY THIS EXISTS: a suite that fails and then passes on a retry is not a
# regression and not a green run either. Counting it as a failure trains people
# to re-run the nightly until it is green, which is how a real failure gets
# ignored; counting it as a pass makes it invisible. It gets its own state
# instead: quarantined, named, aged, and reported every single night until
# somebody fixes or deletes it.
#
# A quarantined suite does NOT block a merge. It does appear in every nightly
# report with its age, and past 14 days with no owner it escalates exactly
# like a red streak — the deadline is what stops quarantine becoming a place
# tests go to be forgotten.
#
# APPEND-ONLY JOURNAL. `close` appends a closing record rather than rewriting
# the file, so the history of what was quarantined and for how long survives —
# that history is one of the reaper's inputs.
#
# Usage:
#   aid-test-quarantine.sh add    <suite> [owner]
#   aid-test-quarantine.sh assign <suite> <owner>
#   aid-test-quarantine.sh list   [--json]
#   aid-test-quarantine.sh close <suite> <fixed|deleted>
#
# The record lives beside the nightly artifacts, under
# ${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}/quarantine.jsonl
# — a shared host path outside any checkout, for the same reason the nightly
# artifact is: a CI job and the PM's checkout must be able to read the same
# file, and `.aid-o/` is gitignored so CI could never write somewhere the PM
# can see.
#
# Exit codes: 0 = ok, 1 = nothing to do (unknown suite on close), 2 = usage.
#
# **Last Updated:** 2026-08-10
# =============================================================================
set -uo pipefail

AID_NIGHTLY_DIR="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
QUARANTINE_FILE="$AID_NIGHTLY_DIR/quarantine.jsonl"
QUARANTINE_ESCALATE_DAYS="${AID_QUARANTINE_ESCALATE_DAYS:-14}"

_today() { date -u +%Y-%m-%d; }

_ensure_dir() {
  mkdir -p "$AID_NIGHTLY_DIR" 2>/dev/null || {
    echo "aid-test-quarantine: cannot create '$AID_NIGHTLY_DIR'" >&2
    return 2
  }
}

# _open_entries — the current open set, folded from the journal: one object per
# suite, the newest `add` that has no later `close`.
_open_entries() {
  [[ -f "$QUARANTINE_FILE" ]] || { echo '[]'; return 0; }
  # `assign` records must NOT take part in the last-record-wins fold that
  # decides open-vs-closed — an assign is not a lifecycle event, it only
  # supplies the owner of the entry that is already open. Folding it in made
  # an assigned suite disappear from the list entirely.
  jq -Rcn '
    ([inputs | select(length > 0) | fromjson]) as $all
    | ($all | map(select(.action == "assign"))) as $assigns
    | $all
    | map(select(.action == "add" or .action == "close"))
    | group_by(.suite)
    | map(sort_by(.at) | last)
    | map(select(.action == "add"))
    | map(. as $e
          | ([$assigns[] | select(.suite == $e.suite and .at >= $e.at)]
             | sort_by(.at) | last | .owner // "") as $o
          | if $o != "" then .owner = $o else . end)
    | sort_by(.at)' "$QUARANTINE_FILE"
}

# _with_age <entries_json> — each entry plus the whole days it has been open.
_with_age() {
  jq -c --arg today "$(_today)" '
    def days($a; $b): (($b | strptime("%Y-%m-%d") | mktime)
                     - ($a | strptime("%Y-%m-%d") | mktime)) / 86400 | floor;
    map(. + {age_days: days(.opened; $today)})' <<<"$1"
}

cmd_add() {
  local suite="${1:-}" owner="${2:-}"
  [[ -n "$suite" ]] || { echo "aid-test-quarantine: add needs a suite" >&2; return 2; }
  _ensure_dir || return $?
  # ALREADY OPEN IS A NO-OP, and that is the whole deadline. A second `add`
  # would stamp a fresh `opened` date, so a suite that flakes every week would
  # reset its own age every week and never reach the 14-day escalation — the
  # record would be a permanent record of nothing. The nightly calls `add`
  # every time a suite flakes, so this path is the common one, not the corner.
  if [[ "$(_open_entries | jq --arg s "$suite" '[.[] | select(.suite == $s)] | length')" -gt 0 ]]; then
    return 0
  fi
  jq -nc --arg suite "$suite" --arg owner "$owner" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg opened "$(_today)" \
    '{action:"add", suite:$suite, owner:$owner, opened:$opened, at:$at}' \
    >> "$QUARANTINE_FILE"
}

cmd_assign() {
  local suite="${1:-}" owner="${2:-}"
  [[ -n "$suite" ]] || { echo "aid-test-quarantine: assign needs a suite" >&2; return 2; }
  [[ -n "$owner" ]] || { echo "aid-test-quarantine: assign needs an owner" >&2; return 2; }
  # The gap this closes: `add` is deliberately a no-op once an entry is open
  # (so a weekly flake cannot reset its own deadline), the nightly is the only
  # automatic producer and it always passes an empty owner, and there was no
  # other way in. Every entry was therefore ownerless for ever and escalated
  # weekly with no way to say "mine" — the standard's owner+deadline rule was
  # unreachable. `assign` sets the owner on an OPEN entry and deliberately does
  # NOT touch `opened`, so taking ownership never buys extra days.
  if [[ "$(_open_entries | jq --arg s "$suite" '[.[] | select(.suite == $s)] | length')" -eq 0 ]]; then
    echo "aid-test-quarantine: '$suite' is not quarantined — nothing to assign" >&2
    return 1
  fi
  _ensure_dir || return $?
  jq -nc --arg suite "$suite" --arg owner "$owner" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{action:"assign", suite:$suite, owner:$owner, at:$at}' >> "$QUARANTINE_FILE"
}

cmd_close() {
  local suite="${1:-}" resolution="${2:-}"
  [[ -n "$suite" ]] || { echo "aid-test-quarantine: close needs a suite" >&2; return 2; }
  case "$resolution" in
    fixed|deleted) ;;
    *) echo "aid-test-quarantine: close needs a resolution — fixed or deleted" >&2; return 2 ;;
  esac
  if [[ "$(_open_entries | jq --arg s "$suite" '[.[] | select(.suite == $s)] | length')" -eq 0 ]]; then
    echo "aid-test-quarantine: '$suite' is not quarantined — nothing to close" >&2
    return 1
  fi
  _ensure_dir || return $?
  jq -nc --arg suite "$suite" --arg r "$resolution" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{action:"close", suite:$suite, resolution:$r, at:$at}' >> "$QUARANTINE_FILE"
}

cmd_list() {
  local entries; entries="$(_with_age "$(_open_entries)")"
  if [[ "${1:-}" == "--json" ]]; then
    printf '%s\n' "$entries"
    return 0
  fi
  if [[ "$(jq 'length' <<<"$entries")" -eq 0 ]]; then
    echo "No quarantined suites."
    return 0
  fi
  jq -r --argjson limit "$QUARANTINE_ESCALATE_DAYS" '.[]
    | "\(.suite)\t\(if .owner == "" then "NO OWNER" else .owner end)\t\(.age_days)d\(if .owner == "" and .age_days >= $limit then "\tESCALATE" else "" end)"' \
    <<<"$entries"
}

case "${1:-}" in
  add)   shift; cmd_add "$@" ;;
  assign) shift; cmd_assign "$@" ;;
  close) shift; cmd_close "$@" ;;
  list)  shift; cmd_list "$@" ;;
  --help|-h|"")
    sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) echo "aid-test-quarantine: unknown command '$1'" >&2; exit 2 ;;
esac
