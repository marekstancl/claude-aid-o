#!/usr/bin/env bash
# aid-tier: t2
# test-step-review-acceptance.sh — replay 20 recorded step diffs through a review
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

entries() { jq -c '.entries[]' "$SAMPLE"; }

cmd_prepare() {
  local mode="$1" out="$2" only="${3:-}"
  mkdir -p "$out"
  entries | while read -r e; do
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
    entries | while read -r e; do collect_new_row "$e" "$out"; done | jq -s --arg mode "$mode" --arg model "$model" \
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

cmd_stub() {
  local mode="$1" model="$2" only="${3:-}"
  local guard; guard="$(mktemp -d)"
  [[ "$mode" == new ]] && export STUB=1
  for b in claude codex; do printf '#!/usr/bin/env bash\necho "guard: %s must not be called in stub mode" >&2\nexit 99\n' "$b" > "$guard/$b"; chmod +x "$guard/$b"; done
  export PATH="$guard:$PATH" AID_REVIEW_DISPATCH_STUB=1
  local out; out="$(mktemp -d)"
  cmd_prepare "$mode" "$out" "$only" >/dev/null
  local missing=0
  entries | while read -r e; do
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
  if [[ -n "$only" ]]; then [[ "$answered" -eq 1 ]] || die "stub: expected 1 answer for $only, got $answered"; else [[ "$answered" -eq 20 ]] || die "stub: expected 20 answers, got $answered"; fi
  # the guard is the proof: had anything called claude/codex, exit 99 would have failed above
  [[ "$mode" == new ]] && cmd_cleanup "$out"
  rm -rf "$guard" "$out"
  echo "Results: 1/1 passed, 0 failed"
}

main() {
  local sub="${1:-}"; shift || true
  local mode="" out="" model="" only=""; local -a tokens=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
    *) die "usage: $0 prepare|collect|stub ..." ;;
  esac
}
main "$@"
