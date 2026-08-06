#!/usr/bin/env bats
# test-ancillary-classifier.bats — P073 Step 14: the ONE ancillary/delivery
# classifier.
#
# The same dirty-worktree exception regex was duplicated VERBATIM at four call
# sites — aid-plan-fsm.sh twice, aid-release.sh, and a four-entry variant in
# aid-fsm.sh — with the codebase's own comment noting the shared shape.
#
# THIS STEP IS BEHAVIOUR-NEUTRAL BY CONTRACT. Every existing caller passes
# `--mode legacy5` (or `legacy4`), reproducing its current exception set
# exactly; the broader `--mode policy` is switched on only by Step 17. The
# byte-identical assertions below are what make that contract checkable rather
# than asserted — but only if the fixture EXERCISES the differences. The first
# cut of this suite passed while the classifier silently exempted three paths
# the old regexes blocked, because the porcelain stream contained none of the
# edge cases. The stream below now carries them explicitly: a descendant of a
# bare exact entry, the bare directory of a prefix entry, and near-miss
# suffixes.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-ancillary.sh"
  export LIB
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
}

teardown() {
  teardown_test_evidence_dir
}

# _anc <body> — runs <body> with the classifier sourced.
_anc() {
  bash -c '
    set -uo pipefail
    . "$1"
    cd "$2"
    eval "$3"
  ' _ "$LIB" "$ROOT" "$1"
}

# The four call sites' original regexes, kept verbatim so the byte-identical
# tests below compare against what actually shipped, not a paraphrase.
_legacy5_regex() {
  printf '%s' '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$|^.. \.aid-o/work/plan-state/'
}
_legacy4_regex() {
  printf '%s' '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$'
}

# A porcelain stream covering every interesting case at once.
_porcelain() {
  cat <<'EOF'
 M .aid-o/config/queue.yaml
 M .aid-o/work/audit-log.jsonl
 M .aid-o/metrics/gate-runtime-baselines.yaml
 M .aid-o/metrics/gate-runtime-baselines.yaml.lock
 M .aid-o/work/plan-state/P900/plan-state.yaml
 M .aid-o/work/plan-state
 M .aid-o/config/queue.yaml.bak
 M .aid-o/config/queue.yaml/nested.txt
 M .aid-o/work/audit-log.jsonl/foo
 M .aid-o/metrics/gate-runtime-baselines.yamlX
 M .aid-o/work/evidence/P900/R-1/delivery-report.json
 M .aid-o/reports/P900-delivery.md
 M .aid-o/metrics/other-metric.yaml
 M plugins/aid-orchestrator/scripts/aid-fsm.sh
 M docs/plans/something.md
 M README.md
EOF
}

# ─── the behaviour-neutrality contract ────────────────────────────────────

@test "P073 Step 14: --mode legacy5 filters BYTE-IDENTICALLY to the original inline regex" {
  local via_lib via_regex
  via_lib="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode legacy5')"
  via_regex="$(_porcelain | grep -vE "$(_legacy5_regex)" || true)"
  [ "$via_lib" = "$via_regex" ]
}

@test "P073 Step 14: --mode legacy4 filters BYTE-IDENTICALLY to aid-fsm.sh's four-entry variant" {
  local via_lib via_regex
  via_lib="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode legacy4')"
  via_regex="$(_porcelain | grep -vE "$(_legacy4_regex)" || true)"
  [ "$via_lib" = "$via_regex" ]
}

@test "P073 Step 14: legacy5 and legacy4 differ by EXACTLY the plan-state entry" {
  local five four
  five="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode legacy5')"
  four="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode legacy4')"
  [ "$five" != "$four" ]
  run bash -c "diff <(printf '%s\n' '$four') <(printf '%s\n' '$five') | grep -c 'plan-state'"
  [ "$output" = "1" ]
}

@test "P073 Step 14: --mode policy widens to the loaded globs" {
  local legacy policy
  legacy="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode legacy5')"
  policy="$(_porcelain | _anc 'aid_ancillary_filter_porcelain --mode policy')"
  # The evidence/report/metrics lines survive legacy5 but not policy.
  [[ "$legacy" == *"delivery-report.json"* ]]
  [[ "$policy" != *"delivery-report.json"* ]]
  [[ "$policy" != *"P900-delivery.md"* ]]
  [[ "$policy" != *"other-metric.yaml"* ]]
  # Real delivery paths survive BOTH — widening is bounded.
  [[ "$policy" == *"aid-fsm.sh"* ]]
  [[ "$policy" == *"README.md"* ]]
  [[ "$policy" == *"docs/plans/something.md"* ]]
}

