#!/usr/bin/env bash
# aid-run-gates.sh — the gate runner.
#
# WHY THIS FILE EXISTS: it is the one program that turns the gate table in
# execution.yaml into a gates_report.json. It reads each gate's `command`,
# `required`, `timeout_seconds`, `max_retries` and `run_mode`, runs the
# command (inline, or as an aid-job.sh job for `run_mode: background`), and
# writes one version-2 row per defined gate (lib/aid-gate-row.sh) plus the
# `overall` verdict, which fails only on a failed `required: true` gate that no
# PM waiver covers. It chooses nothing: the caller names the profile
# (--profile, resolved by lib/aid-gate-profile-select.sh), the file names the
# deadline, and a configuration key the runner no longer reads
# (`_refuse_dead_keys` below) stops the run with exit 2 and the upgrade
# command instead of being ignored. The FSM's
# GATES:DONE precondition trusts a report only when this file wrote it
# (`_generated_by`).
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
# Profiles (P061 E1 Step 2, reshaped by P097 Step 4):
#   • --profile <name> runs exactly execution.yaml.gate_profiles.<name>.include[]
#     and nothing else decides. Gates outside the profile get an explicit
#     `status: skip, reason: not_in_profile` row and never affect `overall`.
#     Omitting --profile runs every defined gate.
#   • The name is validated through lib/aid-gate-profile-select.sh BEFORE any
#     gate runs: an unknown name, or a profile whose include[] names no
#     `required: true` gate (a run that can only skip is not a run), exits 2
#     naming the declared profiles and the upgrade command. An include[] entry
#     that is not a key under gates, or names a gate without a command, exits 1.
#   • gates_report.json records `profile` (null without --profile),
#     `profile_source: caller|none`, `profile_table` (the declared names in
#     order — the GATES:DONE floor compares indexes within THIS list) and
#     `excluded_gates[]`.
#
# P097 Step 2 — every row is a version-2 gate row (lib/aid-gate-row.sh,
#   defaults/schemas/gate-row.schema.json): `row_version: 2`, `status`
#   pass|fail|skip, a `reason` from the closed vocabulary, `duration_ms`,
#   `started_at`/`completed_at`, `evidence`, `required`, `waived`,
#   `reused_from`, and `result` as the derived version-1 compatibility field.
#   The rows are stamped in ONE place (`_gate_row_finalize`) on their way into
#   the report and the checkpoint file, and a row whose reason is outside the
#   vocabulary fails the run naming the gate.
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
#   {evidence_dir} — this run's evidence directory, resolved against the STATE root
#                    (the primary checkout's .aid-o), so a gate run from a plan
#                    worktree finds the evidence the FSM wrote — a relative
#                    `.aid-o/work/evidence/...` in a gate command does not.
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
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# P097 Step 4 — the one profile resolver (names, ranks, refusals).
source "${SCRIPT_DIR}/lib/aid-gate-profile-select.sh"

# ─── State paths vs the tree under test (P079 Step 2, IMP-479) ──────────────
# Two different roots meet in this file and used to be the same one by
# accident:
#
#   the TREE UNDER TEST — the caller's cwd. Gate COMMANDS run there, and the
#   report's head_sha describes it. That contract is deliberate and unchanged:
#   a gate must see the candidate code.
#
#   the STATE ROOT — where `.aid-o` lives. It is the primary checkout and never
#   moves into a worktree, so every STATE artifact this runner writes or reads
#   (timeline, report, ledger, waivers, project config) belongs there.
#
# Before this step both were "whatever cwd happened to be", so a worktree run
# wrote its evidence into a `.aid-o` the primary checkout could not see — and
# where the directory did not exist, the guarded writers below simply went
# quiet. `_gates_state_path` resolves the state root and keeps the historic
# relative form when invoked AT that root; the printf fallback keeps fixtures
# that run outside any git repository byte-identical.
_gates_state_path() {
  aid_state_path "$1" 2>/dev/null || printf '%s' "$1"
}

# _gates_evidence_dir <epic_id> <run_id> — this run's evidence directory,
# state-root resolved. The one place the layout is spelled out.
_gates_evidence_dir() {
  _gates_state_path ".aid-o/work/evidence/${1}/${2}"
}

# ─── Recovery-ladder emitters (P076 Step 13) ────────────────────────────────
# The ladder RECORDS and ROUTES; it never replaces a verdict. Every call below
# is additive: the gate's `job_timeout` or `job_lost` row is written exactly as
# it would be without the ladder, and a ladder that cannot be loaded or cannot
# be written changes nothing at all.
#
# Sourced LAZILY and BEST-EFFORT (the opposite discipline from
# aid-resume-artifact.sh above, on purpose): those definitions are load-bearing
# for a gate's correctness, this one is evidence. Failing a gate run because a
# recovery record could not be written would be the ladder replacing a verdict.
_AID_GATE_LADDER_STATE=""   # "" untried | "ok" | "no"
_gate_ladder_emit() {
  local class="$1" emitter="$2" detail="${3:-}" dir="${_evidence_dir:-}"
  [[ -n "$dir" && -d "$dir" ]] || return 0
  if [[ -z "$_AID_GATE_LADDER_STATE" ]]; then
    _AID_GATE_LADDER_STATE="no"
    if [[ -f "${SCRIPT_DIR}/lib/aid-recovery-ladder.sh" ]]; then
      # shellcheck source=lib/aid-recovery-ladder.sh
      source "${SCRIPT_DIR}/lib/aid-recovery-ladder.sh" >/dev/null 2>&1 \
        && declare -F aid_ladder_emit >/dev/null 2>&1 \
        && _AID_GATE_LADDER_STATE="ok"
    fi
  fi
  [[ "$_AID_GATE_LADDER_STATE" == "ok" ]] || return 0
  # stdout is muted deliberately: several callers of this helper have a GATE ROW
  # on their own stdout, and one stray line there would corrupt the report.
  aid_ladder_emit "$dir" "$class" "$emitter" "$detail" >/dev/null 2>&1 || true
  return 0
}

