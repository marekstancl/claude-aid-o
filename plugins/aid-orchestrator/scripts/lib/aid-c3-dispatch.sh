#!/usr/bin/env bash
# =============================================================================
# aid-c3-dispatch.sh — C3 Cross-Provider Dispatch Bridge (P065, E-065-1_7)
#
# CLI skeleton for the C3 (independent audit) cross-provider dispatch bridge.
# Only the `build-manifest` subcommand is implemented in this step (Step 2 of
# the EPIC); `dispatch` and `verify` are LATER steps and are present here only
# as fail-closed stubs so the arg-dispatch scaffold is complete.
#
# ---------------------------------------------------------------------------
# build-manifest <evidence_dir> <base_sha> <head_sha> <risk_profile>
# ---------------------------------------------------------------------------
# Writes the four Codex brief files under <evidence_dir>/c3/ and a canonical
# hash-manifest (<evidence_dir>/audit-input-manifest.json) that records exactly
# what brief Codex is given and at what commit. The manifest is the
# provenance/integrity root the later `verify` step and the FSM bind the audit
# report to. It is NOT a sandbox — Codex reads the repo directly (a later step).
#
# The manifest carries BOTH:
#   (a) the EXISTING C3 producer-hook fields — allowlist[] / input_hash /
#       prior_pass_summaries / required_independence_level — formalised
#       VERBATIM from skills/pipeline.md §7 (the prose "C3 producer hook").
#       The advisory auditor's allowlist-only citation depends on the changed
#       source paths appearing in allowlist[], so this logic is unchanged.
#   (b) the NEW Codex brief provenance — base_sha / head_sha /
#       codex_brief_files[] ({path,sha256,size}) / codex_brief_hash /
#       allowed_recheck_commands / verification_budget.
#
# allowlist[] and codex_brief_files[] are DIFFERENT, intentional sets:
#   - allowlist[] = changed source paths ($AID_CHANGED_PATHS, verbatim) + this
#     run's evidence artifacts (final_report.md, gates_report.json, prior
#     verifier-output-*.md). It is what C3 may CITE.
#   - codex_brief_files[] = the four c3/ brief files Codex is GIVEN.
#
# Determinism (idempotency): every path sort uses `LC_ALL=C`; codex_brief_files[]
# is stored pre-sorted by path (jq -S canonicalises object KEYS, not array
# order); codex_brief_hash is sha256 over the jq -S -c canonical form of
# {base_sha,head_sha,codex_brief_files,required_independence_level}. Re-running
# build-manifest on identical inputs — and the later `verify` re-hash — reproduce
# byte-identical hashes across dev/CI/dogfood.
#
# Exit codes:
#   0 — manifest written and passed aid-protocol-validate.sh
#   1 — PRECONDITION FAIL (usage, non-git dir, unresolvable SHA, unreadable
#       brief source, or emitted manifest failed protocol validation) — no
#       audit-input-manifest.json is left behind on precondition failure.
#   2 — subcommand not yet implemented (dispatch / verify stubs)
#
# Environment (optional):
#   AID_CHANGED_PATHS   — file with one repo-relative changed path per line
#                         (same convention as the delivery gates). Missing/empty
#                         → allowlist:[] (existing behaviour); codex_brief_files
#                         is still built from the diff.
#   C3_AUDIT_POLICY     — override path to c3-audit-policy.yaml (test/CI seam,
#                         same convention as test-c3-audit.bats).
#   AID_PLAN_AC_FILE    — explicit source for c3/bundle-plan-ac.md. If set but
#                         unreadable → PRECONDITION FAIL. If unset, falls back to
#                         <evidence_dir>/final_report.md, then a deterministic stub.
#
# **Last Updated:** 2026-07-14
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$SCRIPT_DIR/../aid-protocol-validate.sh"
DEFAULT_POLICY="$PLUGIN_ROOT/defaults/policies/c3-audit-policy.yaml"

PRODUCER="orchestrator@done-review"
GENERATED_BY_TOOL="aid-c3-dispatch.sh#build-manifest"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: aid-c3-dispatch.sh <subcommand> [args...]

Subcommands:
  build-manifest <evidence_dir> <base_sha> <head_sha> <risk_profile>
      Write the Codex brief files under <evidence_dir>/c3/ and a canonical
      hash-manifest at <evidence_dir>/audit-input-manifest.json.

  dispatch, verify
      Not yet implemented (later EPIC steps).
