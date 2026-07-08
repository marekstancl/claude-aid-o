#!/usr/bin/env bash
# aid-invalidation-map.sh — E8 D3: observe-only invalidation-map producer
#
# Given an applied fix's changed paths, derives:
#   - affected_c1_checks[]  — deterministic subset of delivery-gate.yaml checks
#                             (only checks whose required_when declares
#                             changed_paths_match) whose glob(s) matched at
#                             least one changed path.
#   - affected_c2_modes[]   — conservative: ANY changed path matching a
#                             C2-relevant surface (review-profiles.yaml surface
#                             with a non-empty lenses[]) marks ALL canonical C2
#                             modes (local, wiring, behavior, final) as
#                             affected. There is no real substrate today for
#                             precise path-to-mode derivation (E8 D3) — this
#                             script is honest about that instead of
#                             pretending precision it can't deliver.
#
# Emits invalidation-map.json (protocol-v2 envelope) to the evidence dir and a
# timeline log_event. Observe-only: this script NEVER invokes delivery-gate,
# semantic-review, or any other stage — it only records a request/flag
# (require_rerun) for a human/PM to act on later.
#
# NOTE on reuse: aid-delivery-gate.sh's `_check_applicable` / `_changed_paths_match`
# are NOT sourced or called here — they are private functions inside a 900+ line
# executable script, not designed to be reused (explicit L2 fix, plan P057 D3).
# This script instead reads the changed_paths_match globs directly from
# delivery-gate.yaml via yq and re-implements the same bash case-glob matching
# approach (glob semantics reused, not the function).
#
# Usage:
#   aid-invalidation-map.sh --fix-ref <ref> --evidence-dir <path> \
#                            --changed-paths <file> [--out <path>]
#
# Options:
#   --fix-ref <ref>         Identifier for the applied fix (commit sha,
#                            gate-fixer iteration label, or any caller-supplied
#                            string). Opaque — stored verbatim.
#   --evidence-dir <path>   Run evidence directory. invalidation-map.json and
#                            the timeline event are written here by default.
#   --changed-paths <file>  File with one changed path per line (same
#                            convention as aid-delivery-gate.sh --changed-paths).
#   --out <path>             Optional explicit output path (default:
#                            <evidence-dir>/invalidation-map.json).
#
# Environment:
#   DELIVERY_GATE_POLICY   — overrides default delivery-gate.yaml path (test/CI
#                            override, same convention as aid-delivery-gate.sh)
#   REVIEW_PROFILE_POLICY  — overrides default review-profiles.yaml path
#                            (test/CI override, same convention as aid-fsm.sh)
#
# Exit codes:
#   0 — artifact written (including fail-safe degraded reads of policy files)
#   1 — usage error (missing required args, changed-paths file not found)
#
# Constraints:
#   - No new runtime dependency beyond bash/jq/yq/git.
#   - Never invokes aid-delivery-gate.sh, aid-run-gates.sh, or any
#     semantic-review dispatch — observe-only, zero side effects beyond its
#     own artifact + timeline event.
#
# **Last Updated:** 2026-07-08

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-stage-log.sh
source "${SCRIPT_DIR}/aid-stage-log.sh"

PRODUCER="aid-invalidation-map.sh@2.51.0"

# Canonical C2 mode catalog (agents/verifier.md c2_mode: local|wiring|behavior|final).
# Fixed list — conservative derivation marks ALL of these when any C2-relevant
# surface is touched (D3: no per-mode path derivation exists today).
readonly C2_MODES=(local wiring behavior final)

usage() {
  cat <<EOF
Usage: aid-invalidation-map.sh --fix-ref <ref> --evidence-dir <path> --changed-paths <file> [--out <path>]
EOF
}

FIX_REF=""
EVIDENCE_DIR=""
CHANGED_PATHS_FILE=""
OUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix-ref) FIX_REF="${2:-}"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --changed-paths) CHANGED_PATHS_FILE="${2:-}"; shift 2 ;;
    --out) OUT_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$FIX_REF" || -z "$EVIDENCE_DIR" || -z "$CHANGED_PATHS_FILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$CHANGED_PATHS_FILE" ]]; then
  echo "ERROR: --changed-paths file not found: ${CHANGED_PATHS_FILE}" >&2
  exit 1
fi

mkdir -p "$EVIDENCE_DIR" 2>/dev/null || true
[[ -z "$OUT_PATH" ]] && OUT_PATH="${EVIDENCE_DIR}/invalidation-map.json"
TIMELINE_FILE="${EVIDENCE_DIR}/timeline.jsonl"

