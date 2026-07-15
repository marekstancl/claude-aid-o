#!/usr/bin/env bats
# test-pipeline-c3-dispatch.bats — E-065-3_7 Step 10 (17e grounding) for the
# pipeline.md DONE-review rewiring: `c3` mode now drives the deterministic bridge
# `aid-c3-dispatch.sh` (build-manifest → dispatch → verify) instead of an
# in-process Claude `Agent()`; `legacy_health` stays on the Claude auditor.
#
# What this suite proves (and what it deliberately does NOT):
#   pipeline.md is a PROSE protocol the orchestrating LLM reads and follows — it
#   is not an executable script, so there is nothing to "run". The failure mode
#   this guards against is prose citing a FICTIONAL interface: an
#   `aid-c3-dispatch.sh <subcommand>` that does not exist, or a call whose arg
#   shape the real script would reject. So every assertion below is grounded:
#     (1) every subcommand pipeline.md cites is a REAL subcommand of the actual
#         aid-c3-dispatch.sh (truth derived from the script's own usage(), not a
#         hardcoded list), and
#     (2) the arg shape each citation implies matches what the real script
#         enforces — proven by executing the real script with wrong/edge args
#         and observing its precondition failures.
#   AC1/AC2 additionally lock the prose instructions themselves (c3 → bridge +
#   NO Agent() for the audit; legacy_health → Agent(agents/auditor.md);
#   producer hook → build-manifest).

load test-helpers.bash

# flat_pipeline — pipeline.md with newlines/indentation collapsed to single
# spaces, so assertions can match phrases that wrap across lines in the prose.
flat_pipeline() {
  tr '\n' ' ' < "$PIPELINE_MD" | tr -s ' '
}

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PIPELINE_MD="$AID_PLUGIN_PATH/skills/pipeline.md"
  export PIPELINE_MD
  DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  export DISPATCH
  [ -f "$PIPELINE_MD" ] || { echo "missing pipeline.md: $PIPELINE_MD" >&2; return 1; }
  [ -f "$DISPATCH" ]    || { echo "missing aid-c3-dispatch.sh: $DISPATCH" >&2; return 1; }
}

# real_subcommands — the set of subcommands the ACTUAL script exposes, derived
# from its usage() heredoc (2-space-indented "  <name> <args...>" lines). Truth
# comes from the script, never from a list maintained in this test.
real_subcommands() {
  bash "$DISPATCH" --help | grep -oE '^  [a-z][a-z-]+ ' | tr -d ' ' | sort -u
}

# cited_subcommands — every subcommand pipeline.md invokes via the bridge, i.e.
# the token following `aid-c3-dispatch.sh` (with or without a closing quote).
cited_subcommands() {
  grep -oE 'aid-c3-dispatch\.sh"? +[a-z][a-z-]+' "$PIPELINE_MD" \
    | sed -E 's/.*[[:space:]]+//' | sort -u
}

# ─── 17e core: no fictional interface ───────────────────────────────────────

