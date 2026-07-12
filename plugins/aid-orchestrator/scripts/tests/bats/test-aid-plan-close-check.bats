#!/usr/bin/env bats
# test-aid-plan-close-check.bats — aid-plan-close-check.sh (PM plugin-infra fix,
# branch fix/plan-close-consistency).
#
# Covers the 4 mechanical checks + aggregate self-check the script implements:
#   1. official report tracking (private/gitignored vs committed storage mode)
#   2. Head freshness (docs-only vs code delta since the report's recorded Head)
#   3. fsm-state.yaml DONE-but-pending guard
#   4. queue.yaml / active.md revalidation (reuses aid-fsm.sh's queue_revalidate)
#
# All fixtures build a real git repo under a bats mktemp -d (test-release-
# policy.bats-style fixture helpers), since Check 1/2 depend on real git
# tracking + git log/diff, and Check 4 depends on real branch/merge state
# (same pattern test-queue-revalidation.bats uses for make_merged_dep).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh"
  export SCRIPT
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/reports"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture helpers ─────────────────────────────────────────────────────

# write_passing_delivery_report <plan_id>
#   Commits a delivery report whose Head field equals the exact commit that
#   last touched it (the standard "generation, then fix-head" 2-commit
#   pattern) so Check 1 (committed) + Check 2 (fresh) both pass by default.
#   Callers add further commits afterward to exercise staleness.
write_passing_delivery_report() {
  local plan_id="$1"
  local file="$TEST_PROJECT_ROOT/.aid-o/reports/${plan_id}-delivery.md"
  cat > "$file" <<EOF
---
Head: PLACEHOLDER
plan_id: "${plan_id}"
---

# Delivery Report
EOF
  git add "$file"
  git commit -q -m "docs: add ${plan_id} delivery report"
  local sha; sha=$(git rev-parse HEAD)
  sed -i "s/PLACEHOLDER/${sha}/" "$file"
  git add "$file"
  git commit -q -m "docs: finalize ${plan_id} delivery report head"
}

# write_annotated_delivery_report <plan_id> <head_at_generation> <head>
#   Writes (and commits) a report with all 3 Head fields already present,
#   matching the WAN P062-delivery.md convention exactly.
write_annotated_delivery_report() {
  local plan_id="$1" head_at_gen="$2" head="$3"
  local file="$TEST_PROJECT_ROOT/.aid-o/reports/${plan_id}-delivery.md"
  cat > "$file" <<EOF
---
Head: ${head}
Head_at_generation: ${head_at_gen}
Head_note: >-
  Reporter ran against ${head_at_gen:0:7}; docs-only commit(s) landed after —
  zero code/test delta, live-tested evidence above still applies unchanged.
plan_id: "${plan_id}"
---

# Delivery Report
EOF
  git add "$file"
  git commit -q -m "docs: add pre-annotated ${plan_id} delivery report"
}

# write_fsm_state <epic_id> <run_id> <state> <pending_count>
#   Writes a minimal fsm-state.yaml with a steps[] array of 2 entries, the
#   first N of which are "pending" (pending_count) and the rest "completed".
write_fsm_state() {
  local epic_id="$1" run_id="$2" state="$3" pending_count="$4"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}"
  mkdir -p "$dir"
  local s1="completed" s2="completed"
  [[ "$pending_count" -ge 1 ]] && s1="pending"
  [[ "$pending_count" -ge 2 ]] && s2="pending"
  cat > "$dir/fsm-state.yaml" <<EOF
epic_id: $epic_id
run_id: $run_id
state: $state
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: $s1
  - id: 2
    status: $s2
EOF
}

# make_merged_epic_branch <epic_id>
#   Real merged branch (task/<epic_id>/main, --no-ff into main, branch kept)
#   — same construction test-queue-revalidation.bats's make_merged_dep uses.
make_merged_epic_branch() {
  local epic="$1"
  local br="task/${epic}/main"
  git checkout -q -b "$br"
  echo "$epic work" > "${epic//\//_}.txt"
  git add "${epic//\//_}.txt"
  git commit -q -m "feat: ${epic} work"
  git checkout -q main
  git merge -q --no-ff "$br" -m "merge: ${epic} into main"
}

