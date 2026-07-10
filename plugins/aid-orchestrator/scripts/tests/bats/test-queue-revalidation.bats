#!/usr/bin/env bats
# P060 Step 7 — aid-fsm.sh queue dependency revalidation (OBS-20260709-06).
#
# Revalidates a queue entry's `depends_on` (the REAL schema field — epic IDs,
# NOT a non-existent `blocked_on`) against LIVE git at start, with the D8
# 4-output contract per dep:
#   1. dep branch exists + is-ancestor of main/HEAD → unblock (queue_dep_revalidated)
#   2. dep branch exists + NOT ancestor            → blocked (queue_dep_blocked)
#   3. dep branch DELETED after merge (the norm)   → merged-detection → unblock
#   4. no signal at all                            → fail-loud (queue_dep_unresolved)
# Plus: unparseable queue → queue_parse_failed; missing queue / no entry → no-op.
#
# 8 scenarios (F4 a-g; c is split into blocked-status + cmd_init-no-crash).
# One scenario (live-format) runs against a COPY of the live dogfood queue.yaml
# format (mixed indentation: top-level `- epic_id:` 2-space list with multi-line
# depends_on, interleaved with a 4-space quoted block) — the parser must handle it.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  QUEUE="$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"
  export QUEUE
  TL="$TEST_PROJECT_ROOT/.aid-o/work/evidence/qrev-timeline.jsonl"
  export TL
  mkdir -p "$(dirname "$QUEUE")"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture helpers ─────────────────────────────────────────────────────

# make_merged_dep <dep> [keep_branch]
#   Create task/<dep>/main with a commit, merge it into main (--no-ff).
#   Deletes the branch afterward unless keep_branch=keep.
make_merged_dep() {
  local dep="$1" keep="${2:-delete}"
  local br="task/${dep}/main"
  git checkout -q -b "$br"
  echo "$dep work" > "${dep}.txt"
  git add "${dep}.txt"
  git commit -q -m "feat: ${dep} work"
  git checkout -q main
  git merge -q --no-ff "$br" -m "merge: ${dep} into main"
  [[ "$keep" == "delete" ]] && git branch -q -D "$br"
  return 0
}

# make_unmerged_dep <dep>
#   Create task/<dep>/main with a commit NOT merged into main; leave HEAD on main.
make_unmerged_dep() {
  local dep="$1"
  local br="task/${dep}/main"
  git checkout -q -b "$br"
  echo "$dep wip" > "${dep}.txt"
  git add "${dep}.txt"
  git commit -q -m "wip: ${dep}"
  git checkout -q main
  return 0
}

# write_queue <<'YAML' ... — write $QUEUE from stdin.
write_queue() { cat > "$QUEUE"; }

# ─── (a) dep merged, branch EXISTS → unblock + queue_dep_revalidated ─────
@test "(a) dep merged + branch exists → unblocked (ancestor)" {
  make_merged_dep E-DEP keep
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-DEP
  path: p
  status: completed
  depends_on: []
- epic_id: E-MAIN
  path: p
  status: queued
  depends_on: ["E-DEP"]
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "unblocked" ]
  assert_timeline_event "$TL" "queue_dep_revalidated"
  grep -q '"resolution":"ancestor"' "$TL"
}

# ─── (b) dep merged, branch DELETED (norm) → merged-detection → unblock ──
@test "(b) dep merged + branch deleted (norm) → unblocked (merged-detection)" {
  make_merged_dep E-DEP delete
  # queue status queued (NOT completed) so the unblock comes from git merge log,
  # proving branch-deleted merged-detection works without the bookkeeping flag.
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-DEP
  path: p
  status: queued
  depends_on: []
- epic_id: E-MAIN
  path: p
  status: queued
  depends_on: ["E-DEP"]
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "unblocked" ]
  grep -q '"resolution":"merged_log"' "$TL"
}

# ─── (c1) dep genuinely unmerged → blocked ──────────────────────────────
@test "(c1) dep genuinely unmerged (branch exists, not ancestor) → blocked" {
  make_unmerged_dep E-DEP
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-DEP
  path: p
  status: queued
  depends_on: []
- epic_id: E-MAIN
  path: p
  status: queued
  depends_on: ["E-DEP"]
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "blocked" ]
  assert_timeline_event "$TL" "queue_dep_blocked"
}

