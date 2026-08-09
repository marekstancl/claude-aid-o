#!/usr/bin/env bash
# aid-run-gates.sh — Deterministic gate runner with provenance fields (P032 Step 3).
#
# Usage:
#   aid-run-gates.sh run-gate <gate_name> <command> <timeout_s> <log_file>
#   aid-run-gates.sh run-all <execution_yaml> <epic_id> <run_id> [timeline_file] [--state-file <path>] [--report-file <path>] [--plan-json <path>] [--profile <name>] [--base-commit <sha>] [--plan-path <path>]
#
# P068 Step 2 changes:
#   • --base-commit <sha> / --plan-path <path> supply the {base_commit} and
#     {plan_path} substitution tokens EXPLICITLY. Both are additive and
#     optional; omitted, the runner reads them from --state-file exactly as
#     before (unchanged EPIC-scoped behaviour). They exist for the plan-final
#     run, which has no fsm-state.yaml at all — without them `plan_diff` gets
#     `--plan null`, takes its Fast Mode exit-2 skip, and the one release gate
#     run for a whole plan reports success while verifying nothing.
#
# P061 E1 Step 2 changes:
#   • --profile <name> selects a named subset of gates to run, from
#     execution.yaml.gate_profiles.<name>.include[] (a whitelist of gate
#     keys). Gates defined under execution.yaml.gates but NOT in the active
#     profile's include[] are NOT run — they get an explicit
#     `profile_excluded` result row instead of being silently omitted, and
#     never affect `overall` (same treatment as a skipped required:false
#     gate). Omitting --profile preserves today's behavior exactly: all
#     defined gates run, even if gate_profiles exists in execution.yaml.
#   • Unknown --profile name, or a profile include[] entry that isn't a key
#     under execution.yaml.gates, is fail-loud (exit != 0) BEFORE any gate
#     runs.
#   • gates_report.json gains: profile, profile_source, profile_reason,
#     excluded_gates[] (additive; null/[] when --profile isn't passed).
#
# P032 Step 3 changes vs pre-Session-A:
#   • execution.yaml parsing switched from awk regex to yq (mikefarah variant)
#   • timeline events `gate_runner_start` / `gate_runner_complete` framing the
#     entire run (in addition to per-gate `gate_start` / `gate_complete`)
#   • gates_report.json gains provenance fields:
#       _generated_by:  "aid-run-gates.sh@vX.Y.Z"
#       _generated_at:  ISO 8601 UTC timestamp
#       _command_log:   array of {name, command, exit_code, duration_ms} per gate
#   • System dependency: yq Go-based mikefarah variant (NOT Python kislyuk/yq)
#
# Gate command placeholders (substituted by resolve_placeholders before bash -c):
#   {plan_path}    — absolute realpath of source plan.md, or literal "null" for Fast Mode EPICs
#   {epic_id}      — EPIC identifier (e.g., E-037-1_2)
#   {run_id}       — Run identifier within EPIC (e.g., R-E037-1)
#   {base_commit}  — git SHA at EPIC start (recorded in fsm-state.yaml)
#   {plugin_path}  — absolute path of the installed aid-orchestrator plugin (P069 Step 12),
#                    resolved from .aid-o/config/plugin.yaml's plugin_path field (the same
#                    value /aid-init discovers and writes), falling back to $AID_PLUGIN_PATH
#                    when that file is absent. Lets a generated gate command reference this
#                    plugin's own scripts (e.g. aid-select-tests.sh) with a real, resolvable
#                    path instead of a bare script name with no PATH entry pointing at it.
#
# Unknown {token} → fail-loud exit 1 (introduce new tokens via resolve_placeholders).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-gate-runtime-baseline.sh
source "${SCRIPT_DIR}/lib/aid-gate-runtime-baseline.sh"
# shellcheck source=lib/aid-gitignore-backfill.sh
source "${SCRIPT_DIR}/lib/aid-gitignore-backfill.sh"
# shellcheck source=lib/aid-test-scheduler-report.sh
source "${SCRIPT_DIR}/lib/aid-test-scheduler-report.sh"
# shellcheck source=lib/aid-run-gates-report.sh
source "${SCRIPT_DIR}/lib/aid-run-gates-report.sh"
# shellcheck source=lib/aid-gate-row.sh
source "${SCRIPT_DIR}/lib/aid-gate-row.sh"
# shellcheck source=lib/aid-resume-artifact.sh
# THE shared continuation vocabulary (artifact basename, revision pair,
# pending-pointer resolution, gate-row binding key). Sourced fail-CLOSED: this
# file's live-job refusal and row-freshness checks are only as good as these
# definitions, and a missing lib that degraded to a local default is precisely
# the fail-open the duplicate constant produced.
if [[ ! -f "${SCRIPT_DIR}/lib/aid-resume-artifact.sh" ]]; then
  echo "ERROR: aid-run-gates.sh: missing ${SCRIPT_DIR}/lib/aid-resume-artifact.sh — refusing to run gates without the shared continuation definitions" >&2
  exit 2
fi
source "${SCRIPT_DIR}/lib/aid-resume-artifact.sh"

PLUGIN_VERSION="${PLUGIN_VERSION:-v2.16.0}"

# ─── Gate runtime baseline gitignore bootstrap (P063 Step 2) ────────────────
# Lazy, idempotent, LOCAL-ONLY: if `.aid-o/metrics/` (the gate runtime
# baseline library's data directory — owned by aid-gate-runtime-baseline.sh,
# Step 1) is not ALREADY excluded from git in this clone — whether via a
# brand-new project's shipped/tracked `.gitignore` or a previous run of this
# very function — add it (and its `.lock` glob) to `.git/info/exclude`
# (never the tracked `.gitignore`). Uses the exact same
# `git check-ignore -q <probe>` technique aid-plan-close-check.sh's Check 1
# uses for its own per-project gitignored-vs-committed detection.
#
# Lives HERE (not inside aid-gate-runtime-baseline.sh) because this plugin's
# own P063 EPIC plan.json scopes that library file to Step 1 only — Step 2
# integrates it without modifying it, calling only its already-published
# gate_baseline_update/gate_baseline_report_json/gate_baseline_show functions.
#
# Deliberately a no-op whenever AID_GATE_BASELINE_FILE is set — that env var
# is aid-gate-runtime-baseline.sh's own documented test-isolation seam (its
# bats suite points it at an isolated tmp file "without requiring a git
# checkout"); if a caller has opted into that isolation, this bootstrap must
# never write into the REAL clone's `.git/info/exclude` as a side effect.
# Also a no-op when git is unavailable or CWD isn't inside a git working
# tree — fails open, matching every public function in the two libraries
# this depends on.
aid_gate_baseline_ensure_gitignored() {
  [[ -n "${AID_GATE_BASELINE_FILE:-}" ]] && return 0
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  # Already excluded (tracked .gitignore OR a prior .git/info/exclude
  # backfill) — nothing to do.
  git check-ignore -q ".aid-o/metrics/__aid_gate_baseline_probe__" 2>/dev/null && return 0

  gitignore_exclude_append ".git/info/exclude" ".aid-o/metrics/"
  gitignore_exclude_append ".git/info/exclude" ".aid-o/metrics/*.lock"
  return 0
}

# Phase 2 (P037) — resolve {token} placeholders in gate commands via bash parameter expansion.
# Recognized tokens: {plan_path}, {epic_id}, {run_id}, {base_commit}, {plugin_path}.
# Unknown {<token>} → fail-loud exit 1 (silent pass-through is a debug trap).
#
# Args: $1=command string, $2=epic_id, $3=run_id, $4=base_commit, $5=plan_path (may be "null" or
#       empty), $6=plugin_path (P069 Step 12; may be empty — an empty value is deliberately NOT
#       substituted, so a command that actually references {plugin_path} falls through to the
#       unknown-token fail-loud check below rather than silently running a hollow/incomplete
#       command).
# Returns: resolved command string on stdout; exit 1 on unknown token.
resolve_placeholders() {
  local cmd="$1" epic="$2" run="$3" base="$4" plan="$5" plugin_path="${6:-}"

  cmd="${cmd//\{epic_id\}/$epic}"
  cmd="${cmd//\{run_id\}/$run}"
  cmd="${cmd//\{base_commit\}/$base}"
  cmd="${cmd//\{plan_path\}/$plan}"
  [[ -n "$plugin_path" ]] && cmd="${cmd//\{plugin_path\}/$plugin_path}"

  # Fail-loud on any remaining {<token>} — gate authors must not introduce unknown placeholders
  if [[ "$cmd" =~ \{[a-zA-Z_]+\} ]]; then
    local bad_token="${BASH_REMATCH[0]}"
    echo "ERROR: aid-run-gates.sh: unknown placeholder $bad_token in gate command" >&2
    echo "  Valid tokens: {plan_path}, {epic_id}, {run_id}, {base_commit}, {plugin_path}" >&2
    return 1
  fi

  printf '%s' "$cmd"
}

