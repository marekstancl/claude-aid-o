#!/usr/bin/env bash
# =============================================================================
# test-evidence-verify.sh — Evidence Pack Verifier test harness (E-051-1_1 QA)
#
# Tests aid-evidence-verify.sh against purpose-built fixtures.
# Each fixture tests specific check behavior.
#
# Exit: 0 if all tests pass, 1 if any fail
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
VERIFIER="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/aid-evidence-verify.sh"
VALIDATOR="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/aid-protocol-validate.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/evidence-verify"
GOLDEN_FILE="${FIXTURES_DIR}/_golden/verification-report.sample.json"

SCRATCHPAD="${TMPDIR:-/tmp}/aid-ev-test-$$"
mkdir -p "$SCRATCHPAD"
trap 'rm -rf "$SCRATCHPAD"' EXIT

PASS=0
FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

assert_json_field() {
  local label="$1" file="$2" query="$3" expected="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null) || actual="<error>"
  if [[ "$actual" == "$expected" ]]; then
    _pass "${label}"
  else
    _fail "${label} (expected='${expected}' got='${actual}')"
  fi
}

assert_check_status() {
  local label="$1" file="$2" check_id="$3" expected_status="$4"
  assert_json_field "$label" "$file" \
    ".verification_report.checks[] | select(.id==\"${check_id}\") | .status" \
    "$expected_status"
}

# ---------------------------------------------------------------------------
# Helper: setup_git_repo — init a temp git repo, return HEAD sha via echo
# ---------------------------------------------------------------------------
setup_git_repo() {
  local dir="$1" with_dirty="${2:-false}"
  git init -q "$dir"
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  # Ignore .aid-o/ so the evidence dir never appears as untracked
  echo ".aid-o/" > "$dir/.gitignore"
  echo "init" > "$dir/README.md"
  git -C "$dir" add .gitignore README.md
  git -C "$dir" commit -q -m "init"
  if [[ "$with_dirty" == "true" ]]; then
    echo "dirty" > "$dir/dirty.txt"  # untracked file -> dirty
  fi
  git -C "$dir" rev-parse HEAD
}

# ---------------------------------------------------------------------------
# Helper: setup_evidence_pack — copy fixtures into a temp repo's evidence dir
# Replaces __PACK_HEAD__ with the actual pack_head SHA.
# ---------------------------------------------------------------------------
setup_evidence_pack() {
  local repo_dir="$1" fixture_name="$2" pack_head="$3"
  local ev_dir="$repo_dir/.aid-o/work/evidence/E-test/$fixture_name"
  mkdir -p "$ev_dir"

  # Copy and inject pack_head into each fixture JSON artifact
  for src in "$FIXTURES_DIR/$fixture_name/"*.json; do
    [[ -f "$src" ]] || continue
    local dst="$ev_dir/$(basename "$src")"
    sed "s/__PACK_HEAD__/$pack_head/g" "$src" > "$dst"
  done

  # Copy non-JSON files as-is
  for src in "$FIXTURES_DIR/$fixture_name/"*; do
    [[ -f "$src" ]] || continue
    local ext="${src##*.}"
    if [[ "$ext" != "json" ]]; then
      cp "$src" "$ev_dir/"
    fi
  done

  echo "$ev_dir"
}

# ---------------------------------------------------------------------------
# Helper: run_verifier — invoke verifier and capture output file + exit code
# Sets LAST_VR_FILE and LAST_VR_EXIT.
# ---------------------------------------------------------------------------
LAST_VR_FILE=""
LAST_VR_EXIT=0

run_verifier() {
  local repo_dir="$1" fixture_name="$2"
  local out_file="$SCRATCHPAD/vr-${fixture_name}.json"
  shift 2
  local extra_args=("$@")

  local exit_code=0
  AID_PROJECT_ROOT="$repo_dir" \
    bash "$VERIFIER" "E-test" "$fixture_name" \
    --out "$out_file" "${extra_args[@]}" 2>/dev/null || exit_code=$?

  LAST_VR_FILE="$out_file"
  LAST_VR_EXIT="$exit_code"
}

