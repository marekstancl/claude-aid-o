#!/usr/bin/env bash
# =============================================================================
# aid-routed-findings.sh — where a review finding goes when no remaining step
# may fix it (P079 Step 7, IMP-473).
#
# THE INCIDENT THIS EXISTS FOR: three times in one P076 run — once across
# EPICs — a review produced a finding whose file lay outside every remaining
# step's allowed_paths. There was nowhere legitimate to fix it, so it lived in
# the controller's prose until the prose ended. A finding that no authorized
# step may fix is not a finding that stops mattering.
#
# The carrier is PLAN-scoped, not run-scoped, because the recurrence pattern
# includes findings that belong to a LATER EPIC. Same journal discipline as
# lib/aid-obligations.sh — append-only JSONL in the state root's plan-state
# directory, which outlives every worktree — for the same reason.
#
# FINGERPRINTS ARE OPAQUE. Two formulas ship (`fingerprint()` for
# semantic-review findings, `fingerprint_audit_report()` for C3 audit
# findings, both in lib/aid-finding-fingerprint.sh) and this library
# recomputes NEITHER: a fingerprint is copied verbatim from the source
# artifact and only its shared `sha256:<64hex>` envelope is validated. A
# recomputation here would silently disagree with the artifact the moment
# either formula changed, and the disagreement would look like "no route
# recorded".
#
# TARGETS:
#   step:<n>        — an authorized later step of THIS epic will fix it
#   epic:<epic_id>  — a later EPIC of this plan owns it
#   backlog:<IMP-x> — registered as future work; the plan may ship
#   resolved:<ref>  — already fixed; <ref> says where
#
# The consumer is `cmd_done_advance`: an EPIC cannot complete while a finding
# routed to it (or to one of its steps) is unresolved, and — the half that
# makes the carrier honest — an out-of-scope finding in the canonical CP3
# artifact with NO journal entry at all fails the same check by fingerprint.
# The controller can no longer hold one in prose.
# =============================================================================

[[ -n "${_AID_ROUTED_FINDINGS_SOURCED:-}" ]] || {
  _AID_ROUTED_FINDINGS_SOURCED=1
  _aid_rf_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "${_aid_rf_dir}/aid-roots.sh"
}

# _aid_rf_file <plan_id> — the journal path under the STATE root, or nothing
# (with a reason on stderr) when there is no durable place for it.
_aid_rf_file() {
  local plan_id="${1:-}" root=""
  [[ -n "$plan_id" ]] || { echo "ERROR: aid-routed-findings: a plan id is required" >&2; return 2; }
  if ! root="$(aid_state_root 2>/dev/null)"; then
    echo "ERROR: aid-routed-findings: cannot resolve the state root — refusing to record a route where a worktree teardown would erase it" >&2
    return 2
  fi
  printf '%s/.aid-o/work/plan-state/%s/routed-findings.jsonl' "$root" "$plan_id"
}

# _aid_rf_valid_target <target> [total_steps]
_aid_rf_valid_target() {
  local target="${1:-}" total="${2:-}"
  case "$target" in
    step:*)
      local n="${target#step:}"
      [[ "$n" =~ ^[0-9]+$ ]] || { echo "ERROR: aid-routed-findings: step target must be 'step:<n>' (got '${target}')" >&2; return 1; }
      if [[ -n "$total" && "$total" =~ ^[0-9]+$ ]] && (( n > total )); then
        echo "ERROR: aid-routed-findings: step:${n} is past this EPIC's last step (${total}) — there is no such step to fix it in" >&2
        return 1
      fi
      ;;
    epic:E-*|backlog:*|resolved:*)
      [[ -n "${target#*:}" ]] || { echo "ERROR: aid-routed-findings: '${target}' names no target" >&2; return 1; }
      ;;
    *)
      echo "ERROR: aid-routed-findings: target must be step:<n> | epic:<id> | backlog:<IMP-n> | resolved:<ref> (got '${target:-<empty>}')" >&2
      return 1
      ;;
  esac
  return 0
}

