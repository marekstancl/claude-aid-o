#!/usr/bin/env bash
# =============================================================================
# aid-review-round.sh — one review round at a time, for every checkpoint:
# the plan review (CP1), the step review (CP2), the EPIC review (CP3), the
# fast-mode review (CP6) and the whole-plan review at plan close (CP7).
#
# Which review a call is about is the first option group:
#   --plan <file>                                       CP1: evidence/<plan_id>/cp1/
#   --checkpoint cp2 --evidence-dir <run dir> --step N  evidence/<run>/cp2/step-N/
#   --checkpoint cp3 --evidence-dir <run dir>           evidence/<run>/cp3/
#   --checkpoint cp6 --evidence-dir <do dir>            evidence/do/<id>/cp6/
#   --checkpoint cp7 --evidence-dir <final run dir>     evidence/<plan>/<R-…-final-N>/cp7/
#
#   prepare … --round K [--only <role>] [--manual] [--stub]
#       build the packet and one prompt per expected reviewer
#   dispatch … --round K --provider codex --role <r>
#       run one codex reviewer (claude reviewers are dispatched by the controller)
#   collect … --round K
#       validate the answers, decide whether the round is valid, adjudicate
#   close … --round K --tokens <role>=<n|unknown> … [--fixer <role>=<model>:<in>:<out>]
#       write measurement.json and the verdict; a round counts only once closed
#   retry … --round K --role <r>
#       clear one invalid or missing reviewer so it can answer again
#   override … --rounds 1|2|3 --reason "<the PM's words>"
#       record the PM's instruction to run one round, or a third
#   dispute … --round K --fingerprint <fp> --reason "<why>" [--pm accepted|rejected [--finding-card <card>]]
#       CP1, CP2, CP3: a disputed finding stays blocking; only the PM's answer
#       clears it, and at CP2/CP3 `--pm accepted` needs the Decision card that
#       quotes the finding and a PM prompt after it (the hook audit)
#   fix-check | finalize                                 CP1 only (see below)
#
# Every subcommand loads and validates the checkpoint's reviewer block first
# (review_checkpoints.plan_review / step_review / epic_review / final_review). A step round
# is prepared only from a step-check.json computed at HEAD, and closed only at
# the same HEAD, with a recorded dispatch bracket for every claude reviewer
# (unless the round was prepared --stub, which the FSM refuses to advance on).
#
# Common options: --project-root <dir> (default: the plan's workspace, or the
# repository the evidence dir belongs to).
# Exit: 0 done, 1 refused (reason on stderr), 2 usage or missing tool.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-review-config.sh
source "${SCRIPT_DIR}/lib/aid-review-config.sh"
# shellcheck source=lib/aid-plan-review-packet.sh
source "${SCRIPT_DIR}/lib/aid-plan-review-packet.sh"
# shellcheck source=lib/aid-step-review-packet.sh
source "${SCRIPT_DIR}/lib/aid-step-review-packet.sh"
# shellcheck source=lib/aid-review-summary.sh
source "${SCRIPT_DIR}/lib/aid-review-summary.sh"
# The three consumers a step round writes to after its last round (Step 7):
# shellcheck source=lib/aid-routed-findings.sh
source "${SCRIPT_DIR}/lib/aid-routed-findings.sh"
# shellcheck source=lib/aid-obligations.sh
source "${SCRIPT_DIR}/lib/aid-obligations.sh"
# shellcheck source=lib/aid-ancillary.sh
source "${SCRIPT_DIR}/lib/aid-ancillary.sh"

usage() { sed -n '4,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

CMD="${1:-}"; [[ -n "$CMD" && "$CMD" != -h && "$CMD" != --help ]] || usage
shift
PLAN="" CHECKPOINT="" EVID="" STEP="" ROUND="" ROOT="" ONLY="" MANUAL=0 STUB=0 ROLE="" PROVIDER="" FINGERPRINT="" REASON="" ROUNDS="" PM_ANSWER="" FIXER="" CARD=""
TOKENS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)         PLAN="${2:-}"; shift 2 ;;
    --checkpoint)   CHECKPOINT="${2:-}"; shift 2 ;;
    --evidence-dir) EVID="${2:-}"; shift 2 ;;
    --step)         STEP="${2:-}"; shift 2 ;;
    --round)        ROUND="${2:-}"; shift 2 ;;
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --only)         ONLY="${2:-}"; shift 2 ;;
    --manual)       MANUAL=1; shift ;;
    --stub)         STUB=1; shift ;;
    --role)         ROLE="${2:-}"; shift 2 ;;
    --provider)     PROVIDER="${2:-}"; shift 2 ;;
    --fingerprint)  FINGERPRINT="${2:-}"; shift 2 ;;
    --reason)       REASON="${2:-}"; shift 2 ;;
    --rounds)       ROUNDS="${2:-}"; shift 2 ;;
    --pm)           PM_ANSWER="${2:-}"; shift 2 ;;
    --fixer)        FIXER="${2:-}"; shift 2 ;;
    --finding-card) CARD="${2:-}"; shift 2 ;;
    --tokens)       shift; while [[ $# -gt 0 && "$1" != --* ]]; do TOKENS+=("$1"); shift; done ;;
    -*) echo "${CMD}: unknown option $1" >&2; exit 2 ;;
    *)  [[ -z "$PLAN" ]] && PLAN="$1"; shift ;;   # a bare path is the plan (CP1 compatibility)
  esac
done

_die() { echo "${CMD}: $1" >&2; exit "${2:-1}"; }
_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

for tool in jq yq sha256sum git; do
  command -v "$tool" >/dev/null 2>&1 || _die "${tool} not installed" 2
done

# ── which review ─────────────────────────────────────────────────────────────
MODE="" BASE="" NS="" BLOCK="" ROLES_SKILL="" PLAN_ID="" STEPCHECK=""
if [[ -n "$PLAN" && -n "$CHECKPOINT" ]]; then _die "give --plan (CP1) or --checkpoint (CP2/CP3/CP6), not both" 2; fi
if [[ -n "$PLAN" ]]; then
  MODE=plan; CHECKPOINT=cp1
  [[ -f "$PLAN" ]] || _die "plan file required (got '${PLAN}')" 2
  PLAN="$(realpath "$PLAN")"
  [[ -n "$ROOT" ]] || ROOT="$(_aid_plan_project_root "$PLAN")" || _die "the plan is not inside an AID workspace; pass --project-root" 2
  PLAN_ID="$(_aid_plan_id_of "$PLAN")" || _die "the plan has no valid frontmatter id" 2
  BASE="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/cp1"
  NS=plan_review; BLOCK=plan_review; ROLES_SKILL="${AID_PLUGIN_PATH}/skills/plan-review-roles.md"
elif [[ -n "$CHECKPOINT" ]]; then
  MODE=step
  [[ "$CHECKPOINT" =~ ^cp[2367]$ ]] || _die "--checkpoint must be cp2, cp3, cp6 or cp7" 2
  [[ -n "$EVID" && -d "$EVID" ]] || _die "--evidence-dir <dir> required and must exist" 2
  EVID="$(realpath "$EVID")"
  if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || _die "not inside a git repository; pass --project-root" 2
    # the tree the run's branch is checked out in, as aid-step-check.sh diffs it
    if [[ "$CHECKPOINT" =~ ^cp[23]$ ]]; then ROOT="$(aid_run_checkout_root "${EVID}/fsm-state.yaml" "$ROOT")" || exit 2; fi
  fi
  ROOT="$(realpath "$ROOT")"
  case "$CHECKPOINT" in
    cp2) [[ "$STEP" =~ ^[0-9]+$ ]] || _die "--step N required for cp2" 2; BASE="${EVID}/cp2/step-${STEP}"; NS=step_review; BLOCK=step_review ;;
    cp3) BASE="${EVID}/cp3"; NS=epic_review; BLOCK=epic_review ;;
    cp6) BASE="${EVID}/cp6"; NS=do_review; BLOCK=step_review; export RC_CHECKPOINT=cp6 ;;
    cp7) BASE="${EVID}/cp7"; NS=final_review; BLOCK=final_review ;;
  esac
  ROLES_SKILL="${AID_PLUGIN_PATH}/skills/step-review-roles.md"
  STEPCHECK="${BASE}/step-check.json"
else
  _die "give --plan <file> (CP1) or --checkpoint cp2|cp3|cp6|cp7 --evidence-dir <dir> [--step N]" 2
fi

# the review config belongs to the state root (a linked worktree has none, or a stale copy)
aid_review_config_load "$(aid_state_root "$ROOT" 2>/dev/null || echo "$ROOT")" "$BLOCK" "$ROLES_SKILL" || exit 2
aid_review_config_validate || exit 1

