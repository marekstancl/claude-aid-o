#!/usr/bin/env bash
# =============================================================================
# aid-delivery-gate.sh — C1 Delivery Engine main dispatcher
#
# Orchestrates all DG check plugins, aggregates results, and writes a
# protocol-v2 delivery-gate.json artifact.
#
# Usage:
#   aid-delivery-gate.sh --epic <id> --run <id> --base <sha> --phase <D0|D1> \
#                         [--changed-paths <file>]
#
# Options:
#   --epic          EPIC ID (e.g. E-050-1_1)
#   --run           Run ID (e.g. R-E050-1)
#   --base          Base git SHA (used for freshness check)
#   --phase         D0 (post-execute, observe) or D1 (pre-release, future)
#   --changed-paths Optional file with one changed path per line
#
# Output:
#   .aid-o/work/evidence/<epic_id>/<run_id>/delivery-gate.json
#
# Environment:
#   DELIVERY_GATE_POLICY — overrides default policy path
#   AID_PROJECT_ROOT     — project root (default: git toplevel)
#   AID_EVIDENCE_BASE    — overrides .aid-o/work/evidence/ base path
#
# Exit codes:
#   0 — observe mode success (delivery_ready may still be false — check JSON)
#   1 — hard error (missing required args, policy not found, cannot write output)
#
# Constraints:
#   - No eval, no shell string expansion for command execution
#   - Missing check scripts → unverifiable (not error, not pass)
#   - Policy not found → exit 1 (hard error)
#   - Produces valid protocol-v2 JSON (verified by aid-protocol-validate.sh)
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve script directory (absolute, follows symlinks)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source library files
# ---------------------------------------------------------------------------
# shellcheck source=lib/aid-delivery-profile.sh
source "${SCRIPT_DIR}/lib/aid-delivery-profile.sh"
# shellcheck source=lib/aid-finding-fingerprint.sh
source "${SCRIPT_DIR}/lib/aid-finding-fingerprint.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly CHECKS=(dg01 dg02 dg03 dg04 dg05 dg06 dg07 dg08 dg09 dg10 dg11 dg12)
readonly CHECK_SCRIPT_DIR="${SCRIPT_DIR}/lib/delivery-checks"
readonly PRODUCER="aid-delivery-gate@2.0"
readonly SCHEMA_VERSION="aid-2.0"
readonly CONTROL_PROTOCOL="aid-2.0"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
EPIC_ID=""
RUN_ID=""
BASE_SHA=""
PHASE=""
CHANGED_PATHS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic)
      [[ $# -lt 2 ]] && { echo "ERROR: --epic requires a value" >&2; exit 1; }
      EPIC_ID="$2"
      shift 2
      ;;
    --run)
      [[ $# -lt 2 ]] && { echo "ERROR: --run requires a value" >&2; exit 1; }
      RUN_ID="$2"
      shift 2
      ;;
    --base)
      [[ $# -lt 2 ]] && { echo "ERROR: --base requires a value" >&2; exit 1; }
      BASE_SHA="$2"
      shift 2
      ;;
    --phase)
      [[ $# -lt 2 ]] && { echo "ERROR: --phase requires a value" >&2; exit 1; }
      PHASE="$2"
      shift 2
      ;;
    --changed-paths)
      [[ $# -lt 2 ]] && { echo "ERROR: --changed-paths requires a value" >&2; exit 1; }
      CHANGED_PATHS_FILE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Usage: aid-delivery-gate.sh --epic <id> --run <id> --base <sha> --phase <D0|D1> [--changed-paths <file>]" >&2
      exit 1
      ;;
  esac
done

# Validate required arguments
for _req_arg in EPIC_ID RUN_ID BASE_SHA PHASE; do
  if [[ -z "${!_req_arg}" ]]; then
    echo "ERROR: required argument missing: --${_req_arg//_/-}" >&2
    exit 1
  fi
done

if [[ "$PHASE" != "D0" && "$PHASE" != "D1" ]]; then
  echo "ERROR: --phase must be D0 or D1, got: ${PHASE}" >&2
  exit 1
fi

if [[ -n "$CHANGED_PATHS_FILE" && ! -f "$CHANGED_PATHS_FILE" ]]; then
  echo "ERROR: --changed-paths file not found: ${CHANGED_PATHS_FILE}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve project root
# ---------------------------------------------------------------------------
if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$AID_PROJECT_ROOT"
else
  PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: cannot determine project root (not a git repo?)" >&2
    exit 1
  }
fi

# ---------------------------------------------------------------------------
# Resolve policy file
# ---------------------------------------------------------------------------
if [[ -n "${DELIVERY_GATE_POLICY:-}" ]]; then
  POLICY_FILE="$DELIVERY_GATE_POLICY"
else
  POLICY_FILE="${SCRIPT_DIR}/../defaults/policies/delivery-gate.yaml"
fi

# Canonicalize path
POLICY_FILE="$(cd "$(dirname "$POLICY_FILE")" && pwd)/$(basename "$POLICY_FILE")"

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: delivery-gate policy not found: ${POLICY_FILE}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve output path
# ---------------------------------------------------------------------------
if [[ -n "${AID_EVIDENCE_BASE:-}" ]]; then
  EVIDENCE_BASE="$AID_EVIDENCE_BASE"
else
  EVIDENCE_BASE="${PROJECT_ROOT}/.aid-o/work/evidence"
fi

OUTPUT_DIR="${EVIDENCE_BASE}/${EPIC_ID}/${RUN_ID}"
OUTPUT_FILE="${OUTPUT_DIR}/delivery-gate.json"
PROJECT_ID="$(basename "$PROJECT_ROOT")"  # must be set before findings[] loop at line ~648

mkdir -p "$OUTPUT_DIR" || {
  echo "ERROR: cannot create output directory: ${OUTPUT_DIR}" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Resolve current HEAD and freshness
# ---------------------------------------------------------------------------
HEAD_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || {
  echo "ERROR: cannot resolve HEAD sha" >&2
  exit 1
}

# revision.head_sha is always the current HEAD at time of dispatch.
# revision.freshness/head_is_current are for protocol-level staleness:
#   "is this artifact still current right now?" — at creation time, always yes.
# delivery_gate.freshness is delivery-level:
#   "did commits land after the run started?" — stale if HEAD != base_sha.
REVISION_FRESHNESS="current"
HEAD_IS_CURRENT="true"

if [[ "$HEAD_SHA" == "$BASE_SHA" ]]; then
  DG_FRESHNESS="fresh"
else
  # Commits landed since run started → delivery report is based on a different snapshot
  DG_FRESHNESS="stale"
fi

# ---------------------------------------------------------------------------
# Resolve profile
# ---------------------------------------------------------------------------
PROFILE="$(resolve_profile "$PROJECT_ROOT" "${CHANGED_PATHS_FILE:-}")" || {
  echo "ERROR: resolve_profile failed" >&2
  exit 1
}

# Read policy settings
BLOCK_ON_UNVERIFIABLE="$(yq e '.block_on_unverifiable // true' "$POLICY_FILE" 2>/dev/null)"
OUTPUT_PREVIEW_LINES="$(yq e '.output_preview_lines // 80' "$POLICY_FILE" 2>/dev/null)"

# Read skip_reason_allowlist
mapfile -t SKIP_REASON_ALLOWLIST < <(yq e '.skip_reason_allowlist[]' "$POLICY_FILE" 2>/dev/null)

# ---------------------------------------------------------------------------
# Applicability helpers
# ---------------------------------------------------------------------------

# _has_lockfile: check if a lockfile exists in project root
_has_lockfile() {
  local root="$1"
  [[ -f "${root}/package-lock.json" ]] || \
  [[ -f "${root}/yarn.lock" ]] || \
  [[ -f "${root}/pnpm-lock.yaml" ]] || \
  [[ -f "${root}/bun.lockb" ]]
}

# _has_workspaces: check if package.json has "workspaces"
_has_workspaces() {
  local root="$1"
  [[ -f "${root}/package.json" ]] && grep -q '"workspaces"' "${root}/package.json"
}

# _has_build_script: check if package.json has scripts.build
_has_build_script() {
  local root="$1"
  [[ -f "${root}/package.json" ]] && \
    jq -e '.scripts.build // empty' "${root}/package.json" >/dev/null 2>&1
}

# _has_typecheck_script: check if package.json has scripts.typecheck
_has_typecheck_script() {
  local root="$1"
  [[ -f "${root}/package.json" ]] && \
    jq -e '.scripts.typecheck // empty' "${root}/package.json" >/dev/null 2>&1
}

# _has_ts_files: check if any .ts files exist
_has_ts_files() {
  local root="$1"
  find "$root" -name "*.ts" -not -path "*/node_modules/*" -maxdepth 5 \
    -print -quit 2>/dev/null | grep -q .
}

# _changed_paths_match: check if any changed path matches any glob pattern
_changed_paths_match() {
  local patterns_json="$1"
  local changed_file="$2"

  [[ -z "$changed_file" || ! -f "$changed_file" ]] && return 1

  # Get patterns as array
  local -a patterns
  mapfile -t patterns < <(echo "$patterns_json" | jq -r '.[]' 2>/dev/null)

  while IFS= read -r changed_path; do
    [[ -z "$changed_path" ]] && continue
    for pattern in "${patterns[@]}"; do
      # Use bash glob matching (extglob-safe)
      # shellcheck disable=SC2254
      case "$changed_path" in
        $pattern) return 0 ;;
      esac
    done
  done < "$changed_file"

  return 1
}

# _dep_removed: check if package.json changed and a dep was removed
_dep_removed() {
  local root="$1"
  local base_sha="$2"
  local changed_file="${3:-}"

  # First check if package.json is in changed paths (if file provided)
  if [[ -n "$changed_file" && -f "$changed_file" ]]; then
    grep -q "package.json" "$changed_file" || return 1
  fi

  # Try git diff to detect removed dep
  git -C "$root" diff "${base_sha}..HEAD" -- package.json 2>/dev/null | \
    grep -q '^-' || return 1

  return 0
}

# _has_authority_surface: check if any .yaml/.json policy files changed
_has_authority_surface() {
  local changed_file="${1:-}"

  [[ -z "$changed_file" || ! -f "$changed_file" ]] && return 1
  grep -qE '\.(yaml|yml|json)$' "$changed_file"
}

# ---------------------------------------------------------------------------
# _check_applicable(check_id) → 0=applicable, 1=not applicable
# ---------------------------------------------------------------------------
_check_applicable() {
  local check_id="$1"

  # Read required_when conditions from policy
  local conditions_count
  conditions_count="$(yq e ".checks.${check_id}.required_when | length" "$POLICY_FILE" 2>/dev/null)"

  if [[ -z "$conditions_count" || "$conditions_count" == "null" || "$conditions_count" -eq 0 ]]; then
    # No required_when → not applicable
    return 1
  fi

  # Top-level OR: any condition group that fully passes → applicable
  local i
  for (( i=0; i<conditions_count; i++ )); do
    local cond_json
    cond_json="$(yq e -o=json ".checks.${check_id}.required_when[${i}]" "$POLICY_FILE" 2>/dev/null)"

    # Check always:true
    local always_val
    always_val="$(echo "$cond_json" | jq -r '.always // false')"
    if [[ "$always_val" == "true" ]]; then
      return 0
    fi

    # Check has_lockfile
    local hl
    hl="$(echo "$cond_json" | jq -r '.has_lockfile // false')"
    if [[ "$hl" == "true" ]]; then
      _has_lockfile "$PROJECT_ROOT" && return 0
    fi

    # Check has_workspaces
    local hw
    hw="$(echo "$cond_json" | jq -r '.has_workspaces // false')"
    if [[ "$hw" == "true" ]]; then
      _has_workspaces "$PROJECT_ROOT" && return 0
    fi

    # Check has_build_script
    local hbs
    hbs="$(echo "$cond_json" | jq -r '.has_build_script // false')"
    if [[ "$hbs" == "true" ]]; then
      _has_build_script "$PROJECT_ROOT" && return 0
    fi

    # Check has_typecheck_script
    local hts
    hts="$(echo "$cond_json" | jq -r '.has_typecheck_script // false')"
    if [[ "$hts" == "true" ]]; then
      _has_typecheck_script "$PROJECT_ROOT" && return 0
    fi

    # Check has_ts_files
    local htf
    htf="$(echo "$cond_json" | jq -r '.has_ts_files // false')"
    if [[ "$htf" == "true" ]]; then
      _has_ts_files "$PROJECT_ROOT" && return 0
    fi

    # Check changed_paths_match
    local cpm
    cpm="$(echo "$cond_json" | jq -c '.changed_paths_match // null')"
    if [[ "$cpm" != "null" ]]; then
      _changed_paths_match "$cpm" "${CHANGED_PATHS_FILE:-}" && return 0
    fi

    # Check dep_removed
    local dr
    dr="$(echo "$cond_json" | jq -r '.dep_removed // false')"
    if [[ "$dr" == "true" ]]; then
      _dep_removed "$PROJECT_ROOT" "$BASE_SHA" "${CHANGED_PATHS_FILE:-}" && return 0
    fi

    # Check has_authority_surface
    local has_auth
    has_auth="$(echo "$cond_json" | jq -r '.has_authority_surface // false')"
    if [[ "$has_auth" == "true" ]]; then
      _has_authority_surface "${CHANGED_PATHS_FILE:-}" && return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# _in_allowlist(reason) → 0=allowed, 1=not allowed
# ---------------------------------------------------------------------------
_in_allowlist() {
  local reason="$1"
  local allowed
  for allowed in "${SKIP_REASON_ALLOWLIST[@]}"; do
    [[ "$reason" == "$allowed" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# _get_check_name(check_id) → prints check name
# ---------------------------------------------------------------------------
_get_check_name() {
  local check_id="$1"
  yq e ".checks.${check_id}.name // \"${check_id}\"" "$POLICY_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# _get_policy_skip_reason(check_id, profile) → prints skip reason or ""
# ---------------------------------------------------------------------------
_get_policy_skip_reason() {
  local check_id="$1"
  local first_profile="$2"

  # For union profiles, use first component
  local profile_part="${first_profile%%+*}"

  yq e ".profiles.${profile_part}.commands.${check_id}.skip_reason // \"\"" \
    "$POLICY_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Run a single check
#
# Outputs a JSON object representing the check result.
# Sets global DELIVERY_READY=false on fail conditions.
# ---------------------------------------------------------------------------

COUNT_TOTAL=0
COUNT_PASS=0
COUNT_FAIL=0
COUNT_SKIP=0
COUNT_UNVERIFIABLE=0
DELIVERY_READY=true

# Collect check results as JSON array (built incrementally)
CHECKS_JSON="[]"

_run_check() {
  local check_id="$1"
  COUNT_TOTAL=$(( COUNT_TOTAL + 1 ))

  local check_name
  check_name="$(_get_check_name "$check_id")"

  # -------------------------------------------------------------------------
  # 1. Profile is unverifiable → all checks unverifiable
  # -------------------------------------------------------------------------
  if [[ "$PROFILE" == "unverifiable" ]]; then
    COUNT_UNVERIFIABLE=$(( COUNT_UNVERIFIABLE + 1 ))
    CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
      --arg id "$check_id" \
      --arg name "$check_name" \
      '. + [{"id": $id, "name": $name, "status": "unverifiable", "skip_reason": "unverifiable_profile", "output_preview": "", "duration_ms": 0}]')"
    return
  fi

  # -------------------------------------------------------------------------
  # 2. Applicability check
  # -------------------------------------------------------------------------
  if ! _check_applicable "$check_id"; then
    # Check if the policy specifies a skip_reason for this check in this profile
    local policy_skip_reason
    policy_skip_reason="$(_get_policy_skip_reason "$check_id" "$PROFILE")"

    local skip_reason="not_required"
    if [[ -n "$policy_skip_reason" ]]; then
      skip_reason="$policy_skip_reason"
    fi

    COUNT_SKIP=$(( COUNT_SKIP + 1 ))
    CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
      --arg id "$check_id" \
      --arg name "$check_name" \
      --arg reason "$skip_reason" \
      '. + [{"id": $id, "name": $name, "status": "skip", "skip_reason": $reason, "output_preview": "", "duration_ms": 0}]')"
    return
  fi

  # -------------------------------------------------------------------------
  # 3. Policy overrides: check if policy says skip for this check+profile
  # -------------------------------------------------------------------------
  local policy_skip_reason
  policy_skip_reason="$(_get_policy_skip_reason "$check_id" "$PROFILE")"

  # Get the command argv from policy
  local -a check_argv
  mapfile -t check_argv < <(select_commands "$POLICY_FILE" "$PROFILE" "$check_id")

  # -------------------------------------------------------------------------
  # 4. If policy provides a skip_reason and empty cmd → skip
  # -------------------------------------------------------------------------
  if [[ -n "$policy_skip_reason" && ${#check_argv[@]} -eq 0 ]]; then
    # Validate the skip_reason is in the allowlist
    if _in_allowlist "$policy_skip_reason"; then
      COUNT_SKIP=$(( COUNT_SKIP + 1 ))
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg reason "$policy_skip_reason" \
        '. + [{"id": $id, "name": $name, "status": "skip", "skip_reason": $reason, "output_preview": "", "duration_ms": 0}]')"
    else
      # skip_reason not in allowlist → unverifiable (observe mode: log warn, count as unverifiable)
      echo "WARN: check ${check_id} skip_reason '${policy_skip_reason}' not in allowlist — counting as unverifiable" >&2
      COUNT_UNVERIFIABLE=$(( COUNT_UNVERIFIABLE + 1 ))
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg reason "invalid_skip_reason:${policy_skip_reason}" \
        '. + [{"id": $id, "name": $name, "status": "unverifiable", "skip_reason": $reason, "output_preview": "", "duration_ms": 0}]')"
    fi
    return
  fi

  # -------------------------------------------------------------------------
  # 5. Find check script
  # -------------------------------------------------------------------------
  # Determine script filename: dg<N>-<name>.sh (e.g. dg01-dependency-consistency.sh)
  local check_script="${CHECK_SCRIPT_DIR}/${check_id}-${check_name}.sh"

  if [[ ! -f "$check_script" ]]; then
    COUNT_UNVERIFIABLE=$(( COUNT_UNVERIFIABLE + 1 ))
    CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
      --arg id "$check_id" \
      --arg name "$check_name" \
      '. + [{"id": $id, "name": $name, "status": "unverifiable", "skip_reason": "check_script_missing", "output_preview": "", "duration_ms": 0}]')"
    return
  fi

  # -------------------------------------------------------------------------
  # 6. If no argv after policy resolution and check script exists → run script
  #    with no args (script handles its own logic, e.g. dg07 state-consistency)
  # -------------------------------------------------------------------------

  # -------------------------------------------------------------------------
  # 7. Execute the check script (argv array, no eval, no shell expansion)
  # -------------------------------------------------------------------------
  local check_output
  local check_exit=0

  # Build the full command: script + argv array
  # Use timeout for safety (default 120s)
  local timeout_seconds=120

  local _t_start _t_end duration_ms
  _t_start=$(date +%s%3N 2>/dev/null || date +%s)
  check_output="$(AID_PROJECT_ROOT="$PROJECT_ROOT" \
    AID_EPIC_ID="$EPIC_ID" \
    AID_RUN_ID="$RUN_ID" \
    AID_BASE_SHA="$BASE_SHA" \
    AID_CHANGED_PATHS="${CHANGED_PATHS_FILE:-}" \
    timeout "$timeout_seconds" \
    "$check_script" "${check_argv[@]}" 2>&1)" || check_exit=$?
  _t_end=$(date +%s%3N 2>/dev/null || date +%s)
  duration_ms=$(( _t_end - _t_start ))

  # Truncate output_preview to OUTPUT_PREVIEW_LINES lines
  local output_preview
  output_preview="$(echo "$check_output" | head -n "$OUTPUT_PREVIEW_LINES")"

  # Map exit codes: 0=pass, 1=fail, 2=unverifiable, 124=timeout→unverifiable
  case "$check_exit" in
    0)
      COUNT_PASS=$(( COUNT_PASS + 1 ))
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg preview "$output_preview" \
        --argjson dur "$duration_ms" \
        '. + [{"id": $id, "name": $name, "status": "pass", "skip_reason": "", "output_preview": $preview, "duration_ms": $dur}]')"
      ;;
    1)
      COUNT_FAIL=$(( COUNT_FAIL + 1 ))
      DELIVERY_READY=false
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg preview "$output_preview" \
        --argjson dur "$duration_ms" \
        '. + [{"id": $id, "name": $name, "status": "fail", "skip_reason": "", "output_preview": $preview, "duration_ms": $dur}]')"
      ;;
    124)
      # timeout
      COUNT_UNVERIFIABLE=$(( COUNT_UNVERIFIABLE + 1 ))
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg preview "check timed out after ${timeout_seconds}s" \
        --argjson dur "$duration_ms" \
        '. + [{"id": $id, "name": $name, "status": "unverifiable", "skip_reason": "check_timeout", "output_preview": $preview, "duration_ms": $dur}]')"
      ;;
    *)
      # exit 2 or other → unverifiable
      COUNT_UNVERIFIABLE=$(( COUNT_UNVERIFIABLE + 1 ))
      local skip_reason_exit="check_exit_${check_exit}"
      CHECKS_JSON="$(echo "$CHECKS_JSON" | jq \
        --arg id "$check_id" \
        --arg name "$check_name" \
        --arg reason "$skip_reason_exit" \
        --arg preview "$output_preview" \
        --argjson dur "$duration_ms" \
        '. + [{"id": $id, "name": $name, "status": "unverifiable", "skip_reason": $reason, "output_preview": $preview, "duration_ms": $dur}]')"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
for _check_id in "${CHECKS[@]}"; do
  _run_check "$_check_id"
done

# ---------------------------------------------------------------------------
# Compute delivery_ready
# ---------------------------------------------------------------------------

# Stale HEAD → delivery_ready: false
if [[ "$DG_FRESHNESS" == "stale" ]]; then
  DELIVERY_READY=false
fi

# Profile unverifiable → delivery_ready: false
if [[ "$PROFILE" == "unverifiable" ]]; then
  DELIVERY_READY=false
fi

# Any fail → delivery_ready: false (already set in loop)

# Unverifiable + block_on_unverifiable → delivery_ready: false
if [[ "$BLOCK_ON_UNVERIFIABLE" == "true" && "$COUNT_UNVERIFIABLE" -gt 0 ]]; then
  DELIVERY_READY=false
fi

# Compute would_block: in observe mode would_block reflects what would happen if enforcement were active
WOULD_BLOCK=false
if [[ "$DELIVERY_READY" == "false" ]]; then
  WOULD_BLOCK=true
fi

# Compute outer status: pass if delivery_ready, else fail (for the envelope)
if [[ "$DELIVERY_READY" == "true" ]]; then
  STATUS="pass"
else
  STATUS="fail"
fi

# ---------------------------------------------------------------------------
# Build findings[] array from fail/unverifiable checks
#
# jq has no sha256 builtin, so fingerprints are computed per-entry in bash.
# Strategy: extract [id, status, name] tuples from CHECKS_JSON (one JSON array
# per line), iterate in a bash while loop, compute sha256 fingerprint, and
# accumulate a findings JSON array.
# ---------------------------------------------------------------------------
FINDINGS_JSON="[]"
while IFS= read -r tuple; do
  [[ -z "$tuple" ]] && continue

  _f_id="$(echo "$tuple" | jq -r '.[0]')"
  _f_status="$(echo "$tuple" | jq -r '.[1]')"
  _f_name="$(echo "$tuple" | jq -r '.[2]')"

  if [[ "$_f_status" == "fail" ]]; then
    _severity="high"
    _finding_class="delivery_gate_fail"
    _action_owner="gate-fixer"
  else
    _severity="medium"
    _finding_class="delivery_gate_unverifiable"
    _action_owner="reviewer"
  fi

  # Canonical fingerprint: sha256(project_id \x1f artifact_type \x1f check_id \x1f target_path \x1f finding_class)
  # Must match lib/aid-finding-fingerprint.sh fingerprint() so --check-fingerprint validates
  _fp_hex="$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' \
    "$PROJECT_ID" "delivery_gate" "$_f_id" "" "$_finding_class" \
    | sha256sum | cut -d' ' -f1 | cut -c1-64)"
  _fingerprint="sha256:${_fp_hex}"
  _occurrence_id="$(printf '%s:%s:%s' "$RUN_ID" "$_f_id" "${_fp_hex:0:12}")"

  _entry="$(jq -n \
    --arg fingerprint "$_fingerprint" \
    --arg occurrence_id "$_occurrence_id" \
    --arg severity "$_severity" \
    --arg check_id "$_f_id" \
    --arg finding_class "$_finding_class" \
    --arg description "${_f_id} ${_f_name}: status=${_f_status}" \
    --arg action_owner "$_action_owner" \
    '{
      "fingerprint": $fingerprint,
      "occurrence_id": $occurrence_id,
      "severity": $severity,
      "check_id": $check_id,
      "target_path": "",
      "finding_class": $finding_class,
      "description": $description,
      "action_owner": $action_owner
    }')"

  FINDINGS_JSON="$(echo "$FINDINGS_JSON" | jq --argjson entry "$_entry" '. + [$entry]')"
done < <(echo "$CHECKS_JSON" | jq -c \
  '.[] | select(.status == "fail" or .status == "unverifiable") | [.id, .status, .name]' \
  2>/dev/null)

# Fallback: ensure valid JSON array
if ! echo "$FINDINGS_JSON" | jq -e '. | arrays' >/dev/null 2>&1; then
  FINDINGS_JSON="[]"
fi

# ---------------------------------------------------------------------------
# Build JSON without subject_hash first (for hashing)
# ---------------------------------------------------------------------------
CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Build the delivery_gate payload object for hashing
DG_PAYLOAD_FOR_HASH="$(jq -n \
  --arg phase "$PHASE" \
  --arg profile "$PROFILE" \
  --arg freshness "$DG_FRESHNESS" \
  --argjson delivery_ready "$DELIVERY_READY" \
  --argjson checks "$CHECKS_JSON" \
  --argjson total "$COUNT_TOTAL" \
  --argjson pass_count "$COUNT_PASS" \
  --argjson fail_count "$COUNT_FAIL" \
  --argjson skip_count "$COUNT_SKIP" \
  --argjson unverifiable_count "$COUNT_UNVERIFIABLE" \
  --argjson would_block "$WOULD_BLOCK" \
  '{
    "phase": $phase,
    "profile": $profile,
    "freshness": $freshness,
    "delivery_ready": $delivery_ready,
    "checks": $checks,
    "summary": {
      "total": $total,
      "pass": $pass_count,
      "fail": $fail_count,
      "skip": $skip_count,
      "unverifiable": $unverifiable_count,
      "would_block": $would_block
    }
  }')"

# Compute subject_hash from the delivery_gate payload
CONTENT_FOR_HASH="$(echo -n "$DG_PAYLOAD_FOR_HASH" | sha256sum | cut -d' ' -f1)"
SUBJECT_HASH="sha256:${CONTENT_FOR_HASH}"

# ---------------------------------------------------------------------------
# Build final protocol-v2 JSON
# ---------------------------------------------------------------------------
FINAL_JSON="$(jq -n \
  --arg schema_version "$SCHEMA_VERSION" \
  --arg artifact_type "delivery_gate" \
  --arg producer "$PRODUCER" \
  --arg created_at "$CREATED_AT" \
  --arg control_protocol "$CONTROL_PROTOCOL" \
  --arg project_id "$PROJECT_ID" \
  --arg epic_id "$EPIC_ID" \
  --arg run_id "$RUN_ID" \
  --arg subject_hash "$SUBJECT_HASH" \
  --arg head_sha "$HEAD_SHA" \
  --arg base_sha "$BASE_SHA" \
  --arg head_is_current "$HEAD_IS_CURRENT" \
  --arg revision_freshness "$REVISION_FRESHNESS" \
  --arg status "$STATUS" \
  --argjson delivery_ready "$DELIVERY_READY" \
  --arg generated_by_tool "aid-delivery-gate" \
  --argjson delivery_gate_payload "$DG_PAYLOAD_FOR_HASH" \
  --argjson findings "$FINDINGS_JSON" \
  '{
    "schema_version": $schema_version,
    "artifact_type": $artifact_type,
    "producer": $producer,
    "created_at": $created_at,
    "control_protocol": $control_protocol,
    "identity": {
      "project_id": $project_id,
      "epic_id": $epic_id,
      "run_id": $run_id
    },
    "subject": {
      "subject_hash": $subject_hash
    },
    "revision": {
      "head_sha": $head_sha,
      "base_sha": $base_sha,
      "head_is_current": ($head_is_current == "true"),
      "freshness": $revision_freshness
    },
    "status": $status,
    "verdict": {
      "kind": "delivery_ready",
      "value": $delivery_ready
    },
    "provenance": {
      "dispatch_mode": "deterministic",
      "generated_by_tool": $generated_by_tool
    },
    "findings": $findings,
    "delivery_gate": $delivery_gate_payload
  }')"

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
if ! echo "$FINAL_JSON" > "$OUTPUT_FILE"; then
  echo "ERROR: cannot write output to: ${OUTPUT_FILE}" >&2
  exit 1
fi

# Report summary to stdout
echo "delivery-gate: ${EPIC_ID}/${RUN_ID} profile=${PROFILE} phase=${PHASE} freshness=${DG_FRESHNESS} delivery_ready=${DELIVERY_READY}"
echo "  checks: total=${COUNT_TOTAL} pass=${COUNT_PASS} fail=${COUNT_FAIL} skip=${COUNT_SKIP} unverifiable=${COUNT_UNVERIFIABLE}"
echo "  output: ${OUTPUT_FILE}"

# Dispatcher always exits 0 in observe mode (delivery_ready=false is in the JSON)
exit 0
