#!/usr/bin/env bats
# test-roots-worktree.bats — P074 Step 1: shared invoke-root/state-root
# resolver (lib/aid-roots.sh) + cwd-relative site migration.
#
# THE GROUNDED FAILURE MODE UNDER TEST: `.aid-o/` is gitignored, so a fresh
# linked worktree has none — before this step, every cwd-relative `.aid-o`
# site invoked from inside a worktree silently created and used a SECOND
# empty workspace invisible to the primary status surfaces. Every migrated
# entrypoint invoked FROM INSIDE the worktree must read and write the
# PRIMARY `.aid-o`.
#
# The "no forked .aid-o at ANY point of the chain" assertion is enforced by
# a tripwire, not a post-hoc `-d` check: a regular FILE named `.aid-o` is
# planted at the worktree top level (NOT matched by the `.aid-o/` gitignore
# dir pattern, invisible to --untracked-files=no guards). Any chain member
# that still tried `mkdir -p .aid-o/...` relative to the worktree would fail
# on it and abort the pipeline — so a green end-to-end run PROVES no member
# touched a worktree-local workspace at any point.
#
# FD-3 HYGIENE: bats reports test results over fd 3; a
# spawned child that inherits and holds that fd open silently truncates the
# suite's TAP output (tests appear green because missing results still exit
# 0). Every heavyweight invocation below (FSM init, pipeline chain,
# plan-close-check, golden sequence) therefore runs with `3>&-` so no child
# of the AID script chain can ever hold bats' report fd. After any edit to
# this file, verify the full result count:
#   bats --tap test-roots-worktree.bats | grep -cE '^(ok|not ok)'   # == plan count (currently 32)

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPTS="$AID_PLUGIN_PATH/scripts"
  ROOTS="$SCRIPTS/lib/aid-roots.sh"
  FSM="$SCRIPTS/aid-fsm.sh"
  PIPELINE="$SCRIPTS/aid-auto-pipeline.sh"
  FIXTURES="$SCRIPTS/tests/fixtures"
  export SCRIPTS ROOTS FSM PIPELINE FIXTURES
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  # The resolver honours AID_PROJECT_ROOT — a stray value from the invoking
  # environment must never leak into fixture resolution.
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _mk_primary <dir> — a committed primary checkout with the .aid-o skeleton
# the pipeline expects; .aid-o/ gitignored exactly like a real AID project.
_mk_primary() {
  local d="$1"
  mkdir -p "$d/.aid-o/plans" "$d/.aid-o/tasks" "$d/.aid-o/config" \
           "$d/.aid-o/work/evidence" "$d/.aid-o/work/runs"
  printf 'counter: 0\n' > "$d/.aid-o/config/counter.yaml"
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed primary"
  )
}

# _mk_worktree <primary> <wt_path> [branch] — a linked worktree of <primary>.
_mk_worktree() {
  local primary="$1" wt="$2" branch="${3:-p074/wt}"
  git -C "$primary" worktree add -q "$wt" -b "$branch"
}

# _phys <dir> — physical path (matches what git/pwd -P report).
_phys() { (cd "$1" && pwd -P); }

# _plant_tripwire <wt> — the read-only FILE named .aid-o (see header).
_plant_tripwire() {
  printf 'P074 tripwire: no chain member may create .aid-o inside a worktree\n' > "$1/.aid-o"
  chmod 444 "$1/.aid-o"
}

# ─── resolver unit contract ──────────────────────────────────────────────

@test "aid_state_root from inside a linked worktree resolves the PRIMARY checkout root" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  run bash -c "cd '$TEST_TMPDIR/wt' && source '$ROOTS' && aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/primary")" ]
}

@test "aid_state_root from a subdirectory of the primary checkout resolves the top level" {
  _mk_primary "$TEST_TMPDIR/primary"
  mkdir -p "$TEST_TMPDIR/primary/src/deep"
  run bash -c "cd '$TEST_TMPDIR/primary/src/deep' && source '$ROOTS' && aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/primary")" ]
}

@test "aid_state_root outside any git repository fails exit 2 with the exact message (no \$PWD fallback)" {
  mkdir -p "$TEST_TMPDIR/norepo"
  run bash -c "cd '$TEST_TMPDIR/norepo' && source '$ROOTS' && aid_state_root"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: not inside a git repository — AID needs a repo root"* ]]
  [[ "$output" != *"$TEST_TMPDIR/norepo"* ]]   # it never printed a fallback root
}

@test "AID_PROJECT_ROOT pointing INTO a linked worktree canonicalizes to the primary root instead of forking state" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  run bash -c "cd '$TEST_TMPDIR/norepo-does-not-matter' 2>/dev/null; cd /; source '$ROOTS' && AID_PROJECT_ROOT='$TEST_TMPDIR/wt' aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/primary")" ]
}