EOF
}

# ---------------------------------------------------------------------------
# _fail <msg>  — emit a PRECONDITION FAIL message and exit 1.
# ---------------------------------------------------------------------------
_fail() {
  echo "PRECONDITION FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# _sha256 <file>   — bare 64-hex sha256 of a file's raw bytes (empty-string
#                    hash if the file is absent/unreadable — used for deleted
#                    changed-source paths in the allowlist input_hash).
# ---------------------------------------------------------------------------
_sha256_file() {
  local f="$1"
  if [[ -n "$f" && -f "$f" && -r "$f" ]]; then
    sha256sum "$f" | awk '{print $1}'
  else
    printf '' | sha256sum | awk '{print $1}'
  fi
}

# _sha256_str <string>  — bare 64-hex sha256 of the exact bytes of a string
#                         (no trailing newline).
_sha256_str() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# _path_is_within <root> <candidate>  — true iff <candidate> (relative or
# absolute) resolves to somewhere INSIDE <root>. Uses `realpath -m` so it
# works for not-yet-existing/deleted paths (a changed-path entry for a
# deleted file must still validate). CP3 security finding: AID_CHANGED_PATHS
# entries and AID_PLAN_AC_FILE both become citable evidence in the manifest
# (allowlist[]/input_hash and the Codex brief respectively) — an unvalidated
# "../../etc/passwd"-style or absolute entry would hash and expose real
# out-of-repo file content. Every path from either source MUST pass this
# check before being read or recorded.
_path_is_within() {
  local root="$1" candidate="$2" resolved
  resolved="$(realpath -m -- "$candidate" 2>/dev/null)" || return 1
  case "$resolved" in
    "$root"|"$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ===========================================================================
# cmd_build_manifest <evidence_dir> <base_sha> <head_sha> <risk_profile>
# ===========================================================================
cmd_build_manifest() {
  # --- Step 1: argument validation -----------------------------------------
  if [[ $# -ne 4 ]]; then
    usage >&2
    _fail "build-manifest requires exactly 4 args: <evidence_dir> <base_sha> <head_sha> <risk_profile>"
  fi

  local evidence_dir="$1"
  local base_sha_in="$2"
  local head_sha_in="$3"
  local risk_profile="$4"

  [[ -n "$evidence_dir" ]]  || _fail "evidence_dir is empty"
  [[ -n "$base_sha_in" ]]   || _fail "base_sha is empty"
  [[ -n "$head_sha_in" ]]   || _fail "head_sha is empty"
  [[ -n "$risk_profile" ]]  || _fail "risk_profile is empty"

  # Must be inside a git repo.
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || _fail "not a git repository (cwd: $(pwd))"

  # SHAs must resolve to real commit objects; normalise to full 40-hex.
  local base_sha head_sha
  base_sha="$(git rev-parse --verify --quiet "${base_sha_in}^{commit}" 2>/dev/null)" \
    || _fail "unresolvable base_sha: ${base_sha_in}"
  head_sha="$(git rev-parse --verify --quiet "${head_sha_in}^{commit}" 2>/dev/null)" \
    || _fail "unresolvable head_sha: ${head_sha_in}"

  # --- Step 2: create the c3/ brief directory ------------------------------
  local c3_dir="$evidence_dir/c3"
  mkdir -p "$c3_dir" || _fail "cannot create $c3_dir"

  # Absolute evidence dir (exists now — used for reading evidence artifacts).
  local evidence_abs
  evidence_abs="$(cd "$evidence_dir" && pwd)" || _fail "cannot resolve evidence_dir: $evidence_dir"

  # --- Step 5 (needed early for the review-profile stub): resolve the
  #     required independence level from policy (fail-closed cross_provider). --
  local policy_file="${C3_AUDIT_POLICY:-$DEFAULT_POLICY}"
  local required_independence_level=""
  if [[ -f "$policy_file" ]]; then
    required_independence_level="$(
      risk_profile="$risk_profile" \
        yq -r '.risk_profiles[strenv(risk_profile)].required_independence_level // ""' \
        "$policy_file" 2>/dev/null || echo ""
    )"
  fi
  case "$required_independence_level" in
    context_only|cross_model|cross_provider) ;;
    *) required_independence_level="cross_provider" ;;  # fail-closed (D9)
  esac

  # --- Identity: epic_id / run_id / project_id -----------------------------
  # epic_id/run_id: prefer fsm-state.yaml (authoritative), else derive from the
  # evidence_dir path structure (.aid-o/work/evidence/{epic_id}/{run_id}/).
  local epic_id="" run_id=""
  local state_file="$evidence_dir/fsm-state.yaml"
  if [[ -f "$state_file" ]]; then
    epic_id="$(yq -r '.epic_id // ""' "$state_file" 2>/dev/null || echo "")"
    run_id="$(yq -r '.run_id // ""' "$state_file" 2>/dev/null || echo "")"
    [[ "$epic_id" == "null" ]] && epic_id=""
    [[ "$run_id" == "null" ]] && run_id=""
  fi
  [[ -z "$epic_id" ]] && epic_id="$(basename "$(dirname "$evidence_abs")")"
  [[ -z "$run_id" ]]  && run_id="$(basename "$evidence_abs")"

  # project_id: from .aid-o/config/project.yaml under the repo; fall back to
  # "unknown" (non-empty — the validator rejects an empty identity.project_id).
  local project_id="" project_yaml=""
  project_yaml="$(find "$repo_root" -path '*/.aid-o/config/project.yaml' -print -quit 2>/dev/null || true)"
  if [[ -n "$project_yaml" && -f "$project_yaml" ]]; then
    project_id="$(yq -r '.project_id // ""' "$project_yaml" 2>/dev/null || echo "")"
  fi
  [[ -z "$project_id" || "$project_id" == "null" ]] && project_id="unknown"

  # --- Step 4: write the four Codex brief files ----------------------------
  # (a) bundle-diff.patch — full tree-to-tree diff base..head (deterministic:
  #     no external diff driver, no color).
  git diff --no-ext-diff --no-color "$base_sha" "$head_sha" > "$c3_dir/bundle-diff.patch" 2>/dev/null \
    || _fail "git diff failed for ${base_sha}..${head_sha}"

  # (b) bundle-scope.txt — changed paths, NUL-separated (--name-only -z).
  git diff --no-ext-diff --name-only -z "$base_sha" "$head_sha" > "$c3_dir/bundle-scope.txt" 2>/dev/null \
    || _fail "git diff --name-only failed for ${base_sha}..${head_sha}"

  # (c) bundle-plan-ac.md — plan + acceptance criteria brief.
  if [[ -n "${AID_PLAN_AC_FILE:-}" ]]; then
    [[ -f "$AID_PLAN_AC_FILE" && -r "$AID_PLAN_AC_FILE" ]] \
      || _fail "AID_PLAN_AC_FILE set but unreadable: $AID_PLAN_AC_FILE"
    _path_is_within "$repo_root" "$AID_PLAN_AC_FILE" \
      || _fail "AID_PLAN_AC_FILE escapes the repo (path traversal / absolute path rejected): $AID_PLAN_AC_FILE"
    cat "$AID_PLAN_AC_FILE" > "$c3_dir/bundle-plan-ac.md" \
      || _fail "cannot write bundle-plan-ac.md from $AID_PLAN_AC_FILE"
  elif [[ -f "$evidence_dir/final_report.md" ]]; then
    cat "$evidence_dir/final_report.md" > "$c3_dir/bundle-plan-ac.md" \
      || _fail "cannot write bundle-plan-ac.md from final_report.md"
  else
    printf '# Plan / Acceptance Criteria\n\n_No plan/AC source available at build-manifest time (epic=%s run=%s)._\n' \
      "$epic_id" "$run_id" > "$c3_dir/bundle-plan-ac.md" \
      || _fail "cannot write bundle-plan-ac.md stub"
  fi

  # (d) bundle-review-profile.json — the run's review profile (verbatim if
  #     present, else a minimal deterministic synthesis from the args).
  if [[ -f "$evidence_dir/review-profile.json" ]]; then
    cat "$evidence_dir/review-profile.json" > "$c3_dir/bundle-review-profile.json" \
      || _fail "cannot copy review-profile.json into the brief"
  else
    jq -S -c -n \
      --arg rp "$risk_profile" \
      --arg lvl "$required_independence_level" \
      '{risk_profile: $rp, required_independence_level: $lvl}' \
      > "$c3_dir/bundle-review-profile.json" \
      || _fail "cannot synthesise bundle-review-profile.json"
  fi

  # --- Step 4 (cont): codex_brief_files[] + codex_brief_hash ---------------
  # Path order pinned via LC_ALL=C sort (array order is NOT canonicalised by
  # jq -S). Paths are evidence-dir-relative (c3/<name>).
  local brief_paths=()
  mapfile -t brief_paths < <(printf '%s\n' \
    "c3/bundle-diff.patch" \
    "c3/bundle-scope.txt" \
    "c3/bundle-plan-ac.md" \
    "c3/bundle-review-profile.json" \
    | LC_ALL=C sort)

  local cbf_json="[]"
  local bp full h sz
  for bp in "${brief_paths[@]}"; do
    full="$evidence_dir/$bp"
    [[ -f "$full" && -r "$full" ]] || _fail "brief file missing/unreadable: $bp"
    h="$(sha256sum "$full" | awk '{print $1}')"
    sz="$(wc -c < "$full" | tr -d '[:space:]')"
    [[ -n "$sz" ]] || sz=0
    cbf_json="$(printf '%s' "$cbf_json" \
      | jq -c --arg p "$bp" --arg s "sha256:$h" --argjson z "$sz" \
          '. + [{path: $p, sha256: $s, size: $z}]')" \
      || _fail "cannot assemble codex_brief_files entry for $bp"
  done

  local cbf_canonical codex_brief_hash
  cbf_canonical="$(jq -S -c -n \
    --arg base "$base_sha" \
    --arg head "$head_sha" \
    --argjson files "$cbf_json" \
    --arg level "$required_independence_level" \
    '{base_sha: $base, head_sha: $head, codex_brief_files: $files, required_independence_level: $level}')" \
    || _fail "cannot build codex_brief_hash canonical form"
  codex_brief_hash="sha256:$(_sha256_str "$cbf_canonical")"

  # --- Step 3: allowlist[] + input_hash (VERBATIM from pipeline.md §7) ------
  # allowlist = $AID_CHANGED_PATHS (verbatim, repo-relative) + this run's
  # evidence artifacts. read_path maps each stored path string → the file whose
  # bytes feed the per-path input_hash line.
  declare -A read_path=()
  local allow_arr=()
  local line

  if [[ -n "${AID_CHANGED_PATHS:-}" && -f "$AID_CHANGED_PATHS" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      _path_is_within "$repo_root" "$repo_root/$line" \
        || _fail "AID_CHANGED_PATHS entry escapes the repo (path traversal / absolute path rejected): $line"
      allow_arr+=("$line")
      read_path["$line"]="$repo_root/$line"
    done < "$AID_CHANGED_PATHS"
  fi

  local name
  for name in final_report.md gates_report.json; do
    if [[ -f "$evidence_dir/$name" ]]; then
      allow_arr+=("$name")
      read_path["$name"]="$evidence_dir/$name"
    fi
  done

  local vf bn
  shopt -s nullglob
  for vf in "$evidence_dir"/verifier-output-*.md; do
    bn="$(basename "$vf")"
    allow_arr+=("$bn")
    read_path["$bn"]="$vf"
  done
  shopt -u nullglob

  # Deterministic stored order (LC_ALL=C), deduped.
  local allow_sorted=()
  if [[ ${#allow_arr[@]} -gt 0 ]]; then
    mapfile -t allow_sorted < <(printf '%s\n' "${allow_arr[@]}" | LC_ALL=C sort -u)
  fi

  # input_hash: per-path sha256("<path>:" + sha256(content)); sort lines
  # (LC_ALL=C); join with newlines; input_hash = "sha256:" + sha256(joined).
  local input_lines=()
  local p rp inner
  for p in "${allow_sorted[@]}"; do
    rp="${read_path[$p]:-}"
    inner="$(_sha256_file "$rp")"
    input_lines+=("$(_sha256_str "${p}:${inner}")")
  done

  local joined="" input_hash
  if [[ ${#input_lines[@]} -gt 0 ]]; then
    local sorted_lines=()
    mapfile -t sorted_lines < <(printf '%s\n' "${input_lines[@]}" | LC_ALL=C sort)
    joined="$(IFS=$'\n'; printf '%s' "${sorted_lines[*]}")"
  fi
  input_hash="sha256:$(_sha256_str "$joined")"

  # allowlist JSON array.
  local allow_json="[]"
  if [[ ${#allow_sorted[@]} -gt 0 ]]; then
    allow_json="$(printf '%s\n' "${allow_sorted[@]}" | jq -R . | jq -s .)"
  fi

  # --- Step 6: envelope revision + subject ---------------------------------
  # Honest freshness: head_is_current/freshness reflect whether head_sha is the
  # current git HEAD (normal DONE-review case → true/current).
  local current_head head_is_current freshness
  current_head="$(git rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -n "$current_head" && "$head_sha" == "$current_head" ]]; then
    head_is_current="true"
    freshness="current"
  else
    head_is_current="false"
    freshness="stale"
  fi

  local subject_hash_hex
  subject_hash_hex="$(_sha256_str "$head_sha")"

  local iso_now
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # verification_budget: bounds what the C3 prompt may execute so the audit
  # cannot re-run expensive suites that belong at the plan boundary.
  local vbudget_json='{"max_commands":10,"max_seconds":120}'
  # allowed_recheck_commands: explicit targeted commands Codex may run.
  # Default empty — the full suite is NOT re-runnable by Codex.
  local arc_json='[]'

  # --- Step 6 (cont): emit the manifest (atomic: temp then mv) --------------
  local manifest_out="$evidence_dir/audit-input-manifest.json"
  local manifest_tmp="$manifest_out.tmp.$$"

  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "audit_input_manifest" \
    --arg producer "$PRODUCER" \
    --arg created_at "$iso_now" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$project_id" \
    --arg epic_id "$epic_id" \
    --arg run_id "$run_id" \
    --arg subject_hash "sha256:$subject_hash_hex" \
    --arg head_sha "$head_sha" \
    --argjson head_is_current "$head_is_current" \
    --arg freshness "$freshness" \
    --arg generated_by_tool "$GENERATED_BY_TOOL" \
    --argjson allowlist "$allow_json" \
    --arg input_hash "$input_hash" \
    --arg required_independence_level "$required_independence_level" \
    --arg base_sha "$base_sha" \
    --argjson codex_brief_files "$cbf_json" \
    --arg codex_brief_hash "$codex_brief_hash" \
    --argjson allowed_recheck_commands "$arc_json" \
    --argjson verification_budget "$vbudget_json" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {project_id: $project_id, epic_id: $epic_id, run_id: $run_id},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: $head_is_current, freshness: $freshness},
      status: "pass",
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: $generated_by_tool},
      audit_input_manifest: {
        allowlist: $allowlist,
        input_hash: $input_hash,
        prior_pass_summaries: "untrusted",
        required_independence_level: $required_independence_level,
        base_sha: $base_sha,
        head_sha: $head_sha,
        codex_brief_files: $codex_brief_files,
        codex_brief_hash: $codex_brief_hash,
        allowed_recheck_commands: $allowed_recheck_commands,
        verification_budget: $verification_budget
      }
    }' > "$manifest_tmp" \
    || { rm -f "$manifest_tmp"; _fail "jq failed to render the manifest"; }

  mv "$manifest_tmp" "$manifest_out" || { rm -f "$manifest_tmp"; _fail "cannot move manifest into place"; }

  # --- Step 7: sanity-check via the authoritative protocol validator --------
  local validate_out=""
  if ! validate_out="$(bash "$VALIDATE" "$manifest_out" 2>&1)"; then
    rm -f "$manifest_out"
    _fail "emitted manifest failed aid-protocol-validate.sh: ${validate_out}"
  fi

  # Success — print the manifest path for callers.
  echo "$manifest_out"
  return 0
}

# ===========================================================================
# Subcommand dispatch
# ===========================================================================
main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi

  local subcommand="$1"
  shift

  case "$subcommand" in
    build-manifest)
      cmd_build_manifest "$@"
      ;;
    dispatch|verify)
      # LATER EPIC steps — deliberately not implemented here (Step 2 scope).
      echo "not yet implemented: ${subcommand}" >&2
      exit 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "unknown subcommand: ${subcommand}" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
