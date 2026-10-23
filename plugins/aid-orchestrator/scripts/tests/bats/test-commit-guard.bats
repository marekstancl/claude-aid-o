#!/usr/bin/env bats
# aid-tier: t2
# test-commit-guard.bats — P060 Step 6 (E-060-2_2) behavioral suite for the
# commit-scope + branch pre-commit guard (D7) and its controller-side companion.
#
# Grounding (why this suite exists): OBS-20260709-01 (a broad `git add` staged
# files outside the active step's scope) and OBS-20260709-04 (a rogue commit
# landed on `main` under a test identity while a run was mid-EXECUTE). The old
# template fired ONLY on task/*|epic/* branches and never scope-checked staged
# files, so both slipped through. The new template (defaults/hooks/pre-commit)
# fires on ALL branches, discovers the active run (EXECUTE|GATES|DONE), and
# enforces staged ⊆ state-appropriate scope. --no-verify residue is caught
# out-of-band by the aid-fsm.sh companion (commit_scope_violation event).
#
# F4 scenarios (map to the plan):
#   (a)  EXECUTE: staged outside the step's allowed_paths        → fail (listing)
#   (b)  HEAD=main during an EXECUTE run (OBS-04 shape)          → fail
#   (c)  EXECUTE: staged in-scope on the run's branch           → pass
#   (d)  GATES: gate-fix outside per-step but inside union      → pass
#   (e)  DONE/release: version files + both CHANGELOGs pass; non-whitelisted fail
#   (e2) DONE/review: file within union passes; file outside union fails
#   (e3) consumer without versioning config → warn + pass + disclosure
#   (f)  jq missing → warn + skip scope check (NOT blocked by absent tooling)
#   (g)  plan.json declares no allowed_paths → warn + pass + disclosure
#   (h)  outside an AID run (no active state file) → no-op pass
#   (i)  companion: --no-verify bypass → commit_scope_violation at step-advance

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  HOOK="$AID_PLUGIN_PATH/defaults/hooks/pre-commit"
  export HOOK
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  export AID_TEST_MODE=1
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Fixtures ────────────────────────────────────────────────────────────────

# _write_state <state> <branch> [done_phase] [current_step]
_write_state() {
  local state="$1" branch="$2" done_phase="${3:-}" cur="${4:-1}"
  local sf="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  {
    echo "epic_id: E-test"
    echo "run_id: R-test"
    echo "state: $state"
    echo "current_step: $cur"
    echo "total_steps: 2"
    echo "branch: $branch"
    echo "base_commit: $(git rev-parse HEAD)"
    if [[ -n "$done_phase" ]]; then echo "done_phase: $done_phase"; fi
  } > "$sf"
  _map_entry E-test "$sf"
}

# _map_entry <epic> <state_file> — the run's active-runs.json entry, as init
# writes it (P112: the hook takes a branch's run only from this map).
_map_entry() {
  local map="$TEST_PROJECT_ROOT/.aid-o/work/active-runs.json"
  mkdir -p "$(dirname "$map")"; [[ -s "$map" ]] || echo '{}' > "$map"
  jq --arg e "$1" --arg sf "$2" '.[$e] = {state_file: $sf, governs_main: true, auto_controller: "unknown"}' "$map" > "$map.t" && mv "$map.t" "$map"
}

# _write_plan — default 2-step plan (step0=src/a.txt, step1=src/b.txt).
_write_plan() {
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'JSON'
{ "steps": [
  { "id": "s0", "allowed_paths": ["src/a.txt"] },
  { "id": "s1", "allowed_paths": ["src/b.txt"] }
] }
JSON
}

# _write_plan_empty_step1 — step1 has an plan.json declares no allowed_paths list.
_write_plan_empty_step1() {
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'JSON'
{ "steps": [
  { "id": "s0", "allowed_paths": ["src/a.txt"] },
  { "id": "s1", "allowed_paths": [] }
] }
JSON
}

# _write_project_versioning — project.yaml with a versioning whitelist.
_write_project_versioning() {
  mkdir -p .aid-o/config
  cat > .aid-o/config/project.yaml <<'YAML'
versioning:
  source: CHANGELOG.md
  files:
    - path: plugin.json
      type: json
YAML
}

