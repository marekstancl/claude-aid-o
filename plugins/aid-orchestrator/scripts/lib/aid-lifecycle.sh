#!/usr/bin/env bash
# =============================================================================
# lib/aid-lifecycle.sh — IMP-232 canonical plan-level closure (v2.58.0)
#
# Durable, evidence-anchored plan lifecycle: a small set of GIT-TRACKED,
# PUBLIC-SAFE artifacts under .aid-lifecycle/ that survive a clean clone and the
# eco-dev<->eco-prod mirror, while all detailed (potentially sensitive) evidence
# stays in gitignored .aid-o/.
#
#   .aid-lifecycle/repo-identity.yaml     — stable repo UUID (repo-local plan IDs)
#   .aid-lifecycle/manifests/P<NN>.yaml   — declared EPIC set (denominator) +
#                                           structured deps + delivery provenance
#   .aid-lifecycle/receipts/P<NN>.yaml    — final closure receipt
#
# PUBLIC-SAFE CONTRACT (binding): these files may contain ONLY technical
# "receipts" — repo/plan/EPIC IDs, lifecycle state, delivery/review SHAs,
# normalized verdict, blocker count, schema/tool version, timestamps, technical
# hashes. NEVER report bodies, findings text, prompts, agent output, absolute/
# local paths, secrets, PII, customer/project names, or free-form waiver reasons.
# aid_lifecycle_publicsafe_check enforces this before anything is committed.
#
# Pure-ish helpers (git + jq + yq + uuidgen). Idempotent double-source guard.
# =============================================================================
[[ -n "${_AID_LIFECYCLE_SH_LOADED:-}" ]] && return 0
_AID_LIFECYCLE_SH_LOADED=1

# Resolve the plugin's defaults dir (for orchestration.yaml) relative to this lib.
_AID_LC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_AID_LC_LIB_DIR}/aid-adjudication.sh"

# ── Paths ────────────────────────────────────────────────────────────────────
aid_lifecycle_dir()   { echo "${1:-.}/.aid-lifecycle"; }
aid_identity_path()   { echo "$(aid_lifecycle_dir "${1:-.}")/repo-identity.yaml"; }
# aid_manifest_path <plan_id> [root] — the git-tracked lifecycle manifest.
#
# P068 E-068-1_2 Step 6 — THE TARGET-REF OVERRIDE. Every manifest READER in this
# file (aid_lifecycle_declared_epics, _aid_lc_delivered, _aid_lc_reviewed_accepted,
# aid_lifecycle_build_receipt, aid_plan_closure_state) resolves the file through
# this one function, so redirecting it here redirects all of them consistently.
#
# WHY IT IS NEEDED: after a plan merge the delivery bindings live on the TARGET
# branch — Step 5 commits them there by plumbing and then restores the worktree
# copy, because the worktree is sitting on `plan/<plan_id>`, whose copy of the
# manifest predates the bindings. Reading the worktree file at close time
# therefore reports a plan with NO deliveries, i.e. `active`, and would either
# refuse a legitimately closable plan or (worse, had the state check been laxer)
# build a receipt out of the pre-merge manifest. The override materialises the
# TARGET-BRANCH content read-only into a temp file for the duration of a scoped
# read; nothing in the worktree is touched. Deliberately NOT exported — a child
# process must resolve its own.
aid_manifest_path() {
  if [[ -n "${_AID_LC_MANIFEST_OVERRIDE:-}" ]]; then echo "$_AID_LC_MANIFEST_OVERRIDE"; return 0; fi
  echo "$(aid_lifecycle_dir "${2:-.}")/manifests/${1}.yaml"
}

# aid_lc_manifest_ref_begin <plan_id> <root> <ref> — materialise <ref>'s copy of
# the lifecycle manifest and route every reader at it until _end. Returns 1 (and
# sets nothing) when that ref carries no manifest, so a caller can fall back to
# the ordinary worktree path rather than silently reading an empty file.
aid_lc_manifest_ref_begin() {
  local plan_id="$1" root="${2:-.}" ref="$3"
  local rel=".aid-lifecycle/manifests/${plan_id}.yaml"
  local tmp; tmp="$(mktemp 2>/dev/null)" || return 1
  if ! git -C "$root" show "${ref}:${rel}" > "$tmp" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  _AID_LC_MANIFEST_OVERRIDE="$tmp"
  return 0
}

aid_lc_manifest_ref_end() {
  [[ -n "${_AID_LC_MANIFEST_OVERRIDE:-}" ]] && rm -f -- "$_AID_LC_MANIFEST_OVERRIDE" 2>/dev/null
  unset _AID_LC_MANIFEST_OVERRIDE
  return 0
}
aid_receipt_path()    { echo "$(aid_lifecycle_dir "${2:-.}")/receipts/${1}.yaml"; }

# _aid_lc_require_target_branch <root> — 0 iff HEAD is on the configured
# target_branch. NO lifecycle tracked write may happen on any other branch
# (constraint: before merge there are NO tracked lifecycle commits). Callers must
# check this BEFORE writing any worktree lifecycle artifact.

# =============================================================================
# PLAN MODE (P068 E-068-1_2 Step 5) — advancing the target ref by PLUMBING
# =============================================================================
#
# In `plan_branch` mode no EPIC ever merges into the target branch: the ONE
# merge happens at the plan boundary, in `aid-plan-fsm.sh plan-merge-to-main`.
# That command publishes the merge with a compare-and-swap `git update-ref` and
# then has to layer the lifecycle commit (delivery bindings + the CF1 re-scope)
# on top of it — while standing on the PLAN branch, because the target branch is
# normally checked out in another linked worktree and Git refuses the same
# branch in two worktrees. `git checkout <target_branch>` is therefore not
# available, and every function below assumed it.
#
# So plan mode replaces two mechanisms and nothing else:
#
#   1. `_aid_lc_require_target_branch` — the legacy guard asserts
#      `git branch --show-current == target_branch`. Its SAFETY INVARIANT is
#      "the commit lands on the target branch", and in plan mode that is
#      satisfied BY CONSTRUCTION: `_aid_lc_isolated_commit` writes exactly
#      `refs/heads/<target_branch>` with `git update-ref <new> <expected-old>`,
#      using no worktree and no HEAD. The guard is therefore satisfied, not
#      bypassed.
#   2. The three EVIDENCE readers on the binding path. `_aid_lc_find_delivery_merge`
#      greps the target branch for a merge naming the EPIC — but the only merge
#      reaching the target branch is `merge(plan): <plan_id>`, which names no
#      EPIC id, so it returns empty. `_aid_lc_epic_reviewed_head` and
#      `_aid_lc_epic_review_status` read a per-EPIC audit-report.json that the
#      new model no longer produces: in `plan_branch` mode the review genuinely
#      happens ONCE, for the whole plan. In plan mode the merge SHA is supplied
#      explicitly by the caller and the reviewed head / review status come from
#      the PLAN-FINAL run's audit-report.json and curator-report.json.
#
# Everything else — the staged/unstaged collision prechecks, schema + public-safe
# validation, idempotence, `_aid_lc_can_bind`'s ancestry confirmation — is
# UNCHANGED, and every legacy code path is byte-identical when plan mode is off.
#
# Plan mode is activated by `aid_lc_plan_mode_begin` and is a per-process
# setting; `aid_lc_plan_mode_end` clears it. Never leave it on across an
# unrelated lifecycle call.
# -----------------------------------------------------------------------------

# aid_lc_plan_mode_begin <merge_sha> <plan_final_run_dir_abs> <parent_commit>
#   merge_sha   — the published plan merge commit, bound as every EPIC's delivery_sha
#   run_dir_abs — the plan-final run directory holding audit-report.json + curator-report.json
#   parent_commit — the commit the lifecycle commit is built on (the merge commit),
#                   and the CAS "expected old value" for the target ref update
aid_lc_plan_mode_begin() {
  _AID_LC_PLAN_MODE=1
  _AID_LC_PLAN_MERGE_SHA="$1"
  _AID_LC_PLAN_RUN_DIR="$2"
  _AID_LC_PLAN_PARENT="$3"
  export _AID_LC_PLAN_MODE _AID_LC_PLAN_MERGE_SHA _AID_LC_PLAN_RUN_DIR _AID_LC_PLAN_PARENT
}
aid_lc_plan_mode_end() {
  unset _AID_LC_PLAN_MODE _AID_LC_PLAN_MERGE_SHA _AID_LC_PLAN_RUN_DIR _AID_LC_PLAN_PARENT
}
_aid_lc_plan_mode() { [[ "${_AID_LC_PLAN_MODE:-0}" == "1" ]]; }

# _aid_lc_plan_final_trusted_candidate <root> <plan_id> — echoes "<candidate_sha> <run_id>"
# from the DURABLE, git-tracked D1 plan-final evidence receipt (never from a
# gitignored, freely-editable runtime file), or returns 1 if none/ambiguous.
# D5 lifecycle-audit HIGH follow-up: this is the anchor that makes
# _aid_lc_plan_review_status's adjudication bypass safe against a forged
# audit-report.json + curator-report.json pair that is only INTERNALLY
# self-consistent (matching each other) but does not describe the actual
# frozen candidate/run — the receipt requires rewriting immutable git
# history to forge, unlike editing two JSON files in .aid-o/work/.
# Mirrors aid-plan-fsm.sh's _pfsm_recover_plan_final_receipt discovery/dedup
# logic (kept independent, not shared, to avoid aid-lifecycle.sh depending
# on the top-level aid-plan-fsm.sh script).
_aid_lc_plan_final_trusted_candidate() {
  local root="$1" plan_id="$2"
  [[ "$plan_id" =~ ^P[0-9]{3}$ ]] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local -A seen=()
  local found=0 result="" ref
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    # D5 lifecycle-audit round-2 MEDIUM: a singleton-tree check AND the
    # FULL D1 receipt grammar (exact key set, every field's pattern,
    # ref-safe run_id, outputs shape) — not a reduced subset — so this
    # independent reader accepts exactly what aid-plan-fsm.sh's own
    # _pfsm_validate_plan_final_receipt_json/_pfsm_verify_plan_final_receipt
    # would, never something looser. Duplicated rather than sourced (see the
    # comment above the function) — kept in sync deliberately; a schema
    # change to the receipt shape must update both.
    local tree; tree="$(git -C "$root" ls-tree -r --name-only "$ref" 2>/dev/null || true)"
    [[ "$tree" == "receipt.json" ]] || continue
    local receipt; receipt="$(git -C "$root" show "${ref}:receipt.json" 2>/dev/null || true)"
    [[ -n "$receipt" ]] || continue
    jq -e '
      (type == "object") and
      ((keys | sort) == (["artifact_type","candidate_frozen_at","candidate_sha","evidence_ref","outputs","plan_base_commit","plan_id","review_verdict","run_id","schema_version","target_branch","target_head_at_freeze"] | sort)) and
      (.schema_version == "aid-plan-final-evidence-1") and
      (.artifact_type == "plan_final_evidence_receipt") and
      (.review_verdict == "accepted") and
      (.plan_id | test("^P[0-9]{3}$")) and
      (.candidate_sha | test("^[0-9a-f]{40}$")) and
      (.candidate_frozen_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.plan_base_commit | test("^[0-9a-f]{40}$")) and
      (.run_id | test("^[A-Za-z0-9._-]+$")) and
      (.evidence_ref | test("^refs/heads/aid-evidence/P[0-9]{3}/[0-9a-f]{40}/[A-Za-z0-9._-]+$")) and
      (.target_branch | type == "string" and length > 0 and test("^[A-Za-z0-9._/-]+$")) and
      (.target_head_at_freeze | test("^[0-9a-f]{40}$")) and
      (.outputs | type == "object" and length > 0) and
      ([.outputs | to_entries[] | (.key | type == "string" and test("^[A-Za-z0-9._/-]+$") and (contains("..") | not) and (startswith("/") | not)) and (.value | type == "string" and test("^sha256:[0-9a-f]{64}$"))] | all)
    ' <<< "$receipt" >/dev/null 2>&1 || continue
    [[ "$(jq -r '.plan_id' <<< "$receipt")" == "$plan_id" ]] || continue
    local cand run expected
    cand="$(jq -r '.candidate_sha' <<< "$receipt")"
    run="$(jq -r '.run_id' <<< "$receipt")"
    expected="refs/heads/aid-evidence/${plan_id}/${cand}/${run}"
    [[ "$(jq -r '.evidence_ref' <<< "$receipt")" == "$expected" ]] || continue
    local suffix="${ref#refs/heads/}"
    [[ "$suffix" == "$ref" ]] && suffix="$(sed -E 's#^refs/remotes/[^/]+/##' <<< "$ref")"
    [[ "$suffix" == "${expected#refs/heads/}" ]] || continue
    local obj; obj="$(git -C "$root" rev-parse --verify --quiet "$ref" 2>/dev/null || true)"
    [[ -n "$obj" ]] || continue
    if [[ -n "${seen[$suffix]:-}" ]]; then
      [[ "${seen[$suffix]}" == "$obj" ]] || return 1
      continue
    fi
    seen["$suffix"]="$obj"
    found=$((found + 1))
    result="${cand} ${run}"
  done < <(git -C "$root" for-each-ref --format='%(refname)' \
    "refs/heads/aid-evidence/${plan_id}/" "refs/remotes/*/aid-evidence/${plan_id}/**" 2>/dev/null)
  [[ "$found" -eq 1 ]] || return 1
  printf '%s' "$result"
}

