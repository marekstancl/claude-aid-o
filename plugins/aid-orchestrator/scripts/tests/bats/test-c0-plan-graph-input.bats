#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 9 — the C0 plan-review prompt must not ask the reviewer to
# analyse an artifact (the whole-plan source dependency graph) the review
# usually runs BEFORE it exists (audit-input-manifest.json records both
# graph paths as `absent_pre_generation`), and the graph file's mtime is
# routinely minutes AFTER the review it would supposedly feed.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TEMPLATE="$AID_PLUGIN_PATH/defaults/prompts/c0-plan-review-prompt-v1.md"
  RENDER="$AID_PLUGIN_PATH/scripts/lib/aid-render-prompt.sh"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

_render_with_absent_graphs() {
  local vars="$TEST_TMPDIR/vars.json"
  jq -n '{
    plan_path: "plans/P900.md",
    plan_sha256: "sha256:deadbeef",
    reviewed_head: "abc123",
    input_manifest_path: "evidence/P900/c0/codex/audit-input-manifest.json",
    input_manifest_hash: "sha256:cafef00d",
    plan_graph_path: "absent_pre_generation",
    source_plan_graph_path: "absent_pre_generation",
    contracts_paths: "[]",
    c0_evidence_paths: "[]",
    output_schema_path: "schemas/c0-plan-review.schema.json"
  }' > "$vars"
  local out="$TEST_TMPDIR/rendered.md"
  bash "$RENDER" --template "$TEMPLATE" --vars-json "$vars" --output "$out" >/dev/null || return 1
  cat "$out"
}

@test "with both graph fields absent, the rendered prompt directs the reviewer at Dependencies: blocks by name" {
  run _render_with_absent_graphs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dependencies:"* ]]
  [[ "$output" == *"Depends on:"* ]]
  [[ "$output" == *"Blocks:"* ]]
  # The cycle/unsatisfied-output analysis the graph would have driven is
  # still asked for — just sourced from the per-step blocks instead. It
  # must not merely name the blocks: it must tell the reviewer HOW to get
  # from "ordering" (what Dependencies: blocks encode) to "output" (what
  # they don't) — reading each step's own stated needs against that order.
  [[ "$output" == *"acyclic"* ]]
  [[ "$output" == *"output no earlier step produces"* ]]
  [[ "$output" == *"Objective"* ]]
  [[ "$output" == *"Files"* ]]
}

@test "the shipped prompt requires no artifact the manifest can record as absent without naming the Dependencies: substitute" {
  refute_grep -F "pre-generation authority" "$TEMPLATE"

  # Check 2 (the dependency/scope check) must name the substitute explicitly,
  # and must not itself lean on the graph being present — a regression that
  # re-requires the graph under different wording would fail this.
  run bash -c "sed -n '/^2\\. Scope & dependencies/,/^3\\./p' '$TEMPLATE'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dependencies:"* ]]
  refute_grep -qiE 'whole.plan (source )?graph|pre-generation authority' <(echo "$output")
}

@test "a manifest recording absent_pre_generation still validates (unchanged contract)" {
  # Sanity: the vars object above (both graph paths = absent_pre_generation)
  # satisfies the renderer's own string-value contract — the substitute
  # wording is a prompt-body change, not a schema/contract change.
  run _render_with_absent_graphs
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent_pre_generation"* ]]
}

@test "a graph bound to a different plan hash is still refused (this step loosens nothing about validation)" {
  # This step only touches prompt TEXT. The manifest builder's hash-binding
  # refusal and its absent-graph handling both live in aid-c0-plan-review.sh
  # and must still be there, untouched.
  local lib="$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh"
  run grep -q 'plan graph hash does not match reviewed plan' "$lib"
  [ "$status" -eq 0 ]
  run grep -q 'absent_pre_generation' "$lib"
  [ "$status" -eq 0 ]
}
