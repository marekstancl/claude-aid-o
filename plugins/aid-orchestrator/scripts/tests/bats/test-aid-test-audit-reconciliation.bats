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
_inventory() {
  local ids=("$@")
  printf '%s\n' "${ids[@]}" | jq -R -s \
    '{schema_version:"1.0.0", run_units: (split("\n") | map(select(length>0)) | map({run_unit_id: .}))}' \
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
  printf '%s' '{"schema_version":"1.0.0","run_units":[]}' > "$INVENTORY"
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
  [[ "$output" == *"not readable as JSON"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "an inventory listing the same run unit twice is corrupt identity, not something to de-duplicate" {
  printf '%s' '{"schema_version":"1.0.0","run_units":[{"run_unit_id":"bats:a"},{"run_unit_id":"bats:a"}]}' > "$INVENTORY"
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
