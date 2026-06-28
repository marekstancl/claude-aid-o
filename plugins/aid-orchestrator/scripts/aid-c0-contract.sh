#!/usr/bin/env bash
# =============================================================================
# aid-c0-contract.sh — C0 Plan Contract Gate artifact producer
#
# Usage: aid-c0-contract.sh <subcommand> [args]
#
# Subcommands:
#   contract <plan.json> <c0_evidence_dir> [--out <path>]
#       Reads plan.json, derives dependency bindings, computes per-binding
#       hashes and a manifest_hash, then emits contract-manifest.json and
#       plan-graph.json to the evidence directory.
#       Exit 0 always unless plan.json is missing or invalid JSON (exit 1).
#
#   review   <plan.md>   <c0_evidence_dir> [--out <path>]
#       STUB — Step 3 will implement the 5 structural checks and lens evidence
#       scan. Currently emits a minimal plan-review.json and exits 0.
#
# Protocol v2 envelope fields (contract and plan-graph artifacts):
#   schema_version: aid-2.0
#   control_protocol: aid-2.0
#   producer: aid-c0-contract.sh@<version>
#   status: pending (C0 is observe-only; E5 is authoritative)
#   verdict.kind: none
#
# Requirements: bash 4.0+, jq, sha256sum, awk, git
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate lib directory relative to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# ---------------------------------------------------------------------------
# Protocol v2 envelope constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION="aid-2.0"
CONTROL_PROTOCOL="aid-2.0"
PRODUCER="aid-c0-contract.sh@1.0"

# ---------------------------------------------------------------------------
# Helper: build a minimal protocol v2 envelope around a payload
# Usage: _build_envelope <artifact_type> <payload_key> <payload_json> <project_root>
# Output: complete protocol v2 envelope JSON
# ---------------------------------------------------------------------------
_build_envelope() {
  local artifact_type="$1"
  local payload_key="$2"
  local payload_json="$3"
  local project_root="${4:-$PWD}"

  local created_at
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local project_id
  project_id="$(basename "$project_root")"

  # Git metadata — gracefully fall back if not in a git repo
  local head_sha
  head_sha="$(git -C "$project_root" rev-parse HEAD 2>/dev/null)" || head_sha="0000000000000000000000000000000000000000"

  # Compute subject_hash from the payload
  local subject_hash
  subject_hash="sha256:$(printf '%s' "$payload_json" | sha256sum | awk '{print $1}')"

  jq -n \
    --arg schema_version     "$SCHEMA_VERSION" \
    --arg artifact_type      "$artifact_type" \
    --arg producer           "$PRODUCER" \
    --arg created_at         "$created_at" \
    --arg control_protocol   "$CONTROL_PROTOCOL" \
    --arg project_id         "$project_id" \
    --arg subject_hash       "$subject_hash" \
    --arg head_sha           "$head_sha" \
    --arg payload_key        "$payload_key" \
    --argjson payload        "$payload_json" \
    '{
      "schema_version":    $schema_version,
      "artifact_type":     $artifact_type,
      "producer":          $producer,
      "created_at":        $created_at,
      "control_protocol":  $control_protocol,
      "identity": {
        "project_id": $project_id
      },
      "subject": {
        "subject_hash": $subject_hash
      },
      "revision": {
        "head_sha":        $head_sha,
        "head_is_current": true,
        "freshness":       "current"
      },
      "status":  "pending",
      "verdict": { "kind": "none", "ready": false },
      "provenance": {
        "dispatch_mode":     "deterministic",
        "generated_by_tool": "aid-c0-contract.sh"
      }
    } + { ($payload_key): $payload }'
}

# ---------------------------------------------------------------------------
# Subcommand dispatch
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: aid-c0-contract.sh <subcommand> [args]" >&2
  echo "  contract <plan.json> <c0_evidence_dir> [--out <path>]" >&2
  echo "  review   <plan.md>   <c0_evidence_dir> [--out <path>]" >&2
  exit 1
fi

SUBCOMMAND="$1"
shift

