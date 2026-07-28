#!/usr/bin/env bash
# =============================================================================
# aid-c0-plan-review.sh — C0 Cross-Provider PLAN Review Bridge (P065, E-065-7_7 Step 18)
#
# Plan-time analogue of aid-c3-dispatch.sh: runs a FRESH, isolated `codex exec`
# over the FINAL plan (before it is turned into EPICs) and emits a SEPARATE
# `c0-plan-review.json` artifact — NEVER a C3 `audit_report`. It reuses ONLY the
# C3 transport (`_run_codex_isolated`, sourced from aid-c3-dispatch.sh, which
# carries no C3-specific coupling — see that function's header comment). The
# artifact, schema, prompt, and manifest are C0's own: a C3 pass can never stand
# in for a C0 pass and vice-versa.
#
# Gated to high-risk plans: `dispatch` skips Codex entirely for a low/docs-risk
# plan (`c0_codex_review: skipped(profile)`, exit 0 — a legitimate, expected
# outcome, not a failure) unless AID_C0_FORCE_REVIEW is set (PM/profile
# promotion). For a high-risk plan, Codex unavailable/timeout/invalid always
# yields `status: unverifiable` — never a false PASS, and dispatch exits 2.
#
# ---------------------------------------------------------------------------
# build-manifest <plan_file> <evidence_dir>
# ---------------------------------------------------------------------------
# <evidence_dir> is the PLAN-ID evidence ROOT — `.aid-o/work/evidence/<plan_id>/`
# — the SAME directory `aid-c0-contract.sh` writes `c0/plan-graph.json` +
# `c0/contract-manifest.json` into, and `aid-cp1-gate.sh` reads
# `cp1-deep/cp1-lens-L{1,2,3}-*.md` + `cp1-deep/cp1-adjudicator.md` from. This
# step writes ONLY under `<evidence_dir>/c0/codex/` (its own subtree) and the
# canonical `<evidence_dir>/c0-plan-review.json` — it never touches those
# sibling files, only HASHES them (when present) as manifest inputs.
#
# Writes `<evidence_dir>/c0/codex/audit-input-manifest.json`: a canonical hash
# manifest of {plan_file, contracts the plan cites, plan-graph, existing C0
# evidence} + `reviewed_plan_hash` (sha256 of the plan file) + `reviewed_head`
# (current git HEAD) + `input_hash` (canonical-JSON sha256 over the sorted file
# set). Reuses the registered `audit_input_manifest` artifact_type (validated by
# aid-protocol-validate.sh, same as C3's manifest) with a C0-specific
# `c0_plan_review_input` payload nested inside — additionalProperties is NOT
# restricted on that schema, so this is a legitimate, validator-clean extension.
#
# ---------------------------------------------------------------------------
# dispatch <evidence_dir>
# ---------------------------------------------------------------------------
# Reads the manifest's recorded risk_profile. Low/docs (and no
# AID_C0_FORCE_REVIEW override) → writes a `outcome: "skipped(profile)"`
# c0-plan-review.json and exits 0 WITHOUT probing or invoking Codex. Otherwise:
# probes cross_provider availability for THIS run (never cached, mirrors C3),
# renders the sealed C0 prompt deterministically via aid-render-prompt.sh,
# invokes the real Codex CLI (read-only, fresh process, via the shared
# `_run_codex_isolated`) and captures raw output + provenance into
# `<evidence_dir>/c0/codex/c0-dispatch.json`. Validates the raw response with an
# explicit jq gate (mirrors C3's `_validate_response`, C0 key-shape), binds it
# to the manifest (reviewed_plan_hash / input_manifest_hash / reviewed_head),
# normalizes findings (fingerprint via aid-finding-fingerprint.sh,
# occurrence_id `c0-<plan_id>-<n>`), and writes the canonical
# `<evidence_dir>/c0-plan-review.json`. Every failure path fails CLOSED to
# `status: unverifiable` (never a false pass). Exit 0 iff Codex genuinely
# dispatched (outcome=dispatched); exit 2 for every other outcome, including
# skip-gate-adjacent errors — but the skip path itself (low/docs, no override)
# is NOT an error and exits 0.
#
# ---------------------------------------------------------------------------
# verify [--reference] <evidence_dir>
# ---------------------------------------------------------------------------
# Re-checks the codex-derived provenance chain (real session, stream hash,
# raw-binding) and proves `c0-plan-review.json` is a faithful, deterministic
# transform of Codex's raw response — mirrors aid-c3-dispatch.sh `verify`.
# `--reference` checks freshness against the manifest's captured `reviewed_head`
# (committed historical fixtures) instead of the live HEAD.
#
# Exit codes (same convention as aid-c3-dispatch.sh):
#   0 — success (manifest written + protocol-validated / dispatched + verified /
#       skipped(profile) is also exit 0 — a legitimate non-dispatch outcome)
#   1 — PRECONDITION FAIL (usage, non-git dir, unreadable plan file, missing
#       manifest, emitted manifest failed protocol validation)
#   2 — dispatch non-dispatched outcome / verify NOT-verified (fail-closed)
#
# Environment (optional):
#   AID_C0_FORCE_REVIEW        — PM/profile-promotion override: non-empty forces
#                                 the Codex plan review to run even when the
#                                 manifest's recorded risk_profile is not "high".
#   AID_C0_INDEPENDENCE_BIN     — override for the cross_provider pre-check binary
#                                 (test seam; default aid-audit-independence.sh).
#   AID_C0_RENDER_BIN           — override for the prompt renderer (test seam;
#                                 default aid-render-prompt.sh).
#   AID_C0_CODEX_MODEL          — override for the `-m` model arg passed to codex
#                                 (default: same as C3's CODEX_MODEL default).
#
# **Last Updated:** 2026-07-25
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Reuse the shared transport + primitives from aid-c3-dispatch.sh. The guard
# at the bottom of that file (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`) means
# sourcing it here NEVER runs C3's own CLI dispatcher — only its function/
# variable definitions are pulled in: _fail, _sha256_file, _sha256_str,
# _path_is_within, _run_codex_isolated, _json_str_or_null, _json_num_or_null,
# _events_valid_of, _session_id_of, _looks_rate_limited, plus the globals
# SCRIPT_DIR/PLUGIN_ROOT/VALIDATE/DEFAULT_POLICY/CODEX_MODEL. This IS the
# "extract shared transport" the plan asks for — `_run_codex_isolated` needed
# no code change (already generic; see its header comment), so the shared
# surface is reused via `source`, not duplicated.
# ---------------------------------------------------------------------------
# shellcheck source=aid-c3-dispatch.sh
source "$SCRIPT_DIR/aid-c3-dispatch.sh"

# --- C0-specific overrides (do NOT reuse C3's own template/schema/producer) --
C0_PROMPT_TEMPLATE="$PLUGIN_ROOT/defaults/prompts/c0-plan-review-prompt-v1.md"
C0_RESPONSE_SCHEMA="$PLUGIN_ROOT/defaults/schemas/c0-plan-review.schema.json"
C0_INDEPENDENCE_BIN="${AID_C0_INDEPENDENCE_BIN:-$SCRIPT_DIR/aid-audit-independence.sh}"
C0_RENDER_PROMPT="${AID_C0_RENDER_BIN:-$SCRIPT_DIR/aid-render-prompt.sh}"
C0_LEDGER_BIN="${AID_C0_LEDGER_BIN:-$SCRIPT_DIR/aid-cp1-ledger.sh}"
C0_PRODUCER="orchestrator@cp1-deep"
# CODEX_MODEL is a plain global (sourced default "gpt-5.6-terra"); repoint it
# for THIS process only when a C0-specific override is given.
CODEX_MODEL="${AID_C0_CODEX_MODEL:-$CODEX_MODEL}"

# ---------------------------------------------------------------------------
# usage — overrides the sourced C3 usage() (function redefinition wins).
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: aid-c0-plan-review.sh <subcommand> [args...]

Subcommands:
  build-manifest <plan_file> <evidence_dir>
      Write <evidence_dir>/c0/codex/audit-input-manifest.json — the hashed C0
      input manifest (plan file + cited contracts + plan-graph + existing C0
      evidence), reviewed_plan_hash, and reviewed_head.

  dispatch <evidence_dir>
      Gate on the manifest's recorded risk_profile (skip for low/docs unless
      AID_C0_FORCE_REVIEW is set); otherwise probe cross_provider, render the
      sealed C0 prompt, invoke the real Codex CLI (read-only, fresh process),
      and write the canonical <evidence_dir>/c0-plan-review.json.
      Exit 0 = dispatched (or skipped(profile)); exit 2 = every other outcome.

  verify [--reference] <evidence_dir>
      Re-check the codex provenance chain and prove c0-plan-review.json is a
      faithful, deterministic transform of Codex's raw response. Exit 0 =
      verified; exit 2 = any check failed (fail-closed). --reference checks
      freshness against the manifest's captured reviewed_head instead of the
      live HEAD.
EOF
}

# ===========================================================================
# Frontmatter helpers (mirror aid-cp1-gate.sh's plan_id/risk extraction — that
# script lives outside this step's allowed_paths, so the minimal parsing logic
# is duplicated here rather than refactored into a shared lib; keep both in
# sync if either changes).
# ===========================================================================

# _c0_read_frontmatter <plan_file>
#   Sets globals _C0_FM_ID and _C0_FM_RISK from the plan's YAML frontmatter
#   (first '---' to the closing '---'). Fails closed (_fail) if the block is
#   never closed.
_c0_read_frontmatter() {
  local plan_file="$1"
  _C0_FM_ID=""
  _C0_FM_RISK=""
  local in_fm=0 fm_done=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    if [[ "$in_fm" -eq 0 ]]; then
      [[ "$line" == "---" ]] && in_fm=1
      continue
    fi
    if [[ "$line" == "---" ]]; then
      fm_done=1
      break
    fi
    if [[ "$line" =~ ^id:[[:space:]]*(.+)$ ]]; then
      _C0_FM_ID="$(printf '%s' "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi
    if [[ "$line" =~ ^risk:[[:space:]]*(.+)$ ]]; then
      _C0_FM_RISK="$(printf '%s' "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi
  done < "$plan_file"
  [[ "$fm_done" -eq 1 ]] || _fail "plan file missing closing '---' for frontmatter block: $plan_file"
}

# High-risk patterns — VERBATIM copy of aid-cp1-gate.sh's HIGH_RISK_PATTERNS
# (that script is outside this step's allowed_paths; see comment above).
_C0_HIGH_RISK_PATTERNS=(
  '@app\.(get|post|put|patch|delete|head|options)\(|@router\.(get|post|put|patch|delete|head|options)\(|add_route\(|def [a-zA-Z_]+\(.*request|async def [a-zA-Z_]+\(.*request'
  'authenticate|authorize|verify_token|check_permission|require_auth'
  'Schema|Validator|validate\(|marshmallow|pydantic|BaseModel'
  'migrate|alembic|revision|upgrade|downgrade'
  'fsm-state|state_machine|cmd_transition|aid-fsm\.sh'
  'exec\(|subprocess|eval\(|pickle|yaml\.load'
  'stripe|payment|charge|billing|invoice'
  'requirements\.txt|pyproject\.toml|package\.json|Gemfile'
)

# _c0_risk_of <plan_file>  — echoes "high" or "low" (docs/medium collapse to
# "low" here; only "high" auto-runs Codex per the plan's gate contract).
_c0_risk_of() {
  local plan_file="$1" pattern
  _c0_read_frontmatter "$plan_file"
  if [[ "$_C0_FM_RISK" == "high" ]]; then
    echo "high"
    return 0
  fi
  for pattern in "${_C0_HIGH_RISK_PATTERNS[@]}"; do
    if grep -qE "$pattern" "$plan_file" 2>/dev/null; then
      echo "high"
      return 0
    fi
  done
  echo "low"
}

# _c0_plan_id_of <plan_file>  — the plan's frontmatter `id:` field. Fails
# closed (no plan_id → no stable occurrence_id namespace).
_c0_plan_id_of() {
  local plan_file="$1"
  _c0_read_frontmatter "$plan_file"
  [[ -n "$_C0_FM_ID" ]] || _fail "plan file missing 'id' field in frontmatter: $plan_file"
  [[ "$_C0_FM_ID" =~ ^[A-Za-z0-9_-]+$ ]] || _fail "plan id '$_C0_FM_ID' contains invalid characters (path traversal guard)"
  echo "$_C0_FM_ID"
}

# _c0_project_id <repo_root>  — same convention as aid-c3-dispatch.sh's
# build-manifest: .aid-o/config/project.yaml, fallback "unknown".
_c0_project_id() {
  local repo_root="$1" project_yaml="" pid=""
  project_yaml="$(find "$repo_root" -path '*/.aid-o/config/project.yaml' -print -quit 2>/dev/null || true)"
  if [[ -n "$project_yaml" && -f "$project_yaml" ]]; then
    pid="$(yq -r '.project_id // ""' "$project_yaml" 2>/dev/null || echo "")"
  fi
  [[ -z "$pid" || "$pid" == "null" ]] && pid="unknown"
  echo "$pid"
}

