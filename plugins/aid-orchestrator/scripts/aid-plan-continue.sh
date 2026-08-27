#!/usr/bin/env bash
# =============================================================================
# aid-plan-continue.sh — one finished EPIC forward. (P090 Step 3.)
#
# WHY THIS IS A PROGRAM AND NOT A PARAGRAPH. The sequence below is exactly the
# one `skills/pipeline.md` (steps 16a/16b) has been prescribing to a human:
# mirror the merge into the queue, ask what is next, claim it, start it. As
# prose it was a rule that had to be REMEMBERED, and a test could prove at most
# that the prose existed. As a script it can be run, and a test can drive it end
# to end. That is the whole difference this file makes.
#
# WHAT IT DOES NOT DO. It does not close a plan: on `none` it NAMES the closing
# sequence and stops, because closing is a decision. It has no loop of its own:
# one invocation moves a plan by one EPIC and exits.
#
# WHAT IT CAN OPTIONALLY DO (P090 Step 6). `epic-start` registers the branch and
# the manifest record; it does not RUN the EPIC — an agent does. With
# `autonomy.spawn_next_epic: true` in `.aid-o/config/project.yaml` this script
# starts that agent: a headless `claude -p "/aid-run --auto --epic <id>"` under
# `aid-job.sh` (IMP-262), which gives it a durable identity, a deadline and a
# collectable terminal result. DEFAULT OFF, and that is a decision about money
# and trust rather than a technical detail — sessions that start sessions are
# not something to switch on by accident.
#
# THE ORDER, AND WHY EACH LINK IS WHERE IT IS:
#
#   0. PROOF   `git merge-base --is-ancestor <task branch> plan/<plan>`.
#      Before anything is written. A queue entry with no `merge_target` is
#      judged by its status alone (lib/aid-queue-write.sh:_queue_dep_state), so
#      an unearned `merged_to_plan` there would falsely unblock a dependent.
#      No proof, no mirror.
#   1. MIRROR  `set-status <finished epic> merged_to_plan`. Skipped when the
#      entry already says so, which is what makes a second run harmless.
#      A refusal because the entry is terminal means queue and manifest
#      disagree: stop and report — never reconcile by hand.
#   2. ASK     `aid-plan-fsm.sh next-epic <plan>` — the READ from Step 2, which
#      changes nothing and leaves a timeline line. `none` or `blocked:` ends the
#      run HERE, with the queue never claimed.
#   3. CLAIM   `aid-queue-write.sh claim-next <plan>`. Between the ask and the
#      claim the queue can move; if the claim takes a different entry, that is
#      not an error, it is recorded.
#   4. START   `aid-plan-fsm.sh epic-start <plan> <the entry CLAIM took>`.
#
# IDEMPOTENCE KEYS ON THE QUEUE, not on any artifact: run it twice over the same
# finished EPIC and the second run skips the mirror and simply asks again.
#
# THE ONE STATE IT WILL NOT CLEAN UP SILENTLY. If the process dies between
# claim and start, the entry is left `running` with nothing running. `peek`
# deliberately does not return such an entry, and this script will not quietly
# reset one either — a `running` entry is either a crash or somebody else's live
# run, and taking it out from under a live run is worse than waiting. It is
# reported, and released only by an explicit, human-invoked
# `--reclaim <epic_id>`, which no automation calls.
#
# THE GUIDANCE FILE (P090 Step 4). `.aid-o/work/evidence/<plan>/continue-state.json`,
# schema `aid-plan-continue/1`. Written at the end of EVERY run — the ones that
# advanced the plan and the ones that stopped at link 0 alike, because the run that
# failed is exactly the one somebody will come back to. `next_epic` is filled in only
# when an EPIC was really started; a guidance naming an unstarted EPIC as in flight
# would be worse than none. A guidance that cannot itself be written is announced on
# stderr and does not undo the advance that already happened. Read at the start of
# the next run. It is a GUIDANCE, not an authority: after a lost turn it says where the
# last run got to, and the next run still ASKS the queue, because what is merged can
# have changed in between. It is deliberately NOT the existing `aid-auto-resume/1`
# artifact — that one is written by aid-run-gates.sh about an unfinished GATE and read
# by aid-fsm.sh, and folding a queue answer into it would change a schema somebody else
# parses.
#
# Exit codes:
#   0  the plan moved on (or ended cleanly: `none` / `blocked:` / nothing owed)
#   1  something in the chain failed and was named; the plan did NOT move
#   2  usage
#   3  transient — retry later, and never treat it as an end. A lock that was
#      unavailable, or any unexpected non-usage failure of `next-epic` /
#      `claim-next`. A `next-epic` USAGE refusal (exit 2 — an unknown plan) is
#      permanent and comes back as 1 instead, because retrying it forever is
#      what a loop would otherwise do.
#   4  the plan advanced but the spawn it was configured to do did not happen
#      (see Step 6). The state is correct and claimable; nothing is running.
#
# **Last Updated:** 2026-08-27
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_LIB="${SCRIPT_DIR}/lib/aid-queue-write.sh"
PLAN_FSM="${SCRIPT_DIR}/aid-plan-fsm.sh"

# The queue library is SOURCED for its readers only — `_queue_resolve_dep_branch`
# is the one place that knows how an EPIC's task branch is found (conventional
# name first, then the branch its evidence recorded), and a second copy of that
# knowledge here is exactly how a proof starts disagreeing with the check it is
# meant to mirror. Every WRITE still goes through the CLI, one subprocess per
# transition, so this file never holds the queue lock.
# shellcheck disable=SC1090
source "$QUEUE_LIB"

# The run's subject, set by main before anything reads them. Declared here so
# no path can reference one under `set -u` before it is assigned.
ROOT=""
PLAN_ID=""
FINISHED_EPIC=""

_pc_say()  { printf '%s\n' "$*"; }
_pc_fail() { printf 'ERROR: aid-plan-continue: %s\n' "$*" >&2; }

