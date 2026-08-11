#!/usr/bin/env bats
# aid-tier: t2
# test-plan-force.bats — P073 Step 7: the plan-level force framework.
#
# aid-plan-fsm.sh hard-rejected `--force` on every subcommand, so a defective
# bookkeeping path could strand the PM with no supported way to finish a plan.
# This suite tests the FRAMEWORK helpers directly (Step 8 wires them into the
# eight public commands):
#   _pfsm_precondition  — forceable/hard classification, in code not prose
#   _pfsm_handle_force  — the three audited records, waiver fail-closed
#
# The helpers are sourced out of aid-plan-fsm.sh rather than driven through the
# CLI, because at this step no command parses --force yet.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PFSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  ( cd "$ROOT" && git init -q && git config user.email t@e.com && git config user.name T \
      && printf 'seed\n' > README.md && git add -A && git commit -qm seed )
}

teardown() {
  teardown_test_evidence_dir
}

# _force <shell-body> — runs <shell-body> with the force helpers in scope.
# aid-plan-fsm.sh is a standalone CLI whose bottom dispatches on "$1", so it is
# sourced with a no-op argument list and the dispatcher guarded off by the
# AID_PFSM_NO_DISPATCH seam the file already honours for tests... which it does
# not, so instead only the helper block is extracted. Bounded by the two
# marker comments that open and close the P073 Step 7 block.
_force() {
  local body="$1"
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    eval "$(sed -n "/^_PFSM_BYPASSED=\"\"/,/^# _pfsm_parse_force_flag/p" "'"$PFSM"'")"
    cd "'"$ROOT"'"
    '"$body"'
  '
}

# ─── reason validation ────────────────────────────────────────────────────

@test "P073 Step 7: a reason under 20 characters is refused and writes nothing" {
  run _force '
    _PFSM_FORCE=1; _PFSM_FORCE_REASON="too short"
    _fails() { return 1; }
    _pfsm_precondition "clean_worktree" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

# ─── the three records ────────────────────────────────────────────────────

@test "P073 Step 7: a forced call writes the waiver receipt and the audit-log entry" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORCE: recorded at"* ]]

  # Record 3: the waiver artifact.
  local w
  w="$(find "$ROOT/.aid-o" -name 'waiver-plan-plan-close-*.json' | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.artifact_type' "$w")" = "waiver" ]
  [ "$(jq -r '.forced_override' "$w")" = "true" ]
  [ "$(jq -r '.bypassed_preconditions | join(",")' "$w")" = "bookkeeping_complete" ]
  [ "$(jq -r '.identity.epic_id' "$w")" = "P900" ]
  [ "$(jq -r '.waiver.visible' "$w")" = "true" ]
  [ "$(jq -r '.waiver.reason | length >= 20' "$w")" = "true" ]
  # HEAD-bound.
  [ "$(jq -r '.revision.head_sha' "$w")" = "$(cd "$ROOT" && git rev-parse HEAD)" ]

  # Record 2: the cross-plan audit log.
  [ -s "$ROOT/.aid-o/work/audit-log.jsonl" ]
  run grep -c 'plan_force_override' "$ROOT/.aid-o/work/audit-log.jsonl"
  [ "$output" -ge 1 ]
}

@test "P073 Step 7: the timeline event is written when a plan-final run dir exists" {
  mkdir -p "$ROOT/.aid-o/work/plan-final/P900"
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  [ -s "$ROOT/.aid-o/work/plan-final/P900/timeline.jsonl" ]
  run jq -r '.event' "$ROOT/.aid-o/work/plan-final/P900/timeline.jsonl"
  [ "$output" = "plan_force_override" ]
}

@test "P073 Step 7: a force that bypassed NOTHING writes no waiver (no receipt for a no-op flag)" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="passed --force defensively but every precondition was satisfied"
    _PFSM_BYPASSED=""
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"bypassed nothing"* ]]
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

