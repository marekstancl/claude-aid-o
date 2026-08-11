#!/usr/bin/env bash
# aid-tier: t2
# test-enforcement-registry-test-audit.sh — P066 Step 19, extended by P072 Step 22.
#
# Verifies the 3 enforcement rows this plan registers
# (test_audit_static_command_allowlist, test_audit_catalog_approval_boundary,
# test_audit_never_auto_invoked): each has the full required field set (not
# merely a subset), and each row's `source` citation resolves to real code —
# the referenced file exists, and every function name named in parentheses
# actually appears in it. A row whose source can't be resolved is exactly
# the P026 failure mode (a detector that looks wired but isn't) this
# registry exists to prevent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${PLUGIN_DIR}/defaults/enforcement-registry.yaml"
BASELINE_FIXTURE="${SCRIPT_DIR}/fixtures/enforcement-registry-baseline-pre-p066-e3.json"

REQUIRED_IDS=(
  test_audit_static_command_allowlist
  test_audit_catalog_approval_boundary
  test_audit_never_auto_invoked
  test_tier_declared
  test_tier_runner_refusal
  test_tier_declared_at_plan_time
  selector_honesty_check
)
REQUIRED_FIELDS=(id type source description instruction severity surface status verdict test)

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

registry_json="$(yq -o=json '.' "$REGISTRY" 2>/dev/null)" || {
  echo "  FAIL: $REGISTRY did not parse as YAML"
  echo "Results: 0/1 passed, 1 failed"
  exit 1
}

