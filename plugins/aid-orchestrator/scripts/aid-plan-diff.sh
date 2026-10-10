#!/usr/bin/env bash
# aid-plan-diff.sh — P037 Phase 2 — Plan AC executable verification
#
# Parses plan.md ## Acceptance Criteria section, runs verification_pattern per AC,
# emits plan-diff.json with per-AC verdict (present|absent).
#
# Usage:
#   aid-plan-diff.sh --plan <path> --evidence-dir <path> --base-commit <sha>
#   aid-plan-diff.sh ... --step <N> --plan-json <plan.json>      (P110)
#     The run's step N (0-based, as cp2/step-N): the brief points of
#     plan.json steps[N].zavira that no LATER plan step names (a point named by
#     several steps is measured at the last one — read over the whole plan
#     file's **Zavírá:** fields; the earlier steps list it as deferred_to_step),
#     plus the step's own labelled criteria (`- [ ] [<role>] …` with a block)
#     under `### Step <plan_step>:`. Writes <evidence-dir>/cp2/step-N/plan-diff.json
#     (scope: step); merges cp2/step-N/deferred.json entries whose Decision card
#     the PM answered (aid_pm_card_check); neither points nor own criteria →
#     unmeasured_step: true, exit 2.
#   aid-plan-diff.sh ... --isolated [--cwd <worktree>]              (P110)
#     The close's measurer. --cwd runs every point inside that git worktree
#     (head_commit is its HEAD; file points resolve there; not a worktree →
#     exit 3 cwd_not_worktree). The project rule comes from the STATE root's
#     .aid-o/config/execution.yaml `verification_env:` (never the candidate's):
#       empty  — every cmd runs in a new network namespace with loopback up and
#                the caller's uid (`unshare -rn` + nested `unshare --map-user`),
#                with a clean environment; a host variable that holds a test
#                service address (*DATABASE_URL, *REDIS_URL, *_TEST_*URL|DSN) the project did
#                not declare → absent (reason=env_stripped: VAR); a cmd naming a
#                database URL → absent (reason=no_verification_env);
#       a map  — every cmd runs with those variables and the host network
#                (network: "host (verification_env)"); a value `${VAR}` names a
#                host variable, unset → absent (reason=verification_env_unset: VAR).
#     Without a usable nested unshare every cmd is absent (reason=no_isolation),
#     never present. plan-diff.json gains isolation {worktree, env_keys, network}.
#
# Exit codes:
#   0  — all ACs present (gate pass)
#   1  — ≥1 AC absent (gate fail)
#   2  — graceful skip: Fast Mode (--plan empty or "null") OR plan has no AC section / no verification_pattern blocks
#   3  — cwd_not_worktree: --cwd is not a git worktree (P110)
#   10 — input validation error (evidence_dir missing or plan path provided but file not found)
#
# Security note: pattern `cmd:` arguments are author-controlled (plan.md) and trusted
# at same level as plan content itself. eval() is used by design. Do not feed
# user-supplied or external content here — patterns must originate from versioned plan files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"   # aid_state_path — a relative evidence dir lives in the state root
# shellcheck source=lib/aid-verification-pattern.sh
source "${SCRIPT_DIR}/lib/aid-verification-pattern.sh"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"   # _aid_plan_step_bounds, _aid_plan_step_field (P110 --step)
# shellcheck source=lib/aid-decision-card.sh
source "${SCRIPT_DIR}/lib/aid-decision-card.sh"   # aid_pm_card_check — a deferral the PM answered (P110)

PLUGIN_VERSION="${PLUGIN_VERSION:-v2.67.0}"

usage() {
  cat <<EOF
Usage: aid-plan-diff.sh --plan <path> --evidence-dir <path> --base-commit <sha>

Options:
  --plan <path>           Path to plan.md (e.g., .aid-o/plans/P037-*.md)
  --evidence-dir <path>   Run evidence directory (output written here as plan-diff.json)
  --base-commit <sha>     Git base commit for diff context (recorded in output)
  --step <N>              The run's step index (0-based): measure that step only (P110)
  --plan-json <path>      The run's plan.json (required with --step)
  --isolated              Run every cmd point under the project's isolation rule (P110)
  --cwd <dir>             Run the points inside this git worktree (the candidate)
EOF
}

