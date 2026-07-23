#!/usr/bin/env bash
# =============================================================================
# aid-job.sh — Controller-owned background job supervisor (IMP-262)
#
# A small, standalone helper that gives a long-running command a DURABLE
# IDENTITY and a TERMINAL RESULT that a resumed AUTO controller can collect
# without relying on `tail -f`, an agent notification, or the original shell
# staying alive.
#
# Subcommands:
#   run       Start a command in its own session/process-group; write a durable
#             job record; return immediately with the job id.
#   status    Report state from the OWNED PROCESS + terminal result only.
#             PID-reuse-safe. `tail -f`/log growth are never liveness signals.
#   collect   Idempotently return the terminal result. Never relaunches.
#             `--require-current` marks a result stale if the tree moved.
#   cancel    Signal the recorded PROCESS GROUP (no orphaned child) and ensure
#             a terminal cancellation result is written.
#   watchdog  Queryable AUTO-liveness check: no live owned job + no progress for
#             the interval => `resume_needed` (not a daemon).
#   redgreen  Validate a paired baseline(fail)/fixed(pass) receipt set.
#   __wrap    INTERNAL — the supervised wrapper process. Not a public command.
#
# Design invariants:
#   - Completion is read from the owned process + its exit status, NEVER from
#     log growth, a `tail -f`, or a notification.
#   - PID reuse is defeated by recording /proc/<pid>/stat starttime (kernel
#     authoritative) plus a child-written cookie; a reused PID has a different
#     starttime and is treated as gone.
#   - job.json is written before exec (temp+mv); result.json is written
#     atomically on exit (temp+mv). `collect` is idempotent.
#   - A result is bound to its start HEAD + tree hash; a moved tree is `stale`.
#   - Nothing here is a hard FSM/gate precondition. Opt-in at the controller
#     boundary only — must never become a release-blocking ceremony.
#
# Exit codes:
#   0  success / terminal_pass / accepted / queryable-ok
#   1  usage / validation error, or terminal non-pass (collect)
#   2  I/O or environment error (missing record, missing tool)
#   3  not terminal yet (collect on a started/running/lost job — no evidence)
#   4  stale (collect --require-current on a moved tree)
#   5  redgreen pair rejected
#
# Requirements: bash 4+, jq, sha256sum, setsid (util-linux), Linux /proc.
# =============================================================================
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
readonly JOB_ID_RE='^[A-Za-z0-9._-]{1,128}$'
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly SELF

# Encode a bash argv array as a JSON string array, one jq --arg per element.
# Avoids jq --args (mis-parses leading-dash args) and NUL splitting (jq 1.6
# truncates raw input at the first NUL). Safe for spaces, quotes, dashes.
_argv_to_json() {
  local acc='[]' a
  for a in "$@"; do
    acc="$(jq -c --arg a "$a" '. + [$a]' <<<"$acc")"
  done
  printf '%s' "$acc"
}

# ── Small utilities ──────────────────────────────────────────────────────────
_die() { printf 'aid-job: %s\n' "$1" >&2; exit "${2:-1}"; }

_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_epoch_now() { date -u +%s; }

# Validate a job id BEFORE it becomes a filesystem path or a jq value.
_validate_job_id() {
  local id="$1"
  [[ "$id" =~ $JOB_ID_RE ]] || _die "invalid job id (charset [A-Za-z0-9._-], <=128): '$id'" 1
  [[ "$id" == *".."* ]] && _die "invalid job id (path traversal): '$id'" 1
  return 0
}

# Kernel-authoritative process-start identity: field 22 of /proc/<pid>/stat.
# Robust against a comm field containing spaces/parens: strip through the last ')'.
_proc_starttime() {
  local pid="$1" stat rest
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo ""; return 0; }
  [[ -r "/proc/$pid/stat" ]] || { echo ""; return 0; }
  stat="$(cat "/proc/$pid/stat" 2>/dev/null || true)"
  [[ -n "$stat" ]] || { echo ""; return 0; }
  rest="${stat##*) }"                # drop through the LAST ") " (comm may contain ")")
  # rest now starts at field 3 (state). starttime is field 22 => index 19 here.
  # shellcheck disable=SC2206
  local f=($rest)
  echo "${f[19]:-}"
}

