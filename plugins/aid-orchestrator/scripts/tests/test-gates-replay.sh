#!/usr/bin/env bash
# aid-tier: t2
# =============================================================================
# test-gates-replay.sh — do the rebuilt gates give the recorded verdicts?
#
# WHY THIS FILE EXISTS: P097 rewrote the gate row (Step 2), the profile table
# (Step 4), the timeouts (Step 5) and removed three key families (Step 6). Every
# unit suite in scripts/tests/bats proves a piece of that on a fixture the same
# plan wrote. None of them can answer the only question a PM actually asks
# before the old code is deleted: on the runs that really happened, does the new
# runner reach the SAME verdict? This file answers it on the recorded sample
# (scripts/tests/fixtures/gates/gates-sample.json, written by Step 1) and writes
# the answer to scripts/tests/fixtures/gates/gates-acceptance.json.
#
# HOW IT REPLAYS A RUN — and what it deliberately does NOT do
#   For each sample entry:
#     1. the project's execution.yaml AT THE RECORDED SHA, read with
#        `git show <sha>:.aid-o/config/execution.yaml`. Read-only: nothing is
#        written into the other projects, not even git worktree metadata.
#     2. that file upgraded in memory by Step 3's `execution_yaml_upgrade`
#        (dead keys out, default_profile and when_paths in) — the configuration
#        a project gets after the upgrade, not a hand-written fixture.
#     3. every gate `command` REPLACED by `exit <recorded exit code>` (from the
#        report's `_command_log`, else the row's own `exit_code`). A
#        `vacuous_pass` row is replayed as `printf '<recorded stdout>'; exit 0`
#        so the vacuity rule sees what it saw then.
#     4. `run-all --profile <recorded profile>`, then `overall` and the per-gate
#        STATUS of the new rows against the recorded rows, both sides put
#        through `gate_row_normalize` (lib/aid-gate-row.sh) so a version-1 row
#        and a version-2 row are compared in one vocabulary.
#
#   NO project test suite is executed. That is the point of the stubbing: this
#   proves the runner's mapping from (profile, exit code, pass_criteria) to
#   (status, overall), which is exactly what P097 changed. It does not re-prove
#   that ACTA's pytest still passes — that was true at the recorded sha and is
#   not this plan's claim. The tree at the sha is not materialised at all: with
#   every command stubbed, nothing in the run reads a file from it.
#
# DIFFERENCE CLASSES (every one is recorded, never silently dropped). Only
# `status` and `overall` are VERDICT differences; the rest are listed and
# explained, which is what "equal after explanation" in the plan's AC means:
#   legacy_row  — a recorded row with no `result`: compared on `overall` only.
#   config_drift— a gate in the recorded report that the upgraded configuration
#                 no longer defines, or the reverse.
#   profile_gone— the recorded profile name is not in the upgraded table.
#   refused     — the runner refused the run (exit 2/1); the message is kept.
#   status      — both sides have a status and they differ.
#   overall     — the run verdicts differ.
#   reason      — status equal, `reason` differs. Not a verdict difference; kept
#                 separately so the record can state it instead of hiding it.
#
# RUN IT (t2 — by hand before P097 Step 9, nightly after; NOT on the merge path):
#   AID_PLUGIN_PATH=<plugin dir> bash scripts/tests/test-gates-replay.sh
#   flags: --sample <file>  --out <file>  --limit <n>  --keep
#   Exit: 0 every run equal after explanation, 1 otherwise, 2 bad input.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$PLUGIN_DIR}"

SAMPLE="${SCRIPT_DIR}/fixtures/gates/gates-sample.json"
OUT="${SCRIPT_DIR}/fixtures/gates/gates-acceptance.json"
PROJECTS_ROOT="${AID_REPLAY_PROJECTS_ROOT:-/opt/eco/projects}"
LIMIT=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample) SAMPLE="${2:?--sample needs a file}"; shift 2 ;;
    --out)    OUT="${2:?--out needs a file}"; shift 2 ;;
    --limit)  LIMIT="${2:?--limit needs a number}"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    -h|--help) sed -n '3,50p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ── VERDICT DIFFERENCES THIS FILE ACCEPTS AS EXPLAINED ───────────────────────
# A `status` or `overall` difference is a VERDICT difference and nothing
# explains it away by class. The plan's AC ("equal == replayed AFTER
# explanations") means exactly one thing can: a difference someone has looked
# at, written down, and justified. That list is HERE, in the open, one entry per
# line — not a rule that silently absorbs a class of them. Every entry is
# reproduced in docs/plans/P097-acceptance-run.md and is what the PM is asked to
# accept in writing before Step 9. An empty list is the normal state.
#
# Format: <run_id>|<gate or (overall)>|<explanation>
EXPLAINED_VERDICT_DIFFS=(
  "R-P019-final-5|(overall)|the recorded run was a FALSE GREEN and the new runner is right: ts_e2e exited 130 (interrupted) and the run still reported pass, because the runner of 2026-08 (aid-run-gates.sh@v2.16.0) recorded no 'required' on any row and ACTA declared the gate only through required_when: 'frontend/e2e exists' — a static claim nothing enforced. Step 3's upgrade turns that dead key into required: true, so the same inputs now give overall=fail. This is the change P097 exists to make, observed on a real run."
)

