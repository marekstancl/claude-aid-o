#!/usr/bin/env bats
# test-aid-test-audit-lanes.bats — P072 Step 18.
#
# Lanes are PROPOSALS in the decision artifact. Nothing here writes the
# catalog, changes a scheduler mode, or approves a mapping — the audit
# recommends, it does not act.
#
# The cases below pin the four dispositions and, above all, the rule that
# separates a proposal from a wish: a lane reaches `proposed_parallel` only on
# a pilot receipt for its OWN membership.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  CONSOLIDATE="$PLUGIN_DIR/scripts/aid-test-audit-consolidate.sh"

  AUDIT_ID="lanes-1"
  WORK="$TEST_TMPDIR/work"; ART="$WORK/agents"; OUT="$WORK/out"
  MAPS="$OUT/resource-maps"; PILOTS="$OUT/pilots"
  mkdir -p "$ART" "$OUT" "$MAPS" "$PILOTS"

  PROJ="$TEST_TMPDIR/proj"; mkdir -p "$PROJ/.aid-o/config"
  cp "$PLUGIN_DIR/defaults/config/test-audit.yaml" "$PROJ/.aid-o/config/test-audit.yaml"

  INVENTORY="$WORK/inventory.json"; MANIFEST="$WORK/dispatch-manifest.json"
}

teardown() { teardown_test_evidence_dir; }

_inventory() {
  printf '%s\n' "$@" | jq -R -s \
    '{schema_version:"1.0.0", run_units: (split("\n") | map(select(length>0)) | map({run_unit_id: .}))}' \
    > "$INVENTORY"
}
_manifest() {
  printf '%s\n' "$@" | jq -R -s --arg a "$AUDIT_ID" \
    '{audit_id:$a, max_concurrent_agents:1, entries:[
       {wave:1, focus:"shard_portfolio", shard_id:"shard-0",
        run_unit_ids:(split("\n")|map(select(length>0))),
        artifact_path:"agents/1-shard_portfolio-shard-0.json",
        producer_agent_dispatch_id:"d0"}]}' > "$MANIFEST"
}
_disposition() {
  jq -nc --arg id "$1" '
    {run_unit_id:$id, disposition:"keep",
     behavior_claim:"guards the transition table against silent reordering",
     failure_signal:"transition returns the previous state instead of the next",
     falsification:{method:"unproved"}, uniqueness:"unique", layer:"unit",
     cheaper_layer_possible:"no", cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}'
}
_shard() {
  local joined; joined="$(printf '%s\n' "$@" | jq -s -c '.')"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[], produced_at:"2026-08-03T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"
}

# _map <run_unit_id> <capped:true|false> <kind/namespace>...
_map() {
  local id="$1" capped="$2"; shift 2
  local res="[]"
  for pair in "$@"; do
    res="$(jq -c --arg k "${pair%%/*}" --arg n "${pair##*/}" \
      '. + [{kind:$k, namespace:$n, detail:"d", location:"tests/x.bats:1"}]' <<<"$res")"
  done
  local unres="[]"
  [[ "$capped" == "true" ]] && unres='[{"directive":"$X/h.bash","location":"tests/x.bats:1","reason":"path is computed from variables this cannot expand"}]'
  jq -nc --arg id "$id" --argjson res "$res" --argjson unres "$unres" --argjson c "$capped" \
    '{schema_version:"aid-test-resource-map-v1", run_unit_id:$id, source_paths:["tests/x.bats"],
      follow_depth_cap:3, resources:$res, unresolved_sources:$unres, capped_at_unknown:$c}' \
    > "$MAPS/$(echo "$id" | tr '/:' '__').json"
}

