#!/usr/bin/env bash
# aid-evidence-verify.sh — AID evidence pack verifier (Step 2: core checks)
#
# Usage: aid-evidence-verify.sh [<epic_id> <run_id>] [--out <path>] [--at-head]
#
# Verifies git cleanliness, locates the canonical evidence pack, and validates
# every protocol-v2 artifact for freshness, protocol conformance, and fingerprint.
#
# Exit codes:
#   0  — all checks pass
#   1  — one or more checks failed or are unverifiable
#   2  — usage error

set -uo pipefail

# ---------------------------------------------------------------------------
# Script location — used to resolve peer scripts (no eval)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="${SCRIPT_DIR}/aid-protocol-validate.sh"
TTL_GUARD="${SCRIPT_DIR}/aid-registry-ttl-guard.sh"

# ---------------------------------------------------------------------------
# Check result variables (populated by run_* functions)
# ---------------------------------------------------------------------------
CHECK_git_clean_STATUS="skip"
CHECK_git_clean_DETAIL=""
CHECK_git_clean_EVIDENCE=""

CHECK_evidence_pack_found_STATUS="skip"
CHECK_evidence_pack_found_DETAIL=""
CHECK_evidence_pack_found_EVIDENCE=""

CHECK_artifact_head_freshness_STATUS="skip"
CHECK_artifact_head_freshness_DETAIL=""
CHECK_artifact_head_freshness_EVIDENCE=""

CHECK_protocol_validate_STATUS="skip"
CHECK_protocol_validate_DETAIL=""
CHECK_protocol_validate_EVIDENCE=""

CHECK_fingerprint_STATUS="skip"
CHECK_fingerprint_DETAIL=""
CHECK_fingerprint_EVIDENCE=""

CHECK_ttl_registry_STATUS=""
CHECK_ttl_registry_DETAIL=""
CHECK_ttl_registry_EVIDENCE=""

CHECK_observe_blocking_interpretation_STATUS=""
CHECK_observe_blocking_interpretation_DETAIL=""
CHECK_observe_blocking_interpretation_EVIDENCE=""

PACK_HEAD=""
EVIDENCE_DIR=""
EPIC_ID=""
RUN_ID=""
CURRENT_HEAD=""

VALIDATOR_MISSING=false
AT_HEAD_MODE=false
OUT_PATH=""

# Internal: v2 artifact list (populated by run_pack_discovery)
V2_ARTIFACTS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Severity ordering for worst-result aggregation: fail > unverifiable > pass > skip
# Returns 0 if $1 is "worse" than $2
_is_worse() {
  local a="$1" b="$2"
  _rank() {
    case "$1" in
      fail)          echo 4 ;;
      unverifiable)  echo 3 ;;
      pass)          echo 2 ;;
      skip)          echo 1 ;;
      *)             echo 0 ;;
    esac
  }
  [[ "$(_rank "$a")" -gt "$(_rank "$b")" ]]
}

# Merge new status into existing worst
_merge_status() {
  local current="$1" incoming="$2"
  if _is_worse "$incoming" "$current"; then
    echo "$incoming"
  else
    echo "$current"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing (no eval)
# ---------------------------------------------------------------------------
parse_args() {
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        if [[ $# -lt 2 ]]; then
          echo "aid-evidence-verify: --out requires a path argument" >&2
          exit 2
        fi
        OUT_PATH="$2"
        shift 2
        ;;
      --at-head)
        AT_HEAD_MODE=true
        shift
        ;;
      -*)
        echo "aid-evidence-verify: unknown option: $1" >&2
        echo "Usage: aid-evidence-verify.sh [<epic_id> <run_id>] [--out <path>] [--at-head]" >&2
        exit 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  case "${#positional[@]}" in
    0)
      # auto-detect
      ;;
    2)
      EPIC_ID="${positional[0]}"
      RUN_ID="${positional[1]}"
      ;;
    *)
      echo "aid-evidence-verify: expected 0 or 2 positional args (epic_id run_id), got ${#positional[@]}" >&2
      echo "Usage: aid-evidence-verify.sh [<epic_id> <run_id>] [--out <path>] [--at-head]" >&2
      exit 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Root resolution (canonical pattern per task spec)
# ---------------------------------------------------------------------------
resolve_root() {
  if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
    ROOT="$AID_PROJECT_ROOT"
  else
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="."
  fi
  export ROOT
}

