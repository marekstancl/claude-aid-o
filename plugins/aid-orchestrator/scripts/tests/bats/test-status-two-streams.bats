#!/usr/bin/env bats
# test-status-two-streams.bats — P074 Step 12: the two-stream `/aid-status`
# surface, its rendering recipes, and the rendered overview itself.
#
# WHY THIS SUITE EXISTS AND WHAT IT ACTUALLY TESTS: `/aid-status` is a
# PROSE-DRIVEN surface — there is no status script, by design (Step 12 keeps
# it that way). A test that re-implemented the rendering in bash would prove
# nothing about the documented instruction, which is the thing agents
# actually execute. So this suite EXTRACTS the recipe blocks from
# `commands/aid-status.md` (```bash fences whose first line is
# `# recipe: <name>`), CONCATENATES them in file order, calls
# `render_overview`, and compares the result BYTE-FOR-BYTE with the example
# renders published in that same file. The doc is the implementation; the doc
# is what runs here. Delete a rendering instruction and this suite goes red.
#
# Covered: the full two-stream render (plan blocks, worktree column, the
# `missing!` marker, `Closing:`, the unreadable-state degradation line, the
# unassigned-runs block, quick tasks, the queue summary), the plan-less flat
# render, the deterministic `next-epic` rule (live runs by epic_id order, then
# the queue candidate, then `(none)`), and the individual recipes.
#
# Every fixture is a real git repository (with a real linked worktree in the
# two-stream case): the recipes resolve `.aid-o` through lib/aid-roots.sh, and
# the worktree-invariance case is the regression test for the surface being
# rendered from inside a plan worktree at all.
#
# FD-3 HYGIENE: every recipe runs in a child shell — run them with `3>&-`.
# After any edit verify:
#   bats --tap test-status-two-streams.bats | grep -cE '^(ok|not ok)'   # == 17

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DOC="$AID_PLUGIN_PATH/commands/aid-status.md"
  export DOC
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_QUEUE_FILE AID_QUEUE_WRITE_PROJECT_ROOT
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# ─── the extractor: the doc IS the implementation under test ─────────────

# _recipes [name] — every `# recipe:` block body in file order, or just the
# named one. Comments included: they are part of the documented instruction.
_recipes() {
  awk -v want="${1:-}" '
    /^# recipe: / {
      n = $0; sub(/^# recipe: /, "", n); sub(/ .*$/, "", n)
      if (want == "" || want == n) { inblk = 1; print; next }
      skip = 1; next
    }
    inblk && /^```$/ { inblk = 0; next }
    skip  && /^```$/ { skip = 0; next }
    inblk { print }
  ' "$DOC"
}

# _doc_render <n> — the n-th published example render (a fenced block whose
# first line is `AID Status`): 1 = two-stream, 2 = plan-less flat.
_doc_render() {
  awk -v want="$1" '
    /^```$/ && !inblk { inblk = 1; first = 1; next }
    /^```$/ &&  inblk { inblk = 0; next }
    inblk {
      if (first) { first = 0; if ($0 != "AID Status") { inblk = 0; next }; n++ }
      if (n == want) print
    }
  ' "$DOC"
}

# FD-3 HAZARD (verified on bats 1.8.2, 2026-08-06): a `run` child that exits
# 127 triggers bats' BW01 warning, which is written to fd 3 — and with fd 3
# closed (`3>&-`, mandatory here) that write breaks the reporter and the WHOLE
# FILE's results vanish as "Executed 0 instead of expected N". A deleted recipe
# is exactly a 127 (function not defined), i.e. the negative-control case would
# silently lose its own red. Both helpers below therefore turn "the doc did not
# define this function" into a named rc 1 before calling it.

# _render <cwd> — assemble every recipe and print the overview.
_render() {
  local body; body="$(_recipes)"
  run bash -c "cd '$1' && $body
declare -F render_overview >/dev/null || { echo 'MISSING: render_overview is not defined by aid-status.md' >&2; exit 1; }
render_overview" 3>&-
}

