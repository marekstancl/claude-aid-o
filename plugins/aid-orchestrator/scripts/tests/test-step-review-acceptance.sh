#!/usr/bin/env bash
# aid-tier: t2
# test-step-review-acceptance.sh — replay the recorded step diffs of the sample through a review
# flow and record what each review found and cost (P094 Steps 1 and 13).
#
# Modes
#   --mode baseline   today's flow: the verbatim verifier prompt header of
#                     agents/verifier.md over the diff and the DoD, one dispatch
#                     per entry (Step 1 of P094)
#   --mode new        the P094 engine (aid-step-check.sh + aid-review-round.sh),
#                     available from Step 6 onward
#
# Subcommands (the model dispatch is the controller's, never this script's)
#   prepare  --mode M --out DIR [--only ID]        materialise diff, DoD and prompt per entry
#            [--model NAME]                        (new) the claude roles' model for this run
#   cleanup  --out DIR                             (new) remove the worktrees prepare added
#   collect  --mode M --out DIR --model NAME       read the answers, write results-<mode>-<model>.json
#            [--tokens ID=total ...]               subagent token totals from the Agent tool result ("unknown" allowed)
#                                                  (new mode: ID:ROLE=total, one per dispatched role)
#   stub     --mode M --model NAME [--only ID]     replay fixtures/step-review/answers/ with the guard
#   final prepare|collect|stub [--out DIR] …        the retired auditor's recorded findings replayed
#                                                   through the whole-plan round (cp7); see "final" below
#   replay-do  --evidence DIR --project-root DIR    re-adjudicate the recorded cp6 rounds under
#                                                   DIR/do/*/cp6/round-1 with THIS tree's adjudicator
#                                                   and print one line per round. A measurement, not
#                                                   an assertion: the citations resolve only against
#                                                   the checkout the round was reviewed in.
#
# The stub guard: `stub` prepends a directory whose `claude` and `codex` exit 99
# to PATH and exports AID_REVIEW_DISPATCH_STUB=1; any exit 99 fails the suite.
# It proves no model was called, which is what the nightly run of this suite
# asserts. The paid runs are manual, with their ceiling written in
# docs/plans/P094-baseline.md and P094-acceptance-run.md before they start.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$PLUGIN_DIR/scripts/tests/fixtures/step-review"
SAMPLE="$FIX/sample.json"

die() { echo "test-step-review-acceptance: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not installed"; }
need jq; need git

# The verbatim prompt header of today's verifier card (agents/verifier.md,
# "Required Prompt Header"), extracted at run time so the baseline reviews with
# the text the card carries, not a copy that could drift.
verifier_header() {
  awk '/^### Required Prompt Header/{on=1; next} on && /^```$/{if(seen){exit} seen=1; next} on && seen{print}' \
    "$PLUGIN_DIR/agents/verifier.md"
}

# entries [<mode>] — the sample's entries; an entry may name the modes it belongs
# to (`modes`), e.g. a sabotaged diff written for the new flow has no baseline run.
entries() { jq -c --arg m "${1:-}" '.entries[] | select($m == "" or ((.modes // ["baseline", "new"]) | index($m)))' "$SAMPLE"; }

