#!/usr/bin/env bash
# =============================================================================
# aid-plan-to-epic.sh — Convert a Plan.md file into an EPIC.md for a given phase
#
# Usage:
#   ./aid-plan-to-epic.sh \
#     --plan <path> --phase <N> --total <T> \
#     --epic-template <path> --output-dir <path> --counter-yaml <path> \
#     [--project-root <workspace>] \
#     [--generation-authority <path> --transaction <path>]
#
# --generation-authority / --transaction (P074 Step 14, both or neither):
# verify the pipeline's sealed plan-scoped CP1 decision instead of re-running
# the CP1 gate for this phase. Without them the per-invocation gate runs
# exactly as before.
#
# Reads the plan, extracts phase-specific steps, fills the EPIC template,
# and writes the completed EPIC to the output directory.
#
# stdout: Absolute path to the generated EPIC file
# stderr: JSON error on failure (see Exit Codes in README.md)
#
# Exit codes: 0=success, 1=validation, 2=dependency, 3=I/O
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
# Shared per-step scoping helpers (single source of truth with aid-epic-to-json.sh,
# gates/aid-contract-validate.sh and aid-plan-lint.sh) — provides the ONE Files-block
# bullet extractor (_aid_extract_files_bullets) + path cleaner (_aid_split_path_entry).
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
check_prerequisites

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
plan=""
phase=""
total=""
epic_template=""
output_dir=""
counter_yaml=""
project_root=""
generation_authority=""   # P074 Step 14 — sealed plan-scoped CP1 decision
generation_transaction="" # P074 Step 14 — the transaction that owns this phase

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)        plan="$2";          shift 2 ;;
    --phase)       phase="$2";         shift 2 ;;
    --total)       total="$2";         shift 2 ;;
    --epic-template) epic_template="$2"; shift 2 ;;
    --output-dir)  output_dir="$2";    shift 2 ;;
    --counter-yaml) counter_yaml="$2"; shift 2 ;;
    --project-root) project_root="$2"; shift 2 ;;
    --generation-authority) generation_authority="$2"; shift 2 ;;
    --transaction)          generation_transaction="$2"; shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -z "$plan" ]]          && error_exit "Missing required argument: --plan" 1
[[ -z "$phase" ]]         && error_exit "Missing required argument: --phase" 1
[[ -z "$total" ]]         && error_exit "Missing required argument: --total" 1
[[ -z "$epic_template" ]] && error_exit "Missing required argument: --epic-template" 1
[[ -z "$output_dir" ]]    && error_exit "Missing required argument: --output-dir" 1
[[ -z "$counter_yaml" ]]  && error_exit "Missing required argument: --counter-yaml" 1

# Validate files exist
[[ ! -f "$plan" ]]          && error_exit "Plan file not found: $plan" 3
[[ ! -f "$epic_template" ]] && error_exit "EPIC template not found: $epic_template. Run /aid-init to deploy templates." 2
[[ ! -d "$output_dir" ]]    && error_exit "Output directory not found: $output_dir" 3
[[ -n "$project_root" && ! -d "$project_root/.aid-o" ]] && error_exit "--project-root must name an AID workspace containing .aid-o: $project_root" 3

# Validate phase/total are positive integers
[[ ! "$phase" =~ ^[0-9]+$ ]] && error_exit "Phase must be a positive integer, got: $phase" 1
[[ ! "$total" =~ ^[0-9]+$ ]] && error_exit "Total must be a positive integer, got: $total" 1
[[ "$phase" -lt 1 || "$phase" -gt "$total" ]] && error_exit "Phase $phase out of range (1-$total)" 1

# ---------------------------------------------------------------------------
# Step 1: Parse plan frontmatter — extract plan ID
# ---------------------------------------------------------------------------
frontmatter="$(parse_frontmatter "$plan")"

plan_id=""
while IFS='=' read -r key val; do
  case "$key" in
    id) plan_id="$val" ;;
  esac
done <<< "$frontmatter"

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1

# ---------------------------------------------------------------------------
# Step 1a: generation readiness — the canonical pre-generation contract.
# It runs Files lint plus the shared SOURCE-plan dependency parser/whole-plan
# graph before any EPIC exists.  This removes the former circular requirement
# for plan-graph.json (which used to be produced only after generation), and
# makes direct script use receive the same concise author guidance as /aid-plan.
READINESS_SCRIPT="${SCRIPT_DIR}/aid-generation-readiness.sh"
# Resolve once: the same plan-scoped evidence root is consumed by CP1/C0.
_project_root=""
if [[ -n "$project_root" ]]; then
  # The caller's workspace is authoritative when a plan is deliberately kept
  # outside `.aid-o/plans/` (fixtures, imports, or a controller-owned plan).
  # Searching from that external source path can otherwise bind evidence to an
  # unrelated enclosing checkout.
  _project_root="$(realpath "$project_root")"
else
  _search_dir="$(dirname "$(realpath "$plan")")"
  while [[ "$_search_dir" != "/" ]]; do
    if [[ -d "${_search_dir}/.aid-o" ]]; then _project_root="$_search_dir"; break; fi
    _search_dir="$(dirname "$_search_dir")"
  done
  [[ -z "$_project_root" ]] && _project_root="$(dirname "$(realpath "$plan")")"
fi
_ready_args=("$plan" --total "$total")
# Source graph is a real, hashed C0 input when this is an AID project. It is
# regenerated deterministically from the plan, never hand-authored.  Keep it
# under generation/: c0/plan-graph.json has a different owner and meaning
# after an EPIC exists (aid-c0-contract.sh's per-EPIC contract graph).
# A project may keep a valid plan outside `.aid-o/plans/` (fixtures, imported
# plans and older workspaces do). Evidence ownership is determined by the
# discovered project root and frontmatter plan id, not by the source path; do
# not make those legitimate callers miss the required provisional graph.
if [[ -d "${_project_root}/.aid-o" ]]; then
  _ready_args+=(--write-provisional "${_project_root}/.aid-o/work/evidence/${plan_id}/generation/provisional-graph.json")
fi
if [[ -x "$READINESS_SCRIPT" || -f "$READINESS_SCRIPT" ]]; then
  _ready_out="$(bash "$READINESS_SCRIPT" "${_ready_args[@]}" 2>&1)" && _ready_rc=0 || _ready_rc=$?
  if [[ "$_ready_rc" -ne 0 ]]; then
    printf '%s\n' "$_ready_out" >&2
    error_exit "Generation readiness failed for $plan; repair the source-plan diagnostics before creating any EPIC." 7
  elif [[ "$phase" -eq 1 && -n "$_ready_out" ]]; then
    printf '%s\n' "$_ready_out" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Step 1b: CP1-deep evidence gate (high-risk plans only)
#
# The gate script exits 0 for low-risk plans (no-op) and exits non-zero for
# high-risk plans that are missing CP1-deep evidence or have unresolved
# accepted blockers from the adjudicator. Producer-before-consumer: this
# check runs after plan_id is known but before any EPIC artifacts are written.
# ---------------------------------------------------------------------------
#
# P074 STEP 14 — AUTHORITY VERIFICATION INSTEAD OF A PER-PHASE GATE.
#
# THE GROUNDED FAILURE (F2, live 2026-08-04): this call is unconditional per
# invocation and the gate's one-shot PM-override memo is function-local, so a
# 3-phase plan demanded 3 PM artifacts and got worked around with a watcher —
# the anti-pattern §16a explicitly forbids normalizing. The pipeline now runs
# the gate ONCE per plan and seals the decision; each phase VERIFIES that seal.
#
# HONEST CLASSIFICATION (AID-v3 §1): the authority receipt, like every AID
# artifact, is FORGEABLE by a Bash-capable actor — there is no actor
# impossibility here and none is claimed. What enforces the decision is the
# BINDING plus audit detectability: a forged or replayed receipt must still
# match the real plan bytes, the real target head, this phase's independently
# re-derived ids, and the owning transaction's authority_sha256, and every
# forced authority carries the three P073 audit records. A leaked authority
# file is therefore useless outside its own transaction.
#
# WITHOUT the flags, the standalone per-invocation gate below runs unchanged.
# ---------------------------------------------------------------------------
if { [[ -n "$generation_authority" ]] && [[ -z "$generation_transaction" ]]; } \
   || { [[ -z "$generation_authority" ]] && [[ -n "$generation_transaction" ]]; }; then
  error_exit "--generation-authority and --transaction must be passed together (a receipt without its owning transaction proves nothing, and a transaction without its receipt has no sealed decision). Run generation through aid-auto-pipeline.sh." 1
