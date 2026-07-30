#!/usr/bin/env bash
# aid-test-audit-write-plan-bridge.sh — P066 Step 16.
#
# Implements PM required fix 5's exact scope: durable state carries
# audit_id, verdict, recommended_action. A same-conversation "pokračuj"
# triggers the sanctioned `/aid-plan write` handoff for that record; outside
# that context the controller asks for clarification. This script is the
# validator ONLY — it never invokes `/aid-plan write` itself; that is a
# skill the controller invokes directly.
#
# --write-plan and a same-conversation continuation both resolve to this
# SAME validator call and identical verdict — there is only one check
# function; no separate code path exists for either trigger.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TAWPB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_TAWPB_LIB_DIR}/aid-test-adapter-contract.sh"
_TAWPB_FINDINGS_SCHEMA="${_TAWPB_LIB_DIR}/../../defaults/schemas/test-audit-consolidated-findings.schema.json"
_TAWPB_BRIEF_SCHEMA="${_TAWPB_LIB_DIR}/../../defaults/schemas/test-audit-plan-brief.schema.json"

_tawpb_record_file() { printf '%s/durable-record.json' "${1%/}"; }

# aid_test_audit_write_plan_bridge_persist <output_dir> <audit_id> <verdict> <recommended_action>
#   Persists the durable per-audit record (audit_id, verdict,
#   recommended_action) — the ONLY state this same-conversation convention
#   relies on (Constraint 10: never a global interceptor).
aid_test_audit_write_plan_bridge_persist() {
  local output_dir="$1" audit_id="$2" verdict="$3" recommended_action="$4"
  mkdir -p "$output_dir"
  local record_json
  record_json="$(jq -n --arg id "$audit_id" --arg v "$verdict" --arg ra "$recommended_action" \
    '{audit_id:$id, verdict:$v, recommended_action:$ra}')"
  local file="$( _tawpb_record_file "$output_dir")"
  local tmp="${file}.tmp.$$"
  printf '%s\n' "$record_json" > "$tmp" && mv "$tmp" "$file"
}

# aid_test_audit_write_plan_bridge_check <output_dir> <catalog_path>
#   Prints {ready:true, brief_path:...} or {ready:false, reason:...} —
#   NEVER invokes `/aid-plan write` itself. Checks: durable record exists;
#   verdict is "remediation recommended" (a clean/needs-measurement verdict
#   has no brief to hand off); consolidated-findings.json and
#   implementation-plan-brief.{json,md} exist and are schema-valid; every
#   cited run_unit_id still resolves in the CURRENT catalog (a stale
#   run_unit_id — the catalog changed since this audit ran — blocks the
#   handoff).
aid_test_audit_write_plan_bridge_check() {
  local output_dir="$1" catalog_path="$2"
  local record_file="$( _tawpb_record_file "$output_dir")"

  if [[ ! -f "$record_file" ]]; then
    jq -nc '{ready:false, reason:"no durable record found for this audit"}'
    return 0
  fi
  local record_json
  record_json="$(jq -e '.' "$record_file" 2>/dev/null)" || {
    jq -nc '{ready:false, reason:"durable record is not valid JSON"}'
    return 0
  }

  local verdict
  verdict="$(jq -r '.verdict' <<<"$record_json")"
  if [[ "$verdict" != "remediation recommended" ]]; then
    jq -nc --arg v "$verdict" '{ready:false, reason:("no brief: audit found nothing to fix (verdict: " + $v + ")")}'
    return 0
  fi

  local findings_path brief_json_path brief_md_path
  findings_path="${output_dir%/}/consolidated-findings.json"
  brief_json_path="${output_dir%/}/implementation-plan-brief.json"
  brief_md_path="${output_dir%/}/implementation-plan-brief.md"

  [[ -f "$findings_path" ]] || { jq -nc '{ready:false, reason:"consolidated-findings.json is missing"}'; return 0; }
  [[ -f "$brief_json_path" ]] || { jq -nc '{ready:false, reason:"implementation-plan-brief.json is missing"}'; return 0; }
  [[ -f "$brief_md_path" ]] || { jq -nc '{ready:false, reason:"implementation-plan-brief.md is missing"}'; return 0; }

  local findings_doc brief_doc
  findings_doc="$(jq -e '.' "$findings_path" 2>/dev/null)" || { jq -nc '{ready:false, reason:"consolidated-findings.json is not valid JSON"}'; return 0; }
  adapter_validate_schema "$_TAWPB_FINDINGS_SCHEMA" "$findings_doc" \
    || { jq -nc '{ready:false, reason:"consolidated-findings.json failed schema validation"}'; return 0; }

  brief_doc="$(jq -e '.' "$brief_json_path" 2>/dev/null)" || { jq -nc '{ready:false, reason:"implementation-plan-brief.json is not valid JSON"}'; return 0; }
  adapter_validate_schema "$_TAWPB_BRIEF_SCHEMA" "$brief_doc" \
    || { jq -nc '{ready:false, reason:"implementation-plan-brief.json failed schema validation"}'; return 0; }

  # Stale-BRIEF detection (Step 14's own hash) — the brief must have been
  # derived from the findings file exactly as it exists now.
  local expected_hash actual_hash
  expected_hash="sha256:$(sha256sum "$findings_path" | cut -d' ' -f1)"
  actual_hash="$(jq -r '.generated_from_hash' <<<"$brief_doc")"
  if [[ "$expected_hash" != "$actual_hash" ]]; then
    jq -nc '{ready:false, reason:"stale brief: implementation-plan-brief.json was not derived from the current consolidated-findings.json"}'
    return 0
  fi

  # Stale run_unit_id detection — every cited run_unit_id must still resolve
  # in the CURRENT catalog (the catalog may have changed since this audit ran).
  # Codex review: a missing/malformed/unparseable catalog previously fell
  # through this whole block silently and reached {ready:true} at the bottom
  # — meaning the documented "every cited run_unit_id resolves" guarantee
  # was NOT enforced whenever the catalog couldn't be read. Fail closed
  # instead: an unreadable catalog blocks the handoff just like a stale ID.
  if [[ ! -f "$catalog_path" ]]; then
    jq -nc --arg p "$catalog_path" '{ready:false, reason:("cannot verify run_unit_ids: catalog not found: " + $p)}'
    return 0
  fi
  local catalog_json
  case "$catalog_path" in
    *.json) catalog_json="$(jq -c '.' "$catalog_path" 2>/dev/null)" ;;
    *) catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null)" ;;
  esac
  if [[ -z "$catalog_json" || "$catalog_json" == "null" ]]; then
    jq -nc --arg p "$catalog_path" '{ready:false, reason:("cannot verify run_unit_ids: catalog is not valid/parseable: " + $p)}'
    return 0
  fi
  local stale_id
  stale_id="$(jq -r --argjson catalog "$catalog_json" '
    (($catalog.run_units // []) | map(.run_unit_id)) as $live |
    [.items[] | select(.run_unit_id as $r | $live | index($r) == null) | .run_unit_id] | .[0] // empty
  ' <<<"$brief_doc")"
  if [[ -n "$stale_id" ]]; then
    jq -nc --arg id "$stale_id" '{ready:false, reason:("stale run_unit_id: " + $id + " no longer resolves in the current catalog")}'
    return 0
  fi

  jq -nc --arg path "$brief_md_path" '{ready:true, brief_path:$path}'
}