@test "P073 Step 14: a MISSING --mode is a usage error, never a silent default" {
  run _anc 'aid_ancillary_filter_porcelain < /dev/null'
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires --mode"* ]]
  [[ "$output" == *"mandatory"* ]]
}

@test "P073 Step 14: an unknown --mode is refused too" {
  run _anc 'aid_ancillary_filter_porcelain --mode everything < /dev/null'
  [ "$status" -eq 2 ]
  [[ "$output" == *"got 'everything'"* ]]
}

# ─── glob matching ────────────────────────────────────────────────────────

@test "P073 Step 14: aid_ancillary_match matches an exact path and a directory prefix" {
  run _anc 'aid_ancillary_match ".aid-o/config/queue.yaml" && echo YES || echo NO'
  [ "$output" = "YES" ]
  run _anc 'aid_ancillary_match ".aid-o/work/plan-state/P900/plan-state.yaml" && echo YES || echo NO'
  [ "$output" = "YES" ]
  run _anc 'aid_ancillary_match ".aid-o/work/anything/at/all.txt" && echo YES || echo NO'
  [ "$output" = "YES" ]
}

@test "P073 Step 14: aid_ancillary_match does NOT match delivery paths" {
  local p
  for p in "plugins/aid-orchestrator/scripts/aid-fsm.sh" "README.md" "docs/plans/x.md" ".aid-o/config/execution.yaml"; do
    run _anc "aid_ancillary_match '$p' && echo YES || echo NO"
    [ "$output" = "NO" ]
  done
}

@test "P073 Step 14: the shipped policy deliberately ships NO docs/** default" {
  # Documentation is frequently part of what a plan delivers; shipping it as
  # ancillary would let a delivery change ride through a frozen review.
  # Query the LIST, not the file text — the policy's prose explains at length
  # why docs/** is absent, and a bare grep would trip over that explanation.
  run bash -c "yq -r '.plan_final.ancillary_paths[]' '$AID_PLUGIN_PATH/defaults/policies/plan-final-policy.yaml' | grep -c '^docs/' || true"
  [ "$output" = "0" ]
  run _anc 'aid_ancillary_match "docs/anything.md" && echo YES || echo NO'
  [ "$output" = "NO" ]
}

# ─── fail-closed ──────────────────────────────────────────────────────────

@test "P073 Step 14: a MALFORMED project policy falls back to the five legacy paths and warns once" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'this: is: not: valid: yaml: [\n' > "$ROOT/.aid-o/config/policies/plan-final-policy.yaml"

  run _anc 'aid_ancillary_load "."; printf "%s\n" "${_AID_ANCILLARY_PATTERNS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"falling back to the five legacy runtime paths"* ]]
  [[ "$output" == *"never widened on a read error"* ]]
  # Exactly the five, and NOT the wider globs.
  [[ "$output" == *".aid-o/work/plan-state/**"* ]]
  [[ "$output" != *".aid-o/reports/**"* ]]
}

@test "P073 Step 14: a project policy that REMOVES entries is honoured for classification" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  cat > "$ROOT/.aid-o/config/policies/plan-final-policy.yaml" <<'EOF'
schema_version: "aid-2.0"
plan_final:
  ancillary_paths:
    - ".aid-o/work/audit-log.jsonl"
EOF
  run _anc 'aid_ancillary_match ".aid-o/work/audit-log.jsonl" && echo YES || echo NO'
  [ "$output" = "YES" ]
  run _anc 'aid_ancillary_match ".aid-o/config/queue.yaml" && echo YES || echo NO'
  [ "$output" = "NO" ]
  # But the preflight callers keep the five as a FLOOR, so routine operation
  # cannot deadlock on a project removing queue.yaml.
  run bash -c "printf ' M .aid-o/config/queue.yaml\n' | $(printf '%q' bash) -c '. \"$LIB\"; cd \"$ROOT\"; aid_ancillary_filter_porcelain --mode legacy5'"
  [ -z "$output" ]
}

# ─── overlap warning ──────────────────────────────────────────────────────