run_gate() {
  local gate_name="$1"
  local command="$2"
  local timeout_s="${3:-60}"
  local log_file="${4:-/dev/null}"

  local start_ms
  start_ms=$(date +%s%3N)

  local output exit_code=0
  # </dev/null: a stdin-consuming gate (ssh, cat, …) must NOT inherit the
  # driver's stdin — in run_all_gates that stdin is the here-string of remaining
  # gate names, and eating it silently starves every subsequent gate while
  # overall still reports pass (OBS-20260708-07).
  output=$(LC_ALL=C timeout "$timeout_s" bash -c "$command" </dev/null 2>&1) || exit_code=$?

  local end_ms
  end_ms=$(date +%s%3N)
  local duration_ms=$(( end_ms - start_ms ))

  local result="pass"
  [[ $exit_code -ne 0 ]] && result="fail"

  # Truncate output to 2000 chars for JSON safety
  local output_truncated="${output:0:2000}"
  # Escape for JSON
  output_truncated="${output_truncated//\\/\\\\}"
  output_truncated="${output_truncated//\"/\\\"}"
  output_truncated="${output_truncated//$'\n'/\\n}"
  output_truncated="${output_truncated//$'\t'/\\t}"

  local json="{\"gate\":\"${gate_name}\",\"result\":\"${result}\",\"exit_code\":${exit_code},\"duration_ms\":${duration_ms},\"output\":\"${output_truncated}\"}"
  echo "$json"

  # Log to file if provided
  [[ "$log_file" != "/dev/null" ]] && echo "$json" >> "$log_file"

  [[ $exit_code -eq 0 ]] && return 0 || return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# P076 Step 2 — the background gate path.
#
# A gate declaring `run_mode: background` (Step 1's field) does NOT run under a
# bare `timeout` in this shell. It runs through aid-job.sh, which already owns
# every piece this runner would otherwise have to re-implement: a session/
# process-group of its own (so a cancelled gate leaves no surviving child), a
# PID-reuse-safe liveness check, a hard deadline timer, and a terminal result
# bound to the HEAD/tree it started from. NOTHING here spawns, supervises or
# reaps a process itself — the registry's no-second-supervisor grep guard stays
# green by construction.
#
# The semantics are supervised-resumable-SYNCHRONOUS: the runner polls the job
# to completion inside its own invocation. Nothing is fire-and-return, there is
# no daemon and no cron. What background buys is not concurrency — it is that a
# runner killed mid-gate leaves a job that is still alive and still recording,
# so the next invocation re-attaches by command fingerprint and collects the
# result instead of paying for the whole suite a second time.
# ═══════════════════════════════════════════════════════════════════════════

# Poll cadence, heartbeat cadence, and the grace period added to a gate's own
# timeout before the runner stops believing the job's deadline timer. The
# defaults are the specified 5 s / 60 s / 30 s; the env vars exist so a test can
# exercise a full poll-and-heartbeat cycle in seconds instead of minutes.
AID_GATE_POLL_INTERVAL_SEC="${AID_GATE_POLL_INTERVAL_SEC:-5}"
AID_GATE_HEARTBEAT_SEC="${AID_GATE_HEARTBEAT_SEC:-60}"
AID_GATE_DEADLINE_GRACE_SEC="${AID_GATE_DEADLINE_GRACE_SEC:-30}"

# resolve_run_mode <execution_yaml> <gate_name>
#   Step 1's field, read here for the first time. Absent/null → "foreground",
#   which is what makes every pre-P076 consumer config behave identically.
resolve_run_mode() {
  local file="$1" gate="$2"
  yq ".gates.\"${gate}\".run_mode // \"foreground\"" "$file"
}

# _run_mode_declared <execution_yaml> <gate_name>
#   True iff the gate DECLARES a run_mode key at all. Not a second run_mode
#   reader — it resolves no value and applies no default; resolve_run_mode above
#   stays the only place that turns config into a mode. It exists because
#   resolve_run_mode deliberately collapses "absent" and "explicit foreground"
#   into the same answer, and the P076 Step 3 advice must stay silent for BOTH
#   explicit values: a PM who already wrote `run_mode: foreground` has made the
#   decision this advice exists to prompt.
_run_mode_declared() {
  local file="$1" gate="$2"
  [[ "$(yq ".gates.\"${gate}\" | has(\"run_mode\")" "$file" 2>/dev/null)" == "true" ]]
}

# validate_all_run_modes <execution_yaml>
#   Fail-loud sweep over EVERY defined gate, run BEFORE any gate command is
#   spawned — exactly like the gate-profile validation above it. A typo
#   (`backgroud`) must never degrade silently to the default: a background
#   declaration is a contract, and a run that quietly ignored it would produce
#   an unowned gate with no job record while reporting success.
validate_all_run_modes() {
  local file="$1" gate mode
  while IFS= read -r gate; do
    [[ -z "$gate" ]] && continue
    mode="$(resolve_run_mode "$file" "$gate")"
    case "$mode" in
      foreground|background) ;;
      *)
        echo "ERROR: aid-run-gates.sh: gate '${gate}' has invalid run_mode: '${mode}' (accepted values: foreground, background)" >&2
        return 1
        ;;
    esac
  done < <(yq '.gates | keys | .[]' "$file")
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# P076 Step 8 — service declarations.
#
# execution.yaml may carry an OPTIONAL `services:` map: the per-project
# declaration of long-lived processes a run needs standing up before its gates
# mean anything. It lives here, and not in some new file, because execution.yaml
# is already the per-project gate/runtime contract every project owns.
#
# Two authorities, deliberately, and they must agree:
#   • defaults/schemas/service-declaration.schema.json — the documentation and
#     test authority for the shape.
#   • _validate_services_config below — the RUNTIME enforcement, mirroring every
#     constraint in that schema plus the one JSON Schema cannot express across
#     sibling properties (duplicate port_env).
# scripts/tests/bats/test-service-declaration.bats drives BOTH from one shared
# case table, so the two cannot drift apart silently.
#
# Nothing in this step starts, stops or supervises a service. This is validation
# only: shape refused early, loudly, by service and field.
# ═══════════════════════════════════════════════════════════════════════════

# _svc_err <service> <message>
#   Every service violation names the service; the message names the field.
_svc_err() {
  echo "ERROR: aid-run-gates.sh: services: service '${1}': ${2}" >&2
}

# _svc_denied_port_env <name>
#   True when <name> is a variable the runner's own children depend on.
#
#   port_env names the variable carrying the per-run allocated port, and that
#   variable is exported into the environment of every service and gate command.
#   So the name is not merely cosmetic: `port_env: PATH` would set PATH to a port
#   number for the whole run and no command would resolve a binary again;
#   `BASH_ENV`, `LD_PRELOAD` or `NODE_OPTIONS` would point a code-loading hook at
#   one. This is refused at declaration time, in the same sweep as every other
#   shape rule, rather than at export time — the exporting step should inherit a
#   name it can already trust.
#
#   Matching is EXACT and CASE-SENSITIVE for the enumerated names, and
#   case-sensitive PREFIX for the open-ended families (LD_, DYLD_, BASH_FUNC_,
#   AID_). Case-sensitive because environment variables are: `Path` is not `PATH`
#   and nothing on the system honours it, so refusing the case variant would be a
#   false refusal that buys no safety. Prefix only where the family is genuinely
#   open-ended and libc/shell-version dependent (LD_PRELOAD, LD_AUDIT,
#   LD_LIBRARY_PATH, …), so an enumeration would silently go stale.
#
#   THE LIST ITSELF LIVES IN lib/aid-env-name-denylist.sh, because there are two
#   consumers — this declaration-time check and the export-time guard in
#   lib/aid-service.sh — and a second enumeration is a list that drifts. It did:
#   the export-time copy was missing the interpreter-hook and git families while
#   advertising that it covered them.
#
#   MIRRORED BY: defaults/schemas/service-declaration.schema.json
#   (port_env.allOf) — keep the two lists in the same order.
_svc_denied_port_env() {
  if ! declare -F aid_env_name_denied >/dev/null 2>&1; then
    # shellcheck source=lib/aid-env-name-denylist.sh
    source "${SCRIPT_DIR}/lib/aid-env-name-denylist.sh" 2>/dev/null || true
  fi
  if ! declare -F aid_env_name_denied >/dev/null 2>&1; then
    # FAIL CLOSED, and say why: with no denylist available every name is denied,
    # which refuses a legitimate declaration rather than admitting a hostile one.
    echo "ERROR: aid-run-gates.sh: the shared env-name denylist (${SCRIPT_DIR}/lib/aid-env-name-denylist.sh) could not be loaded — refusing every port_env name rather than exporting one unchecked" >&2
    return 0
  fi
  aid_env_name_denied "$1"
}

# _svc_backgrounding_form <start_cmd>
#   Echoes the backgrounding form found in a start_cmd, or nothing.
#
#   start_cmd MUST remain the foreground process of its job: the supervisor owns
#   the process group, and a command that backgrounds itself hands back a pid
#   owning nothing — the one violation that produces an UNSTOPPABLE orphan.
#
#   HONEST LIMIT: this is a SYNTACTIC lint, not a proof. It catches the obvious
#   forms — a trailing `&` (a trailing `&&` is not one, that is a shell syntax
#   error to be reported by the shell), and `nohup`, `disown` or `setsid` used as
#   a command word. It CANNOT see a command that daemonises inside itself (a
#   wrapper script that forks and exits, a `docker run -d` behind an npm script).
#   That case is deliberately not chased here: it is caught at runtime instead, by
#   the rule that a TERMINAL job whose probe still reports healthy is exactly the
#   daemonised-start_cmd violation. A clean result here means "no obvious
#   backgrounding syntax", never "proven foreground".
#
#   MIRRORED BY: defaults/schemas/service-declaration.schema.json
#   (start_cmd.allOf).
_svc_backgrounding_form() {
  local cmd="$1" trimmed
  # Regexes held in variables: an unquoted ERE containing ';', '|' and '(' is
  # fragile inline, and BASH_REMATCH still works through a variable.
  local re_amp='(^|[^&])&$'
  local re_word='(^|[[:space:];&|(])(nohup|disown|setsid)[[:space:]]'
  trimmed="${cmd%"${cmd##*[![:space:]]}"}"
  if [[ "$trimmed" =~ $re_amp ]]; then
    echo "a trailing '&'"
    return 0
  fi
  if [[ "$cmd" =~ $re_word ]]; then
    echo "'${BASH_REMATCH[2]}'"
    return 0
  fi
  return 1
}

# _validate_needs_services <execution_yaml> <declared_names_newline_separated>
#   A gate may declare `needs_services: [names]` — the services that must be
#   HEALTHY before that gate is allowed to run. The list is validated against the
#   DECLARED service names here, at the same config check as everything else,
#   because the failure it prevents is silent: a gate naming a service that no
#   longer exists (renamed, removed, typo'd) would otherwise either wait on
#   nothing or fail at gate time with a diagnosis about readiness when the truth
#   is a stale config line.
#
#   Runs even when there is NO `services:` block at all — that is precisely the
#   case where every name is unknown, and it is the loudest one worth catching.
#
#   rc 0 nothing to complain about · rc 1 a refused declaration (named).
_validate_needs_services() {
  local file="$1" declared="$2"
  local gate n tag
  [[ "$(yq 'has("gates")' "$file" 2>/dev/null || echo false)" == "true" ]] || return 0

  # ONE yq call for the whole check in the overwhelmingly common case: the gates
  # that carry the key at all. A project using none pays a single query.
  local carriers
  # `select(.value | has(...))` and NOT `select(.value | type == "!!map" and
  # has(...))`: the second form's operator precedence makes yq evaluate the
  # `and` as the right-hand side of the `==`, so it selects NOTHING and the whole
  # check silently passes — which is exactly how this was first written, and the
  # unknown name reached the gate loop instead of the config check. `has` on a
  # non-map gate value is simply false, so the type test bought nothing anyway.
  carriers="$(yq '.gates | to_entries[] | select(.value | has("needs_services")) | .key' "$file" 2>/dev/null || true)"
  [[ -n "$carriers" ]] || return 0

  while IFS= read -r gate; do
    [[ -z "$gate" ]] && continue
    tag="$(GATE="$gate" yq '.gates[strenv(GATE)].needs_services | tag' "$file" 2>/dev/null || echo '!!null')"
    if [[ "$tag" != '!!seq' ]]; then
      echo "ERROR: aid-run-gates.sh: gate '${gate}': 'needs_services' must be a list of declared service names (found ${tag#\!\!})" >&2
      return 1
    fi
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      if ! grep -qxF "$n" <<<"$declared"; then
        echo "ERROR: aid-run-gates.sh: gate '${gate}': 'needs_services' names '${n}', which is not a declared service. Declared services: ${declared//$'\n'/, }" >&2
        echo "  A gate cannot wait on a service this project does not declare — add it under 'services:' in ${file}, or drop the name." >&2
        return 1
      fi
    done < <(GATE="$gate" yq '.gates[strenv(GATE)].needs_services | .[]' "$file" 2>/dev/null)
  done <<< "$carriers"
  return 0
}

# _validate_services_config <execution_yaml>
#   Fail-loud sweep over every declared service, run at run_all entry BEFORE any
#   service or gate action. Also validates every gate's optional `needs_services`
#   list against the names this same sweep just accepted (see
#   _validate_needs_services) — the two belong to one config check, because a
#   reference is only checkable next to the thing it references.
#
#   Exit contract — three outcomes, not two:
#     0  nothing to complain about. Either there is no `services:` block (or an
#        empty one), in which case the function touches nothing and this is the
#        byte-identical path every pre-P076 project stays on; or every declared
#        service was inspected and is well-formed.
#     1  a declaration was inspected and REFUSED — the message names the service
#        and the field.
#     2  the config could NOT be inspected (file missing, yq missing, yq could
#        not parse the file). This is the fail-CLOSED outcome and it is
#        deliberately not 0: "I could not look" must never read as "it is fine".
#        run_all cannot reach it today — it guards with `[[ -f ]]` and
#        require_yq_mikefarah before calling — but the function is a
#        general-purpose primitive now, and a future second caller without those
#        guards must inherit a refusal, not a silent skip.
#   Every non-zero outcome is a refusal for callers that use `|| exit 1`.
_validate_services_config() {
  local file="$1"
  local svc key tag val
  local -a env_names=() env_owners=()

  # ── fail-closed preflight: distinguish "nothing to validate" from "could not
  # look at it". Both used to return 0; only the first one still does.
  if [[ ! -f "$file" ]]; then
    echo "ERROR: aid-run-gates.sh: services: cannot validate '${file}': file not found (refusing rather than assuming there are no services)" >&2
    return 2
  fi
  if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: aid-run-gates.sh: services: cannot validate '${file}': yq is not available (refusing rather than assuming there are no services)" >&2
    return 2
  fi

  local has_services
  if ! has_services="$(yq 'has("services")' "$file" 2>&1)"; then
    echo "ERROR: aid-run-gates.sh: services: cannot parse '${file}': ${has_services}" >&2
    return 2
  fi
  # No services block: there is nothing to validate about services, but a gate
  # naming one is still a config error — and the most obvious one there is.
  [[ "$has_services" == "true" ]] || { _validate_needs_services "$file" ""; return $?; }

  local root_tag
  if ! root_tag="$(yq '.services | tag' "$file" 2>&1)"; then
    echo "ERROR: aid-run-gates.sh: services: cannot read the services block of '${file}': ${root_tag}" >&2
    return 2
  fi
  case "$root_tag" in
    '!!null') _validate_needs_services "$file" ""; return $? ;;   # `services:` with no entries is the same as absent
    '!!map') ;;
    *)
      echo "ERROR: aid-run-gates.sh: services: must be a map of service name -> declaration (found ${root_tag#\!\!})" >&2
      return 1
      ;;
  esac

  # The sweep below reads service names line by line, so a name containing a
  # NEWLINE would arrive as two names and be blamed on the wrong field ("api":
  # declaration must be a map, found null). Catch it here, where the diagnosis is
  # still true: if the key list produces more lines than there are keys, some name
  # contains a newline. Fail-closed either way — this only replaces a misleading
  # refusal with an accurate one.
  local declared_keys key_lines
  declared_keys="$(yq '.services | keys | length' "$file")"
  key_lines="$(yq '.services | keys | .[]' "$file" | wc -l)"
  if [[ "$key_lines" != "$declared_keys" ]]; then
    echo "ERROR: aid-run-gates.sh: services: a service name contains a newline (${declared_keys} name(s) declared, ${key_lines} line(s) of text) — service names must match ^[a-z0-9][a-z0-9_-]*\$" >&2
    return 1
  fi

  # Every name this sweep ACCEPTS, for the needs_services cross-check below. It
  # is built from the accepted names rather than from a second yq read, so a gate
  # can never reference a service the sweep refused.
  local accepted_names=""

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue

    # Service name: it becomes part of log lines, job directory names and error
    # messages, so it stays filesystem- and shell-safe.
    if [[ ! "$svc" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
      _svc_err "$svc" "invalid service name (allowed: lowercase letters, digits, '_' and '-', starting with a letter or digit)"
      return 1
    fi

    tag="$(SVC="$svc" yq '.services[strenv(SVC)] | tag' "$file" 2>/dev/null || echo '!!null')"
    if [[ "$tag" != '!!map' ]]; then
      _svc_err "$svc" "declaration must be a map of fields (found ${tag#\!\!})"
      return 1
    fi

    # additionalProperties: false — an unknown key is a typo, and a typo that is
    # silently ignored is a contract the project believes it declared.
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      case "$key" in
        start_cmd|probe_cmd|stop_cmd|startup_deadline_seconds|max_lifetime_seconds|log_hint|restart_authorized|port_env) ;;
        *)
          _svc_err "$svc" "unknown field '${key}' (accepted: start_cmd, probe_cmd, stop_cmd, startup_deadline_seconds, max_lifetime_seconds, log_hint, restart_authorized, port_env)"
          return 1
          ;;
      esac
    done < <(SVC="$svc" yq '.services[strenv(SVC)] | keys | .[]' "$file")

    # Required fields.
    for key in start_cmd probe_cmd startup_deadline_seconds; do
      if [[ "$(SVC="$svc" K="$key" yq '.services[strenv(SVC)] | has(strenv(K))' "$file")" != "true" ]]; then
        _svc_err "$svc" "missing required field '${key}'"
        return 1
      fi
    done

    # Non-empty strings.
    for key in start_cmd probe_cmd stop_cmd log_hint; do
      [[ "$(SVC="$svc" K="$key" yq '.services[strenv(SVC)] | has(strenv(K))' "$file")" == "true" ]] || continue
      tag="$(SVC="$svc" K="$key" yq '.services[strenv(SVC)][strenv(K)] | tag' "$file")"
      val="$(SVC="$svc" K="$key" yq '.services[strenv(SVC)][strenv(K)]' "$file")"
      if [[ "$tag" != '!!str' || -z "$val" ]]; then
        _svc_err "$svc" "field '${key}' must be a non-empty string"
        return 1
      fi
    done

    # start_cmd stays in the FOREGROUND of its job. Syntactic lint only — see
    # _svc_backgrounding_form for exactly what it does and does not catch.
    local bgform
    if bgform="$(_svc_backgrounding_form "$(SVC="$svc" yq '.services[strenv(SVC)].start_cmd' "$file")")"; then
      _svc_err "$svc" "field 'start_cmd' must stay in the FOREGROUND of its job, but it contains ${bgform}: the supervisor owns the process group, and a command that backgrounds itself returns a pid owning nothing, so the run can no longer stop what it started. (This check is syntactic: it catches a trailing '&', 'nohup', 'disown' and 'setsid'; it cannot catch a command that daemonises internally, which is caught at runtime instead — a TERMINAL job whose probe still reports healthy.)"
      return 1
    fi

    # Positive integers.
    for key in startup_deadline_seconds max_lifetime_seconds; do
      [[ "$(SVC="$svc" K="$key" yq '.services[strenv(SVC)] | has(strenv(K))' "$file")" == "true" ]] || continue
      tag="$(SVC="$svc" K="$key" yq '.services[strenv(SVC)][strenv(K)] | tag' "$file")"
      val="$(SVC="$svc" K="$key" yq '.services[strenv(SVC)][strenv(K)]' "$file")"
      if [[ "$tag" != '!!int' || ! "$val" =~ ^[0-9]+$ || "$val" -lt 1 ]]; then
        _svc_err "$svc" "field '${key}' must be an integer >= 1"
        return 1
      fi
    done

    # Booleans. Absent restart_authorized defaults to false — repairs are opt-in
    # authority, so the default is the one that grants nothing.
    if [[ "$(SVC="$svc" yq '.services[strenv(SVC)] | has("restart_authorized")' "$file")" == "true" ]]; then
      tag="$(SVC="$svc" yq '.services[strenv(SVC)].restart_authorized | tag' "$file")"
      if [[ "$tag" != '!!bool' ]]; then
        _svc_err "$svc" "field 'restart_authorized' must be true or false"
        return 1
      fi
    fi

    # port_env: optional (a service on a fixed external port declares none and
    # allocation is skipped for it), but when present it must be a legal env var
    # name AND unowned by any other service.
    if [[ "$(SVC="$svc" yq '.services[strenv(SVC)] | has("port_env")' "$file")" == "true" ]]; then
      tag="$(SVC="$svc" yq '.services[strenv(SVC)].port_env | tag' "$file")"
      val="$(SVC="$svc" yq '.services[strenv(SVC)].port_env' "$file")"
      if [[ "$tag" != '!!str' || ! "$val" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        _svc_err "$svc" "field 'port_env' must be a valid environment variable name (^[A-Za-z_][A-Za-z0-9_]*\$)"
        return 1
      fi
      if _svc_denied_port_env "$val"; then
        _svc_err "$svc" "field 'port_env' must not name the reserved variable '${val}': it is exported into every service and gate command, and that variable controls how commands are found, parsed or loaded (or is AID's own runtime state) — setting it to a port number would break or hijack the whole run. Pick a service-specific name such as '$(printf '%s' "${svc^^}" | tr -c 'A-Z0-9_' '_')_PORT'."
        return 1
      fi
      local i
      for i in "${!env_names[@]}"; do
        if [[ "${env_names[$i]}" == "$val" ]]; then
          _svc_err "$svc" "field 'port_env' duplicates '${val}', already declared by service '${env_owners[$i]}' — one env var, one owner"
          return 1
        fi
      done
      env_names+=("$val")
      env_owners+=("$svc")
    fi
    accepted_names+="${svc}"$'\n'
  done < <(yq '.services | keys | .[]' "$file")

  _validate_needs_services "$file" "${accepted_names%$'\n'}" || return 1

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# P076 Step 10 — the service LIFECYCLE, wired into a real run.
#
# Step 8 gave the declaration a validator; Step 9 gave it a library. This is the
# step that makes either reachable, and its whole shape is one rule:
#
#   ACQUIRE ONCE before the gate loop, RELEASE ONCE after the report is written.
#
# Never per gate. Two gates sharing a service must not let the first one tear it
# down under the second (the Codex round's parallel-teardown finding), and a
# service is declared for the RUN, not for a gate — so a service no gate names is
# still brought up and taken down with the run.
#
# There is no completion hook anywhere in this file that a SIGKILLed runner can
# reach, so the crash safety net is not a hook: a RERUN sweeps at ENTRY, before it
# acquires, and `resume`/`done-advance` sweep for a run that is being wrapped up
# without a rerun. All of them call `aid_service_down_all` — ONE teardown
# definition, four callers.
#
# A project that declares no services makes ZERO of these calls: every one of
# them is behind `_svc_declared_count > 0`, and the library is not even sourced.
# ═══════════════════════════════════════════════════════════════════════════

# Set to 1 once this invocation has acquired services, so the release is exactly
# once and a release without an acquire is a no-op.
_SVC_ACQUIRED=0

# _svc_declared_count <execution_yaml> — how many services the config declares.
# ONE yq call; 0 for a config with no block, an empty block, or an unreadable
# file (the shape is refused upstream by _validate_services_config, which runs
# first — this function only decides whether the lifecycle applies at all).
_svc_declared_count() {
  local n
  n="$(yq '.services // {} | length' "$1" 2>/dev/null || echo 0)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# _svc_lib_load — source lib/aid-service.sh, fail CLOSED.
#   Called only when services are declared. A missing library with declared
#   services is not a run that can proceed: the gates would run against
#   infrastructure nobody started and report on it as if they had.
_svc_lib_load() {
  declare -F aid_service_up_all >/dev/null 2>&1 && return 0
  if [[ ! -f "${SCRIPT_DIR}/lib/aid-service.sh" ]]; then
    echo "ERROR: aid-run-gates.sh: services are declared but ${SCRIPT_DIR}/lib/aid-service.sh is missing — refusing to run gates against infrastructure nothing brought up" >&2
    return 1
  fi
  # shellcheck source=lib/aid-service.sh
  source "${SCRIPT_DIR}/lib/aid-service.sh" || return 1
  declare -F aid_service_up_all >/dev/null 2>&1
}

# _svc_stale_state_present <evidence_dir>
#   True when THIS run's evidence already holds service state that is not
#   accounted for as stopped — a registry entry in any non-stopped state, or a
#   job directory under the supervisor's layout. That is the signature of a run
#   that died before its release, and it is the only thing the entry sweep needs
#   to decide on: `aid_service_down_all` does the actual reasoning.
_svc_stale_state_present() {
  local ev="$1" reg="$1/services.json" jr="$1/service-jobs"
  if [[ -f "$reg" ]] \
     && jq -e '[.services[]? | select(.state != "stopped")] | length > 0' "$reg" >/dev/null 2>&1; then
    return 0
  fi
  # if/fi rather than an `&&` chain: this file runs under `set -e`, and a
  # trailing false `&&` list as a statement is the shape that exits a script.
  if [[ -d "$jr" ]]; then
    if compgen -G "${jr}/*/*/job.json" >/dev/null 2>&1; then return 0; fi
  fi
  return 1
}

# ─── WHO OWNS THIS RUN'S SERVICES (P076 Step 10 fix) ────────────────────────
# `_svc_stale_state_present` answers "is there service state that is not
# stopped". That is NOT the question the entry sweep needs, and the difference
# is destructive: a run that is HEALTHY and mid-gates looks exactly like a run
# that died with its services up. Asking only the first question means a second
# `run-all` entering the same evidence directory tears a LIVE run's database
# down under its running gates.
#
# So the acquire path proves the previous owner is GONE before it touches
# anything, and it proves it about a process rather than about a state string.
# The claim record is written BEFORE the acquire, so any service state that
# exists was preceded by a live claim — there is no window in which state exists
# and no owner is recorded.
#
# WHAT IS NOT HERE, deliberately: no `flock` held across the run. I measured the
# reason rather than assuming it — a descriptor opened with `exec {fd}>>lock` is
# NOT close-on-exec in bash 5.2, so a run-scoped lock is inherited by every
# service `aid-job.sh` detaches, and the lock then outlives the runner for the
# whole lifetime of the service (verified: parent locks, spawns a setsid'd
# child, closes its own fd — the lock is still held). That converts a crash into
# a permanently unrunnable project, which is worse than what it prevents. The
# claim-before-acquire ordering gives the same mutual exclusion for the case
# that matters without putting a descriptor into a detached process.
#
# THE ONE CASE THAT DOES NOT FAIL CLOSED, named: service state with NO claim
# record. It is swept, as before. Every acquire in this file writes a claim
# first, so an unclaimed registry is either from a build older than this change
# or hand-written — never a live run of this code. Refusing there would make the
# crash recovery unreachable for exactly the runs it exists for.
_SVC_OWNER_CLAIMED=0
_svc_owner_file() { printf '%s/services.owner.json' "$1"; }

# _svc_boot_id — an identity for THIS boot, so a recorded pid from before a
# reboot is provably dead rather than ambiguously reused. Empty where the kernel
# does not publish one; an empty value is simply not compared.
_svc_boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || true; }

# _svc_proc_starttime <pid> — field 22 of /proc/<pid>/stat (jiffies since boot),
# the field that distinguishes a live pid from a RECYCLED one. Parsed after the
# last ')' because a process name may contain spaces and parentheses.
_svc_proc_starttime() {
  local pid="$1" line rest
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -r "/proc/${pid}/stat" ]] || return 1
  line="$(cat "/proc/${pid}/stat" 2>/dev/null)" || return 1
  rest="${line##*') '}"
  local -a f=()
  read -r -a f <<<"$rest"
  # After the comm field the remainder starts at field 3, so field 22 is index 19.
  [[ -n "${f[19]:-}" ]] || return 1
  printf '%s' "${f[19]}"
}