# ─── (c2) cmd_init does NOT crash on the rc=1 (not-ancestor) branch ──────
@test "(c2) cmd_init reads queue with unmerged dep → does not crash (rc=1 handled)" {
  make_unmerged_dep E-DEP
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-DEP
  path: p
  status: queued
  depends_on: []
- epic_id: E-MAIN
  path: p
  status: queued
  depends_on: ["E-DEP"]
YAML
  local sf="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-MAIN/R-M/fsm-state.yaml"
  mkdir -p "$(dirname "$sf")"
  # HEAD=main → cmd_init auto-creates task/E-MAIN/main, then revalidates E-MAIN's
  # dep E-DEP (branch exists, not ancestor → rc=1). Must NOT abort init.
  run "$FSM" init E-MAIN R-M 3 manual main HEAD "$sf"
  [ "$status" -eq 0 ]
  [ -f "$sf" ]
}

# ─── (d) dep with NO signal at all → fail-loud ──────────────────────────
@test "(d) dep with no signal at all → fail-loud (queue_dep_unresolved)" {
  # No branch, no evidence, no merge log, queue status not completed.
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-DEP
  path: p
  status: queued
  depends_on: []
- epic_id: E-MAIN
  path: p
  status: queued
  depends_on: ["E-DEP"]
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 1 ]
  [ "$output" == "failed" ]
  assert_timeline_event "$TL" "queue_dep_unresolved"
}

# ─── (e) unparseable queue → queue_parse_failed fail-loud ────────────────
@test "(e) unparseable queue → queue_parse_failed fail-loud" {
  # A stray invalid JSON escape (\q) in a status value makes the awk-emitted
  # JSON invalid → jq -e fails → fail-loud.
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-MAIN
  path: p
  status: don\qe
  depends_on: ["E-DEP"]
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 1 ]
  [ "$output" == "failed" ]
  assert_timeline_event "$TL" "queue_parse_failed"
}

# ─── (f) missing queue / no entry for this epic → no-op (no event) ───────
@test "(f) missing queue file AND no-entry → no-op, no event" {
  # (i) missing queue file
  run "$FSM" queue-revalidate E-MAIN "$TEST_PROJECT_ROOT/.aid-o/config/nope.yaml" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "noop" ]
  [ ! -f "$TL" ]

  # (ii) queue exists but has no entry for this epic
  write_queue <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-OTHER
  path: p
  status: queued
  depends_on: []
YAML
  run "$FSM" queue-revalidate E-MAIN "$QUEUE" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "noop" ]
  [ ! -f "$TL" ]
}

# ─── (g) standalone callable AND live dogfood queue.yaml format ─────────
@test "(g) standalone queue-revalidate against LIVE dogfood queue.yaml format → returns state" {
  # A copy of the LIVE .aid-o/config/queue.yaml FORMAT: mixed indentation — a
  # top-level `- epic_id:` list with 2-space keys and a multi-line depends_on,
  # interleaved with a 4-space quoted block. The parser must handle both in one
  # file (yq cannot). E-016-1_3 is completed → E-016-2_3 unblocks via
  # merged_completed, proving the 2-space top-level list + multi-line depends_on
  # parse correctly.
  write_queue <<'YAML'
# Epic Queue — managed by Orchestrator + /epic-queue command
paused: false
last_modified: "2026-07-10T06:18:51Z"
queue:
- epic_id: E-016-1_3
  path: .aid-o/02-epics/E-016-1_3-gui-data-layer-kanban.md
  priority: medium
  status: completed
  depends_on: []
  added_at: '2026-02-27T16:00:00Z'
- epic_id: E-016-2_3
  path: .aid-o/02-epics/E-016-2_3-gui-ai-companion.md
  priority: medium
  status: queued
  depends_on:
  - E-016-1_3
  added_at: '2026-02-27T16:00:01Z'

  - epic_id: "E-057-1_2"
    path: "/opt/x/E-057-1_2.md"
    priority: medium
    status: completed
    depends_on: []
    added_at: "2026-07-02T05:59:08Z"

  - epic_id: "E-057-2_2"
    path: "/opt/x/E-057-2_2.md"
    priority: medium
    status: queued
    depends_on: ["E-057-1_2"]
    added_at: "2026-07-02T05:59:20Z"
YAML
  run "$FSM" queue-revalidate E-016-2_3 "$QUEUE" "$TL"
  [ "$status" -eq 0 ]
  [ "$output" == "unblocked" ]
  # parser succeeded (NOT a parse failure)
  ! grep -q 'queue_parse_failed' "$TL"
  grep -q '"resolution":"merged_completed"' "$TL"
}
