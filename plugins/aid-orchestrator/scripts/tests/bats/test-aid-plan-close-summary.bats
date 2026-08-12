#!/usr/bin/env bats
# aid-tier: t1
# test-aid-plan-close-summary.bats — fixtures for the plan-final/close renderer
# (P080 Step 12).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   aid_plan_close_render emits text on stdout and an artifact BODY on disk. It
#   never publishes. Publication through the Artifact tool is a live,
#   session-level act owned by the controller instruction, and NOTHING here
#   claims to cover it — the same boundary test-aid-artifact-render.bats draws.
#
# WHY THE FIXTURES ARE HAND-AUTHORED
#   Every release-decision.json in this repo is EPIC-mode and therefore carries
#   `plan_summary: null`. There is no PLAN-mode artifact to copy, so the
#   plan_summary fixtures below are built from the producer's field set
#   (scripts/aid-release-policy.sh:1107-1136) and the brief fixtures from
#   build_brief_payload (scripts/aid-pm-brief.sh:116-133).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  OUT_DIR="$TEST_TMPDIR/out"
  mkdir -p "$OUT_DIR"
  export OUT_DIR
  BRIEF="$TEST_TMPDIR/pm-decision-brief.json"
  DECISION="$TEST_TMPDIR/release-decision.json"
  export BRIEF DECISION
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-close-summary.sh"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ───────────────────────────────────────────────────────────────

# _brief <release_ready> <merge_mode> <blockers_json>
_brief() {
  jq -n --argjson ready "$1" --arg mode "$2" --argjson blockers "$3" '{
    schema_version: "aid-2.0",
    artifact_type: "pm_decision_brief",
    pm_decision_brief: {
      communication_status: "complete",
      release_ready: $ready,
      blockers: $blockers,
      waivers_applied: [],
      human_summary_path: "pm-summary.md",
      merge_mode: $mode,
      evidence_verification_status: "pass",
      evidence_verified_at_head: true,
      reporter_status: "ok",
      reporter_reason: "",
      simplifier_status: "ok",
      simplifier_reason: "",
      summary_for_pm: "release_ready=true; evidence=pass; blockers=0",
      delivered_summary_ref: ".aid-o/work/evidence/P080/delivery.md"
    }
  }' > "$BRIEF"
}

# _decision <final_merge_sha_json> <tag_status>
_decision() {
  jq -n --argjson merge "$1" --arg tag "$2" '{
    schema_version: "aid-2.0",
    artifact_type: "release_decision",
    release_decision: {
      release_ready: true,
      merge_mode: "auto",
      plan_summary: {
        plan_id: "P080",
        plan_final_run_id: "R-1",
        reviewed_candidate_sha: "1111111111111111111111111111111111111111",
        approved_target_sha: "2222222222222222222222222222222222222222",
        target_ref: "main",
        final_merge_sha: $merge,
        release_tag_status: $tag,
        epics: [
          {epic_id: "E-080-1", run_id: "R-1", status: "merged_to_plan", skipped: false, reason: null},
          {epic_id: "E-080-2", run_id: "R-2", status: "merged_to_plan", skipped: false, reason: null},
          {epic_id: "E-080-3", run_id: "R-3", status: "abandoned",      skipped: true,  reason: "superseded"}
        ],
        plan_final_gates: {report: ".aid-o/work/evidence/P080/gates-report.json", result: "pass",
                           quarantine_substitutes: []},
        specialist_review: {status: "clean"},
        remaining_backlog: ["IMP-999"]
      }
    }
  }' > "$DECISION"
}

_blockers_two() {
  jq -n '[{input_id: "review_profile", severity: "high", reason: "profil neodpovídá HEAD"},
          {input_id: "delivery_report", severity: "high", reason: "chybí delivery report"}]'
}

# ─── fixture class 1: not release-ready → Decision-required card ────────────

@test "not-release-ready brief renders a Decision-required card with a recommendation" {
  _brief false blocked "$(_blockers_two)"
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Potřebuji tvoje rozhodnutí: jak uzavřít plán P080?"* ]]
  [[ "$output" == *"Doporučení:"* ]]
  # Every card field of the Decision skeleton is present.
  [[ "$output" == *"Proč teď:"* ]]
  [[ "$output" == *"Alternativy:"* ]]
  [[ "$output" == *"Riziko / co není ověřeno:"* ]]
  # The blocker count is COUNTED, not asserted by prose.
  [[ "$output" == *"2 blokátorů"* ]]
  [[ "$output" == *"review_profile: profil neodpovídá HEAD"* ]]
  [ -s "$OUT_DIR/plan-close-artifact.html" ]
}

@test "the not-ready card renders the EXACT invocation of every offered option" {
  _brief false blocked "$(_blockers_two)"
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  # Byte-compare, not "at least one command": A is the no-action option (there
  # is no defer command at this HEAD), B and C are the two real invocations.
  [[ "$output" == *"Doporučení: A — nedělat nic — plán zůstává otevřený, žádný příkaz se nespouští."* ]]
  [[ "$output" == *"Alternativy: B — mergnout plán do main i tak, na vlastní riziko — \`aid-plan-fsm.sh plan-merge-to-main P080 --decision ${DECISION}\`; C — uzavřít plán bez merge — \`aid-plan-fsm.sh plan-close P080\`"* ]]
}