_pc_usage() {
  cat <<'EOF'
Usage: aid-plan-continue.sh <plan_id> <finished_epic_id> [--spawn|--no-spawn]
                           [--project-root <path>]
       aid-plan-continue.sh --reclaim <epic_id> [--project-root <path>]

Moves a plan forward by one EPIC after a merge: proof -> mirror -> ask -> claim
-> start. Prints what it did at every step.

  --spawn / --no-spawn  Override autonomy.spawn_next_epic for this run. Without
                        either, the configuration decides (default: off).
  --reclaim <epic_id>   Release an entry stuck at `running` with no live run
                        back to `pending`. HUMAN-INVOKED ONLY: automation must
                        never call it, because a `running` entry may be a live
                        run belonging to somebody else.
EOF
}

# _pc_queue <args...> — the queue CLI against the resolved root.
_pc_queue() { bash "$QUEUE_LIB" "$@" --project-root "$ROOT"; }

# _pc_note <event> [epic_id] [detail] — one line into the plan's timeline.
# Best-effort by design: the AUTHORITATIVE trace of what was asked is written
# by `next-epic` itself (which fails hard if it cannot record). These are the
# surrounding notes, and losing one must not undo a merge that already landed.
_pc_note() {
  local ev_dir="${ROOT}/.aid-o/work/evidence/${PLAN_ID}"
  local ev
  ev="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$PLAN_ID" \
        --arg event "$1" --arg epic "${2:-}" --arg detail "${3:-}" \
        '{event:$event, plan_id:$plan, epic_id:$epic, detail:$detail, at:$ts}' 2>/dev/null)" || return 0
  [[ -n "$ev" ]] || return 0
  mkdir -p "$ev_dir" 2>/dev/null || return 1
  printf '%s\n' "$ev" >> "${ev_dir}/timeline.jsonl" 2>/dev/null || return 1
  return 0
}

# _pc_note_strict <event> [epic_id] [detail] — the same line, but a failure to
# record it is a failure.
#
# Used for every SPAWN decision and for nothing else. Starting a session costs
# money, and a decision about money that nobody can look up afterwards is not
# an auditable decision — AC21 asks for the reasons to be recorded, not for
# them to be attempted. Everything else in this script stays best-effort,
# because losing a note about a merge that already landed helps nobody.
_pc_note_strict() {
  if ! _pc_note "$@"; then
    _pc_fail "could not record the '$1' decision in ${ROOT}/.aid-o/work/evidence/${PLAN_ID}/timeline.jsonl. Starting a session is an action with a cost; refusing rather than doing it unrecorded."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# The guidance file — one reader, one writer, both in this script. (Step 4.)
#
# An artifact with no reader causes nothing to resume, so the producer and the
# consumer are deliberately the same program.
# ---------------------------------------------------------------------------
_pc_state_path() { printf '%s/.aid-o/work/evidence/%s/continue-state.json' "$ROOT" "$PLAN_ID"; }

# _pc_state_read — sets _PC_GUIDE_JSON (empty when there is nothing usable) and
# _PC_GUIDE_NOTE (the line to print when there is not). Deliberately assigns to
# globals instead of echoing: a `$(...)` call runs in a subshell, and every
# variable it sets dies with it — which is exactly how a guidance can be read
# and then silently forgotten.
#
# Never half-interprets: anything that is not a well-formed object of THIS
# schema is treated as absent and said so, rather than mined for whichever
# fields happen to have survived.
_PC_GUIDE_JSON=""
_PC_GUIDE_NOTE=""
_pc_state_read() {
  _PC_GUIDE_JSON=""; _PC_GUIDE_NOTE=""
  local f; f="$(_pc_state_path)"
  if [[ ! -f "$f" ]]; then
    _PC_GUIDE_NOTE="guide:   none — this run starts from the queue alone"
    return 0
  fi
  # The guard is the whole schema, not just its name (Codex review, EPIC 1):
  # the right `schema` on a file copied from ANOTHER plan carries that plan's
  # `next_epic`, and an unfinished one from P091 would refuse P090's mirror.
  # So: our schema, our plan, and every field present and a string.
  _PC_GUIDE_JSON="$(jq -ec --arg plan "$PLAN_ID" '
      select(.schema == "aid-plan-continue/1")
      | select(.plan_id == $plan)
      | select((.last_completed_epic | type) == "string")
      | select((.last_result | type) == "string")
      | select((.next_epic | type) == "string")
      | select((.at | type) == "string")
      | select((.job_id | type) == "string")
      | select((.jobs_dir | type) == "string")
      | select((.job_fingerprint | type) == "string")
      | select((.spawned_count | type) == "number")' "$f" 2>/dev/null)" || _PC_GUIDE_JSON=""
  if [[ -z "$_PC_GUIDE_JSON" ]]; then
    _PC_GUIDE_NOTE="guide:   ${f} is unreadable, not aid-plan-continue/1, or not about ${PLAN_ID} — ignoring it and asking the queue instead"
  fi
  return 0
}

# _pc_state_write <last_result> [next_epic] — atomically. A crash mid-write must
# not leave half a file behind, so it is tmp + mv, exactly like every other
# durable write in this plugin.
# The four job fields exist because of Step 6, and they are here rather than in
# the job record for a reason: `aid-job.sh status`/`collect` need an EXACT job
# id, and after an interruption nothing else in the plan knows it — `watchdog`
# only asks about a whole directory. `spawned_count` is here too because a cap
# that does not survive a restart is not a cap. They carry forward untouched on
# a run that did not spawn, so an ordinary continuation never erases them.
_pc_state_write() {
  local last_result="$1" next_epic="${2:-}"
  local f; f="$(_pc_state_path)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || { _pc_fail "cannot create $(dirname "$f") — the guidance was not written."; return 1; }

  local job_id="$_PC_SPAWN_JOB_ID" jobs_dir="$_PC_SPAWN_JOBS_DIR" fp="$_PC_SPAWN_FINGERPRINT" n="$_PC_SPAWN_COUNT"
  if [[ -z "$job_id" && -n "$_PC_GUIDE_JSON" ]]; then
    job_id="$(jq -r '.job_id // ""'          <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    jobs_dir="$(jq -r '.jobs_dir // ""'      <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    fp="$(jq -r '.job_fingerprint // ""'     <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if [[ "$n" -eq 0 && -n "$_PC_GUIDE_JSON" ]]; then
    local prev; prev="$(jq -r '.spawned_count // 0' <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    [[ "$prev" =~ ^[0-9]+$ ]] && n="$prev"
  fi

  local tmp="${f}.tmp.$$"
  if ! jq -n --arg plan "$PLAN_ID" --arg last "$FINISHED_EPIC" --arg res "$last_result" \
        --arg next "$next_epic" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg job "$job_id" --arg jd "$jobs_dir" --arg fp "$fp" --argjson n "$n" \
        '{schema:"aid-plan-continue/1", plan_id:$plan, last_completed_epic:$last,
          last_result:$res, next_epic:$next, at:$at,
          job_id:$job, jobs_dir:$jd, job_fingerprint:$fp, spawned_count:$n}' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    _pc_fail "could not stage the guidance at ${tmp}."
    return 1
  fi
  mv -- "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; _pc_fail "could not install the guidance at ${f}."; return 1; }
  return 0
}

# _pc_report_stranded — every entry of this plan sitting at `running`.
#
# AC12. Such an entry is either a crash between claim and start, or somebody
# else's live run; the two are indistinguishable from here, which is exactly why
# it is REPORTED and never collected. `peek` already refuses to return one, so
# without this the plan would simply go quiet about it.
_pc_report_stranded() {
  local file; file="$(queue_write_path)"
  [[ -f "$file" ]] || return 0
  # Under the queue lock, like every other read that has to be self-consistent:
  # a scan racing a claim's rewrite can miss the very entry it exists to find
  # (Codex review, EPIC 1). A lock we cannot get is reported, never silently
  # turned into "nothing is stuck".
  if ! aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)"; then
    _pc_say "stuck:   could not read the queue under its lock just now — no claim is made here about entries left at 'running'."
    return 0
  fi
  local fd="$AID_LOCK_FD"
  local id ids
  ids="$(queue_entry_ids "$file")"
  while IFS= read -r id; do
    [[ -n "$id" ]] && _queue_valid_id "$id" || continue
    [[ "$(queue_get_field "$id" plan_id "$file")" == "$PLAN_ID" ]] || continue
    [[ "$(queue_get_status "$id" "$file")" == "running" ]] || continue
    _pc_say "stuck:   ${id} is 'running'. If no run is behind it, it is a crash between claim and start;"
    _pc_say "         nothing here will collect it, because it may be a live run. Release it yourself with:"
    _pc_say "           aid-plan-continue.sh --reclaim ${id}"
  done <<< "$ids"
  aid_lock_release "$fd"
  return 0
}