# _explained <run_id> <gate> — echo the explanation, or nothing.
_explained() {
  local e
  for e in "${EXPLAINED_VERDICT_DIFFS[@]}"; do
    [[ "${e%%|*}" == "$1" ]] || continue
    local rest="${e#*|}"
    [[ "${rest%%|*}" == "$2" ]] && { printf '%s' "${rest#*|}"; return 0; }
  done
  return 1
}

for tool in jq yq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found" >&2; exit 2; }
done
[[ -f "$SAMPLE" ]] || { echo "ERROR: no sample at ${SAMPLE}" >&2; exit 2; }

# shellcheck source=lib/aid-gate-row.sh
source "${PLUGIN_DIR}/scripts/lib/aid-gate-row.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aid-gates-replay.XXXXXX")"
cleanup() { (( KEEP )) || rm -rf "$WORK"; }
trap cleanup EXIT
(( KEEP )) && echo "workdir: ${WORK}"

UPGRADE_LIB="${PLUGIN_DIR}/scripts/lib/aid-init-execution-yaml.sh"
RUNNER="${PLUGIN_DIR}/scripts/aid-run-gates.sh"

# upgrade_in_place <yaml> — Step 3's upgrade, two-pass (propose, then confirm
# the hash it printed). Exit 0 when the file is upgraded OR had nothing to
# upgrade; 1 when the upgrade itself refused (the reason goes to stderr).
upgrade_in_place() {
  local f="$1" out hash
  out="$(bash "$UPGRADE_LIB" upgrade "$f" 2>&1)"
  case "$?" in
    0) return 0 ;;                      # nothing to upgrade
    3) : ;;                             # a diff was proposed — confirm it
    *) printf '%s\n' "$out" >&2; return 1 ;;
  esac
  hash="$(grep -o 'sha256:[0-9a-f]\{64\}' <<<"$out" | head -1)"
  [[ -n "$hash" ]] || { printf '%s\n' "$out" >&2; return 1; }
  bash "$UPGRADE_LIB" upgrade "$f" --confirm-upgrade "$hash" >/dev/null 2>&1
}

# stub_commands <yaml> <report> — replace every gate command with its recorded
# outcome. A gate the report never mentions keeps exit 0: it was not the reason
# the run ended as it did, and inventing a failure for it would.
stub_commands() {
  local yaml="$1" report="$2" g ec reason out
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    ec="$(jq -r --arg g "$g" '
      (first(._command_log[]? | select(.name == $g) | .exit_code))
      // (.gates[$g].exit_code) // 0 | tostring' "$report")"
    [[ "$ec" =~ ^-?[0-9]+$ ]] || ec=0
    reason="$(jq -r --arg g "$g" '.gates[$g].reason // ""' "$report")"
    if [[ "$reason" == "vacuous_pass" ]]; then
      # The rule fires on OUTPUT, so the output is what has to come back.
      out="$(jq -r --arg g "$g" '.gates[$g].output // ""' "$report")"
      G="$g" CMD="printf '%s' $(printf '%q' "$out"); exit ${ec}" \
        yq -i '.gates[strenv(G)].command = strenv(CMD)' "$yaml"
    else
      G="$g" CMD="exit ${ec}" yq -i '.gates[strenv(G)].command = strenv(CMD)' "$yaml"
    fi
    # A stubbed command finishes instantly; a recorded multi-minute timeout
    # must not be waited out again.
    G="$g" yq -i '.gates[strenv(G)].timeout_seconds = 60' "$yaml"
  done < <(yq '.gates | select(type == "!!map") | keys | .[]' "$yaml")
}

# ── the replay ───────────────────────────────────────────────────────────────
total="$(jq '.sample | length' "$SAMPLE")"
(( LIMIT > 0 && LIMIT < total )) && total="$LIMIT"
echo "replaying ${total} recorded runs from $(basename "$SAMPLE")"

diffs_file="${WORK}/differences.jsonl"
reasons_file="${WORK}/reason-differences.jsonl"
runs_file="${WORK}/runs.jsonl"
: >"$diffs_file"; : >"$reasons_file"; : >"$runs_file"