# _svc_owner_live <evidence_dir>
#   rc 0  another gate runner is — or may still be — managing these services
#   rc 1  no owner, or the recorded owner is PROVABLY gone
#   Every "cannot tell" answers rc 0: refusing to start is recoverable, tearing
#   down a live run's infrastructure is not.
_svc_owner_live() {
  local ev="$1" f pid rec_start rec_boot rec_host cur_start now_boot now_host
  f="$(_svc_owner_file "$ev")"
  [[ -f "$f" ]] || return 1
  pid="$(jq -r '.pid // empty' "$f" 2>/dev/null || true)"
  if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    # A claim record we cannot read is not a claim we can dismiss.
    return 0
  fi
  [[ "$pid" == "$$" ]] && return 1   # our own claim from an earlier phase
  rec_start="$(jq -r '.starttime // empty' "$f" 2>/dev/null || true)"
  rec_boot="$(jq -r '.boot_id // empty'   "$f" 2>/dev/null || true)"
  rec_host="$(jq -r '.host // empty'      "$f" 2>/dev/null || true)"
  now_boot="$(_svc_boot_id)"
  now_host="$(hostname 2>/dev/null || true)"
  # A pid from another machine says nothing about any process here.
  [[ -n "$rec_host" && -n "$now_host" && "$rec_host" != "$now_host" ]] && return 0
  # Same machine, different boot: whatever held that pid did not survive.
  [[ -n "$rec_boot" && -n "$now_boot" && "$rec_boot" != "$now_boot" ]] && return 1
  if cur_start="$(_svc_proc_starttime "$pid")"; then
    [[ -n "$rec_start" && "$cur_start" != "$rec_start" ]] && return 1  # pid recycled
    return 0
  fi
  # No readable /proc entry. On Linux the absence of /proc/<pid> is proof; a
  # /proc/<pid> we merely cannot READ (another user, hidepid) is not.
  if [[ -d /proc ]]; then
    [[ -e "/proc/${pid}" ]] && return 0
    return 1
  fi
  ps -p "$pid" -o pid= >/dev/null 2>&1 && return 0
  return 1
}

# _svc_owner_describe <evidence_dir> — one line for the refusal message.
_svc_owner_describe() {
  jq -r '"pid " + (.pid|tostring) + ", claimed at " + (.claimed_at // "?")
         + ", run " + (.run_id // "?")' "$(_svc_owner_file "$1")" 2>/dev/null \
    || printf 'an unreadable claim record'
}

# _svc_owner_claim <evidence_dir> <run_id> — atomic tmp+mv, so a concurrent
# reader sees the old record or the new one and never half of one.
_svc_owner_claim() {
  local ev="$1" run="${2:-}" f tmp
  f="$(_svc_owner_file "$ev")"
  tmp="${f}.tmp.$$"
  jq -n --arg pid "$$" --arg st "$(_svc_proc_starttime "$$" || true)" \
        --arg boot "$(_svc_boot_id)" --arg host "$(hostname 2>/dev/null || true)" \
        --arg run "$run" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema:"aid.services.owner/1", pid:($pid|tonumber), starttime:$st,
          boot_id:$boot, host:$host, run_id:$run, claimed_at:$at}' \
        > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  _SVC_OWNER_CLAIMED=1
  return 0
}

# _svc_owner_clear <evidence_dir> — released with the services it covered.
_svc_owner_clear() {
  (( _SVC_OWNER_CLAIMED == 1 )) || return 0
  _SVC_OWNER_CLAIMED=0
  rm -f "$(_svc_owner_file "$1")" 2>/dev/null || true
  return 0
}

