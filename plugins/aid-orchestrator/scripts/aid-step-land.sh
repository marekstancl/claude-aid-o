#!/usr/bin/env bash
# =============================================================================
# aid-step-land.sh — take over a returned step in the background (AID 3.11.0)
#
#   aid-step-land.sh <state_file> <step_index> [--check "<AC#>:<command>"]… [--env NAME=value]…
#                    [--tree <plan tree>] [--timeout <s>] [--lock-wait <s>] [--recheck]
#
# The MECHANICAL half of taking over a step, which the controller ran in the foreground until 3.10.0 and which
# kept it from accepting other returns and dispatching other steps meanwhile (WAN P115, 25. 10. 2026: 53 of 180
# minutes). The controller starts this with Bash run_in_background, ends its turn `AID-WAIT: převzetí kroku N`,
# and on the notification reads the record. Judgement stays with the controller: which checks belong to an
# acceptance criterion, what to do about a failure, the verify file, the step review, increment-step.
#
# What it does, and NOTHING else (it never fixes, amends a contract or the scope, renames, retries):
#   wave   (the step ran in its own tree on step/<id>):
#            validate the return · commit it there · build the merge of step/<id> onto the plan's HEAD in that tree
#            (detached; first parent = the plan, as aid_parallel_merge) · run the checks there · fast-forward the
#            plan's branch to it only when every check passed and its HEAD has not moved · remove the clean tree
#   serial (the step ran in the plan's tree): validate · commit on the run's branch · run the checks
#   --recheck (after a step-review fixer committed, or after the role fixed a serial step whose checks failed — its
#             commit stays on the branch): the same checks on the plan's HEAD, nothing else
# then the plan's own measurer (aid-plan-diff.sh --step N) on the landed HEAD, which increment-step reuses.
#
# Every command criterion (lib/aid-ac-command.sh: its text begins with a backticked command — a space, a slash or
# NAME=value; one bare word is a name, not a command) must come with exactly that command (`--check "<n>:<command>"`,
# n = its 1-based place in plan.json), or with another one and its reason (`--reason "<n>:<why>"`, 3.13.0: the
# plan's command measures another environment); environment the project's tests need goes in `--env`, never into
# the command. Anything else is refused before a thing changes.
#
# Record: <step dir>/land.json (schema version 1), written `running` at the start and replaced atomically with the
# result: landed | return_rejected | merge_conflict | check_failed | base_moved | precondition_failed | interrupted. The full
# output of every check goes, redacted, to <step dir>/land-logs/ (evidence, never git). increment-step refuses a
# step whose record is missing a command criterion, failed, is still running or does not match HEAD.
# Exit: 0 landed · 1 any other result (the record says which) · 2 usage.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-roots.sh"
source "${SCRIPT_DIR}/lib/aid-lock.sh"
source "${SCRIPT_DIR}/lib/aid-dispatch-contract.sh"
source "${SCRIPT_DIR}/lib/aid-parallel-dispatch.sh"
source "${SCRIPT_DIR}/lib/aid-gate-outcome-summary.sh"
source "${SCRIPT_DIR}/lib/aid-ac-command.sh"            # ac_command: which criteria are commands (3.13.0)

_usage() { sed -n '4,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -ge 2 ]] || _usage
SF="$1" N="$2"; shift 2
CHECKS=() ENVS=() WHY=() TREE="" TMO=1800 LOCK_WAIT=5 RECHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)     [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; CHECKS+=("$2"); shift 2 ;;
    --reason)    [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; WHY+=("$2"); shift 2 ;;   # <AC#>:<why the command differs from the plan's>
    --env)       [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; ENVS+=("$2"); shift 2 ;;
    --tree)      [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; TREE="$2"; shift 2 ;;
    --timeout)   [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; TMO="$2"; shift 2 ;;
    --lock-wait) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; LOCK_WAIT="$2"; shift 2 ;;
    --recheck)   RECHECK=1; shift ;;
    *) echo "${0##*/}: unknown argument: $1" >&2; _usage ;;
  esac
