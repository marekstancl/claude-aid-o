#!/usr/bin/env bash
# =============================================================================
# stop-hook-bench.sh — how long AID's Stop rules take on a long session, and whether a faster version
# still gives the same verdicts (AID 3.11.0, Z3 of docs/plans/2026-10-25-prevzeti-kroku-na-pozadi.md).
#
#   stop-hook-bench.sh [--base <git-ref>] [--lines <n>] [--runs <n>] [--limit <s>]
#
# Builds a synthetic transcript in the shape Claude Code writes (about <lines> lines of ~7 KB, default 25 000 plus the notifications, no real
# session data), a throwaway AID workspace with an autonomous plan bound to the session, and runs the two
# Stop rules that read the transcript (queue_continuation_notice, turn_step_open) from the working tree
# and from <base> (default main, unpacked with git archive). One warm-up, then <runs> timed runs per
# version (default 5), each under a <limit>-second timeout (default 30); a run that times out or fails
# stops the bench (exit 2). Prints the medians and holds them to the brief's target: the working tree at
# most 2 s and at least 4x faster than <base> (exit 1 otherwise).
# Then the verdict set — the same events against both versions, exit code and the reason line compared:
# a plain end, AID-WAIT with a live and with an answered background job, a card, a corrupt line at the
# end, an empty transcript. Each run must print exactly two well-formed verdict lines. Exit 0 when the target
# holds and every verdict matches, 1 otherwise.
# Not a test of the suite: timings depend on the machine. Run it by hand and keep the output as evidence.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
REPO="$(git -C "$PLUGIN" rev-parse --show-toplevel)"
BASE=main LINES_N=25000 RUNS=5 LIMIT=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)  [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; exit 2; }; BASE="$2"; shift 2 ;;
    --lines) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; exit 2; }; LINES_N="$2"; shift 2 ;;
    --runs)  [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; exit 2; }; RUNS="$2"; shift 2 ;;
    --limit) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; exit 2; }; LIMIT="$2"; shift 2 ;;
    *) echo "usage: ${0##*/} [--base <ref>] [--lines <n>] [--runs <n>] [--limit <s>]" >&2; exit 2 ;;
  esac
done

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/base"
git -C "$REPO" archive "$BASE" plugins/aid-orchestrator/scripts plugins/aid-orchestrator/defaults | tar -x -C "$W/base" \
  || { echo "cannot unpack ${BASE}" >&2; exit 2; }
NEW="$PLUGIN/scripts"; OLD="$W/base/plugins/aid-orchestrator/scripts"

# --- a workspace with plan P090 running autonomously for session S1 ---------------------------------------
source "$PLUGIN/scripts/tests/bats/test-helpers.bash"
ROOT="$W/repo"; aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work/plan-state/P090" >/dev/null
printf 'plan_id: P090\nplan_state: EPIC_INTEGRATION\nmode: plan_branch\nplan_branch: plan/P090\ntarget_branch: main\nautonomy: auto\nauto_session: S1\n' \
  > "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
printf 'send_alert() { :; }\n' > "$W/tg.sh"
export AID_TELEGRAM_LIB="$W/tg.sh" AID_QUIET=1 AID_TEST_MODE=1
# a run in EXECUTE whose step 0 was dispatched under a contract, so turn_step_open reads the transcript too
EV="$ROOT/.aid-o/work/evidence/E-090-1_1/R-E090-1"; mkdir -p "$EV/steps/step_1"
printf 'state: EXECUTE\ncurrent_step: 0\nepic_id: E-090-1_1\nrun_id: R-E090-1\n' > "$EV/fsm-state.yaml"
printf '{"steps":[{"id":"step_1"}]}\n' > "$EV/plan.json"
printf '{"version":"v-bench-1","step_id":"step_1"}\n' > "$EV/steps/step_1/contract.json"

# --- the synthetic transcript ---------------------------------------------------------------------------
pad="$(head -c 7000 /dev/zero | tr '\0' 'x')"
python3 - "$W/long.jsonl" "$LINES_N" "$pad" <<'PY'
import json, sys
out, n, pad = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with open(out, "w") as f:
    for i in range(n // 2):
        tid = f"toolu_{i:08d}"
        if i % 50 == 7:
            use = {"type": "tool_use", "id": tid, "name": "Agent", "input": {"prompt": "Dispatch Contract (version v-bench-1) step", "description": "d"}}
            res = "Async agent launched successfully."
        else:
            use = {"type": "tool_use", "id": tid, "name": "Bash",
                   "input": {"command": "true", "run_in_background": i % 40 == 3}}
            res = pad
        f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": f"turn {i}"}, use]}},
                           separators=(",", ":")) + "\n")
        f.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": res}]}},
                           separators=(",", ":")) + "\n")
        if i % 50 == 7 or i % 40 == 3:   # every background call of the past is answered
            f.write(json.dumps({"type": "user", "message": {"content": f"<task-notification><tool-use-id>{tid}</tool-use-id></task-notification>"}},
                               separators=(",", ":")) + "\n")
