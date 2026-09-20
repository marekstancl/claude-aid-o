#!/usr/bin/env bats
# aid-tier: t1
# test-epic-summary-page.bats — the PM's page about a FINISHED EPIC
# (P089 Step 4).
#
# TIER, HONESTLY. The plan proposed t0. The last case drives the REAL caller —
# `aid-fsm.sh done-advance review release` — and that needs a git repository
# with a commit, which alone costs more than the whole t0 budget allows per
# case. Tier follows measured cost, never importance, so the suite is t1.
#
# WHY A CALLER-FLOW CASE AT ALL
#   A unit test of the renderer proves the renderer. It cannot prove that
#   anything in the running system ever calls it — and a page nobody produces
#   is exactly what the Step 6 obligation would then demand forever. The CP
#   contract states it as a rule: every new integration function needs at least
#   one caller-flow test.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  EV="$TEST_TMPDIR/evidence"
  OUT="$TEST_TMPDIR/epic-summary-artifact.html"
  export EV OUT
  mkdir -p "$EV"
  unset AID_PROJECT_ROOT
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-epic-summary-page.sh"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# ─── fixtures ───────────────────────────────────────────────────────────────

_state() {
  cat > "$EV/fsm-state.yaml" <<YAML
epic_id: ${1:-E-089-1_3}
run_id: R-E089-1
state: DONE
current_step: 4
total_steps: 4
gate_retries: ${2:-0}
started_at: "2026-08-26T08:00:00Z"
steps:
  - id: 4
    status: completed
    completed_at: "2026-08-26T10:30:00Z"
done_phase: review
YAML
  # A real run always leaves one of these behind, and since 2026-08-28 the
  # profile requires what they carry. Fixtures that render successfully must
  # therefore have one too; the test that proves the refusal removes it.
  cat > "$EV/final_report.md" <<'MD'
# Final report

## Co EPIC dodal

- co bylo dodáno v této fixture
MD
}

# _review <verdict> <open blockers> <open majors> — a closed EPIC review round
_review() {
  mkdir -p "$EV/cp3/round-1"
  jq -nc --arg v "$1" '{checkpoint: "cp3", verdict: $v, rounds: [{round: 1, verdict: $v}]}' > "$EV/cp3/rounds.json"
  jq -nc --argjson b "${2:-0}" --argjson m "${3:-0}" '
    {findings: ([range($b) | {severity: "blocker", status: "open", claim: "b"}]
              + [range($m) | {severity: "major", status: "open", claim: "m"}]
              + [{severity: "minor", status: "fixed", claim: "done"}])}' > "$EV/cp3/round-1/merged.json"
}

# ─── what the review left open is on the page ───────────────────────────────

@test "a passed review with open findings says how many stay open" {
  _state; _review pass 0 2
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]

  grep -qF 'Revize EPICu prošla, otevřených nálezů zůstává 2' "$OUT"
  grep -qF '<span class="k">Kroků</span><span class="v">4</span>' "$OUT"
  grep -qF '<span class="k">Blokující</span><span class="v">0</span>' "$OUT"
  grep -qF 'Hotovo, s otevřenými nálezy' "$OUT"
  # The duration is COMPUTED from the state file, never asserted.
  grep -qF '<span class="k">Trvalo</span><span class="v">2 h 30 min</span>' "$OUT"
}

# ─── an incomplete review is NAMED, never implied away ──────────────────────

@test "a missing review record is named on the page and changes the verdict" {
  _state
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]

  grep -qF 'CHYBÍ záznam revize EPICu' "$OUT"
  grep -qF 'Revize neúplná' "$OUT"
  # And the decision it forces is a real decision, with a recommendation.
  grep -qF 'Doporučuju dokončit' "$OUT"
  grep -qF '<h2>Jak pokračovat</h2>' "$OUT"
}

@test "open blockers make the verdict critical and the decision explicit" {
  _state; _review fail 2 3
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]

  grep -qF 'Blokující nálezy' "$OUT"
  grep -qF 'state-critical' "$OUT"
  grep -qF '<span class="k">Blokující</span><span class="v">2</span>' "$OUT"
  grep -qF 'Revize EPICu neprošla: otevřených nálezů 5, z toho 2 blokujících' "$OUT"
  grep -qF 'Doporučuju vrátit' "$OUT"
}

