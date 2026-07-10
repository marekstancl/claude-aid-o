#!/usr/bin/env bats
# test-release-policy.bats — aid-release-policy.sh (C4 release aggregator, E-059-2_2 Step 4)
# plus the B1 shared-lib (lib/aid-review-signals.sh) cross-check against the FSM.
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
#    1   missing delivery-gate → rejected               ADAPTED  → "REQUIRED removed: delivery-gate …"
#    2   nested-missing fields → rejected               ADAPTED  → protocol field checks (Step 3 suite)
#    3   missing behavior_trace                         N/A      → C2/E5 owns its own hooks (not C4)
#    4   CP3 fail → fix loop not GATES                  SKIP-REF → C2/FSM checkpoint, outside C4
#    5   CP4 pass w/o rerun → CP5 rejected              ADAPTED-ADVISORY → invalidation require_rerun
#                                                                 advisory in release-decision (E10 blocks)
#    6   Auditor High+score95 → blocked                 ADAPTED  → "profile-gating ACTIVE … audit … blocked"
#    7   score60 no blockers → proceed+warning          ADAPTED  → healthy/advisory positive control
#    8   Curator APPROVED → rejected                    ADAPTED  → schema/enum validation (Step 3 suite)
#   9-10 CP6 prod/docs                                  SKIP-REF → fast-profile follow-up (D6)
#   11   stale HEAD → no MERGE                          SIMULATED→ "--at-head stale …" (head_match=false)
#   12   forced waiver visible, no PASS rewrite         ADAPTED  → "dual: … writes a valid waiver" (Step 5)
#  13-16 profile/IR/lens cadence                        N/A      → C2/E3 review-profile hooks (E10 promotion)
#   17   unit pass, prod wiring fail → blocked          ADAPTED  → semantic-review-final presence/stale-blocking (E9); content-verdict blocking deferred to E10
#   18   auto-merge eligible EPIC w/o PM brief          NEW (D11)→ "d11 [18] …" (pm_brief_status seam)
#   19   per-EPIC release without Reporter              NEW (D11)→ "d11 [19] …" (not_applicable)
#   20   plan-boundary w/o Reporter, NOT disabled       NEW (D11)→ "d11 [20] …" (missing → false)
#   21   per-EPIC release without Simplifier            NEW (D11)→ "d11 [21] …" (not_applicable)
#   22   plan-boundary w/o Simplifier, NOT disabled     NEW (D11)→ "d11 [22] …" (missing → false)
#   23   stale evidence pack (--at-head mismatch)       NEW (D11)→ "d11 [23] …" (evs=fail, NOT unverifiable)
#   24   force/waiver on Reporter/Simplifier blocker    NEW (D11)→ "d11 [24] waiver …" (waived != pass, via brief)
#   25   plan-boundary w/o Reporter AND Simplifier      NEW (D11)→ "d11 [25] dual …" (both missing → mixed)
#   26   review_profile as the SOLE C4 blocker          COVERED  → Step-5 "dual: … required_input (sole review_profile — DOMINANT)"
#   27   C4 more lenient than legacy / same-cat multi   COVERED  → Step-5 "dual: … c4_permissive" + "dual: … mixed"
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