# _pilot <lane_id> <promotion> <run_unit_id>...
#
# Produces a receipt the consolidator will actually ACCEPT: a real membership
# hash over the sorted membership, and one clean repetition per `repeat`. The
# first version of this helper emitted `promotion: proposed` with an empty
# `repetitions` array and a zero hash — an artifact the pilot's own schema
# rejects — and the consolidator promoted a lane from it anyway. Fixtures that
# take a shortcut production forbids test a path production does not have.
_pilot() {
  local lane="$1" promo="$2"; shift 2
  local sha; sha="$(printf '%s\n' "$@" | sort | tr '\n' '\0' | sha256sum | cut -d' ' -f1)"
  local reps='[]'
  if [[ "$promo" == "proposed" ]]; then
    reps="$(jq -nc '[{index:1, verdict:"match",
      serial:{duration_ms:20, exit_code:0, job_state:"terminal_pass", results:[], dirty_paths:[], escaped_paths:[]},
      parallel:{duration_ms:10, exit_code:0, job_state:"terminal_pass", results:[], dirty_paths:[], escaped_paths:[]}}]')"
  fi
  jq -nc --arg l "$lane" --arg p "$promo" --arg sha "$sha" --argjson reps "$reps" \
    --arg aid "$AUDIT_ID" --args \
    '{schema_version:"aid-test-parallel-pilot-v1", lane_id:$l, audit_id:$aid,
      target_root:"/tmp/clone", membership:($ARGS.positional | sort),
      membership_sha256:$sha,
      workers:2, repeat:1, promotion:$p, reason:"fixture receipt for lane construction",
      benefit_ms:5000, noise_threshold_ms:2000, failing_repetition:(if $p == "refused" then 1 else null end),
      repetitions:$reps, parallelism:{available:true, note:"GNU parallel is present"}}' \
    -- "$@" > "$PILOTS/$lane.json"
}

_run() {
  bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" \
    --mode full --inventory "$INVENTORY" --project-root "$PROJ" \
    --resource-maps-dir "$MAPS" --pilots-dir "$PILOTS" "$@"
}

_lanes() { jq -c '.parallelization.lanes' "$OUT/decision.json"; }
_lane_for() { jq -c --arg u "$1" '[.parallelization.lanes[] | select(.run_unit_ids | index($u))][0]' "$OUT/decision.json"; }

# ─── The four dispositions ─────────────────────────────────────────────────

@test "a unit with a SHARED resource yields keep_serial naming that resource" {
  # One shared resource is enough: a lane is only as safe as its least
  # isolated member.
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" false "lock/shared" "temp_path/per-test"
  _run
  local l; l="$(_lane_for "bats:a")"
  [ "$(jq -r '.disposition' <<<"$l")" = "keep_serial" ]
  [[ "$(jq -r '.resource_basis | join(",")' <<<"$l")" == *"lock/shared"* ]]
}

@test "a keep_serial lane cites the LOCATION that justifies it" {
  # "not parallel-safe" with no locus sends nobody anywhere.
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" false "lock/shared"
  _run
  [ "$(jq -r '.evidence_refs | length' <<<"$(_lane_for "bats:a")")" -ge 1 ]
}

@test "a NAMED removable conflict yields blocked_pending_fix, not merely keep_serial" {
  # A fixed path or a port can be fixed. Saying so is more useful than saying
  # "not parallel".
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" false "fixed_path/shared"
  _run
  [ "$(jq -r '.disposition' <<<"$(_lane_for "bats:a")")" = "blocked_pending_fix" ]
}

@test "a unit whose dependencies could not be READ yields context_required" {
  # It was never actually evaluated. Filing it as "considered and kept serial"
  # would claim an assessment nobody made.
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" true "temp_path/unknown"
  _run
  local l; l="$(_lane_for "bats:a")"
  [ "$(jq -r '.disposition' <<<"$l")" = "context_required" ]
  [ "$(jq -r '.evidence_refs | length' <<<"$l")" -ge 1 ]
}

# ─── The promotion rule ────────────────────────────────────────────────────

@test "candidates with no pilot stay keep_serial — a candidate is not a proposal" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _run
  [ "$(jq -r '[.parallelization.lanes[] | select(.disposition == "proposed_parallel")] | length' "$OUT/decision.json")" = "0" ]
}

@test "a pilot for the EXACT membership promotes the lane" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" proposed "bats:a" "bats:b"
  _run
  local l; l="$(_lane_for "bats:a")"
  [ "$(jq -r '.disposition' <<<"$l")" = "proposed_parallel" ]
  [ "$(jq -r '.evidence_refs | length' <<<"$l")" -ge 1 ]
}

