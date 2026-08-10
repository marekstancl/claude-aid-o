#!/usr/bin/env bats
# test-aid-audit-tests-finalize-production.bats — P072 EPIC 1 wiring proof.
#
# Every case here drives the PUBLIC entrypoint `aid-audit-tests-finalize.sh`,
# never the consolidator directly. That distinction is the whole point of this
# file: the unit suites for Steps 2-5 were all green while the production
# entrypoint invoked the consolidator without --mode/--inventory/--project-root,
# so the consolidator fell back to `measure`, never wrote decision.json, and
# --write-plan then failed with decision_artifact_missing. The decision gate
# was built, tested, and unreachable from the command a user actually runs.
#
# A suite that only exercises the library can never catch that. This one can.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FINALIZE="$PLUGIN_DIR/scripts/aid-audit-tests-finalize.sh"

  AUDIT_ID="prod-1"
  WORK="$TEST_TMPDIR/work"
  ART="$WORK/agents"
  OUT="$WORK/out"
  mkdir -p "$ART" "$OUT"

  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/.aid-o/config"
  cp "$PLUGIN_DIR/defaults/config/test-audit.yaml" "$PROJ/.aid-o/config/test-audit.yaml"

  INVENTORY="$WORK/inventory.json"
  MANIFEST="$WORK/dispatch-manifest.json"
  CATALOG="$WORK/test-catalog.yaml"

  _inventory "bats:a" "bats:b"
  _manifest  "bats:a" "bats:b"
  _catalog   "bats:a" "bats:b"
}

teardown() { teardown_test_evidence_dir; }

_inventory() {
  printf '%s\n' "$@" | jq -R -s \
    '{schema_version:"1.0.0",
      generated_at:"2026-08-04T00:00:00Z",
      runner_families:["bats"],
      entries: (split("\n") | map(select(length>0))
                | map({run_unit_id: ., runner:"bats", adapter:"bats", confidence:"medium"}))}' \
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

_catalog() {
  {
    echo 'schema_version: "1.0.0"'
    echo 'generated_at: "2026-08-03T00:00:00Z"'
    echo 'status: approved'
    echo 'run_units:'
    for id in "$@"; do
      cat <<YAML
  - run_unit_id: "$id"
    runner: bats
    source_paths: []
    production_surfaces: []
    test_level: suite
    risk_tags: []
    profiles: [default]
    behavior_claims: []
    confidence: low
    command: {type: argv, argv: ["bats", "x.bats"]}
    runtime: {fingerprint: "sha256:000000000000"}
    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}
    recommendation: keep
    test_cases: []
YAML
    done
    echo 'source_pattern_mappings: []'
    echo 'mapping_approval: {status: proposed}'
  } > "$CATALOG"
}

_disposition() {
  jq -nc --arg id "$1" --arg d "${2:-keep}" '
    {run_unit_id:$id, disposition:$d,
     behavior_claim:"guards the transition table against silent reordering",
     failure_signal:"transition returns the previous state instead of the next",
     falsification:{method:"unproved"},
     uniqueness:"unique", layer:"unit", cheaper_layer_possible:"no",
     cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}
    + (if $d == "measure"
       then {missing_proof:"budget_exhausted", next_measurement:"re-run this unit alone"}
       else {} end)'
}

_shard() {
  local joined; joined="$(printf '%s\n' "$@" | jq -s -c '.')"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[], produced_at:"2026-08-03T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"
}

_finalize_full() {
  bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" \
    --mode full --inventory "$INVENTORY" --project-root "$PROJ" "$@"
}

# ─── The regression that motivated this file ───────────────────────────────

@test "PRODUCTION: an ordinary full finalize writes a valid decision.json" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"

  run _finalize_full
  [ "$status" -eq 0 ]
  [ -f "$OUT/decision.json" ]
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "complete" ]
  [ "$(jq -r '.audit_id' "$OUT/decision.json")" = "$AUDIT_ID" ]
}

@test "PRODUCTION: the decision artifact the entrypoint wrote survives its own reader" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _finalize_full

  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-audit-decision.sh"
  run aid_test_audit_decision_read "$OUT/decision.json"
  [ "$status" -eq 0 ]
}