@test "dogfood escape: AID_PROJECT_ROOT naming a root carrying its own .aid-o/work/plan-state wins as given" {
  _mk_primary "$TEST_TMPDIR/dogfood"
  mkdir -p "$TEST_TMPDIR/dogfood/.aid-o/work/plan-state"
  # Even resolved from INSIDE another repo, the named root is honoured.
  _mk_primary "$TEST_TMPDIR/other"
  run bash -c "cd '$TEST_TMPDIR/other' && source '$ROOTS' && AID_PROJECT_ROOT='$TEST_TMPDIR/dogfood' aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/dogfood")" ]
}

@test "AID_PROJECT_ROOT naming neither a repo root nor a plan-state carrier fails naming both accepted forms" {
  mkdir -p "$TEST_TMPDIR/junk"
  run bash -c "source '$ROOTS' && AID_PROJECT_ROOT='$TEST_TMPDIR/junk' aid_state_root"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git repository root"* ]]
  [[ "$output" == *".aid-o/work/plan-state"* ]]
}

@test "worktree with a STALE local .aid-o/config fork named as AID_PROJECT_ROOT still canonicalizes to the primary (narrow escape)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  # A stale fork left behind by the pre-P074 bug: config only, NO plan-state.
  mkdir -p "$TEST_TMPDIR/wt/.aid-o/config"
  run bash -c "source '$ROOTS' && AID_PROJECT_ROOT='$TEST_TMPDIR/wt' aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/primary")" ]
}

@test "cache validity: same-process cache is honoured across cwd changes and invalidated when AID_PROJECT_ROOT changes" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_primary "$TEST_TMPDIR/dogfood"
  mkdir -p "$TEST_TMPDIR/dogfood/.aid-o/work/plan-state"
  # Deliberately NOT a command-substitution subshell: aid_state_root runs in
  # THIS shell (stdout redirected to a file), so the cache variables mutate
  # in one live process across all four calls.
  source "$ROOTS"
  cd "$TEST_TMPDIR/primary"
  aid_state_root > "$TEST_TMPDIR/r1"
  # cwd changes, no override: the CACHE answers (still the primary), proving
  # the cached value is actually used in-process.
  cd "$TEST_TMPDIR/dogfood"
  aid_state_root > "$TEST_TMPDIR/r1b"
  # Override set AFTER caching: cache is keyed on the override → invalidated,
  # the new override is honoured.
  export AID_PROJECT_ROOT="$TEST_TMPDIR/dogfood"
  aid_state_root > "$TEST_TMPDIR/r2"
  # Override removed again: key mismatch → recomputed from $PWD.
  unset AID_PROJECT_ROOT
  cd "$TEST_TMPDIR/primary"
  aid_state_root > "$TEST_TMPDIR/r3"
  [ "$(cat "$TEST_TMPDIR/r1")"  = "$(_phys "$TEST_TMPDIR/primary")" ]
  [ "$(cat "$TEST_TMPDIR/r1b")" = "$(_phys "$TEST_TMPDIR/primary")" ]
  [ "$(cat "$TEST_TMPDIR/r2")"  = "$(_phys "$TEST_TMPDIR/dogfood")" ]
  [ "$(cat "$TEST_TMPDIR/r3")"  = "$(_phys "$TEST_TMPDIR/primary")" ]
}

@test "bare repository: resolution fails loudly instead of writing state next to a bare repo" {
  _mk_primary "$TEST_TMPDIR/primary"
  git clone -q --bare "$TEST_TMPDIR/primary" "$TEST_TMPDIR/bare.git"
  run bash -c "cd '$TEST_TMPDIR/bare.git' && source '$ROOTS' && aid_state_root"
  [ "$status" -eq 2 ]
  # Two environments, one outcome: with safe.bareRepository=explicit git
  # refuses the bare dir outright (our not-a-repo error); without it the
  # common-dir parent lacks a .git marker (our bare-repository error).
  # Either way the resolver fails loudly and never prints a usable root.
  [[ "$output" == *"bare repository"* || "$output" == *"not inside a git repository"* ]]
  [[ "$output" == ERROR:* ]]
}

@test "aid_invoke_root returns the WORKTREE top level from inside the worktree (tree ops stay local)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  mkdir -p "$TEST_TMPDIR/wt/sub"
  run bash -c "cd '$TEST_TMPDIR/wt/sub' && source '$ROOTS' && aid_invoke_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/wt")" ]
}

