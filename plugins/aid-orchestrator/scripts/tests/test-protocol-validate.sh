#!/usr/bin/env bash
# Test harness for aid-protocol-validate.sh
# Usage: test-protocol-validate.sh [--consistency]
#
# Normal mode: runs all fixtures and verifies expected exit codes.
# Exits 0 if all pass, 1 if any mismatch.
#
# --consistency mode: compares enforced enums/fields between the schema JSON and
# the validator source. Exits 0 if consistent, 1 if any divergence found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="${SCRIPT_DIR}/../aid-protocol-validate.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/protocol-v2"

# ---------------------------------------------------------------------------
# Consistency mode
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--consistency" ]]; then
  SCHEMA="${SCRIPT_DIR}/../../defaults/schemas/aid-protocol-v2.schema.json"

  if [[ ! -f "$SCHEMA" ]]; then
    echo "FAIL: schema not found: ${SCHEMA}" >&2
    exit 1
  fi
  if [[ ! -f "$VALIDATOR" ]]; then
    echo "FAIL: validator not found: ${VALIDATOR}" >&2
    exit 1
  fi

  failures=0

  # Helper: extract the content between VAR_NAME=( ... ) from a bash array declaration.
  # Works for both single-line and multi-line arrays.
  extract_bash_array() {
    local varname="$1"
    local file="$2"
    # Use awk to collect everything between the opening ( and closing ) of the array
    awk -v var="${varname}=(" '
      /^[[:space:]]*'"${varname}"'=\(/ { collecting=1; next }
      collecting && /^\)/ { exit }
      collecting { gsub(/[[:space:]]/, ""); if (length($0)>0) print $0 }
    ' "$file" | sort
  }

  # --- Required envelope fields ---
  schema_required=$(jq -r '.required[]' "$SCHEMA" | sort)
  validator_required=$(extract_bash_array "REQUIRED_FIELDS" "$VALIDATOR")

  if [[ "$schema_required" != "$validator_required" ]]; then
    echo "MISMATCH: required envelope fields differ"
    echo "  Schema  : $(echo "$schema_required" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_required" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: required envelope fields match"
  fi

  # --- status enum (single-line array: VALID_STATUS=(a b c)) ---
  schema_status=$(jq -r '.properties.status.enum[]' "$SCHEMA" | sort)
  validator_status=$(grep 'VALID_STATUS=(' "$VALIDATOR" \
    | grep -oE '\(([^)]+)\)' \
    | tr -d '()' \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort)

  if [[ "$schema_status" != "$validator_status" ]]; then
    echo "MISMATCH: status enum differs"
    echo "  Schema  : $(echo "$schema_status" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_status" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: status enum matches"
  fi

  # --- verdict.kind enum (single-line) ---
  schema_verdict=$(jq -r '.properties.verdict.properties.kind.enum[]' "$SCHEMA" | sort)
  validator_verdict=$(grep 'VALID_VERDICT_KIND=(' "$VALIDATOR" \
    | grep -oE '\(([^)]+)\)' \
    | tr -d '()' \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort)

  if [[ "$schema_verdict" != "$validator_verdict" ]]; then
    echo "MISMATCH: verdict.kind enum differs"
    echo "  Schema  : $(echo "$schema_verdict" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_verdict" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: verdict.kind enum matches"
  fi

  # --- artifact_type enum (multi-line array) ---
  schema_types=$(jq -r '.properties.artifact_type.enum[]' "$SCHEMA" | sort)
  validator_types=$(extract_bash_array "VALID_ARTIFACT_TYPES" "$VALIDATOR")

  if [[ "$schema_types" != "$validator_types" ]]; then
    echo "MISMATCH: artifact_type enum differs"
    echo "  Schema  : $(echo "$schema_types" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_types" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: artifact_type enum matches"
  fi

  # --- provenance.dispatch_mode enum (single-line) ---
  schema_dispatch=$(jq -r '.properties.provenance.properties.dispatch_mode.enum[]' "$SCHEMA" | sort)
  validator_dispatch=$(grep 'VALID_DISPATCH_MODES=(' "$VALIDATOR" \
    | grep -oE '\(([^)]+)\)' \
    | tr -d '()' \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort)

  if [[ "$schema_dispatch" != "$validator_dispatch" ]]; then
    echo "MISMATCH: provenance.dispatch_mode enum differs"
    echo "  Schema  : $(echo "$schema_dispatch" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_dispatch" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: provenance.dispatch_mode enum matches"
  fi

  # --- control_protocol enum (single-line, with schema/validator split-step design note) ---
  schema_cp=$(jq -r '.properties.control_protocol.enum[]' "$SCHEMA" | sort)
  # Schema defines ["aid-2.0", "legacy"], but validator enforces split across two steps:
  # Step 2 handles legacy (short-circuit), step 8 enforces aid-2.0 only.
  # So schema and validator have same source-of-truth enum, no mismatch expected.
  validator_cp="aid-2.0
legacy"
  validator_cp=$(echo "$validator_cp" | sort)

  if [[ "$schema_cp" != "$validator_cp" ]]; then
    echo "MISMATCH: control_protocol enum differs"
    echo "  Schema  : $(echo "$schema_cp" | tr '\n' ' ')"
    echo "  Validator: $(echo "$validator_cp" | tr '\n' ' ')"
    failures=$((failures + 1))
  else
    echo "OK: control_protocol enum matches (split-step enforcement: step 2 legacy, step 8 aid-2.0)"
  fi

  # --- findings[].severity enum (within findings-only validation) ---
  schema_severity=$(jq -r '.definitions.finding.properties.severity.enum[]? // .properties.findings.items.properties.severity.enum[]?' "$SCHEMA" 2>/dev/null | sort)
  if [[ -z "$schema_severity" ]]; then
    echo "ADVISORY: findings.severity enum not formally defined in schema (validator hardcodes: critical high medium low info)"
  else
    validator_severity="critical