# _aid_lc_plan_review_status <root> [plan_id] — the ONE plan-level verdict,
# read from the plan-final run's audit-report.json + curator-report.json.
# Same vocabulary and the same fail-closed bias as the per-EPIC classifier it
# stands in for: `unverifiable` whenever the evidence does not positively say
# "no blockers", never a default to `accepted`. <root> is REQUIRED for the
# adjudication bypass below (it anchors candidate/run to the durable
# receipt); omitting it does not break normal classification, it just
# disables that bypass. [plan_id] — D5 lifecycle-audit round-2 HIGH: MUST be
# the caller's own authoritative plan id (threaded from
# aid_lifecycle_bind_delivery's/aid_lifecycle_plan_reconcile's own trusted
# `plan_id` parameter, all the way from aid-plan-fsm.sh's CLI-level plan
# argument) — NEVER guessed from the mutable, gitignored
# plan_final_evidence_dir path this function's run directory ultimately
# derives from. A path-derived guess is exactly what let an attacker who
# controls that mutable field redirect the trusted-receipt lookup at an
# unrelated plan's (possibly also-legitimate) receipt. Omitting plan_id
# disables the adjudication bypass entirely (falls through to "rejected"),
# it is never silently guessed.
_aid_lc_plan_review_status() {
  local root="${1:-.}" plan_id="${2:-}"
  local dir="${_AID_LC_PLAN_RUN_DIR:-}"
  [[ -n "$dir" ]] || { echo "none"; return 0; }
  local audit="${dir}/audit-report.json" curator="${dir}/curator-report.json"
  [[ -f "$audit" ]] || { echo "none"; return 0; }
  local st bf
  st="$(jq -r '.status // ""' "$audit" 2>/dev/null || true)"
  # `//` is NOT usable here: jq treats `false` as falsy, so `.blocking_findings //
  # .audit_report.blocking_findings` would fall through on the very value that
  # means "accepted". Read the two shapes explicitly instead.
  bf="$(jq -r 'if has("blocking_findings") then .blocking_findings
               elif (.audit_report? | type) == "object" and (.audit_report | has("blocking_findings")) then .audit_report.blocking_findings
               else null end' "$audit" 2>/dev/null || true)"
  if [[ "$st" == "unverifiable" ]]; then echo "unverifiable"; return 0; fi
  if [[ "$bf" == "true" || ( "$bf" =~ ^[0-9]+$ && "$bf" != "0" ) ]]; then
    # D5 / IMP-468 follow-up (auditor-flagged gap): a raw Auditor
    # blocking_findings:true is not automatically "rejected" anymore — the
    # plan-final review boundary (aid-plan-fsm.sh's own, stricter D5 gate)
    # may have already accepted a formal, exactly-bound Curator adjudication
    # for every critical|high finding. Without this check, a plan that
    # legitimately passed that gate could never reach "accepted" here,
    # permanently misclassified in the git-tracked .aid-lifecycle layer
    # regardless of how the plan-final boundary itself judged it. Only a
    # FULLY resolved set (every blocking finding validly adjudicated, no
    # malformed/stale entries, no illegal false_positive) bypasses this —
    # anything less falls through to "rejected", same as before.
    #
    # D5 lifecycle-audit HIGH: candidate_sha/run_id are NOT read from
    # audit-report.json's own envelope — that file (and curator-report.json)
    # are gitignored, mutable, and being classified BY this same function;
    # an attacker who can replace both together, internally consistently,
    # could otherwise redefine their own trust anchor. They are read from
    # the DURABLE, git-tracked plan-final evidence receipt instead
    # (_aid_lc_plan_final_trusted_candidate), and audit-report.json's own
    # envelope is then required to AGREE with that trusted anchor — a
    # mismatch (or no discoverable/unambiguous receipt at all) refuses the
    # bypass instead of trusting the file being classified to name its own
    # candidate.
    local trusted=""
    if [[ -n "$plan_id" ]]; then
      trusted="$(_aid_lc_plan_final_trusted_candidate "$root" "$plan_id" 2>/dev/null || true)"
    fi
    local adj_candidate="" adj_run=""
    if [[ -n "$trusted" ]]; then
      read -r adj_candidate adj_run <<< "$trusted"
    fi
    local env_candidate env_run
    env_candidate="$(jq -r '.revision.head_sha // ""' "$audit" 2>/dev/null || true)"
    env_run="$(jq -r '.identity.run_id // ""' "$audit" 2>/dev/null || true)"
    if [[ -n "$adj_candidate" && -n "$adj_run" && "$env_candidate" == "$adj_candidate" && "$env_run" == "$adj_run" && -f "$curator" ]] \
       && aid_adjudication_fully_resolved "$audit" "$curator" "$adj_candidate" "$adj_run"; then
      : # every raw blocker is formally, validly adjudicated against the durably-anchored candidate/run — do not reject on the raw flag alone
    else
      echo "rejected"; return 0
    fi
  fi
  if [[ "$bf" != "false" && "$bf" != "0" && "$bf" != "true" && ! ( "$bf" =~ ^[0-9]+$ ) ]]; then echo "unverifiable"; return 0; fi
  # The Curator's verdict is part of the plan-level review, so a Curator that
  # reports blockers rejects the plan just as the Auditor does.
  if [[ -f "$curator" ]]; then
    local cbf; cbf="$(jq -r 'if has("blocking_findings") then .blocking_findings
                             elif (.curator? | type) == "object" and (.curator | has("blocking_findings")) then .curator.blocking_findings
                             else false end' "$curator" 2>/dev/null || true)"
    if [[ "$cbf" == "true" || ( "$cbf" =~ ^[0-9]+$ && "$cbf" != "0" ) ]]; then echo "rejected"; return 0; fi
  fi
  echo "accepted"
}

_aid_lc_require_target_branch() {
  local root="${1:-.}" cur tb
  # Plan mode: the write is published straight to refs/heads/<target_branch> by
  # `git update-ref`, so the invariant this guard protects holds by construction.
  # There is no branch to be "on" — see the PLAN MODE header above.
  if _aid_lc_plan_mode; then return 0; fi
  cur="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  tb="$(aid_target_branch)"
  if [[ "$cur" != "$tb" ]]; then
    echo "lifecycle: refusing on branch '${cur:-<detached>}' — lifecycle writes only on target_branch '${tb}' (pre-merge/task branches make NO tracked lifecycle commit)" >&2
    return 3
  fi
  return 0
}

# ── Isolated commit (never touches the user's index) ─────────────────────────
# _aid_lc_isolated_commit <root> <message> <relpath...>
# Commits ONLY the given paths on target_branch via a throwaway GIT_INDEX_FILE,
# then re-syncs ONLY those paths' entries in the real index. FAIL-CLOSED guards:
#   - refuses on a non-target branch (never a commit on a task branch);
#   - refuses if the USER has any of the target paths STAGED in the real index
#     (a lifecycle collision would otherwise be silently clobbered by the reset).
# The user's own staged/unstaged files are provably untouched (index-fingerprint
# tests). No-op if nothing changed. Non-zero on any failure (leaving the worktree
# file untracked → ignored by the init clean-tree guard → recovery re-runs).
# _aid_lc_no_staged_collision <root> <relpath...> — refuses (4) if the user has any
# target path STAGED in their real index. Safe to call AFTER AID has written its own
# canonical content to the worktree path (it ignores unstaged worktree state), so it
# is the defense-in-depth guard used INSIDE _aid_lc_isolated_commit.
_aid_lc_no_staged_collision() {
  local root="$1"; shift
  local staged; staged="$(git -C "$root" diff --cached --name-only -- "$@" 2>/dev/null || true)"
  if [[ -n "$staged" ]]; then
    echo "lifecycle: refusing — a lifecycle path is staged in your index: ${staged//$'\n'/ } (unstage it; AID manages these files)" >&2
    return 4
  fi
  return 0
}

# _aid_lc_precheck_write <root> <relpath...> — the fail-closed ENTRY precondition for
# ANY lifecycle write. Call BEFORE AID writes/modifies a worktree artifact. Refuses
# (3) off target_branch, and (4) if the user has EITHER a STAGED lifecycle path OR an
# UNSTAGED modification to an already-tracked lifecycle path. The unstaged check is
# essential: the isolated commit builds its tree from the worktree files on disk, so
# an uncommitted user edit to a tracked manifest/receipt would otherwise be swept
# into AID's automatic commit. NEVER call this from inside _aid_lc_isolated_commit —
# by then AID has legitimately modified the worktree file, so an unstaged diff is
# AID's own; use _aid_lc_no_staged_collision there.
_aid_lc_precheck_write() {
  local root="$1"; shift
  _aid_lc_require_target_branch "$root" || return 3
  _aid_lc_no_staged_collision "$root" "$@" || return 4
  local unstaged; unstaged="$(git -C "$root" diff --name-only -- "$@" 2>/dev/null || true)"
  if [[ -n "$unstaged" ]]; then
    echo "lifecycle: refusing — a tracked lifecycle path has UNSTAGED changes: ${unstaged//$'\n'/ } (commit or discard your edit; AID manages these files)" >&2
    return 4
  fi
  return 0
}