@test "aid_state_path: relative at the state root (historic byte-identity), absolute primary path from a worktree" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  run bash -c "cd '$TEST_TMPDIR/primary' && source '$ROOTS' && aid_state_path .aid-o/config/queue.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = ".aid-o/config/queue.yaml" ]
  run bash -c "cd '$TEST_TMPDIR/wt' && source '$ROOTS' && aid_state_path .aid-o/config/queue.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_phys "$TEST_TMPDIR/primary")/.aid-o/config/queue.yaml" ]
}

@test "shared lib and aid-plan-fsm.sh private resolver agree on the same contract from a worktree (anti-drift)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  # The plan FSM's contract formula: dirname of the absolute git common dir.
  expected="$(dirname "$(git -C "$TEST_TMPDIR/wt" rev-parse --path-format=absolute --git-common-dir)")"
  run bash -c "cd '$TEST_TMPDIR/wt' && source '$ROOTS' && aid_state_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

# ─── aid-fsm.sh init from a linked worktree ──────────────────────────────

@test "aid-fsm.sh init executed from a worktree writes ONLY the primary .aid-o (tripwire green)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary state_file
  primary="$(_phys "$TEST_TMPDIR/primary")"
  state_file="$primary/.aid-o/work/evidence/E-901-1_1/R-901/fsm-state.yaml"
  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' init E-901-1_1 R-901 2 manual main HEAD '$state_file'" 3>&-
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
  # State artefacts landed in the PRIMARY workspace...
  [ -f "$primary/.aid-o/work/evidence/E-901-1_1/R-901/timeline.jsonl" ]
  [ -f "$primary/.aid-o/work/active-runs.json" ]
  # ...and the worktree carries NO forked workspace (tripwire file untouched).
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "aid-fsm.sh init from a worktree with AID_PROJECT_ROOT set to the WORKTREE path still lands in the primary .aid-o" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary state_file
  primary="$(_phys "$TEST_TMPDIR/primary")"
  state_file="$primary/.aid-o/work/evidence/E-902-1_1/R-902/fsm-state.yaml"
  run bash -c "cd '$TEST_TMPDIR/wt' && AID_PROJECT_ROOT='$TEST_TMPDIR/wt' '$FSM' init E-902-1_1 R-902 2 manual main HEAD '$state_file'" 3>&-
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
  [ -f "$primary/.aid-o/work/evidence/E-902-1_1/R-902/timeline.jsonl" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "init dirty guard checks the INVOKING tree: dirt in the worktree blocks a worktree init, primary stays clean-checkable" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  local primary state_file
  primary="$(_phys "$TEST_TMPDIR/primary")"
  # Dirty the WORKTREE's tracked file only.
  printf 'dirty\n' >> "$TEST_TMPDIR/wt/README.md"
  state_file="$primary/.aid-o/work/evidence/E-903-1_1/R-903/fsm-state.yaml"
  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' init E-903-1_1 R-903 2 manual main HEAD '$state_file'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uncommitted changes"* ]]
  # The primary checkout, still clean, can init the same EPIC.
  run bash -c "cd '$primary' && '$FSM' init E-903-1_1 R-903 2 manual main HEAD '$state_file'" 3>&-
  [ "$status" -eq 0 ]
}

# ─── full generation chain from inside the worktree ──────────────────────

@test "full generation chain (auto-pipeline → plan-to-epic → epic-to-json → json-to-run → queue-add) from a worktree touches only the primary .aid-o" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary
  primary="$(_phys "$TEST_TMPDIR/primary")"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$primary/.aid-o/plans/P099-multi.md"

  run bash -c "cd '$TEST_TMPDIR/wt' && bash '$PIPELINE' --plan '$primary/.aid-o/plans/P099-multi.md' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]

  # The tripwire FILE is still a file — no chain member forked a workspace
  # inside the worktree at ANY point (a single mkdir would have aborted).
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]

  # Every stage's artefacts landed in the PRIMARY workspace:
  ls "$primary/.aid-o/tasks/"E-099-*.md >/dev/null                       # plan-to-epic
  find "$primary/.aid-o/work/evidence" -name plan.json | grep -q .       # epic-to-json
  find "$primary/.aid-o/work/runs" -name 'R-*.md' | grep -q .            # json-to-run
  find "$primary/.aid-o/work/evidence" -name fsm-state.yaml | grep -q .  # FSM init
  grep -q 'E-099-1_3' "$primary/.aid-o/config/queue.yaml"                # queue-add
  # the primary counter file is still the one and only counter (numeric-ID
  # plans derive EPIC ids from the plan id, so its VALUE is untouched — the
  # tripwire above already proves no forked counter exists in the worktree)
  [ -f "$primary/.aid-o/config/counter.yaml" ]
}

