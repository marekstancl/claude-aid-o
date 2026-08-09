#!/usr/bin/env bash
# =============================================================================
# aid-service.sh — READINESS OVER OWNED JOBS (P076 Step 9)
#
# Brings the OPTIONAL `services:` declarations of a project's execution.yaml up
# and down. It starts nothing itself: every long-lived process is started,
# supervised, deadlined and killed by `aid-job.sh`, the ONE process owner in
# this system. There is deliberately no `setsid` here, no process-group
# arithmetic and no `kill` of a service process — the service's JOB is the
# ownership record, and this file is the thing that decides when that job is
# READY, not the thing that owns it.
#
# Provides (sourced, never executed):
#   aid_service_up_all    <run_evidence_dir> [<execution_yaml>]
#   aid_service_down_all  <run_evidence_dir> [<execution_yaml>]
#   aid_service_status    <name> [<run_evidence_dir>] [<execution_yaml>]
#
# ── THE REGISTRY ────────────────────────────────────────────────────────────
# `<run_evidence_dir>/services.json` is the run's per-service record and the
# SOLE source of the allocated port for every later reader (stop, probe,
# restart, status). It lives in the RUN'S EVIDENCE, not in the worktree,
# because the state root is deliberately shared between concurrent runs: two
# runs of the same project must not see one another's ports.
#
# It is written EAGERLY and in TWO PHASES, and that is the whole point of the
# design rather than an implementation detail:
#
#   phase 1  {service, run_id, port, state:"starting", job_id:null}  is written
#            BEFORE aid-job.sh is asked to spawn anything.
#   phase 2  the same entry is rewritten with the real `job_id` IMMEDIATELY
#            after the spawn returns.
#   phase 3  the entry flips to `healthy` once the probe agrees.
#
# So there is no window in which a spawned service job has no registry entry —
# only windows in which the entry is one field less precise. A death anywhere
# in the sequence leaves something every teardown path can see. Belt and
# braces, `aid_service_down_all` ALSO sweeps the supervisor's documented
# one-job-one-directory layout (`service-jobs/<name>/<job-id>/job.json`) and
# cancels any still-live job the registry does not name.
#
# A registry write failure FAILS THE UP. A service without its record is a
# service the run cannot stop, and an unstoppable process is the exact failure
# this file exists to prevent. Locking is `flock` on a lock file beside the
# registry plus atomic tmp+mv in the registry's own directory, and a registry
# that is not a registry is REFUSED, never clobbered.
#
# ── WHAT THE REGISTRY IS AUTHORITATIVE FOR (the trust model) ────────────────
# The registry was made self-sufficient on purpose, so that a teardown in a
# process which never saw the startup still works even if the config has moved.
# That property is worth keeping. But "the registry records what this run
# allocated" and "the registry decides what command runs, and against which
# directory" are different claims, and only the first one is granted:
#
#   ALLOCATED FACTS — port, job_id, jobs_dir, counters. The registry is the SOLE
#   source, and every one of them is REVALIDATED on read rather than trusted:
#   a port must be an integer in range, a service name must be the same
#   `^[a-z0-9][a-z0-9_-]*$` the declaration validator enforces, and — the one
#   that crosses a trust boundary — a recorded `jobs_dir` MUST resolve inside
#   the evidence directory it was loaded from. A value that does not is refused
#   and the canonical `<evidence>/service-jobs/<name>` is used instead, so a
#   registry can never aim `aid-job.sh cancel` at another run's job whatever it
#   says. Fails CLOSED, always.
#
#   COMMANDS — stop_cmd, probe_cmd. The DECLARATION is authoritative whenever
#   one can be read, and "readable" is decided per FILE, not per service:
#     • the config declares the service → the DECLARED command runs, divergence
#       from the recorded copy logged;
#     • the config is READABLE and does not declare the service → the recorded
#       command is REFUSED and nothing is executed for it. A readable config is
#       an authority saying this service does not exist, so the registry cannot
#       introduce one. The entry's JOB is still cancelled by id — that is what
#       actually kills the process — so the refusal costs the courtesy command
#       and never leaves a live job running;
#     • no config readable at all (it moved, or the caller passed none) → the
#       recorded copy runs, logged as UNRECONCILED.
#
#   THE HONEST LIMIT, named rather than implied: in that last case the registry
#   is the only surviving record of how to stop the service, and this file
#   chooses stopping the service over refusing to act. That is the one branch
#   in which a file inside the evidence directory still chooses a command, so
#   EVERY caller in this repo passes its execution.yaml — `aid-run-gates.sh` on
#   entry sweep and release, and `aid-fsm.sh` on both `resume` and
#   `done-advance`. What this model removes unconditionally is reaching OUT of
#   the evidence directory to a different run's jobs.
#
# ── RESOURCE EVIDENCE (observe only) ────────────────────────────────────────
# Reaching `healthy` also appends one line to
# `<evidence>/service-resources.jsonl` naming the per-run resource the service
# occupies ({kind: external_service, namespace: per-run, id: "<name>:<port>"}).
# Nothing consumes it to make a decision — the resource-map classifier is not
# touched — so it can never turn a per-run port into a verdict by accident. See
# `_aid_svc_emit_resource`.
#
# ── STATES ──────────────────────────────────────────────────────────────────
#   absent → starting → healthy | unhealthy | timed_out | lost
# `absent` is the absence of an entry, not a stored value. One further value,
# `stopped`, is written by `aid_service_down_all`: it is the post-teardown
# terminal state of an entry and sits OUTSIDE the startup lifecycle above (the
# plan names it explicitly for down_all).
#
# ── PORTS ───────────────────────────────────────────────────────────────────
# A service that declares `port_env` gets a fresh port per run, allocated by a
# transient `python3` socket bind — the only genuine BIND probe available to us.
# Bash's `/dev/tcp` is connect-only: a connect scan proves somebody is not
# listening, never that we could bind. `python3` is therefore a declared
# dependency of the services feature, refused BY NAME at `aid_service_up_all`
# when a port_env service is declared and it is absent.
#
# The window between releasing the probe socket and the service binding the
# port cannot be closed without holding the socket across an exec, so it is
# closed PRAGMATICALLY and the honesty is stated rather than hidden: if the
# started service fails its probe AND its captured output names a bind failure,
# ONE reallocation with a fresh port is attempted. A second collision is a
# named failure. That is best-effort, and it is documented as best-effort.
#
# ── PROBING ─────────────────────────────────────────────────────────────────
# Fixed 1 s interval. No adaptive polling, no startup_p95 field: the probe is
# declared cheap and side-effect free by contract, and an adaptive schedule
# would buy a fraction of a second at the price of a second timing model.
#
# ── THE FOREGROUND CONTRACT ─────────────────────────────────────────────────
# `start_cmd` MUST remain the foreground process of its job. execution.yaml's
# validator lints the obvious syntax (`&`, `nohup`, `disown`, `setsid`) and says
# plainly that it cannot see a command that daemonises INSIDE itself. This file
# is where that residual is caught, at runtime: a job that has reached a
# TERMINAL state while its probe still reports HEALTHY means the thing
# answering the probe is not the process the supervisor owns. That is the
# violation, and it is refused by name.
#
# The window in which that verdict is reachable is the DECLARED STARTUP BUDGET,
# not a private timer: after the job reaches a terminal state the probe keeps
# asking until `startup_deadline_seconds` is spent (never less than
# AID_SERVICE_TERMINAL_GRACE_SEC, so a job that ends at the very edge of its
# budget still gets a fair window). So the guarantee is stateable: ANY hand-off
# that answers a probe within the budget the declaration itself asked for is
# named `daemonized_start_cmd`. What it still cannot see is a child that binds
# AFTER that budget — an unbounded wait is not available to a run that has to
# finish. The price of the wider window is that a service which simply crashes
# is now reported at the end of its startup budget rather than a few seconds in;
# a declaration that wants fast failure declares a short
# `startup_deadline_seconds`, which is exactly what that field is for.
#
# Requirements: bash 4.1+ (named fd redirection), jq, flock, yq (mikefarah),
# aid-job.sh; python3 additionally for any service declaring `port_env`.
# =============================================================================

