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
  BACKLOG="$TEST_TMPDIR/backlog.md"
  export EV OUT BACKLOG
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

_audit() {
  jq -nc --argjson blocking "${1:-0}" --argjson other "${2:-0}" '
    {audit_report: {findings:
      ([range($blocking) | {severity: "high"}] + [range($other) | {severity: "low"}])}}' \
    > "$EV/audit-report.json"
}

_curator() {
  local ids="$1"
  jq -nc --argjson ids "$ids" '{curator: {proposals: [$ids[] | {id: ., recommended_disposition: "approve"}]}}' \
    > "$EV/curator-report.json"
}

_backlog() {
  cat > "$BACKLOG" <<'MD'
## Active Proposals

| ID | Type | Area | Suggestion | Priority | Source | Status |
|----|------|------|------------|----------|--------|--------|
| IMP-601 | refactoring | scripts/lib | **Dvě kopie téhož mapování důvodů.** Rozejdou se. Effort S. | low | curator (E-089-1_3) | pending |
| IMP-602 | bug | docs | **Registr neuvádí anti-drift bránu.** Effort S. | medium | curator (E-089-1_3) | pending |
MD
}

# ─── the page names the backlog items AND why they exist ────────────────────

@test "the page names each backlog item with the reason it was filed" {
  _state; _audit 0 2; _curator '["IMP-601","IMP-602"]'; _backlog
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]

  grep -qF 'IMP-601 — Dvě kopie téhož mapování důvodů.' "$OUT"
  grep -qF 'IMP-602 — Registr neuvádí anti-drift bránu.' "$OUT"
  grep -qF '<span class="k">Kroků</span><span class="v">4</span>' "$OUT"
  grep -qF '<span class="k">Blokující</span><span class="v">0</span>' "$OUT"
  grep -qF 'Hotovo, s otevřenými návrhy' "$OUT"
  # The duration is COMPUTED from the state file, never asserted.
  grep -qF '<span class="k">Trvalo</span><span class="v">2 h 30 min</span>' "$OUT"
}

@test "an item the backlog does not carry says so instead of inventing a reason" {
  _state; _audit 0 0; _curator '["IMP-999"]'; _backlog
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]
  grep -qF 'IMP-999 — důvod vzniku není v backlogu dohledatelný' "$OUT"
}

# ─── an incomplete review is NAMED, never implied away ──────────────────────

@test "a missing curator report is named on the page and changes the verdict" {
  _state; _audit 0 1
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]

  grep -qF 'CHYBÍ report kurátora' "$OUT"
  grep -qF 'Revize neúplná' "$OUT"
  # And the decision it forces is a real decision, with a recommendation.
  grep -qF 'Doporučuju dokončit' "$OUT"
  grep -qF '<h2>Jak pokračovat</h2>' "$OUT"
}

@test "blocking findings make the verdict critical and the decision explicit" {
  _state; _audit 2 3; _curator '[]'
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]

  grep -qF 'Blokující nálezy' "$OUT"
  grep -qF 'state-critical' "$OUT"
  grep -qF '<span class="k">Blokující</span><span class="v">2</span>' "$OUT"
  grep -qF 'Audit: 5 nálezů, z toho 2 blokujících' "$OUT"
  grep -qF 'Doporučuju vrátit' "$OUT"
}

@test "a clean EPIC with no proposals asks for nothing, and no command stands beside that" {
  _state; _audit 0 0; _curator '[]'
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]

  grep -qF 'Hotovo, bez nálezů' "$OUT"
  grep -qF 'Nic — ozvu se, až bude hotovo' "$OUT"
  refute_grep -qF '<h2>Jak pokračovat</h2>' "$OUT"
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
  grep -qF 'CHYBÍ report auditu' "$page"
}

@test "an audit report whose verdict cannot be read is named, not read as clean (Codex, P089)" {
  _state
  # The .yaml form with findings but no `blocking_findings:` line — a report
  # this page cannot vouch for.
  cat > "$EV/audit-report.yaml" <<'YAML'
audit_report:
  findings:
    - severity: high
      title: Production regression
YAML
  _curator '[]'
  run aid_epic_summary_page_render "$EV" "$OUT" "$BACKLOG"
  [ "$status" -eq 0 ]
  grep -qF 'CHYBÍ čitelný verdikt auditu' "$OUT"
  grep -qF 'Revize neúplná' "$OUT"
  refute_grep -qF 'Audit doběhl a blokující nálezy nehlásí' "$OUT"
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