# _svc_manual_commands <evidence_dir> <execution_yaml>
#   The commands a human would run to finish a teardown this run could not. Read
#   from the registry, which is the only record of what was allocated — printed
#   verbatim so the line can be pasted rather than reconstructed.
_svc_manual_commands() {
  local ev="$1" reg="$1/services.json"
  [[ -f "$reg" ]] || return 0
  jq -r --arg job "${SCRIPT_DIR}/aid-job.sh" '
    .services // {} | to_entries[] | select(.value.state != "stopped") |
    "  service " + .key + ":"
    + (if (.value.stop_cmd // "") != "" then "\n    " + .value.stop_cmd else "" end)
    + (if (.value.job_id // "") != "" then
         "\n    bash " + $job + " cancel --jobs-dir " + (.value.jobs_dir // "?") + " --id " + .value.job_id
       else "" end)
  ' "$reg" 2>/dev/null || true
}

# _svc_release_run <evidence_dir> <execution_yaml>
#   THE release. Idempotent, called exactly once per invocation that acquired,
#   and NEVER able to un-write evidence: it runs after the report is written, and
#   a failure is a warning naming the manual commands — not a failed run.
_svc_release_run() {
  local ev="$1" yaml="$2"
  (( _SVC_ACQUIRED == 1 )) || return 0
  _SVC_ACQUIRED=0
  if ! aid_service_down_all "$ev" "$yaml"; then
    echo "WARN: aid-run-gates.sh: service teardown did not fully succeed — at least one declared service still answers its probe. The gate report is already written and is NOT affected. Finish the teardown by hand:" >&2
    _svc_manual_commands "$ev" "$yaml" >&2
  fi
  # The claim covered the services this invocation owned; they are down, so it
  # is dropped LAST — a claim removed before the teardown would let a runner
  # entering in that window sweep a service that is still being stopped.
  _svc_owner_clear "$ev"
  return 0
}

# _gate_expect_p95_seconds <gate_name>
#   The gate's runtime-baseline p95 in SECONDS for aid-job.sh's --expect-p95,
#   but only once the baseline holds >= 3 non-censored samples (the same
#   "enough data to quote" threshold gate_baseline_recommend_timeout uses).
#   Echoes nothing for a young gate, so the flag is simply omitted and the job
#   record legitimately lacks the field.
_gate_expect_p95_seconds() {
  local gate_name="$1" bj p95 nc
  bj="$(gate_baseline_report_json "$gate_name" 2>/dev/null || true)"
  [[ -z "$bj" || "$bj" == "null" ]] && return 0
  p95="$(jq -r '.p95_ms // "null"' <<<"$bj" 2>/dev/null || echo null)"
  nc="$(jq -r '.non_censored_samples_count // 0' <<<"$bj" 2>/dev/null || echo 0)"
  [[ "$p95" =~ ^[0-9]+$ ]] || return 0
  [[ "$nc" =~ ^[0-9]+$ ]] || return 0
  if (( nc < 3 )); then return 0; fi
  printf '%s' "$(( (p95 + 999) / 1000 ))"
  return 0
}

# _bg_fail_row <gate_name> <reason> <message> [job_id]
#   The gate row for a background gate that never got a supervised job at all.
#   Deliberately a plain `fail` in the existing vocabulary — the reason field
#   says WHY, and no consumer needs a new result enum to handle it.
_bg_fail_row() {
  local gate_name="$1" reason="$2" message="$3" job_id="${4:-}"
  jq -nc --arg g "$gate_name" --arg r "$reason" --arg o "$message" \
        --arg jid "$job_id" \
    '{gate:$g, result:"fail", exit_code:1, duration_ms:0, output:$o,
      reason:$r, job_id:(if $jid == "" then null else $jid end),
      job_state:"none"}'
}

# ─── P076 Step 4 — the eager continuation pointer ───────────────────────────
# One artifact per RUN (one path), written BEFORE a background job is spawned
# and deleted only once the run's LAST outstanding background job has been
# collected. It exists because a controller that dies mid-EXECUTE cannot write
# anything on its way out: "a resume is required" must be derivable from what
# the controller provably LEFT BEHIND. `awaiting_host_resume` is therefore never
# stored anywhere — consumers derive it from (artifact exists) AND (no liveness
# signal). These globals are populated once in run_all_gates(); they are read
# (never written) inside run_background_gate, which runs in a command
# substitution subshell.
# AID_RESUME_ARTIFACT_BASENAME is defined ONCE, in lib/aid-resume-artifact.sh,
# and sourced above. It used to be declared here AND in aid-fsm.sh: two string
# literals with no shared source and no test binding them, so renaming one made
# the FSM's live-job refusal evaluate an empty glob and return 0 — a guard whose
# failure mode was indistinguishable from "nothing to guard".
_RESUME_ARTIFACT=""
_RESUME_PLAN_ID=""
_RESUME_EPIC_ID=""
_RESUME_RUN_ID=""
_RESUME_SAFE_NEXT_ACTION=""
# aid-job.sh's terminal vocabulary, verbatim (see its `_derive_state` / the
# states its result.json records). Never re-derived, never abbreviated.
AID_JOB_TERMINAL_STATES='["terminal_pass","terminal_fail","timed_out","cancelled"]'

# _job_head_drifted <recorded_head> <current_head>
#   THE single revision-drift judgement in this file, shared by the two places
#   that need it: re-attaching a supervised job, and restoring a checkpointed
#   gate row. Returns 0 (drifted) only when both heads are known, the recorded
#   one is a real sha ("none" is the supervisor's own no-git marker), and they
#   differ. Unknowable → not drifted: a repo with no git is not a moved tree.
_job_head_drifted() {
  local rec="$1" cur="$2"
  [[ -n "$rec" && -n "$cur" && "$rec" != "none" && "$rec" != "$cur" ]]
}

# _job_result_stale <job_sh> <jobs_dir> <job_id> <repo>
#   rc 0 iff the job has a TERMINAL result that the CURRENT tree did not earn.
#
#   THE freshness judgement for replaying an existing job's result, and it is
#   deliberately not a third notion of "current": it asks `aid-job.sh collect
#   --require-current`, the same primitive `aid-fsm.sh resume` asks, which
#   compares the recorded start HEAD *and* start TREE and answers rc 4 when
#   either moved.
#
#   Why HEAD alone was not enough (CP3 blocking finding, reproduced in both
#   directions): the ordinary state of a gate re-run is a tree that MOVED without
#   a commit. Head-only re-attach therefore replayed `terminal_pass` for a
#   command that now fails (a green report for a broken tree), and replayed
#   `terminal_fail` after a gate-fixer had already repaired the tree (a fix loop
#   that burns its iterations on an already-green gate and can never converge).
#
#   It answers exactly one question — "did the tree that produced this result
#   move?" — and the two callers do DIFFERENT things with the answer: the
#   re-attach decision refuses to replay on it, while the post-supervision read
#   only records it. The judgement is shared; the consequence is not.
#
#   A job with NO terminal result is never "stale": a still-LIVE job whose tree
#   has not moved must keep re-attaching — that is the whole crash-resume story —
#   and drift on a live job is judged by the head/fingerprint check at the call
#   site, exactly as before.
_job_result_stale() {
  local job_sh="$1" jobs_dir="$2" job_id="$3" repo="$4" rc=0
  [[ -f "${jobs_dir}/${job_id}/result.json" ]] || return 1
  local -a args=(collect --jobs-dir "$jobs_dir" --id "$job_id")
  [[ -n "$repo" ]] && args+=(--repo "$repo")   # array, so a path with spaces survives
  args+=(--require-current)
  bash "$job_sh" "${args[@]}" >/dev/null 2>&1 || rc=$?
  (( rc == 4 ))
}

# _resume_artifact_write <job_id> <gate_name> <fingerprint> <jobs_dir>
#   Atomic (mktemp + mv) rewrite of the run's ONE continuation pointer.
#   rc 1 on any failure — the caller must then refuse to leave a background job
#   running that nothing points at.
_resume_artifact_write() {
  local job_id="$1" gate_name="$2" fp="$3" jobs_dir="$4"
  [[ -n "$_RESUME_ARTIFACT" ]] || return 1
  # The schema forbids '<' in safe_next_action so an unresolved placeholder can
  # never persist. Enforce it at the writer too: a pointer that would not
  # validate is not written, and the gate refuses rather than spawning.
  [[ "$_RESUME_SAFE_NEXT_ACTION" != *"<"* ]] || return 1
  [[ -n "$_RESUME_SAFE_NEXT_ACTION" ]] || return 1
  local dir; dir="$(dirname "$_RESUME_ARTIFACT")"
  [[ -d "$dir" ]] || return 1
  local tmp
  tmp="$(mktemp "${_RESUME_ARTIFACT}.XXXXXX" 2>/dev/null)" || return 1
  if ! jq -nc \
        --arg plan "${_RESUME_PLAN_ID:-unknown}" \
        --arg epic "$_RESUME_EPIC_ID" \
        --arg run "$_RESUME_RUN_ID" \
        --arg job "$job_id" \
        --arg jobs "$jobs_dir" \
        --arg gate "$gate_name" \
        --arg fp "$fp" \
        --argjson terminal "$AID_JOB_TERMINAL_STATES" \
        --arg next "$_RESUME_SAFE_NEXT_ACTION" \
        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{schema:"aid-auto-resume/1", plan_id:$plan, epic_id:$epic, run_id:$run,
          job_id:$job, jobs_dir:$jobs, gate:$gate, command_fingerprint:$fp,
          expected_terminal_states:$terminal, safe_next_action:$next,
          created_at:$now}' > "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
  mv -f "$tmp" "$_RESUME_ARTIFACT" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  return 0
}

# _resume_map_field <field> <value>
#   Best-effort pointer maintenance on the active-runs entry. The ARTIFACT is
#   authoritative; the map is presentation, so a failure here warns and never
#   fails the gate (the accepted error-handling split for this step).
_resume_map_field() {
  local field="$1" value="$2"
  [[ -n "$_RESUME_EPIC_ID" ]] || return 0
  [[ -f "${SCRIPT_DIR}/aid-fsm.sh" ]] || return 0
  if ! bash "${SCRIPT_DIR}/aid-fsm.sh" active-runs set "$_RESUME_EPIC_ID" "$field" "$value" >/dev/null 2>&1; then
    echo "WARNING: aid-run-gates.sh: could not update active-runs field '${field}' for ${_RESUME_EPIC_ID} — the resume artifact at ${_RESUME_ARTIFACT} remains authoritative" >&2
  fi
  return 0
}

# _resume_jobs_still_live <jobs_dir>
#   Cheap `aid-job.sh status` sweep over the run's jobs dir. rc 0 iff at least
#   one supervised job is still started/running — i.e. the continuation pointer
#   must NOT be deleted yet.
_resume_jobs_still_live() {
  local jobs_dir="$1" d id st
  [[ -d "$jobs_dir" ]] || return 1
  for d in "$jobs_dir"/*/; do
    [[ -f "${d}job.json" ]] || continue
    id="$(basename "$d")"
    st="$(bash "${SCRIPT_DIR}/aid-job.sh" status --jobs-dir "$jobs_dir" --id "$id" 2>/dev/null || echo unknown)"
    case "$st" in started|running) return 0 ;; esac
  done
  return 1
}

# run_background_gate <gate_name> <resolved_cmd> <timeout_s> <attempt>
#                     <jobs_dir> <timeline_file> <repo>
#   Drop-in replacement for run_gate() on a background gate: emits ONE gate-row
#   JSON object on stdout with the same shape every other row has (plus job_id
#   and job_state), returns 0 iff the gate passed.
#
#   Branch outcomes, exhaustively:
#     • a job dir for THIS attempt exists, same fingerprint, same start HEAD
#         – still live      → re-attach and poll
#         – already terminal → `collect` idempotently; the suite NEVER re-runs
#     • a job dir exists but the fingerprint or the start HEAD moved
#                           → cancel it, ARCHIVE the dir to `.superseded-<epoch>`
#                             (aid-job.sh run refuses an existing dir, so the
#                             deterministic id has to be freed), start fresh
#     • no job dir          → start fresh
#
#   The id is ALWAYS the deterministic `<gate>-attempt-<N>`: that keeps the jobs
#   root FLAT (`jobs/<gate>-attempt-N/`), which is the only topology the
#   supervisor's watchdog can scan (it reads immediate children only), and it
#   keeps each retry attempt a distinct job — so a failed terminal job is never
#   re-attached as the NEXT attempt's result.
run_background_gate() {
  local gate_name="$1" command="$2" timeout_s="$3" attempt="$4" \
        jobs_dir="$5" timeline_file="$6" repo="$7"

  local job_sh="${SCRIPT_DIR}/aid-job.sh"
  if [[ ! -f "$job_sh" ]]; then
    echo "ERROR: aid-run-gates.sh: gate '${gate_name}' declares run_mode: background but the supervisor is unavailable at ${job_sh} — refusing to fall back to the unowned foreground path" >&2
    _bg_fail_row "$gate_name" "job_supervisor_unavailable" "aid-job.sh not found at ${job_sh}"
    return 1
  fi

  mkdir -p "$jobs_dir" 2>/dev/null || true
  local job_id="${gate_name}-attempt-${attempt}"
  local job_dir="${jobs_dir}/${job_id}"

  # The EXACT argv the supervisor will run — and therefore the exact argv the
  # fingerprint has to cover. Computed by aid-job.sh itself: one definition of
  # the sha256-over-NUL-joined-argv formula, never a copy of it here.
  local -a job_argv=(bash -c "$command")
  # stdout and stderr captured SEPARATELY via a temp file — an assignment made
  # inside a command substitution happens in a subshell and would never reach
  # this scope.
  local fp="" fp_err="" fp_rc=0 fp_errfile
  fp_errfile="$(mktemp)"
  fp="$(bash "$job_sh" fingerprint -- "${job_argv[@]}" 2>"$fp_errfile")" || fp_rc=$?
  fp_err="$(cat "$fp_errfile" 2>/dev/null || true)"
  rm -f "$fp_errfile"
  if (( fp_rc != 0 )) || [[ -z "$fp" ]]; then
    echo "ERROR: aid-run-gates.sh: gate '${gate_name}' — aid-job.sh fingerprint failed (exit ${fp_rc}): ${fp_err}" >&2
    _bg_fail_row "$gate_name" "job_fingerprint_failed" "${fp_err}" "$job_id"
    return 1
  fi

  # `replayed_result` is the ONE thing that decides whether the working tree gets
  # a veto over this gate's outcome, and it is a statement about provenance, not
  # about timing: it is 1 only when this invocation found an ALREADY-TERMINAL job
  # and reported a result it never watched being produced. A job this invocation
  # spawned, or one it re-attached to while still live and polled to completion,
  # is watched — its result is this run's own work.
  local replayed_result=0
  local reattach=0
  if [[ -d "$job_dir" && -f "$job_dir/job.json" ]]; then
    local rec_fp rec_head cur_head drift_reason=""
    rec_fp="$(jq -r '.command_fingerprint // ""' "$job_dir/job.json" 2>/dev/null || echo "")"
    rec_head="$(jq -r '.start_head // ""' "$job_dir/job.json" 2>/dev/null || echo "")"
    cur_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
    if [[ "$rec_fp" != "$fp" ]]; then
      drift_reason="command_fingerprint_mismatch"
    elif _job_head_drifted "$rec_head" "$cur_head"; then
      # Same command, but HEAD moved since the job started. Re-attaching would
      # answer a question about a revision nobody is asking about any more.
      drift_reason="start_head_moved"
    elif _job_result_stale "$job_sh" "$jobs_dir" "$job_id" "$repo"; then
      # Same command, same HEAD — but the job's TERMINAL result was produced
      # against a different working tree. That result is not this run's evidence,
      # so the job is superseded and the gate genuinely re-runs. Judged by the
      # supervisor's own `collect --require-current`, so the runner and `resume`
      # cannot disagree about what "current" means.
      drift_reason="result_tree_moved"
    fi
    if [[ -n "$drift_reason" ]]; then
      local sup_ts sup_dir sup_log
      sup_ts="$(date -u +%s)"
      sup_dir="${job_dir}.superseded-${sup_ts}"
      sup_log="${jobs_dir}/${job_id}.superseded-${sup_ts}.log"
      {
        echo "aid-run-gates.sh: gate '${gate_name}' job '${job_id}' superseded (${drift_reason})"
        echo "  recorded fingerprint: ${rec_fp}"
        echo "  current fingerprint:  ${fp}"
        echo "  recorded start_head:  ${rec_head}"
        echo "  current HEAD:         ${cur_head}"
        echo "-- cancel --"
        bash "$job_sh" cancel --jobs-dir "$jobs_dir" --id "$job_id" 2>&1 || true
        echo "-- archive to ${sup_dir} --"
        mv "$job_dir" "$sup_dir" 2>&1 || true
      } >"$sup_log" 2>&1 || true
      log_event "$timeline_file" "gate_job_superseded" gate="$gate_name" \
        job_id="$job_id" reason="$drift_reason" archived_to="$sup_dir" log="$sup_log"
      # If the archive did not happen the id is still occupied; `run` below
      # fails loudly rather than pretending a stale job is this attempt.
    else
      reattach=1
    fi
  fi

  # ── P076 Step 4: PRE-SPAWN pointer ───────────────────────────────────────
  # Written BEFORE aid-job.sh is asked to start anything, carrying job_id
  # "pending" plus the jobs_dir and the command fingerprint. That closes the
  # only crash window that could produce a started job nothing points at: a
  # death between this write and the spawn leaves a pointer that says "a job
  # with THIS fingerprint was about to be started HERE", which a resume can
  # resolve by scanning the jobs dir (found → collect; none → nothing ran).
  # An unwritable evidence directory refuses the gate HERE — before the spawn —
  # because an unresumable background job must never come into existence.
  if ! _resume_artifact_write "pending" "$gate_name" "$fp" "$jobs_dir"; then
    echo "ERROR: aid-run-gates.sh: gate '${gate_name}' — could not write the continuation pointer at '${_RESUME_ARTIFACT:-<unset>}'; refusing to spawn a background job nothing can resume" >&2
    _bg_fail_row "$gate_name" "resume_artifact_write_failed" "could not write ${_RESUME_ARTIFACT:-<unset>} — no background job was started" "$job_id"
    return 1
  fi

  if (( reattach )); then
    local pre_state
    pre_state="$(bash "$job_sh" status --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null || echo unknown)"
    # Already terminal at re-attach time → whatever this invocation reports for
    # it is a REPLAY of a result produced before this invocation existed.
    case "$pre_state" in
      terminal_pass|terminal_fail|timed_out|cancelled) replayed_result=1 ;;
    esac
    log_event "$timeline_file" "gate_job_reattached" gate="$gate_name" \
      job_id="$job_id" state="$pre_state" attempt="$attempt"
  else
    local -a run_args=(run --jobs-dir "$jobs_dir" --id "$job_id"
                       --label "$gate_name" --deadline "$timeout_s")
    local p95_sec
    p95_sec="$(_gate_expect_p95_seconds "$gate_name")"
    [[ -n "$p95_sec" ]] && run_args+=(--expect-p95 "$p95_sec")
    run_args+=(-- "${job_argv[@]}")

    local start_err start_rc=0
    start_err="$(bash "$job_sh" "${run_args[@]}" 2>&1 >/dev/null)" || start_rc=$?
    if (( start_rc != 0 )); then
      # A background declaration is a contract. The supervisor's own stderr is
      # surfaced verbatim; there is deliberately NO fallback to run_gate().
      echo "ERROR: aid-run-gates.sh: gate '${gate_name}' run_mode: background — aid-job.sh run failed (exit ${start_rc}): ${start_err}" >&2
      _bg_fail_row "$gate_name" "job_start_failed" "aid-job.sh run exit ${start_rc}: ${start_err}" "$job_id"
      return 1
    fi
    log_event "$timeline_file" "gate_job_started" gate="$gate_name" \
      job_id="$job_id" attempt="$attempt" deadline_sec="$timeout_s" \
      jobs_dir="$jobs_dir"
  fi

  # ── P076 Step 4: POST-SPAWN rewrite ──────────────────────────────────────
  # Immediately after the job exists, the same single path is atomically
  # rewritten with the REAL job id. A crash in the window between the spawn and
  # this line still leaves the pending pointer, and the fingerprint scan covers
  # it — so no window produces a job without a pointer, only a pointer that is
  # one field less precise.
  #
  # If THIS write fails the job is already running, so refusing is not enough:
  # the just-started job is CANCELLED (fail closed WITH cleanup — an
  # unresumable background job must not keep running). A cancel that also fails
  # is reported with the exact manual command.
  if ! _resume_artifact_write "$job_id" "$gate_name" "$fp" "$jobs_dir"; then
    echo "ERROR: aid-run-gates.sh: gate '${gate_name}' — could not rewrite the continuation pointer at '${_RESUME_ARTIFACT:-<unset>}' with job id '${job_id}'; cancelling the job rather than leaving it unresumable" >&2
    local _cancel_rc=0
    bash "$job_sh" cancel --jobs-dir "$jobs_dir" --id "$job_id" >/dev/null 2>&1 || _cancel_rc=$?
    if (( _cancel_rc != 0 )); then
      echo "ERROR: aid-run-gates.sh: the compensating cancel ALSO failed (exit ${_cancel_rc}). Cancel it by hand: bash ${job_sh} cancel --jobs-dir ${jobs_dir} --id ${job_id}" >&2
    fi
    _bg_fail_row "$gate_name" "resume_artifact_write_failed" "could not record job ${job_id} in ${_RESUME_ARTIFACT:-<unset>}; job cancelled (cancel exit ${_cancel_rc})" "$job_id"
    return 1
  fi
  # Pointer maintenance on the live map entry — warn-only by design.
  _resume_map_field resume_artifact "$_RESUME_ARTIFACT"

  # ── poll to completion, inside THIS invocation ────────────────────────────
  local poll_start=$SECONDS last_heartbeat=$SECONDS state=""
  local grace_budget=$(( timeout_s + AID_GATE_DEADLINE_GRACE_SEC ))
  while true; do
    state="$(bash "$job_sh" status --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null || echo unknown)"
    case "$state" in
      terminal_pass|terminal_fail|timed_out|cancelled) break ;;
      lost)
        # The owned process vanished without a terminal record. That proves no
        # outcome, so it is never a pass and never an ordinary command failure.
        break
        ;;
    esac

    local elapsed=$(( SECONDS - poll_start ))
    # The deadline is the JOB's, not this invocation's: a re-attached job that
    # has already been running for an hour must not be handed a fresh timeout
    # window. Measured from the job's own started_epoch when it is readable,
    # falling back to this poll loop's elapsed time.
    local job_started job_elapsed="$elapsed"
    job_started="$(jq -r '.started_epoch // empty' "$job_dir/job.json" 2>/dev/null || true)"
    if [[ "$job_started" =~ ^[0-9]+$ ]]; then
      job_elapsed=$(( $(date -u +%s) - job_started ))
    fi
    if (( timeout_s > 0 && job_elapsed > grace_budget )); then
      # The job's OWN deadline timer is authoritative for killing. Being this
      # far past due with no terminal result means that timer did not land, so
      # the runner takes over: cancel (group-owned — no child survives) and
      # read whatever terminal record that produced.
      log_event "$timeline_file" "gate_job_deadline_exceeded" gate="$gate_name" \
        job_id="$job_id" elapsed_sec="$job_elapsed" poll_elapsed_sec="$elapsed" \
        deadline_sec="$timeout_s" grace_sec="$AID_GATE_DEADLINE_GRACE_SEC"
      bash "$job_sh" cancel --jobs-dir "$jobs_dir" --id "$job_id" >/dev/null 2>&1 || true
      state="$(bash "$job_sh" status --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null || echo lost)"
      break
    fi

    if (( SECONDS - last_heartbeat >= AID_GATE_HEARTBEAT_SEC )); then
      last_heartbeat=$SECONDS
      # The progress signal a stall consumer reads: a long gate that is still
      # polling is WORKING, not hung.
      log_event "$timeline_file" "gate_job_heartbeat" gate="$gate_name" \
        job_id="$job_id" state="$state" elapsed_sec="$elapsed"
    fi

    sleep "$AID_GATE_POLL_INTERVAL_SEC"
  done

  # `collect` is the idempotent terminal read — it NEVER relaunches, which is
  # what makes a crash cost zero re-execution: a job that finished while nobody
  # was watching is simply collected.
  #
  # `--require-current` is passed ONLY on the replay path, and the distinction is
  # the whole point. Two different questions are asked at two different places:
  #
  #   line ~494, before anything is spawned: "may I REPLAY a result I did not
  #     watch?" The tree must answer that — a terminal record from an earlier
  #     invocation is evidence about the tree it ran against, and replaying it
  #     over a moved tree is what produced the stale PASS and the fix loop that
  #     could not converge. That check stands, unchanged.
  #
  #   here, after this invocation spawned (or re-attached to) the job, supervised
  #     it and polled it to completion: "may I REPORT a result I DID watch?" The
  #     tree has no standing to veto that. The command ran, it exited, and the
  #     exit code is the gate's answer. Binding it to the tree here meant a
  #     background gate failed for writing a file — something the foreground path
  #     lets any gate do freely — and no retry could ever help, because every
  #     attempt re-dirtied the tree the same way. A concurrent editor save during
  #     a 26-minute suite had the same effect.
  #
  # rc 4 is therefore reachable only when `replayed_result` is 1. rc 0 (pass) and
  # 1 (non-pass terminal) are ordinary results, and 3 (not terminal, i.e. `lost`)
  # is handled by the row mapping below exactly as before.
  local _collect_rc=0
  local -a _collect_args=(collect --jobs-dir "$jobs_dir" --id "$job_id")
  [[ -n "$repo" ]] && _collect_args+=(--repo "$repo")
  (( replayed_result )) && _collect_args+=(--require-current)
  bash "$job_sh" "${_collect_args[@]}" >/dev/null 2>&1 || _collect_rc=$?

  # ── P076 Step 4: the pointer's only deletion site ─────────────────────────
  # A SUCCESSFUL collect means the job reached one of the supervisor's terminal
  # states. The pointer then goes away — but only if no OTHER background job of
  # this run is still live (checked with the cheap `status` sweep), because one
  # artifact serves the whole run. A `lost` job is deliberately NOT a successful
  # collect: the pointer stays so a resume reports the truth about it.
  case "$state" in
    terminal_pass|terminal_fail|timed_out|cancelled)
      if ! _resume_jobs_still_live "$jobs_dir"; then
        rm -f "$_RESUME_ARTIFACT" 2>/dev/null || true
        _resume_map_field resume_artifact ""
        # Only an AUTO run may be re-asserted as `active`: a manual run's
        # controller is a human, and stamping `active` over `manual` would be
        # this map claiming an autonomous controller that does not exist.
        if [[ "${AID_AUTO_MODE:-}" == "1" ]]; then
          _resume_map_field auto_controller active
        fi
      fi
      ;;
  esac

  # REPLAY ONLY (see the collect comment above): an already-terminal job whose
  # result this invocation never watched, against a tree that moved since. The
  # supervisor's result is real, but it is evidence about a different tree — so
  # it is refused, loudly, instead of replayed. A plain `fail` in the existing
  # vocabulary: the retry loop's next attempt gets its own job id and genuinely
  # re-runs the gate at the current tree, which is how the fix loop converges
  # instead of replaying a verdict nobody can change.
  if (( _collect_rc == 4 )); then
    log_event "$timeline_file" "gate_job_result_stale" gate="$gate_name" \
      job_id="$job_id" state="$state"
    echo "ERROR: aid-run-gates.sh: gate '${gate_name}' — job '${job_id}' is ${state}, but its result was produced by an EARLIER invocation against a different working tree; refusing to replay it as this run's result" >&2
    _bg_fail_row "$gate_name" "job_result_not_current" \
      "job ${job_id} is ${state} but its result was produced by an earlier invocation against a different working tree — it was not replayed" "$job_id"
    return 1
  fi

  # The tree moved while this gate was being supervised. That is RECORDED, never
  # a verdict: the gate ran, this invocation watched it, and what it returned is
  # what the row says. The observation exists because "the suite passed but
  # something edited the tree underneath it" is worth seeing when a later result
  # looks inconsistent — an additive field and one timeline event, both absent on
  # an undisturbed run, so no existing consumer sees a change.
  local _tree_moved=0
  if (( ! replayed_result )) && _job_result_stale "$job_sh" "$jobs_dir" "$job_id" "$repo"; then
    _tree_moved=1
    log_event "$timeline_file" "gate_job_tree_moved" gate="$gate_name" \
      job_id="$job_id" state="$state"
  fi

  local row row_rc=0
  row="$(gate_row_from_job "$gate_name" "$job_dir" "$job_id" "$state")" || row_rc=$?
  if (( _tree_moved )); then
    # A jq failure must never blank a row that already exists — keep the row.
    local _annotated=""
    _annotated="$(jq -c '. + {tree_moved_during_run:true}' <<<"$row" 2>/dev/null || true)"
    if [[ -n "$_annotated" ]]; then row="$_annotated"; fi
  fi
  printf '%s\n' "$row"
  return "$row_rc"
}

# _gate_row_checkpoint <rows_dir> <gate_name> <row_json> <head>
#   Durable incremental checkpoint (P076 Step 2). As each gate COMPLETES, its
#   row is written beside the run's evidence with an atomic tmp+mv. This is
#   what a rerun after a crash assembles from — and what Step 5's resume writes
#   into. Never brings the evidence directory into being (the same discipline
#   the execution ledger follows): a gate run must not dirty a working tree.
#
#   The row is BOUND to the revision it was produced at AND to the run that
#   produced it, in an additive `_checkpoint` envelope carrying
#   {head, tree, key, written_at}:
#     • head + tree — the same PAIR aid-job.sh binds a job result to, read from
#       `aid-job.sh revision`. HEAD alone was tree-blind: an uncommitted edit
#       never invalidated a row, which is the same one-sided binding that let a
#       background job replay a result the working tree had not earned.
#     • key — a keyed digest over the RUN's own secret (lib/aid-resume-artifact.sh),
#       the gate name and that revision pair. `head` is public and guessable, so
#       it could never establish that this run's writers produced the row: a
#       hand-written `gates_rows/<gate>.json` satisfied it and replayed as a
#       required-gate PASS. The key cannot be produced without reading the run's
#       own 0600 key file (see the honest limit stated on that helper).
#   The restore pass below refuses — as an explicit FAIL row, never silence —
#   any row whose envelope is missing, whose head or tree has moved, or whose
#   key does not verify. Fail closed in every direction: a run that could not
#   establish a key writes no binding and accepts none.
_gate_row_checkpoint() {
  local rows_dir="$1" gate_name="$2" row_json="$3" head="${4:-}" \
        tree="${5:-}" run_key="${6:-}" home="${7:-}"
  [[ -n "$rows_dir" ]] || return 0
  # The gate name becomes a filename — never let it become a path.
  case "$gate_name" in */*|*..*|"") return 0 ;; esac
  mkdir -p "$rows_dir" 2>/dev/null || return 0
  local dest="${rows_dir}/${gate_name}.json" tmp
  tmp="$(mktemp "${dest}.XXXXXX" 2>/dev/null)" || return 0
  local bound key
  key="$(aid_gate_row_binding_key "$run_key" "$gate_name" "$head" "$tree" "$home")"
  bound="$(jq -c --arg h "$head" --arg tr "$tree" --arg k "$key" \
             --arg t "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
             '. + {_checkpoint: {head: $h, tree: $tr, key: $k, written_at: $t}}' \
             <<<"$row_json" 2>/dev/null)" \
    || bound=""
  [[ -n "$bound" ]] && row_json="$bound"
  if printf '%s\n' "$row_json" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dest" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Verify yq is the mikefarah Go-based variant.
# Python kislyuk/yq has incompatible CLI (different default-value syntax,
# argument parsing) — fail fast with clear remediation.
require_yq_mikefarah() {
  if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq required but not installed." >&2
    echo "  Install (mikefarah Go variant — NOT the Python kislyuk/yq PyPI package):" >&2
    echo "    Debian/Ubuntu: sudo apt install yq" >&2
    echo "    macOS:         brew install yq" >&2
    echo "    Arch:          pacman -S go-yq" >&2
    echo "    Generic:       download from https://github.com/mikefarah/yq/releases" >&2
    exit 1
  fi
  if ! yq --version 2>&1 | grep -qi 'mikefarah'; then
    echo "ERROR: yq is installed but not the mikefarah Go variant." >&2
    echo "  Detected: $(yq --version 2>&1)" >&2
    echo "  Required: yq mikefarah Go variant (https://github.com/mikefarah/yq)." >&2
    echo "  Fix: sudo apt remove python3-yq && download mikefarah binary." >&2
    exit 1
  fi
}

# _gate_output_escape <string>
#   Same truncate-then-JSON-escape discipline run_gate() already applies to
#   a captured command's raw output, factored out for run_scheduled_
#   targeted_tests() below (which builds its own gate-row JSON by hand,
#   never through run_gate()'s generic `bash -c "$command"` capture).
_gate_output_escape() {
  local s="${1:0:2000}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# run_scheduled_targeted_tests <gate_name> <effective_mode> <base_commit>
#                               <plugin_path> <epic_id> <run_id>
#                               <project_root> <timeout_s>
#   P069 Step 14 — the targeted_tests-only, scheduler-backed dispatch path,
#   used INSTEAD OF run_gate() only when Step 13's rollout gate has
#   unlocked observe_parallel/parallel for THIS run. Never called for any
#   other gate, and never called at all when the rollout gate resolves
#   sequential (the ordinary run_gate() path below is then completely
#   unchanged from pre-Step-14 behavior).
#
#   Emits a JSON object on stdout matching run_gate()'s own output
#   contract exactly ({gate, result, exit_code, duration_ms, output}) so
#   every downstream consumer (retry loop, waiver check, baseline update,
#   gates_json aggregation) needs zero changes to accept either source.
#   Returns 0 iff result=="pass".
#
#   aid-select-tests.sh --emit-units's own exit-code contract governs what
#   happens next:
#     0  — units written (possibly EMPTY — a docs-only/no-impact change).
#          A non-empty unit set is handed to aid-test-scheduler.sh dispatch
#          under the unlocked mode; an empty set is an immediate pass
#          (aid-test-scheduler.sh itself refuses to schedule zero units).
#     1/10 — a genuine command/usage failure — treated exactly like an
#          ordinary gate-command failure, never escalation.
#     3/11 — D-selector-1 unverifiable / Step 10 mapping_gap — the caller
#          (run_all_gates(), immediately after this function returns)
#          is responsible for the escalation decision; this function only
#          ever reports the plain fail row, unchanged in shape from what a
#          direct (non-scheduled) invocation would have produced.
run_scheduled_targeted_tests() {
  local gate_name="$1" effective_mode="$2" base_commit="$3" plugin_path="$4" \
        epic_id="$5" run_id="$6" project_root="$7" timeout_s="$8" attempt="${9:-1}"

  local start_ms; start_ms=$(date +%s%3N)
  local units_file="${project_root}/.aid-o/work/evidence/${epic_id}/${run_id}/gates/targeted-units.json"
  mkdir -p "$(dirname "$units_file")"

  local select_output select_ec=0
  select_output=$(timeout "$timeout_s" "${plugin_path}/scripts/aid-select-tests.sh" \
    --base "$base_commit" --emit-units "$units_file" </dev/null 2>&1) || select_ec=$?

  local end_ms duration_ms
  end_ms=$(date +%s%3N)
  duration_ms=$(( end_ms - start_ms ))

  if [[ $select_ec -ne 0 ]]; then
    echo "{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"exit_code\":${select_ec},\"duration_ms\":${duration_ms},\"output\":\"$(_gate_output_escape "$select_output")\"}"
    return 1
  fi

  # Codex review: a missing/malformed units file after a successful
  # (exit 0) --emit-units run must never silently degrade to "zero units
  # selected → pass" — that fail-open would mask a real writer bug as a
  # clean docs-only-style pass. Require the file to actually parse as a
  # JSON array before treating an empty result as legitimate.
  if ! jq -e 'type == "array"' "$units_file" >/dev/null 2>&1; then
    echo "{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"exit_code\":1,\"duration_ms\":${duration_ms},\"output\":\"$(_gate_output_escape "aid-select-tests.sh --emit-units exited 0 but ${units_file} is missing or not a valid JSON array")\"}"
    return 1
  fi

  local expected_unit_ids_json
  expected_unit_ids_json="$(jq -c '[.[].unit_id]' "$units_file")"

  if [[ "$(jq 'length' <<<"$expected_unit_ids_json")" -eq 0 ]]; then
    # No test impact (e.g. a docs-only change) — nothing to schedule;
    # aid-test-scheduler.sh itself refuses to dispatch a zero-length unit
    # set, so an immediate pass here matches the direct-execution path's
    # own "selected_tests is empty by design → exit 0" contract exactly.
    echo "{\"gate\":\"${gate_name}\",\"result\":\"pass\",\"exit_code\":0,\"duration_ms\":${duration_ms},\"output\":\"$(_gate_output_escape "$select_output")\"}"
    return 0
  fi

  local dispatch_stderr_file; dispatch_stderr_file="$(mktemp)"
  local dispatch_output dispatch_ec=0
  dispatch_output=$(timeout "$timeout_s" bash "${plugin_path}/scripts/aid-test-scheduler.sh" dispatch \
    --project-root "$project_root" --run-id "${run_id}-targeted_tests" \
    --units-json "$units_file" --mode "$effective_mode" --attempt "$attempt" 2>"$dispatch_stderr_file") || dispatch_ec=$?

  end_ms=$(date +%s%3N)
  duration_ms=$(( end_ms - start_ms ))

  if [[ $dispatch_ec -ne 0 ]]; then
    local err_text; err_text="$(cat "$dispatch_stderr_file" 2>/dev/null)"
    rm -f "$dispatch_stderr_file"
    echo "{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"exit_code\":1,\"duration_ms\":${duration_ms},\"output\":\"$(_gate_output_escape "$err_text")\"}"
    return 1
  fi
  rm -f "$dispatch_stderr_file"

  local batches_json
  if ! batches_json="$(jq -c -n --argjson b "$dispatch_output" '[$b]' 2>/dev/null)"; then
    echo "{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"exit_code\":1,\"duration_ms\":${duration_ms},\"output\":\"scheduler dispatch produced invalid JSON\"}"
    return 1
  fi

  local row_json
  row_json="$(scheduler_report_merge_gate_row "$gate_name" "$expected_unit_ids_json" "$batches_json")"
  echo "$row_json"
  [[ "$(jq -r '.result' <<<"$row_json")" == "pass" ]] && return 0 || return 1
}

run_all_gates() {
  local execution_yaml="$1"
  local epic_id="$2"
  local run_id="$3"
  shift 3

  # Determine timeline_file: use positional $4 ONLY if it's not a flag.
  # Bug fix (PM-reported): the previous `${4:-default}` + unconditional
  # `shift` swallowed `--state-file` when caller skipped the positional
  # arg, causing log_event to write to a literal file named "--state-file".
  local timeline_file=".aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl"
  if [[ -n "${1:-}" && "${1}" != --* ]]; then
    timeline_file="$1"
    shift
  fi

  # Parse optional flags: --state-file, --report-file, --plan-json, --profile,
  # --base-commit, --plan-path
  local state_file="" report_file="" plan_json="" profile=""
  # P068 Step 2 — explicit substitution inputs. ADDITIVE and OPTIONAL: when
  # absent, both fall back to --state-file exactly as before, so every existing
  # EPIC-scoped caller is byte-for-byte unaffected. They exist because a
  # PLAN-FINAL run has no fsm-state.yaml (an EPIC-scoped artifact) and without
  # them `plan_diff` would receive `--plan null`, take its documented Fast Mode
  # graceful skip (exit 2, which execution.yaml's pass_criteria ACCEPTS) and
  # report a green gate that verified nothing.
  local base_commit_opt="" plan_path_opt=""
  local base_commit_opt_set=0 plan_path_opt_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state-file) state_file="$2"; shift 2 ;;
      --report-file) report_file="$2"; shift 2 ;;
      --plan-json) plan_json="$2"; shift 2 ;;
      --profile) profile="$2"; shift 2 ;;
      --base-commit) base_commit_opt="$2"; base_commit_opt_set=1; shift 2 ;;
      --plan-path) plan_path_opt="$2"; plan_path_opt_set=1; shift 2 ;;
      *) shift ;;
    esac
  done

  # A flag that is PASSED must carry a real value — an empty --plan-path would
  # otherwise silently degrade to the same `null` this flag exists to prevent.
  if (( base_commit_opt_set )) && [[ -z "$base_commit_opt" || "$base_commit_opt" == "null" ]]; then
    echo "ERROR: aid-run-gates.sh: --base-commit was passed with an empty/'null' value — pass a real commit or omit the flag." >&2
    exit 1
  fi
  if (( plan_path_opt_set )) && [[ -z "$plan_path_opt" || "$plan_path_opt" == "null" ]]; then
    echo "ERROR: aid-run-gates.sh: --plan-path was passed with an empty/'null' value — pass a real plan file path or omit the flag." >&2
    exit 1
  fi

  [[ -f "$execution_yaml" ]] || { echo "ERROR: execution_yaml not found: $execution_yaml" >&2; exit 1; }

  require_yq_mikefarah

  # ─── run_mode validation (P076 Step 2) ─────────────────────────────────
  # Swept over EVERY defined gate here, before a single gate command is
  # spawned — a typo on the third gate must not be discovered after the first
  # two have already run.
  validate_all_run_modes "$execution_yaml" || exit 1

  # ─── services validation (P076 Step 8) ─────────────────────────────────
  # Same entry point, same spirit: the OPTIONAL `services:` block is checked
  # here, before any service or gate action, so a malformed declaration is
  # refused by service and field instead of surfacing as a mystery failure in
  # the middle of a gate. An absent block is a no-op — nothing changes for a
  # project that declares no services.
  _validate_services_config "$execution_yaml" || exit 1

  # One-time-per-clone lazy bootstrap (P063 Step 2) — see
  # aid_gate_baseline_ensure_gitignored above. Called once per run (not per
  # gate/attempt): idempotent, and there's nothing gate-specific about it.
  aid_gate_baseline_ensure_gitignored

  # ─── Gate profile resolution (P061 E1 Step 2) ──────────────────────────
  # A profile is a named include[] whitelist of gate keys under
  # execution.yaml.gate_profiles. --profile <name> activates exactly one
  # profile for THIS run (auto-selection by risk/phase is a later EPIC —
  # for this step profile_source is always "cli_flag"). Omitting --profile
  # leaves `profile`/`include_gates_json` empty and every check below is
  # skipped, so legacy execution.yaml files (with or without a
  # `gate_profiles` block) behave EXACTLY as before — this is the
  # backward-compatibility contract.
  #
  # Both fail-loud cases are validated upfront, before any gate runs:
  #   1. --profile <name> where <name> is not a key under gate_profiles.
  #   2. A profile's include[] lists a gate not defined under .gates.
  local profile_source="null" profile_reason="null"
  local include_gates_json="[]"
  if [[ -n "$profile" ]]; then
    local profile_def
    profile_def=$(PROFILE="$profile" yq '.gate_profiles[strenv(PROFILE)]' "$execution_yaml")
    if [[ -z "$profile_def" || "$profile_def" == "null" ]]; then
      echo "ERROR: aid-run-gates.sh: unknown gate profile '${profile}' — no such key under gate_profiles in ${execution_yaml}" >&2
      exit 1
    fi

    include_gates_json=$(PROFILE="$profile" yq -o=json '.gate_profiles[strenv(PROFILE)].include // []' "$execution_yaml" | tr -d '\n ')
    local profile_defined_keys_json
    profile_defined_keys_json=$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')
    local inc_gate
    while IFS= read -r inc_gate; do
      [[ -z "$inc_gate" ]] && continue
      if ! jq -e --arg g "$inc_gate" 'any(.[]; . == $g)' <<< "$profile_defined_keys_json" >/dev/null 2>&1; then
        echo "ERROR: aid-run-gates.sh: gate profile '${profile}' includes undefined gate '${inc_gate}' (not present under execution.yaml.gates)" >&2
        exit 1
      fi
    done < <(jq -r '.[]' <<< "$include_gates_json")

    profile_source="cli_flag"
    profile_reason="explicit --profile flag"
  fi

  # FSM state check: refuse to run if state is not GATES, UNLESS caller is
  # cmd_advance_to_gates (signaled via AID_GATES_TRIGGERED_BY_FSM=1, P035 Step 2).
  # That caller has already validated EXECUTE state + step completion; the
  # atomic flow runs gates with state==EXECUTE then commits transition via
  # cmd_transition (which re-validates _generated_by from this run's report).
  # Strict equality check `=="1"` — accidental bypass via truthy-but-not-1 values
  # is excluded.
  if [[ -n "$state_file" && "${AID_GATES_TRIGGERED_BY_FSM:-}" != "1" ]]; then
    local current_state
    current_state=$("${SCRIPT_DIR}/aid-fsm.sh" get-state "$state_file")
    if [[ "$current_state" != "GATES" ]]; then
      echo "ERROR: FSM state must be GATES to run gates, found: $current_state." >&2
      echo "  For atomic gates+transition flow: use 'aid-fsm.sh advance-to-gates <state_file>' instead." >&2
      exit 1
    fi
  fi

  # Resolve report path early so we can put it in the gate_runner_start event.
  local report_path="${report_file:-}"
  [[ -z "$report_path" ]] && report_path=".aid-o/work/evidence/${epic_id}/${run_id}/gates/gates_report.json"

  # Phase 2 (P037) — pull base_commit and plan_path from fsm-state.yaml for placeholder resolution.
  # Falls back to empty/null when fsm-state.yaml is absent (e.g., legacy/source-mode invocations).
  local base_commit_resolved="" plan_path_resolved="null"
  if [[ -n "$state_file" && -f "$state_file" ]]; then
    base_commit_resolved=$(grep '^base_commit:' "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    plan_path_resolved=$(grep '^plan_path:' "$state_file" 2>/dev/null | awk '{print $2}' || echo "null")
    [[ -z "$plan_path_resolved" ]] && plan_path_resolved="null"
  fi
  # P068 Step 2 — the explicit flags WIN over the state file when supplied.
  # Precedence, not merge: a plan-final caller that names its own base/plan is
  # the authority for this run; a caller that names neither is on the legacy
  # state-file path unchanged.
  # (if/fi, not `(( x )) && ...` — under `set -e` a false arithmetic test as the
  # last command of a && list exits the script.)
  if (( base_commit_opt_set )); then base_commit_resolved="$base_commit_opt"; fi
  if (( plan_path_opt_set )); then plan_path_resolved="$plan_path_opt"; fi

  # P069 Step 12 — resolve {plugin_path} ONCE here, exactly mirroring how
  # base_commit/plan_path are already resolved by this same caller.
  # resolve_placeholders() itself gains zero new file/env-reading logic — it
  # remains a pure substitution function over one additional argument.
  local plugin_path_resolved=""
  local _plugin_project_root
  _plugin_project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [[ -f "${_plugin_project_root}/.aid-o/config/plugin.yaml" ]]; then
    plugin_path_resolved="$(yq -r '.plugin_path // ""' "${_plugin_project_root}/.aid-o/config/plugin.yaml" 2>/dev/null || echo "")"
  fi
  [[ -z "$plugin_path_resolved" ]] && plugin_path_resolved="${AID_PLUGIN_PATH:-}"

  # ─── gate_runner_start (P032 Step 3) ──────────────────────────────
  local gate_count gate_names_json
  gate_count=$(yq '.gates | length' "$execution_yaml")
  gate_names_json=$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')
  log_event "$timeline_file" "gate_runner_start" \
    report_path="$report_path" gate_count="$gate_count" \
    command_list="$gate_names_json"

  local run_start=$SECONDS
  local overall="pass"
  local gates_json="{"
  local first=true
  # `processed` counts EXCLUSIVELY defined-gate result rows emitted below
  # (pass/fail/skip). It is compared to gate_count (defined) after the loop:
  # a mismatch means a gate row was silently lost → _integrity fail + overall
  # fail (OBS-20260708-07). Reconciliation rows (undefined_gate, Step 2) and the
  # _integrity row itself MUST NOT increment it. Use $((x+1)) not ((x++)) — the
  # latter returns 0 on first use and trips set -e.
  local processed=0
  declare -a command_log=()
  # Gate keys excluded by the active profile (P061 E1 Step 2). Populated
  # only when --profile is set; stays empty otherwise.
  declare -a excluded_gates=()
  # Gate keys whose failed result was WAIVED by a valid gate-scoped PM waiver
  # (IMP-270). Populated inline when a failing gate has a check-valid waiver at
  # the current HEAD+command. Surfaces top-level as waived_gates[] so nothing
  # downstream can miss that a required gate was accepted without passing.
  declare -a waived_gates=()
  # Gates whose runtime baseline (P063 Step 2) already has enough data
  # (non_censored_samples_count >= 5) to be worth a human-readable summary
  # line after the run — populated inline at merge time below (reusing the
  # runtime_baseline_json already fetched there) so the post-loop summary
  # never re-queries gates that were profile_excluded/skipped/never run this
  # round, and never re-fetches the same gate's baseline twice.
  declare -a baseline_summary_gates=()
  # P076 Step 3 — gates whose own telemetry recommends `background` while their
  # config declares no run_mode at all. Appended EXACTLY ONCE per gate, at the
  # single post-retry merge point below (never per attempt), from the
  # runtime_baseline JSON already fetched there — no second baseline pass.
  # Emitted after the run as one named timeline event per gate, observe-only:
  # flipping a gate stays a one-line human edit (P069 observe-then-promote).
  declare -a run_mode_advice_gates=()

  # P069 Step 14 — targeted_tests escalation (exit 3 unknown_production /
  # exit 11 mapping_gap). Set inline when that gate's FINAL result settles
  # (regardless of whether it ran sequentially or through the scheduler —
  # both paths ultimately invoke aid-select-tests.sh and can produce either
  # exit code). Consumed AFTER the whole targeted-profile pass finishes and
  # its own report has been fully assembled — never mid-loop, and never
  # mutating this pass's own `gates_json`/`processed`/`gate_count` bookkeeping.
  local escalation_triggered=false
  local escalation_reason=""

  # ─── Background job + row-checkpoint locations (P076 Step 2) ─────────────
  # Both live under THIS run's evidence directory. Resolved once, and only when
  # that directory already exists — the gate runner writes into evidence, it
  # never invents evidence directories (same rule the execution ledger follows).
  local _evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  local _jobs_dir="" _rows_dir=""
  if [[ -d "$_evidence_dir" ]]; then
    _jobs_dir="${_evidence_dir}/jobs"
    _rows_dir="${_evidence_dir}/gates_rows"
  fi

  # The revision every row produced by THIS invocation is bound to, and the one
  # a restored row's binding is compared against. HEAD *and* tree, read from the
  # supervisor's own `revision` so the checkpoint envelope and a job record
  # cannot mean different things by "the current revision".
  # ONE derivation, shared with `resume`'s writer (lib/aid-resume-artifact.sh):
  # the repo whose tree a row is about is the repo the JOB runs in, which is the
  # same `--repo` this runner hands the supervisor.
  local _rows_rev _rows_head _rows_tree _rows_key _rows_home
  _rows_rev="$(aid_gate_row_revision "$_plugin_project_root")"
  _rows_head="${_rows_rev%% *}"; _rows_tree="${_rows_rev##* }"
  # The run's own gate-row secret. Created on first use beside the run's other
  # evidence, never bringing an evidence directory into being; empty when there
  # is no evidence directory, which makes every checkpoint unbindable and every
  # restore a refusal — the fail-closed direction.
  _rows_key="$(aid_gate_row_run_key "$_evidence_dir")"
  # The checkpoint's HOME — the canonical path of the directory it lives in, so a
  # binding written here verifies only here. See the lifecycle note on the key.
  _rows_home="$(aid_gate_row_home "$_evidence_dir")"

  # ─── P076 Step 4 — continuation pointer identity, resolved ONCE ──────────
  # `safe_next_action` is stored FULLY RESOLVED: this plugin's real path (never
  # a {plugin_path} token), the literal epic and run ids, the real execution.yaml
  # and report paths. The schema forbids '<' in the field precisely so no
  # '<epic_id>'-style placeholder can survive into a continuation instruction.
  _RESUME_EPIC_ID="$epic_id"
  _RESUME_RUN_ID="$run_id"
  _RESUME_PLAN_ID="unknown"
  [[ "$epic_id" =~ ^E-([0-9]+) ]] && _RESUME_PLAN_ID="P${BASH_REMATCH[1]}"
  _RESUME_ARTIFACT=""
  [[ -d "$_evidence_dir" ]] && _RESUME_ARTIFACT="${_evidence_dir}/${AID_RESUME_ARTIFACT_BASENAME}"
  _RESUME_SAFE_NEXT_ACTION="bash ${SCRIPT_DIR}/aid-run-gates.sh run-all ${execution_yaml} ${epic_id} ${run_id} --report-file ${report_path}"

  # ─── Execution ledger (P072 Step 26) ─────────────────────────────────────
  # The gate runner owns the ledger's LIFECYCLE only; the dispatch points own
  # its content. It cannot see run units for a fan-out command — `run_gate`
  # takes an opaque command string — so a ledger appended from here would
  # record one entry per gate and could never find the overlap it exists for.
  local _ledger_path="" _ledger_unaccounted_reason=""
  if [[ -z "${AID_EXECUTION_LEDGER:-}" ]]; then
    # Beside this run's other evidence, and created the same way the timeline
    # and the report are: written INTO an existing directory, never bringing
    # one into being. The gate runner does not create directories in the
    # project under test — a real regression this broke, because an invented
    # `.aid-o/work/evidence/execution-ledger/` is an untracked path, and a gate
    # run that dirties `git status` is one that cannot be run safely from a
    # checkout somebody is working in.
    local _ledger_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    if [[ -d "$_ledger_dir" ]]; then
      _ledger_path="${_ledger_dir}/execution-ledger.json"
      # A failed open is NOT a reason to run unaccounted. Swallowing it produced
      # exactly the outcome the ledger exists to prevent: a green gate run whose
      # test accounting silently did not happen.
      if ! bash "${SCRIPT_DIR}/aid-test-execution-ledger.sh" open \
           --path "$_ledger_path" --run-id "${run_id:-run}" \
           --candidate-sha "${base_commit_resolved:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}" >/dev/null 2>&1; then
        echo "ERROR: aid-run-gates.sh: could not open the execution ledger at '$_ledger_path' — refusing to run gates unaccounted" >&2
        return 3
      fi
      export AID_EXECUTION_LEDGER="$_ledger_path"
    else
      # No evidence directory means no run is being recorded at all — the
      # timeline and the report have nowhere to go either. Said out loud
      # rather than inferred from silence, because "this run was not
      # accounted" and "this run had no duplicates" must never look alike.
      # Recorded in the REPORT, not on stderr. This command's stdout contract is
      # a JSON document, and a diagnostic on stderr merges into it for any
      # caller that captures both — bats' own `run` does exactly that, and this
      # line turned four passing gate-runner tests red by making the report
      # unparseable. The fact still has to be durable, so it goes where the rest
      # of the run's findings go.
      _ledger_unaccounted_reason="no evidence directory at '${_ledger_dir}' — this gate run is NOT accounted by an execution ledger and cannot support a no-double-execution claim"
    fi
  fi

  # ─── Services: entry sweep, then ACQUIRE ONCE (P076 Step 10) ─────────────
  # HERE, and not earlier or later, for four reasons that each pin one edge:
  #   • after `_validate_services_config`, so a malformed declaration is refused
  #     before anything is started;
  #   • after `_evidence_dir` is resolved, because the service registry lives in
  #     the run's evidence and nothing here invents an evidence directory;
  #   • after the ledger is opened, so a run that cannot be accounted refuses
  #     before it starts a process;
  #   • BEFORE the gate loop, so a service failure fails the whole run before a
  #     single gate has run and reported on infrastructure that never came up.
  #
  # The sweep runs before the acquire because a SIGKILLed runner reaches no
  # completion hook, ever: the next `run-all` IS the crash recovery. It tears
  # down whatever the dead run left non-stopped (registry entries plus, inside
  # `aid_service_down_all`, any live job the registry does not name), and the
  # idempotent `up_all` then starts cleanly instead of beside an orphan.
  #
  # ONE OWNER PER RUN, and it is enforced two different ways for two different
  # kinds of second runner — say which is which, because a single sentence here
  # previously implied a guarantee only one half of it delivered:
  #   • the KNOWN re-entry. The targeted_tests escalation re-enters this script
  #     as a subprocess against the SAME epic/run — and therefore the same
  #     registry — while this invocation's services are up. It is handed
  #     AID_SERVICE_LIFECYCLE_OWNED=1, which makes it a CONSUMER: it still reads
  #     the registry for its own `needs_services` checks, and it neither sweeps,
  #     acquires nor releases. An environment variable is enough here and only
  #     here, because we are the parent that sets it.
  #   • ANY OTHER second runner — a rerun launched while the first is still mid
  #     gates, from a script, a second session, or a scheduler. Nothing tells us
  #     about that one, so we ask the operating system: the claim record left by
  #     the current owner is checked against a LIVE PROCESS, and a second runner
  #     REFUSES rather than sweeping a running run's services out from under it.
  #     Refusing is the fail-closed direction: a run that will not start is an
  #     error message, a database torn down mid-gates is a corrupted verdict.
  local _svc_count=0 _svc_manage=1
  _svc_count="$(_svc_declared_count "$execution_yaml")"
  [[ "${AID_SERVICE_LIFECYCLE_OWNED:-}" == "1" ]] && _svc_manage=0
  if (( _svc_count > 0 )); then
    _svc_lib_load || exit 1
  fi
  # A run that declares services and does not manage them is a legitimate but
  # UNUSUAL shape: every gate that does not name `needs_services` runs against
  # infrastructure nobody started, and passes. Recorded, so that run's evidence
  # cannot be mistaken for a run that had its services (finding 3).
  if (( _svc_count > 0 && _svc_manage == 0 )); then
    log_event "$timeline_file" "services_lifecycle_delegated" \
      declared="$_svc_count" reason="AID_SERVICE_LIFECYCLE_OWNED"
  fi
  if (( _svc_count > 0 && _svc_manage == 1 )); then
    if [[ -z "$_evidence_dir" || ! -d "$_evidence_dir" ]]; then
      echo "ERROR: aid-run-gates.sh: ${_svc_count} service(s) declared in ${execution_yaml} but there is no evidence directory at '${_evidence_dir}' to hold the service registry — refusing to start a service this run could not record, and therefore could not stop" >&2
      exit 1
    fi
    # BEFORE the sweep, because the sweep is the destructive step.
    if _svc_owner_live "$_evidence_dir"; then
      log_event "$timeline_file" "service_owner_conflict" evidence_dir="$_evidence_dir"
      echo "ERROR: aid-run-gates.sh: another gate runner is still managing the services recorded under '${_evidence_dir}' ($(_svc_owner_describe "$_evidence_dir")) — refusing to run. Two runners sharing one run's service registry cannot both own it: this one would sweep the live run's services out from under its gates. Wait for that run, or stop it; if it is gone and this message persists, its claim record is ${_evidence_dir}/services.owner.json." >&2
      exit 1
    fi
    if _svc_stale_state_present "$_evidence_dir"; then
      echo "aid-run-gates.sh: this run's evidence still holds service state from an earlier, unfinished invocation — sweeping it before acquiring (a killed runner reaches no cleanup hook; this rerun is the cleanup)" >&2
      log_event "$timeline_file" "service_stale_sweep" evidence_dir="$_evidence_dir"
      aid_service_down_all "$_evidence_dir" "$execution_yaml" || true
    fi
    # The claim goes down BEFORE anything is started, so there is no window in
    # which this run owns a service that no record names as ours. A claim we
    # cannot write is a claim the next runner cannot check, so it fails the run
    # rather than starting services nobody can prove ownership of.
    if ! _svc_owner_claim "$_evidence_dir" "$run_id"; then
      echo "ERROR: aid-run-gates.sh: could not record the service ownership claim at '$(_svc_owner_file "$_evidence_dir")' — refusing to start services whose owner a second runner could not check (it would read the absence as 'nobody owns these' and sweep them)" >&2
      exit 1
    fi
    log_event "$timeline_file" "services_acquire_start" declared="$_svc_count"
    local _svc_up_rc=0
    aid_service_up_all "$_evidence_dir" "$execution_yaml" || _svc_up_rc=$?
    if (( _svc_up_rc != 0 )); then
      # Whatever DID come up is recorded and therefore stoppable — release it
      # through the one teardown definition before failing.
      _SVC_ACQUIRED=1
      log_event "$timeline_file" "services_acquire_fail" declared="$_svc_count" exit_code="$_svc_up_rc"
      _svc_release_run "$_evidence_dir" "$execution_yaml"
      echo "ERROR: aid-run-gates.sh: the declared services for this run did not come up (aid_service_up_all exit ${_svc_up_rc}) — refusing to run any gate against infrastructure that is not there. The named service failure is above." >&2
      exit 1
    fi
    _SVC_ACQUIRED=1
    log_event "$timeline_file" "services_acquired" declared="$_svc_count"
  fi

  # Iterate gate names via yq (mikefarah)
  local gate_names
  gate_names=$(yq '.gates | keys | .[]' "$execution_yaml")

  while IFS= read -r gate_name; do
    [[ -z "$gate_name" ]] && continue

    # Test-only fault injection (never set in production): drop a gate's
    # iteration WITHOUT emitting a row or incrementing `processed`, simulating a
    # silently-lost gate so the defined==processed integrity assert below can be
    # exercised end-to-end (OBS-20260708-07 F4c).
    if [[ -n "${AID_TEST_DROP_GATE:-}" && "$gate_name" == "${AID_TEST_DROP_GATE}" ]]; then
      continue
    fi

    # Test-only fault injection (never set in production): skip a gate's
    # iteration to simulate a runner that DIED before reaching it. Unlike
    # AID_TEST_DROP_GATE above, this seam deliberately does NOT suppress the
    # checkpoint-restore pass — a crashed run's un-iterated gate is exactly what
    # that pass exists for, and no ordinary path through this loop leaves a gate
    # rowless, so this is the only way to exercise it.
    #
    # Setting it can no longer MANUFACTURE a result. It used to: combined with a
    # hand-written `gates_rows/<gate>.json` whose only binding was the public
    # HEAD, a required gate declaring `command: "exit 1"` reported `pass`. The
    # restore pass now requires a keyed binding only this run's own writers can
    # produce, so this seam can skip a gate's execution but the outcome is either
    # a genuine row the run itself checkpointed, or an explicit refusal — and a
    # gate with no restorable row at all trips the defined==processed integrity
    # assert and fails the run.
    if [[ -n "${AID_TEST_DROP_GATE_RESTORE:-}" && "$gate_name" == "${AID_TEST_DROP_GATE_RESTORE}" ]]; then
      continue
    fi

    # ─── Gate-profile exclusion (P061 E1 Step 2) ──────────────────────
    # A gate defined in execution.yaml but not listed in the active
    # profile's include[] is never run — but it must never be silently
    # dropped either (same defined==processed contract as the no_command
    # skip row above): emit an explicit profile_excluded row, count it
    # toward `processed`, and record it in excluded_gates. A required:true
    # gate excluded this way does NOT fail the run — same treatment as a
    # skipped required:false gate below.
    if [[ -n "$profile" ]] && ! jq -e --arg g "$gate_name" 'any(.[]; . == $g)' <<< "$include_gates_json" >/dev/null 2>&1; then
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="profile_excluded" reason="profile_excluded" profile="$profile"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"profile_excluded\",\"reason\":\"profile_excluded\",\"exit_code\":0,\"duration_ms\":0,\"output\":\"\",\"attempts\":0}"
      processed=$((processed+1))
      excluded_gates+=("$gate_name")
      continue
    fi

    local cmd required max_retries timeout_s pass_criteria run_mode
    cmd=$(yq ".gates.\"${gate_name}\".command" "$execution_yaml")
    required=$(yq ".gates.\"${gate_name}\".required // false" "$execution_yaml")
    max_retries=$(yq ".gates.\"${gate_name}\".max_retries // 1" "$execution_yaml")
    timeout_s=$(yq ".gates.\"${gate_name}\".timeout_seconds // 60" "$execution_yaml")
    pass_criteria=$(yq ".gates.\"${gate_name}\".pass_criteria // \"\"" "$execution_yaml")
    # P076 Step 2 — already validated for every gate above; re-read here as the
    # per-gate dispatch input. Absent → "foreground" → the untouched code path.
    run_mode=$(resolve_run_mode "$execution_yaml" "$gate_name")

    if [[ -z "$cmd" || "$cmd" == "null" ]]; then
      # A null-command gate must leave an explicit skip row — never a bare
      # `continue` (which loses the row and lets defined>rows slip through as a
      # false pass). Counting it keeps defined==processed true by construction.
      echo "WARN: gate '${gate_name}' has no command — recording skip (no_command)" >&2
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="skip" reason="no_command"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"skip\",\"reason\":\"no_command\",\"exit_code\":0,\"duration_ms\":0,\"output\":\"\",\"attempts\":0}"
      processed=$((processed+1))
      continue
    fi

    # ─── needs_services fail-fast (P076 Step 10) ──────────────────────────
    # A gate that declares `needs_services` runs ONLY when every named service is
    # healthy right now. The check is here — before placeholder resolution, before
    # the ledger append, before any dispatch — so a gate whose dependency is down
    # fails FAST and by name instead of failing slowly, in its own words, about
    # something else. The names were validated against the declarations at config
    # check, so anything unhealthy here is a runtime fact, never a typo.
    #
    # This is a READ of the registry plus one probe per service: cheap enough to
    # sit on the `background` path too, where it happens at gate start, before the
    # job is spawned. And it never touches the service — checking is not managing;
    # the run acquired once and will release once.
    #
    # Other gates are completely unaffected: one unhealthy dependency fails ONE
    # gate, and the loop continues.
    if (( _svc_count > 0 )); then
      local _needs_json _need _unhealthy=""
      _needs_json="$(GATE="$gate_name" yq -o=json '.gates[strenv(GATE)].needs_services // []' "$execution_yaml" 2>/dev/null | tr -d '\n ' || echo '[]')"
      if [[ -n "$_needs_json" && "$_needs_json" != "[]" && "$_needs_json" != "null" ]]; then
        while IFS= read -r _need; do
          [[ -z "$_need" ]] && continue
          if ! aid_service_status "$_need" "$_evidence_dir" "$execution_yaml" >/dev/null 2>&1; then
            _unhealthy+="${_unhealthy:+, }${_need}"
          fi
        done < <(jq -r '.[]' <<<"$_needs_json" 2>/dev/null || true)
      fi
      if [[ -n "$_unhealthy" ]]; then
        echo "ERROR: aid-run-gates.sh: gate '${gate_name}' needs service(s) that are not healthy: ${_unhealthy} — failing this gate fast rather than running it against infrastructure that is not there" >&2
        log_event "$timeline_file" "gate_complete" gate="$gate_name" result="fail" reason="service_unhealthy" services="$_unhealthy"
        $first || gates_json+=","
        first=false
        gates_json+="\"${gate_name}\":$(jq -nc --arg g "$gate_name" --arg s "$_unhealthy" \
          '{gate:$g, result:"fail", reason:"service_unhealthy", exit_code:1, duration_ms:0,
            output:("required service(s) not healthy: " + $s), attempts:0, unhealthy_services:($s | split(", "))}')"
        processed=$((processed+1))
        if [[ "${required:-false}" == "true" ]]; then overall="fail"; fi
        continue
      fi
    fi

    # Phase 2 (P037) — resolve {token} placeholders before bash -c execution.
    # Unknown tokens fail-loud — mark gate as fail and continue to next gate.
    local resolved_cmd
    if ! resolved_cmd=$(resolve_placeholders "$cmd" "$epic_id" "$run_id" "$base_commit_resolved" "$plan_path_resolved" "$plugin_path_resolved"); then
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="fail" reason="unknown_placeholder"
      overall="fail"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"unknown_placeholder\",\"attempts\":0}"
      processed=$((processed+1))
      continue
    fi

    log_event "$timeline_file" "gate_start" gate="$gate_name" epic_id="$epic_id"

    # ─── P069 Step 14 — scheduler dispatch (targeted_tests ONLY) ──────────
    # Every other gate is completely unaffected: gate_concurrency_context
    # stays "sequential" and use_scheduled_dispatch stays false, so the
    # retry loop below calls run_gate() exactly as it always has.
    local gate_concurrency_context="sequential"
    local use_scheduled_dispatch=false
    local rollout_effective_mode="sequential"
    if [[ "$gate_name" == "targeted_tests" ]]; then
      local rollout_json
      rollout_json="$("${SCRIPT_DIR}/aid-scheduler-rollout-gate.sh" --project-root "$_plugin_project_root" 2>/dev/null)" || rollout_json=""
      rollout_effective_mode="$(jq -r '.effective_mode // "sequential"' <<<"$rollout_json" 2>/dev/null || echo "sequential")"
      if [[ "$rollout_effective_mode" == "observe_parallel" || "$rollout_effective_mode" == "parallel" ]]; then
        use_scheduled_dispatch=true
        gate_concurrency_context="$rollout_effective_mode"
      fi
    fi

    # The dispatch points tag their entries with the gate they are running
    # under, which only this loop knows.
    export AID_CURRENT_GATE_ID="$gate_name"

    # THE FOURTH EMISSION PATH. A gate whose command invokes a runner DIRECTLY
    # passes through none of the fan-out points, so without this the ledger
    # would record nothing for it — and this repository's real double
    # execution (`gate:bats_fsm` running a file the pool also runs) would have
    # been certified clean by the very check built to find it.
    #
    # A command that resolves to no test file appends nothing, which is
    # correct: those gates execute no unit.
    if [[ -n "${AID_EXECUTION_LEDGER:-}" ]]; then
      while read -r _lg_bats; do
        [[ -z "$_lg_bats" ]] && continue
        # No `|| true`. An append that fails is a hole in the accounting, and
        # a holed ledger reports zero duplicates just like a clean one.
        if ! bash "${SCRIPT_DIR}/aid-test-execution-ledger.sh" append \
             --path "$AID_EXECUTION_LEDGER" \
             --run-unit-id "bats:${_lg_bats%.bats}" --gate-id "$gate_name" \
             --fingerprint "$(printf '%s' "$resolved_cmd" | sha256sum | cut -c1-16)" \
             --dispatch-point gate_runner_direct >/dev/null 2>&1; then
          echo "ERROR: aid-run-gates.sh: execution-ledger append failed for gate '$gate_name' — refusing to continue with incomplete accounting" >&2
          # An abandoned run must not abandon its services. Same one teardown.
          _svc_release_run "$_evidence_dir" "$execution_yaml"
          return 3
        fi
      done < <(grep -oE '[A-Za-z0-9_./-]+\.bats' <<<"$resolved_cmd" 2>/dev/null \
                 | grep -v 'aid-bats-parallel-lane' || true)
    fi

    local gate_result="" attempt=0 gate_exit=0
    for (( attempt=1; attempt<=max_retries+1; attempt++ )); do
      gate_exit=0
      if $use_scheduled_dispatch; then
        gate_result=$(run_scheduled_targeted_tests "$gate_name" "$rollout_effective_mode" "$base_commit_resolved" "$plugin_path_resolved" "$epic_id" "$run_id" "$_plugin_project_root" "$timeout_s" "$attempt") || gate_exit=$?
      elif [[ "$run_mode" == "background" ]]; then
        # P076 Step 2 — delegated, group-owned, re-attachable. Each RETRY gets
        # its own deterministic job id (`<gate>-attempt-<N>`), so the existing
        # retry budget and code path are untouched: this branch declares how an
        # attempt runs, it never rewires how many attempts there are.
        if [[ -z "$_jobs_dir" ]]; then
          echo "ERROR: aid-run-gates.sh: gate '${gate_name}' declares run_mode: background but there is no evidence directory at '${_evidence_dir}' to hold its job record — refusing to run it unowned" >&2
          gate_result=$(_bg_fail_row "$gate_name" "no_jobs_dir" "no evidence directory at ${_evidence_dir}")
          gate_exit=1
        else
          gate_result=$(run_background_gate "$gate_name" "$resolved_cmd" "$timeout_s" "$attempt" "$_jobs_dir" "$timeline_file" "$_plugin_project_root") || gate_exit=$?
        fi
      else
        gate_result=$(run_gate "$gate_name" "$resolved_cmd" "$timeout_s" /dev/null) || gate_exit=$?
      fi
      local r
      r=$(echo "$gate_result" | jq -r '.result')
      # Phase 2 (P037) — exit code 2 is a graceful skip when gate's pass_criteria
      # mentions "exit 2" (legacy plan / no AC blocks / Fast Mode).
      # Evidence truthfulness fix: result="skip" (not "pass") so gates_report.json
      # accurately reflects that the gate did not verify anything, only skipped.
      # The outer overall="pass" logic treats "skip" same as "pass" for required=false gates.
      local gate_ec
      gate_ec=$(echo "$gate_result" | jq -r '.exit_code')
      if [[ "$r" != "pass" && "$gate_ec" == "2" && "$pass_criteria" == *"exit 2"* ]]; then
        gate_result=$(echo "$gate_result" | jq '.result = "skip"')
        r="skip"
      fi

      # ─── Gate runtime baseline sample (P063 Step 2) ────────────────────
      # One sample per ATTEMPT (not per gate) — a retried gate's earlier
      # failed/timed-out attempts are real duration data too. Deliberately
      # excludes "skip" (both the no_command-less path above, which never
      # reaches here, and this exit-2/pass_criteria convention above): a
      # skip never really executed the gate's intended work, so it is not a
      # meaningful timing sample. Never allowed to fail the run — a metrics
      # write is never load-bearing for gate pass/fail.
      if [[ "$r" != "skip" ]]; then
        local baseline_exit_code baseline_duration_ms
        baseline_exit_code=$(echo "$gate_result" | jq -r '.exit_code')
        baseline_duration_ms=$(echo "$gate_result" | jq -r '.duration_ms')
        gate_baseline_update "$gate_name" "$cmd" "$resolved_cmd" \
          "$baseline_exit_code" "$baseline_duration_ms" "$timeout_s" "$gate_concurrency_context" || true
      fi

      [[ "$r" == "pass" || "$r" == "skip" ]] && break

      # ─── Repeated-timeout policy block (P063 Step 3) ───────────────────
      # Reached ONLY when the current attempt already failed/timed out (the
      # pass/skip break above already returned for a passing attempt — a
      # gate whose CURRENT attempt just passed NEVER reaches this check,
      # which is what makes AC10 hold) AND the loop is about to decide
      # whether to consume another attempt. `timeout_s` is the gate's
      # currently-configured timeout, read once before this loop began.
      # gate_baseline_policy_check compares the last 3 recorded samples
      # (already including the one gate_baseline_update just wrote above for
      # THIS attempt) — "block" iff all 3 are censored (timeout) AND each
      # sample's OWN recorded timeout_seconds >= the current config, so a
      # timeout streak recorded under a since-raised timeout never blocks a
      # fresh attempt under the new, longer timeout (AC6 fixture b).
      if [[ "$(gate_baseline_policy_check "$gate_name" "$timeout_s")" == "block" ]]; then
        gate_baseline_mark_policy_block "$gate_name" "increase_timeout_or_background" || true
        # result stays the UNCHANGED literal "fail" (never a new value) —
        # reason/recommendation are purely additive fields describing WHY no
        # further attempt was made.
        gate_result=$(echo "$gate_result" | jq '.result = "fail" | .reason = "timeout_policy_block" | .recommendation = "increase_timeout_or_background"')
        break
      fi

      [[ $attempt -le $max_retries ]] && echo "Gate ${gate_name} failed (attempt ${attempt}/${max_retries}), retrying..." >&2
    done

    local final_result
    final_result=$(echo "$gate_result" | jq -r '.result')

    # ─── Gate-scoped PM waiver (IMP-270) ───────────────────────────────────
    # A failed gate becomes `waived` (NEVER `pass`) iff a gate-scoped waiver
    # exists for it AND aid-gate-waiver.sh check returns `valid` for the exact
    # (project, epic, run, HEAD, gate, command fingerprint) tuple. A waiver
    # file alone changes nothing — the check must pass. On valid: consume the
    # single-use waiver, stamp result=waived + waiver_ref, and record the gate
    # in waived_gates[]. overall then treats it like a pass (the required-fail
    # branch below is skipped because final_result is no longer "fail"), but
    # the top-level waived_gates[] array keeps it visible in PM/release
    # evidence. A waiver present but failing check for ANY reason leaves the
    # result "fail" and records waiver_rejected:<verdict> on the row.
    if [[ "$final_result" == "fail" ]]; then
      local _wv_ev_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
      local _wv_file="${_wv_ev_dir}/waivers/gate-waiver-${gate_name}.json"
      if [[ -f "$_wv_file" ]]; then
        local _wv_head _wv_cmd_sha _wv_verdict _wv_rc
        _wv_head=$(git rev-parse HEAD 2>/dev/null || echo "")
        _wv_cmd_sha=$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)
        _wv_rc=0
        _wv_verdict=$("${SCRIPT_DIR}/aid-gate-waiver.sh" check "$gate_name" \
          --evidence-dir "$_wv_ev_dir" --head "$_wv_head" \
          --command-sha "$_wv_cmd_sha" --epic "$epic_id" --run "$run_id" 2>/dev/null) || _wv_rc=$?
        if [[ "$_wv_rc" -eq 0 && "$_wv_verdict" == "valid" ]]; then
          # IMP-270 review F1: consumption must be DURABLE before we waive. If
          # consume fails (read-only dir, ENOSPC, lock lost) the single-use
          # waiver is not spent and would be replayable, so fail closed —
          # leave the gate `fail` with waiver_rejected:consume_failed rather
          # than stamping a waived result on an unconsumed waiver.
          local _wv_consume_rc=0
          "${SCRIPT_DIR}/aid-gate-waiver.sh" consume "$gate_name" \
            --evidence-dir "$_wv_ev_dir" --by-run "$run_id" >/dev/null 2>&1 || _wv_consume_rc=$?
          if [[ "$_wv_consume_rc" -ne 0 ]]; then
            gate_result=$(echo "$gate_result" | jq '.waiver_rejected = "consume_failed"')
          else
            gate_result=$(echo "$gate_result" | jq \
              --arg ref "waivers/gate-waiver-${gate_name}.json" \
              '.result = "waived" | .waiver_ref = $ref')
            final_result="waived"
            waived_gates+=("$gate_name")
          fi
        else
          gate_result=$(echo "$gate_result" | jq --arg v "$_wv_verdict" '.waiver_rejected = $v')
        fi
      fi
    fi

    log_event "$timeline_file" "gate_complete" gate="$gate_name" result="$final_result" attempt="$attempt"

    # ─── P069 Step 14 — targeted_tests escalation detection ───────────────
    # Exit 3 (D-selector-1 unverifiable) / exit 11 (Step 10 mapping_gap) are
    # NEVER treated as an ordinary gate failure and NEVER as a pass — a
    # required:false targeted_tests row failing this way must not let the
    # WHOLE RUN'S overall verdict silently rest on a selector that verified
    # nothing. `result` on THIS row is left completely UNCHANGED (still the
    # existing plain "fail", or "waived" if a valid waiver applied above —
    # never a new enum value, matching test-aid-run-gates.bats's own
    # pre-existing, byte-for-byte-preserved assertion on this exact
    # scenario) — escalation is recorded as PURELY ADDITIVE metadata: a new,
    # optional `escalation` sibling field on this SAME row, plus a run-level
    # flag consumed once, after this entire pass's own report is fully
    # assembled, to trigger a genuinely-executed --profile full substitute.
    if [[ "$gate_name" == "targeted_tests" ]]; then
      local _esc_exit_code; _esc_exit_code=$(echo "$gate_result" | jq -r '.exit_code')
      if [[ "$_esc_exit_code" == "3" || "$_esc_exit_code" == "11" ]]; then
        local _esc_output _esc_path
        _esc_output=$(echo "$gate_result" | jq -r '.output')
        _esc_path=$(grep -oE '(unverifiable: unknown production path [^ ]+|mapping_gap: no approved mapping row matches [^ ]+)' <<<"$_esc_output" | head -1 | awk '{print $NF}')
        [[ -z "$_esc_path" ]] && _esc_path="unknown"
        escalation_triggered=true
        escalation_reason="exit_code ${_esc_exit_code}: ${_esc_path}"
        gate_result=$(echo "$gate_result" | jq --argjson ec "$_esc_exit_code" --arg path "$_esc_path" \
          '.escalation = {triggered: true, exit_code: $ec, path: $path}')
      fi
    fi

    # Add to gates JSON aggregate. `runtime_baseline` (P063 Step 2) is purely
    # additive — gate_baseline_report_json always returns a valid JSON object
    # (a zeroed/null-filled one when there's no entry yet or yq/jq is
    # missing), never a bare `null`, so this merge never removes/renames any
    # existing key.
    local runtime_baseline_json runtime_baseline_nc
    runtime_baseline_json=$(gate_baseline_report_json "$gate_name" 2>/dev/null)
    [[ -z "$runtime_baseline_json" ]] && runtime_baseline_json='null'
    runtime_baseline_nc=$(jq -r '.non_censored_samples_count // 0' <<<"$runtime_baseline_json" 2>/dev/null)
    [[ "$runtime_baseline_nc" =~ ^[0-9]+$ ]] && (( runtime_baseline_nc >= 5 )) && baseline_summary_gates+=("$gate_name")

    # ─── P076 Step 3 — run_mode advice collection (observe-only) ───────────
    # Same already-fetched runtime_baseline_json, no extra read. The
    # recommendation itself carries the library's rules (>= 5 non-censored
    # samples AND p95 > 10 min → "background"; anything else → null or
    # "foreground"), so nothing is re-derived here. An unreadable/absent
    # baseline yields null → no advice, no failure (fail-open telemetry).
    local _advice_rec _advice_p95
    _advice_rec=$(jq -r '.run_mode_recommended // "null"' <<<"$runtime_baseline_json" 2>/dev/null || echo null)
    if [[ "$_advice_rec" == "background" ]] && ! _run_mode_declared "$execution_yaml" "$gate_name"; then
      _advice_p95=$(jq -r '.p95_ms // "null"' <<<"$runtime_baseline_json" 2>/dev/null || echo null)
      [[ "$_advice_p95" =~ ^[0-9]+$ ]] || _advice_p95="null"
      run_mode_advice_gates+=("${gate_name}|${_advice_p95}")
    fi
    $first || gates_json+=","
    first=false
    local merged_row
    merged_row=$(echo "$gate_result" | jq --argjson rb "$runtime_baseline_json" ". + {\"attempts\":${attempt}, \"runtime_baseline\": \$rb}")
    gates_json+="\"${gate_name}\":${merged_row}"
    processed=$((processed+1))

    # P076 Step 2 — durable incremental checkpoint of the COMPLETED row.
    _gate_row_checkpoint "$_rows_dir" "$gate_name" "$merged_row" "$_rows_head" \
      "$_rows_tree" "$_rows_key" "$_rows_home"

    # ─── command_log entry (P032 Step 3 provenance) ──────────────────
    local exit_code dur_ms
    exit_code=$(echo "$gate_result" | jq -r '.exit_code')
    dur_ms=$(echo "$gate_result" | jq -r '.duration_ms')
    command_log+=("$(jq -nc \
      --arg name "$gate_name" \
      --arg command "$cmd" \
      --argjson exit "$exit_code" \
      --argjson dur "$dur_ms" \
      '{name:$name, command:$command, exit_code:$exit, duration_ms:$dur}')")

    # Mark overall fail if required gate fails
    if [[ "$final_result" == "fail" && "${required:-false}" == "true" ]]; then
      overall="fail"
    fi
  done <<< "$gate_names"
  unset AID_CURRENT_GATE_ID

  # ─── restore checkpointed rows this invocation did not produce (P076 S2) ──
  # The other half of the incremental checkpoint: the in-memory rows above are
  # read exactly as before, AND any gate that already has a durable row file
  # but produced no row in THIS invocation is restored from it, verbatim and
  # authoritative. That is what a rerun after a crash assembles from — the
  # finished suite is not re-executed to reproduce a row that already exists.
  #
  # Only DEFINED gates are restored: a row file for a gate that execution.yaml
  # no longer declares is not this run's business, and counting it would break
  # the defined==processed assert below. The membership test is anchored by the
  # opening quote (`"name":`), so gate `a` never matches inside gate `ba`.
  #
  # A row file is authoritative only for the REVISION it was produced at AND
  # only when THIS RUN's own writers produced it. Every checkpoint carries a
  # `_checkpoint` envelope of {head, tree, key}; a row whose envelope is missing
  # (an older runner, or a jq failure at write time), whose head or tree has
  # since moved, or whose keyed binding does not verify against this run's
  # secret, is NEVER restored as a pass. It is replaced by an explicit
  # `gate_row_stale` FAIL row, which still counts toward `processed` — so the
  # defined==processed integrity assert keeps holding — and still forces
  # overall=fail when the gate is required. Refusal, not silence: "this gate has
  # no current result" must look different from "this gate passed".
  #
  # The key check is what closes the demonstrated forgery: a hand-written row
  # carrying the current HEAD used to replay as a required-gate PASS, because
  # HEAD is public and readable by anything that can write the row file. It also
  # fails closed on its own inputs — no run key (no evidence directory, or an
  # unwritable/corrupt key file) means EVERY row is refused, never accepted.
  if [[ -n "$_rows_dir" && -d "$_rows_dir" ]]; then
    local _rf _rg _rrow _rec_head _rec_tree _rec_key _want_key _stale_reason _required_rg
    for _rf in "$_rows_dir"/*.json; do
      [[ -f "$_rf" ]] || continue
      _rg="$(basename "$_rf" .json)"
      [[ "$gates_json" == *"\"${_rg}\":"* ]] && continue
      grep -qxF "$_rg" <<< "$gate_names" || continue
      # The lost-gate fault injection simulates a row that was never produced;
      # restoring one from an earlier run would defeat the very assert it feeds.
      [[ -n "${AID_TEST_DROP_GATE:-}" && "$_rg" == "${AID_TEST_DROP_GATE}" ]] && continue
      _rrow="$(jq -c '.' "$_rf" 2>/dev/null)" || continue
      [[ -z "$_rrow" || "$_rrow" == "null" ]] && continue

      _rec_head="$(jq -r '._checkpoint.head // ""' <<<"$_rrow" 2>/dev/null || echo "")"
      _rec_tree="$(jq -r '._checkpoint.tree // ""' <<<"$_rrow" 2>/dev/null || echo "")"
      _rec_key="$(jq -r '._checkpoint.key // ""' <<<"$_rrow" 2>/dev/null || echo "")"
      _want_key="$(aid_gate_row_binding_key "$_rows_key" "$_rg" "$_rows_head" "$_rows_tree" "$_rows_home")"
      _stale_reason=""
      if [[ -z "$_rec_head" ]]; then
        _stale_reason="row_not_bound_to_a_revision"
      elif _job_head_drifted "$_rec_head" "$_rows_head"; then
        _stale_reason="start_head_moved"
      elif [[ -z "$_rec_tree" ]] || { [[ -n "$_rows_tree" ]] && [[ "$_rec_tree" != "$_rows_tree" ]]; }; then
        _stale_reason="start_tree_moved"
      elif [[ -z "$_want_key" ]]; then
        _stale_reason="run_key_unavailable"
      elif [[ "$_rec_key" != "$_want_key" ]]; then
        _stale_reason="row_not_written_by_this_run"
      fi

      _required_rg="$(yq ".gates.\"${_rg}\".required // false" "$execution_yaml")"
      $first || gates_json+=","
      first=false
      if [[ -n "$_stale_reason" ]]; then
        gates_json+="\"${_rg}\":$(jq -nc --arg g "$_rg" --arg sr "$_stale_reason" \
          --arg rec "$_rec_head" --arg cur "$_rows_head" --arg src "$_rf" \
          '{gate:$g, result:"fail", exit_code:1, duration_ms:0, attempts:0,
            output:("checkpointed gate row at " + $src + " is not valid for the current revision (" + $sr + "); the gate did not run in this invocation"),
            reason:"gate_row_stale", stale_reason:$sr,
            recorded_head:(if $rec == "" then null else $rec end),
            current_head:(if $cur == "" then null else $cur end)}')"
        processed=$((processed+1))
        log_event "$timeline_file" "gate_row_stale" gate="$_rg" source="$_rf" \
          reason="$_stale_reason" recorded_head="$_rec_head" current_head="$_rows_head"
        if [[ "$_required_rg" == "true" ]]; then overall="fail"; fi
      else
        gates_json+="\"${_rg}\":${_rrow}"
        processed=$((processed+1))
        log_event "$timeline_file" "gate_row_restored" gate="$_rg" source="$_rf" \
          head="$_rec_head"
        if [[ "$(jq -r '.result // ""' <<<"$_rrow")" == "fail" ]] \
           && [[ "$_required_rg" == "true" ]]; then
          overall="fail"
        fi
      fi
    done
  fi

  # ─── Close the ledger, and evaluate it ───────────────────────────────────
  # `close` is where the duplicate check actually runs. Opening a ledger and
  # never closing it would be a detector with no consumer — the exact shape
  # this project's registry exists to prevent.
  #
  # A detected double execution is recorded on the report rather than silently
  # tolerated. It does not fail the gate PASS/FAIL verdict, which belongs to
  # the gates themselves; it is a run-level finding about the run's own shape,
  # and it is visible because the alternative is double-counting wall clock
  # forever.
  if [[ -n "${_ledger_path:-}" && -f "${_ledger_path}" ]]; then
    local _ledger_out _ledger_rc=0
    _ledger_out="$(bash "${SCRIPT_DIR}/aid-test-execution-ledger.sh" close --path "$_ledger_path" 2>&1)" || _ledger_rc=$?
    # Any failure OTHER than "duplicates found" means the ledger could not be
    # evaluated at all, which is not a clean run — it is an unknown one.
    if [[ "$_ledger_rc" -ne 0 && "$_ledger_rc" -ne 7 ]]; then
      echo "ERROR: aid-run-gates.sh: the execution ledger could not be closed or evaluated (exit ${_ledger_rc}): ${_ledger_out}" >&2
      unset AID_EXECUTION_LEDGER
      # Same rule as the append path: no return from this function leaves a
      # service this invocation acquired still running.
      _svc_release_run "$_evidence_dir" "$execution_yaml"
      return 3
    fi
    if [[ "$_ledger_rc" -eq 7 ]]; then
      echo "$_ledger_out" >&2
      gates_json+=",\"_execution_ledger\":$(jq -c '{path:$p, duplicates:.summary.duplicates, dispatched:.summary.dispatched}' \
        --arg p "$_ledger_path" "$_ledger_path")"
    else
      gates_json+=",\"_execution_ledger\":$(jq -c '{path:$p, duplicates:(.summary.duplicates // []), dispatched:(.summary.dispatched // 0)}' \
        --arg p "$_ledger_path" "$_ledger_path" 2>/dev/null || echo '{}')"
    fi
    unset AID_EXECUTION_LEDGER
  elif [[ -n "$_ledger_unaccounted_reason" ]]; then
    gates_json+=",\"_execution_ledger\":$(jq -nc --arg r "$_ledger_unaccounted_reason" '{accounted:false, reason:$r}')"
  fi

  # ─── defined==processed integrity assert (OBS-20260708-07) ──────────────
  # `gate_count` (yq '.gates | length') is `defined`; `processed` is the number
  # of defined-gate result rows actually emitted above. If they differ, a gate
  # was silently lost (e.g. a stdin-consuming gate ate the here-string) and the
  # run must NEVER be reported as green: emit an explicit _integrity row and
  # force overall=fail. The row respects the `first` comma flag even when 0
  # gates were processed, so the JSON stays valid. `_integrity` is diagnostic
  # metadata — it does NOT count toward `processed` or `defined`.
  if [[ "$processed" != "$gate_count" ]]; then
    overall="fail"
    log_event "$timeline_file" "gate_integrity_fail" defined="$gate_count" processed="$processed"
    $first || gates_json+=","
    first=false
    gates_json+="\"_integrity\":{\"result\":\"fail\",\"reason\":\"gate_count_mismatch\",\"defined\":${gate_count},\"processed\":${processed}}"
  fi

  # ─── plan.json ⇄ execution.yaml gate reconciliation (P060 Step 2, OBS-20260702-05) ──
  # A gate declared in plan.json.gates[] but NOT defined in execution.yaml would
  # otherwise silently never run while overall reports pass (F1). For each such
  # gate emit an explicit undefined_gate fail row and force overall=fail.
  # Counter-universe contract (shared with the Step-1 _integrity assert above):
  # these reconciliation rows are NOT defined gates — they MUST NOT increment
  # `processed` and MUST NOT count toward `defined` (=gate_count). They only
  # append to gates_json (respecting the `first` comma flag) and set overall.
  local plan_gates_reconciled=false
  if [[ -n "$plan_json" && -f "$plan_json" ]]; then
    plan_gates_reconciled=true
    # Defined gate keys from execution.yaml (mikefarah yq → JSON array).
    local defined_keys_json
    defined_keys_json=$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')
    # Declared gates from plan.json.gates[] (jq). Absent/empty → no rows emitted.
    # Process substitution (not a pipe) keeps the loop in this shell so overall/
    # first/gates_json mutations persist.
    local declared_gate
    while IFS= read -r declared_gate; do
      [[ -z "$declared_gate" ]] && continue
      # Defined in execution.yaml? (jq any over the keys array, --arg-safe.)
      if jq -e --arg g "$declared_gate" 'any(.[]; . == $g)' <<< "$defined_keys_json" >/dev/null 2>&1; then
        continue
      fi
      overall="fail"
      log_event "$timeline_file" "gate_complete" gate="$declared_gate" result="fail" reason="undefined_gate"
      $first || gates_json+=","
      first=false
      gates_json+="\"${declared_gate}\":{\"gate\":\"${declared_gate}\",\"result\":\"fail\",\"reason\":\"undefined_gate\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"gate declared in plan.json but not defined in execution.yaml\",\"attempts\":0}"
    done < <(jq -r '.gates // [] | .[]' "$plan_json" 2>/dev/null)
  fi

  gates_json+="}"

  local completed_at
  completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build base report
  local report
  report="{\"epic_id\":\"${epic_id}\",\"run_id\":\"${run_id}\",\"overall\":\"${overall}\",\"completed_at\":\"${completed_at}\",\"gates\":${gates_json}}"

  # ─── jq-merge provenance fields (P032 Step 3) ──────────────────────
  local command_log_array
  if (( ${#command_log[@]} == 0 )); then
    command_log_array="[]"
  else
    command_log_array=$(printf '%s\n' "${command_log[@]}" | jq -s '.')
  fi

  local generated_by="aid-run-gates.sh@${PLUGIN_VERSION}"
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # ─── coverage/relevance fields (E2 C1 Delivery Engine) ────────────────────
  # Read $AID_CHANGED_PATHS (env var pointing to a file with one path per line).
  # Produces: covered_paths[], changed_paths_covered, relevance.
  local covered_paths_json="[]"
  local changed_paths_covered="false"
  local relevance="unknown"

  if [[ -n "${AID_CHANGED_PATHS:-}" && -f "${AID_CHANGED_PATHS}" ]]; then
    local matched_paths=()
    while IFS= read -r changed_path; do
      [[ -z "$changed_path" ]] && continue
      # If the changed path exists on disk, consider it matched
      if [[ -e "$changed_path" ]]; then
        matched_paths+=("$changed_path")
      fi
    done < "${AID_CHANGED_PATHS}"

    if (( ${#matched_paths[@]} > 0 )); then
      covered_paths_json=$(printf '%s\n' "${matched_paths[@]}" | jq -R . | jq -s '.')
      changed_paths_covered="true"
      relevance="direct"
    else
      relevance="none"
    fi
  fi

  # ─── revision.head_sha stamping (P060 Step 2, substrate for Step 8) ───────────
  # gates_report today has no binding to the commit it evaluated. Stamp the HEAD
  # SHA at report-write time. If git is unavailable/not a repo, set head_sha null
  # (never fail the run over provenance metadata).
  local head_sha revision_json
  head_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [[ -n "$head_sha" ]]; then
    revision_json=$(jq -nc --arg h "$head_sha" '{head_sha:$h}')
  else
    revision_json='{"head_sha":null}'
  fi

  # ─── gate profile fields (P061 E1 Step 2) ──────────────────────────────
  # profile/profile_source/profile_reason stay JSON null when --profile
  # wasn't passed (legacy-compat: field present, value absent-equivalent).
  # excluded_gates is always an array, empty when no gate was excluded.
  local profile_val_json="null" profile_source_val_json="null" profile_reason_val_json="null"
  if [[ -n "$profile" ]]; then
    profile_val_json=$(jq -nc --arg v "$profile" '$v')
    profile_source_val_json=$(jq -nc --arg v "$profile_source" '$v')
    profile_reason_val_json=$(jq -nc --arg v "$profile_reason" '$v')
  fi
  local excluded_gates_json
  if (( ${#excluded_gates[@]} == 0 )); then
    excluded_gates_json="[]"
  else
    excluded_gates_json=$(printf '%s\n' "${excluded_gates[@]}" | jq -R . | jq -s '.')
  fi

  # ─── waived_gates[] (IMP-270) ──────────────────────────────────────────
  # Always an array; empty when no gate was waived. A required gate reported
  # `waived` never flips overall to fail, so this is the one place PM/release
  # evidence can see, at a glance, that a required gate was accepted without
  # passing — surfaced top-level so nothing downstream can miss it.
  local waived_gates_json
  if (( ${#waived_gates[@]} == 0 )); then
    waived_gates_json="[]"
  else
    waived_gates_json=$(printf '%s\n' "${waived_gates[@]}" | jq -R . | jq -s '.')
  fi

  report=$(jq --arg gen "$generated_by" \
              --arg ts  "$generated_at" \
              --argjson cl "$command_log_array" \
              --argjson cp "$covered_paths_json" \
              --argjson ccov "$changed_paths_covered" \
              --arg rel "$relevance" \
              --argjson pgr "$plan_gates_reconciled" \
              --argjson rev "$revision_json" \
              --argjson prof "$profile_val_json" \
              --argjson profsrc "$profile_source_val_json" \
              --argjson profreason "$profile_reason_val_json" \
              --argjson excl "$excluded_gates_json" \
              --argjson waived "$waived_gates_json" \
              '. + {_generated_by: $gen, _generated_at: $ts, _command_log: $cl, covered_paths: $cp, changed_paths_covered: $ccov, relevance: $rel, plan_gates_reconciled: $pgr, revision: $rev, profile: $prof, profile_source: $profsrc, profile_reason: $profreason, excluded_gates: $excl, waived_gates: $waived}' \
              <<< "$report")

  # ─── P069 Step 14 — targeted_tests escalation: full-profile substitute ──
  # Triggered ONLY by targeted_tests's own exit 3/11 (set inline above,
  # regardless of scheduler mode). A SECOND, entirely separate
  # run_all_gates()-style pass — invoked as its own subprocess against the
  # SAME epic_id/run_id, never an in-process recursive call sharing this
  # invocation's own gates_json/processed/gate_count state — produces its
  # OWN complete report. That report becomes the actual, verdict-bearing
  # result verbatim; this pass's own (targeted) report is preserved
  # underneath as informational metadata only, via merge_escalation_report.
  #
  # Codex review (HIGH): compose_execution_yaml/render_gate_profiles_block
  # never put targeted_tests in a generated `full` profile, but a
  # HAND-AUTHORED execution.yaml is free to — profile include[] validation
  # (above) only checks that named gates exist, never which profile they
  # belong to. If `full` ever also included targeted_tests, the subprocess
  # below would hit the identical exit 3/11 and spawn ANOTHER escalation,
  # unbounded. Refusing to escalate whenever THIS invocation's own active
  # profile is already "full" closes that off structurally: escalating
  # "full" to "full" is meaningless regardless of profile contents, so
  # this guard needs no assumption about what `full` does or doesn't
  # include.
  if $escalation_triggered && [[ "$profile" != "full" ]]; then
    echo "aid-run-gates.sh: targeted_tests escalated (${escalation_reason}) — running a full --profile substitute" >&2
    local full_escalation_report_path="${report_path}.full-escalation.json"
    # Codex review: a STALE report from an earlier escalation attempt at
    # this same path must never be mistaken for this run's own output if
    # the subprocess below fails before writing anything — remove it
    # first so the "no report file" fallback branch is only ever reached
    # on a genuine failure, never a leftover from a previous run.
    rm -f "$full_escalation_report_path"
    local -a escalation_args=(run-all "$execution_yaml" "$epic_id" "$run_id" --profile full --report-file "$full_escalation_report_path")
    if [[ -n "$base_commit_resolved" && "$base_commit_resolved" != "null" ]]; then
      escalation_args+=(--base-commit "$base_commit_resolved")
    fi
    if [[ -n "$plan_path_resolved" && "$plan_path_resolved" != "null" ]]; then
      escalation_args+=(--plan-path "$plan_path_resolved")
    fi
    if [[ -n "$plan_json" ]]; then
      escalation_args+=(--plan-json "$plan_json")
    fi
    # Everything this subprocess dispatches is a DELIBERATE rerun: it inherits
    # the parent's AID_EXECUTION_LEDGER, so without this marker the escalation
    # re-running the same units under the full profile would be recorded as an
    # accidental double execution and fail a run that behaved correctly.
    # The escalation is a CONSUMER of this run's services, never their owner —
    # see the acquire block. Without this it would sweep the services THIS
    # invocation is still holding, which is the parallel-teardown race in its
    # most literal form: one runner tearing a service down under another.
    AID_EXECUTION_KIND=escalation AID_SERVICE_LIFECYCLE_OWNED=1 \
      bash "${BASH_SOURCE[0]}" "${escalation_args[@]}" >/dev/null 2>&1 || true
    if [[ -f "$full_escalation_report_path" ]]; then
      local full_report_json; full_report_json="$(cat "$full_escalation_report_path")"
      report="$(merge_escalation_report "$report" "$full_report_json" "$escalation_reason")"
      # Codex review (HIGH): the merged report's own .overall now reflects
      # the FULL pass's real verdict, but this function's own exit status
      # and gates_complete/gate_runner_complete log events below still
      # read the shell-local $overall variable — which was computed
      # BEFORE this merge and still holds the ORIGINAL targeted-only
      # pass's verdict. Left unfixed, the persisted report and the
      # command's own exit code could disagree (e.g. report says "pass"
      # while the command exits 1, or vice versa). Recompute from the
      # merged report so both stay in agreement.
      overall="$(jq -r '.overall' <<<"$report")"
    else
      report="$(jq --arg reason "$escalation_reason" \
        '. + {escalation: {triggered_by:"targeted_tests", reason:$reason, targeted_run:null, error:"full-profile escalation run failed to produce a report"}}' \
        <<<"$report")"
    fi
  fi

  echo "$report"

  # Persist gates_report.json if --report-file specified
  if [[ -n "$report_file" ]]; then
    mkdir -p "$(dirname "$report_file")"
    # Atomic write via tmp + mv (so concurrent FSM read sees full report)
    echo "$report" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
  fi

  # ─── Services: RELEASE ONCE (P076 Step 10) ───────────────────────────────
  # AFTER the report is written and echoed, on both the pass and the fail path,
  # and exactly once for the whole run. Cleanup never un-writes evidence: if the
  # teardown does not fully succeed the run still reports what the gates found,
  # and the failure is a warning naming the manual commands.
  if (( _SVC_ACQUIRED == 1 )); then
    _svc_release_run "$_evidence_dir" "$execution_yaml"
    log_event "$timeline_file" "services_released" declared="$_svc_count"
  fi

  # Existing per-run completion event (kept for backward compat)
  log_event "$timeline_file" "gates_complete" overall="$overall" epic_id="$epic_id"

  # ─── gate_runner_complete (P032 Step 3) ────────────────────────────
  local total_duration=$((SECONDS - run_start))
  log_event "$timeline_file" "gate_runner_complete" \
    report_path="$report_path" overall="$overall" duration_sec="$total_duration"

  # ─── Gate runtime baseline summary (P063 Step 2) ───────────────────────
  # Human-readable, one line per gate whose baseline has "enough data to
  # trust" (non_censored_samples_count >= 5 — matches
  # gate_baseline_recommend_run_mode's own threshold). `baseline_summary_gates`
  # was populated inline at merge time above (reusing the runtime_baseline
  # JSON already fetched there for THIS run's gates only — never a second
  # full re-scan of every defined gate, which would re-pay yq/jq subprocess
  # cost for profile_excluded/skipped/never-run gates for no benefit).
  # Printed to stderr only — stdout carries exactly the final JSON `report`
  # line consumed by callers/tests (`run-all ... | jq`).
  if (( ${#baseline_summary_gates[@]} > 0 )); then
    local baseline_summary_gate
    for baseline_summary_gate in "${baseline_summary_gates[@]}"; do
      gate_baseline_show "$baseline_summary_gate" >&2
    done
  fi

  # ─── run_mode advice (P076 Step 3) ─────────────────────────────────────
  # The first behavioural consumer of gate_baseline_recommend_run_mode, and
  # deliberately the mildest one: a named timeline event carrying the exact
  # one-line edit, once per gate per run. It changes NOTHING about how any gate
  # ran — the run is already over at this point, the report is written, and the
  # decision to flip stays a human one. The edit string is built from the gate
  # name alone, so it is copy-pasteable in any consumer project.
  if (( ${#run_mode_advice_gates[@]} > 0 )); then
    local _advice_entry _advice_gate_name _advice_gate_p95
    for _advice_entry in "${run_mode_advice_gates[@]}"; do
      _advice_gate_name="${_advice_entry%|*}"
      _advice_gate_p95="${_advice_entry##*|}"
      # Once per gate per RUN, not per invocation: a targeted pass that
      # escalates re-enters this script as a subprocess writing to the SAME
      # run timeline, and a gate present in both passes must still be advised
      # exactly once. Cheap because the advice list is normally empty.
      if [[ -f "$timeline_file" ]] && jq -se --exit-status --arg g "$_advice_gate_name" \
           'any(.[]; .event == "gate_run_mode_advice" and .gate == $g)' \
           "$timeline_file" >/dev/null 2>&1; then
        continue
      fi
      log_event "$timeline_file" "gate_run_mode_advice" \
        gate="$_advice_gate_name" \
        p95_ms="$_advice_gate_p95" \
        edit="set gates.${_advice_gate_name}.run_mode: background in .aid-o/config/execution.yaml"
    done
  fi

  [[ "$overall" == "pass" ]] && return 0 || return 1
}

# Dispatch
case "${1:-}" in
  run-gate)  shift; run_gate "$@" ;;
  run-all)   shift; run_all_gates "$@" ;;
  *)
    # Source mode — functions available to caller
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
    echo "Usage: aid-run-gates.sh <run-gate|run-all> [args...]" >&2; exit 1 ;;
esac
