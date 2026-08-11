#!/usr/bin/env bats
# aid-tier: t0
# test-aid-gitignore-backfill.bats — P063 Step 2: aid-gitignore-backfill.sh
# (Gate Runtime Baselines EPIC).
#
# Two layers:
#   1. Unit tests for gitignore_exclude_has_entry / gitignore_exclude_append
#      themselves — generic over WHICH file they operate on, exercised against
#      BOTH a plain-`.gitignore`-style fixture and a `.git/info/exclude`-style
#      fixture (same two functions, different target paths — no duplicated
#      logic anywhere).
#   2. AC9 integration tests — the real end-to-end lazy bootstrap, invoked
#      through the actual aid-run-gates.sh `run-all` entrypoint (its own
#      `aid_gate_baseline_ensure_gitignored`, called once per run — see that
#      script) against a REAL temp git repo, so the mechanism is verified as
#      actually wired end-to-end, not just unit-tested in isolation. (This
#      bootstrap function lives in aid-run-gates.sh rather than
#      aid-gate-runtime-baseline.sh: this EPIC's plan.json scopes that
#      library file to its own Step 1 only, so Step 2 integrates it purely by
#      calling its already-published functions, never modifying it.) Also
#      confirms the brand-new-project half of AC9 (shipped defaults/.gitignore
#      already contains `.aid-o/metrics/`).
#
# Covers:
#   Edge case 1 — .aid-o/metrics/ doesn't exist yet -> created on demand,
#                 triggers the lazy exclude bootstrap in the same call.
#   Edge case 2 — hand-edited unrelated lines -> only appended at EOF, never
#                 reordered/rewritten.
#   Edge case 3 — running the backfill a second time -> idempotent no-op.
#   Edge case 5 — .git/info/exclude doesn't exist yet -> created on demand.
#   AC9         — existing project bootstrap (+idempotent) and brand-new
#                 project defaults/.gitignore fixture.

load test-helpers.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gitignore-backfill.sh"
  export LIB
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  export RUN_GATES
  WORK="$(mktemp -d)"
  export WORK
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# ─── Unit tests: gitignore_exclude_has_entry ────────────────────────────────

