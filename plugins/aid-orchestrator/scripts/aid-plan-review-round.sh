#!/usr/bin/env bash
# =============================================================================
# aid-plan-review-round.sh — plan review (CP1), one round at a time.
#
# The controller runs these subcommands in the order commands/aid-plan.md
# "Plan review (CP1)" lists; every one of them loads and validates
# review_checkpoints.plan_review first. Evidence lives under
# .aid-o/work/evidence/<plan_id>/cp1/ (rounds.json, round-N/, override.json).
#
#   prepare <plan> --round N [--only <role>] [--manual]
#       build the packet and one prompt per expected reviewer
#   dispatch <plan> --round N --provider codex --role <r>
#       run one codex reviewer (claude reviewers are dispatched by the controller)
#   collect <plan> --round N
#       validate the answers, decide whether the round is valid, adjudicate
#   close <plan> --round N --tokens <role>=<n|unknown> ...
#       write measurement.json; a round counts only once it is closed
#   retry <plan> --round N --role <r>
#       clear one invalid or missing reviewer so it can answer again
#   fix-check <plan> --round N
#       check the author's fix against the round's packet and fix list
#   dispute <plan> --round N --fingerprint <f> --reason "<why>" [--pm accepted|rejected]
#       mark a finding disputed (it stays open); with --pm record the PM's answer
#       in the PM's words: accepted closes the finding, rejected reopens it
#   finalize <plan>
#       the one edit after the last round: its fixes plus acceptance criteria
#   override <plan> --rounds 1|2|3 --reason "<the PM's words>"
#       record the PM's instruction to run one round, or a third
#
# Common options: --project-root <dir> (default: the plan's own workspace).
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