# Liveness: PID present AND recorded starttime still matches (defeats PID reuse).
# Returns 0 (alive) / 1 (gone or reused).
_proc_alive() {
  local pid="$1" want="$2" have
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ -d "/proc/$pid" ]] || return 1
  have="$(_proc_starttime "$pid")"
  [[ -n "$want" && "$have" == "$want" ]]
}

# Revision fingerprint: HEAD sha + a hash covering staged+unstaged tree state.
# A tree move (HEAD change OR working-tree edit) changes the second field.
_job_revision() {
  local repo="$1" head tree
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo none)"
    # Exclude the AID workspace (.aid-o/) so the supervisor writing its OWN job
    # records is never mistaken for source-tree drift. `git diff HEAD` covers
    # tracked files only; untracked .aid-o/ appears only in --porcelain.
    # Exclude .aid-o/ via a git PATHSPEC, not a substring grep (review LOW): a
    # substring filter would also drop an unrelated drifted path that merely
    # contains ".aid-o/", hiding real drift. `:(exclude)` is anchored by git.
    tree="$( { git -C "$repo" diff HEAD -- . ':(exclude).aid-o/**' 2>/dev/null || true; \
               git -C "$repo" status --porcelain -- . ':(exclude).aid-o/**' 2>/dev/null || true; } \
             | sha256sum | cut -d' ' -f1 )"
    printf '%s %s' "$head" "$tree"
  else
    printf 'nogit nogit'
  fi
}

_sha256_file() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Atomic JSON write (temp in same dir + mv).
_atomic_write() {
  local dest="$1" content="$2" tmp
  tmp="$(mktemp "${dest}.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv -f "$tmp" "$dest"
}

_need() { command -v "$1" >/dev/null 2>&1 || _die "required tool not found: $1" 2; }