setup() {
  export TZ=UTC
  export AID_TEST_MODE=1
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
  REPORT_PLAN_ID="P059"                # P<num> from epic_id → delivery-report filename

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  PROJ="$TEST_TMPDIR/project"
  EVID="$PROJ/.aid-o/work/evidence/$EPIC/$RUN"
  C0="$PROJ/.aid-o/work/evidence/$PLANREF_ID/c0"
  CFG="$PROJ/.aid-o/config"
  REPORTS="$PROJ/.aid-o/reports"
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

# Full release_ready:true layout (off-boundary reporter/simplifier). Sets HEAD_SHA.
_build_healthy() {
  mkdir -p "$EVID/gates" "$C0" "$CFG" "$REPORTS"
  # Fixture run-evidence artifacts live under fixtures/release-policy/pack/ (NOT evidence/ —
  # .gitignore line 30 `evidence/` would silently untrack them, the same class of trap as .aid-o/).
  cp "$FIX/pack/review-profile.json"        "$EVID/review-profile.json"
  cp "$FIX/pack/delivery-gate.json"         "$EVID/delivery-gate.json"
  cp "$FIX/pack/semantic-review-final.json" "$EVID/semantic-review-final.json"
  cp "$FIX/pack/acceptance-evidence.json"   "$EVID/acceptance-evidence.json"
  cp "$FIX/pack/gates_report.json"          "$EVID/gates_report.json"
  cp "$FIX/pack/epic_input.md"              "$EVID/epic_input.md"
  cp "$FIX/plan-review/plan-review.json"        "$C0/plan-review.json"
  cp "$FIX/config/execution.yaml"               "$CFG/execution.yaml"
  cp "$FIX/config/permissions-auto.yaml"        "$CFG/permissions.yaml"
  HEAD_SHA="$(_git_init_commit)"
  local f
  for f in "$EVID/review-profile.json" "$EVID/delivery-gate.json" \
           "$EVID/semantic-review-final.json" "$EVID/acceptance-evidence.json" \
           "$C0/plan-review.json"; do
    _rewrite_head "$f" "$HEAD_SHA"
  done
}

# On-boundary layout with BOTH reporter + simplifier VALID (each maps to pass).
_on_boundary_both_valid() {
  _build_healthy
  touch "$EVID/ca-review-complete"
  cp "$FIX/reports/P059-delivery-valid.md" "$REPORTS/${REPORT_PLAN_ID}-delivery.md"
  mkdir -p "$EVID/reporter"
  echo "smoke ok" > "$EVID/reporter/smoke.txt"
  cp "$FIX/simplifier/simplifier-report.md" "$EVID/simplifier-report.md"
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

@test "REQUIRED removed: delivery-gate → release_ready:false + blocker delivery_gate" {
  _build_healthy; rm -f "$EVID/delivery-gate.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker delivery_gate
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
  _build_healthy; rm -f "$C0/plan-review.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker plan_review
}

@test "REQUIRED broken: verification (dirty tree) → false + blocker verification_report + evs fail" {
  _build_healthy
  echo "dirty" > "$PROJ/untracked.txt"     # untracked, not under .aid-o → git_clean fail
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
  jq -e --arg id "plan_review" '.release_decision.inputs[] | select(.id==$id) | .reason | test("P059-release-policy/c0")' "$OUT" >/dev/null
}

@test "plan-review hop is FOLLOWED: wrong plan_ref → plan-review not found → blocked" {
  _build_healthy
  # Repoint epic_input.md plan_ref at a plan whose c0 evidence does not exist.
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

# ─── audit-report + curator-report profile-gating (symmetric) ────────────────

@test "profile-gating INACTIVE (risk low) + audit/curator missing → advisory, not required" {
  _build_healthy   # review-profile risk_profile=low → C3 gate inactive; no audit/curator files
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_input_verdict audit_report)" == "advisory" ]
  [ "$(_input_verdict curator_report)" == "advisory" ]
  ! _has_blocker audit_report
  ! _has_blocker curator_report
}

@test "profile-gating ACTIVE (risk high) + audit/curator missing → blocked (both)" {
  _build_healthy
  _cp_head "$FIX/c3/review-profile-high.json" "$EVID/review-profile.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker audit_report
  _has_blocker curator_report
  [ "$(_input_verdict audit_report)" == "blocked" ]
  [ "$(_input_verdict curator_report)" == "blocked" ]
}

@test "profile-gating ACTIVE (risk high) + audit/curator PRESENT → not blocked (release_ready true)" {
  _build_healthy
  _cp_head "$FIX/c3/review-profile-high.json" "$EVID/review-profile.json"
  _cp_head "$FIX/c3/audit-report.json"        "$EVID/audit-report.json"
  _cp_head "$FIX/c3/curator-report.json"      "$EVID/curator-report.json"
  _run_agg
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  [ "$(_input_verdict audit_report)" == "pass" ]
  [ "$(_input_verdict curator_report)" == "pass" ]
}

# ─── --at-head stale ─────────────────────────────────────────────────────────

@test "--at-head stale (pack_head reachable but != HEAD) → evah false + evs fail + blocked" {
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

# ─── Reporter CONDITIONAL ×4 ─────────────────────────────────────────────────

@test "reporter CONDITIONAL: off-boundary (no marker) → not_applicable, unaffected" {
  _build_healthy   # no ca-review-complete
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "not_applicable" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker reporter
}

@test "reporter CONDITIONAL: on-boundary + enabled + report missing → missing + blocker" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"   # simplifier stays valid → isolates reporter
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "missing" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker reporter
}

@test "reporter CONDITIONAL: on-boundary + reporter.enabled:false → disabled, unaffected" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"           # would be missing if enabled…
  cp "$FIX/config/execution-reporter-off.yaml" "$CFG/execution.yaml"   # …but disabled → N/A
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "disabled" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker reporter
}

@test "reporter CONDITIONAL: on-boundary + enabled + valid report → pass" {
  _on_boundary_both_valid
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "pass" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker reporter
}

@test "reporter CONDITIONAL: on-boundary + enabled + invalid _test_evidence → fail + blocker" {
  _on_boundary_both_valid
  cp "$FIX/reports/P059-delivery-invalid.md" "$REPORTS/${REPORT_PLAN_ID}-delivery.md"
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "fail" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker reporter
}

# ─── Simplifier CONDITIONAL ×4 ───────────────────────────────────────────────

@test "simplifier CONDITIONAL: off-boundary (no marker) → not_applicable, unaffected" {
  _build_healthy
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "not_applicable" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker simplifier
}

@test "simplifier CONDITIONAL: on-boundary + enabled + report missing → missing + blocker" {
  _on_boundary_both_valid
  rm -f "$EVID/simplifier-report.md"     # reporter stays valid → isolates simplifier
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "missing" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker simplifier
}

@test "simplifier CONDITIONAL: on-boundary + simplifier.enabled:false → disabled, unaffected" {
  _on_boundary_both_valid
  rm -f "$EVID/simplifier-report.md"
  cp "$FIX/config/execution-simplifier-off.yaml" "$CFG/execution.yaml"
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "disabled" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker simplifier
}

@test "simplifier CONDITIONAL: on-boundary + enabled + present report → pass" {
  _on_boundary_both_valid
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "pass" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker simplifier
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
  rm -f "$EVID/delivery-gate.json"     # force a blocker
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

# ─── B1: shared lib sourceable + FSM cross-check ─────────────────────────────

@test "B1: lib/aid-review-signals.sh sources standalone and both functions are callable" {
  source "$SCRIPTS/lib/aid-review-signals.sh"
  [ "$(type -t _aid_read_toggle)" == "function" ]
  [ "$(type -t _aid_validate_test_evidence)" == "function" ]
  # toggle: enabled default (missing file) and disabled path
  run _aid_read_toggle "$TEST_TMPDIR/does-not-exist.yaml" reporter
  [ "$status" -eq 0 ]
  printf 'reporter:\n  enabled: false\n' > "$TEST_TMPDIR/exec.yaml"
  run _aid_read_toggle "$TEST_TMPDIR/exec.yaml" reporter
  [ "$status" -eq 1 ]
}

@test "B1 cross-check (true substrate): aggregator lib result == fsm_eval internal (reporter/simplifier valid)" {
  _on_boundary_both_valid
  # aid-fsm.sh source shim — set positional params to a harmless dispatcher cmd (delivery-report.bats pattern).
  cat > "$EVID/fsm-state.yaml" <<EOF
epic_id: ${EPIC}
run_id: ${RUN}
branch: task/${EPIC}/main
state: GATES
created_at: 2026-07-09T10:00:00Z
current_step: 1
total_steps: 5
EOF
  set -- "verify-state" "$EVID/fsm-state.yaml"
  source "$SCRIPTS/aid-fsm.sh" >/dev/null

  # Reporter substrate: the aggregator calls _aid_validate_test_evidence on the SAME report
  # path (P<num>-delivery.md) that fsm_eval_delivery_report_present derives internally.
  local sub_valid fsm_deliv
  sub_valid="$(_aid_validate_test_evidence "$REPORTS/${REPORT_PLAN_ID}-delivery.md" "$EVID")"
  fsm_deliv="$(fsm_eval_delivery_report_present "$EPIC" "$EVID" "$PROJ")"
  [ "$sub_valid" == "true" ]
  [ "$fsm_deliv" == "true" ]              # fsm true-substrate agrees with the shared lib

  # Simplifier substrate: shared toggle + file existence (fsm_eval_simplifier_present uses both).
  local fsm_simp
  _aid_read_toggle "$CFG/execution.yaml" "simplifier"   # exit 0 = enabled (asserted via $?)
  [ "$?" -eq 0 ]
  fsm_simp="$(fsm_eval_simplifier_present "$EPIC" "$EVID" "$PROJ")"
  [ "$fsm_simp" == "true" ]

  # And the aggregator's 5-enum status is layered on that same substrate.
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "pass" ]
  [ "$(_rd '.release_decision.simplifier_status')" == "pass" ]
}

@test "B1 cross-check (false substrate): invalid _test_evidence → lib false == fsm false == aggregator fail" {
  _on_boundary_both_valid
  cp "$FIX/reports/P059-delivery-invalid.md" "$REPORTS/${REPORT_PLAN_ID}-delivery.md"
  cat > "$EVID/fsm-state.yaml" <<EOF
epic_id: ${EPIC}
run_id: ${RUN}
branch: task/${EPIC}/main
state: GATES
created_at: 2026-07-09T10:00:00Z
current_step: 1
total_steps: 5
EOF
  set -- "verify-state" "$EVID/fsm-state.yaml"
  source "$SCRIPTS/aid-fsm.sh" >/dev/null

  local sub_valid fsm_deliv
  sub_valid="$(_aid_validate_test_evidence "$REPORTS/${REPORT_PLAN_ID}-delivery.md" "$EVID")"
  fsm_deliv="$(fsm_eval_delivery_report_present "$EPIC" "$EVID" "$PROJ")"
  [ "$sub_valid" == "false" ]
  [ "$fsm_deliv" == "false" ]

  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "fail" ]
}