@test "P073 Step 14: an overlap between a glob and a protected path warns, naming BOTH sides" {
  printf '%s\n' ".aid-o/work/evidence/P900/R-1/close-receipt.json" \
                "plugins/aid-orchestrator/scripts/aid-fsm.sh" > "$ROOT/protected.txt"
  run _anc "aid_ancillary_overlap_warn '$ROOT/protected.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ancillary glob '.aid-o/work/**' covers protected path"* ]]
  [[ "$output" == *"close-receipt.json"* ]]
  [[ "$output" == *"protected set wins"* ]]
  # A non-overlapping protected path produces no warning.
  [[ "$output" != *"aid-fsm.sh"* ]]
}

@test "P073 Step 14: overlaps are WARNED, never rejected — the shipped defaults themselves overlap" {
  # Rejecting overlap would forbid the very policy this plugin ships, because
  # close-consumed evidence lives under .aid-o/work/.
  printf '%s\n' ".aid-o/work/evidence/P900/R-1/x.json" > "$ROOT/protected.txt"
  run _anc "aid_ancillary_overlap_warn '$ROOT/protected.txt' && echo RETURNED_OK"
  [[ "$output" == *"RETURNED_OK"* ]]
}

# ─── the four call sites carry no inline copy any more ────────────────────

@test "P073 Step 14: zero inline gate-runtime-baselines regexes remain outside the shared lib" {
  run bash -c '! grep -n "gate-runtime-baselines" \
      "'"$AID_PLUGIN_PATH"'/scripts/aid-plan-fsm.sh" \
      "'"$AID_PLUGIN_PATH"'/scripts/aid-release.sh" \
      "'"$AID_PLUGIN_PATH"'/scripts/aid-fsm.sh" | grep -q "grep -vE"'
  [ "$status" -eq 0 ]
}

@test "P073 Step 14: all four call sites go through the shared filter with an explicit mode" {
  run bash -c "grep -c 'aid_ancillary_filter_porcelain --mode legacy5' '$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh'"
  [ "$output" = "2" ]
  run bash -c "grep -c 'aid_ancillary_filter_porcelain --mode legacy5' '$AID_PLUGIN_PATH/scripts/aid-release.sh'"
  [ "$output" = "1" ]
  run bash -c "grep -c 'aid_ancillary_filter_porcelain --mode legacy4' '$AID_PLUGIN_PATH/scripts/aid-fsm.sh'"
  [ "$output" = "1" ]
}

# ─── Codex-review finding on the first cut of this step ───────────────────

@test "P073 Step 14 (review finding): the legacy modes are ANCHORED — a descendant of a bare entry still blocks" {
  # The permissive directory-prefix rule silently exempted paths the old
  # anchored regexes blocked. Measured: three of them.
  local p
  for p in ".aid-o/config/queue.yaml/nested.txt" ".aid-o/work/audit-log.jsonl/foo"; do
    run bash -c "printf ' M %s\n' '$p' | $(printf '%q' bash) -c '. \"$LIB\"; aid_ancillary_filter_porcelain --mode legacy5'"
    [ -n "$output" ]   # still dirty => still blocks, as it did before
  done
}

@test "P073 Step 14 (review finding): the bare directory of a prefix entry still blocks under legacy" {
  # The old regex was `\.aid-o/work/plan-state/` — WITH the slash — so a
  # tracked file literally named `.aid-o/work/plan-state` was never exempt.
  run bash -c "printf ' M .aid-o/work/plan-state\n' | $(printf '%q' bash) -c '. \"$LIB\"; aid_ancillary_filter_porcelain --mode legacy5'"
  [ -n "$output" ]
  # While something genuinely under it is exempt, exactly as before.
  run bash -c "printf ' M .aid-o/work/plan-state/P900/x.yaml\n' | $(printf '%q' bash) -c '. \"$LIB\"; aid_ancillary_filter_porcelain --mode legacy5'"
  [ -z "$output" ]
}

@test "P073 Step 14 (review finding): POLICY mode keeps the permissive rule, which is what its globs want" {
  # The strictness applies to the legacy modes only — `.aid-o/work/**` is meant
  # to cover the subtree.
  run bash -c "printf ' M .aid-o/work/anything/deep/x.txt\n' | $(printf '%q' bash) -c '. \"$LIB\"; cd \"$ROOT\"; aid_ancillary_filter_porcelain --mode policy'"
  [ -z "$output" ]
}
