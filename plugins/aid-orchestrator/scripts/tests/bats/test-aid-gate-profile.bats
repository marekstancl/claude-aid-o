#!/usr/bin/env bats
# test-aid-gate-profile.bats — P061 EPIC 2/6, plan Step 7 (plan.json step_1_backend):
# aid-gate-profile.sh shared risk-classification resolver + profile ordering.
#
# Covers:
#   (1)  profile ordering: quick < targeted < standard < full < release
#   (2)  gate_profile_max ties/comparisons
#   (3)  docs-only changed paths -> quick
#   (4)  ordinary code changed paths -> standard
#   (5)  high-risk path -> full (short-circuits even alongside docs paths)
#   (6)  release boundary (fsm-state.yaml done_phase=release) -> release
#   (7)  no-fsm-state guard: nonexistent state path -> well-defined fallback, no crash
#   (8)  no args at all (simulated /aid-do, nothing supplied) -> quick, exit 0
#   (9)  manual upward override always applies
#   (10) manual downward override on high-risk tier REQUIRES waiver (force+reason>=20)
#   (11) waiver with too-short reason is rejected
#   (12) manual downward override on non-high-risk tier needs no waiver
#   (13) unknown override name is ignored (warning, no effect)
#   (14) review-profile.json floor tightens (never loosens) the path-derived result
#   (15) review-profile.json missing/unparseable/unverifiable fails CLOSED to "full"
#   (16) review-profile.json absent entirely -> no floor applied
#
# Harness style mirrors test-cache-preflight.bats (temp dir, no git needed —
# this resolver has no git dependency).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  GP="$PLUGIN_ROOT/scripts/lib/aid-gate-profile.sh"
  export GP
  WORK="$(mktemp -d)"
  export WORK
  unset AID_GATE_PROFILE_OVERRIDE AID_GATE_PROFILE_FORCE AID_GATE_PROFILE_FORCE_REASON
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# make_paths_file <file> <path...> — one path per line.
make_paths_file() {
  local file="$1"; shift
  : > "$file"
  local p
  for p in "$@"; do printf '%s\n' "$p" >> "$file"; done
}

# ─── (1) profile ordering table ─────────────────────────────────────────────
@test "ordering: gate_profile_rank returns quick=0 < targeted=1 < standard=2 < full=3 < release=4" {
  run bash "$GP" rank quick
  [ "$status" -eq 0 ]; [ "$output" = "0" ]
  run bash "$GP" rank targeted
  [ "$status" -eq 0 ]; [ "$output" = "1" ]
  run bash "$GP" rank standard
  [ "$status" -eq 0 ]; [ "$output" = "2" ]
  run bash "$GP" rank full
  [ "$status" -eq 0 ]; [ "$output" = "3" ]
  run bash "$GP" rank release
  [ "$status" -eq 0 ]; [ "$output" = "4" ]
}

@test "ordering: gate_profile_rank on an unknown name returns non-zero, no stdout" {
  run bash "$GP" rank bogus
  [ "$status" -ne 0 ]
}

# ─── (2) gate_profile_max ────────────────────────────────────────────────────
@test "ordering: gate_profile_max picks the higher-ranked of two profiles" {
  run bash "$GP" max quick full
  [ "$status" -eq 0 ]; [ "$output" = "full" ]
  run bash "$GP" max release quick
  [ "$status" -eq 0 ]; [ "$output" = "release" ]
  run bash "$GP" max targeted standard
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
}

@test "ordering: gate_profile_max is a tie-safe reflexive comparison (a==b -> a)" {
  run bash "$GP" max quick quick
  [ "$status" -eq 0 ]; [ "$output" = "quick" ]
}

# ─── (3) docs-only -> quick ──────────────────────────────────────────────────
@test "classify: docs-only changed paths -> quick" {
  local pf="$WORK/docs.txt"
  make_paths_file "$pf" "docs/plans/foo.md" "README.md" "CHANGELOG.md"
  run bash "$GP" classify-paths "$pf"
  [ "$status" -eq 0 ]; [ "$output" = "quick" ]
  run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]; [ "$output" = "quick" ]
}

