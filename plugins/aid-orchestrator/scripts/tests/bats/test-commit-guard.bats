#!/usr/bin/env bats
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
#   (g)  empty allowed_paths → warn + pass + disclosure
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

# _write_plan_empty_step1 — step1 has an empty allowed_paths list.
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

# ─── (d) GATES: gate-fix outside per-step but inside union → pass ─────────────
@test "d: GATES gate-fix inside the union of all steps passes" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state GATES task/E-test/main "" 1
  _stage src/a.txt                # step0 path: outside step1, inside union
  run bash "$HOOK"
  [ "$status" -eq 0 ]
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

# ─── (f) jq missing → warn + skip scope check (not blocked by absent tooling) ─
@test "f: jq missing warns and skips the scope check (commit not blocked)" {
  git checkout -q -b task/E-test/main
  _write_plan
  _write_state EXECUTE task/E-test/main "" 1
  _stage src/a.txt                # would FAIL scope if jq were present
  local farm; farm=$(_farm_excluding jq)
  run env PATH="$farm" bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq not found"* ]]
  grep -q '"reason":"jq_absent"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# ─── (g) empty allowed_paths → warn + pass + disclosure ───────────────────────
@test "g: empty allowed_paths warns, passes, and discloses" {
  git checkout -q -b task/E-test/main
  _write_plan_empty_step1
  _write_state EXECUTE task/E-test/main "" 1
  _stage src/whatever.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty allowed_paths"* ]]
  grep -q '"reason":"empty_allowed_paths"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# ─── (h) outside an AID run (no active state file) → no-op pass ───────────────
@test "h: no active AID run is a no-op pass" {
  # No state file written at all.
  _stage src/b.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (j) OBS-20260712-01 regression: a stale DONE/release run on a TASK
#     branch (not main) must never restrict a plain commit on main ─────────────
@test "j: a stale DONE/release run declared on a task branch does not limit a plain commit on main" {
  # Simulates E-052-1_1: merged, DONE/release, weeks old, branch: task/.../main
  # (not main itself). Stays checked out on main (no git checkout).
  _write_state DONE task/E-old/main release 1
  _stage src/anything.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

# ─── (k) order-independence + ambiguity: two runs both explicitly declare
#     branch: main in DONE/release → treated as ambiguous, never "pick one" ───
@test "k: two runs both declaring branch:main in DONE/release is ambiguous — passes, does not enforce either scope" {
  _write_project_versioning
  _write_state DONE main release 1
  _write_state_at "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-other/R-other" DONE main release
  # A file that would FAIL either run's version whitelist if one were picked.
  _stage src/rogue.txt
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ambiguous"* ]]
}

# ─── (l) a run explicitly declared on branch:main still enforces the
#     version whitelist on main (the fix narrows the match, doesn't remove it) ─
@test "l: a DONE/release run explicitly declared on branch:main still enforces the version whitelist" {
  _write_project_versioning
  _write_state DONE main release 1
  _stage src/rogue.txt
  run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DONE/release"* ]]
  [[ "$output" == *"src/rogue.txt"* ]]
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

  run bash "$FSM" increment-step "$sf" --force \
    --reason "companion out-of-scope --no-verify commit detection test exercise" \
    --blocked-checks dispatch_orphan_complete
  [ "$status" -eq 0 ]                      # non-blocking: increment still succeeds
  grep -q '"event":"commit_scope_violation"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q 'src/rogue.txt' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}
