#!/usr/bin/env bats
# aid-tier: t1
# test-aid-gate-runtime-baseline.bats — P063 Step 1: aid-gate-runtime-baseline.sh
# (Gate Runtime Baselines EPIC). Owns AC1-AC5, AC12, AC13's tests directly, per
# the plan's Step 1 file list (Step 1 is the single source of truth all later
# steps depend on, so its own correctness is proven here, not three steps later).
#
# Harness style: source the library directly (matches how aid-run-gates.sh will
# consume it — "source .../lib/aid-gate-runtime-baseline.sh" — rather than the
# CLI dispatch some sibling libs expose for simple single-arg helpers). Each
# test points AID_GATE_BASELINE_FILE at an isolated per-test tmp file so no
# test depends on git or a real .aid-o/ tree (out of scope for this library —
# Step 2 owns aid-run-gates.sh wiring and the gitignore backfill).
#
# Covers:
#   AC1  — first-ever run creates a fresh entry, samples_count: 1
#   AC2  — repeated run (same fingerprint) updates p50/p95/max, increments samples_count
#   AC3  — command-template fingerprint change resets the series
#   AC4  — censored (timeout) samples excluded from percentiles; all-censored -> insufficient data
#   AC5  — run_mode_recommended "background" only once non_censored_samples_count >= 5 and p95 > 10min
#   AC12 — mid-write crash never corrupts the real file; separate corrupted-file-on-disk fixture
#   AC13 — gate_name (not a fingerprint) is the real lookup key; two gates never collide

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gate-runtime-baseline.sh"
  export LIB
  WORK="$(mktemp -d)"
  export WORK
  export AID_GATE_BASELINE_FILE="$WORK/gate-runtime-baselines.yaml"
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# ─── AC1: first-ever run creates a fresh entry with samples_count: 1 ────────
@test "AC1: first-ever run of a gate (file absent) creates a fresh entry with samples_count 1" {
  # Explicitly absent — not just "happens to not exist yet".
  [ ! -e "$AID_GATE_BASELINE_FILE" ]

  gate_baseline_update "gate_a" "echo hi" "echo hi" 0 1200 60

  [ -f "$AID_GATE_BASELINE_FILE" ]
  run yq '.gates.gate_a.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run yq '.gates.gate_a.non_censored_samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  run yq '.gates.gate_a.last_attempt_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "pass" ]
  run yq '.gates.gate_a.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "none" ]
  run yq '.gates.gate_a.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
}

# ─── AC2: repeated run (same fingerprint) updates percentiles, increments samples_count ──
@test "AC2: repeated run of same gate updates p50/p95/max and increments samples_count" {
  gate_baseline_update "gate_b" "run-tests" "run-tests --resolved" 0 1000 60
  run yq '.gates.gate_b.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]

  gate_baseline_update "gate_b" "run-tests" "run-tests --resolved" 0 3000 60

  run yq '.gates.gate_b.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_b.p50_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1000" ]
  run yq '.gates.gate_b.p95_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "3000" ]
  run yq '.gates.gate_b.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "3000" ]
}

# ─── AC3: fingerprint change resets the series ──────────────────────────────
@test "AC3: command-template fingerprint change resets the series (samples_count restarts at 1)" {
  gate_baseline_update "gate_c" "tpl-v1" "resolved-v1" 0 1000 60
  gate_baseline_update "gate_c" "tpl-v1" "resolved-v1" 0 2000 60
  run yq '.gates.gate_c.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_c.series_reset_at' "$AID_GATE_BASELINE_FILE"
  local first_reset_at="$output"
  [ "$first_reset_at" != "null" ]

  # Edit the command template — this must reset the series, not blend old samples in.
  gate_baseline_update "gate_c" "tpl-v2-EDITED" "resolved-v2" 0 5000 60

  run yq '.gates.gate_c.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  run yq '.gates.gate_c.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "5000" ]  # old 1000/2000 samples were NOT blended in
  run yq '.gates.gate_c.series_reset_at' "$AID_GATE_BASELINE_FILE"
  [ "$output" != "null" ]
  [ "$output" != "$first_reset_at" ]
}

# ─── AC4: censored samples excluded from percentiles; all-censored -> insufficient data ──
@test "AC4: a timed-out sample is recorded but excluded from percentiles" {
  gate_baseline_update "gate_d" "tpl" "resolved" 0 1000 60
  gate_baseline_update "gate_d" "tpl" "resolved" 124 999999 60

  run yq '.gates.gate_d.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_d.non_censored_samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  # Timeout sample's huge duration must never leak into p95/max.
  run yq '.gates.gate_d.p95_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1000" ]
  run yq '.gates.gate_d.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1000" ]
  run yq '.gates.gate_d.recent_samples[1].censored' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
}

