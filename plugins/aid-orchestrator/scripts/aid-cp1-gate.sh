#!/usr/bin/env bash
# =============================================================================
# aid-cp1-gate.sh — CP1-deep evidence gate for high-risk plans
#
# Usage:
#   ./aid-cp1-gate.sh --plan <path> [--project-root <path>]
#
# For low-risk plans: exits 0 immediately (no evidence required).
# For high-risk plans: verifies that all 4 CP1-deep evidence files exist
# and that the adjudicator verdict has no unresolved accepted blockers.
#
# Risk is determined by:
#   1. Plan frontmatter field `risk: low|medium|high`
#   2. High-risk pattern grep across plan body (overrides `risk: medium` or absent)
#
# High-risk patterns (from skills/review-checkpoint-contracts.md):
#   - Auth handlers / routes
#   - Auth logic (authenticate, authorize, verify_token, ...)
#   - Schema / validation (Schema, Validator, pydantic, BaseModel, ...)
#   - Migrations (migrate, alembic, revision, upgrade, downgrade)
#   - FSM / state (fsm-state, cmd_transition, aid-fsm.sh, ...)
#   - Security sinks (exec(, subprocess, eval(, pickle, yaml.load)
#   - Payment (stripe, payment, charge, billing, invoice)
#   - Dependency manifests (requirements.txt, pyproject.toml, package.json, Gemfile)
#
# Evidence dir: <project_root>/.aid-o/work/evidence/<plan_id>/cp1-deep/
# Required files (all 4 must exist):
#   cp1-lens-security.md
#   cp1-lens-correctness.md
#   cp1-lens-architectural.md
#   cp1-adjudicator.md
#
# Adjudicator check: reads cp1-adjudicator.md and fails if the file
# contains non-empty `accepted_blockers:` (i.e., unresolved blockers).
# A YAML value of `accepted_blockers: []` (empty list) is a pass.
#
# stdout: human-readable status lines
# stderr: JSON error on failure (consistent with other AID scripts)
# Exit codes: 0=pass or not-applicable, 1=gate failure, 2=usage error, 3=I/O error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
plan=""
project_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)         plan="$2";         shift 2 ;;
    --project-root) project_root="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $(basename "$0") --plan <path> [--project-root <path>]"
      echo ""
      echo "Options:"
      echo "  --plan <path>          Path to the plan .md file (required)"
      echo "  --project-root <path>  Project root containing .aid-o/ (default: cwd)"
      echo "  --help                 Show this help"
      exit 0
      ;;
    *)
      error_exit "Unknown argument: $1" 2
      ;;
  esac
done

[[ -z "$plan" ]] && error_exit "Missing required argument: --plan" 2
[[ ! -f "$plan" ]] && error_exit "Plan file not found: $plan" 3

# Default project root to cwd
[[ -z "$project_root" ]] && project_root="$(pwd)"

# ---------------------------------------------------------------------------
# Step 1: Extract plan ID from frontmatter
# ---------------------------------------------------------------------------
plan_id=""
risk_fm=""  # risk value from frontmatter (low|medium|high or empty)

while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^id:[[:space:]]*(.+)$ ]]; then
    plan_id="${BASH_REMATCH[1]}"
    plan_id="$(echo "$plan_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  if [[ "$line" =~ ^risk:[[:space:]]*(.+)$ ]]; then
    risk_fm="${BASH_REMATCH[1]}"
    risk_fm="$(echo "$risk_fm" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  # Stop at end of frontmatter block (second ---)
  [[ "$line" == "---" && -n "$plan_id" ]] && break
done < "$plan"

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1
[[ "$plan_id" =~ ^[A-Za-z0-9_-]+$ ]] || error_exit "Plan id '$plan_id' contains invalid characters (path traversal guard)" 1

# ---------------------------------------------------------------------------
# Step 2: Determine if the plan is high-risk
# ---------------------------------------------------------------------------
# High-risk patterns (grep -E extended regex, applied to plan body).
# Each pattern matches one risk category from review-checkpoint-contracts.md.
HIGH_RISK_PATTERNS=(
  # routes / auth handlers
  '@app\.(get|post|put|patch|delete|head|options)\(|@router\.(get|post|put|patch|delete|head|options)\(|add_route\(|def [a-zA-Z_]+\(.*request|async def [a-zA-Z_]+\(.*request'
  # auth logic
  'authenticate|authorize|verify_token|check_permission|require_auth'
  # schema / validation
  'Schema|Validator|validate\(|marshmallow|pydantic|BaseModel'
  # migrations
  'migrate|alembic|revision|upgrade|downgrade'
  # fsm / state
  'fsm-state|state_machine|cmd_transition|aid-fsm\.sh'
  # security sinks
  'exec\(|subprocess|eval\(|pickle|yaml\.load'
  # payment
  'stripe|payment|charge|billing|invoice'
  # dependency manifests
  'requirements\.txt|pyproject\.toml|package\.json|Gemfile'
)

is_high_risk=0

# Frontmatter `risk: high` always triggers CP1-deep
if [[ "$risk_fm" == "high" ]]; then
  is_high_risk=1
