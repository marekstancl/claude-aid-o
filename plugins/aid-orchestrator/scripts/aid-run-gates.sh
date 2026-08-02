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

  # P069 Step 14 — targeted_tests escalation (exit 3 unknown_production /
  # exit 11 mapping_gap). Set inline when that gate's FINAL result settles
  # (regardless of whether it ran sequentially or through the scheduler —
  # both paths ultimately invoke aid-select-tests.sh and can produce either
  # exit code). Consumed AFTER the whole targeted-profile pass finishes and
  # its own report has been fully assembled — never mid-loop, and never
  # mutating this pass's own `gates_json`/`processed`/`gate_count` bookkeeping.
  local escalation_triggered=false
  local escalation_reason=""

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

    local cmd required max_retries timeout_s pass_criteria
    cmd=$(yq ".gates.\"${gate_name}\".command" "$execution_yaml")
    required=$(yq ".gates.\"${gate_name}\".required // false" "$execution_yaml")
    max_retries=$(yq ".gates.\"${gate_name}\".max_retries // 1" "$execution_yaml")
    timeout_s=$(yq ".gates.\"${gate_name}\".timeout_seconds // 60" "$execution_yaml")
    pass_criteria=$(yq ".gates.\"${gate_name}\".pass_criteria // \"\"" "$execution_yaml")

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

    local gate_result="" attempt=0 gate_exit=0
    for (( attempt=1; attempt<=max_retries+1; attempt++ )); do
      gate_exit=0
      if $use_scheduled_dispatch; then
        gate_result=$(run_scheduled_targeted_tests "$gate_name" "$rollout_effective_mode" "$base_commit_resolved" "$plugin_path_resolved" "$epic_id" "$run_id" "$_plugin_project_root" "$timeout_s" "$attempt") || gate_exit=$?
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
    $first || gates_json+=","
    first=false
    gates_json+="\"${gate_name}\":$(echo "$gate_result" | jq --argjson rb "$runtime_baseline_json" ". + {\"attempts\":${attempt}, \"runtime_baseline\": \$rb}")"
    processed=$((processed+1))

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
