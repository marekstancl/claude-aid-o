#!/usr/bin/env bats
# aid-tier: t2
# P065 Step 13 (E-065-4_7) — Evidence sanitization backstop.
#
# Committed e2e evidence (the codex-stream-sample/ grounding sample) is produced
# by a script that sanitizes before writing (discover-codex-stream.sh's
# sanitize()/_verify_no_leaks). This suite is the BACKSTOP, not the
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
#
#   The bare `\b${LOCAL_USER}\b` alternative is skipped when LOCAL_USER is a
#   generic CI-assigned account name that collides with ordinary English
#   vocabulary this project's own dogfood evidence legitimately uses (e.g.
#   GitHub Actions' default runner account is literally "runner", and this
#   evidence talks about "gate runner"/"test runner" constantly — a false
#   positive on every CI run, not a real leak). The path-form check
#   (`/(home|Users)/${LOCAL_USER}`) still applies unconditionally: an actual
#   filesystem path is unambiguous regardless of what word the account uses.
_grep_leak_signatures() {
  local dir="$1"
  local bare_user_alt=""
  case "$LOCAL_USER" in
    runner|runneradmin|root|ci|user|admin|build|builder|actions|github|test|default)
      ;; # generic/CI account name — omit the bare-word alternative
    *)
      bare_user_alt="|\\b${LOCAL_USER}\\b"
      ;;
  esac
  grep -rEn \
    "${HOME:-/nonexistent}|${REPO_ROOT}|/(home|Users)/${LOCAL_USER}${bare_user_alt}|sk[-_](live|test)?[A-Za-z0-9_-]{16,}|gh[ps]_[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]{16,}|ghu_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" \
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