# ── run ──────────────────────────────────────────────────────────────────────
cmd_run() {
  local jobs_dir="" job_id="" label="" owner="" repo=""
  local expect_p95=0 deadline=0
  local polarity="" expect="" filter=""
  local -a command=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --id) job_id="$2"; shift 2;;
      --label) label="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      --repo) repo="$2"; shift 2;;
      --expect-p95) expect_p95="$2"; shift 2;;
      --deadline) deadline="$2"; shift 2;;
      --polarity) polarity="$2"; shift 2;;
      --expect) expect="$2"; shift 2;;
      --filter) filter="$2"; shift 2;;
      --) shift; command=("$@"); break;;
      *) _die "run: unknown arg '$1'" 1;;
    esac
  done

  [[ -n "$jobs_dir" ]] || _die "run: --jobs-dir required" 1
  [[ ${#command[@]} -gt 0 ]] || _die "run: command required after --" 1
  [[ "$expect_p95" =~ ^[0-9]+$ ]] || _die "run: --expect-p95 must be integer seconds" 1
  [[ "$deadline" =~ ^[0-9]+$ ]] || _die "run: --deadline must be integer seconds" 1
  if [[ -n "$polarity" ]]; then
    [[ "$polarity" == baseline || "$polarity" == fixed ]] || _die "run: --polarity must be baseline|fixed" 1
  fi
  if [[ -n "$expect" ]]; then
    [[ "$expect" == pass || "$expect" == fail ]] || _die "run: --expect must be pass|fail" 1
  fi
  _need jq; _need sha256sum; _need setsid

  [[ -n "$repo" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if [[ -z "$job_id" ]]; then
    job_id="job-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
  fi
  _validate_job_id "$job_id"

  local job_dir="$jobs_dir/$job_id"
  [[ -e "$job_dir" ]] && _die "run: job id already exists: $job_id" 1
  mkdir -p "$job_dir"

  # Command fingerprint: sha256 over NUL-joined argv (never re-executed from record).
  local fingerprint cmd_json
  fingerprint="$(printf '%s\0' "${command[@]}" | sha256sum | cut -d' ' -f1)"
  cmd_json="$(_argv_to_json "${command[@]}")"

  local rev head_sha tree_hash
  rev="$(_job_revision "$repo")"
  head_sha="${rev%% *}"; tree_hash="${rev##* }"

  local now_iso now_epoch
  now_iso="$(_iso_now)"; now_epoch="$(_epoch_now)"

  # Initial durable record — written BEFORE exec. state=started, pid unknown yet.
  local job_json
  job_json="$(jq -nc \
    --arg id "$job_id" \
    --arg lbl "$label" \
    --arg owner "$owner" \
    --arg repo "$repo" \
    --arg state "started" \
    --arg fp "$fingerprint" \
    --arg head "$head_sha" \
    --arg tree "$tree_hash" \
    --arg started_at "$now_iso" \
    --argjson started_epoch "$now_epoch" \
    --argjson p95 "$expect_p95" \
    --argjson deadline "$deadline" \
    --arg polarity "$polarity" \
    --arg expect "$expect" \
    --arg filter "$filter" \
    --arg stdout "$job_dir/stdout.log" \
    --arg result "$job_dir/result.json" \
    --argjson cmdarr "$cmd_json" \
    '{schema:"aid-job/1", id:$id, label:$lbl, owner:$owner, repo:$repo,
      state:$state, command_fingerprint:$fp,
      start_head:$head, start_tree:$tree,
      started_at:$started_at, started_epoch:$started_epoch,
      expected_p95_sec:$p95, deadline_sec:$deadline,
      polarity:$polarity, expect:$expect, filter:$filter,
      stdout_path:$stdout, result_path:$result,
      pid:null, pgid:null, proc_starttime:null, cookie:null,
      command:$cmdarr}')"
  _atomic_write "$job_dir/job.json" "$job_json"

  # Launch the supervised wrapper in its own session (setsid => new PGID),
  # fully detached from this shell so it survives controller replacement.
  setsid bash "$SELF" __wrap "$job_dir" </dev/null >>"$job_dir/wrapper.log" 2>&1 &
  disown 2>/dev/null || true

  # Best-effort: wait briefly for the wrapper to record its running identity,
  # so callers get a live pid. Not required for correctness (status re-derives).
  local i
  for i in $(seq 1 30); do
    if [[ -f "$job_dir/result.json" ]]; then break; fi
    if jq -e '.pid != null' "$job_dir/job.json" >/dev/null 2>&1; then break; fi
    sleep 0.1
  done

  echo "$job_id"
}

# ── __wrap (internal supervised process) ─────────────────────────────────────
cmd_wrap() {
  local job_dir="${1:?__wrap requires job_dir}"
  [[ -f "$job_dir/job.json" ]] || _die "__wrap: missing job.json in $job_dir" 2

  local repo deadline fingerprint start_head start_tree polarity expect filter
  repo="$(jq -r '.repo' "$job_dir/job.json")"
  deadline="$(jq -r '.deadline_sec' "$job_dir/job.json")"
  fingerprint="$(jq -r '.command_fingerprint' "$job_dir/job.json")"
  start_head="$(jq -r '.start_head' "$job_dir/job.json")"
  start_tree="$(jq -r '.start_tree' "$job_dir/job.json")"
  polarity="$(jq -r '.polarity' "$job_dir/job.json")"
  expect="$(jq -r '.expect' "$job_dir/job.json")"
  filter="$(jq -r '.filter' "$job_dir/job.json")"

  # Reconstruct the command array from the record.
  local -a command=()
  mapfile -t command < <(jq -r '.command[]' "$job_dir/job.json")

  # Record running identity: our own pid, pgid, starttime, and a cookie.
  local mypid mypgid mystart cookie
  mypid=$$
  mypgid="$(ps -o pgid= -p "$mypid" 2>/dev/null | tr -d ' ' || echo "$mypid")"
  mystart="$(_proc_starttime "$mypid")"
  cookie="$(date -u +%s%N)-${RANDOM}"

  local updated
  updated="$(jq -c \
    --arg state "running" \
    --argjson pid "$mypid" \
    --argjson pgid "${mypgid:-0}" \
    --arg starttime "$mystart" \
    --arg cookie "$cookie" \
    '.state=$state | .pid=$pid | .pgid=$pgid | .proc_starttime=$starttime | .cookie=$cookie' \
    "$job_dir/job.json")"
  _atomic_write "$job_dir/job.json" "$updated"

  # Run the command in the background so this wrapper can wait + trap signals.
  local _cancelled=0 cmd_pid rc=0
  # shellcheck disable=SC2317
  _on_term() { _cancelled=1; kill -KILL "${cmd_pid:-0}" 2>/dev/null || true; }
  trap _on_term TERM INT

  ( exec "${command[@]}" ) >"$job_dir/stdout.log" 2>&1 &
  cmd_pid=$!

  # Hard-deadline timer (kills only the command; marker disambiguates).
  local timer_pid=""
  if [[ "$deadline" =~ ^[0-9]+$ && "$deadline" -gt 0 ]]; then
    ( sleep "$deadline"; : > "$job_dir/.deadline_hit"; kill -TERM "$cmd_pid" 2>/dev/null || true
      sleep 2; kill -KILL "$cmd_pid" 2>/dev/null || true ) &
    timer_pid=$!
  fi

  if wait "$cmd_pid"; then rc=0; else rc=$?; fi
  [[ -n "$timer_pid" ]] && kill "$timer_pid" 2>/dev/null || true

  local end_iso end_epoch stdout_sha end_rev end_head end_tree state
  end_iso="$(_iso_now)"; end_epoch="$(_epoch_now)"
  stdout_sha="$(_sha256_file "$job_dir/stdout.log")"
  end_rev="$(_job_revision "$repo")"; end_head="${end_rev%% *}"; end_tree="${end_rev##* }"

  if [[ -f "$job_dir/.deadline_hit" ]]; then
    state="timed_out"
  elif [[ "$_cancelled" -eq 1 ]]; then
    state="cancelled"
  elif [[ "$rc" -eq 0 ]]; then
    state="terminal_pass"
  else
    state="terminal_fail"
  fi

  # Observed polarity for red-green receipts.
  local observed=""
  [[ -n "$polarity" ]] && { [[ "$rc" -eq 0 ]] && observed="pass" || observed="fail"; }
  local expect_match="null"
  if [[ -n "$expect" ]]; then
    [[ "$observed" == "$expect" ]] && expect_match="true" || expect_match="false"
  fi

  local result
  result="$(jq -nc \
    --arg id "$(jq -r '.id' "$job_dir/job.json")" \
    --arg state "$state" \
    --argjson exit_code "$rc" \
    --arg fp "$fingerprint" \
    --arg start_head "$start_head" \
    --arg start_tree "$start_tree" \
    --arg end_head "$end_head" \
    --arg end_tree "$end_tree" \
    --arg started_at "$(jq -r '.started_at' "$job_dir/job.json")" \
    --arg ended_at "$end_iso" \
    --argjson ended_epoch "$end_epoch" \
    --arg stdout_sha "$stdout_sha" \
    --arg cookie "$cookie" \
    --arg polarity "$polarity" \
    --arg expect "$expect" \
    --arg observed "$observed" \
    --argjson expect_match "$expect_match" \
    --arg filter "$filter" \
    '{schema:"aid-job-result/1", id:$id, state:$state, exit_code:$exit_code,
      command_fingerprint:$fp,
      start_head:$start_head, start_tree:$start_tree,
      end_head:$end_head, end_tree:$end_tree,
      started_at:$started_at, ended_at:$ended_at, ended_epoch:$ended_epoch,
      stdout_sha256:$stdout_sha, cookie:$cookie,
      polarity:$polarity, expect:$expect, observed_polarity:$observed,
      expect_match:$expect_match, filter:$filter}')"
  _atomic_write "$job_dir/result.json" "$result"

  # Also reflect terminal state into job.json (best-effort; result.json is SSOT).
  local jj
  jj="$(jq -c --arg s "$state" '.state=$s' "$job_dir/job.json" 2>/dev/null || true)"
  [[ -n "$jj" ]] && _atomic_write "$job_dir/job.json" "$jj"

  # Reap any survivors (grandchildren / a command ignoring TERM). result.json is
  # already durable, so a group SIGKILL that also ends this wrapper is safe.
  if [[ "$state" == "cancelled" || "$state" == "timed_out" ]]; then
    kill -KILL -"${mypgid:-0}" 2>/dev/null || true
  fi
  exit 0
}

# ── shared: resolve a job dir + read live (non-terminal) state ────────────────
_resolve_job_dir() {
  local jobs_dir="$1" job_id="$2"
  _validate_job_id "$job_id"
  local d="$jobs_dir/$job_id"
  [[ -d "$d" && -f "$d/job.json" ]] || _die "no such job: $job_id (under $jobs_dir)" 2
  echo "$d"
}

# Echo the current state string derived from OWNED PROCESS + terminal result.
# Never consults log growth or a tail process.
_derive_state() {
  local job_dir="$1"
  if [[ -f "$job_dir/result.json" ]]; then
    jq -r '.state' "$job_dir/result.json"
    return 0
  fi
  local pid starttime recorded
  pid="$(jq -r '.pid // empty' "$job_dir/job.json")"
  starttime="$(jq -r '.proc_starttime // empty' "$job_dir/job.json")"
  recorded="$(jq -r '.state' "$job_dir/job.json")"
  if [[ -z "$pid" ]]; then
    # No pid recorded yet: either just-started, or the wrapper never came up.
    echo "$recorded"       # "started"
    return 0
  fi
  if _proc_alive "$pid" "$starttime"; then
    echo "running"
  else
    echo "lost"            # owned process gone AND no terminal record
  fi
}

# ── status ───────────────────────────────────────────────────────────────────
cmd_status() {
  local jobs_dir="" job_id="" as_json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --id) job_id="$2"; shift 2;;
      --json) as_json=1; shift;;
      *) _die "status: unknown arg '$1'" 1;;
    esac
  done
  [[ -n "$jobs_dir" && -n "$job_id" ]] || _die "status: --jobs-dir and --id required" 1
  _need jq
  local job_dir state; job_dir="$(_resolve_job_dir "$jobs_dir" "$job_id")"
  state="$(_derive_state "$job_dir")"
  if [[ "$as_json" -eq 1 ]]; then
    if [[ -f "$job_dir/result.json" ]]; then
      jq -c --arg s "$state" '. + {reported_state:$s}' "$job_dir/result.json"
    else
      jq -c --arg s "$state" '{id:.id, reported_state:$s, pid:.pid, proc_starttime:.proc_starttime, start_head:.start_head, start_tree:.start_tree}' "$job_dir/job.json"
    fi
  else
    echo "$state"
  fi
}