@test "AC4: all samples censored -> percentiles null, recommendation is explicitly insufficient data" {
  gate_baseline_update "gate_e" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_e" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_e" "tpl" "resolved" 124 500000 60

  run yq '.gates.gate_e.non_censored_samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "0" ]
  for f in p50_ms p90_ms p95_ms max_ms; do
    run yq ".gates.gate_e.${f}" "$AID_GATE_BASELINE_FILE"
    [ "$output" = "null" ]
  done
  run yq '.gates.gate_e.timeout_recommended_seconds' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]

  # The recommend function must echo NOTHING (never a value derived from timeouts).
  run gate_baseline_recommend_timeout "gate_e"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Human-readable summary states insufficient data explicitly.
  run gate_baseline_show "gate_e"
  [[ "$output" == *"insufficient data"* ]]
}

# ─── AC5: run_mode_recommended background only once threshold met ──────────
@test "AC5: run_mode_recommended stays null below 5 non-censored samples even if p95 > 10min" {
  for i in 1 2 3 4; do
    gate_baseline_update "gate_f" "tpl" "resolved" 0 700000 900
  done
  run yq '.gates.gate_f.non_censored_samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "4" ]
  run yq '.gates.gate_f.run_mode_recommended' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]
  run gate_baseline_recommend_run_mode "gate_f"
  [ -z "$output" ]
}

@test "AC5: run_mode_recommended becomes background once non_censored_samples_count >= 5 and p95 > 10min" {
  for i in 1 2 3 4 5; do
    gate_baseline_update "gate_g" "tpl" "resolved" 0 700000 900
  done
  run yq '.gates.gate_g.non_censored_samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "5" ]
  run yq '.gates.gate_g.p95_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "700000" ]
  run yq '.gates.gate_g.run_mode_recommended' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "background" ]
  run gate_baseline_recommend_run_mode "gate_g"
  [ "$output" = "background" ]
}

@test "AC5: run_mode_recommended is foreground once threshold met but p95 under 10min" {
  for i in 1 2 3 4 5; do
    gate_baseline_update "gate_h" "tpl" "resolved" 0 50000 60
  done
  run yq '.gates.gate_h.run_mode_recommended' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "foreground" ]
}

# ─── AC12: mid-write crash never corrupts the real file ────────────────────
@test "AC12: mv failure (simulated crash between tmp-write and mv) leaves real file untouched and parseable" {
  gate_baseline_update "gate_i" "tpl" "resolved" 0 1000 60
  local orig_content
  orig_content="$(cat "$AID_GATE_BASELINE_FILE")"

  # Simulate "process killed after the tmp file was written, before mv ran" by
  # making `mv` fail deterministically for this one call — the net observable
  # state (tmp file materialized, real file never replaced) is identical to a
  # genuine kill at that exact point, and is fully reproducible in CI.
  local fakebin="$WORK/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/mv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$fakebin/mv"

  PATH="$fakebin:$PATH" run gate_baseline_update "gate_i" "tpl" "resolved" 0 9999999 60
  [ "$status" -eq 0 ]  # never crashes the caller even though the write failed

  local new_content
  new_content="$(cat "$AID_GATE_BASELINE_FILE")"
  [ "$orig_content" = "$new_content" ]

  run yq -e '.' "$AID_GATE_BASELINE_FILE"
  [ "$status" -eq 0 ]
  run yq '.gates.gate_i.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]  # the failed second attempt never landed
}

@test "AC12: a genuinely malformed pre-existing file is quarantined as .corrupt.<timestamp>, fresh series starts" {
  printf 'this: [is not, valid yaml: {{{\n' > "$AID_GATE_BASELINE_FILE"

  gate_baseline_update "gate_j" "tpl" "resolved" 0 1234 60

  # Original garbage preserved under a .corrupt.<unix-ts> sibling, not discarded.
  local corrupt_files
  corrupt_files=$(find "$WORK" -maxdepth 1 -name "gate-runtime-baselines.yaml.corrupt.*")
  [ -n "$corrupt_files" ]
  [[ "$(basename "$corrupt_files")" =~ ^gate-runtime-baselines\.yaml\.corrupt\.[0-9]+$ ]]
  grep -q "is not, valid yaml" "$corrupt_files"

  # A fresh series started at the real path.
  run yq -e '.' "$AID_GATE_BASELINE_FILE"
  [ "$status" -eq 0 ]
  run yq '.gates.gate_j.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
}

# ─── AC13: gate_name is the real lookup key — two gates never collide ──────
@test "AC13: two different gate_names with similar command_templates never collide" {
  gate_baseline_update "gate_k" "same-looking-template --flag" "resolved-k" 0 1111 60
  gate_baseline_update "gate_l" "same-looking-template --flag" "resolved-l" 0 2222 60

  run yq '.gates.gate_k.last_duration_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1111" ]
  run yq '.gates.gate_l.last_duration_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2222" ]
  run yq '.gates.gate_k.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  run yq '.gates.gate_l.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]

  # A second attempt against gate_k must never touch gate_l's entry.
  gate_baseline_update "gate_k" "same-looking-template --flag" "resolved-k" 0 3333 60
  run yq '.gates.gate_k.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_l.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]

  # gate_baseline_policy_check also locates purely by gate_name.
  run gate_baseline_policy_check "gate_k" 60 3
  [ "$output" = "no-block" ]
  run gate_baseline_policy_check "gate_l" 60 3
  [ "$output" = "no-block" ]
}

