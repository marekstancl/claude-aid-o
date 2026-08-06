#!/usr/bin/env bats
# test-pm-override.bats — P073 Step 10: ONE PM-override artifact schema for
# both bounded review loops.
#
# Two opposite override philosophies used to coexist. C0 required a single-use
# artifact, claimed atomically and corroborated afterwards. C3 took a bare
# environment variable that left no receipt and — because an export persists —
# silently authorised EVERY subsequent attempt in the same shell. C0's own
# error text explicitly rejects the env model.
#
# This suite proves the convergence: one producer, one schema, one atomic
# single-use claim, and a deprecated env path that gets exactly one conversion
# per plan.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  C3LIB="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  export FSM C3LIB
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  REASON="the third recheck converged on a different subsystem and warrants one more audit"
  export REASON
}

teardown() {
  teardown_test_evidence_dir
}

# _claim <evidence_root> — drives the real claim primitive out of the C3 lib.
_claim() {
  bash -c '
    set -uo pipefail
    eval "$(sed -n "/^_c3_override_file()/,/^# _sha256 /p" "$1")"
    _c3_claim_pm_override "$2"
  ' _ "$C3LIB" "$1"
}

# _convert <evidence_root> <plan_id> — drives the real conversion primitive.
_convert() {
  bash -c '
    set -uo pipefail
    eval "$(sed -n "/^_c3_override_file()/,/^# _sha256 /p" "$1")"
    _c3_convert_env_override "$2" "$3"
  ' _ "$C3LIB" "$1" "$2"
}

# ─── the producer ─────────────────────────────────────────────────────────

@test "P073 Step 10: grant writes a valid c3 override artifact" {
  run "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  local a="$ROOT/.aid-o/work/evidence/P900/c3-pm-escalation-override.json"
  [ -f "$a" ]
  [ "$(jq -r '.artifact_type' "$a")" = "pm_escalation_override" ]
  [ "$(jq -r '.target' "$a")" = "c3" ]
  [ "$(jq -r '.plan_id' "$a")" = "P900" ]
  [ "$(jq -r '.origin' "$a")" = "grant" ]
  [ "$(jq -r '.pm_ref' "$a")" = "$REASON" ]
}

@test "P073 Step 10: grant writes the c0 artifact at the EXISTING path and shape its consumers already read" {
  run "$FSM" pm-override grant c0 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  local a="$ROOT/.aid-o/work/evidence/P900/cp1-pm-escalation-override.json"
  [ -f "$a" ]
  # aid-cp1-gate.sh and aid-cp1-ledger.sh both read exactly this field; the
  # added fields must not disturb it.
  [ "$(jq -r '.pm_ref' "$a")" = "$REASON" ]
  [ "$(jq -r '.target' "$a")" = "c0" ]
}

@test "P073 Step 10: grant REFUSES to overwrite an unconsumed override" {
  run "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  run "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNCONSUMED override already exists"* ]]
  [[ "$output" == *"authorises exactly one further attempt"* ]]
}

@test "P073 Step 10: grant rejects a short reason, a bad target and a bad plan id" {
  run "$FSM" pm-override grant c3 P900 --reason "too short" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]

  run "$FSM" pm-override grant c9 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be 'c0' or 'c3'"* ]]

  run "$FSM" pm-override grant c3 NOTAPLAN --reason "$REASON" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_id must match"* ]]
}

@test "P073 Step 10: pm-override rejects an unknown action rather than guessing" {
  run "$FSM" pm-override revoke c3 P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown action 'revoke'"* ]]
}

# ─── the single-use claim ─────────────────────────────────────────────────

@test "P073 Step 10: a claim consumes the artifact exactly once" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  run "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -eq 0 ]

  run _claim "$ev"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reason' <<<"$output")" = "$REASON" ]
  # The source is gone and a .consumed-<epoch> archive exists.
  [ ! -f "$ev/c3-pm-escalation-override.json" ]
  run bash -c "ls '$ev'/c3-pm-escalation-override.json.consumed-* | wc -l"
  [ "$output" = "1" ]

  # A second claim with no fresh grant fails closed.
  run _claim "$ev"
  [ "$status" -ne 0 ]
}

