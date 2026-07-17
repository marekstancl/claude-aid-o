#!/usr/bin/env bats
# P065 Step 13 (E-065-4_7) — Evidence sanitization backstop.
#
# Committed e2e evidence (the P065 Step 1 codex-stream-sample/ grounding
# sample, and the Step 13 c3-dogfood-fixture/ + c3-dogfood-live-attestation.md
# dogfood proof) is produced by scripts that sanitize before writing
# (discover-codex-stream.sh's sanitize()/_verify_no_leaks, c3-dogfood.sh's
# _sanitize_file()/_verify_no_leaks_dir()). This suite is the BACKSTOP, not the
# only line of defense: it independently greps every committed evidence dir for
# leak signatures and fails the build if any is found, so a future manual edit
# or a harness regression cannot silently reintroduce a leak.
#
# Signatures checked (mirrors the two harnesses' own sanitizer patterns):
#   - absolute $HOME / /home/<user>/ / /Users/<user>/ paths
#   - the current checkout's absolute repo root path
#   - the local account name (`whoami`) as a whole word
#   - token-shaped strings: sk-/sk_, gh[ps]_/gho_/ghu_/github_pat_, AKIA,
#     xox[baprs]-, PEM private key blocks, Bearer tokens, JWT (eyJ...) triples

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  E2E_EVIDENCE_DIR="$REPO_ROOT/plugins/aid-orchestrator/scripts/tests/e2e/evidence"
  export E2E_EVIDENCE_DIR
  LOCAL_USER="$(id -un 2>/dev/null || echo user)"
  export LOCAL_USER
}

# _grep_leak_signatures <dir>
#   Prints any matching line (with filename) across every file in <dir> for a
#   leak signature; returns 0 (found something) iff at least one match exists.
_grep_leak_signatures() {
  local dir="$1"
  grep -rEn \
    "${HOME:-/nonexistent}|${REPO_ROOT}|/(home|Users)/${LOCAL_USER}|\\b${LOCAL_USER}\\b|sk[-_](live|test)?[A-Za-z0-9_-]{16,}|gh[ps]_[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]{16,}|ghu_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" \
    "$dir" 2>/dev/null
}

@test "e2e evidence: codex-stream-sample/ exists and is committed" {
  [ -d "$E2E_EVIDENCE_DIR/codex-stream-sample" ]
  [ -f "$E2E_EVIDENCE_DIR/codex-stream-sample/events.jsonl" ]
  [ -f "$E2E_EVIDENCE_DIR/codex-stream-sample/fields.md" ]
}

@test "e2e evidence: codex-stream-sample/ contains no leak signatures" {
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/codex-stream-sample"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "e2e evidence: c3-dogfood-live-attestation.md exists and is committed" {
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-live-attestation.md" ]
}

@test "e2e evidence: c3-dogfood-live-attestation.md contains no leak signatures" {
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-live-attestation.md"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "e2e evidence: c3-dogfood-live-attestation.md records the required attestation fields" {
  grep -qE '^\| codex_version \| `codex-cli' "$E2E_EVIDENCE_DIR/c3-dogfood-live-attestation.md"
  grep -qE '^\| codex_session_id \(prefix only\) \| `.{8,}\.\.\.`' "$E2E_EVIDENCE_DIR/c3-dogfood-live-attestation.md"
  grep -qE '^live_verify: passed$' "$E2E_EVIDENCE_DIR/c3-dogfood-live-attestation.md"
}

@test "e2e evidence: c3-dogfood-fixture/ exists and is committed" {
  [ -d "$E2E_EVIDENCE_DIR/c3-dogfood-fixture" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture/audit-input-manifest.json" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture/audit-report.json" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture/c3/c3-dispatch.json" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture/c3/codex-last-message.json" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture/c3/codex-events.jsonl" ]
}

@test "e2e evidence: c3-dogfood-fixture/ contains no leak signatures" {
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-fixture"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "e2e evidence: c3-dogfood-fixture/ passes aid-c3-dispatch.sh verify --reference" {
  local dispatch="$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh"
  run bash "$dispatch" verify --reference "$E2E_EVIDENCE_DIR/c3-dogfood-fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}

# --- IMP-245 follow-up: real-AC dogfood proof (pass + fail, both determinate) ---

@test "e2e evidence: c3-dogfood-fixture-real-ac-pass/ exists, is committed, and is a determinate pass" {
  [ -d "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass/audit-report.json" ]
  run jq -r '.status' "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass/audit-report.json"
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "e2e evidence: c3-dogfood-fixture-real-ac-fail/ exists, is committed, and is a determinate fail" {
  [ -d "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail/audit-report.json" ]
  run jq -r '.status' "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail/audit-report.json"
  [ "$status" -eq 0 ]
  [ "$output" = "fail" ]
  run jq -r '.audit_report.blocking_findings' "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail/audit-report.json"
  [ "$output" = "true" ]
}

@test "e2e evidence: c3-dogfood-fixture-real-ac-{pass,fail}/ contain no leak signatures" {
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "e2e evidence: c3-dogfood-fixture-real-ac-{pass,fail}-live-attestation.md exist and contain no leak signatures" {
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass-live-attestation.md" ]
  [ -f "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail-live-attestation.md" ]
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass-live-attestation.md"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run _grep_leak_signatures "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail-live-attestation.md"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "e2e evidence: c3-dogfood-fixture-real-ac-{pass,fail}/ both pass aid-c3-dispatch.sh verify --reference" {
  local dispatch="$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh"
  run bash "$dispatch" verify --reference "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-pass"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
  run bash "$dispatch" verify --reference "$E2E_EVIDENCE_DIR/c3-dogfood-fixture-real-ac-fail"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}
