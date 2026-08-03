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

# Suites are written into the PROJECT and the disposable root is a clone of it:
# the pilot now refuses a target that is not a snapshot of the audited tree, so
# a fixture that fabricated an unrelated clone would be testing a path
# production refuses to take.
_suite() {
  mkdir -p "$PROJ/tests"
  printf '%s' "$2" > "$PROJ/tests/$1.bats"
}

_clone() {
  rm -rf "$PROJ/tests"; mkdir -p "$PROJ/tests"
  ( cd "$PROJ" && git add -A 2>/dev/null; git commit -qm base --allow-empty )
}

# Call after the suites and catalog are in place.
_snapshot() {
  ( cd "$PROJ" && git add -A && git commit -qm fixtures --allow-empty -q )
  rm -rf "$CLONE"; git clone -q "$PROJ" "$CLONE"
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
  _snapshot
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
  _snapshot
  run bash "$PILOT" --lane-id l --unit "bats:tests/a" \
    --catalog "$PROJ/.aid-o/config/test-catalog.yaml" \
    --output-dir "$OUT" --target-root "$PROJ" --project-root "$PROJ"
  [ "$status" -eq 10 ]
  [[ "$output" == *"disposable clone"* ]]
}

@test "REFUSAL: a linked worktree of the project is not a disposable root" {
  # It shares the object store, so a mutation there is not contained.
  _clone; _suite a "${AT} \"x\" { true; }"; _catalog a
  _snapshot
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
  echo tracked > "$PROJ/tracked.txt"
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
  echo t > "$PROJ/t.txt"
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

# ─── What an adversarial review found, each pinned ─────────────────────────

@test "a lane whose CONCURRENT run exits non-zero is refused, however it reads per case" {
  # Two suites each containing a case called "same", one failing only under
  # concurrency. Matching results by NAME found the passing one, the exit code
  # was never examined, and a lane whose parallel run had failed was proposed.
  _clone
  _suite a "${AT} \"same\" {
  : > \"\$BATS_TEST_DIRNAME/../token\"
  sleep 2
  rm \"\$BATS_TEST_DIRNAME/../token\"
}"
  _suite b "${AT} \"same\" {
  sleep 0.1
  [ ! -e \"\$BATS_TEST_DIRNAME/../token\" ]
  sleep 2
}"
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2 || true)"
  [ "$(jq -r '.promotion' "$r")" = "refused" ]
  [ "$(jq -r '.repetitions[0].parallel.exit_code' "$r")" != "0" ]
  [[ "$(jq -r '.reason' "$r")" == *"exited"* ]]
}

@test "a serial run may not WARM state that the concurrent run then finds ready" {
  # Sharing one working tree between the two sides makes a cold race vanish
  # exactly when it is being looked for. Each side runs in its own snapshot.
  _clone
  printf 'state/\n' > "$PROJ/.gitignore"
  for n in a b; do
    _suite "$n" "${AT} \"work\" {
  if [[ ! -e \"\$BATS_TEST_DIRNAME/../state/ready\" ]]; then
    mkdir \"\$BATS_TEST_DIRNAME/../state\" || return 1
    sleep 0.2
    : > \"\$BATS_TEST_DIRNAME/../state/ready\"
  fi
  sleep 2
}"
  done
  _catalog a b
  local r; r="$(_pilot --unit "bats:tests/a" --unit "bats:tests/b" --workers 2 || true)"
  [ "$(jq -r '.promotion' "$r")" != "proposed" ]
}

@test "a write GIT IGNORES is still a mutation" {
  # `git status` cannot see it, and an ignored marker is exactly how one run
  # leaves state for the next.
  _clone
  printf 'scratch/\n' > "$PROJ/.gitignore"
  _suite a "${AT} \"writes an ignored file\" {
  mkdir -p \"\$BATS_TEST_DIRNAME/../scratch\"
  echo x > \"\$BATS_TEST_DIRNAME/../scratch/left-behind\"
}"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2 || true)"
  [ "$(jq -r '.repetitions[0].serial.dirty_paths | length' "$r")" -ge 1 ]
  [[ "$(jq -r '.repetitions[0].serial.dirty_paths | join(",")' "$r")" == *"left-behind"* ]]
}