usage() { sed -n '4,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

CMD="${1:-}"; [[ -n "$CMD" && "$CMD" != -h && "$CMD" != --help ]] || usage
shift
PLAN="" ROUND="" ROOT="" ONLY="" MANUAL=0 ROLE="" PROVIDER="" FINGERPRINT="" REASON="" ROUNDS="" PM_ANSWER=""
TOKENS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --round)        ROUND="${2:-}"; shift 2 ;;
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --only)         ONLY="${2:-}"; shift 2 ;;
    --manual)       MANUAL=1; shift ;;
    --role)         ROLE="${2:-}"; shift 2 ;;
    --provider)     PROVIDER="${2:-}"; shift 2 ;;
    --fingerprint)  FINGERPRINT="${2:-}"; shift 2 ;;
    --reason)       REASON="${2:-}"; shift 2 ;;
    --rounds)       ROUNDS="${2:-}"; shift 2 ;;
    --pm)           PM_ANSWER="${2:-}"; shift 2 ;;
    --tokens)       shift; while [[ $# -gt 0 && "$1" != --* ]]; do TOKENS+=("$1"); shift; done ;;
    -*) echo "${CMD}: unknown option $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done

_die() { echo "${CMD}: $1" >&2; exit "${2:-1}"; }

for tool in jq yq sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || _die "${tool} not installed" 2
done
[[ -n "$PLAN" && -f "$PLAN" ]] || _die "plan file required (got '${PLAN}')" 2
PLAN="$(realpath "$PLAN")"
[[ -n "$ROOT" ]] || ROOT="$(_aid_plan_project_root "$PLAN")" || _die "the plan is not inside an AID workspace; pass --project-root" 2
PLAN_ID="$(_aid_plan_id_of "$PLAN")" || _die "the plan has no valid frontmatter id" 2
CP1="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/cp1"

aid_review_config_load "$ROOT" plan_review "${SCRIPT_DIR}/../skills/plan-review-roles.md" || exit 2
aid_review_config_validate || exit 1

_need_round() { [[ "$ROUND" =~ ^[1-9][0-9]*$ ]] || _die "--round N required" 2; }
_round_dir() { printf '%s/round-%s' "$CP1" "$1"; }
_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# _override_rounds — the PM's recorded round count, or nothing.
_override_rounds() { [[ -f "${CP1}/override.json" ]] && jq -r '.rounds // empty' "${CP1}/override.json" 2>/dev/null; }

# _expected_roles <round> — the reviewers a round asks, one per line.
_expected_roles() {
  local n="$1" roles prev fix type
  type="$(_aid_fm_get "$PLAN" type)"
  if [[ "$type" == docs ]]; then roles="$RC_EXTRA_DOCS_TYPE_REVIEWERS"; else roles="${RC_ROLE[*]}"; fi
  if (( n >= 2 )); then
    # The confirmation round asks only reviewers whose findings touch a changed
    # step, plus every reviewer of a blocker or major still open.
    prev="$(_round_dir $((n - 1)))/merged.json"; fix="$(_round_dir $((n - 1)))/fix-diff.json"
    local narrow
    narrow="$(jq -r --slurpfile fd "$fix" '
      ($fd[0].steps_changed // []) as $changed
      | [.findings[] | select(.step != null and (.step | IN($changed[]))
                              or ((.severity == "blocker" or .severity == "major") and .status != "fixed"))
         | .reported_by[]] | unique | .[]' "$prev")"
    roles="$(for r in $roles; do grep -qxF "$r" <<<"$narrow" && echo "$r"; done)"
  fi
  if [[ -n "$ONLY" ]]; then
    [[ " ${roles//$'\n'/ } " == *" ${ONLY} "* ]] || _die "role ${ONLY} is not expected in this round"
    roles="$ONLY"
  fi
  printf '%s\n' $roles
}

cmd_prepare() {
  _need_round
  local dir index check
  check="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/plan-check.json"
  [[ -f "$check" ]] || _die "no plan-check.json for ${PLAN_ID}; run aid-plan-check.sh ${PLAN} --json ${check}"

  if (( MANUAL )); then
    (( ROUND == 1 )) || _die "--manual runs one reviewer on the plan as it is; use --round 1" 2
    dir="${CP1}/manual/$(date -u +%Y%m%dT%H%M%SZ)"
  else
    dir="$(_round_dir "$ROUND")"
    [[ -d "${dir}/packet" ]] && _die "round ${ROUND} already prepared; a retry goes through 'retry', a fresh round through the next number"
    if (( ROUND > RC_ROUNDS_DEFAULT )); then
      local allowed; allowed="$(_override_rounds)"
      [[ -n "$allowed" && "$allowed" -ge "$ROUND" ]] \
        || _die "round ${ROUND} exceeds rounds_default ${RC_ROUNDS_DEFAULT}; it needs the PM's override.json (aid-plan-review-round.sh override)"
    fi
    if (( ROUND >= 2 )); then
      local prev; prev="$(_round_dir $((ROUND - 1)))"
      [[ -f "${prev}/fix-diff.json" ]] || _die "round $((ROUND - 1)) has no fix-diff.json; run fix-check first"
      [[ "$(jq -r '.pass' "${prev}/fix-diff.json")" == true ]] \
        || _die "the fix of round $((ROUND - 1)) did not pass fix-check: $(jq -c '.added_outside_fixes' "${prev}/fix-diff.json")"
      [[ "$(jq '[.findings[] | select(.status != "fixed" and (.severity == "blocker" or .severity == "major"))] | length' "${prev}/merged.json")" -gt 0 ]] \
        || _die "nothing to confirm: round $((ROUND - 1)) left no open blocker or major finding"
    fi
  fi

  mkdir -p "$dir" || _die "cannot create ${dir}"
  # A half-prepared round is removed whole, so a second prepare can run.
  trap 'rm -rf "$dir"' EXIT
  aid_plan_review_packet_build "$PLAN" "$ROOT" "$check" "$dir" || exit 1

  local roles=() role
  mapfile -t roles < <(_expected_roles "$ROUND" | grep -v '^$')
  local min; min="$(aid_review_config_floor "${#roles[@]}")"
  jq -n --argjson round "$ROUND" --arg sha "$(jq -r .plan_sha256 "${dir}/packet/manifest.json")" \
    --argjson min "$min" --arg at "$(_now)" --argjson degraded "$([[ "$RC_DEGRADED" == 1 ]] && echo true || echo false)" \
    '{round: $round, plan_sha256: $sha, reviewers_expected: $ARGS.positional,
      min_answers_effective: $min, degraded: $degraded, started_at: $at}' \
    --args "${roles[@]}" > "${dir}/round.json"

  for role in "${roles[@]}"; do
    aid_plan_review_prompt_render "$role" "$ROUND" "$dir" || exit 1
  done

  trap - EXIT
  if (( ! MANUAL )); then
    index="${CP1}/rounds.json"
    [[ -f "$index" ]] || echo '[]' > "$index"
    jq --argjson r "$ROUND" --arg sha "$(jq -r .plan_sha256 "${dir}/round.json")" --arg at "$(_now)" \
      '. + [{round: $r, plan_sha256: $sha, prepared_at: $at}]' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
    aid_plan_log "$PLAN" plan_review_round_start round="$ROUND" reviewers="${#roles[@]}"
  fi
  echo "prepared round ${ROUND}: ${#roles[@]} reviewers → ${dir}"
  for role in "${roles[@]}"; do echo "  ${dir}/prompt-${role}.md"; done
}

_existing_round() {
  _need_round
  local dir; dir="$(_round_dir "$ROUND")"
  [[ -f "${dir}/round.json" ]] || _die "round ${ROUND} is not prepared (${dir}/round.json missing)"
  printf '%s' "$dir"
}
# _json_strings <s>... — the arguments as a JSON array of strings.
_json_strings() { jq -nc '$ARGS.positional' --args "$@"; }
_expects() { jq -e --arg r "$1" '.reviewers_expected | index($r) != null' "$2/round.json" >/dev/null; }

cmd_dispatch() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ "$PROVIDER" == codex ]] || _die "--provider codex required; claude reviewers are dispatched by the controller (scripts/lib/aid-plan-review-adapter-claude.md)" 2
  [[ -n "$ROLE" ]] || _die "--role required" 2
  _expects "$ROLE" "$dir" || _die "role ${ROLE} is not expected in round ${ROUND}"
  local i; i="$(aid_review_role_index "$ROLE")"
  [[ "${RC_PROVIDER[$i]}" == codex ]] \
    || _die "role ${ROLE} is dispatched by the controller (see scripts/lib/aid-plan-review-adapter-claude.md)"
  local answer="${dir}/reviewer-${ROLE}.json" usage="${dir}/codex-${ROLE}.usage.json"
  [[ -e "$answer" ]] && _die "${answer} already exists; a reviewer is never paid twice (use retry after collect lists it as invalid)"

  if ! command -v codex >/dev/null 2>&1; then
    jq -n '{answered: false, reason: "codex_absent"}' > "$usage"
    echo "codex is not installed; ${ROLE} is recorded as not answered — continue with the other reviewers, then collect"
    return 0
  fi
  local events="${dir}/codex-${ROLE}.events.jsonl" last="${dir}/codex-${ROLE}.last.txt" rc=0
  # In a subshell: the launcher's library sets its own shell options on load.
  ( # shellcheck source=lib/aid-c3-dispatch.sh
    source "${SCRIPT_DIR}/lib/aid-c3-dispatch.sh"
    CODEX_MODEL="${RC_MODEL[$i]}"
    _run_codex_isolated "$ROOT" "${dir}/prompt-${ROLE}.md" "$events" "${dir}/codex-${ROLE}.stderr.txt" "$last"
  ) || rc=$?

  if [[ -s "$last" ]]; then
    aid_plan_review_unfence "$last" "$answer"
  fi
  if [[ -s "$answer" ]]; then
    jq -s 'map(select(.type == "turn.completed")) | last | .usage // {}
           | {answered: true, tokens_in: (.input_tokens // "unknown"), cache_read: (.cached_input_tokens // "unknown"),
              tokens_out: (.output_tokens // "unknown")}' "$events" > "$usage" 2>/dev/null \
      || jq -n '{answered: true, tokens_in: "unknown", tokens_out: "unknown"}' > "$usage"
    echo "dispatched ${ROLE} (codex ${RC_MODEL[$i]}): answer in ${answer}"
  else
    rm -f "$answer"
    jq -n --arg why "$([[ "$rc" == 124 ]] && echo timeout || echo no_file)" '{answered: false, reason: $why}' > "$usage"
    _die "codex returned no answer for ${ROLE} (exit ${rc}); recorded as not answered, see ${dir}/codex-${ROLE}.stderr.txt"
  fi
}

cmd_retry() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ -n "$ROLE" ]] || _die "--role required" 2
  [[ -f "${dir}/collect.json" ]] || _die "round ${ROUND} is not collected; retry is for a role collect listed as invalid or missing"
  jq -e --arg r "$ROLE" '(.missing | index($r)) or ([.invalid[].role] | index($r))' "${dir}/collect.json" >/dev/null \
    || _die "role ${ROLE} answered validly in round ${ROUND}; a valid answer is never paid for twice"
  [[ -f "${dir}/measurement.json" ]] && _die "round ${ROUND} is closed"
  rm -f "${dir}/reviewer-${ROLE}.json" "${dir}/reviewer-${ROLE}.invalid.txt" "${dir}/reviewer-${ROLE}.missing" \
        "${dir}/codex-${ROLE}".*
  echo "retry ${ROLE}: dispatch ${dir}/prompt-${ROLE}.md again, then collect"
}

