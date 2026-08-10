#!/usr/bin/env bash
# test-integration-audit-report-shapes.sh — P072 Step 21.
#
# Five report shapes, each driven end to end through the ONE production
# entrypoint (`aid-audit-tests-finalize.sh`), asserting both the artifact and
# the text a user would read:
#
#   complete · incomplete · no-removal · serial-only · proven-parallel
#
# WHY SHAPES RATHER THAN UNITS
#   The existing integration suite proves the handoff is mechanically
#   reachable. That is a different question from whether the DECISION is right
#   and the text says what the decision says — and the two have disagreed:
#   an incomplete audit rendered "Verdict: clean", and a decision proposing a
#   removal rendered "No action needed" above it. Those are only visible when
#   consolidate, render and bridge run together on one input.
#
# EVERY SHAPE ALSO ASSERTS CONTAINMENT
#   The audit must write nothing outside its own evidence directory. A suite
#   that tolerates its own leakage cannot make that claim about the audit.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FINALIZE="${PLUGIN_DIR}/scripts/aid-audit-tests-finalize.sh"

pass=0; fail=0
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ─── Fixture construction ───────────────────────────────────────────────────
# _shape <name> — sets SDIR/ART/OUT/INV/MAN/PROJ for a fresh shape.
_shape() {
  SHAPE="$1"
  SDIR="${WORK}/${SHAPE}"
  ART="${SDIR}/agents"; OUT="${SDIR}/out"
  PROJ="${SDIR}/proj"
  mkdir -p "$ART" "$OUT" "$PROJ/.aid-o/config"
  cp "${PLUGIN_DIR}/defaults/config/test-audit.yaml" "$PROJ/.aid-o/config/test-audit.yaml"
  INV="${SDIR}/inventory.json"; MAN="${SDIR}/manifest.json"
  AUDIT_ID="shape-${SHAPE}"
}

_inventory() {
  printf '%s\n' "$@" | jq -R -s \
    '{schema_version:"1.0.0",
      generated_at:"2026-08-04T00:00:00Z",
      runner_families:["bats"],
      entries: (split("\n") | map(select(length>0))
                | map({run_unit_id: ., runner:"bats", adapter:"bats", confidence:"medium"}))}' > "$INV"
}
_manifest() {
  printf '%s\n' "$@" | jq -R -s --arg a "$AUDIT_ID" \
    '{audit_id:$a, max_concurrent_agents:1, entries:[
       {wave:1, focus:"shard_portfolio", shard_id:"shard-0",
        run_unit_ids:(split("\n")|map(select(length>0))),
        artifact_path:"agents/1-shard_portfolio-shard-0.json",
        producer_agent_dispatch_id:"d0"}]}' > "$MAN"
}
# _disposition <id> [disposition]
_disposition() {
  jq -nc --arg id "$1" --arg d "${2:-keep}" '
    {run_unit_id:$id, disposition:$d,
     behavior_claim:"guards the transition table against silent reordering",
     failure_signal:"transition returns the previous state instead of the next",
     falsification:(if $d == "remove" or $d == "merge" or $d == "rewrite_unit"
                    then {method:"mutation", evidence_ref:"evidence/mutation.txt"}
                    else {method:"unproved"} end),
     uniqueness:"unique", layer:"unit", cheaper_layer_possible:"no",
     cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}'
}
_shard() {
  local joined; joined="$(printf '%s\n' "$@" | jq -s -c '.')"
  mkdir -p "$OUT/evidence"; echo "mutation probe" > "$OUT/evidence/mutation.txt"
  jq -n --argjson d "$joined" '
    {schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
     findings:[], produced_at:"2026-08-04T00:00:00Z",
     producer_agent_dispatch_id:"d0", dispositions:$d}' \
    > "$ART/1-shard_portfolio-shard-0.json"
}
_finalize() {
  bash "$FINALIZE" --audit-id "$AUDIT_ID" --wave-artifacts-dir "$ART" \
    --dispatch-manifest "$MAN" --output-dir "$OUT" \
    --mode full --inventory "$INV" --project-root "$PROJ" "$@"
}

# Containment: nothing outside the audit output directory may change.
_snapshot_proj() { ( cd "$PROJ" && find . -type f -exec sha256sum {} + 2>/dev/null | sort ); }

_assert_contained() {
  local before="$1" after="$2"
  if [[ "$before" == "$after" ]]; then
    pass_msg "${SHAPE}: nothing outside the audit evidence directory was created or modified"
  else
    fail_msg "${SHAPE}: the audit wrote outside its evidence directory: $(diff <(printf '%s' "$before") <(printf '%s' "$after") | head -5 | tr '\n' ' ')"
  fi
}

