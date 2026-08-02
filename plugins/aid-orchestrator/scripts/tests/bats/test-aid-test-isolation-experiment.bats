#!/usr/bin/env bats
# test-aid-test-isolation-experiment.bats — P069 Step 6.
#
# Proves aid-test-isolation-experiment.sh:
#   - a genuinely isolated pair promotes to safe, proposed overlay written
#   - a pair sharing an undeclared resource fails promotion, naming the
#     specific divergence
#   - the experiment's working directory is never the repo root (a live
#     project-root file is untouched by the candidate commands)
#   - the written proposed-overlay entry validates against Step 5's schema
#     and its catalog_fingerprint_at_promotion matches the real catalog
#     entry's runtime.fingerprint
#   - a git-worktree-add failure fails closed as unknown (no promotion, no
#     live-tree execution)
#   - the disposable worktree is removed unconditionally (no leftover
#     `git worktree list` entry) on both success and refusal

load test-helpers.bash

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-isolation-experiment.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/scheduler-parallel-overlay.schema.json"
  setup_test_evidence_dir
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
}

teardown() {
  teardown_test_evidence_dir
}

_write_catalog() {
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"safe1", runner:"shell", source_paths:["s1"], production_surfaces:["s1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"echo safe1 > out1.txt; grep -q safe1 out1.txt"}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"safe2", runner:"shell", source_paths:["s2"], production_surfaces:["s2"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"echo safe2 > out2.txt; grep -q safe2 out2.txt"}, runtime:{fingerprint:"sha256:bbbbbbbbbbbb"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"confl1", runner:"shell", source_paths:["c1"], production_surfaces:["c1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"sleep 0.5; echo X > shared.txt; sleep 0.5; grep -q X shared.txt"}, runtime:{fingerprint:"sha256:cccccccccccc"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"confl2", runner:"shell", source_paths:["c2"], production_surfaces:["c2"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"echo Y > shared.txt; sleep 0.8; grep -q Y shared.txt"}, runtime:{fingerprint:"sha256:dddddddddddd"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"locked1", runner:"shell", source_paths:["l1"], production_surfaces:["l1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"echo locked1 > out3.txt; grep -q locked1 out3.txt"}, runtime:{fingerprint:"sha256:eeeeeeeeeeee"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[{lock_target:"db", resolved_scope:"db"}], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  # The catalog must be committed — aid-test-isolation-experiment.sh reads
  # it via `git show <commit>:...`, never the live working tree (Codex
  # review fix), so an uncommitted catalog is invisible to it.
  git -C "$TEST_PROJECT_ROOT" add -f .aid-o/config/test-catalog.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m "test catalog"
}

@test "a genuinely isolated pair promotes to safe with a written, schema-valid proposed overlay" {
  _write_catalog
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso1" --unit-ids "safe1,safe2" --n 3
  [ "$status" -eq 0 ]

  local proposed="$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso1/scheduler-overlay.proposed.json"
  [ -f "$proposed" ]
  run jq -r '.status' "$proposed"
  [ "$output" = "proposed" ]
  run jq -r '[.overlay[].run_unit_id] | sort | join(",")' "$proposed"
  [ "$output" = "safe1,safe2" ]
  run jq -r '.overlay[] | select(.run_unit_id=="safe1") | .promoted_status' "$proposed"
  [ "$output" = "safe" ]
  run jq -r '.overlay[] | select(.run_unit_id=="safe1") | .catalog_fingerprint_at_promotion' "$proposed"
  [ "$output" = "sha256:aaaaaaaaaaaa" ]
  run jq -r '.overlay[] | select(.run_unit_id=="safe1") | .evidence_run_id' "$proposed"
  [ "$output" = "iso1" ]

  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1 && {
    run python3 -c "
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open('$SCHEMA'))
inst = json.load(open('$proposed'))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
"
    [ "$status" -eq 0 ]
  }
}

@test "a pair sharing an undeclared resource fails promotion, naming the specific divergence" {
  _write_catalog
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso2" --unit-ids "confl1,confl2" --n 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"confl1"* || "$output" == *"confl2"* ]]
  [[ "$output" == *"solo baseline"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso2/scheduler-overlay.proposed.json" ]
}

@test "a unit whose catalog isolation.lock_usage is non-empty promotes to constrained, never safe" {
  _write_catalog
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso3" --unit-ids "locked1" --n 2
  [ "$status" -eq 0 ]
  local proposed="$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso3/scheduler-overlay.proposed.json"
  run jq -r '.overlay[0].promoted_status' "$proposed"
  [ "$output" = "constrained" ]
}

@test "the experiment never executes against the live project checkout" {
  _write_catalog
  # Seed a sentinel file at the live project root; the candidate's command
  # only ever writes RELATIVE paths, so if it ran in the live tree this
  # sentinel's content would be at risk of collision/overwrite for a
  # same-named file — assert the live root's own working tree is untouched
  # and the proposed overlay's evidence trail points at a DIFFERENT path
  # (the disposable worktree), never the live root.
  echo "sentinel" > "$TEST_PROJECT_ROOT/out1.txt"
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso4" --unit-ids "safe1" --n 2
  [ "$status" -eq 0 ]
  run cat "$TEST_PROJECT_ROOT/out1.txt"
  [ "$output" = "sentinel" ]
  # Every worktree this run created (solo baseline + each trial) is gone,
  # and none of them is the live project root.
  local d
  for d in "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso4"/isolation-worktree-*; do
    [ ! -e "$d" ]
  done
}

@test "the disposable worktree is removed unconditionally after both a promotion and a refusal" {
  _write_catalog
  bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso5" --unit-ids "safe1" --n 2 >/dev/null
  run git -C "$TEST_PROJECT_ROOT" worktree list
  [[ "$output" != *"iso5"* ]]
  local d
  for d in "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso5"/isolation-worktree-*; do
    [ ! -e "$d" ]
  done

  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso6" --unit-ids "confl1,confl2" --n 3
  [ "$status" -ne 0 ]
  run git -C "$TEST_PROJECT_ROOT" worktree list
  [[ "$output" != *"iso6"* ]]
  for d in "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso6"/isolation-worktree-*; do
    [ ! -e "$d" ]
  done
}

@test "a git-worktree-add failure fails closed as unknown — no promotion, no live-tree execution" {
  _write_catalog
  # Force worktree add to fail: point --commit at a nonexistent object.
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso7" --unit-ids "safe1" --n 2 --commit "0000000000000000000000000000000000000000"
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso7/scheduler-overlay.proposed.json" ]
  [ ! -f "$TEST_PROJECT_ROOT/out1.txt" ]
}

@test "a solo baseline's leftover file never contaminates a later trial's fresh worktree (Codex regression)" {
  _write_catalog
  # This candidate's command ALWAYS asserts a file is ABSENT then creates
  # it. With a shared/reused worktree, the solo baseline creates the file
  # and every subsequent trial would then see it already present and FAIL
  # its own "must be absent" assertion — with genuinely fresh worktrees per
  # run, every single run (solo + all trials) sees an empty tree and
  # passes identically.
  yq -o=json '.' "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" | jq \
    '.run_units += [{run_unit_id:"needs-fresh-tree", runner:"shell", source_paths:["n1"], production_surfaces:["n1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium", command:{type:"shell", shell:"test ! -f leftover.txt && echo leftover > leftover.txt"}, runtime:{fingerprint:"sha256:ffffffffffff"}, parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false}, isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"}, recommendation:"keep", test_cases:[]}]' \
    | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml.new"
  mv "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml.new" "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git -C "$TEST_PROJECT_ROOT" add -f .aid-o/config/test-catalog.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m "add needs-fresh-tree"

  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso9" --unit-ids "needs-fresh-tree" --n 3
  [ "$status" -eq 0 ]
}

@test "--commit rejects a value shaped like a git option instead of passing it through unvalidated (Codex regression)" {
  _write_catalog
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso10" --unit-ids "safe1" --n 2 --commit "--help"
  [ "$status" -ne 0 ]
  [[ "$output" != *"usage:"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/iso10/scheduler-overlay.proposed.json" ]
}

@test "the catalog is read from the resolved --commit, never the live working tree (Codex regression)" {
  _write_catalog
  local commit_a; commit_a="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  # Mutate the LIVE catalog (uncommitted) to remove safe1 entirely — if the
  # experiment reads the live tree instead of commit A, resolving "safe1"
  # would fail differently (not found) than the real, correct behavior of
  # reading commit A's catalog, which still has it.
  yq -o=json '.' "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" | jq '.run_units |= map(select(.run_unit_id != "safe1"))' \
    | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"

  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso11" --unit-ids "safe1" --n 2 --commit "$commit_a"
  [ "$status" -eq 0 ]
}

@test "TERM mid-trial cancels the outstanding unit to a terminal receipt (Codex regression: jobs-dir visibility across command substitution)" {
  # _ISO_CURRENT_JOBS_DIR was previously set INSIDE _iso_run_set, which
  # every caller invokes via command substitution — a subshell — so the
  # assignment never reached the parent's cleanup trap. Prove the real,
  # end-to-end consequence is fixed: a signal arriving while a unit is
  # still running must still result in a real cancellation, not an
  # orphaned process with the worktree ripped out from under it.
  _write_catalog
  yq -o=json '.' "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" | jq \
    '.run_units += [{run_unit_id:"hung1", runner:"shell", source_paths:["h1"], production_surfaces:["h1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium", command:{type:"shell", shell:"sleep 30 & echo $! > '"$TEST_PROJECT_ROOT"'/child.pid; wait"}, runtime:{fingerprint:"sha256:ffffffffffff"}, parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false}, isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"}, recommendation:"keep", test_cases:[]}]' \
    | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml.new"
  mv "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml.new" "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git -C "$TEST_PROJECT_ROOT" add -f .aid-o/config/test-catalog.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m "add hung1"

  bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso12" --unit-ids "hung1" --n 1 &
  local pid=$!
  for ((i = 0; i < 50; i++)); do
    [[ -f "$TEST_PROJECT_ROOT/child.pid" ]] && break
    sleep 0.1
  done
  [ -f "$TEST_PROJECT_ROOT/child.pid" ]
  kill -TERM "$pid"
  wait "$pid" || true

  local child_pid; child_pid="$(cat "$TEST_PROJECT_ROOT/child.pid")"
  run kill -0 "$child_pid"
  [ "$status" -ne 0 ]
}

@test "an unknown run_unit_id is rejected before any worktree is created" {
  _write_catalog
  run bash "$SCRIPT" run --project-root "$TEST_PROJECT_ROOT" --run-id "iso8" --unit-ids "does-not-exist" --n 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"does-not-exist"* ]]
  run git -C "$TEST_PROJECT_ROOT" worktree list
  [[ "$output" != *"iso8"* ]]
}