# _call <cwd> <shell-expression> — assemble every recipe and evaluate one call.
_call() {
  local dir="$1" expr="$2" fn="${2%% *}" body; body="$(_recipes)"
  run bash -c "cd '$dir' && $body
declare -F ${fn} >/dev/null || { echo 'MISSING: ${fn} is not defined by aid-status.md' >&2; exit 1; }
$expr" 3>&-
}

# ─── fixtures ────────────────────────────────────────────────────────────

# _repo <dir> — a committed git repo with `.aid-o/` gitignored, exactly like a
# real AID project. The recipes resolve state through lib/aid-roots.sh, which
# needs a repository and fails loudly outside one — so every fixture is a repo.
_repo() {
  local d="$1"
  mkdir -p "$d"
  printf '.aid-o/\n.aid-worktrees/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed"
  )
}

# _plan <root> <plan_id> <plan_state> [worktree_path]
_plan() {
  local d="$1" pid="$2" state="$3" wt="${4:-}"
  mkdir -p "$d/.aid-o/work/plan-state/$pid"
  {
    echo "plan_id: $pid"
    echo "plan_state: $state"
    echo "mode: plan_branch"
    if [[ -n "$wt" ]]; then echo "worktree_path: $wt"; fi
  } > "$d/.aid-o/work/plan-state/$pid/plan-state.yaml"
}

# _fixture <root> full|flat — THE fixture the published example renders were
# produced from. `full`: P901 (worktree present, two runs, one queue row),
# P902 (worktree recorded but absent, no runs, one queue row with a dep),
# P903 (PLAN_MERGING → closing), P904 (unparseable state file), one plan-less
# run, four quick logs with fixed mtimes. `flat`: no plan-state at all.
_fixture() {
  local d="$1" mode="${2:-full}"
  _repo "$d"
  mkdir -p "$d/.aid-o/work/quick" "$d/.aid-o/config"

  if [[ "$mode" == "full" ]]; then
    # a REAL linked worktree — the tree /aid-status must also be renderable from
    git -C "$d" worktree add -q -b plan/P901 "$d/.aid-worktrees/plan-P901" main
    _plan "$d" P901 EPIC_INTEGRATION ".aid-worktrees/plan-P901"
    _plan "$d" P902 PLAN_GATES ".aid-worktrees/plan-P902"   # directory absent on purpose
    _plan "$d" P903 PLAN_MERGING
    mkdir -p "$d/.aid-o/work/plan-state/P904"
    printf 'plan_id: P904\n  bad: [\n' > "$d/.aid-o/work/plan-state/P904/plan-state.yaml"
    cat > "$d/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-901-1_2": {"state_file": ".aid-o/work/evidence/E-901-1_2/R-A/fsm-state.yaml",
                "run_id": "R-A", "state": "EXECUTE", "branch": "task/E-901-1_2/main",
                "plan_id": "P901", "governs_main": true, "updated_at": "2026-08-06T00:00:00Z"},
  "E-901-2_2": {"state_file": ".aid-o/work/evidence/E-901-2_2/R-B/fsm-state.yaml",
                "run_id": "R-B", "state": "READY", "branch": "task/E-901-2_2/main",
                "plan_id": "P901", "governs_main": false, "updated_at": "2026-08-06T00:00:00Z"},
  "E-900-1_1": {"state_file": ".aid-o/work/evidence/E-900-1_1/R-D/fsm-state.yaml",
                "run_id": "R-D", "state": "GATES", "branch": "task/E-900-1_1/main",
                "plan_id": null, "governs_main": true, "updated_at": "2026-08-06T00:00:00Z"}
}
JSON
  else
    # A plan-less project has no plan-owned runs by construction: plan-state is
    # written at plan-start, before any EPIC of that plan is initialized.
    cat > "$d/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-900-1_1": {"state_file": ".aid-o/work/evidence/E-900-1_1/R-D/fsm-state.yaml",
                "run_id": "R-D", "state": "GATES", "branch": "task/E-900-1_1/main",
                "plan_id": null, "governs_main": true, "updated_at": "2026-08-06T00:00:00Z"}
}
JSON
  fi

  cat > "$d/.aid-o/config/queue.yaml" <<'YAML'
