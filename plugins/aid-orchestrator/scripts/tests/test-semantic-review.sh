#!/usr/bin/env bash
# test-semantic-review.sh — E5 C2 Semantic Review Engine test harness
# Tests: aid-finding-merge.sh, aid-acceptance-evidence.sh, aid-consumption-proof.sh,
#        review-profile-check.sh (completed_lenses E5 path)
# Exit: 0=all pass, 1=failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/semantic-review"
PASS=0; FAIL=0

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1"; (( FAIL++ )) || true; }

echo "=== C2 Semantic Review Engine Tests ==="
TMPDIR=$(mktemp -d)
TMPDIR2=""
trap 'rm -rf "$TMPDIR" "${TMPDIR2:-}"' EXIT

# --- T1: aid-finding-merge.sh — same fingerprint, different severity → max ---
echo "T1: finding-merge severity=max"
cat > "$TMPDIR/r1.json" <<'J'
{"semantic_review":{"findings":[{"fingerprint":"sha256:aabbccdd00000000000000000000000000000000000000000000000000000001","lens":"transaction_boundary","check_id":"TXN-001","target_path":"a.ts","finding_class":"boundary_violation","severity":"high","detail":"msg-high"}]}}
J
cat > "$TMPDIR/r2.json" <<'J'
{"semantic_review":{"findings":[{"fingerprint":"sha256:aabbccdd00000000000000000000000000000000000000000000000000000001","lens":"transaction_boundary","check_id":"TXN-001","target_path":"a.ts","finding_class":"boundary_violation","severity":"critical","detail":"msg-critical"}]}}
J
MERGE_OUT=$(bash "$PLUGIN_DIR/scripts/lib/aid-finding-merge.sh" merge_findings "$TMPDIR/r1.json" "$TMPDIR/r2.json" 2>/dev/null)
SEVERITY=$(echo "$MERGE_OUT" | jq -r '.findings[0].severity' 2>/dev/null)
if [[ "$SEVERITY" == "critical" ]]; then _pass "merge severity=max(critical)"; else _fail "merge severity expected critical, got: $SEVERITY"; fi
CONFLICT_COUNT=$(echo "$MERGE_OUT" | jq '.merge_meta.conflicts | length' 2>/dev/null)
if [[ "$CONFLICT_COUNT" -ge 1 ]]; then _pass "merge conflict recorded"; else _fail "merge conflict not recorded"; fi

# --- T2: aid-finding-merge.sh — 2 unique fingerprints → 2 findings ---
echo "T2: finding-merge 2 unique fingerprints"
cat > "$TMPDIR/r3.json" <<'J'
{"semantic_review":{"findings":[{"fingerprint":"sha256:0000000000000000000000000000000000000000000000000000000000000001","lens":"field_lineage","check_id":"FL-001","target_path":"b.ts","finding_class":"missing_persistence","severity":"high","detail":"d1"}]}}
J
cat > "$TMPDIR/r4.json" <<'J'
{"semantic_review":{"findings":[{"fingerprint":"sha256:0000000000000000000000000000000000000000000000000000000000000002","lens":"negative_case","check_id":"NC-001","target_path":"c.ts","finding_class":"missing_negative_proof","severity":"medium","detail":"d2"}]}}
J
MERGE2=$(bash "$PLUGIN_DIR/scripts/lib/aid-finding-merge.sh" merge_findings "$TMPDIR/r3.json" "$TMPDIR/r4.json" 2>/dev/null)
COUNT=$(echo "$MERGE2" | jq '.findings | length' 2>/dev/null)
if [[ "$COUNT" -eq 2 ]]; then _pass "2 unique fingerprints → 2 findings"; else _fail "expected 2 findings, got: $COUNT"; fi

# --- T3: aid-acceptance-evidence.sh — covered=true from verifier output ---
echo "T3: acceptance-evidence covered=true"
cat > "$TMPDIR/plan.json" <<'J'
{"steps":[{"id":"step-0","title":"Test step","acceptance_criteria":["The feature works correctly"]}]}
J
mkdir -p "$TMPDIR/evidence"
# Compute ac_id: sha256[:12] of the AC text + step_num (1-indexed, no zero-padding)
AC_TEXT="The feature works correctly"
AC_HASH=$(printf '%s' "$AC_TEXT" | sha256sum | cut -c1-12)
AC_ID="${AC_HASH}_1"
cat > "$TMPDIR/evidence/verifier-output-step-1.md" <<MD
## AC Coverage
ac_coverage:
  - ac_id: "${AC_ID}"
    ac_text: "The feature works correctly"
    covered: true
    evidence: "diff shows feature implementation"
    deviation: none
MD
bash "$PLUGIN_DIR/scripts/aid-acceptance-evidence.sh" reconstruct "$TMPDIR/plan.json" "$TMPDIR/evidence" 2>/dev/null
ACC_FILE="$TMPDIR/evidence/acceptance-evidence.json"
if [[ -f "$ACC_FILE" ]]; then
  COVERED=$(jq -r '.acceptance_evidence.criteria[0].covered' "$ACC_FILE" 2>/dev/null)
  DEV=$(jq -r '.acceptance_evidence.criteria[0].deviation' "$ACC_FILE" 2>/dev/null)
  if [[ "$COVERED" == "true" ]]; then _pass "acceptance-evidence covered=true"; else _fail "expected covered=true, got: $COVERED"; fi
  if [[ "$DEV" == "none" ]]; then _pass "acceptance-evidence deviation=none"; else _fail "expected deviation=none, got: $DEV"; fi
