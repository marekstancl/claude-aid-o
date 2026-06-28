#!/usr/bin/env bash
# review-profile-check.sh — Check review profile coverage (missing_lenses detector)
#
# Exit: 0=complete (no missing), 1=missing lenses, 2=unverifiable
# Args: [<review-profile.json> <evidence_dir>] — or reads from env AID_* for FSM integration
# Env:
#   AID_PROJECT_ROOT — project root (for locating review-profile.json)
#   AID_EPIC_ID      — EPIC ID
#   AID_RUN_ID       — Run ID
#
# In E3: completed_lenses is always [] (C2/C3 contract for E5).
# Outputs CSV of missing lenses to stdout when exit=1.

set -uo pipefail

# --- Locate review-profile.json ---
# Priority: positional arg > env-derived path
if [[ $# -ge 1 ]]; then
  PROFILE_JSON="$1"
  EVIDENCE_DIR="${2:-$(dirname "$PROFILE_JSON")}"
else
  ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
  EPIC_ID="${AID_EPIC_ID:-}"
  RUN_ID="${AID_RUN_ID:-}"
  if [[ -z "$EPIC_ID" || -z "$RUN_ID" ]]; then
    echo "unverifiable: AID_EPIC_ID and AID_RUN_ID required when no positional args"
    exit 2
  fi
  EVIDENCE_DIR="${ROOT}/.aid-o/work/evidence/${EPIC_ID}/${RUN_ID}"
  PROFILE_JSON="${EVIDENCE_DIR}/review-profile.json"
fi

# --- Guard: file must exist and be valid JSON ---
if [[ ! -f "$PROFILE_JSON" ]]; then
  echo "unverifiable: review-profile.json not found: $PROFILE_JSON"
  exit 2
fi

_json_valid=false
if command -v jq &>/dev/null; then
  jq empty "$PROFILE_JSON" 2>/dev/null && _json_valid=true
fi
if [[ "$_json_valid" == "false" ]] && command -v python3 &>/dev/null; then
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PROFILE_JSON" 2>/dev/null && _json_valid=true
fi
if [[ "$_json_valid" == "false" ]]; then
  echo "unverifiable: review-profile.json is not valid JSON"
  exit 2
fi

# --- Read required_lenses and check field presence ---
HAS_REQUIRED=false
REQUIRED_LENSES=""

if command -v jq &>/dev/null; then
  if jq -e '.review_profile | has("required_lenses")' "$PROFILE_JSON" &>/dev/null; then
    HAS_REQUIRED=true
    REQUIRED_LENSES=$(jq -r '.review_profile.required_lenses // [] | .[]' "$PROFILE_JSON" 2>/dev/null | tr '\n' ' ' | xargs || true)
  fi
elif command -v python3 &>/dev/null; then
  _py_result=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
rp=d.get('review_profile',{})
if 'required_lenses' in rp:
    lenses=rp['required_lenses']
    print('HAS_REQUIRED=true')
    print('LENSES=' + ' '.join(lenses))
else:
    print('HAS_REQUIRED=false')
    print('LENSES=')
" "$PROFILE_JSON" 2>/dev/null || true)
  if echo "$_py_result" | grep -q "HAS_REQUIRED=true"; then
    HAS_REQUIRED=true
    REQUIRED_LENSES=$(echo "$_py_result" | grep "^LENSES=" | sed 's/^LENSES=//')
  fi
fi

if [[ "$HAS_REQUIRED" == "false" ]]; then
  echo "unverifiable: review-profile.json missing required_lenses field"
  exit 2
fi

# --- E3 contract: completed_lenses = [] (C2/C3 contract for E5) ---
# In E3, completed_lenses is always empty. Evidence markers from C2/C3 will be
# added by E5. For now: missing = all required_lenses.
COMPLETED_LENSES=""

# --- Compute missing = required - completed ---
MISSING_LENSES=""
for lens in $REQUIRED_LENSES; do
  if ! echo " $COMPLETED_LENSES " | grep -qF " $lens "; then
    MISSING_LENSES="${MISSING_LENSES}${MISSING_LENSES:+,}${lens}"
  fi
done

if [[ -z "$MISSING_LENSES" ]]; then
  # No missing lenses (empty required_lenses = docs_trivial)
  exit 0
else
  echo "$MISSING_LENSES"
  exit 1
fi
