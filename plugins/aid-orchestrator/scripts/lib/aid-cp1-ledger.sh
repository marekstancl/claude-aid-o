#!/usr/bin/env bash
# =============================================================================
# aid-cp1-ledger.sh — CP1 revision-limit ledger (P065, E-065-7_7 Step 19)
#
# The mechanical CP1 revision-limit AUTHORITY. A per-plan (`plan_id`-keyed)
# review-cycle counter that survives normal evidence-path/verifier changes.
#
# WHY THIS EXISTS: `revision_count` today lives only in adjudicator prose and
# aid-cp1-gate.sh (see that file — read-only reference, NOT modified here)
# never reads it; the gate fails only on `accepted_blockers`. Nothing
# mechanically bounds a runaway CP1 revise-loop. This script is the counting
# primitive that closes that gap.
#
# SCOPE (this step, Step 19, is the FOUNDATION only):
#   - init / increment / read / check-budget, all fail-closed.
#   - Does NOT wire itself into aid-cp1-gate.sh or aid-plan-to-epic.sh — that
#     mechanical GATE enforcement (blocking epic-gen on an exhausted budget)
#     is Step 20's job (a LATER step, not implemented here — no back-dependency
#     from this file onto Step 20's work).
#   - `check-budget` only REPORTS status; it never blocks anything by itself.
#
# NOT COMMITTED: `.aid-o/` (and `**/.aid-o/`) is gitignored (see .gitignore
# root rules) — the ledger is RUNTIME state, created by an explicit `init`.
# P065 BOOTSTRAP: `aid-cp1-ledger.sh init --pre-enforcement P065` is a RUNTIME
# action for the orchestrator to run later against the live P065 workspace —
# it is NOT part of this code-only step and this step does not run it.
#
# HONEST SCOPE: this ledger is resilient to normal evidence-dir/verifier-
# identity churn (its path depends on plan_id ONLY). It does NOT claim to be
# un-deletable — a missing ledger with CP1 evidence already present is FAIL-
# CLOSED (budget-exhausted/init-required), never a silent reset. Recovery is
# an explicit `init` (only valid for a provably-new plan) or a PM override.
#
# CP1 EVIDENCE DIR — how "does this plan already have CP1-deep evidence"
# is determined: aid-cp1-gate.sh (read for this) computes
#   <project_root>/.aid-o/work/evidence/<plan_id>/cp1-deep/
# and requires 4 named files there (cp1-lens-L1-behavior.md, -L2-feasibility.md,
# -L3-enforcement.md, cp1-adjudicator.md) for a high-risk plan to pass. This
# script reuses that EXACT path (`_cp1_evidence_dir`) — plan_id-keyed, no
# separate convention invented — and treats "the dir exists and is non-empty"
# (>=1 entry) as evidence-present, rather than requiring all 4 named files:
# a PARTIAL evidence write (e.g. only L1 written so far, adjudicator crashed
# mid-run) already proves the plan is not "provably new" and must not be
# allowed a silent attempts:0 reset via a bare `init`. Fail-closed leans
# toward the stricter (any-entry) reading here on purpose.
#
# LEDGER FILE — <project_root>/.aid-o/work/cp1-ledger/<plan_id>.yaml
#   schema_version:  "aid-2.0"
#   plan_id:         string
#   attempts:        integer (0 = no revision cycle counted yet)
#   max:             integer, currently 3 (1 initial + 2 revisions)
#   pre_enforcement: boolean (true only for the explicit P065 bootstrap path)
#   pm_override:     {present: boolean, ref: string|null}
#   created_at / updated_at: ISO-8601 UTC
#   attempts_log:    [{n, plan_hash, codex_session (string|null), at}, ...]
#
# Usage:
#   aid-cp1-ledger.sh init [--pre-enforcement] [--project-root <path>] <plan_id>
#   aid-cp1-ledger.sh increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
#   aid-cp1-ledger.sh read [--project-root <path>] <plan_id>
#   aid-cp1-ledger.sh check-budget [--project-root <path>] <plan_id>
#
# Exit codes:
#   init/increment/read: 0 = success, 1 = precondition/fail-closed failure.
#   check-budget: 0 = budget available (incl. pm_override present), 1 = FAIL-
#     CLOSED (exhausted, OR corrupt ledger, OR evidence present but ledger
#     missing), 2 = not_initialized (no ledger AND no CP1 evidence — a
#     genuinely brand-new plan; caller should run `init`).
#
# **Last Updated:** 2026-07-18
# =============================================================================
set -euo pipefail