# ── collect ──────────────────────────────────────────────────────────────────
cmd_collect() {
  local jobs_dir="" job_id="" require_current=0 repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --id) job_id="$2"; shift 2;;
      --repo) repo="$2"; shift 2;;
      --require-current) require_current=1; shift;;
      *) _die "collect: unknown arg '$1'" 1;;
    esac
  done
  [[ -n "$jobs_dir" && -n "$job_id" ]] || _die "collect: --jobs-dir and --id required" 1
  _need jq
  local job_dir; job_dir="$(_resolve_job_dir "$jobs_dir" "$job_id")"

  if [[ ! -f "$job_dir/result.json" ]]; then
    # Not terminal — a started/running/lost job PROVES NO OUTCOME.
    local live; live="$(_derive_state "$job_dir")"
    local reported="in_flight"
    [[ "$live" == "lost" ]] && reported="lost"
    jq -nc --arg id "$job_id" --arg s "$reported" --arg live "$live" \
      '{id:$id, state:$s, live_state:$live, terminal:false, note:"no terminal result — a started/in-flight job is not evidence"}'
    exit 3
  fi

  # Terminal record exists. Optionally enforce revision binding.
  if [[ "$require_current" -eq 1 ]]; then
    [[ -n "$repo" ]] || repo="$(jq -r '.repo // empty' "$job_dir/job.json")"
    [[ -n "$repo" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    local cur cur_head cur_tree rec_head rec_tree
    cur="$(_job_revision "$repo")"; cur_head="${cur%% *}"; cur_tree="${cur##* }"
    rec_head="$(jq -r '.start_head' "$job_dir/result.json")"
    rec_tree="$(jq -r '.start_tree' "$job_dir/result.json")"
    if [[ "$cur_head" != "$rec_head" || "$cur_tree" != "$rec_tree" ]]; then
      jq -c '. + {stale:true, note:"tree moved since result was produced — result is stale, not current evidence"}' "$job_dir/result.json"
      exit 4
    fi
  fi

  # Idempotent: same terminal record on every call.
  cat "$job_dir/result.json"
  local st; st="$(jq -r '.state' "$job_dir/result.json")"
  [[ "$st" == "terminal_pass" ]] && exit 0 || exit 1
}

# ── cancel ───────────────────────────────────────────────────────────────────
cmd_cancel() {
  local jobs_dir="" job_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --id) job_id="$2"; shift 2;;
      *) _die "cancel: unknown arg '$1'" 1;;
    esac
  done
  [[ -n "$jobs_dir" && -n "$job_id" ]] || _die "cancel: --jobs-dir and --id required" 1
  _need jq
  local job_dir; job_dir="$(_resolve_job_dir "$jobs_dir" "$job_id")"

  # Idempotent: already terminal → return that state, do nothing.
  if [[ -f "$job_dir/result.json" ]]; then
    jq -r '.state' "$job_dir/result.json"; exit 0
  fi

  local pid pgid starttime
  pid="$(jq -r '.pid // empty' "$job_dir/job.json")"
  pgid="$(jq -r '.pgid // empty' "$job_dir/job.json")"
  starttime="$(jq -r '.proc_starttime // empty' "$job_dir/job.json")"

  # Review MEDIUM (sharpest weapon): reject pgid 0 (kill -0 targets the CALLER's
  # own group) and 1 (broadcast), and require the recorded pgid to still be the
  # live pid's ACTUAL process group — a corrupted/forged job.json cannot redirect
  # the signal at another group. setsid guarantees pgid==pid>1 for a real job.
  local _live_pgid=""
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && _live_pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [[ "$pgid" =~ ^[1-9][0-9]*$ && "$pgid" -gt 1 ]] \
     && _proc_alive "$pid" "$starttime" \
     && [[ "$pgid" == "$_live_pgid" ]]; then
    # Signal the whole recorded PROCESS GROUP — no child is left unowned. The
    # wrapper traps TERM and writes a terminal cancellation result.
    kill -TERM -"$pgid" 2>/dev/null || true
    local i
    for i in $(seq 1 50); do
      [[ -f "$job_dir/result.json" ]] && break
      sleep 0.1
    done
  fi

  if [[ -f "$job_dir/result.json" ]]; then
    jq -r '.state' "$job_dir/result.json"; exit 0
  fi

  # Fallback: wrapper already gone without a record (e.g. crash) — write a
  # terminal cancellation result ourselves so the job never dangles.
  local now_iso; now_iso="$(_iso_now)"
  local result
  result="$(jq -nc \
    --arg id "$job_id" \
    --arg started_at "$(jq -r '.started_at' "$job_dir/job.json")" \
    --arg ended_at "$now_iso" \
    --arg fp "$(jq -r '.command_fingerprint' "$job_dir/job.json")" \
    --arg sh "$(jq -r '.start_head' "$job_dir/job.json")" \
    --arg st "$(jq -r '.start_tree' "$job_dir/job.json")" \
    '{schema:"aid-job-result/1", id:$id, state:"cancelled", exit_code:143,
      command_fingerprint:$fp, start_head:$sh, start_tree:$st,
      end_head:$sh, end_tree:$st, started_at:$started_at, ended_at:$ended_at,
      stdout_sha256:null, cookie:null, note:"cancellation recorded by supervisor fallback (wrapper absent)"}')"
  _atomic_write "$job_dir/result.json" "$result"
  echo "cancelled"
  exit 0
}

