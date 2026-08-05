#!/usr/bin/env bats
# test-aid-test-audit-reconciliation.bats — P072 Step 4.
#
# The three-way reconciliation (inventory / assignment / disposition) is what
# turns "every shard reported" into "every test was decided". Each case here
# breaks exactly one of those three in a different way and asserts the audit
# refuses to call itself complete.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  CONSOLIDATE="$PLUGIN_DIR/scripts/aid-test-audit-consolidate.sh"

  AUDIT_ID="recon-1"
  WORK="$TEST_TMPDIR/work"
  ART="$WORK/agents"
  OUT="$WORK/out"
  mkdir -p "$ART" "$OUT"

  # A real project root, so the configured threshold is read rather than guessed.
  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/.aid-o/config"
  cp "$PLUGIN_DIR/defaults/config/test-audit.yaml" "$PROJ/.aid-o/config/test-audit.yaml"

  INVENTORY="$WORK/inventory.json"
  MANIFEST="$WORK/dispatch-manifest.json"

  # A coverage-reducing disposition must cite falsification evidence that
  # actually exists — materialise the file the fixtures reference.
  mkdir -p "$OUT/mutations"
  printf '%s' '{"mutation":"flip the transition guard","caught_by":"bats:b"}'     > "$OUT/mutations/m1.json"
}

teardown() { teardown_test_evidence_dir; }

# _inventory <id...> — the discovered portfolio.
#
# This used to emit `{"schema_version":"1.0.0","run_units":[...]}`, a shape the
# real scanner has never produced and the inventory schema does not allow. The
# consolidator read `.run_units[]` to match it, so producer and consumer
# disagreed in production while every test here passed. A fixture that invents
# its own contract proves only that two pieces of test code agree.
#
# It now emits what aid-test-inventory.sh emits, and the consolidator
# schema-validates whatever it is handed — so this can never drift silently
# again.
_inventory() {
  local ids=("$@")
  printf '%s\n' "${ids[@]}" | jq -R -s \
    '{schema_version:"1.0.0",
      generated_at:"2026-08-04T00:00:00Z",
      runner_families:["bats"],
      entries: (split("\n") | map(select(length>0))
                | map({run_unit_id: ., runner:"bats", adapter:"bats", confidence:"medium"}))}' \
    > "$INVENTORY"
}

# _manifest <id...> — one shard assigned exactly these units.
_manifest() {
  local ids=("$@")
  printf '%s\n' "${ids[@]}" | jq -R -s --arg a "$AUDIT_ID" \
    '{audit_id:$a, max_concurrent_agents:1, entries:[
       {wave:1, focus:"shard_portfolio", shard_id:"shard-0",
        run_unit_ids:(split("\n")|map(select(length>0))),
        artifact_path:"agents/1-shard_portfolio-shard-0.json",
        producer_agent_dispatch_id:"d0"}]}' > "$MANIFEST"
}

# _disposition <run_unit_id> [disposition] — one complete, schema-valid record.
_disposition() {
  jq -nc --arg id "$1" --arg d "${2:-keep}" '
    {run_unit_id:$id, disposition:$d,
     behavior_claim:"guards the FSM transition table against silent reordering",
     failure_signal:"transition returns the previous state instead of the next",
     falsification:(if $d == "remove" or $d == "merge" or $d == "rewrite_unit"
                    then {method:"mutation", evidence_ref:"mutations/m1.json"}
                    else {method:"unproved"} end),
     uniqueness:"unique", layer:"unit", cheaper_layer_possible:"no",
     cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}
    + (if $d == "measure"
       then {missing_proof:"budget_exhausted",
             next_measurement:"re-run this unit alone with a 10 minute budget"}
       else {} end)'
}

# _shard_artifact <disposition-json...> — the wave-1 artifact.
_shard_artifact() {
  local dispositions=("$@") joined
  joined="$(printf '%s\n' "${dispositions[@]}" | jq -s -c '.')"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[], produced_at:"2026-08-03T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"
}

_run_full() {
  bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" \
    --mode full --inventory "$INVENTORY" --project-root "$PROJ"
}

_status() { jq -r '.audit_status' "$OUT/decision.json"; }
_reason() { jq -r '.incomplete_reason // ""' "$OUT/decision.json"; }

@test "all three counts agree: the audit is complete" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a")" "$(_disposition "bats:b")"

  run _run_full
  [ "$status" -eq 0 ]
  [ -f "$OUT/decision.json" ]
  [ "$(_status)" = "complete" ]
  [ "$(jq -r '.portfolio_coverage.inventory_count' "$OUT/decision.json")" = "2" ]
  [ "$(jq -r '.portfolio_coverage.disposition_count' "$OUT/decision.json")" = "2" ]
}

@test "a shard that emits ZERO dispositions for an assigned unit fails closed" {
  _inventory "bats:a"
  _manifest  "bats:a"
  jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
          findings:[], produced_at:"2026-08-03T00:00:00Z", producer_agent_dispatch_id:"d0"}' \
    > "$ART/1-shard_portfolio-shard-0.json"

  run _run_full
  [ "$status" -ne 0 ]
  [[ "$output" == *"no dispositions"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "dropping ONE assigned unit yields incomplete with coverage_mismatch and names the unit" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "coverage_mismatch" ]
  [ "$(jq -r '.portfolio_coverage.missing_run_unit_ids[0]' "$OUT/decision.json")" = "bats:b" ]
}

@test "duplicating one unit yields incomplete with duplicate_dispositions" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")" "$(_disposition "bats:a" "fix")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "duplicate_dispositions" ]
  [ "$(jq -r '.portfolio_coverage.duplicate_run_unit_ids[0]' "$OUT/decision.json")" = "bats:a" ]
}

