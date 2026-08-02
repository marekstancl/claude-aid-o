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
# shellcheck source=aid-test-audit-decision.sh
source "${_TAWPB_LIB_DIR}/aid-test-audit-decision.sh"
_TAWPB_FINDINGS_SCHEMA="${_TAWPB_LIB_DIR}/../../defaults/schemas/test-audit-consolidated-findings.schema.json"
_TAWPB_BRIEF_SCHEMA="${_TAWPB_LIB_DIR}/../../defaults/schemas/test-audit-plan-brief.schema.json"

_tawpb_record_file() { printf '%s/durable-record.json' "${1%/}"; }

# aid_test_audit_write_plan_bridge_persist <output_dir> <audit_id> <verdict> <recommended_action>
#   Persists the durable per-audit record (audit_id, verdict,
#   recommended_action) — the ONLY state this same-conversation convention
#   relies on (Constraint 10: never a global interceptor).
aid_test_audit_write_plan_bridge_persist() {
  local output_dir="$1" audit_id="$2" verdict="$3" recommended_action="$4" audit_mode="${5:-}"
  mkdir -p "$output_dir"
  local record_json
  # P072 Step 3 — the record carries the mode the audit ACTUALLY ran in, so
  # the bridge is not obliged to believe a mode handed to it by its caller.
  # Omitted (legacy callers) means "not recorded", which the bridge treats as
  # no corroboration rather than as agreement.
  record_json="$(jq -n --arg id "$audit_id" --arg v "$verdict" --arg ra "$recommended_action" --arg m "$audit_mode" \
    '{audit_id:$id, verdict:$v, recommended_action:$ra} + (if $m == "" then {} else {audit_mode:$m} end)')"
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
# P072 Step 3 — the third argument is the AUDIT MODE. It is optional and
# defaults to `full`, so every existing caller keeps its current behavior
# under the mode this gate applies to; `static`/`measure` callers pass their
# real mode and skip the decision gate entirely.
#
# Why the gate is mode-scoped rather than universal: a `static` audit
# produces no decision artifact BY DESIGN, so a blanket requirement would
# silently remove a working capability (`--mode static --write-plan` can
# reach ready:true today) instead of adding a safeguard. The Scope this
# implements says static and measure are untouched, and mode-scoping is how
# that promise is kept mechanically rather than only in prose.
aid_test_audit_write_plan_bridge_check() {
  local output_dir="$1" catalog_path="$2" audit_mode="${3-}"
  local record_file="$( _tawpb_record_file "$output_dir")"

  # The mode is REQUIRED and never defaulted. Defaulting either way is wrong:
  # guessing `measure` would let an omitted argument silently skip the gate
  # (fail-open), and guessing `full` would change the answer for a legacy
  # static/measure caller that never had a decision artifact to begin with.
  # Refusing to guess is the only option that neither opens the gate nor
  # invents a result.
  if [[ -z "$audit_mode" ]]; then
    jq -nc '{ready:false, reason:"audit mode not supplied — the bridge does not guess it"}'
    return 0
  fi
  case "$audit_mode" in
    static|measure|full) ;;
    *)
      jq -nc --arg m "$audit_mode" '{ready:false, reason:("unknown audit mode: " + $m)}'
      return 0
      ;;
  esac

  # The durable record, when it carries a mode, OUTRANKS the argument: the
  # record was written by the audit itself, the argument by whoever is asking
  # for the handoff. A caller cannot relabel a full audit as `measure` to
  # slip past the decision gate.
  if [[ -f "$record_file" ]]; then
    local recorded_mode
    recorded_mode="$(jq -r '.audit_mode // empty' "$record_file" 2>/dev/null || true)"
    if [[ -n "$recorded_mode" && "$recorded_mode" != "$audit_mode" ]]; then
      jq -nc --arg r "$recorded_mode" --arg a "$audit_mode" \
        '{ready:false, reason:("audit mode mismatch: the audit recorded " + $r + ", the caller claimed " + $a)}'
      return 0
    fi
  fi

  # ─── full-mode decision gate (P072 Step 3).
  # Runs BEFORE every other check: an audit that cannot state a decision is
  # not remediation-ready regardless of what its findings say, so there is
  # nothing later worth evaluating.
  if [[ "$audit_mode" == "full" ]]; then
    local decision_path="${output_dir%/}/decision.json"
    local decision_status decision_rc decision_audit_id record_audit_id

    if [[ ! -f "$decision_path" ]]; then
      jq -nc '{ready:false, reason:"decision_artifact_missing"}'
      return 0
    fi

    # `if x="$(...)"; then` rather than `x="$(...)"; rc=$?`: under the
    # caller's `set -e`, a failing command substitution inside a plain
    # assignment terminates the shell before this function can emit its
    # fail-closed JSON — the refusal would be silent.
    if decision_status="$(aid_test_audit_decision_status "$decision_path" 2>/dev/null)"; then
      decision_rc=0
    else
      decision_rc=$?
    fi
    if (( decision_rc != 0 )); then
      jq -nc --arg rc "$decision_rc" '{ready:false, reason:("decision_artifact_invalid (validator exit " + $rc + ")")}'
      return 0
    fi

    # Bind the artifact to THIS audit. Without this, a decision.json left in
    # a reused output directory by an earlier audit (--resume reuses the
    # directory) would authorize a later, undecided one.
    if [[ -f "$record_file" ]]; then
      decision_audit_id="$(jq -r '.audit_id // empty' "$decision_path" 2>/dev/null || true)"
      record_audit_id="$(jq -r '.audit_id // empty' "$record_file" 2>/dev/null || true)"
      if [[ -n "$record_audit_id" && "$decision_audit_id" != "$record_audit_id" ]]; then
        jq -nc --arg d "$decision_audit_id" --arg r "$record_audit_id" \
          '{ready:false, reason:("decision_artifact_foreign: decision belongs to audit " + $d + ", this audit is " + $r)}'
        return 0
      fi
    fi

    if [[ "$decision_status" == "incomplete" ]]; then
      jq -nc '{ready:false, reason:"audit_incomplete"}'
      return 0
    fi
    if [[ "$decision_status" != "complete" ]]; then
      jq -nc '{ready:false, reason:"decision_artifact_invalid"}'
      return 0
    fi
  fi

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
  # A real, dogfooded catalog (this repo's own 83 run_units) is large enough
  # that `--argjson catalog "$catalog_json"` on the command line hit an
  # "Argument list too long" jq failure — which then produced EMPTY stdout,
  # silently treated as "no stale run_unit_id found" (fail-OPEN on a jq
  # failure, not merely a cosmetic error). Pass the catalog via a temp file
  # and --slurpfile instead — no argv size limit, and any real jq failure
  # here now propagates as a script failure, never a silent pass-through.
  local catalog_tmp
  catalog_tmp="$(mktemp)"
  printf '%s' "$catalog_json" > "$catalog_tmp"
  local stale_id
  stale_id="$(jq -r --slurpfile catalog "$catalog_tmp" '
    (($catalog[0].run_units // []) | map(.run_unit_id)) as $live |
    [.items[] | select(.run_unit_id as $r | $live | index($r) == null) | .run_unit_id] | .[0] // empty
  ' <<<"$brief_doc")" || { rm -f "$catalog_tmp"; jq -nc '{ready:false, reason:"internal error: stale run_unit_id check failed to evaluate"}'; return 0; }
  rm -f "$catalog_tmp"
  if [[ -n "$stale_id" ]]; then
    jq -nc --arg id "$stale_id" '{ready:false, reason:("stale run_unit_id: " + $id + " no longer resolves in the current catalog")}'
    return 0
  fi

  jq -nc --arg path "$brief_md_path" '{ready:true, brief_path:$path}'
}