# Parse CLI
PLAN=""; EVIDENCE_DIR=""; BASE_COMMIT=""; STEP_N=""; PLAN_JSON=""; ISOLATED=0; RUN_CWD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --isolated) ISOLATED=1; shift ;;
    --cwd) RUN_CWD="$2"; shift 2 ;;
    --step) STEP_N="$2"; shift 2 ;;
    --plan-json) PLAN_JSON="$2"; shift 2 ;;
    --plan) PLAN="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --base-commit) BASE_COMMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 10 ;;
  esac
done

# A relative evidence dir (.aid-o/work/evidence/...) names the state root's, also when this
# runs inside a plan worktree, where .aid-o does not exist (P100 Step 7).
[[ -n "$EVIDENCE_DIR" && "$EVIDENCE_DIR" != /* ]] && EVIDENCE_DIR="$(aid_state_path "$EVIDENCE_DIR")"

# Fast Mode / manual EPIC handling: empty or literal "null" plan_path → graceful skip
if [[ -z "$PLAN" || "$PLAN" == "null" ]]; then
  [[ -z "$EVIDENCE_DIR" ]] && { usage; exit 10; }
  mkdir -p "$EVIDENCE_DIR" 2>/dev/null || true
  GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
    --arg ga "$GEN_AT" \
    --arg reason "fast-mode EPIC (plan_path is null in fsm-state.yaml; no plan to verify)" \
    '{
      "_generated_by": $gb,
      "_generated_at": $ga,
      "plan_path": null,
      "base_commit": null,
      "head_commit": null,
      "ac_count": 0,
      "results": [],
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1, "reason": $reason,
                  "unmeasured": {"summary_prose": 0, "summary_unparsed": 0, "step_bullets": 0}},
      "overall_verdict": "skipped"
    }' > "${EVIDENCE_DIR}/plan-diff.json"
  exit 2
fi

[[ -z "$EVIDENCE_DIR" ]] && { usage; exit 10; }
[[ ! -f "$PLAN" ]] && { echo "Plan not found: $PLAN" >&2; exit 10; }
[[ ! -d "$EVIDENCE_DIR" ]] && { echo "Evidence dir not found: $EVIDENCE_DIR" >&2; exit 10; }
# The project rule is the STATE root's (ACTA #33: never the candidate's copy),
# resolved before the run moves into --cwd.
STATE_ROOT="$(aid_state_root 2>/dev/null || pwd)"
if [[ -n "$RUN_CWD" ]]; then
  # the worktree's top, not a directory inside it (points run from the top)
  if [[ "$(git -C "$RUN_CWD" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$RUN_CWD" 2>/dev/null && pwd -P)" ]]; then
    echo "REFUSED (cwd_not_worktree): --cwd ${RUN_CWD} is not a git worktree
next: pass the candidate worktree (plan-finalize --stage freeze creates it), or run from inside it with --cwd .
(pipeline.md §When AID refuses: cwd_not_worktree)" >&2
    exit 3
  fi
  PLAN="$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")"
  EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd)"
  [[ -n "$PLAN_JSON" && -f "$PLAN_JSON" ]] && PLAN_JSON="$(cd "$(dirname "$PLAN_JSON")" && pwd)/$(basename "$PLAN_JSON")"
  RUN_CWD="$(cd "$RUN_CWD" && pwd)"
  cd "$RUN_CWD"
fi
[[ -z "$BASE_COMMIT" ]] && BASE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

HEAD_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
TIMELINE_FILE="${EVIDENCE_DIR}/timeline.jsonl"
OUTPUT_FILE="${EVIDENCE_DIR}/plan-diff.json"
SCOPE=plan PLAN_STEP=null STEP_DIR=""
if [[ -n "$STEP_N" ]]; then
  [[ "$STEP_N" =~ ^[0-9]+$ ]] || { echo "--step takes the run's 0-based step index (got '${STEP_N}')" >&2; exit 10; }
  [[ -f "$PLAN_JSON" ]] || { echo "--step needs --plan-json <the run's plan.json> (not found: ${PLAN_JSON:-none})" >&2; exit 10; }
  jq -e --argjson n "$STEP_N" '.steps[$n] != null' "$PLAN_JSON" >/dev/null \
    || { echo "--step ${STEP_N}: ${PLAN_JSON} has no step at that index" >&2; exit 10; }
  SCOPE=step
  PLAN_STEP="$(jq -r --argjson n "$STEP_N" '.steps[$n].plan_step // null' "$PLAN_JSON")"
  STEP_DIR="${EVIDENCE_DIR}/cp2/step-${STEP_N}"
  mkdir -p "$STEP_DIR"
  OUTPUT_FILE="${STEP_DIR}/plan-diff.json"
fi
GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Per-AC command timeout (seconds). A hanging or pathologically slow AC
# verification_pattern must not wedge the whole DONE-review — it is killed after
# this budget and reported absent(reason=timeout). Override via
# AID_PLAN_DIFF_AC_TIMEOUT for a plan with a legitimately long (but bounded) AC.
# Default 120s is ample for grep/jq/git checks and small bats --filter subsets; a
# full unbounded test suite inside a single AC is an anti-pattern — bound it or
# raise this (added 2026-07-10; matches aid-run-gates.sh's per-gate timeout model).
AC_CMD_TIMEOUT="${AID_PLAN_DIFF_AC_TIMEOUT:-120}"

# ── isolation (P110, --isolated) ────────────────────────────────────────────
# PD_NET: unshare | host | none | env_stripped:<VAR> | verification_env_unset:<VAR>
PD_NET="" PD_NET_LABEL="null" PD_ENV=() PD_ENV_KEYS="[]" PD_NEXT=""
# <timeout> <cmd file> — the namespace prefix: loopback up as root, then back to
# the caller's uid. Its own pid namespace too: whatever the point starts in the
# background (a listener) dies with it instead of outliving the measurer.
_pd_ns_run() {
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" \
    unshare -rn --pid --fork sh -c 'ip link set lo up 2>/dev/null; exec unshare --map-user="$1" --map-group="$2" timeout "$3" bash "$4"' \
    _ "$(id -u)" "$(id -g)" "$1" "$2"
}
_pd_isolation_init() {
  local map key val var probe
  map="$(yq -o=json '.verification_env // {}' "${STATE_ROOT}/.aid-o/config/execution.yaml" 2>/dev/null || echo '{}')"
  [[ -n "$map" && "$map" != null ]] || map='{}'
  if [[ "$(jq 'length' <<< "$map")" -gt 0 ]]; then
    PD_NET=host; PD_NET_LABEL="host (verification_env)"
    PD_ENV_KEYS="$(jq -c 'keys' <<< "$map")"
    while IFS=$'\t' read -r key val; do
      if [[ "$val" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]; then
        var="${BASH_REMATCH[1]}"
        [[ -n "${!var+x}" ]] || { PD_NET="verification_env_unset: ${var}"; PD_NEXT="next: set ${var} in the environment that runs the close, or give ${key} a literal value in verification_env"; return 0; }
        val="${!var}"
      fi
      PD_ENV+=("${key}=${val}")
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$map")
    return 0
  fi
  # a service address a test suite reads (ASISTENT_TEST_DATABASE_URL), not any
  # name with TEST in it (BATS_TEST_TMPDIR)
  var="$(compgen -e | grep -E '^[A-Za-z0-9_]*(DATABASE_URL|REDIS_URL|_TEST_[A-Za-z0-9_]*(URL|DSN))$' | head -1)" || true
  if [[ -n "$var" ]]; then
    PD_NET="env_stripped: ${var}"
    PD_NEXT="next: declare ${var} in verification_env (.aid-o/config/execution.yaml) or unset it — a suite that reads it would skip its database tests silently"
    return 0
  fi
  probe="$(mktemp)"; echo true > "$probe"
  if command -v unshare >/dev/null 2>&1 && _pd_ns_run 10 "$probe" >/dev/null 2>&1; then
    PD_NET=unshare; PD_NET_LABEL=unshare
    command -v ip >/dev/null 2>&1 || PD_NET_LABEL="unshare (no loopback)"
  else
    PD_NET=none
    PD_NEXT="next: install util-linux >= 2.38 (unshare --map-user) and allow user namespaces (sysctl kernel.unprivileged_userns_clone=1); until then no point is measured"
  fi
  rm -f "$probe"
}
(( ISOLATED )) && _pd_isolation_init

log_event "$TIMELINE_FILE" "plan_diff_start" plan="$PLAN" base_commit="$BASE_COMMIT" head_commit="$HEAD_COMMIT" || true

# Extract AC section + parse verification_pattern blocks. The parser lives in
# lib/aid-verification-pattern.sh (P109): the plan check, the brief lint and the
# plan lint read criteria through the same function this runner does.
parse_ac_blocks() {
  if [[ "$SCOPE" == step ]]; then parse_step_blocks; else
  _aid_vp_parse_ac "$PLAN" "Acceptance Criteria|Success Criteria"
  fi
}

# _last_naming_step — "AC<n>\t<highest plan step whose **Zavírá:** names it>",
# over the WHOLE plan file, so EPIC boundaries do not matter (P110).
_last_naming_step() {
  local s e head n val id
  while IFS=$'\t' read -r s e head; do
    [[ "$head" =~ ^###\ Step\ ([0-9]+) ]] || continue
    n="${BASH_REMATCH[1]}"
    val="$(_aid_plan_step_field "$PLAN" "$s" "$e" "Zavírá")" || continue
    for id in $(grep -oE '\bAC[0-9]+\b' <<< "$val"); do printf '%s\t%s\n' "$id" "$n"; done
  done < <(_aid_plan_step_bounds "$PLAN") | sort -k1,1 -k2,2n | awk -F'\t' '{last[$1] = $2} END {for (k in last) print k "\t" last[k]}'
}

# parse_step_blocks — the records of one run step (--step): its brief points
# measured here, the ones a later step measures (type `deferred`, cmd = that
# step), and the step's own labelled criteria.
parse_step_blocks() {
  local zav rec label last
  zav=" $(jq -r --argjson n "$STEP_N" '(.steps[$n].zavira // [])[]' "$PLAN_JSON" | tr '\n' ' ') "
  declare -A lastof=()
  while IFS=$'\t' read -r label last; do [[ -n "$label" ]] && lastof[$label]="$last"; done < <(_last_naming_step)
  if [[ "$zav" != "  " ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      label="${rec%%$'\x1f'*}"
      [[ "$zav" == *" $label "* ]] || continue
      last="${lastof[$label]:-}"
      if [[ "$PLAN_STEP" != null && -n "$last" ]] && (( last > PLAN_STEP )); then
        IFS=$'\x1f' read -r _ text _ <<< "$rec"
        printf '%s\x1f%s\x1fdeferred\x1f%s\x1f\x1f\x1f0\n' "$label" "$text" "$last"
      else
        printf '%s\n' "$rec"
      fi
    done < <(_aid_vp_parse_ac "$PLAN" "Acceptance Criteria")
  fi
  [[ "$PLAN_STEP" != null ]] && _aid_vp_parse_ac "$PLAN" "Step ${PLAN_STEP}:"
  return 0
}

# Run a single verification_pattern, output verdict + evidence.
# Supported types: cmd (exit code), must_not_exist (file absent), must_contain (regex match).
run_pattern() {
  local type=$1 cmd=$2 file=$3 regex=$4 expected_exit=$5 t="${6:-}" label="${7:-ac}"
  # the block's own timeout: (P110, 1..1800 s) or the runner's default
  [[ "$t" =~ ^[1-9][0-9]*$ ]] || t="$AC_CMD_TIMEOUT"

  local start_ms end_ms duration_ms
  start_ms=$(date +%s%3N)

  local verdict evidence
  # Defensive: expected_exit must be an integer. Coerce non-numeric / empty to 0.
  if ! [[ "$expected_exit" =~ ^[0-9]+$ ]]; then
    expected_exit=0
  fi
  case "$type" in
    cmd)
      local actual_exit=0
      # Per-AC timeout + process isolation. `timeout … bash -c` runs the AC cmd in
      # a SEPARATE process so (a) a hanging or pathologically slow AC cannot wedge
      # the whole DONE-review — timeout kills it after AC_CMD_TIMEOUT and we report
      # absent(reason=timeout); and (b) FATAL bash errors (set -u unbound-var
      # expansion aborts) stay contained in the child and remain catchable via the
      # exit code — the guarantee the old ( eval ) sub-subshell gave, now also
      # kill-able (PM fix 2026-07-08; per-AC timeout added 2026-07-10).
      # </dev/null: a command that reads stdin would eat the remaining criteria of
      # the loop's here-string (the same guard run_gate carries).
      if (( ISOLATED )); then
        case "$PD_NET" in
          none) printf 'absent\x1fno isolation: nested unshare refused (reason=no_isolation)\x1f0\n'; return 0 ;;
          env_stripped:*|verification_env_unset:*) printf 'absent\x1f%s (reason=%s)\x1f0\n' "$PD_NET" "$PD_NET"; return 0 ;;
        esac
        if [[ "$PD_NET" == unshare ]] && grep -Eq 'postgres(ql)?://|redis://|DATABASE_URL' <<< "$cmd"; then
          printf 'absent\x1fthe point needs a database and the project declares no verification_env (reason=no_verification_env)\x1f0\n'; return 0
        fi
        # written verbatim, so no shell re-parses the command (nested quotes, $x)
        local cf="${EVIDENCE_DIR}/cmd-${label//[^A-Za-z0-9_-]/_}.sh"; printf '%s\n' "$cmd" > "$cf"
        if [[ "$PD_NET" == unshare ]]; then
          _pd_ns_run "$t" "$cf" </dev/null >/dev/null 2>&1 || actual_exit=$?
        else
          env -i PATH="$PATH" HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" "${PD_ENV[@]}" timeout "$t" bash "$cf" </dev/null >/dev/null 2>&1 || actual_exit=$?
        fi
      else
        timeout "$t" bash -c "$cmd" </dev/null >/dev/null 2>&1 || actual_exit=$?
      fi
      if [[ "$actual_exit" -eq 124 && "$expected_exit" -ne 124 ]]; then
        verdict="absent"; evidence="timeout after ${t}s (reason=timeout)"
      elif [[ "$actual_exit" -eq "$expected_exit" ]]; then
        verdict="present"; evidence="exit=$actual_exit"
      else
        verdict="absent"; evidence="exit=$actual_exit (expected $expected_exit)"
      fi
      ;;
    must_not_exist)
      if [[ -e "$file" ]]; then
        verdict="absent"; evidence="file still exists at $file"
      else
        verdict="present"; evidence="file absent"
      fi
      ;;
    must_contain)
      if [[ ! -f "$file" ]]; then
        verdict="absent"; evidence="file not found: $file"
      elif grep -Eiq -- "$regex" "$file" 2>/dev/null; then
        verdict="present"; evidence="regex matched in $file"
      else
        verdict="absent"; evidence="regex not found in $file"
      fi
      ;;
    no_verification)
      verdict="skipped"; evidence="no verification_pattern block — prose AC, cannot auto-verify"
      ;;
    deferred)
      verdict="skipped"; evidence="measured at plan step ${cmd} (deferred_to_step)"
      ;;
    *)
      verdict="absent"; evidence="unknown pattern type: $type"
      ;;
  esac

  end_ms=$(date +%s%3N)
  duration_ms=$((end_ms - start_ms))

  # Use ASCII Unit Separator (0x1f) — `evidence` may contain "|" or ":".
  printf '%s\x1f%s\x1f%s\n' "$verdict" "$evidence" "$duration_ms"
}

# Main loop
ac_lines="$(parse_ac_blocks)"
# Count rows containing the Unit Separator delimiter.
ac_count="$(printf '%s' "$ac_lines" | grep -c $'\x1f' || true)"
ac_count="${ac_count:-0}"

# What this gate does NOT measure, counted so the plan close can say it aloud
# (2.114.0, agents P010: 13 summary criteria measured against ~57 step-level
# bullets the parser never saw; `status: pass` with `criteria: []` and nobody
# noticed until the final review raised it four rounds running):
#   summary_prose    — summary criteria parsed (AC<N>:/[role]) with no verification_pattern
#   summary_unparsed — bullets under the summary heading the parser does not take (no AC<N>: mark)
#   step_bullets     — bullets under a step's **Acceptance Criteria:** (never measured here)
summary_prose="$(printf '%s\n' "$ac_lines" | awk -F $'\x1f' 'NF > 2 && $3 == "no_verification" {n++} END {print n+0}')"
read -r summary_unparsed step_bullets < <(awk '
  /^## (Acceptance Criteria|Success Criteria)/ { sec=1; step=0; next }
  /^## /  { sec=0 }
  /^### Step [0-9]+/ { step=1; sec=0; inac=0; next }
  sec && /^- / && $0 !~ /^- \[[ x]\] AC[0-9]+:/ && $0 !~ /^- \[[ x]\] \[[a-z_]+\]/ { u++ }
  step && /^\*\*Acceptance Criteria:\*\*/ { inac=1; next }
  step && inac && /^- / { b++; next }
  step && inac && (/^\*\*/ || /^$/ || /^#/) { inac=0 }
  END { printf "%d %d\n", u+0, b+0 }' "$PLAN")
unmeasured_json="$(jq -nc --argjson p "$summary_prose" --argjson u "$summary_unparsed" --argjson b "$step_bullets" '{summary_prose: $p, summary_unparsed: $u, step_bullets: $b}')"

if [[ "$ac_count" -eq 0 && "$SCOPE" == step ]]; then
  # A step that closes no brief point and has no labelled criterion of its own:
  # nothing to run, said aloud (P110).
  jq -n --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" --arg ga "$GEN_AT" --arg pl "$PLAN" \
    --arg bc "$BASE_COMMIT" --arg hc "$HEAD_COMMIT" --argjson st "$STEP_N" --argjson ps "$PLAN_STEP" \
    '{_generated_by: $gb, _generated_at: $ga, plan_path: $pl, base_commit: $bc, head_commit: $hc,
      scope: "step", step: $st, plan_step: $ps, unmeasured_step: true, ac_count: 0, results: [],
      summary: {present_count: 0, absent_count: 0, skipped_count: 0}, overall_verdict: "skipped"}
     + {isolation: (if $iso == 1 then {worktree: $wt, env_keys: $ek, network: (if $net == "null" then null else $net end)} else null end)}' \
    --argjson iso "$ISOLATED" --arg wt "$(pwd)" --argjson ek "$PD_ENV_KEYS" --arg net "$PD_NET_LABEL" > "$OUTPUT_FILE"
  log_event "$TIMELINE_FILE" "plan_diff_complete" scope="step" step="$STEP_N" verdict="unmeasured_step" sha256="$(sha256sum "$OUTPUT_FILE" | cut -d' ' -f1)" || true
  exit 2
fi

if [[ "$ac_count" -eq 0 ]]; then
  # Graceful skip — no AC blocks
  jq -n \
    --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
    --arg ga "$GEN_AT" \
    --arg pl "$PLAN" \
    --arg bc "$BASE_COMMIT" \
    --arg hc "$HEAD_COMMIT" \
    '{
      "_generated_by": $gb,
      "_generated_at": $ga,
      "plan_path": $pl,
      "base_commit": $bc,
      "head_commit": $hc,
      "ac_count": 0,
      "results": [],
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1, "unmeasured": $um},
      "overall_verdict": "skipped"
    }
    + {isolation: (if $iso == 1 then {worktree: $wt, env_keys: $ek, network: (if $net == "null" then null else $net end)} else null end)}' \
    --argjson um "$unmeasured_json" --argjson iso "$ISOLATED" --arg wt "$(pwd)" --argjson ek "$PD_ENV_KEYS" --arg net "$PD_NET_LABEL" > "$OUTPUT_FILE"
  log_event "$TIMELINE_FILE" "plan_diff_complete" verdict="skipped" ac_count="0" step_bullets_unmeasured="$step_bullets" || true
  exit 2