# ─── (4) ordinary code change -> standard ───────────────────────────────────
@test "classify: ordinary (non-doc, non-high-risk) code change -> standard" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  run bash "$GP" classify-paths "$pf"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
  run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
}

# ─── (5) high-risk path -> full, short-circuits over docs paths ─────────────
@test "classify: a high-risk path present anywhere -> full, even mixed with docs paths" {
  local pf="$WORK/highrisk.txt"
  make_paths_file "$pf" "docs/plans/foo.md" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  run bash "$GP" classify-paths "$pf"
  [ "$status" -eq 0 ]; [ "$output" = "full" ]
}

@test "classify: each documented high-risk pattern individually classifies full" {
  local p
  for p in \
    "plugins/aid-orchestrator/scripts/aid-fsm.sh" \
    "plugins/aid-orchestrator/scripts/aid-run-gates.sh" \
    "plugins/aid-orchestrator/scripts/aid-release-policy.sh" \
    "plugins/aid-orchestrator/scripts/aid-evidence-verify.sh" \
    "plugins/aid-orchestrator/defaults/schemas/plan.schema.json" \
    "plugins/aid-orchestrator/defaults/policies/release-policy.yaml" \
    "plugins/aid-orchestrator/agents/verifier.md"
  do
    local pf="$WORK/hr.txt"
    make_paths_file "$pf" "$p"
    run bash "$GP" classify-paths "$pf"
    [ "$status" -eq 0 ]
    [ "$output" = "full" ] || { echo "FAILED for path: $p (got: $output)"; return 1; }
  done
}

# ─── (6) release boundary ────────────────────────────────────────────────────
@test "release boundary: fsm-state.yaml done_phase=release -> release, regardless of ordinary paths" {
  local pf="$WORK/ordinary.txt" state="$WORK/fsm-state.yaml"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  printf 'epic_id: E-x\nrun_id: R-x\nstate: DONE\ndone_phase: release\n' > "$state"
  run bash "$GP" resolve "$pf" "$state"
  [ "$status" -eq 0 ]; [ "$output" = "release" ]
}

@test "release boundary: fsm-state.yaml WITHOUT done_phase=release does not force release" {
  local pf="$WORK/ordinary.txt" state="$WORK/fsm-state.yaml"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  printf 'epic_id: E-x\nrun_id: R-x\nstate: EXECUTE\n' > "$state"
  run bash "$GP" resolve "$pf" "$state"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
}

# ─── (7) no-fsm-state guard ───────────────────────────────────────────────────
@test "no-fsm-state guard: nonexistent fsm-state path does not crash, falls back to path classification" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  run bash "$GP" resolve "$pf" "$WORK/nonexistent-state.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "standard" ]
}

@test "no-fsm-state guard: fsm-state arg entirely omitted does not crash" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "standard" ]
}

# ─── (8) simulated /aid-do: nothing supplied at all ─────────────────────────
@test "simulated /aid-do context: no changed-paths file, no fsm-state -> defined default (quick), exit 0" {
  run bash "$GP" resolve ""
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}

@test "simulated /aid-do context: nonexistent changed-paths file -> defined default (quick), exit 0" {
  run bash "$GP" resolve "$WORK/does-not-exist.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}

# ─── (9) manual upward override always applies ──────────────────────────────
@test "override: upward override (quick -> full) always applies, no waiver needed" {
  local pf="$WORK/docs.txt"
  make_paths_file "$pf" "docs/plans/foo.md"
  AID_GATE_PROFILE_OVERRIDE=full run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

@test "override: equal-rank override applies trivially" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  AID_GATE_PROFILE_OVERRIDE=standard run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "standard" ]
}

# ─── (10) downward override on high-risk tier requires waiver ──────────────
@test "override: downward override on high-risk computed profile WITHOUT waiver is rejected (stays full, warns)" {
  local pf="$WORK/highrisk.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  AID_GATE_PROFILE_OVERRIDE=quick run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"full"* ]]
  [[ "$output" == *"rejected"* ]]
  [[ "$output" == *"AID_GATE_PROFILE_FORCE"* ]]
}