fi

# Frontmatter `risk: low` exempts from pattern scan
if [[ "$risk_fm" == "low" ]]; then
  is_high_risk=0
else
  # Scan plan body for high-risk patterns
  for pattern in "${HIGH_RISK_PATTERNS[@]}"; do
    if grep -qE "$pattern" "$plan" 2>/dev/null; then
      is_high_risk=1
      break
    fi
  done
fi

# ---------------------------------------------------------------------------
# Step 3: If not high-risk, exit immediately — gate is not applicable
# ---------------------------------------------------------------------------
if [[ "$is_high_risk" -eq 0 ]]; then
  echo "CP1-gate: plan $plan_id is low-risk — CP1-deep not required. Proceeding." >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3b: If no .aid-o/ workspace exists, gate is not applicable.
# The gate only enforces within AID-managed projects. Scripts calling
# aid-plan-to-epic.sh directly (e.g., from test harnesses) without a
# workspace are not subject to CP1-deep enforcement.
# ---------------------------------------------------------------------------
if [[ ! -d "${project_root}/.aid-o" ]]; then
  echo "CP1-gate: no .aid-o/ workspace found at ${project_root} — gate skipped (not an AID project)." >&2
  exit 0
fi

echo "CP1-gate: plan $plan_id is high-risk — checking CP1-deep evidence." >&2

# ---------------------------------------------------------------------------
# Step 4: Check for evidence dir and required files
# ---------------------------------------------------------------------------
evidence_dir="${project_root}/.aid-o/work/evidence/${plan_id}/cp1-deep"

REQUIRED_FILES=(
  "cp1-lens-security.md"
  "cp1-lens-correctness.md"
  "cp1-lens-architectural.md"
  "cp1-adjudicator.md"
)

missing_files=()
for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${evidence_dir}/${f}" ]]; then
    missing_files+=("$f")
  fi
done

if [[ "${#missing_files[@]}" -gt 0 ]]; then
  missing_list="$(printf '  - %s\n' "${missing_files[@]}")"
  cat >&2 <<ERRMSG
ERROR: High-risk plan requires CP1-deep evidence.
Missing files in ${evidence_dir}/:
${missing_list}
Run /aid-plan --deep to generate CP1-deep evidence before EPIC generation.
ERRMSG
  exit 1
fi

echo "CP1-gate: all 4 evidence files present in ${evidence_dir}/" >&2

# ---------------------------------------------------------------------------
# Step 5: Check adjudicator verdict — no unresolved accepted_blockers allowed
# ---------------------------------------------------------------------------
adjudicator_file="${evidence_dir}/cp1-adjudicator.md"

# Extract the accepted_blockers value from the adjudicator file.
# We look for `accepted_blockers:` followed by either:
#   accepted_blockers: []        → empty list = pass
#   accepted_blockers: [...]     → non-empty = fail
#   accepted_blockers:           (block scalar with list items below) → fail
#
# Strategy: grep for the line, then check if the rest of the line is "[]" or empty.
# If it's a block scalar (next lines start with "  -"), that's also a fail.
accepted_blockers_line="$(grep -n "^accepted_blockers:" "$adjudicator_file" 2>/dev/null | head -1 || echo "")"

if [[ -z "$accepted_blockers_line" ]]; then
  # No accepted_blockers field found — treat as pass (field may not be present
  # if no blockers were identified at all). Check verdict field instead.
  verdict_line="$(grep -E "^verdict:" "$adjudicator_file" 2>/dev/null | head -1 || echo "")"
  if [[ -n "$verdict_line" ]]; then
    verdict_value="$(echo "$verdict_line" | sed 's/^verdict:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    if [[ "$verdict_value" == "fail" || "$verdict_value" == "revise" ]]; then
      cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved verdict: ${verdict_value}
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
      exit 1
    fi
  fi
  echo "CP1-gate: adjudicator shows no accepted_blockers field — assuming no blockers. PASS." >&2
  exit 0
fi

# Extract the value after "accepted_blockers:"
accepted_value="$(echo "$accepted_blockers_line" | sed 's/^[0-9]*:accepted_blockers:[[:space:]]*//')"
accepted_value="$(echo "$accepted_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [[ "$accepted_value" == "[]" || -z "$accepted_value" ]]; then
  # Check if it's a block scalar — look at the line after "accepted_blockers:"
  line_num="$(echo "$accepted_blockers_line" | cut -d: -f1)"
  next_line_num=$(( line_num + 1 ))
  next_line="$(sed -n "${next_line_num}p" "$adjudicator_file" 2>/dev/null || echo "")"
  next_line="$(echo "$next_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ "$next_line" =~ ^-[[:space:]] ]]; then
    # Block scalar with at least one list item — there are accepted blockers
    cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved blockers.
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
    exit 1
  fi

  echo "CP1-gate: adjudicator accepted_blockers is empty. PASS." >&2
  exit 0
else
  # Non-empty inline list — has accepted blockers
  cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved blockers.
accepted_blockers: ${accepted_value}
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
  exit 1
fi
