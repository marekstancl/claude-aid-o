#!/usr/bin/env bats
# aid-tier: t2
# test-release-policy.bats — aid-release-policy.sh (C4 release aggregator, E-059-2_2 Step 4)
#
# The HEALTHY (release_ready:true) fixture does a REAL git init + commit and aligns HEAD
# with each artifact's revision.head_sha (via .aid-o/ being gitignored, so evidence never
# dirties the tree) — without this, aid-evidence-verify.sh --at-head silently degrades to
# always-false and the green branch is never exercised (precedent: test-evidence-verify.sh).
# AID_PROJECT_ROOT is propagated into the aggregator so its evidence-verify child resolves
# the same root.
#
# Fixtures live under scripts/tests/fixtures/release-policy/ with NO .aid-o/ segment (the
# `**/.aid-o/` .gitignore rule would silently untrack them) and are copied/constructed into
# a mktemp .aid-o layout at runtime. A suite assertion verifies every fixture file is tracked.
#
# ═══════════════════════════════════════════════════════════════════════════════
# Doc-1 §13.2 FULL DISPOSITION (17 review-instruction fixtures + 10 D11 rows 18-27)
# Source table: `.aid-o/plans/P059-e9-c4-release-policy.md` Step 7 (rows 1-27).
# Every Doc-1 fixture is accounted for — none dropped. Legend:
#   ADAPTED         = the C4 aggregator expresses this fixture through a REQUIRED/audit/schema row.
#   SIMULATED       = built inline (head_match/at-head branch), not a copied fixture.
#   ADAPTED-ADVISORY= mapped, but non-blocking at C4 today (blocking deferred to E10).
#   N/A / SKIP-REF  = out of the C4 aggregator's boundary; owned by another control layer.
#
#   Row  Fixture                                        Disposition (where it lives here)
#   ───  ─────────────────────────────────────────────  ─────────────────────────────────────────
#    1   missing delivery-gate → rejected               RETIRED  → the C1 delivery gate is gone (P096 Step 8)
#    2   nested-missing fields → rejected               ADAPTED  → protocol field checks (Step 3 suite)
#    3   missing behavior_trace                         N/A      → C2/E5 owns its own hooks (not C4)
#    4   CP3 fail → fix loop not GATES                  SKIP-REF → C2/FSM checkpoint, outside C4
#    5   CP4 pass w/o rerun → CP5 rejected              ADAPTED-ADVISORY → invalidation require_rerun
#                                                                 advisory in release-decision (E10 blocks)
#    6   Auditor High+score95 → blocked                 RETIRED  → the whole-delivery round (final_review input) replaced the auditor
#    7   score60 no blockers → proceed+warning          ADAPTED  → healthy/advisory positive control
#    8   Curator APPROVED → rejected                    ADAPTED  → schema/enum validation (Step 3 suite)
#   9-10 CP6 prod/docs                                  SKIP-REF → fast-profile follow-up (D6)
#   11   stale HEAD → no MERGE                          SIMULATED→ "--at-head stale …" (head_match=false)
#   12   forced waiver visible, no PASS rewrite         ADAPTED  → "decision: --force … writes a valid waiver"
#  13-16 profile/IR/lens cadence                        N/A      → C2/E3 review-profile hooks (E10 promotion)
#   17   unit pass, prod wiring fail → blocked          ADAPTED  → semantic-review-final presence/stale-blocking (E9); content-verdict blocking deferred to E10
#   18   auto-merge eligible EPIC w/o PM brief          NEW (D11)→ "d11 [18] …" (pm_brief_status seam)
#  19-22 Reporter / Simplifier at the boundary          RETIRED  → both left the flow (P096)
#   23   stale evidence pack (--at-head mismatch)       NEW (D11)→ "d11 [23] …" (evs=fail, NOT unverifiable)
#  24-25 waiver on / pair of Reporter+Simplifier blockers RETIRED → "F4(d)" keeps waived != pass on a required input
#  26-27 divergence between the old and the new decision  RETIRED  → the dual run left with the legacy verdict it compared against (P096)
#
# The 5 N/A / SKIP-REF disposition rows (3, 4, 9-10, 13-16) are intentionally NOT expressed as
# C4 aggregator tests — they are enforced by other control layers and referenced here (and row
# by row in the table above) so no Doc-1 fixture is silently dropped:
#   1. row 3      (missing behavior_trace)   → N/A: C2/E5 semantic-review owns its own hooks
#   2. row 4      (CP3 fail → fix loop)       → SKIP-REF: C2/FSM CP3 checkpoint (aid-fsm.sh cp3_integration_precond)
#   3. row 9      (CP6 prod)                  → SKIP-REF: CP6 fast-profile follow-up, deferred per D6
#   4. row 10     (CP6 docs)                  → SKIP-REF: CP6 fast-profile follow-up, deferred per D6
#   5. rows 13-16 (profile/IR/lens cadence)   → N/A: C2/E3 review-profile hooks; blocking promotion → E10
# ═══════════════════════════════════════════════════════════════════════════════