_need_round() { [[ "$ROUND" =~ ^[1-9][0-9]*$ ]] || _die "--round K required" 2; }
_round_dir() { printf '%s/round-%s' "$BASE" "$1"; }
_head() { git -C "$ROOT" rev-parse HEAD; }
_plan_only() { [[ "$MODE" == plan ]] || _die "${CMD} is a plan-review (CP1) subcommand; a step round is fixed by the step's role and confirmed by the next round" 2; }
# _log <event> [k=v …] — the round's events go to the plan's timeline (CP1) or the run's (steps).
_log() {
  local ev="$1"; shift
  if [[ "$MODE" == plan ]]; then
    # CP1 keeps its event names (the status tile and the P093 suites read them).
    case "$ev" in
      review_round_start) ev=plan_review_round_start ;;
      review_round_close) ev=plan_review_round_complete ;;
      review_override)    ev=plan_review_override ;;
    esac
    aid_plan_log "$PLAN" "$ev" "$@"
  else
    log_event "${EVID}/timeline.jsonl" "$ev" "$@"
  fi
}
# _focus <role> — the dispatch focus the controller uses for a claude role.
_focus() {
  local r="${1//_/-}"
  case "$CHECKPOINT" in
    cp1) echo "cp1-${r}" ;;
    cp2) echo "cp2-step-${STEP}-${r}" ;;
    *)   echo "${CHECKPOINT}-${r}" ;;
  esac
}
# _is_generalist <role> — the role whose answer a round cannot do without.
_is_generalist() { [[ "$1" == generalist_* || "$1" == *_generalist ]]; }

# _round_verdict <merged.json> — pass without an open blocker or major
# (AID_SR_OPEN_JQ, lib/aid-step-review-packet.sh), fail otherwise.
_round_verdict() { jq -r "if [.findings[] | select(${AID_SR_OPEN_JQ})] | length == 0 then \"pass\" else \"fail\" end" "$1"; }

# _override_rounds — the PM's recorded round count, or nothing.
_override_rounds() { [[ -f "${BASE}/override.json" ]] && jq -r '.rounds // empty' "${BASE}/override.json" 2>/dev/null; }

# _expected_roles <round> — the reviewers a round asks, one per line.
_expected_roles() {
  local n="$1" roles prev fix narrow
  if [[ "$MODE" == plan ]]; then
    local type; type="$(_aid_fm_get "$PLAN" type)"
    if [[ "$type" == docs ]]; then roles="$RC_EXTRA_DOCS_TYPE_REVIEWERS"; else roles="${RC_ROLE[*]}"; fi
    if (( n >= 2 )); then
      # The confirmation round asks only reviewers whose findings touch a changed
      # step, plus every reviewer of a blocker or major still open.
      prev="$(_round_dir $((n - 1)))/merged.json"; fix="$(_round_dir $((n - 1)))/fix-diff.json"
      narrow="$(jq -r --slurpfile fd "$fix" '
        ($fd[0].steps_changed // []) as $changed
        | [.findings[] | select(.step != null and (.step | IN($changed[]))
                                or ((.severity == "blocker" or .severity == "major") and .status != "fixed"))
           | .reported_by[]] | unique | .[]' "$prev")"
      roles="$(for r in $roles; do grep -qxF "$r" <<<"$narrow" && echo "$r"; done)"
    fi
  else
    # Unconditional roles, plus the roles the step check's verdict enables.
    local verdict i
    verdict="$(jq -r '.verdict' "$STEPCHECK")"
    roles=""
    for i in "${!RC_ROLE[@]}"; do
      [[ -z "${RC_WHEN[$i]}" || "${RC_WHEN[$i]}" == "$verdict" ]] && roles+="${RC_ROLE[$i]} "
    done
    if (( n >= 2 )); then
      # The confirmation round asks the reporters of what is still open.
      prev="$(_round_dir $((n - 1)))/merged.json"
      # (routed and carried findings are still open to the reviewer: a PM
      # override after the last round asks about them again)
      # A delta round after a passed round has nothing open: every role is asked.
      narrow="$(jq -r "[.findings[] | select(${AID_SR_OPEN_JQ}) | .reported_by[]] | unique | .[]" "$prev")"
      [[ -z "$narrow" ]] || roles="$(for r in $roles; do grep -qxF "$r" <<<"$narrow" && echo "$r"; done)"
    fi
  fi
  if [[ -n "$ONLY" ]]; then
    [[ " ${roles//$'\n'/ } " == *" ${ONLY} "* ]] || _die "role ${ONLY} is not expected in this round"
    roles="$ONLY"
  fi
  printf '%s\n' $roles
}

# _index_add <round> <sha> — the round index: a JSON array for CP1 (its gate
# reads that shape), an object {verdict, head_sha, rounds: []} for steps.
_index_add() {
  local index="${BASE}/rounds.json"
  if [[ "$MODE" == plan ]]; then
    [[ -f "$index" ]] || echo '[]' > "$index"
    jq --argjson r "$1" --arg sha "$2" --arg at "$(_now)" \
      '. + [{round: $r, plan_sha256: $sha, prepared_at: $at}]' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
  else
    [[ -f "$index" ]] || jq -n --arg h "$2" '{verdict: null, head_sha: $h, rounds: []}' > "$index"
    jq --argjson r "$1" --arg sha "$2" --arg at "$(_now)" \
      '.rounds += [{round: $r, head_sha: $sha, prepared_at: $at}]' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
  fi
}

# _carried_roles <round_dir> <role>... — cp7, first round of an attempt that
# follows a fix (<run>/fix-class.json): a role is carried, not asked again, when
# nothing it reads was touched by the fix (criteria, claims, diff) AND it had
# nothing to report in the previous attempt. Its answer is copied into this
# round; prints {role: source path}. A role that reported anything is asked
# again, because its evidence was checked against another commit.
# _prev_attempt_rounds — the cp7 rounds of the previous attempt (a sibling run
# directory), newest first; nothing when this is the first attempt.
_prev_attempt_rounds() {
  local fc="${EVID}/fix-class.json"
  [[ -f "$fc" ]] || return 0
  ls -d "$(dirname "$EVID")/$(basename "$(jq -r '.previous_run_dir // "none"' "$fc")")"/cp7/round-* 2>/dev/null | sort -t- -k2 -n -r
}
_carried_roles() {
  local dir="$1" fc="${EVID}/fix-class.json" role feeds src out='{}'; shift
  [[ -f "$fc" ]] || { echo '{}'; return 0; }
  for role in "$@"; do
    case "$role" in
      final_criteria)   feeds='["criteria","diff"]' ;;
      final_claims)     feeds='["claims","diff"]' ;;
      *)                feeds='["diff"]' ;;
    esac
    jq -e --argjson f "$feeds" '(.invalidated_feeds - $f) == .invalidated_feeds' "$fc" >/dev/null || continue
    src="$(for d in $(_prev_attempt_rounds); do
             [[ -f "$d/measurement.json" ]] && jq -e --arg r "$role" '.valid | index($r)' "$d/collect.json" >/dev/null 2>&1 \
               && { echo "$d/reviewer-${role}.json"; break; }
           done)"
    [[ -n "$src" ]] && jq -e '(.findings | length) == 0' "$src" >/dev/null 2>&1 || continue
    cp "$src" "${dir}/reviewer-${role}.json" || continue
    [[ -f "${src%/*}/codex-${role}.usage.json" ]] && cp "${src%/*}/codex-${role}.usage.json" "$dir/"
    out="$(jq -c --arg r "$role" --arg s "$src" '.[$r] = $s' <<< "$out")"
  done
  echo "$out"
}
# _previous_attempt_round — cp7 after a fix: the last closed round of the previous
# attempt, when it left a blocker or major open. A fix always moves the candidate,
# so the confirmation happens in the NEXT attempt's first round: its packet shows
# the reviewers what stayed open and what the fix changed.
_previous_attempt_round() {
  local d
  for d in $(_prev_attempt_rounds); do
    [[ -f "$d/measurement.json" ]] || continue
    jq -e '[.findings[] | select((.status | IN("open", "disputed", "form_invalid")) and (.severity == "blocker" or .severity == "major"))] | length > 0' "$d/merged.json" >/dev/null 2>&1 && echo "$d"
    return 0
  done
}
_is_carried() { jq -e --arg r "$2" '(.carried_from // {}) | has($r)' "$1/round.json" >/dev/null 2>&1; }