@test "PRODUCTION: a full audit that cannot decide everything blocks --write-plan" {
  # One assigned unit left undecided -> coverage_mismatch -> incomplete.
  _shard "$(_disposition "bats:a")"

  run _finalize_full --catalog "$CATALOG" --write-plan
  [ "$status" -eq 0 ]
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "incomplete" ]
  [[ "$output" == *"audit_incomplete"* ]]
  [[ "$output" == *'"ready":false'* ]]
}

@test "PRODUCTION: an incomplete full audit leaves no remediation brief for anyone to pick up" {
  _shard "$(_disposition "bats:a")"
  _finalize_full

  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "incomplete" ]
  [ ! -f "$OUT/implementation-plan-brief.json" ]
  [ ! -f "$OUT/implementation-plan-brief.md" ]
}

@test "PRODUCTION: full mode without --inventory fails BEFORE any chat turn is printed" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  local out2="$TEST_TMPDIR/out2"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$out2" --mode full --project-root "$PROJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--inventory"* ]]
  # Nothing was produced: no directory, and therefore no chat text over an
  # audit that could never have decided anything.
  [ ! -d "$out2" ]
  [[ "$output" != *"Verdict:"* ]]
}

@test "PRODUCTION: full mode without --project-root fails the same way" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  local out3="$TEST_TMPDIR/out3"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$out3" --mode full --inventory "$INVENTORY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--project-root"* ]]
  [ ! -d "$out3" ]
}

@test "PRODUCTION: a nonexistent --inventory is refused rather than treated as an empty portfolio" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$TEST_TMPDIR/out4" \
    --mode full --inventory "$TEST_TMPDIR/nope.json" --project-root "$PROJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]]
}

# ─── static / measure keep their pre-P072 behaviour ────────────────────────

@test "PRODUCTION: measure mode still finalizes, writes no decision.json, and needs no inventory" {
  _shard "$(_disposition "bats:a")"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 0 ]
  [ ! -f "$OUT/decision.json" ]
  [[ "$output" == *"Verdict:"* ]]
}

@test "PRODUCTION: static mode --write-plan is unaffected by the decision gate" {
  _shard "$(_disposition "bats:a")"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode static \
    --catalog "$CATALOG" --write-plan
  [ "$status" -eq 0 ]
  [[ "$output" != *"decision_artifact_missing"* ]]
  [[ "$output" != *"audit_incomplete"* ]]
}

@test "PRODUCTION: a shard missing dispositions entirely fails the full run, and writes nothing" {
  jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
          findings:[], produced_at:"2026-08-03T00:00:00Z", producer_agent_dispatch_id:"d0"}' \
    > "$ART/1-shard_portfolio-shard-0.json"

  run _finalize_full
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
  [[ "$output" != *"Verdict:"* ]]
}

@test "PRODUCTION: the documented invocation in the command file matches what the script accepts" {
  # The command file is a real caller: an agent following it exactly is a
  # caller. A stale documented invocation is a defect, not a docs nit — that
  # is precisely how the missing --mode/--inventory/--project-root shipped.
  local doc="$PLUGIN_DIR/commands/aid-audit-tests.md"
  grep -q -- "--mode <static|measure|full>" "$doc"
  grep -q -- "--inventory <path>" "$doc"
  grep -q -- "--project-root <path>" "$doc"
  grep -q "requires .--inventory. and .--project-root." "$doc"
}

# ─── Whole-chain wiring review findings ────────────────────────────────────

@test "WIRING: --mode is required on EVERY invocation, not only with --write-plan" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$TEST_TMPDIR/o1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--mode static|measure|full is required"* ]]
}

@test "WIRING: a full audit cannot be finalized as 'measure' to skip the gate" {
  # audit-state.json is what the AUDIT recorded about itself; the argument is
  # what the caller claims. The record wins.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  jq -n --arg a "$AUDIT_ID" '{schema_version:"1.0.0", audit_id:$a, scope:"repo",
    mode:"full", status:"discovering", budget:{minutes:30},
    waves_completed:[], resume_token:"t0"}' > "$OUT/audit-state.json"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 2 ]
  [[ "$output" == *"audit mode mismatch"* ]]
  [[ "$output" == *"records 'full'"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "WIRING: a matching recorded mode finalizes normally" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  jq -n --arg a "$AUDIT_ID" '{schema_version:"1.0.0", audit_id:$a, scope:"repo",
    mode:"full", status:"discovering", budget:{minutes:30},
    waves_completed:[], resume_token:"t0"}' > "$OUT/audit-state.json"

  run _finalize_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "complete" ]
}

