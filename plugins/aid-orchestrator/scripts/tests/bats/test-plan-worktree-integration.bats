#!/usr/bin/env bats
# aid-tier: t2
# test-plan-worktree-integration.bats — P074 Step 19: the whole promise, in one fixture.
#
# WHAT THIS SUITE IS FOR. Every other P074 suite proves one mechanism against a
# fixture built for that mechanism. None of them proves the thing the PM asked
# for, which is a SEQUENCE: plan B gets planned and generated while plan A is
# mid-implementation, from the same repository, with an unrelated dirty edit in
# the PM's own checkout, and a killed generation picks up where it stopped.
# That sequence is the plan's acceptance instrument, so it is exercised here
# end to end rather than assembled from unit-level claims. It replays the exact
# 2026-08-04/2026-08-05 pain: dirty tree + a second plan + a kill + a resume +
# review isolation.
#
# It also records, in section 6, exactly how far the dirty-tree half of that
# promise reaches TODAY — two pinned open gaps, carrying their production
# messages, rather than a fixture arranged to avoid them.
#
# THE TWO STREAMS
#   A  P941, `plan_branch` mode. plan-start creates .aid-worktrees/plan-P941 on
#      plan/P941; one EPIC is started and driven to mid-execution INSIDE that
#      worktree; later it completes and merges to the plan branch — all without
#      the primary checkout ever moving.
#   B  Planned and generated FROM THE PRIMARY CHECKOUT while A is live: the id
#      is allocated under the counter lock, the plan file is written, and the
#      generation transaction runs to completion (authority once, three phases,
#      three queue entries).
#
# HEAD STABILITY IS ASSERTED, NOT ASSUMED. `_b` brackets EVERY plan-B command
# with `git symbolic-ref HEAD` in the primary checkout and compares the two
# readings byte-for-byte. That is the single guarantee the whole plan exists to
# provide: the PM's tree is never borrowed.
#
# FAILURE NAMING (step Error Handling). `_ok` prefixes every assertion with the
# stream, the command and the fixture stage, so a red line identifies the
# owning step without reading the fixture.
#
# WHAT IS STUBBED, AND WHY THAT IS HONEST. Only the CP1 gate (a Codex-dependent
# stage — it is counted, not evaluated, because "how many times was authority
# minted" is the property under test) and, in the kill cases, thin wrappers
# that run the GENUINE script and then SIGKILL the pipeline at a real write
# boundary. Everything else — plan-start, the worktree, the enforcer,
# alloc, the pipeline, the queue writer, the hooks, the status recipes — is
# production code.
#
# NAMED SKIPS, NEVER A FALSE PASS. `yq` absent, `flock` absent, or a git too
# old for linked worktrees all SKIP with the reason and the version found.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits it can
# truncate this file's TAP output, and a `run` child exiting 127 destroys it
# outright (the bats warning is written to fd 3, which `3>&-` has closed). So
# every invocation runs with `3>&-` and every `run` goes through a `bash -c`,
# which can never itself be a missing command. After any edit verify:
#   bats --tap test-plan-worktree-integration.bats | grep -cE '^(ok|not ok)'   # == 9

load test-helpers.bash

PLAN_A="P941"
EPIC_A="E-941-1_1"

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  REPO_PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  # The /aid-status recipes resolve the plugin through AID_PLUGIN_PATH and
  # refuse without it — they are instructions written for an installed plugin.
  AID_PLUGIN_PATH="$REPO_PLUGIN"
  export AID_PLUGIN_PATH
  FIXTURES="$REPO_PLUGIN/scripts/tests/fixtures"
  TEST_TMPDIR="$(mktemp -d)"
  export REPO_PLUGIN FIXTURES TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  export ROOT
  unset AID_PROJECT_ROOT AID_WT_REDIRECTED AID_QUEUE_FILE AID_QUEUE_WRITE_PROJECT_ROOT
  unset AID_TEST_KILL_EPIC_TO_JSON AID_TEST_KILL_QUEUE_ADD AID_TEST_KILL_FINALIZE_REWRITE
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT" AID_PLAN_MANIFEST_PROJECT_ROOT="$ROOT"
  PLAN_FSM="$REPO_PLUGIN/scripts/aid-plan-fsm.sh"
  FSM="$REPO_PLUGIN/scripts/aid-fsm.sh"
  PRECOMMIT="$REPO_PLUGIN/defaults/hooks/pre-commit"
  STATUS_DOC="$REPO_PLUGIN/commands/aid-status.md"
  export PLAN_FSM FSM PRECOMMIT STATUS_DOC
  CP1_COUNT="$TEST_TMPDIR/cp1.count"; : > "$CP1_COUNT"
  export CP1_COUNT AID_TEST_CP1_COUNTER="$CP1_COUNT"
  export AID_TEST_E2J_COUNT="$TEST_TMPDIR/e2j.count"
  export AID_TEST_QADD_COUNT="$TEST_TMPDIR/qadd.count"
  _require_env
  _mk_shadow
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# ── environment preconditions: a named skip is the only honest degradation ──

_require_env() {
  command -v yq >/dev/null 2>&1 \
    || skip "yq is not installed — plan-state cannot be read or written, so neither stream can be built"
  command -v jq >/dev/null 2>&1 \
    || skip "jq is not installed — the transaction manifest and the active-runs map cannot be read"
  command -v flock >/dev/null 2>&1 \
    || skip "flock is not available — locked id allocation and the locked queue writer degrade (lib/aid-lock.sh documents this), so neither can be asserted here"
  git worktree list --porcelain >/dev/null 2>&1 \
    || skip "git $(git --version 2>/dev/null | awk '{print $3}') has no usable 'git worktree' — per-plan execution worktrees cannot be created"
}

# ── assertion vocabulary: every failure names stream, command and stage ─────

# _ok <stream> <command> <stage> <message> -- <test expression...>
_ok() {
  local stream="$1" cmd="$2" stage="$3" msg="$4"; shift 5   # the 5th is `--`
  if ! "$@"; then
    echo "INTEGRATION FAIL [stream ${stream}] [${cmd}] [fixture stage: ${stage}]: ${msg}" >&2
    return 1
  fi
  return 0
}

_contains() { [[ "$1" == *"$2"* ]]; }
_absent()   { [[ "$1" != *"$2"* ]]; }
_eq()       { [[ "$1" == "$2" ]]; }

# ── the shadow plugin: a symlink farm with a counting CP1 and kill wrappers ─
#
# Symlinks, not a copy: the plugin tree is large and every script must stay the
# genuine one. The three wrappers below each RUN the real script and only add a
# signal, so a kill exercises a real write-ordering window rather than a
# fabricated post-crash state.

