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
# P072 Step 4 — the mode decides whether per-unit dispositions are OWED, and
# the inventory is the denominator every coverage figure is computed against.
# Both default to the pre-P072 behaviour so an existing caller is unaffected.
audit_mode="measure" inventory_path="" project_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-id) [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --wave-artifacts-dir) [[ $# -ge 2 ]] || _die 2 "--wave-artifacts-dir requires a value"; wave_artifacts_dir="$2"; shift 2 ;;
    --dispatch-manifest) [[ $# -ge 2 ]] || _die 2 "--dispatch-manifest requires a value"; dispatch_manifest="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || _die 2 "--mode requires a value"
      case "$2" in static|measure|full) audit_mode="$2" ;; *) _die 2 "--mode must be static|measure|full" ;; esac
      shift 2 ;;
    --inventory) [[ $# -ge 2 ]] || _die 2 "--inventory requires a value"; inventory_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
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
# One temp DIR, one trap, installed before anything can fail — two sequential
# mktemp calls under `set -e` leak the first if the second fails.
_tmpdir="$(mktemp -d)"
trap 'rm -rf "$_tmpdir"' EXIT
all_findings_ndjson="${_tmpdir}/findings.ndjson"
all_dispositions_ndjson="${_tmpdir}/dispositions.ndjson"
: > "$all_findings_ndjson"; : > "$all_dispositions_ndjson"

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

  # P072 Step 4 — a shard_portfolio artifact owes one terminal disposition per
  # run unit it was ASSIGNED. Enforced here rather than in the schema because
  # only this script knows the audit mode, and static/measure legitimately
  # produce none.
  if [[ "$exp_focus" == "shard_portfolio" ]]; then
    if [[ "$audit_mode" == "full" ]] && ! jq -e 'has("dispositions")' <<<"$artifact_json" >/dev/null; then
      _die 1 "shard artifact '$basename_f' has no dispositions[] — in full mode every assigned run_unit_id needs exactly one terminal disposition, and silence cannot be told apart from 'never inspected'"
    fi
    # No `|| true`: a jq failure here would otherwise read as "this shard
    # decided nothing", which is exactly the state this reconciliation exists
    # to detect. A parse failure must fail the consolidation instead.
    jq -c --arg shard "$act_shard_id" '(.dispositions // [])[] | {shard: $shard, run_unit_id, disposition, missing_proof, next_measurement}' \
      <<<"$artifact_json" >> "$all_dispositions_ndjson" \
      || _die 1 "could not read dispositions[] from '$basename_f'"
  fi
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

# ─── P072 Step 4: three-way reconciliation ─────────────────────────────────
#
# Runs BEFORE the remediation brief is written, so an audit that cannot claim
# a complete decision never leaves a remediation artifact on disk for someone
# to pick up. Reconciling afterwards would have produced the brief first and
# only then said the audit was incomplete.
#
# Reconciliation is PER SHARD, not over a flattened global set. A global set
# comparison is fooled by the obvious case: shard A is assigned {a,b} and
# emits only {a}, shard B is assigned {c} and emits {b,c} — the flattened
# sets match exactly, while shard A silently decided nothing about b.
decision_written="false"
audit_status_final="complete"

if [[ "$audit_mode" == "full" ]]; then
  # shellcheck source=lib/aid-test-audit-decision.sh
  source "${SCRIPT_DIR}/lib/aid-test-audit-decision.sh"
  # shellcheck source=lib/aid-test-audit-config.sh
  source "${SCRIPT_DIR}/lib/aid-test-audit-config.sh"

  [[ -n "$inventory_path" && -f "$inventory_path" ]] \
    || _die 2 "--inventory is required in full mode (it is the denominator every coverage figure is measured against) and must exist"
  [[ -n "$project_root" && -d "$project_root" ]] \
    || _die 2 "--project-root is required in full mode — the unresolved-fraction threshold is read from that project's test-audit.yaml, and deriving it from --output-dir guesses wrong"

  # IDs stay JSON end to end. A round trip through newline-delimited text
  # splits an id containing a control character into two different ids.
  inventory_ids_json="$(jq -c '[.run_units[].run_unit_id]' "$inventory_path")" \
    || _die 2 "--inventory '$inventory_path' is not readable as JSON with a run_units[] array — an unreadable inventory is an operational failure, not an empty portfolio"

  inv_dupes="$(jq -r 'group_by(.) | map(select(length>1) | .[0]) | .[0] // empty' <<<"$inventory_ids_json")"
  [[ -z "$inv_dupes" ]] || _die 6 "inventory lists run_unit_id '$inv_dupes' more than once — identity is corrupt, and de-duplicating it would hide that"

  inventory_unique_json="$(jq -c 'unique' <<<"$inventory_ids_json")"
  inventory_count="$(jq 'length' <<<"$inventory_unique_json")"

  if [[ "$inventory_count" -eq 0 ]]; then
    audit_status_final="incomplete"
    decision_json="$(jq -n --arg id "$audit_id" '{
      schema_version:"aid-test-audit-decision-v1", audit_id:$id,
      audit_status:"incomplete", incomplete_reason:"empty_inventory",
      current_runtime:{kind:"unknown",duration_ms:null,scope:["none"]},
      actions:[], parallelization:{lanes:[],smallest_safe_pilot:null}, unresolved:[],
      portfolio_coverage:{inventory_count:0,assigned_count:0,disposition_count:0,
                          missing_run_unit_ids:[],duplicate_run_unit_ids:[]},
      portfolio_change:{current_run_units:0,proposed_run_units:0,keep:[],rewrite_unit:[],
                        merge_groups:[],remove:[],runtime_before_ms:null,runtime_after_ms:null,
                        impact_kind:"unknown"}}')"
    aid_test_audit_decision_write "$decision_json" "${output_dir%/}/decision.json" \
      || _die 1 "internal error: the empty-inventory decision artifact failed its own schema"
    decision_written="true"
  else
    # (shard, run_unit_id) pairs on both sides — the multiset comparison.
    assigned_pairs_json="$(jq -c '[.entries[] | select(.focus == "shard_portfolio")
      | .shard_id as $s | .run_unit_ids[] | {shard: $s, run_unit_id: .}]' <<<"$manifest_json")" \
      || _die 1 "could not read shard assignments from the dispatch manifest"
    decided_pairs_json="$(jq -s -c '[.[] | {shard, run_unit_id}]' "$all_dispositions_ndjson")" \
      || _die 1 "could not read the collected dispositions"
    dispositions_json="$(jq -s -c '.' "$all_dispositions_ndjson")" \
      || _die 1 "could not read the collected dispositions"

    # A disposition naming a unit the inventory never discovered means a shard
    # invented one — a different failure from merely missing a unit.
    invented="$(jq -r --argjson inv "$inventory_unique_json" \
      '[.[] | select(.run_unit_id as $r | $inv | index($r) == null) | .run_unit_id] | unique | .[0] // empty' \
      <<<"$dispositions_json")"
    [[ -z "$invented" ]] || _die 5 "a disposition names run_unit_id '$invented', which the inventory never discovered — a shard cannot invent a unit"

    # Assigned-but-not-decided, evaluated per shard.
    missing_json="$(jq -c -n --argjson a "$assigned_pairs_json" --argjson d "$decided_pairs_json" \
      '[$a[] | select(. as $p | $d | index($p) == null) | .run_unit_id] | unique')"
    # Decided more than once for the SAME shard, or by more than one shard.
    dupes_json="$(jq -c '[.[].run_unit_id] | group_by(.) | map(select(length>1) | .[0]) | unique' \
      <<<"$decided_pairs_json")"

    assigned_count="$(jq '[.[].run_unit_id] | unique | length' <<<"$assigned_pairs_json")"
    disposition_count="$(jq '[.[].run_unit_id] | unique | length' <<<"$decided_pairs_json")"

    # The threshold must be a real number in [0,1]. An unreadable value would
    # otherwise be coerced to 0 by awk, making every audit exceed it.
    max_unresolved="$(test_audit_decision_key max_unresolved_fraction "$project_root")" \
      || _die 2 "could not read decision.max_unresolved_fraction from '$project_root' — refusing to guess the threshold that decides whether this audit is complete"
    awk -v m="$max_unresolved" 'BEGIN{ if (m ~ /^[0-9]*\.?[0-9]+$/ && m+0 >= 0 && m+0 <= 1) exit 0; exit 1 }' \
      || _die 2 "decision.max_unresolved_fraction '$max_unresolved' is not a number in [0,1]"

    unresolved_json="$(jq -c '[.[] | select(.disposition == "measure") |
      {run_unit_id, missing_proof: (.missing_proof // "budget_exhausted"),
       next_measurement: (.next_measurement // "re-run this unit under --mode full with a larger budget")}]' \
      <<<"$dispositions_json")"
    unresolved_count="$(jq 'length' <<<"$unresolved_json")"

    reason=""
    if [[ "$(jq 'length' <<<"$missing_json")" -gt 0 ]]; then
      reason="coverage_mismatch"
    elif [[ "$(jq 'length' <<<"$dupes_json")" -gt 0 ]]; then
      reason="duplicate_dispositions"
    elif [[ "$inventory_count" -ne "$assigned_count" || "$assigned_count" -ne "$disposition_count" ]]; then
      reason="coverage_mismatch"
    elif awk -v u="$unresolved_count" -v t="$inventory_count" -v m="$max_unresolved" \
          'BEGIN{ exit !((u/t) > m) }'; then
      # Strictly greater: the configured value is the maximum still ACCEPTED,
      # so a portfolio sitting exactly on it is complete.
      reason="unresolved_fraction_exceeded"
    fi

    keep_json="$(jq -c '[.[] | select(.disposition=="keep") | .run_unit_id] | unique' <<<"$dispositions_json")"
    rewrite_json="$(jq -c '[.[] | select(.disposition=="rewrite_unit") | .run_unit_id] | unique' <<<"$dispositions_json")"
    remove_json="$(jq -c '[.[] | select(.disposition=="remove") | .run_unit_id] | unique' <<<"$dispositions_json")"
    removed_n="$(jq 'length' <<<"$remove_json")"

    status="complete"; reason_field="{}"
    if [[ -n "$reason" ]]; then
      status="incomplete"; reason_field="$(jq -nc --arg r "$reason" '{incomplete_reason:$r}')"
    fi
    audit_status_final="$status"

    decision_json="$(jq -n \
      --arg id "$audit_id" --arg status "$status" \
      --argjson extra "$reason_field" \
      --argjson inv "$inventory_unique_json" --argjson missing "$missing_json" --argjson dupes "$dupes_json" \
      --argjson unresolved "$unresolved_json" \
      --argjson keep "$keep_json" --argjson rewrite "$rewrite_json" --argjson remove "$remove_json" \
      --argjson ic "$inventory_count" --argjson ac "$assigned_count" --argjson dc "$disposition_count" \
      --argjson removed_n "$removed_n" '
      {schema_version:"aid-test-audit-decision-v1", audit_id:$id, audit_status:$status,
       current_runtime:{kind:"unknown", duration_ms:null, scope:$inv},
       actions:[], parallelization:{lanes:[], smallest_safe_pilot:null},
       unresolved:$unresolved,
       portfolio_coverage:{inventory_count:$ic, assigned_count:$ac, disposition_count:$dc,
                           missing_run_unit_ids:$missing, duplicate_run_unit_ids:$dupes},
       portfolio_change:{current_run_units:$ic, proposed_run_units:($ic - $removed_n),
                         keep:$keep, rewrite_unit:$rewrite, merge_groups:[], remove:$remove,
                         runtime_before_ms:null, runtime_after_ms:null, impact_kind:"unknown"}}
      + $extra')"

    aid_test_audit_decision_write "$decision_json" "${output_dir%/}/decision.json" \
      || _die 1 "internal error: the generated decision artifact failed its own schema"
    decision_written="true"
  fi
fi

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

# An incomplete audit must not leave a remediation brief behind: the brief is
# the thing a later step picks up, and an audit that cannot claim a complete
# decision has not earned one.
if [[ "$audit_status_final" != "complete" ]]; then
  rm -f "${output_dir%/}/implementation-plan-brief.json" "${output_dir%/}/implementation-plan-brief.md"
elif [[ "$actionable_count" -gt 0 ]]; then
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
