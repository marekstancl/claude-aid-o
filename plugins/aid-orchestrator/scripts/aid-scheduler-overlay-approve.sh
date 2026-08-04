#!/usr/bin/env bash
# aid-scheduler-overlay-approve.sh — P069 Step 5.
#
# The mandatory, PM-invoked approval gate for scheduler-parallel-overlay.schema.json
# (mirroring P066's aid-test-catalog-approve.sh + aid-test-catalog-confirm-mapping.sh
# pattern, never a novel mechanism): displays every NEWLY proposed promotion as
# a reviewable diff with a reviewed_diff_hash; only a matching --confirm-overlay
# <hash> invocation writes anything. A promotion whose
# catalog_fingerprint_at_promotion no longer matches the CURRENT catalog's
# runtime.fingerprint for that run_unit_id is rejected BEFORE the diff is even
# displayed — a stale promotion can never be silently approved, or even
# offered for approval.
#
# Merge semantics: the canonical, force-tracked overlay accumulates promotions
# across many separate isolation-experiment runs (Step 6). This script UPSERTS
# the proposed file's entries into the existing approved overlay by
# run_unit_id — a new promotion for an already-promoted unit supersedes the
# old entry; every other existing entry is carried through unchanged.
#
# The approved overlay target and the catalog read for fingerprint
# verification are ALWAYS the canonical
# ${project_root}/.aid-o/config/test-scheduler-parallel-overlay.yaml and
# ${project_root}/.aid-o/config/test-catalog.yaml — never PM-supplied override
# paths (same fixed-target security rationale as aid-test-catalog-approve.sh).
#
# Usage:
#   # Step 1 — display the diff and its hash, make no changes:
#   aid-scheduler-overlay-approve.sh --proposed <path> --project-root <path>
#
#   # Step 2 — confirm with the exact hash just shown:
#   aid-scheduler-overlay-approve.sh --proposed <path> --project-root <path> \
#     --confirm-overlay <reviewed_diff_hash>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

OVERLAY_SCHEMA="${SCHEMAS_DIR}/scheduler-parallel-overlay.schema.json"

_die() { echo "aid-scheduler-overlay-approve.sh: $2" >&2; exit "$1"; }