fi

# THE id derivation, shared with aid-auto-pipeline.sh (which SEALS these ids
# into the transaction) and aid-epic-to-json.sh — plus the version that
# derivation is stamped with. Sourcing it is what makes the verification below
# a comparison between the RECORDED value and a FRESHLY DERIVED one rather
# than a comparison between two hand-maintained copies that could drift apart
# silently.
# shellcheck source=lib/aid-generation-ids.sh
source "${SCRIPT_DIR}/lib/aid-generation-ids.sh"

# _validate_against_schema <document> <schema.json> <label>
#   A small, dependency-free draft-07 subset validator: `required`, `type`,
#   `const`, `pattern`, `minimum`, `minLength`, `additionalProperties: false`,
#   and one level of `additionalProperties: {object schema}` (the transaction's
#   phases map). Enough to make "fails its schema" a real statement about these
#   two documents rather than a spot check, and it fails CLOSED if the schema
#   file itself is missing.
_validate_against_schema() {
  local doc="$1" schema="$2" label="$3"
  [[ -f "$schema" ]] \
    || error_exit "cannot validate the ${label}: schema ${schema} is missing — the verifier is fail-closed and will not accept an unvalidated document." 2
  local errs rc=0
  errs="$(jq -r -n --slurpfile d "$doc" --slurpfile s "$schema" '
    def typeok($v; $t):
      if $t == null then true
      elif ($t | type) == "array" then ([ $t[] | typeok($v; .) ] | any)
      elif $t == "integer" then (($v | type) == "number" and (($v | floor) == $v))
      elif $t == "null" then ($v == null)
      else (($v | type) == $t) end;

    # NOT `$sch.additionalProperties // true`: jq treats FALSE as empty for
    # `//`, so the literal `false` this validator exists to honour would
    # silently become `true` and every unknown property would be allowed.
    def ap($sch): if ($sch | has("additionalProperties")) then $sch.additionalProperties else true end;

    def check($val; $sch; $path):
      ( if ($sch | has("const")) and ($val != $sch.const)
          then ["\($path): must be \($sch.const | tojson)"] else [] end )
      + ( if ($sch.type != null) and (typeok($val; $sch.type) | not)
            then ["\($path): expected \($sch.type | tojson), got \($val | type)"] else [] end )
      + ( if ($sch.pattern != null) and (($val | type) == "string") and (($val | test($sch.pattern)) | not)
            then ["\($path): does not match /\($sch.pattern)/"] else [] end )
      + ( if ($sch.minLength != null) and (($val | type) == "string") and (($val | length) < $sch.minLength)
            then ["\($path): shorter than minLength \($sch.minLength)"] else [] end )
      + ( if ($sch.minimum != null) and (($val | type) == "number") and ($val < $sch.minimum)
            then ["\($path): below minimum \($sch.minimum)"] else [] end )
      + ( if ($val | type) == "object"
            then [ ($sch.required // [])[] as $k | select(($val | has($k)) | not)
                   | "\($path).\($k): required property is missing" ]
            else [] end )
      + ( if ($val | type) == "object" and (ap($sch) == false)
            then [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k)) | not)
                   | "\($path).\($k): property is not allowed (additionalProperties: false)" ]
            else [] end )
      + ( if ($val | type) == "object"
            then ( [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k))) | $k ]
                   | map(. as $k | check($val[$k]; $sch.properties[$k]; "\($path).\($k)")) | add // [] )
            else [] end )
      + ( if ($val | type) == "object" and ((ap($sch) | type) == "object")
            then ( [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k)) | not) | $k ]
                   | map(. as $k | check($val[$k]; ap($sch); "\($path).\($k)")) | add // [] )
            else [] end );

    check($d[0]; $s[0]; "$") | unique | join("; ")
  ' 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    error_exit "cannot validate the ${label} ${doc} against ${schema} (unreadable or malformed JSON) — the verifier is fail-closed." 1
  fi
  [[ -z "$errs" ]] && return 0
  error_exit "${label} ${doc} fails its schema ($(jq -r '."$id" // "unknown"' "$schema")): ${errs}" 1
}

_verify_generation_authority() {
  local auth="$1" tx="$2"
  # FAIL-CLOSED BY DEFINITION: no jq, no verification, no generation.
  command -v jq >/dev/null 2>&1 \
    || error_exit "generation authority verification requires jq, which is unavailable — the verifier is fail-closed by definition and will not fall back to gate-less generation." 2
  [[ -f "$auth" ]] || error_exit "generation authority not readable: ${auth} — run generation through aid-auto-pipeline.sh (never a gate-less fallback)." 1
  [[ -f "$tx" ]]   || error_exit "generation transaction not readable: ${tx} — a transaction is never implicitly recreated mid-run. Run generation through aid-auto-pipeline.sh." 1

  # SCHEMA VALIDATION of BOTH documents against the shipped schemas: every
  # `required` key present with the declared type, and `additionalProperties:
  # false` honoured. Field-presence spot checks are not enough — a document
  # could carry an unknown field, a wrong type, or a missing required key and
  # still pass. The schemas are the source of truth;
  # jq walks them so no external validator is required (and a missing
  # validator can never become a silent skip).
  local schema_dir="${SCRIPT_DIR}/../defaults/schemas"
  _validate_against_schema "$auth" "${schema_dir}/generation-authority.schema.json" "generation authority"
  _validate_against_schema "$tx"   "${schema_dir}/generation-transaction.schema.json" "generation transaction"

  # self_sha256 — canonical JSON (`jq -S -c`) with the hash field NULLED.
  local recorded computed
  recorded="$(jq -r '.self_sha256' "$auth")"
  computed="$(jq -S -c '.self_sha256 = null' "$auth" | sha256sum | awk '{print $1}')"
  [[ "$recorded" == "$computed" ]] \
    || error_exit "generation authority self_sha256 mismatch: recorded ${recorded}, recomputed ${computed} — ${auth} was modified after it was sealed." 1

  # plan bytes
  local plan_now; plan_now="$(sha256sum "$plan" | awk '{print $1}')"
  [[ "$(jq -r '.plan_sha256' "$auth")" == "$plan_now" ]] \
    || error_exit "generation authority plan_sha256 does not match the plan on disk (sealed $(jq -r '.plan_sha256' "$auth"), current ${plan_now}) — the plan was edited after the authority was sealed. Supersede the transaction and regenerate." 1

  # target head — resolved the same way aid-auto-pipeline.sh resolves it.
  local orch tb head_now
  orch="${SCRIPT_DIR}/../defaults/orchestration.yaml"; tb=""
  if [[ -f "$orch" ]] && command -v yq >/dev/null 2>&1; then
    tb="$(yq -r '.lifecycle.target_branch // ""' "$orch" 2>/dev/null || true)"
  fi
  [[ -z "$tb" || "$tb" == "null" ]] && tb="main"
  # The BRANCH itself, not only the commit it points at: an authority sealed
  # against a different integration branch that happens to share a head today
  # would otherwise verify.
  [[ "$(jq -r '.target_branch' "$auth")" == "$tb" ]] \
    || error_exit "generation authority target_branch is '$(jq -r '.target_branch' "$auth")' but this workspace's configured integration branch is '${tb}' — the authority was sealed for a different branch. Supersede the transaction and regenerate." 1
  head_now="$(git -C "$_project_root" rev-parse --verify --quiet "${tb}^{commit}" 2>/dev/null || true)"
  [[ "$(jq -r '.target_head' "$auth")" == "$head_now" ]] \
    || error_exit "generation authority target_head does not match ${tb} (sealed $(jq -r '.target_head' "$auth"), current ${head_now:-<unresolved>}) — the target branch moved after the authority was sealed. Supersede the transaction and regenerate." 1

  # phase range + derivation version
  local sealed_total sealed_pdv
  sealed_total="$(jq -r '.total_phases' "$auth")"
  sealed_pdv="$(jq -r '.phase_derivation_version' "$auth")"
  [[ "$sealed_total" == "$total" ]] \
    || error_exit "generation authority total_phases (${sealed_total}) does not match this invocation's --total (${total})." 1
  [[ "$phase" -ge 1 && "$phase" -le "$sealed_total" ]] \
    || error_exit "phase ${phase} is outside the authorized range 1..${sealed_total}." 1
  [[ "$sealed_pdv" == "$AID_GEN_PHASE_DERIVATION_VERSION" ]] \
    || error_exit "generation authority was sealed under phase_derivation_version ${sealed_pdv} but this script derives phases at version ${AID_GEN_PHASE_DERIVATION_VERSION} — plugin upgraded mid-transaction; supersede and regenerate." 1

  # transaction linkage — a leaked authority is useless outside its own
  # transaction, and a foreign transaction cannot adopt it.
  [[ "$(jq -r '.authority_sha256 // ""' "$tx")" == "$recorded" ]] \
    || error_exit "transaction ${tx} is not bound to this authority (transaction.authority_sha256 $(jq -r '.authority_sha256 // "<null>"' "$tx"), authority.self_sha256 ${recorded}) — a replayed or foreign receipt." 1
  [[ "$(jq -r '.plan_id' "$tx")" == "$(jq -r '.plan_id' "$auth")" ]] \
    || error_exit "transaction plan_id $(jq -r '.plan_id' "$tx") does not match authority plan_id $(jq -r '.plan_id' "$auth")." 1

  # THE FULL IDENTITY TUPLE, both documents. The linkage hash alone only proves
  # the transaction NAMES this authority; a transaction whose own recorded
  # identity has drifted (a hand-edited or stale manifest) would otherwise
  # still pass. Identity is (plan_sha256, target_head,
  # phase_derivation_version, total_phases) — the exact tuple the authority
  # seals — so the two can never disagree about what is being generated.
  local a_id t_id
  a_id="$(jq -r '[.plan_sha256, .target_head, (.phase_derivation_version|tostring), (.total_phases|tostring)] | join("|")' "$auth")"
  t_id="$(jq -r '[.plan_sha256, .target_head, (.phase_derivation_version|tostring), (.total_phases|tostring)] | join("|")' "$tx")"
  [[ "$a_id" == "$t_id" ]] \
    || error_exit "transaction identity '${t_id}' does not match authority identity '${a_id}' (plan_sha256|target_head|phase_derivation_version|total_phases) — the pair describes two different generations. Supersede the transaction and regenerate." 1
  [[ "$t_id" == "${plan_now}|${head_now}|${AID_GEN_PHASE_DERIVATION_VERSION}|${total}" ]] \
    || error_exit "the sealed identity '${t_id}' does not describe this invocation ('${plan_now}|${head_now}|${AID_GEN_PHASE_DERIVATION_VERSION}|${total}')." 1

  # per-phase ids: RE-DERIVED here, NOW, from plan_id+phase+total and compared
  # against what the transaction recorded, so derivation drift between plugin
  # versions is caught at verify time rather than at queue time.
  #
  # THE TWO SIDES REMAIN INDEPENDENT even though one function produces both:
  # the recorded id was written by an earlier process from a possibly different
  # plugin version into a file an actor can edit, and the derived id is
  # computed here from this invocation's arguments. The sealed
  # phase_derivation_version (checked above) is what rules out the remaining
  # case — a transaction recorded under a DIFFERENT derivation — before these
  # ids are compared at all.
  local d_epic d_run r_epic r_run
  d_epic="$(aid_gen_epic_id "$plan_id" "$phase" "$total")"
  d_run="$(aid_gen_run_id "$d_epic")"
  r_epic="$(jq -r --arg p "$phase" '.phases[$p].epic_id // ""' "$tx")"
  r_run="$(jq -r --arg p "$phase" '.phases[$p].run_id // ""' "$tx")"
  [[ -n "$r_epic" ]] \
    || error_exit "transaction ${tx} has no record for phase ${phase} — the phase is not part of this transaction." 1
  [[ "$r_epic" == "$d_epic" ]] \
    || error_exit "phase ${phase} epic_id mismatch: transaction records ${r_epic}, this script derives ${d_epic}." 1
  [[ "$r_run" == "$d_run" ]] \
    || error_exit "phase ${phase} run_id mismatch: transaction records ${r_run}, this script derives ${d_run}." 1

  echo "[INFO] generation_authority: verified ${auth} for phase ${phase}/${total} (plan bytes, ${tb} head, phase range, re-derived ids, transaction linkage) — the CP1 gate is not re-run for this phase." >&2
}

