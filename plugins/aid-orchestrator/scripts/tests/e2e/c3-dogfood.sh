#!/usr/bin/env bash
# =============================================================================
# c3-dogfood.sh — P065 Step 13 (EPIC E-065-4_7) real-Codex dogfood driver.
#
# Runs the COMPLETE C3 cross-provider dispatch bridge (aid-c3-dispatch.sh
# build-manifest → dispatch → verify) ONCE against the REAL Codex CLI, then
# produces two committed proofs:
#
#   1. evidence/c3-dogfood-live-attestation.md — a sanitized ATTESTATION that a
#      real live-verified run happened (provenance proof). The raw evidence
#      itself is never committed (it may carry local paths/session detail).
#   2. evidence/c3-dogfood-fixture/ — a sanitized, internally re-hashed
#      REGRESSION FIXTURE of the same run, for `aid-c3-dispatch.sh verify
#      --reference` to exercise going forward. This fixture proves the bridge's
#      *verify logic* is self-consistent — it is explicitly NOT a substitute
#      for the attestation's external-provenance claim (sanitizing changes raw
#      bytes, hence hashes, hence it cannot bind to the live run's own hashes).
#
# It also runs two script-internal (never committed) assertions:
#   - a negative control: a corrupted copy of the fixture's raw event stream
#     must make `verify --reference` exit 2.
#   - an FSM acceptance demo: with `enforcement: blocking` pinned, a seeded
#     `done-advance` over the REAL fixture must reach whichever outcome its
#     own honest content implies — BLOCK if the live run's audit-report.json
#     came back status:"unverifiable" (Codex declined a firm verdict), or
#     ADVANCE if it is a genuine pass/fail. A separate, fully-controlled demo
#     (7b) independently proves the "advances on clean content" half against
#     an in-test fake codex stub, regardless of what the one real live Codex
#     call happened to answer content-wise. The 7a demo runs in an isolated
#     `git worktree` checked out at the EXACT commit the live run reviewed
#     (still a real, resolvable commit object at this point in the script,
#     before the throwaway branch is deleted) — this is required because the
#     bridge's `verify` (live mode, no --reference) and the FSM's own
#     dispatch-provenance hook both bind `reviewed_head` to the CURRENT git
#     HEAD, and a commit hash cannot be forged in an unrelated repo.
#
# A throwaway branch + trivial new file give `build-manifest` a real,
# resolvable base/head commit pair for Codex to review. The branch (and its
# commit) is deleted on exit — this never touches task/E-065-4_7/main history.
#
# Usage: c3-dogfood.sh
# Exit codes:
#   0  dogfood complete (or genuinely skipped — see Error Handling below)
#   1  dogfood failed, or codex unavailable with no prior committed proof
#
# Requirements: bash 4+, jq, git, sha256sum, codex CLI (>= 0.143.0) authenticated.
#
# Error Handling:
#   - Codex auth unavailable AND the committed attestation + fixture already
#     exist from a prior real run → print "DOGFOOD SKIPPED: codex auth
#     unavailable" and exit 0. A skip NEVER substitutes for the first real
#     proof — if either committed artifact is missing, this exits non-zero.
#   - Any other failure (dispatch didn't reach dispatched/cross_provider, live
#     verify failed, working tree changed, validator rejected the report,
#     negative control didn't trip, FSM demo didn't advance) exits non-zero
#     with a diagnostic on stderr.
#
# **Last Updated:** 2026-07-15
# =============================================================================
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$E2E_DIR/../../.." && pwd)"           # plugins/aid-orchestrator
DISPATCH_BIN="$PLUGIN_DIR/scripts/lib/aid-c3-dispatch.sh"
INDEP_BIN="$PLUGIN_DIR/scripts/lib/aid-audit-independence.sh"
FSM_BIN="$PLUGIN_DIR/scripts/aid-fsm.sh"
VALIDATE_BIN="$PLUGIN_DIR/scripts/aid-protocol-validate.sh"

FIXTURE_DIR="$E2E_DIR/evidence/c3-dogfood-fixture"
ATTESTATION_MD="$E2E_DIR/evidence/c3-dogfood-live-attestation.md"