# ===========================================================================
# Subcommand: contract
# ===========================================================================
cmd_contract() {
  # -------------------------------------------------------------------------
  # Arg parsing
  # -------------------------------------------------------------------------
  local plan_json=""
  local evidence_dir=""
  local out_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --out requires a path argument" >&2
          exit 1
        fi
        out_path="$2"
        shift 2
        ;;
      -*)
        echo "ERROR: Unknown flag: $1" >&2
        exit 1
        ;;
      *)
        if [[ -z "$plan_json" ]]; then
          plan_json="$1"
        elif [[ -z "$evidence_dir" ]]; then
          evidence_dir="$1"
        else
          echo "ERROR: Unexpected argument: $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$plan_json" || -z "$evidence_dir" ]]; then
    echo "Usage: aid-c0-contract.sh contract <plan.json> <c0_evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  # -------------------------------------------------------------------------
  # Validate plan.json existence and JSON validity
  # -------------------------------------------------------------------------
  if [[ ! -f "$plan_json" ]]; then
    echo "ERROR: plan.json not found: $plan_json" >&2
    exit 1
  fi

  if ! jq . "$plan_json" >/dev/null 2>&1; then
    echo "ERROR: plan.json is not valid JSON: $plan_json" >&2
    exit 1
  fi

  # -------------------------------------------------------------------------
  # Source helper libs
  # -------------------------------------------------------------------------
  # shellcheck source=lib/aid-contract-hash.sh
  source "${LIB_DIR}/aid-contract-hash.sh"
  # shellcheck source=lib/aid-plan-graph.sh
  source "${LIB_DIR}/aid-plan-graph.sh"

  # -------------------------------------------------------------------------
  # Ensure evidence directory exists
  # -------------------------------------------------------------------------
  mkdir -p "$evidence_dir"

  # -------------------------------------------------------------------------
  # Resolve project root (directory containing plan.json, or its parent git root)
  # -------------------------------------------------------------------------
  local plan_dir
  plan_dir="$(dirname "$(cd "$(dirname "$plan_json")" && pwd)/$(basename "$plan_json")")"
  local project_root
  project_root="$(git -C "$plan_dir" rev-parse --show-toplevel 2>/dev/null)" || project_root="$plan_dir"

  # -------------------------------------------------------------------------
  # Step 1: Extract dependencies from plan.json
  # -------------------------------------------------------------------------
  # Read as "before->after" edge pairs (one per line)
  local deps_nl
  deps_nl="$(jq -r '.dependencies[]? | "\(.before)->\(.after)"' "$plan_json" 2>/dev/null || true)"

  # -------------------------------------------------------------------------
  # Step 2: Build bindings array and collect hashes
  # -------------------------------------------------------------------------
  local bindings_json="[]"
  local all_hashes=""

  if [[ -n "$deps_nl" ]]; then
    while IFS= read -r edge; do
      [[ -z "$edge" ]] && continue

      local producer="${edge%%->*}"
      local consumer="${edge##*->}"
      [[ -z "$producer" || -z "$consumer" ]] && continue

      local field="output"
      local status="pending"
      local provenance="plan_dependency"

      # Compute per-binding hash using \x1f separator
      local bhash
      bhash="$(binding_hash "$producer" "$consumer" "$field")"

      # Accumulate hashes for manifest_hash computation
      if [[ -z "$all_hashes" ]]; then
        all_hashes="$bhash"
      else
        all_hashes="${all_hashes}