_aid_lc_isolated_commit() {
  local root="$1" msg="$2"; shift 2
  local rels=("$@")
  # Defense-in-depth: AID has already written its canonical content to these paths,
  # so only a STAGED user collision is meaningful here (an unstaged diff would be
  # AID's own legitimate write). The full unstaged/entry guard runs at the caller.
  _aid_lc_require_target_branch "$root" || return 3
  _aid_lc_no_staged_collision "$root" "${rels[@]}" || return $?

  # ── PLAN MODE: advance the target ref by plumbing, never by checkout ──────
  # Built on the caller-supplied parent (the published plan merge commit) and
  # published with a compare-and-swap against that same commit, so a concurrent
  # writer cannot be clobbered. No worktree, no HEAD, no index reset — which is
  # what makes this work with the target branch checked out in another worktree.
  # The worktree copies of the lifecycle paths are restored afterwards, so the
  # plan branch is not left dirty by a write that is already durable elsewhere.
  if _aid_lc_plan_mode; then
    local tb; tb="$(aid_target_branch)"
    local parent="${_AID_LC_PLAN_PARENT:-}"
    if [[ -z "$parent" ]]; then
      echo "lifecycle: plan mode requires a parent commit (aid_lc_plan_mode_begin) — refusing to guess one" >&2
      return 1
    fi
    # The ref must still be where the caller said it was — otherwise something
    # else moved the target branch and this commit's CAS base is a guess.
    local live; live="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${tb}" 2>/dev/null || true)"
    if [[ "$live" != "$parent" ]]; then
      echo "lifecycle: refusing the plan-mode lifecycle commit — ${tb} is at ${live:-<absent>}, not at the expected ${parent} (something else advanced the target branch)" >&2
      return 1
    fi
    local rc=0 newsha=""
    newsha="$( cd "$root"
      tmpidx="$(mktemp)"
      if ! GIT_INDEX_FILE="$tmpidx" git read-tree "$parent" 2>/dev/null; then rm -f "$tmpidx"; exit 1; fi
      GIT_INDEX_FILE="$tmpidx" git add -- "${rels[@]}" 2>/dev/null
      tree="$(GIT_INDEX_FILE="$tmpidx" git write-tree 2>/dev/null)"
      rm -f "$tmpidx"
      [[ -n "$tree" ]] || exit 1
      # Idempotent: identical content on the parent means the write already landed.
      [[ "$tree" == "$(git rev-parse "${parent}^{tree}" 2>/dev/null)" ]] && exit 0
      commit="$(git commit-tree "$tree" -p "$parent" -m "$msg" 2>/dev/null)"
      [[ -n "$commit" ]] || exit 1
      git update-ref "refs/heads/${tb}" "$commit" "$parent" 2>/dev/null || exit 1
      printf '%s' "$commit"
    )" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      # Advance the CAS base so a SECOND plan-mode commit in the same pass (the
      # receipt, Step 6) chains onto this one instead of re-CASing against a
      # commit the ref has already left.
      [[ -n "$newsha" ]] && _AID_LC_PLAN_PARENT="$newsha"
      # Restore the worktree copies: the content is durable on the target branch,
      # and leaving the plan branch dirty would fail the next stage's clean-tree
      # precondition for a change that is not the plan branch's.
      local r
      for r in "${rels[@]}"; do
        if git -C "$root" ls-files --error-unmatch -- "$r" >/dev/null 2>&1; then
          git -C "$root" checkout -q HEAD -- "$r" 2>/dev/null || true
        fi
      done
    fi
    return "$rc"
  fi

  ( cd "$root"
    local tmpidx; tmpidx="$(mktemp)"
    if ! GIT_INDEX_FILE="$tmpidx" git read-tree HEAD 2>/dev/null; then rm -f "$tmpidx"; exit 1; fi
    GIT_INDEX_FILE="$tmpidx" git add -- "${rels[@]}" 2>/dev/null
    local tree; tree="$(GIT_INDEX_FILE="$tmpidx" git write-tree 2>/dev/null)"
    rm -f "$tmpidx"
    [[ -n "$tree" ]] || exit 1
    # No-op if the paths are already committed identically.
    [[ "$tree" == "$(git rev-parse 'HEAD^{tree}' 2>/dev/null)" ]] && exit 0
    local parent commit
    parent="$(git rev-parse HEAD 2>/dev/null)"
    commit="$(git commit-tree "$tree" -p "$parent" -m "$msg" 2>/dev/null)"
    [[ -n "$commit" ]] || exit 1
    git update-ref HEAD "$commit" 2>/dev/null || exit 1
    git reset -q -- "${rels[@]}" 2>/dev/null || true
  )
}

# ── Repo identity ────────────────────────────────────────────────────────────
# aid_repo_id [root] — stable, git-tracked UUID. Created once (uuidgen; fallback
# to the root-commit SHA as a legacy bootstrap) and then persisted, so it is
# copied by clone AND by the eco-dev<->eco-prod mirror. NEVER derived from the
# git remote URL (a mirror would then carry two identities).
aid_repo_id() {
  local root="${1:-.}"
  local id_file; id_file="$(aid_identity_path "$root")"
  if [[ -f "$id_file" ]]; then
    local existing; existing="$(yq -r '.repo_id // ""' "$id_file" 2>/dev/null || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then echo "$existing"; return 0; fi
  fi
  # Create + persist.
  local new_id=""
  if command -v uuidgen >/dev/null 2>&1; then
    new_id="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ -z "$new_id" ]]; then
    # Legacy bootstrap fallback: root commit SHA (still stable across clone/mirror).
    new_id="rootcommit-$(git -C "$root" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)"
  fi
  mkdir -p "$(dirname "$id_file")"
  {
    echo "schema_version: aid-lifecycle-identity-1.0"
    echo "repo_id: ${new_id}"
  } > "$id_file"
  echo "$new_id"
}

# ── Target branch config ─────────────────────────────────────────────────────
# aid_target_branch — the configured integration branch (NOT hardcoded 'main').
# Reads .lifecycle.target_branch from orchestration.yaml, default 'main'.
aid_target_branch() {
  local orch="${_AID_LC_LIB_DIR}/../../defaults/orchestration.yaml"
  local tb=""
  [[ -f "$orch" ]] && tb="$(yq -r '.lifecycle.target_branch // ""' "$orch" 2>/dev/null || true)"
  [[ -z "$tb" || "$tb" == "null" ]] && tb="main"
  echo "$tb"
}

# ── Plan mode (P064 E-064-1_2 Step 3) ────────────────────────────────────────
# aid_lifecycle_plan_mode <plan_id> [root] — the AUTHORITATIVE reader for which
# release model plan_id follows. Reads ONLY the git-tracked manifest
# `.aid-lifecycle/manifests/<plan_id>.yaml` — never plan-state.yaml's own
# `mode` cache (see aid-plan-state.sh's file header for that cache's own
# explicit disclaimer: "THIS STEP DOES NOT IMPLEMENT THAT RE-READ" — this
# function is the reader a later step wires plan_state_get's `mode` output
# against, fail-closed on a mismatch).
#
# Always echoes exactly one of "plan_branch" / "legacy_epic_release_mode" and
# always returns 0 — there is no "not_found"/"corrupt" exit code here on
# purpose: a plan with no manifest, or a manifest with no `mode` key (every
# manifest written before this step, or one `aid_lifecycle_ensure_manifest`
# created without ever calling `aid_lifecycle_set_plan_mode`), is legitimately
# "not yet declared plan_branch" — the documented default is the release
# model that was already in effect before P064 introduced plan/Pxxx branches,
# so absence is never ambiguous. A manifest that fails to parse as YAML is
# treated the same way (fail SAFE to the pre-P064 model, not fail-open to the
# newer, stricter one a caller might not be ready to enforce).
aid_lifecycle_plan_mode() {
  local plan_id="$1" root="${2:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || { echo "legacy_epic_release_mode"; return 0; }
  local mode; mode="$(yq -r '.mode // ""' "$manifest" 2>/dev/null || true)"
  case "$mode" in
    plan_branch) echo "plan_branch" ;;
    *)           echo "legacy_epic_release_mode" ;;
  esac
  return 0
}

# aid_lifecycle_set_plan_mode <plan_id> <mode> [root] — the DURABLE mode-write
# path `plan-start` (a LATER step, Step 4, not yet built) needs to persist the
# authoritative release model into the git-tracked manifest BEFORE any EPIC
# begins. Ensures the manifest exists first (aid_lifecycle_ensure_manifest —
# creating it from a strict legacy parse of the prose plan if none exists
# yet), then durably writes `.mode` via the SAME isolated-commit path every
# other lifecycle mutator uses (never touches the user's index; fail-closed
# entry precheck against a staged/unstaged collision on the manifest path).
# Idempotent: a no-op (return 0, no write, no commit) when the manifest
# already carries the requested mode.
#
# Returns: 0 durably written (or already correct), 1 bad mode arg / manifest
# write or schema-validate failure, 2 ambiguous plan (legacy-unverifiable),
# 3 plan not found / not on target_branch, 4 user staged/unstaged collision,
# 5 commit not durable (recoverable — re-run).
aid_lifecycle_set_plan_mode() {
  local plan_id="$1" mode="$2" root="${3:-.}"
  case "$mode" in
    plan_branch|legacy_epic_release_mode) ;;
    *)
      echo "lifecycle: aid_lifecycle_set_plan_mode: mode must be 'plan_branch' or 'legacy_epic_release_mode' (got '${mode:-<empty>}')" >&2
      return 1
      ;;
  esac

  # Ensures the manifest is durably present (creates + commits it from the
  # strict legacy parse if this is the plan's first lifecycle write). Any
  # non-zero here (ambiguous/not-found/collision/commit-failure) propagates
  # UNTOUCHED — a mode write must never proceed on a manifest that isn't
  # itself durably in place.
  local mrc=0
  aid_lifecycle_ensure_manifest "$plan_id" "$root" >/dev/null 2>&1 || mrc=$?
  [[ "$mrc" -ne 0 ]] && return "$mrc"

  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  local relpath=".aid-lifecycle/manifests/${plan_id}.yaml"
  # Entry precheck BEFORE mutating the (now durable) manifest: a user's
  # staged/unstaged edit to the tracked manifest must never be swept into
  # this commit (ensure_manifest early-returns for an already-durable
  # manifest without re-prechecking, so this is the guard that catches that
  # case — mirrors aid_lifecycle_record_delivery's own re-precheck).
  _aid_lc_precheck_write "$root" "$relpath" || return $?

  local current; current="$(yq -r '.mode // ""' "$manifest" 2>/dev/null || true)"
  [[ "$current" == "$mode" ]] && return 0   # already correct — documented no-op

  local tmp; tmp="$(mktemp)"
  yq ".mode = \"${mode}\"" "$manifest" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  # Validate BEFORE placing into the worktree — fail-closed, mirrors every
  # other lifecycle write in this file (never a partially-written, unvalidated
  # tracked artifact).
  if ! aid_lifecycle_validate_artifact "$tmp" "plan-lifecycle-manifest.schema.json"; then
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$manifest"

  if ! _aid_lc_isolated_commit "$root" "lifecycle: mode=${mode} for ${plan_id}" "$relpath"; then
    echo "lifecycle: aid_lifecycle_set_plan_mode: manifest mode write not committed for ${plan_id} (recoverable — re-run)" >&2
    return 5
  fi
  git -C "$root" cat-file -e "$(aid_target_branch):${relpath}" 2>/dev/null || return 5
  return 0
}

