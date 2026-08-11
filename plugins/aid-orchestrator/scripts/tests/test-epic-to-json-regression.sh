#!/usr/bin/env bash
# aid-tier: t2
# =============================================================================
# test-epic-to-json-regression.sh — Golden snapshot regression for aid-epic-to-json.sh
#
# Verifies that the plan-graph lib refactor produces IDENTICAL plan.json output
# compared to the golden snapshot captured before the refactor.
#
# Usage:
#   ./test-epic-to-json-regression.sh
#
# First-run mode: if golden dir is absent, generates it from current output.
# Exit: 0 all pass, 1 any fail
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-epic-to-json.sh"
SCHEMA_FILE="$REPO_ROOT/plugins/aid-orchestrator/defaults/templates/plan.schema.json"
GOLDEN_DIR="$SCRIPT_DIR/fixtures/epic-to-json-golden"
FIXTURE_MINIMAL="$SCRIPT_DIR/fixtures/E-TEST-001-1_1-minimal-test-plan.md"
FIXTURE_CYCLE="$SCRIPT_DIR/fixtures/E-TEST-003-1_1-circular-deps.md"
FIXTURE_STEP_SCOPING="$SCRIPT_DIR/fixtures/E-TEST-005-1_1-step-scoping-repro.md"
FIXTURE_VERB_STRIP="$SCRIPT_DIR/fixtures/E-TEST-006-1_1-test-rewrite-verbs.md"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  echo "ERROR: Script not found: $SCRIPT_UNDER_TEST" >&2
  exit 1
fi
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: Schema not found: $SCHEMA_FILE" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_MINIMAL" ]]; then
  echo "ERROR: Minimal fixture not found: $FIXTURE_MINIMAL" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_CYCLE" ]]; then
  echo "ERROR: Cycle fixture not found: $FIXTURE_CYCLE" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_STEP_SCOPING" ]]; then
  echo "ERROR: Step-scoping repro fixture not found: $FIXTURE_STEP_SCOPING" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_VERB_STRIP" ]]; then
  echo "ERROR: Verb-strip fixture not found: $FIXTURE_VERB_STRIP" >&2
  exit 1
fi

echo "=== test-epic-to-json-regression.sh ==="
echo "Script: $SCRIPT_UNDER_TEST"
echo "Golden: $GOLDEN_DIR"
echo ""

# ---------------------------------------------------------------------------
# Helper: run script on a fixture, return path to plan.json
# ---------------------------------------------------------------------------
run_on_fixture() {
  local fixture="$1"
  local out_dir="$2"
  local result
  result="$(bash "$SCRIPT_UNDER_TEST" \
    --epic "$fixture" \
    --schema "$SCHEMA_FILE" \
    --output-dir "$out_dir" 2>/dev/null)"
  echo "$result" | jq -r '.plan_json'
}

# ---------------------------------------------------------------------------
# First-run mode: generate golden snapshots if directory absent
# ---------------------------------------------------------------------------
if [[ ! -d "$GOLDEN_DIR" ]]; then
  # A missing golden directory is a BROKEN CHECKOUT, not an invitation to mint
  # a baseline. The goldens are committed; if they are not here, something is
  # wrong with this tree — and silently recording whatever the code currently
  # produces means a refactor that broke the output gets enshrined as correct,
  # while the suite reports "0/0 run" and exits 0, which reads exactly like a
  # clean pass.
  #
  # Regenerating is still possible, but it now has to be asked for by a person
  # who means it.
  if [[ "${AID_REGENERATE_GOLDEN:-0}" != "1" ]]; then
    echo "ERROR: golden directory '$GOLDEN_DIR' is missing." >&2
    echo "       The goldens are committed, so this is a broken checkout." >&2
    echo "       This suite refuses to mint a baseline from the current output —" >&2
    echo "       that would record a broken refactor as the expected result." >&2
    echo "       If you genuinely intend to regenerate: AID_REGENERATE_GOLDEN=1 $0" >&2
    echo "Results: 0/1 passed, 1 failed"
    exit 1
  fi
  echo "Golden directory not found — regenerating on explicit request (AID_REGENERATE_GOLDEN=1)."
  mkdir -p "$GOLDEN_DIR"

  out_dir="$TMPDIR_ROOT/gen-minimal"
  mkdir -p "$out_dir"
  plan_path="$(run_on_fixture "$FIXTURE_MINIMAL" "$out_dir")"
  if [[ -z "$plan_path" || ! -f "$plan_path" ]]; then
    echo "ERROR: Failed to generate output for minimal fixture." >&2
    exit 1
  fi
  # Save golden without the timestamp field (it changes each run)
  jq -S 'del(.created_at)' "$plan_path" > "$GOLDEN_DIR/minimal-plan.golden.json"

  echo "Generated golden snapshot: $GOLDEN_DIR/minimal-plan.golden.json"
  echo ""
  echo "Results: 0/0 run, 0 passed, 0 failed (REGENERATED — this run verified nothing)"
  exit 0
