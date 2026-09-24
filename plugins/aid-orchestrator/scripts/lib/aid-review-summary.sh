#!/usr/bin/env bash
# aid-review-summary.sh — what a review checkpoint cost, in tokens and USD.
# One library for every checkpoint (P094 Step 11).
#
#   aid_review_usd <model> <in> <out> <cache_read> <cache_write>
#       USD (four decimals) from defaults/prices.yaml (a project's
#       .aid-o/config/prices.yaml wins); "unknown" for an unlisted model, a
#       missing table or a non-numeric count.
#   aid_review_usd_blended <model> <tokens>
#       USD from the model's `blended` rate — for a figure reported as one total.
#   aid_review_prices_file        prints the table in use (AID_REVIEW_PRICES, project, default), or nothing
#   aid_review_summary <cp dir>   one line (≤ 120 chars) for one checkpoint directory
#       (<evidence>/cp1, <run>/cp2/step-N, <run>/cp3, <do>/cp6):
#         review: none | review: legacy evidence
#         review: skip (small, clean, in scope)          (a skip/no_change index)
#         review: 2 rounds, 812000 tokens, 1 unknown, 4.1200 USD, missing: generalist_b, degraded: yes[, round 2 not closed][, verdict fail]
#         review: 2 rounds, measurement unreadable (round 1)
#   aid_epic_review_summary <run dir>
#       one line over every cp2/step-*/ and cp3/:
#         steps: 5 (3 skip, 2 rounds), cp3: pass, 1234567 tokens, 2 unknown, 9.8765 USD[, step 3 round 1 not closed]
#   A token value a reviewer could not report is counted as unknown, never
#   summed as zero, so an unmeasured round never looks free.
#   aid_plan_close_time <project_root> <plan_id> [epic_run_dir...]
#       where the plan's time went, in minutes, as JSON (P099 Step 7).
# NO top-level `set -e` — sourced under the caller's own shell.

_AID_RS_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=aid-session-store.sh
source "$(dirname "${BASH_SOURCE[0]}")/aid-session-store.sh"

aid_review_prices_file() {
  # AID_REVIEW_PRICES names a table explicitly (a PM's what-if, a test fixture).
  if [[ -n "${AID_REVIEW_PRICES:-}" ]]; then
    [[ -f "$AID_REVIEW_PRICES" ]] && { printf '%s\n' "$AID_REVIEW_PRICES"; return 0; }
    return 1
  fi
  local root="${AID_PROJECT_ROOT:-${1:-}}"
  [[ -n "$root" && -f "${root}/.aid-o/config/prices.yaml" ]] && { printf '%s\n' "${root}/.aid-o/config/prices.yaml"; return 0; }
  [[ -f "${_AID_RS_PLUGIN}/defaults/prices.yaml" ]] && { printf '%s\n' "${_AID_RS_PLUGIN}/defaults/prices.yaml"; return 0; }
  return 1
}

# _aid_rs_rate <model> <field> — the rate or "" (missing table, model or field)
_aid_rs_rate() {
  local f; f="$(aid_review_prices_file)" || return 1
  local v; v="$(yq -r ".models[\"$1\"].$2 // \"\"" "$f" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+([.][0-9]+)?$ ]] && printf '%s' "$v"
}

aid_review_usd() {
  local model="$1" in="$2" out="$3" cr="${4:-0}" cw="${5:-0}" ri ro rr rw
  for v in "$in" "$out" "$cr" "$cw"; do [[ "$v" =~ ^[0-9]+$ ]] || { echo unknown; return 0; }; done
  ri="$(_aid_rs_rate "$model" input)"; ro="$(_aid_rs_rate "$model" output)"
  rr="$(_aid_rs_rate "$model" cache_read)"; rw="$(_aid_rs_rate "$model" cache_write)"
  [[ -n "$ri" && -n "$ro" ]] || { echo unknown; return 0; }
  awk -v i="$in" -v o="$out" -v c="$cr" -v w="$cw" -v ri="$ri" -v ro="$ro" -v rr="${rr:-0}" -v rw="${rw:-0}" \
    'BEGIN { printf "%.4f\n", (i*ri + o*ro + c*rr + w*rw) / 1000000 }'
}

aid_review_usd_blended() {
  local model="$1" t="$2" r
  [[ "$t" =~ ^[0-9]+$ ]] || { echo unknown; return 0; }
  r="$(_aid_rs_rate "$model" blended)"
  [[ -n "$r" ]] || { echo unknown; return 0; }
  awk -v t="$t" -v r="$r" 'BEGIN { printf "%.4f\n", t*r/1000000 }'
}