@test "P073 Step 10: the claim records a content hash of the artifact it consumed, so a later audit can verify it" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT" >/dev/null
  run _claim "$ev"
  [ "$status" -eq 0 ]
  local path sha
  path="$(jq -r '.consumed_path' <<<"$output")"
  sha="$(jq -r '.consumed_sha256' <<<"$output")"
  [ -f "$path" ]
  [ "$sha" = "sha256:$(sha256sum "$path" | awk '{print $1}')" ]
}

@test "P073 Step 10: a hand-written artifact with a short pm_ref is rejected by the claim" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  jq -n '{schema_version:"aid-2.0", artifact_type:"pm_escalation_override",
          target:"c3", plan_id:"P900", pm_ref:"tooshort", created_at:"2026-08-05T00:00:00Z"}' \
    > "$ev/c3-pm-escalation-override.json"
  run _claim "$ev"
  [ "$status" -ne 0 ]
  # Fail-closed means untouched, not consumed.
  [ -f "$ev/c3-pm-escalation-override.json" ]
}

# ─── the deprecated env var: one conversion, then never again ─────────────

@test "P073 Step 10: the env var is converted into a single-use artifact, with a deprecation warning" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  AID_C3_FORCE_BEYOND_ESCALATION="$REASON" run _convert "$ev" P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"is deprecated"* ]]
  [[ "$output" == *"single-use override artifact"* ]]
  [ "$(jq -r '.origin' "$ev/c3-pm-escalation-override.json")" = "env" ]
  [ "$(jq -r '.pm_ref' "$ev/c3-pm-escalation-override.json")" = "$REASON" ]
}

@test "P073 Step 10: a still-exported env var cannot be converted TWICE — the lingering export is not a standing bypass" {
  # This is the whole reason the env model was rejected: an export persists, so
  # the old gate re-authorised every later attempt in the same shell.
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  AID_C3_FORCE_BEYOND_ESCALATION="$REASON" run _convert "$ev" P900
  [ "$status" -eq 0 ]
  run _claim "$ev"
  [ "$status" -eq 0 ]

  # The variable is STILL exported — and must now be refused.
  AID_C3_FORCE_BEYOND_ESCALATION="$REASON" run _convert "$ev" P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"already consumed once"* ]]
  [[ "$output" == *"pm-override grant c3 P900"* ]]
  [ ! -f "$ev/c3-pm-escalation-override.json" ]
}

@test "P073 Step 10: an UNCONSUMED artifact wins over the env var (no double-use race)" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT" >/dev/null
  AID_C3_FORCE_BEYOND_ESCALATION="a completely different reason that is also long enough" \
    run _convert "$ev" P900
  # Return code 2 == "artifact already present, variable ignored".
  [ "$status" -eq 2 ]
  # The artifact still carries the GRANTED reason, not the env one.
  [ "$(jq -r '.pm_ref' "$ev/c3-pm-escalation-override.json")" = "$REASON" ]
  [ "$(jq -r '.origin' "$ev/c3-pm-escalation-override.json")" = "grant" ]
}

@test "P073 Step 10: an env var with a short reason is refused and writes no artifact" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  AID_C3_FORCE_BEYOND_ESCALATION="too short" run _convert "$ev" P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"under 20 characters"* ]]
  [ ! -f "$ev/c3-pm-escalation-override.json" ]
}