# ─── fail-closed receipt ──────────────────────────────────────────────────

@test "P073 Step 7: an unwritable evidence dir FAILS the force rather than bypassing silently" {
  mkdir -p "$ROOT/.aid-o/work/plan-final"
  chmod a-w "$ROOT/.aid-o/work/plan-final"
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  local rc="$status"
  chmod u+w "$ROOT/.aid-o/work/plan-final"
  [ "$rc" -ne 0 ]
  [[ "$output" == *"refusing a silent bypass"* ]]
}

# ─── forceable vs hard classification ─────────────────────────────────────

@test "P073 Step 7: a FORCEABLE precondition is bypassed under --force and recorded by name" {
  run _force '
    _PFSM_FORCE=1
    _fails() { echo "the check own recovery message" >&2; return 1; }
    if _pfsm_precondition "clean_worktree" forceable _fails; then echo CONTINUED; else echo REFUSED; fi
    echo "bypassed=$_PFSM_BYPASSED"
  '
  [ "$status" -eq 0 ]
  # The check printed its own recovery FIRST — the normal path is never hidden.
  [[ "$output" == *"the check own recovery message"* ]]
  [[ "$output" == *"CONTINUED"* ]]
  [[ "$output" == *"bypassed=clean_worktree"* ]]
}

@test "P073 Step 7: a HARD precondition is NEVER bypassed, even with --force" {
  run _force '
    _PFSM_FORCE=1
    _fails() { echo "unresolvable merge in progress" >&2; return 1; }
    if _pfsm_precondition "merge_in_progress" hard _fails; then echo CONTINUED; else echo REFUSED; fi
    echo "bypassed=$_PFSM_BYPASSED"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" == *"FORCE CANNOT BYPASS 'merge_in_progress'"* ]]
  [[ "$output" == *"bypassed="* ]]
  [[ "$output" != *"bypassed=merge_in_progress"* ]]
}

@test "P073 Step 7: without --force a forceable precondition still refuses" {
  run _force '
    _PFSM_FORCE=0
    _fails() { echo "the check own recovery message" >&2; return 1; }
    if _pfsm_precondition "clean_worktree" forceable _fails; then echo CONTINUED; else echo REFUSED; fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" != *"FORCE:"* ]]
}

@test "P073 Step 7: a passing precondition records nothing and continues" {
  run _force '
    _PFSM_FORCE=1
    _ok() { return 0; }
    if _pfsm_precondition "clean_worktree" forceable _ok; then echo CONTINUED; else echo REFUSED; fi
    echo "bypassed=[$_PFSM_BYPASSED]"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONTINUED"* ]]
  [[ "$output" == *"bypassed=[]"* ]]
}

@test "P073 Step 7: an unknown classification fails closed" {
  run _force '
    _PFSM_FORCE=1
    _fails() { return 1; }
    if _pfsm_precondition "typo_class" sortof _fails; then echo CONTINUED; else echo REFUSED; fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" == *"unknown class"* ]]
}

# ─── injection safety ─────────────────────────────────────────────────────

@test "P073 Step 7: a reason containing shell metacharacters and newlines lands intact, not interpreted" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="closing after \$(rm -rf /) `id` and a \"quote\"; long enough to pass validation"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  local w
  w="$(find "$ROOT/.aid-o" -name 'waiver-plan-*.json' | head -1)"
  [ -n "$w" ]
  # jq --arg encoded it; the shell never evaluated it.
  run jq -r '.waiver.reason' "$w"
  [[ "$output" == *'$(rm -rf /)'* ]]
  [[ "$output" == *'"quote"'* ]]
}

# ─── protocol-v2 validation + C4 visibility ───────────────────────────────