for f in "$DISPATCH_BIN" "$INDEP_BIN" "$FSM_BIN" "$VALIDATE_BIN"; do
  [[ -f "$f" ]] || { echo "ERROR: required script missing: $f" >&2; exit 1; }
done
for c in jq git sha256sum; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c required in PATH" >&2; exit 1; }
done

REPO_ROOT="$(cd "$E2E_DIR" && git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "ERROR: $E2E_DIR is not inside a git repository" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Availability gate (Error Handling, plan §Step 13): re-uses the bridge's OWN
# cross_provider precheck (command + sanity + auth + output-schema) — never a
# separate ad-hoc probe. A skip is legitimate ONLY when a prior real proof is
# already committed; otherwise the plan is not complete and this must fail.
# ---------------------------------------------------------------------------
codex_available=1
if ! command -v codex >/dev/null 2>&1; then
  codex_available=0
elif ! bash "$INDEP_BIN" detect --required cross_provider >/dev/null 2>&1; then
  codex_available=0
fi

if [[ "$codex_available" -eq 0 ]]; then
  if [[ -f "$ATTESTATION_MD" && -d "$FIXTURE_DIR" ]]; then
    echo "DOGFOOD SKIPPED: codex auth unavailable"
    exit 0
  else
    echo "DOGFOOD FAILED: codex auth unavailable AND no prior committed proof exists (attestation/fixture missing)." >&2
    echo "The plan is not complete until at least one real dogfood run has produced committed evidence — a skip never substitutes for it." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Preconditions: clean working tree, on a real branch (not detached).
# ---------------------------------------------------------------------------
[[ -z "$(cd "$REPO_ROOT" && git status --porcelain)" ]] \
  || { echo "ERROR: working tree is not clean — refusing to start (commit/stash first)." >&2; exit 1; }

ORIG_BRANCH="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD)"
[[ "$ORIG_BRANCH" != "HEAD" ]] \
  || { echo "ERROR: repo is in detached HEAD state — refusing to start." >&2; exit 1; }

THROWAWAY_BRANCH="c3-dogfood-throwaway-$$"
MARKER_FILE="$E2E_DIR/c3-dogfood-throwaway-marker-$$.txt"
DOGFOOD_EVIDENCE_DIR="$REPO_ROOT/.aid-o/work/evidence/E-c3-dogfood/R-$$"
DEMO_WORKTREE_DIR=""
BRANCH_CREATED=0