_mk_shadow() {
  SHADOW="$TEST_TMPDIR/plugin"
  mkdir -p "$SHADOW/scripts"
  local f b
  for f in "$REPO_PLUGIN/scripts"/*; do
    b="$(basename "$f")"
    [[ "$b" == "tests" ]] && continue
    ln -s "$f" "$SHADOW/scripts/$b"
  done
  ln -s "$REPO_PLUGIN/defaults" "$SHADOW/defaults"

  rm -f "$SHADOW/scripts/aid-cp1-gate.sh"
  cat > "$SHADOW/scripts/aid-cp1-gate.sh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${AID_TEST_CP1_COUNTER:-}" ]] && printf 'call\n' >> "$AID_TEST_CP1_COUNTER"
echo "CP1 GATE: low-risk plan, no CP1-deep evidence required"
exit 0
STUB

  rm -f "$SHADOW/scripts/aid-epic-to-json.sh"
  cat > "$SHADOW/scripts/aid-epic-to-json.sh" <<STUB
#!/usr/bin/env bash
"$REPO_PLUGIN/scripts/aid-epic-to-json.sh" "\$@"
_rc=\$?
if [[ -n "\${AID_TEST_KILL_EPIC_TO_JSON:-}" ]]; then
  printf 'x' >> "\$AID_TEST_E2J_COUNT"
  _n=\$(wc -c < "\$AID_TEST_E2J_COUNT" | tr -d ' ')
  if [[ "\$_n" == "\$AID_TEST_KILL_EPIC_TO_JSON" ]]; then
    kill -9 "\$PPID" 2>/dev/null
    sleep 5
  fi
fi
exit \$_rc
STUB

  chmod +x "$SHADOW/scripts/aid-cp1-gate.sh" "$SHADOW/scripts/aid-epic-to-json.sh"
  PIPELINE="$SHADOW/scripts/aid-auto-pipeline.sh"
  export SHADOW PIPELINE
}

# ── the fixture repository ─────────────────────────────────────────────────

# _mk_primary — a committed checkout with the .aid-o skeleton, the gitignore a
# real AID project has, the pre-commit hook /aid-init installs, and a counter
# parked at 941 so the NEXT allocation is plan B's own id.
_mk_primary() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/tasks" "$ROOT/.aid-o/config" \
           "$ROOT/.aid-o/work/evidence" "$ROOT/.aid-o/work/runs"
  cat > "$ROOT/.aid-o/config/counter.yaml" <<'EOF'
# AID Orchestrator — Autoincrement ID Counters
plan: 941     # Last assigned plan number. Next: P942
epic: 0       # Last assigned ad-hoc EPIC number. Next: E-001
EOF
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  printf 'the PM is editing this\n' > "$ROOT/pm-notes.txt"
  (
    exec 3>&-
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
  cp "$PRECOMMIT" "$ROOT/.git/hooks/pre-commit"
  chmod +x "$ROOT/.git/hooks/pre-commit"
  FIXTURE_COMMIT="$(git -C "$ROOT" rev-parse HEAD 3>&-)"
  export FIXTURE_COMMIT
}

# _plan_branch_default — make a NEW plan (i.e. plan B, which the pipeline opens
# for itself) a plan_branch plan, which is what gives it its own execution
# worktree. BOTH files are required: the policy is only a CEILING, and
# `_pfsm_default_mode` downgrades to legacy with `plan_branch_unavailable:
# no_gate_profiles` unless the gate table the mode resolves against exists.
# Used only by the boundary case below — the repo default is legacy, and the
# main fixture deliberately runs plan B the way a default project would.
_plan_branch_default() {
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'default_mode: plan_branch\n' > "$ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"
  cat > "$ROOT/.aid-o/config/execution.yaml" <<'YML'
version: "1.0"
gates: {}
gate_profiles:
  release:
    include: []
YML
}

_wt_a() { printf '%s/.aid-worktrees/plan-%s' "$ROOT" "$PLAN_A"; }
_sf_a()  { printf '.aid-o/work/evidence/%s/R-A/fsm-state.yaml' "$EPIC_A"; }
_phys() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# _from <dir> <script> <args...> — a real CLI with <dir> as cwd. `bash -c` can
# never be a missing command, so no 127 ever reaches `run`.
_from() {
  local d="$1" prog="$2"; shift 2
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$d' && exec bash '$prog'${q}" 3>&-
}

# _head — the primary checkout's symbolic HEAD, verbatim (`refs/heads/main`).
# `symbolic-ref` and not `rev-parse`: a checkout that switched branch and came
# back would hide inside a sha comparison.
_head() { git -C "$ROOT" symbolic-ref HEAD 3>&-; }

# _b <label> <cmd...> — run a PLAN-B command from the primary checkout with the
# HEAD-stability bracket. Sets `B_STATUS` / `B_OUTPUT` for the caller and
# returns non-zero (with a named failure) if HEAD moved.
_b() {
  local label="$1"; shift
  local before after
  before="$(_head)"
  B_STATUS=0
  B_OUTPUT="$( "$@" 2>&1 )" || B_STATUS=$?
  after="$(_head)"
  if [[ "$before" != "$after" ]]; then
    echo "INTEGRATION FAIL [stream B] [${label}] [fixture stage: ${FIXTURE_STAGE:-?}]: the primary checkout's HEAD moved from '${before}' to '${after}' — a plan-B command borrowed the PM's tree" >&2
    return 1
  fi
  return 0
}

# ── stream A ───────────────────────────────────────────────────────────────

# _a_start — plan A opened in plan_branch mode: plan branch, plan-state,
# lifecycle manifest and the execution worktree at .aid-worktrees/plan-P941.
_a_start() {
  FIXTURE_STAGE="A:plan-start"
  cat > "$ROOT/.aid-o/plans/${PLAN_A}-stream-a.md" <<'MD'
---
id: P941
type: plan
status: ready
---
# Plan: stream A
**EPIC 1: implement**
MD
  run _from "$ROOT" "$PLAN_FSM" plan-start "$PLAN_A" --mode plan_branch --project-root "$ROOT"
  _ok A plan-start "$FIXTURE_STAGE" "plan-start failed: $output" -- [ "$status" -eq 0 ]
  _ok A plan-start "$FIXTURE_STAGE" "no execution worktree at $(_wt_a)" -- [ -d "$(_wt_a)" ]
}

# _a_epic_midexecution — the EPIC started, its run initialised (which the Step
# 8 enforcer redirects INTO the worktree), and driven to EXECUTE: stream A is
# now genuinely mid-implementation, which is the state everything else in this
# suite runs concurrently with.
_a_epic_midexecution() {
  FIXTURE_STAGE="A:mid-execution"
  run _from "$ROOT" "$PLAN_FSM" epic-start "$PLAN_A" "$EPIC_A" --project-root "$ROOT"
  _ok A epic-start "$FIXTURE_STAGE" "epic-start failed: $output" -- [ "$status" -eq 0 ]

  run _from "$ROOT" "$FSM" init "$EPIC_A" R-A 2 manual main HEAD "$(_sf_a)"
  _ok A init "$FIXTURE_STAGE" "init failed: $output" -- [ "$status" -eq 0 ]
  _ok A init "$FIXTURE_STAGE" "init did not redirect into the plan worktree" -- _contains "$output" "executes in its own worktree"
  # The task branch is checked out in the WORKTREE — never in the PM's tree.
  run bash -c "git -C '$(_wt_a)' symbolic-ref --short HEAD" 3>&-
  _ok A init "$FIXTURE_STAGE" "the worktree is not on the task branch (got: $output)" -- _eq "$output" "task/${EPIC_A}/main"

  # READY→EXECUTE's own precondition is a real plan.json for the run, in the
  # PRIMARY .aid-o (state never forks into the worktree) — seeded from the
  # shared fixture with this EPIC's id so the transition is the genuine one.
  local run_dir="$ROOT/.aid-o/work/evidence/${EPIC_A}/R-A"
  jq --arg e "$EPIC_A" '.epic_id = $e' "$FIXTURES/minimal-plan.json" > "$run_dir/plan.json"
  run _from "$ROOT" "$FSM" transition READY EXECUTE "$(_sf_a)"
  _ok A transition "$FIXTURE_STAGE" "READY→EXECUTE failed: $output" -- [ "$status" -eq 0 ]
}

# _a_dirty_pm_edit — the unrelated dirty TRACKED edit in the PM's own checkout.
# Before P074 this single line blocked plan-start, epic-start and the merge for
# the OTHER plan; it is the loosening's headline case, so it stays dirty for
# the whole of stream B.
_a_dirty_pm_edit() {
  printf 'an unrelated edit the PM has not committed\n' >> "$ROOT/pm-notes.txt"
}

# ── stream B ───────────────────────────────────────────────────────────────

# _b_allocate — plan B's id, minted through the locked allocator.
_b_allocate() {
  FIXTURE_STAGE="B:alloc"
  _b "alloc plan-id" _from "$ROOT" "$FSM" alloc plan-id || return 1
  PLAN_B="$(printf '%s' "$B_OUTPUT" | tail -1 | tr -d '[:space:]')"
  export PLAN_B
  _ok B "alloc plan-id" "$FIXTURE_STAGE" "allocation returned '${PLAN_B}', expected P942 from a counter at 941" -- _eq "$PLAN_B" "P942"
}

# _b_write_plan — plan B's file, derived from the shared multi-phase fixture so
# the generation has three real phases to partition.
_b_write_plan() {
  PLAN_B_FILE="$ROOT/.aid-o/plans/${PLAN_B}-second-stream.md"
  sed "s/P099/${PLAN_B}/g" "$FIXTURES/multi-phase-plan-numeric.md" > "$PLAN_B_FILE"
  export PLAN_B_FILE
  GEN_B="$ROOT/.aid-o/work/evidence/${PLAN_B}/generation"
  TX_B="$GEN_B/transaction.json"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  export GEN_B TX_B QUEUE
}

_b_generate() {
  FIXTURE_STAGE="${1:-B:generate}"
  _b "aid-auto-pipeline.sh --plan ${PLAN_B_FILE}" \
     bash -c "cd '$ROOT' && bash '$PIPELINE' --plan '$PLAN_B_FILE' --queue-mode chain" 3>&-
}

# _b_generate_unbracketed <stage> — the same run WITHOUT the HEAD-stability
# bracket. Used only by the pin below, whose whole subject is a HEAD move: the
# bracket would (correctly) abort the test at the very fact it exists to
# record.
_b_generate_unbracketed() {
  FIXTURE_STAGE="${1:-B:generate}"
  B_STATUS=0
  B_OUTPUT="$( bash -c "cd '$ROOT' && bash '$PIPELINE' --plan '$PLAN_B_FILE' --queue-mode chain" 2>&1 3>&- )" || B_STATUS=$?
}

# _b_generate_killed <phase> — a generation that REALLY dies (SIGKILL of the
# pipeline shell) after phase <phase-1>'s outputs are on disk. Its non-zero
# exit is expected and never propagated.
_b_generate_killed() {
  FIXTURE_STAGE="B:killed-generation"
  local before after
  before="$(_head)"
  # The `|| B_STATUS=$?` is mandatory, not style: the run is EXPECTED to die,
  # and bats runs test bodies under `set -e`, so an unguarded non-zero subshell
  # would abort the test at the kill instead of letting it assert the kill.
  B_STATUS=0
  ( cd "$ROOT" && AID_TEST_KILL_EPIC_TO_JSON="$1" bash "$PIPELINE" --plan "$PLAN_B_FILE" --queue-mode chain 3>&- ) >/dev/null 2>&1 || B_STATUS=$?
  after="$(_head)"
  _ok B "killed generation" "$FIXTURE_STAGE" "HEAD moved from '${before}' to '${after}' during a KILLED generation" -- _eq "$before" "$after"
}

_epics_b()  { ls "$ROOT/.aid-o/tasks"/E-942-*.md 2>/dev/null | wc -l | tr -d ' '; }
_queued_b() { grep -c 'epic_id: "E-942' "$QUEUE" 2>/dev/null || echo 0; }
_cp1_calls() { wc -l < "$CP1_COUNT" | tr -d ' '; }

# ── the /aid-status surface: the DOC is the implementation ─────────────────
#
# There is no status script by design (Step 12), so the render is assembled
# from the `# recipe:` blocks published in commands/aid-status.md — the same
# extraction test-status-two-streams.bats uses. A missing recipe becomes a
# named rc 1 here, never a 127 (which would destroy this file's TAP output).

_recipes() {
  awk '
    /^# recipe: / { inblk = 1; print; next }
    inblk && /^```$/ { inblk = 0; next }
    inblk { print }
  ' "$STATUS_DOC"
}

_render() {
  local body; body="$(_recipes)"
  # THE 127 TRAP, and why the tail of this command looks paranoid. bats' `run`
  # reacts to a child that exits 127 by writing a BW01 warning to fd 3 — which
  # `3>&-` has closed — and that write breaks the reporter, so the WHOLE FILE's
  # results vanish while the run still exits 0. `render_overview` is assembled
  # from a doc: any command it calls that is not installed makes the LAST
  # command of this `bash -c` exit 127, which is exactly that trap. The exit
  # code is therefore remapped: 127 becomes 98, which fails the assertion
  # loudly and visibly instead of silently deleting the suite's output.
  status=0
  output="$(bash -c "cd '$1' && $body
declare -F render_overview >/dev/null || { echo 'MISSING: render_overview is not defined by aid-status.md' >&2; exit 1; }
render_overview" 2>&1 3>&-)" || status=$?
}

_stage_in() {
  mkdir -p "$1/$(dirname "$2")"
  printf 'x\n' > "$1/$2"
  git -C "$1" add "$2" 3>&-
}

# ═══════════════════════════════════════════════════════════════════════════
# 1. THE WHOLE PROMISE, IN ORDER
# ═══════════════════════════════════════════════════════════════════════════

@test "P074: plan B is allocated, written and generated end-to-end while plan A implements in its worktree, and the primary checkout never moves" {
  _mk_primary
  local head0; head0="$(_head)"

  # ── stream A: opened, and genuinely mid-implementation ──────────────────
  _a_start
  _a_epic_midexecution

  # The PM's checkout is still on main, untouched by everything stream A did.
  _ok A fixture "A:mid-execution" "the primary checkout left main" -- _eq "$(_head)" "$head0"

  # ── stream B: allocation, plan file, generation ─────────────────────────
  _b_allocate
  _b_write_plan
  _b_generate
  _ok B generation "B:generate" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]

  # Authority minted ONCE for the whole plan (D26), three phases, three queue
  # entries, and a completed transaction.
  _ok B generation "B:generate" "CP1 ran $(_cp1_calls) times — authority must be minted once per plan" -- _eq "$(_cp1_calls)" "1"
  _ok B generation "B:generate" "expected 3 EPIC files, found $(_epics_b)" -- _eq "$(_epics_b)" "3"
  _ok B generation "B:generate" "expected 3 queue entries, found $(_queued_b)" -- _eq "$(_queued_b)" "3"
  _ok B generation "B:generate" "no generation authority receipt was written" -- [ -f "$GEN_B/generation-authority.json" ]
  run bash -c "jq -r '.phases | keys | sort | join(\",\")' '$TX_B'" 3>&-
  _ok B generation "B:generate" "the transaction does not record three phases (got: $output)" -- _eq "$output" "1,2,3"

  # ── the guarantee: the PM's tree never moved ───────────────────────────
  _ok B generation "B:generate" "the primary checkout's HEAD changed across the generation" -- _eq "$(_head)" "$head0"

  # ── stream A finishes, in its own worktree, afterwards ─────────────────
  FIXTURE_STAGE="A:completion"
  # The EPIC's delivery, committed on the task branch IN THE WORKTREE. The path
  # is inside the run's step-1 allowed_paths on purpose: the installed hook now
  # resolves the state root from a linked worktree (Step 2), so the commit-scope
  # guard is LIVE here — committing outside scope is correctly refused, and
  # arranging for that would be arranging the fixture around a working guard.
  run bash -c "cd '$(_wt_a)' && mkdir -p src/core && printf 'the delivery\n' > src/core/module.py \
    && git add src/core/module.py && git -c user.email=a@t -c user.name=A commit -qm 'A: the delivery'" 3>&-
  _ok A commit "$FIXTURE_STAGE" "could not commit the delivery in the worktree: $output" -- [ "$status" -eq 0 ]

  # done-advance, driven from the PRIMARY checkout: the Step 8 enforcer moves
  # it into A's worktree, and the plan_branch path advances review→release
  # without touching the per-EPIC release stack.
  _a_seed_done_review
  run _from "$ROOT" "$FSM" done-advance review release "$(_sf_a)"
  _ok A done-advance "$FIXTURE_STAGE" "done-advance failed: $output" -- [ "$status" -eq 0 ]
  _ok A done-advance "$FIXTURE_STAGE" "done-advance did not run in the plan worktree" -- _contains "$output" "executes in its own worktree"
  _ok A done-advance "$FIXTURE_STAGE" "the primary checkout moved during done-advance" -- _eq "$(_head)" "$head0"

  # epic-merge-to-plan, also from the primary checkout: the merge lands on
  # plan/P941 inside the worktree and the PM's tree never sees the delivery.
  _a_seed_completion_evidence
  run _from "$ROOT" "$PLAN_FSM" epic-merge-to-plan "$PLAN_A" "$EPIC_A" --project-root "$ROOT"
  _ok A epic-merge-to-plan "$FIXTURE_STAGE" "the merge failed: $output" -- [ "$status" -eq 0 ]
  _ok A epic-merge-to-plan "$FIXTURE_STAGE" "the merge did not run in the plan worktree" -- _contains "$output" "executes in its own worktree"
  run bash -c "git -C '$ROOT' log --format=%H plan/${PLAN_A} -- src/core/module.py | head -1" 3>&-
  _ok A epic-merge-to-plan "$FIXTURE_STAGE" "the delivery is not reachable from plan/${PLAN_A}" -- [ -n "$output" ]
  _ok A epic-merge-to-plan "$FIXTURE_STAGE" "the delivery leaked into the PM's checkout" -- [ ! -f "$ROOT/src/core/module.py" ]
  _ok A epic-merge-to-plan "$FIXTURE_STAGE" "the primary checkout moved during the merge" -- _eq "$(_head)" "$head0"
}

# _a_seed_done_review — stream A's run parked at DONE/review with the minimum
# evidence done-advance reads, written where the run actually lives.
_a_seed_done_review() {
  local dir="$ROOT/.aid-o/work/evidence/${EPIC_A}/R-A"
  mkdir -p "$dir/gates"
  cat > "$dir/fsm-state.yaml" <<YAML
epic_id: ${EPIC_A}
run_id: R-A
branch: task/${EPIC_A}/main
state: DONE
done_phase: review
streamlined_mode: false
created_at: 2026-08-06T00:00:00Z
total_steps: 2
current_step: 2
pm_decision: merge
YAML
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-08-06T00:00:00Z","_command_log":[]}\n' \
    > "$dir/gates/gates_report.json"
  touch "$ROOT/.aid-o/work/audit-log.jsonl"
  cat > "$ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$REPO_PLUGIN"
dispatch_mode: subagent
YAML
}

# _a_seed_completion_evidence — the task-sha-bound epic-complete record
# epic-merge-to-plan requires (P068 F2). The evidence goes where epic-start
# RECORDED the run (`R-<epic_id>-plan`), not where this fixture's own `init`
# run lives: epic-complete reads the manifest entry, and seeding the wrong
# directory would make the merge refuse for a reason that has nothing to do
# with the two-stream property under test.
_a_seed_completion_evidence() {
  local dir="$ROOT/.aid-o/work/evidence/${EPIC_A}/R-${EPIC_A}-plan"
  mkdir -p "$dir/gates"
  printf 'epic_id: %s\nstate: DONE\ndone_phase: release\n' "$EPIC_A" > "$dir/fsm-state.yaml"
  run _from "$ROOT" "$PLAN_FSM" epic-complete "$PLAN_A" "$EPIC_A" --project-root "$ROOT"
  _ok A epic-complete "A:completion" "epic-complete failed: $output" -- [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. THE KILL AND THE RESUME
# ═══════════════════════════════════════════════════════════════════════════

@test "P074: a generation KILLED after phase 1 resumes to completion — phase 1 verified, authority reused, nothing duplicated" {
  _mk_primary
  local head0; head0="$(_head)"
  _a_start
  _a_epic_midexecution
  _b_allocate
  _b_write_plan

  # A REAL SIGKILL of the pipeline, after phase 1's outputs are durable and
  # before phase 2 is recorded.
  _b_generate_killed 2
  _ok B "killed generation" "B:killed-generation" "the pipeline did not actually die (rc=${B_STATUS})" -- [ "$B_STATUS" -ne 0 ]
  _ok B "killed generation" "B:killed-generation" "no transaction manifest survived the kill" -- [ -f "$TX_B" ]
  run bash -c "jq -r '.phases[\"1\"].epic_sha256 // \"none\"' '$TX_B'" 3>&-
  _ok B "killed generation" "B:killed-generation" "phase 1 was not recorded before the kill" -- [ "$output" != "none" ]
  run bash -c "jq -r '.phases[\"2\"].epic_sha256 // \"none\"' '$TX_B'" 3>&-
  _ok B "killed generation" "B:killed-generation" "phase 2 was recorded, so the kill missed its window" -- _eq "$output" "none"

  local phase1; phase1="$(jq -r '.phases["1"].epic_sha256' "$TX_B")"
  : > "$CP1_COUNT"

  # THE RESUME, from the primary checkout, with stream A still live.
  _b_generate "B:resume"
  _ok B resume "B:resume" "the resumed pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]
  _ok B resume "B:resume" "phase 1 was regenerated instead of verified" -- _contains "$B_OUTPUT" "verified against the transaction"
  _ok B resume "B:resume" "phase 1's recorded output changed across the resume" -- _eq "$(jq -r '.phases["1"].epic_sha256' "$TX_B")" "$phase1"
  _ok B resume "B:resume" "the sealed authority was re-minted ($(_cp1_calls) CP1 calls)" -- _eq "$(_cp1_calls)" "0"
  _ok B resume "B:resume" "expected 3 EPIC files after the resume, found $(_epics_b)" -- _eq "$(_epics_b)" "3"
  _ok B resume "B:resume" "expected 3 queue entries after the resume, found $(_queued_b)" -- _eq "$(_queued_b)" "3"
  _ok B resume "B:resume" "the primary checkout moved across kill + resume" -- _eq "$(_head)" "$head0"
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. HEAD STABILITY, COMMAND BY COMMAND
# ═══════════════════════════════════════════════════════════════════════════

@test "P074: every plan-B command leaves the primary checkout's symbolic HEAD byte-identical" {
  _mk_primary
  _a_start
  _a_epic_midexecution
  local head0; head0="$(_head)"

  # Each `_b` call brackets its command with a symbolic-ref reading and fails
  # by name if the two differ — so the assertions below are the brackets.
  _b_allocate
  _ok B "alloc plan-id" "B:head-stability" "HEAD moved across allocation" -- _eq "$(_head)" "$head0"
  _b_write_plan
  _b_generate "B:head-stability"
  _ok B generation "B:head-stability" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]
  _ok B generation "B:head-stability" "HEAD moved across generation" -- _eq "$(_head)" "$head0"

  # The decisive shape at the end: stream A's tree is elsewhere, on its own
  # task branch, and the PM's checkout is still exactly where it was — even
  # though plan B, being a DEFAULT (legacy) plan, has no worktree of its own
  # and every one of its commands therefore ran in the primary checkout. That
  # is the harder case, not the easier one: HEAD stability here is a property
  # of the commands, not a side effect of them running somewhere else.
  _ok A fixture "B:head-stability" "plan A's worktree is gone" -- [ -d "$(_wt_a)" ]
  _ok A fixture "B:head-stability" "plan A's worktree resolves to the primary checkout" -- [ "$(_phys "$(_wt_a)")" != "$(_phys "$ROOT")" ]
  run bash -c "git -C '$(_wt_a)' symbolic-ref --short HEAD" 3>&-
  _ok A fixture "B:head-stability" "stream A's worktree left its task branch (got: $output)" -- _eq "$output" "task/${EPIC_A}/main"
  _ok B fixture "B:head-stability" "the primary checkout is no longer on main" -- _eq "$(_head)" "refs/heads/main"
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. THE STATUS SURFACE RENDERS BOTH STREAMS
# ═══════════════════════════════════════════════════════════════════════════

@test "P074: the /aid-status data files render BOTH streams from the live two-stream fixture" {
  _mk_primary
  _a_start
  _a_epic_midexecution
  _b_allocate
  _b_write_plan
  _b_generate "status"
  _ok B generation "status" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]

  _render "$ROOT"
  _ok "A+B" render_overview "status" "the render failed: $output" -- [ "$status" -eq 0 ]
  # Stream A is a plan with lifecycle state, so it renders as a PLAN BLOCK —
  # with the execution worktree named, which is the two-stream surface's whole
  # point: the operator can see WHERE each stream is running.
  _ok A render_overview "status" "stream A does not appear as a plan block. RENDER WAS:
$output" -- _contains "$output" "Plan ${PLAN_A}"
  _ok A render_overview "status" "stream A's EPIC row does not appear" -- _contains "$output" "$EPIC_A"
  _ok A render_overview "status" "stream A's execution worktree is not shown" -- _contains "$output" ".aid-worktrees/plan-${PLAN_A}"

  # Stream B is a DEFAULT (legacy) plan: it has no plan-state, so by design it
  # has no plan block of its own — asserting one would be asserting a lifecycle
  # record that must not exist. What it DOES contribute is its three queued
  # EPICs, and the queue summary counts them, so the second stream is visible
  # in the same overview rather than invisible until someone opens the queue.
  _ok B render_overview "status" "stream B's three queued EPICs are not reflected in the queue summary. RENDER WAS:
$output" -- _contains "$output" "3 queued"

  # The same overview renders from INSIDE a plan worktree — the state root is
  # resolved through the git common dir, not from the cwd.
  local from_primary="$output"
  _render "$(_wt_a)"
  _ok "A+B" render_overview "status" "the render from inside the worktree failed: $output" -- [ "$status" -eq 0 ]
  _ok "A+B" render_overview "status" "the overview differs when rendered from inside plan A's worktree" -- _eq "$output" "$from_primary"
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. MAIN IS GOVERNED WHILE EITHER STREAM RUNS
# ═══════════════════════════════════════════════════════════════════════════

@test "P074: BOTH streams hold their own slot in the active-runs map, and a plan-mode run deliberately does not govern main" {
  _mk_primary
  _a_start
  _a_epic_midexecution
  _b_allocate
  _b_write_plan
  _b_generate "B:governs-main"
  _ok B generation "B:governs-main" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]

  # Both streams are in the map at once — the single slot could only ever hold
  # the LATER init, which is the regression Step 4 closed.
  local map="$ROOT/.aid-o/work/active-runs.json"
  run bash -c "jq -r 'keys | sort | join(\",\")' '$map'" 3>&-
  _ok A active-runs "B:governs-main" "stream A is missing from the active-runs map (got: $output)" -- _contains "$output" "$EPIC_A"
  _ok B active-runs "B:governs-main" "stream B's runs are missing from the active-runs map (got: $output)" -- _contains "$output" "E-942-1_3"

  # And the map records the TRUE governance fact PER RUN, which is what makes
  # one entry per run necessary rather than tidy: stream A's EPIC belongs to a
  # plan_branch plan and merges to the PLAN branch, so it does not govern main;
  # stream B is a default (legacy) plan whose EPICs release individually, so
  # each of them does. A single slot cannot represent both answers at once.
  run bash -c "jq -r '.\"${EPIC_A}\".governs_main' '$map'" 3>&-
  _ok A active-runs "B:governs-main" "stream A's plan_branch run claims to govern main (got: $output)" -- _eq "$output" "false"
  run bash -c "jq -r '.\"E-942-1_3\".governs_main' '$map'" 3>&-
  _ok B active-runs "B:governs-main" "stream B's legacy run does not govern main (got: $output)" -- _eq "$output" "true"
}

@test "P074: a main-branch commit is BLOCKED while a run that DOES govern main is live, with both plan streams running" {
  _mk_primary
  _a_start
  _a_epic_midexecution
  _b_allocate
  _b_write_plan
  _b_generate "governs-main"
  _ok B generation "governs-main" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]

  # A third run that genuinely governs main: an ad-hoc EPIC with no plan
  # lifecycle, i.e. the legacy per-EPIC release model, driven to EXECUTE.
  local sf=".aid-o/work/evidence/E-777-1_1/R-C/fsm-state.yaml"
  run _from "$ROOT" "$FSM" init E-777-1_1 R-C 1 manual main HEAD "$sf"
  _ok C init "governs-main" "the governing run could not be initialised: $output" -- [ "$status" -eq 0 ]
  jq --arg e "E-777-1_1" '.epic_id = $e' "$FIXTURES/minimal-plan.json" \
    > "$ROOT/.aid-o/work/evidence/E-777-1_1/R-C/plan.json"
  run _from "$ROOT" "$FSM" transition READY EXECUTE "$sf"
  _ok C transition "governs-main" "READY→EXECUTE failed: $output" -- [ "$status" -eq 0 ]
  run bash -c "jq -r '.\"E-777-1_1\".governs_main' '$ROOT/.aid-o/work/active-runs.json'" 3>&-
  _ok C active-runs "governs-main" "the legacy run does not govern main (got: $output)" -- _eq "$output" "true"

  # init auto-checked out the task branch; the PM's tree goes back to main,
  # which is where a rogue commit would be attempted from.
  run bash -c "cd '$ROOT' && git checkout -q main" 3>&-
  _ok C fixture "governs-main" "could not return the primary checkout to main: $output" -- [ "$status" -eq 0 ]
  _stage_in "$ROOT" src/rogue.txt
  run bash -c "cd '$ROOT' && git commit -m 'rogue on main while three runs are live'" 3>&-
  _ok C pre-commit "governs-main" "a commit on main was allowed while a governing run was live" -- [ "$status" -ne 0 ]
  _ok C pre-commit "governs-main" "the refusal does not name the branch it protected: $output" -- _contains "$output" "HEAD is 'main'"
}

# ═══════════════════════════════════════════════════════════════════════════
# 6. THE DIRTY PM EDIT, THE RESTORE CONTRACT, AND THE WIRED epic-start
# ═══════════════════════════════════════════════════════════════════════════
#
# READ THIS BEFORE CHANGING THE THREE TESTS BELOW. The Step 5 loosening is real
# and is asserted positively here: with an unrelated dirty TRACKED edit in the
# primary checkout, plan-start, epic-start, the locked allocation and the whole
# generation phase loop all proceed, and the edit survives byte-identically.
# Every one of those used to refuse on the repo-wide clean-worktree preflight.
#
# Until P075 the promise did NOT hold all the way to a queued EPIC, and this
# section pinned two open gaps. BOTH are now closed, and what replaced each pin
# is the behaviour that closed it:
#
#   LEGACY plan B (the default, no gate profiles: no execution worktree)
#     `aid-fsm.sh init` runs in the PRIMARY checkout, auto-creates and CHECKS
#     OUT `task/<epic>/main` there, and only then hits its own uncommitted-
#     changes guard — the one Step 5 deliberately KEPT, because done-advance
#     needs a clean diff to attribute. That refusal is DESIGN, not a gap, and
#     it stays. What was a gap is what happened next: `aid-json-to-run.sh` runs
#     under `set -e`, so the refusal aborted it at the init call, BEFORE the
#     branch restore, leaving the PM's checkout parked on the task branch init
#     had just created — the "borrowed the PM's tree" outcome, produced by the
#     very check that was protecting it. init's status is now captured, the
#     restore runs either way, and only then is the failure re-raised. That is
#     the BRANCH-RESTORE CONTRACT, and the first test below is its case: a
#     genuinely failing init with the caller's branch handed back.
#
#   PLAN_BRANCH plan B (with the gate table, so plan-start gives it a worktree)
#     `init` redirects INTO plan B's own worktree, where the tree is clean and
#     the PM's edit is irrelevant — and then used to refuse on the plan-branch
#     lineage check, because nothing ever ran `epic-start` for the EPICs the
#     pipeline had just generated. `epic-start` is now a named stage of the
#     generation chain (aid-json-to-run.sh, gated on --plan-mode plan_branch),
#     so the lineage check is satisfied and the EPIC initialises. The second
#     test below asserts the registration ITSELF — the ledger and the
#     production log line — not merely the absence of the old refusal.
#
# ONE GAP REMAINS, AND IT IS PINNED RATHER THAN AVOIDED. init leaves the plan
# worktree on the phase's task branch, and the restore returns the CALLER's
# checkout (the primary one, which never moved). So phase 2 of a MULTI-phase
# plan_branch plan redirects into a worktree still on phase 1's task branch and
# hard-fails the cross-EPIC mismatch. Phase 1 completes; phase 2 does not. The
# second test pins that with its production message; the third test proves the
# path is otherwise sound by running a SINGLE-phase plan_branch plan green.
#
# WHICH PATH EACH TEST TAKES IS ASSERTED, NOT ASSUMED. `plan_branch` is only
# reachable when the fixture has BOTH the policy default AND a `gate_profiles`
# table (see _plan_branch_default) — without the table the mode resolver
# downgrades to legacy and a test meaning to exercise the plan-branch path
# would silently exercise the legacy one. Every test below reads the mode back
# out of the COMMITTED lifecycle manifest, which is the same source the
# pipeline's own resolver uses, and fails by name if it is not the intended one.

# _b_recorded_mode — plan B's mode as the pipeline's own resolver reads it:
# from the COMMITTED lifecycle manifest on the target branch, never from the
# default-mode resolver (which answers a different question and downgrades).
_b_recorded_mode() {
  git -C "$ROOT" show "main:.aid-lifecycle/manifests/${PLAN_B}.yaml" 2>/dev/null \
    | yq -r '.mode // "none"' 2>/dev/null || printf 'none'
}

# _b_epic_start_ops — how many epic-start records plan B's operation ledger
# carries. The ledger is the durable receipt; the log line is the narration.
_b_epic_start_ops() {
  local f="$ROOT/.aid-o/work/plan-state/${PLAN_B}/operations.jsonl"
  [[ -f "$f" ]] || { printf '0'; return 0; }
  jq -r 'select(.command == "epic-start") | .subject' "$f" 2>/dev/null \
    | sort -u | wc -l | tr -d ' '
}

@test "P074/P075: a dirty tracked edit no longer blocks the second stream's planning or generation, and the kept init guard now hands the caller's branch back before it reports" {
  _mk_primary
  _a_start
  _a_dirty_pm_edit
  local dirty_before; dirty_before="$(cat "$ROOT/pm-notes.txt")"
  local head0; head0="$(_head)"

  # Every command here used to refuse on the repo-wide clean-tree preflight.
  _a_epic_midexecution
  _b_allocate
  _b_write_plan
  _b_generate_unbracketed "dirty-tree"

  # THE PATH UNDER TEST: plan B is a DEFAULT plan, so no gate_profiles table,
  # so legacy mode — init runs in the PRIMARY checkout and the PM's edit is in
  # the tree it evaluates. Asserted, because a plan_branch plan B would take
  # the redirect and never reach the guard this test is about.
  _ok B fixture "dirty-tree" "plan B is not the legacy plan this test needs (recorded mode: $(_b_recorded_mode))" -- _absent "$(_b_recorded_mode)" "plan_branch"
  _ok B fixture "dirty-tree" "plan B got an execution worktree, so init would redirect out of the PM's tree" -- [ ! -d "$ROOT/.aid-worktrees/plan-${PLAN_B}" ]

  # Stage 1 — the generation itself — completes with the edit in place.
  _ok B generation "dirty-tree" "the CP1 authority was not sealed with a dirty tree present" -- [ -f "$GEN_B/generation-authority.json" ]
  _ok B generation "dirty-tree" "generation did not produce all three EPICs (found $(_epics_b))" -- _eq "$(_epics_b)" "3"
  run bash -c "jq -r '.phases | keys | sort | join(\",\")' '$TX_B'" 3>&-
  _ok B generation "dirty-tree" "the transaction does not record three phases (got: $output)" -- _eq "$output" "1,2,3"

  # And the PM's edit is untouched by either stream.
  _ok "A+B" fixture "dirty-tree" "the PM's uncommitted edit was altered by the two streams" -- _eq "$(cat "$ROOT/pm-notes.txt")" "$dirty_before"
  run bash -c "git -C '$ROOT' status --porcelain" 3>&-
  _ok "A+B" fixture "dirty-tree" "the PM's edit is no longer reported as modified: $output" -- _contains "$output" "pm-notes.txt"

  # THE KEPT GUARD, WHICH IS DESIGN: init refuses on the dirty tree it runs in,
  # because done-advance must attribute a clean diff to the EPIC's work. The
  # failure is still REPORTED — the restore must not swallow it.
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "stage 2 stopped reporting the kept dirty guard as a failure — the restore is swallowing init's status" -- [ "$B_STATUS" -ne 0 ]
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "the refusal is not the kept dirty guard: $B_OUTPUT" -- _contains "$B_OUTPUT" "Uncommitted changes present"

  # THE BRANCH-RESTORE CONTRACT: init really did create and check out the task
  # branch on its way to refusing — so the restore was real work, not a no-op —
  # and the caller's branch is back, with the failure line saying so.
  run bash -c "git -C '$ROOT' rev-parse --verify --quiet 'task/E-942-1_3/main'" 3>&-
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "init never created the task branch, so this run does not exercise the restore at all" -- [ -n "$output" ]
  run bash -c "git -C '$ROOT' symbolic-ref HEAD" 3>&-
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "the primary checkout was LEFT on a task branch after a failing init (got: $output)" -- _eq "$output" "refs/heads/main"
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "HEAD is on main but not where the run started" -- _eq "$(_head)" "$head0"
  _ok B "aid-fsm.sh init (stage 2)" "dirty-tree" "the failure does not report that the checkout was restored first: $B_OUTPUT" -- _contains "$B_OUTPUT" "the checkout was restored to 'main' first"
}

@test "P075: with plan B worktree-backed, epic-start registers the task branch and stage 2 initialises the EPIC inside plan B's own worktree" {
  _mk_primary
  _plan_branch_default
  _a_start
  _a_epic_midexecution
  _a_dirty_pm_edit
  local dirty_before; dirty_before="$(cat "$ROOT/pm-notes.txt")"
  local head0; head0="$(_head)"
  _b_allocate
  _b_write_plan
  _b_generate "plan-branch-B"

  # THE PATH UNDER TEST, read from the same source the pipeline's resolver uses.
  # Without the gate_profiles table in _plan_branch_default this reads `legacy`
  # and the whole test would silently exercise the wrong path.
  _ok B fixture "plan-branch-B" "plan B is not plan_branch (recorded mode: $(_b_recorded_mode)) — the gate_profiles table is what makes the mode reachable" -- _eq "$(_b_recorded_mode)" "plan_branch"
  _ok B plan-start "plan-branch-B" "plan B got no execution worktree" -- [ -d "$ROOT/.aid-worktrees/plan-${PLAN_B}" ]
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "stage 2 did not redirect into plan B's worktree: $B_OUTPUT" -- _contains "$B_OUTPUT" "executes in its own worktree"
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "the dirty-tree guard fired despite the redirect: $B_OUTPUT" -- _absent "$B_OUTPUT" "Uncommitted changes present"

  # epic-start ACTUALLY RAN. Two independent witnesses, because the absence of
  # the old lineage refusal would prove nothing on its own: the production log
  # line, and the durable operation ledger.
  _ok B epic-start "plan-branch-B" "the generation chain never reported registering the task branch: $B_OUTPUT" -- _contains "$B_OUTPUT" "P075: epic-start registered task/E-942-1_3/main for ${PLAN_B} before FSM init"
  _ok B epic-start "plan-branch-B" "plan B's operation ledger records no epic-start (found $(_b_epic_start_ops))" -- [ "$(_b_epic_start_ops)" -ge 1 ]
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "the plan-branch lineage check still refuses — epic-start did not satisfy it: $B_OUTPUT" -- _absent "$B_OUTPUT" "plan-branch lineage check failed"

  # AND THE EPIC IS INITIALISED. The run's state file exists and is READY.
  run bash -c "find '$ROOT/.aid-o/work/evidence/E-942-1_3' -name fsm-state.yaml | head -1" 3>&-
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "no fsm-state.yaml was written for E-942-1_3" -- [ -n "$output" ]
  run bash -c "yq -r '.state' \"\$(find '$ROOT/.aid-o/work/evidence/E-942-1_3' -name fsm-state.yaml | head -1)\"" 3>&-
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "E-942-1_3's run is not READY (got: $output)" -- _eq "$output" "READY"

  # The task branch is checked out in the PLAN's worktree — never in the PM's.
  run bash -c "git -C '$ROOT' rev-parse --verify --quiet 'task/E-942-1_3/main'" 3>&-
  _ok B epic-start "plan-branch-B" "task/E-942-1_3/main does not exist as a ref" -- [ -n "$output" ]
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "the task branch was checked out in the PM's own tree" -- _eq "$(_head)" "$head0"
  _ok "A+B" fixture "plan-branch-B" "the PM's uncommitted edit was altered" -- _eq "$(cat "$ROOT/pm-notes.txt")" "$dirty_before"

  # EVERY phase, not just the first. init leaves the plan worktree on that
  # phase's task branch; without a worktree-side restore the next phase
  # redirected into a tree still on the previous phase's branch and died on the
  # cross-EPIC mismatch. This asserts the whole multi-phase generation, which is
  # what a real plan looks like — a single-phase run cannot detect the gap.
  _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "a MULTI-phase plan_branch generation did not complete: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]
  local _ph
  for _ph in 1 2 3; do
    run bash -c "find '$ROOT/.aid-o/work/evidence/E-942-${_ph}_3' -name fsm-state.yaml 2>/dev/null | head -1" 3>&-
    _ok B "aid-fsm.sh init (stage 2)" "plan-branch-B" "phase ${_ph}/3 has no fsm-state.yaml — the multi-phase chain stopped early" -- [ -n "$output" ]
    run bash -c "git -C '$ROOT' rev-parse --verify --quiet 'task/E-942-${_ph}_3/main'" 3>&-
    _ok B epic-start "plan-branch-B" "task/E-942-${_ph}_3/main was never registered" -- [ -n "$output" ]
  done

  # Between phases the plan worktree rests on the plan branch — that IS the
  # restore, and it is why phase 2 finds a usable tree.
  run bash -c "git -C '$ROOT/.aid-worktrees/plan-${PLAN_B}' symbolic-ref --short HEAD" 3>&-
  _ok B "aid-json-to-run.sh" "plan-branch-B" "plan B's worktree did not come to rest on its plan branch (got: $output)" -- _eq "$output" "plan/${PLAN_B}"
  _ok B "aid-json-to-run.sh" "plan-branch-B" "the worktree restore was never reported: $B_OUTPUT" -- _contains "$B_OUTPUT" "restored plan worktree to 'plan/${PLAN_B}'"
}

@test "P075: a SINGLE-phase plan_branch plan B generates AND initialises green while plan A implements, with the PM's tree dirty and untouched" {
  _mk_primary
  _plan_branch_default
  _a_start
  _a_epic_midexecution
  _a_dirty_pm_edit
  local dirty_before; dirty_before="$(cat "$ROOT/pm-notes.txt")"
  local head0; head0="$(_head)"
  _b_allocate

  # One phase, so the multi-phase worktree-restore gap is out of the way and
  # what is left is the wiring itself: register, init, queue — all green.
  PLAN_B_FILE="$ROOT/.aid-o/plans/${PLAN_B}-single-phase.md"
  sed "s/P-TEST-001/${PLAN_B}/g" "$FIXTURES/minimal-plan.md" > "$PLAN_B_FILE"
  export PLAN_B_FILE
  GEN_B="$ROOT/.aid-o/work/evidence/${PLAN_B}/generation"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  export GEN_B QUEUE

  _b_generate "single-phase-B"
  _ok B fixture "single-phase-B" "plan B is not plan_branch (recorded mode: $(_b_recorded_mode))" -- _eq "$(_b_recorded_mode)" "plan_branch"
  _ok B generation "single-phase-B" "the pipeline failed: $B_OUTPUT" -- [ "$B_STATUS" -eq 0 ]

  # epic-start ran, and the EPIC is initialised and queued.
  _ok B epic-start "single-phase-B" "the generation chain never reported registering the task branch: $B_OUTPUT" -- _contains "$B_OUTPUT" "P075: epic-start registered task/E-942-1_1/main for ${PLAN_B} before FSM init"
  _ok B epic-start "single-phase-B" "plan B's operation ledger records no epic-start (found $(_b_epic_start_ops))" -- [ "$(_b_epic_start_ops)" -ge 1 ]
  run bash -c "yq -r '.state' \"\$(find '$ROOT/.aid-o/work/evidence/E-942-1_1' -name fsm-state.yaml | head -1)\"" 3>&-
  _ok B "aid-fsm.sh init (stage 2)" "single-phase-B" "E-942-1_1's run is not READY (got: $output)" -- _eq "$output" "READY"
  run bash -c "grep -c 'epic_id: \"E-942-1_1\"' '$QUEUE'" 3>&-
  _ok B queue "single-phase-B" "E-942-1_1 was not queued (got: $output)" -- _eq "$output" "1"

  # The branch work happened in plan B's worktree; the PM's tree is untouched.
  run bash -c "git -C '$ROOT' rev-parse --verify --quiet 'task/E-942-1_1/main'" 3>&-
  _ok B epic-start "single-phase-B" "task/E-942-1_1/main was never registered" -- [ -n "$output" ]
  # The worktree comes to rest on the plan branch after init, the same restore
  # a multi-phase run depends on between phases.
  run bash -c "git -C '$ROOT/.aid-worktrees/plan-${PLAN_B}' symbolic-ref --short HEAD" 3>&-
  _ok B "aid-json-to-run.sh" "single-phase-B" "plan B's worktree did not come to rest on its plan branch (got: $output)" -- _eq "$output" "plan/${PLAN_B}"
  _ok B "aid-fsm.sh init (stage 2)" "single-phase-B" "the primary checkout moved" -- _eq "$(_head)" "$head0"
  _ok "A+B" fixture "single-phase-B" "the PM's uncommitted edit was altered" -- _eq "$(cat "$ROOT/pm-notes.txt")" "$dirty_before"
  _ok A fixture "single-phase-B" "stream A left its own task branch" -- [ -d "$(_wt_a)" ]
}