cmd_prepare() {
  local mode="$1" out="$2" only="${3:-}"
  mkdir -p "$out"
  entries "$mode" | while read -r e; do
    local id repo range head step dod files
    id="$(jq -r .id <<<"$e")"; [[ -z "$only" || "$only" == "$id" ]] || continue
    repo="$(jq -r .repo_path <<<"$e")"; range="$(jq -r .range <<<"$e")"; head="$(jq -r .head_sha <<<"$e")"
    step="$(jq -r .step <<<"$e")"
    git -C "$repo" cat-file -e "${head}^{commit}" 2>/dev/null || die "$id: head $head does not resolve in $repo"
    git -C "$repo" cat-file -e "${range%%..*}^{commit}" 2>/dev/null || die "$id: range base does not resolve in $repo"
    git -C "$repo" merge-base --is-ancestor "${range%%..*}" "$head" 2>/dev/null || die "$id: range base is not an ancestor of the reviewed head (the diff would show foreign changes)"
    local d="$out/$id"; mkdir -p "$d"
    git -C "$repo" diff "$range" > "$d/diff.patch"
    jq -r '.dod | "Objective: \(.objective)\n\nAcceptance criteria:\n" + (.acceptance_criteria | map("- " + .) | join("\n"))' <<<"$e" > "$d/dod.md"
    jq '.step_files' <<<"$e" > "$d/files.json"
    case "$mode" in
      baseline)
        {
          verifier_header | sed -e "s/{focus}/code-review/" -e "s#verifier-output-step-N.md#$d/verifier-output.md#" \
                                -e "s#evidence/<epic>/<run>/verifier-output-step-N.md#$d/verifier-output.md#"
          printf '\nThe repository to read is %s at commit %s (read-only). Write the output file to the ABSOLUTE path %s.\n' "$repo" "$head" "$d/verifier-output.md"
          printf '\n--- Definition of Done ---\n'; cat "$d/dod.md"
          printf '\n--- step_outputs (in scope) ---\n'; jq -r '.outputs[]?' "$d/files.json"
          printf '\n--- step_forbidden_paths ---\n'; jq -r '.forbidden_paths[]?' "$d/files.json"
          printf '\n--- diff (%s) ---\n' "$range"; cat "$d/diff.patch"
        } > "$d/prompt.md"
        ;;
      new)
        # The P094 engine: a detached worktree of the entry's repository at
        # the reviewed head, a run evidence dir with the step's plan.json and
        # base_commit = the range base, the step check, and — for a review
        # verdict — a prepared round whose prompts the controller dispatches.
        local wt="$d/wt" ev="$d/ev/$(jq -r .epic <<<"$e")/$(jq -r .run <<<"$e")" cp="$d/ev/$(jq -r .epic <<<"$e")/$(jq -r .run <<<"$e")/cp2/step-$step"
        if [[ ! -d "$wt" ]]; then git -C "$repo" worktree add -q --detach "$wt" "$head" 2>/dev/null || die "$id: cannot add a worktree at $head in $repo"; fi
        mkdir -p "$ev"; : > "$ev/timeline.jsonl"
        printf 'base_commit: %s\nstreamlined_mode: false\nepic_id: %s\nrun_id: %s\n' "${range%%..*}" "$(jq -r .epic <<<"$e")" "$(jq -r .run <<<"$e")" > "$ev/fsm-state.yaml"
        jq --argjson n "$step" '. as $e | {steps: ([range(0; $n) | {id: ("filler-" + tostring), role: "backend", objective: "earlier step"}]
                                          + [{id: "reviewed", role: "backend", objective: $e.dod.objective, acceptance_criteria: $e.dod.acceptance_criteria,
                                              outputs: $e.step_files.outputs, allowed_paths: $e.step_files.allowed_paths, forbidden_paths: $e.step_files.forbidden_paths}])}' <<<"$e" > "$ev/plan.json"
        if [[ -n "${MODEL:-}" ]]; then
          mkdir -p "$wt/.aid-o/config/policies"
          yq "(.review_checkpoints.step_review.reviewers[] | select(.provider == \"claude\") | .model) = \"$MODEL\"" \
             "$PLUGIN_DIR/defaults/policies/review-checkpoints.yaml" > "$wt/.aid-o/config/policies/review-checkpoints.yaml"
        fi
        rm -rf "$cp"
        local verdict; verdict="$( (cd "$wt" && bash "$PLUGIN_DIR/scripts/aid-step-check.sh" --checkpoint cp2 --step "$step" --evidence-dir "$ev" --project-root "$wt") 2>&1 | tail -1)"
        echo "$id: $verdict"
        if [[ "$verdict" == "verdict: review"* ]]; then
          bash "$PLUGIN_DIR/scripts/aid-review-round.sh" prepare --checkpoint cp2 --evidence-dir "$ev" --step "$step" --project-root "$wt" --round 1 ${STUB:+--stub} 2>&1 | grep -E 'prompt-|prepared' | sed "s/^/$id: /"
        fi
        continue
        ;;
      *) die "unknown mode $mode" ;;
    esac
    echo "$id: prompt at $d/prompt.md"
  done
}

# baseline answers: verifier-output.md with `verdict:` and a findings section;
# a finding is a level-2/3 heading or bullet carrying a severity word.
count_findings_md() {
  grep -cE '^(#{2,3} .*(F[0-9]|HIGH|CRITICAL|MEDIUM|LOW|BLOCK|MAJOR|MINOR)|- \*\*(severity|finding)|\s*- severity:)' "$1" 2>/dev/null || true
}