# ── Public-safe contract enforcement ─────────────────────────────────────────
# aid_lifecycle_publicsafe_check <yaml_file>
# Rejects (exit 1) any lifecycle artifact that carries content the public-safe
# contract forbids. Two independent guards:
#   (a) forbidden VALUE patterns — absolute/home paths, obvious secret markers.
#   (b) forbidden KEY names — report/findings/prompt/reason/output/path bodies.
# Unknown-field rejection (additionalProperties:false) is enforced separately by
# the JSON-Schema validation of manifests/receipts; this is the value/secret net.
aid_lifecycle_publicsafe_check() {
  local f="$1"
  [[ -f "$f" ]] || { echo "publicsafe: file not found: $f" >&2; return 1; }
  # (a) forbidden value patterns (absolute paths, home dirs, common secret tokens)
  if grep -nEi '(^|[^A-Za-z0-9_])(/home/|/Users/|/opt/|/root/|/var/|/etc/|[A-Za-z]:\\\\)' "$f" >/dev/null 2>&1; then
    echo "publicsafe: absolute/local path detected in $f (forbidden)" >&2; return 1
  fi
  if grep -nEi '(BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|xox[baprs]-|ghp_[A-Za-z0-9]{20,}|password|secret[_-]?key|api[_-]?key|token[[:space:]]*:)' "$f" >/dev/null 2>&1; then
    echo "publicsafe: possible secret/credential detected in $f (forbidden)" >&2; return 1
  fi
  # (b) forbidden key names (free-text bodies must live in gitignored .aid-o/)
  if grep -nEi '^[[:space:]]*(report_body|findings_text|finding|prompt|agent_output|rendered_prompt|waiver_reason|reason|local_path|abs_path|notes|description)[[:space:]]*:' "$f" >/dev/null 2>&1; then
    echo "publicsafe: forbidden free-text/body key detected in $f (only technical receipt fields allowed)" >&2; return 1
  fi
  return 0
}

# ── Schema validation (additionalProperties:false enforcement) ───────────────
aid_lifecycle_schema_dir() { echo "${_AID_LC_LIB_DIR}/../../defaults/schemas"; }

# aid_lifecycle_schema_validate <yaml_file> <schema_basename>
# Converts the YAML artifact to JSON and validates it against the given schema
# (additionalProperties:false rejects unknown fields). The public-safe contract
# is BINDING, so the validator is required: if python3/jsonschema is unavailable
# this FAILS CLOSED (exit 1) rather than silently passing an unvalidated artifact
# destined for a public-safe git commit. Exit 1 on a real schema violation.
aid_lifecycle_schema_validate() {
  local yaml_f="$1" schema_base="$2"
  local schema_f; schema_f="$(aid_lifecycle_schema_dir)/${schema_base}"
  [[ -f "$yaml_f" ]] || { echo "schema: file not found: $yaml_f" >&2; return 1; }
  [[ -f "$schema_f" ]] || { echo "schema: schema not found: $schema_f" >&2; return 1; }
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
    echo "schema: validator unavailable (python3 + jsonschema required to validate lifecycle artifacts before commit)" >&2
    return 1
  fi
  yq -o=json '.' "$yaml_f" 2>/dev/null | python3 -c '
import sys, json, jsonschema
schema = json.load(open(sys.argv[1]))
try:
    inst = json.load(sys.stdin)
except Exception as e:
    print("schema: artifact is not valid YAML/JSON: %s" % e, file=sys.stderr); sys.exit(1)
try:
    jsonschema.validate(inst, schema)
except jsonschema.ValidationError as e:
    print("schema: %s" % e.message, file=sys.stderr); sys.exit(1)
' "$schema_f"
}

# aid_lifecycle_validate_artifact <yaml_file> <schema_basename>
# The MANDATORY pre-commit gate for any .aid-lifecycle/ artifact: it must pass
# BOTH the JSON-Schema validation (allowlist + additionalProperties:false) AND
# the public-safe value/secret/abs-path net. Either failure => exit 1.
aid_lifecycle_validate_artifact() {
  local yaml_f="$1" schema_base="$2"
  aid_lifecycle_schema_validate "$yaml_f" "$schema_base" || return 1
  aid_lifecycle_publicsafe_check "$yaml_f" || return 1
  return 0
}

# ── Legacy strict EPIC-declaration parser ────────────────────────────────────
# aid_lifecycle_parse_legacy_epics <plan_id> <plan_file>
# STRICT grammar only (no fuzzy hint search). A plan declares its EPICs as bold
# lines:
#     **EPIC N: ...**            -> scope: required
#     **EPIC N / Backlog: ...**  -> scope: backlog
# Any bold EPIC line NOT matching either form, a non-contiguous 1..K numbering,
# or zero EPIC lines => the whole plan is ambiguous: prints nothing, returns 2
# (caller classifies the plan legacy-unverifiable, never a guess).
# On success prints one "E-<planNum>-<N>_<K> <scope>" line per EPIC, ordered.
aid_lifecycle_parse_legacy_epics() {
  local plan_id="$1" plan_file="$2"
  [[ -f "$plan_file" ]] || return 2
  local plan_num="${plan_id#P}"
  [[ "$plan_num" =~ ^[0-9]+$ ]] || return 2

  # Collect bold EPIC lines in document order.
  local -a nums=() scopes=()
  local line n scope
  while IFS= read -r line; do
    if [[ "$line" =~ ^\*\*EPIC\ ([0-9]+)\ /\ [Bb]acklog ]]; then
      n="${BASH_REMATCH[1]}"; scope="backlog"
    elif [[ "$line" =~ ^\*\*EPIC\ ([0-9]+): ]]; then
      n="${BASH_REMATCH[1]}"; scope="required"
    elif [[ "$line" =~ ^\*\*EPIC\ ([0-9]+) ]]; then
      # a bold EPIC line in neither sanctioned form -> ambiguous
      return 2
    else
      continue
    fi
    nums+=("$n"); scopes+=("$scope")
  done < <(grep -E '^\*\*EPIC [0-9]+' "$plan_file")

  local k="${#nums[@]}"
  [[ "$k" -ge 1 ]] || return 2
  # Numbering must be exactly 1..K in order (contiguous, no dupes, no gaps).
  local i
  for (( i=0; i<k; i++ )); do
    [[ "${nums[$i]}" -eq $((i+1)) ]] || return 2
  done
  for (( i=0; i<k; i++ )); do
    printf 'E-%s-%d_%d %s\n' "$plan_num" "$((i+1))" "$k" "${scopes[$i]}"
  done
  return 0
}

# ── Receipt build + commit (receipt-first, isolated, fail-closed) ────────────
# aid_lifecycle_build_receipt <plan_id> <root> — emit the closure receipt YAML to
# stdout, built from the manifest's declared_epics + deliveries. Includes ALL
# declared EPICs (required + backlog) for provenance honesty, but closing only
# depends on the REQUIRED set (verified by the caller).
aid_lifecycle_build_receipt() {
  local plan_id="$1" root="${2:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local repo_id tb mhash
  repo_id="$(yq -r '.repo_id // ""' "$manifest")"
  tb="$(aid_target_branch)"
  # plan_manifest_sha covers the identity/denominator keys only (§3.3):
  # exclude deliveries + any closure block so binding/closing never churns it.
  mhash="sha256:$(yq -o=json '{"schema_version":.schema_version,"repo_id":.repo_id,"plan_id":.plan_id,"source_plan_sha":.source_plan_sha,"declared_epics":.declared_epics,"depends_on_plans":.depends_on_plans}' "$manifest" 2>/dev/null | jq -cS . 2>/dev/null | sha256sum | cut -c1-64)"
  {
    echo "schema_version: aid-lifecycle-receipt-1.0"
    echo "repo_id: ${repo_id}"
    echo "plan_id: ${plan_id}"
    echo "plan_manifest_sha: ${mhash}"
    echo "state: closed"
    echo "target_branch: ${tb}"
    echo "aid_version: ${AID_LIFECYCLE_VERSION:-2.58.0}"
    echo "epics:"
    local eid scope
    while read -r eid scope; do
      [[ -z "$eid" ]] && continue
      local dsha rsha verdict blockers
      dsha="$(yq -r ".deliveries.\"${eid}\".delivery_sha // \"\"" "$manifest")"
      rsha="$(yq -r ".deliveries.\"${eid}\".reviewed_sha // \"\"" "$manifest")"
      verdict="$(yq -r ".deliveries.\"${eid}\".review // \"\"" "$manifest")"
      blockers="$(yq -r ".deliveries.\"${eid}\".unresolved_blockers // 0" "$manifest")"
      echo "  - epic_id: ${eid}"
      [[ -n "$dsha" && "$dsha" != "null" ]] && echo "    delivery_sha: ${dsha}"
      [[ -n "$rsha" && "$rsha" != "null" ]] && echo "    reviewed_sha: ${rsha}"
      [[ -n "$verdict" && "$verdict" != "null" ]] && echo "    verdict: ${verdict}"
      echo "    unresolved_blocker_count: ${blockers:-0}"
    done < <(aid_lifecycle_declared_epics "$plan_id" "$root")
  }
}

# aid_lifecycle_commit_receipt <plan_id> <root> — write the receipt to the work
# tree, validate (schema + public-safe) BEFORE committing, then commit ONLY the
# receipt path via `git commit -- <path>` (git's internal temp index; the user's
# real index is never touched). Returns 0 iff the receipt is committed + reachable
# from target_branch. On validation failure NOTHING is committed (fail-closed).
aid_lifecycle_commit_receipt() {
  local plan_id="$1" root="${2:-.}"
  local relpath=".aid-lifecycle/receipts/${plan_id}.yaml"
  # Fail-closed BEFORE writing anything: target_branch + no staged collision.
  _aid_lc_precheck_write "$root" "$relpath" || return $?
  local receipt="${root}/${relpath}"
  mkdir -p "$(dirname "$receipt")"
  local tmp; tmp="$(mktemp)"
  aid_lifecycle_build_receipt "$plan_id" "$root" > "$tmp" || { rm -f "$tmp"; return 1; }
  # Validate BEFORE writing into the tree (fail-closed: no partial closed state).
  if ! aid_lifecycle_validate_artifact "$tmp" "plan-lifecycle-receipt.schema.json"; then
    rm -f "$tmp"; return 1
  fi
  # An untracked receipt already on disk is EITHER our own interrupted-run artifact
  # (byte-identical to the canonical one we just built => safe to re-commit) OR a
  # user collision (differs => refuse, never clobber). A tracked+modified receipt is
  # already refused by the entry precheck above; this guards only the untracked case.
  if [[ -f "$receipt" ]] && ! git -C "$root" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1; then
    if ! cmp -s "$receipt" "$tmp"; then
      rm -f "$tmp"
      echo "lifecycle: refusing — an untracked receipt ${relpath} differs from the canonical receipt (user collision; remove or reconcile it — AID will not overwrite it)" >&2
      return 4
    fi
  fi
  mv "$tmp" "$receipt"
  # Isolated commit — the user's index/staged files are never touched. Idempotent
  # (no-op if already committed identically). Recovery from an interrupted prior
  # run (untracked/staged receipt) just re-runs this.
  _aid_lc_isolated_commit "$root" "closure: receipt for ${plan_id}" "$relpath" || true
  # `closed` iff the receipt is committed AND reachable from target_branch. A
  # plan-close run on a non-target branch (or a failed commit) yields
  # closing_pending_commit here (durability check fails), never a false closed.
  aid_lifecycle_receipt_durable "$plan_id" "$root"
}