@test "override: downward override on high-risk computed profile WITH valid waiver applies" {
  local pf="$WORK/highrisk.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  AID_GATE_PROFILE_OVERRIDE=quick AID_GATE_PROFILE_FORCE=1 \
    AID_GATE_PROFILE_FORCE_REASON="hotfix waiver, PM approved this" \
    run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}

# ─── (11) waiver with too-short reason is rejected ──────────────────────────
@test "override: waiver with a reason under 20 chars is rejected (min-length enforced)" {
  local pf="$WORK/highrisk.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  AID_GATE_PROFILE_OVERRIDE=quick AID_GATE_PROFILE_FORCE=1 \
    AID_GATE_PROFILE_FORCE_REASON="too short" \
    run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"full"* ]]
  [[ "$output" == *"rejected"* ]]
}

# ─── (12) downward override on non-high-risk tier needs no waiver ──────────
@test "override: downward override on a NON-high-risk computed profile applies without waiver" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  AID_GATE_PROFILE_OVERRIDE=targeted run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "targeted" ]
}

# ─── (13) unknown override name is ignored ──────────────────────────────────
@test "override: unknown profile name in AID_GATE_PROFILE_OVERRIDE is ignored (warns, computed unchanged)" {
  local pf="$WORK/ordinary.txt"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  AID_GATE_PROFILE_OVERRIDE=bogus run bash "$GP" resolve "$pf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"standard"* ]]
  [[ "$output" == *"ignoring"* ]]
}

# ─── (14) review-profile.json floor tightens, never loosens ────────────────
@test "review-profile floor: risk_profile=high tightens an ordinary (standard) change to full" {
  local pf="$WORK/ordinary.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-prefilter.sh"
  printf '{"review_profile":{"risk_profile":"high"}}' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

@test "review-profile floor: risk_profile=docs_trivial does NOT loosen a high-risk (full) change" {
  local pf="$WORK/highrisk.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  printf '{"review_profile":{"risk_profile":"docs_trivial"}}' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

@test "review-profile floor: risk_profile=low maps to targeted floor" {
  local pf="$WORK/docs.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "docs/plans/foo.md"
  printf '{"review_profile":{"risk_profile":"low"}}' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "targeted" ]
}

# ─── (15) unverifiable / unparseable / missing field fails CLOSED to full ───
@test "review-profile floor: risk_profile=unverifiable fails closed to full even on a docs-only change" {
  local pf="$WORK/docs.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "docs/plans/foo.md"
  printf '{"review_profile":{"risk_profile":"unverifiable"}}' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

@test "review-profile floor: malformed (non-JSON) review-profile.json fails closed to full" {
  local pf="$WORK/docs.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "docs/plans/foo.md"
  printf 'not valid json at all' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

@test "review-profile floor: JSON present but missing risk_profile field fails closed to full" {
  local pf="$WORK/docs.txt" rp="$WORK/rp.json"
  make_paths_file "$pf" "docs/plans/foo.md"
  printf '{"review_profile":{}}' > "$rp"
  run bash "$GP" resolve "$pf" "" "$rp"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]
}

# ─── (16) review-profile.json absent entirely -> no floor applied ──────────
@test "review-profile floor: nonexistent review-profile.json path applies no floor at all" {
  local pf="$WORK/docs.txt"
  make_paths_file "$pf" "docs/plans/foo.md"
  run bash "$GP" resolve "$pf" "" "$WORK/nonexistent-rp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}

@test "review-profile floor: gate_profile_review_floor echoes empty string when path is absent" {
  run bash -c "source '$GP'; gate_profile_review_floor '$WORK/nonexistent-rp.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ─── sourced-function-level sanity (not just CLI subprocess) ───────────────
@test "sourced: gate_profile_classify_paths is directly callable after sourcing (not just via CLI)" {
  run bash -c "source '$GP'; gate_profile_classify_paths 'docs/x.md' 'README.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}