PLUGIN_VERSION="${PLUGIN_VERSION:-v2.16.0}"

# Phase 2 (P037) — resolve {token} placeholders in gate commands via bash parameter expansion.
# Recognized tokens: {plan_path}, {epic_id}, {run_id}, {base_commit}, {plugin_path}, {evidence_dir}.
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
  cmd="${cmd//\{evidence_dir\}/$(_gates_evidence_dir "$epic" "$run")}"
  [[ -n "$plugin_path" ]] && cmd="${cmd//\{plugin_path\}/$plugin_path}"

  # Fail-loud on any remaining {<token>} — gate authors must not introduce unknown placeholders
  if [[ "$cmd" =~ \{[a-zA-Z_]+\} ]]; then
    local bad_token="${BASH_REMATCH[0]}"
    echo "ERROR: aid-run-gates.sh: unknown placeholder $bad_token in gate command" >&2
    echo "  Valid tokens: {plan_path}, {epic_id}, {run_id}, {base_commit}, {plugin_path}, {evidence_dir}" >&2
    return 1
  fi

  printf '%s' "$cmd"
}

run_gate() {
  local gate_name="$1"
  local command="$2"
  local timeout_s="${3:-60}"
  local log_file="${4:-/dev/null}"

  local start_ms started_at
  start_ms=$(date +%s%3N)
  started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local output exit_code=0
  # </dev/null: a stdin-consuming gate (ssh, cat, …) must NOT inherit the
  # driver's stdin — in run_all_gates that stdin is the here-string of remaining
  # gate names, and eating it silently starves every subsequent gate while
  # overall still reports pass (OBS-20260708-07).
  output=$(LC_ALL=C timeout "$timeout_s" bash -c "$command" </dev/null 2>&1) || exit_code=$?

  local end_ms completed_at
  end_ms=$(date +%s%3N)
  completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local duration_ms=$(( end_ms - start_ms ))

  local result="pass" reason=""
  [[ $exit_code -ne 0 ]] && result="fail"
  # `timeout(1)` exits 124 when the deadline passed: the row says so by name
  # (the closed vocabulary's `job_timeout`, the same reason a background gate's
  # supervisor reports), never as a bare `exit_124` a reader has to decode.
  [[ $exit_code -eq 124 ]] && reason="job_timeout"
  # A gate that exits 0 while its own output says it looked at nothing did not
  # pass, it did not run. The list is closed and literal on purpose: "0 errors"
  # is a result, "0 files checked" is an absence. A fan-out gate with one empty
  # sub-run among real ones is not vacuous: any positive count clears it.
  if [[ "$result" == pass ]] && grep -qiE \
       '(^|[^0-9])0 (source )?files (checked|processed|linted|scanned)|(checked|found|in) 0 (source )?files|collected 0 items|no tests (ran|found)|ran 0 tests|^1\.\.0( |$)|\[no test files\]' <<<"$output" \
     && ! grep -qiE '(^|[^0-9])[1-9][0-9]* (source )?(files?|tests?|items?|passed)|^ok( |$)' <<<"$output"; then
    result="fail"; reason="vacuous_pass"
  fi

  # Truncate output to 2000 chars for JSON safety
  local output_truncated="${output:0:2000}"
  # Escape for JSON
  output_truncated="${output_truncated//\\/\\\\}"
  output_truncated="${output_truncated//\"/\\\"}"
  output_truncated="${output_truncated//$'\n'/\\n}"
  output_truncated="${output_truncated//$'\t'/\\t}"

  # The version-2 row (P097 Step 2): status/reason/waived derived here by the
  # one mapping every row goes through; `result` rides along as the derived
  # compatibility field.
  local json
  json="$(gate_row_normalize "{\"gate\":\"${gate_name}\",\"result\":\"${result}\"${reason:+,\"reason\":\"${reason}\"},\"exit_code\":${exit_code},\"duration_ms\":${duration_ms},\"started_at\":\"${started_at}\",\"completed_at\":\"${completed_at}\",\"output\":\"${output_truncated}\"}")"
  echo "$json"

  # Log to file if provided
  [[ "$log_file" != "/dev/null" ]] && echo "$json" >> "$log_file"

  [[ "$result" == pass ]] && return 0 || return 1
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

# _gate_scripts_missing_in_tree <resolved_cmd> <tree>  (P087 Step 6)
#
# Every repo-relative script a gate command RUNS must exist in the tree the
# gate runs in — the candidate branch. A script is "run" when it is the first
# word of a command segment (after ;, &&, ||, |) or the argument of an
# interpreter (bash, sh, node, python, bats…); `echo scripts/x.sh` names a
# file and runs nothing, so it is not judged. Prints the missing ones, one per
# line; prints nothing when all are there. Absolute paths and
# {plugin_path}-resolved ones are the installed plugin's business, not the
# branch's, and are not judged. There is deliberately NO fallback to the state
# root's copy: a gate that ran the primary checkout's script would certify a
# branch that does not carry it, which is the drift IMP-497 was about.
_gate_scripts_missing_in_tree() {
  local cmd="$1" tree="$2" w prev="" runs=1
  for w in $cmd; do
    w="${w#\'}"; w="${w%\'}"; w="${w#\"}"; w="${w%\"}"; w="${w#./}"
    case "$w" in
      ';'|'&&'|'||'|'|'|'('|'{') runs=1; prev=""; continue ;;
    esac
    if (( runs )) || [[ "$prev" =~ ^(bash|sh|zsh|node|python|python3|bats|source|\.)$ ]]; then
      if [[ "$w" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sh|bash|bats|py|mjs|js|ts)$ && "$w" != /* && ! -e "${tree}/${w}" ]]; then
        printf '%s\n' "$w"
      fi
    fi
    # An interpreter's own flag (`bash -e script.sh`) keeps the interpreter
    # as the previous word, so the script after it is still judged.
    if [[ "$w" == -* ]] && [[ "$prev" =~ ^(bash|sh|zsh|node|python|python3|bats|source)$ ]]; then runs=0; continue; fi
    runs=0; prev="$w"
  done
}

# resolve_run_mode <execution_yaml> <gate_name>
#   Step 1's field, read here for the first time. Absent/null → "foreground",
#   which is what makes every pre-P076 consumer config behave identically.
resolve_run_mode() {
  local file="$1" gate="$2"
  yq ".gates.\"${gate}\".run_mode // \"foreground\"" "$file"
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

# validate_all_timeouts <execution_yaml>
#   `timeout_seconds` is the gate's deadline and nothing else (P097 Step 5):
#   absent → the template default 60; anything but a positive integer is a
#   configuration refusal that names the gate, before any gate runs.
validate_all_timeouts() {
  local file="$1" gate t
  while IFS= read -r gate; do
    [[ -z "$gate" ]] && continue
    t="$(GATE="$gate" yq '.gates[strenv(GATE)].timeout_seconds // 60' "$file")"
    if [[ ! "$t" =~ ^[0-9]+$ ]] || (( t <= 0 )); then
      echo "ERROR: aid-run-gates.sh: gate '${gate}' has invalid timeout_seconds: '${t}' (a positive integer number of seconds; omit the key for the default 60)" >&2
      return 2
    fi
  done < <(yq '.gates | keys | .[]' "$file")
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# P097 Step 6 — keys the runner no longer reads are REFUSED, never ignored.
#
# `required_when`, `needs_services`, `services:` and `gate_profile_defaults`
# left this runner with the service lifecycle and the applicability library.
# A key that is merely ignored is how `required_when` rotted unread for four
# months, so an execution.yaml that still carries one stops the run before any
# gate starts and names the upgrade that removes it (Step 3). The KEY is the
# signal, not its content: `services: {}` is refused like a populated block.
# ═══════════════════════════════════════════════════════════════════════════

# _refuse_dead_keys <execution_yaml> — exit 2 with key, gate and the upgrade
# command on stderr when a removed key is present; silent otherwise.
_refuse_dead_keys() {
  local file="$1" found
  found="$(yq -o=json '.' "$file" 2>/dev/null | jq -r '. as $r
    | (["services","gate_profile_defaults"][] | select(. as $k | $r | has($k)) | . + " (top level)"),
      ($r.gates // {} | to_entries[] | .key as $g | .value | select(type == "object") | keys[]
        | select(. == "required_when" or . == "needs_services") | . + " (gate " + $g + ")")' 2>/dev/null)" || found=""
  [[ -n "$found" ]] || return 0
  echo "ERROR: aid-run-gates.sh: ${file} carries configuration this runner no longer reads: ${found//$'\n'/; }. Refusing to run any gate on a key nothing enforces — $(gate_profile_upgrade_hint)" >&2
  exit 2
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
      job_state:"none"}' | gate_row_normalize
}

# _gate_row_finalize <gate_name> <row_json>
#   Every row on its way into the report or a checkpoint file passes here:
#   version-2 shape (gate_row_normalize) and a reason inside the closed
#   vocabulary (gate_row_check). Prints the row; exit 1 (naming the gate) when
#   the runner produced a row outside its own contract — that is the defect,
#   not something to write down and carry on from.
_gate_row_finalize() {
  local gate_name="$1" row
  row="$(gate_row_normalize "$2")" || return 1
  gate_row_check "$gate_name" "$row" || return 1
  printf '%s' "$row"
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
#     • a job dir exists but the fingerprint, the start HEAD or the recorded
#       deadline (job.json deadline_sec vs timeout_seconds) moved
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
    elif [[ "$(jq -r '.deadline_sec // ""' "$job_dir/job.json" 2>/dev/null)" != "$timeout_s" ]]; then
      # The job ran under another timeout_seconds. Re-collecting it would hand
      # back the old deadline's verdict (typically job_timeout) after the
      # operator raised the timeout to fix exactly that — so it is superseded
      # and the gate runs under the configured deadline, live or terminal.
      drift_reason="deadline_changed"
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
      local sup_ts sup_dir sup_log cancel_rc=0
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
        bash "$job_sh" cancel --jobs-dir "$jobs_dir" --id "$job_id" 2>&1 || cancel_rc=$?
        echo "cancel exit: ${cancel_rc}"
      } >"$sup_log" 2>&1 || true
      # A cancel that could not end the old process group (it survived TERM and
      # KILL, aid-job.sh exits non-zero) leaves the old command running against
      # this tree. Archiving the job and starting a fresh one under the same id
      # would run two copies at once — the gate fails here instead (P097 CP3).
      if (( cancel_rc != 0 )); then
        echo "ERROR: aid-run-gates.sh: gate '${gate_name}' — the superseded job '${job_id}' could not be stopped (see ${sup_log}); refusing to start a second copy" >&2
        _bg_fail_row "$gate_name" "job_lost" "superseded job ${job_id} could not be stopped; see ${sup_log}" "$job_id"
        return 1
      fi
      mv "$job_dir" "$sup_dir" >>"$sup_log" 2>&1 || true
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
      # P076 Step 13 — GATE_TIMEOUT, mechanical ladder entry. Recorded here and
      # nothing else: the cancel below, the state re-read and the row mapping
      # are untouched.
      _gate_ladder_emit GATE_TIMEOUT gate_job_deadline_exceeded \
        "gate ${gate_name} job ${job_id} ran ${job_elapsed}s past a ${timeout_s}s deadline plus ${AID_GATE_DEADLINE_GRACE_SEC}s grace; the runner is cancelling it"
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

  # P076 Step 13 — JOB_LOST, mechanical ladder entry. The MAPPING is what is
  # observed (`reason:"job_lost"` — no terminal record exists, so nothing about
  # the outcome is proven), read back off the row rather than re-derived, so the
  # ladder can never disagree with the row it is recording. The row itself, its
  # fail result and `row_rc` are untouched.
  if [[ "$(jq -r '.reason // ""' <<<"$row" 2>/dev/null || true)" == "job_lost" ]]; then
    _gate_ladder_emit JOB_LOST gate_job_lost \
      "gate ${gate_name} job ${job_id} is '${state}' with no terminal record — the absence of a result is not a pass"
  fi

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

# _gate_bats_units <resolved_command>
#   The .bats files a gate command actually dispatches, one per line, relative
#   to the project root. Three shapes, because the ledger has to see all of
#   them or its double-execution accounting silently under-reports:
#     * literal paths          — `bats a.bats b.bats`
#     * a directory glob       — `bats path/*.bats` (expanded here, because the
#                                shell expands it at dispatch time and the
#                                command string never contains the file names)
#     * a glob minus a filter  — `ls path/*.bats | grep -v -e X -e Y`, which is
#                                how gate:bats_all excludes the boundary files
#                                that gate:bats_boundary owns
#   Getting the third one wrong is not cosmetic: counting the excluded files
#   here would report every boundary file as double-dispatched, and skipping
#   glob expansion entirely (the state P078 left behind for one commit) drops
#   159 files out of the accounting and certifies the portfolio clean.
#   aid-test-inventory.sh derives the same partition for reconciliation.contains[];
#   the two must agree.
_gate_bats_units() {
  local cmd="$1" tok f
  local -a excludes=()
  # `grep -v -e A -e B` / `grep -v A` inside the command declares exclusions.
  if [[ "$cmd" == *"grep -v"* ]]; then
    while read -r tok; do
      [[ -n "$tok" ]] && excludes+=("$tok")
    done < <(grep -oE '\-v( +\-e +[A-Za-z0-9_./-]+)+|\-v +[A-Za-z0-9_./-]+' <<<"$cmd" \
               | grep -oE '[A-Za-z0-9_./-]+' | grep -vx -e v -e e || true)
  fi
  {
    # literal paths
    grep -oE '[A-Za-z0-9_./-]+\.bats' <<<"$cmd" 2>/dev/null || true
    # globs — expanded against the CURRENT directory, which run_all_gates has
    # already set to the project root for command execution
    while read -r tok; do
      [[ -n "$tok" ]] || continue
      compgen -G "$tok" 2>/dev/null || true
    done < <(grep -oE '[A-Za-z0-9_./-]*\*[A-Za-z0-9_./-]*\.bats' <<<"$cmd" 2>/dev/null || true)
  } | sort -u | while read -r f; do
    [[ -n "$f" ]] || continue
    local skip=0 ex
    for ex in "${excludes[@]:-}"; do
      [[ -n "$ex" && "$f" == *"$ex"* ]] && skip=1
    done
    (( skip )) || printf '%s\n' "$f"
  done
}

run_all_gates() {
  local execution_yaml="$1"
  local epic_id="$2"
  local run_id="$3"
  shift 3

  # THE run's evidence directory, resolved ONCE (P079 Step 2). Every state
  # artifact below — timeline, default report path, execution ledger, waivers,
  # job records, row checkpoints — hangs off this one
  # value, and the recovery ladder reads it by name from this scope.
  local _evidence_dir; _evidence_dir="$(_gates_evidence_dir "$epic_id" "$run_id")"

  # Determine timeline_file: use positional $4 ONLY if it's not a flag.
  # Bug fix (PM-reported): the previous `${4:-default}` + unconditional
  # `shift` swallowed `--state-file` when caller skipped the positional
  # arg, causing log_event to write to a literal file named "--state-file".
  local timeline_file
  if [[ -n "${1:-}" && "${1}" != --* ]]; then
    timeline_file="$1"
    shift
  else
    timeline_file="${_evidence_dir}/timeline.jsonl"
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
  validate_all_timeouts "$execution_yaml" || exit 2

  # ─── removed keys (P097 Step 6) ────────────────────────────────────────
  # Same entry point: a `services:` block, `gate_profile_defaults`, or a gate
  # with `required_when`/`needs_services` is refused with the upgrade command
  # before any gate runs. Ignoring the key is what let it rot unread.
  _refuse_dead_keys "$execution_yaml"

  # ─── Gate profile validation (P097 Step 4) ───────────────────────────
  # The caller names the profile; nothing here chooses one. A name that is
  # not declared, or a profile that could only skip, is refused with exit 2
  # before any gate runs. include[] entries are then checked against gates:
  # (an undefined gate or a gate without a command is exit 1, as before).
  local profile_source="none"
  local include_gates_json="[]"
  local profile_table_json
  profile_table_json="$(gate_profile_table "$execution_yaml" | jq -R . | jq -sc .)"
  if [[ -n "$profile" ]]; then
    if ! gate_profile_exists "$execution_yaml" "$profile"; then
      echo "ERROR: aid-run-gates.sh: unknown gate profile '${profile}' — declared profiles in ${execution_yaml}: ${profile_table_json}; $(gate_profile_upgrade_hint)" >&2
      exit 2
    fi
    include_gates_json=$(PROFILE="$profile" yq -o=json '.gate_profiles[strenv(PROFILE)].include // []' "$execution_yaml" | tr -d '\n ')
    local profile_defined_keys_json
    profile_defined_keys_json=$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')
    local inc_gate inc_cmd
    while IFS= read -r inc_gate; do
      [[ -z "$inc_gate" ]] && continue
      if ! jq -e --arg g "$inc_gate" 'any(.[]; . == $g)' <<< "$profile_defined_keys_json" >/dev/null 2>&1; then
        echo "ERROR: aid-run-gates.sh: gate profile '${profile}' includes undefined gate '${inc_gate}' (not present under execution.yaml.gates)" >&2
        exit 1
      fi
      # P083 Step 5 (case 3): a gate defined but with no `command` is a
      # configuration refusal, not the silent skip/no_command row it used to
      # fall through to below. A gate absent from every profile is
      # unaffected: this only runs when a profile is active, and only over
      # ITS include[].
      inc_cmd=$(GATE="$inc_gate" yq '.gates[strenv(GATE)].command' "$execution_yaml")
      if [[ -z "$inc_cmd" || "$inc_cmd" == "null" ]]; then
        echo "ERROR: aid-run-gates.sh: gate profile '${profile}' includes gate '${inc_gate}', which has no command in ${execution_yaml} — a profile-included gate with no command is a configuration error, not a silent skip." >&2
        exit 1
      fi
    done < <(jq -r '.[]' <<< "$include_gates_json")
    # After the per-gate checks, so a command-less gate is still named as
    # such: a profile whose include[] carries no required gate is refused —
    # a run that can only skip is not a run. The one exception is the
    # plan-final reuse copy (aid-plan-fsm.sh sets AID_GATES_REUSE_OF to the
    # attempt the required rows were copied from): there the required gates
    # already passed and the narrowed include[] is what is left to execute.
    if [[ -z "${AID_GATES_REUSE_OF:-}" ]] && ! gate_profile_has_required_gate "$execution_yaml" "$profile"; then
      echo "ERROR: aid-run-gates.sh: gate profile '${profile}' includes no required gate (include: $(PROFILE="$profile" yq -o=json -I=0 '.gate_profiles[strenv(PROFILE)].include // []' "$execution_yaml")) — a run that can only skip is not a run; declared profiles: ${profile_table_json}; $(gate_profile_upgrade_hint)" >&2
      exit 2
    fi
    profile_source="caller"
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
  [[ -z "$report_path" ]] && report_path="${_evidence_dir}/gates/gates_report.json"

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
  # P079 Step 2: the CONFIG root is not the tree under test. `_plugin_project_root`
  # stays the invoking tree — gate-row revisions and background jobs are claims
  # about THAT tree — but `.aid-o` never moves into a worktree, so plugin.yaml
  # must be read from the state root or a worktree run silently fell through to
  # AID_PLUGIN_PATH.
  local _config_root
  _config_root="$(aid_state_root 2>/dev/null || printf '%s' "$_plugin_project_root")"
  if [[ -f "${_config_root}/.aid-o/config/plugin.yaml" ]]; then
    plugin_path_resolved="$(yq -r '.plugin_path // ""' "${_config_root}/.aid-o/config/plugin.yaml" 2>/dev/null || echo "")"
  fi
  [[ -z "$plugin_path_resolved" ]] && plugin_path_resolved="${AID_PLUGIN_PATH:-}"

  # ─── gate_runner_start (P032 Step 3) ──────────────────────────────
  local gate_count gate_names_json
  gate_count=$(yq '.gates | length' "$execution_yaml")
  gate_names_json=$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')

  # ─── `required` resolved up front, for every gate ───────────────────
  # Explicit `required: true|false` (an unquoted boolean) or absent → false
  # with source `legacy_default`. Resolved before the loop so a malformed
  # value late in the file refuses the run before an earlier gate has run and
  # left its side effects. (`required_when` no longer exists — P097 Step 6;
  # `_refuse_dead_keys` above already stopped a file that still carries it.)
  local _rw_gate _rw_tag
  declare -A _AID_REQ_RESOLVED=() _AID_REQ_SOURCE=()
  while IFS= read -r _rw_gate; do
    [[ -n "$_rw_gate" ]] || continue
    _rw_tag="$(GATE="$_rw_gate" yq -r '.gates[strenv(GATE)].required | tag' "$execution_yaml" 2>/dev/null || echo '!!null')"
    case "$_rw_tag" in
      '!!null') _AID_REQ_RESOLVED["$_rw_gate"]=false; _AID_REQ_SOURCE["$_rw_gate"]=legacy_default ;;
      '!!bool')
        _AID_REQ_RESOLVED["$_rw_gate"]="$(GATE="$_rw_gate" yq -r '.gates[strenv(GATE)].required' "$execution_yaml")"
        _AID_REQ_SOURCE["$_rw_gate"]=explicit ;;
      *)
        echo "ERROR: aid-run-gates.sh: gate '${_rw_gate}': required must be an unquoted true or false (found ${_rw_tag#\!\!}). Refusing to run any gate on a requirement this runner cannot read — guessing it is what left failing gates green." >&2
        return 1 ;;
    esac
  done < <(yq '.gates | keys | .[]' "$execution_yaml")
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

  # P069 Step 14 — targeted_tests escalation (exit 3 unknown_production /
  # exit 11 mapping_gap). Set inline when that gate's FINAL result settles
  # (the gate invokes aid-select-tests.sh and can produce either
  # exit code). Consumed AFTER the whole targeted-profile pass finishes and
  # its own report has been fully assembled — never mid-loop, and never
  # mutating this pass's own `gates_json`/`processed`/`gate_count` bookkeeping.
  local escalation_triggered=false
  local escalation_reason=""

  # ─── Background job + row-checkpoint locations (P076 Step 2) ─────────────
  # Both live under `$_evidence_dir` (resolved once at the top of this
  # function) and are set only when that directory already exists — the gate
  # runner writes into evidence, it never invents evidence directories (the
  # same rule the execution ledger follows).
  local _jobs_dir="" _rows_dir=""
  if [[ -d "$_evidence_dir" ]]; then
    # The report, the rows and the logs all live here: a directory that cannot
    # be written refuses the run BEFORE any gate, so no partial row exists.
    if [[ ! -w "$_evidence_dir" ]]; then
      echo "ERROR: aid-run-gates.sh: evidence directory '${_evidence_dir}' is not writable — refusing to run gates whose rows could not be recorded" >&2
      return 2
    fi
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
    if [[ -d "$_evidence_dir" ]]; then
      _ledger_path="${_evidence_dir}/execution-ledger.json"
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
      _ledger_unaccounted_reason="no evidence directory at '${_evidence_dir}' — this gate run is NOT accounted by an execution ledger and cannot support a no-double-execution claim"
    fi
  fi

  # Iterate gate names via yq (mikefarah)
  local gate_names
  gate_names=$(yq '.gates | keys | .[]' "$execution_yaml")

  while IFS= read -r gate_name; do
    [[ -z "$gate_name" ]] && continue

    # Every row carries the resolved requirement and where it came from —
    # including the branches that never run a command. Without it the final
    # "derive the verdict from the rows" pass is blind on exactly those
    # branches, and a reader cannot tell a gate that was excused from one that
    # was never required. (Codex review, 2026-09-02.)
    _req_fields() {
      printf '"required":%s,"required_source":"%s"' \
        "$([[ "${_AID_REQ_RESOLVED[$1]:-false}" == "true" ]] && echo true || echo false)" \
        "${_AID_REQ_SOURCE[$1]:-legacy_default}"
    }

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
    # skip row above): emit an explicit `skip / not_in_profile` row, count it
    # toward `processed`, and record it in excluded_gates. A required:true
    # gate excluded this way does NOT fail the run — same treatment as a
    # skipped required:false gate below.
    if [[ -n "$profile" ]] && ! jq -e --arg g "$gate_name" 'any(.[]; . == $g)' <<< "$include_gates_json" >/dev/null 2>&1; then
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="skip" reason="not_in_profile" profile="$profile"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"skip\",\"reason\":\"not_in_profile\",\"exit_code\":null,\"duration_ms\":0,\"output\":\"\",\"attempts\":0,$(_req_fields "$gate_name")}"
      processed=$((processed+1))
      excluded_gates+=("$gate_name")
      continue
    fi

    local cmd required max_retries timeout_s pass_criteria run_mode
    cmd=$(yq ".gates.\"${gate_name}\".command" "$execution_yaml")
    # Resolved up front (see the block above): explicit `required:` or the
    # pre-2026-09 default of false.
    required="${_AID_REQ_RESOLVED[$gate_name]:-false}"
    local required_source="${_AID_REQ_SOURCE[$gate_name]:-legacy_default}"
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
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"skip\",\"reason\":\"no_command\",\"exit_code\":0,\"duration_ms\":0,\"output\":\"\",\"attempts\":0,$(_req_fields "$gate_name")}"
      processed=$((processed+1))
      continue
    fi

    # Phase 2 (P037) — resolve {token} placeholders before bash -c execution.
    # Unknown tokens fail-loud — mark gate as fail and continue to next gate.
    local resolved_cmd
    if ! resolved_cmd=$(resolve_placeholders "$cmd" "$epic_id" "$run_id" "$base_commit_resolved" "$plan_path_resolved" "$plugin_path_resolved"); then
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="fail" reason="unknown_placeholder"
      overall="fail"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":{\"gate\":\"${gate_name}\",\"result\":\"fail\",\"reason\":\"unknown_placeholder\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"unknown_placeholder\",\"attempts\":0,$(_req_fields "$gate_name")}"
      processed=$((processed+1))
      continue
    fi

    # P087 Step 6 — the branch under test carries every script its gates name.
    local _missing_scripts
    _missing_scripts="$(_gate_scripts_missing_in_tree "$resolved_cmd" "$_plugin_project_root")"
    if [[ -n "$_missing_scripts" ]]; then
      local _ms_list="${_missing_scripts//$'\n'/ }"
      echo "ERROR: aid-run-gates.sh: gate '${gate_name}' names ${_ms_list}— not in the tree ${_plugin_project_root}. The branch under test must carry every script its gates name; there is no fallback to the primary checkout." >&2
      # The timeline keeps the event's original reason name (test-gate-config-
      # branch.bats greps it); the ROW carries the vocabulary name.
      log_event "$timeline_file" "gate_complete" gate="$gate_name" result="fail" reason="gate_script_missing_in_tree" scripts="$_ms_list"
      $first || gates_json+=","
      first=false
      gates_json+="\"${gate_name}\":$(jq -nc --arg g "$gate_name" --arg s "$_ms_list" --arg t "$_plugin_project_root" \
        --argjson rq "$([[ "${_AID_REQ_RESOLVED[$gate_name]:-false}" == "true" ]] && echo true || echo false)" \
        --arg rs "${_AID_REQ_SOURCE[$gate_name]:-legacy_default}" \
        '{gate:$g, result:"fail", reason:"missing_script", exit_code:1, duration_ms:0,
          output:("gate script(s) not in the tree " + $t + ": " + $s), attempts:0,
          required:$rq, required_source:$rs}')"
      processed=$((processed+1))
      if [[ "${required:-false}" == "true" ]]; then overall="fail"; fi
      continue
    fi

    log_event "$timeline_file" "gate_start" gate="$gate_name" epic_id="$epic_id"

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
          return 3
        fi
      done < <(_gate_bats_units "$resolved_cmd")
    fi

    local gate_result="" attempt=0 gate_exit=0
    for (( attempt=1; attempt<=max_retries+1; attempt++ )); do
      gate_exit=0
      if [[ "$run_mode" == "background" ]]; then
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
      r=$(echo "$gate_result" | jq -r '.status')
      # Phase 2 (P037) — exit code 2 is a graceful skip when gate's pass_criteria
      # mentions "exit 2" (legacy plan / no AC blocks / Fast Mode).
      # Evidence truthfulness fix: result="skip" (not "pass") so gates_report.json
      # accurately reflects that the gate did not verify anything, only skipped.
      # The outer overall="pass" logic treats "skip" same as "pass" for required=false gates.
      local gate_ec
      gate_ec=$(echo "$gate_result" | jq -r '.exit_code')
      if [[ "$r" != "pass" && "$gate_ec" == "2" && "$pass_criteria" == *"exit 2"* ]]; then
        gate_result=$(echo "$gate_result" | jq '.status = "skip" | .result = "skip" | .reason = "exit_2"')
        r="skip"
      fi

      [[ "$r" == "pass" || "$r" == "skip" ]] && break

      [[ $attempt -le $max_retries ]] && echo "Gate ${gate_name} failed (attempt ${attempt}/${max_retries}), retrying..." >&2
    done
    # A gate that spent every attempt leaves the loop by its condition, one
    # past the last attempt made; `attempts` on the row counts attempts, not
    # loop exits. (P097 Step 5: the policy block's early `break` used to hide
    # this for timeouts.)
    (( attempt > max_retries + 1 )) && attempt=$(( max_retries + 1 ))

    # `final_result` is the row's status, or "waived" once a waiver applied:
    # the one word the timeline event and the overall verdict below key on.
    local final_result
    final_result=$(echo "$gate_result" | jq -r '.status')

    # ─── Gate-scoped PM waiver (IMP-270) ───────────────────────────────────
    # A failed gate becomes `waived: true` (its status stays `fail`, NEVER
    # `pass`) iff a gate-scoped waiver exists for it AND aid-gate-waiver.sh
    # check returns `valid` for the exact (project, epic, run, HEAD, gate,
    # command fingerprint) tuple. A waiver file alone changes nothing — the
    # check must pass. On valid: consume the single-use waiver, stamp
    # waived=true (+ the derived result "waived") + waiver_ref, and record the
    # gate in waived_gates[]. overall then treats it like a pass (the
    # required-fail branch below is skipped because final_result is no longer
    # "fail"), but the top-level waived_gates[] array keeps it visible in
    # PM/release evidence. A waiver present but failing check for ANY reason
    # leaves the row `fail` and records waiver_rejected:<verdict> on it.
    if [[ "$final_result" == "fail" ]]; then
      local _wv_file="${_evidence_dir}/waivers/gate-waiver-${gate_name}.json"
      if [[ -f "$_wv_file" ]]; then
        local _wv_head _wv_cmd_sha _wv_verdict _wv_rc
        _wv_head=$(git rev-parse HEAD 2>/dev/null || echo "")
        _wv_cmd_sha=$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)
        _wv_rc=0
        _wv_verdict=$("${SCRIPT_DIR}/aid-gate-waiver.sh" check "$gate_name" \
          --evidence-dir "$_evidence_dir" --head "$_wv_head" \
          --command-sha "$_wv_cmd_sha" --epic "$epic_id" --run "$run_id" 2>/dev/null) || _wv_rc=$?
        if [[ "$_wv_rc" -eq 0 && "$_wv_verdict" == "valid" ]]; then
          # IMP-270 review F1: consumption must be DURABLE before we waive. If
          # consume fails (read-only dir, ENOSPC, lock lost) the single-use
          # waiver is not spent and would be replayable, so fail closed —
          # leave the gate `fail` with waiver_rejected:consume_failed rather
          # than stamping a waived result on an unconsumed waiver.
          local _wv_consume_rc=0
          "${SCRIPT_DIR}/aid-gate-waiver.sh" consume "$gate_name" \
            --evidence-dir "$_evidence_dir" --by-run "$run_id" >/dev/null 2>&1 || _wv_consume_rc=$?
          if [[ "$_wv_consume_rc" -ne 0 ]]; then
            gate_result=$(echo "$gate_result" | jq '.waiver_rejected = "consume_failed"')
          else
            gate_result=$(echo "$gate_result" | jq \
              --arg ref "waivers/gate-waiver-${gate_name}.json" \
              '.waived = true | .result = "waived" | .waiver_ref = $ref')
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

    # Add to gates JSON aggregate.
    $first || gates_json+=","
    first=false
    local merged_row
    # `required` travels WITH the row. Without it the report cannot say why a
    # run passed or failed, and the end-of-run verdict has nothing to re-derive
    # from — which is how "overall: pass" survived a failed required gate.
    # `required_source` rides along so a reader can tell WHY a gate was (or
    # was not) required — `explicit` or `legacy_default`.
    merged_row=$(echo "$gate_result" | jq \
      --argjson req "$([[ "${required:-false}" == "true" ]] && echo true || echo false)" \
      --arg reqsrc "${required_source:-legacy_default}" \
      ". + {\"attempts\":${attempt}, \"required\": \$req, \"required_source\": \$reqsrc}")
    # The checkpoint file is a row too, so the contract is applied BEFORE it
    # is written; a row outside the vocabulary ends the run here, by name.
    merged_row="$(_gate_row_finalize "$gate_name" "$merged_row")" || return 1
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

      # The SAME resolution every executed gate got. Reading `.required // false`
      # here would have left a restored failing row non-blocking for exactly
      # the gates this change exists to make blocking — a false green on the
      # path that does not run the command and therefore gets the least
      # scrutiny.
      _required_rg="${_AID_REQ_RESOLVED[$_rg]:-false}"
      local _reqsrc_rg="${_AID_REQ_SOURCE[$_rg]:-legacy_default}"
      $first || gates_json+=","
      first=false
      if [[ -n "$_stale_reason" ]]; then
        gates_json+="\"${_rg}\":$(jq -nc --arg g "$_rg" --arg sr "$_stale_reason" \
          --arg rec "$_rec_head" --arg cur "$_rows_head" --arg src "$_rf" \
          --arg rq "$_required_rg" --arg rs "$_reqsrc_rg" \
          '{gate:$g, result:"fail", exit_code:1, duration_ms:0, attempts:0,
            output:("checkpointed gate row at " + $src + " is not valid for the current revision (" + $sr + "); the gate did not run in this invocation"),
            reason:"gate_row_stale", stale_reason:$sr,
            recorded_head:(if $rec == "" then null else $rec end),
            current_head:(if $cur == "" then null else $cur end),
            required:($rq == "true"), required_source:$rs}')"
        processed=$((processed+1))
        log_event "$timeline_file" "gate_row_stale" gate="$_rg" source="$_rf" \
          reason="$_stale_reason" recorded_head="$_rec_head" current_head="$_rows_head"
        if [[ "$_required_rg" == "true" ]]; then overall="fail"; fi
      else
        gates_json+="\"${_rg}\":$(jq -c --arg rq "$_required_rg" --arg rs "$_reqsrc_rg" \
          '. + {required:($rq == "true"), required_source:$rs}' <<<"$_rrow")"
        processed=$((processed+1))
        log_event "$timeline_file" "gate_row_restored" gate="$_rg" source="$_rf" \
          head="$_rec_head"
        if [[ "$(gate_row_normalize "$_rrow" | jq -r 'select(.waived | not) | .status')" == "fail" ]] \
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
      # `required` is stated as true and `required_source` as `undefined_gate`
      # rather than left absent. The gate has no definition, so there is no
      # requirement to resolve — but a row without the two fields makes "every
      # row says whether it counted" untrue, and this one counts: it forces
      # overall=fail on the next line.
      gates_json+="\"${declared_gate}\":{\"gate\":\"${declared_gate}\",\"result\":\"fail\",\"reason\":\"undefined_gate\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"gate declared in plan.json but not defined in execution.yaml\",\"attempts\":0,\"required\":true,\"required_source\":\"undefined_gate\"}"
    done < <(jq -r '.gates // [] | .[]' "$plan_json" 2>/dev/null)
  fi

  gates_json+="}"

  # ─── every row is a version-2 row, checked against the vocabulary ────────
  # The branches above that never run a command (not_in_profile, no_command,
  # service_unhealthy, unknown_placeholder, missing_script, gate_row_stale,
  # undefined_gate) and the restored checkpoint rows are stamped here, in one
  # pass, so no emission site can leave a version-1 row behind. `_integrity`
  # and `_execution_ledger` are run-level records, not rows, and are skipped.
  gates_json="$(jq -c "${AID_GATE_ROW_JQ} gate_rows_normalize" <<<"$gates_json")" || {
    echo "ERROR: aid-run-gates.sh: the gate rows could not be normalized to the version-2 contract" >&2
    return 1
  }
  local _chk_gate _chk_row
  while IFS=$'\t' read -r _chk_gate _chk_row; do
    [[ -n "$_chk_gate" ]] || continue
    gate_row_check "$_chk_gate" "$_chk_row" || return 1
  done < <(jq -r 'to_entries[] | select((.key|startswith("_")|not) and (.value|type) == "object") | "\(.key)\t\(.value|tojson)"' <<<"$gates_json")

  # ─── the verdict is DERIVED from the rows, once, here ──────────────────
  # `overall` is set in seven places above, each inside its own branch, and a
  # path that reaches none of them used to leave the run reported as `pass`
  # however its gates ended (ACTA/WAN, 2026-08-27..09-01: "overall: pass
  # navzdory spadlým branám"). Those assignments stay as the fast path; this is
  # the authority. A row that FAILED and is REQUIRED makes the run fail, and
  # nothing downstream has to agree for that to hold.
  #
  # A waived row (`waived: true`) is deliberately not a failure here — a waiver
  # is a recorded PM decision, and the surrounding code already surfaces it as
  # risk acceptance rather than as a pass.
  local _derived_fail
  _derived_fail="$(jq -r '[to_entries[]
      | select((.value.status? // "") == "fail" and (.value.waived? // false) == false)
      | select((.value.required? // false) == true)] | length' <<<"$gates_json" 2>/dev/null)" || _derived_fail=""
  if [[ "$_derived_fail" =~ ^[0-9]+$ ]] && (( _derived_fail > 0 )) && [[ "$overall" != "fail" ]]; then
    log_event "$timeline_file" "gate_overall_corrected" was="$overall" required_failures="$_derived_fail"
    echo "aid-run-gates: overall was '${overall}' with ${_derived_fail} required gate(s) failed — corrected to fail" >&2
    overall="fail"
  fi
  if [[ ! "$_derived_fail" =~ ^[0-9]+$ ]]; then
    # The rows could not be counted. That is not evidence of a pass: say so and
    # leave whatever the branches decided, rather than silently blessing it.
    # AN UNCONFIRMABLE PASS IS NOT A PASS. Printing "unconfirmed" to stderr left
    # `pass` in the report, and every consumer downstream reads the report, not
    # the warning (Codex, 2026-09-02). A verdict that cannot be checked against
    # its own rows becomes a failure, which is the direction that cannot hide a
    # broken run.
    echo "aid-run-gates: could not re-derive the verdict from the gate rows — refusing to report '${overall}' unchecked" >&2
    if [[ "$overall" == "pass" ]]; then
      log_event "$timeline_file" "gate_overall_unverifiable" was="$overall"
      overall="fail"
    fi
  fi

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

  # ─── gate profile fields (P097 Step 4) ─────────────────────────────────
  # `profile` is null without --profile; `profile_source` is caller|none;
  # `profile_table` is the declared order the floor compares indexes in
  # ([] when the file declares no gate_profiles). excluded_gates is always
  # an array, empty when no gate was excluded.
  local profile_val_json="null"
  [[ -n "$profile" ]] && profile_val_json=$(jq -nc --arg v "$profile" '$v')
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
              --arg profsrc "$profile_source" \
              --argjson proftable "$profile_table_json" \
              --argjson excl "$excluded_gates_json" \
              --argjson waived "$waived_gates_json" \
              '. + {_generated_by: $gen, _generated_at: $ts, _command_log: $cl, covered_paths: $cp, changed_paths_covered: $ccov, relevance: $rel, plan_gates_reconciled: $pgr, revision: $rev, profile: $prof, profile_source: $profsrc, profile_table: $proftable, excluded_gates: $excl, waived_gates: $waived}' \
              <<< "$report")

  # ─── P069 Step 14 — targeted_tests escalation: full-profile substitute ──
  # Triggered ONLY by targeted_tests's own exit 3/11 (set inline
  # above). A SECOND, entirely separate
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
    AID_EXECUTION_KIND=escalation \
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

  # Existing per-run completion event (kept for backward compat)
  log_event "$timeline_file" "gates_complete" overall="$overall" epic_id="$epic_id"

  # ─── gate_runner_complete (P032 Step 3) ────────────────────────────
  local total_duration=$((SECONDS - run_start))
  log_event "$timeline_file" "gate_runner_complete" \
    report_path="$report_path" overall="$overall" duration_sec="$total_duration"

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
