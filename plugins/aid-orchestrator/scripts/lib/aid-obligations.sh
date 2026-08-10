#!/usr/bin/env bash
# =============================================================================
# aid-obligations.sh — the durable carrier for a deferral a run decides to make
# (P079 Step 6, IMP-476).
#
# THE INCIDENT THIS EXISTS FOR: the first P076 run deferred a release-blocking
# item and wrote it into a `carried-obligations.md` the controller invented on
# the spot — inside the plan WORKTREE's gitignored `.aid-o`. The worktree was
# torn down at close and the obligation went with it. Nothing read that file
# because nothing ever wrote it: it had no writer and no reader anywhere in the
# codebase. The release shipped without it.
#
# Two properties make an obligation durable:
#
#   IT LIVES IN THE STATE ROOT. `.aid-o/work/plan-state/<plan_id>/` is the one
#   directory that exists independently of any worktree — the same place
#   plan-state.yaml and pm-auto-go.json already live, and it survives every
#   worktree operation. This library refuses to write anywhere else: if the
#   state root cannot be resolved, there is no safe place for the record and
#   saying so is better than writing one somewhere it will be lost.
#
#   SOMETHING CONSUMES IT. `aid-plan-close-check.sh` refuses to close a plan
#   with an open `release_blocker`. A record nobody reads is what failed last
#   time (AID-v3 §1 — a detector without enforcement is decoration).
#
# APPEND-ONLY JOURNAL. Adds and resolutions are single lines appended with
# O_APPEND, the same discipline as timeline.jsonl: two sessions appending
# concurrently interleave safely and neither can lose the other's line. There
# are no in-place edits, so there is no read-modify-write window.
#
# INDICES ARE ASSIGNED AT FOLD TIME, never embedded at write time. Two
# concurrent adds would otherwise be able to embed the same index, and a later
# `resolve <index>` would silently close an unrelated release blocker — the one
# duplication path that would weaken the guard this library exists to provide.
#
# SEVERITIES:
#   release_blocker — blocks plan-close until resolved (or registered as a
#                     backlog IMP and resolved with that IMP number).
#   followup        — recorded for the record; never blocks anything.
#
# ABANDONED PLANS: a plan that is rolled back or abandoned leaves its journal
# in place and nothing consumes it. That is harmless and deliberate — the file
# is evidence of what was decided, not a task queue.
#
# Sourced, not executed. Callers: aid-plan-close-check.sh (reader),
# skills/pipeline.md instructs the controller to call the writer.
# =============================================================================

# shellcheck source=aid-roots.sh
[[ -n "${_AID_OBLIGATIONS_SOURCED:-}" ]] || {
  _AID_OBLIGATIONS_SOURCED=1
  _aid_obl_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "${_aid_obl_dir}/aid-roots.sh"
}

AID_OBLIGATIONS_SEVERITIES="release_blocker followup"

# _aid_obligation_file <plan_id> — the journal path under the STATE root, or
# nothing (with a reason on stderr) when there is no safe place to write.
_aid_obligation_file() {
  local plan_id="${1:-}" root=""
  if [[ -z "$plan_id" ]]; then
    echo "ERROR: aid-obligations: a plan id is required" >&2
    return 2
  fi
  if ! root="$(aid_state_root 2>/dev/null)"; then
    echo "ERROR: aid-obligations: cannot resolve the state root, so there is no durable place for ${plan_id}'s obligations — refusing to write one into a worktree that will be torn down" >&2
    return 2
  fi
  printf '%s/.aid-o/work/plan-state/%s/carried-obligations.jsonl' "$root" "$plan_id"
}