replayed=0
for i in $(seq 0 $(( total - 1 ))); do
  entry="$(jq -c --argjson i "$i" '.sample[$i]' "$SAMPLE")"
  project="$(jq -r '.project' <<<"$entry")"
  run_id="$(jq -r '.run_id' <<<"$entry")"
  sha="$(jq -r '.sha' <<<"$entry")"
  profile="$(jq -r '.profile // ""' <<<"$entry")"
  report="${PROJECTS_ROOT}/$(jq -r '.report_path' <<<"$entry")"
  epic_id="$(jq -r '.epic_id // "REPLAY"' <<<"$entry")"

  d="${WORK}/${project}-${run_id}"
  mkdir -p "${d}/tree"
  status="ok"; refusal=""

  if [[ ! -f "$report" ]]; then
    status="refused"; refusal="recorded report not found: ${report}"
  elif ! git -C "${PROJECTS_ROOT}/${project}" show "${sha}:.aid-o/config/execution.yaml" >"${d}/execution.yaml" 2>"${d}/git.err"; then
    status="refused"; refusal="execution.yaml not recoverable at ${sha}: $(head -1 "${d}/git.err")"
  elif ! upgrade_in_place "${d}/execution.yaml" 2>"${d}/upgrade.err"; then
    status="refused"; refusal="upgrade refused: $(head -1 "${d}/upgrade.err")"
  fi

  if [[ "$status" == "ok" ]]; then
    stub_commands "${d}/execution.yaml" "$report"
    declared="$(yq -o=json -I=0 '.gate_profiles | select(type == "!!map") | keys' "${d}/execution.yaml")"
    [[ -n "$declared" ]] || declared='[]'
    args=(run-all "${d}/execution.yaml" "$epic_id" "$run_id" "${d}/timeline.jsonl" --report-file "${d}/new.json")
    if [[ -n "$profile" && "$profile" != "null" ]]; then
      if ! jq -e --arg p "$profile" 'any(.[]; . == $p)' <<<"$declared" >/dev/null; then
        status="profile_gone"
        refusal="recorded profile '${profile}' is not declared at this sha after the upgrade (declared: ${declared})"
      else
        args+=(--profile "$profile")
      fi
    fi
    if [[ "$status" == "ok" ]]; then
      ( cd "${d}/tree" && bash "$RUNNER" "${args[@]}" ) >"${d}/run.log" 2>&1
      rc=$?
      if [[ ! -f "${d}/new.json" ]]; then
        status="refused"
        refusal="runner exited ${rc} with no report: $(grep -m1 ERROR "${d}/run.log" || tail -1 "${d}/run.log")"
      fi
    fi
  fi

  if [[ "$status" != "ok" ]]; then
    jq -nc --arg r "$run_id" --arg g "*" --arg old "recorded" --arg new "$status" --arg e "$refusal" \
      '{run_id:$r, gate:$g, old:$old, new:$new, explanation:$e, class:$new}' >>"$diffs_file"
    jq -nc --arg r "$run_id" --arg p "$project" --arg s "$status" \
      '{run_id:$r, project:$p, result:$s}' >>"$runs_file"
    printf '  %-28s %-22s %s\n' "$project/$run_id" "$status" "$refusal"
    replayed=$(( replayed + 1 ))
    continue
  fi

  # Compare. Both sides through gate_row_normalize; `_`-prefixed keys
  # (_integrity, _execution_ledger) are diagnostics, not gates.
  cmp="$(jq -nc \
      --slurpfile old "$report" --slurpfile new "${d}/new.json" \
      --arg run "$run_id" "${AID_GATE_ROW_JQ}"'
    ($old[0]) as $o | ($new[0]) as $n
    | (($o.gates // {}) | gate_rows_normalize
        | with_entries(select(.key | startswith("_") | not))) as $orows
    | (($n.gates // {}) | gate_rows_normalize
        | with_entries(select(.key | startswith("_") | not))) as $nrows
    | (($o.gates // {}) | with_entries(select(.key | startswith("_") | not))) as $oraw
    | { overall_old: ($o.overall // null), overall_new: ($n.overall // null),
        diffs: (
          ([ $orows | keys[] ] + [ $nrows | keys[] ] | unique)
          | map(. as $g
            | ($orows[$g] // null) as $a | ($nrows[$g] // null) as $b
            | if $a == null then
                {run_id:$run, gate:$g, old:"absent", new:($b.status), class:"config_drift",
                 explanation:"the upgraded configuration defines a gate the recorded run did not have"}
              elif $b == null then
                {run_id:$run, gate:$g, old:($a.status), new:"absent", class:"config_drift",
                 explanation:"the recorded run had a gate the configuration at this sha no longer defines"}
              elif ($oraw[$g].result // null) == null then
                {run_id:$run, gate:$g, old:"legacy_row", new:($b.status), class:"legacy_row",
                 explanation:"the recorded row carries no result — Data Model: compared on overall only, listed here"}
              elif $a.status != $b.status then
                {run_id:$run, gate:$g, old:($a.status), new:($b.status), class:"status",
                 explanation:"status differs"}
              elif $a.reason != $b.reason then
                {run_id:$run, gate:$g, old:($a.reason), new:($b.reason), class:"reason",
                 explanation:"same status, different reason"}
              else empty end)
          | map(select(. != null)) ) }' )"

  overall_old="$(jq -r '.overall_old' <<<"$cmp")"
  overall_new="$(jq -r '.overall_new' <<<"$cmp")"
  jq -c '.diffs[] | select(.class != "reason")' <<<"$cmp" >>"$diffs_file"
  jq -c '.diffs[] | select(.class == "reason")' <<<"$cmp" >>"$reasons_file"

  overall_note=""
  if [[ "$overall_old" != "$overall_new" ]]; then
    overall_note="$(_explained "$run_id" "(overall)" || true)"
    jq -nc --arg r "$run_id" --arg o "$overall_old" --arg n "$overall_new" \
      --arg e "${overall_note:-the run verdict itself differs, and no written explanation covers it}" \
      --argjson acc "$([[ -n "$overall_note" ]] && echo true || echo false)" \
      '{run_id:$r, gate:"(overall)", old:$o, new:$n, class:"overall",
        explanation:$e, explained:$acc}' >>"$diffs_file"
  fi

  # HARD (a verdict difference, nothing explains it away): `status` on a gate
  # both sides have, and `overall`. SOFT (listed, explained, not a verdict
  # difference): `reason` — the same status reached with a renamed reason;
  # `legacy_row` — the Data Model says compare on overall only; `config_drift`
  # — a gate only one side defines, which the plan's own edge case says to
  # list. A drifted gate that actually changed the run's outcome is not hidden
  # by this: `overall` is compared independently and is hard.
  hard=0
  _g=""
  while IFS= read -r _g; do
    [[ -n "$_g" ]] || continue
    _explained "$run_id" "$_g" >/dev/null || hard=$(( hard + 1 ))
  done < <(jq -r '.diffs[] | select(.class == "status") | .gate' <<<"$cmp")
  if [[ "$overall_old" != "$overall_new" && -z "$overall_note" ]]; then hard=$(( hard + 1 )); fi
  soft="$(jq -c '[.diffs[] | select(.class == "reason" or .class == "legacy_row" or .class == "config_drift")] | length' <<<"$cmp")"
  res="equal"; (( hard > 0 )) && res="differs"
  jq -nc --arg r "$run_id" --arg p "$project" --arg s "$res" --argjson soft "$soft" \
    '{run_id:$r, project:$p, result:$s, explained:$soft}' >>"$runs_file"
  printf '  %-28s overall %s→%s  rows %s  %s\n' "$project/$run_id" \
    "$overall_old" "$overall_new" "$(jq '.diffs|length' <<<"$cmp")" "$res"
  replayed=$(( replayed + 1 ))
done

# `equal` counts runs equal AFTER explanation; `raw_equal` counts runs with no
# difference of ANY class. The raw number is reported so a mismatch that an
# explanation absorbs is still visible as a number.
mkdir -p "$(dirname "$OUT")"
jq -n \
  --argjson replayed "$replayed" \
  --slurpfile runs <(cat "$runs_file") \
  --slurpfile diffs <(cat "$diffs_file") \
  --slurpfile reasons <(cat "$reasons_file") \
  --arg sample "$(basename "$SAMPLE")" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  ($runs) as $R | ($diffs) as $D | ($reasons) as $S
  | { replayed: $replayed,
      equal: ([$R[] | select(.result == "equal")] | length),
      raw_equal: ([$R[] | select(.result == "equal" and (.explained // 0) == 0)] | length),
      differences: ($D + $S),
      by_class: ($D + $S | group_by(.class) | map({key: .[0].class, value: length}) | from_entries),
      verdict_differences_explained: ([$D[] | select(.explained == true)]),
      pm_acceptance: "owed — every entry of verdict_differences_explained must be accepted in writing by the PM before P097 Step 9 (docs/plans/P097-acceptance-run.md)",
      sample: $sample,
      generated_by: "scripts/tests/test-gates-replay.sh",
      generated_at: $generated_at }' >"$OUT"

echo ""
jq -r '"replayed=\(.replayed) equal=\(.equal) raw_equal=\(.raw_equal) differences=\(.differences|length) by_class=\(.by_class)"' "$OUT"
echo "wrote ${OUT}"

jq -e '.replayed >= 30 and .equal == .replayed' "$OUT" >/dev/null && exit 0
echo "FAIL: replayed >= 30 and equal == replayed is not met" >&2
exit 1