@test "a disposition for a unit the inventory never discovered exits 5 and quotes the id" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")" "$(_disposition "bats:invented")"

  run _run_full
  [ "$status" -eq 5 ]
  [[ "$output" == *"bats:invented"* ]]
  [[ "$output" == *"invent"* ]]
}

@test "a portfolio where every unit is 'measure' yields incomplete, never a completed audit" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b" "measure")" \
    "$(_disposition "bats:c" "measure")" "$(_disposition "bats:d" "measure")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "unresolved_fraction_exceeded" ]
  [ "$(jq -r '.unresolved | length' "$OUT/decision.json")" = "4" ]
}

@test "each unresolved entry carries its own missing_proof and next_measurement" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b" "measure")" \
    "$(_disposition "bats:c" "measure")" "$(_disposition "bats:d" "measure")"
  _run_full

  run jq -r '.unresolved[0].missing_proof' "$OUT/decision.json"
  [ "$output" = "budget_exhausted" ]
  run jq -r '.unresolved[0].next_measurement' "$OUT/decision.json"
  [[ "$output" == *"10 minute budget"* ]]
}

@test "one 'measure' out of four stays UNDER the threshold and remains complete" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b")" \
    "$(_disposition "bats:c")" "$(_disposition "bats:d")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "complete" ]
  [ "$(jq -r '.unresolved | length' "$OUT/decision.json")" = "1" ]
}

@test "an empty inventory is incomplete with empty_inventory, never a completed audit of nothing" {
  printf '%s' '{"schema_version":"1.0.0","generated_at":"2026-08-04T00:00:00Z","runner_families":[],"entries":[]}' > "$INVENTORY"
  _manifest "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "empty_inventory" ]
}

@test "portfolio_change reflects the real remove set and the proposed count" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "remove")" "$(_disposition "bats:b")" \
    "$(_disposition "bats:c")" "$(_disposition "bats:d")"
  _run_full

  [ "$(jq -r '.portfolio_change.current_run_units' "$OUT/decision.json")" = "4" ]
  [ "$(jq -r '.portfolio_change.proposed_run_units' "$OUT/decision.json")" = "3" ]
  [ "$(jq -r '.portfolio_change.remove[0]' "$OUT/decision.json")" = "bats:a" ]
  [ "$(jq -r '.portfolio_change.keep | length' "$OUT/decision.json")" = "3" ]
}

@test "the counts are computed here, not taken from a shard's self-report" {
  # The artifact claims a bogus count via an extra findings entry; the
  # reconciliation must ignore anything the shard asserts about itself.
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$(jq -r '.portfolio_coverage.disposition_count' "$OUT/decision.json")" = "1" ]
  [ "$(jq -r '.portfolio_coverage.inventory_count' "$OUT/decision.json")" = "2" ]
}

@test "measure mode neither requires dispositions nor writes a decision artifact" {
  _inventory "bats:a"
  _manifest  "bats:a"
  jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
          findings:[], produced_at:"2026-08-03T00:00:00Z", producer_agent_dispatch_id:"d0"}' \
    > "$ART/1-shard_portfolio-shard-0.json"

  run bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "full mode without --inventory refuses rather than guessing the denominator" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode full --project-root "$PROJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--inventory is required"* ]]
}

@test "the written decision artifact validates against its own schema on read-back" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")"
  _run_full

  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-audit-decision.sh"
  run aid_test_audit_decision_read "$OUT/decision.json"
  [ "$status" -eq 0 ]
}

@test "a remove disposition without falsification evidence is rejected by the wave schema" {
  _inventory "bats:a"
  _manifest  "bats:a"
  local bad
  bad="$(_disposition "bats:a" "remove" | jq -c '.falsification = {method:"unproved"}')"
  _shard_artifact "$bad"

  run _run_full
  [ "$status" -ne 0 ]
  [[ "$output" == *"schema validation"* ]]
}

# ─── Adversarial cases (Codex review of the first cut) ──────────────────────

# _manifest2 <shardA-ids...> -- <shardB-ids...> — two shards, explicit split.
_manifest2() {
  local a=() b=() seen=0
  for x in "$@"; do
    if [[ "$x" == "--" ]]; then seen=1; continue; fi
    if [[ "$seen" -eq 0 ]]; then a+=("$x"); else b+=("$x"); fi
  done
  jq -n --arg au "$AUDIT_ID" \
    --argjson a "$(printf '%s\n' "${a[@]}" | jq -R -s 'split("\n")|map(select(length>0))')" \
    --argjson b "$(printf '%s\n' "${b[@]}" | jq -R -s 'split("\n")|map(select(length>0))')" \
    '{audit_id:$au, max_concurrent_agents:2, entries:[
       {wave:1, focus:"shard_portfolio", shard_id:"shard-0", run_unit_ids:$a,
        artifact_path:"agents/1-shard_portfolio-shard-0.json", producer_agent_dispatch_id:"d0"},
       {wave:1, focus:"shard_portfolio", shard_id:"shard-1", run_unit_ids:$b,
        artifact_path:"agents/1-shard_portfolio-shard-1.json", producer_agent_dispatch_id:"d1"}]}' \
    > "$MANIFEST"
}

_shard_artifact_n() {
  local shard="$1" dispatch="$2"; shift 2
  local joined; joined="$(printf '%s\n' "$@" | jq -s -c '.')"
  jq -n --argjson d "$joined" --arg s "$shard" --arg p "$dispatch" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:$s,
     findings:[], produced_at:"2026-08-03T00:00:00Z",
     producer_agent_dispatch_id:$p, dispositions:$d}' \
    > "$ART/1-shard_portfolio-${shard}.json"
}