# ─── golden: primary-checkout behaviour preserved ────────────────────────

@test "golden: primary-checkout init sequence keeps historic RELATIVE state paths (no absolute-root leakage in output or layout)" {
  _mk_primary "$TEST_TMPDIR/primary"
  local primary state_file
  primary="$(_phys "$TEST_TMPDIR/primary")"
  state_file=".aid-o/work/evidence/E-910-1_1/R-910/fsm-state.yaml"
  run bash -c "cd '$primary' && '$FSM' init E-910-1_1 R-910 2 manual main HEAD '$state_file' && '$FSM' get-state '$state_file'" 3>&-
  [ "$status" -eq 0 ]
  # Byte-behaviour guard: at the state root every resolved path stays
  # RELATIVE, so the absolute fixture root must never appear in the output.
  [[ "$output" != *"$primary"* ]]
  # Historic layout intact.
  [ -f "$primary/$state_file" ]
  [ -f "$primary/.aid-o/work/evidence/E-910-1_1/R-910/timeline.jsonl" ]
  [ -f "$primary/.aid-o/work/active-runs.json" ]
  [[ "$output" == *READY* ]]
}

@test "golden: primary-checkout scripted sequence is byte-identical old (git-archive HEAD) vs new (working tree) scripts" {
  # A REAL before/after: the committed HEAD scripts are extracted via
  # `git archive` and the identical scripted sequence (full pipeline +
  # get-state + init + relative layout listing) runs against twin fixtures,
  # one per script tree. Combined stdout+stderr must be byte-identical after
  # normalizing ONLY controller_hash, timestamps/dates, duration_ms, commit
  # SHAs and the (necessarily different) fixture tmp roots.
  local repo_root="$AID_PLUGIN_PATH/../.."
  mkdir -p "$TEST_TMPDIR/old"
  git -C "$repo_root" archive HEAD plugins/aid-orchestrator | tar -x -C "$TEST_TMPDIR/old"
  local OLD_S="$TEST_TMPDIR/old/plugins/aid-orchestrator/scripts"
  local NEW_S="$SCRIPTS"

  _golden_seq() {  # $1=scripts dir  $2=fixture dir
    local S="$1" d="$2"
    (
      exec 3>&- 2>/dev/null || true   # never hand bats' report fd to the chain
      cd "$d"
      # AID_PLUGIN_PATH must not leak the NEW tree into the OLD run — each
      # tree derives its own plugin root from its scripts dir.
      unset AID_PLUGIN_PATH
      bash "$S/aid-auto-pipeline.sh" --plan "$PWD/.aid-o/plans/P099-multi.md" --queue-mode chain
      echo "pipeline_rc=$?"
      bash "$S/aid-fsm.sh" get-state ".aid-o/work/evidence/E-099-1_3/R-E099-1/fsm-state.yaml"
      echo "getstate_rc=$?"
      bash "$S/aid-fsm.sh" init E-910-1_1 R-910 2 manual main HEAD ".aid-o/work/evidence/E-910-1_1/R-910/fsm-state.yaml"
      echo "init_rc=$?"
      # P074 Step 15 adds the generation-transaction artifacts, which the old
      # (pre-migration) script tree cannot produce — they are a deliberate new
      # behaviour, not a migration side effect. This golden compares ROOT
      # RESOLUTION, so they are filtered out of the layout listing.
      find .aid-o -type f \
        | grep -vE 'generation/(transaction\.json(\.lock)?|generation-authority\.json)$' \
        | sort
      cat .aid-o/work/evidence/E-910-1_1/R-910/fsm-state.yaml
    ) 2>&1
  }
  _golden_norm() {  # $1=fixture root to blank
    sed -E "s#$1#FIXROOT#g; \
            s/controller_hash: [0-9a-f]+/controller_hash: H/; \
            s/\"duration_ms\": [0-9]+/\"duration_ms\": N/; \
            s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}(\.[0-9]+)?Z?/TS/g; \
            s/[0-9a-f]{40}/SHA/g; \
            s/[0-9]{4}-[0-9]{2}-[0-9]{2}/DATE/g"
  }

  _mk_primary "$TEST_TMPDIR/fold"
  _mk_primary "$TEST_TMPDIR/fnew"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$TEST_TMPDIR/fold/.aid-o/plans/P099-multi.md"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$TEST_TMPDIR/fnew/.aid-o/plans/P099-multi.md"

  _golden_seq "$OLD_S" "$TEST_TMPDIR/fold" | _golden_norm "$(_phys "$TEST_TMPDIR/fold")" > "$TEST_TMPDIR/out-old.txt"
  _golden_seq "$NEW_S" "$TEST_TMPDIR/fnew" | _golden_norm "$(_phys "$TEST_TMPDIR/fnew")" > "$TEST_TMPDIR/out-new.txt"

  if ! diff -u "$TEST_TMPDIR/out-old.txt" "$TEST_TMPDIR/out-new.txt" >&2; then
    false
  fi
}