else
  _fail "acceptance-evidence.json not created"
fi

# --- T4: aid-consumption-proof.sh — all bindings verified ---
echo "T4: consumption-proof all verified"
cat > "$TMPDIR/manifest.json" <<'J'
{"bindings":[{"id":"B-001","contract_ref":"auth.contract.json","status":"pending"}]}
J
echo "B-001 evidence record" > "$TMPDIR/evidence/auth-evidence.txt"
bash "$PLUGIN_DIR/scripts/aid-consumption-proof.sh" verify "$TMPDIR/manifest.json" "$TMPDIR/evidence" 2>/dev/null
PROOF="$TMPDIR/evidence/consumption-proof.json"
if [[ -f "$PROOF" ]]; then
  STATE=$(jq -r '.consumption_proof.state' "$PROOF" 2>/dev/null)
  if [[ "$STATE" == "verified" ]]; then _pass "consumption-proof state=verified"; else _fail "expected state=verified, got: $STATE"; fi
else
  _fail "consumption-proof.json not created"
fi

# --- T5: consumption-proof manifest missing → fail-safe unresolvable ---
echo "T5: consumption-proof manifest missing → unresolvable"
bash "$PLUGIN_DIR/scripts/aid-consumption-proof.sh" verify "/nonexistent/manifest.json" "$TMPDIR/evidence" --out "$TMPDIR/proof-missing.json" 2>/dev/null
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 0 ]]; then _pass "consumption-proof exit 0 on missing manifest"; else _fail "expected exit 0, got: $EXIT_CODE"; fi
if [[ -f "$TMPDIR/proof-missing.json" ]]; then
  MS=$(jq -r '.consumption_proof.state' "$TMPDIR/proof-missing.json" 2>/dev/null)
  if [[ "$MS" == "unresolvable" ]]; then _pass "consumption-proof state=unresolvable on missing manifest"; else _fail "expected unresolvable, got: $MS"; fi
fi

# --- T6: review-profile-check.sh E5 — lenses_run satisfies required_lenses ---
echo "T6: review-profile-check E5 completed_lenses"
cat > "$TMPDIR/review-profile.json" <<'J'
{"review_profile":{"required_lenses":["transaction_boundary","field_lineage"],"dispatch_mode":"behavior"}}
J
cat > "$TMPDIR/semantic-review-local.json" <<'J'
{"semantic_review":{"lenses_run":["transaction_boundary","field_lineage"],"findings":[]}}
J
bash "$PLUGIN_DIR/scripts/lib/review-profile-check.sh" "$TMPDIR/review-profile.json" "$TMPDIR" 2>/dev/null
EXIT_E5=$?
if [[ "$EXIT_E5" -eq 0 ]]; then _pass "review-profile-check E5 lenses satisfied → exit 0"; else _fail "expected exit 0 (satisfied), got: $EXIT_E5"; fi

# --- T7: review-profile-check.sh E3 backward-compat (no C2 files → missing) ---
echo "T7: review-profile-check E3 backward-compat"
TMPDIR2=$(mktemp -d)
cat > "$TMPDIR2/review-profile.json" <<'J'
{"review_profile":{"required_lenses":["transaction_boundary"],"dispatch_mode":"local"}}
J
bash "$PLUGIN_DIR/scripts/lib/review-profile-check.sh" "$TMPDIR2/review-profile.json" "$TMPDIR2" 2>/dev/null
EXIT_E3=$?
if [[ "$EXIT_E3" -eq 1 ]]; then _pass "review-profile-check E3 compat → exit 1 (missing)"; else _fail "expected exit 1 (E3 missing), got: $EXIT_E3"; fi

# --- T8: FC-24..28 fixture files exist, valid JSON, and valid fingerprint format ---
echo "T8: FC fixtures valid JSON + fingerprint schema"
for fc in fc-24-transaction-boundary-neg fc-25-field-lineage-neg fc-26-negative-case-neg fc-27-operation-order-neg fc-28-requirement-drift-neg; do
  F="${FIXTURE_DIR}/${fc}.json"
  if [[ -f "$F" ]] && jq empty "$F" 2>/dev/null; then
    _pass "fixture ${fc}.json valid"
  else
    _fail "fixture ${fc}.json missing or invalid"
  fi
  FP=$(jq -r '.semantic_review.findings[0].fingerprint // ""' "$F" 2>/dev/null)
  if echo "$FP" | grep -qE '^sha256:[0-9a-f]{64}$'; then
    _pass "fixture ${fc}.json fingerprint valid"
  else
    _fail "fixture ${fc}.json fingerprint invalid: $FP"
  fi
done