@test "release-ready but manual merge_mode still asks, and recommends the merge command" {
  _brief true manual '[]'
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Potřebuji tvoje rozhodnutí:"* ]]
  [[ "$output" == *"Doporučení: A — mergnout plán do main — \`aid-plan-fsm.sh plan-merge-to-main P080 --decision ${DECISION}\`"* ]]
  # Zero blockers still renders the Riziko line — the field is required.
  [[ "$output" == *"Riziko / co není ověřeno: Žádná materiální nejistota"* ]]
}

# ─── fixture class 2: completed close → Finished card ──────────────────────

@test "release-ready + auto merge_mode renders a Finished card with counted EPICs" {
  _brief true auto '[]'
  _decision '"3333333333333333333333333333333333333333"' v2.84.0

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hotovo: plán P080 je připravený k uzavření."* ]]
  # 2 of 3 EPICs merged — COUNTED from epics[], which carries no total field.
  [[ "$output" == *"Změnilo se: 2 z 3 EPIKŮ je v plánu"* ]]
  [[ "$output" == *"tag v2.84.0"* ]]
  [[ "$output" == *"Ověřeno: plan-final brány pass"* ]]
  [[ "$output" != *"Potřebuji tvoje rozhodnutí"* ]]
}

@test "the tag status is echoed verbatim, including the not_tagged default" {
  _brief true auto '[]'
  _decision null not_tagged
  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag not_tagged"* ]]
  # The value `tagged` does not exist in the shipped vocabulary.
  [[ "$output" != *"tag tagged"* ]]
  grep -qF 'not_tagged' "$OUT_DIR/plan-close-artifact.html"
}

# ─── fixture class 3: fail-closed, both shapes ─────────────────────────────

@test "a brief missing one of the eight named fields exits 1 and names it" {
  _brief false manual '[]'
  jq 'del(.pm_decision_brief.waivers_applied)' "$BRIEF" > "$BRIEF.tmp" && mv "$BRIEF.tmp" "$BRIEF"
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field(s): waivers_applied"* ]]
  [ ! -f "$OUT_DIR/plan-close-artifact.html" ]
}

@test "a release-decision without .release_decision.plan_summary exits 1" {
  _brief true auto '[]'
  _decision null not_tagged
  jq '.release_decision.plan_summary = null' "$DECISION" > "$DECISION.tmp" && mv "$DECISION.tmp" "$DECISION"

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"carries no .release_decision.plan_summary"* ]]
  [ ! -f "$OUT_DIR/plan-close-artifact.html" ]
}

@test "an absent brief exits 1 pointing at aid-pm-brief.sh, never improvising" {
  _decision null not_tagged
  run aid_plan_close_render "$TEST_TMPDIR/nope.json" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run aid-pm-brief.sh"* ]]
  [ ! -f "$OUT_DIR/plan-close-artifact.html" ]
}

@test "a malformed release-decision.json degrades visibly, not into a complete-looking page" {
  _brief true auto '[]'
  printf '{ this is not json' > "$DECISION"
  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing or unparseable"* ]]
  [ ! -f "$OUT_DIR/plan-close-artifact.html" ]
}

# ─── the rollback option is conditional on a real revert commit ────────────

@test "final_merge_sha null renders no rollback command at all" {
  _brief false manual '[]'
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"plan-rollback"* ]]
  [[ "$output" == *"Vrácení zpět: není použitelné — plán zatím není mergnutý do main."* ]]
}

@test "a merged plan offers plan-rollback with the SHA interpolated from the input" {
  _brief false manual '[]'
  _decision '"3333333333333333333333333333333333333333"' not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Alternativy: B — vrátit merge zpět — \`aid-plan-fsm.sh plan-rollback P080 --revert-commit 3333333333333333333333333333333333333333 --reason \"<důvod vrácení>\"\`"* ]]
  [[ "$output" == *"Doporučení: A — uzavřít plán — \`aid-plan-fsm.sh plan-close P080\`"* ]]
  [[ "$output" != *"Vrácení zpět: není použitelné"* ]]
}

# ─── the artifact body ─────────────────────────────────────────────────────

@test "the artifact body is a body, carries the counted tiles and asks nothing when nothing is asked" {
  _brief true auto '[]'
  _decision '"3333333333333333333333333333333333333333"' v2.84.0

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  body="$OUT_DIR/plan-close-artifact.html"
  # A BODY: the Artifact tool supplies the skeleton.
  ! grep -qiF '<!doctype' "$body"
  ! grep -qiF '<html' "$body"
  # Counted, not asserted.
  grep -qF '2/3 EPIKŮ' "$body"
  grep -qF 'Plán P080 — plan-final boundary' "$body"
  # Block 6 always renders; the Finished card asks for nothing, so the shipped
  # literal appears rather than a silently absent block.
  grep -qF 'Nic — ozvu se, až bude hotovo' "$body"
  # The full revert SHA never reaches the page — the label does (see the lib
  # header: a 40-hex run trips the renderer's high_entropy_blob detector).
  ! grep -qF '3333333333333333333333333333333333333333' "$body"
}

@test "the option labels reach the artifact's next-steps block" {
  _brief false blocked "$(_blockers_two)"
  _decision null not_tagged

  run aid_plan_close_render "$BRIEF" "$DECISION" P080 "$OUT_DIR"
  [ "$status" -eq 0 ]
  body="$OUT_DIR/plan-close-artifact.html"
  grep -qF 'Jak pokračovat' "$body"
  grep -qF 'uzavřít plán bez merge' "$body"
  # Blockers are the unresolved tile, counted from the brief.
  grep -qF 'Blokátory' "$body"
}