# ---------------------------------------------------------------------------
# Check 1: git_clean
# ---------------------------------------------------------------------------
run_git_clean_check() {
  local git_output
  git_output=$(git -C "$ROOT" status --porcelain 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    CHECK_git_clean_STATUS="unverifiable"
    CHECK_git_clean_DETAIL="git status failed (not a git repo or git unavailable)"
    CHECK_git_clean_EVIDENCE="$git_output"
    return
  fi

  if [[ -z "$git_output" ]]; then
    CHECK_git_clean_STATUS="pass"
    CHECK_git_clean_DETAIL="working tree is clean"
  else
    CHECK_git_clean_STATUS="fail"
    CHECK_git_clean_DETAIL="working tree has uncommitted changes"
    CHECK_git_clean_EVIDENCE="$git_output"
  fi
}

# ---------------------------------------------------------------------------
# Check 2: evidence_pack_found + v2 artifact enumeration
# ---------------------------------------------------------------------------
run_pack_discovery() {
  local evidence_base="$ROOT/.aid-o/work/evidence"

  if [[ -n "$EPIC_ID" && -n "$RUN_ID" ]]; then
    # Explicit epic/run provided
    EVIDENCE_DIR="${evidence_base}/${EPIC_ID}/${RUN_ID}"
    if [[ ! -d "$EVIDENCE_DIR" ]]; then
      CHECK_evidence_pack_found_STATUS="fail"
      CHECK_evidence_pack_found_DETAIL="evidence directory not found: $EVIDENCE_DIR"
      return
    fi
    echo "aid-evidence-verify: using evidence pack: ${EPIC_ID}/${RUN_ID}" >&2
  else
    # Auto-detect: find most recent run subdir with fsm-state.yaml, sorted by mtime
    if [[ ! -d "$evidence_base" ]]; then
      CHECK_evidence_pack_found_STATUS="fail"
      CHECK_evidence_pack_found_DETAIL="evidence base directory not found: $evidence_base"
      return
    fi

    local best_dir="" best_mtime=0
    # Find all fsm-state.yaml files (depth 3 from evidence base: epic_id/run_id/fsm-state.yaml)
    while IFS= read -r -d '' state_file; do
      local run_dir
      run_dir="$(dirname "$state_file")"
      local mtime
      mtime=$(stat -c "%Y" "$state_file" 2>/dev/null) || continue
      if [[ "$mtime" -gt "$best_mtime" ]]; then
        best_mtime="$mtime"
        best_dir="$run_dir"
      fi
    done < <(find "$evidence_base" -mindepth 3 -maxdepth 3 -name "fsm-state.yaml" -print0 2>/dev/null)

    if [[ -z "$best_dir" ]]; then
      CHECK_evidence_pack_found_STATUS="fail"
      CHECK_evidence_pack_found_DETAIL="no evidence packs found under $evidence_base"
      echo "aid-evidence-verify: no evidence packs found" >&2
      return
    fi

    EVIDENCE_DIR="$best_dir"
    # Extract epic_id and run_id from path
    local rel_path="${EVIDENCE_DIR#${evidence_base}/}"
    RUN_ID="${rel_path##*/}"
    EPIC_ID="${rel_path%/*}"
    echo "aid-evidence-verify: auto-selected evidence pack: ${EPIC_ID}/${RUN_ID}" >&2
  fi

  # Find all *.json in pack dir
  local json_files=()
  while IFS= read -r -d '' jf; do
    json_files+=("$jf")
  done < <(find "$EVIDENCE_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null)

  # Also look one level deeper (e.g. gates/)
  while IFS= read -r -d '' jf; do
    json_files+=("$jf")
  done < <(find "$EVIDENCE_DIR" -mindepth 2 -maxdepth 2 -name "*.json" -print0 2>/dev/null)

  if [[ "${#json_files[@]}" -eq 0 ]]; then
    CHECK_evidence_pack_found_STATUS="fail"
    CHECK_evidence_pack_found_DETAIL="evidence directory contains no JSON files"
    return
  fi

  # Filter to v2 artifacts (schema_version == "aid-2.0", control_protocol != "legacy")
  local found_v2=false
  for jf in "${json_files[@]}"; do
    local sv cp
    sv=$(jq -r '.schema_version // ""' "$jf" 2>/dev/null) || continue
    cp=$(jq -r '.control_protocol // ""' "$jf" 2>/dev/null) || continue
    if [[ "$sv" == "aid-2.0" && "$cp" != "legacy" ]]; then
      V2_ARTIFACTS+=("$jf")
      found_v2=true
    fi
  done

  if ! $found_v2; then
    CHECK_evidence_pack_found_STATUS="unverifiable"
    CHECK_evidence_pack_found_DETAIL="evidence pack exists but contains no v2 artifacts"
    CHECK_evidence_pack_found_EVIDENCE="reason: no_v2_artifacts"
    return
  fi

  CHECK_evidence_pack_found_STATUS="pass"
  CHECK_evidence_pack_found_DETAIL="found ${#V2_ARTIFACTS[@]} v2 artifact(s) in ${EVIDENCE_DIR}"
}

# ---------------------------------------------------------------------------
# Check 3: artifact_head_freshness
# ---------------------------------------------------------------------------
run_freshness_check() {
  # Skip if pack discovery failed
  if [[ "$CHECK_evidence_pack_found_STATUS" != "pass" ]]; then
    CHECK_artifact_head_freshness_STATUS="skip"
    CHECK_artifact_head_freshness_DETAIL="skipped — evidence pack not found"
    return
  fi

  if [[ "${#V2_ARTIFACTS[@]}" -eq 0 ]]; then
    CHECK_artifact_head_freshness_STATUS="skip"
    CHECK_artifact_head_freshness_DETAIL="skipped — no v2 artifacts"
    return
  fi

  # Resolve current HEAD
  CURRENT_HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || {
    CHECK_artifact_head_freshness_STATUS="unverifiable"
    CHECK_artifact_head_freshness_DETAIL="git rev-parse HEAD failed"
    return
  }

  # Collect head_sha from each v2 artifact
  local seen_heads=()
  for artifact in "${V2_ARTIFACTS[@]}"; do
    local head_sha
    head_sha=$(jq -r '.revision.head_sha // ""' "$artifact" 2>/dev/null)
    if [[ -z "$head_sha" ]]; then
      CHECK_artifact_head_freshness_STATUS="fail"
      CHECK_artifact_head_freshness_DETAIL="artifact missing revision.head_sha"
      CHECK_artifact_head_freshness_EVIDENCE="artifact: $artifact"
      return
    fi
    # Check if already seen
    local already_seen=false
    for h in "${seen_heads[@]+"${seen_heads[@]}"}"; do
      if [[ "$h" == "$head_sha" ]]; then
        already_seen=true
        break
      fi
    done
    if ! $already_seen; then
      seen_heads+=("$head_sha")
    fi
  done

  # All artifacts must share one single pack_head
  if [[ "${#seen_heads[@]}" -gt 1 ]]; then
    CHECK_artifact_head_freshness_STATUS="fail"
    CHECK_artifact_head_freshness_DETAIL="artifacts have inconsistent head_sha values"
    CHECK_artifact_head_freshness_EVIDENCE="reason: head_sha_inconsistent, values: ${seen_heads[*]}"
    return
  fi

  PACK_HEAD="${seen_heads[0]}"

  # Verify pack_head is a real, reachable commit
  if ! git -C "$ROOT" cat-file -e "${PACK_HEAD}^{commit}" 2>/dev/null; then
    CHECK_artifact_head_freshness_STATUS="fail"
    CHECK_artifact_head_freshness_DETAIL="pack_head is not a known commit object"
    CHECK_artifact_head_freshness_EVIDENCE="reason: divergent_stale, pack_head: $PACK_HEAD"
    return
  fi

  if ! git -C "$ROOT" merge-base --is-ancestor "$PACK_HEAD" HEAD 2>/dev/null; then
    CHECK_artifact_head_freshness_STATUS="fail"
    CHECK_artifact_head_freshness_DETAIL="pack_head is not reachable from HEAD"
    CHECK_artifact_head_freshness_EVIDENCE="reason: divergent_stale, pack_head: $PACK_HEAD, current_head: $CURRENT_HEAD"
    return
  fi

  # --at-head strict mode
  if $AT_HEAD_MODE; then
    if [[ "$PACK_HEAD" != "$CURRENT_HEAD" ]]; then
      CHECK_artifact_head_freshness_STATUS="fail"
      CHECK_artifact_head_freshness_DETAIL="--at-head mode: pack_head does not equal current HEAD"
      CHECK_artifact_head_freshness_EVIDENCE="reason: not_at_head, pack_head: $PACK_HEAD, current_head: $CURRENT_HEAD"
      return
    fi
  fi

  CHECK_artifact_head_freshness_STATUS="pass"
  CHECK_artifact_head_freshness_DETAIL="all v2 artifacts share pack_head: $PACK_HEAD"
}

# ---------------------------------------------------------------------------
# Checks 4+5: protocol_validate and fingerprint (per artifact)
# ---------------------------------------------------------------------------
run_protocol_checks() {
  # Skip if pack not found
  if [[ "$CHECK_evidence_pack_found_STATUS" != "pass" ]]; then
    CHECK_protocol_validate_STATUS="skip"
    CHECK_protocol_validate_DETAIL="skipped — evidence pack not found"
    CHECK_fingerprint_STATUS="skip"
    CHECK_fingerprint_DETAIL="skipped — evidence pack not found"
    return
  fi

  if [[ "${#V2_ARTIFACTS[@]}" -eq 0 ]]; then
    CHECK_protocol_validate_STATUS="skip"
    CHECK_protocol_validate_DETAIL="skipped — no v2 artifacts"
    CHECK_fingerprint_STATUS="skip"
    CHECK_fingerprint_DETAIL="skipped — no v2 artifacts"
    return
  fi

  # Check if validator is available
  if [[ ! -f "$VALIDATOR" ]]; then
    VALIDATOR_MISSING=true
    CHECK_protocol_validate_STATUS="unverifiable"
    CHECK_protocol_validate_DETAIL="validator not found: $VALIDATOR"
    CHECK_protocol_validate_EVIDENCE="reason: validator_missing"
    CHECK_fingerprint_STATUS="unverifiable"
    CHECK_fingerprint_DETAIL="validator not found: $VALIDATOR"
    CHECK_fingerprint_EVIDENCE="reason: validator_missing"
    return
  fi

  # Determine the head to pass to --current-head
  local head_arg=""
  if [[ -n "$PACK_HEAD" ]]; then
    head_arg="$PACK_HEAD"
  elif [[ -n "$CURRENT_HEAD" ]]; then
    head_arg="$CURRENT_HEAD"
  fi

  local worst_pv_status="pass"
  local worst_pv_detail=""
  local worst_pv_evidence=""
  local worst_fp_status="pass"
  local worst_fp_detail=""
  local worst_fp_evidence=""

  for artifact in "${V2_ARTIFACTS[@]}"; do
    local artifact_name
    artifact_name="$(basename "$artifact")"

    # --- protocol_validate ---
    local pv_exit pv_status pv_detail pv_evidence
    if [[ -n "$head_arg" ]]; then
      bash "$VALIDATOR" "$artifact" --current-head "$head_arg" 2>/dev/null
      pv_exit=$?
    else
      bash "$VALIDATOR" "$artifact" 2>/dev/null
      pv_exit=$?
    fi

    if [[ "$pv_exit" -eq 0 ]]; then
      pv_status="pass"
      pv_detail="protocol validation passed"
      pv_evidence=""
    else
      pv_status="fail"
      pv_detail="protocol validation failed for: $artifact_name"
      pv_evidence="exit $pv_exit"
    fi

    if _is_worse "$pv_status" "$worst_pv_status"; then
      worst_pv_status="$pv_status"
      worst_pv_detail="$pv_detail"
      worst_pv_evidence="$pv_evidence"
    fi

    # --- fingerprint ---
    local fp_exit fp_status fp_detail fp_evidence
    bash "$VALIDATOR" "$artifact" --check-fingerprint 2>/dev/null
    fp_exit=$?

    if [[ "$fp_exit" -eq 0 ]]; then
      fp_status="pass"
      fp_detail="fingerprint check passed"
      fp_evidence=""
    else
      fp_status="fail"
      fp_detail="fingerprint check failed for: $artifact_name"
      fp_evidence="exit $fp_exit"
    fi

    if _is_worse "$fp_status" "$worst_fp_status"; then
      worst_fp_status="$fp_status"
      worst_fp_detail="$fp_detail"
      worst_fp_evidence="$fp_evidence"
    fi
  done

  CHECK_protocol_validate_STATUS="$worst_pv_status"
  CHECK_protocol_validate_DETAIL="$worst_pv_detail"
  CHECK_protocol_validate_EVIDENCE="$worst_pv_evidence"
  CHECK_fingerprint_STATUS="$worst_fp_status"
  CHECK_fingerprint_DETAIL="$worst_fp_detail"
  CHECK_fingerprint_EVIDENCE="$worst_fp_evidence"
}

# ---------------------------------------------------------------------------
# Check 6: ttl_registry
# ---------------------------------------------------------------------------
run_ttl_registry_check() {
  if [[ ! -x "$TTL_GUARD" ]]; then
    CHECK_ttl_registry_STATUS="unverifiable"
    CHECK_ttl_registry_DETAIL="aid-registry-ttl-guard.sh not found or not executable"
    CHECK_ttl_registry_EVIDENCE=""
    return
  fi

  local output exit_code
  output=$("$TTL_GUARD" 2>&1) && exit_code=0 || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    CHECK_ttl_registry_STATUS="pass"
    CHECK_ttl_registry_DETAIL="registry TTL guard passed"
    CHECK_ttl_registry_EVIDENCE=""
  elif [[ $exit_code -eq 2 ]]; then
    CHECK_ttl_registry_STATUS="unverifiable"
    CHECK_ttl_registry_DETAIL="registry not found or not readable"
    CHECK_ttl_registry_EVIDENCE="exit 2"
  else
    CHECK_ttl_registry_STATUS="fail"
    CHECK_ttl_registry_DETAIL="TTL violation: one or more planned rows are past deadline without deferral"
    CHECK_ttl_registry_EVIDENCE="exit $exit_code: $output"
  fi
}

# ---------------------------------------------------------------------------
# Check 7: observe_blocking_interpretation
# ---------------------------------------------------------------------------
run_observe_blocking_check() {
  local dg_file="$EVIDENCE_DIR/delivery-gate.json"

  if [[ ! -f "$dg_file" ]]; then
    CHECK_observe_blocking_interpretation_STATUS="skip"
    CHECK_observe_blocking_interpretation_DETAIL="no delivery-gate.json in evidence pack"
    CHECK_observe_blocking_interpretation_EVIDENCE=""
    return
  fi

  # Read fields with jq — use has() for presence check, separate read for raw value
  # IMPORTANT: enforcement field may be ABSENT (not just null). Check with has().
  # IMPORTANT: would_block may be false (bool), so use has() not //, which treats false as falsy.
  local has_enforcement enforcement has_would_block would_block_raw
  has_enforcement=$(jq '.delivery_gate.summary | has("enforcement")' "$dg_file" 2>/dev/null) || has_enforcement="false"
  enforcement=$(jq -r '.delivery_gate.summary.enforcement // "null"' "$dg_file" 2>/dev/null) || enforcement="null"
  has_would_block=$(jq '.delivery_gate.summary | has("would_block")' "$dg_file" 2>/dev/null) || has_would_block="false"
  would_block_raw=$(jq -r '.delivery_gate.summary.would_block' "$dg_file" 2>/dev/null) || would_block_raw="null"

  # Rule 1: enforcement key MUST be present AND not null
  if [[ "$has_enforcement" != "true" || "$enforcement" == "null" ]]; then
    CHECK_observe_blocking_interpretation_STATUS="fail"
    CHECK_observe_blocking_interpretation_DETAIL="enforcement key absent or null in delivery_gate.summary (expected: observe|dual_run|blocking)"
    CHECK_observe_blocking_interpretation_EVIDENCE="has_enforcement=$has_enforcement enforcement=$enforcement"
    return
  fi

  # Rule 2: enforcement must be a valid value
  case "$enforcement" in
    observe|dual_run|blocking) ;;  # valid
    *)
      CHECK_observe_blocking_interpretation_STATUS="fail"
      CHECK_observe_blocking_interpretation_DETAIL="enforcement value '$enforcement' not in {observe, dual_run, blocking}"
      CHECK_observe_blocking_interpretation_EVIDENCE="enforcement=$enforcement"
      return
      ;;
  esac

  # Rule 3: if enforcement=observe, would_block must be present (bool, not absent/null)
  if [[ "$enforcement" == "observe" ]]; then
    if [[ "$has_would_block" != "true" || "$would_block_raw" == "null" ]]; then
      CHECK_observe_blocking_interpretation_STATUS="fail"
      CHECK_observe_blocking_interpretation_DETAIL="enforcement=observe but would_block is absent/null (must be bool)"
      CHECK_observe_blocking_interpretation_EVIDENCE="has_would_block=$has_would_block would_block=$would_block_raw"
      return
    fi
  fi

  CHECK_observe_blocking_interpretation_STATUS="pass"
  CHECK_observe_blocking_interpretation_DETAIL="observe-vs-blocking interpretation consistent (enforcement=$enforcement, would_block=$would_block_raw)"
  CHECK_observe_blocking_interpretation_EVIDENCE=""
}

