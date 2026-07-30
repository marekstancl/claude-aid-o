#!/usr/bin/env bash
# aid-test-audit-config.sh — P066 Step 5.
#
# Audit config contract — schema and default-loader, created BEFORE any
# consumer (Steps 11/13 in EPIC 2 call load_test_audit_config directly).
# /aid-init distribution (Step 18, copy-if-absent) is a separate, later
# concern: this loader works correctly from the hardcoded defaults below even
# before any project has run /aid-init against the new default file.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TAC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TAC_SCHEMA="${_TAC_LIB_DIR}/../../defaults/schemas/test-audit-config.schema.json"

# _tac_defaults_json — the exact hardcoded defaults every consumer step gets
# even before /aid-init (Step 18) has ever distributed test-audit.yaml.
#
# allowed_runners corrected during Step 11 (Codex review): these values MUST
# match the real `.runner` labels the Step 2-4 adapters actually emit into
# the catalog (`bats`, `package-script`, `declared-command`, `ci`) — the
# plan's original illustrative default (`bats, npm, vitest, playwright`)
# named test FRAMEWORKS, not adapter/runner labels, and would have silently
# excluded every non-Bats project's package-script/CI/declared-command
# run_units from dispatch by default — directly contradicting this plan's
# own Success Criteria ("a consumer project with no Bats gets a working
# static/measure audit from the package-script/generic adapters alone").
_tac_defaults_json() {
  jq -n '{
    budget_minutes_default: 30,
    max_read_only_audit_agents: 4,
    allowed_runners: ["bats", "package-script", "declared-command", "ci"]
  }'
}

# _tac_have_jsonschema — same idiom as test-aid-c3-dispatch.bats.
_tac_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# _tac_validate <instance_json> — exit 0 valid, 1 invalid. When python3 +
# jsonschema are unavailable, FAILS CLOSED (never a silent skip-as-valid) —
# matching aid-plan-fsm.sh's own established precedent (aid_lifecycle_schema_
# validate: "validator unavailable ... refusing to act on an unvalidated
# artifact"). A present config is a signal someone intended to customize it;
# accepting it unvalidated just because the validator happens to be missing
# would violate this loader's own fail-closed contract.
_tac_validate() {
  local instance_json="$1"
  _tac_have_jsonschema || {
    echo "load_test_audit_config: validator unavailable (python3 + jsonschema are required to validate test-audit-config.schema.json) — refusing to act on an unvalidated present config" >&2
    return 1
  }
  local instance_file
  instance_file="$(mktemp)"
  printf '%s' "$instance_json" > "$instance_file"
  python3 - "$_TAC_SCHEMA" "$instance_file" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
PY
  local rc=$?
  rm -f "$instance_file"
  return $rc
}

# load_test_audit_config [project_root]
#   Reads .aid-o/config/test-audit.yaml if present and schema-valid;
#   otherwise echoes the hardcoded defaults verbatim. A PRESENT but
#   malformed config fails closed (named error to stderr, non-zero exit,
#   NO output) — a present file is a signal someone intended to customize
#   it, so silently falling back to defaults would mask a real mistake.
load_test_audit_config() {
  local project_root="${1:-.}"
  local config_path="${project_root%/}/.aid-o/config/test-audit.yaml"

  [[ -f "$config_path" ]] || { _tac_defaults_json; return 0; }

  command -v yq >/dev/null 2>&1 || {
    echo "load_test_audit_config: yq not found on PATH — cannot parse $config_path" >&2
    return 1
  }

  local config_json
  config_json="$(yq -o=json '.' "$config_path" 2>/dev/null)" || {
    echo "load_test_audit_config: $config_path is not valid YAML" >&2
    return 1
  }
  [[ -n "$config_json" && "$config_json" != "null" ]] || {
    echo "load_test_audit_config: $config_path parsed to an empty document" >&2
    return 1
  }

  if ! _tac_validate "$config_json"; then
    echo "load_test_audit_config: $config_path failed schema validation (test-audit-config.schema.json)" >&2
    return 1
  fi

  printf '%s\n' "$config_json"
}