cmd_prepare() {
  _need_round
  # The PM's switch (review_checkpoints.enabled / the checkpoint's own key) is
  # honoured here as well as in the FSM, so fast mode (no FSM) obeys it too.
  if (( ! RC_ENABLED )); then
    echo "prepare: the ${CHECKPOINT} review is switched off in ${RC_CONFIG_FILE} (review_checkpoints); nothing prepared" >&2
    exit 3
  fi
  local dir sha check
  if [[ "$MODE" == plan ]]; then
    check="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/plan-check.json"
    [[ -f "$check" ]] || _die "no plan-check.json for ${PLAN_ID}; run aid-plan-check.sh ${PLAN} --json ${check}"
  else
    [[ -f "$STEPCHECK" ]] || _die "no step-check.json in ${BASE}; run aid-step-check.sh --checkpoint ${CHECKPOINT}${STEP:+ --step $STEP} --evidence-dir ${EVID}"
    [[ "$(jq -r .head_sha "$STEPCHECK")" == "$(_head)" ]] || _die "step-check.json is stale (head moved); run aid-step-check.sh again"
    local verdict; verdict="$(jq -r .verdict "$STEPCHECK")"
    [[ "$verdict" == review || "$verdict" == "review+security" ]] || _die "verdict is ${verdict}; no round (rounds.json was written by the step check)"
  fi

  if (( MANUAL )); then
    (( ROUND == 1 )) || _die "--manual runs one reviewer on the change as it is; use --round 1" 2
    dir="${BASE}/manual/$(date -u +%Y%m%dT%H%M%SZ)"
  else
    dir="$(_round_dir "$ROUND")"
    # A packet without a round record is a prepare that died; it is rebuilt.
    [[ -f "${dir}/round.json" ]] && _die "round ${ROUND} already prepared; a retry goes through 'retry', a fresh round through the next number"
    if [[ "$CHECKPOINT" == cp7 ]] && (( ROUND >= 2 )); then
      _die "a whole-plan round is bound to one candidate, and a fix moves it: commit the fix, run plan-finalize --stage freeze, and prepare round 1 of the new attempt (its packet carries what stayed open and the fix)"
    fi
    # A step that moves after a PASSED round gets a delta round over the new
    # commits: nothing to fix, so it is neither a fix round nor one the round
    # budget counts — the reviewers only have to see what they have not seen.
    local prev="" delta=0
    if (( ROUND >= 2 )); then
      prev="$(_round_dir $((ROUND - 1)))"
      if [[ "$MODE" != plan ]]; then
        [[ -f "${prev}/measurement.json" ]] || _die "round $((ROUND - 1)) is not closed"
        [[ "$(jq -r .head_sha "${prev}/round.json")" != "$(_head)" ]] \
          || _die "HEAD has not moved since round $((ROUND - 1)); a confirmation round reviews a fix"
        [[ "$(jq -r '.verdict // ""' "${prev}/measurement.json")" == pass ]] && delta=1
      fi
    fi
    if (( ROUND > RC_ROUNDS_DEFAULT && ! delta )); then
      local allowed; allowed="$(_override_rounds)"
      [[ -n "$allowed" && "$allowed" -ge "$ROUND" ]] \
        || _die "round ${ROUND} exceeds rounds_default ${RC_ROUNDS_DEFAULT}; it needs the PM's override.json (aid-review-round.sh override)"
    fi
    if (( ROUND >= 2 && ! delta )); then
      if [[ "$MODE" == plan ]]; then
        [[ -f "${prev}/fix-diff.json" ]] || _die "round $((ROUND - 1)) has no fix-diff.json; run fix-check first"
        [[ "$(jq -r '.pass' "${prev}/fix-diff.json")" == true ]] \
          || _die "the fix of round $((ROUND - 1)) did not pass fix-check: $(jq -c '.added_outside_fixes' "${prev}/fix-diff.json")"
      fi
      [[ "$(jq '[.findings[] | select(.status != "fixed" and (.severity == "blocker" or .severity == "major"))] | length' "${prev}/merged.json")" -gt 0 ]] \
        || _die "nothing to confirm: round $((ROUND - 1)) left no open blocker or major finding"
    fi
  fi

  rm -rf "$dir"; mkdir -p "$dir" || _die "cannot create ${dir}"
  # A half-prepared round is removed whole, so a second prepare can run.
  trap 'rm -rf "$dir"' EXIT
  local roles=() role
  if [[ "$MODE" == plan ]]; then
    aid_plan_review_packet_build "$PLAN" "$ROOT" "$check" "$dir" || exit 1
    sha="$(jq -r .plan_sha256 "${dir}/packet/manifest.json")"
    mapfile -t roles < <(_expected_roles "$ROUND" | grep -v '^$')
    local min; min="$(aid_review_config_floor "${#roles[@]}")"
    jq -n --argjson round "$ROUND" --arg sha "$sha" \
      --argjson min "$min" --arg at "$(_now)" --argjson degraded "$([[ "$RC_DEGRADED" == 1 ]] && echo true || echo false)" \
      '{round: $round, plan_sha256: $sha, reviewers_expected: $ARGS.positional,
        min_answers_effective: $min, degraded: $degraded, started_at: $at}' \
      --args "${roles[@]}" > "${dir}/round.json"
    for role in "${roles[@]}"; do aid_plan_review_prompt_render "$role" "$ROUND" "$dir" || exit 1; done
  else
    local prevdir=""; (( ROUND >= 2 )) && prevdir="$(_round_dir $((ROUND - 1)))"
    [[ "$CHECKPOINT" == cp7 && "$ROUND" -eq 1 ]] && prevdir="$(_previous_attempt_round)"
    if [[ "$CHECKPOINT" == cp7 ]]; then
      aid_final_review_packet_build "$ROOT" "$dir" "$STEPCHECK" "$EVID" "$prevdir" || exit 1
    else
      aid_step_review_packet_build "$ROOT" "$CHECKPOINT" "$dir" "$STEPCHECK" "${EVID}/plan.json" "${STEP:-}" "$prevdir" || exit 1
    fi
    sha="$(_head)"
    mapfile -t roles < <(_expected_roles "$ROUND" | grep -v '^$')
    local min="${#roles[@]}"   # a step round needs every expected role (a codex role may be provider_absent)
    local carried='{}'
    [[ "$CHECKPOINT" == cp7 && "$ROUND" -eq 1 ]] && carried="$(_carried_roles "$dir" "${roles[@]}")"
    jq -n --arg cp "$CHECKPOINT" --argjson step "${STEP:-null}" --argjson round "$ROUND" --arg h "$sha" \
      --arg scs "$(jq -r .sha256 "$STEPCHECK")" --argjson min "$min" --arg at "$(_now)" \
      --argjson degraded "$([[ "$RC_DEGRADED" == 1 ]] && echo true || echo false)" \
      --argjson stub "$([[ "$STUB" == 1 ]] && echo true || echo false)" \
      --arg conf "$([[ -z "$prevdir" ]] || { (( ROUND >= 2 )) && echo "round-$((ROUND - 1))" || echo "$prevdir"; })" --argjson carried "$carried" \
      '{checkpoint: $cp, step: $step, round: $round, head_sha: $h, step_check_sha256: $scs,
        reviewers_expected: $ARGS.positional, min_answers_effective: $min, degraded: $degraded, stub: $stub,
        confirmation_of: (if $conf == "" then null else $conf end), started_at: $at}
       + (if ($carried | length) > 0 then {carried_from: $carried} else {} end)' \
      --args "${roles[@]}" > "${dir}/round.json"
    for role in "${roles[@]}"; do
      _is_carried "$dir" "$role" || aid_step_review_prompt_render "$role" "$ROUND" "$dir" "$CHECKPOINT" "${STEP:-}" || exit 1
    done
  fi

  trap - EXIT
  if (( ! MANUAL )); then
    _index_add "$ROUND" "$sha"
    _log review_round_start checkpoint="$CHECKPOINT" step="${STEP:-null}" round="$ROUND" reviewers="${#roles[@]}"
  fi
  echo "prepared round ${ROUND}: ${#roles[@]} reviewers → ${dir}"
  for role in "${roles[@]}"; do
    if _is_carried "$dir" "$role"; then echo "  ${role}: carried from the previous attempt (the fix touched nothing it reads, and it had no finding)"
    else echo "  ${dir}/prompt-${role}.md  (focus $(_focus "$role")$(_agent_note "$role"))"; fi
  done
}