fi

# ---------------------------------------------------------------------------
# T1: Minimal fixture — plan.json matches golden (keys-sorted, no timestamp)
# ---------------------------------------------------------------------------
echo "TEST: T1 — Minimal fixture output matches golden snapshot"
{
  t1_out="$TMPDIR_ROOT/t1"
  mkdir -p "$t1_out"
  plan_path="$(run_on_fixture "$FIXTURE_MINIMAL" "$t1_out")"
  if [[ -z "$plan_path" || ! -f "$plan_path" ]]; then
    _fail "T1: script failed to produce plan.json"
  else
    actual="$(jq -S 'del(.created_at)' "$plan_path")"
    expected="$(jq -S '.' "$GOLDEN_DIR/minimal-plan.golden.json")"
    if diff_out="$(diff <(echo "$expected") <(echo "$actual") 2>&1)"; then
      _pass "T1: plan.json matches golden (keys sorted, timestamp excluded)"
    else
      _fail "T1: plan.json differs from golden"
      echo "--- diff (expected vs actual) ---"
      echo "$diff_out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# T2: Minimal fixture — two consecutive runs produce identical output
#     (determinism check for topological_order)
# ---------------------------------------------------------------------------
echo "TEST: T2 — Two runs on minimal fixture produce identical output (determinism)"
{
  t2a_out="$TMPDIR_ROOT/t2a"
  t2b_out="$TMPDIR_ROOT/t2b"
  mkdir -p "$t2a_out" "$t2b_out"
  plan_a="$(run_on_fixture "$FIXTURE_MINIMAL" "$t2a_out")"
  plan_b="$(run_on_fixture "$FIXTURE_MINIMAL" "$t2b_out")"
  if [[ -z "$plan_a" || ! -f "$plan_a" || -z "$plan_b" || ! -f "$plan_b" ]]; then
    _fail "T2: one or both runs failed to produce plan.json"
  else
    actual_a="$(jq -S 'del(.created_at)' "$plan_a")"
    actual_b="$(jq -S 'del(.created_at)' "$plan_b")"
    if diff_out="$(diff <(echo "$actual_a") <(echo "$actual_b") 2>&1)"; then
      _pass "T2: two consecutive runs produce identical output"
    else
      _fail "T2: runs differ (non-deterministic output)"
      echo "--- diff (run 1 vs run 2) ---"
      echo "$diff_out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# T3: Cycle fixture — exits non-zero with "Circular dependency" in stderr
# ---------------------------------------------------------------------------
echo "TEST: T3 — Cycle fixture exits non-zero with circular dependency error"
{
  t3_out="$TMPDIR_ROOT/t3"
  mkdir -p "$t3_out"
  stderr_out="$TMPDIR_ROOT/t3-stderr.txt"
  AID_ALLOW_SPARSE_AC=1 bash "$SCRIPT_UNDER_TEST" \
    --epic "$FIXTURE_CYCLE" \
    --schema "$SCHEMA_FILE" \
    --output-dir "$t3_out" \
    >"$TMPDIR_ROOT/t3-stdout.txt" 2>"$stderr_out"
  exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    if grep -q "Circular dependency" "$stderr_out"; then
      _pass "T3: cycle fixture exits $exit_code and stderr contains 'Circular dependency'"
    else
      _fail "T3: exits non-zero but stderr missing 'Circular dependency' — got: $(cat "$stderr_out")"
    fi
  else
    _fail "T3: cycle fixture should exit non-zero but exited 0"
  fi
}

# ---------------------------------------------------------------------------
# T4: ui_change_contract round-trip — steps[0].ui_change_contract non-null
# ---------------------------------------------------------------------------
echo "TEST: T4 — ui_change_contract envelope round-trip"
{
  FIXTURE_UI_CONTRACT="$SCRIPT_DIR/fixtures/epic-to-json-golden/ui-contract-plan/epic.md"
  EXPECTED_UI_CONTRACT="$SCRIPT_DIR/fixtures/epic-to-json-golden/ui-contract-plan/expected.json"

  if [[ ! -f "$FIXTURE_UI_CONTRACT" ]]; then
    _fail "T4 — fixture missing: $FIXTURE_UI_CONTRACT"
  elif [[ ! -f "$EXPECTED_UI_CONTRACT" ]]; then
    _fail "T4 — expected.json missing: $EXPECTED_UI_CONTRACT"
  else
    t4_out="$TMPDIR_ROOT/t4"
    mkdir -p "$t4_out"
    t4_plan="$(run_on_fixture "$FIXTURE_UI_CONTRACT" "$t4_out")"

    if [[ -z "$t4_plan" || ! -f "$t4_plan" ]]; then
      _fail "T4 — aid-epic-to-json.sh failed on ui-contract fixture"
    else
      # Check that steps[0].ui_change_contract is non-null
      step0_contract="$(jq -r '.steps[0].ui_change_contract' "$t4_plan")"
      if [[ "$step0_contract" == "null" || -z "$step0_contract" ]]; then
        _fail "T4 — steps[0].ui_change_contract is null (expected non-null)"
      else
        # Verify specific fields match expected.json
        contract_path="$(jq -r '.steps[0].ui_change_contract.path' "$t4_plan")"
        contract_sha="$(jq -r '.steps[0].ui_change_contract.sha256' "$t4_plan")"
        contract_schema="$(jq -r '.steps[0].ui_change_contract.schema_version' "$t4_plan")"

        expected_path="$(jq -r '.steps[0].ui_change_contract.path' "$EXPECTED_UI_CONTRACT")"
        expected_sha="$(jq -r '.steps[0].ui_change_contract.sha256' "$EXPECTED_UI_CONTRACT")"
        expected_schema="$(jq -r '.steps[0].ui_change_contract.schema_version' "$EXPECTED_UI_CONTRACT")"

        if [[ "$contract_path" == "$expected_path" && "$contract_sha" == "$expected_sha" && "$contract_schema" == "$expected_schema" ]]; then
          _pass "T4 — ui_change_contract round-trip: path/sha256/schema_version match"
        else
          _fail "T4 — ui_change_contract mismatch. Got: path=$contract_path sha256=$contract_sha schema=$contract_schema | Expected: path=$expected_path sha256=$expected_sha schema=$expected_schema"
        fi
      fi
    fi
  fi
}

# ---------------------------------------------------------------------------
# T5 — Per-step scoping repro (P058 Step 1, RED before the Step 2-3 fix)
#
# E-TEST-005 has 2 steps (backend, qa) with genuinely distinct Files/AC.
# Today aid-epic-to-json.sh broadcasts the flat `## Artifacts` and
# `## Scope > Allowed files/paths` sections to EVERY step, and its AC
# delimiter (`IFS='|||'`) collides with any literal `|` inside AC text. All
# 4 asserts below are expected to FAIL against the current (unfixed)
# generator — that is the point of this test: it freezes the bug as a
# reproducible red state ahead of the P058 Step 2-3 fix.
# ---------------------------------------------------------------------------
echo "TEST: T5 — Per-step scoping repro (E-TEST-005)"
{
  t5_out="$TMPDIR_ROOT/t5"
  mkdir -p "$t5_out"
  t5_plan="$(run_on_fixture "$FIXTURE_STEP_SCOPING" "$t5_out")"

  if [[ -z "$t5_plan" || ! -f "$t5_plan" ]]; then
    _fail "T5a — aid-epic-to-json.sh failed on step-scoping fixture"
    _fail "T5b — aid-epic-to-json.sh failed on step-scoping fixture"
    _fail "T5c — aid-epic-to-json.sh failed on step-scoping fixture"
    _fail "T5d — aid-epic-to-json.sh failed on step-scoping fixture"
  else
    # T5a: steps[].outputs must NOT be identical across steps (backend step 1
    # has 3 files, qa step 2 has 2 files — they must differ). Today both
    # steps get the full 5-entry EPIC-wide artifact union, so this fails.
    outputs_step0="$(jq -c '.steps[0].outputs' "$t5_plan")"
    outputs_step1="$(jq -c '.steps[1].outputs' "$t5_plan")"
    if [[ "$outputs_step0" != "$outputs_step1" ]]; then
      _pass "T5a — steps[].outputs are NOT identical across steps (per-step scoped)"
    else
      _fail "T5a — steps[].outputs ARE identical across steps (broadcast bug): $outputs_step0"
    fi

    # T5b: count of acceptance_criteria per step must equal the count of
    # source AC bullets for that role (backend=2, qa=2). qa's first bullet
    # contains a literal jq pipe `|`, which the current IFS='|||' delimiter
    # incorrectly splits into an extra fragment (backend has no `|`, so it
    # is unaffected and should already pass).
    backend_ac_count="$(jq '.steps[0].acceptance_criteria | length' "$t5_plan")"
    qa_ac_count="$(jq '.steps[1].acceptance_criteria | length' "$t5_plan")"
    if [[ "$backend_ac_count" -eq 2 && "$qa_ac_count" -eq 2 ]]; then
      _pass "T5b — acceptance_criteria count matches source bullets (backend=2, qa=2, no pipe-split fragments)"
    else
      _fail "T5b — acceptance_criteria count mismatch (pipe-split fragment): backend=$backend_ac_count (want 2), qa=$qa_ac_count (want 2)"
    fi

    # T5c: allowed_paths entries must be path-like — no prose, no trailing
    # sentence, no unstripped multi-path "+" join. Today the Scope-derived
    # multi-path/prose entry survives as one unsplit blob, which fails this.
    bad_paths="$(jq -r '
      [.steps[].allowed_paths[]] | unique | .[]
      | select(test("^[A-Za-z0-9_./-]+$") | not)
    ' "$t5_plan")"
    if [[ -z "$bad_paths" ]]; then
      _pass "T5c — allowed_paths entries are all path-like (no prose/trailing sentence)"
    else
      _fail "T5c — allowed_paths contain non-path-like entries: $(echo "$bad_paths" | tr '\n' '|')"
    fi

    # T5d: the multi-path "`a` + `b`" Files/Scope entry must produce BOTH
    # paths as separate allowed_paths entries — the second path must not be
    # silently dropped or left merged into the first.
    has_root_changelog="$(jq -r '[.steps[].allowed_paths[]] | index("CHANGELOG.md")' "$t5_plan")"
    has_plugin_changelog="$(jq -r '[.steps[].allowed_paths[]] | index("plugins/aid-orchestrator/CHANGELOG.md")' "$t5_plan")"
    if [[ "$has_root_changelog" != "null" && "$has_plugin_changelog" != "null" ]]; then
      _pass "T5d — multi-path Files entry preserved as two separate allowed_paths entries"
    else
      _fail "T5d — multi-path Files entry NOT preserved as two separate paths (root_idx=$has_root_changelog, plugin_idx=$has_plugin_changelog)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# T6 — Files-verb strip (v2.57.2): Create/Modify/Test/Rewrite all strip to
# bare path-like allowed_paths entries. Before v2.57.2 only Create/Modify were
# stripped, so Test:/Rewrite: entries survived as non-path-like blobs and broke
# the pipeline allowed_paths_shape contract.
# ---------------------------------------------------------------------------
echo "TEST: T6 — Files-verb strip (Create/Modify/Test/Rewrite) (E-TEST-006)"
{
  t6_out="$TMPDIR_ROOT/t6"
  mkdir -p "$t6_out"
  t6_plan="$(run_on_fixture "$FIXTURE_VERB_STRIP" "$t6_out")"

  if [[ -z "$t6_plan" || ! -f "$t6_plan" ]]; then
    _fail "T6a — aid-epic-to-json.sh failed on verb-strip fixture"
    _fail "T6b — aid-epic-to-json.sh failed on verb-strip fixture"
  else
    # T6a: NO allowed_paths entry may retain a Files verb label. Any residual
    # "Test:"/"Rewrite:"/"Create:"/"Modify:" prefix means the strip missed it.
    labelled="$(jq -r '
      [.steps[].allowed_paths[]] | unique | .[]
      | select(test("^(Create|Modify|Test|Rewrite):"))
    ' "$t6_plan")"
    if [[ -z "$labelled" ]]; then
      _pass "T6a — no allowed_paths entry retains a Create/Modify/Test/Rewrite label"
    else
      _fail "T6a — allowed_paths retain verb labels: $(echo "$labelled" | tr '\n' '|')"
    fi

    # T6b: the Test:- and Rewrite:-labelled paths must appear as bare paths.
    has_test_path="$(jq -r '[.steps[].allowed_paths[]] | index("tests/test_module.py")' "$t6_plan")"
    has_rewrite_path="$(jq -r '[.steps[].allowed_paths[]] | index("src/core/legacy.py")' "$t6_plan")"
    if [[ "$has_test_path" != "null" && "$has_rewrite_path" != "null" ]]; then
      _pass "T6b — Test:/Rewrite: paths present as bare paths (tests/test_module.py, src/core/legacy.py)"
    else
      _fail "T6b — Test:/Rewrite: bare paths missing (test_idx=$has_test_path, rewrite_idx=$has_rewrite_path)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((PASS + FAIL))
echo ""
echo "Results: $total/$total run, $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