# _c0_resolve_contract_token <repo_root> <token>
#   P068 Step 1 (CF3, second half). A plan cites contracts by the token
#   `defaults/schemas/...` or `defaults/policies/...`, but in a plugin
#   repository those files do NOT live at `<repo_root>/defaults/` — they live
#   under `<repo_root>/plugins/<name>/defaults/`. Testing the token against the
#   repo root ALONE therefore failed the existence check for every real
#   contract in this repository, and the manifest silently sealed an empty
#   `contracts` array even for a plan citing a dozen schemas: the reviewer saw
#   none of them.
#
#   The token is now resolved against the repository root FIRST (unchanged
#   behaviour for a non-plugin layout, and it wins on a collision so an
#   existing consumer's paths never move), then against each `plugins/*/`
#   directory in LC_ALL=C order. Echoes the repo-relative path of the FIRST
#   candidate that exists, or nothing. Every candidate is still containment-
#   checked, so a `..` token cannot escape the repo via the plugin prefix.
_c0_resolve_contract_token() {
  local root="$1" tok="$2" cand d rel
  if [[ -f "$root/$tok" ]] && _path_is_within "$root" "$root/$tok"; then
    printf '%s' "$tok"
    return 0
  fi
  while IFS= read -r d; do
    [[ -n "$d" && -d "$d" ]] || continue
    cand="$d/$tok"
    [[ -f "$cand" ]] || continue
    _path_is_within "$root" "$cand" || continue
    rel="$(realpath -m --relative-to="$root" "$cand" 2>/dev/null)" || continue
    printf '%s' "$rel"
    return 0
  done < <(find "$root/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
  return 1
}

# _c0_manifest_entry <repo_root> <repo_rel_path>
#   Echoes {path,sha256,size} for a repo-root-relative path. Missing files
#   hash to the empty-string sha256 with size 0 (same "absent input" pattern
#   as aid-c3-dispatch.sh's _sha256_file).
#
#   P068 Step 1 note: the ONE caller that used to rely on that absent-input
#   fallback for a semantic purpose — the plan-graph — no longer does. An
#   absent graph is now recorded as the explicit status string
#   `absent_pre_generation` instead (see cmd_build_manifest), because a
#   zero-byte seal cannot be told apart from a truncated file. The fallback
#   remains here for any other input that vanishes between listing and
#   hashing, where "absent" genuinely is the honest hash.
_c0_manifest_entry() {
  local root="$1" rel="$2" full h sz
  full="$root/$rel"
  h="$(_sha256_file "$full")"
  if [[ -f "$full" ]]; then
    sz="$(wc -c < "$full" | tr -d '[:space:]')"
    [[ -n "$sz" ]] || sz=0
  else
    sz=0
  fi
  jq -c -n --arg p "$rel" --arg s "sha256:$h" --argjson z "$sz" '{path:$p, sha256:$s, size:$z}'
}

# ===========================================================================
# cmd_build_manifest <plan_file> <evidence_dir>
# ===========================================================================
cmd_build_manifest() {
  if [[ $# -ne 2 ]]; then
    usage >&2
    _fail "build-manifest requires exactly 2 args: <plan_file> <evidence_dir>"
  fi
  local plan_file="$1" evidence_dir="$2"
  [[ -n "$plan_file" ]] || _fail "plan_file is empty"
  [[ -f "$plan_file" && -r "$plan_file" ]] || _fail "plan file not found/readable: $plan_file"
  [[ -n "$evidence_dir" ]] || _fail "evidence_dir is empty"

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || _fail "not a git repository (cwd: $(pwd))"

  local reviewed_head
  reviewed_head="$(git rev-parse HEAD 2>/dev/null)" \
    || _fail "cannot resolve current HEAD"

  local plan_id risk_profile
  plan_id="$(_c0_plan_id_of "$plan_file")"
  risk_profile="$(_c0_risk_of "$plan_file")"

  mkdir -p "$evidence_dir/c0/codex" || _fail "cannot create $evidence_dir/c0/codex"
  local evidence_abs
  evidence_abs="$(cd "$evidence_dir" && pwd)" || _fail "cannot resolve evidence_dir: $evidence_dir"

  local plan_file_abs plan_file_rel
  plan_file_abs="$(realpath -m -- "$plan_file" 2>/dev/null)" || _fail "cannot resolve plan_file path: $plan_file"
  _path_is_within "$repo_root" "$plan_file_abs" \
    || _fail "plan_file escapes the repo (path traversal / absolute path rejected): $plan_file"
  plan_file_rel="$(realpath -m --relative-to="$repo_root" "$plan_file_abs" 2>/dev/null)" \
    || _fail "cannot compute repo-relative plan_file path"

  local reviewed_plan_hash
  reviewed_plan_hash="sha256:$(sha256sum "$plan_file" | awk '{print $1}')"

  local evidence_dir_rel
  evidence_dir_rel="$(realpath -m --relative-to="$repo_root" "$evidence_abs" 2>/dev/null)" \
    || _fail "cannot compute repo-relative evidence_dir path"

  # --- contracts the plan cites: defaults/{schemas,policies}/* paths mentioned
  #     in the plan text that ACTUALLY exist on disk — resolved against the
  #     repo root AND each plugins/*/ directory (P068 Step 1, CF3). A plan
  #     citing no external contracts yields an empty (still valid) array. ----
  local contracts=()
  local tok resolved
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    resolved="$(_c0_resolve_contract_token "$repo_root" "$tok")" || continue
    [[ -n "$resolved" ]] && contracts+=("$resolved")
  done < <(grep -oE 'defaults/(schemas|policies)/[A-Za-z0-9_./-]+\.(json|ya?ml)' "$plan_file" 2>/dev/null | LC_ALL=C sort -u)
  if [[ ${#contracts[@]} -gt 0 ]]; then
    mapfile -t contracts < <(printf '%s\n' "${contracts[@]}" | LC_ALL=C sort -u)
  fi

  # --- plan-graph (sibling c0/ dir; may not exist yet at plan-review time) --
  #
  # P068 Step 1 (CF3 refinement). `plan-graph.json` is produced by
  # `aid-c0-contract.sh contract <plan.json>`, and `plan.json` exists only
  # AFTER EPIC generation — so a pre-generation plan review can never supply
  # it. That is a legitimate, expected state, not a defect.
  #
  # It used to be sealed as an ordinary absent input: the empty-string sha256
  # with `size: 0`. That is indistinguishable from a graph that WAS produced
  # and then truncated to zero bytes — the reviewer could not tell "not
  # generated yet" from "generated and destroyed". The manifest now records
  # the explicit status string `absent_pre_generation` in `plan_graph`
  # instead, and drops the phantom entry from `files[]`/`allowlist` entirely
  # (there is no file to allow reading, and a zero-byte entry in the hashed
  # set is exactly the opaque seal being removed). When the graph DOES exist —
  # any post-generation review — it is sealed and hashed exactly as before, as
  # a {path,sha256,size} object.
  #
  # This changes the sealed `input_hash` for every pre-generation review, which
  # is intended: the hash now commits to a different, honest input set.
  local plan_graph_rel="$evidence_dir_rel/c0/plan-graph.json"
  local plan_graph_present=0
  [[ -f "$repo_root/$plan_graph_rel" ]] && plan_graph_present=1
  if [[ "$plan_graph_present" -eq 1 ]]; then
    # A source-plan provisional graph is produced before EPIC/plan.json exists.
    # It is useful only when cryptographically bound to THIS plan bytes; a
    # hand-edited graph with a different plan_sha256 must not become a sealed
    # C0 input merely because it happens to be valid JSON.
    local graph_schema graph_plan_sha graph_cycles
    graph_schema="$(jq -r '.schema // ""' "$repo_root/$plan_graph_rel" 2>/dev/null)" || _fail "plan graph is not valid JSON: $plan_graph_rel"
    if [[ "$graph_schema" == "aid-source-plan-graph/v1" ]]; then
      graph_plan_sha="$(jq -r '.plan_sha256 // ""' "$repo_root/$plan_graph_rel")"
      [[ "$graph_plan_sha" == "$reviewed_plan_hash" ]] || _fail "provisional plan graph hash does not match reviewed plan: $plan_graph_rel"
      jq -e '(.edges|type == "array") and (.topological_order|type == "array") and (.cycles|type == "array")' "$repo_root/$plan_graph_rel" >/dev/null \
        || _fail "provisional plan graph has invalid graph shape: $plan_graph_rel"
      graph_cycles="$(jq '.cycles | length' "$repo_root/$plan_graph_rel")"
      [[ "$graph_cycles" == "0" ]] || _fail "provisional plan graph contains cycle(s): $plan_graph_rel"
    fi
  fi

  # --- existing C0 evidence: cp1-deep lenses/adjudicator + c0 contract/plan-
  #     review artifacts, whichever are ACTUALLY present (nullglob). ---------
  local c0_evidence=()
  local f bn
  # cp1-lens-*.md is a genuine glob — nullglob elides it when nothing matches.
  shopt -s nullglob
  for f in "$evidence_abs"/cp1-deep/cp1-lens-*.md; do
    bn="$(realpath -m --relative-to="$repo_root" "$f" 2>/dev/null)" || continue
    c0_evidence+=("$bn")
  done
  shopt -u nullglob
  # The remaining three are LITERAL filenames, not glob patterns — nullglob has
  # no effect on a literal path (it only elides a pattern with metacharacters
  # that fails to match), so each needs its own explicit -f existence check.
  for f in "$evidence_abs/cp1-deep/cp1-adjudicator.md" \
           "$evidence_abs/c0/contract-manifest.json" \
           "$evidence_abs/c0/plan-review.json"; do
    [[ -f "$f" ]] || continue
    bn="$(realpath -m --relative-to="$repo_root" "$f" 2>/dev/null)" || continue
    c0_evidence+=("$bn")
  done
  mapfile -t c0_evidence < <(printf '%s\n' "${c0_evidence[@]}" | LC_ALL=C sort -u)

  # --- assemble the full hashed file set (plan + contracts + plan-graph +
  #     c0 evidence), sorted (LC_ALL=C) for determinism. --------------------
  local all_paths=("$plan_file_rel" "${contracts[@]}" "${c0_evidence[@]}")
  [[ "$plan_graph_present" -eq 1 ]] && all_paths+=("$plan_graph_rel")
  mapfile -t all_paths < <(printf '%s\n' "${all_paths[@]}" | LC_ALL=C sort -u)

  local files_json="[]" p entry
  for p in "${all_paths[@]}"; do
    [[ -z "$p" ]] && continue
    entry="$(_c0_manifest_entry "$repo_root" "$p")" || _fail "cannot hash manifest entry: $p"
    files_json="$(printf '%s' "$files_json" | jq -c --argjson e "$entry" '. + [$e]')" \
      || _fail "cannot assemble files[] entry for $p"
  done

  local contracts_json="[]"
  if [[ ${#contracts[@]} -gt 0 ]]; then
    contracts_json="$(printf '%s\n' "${contracts[@]}" | jq -R . | jq -s .)"
  fi
  local c0_evidence_json="[]"
  if [[ ${#c0_evidence[@]} -gt 0 && -n "${c0_evidence[0]}" ]]; then
    c0_evidence_json="$(printf '%s\n' "${c0_evidence[@]}" | jq -R . | jq -s .)"
  fi
  # Present → the {path,sha256,size} seal, exactly as before.
  # Absent  → the explicit status string, never a zero-byte seal.
  local plan_graph_entry
  if [[ "$plan_graph_present" -eq 1 ]]; then
    plan_graph_entry="$(_c0_manifest_entry "$repo_root" "$plan_graph_rel")" \
      || _fail "cannot hash plan-graph entry"
  else
    plan_graph_entry='"absent_pre_generation"'
  fi

  local canonical input_hash
  canonical="$(jq -S -c -n \
    --arg rph "$reviewed_plan_hash" --arg rh "$reviewed_head" --argjson files "$files_json" \
    '{reviewed_plan_hash: $rph, reviewed_head: $rh, files: $files}')" \
    || _fail "cannot build input_hash canonical form"
  input_hash="sha256:$(_sha256_str "$canonical")"

  local project_id
  project_id="$(_c0_project_id "$repo_root")"

  local allow_json="[]"
  if [[ ${#all_paths[@]} -gt 0 ]]; then
    allow_json="$(printf '%s\n' "${all_paths[@]}" | jq -R . | jq -s '[.[] | select(length > 0)]')"
  fi

  local subject_hash_hex iso_now
  subject_hash_hex="$(_sha256_str "$reviewed_head")"
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local manifest_out="$evidence_dir/c0/codex/audit-input-manifest.json"
  local manifest_tmp="$manifest_out.tmp.$$"

  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "audit_input_manifest" \
    --arg producer "$C0_PRODUCER" \
    --arg created_at "$iso_now" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$project_id" \
    --arg plan_id "$plan_id" \
    --arg subject_hash "sha256:$subject_hash_hex" \
    --arg reviewed_head "$reviewed_head" \
    --arg generated_by_tool "aid-c0-plan-review.sh#build-manifest" \
    --argjson allowlist "$allow_json" \
    --arg input_hash "$input_hash" \
    --arg plan_file "$plan_file_rel" \
    --arg reviewed_plan_hash "$reviewed_plan_hash" \
    --arg risk_profile "$risk_profile" \
    --argjson contracts "$contracts_json" \
    --argjson plan_graph "$plan_graph_entry" \
    --argjson c0_evidence "$c0_evidence_json" \
    --argjson files "$files_json" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {project_id: $project_id, plan_id: $plan_id},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $reviewed_head, head_is_current: true, freshness: "current"},
      status: "pass",
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: $generated_by_tool},
      audit_input_manifest: {
        allowlist: $allowlist,
        input_hash: $input_hash,
        prior_pass_summaries: "untrusted",
        required_independence_level: "cross_provider",
        c0_plan_review_input: {
          plan_file: $plan_file,
          reviewed_plan_hash: $reviewed_plan_hash,
          reviewed_head: $reviewed_head,
          plan_id: $plan_id,
          risk_profile: $risk_profile,
          contracts: $contracts,
          plan_graph: $plan_graph,
          c0_evidence: $c0_evidence,
          files: $files
        }
      }
    }' > "$manifest_tmp" \
    || { rm -f "$manifest_tmp"; _fail "jq failed to render the manifest"; }

  mv "$manifest_tmp" "$manifest_out" || { rm -f "$manifest_tmp"; _fail "cannot move manifest into place"; }

  local validate_out=""
  if ! validate_out="$(bash "$VALIDATE" "$manifest_out" 2>&1)"; then
    rm -f "$manifest_out"
    _fail "emitted manifest failed aid-protocol-validate.sh: ${validate_out}"
  fi

  echo "$manifest_out"
  return 0
}

# ===========================================================================
# dispatch helpers
# ===========================================================================

# _c0_write_dispatch_json — emit c0/codex/c0-dispatch.json (atomic temp+mv).
# Positional args:
#   1 out 2 project_root 3 reviewed_head 4 input_manifest_hash
#   5 template_id 6 template_sha256 7 rendered_prompt_sha256 8 codex_version
#   9 invoked(true|false) 10 exit_code(int|"") 11 outcome 12 session_id
#   13 codex_model 14 events_valid(true|false) 15 stdout_sha256
#   16 raw_response_sha256 17 achieved_level
_c0_write_dispatch_json() {
  local out="$1" project_root="$2" reviewed_head="$3" input_manifest_hash="$4"
  local template_id="$5" template_sha256="$6" rendered_prompt_sha256="$7" codex_version="$8"
  local invoked="$9" exit_code="${10}" outcome="${11}" session_id="${12}" codex_model="${13}"
  local events_valid="${14}" stdout_sha256="${15}" raw_response_sha256="${16}" achieved_level="${17}"

  local iso_now tmp
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$out.tmp.$$"

  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "c0_dispatch" \
    --arg producer "$C0_PRODUCER" \
    --arg created_at "$iso_now" \
    --arg generated_by_tool "aid-c0-plan-review.sh#dispatch" \
    --arg project_root "$project_root" \
    --arg reviewed_head "$reviewed_head" \
    --arg input_manifest_hash "$input_manifest_hash" \
    --arg required_independence_level "cross_provider" \
    --arg probed_independence_level "cross_provider" \
    --arg executor_kind "codex_cli" \
    --argjson template_id "$(_json_str_or_null "$template_id")" \
    --argjson template_sha256 "$(_json_str_or_null "$template_sha256")" \
    --argjson rendered_prompt_sha256 "$(_json_str_or_null "$rendered_prompt_sha256")" \
    --argjson codex_version "$(_json_str_or_null "$codex_version")" \
    --argjson invoked "$invoked" \
    --argjson exit_code "$(_json_num_or_null "$exit_code")" \
    --arg outcome "$outcome" \
    --argjson codex_session_id "$(_json_str_or_null "$session_id")" \
    --arg codex_reported_model "$codex_model" \
    --argjson events_valid "$events_valid" \
    --argjson stdout_sha256 "$(_json_str_or_null "$stdout_sha256")" \
    --argjson raw_response_sha256 "$(_json_str_or_null "$raw_response_sha256")" \
    --arg achieved_independence_level "$achieved_level" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      provenance: {dispatch_mode: "cross_provider", generated_by_tool: $generated_by_tool},
      executor: {kind: $executor_kind, reported_model: $codex_reported_model, codex_version: $codex_version},
      subject: {project_root: $project_root, reviewed_head: $reviewed_head, input_manifest_hash: $input_manifest_hash},
      prompt: {template_id: $template_id, template_sha256: $template_sha256, rendered_prompt_sha256: $rendered_prompt_sha256},
      dispatch: {
        invoked: $invoked,
        exit_code: $exit_code,
        outcome: $outcome,
        events_valid: $events_valid,
        codex_session_id: $codex_session_id,
        stdout_sha256: $stdout_sha256,
        raw_response_sha256: $raw_response_sha256
      },
      independence: {
        required_independence_level: $required_independence_level,
        probed_independence_level: $probed_independence_level,
        achieved_independence_level: $achieved_independence_level
      }
    }' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
  return 0
}

# _c0_validate_response <last_message_file>
#   The TRUSTED gate over Codex's raw output — mirrors aid-c3-dispatch.sh's
#   _validate_response but for the C0 key-shape (artifact_type/
#   reviewed_plan_hash/reviewed_head/input_manifest_hash instead of C3's
#   reviewed_head/codex_brief_hash). Rejects a C3-shaped audit_report response
#   outright (missing artifact_type/reviewed_plan_hash/input_manifest_hash,
#   extra codex_brief_hash) — the "Codex emits a C3 shape" edge case.
_c0_validate_response() {
  local f="$1" rc=0 doc_count
  [[ -f "$f" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  doc_count="$(jq -c . "$f" 2>/dev/null | wc -l | tr -d '[:space:]')"
  [[ "$doc_count" == "1" ]] || return 1

  jq -e '
    (type == "object")
    and ((keys_unsorted
          - ["artifact_type","reviewed_plan_hash","reviewed_head","input_manifest_hash","review_status","blocking_findings","findings","unverifiable_reasons"])
         | length == 0)
    and ((["artifact_type","reviewed_plan_hash","reviewed_head","input_manifest_hash","review_status","blocking_findings","findings"]
          - keys_unsorted) | length == 0)
    and (.artifact_type == "c0_plan_review")
    and (.review_status | (. == "pass" or . == "findings" or . == "unverifiable"))
    and (.reviewed_plan_hash    | (type == "string" and test("^sha256:[0-9a-f]{64}$")))
    and (.reviewed_head         | (type == "string" and test("^[0-9a-f]{40}$")))
    and (.input_manifest_hash   | (type == "string" and test("^sha256:[0-9a-f]{64}$")))
    and (.blocking_findings | type == "boolean")
    and (.findings | type == "array")
    and (if .review_status == "unverifiable"
           then (.unverifiable_reasons
                 | (type == "array") and (length > 0)
                   and all(.[]; type == "string" and length > 0))
           else (has("unverifiable_reasons") | not)
         end)
    and (.blocking_findings
         == ([.findings[] | select(.severity == "critical" or .severity == "high")] | length > 0))
    and (if .review_status == "pass"
           then (.findings | length == 0) and (.blocking_findings == false)
           else true end)
    and (if .review_status == "findings"
           then (.findings | length >= 1)
           else true end)
    and (all(.findings[]; . as $f
          | ((["critical","high","medium","low","info"]) | index($f.severity) != null)
            and ($f.area           | type == "string" and length > 0)
            and ($f.finding        | type == "string" and length > 0)
            and ($f.recommendation | type == "string" and length > 0)
            and (if ($f.severity == "critical" or $f.severity == "high")
                   then ($f | has("action_owner")) else true end)
            and (if ($f | has("action_owner"))
                   then ((["implementer","reviewer","pm","gate-fixer"]) | index($f.action_owner) != null)
                   else true end)
        ))
  ' "$f" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]]
}

# _c0_derive_semantics <validated_last_msg_path>
#   The single source of truth for what c0-plan-review.json's status/
#   review_status/outcome/blocking_findings/unverifiable_reasons fields MUST
#   be, as a deterministic function of an ALREADY-_c0_validate_response-
#   validated raw response. Mirrors aid-c3-dispatch.sh's
#   _derive_report_semantics. Both the writer and `verify` call this so they
#   can never diverge.
_c0_derive_semantics() {
  local last_msg="$1"
  [[ -f "$last_msg" ]] || return 1
  jq -ce '
    if .review_status == "unverifiable" then
      {
        status: "unverifiable",
        review_status: "unverifiable",
        outcome: "review_unverifiable",
        blocking_findings: false,
        unverifiable_reasons: (.unverifiable_reasons // [])
      }
    else
      ([.findings[] | select(.severity == "critical" or .severity == "high")] | length > 0) as $blocking
      | {
          status: (if $blocking then "fail" else "pass" end),
          review_status: .review_status,
          outcome: "dispatched",
          blocking_findings: $blocking,
          unverifiable_reasons: []
        }
    end
  ' "$last_msg" 2>/dev/null
}

# _c0_normalize <project_id> <plan_id> <last_message_file>
#   Deterministically turn Codex's raw findings[] into fingerprinted findings.
#   occurrence_id = "c0-<plan_id>-<n>"; fingerprint via aid-finding-fingerprint.sh
#   (finding_class arg = "c0_plan_review", distinct from C3's "audit_report").
_c0_normalize() {
  local project_id="$1" plan_id="$2" last_msg="$3"
  local fp_helper="$SCRIPT_DIR/aid-finding-fingerprint.sh"
  local count
  count="$(jq '.findings | length' "$last_msg" 2>/dev/null)" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1

  local out="[]" n sev area finding rec has_ao ao occ fp item
  for (( n=0; n<count; n++ )); do
    sev="$(jq -r --argjson i "$n" '.findings[$i].severity'       "$last_msg" 2>/dev/null)"     || return 1
    area="$(jq -r --argjson i "$n" '.findings[$i].area'          "$last_msg" 2>/dev/null)"     || return 1
    finding="$(jq -r --argjson i "$n" '.findings[$i].finding'    "$last_msg" 2>/dev/null)"     || return 1
    rec="$(jq -r --argjson i "$n" '.findings[$i].recommendation' "$last_msg" 2>/dev/null)"     || return 1
    has_ao="$(jq -r --argjson i "$n" '.findings[$i] | has("action_owner")' "$last_msg" 2>/dev/null)" || return 1
    occ="c0-${plan_id}-${n}"
    fp="$(bash "$fp_helper" fingerprint_audit_report "$project_id" c0_plan_review "$occ" "$sev" "$area" "$finding" "$rec" 2>/dev/null)" || return 1
    fp="${fp%$'\n'}"
    [[ "$fp" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    if [[ "$has_ao" == "true" ]]; then
      ao="$(jq -r --argjson i "$n" '.findings[$i].action_owner' "$last_msg" 2>/dev/null)" || return 1
      item="$(jq -nc --arg fp "$fp" --arg occ "$occ" --arg sev "$sev" --arg ao "$ao" \
                --arg area "$area" --arg finding "$finding" --arg rec "$rec" \
                '{fingerprint:$fp,occurrence_id:$occ,severity:$sev,action_owner:$ao,area:$area,finding:$finding,recommendation:$rec}')" || return 1
    else
      item="$(jq -nc --arg fp "$fp" --arg occ "$occ" --arg sev "$sev" \
                --arg area "$area" --arg finding "$finding" --arg rec "$rec" \
                '{fingerprint:$fp,occurrence_id:$occ,severity:$sev,area:$area,finding:$finding,recommendation:$rec}')" || return 1
    fi
    out="$(jq -c --argjson item "$item" '. + [$item]' <<<"$out")" || return 1
  done
  printf '%s' "$out"
}

# _c0_write_unverifiable <evidence_dir> <manifest> <outcome> <achieved> <session_id> <last_msg_or_empty> <reasons_json_or_empty>
#   Fail-closed writer — ALWAYS writes c0-plan-review.json with
#   status:"unverifiable", blocking_findings:false, empty findings[]. NEVER
#   pass/fail. Mirrors aid-c3-dispatch.sh's _write_unverifiable.
_c0_write_unverifiable() {
  local evidence_dir="$1" manifest="$2" outcome="$3" achieved="$4" session_id="$5"
  local last_msg="$6" reasons_json="$7"
  local report="$evidence_dir/c0-plan-review.json"

  local reviewed_plan_hash reviewed_head plan_id
  reviewed_plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest" 2>/dev/null || echo "")"
  reviewed_head="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head // ""' "$manifest" 2>/dev/null || echo "")"
  plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest" 2>/dev/null || echo "")"
  local manifest_input_hash
  manifest_input_hash="sha256:$(sha256sum "$manifest" | awk '{print $1}')"

  local raw_plan_hash="" raw_head="" raw_imh=""
  if [[ -n "$last_msg" && -f "$last_msg" ]] && jq -e . "$last_msg" >/dev/null 2>&1; then
    raw_plan_hash="$(jq -r '.reviewed_plan_hash // ""' "$last_msg" 2>/dev/null || echo "")"
    raw_head="$(jq -r '.reviewed_head // ""' "$last_msg" 2>/dev/null || echo "")"
    raw_imh="$(jq -r '.input_manifest_hash // ""' "$last_msg" 2>/dev/null || echo "")"
    [[ "$raw_plan_hash" == "null" ]] && raw_plan_hash=""
    [[ "$raw_head" == "null" ]] && raw_head=""
    [[ "$raw_imh" == "null" ]] && raw_imh=""
  fi

  local iso_now
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -n "$reasons_json" ]] || reasons_json="[]"

  local tmp="$report.tmp.$$"
  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "c0_plan_review" \
    --arg producer "$C0_PRODUCER" \
    --arg created_at "$iso_now" \
    --arg plan_id "$plan_id" \
    --arg reviewed_plan_hash "${raw_plan_hash:-$reviewed_plan_hash}" \
    --arg reviewed_head "${raw_head:-$reviewed_head}" \
    --arg input_manifest_hash "${raw_imh:-$manifest_input_hash}" \
    --arg review_status "unverifiable" \
    --arg outcome "$outcome" \
    --arg achieved "$achieved" \
    --arg model "$CODEX_MODEL" \
    --argjson session_id "$(_json_str_or_null "$session_id")" \
    --argjson reasons "$reasons_json" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      identity: {plan_id: $plan_id},
      reviewed_plan_hash: $reviewed_plan_hash,
      reviewed_head: $reviewed_head,
      input_manifest_hash: $input_manifest_hash,
      review_status: $review_status,
      blocking_findings: false,
      unverifiable_reasons: $reasons,
      findings: [],
      codex: {provider: "codex", model: $model, session_id: $session_id, achieved_independence_level: $achieved},
      outcome: $outcome
    }' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$report" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

# _c0_write_skipped <evidence_dir> <manifest>
#   The low/docs-risk "Codex not auto-run" outcome. Distinct from unverifiable
#   (this is an EXPECTED, non-error state — the review was never attempted,
#   not attempted-and-failed). review_status is honestly "skipped" (a 4th
#   value the raw model schema never uses, since Codex never runs on this
#   path) rather than borrowing "pass" or "unverifiable", neither of which
#   would be true.
_c0_write_skipped() {
  local evidence_dir="$1" manifest="$2"
  local report="$evidence_dir/c0-plan-review.json"

  local reviewed_plan_hash reviewed_head plan_id manifest_input_hash iso_now
  reviewed_plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest" 2>/dev/null || echo "")"
  reviewed_head="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head // ""' "$manifest" 2>/dev/null || echo "")"
  plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest" 2>/dev/null || echo "")"
  manifest_input_hash="sha256:$(sha256sum "$manifest" | awk '{print $1}')"
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local tmp="$report.tmp.$$"
  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "c0_plan_review" \
    --arg producer "$C0_PRODUCER" \
    --arg created_at "$iso_now" \
    --arg plan_id "$plan_id" \
    --arg reviewed_plan_hash "$reviewed_plan_hash" \
    --arg reviewed_head "$reviewed_head" \
    --arg input_manifest_hash "$manifest_input_hash" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      identity: {plan_id: $plan_id},
      reviewed_plan_hash: $reviewed_plan_hash,
      reviewed_head: $reviewed_head,
      input_manifest_hash: $input_manifest_hash,
      review_status: "skipped",
      blocking_findings: false,
      findings: [],
      codex: {provider: "codex", model: null, session_id: null, achieved_independence_level: "not_probed"},
      outcome: "skipped(profile)"
    }' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$report" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

# _c0_copy_atomic <src> <dst>  — copy <src> to <dst> via temp+mv (a reader never
# observes a partial file). Returns 1 — no side effect beyond a removed temp —
# if <src> is missing or either write step fails (e.g. <dst>'s parent directory
# is not writable). Mirrors aid-c3-dispatch.sh's _c3_copy_atomic.
_c0_copy_atomic() {
  local src="$1" dst="$2" tmp
  [[ -f "$src" ]] || return 1
  tmp="$dst.tmp.$$"
  cp -f "$src" "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$dst" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# _c0_write_loop_summary <evidence_dir> <n> <session_id> <head_sha> <dispatch_outcome> <report_status>
#   Accumulate <evidence_dir>/c0/loop-summary.json — the PM-facing record of
#   every C0 review attempt this evidence dir has seen so far. Mirrors
#   aid-c3-dispatch.sh's _c3_write_loop_summary (P065 Step 17/E-065-6_7):
#     {schema_version, artifact_type:"c0_loop_summary", producer, created_at,
#      attempts: [{n, session_id, head, outcome, recorded_at}, ...] (sorted by
#        n; re-writing entry <n> REPLACES any prior record for that same n),
#      recheck_count,   -- count of GENUINELY dispatched attempts minus 1,
#                          floored at 0.
#      outcome,         -- "clean" (latest attempt's blocking_findings==false),
#                          "unverifiable" (latest review_status=="unverifiable"),
#                          "escalated" (latest still blocking AND the SAME
#                          blocking-finding fingerprint survived the immediately
#                          prior dispatched attempt — mechanically decidable,
#                          the ONE new capability Part B adds), or null (still
#                          blocking, retriable).
#      escalation_reason, current_attempt}
#   DELIBERATELY does NOT port a "budget_exhausted" escalation branch: C0's
#   actual attempt-count bound is the CP1 ledger (aid-cp1-ledger.sh, max:3),
#   a SEPARATE, already-tested enforcement mechanism. Duplicating that bound
#   here would create two independent copies of the same truth that could
#   diverge (P065 E-065-7_7 Finding B PM decision: no dual-copy-of-truth) —
#   the hard 3-attempt cap keeps working unchanged via the ledger regardless
#   of what this documentary file says. Returns 1 on any write failure
#   (temp+mv — never a partial overwrite).
_c0_write_loop_summary() {
  local evidence_dir="$1" n="$2" session_id="$3" head_sha="$4" dispatch_outcome="$5" report_status="$6"
  local out="$evidence_dir/c0/loop-summary.json"
  local tmp="$out.tmp.$$"
  local existing="[]"
  if [[ -f "$out" ]]; then
    existing="$(jq -c '.attempts // []' "$out" 2>/dev/null)"
    [[ -n "$existing" ]] || existing="[]"
  fi

  local iso_now new_entry
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  new_entry="$(jq -nc \
    --argjson n "$n" \
    --argjson session_id "$(_json_str_or_null "$session_id")" \
    --argjson head "$(_json_str_or_null "$head_sha")" \
    --arg outcome "$dispatch_outcome" \
    --arg recorded_at "$iso_now" \
    '{n:$n, session_id:$session_id, head:$head, outcome:$outcome, recorded_at:$recorded_at}')" \
    || return 1

  local attempts dispatched_count recheck_count top_outcome
  attempts="$(jq -c --argjson e "$new_entry" --argjson n "$n" \
    '(map(select(.n != $n))) + [$e] | sort_by(.n)' <<<"$existing")" || return 1
  dispatched_count="$(jq '[.[] | select(.outcome=="dispatched")] | length' <<<"$attempts" 2>/dev/null)"
  [[ "$dispatched_count" =~ ^[0-9]+$ ]] || dispatched_count=0
  recheck_count=0
  [[ "$dispatched_count" -gt 0 ]] && recheck_count=$(( dispatched_count - 1 ))

  # Same-fingerprint-survives detection — compare THIS attempt's blocking-
  # finding fingerprints against the immediately-prior dispatched attempt's.
  # Mirrors _c3_write_loop_summary's identical logic exactly.
  local same_fingerprint_survived=false
  if [[ "$report_status" == "fail" ]]; then
    local prev_n prev_nn prev_report
    prev_n="$(jq -r --argjson n "$n" \
      '[.[] | select(.n < $n and .outcome == "dispatched")] | sort_by(.n) | last | .n // empty' \
      <<<"$attempts" 2>/dev/null)"
    if [[ -n "$prev_n" ]]; then
      prev_nn="$(printf '%02d' "$prev_n")"
      prev_report="$evidence_dir/c0/attempt-$prev_nn/c0-plan-review.json"
      if [[ -f "$prev_report" ]]; then
        local cur_fps prev_fps overlap
        cur_fps="$(jq -c '[.findings[]?.fingerprint] | sort' "$evidence_dir/c0-plan-review.json" 2>/dev/null)"
        prev_fps="$(jq -c '[.findings[]?.fingerprint] | sort' "$prev_report" 2>/dev/null)"
        [[ -n "$cur_fps" ]] || cur_fps='[]'
        [[ -n "$prev_fps" ]] || prev_fps='[]'
        overlap="$(jq -n --argjson a "$cur_fps" --argjson b "$prev_fps" \
          '[$a[] | select(. as $x | $b | index($x))] | length' 2>/dev/null)"
        [[ "${overlap:-0}" -gt 0 ]] && same_fingerprint_survived=true
      fi
    fi
  fi

  local escalation_reason='null'
  case "$report_status" in
    pass) top_outcome='"clean"' ;;
    unverifiable|fail)
      if [[ "$same_fingerprint_survived" == true ]]; then
        top_outcome='"escalated"'
        escalation_reason='"same_fingerprint_survived"'
      elif [[ "$report_status" == "unverifiable" ]]; then
        top_outcome='"unverifiable"'
      else
        top_outcome='null'
      fi
      ;;
    *)    top_outcome='null' ;;
  esac

  jq -n \
    --argjson attempts "$attempts" \
    --argjson recheck_count "$recheck_count" \
    --argjson outcome "$top_outcome" \
    --argjson escalation_reason "$escalation_reason" \
    --argjson current_attempt "$n" \
    --arg created_at "$iso_now" \
    '{schema_version:"aid-2.0", artifact_type:"c0_loop_summary",
      producer:"orchestrator@done-review", created_at:$created_at,
      attempts:$attempts, recheck_count:$recheck_count, outcome:$outcome,
      escalation_reason:$escalation_reason, current_attempt:$current_attempt}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$out" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

# _c0_finalize_attempt <evidence_dir> <attempt_dir> <manifest> <n> <nn> <session_id> <head_sha> <dispatch_outcome>
#   Copies <attempt_dir>'s c0-plan-review.json to the canonical <evidence_dir>
#   root, then updates c0/loop-summary.json (attempts history, same-
#   fingerprint-survives detection, current_attempt pointer). On a
#   canonical-copy failure: stomps the canonical report to status:unverifiable
#   (best effort) and marks the whole call a failure — the caller
#   (cmd_dispatch) must exit 2 on a 1, never exit 0. Mirrors
#   aid-c3-dispatch.sh's _c3_finalize_attempt (minus its budget_exhausted
#   escalation branch — see _c0_write_loop_summary's header comment).
_c0_finalize_attempt() {
  local evidence_dir="$1" attempt_dir="$2" manifest="$3" n="$4" nn="$5"
  local session_id="$6" head_sha="$7" dispatch_outcome="$8"
  local rc=0

  # report_status: this attempt's OWN report status BEFORE the canonical
  # copy — "fail" iff blocking_findings (mirrors _derive_report_semantics'
  # status:"fail" iff a crit/high finding exists), "unverifiable" iff
  # review_status=="unverifiable" OR "skipped", else "pass". C0's report has
  # no top-level .status field (unlike C3's audit-report.json), so derive
  # the equivalent from review_status + blocking_findings directly.
  #
  # CP2 Part-B self-verify finding: "skipped" (the low/docs risk-profile
  # early-return — _c0_write_skipped, Codex never invoked) was NOT
  # special-cased here and fell through to "pass", which
  # _c0_write_loop_summary then maps to top-level outcome:"clean" — and
  # "clean" is TERMINAL under the new ALLOWLIST guard. A plan that starts
  # low-risk (attempt 1 correctly skips) and is later revised into
  # high-risk territory (attempt 2, rebuilt manifest) would then have its
  # first REAL review permanently blocked by a guard meant to prevent
  # re-litigating an already-genuinely-clean review. "skipped" means "no
  # review happened at all" — treat it the same as "unverifiable" (also
  # non-terminal in the ALLOWLIST) rather than a genuine clean pass.
  local report_status=""
  if [[ -f "$attempt_dir/c0-plan-review.json" ]]; then
    local rs bf
    rs="$(jq -r '.review_status // ""' "$attempt_dir/c0-plan-review.json" 2>/dev/null)" || rs=""
    bf="$(jq -r '.blocking_findings // false' "$attempt_dir/c0-plan-review.json" 2>/dev/null)" || bf="false"
    if [[ "$rs" == "unverifiable" || "$rs" == "skipped" ]]; then
      report_status="unverifiable"
    elif [[ "$bf" == "true" ]]; then
      report_status="fail"
    else
      report_status="pass"
    fi
  fi

  if _c0_copy_atomic "$attempt_dir/c0-plan-review.json" "$evidence_dir/c0-plan-review.json"; then
    : # success — fall through to the loop-summary write below
  else
    echo "aid-c0-plan-review: FATAL — cannot copy c0/attempt-$nn/c0-plan-review.json to the canonical evidence-root path; failing closed (attempt evidence remains authoritative under c0/attempt-$nn/)" >&2
    _c0_write_unverifiable "$evidence_dir" "$manifest" canonical_copy_failed unavailable "" "" "" || true
    report_status="canonical_copy_failed"
    rc=1
  fi

  # SECURITY/CORRECTNESS: a loop-summary write failure must also fail this
  # call, even when the canonical report copy itself succeeded — otherwise
  # cmd_verify would have no way to find this attempt's raw evidence
  # (mirrors aid-c3-dispatch.sh's identical fail-closed rule).
  local summary_rc=0
  _c0_write_loop_summary "$evidence_dir" "$n" "$session_id" "$head_sha" "$dispatch_outcome" "$report_status" || summary_rc=$?
  if [[ "$summary_rc" -ne 0 ]]; then
    echo "aid-c0-plan-review: FATAL — c0/loop-summary.json write failed after attempt $nn; cmd_verify cannot resolve the current attempt's raw evidence. Failing closed." >&2
    _c0_write_unverifiable "$evidence_dir" "$manifest" loop_summary_write_failed unavailable "" "" "" || true
    rc=1
  fi
  return "$rc"
}

# _c0_write_report <evidence_dir> <manifest> <last_msg> <achieved> <session_id>
#   Assemble the final c0-plan-review.json from an ALREADY-VALIDATED raw
#   response. The ONLY place review_status pass|findings is written for a real
#   dispatch. Any assembly failure fails closed to _c0_write_unverifiable
#   outcome=invalid_output. Returns 0 on success, 2 otherwise.
_c0_write_report() {
  local evidence_dir="$1" manifest="$2" last_msg="$3" achieved="$4" session_id="$5"

  local project_id plan_id
  project_id="$(jq -r '.identity.project_id // "unknown"' "$manifest" 2>/dev/null || echo unknown)"
  [[ -n "$project_id" && "$project_id" != "null" ]] || project_id="unknown"
  plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest" 2>/dev/null || echo "")"

  local semantics status blocking review_status
  semantics="$(_c0_derive_semantics "$last_msg")" \
    || { _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  status="$(jq -r '.status' <<<"$semantics" 2>/dev/null)"
  blocking="$(jq -r '.blocking_findings' <<<"$semantics" 2>/dev/null)"
  review_status="$(jq -r '.review_status' <<<"$semantics" 2>/dev/null)"

  if [[ "$status" == "unverifiable" ]]; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  local findings_json
  findings_json="$(_c0_normalize "$project_id" "$plan_id" "$last_msg")" \
    || { _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }

  local raw_plan_hash raw_head raw_imh
  raw_plan_hash="$(jq -r '.reviewed_plan_hash' "$last_msg" 2>/dev/null)" || raw_plan_hash=""
  raw_head="$(jq -r '.reviewed_head' "$last_msg" 2>/dev/null)" || raw_head=""
  raw_imh="$(jq -r '.input_manifest_hash' "$last_msg" 2>/dev/null)" || raw_imh=""

  local report="$evidence_dir/c0-plan-review.json"
  local iso_now tmp
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$report.tmp.$$"

  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "c0_plan_review" \
    --arg producer "$C0_PRODUCER" \
    --arg created_at "$iso_now" \
    --arg plan_id "$plan_id" \
    --arg reviewed_plan_hash "$raw_plan_hash" \
    --arg reviewed_head "$raw_head" \
    --arg input_manifest_hash "$raw_imh" \
    --arg review_status "$review_status" \
    --argjson blocking "$blocking" \
    --argjson findings "$findings_json" \
    --arg model "$CODEX_MODEL" \
    --arg session_id "$session_id" \
    --arg achieved "$achieved" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      identity: {plan_id: $plan_id},
      reviewed_plan_hash: $reviewed_plan_hash,
      reviewed_head: $reviewed_head,
      input_manifest_hash: $input_manifest_hash,
      review_status: $review_status,
      blocking_findings: $blocking,
      findings: $findings,
      codex: {provider: "codex", model: $model, session_id: $session_id, achieved_independence_level: $achieved},
      outcome: "dispatched"
    }' > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  mv "$tmp" "$report" 2>/dev/null \
    || { rm -f "$tmp"; _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }

  return 0
}

# _c0_process_response <evidence_dir> <manifest> <codex_rc> <events_valid> <dispatch_outcome> <achieved> <session_id> <reviewed_head> <c0_dir>
#   The validate → normalize → write pipeline. Mirrors
#   aid-c3-dispatch.sh's _process_response for the C0 key-shape.
#   <c0_dir> is the directory the raw Codex artifacts (codex-last-message.json
#   etc) were actually written to by THIS invocation of cmd_dispatch — passed
#   explicitly rather than re-derived, since legacy mode's two-level
#   <evidence_dir>/c0/codex and attempt mode's one-level <attempt_dir>/c0
#   differ (P065 E-065-7_7 DONE-review Finding 2 Part A, CP2 round-9).
_c0_process_response() {
  local evidence_dir="$1" manifest="$2" codex_rc="$3" events_valid="$4"
  local dispatch_outcome="$5" achieved="$6" session_id="$7" reviewed_head="$8"
  local c0_dir="$9"
  local last_msg="$c0_dir/codex-last-message.json"

  if [[ "$codex_rc" != "0" ]]; then
    local uo
    case "$dispatch_outcome" in
      timeout)      uo="timeout" ;;
      rate_limited) uo="rate_limited" ;;
      *)            uo="unavailable" ;;
    esac
    _c0_write_unverifiable "$evidence_dir" "$manifest" "$uo" "$achieved" "$session_id" "" ""
    return 2
  fi

  if [[ "$events_valid" != "true" ]]; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "" ""
    return 2
  fi

  if [[ ! -f "$last_msg" ]] || ! jq -e . "$last_msg" >/dev/null 2>&1; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "" ""
    return 2
  fi
  if ! _c0_validate_response "$last_msg"; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  # Provenance-binding hash checks — Codex must echo the sealed plan hash +
  # input manifest hash AND review the EXACT commit.
  local manifest_plan_hash raw_plan_hash manifest_input_hash raw_imh raw_head current_head
  manifest_plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest" 2>/dev/null || echo "")"
  raw_plan_hash="$(jq -r '.reviewed_plan_hash // ""' "$last_msg" 2>/dev/null || echo "")"
  if [[ -z "$manifest_plan_hash" || "$raw_plan_hash" != "$manifest_plan_hash" ]]; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" hash_mismatch "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi
  manifest_input_hash="sha256:$(sha256sum "$manifest" | awk '{print $1}')"
  raw_imh="$(jq -r '.input_manifest_hash // ""' "$last_msg" 2>/dev/null || echo "")"
  if [[ "$raw_imh" != "$manifest_input_hash" ]]; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" hash_mismatch "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi
  raw_head="$(jq -r '.reviewed_head // ""' "$last_msg" 2>/dev/null || echo "")"
  current_head="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -z "$reviewed_head" || "$raw_head" != "$reviewed_head" || -z "$current_head" || "$raw_head" != "$current_head" ]]; then
    _c0_write_unverifiable "$evidence_dir" "$manifest" head_mismatch "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  local semantics_5a
  semantics_5a="$(_c0_derive_semantics "$last_msg")" \
    || { _c0_write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  if [[ "$(jq -r '.status' <<<"$semantics_5a" 2>/dev/null)" == "unverifiable" ]]; then
    local reasons
    reasons="$(jq -c '.unverifiable_reasons' <<<"$semantics_5a" 2>/dev/null || echo '[]')"
    _c0_write_unverifiable "$evidence_dir" "$manifest" review_unverifiable "$achieved" "$session_id" "$last_msg" "$reasons"
    return 2
  fi

  _c0_write_report "$evidence_dir" "$manifest" "$last_msg" "$achieved" "$session_id"
  return $?
}

# _c0_try_claim_override <project_root> <plan_id> <bypass_label>
#   9th DONE-review audit fix (P065 E-065-7_7: "C0 bounded review lifecycle"
#   finding). Both bypass points in cmd_dispatch below previously accepted
#   ANY AID_C0_FORCE_BEYOND_ESCALATION env var >= 20 characters as
#   "PM-authorized" — no real authorization was required or consumed, so
#   anyone with shell access could bypass the bounded review loop
#   indefinitely. Replaced with a real, single-use claim against the SAME
#   cp1-pm-escalation-override.json artifact + atomic-claim primitive
#   aid-cp1-ledger.sh's cmd_increment already uses (via its shared
#   claim-pm-override subcommand — reused, not reimplemented). On success,
#   warns to stderr with the claimed reason + consumed_path (operator-
#   visible audit trail, mirroring the WARNING this file already printed)
#   and returns 0. On failure (no valid artifact present for this plan_id),
#   returns 1 with nothing printed — caller rejects exactly as before.
_c0_try_claim_override() {
  local project_root="$1" plan_id="$2" bypass_label="$3"
  [[ -n "$project_root" && -n "$plan_id" ]] || return 1
  local claim_json
  claim_json="$(bash "$C0_LEDGER_BIN" claim-pm-override --project-root "$project_root" "$plan_id" 2>/dev/null)" || return 1
  local reason consumed_path
  reason="$(jq -r '.reason // ""' <<<"$claim_json" 2>/dev/null)"
  consumed_path="$(jq -r '.consumed_path // ""' <<<"$claim_json" 2>/dev/null)"
  [[ -n "$reason" ]] || return 1
  echo "aid-c0-plan-review: WARNING — proceeding past ${bypass_label} via a genuine, claimed PM-escalation override: ${reason} (consumed: ${consumed_path})" >&2
  return 0
}

# ===========================================================================
# cmd_dispatch <evidence_dir>
#
# P065 Step 18 (E-065-7_7) — per-attempt evidence layering.
#
# Interface: an OPTIONAL AID_C0_ATTEMPT env var (positive integer, e.g. "2")
# tells this invocation which fix->reverify LOOP ATTEMPT it is. Unset (the
# default) → LEGACY BEHAVIOR, byte-for-byte unchanged: every artifact is
# written directly under <evidence_dir>/c0/codex/ and <evidence_dir>/c0-plan-
# review.json. SET to N → artifacts are written into the SELF-CONTAINED
# directory <evidence_dir>/c0/attempt-NN/ (NN = N zero-padded to 2 digits),
# and the c0-plan-review.json is copied to the canonical evidence-root path
# afterward. If the copy fails, this dispatch fails closed (exit 2).
# ===========================================================================
cmd_dispatch() {
  if [[ $# -ne 1 ]]; then
    usage >&2
    echo "PRECONDITION FAIL: dispatch requires exactly 1 arg: <evidence_dir>" >&2
    exit 1
  fi
  local evidence_dir="$1"
  [[ -n "$evidence_dir" ]] || { echo "PRECONDITION FAIL: evidence_dir is empty" >&2; exit 1; }
  [[ -d "$evidence_dir" ]] || { echo "PRECONDITION FAIL: evidence_dir not a directory: $evidence_dir" >&2; exit 1; }

  # --- Step 0: resolve the attempt slot for THIS invocation ---
  # work_evidence_dir/work_c0_dir are what the rest of this function
  # reads/writes through. attempt_explicit=0 (AID_C0_ATTEMPT unset) makes them
  # IDENTICAL to the pre-Step-18 evidence_dir/c0_dir — the legacy path is
  # untouched. See this function's header comment for the full contract.
  local attempt_n="${AID_C0_ATTEMPT:-}"
  local attempt_explicit=0 attempt_dir="" attempt_nn=""
  # One PM-escalation override authorizes bypassing WHATEVER guard(s) below
  # would otherwise block THIS dispatch call — a PM placing the artifact is
  # authorizing "one more dispatch despite normal restrictions", not a
  # specific internal mechanism. Without this flag, a same-hash retry after
  # a terminal outcome hits BOTH the terminal-outcome guard AND the
  # same-hash guard, and each would independently try to claim (consume)
  # the single-use artifact — the second claim would then fail on an
  # already-consumed file, defeating a legitimately-authorized retry.
  local pm_override_claimed_this_call=false
  local work_evidence_dir="$evidence_dir"
  local work_c0_dir="$evidence_dir/c0/codex"
  local root_manifest="$evidence_dir/c0/codex/audit-input-manifest.json"
  local manifest_for_call="$root_manifest"

  if [[ -n "$attempt_n" ]]; then
    [[ "$attempt_n" =~ ^[1-9][0-9]*$ ]] \
      || { echo "PRECONDITION FAIL: AID_C0_ATTEMPT must be a positive integer (got: $attempt_n)" >&2; exit 1; }

    # Terminal-outcome guard (Part B, mirrors aid-c3-dispatch.sh's identical
    # round-1-6-hardened guard exactly, including its ALLOWLIST polarity —
    # see that file's own header comment for the full rationale). Only two
    # values are KNOWN-SAFE to proceed on without an override — "" (a
    # genuinely in-progress loop) and "unverifiable" (not a loop iteration,
    # must stay freely retriable). Every other value — recognized-terminal
    # ("clean"/"escalated") or not — requires an explicit, auditable,
    # PM-authorized override.
    local existing_summary="$evidence_dir/c0/loop-summary.json"
    if [[ -f "$existing_summary" ]]; then
      if ! jq -e 'type == "object"' "$existing_summary" >/dev/null 2>&1; then
        echo "PRECONDITION FAIL: c0/loop-summary.json exists but is not a valid JSON object — cannot determine loop state; refusing further automatic dispatch (bounded-loop requirement: state must be provably safe, never assumed)." >&2
        exit 1
      fi
      local prior_loop_outcome
      prior_loop_outcome="$(jq -r '.outcome // ""' "$existing_summary" 2>/dev/null)" || prior_loop_outcome=""
      if [[ "$prior_loop_outcome" != "" && "$prior_loop_outcome" != "unverifiable" ]]; then
        local guard_project_root guard_plan_id
        guard_project_root="$(git -C "$evidence_dir" rev-parse --show-toplevel 2>/dev/null || echo "")"
        guard_plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$root_manifest" 2>/dev/null || echo "")"
        if ! _c0_try_claim_override "$guard_project_root" "$guard_plan_id" "a recorded terminal outcome (\"$prior_loop_outcome\")"; then
          echo "PRECONDITION FAIL: c0/loop-summary.json already recorded outcome=\"$prior_loop_outcome\" for this evidence dir — automatic further C0 dispatches are rejected (bounded-loop requirement: only an in-progress or \"unverifiable\" outcome may proceed without override; \"$prior_loop_outcome\" is treated as terminal, whether or not it is a recognized value)." >&2
          echo "Fix: a further attempt requires a genuine, single-use PM-escalation override artifact: \${plan_evidence_root}/cp1-pm-escalation-override.json with a pm_ref >= 20 chars — not a bare environment variable." >&2
          exit 1
        fi
        pm_override_claimed_this_call=true
      fi
    fi

    attempt_explicit=1
    attempt_nn="$(printf '%02d' "$attempt_n")"
    attempt_dir="$evidence_dir/c0/attempt-$attempt_nn"

    # Collision guard — reusing a dispatched slot is a PRECONDITION FAIL.
    if [[ -f "$attempt_dir/c0/c0-dispatch.json" ]]; then
      local prior_outcome
      # CP2 round-9f finding (mirrors the identical fix in aid-c3-dispatch.sh):
      # guarded like every other jq read in this file. A corrupted/torn
      # c0-dispatch.json cannot possibly BE a genuinely completed prior
      # dispatch (the writer always writes valid JSON atomically via
      # temp+mv), so falling back to "" (not dispatched, retry allowed) on a
      # read failure is the semantically correct default.
      prior_outcome="$(jq -r '.dispatch.outcome // ""' "$attempt_dir/c0/c0-dispatch.json" 2>/dev/null)" || prior_outcome=""
      if [[ "$prior_outcome" == "dispatched" ]]; then
        echo "PRECONDITION FAIL: c0/attempt-$attempt_nn already recorded a completed dispatch (outcome=dispatched); refusing to reuse — pass a new AID_C0_ATTEMPT" >&2
        exit 1
      fi
    fi

    mkdir -p "$attempt_dir/c0" || { echo "PRECONDITION FAIL: cannot create $attempt_dir/c0" >&2; exit 1; }
    # Seal this attempt's OWN manifest snapshot so a later `verify` against
    # attempt_dir alone is self-contained.
    _c0_copy_atomic "$root_manifest" "$attempt_dir/c0/audit-input-manifest.json" \
      || { echo "PRECONDITION FAIL: cannot seal audit-input-manifest.json into $attempt_dir" >&2; exit 1; }

    work_evidence_dir="$attempt_dir"
    work_c0_dir="$attempt_dir/c0"
    manifest_for_call="$attempt_dir/c0/audit-input-manifest.json"
  fi

  local manifest="$root_manifest"
  [[ -f "$manifest" ]] || { echo "PRECONDITION FAIL: manifest missing (run build-manifest first): $manifest" >&2; exit 1; }

  local c0_dir="$work_c0_dir"
  mkdir -p "$c0_dir" || { echo "PRECONDITION FAIL: cannot create $c0_dir" >&2; exit 1; }

  local risk_profile reviewed_head
  risk_profile="$(jq -r '.audit_input_manifest.c0_plan_review_input.risk_profile // "low"' "$manifest_for_call")"
  reviewed_head="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head // ""' "$manifest_for_call")"
  [[ -n "$reviewed_head" ]] || { echo "PRECONDITION FAIL: manifest has no reviewed_head" >&2; exit 1; }

  # --- risk gate: low/docs profile → Codex NOT auto-run -----------------------
  if [[ "$risk_profile" != "high" && -z "${AID_C0_FORCE_REVIEW:-}" ]]; then
    echo "aid-c0-plan-review: risk_profile=$risk_profile (not high) and AID_C0_FORCE_REVIEW unset — skipping Codex plan review." >&2
    _c0_write_skipped "$work_evidence_dir" "$manifest_for_call" \
      || { echo "PRECONDITION FAIL: cannot write skipped c0-plan-review.json" >&2; exit 1; }
    if [[ "$attempt_explicit" -eq 1 ]]; then
      _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
        "" "$reviewed_head" "skipped(profile)" || true
    fi
    echo "$evidence_dir/c0-plan-review.json"
    return 0
  fi

  local project_root
  project_root="$(git -C "$evidence_dir" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "PRECONDITION FAIL: evidence_dir is not inside a git repository: $evidence_dir" >&2; exit 1; }

  # SAME-HASH RE-DISPATCH GUARD (7th + 8th DONE-review audits, P065
  # E-065-7_7: "C0 bounded review lifecycle" finding). The CP1 ledger's own
  # `increment` is correctly a no-op for an unchanged plan_hash (that's a
  # deliberate, already-tested design choice — see aid-cp1-ledger.sh's NOTE
  # at cmd_increment), but that no-op only protects the BUDGET COUNTER.
  # Nothing previously stopped a caller from dispatching to Codex repeatedly
  # for the SAME unchanged plan_hash — at zero ledger cost — until a
  # favorable review happened to come back, then simply not dispatching
  # again: budget-free fishing for a pass on an unrevised plan.
  #
  # APPLIES TO BOTH MODES (fixed after the 8th audit — the 7th-audit fix
  # scoped this to legacy mode only, reasoning that attempt-explicit mode's
  # terminal-outcome guard above was already adequate; the 8th audit
  # correctly found that reasoning incomplete). The terminal-outcome guard
  # only rejects retrying after a TERMINAL outcome ("clean"/"escalated");
  # loop-summary's outcome is `null` (read back as "" by the guard above)
  # for a genuinely-dispatched-but-still-blocking, non-escalated result —
  # indistinguishable there from "never dispatched yet". That let
  # attempt-explicit mode retry the SAME unrevised hash indefinitely after
  # a blocking (non-terminal) review, same budget-free fishing gap, just in
  # the other mode. The ledger-tip-hash check below is a strictly separate,
  # additional guard that closes this in BOTH modes uniformly, using the
  # SAME authoritative signal (was this exact hash EVER genuinely
  # dispatched, per the ledger's own attempts_log — which is never written
  # for transport failures/"unverifiable" results, so those remain freely
  # retriable at the same hash exactly as before, in both modes).
  #
  # Uses the ledger's own last recorded hash for this plan_id (read-only —
  # `read` never mutates or consumes the ledger); a genuine, single-use PM
  # override path is provided via _c0_try_claim_override (9th DONE-review
  # audit fix — see that function's header). A plan_id with no ledger yet
  # (first-ever dispatch) has nothing to compare against and proceeds
  # normally.
  local c0_plan_id c0_reviewed_plan_hash
  c0_plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest_for_call" 2>/dev/null || echo "")"
  c0_reviewed_plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest_for_call" 2>/dev/null || echo "")"
  if [[ -n "$c0_plan_id" && -n "$c0_reviewed_plan_hash" ]]; then
    local ledger_read_json="" ledger_read_rc=0
    ledger_read_json="$(bash "$C0_LEDGER_BIN" read --project-root "$project_root" "$c0_plan_id" 2>/dev/null)" || ledger_read_rc=$?
    if [[ "$ledger_read_rc" -eq 0 && -n "$ledger_read_json" ]]; then
      local c0_last_hash
      c0_last_hash="$(jq -r '.attempts_log[-1].plan_hash // ""' <<<"$ledger_read_json" 2>/dev/null || echo "")"
      if [[ -n "$c0_last_hash" && "$c0_last_hash" == "$c0_reviewed_plan_hash" && "$pm_override_claimed_this_call" != true ]]; then
        if ! _c0_try_claim_override "$project_root" "$c0_plan_id" "a same-hash re-dispatch ($c0_reviewed_plan_hash)"; then
          echo "PRECONDITION FAIL: plan_hash $c0_reviewed_plan_hash for plan_id=$c0_plan_id already has a recorded ledger attempt at this exact hash — refusing to re-dispatch an unchanged plan to Codex (a same-hash re-run cannot consume ledger budget, so nothing else stops repeated re-dispatch of an unchanged plan hoping for a favorable review by chance)." >&2
          echo "Fix: change the plan (new plan_hash) before dispatching again, or provide a genuine, single-use PM-escalation override artifact: \${plan_evidence_root}/cp1-pm-escalation-override.json with a pm_ref >= 20 chars — not a bare environment variable." >&2
          exit 1
        fi
        pm_override_claimed_this_call=true
      fi
    fi
  fi

  local manifest_input_hash
  manifest_input_hash="sha256:$(sha256sum "$manifest_for_call" | awk '{print $1}')"

  # --- cross_provider PRE-CHECK for THIS run (never cached) -------------------
  local precheck_rc=0 precheck_out=""
  precheck_out="$("$C0_INDEPENDENCE_BIN" detect --required cross_provider 2>&1)" || precheck_rc=$?

  if [[ "$precheck_rc" -ne 0 ]]; then
    echo "aid-c0-plan-review: cross_provider unavailable this run (pre-check rc=$precheck_rc): $precheck_out" >&2
    _c0_write_dispatch_json "$work_c0_dir/c0-dispatch.json" "$project_root" "$reviewed_head" "$manifest_input_hash" \
      "" "" "" "" "false" "" "unavailable" "" "$CODEX_MODEL" "false" "" "" "unavailable"
    _c0_write_unverifiable "$work_evidence_dir" "$manifest_for_call" unavailable "unavailable" "" "" "" || true
    if [[ "$attempt_explicit" -eq 1 ]]; then
      _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
        "" "$reviewed_head" unavailable || true
    fi
    exit 2
  fi

  # --- render the sealed C0 prompt DETERMINISTICALLY --------------------------
  local plan_file_rel reviewed_plan_hash plan_graph_rel contracts_str c0_evidence_str
  plan_file_rel="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_file // ""' "$manifest_for_call")"
  reviewed_plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest_for_call")"
  # `plan_graph` is EITHER a {path,sha256,size} seal (graph present) OR the
  # status string `absent_pre_generation` (P068 Step 1). Indexing a string with
  # `.path` is a jq ERROR, not a null — so the shape is branched on explicitly
  # and the status string is passed through to the prompt verbatim, telling the
  # reviewer why there is no graph rather than handing it an empty path.
  plan_graph_rel="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph
                             | if type == "object" then (.path // "") else (. // "") end' "$manifest_for_call")"
  contracts_str="$(jq -r '.audit_input_manifest.c0_plan_review_input.contracts // [] | join(", ")' "$manifest_for_call")"
  c0_evidence_str="$(jq -r '.audit_input_manifest.c0_plan_review_input.c0_evidence // [] | join(", ")' "$manifest_for_call")"

  local output_schema_path input_manifest_path_rel
  output_schema_path="$(realpath -m --relative-to="$project_root" "$C0_RESPONSE_SCHEMA" 2>/dev/null || echo "$C0_RESPONSE_SCHEMA")"
  input_manifest_path_rel="$(realpath -m --relative-to="$project_root" "$manifest_for_call" 2>/dev/null || echo "$manifest_for_call")"

  local vars_json="$work_c0_dir/codex-prompt-vars.json"
  jq -n \
    --arg plan_path "$plan_file_rel" \
    --arg plan_sha256 "$reviewed_plan_hash" \
    --arg reviewed_head "$reviewed_head" \
    --arg input_manifest_path "$input_manifest_path_rel" \
    --arg input_manifest_hash "$manifest_input_hash" \
    --arg plan_graph_path "$plan_graph_rel" \
    --arg contracts_paths "$contracts_str" \
    --arg c0_evidence_paths "$c0_evidence_str" \
    --arg output_schema_path "$output_schema_path" \
    '{plan_path:$plan_path, plan_sha256:$plan_sha256, reviewed_head:$reviewed_head,
      input_manifest_path:$input_manifest_path, input_manifest_hash:$input_manifest_hash,
      plan_graph_path:$plan_graph_path, contracts_paths:$contracts_paths,
      c0_evidence_paths:$c0_evidence_paths, output_schema_path:$output_schema_path}' \
    > "$vars_json" || { echo "PRECONDITION FAIL: cannot assemble prompt vars" >&2; exit 1; }

  local prompt_file="$work_c0_dir/codex-prompt.txt"
  local render_prov=""
  local template_id="" template_sha256="" rendered_prompt_sha256=""
  if render_prov="$(bash "$C0_RENDER_PROMPT" --template "$C0_PROMPT_TEMPLATE" --vars-json "$vars_json" --output "$prompt_file" 2>&1)"; then
    template_id="$(printf '%s' "$render_prov" | jq -r '.template_id // ""' 2>/dev/null)"
    template_sha256="$(printf '%s' "$render_prov" | jq -r '.template_sha256 // ""' 2>/dev/null)"
    rendered_prompt_sha256="$(printf '%s' "$render_prov" | jq -r '.rendered_prompt_sha256 // ""' 2>/dev/null)"
  else
    echo "aid-c0-plan-review: prompt render failed: $render_prov" >&2
    _c0_write_dispatch_json "$work_c0_dir/c0-dispatch.json" "$project_root" "$reviewed_head" "$manifest_input_hash" \
      "" "" "" "" "false" "" "render_failed" "" "$CODEX_MODEL" "false" "" "" "unavailable"
    _c0_write_unverifiable "$work_evidence_dir" "$manifest_for_call" unavailable "unavailable" "" "" "" || true
    if [[ "$attempt_explicit" -eq 1 ]]; then
      _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
        "" "$reviewed_head" render_failed || true
    fi
    exit 2
  fi

  local codex_version
  codex_version="$(codex --version 2>/dev/null || echo "")"

  local events_file="$work_c0_dir/codex-events.jsonl"
  local stderr_file="$work_c0_dir/codex-events.stderr"
  local last_msg_file="$work_c0_dir/codex-last-message.json"
  rm -f "$events_file" "$stderr_file" "$last_msg_file"

  local codex_rc=0
  _run_codex_isolated "$project_root" "$prompt_file" "$events_file" "$stderr_file" "$last_msg_file" \
    || codex_rc=$?

  local session_id events_valid outcome achieved
  session_id="$(_session_id_of "$events_file")" || session_id=""
  events_valid="$(_events_valid_of "$events_file")"

  if [[ "$codex_rc" -eq 124 ]]; then
    outcome="timeout"
    events_valid="false"
  elif [[ "$events_valid" == "true" ]]; then
    outcome="dispatched"
  elif _looks_rate_limited "$events_file" "$stderr_file"; then
    outcome="rate_limited"
  else
    outcome="failed"
  fi

  if [[ "$events_valid" == "true" ]]; then
    achieved="cross_provider"
  else
    achieved="unavailable"
  fi

  local stdout_sha256="" raw_response_sha256=""
  [[ -s "$events_file" ]]   && stdout_sha256="sha256:$(sha256sum "$events_file"   | awk '{print $1}')"
  [[ -f "$last_msg_file" ]] && raw_response_sha256="sha256:$(sha256sum "$last_msg_file" | awk '{print $1}')"

  _c0_write_dispatch_json "$work_c0_dir/c0-dispatch.json" "$project_root" "$reviewed_head" "$manifest_input_hash" \
    "$template_id" "$template_sha256" "$rendered_prompt_sha256" "$codex_version" \
    "true" "$codex_rc" "$outcome" "$session_id" "$CODEX_MODEL" "$events_valid" \
    "$stdout_sha256" "$raw_response_sha256" "$achieved" \
    || { echo "PRECONDITION FAIL: cannot write c0-dispatch.json" >&2; exit 1; }

  local presp_rc=0
  _c0_process_response "$work_evidence_dir" "$manifest_for_call" "$codex_rc" "$events_valid" \
    "$outcome" "$achieved" "$session_id" "$reviewed_head" "$work_c0_dir" || presp_rc=$?

  # FINDING 1 FIX: Mechanically increment the CP1 ledger for a genuine
  # dispatch. This closes the gap: before this fix, the ledger was never
  # incremented by code, only mentioned in prose. Now every real dispatch
  # also advances the counter.
  #
  # CP2 (round-4 re-review) found `outcome == "dispatched"` alone is too
  # broad a gate: `outcome` is a pure TRANSPORT-level signal (Codex's CLI
  # event stream was well-formed) — it says nothing about whether the
  # RESPONSE CONTENT then passed validation (hash binding, schema). A
  # transport-genuine-but-content-invalid response (`_c0_process_response`
  # writes `review_status: "unverifiable"`) would have incremented the
  # ledger under the outcome-only check — contradicting BOTH this file's
  # own carve-out below AND the plan's own Step 20 spec ("Codex
  # unavailable/timeout/invalid does not increment the ledger"), which
  # explicitly groups "invalid" alongside true transport failures for C0
  # (unlike C3's sibling EPIC 6 system, which evolved a DIFFERENT,
  # deliberately more nuanced budget rule for its own "genuinely dispatched
  # but invalid content" case in a later round — C0's spec never asked for
  # that distinction). Gate on the ACTUAL WRITTEN report's `review_status`,
  # not the transport-level `outcome` alone.
  # Read from work_evidence_dir (the CURRENT attempt's own report), not the
  # canonical evidence_dir root — in attempt mode these diverge until
  # _c0_finalize_attempt copies the attempt's report to the root at the end
  # of this function; reading the root here would check a stale/prior
  # attempt's report instead of this dispatch's own (P065 E-065-7_7
  # DONE-review Finding 2 Part A, CP2 round-9).
  local report_review_status=""
  report_review_status="$(jq -r '.review_status // ""' "$work_evidence_dir/c0-plan-review.json" 2>/dev/null || echo "")"
  if [[ "$outcome" == "dispatched" && "$report_review_status" != "unverifiable" ]]; then
    local plan_id plan_hash ledger_rc=0
    plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest_for_call" 2>/dev/null || echo "")"
    plan_hash="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash // ""' "$manifest_for_call" 2>/dev/null || echo "")"

    if [[ -z "$plan_id" || -z "$plan_hash" ]]; then
      echo "PRECONDITION FAIL: cannot extract plan_id or plan_hash from manifest for ledger increment" >&2
      _c0_write_unverifiable "$work_evidence_dir" "$manifest_for_call" ledger_increment_failed "$achieved" "$session_id" "" "" || true
      if [[ "$attempt_explicit" -eq 1 ]]; then
        _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
          "$session_id" "$reviewed_head" "$outcome" || true
      fi
      exit 2
    fi

    if ! bash "$C0_LEDGER_BIN" increment --project-root "$project_root" --codex-session "$session_id" "$plan_id" "$plan_hash" >/dev/null 2>&1; then
      ledger_rc=$?
      echo "aid-c0-plan-review: ledger increment failed (rc=$ledger_rc) for plan_id=$plan_id — dispatched codex response is unverifiable without a recorded loop iteration" >&2
      _c0_write_unverifiable "$work_evidence_dir" "$manifest_for_call" ledger_increment_failed "$achieved" "$session_id" "" "" || true
      if [[ "$attempt_explicit" -eq 1 ]]; then
        _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
          "$session_id" "$reviewed_head" "$outcome" || true
      fi
      exit 2
    fi
  fi

  echo "$work_c0_dir/c0-dispatch.json"

  # --- finalize attempt: copy to canonical path if attempt_explicit -------
  if [[ "$attempt_explicit" -eq 1 ]]; then
    if ! _c0_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$root_manifest" "$attempt_n" "$attempt_nn" \
           "$session_id" "$reviewed_head" "$outcome"; then
      exit 2
    fi
  fi

  # 12th DONE-review audit fix ("C0 dispatch lifecycle / fail-closed exit
  # contract"): $presp_rc (captured above from _c0_process_response, "||
  # presp_rc=$?") was computed but never checked here — the exit code
  # decision looked ONLY at $outcome, a pure TRANSPORT-level signal (did
  # the Codex CLI call itself succeed). A transport-genuine but
  # content-invalid response (hash mismatch, head mismatch, C3-shaped
  # output, missing action_owner, etc.) makes _c0_process_response write
  # review_status:"unverifiable" to the report AND return non-zero — but
  # this function still returned 0, telling the caller the dispatch was
  # clean when the actual written report says otherwise. The ledger-
  # increment gate a few lines above already correctly reads the WRITTEN
  # report's review_status for exactly this reason (see FINDING 1 FIX
  # comment above) — this closes the same gap for the function's own exit
  # code. $report_review_status was already read from the CURRENT
  # attempt's own report earlier in this function; reused here rather than
  # re-read, since _c0_finalize_attempt only copies that report to the
  # canonical root, it never mutates the attempt's own copy.
  if [[ "$outcome" == "dispatched" && "$presp_rc" -eq 0 && "$report_review_status" != "unverifiable" ]]; then
    return 0
  else
    exit 2
  fi
}

# ===========================================================================
# cmd_verify [--reference] <evidence_dir>
# ===========================================================================

# _c0_vfail <reason>  — emit a verify failure reason on stderr and exit 2.
_c0_vfail() {
  echo "verify: NOT verified — $1" >&2
  exit 2
}

_c0_file_sha_pref() {
  local f="$1"
  [[ -f "$f" && -r "$f" ]] || { printf ''; return 0; }
  printf 'sha256:%s' "$(sha256sum "$f" | awk '{print $1}')"
}

cmd_verify() {
  command -v jq        >/dev/null 2>&1 || _c0_vfail "jq not found in PATH"
  command -v sha256sum >/dev/null 2>&1 || _c0_vfail "sha256sum not found in PATH"

  local reference=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reference) reference=1; shift ;;
      --)          shift; break ;;
      -*)          _c0_vfail "unknown flag: $1" ;;
      *)           break ;;
    esac
  done
  local evidence_dir="${1:-}"
  [[ -n "$evidence_dir" ]] || _c0_vfail "usage: verify [--reference] <evidence_dir>"
  [[ -d "$evidence_dir" ]] || _c0_vfail "evidence_dir not a directory: $evidence_dir"

  local c0_dir="$evidence_dir/c0/codex"
  local report="$evidence_dir/c0-plan-review.json"

  # --- Step 0 (P065 E-065-7_7 DONE-review Finding B): resolve the CURRENT
  # attempt's raw-evidence directory, if this evidence_dir has ever used
  # AID_C0_ATTEMPT layering. Raw dispatch artifacts (c0-dispatch.json,
  # codex-last-message.json, codex-events.jsonl, codex-prompt.txt, and the
  # sealed audit-input-manifest.json) are written ONLY under
  # c0/attempt-NN/c0/ — never mirrored to the canonical c0/codex/ location —
  # so a plain `verify <evidence_dir>` after an attempt-mode dispatch must
  # read them from there. c0/loop-summary.json's current_attempt (set by
  # _c0_write_loop_summary, unconditionally, on every _c0_finalize_attempt
  # call) is the single source of truth for "which attempt is canonical
  # right now." Absent entirely (this evidence_dir never used
  # AID_C0_ATTEMPT) → unchanged legacy behavior.
  local loop_summary="$evidence_dir/c0/loop-summary.json"
  if [[ -f "$loop_summary" ]]; then
    # CP2 round-9e finding (found in aid-c3-dispatch.sh's mirror of this exact
    # block, same fix applied here): `jq -e .` alone accepts any
    # syntactically-valid JSON — including a bare array/scalar/bool, e.g.
    # from a truncated or partial write — which then crashed the UNGUARDED
    # read below under `set -euo pipefail`. Require the top-level value to
    # actually be an object, AND guard the read itself (belt + suspenders,
    # matching every other jq call in this file's `cmd || var=default`
    # idiom) so a corrupted file fails closed with a clean message, never a
    # raw crash.
    jq -e 'type == "object"' "$loop_summary" >/dev/null 2>&1 \
      || _c0_vfail "c0/loop-summary.json is not a valid JSON object"
    local cur_attempt
    cur_attempt="$(jq -r '.current_attempt // empty' "$loop_summary" 2>/dev/null)" || cur_attempt=""
    if [[ -n "$cur_attempt" ]]; then
      [[ "$cur_attempt" =~ ^[1-9][0-9]*$ ]] \
        || _c0_vfail "c0/loop-summary.json current_attempt is not a positive integer: $cur_attempt"
      local cur_nn resolved_attempt_dir
      cur_nn="$(printf '%02d' "$cur_attempt")"
      resolved_attempt_dir="$evidence_dir/c0/attempt-$cur_nn"
      [[ -d "$resolved_attempt_dir" ]] \
        || _c0_vfail "c0/loop-summary.json points at attempt-$cur_nn but c0/attempt-$cur_nn/ is missing"
      # The canonical report must be EXACTLY this attempt's own report — a
      # diverged pointer or a stale/hand-copied canonical report must fail
      # closed rather than silently verify raw evidence against the wrong
      # report.
      [[ -f "$resolved_attempt_dir/c0-plan-review.json" ]] \
        || _c0_vfail "c0/attempt-$cur_nn/c0-plan-review.json is missing"
      cmp -s "$resolved_attempt_dir/c0-plan-review.json" "$report" \
        || _c0_vfail "canonical c0-plan-review.json does not match c0/attempt-$cur_nn/c0-plan-review.json (report and raw evidence must come from the same attempt)"
      c0_dir="$resolved_attempt_dir/c0"
    fi
  fi

  local dispatch_json="$c0_dir/c0-dispatch.json"
  local last_msg="$c0_dir/codex-last-message.json"
  local events="$c0_dir/codex-events.jsonl"
  local manifest="$c0_dir/audit-input-manifest.json"

  local f
  for f in "$dispatch_json" "$report" "$last_msg" "$events" "$manifest"; do
    [[ -f "$f" ]] || _c0_vfail "required artifact missing: ${f#"$evidence_dir"/}"
  done
  jq -e . "$dispatch_json" >/dev/null 2>&1 || _c0_vfail "c0-dispatch.json is not valid JSON"
  jq -e . "$report"        >/dev/null 2>&1 || _c0_vfail "c0-plan-review.json is not valid JSON"
  jq -e . "$manifest"      >/dev/null 2>&1 || _c0_vfail "audit-input-manifest.json is not valid JSON"

  local d_invoked d_exit d_outcome d_events_valid d_session d_indep
  d_invoked="$(jq -r '.dispatch.invoked'       "$dispatch_json" 2>/dev/null || true)"
  d_exit="$(jq -r '.dispatch.exit_code'        "$dispatch_json" 2>/dev/null || true)"
  d_outcome="$(jq -r '.dispatch.outcome'       "$dispatch_json" 2>/dev/null || true)"
  d_events_valid="$(jq -r '.dispatch.events_valid' "$dispatch_json" 2>/dev/null || true)"
  d_session="$(jq -r '.dispatch.codex_session_id // ""' "$dispatch_json" 2>/dev/null || true)"
  d_indep="$(jq -r '.independence.achieved_independence_level' "$dispatch_json" 2>/dev/null || true)"
  [[ "$d_invoked" == "true" ]]              || _c0_vfail "dispatch.invoked != true (codex was not invoked)"
  [[ "$d_exit" == "0" ]]                    || _c0_vfail "dispatch.exit_code != 0 (codex exited: $d_exit)"
  [[ "$d_outcome" == "dispatched" ]]        || _c0_vfail "dispatch.outcome != dispatched (: $d_outcome)"
  [[ "$d_events_valid" == "true" ]]         || _c0_vfail "dispatch.events_valid != true"
  [[ -n "$d_session" && "$d_session" != "null" ]] || _c0_vfail "dispatch.codex_session_id is empty"
  [[ "$d_indep" == "cross_provider" ]]      || _c0_vfail "achieved_independence_level != cross_provider (: $d_indep)"

  local d_stdout_sha d_raw_sha events_sha last_sha
  d_stdout_sha="$(jq -r '.dispatch.stdout_sha256 // ""'       "$dispatch_json" 2>/dev/null || true)"
  d_raw_sha="$(jq -r '.dispatch.raw_response_sha256 // ""'    "$dispatch_json" 2>/dev/null || true)"
  events_sha="$(_c0_file_sha_pref "$events")"
  last_sha="$(_c0_file_sha_pref "$last_msg")"
  [[ -n "$d_stdout_sha" && "$d_stdout_sha" == "$events_sha" ]] \
    || _c0_vfail "stdout_sha256 != sha256(codex-events.jsonl) (event stream swapped/edited)"
  [[ -n "$d_raw_sha" && "$d_raw_sha" == "$last_sha" ]] \
    || _c0_vfail "raw_response_sha256 != sha256(codex-last-message.json) (raw response swapped/edited)"

  _c0_validate_response "$last_msg" || _c0_vfail "raw response fails the trusted _c0_validate_response gate"

  local project_id plan_id
  project_id="$(jq -r '.identity.project_id // "unknown"' "$manifest" 2>/dev/null || true)"
  [[ -n "$project_id" && "$project_id" != "null" ]] || project_id="unknown"
  plan_id="$(jq -r '.audit_input_manifest.c0_plan_review_input.plan_id // ""' "$manifest" 2>/dev/null || true)"

  local expected exp_status exp_review_status r_status r_review_status
  expected="$(_c0_derive_semantics "$last_msg")" \
    || _c0_vfail "cannot derive expected report semantics from the raw response"
  exp_status="$(jq -r '.status' <<<"$expected" 2>/dev/null)"
  exp_review_status="$(jq -r '.review_status' <<<"$expected" 2>/dev/null)"
  r_review_status="$(jq -r '.review_status' "$report" 2>/dev/null || true)"
  [[ "$r_review_status" == "$exp_review_status" ]] \
    || _c0_vfail "review_status != expected-from-raw (report:${r_review_status} expected:${exp_review_status})"

  if [[ "$exp_status" == "unverifiable" ]]; then
    _c0_vfail "raw response derives to unverifiable — a dispatched=true chain must never reach this branch"
  fi

  # faithful-transform equality — report <-> raw
  local r_plan_hash r_head r_imh r_block raw_plan_hash raw_head raw_imh raw_block
  r_plan_hash="$(jq -r '.reviewed_plan_hash // ""'    "$report" 2>/dev/null || true)"
  r_head="$(jq -r '.reviewed_head // ""'              "$report" 2>/dev/null || true)"
  r_imh="$(jq -r '.input_manifest_hash // ""'         "$report" 2>/dev/null || true)"
  r_block="$(jq -r '.blocking_findings'               "$report" 2>/dev/null || true)"
  raw_plan_hash="$(jq -r '.reviewed_plan_hash // ""'  "$last_msg" 2>/dev/null || true)"
  raw_head="$(jq -r '.reviewed_head // ""'            "$last_msg" 2>/dev/null || true)"
  raw_imh="$(jq -r '.input_manifest_hash // ""'       "$last_msg" 2>/dev/null || true)"
  [[ "$r_plan_hash" == "$raw_plan_hash" ]] || _c0_vfail "reviewed_plan_hash != raw.reviewed_plan_hash"
  [[ "$r_head" == "$raw_head" ]]           || _c0_vfail "reviewed_head != raw.reviewed_head"
  [[ "$r_imh" == "$raw_imh" ]]             || _c0_vfail "input_manifest_hash != raw.input_manifest_hash"

  raw_block="$(jq -r '[.findings[] | select(.severity=="critical" or .severity=="high")] | length > 0' "$last_msg" 2>/dev/null || true)"
  [[ "$r_block" == "$raw_block" ]] || _c0_vfail "blocking_findings != (exists raw crit/high finding)"

  local raw_tuples report_tuples
  raw_tuples="$(jq -Sc '[.findings[] | {severity,area,finding,recommendation}
                          + (if has("action_owner") then {action_owner} else {} end)] | sort' \
                "$last_msg" 2>/dev/null || true)"
  report_tuples="$(jq -Sc '[.findings[] | {severity,area,finding,recommendation}
                             + (if has("action_owner") then {action_owner} else {} end)] | sort' \
                   "$report" 2>/dev/null || true)"
  [[ -n "$raw_tuples" && "$raw_tuples" == "$report_tuples" ]] \
    || _c0_vfail "report findings tuple-set diverges from raw (a finding was added/removed/edited)"

  local raw_count report_count
  raw_count="$(jq '.findings | length'    "$last_msg" 2>/dev/null || true)"
  report_count="$(jq '.findings | length' "$report"   2>/dev/null || true)"
  [[ "$raw_count" =~ ^[0-9]+$ && "$report_count" =~ ^[0-9]+$ ]] || _c0_vfail "cannot count findings"
  [[ "$raw_count" == "$report_count" ]] || _c0_vfail "report/raw finding count differ ($report_count vs $raw_count)"

  local fp_helper="$SCRIPT_DIR/aid-finding-fingerprint.sh"
  local n sev area finding rec occ_expected fp_expected occ_actual fp_actual
  for (( n=0; n<raw_count; n++ )); do
    sev="$(jq -r --argjson i "$n" '.findings[$i].severity'       "$last_msg" 2>/dev/null || true)"
    area="$(jq -r --argjson i "$n" '.findings[$i].area'          "$last_msg" 2>/dev/null || true)"
    finding="$(jq -r --argjson i "$n" '.findings[$i].finding'    "$last_msg" 2>/dev/null || true)"
    rec="$(jq -r --argjson i "$n" '.findings[$i].recommendation' "$last_msg" 2>/dev/null || true)"
    occ_expected="c0-${plan_id}-${n}"
    fp_expected="$(bash "$fp_helper" fingerprint_audit_report "$project_id" c0_plan_review "$occ_expected" "$sev" "$area" "$finding" "$rec" 2>/dev/null)" \
      || _c0_vfail "cannot recompute fingerprint for finding $n"
    fp_expected="${fp_expected%$'\n'}"
    occ_actual="$(jq -r --argjson i "$n" '.findings[$i].occurrence_id // ""' "$report" 2>/dev/null || true)"
    fp_actual="$(jq -r --argjson i "$n" '.findings[$i].fingerprint // ""'    "$report" 2>/dev/null || true)"
    [[ "$occ_actual" == "$occ_expected" ]] || _c0_vfail "finding $n occurrence_id mismatch (got '$occ_actual', expected '$occ_expected')"
    [[ "$fp_actual" == "$fp_expected" ]]    || _c0_vfail "finding $n fingerprint does not recompute from the raw finding"
  done

  # prompt-template freshness
  local d_tpl_sha d_rendered_sha cur_tpl_sha cur_rendered_sha prompt_txt
  d_tpl_sha="$(jq -r '.prompt.template_sha256 // ""'        "$dispatch_json" 2>/dev/null || true)"
  d_rendered_sha="$(jq -r '.prompt.rendered_prompt_sha256 // ""' "$dispatch_json" 2>/dev/null || true)"
  [[ -f "$C0_PROMPT_TEMPLATE" ]] || _c0_vfail "prompt template missing: $C0_PROMPT_TEMPLATE"
  cur_tpl_sha="$(_c0_file_sha_pref "$C0_PROMPT_TEMPLATE")"
  [[ -n "$d_tpl_sha" && "$d_tpl_sha" == "$cur_tpl_sha" ]] \
    || _c0_vfail "prompt template changed since dispatch (template_sha256 stale) — re-run the review"
  prompt_txt="$c0_dir/codex-prompt.txt"
  [[ -f "$prompt_txt" ]] || _c0_vfail "rendered prompt missing: c0/codex/codex-prompt.txt"
  cur_rendered_sha="$(_c0_file_sha_pref "$prompt_txt")"
  [[ -n "$d_rendered_sha" && "$d_rendered_sha" == "$cur_rendered_sha" ]] \
    || _c0_vfail "rendered prompt edited (rendered_prompt_sha256 mismatch)"

  # input_manifest_hash chain: report/raw echo must match the LIVE manifest hash.
  local live_manifest_hash
  live_manifest_hash="sha256:$(sha256sum "$manifest" | awk '{print $1}')"
  [[ "$r_imh" == "$live_manifest_hash" ]] \
    || _c0_vfail "input_manifest_hash chain broken (report != sha256(manifest)) — manifest was altered since dispatch"

  # freshness (mode-dependent)
  local expected_head
  if [[ "$reference" -eq 1 ]]; then
    expected_head="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head // ""' "$manifest" 2>/dev/null || true)"
    [[ -n "$expected_head" ]] || _c0_vfail "manifest has no reviewed_head (reference mode)"
    [[ "$r_head" == "$expected_head" ]] \
      || _c0_vfail "reviewed_head != manifest.reviewed_head (reference-mode freshness)"
  else
    expected_head="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
    [[ -n "$expected_head" ]] || _c0_vfail "cannot resolve current HEAD (live mode)"
    [[ "$r_head" == "$expected_head" ]] \
      || _c0_vfail "reviewed_head != current HEAD (live-mode freshness — stale review)"
  fi

  echo "verified — codex session $d_session reviewed $r_head"
  return 0
}

# ===========================================================================
# main — overrides the sourced C3 main() (function redefinition wins).
# ===========================================================================
main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi
  local subcommand="$1"
  shift
  case "$subcommand" in
    build-manifest) cmd_build_manifest "$@" ;;
    dispatch)       cmd_dispatch "$@" ;;
    verify)         cmd_verify "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    *)
      echo "unknown subcommand: ${subcommand}" >&2
      usage >&2
      exit 1
      ;;
  esac
}

# Only run the CLI dispatcher when executed directly; when sourced (e.g. by the
# bats suite), just define the functions. Mirrors aid-c3-dispatch.sh's guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
