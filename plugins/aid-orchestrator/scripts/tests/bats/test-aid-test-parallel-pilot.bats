#!/usr/bin/env bats
# test-aid-test-parallel-pilot.bats — P072 Step 15.
#
# The pilot's job is to REFUSE well. A promotion is cheap to grant and
# expensive to be wrong about, so every case here pins a refusal, the locus it
# names, or the honesty of a verdict that declines to propose anything.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  PILOT="$PLUGIN_DIR/scripts/aid-test-parallel-pilot.sh"
  SCHEMA="$PLUGIN_DIR/defaults/schemas/test-parallel-pilot.schema.json"
  AT='@'"test"

  # A disposable project with its own tiny bats suites and its own catalog.
  PROJ="$TEST_TMPDIR/proj"
  CLONE="$TEST_TMPDIR/clone"
  mkdir -p "$PROJ/.aid-o/config"
  ( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name t )
  OUT="$TEST_TMPDIR/out"
}

teardown() { teardown_test_evidence_dir; }

# _suite <name> <body>
_suite() {
  mkdir -p "$CLONE/tests"
  printf '%s' "$2" > "$CLONE/tests/$1.bats"
}

_clone() {
  rm -rf "$CLONE"; mkdir -p "$CLONE/tests"
  ( cd "$CLONE" && git init -q && git config user.email t@t && git config user.name t )
}

# _catalog <name...> — one bats run unit per suite name
_catalog() {
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    for n in "$@"; do
      echo "  - run_unit_id: \"bats:tests/$n\""
      echo '    runner: bats'
      echo "    source_paths: [\"tests/$n.bats\"]"
      echo "    command: {type: argv, argv: [\"bats\", \"tests/$n.bats\"]}"
    done
  } > "$PROJ/.aid-o/config/test-catalog.yaml"
  printf 'gates: []\n' > "$PROJ/.aid-o/config/execution.yaml"
}

_pilot() {
  bash "$PILOT" --lane-id "lane-1" --catalog "$PROJ/.aid-o/config/test-catalog.yaml" \
    --execution-yaml "$PROJ/.aid-o/config/execution.yaml" \
    --output-dir "$OUT" --target-root "$CLONE" --project-root "$PROJ" \
    --deadline 120 "$@"
}

_validate() {
  python3 - "$SCHEMA" "$1" <<'PY'
import json,sys
from jsonschema.validators import Draft202012Validator
schema=json.load(open(sys.argv[1])); inst=json.load(open(sys.argv[2]))
errs=list(Draft202012Validator(schema).iter_errors(inst))
for e in errs: print("/".join(str(x) for x in e.path) or "(root)", e.message)
sys.exit(1 if errs else 0)
PY
}

# ─── Refusals that happen before anything runs ─────────────────────────────

@test "REFUSAL: piloting the live checkout exits 10" {
  # The pilot runs the same tests twice and then inspects the tree for leaks.
  # Doing that in the checkout under audit is how a measurement becomes an
  # outage.
  _clone; _suite a "${AT} \"x\" { true; }"; _catalog a
  run bash "$PILOT" --lane-id l --unit "bats:tests/a" \
    --catalog "$PROJ/.aid-o/config/test-catalog.yaml" \
    --output-dir "$OUT" --target-root "$PROJ" --project-root "$PROJ"
  [ "$status" -eq 10 ]
  [[ "$output" == *"disposable clone"* ]]
}

@test "REFUSAL: a linked worktree of the project is not a disposable root" {
  # It shares the object store, so a mutation there is not contained.
  _clone; _suite a "${AT} \"x\" { true; }"; _catalog a
  ( cd "$PROJ" && echo x > f && git add f && git commit -qm init )
  local wt="$TEST_TMPDIR/wt"
  ( cd "$PROJ" && git worktree add -q "$wt" -b wtb )
  run bash "$PILOT" --lane-id l --unit "bats:tests/a" \
    --catalog "$PROJ/.aid-o/config/test-catalog.yaml" \
    --output-dir "$OUT" --target-root "$wt" --project-root "$PROJ"
  [ "$status" -eq 10 ]
  [[ "$output" == *"object store"* ]]
}

