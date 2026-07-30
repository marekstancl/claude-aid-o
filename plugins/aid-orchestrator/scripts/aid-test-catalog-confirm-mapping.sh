#!/usr/bin/env bash
# aid-test-catalog-confirm-mapping.sh — P066 Step 17.
#
# The MANDATORY, SEPARATE mapping-confirmation gate PM feedback item 2
# requires: approving the catalog file as a whole (aid-test-catalog-approve.sh)
# must never also approve source_pattern_mappings[] — only this script,
# given the EXACT hash of the diff it just displayed, can do that.
#
# Usage:
#   # Step 1 — display the diff and its hash, make no changes:
#   aid-test-catalog-confirm-mapping.sh --catalog <path>
#
#   # Step 2 — confirm with the exact hash just shown:
#   aid-test-catalog-confirm-mapping.sh --catalog <path> \
#     --confirm-mapping <reviewed_diff_hash> [--approved-by <name>]
#
# A missing or mismatched --confirm-mapping hash always fails closed,
# re-displaying the current diff — never silently proceeds. Rows added or
# changed to the catalog AFTER a confirmation revert (by construction —
# reviewed_diff_hash is recomputed from the CURRENT rows every invocation)
# to requiring a fresh hash: a stale hash from a prior document state will
# not match the freshly-computed one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

CATALOG_SCHEMA="${SCHEMAS_DIR}/test-catalog.schema.json"

_die() { echo "aid-test-catalog-confirm-mapping.sh: $2" >&2; exit "$1"; }

catalog_path="" confirm_hash="" approved_by="operator"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --confirm-mapping) [[ $# -ge 2 ]] || _die 2 "--confirm-mapping requires a value"; confirm_hash="$2"; shift 2 ;;
    --approved-by) [[ $# -ge 2 ]] || _die 2 "--approved-by requires a value"; approved_by="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$catalog_path" ]] || _die 2 "--catalog is required"
[[ -f "$catalog_path" ]] || _die 3 "--catalog '$catalog_path' does not exist"

catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null)" || _die 1 "--catalog '$catalog_path' is not valid YAML"
adapter_validate_schema "$CATALOG_SCHEMA" "$catalog_json" \
  || _die 1 "--catalog '$catalog_path' failed schema validation"

# The reviewed diff is EVERY row's full displayed shape (match_type,
# path_pattern, classification, target_run_unit_ids, precedence) — a
# canonical, sorted-key JSON array — hashed exactly as displayed. Rows
# added/changed after a confirmation recompute to a DIFFERENT hash, so a
# stale --confirm-mapping value never matches. Codex review: match_type and
# precedence were previously excluded from the hash, so changing e.g. an
# exact rule to a prefix rule (both routing-relevant and both shown in the
# diff) would still pass a stale --confirm-mapping value.
diff_rows_json="$(jq -cS '[.source_pattern_mappings[] | {match_type, path_pattern, classification, target_run_unit_ids, precedence}]' <<<"$catalog_json")"
computed_hash="sha256:$(printf '%s' "$diff_rows_json" | sha256sum | cut -d' ' -f1)"

_print_diff() {
  echo "Reviewed diff (source_pattern_mappings[] — pattern, classification, target run_unit_ids):"
  jq -r '.source_pattern_mappings[] | "  [\(.precedence)] \(.match_type) \(.path_pattern) -> \(.classification) -> \(.target_run_unit_ids | join(", "))"' <<<"$catalog_json"
  echo ""
  echo "reviewed_diff_hash: ${computed_hash}"
  echo ""
  echo "To confirm this exact mapping, re-run with:"
  echo "  --confirm-mapping ${computed_hash}"
}

if [[ -z "$confirm_hash" ]]; then
  _print_diff
  exit 0
fi

if [[ "$confirm_hash" != "$computed_hash" ]]; then
  echo "aid-test-catalog-confirm-mapping.sh: provided --confirm-mapping hash does not match the current reviewed diff (stale or wrong hash) — refusing to approve, re-displaying the current diff:" >&2
  _print_diff
  exit 1
fi

approved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

updated_json="$(jq -c \
  --arg by "$approved_by" \
  --arg at "$approved_at" \
  --arg hash "$computed_hash" \
  '
  .mapping_approval = {status: "approved", approved_by: $by, approved_at: $at, reviewed_diff_hash: $hash}
  | .source_pattern_mappings = [.source_pattern_mappings[] | .status = "approved"]
  ' <<<"$catalog_json")"

adapter_validate_schema "$CATALOG_SCHEMA" "$updated_json" \
  || _die 1 "internal error: confirming the mapping produced a schema-invalid document — refusing to publish"

tmp_path="${catalog_path}.tmp.$$"
yq -P '.' <<<"$updated_json" > "$tmp_path"
mv "$tmp_path" "$catalog_path"

row_count="$(jq '.source_pattern_mappings | length' <<<"$updated_json")"
echo "aid-test-catalog-confirm-mapping.sh: mapping confirmed (reviewed_diff_hash: ${computed_hash}) — ${row_count} source_pattern_mappings rows approved"