# _stage <file> [content] — create + git add a file (makes intermediate dirs).
_stage() {
  local f="$1" c="${2:-x}"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$c" > "$f"
  git add "$f"
}

# _write_state_at <evidence_dir> <state> <branch> [done_phase]
#   Writes a minimal fsm-state.yaml directly under an ARBITRARY evidence dir
#   (unlike _write_state, which always targets $TEST_EVIDENCE_DIR) — used to
#   simulate a SECOND, independent historical run alongside the primary one.
_write_state_at() {
  local dir="$1" state="$2" branch="$3" done_phase="${4:-}"
  mkdir -p "$dir"
  local sf="$dir/fsm-state.yaml"
  {
    echo "epic_id: E-other"
    echo "run_id: R-other"
    echo "state: $state"
    echo "current_step: 1"
    echo "total_steps: 1"
    echo "branch: $branch"
    echo "base_commit: $(git rev-parse HEAD)"
    if [[ -n "$done_phase" ]]; then echo "done_phase: $done_phase"; fi
  } > "$sf"
}

# _write_pointer <state_file> — writes the active-run pointer JSON directly
# (bypassing aid-fsm.sh's cmd_init for test isolation/speed), matching the
# schema `write_active_run_pointer()` produces.
_write_pointer() {
  local sf="$1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  jq -n --arg sf "$sf" \
    '{state_file: $sf, epic_id: "E-test", run_id: "R-test", written_at: "2026-01-01T00:00:00Z"}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/active-run-pointer.json"
}

# _farm_excluding <cmd> — a PATH dir with every tool the hook needs EXCEPT <cmd>,
# used to simulate absent tooling (jq) without touching the real environment.
_farm_excluding() {
  local ex="$1" d="$BATS_TEST_TMPDIR/farm_no_$ex" c p
  rm -rf "$d"; mkdir -p "$d"
  for c in bash sh git grep awk sed tr cat dirname date find head tail sort env printf mktemp jq yq; do
    [[ "$c" == "$ex" ]] && continue
    p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$d/$c"
  done
  echo "$d"
}

# ─── (a) EXECUTE: staged outside the current step's allowed_paths → fail ──────
@test "a: EXECUTE staged outside step allowed_paths fails with listing" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state EXECUTE task/E-test/main "" 1   # step1 scope = src/b.txt
  _stage src/a.txt                              # step0 path, out of scope now
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside EXECUTE step 1 scope"* ]]
  [[ "$output" == *"src/a.txt"* ]]
}

# ─── (b) HEAD=main during an EXECUTE run (OBS-04 shape) → fail ────────────────
@test "b: commit on main while an EXECUTE run is active is blocked" {
  # Setup leaves us on main; the run's branch is the task branch (not main).
  _write_plan
  _write_state EXECUTE task/E-test/main "" 1
  # OBS-20260712-01: main-fallback governance now requires the active-run
  # pointer (see (m) below for the dedicated pointer-lifecycle test) — a real
  # `aid-fsm.sh init` always writes one, so a genuinely active run reaches
  # this hook exactly as it did before the fix.
  _write_pointer "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _stage src/b.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
  [[ "$output" == *"EXECUTE"* ]]
}

# ─── (c) EXECUTE: staged in-scope on the run's branch → pass ──────────────────
@test "c: EXECUTE staged in-scope on the correct branch passes" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state EXECUTE task/E-test/main "" 1
  _stage src/b.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (c2) a declared directory, a glob, an exact path; one rule in the hook and the contract (3.8.1) ───
@test "c2: a directory declared as dir/ or dir, a glob and an exact path cover their files; dir2 is no prefix of dir; the hook's rule equals the contract's" {
  git checkout -q -b task/E-test/main
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'JSON'
{ "steps": [ { "id": "s0", "allowed_paths": ["src/a.txt"] },
             { "id": "s1", "allowed_paths": ["ui/__tests__/", "lib", "docs/*.md", "src/b.txt"] } ] }
JSON
  _write_state EXECUTE task/E-test/main "" 1
  local f; for f in ui/__tests__/new.test.ts lib/x.sh docs/a.md src/b.txt; do
    git reset -q; _stage "$f"; run bash "$HOOK"; [ "$status" -eq 0 ] || { echo "$f: $output"; false; }
  done
  git reset -q; _stage lib2/x.sh; run bash "$HOOK"; [ "$status" -eq 1 ]
  # one rule, two copies (the hook cannot load the plugin)
  local hook_fn contract_fn
  hook_fn="$(sed -n '/^_aid_path_covers() {/,/^}/p' "$HOOK")"
  contract_fn="$(sed -n '/^_aid_path_covers() {/,/^}/p' "$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh")"
  [ -n "$hook_fn" ] && [ "$hook_fn" = "$contract_fn" ]
}

