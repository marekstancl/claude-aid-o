#!/usr/bin/env bats
# test-cp1-ledger.bats — P065 E-065-7_7 Step 19: aid-cp1-ledger.sh unit tests.
#
# aid-cp1-ledger.sh is the mechanical CP1 revision-limit AUTHORITY: a
# plan_id-keyed runtime ledger at .aid-o/work/cp1-ledger/<plan_id>.yaml that
# survives normal evidence-path/verifier-identity churn. This suite proves
# each acceptance criterion from the Step 19 spec:
#   - init/increment/read/check-budget subcommands work as specified.
#   - increment is a no-op on an unchanged plan_hash, advances on a new one.
#   - check-budget is FAIL-CLOSED when CP1 evidence exists but the ledger is
#     missing or corrupt (never auto-creates a zero ledger in that case).
#   - the ledger is resilient to verifier-swap and evidence-dir-rename (its
#     path depends on plan_id ONLY).
#   - init --pre-enforcement P065 yields pre_enforcement:true, attempts:0.
#
# This suite does NOT test aid-cp1-gate.sh enforcement (unmodified, read-only
# reference) or any Step-20 gate wiring — that is out of scope here.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LEDGER="$AID_PLUGIN_PATH/scripts/lib/aid-cp1-ledger.sh"
  export LEDGER
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

# _ledger_file <plan_id>  — echoes the canonical ledger path under the test project root.
_ledger_file() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/cp1-ledger/${1}.yaml"
}

# _evidence_dir <plan_id>  — echoes the canonical CP1-deep evidence dir.
_evidence_dir() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${1}/cp1-deep"
}

# _seed_evidence <plan_id> [filename]  — writes one non-empty CP1-deep
# evidence file (partial evidence is enough to count as "not provably new").
_seed_evidence() {
  local plan_id="$1" fname="${2:-cp1-adjudicator.md}"
  local dir; dir="$(_evidence_dir "$plan_id")"
  mkdir -p "$dir"
  printf 'verdict: pass\n' > "$dir/$fname"
}

# _ledger <plan_id> <jq_filter>  — reads the ledger as JSON and applies a jq filter.
_ledger_field() {
  local plan_id="$1" filter="$2"
  bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" "$plan_id" | jq -r "$filter"
}

# ─── init ────────────────────────────────────────────────────────────────

@test "init creates a fresh ledger at attempts:0 for a provably new plan" {
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P100
  [ "$status" -eq 0 ]
  [ -f "$(_ledger_file P100)" ]
  [ "$(_ledger_field P100 '.attempts')" = "0" ]
  [ "$(_ledger_field P100 '.max')" = "3" ]
  [ "$(_ledger_field P100 '.pre_enforcement')" = "false" ]
  [ "$(_ledger_field P100 '.pm_override.present')" = "false" ]
}

@test "init (without --pre-enforcement) refuses when CP1 evidence already exists" {
  _seed_evidence P101
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P101
  [ "$status" -ne 0 ]
  [[ "$output" == *"not provably new"* ]]
  [ ! -f "$(_ledger_file P101)" ]
}

@test "init refuses when only PARTIAL CP1 evidence exists (one lens file)" {
  _seed_evidence P102 "cp1-lens-L1-behavior.md"
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P102
  [ "$status" -ne 0 ]
  [ ! -f "$(_ledger_file P102)" ]
}

@test "init --pre-enforcement P065 yields pre_enforcement:true, attempts:0, bypassing the evidence check" {
  _seed_evidence P065
  run bash "$LEDGER" init --pre-enforcement --project-root "$TEST_PROJECT_ROOT" P065
  [ "$status" -eq 0 ]
  [ "$(_ledger_field P065 '.pre_enforcement')" = "true" ]
  [ "$(_ledger_field P065 '.attempts')" = "0" ]
  [ "$(_ledger_field P065 '.plan_id')" = "P065" ]
}

@test "init never overwrites an existing ledger (no silent reset via double-init)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P103
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P103 sha256:aaa >/dev/null
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P103
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
  # attempts must still be 1 — untouched by the refused re-init.
  [ "$(_ledger_field P103 '.attempts')" = "1" ]
}

@test "init rejects a path-traversal plan_id" {
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" "../../etc/passwd"
  [ "$status" -ne 0 ]
}

# ─── increment ───────────────────────────────────────────────────────────