@test "a change to an ALREADY PRESENT file is a mutation, not merely a new path" {
  _clone
  echo original > "$PROJ/data.txt"
  _suite a "${AT} \"edits an existing file\" { echo changed > \"\$BATS_TEST_DIRNAME/../data.txt\"; }"
  _catalog a
  local r; r="$(_pilot --unit "bats:tests/a" --workers 2 || true)"
  [ "$(jq -r '.promotion' "$r")" = "refused" ]
  [[ "$(jq -r '.reason' "$r")" == *"data.txt"* ]]
}

@test "REFUSAL: a target root at a DIFFERENT revision is not evidence about this one" {
  # Otherwise the pilot measures an unrelated or stale repository that happens
  # to contain the same paths, and the result is consumed for the audited tree.
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _catalog a
  _snapshot
  ( cd "$PROJ" && echo drift > drift.txt && git add drift.txt && git commit -qm drift )
  run bash "$PILOT" --lane-id l --unit "bats:tests/a" \
    --catalog "$PROJ/.aid-o/config/test-catalog.yaml" \
    --execution-yaml "$PROJ/.aid-o/config/execution.yaml" \
    --output-dir "$OUT" --target-root "$CLONE" --project-root "$PROJ"
  [ "$status" -eq 10 ]
  [[ "$output" == *"not a snapshot of the audited tree"* ]]
}

@test "REFUSAL: a unit whose approved command is not exactly [bats, file] is not piloted" {
  # Taking the first .bats argument out of a longer approved command and
  # dropping the rest would pilot something the project does not run — and the
  # dropped file could be the one that races.
  _clone
  _suite a "${AT} \"a1\" { true; }"
  _suite extra "${AT} \"e1\" { true; }"
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/a"'
    echo '    runner: bats'
    echo '    source_paths: ["tests/a.bats"]'
    echo '    command: {type: argv, argv: ["bats", "tests/a.bats", "tests/extra.bats"]}'
  } > "$PROJ/.aid-o/config/test-catalog.yaml"
  printf 'gates: []\n' > "$PROJ/.aid-o/config/execution.yaml"
  run _pilot --unit "bats:tests/a" --workers 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot represent exactly"* ]]
}

@test "a receipt claiming a benefit with NO repetitions is rejected by the schema" {
  # 'consumes only proposed' would otherwise promote a lane that never ran.
  local f="$TEST_TMPDIR/empty.json"
  jq -n '{schema_version:"aid-test-parallel-pilot-v1", lane_id:"l", audit_id:null,
    target_root:"/tmp/x", membership:["bats:a","bats:b"],
    membership_sha256:"0000000000000000000000000000000000000000000000000000000000000000",
    workers:2, repeat:1, promotion:"proposed", reason:"a benefit with no evidence",
    benefit_ms:5000, noise_threshold_ms:2000, failing_repetition:null, repetitions:[],
    parallelism:{available:true, note:"GNU parallel is present here"}}' > "$f"
  run _validate "$f"
  [ "$status" -ne 0 ]
}

@test "a receipt whose repetition FAILED cannot be proposed" {
  local f="$TEST_TMPDIR/failedrep.json"
  jq -n '{schema_version:"aid-test-parallel-pilot-v1", lane_id:"l", audit_id:null,
    target_root:"/tmp/x", membership:["bats:a","bats:b"],
    membership_sha256:"0000000000000000000000000000000000000000000000000000000000000000",
    workers:2, repeat:1, promotion:"proposed", reason:"claims a benefit anyway",
    benefit_ms:5000, noise_threshold_ms:2000, failing_repetition:null,
    repetitions:[{index:1, verdict:"match",
      serial:{duration_ms:10, exit_code:0, job_state:"terminal_pass", results:[], dirty_paths:[], escaped_paths:[]},
      parallel:{duration_ms:5, exit_code:1, job_state:"terminal_fail", results:[], dirty_paths:[], escaped_paths:[]}}],
    parallelism:{available:true, note:"GNU parallel is present here"}}' > "$f"
  run _validate "$f"
  [ "$status" -ne 0 ]
}