@test "grounding: pipeline.md cites at least one aid-c3-dispatch.sh subcommand" {
  run cited_subcommands
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "17e: every aid-c3-dispatch.sh subcommand cited in pipeline.md is REAL" {
  local real cited c
  real="$(real_subcommands)"
  cited="$(cited_subcommands)"
  # Sanity: the real set is non-empty and is exactly the three implemented cmds.
  [ -n "$real" ]
  echo "$real" | grep -qx "build-manifest"
  echo "$real" | grep -qx "dispatch"
  echo "$real" | grep -qx "verify"
  # Core assertion: cited ⊆ real. Any cited token absent from the real set is a
  # fictional-interface citation and fails here.
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    echo "$real" | grep -qx "$c" \
      || { echo "pipeline.md cites non-existent subcommand: '$c' (real: $real)" >&2; return 1; }
  done <<< "$cited"
}

@test "17e (contrast): a fictional subcommand is genuinely rejected by the script" {
  # Proves the grounding above is meaningful: the script does NOT silently accept
  # arbitrary subcommands, so ⊆-real is a real constraint.
  run bash "$DISPATCH" totally-not-a-real-subcommand
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "grounding: pipeline.md cites all three of build-manifest, dispatch, verify" {
  local cited
  cited="$(cited_subcommands)"
  echo "$cited" | grep -qx "build-manifest"
  echo "$cited" | grep -qx "dispatch"
  echo "$cited" | grep -qx "verify"
}

# ─── arg-shape grounding: prose signature == enforced signature ─────────────

@test "grounding: build-manifest signature matches prose (4 positional args)" {
  # Prose cites the 4-arg signature explicitly.
  grep -qF 'build-manifest <evidence_dir> <base_sha> <head_sha> <risk_profile>' "$PIPELINE_MD"
  flat_pipeline | grep -qE 'build-manifest .*exactly 4 positional args'
  # Real script enforces exactly 4: 3 args is rejected with the matching message.
  run bash "$DISPATCH" build-manifest a b c
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires exactly 4 args"* ]]
}

@test "grounding: dispatch signature matches prose (1 positional arg)" {
  grep -qE 'dispatch <evidence_dir>' "$PIPELINE_MD"
  grep -qE 'dispatch.*exactly 1 positional arg' "$PIPELINE_MD"
  # Real script enforces exactly 1: 0 args is rejected with the matching message.
  run bash "$DISPATCH" dispatch
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires exactly 1 arg"* ]]
}

@test "grounding: verify signature matches prose ([--reference] <evidence_dir>)" {
  grep -qF 'verify [--reference] <evidence_dir>' "$PIPELINE_MD"
  # Real script: missing evidence_dir → usage string mentioning the same signature.
  run bash "$DISPATCH" verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"verify [--reference] <evidence_dir>"* ]]
  # And --reference is a genuinely accepted leading flag (not "unknown flag");
  # it fails later on the missing evidence_dir, proving the flag itself parsed.
  run bash "$DISPATCH" verify --reference
  [ "$status" -ne 0 ]
  [[ "$output" != *"unknown flag"* ]]
}

# ─── AC1: Auditor dispatch — c3 uses the bridge, NOT Agent(); legacy_health keeps Agent() ──

@test "AC1: pipeline.md c3 branch instructs dispatch + verify via the bridge" {
  grep -qE 'aid-c3-dispatch\.sh"? +dispatch "\$evidence_dir"' "$PIPELINE_MD"
  grep -qE 'aid-c3-dispatch\.sh"? +verify +"\$evidence_dir"' "$PIPELINE_MD"
}

@test "AC1: pipeline.md c3 branch explicitly forbids Agent() for the audit" {
  # The c3 branch must say NOT to call Agent(agents/auditor.md) for the audit.
  flat_pipeline | grep -qE 'Do NOT call `?Agent\(agents/auditor\.md\)'
  grep -qE 'NO `?Agent\(\)`? for the audit' "$PIPELINE_MD"
}

@test "AC1: pipeline.md legacy_health branch still instructs Agent(agents/auditor.md)" {
  # The legacy_health bullet still routes the audit through the Claude sub-agent.
  grep -qE 'legacy_health.*UNCHANGED' "$PIPELINE_MD"
  grep -q 'agents/auditor.md' "$PIPELINE_MD"
  grep -q "\`Agent()\` tool call in \`legacy_health\`" "$PIPELINE_MD"
}

@test "AC1: pipeline.md documents unverifiable-on-exit-2 with no fallback path" {
  grep -qiE 'exit 2' "$PIPELINE_MD"
  grep -qiE 'unverifiable' "$PIPELINE_MD"
  grep -qiE 'no fallback' "$PIPELINE_MD"
  # Never substitutes the Claude auditor for a c3 pass.
  flat_pipeline | grep -qE 'never substitutes the Claude auditor for a `?c3`? pass'
}

# ─── AC2: producer hook now calls build-manifest ────────────────────────────

@test "AC2: pipeline.md producer hook instructs aid-c3-dispatch.sh build-manifest" {
  grep -qE 'aid-c3-dispatch\.sh"? +build-manifest' "$PIPELINE_MD"
  # And frames it as the producer hook (not the old hand-assembled JSON).
  grep -qE 'C3 producer hook' "$PIPELINE_MD"
}

# ─── PM summary surfaces independence levels ────────────────────────────────

@test "PM summary surfaces independence_level / required_independence_level" {
  grep -qE 'independence_level' "$PIPELINE_MD"
  grep -qE 'required_independence_level' "$PIPELINE_MD"
  # And documents that under enforcement: observe the unverifiable verdict is advisory.
  grep -qiE 'enforcement: observe' "$PIPELINE_MD"
  grep -qiE 'advisory' "$PIPELINE_MD"
}