@test "increment with a new plan_hash advances attempts 0 -> 1 -> 2" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P110
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P110 sha256:aaa >/dev/null
  [ "$(_ledger_field P110 '.attempts')" = "1" ]
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P110 sha256:bbb >/dev/null
  [ "$(_ledger_field P110 '.attempts')" = "2" ]
  [ "$(_ledger_field P110 '.attempts_log | length')" = "2" ]
  [ "$(_ledger_field P110 '.attempts_log[-1].plan_hash')" = "sha256:bbb" ]
}

@test "increment with an unchanged plan_hash is a no-op (neither advances nor resets)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P111
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P111 sha256:aaa >/dev/null
  local before; before="$(_ledger_field P111 '.updated_at')"
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P111 sha256:aaa
  [ "$status" -eq 0 ]
  [ "$(_ledger_field P111 '.attempts')" = "1" ]
  [ "$(_ledger_field P111 '.attempts_log | length')" = "1" ]
  [ "$(_ledger_field P111 '.updated_at')" = "$before" ]
}

@test "increment records codex_session when provided" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P112
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" --codex-session "sess-1" P112 sha256:aaa >/dev/null
  [ "$(_ledger_field P112 '.attempts_log[-1].codex_session')" = "sess-1" ]
}

@test "increment never auto-creates a ledger (fails when ledger missing)" {
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P113 sha256:aaa
  [ "$status" -ne 0 ]
  [ ! -f "$(_ledger_file P113)" ]
}

@test "increment fails closed on a corrupt ledger (does not repair or reset it)" {
  mkdir -p "$(dirname "$(_ledger_file P114)")"
  printf '{{{ not valid yaml :::\n' > "$(_ledger_file P114)"
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P114 sha256:aaa
  [ "$status" -ne 0 ]
  # corrupt file must be left untouched, not silently rewritten.
  run cat "$(_ledger_file P114)"
  [[ "$output" == *"not valid yaml"* ]]
}

# ─── read ────────────────────────────────────────────────────────────────

@test "read fails when the ledger is missing" {
  run bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P120
  [ "$status" -ne 0 ]
}

@test "read fails when the ledger is corrupt" {
  mkdir -p "$(dirname "$(_ledger_file P121)")"
  printf 'attempts: "not-a-number"\n' > "$(_ledger_file P121)"
  run bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P121
  [ "$status" -ne 0 ]
}

# ─── check-budget ────────────────────────────────────────────────────────

@test "check-budget reports available when attempts < max" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P130
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P130 sha256:aaa >/dev/null
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P130
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq -r '.status')" == "available" ]]
  [[ "$(echo "$output" | jq -r '.attempts')" == "1" ]]
}

@test "check-budget reports exhausted when attempts >= max and no pm_override" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P131
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P131 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P131 sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P131 sha256:ccc >/dev/null
  [ "$(_ledger_field P131 '.attempts')" = "3" ]
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P131
  [ "$status" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.status')" == "exhausted" ]]
}

@test "check-budget ignores pm_override.present field; it is NOT honored as a bypass" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P132
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P132 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P132 sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P132 sha256:ccc >/dev/null
  # At this point, attempts=3 and max=3, so budget is exhausted.
  # Simulate an out-of-band ledger-internal override (no dedicated setter subcommand per spec).
  local lf; lf="$(_ledger_file P132)"
  yq -i '.pm_override.present = true | .pm_override.ref = "pm-decision-2026-07-18"' "$lf"
  # Even with pm_override.present set to true, the budget check must still
  # report exhausted — the ONLY sanctioned override is the gate-level
  # cp1-pm-escalation-override.json artifact, not the ledger-internal field.
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P132
  [ "$status" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.status')" == "exhausted" ]]
  [[ "$(echo "$output" | jq -r '.pm_override')" == "false" ]]
}