# aid_lifecycle_plan_close <plan_id> <root> [<plan_mode_parent>] — forward-path
# close. Requires the manifest to show EVERY required EPIC delivered +
# reviewed-accepted; then writes + commits the receipt (=> closed). Fail-closed:
# any missing predicate => no receipt, non-zero.
#
# P068 E-068-1_2 Step 6 — PLAN-MODE PLUMBING (the third optional argument).
# Without it the receipt commit reaches _aid_lc_isolated_commit's ordinary path,
# which goes through _aid_lc_require_target_branch and refuses whenever the
# target branch is not the branch currently checked out — the NORMAL case for a
# plan-branch close, where the controller sits on plan/<plan_id> and the target
# branch may additionally be checked out in another worktree. Passing the LIVE
# target head as <plan_mode_parent> switches the receipt commit to the same
# `commit-tree` + CAS `update-ref` path Step 5 established for the delivery
# bindings: no checkout, no HEAD move, no index reset.
#
# RESTORE-ON-FAILURE (mirrors aid_lifecycle_plan_merge_bind's _lc_rollback
# discipline, added for the same reason): in plan mode a failed close must leave
# the worktree byte-identical to never having run, because the caller's
# clean-worktree precondition would otherwise refuse the prescribed re-run. A
# receipt that did not exist on entry is removed; one that did is restored. The
# LEGACY (two-argument) path deliberately keeps its existing behaviour — an
# uncommitted receipt left on disk is what makes aid_plan_closure_state report
# `closing_pending_commit`, which several callers and suites depend on.
aid_lifecycle_plan_close() {
  local plan_id="$1" root="${2:-.}" plan_parent="${3:-}"

  # Plan mode reads (and builds the receipt from) the TARGET BRANCH's manifest —
  # the one Step 5's bindings landed on — not the plan branch's stale worktree
  # copy. See aid_manifest_path's header for why this is a correctness fix and
  # not a convenience.
  local _mref=0
  if [[ -n "$plan_parent" ]]; then
    aid_lc_manifest_ref_begin "$plan_id" "$root" "$(aid_target_branch)" && _mref=1
  fi

  # _pc_done <rc> — the single exit point that drops the target-ref override.
  _pc_done() { [[ "$_mref" -eq 1 ]] && aid_lc_manifest_ref_end; return "$1"; }

  local st; st="$(aid_plan_closure_state "$plan_id" "$root")"
  case "$st" in
    closed) echo "already closed" >&2; _pc_done 0; return 0 ;;
    not_found) echo "plan-close: ${plan_id} not found" >&2; _pc_done 3; return 3 ;;
    legacy-unverifiable) echo "plan-close: ${plan_id} is legacy-unverifiable (run plan-reconcile)" >&2; _pc_done 1; return 1 ;;
    active) echo "plan-close: ${plan_id} is active — not all required EPICs are delivered + reviewed-accepted" >&2; _pc_done 1; return 1 ;;
    delivered-but-unreconciled|closing_pending_commit) ;;
    # CP2 L3: the case had no default arm, so an empty or unrecognised closure
    # state fell straight through and committed a receipt — declaring a plan
    # closed on the strength of a state nobody could name. Fail closed.
    *) echo "plan-close: ${plan_id} has an unrecognised closure state '${st:-<empty>}' — refusing to write a receipt for a state this code cannot interpret" >&2; _pc_done 1; return 1 ;;
  esac

  # delivered-but-unreconciled or closing_pending_commit -> write/commit receipt.
  if [[ -z "$plan_parent" ]]; then
    aid_lifecycle_commit_receipt "$plan_id" "$root" || { echo "plan-close: receipt not committed/reachable for ${plan_id}" >&2; return 1; }
    echo "closed ${plan_id}"
    return 0
  fi

  # ── Plan mode ────────────────────────────────────────────────────────────
  local tb; tb="$(aid_target_branch)"
  local live; live="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${tb}" 2>/dev/null || true)"
  if [[ "$live" != "$plan_parent" ]]; then
    echo "plan-close: refusing the plan-mode receipt commit — ${tb} is at ${live:-<absent>}, not at the expected ${plan_parent} (something else advanced the target branch)" >&2
    _pc_done 1; return 1
  fi

  local receipt; receipt="$(aid_receipt_path "$plan_id" "$root")"
  local _rc_snap="" _rc_existed=0
  if [[ -f "$receipt" ]]; then
    _rc_existed=1
    _rc_snap="$(mktemp 2>/dev/null)" || _rc_snap=""
    [[ -n "$_rc_snap" ]] && cp -p -- "$receipt" "$_rc_snap" 2>/dev/null
  fi

  aid_lc_plan_mode_begin "" "" "$plan_parent"
  local crc=0
  aid_lifecycle_commit_receipt "$plan_id" "$root" || crc=$?
  local newparent="${_AID_LC_PLAN_PARENT:-$plan_parent}"
  aid_lc_plan_mode_end

  if [[ "$crc" -ne 0 ]]; then
    if [[ "$_rc_existed" -eq 1 ]]; then
      [[ -n "$_rc_snap" && -f "$_rc_snap" ]] && cp -p -- "$_rc_snap" "$receipt" 2>/dev/null
    else
      rm -f -- "$receipt" 2>/dev/null || true
    fi
    [[ -n "$_rc_snap" ]] && rm -f -- "$_rc_snap" 2>/dev/null
    echo "plan-close: receipt not committed/reachable for ${plan_id} — the worktree is restored to its pre-run bytes; re-run to converge." >&2
    _pc_done 1; return 1
  fi
  [[ -n "$_rc_snap" ]] && rm -f -- "$_rc_snap" 2>/dev/null
  printf '%s\n' "$newparent"
  echo "closed ${plan_id}"
  _pc_done 0; return 0
}

# ── Legacy reconciliation (metadata-only; never fabricates) ──────────────────
# _aid_lc_frontmatter_depends <plan_file> — echo the plan's structured
# depends_on_plans entries (one per line), or nothing. Reads ONLY the YAML
# frontmatter (the block bounded by the first two `---` fences); a plan without
# frontmatter or without the key yields empty. Tolerates leading blank lines before
# the opening fence so a stray blank line can never silently drop a declared
# dependency (a D1 gate fail-OPEN). mikefarah-yq safe (`// []`, not the jq-ism `[]?`).
_aid_lc_frontmatter_depends() {
  local pf="$1"
  [[ -f "$pf" ]] || return 0
  awk '
    !started && /^[[:space:]]*$/ { next }                 # skip leading blank lines
    !started && /^---[[:space:]]*$/ { started=1; infm=1; next }  # opening fence
    !started { exit }                                     # first non-blank line is not a fence => no frontmatter
    infm && /^---[[:space:]]*$/ { exit }                  # closing fence
    infm { print }
  ' "$pf" 2>/dev/null \
    | yq -r '.depends_on_plans // [] | .[]' 2>/dev/null || true
}

# aid_lifecycle_ensure_manifest <plan_id> <root> — create + commit a git-tracked
# manifest from the STRICT legacy parse if none exists. NEVER edits the prose
# plan. Returns 0 (present/created), 2 (ambiguous => legacy-unverifiable),
# 3 (plan not found), 4 (user collision on the manifest path), 5 (commit not durable).
aid_lifecycle_ensure_manifest() {
  local plan_id="$1" root="${2:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  # Fast path ONLY when the manifest is already DURABLE on the target branch. A
  # manifest that exists on disk but is NOT yet committed (an interrupted commit,
  # or a hand-created/staged file) must NOT be reported as "ensured" — fall through
  # to the precheck + (re)commit + cat-file verify path below so the durability
  # guarantee actually holds. Mirrors aid_lifecycle_commit_receipt, which has no
  # early return and always re-verifies via a cat-file durability probe. Using
  # existence alone here would report success for a non-durable manifest AND make
  # the staged-collision precheck unreachable whenever the file is present.
  git -C "$root" cat-file -e "$(aid_target_branch):.aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null && return 0
  local plan_file; plan_file="$(aid_lifecycle_plan_file "$plan_id" "$root" || true)"
  [[ -z "$plan_file" ]] && return 3
  # Fail-closed BEFORE creating any artifact: target_branch + no staged collision.
  _aid_lc_precheck_write "$root" ".aid-lifecycle/repo-identity.yaml" ".aid-lifecycle/manifests/${plan_id}.yaml" || return $?
  local parsed rc=0
  parsed="$(aid_lifecycle_parse_legacy_epics "$plan_id" "$plan_file")" || rc=$?
  [[ "$rc" -ne 0 ]] && return 2
  local repo_id; repo_id="$(aid_repo_id "$root")"
  local spsha="sha256:$(sha256sum "$plan_file" 2>/dev/null | cut -c1-64)"
  # Structured dependencies from the plan frontmatter (D1): a real `depends_on_plans`
  # is written into the tracked manifest so the init gate can actually block on it
  # via the normal path (legacy plans without frontmatter => empty, unchanged).
  local deps; deps="$(_aid_lc_frontmatter_depends "$plan_file")"
  mkdir -p "$(dirname "$manifest")"
  # Build to a TEMP first (never write straight over the worktree path), so an
  # existing UNTRACKED manifest can be guarded exactly like the receipt path.
  local tmp; tmp="$(mktemp)"
  {
    echo "schema_version: aid-lifecycle-1.0"
    echo "repo_id: ${repo_id}"
    echo "plan_id: ${plan_id}"
    echo "source_plan_sha: ${spsha}"
    echo "declared_epics:"
    local eid scope
    while read -r eid scope; do
      [[ -z "$eid" ]] && continue
      echo "  - {id: ${eid}, scope: ${scope}}"
    done <<< "$parsed"
    if [[ -z "$deps" ]]; then
      echo "depends_on_plans: []"
    else
      echo "depends_on_plans:"
      local d; while read -r d; do [[ -n "$d" ]] && echo "  - ${d}"; done <<< "$deps"
    fi
  } > "$tmp"
  # Validate (public-safe) BEFORE placing the file into the worktree.
  aid_lifecycle_validate_artifact "$tmp" "plan-lifecycle-manifest.schema.json" || { rm -f "$tmp"; return 2; }
  # Untracked-collision guard (mirror of aid_lifecycle_commit_receipt): a manifest
  # already on disk that is NOT tracked is EITHER our own interrupted-run artifact
  # (byte-identical to the canonical one => safe to recover) OR a foreign user file
  # (differs => refuse, never clobber). A tracked+modified manifest is already
  # refused by the entry precheck above; this guards only the untracked case.
  if [[ -f "$manifest" ]] && ! git -C "$root" ls-files --error-unmatch -- ".aid-lifecycle/manifests/${plan_id}.yaml" >/dev/null 2>&1; then
    if ! cmp -s "$manifest" "$tmp"; then
      rm -f "$tmp"
      echo "lifecycle: refusing — an untracked manifest .aid-lifecycle/manifests/${plan_id}.yaml differs from the canonical manifest (user collision; remove or reconcile it — AID will not overwrite it)" >&2
      return 4
    fi
  fi
  mv "$tmp" "$manifest"
  # Commit the identity + manifest TOGETHER so the repo identity is durable from the
  # moment the plan gets a manifest (survives a clean clone). Isolated commit — the
  # user's index is never touched.
  # Fail-closed: the manifest+identity MUST land as a durable commit. A commit
  # failure returns non-zero (never a silent "ensured") so the caller can stop.
  _aid_lc_isolated_commit "$root" "lifecycle: manifest + identity for ${plan_id}" \
    ".aid-lifecycle/repo-identity.yaml" ".aid-lifecycle/manifests/${plan_id}.yaml" || return 5
  git -C "$root" cat-file -e "$(aid_target_branch):.aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null || return 5
  return 0
}