@test "has_entry: file does not exist -> false" {
  run gitignore_exclude_has_entry "$WORK/does-not-exist" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

@test "has_entry (.gitignore-style fixture): entry present -> true" {
  local f="$WORK/.gitignore"
  printf 'node_modules/\n.aid-o/metrics/\ndist/\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
}

@test "has_entry (.gitignore-style fixture): entry absent among unrelated lines -> false" {
  local f="$WORK/.gitignore"
  printf 'node_modules/\ndist/\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

@test "has_entry (.git/info/exclude-style fixture): entry present -> true" {
  local f="$WORK/exclude"
  printf '# git ls-files --others --exclude-from=.git/info/exclude\n.aid-o/metrics/*.lock\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/*.lock"
  [ "$status" -eq 0 ]
}

@test "has_entry: exact-line match only — a substring/prefix does NOT count as present" {
  local f="$WORK/.gitignore"
  printf '.aid-o/metrics/extra-suffix\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

# ─── Unit tests: gitignore_exclude_append ───────────────────────────────────

@test "append (.gitignore-style): file absent -> created with parent dir, entry written" {
  local f="$WORK/nested/dir/.gitignore"
  [ ! -e "$f" ]
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  [ -f "$f" ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
}

@test "append (.git/info/exclude-style): file absent -> created on demand (edge case 5)" {
  local f="$WORK/git-info/exclude"
  [ ! -e "$f" ]
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/*.lock"
  [ -f "$f" ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/*.lock"
  [ "$status" -eq 0 ]
}

@test "append: hand-edited unrelated lines are preserved, entry only appended at EOF (edge case 2)" {
  local f="$WORK/.gitignore"
  printf '# hand-written header\nnode_modules/\n*.log\n' > "$f"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  # Original lines untouched, in original order.
  [ "$(sed -n '1p' "$f")" = "# hand-written header" ]
  [ "$(sed -n '2p' "$f")" = "node_modules/" ]
  [ "$(sed -n '3p' "$f")" = "*.log" ]
  # New entry appended at EOF, exactly once.
  [ "$(sed -n '4p' "$f")" = ".aid-o/metrics/" ]
  [ "$(wc -l < "$f")" -eq 4 ]
}

@test "append: running twice is idempotent — no duplicate line (edge case 3)" {
  local f="$WORK/.git-info-exclude"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  local count
  count=$(grep -cxF ".aid-o/metrics/" "$f")
  [ "$count" -eq 1 ]
}

@test "append: two different entries against the same file both land, in call order" {
  local f="$WORK/.gitignore"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/*.lock"
  [ "$(sed -n '1p' "$f")" = ".aid-o/metrics/" ]
  [ "$(sed -n '2p' "$f")" = ".aid-o/metrics/*.lock" ]
}

# ─── AC9: end-to-end lazy bootstrap via aid-run-gates.sh run-all ────────────
# Real temp git repo (not a bare fixture) so the wiring through
# aid-run-gates.sh's aid_gate_baseline_ensure_gitignored is proven end-to-end
# (driven through the real `run-all` entrypoint, exactly like production),
# not just each half in isolation. Uses the REAL default baseline-file path
# (no AID_GATE_BASELINE_FILE override) — that override is precisely what
# tells aid_gate_baseline_ensure_gitignored "this is an isolated test, never
# touch git", so it must stay UNSET for these tests to exercise the real path.

_ac9_setup_git_repo() {
  AC9_REPO="$WORK/existing-project"
  mkdir -p "$AC9_REPO"
  ( cd "$AC9_REPO" \
    && { git init -q -b main 2>/dev/null || git init -q ; } \
    && git config user.email "test@test.local" \
    && git config user.name "Test" \
    && mkdir -p .aid-o/config \
    && echo "gates: {}" > .aid-o/config/execution.yaml \
    && git add .aid-o/config/execution.yaml \
    && git commit -q -m "already-initialized project" )
  cat > "$AC9_REPO/exec.yaml" <<'YAML'
gates:
  bats_all:
    command: "exit 0"
    required: true
YAML
}

# _ac9_run_gates <repo> — drives a real aid-run-gates.sh run-all inside
# <repo> (CWD-relative, matching production's bare-CWD convention), with
# AID_GATE_BASELINE_FILE explicitly unset so the real default path is used.
_ac9_run_gates() {
  local repo="$1"
  ( cd "$repo" \
    && unset AID_GATE_BASELINE_FILE \
    && "$RUN_GATES" run-all exec.yaml E-X R-1 >/dev/null 2>&1 )
}

@test "AC9: first baseline write in an existing (already-initialized) project backfills .git/info/exclude, never touches tracked .gitignore" {
  _ac9_setup_git_repo
  _ac9_run_gates "$AC9_REPO"

  run grep -qxF ".aid-o/metrics/" "$AC9_REPO/.git/info/exclude"
  [ "$status" -eq 0 ]
  run grep -qxF ".aid-o/metrics/*.lock" "$AC9_REPO/.git/info/exclude"
  [ "$status" -eq 0 ]
  # Never touches the tracked .gitignore (doesn't even exist in this fixture).
  [ ! -e "$AC9_REPO/.gitignore" ]
  # The baseline file itself landed under .aid-o/metrics/ and is untracked
  # (now genuinely ignored) rather than accidentally staged.
  [ -f "$AC9_REPO/.aid-o/metrics/gate-runtime-baselines.yaml" ]
  run git -C "$AC9_REPO" status --porcelain .aid-o/metrics/
  [ -z "$output" ]
}

@test "AC9: .git/info/exclude doesn't exist yet in this clone -> created on demand (edge case 5, real repo)" {
  _ac9_setup_git_repo
  rm -f "$AC9_REPO/.git/info/exclude"
  [ ! -e "$AC9_REPO/.git/info/exclude" ]

  _ac9_run_gates "$AC9_REPO"

  [ -f "$AC9_REPO/.git/info/exclude" ]
  run grep -qxF ".aid-o/metrics/" "$AC9_REPO/.git/info/exclude"
  [ "$status" -eq 0 ]
}

@test "AC9: second run is idempotent — no duplicate .git/info/exclude lines, no reordering of hand-edited entries" {
  _ac9_setup_git_repo
  printf '# hand-written local ignore\nscratch/\n' > "$AC9_REPO/.git/info/exclude"

  _ac9_run_gates "$AC9_REPO"
  _ac9_run_gates "$AC9_REPO"

  local exclude="$AC9_REPO/.git/info/exclude"
  [ "$(sed -n '1p' "$exclude")" = "# hand-written local ignore" ]
  [ "$(sed -n '2p' "$exclude")" = "scratch/" ]
  local count
  count=$(grep -cxF ".aid-o/metrics/" "$exclude")
  [ "$count" -eq 1 ]
  count=$(grep -cxF ".aid-o/metrics/*.lock" "$exclude")
  [ "$count" -eq 1 ]
}

@test "AC9: already-gitignored via tracked .gitignore -> bootstrap never touches .git/info/exclude at all" {
  _ac9_setup_git_repo
  ( cd "$AC9_REPO" \
    && echo ".aid-o/metrics/" > .gitignore \
    && git add .gitignore \
    && git commit -q -m "project already ignores metrics dir" )

  _ac9_run_gates "$AC9_REPO"

  # check-ignore already said "yes" via the tracked .gitignore, so the
  # bootstrap short-circuits before ever calling gitignore_exclude_append —
  # .git/info/exclude (present or not, per git-init defaults) must never
  # gain our entry.
  run grep -qxF ".aid-o/metrics/" "$AC9_REPO/.git/info/exclude"
  [ "$status" -ne 0 ]
}

@test "AID_GATE_BASELINE_FILE override (test isolation) -> run-all never touches git state at all" {
  # Regression guard for the exact hazard this suite's own harness must
  # avoid: a bats suite pointing AID_GATE_BASELINE_FILE at an isolated tmp
  # file (the documented test-isolation seam — see e.g.
  # test-aid-gate-runtime-baseline.bats) must be a guaranteed no-op on git
  # state, even though it runs from inside a real git repo (this plugin's own
  # dev checkout, in that suite's case). Proven here against a THROWAWAY repo
  # so this test itself can never pollute anything real.
  _ac9_setup_git_repo
  local before_exclude="" before_status
  [ -f "$AC9_REPO/.git/info/exclude" ] && before_exclude="$(cat "$AC9_REPO/.git/info/exclude")"
  before_status="$(git -C "$AC9_REPO" status --porcelain)"

  ( cd "$AC9_REPO" \
    && AID_GATE_BASELINE_FILE="$WORK/isolated-baseline.yaml" "$RUN_GATES" run-all exec.yaml E-X R-1 >/dev/null 2>&1 )

  local after_exclude="" after_status
  [ -f "$AC9_REPO/.git/info/exclude" ] && after_exclude="$(cat "$AC9_REPO/.git/info/exclude")"
  after_status="$(git -C "$AC9_REPO" status --porcelain)"
  [ "$before_exclude" = "$after_exclude" ]
  [ "$before_status" = "$after_status" ]
  # The override was honored — the baseline file landed at the isolated path,
  # NOT under the repo's own .aid-o/metrics/.
  [ -f "$WORK/isolated-baseline.yaml" ]
  [ ! -e "$AC9_REPO/.aid-o/metrics/gate-runtime-baselines.yaml" ]
}

# ─── AC9 (brand-new project half): shipped defaults/.gitignore ─────────────

@test "AC9: brand-new project fixture — shipped defaults/.gitignore already contains .aid-o/metrics/" {
  run grep -qxF ".aid-o/metrics/" "$PLUGIN_ROOT/defaults/.gitignore"
  [ "$status" -eq 0 ]
}
