#!/usr/bin/env bash
# =============================================================================
# aid-c3-dispatch.sh — C3 Cross-Provider Dispatch Bridge (P065, E-065-1_7)
#
# CLI skeleton for the C3 (independent audit) cross-provider dispatch bridge.
# `build-manifest` (E-065-1_7), `dispatch` + `verify` (E-065-2_7) are implemented.
# `dispatch` now runs the FULL pipeline end-to-end: probe → render → invoke Codex
# → capture raw → validate (trusted `_validate_response`) → deterministic
# `_normalize` → `_write_report` (the ONLY place status:pass|fail is written) with
# a fail-closed `_write_unverifiable` on every failure path (E-065-2_7 Step 6).
# `verify` (E-065-2_7 Step 7) re-checks the codex-derived provenance chain AND
# proves audit-report.json is a faithful, deterministic transform of Codex's RAW
# response (re-validate the raw + field-for-field equality + index-bound
# fingerprint recompute). A bridge cannot fabricate or edit findings without
# detection; any divergence → exit 2 (fail-closed). See cmd_verify.
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
#   2 — dispatch non-dispatched outcome / verify NOT-verified (any provenance or
#       faithful-transform check failed — fail-closed)
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
#   AID_C3_ATTEMPT      — (P065 Step 17, E-065-6_7) optional positive integer
#                         identifying which fix->reverify loop attempt (pipeline.md
#                         §6a, Step 16) THIS `dispatch` call is (01 = initial audit,
#                         02/03 = rechecks). Unset (the default) → legacy single-shot
#                         behavior: every artifact lands directly under
#                         <evidence_dir>/c3/ and audit-report.{json,md} as it always
#                         did, byte-for-byte unchanged. Set → this call's artifacts
#                         are written into the self-contained <evidence_dir>/c3/
#                         attempt-NN/ (NN zero-padded), and that attempt's
#                         audit-report.{json,md} is copied to the canonical
#                         evidence-root path afterward. See cmd_dispatch's own
#                         header comment for the full contract.
#
# **Last Updated:** 2026-07-17
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$SCRIPT_DIR/../aid-protocol-validate.sh"
DEFAULT_POLICY="$PLUGIN_ROOT/defaults/policies/c3-audit-policy.yaml"

PRODUCER="orchestrator@done-review"
GENERATED_BY_TOOL="aid-c3-dispatch.sh#build-manifest"

# --- dispatch-subcommand collaborators (test seams via env override) ---------
# INDEPENDENCE_BIN — the "can we invoke codex THIS run" pre-check. Detection
#   only; NOT a cross-run availability cache. Overridable so tests can spy on
#   the exact `detect --required <level>` call the bridge makes (AC1/AC3).
# RENDER_PROMPT   — the deterministic prompt renderer (never a shell heredoc).
# CODEX_MODEL     — the -m arg the bridge invokes Codex with; this argument is
#   the authoritative "reported model" for provenance because the model slug is
#   ABSENT from the codex --json stream (fields.md §Model). Default is the
#   session-confirmed working model.
INDEPENDENCE_BIN="${AID_C3_INDEPENDENCE_BIN:-$SCRIPT_DIR/aid-audit-independence.sh}"
RENDER_PROMPT="${AID_C3_RENDER_BIN:-$SCRIPT_DIR/aid-render-prompt.sh}"
PROMPT_TEMPLATE="$PLUGIN_ROOT/defaults/prompts/c3-audit-prompt-v2.md"
RESPONSE_SCHEMA="$PLUGIN_ROOT/defaults/schemas/c3-codex-response.schema.json"
CODEX_MODEL="${AID_C3_CODEX_MODEL:-gpt-5.6-terra}"

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

  dispatch <evidence_dir>
      Select the Codex executor, probe cross_provider availability for THIS run
      (never cached), render the sealed C3 prompt deterministically, invoke the
      real Codex CLI (read-only, fresh process) and capture its raw output plus
      codex-derived provenance into <evidence_dir>/c3/c3-dispatch.json.
      Exit 0 = dispatched + events_valid (achieved cross_provider); exit 2 =
      non-dispatched / unavailable / rate_limited / timeout (bridge NEVER runs a
      fallback itself — it only signals unavailability).
      Optional AID_C3_ATTEMPT=<N> env var layers this call's artifacts under
      c3/attempt-NN/ instead (P065 Step 17 fix->reverify loop evidence).

  verify [--reference] <evidence_dir>
      Re-check the codex provenance chain and prove audit-report.json is a
      faithful, deterministic transform of Codex's raw response. Exit 0 =
      verified; exit 2 = any check failed (fail-closed). --reference checks
      freshness against the manifest's captured head_sha (committed historical
      fixtures) instead of the live HEAD.

  escalate <evidence_dir> <reason, >=20 chars>
      Manually mark an IN-PROGRESS C3 fix-loop (c3/loop-summary.json must
      already exist) as outcome:"escalated" / escalation_reason:
      "conflicting_findings". For pipeline.md 6a's "the findings are mutually
      conflicting" exit condition — a subjective judgment call the bridge
      cannot detect mechanically, unlike same-fingerprint-survival (which
      `dispatch` already detects and escalates automatically, no manual step
      needed). Once recorded, the same terminal guard applies here too — it
      allows a further dispatch only when the outcome is "" (in-progress) or
      "unverifiable" (must stay retriable); every other value, including the
      "escalated" this call just wrote, is rejected without an override —
      bypassable only via AID_C3_FORCE_BEYOND_ESCALATION, same as always.
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

  if [[ -f "$evidence_dir/final_report.md" ]]; then
    allow_arr+=("final_report.md")
    read_path["final_report.md"]="$evidence_dir/final_report.md"
  fi

  # gates_report.json: root, fallback gates/ (matches aid-release-policy.sh's existing
  # dual-path pattern — aid-run-gates.sh canonically writes it nested under gates/).
  if [[ -f "$evidence_dir/gates_report.json" ]]; then
    allow_arr+=("gates_report.json")
    read_path["gates_report.json"]="$evidence_dir/gates_report.json"
  elif [[ -f "$evidence_dir/gates/gates_report.json" ]]; then
    allow_arr+=("gates/gates_report.json")
    read_path["gates/gates_report.json"]="$evidence_dir/gates/gates_report.json"
  fi

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
# dispatch helpers
# ===========================================================================

# _json_num_or_null <maybe-int>  — echo the integer verbatim if non-empty, else
# the JSON literal `null` (for --argjson of a not-applicable exit code).
_json_num_or_null() {
  if [[ -n "$1" ]]; then printf '%s' "$1"; else printf 'null'; fi
}

# _json_str_or_null <maybe-string>  — echo a JSON string if non-empty, else the
# JSON literal `null` (so codex-derived fields are honestly absent, not "").
_json_str_or_null() {
  if [[ -n "$1" ]]; then jq -n --arg s "$1" '$s'; else printf 'null'; fi
}