paused: false
queue:
  - epic_id: E-901-3_3
    path: .aid-o/tasks/E-901-3_3.md
    priority: high
    status: pending
    depends_on: []
    plan_id: "P901"
  - epic_id: E-902-2_2
    path: .aid-o/tasks/E-902-2_2.md
    priority: low
    status: queued
    depends_on: ["E-902-1_1"]
    plan_id: "P902"
  - epic_id: E-000-1_1
    path: .aid-o/tasks/E-000-1_1.md
    priority: medium
    status: completed
    depends_on: []
    plan_id: null
YAML

  printf '# Add login button\n' > "$d/.aid-o/work/quick/Q-007.md"
  printf '# Fix README typo\n'  > "$d/.aid-o/work/quick/Q-006.md"
  printf '# Older thing\n'      > "$d/.aid-o/work/quick/Q-005.md"
  printf '# Oldest thing\n'     > "$d/.aid-o/work/quick/Q-004.md"
  touch -d '2026-08-06T10:00:00' "$d/.aid-o/work/quick/Q-007.md"
  touch -d '2026-08-06T09:00:00' "$d/.aid-o/work/quick/Q-006.md"
  touch -d '2026-08-06T08:00:00' "$d/.aid-o/work/quick/Q-005.md"
  touch -d '2026-08-06T07:00:00' "$d/.aid-o/work/quick/Q-004.md"
}

# ─── the rendered artifact: doc promise == doc output ────────────────────

@test "the two-stream fixture renders EXACTLY the example render published in aid-status.md" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _render "$d"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_TMPDIR/got.txt"
  _doc_render 1 > "$TEST_TMPDIR/want.txt"
  [ -s "$TEST_TMPDIR/want.txt" ]
  run diff -u "$TEST_TMPDIR/want.txt" "$TEST_TMPDIR/got.txt"
  [ "$status" -eq 0 ]
}

@test "the plan-less fixture renders EXACTLY the published flat render (today's shape)" {
  local d="$TEST_TMPDIR/flat"
  _fixture "$d" flat
  _render "$d"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_TMPDIR/got.txt"
  _doc_render 2 > "$TEST_TMPDIR/want.txt"
  [ -s "$TEST_TMPDIR/want.txt" ]
  run diff -u "$TEST_TMPDIR/want.txt" "$TEST_TMPDIR/got.txt"
  [ "$status" -eq 0 ]
  # the flat shape has no plan furniture at all
  ! grep -q '^Plan P' "$TEST_TMPDIR/got.txt"
  ! grep -q '^Closing:' "$TEST_TMPDIR/got.txt"
  grep -q '^Active EPICs:$' "$TEST_TMPDIR/got.txt"
}

@test "the SAME overview renders from inside a linked plan worktree, from a subdirectory, and from the primary checkout" {
  # THE REGRESSION THIS CLOSES: `.aid-o` is gitignored, so a linked worktree
  # never has one. Any cwd-relative read renders an empty plan-less overview
  # there while the PM believes they are looking at the project's state. The
  # recipes must resolve the state root (lib/aid-roots.sh) instead.
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  [ -d "$d/.aid-worktrees/plan-P901/.git" ] || [ -f "$d/.aid-worktrees/plan-P901/.git" ]
  [ ! -d "$d/.aid-worktrees/plan-P901/.aid-o" ]      # the worktree has no state of its own
  _render "$d"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_TMPDIR/primary.txt"
  _render "$d/.aid-worktrees/plan-P901"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_TMPDIR/worktree.txt"
  run diff -u "$TEST_TMPDIR/primary.txt" "$TEST_TMPDIR/worktree.txt"
  [ "$status" -eq 0 ]
  # and from an ordinary subdirectory of the primary checkout
  mkdir -p "$d/src/deep"
  _render "$d/src/deep"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_TMPDIR/subdir.txt"
  run diff -u "$TEST_TMPDIR/primary.txt" "$TEST_TMPDIR/subdir.txt"
  [ "$status" -eq 0 ]
  # the rendered overview is real content, not two identically-empty renders
  grep -q '^Plan P901 — EPIC_INTEGRATION$' "$TEST_TMPDIR/worktree.txt"
  grep -q '^Queue: 2 queued, 0 running, 1 done | Auto-pickup: active$' "$TEST_TMPDIR/worktree.txt"
}