# _pc_is_merged <epic_id> — the same ancestry question as link 0, but silent and
# as a predicate. Used to judge the guidance, never as the proof itself.
_pc_is_merged() {
  local branch; branch="$(_queue_resolve_dep_branch "$1" "$ROOT")"
  [[ -n "$branch" ]] || return 1
  git -C "$ROOT" merge-base --is-ancestor "$branch" "plan/${PLAN_ID}" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# _pc_prove_merged <plan_id> <epic_id> — link 0.
# Returns 0 when the EPIC's work is provably an ancestor of plan/<plan_id>.
# ---------------------------------------------------------------------------
_pc_prove_merged() {
  local plan_id="$1" epic_id="$2"
  local plan_branch="plan/${plan_id}"
  if ! git -C "$ROOT" show-ref --verify --quiet "refs/heads/${plan_branch}"; then
    _pc_fail "there is no ${plan_branch} in ${ROOT} — nothing can be proven merged into it."
    return 1
  fi
  local branch; branch="$(_queue_resolve_dep_branch "$epic_id" "$ROOT")"
  if [[ -z "$branch" ]]; then
    _pc_fail "cannot find the task branch for ${epic_id} (neither task/${epic_id}/main nor a branch recorded in its evidence) — refusing to mirror a merge it cannot prove."
    return 1
  fi
  if ! git -C "$ROOT" merge-base --is-ancestor "$branch" "$plan_branch" >/dev/null 2>&1; then
    _pc_fail "${branch} is not an ancestor of ${plan_branch} — ${epic_id} is not merged, so nothing is mirrored. Run 'aid-plan-fsm.sh epic-merge-to-plan ${plan_id} ${epic_id}' first."
    return 1
  fi
  _pc_say "proof:   ${branch} is an ancestor of ${plan_branch}"
  return 0
}

# ===========================================================================
# STEP 6 — starting the claimed EPIC as a supervised job.
#
# Everything below is inert unless it is switched on. The switch lives in
# `.aid-o/config/project.yaml`, read exactly the way P089 reads its own keys
# (lib/aid-release-scope.sh): through `yq`, defaulting when the tool, the file
# or the key is absent, and REFUSING — by name — when a key is present but not
# a usable value. A silent default over a typo is how a cap of 3 becomes no cap.
#
#   autonomy.spawn_next_epic     bool  default false
#   autonomy.max_spawned_epics   int>0 default 3
#   autonomy.spawn_deadline_sec  int>0 default 3600
# ===========================================================================

_PC_SPAWN_DEFAULT_ENABLED=false
_PC_SPAWN_DEFAULT_MAX=3
_PC_SPAWN_DEFAULT_DEADLINE=3600

# _pc_cfg <key> — the raw scalar under `autonomy.` in project.yaml, or nothing.
# Nothing means "not configured", which is the caller's cue to use its default.
_pc_cfg() {
  command -v yq >/dev/null 2>&1 || return 1
  local cfg="${ROOT%/}/.aid-o/config/project.yaml"
  [[ -f "$cfg" ]] || return 1
  local out
  out="$(yq -r ".autonomy.$1" "$cfg" 2>/dev/null)" || return 1
  [[ -n "$out" && "$out" != "null" ]] || return 1
  printf '%s' "$out"
}

# _pc_cfg_bool <key> <default> / _pc_cfg_int <key> <default>
#
# A missing value defaults AND SAYS SO — on stderr, because stdout is the value.
# Saying so is not decoration: "it is off" and "nothing told me, so it is off"
# lead to different next actions, and only one of them is a configuration bug.
# A PRESENT but unusable value is an error naming the key, never a quiet
# fallback: a silent default over a typo is how a cap of 3 becomes no cap.
#
# "It was defaulted" is reported through the EXIT CODE — 0 configured, 10
# defaulted, 1 unusable — and never through a global. Both are called in
# `$(...)`, and a variable assigned inside a command substitution dies with the
# subshell: the first cut of this used a global and the caller read it as unset
# every single time.
_PC_CFG_RC_DEFAULTED=10
_pc_cfg_bool() {
  local raw
  if ! raw="$(_pc_cfg "$1")"; then
    echo "NOTE: aid-plan-continue: autonomy.$1 is not configured; using the default '$2'." >&2
    printf '%s' "$2"; return "$_PC_CFG_RC_DEFAULTED"
  fi
  case "$raw" in
    true|false) printf '%s' "$raw"; return 0 ;;
    *) _pc_fail "autonomy.$1 in .aid-o/config/project.yaml is '${raw}'; it must be true or false. Nothing was spawned."; return 1 ;;
  esac
}
_pc_cfg_int() {
  local raw
  if ! raw="$(_pc_cfg "$1")"; then
    echo "NOTE: aid-plan-continue: autonomy.$1 is not configured; using the default '$2'." >&2
    printf '%s' "$2"; return "$_PC_CFG_RC_DEFAULTED"
  fi
  if [[ ! "$raw" =~ ^[0-9]+$ ]] || [[ "$raw" -lt 1 ]]; then
    _pc_fail "autonomy.$1 in .aid-o/config/project.yaml is '${raw}'; it must be a whole number of at least 1. Nothing was spawned."
    return 1
  fi
  printf '%s' "$raw"
  return 0
}