@test "REFUSAL: a unit absent from the catalog exits 3 — no command is invented" {
  _clone; _suite a "${AT} \"x\" { true; }"; _catalog a
  run _pilot --unit "bats:tests/nope"
  [ "$status" -eq 3 ]
  [[ "$output" == *"never invents a command"* ]]
}

@test "REFUSAL: one worker is not concurrency" {
  _clone; _suite a "${AT} \"x\" { true; }"; _catalog a
  run _pilot --unit "bats:tests/a" --workers 1
  [ "$status" -eq 2 ]
}

# ─── The comparison ────────────────────────────────────────────────────────

@test "a lane whose cases agree serially and concurrently is not refused" {
  _clone
  _suite a "${AT} \"a1\" { true; }
${AT} \"a2\" { true; }"
  _suite b "${AT} \"b1\" { true; }"
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2)"
  [ -f "$r" ]
  [ "$(jq -r '.promotion' "$r")" != "refused" ]
  [ "$(jq -r '.repetitions[0].verdict' "$r")" = "match" ]
  run _validate "$r"
  [ "$status" -eq 0 ]
}

@test "a case that PASSES serially and FAILS concurrently is refused, and named" {
  # The whole point. A file that only works when it has the directory to
  # itself must never enter a pool.
  _clone
  _suite a "setup() { mkdir \"\$BATS_TEST_DIRNAME/../shared-dir\"; }
teardown() { rmdir \"\$BATS_TEST_DIRNAME/../shared-dir\" 2>/dev/null || true; }
${AT} \"a1\" { [ -d \"\$BATS_TEST_DIRNAME/../shared-dir\" ]; }"
  _suite b "${AT} \"b1\" { mkdir \"\$BATS_TEST_DIRNAME/../shared-dir\"; }"
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2 || true)"
  [ -f "$r" ]
  # Either the runs differ (refused) or the clone was left dirty — both are
  # refusals, and neither may be a proposal.
  [ "$(jq -r '.promotion' "$r")" != "proposed" ]
}

@test "a mismatch names the differing cases rather than counting them" {
  # "three cases differed" sends nobody anywhere.
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2)"
  # This lane matches, so assert the SHAPE that a mismatch would use.
  [ "$(jq -r '.repetitions[0] | has("differences")' "$r")" = "true" ]
  [ "$(jq -r '.repetitions[0].differences | type' "$r")" = "array" ]
}

@test "a dirty clone after a run is a refusal, with the paths listed" {
  _clone
  ( cd "$CLONE" && echo tracked > tracked.txt && git add tracked.txt && git commit -qm init )
  _suite a "${AT} \"dirties the tree\" { echo mutated > \"\$BATS_TEST_DIRNAME/../tracked.txt\"; }"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2 || true)"
  [ -f "$r" ]
  [ "$(jq -r '.promotion' "$r")" = "refused" ]
  [[ "$(jq -r '.reason' "$r")" == *"tracked.txt"* ]]
}

# ─── Repeat policy ─────────────────────────────────────────────────────────

@test "every repetition must satisfy every criterion" {
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _suite b "${AT} \"b1\" { true; }"
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2 --repeat 2)"
  [ "$(jq -r '.repeat' "$r")" = "2" ]
  [ "$(jq -r '.repetitions | length' "$r")" = "2" ]
}

@test "a failing repetition ends the pilot and records its INDEX, with no retry" {
  # Retrying until green is how a flaky lane gets promoted.
  _clone
  ( cd "$CLONE" && echo t > t.txt && git add t.txt && git commit -qm init )
  _suite a "${AT} \"dirties\" { echo x > \"\$BATS_TEST_DIRNAME/../t.txt\"; }"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2 --repeat 3 || true)"
  [ "$(jq -r '.promotion' "$r")" = "refused" ]
  [ "$(jq -r '.failing_repetition' "$r")" = "1" ]
  # It stopped rather than running all three.
  [ "$(jq -r '.repetitions | length' "$r")" -lt 3 ]
}

# ─── Honest non-proposals ──────────────────────────────────────────────────

@test "a benefit within the noise threshold is safe_not_worthwhile, not a lane" {
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _suite b "${AT} \"b1\" { true; }"
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2)"
  [ "$(jq -r '.promotion' "$r")" = "safe_not_worthwhile" ]
  [[ "$(jq -r '.reason' "$r")" == *"noise"* ]]
  [ "$(jq -r '.benefit_ms' "$r")" != "null" ]
}

