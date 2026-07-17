#!/usr/bin/env bash
# =============================================================================
# c3-dogfood-real-ac.sh — P065 IMP-245 follow-up: real Codex dispatch against a
# minimal, REAL acceptance-criteria document, proving the C3 bridge can reach
# a determinate pass/fail verdict — not just honestly decline one.
#
# c3-dogfood.sh (the original E-065-4_7 dogfood) proves the bridge is
# trustworthy when it declines: its throwaway diff deliberately carries no
# real plan/AC, so Codex correctly reports review_status:"unverifiable" for a
# legitimate reason (no AC to check against). That is necessary but not
# sufficient — IMP-245's actual goal was "an empty allowed_recheck_commands
# must not prevent a normal pass/fail review", not "unverifiable is fine".
# This script supplies a REAL, tiny AC document (via AID_PLAN_AC_FILE) tied to
# a REAL, checkable diff, so Codex has everything it needs to render an actual
# verdict using only the always-allowed reads (no recheck commands needed).
#
# Runs TWO independent real dispatches, each on its own throwaway branch:
#   1. PASS case   — a diff that clearly satisfies the AC.
#   2. FAIL case   — a diff that clearly violates the AC (wrong arithmetic +
#      missing required comment).
# Each produces its own committed, sanitized fixture
# (c3-dogfood-fixture-real-ac-pass/, c3-dogfood-fixture-real-ac-fail/) plus a
# live attestation, mirroring c3-dogfood.sh's sanitize/verify/FSM-demo
# structure. Both real session ids are independently leak-checked afterward.
#
# Usage: c3-dogfood-real-ac.sh
# Exit codes: 0 both cases produced the EXPECTED determinate verdict and
# passed every check; 1 otherwise (see stderr for which check failed).
#
# Requirements: bash 4+, jq, git, sha256sum, codex CLI (>= 0.143.0) authenticated.
#
# **Last Updated:** 2026-07-16
# =============================================================================
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$E2E_DIR/../../.." && pwd)"
DISPATCH_BIN="$PLUGIN_DIR/scripts/lib/aid-c3-dispatch.sh"
INDEP_BIN="$PLUGIN_DIR/scripts/lib/aid-audit-independence.sh"
FSM_BIN="$PLUGIN_DIR/scripts/aid-fsm.sh"
VALIDATE_BIN="$PLUGIN_DIR/scripts/aid-protocol-validate.sh"

for f in "$DISPATCH_BIN" "$INDEP_BIN" "$FSM_BIN" "$VALIDATE_BIN"; do
  [[ -f "$f" ]] || { echo "ERROR: required script missing: $f" >&2; exit 1; }
done
for c in jq git sha256sum; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c required in PATH" >&2; exit 1; }
done

REPO_ROOT="$(cd "$E2E_DIR" && git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "ERROR: $E2E_DIR is not inside a git repository" >&2; exit 1; }

PLACEHOLDER_SESSION_ID="00000000-0000-7000-8000-000000000000"

codex_available=1
if ! command -v codex >/dev/null 2>&1; then
  codex_available=0
elif ! bash "$INDEP_BIN" detect --required cross_provider >/dev/null 2>&1; then
  codex_available=0
fi
if [[ "$codex_available" -eq 0 ]]; then
  if [[ -d "$E2E_DIR/evidence/c3-dogfood-fixture-real-ac-pass" && -d "$E2E_DIR/evidence/c3-dogfood-fixture-real-ac-fail" ]]; then
    echo "REAL-AC DOGFOOD SKIPPED: codex auth unavailable"
    exit 0
  else
    echo "REAL-AC DOGFOOD FAILED: codex auth unavailable AND no prior committed proof exists." >&2
    exit 1
  fi
fi

[[ -z "$(cd "$REPO_ROOT" && git status --porcelain)" ]] \
  || { echo "ERROR: working tree is not clean — refusing to start (commit/stash first)." >&2; exit 1; }
ORIG_BRANCH="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD)"
[[ "$ORIG_BRANCH" != "HEAD" ]] \
  || { echo "ERROR: repo is in detached HEAD state — refusing to start." >&2; exit 1; }

# ---------------------------------------------------------------------------
# Shared sanitizer (same approach as c3-dogfood.sh's _sanitize_file).
# ---------------------------------------------------------------------------
_escape_ere_pattern() { sed -e 's/[.[\*^$()+?{}|#\\]/\\&/g'; }