# ---------------------------------------------------------------------------
# T01: clean-pack — all required checks pass
# ---------------------------------------------------------------------------
test_clean_pack() {
  local repo="$SCRATCHPAD/repo-clean"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "clean-pack" "$pack_head"

  run_verifier "$repo" "clean-pack"

  assert_check_status "T01/git_clean"                       "$LAST_VR_FILE" "git_clean"                       "pass"
  assert_check_status "T01/evidence_pack_found"             "$LAST_VR_FILE" "evidence_pack_found"             "pass"
  assert_check_status "T01/artifact_head_freshness"         "$LAST_VR_FILE" "artifact_head_freshness"         "pass"
  assert_check_status "T01/protocol_validate"               "$LAST_VR_FILE" "protocol_validate"               "pass"
  assert_check_status "T01/fingerprint"                     "$LAST_VR_FILE" "fingerprint"                     "pass"
  assert_check_status "T01/observe_blocking_interpretation" "$LAST_VR_FILE" "observe_blocking_interpretation" "pass"
  assert_json_field   "T01/verified"                        "$LAST_VR_FILE" ".verification_report.summary.verified" "true"
}

# ---------------------------------------------------------------------------
# T02: dirty-git — git_clean fails
# ---------------------------------------------------------------------------
test_dirty_git() {
  local repo="$SCRATCHPAD/repo-dirty"
  local pack_head
  pack_head=$(setup_git_repo "$repo" "true")  # dirty=true
  setup_evidence_pack "$repo" "dirty-git" "$pack_head"

  run_verifier "$repo" "dirty-git"

  assert_check_status "T02/git_clean" "$LAST_VR_FILE" "git_clean" "fail"
  assert_json_field   "T02/verified"  "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
  if [[ "$LAST_VR_EXIT" -eq 1 ]]; then
    _pass "T02/exit-1"
  else
    _fail "T02/exit-1 (expected exit 1, got $LAST_VR_EXIT)"
  fi
}

# ---------------------------------------------------------------------------
# T03: ancestor-pack — freshness PASS for historical (ancestor) pack
# ---------------------------------------------------------------------------
test_ancestor_pack() {
  local repo="$SCRATCHPAD/repo-ancestor"
  local pack_head current_head
  # Create repo with 2 commits — pack uses first commit, HEAD is second
  git init -q "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  echo ".aid-o/" > "$repo/.gitignore"
  echo "v1" > "$repo/README.md"
  git -C "$repo" add .gitignore README.md
  git -C "$repo" commit -q -m "first"
  pack_head=$(git -C "$repo" rev-parse HEAD)
  # Make a second commit — HEAD moves forward
  echo "v2" >> "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "second"
  current_head=$(git -C "$repo" rev-parse HEAD)

  setup_evidence_pack "$repo" "ancestor-pack" "$pack_head"

  run_verifier "$repo" "ancestor-pack"

  # freshness: pass (pack_head is ancestor, not divergent-stale)
  assert_check_status "T03/artifact_head_freshness" "$LAST_VR_FILE" "artifact_head_freshness" "pass"
  assert_json_field   "T03/pack_head"               "$LAST_VR_FILE" ".verification_report.pack_head" "$pack_head"
}