# ─── fixture hygiene ─────────────────────────────────────────────────────────

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
# E-059-2_2 Step 5 — C4 dual-run hook + preempted telemetry + force waiver.
#
# State is built INLINE (not under fixtures/release-policy/dual-*/): new fixture
# FILES would fail the "every fixture is git-tracked" test above until committed,
# and this task's git guard forbids staging/committing. Inline heredocs are the
# self-contained equivalent (same convention as test-tiered-severity.bats).
# ═══════════════════════════════════════════════════════════════════════════════

# ─── divergence_class taxonomy (pure-function unit tests) ─────────────────────
# _divclass <match> <c4_ready> <bcount> <blockers> → prints the class.
# Sourced in a clean `bash -c` subshell so aid-fsm.sh's `set -euo pipefail` never
# leaks into the bats assertion shell. This is the AUTHORITATIVE 7-class coverage.
_divclass() {
  bash -c '
    source "$1" >/dev/null 2>&1
    _c4_divergence_class "$2" "$3" "$4" "$5"
  ' _ "$SCRIPTS/aid-fsm.sh" "$1" "$2" "$3" "$4"
}

@test "dual: divergence_class=none when match=true (evaluated first)" {
  [ "$(_divclass true true 0 '')" == "none" ]
  # match=true dominates even with a blocker present (both-blocked agreement).
  [ "$(_divclass true false 1 'review_profile')" == "none" ]
}