# new mode: `collect` and `close` every prepared round (tokens come as
# `<id>:<role>=<n|unknown>`), then one row per entry from rounds.json,
# merged.json and measurement.json: the verdict, the accepted findings, the
# tokens and USD summed over the roles.
collect_new_row() {
  local e="$1" out="$2"; shift 2
  local id step ev cp d
  id="$(jq -r .id <<<"$e")"; step="$(jq -r .step <<<"$e")"; d="$out/$id"
  ev="$d/ev/$(jq -r .epic <<<"$e")/$(jq -r .run <<<"$e")"; cp="$ev/cp2/step-$step"
  if [[ -d "$cp/round-1" && ! -f "$cp/round-1/measurement.json" ]]; then
    local roles=() r
    for r in $(jq -r '.reviewers_expected[]' "$cp/round-1/round.json"); do roles+=("$r=${TOK["$id:$r"]:-unknown}"); done
    bash "$PLUGIN_DIR/scripts/aid-review-round.sh" collect --checkpoint cp2 --evidence-dir "$ev" --step "$step" --project-root "$d/wt" --round 1 >/dev/null 2>&1 || true
    bash "$PLUGIN_DIR/scripts/aid-review-round.sh" close --checkpoint cp2 --evidence-dir "$ev" --step "$step" --project-root "$d/wt" --round 1 --tokens "${roles[@]}" >/dev/null 2>&1 \
      || echo "$id: close failed (round invalid or a role unanswered)" >&2
  fi
  local verdict reported=0 tok=0 unk=0 usd=0 usd_unk=0 answered=false
  verdict="$(jq -r '.verdict // "open"' "$cp/rounds.json" 2>/dev/null || echo no_check)"
  if [[ -f "$cp/round-1/measurement.json" ]]; then
    answered=true
    reported="$(jq '[.findings[] | select(.status == "open" or .status == "disputed")] | length' "$cp/round-1/merged.json" 2>/dev/null || echo 0)"
    read -r tok unk usd usd_unk <<< "$(jq -r '[.reviewers[]] as $r | "\([$r[] | .tokens | numbers] | add // 0) \([$r[] | select((.tokens|type) != "number")] | length) \([$r[] | .usd | numbers] | add // 0) \([$r[] | select((.usd|type) != "number")] | length)"' "$cp/round-1/measurement.json")"
  elif [[ "$verdict" == skip || "$verdict" == no_change ]]; then answered=true; fi
  jq -nc --arg id "$id" --arg v "$verdict" --argjson r "$reported" --argjson t "$tok" --argjson unk "$unk" --argjson usd "$usd" --argjson uu "$usd_unk" \
     --argjson a "$answered" --arg orig "$(jq -r .original_verdict <<<"$e")" \
     '{id:$id, original_verdict:$orig, verdict:$v, findings_reported:$r, findings_confirmed:null, answered:$a,
       tokens_total:(if $unk > 0 then "unknown" else $t end), usd:(if $uu > 0 then "unknown" else $usd end), seconds:null}'
}