for id in "${REQUIRED_IDS[@]}"; do
  echo "TEST: row '$id' exists with the full required field set"
  row_json="$(jq -c --arg id "$id" '.enforcements[]? // empty | select(.id == $id)' <<<"$registry_json" 2>/dev/null)"
  if [[ -z "$row_json" ]]; then
    # Registry top-level key may not be "enforcements" — fall back to a
    # flat top-level array search.
    row_json="$(jq -c --arg id "$id" '.[] | arrays? // empty' <<<"$registry_json" 2>/dev/null)"
  fi
  if [[ -z "$row_json" ]]; then
    # Search every top-level key that holds an array for a matching id.
    row_json="$(jq -c --arg id "$id" '[.[] | select(type == "array") | .[] | select(.id == $id)] | .[0] // empty' <<<"$registry_json" 2>/dev/null)"
  fi
  if [[ -z "$row_json" || "$row_json" == "null" ]]; then
    fail_msg "row '$id' not found in $REGISTRY"
    continue
  fi
  pass_msg "row '$id' found"

  missing_fields=""
  for field in "${REQUIRED_FIELDS[@]}"; do
    val="$(jq -r --arg f "$field" '.[$f] // empty' <<<"$row_json")"
    [[ -n "$val" ]] || missing_fields="${missing_fields}${missing_fields:+, }${field}"
  done
  if [[ -n "$missing_fields" ]]; then
    fail_msg "row '$id' missing required field(s): $missing_fields"
  else
    pass_msg "row '$id' has all required fields"
  fi

  echo "TEST: row '$id' source citation resolves to real code"
  source_str="$(jq -r '.source' <<<"$row_json")"

  # Codex review: a source citing MULTIPLE files (e.g. "a.sh; b.sh (fn)")
  # previously only resolved the first whitespace-delimited token — split on
  # ';' first so every cited file gets checked, not just the first.
  IFS=';' read -r -a clauses <<<"$source_str"
  for clause in "${clauses[@]}"; do
    clause="$(sed -E 's/^\s+//; s/\s+$//' <<<"$clause")"
    [[ -z "$clause" ]] && continue
    source_file="${clause%% *}"
    resolved_path="${PLUGIN_DIR}/${source_file}"
    if [[ ! -f "$resolved_path" ]]; then
      fail_msg "row '$id' source file does not exist: $resolved_path"
      continue
    fi
    pass_msg "row '$id' source file exists: $source_file"

    # Extract every function/identifier named inside parentheses (comma or
    # semicolon separated) and confirm each appears in the source file.
    paren_content="$(sed -n 's/.*(\(.*\)).*/\1/p' <<<"$clause")"
    if [[ -n "$paren_content" ]]; then
      IFS=',' read -r -a names <<<"$paren_content"
      for raw_name in "${names[@]}"; do
        name="$(sed -E 's/^\s+//; s/\s+$//' <<<"$raw_name")"
        [[ -z "$name" ]] && continue
        # Only check bare identifier-shaped tokens (skip free-text notes).
        if [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          if grep -qF "$name" "$resolved_path"; then
            pass_msg "row '$id' function/identifier '$name' found in $source_file"
          else
            fail_msg "row '$id' function/identifier '$name' NOT found in $source_file — source citation does not resolve"
          fi
        fi
      done
    fi
  done
done

echo "TEST: no pre-existing row (per the checked-in pre-Step-19 baseline) was modified or removed"
# DECLARED AMENDMENTS (P079 Step 13). The point of this check is that a
# pre-existing row cannot be changed SILENTLY — not that a row is frozen
# forever. A row whose description or cite genuinely has to move says so here,
# with the plan that moved it and why; anything not on this list still fails.
# The list is deliberately id-only and short: it is a record, not an allowlist
# to grow.
declare -A DECLARED_AMENDMENTS=(
  # P076 Step 1/3 gave the run-mode recommendation a real landing field and a
  # first (observe-only) consumer, so the row's "changes nothing by itself"
  # sentence had become false. Amended with P076, not by this plan.
  ["gate_runtime_baseline_advisory"]="P076 Steps 1+3 — run_mode landing field + observe-only advice event"
  # P079 Step 4 repointed a cite that named nothing (`aid-fsm.sh:1739` was
  # neither the check nor the `grep -q` the row and the template both claimed)
  # and recorded that the anchor is now case-insensitive.
  ["increment_result_pass"]="P079 Step 4 (IMP-472) — stale cite repointed, case-tolerance recorded"
)
# Codex review: counting `- id:` lines only proved the registry didn't
# SHRINK below a floor — it never proved that any SPECIFIC prior row
# survived unchanged (a delete-one/add-two edit would still pass). Compare
# every baseline row's full identity-defining field set against the live
# registry instead; new rows (this step's 3 additions, or any future ones)
# are unaffected since the baseline only lists what existed before this step.
if [[ ! -f "$BASELINE_FIXTURE" ]]; then
  fail_msg "baseline fixture missing: $BASELINE_FIXTURE"
else
  baseline_count="$(jq 'length' "$BASELINE_FIXTURE")"
  live_rows_file="$(mktemp)"
  jq -c '[.enforcements[] | {id, type, source, description, instruction, severity, surface, status, verdict, test}] | sort_by(.id)' <<<"$registry_json" > "$live_rows_file"
  mismatch_ids="$(jq -r -n --slurpfile baseline "$BASELINE_FIXTURE" --slurpfile live "$live_rows_file" '
    ($live[0] | map({(.id): .}) | add) as $live_by_id |
    [$baseline[0][] | select($live_by_id[.id] != .) | .id] | .[]
  ')" || fail_msg "internal error: jq comparison against baseline fixture failed"
  rm -f "$live_rows_file"
  if [[ -n "$mismatch_ids" ]]; then
    while IFS= read -r bad_id; do
      [[ -z "$bad_id" ]] && continue
      if [[ -n "${DECLARED_AMENDMENTS[$bad_id]:-}" ]]; then
        # Declared means "this row's CONTENT was allowed to move", never "this
        # row may vanish" — a deletion is not an amendment.
        if jq -e --arg id "$bad_id" 'any(.[]; .id == $id)' <<<"$(jq -c '[.enforcements[] | {id}]' <<<"$registry_json")" >/dev/null; then
          pass_msg "pre-existing row '$bad_id' was amended, and the amendment is declared: ${DECLARED_AMENDMENTS[$bad_id]}"
        else
          fail_msg "row '$bad_id' has a declared amendment but is GONE from the registry — an amendment is not a licence to delete"
        fi
        continue
      fi
      fail_msg "pre-existing row '$bad_id' is missing or was modified relative to the pre-Step-19 baseline"
    done <<<"$mismatch_ids"
  else
    pass_msg "all $baseline_count pre-existing rows are present and byte-identical to the pre-Step-19 baseline"
  fi
fi


# ─── P072 Step 22 ───────────────────────────────────────────────────────────
#
# The registry exists because of P026: a working detector flagged correctly and
# the change was merged anyway, because nothing acted on it. A row is the
# promise that a detector has a consumer — and a promise nobody checks is the
# same failure one level up.

INTERNAL_REGISTRY="$(cd "${PLUGIN_DIR}/../.." && pwd)/docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml"

P072_ROWS=(
  test_audit_incomplete_blocks_write_plan
  test_audit_disposition_reconciliation
  test_audit_coverage_reduction_requires_falsification
  test_audit_clone_config_precondition
  test_audit_aggregate_unparsed_fails
  test_audit_inventory_arithmetic_guard
  test_audit_resource_map_shared_evidence
  test_audit_pilot_evidence_bound
  test_catalog_parallel_provenance_binding
  test_lane_single_parallel_authority
  test_audit_lane_membership_exact
  test_audit_profile_ingestion_fail_closed
  test_audit_profile_selection_owed
  test_audit_profile_supervised_execution
  test_execution_no_double_dispatch
)

_p072_field() {   # <id> <field> [registry]
  ROW_ID="$1" yq -r ".enforcements[] | select(.id == strenv(ROW_ID)) | .${2} // \"\"" \
    "${3:-$REGISTRY}" 2>/dev/null | head -1
}

echo "TEST: every P072 row exists in BOTH registries"
missing_dist=""; missing_int=""
for id in "${P072_ROWS[@]}"; do
  [[ -n "$(_p072_field "$id" id)" ]] || missing_dist="$missing_dist $id"
  [[ -n "$(_p072_field "$id" id "$INTERNAL_REGISTRY")" ]] || missing_int="$missing_int $id"
done
[[ -z "$missing_dist" ]] && pass_msg "all ${#P072_ROWS[@]} P072 rows are in the distributed registry" \
  || fail_msg "missing from the distributed registry:$missing_dist"
# A row added to one registry only is a row nobody finds from the other, which
# is why both CHANGELOGs are identical too.
[[ -z "$missing_int" ]] && pass_msg "all ${#P072_ROWS[@]} P072 rows are mirrored internally" \
  || fail_msg "missing from the internal registry:$missing_int"

echo "TEST: an ACTIVE P072 row's source resolves to a real file"
bad=""
for id in "${P072_ROWS[@]}"; do
  [[ "$(_p072_field "$id" status)" == "active" ]] || continue
  src="$(_p072_field "$id" source)"
  found=0
  while read -r token; do
    [[ -z "$token" ]] && continue
    [[ -f "${PLUGIN_DIR}/${token}" ]] && found=1
  done < <(grep -oE '(scripts|defaults)/[A-Za-z0-9_./-]+\.(sh|json|yaml|txt)' <<<"$src" || true)
  [[ "$found" -eq 1 ]] || bad="$bad $id"
done
[[ -z "$bad" ]] && pass_msg "every active P072 row cites a source file that exists" \
  || fail_msg "active rows citing a nonexistent source:$bad"

echo "TEST: an ACTIVE P072 row names a test file that exists"
bad=""
for id in "${P072_ROWS[@]}"; do
  [[ "$(_p072_field "$id" status)" == "active" ]] || continue
  t="$(_p072_field "$id" test)"
  found=0
  while read -r token; do
    [[ -z "$token" ]] && continue
    [[ -f "${PLUGIN_DIR}/${token}" ]] && found=1
  done < <(grep -oE 'scripts/tests/[A-Za-z0-9_./-]+\.(sh|bats)' <<<"$t" || true)
  [[ "$found" -eq 1 ]] || bad="$bad $id"
done
[[ -z "$bad" ]] && pass_msg "every active P072 row names a test that exists" \
  || fail_msg "active rows naming a nonexistent test:$bad"

echo "TEST: a PLANNED row carries a deadline, so it cannot sit unwired forever"
bad=""
for id in "${P072_ROWS[@]}"; do
  [[ "$(_p072_field "$id" status)" == "planned" ]] || continue
  d="$(_p072_field "$id" deadline)"
  [[ -n "$d" && "$d" != "null" ]] || bad="$bad $id"
done
[[ -z "$bad" ]] && pass_msg "every planned P072 row carries a deadline" \
  || fail_msg "planned rows with no deadline:$bad"

echo "TEST: every P072 row records its recovery behaviour"
bad=""
for id in "${P072_ROWS[@]}"; do
  r="$(_p072_field "$id" recovery)"
  [[ -n "$r" && "$r" != "null" ]] || bad="$bad $id"
done
[[ -z "$bad" ]] && pass_msg "every P072 row states what an operator does when it fires" \
  || fail_msg "rows with no stated recovery:$bad"

echo "TEST: the source check FIRES — a row citing a nonexistent file is rejected"
# Asserted against a deliberately broken row, so this cannot pass merely
# because every real row happens to be fine.
broken_found=0
while read -r token; do
  [[ -z "$token" ]] && continue
  [[ -f "${PLUGIN_DIR}/${token}" ]] && broken_found=1
done < <(grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' <<<"scripts/this-file-does-not-exist.sh" || true)
[[ "$broken_found" -eq 0 ]] \
  && pass_msg "the source check rejects a citation that does not resolve" \
  || fail_msg "the source check accepted a nonexistent file — the guard cannot fire"

echo "TEST: this plan adds no auto-invocation surface"
# test_audit_never_auto_invoked claims the audit runs only when a user asks.
# P072 must not have quietly made that false.
if grep -q "aid-audit-tests" "${PLUGIN_DIR}/scripts/aid-fsm.sh" 2>/dev/null \
   || grep -q "aid-audit-tests" "${PLUGIN_DIR}/skills/pipeline.md" 2>/dev/null; then
  fail_msg "an FSM or pipeline surface now references aid-audit-tests — never-auto-invoked is no longer true"
else
  pass_msg "no FSM or pipeline surface dispatches the audit"
fi

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
