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
source "${SCRIPT_DIR}/lib/aid-test-profile-validate.sh"
source "${SCRIPT_DIR}/lib/aid-test-lane-input-validate.sh"

INVENTORY_SCHEMA="${SCHEMAS_DIR}/test-audit-inventory.schema.json"
FINDINGS_SCHEMA="${SCHEMAS_DIR}/test-audit-consolidated-findings.schema.json"
WAVE_SCHEMA="${SCHEMAS_DIR}/test-audit-wave-artifact.schema.json"
BRIEF_SCHEMA="${SCHEMAS_DIR}/test-audit-plan-brief.schema.json"

_die() { echo "aid-test-audit-consolidate.sh: $2" >&2; exit "$1"; }

audit_id="" wave_artifacts_dir="" output_dir="" dispatch_manifest=""
# P072 Step 4 — the mode decides whether per-unit dispositions are OWED, and
# the inventory is the denominator every coverage figure is computed against.
# Both default to the pre-P072 behaviour so an existing caller is unaffected.
audit_mode="measure" inventory_path="" project_root="" profiles_dir="" profile_selection=""
resource_maps_dir="" pilots_dir=""
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
    --profiles-dir) [[ $# -ge 2 ]] || _die 2 "--profiles-dir requires a value"; profiles_dir="$2"; shift 2 ;;
    --resource-maps-dir) [[ $# -ge 2 ]] || _die 2 "--resource-maps-dir requires a value"; resource_maps_dir="$2"; shift 2 ;;
    --pilots-dir) [[ $# -ge 2 ]] || _die 2 "--pilots-dir requires a value"; pilots_dir="$2"; shift 2 ;;
    --profile-selection) [[ $# -ge 2 ]] || _die 2 "--profile-selection requires a value"; profile_selection="$2"; shift 2 ;;
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
    jq -c --arg shard "$act_shard_id" '(.dispositions // [])[] | {shard: $shard, run_unit_id, disposition,
       missing_proof, next_measurement, uniqueness, overlaps_with, falsification, cost}' \
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
  # Validate the inventory against its OWN schema before reading a single field.
  # This exists because of a real, total failure: this script read `.run_units[]`
  # while the scanner and the schema both say `entries[]`, so every `--mode full`
  # audit died at consolidation — and the regression suite never saw it, because
  # its fixture was hand-written as `{"run_units":[]}`, a shape the real producer
  # has never emitted. A fixture that invents its own contract tests nothing.
  # Validating here means a wrong-shaped inventory now fails loudly wherever it
  # came from, test or production.
  if ! adapter_validate_schema "$INVENTORY_SCHEMA" "$(cat "$inventory_path")"; then
    _die 2 "--inventory '$inventory_path' is not a valid aid-test-audit-inventory (see ${INVENTORY_SCHEMA}) — an inventory that does not match its contract cannot be the denominator for anything"
  fi
  [[ -n "$project_root" && -d "$project_root" ]] \
    || _die 2 "--project-root is required in full mode — the unresolved-fraction threshold is read from that project's test-audit.yaml, and deriving it from --output-dir guesses wrong"

  # IDs stay JSON end to end. A round trip through newline-delimited text
  # splits an id containing a control character into two different ids.
  inventory_ids_json="$(jq -c '[.entries[].run_unit_id]' "$inventory_path")" \
    || _die 2 "--inventory '$inventory_path' is not readable as JSON with an entries[] array — an unreadable inventory is an operational failure, not an empty portfolio"

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

    # ─── P072 Step 13: profiles become named root-cause actions ─────────────
    #
    # The mapping is where a diagnosis stops being a number and becomes advice,
    # so it is also where a dishonest saving would enter. Two rules hold it
    # shut:
    #
    #   * a receipt that did not COMPLETE can never produce a `measured`
    #     impact. Its elapsed time is a LOWER BOUND, so it goes in `before_ms`
    #     with `after_ms: null` and `kind: unknown`. Presenting a lower bound
    #     as a before-and-after pair is exactly the invented saving the
    #     adversarial contract forbids.
    #
    #   * a rising per-case cost maps to `measure`, never to `fix` and never
    #     to `split`. `cost_rises_across_run` says later cases were more
    #     expensive than earlier ones. It does NOT say state accumulated —
    #     the cases may simply be heavier work — and the two call for opposite
    #     remedies. Only the fresh-root/reordered probe named in the receipt
    #     separates them, so until it runs the honest action is to measure.
    #
    #   * a receipt that fails schema validation stops the audit. See
    #     `lib/aid-test-profile-validate.sh` for why an empty action list is
    #     the most dangerous possible response to a corrupt input.
    profile_actions_json='[]'
    if [[ -n "$profiles_dir" ]]; then
      # Fail-closed. A profiles directory that was named but does not exist, or
      # that holds one unreadable receipt, HALTS finalization. The alternative
      # — the `|| echo '[]'` this replaced — turned a corrupt input into an
      # empty action list, which renders identically to "nothing needed doing".
      if ! test_profile_validate_dir "$profiles_dir" "$audit_id"; then
        _die 6 "profiles directory '$profiles_dir' contains a receipt that is not a valid aid-test-profile-v1 — finalization stops here rather than producing an action list that silently omits it"
      fi
      # An empty profiles directory is a real state — the audit profiled
      # nothing — and must not be confused with synthesis that produced
      # nothing from receipts that were there.
      _receipt_count="$(find "$profiles_dir" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l)"
      if [[ "$_receipt_count" -gt 0 ]]; then
      profile_actions_json="$(
        find "$profiles_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
          | xargs -0 -r jq -sc --argjson rm "$remove_json" '
            [ .[]
              # A unit already proposed for deletion gets no cost action:
              # optimising a test scheduled for removal is wasted work.
              | select(.run_unit_id as $u | $rm | index($u) | not)
              | . as $p
              | ($p.root_cause.bucket) as $b
              | {
                  action: (if $b == "duplicate_membership" then "fix"
                           elif $b == "test_body" then "keep_serial"
                           else "measure" end),
                  targets: [$p.run_unit_id],
                  priority: (if $p.complete then "medium" else "high" end),
                  reason: ($p.root_cause.reason | .[0:500]),
                  evidence_refs: ["profiles/" + $p.evidence_log],
                  impact: (if $p.complete and ($b == "duplicate_membership")
                           then {kind:"estimated", before_ms:$p.elapsed_ms, after_ms:null,
                                 assumptions:["removing the duplicate dispatch saves one full run of this unit"]}
                           elif $p.complete
                           then {kind:"unknown", before_ms:null, after_ms:null, assumptions:[]}
                           else {kind:"unknown", before_ms:$p.lower_bound_ms, after_ms:null,
                                 assumptions:["the run did not finish — this is a lower bound on current cost, not a measured total"]}
                           end)
                } ]'
      )" || _die 6 "could not build actions from the validated profiles in '$profiles_dir'"
      [[ -n "$profile_actions_json" ]] || _die 6 "profile action synthesis produced nothing from '$profiles_dir' — an empty result from a non-empty directory is a bug, not a finding"
      fi
    fi

    # ─── The selection is the obligation, and it is enforced here ───────────
    #
    # A selection artifact names the units this audit decided owed a profile.
    # Without this check the selector would be a detector with no enforcement:
    # it would name three slow suites, nobody would profile them, and the audit
    # would finalize looking exactly as complete as one that had.
    if [[ -n "$profile_selection" ]]; then
      [[ -f "$profile_selection" ]] \
        || _die 6 "--profile-selection '$profile_selection' does not exist"
      jq -e '.schema_version == "aid-test-profile-selection-v1"' "$profile_selection" >/dev/null 2>&1 \
        || _die 6 "'$profile_selection' is not an aid-test-profile-selection-v1 artifact"
      _sel_audit="$(jq -r '.audit_id // ""' "$profile_selection")"
      [[ "$_sel_audit" == "$audit_id" ]] \
        || _die 6 "the profile selection belongs to audit '$_sel_audit', not '$audit_id'"

      _owed="$(jq -r '.selected[].run_unit_id' "$profile_selection")"
      if [[ -n "$_owed" ]]; then
        _have='[]'
        if [[ -n "$profiles_dir" && -d "$profiles_dir" ]]; then
          _have="$(find "$profiles_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
                    | xargs -0 -r jq -sc '[.[].run_unit_id]')"
          [[ -n "$_have" ]] || _have='[]'
        fi
        _missing="$(jq -r --argjson have "$_have" \
          '[.selected[].run_unit_id | select(. as $u | $have | index($u) | not)] | join(", ")' \
          "$profile_selection")"
        [[ -z "$_missing" ]] \
          || _die 6 "the audit selected these units for cost profiling and no receipt exists for them: ${_missing} — finalizing here would present an audit that skipped its own diagnosis as one that completed it"
      fi

      # Deferred units are reported, never dropped. A unit over the trigger
      # that did not fit under the ceiling is a known, quantified gap; leaving
      # it out of the findings is how a gap becomes invisible.
      _deferred_actions="$(jq -c '[.deferred[] | {
          action: "measure",
          targets: [.run_unit_id],
          priority: "low",
          reason: .reason,
          evidence_refs: ["profile-selection.json"],
          impact: {kind:"unknown", before_ms:.measured_ms, after_ms:null,
                   assumptions:["measured wall time only — no diagnosis was run for this unit"]}
        }]' "$profile_selection")"
      profile_actions_json="$(jq -nc --argjson a "$profile_actions_json" --argjson b "$_deferred_actions" '$a + $b')"
    fi


    # ─── P072 Step 18: resource maps and pilots become lanes ────────────────
    #
    # A lane is a PROPOSAL written into the decision artifact and rendered for a
    # human. Nothing here writes the catalog, changes a scheduler mode, or
    # approves a mapping — that separation is what keeps the audit a
    # recommendation rather than an actor.
    #
    # The grouping rule, and why each branch is what it is:
    #
    #   any `shared` resource      -> keep_serial, naming that resource. One
    #                                 shared resource is enough; a lane is only
    #                                 as safe as its least isolated member.
    #   a removable named conflict -> blocked_pending_fix. A fixed path or port
    #                                 can be fixed; saying so is more useful
    #                                 than "not parallel".
    #   an unresolved template     -> context_required, and NOT keep_serial:
    #                                 the unit was never actually evaluated, and
    #                                 filing it as "considered and kept serial"
    #                                 would claim an assessment nobody made.
    #   everything per-test/per-run-> a candidate lane, which becomes
    #                                 `proposed_parallel` ONLY with a pilot
    #                                 receipt for THAT EXACT membership.
    lanes_json='[]'
    smallest_pilot='null'
    if [[ -n "$resource_maps_dir" && -d "$resource_maps_dir" ]]; then
      # Fail-closed, on the same terms as the profile receipts. Selecting these
      # by a `schema_version` string match alone let a malformed, foreign or
      # self-contradicting artifact promote a lane — including one claiming
      # `promotion: proposed` with an empty `repetitions` array, which its own
      # schema rejects outright.
      # The audit's own inventory names the units this audit is about.
      _known_ids="$(mktemp)"
      # NOT `|| : > "$_known_ids"`. Failing to an empty id set here made every
      # resource map look like it named an unknown unit — or, worse, made the
      # validation vacuous. The inventory was schema-validated above, so a
      # failure at this point is a real one.
      jq -r '.entries[].run_unit_id' "$inventory_path" > "$_known_ids" \
        || _die 2 "could not read run_unit_ids from the validated inventory '$inventory_path'"
      if ! test_lane_validate_resource_maps "$resource_maps_dir" "$_known_ids"; then
        _die 6 "resource-map directory '$resource_maps_dir' contains an artifact that is not a valid aid-test-resource-map-v1 for this catalog — finalization stops rather than proposing lanes from evidence it could not read"
      fi
      maps_json="$(find "$resource_maps_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
                    | xargs -0 -r jq -sc '[.[]]')"
      [[ -n "$maps_json" ]] || maps_json='[]'

      pilots_json='[]'
      if [[ -n "$pilots_dir" && -d "$pilots_dir" ]]; then
        if ! test_lane_validate_pilots "$pilots_dir" "$audit_id" "$_known_ids"; then
          _die 6 "pilots directory '$pilots_dir' contains a receipt that is not a valid, this-audit, self-consistent aid-test-parallel-pilot-v1 — finalization stops rather than promoting a lane on it"
        fi
        pilots_json="$(find "$pilots_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
                        | xargs -0 -r jq -sc '[.[]]')"
        [[ -n "$pilots_json" ]] || pilots_json='[]'
      fi

      lanes_json="$(jq -nc --argjson maps "$maps_json" --argjson pilots "$pilots_json" \
                       --argjson rm "$remove_json" '
        # A unit proposed for removal is not worth arranging into a lane.
        ($maps | map(select(.run_unit_id as $u | $rm | index($u) | not))) as $m

        # Serial-with-reason: one shared resource is enough.
        | ( [ $m[] | select([.resources[] | select(.namespace == "shared")] | length > 0)
              | { lane_id: ("serial-" + (.run_unit_id | gsub("[^A-Za-z0-9]"; "-"))),
                  disposition: "keep_serial",
                  run_unit_ids: [.run_unit_id],
                  resource_basis: ([.resources[] | select(.namespace == "shared")
                                    | .kind + "/" + .namespace] | unique),
                  # The MAP is the evidence, and it carries the file:line for
                  # every entry. A bare `file:line` is not a valid evidence
                  # ref (the schema requires an audit-relative artifact path),
                  # and pointing at the artifact keeps the locations one hop
                  # away rather than losing them.
                  evidence_refs: ["resource-maps/" + (.run_unit_id | gsub("[/:]"; "_")) + ".json"] } ] ) as $serial

        # Blocked: a NAMED, removable conflict — a fixed path or a port. Worth
        # distinguishing from "shared, nothing to be done".
        | ( [ $m[] | select([.resources[] | select(.namespace == "shared"
                              and (.kind == "fixed_path" or .kind == "port"))] | length > 0)
              | .run_unit_id ] ) as $blocked_ids

        | ( [ $serial[] | if (.run_unit_ids[0] as $u | $blocked_ids | index($u))
                          then .disposition = "blocked_pending_fix" else . end ] ) as $serial

        # Never evaluated: a dependency that could not be read at all.
        | ( [ $m[] | select(.capped_at_unknown == true)
              | { lane_id: ("context-" + (.run_unit_id | gsub("[^A-Za-z0-9]"; "-"))),
                  disposition: "context_required",
                  run_unit_ids: [.run_unit_id],
                  resource_basis: ([.resources[] | .kind + "/" + .namespace] | unique | .[0:5]),
                  evidence_refs: ["resource-maps/" + (.run_unit_id | gsub("[/:]"; "_")) + ".json"] } ] ) as $context

        | ( [ $serial[] | .run_unit_ids[0] ] + [ $context[] | .run_unit_ids[0] ] ) as $spoken_for

        # Candidates: everything left, all of whose resources are private.
        | ( [ $m[] | select(.run_unit_id as $u | $spoken_for | index($u) | not)
              | select([.resources[] | select(.namespace == "unknown")] | length == 0)
              | .run_unit_id ] | sort ) as $candidates

        # One candidate lane, deterministic by sorted id so repeated runs on
        # identical input produce identical lanes.
        | ( if ($candidates | length) > 1
            then [ { lane_id: "candidate-pool",
                     disposition: "keep_serial",
                     run_unit_ids: $candidates,
                     resource_basis: ([ $m[] | select(.run_unit_id as $u | $candidates | index($u))
                                        | .resources[] | .kind + "/" + .namespace ] | unique),
                     evidence_refs: [] } ]
            else [] end ) as $candidate_lanes

        # A candidate lane is promoted ONLY by a pilot for its EXACT
        # membership. Evidence gathered for a different set promotes nothing.
        | ( [ $candidate_lanes[] as $lane
              | ( [ $pilots[] | select(.promotion == "proposed")
                    | select((.membership | sort) == ($lane.run_unit_ids | sort)) ][0] ) as $p
              | if $p == null then $lane
                else $lane
                     | .disposition = "proposed_parallel"
                     | .evidence_refs = ["pilots/" + ($p.lane_id | gsub("[/:]"; "_")) + ".json"]
                end ] ) as $candidate_lanes

        | $serial + $context + $candidate_lanes')"
      [[ -n "$lanes_json" ]] || lanes_json='[]'

      # The smallest membership whose pilot would settle the most currently
      # unsettled units. Naming it turns "parallelism is unproven" into one
      # bounded thing somebody can actually run.
      smallest_pilot="$(jq -nc --argjson lanes "$lanes_json" '
        ( [ $lanes[] | select(.disposition == "keep_serial") | select((.run_unit_ids | length) > 1) ][0] ) as $l
        | if $l == null then null
          else { run_unit_ids: $l.run_unit_ids,
                 workers: 2,
                 repeat: 2,
                 pass_criteria: [
                   "every case matches position by position between the serial and concurrent runs",
                   "both runs exit zero from a terminal job state",
                   "neither run changes its snapshot or writes outside it",
                   "every repetition satisfies all of the above, with no retry"
                 ] }
          end')"
      [[ -n "$smallest_pilot" ]] || smallest_pilot='null'
    fi

    # ─── P072 Step 5: content checks on the dispositions themselves ─────────
    #
    # Relationship to the mechanism that already ships: the wave-artifact
    # schema requires a `falsification_check` STRING on every FINDING, and
    # this script already dies when a remove/quarantine finding lacks one
    # (see the block above). That check is retained unchanged and stays at
    # the findings level. The structured `falsification` object checked here
    # lives on DISPOSITIONS, which findings do not have. Neither supersedes
    # the other: findings-level is per reported problem, disposition-level is
    # per portfolio decision. What must never happen is the two DISAGREEING
    # about the same unit, which is the cross-level check below.
    #
    # ORDER: semantic contradictions (7, 8) are evaluated before filesystem
    # resolution (6). A contradiction is a defect in the decision itself and
    # is decidable from the artifacts alone; letting a missing evidence file
    # mask it would report the shallower problem and hide the deeper one.

    # A merge whose named partner is itself scheduled for deletion produces a
    # group whose survivor does not survive.
    contradiction="$(jq -r '
      (map(select(.disposition == "remove") | .run_unit_id)) as $removed
      | [ .[] | select(.disposition == "merge")
          | . as $m | (.overlaps_with // [])[]
          | select(. as $p | $removed | index($p) != null)
          | "\($m.run_unit_id) -> \(.)" ] | .[0] // empty' <<<"$dispositions_json")"
    [[ -z "$contradiction" ]] \
      || _die 7 "contradictory dispositions: a merge names a partner that is itself marked remove ($contradiction) — the group's survivor is scheduled for deletion"

    # The two levels may differ in SHAPE; they may not CONTRADICT each other
    # about the same unit. Note what this check is deliberately NOT: an
    # "empty falsification_check alongside a remove disposition" test would be
    # unreachable, because test-audit-consolidated-findings.schema.json
    # already requires falsification_check to be non-empty on every finding —
    # a check that can never fire is decoration, not defence. The reachable
    # contradiction is a disposition proposing deletion while a finding for
    # the same unit recommends keeping it.
    cross_level="$(jq -r --argjson f "$with_ids_json" '
      (map(select(.disposition == "remove") | .run_unit_id)) as $rm
      | [ $f[] | select((.run_unit_id as $r | $rm | index($r)) != null)
                | select(.recommendation == "keep") | .run_unit_id ] | .[0] // empty' \
      <<<"$dispositions_json")"
    [[ -z "$cross_level" ]] \
      || _die 8 "unit '$cross_level' is proposed for removal by its disposition while a finding for the same unit recommends keeping it — the two levels disagree and the consolidator will not pick a side"

    # An overlaps_with naming a unit that has no disposition of its own would
    # otherwise be inserted into the published merge groups as a phantom
    # member of the proposed portfolio.
    dangling="$(jq -r '
      (map(.run_unit_id)) as $known
      | [ .[] | select(.disposition == "merge") | (.overlaps_with // [])[]
          | select(. as $p | $known | index($p) == null) ] | .[0] // empty' <<<"$dispositions_json")"
    [[ -z "$dangling" ]] \
      || _die 9 "a merge names overlap partner '$dangling', which has no disposition of its own — a merge group cannot contain a unit nobody decided"

    # An evidence_ref that names nothing is indistinguishable from no evidence.
    # The reference is resolved against the audit directory and must stay
    # inside it: an absolute path, a `..` climb, or a symlink pointing out is
    # refused rather than accepted because the file happens to exist.
    evidence_pairs="${_tmpdir}/evidence-pairs.tsv"
    jq -r '.[] | select(.disposition == "remove" or .disposition == "merge" or .disposition == "rewrite_unit")
           | [.run_unit_id, (.falsification.evidence_ref // "")] | @tsv' \
      <<<"$dispositions_json" > "$evidence_pairs" \
      || _die 1 "could not extract falsification references from the dispositions"

    out_canon="$(cd "$output_dir" && pwd -P)" || _die 1 "could not resolve --output-dir"
    while IFS=$'\t' read -r _u _ref; do
      [[ -n "$_ref" ]] \
        || _die 6 "a coverage-reducing disposition for '$_u' carries no falsification evidence_ref — 'nothing' is not a reference"
      case "$_ref" in
        /*) _die 6 "falsification evidence '$_ref' for '$_u' is an absolute path — evidence must live inside the audit directory" ;;
      esac
      _target="${out_canon}/${_ref}"
      [[ -f "$_target" ]] \
        || _die 6 "a coverage-reducing disposition for '$_u' cites falsification evidence '$_ref', which does not exist — an unresolvable reference is not evidence"
      # readlink -f, not `cd dirname && pwd -P` + basename: the latter
      # canonicalises only the DIRECTORY part, so a symlink on the final
      # component still resolved to a path inside the audit directory while
      # pointing anywhere on disk.
      _resolved="$(readlink -f "$_target")" \
        || _die 6 "could not resolve falsification evidence '$_ref' for '$_u'"
      case "$_resolved" in
        "$out_canon"/*) : ;;
        *) _die 6 "falsification evidence '$_ref' for '$_u' resolves to '$_resolved', outside the audit directory — refused" ;;
      esac
    done < "$evidence_pairs"

    # merge_groups: connected components over the overlap relation, so three
    # mutually overlapping units form ONE group of three rather than three
    # pairs. Iterated to a genuine fixed point — the loop repeats until the
    # component list stops changing, rather than relying on a fixed number of
    # passes over an array that is being mutated as it is indexed.
    merge_groups_json="$(jq -c '
      def merge_once:
        reduce .[] as $g ([];
          ([ .[] | select((. - $g) != .) ] | flatten) as $touching
          | if ($touching | length) == 0 then . + [$g]
            else [ .[] | select((. - $g) == .) ] + [ ($touching + $g) | unique ]
            end);
      def fixpoint: merge_once as $n | if $n == . then . else $n | fixpoint end;
      [ .[] | select(.disposition == "merge")
        | ([.run_unit_id] + (.overlaps_with // [])) | unique ]
      | fixpoint | map(select(length > 1)) | unique' <<<"$dispositions_json")"

    merged_surplus="$(jq '[.[] | length - 1] | add // 0' <<<"$merge_groups_json")"

    # impact_kind is the WEAKEST evidence level among the units that
    # contribute, never the strongest: one unknown cost makes the whole
    # portfolio figure unknown. A proposed merge additionally makes the AFTER
    # figure unknowable from per-unit costs — nobody has measured what the
    # merged unit costs — so a merge downgrades the claim rather than letting
    # every member's cost survive into a total that no longer describes the
    # proposed portfolio.
    impact_kind="$(jq -r '
      [ .[] | .cost.kind // "unknown" ] as $k
      | if ($k | length) == 0 then "unknown"
        elif ($k | index("unknown")) != null then "unknown"
        elif ($k | index("lower_bound")) != null then "estimated"
        else "measured" end' <<<"$dispositions_json")"
    if [[ "$merged_surplus" -gt 0 && "$impact_kind" == "measured" ]]; then
      impact_kind="estimated"
    fi

    runtime_before="null"; runtime_after="null"
    if [[ "$impact_kind" == "measured" ]]; then
      # Reachable only when every unit is `measured`, which the schema
      # guarantees carries an integer duration — so there is no absent value
      # to default here, and defaulting one would fabricate an exact figure.
      jq -e 'all(.[]; .cost.duration_ms | type == "number")' <<<"$dispositions_json" >/dev/null \
        || _die 1 "internal error: impact_kind is 'measured' but a cost.duration_ms is not a number"
      runtime_before="$(jq '[.[] | .cost.duration_ms] | add // 0' <<<"$dispositions_json")"
      runtime_after="$(jq --argjson rm "$remove_json" \
        '[.[] | select(.run_unit_id as $r | $rm | index($r) == null) | .cost.duration_ms] | add // 0' \
        <<<"$dispositions_json")"
    fi

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
      --argjson removed_n "$removed_n" \
      --argjson merge_groups "$merge_groups_json" --arg impact_kind "$impact_kind" \
      --argjson merged_surplus "$merged_surplus" \
      --argjson profile_actions "$profile_actions_json" \
      --argjson lanes "$lanes_json" --argjson smallest_pilot "$smallest_pilot" \
      --argjson rt_before "$runtime_before" --argjson rt_after "$runtime_after" '
      {schema_version:"aid-test-audit-decision-v1", audit_id:$id, audit_status:$status,
       current_runtime:{kind:"unknown", duration_ms:null, scope:$inv},
       actions:$profile_actions, parallelization:{lanes:$lanes, smallest_safe_pilot:$smallest_pilot},
       unresolved:$unresolved,
       portfolio_coverage:{inventory_count:$ic, assigned_count:$ac, disposition_count:$dc,
                           missing_run_unit_ids:$missing, duplicate_run_unit_ids:$dupes},
       portfolio_change:{current_run_units:$ic, proposed_run_units:($ic - $removed_n - $merged_surplus),
                         keep:$keep, rewrite_unit:$rewrite, merge_groups:$merge_groups, remove:$remove,
                         runtime_before_ms:$rt_before, runtime_after_ms:$rt_after,
                         impact_kind:$impact_kind}}
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
