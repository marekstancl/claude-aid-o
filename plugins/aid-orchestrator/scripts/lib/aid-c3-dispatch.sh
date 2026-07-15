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
PROMPT_TEMPLATE="$PLUGIN_ROOT/defaults/prompts/c3-audit-prompt-v1.md"
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

  verify
      Not yet implemented (later EPIC step).
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
#   ⚠️ DISCOVERED ISSUE — `--output-schema` is deliberately NOT passed. Step 4's
#   c3-codex-response.schema.json uses `if/then/else` + `allOf`, and Step 1's
#   empirical finding (codex-stream-sample/fields.md §`--output-schema empirical
#   behavior`) is that Codex forwards the schema to OpenAI strict structured
#   output, which HARD-FAILS (HTTP 400 "'if' is not permitted") on any
#   conditional keyword. Passing it would 400 every dispatch. The trusted gate
#   is the bridge's own _validate_response (Step 6, next step), NOT the backend.
#   We do NOT strip if/then from the schema to work around this — it is not ours
#   to change, and the conditional rules are load-bearing for bridge validation.
#
#   Returns the codex/timeout exit code (124 = timed out).
_run_codex_isolated() {
  local project_root="$1" prompt_file="$2" events_out="$3" stderr_out="$4" last_out="$5"
  local prompt rc=0
  prompt="$(cat "$prompt_file")"
  timeout "${AID_C3_TIMEOUT_SECONDS:-900}" \
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
# cmd_dispatch <evidence_dir>
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

  local manifest="$evidence_dir/audit-input-manifest.json"
  [[ -f "$manifest" ]] || { echo "PRECONDITION FAIL: manifest missing (run build-manifest first): $manifest" >&2; exit 1; }

  local c3_dir="$evidence_dir/c3"
  mkdir -p "$c3_dir" || { echo "PRECONDITION FAIL: cannot create $c3_dir" >&2; exit 1; }

  # --- Step 1: read the sealed brief provenance from the manifest -------------
  local base_sha head_sha codex_brief_hash required_level input_hash
  base_sha="$(jq -r '.audit_input_manifest.base_sha // ""' "$manifest")"
  head_sha="$(jq -r '.audit_input_manifest.head_sha // ""' "$manifest")"
  codex_brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash // ""' "$manifest")"
  required_level="$(jq -r '.audit_input_manifest.required_independence_level // "cross_provider"' "$manifest")"
  input_hash="$(jq -r '.audit_input_manifest.input_hash // ""' "$manifest")"
  [[ -n "$head_sha" ]] || { echo "PRECONDITION FAIL: manifest has no head_sha" >&2; exit 1; }

  # --- Step 1 (cont): resolve project_root = the real repo root --------------
  local project_root
  project_root="$(git -C "$evidence_dir" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "PRECONDITION FAIL: evidence_dir is not inside a git repository: $evidence_dir" >&2; exit 1; }

  # --- Step 2: executor = codex_cli (hardcoded default; full policy = Step 8) -
  # Only kind that exists; fail-closed default per the plan.
  local executor_kind="codex_cli"

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
    _write_dispatch_json "$c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
      "$required_level" "" "" "" "" "false" "" "unavailable" "" "$CODEX_MODEL" "false" "" "" "unavailable"
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

  local vars_json="$c3_dir/codex-prompt-vars.json"
  jq -n \
    --arg plan_path "c3/bundle-plan-ac.md" \
    --arg plan_sha256 "$plan_sha256" \
    --arg base_sha "$base_sha" \
    --arg head_sha "$head_sha" \
    --arg input_manifest_path "audit-input-manifest.json" \
    --arg input_manifest_hash "$input_manifest_hash" \
    --arg codex_brief_hash "$codex_brief_hash" \
    --arg bundle_diff_path "c3/bundle-diff.patch" \
    --arg bundle_scope_path "c3/bundle-scope.txt" \
    --arg acceptance_criteria_path "c3/bundle-plan-ac.md" \
    --arg review_profile_path "c3/bundle-review-profile.json" \
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

  local prompt_file="$c3_dir/codex-prompt.txt"
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
    _write_dispatch_json "$c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
      "$required_level" "" "" "" "" "false" "" "render_failed" "" "$CODEX_MODEL" "false" "" "" "unavailable"
    exit 2
  fi

  # --- Step 5: codex_version (best effort; slug is NOT in the stream) ---------
  local codex_version
  codex_version="$(codex --version 2>/dev/null || echo "")"

  # --- Step 6: launch codex (fresh, read-only, isolated) and capture ---------
  local events_file="$c3_dir/codex-events.jsonl"
  local stderr_file="$c3_dir/codex-events.stderr"
  local last_msg_file="$c3_dir/codex-last-message.json"
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

  _write_dispatch_json "$c3_dir/c3-dispatch.json" "$project_root" "$head_sha" "$codex_brief_hash" \
    "$required_level" "$template_id" "$template_sha256" "$rendered_prompt_sha256" "$codex_version" \
    "true" "$codex_rc" "$outcome" "$session_id" "$CODEX_MODEL" "$events_valid" \
    "$stdout_sha256" "$raw_response_sha256" "$achieved" \
    || { echo "PRECONDITION FAIL: cannot write c3-dispatch.json" >&2; exit 1; }

  # --- Step 8: exit status -----------------------------------------------------
  # 0 iff dispatched + events_valid (achieved cross_provider). Everything else
  # (timeout / rate_limited / failed) signals unavailability → exit 2. The raw
  # output is handed to Step 6's normalize/validate as-is; the bridge NEVER runs
  # a fallback of its own.
  echo "$c3_dir/c3-dispatch.json"
  if [[ "$outcome" == "dispatched" ]]; then
    return 0
  else
    exit 2
  fi
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
      # LATER EPIC step (Step 7) — deliberately not implemented here.
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