write_queue_yaml() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 1 — DONE fsm-state with all steps pending → FAILS (Check 3)
# ═══════════════════════════════════════════════════════════════════════

@test "(1) DONE fsm-state with all steps pending -> self-check FAILS" {
  write_passing_delivery_report "P601"
  write_fsm_state "E-601-1_1" "R-1" "DONE" 2

  run "$SCRIPT" P601 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"state=DONE but 2 step(s) still status:pending"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 2 — report at old HEAD, CODE commit lands after → FAILS
# ═══════════════════════════════════════════════════════════════════════

@test "(2) code commit lands after report generation -> FAILS with regeneration required" {
  write_passing_delivery_report "P602"

  mkdir -p "$TEST_PROJECT_ROOT/src"
  echo "def handler(): pass" > "$TEST_PROJECT_ROOT/src/app.py"
  git add "$TEST_PROJECT_ROOT/src/app.py"
  git commit -q -m "feat: add handler"

  run "$SCRIPT" P602 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"regeneration required"* ]]
  [[ "$output" == *"src/app.py"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 3 — docs-only commit lands after: annotated=PASS, bare=FAILS
# ═══════════════════════════════════════════════════════════════════════

@test "(3a) docs-only commit lands after report, NO annotation fields -> FAILS needs-annotation" {
  write_passing_delivery_report "P603"

  echo "trailing docs note" >> "$TEST_PROJECT_ROOT/README.md"
  git add "$TEST_PROJECT_ROOT/README.md"
  git commit -q -m "docs: trailing readme update"

  run "$SCRIPT" P603 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"needs Head_at_generation + Head + Head_note annotation"* ]]
}

@test "(3b) docs-only delta WITH Head_at_generation+Head+Head_note already present -> PASSES" {
  # Generation commit establishes head_at_gen.
  echo x > "$TEST_PROJECT_ROOT/gen-marker.txt"
  git -C "$TEST_PROJECT_ROOT" add gen-marker.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "chore: generation marker"
  local head_at_gen; head_at_gen=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)

  # Docs-only trailing commit (simulates active.md/queue.yaml sync landing
  # after the report was generated).
  echo "sync" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: active.md/queue.yaml sync"
  local trailing_head; trailing_head=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)

  write_annotated_delivery_report "P603b" "$head_at_gen" "$trailing_head"

  run "$SCRIPT" P603b --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"check2"*"fresh"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 4 — report exists on disk but untracked in COMMITTED-mode -> FAILS
# ═══════════════════════════════════════════════════════════════════════

@test "(4) report exists on disk but is untracked in committed-mode project -> FAILS" {
  # setup_test_evidence_dir's fixture repo has NO .gitignore at all, so
  # .aid-o/reports/ is NOT ignored -> committed mode by construction (WAN's
  # mode), unlike this actual aid-orchestrator repo (where .aid-o/ IS
  # entirely gitignored, private mode).
  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P604-delivery.md"
  cat > "$file" <<'EOF'
---
Head: deadbeef
plan_id: "P604"
---

# Delivery Report
EOF
  # Deliberately NOT git-added — untracked on disk.

  run "$SCRIPT" P604 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"UNTRACKED"* ]]
  [[ "$output" == *"report_storage: committed"* ]]
}