_sanitize_file() {
  local f="$1" session_id="$2" user home_esc repo_esc user_esc session_esc tmp
  [[ -f "$f" ]] || return 0
  user="$(id -un 2>/dev/null || echo user)"
  home_esc="$(printf '%s' "${HOME:-/nonexistent}" | _escape_ere_pattern)"
  repo_esc="$(printf '%s' "$REPO_ROOT" | _escape_ere_pattern)"
  user_esc="$(printf '%s' "$user" | _escape_ere_pattern)"
  tmp="$f.sanitized.$$"
  local -a sed_args=(
    -e "s#${repo_esc}#<REPO>#g"
    -e "s#${home_esc}#<HOME>#g"
    -e "s#/(home|Users)/${user_esc}#<HOME>#g"
    -e "s#\\b${user_esc}\\b#<USER>#g"
  )
  if [[ -n "$session_id" ]]; then
    session_esc="$(printf '%s' "$session_id" | _escape_ere_pattern)"
    sed_args+=(-e "s#${session_esc}#${PLACEHOLDER_SESSION_ID}#g")
  fi
  sed_args+=(
    -e 's#sk[-_](live|test)?[A-Za-z0-9_-]{16,}#<REDACTED_TOKEN>#g'
    -e 's#gh[ps]_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g'
    -e 's#gho_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g'
    -e 's#ghu_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g'
    -e 's#github_pat_[A-Za-z0-9_]{16,}#<REDACTED_TOKEN>#g'
    -e 's#AKIA[0-9A-Z]{16}#<REDACTED_TOKEN>#g'
    -e 's#xox[baprs]-[A-Za-z0-9-]{10,}#<REDACTED_TOKEN>#g'
    -e 's#-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----#<REDACTED_PRIVATE_KEY>#g'
    -e 's#([Aa]uthorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1<REDACTED_TOKEN>#g'
    -e 's#eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+#<REDACTED_JWT>#g'
  )
  sed -E "${sed_args[@]}" "$f" > "$tmp" && mv "$tmp" "$f"
}

_verify_no_leaks_dir() {
  local dir="$1" user f
  user="$(id -un 2>/dev/null || echo user)"
  while IFS= read -r -d '' f; do
    if grep -qE "${HOME:-/nonexistent}|${REPO_ROOT}|/(home|Users)/${user}|\\b${user}\\b|sk[-_](live|test)?[A-Za-z0-9_-]{16,}|gh[ps]_[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]{16,}|ghu_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "$f" 2>/dev/null; then
      echo "SANITIZE_LEAK_DETECTED: residual secret/path signature in $f" >&2
      return 1
    fi
  done < <(find "$dir" -type f -print0)
  return 0
}

