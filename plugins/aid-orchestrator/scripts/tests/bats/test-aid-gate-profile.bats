#!/usr/bin/env bats
# aid-tier: t0
# test-aid-gate-profile.bats — the pre-P097 profile library
# (scripts/lib/aid-gate-profile.sh), reduced by P097 Step 4 to the cases
# that still hold: the static rank table and the path classification that
# `execution_yaml_default_when_paths` was copied from. Nothing in scripts/
# sources the library any more; the resolver is lib/aid-gate-profile-select.sh
# (test-aid-gate-profile-select.bats). Step 9 deletes both this suite and the
# library. The release-boundary, override and review-profile floor layers are
# dead code and are no longer tested here.

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
  make_paths_file "$pf" "plugins/aid-orchestrator/scripts/aid-review-profile.sh"
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
@test "sourced: gate_profile_classify_paths is directly callable after sourcing (not just via CLI)" {
  run bash -c "source '$GP'; gate_profile_classify_paths 'docs/x.md' 'README.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}
