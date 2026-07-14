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

# ── Paths ────────────────────────────────────────────────────────────────────
aid_lifecycle_dir()   { echo "${1:-.}/.aid-lifecycle"; }
aid_identity_path()   { echo "$(aid_lifecycle_dir "${1:-.}")/repo-identity.yaml"; }
aid_manifest_path()   { echo "$(aid_lifecycle_dir "${2:-.}")/manifests/${1}.yaml"; }
aid_receipt_path()    { echo "$(aid_lifecycle_dir "${2:-.}")/receipts/${1}.yaml"; }

# _aid_lc_require_target_branch <root> — 0 iff HEAD is on the configured
# target_branch. NO lifecycle tracked write may happen on any other branch
# (constraint: before merge there are NO tracked lifecycle commits). Callers must
# check this BEFORE writing any worktree lifecycle artifact.
_aid_lc_require_target_branch() {
  local root="${1:-.}" cur tb
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

# aid_lifecycle_plan_close <plan_id> <root> — forward-path close. Requires the
# manifest to show EVERY required EPIC delivered + reviewed-accepted; then writes
# + commits the receipt (=> closed). Fail-closed: any missing predicate => no
# receipt, non-zero.
aid_lifecycle_plan_close() {
  local plan_id="$1" root="${2:-.}"
  local st; st="$(aid_plan_closure_state "$plan_id" "$root")"
  case "$st" in
    closed) echo "already closed" >&2; return 0 ;;
    not_found) echo "plan-close: ${plan_id} not found" >&2; return 3 ;;
    legacy-unverifiable) echo "plan-close: ${plan_id} is legacy-unverifiable (run plan-reconcile)" >&2; return 1 ;;
    active) echo "plan-close: ${plan_id} is active — not all required EPICs are delivered + reviewed-accepted" >&2; return 1 ;;
  esac
  # delivered-but-unreconciled or closing_pending_commit -> write/commit receipt.
  aid_lifecycle_commit_receipt "$plan_id" "$root" || { echo "plan-close: receipt not committed/reachable for ${plan_id}" >&2; return 1; }
  echo "closed ${plan_id}"
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
  rep="$(ls "${root}/.aid-o/work/evidence/${epic_id}"/*/audit-report.json 2>/dev/null | head -1 || true)"
  [[ -z "$rep" ]] && return 0
  jq -r '.revision.head_sha // .reviewed_head // ""' "$rep" 2>/dev/null || true
}

# _aid_lc_epic_review_status <epic_id> <root> — classify the EPIC's audit review
# from its provenance (gitignored evidence). Echoes one of:
#   accepted     — explicit blocking_findings false/0
#   rejected     — blocking_findings true or a nonzero count
#   unverifiable — status:unverifiable OR blocking_findings absent/null (never
#                  presented as accepted — a merge can be delivered while its
#                  historical review is unverifiable)
#   none         — no audit report at all
_aid_lc_epic_review_status() {
  local epic_id="$1" root="${2:-.}"
  local rep
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
  local shas n
  shas="$(git -C "$root" log "$tb" --merges --grep "${epic_id}" --pretty=%H 2>/dev/null || true)"
  n="$(printf '%s' "$shas" | grep -c . || true)"
  if [[ "$n" -eq 0 ]]; then echo ""; return 0; fi
  if [[ "$n" -gt 1 ]]; then echo "AMBIGUOUS"; return 0; fi
  printf '%s' "$shas"
}

# _aid_lc_can_bind <epic_id> <root> — READ-ONLY delivery-bind check (no manifest,
# no writes). Delivery is bindable when there is an UNAMBIGUOUS merge on
# target_branch AND the EPIC's reviewed-head provenance is an ancestor of it —
# INDEPENDENT of the review verdict (a merge can be delivered while its review is
# unverifiable). Echoes "<merge_sha> <reviewed_sha> <review_status>" on success.
# Returns 0 (delivery bindable), 1 (not delivered), 2 (ambiguous merge / missing
# reviewed-head provenance => unverifiable delivery, never a guess).
_aid_lc_can_bind() {
  local epic_id="$1" root="${2:-.}"
  local merge; merge="$(_aid_lc_find_delivery_merge "$epic_id" "$root")"
  [[ "$merge" == "AMBIGUOUS" ]] && return 2
  [[ -z "$merge" ]] && return 1
  local rhead; rhead="$(_aid_lc_epic_reviewed_head "$epic_id" "$root")"
  [[ -z "$rhead" ]] && return 2   # no reviewed-head provenance -> unverifiable delivery
  git -C "$root" merge-base --is-ancestor "$rhead" "$merge" 2>/dev/null || return 1
  local rs; rs="$(_aid_lc_epic_review_status "$epic_id" "$root")"
  echo "${merge} ${rhead} ${rs}"
  return 0
}

# aid_lifecycle_bind_delivery <plan_id> <epic_id> <root> — WRITE a verified
# historical delivery binding into the manifest (metadata-only). Returns 0 bound,
# 1 not delivered, 2 unverifiable.
aid_lifecycle_bind_delivery() {
  local plan_id="$1" epic_id="$2" root="${3:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local out rc=0; out="$(_aid_lc_can_bind "$epic_id" "$root")" || rc=$?
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
    if [[ "$scope" != "required" ]]; then echo "  ${eid}: ${scope} (excluded from denominator)"; continue; fi
    # already recorded in the manifest?
    if _aid_lc_delivered "$plan_id" "$eid" "$root" && _aid_lc_reviewed_accepted "$plan_id" "$eid" "$root"; then
      echo "  ${eid}: required delivered+accepted"; continue
    fi
    local crc=0 cbout; cbout="$(_aid_lc_can_bind "$eid" "$root")" || crc=$?
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
    [[ "$scope" == "required" ]] || continue
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