# aid_obligation_add <plan_id> <severity> <text> [source_ref]
aid_obligation_add() {
  local plan_id="${1:-}" severity="${2:-}" text="${3:-}" source_ref="${4:-}" file
  case " ${AID_OBLIGATIONS_SEVERITIES} " in
    *" ${severity} "*) ;;
    *) echo "ERROR: aid-obligations: severity must be one of: ${AID_OBLIGATIONS_SEVERITIES} (got '${severity:-<empty>}')" >&2; return 1 ;;
  esac
  if [[ -z "${text// /}" ]]; then
    echo "ERROR: aid-obligations: an obligation needs text saying what is owed" >&2
    return 1
  fi
  file="$(_aid_obligation_file "$plan_id")" || return 2
  mkdir -p "$(dirname "$file")" 2>/dev/null || {
    echo "ERROR: aid-obligations: cannot create $(dirname "$file")" >&2
    return 2
  }
  local line
  line="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$plan_id" \
    --arg sev "$severity" --arg text "$text" --arg ref "$source_ref" \
    '{op:"add", ts:$ts, plan_id:$plan, severity:$sev, text:$text, source_ref:$ref}')" || {
    echo "ERROR: aid-obligations: cannot build the journal line (jq missing?)" >&2
    return 2
  }
  printf '%s\n' "$line" >> "$file" || {
    echo "ERROR: aid-obligations: cannot append to $file" >&2
    return 2
  }
  echo "Recorded ${severity}: ${text}" >&2
  return 0
}

# aid_obligation_resolve <plan_id> <index> <resolution>
# <index> is the ordinal `aid_obligation_open` printed — assigned at fold time.
aid_obligation_resolve() {
  local plan_id="${1:-}" index="${2:-}" resolution="${3:-}" file
  if ! [[ "$index" =~ ^[0-9]+$ ]]; then
    echo "ERROR: aid-obligations: index must be the ordinal shown by 'open' (got '${index:-<empty>}')" >&2
    return 1
  fi
  if [[ -z "${resolution// /}" ]]; then
    echo "ERROR: aid-obligations: a resolution must say HOW it was discharged (a fix, or the backlog IMP it was registered as)" >&2
    return 1
  fi
  file="$(_aid_obligation_file "$plan_id")" || return 2
  if [[ ! -f "$file" ]]; then
    echo "ERROR: aid-obligations: ${plan_id} has no obligations journal" >&2
    return 1
  fi
  local line
  line="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$plan_id" \
    --argjson idx "$index" --arg res "$resolution" \
    '{op:"resolve", ts:$ts, plan_id:$plan, index:$idx, resolution:$res}')" || return 2
  printf '%s\n' "$line" >> "$file" || {
    echo "ERROR: aid-obligations: cannot append to $file" >&2
    return 2
  }
  return 0
}

# aid_obligation_open <plan_id> [severity]
# Prints one TSV line per OPEN obligation: <index>\t<severity>\t<text>\t<ref>.
# Exit: 0 with output, 0 with no output when there are none, 2 when the journal
# cannot be read or contains a line that is not valid JSON (fail CLOSED — an
# unreadable journal must never look like an empty one).
aid_obligation_open() {
  local plan_id="${1:-}" want="${2:-}" file
  file="$(_aid_obligation_file "$plan_id")" || return 2
  [[ -f "$file" ]] || return 0
  local bad
  bad="$(grep -cvE '^[[:space:]]*\{.*\}[[:space:]]*$' "$file" 2>/dev/null || true)"
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "ERROR: aid-obligations: ${file} has ${bad:-one or more} unreadable line(s) — refusing to report 'no open obligations' from a journal that cannot be parsed" >&2
    return 2
  fi
  jq -rs --arg want "$want" '
    ( [ .[] | select(.op == "resolve") | .index ] | map({(tostring): true}) | add // {} ) as $done
    | [ .[] | select(.op == "add") ]
    | to_entries
    | map(select($done[(.key + 1 | tostring)] | not))
    | map(select($want == "" or .value.severity == $want))
    | .[]
    | "\(.key + 1)\t\(.value.severity)\t\(.value.text)\t\(.value.source_ref // "")"
  ' "$file"
}