done
[[ -f "$SF" && "$N" =~ ^[0-9]+$ && "$TMO" =~ ^[0-9]+$ && "$LOCK_WAIT" =~ ^[0-9]+$ ]] || _usage
SF="$(realpath "$SF")"; EV="$(dirname "$SF")"; PJ="${EV}/plan.json"
[[ -f "$PJ" ]] || { echo "${0##*/}: no ${PJ}" >&2; exit 2; }
SID="$(jq -r --argjson i "$N" '.steps[$i].id // ""' "$PJ")"
[[ -n "$SID" ]] || { echo "${0##*/}: plan.json has no step ${N}" >&2; exit 2; }
SD="${EV}/steps/${SID}"; mkdir -p "$SD/land-logs"
REC="${SD}/land.json"
EPIC="$(yq -r '.epic_id // ""' "$SF")"; RUN="$(yq -r '.run_id // ""' "$SF")"
[[ -n "$TREE" ]] || TREE="$(git rev-parse --show-toplevel 2>/dev/null)"
TREE="$(realpath "$TREE")"
STATE_ROOT="$(cd "$TREE" && aid_state_root 2>/dev/null || printf '%s' "$TREE")"

# --- the record ---------------------------------------------------------------------------------------------
STATUS=running REASON="" PATHKIND="" STEP_SHA="" BASE_SHA="" LANDED_SHA="" CSHA="" RSHA="" MEASURE=""
CHECKS_JSON="[]"
_sha() { [[ -f "$1" ]] && sha256sum "$1" | cut -d' ' -f1 || printf ''; }
_write() {
  local tmp="${REC}.tmp.$$"
  jq -n --arg plan "$EPIC" --arg run "$RUN" --argjson i "$N" --arg sid "$SID" --arg st "$STATUS" --arg why "$REASON" \
        --arg path "$PATHKIND" --arg ssha "$STEP_SHA" --arg bsha "$BASE_SHA" --arg lsha "$LANDED_SHA" \
        --arg c "$CSHA" --arg r "$RSHA" --argjson checks "$CHECKS_JSON" --arg m "$MEASURE" \
        --argjson pid "$$" --arg ctok "$CHECK_TOKEN" --arg sess "${CLAUDE_CODE_SESSION_ID:-}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson env "$(printf '%s\n' "${ENVS[@]+"${ENVS[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')" \
    '{version: 1, epic_id: $plan, run_id: $run, step_index: $i, step_id: $sid, status: $st, reason: $why,
      path: $path, contract_sha256: $c, return_sha256: $r, step_sha: $ssha, base_sha: $bsha, landed_sha: $lsha,
      env: $env, checks: $checks, measure: $m, pid: $pid, session_id: $sess, check_token: $ctok, at: $at}' > "$tmp" && mv -f "$tmp" "$REC"
}
HAVE_LOCK=0 OWNED=0 BACK_NOTE="" CHECK_PID="" CHECK_TOKEN=""
# the run's timeline keeps every takeover of a step, start and result: increment-step reads it, so a step whose
# takeover started cannot advance without its record, and a recheck can start only from a result recorded there
# _tl <event> [jq args…] — one line in the run's timeline, the same shape log_event writes; unlike log_event
# (which never blocks a pipeline) a line that could not be written is a failure here
_tl() {
  local ev="$1"; shift
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg e "$ev" --argjson step "$N" --arg path "$PATHKIND" "$@" \
    '{ts: $ts, event: $e} + ($ARGS.named | del(.ts, .e))' >> "${EV}/timeline.jsonl" 2>/dev/null
}
_log_result() {
  _tl step_takeover_result --arg status "$STATUS" --arg step_sha "$STEP_SHA" --arg base_sha "$BASE_SHA" --arg landed_sha "$LANDED_SHA"
}
_end() {  # <status> <reason> — the record is written only by the takeover that owns it: one that holds the lock
          # AND has started (`running`). A refused second takeover, or one refused before it started, leaves the
          # record as it was (the running one's, or the landed one a --recheck starts from).
  STATUS="$1" REASON="$2${BACK_NOTE}"
  if (( HAVE_LOCK && OWNED )); then
    # a landed result the run's timeline does not hold is not landed (increment-step asks the timeline)
    if ! _log_result && [[ "$STATUS" == landed ]]; then
      STATUS=precondition_failed REASON="the result could not be written to the run's timeline ${EV}/timeline.jsonl"
    fi
    _write
  fi
  echo "land: step ${N} (${SID}): ${STATUS}${REASON:+ — ${REASON}}"
  [[ "$STATUS" == landed ]] && exit 0 || exit 1
}
# Stopped by a signal or an error while running: the check's whole process group goes, a wave's step tree goes back
# to its branch, and the record says `interrupted` (a kill -9 cannot be caught: the next takeover repairs the tree,
# below, and the lock dies with the process — no check keeps it, its descriptor is closed for them).
# _stop_group <token> — TERM, a second, then KILL, to every process of this user that carries the check's token in
# its environment (AID_LAND_TOKEN, inherited by everything a check starts): identity by the token, not by a process
# group or a directory that a daemon can leave or a recycled number can reach.
_stop_group() {
  local tok="$1" p sig
  [[ -n "$tok" ]] || return 0
  for sig in TERM KILL; do
    for p in $(pgrep -u "$(id -u)" 2>/dev/null); do
      [[ "$p" == "$$" || "$p" == "$BASHPID" ]] && continue
      grep -qz "^AID_LAND_TOKEN=${tok}$" "/proc/${p}/environ" 2>/dev/null && kill "-${sig}" "$p" 2>/dev/null
    done
    [[ "$sig" == TERM ]] && sleep 1
  done
  return 0
}
_on_exit() {
  [[ -n "$CHECK_TOKEN" ]] && _stop_group "$CHECK_TOKEN"
  if [[ "$STATUS" == running ]] && (( HAVE_LOCK && OWNED )); then
    [[ "$PATHKIND" == wave ]] && _back
    STATUS=interrupted REASON="the takeover was stopped before it finished — take the step over again${BACK_NOTE}"
    _log_result || true; _write
  fi
}
trap _on_exit EXIT
trap 'exit 130' INT TERM HUP

# --- what the checks must be ---------------------------------------------------------------------------------
declare -A WANT=() GOT=() GOTWHY=()
while IFS=$'\t' read -r k cmd; do [[ -n "$k" ]] && WANT[$k]="$cmd"; done < <(
  jq -r --argjson i "$N" "${AID_AC_COMMAND_JQ}"'.steps[$i].acceptance_criteria // [] | to_entries[]
    | (.value | ac_command) as $c | select($c != null) | "\(.key + 1)\t\($c)"' "$PJ")
for w in "${WHY[@]+"${WHY[@]}"}"; do
  k="${w%%:*}"; [[ "$k" =~ ^[0-9]+$ && "$w" == *:* ]] || { REASON="--reason must be <AC#>:<why>, got '${w}'"; break; }
  GOTWHY[$k]="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "${w#*:}")"
done
for c in "${CHECKS[@]+"${CHECKS[@]}"}"; do
  k="${c%%:*}"; cmd="${c#*:}"; cmd="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "$cmd")"
  [[ "$k" =~ ^[0-9]+$ && "$c" == *:* ]] || { REASON="--check must be <AC#>:<command>, got '${c}'"; break; }
  [[ -z "${GOT[$k]+x}" ]] || { REASON="AC${k} is given twice"; break; }
  [[ -n "${WANT[$k]+x}" ]] || { REASON="AC${k} is not a command criterion (its text does not begin with a backticked command)"; break; }
  # 3.13.0: another command measures the same point elsewhere (the plan's `docker compose exec` reads the main
  # checkout) only with its reason, which the record and increment-step show
  if [[ "$cmd" != "${WANT[$k]}" ]] && (( ${#GOTWHY[$k]} < 10 )); then
    REASON="AC${k}: the command differs from the plan's — plan: ${WANT[$k]} · given: ${cmd} (a replacement needs --reason \"${k}:<why, 10+ chars>\")"; break
  fi
  GOT[$k]="$cmd"
done
if [[ -z "$REASON" ]]; then
  for k in "${!GOTWHY[@]}"; do
    [[ -n "${GOT[$k]+x}" && "${GOT[$k]}" != "${WANT[$k]:-}" ]] || { REASON="AC${k} has --reason but no replaced --check"; break; }
  done
fi
if [[ -z "$REASON" ]]; then
  for k in "${!WANT[@]}"; do [[ -n "${GOT[$k]+x}" ]] || { REASON="AC${k} is a command criterion and has no --check: ${WANT[$k]}"; break; }; done
fi
for e in "${ENVS[@]+"${ENVS[@]}"}"; do [[ "$e" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || REASON="--env must be NAME=value, got '${e}'"; done
[[ -z "$REASON" ]] || _end precondition_failed "$REASON"

# --- one takeover per plan at a time ---------------------------------------------------------------------------
mkdir -p "${STATE_ROOT}/.aid-o/work/locks"
aid_lock_acquire "${STATE_ROOT}/.aid-o/work/locks/land-${EPIC}.lock" "$LOCK_WAIT" \
  || _end precondition_failed "another takeover of ${EPIC} is running (lock held over ${LOCK_WAIT} s)"
LOCK_FD="$AID_LOCK_FD"; HAVE_LOCK=1

cur="$(yq -r '.current_step // ""' "$SF")"
[[ "$cur" == "$N" ]] || _end precondition_failed "the run's current step is ${cur}, not ${N} — steps are taken over in order"
WBASE="$(aid_orchestration_value "$STATE_ROOT" .dispatch.worktree_base | cut -f1)"
WT="$(_aid_pd_step_worktree_path "$TREE" "$SID" "$WBASE")"; BR="$(_aid_pd_step_branch "$SID")"
if (( RECHECK )); then PATHKIND=recheck; WT="$TREE"
elif [[ -d "$WT" ]] && git -C "$TREE" show-ref --verify --quiet "refs/heads/${BR}"; then PATHKIND=wave
else PATHKIND=serial; WT="$TREE"; fi
# the plan's tree is clean except on the serial path, where the step's own uncommitted work is in it
if [[ "$PATHKIND" != serial ]]; then
  git -C "$TREE" diff --quiet && git -C "$TREE" diff --cached --quiet \
    || _end precondition_failed "the plan's tree ${TREE} has uncommitted changes"
fi
git -C "$TREE" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 \
  || _end precondition_failed "this git has no merge-tree --write-tree (needs 2.38+): increment-step could not check the landed merge"
CSHA="$(_sha "${SD}/contract.json")"
if (( RECHECK )); then   # the record is about to be replaced: take what proves the takeover from it first
  # what the recheck starts from: a landed record's commit; the base a failed recheck carried forward; or, on the
  # serial path, the step's own commit when its checks failed (the commit stays there, the role fixes on top of it)
  prev="$(jq -r 'if .status == "landed" then .landed_sha elif .path == "recheck" then .base_sha
                 elif .path == "serial" and .status == "check_failed" then .step_sha else "" end // ""' "$REC" 2>/dev/null)"
  [[ -n "$prev" ]] || _end precondition_failed "no landed record of step ${N} to recheck"
  RSHA="$(jq -r '.return_sha256 // ""' "$REC")"; STEP_SHA="$(jq -r '.step_sha // ""' "$REC")"
fi
# a takeover killed with -9 cannot clean up: its check's process group may still run in the step's tree — stop it
# before this one touches anything (the record names the check's token while it runs)
old_tok="$(jq -r 'select(.status == "running") | .check_token // ""' "$REC" 2>/dev/null)"
[[ "$old_tok" =~ ^[0-9a-f]{32}$ ]] && _stop_group "$old_tok"
(( RECHECK )) && BASE_SHA="$prev"
OWNED=1; _write   # running
_tl step_takeover_started || _end precondition_failed "the run's timeline ${EV}/timeline.jsonl cannot be written"

# --- the checks ---------------------------------------------------------------------------------------------------
_run_checks() {  # <cwd> — every --check in order; stops at the first that fails
  local cwd="$1" k cmd rc t0 t1 log out timed
  for k in $(printf '%s\n' "${!GOT[@]}" | sort -n); do
    cmd="${GOT[$k]}"; log="${SD}/land-logs/ac${k}.log"
    t0=$(date +%s)
    # Output to a file, never a pipe: a test that leaves a server running would hold a pipe open past its time
    # limit. GNU timeout makes itself a group leader (its pid = the group) and signals the whole group; the lock's
    # descriptor is closed for the check, so a process it leaves behind cannot keep the plan locked.
    CHECK_TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    _write   # the token is in the record before any process carries it: a kill -9 from here on leaves it findable
    ( cd "$cwd" && exec env "${ENVS[@]+"${ENVS[@]}"}" AID_LAND_TOKEN="$CHECK_TOKEN" timeout -k 10 "$TMO" bash -c "$cmd" ) \
      > "${log}.raw" 2>&1 {LOCK_FD}>&- &
    CHECK_PID=$!; wait "$CHECK_PID"; rc=$?
    _stop_group "$CHECK_TOKEN"   # a process the check left behind (a server, a watcher, a daemon) goes too
    CHECK_PID="" CHECK_TOKEN=""
    t1=$(date +%s); timed=false; [[ $rc == 124 || $rc == 137 ]] && timed=true
    out="$(aid_gate_outcome_redact "$(cat "${log}.raw")")"; rm -f "${log}.raw"
    printf '%s\n' "$out" > "$log"
    CHECKS_JSON="$(jq -c --argjson k "$k" --arg c "$cmd" --argjson x "$rc" --argjson d "$((t1 - t0))" --argjson to "$timed" \
      --arg tail "$(tail -c 4000 <<< "$out")" --arg log "$log" \
      --arg pc "${WANT[$k]}" --arg why "${GOTWHY[$k]:-}" \
      '. + [{ac: $k, command: $c, exit: $x, duration_s: $d, timed_out: $to, output_tail: $tail, log: $log}
            + (if $c != $pc then {plan_command: $pc, reason: $why} else {} end)]' <<< "$CHECKS_JSON")"
    _write
    (( rc == 0 )) || { REASON="AC${k} failed (exit ${rc}$([[ $timed == true ]] && echo ", timed out after ${TMO} s")): ${cmd}"; return 1; }
    # untracked files (caches, reports a test writes) do not count; tracked changes and commits do
    local dirty; dirty="$(git -C "$cwd" status --porcelain --untracked-files=no | cut -c4- | tr '\n' ' ')"
    [[ -z "$dirty" ]] || { REASON="AC${k} passed but changed tracked files: ${dirty}— a check must not change the step's work"; return 1; }
  done
  return 0
}
_settled() {  # <tree> — before a landed record: nothing (a check, the measurer) committed or changed tracked files
  [[ "$(git -C "$1" rev-parse HEAD)" == "$LANDED_SHA" ]] \
    || _end base_moved "HEAD moved to $(git -C "$1" rev-parse --short HEAD) during the takeover (a check or the measurer committed?) — take the step over again"
  git -C "$1" diff --quiet && git -C "$1" diff --cached --quiet \
    || _end check_failed "tracked files changed during the takeover: $(git -C "$1" status --porcelain --untracked-files=no | cut -c4- | tr '\n' ' ')"
}
_measure() {  # the plan's own measurer on the landed HEAD; increment-step reuses its result when bound to HEAD
  local pp base rc=0
  pp="$(yq -r '.plan_path // ""' "$SF")"; base="$(yq -r '.base_commit // "HEAD"' "$SF")"
  [[ -n "$pp" && "$pp" != null && -f "$pp" ]] || { MEASURE="skipped: no plan file"; return 0; }
  (cd "$TREE" && timeout -k 10 "$TMO" bash "${SCRIPT_DIR}/aid-plan-diff.sh" --plan "$pp" --evidence-dir "$EV" --base-commit "$base" \
     --step "$N" --plan-json "$PJ" > "${SD}/land-logs/measure.log" 2>&1) || rc=$?
  MEASURE="aid-plan-diff.sh exit ${rc}"
}

# --- recheck ------------------------------------------------------------------------------------------------------
if (( RECHECK )); then
  BASE_SHA="$prev"; LANDED_SHA="$(git -C "$TREE" rev-parse HEAD)"
  git -C "$TREE" merge-base --is-ancestor "$prev" "$LANDED_SHA" || _end precondition_failed "HEAD ${LANDED_SHA:0:8} does not descend from the landed ${prev:0:8}"
  _run_checks "$TREE" || _end check_failed "$REASON"
  _measure; _settled "$TREE"; _end landed ""
fi

# --- wave or serial ---------------------------------------------------------------------------------------------
# the step's tree goes back to its branch, clean, on every failure; what it could not do is said in the record
_back() {
  git -C "$WT" merge --abort >/dev/null 2>&1 || true
  if [[ -z "$(git -C "$WT" branch --show-current)" ]]; then   # detached on a candidate: its work is all on the branch
    git -C "$WT" reset -q --hard 2>/dev/null; git -C "$WT" checkout -q "$BR" 2>/dev/null
  fi
  [[ "$(git -C "$WT" branch --show-current)" == "$BR" && -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ]] \
    || BACK_NOTE=" · the step's tree ${WT} did not return clean to ${BR} — look at it before taking the step over again"
}
# a takeover killed before it could clean up (kill -9) left the step's tree detached on a candidate: repair it first
if [[ "$PATHKIND" == wave && -z "$(git -C "$WT" branch --show-current)" ]]; then
  _back; [[ -z "$BACK_NOTE" ]] || _end precondition_failed "a previous takeover left the step's tree detached and it could not be repaired${BACK_NOTE}"
fi
[[ -f "${SD}/output.md" && -f "${SD}/contract.json" ]] || _end precondition_failed "the step has no output.md or contract.json in ${SD}"
aid_dispatch_contract_extract "${SD}/output.md" > "${SD}/return.json.tmp" 2>"${SD}/land-logs/extract.log" \
  && mv -f "${SD}/return.json.tmp" "${SD}/return.json" \
  || { rm -f "${SD}/return.json.tmp"; _end return_rejected "$(head -1 "${SD}/land-logs/extract.log")"; }
RSHA="$(_sha "${SD}/return.json")"
if ! rep="$(aid_dispatch_contract_validate "${SD}/contract.json" "${SD}/return.json" "$WT")"; then
  _end return_rejected "$(jq -r '.reasons | join("; ")' <<< "$rep" 2>/dev/null)"
fi
title="$(jq -r --argjson i "$N" '.steps[$i].objective // .steps[$i].id' "$PJ" | cut -c1-72)"
BASE_SHA="$(git -C "$TREE" rev-parse HEAD)"
aid_dispatch_contract_commit "$WT" "${SD}/contract.json" "${SD}/return.json" "step $((N + 1)): ${title}" \
  > "${SD}/land-logs/commit.log" 2>&1 || _end return_rejected "the commit was refused: $(tail -1 "${SD}/land-logs/commit.log")"
if [[ "$PATHKIND" == wave ]]; then STEP_SHA="$(git -C "$TREE" rev-parse "refs/heads/${BR}")"; else STEP_SHA="$(git -C "$TREE" rev-parse HEAD)"; fi
_write

if [[ "$PATHKIND" == serial ]]; then
  LANDED_SHA="$STEP_SHA"
  _run_checks "$TREE" || _end check_failed "$REASON"
  _measure; _settled "$TREE"; _end landed ""
fi

# wave: the candidate is built in the step's tree, detached, so the plan's branch moves only when it is proven
pbranch="$(git -C "$TREE" branch --show-current)"
git -C "$WT" checkout -q --detach "$BASE_SHA" 2>"${SD}/land-logs/merge.log" || { _back; _end precondition_failed "the step's tree cannot leave ${BR}: $(head -1 "${SD}/land-logs/merge.log")"; }
if ! git -C "$WT" merge --no-ff --no-edit -m "Merge branch '${BR}' into ${pbranch}" "$BR" >> "${SD}/land-logs/merge.log" 2>&1; then
  conflicted="$(git -C "$WT" diff --name-only --diff-filter=U | tr '\n' ' ')"
  _back
  _end merge_conflict "${BR} conflicts with the plan's HEAD in: ${conflicted:-?} — reset the step onto the new base (aid_parallel_step_reset) and dispatch it again"
fi
LANDED_SHA="$(git -C "$WT" rev-parse HEAD)"
_run_checks "$WT" || { LANDED_SHA=""; _back; _end check_failed "$REASON"; }
[[ "$(git -C "$TREE" rev-parse HEAD)" == "$BASE_SHA" ]] || { _back; LANDED_SHA=""; _end base_moved "the plan's HEAD moved during the takeover — take the step over again"; }
git -C "$TREE" diff --quiet && git -C "$TREE" diff --cached --quiet || { _back; LANDED_SHA=""; _end precondition_failed "the plan's tree got uncommitted changes during the takeover"; }
git -C "$TREE" merge --ff-only -q "$LANDED_SHA" 2>>"${SD}/land-logs/merge.log" || { _back; LANDED_SHA=""; _end base_moved "the plan's branch could not be fast-forwarded: $(tail -1 "${SD}/land-logs/merge.log")"; }
git -C "$TREE" worktree remove "$WT" >/dev/null 2>&1 || echo "land: ${WT} was kept — it holds uncommitted work" >&2
_measure; _settled "$TREE"
_end landed ""   # the lock goes with the process, after the record is written