@test "P073 Step 7: the force waiver validates against the protocol-v2 waiver schema" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  local w
  w="$(find "$ROOT/.aid-o" -name 'waiver-plan-*.json' | head -1)"

  # The waiver SUBOBJECT is the strict part (additionalProperties: false), so
  # the additive fields had to go top-level; assert both halves hold.
  run jq -e '
    .waiver | keys_unsorted | sort ==
      ["reason","scope","visible","waived_at","waived_by","waived_check"]
  ' "$w"
  [ "$status" -eq 0 ]
  run jq -e '.forced_override == true and (.bypassed_preconditions | length) >= 1' "$w"
  [ "$status" -eq 0 ]

  # Unconditional: the validator ships with the plugin, so a conditional here
  # would silently stop proving anything if it were ever moved.
  [ -x "$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh" ]
  run bash "$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh" "$w"
  [ "$status" -eq 0 ]
}

@test "P073 Step 7: the schema declares the additive fields, so they are documented not smuggled" {
  local schema="$AID_PLUGIN_PATH/defaults/schemas/waiver.schema.json"
  run jq -e '.properties.forced_override and .properties.bypassed_preconditions' "$schema"
  [ "$status" -eq 0 ]
  # A bypassed_preconditions list without forced_override is not a legal shape.
  run jq -e '.dependentRequired.bypassed_preconditions | index("forced_override")' "$schema"
  [ "$status" -eq 0 ]
}

# ─── C4 visibility (the whole point of the waiver artifact) ────────────────

@test "P073 Step 7: a C4 aggregation over the evidence dir lists the plan-level force in waivers_applied[]" {
  # The force receipt exists so the PM surface never sees a silent bypass.
  # aid-release-policy.sh is the C4 aggregator; in plan mode it scans
  # waiver-*.json under the evidence dir it is given.
  local ev="$ROOT/.aid-o/work/evidence/P900/R-P900-final-1"
  mkdir -p "$ev"
  # Plan mode never falls back to EPIC resolution, so the aggregator needs a
  # real manifest. Build it through the sanctioned producer, not by hand.
  local head; head="$(cd "$ROOT" && git rev-parse HEAD)"
  run bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    cd "'"$ROOT"'"
    plan_manifest_init P900 plan/P900 main "'"$head"'" "'"$head"'" plan_branch >/dev/null
    # The aggregator enforces the P064 identity invariant, so the manifest has
    # to carry a real frozen candidate pointing at this evidence dir.
    # P073 Step 15 made the protected-path set part of the freeze contract:
    # the 7th and 8th arguments are REQUIRED, because a freeze with no
    # protected set cannot support review equivalence and must not look as if
    # it does. This fixture predates that and was calling the 6-argument form.
    printf "%s\0" "scripts/a.sh" > "'"$BATS_TEST_TMPDIR"'/force-prot.nul"
    plan_manifest_freeze_candidate P900 "'"$head"'" "'"$head"'" \
      R-P900-final-1 ".aid-o/work/evidence/P900/R-P900-final-1" "2026-08-05T00:00:00Z" \
      "'"$BATS_TEST_TMPDIR"'/force-prot.nul" true >/dev/null
  '
  [ "$status" -eq 0 ]

  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  # With a manifest recording the plan-final run dir, the receipt is written
  # straight there — no fallback, no sweep needed.
  run bash -c "ls '$ev'/waiver-plan-*.json | wc -l"
  [ "$output" = "1" ]

  local out="$ROOT/decision.json"
  run bash "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh" \
      --plan P900 --run-id R-P900-final-1 --evidence-dir "$ev" \
      --candidate-sha "$head" --target-ref main --target-head-sha "$head" \
      --out "$out"
  # The aggregator may legitimately report NOT-ready on this bare fixture; what
  # matters is that it produced a decision listing the force receipt.
  [ -s "$out" ]
  # The field may be nested under the decision envelope; assert on the whole
  # document so this does not depend on the aggregator's exact nesting.
  run jq -r '[.. | objects | select(has("waivers_applied")) | .waivers_applied[]?] | join(",")' "$out"
  [[ "$output" == *"waiver-plan-plan-close-"* ]]
}

