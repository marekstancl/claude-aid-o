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
# (additionalProperties:false rejects unknown fields). Requires python3 +
# jsonschema; if unavailable, returns 0 (best-effort — the publicsafe value/key
# net still runs independently). Exit 1 on a real schema violation.
aid_lifecycle_schema_validate() {
  local yaml_f="$1" schema_base="$2"
  local schema_f; schema_f="$(aid_lifecycle_schema_dir)/${schema_base}"
  [[ -f "$yaml_f" ]] || { echo "schema: file not found: $yaml_f" >&2; return 1; }
  [[ -f "$schema_f" ]] || { echo "schema: schema not found: $schema_f" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -c 'import jsonschema' >/dev/null 2>&1 || return 0
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
_aid_lc_delivered() {
  local plan_id="$1" epic_id="$2" root="${3:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local sha; sha="$(yq -r ".deliveries.\"${epic_id}\".delivery_sha // \"\"" "$manifest" 2>/dev/null || true)"
  [[ -n "$sha" && "$sha" != "null" ]]
}
_aid_lc_reviewed_accepted() {
  local plan_id="$1" epic_id="$2" root="${3:-.}"
  local manifest; manifest="$(aid_manifest_path "$plan_id" "$root")"
  [[ -f "$manifest" ]] || return 1
  local verdict blockers
  verdict="$(yq -r ".deliveries.\"${epic_id}\".reviewed_verdict // \"\"" "$manifest" 2>/dev/null || true)"
  blockers="$(yq -r ".deliveries.\"${epic_id}\".unresolved_blockers // 1" "$manifest" 2>/dev/null || echo 1)"
  [[ "$verdict" == "pass" && "$blockers" == "0" ]]
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

  # Committed receipt is authoritative.
  if [[ -f "$receipt" ]]; then
    if aid_lifecycle_receipt_durable "$plan_id" "$root"; then echo "closed"; else echo "closing_pending_commit"; fi
    return 0
  fi
  # Nothing at all -> not_found (a plan-number gap has no lifecycle meaning).
  if [[ -z "$plan_file" && ! -f "$manifest" ]]; then echo "not_found"; return 0; fi

  local declared="" drc=0
  declared="$(aid_lifecycle_declared_epics "$plan_id" "$root")" || drc=$?
  if [[ "$drc" -eq 2 ]]; then echo "legacy-unverifiable"; return 0; fi
  if [[ "$drc" -eq 3 ]]; then echo "not_found"; return 0; fi

  # Every REQUIRED epic must be delivered + reviewed-accepted.
  local eid scope all_ok=true
  while read -r eid scope; do
    [[ "$scope" == "required" ]] || continue
    if ! _aid_lc_delivered "$plan_id" "$eid" "$root" || ! _aid_lc_reviewed_accepted "$plan_id" "$eid" "$root"; then
      all_ok=false; break
    fi
  done <<< "$declared"

  if [[ "$all_ok" == "true" ]]; then echo "delivered-but-unreconciled"; else echo "active"; fi
}
