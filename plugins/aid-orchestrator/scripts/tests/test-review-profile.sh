#!/usr/bin/env bash
# test-review-profile.sh — E3 Adaptive Review Profile resolver test harness
#
# Tests aid-prefilter.sh profile, aid-profile-hash.sh, review-profile-check.sh
# Exit: 0 if all pass, 1 if any fail
# Output: Results: X/Y passed, Z failed
#
# Acceptance criteria covered:
#   T01  docs-trivial: CHANGELOG.md → docs_trivial, 0 required_lenses
#   T02  docs-trivial-hidden-behavior: docs path + content signal → elevated risk
#   T03  e044-must-classify-high: scripts/lib/*.sh with signals → high
#   T04  mixed-surfaces: scripts + schemas → high, union of required_lenses
#   T05  medium-single-surface: commands/*.md → control_instruction (medium)
#   T06  clean-low: tests/*.sh with assert/PASS/FAIL signals → low
#   T07  unknown-surface: src/*.py (no match) → unverifiable
#   T08  unplanned-security-surface: new script not in plan → candidate adds scripts_core
#   T09  control-instruction-md: commands/*.md NOT docs_trivial
#   T10  range-undetermined: no --range, no fsm-state.yaml → exit 22
#   T11  stub-completed: empty required_lenses → review-profile-check exit 0
#   T12  profile_hash determinism
#   T13  missing lenses detected: review-profile-check exit 1 with lens names

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PREFILTER="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/aid-prefilter.sh"
CHECK_SCRIPT="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/lib/review-profile-check.sh"
HASH_LIB="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/lib/aid-profile-hash.sh"
PROFILES_FILE="${PLUGIN_ROOT}/plugins/aid-orchestrator/defaults/policies/review-profiles.yaml"

SCRATCHPAD="${TMPDIR:-/tmp}/aid-rp-test-$$"
mkdir -p "$SCRATCHPAD"
trap 'rm -rf "$SCRATCHPAD"' EXIT

PASS=0
FAIL=0

_pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "${label} (exit=${actual})"
  else
    _fail "${label} (expected=${expected}, got=${actual})"
  fi
}

assert_field() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    _pass "${label}"
  else
    _fail "${label}: expected='${expected}', got='${actual}'"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _pass "${label}"
  else
    _fail "${label}: '$needle' not found in output"
  fi
}

assert_not_equal() {
  local label="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != "$unexpected" ]]; then
    _pass "${label} (value='${actual}')"
  else
    _fail "${label}: expected value != '${unexpected}', but got that"
  fi
}

# ---------------------------------------------------------------------------
# setup_temp_repo: init a git repo with one base commit
# ---------------------------------------------------------------------------
setup_temp_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  echo "base" > "${dir}/base.txt"
  git -C "$dir" add base.txt
  git -C "$dir" commit -q -m "base commit"
}