# ─── (d) GATES: gate-fix outside per-step but inside union → pass ─────────────
@test "d: GATES gate-fix inside the union of all steps passes" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state GATES task/E-test/main "" 1
  _stage src/a.txt                # step0 path: outside step1, inside union
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "d2: in GATES a commit touching only the backlog passes, and the hook's always-allowed list equals the FSM's" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state GATES task/E-test/main "" 2
  _stage docs/plans/BACKLOG.md "- IMP-1 a finding"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local hook_list fsm_list
  hook_list="$(grep '^_AID_ALWAYS_ALLOWED=' "$HOOK" | cut -d= -f2-)"
  fsm_list="$(grep '^_FSM_ALWAYS_ALLOWED=' "$FSM" | cut -d= -f2-)"
  [ -n "$hook_list" ] && [ "$hook_list" = "$fsm_list" ]
}

# ─── (e) DONE/release: version whitelist ─────────────────────────────────────
@test "e: DONE/release passes version files + both CHANGELOGs" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_project_versioning
  _write_state DONE task/E-test/main release 2

  # version files (source CHANGELOG.md + files[].path plugin.json) + both CHANGELOGs
  _stage CHANGELOG.md
  _stage plugins/aid-orchestrator/CHANGELOG.md
  _stage plugin.json
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "e: DONE/release fails a non-whitelisted file (L3-B1 hole)" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_project_versioning
  _write_state DONE task/E-test/main release 2

  _stage src/rogue.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DONE/release"* ]]
  [[ "$output" == *"src/rogue.txt"* ]]
}

# ─── (e2) DONE/review: union of all steps (precedent 23964c8) ─────────────────
@test "e2: DONE/review passes a file within the union" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state DONE task/E-test/main review 2

  _stage src/a.txt                # inside union → legit curator/auditor fix
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "e2: DONE/review fails a file outside the union" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state DONE task/E-test/main review 2

  _stage src/z.txt                # outside union → fail
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DONE/review"* ]]
  [[ "$output" == *"src/z.txt"* ]]
}

# ─── (e3) consumer without versioning config → warn + pass + disclosure ───────
@test "e3: DONE/release without versioning config warns, passes, discloses" {
  git checkout -q -b task/E-test/main
  _write_plan
  # No .aid-o/config/project.yaml written.
  _write_state DONE task/E-test/main release 2
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"versioning config unavailable"* ]]
  grep -q '"event":"commit_guard_disclosure"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q '"reason":"versioning_absent"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# ─── (f) jq missing: a run branch is refused (P112 — the map cannot be read,
#     so the run is unknown); any other branch passes with a line ─────────────
@test "hook-map: jq missing on a run branch refuses active_runs_unreadable; elsewhere it passes" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state EXECUTE task/E-test/main "" 1
  _stage src/a.txt
  local farm; farm=$(_farm_excluding jq)
  run env PATH="$farm" bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: active_runs_unreadable)"* && "$output" == *"next: "* ]]
  git checkout -q -b feature/x
  run env PATH="$farm" bash "$HOOK"
  [ "$status" -eq 0 ]; [[ "$output" == *"cannot be read"* ]]
}