# _aid_lc_epic_reviewed_head <epic_id> <root> — reviewed head SHA from the EPIC's
# audit provenance (gitignored evidence). Empty if no provenance (=> unverifiable).
_aid_lc_epic_reviewed_head() {
  local epic_id="$1" root="${2:-.}"
  local rep
  # Plan mode: there is no per-EPIC audit report to read — the review happened
  # once for the whole plan. The reviewed head is the plan-final Auditor's.
  if _aid_lc_plan_mode; then
    local pa="${_AID_LC_PLAN_RUN_DIR:-}/audit-report.json"
    [[ -f "$pa" ]] || return 0
    jq -r '.revision.head_sha // .reviewed_head // ""' "$pa" 2>/dev/null || true
    return 0
  fi
  rep="$(ls "${root}/.aid-o/work/evidence/${epic_id}"/*/audit-report.json 2>/dev/null | head -1 || true)"
  [[ -z "$rep" ]] && return 0
  jq -r '.revision.head_sha // .reviewed_head // ""' "$rep" 2>/dev/null || true
}

# _aid_lc_epic_review_status <epic_id> <root> [plan_id] — classify the EPIC's
# audit review from its provenance (gitignored evidence). Echoes one of:
#   accepted     — explicit blocking_findings false/0
#   rejected     — blocking_findings true or a nonzero count
#   unverifiable — status:unverifiable OR blocking_findings absent/null (never
#                  presented as accepted — a merge can be delivered while its
#                  historical review is unverifiable)
#   none         — no audit report at all
# [plan_id], in PLAN MODE only, is the authoritative plan id this call is
# scoped to (D5 lifecycle-audit HIGH follow-up: it MUST come from the
# caller's own trusted parameter, never be guessed from a mutable runtime
# path — see _aid_lc_plan_review_status).
_aid_lc_epic_review_status() {
  local epic_id="$1" root="${2:-.}" plan_id="${3:-}"
  local rep
  # Plan mode: the ONE plan-level verdict stands for every EPIC in the plan —
  # see _aid_lc_plan_review_status and the PLAN MODE header.
  if _aid_lc_plan_mode; then _aid_lc_plan_review_status "$root" "$plan_id"; return 0; fi
  rep="$(ls "${root}/.aid-o/work/evidence/${epic_id}"/*/audit-report.json 2>/dev/null | head -1 || true)"
  [[ -z "$rep" ]] && { echo "none"; return 0; }
  local st bf
  st="$(jq -r '.status // ""' "$rep" 2>/dev/null || true)"
  bf="$(jq -r '.blocking_findings' "$rep" 2>/dev/null || true)"   # direct read (no `// empty`)
  if [[ "$st" == "unverifiable" ]]; then echo "unverifiable"; return 0; fi
  if [[ "$bf" == "false" || "$bf" == "0" ]]; then echo "accepted"; return 0; fi
  if [[ "$bf" == "true" || ( "$bf" =~ ^[0-9]+$ && "$bf" != "0" ) ]]; then echo "rejected"; return 0; fi
  echo "unverifiable"
}

# _aid_lc_find_delivery_merge <epic_id> <root> — echo an UNAMBIGUOUS merge SHA on
# target_branch that MENTIONS this EPIC, or "" (none) / "AMBIGUOUS". The commit
# message only LOCATES candidates (matches both the `feat: complete EPIC <id>`
# pipeline merge and a `merge: <id>` message); binding is CONFIRMED by the caller
# against reviewed-head provenance (ancestor check), never by the message alone.
_aid_lc_find_delivery_merge() {
  local epic_id="$1" root="${2:-.}" tb; tb="$(aid_target_branch)"
  # Plan mode: the only merge reaching the target branch is `merge(plan): <plan_id>`,
  # which names no EPIC id, so the grep below returns empty for EVERY EPIC. The
  # merge SHA is therefore supplied explicitly by the caller.
  if _aid_lc_plan_mode; then printf '%s' "${_AID_LC_PLAN_MERGE_SHA:-}"; return 0; fi
  local shas n
  shas="$(git -C "$root" log "$tb" --merges --grep "${epic_id}" --pretty=%H 2>/dev/null || true)"
  n="$(printf '%s' "$shas" | grep -c . || true)"
  if [[ "$n" -eq 0 ]]; then echo ""; return 0; fi
  if [[ "$n" -gt 1 ]]; then echo "AMBIGUOUS"; return 0; fi
  printf '%s' "$shas"
}

# _aid_lc_can_bind <epic_id> <root> [plan_id] — READ-ONLY delivery-bind check
# (no manifest, no writes). Delivery is bindable when there is an UNAMBIGUOUS
# merge on target_branch AND the EPIC's reviewed-head provenance is an
# ancestor of it — INDEPENDENT of the review verdict (a merge can be
# delivered while its review is unverifiable). Echoes
# "<merge_sha> <reviewed_sha> <review_status>" on success. Returns 0
# (delivery bindable), 1 (not delivered), 2 (ambiguous merge / missing
# reviewed-head provenance => unverifiable delivery, never a guess).
_aid_lc_can_bind() {
  local epic_id="$1" root="${2:-.}" plan_id="${3:-}"
  local merge; merge="$(_aid_lc_find_delivery_merge "$epic_id" "$root")"
  [[ "$merge" == "AMBIGUOUS" ]] && return 2
  [[ -z "$merge" ]] && return 1
  local rhead; rhead="$(_aid_lc_epic_reviewed_head "$epic_id" "$root")"
  [[ -z "$rhead" ]] && return 2   # no reviewed-head provenance -> unverifiable delivery
  git -C "$root" merge-base --is-ancestor "$rhead" "$merge" 2>/dev/null || return 1
  local rs; rs="$(_aid_lc_epic_review_status "$epic_id" "$root" "$plan_id")"
  echo "${merge} ${rhead} ${rs}"
  return 0
}

# aid_lifecycle_bind_delivery <plan_id> <epic_id> <root> — WRITE a verified
# historical delivery binding into the manifest (metadata-only). Returns 0 bound,
# 1 not delivered, 2 unverifiable.
# P068 Step 5: <merge_sha_override> is the 4th, OPTIONAL argument the plan-mode
# caller uses to supply the plan merge commit explicitly (the legacy signature
# accepted no merge SHA at all, which is precisely why the binding path could
# not be reused at the plan boundary). Legacy callers pass three arguments and
# behave identically.
aid_lifecycle_bind_delivery() {
  local plan_id="$1" epic_id="$2" root="${3:-.}" merge_sha_override="${4:-}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  if [[ -n "$merge_sha_override" ]]; then _AID_LC_PLAN_MERGE_SHA="$merge_sha_override"; fi
  local out rc=0; out="$(_aid_lc_can_bind "$epic_id" "$root" "$plan_id")" || rc=$?
  [[ "$rc" -ne 0 ]] && return "$rc"
  local merge rhead rs; read -r merge rhead rs <<< "$out"
  local blockers; blockers="$([[ "$rs" == "accepted" ]] && echo 0 || echo 1)"
  ( cd "$root"
    yq -i ".deliveries.\"${epic_id}\".delivery = \"delivered\" |
           .deliveries.\"${epic_id}\".delivery_sha = \"${merge}\" |
           .deliveries.\"${epic_id}\".reviewed_sha = \"${rhead}\" |
           .deliveries.\"${epic_id}\".review = \"${rs}\" |
           .deliveries.\"${epic_id}\".unresolved_blockers = ${blockers}" \
      ".aid-lifecycle/manifests/${plan_id}.yaml" )
  return 0
}

# aid_lifecycle_plan_reconcile <plan_id> <root> <apply(true|false)>
# Metadata-only: ensures the manifest, attempts a strict historical bind for each
# REQUIRED EPIC, then classifies. --apply commits the manifest updates and, if all
# required are delivered+accepted, writes the closure receipt. Prints the derived
# state + a per-EPIC evidence line. NEVER edits the plan, fabricates a report, or
# closes an in-progress plan.
aid_lifecycle_plan_reconcile() {
  local plan_id="$1" root="${2:-.}" apply="${3:-false}"
  local pf mf
  pf="$(aid_lifecycle_plan_file "$plan_id" "$root" || true)"
  mf="$(aid_manifest_path "$plan_id" "$root")"
  if [[ -z "$pf" && ! -f "$mf" ]]; then echo "state: not_found"; return 0; fi

  # Declared set (manifest if present, else strict legacy parse) — READ-ONLY.
  local declared drc=0
  declared="$(aid_lifecycle_declared_epics "$plan_id" "$root")" || drc=$?
  if [[ "$drc" -eq 2 ]]; then echo "state: legacy-unverifiable (ambiguous EPIC declaration)"; return 0; fi
  if [[ "$drc" -eq 3 ]]; then echo "state: not_found"; return 0; fi

  # --apply first materializes the tracked manifest (metadata-only, never edits
  # the plan). Dry-run touches NOTHING on disk.
  if [[ "$apply" == "true" ]]; then
    _aid_lc_require_target_branch "$root" || { echo "state: reconcile --apply refused — must run on target_branch"; return 3; }
    local ercc=0; aid_lifecycle_ensure_manifest "$plan_id" "$root" >/dev/null 2>&1 || ercc=$?
    if [[ "$ercc" -eq 4 ]]; then echo "state: reconcile --apply refused — manifest has a user staged/unstaged collision"; return 4; fi
    [[ "$ercc" -ne 0 ]] && { echo "state: legacy-unverifiable (manifest could not be created)"; return 2; }
    # Entry precheck BEFORE the per-EPIC bind loop mutates the manifest: a user's
    # staged/unstaged edit to the tracked manifest must not be swept into AID's commit.
    _aid_lc_precheck_write "$root" ".aid-lifecycle/manifests/${plan_id}.yaml" || { echo "state: reconcile --apply refused — manifest has a user staged/unstaged collision"; return 4; }
  fi

  # Classify each REQUIRED EPIC read-only; --apply also records verified bindings.
  local eid scope all_required_ok=true saw_unverifiable=false
  while read -r eid scope; do
    [[ -z "$eid" ]] && continue
    if ! _aid_lc_scope_is_required "$scope"; then echo "  ${eid}: ${scope} (excluded from denominator)"; continue; fi
    # already recorded in the manifest?
    if _aid_lc_delivered "$plan_id" "$eid" "$root" && _aid_lc_reviewed_accepted "$plan_id" "$eid" "$root"; then
      echo "  ${eid}: required delivered+accepted"; continue
    fi
    local crc=0 cbout; cbout="$(_aid_lc_can_bind "$eid" "$root" "$plan_id")" || crc=$?
    if [[ "$crc" -eq 0 ]]; then
      local rs; rs="$(printf '%s' "$cbout" | awk '{print $3}')"
      [[ "$apply" == "true" ]] && aid_lifecycle_bind_delivery "$plan_id" "$eid" "$root" >/dev/null 2>&1 || true
      if [[ "$rs" == "accepted" ]]; then
        echo "  ${eid}: required delivered + review accepted"
      else
        # Honest: the merge IS delivered, but the review is unverifiable/rejected
        # => NOT accepted => plan stays active (never presented as accepted).
        echo "  ${eid}: required DELIVERED but review ${rs} (not accepted)"; all_required_ok=false; saw_unverifiable=true
      fi
    elif [[ "$crc" -eq 2 ]]; then
      echo "  ${eid}: required UNVERIFIABLE delivery (ambiguous merge / no reviewed-head provenance)"; all_required_ok=false; saw_unverifiable=true
    else
      echo "  ${eid}: required NOT delivered"; all_required_ok=false
    fi
  done <<< "$declared"

  if [[ "$apply" == "true" ]]; then
    if ! _aid_lc_isolated_commit "$root" "lifecycle: delivery bindings for ${plan_id} (reconcile)" ".aid-lifecycle/manifests/${plan_id}.yaml"; then
      echo "state: reconcile — delivery bindings NOT committed (recoverable — re-run --apply)"; return 5
    fi
    local st rcv_rc=0; st="$(aid_plan_closure_state "$plan_id" "$root")"
    if [[ "$st" == "delivered-but-unreconciled" || "$st" == "closing_pending_commit" ]]; then
      if aid_lifecycle_commit_receipt "$plan_id" "$root" >/dev/null 2>&1; then st="closed"; else rcv_rc=5; fi
    fi
    echo "state: ${st}"
    # A receipt-commit failure must NOT be reported as success: propagate non-zero
    # (the stdout state line stays honest — never "closed" when the receipt failed).
    # NB: a proper if/fi (not `[[ ]] && { }`) so a clean run returns 0, not the
    # falsy exit status of the test when rcv_rc==0.
    if [[ "$rcv_rc" -ne 0 ]]; then
      echo "reconcile: closure receipt NOT committed for ${plan_id} (recoverable — re-run --apply)" >&2
      return 5
    fi
    return 0
  else
    # Dry-run: derive the would-be state without touching disk.
    if [[ "$all_required_ok" == "true" ]]; then echo "state: delivered-but-unreconciled (would close on --apply)"
    elif [[ "$saw_unverifiable" == "true" ]]; then echo "state: active (some required EPICs unverifiable — see above)"
    else echo "state: active"; fi
  fi
}