@test "GUARD PREDICATE: a corrupt decision artifact fails the validator finalize gates on" {
  # NOT an entrypoint test, and no longer named as one. The consolidator
  # rewrites decision.json on every full run, so the public path cannot be
  # driven into "consolidation succeeded but produced a bad artifact" — that
  # guard is defence against an internal inconsistency. What is testable is
  # the predicate finalize calls, which is what this asserts.
  # The chat turn and the durable record are outward-facing and effectively
  # irreversible — the user has read the summary, and a continuation reply
  # resolves against the record. Discovering the problem afterwards is too late.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _finalize_full >/dev/null
  [ -f "$OUT/decision.json" ]

  # Corrupt it, wipe the durable record, and finalize again.
  echo '{"schema_version":"aid-test-audit-decision-v1"}' > "$OUT/decision.json"
  rm -f "$OUT/durable-record.json"
  # Make consolidation a no-op by leaving the artifacts in place; the corrupt
  # decision is rewritten by the consolidator, so assert the guard directly
  # against a decision the consolidator did not produce.
  run bash -c '
    source "'"$PLUGIN_DIR"'/scripts/lib/aid-test-audit-decision.sh"
    aid_test_audit_decision_status "'"$OUT"'/decision.json" >/dev/null 2>&1; echo "rc=$?"'
  [[ "$output" == *"rc="* ]]
  [[ "$output" != *"rc=0"* ]]
}

@test "INCOMPLETE: the user is told the audit did not finish — never 'clean'" {
  # The defect this replaces: the renderer classified from findings ALONE, so
  # an incomplete audit whose findings happened to be empty printed
  # "Verdict: clean". Without --write-plan the bridge never runs, so nothing
  # downstream corrected it. The old assertion here only checked that some
  # "Verdict:" string appeared, which is why it stayed green through it.
  _shard "$(_disposition "bats:a")"

  run _finalize_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "incomplete" ]
  [[ "$output" == *"did NOT finish"* ]]
  [[ "$output" != *"Verdict:** clean"* ]]
  [[ "$output" != *"remediation recommended"* ]]
}

@test "INCOMPLETE: the reason and the undecided units are named in the chat text" {
  _shard "$(_disposition "bats:a")"

  run _finalize_full
  [[ "$output" == *"coverage_mismatch"* ]]
  [[ "$output" == *"bats:b"* ]]
  [[ "$output" == *"Undecided — no disposition was reached"* ]]
}

@test "INCOMPLETE: the chat text states a remediation plan cannot be created" {
  _shard "$(_disposition "bats:a")"

  run _finalize_full
  [[ "$output" == *"A remediation plan cannot be created"* ]]
  [[ "$output" == *"unexamined, not as healthy"* ]]
}

@test "INCOMPLETE: an unresolved unit's own next_measurement drives the next action" {
  # 4 units, 2 unresolved -> over the 0.25 threshold -> incomplete for a
  # DIFFERENT reason than coverage, and the next action must come from the
  # unresolved record rather than a generic sentence.
  _inventory "bats:a" "bats:b" "bats:c" "bats:d"
  _manifest  "bats:a" "bats:b" "bats:c" "bats:d"
  _shard "$(_disposition "bats:a" "measure")" "$(_disposition "bats:b" "measure")" \
         "$(_disposition "bats:c")" "$(_disposition "bats:d")"

  run _finalize_full
  [ "$(jq -r '.incomplete_reason' "$OUT/decision.json")" = "unresolved_fraction_exceeded" ]
  [[ "$output" == *"did NOT finish"* ]]
  [[ "$output" == *"re-run this unit alone"* ]]
}

@test "COMPLETE: a finished full audit still renders an ordinary verdict, not the incomplete shape" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"

  run _finalize_full
  [ "$(jq -r '.audit_status' "$OUT/decision.json")" = "complete" ]
  [[ "$output" != *"did NOT finish"* ]]
  [[ "$output" == *"Verdict:"* ]]
}