@test "(4b) report present + gitignored project -> private/gitignored, never a blocker" {
  echo ".aid-o/" > "$TEST_PROJECT_ROOT/.gitignore"
  git -C "$TEST_PROJECT_ROOT" add .gitignore
  git -C "$TEST_PROJECT_ROOT" commit -q -m "chore: gitignore .aid-o"

  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P604b-delivery.md"
  local head; head=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  cat > "$file" <<EOF
---
Head: ${head}
plan_id: "P604b"
---

# Delivery Report
EOF
  # Never added to git at all (this project ignores .aid-o/ entirely) —
  # must still PASS Check 1.

  run "$SCRIPT" P604b --project-root "$TEST_PROJECT_ROOT"
  [[ "$output" == *"PASS"*"private/gitignored"*"never a blocker"* ]]
  ! [[ "$output" == *"FAIL"*"check1"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 5 — queue/active claims blocked but branch is merged -> FAILS
# ═══════════════════════════════════════════════════════════════════════

@test "(5) queue.yaml claims blocked/waiting-for-merge but branch IS merged -> FAILS" {
  write_passing_delivery_report "P605"
  make_merged_epic_branch "E-605-1_2"

  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-605-1_2
  path: p
  status: blocked
  depends_on: []
YAML

  run "$SCRIPT" P605 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"E-605-1_2"*"queue_revalidate confirms the branch IS merged"* ]]
}

@test "(5b) queue.yaml status genuinely unmerged -> PASSES (consistent)" {
  write_passing_delivery_report "P606"

  # E-606-1_2 branch exists but is NOT merged into main.
  git -C "$TEST_PROJECT_ROOT" checkout -q -b task/E-606-1_2/main
  echo wip > "$TEST_PROJECT_ROOT/wip.txt"
  git -C "$TEST_PROJECT_ROOT" add wip.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "wip: E-606-1_2"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-606-1_2
  path: p
  status: blocked
  depends_on: []
YAML

  run "$SCRIPT" P606 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"check4"*"genuinely unmerged, consistent"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 6 — WAN-P062-like fixture (positive regression snapshot) -> PASS
# ═══════════════════════════════════════════════════════════════════════

@test "(6) WAN-P062-like fixture (committed reports, annotated Head, DONE fsm, clean queue) -> overall PASS" {
  # Generation-time commit.
  echo x > "$TEST_PROJECT_ROOT/gen-marker.txt"
  git -C "$TEST_PROJECT_ROOT" add gen-marker.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "chore: E-062-3_3 evidence committed"
  local head_at_gen; head_at_gen=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)

  # 2 docs-only commits land after, mirroring the real P062-delivery.md note
  # ("919aba9 active.md/queue.yaml sync, ede7238 IMP-200/201 backlog notes").
  echo "sync" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: active.md/queue.yaml sync"

  mkdir -p "$TEST_PROJECT_ROOT/docs"
  echo "IMP-200/201 backlog notes" >> "$TEST_PROJECT_ROOT/docs/BACKLOG.md"
  git -C "$TEST_PROJECT_ROOT" add docs/BACKLOG.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: IMP-200/201 backlog notes"
  local trailing_head; trailing_head=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)

  write_annotated_delivery_report "P062" "$head_at_gen" "$trailing_head"

  # 3 EPICs, all DONE, all steps completed.
  write_fsm_state "E-062-1_3" "R-E062-1" "DONE" 0
  write_fsm_state "E-062-2_3" "R-E062-2" "DONE" 0
  write_fsm_state "E-062-3_3" "R-E062-3" "DONE" 0

  # queue.yaml: all 3 completed, no blocked/waiting claims.
  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-062-1_3
  path: p
  status: completed
  depends_on: []
- epic_id: E-062-2_3
  path: p
  status: completed
  depends_on: ["E-062-1_3"]
- epic_id: E-062-3_3
  path: p
  status: completed
  depends_on: ["E-062-2_3"]
YAML

  run "$SCRIPT" P062 --project-root "$TEST_PROJECT_ROOT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVERALL: PASS"* ]]
  ! [[ "$output" == *"FAIL"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 7 — path-classification edge cases (regression: docs/-substring match)
# ═══════════════════════════════════════════════════════════════════════

@test "(7a) code file under docs/ directory (src/docs/generator.py) -> CODE, regeneration required" {
  write_passing_delivery_report "P608"

  # Real code file under a docs/ directory — must NOT be misclassified as
  # docs-only just because "docs/" appears in the path. This is the exact
  # regression case from the verifier's FINDING 1.
  mkdir -p "$TEST_PROJECT_ROOT/src/docs"
  cat > "$TEST_PROJECT_ROOT/src/docs/generator.py" <<'PYTHON'
def render():
    return "<html>real business logic here</html>"

if __name__ == "__main__":
    print(render())
PYTHON
  git add "$TEST_PROJECT_ROOT/src/docs/generator.py"
  git commit -q -m "feat: add docs-generator module (real code, not documentation)"

  run "$SCRIPT" P608 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"regeneration required"* ]]
  [[ "$output" == *"src/docs/generator.py"* ]]
  # Crucially: NOT "docs-only" classification
  ! [[ "$output" == *"docs-only"* ]]
}