# aid_lifecycle_record_delivery <epic_id> <root>
# THE post-merge hook (constraint #2): run on target_branch IMMEDIATELY AFTER an
# EPIC's `git merge task/<epic>/main`. It is the single, named, tested call path
# that (a) ensures the plan's manifest exists, (b) records THIS EPIC's delivery +
# review provenance from the just-completed merge (isolated commit), and (c) if
# that was the last required EPIC now delivered + review-accepted, writes the
# closure receipt (=> closed). Metadata-only: never edits the plan or the merge,
# never touches the user's index. Idempotent. Does NOT run pre-merge / on a task
# branch (constraint #1 — pre-merge plan-close only verifies + keeps the marker).
aid_lifecycle_record_delivery() {
  local epic_id="$1" root="${2:-.}"
  [[ "$epic_id" =~ ^E-([0-9]+) ]] || { echo "record-delivery: cannot derive plan from ${epic_id}" >&2; return 1; }
  local plan_id="P${BASH_REMATCH[1]}"
  # POST-MERGE only: refuse on any non-target branch, BEFORE touching anything.
  _aid_lc_require_target_branch "$root" || return 3
  # Propagate ANY non-zero from ensure_manifest — a manifest that is not durably in
  # place (ambiguous parse, not found, commit failure, OR a user staged/unstaged
  # collision refused by the precheck) must NOT fall through into bind/commit.
  local mrc=0; aid_lifecycle_ensure_manifest "$plan_id" "$root" >/dev/null 2>&1 || mrc=$?
  if [[ "$mrc" -ne 0 ]]; then
    case "$mrc" in
      2) echo "record-delivery: ${plan_id} legacy-unverifiable (ambiguous EPIC declaration)" >&2 ;;
      3) echo "record-delivery: ${plan_id} plan not found" >&2 ;;
      4) echo "record-delivery: ${plan_id} manifest has a user staged/unstaged collision — refusing (unstage/commit/discard your edit)" >&2 ;;
      *) echo "record-delivery: ${plan_id} manifest not ensured durably (rc=${mrc})" >&2 ;;
    esac
    return "$mrc"
  fi
  # Entry precheck on the manifest BEFORE bind_delivery mutates it: a user's UNSTAGED
  # edit to the (already durable) tracked manifest must not be merged into AID's
  # binding and committed. (ensure_manifest early-returns for a durable manifest
  # without re-prechecking, so this is the guard that catches that case.)
  _aid_lc_precheck_write "$root" ".aid-lifecycle/manifests/${plan_id}.yaml" || return $?
  local brc=0; aid_lifecycle_bind_delivery "$plan_id" "$epic_id" "$root" >/dev/null 2>&1 || brc=$?
  # Durably commit the binding; a commit failure is surfaced (non-zero), never masked.
  if ! _aid_lc_isolated_commit "$root" "lifecycle: delivery ${epic_id} (post-merge)" ".aid-lifecycle/manifests/${plan_id}.yaml"; then
    echo "record-delivery ${epic_id}: manifest binding not committed (recoverable — re-run on ${plan_id})" >&2; return 5
  fi
  local st rcv_rc=0; st="$(aid_plan_closure_state "$plan_id" "$root")"
  if [[ "$st" == "delivered-but-unreconciled" || "$st" == "closing_pending_commit" ]]; then
    if aid_lifecycle_commit_receipt "$plan_id" "$root" >/dev/null 2>&1; then
      st="$(aid_plan_closure_state "$plan_id" "$root")"
    else
      rcv_rc=5
    fi
  fi
  local dtag; case "$brc" in 0) dtag="delivered";; 2) dtag="unverifiable";; *) dtag="not-delivered";; esac
  echo "record-delivery ${epic_id}: delivery=${dtag} plan=${plan_id} state=${st}"
  # A receipt-commit failure on the last required EPIC must NOT return success —
  # the state line above stays honest (never "closed"), and we surface non-zero so
  # automation does not treat an unfinished closure as done.
  if [[ "$rcv_rc" -ne 0 ]]; then
    echo "record-delivery ${epic_id}: closure receipt NOT committed for ${plan_id} (recoverable — re-run on ${plan_id})" >&2
    return 5
  fi
  return 0
}

# =============================================================================
# aid_lifecycle_plan_merge_bind <plan_id> <root> <merge_sha> <run_dir_abs>
#                               [<epic_id>=<abandoned|superseded> ...]
#
# P068 E-068-1_2 Step 5, stage 2 — the ONE post-merge lifecycle pass of a
# `plan_branch` plan. Runs AFTER the plan merge commit is published on the
# target branch, and writes, in a SINGLE commit:
#
#   (a) the CF1 re-scope — every abandoned/superseded EPIC's `scope` rewritten
#       so aid_plan_closure_state stops counting it in the required set. This is
#       the FIRST point where the write is legal: _aid_lc_require_target_branch
#       refuses lifecycle writes off the target branch and `epic-complete` runs
#       on a task branch, which is why P064 could only record the terminal
#       status in its runtime manifest. The PM's REASON is deliberately NOT
#       written here — the manifest schema is additionalProperties:false and
#       aid_lifecycle_publicsafe_check rejects a free-text `reason` key; the
#       reason lives in the runtime plan-state and the operation log.
#   (b) the delivery bindings — every non-abandoned, non-superseded declared
#       EPIC bound with delivery_sha = the plan merge commit, and the review
#       verdict taken from the PLAN-level audit-report.json / curator-report.json
#       in <run_dir_abs>. In the new model the review genuinely happens once for
#       the whole plan, so a per-EPIC verdict derived from a per-EPIC audit
#       report no longer exists to be read.
#
# ONE commit for both, so the closure denominator and the deliveries can never
# disagree. It does NOT write the receipt: that is Step 6's (`plan-close`), so a
# single owner writes each artifact. This function makes the plan CLOSABLE.
#
# Idempotent: re-running produces the identical manifest, and the plan-mode
# isolated commit is a documented no-op when the tree is unchanged — so a crash
# between the publish and this pass is resolved by simply re-running it.
#
# Returns: 0 written (or already correct), 1 manifest/validation failure,
# 5 commit not durable (recoverable — re-run).
# =============================================================================
aid_lifecycle_plan_merge_bind() {
  local plan_id="$1" root="${2:-.}" merge_sha="$3" run_dir_abs="$4"; shift 4
  local -a rescope=("$@")
  local relpath=".aid-lifecycle/manifests/${plan_id}.yaml"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"

  if [[ -z "$merge_sha" ]]; then
    echo "lifecycle: plan-merge-bind requires the published merge SHA" >&2; return 1
  fi
  if [[ ! -f "$manifest" ]]; then
    echo "lifecycle: plan-merge-bind: no manifest at ${relpath} — plan-start ensures it; refusing to fabricate one after the merge" >&2
    return 1
  fi

  # The CAS base is the LIVE target head, not the merge commit itself — that is
  # what makes a resumed run converge instead of failing. On a first pass the
  # live head IS the merge commit; on a re-run after a crash it is the lifecycle
  # commit this function already made, and the rebuilt tree then matches it and
  # the commit is a documented no-op. Either way the merge must be published:
  # a target head that does not CONTAIN the merge means this is not stage 2 of
  # anything, and binding deliveries to an unpublished merge would be a lie.
  # CP2 M3 (2026-07-26, corrected): every mutation below rewrites the TRACKED
  # file .aid-lifecycle/manifests/<plan>.yaml. A failure part-way used to leave
  # it dirty, and the printed remedy ("re-run to converge") was then refused by
  # the caller's clean-worktree precondition — a deadlock after an ALREADY
  # published merge. The fix belongs here, not in a blanket exemption from that
  # guard: snapshot the file's exact bytes on entry and restore them on every
  # failure path, so a failed stage 2 is byte-identical to never having run and
  # the re-run converges. Success keeps its edits (they are the deliverable).
  local _lc_snap=""
  _lc_snap="$(mktemp 2>/dev/null)" || _lc_snap=""
  [[ -n "$_lc_snap" ]] && cp -p -- "$manifest" "$_lc_snap" 2>/dev/null

  local tb_live; tb_live="$(git -C "$root" rev-parse --verify --quiet "refs/heads/$(aid_target_branch)" 2>/dev/null || true)"
  if [[ -z "$tb_live" ]] || ! git -C "$root" merge-base --is-ancestor "$merge_sha" "$tb_live" 2>/dev/null; then
    echo "lifecycle: plan-merge-bind: ${merge_sha} is not contained in $(aid_target_branch) (${tb_live:-<absent>}) — the merge is not published; refusing to bind deliveries to it" >&2
    return 1
  fi

  # _lc_rollback — put the manifest back exactly as found, then drop the snapshot.
  _lc_rollback() {
    [[ -n "$_lc_snap" && -f "$_lc_snap" ]] && cp -p -- "$_lc_snap" "$manifest" 2>/dev/null
    [[ -n "$_lc_snap" ]] && rm -f -- "$_lc_snap" 2>/dev/null
    _lc_snap=""
    return 0
  }

  aid_lc_plan_mode_begin "$merge_sha" "$run_dir_abs" "$tb_live"

  # Entry precheck (the staged/unstaged user-collision half is fully active in
  # plan mode; only the branch assertion is satisfied by construction).
  local prc=0; _aid_lc_precheck_write "$root" "$relpath" || prc=$?
  if [[ "$prc" -ne 0 ]]; then aid_lc_plan_mode_end; _lc_rollback; return "$prc"; fi

  # ── (a) CF1 re-scope ─────────────────────────────────────────────────────
  local spec eid newscope
  for spec in ${rescope[@]+"${rescope[@]}"}; do
    [[ "$spec" == *=* ]] || continue
    eid="${spec%%=*}"; newscope="${spec#*=}"
    case "$newscope" in
      abandoned|superseded) ;;
      *) echo "lifecycle: plan-merge-bind: refusing an unknown re-scope '${newscope}' for ${eid}" >&2
         aid_lc_plan_mode_end; _lc_rollback; return 1 ;;
    esac
    ( cd "$root" && yq -i "(.declared_epics[] | select(.id == \"${eid}\") | .scope) = \"${newscope}\"" "$relpath" ) \
      || { echo "lifecycle: plan-merge-bind: could not re-scope ${eid} to ${newscope}" >&2; aid_lc_plan_mode_end; _lc_rollback; return 1; }
  done

  # ── (b) delivery bindings for every EPIC still in the required/backlog set ─
  local scope drc=0 declared=""
  declared="$(aid_lifecycle_declared_epics "$plan_id" "$root")" || drc=$?
  if [[ "$drc" -ne 0 ]]; then
    echo "lifecycle: plan-merge-bind: cannot read the declared EPIC set for ${plan_id} (rc=${drc})" >&2
    aid_lc_plan_mode_end; _lc_rollback; return 1
  fi
  local unbound=""
  while read -r eid scope; do
    [[ -z "$eid" ]] && continue
    case "$scope" in abandoned|superseded) continue ;; esac
    local brc=0
    aid_lifecycle_bind_delivery "$plan_id" "$eid" "$root" "$merge_sha" >/dev/null 2>&1 || brc=$?
    [[ "$brc" -ne 0 ]] && unbound="${unbound:+${unbound}, }${eid}(rc=${brc})"
  done <<< "$declared"
  if [[ -n "$unbound" ]]; then
    echo "lifecycle: plan-merge-bind: could not bind ${unbound} — the plan-final review evidence in ${run_dir_abs} does not support a binding for them" >&2
    aid_lc_plan_mode_end; _lc_rollback; return 1
  fi

  # Validate BEFORE the commit — fail-closed, exactly like every other lifecycle
  # write. A widened `scope` that the schema rejects must never reach the tree.
  if ! aid_lifecycle_validate_artifact "$manifest" "plan-lifecycle-manifest.schema.json"; then
    aid_lc_plan_mode_end; _lc_rollback; return 1
  fi

  local crc=0
  _aid_lc_isolated_commit "$root" "lifecycle: deliveries + scope for ${plan_id} (plan merge)" "$relpath" || crc=$?
  local newparent="${_AID_LC_PLAN_PARENT}"
  aid_lc_plan_mode_end
  if [[ "$crc" -ne 0 ]]; then
    echo "lifecycle: plan-merge-bind: the delivery bindings for ${plan_id} were NOT committed (rc=${crc}) — the merge stands, the manifest is restored to its pre-run bytes; re-run to converge." >&2
    _lc_rollback; return 5
  fi
  if ! git -C "$root" cat-file -e "$(aid_target_branch):${relpath}" 2>/dev/null; then
    _lc_rollback; return 5
  fi
  [[ -n "$_lc_snap" ]] && rm -f -- "$_lc_snap" 2>/dev/null
  printf '%s\n' "$newparent"
  return 0
}