# _seed_and_run_done_advance <worktree_dir> <evidence_src_dir>
# Same seeding pattern as c3-dogfood.sh — isolated worktree pinned at the exact
# commit the live run reviewed, standard DONE/review scaffold, enforcement:blocking
# pinned. Sets LAST_FSM_RC/LAST_FSM_OUT.
_seed_and_run_done_advance() {
  local root="$1" src="$2"
  local evidence="$root/.aid-o/work/evidence/E-c3-dogfood-real-ac/R-demo"
  mkdir -p "$evidence/c3" "$evidence/gates" "$root/.aid-o/tasks" "$root/.aid-o/work" "$root/.aid-o/config"
  cp "$src/audit-input-manifest.json" "$evidence/audit-input-manifest.json"
  cp "$src/audit-report.json"          "$evidence/audit-report.json"
  cp "$src/audit-report.md"            "$evidence/audit-report.md"
  cp "$src"/c3/*                       "$evidence/c3/"
  local state_file="$evidence/fsm-state.yaml"
  cat > "$state_file" <<YAML
epic_id: E-c3-dogfood-real-ac
run_id: R-demo
branch: task/E-c3-dogfood-real-ac/main
state: DONE
done_phase: review
created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
total_steps: 1
current_step: 1
pm_decision: merge
YAML
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@c3-dogfood-real-ac","_generated_at":"%s","_command_log":[]}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$evidence/gates/gates_report.json"
  touch "$root/.aid-o/work/audit-log.jsonl"
  printf 'project_id: ai-orchestrator\n' > "$root/.aid-o/config/project.yaml"
  printf '{"review_profile": {"risk_profile": "high"}}\n' > "$evidence/review-profile.json"
  local curator_hash
  curator_hash="$(sha256sum "$evidence/audit-report.json" | awk '{print $1}')"
  printf '{"curator": {"audit_report_ref": "sha256:%s"}}\n' "$curator_hash" > "$evidence/curator-report.json"
  printf 'curator report\n' > "$evidence/curator-report.md"
  local blocking_policy="$root/.aid-o/c3-audit-policy-blocking.yaml"
  cat > "$blocking_policy" <<'YAML'
version: 1
enforcement: blocking
risk_profiles:
  high:
    c3_required: true
    required_independence_level: cross_model
  unverifiable:
    c3_required: true
    required_independence_level: cross_provider
YAML
  set +e
  LAST_FSM_OUT="$(cd "$root" && AID_TEST_MODE=1 C3_AUDIT_POLICY="$blocking_policy" \
    bash "$FSM_BIN" done-advance review release "$state_file" 2>&1)"
  LAST_FSM_RC=$?
  set -e
}

# ---------------------------------------------------------------------------
# _run_case <label> <expect_review_status> <file_content> <ac_content> <fixture_dirname>
#   Drives one full throwaway-branch → build-manifest → dispatch → live verify
#   → sanitize/commit-fixture → negative control → FSM demo cycle. Cleans up
#   its own throwaway branch/commit/evidence unconditionally on exit.
# ---------------------------------------------------------------------------
_run_case() {
  local label="$1" expect_status="$2" file_content="$3" ac_content="$4" fixture_dirname="$5"
  echo "== c3-dogfood-real-ac [$label]: starting =="

  local demo_file="scripts/e2e-ac-demo/increment.sh"
  local throwaway_branch="c3-dogfood-real-ac-${label}-throwaway-$$"
  local run_evidence_dir="$REPO_ROOT/.aid-o/work/evidence/E-c3-dogfood-real-ac/R-${label}-$$"
  local case_rc=0

  # SECURITY REVIEW FIX: branch creation happens inside the ( ... ) subshell
  # below, so a "branch_created" flag set there could never be observed by
  # this outer function (subshells cannot write back to the parent shell's
  # variables) — that flag existed here before and was permanently 0, making
  # the `git branch -D` cleanup dead code on every run (confirmed: two stale
  # throwaway branches were left behind by a real run). Fixed by always
  # attempting the delete unconditionally — harmless/idempotent if the branch
  # was never created (e.g. an early failure before `git checkout -b` ran).
  # Also registers an EXIT trap (matching c3-dogfood.sh's `trap cleanup
  # EXIT`) so cleanup still runs if this case is interrupted (signal) mid-run,
  # not only on normal completion.
  _case_cleanup() {
    set +e
    local cur_branch
    cur_branch="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    if [[ "$cur_branch" != "$ORIG_BRANCH" ]]; then
      (cd "$REPO_ROOT" && git checkout -q "$ORIG_BRANCH") 2>/dev/null
    fi
    (cd "$REPO_ROOT" && git branch -D "$throwaway_branch") >/dev/null 2>&1
    rm -rf "$run_evidence_dir" 2>/dev/null
  }
  trap _case_cleanup EXIT

  (
    set -euo pipefail
    cd "$REPO_ROOT"
    git checkout -q -b "$throwaway_branch"
    local base_sha head_sha
    base_sha="$(git rev-parse HEAD)"

    mkdir -p "$(dirname "$demo_file")"
    printf '%s' "$file_content" > "$demo_file"
    git add "$demo_file"
    git commit -q -m "chore(c3-dogfood-real-ac): [$label] diagnostic AC-demo diff (never merged)"
    head_sha="$(git rev-parse HEAD)"
    echo "== c3-dogfood-real-ac [$label]: base=${base_sha:0:12} head=${head_sha:0:12} =="

    mkdir -p "$run_evidence_dir"
    local ac_file="$run_evidence_dir/ac-demo-plan.md"
    printf '%s' "$ac_content" > "$ac_file"
    local changed_paths_file="$run_evidence_dir/changed-paths.txt"
    printf '%s\n' "$demo_file" > "$changed_paths_file"

    AID_CHANGED_PATHS="$changed_paths_file" AID_PLAN_AC_FILE="$ac_file" \
      bash "$DISPATCH_BIN" build-manifest "$run_evidence_dir" "$base_sha" "$head_sha" high

    bash "$DISPATCH_BIN" dispatch "$run_evidence_dir"

    verify_out="$(bash "$DISPATCH_BIN" verify "$run_evidence_dir" 2>&1)" || {
      echo "REAL-AC DOGFOOD FAILED [$label]: live verify did not exit 0: $verify_out" >&2
      exit 1
    }
    echo "live verify [$label]: $verify_out"

    bash "$VALIDATE_BIN" "$run_evidence_dir/audit-report.json" >/dev/null 2>&1 \
      || echo "NOTE [$label]: audit-report.json did not pass aid-protocol-validate.sh (expected if status=unverifiable)"

    local session_id got_status got_blocking
    session_id="$(jq -r '.dispatch.codex_session_id // ""' "$run_evidence_dir/c3/c3-dispatch.json")"
    got_status="$(jq -r '.status' "$run_evidence_dir/audit-report.json")"
    got_blocking="$(jq -r '.audit_report.blocking_findings' "$run_evidence_dir/audit-report.json")"
    echo "[$label] observed: status=${got_status} blocking_findings=${got_blocking} (expected status=${expect_status})"

    if [[ "$got_status" != "$expect_status" ]]; then
      echo "REAL-AC DOGFOOD FAILED [$label]: expected status=${expect_status}, got status=${got_status}. Raw findings:" >&2
      jq -c '.findings // []' "$run_evidence_dir/c3/codex-last-message.json" >&2 2>/dev/null || true
      jq -c '.unverifiable_reasons // []' "$run_evidence_dir/c3/codex-last-message.json" >&2 2>/dev/null || true
      exit 1
    fi

    local fixture_dir="$E2E_DIR/evidence/${fixture_dirname}"
    rm -rf "$fixture_dir"
    mkdir -p "$fixture_dir/c3"
    cp "$run_evidence_dir/audit-input-manifest.json" "$fixture_dir/audit-input-manifest.json"
    cp "$run_evidence_dir/audit-report.json"          "$fixture_dir/audit-report.json"
    [[ -f "$run_evidence_dir/audit-report.md" ]] && cp "$run_evidence_dir/audit-report.md" "$fixture_dir/audit-report.md"
    for f in bundle-diff.patch bundle-scope.txt bundle-plan-ac.md bundle-review-profile.json \
             codex-prompt-vars.json codex-prompt.txt codex-events.jsonl codex-last-message.json \
             c3-dispatch.json; do
      [[ -f "$run_evidence_dir/c3/$f" ]] && cp "$run_evidence_dir/c3/$f" "$fixture_dir/c3/$f"
    done

    while IFS= read -r -d '' target; do
      _sanitize_file "$target" "$session_id"
    done < <(find "$fixture_dir" -type f -print0)
    _verify_no_leaks_dir "$fixture_dir" \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: fixture sanitization left a residual leak — refusing to commit." >&2; exit 1; }

    # Recompute codex_brief_hash + raw-byte hashes over the sanitized bytes,
    # then regenerate audit-report.json via the bridge's own trusted
    # _process_response so the fixture is a faithful transform of the
    # SANITIZED raw response (same reasoning as c3-dogfood.sh; uses the
    # PLACEHOLDER session id, never the real one, in the regeneration call).
    # shellcheck disable=SC1090
    source "$DISPATCH_BIN"
    recompute_brief_hash_real_ac() {
      local base head level paths=() p full h sz cbf_json="[]"
      base="$(jq -r '.audit_input_manifest.base_sha' "$fixture_dir/audit-input-manifest.json")"
      head="$(jq -r '.audit_input_manifest.head_sha' "$fixture_dir/audit-input-manifest.json")"
      level="$(jq -r '.audit_input_manifest.required_independence_level' "$fixture_dir/audit-input-manifest.json")"
      mapfile -t paths < <(jq -r '.audit_input_manifest.codex_brief_files[].path' "$fixture_dir/audit-input-manifest.json" | LC_ALL=C sort)
      for p in "${paths[@]}"; do
        full="$fixture_dir/$p"
        [[ -f "$full" ]] || return 1
        h="$(sha256sum "$full" | awk '{print $1}')"
        sz="$(wc -c < "$full" | tr -d '[:space:]')"; [[ -n "$sz" ]] || sz=0
        cbf_json="$(jq -c --arg p "$p" --arg s "sha256:$h" --argjson z "$sz" '. + [{path:$p,sha256:$s,size:$z}]' <<<"$cbf_json")" || return 1
      done
      local canonical newhash tmp="$fixture_dir/audit-input-manifest.json.tmp.$$"
      canonical="$(jq -S -c -n --arg b "$base" --arg h "$head" --argjson f "$cbf_json" --arg l "$level" \
        '{base_sha:$b,head_sha:$h,codex_brief_files:$f,required_independence_level:$l}')" || return 1
      newhash="sha256:$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
      jq --argjson f "$cbf_json" --arg h "$newhash" \
        '.audit_input_manifest.codex_brief_files=$f | .audit_input_manifest.codex_brief_hash=$h' \
        "$fixture_dir/audit-input-manifest.json" > "$tmp" || { rm -f "$tmp"; return 1; }
      mv "$tmp" "$fixture_dir/audit-input-manifest.json" || { rm -f "$tmp"; return 1; }
      printf '%s' "$newhash"
    }
    new_brief_hash="$(recompute_brief_hash_real_ac)" \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: could not recompute codex_brief_hash" >&2; exit 1; }
    new_stdout_sha="sha256:$(sha256sum "$fixture_dir/c3/codex-events.jsonl" | awk '{print $1}')"
    new_raw_sha="sha256:$(sha256sum "$fixture_dir/c3/codex-last-message.json" | awk '{print $1}')"
    tmp_dj="$fixture_dir/c3/c3-dispatch.json.tmp.$$"
    jq --arg s "$new_stdout_sha" --arg r "$new_raw_sha" --arg bh "$new_brief_hash" \
      '.dispatch.stdout_sha256=$s | .dispatch.raw_response_sha256=$r | .subject.codex_brief_hash=$bh' \
      "$fixture_dir/c3/c3-dispatch.json" > "$tmp_dj" && mv "$tmp_dj" "$fixture_dir/c3/c3-dispatch.json"

    dispatch_outcome_orig="$(jq -r '.dispatch.outcome // "dispatched"' "$fixture_dir/c3/c3-dispatch.json")"
    indep_level="$(jq -r '.independence.achieved_independence_level' "$fixture_dir/c3/c3-dispatch.json")"
    fixture_head="$(jq -r '.audit_input_manifest.head_sha' "$fixture_dir/audit-input-manifest.json")"
    set +e
    _process_response "$fixture_dir" "$fixture_dir/audit-input-manifest.json" "0" "true" \
      "$dispatch_outcome_orig" "$indep_level" "$PLACEHOLDER_SESSION_ID" "$fixture_head"
    process_response_rc=$?
    set -e
    [[ -f "$fixture_dir/audit-report.json" ]] \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: _process_response did not produce audit-report.json" >&2; exit 1; }
    _verify_no_leaks_dir "$fixture_dir" \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: post-regeneration leak check failed" >&2; exit 1; }

    fixture_status="$(jq -r '.status' "$fixture_dir/audit-report.json")"
    [[ "$fixture_status" == "$expect_status" ]] \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: regenerated fixture status=${fixture_status}, expected ${expect_status}" >&2; exit 1; }

    fx_verify_out="$(bash "$DISPATCH_BIN" verify --reference "$fixture_dir" 2>&1)" \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: verify --reference on fixture did not exit 0: $fx_verify_out" >&2; exit 1; }
    echo "fixture verify --reference [$label]: $fx_verify_out"

    # Negative control (script-internal, never committed).
    corrupt_dir="$(mktemp -d "${TMPDIR:-/tmp}/c3-dogfood-real-ac-corrupt.XXXXXX")"
    cp -r "$fixture_dir"/. "$corrupt_dir/"
    printf 'corrupted-garbage-not-jsonl\n' >> "$corrupt_dir/c3/codex-events.jsonl"
    set +e
    corrupt_out="$(bash "$DISPATCH_BIN" verify --reference "$corrupt_dir" 2>&1)"
    corrupt_rc=$?
    set -e
    rm -rf "$corrupt_dir"
    [[ "$corrupt_rc" -eq 2 ]] \
      || { echo "REAL-AC DOGFOOD FAILED [$label]: negative control did not exit 2 (rc=$corrupt_rc): $corrupt_out" >&2; exit 1; }
    echo "negative control [$label]: verify --reference correctly exited 2"

    attestation_md="$E2E_DIR/evidence/${fixture_dirname}-live-attestation.md"
    session_prefix="${session_id:0:8}..."
    codex_version="$(jq -r '.dispatch.codex_version // ""' "$run_evidence_dir/c3/c3-dispatch.json")"
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cat > "$attestation_md" <<EOF2
# C3 Dogfood (real AC) — Live Attestation [$label] (P065 IMP-245 follow-up)

Committed PROVENANCE PROOF that the C3 bridge, given a REAL (tiny) acceptance
criteria document via \`AID_PLAN_AC_FILE\`, reached the determinate verdict
\`${expect_status}\` from a real live Codex CLI dispatch — not \`unverifiable\`.
Raw evidence is not committed; \`${fixture_dirname}/\` is a separate, sanitized,
re-hashed regression fixture (proves \`verify\`'s logic, not external provenance).

| Field | Value |
|---|---|
| codex_version | \`${codex_version}\` |
| codex_session_id (prefix only) | \`${session_prefix}\` |
| achieved_independence_level | \`${indep_level}\` |
| expected status | \`${expect_status}\` |
| observed status | \`${got_status}\` |
| run_at (UTC) | \`${now_iso}\` |
| live_verify | passed |

live_verify: passed
EOF2
    echo "wrote $attestation_md"

    # FSM acceptance demo: with enforcement:blocking pinned, a seeded
    # done-advance over this determinate-verdict fixture must behave
    # correctly for that verdict (pass → advances; findings/blocking → blocks).
    demo_worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/c3-dogfood-real-ac-wt.XXXXXX")"
    rmdir "$demo_worktree_dir"
    git -C "$REPO_ROOT" worktree add -q --detach "$demo_worktree_dir" "$head_sha"
    _seed_and_run_done_advance "$demo_worktree_dir" "$fixture_dir"
    fsm_rc="$LAST_FSM_RC"
    fsm_out="$LAST_FSM_OUT"
    git -C "$REPO_ROOT" worktree remove --force "$demo_worktree_dir" >/dev/null 2>&1 || true
    rm -rf "$demo_worktree_dir" 2>/dev/null || true

    if [[ "$expect_status" == "pass" ]]; then
      [[ "$fsm_rc" -eq 0 ]] \
        || { echo "REAL-AC DOGFOOD FAILED [$label]: expected done-advance to ADVANCE on a genuine pass, but rc=$fsm_rc: $fsm_out" >&2; exit 1; }
      echo "FSM demo [$label]: seeded done-advance ADVANCED on a genuine, real, determinate pass — enforcement:blocking."
    else
      [[ "$fsm_rc" -ne 0 ]] \
        || { echo "REAL-AC DOGFOOD FAILED [$label]: expected done-advance to BLOCK on a genuine blocking finding, but it advanced (rc=0)" >&2; exit 1; }
      echo "FSM demo [$label]: seeded done-advance correctly BLOCKED on a genuine, real, determinate blocking finding — enforcement:blocking."
    fi

    echo "== c3-dogfood-real-ac [$label]: PASSED (status=${got_status} as expected) =="
  ) || case_rc=$?

  trap - EXIT
  _case_cleanup
  return "$case_rc"
}

PASS_FILE_CONTENT='#!/usr/bin/env bash
# Echoes the given integer plus one.
increment_by_one() {
  echo $(( $1 + 1 ))
}
'
PASS_AC_CONTENT='## Acceptance Criteria — diagnostic increment function

- File `scripts/e2e-ac-demo/increment.sh` must define a shell function
  `increment_by_one` that takes one integer argument and echoes that integer
  plus exactly 1.
- The function must have a one-line comment directly above its definition
  explaining what it does.
- No other file may be modified.
'

FAIL_FILE_CONTENT='#!/usr/bin/env bash
increment_by_one() {
  echo $(( $1 + 2 ))
}
'
FAIL_AC_CONTENT='## Acceptance Criteria — diagnostic increment function

- File `scripts/e2e-ac-demo/increment.sh` must define a shell function
  `increment_by_one` that takes one integer argument and echoes that integer
  plus exactly 1.
- The function must have a one-line comment directly above its definition
  explaining what it does.
- No other file may be modified.
'

overall_rc=0
_run_case "pass" "pass" "$PASS_FILE_CONTENT" "$PASS_AC_CONTENT" "c3-dogfood-fixture-real-ac-pass" || overall_rc=1
(cd "$REPO_ROOT" && git checkout -q "$ORIG_BRANCH") 2>/dev/null || true
_run_case "fail" "fail" "$FAIL_FILE_CONTENT" "$FAIL_AC_CONTENT" "c3-dogfood-fixture-real-ac-fail" || overall_rc=1
(cd "$REPO_ROOT" && git checkout -q "$ORIG_BRANCH") 2>/dev/null || true

if [[ "$overall_rc" -eq 0 ]]; then
  echo "== c3-dogfood-real-ac: BOTH cases PASSED (pass→pass, fail→fail, both determinate) =="
else
  echo "== c3-dogfood-real-ac: FAILED — see above =="
fi
exit "$overall_rc"