@test "CROSS-SHARD: shard A decides nothing about its own unit while shard B covers it — flattened sets would match, per-shard must not" {
  # A is assigned {a,b} and emits only a. B is assigned {c} and emits {b,c}.
  # Globally {a,b,c} == {a,b,c}; per shard, A never decided b.
  _inventory "bats:a" "bats:b" "bats:c"
  _manifest2 "bats:a" "bats:b" -- "bats:c"
  _shard_artifact_n "shard-0" "d0" "$(_disposition "bats:a")"
  _shard_artifact_n "shard-1" "d1" "$(_disposition "bats:b")" "$(_disposition "bats:c")"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "coverage_mismatch" ]
  [ "$(jq -r '.portfolio_coverage.missing_run_unit_ids[0]' "$OUT/decision.json")" = "bats:b" ]
}

@test "an INCOMPLETE audit leaves no remediation brief behind" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a")"
  _run_full

  [ "$(_status)" = "incomplete" ]
  [ ! -f "$OUT/implementation-plan-brief.json" ]
  [ ! -f "$OUT/implementation-plan-brief.md" ]
}

@test "a malformed inventory is an operational failure, never silently 'empty_inventory'" {
  printf '%s' 'this is not json' > "$INVENTORY"
  _manifest "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$status" -eq 2 ]
  # The inventory is now schema-validated before any field is read, so this is
  # refused as "not a valid inventory" rather than "not readable as JSON". The
  # invariant is the same and is what this test is for: an operational failure,
  # never a silent `empty_inventory`, and never a decision artifact.
  [[ "$output" == *"not a valid aid-test-audit-inventory"* ]]
  [[ "$output" != *"empty_inventory"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "an inventory listing the same run unit twice is corrupt identity, not something to de-duplicate" {
  # Real inventory shape, duplicated entry. The previous fixture used a
  # `run_units[]` key the scanner has never emitted, so this asserted nothing
  # about a real inventory.
  printf '%s' '{"schema_version":"1.0.0","generated_at":"2026-08-04T00:00:00Z","runner_families":["bats"],"entries":[{"run_unit_id":"bats:a","runner":"bats","adapter":"bats","confidence":"medium"},{"run_unit_id":"bats:a","runner":"bats","adapter":"bats","confidence":"medium"}]}' > "$INVENTORY"
  _manifest "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$status" -eq 6 ]
  [[ "$output" == *"more than once"* ]]
}

@test "THRESHOLD BOUNDARY: exactly at max_unresolved_fraction is still complete (the value is the maximum accepted)" {
  # 1 of 4 unresolved == 0.25 == the configured maximum.
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b")" \
    "$(_disposition "bats:c")" "$(_disposition "bats:d")"

  run _run_full
  [ "$(_status)" = "complete" ]
}

@test "THRESHOLD BOUNDARY: one unit past it flips to incomplete" {
  # 2 of 4 == 0.5 > 0.25.
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b" "measure")" \
    "$(_disposition "bats:c")" "$(_disposition "bats:d")"

  run _run_full
  [ "$(_status)" = "incomplete" ]
  [ "$(_reason)" = "unresolved_fraction_exceeded" ]
}

@test "a non-numeric max_unresolved_fraction refuses rather than coercing to zero" {
  printf 'budget_minutes_default: 30\nmax_read_only_audit_agents: 4\nallowed_runners: [bats]\ndecision:\n  max_unresolved_fraction: "banana"\n' \
    > "$PROJ/.aid-o/config/test-audit.yaml"
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run _run_full
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "full mode without --project-root refuses rather than guessing where the threshold lives" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a")"

  run bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode full --inventory "$INVENTORY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--project-root is required"* ]]
}

# ─── P072 Step 5: disposition content ──────────────────────────────────────

@test "a remove citing falsification evidence that does not exist exits 6" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  local bad
  bad="$(_disposition "bats:a" "remove" | jq -c '.falsification.evidence_ref = "mutations/nope.json"')"
  _shard_artifact "$bad" "$(_disposition "bats:b")"

  run _run_full
  [ "$status" -eq 6 ]
  [[ "$output" == *"mutations/nope.json"* ]]
  [[ "$output" == *"not evidence"* ]]
}

@test "a merge naming a partner that is itself marked remove exits 7" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  local m r
  m="$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"]')"
  r="$(_disposition "bats:b" "remove")"
  _shard_artifact "$m" "$r"

  run _run_full
  [ "$status" -eq 7 ]
  [[ "$output" == *"bats:a -> bats:b"* ]]
}

@test "THREE mutually overlapping units form ONE merge group of three, not three pairs" {
  _inventory "bats:a" "bats:b" "bats:c"
  _manifest  "bats:a" "bats:b" "bats:c"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"]')" \
    "$(_disposition "bats:b" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:c"]')" \
    "$(_disposition "bats:c" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:a"]')"
  _run_full

  [ "$(jq -r '.portfolio_change.merge_groups | length' "$OUT/decision.json")" = "1" ]
  [ "$(jq -r '.portfolio_change.merge_groups[0] | length' "$OUT/decision.json")" = "3" ]
}

@test "two disjoint overlap pairs form TWO separate merge groups" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"]')" \
    "$(_disposition "bats:b")" \
    "$(_disposition "bats:c" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:d"]')" \
    "$(_disposition "bats:d")"
  _run_full

  [ "$(jq -r '.portfolio_change.merge_groups | length' "$OUT/decision.json")" = "2" ]
}