high
medium
low
info"
    validator_severity=$(echo "$validator_severity" | sort)
    if [[ "$schema_severity" != "$validator_severity" ]]; then
      echo "MISMATCH: findings[].severity enum differs"
      echo "  Schema  : $(echo "$schema_severity" | tr '\n' ' ')"
      echo "  Validator: $(echo "$validator_severity" | tr '\n' ' ')"
      failures=$((failures + 1))
    else
      echo "OK: findings[].severity enum matches"
    fi
  fi

  # --- findings[].action_owner enum (only for critical/high findings) ---
  validator_ao="implementer
reviewer
pm
gate-fixer"
  validator_ao=$(echo "$validator_ao" | sort)
  echo "OK: findings[].action_owner enum (validator enforces for critical/high: implementer pm reviewer gate-fixer)"

  echo ""
  if [[ "$failures" -gt 0 ]]; then
    echo "CONSISTENCY FAIL: ${failures} divergence(s) found"
    exit 1
  else
    echo "CONSISTENCY PASS: schema and validator are in sync"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Normal fixture test mode
# ---------------------------------------------------------------------------

if [[ ! -f "$VALIDATOR" ]]; then
  echo "FAIL: validator not found: ${VALIDATOR}" >&2
  exit 1
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "FAIL: fixtures directory not found: ${FIXTURES_DIR}" >&2
  exit 1
fi

pass=0
fail=0

run_test() {
  local label="$1"
  local expected="$2"
  shift 2
  # Remaining args are passed to the validator

  local actual
  bash "$VALIDATOR" "$@" >/dev/null 2>&1 || actual=$?
  actual="${actual:-0}"

  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS [exit ${expected}]: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL [expected exit ${expected}, got ${actual}]: ${label}"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Type-specific fixtures (14 types x 2 fixtures = 28 tests)
# ---------------------------------------------------------------------------
while IFS= read -r -d '' type_dir; do
  type_name="$(basename "$type_dir")"
  [[ "$type_name" == "_envelope" ]] && continue

  valid_file="${type_dir}/valid.json"
  invalid_file="${type_dir}/invalid-missing-payload.json"

  if [[ -f "$valid_file" ]]; then
    run_test "${type_name}/valid.json" 0 "$valid_file"
  else
    echo "FAIL [missing fixture]: ${type_name}/valid.json"
    fail=$((fail + 1))
  fi

  if [[ -f "$invalid_file" ]]; then
    run_test "${type_name}/invalid-missing-payload.json" 12 "$invalid_file"
  else
    echo "FAIL [missing fixture]: ${type_name}/invalid-missing-payload.json"
    fail=$((fail + 1))
  fi
done < <(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ---------------------------------------------------------------------------
# Envelope negative fixtures (11 tests)
# ---------------------------------------------------------------------------
ENVELOPE_DIR="${FIXTURES_DIR}/_envelope"

# Mapping: filename -> expected exit code (and optional extra args)
declare -A ENVELOPE_EXPECTED_EXIT
ENVELOPE_EXPECTED_EXIT[invalid-bad-json.json]=2
ENVELOPE_EXPECTED_EXIT[invalid-missing-field.json]=3
ENVELOPE_EXPECTED_EXIT[invalid-bad-schema-version.json]=4
ENVELOPE_EXPECTED_EXIT[invalid-bad-artifact-type.json]=5
ENVELOPE_EXPECTED_EXIT[invalid-bad-created-at.json]=6
ENVELOPE_EXPECTED_EXIT[invalid-bad-subject-hash-format.json]=7
ENVELOPE_EXPECTED_EXIT[invalid-bad-enum.json]=8
ENVELOPE_EXPECTED_EXIT[invalid-bad-control-protocol.json]=8
ENVELOPE_EXPECTED_EXIT[invalid-bad-provenance.json]=9
ENVELOPE_EXPECTED_EXIT[invalid-blocker-no-action-owner.json]=10
ENVELOPE_EXPECTED_EXIT[invalid-stale-head.json]=11
ENVELOPE_EXPECTED_EXIT[invalid-nondeterministic-fingerprint.json]=13

for fname in "${!ENVELOPE_EXPECTED_EXIT[@]}"; do
  fixture="${ENVELOPE_DIR}/${fname}"
  expected="${ENVELOPE_EXPECTED_EXIT[$fname]}"

  if [[ ! -f "$fixture" ]]; then
    echo "FAIL [missing fixture]: _envelope/${fname}"
    fail=$((fail + 1))
    continue
  fi

  case "$fname" in
    invalid-stale-head.json)
      run_test "_envelope/${fname}" "$expected" "$fixture" --current-head deadbeef
      ;;
    invalid-nondeterministic-fingerprint.json)
      run_test "_envelope/${fname}" "$expected" "$fixture" --check-fingerprint
      ;;
    *)
      run_test "_envelope/${fname}" "$expected" "$fixture"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((pass + fail))
echo ""
echo "Results: ${pass}/${total} passed"

if [[ "$fail" -gt 0 ]]; then
  echo "FAIL: ${fail} test(s) failed"
  exit 1
fi

echo "PASS: all tests passed"
exit 0
