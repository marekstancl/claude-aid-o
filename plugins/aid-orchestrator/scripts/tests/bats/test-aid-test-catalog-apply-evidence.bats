#!/usr/bin/env bats
# test-aid-test-catalog-apply-evidence.bats
#
# The gap this closes: the audit proved parallel safety into decision.json and
# nothing ever wrote it into the catalog, so a freshly proposed catalog came out
# with every unit `unknown` no matter how much evidence had been gathered.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  APPLY="$PLUGIN_DIR/scripts/aid-test-catalog-apply-evidence.sh"
  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  printf '%s "a" { true; }\n' '@'"test" > "$PROJ/a.bats"
  printf '%s "b" { true; }\n' '@'"test" > "$PROJ/b.bats"
  ( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name T \
    && git add -A && git commit -qm init )
  CAT="$TEST_TMPDIR/proposed.yaml"
  DEC="$TEST_TMPDIR/decision.json"
}

teardown() { teardown_test_evidence_dir; }

_unit() {   # <id> <file> <status> [sha] [digest]
  jq -nc --arg id "$1" --arg f "$2" --arg st "$3" --arg h "${4:-}" --arg d "${5:-}" '
    {run_unit_id:$id, runner:"bats", source_paths:[$f], production_surfaces:[$f],
     test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[],
     confidence:"medium",
     command:{type:"argv",argv:["bats",$f]},
     runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
     parallel:({status:$st, exclusive_resources:[], max_workers:null, internal_parallelism:false}
               + (if $h == "" then {}
                  else {provenance:{evidence_ref:"fixture", verified_at:"2026-08-01T00:00:00Z",
                                    method:"resource_map_plus_pilot",
                                    source_sha256:$h, resource_digest:$d}} end)),
     isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[],
                adapter_confidence:"static_parse"},
     recommendation:"keep", test_cases:[]}'
}
_catalog() {   # <out> <status-doc> <unit-json...>
  local out="$1" st="$2"; shift 2
  printf '%s\n' "$@" | jq -s --arg s "$st" \
    '{schema_version:"1.0.0", generated_at:"2026-08-05T00:00:00Z", status:$s,
      run_units:., source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' \
    | yq -P '.' > "$out"
}
_bind() {   # <unit-id> <catalog> -> prints "<sha>\t<digest>"
  bash -c "source '$PLUGIN_DIR/scripts/lib/aid-test-catalog-provenance.sh'
    printf '%s\t%s\n' \
      \"\$(aid_test_catalog_provenance_hash '$1' '$2' '$PROJ' 2>/dev/null)\" \
      \"\$(aid_test_catalog_provenance_resource_digest '$1' '$2' '$PROJ' 2>/dev/null)\""
}
_decision() {   # <disposition> <unit-id...>
  local disp="$1"; shift
  printf '%s\n' "$@" | jq -R -s --arg d "$disp" '
    {schema_version:"aid-test-audit-decision-v1", audit_id:"A1",
     parallelization:{lanes:[{lane_id:"lane-1", disposition:$d,
       run_unit_ids:(split("\n")|map(select(length>0))),
       resource_basis:["none"], evidence_refs:["pilots/lane-1.json"]}]}}' > "$DEC"
}

# ─── Promotion from the audit's own evidence ───────────────────────────────

@test "a proposed_parallel lane promotes its units to safe, bound to their content" {
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)" "$(_unit "bats:b" b.bats unknown)"
  _decision proposed_parallel "bats:a" "bats:b"

  run bash "$APPLY" --catalog "$CAT" --decision "$DEC" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.run_units[] | select(.run_unit_id=="bats:a") | .parallel.status' "$CAT")" = "safe" ]
  # Bound, not merely asserted — an unbound `safe` reverts to unknown on read.
  [[ "$(yq -r '.run_units[] | select(.run_unit_id=="bats:a") | .parallel.provenance.source_sha256' "$CAT")" =~ ^[0-9a-f]{64}$ ]]
  # `resource_map_plus_pilot` is the schema's own name for exactly this
  # evidence — a resource map plus a pilot for the lane's membership.
  [ "$(yq -r '.run_units[] | select(.run_unit_id=="bats:a") | .parallel.provenance.method' "$CAT")" = "resource_map_plus_pilot" ]
}

@test "keep_serial, blocked_pending_fix and context_required promote NOTHING" {
  # Three of the four lane dispositions say the opposite of safe, or say
  # nothing. Only proposed_parallel is a claim of safety.
  local d
  for d in keep_serial blocked_pending_fix context_required; do
    _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
    _decision "$d" "bats:a"
    run bash "$APPLY" --catalog "$CAT" --decision "$DEC" --project-root "$PROJ"
    [ "$status" -eq 0 ]
    [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "unknown" ]
  done
}

# ─── Carrying earlier evidence forward ──────────────────────────────────────

@test "evidence from the previous approved catalog is carried into the new one" {
  # Re-proving what is already proven costs hours and learns nothing. This is
  # what stops a complete catalog from costing the whole parallel pool.
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
  local sha dig; IFS=$'\t' read -r sha dig < <(_bind "bats:a" "$CAT")
  local prev="$TEST_TMPDIR/prev.yaml"
  _catalog "$prev" approved "$(_unit "bats:a" a.bats safe "$sha" "$dig")"

  run bash "$APPLY" --catalog "$CAT" --previous "$prev" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "safe" ]
}

@test "evidence is NOT carried when the unit's content has moved" {
  # The whole safety of carrying anything forward: the verdict must be about
  # the same content it was reached on.
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
  local prev="$TEST_TMPDIR/prev.yaml"
  _catalog "$prev" approved "$(_unit "bats:a" a.bats safe \
    "1111111111111111111111111111111111111111111111111111111111111111" \
    "2222222222222222222222222222222222222222222222222222222222222222")"

  run bash "$APPLY" --catalog "$CAT" --previous "$prev" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "unknown" ]
  [[ "$output" == *"not carried because their content moved"* ]]
}

@test "a unit the previous catalog knew but the new one does not is simply absent" {
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
  local sha dig; IFS=$'\t' read -r sha dig < <(_bind "bats:a" "$CAT")
  local prev="$TEST_TMPDIR/prev.yaml"
  _catalog "$prev" approved "$(_unit "bats:a" a.bats safe "$sha" "$dig")" \
                             "$(_unit "bats:gone" gone.bats safe "$sha" "$dig")"

  run bash "$APPLY" --catalog "$CAT" --previous "$prev" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.run_units | length' "$CAT")" = "1" ]
}

# ─── It refuses rather than publishing something unreadable ─────────────────

@test "a result that fails the catalog schema is never written" {
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
  cp "$CAT" "$TEST_TMPDIR/before.yaml"
  # Corrupt the schema_version so the output cannot validate.
  yq -i '.schema_version = 42' "$CAT"
  run bash "$APPLY" --catalog "$CAT" --project-root "$PROJ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fails the catalog schema"* ]]
}

@test "it reports what it did, in counts" {
  _catalog "$CAT" proposed "$(_unit "bats:a" a.bats unknown)"
  _decision proposed_parallel "bats:a"
  run bash "$APPLY" --catalog "$CAT" --decision "$DEC" --project-root "$PROJ"
  [[ "$output" == *"run units"* ]]
  [[ "$output" == *"proved by this audit"* ]]
}