@test "P073 Step 10: after a fresh GRANT the env-consumed history does not block the new artifact" {
  # A consumed env-origin override must not poison later, properly granted ones.
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  AID_C3_FORCE_BEYOND_ESCALATION="$REASON" run _convert "$ev" P900
  [ "$status" -eq 0 ]
  run _claim "$ev"
  [ "$status" -eq 0 ]
  [ ! -f "$ev/c3-pm-escalation-override.json" ]

  run "$FSM" pm-override grant c3 P900 --reason "$REASON" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  # NOTE: this second claim lands within the same epoch second as the first,
  # which is exactly the collision the CP1 primitive papers over with a
  # `sleep 1`. It must succeed here — a legitimate fresh grant is not a race.
  run _claim "$ev"
  [ "$status" -eq 0 ]
  run bash -c "ls '$ev'/c3-pm-escalation-override.json.consumed-* | wc -l"
  [ "$output" = "2" ]
}

# ─── the mechanical containment the plan asks for ─────────────────────────

@test "P073 Step 10: the deprecated variable is referenced ONLY inside the conversion function" {
  run bash -c '
    f="'"$C3LIB"'"
    total=$(grep -c AID_C3_FORCE_BEYOND_ESCALATION "$f" || true)
    infn=$(awk "/^_c3_convert_env_override\(\)/,/^}/" "$f" | grep -c AID_C3_FORCE_BEYOND_ESCALATION || true)
    test "$total" -gt 0 && test "$total" -eq "$infn"
  '
  [ "$status" -eq 0 ]
}

@test "P073 Step 10: no gate reads the env var directly any more" {
  # The exhaustion gate must go through the conversion + claim, never the raw
  # variable — that is what makes the override single-use.
  run grep -n 'AID_C3_FORCE_BEYOND_ESCALATION' "$C3LIB"
  [[ "$output" != *"prior_loop_outcome"* ]]
}

# ─── Codex-review finding on the first cut of this step ───────────────────

@test "P073 Step 10 (review finding): concurrent grants cannot both report success" {
  # The first cut published with a plain `mv`, which OVERWRITES. Two PMs
  # granting at once both passed the existence check, both wrote, the later
  # silently replaced the earlier — and both printed "Granted". One PM
  # decision was lost without a trace.
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  local outdir="$ROOT/out"; mkdir -p "$outdir"

  local i
  for i in 1 2 3 4 5 6; do
    ( "$FSM" pm-override grant c3 P900 \
        --reason "concurrent grant number ${i} with a reason long enough to validate" \
        --project-root "$ROOT" >"$outdir/$i.out" 2>"$outdir/$i.err"; echo "$?" > "$outdir/$i.rc" ) &
  done
  wait

  local granted=0
  for i in 1 2 3 4 5 6; do
    [[ "$(cat "$outdir/$i.rc")" == "0" ]] && granted=$(( granted + 1 ))
  done
  # Exactly one artifact exists, and exactly one caller was told it granted it.
  [ "$granted" = "1" ]
  run bash -c "ls '$ev'/c3-pm-escalation-override.json | wc -l"
  [ "$output" = "1" ]

  # Every loser says so explicitly rather than exiting quietly.
  local losers=0
  for i in 1 2 3 4 5 6; do
    if [[ "$(cat "$outdir/$i.rc")" != "0" ]]; then
      grep -q 'already at\|UNCONSUMED override already exists' "$outdir/$i.err" && losers=$(( losers + 1 ))
    fi
  done
  [ "$losers" = "5" ]

  # And no temp file was left behind by the losers.
  run bash -c "ls '$ev'/c3-pm-escalation-override.json.tmp.* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 Step 10 (review finding): the single artifact left by a concurrent race is a valid, claimable grant" {
  local ev="$ROOT/.aid-o/work/evidence/P900"
  mkdir -p "$ev"
  local i
  for i in 1 2 3; do
    ( "$FSM" pm-override grant c3 P900 \
        --reason "concurrent grant number ${i} with a reason long enough to validate" \
        --project-root "$ROOT" >/dev/null 2>&1 ) &
  done
  wait
  [ "$(jq -r '.artifact_type' "$ev/c3-pm-escalation-override.json")" = "pm_escalation_override" ]
  run _claim "$ev"
  [ "$status" -eq 0 ]
}