@test "impact_kind is the WEAKEST evidence level present, never the strongest" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" | jq -c '.cost={kind:"measured",duration_ms:1000}')" \
    "$(_disposition "bats:b" | jq -c '.cost={kind:"unknown",duration_ms:null}')"
  _run_full

  [ "$(jq -r '.portfolio_change.impact_kind' "$OUT/decision.json")" = "unknown" ]
  [ "$(jq -r '.portfolio_change.runtime_before_ms' "$OUT/decision.json")" = "null" ]
}

@test "all costs measured yields measured runtimes, and removal lowers the after figure" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "remove" | jq -c '.cost={kind:"measured",duration_ms:1000}')" \
    "$(_disposition "bats:b" | jq -c '.cost={kind:"measured",duration_ms:250}')"
  _run_full

  [ "$(jq -r '.portfolio_change.impact_kind' "$OUT/decision.json")" = "measured" ]
  [ "$(jq -r '.portfolio_change.runtime_before_ms' "$OUT/decision.json")" = "1250" ]
  [ "$(jq -r '.portfolio_change.runtime_after_ms' "$OUT/decision.json")" = "250" ]
}

@test "one lower_bound cost downgrades the portfolio figure to estimated" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" | jq -c '.cost={kind:"measured",duration_ms:1000}')" \
    "$(_disposition "bats:b" | jq -c '.cost={kind:"lower_bound",duration_ms:3600000}')"
  _run_full

  [ "$(jq -r '.portfolio_change.impact_kind' "$OUT/decision.json")" = "estimated" ]
}

@test "a keep with uniqueness unproved reconciles fine and is not treated as a defect" {
  _inventory "bats:a"
  _manifest  "bats:a"
  _shard_artifact "$(_disposition "bats:a" | jq -c '.uniqueness="unproved"')"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(_status)" = "complete" ]
}

@test "a remove disposition contradicted by a finding that recommends keep exits 8" {
  # The two levels have different shapes and neither supersedes the other, but
  # they must not disagree about whether the same deletion is supported.
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  local joined
  joined="$(printf '%s\n' "$(_disposition "bats:a" "remove")" "$(_disposition "bats:b")" | jq -s -c '.')"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[{run_unit_id:"bats:a", category:"coverage", severity:"medium",
                evidence_refs:["r1"], recommendation:"keep", confidence:"low",
                falsification_check:"reverting the guard still fails bats:b"}],
     produced_at:"2026-08-03T00:00:00Z", producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"

  run _run_full
  [ "$status" -eq 8 ]
  [[ "$output" == *"bats:a"* ]]
  [[ "$output" == *"disagree"* ]]
}

@test "the findings-level falsification_check rejection still fires unchanged" {
  # Pre-existing P066 behaviour: a remove FINDING with no falsification_check
  # dies before any report is produced. Step 5 must not have displaced it.
  _inventory "bats:a"
  _manifest  "bats:a"
  local joined
  joined="$(printf '%s\n' "$(_disposition "bats:a")" | jq -s -c '.')"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[{run_unit_id:"bats:a", category:"coverage", severity:"high",
                evidence_refs:["r1"], recommendation:"remove", confidence:"high",
                falsification_check:""}],
     produced_at:"2026-08-03T00:00:00Z", producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"

  run _run_full
  [ "$status" -ne 0 ]
  # The consolidator's OWN check must be what fired — not a schema rejection
  # that happens to mention the same field name.
  [[ "$output" == *"rejected before report"* ]]
}

# ─── Step 5 hardening (Codex review) ───────────────────────────────────────

@test "a FIVE-node overlap chain collapses into ONE merge group" {
  _inventory "bats:a" "bats:b" "bats:c" "bats:d" "bats:e"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d" "bats:e"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"]')" \
    "$(_disposition "bats:b" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:c"]')" \
    "$(_disposition "bats:c" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:d"]')" \
    "$(_disposition "bats:d" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:e"]')" \
    "$(_disposition "bats:e")"
  _run_full

  [ "$(jq -r '.portfolio_change.merge_groups | length' "$OUT/decision.json")" = "1" ]
  [ "$(jq -r '.portfolio_change.merge_groups[0] | length' "$OUT/decision.json")" = "5" ]
}

@test "a unit overlapping ITSELF does not create a spurious group" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:a","bats:b"]')" \
    "$(_disposition "bats:b")"
  _run_full

  [ "$(jq -r '.portfolio_change.merge_groups | length' "$OUT/decision.json")" = "1" ]
  [ "$(jq -r '.portfolio_change.merge_groups[0] | length' "$OUT/decision.json")" = "2" ]
}

@test "a merge naming a partner nobody decided exits 9 rather than publishing a phantom member" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:ghost"]')" \
    "$(_disposition "bats:b")"

  run _run_full
  [ "$status" -eq 9 ]
  [[ "$output" == *"bats:ghost"* ]]
}

@test "an ABSOLUTE falsification evidence path is refused" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "remove" | jq -c '.falsification.evidence_ref="/etc/passwd"')" \
    "$(_disposition "bats:b")"

  run _run_full
  # Rejected by the schema's own anchor, before the filesystem is touched.
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "evidence resolving OUTSIDE the audit directory via a symlink is refused" {
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  printf '%s' 'outside' > "$TEST_TMPDIR/outside-evidence.json"
  ln -s "$TEST_TMPDIR/outside-evidence.json" "$OUT/mutations/escape.json"
  _shard_artifact \
    "$(_disposition "bats:a" "remove" | jq -c '.falsification.evidence_ref="mutations/escape.json"')" \
    "$(_disposition "bats:b")"

  run _run_full
  [ "$status" -eq 6 ]
  [[ "$output" == *"outside the audit directory"* ]]
}