# ─── the pre-attempt sweep ────────────────────────────────────────────────

@test "P073 Step 7: freeze sweeps a pre-attempt force receipt into the first attempt dir (moved, not copied)" {
  # A force issued BEFORE any plan-final attempt exists lands in the fallback
  # dir, which the C4 aggregator never scans. _pfsm_finalize_freeze moves it
  # into the attempt dir it allocates, so the first aggregation sees it.
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="plan-start forced past a lineage mismatch on an existing branch"
    _fails() { return 1; }
    _pfsm_precondition "lineage_mismatch" forceable _fails
    _pfsm_handle_force "plan-start" "P900" "'"$ROOT"'" "" "OPEN"
  '
  [ "$status" -eq 0 ]
  local fallback="$ROOT/.aid-o/work/plan-final/P900"
  run bash -c "ls '$fallback'/waiver-plan-*.json | wc -l"
  [ "$output" = "1" ]

  # Drive just the sweep block the way freeze does.
  local run_dir_abs="$ROOT/.aid-o/work/evidence/P900/R-P900-final-1"
  mkdir -p "$run_dir_abs"
  run bash -c '
    set -uo pipefail
    root="'"$ROOT"'"; plan_id=P900
    run_dir_abs="'"$run_dir_abs"'"; run_dir_rel="rel"
    _force_fallback="${root}/.aid-o/work/plan-final/${plan_id}"
    if [[ -d "$_force_fallback" ]]; then
      for _fw in "$_force_fallback"/waiver-plan-*.json; do
        [[ -e "$_fw" ]] || continue
        if mv -n "$_fw" "${run_dir_abs}/" 2>/dev/null && [[ ! -e "$_fw" ]]; then
          echo "swept $(basename "$_fw")"
        else
          echo "NOT swept $(basename "$_fw")"
        fi
      done
      if [[ -s "${_force_fallback}/timeline.jsonl" ]]; then
        cat "${_force_fallback}/timeline.jsonl" >> "${run_dir_abs}/timeline.jsonl" 2>/dev/null \
          && rm -f "${_force_fallback}/timeline.jsonl" 2>/dev/null || true
      fi
      rmdir "$_force_fallback" 2>/dev/null || true
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"swept waiver-plan-plan-start-"* ]]

  # MOVED: present once in the attempt dir, gone from the fallback.
  run bash -c "ls '$run_dir_abs'/waiver-plan-*.json | wc -l"
  [ "$output" = "1" ]
  [ ! -d "$fallback" ]
}

@test "P073 Step 7: the freeze body carries the sweep, so the wiring is not test-only" {
  run grep -c 'swept pre-attempt force receipt' "$PFSM"
  [ "$output" = "1" ]
}

# ─── Codex-review findings on the first cut of this step ──────────────────

@test "P073 Step 7 (review finding 1): a FAILED receipt write leaves no timeline or audit-log trail" {
  # The first cut wrote the timeline event and the audit-log entry BEFORE the
  # fail-closed waiver, so a refused force still left records describing a
  # successful override. Nothing is recorded until the receipt is on disk.
  mkdir -p "$ROOT/.aid-o/work/plan-final/P900"
  chmod a-w "$ROOT/.aid-o/work/plan-final/P900"
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  local rc="$status"
  chmod u+w "$ROOT/.aid-o/work/plan-final/P900"
  [ "$rc" -ne 0 ]
  [ ! -e "$ROOT/.aid-o/work/plan-final/P900/timeline.jsonl" ]
  [ ! -e "$ROOT/.aid-o/work/audit-log.jsonl" ]
}