# _aid_rs_rounds <cp dir> — the round numbers, sorted
_aid_rs_rounds() {
  local d n
  for d in "$1"/round-*/; do
    [[ -d "$d" ]] || continue
    n="${d%/}"; n="${n##*-}"; [[ "$n" =~ ^[0-9]+$ ]] && printf '%s\n' "$n"
  done | sort -n
}

# _aid_rs_sum <measurement files…> — prints "<tokens> <unknown> <usd|unknown> <usd_unknown_count>"
_aid_rs_sum() {
  jq -rs '
    ([.[].reviewers[]] + [.[] | .fixer // empty]) as $r
    | ([$r[] | .tokens | select(type == "number")] | add // 0) as $sum
    | ([$r[] | select((.tokens | type) != "number")] | length) as $unknown
    | ([$r[] | .usd | select(type == "number")] | add // 0) as $usd
    | ([$r[] | select((.usd | type) != "number")] | length) as $usd_unknown
    | "\($sum) \($unknown) \($usd) \($usd_unknown)"' "$@"
}

aid_review_summary() {
  local cp="${1:?aid_review_summary: checkpoint directory required}" n open="" m
  if [[ ! -d "$cp" ]]; then
    [[ -d "${cp%/cp1}/cp1-deep" && "$cp" == */cp1 ]] && echo "review: legacy evidence" || echo "review: none"
    return 0
  fi
  local rounds=(); mapfile -t rounds < <(_aid_rs_rounds "$cp")
  if (( ${#rounds[@]} == 0 )); then
    local v; v="$(jq -r '.verdict // ""' "${cp}/rounds.json" 2>/dev/null)"
    case "$v" in
      skip|no_change) echo "review: ${v} ($(jq -r '.reason // "no reason recorded"' "${cp}/rounds.json"))" ;;
      *) echo "review: none" ;;
    esac
    return 0
  fi
  local files=()
  for n in "${rounds[@]}"; do
    m="${cp}/round-${n}/measurement.json"
    if [[ ! -f "$m" ]]; then open="${open:+${open}, }round ${n} not closed"; continue; fi
    jq -e '.reviewers | type == "object"' "$m" >/dev/null 2>&1 \
      || { echo "review: ${#rounds[@]} rounds, measurement unreadable (round ${n})"; return 0; }
    files+=("$m")
  done
  local line="review: ${#rounds[@]} round$( (( ${#rounds[@]} == 1 )) || echo s)"
  if (( ${#files[@]} )); then
    local tok unk usd usd_unk; read -r tok unk usd usd_unk <<< "$(_aid_rs_sum "${files[@]}")"
    line+=", ${tok} tokens, ${unk} unknown"
    if (( usd_unk == 0 )); then line+=", $(printf '%.4f' "$usd") USD"
    elif [[ "$usd" != 0 ]]; then line+=", $(printf '%.4f' "$usd") USD + ${usd_unk} unknown"
    else line+=", USD unknown"; fi
    line+=", missing: $(jq -rs '[.[].reviewers | to_entries[] | select(.value.answered == false) | .key] | unique
                               | if length == 0 then "none" else join(", ") end' "${files[@]}")"
    line+=", degraded: $(jq -rs 'if any(.[]; .degraded == true) then "yes" else "no" end' "${files[@]}")"
  fi
  [[ -n "$open" ]] && line+=", ${open}"
  local verdict; verdict="$(jq -r 'if type == "object" then (.verdict // "") else "" end' "${cp}/rounds.json" 2>/dev/null)"
  [[ "$verdict" == fail ]] && line+=", verdict fail"
  printf '%s\n' "${line:0:120}"
}

aid_epic_review_summary() {
  local run="${1:?aid_epic_review_summary: run directory required}" d n skips=0 rounds=0 open="" files=() v
  local steps=() cp3="none"
  for d in "$run"/cp2/step-*/; do
    [[ -d "$d" ]] || continue
    n="${d%/}"; n="${n##*-}"; steps+=("$n")
    v="$(jq -r '.verdict // ""' "${d}rounds.json" 2>/dev/null)"
    case "$v" in skip|no_change) skips=$((skips + 1)) ;; *) rounds=$((rounds + 1)) ;; esac
    local r; for r in $(_aid_rs_rounds "${d%/}"); do
      if [[ -f "${d}round-${r}/measurement.json" ]]; then files+=("${d}round-${r}/measurement.json")
      else open="${open:+${open}, }step ${n} round ${r} not closed"; fi
    done
  done
  if [[ -d "$run/cp3" ]]; then
    cp3="$(jq -r '.verdict // "open"' "$run/cp3/rounds.json" 2>/dev/null || echo open)"
    for r in $(_aid_rs_rounds "$run/cp3"); do
      if [[ -f "$run/cp3/round-${r}/measurement.json" ]]; then files+=("$run/cp3/round-${r}/measurement.json")
      else open="${open:+${open}, }cp3 round ${r} not closed"; fi
    done
  fi
  (( ${#steps[@]} == 0 )) && [[ "$cp3" == none ]] && { echo "steps: none reviewed"; return 0; }
  local line="steps: ${#steps[@]} (${skips} skip, ${rounds} rounds), cp3: ${cp3}"
  if (( ${#files[@]} )); then
    local tok unk usd usd_unk; read -r tok unk usd usd_unk <<< "$(_aid_rs_sum "${files[@]}")"
    line+=", ${tok} tokens, ${unk} unknown"
    if (( usd_unk == 0 )); then line+=", $(printf '%.4f' "$usd") USD"
    elif [[ "$usd" != 0 ]]; then line+=", $(printf '%.4f' "$usd") USD + ${usd_unk} unknown"
    else line+=", USD unknown"; fi
  fi
  [[ -n "$open" ]] && line+=", ${open}"
  aid_review_prices_file >/dev/null || line+=", prices.yaml missing"
  printf '%s\n' "${line:0:120}"
}

# aid_plan_close_cost <plan evidence dir> <plan_id> — what closing the plan has
# cost so far, over every plan-final attempt on disk: {attempts, minutes (from
# the first attempt's first file to now), usd (the cp7 rounds, fixers included),
# usd_unknown_roles (roles whose figure is unknown; never counted as zero)}.
aid_plan_close_cost() {
  local dir="$1" plan_id="$2" first
  local -a runs=() files=()
  mapfile -t runs < <(ls -d "$dir"/R-"${plan_id}"-final-* 2>/dev/null | sort -t- -k4 -n)
  mapfile -t files < <(ls "$dir"/R-"${plan_id}"-final-*/cp7/round-*/measurement.json 2>/dev/null)
  first="$(find "${runs[0]:-/nonexistent}" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -n | head -n1)"
  first="${first%.*}"; first="${first:-null}"
  jq -n --argjson attempts "${#runs[@]}" --argjson first "$first" --argjson now "$(date +%s)" \
        --slurpfile m <(cat /dev/null "${files[@]}") '
    ([$m[] | (.reviewers | to_entries[]), (.fixer // empty | {key: "fixer:\(.role)", value: .})]) as $r
    | {attempts: $attempts, minutes: (if $first then (($now - $first) / 60 | floor) else 0 end),
       usd: ([$r[].value.usd | select(type == "number")] | add // 0 | . * 10000 | round / 10000),
       usd_unknown_roles: ([$r[] | select((.value.usd | type) != "number") | .key] | unique)}'
}

# aid_plan_close_time <project_root> <plan_id> [epic_run_dir...]
#   {work_min, review_min, gates_min, waiting_pm_min, outage_min}; a number
#   nobody could measure is null ("neměřeno" on the page), never 0.
#     review   every review round's own start..end (measurement.json): CP1,
#              the EPICs' CP2/CP3, the plan-final CP7
#     gates    gate_runner_start..gate_runner_complete in the EPIC and plan-final
#              timelines
#     waiting  from a Stop the continuation rule let end with a card or a spent
#              budget to the PM's next prompt in that session (hook audit)
#     outage   a gap over 20 minutes after a Stop the rule refused (or let wait)
#              before the session's next hook event — a limit, a crash, a login
#     work     the EPICs' time in EXECUTE minus all of the above
#   Intervals are merged before summing, so two sessions on one plan count once.
#   The sessions of the plan are the ones whose continuation lines name it; the
#   audit is read from the session store (AID_HOOK_AUDIT overrides), with its
#   rotated generations (.2, .1); when the plan began before the oldest line of
#   a full rotation, waiting and outage are null ("not measured"), never
#   understated.
# aid_hook_audit_files — the hook audit and its rotated generations (aid-hook.sh
# rotates at 20 MB into .1 and .2), oldest first, the ones that exist.
aid_hook_audit_files() {
  local a="${AID_HOOK_AUDIT:-$(aid_session_store_dir hooks)/audit.jsonl}" g
  for g in "${a}.2" "${a}.1" "$a"; do [[ -r "$g" ]] && printf '%s\n' "$g"; done
  return 0
}

aid_plan_close_time() {
  local root="$1" plan="$2"; shift 2
  local ev="${root}/.aid-o/work/evidence/${plan}" d audit sids
  local -a m=() tl=()
  mapfile -t m < <(ls "$ev"/cp1/round-*/measurement.json "$ev"/R-"${plan}"-final-*/cp7/round-*/measurement.json 2>/dev/null
                   for d; do find "${root}/${d}" -path '*/cp[23]/*' -name measurement.json 2>/dev/null; done)
  for d; do [[ -f "${root}/${d}/timeline.jsonl" ]] && tl+=("${root}/${d}/timeline.jsonl"); done
  for d in "$ev"/R-"${plan}"-final-*/timeline.jsonl; do [[ -f "$d" ]] && tl+=("$d"); done
  audit="${AID_HOOK_AUDIT:-$(aid_session_store_dir hooks)/audit.jsonl}"
  local -a pat=() gens=()
  mapfile -t gens < <(aid_hook_audit_files)
  local audit_from=""
  if (( ${#gens[@]} )); then
    # Only a full rotation can have dropped lines: then the oldest kept line
    # is where measuring begins.
    [[ -r "${audit}.2" ]] && audit_from="$(head -n1 "${audit}.2" | jq -r '.ts // ""' 2>/dev/null)"
    sids="$(cat "${gens[@]}" | grep -F '"rule":"queue_continuation_notice"' | grep -F "plan=${plan}" | jq -r '.session_id' 2>/dev/null | sort -u)"
    for d in $sids; do pat+=(-e "\"session_id\":\"${d}\""); done
  fi
  # TZ=UTC: jq<1.7 fromdateiso8601 honours the local zone even on a Z suffix (P037);
  # the intervals are compared with $now, a real epoch.
  TZ=UTC jq -n --arg plan "$plan" --argjson now "$(date -u +%s)" \
        --slurpfile m <(cat /dev/null "${m[@]}") \
        --slurpfile t <(for d in "${tl[@]}"; do jq -c --arg f "$d" '. + {_f: $f}' "$d" 2>/dev/null; done) \
        --slurpfile a <( (( ${#pat[@]} )) && cat "${gens[@]}" | grep -F "${pat[@]}") --arg audit_from "$audit_from" '
    def ep: fromdateiso8601? // null;
    def merged: sort_by(.[0]) | reduce .[] as $i ([];
      if length > 0 and $i[0] <= .[-1][1] then .[-1][1] = ([.[-1][1], $i[1]] | max) else . + [$i] end);
    def total: merged | map(.[1] - .[0]) | add // 0;
    def inter($b): [.[] as $x | $b[] as $y | [([$x[0], $y[0]] | max), ([$x[1], $y[1]] | min)] | select(.[0] < .[1])];
    def mins: . / 60 | round;
    # pairs(start_pred; end_pred): each start with the next end in one file
    def pairs(s; e): group_by(._f) | map(sort_by(.ts) | reduce .[] as $x ({o: null, r: []};
        if ($x | s) and .o == null then .o = ($x.ts | ep)
        elif ($x | e) and .o != null then .r += [[.o, ($x.ts | ep)]] | .o = null else . end) | .r) | add // [];
    ([$t[].ts | strings] | min) as $first
    | ($audit_from != "" and $first != null and $first < $audit_from) as $unmeasured
    | ([$m[] | [(.started_at | ep), (.finished_at | ep)] | select(.[0] and .[1])]) as $rev
    | ($t | pairs(.event == "gate_runner_start"; .event == "gate_runner_complete")) as $gat
    | ($t | pairs(.event == "fsm_transition" and .to == "EXECUTE"; .event == "fsm_transition" and .from == "EXECUTE")) as $exe
    | ($a | map(. + {t: (.ts | ep)}) | group_by(.session_id) | map(sort_by(.t))) as $ses
    | ([$ses[] | . as $l | range(0; length) as $i | $l[$i]
        | select(.rule == "queue_continuation_notice" and (.reason | test("^outcome=(handed_over|budget_spent) plan=" + $plan)))
        | [.t, (first($l[$i + 1:][] | select(.event == "UserPromptSubmit") | .t) // $now)]]) as $wait
    | ([$ses[] | . as $l | range(0; length) as $i | $l[$i]
        | select(.rule == "queue_continuation_notice" and (.reason | test("^outcome=(refused|wait) plan=" + $plan)))
        | [.t, (first($l[$i + 1:][] | select(.t > $l[$i].t) | .t) // null)]
        | select(.[1] != null and .[1] - .[0] > 1200)]) as $out
    | (($rev + $gat + $wait + $out) | merged) as $busy
    | {work_min: (if ($exe | length) == 0 then null else ((($exe | total) - ($exe | merged | inter($busy) | total)) | mins) end),
       review_min: (if ($rev | length) == 0 then null else ($rev | total | mins) end),
       gates_min: (if ($t | length) == 0 then null else ($gat | total | mins) end),
       waiting_pm_min: (if ($a | length) == 0 or $unmeasured then null else ($wait | total | mins) end),
       outage_min: (if ($a | length) == 0 or $unmeasured then null else ($out | total | mins) end)}'
}