# ---------------------------------------------------------------------------
# Summary print (minimal for Step 2 — Step 4 adds full JSON report)
# ---------------------------------------------------------------------------
print_check_summary() {
  echo ""
  echo "=== aid-evidence-verify results ==="
  printf "  %-35s %s\n" "git_clean:"                  "$CHECK_git_clean_STATUS"
  [[ -n "$CHECK_git_clean_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_git_clean_DETAIL"
  [[ -n "$CHECK_git_clean_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_git_clean_EVIDENCE"

  printf "  %-35s %s\n" "evidence_pack_found:"         "$CHECK_evidence_pack_found_STATUS"
  [[ -n "$CHECK_evidence_pack_found_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_evidence_pack_found_DETAIL"
  [[ -n "$CHECK_evidence_pack_found_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_evidence_pack_found_EVIDENCE"

  printf "  %-35s %s\n" "artifact_head_freshness:"     "$CHECK_artifact_head_freshness_STATUS"
  [[ -n "$CHECK_artifact_head_freshness_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_artifact_head_freshness_DETAIL"
  [[ -n "$CHECK_artifact_head_freshness_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_artifact_head_freshness_EVIDENCE"

  printf "  %-35s %s\n" "protocol_validate:"           "$CHECK_protocol_validate_STATUS"
  [[ -n "$CHECK_protocol_validate_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_protocol_validate_DETAIL"
  [[ -n "$CHECK_protocol_validate_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_protocol_validate_EVIDENCE"

  printf "  %-35s %s\n" "fingerprint:"                 "$CHECK_fingerprint_STATUS"
  [[ -n "$CHECK_fingerprint_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_fingerprint_DETAIL"
  [[ -n "$CHECK_fingerprint_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_fingerprint_EVIDENCE"

  printf "  %-35s %s\n" "ttl_registry:"                "$CHECK_ttl_registry_STATUS"
  [[ -n "$CHECK_ttl_registry_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_ttl_registry_DETAIL"
  [[ -n "$CHECK_ttl_registry_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_ttl_registry_EVIDENCE"

  printf "  %-35s %s\n" "observe_blocking_interpretation:" "$CHECK_observe_blocking_interpretation_STATUS"
  [[ -n "$CHECK_observe_blocking_interpretation_DETAIL" ]] && printf "    detail: %s\n" "$CHECK_observe_blocking_interpretation_DETAIL"
  [[ -n "$CHECK_observe_blocking_interpretation_EVIDENCE" ]] && printf "    evidence: %s\n" "$CHECK_observe_blocking_interpretation_EVIDENCE"

  if [[ -n "$PACK_HEAD" ]]; then
    echo ""
    echo "  pack_head: $PACK_HEAD"
  fi
  if [[ -n "$CURRENT_HEAD" ]]; then
    echo "  current_head: $CURRENT_HEAD"
  fi
  echo "==================================="
}

# ---------------------------------------------------------------------------
# Exit code aggregation (Step 4 will replace this with emit_report)
# ---------------------------------------------------------------------------
compute_exit_code() {
  local all_pass=true
  for status in \
    "$CHECK_git_clean_STATUS" \
    "$CHECK_evidence_pack_found_STATUS" \
    "$CHECK_artifact_head_freshness_STATUS" \
    "$CHECK_protocol_validate_STATUS" \
    "$CHECK_fingerprint_STATUS" \
    "$CHECK_ttl_registry_STATUS"
  do
    if [[ "$status" != "pass" && "$status" != "skip" ]]; then
      all_pass=false
      break
    fi
  done

  # observe_blocking_interpretation: skip (reason: no_delivery_gate) is NOT a failure
  # Any other non-pass, non-skip value is a failure
  if [[ "$CHECK_observe_blocking_interpretation_STATUS" != "pass" && \
        "$CHECK_observe_blocking_interpretation_STATUS" != "skip" ]]; then
    all_pass=false
  fi

  if $all_pass; then
    return 0
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  resolve_root

  run_git_clean_check
  run_pack_discovery
  run_freshness_check
  run_protocol_checks
  run_ttl_registry_check
  run_observe_blocking_check
  # Step 4 adds: emit_report (writes verification-report.json); replaces print_check_summary

  print_check_summary

  compute_exit_code
  exit $?
}

main "$@"
