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
  echo "IMP-200/201 backlog notes" >> "$TEST_PROJECT_ROOT/docs/2026-06-29-BACKLOG.md"
  git -C "$TEST_PROJECT_ROOT" add docs/2026-06-29-BACKLOG.md
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

# ═══════════════════════════════════════════════════════════════════════
# Regression tests for yq injection fix (strenv + environment variables)
# ═══════════════════════════════════════════════════════════════════════

@test "(9a) --auto-annotate with commit subject containing double quote -> exits 0, valid frontmatter" {
  write_passing_delivery_report "P612"

  echo "update" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  # Commit subject with a double quote - this would cause yq lexer error
  # if the subject text were interpolated directly into the yq expression
  git -C "$TEST_PROJECT_ROOT" commit -q -m 'docs: subject with " quote'

  run "$SCRIPT" P612 --project-root "$TEST_PROJECT_ROOT" --auto-annotate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"auto-annotated"* ]]

  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P612-delivery.md"
  [ -f "$file" ]

  # Verify the frontmatter is valid YAML by checking it parses
  run yq -r '.Head' "$file"
  [ "$status" -eq 0 ]
  [[ "$output" != "" ]]

  # Verify all expected fields are present
  run grep -c "^Head_at_generation:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^Head_note:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^_header_corrected_at:" "$file"
  [ "$output" -eq 1 ]
}

@test "(9b) --auto-annotate with commit subject containing backslash -> exits 0, valid frontmatter" {
  write_passing_delivery_report "P613"

  echo "update" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  # Commit subject with a backslash - another metacharacter that would
  # break yq if interpolated directly into the expression string
  git -C "$TEST_PROJECT_ROOT" commit -q -m 'docs: fix path C:\Users\test'

  run "$SCRIPT" P613 --project-root "$TEST_PROJECT_ROOT" --auto-annotate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"auto-annotated"* ]]

  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P613-delivery.md"
  [ -f "$file" ]

  # Verify the frontmatter is valid YAML
  run yq -r '.Head' "$file"
  [ "$status" -eq 0 ]
  [[ "$output" != "" ]]

  # Verify all expected fields are present
  run grep -c "^Head_at_generation:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^Head_note:" "$file"
  [ "$output" -eq 1 ]
}

