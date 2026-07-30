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
# Completeness (PM whole-EPIC-3 review, real gap): a schema-valid Wave 1
# artifact alone previously produced a schema-valid, publishable "clean"
# consolidated-findings.json/chat verdict with no way to detect a missing
# shard, missing Wave 2 specialist, or missing (mandatory) Wave 3
# adversarial review — the consolidator never consulted the dispatch
# manifest or knew what a COMPLETE dispatch even looked like. --dispatch-
# manifest is now required: every entry the manifest declares must have a
# real, schema-valid artifact whose OWN wave/focus/shard_id/
# producer_agent_dispatch_id fields exactly match what the manifest
# declared for it (catches a wrong-wave/wrong-producer artifact substituted
# in, not merely "some file exists"); any artifact file present in
# --wave-artifacts-dir that no manifest entry declares also fails closed
# (an artifact outside the manifest is never silently folded in); the
# manifest's own audit_id must match --audit-id (a manifest from a
# different audit can never be consulted here by accident). static mode's
# Wave 2 is correctly optional because the dispatch manifest itself omits
# Wave 2 entries for static mode (aid-test-audit-dispatch.sh) — this script
# does not need its own mode-awareness, it trusts the manifest completely.
#
# Usage:
#   aid-test-audit-consolidate.sh --audit-id <id> --wave-artifacts-dir <dir> \
#     --dispatch-manifest <path> --output-dir <dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

FINDINGS_SCHEMA="${SCHEMAS_DIR}/test-audit-consolidated-findings.schema.json"
WAVE_SCHEMA="${SCHEMAS_DIR}/test-audit-wave-artifact.schema.json"
BRIEF_SCHEMA="${SCHEMAS_DIR}/test-audit-plan-brief.schema.json"

_die() { echo "aid-test-audit-consolidate.sh: $2" >&2; exit "$1"; }

