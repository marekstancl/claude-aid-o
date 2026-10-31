#!/usr/bin/env bash
# =============================================================================
# lib/aid-land-record.sh — is a step's background takeover record good enough to advance on? (AID 3.11.0)
#
#   aid_land_record_verify <land.json> <state_file> <plan.json> <step_index> <contract.json> <return.json>
#     0 the record proves the takeover of THIS step at THIS HEAD; 1 with one reason on stdout
#
# The record is written by scripts/aid-step-land.sh. increment-step asks this before it advances a step that
# has one, so a controller cannot write PASS over a red, partial, foreign or stale takeover. Checked, all of it:
# schema version 1 · status landed · the same epic, run, step index and id · landed_sha == HEAD · the contract
# and the return on disk are the ones taken over · every command criterion of the step (an acceptance
# criterion whose text begins with a backticked command) checked exactly once, with exactly that command,
# exit 0, not timed out · the commits exist · a wave's landed commit is the merge of base_sha (first parent) and
# step_sha (second) with the very tree git computes for them · a recheck's landed commit descends from its base.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_LAND_RECORD_SH_LOADED:-}" ]] && return 0
_AID_LAND_RECORD_SH_LOADED=1

aid_land_record_verify() {
  local rec="$1" sf="$2" pj="$3" n="$4" c="$5" r="$6"
  [[ -f "$rec" ]] || { echo "no takeover record ${rec}"; return 1; }
  jq -e 'type == "object"' "$rec" >/dev/null 2>&1 || { echo "the takeover record ${rec} is not a JSON object"; return 1; }
  local v st idx sid epic run lsha bsha ssha path csha rsha head
  IFS=$'\x1f' read -r v st idx sid epic run lsha bsha ssha path csha rsha < <(jq -r \
    '[.version, .status, .step_index, .step_id, .epic_id, .run_id, .landed_sha, .base_sha, .step_sha, .path,
      .contract_sha256, .return_sha256] | map(. // "" | tostring) | join("\u001f")' "$rec")
  [[ "$v" == 1 ]] || { echo "the takeover record has schema version '${v}', not 1"; return 1; }
  [[ "$st" == landed ]] || { echo "the takeover of step ${n} is '${st}', not landed: $(jq -r '.reason // ""' "$rec")"; return 1; }
  [[ "$idx" == "$n" && "$sid" == "$(jq -r --argjson i "$n" '.steps[$i].id // ""' "$pj")" ]] \
    || { echo "the takeover record is about step ${idx} (${sid}), not step ${n}"; return 1; }
  [[ "$epic" == "$(yq -r '.epic_id // ""' "$sf")" && "$run" == "$(yq -r '.run_id // ""' "$sf")" ]] \
    || { echo "the takeover record belongs to ${epic}/${run}, not this run"; return 1; }
  head="$(git rev-parse HEAD 2>/dev/null)"
  [[ -n "$lsha" && "$lsha" == "$head" ]] \
    || { echo "the takeover landed ${lsha:0:8}, HEAD is ${head:0:8} — a commit came after it: aid-step-land.sh … --recheck"; return 1; }
  [[ "$csha" == "$(sha256sum "$c" 2>/dev/null | cut -d' ' -f1)" ]] || { echo "the contract changed after the takeover"; return 1; }
  [[ "$rsha" == "$(sha256sum "$r" 2>/dev/null | cut -d' ' -f1)" ]] || { echo "the return changed after the takeover"; return 1; }

  jq -e '(.checks | type) == "array" and all(.checks[]; type == "object" and (.ac | type) == "number"
          and (.command | type) == "string" and (.exit | type) == "number")' "$rec" >/dev/null 2>&1 \
    || { echo "the takeover record's checks are not a list of {ac, command, exit}"; return 1; }
  local missing
  [[ -n "${AID_AC_COMMAND_JQ:-}" ]] || source "$(dirname "${BASH_SOURCE[0]}")/aid-ac-command.sh"
  missing="$(jq -r --argjson i "$n" --slurpfile rec "$rec" "${AID_AC_COMMAND_JQ}"'
    ($rec[0].checks // []) as $ch
    | .steps[$i].acceptance_criteria // [] | to_entries[]
    | (.value | ac_command) as $cmd | select($cmd != null)
    | (.key + 1) as $k
    | [$ch[] | select(.ac == $k)] as $m
    | if ($m | length) != 1 then "AC\($k) checked \($m | length) times, not once"
      elif ($m[0] | has("plan_command") or has("reason")) and ($m[0].command == $cmd)
        then "AC\($k) carries replacement metadata on the command the plan names"
      elif $m[0].command != $cmd and (($m[0].plan_command != $cmd)
            or (($m[0].reason | type) != "string") or (($m[0].reason | gsub("^\\s+|\\s+$"; "") | length) < 10)
            or (($m[0].command | gsub("\\s"; "") | length) == 0))
        then "AC\($k) ran another command than the plan names, without its reason"
      elif $m[0].exit != 0 or $m[0].timed_out == true then "AC\($k) did not pass (exit \($m[0].exit))"
      else empty end' "$pj" 2>/dev/null)" || { echo "the takeover record's checks could not be read against the plan"; return 1; }
  missing="${missing%%$'\n'*}"
  [[ -z "$missing" ]] || { echo "the takeover record does not prove the step's command criteria: ${missing}"; return 1; }
  local extra
  extra="$(jq -r '[.checks[].ac] | group_by(.) | map(select(length > 1)) | length' "$rec")" || extra=x
  [[ "$extra" == 0 ]] || { echo "the takeover record checks one criterion twice"; return 1; }

  local c
  for c in "$lsha" "$bsha" "$ssha"; do
    [[ -n "$c" ]] && git cat-file -e "${c}^{commit}" 2>/dev/null || { echo "a commit the takeover names (${c:0:8}) does not exist"; return 1; }
  done
  # what the run's timeline says the takeovers of this step produced (aid-step-land.sh writes it, start and result)
  local tl; tl="$(dirname "$(dirname "$(dirname "$rec")")")/timeline.jsonl"
  # the run's timeline holds this very result (aid-step-land.sh writes it before the record says landed)
  grep -F '"event":"step_takeover_result"' "$tl" 2>/dev/null | jq -e --argjson n "$n" --arg l "$lsha" \
    'select(.step == $n and .status == "landed" and .landed_sha == $l)' >/dev/null 2>&1 \
    || { echo "the run's timeline holds no landed takeover of step ${n} at ${lsha:0:8}"; return 1; }
  case "$path" in
    wave)
      git cat-file -e "${bsha}^{commit}" 2>/dev/null && git cat-file -e "${ssha}^{commit}" 2>/dev/null \
        || { echo "the takeover's base or step commit does not exist"; return 1; }
      [[ "$(git rev-parse "${lsha}^1" 2>/dev/null)" == "$bsha" && "$(git rev-parse "${lsha}^2" 2>/dev/null)" == "$ssha" ]] \
        || { echo "the landed commit is not the merge of the base (first parent) and the step (second)"; return 1; }
      [[ "$(git rev-parse "${lsha}^{tree}")" == "$(git merge-tree --write-tree "$bsha" "$ssha" 2>/dev/null | head -1)" ]] \
        || { echo "the landed merge's tree differs from the merge git computes for its parents"; return 1; } ;;
    recheck)
      # it starts from a commit a takeover of this step really produced: a landed one, or a serial step's own
      # commit whose checks failed (the role fixed on top of it)
      grep -F '"event":"step_takeover_result"' "$tl" 2>/dev/null | jq -e --argjson n "$n" --arg b "$bsha" \
        'select(.step == $n and ((.status == "landed" and .landed_sha == $b) or (.path == "serial" and .status == "check_failed" and .step_sha == $b)))' >/dev/null 2>&1 \
        || { echo "the recheck starts from ${bsha:0:8}, which no takeover of step ${n} produced (the run's timeline)"; return 1; }
      git merge-base --is-ancestor "$bsha" "$lsha" 2>/dev/null \
        || { echo "the recheck's HEAD does not descend from the commit landed before"; return 1; } ;;
    serial)
      # the step's commit sits right on the base (or there was nothing to commit) and is what landed
      [[ "$lsha" == "$ssha" ]] || { echo "a serial takeover landed ${lsha:0:8}, not the step's commit ${ssha:0:8}"; return 1; }
      [[ "$ssha" == "$bsha" || "$(git rev-parse "${ssha}^" 2>/dev/null)" == "$bsha" ]] \
        || { echo "the step's commit ${ssha:0:8} does not sit on the base ${bsha:0:8}"; return 1; } ;;
    *) echo "the takeover record has an unknown path '${path}'"; return 1 ;;
  esac
  return 0
}