@test "a semantic contradiction is reported even when the evidence file is also missing" {
  # Exit 7 (the decision contradicts itself) must not be masked by exit 6
  # (a file is absent) — the deeper defect wins.
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"] | .falsification.evidence_ref="mutations/gone.json"')" \
    "$(_disposition "bats:b" "remove" | jq -c '.falsification.evidence_ref="mutations/gone.json"')"

  run _run_full
  [ "$status" -eq 7 ]
}

@test "a merge reduces proposed_run_units by the collapsed members" {
  _inventory "bats:a" "bats:b" "bats:c"
  _manifest  "bats:a" "bats:b" "bats:c"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"]')" \
    "$(_disposition "bats:b")" \
    "$(_disposition "bats:c")"
  _run_full

  [ "$(jq -r '.portfolio_change.current_run_units' "$OUT/decision.json")" = "3" ]
  # 3 units, one merge group of 2 -> the pair becomes one unit.
  [ "$(jq -r '.portfolio_change.proposed_run_units' "$OUT/decision.json")" = "2" ]
}

@test "a proposed merge downgrades a fully measured portfolio to estimated" {
  # Nobody has measured what the MERGED unit costs, so the after figure is
  # no longer a measurement of the proposed portfolio.
  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _shard_artifact \
    "$(_disposition "bats:a" "merge" | jq -c '.uniqueness="overlaps" | .overlaps_with=["bats:b"] | .cost={kind:"measured",duration_ms:100}')" \
    "$(_disposition "bats:b" | jq -c '.cost={kind:"measured",duration_ms:200}')"
  _run_full

  [ "$(jq -r '.portfolio_change.impact_kind' "$OUT/decision.json")" = "estimated" ]
  [ "$(jq -r '.portfolio_change.runtime_after_ms' "$OUT/decision.json")" = "null" ]
}

# ─── P072 Step 13: profiles become actions, honestly ───────────────────────

# A receipt the production ingestion will actually accept: schema-valid, bound
# to this audit, and hashed against a real evidence log sitting beside it.
# Fixtures that skip the bindings would test a path production never takes.
_profile() {
  # <run_unit_id> <bucket> <complete> [elapsed] [lower_bound] [audit_id]
  local id="$1" bucket="$2" complete="$3" elapsed="${4:-1000}" lb="${5:-null}"
  local aid="${6:-$AUDIT_ID}"
  local base; base="$(echo "$id" | tr '/:' '__')"
  mkdir -p "$OUT/profiles"
  printf '1..1\nok 1 something in 5ms\n' > "$OUT/profiles/${base}.log"
  local sha; sha="$(sha256sum "$OUT/profiles/${base}.log" | cut -d' ' -f1)"
  local probe="null"
  case "$bucket" in
    cost_rises_across_run|undecidable)
      probe='"re-run the fastest and slowest bands from a fresh root, and again reversed"' ;;
  esac
  jq -nc --arg id "$id" --arg b "$bucket" --arg aid "$aid" --arg sha "$sha" \
         --arg log "${base}.log" --argjson probe "$probe" \
         --argjson c "$complete" --argjson e "$elapsed" --argjson lb "$lb" '
    {schema_version:"aid-test-profile-v1", run_unit_id:$id, runner:"bats",
     complete:$c, incomplete_reason:(if $c then null else "deadline" end),
     elapsed_ms:$e, exit_code:0, budget_seconds:60,
     lower_bound_ms:$lb, timing:{cases:[],planned:0,truncated:false},
     cost_curve:{detected:($b=="cost_rises_across_run")},
     source_signals:{}, duplicate_membership:{gates:[],duplicated:($b=="duplicate_membership")},
     root_cause:{bucket:$b, confidence:(if $c then "medium" else "low" end),
                 reason:("diagnosed as " + $b + " with cited evidence"), next_probe:$probe},
     evidence_log:$log, evidence_log_sha256:$sha, cancelled:false,
     audit_id:$aid,
     job:{id:"j-1", state:"terminal_pass", live_log:"/dev/null"}}' \
    > "$OUT/profiles/${base}.json"
}

_selection() {
  # <audit_id> then pairs of <selected_id> — deferred entries via _selection_deferred
  local aid="$1"; shift
  jq -nc --arg aid "$aid" --args '
    {schema_version:"aid-test-profile-selection-v1", audit_id:$aid,
     policy:{profile_trigger_ms:120000, profile_max_units:3},
     measured_units: ($ARGS.positional | length),
     selected: [$ARGS.positional[] | {run_unit_id:., measured_ms:200000,
                                      reason:"measured 200000ms, at or above the trigger"}],
     deferred: []}' -- "$@" > "$OUT/profile-selection.json"
}

_run_full_profiled() {
  bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" \
    --mode full --inventory "$INVENTORY" --project-root "$PROJ" \
    --profiles-dir "$OUT/profiles" "$@"
}

@test "STEP 13: a rising cost curve maps to MEASURE — not fix, and not split" {
  # `cost_rises_across_run` says later cases cost more than earlier ones. It
  # does NOT say state accumulated: the cases may simply be heavier work, and
  # the two call for opposite remedies. An earlier build mapped this to `fix`
  # on the strength of a cause it had not established.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "cost_rises_across_run" true
  _run_full_profiled

  [ "$(jq -r '.actions[0].action' "$OUT/decision.json")" = "measure" ]
  [ "$(jq -r '.actions[0].targets[0]' "$OUT/decision.json")" = "bats:a" ]
  run jq -r '[.actions[].action] | index("split")' "$OUT/decision.json"
  [ "$output" = "null" ]
  run jq -r '[.actions[].action] | index("fix")' "$OUT/decision.json"
  [ "$output" = "null" ]
}