load test-helpers.bash

setup() {
  export TZ=UTC
  export AID_TEST_MODE=1
  # Test-cost fix (2026-07-11): stub the real aid-evidence-verify.sh --at-head subprocess
  # (~9s/call against a real fixture) to a fixed "pass" for every test by default. The 4
  # tests that specifically exercise verification's OWN behavior (real healthy pass, real
  # dirty-tree fail, real stale-HEAD fail x2) `unset` this locally before calling _run_agg so
  # they still drive the genuine subprocess end-to-end. See aid-release-policy.sh's
  # run_verification_input() for the seam this activates (double-gated on AID_TEST_MODE).
  export AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"   # .../plugins/aid-orchestrator
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  SCRIPTS="$PLUGIN_ROOT/scripts"
  AGG="$SCRIPTS/aid-release-policy.sh"
  FSM="$SCRIPTS/aid-fsm.sh"
  VALIDATE="$SCRIPTS/aid-protocol-validate.sh"
  PMBRIEF="$SCRIPTS/aid-pm-brief.sh"
  FIX="$SCRIPTS/tests/fixtures/release-policy"

  EPIC="E-059-2_2"
  RUN="R-E059-2_2-1"
  PLANREF_ID="P059-release-policy"     # basename(plan_ref) minus .md

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  PROJ="$TEST_TMPDIR/project"
  EVID="$PROJ/.aid-o/work/evidence/$EPIC/$RUN"
  C0="$PROJ/.aid-o/work/evidence/$PLANREF_ID/c0"
  # Plan review is read from the plan's sealed generation authority (P093).
  AUTH="$PROJ/.aid-o/work/evidence/$PLANREF_ID/generation/generation-authority.json"
  CFG="$PROJ/.aid-o/config"
  OUT="$EVID/release-decision.json"
  HEAD_SHA=""
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# ─── helpers ─────────────────────────────────────────────────────────────────

# .gitignore .aid-o/, commit a tracked file; echoes HEAD sha.
_git_init_commit() {
  echo ".aid-o/" > "$PROJ/.gitignore"
  echo "init" > "$PROJ/README.md"
  git init -q "$PROJ"
  git -C "$PROJ" config user.email test@test.local
  git -C "$PROJ" config user.name Test
  git -C "$PROJ" add .gitignore README.md
  git -C "$PROJ" commit -q -m init
  git -C "$PROJ" rev-parse HEAD
}

# _rewrite_head <file> <sha> — set .revision.head_sha in-place (v2 artifacts).
_rewrite_head() {
  local f="$1" h="$2" tmp
  tmp="$(mktemp)"
  jq --arg h "$h" '.revision.head_sha = $h' "$f" > "$tmp" && mv "$tmp" "$f"
}

# _cp_head <src> <dst> — copy a v2 fixture and align its head_sha with HEAD_SHA.
_cp_head() { cp "$1" "$2"; _rewrite_head "$2" "$HEAD_SHA"; }

# Full release_ready:true layout. Sets HEAD_SHA.
_build_healthy() {
  mkdir -p "$EVID/gates" "$C0" "$CFG"
  # Fixture run-evidence artifacts live under fixtures/release-policy/pack/ (NOT evidence/ —
  # .gitignore line 30 `evidence/` would silently untrack them, the same class of trap as .aid-o/).
  cp "$FIX/pack/review-profile.json"        "$EVID/review-profile.json"
  cp "$FIX/pack/semantic-review-final.json" "$EVID/semantic-review-final.json"
  cp "$FIX/pack/acceptance-evidence.json"   "$EVID/acceptance-evidence.json"
  cp "$FIX/pack/gates_report.json"          "$EVID/gates_report.json"
  cp "$FIX/pack/epic_input.md"              "$EVID/epic_input.md"
  cp "$FIX/config/execution.yaml"               "$CFG/execution.yaml"
  cp "$FIX/config/permissions-auto.yaml"        "$CFG/permissions.yaml"
  HEAD_SHA="$(_git_init_commit)"
  local f
  for f in "$EVID/review-profile.json" "$EVID/semantic-review-final.json" "$EVID/acceptance-evidence.json"; do
    _rewrite_head "$f" "$HEAD_SHA"
  done
  mkdir -p "$(dirname "$AUTH")"
  jq -n --arg h "$HEAD_SHA" '{cp1: {verdict: "pass"}, target_head: $h}' > "$AUTH"
  # the EPIC's own whole-diff round (cp3), closed and passed at HEAD: the final_review input in EPIC mode
  mkdir -p "$EVID/cp3"; jq -n --arg h "$HEAD_SHA" '{verdict: "pass", head_sha: $h, rounds: []}' > "$EVID/cp3/rounds.json"
}

# Run the aggregator to $OUT (bats `run` sets $status/$output).
_run_agg() {
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" AID_PROJECT_ROOT="$PROJ" \
    bash "$AGG" "$EPIC" "$RUN" --out "$OUT"
}

_rd() { jq -r "$1" "$OUT"; }
_has_blocker() { jq -e --arg id "$1" '.release_decision.blockers | any(.input_id == $id)' "$OUT" >/dev/null; }
_input_verdict() { jq -r --arg id "$1" '.release_decision.inputs[] | select(.id==$id) | .verdict' "$OUT"; }
# _input_head_match <id> — echoes the head_match value (true|false|unknown; jq -r strips the
# JSON quotes off "unknown"). E-060-2_2 Step 8.
_input_head_match() { jq -r --arg id "$1" '.release_decision.inputs[] | select(.id==$id) | .head_match' "$OUT"; }

# ─── healthy ─────────────────────────────────────────────────────────────────

@test "healthy fixture (real git-init) → release_ready:true, merge_mode auto, evidence pass" {
  # REAL E2E anchor (not stubbed) — proves the actual aid-evidence-verify.sh --at-head
  # subprocess genuinely returns pass for a well-formed healthy fixture.
  unset AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB
  _build_healthy
  _run_agg
  [ "$status" -eq 0 ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.merge_mode')" == "auto" ]
  [ "$(_rd '.release_decision.evidence_verified_at_head')" == "true" ]
  [ "$(_rd '.release_decision.evidence_verification_status')" == "pass" ]
  [ "$(_rd '.release_decision.blockers | length')" -eq 0 ]
  [ "$(_rd '.release_decision.profile_hash_freshness')" == "evaluated" ]
  [ "$(_rd '.release_decision.pm_brief_required')" == "true" ]
  [ "$(_rd '.release_decision.pm_brief_status')" == "pending" ]
}

@test "healthy fixture with AID's own tracked counter.yaml modified → verification_report pass, no blocker" {
  unset AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB
  _build_healthy
  # A project that tracks its counter: AID rewrote it during the run. amend keeps HEAD_SHA's artifacts honest.
  echo "plan: 1" > "$CFG/counter.yaml"; git -C "$PROJ" add -f .aid-o/config/counter.yaml
  git -C "$PROJ" commit -q --amend --no-edit; HEAD_SHA="$(git -C "$PROJ" rev-parse HEAD)"
  local f; for f in "$EVID"/review-profile.json "$EVID"/semantic-review-final.json "$EVID"/acceptance-evidence.json; do _rewrite_head "$f" "$HEAD_SHA"; done
  jq --arg h "$HEAD_SHA" '.target_head = $h' "$AUTH" > "$AUTH.t" && mv "$AUTH.t" "$AUTH"
  echo "plan: 2" > "$CFG/counter.yaml"
  _run_agg
  [ "$(_input_verdict verification_report)" == "pass" ]
  ! _has_blocker verification_report
}

@test "healthy output validates against the Step-3 release_decision schema (exit 0)" {
  _build_healthy
  _run_agg
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$OUT"
  [ "$status" -eq 0 ]
}

# ─── parametrized removal of each of the 7 REQUIRED inputs → blocked ──────────

@test "REQUIRED removed: review-profile → release_ready:false + blocker review_profile" {
  _build_healthy; rm -f "$EVID/review-profile.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker review_profile
  [ "$(_input_verdict review_profile)" == "blocked" ]
}

@test "REQUIRED removed: semantic-review-final → release_ready:false + blocker semantic_review_final" {
  _build_healthy; rm -f "$EVID/semantic-review-final.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker semantic_review_final
}

@test "REQUIRED removed: acceptance-evidence → release_ready:false + blocker acceptance_evidence" {
  _build_healthy; rm -f "$EVID/acceptance-evidence.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker acceptance_evidence
}

@test "REQUIRED removed: gates_report (root + gates/ both absent) → blocker gates_report" {
  _build_healthy; rm -f "$EVID/gates_report.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker gates_report
}

@test "REQUIRED removed: plan-review → release_ready:false + blocker plan_review" {
  _build_healthy; rm -f "$AUTH"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker plan_review
}

@test "REQUIRED broken: verification (dirty tree) → false + blocker verification_report + evs fail" {
  # REAL E2E anchor (not stubbed) — proves the actual subprocess detects a dirty tree.
  unset AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB
  _build_healthy
  echo "dirty" >> "$PROJ/README.md"        # a modified TRACKED file → git_clean fail (untracked files are not dirt)
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker verification_report
  [ "$(_rd '.release_decision.evidence_verification_status')" == "fail" ]
}

# ─── REGRESSION: empty/whitespace-only REQUIRED inputs (fail-closed, jq 1.6 edge case) ─

@test "REGRESSION: acceptance-evidence EMPTY (0-byte) → release_ready:false + blocker" {
  _build_healthy
  : > "$EVID/acceptance-evidence.json"    # truncate to 0 bytes
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker acceptance_evidence
  [ "$(_input_verdict acceptance_evidence)" == "blocked" ]
}

@test "REGRESSION: acceptance-evidence WHITESPACE-ONLY → release_ready:false + blocker" {
  _build_healthy
  printf '\n' > "$EVID/acceptance-evidence.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker acceptance_evidence
  [ "$(_input_verdict acceptance_evidence)" == "blocked" ]
}

@test "REGRESSION: healthy fixture still passes with fix (no over-rejection)" {
  _build_healthy
  _run_agg
  [ "$status" -eq 0 ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.blockers | length')" -eq 0 ]
}

# ─── plan-review hop ─────────────────────────────────────────────────────────

@test "plan-review hop: healthy plan_review verdict pass, reason cites resolved planref path" {
  _build_healthy
  _run_agg
  [ "$(_input_verdict plan_review)" == "pass" ]
  jq -e --arg id "plan_review" '.release_decision.inputs[] | select(.id==$id) | .reason | test("P059-release-policy/generation")' "$OUT" >/dev/null
}

@test "plan-review hop is FOLLOWED: wrong plan_ref → plan-review not found → blocked" {
  _build_healthy
  # Repoint epic_input.md plan_ref at a plan with no sealed generation authority.
  printf -- '---\nstatus: active\nplan_ref: .aid-o/plans/P999-nonexistent.md\n---\n# EPIC\n' > "$EVID/epic_input.md"
  _run_agg
  [ "$(_input_verdict plan_review)" == "blocked" ]
  _has_blocker plan_review
}

# ─── gates_report fallback ───────────────────────────────────────────────────

@test "gates_report gates/ fallback: root missing, gates/gates_report.json present → pass" {
  _build_healthy
  mkdir -p "$EVID/gates"
  mv "$EVID/gates_report.json" "$EVID/gates/gates_report.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_input_verdict gates_report)" == "pass" ]
}

# ─── --at-head stale ─────────────────────────────────────────────────────────

@test "--at-head stale (pack_head reachable but != HEAD) → evah false + evs fail + blocked" {
  # REAL E2E anchor (not stubbed) — proves the actual subprocess detects a stale HEAD.
  unset AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB
  _build_healthy
  echo "v2" >> "$PROJ/README.md"
  git -C "$PROJ" add README.md
  git -C "$PROJ" commit -q -m second      # HEAD advances past pack_head
  _run_agg
  [ "$(_rd '.release_decision.evidence_verified_at_head')" == "false" ]
  [ "$(_rd '.release_decision.evidence_verification_status')" == "fail" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker verification_report
}

# ─── merge_mode ×3 + fail-closed ─────────────────────────────────────────────

@test "merge_mode: autonomous_mode true + release_ready → auto" {
  _build_healthy   # permissions-auto.yaml
  _run_agg
  [ "$(_rd '.release_decision.merge_mode')" == "auto" ]
}

@test "merge_mode: autonomous_mode false + release_ready → manual" {
  _build_healthy
  cp "$FIX/config/permissions-manual.yaml" "$CFG/permissions.yaml"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.merge_mode')" == "manual" ]
}

@test "merge_mode: not release_ready → blocked (regardless of autonomous_mode)" {
  _build_healthy
  rm -f "$EVID/review-profile.json"    # force a blocker
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  [ "$(_rd '.release_decision.merge_mode')" == "blocked" ]
}

@test "merge_mode fail-closed: permissions.yaml missing → manual" {
  _build_healthy
  rm -f "$CFG/permissions.yaml"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.merge_mode')" == "manual" ]
}

@test "merge_mode fail-closed: preset-model permissions.yaml (no autonomous_mode key) → manual" {
  _build_healthy
  cp "$FIX/config/permissions-preset.yaml" "$CFG/permissions.yaml"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.merge_mode')" == "manual" ]
}

# ─── delivered_summary_ref resolution ────────────────────────────────────────

@test "delivered_summary_ref: epic-summary.md present → resolves to its path" {
  _build_healthy
  echo "# summary" > "$EVID/epic-summary.md"
  _run_agg
  [ "$(_rd '.release_decision.delivered_summary_ref')" == ".aid-o/work/evidence/$EPIC/$RUN/epic-summary.md" ]
}

@test "delivered_summary_ref: only final_report.md → resolves to final_report.md" {
  _build_healthy
  echo "# final" > "$EVID/final_report.md"
  _run_agg
  [ "$(_rd '.release_decision.delivered_summary_ref')" == ".aid-o/work/evidence/$EPIC/$RUN/final_report.md" ]
}

@test "delivered_summary_ref: neither present → null" {
  _build_healthy
  _run_agg
  [ "$(_rd '.release_decision.delivered_summary_ref')" == "null" ]
}

# ─── determinism ─────────────────────────────────────────────────────────────

@test "determinism: two runs → jq del(.created_at) payloads identical" {
  _build_healthy
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" AID_PROJECT_ROOT="$PROJ" bash "$AGG" "$EPIC" "$RUN" --out "$EVID/rd1.json"
  [ "$status" -eq 0 ]
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" AID_PROJECT_ROOT="$PROJ" bash "$AGG" "$EPIC" "$RUN" --out "$EVID/rd2.json"
  [ "$status" -eq 0 ]
  a="$(jq -S 'del(.created_at)' "$EVID/rd1.json")"
  b="$(jq -S 'del(.created_at)' "$EVID/rd2.json")"
  [ "$a" == "$b" ]
  # subject_hash is derived from the payload only → stable across runs.
  [ "$(jq -r '.subject.subject_hash' "$EVID/rd1.json")" == "$(jq -r '.subject.subject_hash' "$EVID/rd2.json")" ]
}

@test "every release-policy fixture file is git-tracked (no .aid-o/ gitignore trap)" {
  local f untracked=0
  while IFS= read -r -d '' f; do
    if ! git -C "$PLUGIN_ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      echo "UNTRACKED FIXTURE: $f"
      untracked=1
    fi
  done < <(find "$FIX" -type f -print0)
  [ "$untracked" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# The release decision inside done-advance + preempted telemetry + force waiver.
#
# State is built INLINE (not under fixtures/release-policy/dual-*/): new fixture
# FILES would fail the "every fixture is git-tracked" test above until committed,
# and this task's git guard forbids staging/committing. Inline heredocs are the
# self-contained equivalent (same convention as test-tiered-severity.bats).
# ═══════════════════════════════════════════════════════════════════════════════

# Builds a done-advance review→release state that passes ALL legacy checks
# (agent_tool dispatch → provenance skipped; no check-severity.yaml → all advisory)
# but has NO C4 evidence pack, so the aggregator returns release_ready=false and
# the dual-run diverges from the legacy verdict (match=false).
_fsm_setup_legacy_green() {
  mkdir -p "$EVID/gates" "$CFG" "$PROJ/.aid-o/tasks" "$PROJ/.aid-o/work"
  touch "$PROJ/.aid-o/work/audit-log.jsonl"
  cat > "$CFG/plugin.yaml" <<EOF
plugin_path: "$PLUGIN_ROOT"
dispatch_mode: agent_tool
EOF
  touch "$CFG/execution.yaml"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-07-09T00:00:00Z","_command_log":[]}\n' \
    > "$EVID/gates/gates_report.json"
  : > "$EVID/timeline.jsonl"
  cat > "$EVID/fsm-state.yaml" <<EOF
epic_id: ${EPIC}
run_id: ${RUN}
branch: task/${EPIC}/main
state: DONE
done_phase: review
created_at: 2026-07-09T10:00:00Z
total_steps: 3
current_step: 3
pm_decision: merge
EOF
  # Real git repo (.aid-o gitignored → evidence never dirties the tree; mirrors _build_healthy).
  echo ".aid-o/" > "$PROJ/.gitignore"
  echo "init" > "$PROJ/README.md"
  git init -q -b main "$PROJ"
  git -C "$PROJ" config user.email test@test.local
  git -C "$PROJ" config user.name Test
  git -C "$PROJ" add .gitignore README.md
  git -C "$PROJ" commit -q -m init
  cd "$PROJ"
  # P094: done-advance re-checks the EPIC review round at HEAD.
  aid_fixture_seed_step_review "$EVID" cp3 "" pass "$(git -C "$PROJ" rev-parse HEAD)"
}

@test "decision: done-advance records release_decision (observe → advances) with head_sha and the verdict" {
  _fsm_setup_legacy_green
  local head; head="$(git -C "$PROJ" rev-parse HEAD)"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 0 ]                                    # observe: a not-ready decision does not block
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"
  local ev; ev="$(grep '"event":"release_decision"' "$EVID/timeline.jsonl" | tail -1)"
  [ "$(echo "$ev" | jq -r '.head_sha')" == "$head" ]
  [ "$(echo "$ev" | jq -r '.release_ready')" == "false" ] # the evidence pack is absent
  [ "$(echo "$ev" | jq -r '.enforcement')" == "observe" ]
}

@test "decision: RELEASE_DECISION_POLICY=blocking → release_ready=false blocks the transition" {
  _fsm_setup_legacy_green
  local pol="$TEST_TMPDIR/rdp-blocking.yaml"
  printf 'version: 1\nenforcement: blocking\n' > "$pol"
  run env RELEASE_DECISION_POLICY="$pol" bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -ne 0 ]
  grep -q '^done_phase: review' "$EVID/fsm-state.yaml"   # transition did NOT advance
  [ "$(grep '"event":"release_decision"' "$EVID/timeline.jsonl" | tail -1 | jq -r '.enforcement')" == "blocking" ]
}

@test "decision: crash-guard — a broken aggregator is logged and done-advance STILL passes (set -e safe)" {
  _fsm_setup_legacy_green
  local broken="$TEST_TMPDIR/broken-aggregator.sh"
  printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$broken"
  run env AID_RELEASE_POLICY_BIN="$broken" bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 0 ]                                    # a crash MUST NOT abort done-advance
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"
  local ev; ev="$(grep '"event":"release_decision"' "$EVID/timeline.jsonl" | tail -1)"
  [ "$(echo "$ev" | jq -r '.exit_code')" == "1" ]
  [ "$(echo "$ev" | jq -r '.release_ready')" == "unknown" ]
}

@test "decision: --force skips the release decision (NO release_decision event) and writes a valid waiver" {
  _fsm_setup_legacy_green
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml" \
    --force --reason "PM approved release despite absent C4 evidence pack (release decision test fixture)"
  [ "$status" -eq 0 ]
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"
  # force bypasses the whole gauntlet → the release decision is structurally unreached.
  ! grep -q '"event":"release_decision"' "$EVID/timeline.jsonl"
  # a protocol-v2 waiver artifact was written and validates against the Step-3 schema.
  local wv; wv="$(ls "$EVID"/waiver-*.json 2>/dev/null | head -1)"
  [ -n "$wv" ]
  [ "$(jq -r '.artifact_type' "$wv")" == "waiver" ]
  [ "$(jq -r '.waiver.visible' "$wv")" == "true" ]
  [ "$(jq -r '.waiver.reason | length >= 20' "$wv")" == "true" ]
  run bash "$VALIDATE" "$wv"
  [ "$status" -eq 0 ]
}

@test "dual: force-written waiver is surfaced by the aggregator in waivers_applied[]" {
  _fsm_setup_legacy_green
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml" \
    --force --reason "PM approved release despite absent C4 evidence pack (release decision test fixture)"
  [ "$status" -eq 0 ]
  local wv wvbase
  wv="$(ls "$EVID"/waiver-*.json 2>/dev/null | head -1)"
  [ -n "$wv" ]
  wvbase="$(basename "$wv")"
  # A follow-up aggregator run globs waiver-*.json → waivers_applied[] (Waived != pass).
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" AID_PROJECT_ROOT="$PROJ" bash "$AGG" "$EPIC" "$RUN" --out "$OUT"
  [ "$status" -eq 0 ]
  jq -e --arg w "$wvbase" '.release_decision.waivers_applied | index($w)' "$OUT" >/dev/null
}

# ─── release_policy_preempted (hard-exits that never reach the C4 slot) ────────

# ═══════════════════════════════════════════════════════════════════════════════
# E-059-2_2 Step 7 — Doc-1 §13.2 D11 negative fixtures (rows 18-27).
#
# These exercise the D11 state model the aggregator (Step 4) + pm-brief (Step 6) added:
# pm_brief_required/pm_brief_status,
# evidence_verification_status fail-vs-unverifiable, and waived != pass through the brief.
# ═══════════════════════════════════════════════════════════════════════════════

@test "d11 [18]: auto-merge-eligible + PM-brief write fails (--out-dir seam) → pm_brief_status failed, NEVER silently generated; merge_mode stays auto (informative)" {
  _build_healthy
  _run_agg
  [ "$status" -eq 0 ]
  # C4 ALWAYS requires a brief and starts pending — even for an auto-merge-ready decision.
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_rd '.release_decision.merge_mode')" == "auto" ]
  [ "$(_rd '.release_decision.pm_brief_required')" == "true" ]
  [ "$(_rd '.release_decision.pm_brief_status')" == "pending" ]
  # Force the brief write to fail: point --out-dir under a path whose parent is a FILE, so
  # mkdir -p + the redirect both fail regardless of uid. Patch-back targets the (writable)
  # evidence dir → pm_brief_status flips to failed, exit 6.
  touch "$TEST_TMPDIR/notadir"
  run bash "$PMBRIEF" "$EVID" --out-dir "$TEST_TMPDIR/notadir/sub"
  [ "$status" -eq 6 ]
  # Re-read the decision: the field moved to failed, NEVER silently to generated.
  [ "$(_rd '.release_decision.pm_brief_status')" == "failed" ]
  [ "$(_rd '.release_decision.pm_brief_required')" == "true" ]
  # merge_mode is informative, not enforcement — it stays auto despite the un-generated brief.
  [ "$(_rd '.release_decision.merge_mode')" == "auto" ]
}

@test "d11 [23]: stale evidence pack (--at-head mismatch) → evidence_verified_at_head=false + evidence_verification_status=fail (NOT unverifiable) → release_ready=false" {
  # REAL E2E anchor (not stubbed) — CP1 L1-B3 regression: proves the actual subprocess
  # maps a stale HEAD to fail, never unverifiable.
  unset AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB
  _build_healthy
  echo "v2" >> "$PROJ/README.md"
  git -C "$PROJ" add README.md
  git -C "$PROJ" commit -q -m second      # HEAD advances past pack_head → --at-head mismatch
  _run_agg
  [ "$(_rd '.release_decision.evidence_verified_at_head')" == "false" ]
  # CP1 L1-B3: --at-head mismatch (like git-dirty) is a per-check FAIL, never unverifiable.
  [ "$(_rd '.release_decision.evidence_verification_status')" == "fail" ]
  [ "$(_rd '.release_decision.evidence_verification_status')" != "unverifiable" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker verification_report
}

# ═══════════════════════════════════════════════════════════════════════════════
# E-060-2_2 Step 8 — at-HEAD staleness must not let a stale artefact look usable.
# F1: the class the E-059-2_2 merge review actually hit (head_match never blocked).
# 9 F4 scenarios (a)-(i). Fixtures for the markdown-provenance and gates-stamp cases
# are built INLINE (heredoc/append) — new fixture FILES would fail the "every fixture
# is git-tracked" test until committed, and this task's git guard forbids committing.
# ═══════════════════════════════════════════════════════════════════════════════

# F4(a) — blocking red-green on an OUT-OF-PACK input (plan_review). evidence-verify does NOT
# scan the plan c0 dir, so BEFORE Step 8 a stale plan-review is a genuine red (release_ready=true,
# plan_review verdict=pass). The MANDATORY assert is the PER-INPUT row, never just release_ready.
@test "F4(a) plan_review out-of-pack stale sha → per-input verdict blocked + blocker (NOT just release_ready)" {
  _build_healthy
  # A non-ancestor (foreign/rebased) sha in the GITIGNORED plan-review artifact.
  jq '.target_head = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"' "$AUTH" > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
  _run_agg
  [ "$status" -eq 0 ]
  # PER-INPUT assert (release_ready alone would mask the out-of-pack detection).
  [ "$(_input_verdict plan_review)" == "blocked" ]
  [ "$(_input_head_match plan_review)" == "false" ]
  _has_blocker plan_review
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
}

# F4(d) — a waiver mapped to a blocked input DOCUMENTS but never unblocks: the inputs[] row flips
# blocked→waived, the blocker line STAYS, the D11 *_status stays, release_ready stays false.
@test "F4(d) waiver mapped to a blocked input → row waived, blocker STAYS, release_ready false" {
  _build_healthy
  rm -f "$EVID/review-profile.json"                      # review_profile → missing → blocked
  # The aggregator's waiver mapping reads only .waiver.waived_check (+ the filename), so the fixture
  # carries no v2 envelope — that also keeps it out of aid-evidence-verify's v2-artifact scan, so
  # the review_profile blocker is the SOLE blocker and this isolates the waiver-never-unblocks semantics.
  cat > "$EVID/waiver-review_profile.json" <<'EOF'
{"waiver":{"waived_check":"review_profile","reason":"PM waived the missing review profile for this release (F4d fixture).","waived_by":"pm","waived_at":"2026-07-10T00:00:00Z","scope":"run","visible":true}}
EOF
  _run_agg
  [ "$(_input_verdict review_profile)" == "waived" ]     # row blocked→waived
  _has_blocker review_profile                            # blocker line STAYS
  [ "$(_rd '.release_decision.release_ready')" == "false" ]   # waiver NEVER unblocks
  [ "$(jq -r '.release_decision.waiver_findings[]|select(.waiver=="waiver-review_profile.json")|.finding' "$OUT")" == "applied" ]
}

# F4(e) — a waiver targeting a NON-blocked input is an orphan_waiver; verdicts unchanged.
@test "F4(e) waiver on a non-blocked input → orphan_waiver finding, verdicts unchanged" {
  _build_healthy                                         # gates_report is pass (healthy)
  # Envelope-less waiver (see F4(d)): invisible to evidence-verify, mapped by the aggregator → the
  # release stays healthy so this isolates "orphan waiver changes nothing".
  cat > "$EVID/waiver-gates_report.json" <<'EOF'
{"waiver":{"waived_check":"gates_report","reason":"PM waiver targeting a non-blocked input (F4e orphan fixture).","waived_by":"pm","waived_at":"2026-07-10T00:00:00Z","scope":"run","visible":true}}
EOF
  _run_agg
  [ "$(_input_verdict gates_report)" == "pass" ]         # verdict UNCHANGED
  [ "$(jq -r '.release_decision.waiver_findings[]|select(.waiver=="waiver-gates_report.json")|.finding' "$OUT")" == "orphan_waiver" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
}

# F4(f) — plan_review ANCESTRY basis (gitignored plan path, like the dogfood). A recorded head_sha
# that is an ancestor of HEAD stays head_match true even after HEAD moves on with release commits;
# a non-ancestor sha → false. A git-tracked fixture would mask exactly the L1-B3 bug.
@test "F4(f) plan_review ancestor sha → head_match true after HEAD moves (release commits); non-ancestor → false blocked" {
  _build_healthy                                         # plan-review head_sha == reviewed HEAD_SHA
  echo "bump" >> "$PROJ/README.md"; git -C "$PROJ" add README.md; git -C "$PROJ" commit -q -m "release bump"
  _run_agg
  [ "$(_input_head_match plan_review)" == "true" ]       # ancestor → true even after HEAD moved
  [ "$(_input_verdict plan_review)" == "pass" ]
  # Foreign / rebased lineage (non-ancestor) → false → blocked.
  jq '.target_head = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"' "$AUTH" > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
  _run_agg
  [ "$(_input_head_match plan_review)" == "false" ]
  [ "$(_input_verdict plan_review)" == "blocked" ]
  _has_blocker plan_review
}

# F4(g) — gates_report WITH a stamped stale head_sha (Step-2 runner stamp gone stale) → direct
# compare false → blocked (out-of-pack net-new blocker).
@test "F4(g) gates_report stamped with a stale head_sha → head_match false → blocked + blocker" {
  _build_healthy
  local tmp; tmp="$(mktemp)"
  jq '.revision = {head_sha:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", head_is_current:false, freshness:"stale"}' \
    "$EVID/gates_report.json" > "$tmp" && mv "$tmp" "$EVID/gates_report.json"
  _run_agg
  [ "$(_input_head_match gates_report)" == "false" ]
  [ "$(_input_verdict gates_report)" == "blocked" ]
  _has_blocker gates_report
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
}

# F4(h) — a legacy gates_report with NO revision stamp → unknown → never blocks (uncomputable basis
# is a declared unknown, not a silent true, but it does not manufacture a block either).
@test "F4(h) gates_report without a revision stamp (legacy) → head_match unknown, never blocks" {
  _build_healthy                                         # fixture gates_report.json has no revision
  _run_agg
  [ "$(_input_head_match gates_report)" == "unknown" ]
  [ "$(_input_verdict gates_report)" == "pass" ]
  ! _has_blocker gates_report
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
}

# F4(i) — positive provenance fixture: a markdown report WITH a `Head:` line → head_match computed
# true/false (never unknown), end-to-end through the aid-release-policy.sh parsing.