@test "a lane of ONE unit is safe_not_worthwhile with the measured equality" {
  # Concurrency cannot help a single file; proposing a lane of one would be
  # proposing nothing at a cost.
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2)"
  [ "$(jq -r '.promotion' "$r")" = "safe_not_worthwhile" ]
  [[ "$(jq -r '.reason' "$r")" == *"lane of one"* ]]
}

@test "a real benefit above the threshold IS proposed, with both durations cited" {
  # Two suites that each sleep: serial ~4s, concurrent ~2s. The threshold is
  # lowered for the fixture so the assertion is about the rule, not the clock.
  _clone
  _suite a "${AT} \"slow a\" { sleep 2; }"
  _suite b "${AT} \"slow b\" { sleep 2; }"
  _catalog a b
  cat > "$PROJ/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: 30
max_read_only_audit_agents: 4
allowed_runners: [bats]
decision:
  pilot_noise_ms: 200
YAML
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2)"
  [ "$(jq -r '.promotion' "$r")" = "proposed" ]
  [ "$(jq -r '.benefit_ms' "$r")" -gt 200 ]
  [[ "$(jq -r '.reason' "$r")" == *"serial"* ]]
  [[ "$(jq -r '.reason' "$r")" == *"parallel"* ]]
}

# ─── Identity and provenance ───────────────────────────────────────────────

@test "the membership is recorded SORTED and hashed, so a lane's identity is stable" {
  # Evidence gathered for one set may not promote another. Argument order must
  # not change what the receipt claims to be about.
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _suite b "${AT} \"b1\" { true; }"
  _catalog a b
  local r1 r2
  r1="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2)"
  local h1; h1="$(jq -r '.membership_sha256' "$r1")"
  r2="$(_pilot --unit "bats:tests/b" --unit "bats:tests/a" --workers 2)"
  [ "$(jq -r '.membership_sha256' "$r2")" = "$h1" ]
  [ "$(jq -r '.membership | join(",")' "$r2")" = "bats:tests/a,bats:tests/b" ]
}

@test "the receipt names the disposable root it ran in" {
  _clone; _suite a "${AT} \"a1\" { true; }"; _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2)"
  [ "$(jq -r '.target_root' "$r")" != "null" ]
  [[ "$(jq -r '.target_root' "$r")" == *"clone"* ]]
}

@test "the receipt records whether concurrency was actually AVAILABLE" {
  # Bats delegates --jobs to GNU parallel. Without it the flag degrades to
  # serial, and `safe_not_worthwhile` would mean "never attempted" while
  # reading as "does not pay".
  _clone; _suite a "${AT} \"a1\" { true; }"; _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2)"
  [ "$(jq -r '.parallelism | has("available")' "$r")" = "true" ]
  [ "$(jq -r '.parallelism.note | length > 10' "$r")" = "true" ]
}

@test "nothing may be PROPOSED when concurrency was unavailable" {
  # Asserted at the schema, because the rule must hold for any producer.
  local f="$TEST_TMPDIR/fake.json"
  jq -n '{schema_version:"aid-test-parallel-pilot-v1", lane_id:"l", audit_id:null,
    target_root:"/tmp/x", membership:["bats:a","bats:b"], workers:2, repeat:1,
    promotion:"proposed", reason:"claims a benefit anyway", benefit_ms:5000,
    noise_threshold_ms:2000, failing_repetition:null, repetitions:[],
    parallelism:{available:false, note:"GNU parallel is not installed here"}}' > "$f"
  run _validate "$f"
  [ "$status" -ne 0 ]
}

@test "a refusal always names a locus" {
  # A verdict nobody can act on is not a verdict.
  local f="$TEST_TMPDIR/norefusal.json"
  jq -n '{schema_version:"aid-test-parallel-pilot-v1", lane_id:"l", audit_id:null,
    target_root:"/tmp/x", membership:["bats:a"], workers:2, repeat:1,
    promotion:"refused", reason:"something went wrong somewhere", benefit_ms:null,
    noise_threshold_ms:2000, repetitions:[],
    parallelism:{available:true, note:"GNU parallel is present here"}}' > "$f"
  run _validate "$f"
  [ "$status" -ne 0 ]
}