@test "queue dependency revalidation FROM the worktree reads the PRIMARY dependency evidence (merged_done)" {
  # Regression test for the worktree-forked dependency-evidence read: the dep
  # has NO live branch, queue status is NOT completed, and no merge commit
  # names it — the ONLY unblock signal is the dep's fsm-state `state: DONE`
  # under the PRIMARY .aid-o. A cwd-relative read from the worktree finds
  # nothing and misreports the dependency as unresolved/failed.
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary
  primary="$(_phys "$TEST_TMPDIR/primary")"
  mkdir -p "$primary/.aid-o/work/evidence/E-770-1_2/R-1"
  printf 'epic_id: E-770-1_2\nrun_id: R-1\nstate: DONE\n' \
    > "$primary/.aid-o/work/evidence/E-770-1_2/R-1/fsm-state.yaml"
  cat > "$primary/.aid-o/config/queue.yaml" <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-770-1_2
  path: p
  status: queued
  depends_on: []
- epic_id: E-770-2_2
  path: p
  status: queued
  depends_on: ["E-770-1_2"]
YAML
  # No explicit queue/timeline args: the DEFAULTS must resolve to the primary
  # root from inside the worktree too.
  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' queue-revalidate E-770-2_2" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]
  grep -q '"resolution":"merged_done"' \
    "$primary/.aid-o/work/evidence/E-770-2_2/queue-revalidate.jsonl"
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "advance-to-gates invoked from the worktree completes INCLUDING the EXECUTE→GATES transition (report + precondition on the primary root)" {
  # Regression test for the round-3 blocker: advance-to-gates writes
  # gates_report.json under the PRIMARY root; cmd_transition's EXECUTE:GATES
  # precondition (check_preconditions) must look for it THERE, not under a
  # worktree-local .aid-o — otherwise the transition rejects right after the
  # gates succeeded.
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  ev="$primary/.aid-o/work/evidence/E-G1/R-G1"
  mkdir -p "$ev/gates"
  cat > "$ev/fsm-state.yaml" <<'EOF'
epic_id: E-G1
run_id: R-G1
state: EXECUTE
current_step: 1
total_steps: 1
base_commit: HEAD
branch: integration/gui-control-v2
streamlined_mode: false
EOF
  printf '{"ts":"2026-06-23T00:00:00Z","event":"run_started"}\n' > "$ev/timeline.jsonl"
  cat > "$primary/.aid-o/config/execution.yaml" <<'EOF'
version: '1.0'
gates:
  smoke:
    command: "echo 'smoke'"
    required: true
    timeout_seconds: 10
    max_retries: 0
EOF
  # CP3 verifier outputs for the EXECUTE→GATES precondition (post-deploy mode).
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-security.md"

  run bash -c "cd '$TEST_TMPDIR/wt' && AID_DEPLOY_DATE='2026-04-01T00:00:00Z' '$FSM' advance-to-gates '$ev/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"advance-to-gates: SUCCESS"* ]]
  grep -q '^state: GATES' "$ev/fsm-state.yaml"          # the transition ran
  [ -f "$ev/gates/gates_report.json" ]                  # report on the PRIMARY root
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]                       # tripwire file untouched
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "aid-plan-close-check.sh from the worktree behaves byte-identically to a primary-checkout run (state root resolved)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary CLOSE="$SCRIPTS/aid-plan-close-check.sh"
  primary="$(_phys "$TEST_TMPDIR/primary")"
  mkdir -p "$primary/.aid-o/plans"
  printf '**EPIC 1: a (Steps 1-1)**\n' > "$primary/.aid-o/plans/P800-x.md"
  local rc_p=0 rc_w=0 out_p out_w
  out_p="$(cd "$primary" && bash "$CLOSE" P800 2>&1 3>&-)" || rc_p=$?
  out_w="$(cd "$TEST_TMPDIR/wt" && bash "$CLOSE" P800 2>&1 3>&-)" || rc_w=$?
  [ "$rc_p" = "$rc_w" ]
  [ "$out_p" = "$out_w" ]
  # And the worktree run never mentioned (or wrote into) the worktree.
  [[ "$out_w" != *"$TEST_TMPDIR/wt"* ]]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "lib/aid-plan-state.sh + lib/aid-plan-manifest.sh from the worktree resolve paths and writes under the PRIMARY root" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary
  primary="$(_phys "$TEST_TMPDIR/primary")"
  # plan_state_path/plan_manifest_path print WITHOUT a trailing newline —
  # capture each separately and emit one per line.
  run bash -c "cd '$TEST_TMPDIR/wt' && source '$SCRIPTS/lib/aid-plan-state.sh' \
    && source '$SCRIPTS/lib/aid-plan-manifest.sh' \
    && printf '%s\n' \"\$(plan_state_path P901)\" \"\$(plan_manifest_path P901)\" \
    && plan_state_init P901 plan_branch plan/P901 main >/dev/null" 3>&-
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$primary/.aid-o/work/plan-state/P901/plan-state.yaml" ]
  [ "${lines[1]}" = "$primary/.aid-o/work/plan-state/P901/plan-boundary-manifest.json" ]
  [ -f "$primary/.aid-o/work/plan-state/P901/plan-state.yaml" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "invalid lib overrides fail loudly (exit 2, both accepted forms named) — no silent write to an arbitrary path" {
  mkdir -p "$TEST_TMPDIR/junk"
  _mk_primary "$TEST_TMPDIR/primary"
  # plan-state lib
  run bash -c "cd '$TEST_TMPDIR/primary' && source '$SCRIPTS/lib/aid-plan-state.sh' \
    && AID_PLAN_STATE_PROJECT_ROOT='$TEST_TMPDIR/junk' plan_state_path P901" 3>&-
  [ "$status" -eq 2 ]
  [[ "$output" == *"git repository root"* ]]
  [[ "$output" == *".aid-o/work/plan-state"* ]]
  # plan-manifest lib
  run bash -c "cd '$TEST_TMPDIR/primary' && source '$SCRIPTS/lib/aid-plan-manifest.sh' \
    && AID_PLAN_MANIFEST_PROJECT_ROOT='$TEST_TMPDIR/junk' plan_manifest_path P901" 3>&-
  [ "$status" -eq 2 ]
  [[ "$output" == *".aid-o/work/plan-state"* ]]
  # aid-fsm.sh advance-to-gates execution_yaml resolution
  run bash -c "cd '$TEST_TMPDIR/primary' && AID_PROJECT_ROOT='$TEST_TMPDIR/junk' \
    '$FSM' advance-to-gates /nonexistent-state.yaml" 3>&-
  [ "$status" -ne 0 ]
  # And nothing was ever written next to the junk directory.
  [ ! -d "$TEST_TMPDIR/junk/.aid-o" ]
}

@test "golden: a worktree-driven init produces the SAME primary .aid-o file layout as a primary-driven init (twin fixtures)" {
  # Twin A: init from the primary checkout.
  _mk_primary "$TEST_TMPDIR/a"
  ( cd "$TEST_TMPDIR/a" && "$FSM" init E-920-1_1 R-920 2 manual main HEAD \
      ".aid-o/work/evidence/E-920-1_1/R-920/fsm-state.yaml" >/dev/null 2>&1 3>&- )
  # Twin B: identical init, driven from inside a linked worktree.
  _mk_primary "$TEST_TMPDIR/b"
  _mk_worktree "$TEST_TMPDIR/b" "$TEST_TMPDIR/b-wt"
  ( cd "$TEST_TMPDIR/b-wt" && "$FSM" init E-920-1_1 R-920 2 manual main HEAD \
      "$(_phys "$TEST_TMPDIR/b")/.aid-o/work/evidence/E-920-1_1/R-920/fsm-state.yaml" >/dev/null 2>&1 3>&- )
  layout_a="$(cd "$TEST_TMPDIR/a" && find .aid-o -type f | sort)"
  layout_b="$(cd "$TEST_TMPDIR/b" && find .aid-o -type f | sort)"
  [ -n "$layout_a" ]
  [ "$layout_a" = "$layout_b" ]
}

# ─── lifecycle commands (increment-step / done-advance) from the worktree ─

# _mk_run <primary> <epic_id> <run_id> — a minimal live run under the PRIMARY
# .aid-o: evidence dir, fsm-state.yaml and a seeded timeline.
_mk_run() {
  local primary="$1" epic="$2" run="$3" ev
  ev="$primary/.aid-o/work/evidence/${epic}/${run}"
  mkdir -p "$ev"
  cat > "$ev/fsm-state.yaml" <<EOF
epic_id: ${epic}
run_id: ${run}
state: DONE
done_phase: review
current_step: 0
total_steps: 2
base_commit: HEAD
branch: p074/wt
pm_decision: merge
streamlined_mode: false
EOF
  printf '{"ts":"2026-06-23T00:00:00Z","event":"run_started"}\n' > "$ev/timeline.jsonl"
  printf '%s\n' "$ev"
}

@test "done-advance review release --force from a worktree writes waiver + audit-log + compliance under the PRIMARY .aid-o (tripwire green)" {
  # The EPIC-review MAJOR: the forced release edge derived .aid-o and
  # project_root from \$PWD, so every artifact it produces (the waiver, the
  # cross-EPIC audit log, compliance.json) forked into a worktree-local
  # workspace — splitting exactly the state the shared resolver centralizes.
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  ev="$(_mk_run "$primary" E-905-1_1 R-905)"

  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' done-advance review release '$ev/fsm-state.yaml' \
    --force --reason 'worktree root-migration regression test for the forced release edge'" 3>&-
  [ "$status" -eq 0 ]

  # The phase actually advanced...
  grep -q '^done_phase: release' "$ev/fsm-state.yaml"
  # ...and all three PM-facing artifacts landed in the PRIMARY workspace.
  ls "$ev"/waiver-review-release-*.json >/dev/null
  [ -f "$primary/.aid-o/work/audit-log.jsonl" ]
  grep -q 'fsm_force_override' "$primary/.aid-o/work/audit-log.jsonl"
  [ -f "$ev/compliance.json" ]
  # The tripwire FILE is still a file — nothing mkdir'd a worktree .aid-o.
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "increment-step --force from a worktree writes its ledger, waiver and audit entry under the PRIMARY .aid-o (tripwire green)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _mk_worktree "$TEST_TMPDIR/primary" "$TEST_TMPDIR/wt"
  _plant_tripwire "$TEST_TMPDIR/wt"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  ev="$(_mk_run "$primary" E-906-1_1 R-906)"
  sed -i 's/^state: DONE/state: EXECUTE/' "$ev/fsm-state.yaml"
  # Step-verify evidence lives ONLY in the primary workspace: the ledger row
  # below can be written at all only if increment-step READ it from there.
  printf 'idempotency_token: TOK-906-0\nstep_id: S0\nplan_step_hash: h0\nreviewed_commit: c0\n' \
    > "$ev/step-0-verify.md"

  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' increment-step '$ev/fsm-state.yaml' \
    --force --reason 'worktree root-migration regression test for the forced step advance'" 3>&-
  [ "$status" -eq 0 ]

  grep -q '^current_step: 1' "$ev/fsm-state.yaml"
  grep -q 'TOK-906-0' "$ev/step-transition-ledger.jsonl"
  ls "$ev"/waiver-step-0-step-1-*.json >/dev/null
  grep -q 'fsm_force_override' "$primary/.aid-o/work/audit-log.jsonl"
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

# ─── P079 Step 1 (IMP-475): advance-to-gates redirects into the plan tree ──
#
# THE LIVE FAILURE: the first P076 run drove advance-to-gates from the PRIMARY
# checkout while the plan's work lived in a linked worktree. The gate COMMANDS
# therefore ran against main — a confident green about code they never saw.
# The fixture proves the redirect by making the gate command record its own
# `pwd`: a green run whose recorded pwd is the worktree is the only evidence
# that the commands saw the candidate tree.

# _seed_worktree_plan <primary> <plan_id> — a plan with a real branch, a real
# registered worktree and the plan-state record the enforcer reads.
_seed_worktree_plan() {
  local primary="$1" plan_id="$2" wt="$1/.aid-worktrees/plan-$2"
  bash -c "cd '$primary' && set -e
    export AID_PLAN_STATE_PROJECT_ROOT='$primary' AID_PLAN_MANIFEST_PROJECT_ROOT='$primary'
    source '$SCRIPTS/lib/aid-plan-state.sh'
    base=\$(git -C '$primary' rev-parse HEAD)
    git -C '$primary' branch plan/${plan_id} \"\$base\"
    plan_state_init ${plan_id} plan_branch plan/${plan_id} main >/dev/null
    git -C '$primary' worktree add -q '$wt' plan/${plan_id}
    plan_state_set_worktree_path ${plan_id} '$wt'" 3>&-
}

# _seed_gates_run <primary> <epic_id> — an EXECUTE run ready for
# advance-to-gates, with a gate command that records its working directory.
_seed_gates_run() {
  local primary="$1" epic_id="$2" ev="$1/.aid-o/work/evidence/$2/R-1"
  mkdir -p "$ev/gates"
  cat > "$ev/fsm-state.yaml" <<EOF
epic_id: ${epic_id}
run_id: R-1
state: EXECUTE
current_step: 1
total_steps: 1
base_commit: HEAD
branch: plan/P900
streamlined_mode: false
EOF
  printf '{"ts":"2026-08-10T00:00:00Z","event":"run_started"}\n' > "$ev/timeline.jsonl"
  cat > "$primary/.aid-o/config/execution.yaml" <<EOF
version: '1.0'
gates:
  where:
    command: "pwd -P > '${primary}/gate-cwd.txt'"
    required: true
    timeout_seconds: 30
    max_retries: 0
EOF
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-security.md"
  printf '%s' "$ev"
}

@test "P079 Step 1: advance-to-gates from the PRIMARY checkout re-executes inside the plan worktree (gate commands see the candidate tree)" {
  _mk_primary "$TEST_TMPDIR/primary"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  _seed_worktree_plan "$primary" P900
  ev="$(_seed_gates_run "$primary" E-900-1_1)"

  run bash -c "cd '$primary' && AID_DEPLOY_DATE='2026-04-01T00:00:00Z' '$FSM' advance-to-gates '$ev/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"executes in its own worktree"* ]]
  [ -f "$primary/gate-cwd.txt" ]
  [ "$(cat "$primary/gate-cwd.txt")" = "$(_phys "$primary/.aid-worktrees/plan-P900")" ]
  [ -f "$ev/gates/gates_report.json" ]                  # evidence on the PRIMARY root
  grep -q '^state: GATES' "$ev/fsm-state.yaml"
}

@test "P079 Step 1: a RELATIVE state-file argument survives the redirect (re-anchored, then absolutized)" {
  _mk_primary "$TEST_TMPDIR/primary"
  local primary
  primary="$(_phys "$TEST_TMPDIR/primary")"
  _seed_worktree_plan "$primary" P900
  _seed_gates_run "$primary" E-900-1_1 >/dev/null
  local rel=".aid-o/work/evidence/E-900-1_1/R-1/fsm-state.yaml"

  run bash -c "cd '$primary' && AID_DEPLOY_DATE='2026-04-01T00:00:00Z' '$FSM' advance-to-gates '$rel'" 3>&-
  [ "$status" -eq 0 ]
  [ "$(cat "$primary/gate-cwd.txt")" = "$(_phys "$primary/.aid-worktrees/plan-P900")" ]
  grep -q '^state: GATES' "$primary/$rel"
}

@test "P079 Step 1: a RECORDED but missing worktree refuses naming --recreate-worktree instead of running on the wrong tree" {
  _mk_primary "$TEST_TMPDIR/primary"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  _seed_worktree_plan "$primary" P900
  ev="$(_seed_gates_run "$primary" E-900-1_1)"
  rm -rf "$primary/.aid-worktrees/plan-P900"

  run bash -c "cd '$primary' && '$FSM' advance-to-gates '$ev/fsm-state.yaml'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"--recreate-worktree"* ]]
  [ ! -f "$primary/gate-cwd.txt" ]                      # no gate ran anywhere
  grep -q '^state: EXECUTE' "$ev/fsm-state.yaml"        # nothing advanced
}

@test "P079 Step 1: a legacy plan with NO recorded worktree is byte-identical to pre-P079 (gates run in the invoking tree)" {
  _mk_primary "$TEST_TMPDIR/primary"
  local primary ev
  primary="$(_phys "$TEST_TMPDIR/primary")"
  ev="$(_seed_gates_run "$primary" E-901-1_1)"

  run bash -c "cd '$primary' && AID_DEPLOY_DATE='2026-04-01T00:00:00Z' '$FSM' advance-to-gates '$ev/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" != *"executes in its own worktree"* ]]
  [ "$(cat "$primary/gate-cwd.txt")" = "$primary" ]
  grep -q '^state: GATES' "$ev/fsm-state.yaml"
}

# ─── guard grep: no unresolved literals sneak back in ────────────────────

@test "guard grep: aid-fsm.sh has zero raw remnants at the migrated sites (AC pattern)" {
  run grep -n 'pwd)/\.aid-o\|^\s*echo "\.aid-o' "$SCRIPTS/aid-fsm.sh"
  [ "$status" -ne 0 ]   # zero matches
}

@test "guard grep: zero unresolved .aid-o literals in the two generation entrypoints outside resolver-routed helpers" {
  for f in "$SCRIPTS/aid-auto-pipeline.sh" "$SCRIPTS/aid-json-to-run.sh"; do
    # Every non-comment line mentioning .aid-o must route through the
    # resolver (aid_state_path / aid_state_root).
    run bash -c "grep -n '\\.aid-o' '$f' | grep -v 'aid_state_path\\|aid_state_root' | grep -v '^[0-9]*:[[:space:]]*#'"
    if [ "$status" -eq 0 ]; then
      echo "unresolved .aid-o literal(s) in $f:" >&2
      echo "$output" >&2
      false
    fi
  done
}