@test "dual: divergence_class=verification_only (sole verification_report blocker)" {
  [ "$(_divclass false false 1 'verification_report')" == "verification_only" ]
}

@test "dual: divergence_class=reporter_missing (sole reporter blocker)" {
  [ "$(_divclass false false 1 'reporter')" == "reporter_missing" ]
}

@test "dual: divergence_class=simplifier_missing (sole simplifier blocker)" {
  [ "$(_divclass false false 1 'simplifier')" == "simplifier_missing" ]
}

@test "dual: divergence_class=required_input (sole review_profile — DOMINANT)" {
  [ "$(_divclass false false 1 'review_profile')" == "required_input" ]
}

@test "dual: divergence_class=required_input (sole semantic_review_final blocker)" {
  # Canonical literal is semantic_review_final (NOT semantic_review).
  [ "$(_divclass false false 1 'semantic_review_final')" == "required_input" ]
  [ "$(_divclass false false 1 'gates_report')" == "required_input" ]
  [ "$(_divclass false false 1 'curator_report')" == "required_input" ]
}

@test "dual: divergence_class=c4_permissive (C4 ready, legacy blocked, no C4 blocker)" {
  [ "$(_divclass false true 0 '')" == "c4_permissive" ]
}

@test "dual: divergence_class=mixed (2+ C4 blockers of any categories)" {
  local blk; blk="$(printf 'review_profile\nreporter')"
  [ "$(_divclass false false 2 "$blk")" == "mixed" ]
  # same-category ×2 is still mixed
  local blk2; blk2="$(printf 'review_profile\ngates_report')"
  [ "$(_divclass false false 2 "$blk2")" == "mixed" ]
}

@test "dual: divergence_class=unclassified (sole non-category blocker — fail-closed)" {
  # invalidation_map never blocks in practice, but if it ever were the sole id → unclassified.
  [ "$(_divclass false false 1 'invalidation_map')" == "unclassified" ]
  [ "$(_divclass false false 1 'some_unknown_id')" == "unclassified" ]
}

@test "dual: divergence_class=unclassified fail-closed (not-ready + EMPTY blockers)" {
  # The aggregator never emits this combo, but the classifier must NOT return empty/null.
  [ "$(_divclass false false 0 '')" == "unclassified" ]
}