[[ -n "${_AID_SERVICE_LIB_LOADED:-}" ]] && return 0
_AID_SERVICE_LIB_LOADED=1

# ── Constants (one definition each; callers read, never re-derive) ───────────
AID_SERVICE_SCHEMA="aid-service-registry/1"
AID_SERVICE_REGISTRY_BASENAME="services.json"
AID_SERVICE_LOCK_BASENAME=".services.lock"
AID_SERVICE_JOBS_SUBDIR="service-jobs"
AID_SERVICE_PROBE_INTERVAL_SEC=1
# The FLOOR of the window in which the probe keeps asking after the job has
# reached a terminal state. The window itself runs to the declared
# `startup_deadline_seconds`; this is only what a job that ends at the very edge
# of that budget still gets. Overridable so an operator with a genuinely slow
# hand-off can widen it without editing a declaration's budget.
AID_SERVICE_TERMINAL_GRACE_SEC="${AID_SERVICE_TERMINAL_GRACE_SEC:-5}"
AID_SERVICE_DEFAULT_MAX_LIFETIME=86400
AID_SERVICE_LOCK_WAIT_SEC=30

# aid-job.sh's terminal vocabulary, verbatim. Never abbreviated, never guessed.
AID_SERVICE_JOB_TERMINAL_RE='^(terminal_pass|terminal_fail|timed_out|cancelled)$'
# ... plus `lost`, which aid-job.sh defines as "owned process gone AND no
# terminal record". For the foreground contract the two say the SAME thing —
# the supervisor no longer owns a running process — so anything that answers a
# probe afterwards is equally not the supervisor's. `lost` is also the reading
# aid-job.sh returns in the instant between the wrapper exiting and the
# collector writing the terminal record, so treating it differently made the
# daemonize verdict depend on which side of that instant we happened to poll.
AID_SERVICE_JOB_ENDED_RE='^(terminal_pass|terminal_fail|timed_out|cancelled|lost)$'

_AID_SERVICE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TEST SEAM ONLY. The environment may point this at a stub supervisor, which is
# how this lib's bats suite drives it. Env control of a process is already code
# execution, so this is not a boundary — it is a hook, and it is named as one.
AID_SERVICE_JOB_SH="${AID_SERVICE_JOB_SH:-${_AID_SERVICE_LIB_DIR}/../aid-job.sh}"

# ── The env-name denylist: ONE definition, two consumers ─────────────────────
# The list lives in lib/aid-env-name-denylist.sh and is read by BOTH the
# declaration-time check (`_svc_denied_port_env` in aid-run-gates.sh) and the
# export-time guard below. A second enumeration is a list that drifts, and it
# did: this file's copy was missing the interpreter-hook and git families while
# its own header advertised that it covered them.
_AID_SERVICE_DENYLIST_AVAILABLE=1
if [[ -r "${_AID_SERVICE_LIB_DIR}/aid-env-name-denylist.sh" ]]; then
  # shellcheck source=aid-env-name-denylist.sh
  source "${_AID_SERVICE_LIB_DIR}/aid-env-name-denylist.sh"
fi
if ! declare -F aid_env_name_denied >/dev/null 2>&1; then
  # FAIL CLOSED: with no denylist available, every name is denied. That refuses
  # a legitimate declaration rather than exporting an unchecked one, and the
  # refusal says which of the two happened.
  _AID_SERVICE_DENYLIST_AVAILABLE=0
  aid_env_name_denied() { return 0; }
fi

# The execution.yaml this lib reads when the caller passes no explicit path.
AID_SERVICE_CONFIG="${AID_SERVICE_CONFIG:-.aid-o/config/execution.yaml}"

# Set by up_all/down_all so `aid_service_status <name>` can keep the one-arg
# signature the plan specifies. A caller that has no such context passes the
# evidence directory as the second argument instead.
AID_SERVICE_EVIDENCE_DIR="${AID_SERVICE_EVIDENCE_DIR:-}"

# ── Diagnostics ──────────────────────────────────────────────────────────────
# Every service failure names the service. `aid-job.sh`'s own stderr is
# propagated VERBATIM behind that prefix — this file never paraphrases the
# supervisor.
_aid_svc_err()      { printf 'ERROR: aid-service: %s\n' "$1" >&2; }
_aid_svc_svc_err()  { printf 'ERROR: aid-service: service %s: %s\n' "$1" "$2" >&2; }
_aid_svc_log()      { printf 'aid-service: %s\n' "$1" >&2; }