CP1_GATE_SCRIPT="${SCRIPT_DIR}/aid-cp1-gate.sh"
if [[ -n "$generation_authority" ]]; then
  _verify_generation_authority "$generation_authority" "$generation_transaction"
elif [[ -f "$CP1_GATE_SCRIPT" ]]; then
  if ! bash "$CP1_GATE_SCRIPT" --plan "$plan" --project-root "$_project_root"; then
    # Gate script already emitted the human-readable error to stderr.
    exit 1
  fi
fi

plan_num="$(aid_gen_plan_num "$plan_id")"

# ---------------------------------------------------------------------------
# Step 2: Generate EPIC ID and slug
# ---------------------------------------------------------------------------
epic_id="$(aid_gen_epic_id "$plan_id" "$phase" "$total")"

# Extract plan title from H1 header
# Supports two formats:
#   "# Plan: Some Title"         → extracts "Some Title"
#   "# P019 — Some Title"        → extracts "Some Title" (strips "PNNN — " prefix)
#   "# P019 - Some Title"        → extracts "Some Title" (strips "PNNN - " prefix)
title="$(awk '
  { gsub(/\r$/, "") }
  /^# Plan:/ {
    sub(/^# Plan:[[:space:]]*/, "")
    print
    exit
  }
  /^# P[0-9]/ {
    sub(/^# P[0-9A-Za-z-]+[[:space:]]*[—–-][[:space:]]*/, "")
    print
    exit
  }
  /^# / {
    sub(/^# /, "")
    print
    exit
  }
' "$plan")"

[[ -z "$title" ]] && title="untitled"
slug="$(slugify "$title")"

# ---------------------------------------------------------------------------
# Step 3: Verify Implementation Steps section exists
#
# NOTE: We scan the ENTIRE plan file (not just the extracted section) for
# step headers and EPIC markers. This is because plans may contain fenced
# code blocks with ## headers that create false section boundaries, causing
# extract_section to miss steps in later phases. By scanning the whole file,
# we reliably find all ### Step N: headers and **EPIC N:** markers regardless
# of intervening ## headers inside code blocks.
# ---------------------------------------------------------------------------