# Policy file locations — same env-override convention as aid-delivery-gate.sh
# (DELIVERY_GATE_POLICY) and aid-fsm.sh's E5 wiring-gate (REVIEW_PROFILE_POLICY).
DELIVERY_GATE_POLICY_FILE="${DELIVERY_GATE_POLICY:-${SCRIPT_DIR}/../../defaults/policies/delivery-gate.yaml}"
REVIEW_PROFILE_POLICY_FILE="${REVIEW_PROFILE_POLICY:-${SCRIPT_DIR}/../../defaults/policies/review-profiles.yaml}"

ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
_HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
_SUBJECT_HASH=$(printf '%s' "$_HEAD_SHA" | sha256sum | cut -c1-64)
_PROJECT_ID=$(grep -m1 'project_id:' "$(find "$(pwd)" -name "project.yaml" -path '*/.aid-o/config/*' 2>/dev/null | head -1)" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")

# ---------------------------------------------------------------------------
# _path_matches_any_glob <path> <glob1> [glob2...]
# Bash case-glob matching (same semantics as aid-delivery-gate.sh's
# _changed_paths_match — the glob-matching APPROACH is reused; the private
# function itself is not, per D3/L2).
# ---------------------------------------------------------------------------
_path_matches_any_glob() {
  local path="$1"; shift
  local pattern
  for pattern in "$@"; do
    [[ -z "$pattern" ]] && continue
    # shellcheck disable=SC2254 — intentional glob matching (not literal)
    case "$path" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Derive affected_c1_checks — deterministic subset (checks declaring
# changed_paths_match in delivery-gate.yaml, read directly via yq).
# ---------------------------------------------------------------------------
AFFECTED_C1_CHECKS=()

if command -v yq >/dev/null 2>&1 && [[ -f "$DELIVERY_GATE_POLICY_FILE" ]]; then
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    check_id=$(echo "$entry" | jq -r '.key')
    mapfile -t globs < <(echo "$entry" | jq -r '.globs[]')
    while IFS= read -r changed_path; do
      [[ -z "$changed_path" ]] && continue
      if _path_matches_any_glob "$changed_path" "${globs[@]}"; then
        AFFECTED_C1_CHECKS+=("$check_id")
        break
      fi
    done < "$CHANGED_PATHS_FILE"
  done < <(yq -o=json eval '.checks // {}' "$DELIVERY_GATE_POLICY_FILE" 2>/dev/null | \
    jq -c 'to_entries[] | {key: .key, globs: ([.value.required_when[]? | .changed_paths_match? // empty] | add // [])} | select(.globs | length > 0)' 2>/dev/null)
fi

# de-dup + sort (only when non-empty — an empty array through printf|sort would
# otherwise become a 1-element array containing an empty string)
if [[ ${#AFFECTED_C1_CHECKS[@]} -gt 0 ]]; then
  mapfile -t AFFECTED_C1_CHECKS < <(printf '%s\n' "${AFFECTED_C1_CHECKS[@]}" | sort -u)
fi

# ---------------------------------------------------------------------------
# Derive affected_c2_modes — conservative (any C2-relevant surface touched →
# ALL canonical C2 modes).
# ---------------------------------------------------------------------------
C2_TOUCHED=0

if command -v yq >/dev/null 2>&1 && [[ -f "$REVIEW_PROFILE_POLICY_FILE" ]]; then
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    mapfile -t globs < <(echo "$entry" | jq -r '.globs[]')
    while IFS= read -r changed_path; do
      [[ -z "$changed_path" ]] && continue
      if _path_matches_any_glob "$changed_path" "${globs[@]}"; then
        C2_TOUCHED=1
        break
      fi
    done < "$CHANGED_PATHS_FILE"
    [[ "$C2_TOUCHED" -eq 1 ]] && break
  done < <(yq -o=json eval '.surfaces // {}' "$REVIEW_PROFILE_POLICY_FILE" 2>/dev/null | \
    jq -c 'to_entries[] | select((.value.lenses // []) | length > 0) | {key: .key, globs: (.value.match.path_globs // [])}' 2>/dev/null)
fi

AFFECTED_C2_MODES=()
if [[ "$C2_TOUCHED" -eq 1 ]]; then
  AFFECTED_C2_MODES=("${C2_MODES[@]}")
fi

# ---------------------------------------------------------------------------
# require_rerun — true iff something was actually flagged. A REQUEST, never
# an auto-trigger: this script does not, and must not, invoke delivery-gate
# or semantic-review itself.
# ---------------------------------------------------------------------------
REQUIRE_RERUN="false"
if [[ ${#AFFECTED_C1_CHECKS[@]} -gt 0 || ${#AFFECTED_C2_MODES[@]} -gt 0 ]]; then
  REQUIRE_RERUN="true"
fi

# ---------------------------------------------------------------------------
# Emit invalidation-map.json (protocol-v2 envelope)
# ---------------------------------------------------------------------------
C1_JSON=$(printf '%s\n' "${AFFECTED_C1_CHECKS[@]}" | jq -R 'select(length > 0)' | jq -s '.')
C2_JSON=$(printf '%s\n' "${AFFECTED_C2_MODES[@]}" | jq -R 'select(length > 0)' | jq -s '.')

jq -n \
  --arg schema_version "aid-2.0" \
  --arg artifact_type "invalidation_map" \
  --arg producer "$PRODUCER" \
  --arg created_at "$ISO_NOW" \
  --arg control_protocol "aid-2.0" \
  --arg project_id "${_PROJECT_ID:-unknown}" \
  --arg subject_hash "sha256:${_SUBJECT_HASH}" \
  --arg head_sha "${_HEAD_SHA}" \
  --arg fix_ref "$FIX_REF" \
  --argjson c1 "$C1_JSON" \
  --argjson c2 "$C2_JSON" \
  --argjson require_rerun "$REQUIRE_RERUN" \
  '{
    schema_version: $schema_version,
    artifact_type: $artifact_type,
    producer: $producer,
    created_at: $created_at,
    control_protocol: $control_protocol,
    identity: {project_id: $project_id},
    subject: {subject_hash: $subject_hash},
    revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
    status: "pass",
    verdict: {kind: "none", ready: false},
    provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-invalidation-map.sh"},
    invalidation_map: {
      applied_fix_ref: $fix_ref,
      affected_c1_checks: $c1,
      affected_c2_modes: $c2,
      require_rerun: $require_rerun
    }
  }' > "$OUT_PATH"

# ---------------------------------------------------------------------------
# Timeline event (observe — never blocks, never triggers a re-run)
# ---------------------------------------------------------------------------
log_event "$TIMELINE_FILE" "invalidation_map_produced" \
  fix_ref="$FIX_REF" \
  c1_count="${#AFFECTED_C1_CHECKS[@]}" \
  c2_count="${#AFFECTED_C2_MODES[@]}" \
  require_rerun="$REQUIRE_RERUN" || true

exit 0