# _events_valid_of <events_file>  — echo "true"/"false" per fields.md's exact
# 4-condition definition (first line thread.started with non-empty thread_id,
# last line turn.completed, no error line, ≥1 agent_message). Mirrors the
# grounding jq in codex-stream-sample/fields.md §events_valid. Fails closed to
# "false" on an empty/unparseable stream.
_events_valid_of() {
  local f="$1" v=""
  [[ -s "$f" ]] || { echo "false"; return 0; }
  v="$(jq -rs '
        (.[0].type=="thread.started")                                                as $c1a
        | ((.[0].thread_id // "")|length>0)                                          as $c1b
        | (.[-1].type=="turn.completed")                                             as $c2
        | ((map(select(.type=="error"))|length)==0)                                  as $c3
        | ((map(select(.type=="item.completed" and .item.type=="agent_message"))|length)>0) as $c4
        | ($c1a and $c1b and $c2 and $c3 and $c4)
      ' "$f" 2>/dev/null)" || v="false"
  [[ "$v" == "true" ]] && echo "true" || echo "false"
}

# _session_id_of <events_file>  — the authoritative session id from the FIRST
# event (thread.started.thread_id); empty if absent. fields.md §Session id.
_session_id_of() {
  local f="$1"
  [[ -s "$f" ]] || { printf ''; return 0; }
  # `|| true` so an unparseable stream under `set -o pipefail` yields "" rather
  # than aborting the caller.
  jq -r 'select(.type=="thread.started")|.thread_id' "$f" 2>/dev/null | head -n1 || true
}

# _looks_rate_limited <events_file> <stderr_file>  — 0 iff the live attempt bears
# the backend rate-limit signature (fields.md §Error path: a stringified 429 /
# rate_limit_exceeded blob in the error/turn.failed line, and/or on stderr).
_looks_rate_limited() {
  grep -qiE 'rate[_ ]?limit|"status"[[:space:]]*:[[:space:]]*429' "$1" "$2" 2>/dev/null
}

# _run_codex_isolated <project_root> <prompt_file> <events_out> <stderr_out> <last_out>
#   Launch the REAL codex CLI as an independent, fresh, read-only process and
#   capture its --json stdout stream, stderr, and last-message. Independence is
#   provider + fresh process + `--sandbox read-only` (NOT a filesystem jail).
#
#   SHARED TRANSPORT (P065 E-065-7_7 Step 18): this helper carries no C3-specific
#   coupling — it takes only a project root + a pre-rendered prompt file and
#   returns raw captures via the five output-file parameters. `aid-c0-plan-review.sh`
#   sources this file (guarded by the BASH_SOURCE!=0 check at the bottom, so
#   sourcing never runs C3's own CLI dispatcher) and reuses THIS function verbatim
#   for the C0 plan-review Codex launch. The only knobs it reads are $CODEX_MODEL
#   (a plain global, not a C3-only concept — a caller may repoint it before
#   calling) and the timeout env var below (AID_C3_TIMEOUT_SECONDS is read FIRST,
#   for exact backward compatibility with existing C3 tests/callers; the generic
#   AID_CODEX_ISOLATED_TIMEOUT_SECONDS is the non-C3-named equivalent for new
#   callers that should not need to know this transport started life in C3).
#
#   ⚠️ DISCOVERED ISSUE — `--output-schema` is deliberately NOT passed. Step 4's
#   c3-codex-response.schema.json uses `if/then/else` + `allOf`, and Step 1's
#   empirical finding (codex-stream-sample/fields.md §`--output-schema empirical
#   behavior`) is that Codex forwards the schema to OpenAI strict structured
#   output, which HARD-FAILS (HTTP 400 "'if' is not permitted") on any
#   conditional keyword. Passing it would 400 every dispatch. The trusted gate
#   is the caller's own explicit jq response validator (_validate_response for
#   C3, its C0 analogue for aid-c0-plan-review.sh), NOT the backend. We do NOT
#   strip if/then from either schema to work around this — it is not ours to
#   change, and the conditional rules are load-bearing for bridge validation.
#
#   Returns the codex/timeout exit code (124 = timed out).
_run_codex_isolated() {
  local project_root="$1" prompt_file="$2" events_out="$3" stderr_out="$4" last_out="$5"
  local prompt rc=0
  prompt="$(cat "$prompt_file")"
  timeout "${AID_C3_TIMEOUT_SECONDS:-${AID_CODEX_ISOLATED_TIMEOUT_SECONDS:-900}}" \
    codex exec --json \
      --cd "$project_root" \
      --sandbox read-only \
      -m "$CODEX_MODEL" \
      -c model_reasoning_effort=high \
      --output-last-message "$last_out" \
      "$prompt" \
      < /dev/null > "$events_out" 2> "$stderr_out" || rc=$?
  return "$rc"
}

# _write_dispatch_json — emit c3/c3-dispatch.json (atomic temp+mv). Writes the
# dispatch-SIDE provenance only; Step 6 (normalize) finalizes the full artifact
# shape. Positional args (all provided by cmd_dispatch):
#   1 out  2 project_root  3 head_sha  4 codex_brief_hash  5 required_level
#   6 template_id  7 template_sha256  8 rendered_prompt_sha256  9 codex_version
#   10 invoked(true|false)  11 exit_code(int|"")  12 outcome  13 session_id
#   14 codex_model  15 events_valid(true|false)  16 stdout_sha256
#   17 raw_response_sha256  18 achieved_level
_write_dispatch_json() {
  local out="$1" project_root="$2" head_sha="$3" codex_brief_hash="$4" required_level="$5"
  local template_id="$6" template_sha256="$7" rendered_prompt_sha256="$8" codex_version="$9"
  local invoked="${10}" exit_code="${11}" outcome="${12}" session_id="${13}" codex_model="${14}"
  local events_valid="${15}" stdout_sha256="${16}" raw_response_sha256="${17}" achieved_level="${18}"

  local iso_now tmp
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$out.tmp.$$"

  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "c3_dispatch" \
    --arg producer "$PRODUCER" \
    --arg created_at "$iso_now" \
    --arg generated_by_tool "aid-c3-dispatch.sh#dispatch" \
    --arg project_root "$project_root" \
    --arg head_sha "$head_sha" \
    --arg codex_brief_hash "$codex_brief_hash" \
    --arg required_independence_level "$required_level" \
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
      subject: {project_root: $project_root, head_sha: $head_sha, codex_brief_hash: $codex_brief_hash},
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

# ===========================================================================
# normalize / validate / write-report helpers (E-065-2_7 Step 6)
#
# TRUST BOUNDARY. Everything above captures Codex's RAW output verbatim; the
# functions below are the ONLY place a `status: pass|fail` audit-report.json is
# ever written, and the only place Codex's narrow findings are turned into a
# runtime-validator-passing protocol-v2 envelope. Every failure path guarantees
# a `status: unverifiable` artifact (never pass/fail) — fail-closed.
# ===========================================================================

# _validate_response <last_message_file>
#   The TRUSTED gate. An EXPLICIT jq validator that does NOT trust the backend's
#   best-effort --output-schema hint: it independently re-asserts every safety
#   rule of the C3 response contract. Returns 0 iff the file parses AND every
#   rule holds; any violation OR any jq error (fail-closed) → non-zero.
#
#   Rules (verbatim from the Step-6 plan):
#     - top-level object; key set EXACTLY {reviewed_head, codex_brief_hash,
#       review_status, blocking_findings, findings} + OPTIONAL unverifiable_reasons
#       (any extra key — incl. provider/model/process_id/input_manifest_hash — or
#       any missing required key fails);
#     - review_status ∈ {pass, findings, unverifiable};
#     - unverifiable_reasons: non-empty string[] REQUIRED iff review_status ==
#       unverifiable, forbidden otherwise;
#     - review_status↔findings binding: pass ⇒ findings==[] AND
#       blocking_findings==false; findings ⇒ findings|length>=1; and
#       blocking_findings MUST equal (∃ finding.severity ∈ {critical,high});
#     - reviewed_head ~ ^[0-9a-f]{40}$; codex_brief_hash ~ ^sha256:[0-9a-f]{64}$;
#       blocking_findings boolean; findings array;
#     - each finding: severity ∈ {critical,high,medium,low,info}; non-empty
#       area/finding/recommendation; action_owner REQUIRED for severity ∈
#       {critical,high} AND — if present at ANY severity — ∈ {implementer,
#       reviewer,pm,gate-fixer}.
_validate_response() {
  local f="$1" rc=0 doc_count
  [[ -f "$f" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1   # validator unavailable → fail-closed

  # CP2 finding (HIGH): `jq -e FILTER "$f"` below evaluates FILTER against EVERY
  # top-level JSON document in the file and `-e`'s exit status reflects only the
  # LAST one — a crafted multi-document file (two concatenated JSON objects)
  # would validate solely against its last document, silently ignoring the
  # first. This is the bridge's explicit trust gate over untrusted model
  # output, so it must reject anything but a single JSON document itself,
  # rather than relying on some other downstream check to incidentally catch
  # the malformed shape.
  doc_count="$(jq -c . "$f" 2>/dev/null | wc -l | tr -d '[:space:]')"
  [[ "$doc_count" == "1" ]] || return 1

  jq -e '
    (type == "object")
    and ((keys_unsorted
          - ["reviewed_head","codex_brief_hash","review_status","blocking_findings","findings","unverifiable_reasons"])
         | length == 0)
    and ((["reviewed_head","codex_brief_hash","review_status","blocking_findings","findings"]
          - keys_unsorted) | length == 0)
    and (.review_status | (. == "pass" or . == "findings" or . == "unverifiable"))
    and (.reviewed_head    | (type == "string" and test("^[0-9a-f]{40}$")))
    and (.codex_brief_hash | (type == "string" and test("^sha256:[0-9a-f]{64}$")))
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

# _derive_report_semantics <validated_last_msg_path>
#   SECURITY REGRESSION FIX (E-065-4_7, CP3 finding): the single shared source
#   of truth for what audit-report.json's status/review_status/outcome/
#   blocking_findings/unverifiable_reasons fields MUST be, purely as a
#   deterministic function of an ALREADY-`_validate_response`-validated raw
#   Codex response. Both writer call sites (_write_report, _write_unverifiable's
#   caller in _process_response) and cmd_verify's Step 5 binding check now call
#   this instead of each independently re-deriving the same logic ad hoc — the
#   bypass this fixes existed BECAUSE cmd_verify never re-derived and compared
#   these fields at all.
#
#   Echoes a canonical JSON object:
#     {status, review_status, outcome, blocking_findings, unverifiable_reasons}
#   Logic:
#     - raw.review_status == "unverifiable" → status=unverifiable,
#       review_status=unverifiable, outcome=review_unverifiable,
#       blocking_findings=false, unverifiable_reasons=raw.unverifiable_reasons
#       (or [] if absent).
#     - otherwise → blocking_findings = (any raw finding severity
#       critical|high); status = blocking_findings ? "fail" : "pass";
#       review_status = raw's own .review_status value verbatim (already
#       schema-validated to be "pass" or "findings" at this point);
#       outcome=dispatched; unverifiable_reasons=[].
#   Returns non-zero (fail-closed) on any jq failure — callers must not
#   proceed past a failure here.
_derive_report_semantics() {
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

# _normalize <project_id> <epic_id> <last_message_file>
#   Deterministically turn Codex's raw findings[] into the top-level protocol-v2
#   findings[] the runtime validator requires. Echoes the findings JSON array on
#   success; returns non-zero if any fingerprint cannot be produced (→ caller
#   maps to invalid_output). Reproducible: identical raw input yields identical
#   fingerprints/occurrence_ids (no timestamps, no randomness).
#     occurrence_id = "c3-<epic_id>-<n>"
#     fingerprint   = aid-finding-fingerprint.sh fingerprint_audit_report ...
#     action_owner is carried ONLY when the Codex finding has it (B5: the raw and
#       normalized tuples must carry the identical action_owner presence/value —
#       never defaulted for low/medium).
_normalize() {
  local project_id="$1" epic_id="$2" last_msg="$3"
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
    occ="c3-${epic_id}-${n}"
    fp="$(bash "$fp_helper" fingerprint_audit_report "$project_id" audit_report "$occ" "$sev" "$area" "$finding" "$rec" 2>/dev/null)" || return 1
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

# _write_report_md <md_path> <report_json>  — human-readable dual-emit twin of
# audit-report.json (same content), matching the Auditor's JSON+MD convention.
# Its existence is checked by aid-fsm.sh; content is derived from the JSON.
_write_report_md() {
  local md="$1" report="$2" tmp="$1.tmp.$$"
  local status blocking review_status outcome provider model indep reviewed_head n
  status="$(jq -r '.status // "unverifiable"' "$report" 2>/dev/null)"
  blocking="$(jq -r '.audit_report.blocking_findings // false' "$report" 2>/dev/null)"
  review_status="$(jq -r '.audit_report.review_status // "unverifiable"' "$report" 2>/dev/null)"
  outcome="$(jq -r '.audit_report.outcome // ""' "$report" 2>/dev/null)"
  provider="$(jq -r '.audit_report.provider // ""' "$report" 2>/dev/null)"
  model="$(jq -r '.audit_report.model // ""' "$report" 2>/dev/null)"
  indep="$(jq -r '.audit_report.independence_level // .audit_report.achieved_independence_level // ""' "$report" 2>/dev/null)"
  reviewed_head="$(jq -r '.audit_report.reviewed_head // ""' "$report" 2>/dev/null)"
  n="$(jq -r '.findings | length' "$report" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0

  {
    printf '# C3 Cross-Provider Audit Report\n\n'
    printf '| Field | Value |\n|---|---|\n'
    printf '| status | `%s` |\n' "$status"
    printf '| blocking_findings | `%s` |\n' "$blocking"
    printf '| review_status | `%s` |\n' "$review_status"
    [[ -n "$outcome" ]] && printf '| outcome | `%s` |\n' "$outcome"
    printf '| provider | `%s` |\n' "$provider"
    printf '| model | `%s` |\n' "$model"
    printf '| independence | `%s` |\n' "$indep"
    printf '| reviewed_head | `%s` |\n' "$reviewed_head"
    printf '| findings | %s |\n\n' "$n"

    if [[ "$status" == "unverifiable" ]]; then
      printf '**Unverifiable** — no trusted pass/fail was produced (outcome: `%s`).\n\n' "$outcome"
      local rc
      rc="$(jq -r '(.audit_report.unverifiable_reasons // []) | length' "$report" 2>/dev/null)"
      if [[ "$rc" =~ ^[0-9]+$ && "$rc" -gt 0 ]]; then
        printf '### Reasons\n\n'
        jq -r '.audit_report.unverifiable_reasons[] | "- " + .' "$report" 2>/dev/null
        printf '\n'
      fi
    fi

    if [[ "$n" -gt 0 ]]; then
      printf '## Findings\n\n'
      jq -r '.findings[] | "### [" + .severity + "] " + (.area // "") + "\n\n" +
             "- **finding:** " + (.finding // "") + "\n" +
             "- **recommendation:** " + (.recommendation // "") + "\n" +
             (if (.action_owner // "") != "" then "- **action_owner:** " + .action_owner + "\n" else "" end) +
             "- **occurrence_id:** `" + (.occurrence_id // "") + "`\n"' "$report" 2>/dev/null
      printf '\n'
    fi
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$md" 2>/dev/null || rm -f "$tmp"
  return 0
}

# _write_unverifiable <evidence_dir> <manifest> <outcome> <achieved> <session_id> <last_msg_or_empty> <reasons_json_or_empty>
#   Fail-closed writer. ALWAYS writes audit-report.json with status:"unverifiable",
#   blocking_findings:false, empty findings[], honest achieved_independence_level,
#   and the reason `outcome`. NEVER pass/fail. The report is deliberately NOT run
#   through aid-protocol-validate.sh's audit_report subfield loop — an unverifiable
#   report legitimately lacks trusted provenance (no Codex echo, or a rejected one),
#   so it cannot and must not masquerade as a validator-clean pass. Honest
#   reviewed_head/codex_brief_hash/process_id are carried only when we actually have
#   a parseable last-message (review_unverifiable / hash_mismatch / head_mismatch).
_write_unverifiable() {
  local evidence_dir="$1" manifest="$2" outcome="$3" achieved="$4" session_id="$5"
  local last_msg="$6" reasons_json="$7"
  local report="$evidence_dir/audit-report.json"
  local report_md="$evidence_dir/audit-report.md"

  local project_id epic_id run_id required_level manifest_input_hash
  project_id="$(jq -r '.identity.project_id // "unknown"' "$manifest" 2>/dev/null || echo unknown)"
  [[ -n "$project_id" && "$project_id" != "null" ]] || project_id="unknown"
  epic_id="$(jq -r '.identity.epic_id // ""' "$manifest" 2>/dev/null || echo "")"
  run_id="$(jq -r '.identity.run_id // ""' "$manifest" 2>/dev/null || echo "")"
  required_level="$(jq -r '.audit_input_manifest.required_independence_level // "cross_provider"' "$manifest" 2>/dev/null || echo cross_provider)"
  case "$required_level" in context_only|cross_model|cross_provider) ;; *) required_level="cross_provider" ;; esac
  manifest_input_hash="$(jq -r '.audit_input_manifest.input_hash // ""' "$manifest" 2>/dev/null || echo "")"

  local raw_head="" raw_brief_hash=""
  if [[ -n "$last_msg" && -f "$last_msg" ]] && jq -e . "$last_msg" >/dev/null 2>&1; then
    raw_head="$(jq -r '.reviewed_head // ""' "$last_msg" 2>/dev/null || echo "")"
    raw_brief_hash="$(jq -r '.codex_brief_hash // ""' "$last_msg" 2>/dev/null || echo "")"
    [[ "$raw_head" == "null" ]] && raw_head=""
    [[ "$raw_brief_hash" == "null" ]] && raw_brief_hash=""
  fi

  local head_sha subject_hex iso_now
  head_sha="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
  [[ -n "$head_sha" ]] || head_sha="0000000000000000000000000000000000000000"
  subject_hex="$(_sha256_str "$head_sha")"
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -n "$reasons_json" ]] || reasons_json="[]"

  local tmp="$report.tmp.$$"
  jq -n \
    --arg project_id "$project_id" --arg epic_id "$epic_id" --arg run_id "$run_id" \
    --arg created_at "$iso_now" \
    --arg subject_hash "sha256:$subject_hex" \
    --arg head_sha "$head_sha" \
    --arg required_level "$required_level" \
    --arg achieved "$achieved" \
    --arg model "$CODEX_MODEL" \
    --arg process_id "$session_id" \
    --arg input_manifest_hash "$manifest_input_hash" \
    --arg reviewed_head "$raw_head" \
    --arg codex_brief_hash "$raw_brief_hash" \
    --arg outcome "$outcome" \
    --argjson reasons "$reasons_json" \
    '{
      schema_version: "aid-2.0",
      artifact_type: "audit_report",
      producer: "orchestrator@done-review",
      created_at: $created_at,
      control_protocol: "aid-2.0",
      identity: ({project_id: $project_id}
                 + (if $epic_id != "" then {epic_id: $epic_id} else {} end)
                 + (if $run_id  != "" then {run_id:  $run_id}  else {} end)),
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: "unverifiable",
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-c3-dispatch.sh#normalize"},
      findings: [],
      audit_report: ({
          review_status: "unverifiable",
          blocking_findings: false,
          required_independence_level: $required_level,
          achieved_independence_level: $achieved,
          provider: "codex",
          model: $model,
          outcome: $outcome,
          unverifiable_reasons: $reasons
        }
        + (if $input_manifest_hash != "" then {input_manifest_hash: $input_manifest_hash} else {} end)
        + (if $process_id != ""          then {process_id: $process_id}                   else {} end)
        + (if $reviewed_head != ""       then {reviewed_head: $reviewed_head}             else {} end)
        + (if $codex_brief_hash != ""    then {codex_brief_hash: $codex_brief_hash}       else {} end))
    }' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$report" 2>/dev/null || { rm -f "$tmp"; return 1; }

  _write_report_md "$report_md" "$report"
  return 0
}

# _write_report <evidence_dir> <manifest> <last_msg> <achieved> <session_id>
#   Assemble the validator-passing protocol-v2 envelope from a VALIDATED raw
#   response (steps 3–5a already passed). The ONLY place status:pass|fail is
#   written. Any assembly/validation failure fails closed to
#   _write_unverifiable outcome=invalid_output (the bridge built a bad envelope —
#   never emit it as pass). Returns 0 on a validator-clean report, 2 otherwise.
_write_report() {
  local evidence_dir="$1" manifest="$2" last_msg="$3" achieved="$4" session_id="$5"
  local report="$evidence_dir/audit-report.json"
  local report_md="$evidence_dir/audit-report.md"

  local project_id epic_id run_id required_level manifest_input_hash
  project_id="$(jq -r '.identity.project_id // "unknown"' "$manifest" 2>/dev/null || echo unknown)"
  [[ -n "$project_id" && "$project_id" != "null" ]] || project_id="unknown"
  epic_id="$(jq -r '.identity.epic_id // ""' "$manifest" 2>/dev/null || echo "")"
  run_id="$(jq -r '.identity.run_id // ""' "$manifest" 2>/dev/null || echo "")"
  required_level="$(jq -r '.audit_input_manifest.required_independence_level // "cross_provider"' "$manifest" 2>/dev/null || echo cross_provider)"
  case "$required_level" in context_only|cross_model|cross_provider) ;; *) required_level="cross_provider" ;; esac
  manifest_input_hash="$(jq -r '.audit_input_manifest.input_hash // ""' "$manifest" 2>/dev/null || echo "")"

  local raw_head raw_brief_hash raw_blocking
  raw_head="$(jq -r '.reviewed_head' "$last_msg" 2>/dev/null)" || raw_head=""
  raw_brief_hash="$(jq -r '.codex_brief_hash' "$last_msg" 2>/dev/null)" || raw_brief_hash=""
  raw_blocking="$(jq -r '.blocking_findings' "$last_msg" 2>/dev/null)" || raw_blocking=""

  # SECURITY REGRESSION FIX (E-065-4_7, CP3 finding): derive status/
  # review_status/blocking_findings from the ONE shared function instead of
  # ad-hoc inline logic, so this writer and cmd_verify's Step 5 binding check
  # can never diverge on what these fields should be.
  local semantics env_status blocking review_status
  semantics="$(_derive_report_semantics "$last_msg")" \
    || { _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  env_status="$(jq -r '.status' <<<"$semantics" 2>/dev/null)"
  blocking="$(jq -r '.blocking_findings' <<<"$semantics" 2>/dev/null)"
  review_status="$(jq -r '.review_status' <<<"$semantics" 2>/dev/null)"

  # Invariant: _write_report is only ever reached (via _process_response Step
  # 5a/6) after the raw response's review_status has already been confirmed
  # != "unverifiable" — assert this rather than silently trusting it, since a
  # "pass"-labeled envelope must never be built over an unverifiable raw
  # response.
  if [[ "$env_status" == "unverifiable" ]]; then
    _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  # Normalize findings (compute the exact fields the runtime validator requires).
  local findings_json
  findings_json="$(_normalize "$project_id" "$epic_id" "$last_msg")" \
    || { _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }

  local head_sha subject_hex iso_now
  head_sha="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
  [[ -n "$head_sha" ]] \
    || { _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  subject_hex="$(_sha256_str "$head_sha")"
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local tmp="$report.tmp.$$"
  jq -n \
    --arg project_id "$project_id" --arg epic_id "$epic_id" --arg run_id "$run_id" \
    --arg created_at "$iso_now" \
    --arg subject_hash "sha256:$subject_hex" \
    --arg head_sha "$head_sha" \
    --arg status "$env_status" \
    --argjson findings "$findings_json" \
    --arg review_status "$review_status" \
    --argjson blocking "$blocking" \
    --arg achieved "$achieved" \
    --arg required_level "$required_level" \
    --arg model "$CODEX_MODEL" \
    --arg process_id "$session_id" \
    --arg input_manifest_hash "$manifest_input_hash" \
    --arg codex_brief_hash "$raw_brief_hash" \
    --arg reviewed_head "$raw_head" \
    '{
      schema_version: "aid-2.0",
      artifact_type: "audit_report",
      producer: "orchestrator@done-review",
      created_at: $created_at,
      control_protocol: "aid-2.0",
      identity: ({project_id: $project_id}
                 + (if $epic_id != "" then {epic_id: $epic_id} else {} end)
                 + (if $run_id  != "" then {run_id:  $run_id}  else {} end)),
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: $status,
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-c3-dispatch.sh#normalize"},
      findings: $findings,
      audit_report: {
        review_status: $review_status,
        blocking_findings: $blocking,
        independence_level: $achieved,
        required_independence_level: $required_level,
        provider: "codex",
        model: $model,
        process_id: $process_id,
        input_manifest_hash: $input_manifest_hash,
        codex_brief_hash: $codex_brief_hash,
        reviewed_head: $reviewed_head,
        outcome: "dispatched"
      }
    }' > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  mv "$tmp" "$report" 2>/dev/null \
    || { rm -f "$tmp"; _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }

  # VALIDATE with the authoritative runtime validator; a bad envelope must NEVER
  # be emitted as pass/fail — fail closed to invalid_output.
  if [[ ! -f "$VALIDATE" ]] || ! bash "$VALIDATE" "$report" >/dev/null 2>&1; then
    _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  # Edge case (plan): Codex's CLAIMED blocking_findings vs the mechanical re-derivation.
  # _validate_response already enforces equality, so this is defence-in-depth — record
  # any discrepancy in the human-readable report rather than trusting Codex's claim.
  _write_report_md "$report_md" "$report"
  if [[ -n "$raw_blocking" && "$raw_blocking" != "$blocking" ]]; then
    printf '\n> NOTE: Codex claimed blocking_findings=`%s`; the mechanical severity-based re-derivation is `%s` (authoritative).\n' \
      "$raw_blocking" "$blocking" >> "$report_md" 2>/dev/null || true
  fi
  return 0
}

# _process_response <evidence_dir> <manifest> <codex_rc> <events_valid> <dispatch_outcome> <achieved> <session_id> <head_sha>
#   The validate → normalize → write pipeline (plan steps 1–6). Consumes the raw
#   capture written by cmd_dispatch and guarantees exactly one audit-report.json
#   is produced. Returns 0 iff a validator-clean pass/fail report was written; 2
#   for every unverifiable outcome. (The dispatch EXIT code is decided separately
#   by cmd_dispatch from the CAPTURE outcome — Step-5 contract — so this return
#   value is informational.)
_process_response() {
  local evidence_dir="$1" manifest="$2" codex_rc="$3" events_valid="$4"
  local dispatch_outcome="$5" achieved="$6" session_id="$7" head_sha="$8"
  local c3_dir="$evidence_dir/c3"
  local last_msg="$c3_dir/codex-last-message.json"

  # Step 1: codex exited non-zero → transport-level unverifiable.
  if [[ "$codex_rc" != "0" ]]; then
    local uo
    case "$dispatch_outcome" in
      timeout)      uo="timeout" ;;
      rate_limited) uo="rate_limited" ;;
      *)            uo="unavailable" ;;
    esac
    _write_unverifiable "$evidence_dir" "$manifest" "$uo" "$achieved" "$session_id" "" ""
    return 2
  fi

  # Step 2: stream did not satisfy events_valid → the output is unusable.
  if [[ "$events_valid" != "true" ]]; then
    _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "" ""
    return 2
  fi

  # Step 3: last-message must parse AND pass the trusted response validator.
  if [[ ! -f "$last_msg" ]] || ! jq -e . "$last_msg" >/dev/null 2>&1; then
    _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "" ""
    return 2
  fi
  if ! _validate_response "$last_msg"; then
    _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  # Step 4: provenance-binding hash checks (Codex must have echoed the SEALED brief
  # and reviewed the EXACT commit — otherwise the audit doesn't bind to this run).
  local manifest_brief_hash raw_brief_hash raw_head current_head
  manifest_brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash // ""' "$manifest" 2>/dev/null || echo "")"
  raw_brief_hash="$(jq -r '.codex_brief_hash // ""' "$last_msg" 2>/dev/null || echo "")"
  if [[ -z "$manifest_brief_hash" || "$raw_brief_hash" != "$manifest_brief_hash" ]]; then
    _write_unverifiable "$evidence_dir" "$manifest" hash_mismatch "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi
  raw_head="$(jq -r '.reviewed_head // ""' "$last_msg" 2>/dev/null || echo "")"
  current_head="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -z "$head_sha" || "$raw_head" != "$head_sha" || -z "$current_head" || "$raw_head" != "$current_head" ]]; then
    _write_unverifiable "$evidence_dir" "$manifest" head_mismatch "$achieved" "$session_id" "$last_msg" ""
    return 2
  fi

  # Step 5a: an HONEST Codex "I couldn't audit" (schema-valid review_status:
  # unverifiable) is distinct from a BROKEN output — carry its reasons through as
  # review_unverifiable, NOT invalid_output. SECURITY REGRESSION FIX
  # (E-065-4_7, CP3 finding): the branch decision is now derived from the SAME
  # shared _derive_report_semantics function _write_report and cmd_verify use,
  # rather than a separate ad-hoc re-read of .review_status — one place decides
  # "is this raw response honestly unverifiable", everywhere.
  local semantics_5a
  semantics_5a="$(_derive_report_semantics "$last_msg")" \
    || { _write_unverifiable "$evidence_dir" "$manifest" invalid_output "$achieved" "$session_id" "$last_msg" ""; return 2; }
  if [[ "$(jq -r '.status' <<<"$semantics_5a" 2>/dev/null)" == "unverifiable" ]]; then
    local reasons
    reasons="$(jq -c '.unverifiable_reasons' <<<"$semantics_5a" 2>/dev/null || echo '[]')"
    _write_unverifiable "$evidence_dir" "$manifest" review_unverifiable "$achieved" "$session_id" "$last_msg" "$reasons"
    return 2
  fi

  # Steps 5–6: normalize + assemble + validate the pass/fail report.
  _write_report "$evidence_dir" "$manifest" "$last_msg" "$achieved" "$session_id"
  return $?
}

# ===========================================================================
# cmd_dispatch <evidence_dir>
# ===========================================================================
#
# P065 Step 17 (E-065-6_7) — per-attempt evidence layering.
#
# Interface: an OPTIONAL AID_C3_ATTEMPT env var (positive integer, e.g. "2")
# tells this invocation which fix->reverify LOOP ATTEMPT it is (pipeline.md
# §6a's c3 fix->reverify loop, Step 16). Chosen as an env var, not a new
# positional arg — `dispatch <evidence_dir>` is a fixed 1-arg CLI many existing
# callers/tests already invoke bare, and env is the SAME seam convention this
# file already uses for every other dispatch-time collaborator override
# (AID_C3_INDEPENDENCE_BIN, AID_C3_CODEX_MODEL, AID_C3_TIMEOUT_SECONDS, ...).
#
# UNSET (the default) → LEGACY BEHAVIOR, byte-for-byte unchanged from before
# Step 17: every artifact is written directly under <evidence_dir>/c3/ and
# <evidence_dir>/audit-report.{json,md}, and NO c3/attempt-*/ directory or
# c3/loop-summary.json is ever created. Deliberate — callers/tests that predate
# the loop concept (including this file's own "two consecutive dispatch calls
# on the same evidence dir" tests) must keep working unmodified.
#
# SET to N → this call's artifacts are written into the SELF-CONTAINED
# directory <evidence_dir>/c3/attempt-NN/ (NN = N zero-padded to 2 digits),
# mirroring the evidence_dir shape exactly: its own audit-input-manifest.json
# snapshot + audit-report.{json,md} + a c3/ subdir holding c3-dispatch.json /
# codex-events.jsonl / codex-events.stderr / codex-last-message.json /
# codex-prompt.txt / codex-prompt-vars.json. Mirroring the shape means
# `verify [--reference] <evidence_dir>/c3/attempt-NN` works UNCHANGED against
# cmd_verify below — no verify code needed to change for this step. After the
# attempt completes (whatever its outcome), its audit-report.{json,md} is
# copied to the CANONICAL <evidence_dir>/audit-report.{json,md} path — the one
# the FSM C3 hook + Curator read (Step 16's existing, unchanged read path) — so
# canonical always equals the LAST attempt. If that copy cannot be made
# durable, the attempt's own report stays authoritative under attempt-NN/ but
# the overall run fails closed (exit 2, canonical stomped to
# status:unverifiable outcome:canonical_copy_failed) rather than silently
# leaving a stale canonical report in place.
#
# Collision guard (plan edge case: "never reuse a number within a single run's
# evidence directory"): reusing an AID_C3_ATTEMPT value that already recorded a
# GENUINELY completed (c3-dispatch.json .dispatch.outcome == "dispatched")
# audit is a PRECONDITION FAIL. A retry of a non-dispatched slot (unavailable /
# rate_limited / timeout / render_failed — pipeline.md's "NOT a loop iteration"
# case) is NOT a collision and may overwrite, matching how the legacy default
# path has always allowed re-dispatching after a non-dispatched outcome.
# ===========================================================================

# _c3_copy_atomic <src> <dst>  — copy <src> to <dst> via temp+mv (a reader never
# observes a partial file). Returns 1 — no side effect beyond a removed temp —
# if <src> is missing or either write step fails, e.g. <dst>'s parent directory
# is not writable (chmod 555): the exact "canonical path unwritable" failure
# mode Step 17's error handling must fail closed on.
_c3_copy_atomic() {
  local src="$1" dst="$2" tmp
  [[ -f "$src" ]] || return 1
  tmp="$dst.tmp.$$"
  cp -f "$src" "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$dst" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# _c3_write_loop_summary <evidence_dir> <n> <session_id> <head_sha> <dispatch_outcome> <report_status>
#   Accumulate <evidence_dir>/c3/loop-summary.json — the PM-facing record of
#   every loop attempt this evidence dir has seen so far. NEW schema (Step 16
#   was docs/policy only, nothing wrote this file before now) — chosen here:
#     {schema_version, artifact_type:"c3_loop_summary", producer, created_at,
#      attempts: [{n, session_id, head, outcome, recorded_at}, ...] (sorted by
#        n; re-writing entry <n> REPLACES any prior record for that same n, so
#        a retried non-loop-iteration outcome on the same slot updates in
#        place rather than duplicating),
#      recheck_count,   -- count of GENUINELY dispatched attempts minus 1,
#                          floored at 0. Mirrors pipeline.md §6a: an
#                          unavailable/rate_limited/timeout/render_failed
#                          attempt is explicitly "NOT a loop iteration" and
#                          must not inflate this count.
#      outcome}         -- "clean" (latest attempt's audit-report.json
#                          status=="pass"), "unverifiable" (latest attempt's
#                          status=="unverifiable"), "escalated" (latest attempt
#                          still status=="fail" AND recheck_count has reached
#                          c3_fix_loop.max_rechecks — the SAME policy key
#                          build-manifest already reads via C3_AUDIT_POLICY/
#                          DEFAULT_POLICY, fail-closed to 2 on any read issue,
#                          matching Step 16's own fail-closed default), or null
#                          (still blocking, budget not yet exhausted — loop
#                          should recheck again). Writing "escalated" here is a
#                          purely DESCRIPTIVE annotation of mechanical facts
#                          already in hand (recheck_count + latest status) — it
#                          does not itself stop, retry, or dispatch anything;
#                          the actual loop-DRIVING decision (whether to spend
#                          another recheck, when to hand off to the PM) stays
#                          the pipeline-level controller's job, per the plan.
#   Only ever called from the AID_C3_ATTEMPT-explicit path in cmd_dispatch —
#   never touches the legacy default path. Returns 1 on any write failure
#   (temp+mv — never a partial overwrite).
_c3_write_loop_summary() {
  local evidence_dir="$1" n="$2" session_id="$3" head_sha="$4" dispatch_outcome="$5" report_status="$6"
  local out="$evidence_dir/c3/loop-summary.json"
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

  local policy_file="${C3_AUDIT_POLICY:-$DEFAULT_POLICY}" max_rechecks=2
  if [[ -f "$policy_file" ]]; then
    local mr
    mr="$(yq -r '.c3_fix_loop.max_rechecks // 2' "$policy_file" 2>/dev/null || echo 2)"
    [[ "$mr" =~ ^[0-9]+$ ]] && max_rechecks="$mr"
  fi

  # CORRECTNESS FIX (E-065-6_7 DONE-review C3 finding, round 4): pipeline.md
  # 6a's loop body documents THREE distinct escalation triggers, but only
  # budget-exhaustion (recheck_count >= max_rechecks, below) was ever
  # code-enforced — "the SAME finding fingerprint survived this recheck (fix
  # ineffective)" was prose-only, so nothing stopped a further automatic
  # AID_C3_ATTEMPT dispatch after the controller judged a fix ineffective.
  # Unlike "conflicting findings" (an inherently subjective judgment call —
  # left to the controller via the `escalate` subcommand below), "same
  # fingerprint survived" IS mechanically decidable: fingerprints are
  # deterministic content hashes, so compare THIS attempt's blocking-finding
  # fingerprints against the immediately-prior dispatched attempt's — any
  # overlap while still blocking means the fix didn't work.
  local same_fingerprint_survived=false
  if [[ "$report_status" == "fail" ]]; then
    local prev_n prev_nn prev_report
    prev_n="$(jq -r --argjson n "$n" \
      '[.[] | select(.n < $n and .outcome == "dispatched")] | sort_by(.n) | last | .n // empty' \
      <<<"$attempts" 2>/dev/null)"
    if [[ -n "$prev_n" ]]; then
      prev_nn="$(printf '%02d' "$prev_n")"
      prev_report="$evidence_dir/c3/attempt-$prev_nn/audit-report.json"
      if [[ -f "$prev_report" ]]; then
        local cur_fps prev_fps overlap
        cur_fps="$(jq -c '[.findings[]?.fingerprint] | sort' "$evidence_dir/audit-report.json" 2>/dev/null)"
        prev_fps="$(jq -c '[.findings[]?.fingerprint] | sort' "$prev_report" 2>/dev/null)"
        [[ -n "$cur_fps" ]] || cur_fps='[]'
        [[ -n "$prev_fps" ]] || prev_fps='[]'
        overlap="$(jq -n --argjson a "$cur_fps" --argjson b "$prev_fps" \
          '[$a[] | select(. as $x | $b | index($x))] | length' 2>/dev/null)"
        [[ "${overlap:-0}" -gt 0 ]] && same_fingerprint_survived=true
      fi
    fi
  fi

  # CORRECTNESS FIX (E-065-6_7 DONE-review C3 finding, round 3): "unverifiable"
  # covers two distinct cases that must NOT be treated alike. (a) A true
  # dispatch failure (codex unavailable/timeout/rate_limited/render_failed) —
  # its attempts[] entry.outcome is the failure string, never "dispatched", so
  # it never contributes to dispatched_count/recheck_count above; this is
  # pipeline.md 6a's documented "not a loop iteration" — retrying it is the
  # whole point and must stay unbounded-retriable, exactly as before. (b) A
  # GENUINE dispatch (attempts[] entry.outcome == "dispatched", Codex's CLI
  # stream was well-formed) whose FINAL response content still failed
  # schema/semantic validation in _process_response — this DOES advance
  # recheck_count (case (a) never does) but previously had no escalation cap
  # at all, unlike the symmetric "fail" branch below: an attacker or
  # malfunctioning caller could keep forcing AID_C3_ATTEMPT dispatches that
  # each produce a genuinely-dispatched-but-invalid report forever, never
  # reaching "escalated" and therefore never hitting the terminal-outcome
  # guard added in rounds 1-2. Mirror the "fail" branch's budget check here
  # too — case (a) is unaffected (recheck_count stays 0 for it either way).
  local escalation_reason='null'
  case "$report_status" in
    pass) top_outcome='"clean"' ;;
    unverifiable|fail)
      if [[ "$same_fingerprint_survived" == true ]]; then
        top_outcome='"escalated"'
        escalation_reason='"same_fingerprint_survived"'
      elif [[ "$recheck_count" -ge "$max_rechecks" ]]; then
        top_outcome='"escalated"'
        escalation_reason='"budget_exhausted"'
      elif [[ "$report_status" == "unverifiable" ]]; then
        top_outcome='"unverifiable"'
      else
        top_outcome='null'
      fi
      ;;
    *)    top_outcome='null' ;;
  esac

  # current_attempt: which attempt-NN/ directory's raw evidence + report is
  # CURRENTLY the one copied to the canonical evidence-root path — set
  # unconditionally to $n on every call, since this function only ever runs
  # from _c3_finalize_attempt right after attempt $n's canonical copy (P065
  # E-065-7_7 DONE-review Finding B: cmd_verify needs this to resolve raw
  # dispatch artifacts, which are never mirrored to the canonical root).
  jq -n \
    --argjson attempts "$attempts" \
    --argjson recheck_count "$recheck_count" \
    --argjson outcome "$top_outcome" \
    --argjson escalation_reason "$escalation_reason" \
    --argjson current_attempt "$n" \
    --arg created_at "$iso_now" \
    '{schema_version:"aid-2.0", artifact_type:"c3_loop_summary",
      producer:"orchestrator@done-review", created_at:$created_at,
      attempts:$attempts, recheck_count:$recheck_count, outcome:$outcome,
      escalation_reason:$escalation_reason, current_attempt:$current_attempt}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$out" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

# _c3_finalize_attempt <evidence_dir> <attempt_dir> <root_manifest> <n> <nn> <session_id> <head_sha> <dispatch_outcome>
#   Only ever called when AID_C3_ATTEMPT was explicit (cmd_dispatch gates every
#   call site on attempt_explicit). Copies <attempt_dir>'s audit-report.{json,md}
#   to the canonical <evidence_dir> root, then updates c3/loop-summary.json.
#   On a canonical-copy failure: stomps the canonical report to
#   status:unverifiable (best effort — evidence_dir may itself be unwritable,
#   in which case this ALSO silently no-ops; that is fine, because the caller
#   reacts to THIS function's return code, not to the stomped file's presence)
#   and prints a FATAL line. Returns 0 iff the canonical copy succeeded; 1
#   otherwise — the caller (cmd_dispatch) must exit 2 on a 1, never exit 0.
_c3_finalize_attempt() {
  local evidence_dir="$1" attempt_dir="$2" root_manifest="$3" n="$4" nn="$5"
  local session_id="$6" head_sha="$7" dispatch_outcome="$8"

  local report_status=""
  [[ -f "$attempt_dir/audit-report.json" ]] \
    && report_status="$(jq -r '.status // ""' "$attempt_dir/audit-report.json" 2>/dev/null)"

  local rc=0
  if _c3_copy_atomic "$attempt_dir/audit-report.json" "$evidence_dir/audit-report.json"; then
    # .md is a human-readable convenience twin of the same content; a failure
    # copying it does not itself invalidate the canonical JSON just copied.
    _c3_copy_atomic "$attempt_dir/audit-report.md" "$evidence_dir/audit-report.md" || true
  else
    echo "aid-c3-dispatch: FATAL — cannot copy c3/attempt-$nn/audit-report.json to the canonical evidence-root path; failing closed (attempt evidence remains authoritative under c3/attempt-$nn/)" >&2
    _write_unverifiable "$evidence_dir" "$root_manifest" canonical_copy_failed unavailable "" "" "" || true
    report_status="canonical_copy_failed"
    rc=1
  fi

  # SECURITY/CORRECTNESS FIX (E-065-6_7 DONE-review C3 finding): a
  # loop-summary write failure was previously swallowed with `|| true`, so a
  # successful canonical-copy (rc still 0 at this point) could report overall
  # dispatch success even though the recheck-count/escalation audit trail
  # (c3/loop-summary.json) is missing or stale — making the loop's actual
  # progress unverifiable to the FSM hook, Curator, and PM. Fail closed: a
  # loop-summary write failure now also fails the whole attempt, even when
  # the canonical report copy itself succeeded.
  local summary_rc=0
  _c3_write_loop_summary "$evidence_dir" "$n" "$session_id" "$head_sha" "$dispatch_outcome" "$report_status" || summary_rc=$?
  if [[ "$summary_rc" -ne 0 ]]; then
    echo "aid-c3-dispatch: FATAL — c3/loop-summary.json write failed after attempt $nn; the recheck/escalation audit trail is unverifiable. Failing closed." >&2
    _write_unverifiable "$evidence_dir" "$root_manifest" loop_summary_write_failed unavailable "" "" "" || true
    rc=1
  fi
  return "$rc"
}

cmd_dispatch() {
  if [[ $# -ne 1 ]]; then
    usage >&2
    echo "PRECONDITION FAIL: dispatch requires exactly 1 arg: <evidence_dir>" >&2
    exit 1
  fi
  local evidence_dir="$1"
  [[ -n "$evidence_dir" ]] || { echo "PRECONDITION FAIL: evidence_dir is empty" >&2; exit 1; }
  [[ -d "$evidence_dir" ]] || { echo "PRECONDITION FAIL: evidence_dir not a directory: $evidence_dir" >&2; exit 1; }

  local manifest="$evidence_dir/audit-input-manifest.json"
  [[ -f "$manifest" ]] || { echo "PRECONDITION FAIL: manifest missing (run build-manifest first): $manifest" >&2; exit 1; }

  local c3_dir="$evidence_dir/c3"
  mkdir -p "$c3_dir" || { echo "PRECONDITION FAIL: cannot create $c3_dir" >&2; exit 1; }

  # --- Step 0 (P065 Step 17): resolve the attempt slot for THIS invocation ---
  # work_evidence_dir/work_c3_dir/manifest_for_call are what the rest of this
  # function reads/writes through. attempt_explicit=0 (AID_C3_ATTEMPT unset)
  # makes them IDENTICAL to the pre-Step-17 evidence_dir/c3_dir/manifest — the
  # legacy path is untouched. See this function's header comment for the full
  # contract.
  local attempt_n="${AID_C3_ATTEMPT:-}"
  local attempt_explicit=0 attempt_dir="" attempt_nn=""
  local work_evidence_dir="$evidence_dir"
  local work_c3_dir="$c3_dir"
  local manifest_for_call="$manifest"

  if [[ -n "$attempt_n" ]]; then
    [[ "$attempt_n" =~ ^[1-9][0-9]*$ ]] \
      || { echo "PRECONDITION FAIL: AID_C3_ATTEMPT must be a positive integer (got: $attempt_n)" >&2; exit 1; }

    # SECURITY/CORRECTNESS FIX (E-065-6_7 DONE-review C3 findings, now six
    # rounds on this guard): rounds 1-2 rejected "escalated" then "clean".
    # A live re-audit at round 5's own HEAD found the check was still a
    # DENYLIST ("escalated" OR "clean") rather than an ALLOWLIST — any OTHER
    # parseable-but-unrecognized outcome string (a typo, corrupted data, a
    # future schema value this check was never updated for) silently fell
    # through and was ALLOWED, defeating the entire bounded-loop guarantee
    # for exactly the class of state this check exists to close off. Flip
    # the polarity: only two values are KNOWN-SAFE to proceed on without an
    # override — "" (bare JSON null via `// ""`, a genuinely in-progress
    # loop) and "unverifiable" (pipeline.md 6a's "not a loop iteration"
    # carve-out, rounds 3-4 — must stay freely retriable). Every other value,
    # recognized-terminal ("clean"/"escalated") or not, now requires the
    # explicit, auditable, PM-authorized override — mirroring this project's
    # established `--force --reason '<>=20 chars>'` pattern.
    local existing_summary="$c3_dir/loop-summary.json"
    if [[ -f "$existing_summary" ]]; then
      local prior_loop_outcome
      prior_loop_outcome="$(jq -r '.outcome // ""' "$existing_summary" 2>/dev/null)"
      if [[ "$prior_loop_outcome" != "" && "$prior_loop_outcome" != "unverifiable" ]]; then
        if [[ -z "${AID_C3_FORCE_BEYOND_ESCALATION:-}" || "${#AID_C3_FORCE_BEYOND_ESCALATION}" -lt 20 ]]; then
          echo "PRECONDITION FAIL: c3/loop-summary.json already recorded outcome=\"$prior_loop_outcome\" for this evidence dir — automatic further C3 dispatches are rejected (bounded-loop requirement: only an in-progress or \"unverifiable\" outcome may proceed without override; \"$prior_loop_outcome\" is treated as terminal, whether or not it is a recognized value)." >&2
          echo "Fix: a further attempt requires an explicit, auditable PM-authorized override: AID_C3_FORCE_BEYOND_ESCALATION='<reason, >=20 chars>'." >&2
          exit 1
        fi
        echo "aid-c3-dispatch: WARNING — proceeding past a recorded terminal outcome (\"$prior_loop_outcome\") via PM-authorized override: ${AID_C3_FORCE_BEYOND_ESCALATION}" >&2
      fi
    fi

    attempt_explicit=1
    attempt_nn="$(printf '%02d' "$attempt_n")"
    attempt_dir="$c3_dir/attempt-$attempt_nn"

    # Collision guard — see header comment above.
    if [[ -f "$attempt_dir/c3/c3-dispatch.json" ]]; then
      local prior_outcome
      prior_outcome="$(jq -r '.dispatch.outcome // ""' "$attempt_dir/c3/c3-dispatch.json" 2>/dev/null)"
      if [[ "$prior_outcome" == "dispatched" ]]; then
        echo "PRECONDITION FAIL: c3/attempt-$attempt_nn already recorded a completed dispatch (outcome=dispatched); refusing to reuse — pass a new AID_C3_ATTEMPT" >&2
        exit 1
      fi
    fi

    mkdir -p "$attempt_dir/c3" || { echo "PRECONDITION FAIL: cannot create $attempt_dir/c3" >&2; exit 1; }
    # Seal this attempt's OWN manifest snapshot (build-manifest already wrote
    # the live/current one at evidence_dir root for this recheck's
    # base..newHEAD — Step 16) so a later `verify` against attempt_dir alone
    # is self-contained.
    _c3_copy_atomic "$manifest" "$attempt_dir/audit-input-manifest.json" \
      || { echo "PRECONDITION FAIL: cannot seal audit-input-manifest.json into $attempt_dir" >&2; exit 1; }

    # Seal a COPY of every codex_brief_files[] entry too (bundle-diff.patch,
    # bundle-scope.txt, bundle-plan-ac.md, bundle-review-profile.json — the
    # brief files build-manifest wrote at evidence_dir root, referenced by
    # RELATIVE path in the manifest). cmd_verify's _recompute_codex_brief_hash
    # reads codex_brief_files[] paths relative to whatever evidence_dir it is
    # given, so `verify [--reference] <evidence_dir>/c3/attempt-NN` needs its
    # OWN copies here, not just the sealed manifest above.
    local _brief_path
    while IFS= read -r _brief_path; do
      [[ -n "$_brief_path" ]] || continue
      mkdir -p "$attempt_dir/$(dirname "$_brief_path")" \
        || { echo "PRECONDITION FAIL: cannot create $attempt_dir/$(dirname "$_brief_path")" >&2; exit 1; }
      _c3_copy_atomic "$evidence_dir/$_brief_path" "$attempt_dir/$_brief_path" \
        || { echo "PRECONDITION FAIL: cannot seal brief file into $attempt_dir: $_brief_path" >&2; exit 1; }
    done < <(jq -r '.audit_input_manifest.codex_brief_files[]?.path // empty' "$manifest" 2>/dev/null)

    work_evidence_dir="$attempt_dir"
    work_c3_dir="$attempt_dir/c3"
    manifest_for_call="$attempt_dir/audit-input-manifest.json"
  fi

  # --- Step 1: read the sealed brief provenance from the manifest -------------
  # (manifest.input_hash is read fresh by _write_report/_process_response where
  # the legacy chain field is actually assembled — not needed in this scope.)
  local base_sha head_sha codex_brief_hash required_level
  base_sha="$(jq -r '.audit_input_manifest.base_sha // ""' "$manifest_for_call")"
  head_sha="$(jq -r '.audit_input_manifest.head_sha // ""' "$manifest_for_call")"
  codex_brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash // ""' "$manifest_for_call")"
  required_level="$(jq -r '.audit_input_manifest.required_independence_level // "cross_provider"' "$manifest_for_call")"
  [[ -n "$head_sha" ]] || { echo "PRECONDITION FAIL: manifest has no head_sha" >&2; exit 1; }

  # --- Step 1 (cont): resolve project_root = the real repo root --------------
  local project_root
  project_root="$(git -C "$evidence_dir" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "PRECONDITION FAIL: evidence_dir is not inside a git repository: $evidence_dir" >&2; exit 1; }

  # --- Step 2: executor = codex_cli (hardcoded default; full policy = Step 8) -
  # Only kind that exists; fail-closed default per the plan. (_write_dispatch_json
  # hardcodes this string directly for the JSON output — no local var needed here.)

  # --- Step 3: cross_provider PRE-CHECK for THIS run (never cached) -----------
  # The executor is chosen BEFORE any level check and Codex is ALWAYS probed as
  # cross_provider, regardless of required_level (achieved cross_provider ≥ a
  # required cross_model still satisfies — do not downgrade the probe). No
  # availability cache is read or written; the previous run's outcome is never a
  # skip precondition — each dispatch independently re-checks and re-attempts.
  local precheck_rc=0 precheck_out=""
  precheck_out="$("$INDEPENDENCE_BIN" detect --required cross_provider 2>&1)" || precheck_rc=$?

  if [[ "$precheck_rc" -ne 0 ]]; then
    # Non-dispatched: cannot invoke codex this run. Signal unavailability; the
    # bridge NEVER launches a fallback itself (that is a later orchestration EPIC).
    echo "aid-c3-dispatch: cross_provider unavailable this run (pre-check rc=$precheck_rc): $precheck_out" >&2
    _write_dispatch_json "$work_c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
      "$required_level" "" "" "" "" "false" "" "unavailable" "" "$CODEX_MODEL" "false" "" "" "unavailable"
    # Fail-closed: a non-dispatched run STILL gets an honest unverifiable report.
    _write_unverifiable "$work_evidence_dir" "$manifest_for_call" unavailable "unavailable" "" "" "" || true
    if [[ "$attempt_explicit" -eq 1 ]]; then
      _c3_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$manifest" "$attempt_n" "$attempt_nn" \
        "" "$head_sha" unavailable || true
    fi
    exit 2
  fi

  # --- Step 4: render the sealed C3 prompt DETERMINISTICALLY ------------------
  # Build the exact declared C3 variable set (canonical JSON) and render via
  # aid-render-prompt.sh — never a shell heredoc. The renderer fails closed on
  # any missing/unknown variable or leftover {{placeholder}}.
  local plan_sha256 input_manifest_hash evidence_paths arc_str vbudget_str output_schema_path
  plan_sha256="$(jq -r '.audit_input_manifest.codex_brief_files[]? | select(.path=="c3/bundle-plan-ac.md") | .sha256' "$manifest" | head -n1)"
  [[ -n "$plan_sha256" ]] || plan_sha256="sha256:"
  input_manifest_hash="sha256:$(sha256sum "$manifest" | awk '{print $1}')"
  evidence_paths="$(jq -r '.audit_input_manifest.allowlist // [] | join(", ")' "$manifest")"
  arc_str="$(jq -c '.audit_input_manifest.allowed_recheck_commands // []' "$manifest")"
  vbudget_str="$(jq -c '.audit_input_manifest.verification_budget // {}' "$manifest")"
  output_schema_path="$(realpath -m --relative-to="$project_root" "$RESPONSE_SCHEMA" 2>/dev/null || echo "$RESPONSE_SCHEMA")"

  # IMP-245 path-resolution fix: Codex runs with `--cd "$project_root"` (the repo
  # root), NOT `--cd "$evidence_dir"` — so every sealed-artifact path handed to it
  # MUST be resolved relative to project_root (matching output_schema_path's
  # existing, correct pattern above), never a bare evidence_dir-relative string
  # like "c3/bundle-diff.patch". A real live dogfood run under c3-audit-prompt-v2
  # surfaced this: once the prompt actually told Codex it's allowed to read these
  # files (fixing the OTHER half of IMP-245), Codex tried to and genuinely
  # couldn't find them from its own --cd anchor, correctly reporting them absent.
  local plan_path_rel input_manifest_path_rel bundle_diff_path_rel bundle_scope_path_rel review_profile_path_rel
  plan_path_rel="$(realpath -m --relative-to="$project_root" "$evidence_dir/c3/bundle-plan-ac.md" 2>/dev/null || echo "c3/bundle-plan-ac.md")"
  input_manifest_path_rel="$(realpath -m --relative-to="$project_root" "$manifest" 2>/dev/null || echo "audit-input-manifest.json")"
  bundle_diff_path_rel="$(realpath -m --relative-to="$project_root" "$evidence_dir/c3/bundle-diff.patch" 2>/dev/null || echo "c3/bundle-diff.patch")"
  bundle_scope_path_rel="$(realpath -m --relative-to="$project_root" "$evidence_dir/c3/bundle-scope.txt" 2>/dev/null || echo "c3/bundle-scope.txt")"
  review_profile_path_rel="$(realpath -m --relative-to="$project_root" "$evidence_dir/c3/bundle-review-profile.json" 2>/dev/null || echo "c3/bundle-review-profile.json")"

  local vars_json="$work_c3_dir/codex-prompt-vars.json"
  jq -n \
    --arg plan_path "$plan_path_rel" \
    --arg plan_sha256 "$plan_sha256" \
    --arg base_sha "$base_sha" \
    --arg head_sha "$head_sha" \
    --arg input_manifest_path "$input_manifest_path_rel" \
    --arg input_manifest_hash "$input_manifest_hash" \
    --arg codex_brief_hash "$codex_brief_hash" \
    --arg bundle_diff_path "$bundle_diff_path_rel" \
    --arg bundle_scope_path "$bundle_scope_path_rel" \
    --arg acceptance_criteria_path "$plan_path_rel" \
    --arg review_profile_path "$review_profile_path_rel" \
    --arg evidence_paths "$evidence_paths" \
    --arg output_schema_path "$output_schema_path" \
    --arg allowed_recheck_commands "$arc_str" \
    --arg verification_budget "$vbudget_str" \
    '{plan_path:$plan_path, plan_sha256:$plan_sha256, base_sha:$base_sha, head_sha:$head_sha,
      input_manifest_path:$input_manifest_path, input_manifest_hash:$input_manifest_hash,
      codex_brief_hash:$codex_brief_hash, bundle_diff_path:$bundle_diff_path,
      bundle_scope_path:$bundle_scope_path, acceptance_criteria_path:$acceptance_criteria_path,
      review_profile_path:$review_profile_path, evidence_paths:$evidence_paths,
      output_schema_path:$output_schema_path, allowed_recheck_commands:$allowed_recheck_commands,
      verification_budget:$verification_budget}' \
    > "$vars_json" || { echo "PRECONDITION FAIL: cannot assemble prompt vars" >&2; exit 1; }

  local prompt_file="$work_c3_dir/codex-prompt.txt"
  local render_prov=""
  local template_id="" template_sha256="" rendered_prompt_sha256=""
  if render_prov="$(bash "$RENDER_PROMPT" --template "$PROMPT_TEMPLATE" --vars-json "$vars_json" --output "$prompt_file" 2>&1)"; then
    template_id="$(printf '%s' "$render_prov" | jq -r '.template_id // ""' 2>/dev/null)"
    template_sha256="$(printf '%s' "$render_prov" | jq -r '.template_sha256 // ""' 2>/dev/null)"
    rendered_prompt_sha256="$(printf '%s' "$render_prov" | jq -r '.rendered_prompt_sha256 // ""' 2>/dev/null)"
  else
    # Rendering is a precondition for invoking Codex; treat a render failure as
    # non-dispatched (not invoked) rather than launching Codex with no prompt.
    echo "aid-c3-dispatch: prompt render failed: $render_prov" >&2
    _write_dispatch_json "$work_c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
      "$required_level" "" "" "" "" "false" "" "render_failed" "" "$CODEX_MODEL" "false" "" "" "unavailable"
    # Fail-closed: render is a precondition for invoking Codex; no trusted audit.
    _write_unverifiable "$work_evidence_dir" "$manifest_for_call" unavailable "unavailable" "" "" "" || true
    if [[ "$attempt_explicit" -eq 1 ]]; then
      _c3_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$manifest" "$attempt_n" "$attempt_nn" \
        "" "$head_sha" render_failed || true
    fi
    exit 2
  fi

  # --- Step 5: codex_version (best effort; slug is NOT in the stream) ---------
  local codex_version
  codex_version="$(codex --version 2>/dev/null || echo "")"

  # --- Step 6: launch codex (fresh, read-only, isolated) and capture ---------
  local events_file="$work_c3_dir/codex-events.jsonl"
  local stderr_file="$work_c3_dir/codex-events.stderr"
  local last_msg_file="$work_c3_dir/codex-last-message.json"
  # Clean any prior run's captures so a partial re-run is never mistaken for fresh.
  rm -f "$events_file" "$stderr_file" "$last_msg_file"

  local codex_rc=0
  _run_codex_isolated "$project_root" "$prompt_file" "$events_file" "$stderr_file" "$last_msg_file" \
    || codex_rc=$?

  # --- Step 7: parse provenance from the captured stream ---------------------
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

  # achieved_independence_level = cross_provider IFF events_valid, else unavailable.
  if [[ "$events_valid" == "true" ]]; then
    achieved="cross_provider"
  else
    achieved="unavailable"
  fi

  local stdout_sha256="" raw_response_sha256=""
  [[ -s "$events_file" ]]   && stdout_sha256="sha256:$(sha256sum "$events_file"   | awk '{print $1}')"
  [[ -f "$last_msg_file" ]] && raw_response_sha256="sha256:$(sha256sum "$last_msg_file" | awk '{print $1}')"

  _write_dispatch_json "$work_c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
    "$required_level" "$template_id" "$template_sha256" "$rendered_prompt_sha256" "$codex_version" \
    "true" "$codex_rc" "$outcome" "$session_id" "$CODEX_MODEL" "$events_valid" \
    "$stdout_sha256" "$raw_response_sha256" "$achieved" \
    || { echo "PRECONDITION FAIL: cannot write c3-dispatch.json" >&2; exit 1; }

  # --- Step 8 (E-065-2_7 Step 6): validate → normalize → write report ----------
  # The full pipeline runs end-to-end here. This ALWAYS produces exactly one
  # audit-report.json (pass/fail for a validator-clean report; unverifiable for
  # every failure). Its return value is informational — the dispatch EXIT code is
  # decided below from the CAPTURE outcome (Step-5 contract), NOT from the report.
  local presp_rc=0
  _process_response "$work_evidence_dir" "$manifest_for_call" "$codex_rc" "$events_valid" \
    "$outcome" "$achieved" "$session_id" "$head_sha" || presp_rc=$?

  # --- Step 9: exit status -----------------------------------------------------
  # 0 iff dispatched + events_valid (Codex ran and produced a well-formed stream);
  # everything else (timeout / rate_limited / failed) signals unavailability →
  # exit 2. The TRUSTWORTHINESS of the audit content is recorded in
  # audit-report.json's status/outcome, independent of this dispatch exit code.
  # P065 Step 17: when AID_C3_ATTEMPT is explicit, the attempt's report is also
  # copied to the canonical evidence-root path here — a copy failure flips an
  # otherwise-0 exit to 2 (fail-closed; see _c3_finalize_attempt).
  echo "$work_c3_dir/c3-dispatch.json"

  local final_rc=2
  [[ "$outcome" == "dispatched" ]] && final_rc=0

  if [[ "$attempt_explicit" -eq 1 ]]; then
    if ! _c3_finalize_attempt "$evidence_dir" "$work_evidence_dir" "$manifest" "$attempt_n" "$attempt_nn" \
           "$session_id" "$head_sha" "$outcome"; then
      final_rc=2
    fi
  fi

  if [[ "$final_rc" -eq 0 ]]; then
    return 0
  else
    exit 2
  fi
}

# ===========================================================================
# cmd_verify [--reference] <evidence_dir>   (E-065-2_7 Step 7)
#
# Re-check the codex-derived provenance chain AND prove the final
# audit-report.json is a faithful, deterministic transform of Codex's RAW
# response (c3/codex-last-message.json). An earlier `verify` only bound "codex
# ran"; this ALSO binds the REPORT CONTENT to Codex's RAW OUTPUT by
# re-validating the raw response with the SAME trusted jq gate and asserting
# field-for-field equality + index-bound fingerprint recomputation — so a
# bridge cannot fabricate, edit, add, or drop a finding without detection.
#
# Every failure → exit 2 (fail-closed: anything not fully proven is "NOT
# verified"). Full success → exit 0 with
#   verified — codex session <id> reviewed <head>
#
# Modes:
#   live (default)  freshness asserts audit_report.reviewed_head == the repo's
#                   CURRENT HEAD (a stale audit after later commits fails).
#   --reference     freshness asserts audit_report.reviewed_head ==
#                   manifest.head_sha (the commit captured at run time), so a
#                   COMMITTED historical fixture still verifies after HEAD moves.
#
# Provenance chain note: c3-dispatch.json does not carry the legacy
# input_manifest_hash (it is not in the dispatch artifact — see
# _write_dispatch_json), so step 7(a) binds the load-bearing 2-way chain
# audit_report.input_manifest_hash == manifest.input_hash. The codex_brief_hash
# chain (7b) is bound 3-way (recompute == manifest == dispatch == report).
# ===========================================================================

# _vfail <reason>  — emit a verify failure reason on stderr and exit 2 (the
# single fail-closed exit for every NOT-verified condition).
_vfail() {
  echo "verify: NOT verified — $1" >&2
  exit 2
}

# _file_sha_pref <file>  — "sha256:<64hex>" over a file's raw bytes; empty (→ a
# guaranteed mismatch on any later compare) when the file is missing/unreadable,
# so a pruned/edited artifact fails a hash check rather than crashing.
_file_sha_pref() {
  local f="$1"
  [[ -f "$f" && -r "$f" ]] || { printf ''; return 0; }
  printf 'sha256:%s' "$(sha256sum "$f" | awk '{print $1}')"
}

# _recompute_codex_brief_hash <evidence_dir> <manifest>
#   Re-derive codex_brief_hash EXACTLY as build-manifest does: re-hash every
#   codex_brief_files[] entry from disk (fail if any diverges from the stored
#   sha256 — a pruned/altered brief), rebuild the canonical
#   {base_sha,head_sha,codex_brief_files,required_independence_level} object with
#   the SAME LC_ALL=C path-sorted array order + `jq -S -c`, and sha256 it. Echoes
#   "sha256:<64hex>" on success; returns non-zero (reason on stderr) on any
#   pruned/altered brief file so the re-hash is byte-identical to build-manifest.
_recompute_codex_brief_hash() {
  local evidence_dir="$1" manifest="$2"
  local base_sha head_sha level
  base_sha="$(jq -r '.audit_input_manifest.base_sha // ""' "$manifest" 2>/dev/null)" || return 1
  head_sha="$(jq -r '.audit_input_manifest.head_sha // ""' "$manifest" 2>/dev/null)" || return 1
  level="$(jq -r '.audit_input_manifest.required_independence_level // ""' "$manifest" 2>/dev/null)" || return 1

  # Path list in the SAME LC_ALL=C sorted order build-manifest stored + hashed.
  local paths=()
  mapfile -t paths < <(jq -r '.audit_input_manifest.codex_brief_files[].path' "$manifest" 2>/dev/null | LC_ALL=C sort)
  [[ ${#paths[@]} -gt 0 ]] || { echo "manifest has no codex_brief_files" >&2; return 1; }

  local cbf_json="[]" p full h sz stored
  for p in "${paths[@]}"; do
    full="$evidence_dir/$p"
    [[ -f "$full" && -r "$full" ]] || { echo "brief file pruned/unreadable: $p" >&2; return 1; }
    h="$(sha256sum "$full" | awk '{print $1}')"
    stored="$(jq -r --arg p "$p" '.audit_input_manifest.codex_brief_files[] | select(.path==$p) | .sha256' "$manifest" 2>/dev/null | head -n1)"
    [[ "sha256:$h" == "$stored" ]] || { echo "brief file altered (sha256 diverged): $p" >&2; return 1; }
    sz="$(wc -c < "$full" | tr -d '[:space:]')"; [[ -n "$sz" ]] || sz=0
    cbf_json="$(printf '%s' "$cbf_json" \
      | jq -c --arg p "$p" --arg s "sha256:$h" --argjson z "$sz" '. + [{path:$p,sha256:$s,size:$z}]')" || return 1
  done

  local canonical
  canonical="$(jq -S -c -n \
    --arg base "$base_sha" --arg head "$head_sha" --argjson files "$cbf_json" --arg level "$level" \
    '{base_sha:$base,head_sha:$head,codex_brief_files:$files,required_independence_level:$level}')" || return 1
  printf 'sha256:%s' "$(_sha256_str "$canonical")"
}

cmd_verify() {
  # jq/sha256sum are hard requirements — fail closed if either is absent.
  command -v jq        >/dev/null 2>&1 || _vfail "jq not found in PATH"
  command -v sha256sum >/dev/null 2>&1 || _vfail "sha256sum not found in PATH"

  # --- arg parse: optional --reference, then <evidence_dir> ------------------
  local reference=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reference) reference=1; shift ;;
      --)          shift; break ;;
      -*)          _vfail "unknown flag: $1" ;;
      *)           break ;;
    esac
  done
  local evidence_dir="${1:-}"
  [[ -n "$evidence_dir" ]] || _vfail "usage: verify [--reference] <evidence_dir>"
  [[ -d "$evidence_dir" ]] || _vfail "evidence_dir not a directory: $evidence_dir"

  local c3_dir="$evidence_dir/c3"
  local report="$evidence_dir/audit-report.json"
  local manifest="$evidence_dir/audit-input-manifest.json"

  # --- Step 0 (P065 E-065-7_7 DONE-review Finding B): resolve the CURRENT
  # attempt's raw-evidence directory, if this evidence_dir has ever used
  # AID_C3_ATTEMPT layering. Raw dispatch artifacts (c3-dispatch.json,
  # codex-last-message.json, codex-events.jsonl, codex-prompt.txt) are
  # written ONLY under c3/attempt-NN/c3/ — never mirrored to the canonical
  # c3/ root — so a plain `verify <evidence_dir>` after an attempt-mode
  # dispatch must read them from there, not from the legacy c3/ location.
  # c3/loop-summary.json's current_attempt (set by _c3_write_loop_summary,
  # unconditionally, on every _c3_finalize_attempt call) is the single
  # source of truth for "which attempt is canonical right now." Absent
  # entirely (this evidence_dir never used AID_C3_ATTEMPT) → unchanged
  # legacy behavior.
  local loop_summary="$c3_dir/loop-summary.json"
  if [[ -f "$loop_summary" ]]; then
    jq -e . "$loop_summary" >/dev/null 2>&1 \
      || _vfail "c3/loop-summary.json is not valid JSON"
    local cur_attempt
    cur_attempt="$(jq -r '.current_attempt // empty' "$loop_summary" 2>/dev/null)"
    if [[ -n "$cur_attempt" ]]; then
      [[ "$cur_attempt" =~ ^[1-9][0-9]*$ ]] \
        || _vfail "c3/loop-summary.json current_attempt is not a positive integer: $cur_attempt"
      local cur_nn resolved_attempt_dir
      cur_nn="$(printf '%02d' "$cur_attempt")"
      resolved_attempt_dir="$c3_dir/attempt-$cur_nn"
      [[ -d "$resolved_attempt_dir" ]] \
        || _vfail "c3/loop-summary.json points at attempt-$cur_nn but c3/attempt-$cur_nn/ is missing"
      # The canonical report must be EXACTLY this attempt's own report — a
      # diverged pointer or a stale/hand-copied canonical report must fail
      # closed rather than silently verify raw evidence against the wrong
      # report.
      [[ -f "$resolved_attempt_dir/audit-report.json" ]] \
        || _vfail "c3/attempt-$cur_nn/audit-report.json is missing"
      cmp -s "$resolved_attempt_dir/audit-report.json" "$report" \
        || _vfail "canonical audit-report.json does not match c3/attempt-$cur_nn/audit-report.json (report and raw evidence must come from the same attempt)"
      c3_dir="$resolved_attempt_dir/c3"
    fi
  fi

  local dispatch_json="$c3_dir/c3-dispatch.json"
  local last_msg="$c3_dir/codex-last-message.json"
  local events="$c3_dir/codex-events.jsonl"

  # --- Step 1: every required artifact must exist ---------------------------
  # The manifest is required too (steps 6a/7/8 read it); a hand-forged report
  # with no c3-dispatch.json fails HERE even if it claims status:pass.
  local f
  for f in "$dispatch_json" "$report" "$last_msg" "$events" "$manifest"; do
    [[ -f "$f" ]] || _vfail "required artifact missing: ${f#"$evidence_dir"/}"
  done
  jq -e . "$dispatch_json" >/dev/null 2>&1 || _vfail "c3-dispatch.json is not valid JSON"
  jq -e . "$report"        >/dev/null 2>&1 || _vfail "audit-report.json is not valid JSON"
  jq -e . "$manifest"      >/dev/null 2>&1 || _vfail "audit-input-manifest.json is not valid JSON"

  # --- Step 2: dispatch provenance says codex genuinely ran cross_provider --
  local d_invoked d_exit d_outcome d_events_valid d_session d_indep
  d_invoked="$(jq -r '.dispatch.invoked'       "$dispatch_json" 2>/dev/null || true)"
  d_exit="$(jq -r '.dispatch.exit_code'        "$dispatch_json" 2>/dev/null || true)"
  d_outcome="$(jq -r '.dispatch.outcome'       "$dispatch_json" 2>/dev/null || true)"
  d_events_valid="$(jq -r '.dispatch.events_valid' "$dispatch_json" 2>/dev/null || true)"
  d_session="$(jq -r '.dispatch.codex_session_id // ""' "$dispatch_json" 2>/dev/null || true)"
  d_indep="$(jq -r '.independence.achieved_independence_level' "$dispatch_json" 2>/dev/null || true)"
  [[ "$d_invoked" == "true" ]]              || _vfail "dispatch.invoked != true (codex was not invoked)"
  [[ "$d_exit" == "0" ]]                    || _vfail "dispatch.exit_code != 0 (codex exited: $d_exit)"
  [[ "$d_outcome" == "dispatched" ]]        || _vfail "dispatch.outcome != dispatched (: $d_outcome)"
  [[ "$d_events_valid" == "true" ]]         || _vfail "dispatch.events_valid != true"
  [[ -n "$d_session" && "$d_session" != "null" ]] || _vfail "dispatch.codex_session_id is empty"
  [[ "$d_indep" == "cross_provider" ]]      || _vfail "achieved_independence_level != cross_provider (: $d_indep)"

  # --- Step 3: recorded stdout/raw sha pinned to the ACTUAL captured streams -
  # (proves the event stream and the raw response were not swapped or edited.)
  local d_stdout_sha d_raw_sha events_sha last_sha
  d_stdout_sha="$(jq -r '.dispatch.stdout_sha256 // ""'       "$dispatch_json" 2>/dev/null || true)"
  d_raw_sha="$(jq -r '.dispatch.raw_response_sha256 // ""'    "$dispatch_json" 2>/dev/null || true)"
  events_sha="$(_file_sha_pref "$events")"
  last_sha="$(_file_sha_pref "$last_msg")"
  [[ -n "$d_stdout_sha" && "$d_stdout_sha" == "$events_sha" ]] \
    || _vfail "stdout_sha256 != sha256(codex-events.jsonl) (event stream swapped/edited)"
  [[ -n "$d_raw_sha" && "$d_raw_sha" == "$last_sha" ]] \
    || _vfail "raw_response_sha256 != sha256(codex-last-message.json) (raw response swapped/edited)"

  # --- Step 4: RE-VALIDATE the raw response with the SAME trusted jq gate ----
  # (types/enums/forbidden-top-level/action_owner-for-high + multi-document
  # guard — NOT trusting Codex's --output-schema. Reuses Step-6 _validate_response.)
  _validate_response "$last_msg" || _vfail "raw response fails the trusted _validate_response gate"

  # Identity as _normalize consumed it (project_id/epic_id from the manifest).
  local project_id epic_id
  project_id="$(jq -r '.identity.project_id // "unknown"' "$manifest" 2>/dev/null || true)"
  [[ -n "$project_id" && "$project_id" != "null" ]] || project_id="unknown"
  epic_id="$(jq -r '.identity.epic_id // ""' "$manifest" 2>/dev/null || true)"

  # --- Step 5 (SECURITY REGRESSION FIX, E-065-4_7, CP3 finding): status /
  #     review_status / outcome / unverifiable_reasons binding ---------------
  # PROVEN BYPASS (pre-fix): none of the checks below this comment ever
  # examined the top-level .status, .audit_report.review_status,
  # .audit_report.outcome, or .audit_report.unverifiable_reasons fields — a
  # report whose top-level .status was hand-edited (e.g. genuine
  # "unverifiable" flipped to "pass", leaving reviewed_head/codex_brief_hash/
  # blocking_findings/findings/process_id untouched) still verified clean.
  # This block derives what those fields MUST be from the raw response via the
  # SAME _derive_report_semantics function the writers use, and fails closed on
  # any divergence. Purely additive — every existing Step 5 check below is
  # unchanged.
  local expected r_status r_review_status exp_status exp_review_status
  expected="$(_derive_report_semantics "$last_msg")" \
    || _vfail "cannot derive expected report semantics from the raw response"
  exp_status="$(jq -r '.status' <<<"$expected" 2>/dev/null)"
  exp_review_status="$(jq -r '.review_status' <<<"$expected" 2>/dev/null)"
  r_status="$(jq -r '.status' "$report" 2>/dev/null || true)"
  r_review_status="$(jq -r '.audit_report.review_status' "$report" 2>/dev/null || true)"
  [[ "$r_status" == "$exp_status" ]] \
    || _vfail "audit_report.status != expected-from-raw (report:${r_status} expected:${exp_status})"
  [[ "$r_review_status" == "$exp_review_status" ]] \
    || _vfail "audit_report.review_status != expected-from-raw (report:${r_review_status} expected:${exp_review_status})"

  if [[ "$exp_status" == "unverifiable" ]]; then
    local r_outcome exp_reasons r_reasons
    r_outcome="$(jq -r '.audit_report.outcome // ""' "$report" 2>/dev/null || true)"
    [[ "$r_outcome" == "review_unverifiable" ]] \
      || _vfail "audit_report.outcome != review_unverifiable (expected-unverifiable path; got: ${r_outcome})"
    exp_reasons="$(jq -Sc '.unverifiable_reasons | sort' <<<"$expected" 2>/dev/null || true)"
    r_reasons="$(jq -Sc '(.audit_report.unverifiable_reasons // []) | sort' "$report" 2>/dev/null || true)"
    [[ -n "$exp_reasons" && "$r_reasons" == "$exp_reasons" ]] \
      || _vfail "audit_report.unverifiable_reasons != raw.unverifiable_reasons"
  fi

  # --- Step 5 (pre-existing): faithful-transform equality — report <-> raw --
  local r_head r_brief r_block raw_head raw_brief raw_block
  r_head="$(jq -r '.audit_report.reviewed_head // ""'    "$report"  2>/dev/null || true)"
  r_brief="$(jq -r '.audit_report.codex_brief_hash // ""' "$report" 2>/dev/null || true)"
  r_block="$(jq -r '.audit_report.blocking_findings'     "$report"  2>/dev/null || true)"
  raw_head="$(jq -r '.reviewed_head // ""'    "$last_msg" 2>/dev/null || true)"
  raw_brief="$(jq -r '.codex_brief_hash // ""' "$last_msg" 2>/dev/null || true)"
  [[ "$r_head" == "$raw_head" ]]   || _vfail "audit_report.reviewed_head != raw.reviewed_head"
  [[ "$r_brief" == "$raw_brief" ]] || _vfail "audit_report.codex_brief_hash != raw.codex_brief_hash"

  # IMP-245 follow-up fix: when the raw response is honestly unverifiable, the
  # writer (_write_report's invariant + _write_unverifiable, both via
  # _derive_report_semantics) intentionally DISCARDS any findings/
  # blocking_findings Codex may have ALSO included alongside its unverifiable
  # verdict — a schema-valid combination (Codex may report concrete partial
  # findings while still declining an overall firm pass/fail; the response
  # schema does not restrict findings/blocking_findings when review_status is
  # "unverifiable"). Comparing the report's blocking_findings/findings against
  # RAW unconditionally (as this block used to, unguarded) breaks on exactly
  # that valid combination — a real live dogfood run under c3-audit-prompt-v2
  # hit this once Codex started returning substantive findings instead of
  # always-empty unverifiable responses (the same class of "writer/verify
  # diverge on a field neither side unified" bug the earlier CRITICAL fix
  # closed for status/review_status/outcome — this is the same root cause
  # surfacing on a different field). For the unverifiable branch, assert the
  # report matches the WRITER's own known, intentional discard
  # (blocking_findings: false, findings: []) rather than raw's actual findings.
  if [[ "$exp_status" == "unverifiable" ]]; then
    [[ "$r_block" == "false" ]] \
      || _vfail "audit_report.blocking_findings != false (required for the unverifiable branch)"
    local r_findings_count
    r_findings_count="$(jq '.findings | length' "$report" 2>/dev/null || true)"
    [[ "$r_findings_count" == "0" ]] \
      || _vfail "audit_report.findings is non-empty in the unverifiable branch (must be [])"
  else
    raw_block="$(jq -r '[.findings[] | select(.severity=="critical" or .severity=="high")] | length > 0' "$last_msg" 2>/dev/null || true)"
    [[ "$r_block" == "$raw_block" ]] || _vfail "audit_report.blocking_findings != (exists raw crit/high finding)"

    # Tuple-set equality — order-insensitive, count-sensitive, action_owner by
    # identical presence-AND-value on BOTH sides (a low/medium finding with no
    # owner in raw and none in report matches — B5). `-S` + `sort` canonicalise.
    local raw_tuples report_tuples
    raw_tuples="$(jq -Sc '[.findings[] | {severity,area,finding,recommendation}
                            + (if has("action_owner") then {action_owner} else {} end)] | sort' \
                  "$last_msg" 2>/dev/null || true)"
    report_tuples="$(jq -Sc '[.findings[] | {severity,area,finding,recommendation}
                               + (if has("action_owner") then {action_owner} else {} end)] | sort' \
                     "$report" 2>/dev/null || true)"
    [[ -n "$raw_tuples" && "$raw_tuples" == "$report_tuples" ]] \
      || _vfail "report findings tuple-set diverges from raw (a finding was added/removed/edited)"

    # Index-bound fingerprint/occurrence_id recompute FROM THE RAW finding — pins
    # each report finding to its raw source (a reordering that breaks recompute →
    # fail). occurrence_id = c3-<epic_id>-<n>; fingerprint via the shared helper.
    local raw_count report_count
    raw_count="$(jq '.findings | length'    "$last_msg" 2>/dev/null || true)"
    report_count="$(jq '.findings | length' "$report"   2>/dev/null || true)"
    [[ "$raw_count" =~ ^[0-9]+$ && "$report_count" =~ ^[0-9]+$ ]] || _vfail "cannot count findings"
    [[ "$raw_count" == "$report_count" ]] || _vfail "report/raw finding count differ ($report_count vs $raw_count)"

    local fp_helper="$SCRIPT_DIR/aid-finding-fingerprint.sh"
    local n sev area finding rec occ_expected fp_expected occ_actual fp_actual
    for (( n=0; n<raw_count; n++ )); do
      sev="$(jq -r --argjson i "$n" '.findings[$i].severity'       "$last_msg" 2>/dev/null || true)"
      area="$(jq -r --argjson i "$n" '.findings[$i].area'          "$last_msg" 2>/dev/null || true)"
      finding="$(jq -r --argjson i "$n" '.findings[$i].finding'    "$last_msg" 2>/dev/null || true)"
      rec="$(jq -r --argjson i "$n" '.findings[$i].recommendation' "$last_msg" 2>/dev/null || true)"
      occ_expected="c3-${epic_id}-${n}"
      fp_expected="$(bash "$fp_helper" fingerprint_audit_report "$project_id" audit_report "$occ_expected" "$sev" "$area" "$finding" "$rec" 2>/dev/null)" \
        || _vfail "cannot recompute fingerprint for finding $n"
      fp_expected="${fp_expected%$'\n'}"
      occ_actual="$(jq -r --argjson i "$n" '.findings[$i].occurrence_id // ""' "$report" 2>/dev/null || true)"
      fp_actual="$(jq -r --argjson i "$n" '.findings[$i].fingerprint // ""'    "$report" 2>/dev/null || true)"
      [[ "$occ_actual" == "$occ_expected" ]] || _vfail "finding $n occurrence_id mismatch (got '$occ_actual', expected '$occ_expected')"
      [[ "$fp_actual" == "$fp_expected" ]]    || _vfail "finding $n fingerprint does not recompute from the raw finding"
    done
  fi

  # --- Step 6: process_id binds to the dispatch session ---------------------
  local r_pid
  r_pid="$(jq -r '.audit_report.process_id // ""' "$report" 2>/dev/null || true)"
  [[ "$r_pid" == "$d_session" ]] || _vfail "audit_report.process_id != dispatch.codex_session_id"

  # --- Step 6a: prompt-template freshness -----------------------------------
  # A changed template (or an edited rendered prompt) INVALIDATES the report — a
  # new review must run with the new prompt.
  local d_tpl_sha d_rendered_sha cur_tpl_sha cur_rendered_sha prompt_txt
  d_tpl_sha="$(jq -r '.prompt.template_sha256 // ""'        "$dispatch_json" 2>/dev/null || true)"
  d_rendered_sha="$(jq -r '.prompt.rendered_prompt_sha256 // ""' "$dispatch_json" 2>/dev/null || true)"
  [[ -f "$PROMPT_TEMPLATE" ]] || _vfail "prompt template missing: $PROMPT_TEMPLATE"
  cur_tpl_sha="$(_file_sha_pref "$PROMPT_TEMPLATE")"
  [[ -n "$d_tpl_sha" && "$d_tpl_sha" == "$cur_tpl_sha" ]] \
    || _vfail "prompt template changed since dispatch (template_sha256 stale) — re-run the audit"
  prompt_txt="$c3_dir/codex-prompt.txt"
  [[ -f "$prompt_txt" ]] || _vfail "rendered prompt missing: c3/codex-prompt.txt"
  cur_rendered_sha="$(_file_sha_pref "$prompt_txt")"
  [[ -n "$d_rendered_sha" && "$d_rendered_sha" == "$cur_rendered_sha" ]] \
    || _vfail "rendered prompt edited (rendered_prompt_sha256 mismatch)"

  # --- Step 7(a): LEGACY input_manifest_hash chain --------------------------
  # audit_report.input_manifest_hash == manifest.input_hash (preserves the D7
  # chain the schema/auditor/FSM require). c3-dispatch.json does not carry this
  # field, so the chain is the load-bearing 2-way.
  local r_imh m_ih
  r_imh="$(jq -r '.audit_report.input_manifest_hash // ""' "$report"  2>/dev/null || true)"
  m_ih="$(jq -r '.audit_input_manifest.input_hash // ""'   "$manifest" 2>/dev/null || true)"
  [[ -n "$m_ih" && "$r_imh" == "$m_ih" ]] \
    || _vfail "input_manifest_hash chain broken (audit_report != manifest.input_hash)"

  # --- Step 7(b): CODEX brief hash — recompute + 3-way bind -----------------
  local recomputed m_bh d_bh r_bh
  recomputed="$(_recompute_codex_brief_hash "$evidence_dir" "$manifest")" \
    || _vfail "codex_brief recompute failed (a brief file was pruned or altered)"
  m_bh="$(jq -r '.audit_input_manifest.codex_brief_hash // ""' "$manifest"      2>/dev/null || true)"
  d_bh="$(jq -r '.subject.codex_brief_hash // ""'             "$dispatch_json" 2>/dev/null || true)"
  r_bh="$(jq -r '.audit_report.codex_brief_hash // ""'        "$report"        2>/dev/null || true)"
  [[ "$recomputed" == "$m_bh" ]] || _vfail "recomputed codex_brief_hash != manifest.codex_brief_hash"
  [[ "$recomputed" == "$d_bh" ]] || _vfail "recomputed codex_brief_hash != dispatch.codex_brief_hash"
  [[ "$recomputed" == "$r_bh" ]] || _vfail "recomputed codex_brief_hash != audit_report.codex_brief_hash"

  # --- Step 8: freshness (mode-dependent) -----------------------------------
  local r_reviewed_head expected_head
  r_reviewed_head="$(jq -r '.audit_report.reviewed_head // ""' "$report" 2>/dev/null || true)"
  if [[ "$reference" -eq 1 ]]; then
    expected_head="$(jq -r '.audit_input_manifest.head_sha // ""' "$manifest" 2>/dev/null || true)"
    [[ -n "$expected_head" ]] || _vfail "manifest has no head_sha (reference mode)"
    [[ "$r_reviewed_head" == "$expected_head" ]] \
      || _vfail "reviewed_head != manifest.head_sha (reference-mode freshness)"
  else
    expected_head="$(git -C "$evidence_dir" rev-parse HEAD 2>/dev/null || echo "")"
    [[ -n "$expected_head" ]] || _vfail "cannot resolve current HEAD (live mode)"
    [[ "$r_reviewed_head" == "$expected_head" ]] \
      || _vfail "reviewed_head != current HEAD (live-mode freshness — stale audit)"
  fi

  # --- Step 9: all checks held ----------------------------------------------
  echo "verified — codex session $d_session reviewed $r_reviewed_head"
  return 0
}

# cmd_escalate <evidence_dir> <reason>
#   E-065-6_7 DONE-review round 4: pipeline.md 6a's "the findings are mutually
#   conflicting" exit condition is a subjective controller judgment call the
#   bridge cannot detect mechanically (unlike same-fingerprint-survival, which
#   _c3_write_loop_summary now detects and escalates on its own). Before this,
#   there was no way for the controller to durably RECORD that judgment —
#   meaning nothing stopped a later stray/automatic AID_C3_ATTEMPT dispatch
#   from reopening a loop the controller had already decided to end. This
#   subcommand gives the controller that missing write path: mark an
#   IN-PROGRESS loop's c3/loop-summary.json outcome "escalated" directly, so
#   the same terminal guard `dispatch` already enforces for every other
#   escalation picks it up on the very next explicit-attempt call.
cmd_escalate() {
  if [[ $# -ne 2 ]]; then
    usage >&2
    echo "PRECONDITION FAIL: escalate requires exactly 2 args: <evidence_dir> <reason>" >&2
    exit 1
  fi
  local evidence_dir="$1" reason="$2"
  [[ "${#reason}" -ge 20 ]] \
    || _fail "escalate reason must be >= 20 characters (got: ${#reason}) — a real, auditable justification is required"

  local summary="$evidence_dir/c3/loop-summary.json"
  [[ -f "$summary" ]] \
    || _fail "no c3/loop-summary.json at $evidence_dir — nothing to escalate (escalate marks an IN-PROGRESS fix-loop terminal; it does not create one from nothing)"

  local cur_outcome
  # CORRECTNESS FIX (E-065-6_7 DONE-review C3 finding, round 5): the original
  # check only rejected "clean", implicitly allowing "unverifiable" (and even
  # an already-"escalated") summary to be escalated too. "unverifiable" is
  # NOT an in-progress-blocking state — per pipeline.md 6a's "not a loop
  # iteration" carve-out (rounds 3-4) it must stay freely retriable, so
  # forcing it to "escalated" here would wrongly terminate a state the rest
  # of the bridge deliberately keeps open. escalate is for ending an
  # IN-PROGRESS (still-blocking, not yet terminal) loop early on a
  # controller's judgment call — that state is represented by exactly one
  # value: a JSON `null` outcome, which `jq -r '.outcome // ""'` reads back
  # as the empty string. Fail closed on every other value (clean, escalated,
  # unverifiable, or anything unrecognized).
  cur_outcome="$(jq -r '.outcome // ""' "$summary" 2>/dev/null)"
  [[ -z "$cur_outcome" ]] \
    || _fail "c3/loop-summary.json already recorded a terminal or non-actionable outcome (\"$cur_outcome\") — escalate only applies to an in-progress, still-blocking loop; refusing to overwrite \"$cur_outcome\""

  local tmp="$summary.tmp.$$" iso_now
  iso_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq --arg reason "$reason" --arg recorded_at "$iso_now" \
    '.outcome = "escalated" | .escalation_reason = "conflicting_findings" |
     .manual_escalation = {reason: $reason, recorded_at: $recorded_at}' \
    "$summary" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; _fail "cannot compute updated loop-summary.json"; }
  mv -f "$tmp" "$summary" 2>/dev/null \
    || { rm -f "$tmp"; _fail "cannot write updated loop-summary.json"; }

  echo "aid-c3-dispatch: c3/loop-summary.json marked outcome=\"escalated\" (conflicting_findings): $reason" >&2
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
    dispatch)
      cmd_dispatch "$@"
      ;;
    verify)
      cmd_verify "$@"
      ;;
    escalate)
      cmd_escalate "$@"
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

# Only run the CLI dispatcher when executed directly; when sourced (e.g. by the
# bats suite to unit-test _validate_response / _process_response in isolation),
# just define the functions. Mirrors aid-finding-fingerprint.sh's guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