# Quick check that a steps section exists (supports multiple formats)
# Plans use "## Implementation Steps" (detailed), "## High-Level Steps" (standard template),
# or may have step/task headers directly without a wrapper section.
# F13 (NR 14): skip fenced code blocks so quoted AID syntax does not falsely match.
has_impl_steps="$(awk '
  BEGIN { in_fence = 0 }
  {
    gsub(/\r$/, "")
    if ($0 ~ /^[[:space:]]*```/) { in_fence = 1 - in_fence; next }
    if (in_fence) next
    if ($0 ~ /^## (Implementation Steps|High-Level Steps)/) { print "yes"; exit }
    if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+/) { print "yes"; exit }
  }
' "$plan")"
[[ "$has_impl_steps" != "yes" ]] && error_exit "Plan file missing step headers. Expected: '## Implementation Steps', '## High-Level Steps', '### Step N:', or '## Task N:'" 1

# ---------------------------------------------------------------------------
# Step 4: Detect phase boundaries and extract steps for this phase
#
# Scan the ENTIRE plan file for:
#   - **EPIC N: Steps M-P** markers (phase boundaries)
#   - ### Step N: headers (step definitions)
#
# Plans use markers like:
#   **EPIC 1: Steps 1-6 — Scripts**
#   **EPIC 1**
#   **Phase 1**
# If no markers found, divide steps evenly across phases.
# ---------------------------------------------------------------------------

# Get all step numbers and EPIC markers from the entire plan file.
# F13 (NR 14, P039 plan-about-AID): skip lines inside ``` fenced blocks so
# meta-plans that quote AID step/marker syntax do not mis-count steps.
# Nested fences (4+ backticks) toggle in_fence twice which preserves the
# "inside-a-fence" invariant. Tilde fences (~~~) are not handled.
step_numbers=()
declare -A phase_start_step
declare -A phase_end_step
declare -A step_to_phase
found_markers=0
current_marker_phase=0
in_fence=0

while IFS= read -r line; do
  line="${line//$'\r'/}"
  # Toggle fence depth on lines starting with 3+ backticks (optional indent).
  if [[ "$line" =~ ^[[:space:]]*\`\`\` ]]; then
    if [[ "$in_fence" -eq 0 ]]; then in_fence=1; else in_fence=0; fi
    continue
  fi
  # Skip header/marker detection while inside a fenced code block.
  [[ "$in_fence" -eq 1 ]] && continue

  # Match EPIC markers: **EPIC N: Steps M-P — Title** or **EPIC N**
  if [[ "$line" =~ ^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))? ]]; then
    current_marker_phase="${BASH_REMATCH[1]}"
    if [[ -n "${BASH_REMATCH[3]:-}" && -n "${BASH_REMATCH[4]:-}" ]]; then
      phase_start_step[$current_marker_phase]="${BASH_REMATCH[3]}"
      phase_end_step[$current_marker_phase]="${BASH_REMATCH[4]}"
    fi
    found_markers=1
  fi
  # Match step headers — multiple formats:
  #   ### Step N: ...   (preferred)
  #   ## Task N: ...    (common alternative)
  #   ## Step N: ...    (level 2 variant)
  if [[ "$line" =~ ^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+) ]]; then
    step_numbers+=("${BASH_REMATCH[2]}")
    if [[ "$current_marker_phase" -gt 0 ]]; then
      step_to_phase["${BASH_REMATCH[2]}"]="$current_marker_phase"
    fi
  fi
done < "$plan"

total_steps="${#step_numbers[@]}"
[[ "$total_steps" -eq 0 ]] && error_exit "No steps found in plan file" 1

# Determine which steps belong to the requested phase
phase_steps=()
if [[ "$found_markers" -eq 1 ]]; then
  if [[ -n "${phase_start_step[$phase]+_}" && -n "${phase_end_step[$phase]+_}" ]]; then
    # We have explicit step ranges from markers
    start="${phase_start_step[$phase]}"
    end="${phase_end_step[$phase]}"
    for sn in "${step_numbers[@]}"; do
      if [[ "$sn" -ge "$start" && "$sn" -le "$end" ]]; then
        phase_steps+=("$sn")
      fi
    done
  else
    # Markers found but without explicit ranges for this phase —
    # use step-to-phase mapping from document order
    for sn in "${step_numbers[@]}"; do
      if [[ "${step_to_phase[$sn]:-0}" == "$phase" ]]; then
        phase_steps+=("$sn")
      fi
    done
  fi
else
  # No explicit markers — divide steps evenly across phases
  steps_per_phase=$(( total_steps / total ))
  remainder=$(( total_steps % total ))

  offset=0
  for p in $(seq 1 "$total"); do
    count="$steps_per_phase"
    # Distribute remainder to earlier phases (3,2,2 for 7 steps across 3 phases)
    if [[ "$remainder" -gt 0 ]]; then
      count=$(( count + 1 ))
      remainder=$(( remainder - 1 ))
    fi
    if [[ "$p" -eq "$phase" ]]; then
      for i in $(seq 0 $(( count - 1 ))); do
        idx=$(( offset + i ))
        phase_steps+=("${step_numbers[$idx]}")
      done
      break
    fi
    offset=$(( offset + count ))
  done
fi

[[ "${#phase_steps[@]}" -eq 0 ]] && error_exit "No steps found for phase $phase" 1

# Build a global→local step-number map. Each EPIC renumbers its steps 1..N in
# document order (the # column), but dependency references are parsed as the
# plan's global step numbers. Without this remap the Depends On column would
# point at global numbers that do not exist in the renumbered table (e.g.
# "step 2 depends on 4" in a 3-step EPIC), which fails validation downstream
# in aid-epic-to-json.sh. phase_steps is already in document order, so its
# index+1 is the local step number.
declare -A global_to_local
_local_idx=0
for sn in "${phase_steps[@]}"; do
  _local_idx=$(( _local_idx + 1 ))
  global_to_local["$sn"]="$_local_idx"
done

# ---------------------------------------------------------------------------
# Step 5: Extract data from each phase step
# ---------------------------------------------------------------------------

# Helper: extract content for a given step number directly from the plan file.
# Returns everything between ### Step N and the next ### Step header (or the
# next **EPIC M:** marker, or section boundary), excluding the header itself.
extract_step_content() {
  local step_num="$1"
  # F13: track fence depth to ignore quoted ### Step / **EPIC** lines.
  # Fence lines inside the matched step body ARE printed verbatim.
  awk -v snum="$step_num" '
    BEGIN { found = 0; in_fence = 0 }
    {
      gsub(/\r$/, "")
      # Fence toggles — when inside the matched step body, the fence line
      # itself is part of the body and must be printed.
      if ($0 ~ /^[[:space:]]*```/) {
        in_fence = 1 - in_fence
        if (found) print
        next
      }
      # Only detect headers/markers outside of fenced blocks.
      if (!in_fence) {
        # Match multiple header formats: ### Step N, ## Task N, ## Step N
        if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+/) {
          # Extract step number from this header
          line = $0
          sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", line)
          sub(/:.*/, "", line)
          sub(/[^0-9].*/, "", line)
          if (found) exit
          if (line == snum) { found = 1; next }
        }
        # Stop at EPIC markers (they separate step groups)
        if (found && $0 ~ /^\*\*EPIC[[:space:]]+[0-9]+/) exit
      }
      if (found) print
    }
  ' "$plan"
}