@test "dual: EVERY (match,ready,bcount,blockers) combo yields a non-empty class in the enum" {
  local valid=" none verification_only reporter_missing simplifier_missing required_input c4_permissive mixed unclassified "
  local m r c blk out
  for m in true false; do
    for r in true false unknown; do
      for c in 0 1 2; do
        blk=""
        [ "$c" == "1" ] && blk="review_profile"
        [ "$c" == "2" ] && blk="$(printf 'review_profile\nreporter')"
        out="$(_divclass "$m" "$r" "$c" "$blk")"
        [ -n "$out" ]                              # never empty
        [[ "$valid" == *" $out "* ]]               # always in the enum
      done
    done
  done
}

# ─── FSM-level end-to-end: legacy-green project with the C4 pack ABSENT ────────
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
  echo "curator ran" > "$EVID/curator-report.md"
  printf 'blocking_findings: false\n' > "$EVID/audit-report.md"
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
}

@test "dual: done-advance emits release_policy_dual_run (observe → advances) with head_sha + non-empty divergence_class" {
  _fsm_setup_legacy_green
  local head; head="$(git -C "$PROJ" rev-parse HEAD)"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 0 ]                                    # observe: transition unaffected by C4 divergence
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"  # phase advanced
  local ev; ev="$(grep '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.head_sha')" == "$head" ]     # head_sha anchor present + == HEAD
  [ "$(echo "$ev" | jq -r '.match')" == "false" ]        # legacy green vs C4 blocked
  local dc; dc="$(echo "$ev" | jq -r '.divergence_class')"
  [ -n "$dc" ] && [ "$dc" != "null" ]                    # non-empty divergence_class
  [ "$dc" == "mixed" ]                                   # C4 pack absent → many blockers → mixed
  [ "$(echo "$ev" | jq -r '.result')" == "compared" ]
}

@test "dual: RELEASE_DECISION_POLICY=blocking → C4 release_ready=false blocks the transition (live blocking branch)" {
  _fsm_setup_legacy_green
  local pol="$TEST_TMPDIR/rdp-blocking.yaml"
  printf 'version: 1\nenforcement: blocking\n' > "$pol"
  run env RELEASE_DECISION_POLICY="$pol" bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -ne 0 ]                                    # C4 false blocks under enforcement:blocking
  grep -q '^done_phase: review' "$EVID/fsm-state.yaml"   # transition did NOT advance
  local ev; ev="$(grep '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.enforcement')" == "blocking" ]
}

@test "dual: hook runs AFTER all legacy checks — legacy-fail + C4-fail → match=true (both blocked)" {
  _fsm_setup_legacy_green
  # Make the legacy verdict FAIL: remove curator-report so the legacy curator check errors.
  rm -f "$EVID/curator-report.md"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -ne 0 ]                                    # legacy blocked → transition fails
  # The dual-run event was still emitted (hook runs before the final tally) and, because
  # BOTH legacy and C4 are not-ready, the verdicts AGREE → match=true → divergence_class none.
  local ev; ev="$(grep '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.match')" == "true" ]
  [ "$(echo "$ev" | jq -r '.divergence_class')" == "none" ]
  [ "$(echo "$ev" | jq -r '.legacy_ready')" == "false" ]
}

@test "dual: crash-guard — broken aggregator → result=crash event + done-advance STILL passes (set -e safe)" {
  _fsm_setup_legacy_green
  local broken="$TEST_TMPDIR/broken-aggregator.sh"
  printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$broken"
  run env AID_RELEASE_POLICY_BIN="$broken" bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 0 ]                                    # crash MUST NOT abort done-advance
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"
  local ev; ev="$(grep '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl" | tail -1)"
  [ "$(echo "$ev" | jq -r '.result')" == "crash" ]
  [ -n "$(echo "$ev" | jq -r '.divergence_class')" ]     # non-empty even on crash
  [ "$(echo "$ev" | jq -r '.divergence_class')" == "unclassified" ]
}