@test "P073 Step 7 (review finding 2): a manifest evidence dir that escapes the plan tree is not honoured" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    # Stub the manifest reader to return a traversing path.
    plan_manifest_get() { printf "../../../../tmp/escaped"; }
    d="$(_pfsm_force_evidence_dir "'"$ROOT"'" P900)"
    echo "dir=$d"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not contained in"* ]]
  [[ "$output" == *"dir=$ROOT/.aid-o/work/plan-final/P900"* ]]
  [[ "$output" != *"dir=$ROOT/../../"* ]]
}

@test "P073 Step 7 (review finding 3): the sweep never clobbers an existing receipt of the same name" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="plan-start forced past a lineage mismatch on an existing branch"
    _fails() { return 1; }
    _pfsm_precondition "lineage_mismatch" forceable _fails
    _pfsm_handle_force "plan-start" "P900" "'"$ROOT"'" "" "OPEN"
  '
  [ "$status" -eq 0 ]
  local fallback="$ROOT/.aid-o/work/plan-final/P900"
  local src; src="$(ls "$fallback"/waiver-plan-*.json | head -1)"
  local run_dir_abs="$ROOT/.aid-o/work/evidence/P900/R-P900-final-1"
  mkdir -p "$run_dir_abs"
  # A file of the same basename is already there, holding different content.
  printf '{"pre":"existing"}\n' > "$run_dir_abs/$(basename "$src")"

  run bash -c '
    set -uo pipefail
    _fw="'"$src"'"; run_dir_abs="'"$run_dir_abs"'"
    if mv -n "$_fw" "${run_dir_abs}/" 2>/dev/null && [[ ! -e "$_fw" ]]; then
      echo "swept"
    else
      echo "NOT swept"
    fi
  '
  [[ "$output" == *"NOT swept"* ]]
  # The pre-existing receipt is intact and the source is still there.
  run jq -r '.pre' "$run_dir_abs/$(basename "$src")"
  [ "$output" = "existing" ]
  [ -e "$src" ]
}

@test "P073 Step 7 (review finding 4): a hand-set bypass name gets a refusal, not a receipt" {
  # `hard` was protected by convention only: _pfsm_handle_force trusted the
  # mutable global, so any caller could write a hard check's name into it and
  # obtain a receipt asserting that check was legitimately bypassed.
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _PFSM_BYPASSED="merge_in_progress"      # never went through the forceable path
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"never bypassed through the forceable precondition path"* ]]
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 Step 7 (review finding 4): a REAL forceable bypass still mints its receipt" {
  # The provenance gate must not break the legitimate path.
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "bookkeeping_complete" forceable _fails
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' 2>/dev/null | wc -l"
  [ "$output" = "1" ]
}

@test "P073 Step 7 (review finding 4): a HARD refusal records nothing, so no receipt is even possible" {
  run _force '
    _PFSM_FORCE=1
    _PFSM_FORCE_REASON="manifest corrupted by an interrupted merge; closing to unblock the release"
    _fails() { return 1; }
    _pfsm_precondition "merge_in_progress" hard _fails || true
    _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"bypassed nothing"* ]]
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

# ─── Independent-review finding ───────────────────────────────────────────

@test "P073 (independent review): two force receipts in the SAME second both survive" {
  # Second-precision names plus a plain `mv` meant the second force silently
  # overwrote the first's audit record — reproduced by the reviewer.
  local i
  for i in 1 2 3; do
    run _force '
      _PFSM_FORCE=1
      _PFSM_FORCE_REASON="force '"$i"' with a reason long enough to pass validation properly"
      _fails() { return 1; }
      _pfsm_precondition "bookkeeping_complete" forceable _fails
      _pfsm_handle_force "plan-close" "P900" "'"$ROOT"'" "OPEN" "CLOSED"
    '
    [ "$status" -eq 0 ]
  done
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' | wc -l"
  [ "$output" = "3" ]
  # Each carries its own distinct reason — none was clobbered.
  run bash -c "find '$ROOT/.aid-o' -name 'waiver-plan-*.json' -exec jq -r '.waiver.reason' {} \; | sort -u | wc -l"
  [ "$output" = "3" ]
}