proposed_path="" project_root="" confirm_hash=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposed) [[ $# -ge 2 ]] || _die 2 "--proposed requires a value"; proposed_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --confirm-overlay) [[ $# -ge 2 ]] || _die 2 "--confirm-overlay requires a value"; confirm_hash="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$proposed_path" ]] || _die 2 "--proposed is required"
[[ -n "$project_root" ]] || _die 2 "--project-root is required"
[[ -f "$proposed_path" ]] || _die 3 "--proposed '$proposed_path' does not exist"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

approved_path="${project_root}/.aid-o/config/test-scheduler-parallel-overlay.yaml"
catalog_path="${project_root}/.aid-o/config/test-catalog.yaml"

proposed_json="$(yq -o=json '.' "$proposed_path" 2>/dev/null)" \
  || _die 1 "--proposed '$proposed_path' is not valid YAML"
[[ -n "$proposed_json" && "$proposed_json" != "null" ]] \
  || _die 1 "--proposed '$proposed_path' parsed to an empty/null document"

adapter_validate_schema "$OVERLAY_SCHEMA" "$proposed_json" \
  || _die 1 "--proposed '$proposed_path' failed schema validation before approval — refusing to review an unvalidated overlay"

proposed_status="$(jq -r '.status' <<<"$proposed_json")"
[[ "$proposed_status" == "proposed" ]] || _die 1 "--proposed '$proposed_path' has status '$proposed_status' — expected 'proposed'"

# Codex review: the schema does not (and cannot, in Draft 2020-12 without a
# uniqueItems-on-a-projection extension) enforce one entry per run_unit_id —
# a proposed document with two entries for the SAME unit would otherwise
# survive the upsert unchanged, leaving the scheduler's `.[0]` lookup
# dependent on array order rather than true supersession. Reject up front.
dup_json="$(jq -c '[.overlay | group_by(.run_unit_id)[] | select(length > 1) | .[0].run_unit_id]' <<<"$proposed_json")"
dup_count="$(jq 'length' <<<"$dup_json")"
if [[ "$dup_count" -gt 0 ]]; then
  echo "aid-scheduler-overlay-approve.sh: refusing to approve — --proposed contains duplicate run_unit_id entries: $(jq -r 'join(", ")' <<<"$dup_json")" >&2
  exit 1
fi

[[ -f "$catalog_path" ]] || _die 3 "no approved catalog found at $catalog_path — run aid-test-catalog-approve.sh first"
catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null)" || _die 1 "$catalog_path is not valid YAML"

# Reject any stale promotion BEFORE ever displaying a diff or accepting a
# confirmation — a promotion whose catalog_fingerprint_at_promotion no
# longer matches the run_unit_id's CURRENT catalog runtime.fingerprint must
# never be silently approved, or even offered for approval.
stale_json="$(jq -c --slurpfile cat <(echo "$catalog_json") '
  ($cat[0].run_units | map({(.run_unit_id): .runtime.fingerprint}) | add // {}) as $current_fp
  | [ .overlay[] | select(($current_fp[.run_unit_id] // null) != .catalog_fingerprint_at_promotion) ]
' <<<"$proposed_json")"

stale_count="$(jq 'length' <<<"$stale_json")"
if [[ "$stale_count" -gt 0 ]]; then
  echo "aid-scheduler-overlay-approve.sh: refusing to approve — ${stale_count} stale promotion(s) whose catalog_fingerprint_at_promotion no longer matches the current catalog:" >&2
  jq -r '.[] | "  - \(.run_unit_id) (promoted against \(.catalog_fingerprint_at_promotion))"' <<<"$stale_json" >&2
  exit 1
fi

if [[ -f "$approved_path" ]]; then
  existing_json="$(yq -o=json '.' "$approved_path" 2>/dev/null)" || _die 1 "$approved_path is not valid YAML"
else
  existing_json='{"schema_version":"1.0.0","status":"approved","overlay":[]}'
fi

# Reviewed diff: every NEWLY proposed row's full displayed shape, hashed
# exactly as displayed — same idiom as aid-test-catalog-confirm-mapping.sh.
# promoted_at is included (Codex review: it was previously excluded, so
# changing it after obtaining a review hash would still confirm under the
# stale hash — this field is written into the approved document, so it must
# be part of what "this exact promotion set" binds).
diff_rows_json="$(jq -cS '[.overlay[] | {run_unit_id, promoted_status, catalog_fingerprint_at_promotion, promoted_at, evidence_run_id}]' <<<"$proposed_json")"
computed_hash="sha256:$(printf '%s' "$diff_rows_json" | sha256sum | cut -d' ' -f1)"

_print_diff() {
  echo "Reviewed diff (proposed promotions — run_unit_id, promoted_status, evidence_run_id):"
  jq -r '.overlay[] | "  \(.run_unit_id) -> \(.promoted_status) (evidence: \(.evidence_run_id))"' <<<"$proposed_json"
  echo ""
  echo "reviewed_diff_hash: ${computed_hash}"
  echo ""
  echo "To confirm this exact promotion set, re-run with:"
  echo "  --confirm-overlay ${computed_hash}"
}

if [[ -z "$confirm_hash" ]]; then
  _print_diff
  exit 0
fi

if [[ "$confirm_hash" != "$computed_hash" ]]; then
  echo "aid-scheduler-overlay-approve.sh: provided --confirm-overlay hash does not match the current reviewed diff (stale or wrong hash) — refusing to approve, re-displaying the current diff:" >&2
  _print_diff
  exit 1
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Upsert: existing entries NOT superseded by a proposed run_unit_id, plus
# every proposed entry — sorted by run_unit_id for deterministic output.
merged_overlay_json="$(jq -c \
  --slurpfile prop <(echo "$proposed_json") \
  '
  (.overlay // []) as $existing
  | ($prop[0].overlay | map(.run_unit_id)) as $superseded
  | { schema_version: "1.0.0", status: "approved",
      overlay: (([$existing[] | select(([.run_unit_id] | inside($superseded)) | not)]
                 + $prop[0].overlay) | sort_by(.run_unit_id)) }
  ' <<<"$existing_json")"

adapter_validate_schema "$OVERLAY_SCHEMA" "$merged_overlay_json" \
  || _die 1 "internal error: merging the proposed overlay produced a schema-invalid document — refusing to publish"

mkdir -p "$(dirname "$approved_path")"

tmp_path="${approved_path}.tmp.$$"
yq -P '.' <<<"$merged_overlay_json" > "$tmp_path"
mv "$tmp_path" "$approved_path"

added_count="$(jq '.overlay | length' <<<"$proposed_json")"

if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  rel_approved="${approved_path#"${project_root}"/}"
  git -C "$project_root" add -f -- "$rel_approved"
  echo "aid-scheduler-overlay-approve.sh: approved and force-tracked $rel_approved (${added_count} promotion(s) confirmed at ${now}, reviewed_diff_hash: ${computed_hash})"
else
  echo "aid-scheduler-overlay-approve.sh: not a git repository, overlay written to $approved_path but not tracked"
fi