# Helper: extract a bold-prefixed field value from step content
# e.g., **Objective:** value
extract_bold_field() {
  local content="$1"
  local field="$2"
  echo "$content" | awk -v field="$field" '
    BEGIN { found = 0; val = "" }
    {
      gsub(/\r$/, "")
      # Match **Field:** or **Field :** patterns
      if ($0 ~ "^\\*\\*" field "(\\s*):") {
        sub("^\\*\\*" field "[[:space:]]*:[[:space:]]*\\*\\*[[:space:]]*", "", $0)
        sub("^\\*\\*" field ":[[:space:]]*\\*\\*[[:space:]]*", "", $0)
        # Handle case where value is on same line as field name
        sub("^.*\\*\\*[[:space:]]*", "", $0)
        if ($0 != "") val = $0
        found = 1
        next
      }
      # Stop at next bold field or section header
      if (found && ($0 ~ /^\*\*[A-Z]/ || $0 ~ /^###/)) exit
      if (found && $0 !~ /^[[:space:]]*$/) {
        if (val != "") val = val "\n" $0
        else val = $0
      }
    }
    END { print val }
  '
}

# Helper: parse step dependency references from a raw dependency string.
# Handles singular ("Step 1"), plural ranges ("Steps 3-5"), mixed formats,
# trailing descriptive text after step references, and reversed ranges.
#
# Args:
#   $1 — raw dependency string, e.g. "Step 1, Steps 3-5 — all needed"
#
# Output (stdout): comma-separated step numbers, e.g. "1, 3, 4, 5"
# Stderr: warning on reversed ranges
parse_step_deps() {
  local raw="$1"
  local result=()

  # P073 Step 5 — one dependency grammar, shared with the canonical parser in
  # lib/aid-source-plan-graph.sh:
  #   * everything from the FIRST annotation separator on (em dash, en dash,
  #     a SPACED ASCII hyphen — unspaced would collide with `Steps 1-3` — or a
  #     space-preceded opening parenthesis) is human prose, discarded before
  #     parsing;
  #   * `none` (authoring form) and `---` (generated-canonical form) are the
  #     two accepted no-dependency markers;
  #   * every remaining token must be recognised IN FULL (the patterns are
  #     end-anchored) — an unrecognised one used to be silently dropped, which
  #     turned a typo into "no dependency", and an unanchored match silently
  #     discarded the tail, so `Steps 1-3 and 5` lost the 5.
  raw="$(printf '%s' "$raw" | sed 's/[—–].*$//; s/ - .*$//; s/ (.*$//')"
  case "$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in
    ---|none|'') return 0 ;;
  esac

  # Tokenize by splitting on commas first, then process each token.
  # We use a while-read loop with newlines as separators after replacing commas.
  local tokens
  tokens="$(echo "$raw" | sed 's/,/\n/g')"

  while IFS= read -r token; do
    # Trim leading/trailing whitespace
    token="$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$token" ]] && continue

    # Match range pattern: "Steps M-N" or "steps M-N" (with optional trailing text)
    if [[ "$token" =~ ^[Ss]teps?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      local range_start="${BASH_REMATCH[1]}"
      local range_end="${BASH_REMATCH[2]}"

      if [[ "$range_start" -gt "$range_end" ]]; then
        echo "WARNING: Reversed range Steps ${range_start}-${range_end} — skipping" >&2
        continue
      fi

      for (( i=range_start; i<=range_end; i++ )); do
        result+=("$i")
      done

    # Match singular pattern: "Step N" (with optional trailing text)
    elif [[ "$token" =~ ^[Ss]teps?[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")

    # Match "Task" range — plans that use "## Task N:" headers reference deps
    # the same way (e.g. "Depends on: Tasks 3-5"). Mirror the Steps logic so
    # Task-style dependency lines are not silently dropped.
    elif [[ "$token" =~ ^[Tt]asks?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      local range_start="${BASH_REMATCH[1]}"
      local range_end="${BASH_REMATCH[2]}"

      if [[ "$range_start" -gt "$range_end" ]]; then
        echo "WARNING: Reversed range Tasks ${range_start}-${range_end} — skipping" >&2
        continue
      fi

      for (( i=range_start; i<=range_end; i++ )); do
        result+=("$i")
      done

    # Match "Task N" singular
    elif [[ "$token" =~ ^[Tt]asks?[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")

    # Match bare number (possibly left after earlier processing). Anchored
    # too: `2 and 5` must not silently become `2`.
    elif [[ "$token" =~ ^([0-9]+)[[:space:]]*$ ]]; then
      result+=("${BASH_REMATCH[1]}")

    else
      # P073 Step 5: loud, not silent. The message names the step and the
      # offending token verbatim so the author can fix the exact line.
      echo "ERROR: step ${step_counter:-?}: unrecognised dependency token '${token}' — accepted: 'Step N', 'Steps N-M', 'none', '---', comma-separated, optionally followed by an annotation after ' — ', ' – ', ' - ' or ' ('" >&2
      return 1
    fi
  done <<< "$tokens"

  # Deduplicate and sort numerically, then join with ", "
  if [[ "${#result[@]}" -gt 0 ]]; then
    printf '%s\n' "${result[@]}" | sort -n -u | paste -sd ',' - | sed 's/,/, /g'
  fi
}

# Helper: strip cross-phase dependencies.
# Removes step numbers that are NOT in the current EPIC's step list.
#
# Args:
#   $1 — comma-separated step numbers (e.g. "1, 2, 3, 14")
#   $2 — space-separated list of valid step numbers for this EPIC (e.g. "15 16 17")
#
# Output (stdout): filtered comma-separated step numbers (may be empty)
strip_cross_phase_deps() {
  local deps_str="$1"
  local valid_steps_str="$2"

  # Build associative array of valid steps
  declare -A valid_map
  for vs in $valid_steps_str; do
    valid_map["$vs"]=1
  done

  # Filter deps
  local filtered=()
  local dep_num
  while IFS=',' read -ra dep_nums; do
    for dep_num in "${dep_nums[@]}"; do
      dep_num="$(echo "$dep_num" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$dep_num" ]] && continue
      if [[ -n "${valid_map[$dep_num]+_}" ]]; then
        filtered+=("$dep_num")
      fi
    done
  done <<< "$deps_str"

  if [[ "${#filtered[@]}" -gt 0 ]]; then
    printf '%s\n' "${filtered[@]}" | paste -sd ',' - | sed 's/,/, /g'
  fi
}

# _aid_split_path_entry — D4 reference cleaner for a single RAW Files bullet
# (as stored, verbatim, in a per-step scoping block's files=[...] array —
# see the "## Step UI Contracts" per-step comment block built below).
#
# NOT called anywhere in THIS script today (see the step_files extraction
# above, which stays on its original single-path logic to keep plan.json
# byte-identical until Step 3 lands — this step only emits the block, it
# does not change what's read from EPIC.md today). aid-epic-to-json.sh does
# NOT source this script (only lib/common.sh is shared between the two CLI
# entry points), so this function cannot be called cross-script — it is the
# exact algorithm Step 3 must PORT/reimplement directly inside
# aid-epic-to-json.sh when it derives per-step allowed_paths from a block's
# files[] values, verified against real plan Files bullets during this
# step's development:
#
#   - The path declaration always sits immediately after the "Create:"/
#     "Modify:" label, as ONE backtick-wrapped span, or several joined by
#     literal " + `" (the "`a.md` + `b.md`" dual-file convention — e.g.
#     "Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md`
#     (identical)"). Only that LEADING run is consumed as path(s).
#   - Anything else — a "(...)" parenthetical, an em-dash/"--" description,
#     or ANY other backtick-wrapped code reference later in a prose-heavy
#     bullet (e.g. an inline "`:131`" line reference or a "`step_ac`"
#     variable name mentioned in the description) — stops the run and is
#     discarded as prose, not consumed as a path.
#   - IMPORTANT: do not naively extract every backtick span in the line —
#     that was tried first and rejected: it pulled unrelated inline-code
#     references out of long descriptions as bogus "paths" (reproduced
#     against P058's own Files bullets, which are description-heavy).
#   - No leading backtick span found → fall back to stripping the entry
#     after the first "--"/em-dash separator, then removing stray backticks
#     (matches the plain, non-backtick-wrapped path case).
#
# Args:
#   $1 — a single RAW Files bullet with the "- " bullet marker and
#        "Create:"/"Modify:" label already stripped (e.g.
#        "`CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (identical)")
#
# Output (stdout): one cleaned path per line (may be more than one line)
#
# v2.58.3: the executable copy that used to live here has been REMOVED — the real
# `_aid_split_path_entry` now comes from the single source of truth `lib/aid-scoping.sh`
# (sourced at the top of this script). aid-epic-to-json.sh + gates/aid-contract-
# validate.sh + aid-plan-lint.sh all use that same one, so there is no longer a
# reimplemented copy to drift from.

# Collect per-step data
steps_table_rows=""
all_ac=""
all_allowed_paths=""
all_forbidden_paths=""
all_artifacts=""
step_objectives=""
step_counter=0
all_step_ui_meta=""
all_step_scoping_meta=""

# Sentinel used to encode a literal "-->" inside per-step scoping block
# payload values (files=[...]/ac=[...]) BEFORE JSON-encoding them, so an
# embedded comment-closer sequence in source text (e.g. an AC describing a
# "start --> middle --> end" flow) can never truncate the HTML comment block
# early. aid-epic-to-json.sh (P058 Step 3) must decode this back to a literal
# "-->" when parsing block values — this exact token is the parse contract.
AID_ARROW_SENTINEL='@@AID_ARROW@@'

for sn in "${phase_steps[@]}"; do
  step_counter=$(( step_counter + 1 ))
  step_content="$(extract_step_content "$sn")"

  # Extract objective — priority chain:
  #   1. Explicit **Objective:** field in step content
  #   2. Text after colon in step header (### Step N: <objective text>)
  #   3. First non-empty line of step content
  objective="$(echo "$step_content" | awk '
    BEGIN { found = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Objective:\*\*/) {
        sub(/^\*\*Objective:\*\*[[:space:]]*/, "", $0)
        print
        found = 1
        next
      }
      if (found && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^\*\*[A-Z]/)) exit
      if (found) print
    }
  ')"
  # Fallback 2: extract from step header text (after "Step N:" or "Task N:")
  if [[ -z "$objective" ]]; then
    # F13: ignore step headers inside fenced code blocks.
    objective="$(awk -v snum="$sn" '
      BEGIN { in_fence = 0 }
      {
        gsub(/\r$/, "")
        if ($0 ~ /^[[:space:]]*```/) { in_fence = 1 - in_fence; next }
        if (in_fence) next
        if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+/) {
          line = $0
          sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", line)
          # Check if this is the right step number
          num = line
          sub(/:.*/, "", num)
          sub(/[^0-9].*/, "", num)
          if (num == snum) {
            # Extract text after "N: " or "N — "
            sub(/^[0-9]+[[:space:]]*[:—–-][[:space:]]*/, "", line)
            if (line != "" && line != num) print line
            exit
          }
        }
      }
    ' "$plan")"
  fi
  # Fallback 3: first non-empty line of step content
  if [[ -z "$objective" ]]; then
    objective="$(echo "$step_content" | awk 'NF { print; exit }')"
  fi

  # Extract AID Role. Accept the header WITH or WITHOUT a colon — plans author it
  # both as `**AID Role:** frontend` and `**AID Role** frontend`. (Matching only
  # the colon form silently defaulted every step to `backend`.)
  role="$(echo "$step_content" | awk '
    /^\*\*AID Role:?\*\*/ {
      sub(/^\*\*AID Role:?\*\*[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
      print tolower($0)
      exit
    }
  ')"
  [[ -z "$role" ]] && role="backend"

  # Extract acceptance criteria. Accept the header WITH or WITHOUT a colon, and
  # items as either `- [ ] ...` checkboxes OR plain `- ...` bullets — plans author
  # AC as plain bullets under `**Acceptance Criteria**`, and matching only the
  # `**Acceptance Criteria:**` + `- [ ]` form silently dropped EVERY criterion,
  # leaving the EPIC's AC section empty (root cause of the E-047-4_7 REOPEN and the
  # per-step-AC pre-flight block in aid-epic-to-json.sh).
  step_ac="$(echo "$step_content" | awk -v role="$role" '
    BEGIN { in_ac = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Acceptance Criteria:?\*\*/) { in_ac = 1; next }
      if (in_ac && $0 ~ /^\*\*/) { in_ac = 0 }
      if (in_ac && $0 ~ /^-[[:space:]]/) {
        line = $0
        sub(/^-[[:space:]]+/, "", line)            # drop the bullet
        sub(/^\[[ xX]\][[:space:]]*/, "", line)    # drop a checkbox if present
        if (line ~ /^\[[^][]+\]/) {                # already carries a [role] prefix
          printf "- [ ] %s\n", line
        } else {
          printf "- [ ] [%s] %s\n", role, line
        }
      }
    }
  ')"
  if [[ -n "$step_ac" ]]; then
    all_ac="${all_ac}${step_ac}"$'\n'
  fi

  # Raw (unprefixed) per-step AC text for the per-step scoping block below
  # (D2). Same extraction/scope as step_ac above, but WITHOUT the
  # "- [ ] [role] " wrapper that the flattened all_ac section needs — the
  # scoping block is already step-scoped, so no role tag is forced on. This
  # matches the ac[] convention frozen in the E-TEST-005 fixture (P058 Step 1).
  step_ac_raw="$(echo "$step_content" | awk '
    BEGIN { in_ac = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Acceptance Criteria:?\*\*/) { in_ac = 1; next }
      if (in_ac && $0 ~ /^\*\*/) { in_ac = 0 }
      if (in_ac && $0 ~ /^-[[:space:]]/) {
        line = $0
        sub(/^-[[:space:]]+/, "", line)
        sub(/^\[[ xX]\][[:space:]]*/, "", line)
        print line
      }
    }
  ')"

  # Extract artifacts (RAW Files bullets, verbatim "Create: `path` — desc" /
  # "Modify: `a` + `b` (desc)" form). This drives both:
  #  (a) all_artifacts — the flattened `## Artifacts` section (unchanged use)
  #  (b) the per-step scoping block's `files=[...]` value below (D2/D4) — the
  #      block gets the RAW text, not the cleaned/split step_files derivation.
  step_artifacts="$(echo "$step_content" | awk '
    BEGIN { in_files = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Files:\*\*/) { in_files = 1; next }
      if (in_files && $0 ~ /^\*\*/) { in_files = 0 }
      if (in_files && $0 ~ /^[[:space:]]*-/) {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        if ($0 != "") print "- " $0
      }
    }
  ')"
  if [[ -n "$step_artifacts" ]]; then
    all_artifacts="${all_artifacts}${step_artifacts}"$'\n'
  fi

  # Top-level-only variant of the above, for the per-step scoping block's
  # files=[...] value (below) ONLY — NOT for all_artifacts (legacy flattened
  # section stays on the indentation-agnostic extraction above, unchanged,
  # to avoid regressing existing goldens). A Files entry sometimes carries
  # further-INDENTED sub-bullets that elaborate on a single top-level
  # "Create:"/"Modify:" bullet — those are prose continuation, not separate
  # files, and must NOT be surfaced as their own files[] array entry. Only a
  # bullet with NO leading whitespace before its "-" is a real, distinct entry.
  #
  # v2.58.3: this is now the SHARED extractor _aid_extract_files_bullets (single
  # source of truth in lib/aid-scoping.sh, byte-identical to the awk it replaces),
  # so aid-plan-lint.sh sees exactly the same "which lines are Files entries" as
  # this generator — they cannot disagree on indented sub-bullets or Test: entries.
  step_artifacts_top_level="$(printf '%s\n' "$step_content" | _aid_extract_files_bullets)"

  # Extract files (Create/Modify paths) for the flattened `## Scope >
  # Allowed files/paths` section — UNCHANGED from before this step. D4's
  # improved multi-path SPLIT + trailing-prose-strip logic (see
  # _aid_split_path_entry below) deliberately does NOT replace this
  # extraction: this section is read today by aid-epic-to-json.sh and
  # broadcast into plan.json's steps[].allowed_paths, so any change here
  # changes plan.json output NOW, before Step 3 exists to consume the new
  # per-step block. Verified: this step's change must be inert on the JSON
  # side (byte-identical plan.json before/after, module docstring "Testing"
  # requirement) — an earlier draft that fixed this extraction in place was
  # reverted after a before/after `aid-epic-to-json.sh` diff showed it
  # was NOT inert (allowed_paths content changed). aid-epic-to-json.sh does
  # NOT source this script (no shared entry point exists between the two
  # CLI scripts, only lib/common.sh) — Step 3 must PORT/reimplement this
  # exact algorithm directly inside aid-epic-to-json.sh when it derives
  # per-step allowed_paths from the block's RAW files[] values, using
  # _aid_split_path_entry below as the reference spec, not as callable code.
  # P079 Step 5 (IMP-480): a top-level Files bullet that does not match the
  # verb grammar used to be dropped by a bare `continue`. Generation then
  # succeeded with a narrower scope than the plan declared — and the EPIC ran
  # with a file its own plan named missing from allowed_paths, which nothing
  # downstream could notice. A parser may refuse, it may not narrow silently.
  step_files=""
  _dropped_bullets=""
  while IFS= read -r _raw_file; do
    [[ -n "${_raw_file// /}" ]] || continue          # blank line, not a bullet
    _raw_file="${_raw_file#- }"
    if [[ ! "$_raw_file" =~ ^(Create|Modify|Test|Rewrite):[[:space:]]*(.*)$ ]]; then
      _dropped_bullets+="  step ${sn}: unparseable Files bullet dropped: \"${_raw_file}\""$'\n'
      continue
    fi
    if [[ -z "${BASH_REMATCH[2]//[[:space:]]/}" ]]; then
      _dropped_bullets+="  step ${sn}: Files bullet has a verb but no path: \"${_raw_file}\""$'\n'
      continue
    fi
    if ! _split_paths="$(_aid_split_path_entry "${BASH_REMATCH[2]}")"; then
      error_exit "Invalid Files entry in step ${sn}: ${_raw_file}. Canonical multi-path form: \`a\` + \`b\` — description." 1
    fi
    while IFS= read -r _path; do
      [[ -n "$_path" ]] && step_files+="${_path}"$'\n'
    done <<< "$_split_paths"
  done <<< "$step_artifacts_top_level"
  if [[ -n "$_dropped_bullets" ]]; then
    error_exit "Files block in ${plan} has bullets this generator cannot parse:
${_dropped_bullets}Every top-level Files bullet must read \`- <Create|Modify|Test|Rewrite>: <path> — <why>\`. See skills/plan-writing.md (Files block grammar). Fix the plan and re-run generation." 1
  fi
  if [[ -n "$step_files" ]]; then
    all_allowed_paths="${all_allowed_paths}${step_files}"$'\n'
  fi

  # Extract UI Change Mode from step content
  ui_change_mode="$(echo "$step_content" | awk '
    /^\*\*UI Change Mode:\*\*/ {
      sub(/^\*\*UI Change Mode:\*\*[[:space:]]*`?/, "")
      sub(/`.*/, "")
      gsub(/[[:space:]]/, "")
      if ($0 == "existing_ui" || $0 == "new_ui") print $0
      exit
    }
  ')"

  # Extract UI Change Contract from step content
  ui_change_contract_raw="$(echo "$step_content" | awk '
    /^\*\*UI Change Contract:\*\*/ {
      sub(/^\*\*UI Change Contract:\*\*[[:space:]]*`?/, "")
      sub(/`.*/, "")
      print
      exit
    }
  ')"
  ui_change_path="$(echo "$ui_change_contract_raw" | sed -n "s/.*path:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')"
  ui_change_sha256="$(echo "$ui_change_contract_raw" | sed -n "s/.*sha256:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')"
  ui_change_schema_version="$(echo "$ui_change_contract_raw" | sed -n "s/.*schema_version:[[:space:]]*\([^|]*\).*/\1/p" | tr -d ' ')"

  # Build per-step UI metadata comment line
  if [[ -n "$ui_change_mode" ]]; then
    step_ui_meta="<!-- step-${step_counter}: ui_change_mode=${ui_change_mode}"
    if [[ -n "$ui_change_path" ]]; then
      step_ui_meta="${step_ui_meta} | path=${ui_change_path}"
      step_ui_meta="${step_ui_meta} | sha256=${ui_change_sha256}"
      step_ui_meta="${step_ui_meta} | schema_version=${ui_change_schema_version}"
    fi
    step_ui_meta="${step_ui_meta} -->"
    all_step_ui_meta="${all_step_ui_meta}${step_ui_meta}"$'\n'
  fi

  # Build per-step scoping metadata block (D2 — per-step files/ac, same
  # HTML-comment-block pattern as step_ui_meta above, emitted under
  # `## Step UI Contracts`). This is the block aid-epic-to-json.sh (P058
  # Step 3) will read PER STEP instead of broadcasting the flattened
  # `## Artifacts` / `## Acceptance Criteria` sections to every step. It is
  # inert today — nothing parses "files="/"ac=" yet, so plan.json output is
  # unaffected by this block's presence.
  #
  # Shape (frozen by the E-TEST-005 fixture, P058 Step 1):
  #   <!-- step-N: files=["Create: `path` — desc","Modify: `a` + `b`"]; ac=["AC text 1","AC text 2"] -->
  #   - files[]: RAW step_artifacts entries, one JSON string per Files bullet,
  #     leading "- " stripped but otherwise verbatim (label + backticks +
  #     description kept) — Step 3 derives outputs=verbatim / allowed_paths=
  #     cleaned FROM this raw text, it does not read the already-cleaned
  #     step_files/all_allowed_paths values.
  #   - ac[]: RAW step_ac_raw entries — AC text with the leading "- " bullet
  #     and "[ ]" checkbox stripped, but WITHOUT the "[role]" prefix that
  #     all_ac forces on (block is already step-scoped, so no role tag).
  #   - Both arrays are JSON-encoded via `jq -R -s -c` (compact, one string
  #     per source line); any literal "-->" substring in a value is replaced
  #     with $AID_ARROW_SENTINEL BEFORE JSON-encoding, so the block's own
  #     closing "-->" can never be truncated early. Step 3 must reverse this
  #     substitution after JSON-decoding each string.
  step_files_json="[]"
  if [[ -n "$step_artifacts_top_level" ]]; then
    step_files_json="$(echo "$step_artifacts_top_level" \
      | sed 's/^- //' \
      | sed "s/-->/${AID_ARROW_SENTINEL}/g" \
      | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  fi
  step_ac_json="[]"
  if [[ -n "$step_ac_raw" ]]; then
    step_ac_json="$(echo "$step_ac_raw" \
      | sed "s/-->/${AID_ARROW_SENTINEL}/g" \
      | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  fi
  step_scoping_meta="<!-- step-${step_counter}: files=${step_files_json}; ac=${step_ac_json} -->"
  all_step_scoping_meta="${all_step_scoping_meta}${step_scoping_meta}"$'\n'

  # Build step objectives list for Goal section.
  # Use the EPIC-local step number (step_counter) so the Goal list stays
  # consistent with the renumbered Steps table; the global number ($sn) only
  # exists in the source plan.
  step_objectives="${step_objectives}- Step ${step_counter}: ${objective}"$'\n'

  # Extract raw dependency line from step content
  raw_dep_line="$(echo "$step_content" | awk '
    BEGIN { in_deps = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps = 1; next }
      if (in_deps && $0 ~ /^\*\*/) { in_deps = 0 }
      if (in_deps && $0 ~ /Depends on:/) {
        sub(/.*Depends on:[[:space:]]*/, "", $0)
        print
      }
    }
  ')"

  # Parse step references from the raw dependency line.
  # Handles:
  #   - "Step 1" -> 1
  #   - "Steps 3-5" -> 3, 4, 5
  #   - "Step 1, Steps 3-5" -> 1, 3, 4, 5
  #   - Trailing descriptive text: "Step 1 — provides base config" -> 1
  #   - Reversed ranges: "Steps 14-1" -> warning + empty
  step_deps=""
  if [[ -n "$raw_dep_line" ]]; then
    # P073 Step 5: an unrecognised token aborts generation. The previous code
    # mapped an unparseable declaration to `---` further down and carried on,
    # so a typo silently became "no dependency" in the generated EPIC. No EPIC
    # file has been written for this plan at this point, so there is no
    # partial output to clean up.
    if ! step_deps="$(parse_step_deps "$raw_dep_line")"; then
      echo "ERROR: EPIC generation aborted — repair the dependency declaration above and rerun. Full grammar: skills/plan-writing.md" >&2
      exit 1
    fi
  fi

  # Strip cross-phase dependencies: remove any step numbers that fall
  # outside the current EPIC's step range
  if [[ -n "$step_deps" ]]; then
    step_deps="$(strip_cross_phase_deps "$step_deps" "${phase_steps[*]}")"
  fi

  # Remap surviving (intra-EPIC) dependencies from global to local step
  # numbers so the Depends On column matches the renumbered # column. After
  # the strip above, every remaining number is in phase_steps and therefore
  # has a global_to_local entry.
  if [[ -n "$step_deps" ]]; then
    remapped_deps=()
    IFS=',' read -ra _dep_nums <<< "$step_deps"
    for _dn in "${_dep_nums[@]}"; do
      _dn="$(echo "$_dn" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$_dn" ]] && continue
      # Drop self-references: a range like "Steps 7-9" on step 9 expands to
      # include 9 itself, which would produce a meaningless self-edge that
      # downstream cycle detection (aid-epic-to-json.sh) rejects.
      [[ "$_dn" == "$sn" ]] && continue
      if [[ -n "${global_to_local[$_dn]+_}" ]]; then
        remapped_deps+=("${global_to_local[$_dn]}")
      fi
    done
    if [[ "${#remapped_deps[@]}" -gt 0 ]]; then
      step_deps="$(printf '%s\n' "${remapped_deps[@]}" | sort -n -u | paste -sd ',' - | sed 's/,/, /g')"
    else
      step_deps=""
    fi
  fi

  # Build Steps table row
  # Collapse multi-line objective to single line for table
  safe_objective="$(echo "$objective" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  # Truncate to reasonable length for table BEFORE escaping, so an escape
  # sequence can never be split in half by the cut (P074 Step 17).
  if [[ "${#safe_objective}" -gt 100 ]]; then
    safe_objective="${safe_objective:0:97}..."
  fi
  # Two-rule escape grammar (P074 Step 17), unambiguous by construction:
  # literal backslash → \\ FIRST, then literal pipe → \|. Escaping only pipes
  # left `\|` ambiguous between "escaped pipe" and "field-final backslash +
  # delimiter". Decoded by the character-walk splitter in aid-epic-to-json.sh.
  safe_objective="${safe_objective//\\/\\\\}"
  safe_objective="${safe_objective//|/\\|}"

  # Determine depends_on for this step within the phase. `---` here is the
  # GENERATED-CANONICAL no-dependency marker, reached only when the author
  # genuinely declared none (or every reference was cross-phase and stripped)
  # — never as a fallback for an unparseable declaration, which now aborts
  # generation in parse_step_deps (P073 Step 5).
  depends_on_str="---"
  if [[ -n "$step_deps" ]]; then
    # parse_step_deps already returns "N, M, ..." format — use as-is
    depends_on_str="$(echo "$step_deps" | head -1)"
    [[ -z "$depends_on_str" ]] && depends_on_str="---"
  fi

  steps_table_rows="${steps_table_rows}| ${step_counter} | ${role} | ${safe_objective} | ${depends_on_str} | --- |"$'\n'
done

# ---------------------------------------------------------------------------
# Step 6: Extract plan-level sections for the EPIC
# ---------------------------------------------------------------------------

# Context
plan_context="$(extract_section "$plan" "Context")"
# Trim trailing whitespace/newlines
plan_context="$(echo "$plan_context" | sed '/^[[:space:]]*$/d')"
epic_context="${plan_context}

This EPIC covers Phase ${phase} of ${total} from plan ${plan_id}."

# Goal — scope to this phase's deliverables
plan_goal="$(extract_section "$plan" "Goal")"
plan_goal="$(echo "$plan_goal" | sed '/^[[:space:]]*$/d')"

if [[ "$total" -eq 1 ]]; then
  epic_goal="$plan_goal"
else
  epic_goal="${plan_goal}

Phase ${phase}/${total} deliverables:
${step_objectives}"
fi

# Scope Allowed — aggregate from phase steps' files.
# Prefer per-file paths over directory paths for better FIRST AID parallel
# detection: file-level granularity avoids false scope overlaps between EPICs.
# When plan steps have **Files:** sections with Create:/Modify: entries, each
# file is listed individually. Directory paths are only emitted as a fallback
# when no specific file paths are available for a given directory.
scope_allowed=""
if [[ -n "$all_allowed_paths" ]]; then
  # Separate file paths (have extension or no trailing slash) from directory
  # paths (end with /). List file paths individually; only include a directory
  # path if no file-level paths already cover that directory.
  scope_allowed="$(echo "$all_allowed_paths" | sort -u | awk '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == "") next
      # Classify: directory path ends with / or has no extension in basename
      n = split($0, parts, "/")
      basename = parts[n]
      if ($0 ~ /\/$/ || basename !~ /\./) {
        dirs[++nd] = $0
      } else {
        files[++nf] = $0
      }
    }
    END {
      # Emit per-file paths first (preferred for parallel detection)
      for (i = 1; i <= nf; i++) {
        printf "- `%s`\n", files[i]
      }
      # Emit directory paths only if no file within that directory is listed
      for (i = 1; i <= nd; i++) {
        dir = dirs[i]
        # Normalize: ensure trailing slash for prefix matching
        dslash = dir
        if (dslash !~ /\/$/) dslash = dslash "/"
        covered = 0
        for (j = 1; j <= nf; j++) {
          if (index(files[j], dslash) == 1) { covered = 1; break }
        }
        if (!covered) printf "- `%s`\n", dir
      }
    }
  ')"
fi
[[ -z "$scope_allowed" ]] && scope_allowed="- <!-- No specific paths identified from plan steps -->"

# Scope Forbidden — extract from plan "Out of scope" items
plan_scope="$(extract_section "$plan" "Scope")"
scope_forbidden="$(echo "$plan_scope" | awk '
  BEGIN { in_out = 0 }
  {
    gsub(/\r$/, "")
    if ($0 ~ /^\*\*Out of scope:\*\*/ || $0 ~ /^Out of scope:/) { in_out = 1; next }
    if (in_out && ($0 ~ /^\*\*/ || $0 ~ /^##/)) { in_out = 0 }
    if (in_out && $0 ~ /^-/) {
      print
    }
  }
')"
[[ -z "$scope_forbidden" ]] && scope_forbidden="- <!-- No forbidden zones specified in plan -->"

# Artifacts
if [[ -z "$all_artifacts" ]]; then
  all_artifacts="- <!-- Auto-generated from plan step files -->"
fi

# Constraints
plan_constraints="$(extract_section "$plan" "Constraints")"
plan_constraints="$(echo "$plan_constraints" | sed '/^[[:space:]]*$/d')"
[[ -z "$plan_constraints" ]] && plan_constraints="- <!-- No constraints specified in plan -->"

# DoD Gates — use defaults
dod_gates="- docs_updated"

# Dependencies section
internal_deps=""
if [[ "$phase" -gt 1 ]]; then
  prev_phase=$(( phase - 1 ))
  prev_epic_id="E-${plan_num}-${prev_phase}_${total}"
  internal_deps="- ${prev_epic_id} — Previous phase must complete first"
else
  internal_deps="<!-- First phase --- no internal dependencies -->"
fi

# External dependencies — parse plan for dependency references
#
# Plans may declare dependencies in two places:
#   1. **Dependencies:** bold field within ## Scope section
#   2. ## Dependencies section (if present as a real H2)
# We check both, but filter out self-references to the current plan_id.
plan_deps=""
# First try: look for **Dependencies:** within the Scope section
plan_scope_full="$(extract_section "$plan" "Scope")"
scope_deps="$(echo "$plan_scope_full" | awk '
  BEGIN { in_deps = 0 }
  {
    gsub(/\r$/, "")
    if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps = 1; next }
    if (in_deps && ($0 ~ /^\*\*/ || $0 ~ /^##/ || $0 ~ /^$/)) { in_deps = 0 }
    if (in_deps) print
  }
')"
if [[ -n "$scope_deps" ]]; then
  plan_deps="$scope_deps"
fi

external_deps=""
if [[ -n "$plan_deps" ]]; then
  # Look for references to other plans (P###) or EPICs (E-###-N_M)
  # Filter out self-references to the current plan
  ext_refs="$(echo "$plan_deps" | grep -oE '(P[0-9]{3}|E-[0-9]{3}-[0-9]+_[0-9]+)' 2>/dev/null | grep -v "^${plan_id}$" || true)"
  if [[ -n "$ext_refs" ]]; then
    while IFS= read -r ref; do
      [[ -n "$ref" ]] && external_deps="${external_deps}- ${ref}"$'\n'
    done <<< "$ext_refs"
  fi
fi
if [[ -z "$external_deps" ]]; then
  external_deps="<!-- No external dependencies -->"
fi

# Queue Implications — depends_on list
depends_on_list="[]"
dep_items=()
if [[ "$phase" -gt 1 ]]; then
  prev_phase=$(( phase - 1 ))
  dep_items+=("E-${plan_num}-${prev_phase}_${total}")
fi
# Add external EPIC deps (only fully-qualified EPIC IDs, not plan IDs)
if [[ -n "$plan_deps" ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && dep_items+=("$ref")
  done <<< "$(echo "$plan_deps" | grep -oE 'E-[0-9]{3}-[0-9]+_[0-9]+' 2>/dev/null || true)"
fi

if [[ "${#dep_items[@]}" -gt 0 ]]; then
  # Build JSON-style list
  dep_str=""
  for item in "${dep_items[@]}"; do
    [[ -n "$dep_str" ]] && dep_str="${dep_str}, "
    dep_str="${dep_str}${item}"
  done
  depends_on_list="[${dep_str}]"
fi

# Hints
hints="- expected_steps: ${#phase_steps[@]}
- complexity: medium
- parallelism_potential: low"

# ---------------------------------------------------------------------------
# Step 7: Build the EPIC from template
# ---------------------------------------------------------------------------

# Read the template
template_content="$(cat "$epic_template")"

# We build the EPIC by constructing it section-by-section rather than doing
# sed-based placeholder replacement (which is fragile with multiline content
# and special characters). Instead, we emit the EPIC directly.

plan_filename="$(basename "$plan")"
source_plan_sha256="sha256:$(sha256sum "$plan" | awk '{print $1}')"
source_step_ids="$(IFS=,; echo "${phase_steps[*]}")"

# Build the steps table
steps_table_header="| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|"
steps_table="${steps_table_header}
${steps_table_rows}"

# Write the full EPIC
cat > "${output_dir}/${epic_id}-${slug}.md" << EPICEOF
---
status: active
plan_ref: ${plan}
plan_epics_total: ${total}
source_plan_sha256: ${source_plan_sha256}
source_phase: ${phase}
source_step_ids: "${source_step_ids}"
runs_total: 1
runs_completed: 0
---

# EPIC: ${epic_id} --- ${title}

## Context

${epic_context}

## Goal

${epic_goal}

## Scope

### Allowed files/paths
${scope_allowed}

### Forbidden zones
${scope_forbidden}

## Artifacts

${all_artifacts}

## Constraints

${plan_constraints}

## DoD Gates

${dod_gates}

## Acceptance Criteria

${all_ac}

## Dependencies

### Internal (same plan)
${internal_deps}

### External (other plans/EPICs)
${external_deps}

### Queue Implications
depends_on: ${depends_on_list}

## Steps (Role Pipeline)

${steps_table}

## Step UI Contracts

$(if [[ -n "$all_step_ui_meta" ]]; then echo "$all_step_ui_meta"; else echo "<!-- No ui_change_mode fields in this plan -->"; fi)
$(if [[ -n "$all_step_scoping_meta" ]]; then echo "$all_step_scoping_meta"; fi)

## Run Breakdown

### Run 1: Phase ${phase}
**Goal:** ${plan_goal}
**Deliverables:** Phase ${phase} of ${total} from plan ${plan_id}

## Hints

${hints}

## Notes

<!-- Auto-generated by aid-plan-to-epic.sh from ${plan_filename} on $(date -u +%Y-%m-%d) -->
EPICEOF

# ---------------------------------------------------------------------------
# Step 8: Output the absolute path to the generated file
# ---------------------------------------------------------------------------
output_file="${output_dir}/${epic_id}-${slug}.md"

# Resolve to absolute path if not already
if [[ "${output_file:0:1}" != "/" ]]; then
  output_file="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
fi

echo "$output_file"