@test "STEP 13: an INCOMPLETE profile yields impact.kind unknown with the lower bound in before_ms" {
  # Presenting a lower bound as a before-and-after pair is the invented saving
  # the adversarial contract forbids.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "undecidable" false 60010 60010
  _run_full_profiled

  [ "$(jq -r '.actions[0].impact.kind' "$OUT/decision.json")" = "unknown" ]
  [ "$(jq -r '.actions[0].impact.before_ms' "$OUT/decision.json")" = "60010" ]
  [ "$(jq -r '.actions[0].impact.after_ms' "$OUT/decision.json")" = "null" ]
  [ "$(jq -r '.actions[0].action' "$OUT/decision.json")" = "measure" ]
  [ "$(jq -r '.actions[0].priority' "$OUT/decision.json")" = "high" ]
  # and the lower bound is labelled as one, not left to be read as a total
  [[ "$(jq -r '.actions[0].impact.assumptions[0]' "$OUT/decision.json")" == *"lower bound"* ]]
}

@test "STEP 13: an incomplete run may NOT carry a high-confidence growth diagnosis" {
  # The cases an unfinished run never reached are exactly the ones that would
  # settle whether cost rose because state accumulated. Claiming `high` from
  # the prefix is the failure this capability exists to remove — so the schema
  # rejects the receipt outright rather than letting it reach an action.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "cost_rises_across_run" false 60010 60010
  local f="$OUT/profiles/bats_a.json"
  jq '.root_cause.confidence = "high"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  # re-hash is unnecessary: the log is untouched, only the receipt changed
  run _run_full_profiled
  [ "$status" -ne 0 ]
  [[ "$output" == *"aid-test-profile-v1"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13: a LOST job is an incomplete profile, never a measurement" {
  # `lost` is aid-job.sh's word for a wrapper that died before writing a
  # terminal record. It is a third thing, distinct from a deadline and from an
  # operator cancel, and none of the three may become a number.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "undecidable" false 30000 30000
  local f="$OUT/profiles/bats_a.json"
  jq '.incomplete_reason = "lost" | .job.state = "lost"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  _run_full_profiled
  [ "$(jq -r '.actions[0].action' "$OUT/decision.json")" = "measure" ]
  [ "$(jq -r '.actions[0].impact.kind' "$OUT/decision.json")" = "unknown" ]
  [ "$(jq -r '.actions[0].impact.after_ms' "$OUT/decision.json")" = "null" ]
}

@test "STEP 13: duplicate_membership yields an ESTIMATED saving with its assumption stated" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "duplicate_membership" true 4200
  _run_full_profiled

  [ "$(jq -r '.actions[0].impact.kind' "$OUT/decision.json")" = "estimated" ]
  [ "$(jq -r '.actions[0].impact.before_ms' "$OUT/decision.json")" = "4200" ]
  [ "$(jq -r '.actions[0].impact.assumptions | length' "$OUT/decision.json")" = "1" ]
}

@test "STEP 13: a completed profile with no dominant cause claims NO numeric benefit" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true 900
  _run_full_profiled

  [ "$(jq -r '.actions[0].action' "$OUT/decision.json")" = "keep_serial" ]
  [ "$(jq -r '.actions[0].impact.kind' "$OUT/decision.json")" = "unknown" ]
  [ "$(jq -r '.actions[0].impact.before_ms' "$OUT/decision.json")" = "null" ]
}

@test "STEP 13: no cost action is emitted for a unit already proposed for REMOVAL" {
  # Optimising a test scheduled for deletion is wasted work.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a" "remove")" "$(_disposition "bats:b")"
  _profile "bats:a" "cost_rises_across_run" true
  _profile "bats:b" "test_body" true
  _run_full_profiled

  run jq -r '[.actions[].targets[]] | index("bats:a")' "$OUT/decision.json"
  [ "$output" = "null" ]
  run jq -r '[.actions[].targets[]] | index("bats:b")' "$OUT/decision.json"
  [ "$output" != "null" ]
}