cmd_collect() {
  local mode="$1" out="$2" model="$3"; shift 3
  declare -A TOK
  for kv in "$@"; do TOK["${kv%%=*}"]="${kv#*=}"; done
  local results="$out/results-$mode-$model.json" rows="[]"
  if [[ "$mode" == new ]]; then
    entries "$mode" | while read -r e; do collect_new_row "$e" "$out"; done | jq -s --arg mode "$mode" --arg model "$model" \
      '{mode:$mode, model:$model, entries:., totals:{answered:([.[]|select(.answered)]|length), rounds:([.[]|select(.verdict=="pass" or .verdict=="fail")]|length),
        skipped:([.[]|select(.verdict=="skip" or .verdict=="no_change")]|length), reported:([.[].findings_reported|numbers]|add // 0),
        tokens_total:([.[].tokens_total|numbers]|add // 0), unknown:([.[]|select(.tokens_total=="unknown")]|length),
        usd:([.[].usd|numbers]|add // 0), usd_unknown:([.[]|select(.usd=="unknown")]|length)}}' > "$results"
    echo "results: $results"; jq -c .totals "$results"; return 0
  fi
  entries | while read -r e; do
    local id d verdict reported="null" tok
    id="$(jq -r .id <<<"$e")"; d="$out/$id"
    tok="${TOK[$id]:-unknown}"
    if [[ -f "$d/verifier-output.md" ]]; then
      verdict="$(grep -oiE '^verdict: *[a-z_]+' "$d/verifier-output.md" | head -1 | awk '{print tolower($2)}')"
      reported="$(count_findings_md "$d/verifier-output.md")"
    else
      verdict="no_answer"
    fi
    jq -nc --arg id "$id" --arg v "${verdict:-unparsed}" --argjson r "${reported:-null}" \
       --arg tok "$tok" --arg orig "$(jq -r .original_verdict <<<"$e")" \
       '{id:$id, original_verdict:$orig, verdict:$v, findings_reported:$r, findings_confirmed:null,
         tokens_total:($tok|tonumber? // $tok), usd:null, seconds:null}'
  done | jq -s --arg mode "$mode" --arg model "$model" \
      '{mode:$mode, model:$model, entries:., totals:{answered:([.[]|select(.verdict!="no_answer")]|length),
        reported:([.[].findings_reported|numbers]|add // 0),
        tokens_total:([.[].tokens_total|numbers]|add // 0),
        unknown:([.[]|select(.tokens_total=="unknown")]|length)}}' > "$results"
  echo "results: $results"; jq -c .totals "$results"
}

# cleanup --out DIR — remove the worktrees `prepare --mode new` added.
cmd_cleanup() {
  local out="$1"
  entries | while read -r e; do
    local id repo; id="$(jq -r .id <<<"$e")"; repo="$(jq -r .repo_path <<<"$e")"
    [[ -d "$out/$id/wt" ]] && git -C "$repo" worktree remove --force "$out/$id/wt" >/dev/null 2>&1
    git -C "$repo" worktree prune >/dev/null 2>&1
  done
  return 0
}

# replay-do --evidence DIR --project-root DIR — what the recorded answers yield
# through this tree's adjudicator. No model is called and no recorded file is
# written: each round is copied to a temporary directory first.
cmd_replay_do() {
  local ev="$1" root="$2" tmp d id sc
  [[ -d "$ev" ]] || die "replay-do: no evidence directory $ev"
  tmp="$(mktemp -d)"
  for d in "$ev"/do/*/cp6; do
    [[ -d "$d/round-1" ]] || continue
    id="$(basename "$(dirname "$d")")"
    cp -r "$d/round-1" "$tmp/$id"
    rm -f "$tmp/$id"/merged.json "$tmp/$id"/rejected.json "$tmp/$id"/yield.json
    sc=(); [[ -f "$d/step-check.json" ]] && sc=(--step-check "$d/step-check.json")
    "$PLUGIN_DIR/scripts/aid-review-adjudicate.sh" "$tmp/$id" --project-root "$root" \
      --namespace do_review "${sc[@]}" >/dev/null 2>&1 || true
    printf '%s\t%s\t%s\t%s\n' "$id" \
      "$([[ "$(jq '.blockers_open // 0' "$tmp/$id/merged.json" 2>/dev/null || echo 0)" -gt 0 ]] && echo fail || echo pass)" \
      "$(jq '.findings | length' "$tmp/$id/merged.json" 2>/dev/null || echo 0)" \
      "$(jq -c '[.[] | .reason]' "$tmp/$id/rejected.json" 2>/dev/null || echo '[]')"
  done
  rm -rf "$tmp"
}

cmd_stub() {
  local mode="$1" model="$2" only="${3:-}"
  local guard; guard="$(mktemp -d)"
  [[ "$mode" == new ]] && export STUB=1
  for b in claude codex; do printf '#!/usr/bin/env bash\necho "guard: %s must not be called in stub mode" >&2\nexit 99\n' "$b" > "$guard/$b"; chmod +x "$guard/$b"; done
  export PATH="$guard:$PATH" AID_REVIEW_DISPATCH_STUB=1
  local out; out="$(mktemp -d)"
  cmd_prepare "$mode" "$out" "$only" >/dev/null
  local missing=0
  entries "$mode" | while read -r e; do
    local id; id="$(jq -r .id <<<"$e")"; [[ -z "$only" || "$only" == "$id" ]] || continue
    if [[ "$mode" == new ]]; then
      local step cp r; step="$(jq -r .step <<<"$e")"; cp="$out/$id/ev/$(jq -r .epic <<<"$e")/$(jq -r .run <<<"$e")/cp2/step-$step"
      [[ -d "$cp/round-1" ]] || continue
      for r in $(jq -r '.reviewers_expected[]' "$cp/round-1/round.json"); do
        local a="$FIX/answers/$id-$r.json"
        if [[ -f "$a" ]]; then cp "$a" "$cp/round-1/reviewer-$r.json"; else echo "no recorded answer for $id ($r)" >&2; fi
      done
      continue
    fi
    local a="$FIX/answers/$id-baseline.md"
    if [[ -f "$a" ]]; then cp "$a" "$out/$id/verifier-output.md"; else echo "no recorded answer for $id" >&2; fi
  done
  cmd_collect "$mode" "$out" "$model" >/dev/null
  local results="$out/results-$mode-$model.json"
  local answered; answered="$(jq -r '.totals.answered' "$results")"
  local expected=1; [[ -n "$only" ]] || expected="$(entries "$mode" | wc -l)"
  [[ "$answered" -eq "$expected" ]] || die "stub: expected $expected answer(s)${only:+ for $only}, got $answered"
  # An entry with a planted defect proves something only when the defect comes out as an accepted finding.
  local unfound
  unfound="$(jq -r --slurpfile s "$SAMPLE" '[$s[0].entries[] | select(.planted) | .id] as $p
    | [.entries[] | select((.id | IN($p[])) and ((.findings_reported // 0) == 0)) | .id] | join(", ")' "$results")"
  [[ -z "$unfound" ]] || die "stub: the planted defect was not reported for: $unfound"
  # the guard is the proof: had anything called claude/codex, exit 99 would have failed above
  [[ "$mode" == new ]] && cmd_cleanup "$out"
  rm -rf "$guard" "$out"
  echo "Results: 1/1 passed, 0 failed"
}

# ── final: the auditor's recorded findings replayed through the whole-plan round ──
# fixtures/plan-final/sample.json holds real high findings of the retired plan-final
# auditor with the commits they were made at. `final prepare` materialises each
# reviewed candidate in a --shared clone (the source repository is never written
# to), builds the cp7 packet over base..candidate and prints the prompts; the
# controller dispatches them; `final collect` closes the rounds and reports, per
# entry, whether the finding recorded as its match (acceptance.json `matched_by`)
# is among the ACCEPTED findings. `final stub` does the same from the recorded
# answers, with the no-model guard, which is what the nightly run asserts.
FINAL_SAMPLE="$PLUGIN_DIR/scripts/tests/fixtures/plan-final/sample.json"
FINAL_FIX="$PLUGIN_DIR/scripts/tests/fixtures/plan-final"

# final_rounds — one line per distinct reviewed candidate: <key>\t<project>\t<plan>\t<run>\t<base>\t<candidate>
final_rounds() {
  jq -r '.entries | group_by(.project + .plan + .candidate_sha)[] | .[0]
         | ["\(.project)-\(.plan)-\(.candidate_sha[0:8])", .project, .plan, .run, .base_sha, .candidate_sha] | @tsv' "$FINAL_SAMPLE"
}

# cmd_final_prepare <out> [<only key>] [<key>=<role>[,<role>…] …] — a round may be
# limited to the roles its findings belong to (a paid run need not ask all three).
cmd_final_prepare() {
  local out="$1" only="${2:-}"; shift 2 || shift $#
  declare -A ROLES; local kv; for kv in "$@"; do ROLES["${kv%%=*}"]="${kv#*=}"; done
  local key project plan run base cand
  mkdir -p "$out"
  while IFS=$'\t' read -r key project plan run base cand; do
    [[ -z "$only" || "$only" == "$key" ]] || continue
    local src="/opt/eco/projects/${project}" clone="$out/$key/repo"
    git -C "$src" cat-file -e "${cand}^{commit}" 2>/dev/null || die "$key: candidate $cand does not resolve in $src"
    [[ -d "$clone" ]] || { git clone -q --shared --no-checkout "$src" "$clone" && git -C "$clone" checkout -q --detach "$cand"; } || die "$key: cannot materialise $cand"
    local ev="$clone/.aid-o/work/evidence/${plan}/R-${plan}-final-replay" rec="$src/.aid-o/work/evidence/${plan}/${run}" planfile
    mkdir -p "$ev" "$clone/.aid-o/config/policies"
    cp "$rec/gates_report.json" "$rec/plan-diff.json" "$ev/" || die "$key: the recorded run has no gates_report.json or plan-diff.json"
    : > "$ev/timeline.jsonl"
    planfile="$({ ls "$src/.aid-o/plans/${plan}"-*.md "$src/.aid-o/plans/archive/${plan}"-*.md 2>/dev/null || true; } | head -n1)"
    [[ -n "$planfile" ]] || die "$key: no plan file for ${plan} in $src"
    # every role on claude at the configured model: the stand-in rule, applied up front
    ROLES_CSV="${ROLES[$key]:-}" yq '.review_checkpoints.final_review.reviewers |= map(.model = (select(.provider == "codex") | "sonnet") // .model | .provider = "claude")
        | .review_checkpoints.final_review.reviewers |= map(select(strenv(ROLES_CSV) == "" or (.role as $r | strenv(ROLES_CSV) | split(",") | contains([$r]))))' \
      "$PLUGIN_DIR/defaults/policies/review-checkpoints.yaml" > "$clone/.aid-o/config/policies/review-checkpoints.yaml"
    ( source "$PLUGIN_DIR/scripts/lib/aid-step-review-packet.sh" && aid_final_review_inputs_build "$src" "$ev" "$planfile" "$plan" ) || die "$key: inputs"
    bash "$PLUGIN_DIR/scripts/aid-step-check.sh" --checkpoint cp7 --base "$base" --evidence-dir "$ev" --project-root "$clone" >/dev/null || die "$key: step check"
    bash "$PLUGIN_DIR/scripts/aid-review-round.sh" prepare --checkpoint cp7 --evidence-dir "$ev" --project-root "$clone" --round 1 \
      $([[ "${STUB:-0}" == 1 ]] && echo --stub) | sed "s|^|$key: |"
  done < <(final_rounds)
}

# cmd_final_collect <out> [<key>:<role>=<tokens> …] — close every prepared round, then one row per sample entry
cmd_final_collect() {
  local out="$1"; shift
  declare -A TOK; local kv; for kv in "$@"; do TOK["${kv%%=*}"]="${kv#*=}"; done
  local key project plan run base cand
  while IFS=$'\t' read -r key project plan run base cand; do
    local clone="$out/$key/repo" ev r; ev="$clone/.aid-o/work/evidence/${plan}/R-${plan}-final-replay"
    [[ -d "$ev/cp7/round-1" && ! -f "$ev/cp7/round-1/measurement.json" ]] || continue
    local roles=(); for r in $(jq -r '.reviewers_expected[]' "$ev/cp7/round-1/round.json"); do roles+=("$r=${TOK["$key:$r"]:-unknown}"); done
    bash "$PLUGIN_DIR/scripts/aid-review-round.sh" collect --checkpoint cp7 --evidence-dir "$ev" --project-root "$clone" --round 1 >/dev/null 2>&1 || true
    bash "$PLUGIN_DIR/scripts/aid-review-round.sh" close --checkpoint cp7 --evidence-dir "$ev" --project-root "$clone" --round 1 --tokens "${roles[@]}" >/dev/null 2>&1 \
      || echo "$key: close failed (round invalid or a role unanswered)" >&2
  done < <(final_rounds)
  jq -c '.entries[]' "$FINAL_SAMPLE" | while read -r e; do
    local id key merged; id="$(jq -r .id <<<"$e")"
    key="$(jq -r '"\(.project)-\(.plan)-\(.candidate_sha[0:8])"' <<<"$e")"
    merged="$out/$key/repo/.aid-o/work/evidence/$(jq -r .plan <<<"$e")/R-$(jq -r .plan <<<"$e")-final-replay/cp7/round-1"
    jq -n --arg id "$id" --arg key "$key" --slurpfile acc "$FINAL_FIX/acceptance.json" \
       --slurpfile m <(cat "$merged/merged.json" 2>/dev/null || echo '{"findings": []}') \
       --slurpfile rej <(cat "$merged/rejected.json" 2>/dev/null || echo '[]') \
       --slurpfile meas <(cat "$merged/measurement.json" 2>/dev/null || echo '{}') '
      ($acc[0].entries[] | select(.id == $id)) as $a
      | {id: $id, round: $key, matched_by: $a.matched_by, mechanism: $a.mechanism,
         matched: ($a.mechanism != null or ($a.matched_by != null and any($m[0].findings[]; .id == $a.matched_by or .fingerprint == $a.matched_by))),
         accepted: ($m[0].findings | length), rejected: ($rej[0] | length),
         usd: ([$meas[0].reviewers[]?.usd | numbers] | add // 0)}'
  done | jq -s '{entries: ., matched: ([.[] | select(.matched)] | length), of: length}'
}

cmd_final_stub() {
  local guard out b; guard="$(mktemp -d)"; out="$(mktemp -d)"
  for b in claude codex; do printf '#!/usr/bin/env bash\necho "guard: %s must not be called in stub mode" >&2\nexit 99\n' "$b" > "$guard/$b"; chmod +x "$guard/$b"; done
  export PATH="$guard:$PATH" AID_REVIEW_DISPATCH_STUB=1 STUB=1
  # a round asks exactly the roles whose answers were recorded for it
  local key project plan run base cand a asked=()
  while IFS=$'\t' read -r key _; do
    asked+=("$key=$({ ls "$FINAL_FIX/answers/$key"-*.json 2>/dev/null || true; } | sed "s|.*/$key-||; s|\.json$||" | paste -sd,)")
  done < <(final_rounds)
  cmd_final_prepare "$out" "" "${asked[@]}" >/dev/null
  while IFS=$'\t' read -r key project plan run base cand; do
    for a in "$FINAL_FIX/answers/$key"-*.json; do
      [[ -f "$a" ]] || continue
      cp "$a" "$out/$key/repo/.aid-o/work/evidence/${plan}/R-${plan}-final-replay/cp7/round-1/reviewer-$(basename "$a" .json | sed "s/^$key-//").json"
    done
  done < <(final_rounds)
  local results want; results="$(cmd_final_collect "$out")"
  want="$(jq -c '[.entries[] | {id, matched}] | sort_by(.id)' "$FINAL_FIX/acceptance.json")"
  rm -rf "$guard" "$out"
  [[ "$(jq -c '[.entries[] | {id, matched}] | sort_by(.id)' <<<"$results")" == "$want" ]] \
    || die "final stub: the replay does not reproduce acceptance.json's matched column: $(jq -c '[.entries[] | {id, matched}]' <<<"$results")"
  echo "Results: 1/1 passed, 0 failed"
}

main() {
  local sub="${1:-}"; shift || true
  if [[ "$sub" == final ]]; then
    local fsub="${1:-}" fout="" fonly=""; shift || true; local -a ftok=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --out) fout="$2"; shift 2 ;; --only) fonly="$2"; shift 2 ;;
        --tokens|--roles) shift; while [[ $# -gt 0 && "$1" != --* ]]; do ftok+=("$1"); shift; done ;;
        *) die "final: unknown option $1" ;;
      esac
    done
    case "$fsub" in
      prepare) [[ -n "$fout" ]] || die "final prepare needs --out"; cmd_final_prepare "$fout" "$fonly" "${ftok[@]}" ;;
      collect) [[ -n "$fout" ]] || die "final collect needs --out"; cmd_final_collect "$fout" "${ftok[@]}" ;;
      stub)    cmd_final_stub ;;
      *) die "usage: $0 final prepare|collect|stub [--out DIR] [--only KEY] [--roles KEY=role,… …] [--tokens KEY:ROLE=n …]" ;;
    esac
    return
  fi
  local mode="" out="" model="" only="" evidence="" root=""; local -a tokens=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence) evidence="$2"; shift 2 ;; --project-root) root="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; --model) model="$2"; MODEL="$2"; shift 2 ;;
      --only) only="$2"; shift 2 ;; --tokens) shift; while [[ $# -gt 0 && "$1" != --* ]]; do tokens+=("$1"); shift; done ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -f "$SAMPLE" ]] || die "sample fixture missing: $SAMPLE"
  case "$sub" in
    prepare) [[ -n "$mode" && -n "$out" ]] || die "prepare needs --mode and --out"; cmd_prepare "$mode" "$out" "$only" ;;
    collect) [[ -n "$mode" && -n "$out" && -n "$model" ]] || die "collect needs --mode, --out, --model"; cmd_collect "$mode" "$out" "$model" "${tokens[@]}" ;;
    stub)    [[ -n "$mode" && -n "$model" ]] || die "stub needs --mode and --model"; cmd_stub "$mode" "$model" "$only" ;;
    cleanup) [[ -n "$out" ]] || die "cleanup needs --out"; cmd_cleanup "$out" ;;
    replay-do) [[ -n "$evidence" && -n "$root" ]] || die "replay-do needs --evidence and --project-root"; cmd_replay_do "$evidence" "$root" ;;
    *) die "usage: $0 prepare|collect|stub|replay-do ..." ;;
  esac
}
main "$@"