# _pc_autonomous_mode — `.aid-o/config/permissions.yaml` must really say
# `autonomous_mode: true`, as a YAML boolean. Checked BEFORE anything is
# started, not inferred afterwards from how the session behaved: a session
# launched into a workspace that has not authorised autonomy would run without
# the mode it was told to run in.
_pc_autonomous_mode() {
  local perm="${ROOT%/}/.aid-o/config/permissions.yaml"
  [[ -f "$perm" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  [[ "$(yq -r '.autonomous_mode | type' "$perm" 2>/dev/null)" == "!!bool" ]] || return 1
  [[ "$(yq -r '.autonomous_mode' "$perm" 2>/dev/null)" == "true" ]]
}

# _pc_spawned_count <jobs_dir> — how many sessions this PLAN has already
# started. Per plan, not per workspace: two plans with spawning on do not add
# up. That is a choice, and the enforcement registry says so.
#
# TWO SOURCES, AND THE HIGHER ONE WINS. The guidance carries the count, and it
# is re-read from the FILE rather than from the copy this run parsed at startup,
# because a racing continuation may have raised it since — a cap decided on a
# stale count is not a cap. But the guidance can also be missing, truncated or
# rejected by its own schema guard, and a cap that a deleted file resets is not
# a cap either. So the job directory is counted too: one directory per session
# this plan ever started, which no lost file can undo.
_pc_spawned_count() {
  local jobs_dir="${1:-}" n=0 m=0 d
  local f; f="$(_pc_state_path)"
  if [[ -f "$f" ]]; then
    n="$(jq -r 'select(.schema == "aid-plan-continue/1") | .spawned_count // 0' "$f" 2>/dev/null)" || n=0
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
  fi
  if [[ -n "$jobs_dir" && -d "$jobs_dir" ]]; then
    for d in "$jobs_dir"/p090-"${PLAN_ID}"-*; do
      [[ -d "$d" ]] && m=$((m + 1))
    done
  fi
  [[ "$m" -gt "$n" ]] && n="$m"
  printf '%s' "$n"
}

# _pc_live_plan_job <jobs_dir> <plan_id> — the id of a job of THIS plan that is
# still alive, or nothing.
#
# It scans the job directory for this plan's own id prefix rather than trusting
# the single `job_id` in the guidance: the guidance names the LAST job this
# plan started, and a job started by an earlier link of the chain — or by a run
# whose guidance write did not land — would otherwise be invisible.
#
# THE ONE EXCLUSION THAT KEEPS THE CHAIN LONGER THAN ONE. The session started
# here reaches its own merge, that merge calls this script again — and the job
# it would find running is the job it is running INSIDE. Refusing on that would
# stop the chain at length one, and nothing would restart it, because
# `aid-job.sh` is a supervisor, not a daemon. So the job id this process was
# launched under (AID_JOB_ID in its environment) is skipped. That id is known
# because it is PRE-ALLOCATED and passed to `aid-job.sh run --id`, and handed to
# the session through `env AID_JOB_ID=<id>` — the supervisor exports nothing.
_pc_live_plan_job() {
  local jobs_dir="$1" plan_id="$2" d id state
  [[ -d "$jobs_dir" ]] || return 0
  for d in "$jobs_dir"/p090-"${plan_id}"-*; do
    [[ -d "$d" ]] || continue
    id="$(basename "$d")"
    [[ "$id" == "${AID_JOB_ID:-}" ]] && continue
    # A status we could NOT read counts as live. The alternative — treating an
    # unreadable or half-written record as "nothing there" — fails open on the
    # one decision in this plan that spends money (Codex review, EPIC 2).
    if ! state="$(bash "${SCRIPT_DIR}/aid-job.sh" status --jobs-dir "$jobs_dir" --id "$id" 2>/dev/null)"; then
      printf '%s' "$id"
      return 0
    fi
    if [[ "$state" == "running" || "$state" == "started" ]]; then
      printf '%s' "$id"
      return 0
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# _pc_launch_detached <cmd...> — run a command with EVERY inherited descriptor
# above stderr closed first.
#
# MEASURED, not theoretical. `aid-job.sh` detaches the supervised command with
# `setsid` and redirects ITS 0/1/2 to the job's wrapper.log — but nothing closes
# the other descriptors the calling shell happened to have open, and the
# supervisor's deadline watchdog is a `sleep <deadline>` that lives for the
# WHOLE deadline. So a caller that captures this script's output through a pipe
# waits an hour for EOF on a pipe a sleeping process still holds. It was found
# exactly that way: a bats suite ran to completion and then sat for fifteen
# minutes with no children, because six `sleep 3600` processes held fd 3.
#
# The loop is the portable-on-Linux idiom, and Linux is already this
# supervisor's stated requirement (`aid-job.sh` reads /proc). The `$(...)` that
# lists the descriptors opens one of its own and closes it before the loop runs.
#
# THIS IS ALSO WHAT MAKES IT SAFE TO LAUNCH UNDER THE QUEUE LOCK. The lock is an
# open descriptor too; flock drops only when the LAST one closes, so a detached
# child inheriting it would hold the queue for the job's lifetime. Closing every
# descriptor above stderr removes that, which is why the cap check, the
# running-job check, the reservation AND the launch can all sit inside one hold
# — and therefore why two racing continuations cannot both start a session.
_pc_launch_detached() {
  bash -c '
    exec 0</dev/null
    _fds="$(ls /proc/self/fd 2>/dev/null)"
    for _n in $_fds; do
      [ "$_n" -gt 2 ] 2>/dev/null && eval "exec ${_n}>&-" 2>/dev/null
    done
    exec "$@"
  ' _ "$@"
}

# ---------------------------------------------------------------------------
# _pc_spawn <plan_id> <epic_id> <override>
#   <override> is "", "yes" or "no" (--spawn / --no-spawn).
#
#   Returns 0 when a session was started OR when spawning was legitimately not
#   done (switched off, cap reached, a job already running) — those are normal
#   outcomes and every one of them is recorded. Returns 1 only when spawning was
#   ASKED FOR and could not happen, because then the caller is left believing
#   something is running that is not.
#
#   Prints the job id it started on stdout via the "spawn:" line, and writes
#   _PC_SPAWN_JOB_ID / _PC_SPAWN_COUNT for the guidance the caller then writes.
# ---------------------------------------------------------------------------
_PC_SPAWN_JOB_ID=""
_PC_SPAWN_JOBS_DIR=""
_PC_SPAWN_FINGERPRINT=""
_PC_SPAWN_COUNT=0
_pc_spawn() {
  local plan_id="$1" epic_id="$2" override="$3"

  # EVERY key is validated first, before any short-circuit. AC21b says an
  # unusable value is an error naming the key, and a `max_spawned_epics: 0`
  # that goes unreported because spawning happens to be off today is a trap
  # waiting for the day somebody turns it on (Codex review, EPIC 2).
  local max deadline crc=0
  crc=0; max="$(_pc_cfg_int max_spawned_epics "$_PC_SPAWN_DEFAULT_MAX")" || crc=$?
  [[ "$crc" -ne 0 && "$crc" -ne "$_PC_CFG_RC_DEFAULTED" ]] && return 1
  crc=0; deadline="$(_pc_cfg_int spawn_deadline_sec "$_PC_SPAWN_DEFAULT_DEADLINE")" || crc=$?
  [[ "$crc" -ne 0 && "$crc" -ne "$_PC_CFG_RC_DEFAULTED" ]] && return 1

  local enabled defaulted="no"
  if [[ "$override" == "yes" ]]; then enabled=true
  elif [[ "$override" == "no" ]]; then
    _pc_say "spawn:   off (--no-spawn). ${epic_id} is claimed and ready; starting it is the controller's move."
    _pc_note "spawn_skipped" "$epic_id" "reason=flag_no_spawn"
    return 0
  else
    crc=0
    enabled="$(_pc_cfg_bool spawn_next_epic "$_PC_SPAWN_DEFAULT_ENABLED")" || crc=$?
    [[ "$crc" -eq "$_PC_CFG_RC_DEFAULTED" ]] && defaulted="yes"
    [[ "$crc" -ne 0 && "$defaulted" == "no" ]] && return 1
  fi

  if [[ "$enabled" != "true" ]]; then
    # "nobody configured it" and "somebody configured it off" are different
    # facts and lead to different next actions.
    local why="autonomy.spawn_next_epic is false"
    [[ "$defaulted" == "yes" ]] && why="autonomy.spawn_next_epic is not configured, and the default is false"
    _pc_say "spawn:   off (${why}). ${epic_id} is claimed and ready; starting it is the controller's move."
    _pc_note "spawn_skipped" "$epic_id" "reason=disabled defaulted=${defaulted}"
    return 0
  fi

  if ! _pc_autonomous_mode; then
    _pc_fail "spawning is switched on, but .aid-o/config/permissions.yaml does not say 'autonomous_mode: true'. A session started without it would not run in the mode it was told to. ${epic_id} stays claimed and ready; nothing was started."
    _pc_note "spawn_refused" "$epic_id" "reason=autonomous_mode_absent"
    return 1
  fi
  if ! command -v claude >/dev/null 2>&1; then
    _pc_fail "spawning is switched on, but there is no 'claude' on PATH. ${epic_id} stays claimed and ready; nothing was started."
    _pc_note "spawn_refused" "$epic_id" "reason=claude_not_on_path"
    return 1
  fi

  local jobs_dir="${ROOT%/}/.aid-o/work/jobs"
  mkdir -p "$jobs_dir" 2>/dev/null || true

  # THE WHOLE DECISION, AND THE LAUNCH, INSIDE ONE HOLD of the queue's own lock:
  # the cap, the "is one already running" test, the reservation and
  # `aid-job.sh run` itself. Two racing continuations therefore cannot both see
  # "nothing is running" and both start a session, and a session is the only
  # thing in this plan that costs money — at-most-once is not academic here.
  #
  # An earlier cut released the lock BEFORE launching, on the reasoning that a
  # `setsid`-detached child inherits a duplicate of the lock descriptor and
  # flock drops only when the last one closes. That reasoning was right about
  # the hazard and wrong about the remedy: releasing early left a window in
  # which a second continuation saw a raised count but no job directory yet, and
  # with `max_spawned_epics > 1` it launched a second session (Codex review,
  # EPIC 2). `_pc_launch_detached` closes EVERY descriptor above stderr before
  # the supervisor runs, so the child holds neither the lock nor anything else
  # of ours — which is what makes the single hold both safe and correct.
  if ! aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)"; then
    _pc_fail "could not take the queue lock to decide about spawning ${epic_id}; nothing was started. Retry."
    _pc_note "spawn_refused" "$epic_id" "reason=lock_unavailable"
    return 1
  fi
  local fd="$AID_LOCK_FD"

  # Read under the lock, never before it — see _pc_spawned_count.
  _PC_SPAWN_COUNT="$(_pc_spawned_count "$jobs_dir")"
  if [[ "$_PC_SPAWN_COUNT" -ge "$max" ]]; then
    aid_lock_release "$fd"
    _pc_say "spawn:   cap reached — this plan has already started ${_PC_SPAWN_COUNT} session(s) and autonomy.max_spawned_epics is ${max}. That is a normal end, not a failure: ${epic_id} is claimed and ready."
    _pc_note_strict "spawn_capped" "$epic_id" "spawned=${_PC_SPAWN_COUNT} max=${max}" || return 1
    return 0
  fi

  local live_job; live_job="$(_pc_live_plan_job "$jobs_dir" "$plan_id")"
  if [[ -n "$live_job" ]]; then
    aid_lock_release "$fd"
    _pc_say "spawn:   not started — job ${live_job} for this plan is still alive. ${epic_id} is claimed and ready."
    _pc_note_strict "spawn_skipped" "$epic_id" "reason=job_running job_id=${live_job}" || return 1
    return 0
  fi

  # Pre-allocated, so the id exists BEFORE the command that carries it does.
  # `aid-job.sh` generates one only after assembling argv and exports nothing,
  # so there is no other way for the session to learn its own id.
  local job_id="p090-${plan_id}-${epic_id}-$((_PC_SPAWN_COUNT + 1))"
  local prompt="/aid-run --auto --epic ${epic_id}"
  local -a jobcmd=(env "AID_JOB_ID=${job_id}" claude -p "$prompt")

  # The reservation, written BEFORE the launch and while the lock is held, so
  # that after any interruption the job id is recoverable and the count that
  # feeds the cap has already moved.
  _PC_SPAWN_JOB_ID="$job_id"
  _PC_SPAWN_JOBS_DIR="$jobs_dir"
  _PC_SPAWN_COUNT=$((_PC_SPAWN_COUNT + 1))
  _PC_SPAWN_FINGERPRINT="$(bash "${SCRIPT_DIR}/aid-job.sh" fingerprint -- "${jobcmd[@]}" 2>/dev/null)" \
    || _PC_SPAWN_FINGERPRINT=""

  # A reservation that could not be WRITTEN is not a reservation, and the docs
  # and the registry both promise it is durable. Refuse rather than start a
  # session nobody could later find or count (Codex review, EPIC 2).
  if ! _pc_state_write "$epic_id" "$epic_id"; then
    aid_lock_release "$fd"
    _PC_SPAWN_JOB_ID=""
    _PC_SPAWN_COUNT=$((_PC_SPAWN_COUNT - 1))
    _pc_fail "could not record the reservation for ${job_id} before starting it; nothing was started. ${epic_id} stays claimed and ready."
    return 1
  fi
  if ! _pc_note_strict "spawn_reserved" "$epic_id" "job_id=${job_id} n=${_PC_SPAWN_COUNT} max=${max} deadline=${deadline}"; then
    aid_lock_release "$fd"
    _PC_SPAWN_JOB_ID=""
    _PC_SPAWN_COUNT=$((_PC_SPAWN_COUNT - 1))
    return 1
  fi

  local rc=0 out=""
  out="$(_pc_launch_detached bash "${SCRIPT_DIR}/aid-job.sh" run \
          --jobs-dir "$jobs_dir" --id "$job_id" \
          --label "continue ${plan_id} ${epic_id}" --repo "$ROOT" \
          --deadline "$deadline" \
          -- "${jobcmd[@]}" 2>&1)" || rc=$?
  aid_lock_release "$fd"

  if [[ "$rc" -ne 0 ]]; then
    # The slot is spent and stays spent, and the RESERVED job id stays recorded:
    # clearing it made the caller's final write fall back to the guidance read
    # at startup, so the record reverted to an older job that is not the one
    # this run tried and failed to start.
    _pc_fail "aid-job.sh run failed for ${epic_id} (rc=${rc}); ${epic_id} stays claimed and ready and NOTHING is running: ${out}"
    _pc_note "spawn_refused" "$epic_id" "reason=job_run_failed rc=${rc}"
    return 1
  fi

  _pc_say "spawn:   started ${job_id} for ${epic_id} (deadline ${deadline}s, ${_PC_SPAWN_COUNT}/${max} for this plan)"
  _pc_note "spawn_started" "$epic_id" "job_id=${job_id} n=${_PC_SPAWN_COUNT} max=${max} deadline=${deadline}"
  return 0
}

# ---------------------------------------------------------------------------
# _pc_reclaim <epic_id> — the deliberately manual door.
# ---------------------------------------------------------------------------
_pc_reclaim() {
  local epic_id="$1"
  local cur; cur="$(_pc_queue get "$epic_id" status)" || cur=""
  if [[ "$cur" != "running" ]]; then
    _pc_fail "--reclaim only releases an entry stuck at 'running'; ${epic_id} is '${cur:-<absent>}'. Nothing written."
    return 1
  fi
  local rc=0
  _pc_queue set-status "$epic_id" pending >/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _pc_fail "could not return ${epic_id} to pending (rc=${rc})."
    return "$rc"
  fi
  _pc_say "reclaim: ${epic_id} running -> pending; it can be claimed again."
  return 0
}

main() {
  local plan_id="" epic_id="" root_opt="" reclaim_id="" spawn_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) root_opt="${2:-}"; shift 2 ;;
      --reclaim)      reclaim_id="${2:-}"; shift 2 ;;
      # Step 6: an EXPLICIT override of autonomy.spawn_next_epic, in either
      # direction. The configuration decides by default, precisely because the
      # implicit call from `epic-merge-to-plan` passes no flags — a switch that
      # only a hand-typed command could set would never fire on the autonomous
      # path it exists for.
      --spawn)        spawn_opt="yes"; shift ;;
      --no-spawn)     spawn_opt="no";  shift ;;
      -h|--help)      _pc_usage; return 0 ;;
      -*)             _pc_usage >&2; _pc_fail "unknown option: $1"; return 2 ;;
      *)
        if   [[ -z "$plan_id" ]]; then plan_id="$1"
        elif [[ -z "$epic_id" ]]; then epic_id="$1"
        else _pc_fail "unexpected argument: $1"; return 2; fi
        shift ;;
    esac
  done

  ROOT="$(cd "${root_opt:-$PWD}" 2>/dev/null && pwd)" || ROOT="${root_opt:-$PWD}"
  export AID_QUEUE_WRITE_PROJECT_ROOT="$ROOT"

  if [[ -n "$reclaim_id" ]]; then
    if [[ -n "$plan_id" || -n "$epic_id" ]]; then
      _pc_fail "--reclaim takes no positional arguments."
      return 2
    fi
    if ! _queue_valid_id "$reclaim_id"; then
      _pc_fail "--reclaim: '${reclaim_id}' is not an epic id."
      return 2
    fi
    _pc_reclaim "$reclaim_id"
    return $?
  fi

  if [[ -z "$plan_id" || -z "$epic_id" ]]; then
    _pc_usage >&2
    return 2
  fi
  if [[ ! "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    _pc_fail "'${plan_id}' is not a plan id (expected P<NNN>)."
    return 2
  fi
  if ! _queue_valid_id "$epic_id"; then
    _pc_fail "'${epic_id}' is not an epic id."
    return 2
  fi
  PLAN_ID="$plan_id"
  FINISHED_EPIC="$epic_id"

  # ── the guidance, first: what the last run got to (Step 4) ──────────────
  # Read BEFORE anything is written, and used only to refuse an out-of-sequence
  # mirror. Everything else this run decides, it decides by asking the queue —
  # what is merged can have changed while the last turn was gone.
  local guide_next=""
  _pc_state_read
  if [[ -n "$_PC_GUIDE_JSON" ]]; then
    guide_next="$(jq -r '.next_epic // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)" || guide_next=""
    local guide_last guide_at
    guide_last="$(jq -r '.last_completed_epic // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    guide_at="$(jq -r '.at // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    _pc_say "guide:   last run finished ${guide_last:-<none>} and left ${guide_next:-<nothing>} in flight (${guide_at:-<no time>})"
  else
    _pc_say "$_PC_GUIDE_NOTE"
  fi
  if [[ -n "$guide_next" && "$guide_next" != "$epic_id" ]] \
     && ! _pc_is_merged "$guide_next"; then
    _pc_fail "the guidance says ${guide_next} was started and it is not in plan/${plan_id} yet, but this run was told ${epic_id} finished. Those two cannot both be true in a plan that runs one EPIC at a time. Nothing was mirrored — check which EPIC actually finished."
    return 1
  fi

  # ── 0. proof, and 1. mirror ─────────────────────────────────────────────
  # The status is read FIRST, because the proof exists to earn a write and an
  # entry that already says `merged_to_plan` has no write to earn. That order
  # also matters after a task branch is pruned: `_queue_resolve_dep_branch` can
  # no longer find a ref, so the proof would fail for ever on a plan that has
  # long since merged — while `epic-merge-to-plan` itself converges happily on
  # its recorded merge commit. Asking "is there anything to write" first keeps
  # the two commands agreeing about a finished EPIC.
  local cur; cur="$(_pc_queue get "$epic_id" status)" || cur=""
  cur="$(queue_status_normalize "$cur")"
  if [[ "$cur" == "merged_to_plan" ]]; then
    _pc_say "mirror:  ${epic_id} already merged_to_plan — skipped (nothing to write, so nothing to prove)"
  else
    if ! _pc_prove_merged "$plan_id" "$epic_id"; then
      _pc_state_write "unproven" "" || true
      return 1
    fi
    local mrc=0
    _pc_queue set-status "$epic_id" merged_to_plan >/dev/null || mrc=$?
    case "$mrc" in
      0) _pc_say "mirror:  ${epic_id} ${cur:-<absent>} -> merged_to_plan" ;;
      3) _pc_fail "the queue lock was unavailable while mirroring ${epic_id} — nothing written. Retry."
         _pc_state_write "mirror_lock_unavailable" "" || true
         return 3 ;;
      1) _pc_fail "the queue refuses to move ${epic_id} to merged_to_plan: it is at a terminal status while the plan branch says it merged. Queue and manifest disagree — a human decides which is wrong. Nothing was written and nothing else was attempted."
         _pc_state_write "mirror_refused_terminal" "" || true
         return 1 ;;
      *) _pc_fail "could not mirror ${epic_id} into the queue (rc=${mrc})."
         _pc_state_write "mirror_failed" "" || true
         return 1 ;;
    esac
  fi

  # An entry left at `running` by a dead process is named here — on every path
  # that gets PAST THE MIRROR, which is the honest scope: a run that stops at
  # link 0 or 1 has not established anything about this plan's state and says so
  # instead. (Codex review, EPIC 1: with the report tied to the `none`/`blocked:`
  # endings alone, a plan with one orphan and one ready EPIC started the ready
  # one and never mentioned the orphan.) After the mirror and before the claim,
  # so the entry this run is about to take is not in it — and after the mirror,
  # so the EPIC this run just finished is not either.
  _pc_report_stranded

  # ── 2. ask ──────────────────────────────────────────────────────────────
  local peeked prc=0
  peeked="$(bash "$PLAN_FSM" next-epic "$plan_id" --project-root "$ROOT")" || prc=$?
  case "$prc" in
    0) _pc_say "ask:     next is ${peeked}" ;;
    1)
      _pc_state_write "$peeked" "" || true
      if [[ "$peeked" == none ]]; then
        _pc_say "ask:     none — every EPIC of ${plan_id} is accounted for."
        _pc_say ""
        _pc_say "The plan is exhausted, but this script does not close plans. Closing is a"
        _pc_say "decision, and in this repository it is three commands:"
        _pc_say "  aid-plan-fsm.sh plan-finalize ${plan_id} --stage <sync|freeze|gates|inputs|review|c4|summary>"
        _pc_say "  aid-plan-fsm.sh plan-merge-to-main ${plan_id} --decision <path>"
        _pc_say "  aid-plan-fsm.sh plan-close ${plan_id}"
      else
        _pc_say "ask:     ${peeked}"
        _pc_say "Nothing is claimable yet and that is not an error — the reason above says"
        _pc_say "what is being waited on. The queue was not claimed."
      fi
      return 0
      ;;
    2) # Usage, or a plan this repository has never started. Permanent: a retry
       # changes nothing, and calling it transient would loop forever.
       _pc_fail "cannot ask what is next for ${plan_id}: next-epic rejected it (exit 2, reason above). The queue was NOT claimed."
       _pc_state_write "ask_rejected" "" || true
       return 1 ;;
    *) _pc_fail "could not ask what is next for ${plan_id} (next-epic exited ${prc}) — the queue was NOT claimed. Retry."
       _pc_state_write "ask_failed_rc${prc}" "" || true
       return 3 ;;
  esac

  # ── 3. claim ────────────────────────────────────────────────────────────
  local claimed crc=0
  claimed="$(_pc_queue claim-next "$plan_id")" || crc=$?
  case "$crc" in
    0) ;;
    1)
      # The queue moved between the ask and the claim. Not an error; the ask
      # was a question, not a reservation.
      _pc_say "claim:   ${claimed} — the queue changed between the question and the claim; nothing was started."
      _pc_note "queue_claim_raced" "" "peeked=${peeked} claimed=${claimed}"
      _pc_state_write "$claimed" "" || true
      return 0
      ;;
    *) _pc_fail "could not claim the next EPIC of ${plan_id} (rc=${crc}) — nothing was started. Retry."
       _pc_state_write "claim_failed_rc${crc}" "" || true
       return 3 ;;
  esac
  if [[ "$claimed" != "$peeked" ]]; then
    _pc_say "claim:   ${claimed} (the question had said ${peeked}; the claim wins)"
    _pc_note "queue_claim_raced" "$claimed" "peeked=${peeked} claimed=${claimed}"
  else
    _pc_say "claim:   ${claimed}"
  fi

  # ── 4. start ────────────────────────────────────────────────────────────
  local srrc=0
  bash "$PLAN_FSM" epic-start "$plan_id" "$claimed" --project-root "$ROOT" || srrc=$?
  if [[ "$srrc" -ne 0 ]]; then
    # The claim succeeded, so the entry is `running` with nothing running.
    # Reconcile it back to `pending` HERE — this is the one case where the
    # script may, because it is the process that made the claim moments ago and
    # therefore knows there is no live run behind it.
    local rrc=0
    _pc_queue set-status "$claimed" pending >/dev/null || rrc=$?
    if [[ "$rrc" -eq 0 ]]; then
      _pc_fail "epic-start failed for ${claimed} (rc=${srrc}); the claim was undone (back to pending) so the next attempt can take it."
      _pc_note "continue_start_failed" "$claimed" "epic-start rc=${srrc}; claim reverted to pending"
    else
      _pc_fail "epic-start failed for ${claimed} (rc=${srrc}) AND the claim could not be undone (rc=${rrc}) — the entry is left 'running' with nothing running. Release it with: aid-plan-continue.sh --reclaim ${claimed}"
      _pc_note "continue_start_failed" "$claimed" "epic-start rc=${srrc}; claim NOT reverted (rc=${rrc})"
    fi
    # The record exists even here — `next_epic` stays empty, because nothing was
    # started and a guidance that named it as in flight would be a lie.
    _pc_state_write "start_failed_rc${srrc}" "" || true
    # A lock epic-start could not take is TRANSIENT, and the caller's own table
    # says exit 3 means "retry later". Flattening it to 1 (Codex review, EPIC 1)
    # told an automated caller a retryable condition was permanent.
    [[ "$srrc" -eq 3 ]] && return 3
    return 1
  fi

  _pc_say "start:   ${claimed} is registered and ready to run."
  _pc_note "continue_advanced" "$claimed" "after=${epic_id}"

  # ── 5. spawn (Step 6, off by default) ───────────────────────────────────
  local sprc=0
  _pc_spawn "$plan_id" "$claimed" "$spawn_opt" || sprc=$?

  # The guidance is written LAST, and after the spawn, so it carries the job id
  # there is no other way to recover. Written after the start, never before — a
  # guidance naming an EPIC that was never started is worse than none.
  _pc_state_write "$claimed" "$claimed" || true

  if [[ "$sprc" -ne 0 ]]; then
    # The plan DID advance: the entry is claimed, the branch exists. Only the
    # session did not start, and saying so with its own code keeps a caller from
    # reading "the plan is stuck" or "something is running" — neither is true.
    return 4
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