@test "a clean EPIC asks for nothing, and no command stands beside that" {
  _state; _review pass 0 0
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]

  grep -qF 'Hotovo, bez nálezů' "$OUT"
  grep -qF 'Nic — ozvu se, až bude hotovo' "$OUT"
  refute_grep -qF '<h2>Jak pokračovat</h2>' "$OUT"
}

@test "a round index with no verdict is named, not read as clean" {
  _state; _review pass 0 0
  echo '{"checkpoint": "cp3"}' > "$EV/cp3/rounds.json"
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]
  grep -qF 'CHYBÍ záznam revize EPICu' "$OUT"
  grep -qF 'Revize neúplná' "$OUT"
}

@test "a run whose state file is unreadable is refused, not guessed at" {
  rm -f "$EV/fsm-state.yaml"
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fsm-state.yaml"* ]]
  [ ! -f "$OUT" ]
}

# ─── the REAL caller: done-advance review → release ─────────────────────────

@test "cmd_done_advance renders the page at the contracted path, newer than the EPIC's last commit" {
  local d="$TEST_TMPDIR/primary"
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

  run bash -c "cd '$d' && '$FSM' init E-901-1_1 R-A 1 manual main HEAD \
    '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]

  local sf="$d/.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml"
  sed -i 's/^state: READY/state: DONE/' "$sf"
  echo "done_phase: review" >> "$sf"

  run bash -c "cd '$d' && '$FSM' done-advance review release \
    '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml' \
    --force --reason 'PM-authorized test override to reach the release edge'" 3>&-
  [ "$status" -eq 0 ]

  # EXACTLY the path the Step 6 obligation looks at — the same convention as
  # plan-summary-artifact.html, one directory deeper.
  local page="$d/.aid-o/work/evidence/P901/E-901-1_1/epic-summary-artifact.html"
  [ -f "$page" ]
  # And newer than the EPIC's last commit, which is what freshness means here.
  [ "$page" -nt "$d/.git/HEAD" ] || [ "$page" -nt "$d/README.md" ]
  grep -qF 'EPIC E-901-1_1' "$page"
  grep -qF 'CHYBÍ záznam revize EPICu' "$page"
}

# --- the page must say what the EPIC produced -----------------------------
# PM, 2026-08-28, on three near-identical WAN P099 pages: none of them named a
# single thing the work produced, while the text sat two files away in the same
# evidence directory.

@test "deliverables: the numbered list in final_report.md becomes what the EPIC delivered" {
  _state
  cat > "$EV/final_report.md" <<'MD'
# Final report

## Co EPIC dodal

Úvodní věta, která se nemá brát.

1. **Stránka [`/wan/mcp`](https://example.test/x)** (repozitář `docs`) — 16 nástrojů
2. **Nasazení a noční sestava** — wan-mcp v compose
MD
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Co EPIC dodal" "$OUT"
  grep -q "Stránka /wan/mcp" "$OUT"          # link target stripped, text kept
  grep -q "Nasazení a noční sestava" "$OUT"
  ! grep -q "Úvodní věta" "$OUT"             # prose under the heading is not a deliverable
  ! grep -q "Krok 1:" "$OUT"                 # a finished page lists results, not step numbers
}

@test "deliverables: a bulleted epic-summary.md is read when final_report.md has none" {
  _state
  rm -f "$EV/final_report.md"
  cat > "$EV/epic-summary.md" <<'MD'
# summary

## ✅ Co bylo dodáno

- první věc
- druhá věc
MD
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "první věc" "$OUT"
  grep -q "druhá věc" "$OUT"
}

@test "deliverables: with neither source the render refuses rather than shipping an empty page" {
  _state
  rm -f "$EV/final_report.md" "$EV/epic-summary.md"
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -ne 0 ]
}

@test "deliverables: a NEGATIVE heading is not read as what was delivered (Codex, 2026-08-28)" {
  _state
  cat > "$EV/final_report.md" <<'MD'
# Final report

## Not delivered

- tohle se NEdodalo

## Undelivered items

- ani tohle
MD
  run aid_epic_summary_page_render "$EV" "$OUT"
  # No affirmative heading anywhere → no deliverables → the profile refuses.
  [ "$status" -ne 0 ]
}

@test "deliverables: an English affirmative heading is read" {
  _state
  cat > "$EV/final_report.md" <<'MD'
# Final report

## What the EPIC delivered

- the read-only tool set
MD
  run aid_epic_summary_page_render "$EV" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "the read-only tool set" "$OUT"
}