fi

present_count=0; absent_count=0; skipped_count=0
# Collect per-AC NDJSON lines for batched slurp (avoids O(n) growing-payload
# re-parse per AC — measurable at 44+ ACs per /simplify efficiency review).
ac_result_lines=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Split on ASCII Unit Separator (0x1f) — cmd: values often contain | so we
  # cannot use that as field delimiter (would corrupt expected_exit, causing
  # `[[ N -eq <garbage> ]]` arithmetic failure under set -u).
  ac_timeout=""
  IFS=$'\x1f' read -r ac_label ac_text pat_type cmd file regex expected_exit ac_timeout <<< "$line"

  IFS=$'\x1f' read -r verdict evidence duration_ms <<< "$(run_pattern "$pat_type" "$cmd" "$file" "$regex" "$expected_exit" "$ac_timeout" "$ac_label")"

  [[ "$verdict" == "present" ]] && present_count=$((present_count + 1))
  [[ "$verdict" == "absent"  ]] && absent_count=$((absent_count + 1))
  [[ "$verdict" == "skipped" ]] && skipped_count=$((skipped_count + 1))

  # Runner-crash belt: if run_pattern died mid-way (empty fields), record a
  # skipped row instead of passing invalid JSON to --argjson (PM fix 2026-07-08).
  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]]; then
    verdict="skipped"; evidence="runner_error: pattern produced no result"; duration_ms=0
    skipped_count=$((skipped_count + 1))
  fi

  # NOTE: jq reserves `label` as a keyword (label/break syntax), so we pass it
  # as $lbl. Same for `verdict` — rename to $vrd defensively.
  ac_result_lines+=("$(jq -nc \
    --arg lbl "$ac_label" \
    --arg text "$ac_text" \
    --arg ptype "$pat_type" \
    --arg vrd "$verdict" \
    --arg evidence "$evidence" \
    --argjson dur "$duration_ms" \
    --arg dts "$([[ "$pat_type" == deferred ]] && echo "$cmd")" \
    '{ac_label: $lbl, ac_text: $text, pattern_type: $ptype, verdict: $vrd, evidence: $evidence, duration_ms: $dur}
     + (if $dts == "" then {} else {deferred_to_step: ($dts | tonumber)} end)
     + ([$evidence | capture("\\(reason=(?<r>[^)]+)\\)")] | if length > 0 then {reason: .[0].r} else {} end)')")
done <<< "$ac_lines"

# Single jq slurp builds final results array — O(1) jq invocation vs O(n).
if (( ${#ac_result_lines[@]} == 0 )); then
  results_json="[]"
else
  results_json=$(printf '%s\n' "${ac_result_lines[@]}" | jq -sc '.')
fi

# A step's deferrals (P110): cp2/step-N/deferred.json, written by
# `aid-fsm.sh increment-step --defer-criterion`. Each entry is honoured only
# while its Decision card passes aid_pm_card_check again — a hand-written file
# defers nothing. A deferred absent point no longer counts as absent here.
if [[ "$SCOPE" == step && -f "${STEP_DIR}/deferred.json" ]]; then
  while IFS=$'\t' read -r dlabel dcard; do
    [[ -n "$dlabel" ]] || continue
    if why="$(aid_pm_card_check "$dcard" "$dlabel")"; then
      results_json="$(jq -c --arg l "$dlabel" --slurpfile d "${STEP_DIR}/deferred.json" \
        'map(if .ac_label == $l then . + {deferred: $d[0][$l]} else . end)' <<< "$results_json")"
    else
      echo "aid-plan-diff: deferral of ${dlabel} not honoured: ${why}" >&2
    fi
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.card // "")"' "${STEP_DIR}/deferred.json" 2>/dev/null)
  absent_count="$(jq '[.[] | select(.verdict == "absent" and .deferred == null)] | length' <<< "$results_json")"
fi

# `pass` means EVERY criterion was checked and found. A skipped criterion (prose,
# or a pattern that produced no result) makes the run `partial`, however many
# others passed: ACTA P024 read `pass` with 4 of 9 criteria never looked at. A
# criterion with no result row at all is a broken run, never a pass.
overall="pass"
[[ "$skipped_count" -gt 0 ]] && overall="partial"
missing_rows=$(( ac_count - ${#ac_result_lines[@]} ))
if (( missing_rows > 0 )); then
  echo "ERROR: aid-plan-diff: ${missing_rows} of ${ac_count} acceptance criteria produced no result row" >&2
  absent_count=$(( absent_count + missing_rows ))
fi
[[ "$absent_count" -gt 0 ]] && overall="fail"

jq -n \
  --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
  --arg ga "$GEN_AT" \
  --arg pl "$PLAN" \
  --arg bc "$BASE_COMMIT" \
  --arg hc "$HEAD_COMMIT" \
  --argjson cnt "$ac_count" \
  --argjson res "$results_json" \
  --argjson pcnt "$present_count" \
  --argjson acnt "$absent_count" \
  --argjson scnt "$skipped_count" \
  --arg ov "$overall" \
  '{
    "_generated_by": $gb,
    "_generated_at": $ga,
    "plan_path": $pl,
    "base_commit": $bc,
    "head_commit": $hc,
    "ac_count": $cnt,
    "results": $res,
    "summary": {"present_count": $pcnt, "absent_count": $acnt, "skipped_count": $scnt, "unmeasured": $um},
    "overall_verdict": $ov
  }
  + {scope: $scope, step: $st, plan_step: $ps}
  + (if $scope == "step" then {unmeasured_step: false} else {} end)
  + (if $scope == "step" and $ps == null then {plan_step_note: "no plan_step (EPIC generated before 2.116.0): only the brief points of zavira were run, the step section was not read"} else {} end)
  + {isolation: (if $iso == 1 then {worktree: $wt, env_keys: $ek, network: (if $net == "null" then null else $net end)} else null end)}
  + (if $next == "" then {} else {next: $next} end)' \
  --argjson um "$unmeasured_json" --arg scope "$SCOPE" --argjson st "${STEP_N:-null}" --argjson ps "$PLAN_STEP" \
  --argjson iso "$ISOLATED" --arg wt "$(pwd)" --argjson ek "$PD_ENV_KEYS" --arg net "$PD_NET_LABEL" --arg next "$PD_NEXT" > "$OUTPUT_FILE"
[[ -n "$PD_NEXT" ]] && echo "$PD_NEXT" >&2

# sha256 binds the file to this run: increment-step accepts a step's
# plan-diff.json only when the timeline holds the measurer's event with its sha.
log_event "$TIMELINE_FILE" "plan_diff_complete" scope="$SCOPE" step="${STEP_N:-null}" verdict="$overall" ac_count="$ac_count" absent_count="$absent_count" sha256="$(sha256sum "$OUTPUT_FILE" | cut -d' ' -f1)" || true

[[ "$absent_count" -gt 0 ]] && exit 1
exit 0