PY
_last() {  # <file> <text> — append the turn's last assistant message
  jq -nc --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$1"
}
_live() {  # <file> — a background call nobody answered yet
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_live",name:"Bash",input:{command:"sleep 1",run_in_background:true}}]}}' >> "$1"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_live",content:"Command running in background with ID: b1."}]}}' >> "$1"
}

# _run <scripts-dir> <transcript> — both rules on one Stop event; prints "<rc>|<reason line>" per rule
_run() {
  local s="$1" t="$2" ev store
  store="$(mktemp -d -p "$W")"
  ev="$(jq -nc --arg c "$ROOT" --arg t "$t" '{session_id:"S1",cwd:$c,transcript_path:$t,stop_hook_active:false}')"
  AID_SESSION_STORE="$store" AID_HOOK_AUDIT="$W/audit.jsonl" timeout "$LIMIT" bash -c '
    source "$1/lib/aid-auto-continuation.sh"; source "$1/lib/aid-hook-rules-turn.sh"
    out="$(aid_hook_rule_auto_continuation_stop <<< "$2" 2>&1)"; echo "$?|$(printf "%s" "$out" | head -1)"
    out="$(aid_hook_rule_turn_step_open <<< "$2" 2>&1)"; echo "$?|$(printf "%s" "$out" | head -1)"
  ' _ "$s" "$ev"
}
# _check <output> — exactly two "<rc>|<reason>" lines, neither from a timeout (124) or a crash (>3)
_check() { [[ "$(grep -cE '^[0-3]\|' <<< "$1")" == 2 && "$(wc -l <<< "$1")" == 2 ]]; }

# --- timing ---------------------------------------------------------------------------------------------
cp "$W/long.jsonl" "$W/t-time.jsonl"; _live "$W/t-time.jsonl"; _last "$W/t-time.jsonl" "AID-WAIT: brána běží"
_median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
_time() {  # <scripts-dir>
  local i t0
  local out
  out="$(_run "$1" "$W/t-time.jsonl")"; _check "$out" || { echo "warm-up of $1 failed or timed out: $out" >&2; exit 2; }
  for (( i=0; i<RUNS; i++ )); do
    t0=$(date +%s.%N); out="$(_run "$1" "$W/t-time.jsonl")"
    _check "$out" || { echo "a timed run of $1 failed or timed out: $out" >&2; exit 2; }
    awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN {printf "%.3f\n", a - b}'
  done | _median
}
size="$(du -h "$W/t-time.jsonl" | cut -f1)"
m_old="$(_time "$OLD")" || exit 2; m_new="$(_time "$NEW")" || exit 2
printf 'transcript: %s lines, %s\nmedian of %s runs: %s %.2f s · working tree %.2f s · %.1fx faster\n' \
  "$(wc -l < "$W/t-time.jsonl")" "$size" "$RUNS" "$BASE" "$m_old" "$m_new" "$(awk -v a="$m_old" -v b="$m_new" 'BEGIN {print (b > 0 ? a / b : 0)}')"

fail=0
awk -v a="$m_old" -v b="$m_new" 'BEGIN {exit !(b <= 2 && b > 0 && a / b >= 4)}' \
  || { echo "TARGET MISSED: the working tree must take at most 2 s and be at least 4x faster than ${BASE}"; fail=1; }

# --- verdicts -------------------------------------------------------------------------------------------
_case() {  # <name> <transcript>
  local a b; a="$(_run "$OLD" "$2")"; b="$(_run "$NEW" "$2")"
  _check "$a" && _check "$b" || { echo "BROKEN $1 (a run failed, timed out or printed no verdict)"; echo "  ${BASE}: $a"; echo "  new : $b"; fail=1; return; }
  if [[ "$a" == "$b" ]]; then echo "same   $1"; else echo "DIFFER $1"; echo "  ${BASE}: ${a//$'\n'/ ; }"; echo "  new : ${b//$'\n'/ ; }"; fail=1; fi
}
cp "$W/long.jsonl" "$W/c1.jsonl"; _last "$W/c1.jsonl" "Krok 2 hotový, pokračuji."
_case "plain end with work left" "$W/c1.jsonl"
cp "$W/long.jsonl" "$W/c2.jsonl"; _live "$W/c2.jsonl"; _last "$W/c2.jsonl" "AID-WAIT: brána běží"
_case "AID-WAIT with a live background job" "$W/c2.jsonl"
cp "$W/long.jsonl" "$W/c3.jsonl"; _last "$W/c3.jsonl" "AID-WAIT: nic neběží"
_case "AID-WAIT with every job answered" "$W/c3.jsonl"
cp "$W/long.jsonl" "$W/c4.jsonl"; _last "$W/c4.jsonl" $'Zastaveno: brána padá\nDůvod: x'
_case "a Blocked card" "$W/c4.jsonl"
cp "$W/long.jsonl" "$W/c5.jsonl"; _last "$W/c5.jsonl" "Pokračuji."; printf '{"type":"assistant","message":{"content":[{"ty\n' >> "$W/c5.jsonl"
_case "a corrupt line at the end" "$W/c5.jsonl"
: > "$W/c6.jsonl"
_case "an empty transcript" "$W/c6.jsonl"
exit "$fail"