@test "dual: --force skips the dual-run hook (NO release_policy_dual_run) and writes a valid waiver" {
  _fsm_setup_legacy_green
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml" \
    --force --reason "PM approved release despite absent C4 evidence pack (dual-run test fixture)"
  [ "$status" -eq 0 ]
  grep -q '^done_phase: release' "$EVID/fsm-state.yaml"
  # force bypasses the whole gauntlet → the dual-run hook is structurally unreached.
  ! grep -q '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl"
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
    --force --reason "PM approved release despite absent C4 evidence pack (dual-run test fixture)"
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

@test "preempted: tiered_compliance blocking failure → release_policy_preempted gate=tiered_compliance (before exit 2)" {
  # Blocking verifier_provenance (subagent + verifier output + EMPTY timeline → unverifiable).
  mkdir -p "$EVID/gates" "$CFG" "$PROJ/.aid-o/tasks" "$PROJ/.aid-o/work"
  touch "$PROJ/.aid-o/work/audit-log.jsonl"
  cat > "$CFG/plugin.yaml" <<EOF
plugin_path: "$PLUGIN_ROOT"
dispatch_mode: subagent
EOF
  touch "$CFG/execution.yaml"
  cat > "$CFG/check-severity.yaml" <<EOF
version: 1
checks:
  verifier_provenance: {severity: blocking, promoted_at: "2026-05-13", promoted_reason: "test"}
EOF
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-07-09T00:00:00Z","_command_log":[]}\n' \
    > "$EVID/gates/gates_report.json"
  echo "curator ran" > "$EVID/curator-report.md"
  printf 'blocking_findings: false\n' > "$EVID/audit-report.md"
  : > "$EVID/timeline.jsonl"
  printf 'classification: RUN\n' > "$EVID/step-1-verify.md"
  cat > "$EVID/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2025-01-01T00:00:00Z
classification: RUN
verdict: pass
EOF
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
  cd "$PROJ"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 2 ]                                    # tiered-compliance exit 2 (before the C4 slot)
  ! grep -q '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl"
  local ev; ev="$(grep '"event":"release_policy_preempted"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.gate')" == "tiered_compliance" ]
}

@test "preempted: streamlined missing integration evidence → release_policy_preempted gate=streamlined_integration" {
  mkdir -p "$EVID" "$CFG" "$PROJ/.aid-o/tasks" "$PROJ/.aid-o/work"
  touch "$PROJ/.aid-o/work/audit-log.jsonl"
  : > "$EVID/timeline.jsonl"
  # streamlined_mode true + none of the 3 integration-review files → integration check dies first.
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
streamlined_mode: true
EOF
  cd "$PROJ"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -ne 0 ]
  ! grep -q '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl"
  local ev; ev="$(grep '"event":"release_policy_preempted"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.gate')" == "streamlined_integration" ]
}

@test "preempted: cp4 curator-validation missing (prod touched) → release_policy_preempted gate=cp4_curator" {
  # Legacy-green EXCEPT the curator touched a production path in base..HEAD with no CP4 review.
  mkdir -p "$EVID/gates" "$CFG" "$PROJ/.aid-o/tasks" "$PROJ/.aid-o/work" "$PROJ/scripts"
  touch "$PROJ/.aid-o/work/audit-log.jsonl"
  cat > "$CFG/plugin.yaml" <<EOF
plugin_path: "$PLUGIN_ROOT"
dispatch_mode: agent_tool
EOF
  touch "$CFG/execution.yaml"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-07-09T00:00:00Z","_command_log":[]}\n' \
    > "$EVID/gates/gates_report.json"
  echo "curator ran" > "$EVID/curator-report.md"
  printf 'blocking_findings: false\n' > "$EVID/audit-report.md"
  : > "$EVID/timeline.jsonl"
  echo ".aid-o/" > "$PROJ/.gitignore"
  git init -q -b main "$PROJ"
  git -C "$PROJ" config user.email test@test.local
  git -C "$PROJ" config user.name Test
  echo "base" > "$PROJ/README.md"
  git -C "$PROJ" add .gitignore README.md
  git -C "$PROJ" commit -q -m base
  local base; base="$(git -C "$PROJ" rev-parse HEAD)"
  echo "echo prod" > "$PROJ/scripts/prod.sh"          # production-path change (matches default cp4 glob)
  git -C "$PROJ" add scripts/prod.sh
  git -C "$PROJ" commit -q -m "touch prod"
  cat > "$EVID/fsm-state.yaml" <<EOF
epic_id: ${EPIC}
run_id: ${RUN}
branch: task/${EPIC}/main
state: DONE
done_phase: review
created_at: 2026-07-09T10:00:00Z
base_commit: ${base}
total_steps: 3
current_step: 3
pm_decision: merge
EOF
  cd "$PROJ"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -ne 0 ]                                   # cp4 die (before the C4 slot)
  ! grep -q '"event":"release_policy_dual_run"' "$EVID/timeline.jsonl"
  local ev; ev="$(grep '"event":"release_policy_preempted"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.gate')" == "cp4_curator" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# E-059-2_2 Step 7 — Doc-1 §13.2 D11 negative fixtures (rows 18-27).