@test "a pilot for a DIFFERENT membership promotes nothing" {
  # Evidence gathered for one set may not promote another. This is the whole
  # difference between a proposal and a wish.
  _inventory "bats:a" "bats:b" "bats:c"; _manifest "bats:a" "bats:b" "bats:c"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")" "$(_disposition "bats:c")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _map "bats:c" false "temp_path/per-test"
  # A pilot covering only two of the three candidates.
  _pilot "candidate-pool" proposed "bats:a" "bats:b"
  _run
  [ "$(jq -r '[.parallelization.lanes[] | select(.disposition == "proposed_parallel")] | length' "$OUT/decision.json")" = "0" ]
}

@test "a REFUSED pilot promotes nothing" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" refused "bats:a" "bats:b"
  _run
  [ "$(jq -r '[.parallelization.lanes[] | select(.disposition == "proposed_parallel")] | length' "$OUT/decision.json")" = "0" ]
}

@test "a safe_not_worthwhile pilot promotes nothing either" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" safe_not_worthwhile "bats:a" "bats:b"
  _run
  [ "$(jq -r '[.parallelization.lanes[] | select(.disposition == "proposed_parallel")] | length' "$OUT/decision.json")" = "0" ]
}

# ─── Determinism and disjointness ──────────────────────────────────────────

@test "lane assignment is DETERMINISTIC across repeated runs on identical input" {
  # Repeated runs must produce identical lanes, or the disjointness check would
  # fire on an artefact of the grouping rather than on a real overlap.
  _inventory "bats:z" "bats:a" "bats:m"; _manifest "bats:z" "bats:a" "bats:m"
  _shard "$(_disposition "bats:z")" "$(_disposition "bats:a")" "$(_disposition "bats:m")"
  _map "bats:z" false "temp_path/per-test"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:m" false "temp_path/per-test"
  _run
  local first; first="$(_lanes)"
  rm -f "$OUT/decision.json"
  _run
  [ "$(_lanes)" = "$first" ]
}

@test "a unit belongs to exactly ONE lane" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "lock/shared"
  _map "bats:b" false "temp_path/per-test"
  _run
  local all uniq
  all="$(jq -r '[.parallelization.lanes[].run_unit_ids[]] | length' "$OUT/decision.json")"
  uniq="$(jq -r '[.parallelization.lanes[].run_unit_ids[]] | unique | length' "$OUT/decision.json")"
  [ "$all" = "$uniq" ]
}

# ─── Honest empty states ───────────────────────────────────────────────────

@test "every unit sharing a resource yields ZERO proposed lanes, and that is complete" {
  # Parallelism not being supportable is a valid, complete result — not an
  # incomplete audit.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "lock/shared"
  _map "bats:b" false "aid_state/shared"
  _run
  [ "$(jq -r '[.parallelization.lanes[] | select(.disposition == "proposed_parallel")] | length' "$OUT/decision.json")" = "0" ]
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "complete" ]
}

@test "with no resource maps at all the audit still completes, proposing nothing" {
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  bash "$CONSOLIDATE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" \
    --mode full --inventory "$INVENTORY" --project-root "$PROJ"
  [ "$(jq -r '.parallelization.lanes | length' "$OUT/decision.json")" = "0" ]
  [ "$(jq -r '.parallelization.smallest_safe_pilot' "$OUT/decision.json")" = "null" ]
}

@test "a unit proposed for REMOVAL is not arranged into a lane" {
  # Arranging a test scheduled for deletion is wasted work.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  # A coverage-reducing proposal must name which retained test still catches
  # the defect — `unproved` is not an argument for deletion, and the wave
  # artifact schema enforces that.
  local d_remove
  d_remove="$(jq -nc '{run_unit_id:"bats:a", disposition:"remove",
     behavior_claim:"guards the transition table against silent reordering",
     failure_signal:"transition returns the previous state instead of the next",
     falsification:{method:"mutation", evidence_ref:"evidence/mutation-a.txt"},
     uniqueness:"unique", layer:"unit",
     cheaper_layer_possible:"no", cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}')"
  mkdir -p "$OUT/evidence"; echo "mutation probe output" > "$OUT/evidence/mutation-a.txt"
  _shard "$d_remove" "$(_disposition "bats:b")"
  _map "bats:a" false "lock/shared"
  _map "bats:b" false "lock/shared"
  _run
  [ "$(jq -r '[.parallelization.lanes[].run_unit_ids[]] | index("bats:a")' "$OUT/decision.json")" = "null" ]
}