_existing_round() {
  _need_round
  local dir; dir="$(_round_dir "$ROUND")"
  [[ -f "${dir}/round.json" ]] || _die "round ${ROUND} is not prepared (${dir}/round.json missing)"
  printf '%s' "$dir"
}
_json_strings() { jq -nc '$ARGS.positional' --args "$@"; }
_expects() { jq -e --arg r "$1" '.reviewers_expected | index($r) != null' "$2/round.json" >/dev/null; }
_closed() { [[ -f "$1/measurement.json" ]]; }
# _stand_in <round_dir> <role> — the codex role's record says a claude stand-in
# was asked for, because the probe could not reach a codex.
_stand_in() { jq -e '.fallback == "claude"' "$1/codex-${2}.usage.json" >/dev/null 2>&1; }
# _codex_probe <model> — {available, binary, version, reason} from the shared
# probe, asked of the model the role will run on.
# The cache belongs to the project under review, never to whatever directory the
# controller happens to stand in — two projects reviewed from one cwd would
# otherwise share one answer.
_codex_probe() { ( AID_PROJECT_ROOT="$ROOT" CODEX_MODEL="$1"; export AID_PROJECT_ROOT CODEX_MODEL; source "${SCRIPT_DIR}/lib/aid-codex-transport.sh"; aid_codex_probe ); }
# _agent_type <role> — the subagent a claude reviewer (or a codex role's
# stand-in) is dispatched as: the role's effort, low → reviewer-light.
_agent_type() {
  local i; i="$(aid_review_role_index "$1")"
  [[ "${RC_EFFORT[$i]}" == low ]] && echo aid-orchestrator:reviewer-light || echo general-purpose
}
# _agent_note <role> — what prepare prints next to a claude role's prompt.
_agent_note() {
  local i; i="$(aid_review_role_index "$1")"
  if [[ "${RC_PROVIDER[$i]}" == claude ]]; then echo ", agent $(_agent_type "$1") at model ${RC_MODEL[$i]}"; fi
}
# _stand_in_line <dir> <role> <why> — what the controller must do instead of paying codex.
_stand_in_line() {
  echo "STAND-IN: no codex answer ($3); dispatch ${1}/prompt-${2}.md to a $(_agent_type "$2") agent at model ${RC_STAND_IN_MODEL} (see scripts/lib/aid-review-adapter-claude.md, \"Stand-in for a Codex role\") and have it write ${1}/reviewer-${2}.json with \"provider\": \"claude\". Then collect."
}

cmd_dispatch() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ "$PROVIDER" == codex ]] || _die "--provider codex required; claude reviewers are dispatched by the controller (scripts/lib/aid-review-adapter-claude.md)" 2
  [[ -n "$ROLE" ]] || _die "--role required" 2
  _expects "$ROLE" "$dir" || _die "role ${ROLE} is not expected in round ${ROUND}"
  local i; i="$(aid_review_role_index "$ROLE")"
  [[ "${RC_PROVIDER[$i]}" == codex ]] \
    || _die "role ${ROLE} is dispatched by the controller (see scripts/lib/aid-review-adapter-claude.md)"
  local answer="${dir}/reviewer-${ROLE}.json" usage="${dir}/codex-${ROLE}.usage.json"
  [[ -e "$answer" ]] && _die "${answer} already exists; a reviewer is never paid twice (use retry after collect lists it as invalid)"
  _stand_in "$dir" "$ROLE" && _die "a stand-in was already ordered for ${ROLE}; codex is asked again only through retry"

  [[ -r "${dir}/prompt-${ROLE}.md" ]] || _die "cannot read ${dir}/prompt-${ROLE}.md; prepare the round again" 2
  local probe why
  probe="$(_codex_probe "${RC_MODEL[$i]}")"
  if [[ "$(jq -r '.available' <<< "$probe")" != true ]]; then
    why="$(jq -r '.reason' <<< "$probe")"
    jq -n --arg r "$why" '{answered: false, reason: $r, fallback: "claude"}' > "$usage"
    _stand_in_line "$dir" "$ROLE" "$why"
    return 0
  fi
  local events="${dir}/codex-${ROLE}.events.jsonl" last="${dir}/codex-${ROLE}.last.txt" rc=0
  # In a subshell: the launcher's library sets its own shell options on load.
  ( # shellcheck source=lib/aid-codex-transport.sh
    source "${SCRIPT_DIR}/lib/aid-codex-transport.sh"
    CODEX_MODEL="${RC_MODEL[$i]}" CODEX_EFFORT="${RC_EFFORT[$i]}"
    _run_codex_isolated "$ROOT" "${dir}/prompt-${ROLE}.md" "$events" "${dir}/codex-${ROLE}.stderr.txt" "$last"
  ) || rc=$?

  [[ -s "$last" ]] && aid_plan_review_unfence "$last" "$answer"
  if [[ -s "$answer" ]]; then
    jq -s 'map(select(.type == "turn.completed")) | last | .usage // {}
           | {answered: true, tokens_in: (.input_tokens // "unknown"), cache_read: (.cached_input_tokens // "unknown"),
              tokens_out: (.output_tokens // "unknown")}' "$events" > "$usage" 2>/dev/null \
      || jq -n '{answered: true, tokens_in: "unknown", tokens_out: "unknown"}' > "$usage"
    echo "dispatched ${ROLE} (codex ${RC_MODEL[$i]}): answer in ${answer}"
  else
    rm -f "$answer"
    local why=no_file; (( rc != 0 )) && why="exit_${rc}"; (( rc == 124 )) && why=timeout
    grep -qiE 'usage limit|rate.?limit|429' "${dir}/codex-${ROLE}.stderr.txt" 2>/dev/null && why=rate_limited
    # Any run that leaves no answer falls back to the stand-in: a transport
    # failure never costs the round its second opinion.
    jq -n --arg why "$why" '{answered: false, reason: $why, fallback: "claude"}' > "$usage"
    _stand_in_line "$dir" "$ROLE" "$why"
  fi
}

cmd_retry() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ -n "$ROLE" ]] || _die "--role required" 2
  [[ -f "${dir}/collect.json" ]] || _die "round ${ROUND} is not collected; retry is for a role collect listed as invalid or missing"
  jq -e --arg r "$ROLE" '(.missing | index($r)) or ([.invalid[].role] | index($r))' "${dir}/collect.json" >/dev/null \
    || _die "role ${ROLE} answered validly in round ${ROUND}; a valid answer is never paid for twice"
  _closed "$dir" && _die "round ${ROUND} is closed"
  [[ "$(jq -r '.routed_at // empty' "${dir}/round.json")" == "" ]] || _die "round ${ROUND} has routed its findings; it cannot be reopened"
  rm -f "${dir}/reviewer-${ROLE}.json" "${dir}/reviewer-${ROLE}.invalid.txt" "${dir}/reviewer-${ROLE}.missing"
  if _stand_in "$dir" "$ROLE"; then
    # The stand-in record is the role's provenance, not a spent answer: it is
    # re-probed and rewritten, never dropped, or the retried answer would look
    # like a claude file nobody asked for (unexpected_provider).
    local probe why; probe="$(_codex_probe "${RC_MODEL[$(aid_review_role_index "$ROLE")]}")"; why="$(jq -r '.reason' <<< "$probe")"
    if [[ "$(jq -r '.available' <<< "$probe")" == true ]]; then
      rm -f "${dir}/codex-${ROLE}".*
      echo "retry ${ROLE}: codex answers again; dispatch ${dir}/prompt-${ROLE}.md, then collect"
    else
      jq -n --arg r "$why" '{answered: false, reason: $r, fallback: "claude"}' > "${dir}/codex-${ROLE}.usage.json"
      _stand_in_line "$dir" "$ROLE" "$why"
    fi
    return 0
  fi
  rm -f "${dir}/codex-${ROLE}".*
  echo "retry ${ROLE}: dispatch ${dir}/prompt-${ROLE}.md again, then collect"
}

