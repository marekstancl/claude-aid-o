#!/usr/bin/env bash
# aid-test-audit-consolidate.sh — P066 Step 14.
#
# Merges all wave artifacts into consolidated-findings.json by stable ID
# (run_unit_id+category+evidence_refs), never by prose similarity. Exact
# duplicates collapse; conflicting recommendations (same run_unit_id+
# category, DIFFERENT evidence_refs) remain visible, each tagged
# unresolved_conflict:true — never silently resolved by the consolidator.
#
# Also renders implementation-plan-brief.{json,md} whenever at least one
# Medium+/actionable finding exists — an all-clean findings set produces
# NEITHER file (Step 16's validator treats absence as the clean case).
#
# Usage:
#   aid-test-audit-consolidate.sh --audit-id <id> --wave-artifacts-dir <dir> \
#     --output-dir <dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

FINDINGS_SCHEMA="${SCHEMAS_DIR}/test-audit-consolidated-findings.schema.json"
WAVE_SCHEMA="${SCHEMAS_DIR}/test-audit-wave-artifact.schema.json"
BRIEF_SCHEMA="${SCHEMAS_DIR}/test-audit-plan-brief.schema.json"

_die() { echo "aid-test-audit-consolidate.sh: $2" >&2; exit "$1"; }

audit_id="" wave_artifacts_dir="" output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-id) [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --wave-artifacts-dir) [[ $# -ge 2 ]] || _die 2 "--wave-artifacts-dir requires a value"; wave_artifacts_dir="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

adapter_validate_audit_id "$audit_id" || _die 2 "--audit-id '$audit_id' is invalid (must match ^[A-Za-z0-9_-]+\$)"
[[ -n "$wave_artifacts_dir" && -d "$wave_artifacts_dir" ]] || _die 2 "--wave-artifacts-dir is required and must exist"
[[ -n "$output_dir" ]] || _die 2 "--output-dir is required"
mkdir -p "$output_dir"

# ─── Read + schema-validate every wave artifact, collect findings[] ─────────
all_findings_ndjson="$(mktemp)"
trap 'rm -f "$all_findings_ndjson"' EXIT

artifact_count=0
shopt -s nullglob
for artifact_file in "$wave_artifacts_dir"/*.json; do
  artifact_count=$((artifact_count + 1))
  artifact_json="$(jq -e '.' "$artifact_file" 2>/dev/null)" \
    || _die 1 "wave artifact is not valid JSON: $artifact_file"
  adapter_validate_schema "$WAVE_SCHEMA" "$artifact_json" \
    || _die 1 "wave artifact failed schema validation: $artifact_file"
  jq -c '.findings[]' <<<"$artifact_json" >> "$all_findings_ndjson" 2>/dev/null || true
done
shopt -u nullglob

# Fail closed on zero wave artifacts — Codex review: an empty (or missing-
# dispatch) --wave-artifacts-dir previously produced a schema-valid, empty
# findings report that looked exactly like a genuinely clean audit, turning
# a missing/interrupted dispatch into a false "clean" verdict.
if [[ "$artifact_count" -eq 0 ]]; then
  _die 1 "no wave artifacts found in '$wave_artifacts_dir' — refusing to report a clean audit over a missing/interrupted dispatch"
fi

all_findings_json="$(jq -cs '.' "$all_findings_ndjson")"

# ─── Dedup: TRUE exact duplicates (identical in every field, not merely
# sharing run_unit_id+category+evidence_refs) collapse to one. Two findings
# that share the same key but differ in severity/recommendation/confidence/
# falsification_check are NOT duplicates — Codex review found the earlier
# `map(.[0])` silently discarded the second, order-dependent, even though
# they can carry contradictory remediation advice. Those are preserved as a
# same-evidence conflict (unresolved_conflict:true), same as a same-
# run_unit_id+category-different-evidence conflict below.
merged_json="$(jq -c '
  (
    group_by([.run_unit_id, .category, .evidence_refs])
    | map(
        if (length == 1) then .
        elif (unique | length) == 1 then [.[0]]
        else map(. + {unresolved_conflict: true})
        end
      )
    | flatten(1)
  ) as $stage1 |
  ($stage1 | group_by([.run_unit_id, .category])) as $by_ruid_cat |
  [$by_ruid_cat[] | if length > 1 then map(. + {unresolved_conflict: true})[] else .[] end]
' <<<"$all_findings_json")"

# ─── Reject an unsupported removal/quarantine recommendation (no
# falsification_check) BEFORE the report is ever produced — the
# consolidator's own enforcement, not merely a schema hope.
unsupported="$(jq -r '
  [.[] | select((.recommendation == "remove" or .recommendation == "quarantine") and ((.falsification_check // "") == ""))] | .[0].run_unit_id // empty
' <<<"$merged_json")"
if [[ -n "$unsupported" ]]; then
  _die 1 "a remove/quarantine finding for '$unsupported' has no falsification_check — rejected before report"
fi

# ─── Compute stable finding_id (hash of run_unit_id+category) per surviving
# finding, then sort by it — deterministic regardless of wave-artifact
# arrival order.
count="$(jq 'length' <<<"$merged_json")"
ids_ndjson="$(mktemp)"
for ((i = 0; i < count; i++)); do
  ruid="$(jq -r ".[$i].run_unit_id" <<<"$merged_json")"
  cat="$(jq -r ".[$i].category" <<<"$merged_json")"
  fid="sha256:$(printf '%s' "${ruid}:${cat}" | sha256sum | cut -c1-12)"
  jq -c --arg fid "$fid" ".[$i] + {finding_id: \$fid}" <<<"$merged_json" >> "$ids_ndjson"
done
with_ids_json="$(jq -cs 'sort_by(.finding_id)' "$ids_ndjson" 2>/dev/null || echo '[]')"
rm -f "$ids_ndjson"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
consolidated_json="$(jq -n --arg audit_id "$audit_id" --arg gen "$generated_at" --argjson findings "$with_ids_json" \
  '{schema_version:"1.0.0", audit_id:$audit_id, generated_at:$gen, findings:$findings}')"

adapter_validate_schema "$FINDINGS_SCHEMA" "$consolidated_json" \
  || _die 1 "internal error: generated consolidated-findings.json failed its own schema"

consolidated_tmp="${output_dir%/}/consolidated-findings.json.tmp.$$"
printf '%s\n' "$consolidated_json" > "$consolidated_tmp"
mv "$consolidated_tmp" "${output_dir%/}/consolidated-findings.json"

# ─── implementation-plan-brief.{json,md} — only when at least one
# Medium+/actionable finding exists. "Medium+" = severity != low.
actionable_json="$(jq -c '[.[] | select(.severity != "low")]' <<<"$with_ids_json")"
actionable_count="$(jq 'length' <<<"$actionable_json")"

if [[ "$actionable_count" -gt 0 ]]; then
  consolidated_hash="sha256:$(sha256sum "${output_dir%/}/consolidated-findings.json" | cut -d' ' -f1)"
  items_json="$(jq -c '[.[] | {
    finding_id, run_unit_id, category,
    proposed_action: .recommendation,
    evidence_refs,
    owner: (.owner // "unassigned")
  }]' <<<"$actionable_json")"
  brief_json="$(jq -n --arg audit_id "$audit_id" --arg hash "$consolidated_hash" --argjson items "$items_json" \
    '{audit_id:$audit_id, verdict:"remediation recommended", items:$items, generated_from_hash:$hash}')"

  adapter_validate_schema "$BRIEF_SCHEMA" "$brief_json" \
    || _die 1 "internal error: generated implementation-plan-brief.json failed its own schema"

  brief_json_tmp="${output_dir%/}/implementation-plan-brief.json.tmp.$$"
  printf '%s\n' "$brief_json" > "$brief_json_tmp"
  mv "$brief_json_tmp" "${output_dir%/}/implementation-plan-brief.json"

  {
    echo "# Test Portfolio Audit — Remediation Brief"
    echo
    echo "Audit: \`$audit_id\` — Verdict: **remediation recommended**"
    echo
    echo "| Finding | Run Unit | Category | Proposed Action | Owner |"
    echo "|---|---|---|---|---|"
    jq -r '.[] | "| \(.finding_id) | \(.run_unit_id) | \(.category) | \(.proposed_action) | \(.owner) |"' <<<"$items_json"
  } > "${output_dir%/}/implementation-plan-brief.md.tmp.$$"
  mv "${output_dir%/}/implementation-plan-brief.md.tmp.$$" "${output_dir%/}/implementation-plan-brief.md"
else
  rm -f "${output_dir%/}/implementation-plan-brief.json" "${output_dir%/}/implementation-plan-brief.md"
fi

echo "$output_dir"