@test "STEP 13: every emitted action cites its evidence log" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "cost_rises_across_run" true
  _run_full_profiled

  [ "$(jq -r '.actions[0].evidence_refs | length' "$OUT/decision.json")" -ge 1 ]
  [[ "$(jq -r '.actions[0].evidence_refs[0]' "$OUT/decision.json")" == profiles/* ]]
}

# ─── Fail-closed ingestion ─────────────────────────────────────────────────
#
# Every case below used to produce an empty action list and a successful exit,
# because the ingestion pipeline ended in `|| echo '[]'`. An empty action list
# renders identically to "nothing needed doing", so a corrupt input read as a
# clean bill of health.

@test "STEP 13 FAIL-CLOSED: an unparseable receipt HALTS finalization" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  printf 'not json at all{' > "$OUT/profiles/bats_a.json"

  run _run_full_profiled
  [ "$status" -ne 0 ]
  [[ "$output" == *"not parseable JSON"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13 FAIL-CLOSED: a receipt missing a required field HALTS finalization" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  local f="$OUT/profiles/bats_a.json"
  jq 'del(.root_cause)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  run _run_full_profiled
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13 FAIL-CLOSED: a FOREIGN audit's receipt is refused, not absorbed" {
  # A profiles directory is a directory, not provenance. Without the audit-id
  # binding, a receipt left behind by an earlier audit reads as current
  # evidence for this one.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true 1000 null "some-other-audit"

  run _run_full_profiled
  [ "$status" -ne 0 ]
  [[ "$output" == *"some-other-audit"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13 FAIL-CLOSED: an evidence log edited after the run HALTS finalization" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  printf '1..1\nok 1 something ENTIRELY different in 5000ms\n' > "$OUT/profiles/bats_a.log"

  run _run_full_profiled
  [ "$status" -ne 0 ]
  [[ "$output" == *"changed after the run"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13 FAIL-CLOSED: an unknown root-cause bucket is refused, never defaulted" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  local f="$OUT/profiles/bats_a.json"
  jq '.root_cause.bucket = "something_invented"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  run _run_full_profiled
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

# ─── The selection is the obligation ───────────────────────────────────────

@test "STEP 13 SELECTION: a selected unit with NO receipt HALTS finalization" {
  # Otherwise the selector is a detector with no enforcement: it names three
  # slow suites, nobody profiles them, and the audit finalizes looking exactly
  # as complete as one that had.
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  mkdir -p "$OUT/profiles"
  _selection "$AUDIT_ID" "bats:a"

  run _run_full_profiled --profile-selection "$OUT/profile-selection.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:a"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STEP 13 SELECTION: a selection from ANOTHER audit is refused" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  _selection "not-this-audit" "bats:a"

  run _run_full_profiled --profile-selection "$OUT/profile-selection.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not-this-audit"* ]]
}

@test "STEP 13 SELECTION: a satisfied selection finalizes normally" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  _profile "bats:a" "test_body" true
  _selection "$AUDIT_ID" "bats:a"

  run _run_full_profiled --profile-selection "$OUT/profile-selection.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.actions[0].action' "$OUT/decision.json")" = "keep_serial" ]
}

@test "STEP 13 SELECTION: a DEFERRED unit is reported with its measured cost, not dropped" {
  # A unit over the trigger that did not fit under the ceiling is a known,
  # quantified gap. Leaving it out of the findings is how a gap goes invisible.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard_artifact "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _profile "bats:a" "test_body" true
  jq -nc --arg aid "$AUDIT_ID" '
    {schema_version:"aid-test-profile-selection-v1", audit_id:$aid,
     policy:{profile_trigger_ms:120000, profile_max_units:1},
     measured_units:2,
     selected:[{run_unit_id:"bats:a", measured_ms:300000, reason:"over the trigger"}],
     deferred:[{run_unit_id:"bats:b", measured_ms:180000,
                reason:"over the 120000ms trigger but past the 1-unit ceiling for this audit — not diagnosed, and not dismissed"}]}' \
    > "$OUT/profile-selection.json"

  run _run_full_profiled --profile-selection "$OUT/profile-selection.json"
  [ "$status" -eq 0 ]
  local deferred
  deferred="$(jq -c '[.actions[] | select(.targets[0] == "bats:b")][0]' "$OUT/decision.json")"
  [ "$(jq -r '.action' <<<"$deferred")" = "measure" ]
  [ "$(jq -r '.impact.before_ms' <<<"$deferred")" = "180000" ]
  [ "$(jq -r '.impact.kind' <<<"$deferred")" = "unknown" ]
  [[ "$(jq -r '.reason' <<<"$deferred")" == *"not diagnosed"* ]]
}

@test "STEP 13: with no profiles directory the audit still completes, with no actions" {
  _inventory "bats:a"; _manifest "bats:a"; _shard_artifact "$(_disposition "bats:a")"
  run _run_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.actions | length' "$OUT/decision.json")" = "0" ]
  [ "$(_status)" = "complete" ]
}

# ─── Big portfolios must not die on argv ────────────────────────────────────

@test "a portfolio larger than a single argv argument still consolidates" {
  # A real audit of this repository produced 158 447 bytes of findings and a
  # larger aggregate of resource maps. `--argjson` puts a whole JSON value in
  # ONE command-line argument, and Linux caps a single argument at 128 KB
  # (MAX_ARG_STRLEN) regardless of ARG_MAX — so consolidation died with
  # "Argument list too long". Because this script is the only mandatory closing
  # step and it fails closed, the audit produced no decision artifact at all.
  #
  # The same defect was fixed in aid-test-resource-map.sh in 2.70.2 and never
  # swept for here. Every fixture in this file is small, which is exactly why
  # nothing caught it — so this one is deliberately not small.
  local n=400 i
  local -a ids=()
  local dfile="$WORK/dispositions.ndjson"; : > "$dfile"
  for ((i=0; i<n; i++)); do
    ids+=("bats:unit-with-a-deliberately-long-identifier-so-the-set-is-big-$i")
    _disposition "bats:unit-with-a-deliberately-long-identifier-so-the-set-is-big-$i" keep >> "$dfile"
  done
  _inventory "${ids[@]}"
  _manifest "${ids[@]}"
  # Assembled from a FILE, because `_shard_artifact` passes its arguments to jq
  # and would hit the very limit this test exists to cover — the fixture running
  # into it too is a fair demonstration of how easy it is to reach.
  jq -s '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
          findings:[], produced_at:"2026-08-03T00:00:00Z",
          producer_agent_dispatch_id:"d0", dispositions:.}' \
    "$dfile" > "$ART/1-shard_portfolio-shard-0.json"

  local size; size="$(wc -c < "$ART/1-shard_portfolio-shard-0.json")"
  echo "wave artifact: ${size}B (limit na jeden argument je 131072)" >&3
  [ "$size" -gt 131072 ]

  run _run_full
  [ "$status" -eq 0 ]
  [ -f "$OUT/decision.json" ]
  # The whole point: a decision artifact exists and accounts for every unit.
  [ "$(jq -r '[.. | objects | select(has("inventory_count")) | .inventory_count] | first' "$OUT/decision.json")" = "$n" ]
}

# ─── A finding's proposal reaches the decision, with identity and honesty ───

_disposition_with_proposal() {   # <unit-id>
  jq -nc --arg id "$1" '
    {run_unit_id:$id, disposition:"keep",
     behavior_claim:"guards the FSM transition table",
     failure_signal:"transition returns the previous state",
     falsification:{method:"unproved"},
     uniqueness:"unique", layer:"unit", cheaper_layer_possible:"no",
     cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}'
}

_finding_with_proposal() {   # <unit-id> <recommendation> [conflicts_json]
  jq -nc --arg id "$1" --arg rec "$2" --argjson conf "${3:-[]}" '
    {run_unit_id:$id, category:"parallel_safety", severity:"high",
     evidence_refs:["resource-maps/x.json"],
     recommendation:$rec, confidence:"high",
     falsification_check:"delete the fixed path write and the map goes clean",
     proposal:{
       change:"a.bats:359 writes $ROOT/.aid-o under a fixed path; allocate a per-test temp dir",
       effort:{bucket:"S", verify_bucket:"M", repeat_count:14,
               facts:["1 file","no production code","no new helper"]},
       benefit:{kind:"unknown", critical_path_ms:null,
                risk_note:null, assumptions:[]},
       conflicts_with:$conf}}'
}

@test "a finding with a proposal becomes a decision action carrying change, effort and identity" {
  _inventory "bats:a"
  _manifest "bats:a"
  local art="$ART/1-shard_portfolio-shard-0.json"
  printf '%s\n' "$(_disposition_with_proposal "bats:a")" | jq -s -c '.' > "$TEST_TMPDIR/d.json"
  jq -n --argjson d "$(cat "$TEST_TMPDIR/d.json")" \
        --argjson f "[$(_finding_with_proposal "bats:a" fix)]" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:$f, produced_at:"2026-08-05T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' > "$art"

  run _run_full
  [ "$status" -eq 0 ]
  local act
  act="$(jq -c '[.actions[] | select(.change != null)] | .[0]' "$OUT/decision.json")"
  [ "$(jq -r '.action' <<<"$act")" = "fix" ]
  [[ "$(jq -r '.change' <<<"$act")" == *"a.bats:359"* ]]
  [ "$(jq -r '.effort.bucket' <<<"$act")" = "S" ]
  [ "$(jq -r '.effort.verify_bucket' <<<"$act")" = "M" ]
  # An unknown benefit stays unknown — never upgraded to a number.
  [ "$(jq -r '.impact.kind' <<<"$act")" = "unknown" ]
  [ "$(jq -r '.impact.after_ms' <<<"$act")" = "null" ]
  # Identity: 16 hex, stable across runs.
  [[ "$(jq -r '.proposal_id' <<<"$act")" =~ ^[0-9a-f]{16}$ ]]
}

@test "a previously declined proposal is marked, kept, and never silently re-litigated" {
  _inventory "bats:a"
  _manifest "bats:a"
  local art="$ART/1-shard_portfolio-shard-0.json"
  jq -n --argjson d "[$(_disposition_with_proposal "bats:a")]" \
        --argjson f "[$(_finding_with_proposal "bats:a" fix)]" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:$f, produced_at:"2026-08-05T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' > "$art"

  # First run to learn the id, then decline it.
  run _run_full
  [ "$status" -eq 0 ]
  local pid; pid="$(jq -r '[.actions[] | select(.change != null)] | .[0].proposal_id' "$OUT/decision.json")"
  mkdir -p "$PROJ/.aid-o/config"
  printf 'declined:\n  - "%s"\n' "$pid" > "$PROJ/.aid-o/config/test-audit-decisions.yaml"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.actions[] | select(.change != null)] | .[0].declined_previously' "$OUT/decision.json")" = "true" ]
}

@test "a remove and a fix sharing a target carry the conflict on BOTH sides" {
  _inventory "bats:a"
  _manifest "bats:a"
  local art="$ART/1-shard_portfolio-shard-0.json"
  jq -n --argjson d "[$(_disposition_with_proposal "bats:a")]" \
        --argjson f "[$(_finding_with_proposal "bats:a" fix), $(_finding_with_proposal "bats:a" remove)]" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:$f, produced_at:"2026-08-05T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' > "$art"

  run _run_full
  [ "$status" -eq 0 ]
  local n_with_conf
  n_with_conf="$(jq -r '[.actions[] | select(.change != null) | select((.conflicts_with // []) | length > 0)] | length' "$OUT/decision.json")"
  [ "$n_with_conf" -eq 2 ]
}

@test "a finding with NO proposal produces no action — a bare verb is not remediation" {
  _inventory "bats:a"
  _manifest "bats:a"
  local art="$ART/1-shard_portfolio-shard-0.json"
  jq -n --argjson d "[$(_disposition_with_proposal "bats:a")]" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[{run_unit_id:"bats:a", category:"parallel_safety", severity:"high",
                evidence_refs:["x"], recommendation:"fix", confidence:"low",
                falsification_check:"none"}],
     produced_at:"2026-08-05T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' > "$art"

  run _run_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.actions[] | select(.change != null)] | length' "$OUT/decision.json")" = "0" ]
}