# ── watchdog ─────────────────────────────────────────────────────────────────
# Queryable AUTO-liveness check (NOT a daemon). No live owned job + no progress
# for --interval seconds => resume_needed.
cmd_watchdog() {
  local jobs_dir="" interval=300 now="" last_progress=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --interval) interval="$2"; shift 2;;
      --now) now="$2"; shift 2;;
      --last-progress) last_progress="$2"; shift 2;;
      *) _die "watchdog: unknown arg '$1'" 1;;
    esac
  done
  [[ -n "$jobs_dir" ]] || _die "watchdog: --jobs-dir required" 1
  [[ "$interval" =~ ^[0-9]+$ ]] || _die "watchdog: --interval must be integer seconds" 1
  _need jq
  [[ -n "$now" ]] || now="$(_epoch_now)"

  # Is any owned job still live? (owned process alive AND no terminal result)
  local live_jobs=0 d
  if [[ -d "$jobs_dir" ]]; then
    for d in "$jobs_dir"/*/; do
      [[ -f "$d/job.json" ]] || continue
      [[ -f "$d/result.json" ]] && continue
      local pid starttime
      pid="$(jq -r '.pid // empty' "$d/job.json")"
      starttime="$(jq -r '.proc_starttime // empty' "$d/job.json")"
      if _proc_alive "$pid" "$starttime"; then
        live_jobs=$((live_jobs + 1))
      fi
    done
  fi

  if [[ "$live_jobs" -gt 0 ]]; then
    jq -nc --argjson n "$live_jobs" '{state:"busy", live_jobs:$n, note:"an owned job is still live"}'
    exit 0
  fi

  # No live owned job. If no progress for >= interval => resume_needed.
  if [[ -n "$last_progress" && "$last_progress" =~ ^[0-9]+$ ]]; then
    local idle=$(( now - last_progress ))
    if [[ "$idle" -ge "$interval" ]]; then
      jq -nc --argjson idle "$idle" --argjson iv "$interval" \
        '{state:"resume_needed", idle_sec:$idle, interval_sec:$iv, live_jobs:0, note:"no live owned job and no progress within interval — resume/diagnose, do not idle"}'
      exit 0
    fi
    jq -nc --argjson idle "$idle" --argjson iv "$interval" \
      '{state:"idle_ok", idle_sec:$idle, interval_sec:$iv, live_jobs:0}'
    exit 0
  fi

  jq -nc '{state:"idle_ok", live_jobs:0, note:"no live owned job; supply --last-progress to evaluate the no-progress interval"}'
  exit 0
}

# ── redgreen ─────────────────────────────────────────────────────────────────
# Validate a paired baseline(expect fail) + fixed(expect pass) receipt set.
# Accepts only when BOTH are terminal, each observed polarity matches its
# expectation, the command fingerprint + filter match, and the revision moved.
cmd_redgreen() {
  local jobs_dir="" baseline="" fixed=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs-dir) jobs_dir="$2"; shift 2;;
      --baseline) baseline="$2"; shift 2;;
      --fixed) fixed="$2"; shift 2;;
      *) _die "redgreen: unknown arg '$1'" 1;;
    esac
  done
  [[ -n "$jobs_dir" && -n "$baseline" && -n "$fixed" ]] || _die "redgreen: --jobs-dir --baseline --fixed required" 1
  _need jq
  local bdir fdir; bdir="$(_resolve_job_dir "$jobs_dir" "$baseline")"; fdir="$(_resolve_job_dir "$jobs_dir" "$fixed")"

  local -a reasons=()
  [[ -f "$bdir/result.json" ]] || reasons+=("baseline_not_terminal")
  [[ -f "$fdir/result.json" ]] || reasons+=("fixed_not_terminal")
  if [[ ${#reasons[@]} -eq 0 ]]; then
    local b_exp b_obs b_fp b_filter b_head
    local f_exp f_obs f_fp f_filter f_head
    b_exp="$(jq -r '.expect' "$bdir/result.json")"
    b_obs="$(jq -r '.observed_polarity' "$bdir/result.json")"; b_fp="$(jq -r '.command_fingerprint' "$bdir/result.json")"
    b_filter="$(jq -r '.filter' "$bdir/result.json")"; b_head="$(jq -r '.start_head' "$bdir/result.json")"
    f_exp="$(jq -r '.expect' "$fdir/result.json")"
    f_obs="$(jq -r '.observed_polarity' "$fdir/result.json")"; f_fp="$(jq -r '.command_fingerprint' "$fdir/result.json")"
    f_filter="$(jq -r '.filter' "$fdir/result.json")"; f_head="$(jq -r '.start_head' "$fdir/result.json")"
    local b_exit f_exit
    b_exit="$(jq -r '.exit_code' "$bdir/result.json")"; f_exit="$(jq -r '.exit_code' "$fdir/result.json")"

    [[ "$b_exp" == "fail" ]] || reasons+=("baseline_expect_not_fail")
    [[ "$b_obs" == "fail" ]] || reasons+=("baseline_observed_not_fail")
    [[ "$f_exp" == "pass" ]] || reasons+=("fixed_expect_not_pass")
    [[ "$f_obs" == "pass" ]] || reasons+=("fixed_observed_not_pass")
    [[ "$b_fp" == "$f_fp" ]] || reasons+=("command_fingerprint_mismatch")
    [[ "$b_filter" == "$f_filter" ]] || reasons+=("filter_mismatch")
    [[ "$b_head" != "$f_head" ]] || reasons+=("same_revision_no_change_proven")
    # Review MEDIUM: HEAD moving is not proof the CODE changed — an empty commit
    # (new HEAD, identical tree) plus a flaky command would otherwise read as a
    # red->green. Compare the COMMITTED TREE OBJECTS of the two revisions, not
    # start_tree (which is a dirty-diff hash and is identical for two clean
    # checkouts). Read repo from job.json (beside result.json). If the objects
    # resolve and are equal -> reject; if git/repo is unavailable, fall back to
    # the HEAD check above rather than a false accept.
    local _rp b_oid="" f_oid=""
    _rp="$(jq -r '.repo // empty' "$bdir/job.json" 2>/dev/null)"
    if [[ -n "$_rp" ]] && git -C "$_rp" rev-parse --git-dir >/dev/null 2>&1; then
      b_oid="$(git -C "$_rp" rev-parse "${b_head}^{tree}" 2>/dev/null || echo b)"
      f_oid="$(git -C "$_rp" rev-parse "${f_head}^{tree}" 2>/dev/null || echo f)"
      [[ "$b_oid" != "$f_oid" ]] || reasons+=("same_tree_no_change_proven")
    fi
    # Cross-check the recorded exit code against the observed polarity so a
    # receipt cannot claim a polarity its own exit code contradicts.
    [[ "$b_exit" =~ ^[0-9]+$ && "$b_exit" -ne 0 ]] || reasons+=("baseline_exit_not_failing")
    [[ "$f_exit" == "0" ]] || reasons+=("fixed_exit_not_passing")
  fi

  if [[ ${#reasons[@]} -eq 0 ]]; then
    jq -nc --arg b "$baseline" --arg f "$fixed" \
      '{verdict:"accepted", baseline:$b, fixed:$f, note:"paired red-green receipts: baseline fails, fixed passes, same command at different revisions"}'
    exit 0
  fi
  local rj; rj="$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -sc .)"
  jq -nc --arg b "$baseline" --arg f "$fixed" --argjson r "$rj" \
    '{verdict:"rejected", baseline:$b, fixed:$f, reasons:$r}'
  exit 5
}

# ── dispatch ─────────────────────────────────────────────────────────────────
main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    run)      cmd_run "$@";;
    status)   cmd_status "$@";;
    collect)  cmd_collect "$@";;
    cancel)   cmd_cancel "$@";;
    watchdog) cmd_watchdog "$@";;
    redgreen) cmd_redgreen "$@";;
    __wrap)   cmd_wrap "$@";;
    ""|-h|--help|help)
      sed -n '3,45p' "$SELF" | sed 's/^# \{0,1\}//'
      exit 0;;
    *) _die "unknown subcommand: $sub (run|status|collect|cancel|watchdog|redgreen)" 1;;
  esac
}
main "$@"