_aid_svc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── Environment export guard ─────────────────────────────────────────────────
# The port variable is exported into the environment of the start, probe and
# stop commands. execution.yaml's validator already refuses a reserved or
# malformed name; this is the second check at the only place that actually
# performs the export, reading the SAME shared list, so a caller that skipped
# validation cannot get `PATH=41234` — or `GIT_SSH_COMMAND=…` — past this file.
#
# A refusal is never silent. Without a word the service starts with its port
# variable unset, binds whatever default it has, fails its probe, and is
# reported as a startup-deadline timeout — a diagnosis that says nothing about
# the actual cause. (`_aid_svc_up_one` refuses such a declaration outright, so
# in practice this message is the defence-in-depth path, not the usual one.)
_aid_svc_export_port() {
  local var="${1:-}" port="${2:-}"
  [[ -n "$var" && -n "$port" && "$port" != "null" ]] || return 0
  if [[ ! "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    _aid_svc_export_refused "$var" "it is not a legal environment variable name"
    return 0
  fi
  if aid_env_name_denied "$var"; then
    _aid_svc_export_refused "$var" "$(_aid_svc_denied_reason)"
    return 0
  fi
  export "${var}=${port}"
}

_aid_svc_denied_reason() {
  if (( _AID_SERVICE_DENYLIST_AVAILABLE )); then
    printf 'it is a variable this system'"'"'s own children depend on (command lookup, shell startup, a loader or interpreter hook, or AID'"'"'s own namespace)'
  else
    printf 'the shared env-name denylist at %s/aid-env-name-denylist.sh could not be loaded, so EVERY name is refused rather than one being exported unchecked' "$_AID_SERVICE_LIB_DIR"
  fi
}

# One message per variable per shell — a probe loop must not turn a single bad
# declaration into a hundred identical lines.
_aid_svc_export_refused() {
  local var="$1" why="$2"
  case " ${_AID_SVC_EXPORT_WARNED:-} " in *" ${var} "*) return 0 ;; esac
  _AID_SVC_EXPORT_WARNED="${_AID_SVC_EXPORT_WARNED:-} ${var}"
  _aid_svc_err "refusing to export the allocated port as '${var}': ${why}. The command will run with '${var}' untouched and no port in hand."
}

# ═══════════════════════════════════════════════════════════════════════════
# Revalidation — nothing read back from the registry is trusted on sight
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_valid_name <name>
#   The SAME charset `_validate_services_config` enforces at declaration time.
#   Re-checked here because THIS file is the one that turns a service name into
#   a filesystem path (`<evidence>/service-jobs/<name>`) and into a job id, and
#   a path builder that relies on a downstream component's validation is a path
#   builder with no validation. `aid-job.sh` refusing the derived id afterwards
#   is defence in depth, not the check.
_aid_svc_valid_name() { [[ "${1-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; }

# _aid_svc_valid_port <value> — an integer in the range a socket can carry.
_aid_svc_valid_port() {
  [[ "${1-}" =~ ^[0-9]{1,5}$ ]] || return 1
  (( 10#${1} > 0 && 10#${1} < 65536 ))
}

# _aid_svc_safe_jobs_dir <evidence_dir> <service> [<recorded_jobs_dir>]
#   Echoes a jobs directory GUARANTEED to resolve inside <evidence_dir>.
#
#   The recorded value is used when it does; otherwise it is refused, loudly,
#   and the canonical path is used instead. This is the single check that stops
#   a hand-written registry from aiming `aid-job.sh cancel` at a concurrent
#   run's jobs — with it, the worst a bad `jobs_dir` can do is name a directory
#   this run already owns.
_aid_svc_safe_jobs_dir() {
  local evidence="$1" name="$2" recorded="${3:-}" canon base rp
  canon="${evidence}/${AID_SERVICE_JOBS_SUBDIR}/${name}"
  [[ -n "$recorded" ]] || { printf '%s' "$canon"; return 0; }
  base="$(realpath -m -- "$evidence" 2>/dev/null || printf '%s' "$evidence")"
  rp="$(realpath -m -- "$recorded" 2>/dev/null || printf '')"
  if [[ -n "$rp" && ( "$rp" == "$base" || "$rp" == "$base"/* ) ]]; then
    printf '%s' "$recorded"
    return 0
  fi
  _aid_svc_log "service ${name}: the registry's jobs_dir '${recorded}' does not resolve inside this run's evidence directory (${base}) — refusing it and using ${canon}"
  printf '%s' "$canon"
}

# ═══════════════════════════════════════════════════════════════════════════
# Registry
# ═══════════════════════════════════════════════════════════════════════════

_aid_svc_registry_path() { printf '%s/%s' "$1" "$AID_SERVICE_REGISTRY_BASENAME"; }
_aid_svc_lock_path()     { printf '%s/%s' "$1" "$AID_SERVICE_LOCK_BASENAME"; }

# _aid_svc_registry_doc <registry_path>
#   Echo the current document, or a fresh empty one when the file does not
#   exist. rc 1 when the file exists but is NOT this registry — a corrupt or
#   foreign file is refused, never overwritten, because overwriting it would
#   destroy the only record of what is currently running.
_aid_svc_registry_doc() {
  local reg="$1"
  if [[ -e "$reg" ]]; then
    jq -ce --arg s "$AID_SERVICE_SCHEMA" \
      'if (.schema == $s and (.services | type) == "object") then . else empty end' \
      "$reg" 2>/dev/null || return 1
    return 0
  fi
  jq -nc --arg s "$AID_SERVICE_SCHEMA" '{schema:$s, services:{}, updated_at:null}'
}

# _aid_svc_registry_put <evidence_dir> <service> <patch_json>
#   Read-modify-write of ONE service entry under an exclusive flock, committed
#   with tmp+mv in the registry's own directory. The patch is shallow-merged
#   over whatever the entry already holds, so a caller updates one field
#   without having to restate the rest.
#   rc 0 written · rc 1 not written (and the caller must fail the up).
_aid_svc_registry_put() {
  local evidence="$1" name="$2" patch="$3"
  local reg lock doc new tmp lfd rc=0 now
  [[ -d "$evidence" ]] || { _aid_svc_err "evidence directory does not exist: ${evidence}"; return 1; }
  reg="$(_aid_svc_registry_path "$evidence")"
  lock="$(_aid_svc_lock_path "$evidence")"
  now="$(_aid_svc_now)"

  # The lock file is created by an ORDINARY command, never by `exec`: a
  # redirection on a command-less `exec` is applied to the SHELL and is
  # permanent, so `exec {fd}>file 2>/dev/null` would silently send every later
  # diagnostic of the calling script to /dev/null. (Found the hard way: it
  # swallowed six of this file's own failure messages.)
  : >> "$lock" 2>/dev/null || { _aid_svc_err "cannot open the registry lock ${lock}"; return 1; }
  exec {lfd}>>"$lock"
  if ! flock -x -w "$AID_SERVICE_LOCK_WAIT_SEC" "$lfd"; then
    exec {lfd}>&-
    _aid_svc_err "timed out after ${AID_SERVICE_LOCK_WAIT_SEC}s waiting for the registry lock ${lock}"
    return 1
  fi

  if ! doc="$(_aid_svc_registry_doc "$reg")" || [[ -z "$doc" ]]; then
    exec {lfd}>&-
    _aid_svc_err "the registry at ${reg} is not a ${AID_SERVICE_SCHEMA} document — refusing to overwrite it (move it aside by hand if it is genuinely stale)"
    return 1
  fi

  if ! new="$(jq -c --arg n "$name" --argjson p "$patch" --arg now "$now" \
        '.services[$n] = ((.services[$n] // {}) + $p)
         | .services[$n].service = $n
         | .services[$n].updated_at = $now
         | .updated_at = $now' <<<"$doc" 2>/dev/null)"; then
    exec {lfd}>&-
    _aid_svc_err "could not compose the registry update for service ${name}"
    return 1
  fi

  if ! tmp="$(mktemp "${reg}.XXXXXX" 2>/dev/null)"; then
    exec {lfd}>&-
    _aid_svc_err "could not create a temporary file beside ${reg}"
    return 1
  fi
  if ! printf '%s\n' "$new" > "$tmp" 2>/dev/null || ! mv -f "$tmp" "$reg" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    rc=1
    _aid_svc_err "could not commit the registry update at ${reg}"
  fi
  exec {lfd}>&-
  return "$rc"
}

# _aid_svc_registry_get <evidence_dir> <service> — the entry JSON, or nothing.
# Shared lock: a reader must not see a half-written document (though tmp+mv
# already makes that impossible, the lock also serialises against the
# read-modify-write above rather than only against the commit).
_aid_svc_registry_get() {
  local evidence="$1" name="$2" reg lock lfd out=""
  reg="$(_aid_svc_registry_path "$evidence")"
  [[ -f "$reg" ]] || return 0
  lock="$(_aid_svc_lock_path "$evidence")"
  # Same discipline as the writer: the lock file is created by an ordinary
  # command, so a failure here costs us the LOCK, never the caller's stderr.
  if : >> "$lock" 2>/dev/null; then
    exec {lfd}>>"$lock"
    flock -s -w "$AID_SERVICE_LOCK_WAIT_SEC" "$lfd" || true
    out="$(jq -ce --arg n "$name" '.services[$n] // empty' "$reg" 2>/dev/null || true)"
    exec {lfd}>&-
  else
    out="$(jq -ce --arg n "$name" '.services[$n] // empty' "$reg" 2>/dev/null || true)"
  fi
  printf '%s' "$out"
}

# _aid_svc_registry_names <evidence_dir> — every service name in the registry.
_aid_svc_registry_names() {
  local reg; reg="$(_aid_svc_registry_path "$1")"
  [[ -f "$reg" ]] || return 0
  jq -r '.services | keys[]?' "$reg" 2>/dev/null || true
}

# _aid_svc_entry_field <entry_json> <field> — "" for null/absent.
_aid_svc_entry_field() {
  local v
  v="$(jq -r --arg f "$2" '.[$f] // "" | tostring' <<<"$1" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# ═══════════════════════════════════════════════════════════════════════════
# Declarations (execution.yaml)
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_declared_names <execution_yaml>
#   rc 0 + the declared service names on stdout (possibly none: no `services:`
#         block at all, or an explicitly empty one — both genuinely mean "there
#         are nothing to bring up").
#   rc 3  the block EXISTS but is not a map.
#
# The distinction is the point. `_validate_services_config` in aid-run-gates.sh
# remains the one authority that DIAGNOSES declaration shape, and it refuses
# this upstream — but a `services:` written as a list is a misunderstanding of
# the declarations, and this file must not be the place where a
# misunderstanding reads as "there are no services" while a missing yq, a
# missing jq and a missing supervisor all refuse. Same doctrine, applied to the
# one case that had been left out of it.
_aid_svc_declared_names() {
  local f="$1" has tag
  [[ -f "$f" ]] || return 0
  command -v yq >/dev/null 2>&1 || return 0
  has="$(yq 'has("services")' "$f" 2>/dev/null || echo false)"
  [[ "$has" == "true" ]] || return 0
  tag="$(yq '.services | tag' "$f" 2>/dev/null || echo '!!null')"
  [[ "$tag" == '!!null' ]] && return 0
  [[ "$tag" == '!!map' ]] || return 3
  yq '.services | keys | .[]' "$f" 2>/dev/null || true
}

# _aid_svc_declares <execution_yaml> <service> — rc 0 iff the file declares it.
_aid_svc_declares() {
  local f="$1" n="$2" line
  [[ -n "$f" && -f "$f" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  while IFS= read -r line; do
    [[ "$line" == "$n" ]] && return 0
  done < <(_aid_svc_declared_names "$f" 2>/dev/null || true)
  return 1
}

# _aid_svc_reconcile_cmd <execution_yaml> <service> <key> <recorded> [quiet]
#   Echoes the command that will actually run. See the trust model in the
#   header: the DECLARATION wins whenever one is readable, and the registry's
#   recorded copy is a fallback for the case the registry exists to serve — a
#   teardown whose config has moved — never a channel for choosing what runs.
#
#   `quiet` suppresses ONLY the unreconciled-fallback notice, and only where a
#   notice would be worse than useless: `aid_service_status` is a read-only
#   question a caller may ask in a loop, and one line of prose per call would
#   drown the answer. A DIVERGENCE is always reported, quiet or not — that is
#   the line that means something happened.
_aid_svc_reconcile_cmd() {
  local yaml="$1" name="$2" key="$3" recorded="$4" quiet="${5:-}" declared
  if _aid_svc_declares "$yaml" "$name"; then
    declared="$(_aid_svc_field "$yaml" "$name" "$key")"
    if [[ "$declared" != "$recorded" ]]; then
      _aid_svc_log "service ${name}: the registry's ${key} differs from the one declared in ${yaml} — the DECLARATION wins (the registry records what this run allocated, it does not choose what executes)"
    fi
    printf '%s' "$declared"
    return 0
  fi
  # The authority IS readable and does not name this service. Then "no
  # declaration available" is false: what we have is a declaration that says
  # this service does not exist, and honouring the registry's recorded command
  # here would let a file inside the evidence directory introduce a service the
  # config never had — a name the caller cannot have reviewed, carrying a
  # command the caller never wrote. REFUSED, and said out loud. The job is still
  # cancelled by id (that is how the process actually dies; the recorded
  # `stop_cmd` is a courtesy on top of it), and the entry is still marked
  # stopped, so the refusal costs a courtesy and never leaves a live job behind.
  if [[ -n "$yaml" && -r "$yaml" ]] && command -v yq >/dev/null 2>&1; then
    if [[ -n "$recorded" && -z "$quiet" ]]; then
      _aid_svc_log "service ${name}: ${yaml} is readable and does NOT declare this service — REFUSING to run the ${key} recorded in the registry (the registry records what a run allocated, it never introduces a service or chooses what executes). If this service is real, declare it; the recorded value is: ${recorded}"
    fi
    printf '%s' ""
    return 0
  fi
  if [[ -n "$recorded" && -z "$quiet" ]]; then
    _aid_svc_log "service ${name}: no declaration available to reconcile ${key} against — using the value recorded at start-up, UNRECONCILED (pass the execution.yaml to reconcile it)"
  fi
  printf '%s' "$recorded"
}

# _aid_svc_field <execution_yaml> <service> <key> — the value, or "" when the
# key is absent (yq renders an absent key as "null", which is never a value we
# want to propagate into a command string or an integer).
_aid_svc_field() {
  local v
  v="$(SVC="$2" K="$3" yq '.services[strenv(SVC)][strenv(K)] // ""' "$1" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# ═══════════════════════════════════════════════════════════════════════════
# Ports
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_alloc_port — a port the kernel just proved WE could bind.
#
# python3 because it is the only genuine bind probe on this box: bash's
# /dev/tcp is connect-only, and "nobody answered a connect" is not "we may
# bind" (a socket in another namespace, a LISTEN with a full backlog, and a
# firewalled port all answer that question wrongly). No SO_REUSEADDR — the
# point is to learn whether an ordinary server bind would succeed, and
# SO_REUSEADDR would let us bind over a TIME_WAIT the real service may not.
#
# The socket is closed before we return it. That release-to-bind window is the
# race the single reallocation retry exists to survive; see the file header.
_aid_svc_alloc_port() {
  local p
  p="$(python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()' 2>/dev/null || true)"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) || return 1
  printf '%s' "$p"
}

# _aid_svc_bind_failure <jobs_dir> <job_id> — rc 0 iff the job's captured
# output names a bind collision. Deliberately a pattern match over the
# supervisor's own capture files rather than a guess: this is the ONE signal
# that distinguishes "somebody took the port between our probe and the bind"
# from "the service is simply broken", and only the first justifies a retry.
_aid_svc_bind_failure() {
  local d="$1/$2"
  local re='([Aa]ddress already in use|EADDRINUSE|[Ee]rrno 98|[Aa]ddress in use|bind: .*in use)'
  grep -Eq "$re" "$d/stdout.log" "$d/wrapper.log" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
# Probe
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_probe <probe_cmd> <port_env> <port> — rc 0 iff healthy. Runs in a
# command-substitution-free SUBSHELL so the exported port never leaks into the
# caller's environment (a run with two port_env services must not hand service
# B the environment of service A).
_aid_svc_probe() {
  local probe_cmd="${1:-}" port_env="${2:-}" port="${3:-}"
  [[ -n "$probe_cmd" ]] || return 1
  (
    _aid_svc_export_port "$port_env" "$port"
    bash -c "$probe_cmd"
  ) >/dev/null 2>&1
}

# _aid_svc_run_stop <stop_cmd> <port_env> <port> — best effort, same isolation.
_aid_svc_run_stop() {
  local stop_cmd="${1:-}" port_env="${2:-}" port="${3:-}"
  [[ -n "$stop_cmd" ]] || return 0
  (
    _aid_svc_export_port "$port_env" "$port"
    bash -c "$stop_cmd"
  ) >/dev/null 2>&1 || true
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Job delegation — every process concern, without exception, goes through here
# ═══════════════════════════════════════════════════════════════════════════

_aid_svc_job_state() {
  local jobs_dir="$1" job_id="$2"
  [[ -n "$job_id" ]] || { printf 'absent'; return 0; }
  bash "$AID_SERVICE_JOB_SH" status --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null || printf 'unknown'
}

_aid_svc_job_cancel() {
  local jobs_dir="$1" job_id="$2" out rc=0
  [[ -n "$job_id" ]] || return 0
  out="$(bash "$AID_SERVICE_JOB_SH" cancel --jobs-dir "$jobs_dir" --id "$job_id" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    # The supervisor's own words, verbatim, behind our prefix.
    _aid_svc_log "aid-job.sh cancel --id ${job_id} exited ${rc}: ${out}"
  fi
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Teardown of ONE service, driven ENTIRELY by the registry
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_stop_one <evidence_dir> <service> [<final_state>] [<execution_yaml>]
#   cancel the recorded job, then run the reconciled stop_cmd with the RECORDED
#   port re-exported, then record the final state. The port is read back from
#   the registry and never re-derived — that is the whole reason the registry
#   holds it, and it is what makes teardown work in a process that never saw
#   the allocation. Every value read back is revalidated first; see the trust
#   model in the header.
#
#   rc 0 always: teardown is best-effort by design, and a partial failure must
#   still attempt everything else. Whether anything SURVIVED is answered by
#   `aid_service_down_all`, which probes afterwards.
_aid_svc_stop_one() {
  local evidence="$1" name="$2" final="${3:-stopped}" yaml="${4:-}"
  local entry job_id jobs_dir port port_env stop_cmd
  if ! _aid_svc_valid_name "$name"; then
    _aid_svc_err "refusing to act on the registry entry '${name}': it is not a valid service name (allowed: lowercase letters, digits, '_' and '-', starting with a letter or digit), and a service name becomes a directory name here"
    return 0
  fi
  entry="$(_aid_svc_registry_get "$evidence" "$name")"
  [[ -n "$entry" ]] || return 0
  job_id="$(_aid_svc_entry_field "$entry" job_id)"
  jobs_dir="$(_aid_svc_entry_field "$entry" jobs_dir)"
  port="$(_aid_svc_entry_field "$entry" port)"
  port_env="$(_aid_svc_entry_field "$entry" port_env)"
  stop_cmd="$(_aid_svc_entry_field "$entry" stop_cmd)"

  jobs_dir="$(_aid_svc_safe_jobs_dir "$evidence" "$name" "$jobs_dir")"
  if [[ -n "$port" ]] && ! _aid_svc_valid_port "$port"; then
    _aid_svc_svc_err "$name" "the registry records a port that is not a port number ('${port}') — the stop command will run without one"
    port=""
  fi
  stop_cmd="$(_aid_svc_reconcile_cmd "$yaml" "$name" stop_cmd "$stop_cmd")"

  _aid_svc_job_cancel "$jobs_dir" "$job_id"
  _aid_svc_run_stop "$stop_cmd" "$port_env" "$port"

  _aid_svc_registry_put "$evidence" "$name" \
    "$(jq -nc --arg s "$final" '{state:$s}')" \
    || _aid_svc_log "service ${name}: teardown ran but the registry state could not be set to ${final}"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Resource evidence — OBSERVE ONLY (P076 Step 10, PM decision 3)
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_emit_resource <evidence_dir> <service> <port>
#   Appends one line to `<evidence>/service-resources.jsonl` when a service
#   reaches healthy:
#     {"kind":"external_service","namespace":"per-run","id":"<name>:<port>"}
#
#   It is EVIDENCE, not a control signal. Nothing reads it to make a decision:
#   the resource-map classifier is deliberately NOT touched by this step, so a
#   per-run service port cannot start failing a parallel-safety verdict on the
#   strength of a line nobody designed that classifier to receive. It exists so
#   that a human — or a later step that decides to consume it on purpose — can
#   see which per-run ports a run actually occupied.
#
#   A service with no `port_env` has no allocated port, and the id says exactly
#   that (`<name>:none`) rather than pretending to a number.
#
#   Best-effort by construction: a failure to append is logged and changes
#   nothing. A service that is healthy is healthy whether or not we could write
#   a note about it.
_aid_svc_emit_resource() {
  local evidence="$1" name="$2" port="${3:-}" line dest
  dest="${evidence}/service-resources.jsonl"
  [[ -d "$evidence" ]] || return 0
  _aid_svc_valid_port "$port" || port="none"
  line="$(jq -nc --arg id "${name}:${port}" \
    '{kind:"external_service", namespace:"per-run", id:$id}' 2>/dev/null)" || return 0
  printf '%s\n' "$line" >> "$dest" 2>/dev/null \
    || _aid_svc_log "service ${name}: could not append its resource line to ${dest} (observe-only evidence; the service itself is unaffected)"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# up
# ═══════════════════════════════════════════════════════════════════════════

# _aid_svc_up_one <evidence_dir> <execution_yaml> <service>
#   rc 0 healthy · rc 1 named failure (already reported, already torn down).
_aid_svc_up_one() {
  local evidence="$1" yaml="$2" name="$3"
  local start_cmd probe_cmd stop_cmd port_env log_hint
  local startup_deadline max_lifetime restart_auth

  # The name becomes a DIRECTORY and a JOB ID a few lines below, so it is
  # validated here rather than downstream. `aid-job.sh` refusing the derived id
  # is real defence in depth, but it does not stop the `mkdir -p` this file does
  # first — a traversal name created a directory four levels above the evidence
  # tree before this check existed.
  if ! _aid_svc_valid_name "$name"; then
    _aid_svc_svc_err "$name" "invalid service name (allowed: lowercase letters, digits, '_' and '-', starting with a letter or digit) — it becomes a directory name and a job id, so it is refused before either is built"
    return 1
  fi
  start_cmd="$(_aid_svc_field "$yaml" "$name" start_cmd)"
  probe_cmd="$(_aid_svc_field "$yaml" "$name" probe_cmd)"
  stop_cmd="$(_aid_svc_field "$yaml" "$name" stop_cmd)"
  port_env="$(_aid_svc_field "$yaml" "$name" port_env)"
  log_hint="$(_aid_svc_field "$yaml" "$name" log_hint)"
  startup_deadline="$(_aid_svc_field "$yaml" "$name" startup_deadline_seconds)"
  max_lifetime="$(_aid_svc_field "$yaml" "$name" max_lifetime_seconds)"
  restart_auth="$(_aid_svc_field "$yaml" "$name" restart_authorized)"
  [[ "$startup_deadline" =~ ^[0-9]+$ ]] || startup_deadline=60
  [[ "$max_lifetime" =~ ^[0-9]+$ ]] || max_lifetime="$AID_SERVICE_DEFAULT_MAX_LIFETIME"
  [[ "$restart_auth" == "true" ]] || restart_auth="false"

  # A port_env this file would refuse to export is refused HERE, before a job
  # exists, rather than becoming a service that starts without its port and is
  # then reported as a startup-deadline timeout — a diagnosis about the symptom.
  if [[ -n "$port_env" ]]; then
    local pe_why=""
    if [[ ! "$port_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      pe_why="it is not a legal environment variable name"
    elif aid_env_name_denied "$port_env"; then
      pe_why="$(_aid_svc_denied_reason)"
    fi
    if [[ -n "$pe_why" ]]; then
      _aid_svc_svc_err "$name" "port_env '${port_env}' will not be exported: ${pe_why}. Refusing to start it with its port variable unset, which would fail its probe and be reported as a startup timeout instead of as this."
      return 1
    fi
  fi

  local hint_suffix=""
  [[ -n "$log_hint" ]] && hint_suffix=" (its own logs: ${log_hint})"

  local jobs_dir="${evidence}/${AID_SERVICE_JOBS_SUBDIR}/${name}"
  local run_id="${AID_SERVICE_RUN_ID:-$(basename "$evidence")}"

  # ── idempotent rerun (a resumed run after a crash) ──────────────────────
  # An existing HEALTHY entry is verified by exactly ONE probe and reused. No
  # second job directory is created, because the service it points at is the
  # service that is running.
  local entry state
  entry="$(_aid_svc_registry_get "$evidence" "$name")"
  if [[ -n "$entry" ]]; then
    state="$(_aid_svc_entry_field "$entry" state)"
    if [[ "$state" == "healthy" ]]; then
      local rport rjob
      rport="$(_aid_svc_entry_field "$entry" port)"
      rjob="$(_aid_svc_entry_field "$entry" job_id)"
      if _aid_svc_probe "$probe_cmd" "$port_env" "$rport"; then
        _aid_svc_log "service ${name}: already healthy (job ${rjob:-none}${rport:+, port ${rport}}) — reused, not restarted"
        return 0
      fi
      _aid_svc_log "service ${name}: the registry says healthy but the probe disagrees — tearing that job down and starting fresh"
      _aid_svc_stop_one "$evidence" "$name" "unhealthy" "$yaml"
    elif [[ "$state" == "starting" || "$state" == "unhealthy" || "$state" == "timed_out" || "$state" == "lost" ]]; then
      # A leftover from a run that died mid-startup. Its job may still be live,
      # and starting a second one beside it is exactly the orphan this file
      # exists to prevent.
      _aid_svc_log "service ${name}: found a leftover '${state}' entry from an earlier attempt — tearing it down before starting"
      _aid_svc_stop_one "$evidence" "$name" "$state" "$yaml"
    fi
  fi

  mkdir -p "$jobs_dir" 2>/dev/null || {
    _aid_svc_svc_err "$name" "could not create the job directory ${jobs_dir}"
    return 1
  }

  local realloc_used=0 restart_used=0 attempt=0
  while : ; do
    attempt=$(( attempt + 1 ))

    # ── port allocation ────────────────────────────────────────────────────
    local port=""
    if [[ -n "$port_env" ]]; then
      if ! port="$(_aid_svc_alloc_port)"; then
        _aid_svc_svc_err "$name" "could not allocate a free port for '${port_env}': the python3 bind probe produced no usable port number"
        return 1
      fi
    fi

    # ── EAGER PHASE 1 — the record exists BEFORE the job does ──────────────
    if ! _aid_svc_registry_put "$evidence" "$name" "$(jq -nc \
          --arg run "$run_id" --arg pe "$port_env" --arg probe "$probe_cmd" \
          --arg stop "$stop_cmd" --arg jd "$jobs_dir" --arg started "$(_aid_svc_now)" \
          --argjson port "${port:-null}" --argjson attempt "$attempt" \
          --argjson realloc "$realloc_used" --argjson restarts "$restart_used" \
          '{run_id:$run, state:"starting", job_id:null, port:$port,
            port_env:(if $pe == "" then null else $pe end),
            probe_cmd:$probe, stop_cmd:(if $stop == "" then null else $stop end),
            jobs_dir:$jd, attempt:$attempt, reallocations:$realloc,
            restarts:$restarts, started_at:$started, failure_reason:null,
            violation:null}')"; then
      _aid_svc_svc_err "$name" "the pre-spawn registry write failed — refusing to start a service the run would have no record of, and therefore no way to stop"
      return 1
    fi

    # ── spawn, through the ONE process owner ───────────────────────────────
    local job_id="${name}-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
    local errfile spawned="" start_rc=0 start_err=""
    errfile="$(mktemp)"
    spawned="$(
      _aid_svc_export_port "$port_env" "$port"
      bash "$AID_SERVICE_JOB_SH" run \
        --jobs-dir "$jobs_dir" --id "$job_id" \
        --label "service:${name}" --deadline "$max_lifetime" \
        -- bash -c "$start_cmd" 2>"$errfile"
    )" || start_rc=$?
    start_err="$(cat "$errfile" 2>/dev/null || true)"
    rm -f "$errfile" 2>/dev/null || true

    if (( start_rc != 0 )) || [[ -z "$spawned" ]]; then
      _aid_svc_registry_put "$evidence" "$name" \
        "$(jq -nc '{state:"unhealthy", failure_reason:"job_start_failed"}')" || true
      _aid_svc_svc_err "$name" "aid-job.sh run failed (exit ${start_rc}): ${start_err}"
      return 1
    fi

    # ── EAGER PHASE 2 — the real job id, immediately ───────────────────────
    if ! _aid_svc_registry_put "$evidence" "$name" \
          "$(jq -nc --arg j "$spawned" '{job_id:$j}')"; then
      # The job is already running, so refusing is not enough: cancel what we
      # can no longer record. Fail closed WITH cleanup.
      _aid_svc_job_cancel "$jobs_dir" "$spawned"
      _aid_svc_run_stop "$stop_cmd" "$port_env" "$port"
      _aid_svc_svc_err "$name" "could not record job '${spawned}' in the registry after spawning it; the job has been cancelled rather than left unstoppable"
      return 1
    fi

    # ── probe to healthy, or to the startup deadline ───────────────────────
    # Fixed 1 s interval. The job state is read BEFORE the probe on every
    # iteration, and that order is load-bearing: a job already TERMINAL when a
    # subsequent probe answers healthy proves the answering process is not the
    # one the supervisor owned.
    local t0=$SECONDS outcome="" job_state="" post_state="" probe_ok=0
    while : ; do
      job_state="$(_aid_svc_job_state "$jobs_dir" "$spawned")"
      probe_ok=0
      _aid_svc_probe "$probe_cmd" "$port_env" "$port" && probe_ok=1

      if [[ "$job_state" =~ $AID_SERVICE_JOB_ENDED_RE ]]; then
        if (( probe_ok )); then outcome="daemonized"; break; fi
        # The job is over and nothing is answering YET. That is not enough to
        # call it a crash: a start_cmd that handed off to a child which is slow
        # to bind looks exactly like this until the child binds, and calling it
        # a plain start failure would report the wrong diagnosis AND walk away
        # from an orphan nobody owns.
        #
        # So the probe keeps asking for the rest of the DECLARED startup budget
        # (never less than the terminal-grace floor, so a job that ends at the
        # very edge of its budget still gets a fair window). The window is a
        # property of the declaration rather than a private timer, which is what
        # makes the guarantee stateable: a hand-off answering at ANY point
        # within the budget is named. An earlier version bounded this at a fixed
        # 5 s and claimed that was "long enough for a hand-off to show itself" —
        # it was not, and a 9 s hand-off got the plain start-failure diagnosis.
        local g0=$SECONDS
        while (( SECONDS - t0 < startup_deadline || SECONDS - g0 < AID_SERVICE_TERMINAL_GRACE_SEC )); do
          sleep "$AID_SERVICE_PROBE_INTERVAL_SEC"
          if _aid_svc_probe "$probe_cmd" "$port_env" "$port"; then probe_ok=1; break; fi
        done
        if (( probe_ok )); then outcome="daemonized"; else outcome="job_${job_state}"; fi
        break
      fi
      if (( probe_ok )); then
        # The probe answered — but WHO answered it? The state read above was
        # taken BEFORE the probe, so on its own it cannot rule out a start_cmd
        # that handed off to a child and returned WHILE we were probing. One
        # more read closes that window in the direction that matters: a job that
        # is terminal now cannot be the process that just answered, and calling
        # that "healthy" would hand the run a service it can never stop.
        post_state="$(_aid_svc_job_state "$jobs_dir" "$spawned")"
        if [[ "$post_state" =~ $AID_SERVICE_JOB_ENDED_RE ]]; then
          job_state="$post_state"; outcome="daemonized"; break
        fi
        outcome="healthy"; break
      fi
      if (( SECONDS - t0 >= startup_deadline )); then outcome="startup_deadline"; break; fi
      sleep "$AID_SERVICE_PROBE_INTERVAL_SEC"
    done

    # ── PHASE 3 / verdict ──────────────────────────────────────────────────
    if [[ "$outcome" == "healthy" ]]; then
      if ! _aid_svc_registry_put "$evidence" "$name" "$(jq -nc \
            --argjson realloc "$realloc_used" --argjson restarts "$restart_used" \
            '{state:"healthy", reallocations:$realloc, restarts:$restarts}')"; then
        _aid_svc_job_cancel "$jobs_dir" "$spawned"
        _aid_svc_run_stop "$stop_cmd" "$port_env" "$port"
        _aid_svc_svc_err "$name" "came up healthy but the registry could not record it; the job has been cancelled rather than left unstoppable"
        return 1
      fi
      _aid_svc_emit_resource "$evidence" "$name" "$port"
      _aid_svc_log "service ${name}: healthy (job ${spawned}${port:+, port ${port}}, attempt ${attempt})"
      return 0
    fi

    if [[ "$outcome" == "daemonized" ]]; then
      # THE runtime half of the foreground contract. Never retried: retrying a
      # start_cmd that daemonises just makes a second orphan.
      _aid_svc_registry_put "$evidence" "$name" "$(jq -nc --arg js "$job_state" \
        '{state:"unhealthy", failure_reason:"daemonized_start_cmd",
          violation:("job ended in " + $js + " while the probe still reported healthy")}')" || true
      _aid_svc_job_cancel "$jobs_dir" "$spawned"
      _aid_svc_run_stop "$stop_cmd" "$port_env" "$port"
      _aid_svc_svc_err "$name" "start_cmd must remain its job's foreground process — its job ended in the state '${job_state}' while the probe still reports healthy, so whatever is answering the probe is NOT the process the supervisor owns and this run can no longer stop what it started${hint_suffix}"
      return 1
    fi

    # Everything below is a service that did not come up. Tear the attempt down
    # BEFORE deciding whether to retry, so a retry never runs beside its
    # predecessor.
    _aid_svc_job_cancel "$jobs_dir" "$spawned"
    _aid_svc_run_stop "$stop_cmd" "$port_env" "$port"

    # ── retry 1 of 1: a bind collision on the allocated port ───────────────
    if [[ -n "$port_env" ]] && _aid_svc_bind_failure "$jobs_dir" "$spawned"; then
      if (( realloc_used == 0 )); then
        realloc_used=1
        _aid_svc_log "service ${name}: port ${port} was taken between allocation and bind — reallocating once (this is the documented best-effort race window)"
        continue
      fi
      _aid_svc_registry_put "$evidence" "$name" "$(jq -nc \
        --argjson realloc "$realloc_used" \
        '{state:"unhealthy", failure_reason:"port_collision_after_reallocation", reallocations:$realloc}')" || true
      _aid_svc_svc_err "$name" "port ${port} collided again after the one reallocation retry — refusing to keep guessing at ports${hint_suffix}"
      return 1
    fi

    # ── the one authorized restart ─────────────────────────────────────────
    if [[ "$restart_auth" == "true" ]] && (( restart_used == 0 )); then
      restart_used=1
      _aid_svc_log "service ${name}: did not become healthy (${outcome}) — spending the ONE authorized restart (restart_authorized: true)"
      continue
    fi

    local final_state failure
    case "$outcome" in
      startup_deadline|job_timed_out) final_state="timed_out" ;;
      job_lost)                       final_state="lost" ;;
      *)                              final_state="unhealthy" ;;
    esac
    if (( restart_used > 0 )); then
      failure="still unhealthy after the one authorized restart"
    elif [[ "$outcome" == "startup_deadline" ]]; then
      failure="did not become healthy within startup_deadline_seconds=${startup_deadline} (its job was ${job_state})"
    elif [[ "$outcome" == "job_lost" ]]; then
      failure="its job was LOST — the supervised process vanished without a terminal result, so nothing here proves what happened"
    else
      failure="its job reached '${job_state}' before the probe ever reported healthy"
    fi
    _aid_svc_registry_put "$evidence" "$name" "$(jq -nc \
      --arg s "$final_state" --arg f "$failure" \
      --argjson realloc "$realloc_used" --argjson restarts "$restart_used" \
      '{state:$s, failure_reason:$f, reallocations:$realloc, restarts:$restarts}')" || true
    _aid_svc_svc_err "$name" "${failure}; its job was cancelled and stop_cmd run${hint_suffix}"
    return 1
  done
}

# aid_service_up_all <run_evidence_dir> [<execution_yaml>]
#   rc 0 every declared service is healthy (or there are none)
#   rc 1 a named service failure — every service started so far stays recorded
#        and stoppable; the caller is expected to call aid_service_down_all
#   rc 2 the declarations could not be inspected, or a declared prerequisite is
#        missing. "I could not look" never reads as "there is nothing to do".
aid_service_up_all() {
  local evidence="${1:-}" yaml="${2:-$AID_SERVICE_CONFIG}"
  if [[ -z "$evidence" ]]; then
    _aid_svc_err "aid_service_up_all requires <run_evidence_dir>"
    return 2
  fi
  if [[ ! -f "$yaml" ]]; then
    _aid_svc_err "cannot read service declarations from '${yaml}': file not found (refusing rather than assuming there are no services)"
    return 2
  fi
  if ! command -v yq >/dev/null 2>&1; then
    _aid_svc_err "cannot read service declarations from '${yaml}': yq is not available (refusing rather than assuming there are no services)"
    return 2
  fi

  if [[ ! -d "$evidence" ]]; then
    _aid_svc_err "the run evidence directory '${evidence}' does not exist — the service registry lives there, and nothing here creates an evidence directory"
    return 2
  fi

  local -a names=() declared=()
  local names_raw="" rc_names=0
  names_raw="$(_aid_svc_declared_names "$yaml")" || rc_names=$?
  if (( rc_names == 3 )); then
    # NOT the same as "there are no services". A `services:` block that is not a
    # map is a misunderstanding of the declarations, and this file refuses it for
    # the same reason it refuses a missing yq: "I could not read it" must never
    # read as "there is nothing to do". (_validate_services_config diagnoses the
    # shape in detail and runs upstream; this is the fail-closed floor.)
    _aid_svc_err "the 'services:' block in '${yaml}' is not a map of service name -> declaration — refusing rather than reading it as 'there are no services'"
    return 2
  fi
  if (( rc_names != 0 )); then
    _aid_svc_err "could not read the service declarations in '${yaml}' (exit ${rc_names}) — refusing rather than assuming there are no services"
    return 2
  fi
  mapfile -t declared <<<"$names_raw"
  local n
  for n in "${declared[@]}"; do [[ -n "$n" ]] && names+=("$n"); done
  # ── no services declared: a cheap no-op, and the byte-identical path every
  # project that declares none stays on. Nothing is created, nothing probed.
  (( ${#names[@]} )) || return 0

  if ! command -v jq >/dev/null 2>&1; then
    _aid_svc_err "${#names[@]} service(s) declared in '${yaml}' but jq is not available — refusing to manage services without a registry"
    return 2
  fi
  if ! command -v flock >/dev/null 2>&1; then
    _aid_svc_err "${#names[@]} service(s) declared in '${yaml}' but flock is not available — refusing to manage services without a lockable registry"
    return 2
  fi
  if [[ ! -f "$AID_SERVICE_JOB_SH" ]]; then
    _aid_svc_err "${#names[@]} service(s) declared in '${yaml}' but the job supervisor is unavailable at ${AID_SERVICE_JOB_SH} — refusing to start a process nothing would own"
    return 2
  fi

  # python3 is a DECLARED DEPENDENCY of the port-allocating half of this
  # feature, refused by name and up front rather than as a mystery failure on
  # the third service.
  if ! command -v python3 >/dev/null 2>&1; then
    for n in "${names[@]}"; do
      if [[ -n "$(_aid_svc_field "$yaml" "$n" port_env)" ]]; then
        _aid_svc_svc_err "$n" "declares port_env but python3 is not installed. Per-run port allocation needs a real BIND probe and python3 is the only one available here — bash's /dev/tcp can only CONNECT, and a connect scan cannot prove a port is bindable. Install python3, or drop port_env and pin the service to a fixed external port."
        return 2
      fi
    done
  fi

  AID_SERVICE_EVIDENCE_DIR="$evidence"

  for n in "${names[@]}"; do
    _aid_svc_up_one "$evidence" "$yaml" "$n" || return 1
  done
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# down
# ═══════════════════════════════════════════════════════════════════════════

# aid_service_down_all <run_evidence_dir> [<execution_yaml>]
#   Teardown reads the REGISTRY for everything it was RECORDED (job id, jobs
#   dir, port), precisely so a teardown in a process that never saw the startup
#   still works — and reconciles the COMMANDS against <execution_yaml> when one
#   is given, because the registry does not choose what executes (see the trust
#   model in the header). The argument defaults to $AID_SERVICE_CONFIG.
#
#   Still best-effort in EFFORT: a stop that partially fails must attempt
#   everything else, and it does. But the exit code now answers the question a
#   caller actually has:
#     rc 0  nothing that this run recorded is answering its probe any more
#     rc 1  at least one service's readiness probe STILL PASSES after teardown —
#           named in the log. "I tried everything" and "everything is down" are
#           different answers and the difference is worth being machine-readable.
#
#   The instrument is the DECLARED probe, and that is the limit: a probe that
#   cannot fail (`probe_cmd: /bin/true`) cannot prove a teardown succeeded, so
#   rc 1 says exactly what it says — the probe still passes — and no more.
aid_service_down_all() {
  local evidence="${1:-}" yaml="${2:-$AID_SERVICE_CONFIG}"
  [[ -n "$evidence" ]] || { _aid_svc_err "aid_service_down_all requires <run_evidence_dir>"; return 1; }
  [[ -d "$evidence" ]] || return 0

  local reg jobs_root
  reg="$(_aid_svc_registry_path "$evidence")"
  jobs_root="${evidence}/${AID_SERVICE_JOBS_SUBDIR}"
  # Cheap no-op: nothing was ever brought up here.
  [[ -f "$reg" || -d "$jobs_root" ]] || return 0

  AID_SERVICE_EVIDENCE_DIR="$evidence"

  # The set of job ids the registry KNOWS about, captured before teardown so
  # the sweep below can tell a recorded job from an unrecorded one.
  local known=""
  if [[ -f "$reg" ]]; then
    known="$(jq -r '[.services[]?.job_id // empty] | join(" ")' "$reg" 2>/dev/null || true)"
  fi

  local n
  local -a stopped_names=()
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    _aid_svc_stop_one "$evidence" "$n" "stopped" "$yaml"
    stopped_names+=("$n")
  done < <(_aid_svc_registry_names "$evidence")

  # ── belt and braces: the supervisor's own layout ───────────────────────
  # One job, one directory: service-jobs/<name>/<job-id>/job.json. Anything
  # LIVE down there that the registry does not name is an orphan — from a
  # superseded retry whose teardown did not complete, or from a crash in a
  # window we have not thought of — and it is cancelled and logged rather than
  # left running.
  local d jd id st svc
  if [[ -d "$jobs_root" ]]; then
    for d in "$jobs_root"/*/; do
      [[ -d "$d" ]] || continue
      svc="$(basename "$d")"
      for jd in "$d"*/; do
        [[ -f "${jd}job.json" ]] || continue
        id="$(basename "$jd")"
        case " ${known} " in *" ${id} "*) continue ;; esac
        st="$(_aid_svc_job_state "${d%/}" "$id")"
        case "$st" in
          started|running)
            _aid_svc_log "service ${svc}: job '${id}' is ${st} but the registry does not name it — cancelling this orphan"
            _aid_svc_job_cancel "${d%/}" "$id"
            ;;
        esac
      done
    done
  fi

  # ── did any of it actually stop? ────────────────────────────────────────
  # One probe per service that had one. A service still answering after its job
  # was cancelled and its stop_cmd ran is precisely the daemonised-hand-off
  # orphan this file cannot reap, and saying so in the exit code is cheaper for
  # a caller than parsing prose.
  local survivors=0 entry sport sprobe sportenv
  for n in "${stopped_names[@]:-}"; do
    [[ -n "$n" ]] || continue
    _aid_svc_valid_name "$n" || continue
    entry="$(_aid_svc_registry_get "$evidence" "$n")"
    [[ -n "$entry" ]] || continue
    sprobe="$(_aid_svc_entry_field "$entry" probe_cmd)"
    sprobe="$(_aid_svc_reconcile_cmd "$yaml" "$n" probe_cmd "$sprobe" quiet)"
    [[ -n "$sprobe" ]] || continue
    sport="$(_aid_svc_entry_field "$entry" port)"
    _aid_svc_valid_port "$sport" || sport=""
    sportenv="$(_aid_svc_entry_field "$entry" port_env)"
    if _aid_svc_probe "$sprobe" "$sportenv" "$sport"; then
      survivors=$(( survivors + 1 ))
      _aid_svc_svc_err "$n" "its readiness probe still passes after teardown${sport:+ on port ${sport}} — its job was cancelled and its stop_cmd was run, so anything genuinely still answering is not a process this run owns (the daemonised-start_cmd case). Teardown did everything it can. (If probe_cmd cannot fail, this line says only that: a probe that cannot fail proves nothing about a teardown.)"
    fi
  done
  (( survivors == 0 )) || return 1
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# status
# ═══════════════════════════════════════════════════════════════════════════

# aid_service_status <name> [<run_evidence_dir>] [<execution_yaml>]
#   One JSON object on stdout; rc 0 iff the service is healthy right now.
#   The port comes from the REGISTRY and is never re-derived — that is what
#   makes a status call from a resumed controller mean the same thing as one
#   from the process that allocated it. The probe COMMAND is reconciled against
#   the declaration exactly as teardown reconciles stop_cmd.
#
#   Every exit path is a decision, never a fall-through. An earlier version
#   handed the registry's `port` straight to `jq --argjson`; a non-numeric value
#   made jq die printing nothing and the function fell through to `return 0` —
#   "healthy" on the strength of a crash, in a function whose entire job is
#   answering a readiness question. Nothing below may report success because
#   something failed.
aid_service_status() {
  local name="${1:-}" evidence="${2:-$AID_SERVICE_EVIDENCE_DIR}" yaml="${3:-$AID_SERVICE_CONFIG}"
  if [[ -z "$name" ]]; then
    _aid_svc_err "aid_service_status requires <name>"
    return 1
  fi
  if ! _aid_svc_valid_name "$name"; then
    _aid_svc_err "service '${name}': not a valid service name (allowed: lowercase letters, digits, '_' and '-', starting with a letter or digit)"
    return 1
  fi
  if [[ -z "$evidence" ]]; then
    _aid_svc_err "service ${name}: no run evidence directory known — pass it as the second argument or set AID_SERVICE_EVIDENCE_DIR"
    return 1
  fi

  local entry
  entry="$(_aid_svc_registry_get "$evidence" "$name")"
  if [[ -z "$entry" ]]; then
    jq -nc --arg n "$name" \
      '{service:$n, state:"absent", job_state:"absent", port:null, job_id:null,
        probe_exit:null, note:"no registry entry — this run never brought it up"}'
    return 1
  fi

  local job_id jobs_dir port port_env probe_cmd rec_state job_state probe_rc=0
  job_id="$(_aid_svc_entry_field "$entry" job_id)"
  jobs_dir="$(_aid_svc_entry_field "$entry" jobs_dir)"
  port="$(_aid_svc_entry_field "$entry" port)"
  port_env="$(_aid_svc_entry_field "$entry" port_env)"
  probe_cmd="$(_aid_svc_entry_field "$entry" probe_cmd)"
  rec_state="$(_aid_svc_entry_field "$entry" state)"
  jobs_dir="$(_aid_svc_safe_jobs_dir "$evidence" "$name" "$jobs_dir")"

  # A port that is not a port is registry corruption, and this function will not
  # guess past it: it is neither a healthy service nor a question we can answer.
  if [[ -n "$port" ]] && ! _aid_svc_valid_port "$port"; then
    _aid_svc_svc_err "$name" "the registry entry records a value that is not a port number ('${port}') — refusing to treat this entry as an answer about readiness"
    jq -nc --arg n "$name" --arg rs "$rec_state" \
      '{service:$n, state:"invalid_registry_entry", registry_state:$rs,
        job_state:"unknown", job_id:null, port:null, probe_exit:null,
        violation:"registry_port_not_a_number"}' 2>/dev/null \
      || printf '{"service":"%s","state":"invalid_registry_entry"}\n' "$name"
    return 1
  fi

  probe_cmd="$(_aid_svc_reconcile_cmd "$yaml" "$name" probe_cmd "$probe_cmd" quiet)"

  job_state="$(_aid_svc_job_state "$jobs_dir" "$job_id")"

  # Exactly ONE probe run — status is a question, not a poll loop.
  _aid_svc_probe "$probe_cmd" "$port_env" "$port" || probe_rc=$?

  local state="" violation=null
  if [[ "$rec_state" == "stopped" ]]; then
    state="stopped"
  elif [[ "$job_state" == "lost" ]]; then
    # Edge case, stated in the plan: a service that WAS healthy whose job is
    # later lost reports lost. Deciding what to do about it belongs elsewhere.
    state="lost"
    # ... but if something is STILL answering, the same reasoning as the ended
    # states applies: the supervisor owns nothing, so whatever answers is not
    # its process. Same violation, named the same way.
    if (( probe_rc == 0 )); then
      violation='"daemonized_start_cmd"'
    fi
  elif [[ "$job_state" == "timed_out" ]]; then
    state="timed_out"
  elif [[ "$job_state" =~ $AID_SERVICE_JOB_TERMINAL_RE ]]; then
    state="unhealthy"
    if (( probe_rc == 0 )); then
      violation='"daemonized_start_cmd"'
    fi
  elif (( probe_rc == 0 )); then
    state="healthy"
  elif [[ "$rec_state" == "starting" ]]; then
    state="starting"
  else
    state="unhealthy"
  fi

  # Both --argjson values are revalidated above (port) or produced here
  # (probe_rc, violation), and the call is STILL checked: a jq that cannot
  # render the answer has not answered, and an unanswered readiness question is
  # not a healthy service.
  if ! jq -nc --arg n "$name" --arg s "$state" --arg rs "$rec_state" \
        --arg js "$job_state" --arg jid "$job_id" \
        --argjson port "${port:-null}" --argjson probe "$probe_rc" \
        --argjson violation "$violation" \
    '{service:$n, state:$s, registry_state:$rs, job_state:$js,
      job_id:(if $jid == "" then null else $jid end), port:$port,
      probe_exit:$probe, violation:$violation}'; then
    _aid_svc_svc_err "$name" "could not render its status document — reporting NOT healthy, because 'the answer could not be produced' is not 'the service is up'"
    return 1
  fi

  [[ "$state" == "healthy" ]] && return 0
  return 1
}