# ── Convenience: does a plan even exist here? (for not_found result) ──────────
# aid_lifecycle_plan_file <plan_id> [root] — echo the .aid-o plan file path if a
# single match exists, else empty. (Active plans live in gitignored .aid-o/plans/.)
aid_lifecycle_plan_file() {
  local plan_id="$1" root="${2:-.}"
  local hit
  hit="$(ls "${root}/.aid-o/plans/${plan_id}"-*.md "${root}/.aid-o/plans/archive/${plan_id}"-*.md 2>/dev/null | head -1 || true)"
  [[ -n "$hit" ]] && echo "$hit"
  return 0   # never non-zero: a caller under `set -e` must not abort when absent
}

# ── Declared EPIC set (denominator source) ───────────────────────────────────
# aid_lifecycle_declared_epics <plan_id> [root]
# Prints "<epic_id> <scope>" lines (ordered). Source of truth is the git-tracked
# manifest if present; otherwise the STRICT legacy parse of the prose plan.
# Return codes: 0 ok; 2 ambiguous (=> legacy-unverifiable); 3 plan not found.
aid_lifecycle_declared_epics() {
  local plan_id="$1" root="${2:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  if [[ -f "$manifest" ]]; then
    yq -r '.declared_epics[] | "\(.id) \(.scope)"' "$manifest" 2>/dev/null && return 0
    return 2
  fi
  local plan_file; plan_file="$(aid_lifecycle_plan_file "$plan_id" "$root")"
  [[ -z "$plan_file" ]] && return 3
  aid_lifecycle_parse_legacy_epics "$plan_id" "$plan_file"   # 0 ok / 2 ambiguous
}

# ── The closure denominator (CF1) ────────────────────────────────────────────
# _aid_lc_scope_is_required <scope> — 0 iff this scope counts towards closure.
#
# The required set is `required` and NOTHING else. Before P068 the only other
# value was `backlog`; Step 5 adds `abandoned` and `superseded`, written by
# plan-merge-to-main in the same commit as the delivery bindings for EPICs the
# PM terminated without delivery. Making the predicate a NAMED function rather
# than an inline `[[ "$scope" == "required" ]]` is the point: "which scopes are
# excluded from the denominator" is now a real rule with more than one excluded
# value, and it must read identically everywhere it is applied.
_aid_lc_scope_is_required() {
  [[ "${1:-}" == "required" ]]
}

# ── Per-EPIC predicates (manifest-recorded; forward path) ────────────────────
# delivered = a bound delivery_sha exists (Phase-2 post-merge record).
# reviewed-and-accepted = recorded verdict 'pass' AND 0 unresolved blockers
# (Phase-1 record). Legacy plans have no manifest deliveries => predicates fail
# => plan stays `active` (correct); the historical-fallback recording that lets
# a legacy plan close is aid-plan-reconcile (commit 3).
# delivered = a bound delivery_sha exists in the manifest (delivery: delivered).
_aid_lc_delivered() {
  local plan_id="$1" epic_id="$2" root="${3:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local sha; sha="$(yq -r ".deliveries.\"${epic_id}\".delivery_sha // \"\"" "$manifest" 2>/dev/null || true)"
  [[ -n "$sha" && "$sha" != "null" ]]
}
# reviewed-and-accepted = the manifest records review: accepted (an unverifiable
# or rejected review is NEVER accepted, so the plan stays active).
_aid_lc_reviewed_accepted() {
  local plan_id="$1" epic_id="$2" root="${3:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local review; review="$(yq -r ".deliveries.\"${epic_id}\".review // \"\"" "$manifest" 2>/dev/null || true)"
  [[ "$review" == "accepted" ]]
}

# ── Receipt durability (committed + reachable from target_branch) ─────────────
# A `closed` state requires the receipt to be COMMITTED and reachable from the
# configured target_branch — a staged/uncommitted receipt is NOT closed. The
# receipt must also pass the public-safe contract.
aid_lifecycle_receipt_durable() {
  local plan_id="$1" root="${2:-.}"
  local receipt; receipt="$(aid_receipt_path "$plan_id" "$root")"
  [[ -f "$receipt" ]] || return 1
  aid_lifecycle_publicsafe_check "$receipt" >/dev/null 2>&1 || return 1
  local tb relpath; tb="$(aid_target_branch)"
  relpath=".aid-lifecycle/receipts/${plan_id}.yaml"
  # Committed on target_branch? (content resolvable at that ref)
  git -C "$root" cat-file -e "${tb}:${relpath}" 2>/dev/null
}

# ── Canonical closure-state resolver ─────────────────────────────────────────
# aid_plan_closure_state <plan_id> [root] — derive the lifecycle state from the
# committed receipt (authoritative when present) + manifest + evidence. Prints
# one of: not_found | legacy-unverifiable | active | delivered-but-unreconciled
#         | closing_pending_commit | closed
aid_plan_closure_state() {
  local plan_id="$1" root="${2:-.}"
  local receipt manifest plan_file
  receipt="$(aid_receipt_path "$plan_id" "$root")"
  manifest="$(aid_manifest_path "$plan_id" "$root")"
  plan_file="$(aid_lifecycle_plan_file "$plan_id" "$root" || true)"

  # A durable ROLLED-BACK record is authoritative and comes FIRST — before the
  # receipt, before deliveries. A rolled-back plan still carries its delivery
  # bindings (they record what WAS merged and then reverted), so evaluating
  # deliveries first would answer `delivered-but-unreconciled` for a plan the
  # git ledger plainly marks as rolled back: the clean clone would read the YAML
  # correctly and the API would still contradict it.
  if command -v yq >/dev/null 2>&1; then
    # ONLY the committed copy on the target branch may establish `rolled_back`.
    # The worktree file is a working copy: anyone can set `status: rolled_back`
    # in it without committing anything, and a resolver that believed it would
    # report a rollback the ledger knows nothing about — the same two-truths
    # failure, just pointing the other way. The plan-mode plumbing also restores
    # the worktree file after publishing, so a genuine rollback leaves no trace
    # there anyway. The ledger is the authority; the worktree is not consulted.
    local _cs_rel=".aid-lifecycle/manifests/${plan_id}.yaml"
    local _cs_tb; _cs_tb="$(aid_target_branch)"
    local _cs_status
    _cs_status="$(git -C "$root" show "${_cs_tb}:${_cs_rel}" 2>/dev/null | yq -r '.status // ""' 2>/dev/null || true)"
    if [[ "$_cs_status" == "rolled_back" ]]; then echo "rolled_back"; return 0; fi
  fi
  # A COMMITTED + reachable receipt is authoritative -> closed.
  if [[ -f "$receipt" ]] && aid_lifecycle_receipt_durable "$plan_id" "$root"; then echo "closed"; return 0; fi
  # Nothing at all -> not_found (a plan-number gap has no lifecycle meaning).
  if [[ -z "$plan_file" && ! -f "$manifest" ]]; then echo "not_found"; return 0; fi

  local declared="" drc=0
  declared="$(aid_lifecycle_declared_epics "$plan_id" "$root")" || drc=$?
  if [[ "$drc" -eq 2 ]]; then echo "legacy-unverifiable"; return 0; fi
  if [[ "$drc" -eq 3 ]]; then echo "not_found"; return 0; fi

  # Every REQUIRED epic must be delivered + reviewed-accepted for closability.
  local eid scope all_ok=true
  while read -r eid scope; do
    _aid_lc_scope_is_required "$scope" || continue
    if ! _aid_lc_delivered "$plan_id" "$eid" "$root" || ! _aid_lc_reviewed_accepted "$plan_id" "$eid" "$root"; then
      all_ok=false; break
    fi
  done <<< "$declared"

  if [[ "$all_ok" != "true" ]]; then
    # Not closable. A stale UNCOMMITTED receipt (never durable) is ignored, not
    # treated as pending — the plan is simply active.
    echo "active"; return 0
  fi
  # Closable. An uncommitted receipt on disk means a close is mid-flight
  # (interrupted before the commit) -> recoverable pending; else ready to close.
  if [[ -f "$receipt" ]]; then echo "closing_pending_commit"; else echo "delivered-but-unreconciled"; fi
}