# ---------------------------------------------------------------------------
# cleanup — runs on EVERY exit (success or failure). Never leaves the throwaway
# branch/commit, the demo worktree, or the scratch evidence dir behind, and
# always returns to the branch this script started on.
# ---------------------------------------------------------------------------
cleanup() {
  local ec=$?
  set +e
  if [[ -n "$DEMO_WORKTREE_DIR" && -d "$DEMO_WORKTREE_DIR" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$DEMO_WORKTREE_DIR" >/dev/null 2>&1
    rm -rf "$DEMO_WORKTREE_DIR" 2>/dev/null
  fi
  local cur_branch
  cur_branch="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ -n "$ORIG_BRANCH" && "$cur_branch" != "$ORIG_BRANCH" ]]; then
    (cd "$REPO_ROOT" && git checkout -q "$ORIG_BRANCH") 2>/dev/null
  fi
  if [[ "$BRANCH_CREATED" -eq 1 ]]; then
    (cd "$REPO_ROOT" && git branch -D "$THROWAWAY_BRANCH") >/dev/null 2>&1
  fi
  rm -f "$MARKER_FILE" 2>/dev/null
  [[ -n "$DOGFOOD_EVIDENCE_DIR" ]] && rm -rf "$DOGFOOD_EVIDENCE_DIR" 2>/dev/null
  exit "$ec"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: throwaway branch + trivial new file → a real, resolvable base/head
# commit pair for build-manifest to diff and Codex to review.
# ---------------------------------------------------------------------------
(cd "$REPO_ROOT" && git checkout -q -b "$THROWAWAY_BRANCH")
BRANCH_CREATED=1
BASE_SHA="$(cd "$REPO_ROOT" && git rev-parse HEAD)"

printf '# C3 dogfood throwaway marker (P065 Step 13).\n# Created %s — this file and its commit are deleted with the branch\n# before this script exits; never merged into any real branch.\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER_FILE"
(cd "$REPO_ROOT" && git add "$MARKER_FILE" \
  && git commit -q -m "chore(c3-dogfood): throwaway marker for P065 Step 13 real dispatch (never merged)")
HEAD_SHA="$(cd "$REPO_ROOT" && git rev-parse HEAD)"

echo "== c3-dogfood: base=${BASE_SHA:0:12} head=${HEAD_SHA:0:12} on throwaway branch =="

# ---------------------------------------------------------------------------
# Step 2: build-manifest → dispatch (REAL codex) → verify (live).
# ---------------------------------------------------------------------------
mkdir -p "$DOGFOOD_EVIDENCE_DIR"
(cd "$REPO_ROOT" && bash "$DISPATCH_BIN" build-manifest "$DOGFOOD_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high) \
  || { echo "DOGFOOD FAILED: build-manifest did not succeed" >&2; exit 1; }

set +e
(cd "$REPO_ROOT" && bash "$DISPATCH_BIN" dispatch "$DOGFOOD_EVIDENCE_DIR")
dispatch_rc=$?
set -e
[[ "$dispatch_rc" -eq 0 ]] \
  || { echo "DOGFOOD FAILED: dispatch exited $dispatch_rc (real Codex run did not reach dispatched/cross_provider)" >&2; exit 1; }

C3_DISPATCH_JSON="$DOGFOOD_EVIDENCE_DIR/c3/c3-dispatch.json"
[[ -f "$C3_DISPATCH_JSON" ]] || { echo "DOGFOOD FAILED: c3-dispatch.json missing after a 0-exit dispatch" >&2; exit 1; }

codex_version="$(jq -r '.executor.codex_version // ""' "$C3_DISPATCH_JSON" 2>/dev/null)" || codex_version=""
[[ "$codex_version" == codex-cli* ]] \
  || { echo "DOGFOOD FAILED: codex_version does not start with 'codex-cli' (got: '${codex_version}')" >&2; exit 1; }

indep_level="$(jq -r '.independence.achieved_independence_level // ""' "$C3_DISPATCH_JSON" 2>/dev/null)" || indep_level=""
[[ "$indep_level" == "cross_provider" ]] \
  || { echo "DOGFOOD FAILED: achieved_independence_level != cross_provider (got: '${indep_level}')" >&2; exit 1; }

session_id="$(jq -r '.dispatch.codex_session_id // ""' "$C3_DISPATCH_JSON" 2>/dev/null)" || session_id=""
[[ -n "$session_id" ]] || { echo "DOGFOOD FAILED: dispatch.codex_session_id is empty" >&2; exit 1; }

set +e
verify_out="$(cd "$REPO_ROOT" && bash "$DISPATCH_BIN" verify "$DOGFOOD_EVIDENCE_DIR" 2>&1)"
verify_rc=$?
set -e
[[ "$verify_rc" -eq 0 ]] \
  || { echo "DOGFOOD FAILED: live 'verify' did not exit 0 (rc=$verify_rc): $verify_out" >&2; exit 1; }
echo "live verify: $verify_out"

(cd "$REPO_ROOT" && bash "$VALIDATE_BIN" "$DOGFOOD_EVIDENCE_DIR/audit-report.json") >/dev/null \
  || { echo "DOGFOOD FAILED: audit-report.json failed aid-protocol-validate.sh" >&2; exit 1; }
echo "audit-report.json: validator-clean"

# ---------------------------------------------------------------------------
# Step 3: read-only confirmation — the working tree must be unchanged (proves
# --sandbox read-only actually blocked any write Codex might have attempted).
# ---------------------------------------------------------------------------
tree_status_after="$(cd "$REPO_ROOT" && git status --porcelain)"
[[ -z "$tree_status_after" ]] \
  || { echo "DOGFOOD FAILED: working tree changed during/after dispatch (--sandbox read-only may have failed):" >&2; echo "$tree_status_after" >&2; exit 1; }
echo "working tree: unchanged after the real run"

# ---------------------------------------------------------------------------
# Step 4: write the sanitized, committed ATTESTATION (provenance proof). The
# raw evidence itself is never committed — only this summary.
# ---------------------------------------------------------------------------
session_prefix="${session_id:0:8}..."
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$(dirname "$ATTESTATION_MD")"
cat > "$ATTESTATION_MD" <<EOF
# C3 Dogfood — Live Attestation (P065 Step 13)

This file is the committed PROVENANCE PROOF that the C3 cross-provider dispatch
bridge (\`aid-c3-dispatch.sh\`) was run once, for real, against the real Codex
CLI, and that \`aid-c3-dispatch.sh verify\` (live mode) accepted the result at
run time. The raw evidence directory itself is deliberately NOT committed (it
may contain local filesystem paths or session detail) — this attestation is
the sanitized record of that run.

The regression fixture committed alongside this file
(\`c3-dogfood-fixture/\`) is a SEPARATE, sanitized, re-hashed copy of the same
run's evidence. It proves the bridge's \`verify\` logic is internally
self-consistent going forward — it is NOT itself external provenance (sanitizing
changes raw bytes, and therefore hashes). This file is the provenance claim;
the fixture is the regression check.

| Field | Value |
|---|---|
| codex_version | \`${codex_version}\` |
| codex_session_id (prefix only) | \`${session_prefix}\` |
| achieved_independence_level | \`${indep_level}\` |
| run_at (UTC) | \`${now_iso}\` |
| live_verify | passed |
| audit-report.json validator | passed |
| working tree after run | unchanged |

live_verify: passed
EOF
echo "wrote $ATTESTATION_MD"

# ---------------------------------------------------------------------------
# Step 5: build the committed regression fixture — sanitize a copy of the real
# evidence, then recompute every hash the sanitization could have changed by
# re-running the bridge's OWN trusted functions (sourced from aid-c3-dispatch.sh)
# rather than hand-patching JSON, so the fixture is guaranteed internally
# consistent with how the bridge actually works.
# ---------------------------------------------------------------------------
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR/c3"
cp "$DOGFOOD_EVIDENCE_DIR/audit-input-manifest.json" "$FIXTURE_DIR/audit-input-manifest.json"
cp "$DOGFOOD_EVIDENCE_DIR/audit-report.json"          "$FIXTURE_DIR/audit-report.json"
cp "$DOGFOOD_EVIDENCE_DIR/audit-report.md"            "$FIXTURE_DIR/audit-report.md"
for f in bundle-diff.patch bundle-scope.txt bundle-plan-ac.md bundle-review-profile.json \
         codex-prompt-vars.json codex-prompt.txt codex-events.jsonl codex-last-message.json \
         c3-dispatch.json; do
  [[ -f "$DOGFOOD_EVIDENCE_DIR/c3/$f" ]] && cp "$DOGFOOD_EVIDENCE_DIR/c3/$f" "$FIXTURE_DIR/c3/$f"
done

# --- sanitizer (same signature families as discover-codex-stream.sh's) ------
_escape_ere_pattern() { sed -e 's/[.[\*^$()+?{}|#\\]/\\&/g'; }

# SECURITY REGRESSION FIX (E-065-4_7, CP3 finding, MEDIUM): the real Codex
# session UUID (dispatch.codex_session_id / audit_report.process_id /
# codex-events.jsonl thread_id — all the SAME value) was being committed
# VERBATIM into the fixture, unlike the attestation which deliberately
# truncates it to a prefix. Replace it with a FIXED, syntactically-valid
# placeholder UUID everywhere it appears, so future dogfood runs never leak a
# real session id into this public marketplace repo.
PLACEHOLDER_SESSION_ID="00000000-0000-7000-8000-000000000000"

_sanitize_file() {
  local f="$1" user home_esc repo_esc user_esc session_esc tmp
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
  # Real Codex session UUID (dispatch.codex_session_id / audit_report.process_id
  # / codex-events.jsonl thread_id — all the SAME value): replace with the
  # FIXED placeholder before the generic token patterns run, so it never lands
  # verbatim in a committed fixture. Guarded on non-empty — an empty pattern
  # would otherwise match (and rewrite) every position in the file.
  if [[ -n "${session_id:-}" ]]; then
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

while IFS= read -r -d '' target; do
  _sanitize_file "$target"
done < <(find "$FIXTURE_DIR" -type f -print0)

_verify_no_leaks_dir "$FIXTURE_DIR" \
  || { echo "DOGFOOD FAILED: fixture sanitization left a residual leak signature — refusing to commit it." >&2; exit 1; }
echo "fixture: sanitized and leak-checked"

# --- recompute codex_brief_hash (only actually changes if a brief file's
#     bytes were touched by sanitization; recomputing is always safe/idempotent) -
recompute_brief_hash() {
  local base head level paths=() p full h sz cbf_json="[]"
  base="$(jq -r '.audit_input_manifest.base_sha' "$FIXTURE_DIR/audit-input-manifest.json")"
  head="$(jq -r '.audit_input_manifest.head_sha' "$FIXTURE_DIR/audit-input-manifest.json")"
  level="$(jq -r '.audit_input_manifest.required_independence_level' "$FIXTURE_DIR/audit-input-manifest.json")"
  mapfile -t paths < <(jq -r '.audit_input_manifest.codex_brief_files[].path' "$FIXTURE_DIR/audit-input-manifest.json" | LC_ALL=C sort)
  for p in "${paths[@]}"; do
    full="$FIXTURE_DIR/$p"
    [[ -f "$full" ]] || { echo "recompute_brief_hash: missing brief file $p" >&2; return 1; }
    h="$(sha256sum "$full" | awk '{print $1}')"
    sz="$(wc -c < "$full" | tr -d '[:space:]')"; [[ -n "$sz" ]] || sz=0
    cbf_json="$(jq -c --arg p "$p" --arg s "sha256:$h" --argjson z "$sz" '. + [{path:$p,sha256:$s,size:$z}]' <<<"$cbf_json")" || return 1
  done
  local canonical newhash tmp="$FIXTURE_DIR/audit-input-manifest.json.tmp.$$"
  canonical="$(jq -S -c -n --arg b "$base" --arg h "$head" --argjson f "$cbf_json" --arg l "$level" \
    '{base_sha:$b,head_sha:$h,codex_brief_files:$f,required_independence_level:$l}')" || return 1
  newhash="sha256:$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
  jq --argjson f "$cbf_json" --arg h "$newhash" \
    '.audit_input_manifest.codex_brief_files=$f | .audit_input_manifest.codex_brief_hash=$h' \
    "$FIXTURE_DIR/audit-input-manifest.json" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$FIXTURE_DIR/audit-input-manifest.json" || { rm -f "$tmp"; return 1; }
  printf '%s' "$newhash"
}
new_brief_hash="$(recompute_brief_hash)" \
  || { echo "DOGFOOD FAILED: could not recompute the fixture's codex_brief_hash" >&2; exit 1; }

# --- recompute the two raw-byte hashes (always recomputed — idempotent even
#     when sanitization was a no-op on these files) and propagate the brief
#     hash into c3-dispatch.json's own subject/dispatch fields ------------------
new_stdout_sha="sha256:$(sha256sum "$FIXTURE_DIR/c3/codex-events.jsonl" | awk '{print $1}')"
new_raw_sha="sha256:$(sha256sum "$FIXTURE_DIR/c3/codex-last-message.json" | awk '{print $1}')"
tmp_dj="$FIXTURE_DIR/c3/c3-dispatch.json.tmp.$$"
jq --arg s "$new_stdout_sha" --arg r "$new_raw_sha" --arg bh "$new_brief_hash" \
  '.dispatch.stdout_sha256=$s | .dispatch.raw_response_sha256=$r | .subject.codex_brief_hash=$bh' \
  "$FIXTURE_DIR/c3/c3-dispatch.json" > "$tmp_dj" && mv "$tmp_dj" "$FIXTURE_DIR/c3/c3-dispatch.json"

# --- regenerate audit-report.json (+ .md) FROM the sanitized raw response, by
#     sourcing aid-c3-dispatch.sh (function-only mode — its own guard skips
#     `main` since $0 here is this script, not aid-c3-dispatch.sh) and calling
#     its trusted _process_response — the SAME dispatch→report pipeline
#     cmd_dispatch itself uses (validate → hash/head-bind checks → the honest
#     "review_status: unverifiable" branch → normalize+_write_report OR
#     _write_unverifiable). Calling _write_report directly here would SKIP that
#     branch and could fabricate a "status: pass" envelope over a raw response
#     Codex itself marked unverifiable — _process_response is what guarantees
#     the fixture is a byte-faithful, HONEST transform of the sanitized raw
#     response, never a hand-patched approximation of one.
dispatch_outcome_orig="$(jq -r '.dispatch.outcome // "dispatched"' "$FIXTURE_DIR/c3/c3-dispatch.json" 2>/dev/null)" || dispatch_outcome_orig="dispatched"
# shellcheck disable=SC1090
source "$DISPATCH_BIN"
set +e
_process_response "$FIXTURE_DIR" "$FIXTURE_DIR/audit-input-manifest.json" "0" "true" \
  "$dispatch_outcome_orig" "$indep_level" "$session_id" "$HEAD_SHA"
process_response_rc=$?
set -e
# rc 0 = validator-clean pass/fail; rc 2 = an honest status:"unverifiable" write
# (e.g. review_unverifiable — Codex itself declined to give a firm verdict).
# Both are legitimate, FAITHFUL outcomes here; only a missing report is fatal.
[[ -f "$FIXTURE_DIR/audit-report.json" ]] \
  || { echo "DOGFOOD FAILED: _process_response did not produce audit-report.json (rc=$process_response_rc)" >&2; exit 1; }
fixture_status="$(jq -r '.status // ""' "$FIXTURE_DIR/audit-report.json")"
fixture_review_status="$(jq -r '.audit_report.review_status // ""' "$FIXTURE_DIR/audit-report.json")"
echo "fixture audit-report.json: status=${fixture_status} review_status=${fixture_review_status}"

# Re-check leaks once more post-regeneration (regeneration re-derives text from
# the already-sanitized raw response, but this is a cheap, deterministic
# backstop rather than an assumption).
_verify_no_leaks_dir "$FIXTURE_DIR" \
  || { echo "DOGFOOD FAILED: fixture leaked a signature after report regeneration." >&2; exit 1; }

# --- positive control: the fixture must now pass verify --reference ----------
set +e
ref_out="$(cd "$REPO_ROOT" && bash "$DISPATCH_BIN" verify --reference "$FIXTURE_DIR" 2>&1)"
ref_rc=$?
set -e
[[ "$ref_rc" -eq 0 ]] \
  || { echo "DOGFOOD FAILED: 'verify --reference' on the freshly-built fixture did not exit 0 (rc=$ref_rc): $ref_out" >&2; exit 1; }
echo "fixture verify --reference: $ref_out"

# ---------------------------------------------------------------------------
# Step 6: negative control — corrupt a SCRATCH copy's raw event stream and
# assert verify --reference exits 2. The corrupted copy is NEVER committed.
# ---------------------------------------------------------------------------
neg_dir="$(mktemp -d "${TMPDIR:-/tmp}/c3-dogfood-negctl.XXXXXX")"
cp -r "$FIXTURE_DIR" "$neg_dir/fixture"
printf 'CORRUPTED-BY-NEGATIVE-CONTROL' >> "$neg_dir/fixture/c3/codex-events.jsonl"
set +e
neg_out="$(cd "$REPO_ROOT" && bash "$DISPATCH_BIN" verify --reference "$neg_dir/fixture" 2>&1)"
neg_rc=$?
set -e
rm -rf "$neg_dir"
[[ "$neg_rc" -eq 2 ]] \
  || { echo "DOGFOOD FAILED: verify --reference on the corrupted control did not exit 2 (got $neg_rc): $neg_out" >&2; exit 1; }
echo "negative control (corrupted codex-events.jsonl): verify --reference correctly exited 2"

# ---------------------------------------------------------------------------
# Step 7: FSM acceptance demo. All script-internal; nothing here is committed.
#
# _seed_and_run_done_advance <worktree_or_repo_dir> <evidence_src_dir>
#   Seeds the standard DONE/review scaffold (fsm-state.yaml, gates_report.json,
#   audit-log.jsonl, review-profile.json:high, curator-report.json/.md with a
#   matching audit_report_ref, c3-audit-policy pinned to enforcement:blocking)
#   under <worktree_or_repo_dir>, copies <evidence_src_dir>'s
#   audit-input-manifest.json / audit-report.json(.md) / c3/* into it, and runs
#   `aid-fsm.sh done-advance review release`. Sets LAST_FSM_RC / LAST_FSM_OUT.
# ---------------------------------------------------------------------------
_seed_and_run_done_advance() {
  local root="$1" src="$2"
  local evidence="$root/.aid-o/work/evidence/E-c3-dogfood-demo/R-demo"
  mkdir -p "$evidence/c3" "$evidence/gates" \
           "$root/.aid-o/tasks" "$root/.aid-o/work" "$root/.aid-o/config"

  cp "$src/audit-input-manifest.json" "$evidence/audit-input-manifest.json"
  cp "$src/audit-report.json"          "$evidence/audit-report.json"
  cp "$src/audit-report.md"            "$evidence/audit-report.md"
  cp "$src"/c3/*                       "$evidence/c3/"

  local state_file="$evidence/fsm-state.yaml"
  cat > "$state_file" <<YAML
epic_id: E-c3-dogfood-demo
run_id: R-demo
branch: task/E-c3-dogfood-demo/main
state: DONE
done_phase: review
created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
total_steps: 1
current_step: 1
pm_decision: merge
YAML

  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@c3-dogfood","_generated_at":"%s","_command_log":[]}\n' \
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

# --- 7a: the REAL fixture, in an isolated worktree pinned at the exact commit
#     the live run reviewed (a real, resolvable object right now — the
#     throwaway branch/commit is only deleted at script exit) so the bridge's
#     live-mode HEAD-freshness checks are satisfiable without disturbing this
#     script's own checkout. ------------------------------------------------
DEMO_WORKTREE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/c3-dogfood-demo-wt.XXXXXX")"
rmdir "$DEMO_WORKTREE_DIR"   # git worktree add requires the target not exist
(cd "$REPO_ROOT" && git worktree add -q --detach "$DEMO_WORKTREE_DIR" "$HEAD_SHA")

_seed_and_run_done_advance "$DEMO_WORKTREE_DIR" "$FIXTURE_DIR"
fixture_fsm_rc="$LAST_FSM_RC"
fixture_fsm_out="$LAST_FSM_OUT"

git -C "$REPO_ROOT" worktree remove --force "$DEMO_WORKTREE_DIR" >/dev/null 2>&1 || true
rm -rf "$DEMO_WORKTREE_DIR" 2>/dev/null || true
DEMO_WORKTREE_DIR=""

# The REAL Codex response was HONESTLY "review_status: unverifiable" (it
# declined a firm verdict — see attestation/finding notes: the bridge's
# allowed_recheck_commands is unconditionally empty by current design, so
# Codex cannot independently re-check gate/manifest evidence and correctly
# refuses to guess a pass). Under enforcement:blocking that MUST block —
# demonstrate whichever behavior the honest content actually implies, rather
# than asserting a fixed expectation that could paper over either a real
# regression or a fabricated fixture.
if [[ "$fixture_status" == "unverifiable" ]]; then
  [[ "$fixture_fsm_rc" -ne 0 ]] \
    || { echo "DOGFOOD FAILED: the honest review_status=unverifiable fixture did NOT block done-advance under enforcement:blocking (rc=0) — the content guardrail is not firing." >&2; exit 1; }
  echo "FSM guardrail check: seeded done-advance over the REAL (review_status=unverifiable) fixture correctly BLOCKED under enforcement:blocking — this is the guardrail working as designed, not a bug."
else
  [[ "$fixture_fsm_rc" -eq 0 ]] \
    || { echo "DOGFOOD FAILED: seeded done-advance over the fixture did not advance (rc=$fixture_fsm_rc):" >&2; echo "$fixture_fsm_out" >&2; exit 1; }
  echo "FSM acceptance demo: seeded done-advance over the fixture advanced (enforcement:blocking)."
fi

# --- 7b: supplementary controlled demo — a SEPARATE, fully-isolated scratch
#     repo drives the SAME real build-manifest -> dispatch -> verify pipeline
#     against an in-test fake `codex` stub that emits a genuine,
#     schema-consistent, NON-blocking finding (the exact pattern the plan's own
#     bats suite uses for this — test-c3-audit.bats's _drive_clean_dispatch).
#     This proves the DISPATCH-PROVENANCE mechanism this EPIC built (Steps 8-9)
#     allows done-advance to ADVANCE under enforcement:blocking whenever the
#     content is genuinely clean — required regardless of what the one real
#     live Codex call above happened to answer content-wise. Nothing here is
#     committed; it exists only to prove the "advances" half of AC3 against a
#     clean report, independently of whether the real run was unverifiable.
CLEAN_DEMO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/c3-dogfood-clean-demo.XXXXXX")"
(
  set -euo pipefail
  cd "$CLEAN_DEMO_DIR"
  git init -q -b main
  git config user.email "c3-dogfood@test.local"
  git config user.name "c3-dogfood"
  mkdir -p .aid-o/config
  printf 'project_id: c3-dogfood-clean-demo\n' > .aid-o/config/project.yaml
  printf 'export const a = 1;\n' > app.ts
  git add .
  git commit -q -m base
  clean_base="$(git rev-parse HEAD)"
  printf 'export const b = 2;\n' >> app.ts
  git add app.ts
  git commit -q -m head
  clean_head="$(git rev-parse HEAD)"

  clean_evidence=".aid-o/work/evidence/E-clean-demo/R-clean"
  mkdir -p "$clean_evidence"
  bash "$DISPATCH_BIN" build-manifest "$clean_evidence" "$clean_base" "$clean_head" high >/dev/null
  clean_brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash' "$clean_evidence/audit-input-manifest.json")"

  mkdir -p .fakecodex
  cat > .fakecodex/codex <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-clean-codex 0.0.0 (c3-dogfood supplementary demo — NOT the real codex CLI)"; exit 0; fi
last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last="$2"; shift 2 ;;
    *) shift ;;
  esac
done
report="$(jq -nc --arg h "$FAKE_HEAD" --arg bh "$FAKE_BRIEF_HASH" \
  '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
    findings:[{severity:"medium",area:"maintainability",
               finding:"Naming in the touched module could be clearer.",
               recommendation:"Rename for clarity in a follow-up."}]}')"
jq -nc '{type:"thread.started",thread_id:"019f0000-0000-7000-8000-0000000c1ea1"}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x .fakecodex/codex

  mkdir -p .fakeindep
  printf '#!/usr/bin/env bash\nexit 0\n' > .fakeindep/detect
  chmod +x .fakeindep/detect

  FAKE_HEAD="$clean_head" FAKE_BRIEF_HASH="$clean_brief_hash" \
    AID_C3_INDEPENDENCE_BIN="$CLEAN_DEMO_DIR/.fakeindep/detect" \
    PATH="$CLEAN_DEMO_DIR/.fakecodex:$PATH" \
    bash "$DISPATCH_BIN" dispatch "$clean_evidence" >/dev/null

  echo "$clean_evidence"
) > "$CLEAN_DEMO_DIR/.clean_evidence_path.txt" 2>"$CLEAN_DEMO_DIR/.clean_demo.stderr"
clean_demo_rc=$?
if [[ "$clean_demo_rc" -ne 0 || ! -s "$CLEAN_DEMO_DIR/.clean_evidence_path.txt" ]]; then
  echo "DOGFOOD FAILED: supplementary clean-demo dispatch (fake codex stub) did not succeed:" >&2
  cat "$CLEAN_DEMO_DIR/.clean_demo.stderr" >&2 2>/dev/null || true
  rm -rf "$CLEAN_DEMO_DIR"
  exit 1
fi
clean_evidence_rel="$(tail -n1 "$CLEAN_DEMO_DIR/.clean_evidence_path.txt")"
clean_evidence_abs="$CLEAN_DEMO_DIR/$clean_evidence_rel"

_seed_and_run_done_advance "$CLEAN_DEMO_DIR" "$clean_evidence_abs"
clean_fsm_rc="$LAST_FSM_RC"
clean_fsm_out="$LAST_FSM_OUT"
rm -rf "$CLEAN_DEMO_DIR"

[[ "$clean_fsm_rc" -eq 0 ]] \
  || { echo "DOGFOOD FAILED: supplementary clean-demo seeded done-advance did not advance under enforcement:blocking (rc=$clean_fsm_rc):" >&2; echo "$clean_fsm_out" >&2; exit 1; }
echo "FSM acceptance demo (supplementary, controlled clean dispatch): seeded done-advance advanced under enforcement:blocking — proves the dispatch-provenance mechanism this EPIC built permits advance on genuinely clean, provenance-intact content."

echo "== c3-dogfood: PASSED =="
exit 0