# ─── Bonus coverage: policy_result/retryable/operator_action write-ordering ──
# (Not its own numbered AC, but directly required by the plan's write-ordering
# contract: gate_baseline_update must NEVER set these three fields to an
# ACTIVE BLOCK itself — only gate_baseline_mark_policy_block may do that.)
@test "gate_baseline_update never sets an active policy block for the CURRENT attempt it just recorded" {
  gate_baseline_update "gate_m" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_m" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_m" "tpl" "resolved" 124 500000 60

  run yq '.gates.gate_m.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "none" ]
  run yq '.gates.gate_m.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
  run yq '.gates.gate_m.operator_action' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]

  # gate_baseline_policy_check (read-only) confirms it — 3 consecutive
  # timeouts at the currently-configured timeout is a "block" verdict, but
  # the verdict itself must not have been written by gate_baseline_update.
  run gate_baseline_policy_check "gate_m" 60 3
  [ "$output" = "block" ]

  # Only gate_baseline_mark_policy_block may flip these three fields.
  gate_baseline_mark_policy_block "gate_m" "increase_timeout_or_background"
  run yq '.gates.gate_m.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "timeout_policy_block" ]
  run yq '.gates.gate_m.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "false" ]
  run yq '.gates.gate_m.operator_action' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "increase_timeout_or_background" ]
}

# ─── E-063-1_1 REOPEN (PM finding, HIGH) ────────────────────────────────────
# A policy block is RUN-SCOPED state describing whether a block is CURRENTLY
# active — never a permanent label. It must clear the instant the SAME gate's
# next attempt is recorded (pass, unrelated unrecovered failure, or a
# fingerprint reset), not persist forever once set.
#
# This is the actual reopened bug: gate_baseline_update used to carry
# policy_result/retryable/operator_action forward UNCONDITIONALLY from
# $existing, so a gate that already recovered still reported retryable:false
# and could permanently refuse aid-fsm.sh's GATES->EXECUTE transition
# (aid-fsm.sh ~line 2015) because of a completely unrelated, already-resolved
# historical block. The OLD (buggy) version of this exact test asserted the
# opposite ("must not stomp on the policy fields") — that assertion was the
# bug's contract, not a spec; it is corrected here.

@test "gate_baseline_update clears a prior policy block once the SAME gate's next attempt passes" {
  gate_baseline_update "gate_n" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_n" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_n" "tpl" "resolved" 124 500000 60
  run gate_baseline_policy_check "gate_n" 60 3
  [ "$output" = "block" ]
  gate_baseline_mark_policy_block "gate_n" "increase_timeout_or_background"
  run yq '.gates.gate_n.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "false" ]

  # The gate's very next recorded attempt is a PASS (same command_template,
  # same timeout — no fingerprint reset in play here).
  gate_baseline_update "gate_n" "tpl" "resolved" 0 1000 60

  run yq '.gates.gate_n.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "none" ]
  run yq '.gates.gate_n.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
  run yq '.gates.gate_n.operator_action' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]

  # History is NOT erased — the timeout trail stays in recent_samples.
  run yq '.gates.gate_n.recent_samples | length' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "4" ]
  run yq '.gates.gate_n.recent_samples[0].censored' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
}

@test "gate_baseline_update clears a prior policy block even when the next attempt fails again for an unrelated reason" {
  gate_baseline_update "gate_o" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_o" "tpl" "resolved" 124 500000 60
  gate_baseline_update "gate_o" "tpl" "resolved" 124 500000 60
  gate_baseline_mark_policy_block "gate_o" "increase_timeout_or_background"
  run yq '.gates.gate_o.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "false" ]

  # Next attempt is a real (non-timeout) failure — exit 1, not 124. Nothing
  # re-triggers the policy check here; only gate_baseline_update's own
  # reset-on-every-call behavior is under test.
  gate_baseline_update "gate_o" "tpl" "resolved" 1 2000 60

  run yq '.gates.gate_o.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "none" ]
  run yq '.gates.gate_o.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
  run yq '.gates.gate_o.operator_action' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]
}

@test "gate_baseline_update clears a prior policy block on a command_template edit (fingerprint reset)" {
  gate_baseline_update "gate_p" "tpl-v1" "resolved-v1" 124 500000 60
  gate_baseline_update "gate_p" "tpl-v1" "resolved-v1" 124 500000 60
  gate_baseline_update "gate_p" "tpl-v1" "resolved-v1" 124 500000 60
  gate_baseline_mark_policy_block "gate_p" "increase_timeout_or_background"
  run yq '.gates.gate_p.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "false" ]

  # command_template edited -> fingerprint reset -> fresh series, fresh state.
  gate_baseline_update "gate_p" "tpl-v2-EDITED" "resolved-v2" 0 1000 60

  run yq '.gates.gate_p.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]  # series really did reset
  run yq '.gates.gate_p.policy_result' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "none" ]
  run yq '.gates.gate_p.retryable' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "true" ]
  run yq '.gates.gate_p.operator_action' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]
}