${bhash}"
      fi

      # Append binding object to bindings JSON array
      bindings_json="$(printf '%s' "$bindings_json" | jq \
        --arg producer   "$producer" \
        --arg consumer   "$consumer" \
        --arg field      "$field" \
        --arg status     "$status" \
        --arg provenance "$provenance" \
        --arg hash       "$bhash" \
        '. + [{
          "producer":   $producer,
          "consumer":   $consumer,
          "field":      $field,
          "status":     $status,
          "provenance": $provenance,
          "hash":       $hash
        }]')"

    done <<< "$deps_nl"
  fi

  # -------------------------------------------------------------------------
  # Step 3: Compute manifest_hash over all binding hashes (lexicographic sort)
  # -------------------------------------------------------------------------
  local mhash
  mhash="$(manifest_hash "$all_hashes")"

  # -------------------------------------------------------------------------
  # Step 4: Build consumption_proof object
  # -------------------------------------------------------------------------
  # Status is ALWAYS "pending_slot" at C0 — verification is E5's responsibility
  local consumption_proof_json
  consumption_proof_json='{"state":"pending_slot","authoritative_phase":"E5"}'

  # -------------------------------------------------------------------------
  # Step 5: Assemble the inner contract_manifest payload
  # -------------------------------------------------------------------------
  local cm_payload
  cm_payload="$(jq -n \
    --argjson bindings          "$bindings_json" \
    --argjson consumption_proof "$consumption_proof_json" \
    --arg     manifest_hash     "$mhash" \
    '{
      "bindings":          $bindings,
      "consumption_proof": $consumption_proof,
      "manifest_hash":     $manifest_hash
    }')"

  # -------------------------------------------------------------------------
  # Step 6: Wrap in protocol v2 envelope and write contract-manifest.json
  # -------------------------------------------------------------------------
  local contract_manifest_json
  contract_manifest_json="$(_build_envelope "contract_manifest" "contract_manifest" "$cm_payload" "$project_root")"

  local contract_out
  if [[ -n "$out_path" ]]; then
    contract_out="$out_path"
  else
    contract_out="${evidence_dir}/contract-manifest.json"
  fi

  printf '%s\n' "$contract_manifest_json" > "$contract_out"

  # -------------------------------------------------------------------------
  # Step 7: Build plan-graph.json using aid-plan-graph.sh
  # -------------------------------------------------------------------------
  local step_ids_nl
  step_ids_nl="$(jq -r '.steps[]?.id' "$plan_json" 2>/dev/null || true)"

  local edges_nl
  edges_nl="$(jq -r '.dependencies[]? | "\(.before)->\(.after)"' "$plan_json" 2>/dev/null || true)"

  local graph_result=""
  if [[ -n "$step_ids_nl" ]]; then
    graph_result="$(build_plan_graph "$step_ids_nl" "$edges_nl")"
  else
    # No steps — emit empty graph
    graph_result='{"edges":[],"topological_order":[],"cycles":[]}'
  fi

  # Wrap in protocol v2 envelope
  local plan_graph_json
  plan_graph_json="$(_build_envelope "plan_graph" "plan_graph" "$graph_result" "$project_root")"

  local graph_out="${evidence_dir}/plan-graph.json"
  printf '%s\n' "$plan_graph_json" > "$graph_out"

  return 0
}