@test "each active stream renders its own block: header, worktree, EPIC rows, queue rows, next" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _render "$d"
  [ "$status" -eq 0 ]
  # exactly two plan blocks — the closing and the unreadable plan are not blocks
  [ "$(grep -c '^Plan P' <<<"$output")" -eq 2 ]
  [[ "$output" == *"Plan P901 — EPIC_INTEGRATION"$'\n'"  worktree: .aid-worktrees/plan-P901"$'\n'"  EPICs:"* ]]
  [[ "$output" == *"    E-901-1_2  [EXECUTE]  run=R-A  branch=task/E-901-1_2/main  governs-main"* ]]
  [[ "$output" == *"    E-901-2_2  [READY]  run=R-B  branch=task/E-901-2_2/main"* ]]
  [[ "$output" == *"  Queue:"$'\n'"    E-901-3_3  [pending]  high"* ]]
  [[ "$output" == *"  next: E-901-1_2  [EXECUTE]"* ]]
  # the second stream: no live runs, so the queue candidate is the next EPIC
  [[ "$output" == *"Plan P902 — PLAN_GATES"* ]]
  [[ "$output" == *"  EPICs:"$'\n'"    (none active)"* ]]
  [[ "$output" == *"  next: E-902-2_2  [queue:pending, 1 dep(s) unverified]"* ]]
  # the plan-less run is visible, and not attached to either plan
  [[ "$output" == *"Unassigned EPIC runs (no plan):"$'\n'"  E-900-1_1  [GATES]"* ]]
}

@test "the rendered worktree column carries the missing! marker with the recorded path verbatim" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _render "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"  worktree: .aid-worktrees/plan-P902   missing!"* ]]
  [[ "$output" != *"plan-P901   missing!"* ]]
  # deleting the present worktree flips its marker too
  rm -rf "$d/.aid-worktrees/plan-P901"
  _render "$d"
  [[ "$output" == *"  worktree: .aid-worktrees/plan-P901   missing!"* ]]
}

@test "an absolute worktree_path that no longer resolves renders missing! with the recorded path, never a guess" {
  local d="$TEST_TMPDIR/moved"
  _repo "$d"
  _plan "$d" P901 PLAN_SYNC "/moved/away/repo/.aid-worktrees/plan-P901"
  mkdir -p "$d/moved/away/repo/.aid-worktrees/plan-P901"   # same-named dir must not rescue it
  _render "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"  worktree: /moved/away/repo/.aid-worktrees/plan-P901   missing!"* ]]
}

@test "a closing plan renders under Closing: and never as a plan block" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _render "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Closing:"$'\n'"  P903 — PLAN_MERGING (worktree -)"* ]]
  [[ "$output" != *"Plan P903"* ]]
}

@test "an unparseable plan-state degrades to its one documented line; every other block still renders" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _render "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan P904: state unreadable — run plan-state P904 --repair"* ]]
  [[ "$output" == *"Plan P901 — EPIC_INTEGRATION"* ]]
  [[ "$output" == *"Plan P902 — PLAN_GATES"* ]]
  [[ "$output" == *"Closing:"* ]]
}

@test "quick tasks render the three newest by mtime, titled, newest first" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _call "$d" quick_tasks
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "  Q-007 — Add login button" ]
  [ "${lines[1]}" = "  Q-006 — Fix README typo" ]
  [ "${lines[2]}" = "  Q-005 — Older thing" ]
  [[ "$output" != *"Q-004"* ]]
}

@test "queue summary counts by the queue layer's status vocabulary and reports the auto-pickup flag" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _call "$d" queue_summary
  [ "$status" -eq 0 ]
  # pending + legacy `queued` = queued; legacy `completed` = done
  [ "$output" = "2 queued, 0 running, 1 done | Auto-pickup: active" ]
  sed -i 's/^paused: false/paused: true/' "$d/.aid-o/config/queue.yaml"
  _call "$d" queue_summary
  [[ "$output" == *"Auto-pickup: paused"* ]]
  # a blocked entry gets its own count
  sed -i '0,/status: pending/s//status: blocked/' "$d/.aid-o/config/queue.yaml"
  _call "$d" queue_summary
  [ "$output" = "1 queued, 0 running, 1 done, 1 blocked | Auto-pickup: paused" ]
}