# Every shape asserts a non-zero unit count FIRST, so a shape cannot pass
# because its fixture was empty.
_assert_units() {
  # `.entries`, the inventory's real key — `.run_units` is the CATALOG's key,
  # and reading it here counted zero for every shape.
  local n; n="$(jq -r '.entries | length' "$INV")"
  if [[ "${n:-0}" -gt 0 ]]; then
    pass_msg "${SHAPE}: fixture has ${n} run unit(s) — the shape is not passing vacuously"
  else
    fail_msg "${SHAPE}: fixture has no run units; every later assertion would be vacuous"
  fi
}

# ─── Shape 1: complete ──────────────────────────────────────────────────────
_shape complete
_inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
_shard "$(_disposition "bats:a")" "$(_disposition "bats:b")"
_assert_units
BEFORE="$(_snapshot_proj)"
echo "TEST: complete shape"
if TEXT="$(_finalize 2>&1)"; then
  if [[ "$(jq -r '.audit_status' "$OUT/decision.json")" == "complete" ]]; then
    pass_msg "complete: audit_status is complete"
  else
    fail_msg "complete: audit_status is $(jq -r '.audit_status' "$OUT/decision.json")"
  fi
  [[ "$TEXT" == *"## 1. What to do now"* ]] \
    && pass_msg "complete: the rendered text leads with the decision" \
    || fail_msg "complete: the rendered text does not lead with section 1"
else
  fail_msg "complete: finalize failed: $(tail -2 <<<"$TEXT")"
fi
_assert_contained "$BEFORE" "$(_snapshot_proj)"

# ─── Shape 2: incomplete ────────────────────────────────────────────────────
_shape incomplete
_inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
# bats:b is assigned but never decided.
_shard "$(_disposition "bats:a")"
_assert_units
BEFORE="$(_snapshot_proj)"
echo "TEST: incomplete shape"
TEXT="$(_finalize 2>&1)"; RC=$?
if [[ "$RC" -ne 0 ]]; then
  # Finalize refuses to render over an unreconciled audit, which is itself the
  # contract: no decision artifact is produced from a shard set that does not
  # cover the manifest.
  pass_msg "incomplete: finalize refuses rather than rendering a partial result"
  [[ "$TEXT" == *"bats:b"* || "$TEXT" == *"disposition"* ]] \
    && pass_msg "incomplete: the refusal names what is missing" \
    || fail_msg "incomplete: the refusal does not say what was missing: $(tail -1 <<<"$TEXT")"
else
  if [[ "$(jq -r '.audit_status' "$OUT/decision.json")" == "incomplete" ]]; then
    pass_msg "incomplete: audit_status is incomplete"
  else
    fail_msg "incomplete: audit_status is $(jq -r '.audit_status' "$OUT/decision.json")"
  fi
  [[ "$TEXT" == *"did not finish"* || "$TEXT" == *"Provisional"* ]] \
    && pass_msg "incomplete: the text leads with a bounded next action, not a verdict" \
    || fail_msg "incomplete: the text does not mark itself unfinished"
  [[ "$TEXT" != *"vytvoř plán oprav"* ]] \
    && pass_msg "incomplete: no remediation plan is suggested" \
    || fail_msg "incomplete: the text suggests creating a remediation plan"
fi
_assert_contained "$BEFORE" "$(_snapshot_proj)"

# ─── Shape 3: no removal ────────────────────────────────────────────────────
_shape no-removal
_inventory "bats:a" "bats:b"; _manifest "bats:a" "bats:b"
_shard "$(_disposition "bats:a" keep)" "$(_disposition "bats:b" fix)"
_assert_units
BEFORE="$(_snapshot_proj)"
echo "TEST: no-removal shape"
if TEXT="$(_finalize 2>&1)"; then
  [[ "$(jq -r '.portfolio_change.remove | length' "$OUT/decision.json")" == "0" ]] \
    && pass_msg "no-removal: portfolio_change.remove is empty" \
    || fail_msg "no-removal: remove is not empty"
  [[ "$TEXT" == *"No test is recommended for removal on current evidence."* ]] \
    && pass_msg "no-removal: the exact no-removal sentence renders" \
    || fail_msg "no-removal: the exact sentence is missing"
else
  fail_msg "no-removal: finalize failed: $(tail -2 <<<"$TEXT")"
fi
_assert_contained "$BEFORE" "$(_snapshot_proj)"

# ─── Shapes 4 and 5 (serial-only / proven-parallel) were removed in P078
# with the parallelism machinery — the audit no longer proposes lanes, so
# there is no lane shape to assert. Shapes 1-3 (complete / incomplete /
# no-removal) are the surviving report-shape contract.

echo "Results: ${pass}/$(( pass + fail )) passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