@test "(9c) --auto-annotate with normal commit subject (no special chars) still works" {
  write_passing_delivery_report "P614"

  echo "update" >> "$TEST_PROJECT_ROOT/README.md"
  git -C "$TEST_PROJECT_ROOT" add README.md
  # Normal commit subject without any special characters
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: update readme"

  run "$SCRIPT" P614 --project-root "$TEST_PROJECT_ROOT" --auto-annotate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"auto-annotated"* ]]

  local file="$TEST_PROJECT_ROOT/.aid-o/reports/P614-delivery.md"
  [ -f "$file" ]

  # Verify the frontmatter is valid YAML
  run yq -r '.Head' "$file"
  [ "$status" -eq 0 ]
  [[ "$output" != "" ]]

  # Verify all expected fields are present
  run grep -c "^Head_at_generation:" "$file"
  [ "$output" -eq 1 ]
  run grep -c "^Head_note:" "$file"
  [ "$output" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════
# D4 / IMP-467 — grouped plan-final freshness (receipt-bound group)
# ═══════════════════════════════════════════════════════════════════════

# _seal_minimal_receipt <plan_id> <candidate_sha>
#   A real, immutable sidecar ref at the exact derived path
#   (refs/heads/aid-evidence/<plan>/<candidate>/R-test-1) containing ONLY
#   receipt.json, plus the runtime manifest fields _pbm/_check2_receipt_
#   covers_candidate read to recognise it. Minimal but REAL: same tree
#   shape and hash-binding _pfsm_verify_plan_final_receipt enforces, not a
#   loosened test-only shortcut.
# _seal_minimal_receipt <plan_id> <candidate_sha> [receipt_candidate_override]
#   A FULLY VALID receipt matching every field _check2_receipt_covers_candidate
#   (mirroring _pfsm_verify_plan_final_receipt, D1) requires: exact derived
#   ref path, exact schema keys, review_verdict:accepted, and plan_id/
#   candidate_sha/run_id/evidence_ref/plan_base_commit/target_branch/
#   target_head_at_freeze/candidate_frozen_at all bound to what the runtime
#   manifest itself records. The optional 3rd arg lets a test seal a receipt
#   whose OWN candidate_sha disagrees with the manifest's, to prove that is
#   refused (not just "any resolvable ref accepted").
_seal_minimal_receipt() {
  local plan_id="$1" candidate="$2" receipt_candidate="${3:-$2}" run_id="R-test-1"
  local base="0000000000000000000000000000000000000000000000000000000000000000"
  base="${base:0:40}"
  local target="main" target_head="1111111111111111111111111111111111111111" frozen_at="2026-01-01T00:00:00Z"
  local ref="refs/heads/aid-evidence/${plan_id}/${receipt_candidate}/${run_id}"
  local tmp; tmp=$(mktemp)
  # D4 round-2 Codex MEDIUM: the manifest-side check now reuses D1's own
  # exact-review-inventory check, which requires EVERY plan-final required
  # output name present (not just one) — a receipt with a partial outputs{}
  # is exactly what that check must reject.
  local h64="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  jq -nc --arg p "$plan_id" --arg c "$receipt_candidate" --arg r "$run_id" --arg ref "$ref" \
        --arg b "$base" --arg t "$target" --arg th "$target_head" --arg fa "$frozen_at" --arg h "$h64" \
    '{schema_version:"aid-plan-final-evidence-1", artifact_type:"plan_final_evidence_receipt",
      review_verdict:"accepted", plan_id:$p, plan_base_commit:$b, candidate_sha:$c,
      candidate_frozen_at:$fa, target_branch:$t, target_head_at_freeze:$th, run_id:$r,
      evidence_ref:$ref, outputs:{
        "semantic-review-final.json":$h, "audit-report.json":$h, "curator-report.json":$h,
        "simplifier-report.md":$h, "delivery-report.json":$h, "review-profile.json":$h,
        "plan-diff.json":$h, "audit-input-manifest.json":$h, "delivery-gate.json":$h,
        "acceptance-evidence.json":$h, "dispatch-record.json":$h}}' \
    > "$tmp"
  local hash; hash="sha256:$(sha256sum "$tmp" | awk '{print $1}')"
  local blob; blob=$(git -C "$TEST_PROJECT_ROOT" hash-object -w "$tmp")
  rm -f "$tmp"
  local tree; tree=$(printf '100644 blob %s\treceipt.json\n' "$blob" | git -C "$TEST_PROJECT_ROOT" mktree)
  local commit; commit=$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -m "aid: seal plan-final evidence ${plan_id} ${run_id}")
  git -C "$TEST_PROJECT_ROOT" update-ref "$ref" "$commit"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${plan_id}"
  # The MANIFEST's own binding is what _check2_receipt_covers_candidate reads
  # to derive the EXPECTED ref/hash — the receipt's ref points at
  # <receipt_candidate>, but the manifest always claims <candidate> (the
  # real one), so a mismatched receipt_candidate produces a ref the manifest
  # itself does NOT expect, exactly like a forged/unrelated receipt would.
  jq -n --arg ref "$ref" --arg h "$hash" --arg p "$plan_id" --arg c "$candidate" --arg r "$run_id" \
        --arg b "$base" --arg t "$target" --arg th "$target_head" --arg fa "$frozen_at" \
    '{plan_boundary_manifest: {plan_id:$p, candidate_sha:$c, plan_final_run_id:$r,
      plan_base_commit:$b, target_branch:$t, target_branch_head_at_candidate_freeze:$th,
      candidate_frozen_at:$fa, plan_final_evidence_ref:$ref, plan_final_evidence_receipt_sha256:$h}}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${plan_id}/plan-boundary-manifest.json"
}

# write_passing_boundary_report <plan_id> — same 2-commit pattern as
# write_passing_delivery_report, for the SIBLING report.
write_passing_boundary_report() {
  local plan_id="$1"
  local file="$TEST_PROJECT_ROOT/.aid-o/reports/${plan_id}-boundary.md"
  cat > "$file" <<EOF
---
Head: PLACEHOLDER
plan_id: "${plan_id}"
---

# Boundary Report
EOF
  git add "$file"
  git commit -q -m "docs: add ${plan_id} boundary report"
  local sha; sha=$(git rev-parse HEAD)
  sed -i "s/PLACEHOLDER/${sha}/" "$file"
  git add "$file"
  git commit -q -m "docs: finalize ${plan_id} boundary report head"
}