@test "no queue status vanishes from the totals — every enum value is counted, unknown values land in 'other'" {
  local d="$TEST_TMPDIR/vocab"
  _repo "$d"
  mkdir -p "$d/.aid-o/config"
  # a queue holding ONLY terminal-but-not-delivered rows must never render
  # "0 queued, 0 running, 0 done" and hide them
  cat > "$d/.aid-o/config/queue.yaml" <<'YAML'
queue:
  - epic_id: E-1-1_1
    status: abandoned
  - epic_id: E-1-2_2
    status: superseded
YAML
  _call "$d" queue_summary
  [ "$status" -eq 0 ]
  [ "$output" = "0 queued, 0 running, 0 done, 2 abandoned | Auto-pickup: active" ]
  # the full vocabulary of lib/aid-queue-write.sh, plus a hand-edited value
  cat > "$d/.aid-o/config/queue.yaml" <<'YAML'
queue:
  - epic_id: E-2-1_9
    status: pending
  - epic_id: E-2-2_9
    status: queued
  - epic_id: E-2-3_9
    status: running
  - epic_id: E-2-4_9
    status: merged_to_plan
  - epic_id: E-2-5_9
    status: released_to_main
  - epic_id: E-2-6_9
    status: completed
  - epic_id: E-2-7_9
    status: blocked
  - epic_id: E-2-8_9
    status: abandoned
  - epic_id: E-2-9_9
    status: superseded
  - epic_id: E-2-10_9
    status: hand_edited_nonsense
YAML
  _call "$d" queue_summary
  [ "$output" = "2 queued, 1 running, 3 done, 1 blocked, 2 abandoned, 1 other | Auto-pickup: active" ]
  # the buckets sum to the number of entries — nothing dropped
  _call "$d" 'queue_summary | grep -oE "[0-9]+ [a-z]+" | awk "{s+=\$1} END {print s}"'
  [ "$output" = "10" ]
}

# ─── the shared next-actionable-EPIC rule ────────────────────────────────

@test "next_epic picks the LOWEST epic_id among actionable live runs — JSON key order is not an ordering" {
  local d="$TEST_TMPDIR/order"
  _repo "$d"
  mkdir -p "$d/.aid-o/work"
  _plan "$d" P901 EPIC_INTEGRATION
  cat > "$d/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-901-9_9": {"run_id": "R-Z", "state": "READY", "branch": "b", "plan_id": "P901"},
  "E-901-0_9": {"run_id": "R-X", "state": "DONE",  "branch": "b", "plan_id": "P901"},
  "E-901-3_9": {"run_id": "R-Y", "state": "GATES", "branch": "b", "plan_id": "P901"}
}
JSON
  _call "$d" 'next_epic P901'
  [ "$status" -eq 0 ]
  # the first key is 9_9 and the lowest id overall is a DONE (not actionable) run
  [ "$output" = "E-901-3_9  [GATES]" ]
}

@test "next_epic falls back to the queue candidate (claimability test of queue_claim_next), then to (none)" {
  local d="$TEST_TMPDIR/fallback"
  _repo "$d"
  mkdir -p "$d/.aid-o/work" "$d/.aid-o/config"
  _plan "$d" P902 PLAN_GATES
  echo '{}' > "$d/.aid-o/work/active-runs.json"
  cat > "$d/.aid-o/config/queue.yaml" <<'YAML'
queue:
  - epic_id: E-902-9_9
    status: running
    depends_on: []
    plan_id: "P902"
  - epic_id: E-902-2_2
    status: queued
    depends_on: ["E-902-1_1"]
    plan_id: "P902"
YAML
  # `running` is not claimable and is skipped; the legacy `queued` reads pending
  _call "$d" 'next_epic P902'
  [ "$output" = "E-902-2_2  [queue:pending, 1 dep(s) unverified]" ]
  # no live run and no claimable queue row → the documented (none)
  _call "$d" 'next_epic P903'
  [ "$output" = "(none)" ]
}

# ─── the individual recipes ──────────────────────────────────────────────