# ─── The next bounded step ─────────────────────────────────────────────────

@test "smallest_safe_pilot names a membership and its pass criteria" {
  # It turns "parallelism is unproven" into one bounded thing somebody can run.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _run
  local sp; sp="$(jq -c '.parallelization.smallest_safe_pilot' "$OUT/decision.json")"
  [ "$sp" != "null" ]
  [ "$(jq -r '.run_unit_ids | length' <<<"$sp")" -ge 2 ]
  [ "$(jq -r '.pass_criteria | length' <<<"$sp")" -ge 1 ]
  [ "$(jq -r '.workers' <<<"$sp")" -ge 2 ]
  [ "$(jq -r '.repeat' <<<"$sp")" -ge 1 ]
}

# ─── Lane inputs are fail-closed ───────────────────────────────────────────
#
# Selecting these by a `schema_version` string match alone let a malformed,
# foreign or self-contradicting artifact promote a lane.

@test "FAIL-CLOSED: a pilot claiming `proposed` with NO repetitions halts the audit" {
  # Its own schema rejects this outright, and the consolidator used to promote
  # a lane from it regardless.
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  local sha; sha="$(printf '%s\n' "bats:a" "bats:b" | sort | tr '\n' '\0' | sha256sum | cut -d' ' -f1)"
  jq -nc --arg sha "$sha" --arg aid "$AUDIT_ID" \
    '{schema_version:"aid-test-parallel-pilot-v1", lane_id:"candidate-pool", audit_id:$aid,
      target_root:"/tmp/clone", membership:["bats:a","bats:b"], membership_sha256:$sha,
      workers:2, repeat:1, promotion:"proposed", reason:"a benefit with no evidence at all",
      benefit_ms:5000, noise_threshold_ms:2000, failing_repetition:null, repetitions:[],
      parallelism:{available:true, note:"GNU parallel is present"}}' > "$PILOTS/candidate-pool.json"

  run _run
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "FAIL-CLOSED: a pilot whose membership hash does not cover its membership halts" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" proposed "bats:a" "bats:b"
  jq '.membership_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$PILOTS/candidate-pool.json" > "$PILOTS/tmp" && mv "$PILOTS/tmp" "$PILOTS/candidate-pool.json"

  run _run
  [ "$status" -ne 0 ]
  [[ "$output" == *"membership"* ]]
}

@test "FAIL-CLOSED: a pilot from ANOTHER audit halts rather than promoting" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" proposed "bats:a" "bats:b"
  jq '.audit_id = "some-older-audit"' "$PILOTS/candidate-pool.json" > "$PILOTS/tmp" \
    && mv "$PILOTS/tmp" "$PILOTS/candidate-pool.json"

  run _run
  [ "$status" -ne 0 ]
  [[ "$output" == *"some-older-audit"* ]]
}

@test "FAIL-CLOSED: an unparseable resource map halts the audit" {
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" false "temp_path/per-test"
  printf '{ truncated' > "$MAPS/bats_a.json"
  run _run
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "FAIL-CLOSED: a resource map for a unit outside this audit halts" {
  # A map for a unit the inventory never heard of describes something else.
  _inventory "bats:a"; _manifest "bats:a"; _shard "$(_disposition "bats:a")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:stranger" false "temp_path/per-test"
  run _run
  [ "$status" -ne 0 ]
  [[ "$output" == *"stranger"* ]]
}

@test "FAIL-CLOSED: a pilot for a unit outside this audit halts" {
  _inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _map "bats:a" false "temp_path/per-test"
  _map "bats:b" false "temp_path/per-test"
  _pilot "candidate-pool" proposed "bats:a" "bats:outsider"
  run _run
  [ "$status" -ne 0 ]
  [[ "$output" == *"outsider"* ]]
}