#
# These exercise the D11 state model the aggregator (Step 4) + pm-brief (Step 6) added:
# pm_brief_required/pm_brief_status, the Reporter/Simplifier 5-enum CONDITIONAL status,
# evidence_verification_status fail-vs-unverifiable, and waived != pass through the brief.
#
# Rows 26-27 (required_input / c4_permissive / mixed divergence classes) are ALREADY
# covered EXACTLY ONCE by the Step-5 `dual:` classifier unit tests above — they are NOT
# re-implemented here (per the do-not-duplicate rule); the header disposition table maps
# them. d11 [25] uses reporter+simplifier (a combo Step 5 does not cover) so it is new.
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

@test "d11 [19]: per-EPIC (off-boundary) release without Reporter → reporter_status not_applicable + reason not_plan_boundary, release_ready unaffected" {
  _build_healthy   # no ca-review-complete marker → off the plan boundary
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "not_applicable" ]
  [ "$(_rd '.release_decision.reporter_reason')" == "not_plan_boundary" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker reporter
}

@test "d11 [20]: plan-boundary without Reporter (enabled, NOT disabled) → reporter_status missing → release_ready=false + blocker" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"   # simplifier stays valid → isolates reporter
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "missing" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker reporter
}

@test "d11 [21]: per-EPIC (off-boundary) release without Simplifier → simplifier_status not_applicable + reason not_plan_boundary, release_ready unaffected" {
  _build_healthy
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "not_applicable" ]
  [ "$(_rd '.release_decision.simplifier_reason')" == "not_plan_boundary" ]
  [ "$(_rd '.release_decision.release_ready')" == "true" ]
  ! _has_blocker simplifier
}

@test "d11 [22]: plan-boundary without Simplifier (enabled, NOT disabled) → simplifier_status missing → release_ready=false + blocker" {
  _on_boundary_both_valid
  rm -f "$EVID/simplifier-report.md"   # reporter stays valid → isolates simplifier
  _run_agg
  [ "$(_rd '.release_decision.simplifier_status')" == "missing" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker simplifier
}

@test "d11 [23]: stale evidence pack (--at-head mismatch) → evidence_verified_at_head=false + evidence_verification_status=fail (NOT unverifiable) → release_ready=false" {
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

@test "d11 [24] waiver: force/waiver on a Reporter-missing blocker → waiver surfaced in release-decision.json AND pm-decision-brief.json; reporter_status stays missing (waived != pass)" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"   # reporter → missing (blocker)
  # A PM waiver artifact sits in the evidence dir (the aggregator globs waiver-*.json).
  cat > "$EVID/waiver-reporter.json" <<'EOF'
{"schema_version":"aid-2.0","artifact_type":"waiver","waiver":{"visible":true,"reason":"PM waived the missing Reporter delivery report for this release (d11 fixture)."}}
EOF
  _run_agg
  # waived != pass: the status is still missing and the blocker is still present…
  [ "$(_rd '.release_decision.reporter_status')" == "missing" ]
  _has_blocker reporter
  # …but the waiver is visible in waivers_applied[].
  jq -e '.release_decision.waivers_applied | index("waiver-reporter.json")' "$OUT" >/dev/null
  # …and the brief (Step 6) echoes BOTH the waiver AND the still-missing reporter_status.
  run bash "$PMBRIEF" "$EVID"
  local brief="$EVID/pm-decision-brief.json"
  [ -f "$brief" ]
  [ "$(jq -r '.pm_decision_brief.reporter_status' "$brief")" == "missing" ]
  jq -e '.pm_decision_brief.waivers_applied | index("waiver-reporter.json")' "$brief" >/dev/null
}

@test "d11 [25] dual: plan-boundary without Reporter AND Simplifier at once → both missing → release_ready=false + divergence_class=mixed (multi-blocker never undefined)" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"   # reporter → missing
  rm -f "$EVID/simplifier-report.md"               # simplifier → missing
  _run_agg
  [ "$(_rd '.release_decision.reporter_status')" == "missing" ]
  [ "$(_rd '.release_decision.simplifier_status')" == "missing" ]
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
  _has_blocker reporter
  _has_blocker simplifier
  # Feed the REAL aggregator blocker set into the SAME classifier the FSM dual-run hook uses:
  # 2+ C4 blockers → mixed, and NEVER empty/null (fail-closed multi-blocker case).
  local bcount blk dc
  bcount="$(_rd '.release_decision.blockers | length')"
  blk="$(jq -r '.release_decision.blockers[].input_id' "$OUT")"
  dc="$(_divclass false false "$bcount" "$blk")"
  [ -n "$dc" ] && [ "$dc" != "null" ]
  [ "$dc" == "mixed" ]
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
  _rewrite_head "$C0/plan-review.json" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  _run_agg
  [ "$status" -eq 0 ]
  # PER-INPUT assert (release_ready alone would mask the out-of-pack detection).
  [ "$(_input_verdict plan_review)" == "blocked" ]
  [ "$(_input_head_match plan_review)" == "false" ]
  _has_blocker plan_review
  [ "$(_rd '.release_decision.release_ready')" == "false" ]
}

