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

setup() {
  export TZ=UTC
  export AID_TEST_MODE=1
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"   # .../plugins/aid-orchestrator
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  SCRIPTS="$PLUGIN_ROOT/scripts"
  AGG="$SCRIPTS/aid-release-policy.sh"
  VALIDATE="$SCRIPTS/aid-protocol-validate.sh"
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