@test "D4: a sibling report's own annotation commit is NOT drift for the other report, when a receipt covers the candidate" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  local candidate; candidate=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  _seal_minimal_receipt "P467" "$candidate"

  # Simulate the delivery report having been auto-annotated on its own
  # (a real annotation commit, touching ONLY that file) — the exact scenario
  # that used to make the BOUNDARY report look stale too.
  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  yq -i '.Head_at_generation = "'"$candidate"'" | .Head_note = "re-annotated"' \
    "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: auto-annotate P467 delivery report"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"receipt-bound report group"*"fresh"* ]]
  ! [[ "$output" == *"P467-boundary.md: Head"*"needs"* ]]
  ! [[ "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}

@test "D4: WITHOUT a receipt, the legacy per-report-only exclusion still applies (a sibling's commit still needs annotation)" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  # No receipt sealed — legacy behavior.

  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  echo "more" >> "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: unrelated delivery report edit"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"needs"* || "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}

@test "D4: a FORGED receipt reference (ref does not resolve) does not grant grouped freshness" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  local candidate; candidate=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467"
  jq -n --arg ref "refs/heads/aid-evidence/P467/${candidate}/R-nope" --arg h "sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    '{plan_boundary_manifest: {plan_final_evidence_ref: $ref, plan_final_evidence_receipt_sha256: $h}}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467/plan-boundary-manifest.json"

  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  echo "more" >> "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: unrelated delivery report edit"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"needs"* || "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}

@test "D4: a VALID, well-formed receipt bound to a DIFFERENT candidate does not grant grouped freshness for THIS candidate" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  local candidate; candidate=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  # A real, fully schema-correct, hash-consistent receipt — but sealed for a
  # candidate OTHER than the one the manifest (and these reports) record.
  local other="2222222222222222222222222222222222222222"
  _seal_minimal_receipt "P467" "$candidate" "$other"

  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  echo "more" >> "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: unrelated delivery report edit"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"needs"* || "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}

@test "D4: a receipt at a resolvable ref but missing required D1 schema keys does not grant grouped freshness" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  local candidate; candidate=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  local run_id="R-test-1"
  local ref="refs/heads/aid-evidence/P467/${candidate}/${run_id}"
  local tmp; tmp=$(mktemp)
  # Missing review_verdict, plan_base_commit, target_branch, etc. — a
  # single-file ref with a matching hash, but NOT the D1 receipt schema.
  printf '{"schema_version":"aid-plan-final-evidence-1","artifact_type":"plan_final_evidence_receipt","plan_id":"P467","candidate_sha":"%s"}\n' \
    "$candidate" > "$tmp"
  local hash; hash="sha256:$(sha256sum "$tmp" | awk '{print $1}')"
  local blob; blob=$(git -C "$TEST_PROJECT_ROOT" hash-object -w "$tmp")
  rm -f "$tmp"
  local tree; tree=$(printf '100644 blob %s\treceipt.json\n' "$blob" | git -C "$TEST_PROJECT_ROOT" mktree)
  local commit; commit=$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -m "aid: forged minimal receipt")
  git -C "$TEST_PROJECT_ROOT" update-ref "$ref" "$commit"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467"
  jq -n --arg ref "$ref" --arg h "$hash" --arg c "$candidate" --arg r "$run_id" \
    '{plan_boundary_manifest: {plan_id:"P467", candidate_sha:$c, plan_final_run_id:$r,
      plan_final_evidence_ref:$ref, plan_final_evidence_receipt_sha256:$h}}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467/plan-boundary-manifest.json"

  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  echo "more" >> "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: unrelated delivery report edit"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"needs"* || "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}

@test "D4: a manifest that internally claims a DIFFERENT plan_id than the CLI-selected plan does not grant grouped freshness (cross-plan replay)" {
  write_passing_delivery_report "P467"
  write_passing_boundary_report "P467"
  local candidate; candidate=$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)
  # Seal a fully valid, well-formed receipt for a DIFFERENT plan (P123) at
  # the SAME candidate — then let P467's own manifest internally (falsely)
  # claim plan_id:"P123" and point at that receipt. Without an explicit
  # PLAN_ID cross-check, _check2_receipt_covers_candidate would derive
  # expected_ref from the manifest's own (lying) plan_id, match this real
  # P123 receipt, and grant P467's reports grouped freshness from evidence
  # that was never about P467 at all.
  _seal_minimal_receipt "P123" "$candidate"
  local run_id="R-test-1"
  local ref="refs/heads/aid-evidence/P123/${candidate}/${run_id}"
  local hash; hash="sha256:$(git -C "$TEST_PROJECT_ROOT" show "${ref}:receipt.json" | sha256sum | awk '{print $1}')"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467"
  jq -n --arg ref "$ref" --arg h "$hash" --arg c "$candidate" --arg r "$run_id" \
    '{plan_boundary_manifest: {plan_id:"P123", candidate_sha:$c, plan_final_run_id:$r,
      plan_final_evidence_ref:$ref, plan_final_evidence_receipt_sha256:$h}}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P467/plan-boundary-manifest.json"

  git -C "$TEST_PROJECT_ROOT" checkout -q main 2>/dev/null || true
  echo "more" >> "$TEST_PROJECT_ROOT/.aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" add ".aid-o/reports/P467-delivery.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: unrelated delivery report edit"

  run "$SCRIPT" P467 --project-root "$TEST_PROJECT_ROOT" --plan-branch
  echo "$output"
  [[ "$output" == *"P467-boundary.md"*"needs"* || "$output" == *"P467-boundary.md: Head_at_generation/Head_note"* ]]
}