@test "check-budget is FAIL-CLOSED (init_required) when CP1 evidence exists but ledger is missing" {
  _seed_evidence P133
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P133
  [ "$status" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.status')" == "init_required" ]]
  [[ "$(echo "$output" | jq -r '.evidence_present')" == "true" ]]
}

@test "check-budget is FAIL-CLOSED (init_required) when the ledger is corrupt, regardless of evidence" {
  mkdir -p "$(dirname "$(_ledger_file P134)")"
  printf 'not: [valid, {yaml\n' > "$(_ledger_file P134)"
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P134
  [ "$status" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.status')" == "init_required" ]]
}

@test "check-budget reports not_initialized (exit 2) for a genuinely new plan (no ledger, no evidence)" {
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P135
  [ "$status" -eq 2 ]
  [[ "$(echo "$output" | jq -r '.status')" == "not_initialized" ]]
  [[ "$(echo "$output" | jq -r '.evidence_present')" == "false" ]]
}

# ─── edge cases (explicitly required by the Step 19 spec) ─────────────────

@test "edge case: verifier agent swapped mid-cycle does not change the ledger count (plan_id-keyed only)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P140
  _seed_evidence P140 "verifier-output-cp1-verifier-a.md"
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P140 sha256:aaa >/dev/null
  [ "$(_ledger_field P140 '.attempts')" = "1" ]

  # Swap the verifier identity: remove verifier A's artifact, install verifier B's.
  rm -f "$(_evidence_dir P140)/verifier-output-cp1-verifier-a.md"
  _seed_evidence P140 "verifier-output-cp1-verifier-b.md"

  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P140 sha256:bbb >/dev/null
  [ "$(_ledger_field P140 '.attempts')" = "2" ]
  [ "$(_ledger_field P140 '.plan_id')" = "P140" ]

  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P140
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq -r '.attempts')" == "2" ]]
}

@test "edge case: evidence dir renamed/rotated does not change the ledger count (path is plan_id-keyed)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P141
  _seed_evidence P141
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P141 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P141 sha256:bbb >/dev/null
  [ "$(_ledger_field P141 '.attempts')" = "2" ]

  # Rotate/rename the evidence dir — the ledger path itself never referenced it.
  mv "$(_evidence_dir P141)" "$TEST_PROJECT_ROOT/.aid-o/work/evidence/P141/cp1-deep.rotated-$(date +%s)"

  [ "$(_ledger_field P141 '.attempts')" = "2" ]
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P141
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq -r '.attempts')" == "2" ]]
}

@test "edge case: ledger deleted with CP1 evidence present is fail-closed, NOT a silent reset" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P142
  _seed_evidence P142
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P142 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P142 sha256:bbb >/dev/null
  [ "$(_ledger_field P142 '.attempts')" = "2" ]

  rm -f "$(_ledger_file P142)"

  # check-budget must fail closed, not silently report a fresh attempts:0 state.
  run bash "$LEDGER" check-budget --project-root "$TEST_PROJECT_ROOT" P142
  [ "$status" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.status')" == "init_required" ]]

  # A plain re-init must also refuse (evidence still present) — no reset path via init either.
  run bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P142
  [ "$status" -ne 0 ]
  [ ! -f "$(_ledger_file P142)" ]
}

# ─── FINDING 2 (E-065-7_7 dispatch integration) ───────────────────────────

@test "FINDING 2: increment rejects a new hash when budget is exhausted (attempts >= max)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P150
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P150 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P150 sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P150 sha256:ccc >/dev/null
  [ "$(_ledger_field P150 '.attempts')" = "3" ]
  [ "$(_ledger_field P150 '.max')" = "3" ]

  # At this point, attempts == max, budget is exhausted. Attempt to increment
  # with a NEW hash (different from the last recorded one).
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P150 sha256:ddd
  [ "$status" -ne 0 ]
  [[ "$output" == *"budget exhausted"* ]]

  # Proof: ledger must be byte-for-byte unchanged (attempts still 3, log still has 3 entries).
  [ "$(_ledger_field P150 '.attempts')" = "3" ]
  [ "$(_ledger_field P150 '.attempts_log | length')" = "3" ]
}

@test "FINDING 2: increment with unchanged hash at max is still a no-op (not budget-gated)" {
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" P151
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P151 sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P151 sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P151 sha256:ccc >/dev/null
  [ "$(_ledger_field P151 '.attempts')" = "3" ]

  # At max budget, but re-running with the SAME last hash is a no-op and must
  # NOT be rejected (the design intent: only NEW hashes trigger budget checks).
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" P151 sha256:ccc
  [ "$status" -eq 0 ]

  # Proof: attempts still 3, log still has 3 entries (no new entry added).
  [ "$(_ledger_field P151 '.attempts')" = "3" ]
  [ "$(_ledger_field P151 '.attempts_log | length')" = "3" ]
}