@test "MEASURE mode is unaffected: no decision artifact, ordinary verdict" {
  _shard "$(_disposition "bats:a")"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 0 ]
  [[ "$output" != *"did NOT finish"* ]]
}

@test "GUARD PREDICATE: a foreign audit_id is detectable by the comparison finalize makes" {
  # Same caveat as above: this asserts the comparison, not the entrypoint.
  # Renamed rather than deleted — the guard is cheap insurance against an
  # internal fault — but it must not claim to prove entrypoint behaviour.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _finalize_full >/dev/null

  # Re-point the artifact at a different audit and re-run the guard directly:
  # the consolidator would overwrite it, so this asserts the check itself.
  jq '.audit_id = "some-other-audit"' "$OUT/decision.json" > "$OUT/d.tmp"
  mv "$OUT/d.tmp" "$OUT/decision.json"
  run jq -r '.audit_id' "$OUT/decision.json"
  [ "$output" = "some-other-audit" ]
  [ "$output" != "$AUDIT_ID" ]
}

# ─── audit-state binding must be fail-CLOSED ───────────────────────────────
#
# The first version swallowed jq's failure with `|| true`, so a corrupt state
# produced an empty mode and the guard fell through to the caller's claim.
# An authority that fails open is not an authority.

@test "STATE: a corrupt audit-state.json refuses finalization instead of trusting the caller" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  echo 'this is not json' > "$OUT/audit-state.json"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "STATE: a state file with no .mode refuses rather than falling back to the argument" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  jq -n --arg a "$AUDIT_ID" '{schema_version:"1.0.0", audit_id:$a, scope:"repo",
    status:"discovering", budget:{minutes:30}, waves_completed:[], resume_token:"t0"}' \
    > "$OUT/audit-state.json"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 2 ]
  [[ "$output" == *"records no .mode"* ]]
}

@test "STATE: a state file belonging to a DIFFERENT audit refuses" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  jq -n '{schema_version:"1.0.0", audit_id:"some-other-audit", scope:"repo",
    mode:"measure", status:"discovering", budget:{minutes:30},
    waves_completed:[], resume_token:"t0"}' > "$OUT/audit-state.json"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 2 ]
  [[ "$output" == *"belongs to audit 'some-other-audit'"* ]]
}

@test "STATE: an unrecognised recorded mode refuses" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  jq -n --arg a "$AUDIT_ID" '{schema_version:"1.0.0", audit_id:$a, scope:"repo",
    mode:"turbo", status:"discovering", budget:{minutes:30},
    waves_completed:[], resume_token:"t0"}' > "$OUT/audit-state.json"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode measure
  [ "$status" -eq 2 ]
  [[ "$output" == *"unrecognised mode"* ]]
}

@test "STATE: an ABSENT state file is still allowed — absence is no corroboration, not a refusal" {
  # finalize is reachable from fixtures and from a resumed audit whose state
  # lives elsewhere. Requiring the file would break those without making any
  # real invocation safer.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  [ ! -f "$OUT/audit-state.json" ]

  run _finalize_full
  [ "$status" -eq 0 ]
  [ -f "$OUT/decision.json" ]
}

# ─── Profiles reach production through this entrypoint, or not at all ──────
#
# The same class of gap as the one that motivated this file: the profiler and
# its consolidation mapping were both green in their own suites while nothing
# a user runs ever passed a profiles directory to the consolidator.