# ---------------------------------------------------------------------------
# add_and_commit: write files into repo and commit
# Usage: add_and_commit <dir> <msg> <path1> <content1> [<path2> <content2> ...]
# ---------------------------------------------------------------------------
add_and_commit() {
  local dir="$1" msg="$2"
  shift 2
  while [[ $# -ge 2 ]]; do
    local fpath="$1" content="$2"
    shift 2
    mkdir -p "$(dirname "${dir}/${fpath}")"
    printf '%s\n' "$content" > "${dir}/${fpath}"
    git -C "$dir" add "${fpath}"
  done
  git -C "$dir" commit -q -m "$msg"
}

# ---------------------------------------------------------------------------
# run_profile: invoke aid-prefilter.sh profile; returns exit code via stdout
# Stdout from prefilter is suppressed (only exit code is echoed).
# ---------------------------------------------------------------------------
run_profile() {
  local repo="$1" epic_path="$2" out_path="$3"
  local ev_dir="${SCRATCHPAD}/ev-$$-${RANDOM}"
  mkdir -p "$ev_dir"
  local rc=0
  AID_PLUGIN_PATH="${PLUGIN_ROOT}/plugins/aid-orchestrator" \
  AID_PROJECT_ROOT="$repo" \
    bash "$PREFILTER" profile "$epic_path" "$ev_dir" \
    --range HEAD~1..HEAD --out "$out_path" >/dev/null 2>/dev/null || rc=$?
  echo "$rc"
}

# ---------------------------------------------------------------------------
# AC01: review-profiles.yaml enforcement + risk_profiles sanity check
# ---------------------------------------------------------------------------
AC01_RC=0
python3 -c "
import yaml, sys
d = yaml.safe_load(open('${PROFILES_FILE}'))
assert d.get('enforcement') == 'observe', 'enforcement != observe'
assert d.get('unknown_surface_profile') == 'unverifiable', 'unknown_surface_profile != unverifiable'
rp = d.get('risk_profiles', {})
for k in ['docs_trivial','low','medium','high','unverifiable']:
    assert k in rp, f'risk_profile {k} missing'
print('ok')
" 2>&1 && AC01_RC=0 || AC01_RC=1
assert_exit "AC01: review-profiles.yaml sanity (python3)" 0 "$AC01_RC"

# ---------------------------------------------------------------------------
# AC03: all lenses subset of C2 vocabulary
# ---------------------------------------------------------------------------
CONTROL_TOPO="${PLUGIN_ROOT}/plugins/aid-orchestrator/docs/design/control-topology.yaml"
if [[ -f "$CONTROL_TOPO" ]]; then
  AC03_RC=0
  python3 -c "
import yaml, sys
profiles = yaml.safe_load(open('${PROFILES_FILE}'))
topo = yaml.safe_load(open('${CONTROL_TOPO}'))
c2_lenses = set(topo.get('C2',{}).get('lenses', []))
if not c2_lenses:
    # Try alternate path
    c2_lenses = set(topo.get('mechanisms',{}).get('C2',{}).get('lenses', []))
all_lenses = set()
for s in profiles.get('surfaces',{}).values():
    all_lenses.update(s.get('lenses', []))
for rp in profiles.get('risk_profiles',{}).values():
    all_lenses.update(rp.get('mandatory_lenses', []))
unknown = all_lenses - c2_lenses
if unknown:
    print(f'FAIL: lenses not in C2 vocab: {unknown}', file=sys.stderr)
    sys.exit(1)
print('ok: all lenses in C2 vocab')
" 2>&1 && AC03_RC=0 || AC03_RC=1
  assert_exit "AC03: all lenses in C2 vocabulary" 0 "$AC03_RC"
else
  echo "SKIP: AC03 (control-topology.yaml not found at $CONTROL_TOPO)"
fi

# ===========================================================================
# T01: docs-trivial — CHANGELOG.md → docs_trivial, no required_lenses
# ===========================================================================
T01_REPO="${SCRATCHPAD}/t01"
setup_temp_repo "$T01_REPO"
add_and_commit "$T01_REPO" "docs change" \
  "CHANGELOG.md" "## v1.0 - added thing"
T01_OUT="${SCRATCHPAD}/t01-profile.json"
T01_RC=$(run_profile "$T01_REPO" "/dev/null" "$T01_OUT")
assert_exit "T01: docs-trivial exit" 0 "$T01_RC"
T01_RISK=$(jq -r '.review_profile.risk_profile' "$T01_OUT" 2>/dev/null || echo "")
assert_field "T01: risk_profile=docs_trivial" "docs_trivial" "$T01_RISK"
T01_LENSES=$(jq '.review_profile.required_lenses | length' "$T01_OUT" 2>/dev/null || echo "-1")
assert_field "T01: required_lenses empty (length=0)" "0" "$T01_LENSES"

# ===========================================================================
# T02: docs-trivial-hidden-behavior — docs path + behavioral content signal
#      cmd_ and transition in content → scripts_core added by content signal
# ===========================================================================
T02_REPO="${SCRATCHPAD}/t02"
setup_temp_repo "$T02_REPO"
add_and_commit "$T02_REPO" "hidden behavior in docs" \
  "docs/api-notes.md" "$(printf 'Notes about the API\ncmd_route handler\ntransition table\n')"
T02_OUT="${SCRATCHPAD}/t02-profile.json"
T02_RC=$(run_profile "$T02_REPO" "/dev/null" "$T02_OUT")
assert_exit "T02: docs-hidden-behavior exit" 0 "$T02_RC"
T02_RISK=$(jq -r '.review_profile.risk_profile' "$T02_OUT" 2>/dev/null || echo "")
T02_CAND=$(jq -r '.review_profile.candidate_time_surfaces | join(",")' "$T02_OUT" 2>/dev/null || echo "")
# scripts_core should be detected via content signal (cmd_, transition)
assert_contains "T02: candidate includes scripts_core" "$T02_CAND" "scripts_core"
# risk must be elevated from docs_trivial
assert_not_equal "T02: risk elevated from docs_trivial" "docs_trivial" "$T02_RISK"

# ===========================================================================
# T03: e044-must-classify-high — scripts/lib/*.sh with signals → high
# ===========================================================================
T03_REPO="${SCRATCHPAD}/t03"
setup_temp_repo "$T03_REPO"
add_and_commit "$T03_REPO" "high risk scripts" \
  "plugins/aid-orchestrator/scripts/lib/new-tool.sh" \
  "$(printf '#!/usr/bin/env bash\ncmd_run() { transition READY EXECUTE; log_event timeline start; }\ndie "fatal"; exit 1\n')"
T03_OUT="${SCRATCHPAD}/t03-profile.json"
T03_RC=$(run_profile "$T03_REPO" "/dev/null" "$T03_OUT")
assert_exit "T03: e044-high exit" 0 "$T03_RC"
T03_RISK=$(jq -r '.review_profile.risk_profile' "$T03_OUT" 2>/dev/null || echo "")
assert_field "T03: risk_profile=high" "high" "$T03_RISK"

# ===========================================================================
# T04: mixed-surfaces — scripts + schemas → high (max), union required_lenses
# ===========================================================================
T04_REPO="${SCRATCHPAD}/t04"
setup_temp_repo "$T04_REPO"
add_and_commit "$T04_REPO" "mixed surfaces" \
  "plugins/aid-orchestrator/scripts/aid-new.sh" \
    "$(printf 'cmd_do() { transition; log_event x; }\nexit 0\n')" \
  "plugins/aid-orchestrator/defaults/schemas/new.json" \
    '{"required": ["field_a"], "enforcement": "observe"}'
T04_OUT="${SCRATCHPAD}/t04-profile.json"
T04_RC=$(run_profile "$T04_REPO" "/dev/null" "$T04_OUT")
assert_exit "T04: mixed-surfaces exit" 0 "$T04_RC"
T04_RISK=$(jq -r '.review_profile.risk_profile' "$T04_OUT" 2>/dev/null || echo "")
assert_field "T04: risk_profile=high (max of high+medium)" "high" "$T04_RISK"
T04_MATCHED=$(jq -r '.review_profile.matched_surfaces | join(",")' "$T04_OUT" 2>/dev/null || echo "")
assert_contains "T04: matched includes scripts_core" "$T04_MATCHED" "scripts_core"
assert_contains "T04: matched includes schemas_and_policies" "$T04_MATCHED" "schemas_and_policies"
T04_LENSES=$(jq -r '.review_profile.required_lenses | join(",")' "$T04_OUT" 2>/dev/null || echo "")
assert_contains "T04: union includes security_threat_model" "$T04_LENSES" "security_threat_model"
assert_contains "T04: union includes field_lineage" "$T04_LENSES" "field_lineage"
assert_contains "T04: union includes behavior_trace" "$T04_LENSES" "behavior_trace"

# ===========================================================================
# T05: medium-single-surface — command .md → control_instruction (medium)
# ===========================================================================
T05_REPO="${SCRATCHPAD}/t05"
setup_temp_repo "$T05_REPO"
add_and_commit "$T05_REPO" "control instruction change" \
  "plugins/aid-orchestrator/commands/aid-run.md" "Updated dispatch step instructions"
T05_OUT="${SCRATCHPAD}/t05-profile.json"
T05_RC=$(run_profile "$T05_REPO" "/dev/null" "$T05_OUT")
assert_exit "T05: control-instruction exit" 0 "$T05_RC"
T05_RISK=$(jq -r '.review_profile.risk_profile' "$T05_OUT" 2>/dev/null || echo "")
assert_field "T05: risk_profile=medium" "medium" "$T05_RISK"
T05_MATCHED=$(jq -r '.review_profile.matched_surfaces | join(",")' "$T05_OUT" 2>/dev/null || echo "")
assert_contains "T05: matched=control_instruction" "$T05_MATCHED" "control_instruction"

# ===========================================================================
# T06: clean-low — bats test file (only matches test_harness, not scripts_core) → low
# NOTE: .sh files under scripts/tests/ also match scripts_core (risk=high) because
# scripts_core glob is scripts/**/*.sh which includes scripts/tests/*.sh.
# Use a .bats file under scripts/tests/bats/ to isolate test_harness surface only.
# ===========================================================================
T06_REPO="${SCRATCHPAD}/t06"
setup_temp_repo "$T06_REPO"
add_and_commit "$T06_REPO" "test harness change" \
  "plugins/aid-orchestrator/scripts/tests/bats/test-foo.bats" \
    "$(printf '@test "assert example" {\n  assert_output "PASS"\n  # Results: 1/1 passed, 0 failed\n}\n')"
T06_OUT="${SCRATCHPAD}/t06-profile.json"
T06_RC=$(run_profile "$T06_REPO" "/dev/null" "$T06_OUT")
assert_exit "T06: clean-low exit" 0 "$T06_RC"
T06_RISK=$(jq -r '.review_profile.risk_profile' "$T06_OUT" 2>/dev/null || echo "")
assert_field "T06: risk_profile=low" "low" "$T06_RISK"
T06_MATCHED=$(jq -r '.review_profile.matched_surfaces | join(",")' "$T06_OUT" 2>/dev/null || echo "")
assert_contains "T06: matched=test_harness" "$T06_MATCHED" "test_harness"

# ===========================================================================
# T07: unknown-surface — src/*.py (no surface match, no docs_allowlist) → unverifiable
# ===========================================================================
T07_REPO="${SCRATCHPAD}/t07"
setup_temp_repo "$T07_REPO"
add_and_commit "$T07_REPO" "unknown production file" \
  "src/some-production-module.py" "def handle_request(): pass"
T07_OUT="${SCRATCHPAD}/t07-profile.json"
T07_RC=$(run_profile "$T07_REPO" "/dev/null" "$T07_OUT")
assert_exit "T07: unknown-surface exit" 0 "$T07_RC"
T07_RISK=$(jq -r '.review_profile.risk_profile' "$T07_OUT" 2>/dev/null || echo "")
assert_field "T07: risk_profile=unverifiable" "unverifiable" "$T07_RISK"

# ===========================================================================
# T08: unplanned-security-surface — candidate-time diff adds scripts_core
#      (plan is /dev/null, but actual diff has a script → candidate adds it)
# ===========================================================================
T08_REPO="${SCRATCHPAD}/t08"
setup_temp_repo "$T08_REPO"
add_and_commit "$T08_REPO" "new script added" \
  "plugins/aid-orchestrator/scripts/aid-new-security.sh" \
    "$(printf 'cmd_check() { log_event audit; exit 0; }\n')"
T08_OUT="${SCRATCHPAD}/t08-profile.json"
T08_RC=$(run_profile "$T08_REPO" "/dev/null" "$T08_OUT")
assert_exit "T08: unplanned-security exit" 0 "$T08_RC"
T08_CAND=$(jq -r '.review_profile.candidate_time_surfaces | join(",")' "$T08_OUT" 2>/dev/null || echo "")
assert_contains "T08: candidate adds scripts_core" "$T08_CAND" "scripts_core"
T08_RISK=$(jq -r '.review_profile.risk_profile' "$T08_OUT" 2>/dev/null || echo "")
assert_field "T08: risk=high (not invalidated, just extended)" "high" "$T08_RISK"

# ===========================================================================
# T09: control-instruction-md — commands/*.md is NOT docs_trivial
# ===========================================================================
T09_REPO="${SCRATCHPAD}/t09"
setup_temp_repo "$T09_REPO"
add_and_commit "$T09_REPO" "update command instruction" \
  "plugins/aid-orchestrator/commands/aid-plan.md" "Updated planning instructions"
T09_OUT="${SCRATCHPAD}/t09-profile.json"
T09_RC=$(run_profile "$T09_REPO" "/dev/null" "$T09_OUT")
assert_exit "T09: control-instruction-md exit" 0 "$T09_RC"
T09_RISK=$(jq -r '.review_profile.risk_profile' "$T09_OUT" 2>/dev/null || echo "")
assert_not_equal "T09: NOT docs_trivial" "docs_trivial" "$T09_RISK"
assert_field "T09: risk_profile=medium (control_instruction)" "medium" "$T09_RISK"

# ===========================================================================
# T10: range-undetermined — no --range and no fsm-state.yaml → exit 22
# ===========================================================================
T10_REPO="${SCRATCHPAD}/t10"
setup_temp_repo "$T10_REPO"
add_and_commit "$T10_REPO" "change" "some.txt" "content"
T10_EVIDENCE="${SCRATCHPAD}/t10-evidence"
mkdir -p "$T10_EVIDENCE"
# No fsm-state.yaml in evidence dir, no --range → range_undetermined
T10_OUT="${SCRATCHPAD}/t10-profile.json"
T10_RC=0
AID_PLUGIN_PATH="${PLUGIN_ROOT}/plugins/aid-orchestrator" \
AID_PROJECT_ROOT="$T10_REPO" \
  bash "$PREFILTER" profile "/dev/null" "$T10_EVIDENCE" --out "$T10_OUT" 2>/dev/null \
  || T10_RC=$?
assert_exit "T10: range-undetermined exit=22" 22 "$T10_RC"
if [[ -f "$T10_OUT" ]]; then
  T10_RISK=$(jq -r '.review_profile.risk_profile' "$T10_OUT" 2>/dev/null || echo "")
  assert_field "T10: risk_profile=unverifiable" "unverifiable" "$T10_RISK"
else
  _fail "T10: review-profile.json not written on exit 22"
fi

# ===========================================================================
# T11: stub-completed — empty required_lenses → review-profile-check exit 0
# ===========================================================================
T11_EVIDENCE="${SCRATCHPAD}/t11-evidence"
mkdir -p "$T11_EVIDENCE"
python3 -c "
import json
d = {
  'schema_version': 'aid-2.0',
  'artifact_type': 'review_profile',
  'review_profile': {
    'required_lenses': [],
    'profile_hash': 'sha256:' + '0' * 64,
    'matched_surfaces': [],
    'plan_time_surfaces': [],
    'candidate_time_surfaces': [],
    'risk_profile': 'docs_trivial',
    'ir_cadence': 1,
    'c2_authorities_max': 0,
    'llm_authorities_total_max': 0
  }
}
import sys
json.dump(d, open('${T11_EVIDENCE}/review-profile.json', 'w'))
"
T11_RC=0
bash "$CHECK_SCRIPT" "${T11_EVIDENCE}/review-profile.json" "$T11_EVIDENCE" 2>/dev/null \
  || T11_RC=$?
assert_exit "T11: stub-completed check exit=0" 0 "$T11_RC"

# ===========================================================================
# T12: profile_hash determinism
# ===========================================================================
H1=$(bash "$HASH_LIB" profile_hash "proj" "scripts_core" \
  "scripts_core schemas_and_policies" "behavior_trace security_threat_model")
H2=$(bash "$HASH_LIB" profile_hash "proj" "scripts_core" \
  "scripts_core schemas_and_policies" "behavior_trace security_threat_model")
if [[ "$H1" == "$H2" && -n "$H1" ]]; then
  _pass "T12: profile_hash determinism"
else
  _fail "T12: profile_hash NOT deterministic (H1='$H1', H2='$H2')"
fi

# ===========================================================================
# T13: missing lenses detected — review-profile-check exit=1, lens names in output
# ===========================================================================
T13_EVIDENCE="${SCRATCHPAD}/t13-evidence"
mkdir -p "$T13_EVIDENCE"
python3 -c "
import json
d = {
  'schema_version': 'aid-2.0',
  'artifact_type': 'review_profile',
  'review_profile': {
    'required_lenses': ['behavior_trace'],
    'profile_hash': 'sha256:' + '0' * 64,
    'matched_surfaces': ['scripts_core'],
    'plan_time_surfaces': [],
    'candidate_time_surfaces': ['scripts_core'],
    'risk_profile': 'high',
    'ir_cadence': 3,
    'c2_authorities_max': 3,
    'llm_authorities_total_max': 5
  }
}
import sys
json.dump(d, open('${T13_EVIDENCE}/review-profile.json', 'w'))
"
T13_RC=0
T13_OUT=$(bash "$CHECK_SCRIPT" "${T13_EVIDENCE}/review-profile.json" "$T13_EVIDENCE" 2>/dev/null) \
  || T13_RC=$?
assert_exit "T13: missing lenses → exit=1" 1 "$T13_RC"
assert_contains "T13: missing lenses in stdout" "$T13_OUT" "behavior_trace"

# ===========================================================================
# T14: plan declares scripts path, diff is docs only → union expands profile
# ===========================================================================
T14_REPO="${SCRATCHPAD}/t14"
setup_temp_repo "$T14_REPO"
# Create a mini plan file that declares scripts path
T14_PLAN="${SCRATCHPAD}/t14-plan.md"
cat > "$T14_PLAN" << 'PLAN'
# Plan P-TEST

## Scope

**Files:**
- plugins/aid-orchestrator/scripts/aid-new.sh

## Steps
nothing
PLAN
# Diff only touches README.md (docs_content)
add_and_commit "$T14_REPO" "docs only change" \
  "README.md" "Updated docs"
T14_OUT="${SCRATCHPAD}/t14-profile.json"
T14_RC=$(run_profile "$T14_REPO" "$T14_PLAN" "$T14_OUT")
assert_exit "T14: plan-declares-scripts exit" 0 "$T14_RC"
T14_PLAN_S=$(jq -r '.review_profile.plan_time_surfaces | join(",")' "$T14_OUT" 2>/dev/null)
T14_CAND_S=$(jq -r '.review_profile.candidate_time_surfaces | join(",")' "$T14_OUT" 2>/dev/null)
T14_RISK=$(jq -r '.review_profile.risk_profile' "$T14_OUT" 2>/dev/null)
assert_contains "T14: plan declares scripts_core" "$T14_PLAN_S" "scripts_core"
assert_contains "T14: candidate has docs_content" "$T14_CAND_S" "docs_content"
# Union should elevate risk beyond docs_trivial
if [[ "$T14_RISK" != "docs_trivial" ]]; then _pass "T14: risk elevated by plan-time (=$T14_RISK)"
else _fail "T14: risk NOT elevated by plan-time surface — union broken"; fi

# ===========================================================================
# Results
# ===========================================================================
echo ""
TOTAL=$(( PASS + FAIL ))
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