# --- T9: mutation-survives (FC merge count) + low-profile-no-local ---
echo "T9: mutation-survives + low-profile-no-local"
MERGE_ALL=$(bash "$PLUGIN_DIR/scripts/lib/aid-finding-merge.sh" merge_findings \
  "$FIXTURE_DIR/fc-24-transaction-boundary-neg.json" \
  "$FIXTURE_DIR/fc-25-field-lineage-neg.json" \
  "$FIXTURE_DIR/fc-26-negative-case-neg.json" \
  "$FIXTURE_DIR/fc-27-operation-order-neg.json" \
  "$FIXTURE_DIR/fc-28-requirement-drift-neg.json" 2>/dev/null)
COUNT_ALL=$(echo "$MERGE_ALL" | jq '.findings | length' 2>/dev/null)
if [[ "$COUNT_ALL" -eq 5 ]]; then
  _pass "FC-24..28 merge → 5 unique findings"
else
  _fail "FC-24..28 merge: expected 5, got: ${COUNT_ALL}"
fi

MERGE_4=$(bash "$PLUGIN_DIR/scripts/lib/aid-finding-merge.sh" merge_findings \
  "$FIXTURE_DIR/fc-24-transaction-boundary-neg.json" \
  "$FIXTURE_DIR/fc-25-field-lineage-neg.json" \
  "$FIXTURE_DIR/fc-26-negative-case-neg.json" \
  "$FIXTURE_DIR/fc-27-operation-order-neg.json" 2>/dev/null)
COUNT_4=$(echo "$MERGE_4" | jq '.findings | length' 2>/dev/null)
if [[ "$COUNT_4" -eq 4 ]]; then
  _pass "mutation-survives: removing FC-28 → 4 findings (not 5)"
else
  _fail "mutation-survives: expected 4, got: ${COUNT_4}"
fi

TMPDIR3=$(mktemp -d)
cat > "$TMPDIR3/review-profile.json" <<'J'
{"review_profile":{"required_lenses":["requirement_test_drift"],"dispatch_mode":"final"}}
J
cat > "$TMPDIR3/semantic-review-final.json" <<'J'
{"semantic_review":{"lenses_run":["requirement_test_drift"],"findings":[]}}
J
bash "$PLUGIN_DIR/scripts/lib/review-profile-check.sh" "$TMPDIR3/review-profile.json" "$TMPDIR3" 2>/dev/null
EXIT_FINAL=$?
rm -rf "$TMPDIR3"
if [[ "$EXIT_FINAL" -eq 0 ]]; then
  _pass "low-profile-no-local: final-only profile satisfied by semantic-review-final.json"
else
  _fail "low-profile-no-local: expected exit 0, got: $EXIT_FINAL"
fi

echo ""
echo "T10: protocol-validate --current-head on generated artifacts"
T10_DIR=$(mktemp -d)
T10_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
mkdir -p "$T10_DIR/ev"
cat > "$T10_DIR/plan.json" <<'J'
{"steps":[{"id":"step-1","title":"SHA test","acceptance_criteria":["SHA must be full 40 chars"]}]}
J
# Create step-1 verifier output
T10_HASH=$(printf '%s' "SHA must be full 40 chars" | sha256sum | cut -c1-12)
cat > "$T10_DIR/ev/verifier-output-step-1.md" <<MD
## AC Coverage
ac_coverage:
  - ac_id: "${T10_HASH}_1"
    ac_text: "SHA must be full 40 chars"
    covered: true
    evidence: "test"
    deviation: none
MD
bash "$PLUGIN_DIR/scripts/aid-acceptance-evidence.sh" reconstruct "$T10_DIR/plan.json" "$T10_DIR/ev" 2>/dev/null
bash "$PLUGIN_DIR/scripts/aid-protocol-validate.sh" "$T10_DIR/ev/acceptance-evidence.json" --current-head "$T10_HEAD" 2>/dev/null
if [[ $? -eq 0 ]]; then _pass "acceptance-evidence passes --current-head validation"; else _fail "acceptance-evidence fails --current-head (short SHA in head_sha?)"; fi

# consumption-proof
cat > "$T10_DIR/manifest.json" <<'J'
{"bindings":[{"id":"SHA-BIND","contract_ref":"x.json","status":"pending"}]}
J
echo "SHA-BIND evidence for sha test" > "$T10_DIR/ev/sha-evidence.txt"
bash "$PLUGIN_DIR/scripts/aid-consumption-proof.sh" verify "$T10_DIR/manifest.json" "$T10_DIR/ev" 2>/dev/null
bash "$PLUGIN_DIR/scripts/aid-protocol-validate.sh" "$T10_DIR/ev/consumption-proof.json" --current-head "$T10_HEAD" 2>/dev/null
if [[ $? -eq 0 ]]; then _pass "consumption-proof passes --current-head validation"; else _fail "consumption-proof fails --current-head (short SHA in head_sha?)"; fi

rm -rf "$T10_DIR"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
# P072 Step 9 — the canonical line run-all-tests.sh counts. The decorated line
# above matches neither its `^Results:` anchor nor its `N/T` fraction, so this
# suite was recorded as 0/0 while passing.
echo "Results: ${PASS}/$((PASS + FAIL)) passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