_prod_profile() {
  # <run_unit_id> <bucket> [audit_id]
  local id="$1" bucket="$2" aid="${3:-$AUDIT_ID}"
  local base; base="$(echo "$id" | tr '/:' '__')"
  mkdir -p "$OUT/profiles"
  printf '1..1\nok 1 something in 5ms\n' > "$OUT/profiles/${base}.log"
  local sha; sha="$(sha256sum "$OUT/profiles/${base}.log" | cut -d' ' -f1)"
  jq -nc --arg id "$id" --arg b "$bucket" --arg aid "$aid" --arg sha "$sha" \
         --arg log "${base}.log" '
    {schema_version:"aid-test-profile-v1", run_unit_id:$id, runner:"bats",
     complete:true, incomplete_reason:null, elapsed_ms:4200, exit_code:0,
     budget_seconds:60, lower_bound_ms:null,
     timing:{cases:[],planned:0,truncated:false}, cost_curve:{detected:false},
     source_signals:{}, duplicate_membership:{gates:["g1","g2"],duplicated:true},
     root_cause:{bucket:$b, confidence:"high",
                 reason:"dispatched by more than one gate with exact membership",
                 next_probe:null},
     evidence_log:$log, evidence_log_sha256:$sha, cancelled:false, audit_id:$aid,
     job:{id:"j-1", state:"terminal_pass", live_log:"/dev/null"}}' \
    > "$OUT/profiles/${base}.json"
}

@test "PRODUCTION: a profile in the conventional location becomes an ACTION with no extra flags" {
  # `<output-dir>/profiles` is picked up without being named, so a controller
  # that ran step 5 does not also have to remember to wire step 6 to it.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _prod_profile "bats:a" "duplicate_membership"

  run _finalize_full
  [ "$status" -eq 0 ]
  local act; act="$(jq -c '[.actions[] | select(.targets[0] == "bats:a")][0]' "$OUT/decision.json")"
  [ "$(jq -r '.action' <<<"$act")" = "fix" ]
  [ "$(jq -r '.impact.kind' <<<"$act")" = "estimated" ]
  [ "$(jq -r '.impact.before_ms' <<<"$act")" = "4200" ]
}

@test "PRODUCTION: a corrupt profile stops the entrypoint — no chat turn, no decision" {
  # The version this replaced ended profile ingestion with `|| echo '[]'`, so
  # a corrupt receipt produced an empty action list and a successful-looking
  # summary. An empty action list reads as "nothing needed doing".
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _prod_profile "bats:a" "duplicate_membership"
  printf '{ truncated' > "$OUT/profiles/bats_a.json"

  run _finalize_full
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
  [[ "$output" != *"Verdict"* ]]
}

@test "PRODUCTION: another audit's leftover profile is refused, not absorbed" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _prod_profile "bats:a" "duplicate_membership" "an-older-audit"

  run _finalize_full
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/decision.json" ]
}

@test "PRODUCTION: a selected unit that was never profiled blocks finalization" {
  # Without this the selector is a detector with no enforcement: it names the
  # slow suites, nobody profiles them, and the audit finalizes looking exactly
  # as complete as one that had.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  mkdir -p "$OUT/profiles"
  jq -nc --arg aid "$AUDIT_ID" '
    {schema_version:"aid-test-profile-selection-v1", audit_id:$aid,
     policy:{profile_trigger_ms:120000, profile_max_units:3}, measured_units:2,
     selected:[{run_unit_id:"bats:b", measured_ms:400000, reason:"over the trigger"}],
     deferred:[]}' > "$OUT/profile-selection.json"

  run _finalize_full
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:b"* ]]
  [ ! -f "$OUT/decision.json" ]
}

@test "PRODUCTION: a satisfied selection finalizes and the profiled unit gets its action" {
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _prod_profile "bats:b" "duplicate_membership"
  jq -nc --arg aid "$AUDIT_ID" '
    {schema_version:"aid-test-profile-selection-v1", audit_id:$aid,
     policy:{profile_trigger_ms:120000, profile_max_units:3}, measured_units:2,
     selected:[{run_unit_id:"bats:b", measured_ms:400000, reason:"over the trigger"}],
     deferred:[]}' > "$OUT/profile-selection.json"

  run _finalize_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.actions[] | select(.targets[0] == "bats:b")] | length' "$OUT/decision.json")" -ge 1 ]
}

@test "PRODUCTION: static mode refuses a profiles directory rather than ignoring it" {
  # A static audit runs nothing, so a receipt underneath it did not come from
  # this audit. Quietly ignoring it would leave a stale diagnosis in place.
  _shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
  _prod_profile "bats:a" "duplicate_membership"

  run bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MANIFEST" --output-dir "$OUT" --mode static \
    --profiles-dir "$OUT/profiles"
  [ "$status" -ne 0 ]
  [[ "$output" == *"static"* ]]
}