@test "plan-rows: two active streams, correct worktree column, closing bucket, unreadable marker, plan-id order" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _call "$d" plan_rows
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = "$(printf 'P901\tEPIC_INTEGRATION\t.aid-worktrees/plan-P901\tok\tactive')" ]
  [ "${lines[1]}" = "$(printf 'P902\tPLAN_GATES\t.aid-worktrees/plan-P902\tmissing!\tactive')" ]
  [ "${lines[2]}" = "$(printf 'P903\tPLAN_MERGING\t-\tok\tclosing')" ]
  [ "${lines[3]}" = "$(printf 'P904\t?\t-\tunreadable\tactive')" ]
  # a legacy stream with no worktree_path is "-", not an error
  _plan "$d" P905 OPEN
  _call "$d" plan_rows
  [[ "$output" == *"$(printf 'P905\tOPEN\t-\tok\tactive')"* ]]
  # every terminal phase buckets as closing; CONFLICT is still work
  _plan "$d" P906 CLOSED; _plan "$d" P907 ROLLED_BACK; _plan "$d" P908 CONFLICT
  _call "$d" plan_rows
  [[ "$output" == *"$(printf 'P906\tCLOSED\t-\tok\tclosing')"* ]]
  [[ "$output" == *"$(printf 'P907\tROLLED_BACK\t-\tok\tclosing')"* ]]
  [[ "$output" == *"$(printf 'P908\tCONFLICT\t-\tok\tactive')"* ]]
}

@test "plan-epics / planless-epics: per-plan selection, epic_id sort, governs-main flag, null and absent plan_id" {
  local d="$TEST_TMPDIR/runs"
  _repo "$d"
  mkdir -p "$d/.aid-o/work"
  cat > "$d/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-901-2_2": {"run_id": "R-B", "state": "READY", "branch": "task/E-901-2_2/main", "plan_id": "P901"},
  "E-901-1_2": {"run_id": "R-A", "state": "EXECUTE", "branch": "task/E-901-1_2/main", "plan_id": "P901", "governs_main": true},
  "E-902-1_1": {"run_id": "R-C", "state": "GATES", "branch": "task/E-902-1_1/main", "plan_id": "P902"},
  "E-900-1_1": {"run_id": "R-D", "state": "GATES", "branch": "task/E-900-1_1/main", "plan_id": null},
  "E-899-1_1": {"run_id": "R-E", "state": "READY", "branch": "task/E-899-1_1/main"}
}
JSON
  _call "$d" 'plan_epics P901'
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *"E-901-1_2"*"[EXECUTE]"*"governs-main"* ]]   # sorted, not key order
  [[ "${lines[1]}" == *"E-901-2_2"*"[READY]"* ]]
  [[ "${lines[1]}" != *"governs-main"* ]]
  [[ "$output" != *"E-902"* ]]
  _call "$d" planless_epics
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *"E-899-1_1"* ]]   # plan_id key absent
  [[ "${lines[1]}" == *"E-900-1_1"* ]]   # plan_id null
  [[ "$output" != *"E-901"* ]]
  # a missing map is not an error for either recipe
  rm -f "$d/.aid-o/work/active-runs.json"
  _call "$d" 'plan_epics P901'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  _call "$d" planless_epics
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "queue-rows: rows split per plan_id through the queue layer's own reader; missing queue file is not an error" {
  local d="$TEST_TMPDIR/root"
  _fixture "$d" full
  _call "$d" 'queue_rows P901'
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "    E-901-3_3  [pending]  high" ]
  _call "$d" 'queue_rows P902'
  [ "${lines[0]}" = "    E-902-2_2  [pending]  low" ]   # legacy `queued` normalized
  _call "$d" 'queue_rows ""'
  [ "${lines[0]}" = "    E-000-1_1  [completed]  medium" ]
  rm -f "$d/.aid-o/config/queue.yaml"
  _call "$d" 'queue_rows P901'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "aid-status.md carries every named recipe the render composes, plus both example renders" {
  for r in state-root plan-rows plan-epics planless-epics queue-rows queue-summary next-epic quick-tasks render-overview; do
    run _recipes "$r"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
  run _doc_render 1; [ -n "$output" ]
  run _doc_render 2; [ -n "$output" ]
  grep -Fq 'plan <id>: state unreadable — run plan-state <id>' "$DOC"
}