cmd_collect() {
  local dir; dir="$(_existing_round)" || exit 1
  local role tmp err valid=() invalid=() missing=() unexpected=()
  tmp="$(mktemp)"
  for role in $(jq -r '.reviewers_expected[]' "${dir}/round.json"); do
    local answer="${dir}/reviewer-${role}.json"
    if [[ ! -s "$answer" ]]; then missing+=("$role"); continue; fi
    aid_plan_review_unfence "$answer" "$tmp"
    if err="$(aid_plan_review_answer_error "$tmp")"; then
      if [[ "$(jq -r '.role' "$tmp")" != "$role" ]]; then
        err="role_mismatch: the file names role $(jq -r '.role' "$tmp")"
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
  jq -e '.reviewers_expected | map(select(startswith("generalist_"))) | length > 0' "${dir}/round.json" >/dev/null && generalist_expected=true
  [[ " ${valid[*]} " == *" generalist_"* ]] && generalist_present=true
  status=valid
  if (( ${#valid[@]} < required )); then
    status=invalid; reason="${#valid[@]} of $(jq '.reviewers_expected | length' "${dir}/round.json") answered (min ${required})"
  elif [[ "$generalist_expected" == true && "$generalist_present" == false ]]; then
    status=invalid; reason="no generalist answered"
  fi

  jq -n --argjson valid "$(_json_strings "${valid[@]}")" \
        --argjson invalid "$(printf '%s\n' "${invalid[@]}" | jq -s '.')" \
        --argjson missing "$(_json_strings "${missing[@]}")" \
        --argjson unexpected "$(_json_strings "${unexpected[@]}")" \
        --argjson required "$required" --argjson gp "$generalist_present" --arg status "$status" --arg reason "$reason" \
    '{valid: $valid, invalid: $invalid, missing: $missing, unexpected: $unexpected,
      answered: ($valid | length), required: $required, generalist_present: $gp,
      status: $status} + (if $reason == "" then {} else {reason: $reason} end)' > "${dir}/collect.json"

  if [[ "$status" != valid ]]; then
    echo "round ${ROUND} invalid: ${reason}; answered reviewers keep their answers, retry only: $(jq -r '[.missing[], .invalid[].role] | join(", ")' "${dir}/collect.json")" >&2
    exit 1
  fi
  local prev=()
  (( ROUND >= 2 )) && [[ -f "$(_round_dir $((ROUND - 1)))/merged.json" ]] && prev=(--previous "$(_round_dir $((ROUND - 1)))")
  "${SCRIPT_DIR}/aid-plan-review-adjudicate.sh" "$dir" --project-root "$ROOT" "${prev[@]}" >/dev/null || exit 1
  echo "round ${ROUND}: ${#valid[@]} of $(jq '.reviewers_expected | length' "${dir}/round.json") answered, missing: $(jq -r '[.missing[], .invalid[].role] | if length == 0 then "none" else join(", ") end' "${dir}/collect.json"), $(jq '.blockers_open' "${dir}/merged.json") blockers open, $(jq 'length' "${dir}/rejected.json") findings rejected"
}

# _token_value <role> — the --tokens value given for <role>, or nothing.
_token_value() {
  local kv
  for kv in "${TOKENS[@]}"; do [[ "${kv%%=*}" == "$1" ]] && { printf '%s' "${kv#*=}"; return 0; }; done
  return 1
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
    echo "round ${ROUND}: measurement updated"; return 0
  fi

  local reviewers='{}' entry usage status reason
  for role in $(jq -r '.reviewers_expected[]' "${dir}/round.json"); do
    i="$(aid_review_role_index "$role")"
    status="$(jq -r --arg r "$role" 'if (.valid | index($r)) then "answered" elif (.missing | index($r)) then "missing" else "invalid" end' "${dir}/collect.json")"
    if [[ "${RC_PROVIDER[$i]}" == codex ]]; then
      usage="${dir}/codex-${role}.usage.json"
      if [[ -f "$usage" ]]; then
        entry="$(jq -c '{tokens: (if (.tokens_in | type) == "number" and (.tokens_out | type) == "number" then .tokens_in + .tokens_out else "unknown" end)}
                        + (del(.answered, .reason)) + (if .reason then {reason} else {} end)' "$usage")"
      else
        entry='{"tokens":"unknown","reason":"no_file"}'
      fi
    else
      value="$(_token_value "$role")" || _die "no --tokens value for ${role}; pass ${role}=<number> from the Agent result, or ${role}=unknown"
      entry="$(jq -nc --arg v "$value" '{tokens: (if $v == "unknown" then "unknown" else ($v | tonumber) end)}')"
    fi
    reason=""
    [[ "$status" == missing ]] && reason="$(jq -r '.reason // "no_file"' <<< "$entry")"
    [[ "$status" == invalid ]] && reason=invalid_answer
    reviewers="$(jq -c --arg r "$role" --argjson e "$entry" --arg p "${RC_PROVIDER[$i]}" --arg m "${RC_MODEL[$i]}" \
      --argjson ok "$([[ "$status" == answered ]] && echo true || echo false)" --arg why "$reason" \
      '.[$r] = ({provider: $p, model: $m, answered: $ok} + ($e | del(.reason)) + (if $why == "" then {} else {reason: $why} end))' <<< "$reviewers")"
  done
  jq -n --argjson round "$ROUND" --arg start "$(jq -r .started_at "${dir}/round.json")" --arg finish "$(_now)" \
        --argjson reviewers "$reviewers" --argjson degraded "$(jq '.degraded' "${dir}/round.json")" \
    '{round: $round, started_at: $start, finished_at: $finish, reviewers: $reviewers, degraded: $degraded}' > "$measurement"
  aid_plan_log "$PLAN" plan_review_round_complete round="$ROUND" \
    status="$(jq -r .status "${dir}/collect.json")" blockers_open="$(jq -r '.blockers_open // 0' "${dir}/merged.json" 2>/dev/null || echo 0)"
  echo "round ${ROUND} closed: $(jq -r '[.reviewers | to_entries[] | "\(.key)=\(.value.tokens)"] | join(" ")' "$measurement")"
}

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
  local dir; dir="$(_existing_round)" || exit 1
  [[ -f "${dir}/merged.json" ]] || _die "round ${ROUND} not collected"
  [[ -f "${dir}/measurement.json" ]] || _die "round ${ROUND} is not closed; run close first"
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
  for d in "${CP1}"/round-*/; do
    [[ -f "${d}measurement.json" ]] || continue
    n="${d%/}"; n="${n##*-}"
    [[ "$n" =~ ^[0-9]+$ ]] && { [[ -z "$best" ]] || (( n > best )); } && best="$n"
  done
  printf '%s' "$best"
}

cmd_finalize() {
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

cmd_dispute() {
  local dir; dir="$(_existing_round)" || exit 1
  [[ -n "$FINGERPRINT" && ${#REASON} -ge 20 ]] || _die "--fingerprint and a --reason of at least 20 characters required" 2
  [[ -f "${dir}/merged.json" ]] || _die "round ${ROUND} not collected"
  local final
  for final in "${CP1}"/round-*/plan-final.md; do
    [[ -f "$final" ]] && cmp -s "$PLAN" "$final" \
      && _die "the plan is finalized (plan-final.md matches it); a dispute now would change what the acceptance criteria must quote — edit the plan and finalize again"
  done
  jq -e --arg f "$FINGERPRINT" '.findings | map(.fingerprint) | index($f) != null' "${dir}/merged.json" >/dev/null \
    || _die "no finding ${FINGERPRINT} in round ${ROUND}"
  local filter
  case "$PM_ANSWER" in
    "")       filter='.status = "disputed" | .dispute = {reason: $why, at: $at}' ;;
    accepted) filter='.status = "fixed" | .dispute.pm = {answer: "accepted", words: $why, at: $at}' ;;
    rejected) filter='.status = "open" | .dispute.pm = {answer: "rejected", words: $why, at: $at}' ;;
    *) _die "--pm takes accepted or rejected" 2 ;;
  esac
  jq --arg f "$FINGERPRINT" --arg why "$REASON" --arg at "$(_now)" "
    .findings |= map(if .fingerprint == \$f then (${filter}) else . end)
    | .blockers_open = ([.findings[] | select(.severity == \"blocker\" and (.status == \"open\" or .status == \"disputed\"))] | length)
  " "${dir}/merged.json" > "${dir}/merged.json.tmp" && mv "${dir}/merged.json.tmp" "${dir}/merged.json"
  echo "finding ${FINGERPRINT}: $(jq -r --arg f "$FINGERPRINT" '.findings[] | select(.fingerprint == $f) | .status' "${dir}/merged.json")"
}

cmd_override() {
  [[ "$ROUNDS" =~ ^[1-3]$ ]] || _die "--rounds takes 1, 2 or 3" 2
  (( ${#REASON} >= 20 )) || _die "--reason must quote the PM's words (at least 20 characters)" 2
  [[ -f "${CP1}/override.json" ]] && _die "override.json already exists; the PM's instruction is recorded once"
  if (( ROUNDS == 1 )); then
    [[ -f "$(_round_dir 1)/measurement.json" ]] || _die "--rounds 1 comes after round 1 is closed"
  fi
  mkdir -p "$CP1"
  jq -n --argjson n "$ROUNDS" --arg at "$(_now)" --arg why "$REASON" --arg sha "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
    '{rounds: $n, by: "PM", at: $at, reason: $why, plan_sha256_at_issue: $sha, recorded_by: "controller"}' > "${CP1}/override.json"
  aid_plan_log "$PLAN" plan_review_override rounds="$ROUNDS"
  echo "recorded the PM's instruction: ${ROUNDS} round(s) (${CP1}/override.json)"
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