MAX_ATTEMPTS=3

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: aid-cp1-ledger.sh <subcommand> [args...]

Subcommands:
  init [--pre-enforcement] [--project-root <path>] <plan_id>
      Create a fresh ledger at attempts:0. Without --pre-enforcement, this
      only succeeds when NO CP1-deep evidence dir exists yet for <plan_id>
      (a provably new plan). --pre-enforcement is the explicit, audited
      bootstrap for an ALREADY in-flight plan (e.g. P065) and bypasses the
      evidence check. In both modes, init refuses to overwrite an existing
      ledger (never a silent reset).

  increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
      Advance the ledger's attempts counter, but ONLY when <plan_hash>
      differs from the last recorded attempt's plan_hash. A re-run with an
      unchanged plan_hash is a no-op (prints current state, does not touch
      the file). Requires an existing, valid ledger — never auto-creates one.

  read [--project-root <path>] <plan_id>
      Print the ledger as JSON. Fails if the ledger is missing or corrupt.

  check-budget [--project-root <path>] <plan_id>
      Report budget status without mutating anything. See exit codes above.
EOF
}

# ---------------------------------------------------------------------------
# _fail <msg>  — emit a PRECONDITION FAIL message and exit 1.
# ---------------------------------------------------------------------------
_fail() {
  echo "PRECONDITION FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# _validate_plan_id <plan_id>  — non-empty, path-traversal-safe.
# ---------------------------------------------------------------------------
_validate_plan_id() {
  local pid="$1"
  [[ -n "$pid" ]] || _fail "plan_id is empty"
  [[ "$pid" =~ ^[A-Za-z0-9_-]+$ ]] || _fail "plan_id '$pid' contains invalid characters (path traversal guard)"
}

# ---------------------------------------------------------------------------
# _ledger_path <project_root> <plan_id>
# ---------------------------------------------------------------------------
_ledger_path() {
  printf '%s/.aid-o/work/cp1-ledger/%s.yaml' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _cp1_evidence_dir <project_root> <plan_id>  — same convention as
# aid-cp1-gate.sh's evidence_dir (see header comment above).
# ---------------------------------------------------------------------------
_cp1_evidence_dir() {
  printf '%s/.aid-o/work/evidence/%s/cp1-deep' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _cp1_evidence_exists <dir>  — true iff the dir exists and has >=1 entry.
# ---------------------------------------------------------------------------
_cp1_evidence_exists() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  local files=("$dir"/*)
  [[ "$had_nullglob" -eq 1 ]] || shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]]
}

# ---------------------------------------------------------------------------
# _json_str_or_null <maybe-string>  — JSON string if non-empty, else `null`.
# ---------------------------------------------------------------------------
_json_str_or_null() {
  if [[ -n "$1" ]]; then jq -n --arg s "$1" '$s'; else printf 'null'; fi
}

# ---------------------------------------------------------------------------
# _ledger_read_json <ledger_path>
#   Reads the ledger YAML, converts to JSON, and validates the minimal shape
#   (attempts/max numeric, plan_id non-empty string). Echoes the JSON on
#   success; returns non-zero (fail-closed) on missing file, unparseable
#   YAML, or a malformed shape. Never partially trusts a corrupt file.
# ---------------------------------------------------------------------------
_ledger_read_json() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local json
  json="$(yq -o=json '.' "$path" 2>/dev/null)" || return 1
  [[ -n "$json" ]] || return 1
  printf '%s' "$json" | jq -e '
    (.attempts | type == "number")
    and (.max | type == "number")
    and (.plan_id | type == "string" and length > 0)
  ' >/dev/null 2>&1 || return 1
  printf '%s' "$json"
}

# ---------------------------------------------------------------------------
# _write_ledger_json <ledger_path> <json>  — atomic temp+mv write, rendered
# as YAML (via yq, matching this project's YAML-state-file convention).
# ---------------------------------------------------------------------------
_write_ledger_json() {
  local path="$1" json="$2" tmp
  tmp="${path}.tmp.$$"
  printf '%s' "$json" | yq -p=json -o=yaml '.' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$path" || { rm -f "$tmp"; return 1; }
  return 0
}

# ===========================================================================
# cmd_init [--pre-enforcement] [--project-root <path>] <plan_id>
# ===========================================================================
cmd_init() {
  local pre_enforcement=false project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pre-enforcement) pre_enforcement=true; shift ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"
  [[ -d "$project_root" ]] || _fail "project_root not found: $project_root"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"

  # Never overwrite an existing ledger — that would be a silent reset.
  if [[ -f "$ledger_path" ]]; then
    _fail "ledger already exists for ${plan_id} at ${ledger_path} — init will not overwrite an existing ledger (silent reset is forbidden). Use 'increment'/'read'/'check-budget', or a PM override to intentionally reset."
  fi

  local evidence_dir; evidence_dir="$(_cp1_evidence_dir "$project_root" "$plan_id")"
  if [[ "$pre_enforcement" != "true" ]]; then
    if _cp1_evidence_exists "$evidence_dir"; then
      _fail "CP1-deep evidence already exists for ${plan_id} at ${evidence_dir} — plan is not provably new. init (without --pre-enforcement) only seeds attempts:0 for a brand-new plan. Use 'init --pre-enforcement' for an explicit, audited bootstrap of an already in-flight plan."
    fi
  fi

  mkdir -p "$(dirname "$ledger_path")" || _fail "cannot create $(dirname "$ledger_path")"

  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local init_json
  init_json="$(jq -n \
    --arg sv "aid-2.0" \
    --arg pid "$plan_id" \
    --argjson max "$MAX_ATTEMPTS" \
    --argjson pre "$pre_enforcement" \
    --arg now "$now" \
    '{
      schema_version: $sv,
      plan_id: $pid,
      attempts: 0,
      max: $max,
      pre_enforcement: $pre,
      pm_override: {present: false, ref: null},
      created_at: $now,
      updated_at: $now,
      attempts_log: []
    }')" || _fail "cannot render initial ledger JSON"

  _write_ledger_json "$ledger_path" "$init_json" || _fail "cannot write ledger to ${ledger_path}"

  echo "$ledger_path"
  return 0
}

# ===========================================================================
# cmd_increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
# ===========================================================================
cmd_increment() {
  local project_root="" codex_session="" plan_id="" plan_hash=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      --codex-session) codex_session="${2:-}"; shift 2 ;;
      --codex-session=*) codex_session="${1#--codex-session=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  [[ ${#positional[@]} -eq 2 ]] || _fail "increment requires exactly <plan_id> <plan_hash> (got ${#positional[@]} positional args)"
  plan_id="${positional[0]}"
  plan_hash="${positional[1]}"
  _validate_plan_id "$plan_id"
  [[ -n "$plan_hash" ]] || _fail "plan_hash is empty"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  [[ -f "$ledger_path" ]] || _fail "ledger not found for ${plan_id} at ${ledger_path} — run 'init' first (increment never auto-creates a ledger)."

  local ledger_json
  ledger_json="$(_ledger_read_json "$ledger_path")" \
    || _fail "ledger for ${plan_id} at ${ledger_path} is missing/corrupt/unparseable — cannot safely increment (fail-closed; obtain a PM override or investigate before re-init)."

  # NOTE (design decision, documented per Step-19 process instructions):
  # plan_hash is the sole gate on whether this call advances the counter, per
  # the acceptance criteria ("increment with an unchanged plan_hash is a
  # no-op; a new plan_hash advances the count"). codex_session is recorded as
  # per-attempt metadata (useful evidence for Step 20 / audit trail) but is
  # NOT an additional advance/no-op condition here — requiring both a new
  # plan_hash AND a new codex_session to differ would risk a stuck ledger if
  # a caller re-supplies the prior session id alongside a genuinely new
  # plan_hash. Session-repeat enforcement, if wanted, is Step 20's call.
  local last_hash
  last_hash="$(printf '%s' "$ledger_json" | jq -r '.attempts_log[-1].plan_hash // ""')"

  if [[ "$plan_hash" == "$last_hash" ]]; then
    printf '%s\n' "$ledger_json"
    return 0
  fi

  local attempts new_n now
  attempts="$(printf '%s' "$ledger_json" | jq -r '.attempts')"
  new_n=$(( attempts + 1 ))
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local cs_json new_json
  cs_json="$(_json_str_or_null "$codex_session")"
  new_json="$(printf '%s' "$ledger_json" | jq \
    --arg ph "$plan_hash" \
    --argjson cs "$cs_json" \
    --arg now "$now" \
    --argjson n "$new_n" \
    '.attempts = $n
     | .updated_at = $now
     | .attempts_log += [{n: $n, plan_hash: $ph, codex_session: $cs, at: $now}]')" \
    || _fail "cannot compute updated ledger for ${plan_id}"

  _write_ledger_json "$ledger_path" "$new_json" || _fail "cannot write updated ledger to ${ledger_path}"

  printf '%s\n' "$new_json"
  return 0
}

# ===========================================================================
# cmd_read [--project-root <path>] <plan_id>
# ===========================================================================
cmd_read() {
  local project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  local ledger_json
  ledger_json="$(_ledger_read_json "$ledger_path")" \
    || _fail "ledger for ${plan_id} at ${ledger_path} is missing or corrupt."

  printf '%s' "$ledger_json" | jq '.'
  return 0
}

# ===========================================================================
# cmd_check_budget [--project-root <path>] <plan_id>
#   Read-only status report. NEVER mutates the ledger or creates one.
# ===========================================================================
cmd_check_budget() {
  local project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path evidence_dir evidence_present
  ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  evidence_dir="$(_cp1_evidence_dir "$project_root" "$plan_id")"
  evidence_present="false"
  _cp1_evidence_exists "$evidence_dir" && evidence_present="true"

  # Case 1: no ledger file at all.
  if [[ ! -f "$ledger_path" ]]; then
    if [[ "$evidence_present" == "true" ]]; then
      # FAIL-CLOSED: CP1 evidence exists but no ledger — never auto-create a
      # zero ledger here (that would let deleting the file reset the budget).
      jq -n --arg pid "$plan_id" --argjson ev true \
        '{plan_id: $pid, status: "init_required", evidence_present: $ev, attempts: null, max: null, pm_override: false,
          reason: "CP1-deep evidence exists but no ledger was found. A missing ledger is treated as budget-exhausted, never a silent reset. Run init, or obtain a PM override."}'
      return 1
    fi
    jq -n --arg pid "$plan_id" --argjson ev false \
      '{plan_id: $pid, status: "not_initialized", evidence_present: $ev, attempts: null, max: null, pm_override: false,
        reason: "No ledger and no CP1-deep evidence yet — plan has not started CP1-deep review. Run init to begin tracking."}'
    return 2
  fi

  # Case 2: ledger file exists — validate it.
  local ledger_json
  if ! ledger_json="$(_ledger_read_json "$ledger_path")"; then
    jq -n --arg pid "$plan_id" --argjson ev "$([[ "$evidence_present" == "true" ]] && echo true || echo false)" \
      '{plan_id: $pid, status: "init_required", evidence_present: $ev, attempts: null, max: null, pm_override: false,
        reason: "Ledger file exists but is corrupt/unparseable — treated as budget-exhausted. PM override required."}'
    return 1
  fi

  local attempts max
  attempts="$(printf '%s' "$ledger_json" | jq -r '.attempts')"
  max="$(printf '%s' "$ledger_json" | jq -r '.max')"
  local ev_bool; ev_bool="$([[ "$evidence_present" == "true" ]] && echo true || echo false)"

  # NOTE: The pm_override field is retained in the ledger schema for forward
  # compatibility and informational purposes, but check-budget NO LONGER uses it
  # to authorize bypassing the budget check. The ONLY sanctioned override path
  # for an exhausted budget is the gate-level cp1-pm-escalation-override.json
  # artifact, verified and consumed by aid-cp1-gate.sh. Direct ledger-internal
  # overrides (via pm_override.present hand-edit) are no longer honored.

  if [[ "$attempts" -ge "$max" ]]; then
    jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" \
      '{plan_id: $pid, status: "exhausted", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: false,
        reason: "attempts >= max — revision budget exhausted. Use PM-escalation override if needed."}'
    return 1
  fi

  jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" \
    '{plan_id: $pid, status: "available", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: false,
      reason: "within budget"}'
  return 0
}

# ===========================================================================
# main
# ===========================================================================
main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    _fail "missing subcommand"
  fi
  local sub="$1"; shift
  case "$sub" in
    init)          cmd_init "$@" ;;
    increment)     cmd_increment "$@" ;;
    read)          cmd_read "$@" ;;
    check-budget)  cmd_check_budget "$@" ;;
    -h|--help)     usage; exit 0 ;;
    *)
      usage >&2
      _fail "unknown subcommand: $sub" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