cmd_collect() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ "$(jq -r '.routed_at // empty' "${dir}/round.json")" == "" ]] || _die "round ${ROUND} has routed its findings; collect cannot run again"
  local role tmp err valid=() invalid=() missing=() absent=() unexpected=() i
  tmp="$(mktemp)"
  for role in $(jq -r '.reviewers_expected[]' "${dir}/round.json"); do
    local answer="${dir}/reviewer-${role}.json"
    i="$(aid_review_role_index "$role")"
    if [[ ! -s "$answer" ]]; then
      # A stand-in that was asked for and never dispatched is MISSING, not
      # absent: the round is invalid, so nobody closes a round on a second
      # opinion that was only ever printed as an instruction.
      # A codex role whose launcher could not be reached and has no stand-in
      # counts as answered-absent (degraded, not invalid); a claude role that
      # wrote nothing is missing.
      if [[ "${RC_PROVIDER[$i]}" == codex ]] && ! _stand_in "$dir" "$role" \
         && jq -e '.answered == false and (.reason | IN("codex_absent", "rate_limited", "timeout"))' "${dir}/codex-${role}.usage.json" >/dev/null 2>&1; then
        absent+=("$role")
      else
        missing+=("$role")
      fi
      continue
    fi
    aid_plan_review_unfence "$answer" "$tmp"
    if err="$(aid_plan_review_answer_error "$tmp" "$CHECKPOINT")"; then
      local named; named="$(jq -r '.role' "$tmp")"
      if [[ "$named" != "$role" ]]; then
        _expects "$named" "$dir" && err="role_mismatch: the file names role ${named}" \
          || err="unknown_role: ${named} is not a reviewer of this round"
      fi
    fi
    if [[ -z "$err" && "${RC_PROVIDER[$i]}" == codex && "$(jq -r '.provider // ""' "$tmp")" == claude ]] \
       && ! _stand_in "$dir" "$role"; then
      err="unexpected_provider: ${role} is a codex role and no stand-in was recorded in codex-${role}.usage.json"
    fi
    # A finding whose command or evidence breaks the form would be dropped by the
    # adjudicator, true or not. Once per role it goes back to its reviewer instead
    # (the `retry` path, with the reason quoted); a second malformed answer is
    # accepted and the adjudicator keeps that finding as form_invalid, open.
    if [[ -z "$err" && ! -e "${dir}/reviewer-${role}.form-asked" ]]; then
      local form
      form="$(jq -r --slurpfile s "$AID_PR_SCHEMA" "$(aid_plan_review_proof_jq) [.findings[] | . as \$f | proof_error as \$e | \"\(\$f.id) \(\$e)\"] | join(\", \")" "$tmp" 2>/dev/null)"
      if [[ -n "$form" ]]; then
        : > "${dir}/reviewer-${role}.form-asked"
        err="form: ${form} — \`command\` is ONE read-only command, \`evidence\` is citations only (path:line; path:first-last), what the line shows goes in \`claim\`; asked once"
      fi
    fi
    if [[ -n "$err" ]]; then
      echo "$err" > "${dir}/reviewer-${role}.invalid.txt"
      invalid+=("$(jq -nc --arg r "$role" --arg why "$err" '{role: $r, reason: $why}')")
    else
      cmp -s "$tmp" "$answer" || cp "$tmp" "$answer"
      rm -f "${dir}/reviewer-${role}.invalid.txt"
      valid+=("$role")
    fi
  done
  rm -f "$tmp"
  for answer in "${dir}"/reviewer-*.json; do
    [[ -e "$answer" ]] || continue
    role="$(basename "$answer" .json)"; role="${role#reviewer-}"
    _expects "$role" "$dir" || unexpected+=("$role")
  done

  local required generalist_expected=false generalist_present=false status reason=""
  required="$(jq '.min_answers_effective' "${dir}/round.json")"
  for role in $(jq -r '.reviewers_expected[]' "${dir}/round.json"); do _is_generalist "$role" && generalist_expected=true; done
  for role in "${valid[@]}"; do _is_generalist "$role" && generalist_present=true; done
  status=valid
  local answered=$(( ${#valid[@]} + ${#absent[@]} ))
  if (( answered < required )); then
    status=invalid; reason="${#valid[@]} of $(jq '.reviewers_expected | length' "${dir}/round.json") answered (min ${required})"
  elif [[ "$generalist_expected" == true && "$generalist_present" == false ]]; then
    status=invalid; reason="no generalist answered"
  fi
  # A form re-ask is owed whatever the count says: a round that stayed valid
  # without the role would adjudicate without its whole answer.
  local reask; reask="$(printf '%s\n' "${invalid[@]}" | jq -rs '[.[] | select(.reason | startswith("form:")) | .role] | join(", ")')"
  [[ "$status" == valid && -n "$reask" ]] && { status=invalid; reason="form re-ask owed: ${reask}"; }

  jq -n --argjson valid "$(_json_strings "${valid[@]}")" \
        --argjson invalid "$(printf '%s\n' "${invalid[@]}" | jq -s '.')" \
        --argjson missing "$(_json_strings "${missing[@]}")" --argjson absent "$(_json_strings "${absent[@]}")" \
        --argjson unexpected "$(_json_strings "${unexpected[@]}")" \
        --argjson required "$required" --argjson gp "$generalist_present" --arg status "$status" --arg reason "$reason" \
    '{valid: $valid, invalid: $invalid, missing: $missing, provider_absent: $absent, unexpected: $unexpected,
      answered: ($valid | length), required: $required, generalist_present: $gp,
      status: $status} + (if $reason == "" then {} else {reason: $reason} end)' > "${dir}/collect.json"

  if [[ "$status" != valid ]]; then
    echo "round ${ROUND} invalid: ${reason}; answered reviewers keep their answers, retry only: $(jq -r '[.missing[], .invalid[].role] | join(", ")' "${dir}/collect.json")" >&2
    exit 1
  fi
  local prev=() extra=()
  (( ROUND >= 2 )) && [[ -f "$(_round_dir $((ROUND - 1)))/merged.json" ]] && prev=(--previous "$(_round_dir $((ROUND - 1)))")
  if [[ "$MODE" == plan ]]; then extra=(--plan "${dir}/packet/plan.md"); else extra=(--step-check "$STEPCHECK"); fi
  "${SCRIPT_DIR}/aid-review-adjudicate.sh" "$dir" --project-root "$ROOT" --namespace "$NS" "${extra[@]}" "${prev[@]}" >/dev/null || exit 1
  echo "round ${ROUND}: ${#valid[@]} of $(jq '.reviewers_expected | length' "${dir}/round.json") answered$( (( ${#absent[@]} )) && echo ", provider absent: ${absent[*]}"), missing: $(jq -r '[.missing[], .invalid[].role] | if length == 0 then "none" else join(", ") end' "${dir}/collect.json"), $(jq '.blockers_open' "${dir}/merged.json") blockers open, $(jq 'length' "${dir}/rejected.json") findings rejected"
}

# _token_value <role> — the --tokens value given for <role>, or nothing.
_token_value() {
  local kv
  for kv in "${TOKENS[@]}"; do [[ "${kv%%=*}" == "$1" ]] && { printf '%s' "${kv#*=}"; return 0; }; done
  return 1
}
# _dispatch_recorded <round dir> <role> — a start and a complete event with the
# role's focus in the round's timeline, the complete naming the reviewer's file.
_dispatch_recorded() {
  local tl="$1/timeline.jsonl" focus; focus="$(_focus "$2")"
  [[ -f "$tl" ]] || return 1
  # No `jq -e`: under pipefail it exits 4 when the LAST input yields nothing, which is the usual case.
  jq -c --arg f "$focus" 'select(.event == "verifier_dispatch_start" and .focus == $f)' "$tl" 2>/dev/null | grep -q . || return 1
  jq -c --arg f "$focus" --arg r "$2" 'select(.event == "verifier_dispatch_complete" and .focus == $f and ((.output_file // "") | test("reviewer-" + $r + "\\.(json|missing)$")))' "$tl" 2>/dev/null | grep -q .
}

# ── the semantic file of a whole-EPIC (cp3) or whole-plan (cp7) round ─────────
# _semantic_final_write <verdict> — <run>/semantic-review-final.json, the
# artifact the boundary consumers keep reading where it always was (aid-fsm.sh
# routed-findings reconciliation, aid-release-policy.sh input row,
# aid-plan-fsm.sh plan-finalize): the union of every round's
# merged.json by fingerprint (the later round's status wins), mapped to the
# protocol shape and checked against defaults/schemas/semantic-review.schema.json
# before it is moved into place. lib/aid-finding-merge.sh merges artifacts of
# that shape, not rounds, so the union is a jq expression here and the file
# says so in merge_meta.merged_from.
#   severity  blocker → critical, major → medium, minor → low
#   status    fixed → resolved, carried → deferred, everything else → open
#   base_sha and range come from step-check.json (the EPIC's base_commit at cp3,
#   the plan's base commit at cp7), so the file names what the reviewers saw
_semantic_final_write() {
  local verdict="$1" out="${EVID}/semantic-review-final.json" tmp base range schema="${AID_PLUGIN_PATH}/defaults/schemas/semantic-review.schema.json"
  range="$(jq -r '.range // ""' "$STEPCHECK")"; base="${range%%..*}"
  tmp="${out}.tmp"
  local rounds=() r
  for r in "${BASE}"/round-*/merged.json; do [[ -f "$r" ]] && rounds+=("$r"); done
  (( ${#rounds[@]} )) || { echo "close: no merged.json under ${BASE}" >&2; return 1; }
  jq -s --arg base "$base" --arg head "$(_head)" --arg range "$range" --arg v "$verdict" --arg at "$(_now)" --arg cp "$CHECKPOINT" \
        --arg project "$(basename "$ROOT")" --arg plan "$(basename "$(dirname "$EVID")")" --arg run "$(basename "$EVID")" \
        --argjson roles "$(_json_strings "${RC_ROLE[@]}")" --argjson from "$(printf '%s\n' "${rounds[@]}" | jq -R . | jq -s .)" '
    def sev: {"blocker": "critical", "major": "medium", "minor": "low"}[.] // "low";
    def st: {"fixed": "resolved", "carried": "deferred"}[.] // "open";
    def file: (split(";")[0] | sub("^[0-9a-f]{7,40}:"; "") | split(":")[0]);
    (sort_by(.round) | map(.findings[]) | group_by(.fingerprint) | map(last)) as $f
    | {artifact_type: "semantic_review", generated_at: $at, generated_by: "aid-review-round.sh close \($cp)",
       revision: {base_sha: $base, head_sha: $head}}
      # a whole-plan file is bound to its plan and attempt (the run directory is <plan>/<run>)
      + (if $cp == "cp7" then {identity: {project_id: $project, epic_id: null, plan_id: $plan, run_id: $run}} else {} end)
      + {semantic_review: {mode: "final", range: $range, verdict: $v, lenses_run: $roles,
         merge_meta: {merged_from: $from, conflicts: []},
         findings: ($f | map({fingerprint, severity: (.severity | sev), lens: (.reported_by[0] // "step_check"),
                              check_id: (.fingerprint[7:23]), target_path: (.evidence | file), finding_class: (.reported_by[0] // "step_check"),
                              status: (.status | st), detail: "\(.claim) (\(.severity), \(if .dispute.pm.answer == "accepted" then "dismissed by the PM (dispute accepted)" else "reported \(.status)" end); evidence \(.evidence); fix: \(.fix))"}))}}' \
    "${rounds[@]}" > "$tmp" || { rm -f "$tmp"; return 1; }
  local err
  # A lens is a reviewer of this round, or step_check for a finding of the
  # deterministic step check; no artifact carries a name nobody defined.
  err="$(jq -r --slurpfile s "$schema" --argjson roles "$(_json_strings "${RC_ROLE[@]}" step_check)" '
    ($s[0]) as $sc | ($sc.properties.semantic_review.properties.findings.items) as $fi
    | if .artifact_type != $sc.properties.artifact_type.const then "artifact_type"
      elif (.semantic_review | type) != "object" then "semantic_review"
      elif (.semantic_review.mode | IN($sc.properties.semantic_review.properties.mode.enum[]) | not) then "semantic_review.mode"
      elif (.semantic_review.lenses_run - $roles | length) > 0 then "lenses_run names \(.semantic_review.lenses_run - $roles | join(", ")), not a reviewer of this round"
      elif ([.semantic_review.findings[].lens] - $roles | length) > 0 then "finding lens \([.semantic_review.findings[].lens] - $roles | unique | join(", ")) is not a reviewer of this round"
      else (first(.semantic_review.findings[] | . as $x
              | ($fi.required - (keys)) as $missing
              | if ($missing | length) > 0 then "finding \($x.fingerprint): missing \($missing | join(", "))"
                elif ($x.fingerprint | test($fi.properties.fingerprint.pattern) | not) then "finding fingerprint \($x.fingerprint)"
                elif ($x.severity | IN($fi.properties.severity.enum[]) | not) then "finding \($x.fingerprint): severity"
                elif ($x.status | IN($fi.properties.status.enum[]) | not) then "finding \($x.fingerprint): status"
                elif ($x.target_path == "") then "finding \($x.fingerprint): target_path"
                else empty end) // "") end' "$tmp" 2>&1)"
  if [[ -n "$err" ]]; then
    echo "close: semantic-review-final.json does not satisfy ${schema}: ${err}" >&2; rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$out"
}

# _record_final_writes — a cp7 close is a stage of the plan close: what it wrote
# is recorded for the decision's integrity check (lib/aid-stage-log.sh).
_record_final_writes() {
  [[ "$CHECKPOINT" == cp7 ]] || return 0
  # shellcheck disable=SC2046  # file names without spaces, relative to the run directory
  aid_stage_writes_record "$EVID" cp7-close $(aid_stage_writes_inputs "$EVID" | grep -E '^(cp7/|semantic-review-final\.json$)')
}

cmd_close() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ -f "${dir}/collect.json" ]] || _die "round ${ROUND} is not collected; run collect first"
  [[ "$(jq -r .status "${dir}/collect.json")" == valid ]] \
    || _die "round ${ROUND} is invalid ($(jq -r '.reason // "too few answers"' "${dir}/collect.json")); retry the roles collect named, then collect again"
  local kv
  for kv in "${TOKENS[@]}"; do
    [[ "$kv" =~ ^[a-z_]+=([0-9]+|unknown)$ ]] || _die "--tokens takes <role>=<number|unknown>, got '${kv}'" 2
  done
  local measurement="${dir}/measurement.json" role i value
  if [[ -f "$measurement" ]]; then
    # A closed round only accepts a value for a role still recorded as unknown.
    local added=0
    for kv in "${TOKENS[@]}"; do
      role="${kv%%=*}"; value="${kv#*=}"
      [[ "$(jq -r --arg r "$role" '.reviewers[$r].tokens // empty' "$measurement")" == unknown && "$value" != unknown ]] || continue
      jq --arg r "$role" --argjson v "$value" '.reviewers[$r].tokens = $v' "$measurement" > "${measurement}.tmp" \
        && mv "${measurement}.tmp" "$measurement" && added=1
    done
    (( added )) || _die "round ${ROUND} already closed"
    _record_final_writes
    echo "round ${ROUND}: measurement updated"; return 0
  fi

  local stub=false dispatch_check=recorded
  if [[ "$MODE" == step ]]; then
    [[ "$(jq -r .head_sha "${dir}/round.json")" == "$(_head)" ]] || _die "head moved during round ${ROUND}; the reviewers saw $(jq -r .head_sha "${dir}/round.json" | cut -c1-12), HEAD is $(_head | cut -c1-12)"
    stub="$(jq -r '.stub // false' "${dir}/round.json")"
    if [[ "$stub" == true ]]; then
      dispatch_check=stubbed
    else
      for role in $(jq -r '.valid[]' "${dir}/collect.json"); do
        i="$(aid_review_role_index "$role")"
        # A stand-in is dispatched by the controller like any claude reviewer,
        # so it owes the same bracket: a stand-in nobody dispatched never closes.
        [[ "${RC_PROVIDER[$i]}" == claude ]] || _stand_in "$dir" "$role" || continue
        _is_carried "$dir" "$role" && continue
        _dispatch_recorded "$dir" "$role" || _die "no_dispatch_record: no start/complete bracket with focus $(_focus "$role") naming reviewer-${role}.json in ${dir}/timeline.jsonl; a reviewer file nobody dispatched does not close a round"
      done
    fi
  fi

  local reviewers='{}' entry usage status reason
  for role in $(jq -r '.reviewers_expected[]' "${dir}/round.json"); do
    i="$(aid_review_role_index "$role")"
    local prov="${RC_PROVIDER[$i]}" model="${RC_MODEL[$i]}"
    # A codex role a claude agent stood in for is priced and recorded as what
    # actually answered, at the checkpoint's stand-in model.
    if [[ "$prov" == codex ]] && _stand_in "$dir" "$role"; then prov=claude; model="$RC_STAND_IN_MODEL"; fi
    status="$(jq -r --arg r "$role" 'if (.valid | index($r)) then "answered" elif (.missing | index($r)) then "missing" elif ((.provider_absent // []) | index($r)) then "provider_absent" else "invalid" end' "${dir}/collect.json")"
    if _is_carried "$dir" "$role"; then
      entry="$(jq -c --arg r "$role" '{tokens: 0, carried_from: .carried_from[$r]}' "${dir}/round.json")"
    elif [[ "$prov" == codex ]]; then
      usage="${dir}/codex-${role}.usage.json"
      if [[ -f "$usage" ]]; then
        entry="$(jq -c '{tokens: (if (.tokens_in | type) == "number" and (.tokens_out | type) == "number" then .tokens_in + .tokens_out else "unknown" end)}
                        + (del(.answered, .reason)) + (if .reason then {reason} else {} end)' "$usage")"
      else
        entry='{"tokens":"unknown","reason":"no_file"}'
      fi
    else
      value="$(_token_value "$role")" || _die "no --tokens value for ${role}; pass ${role}=<number> from the Agent result, or ${role}=unknown"
      [[ "$value" =~ ^([0-9]+|unknown)$ ]] || _die "--tokens value for ${role} must be a number or unknown (got '${value}')" 2
      entry="$(jq -nc --arg v "$value" '{tokens: (if $v == "unknown" then "unknown" else ($v | tonumber) end)}')"
    fi
    reason=""
    [[ "$status" == missing ]] && reason="$(jq -r '.reason // "no_file"' <<< "$entry")"
    [[ "$status" == provider_absent ]] && reason="$(jq -r '.reason // "codex_absent"' <<< "$entry")"
    [[ "$status" == invalid ]] && reason=invalid_answer
    # USD from the tracked price table (Step 11): codex reports input, cached
    # input and output apart; a claude figure is one total, priced at the blend.
    local usd
    if _is_carried "$dir" "$role"; then
      usd=0
    elif [[ "$prov" == codex ]]; then
      usd="$(aid_review_usd "$model" "$(jq -r '.tokens_in // "unknown"' <<< "$entry")" "$(jq -r '.tokens_out // "unknown"' <<< "$entry")" "$(jq -r '.cache_read // 0' <<< "$entry")" 0)"
    else
      usd="$(aid_review_usd_blended "$model" "$(jq -r '.tokens' <<< "$entry")")"
      if [[ "${RC_PROVIDER[$i]}" == codex ]]; then
        entry="$(jq -c --arg fr "$(jq -r '.reason // "unknown"' "${dir}/codex-${role}.usage.json")" \
          '. + {fallback_reason: $fr}' <<< "$entry")"
      fi
    fi
    entry="$(jq -c --arg u "$usd" '. + {usd: ($u | tonumber? // $u)}' <<< "$entry")"
    reviewers="$(jq -c --arg r "$role" --argjson e "$entry" --arg p "$prov" --arg m "$model" \
      --argjson ok "$([[ "$status" == answered ]] && echo true || echo false)" --arg why "$reason" \
      '.[$r] = ({provider: $p, model: $m, answered: $ok} + ($e | del(.reason)) + (if $why == "" then {} else {reason: $why} end))' <<< "$reviewers")"
  done
  local fixer=null
  if [[ -n "$FIXER" ]]; then
    [[ "$FIXER" =~ ^([a-z_-]+)=([^:]+):([0-9]+|unknown):([0-9]+|unknown)$ ]] || _die "--fixer takes <role>=<model>:<tokens_in>:<tokens_out>" 2
    local fusd; fusd="$(aid_review_usd "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" 0 0)"
    fixer="$(jq -nc --arg r "${BASH_REMATCH[1]}" --arg m "${BASH_REMATCH[2]}" --arg i "${BASH_REMATCH[3]}" --arg o "${BASH_REMATCH[4]}" --arg u "$fusd" \
      '{role: $r, model: $m, tokens_in: ($i | tonumber? // $i), tokens_out: ($o | tonumber? // $o),
        tokens: (if ($i | tonumber?) and ($o | tonumber?) then ($i | tonumber) + ($o | tonumber) else "unknown" end), usd: ($u | tonumber? // $u)}')"
  fi
  local degraded; degraded="$(jq '.degraded' "${dir}/round.json")"
  [[ "$(jq '(.provider_absent // []) | length' "${dir}/collect.json")" -gt 0 ]] && degraded=true

  local verdict=pass
  if [[ "$MODE" == step ]]; then
    verdict="$(_round_verdict "${dir}/merged.json")"
    # What stays open after the LAST allowed round is routed or carried before
    # the round is marked closed, so an interrupted close is run again, not lost.
    local last_allowed; last_allowed="$(_override_rounds)"; [[ -n "$last_allowed" ]] || last_allowed="$RC_ROUNDS_DEFAULT"
    aid_step_review_route_open "$ROOT" "$EVID" "$CHECKPOINT" "$STEP" "$dir" "$(( ROUND >= last_allowed ? 1 : 0 ))" \
      || _die "routing the open findings failed; close can be run again"
    jq --arg at "$(_now)" '. + {routed_at: $at}' "${dir}/round.json" > "${dir}/round.json.tmp" && mv "${dir}/round.json.tmp" "${dir}/round.json"
    if [[ "$CHECKPOINT" == cp3 || "$CHECKPOINT" == cp7 ]]; then
      _semantic_final_write "$verdict" || _die "the ${CHECKPOINT} round cannot close: ${EVID}/semantic-review-final.json was not written; close can be run again"
    fi
  fi

  jq -n --argjson round "$ROUND" --arg start "$(jq -r .started_at "${dir}/round.json")" --arg finish "$(_now)" \
        --argjson reviewers "$reviewers" --argjson degraded "$degraded" --argjson fixer "$fixer" \
        --arg dc "$dispatch_check" --arg v "$verdict" --arg cp "$CHECKPOINT" \
    '{checkpoint: $cp, round: $round, started_at: $start, finished_at: $finish, reviewers: $reviewers, degraded: $degraded,
      dispatch_check: $dc, verdict: $v} + (if $fixer then {fixer: $fixer} else {} end)' > "$measurement"

  if [[ "$MODE" == step ]]; then
    local index="${BASE}/rounds.json"
    jq --argjson r "$ROUND" --arg v "$verdict" --arg dc "$dispatch_check" --argjson deg "$degraded" \
      '.rounds |= map(if .round == $r then . + {verdict: $v} else . end) | .verdict = $v | .degraded = $deg
       | (if $dc == "stubbed" then .dispatch_check = "stubbed" else . end)' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
    jq --arg at "$(_now)" --arg v "$verdict" '. + {closed_at: $at, verdict: $v}' "${dir}/round.json" > "${dir}/round.json.tmp" && mv "${dir}/round.json.tmp" "${dir}/round.json"
  fi
  _record_final_writes
  local blockers; blockers="$(jq -r '.blockers_open // 0' "${dir}/merged.json" 2>/dev/null || echo 0)"
  _log review_round_close checkpoint="$CHECKPOINT" step="${STEP:-null}" round="$ROUND" verdict="$verdict" \
    status="$(jq -r .status "${dir}/collect.json")" blockers_open="$blockers"
  # A CP1 round has no verdict of its own (aid-cp1-gate.sh judges the plan): it
  # is valid, and what it left open is the number that matters.
  local outcome="$verdict"; [[ "$MODE" == plan ]] && outcome="valid; open blockers: ${blockers}"
  echo "round ${ROUND} closed (${outcome}): $(jq -r '[.reviewers | to_entries[] | "\(.key)=\(.value.tokens)"] | join(" ")' "$measurement")$([[ "$stub" == true ]] && echo '  [stub: no dispatch check; the FSM refuses this round]')"
}

# ── CP1-only subcommands ──────────────────────────────────────────────────────
# _open_fix_list <round_dir> — steps of open or disputed blockers and majors,
# comma-separated, or `none` when only plan-level findings (or none) are open.
_open_fix_list() {
  local list
  list="$(jq -r '[.findings[] | select((.status == "open" or .status == "disputed")
                   and (.severity == "blocker" or .severity == "major") and .step != null) | .step]
                 | unique | map(tostring) | join(",")' "$1/merged.json")"
  printf '%s' "${list:-none}"
}
# _check_fix <round_dir> <out.json> — aid-plan-check.sh of the current plan
# against the round's packet and fix list; exits 2 on a usage error.
_check_fix() {
  local dir="$1" out="$2" fixes rc=0
  fixes="$(_open_fix_list "$dir")"
  "${SCRIPT_DIR}/aid-plan-check.sh" "$PLAN" --project-root "$ROOT" --snapshot "${dir}/packet/plan.md" \
    --fixes "$fixes" --json "$out" --quiet || rc=$?
  (( rc == 2 )) && _die "aid-plan-check.sh could not check the fix (usage error)" 2
  jq --arg f "$fixes" '. + {fix_list: $f}' "$out" > "${out}.tmp" && mv "${out}.tmp" "$out"
}

cmd_fix_check() {
  _plan_only
  local dir; dir="$(_existing_round)" || exit 1
  [[ -f "${dir}/merged.json" ]] || _die "round ${ROUND} not collected"
  _closed "$dir" || _die "round ${ROUND} is not closed; run close first"
  local out="${dir}/fix-diff.json"
  _check_fix "$dir" "$out"
  jq '.pass = (.added_outside_fixes | length == 0)' "$out" > "${out}.tmp" && mv "${out}.tmp" "$out"
  if [[ "$(jq -r .pass "$out")" == true ]]; then
    echo "fix-check round ${ROUND}: pass; steps changed: $(jq -r '.steps_changed | map(tostring) | join(",") | if . == "" then "none" else . end' "$out")"
  else
    echo "fix-check round ${ROUND}: the fix adds what no finding asked for:" >&2
    jq -r '.added_outside_fixes[] | "  Step \(.step) (\(.kind)): \(.text)"' "$out" >&2
    exit 1
  fi
}

# _last_round — the highest round that is closed, or nothing.
_last_round() {
  local d n best=""
  for d in "${BASE}"/round-*/; do
    [[ -f "${d}measurement.json" ]] || continue
    n="${d%/}"; n="${n##*-}"
    [[ "$n" =~ ^[0-9]+$ ]] && { [[ -z "$best" ]] || (( n > best )); } && best="$n"
  done
  printf '%s' "$best"
}

cmd_finalize() {
  _plan_only
  local last; last="$(_last_round)"
  [[ -n "$last" ]] || _die "no closed round; finalize comes after the last round"
  local dir="$(_round_dir "$last")" out
  out="${dir}/finalize.json"
  _check_fix "$dir" "$out"
  local outside
  outside="$(jq -c '[.added_outside_fixes[] | select(.kind != "ac")]' "$out")"
  [[ "$outside" == "[]" ]] || _die "after the last round only its fixes and acceptance criteria may change; outside the fix list: ${outside}"
  cp "$PLAN" "${dir}/plan-final.md"
  echo "finalized after round ${last}: plan snapshot ${dir}/plan-final.md"
}

# _pm_replied_after <card> — true when the hook audit holds a PM prompt
# (the pm_reply_marker line of a UserPromptSubmit, any session) later than the
# card was written. An audit
# trail, not a proof: a controller that forges the audit file is not stopped.
_pm_replied_after() {
  local -a gens=(); mapfile -t gens < <(aid_hook_audit_files)
  (( ${#gens[@]} )) || return 1
  # ISO-8601 UTC strings sort as time; jq's fromdateiso8601 is off by the DST hour.
  # The rotated generations count too (aid-hook.sh rotates at 20 MB).
  cat "${gens[@]}" | grep -F '"event":"UserPromptSubmit"' | grep -F '"rule":"pm_reply_marker"' \
    | jq -e --arg t "$(date -u -d "@$(stat -c %Y "$1")" +%Y-%m-%dT%H:%M:%SZ)" -s 'any(.[]; .ts > $t)' >/dev/null 2>&1
}

cmd_dispute() {
  [[ "$MODE" == plan || "$CHECKPOINT" == cp2 || "$CHECKPOINT" == cp3 ]] \
    || _die "dispute is for the plan (CP1), step (CP2) and EPIC (CP3) reviews" 2
  local dir; dir="$(_existing_round)" || exit 1
  [[ -n "$FINGERPRINT" && ${#REASON} -ge 20 ]] || _die "--fingerprint and a --reason of at least 20 characters required" 2
  [[ -f "${dir}/merged.json" ]] || _die "round ${ROUND} not collected"
  local final
  for final in "${BASE}"/round-*/plan-final.md; do
    [[ -f "$final" ]] && cmp -s "$PLAN" "$final" \
      && _die "the plan is finalized (plan-final.md matches it); a dispute now would change what the acceptance criteria must quote — edit the plan and finalize again"
  done
  jq -e --arg f "$FINGERPRINT" '.findings | map(.fingerprint) | index($f) != null' "${dir}/merged.json" >/dev/null \
    || _die "no finding ${FINGERPRINT} in round ${ROUND}"
  if [[ "$MODE" == step && "$PM_ANSWER" == accepted ]]; then
    [[ -f "$CARD" ]] || _die "--pm accepted needs --finding-card <the Decision card the PM answered> (skills/communication.md); render it and wait for the PM"
    grep -qF "$FINGERPRINT" "$CARD" || _die "the card ${CARD} does not quote finding ${FINGERPRINT}; the PM must have been asked about this finding"
    _pm_replied_after "$CARD" || _die "no PM prompt after ${CARD} in the hook audit; the PM has not answered the card yet"
  fi
  local filter
  case "$PM_ANSWER" in
    "")       filter='.status = "disputed" | .dispute = {reason: $why, at: $at}' ;;
    accepted) filter='.status = "fixed" | .dispute.pm = {answer: "accepted", words: $why, at: $at, card: $card}' ;;
    rejected) filter='.status = "open" | .dispute.pm = {answer: "rejected", words: $why, at: $at}' ;;
    *) _die "--pm takes accepted or rejected" 2 ;;
  esac
  jq --arg f "$FINGERPRINT" --arg why "$REASON" --arg at "$(_now)" --arg card "$CARD" "
    .findings |= map(if .fingerprint == \$f then (${filter}) else . end)
    | .blockers_open = ([.findings[] | select(.severity == \"blocker\" and (.status == \"open\" or .status == \"disputed\"))] | length)
  " "${dir}/merged.json" > "${dir}/merged.json.tmp" && mv "${dir}/merged.json.tmp" "${dir}/merged.json"
  # A closed step round carries its verdict in four places; the FSM reads the index.
  if [[ "$MODE" == step && -f "${dir}/measurement.json" ]]; then
    local v f index="${BASE}/rounds.json"
    v="$(_round_verdict "${dir}/merged.json")"
    for f in "${dir}/measurement.json" "${dir}/round.json"; do
      jq --arg v "$v" '.verdict = $v' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    done
    jq --argjson r "$ROUND" --arg v "$v" '.rounds |= map(if .round == $r then .verdict = $v else . end)
      | if ([.rounds[].round] | max) == $r then .verdict = $v else . end' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
    [[ "$CHECKPOINT" == cp3 ]] && { _semantic_final_write "$v" || _die "${EVID}/semantic-review-final.json was not rewritten; run the dispute again"; }
    _log review_dispute checkpoint="$CHECKPOINT" step="${STEP:-null}" round="$ROUND" fingerprint="$FINGERPRINT" answer="${PM_ANSWER:-disputed}" verdict="$v"
  fi
  # status "fixed" closes a finding the PM dismissed too; say which one it is
  echo "finding ${FINGERPRINT}: $(jq -r --arg f "$FINGERPRINT" '.findings[] | select(.fingerprint == $f)
    | if .dispute.pm.answer == "accepted" then "dismissed by the PM (dispute accepted)" else .status end' "${dir}/merged.json")"
}

cmd_override() {
  [[ "$ROUNDS" =~ ^[1-3]$ ]] || _die "--rounds takes 1, 2 or 3" 2
  (( ${#REASON} >= 20 )) || _die "--reason must quote the PM's words (at least 20 characters)" 2
  [[ -f "${BASE}/override.json" ]] && _die "override.json already exists; the PM's instruction is recorded once"
  if (( ROUNDS == 1 )); then
    [[ -f "$(_round_dir 1)/measurement.json" ]] || _die "--rounds 1 comes after round 1 is closed"
  fi
  mkdir -p "$BASE"
  if [[ "$MODE" == plan ]]; then
    jq -n --argjson n "$ROUNDS" --arg at "$(_now)" --arg why "$REASON" --arg sha "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
      '{rounds: $n, by: "PM", at: $at, reason: $why, plan_sha256_at_issue: $sha, recorded_by: "controller"}' > "${BASE}/override.json"
  else
    jq -n --argjson n "$ROUNDS" --arg at "$(_now)" --arg why "$REASON" --arg sha "$(_head)" \
      '{rounds: $n, by: "PM", at: $at, reason: $why, head_sha_at_issue: $sha, recorded_by: "controller"}' > "${BASE}/override.json"
  fi
  _log review_override checkpoint="$CHECKPOINT" step="${STEP:-null}" rounds="$ROUNDS"
  echo "recorded the PM's instruction: ${ROUNDS} round(s) (${BASE}/override.json)"
}

case "$CMD" in
  prepare)   cmd_prepare ;;
  dispatch)  cmd_dispatch ;;
  retry)     cmd_retry ;;
  collect)   cmd_collect ;;
  close)     cmd_close ;;
  fix-check) cmd_fix_check ;;
  finalize)  cmd_finalize ;;
  dispute)   cmd_dispute ;;
  override)  cmd_override ;;
  *) echo "unknown subcommand: ${CMD}" >&2; usage ;;
esac