# F4(b) — the FSM dual-run hook is the NAMED emitter of the per-input divergence event.
@test "F4(b) FSM dual-run hook emits c4_head_match_divergence per head_match=false input (observe)" {
  _fsm_setup_legacy_green
  local head; head="$(git -C "$PROJ" rev-parse HEAD)"
  run bash "$FSM" done-advance review release "$EVID/fsm-state.yaml"
  [ "$status" -eq 0 ]                                    # observe: transition unaffected
  local rd="$EVID/release-decision.json"
  [ -f "$rd" ]
  [ "$(jq '[.release_decision.inputs[]|select(.head_match==false)]|length' "$rd")" -gt 0 ]
  local ev; ev="$(grep '"event":"c4_head_match_divergence"' "$EVID/timeline.jsonl" | tail -1)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.head_sha')" == "$head" ]
  [ -n "$(echo "$ev" | jq -r '.input_id')" ]
}

# F4(c) — our own markdown producer WITHOUT the `Head:` provenance line → unknown → the
# MANDATORY pm-brief "At-HEAD verification warnings" line (never a silent true).
@test "F4(c) markdown delivery report WITHOUT Head: provenance → head_match unknown + mandatory pm-brief warning line" {
  _on_boundary_both_valid                               # valid fixtures carry no `Head:` line
  _run_agg
  [ "$(_input_head_match reporter)" == "unknown" ]
  run bash "$PMBRIEF" "$EVID"
  [ -f "$EVID/pm-summary.md" ]
  grep -qi 'At-HEAD verification warnings' "$EVID/pm-summary.md"
  grep -qi 'head_match could not be verified (unknown)' "$EVID/pm-summary.md"
  grep -q 'reporter' "$EVID/pm-summary.md"
}

# F4(d) — a waiver mapped to a blocked input DOCUMENTS but never unblocks: the inputs[] row flips
# blocked→waived, the blocker line STAYS, the D11 *_status stays, release_ready stays false.
@test "F4(d) waiver mapped to a blocked input → row waived, blocker STAYS, release_ready false, D11 status unchanged" {
  _on_boundary_both_valid
  rm -f "$REPORTS/${REPORT_PLAN_ID}-delivery.md"         # reporter → missing → blocked
  # The aggregator's waiver mapping reads only .waiver.waived_check (+ the filename), so the fixture
  # carries no v2 envelope — that also keeps it out of aid-evidence-verify's v2-artifact scan, so
  # the reporter blocker is the SOLE blocker and this isolates the waiver-never-unblocks semantics.
  cat > "$EVID/waiver-reporter.json" <<'EOF'
{"waiver":{"waived_check":"reporter","reason":"PM waived the missing Reporter delivery report for this release (F4d fixture).","waived_by":"pm","waived_at":"2026-07-10T00:00:00Z","scope":"run","visible":true}}
EOF
  _run_agg
  [ "$(_input_verdict reporter)" == "waived" ]           # row blocked→waived
  _has_blocker reporter                                  # blocker line STAYS
  [ "$(_rd '.release_decision.release_ready')" == "false" ]   # waiver NEVER unblocks
  [ "$(jq -r '.release_decision.reporter_status' "$OUT")" == "missing" ]  # D11 status UNCHANGED
  [ "$(jq -r '.release_decision.waiver_findings[]|select(.waiver=="waiver-reporter.json")|.finding' "$OUT")" == "applied" ]
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
  _rewrite_head "$C0/plan-review.json" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
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
@test "F4(i) markdown delivery report WITH a Head: provenance line → head_match computed true/false (not unknown)" {
  _on_boundary_both_valid
  local rep="$REPORTS/${REPORT_PLAN_ID}-delivery.md"
  # Matching provenance (appended at EOF; frontmatter/_test_evidence untouched) → true.
  printf 'Head: %s\n' "$HEAD_SHA" >> "$rep"
  _run_agg
  [ "$(_input_head_match reporter)" == "true" ]
  [ "$(_input_verdict reporter)" == "pass" ]
  # Mismatching provenance → false → blocked (stale report must not look usable).
  cp "$FIX/reports/P059-delivery-valid.md" "$rep"
  printf 'Head: %s\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >> "$rep"
  _run_agg
  [ "$(_input_head_match reporter)" == "false" ]
  [ "$(_input_verdict reporter)" == "blocked" ]
  _has_blocker reporter
}