# ===========================================================================
# Subcommand: review
# Runs 5 deterministic structural checks, scans 5 C0 lens evidence files,
# and emits plan-review.json (observe — never exits non-zero due to findings).
# ===========================================================================
cmd_review() {
  # -------------------------------------------------------------------------
  # Arg parsing
  # -------------------------------------------------------------------------
  local plan_md=""
  local evidence_dir=""
  local out_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --out requires a path argument" >&2
          exit 1
        fi
        out_path="$2"
        shift 2
        ;;
      -*)
        echo "ERROR: Unknown flag: $1" >&2
        exit 1
        ;;
      *)
        if [[ -z "$plan_md" ]]; then
          plan_md="$1"
        elif [[ -z "$evidence_dir" ]]; then
          evidence_dir="$1"
        else
          echo "ERROR: Unexpected argument: $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$plan_md" ]]; then
    echo "Usage: aid-c0-contract.sh review <plan.md> <c0_evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  if [[ ! -f "$plan_md" ]]; then
    echo "ERROR: plan.md not found: $plan_md" >&2
    exit 1
  fi

  if [[ -z "$evidence_dir" ]]; then
    echo "Usage: aid-c0-contract.sh review <plan.md> <c0_evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  mkdir -p "$evidence_dir"

  local review_out
  if [[ -n "$out_path" ]]; then
    review_out="$out_path"
  else
    review_out="${evidence_dir}/plan-review.json"
  fi

  # -------------------------------------------------------------------------
  # Resolve project root (for envelope metadata)
  # -------------------------------------------------------------------------
  local plan_dir
  plan_dir="$(dirname "$(cd "$(dirname "$plan_md")" && pwd)/$(basename "$plan_md")")"
  local project_root
  project_root="$(git -C "$plan_dir" rev-parse --show-toplevel 2>/dev/null)" || project_root="$plan_dir"

  # -------------------------------------------------------------------------
  # Structural checks (all observe — never exit non-zero due to findings)
  # -------------------------------------------------------------------------
  local structural_checks_json="[]"
  local findings_json="[]"

  # --------------------------------------------------------------------------
  # Check 1: plan_graph_topo
  # Does plan-graph.json exist? Are cycles empty?
  # --------------------------------------------------------------------------
  local pg_file="${evidence_dir}/plan-graph.json"
  local pg_status="unverifiable"
  local pg_detail=""

  if [[ ! -f "$pg_file" ]]; then
    pg_status="unverifiable"
    pg_detail="plan-graph.json not found in evidence dir"
  elif ! jq . "$pg_file" >/dev/null 2>&1; then
    pg_status="observe"
    pg_detail="plan-graph.json is not valid JSON"
  else
    local cycles_count
    cycles_count="$(jq '(.plan_graph.cycles // .cycles // []) | length' "$pg_file" 2>/dev/null || echo "0")"
    if [[ "$cycles_count" -gt 0 ]]; then
      pg_status="observe"
      pg_detail="plan-graph contains ${cycles_count} cycle(s)"
    else
      pg_status="pass"
      pg_detail="no cycles"
    fi
  fi

  structural_checks_json="$(printf '%s' "$structural_checks_json" | jq \
    --arg id "plan_graph_topo" \
    --arg status "$pg_status" \
    --arg detail "$pg_detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]')"

  # --------------------------------------------------------------------------
  # Check 2: identifier_domain
  # Are step IDs syntactically unique? Do all dependency references resolve?
  # --------------------------------------------------------------------------
  local id_status="pass"
  local id_detail=""

  # Parse step table rows: lines matching "| N | role |..." (skip header/separator)
  local step_rows
  step_rows="$(grep -E '^\| *[0-9]+ *\|' "$plan_md" 2>/dev/null | grep -vE '^\| *#' | grep -vE '^\| *-' || true)"

  if [[ -n "$step_rows" ]]; then
    # Build step IDs: step_{N}_{role_sanitized}
    local step_ids=()
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      # Extract step number (first column after opening |)
      local step_num
      step_num="$(echo "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
      # Extract role (second column)
      local role_raw
      role_raw="$(echo "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')"

      # Sanitize role: lowercase, replace non-alphanumeric with _
      local role_sanitized
      role_sanitized="$(echo "$role_raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//; s/_$//')"

      if [[ -n "$step_num" && -n "$role_sanitized" ]]; then
        step_ids+=("step_${step_num}_${role_sanitized}")
      fi
    done <<< "$step_rows"

    # Check for duplicates
    if [[ "${#step_ids[@]}" -gt 0 ]]; then
      local sorted_ids
      sorted_ids="$(printf '%s\n' "${step_ids[@]}" | sort)"
      local unique_ids
      unique_ids="$(printf '%s\n' "${step_ids[@]}" | sort -u)"

      local total_count unique_count
      total_count="$(printf '%s\n' "${step_ids[@]}" | wc -l | tr -d ' ')"
      unique_count="$(printf '%s\n' "${step_ids[@]}" | sort -u | wc -l | tr -d ' ')"

      if [[ "$total_count" -ne "$unique_count" ]]; then
        local dup_ids
        dup_ids="$(printf '%s\n' "${step_ids[@]}" | sort | uniq -d | tr '\n' ',' | sed 's/,$//')"
        id_status="observe"
        id_detail="duplicate step ids: ${dup_ids}"

        # Add to findings
        findings_json="$(printf '%s' "$findings_json" | jq \
          --arg id "identifier_domain" \
          --arg detail "duplicate step ids: ${dup_ids}" \
          '. + [{"id": $id, "status": "observe", "detail": $detail}]')"
      fi
    fi
  fi

  structural_checks_json="$(printf '%s' "$structural_checks_json" | jq \
    --arg id "identifier_domain" \
    --arg status "$id_status" \
    --arg detail "$id_detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]')"

  # --------------------------------------------------------------------------
  # Check 3: schema_completeness
  # Does plan.md have required frontmatter and section headers?
  # --------------------------------------------------------------------------
  local sc_status="pass"
  local sc_missing=()

  # Check frontmatter block exists (--- delimiters)
  local fm_block
  fm_block="$(awk '/^---$/{if(p==0){p=1;next}else{exit}} p{print}' "$plan_md" 2>/dev/null || true)"

  if [[ -z "$fm_block" ]]; then
    sc_missing+=("frontmatter block")
    sc_status="observe"
  else
    # Check required frontmatter keys: id, type, status
    for fm_key in id type status; do
      if ! echo "$fm_block" | grep -qE "^${fm_key}:"; then
        sc_missing+=("missing ${fm_key}:")
        sc_status="observe"
      fi
    done

    # Check for risk: field (advisory only — note if missing but keep observe not fail)
    if ! echo "$fm_block" | grep -qE "^risk:"; then
      sc_missing+=("missing risk: field")
      sc_status="observe"
    fi
  fi

  # Check section headers
  # Goal: ## Goal or ## Cíl
  if ! grep -qE '^## (Goal|Cíl)' "$plan_md" 2>/dev/null; then
    sc_missing+=("missing ## Goal section")
    sc_status="observe"
  fi

  # Scope: ## Scope or ## Rozsah
  if ! grep -qE '^## (Scope|Rozsah)' "$plan_md" 2>/dev/null; then
    sc_missing+=("missing ## Scope section")
    sc_status="observe"
  fi

  # Steps: ## Steps or ## Kroky or a step table with | # | Role |
  local has_steps_section=0
  if grep -qE '^## (Steps|Kroky)' "$plan_md" 2>/dev/null; then
    has_steps_section=1
  elif grep -qE '^\| *# *\| *(Role|role)' "$plan_md" 2>/dev/null; then
    has_steps_section=1
  elif grep -qE '^\| *[0-9]+ *\|' "$plan_md" 2>/dev/null; then
    has_steps_section=1
  fi

  if [[ "$has_steps_section" -eq 0 ]]; then
    sc_missing+=("missing ## Steps section")
    sc_status="observe"
  fi

  local sc_detail=""
  if [[ "${#sc_missing[@]}" -gt 0 ]]; then
    sc_detail="$(printf '%s; ' "${sc_missing[@]}" | sed 's/; $//')"
  fi

  structural_checks_json="$(printf '%s' "$structural_checks_json" | jq \
    --arg id "schema_completeness" \
    --arg status "$sc_status" \
    --arg detail "$sc_detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]')"

  # --------------------------------------------------------------------------
  # Check 4: producer_consumer_order
  # Does topological_order from plan-graph.json have each producer before consumers?
  # --------------------------------------------------------------------------
  local pc_status="unverifiable"
  local pc_detail=""

  if [[ -f "$pg_file" ]] && jq . "$pg_file" >/dev/null 2>&1; then
    # Extract topological_order and edges from plan-graph.json
    # plan-graph may have the data at top level or inside plan_graph key
    local topo_order
    topo_order="$(jq -r '(.plan_graph.topological_order // .topological_order // [])[]' "$pg_file" 2>/dev/null || true)"

    local edges_data
    edges_data="$(jq -r '(.plan_graph.edges // .edges // [])[] | "\(.before)->\(.after)"' "$pg_file" 2>/dev/null || true)"

    if [[ -z "$topo_order" && -z "$edges_data" ]]; then
      pc_status="pass"
      pc_detail="no edges to check"
    elif [[ -z "$topo_order" ]]; then
      pc_status="observe"
      pc_detail="topological_order is empty (possible cycles)"
    else
      # Build position map from topological order
      local order_violation=0
      local violation_detail=""
      local pos=0
      declare -A topo_pos

      while IFS= read -r node; do
        [[ -z "$node" ]] && continue
        topo_pos["$node"]="$pos"
        (( pos++ )) || true
      done <<< "$topo_order"

      if [[ -n "$edges_data" ]]; then
        while IFS= read -r edge; do
          [[ -z "$edge" ]] && continue
          local prod="${edge%%->*}"
          local cons="${edge##*->}"

          local prod_pos="${topo_pos[$prod]:-}"
          local cons_pos="${topo_pos[$cons]:-}"

          if [[ -z "$prod_pos" || -z "$cons_pos" ]]; then
            # Node not in topo order (possibly from a cycle)
            continue
          fi

          if [[ "$prod_pos" -ge "$cons_pos" ]]; then
            order_violation=1
            violation_detail="${prod} (pos ${prod_pos}) appears after consumer ${cons} (pos ${cons_pos})"
            break
          fi
        done <<< "$edges_data"
      fi

      if [[ "$order_violation" -eq 1 ]]; then
        pc_status="observe"
        pc_detail="order violation: $violation_detail"
      else
        pc_status="pass"
        pc_detail=""
      fi

      unset topo_pos
    fi
  fi

  structural_checks_json="$(printf '%s' "$structural_checks_json" | jq \
    --arg id "producer_consumer_order" \
    --arg status "$pc_status" \
    --arg detail "$pc_detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]')"

  # --------------------------------------------------------------------------
  # Check 5: contract_manifest_hash
  # Does contract-manifest.json exist? Is manifest_hash present and non-empty?
  # --------------------------------------------------------------------------
  local cm_file="${evidence_dir}/contract-manifest.json"
  local cm_status="unverifiable"
  local cm_detail=""

  if [[ ! -f "$cm_file" ]]; then
    cm_status="unverifiable"
    cm_detail="contract-manifest.json not found in evidence dir"
  elif ! jq . "$cm_file" >/dev/null 2>&1; then
    cm_status="observe"
    cm_detail="contract-manifest.json is not valid JSON"
  else
    # manifest_hash may be at top level or inside contract_manifest key
    local mhash
    mhash="$(jq -r '(.contract_manifest.manifest_hash // .manifest_hash // "") ' "$cm_file" 2>/dev/null || true)"
    if [[ -z "$mhash" || "$mhash" == "null" ]]; then
      cm_status="observe"
      cm_detail="manifest_hash is absent or empty"
    else
      cm_status="pass"
      cm_detail=""
    fi
  fi

  structural_checks_json="$(printf '%s' "$structural_checks_json" | jq \
    --arg id "contract_manifest_hash" \
    --arg status "$cm_status" \
    --arg detail "$cm_detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]')"

  # -------------------------------------------------------------------------
  # Lens evidence scan (5 C0 lenses)
  # -------------------------------------------------------------------------
  local lens_findings_json="[]"
  local lenses_found=0

  _scan_lens() {
    local lens_name="$1"
    local lens_file="${evidence_dir}/c0-lens-${lens_name}.md"

    local verdict="absent"
    local count=0

    if [[ -f "$lens_file" ]]; then
      # Find stop_rule_blockers line and count items
      # Supported formats:
      #   stop_rule_blockers: []           -> count=0
      #   stop_rule_blockers: [item1, item2] -> count=N (inline list)
      #   stop_rule_blockers:              -> followed by "  - ..." or "- ..." lines

      local blockers_line
      blockers_line="$(grep -m1 '^stop_rule_blockers:' "$lens_file" 2>/dev/null || true)"

      if [[ -n "$blockers_line" ]]; then
        # Check for inline empty list: []
        if echo "$blockers_line" | grep -qE '^stop_rule_blockers:[[:space:]]*\[\]'; then
          count=0
        # Check for inline list with items: [item1, item2]
        elif echo "$blockers_line" | grep -qE '^stop_rule_blockers:[[:space:]]*\[.+\]'; then
          # Count commas + 1 to estimate items (simple heuristic for non-empty inline lists)
          local inline_content
          inline_content="$(echo "$blockers_line" | sed 's/^stop_rule_blockers:[[:space:]]*//' | sed 's/^\[//; s/\]$//')"
          # Count items separated by commas
          count=$(( $(echo "$inline_content" | tr -cd ',' | wc -c) + 1 ))
        else
          # Multi-line block: count following lines starting with "  - " or "- "
          # Get line number of stop_rule_blockers:
          local start_line
          start_line="$(grep -n '^stop_rule_blockers:' "$lens_file" 2>/dev/null | head -1 | cut -d: -f1)"
          if [[ -n "$start_line" ]]; then
            # Count subsequent lines starting with optional spaces + dash
            count="$(awk -v start="$start_line" '
              NR > start {
                if (/^[[:space:]]*-[[:space:]]/) { c++ }
                else if (/^[a-zA-Z]/) { exit }
              }
              END { print c+0 }
            ' "$lens_file" 2>/dev/null || echo "0")"
          fi
        fi

        if [[ "$count" -gt 0 ]]; then
          verdict="found"
        else
          verdict="clean"
        fi
      else
        # File exists but no stop_rule_blockers: line found — treat as clean
        verdict="clean"
        count=0
      fi

      (( lenses_found++ )) || true
    fi

    lens_findings_json="$(printf '%s' "$lens_findings_json" | jq \
      --arg lens "$lens_name" \
      --arg verdict "$verdict" \
      --argjson count "$count" \
      '. + [{"lens": $lens, "verdict": $verdict, "count": $count}]')"
  }

  _scan_lens "reuse_compat"
  _scan_lens "planned_call_feasibility"
  _scan_lens "dep_api_grounding"
  _scan_lens "idempotency_matrix"
  _scan_lens "authority_runtime_matrix"

  local lens_dispatch_observed="${lenses_found}/5"

  # -------------------------------------------------------------------------
  # Assemble plan_review payload
  # -------------------------------------------------------------------------
  local pr_payload
  pr_payload="$(jq -n \
    --argjson structural_checks "$structural_checks_json" \
    --argjson lens_findings     "$lens_findings_json" \
    --arg     lens_dispatch     "$lens_dispatch_observed" \
    --argjson findings          "$findings_json" \
    '{
      "structural_checks":       $structural_checks,
      "lens_findings":           $lens_findings,
      "lens_dispatch_observed":  $lens_dispatch,
      "findings":                $findings
    }')"

  # -------------------------------------------------------------------------
  # Wrap in protocol v2 envelope and write plan-review.json
  # -------------------------------------------------------------------------
  local review_envelope
  review_envelope="$(_build_envelope "plan_review" "plan_review" "$pr_payload" "$project_root")"

  # Override status from "pending" to "pass" (observe-only — structural checks
  # never block, so outcome is always pass at envelope level)
  review_envelope="$(printf '%s' "$review_envelope" | jq '.status = "pass"')"

  printf '%s\n' "$review_envelope" > "$review_out"

  # -------------------------------------------------------------------------
  # Self-validate with aid-protocol-validate.sh (advisory — errors to stderr only)
  # -------------------------------------------------------------------------
  local validate_script="${SCRIPT_DIR}/aid-protocol-validate.sh"
  if [[ -f "$validate_script" ]]; then
    if ! bash "$validate_script" "$review_out" >/dev/null 2>&1; then
      echo "WARNING: plan-review.json failed protocol validation (non-blocking)" >&2
      bash "$validate_script" "$review_out" >&2 || true
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$SUBCOMMAND" in
  contract)
    cmd_contract "$@"
    ;;
  review)
    cmd_review "$@"
    ;;
  *)
    echo "ERROR: Unknown subcommand: $SUBCOMMAND" >&2
    echo "Available subcommands: contract, review" >&2
    exit 1
    ;;
esac