# ---------------------------------------------------------------------------
# T04: divergent-stale — freshness FAIL (zero sha not in any real repo)
# ---------------------------------------------------------------------------
test_divergent_stale() {
  local repo="$SCRATCHPAD/repo-divergent"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  # Copy fixture directly (has hardcoded all-zeros sha — not injectable)
  local ev_dir="$repo/.aid-o/work/evidence/E-test/divergent-stale"
  mkdir -p "$ev_dir"
  cp "$FIXTURES_DIR/divergent-stale/delivery-gate.json" "$ev_dir/"

  run_verifier "$repo" "divergent-stale"

  assert_check_status "T04/artifact_head_freshness" "$LAST_VR_FILE" "artifact_head_freshness" "fail"
  assert_json_field   "T04/verified"                "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T05: inconsistent-head — freshness FAIL (two artifacts with different head_sha)
# ---------------------------------------------------------------------------
test_inconsistent_head() {
  local repo="$SCRATCHPAD/repo-inconsistent"
  local pack_head
  pack_head=$(setup_git_repo "$repo")

  # These artifacts use hardcoded different SHAs — no __PACK_HEAD__ replacement needed
  local ev_dir="$repo/.aid-o/work/evidence/E-test/inconsistent-head"
  mkdir -p "$ev_dir"
  cp "$FIXTURES_DIR/inconsistent-head/"*.json "$ev_dir/"

  run_verifier "$repo" "inconsistent-head"

  assert_check_status "T05/artifact_head_freshness" "$LAST_VR_FILE" "artifact_head_freshness" "fail"
}

# ---------------------------------------------------------------------------
# T06: invalid-artifact — protocol_validate FAIL (missing created_at)
# ---------------------------------------------------------------------------
test_invalid_artifact() {
  local repo="$SCRATCHPAD/repo-invalid"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "invalid-artifact" "$pack_head"

  run_verifier "$repo" "invalid-artifact"

  assert_check_status "T06/protocol_validate" "$LAST_VR_FILE" "protocol_validate" "fail"
  assert_json_field   "T06/verified"          "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T07: enum-garbage — protocol_validate FAIL (invalid artifact_type)
# ---------------------------------------------------------------------------
test_enum_garbage() {
  local repo="$SCRATCHPAD/repo-enum"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "enum-garbage" "$pack_head"

  run_verifier "$repo" "enum-garbage"

  assert_check_status "T07/protocol_validate" "$LAST_VR_FILE" "protocol_validate" "fail"
}

# ---------------------------------------------------------------------------
# T08: mixed-legacy — legacy artifacts skipped, v2 artifact verified
# ---------------------------------------------------------------------------
test_mixed_legacy() {
  local repo="$SCRATCHPAD/repo-mixed"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "mixed-legacy" "$pack_head"

  run_verifier "$repo" "mixed-legacy"

  # v2 artifact passes, legacy is skipped (overall should succeed for the v2 artifact)
  assert_check_status "T08/protocol_validate"       "$LAST_VR_FILE" "protocol_validate"       "pass"
  assert_check_status "T08/artifact_head_freshness" "$LAST_VR_FILE" "artifact_head_freshness" "pass"
  # evidence_pack_found: pass (at least one v2 artifact found)
  assert_check_status "T08/evidence_pack_found"     "$LAST_VR_FILE" "evidence_pack_found"     "pass"
}

# ---------------------------------------------------------------------------
# T09: nondeterministic-fingerprint — fingerprint FAIL
# ---------------------------------------------------------------------------
test_nondeterministic_fingerprint() {
  local repo="$SCRATCHPAD/repo-fp"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "nondeterministic-fingerprint" "$pack_head"

  run_verifier "$repo" "nondeterministic-fingerprint"

  assert_check_status "T09/fingerprint" "$LAST_VR_FILE" "fingerprint" "fail"
  assert_json_field   "T09/verified"    "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T10: ttl-violation — ttl_registry FAIL (custom registry with expired entry)
# ---------------------------------------------------------------------------
test_ttl_violation() {
  local repo="$SCRATCHPAD/repo-ttl"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "ttl-violation" "$pack_head"

  local registry="$FIXTURES_DIR/ttl-violation/registry.yaml"

  # Run with custom registry pointing to expired entry
  local out_file="$SCRATCHPAD/vr-ttl.json"
  local exit_code=0
  AID_PROJECT_ROOT="$repo" AID_REGISTRY_PATH="$registry" \
    bash "$VERIFIER" "E-test" "ttl-violation" \
    --out "$out_file" 2>/dev/null || exit_code=$?
  LAST_VR_FILE="$out_file"
  LAST_VR_EXIT="$exit_code"

  assert_check_status "T10/ttl_registry" "$LAST_VR_FILE" "ttl_registry" "fail"
  assert_json_field   "T10/verified"     "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T11: enforcement-absent — observe_blocking_interpretation FAIL
# ---------------------------------------------------------------------------
test_enforcement_absent() {
  local repo="$SCRATCHPAD/repo-absent"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "enforcement-absent" "$pack_head"

  run_verifier "$repo" "enforcement-absent"

  assert_check_status "T11/observe_blocking_interpretation" "$LAST_VR_FILE" "observe_blocking_interpretation" "fail"
  assert_json_field   "T11/verified"                        "$LAST_VR_FILE" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T12: idempotency — verifier run 2x on same pack must both succeed
# ---------------------------------------------------------------------------
test_idempotency() {
  local repo="$SCRATCHPAD/repo-idem"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "clean-pack" "$pack_head"

  # First run
  local out1="$SCRATCHPAD/vr-idem-1.json"
  local exit1=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "clean-pack" --out "$out1" 2>/dev/null || exit1=$?
  if [[ "$exit1" -ne 0 ]]; then
    _fail "T12/first-run (expected exit 0, got $exit1)"
    return
  fi
  _pass "T12/first-run"

  # Second run — must also pass (idempotent)
  local out2="$SCRATCHPAD/vr-idem-2.json"
  local exit2=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "clean-pack" --out "$out2" 2>/dev/null || exit2=$?
  if [[ "$exit2" -eq 0 ]]; then
    _pass "T12/second-run (idempotent)"
  else
    _fail "T12/second-run (expected exit 0, got $exit2)"
  fi

  # Both outputs claim verified: true
  assert_json_field "T12/first-verified" "$out1" ".verification_report.summary.verified" "true"
  assert_json_field "T12/second-verified" "$out2" ".verification_report.summary.verified" "true"
}

# ---------------------------------------------------------------------------
# T12a: --at-head strict mode — pack_head != HEAD must fail
# ---------------------------------------------------------------------------
test_at_head_strict() {
  local repo="$SCRATCHPAD/repo-athead"
  local pack_head current_head

  # Create repo with 2 commits: pack at first, HEAD at second
  git init -q "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  echo ".aid-o/" > "$repo/.gitignore"
  echo "v1" > "$repo/README.md"
  git -C "$repo" add .gitignore README.md
  git -C "$repo" commit -q -m "first"
  pack_head=$(git -C "$repo" rev-parse HEAD)
  echo "v2" >> "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "second"

  setup_evidence_pack "$repo" "clean-pack" "$pack_head"

  # Without --at-head: ancestor -> pass
  local out_nstrict="$SCRATCHPAD/vr-athead-normal.json"
  local exit_nstrict=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "clean-pack" --out "$out_nstrict" 2>/dev/null || exit_nstrict=$?
  assert_check_status "T12a/no-flag-freshness" "$out_nstrict" "artifact_head_freshness" "pass"

  # With --at-head: pack_head != HEAD -> fail
  local out_strict="$SCRATCHPAD/vr-athead-strict.json"
  local exit_strict=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "clean-pack" --at-head --out "$out_strict" 2>/dev/null || exit_strict=$?
  assert_check_status "T12a/at-head-freshness" "$out_strict" "artifact_head_freshness" "fail"
  if [[ "$exit_strict" -eq 1 ]]; then
    _pass "T12a/at-head-exit-1"
  else
    _fail "T12a/at-head-exit-1 (expected exit 1, got $exit_strict)"
  fi
}

# ---------------------------------------------------------------------------
# T12b: auto-detect without args
# ---------------------------------------------------------------------------
test_auto_detect() {
  local repo="$SCRATCHPAD/repo-autodetect"
  local pack_head
  pack_head=$(setup_git_repo "$repo")

  # Setup pack with explicit epic_id and run_id
  local ev_dir="$repo/.aid-o/work/evidence/E-autodetect/autorun"
  mkdir -p "$ev_dir"
  echo "epic_id: E-autodetect" > "$ev_dir/fsm-state.yaml"
  sed "s/__PACK_HEAD__/$pack_head/g" \
    "$FIXTURES_DIR/clean-pack/delivery-gate.json" > "$ev_dir/delivery-gate.json"

  # Run without positional args — auto-detect
  local out="$SCRATCHPAD/vr-autodetect.json"
  local exit_code=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" --out "$out" 2>/dev/null || exit_code=$?

  # Should discover E-autodetect/autorun
  if [[ -f "$out" ]]; then
    _pass "T12b/output-exists"
    assert_json_field "T12b/epic_id" "$out" ".verification_report.evidence_pack.epic_id" "E-autodetect"
  else
    _fail "T12b/output-exists (no output file generated)"
  fi
}

# ---------------------------------------------------------------------------
# T12c: validator-missing runtime test
# ---------------------------------------------------------------------------
test_validator_missing_runtime() {
  local repo="$SCRATCHPAD/repo-valm-rt"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  setup_evidence_pack "$repo" "clean-pack" "$pack_head"

  local out="$SCRATCHPAD/vr-valm.json"
  local exit_code=0
  AID_PROJECT_ROOT="$repo" AID_VALIDATOR_PATH="/nonexistent/aid-protocol-validate.sh" \
    bash "$VERIFIER" "E-test" "clean-pack" --out "$out" 2>/dev/null || exit_code=$?

  assert_check_status "T12c/protocol_validate" "$out" "protocol_validate" "unverifiable"
  assert_json_field "T12c/verified" "$out" ".verification_report.summary.verified" "false"
  if [[ "$exit_code" -eq 1 ]]; then
    _pass "T12c/exit-1"
  else
    _fail "T12c/exit-1 (expected exit 1, got $exit_code)"
  fi
}

# ---------------------------------------------------------------------------
# T13: self-validate — verifier output passes protocol-validate
# ---------------------------------------------------------------------------
test_self_validate() {
  # Use the clean-pack output written by T01
  local vr_file="$SCRATCHPAD/vr-clean-pack.json"

  if [[ ! -f "$vr_file" ]]; then
    # Re-run clean-pack if file doesn't exist
    local repo="$SCRATCHPAD/repo-clean-t13"
    local pack_head
    pack_head=$(setup_git_repo "$repo")
    setup_evidence_pack "$repo" "clean-pack" "$pack_head"
    AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "clean-pack" --out "$vr_file" 2>/dev/null || true
  fi

  if [[ ! -f "$vr_file" ]]; then
    _fail "T13/self-validate (no vr file to validate)"
    return
  fi

  local val_exit=0
  bash "$VALIDATOR" "$vr_file" 2>/dev/null && val_exit=0 || val_exit=$?
  if [[ "$val_exit" -eq 0 ]]; then
    _pass "T13/self-validate (protocol-validate exit 0)"
  else
    _fail "T13/self-validate (protocol-validate exit $val_exit)"
  fi

  assert_json_field "T13/artifact_type" "$vr_file" ".artifact_type" "verification_report"
  assert_json_field "T13/verdict_kind"  "$vr_file" ".verdict.kind"  "none"
}

# ---------------------------------------------------------------------------
# T13b: self-validate failing pack — verification-report with findings[] passes
#       --check-fingerprint (verifies project_id consistency in fingerprints)
# ---------------------------------------------------------------------------
test_self_validate_with_findings() {
  local repo="$SCRATCHPAD/repo-self-val-findings"
  local pack_head
  pack_head=$(setup_git_repo "$repo")
  # dirty-git pack → git_clean:fail → produces findings[]
  touch "$repo/untracked-file-for-t13b.txt"
  setup_evidence_pack "$repo" "dirty-pack-t13b" "$pack_head"

  local out="$SCRATCHPAD/vr-findings.json"
  local exit_code=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "dirty-pack-t13b" --out "$out" 2>/dev/null || exit_code=$?

  if [[ "$exit_code" -ne 1 ]]; then
    _fail "T13b/exit-1 (expected exit 1, got $exit_code)"
    return
  fi
  _pass "T13b/exit-1"

  # Must have at least one finding
  local nf
  nf=$(jq '.findings | length' "$out" 2>/dev/null || echo 0)
  if [[ "$nf" -gt 0 ]]; then
    _pass "T13b/has-findings ($nf finding(s))"
  else
    _fail "T13b/has-findings (expected findings[], got 0)"
    return
  fi

  # Protocol-validate --check-fingerprint must exit 0 (project_id consistency)
  local val_exit=0
  bash "$VALIDATOR" "$out" --check-fingerprint 2>/dev/null && val_exit=0 || val_exit=$?
  if [[ "$val_exit" -eq 0 ]]; then
    _pass "T13b/check-fingerprint (findings[] fingerprints valid)"
  else
    _fail "T13b/check-fingerprint (protocol-validate --check-fingerprint exit $val_exit)"
  fi
}

# ---------------------------------------------------------------------------
# T15: waiver-mixed — E-063-1_1 reopen fix. A pack with ONE current derived
# artifact (delivery-gate.json, head_sha == current HEAD) PLUS ONE immutable
# historical waiver (head_sha == an ANCESTOR commit, not current HEAD) must
# verify as a whole under --at-head: the waiver must never be required to
# equal current HEAD (that would mean rewriting frozen history), but it must
# still be schema-valid and its recorded head_sha must be a real, reachable
# ancestor of current HEAD. All derived (non-waiver) artifacts still must be
# current-HEAD-fresh — unweakened.
# ---------------------------------------------------------------------------
test_waiver_mixed() {
  local repo="$SCRATCHPAD/repo-waiver-mixed"
  local historical_head current_head

  # Commit 1 — this becomes the waiver's frozen, historical HEAD.
  git init -q "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  echo ".aid-o/" > "$repo/.gitignore"
  echo "v1" > "$repo/README.md"
  git -C "$repo" add .gitignore README.md
  git -C "$repo" commit -q -m "first (waiver's recorded head)"
  historical_head=$(git -C "$repo" rev-parse HEAD)

  # Commit 2 — HEAD moves forward; this is where the derived artifact + the
  # verification run itself both live.
  echo "v2" >> "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "second (current HEAD)"
  current_head=$(git -C "$repo" rev-parse HEAD)

  local ev_dir="$repo/.aid-o/work/evidence/E-test/waiver-mixed"
  mkdir -p "$ev_dir"
  for src in "$FIXTURES_DIR/waiver-mixed/"*.json; do
    local dst="$ev_dir/$(basename "$src")"
    sed -e "s/__PACK_HEAD__/$current_head/g" \
        -e "s/__HISTORICAL_HEAD__/$historical_head/g" \
        "$src" > "$dst"
  done

  # --at-head: the derived artifact is fresh (== current_head); the waiver is
  # an ancestor, not equal — must still verify overall.
  local out="$SCRATCHPAD/vr-waiver-mixed.json"
  local exit_code=0
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "waiver-mixed" --at-head --out "$out" 2>/dev/null || exit_code=$?

  assert_check_status "T15/artifact_head_freshness" "$out" "artifact_head_freshness" "pass"
  assert_check_status "T15/protocol_validate"       "$out" "protocol_validate"       "pass"
  assert_json_field    "T15/verified"               "$out" ".verification_report.summary.verified" "true"
  if [[ "$exit_code" -eq 0 ]]; then
    _pass "T15/exit-0"
  else
    _fail "T15/exit-0 (expected exit 0, got $exit_code)"
  fi
}

# ---------------------------------------------------------------------------
# T16: waiver-mixed regression guard — if the waiver's recorded head_sha is
# NOT a real ancestor of current HEAD (a falsified/forged waiver, or one from
# an unrelated/rebased history), the pack must still fail. Proves the fix
# didn't just blanket-exempt every waiver from freshness scrutiny.
# ---------------------------------------------------------------------------
test_waiver_forged_ancestor() {
  local repo="$SCRATCHPAD/repo-waiver-forged"
  local current_head
  current_head=$(setup_git_repo "$repo")

  local ev_dir="$repo/.aid-o/work/evidence/E-test/waiver-forged"
  mkdir -p "$ev_dir"
  # delivery-gate.json: genuinely current.
  sed "s/__PACK_HEAD__/$current_head/g" \
    "$FIXTURES_DIR/waiver-mixed/delivery-gate.json" > "$ev_dir/delivery-gate.json"
  # waiver: head_sha is all-zeros — not a real commit anywhere.
  sed "s/__HISTORICAL_HEAD__/0000000000000000000000000000000000000000/g" \
    "$FIXTURES_DIR/waiver-mixed/waiver-historical.json" > "$ev_dir/waiver-historical.json"

  local out="$SCRATCHPAD/vr-waiver-forged.json"
  AID_PROJECT_ROOT="$repo" bash "$VERIFIER" "E-test" "waiver-forged" --out "$out" 2>/dev/null || true

  assert_check_status "T16/artifact_head_freshness" "$out" "artifact_head_freshness" "fail"
  assert_json_field    "T16/verified"               "$out" ".verification_report.summary.verified" "false"
}

# ---------------------------------------------------------------------------
# T14: golden sample validation
# ---------------------------------------------------------------------------
test_golden_sample() {
  if [[ ! -f "$GOLDEN_FILE" ]]; then
    _fail "T14/golden-sample (file not found: $GOLDEN_FILE)"
    return
  fi

  local val_exit=0
  bash "$VALIDATOR" "$GOLDEN_FILE" --check-fingerprint 2>/dev/null && val_exit=0 || val_exit=$?
  if [[ "$val_exit" -eq 0 ]]; then
    _pass "T14/golden-sample (passes protocol-validate --check-fingerprint)"
  else
    _fail "T14/golden-sample (protocol-validate --check-fingerprint exit $val_exit)"
  fi

  assert_json_field "T14/golden/artifact_type" "$GOLDEN_FILE" ".artifact_type" "verification_report"
  assert_json_field "T14/golden/verified"      "$GOLDEN_FILE" ".verification_report.summary.verified" "true"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  echo "=== test-evidence-verify.sh ==="

  test_clean_pack
  test_dirty_git
  test_ancestor_pack
  test_divergent_stale
  test_inconsistent_head
  test_invalid_artifact
  test_enum_garbage
  test_mixed_legacy
  test_nondeterministic_fingerprint
  test_ttl_violation
  test_enforcement_absent
  test_idempotency
  test_at_head_strict
  test_auto_detect
  test_validator_missing_runtime
  test_self_validate
  test_self_validate_with_findings
  test_waiver_mixed
  test_waiver_forged_ancestor
  test_golden_sample

  echo ""
  echo "Results: ${PASS} passed, ${FAIL} failed"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
