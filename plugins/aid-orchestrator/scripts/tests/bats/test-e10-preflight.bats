#!/usr/bin/env bats
# aid-tier: t1
# test-e10-preflight.bats — E10's bookkeeping hygiene gate.
# Provenance: P062 Step 1 (D7).
#
# WHAT THIS SUITE IS ACTUALLY GUARDING
#   E10 measures how well the control stack catches defects. If it runs over a
#   stale bookkeeping layer it will attribute that mess to the controls, so the
#   preflight must REFUSE rather than report a comfortable pass. Half of these
#   cases therefore assert a refusal: a gate that never refuses anything cannot
#   be told apart from a gate nobody wired.
#
# THE FIXTURE IS A FAKE close-check, ON PURPOSE
#   The preflight's whole design is that it does not reimplement the four
#   checks — it consumes aid-plan-close-check.sh's --json. These cases
#   therefore drive it through a stub that emits that contract, which is what
#   lets a single class be made dirty deterministically. The contract itself
#   (that the real script emits this shape) is asserted once, separately, in
#   the last case, against the real script.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PREFLIGHT="$AID_PLUGIN_PATH/scripts/aid-e10-preflight.sh"
  export PREFLIGHT

  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/.aid-o/plans" "$PROJ/bin"
  export PROJ
  : > "$PROJ/.aid-o/plans/P900-fixture-plan.md"
  git -C "$PROJ" init -q 2>/dev/null || true
  git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null || true
}

teardown() { teardown_test_evidence_dir; }

# _stub <check_id>... — a close-check stand-in that FAILS the named check ids
# and passes everything else. Installed as the sibling the preflight resolves.
_stub() {
  local fails="$*"
  mkdir -p "$PROJ/bin"
  cat > "$PROJ/bin/aid-plan-close-check.sh" <<STUB
#!/usr/bin/env bash
fails="$fails"
res=""
for c in check1 check2 check3 check4; do
  st=pass
  case " \$fails " in *" \$c "*) st=fail ;; esac
  res="\${res}{\"status\":\"\$st\",\"check\":\"\$c\",\"message\":\"fixture\"},"
done
printf '{"plan_id":"P900","overall":"fail","results":[%s]}' "\${res%,}"
[ -z "\$fails" ]
STUB
  chmod +x "$PROJ/bin/aid-plan-close-check.sh"
  cp "$PREFLIGHT" "$PROJ/bin/aid-e10-preflight.sh"
  chmod +x "$PROJ/bin/aid-e10-preflight.sh"
}

@test "a clean bookkeeping layer exits 0 and the artifact says clean" {
  _stub
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict "$PROJ/pf.json")" = "clean" ]
}

@test "a stale report blocks: reports_stale is dirty and the exit is non-zero" {
  _stub check1
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checked[] | select(.class=="reports_stale") | .status' "$PROJ/pf.json")" = "dirty" ]
  [ "$(jq -r .verdict "$PROJ/pf.json")" = "dirty" ]
}

@test "a DONE run with pending steps blocks — the class the re-grounding measured" {
  _stub check3
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checked[] | select(.class=="steps_pending_at_done") | .status' "$PROJ/pf.json")" = "dirty" ]
}

@test "a stale queue after merge blocks" {
  _stub check4
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checked[] | select(.class=="queue_active_stale") | .status' "$PROJ/pf.json")" = "dirty" ]
}

@test "a PM exclusion passes the run but is never rendered as clean" {
  _stub check1
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json" \
    --exclude reports_stale:"PM accepts the private report policy for this window"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.checked[] | select(.class=="reports_stale") | .status' "$PROJ/pf.json")" = "excluded" ]
  [ "$(jq -r .verdict "$PROJ/pf.json")" = "excluded_by_pm" ]
  # The reason travels with it — an exclusion without a recorded why is a
  # silent pass wearing a different word.
  [ "$(jq -r '.exclusions[0].reason' "$PROJ/pf.json")" != "null" ]
}

@test "an exclusion cannot cover a class other than its own" {
  _stub check3
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json" \
    --exclude reports_stale:"this exclusion is for a different class entirely"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checked[] | select(.class=="steps_pending_at_done") | .status' "$PROJ/pf.json")" = "dirty" ]
}

@test "a too-short exclusion reason is refused, not accepted quietly" {
  _stub check1
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --exclude reports_stale:"short"
  [ "$status" -eq 2 ]
  [[ "$output" == *"at least 20 required"* ]]
}

@test "an unknown class in --exclude is refused" {
  _stub
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --exclude nosuchclass:"a perfectly long reason string"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown class"* ]]
}

@test "a close-check that cannot run is recorded, never counted as clean" {
  _stub
  cat > "$PROJ/bin/aid-plan-close-check.sh" <<'BROKEN'
#!/usr/bin/env bash
echo "boom" >&2
exit 2
BROKEN
  chmod +x "$PROJ/bin/aid-plan-close-check.sh"
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  # It must BLOCK. Before the fix this exited 0 with verdict `clean`: the plan
  # contributed no rows, so every class came out clean by silence — a gate
  # reporting a clean bookkeeping layer it was never able to read.
  [ "$status" -eq 1 ]
  [ "$(jq -r .verdict "$PROJ/pf.json")" = "unproven" ]
  [ "$(jq -r '.unrunnable | length' "$PROJ/pf.json")" -gt 0 ]
  # `unproven` is its own word: "we found no mess" and "we could not look" are
  # different facts, and AC1 accepts only clean|excluded_by_pm.
  [ "$(jq -r .verdict "$PROJ/pf.json")" != "clean" ]
}

@test "the audit-log class is not_grounded and carries its citation, not a fabricated check" {
  _stub
  run bash "$PROJ/bin/aid-e10-preflight.sh" --project-root "$PROJ" --out "$PROJ/pf.json"
  [ "$(jq -r '.checked[] | select(.class=="audit_log_self_block") | .status' "$PROJ/pf.json")" = "not_grounded" ]
  note="$(jq -r '.checked[] | select(.class=="audit_log_self_block") | .note' "$PROJ/pf.json")"
  [[ "$note" == *"aid-ancillary.sh"* ]]
}

@test "the REAL close-check emits the --json contract this preflight consumes" {
  # The one case that does not use the stub. If --json ever stops emitting
  # {results:[{status,check,message}]}, every stubbed case above would keep
  # passing over a contract that no longer exists.
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh" P062 --json \
    --project-root "$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  [ -n "$output" ]
  echo "$output" | jq -e '.plan_id and .overall and (.results | type == "array")' >/dev/null
  echo "$output" | jq -e 'all(.results[]; has("status") and has("check") and has("message"))' >/dev/null
}