# ─── (g) plan.json declares no allowed_paths → warn + pass + disclosure ───────────────────────
@test "g: plan.json declares no allowed_paths warns, passes, and discloses" {
  git checkout -q -b task/E-test/main
  _write_plan_empty_step1
  _write_state EXECUTE task/E-test/main "" 1
  _stage src/whatever.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan.json declares no allowed_paths"* ]]
  grep -q '"reason":"empty_allowed_paths"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# ─── (h) outside an AID run (no active state file) → no-op pass ───────────────
@test "h: no active AID run is a no-op pass" {
  # No state file written at all.
  _stage src/b.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (j) OBS-20260712-01 regression: a run superseded by a LATER init's
#     active-run pointer must never restrict a plain commit on main, however
#     long its own DONE/release evidence directory survives on disk ──────────
@test "j: a stale DONE/release run no longer referenced by the active-run pointer does not limit a plain commit on main" {
  # Simulates E-052-1_1: merged, DONE/release, weeks old — a LATER run's init
  # overwrote the pointer, so E-old is no longer "the" active run at all.
  local old_dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-old/R-old"
  _write_state_at "$old_dir" DONE task/E-old/main release
  local new_dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-new/R-new"
  _write_state_at "$new_dir" DONE task/E-new/main review   # supersedes E-old; doesn't itself govern main
  _write_pointer "$new_dir/fsm-state.yaml"
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (k) same OBS-20260712-01 class, EXECUTE/GATES side: an abandoned run
#     superseded by a later init must not block main forever either ──────────
@test "k: a stale abandoned EXECUTE run no longer referenced by the active-run pointer does not block a plain commit on main" {
  local old_dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-old/R-old"
  _write_state_at "$old_dir" EXECUTE task/E-old/main
  local new_dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-new/R-new"
  _write_state_at "$new_dir" DONE task/E-new/main review
  _write_pointer "$new_dir/fsm-state.yaml"
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (l) current active-run pointer, DONE/release → still enforces the
#     version whitelist (the fix narrows discovery, doesn't remove enforcement) ─
@test "l: current active-run pointer in DONE/release still enforces the version whitelist" {
  _write_project_versioning
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-cur/R-cur"
  _write_state_at "$dir" DONE task/E-cur/main release
  _write_pointer "$dir/fsm-state.yaml"
  _stage src/rogue.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DONE/release"* ]]
  [[ "$output" == *"src/rogue.txt"* ]]
}

# ─── (m) current active-run pointer, EXECUTE → still blocks a rogue commit
#     on main (OBS-20260709-04 protection fully preserved) ───────────────────
@test "m: current active-run pointer in EXECUTE still blocks a rogue commit on main" {
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-cur/R-cur"
  _write_state_at "$dir" EXECUTE task/E-cur/main
  _write_pointer "$dir/fsm-state.yaml"
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
}

# ─── (n) invalid pointer variants → fail open, never a new way to block ──────
@test "n: pointer referencing a missing state_file fails open (passes)" {
  _write_pointer "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-ghost/R-ghost/fsm-state.yaml"   # never created
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "n: malformed pointer JSON fails open (passes)" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  echo "{not valid json" > "$TEST_PROJECT_ROOT/.aid-o/work/active-run-pointer.json"
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "n: pointer with no state_file field fails open (passes)" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  echo '{"epic_id":"E-x"}' > "$TEST_PROJECT_ROOT/.aid-o/work/active-run-pointer.json"
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (i) companion: --no-verify bypass → commit_scope_violation at advance ────
@test "i: companion emits commit_scope_violation for out-of-scope --no-verify commit" {
  git checkout -q -b task/E-test/main
  _write_plan
  local sf="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  {
    echo "epic_id: E-test"
    echo "run_id: R-test"
    echo "state: EXECUTE"
    echo "current_step: 0"
    echo "total_steps: 2"
    echo "branch: task/E-test/main"
    echo "base_commit: $(git rev-parse HEAD)"
  } > "$sf"

  # A commit that lands OUTSIDE step0's scope (src/a.txt), pushed past the hook.
  _stage src/rogue.txt
  git commit -q --no-verify -m "rogue out-of-scope commit"
  # --force never waives the step's verification file (aid-fsm.sh).
  printf '# Step 0 Verification\n\n## Result: PASS\n\n- [x] acceptance criterion met\n\nCommit: %s\n\n## Memory Used\nN/A\n\n## Memory Written\nN/A\n' \
    "$(git rev-parse --short HEAD)" > "$TEST_EVIDENCE_DIR/step-0-verify.md"

  run bash "$FSM" increment-step "$sf" --force \
    --reason "companion out-of-scope --no-verify commit detection test exercise" \
    --blocked-checks dispatch_orphan_complete
  [ "$status" -eq 0 ]                      # non-blocking: increment still succeeds
  grep -q '"event":"commit_scope_violation"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q 'src/rogue.txt' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# ─── after the LAST step: union of all steps, not an empty set (ACTA #21) ────
@test "after the last step the guard scopes to the union of all steps, not nothing" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state EXECUTE task/E-test/main "" 2      # current_step == total_steps
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"plan.json declares no allowed_paths"* ]]
  _stage src/elsewhere.txt
  run bash "$HOOK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"union of all steps"* ]]
}

# ── P111 Step 3: a direct run on plan/<id>; Step 5: an abandoned run's branch ──
_write_direct() { _write_state "$@"; echo "direct: true" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"; }

@test "direct: the hook governs a direct run in EXECUTE on plan/<id> (an out-of-scope file is refused)" {
  git checkout -q -b plan/P111
  _write_plan; _write_direct EXECUTE plan/P111 "" 1
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside EXECUTE step 1 scope"* ]]
}

@test "direct: the hook still governs a direct run in DONE with done_phase: review" {
  git checkout -q -b plan/P111
  _write_plan; _write_direct DONE plan/P111 review 2
  _stage src/outside.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DONE/review"* ]]
}

@test "direct: the hook lets the close's commit through at done_phase: release" {
  git checkout -q -b plan/P111
  _write_plan; _write_direct DONE plan/P111 release 2
  _stage src/outside.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "abandon: a commit on the plan branch of an abandoned direct run is refused run_abandoned" {
  git checkout -q -b plan/P111
  _write_plan; _write_direct ERROR plan/P111 "" 1
  printf 'abandoned: true\nabandon_reason: the PM stopped it\n' >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: run_abandoned)"* && "$output" == *"next: "* ]]
}

@test "abandon: a commit on the task branch of an abandoned EPIC run is refused run_abandoned" {
  git checkout -q -b task/E-test/main
  _write_plan; _write_state ERROR task/E-test/main "" 1
  printf 'abandoned: true\nabandon_reason: superseded by a new plan\n' >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run_abandoned"* ]]
}

# ── P112 Step 6: the governing run comes from active-runs.json only ───────────
# _set_aside <dir> <step> — a set-aside copy of the run's state (same branch,
# an older step) where P016's copies lay, never in the map
_set_aside() {
  mkdir -p "$1"; sed "s/^current_step: .*/current_step: $2/" "$TEST_EVIDENCE_DIR/fsm-state.yaml" > "$1/fsm-state.yaml"
  cp "$TEST_EVIDENCE_DIR/plan.json" "$1/plan.json"
}

@test "hook-map: a set-aside copy of the state on the same branch does not govern — the live run's scope does" {
  git checkout -q -b plan/P111
  _write_plan; _write_state EXECUTE plan/P111 "" 1          # live: step 1 = src/b.txt
  _set_aside "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-test/A-early.superseded-1" 0   # sorts first; step 0 = src/a.txt
  _stage src/b.txt
  run bash "$HOOK"; echo "$output"
  [ "$status" -eq 0 ]
  git reset -q; _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]; [[ "$output" == *"outside EXECUTE step 1 scope"* ]]
}
@test "hook-map: the set-aside copy alone (no map entry) governs nothing" {
  git checkout -q -b plan/P111
  _write_plan; _write_state EXECUTE plan/P111 "" 1
  echo '{}' > "$TEST_PROJECT_ROOT/.aid-o/work/active-runs.json"
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}
@test "hook-map: an unreadable map refuses a commit on plan/<id> and lets a commit on another branch through" {
  git checkout -q -b plan/P111
  _write_plan; _write_state EXECUTE plan/P111 "" 1
  echo 'not json' > "$TEST_PROJECT_ROOT/.aid-o/work/active-runs.json"
  export AID_HOOK_AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  _stage src/b.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]; [[ "$output" == *"active_runs_unreadable"* ]]
  git checkout -q -b feature/y
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.rule, .outcome] | join(":")' "$AID_HOOK_AUDIT" | paste -sd' ')" = "active_runs_unreadable:block active_runs_unreadable:pass" ]
}
@test "hook-map: an abandoned run (not in the map) still refuses run_abandoned" {
  git checkout -q -b plan/P111
  _write_plan; _write_direct ERROR plan/P111 "" 1
  printf 'abandoned: true\nabandon_reason: the PM stopped it\n' >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  echo '{}' > "$TEST_PROJECT_ROOT/.aid-o/work/active-runs.json"
  _stage src/a.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]; [[ "$output" == *"run_abandoned"* ]]
}