audit_id="" wave_artifacts_dir="" output_dir="" dispatch_manifest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-id) [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --wave-artifacts-dir) [[ $# -ge 2 ]] || _die 2 "--wave-artifacts-dir requires a value"; wave_artifacts_dir="$2"; shift 2 ;;
    --dispatch-manifest) [[ $# -ge 2 ]] || _die 2 "--dispatch-manifest requires a value"; dispatch_manifest="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

adapter_validate_audit_id "$audit_id" || _die 2 "--audit-id '$audit_id' is invalid (must match ^[A-Za-z0-9_-]+\$)"
[[ -n "$wave_artifacts_dir" && -d "$wave_artifacts_dir" ]] || _die 2 "--wave-artifacts-dir is required and must exist"
[[ -n "$dispatch_manifest" && -f "$dispatch_manifest" ]] || _die 2 "--dispatch-manifest is required and must exist"
[[ -n "$output_dir" ]] || _die 2 "--output-dir is required"
mkdir -p "$output_dir"

# ─── Load + validate the dispatch manifest itself ───────────────────────────
manifest_json="$(jq -e '.' "$dispatch_manifest" 2>/dev/null)" || _die 2 "--dispatch-manifest '$dispatch_manifest' is not valid JSON"
manifest_audit_id="$(jq -r '.audit_id // empty' <<<"$manifest_json")"
[[ -n "$manifest_audit_id" ]] || _die 1 "--dispatch-manifest '$dispatch_manifest' has no audit_id field — cannot verify it belongs to this audit"
[[ "$manifest_audit_id" == "$audit_id" ]] || _die 1 "--dispatch-manifest audit_id '$manifest_audit_id' does not match --audit-id '$audit_id' — refusing to consolidate against a different audit's manifest"

expected_entries_json="$(jq -c '[.entries[] | {wave, focus, shard_id, artifact_path, producer_agent_dispatch_id}]' <<<"$manifest_json")"
expected_count="$(jq 'length' <<<"$expected_entries_json")"
if [[ "$expected_count" -eq 0 ]]; then
  _die 1 "--dispatch-manifest '$dispatch_manifest' declares zero entries — nothing to consolidate"
fi

# ─── Read + schema-validate exactly the artifacts the manifest declares,
#     verifying each one's own identity fields match what was declared ────
all_findings_ndjson="$(mktemp)"
trap 'rm -f "$all_findings_ndjson"' EXIT

consumed_ndjson="$(mktemp)"
for ((i = 0; i < expected_count; i++)); do
  entry="$(jq -c ".[$i]" <<<"$expected_entries_json")"
  exp_wave="$(jq -r '.wave' <<<"$entry")"
  exp_focus="$(jq -r '.focus' <<<"$entry")"
  exp_shard_id="$(jq -r '.shard_id' <<<"$entry")"
  exp_dispatch_id="$(jq -r '.producer_agent_dispatch_id' <<<"$entry")"
  basename_f="$(basename "$(jq -r '.artifact_path' <<<"$entry")")"
  actual_path="${wave_artifacts_dir%/}/${basename_f}"

  [[ -f "$actual_path" ]] \
    || _die 1 "expected wave artifact missing: '$basename_f' (wave $exp_wave, focus $exp_focus) — the dispatch manifest declares it but it was never produced; refusing to consolidate an incomplete dispatch"

  artifact_json="$(jq -e '.' "$actual_path" 2>/dev/null)" \
    || _die 1 "wave artifact is not valid JSON: $actual_path"
  adapter_validate_schema "$WAVE_SCHEMA" "$artifact_json" \
    || _die 1 "wave artifact failed schema validation: $actual_path"

  act_wave="$(jq -r '.wave' <<<"$artifact_json")"
  act_focus="$(jq -r '.focus' <<<"$artifact_json")"
  act_shard_id="$(jq -r '.shard_id' <<<"$artifact_json")"
  act_dispatch_id="$(jq -r '.producer_agent_dispatch_id' <<<"$artifact_json")"
  if [[ "$act_wave" != "$exp_wave" || "$act_focus" != "$exp_focus" || "$act_shard_id" != "$exp_shard_id" || "$act_dispatch_id" != "$exp_dispatch_id" ]]; then
    _die 1 "wave artifact '$basename_f' does not match its dispatch-manifest entry (expected wave=$exp_wave focus=$exp_focus shard_id=$exp_shard_id producer_agent_dispatch_id=$exp_dispatch_id; got wave=$act_wave focus=$act_focus shard_id=$act_shard_id producer_agent_dispatch_id=$act_dispatch_id)"
  fi

  jq -c '.findings[]' <<<"$artifact_json" >> "$all_findings_ndjson" 2>/dev/null || true
  printf '%s\n' "$basename_f" >> "$consumed_ndjson"
done

# ─── Any artifact file the manifest does NOT declare fails closed — never
#     silently folded into the report ────────────────────────────────────
shopt -s nullglob
for artifact_file in "$wave_artifacts_dir"/*.json; do
  bn="$(basename "$artifact_file")"
  if ! grep -qxF "$bn" "$consumed_ndjson"; then
    rm -f "$consumed_ndjson"
    _die 1 "wave artifact '$bn' exists in '$wave_artifacts_dir' but is not declared by any entry in --dispatch-manifest — refusing to consolidate an artifact outside the manifest"
  fi
done
shopt -u nullglob
rm -f "$consumed_ndjson"

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
# Medium+/actionable finding exists: severity != low AND recommendation is
# one of fix/split/merge/remove/quarantine (matches
# aid-test-audit-chat-summary.sh's _tacs_classify_verdict EXACTLY — Codex
# whole-EPIC review: a severity-only filter previously let a Medium+
# finding recommending "keep" or "measure" alone still produce a
# remediation-recommended brief, even though the chat renderer classified
# the SAME findings as "clean" or "needs measurement" — a durable record
# blocking on a verdict with no matching, honest brief on disk).
actionable_json="$(jq -c '[.[] | select(.severity != "low" and (.recommendation | IN("fix","split","merge","remove","quarantine")))]' <<<"$with_ids_json")"
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