# aid_finding_route <plan_id> <fingerprint> <source_checkpoint> <target> [epic_id] [total_steps]
# <epic_id> is the EPIC the finding is routed FROM (its own steps are what
# `step:<n>` refers to); it is also what `aid_finding_open_for_epic` matches.
aid_finding_route() {
  local plan_id="${1:-}" fp="${2:-}" source_cp="${3:-}" target="${4:-}" \
        epic_id="${5:-}" total_steps="${6:-}" file
  if ! [[ "$fp" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ERROR: aid-routed-findings: fingerprint must be copied verbatim from the review artifact as sha256:<64hex> (got '${fp:-<empty>}')" >&2
    return 1
  fi
  [[ -n "$source_cp" ]] || { echo "ERROR: aid-routed-findings: name the checkpoint the finding came from" >&2; return 1; }
  _aid_rf_valid_target "$target" "$total_steps" || return 1
  file="$(_aid_rf_file "$plan_id")" || return 2
  mkdir -p "$(dirname "$file")" 2>/dev/null || {
    echo "ERROR: aid-routed-findings: cannot create $(dirname "$file")" >&2; return 2; }
  local line
  line="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$plan_id" \
    --arg fp "$fp" --arg src "$source_cp" --arg target "$target" --arg epic "$epic_id" \
    '{op:"route", ts:$ts, plan_id:$plan, fingerprint:$fp, source_checkpoint:$src,
      target:$target, epic_id:$epic}')" || return 2
  printf '%s\n' "$line" >> "$file" || {
    echo "ERROR: aid-routed-findings: cannot append to $file" >&2; return 2; }
  return 0
}

# aid_finding_resolve <plan_id> <fingerprint> <resolution>
aid_finding_resolve() {
  local plan_id="${1:-}" fp="${2:-}" resolution="${3:-}" file
  [[ "$fp" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "ERROR: aid-routed-findings: fingerprint must be sha256:<64hex>" >&2; return 1; }
  [[ -n "${resolution// /}" ]] || {
    echo "ERROR: aid-routed-findings: a resolution must say where it was fixed or registered" >&2; return 1; }
  file="$(_aid_rf_file "$plan_id")" || return 2
  [[ -f "$file" ]] || { echo "ERROR: aid-routed-findings: ${plan_id} has no routed-findings journal" >&2; return 1; }
  local line
  line="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$plan_id" \
    --arg fp "$fp" --arg res "$resolution" \
    '{op:"resolve", ts:$ts, plan_id:$plan, fingerprint:$fp, resolution:$res}')" || return 2
  printf '%s\n' "$line" >> "$file" || return 2
  return 0
}

# aid_finding_recorded <plan_id> <fingerprint> — 0 when the journal carries ANY
# entry for this fingerprint (open or resolved). The producer-side check: a
# finding the controller decided about is recorded; one it did not is not.
aid_finding_recorded() {
  local plan_id="${1:-}" fp="${2:-}" file
  file="$(_aid_rf_file "$plan_id" 2>/dev/null)" || return 1
  [[ -f "$file" ]] || return 1
  jq -e --arg fp "$fp" -s 'any(.[]; .fingerprint == $fp)' "$file" >/dev/null 2>&1
}

# aid_finding_open_for_epic <plan_id> <epic_id>
# Prints one TSV line per OPEN finding routed to this EPIC (or one of its
# steps): <fingerprint>\t<source_checkpoint>\t<target>.
#
# A `backlog:` or `resolved:` route is a decision, not an open item — it never
# blocks. A route to a DIFFERENT epic blocks that one, not this one.
#
# Exit 2 when the journal exists but cannot be parsed: "unreadable" and
# "nothing open" must never look alike.
aid_finding_open_for_epic() {
  local plan_id="${1:-}" epic_id="${2:-}" file
  file="$(_aid_rf_file "$plan_id")" || return 2
  [[ -f "$file" ]] || return 0
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "ERROR: aid-routed-findings: ${file} has unreadable line(s) — refusing to report 'no open findings' from a journal that cannot be parsed" >&2
    return 2
  fi
  jq -rs --arg epic "$epic_id" '
    ( [ .[] | select(.op == "resolve") | .fingerprint ] | map({(.): true}) | add // {} ) as $done
    | [ .[]
        | select(.op == "route")
        | select( ((.target | startswith("step:")) and (.epic_id == $epic))
                  or (.target == "epic:" + $epic) )
        | select($done[.fingerprint] | not) ]
    | unique_by(.fingerprint + .source_checkpoint)
    | .[]
    | "\(.fingerprint)\t\(.source_checkpoint)\t\(.target)"
  ' "$file"
}