@test "(7b) code file with docs in package name (packages/sdk-docs/index.ts) -> CODE, regeneration required" {
  write_passing_delivery_report "P609"

  # Another realistic monorepo pattern: package-with-docs-in-the-name.
  mkdir -p "$TEST_PROJECT_ROOT/packages/sdk-docs"
  cat > "$TEST_PROJECT_ROOT/packages/sdk-docs/index.ts" <<'TYPESCRIPT'
export interface APIClient {
  request(path: string): Promise<Response>;
}
TYPESCRIPT
  git add "$TEST_PROJECT_ROOT/packages/sdk-docs/index.ts"
  git commit -q -m "feat: add SDK docs package (real code, not documentation)"

  run "$SCRIPT" P609 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"regeneration required"* ]]
  [[ "$output" == *"packages/sdk-docs/index.ts"* ]]
  # Crucially: NOT "docs-only" classification
  ! [[ "$output" == *"docs-only"* ]]
}

@test "(7c) actual docs directory change (docs/architecture.md) still classifies as docs-only" {
  write_passing_delivery_report "P610"

  mkdir -p "$TEST_PROJECT_ROOT/docs"
  echo "# Architecture" > "$TEST_PROJECT_ROOT/docs/architecture.md"
  git add "$TEST_PROJECT_ROOT/docs/architecture.md"
  git commit -q -m "docs: add architecture guide"

  run "$SCRIPT" P610 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  # Since there's no annotation, this should fail asking for annotation.
  [[ "$output" == *"FAIL"*"needs Head_at_generation + Head + Head_note annotation"* ]]
  # Confirm it's recognized as docs-only (that's the whole point —
  # it should be docs-only, but need annotation since it's stale).
  [[ "$output" == *"docs-only"* ]]
}

@test "(7d) script in scripts/ dir with docs in filename (scripts/generate-docs-index.sh) -> CODE" {
  write_passing_delivery_report "P611"

  mkdir -p "$TEST_PROJECT_ROOT/scripts"
  cat > "$TEST_PROJECT_ROOT/scripts/generate-docs-index.sh" <<'BASH'
#!/bin/bash
# Real shell script, happens to have "docs" in its name.
for doc in docs/*.md; do
  echo "$doc"
done
BASH
  chmod +x "$TEST_PROJECT_ROOT/scripts/generate-docs-index.sh"
  git add "$TEST_PROJECT_ROOT/scripts/generate-docs-index.sh"
  git commit -q -m "feat: add docs index generator script"

  run "$SCRIPT" P611 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  # Extension-based classification (.sh) wins over directory-name patterns.
  [[ "$output" == *"FAIL"*"regeneration required"* ]]
  [[ "$output" == *"scripts/generate-docs-index.sh"* ]]
  ! [[ "$output" == *"docs-only"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# --auto-annotate — idempotency + no double-nesting
# ═══════════════════════════════════════════════════════════════════════

@test "(8) --auto-annotate fixes a docs-only-stale report and is idempotent" {
  write_passing_delivery_report "P607"

  echo "trailing docs note" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: trailing readme update"

  run "$SCRIPT" P607 --project-root "$TEST_PROJECT_ROOT" --auto-annotate
  [ "$status" -eq 0 ]

  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P607-delivery.md"
  [ -f "$file" ]
  run grep -c "^Head_at_generation:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^Head_note:" "$file"
  [ "$output" -eq 1 ]

  # The annotation itself is an uncommitted change at this point (Check 1
  # correctly requires it to be committed in committed-mode projects — that
  # is a SEPARATE, deliberate check, not a hole in idempotency). Commit it,
  # as a real orchestrator/PM would, then run --auto-annotate again with NO
  # further commits: it must be a pure no-op (Head already == current HEAD,
  # so Check 2's match-branch short-circuits before ever re-invoking
  # _auto_annotate_report) — not a double-nested Head_note/Head_at_generation.
  git -C "$TEST_PROJECT_ROOT" add "$file"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: annotate P607 report"

  local before; before=$(md5sum "$file")
  run "$SCRIPT" P607 --project-root "$TEST_PROJECT_ROOT" --auto-annotate
  [ "$status" -eq 0 ]
  local after; after=$(md5sum "$file")
  [ "$before" == "$after" ]

  # No double-nested Head_note / Head_at_generation lines either way.
  run grep -c "^Head_at_generation:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^Head_note:" "$file"
  [ "$output" -eq 1 ]
}
