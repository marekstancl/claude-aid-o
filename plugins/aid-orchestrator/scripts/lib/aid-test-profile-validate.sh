#!/usr/bin/env bash
# aid-test-profile-validate.sh — P072 Step 13 (fail-closed profile ingestion).
#
# The consolidator turns profiling receipts into actions a person will act on:
# "fix this suite", "stop dispatching it twice". A receipt that is truncated,
# hand-edited, produced by an older build, or dropped into the directory by
# something else entirely must therefore STOP finalization.
#
# The first cut ended its ingestion pipeline with `|| echo '[]'`. That is the
# exact failure mode this plugin's own principles name: a corrupt input became
# an empty action list, and an empty action list is indistinguishable from
# "there was nothing to do". Silence that reads as a clean bill of health is
# worse than a hard failure, because nobody goes looking for it.
#
# Exit codes (shared by every function here):
#   0  valid
#   3  invalid — schema violation, wrong schema_version, or unparseable JSON
#   2  the validator itself is unavailable
set -uo pipefail

_TPV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TPV_SCHEMA="${AID_TEST_PROFILE_SCHEMA:-${_TPV_LIB_DIR}/../../defaults/schemas/test-profile.schema.json}"

_tpv_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# test_profile_validate <file> — echoes human-readable errors on stderr.
test_profile_validate() {
  local instance="$1"

  [[ -f "$instance" ]] || {
    echo "aid-test-profile: no such receipt: '$instance'" >&2
    return 3
  }
  if ! jq -e . "$instance" >/dev/null 2>&1; then
    echo "aid-test-profile: '$instance' is not parseable JSON — refusing to treat an unreadable receipt as 'no findings'" >&2
    return 3
  fi
  if [[ ! -f "$_TPV_SCHEMA" ]]; then
    echo "aid-test-profile: schema not found at '$_TPV_SCHEMA' — refusing to treat an unvalidated receipt as valid" >&2
    return 2
  fi
  _tpv_have_jsonschema || {
    echo "aid-test-profile: validator unavailable (python3 + jsonschema required) — refusing to act on unvalidated receipts" >&2
    return 2
  }

  local errors
  errors="$(python3 - "$_TPV_SCHEMA" "$instance" <<'PY'
import json, sys
from jsonschema.validators import Draft202012Validator

schema = json.load(open(sys.argv[1]))
try:
    instance = json.load(open(sys.argv[2]))
except Exception as exc:                      # noqa: BLE001
    print(f"unparseable: {exc}")
    sys.exit(0)

v = Draft202012Validator(schema)
for err in sorted(v.iter_errors(instance), key=lambda e: list(e.path)):
    where = "/".join(str(p) for p in err.path) or "(root)"
    print(f"{where}: {err.message}")
PY
)" || {
    echo "aid-test-profile: the validator itself failed on '$instance'" >&2
    return 2
  }

  if [[ -n "$errors" ]]; then
    echo "aid-test-profile: receipt '$instance' does not satisfy aid-test-profile-v1:" >&2
    printf '  %s\n' "$errors" >&2
    return 3
  fi
  return 0
}

# test_profile_bindings <file> <expected_audit_id> — the two provenance checks
# the schema alone cannot make, because both compare the receipt against
# something outside it.
#
# A directory is not provenance. Without these, a receipt left behind by an
# earlier audit, or a log edited after the run, would be read as current
# evidence for whatever audit happens to be finalizing now.
test_profile_bindings() {
  local instance="$1" expected_audit="$2"
  local got_audit log_name log_path recorded_sha actual_sha

  got_audit="$(jq -r '.audit_id // ""' "$instance")"
  if [[ -n "$expected_audit" ]]; then
    if [[ -z "$got_audit" ]]; then
      echo "aid-test-profile: '$instance' records no audit_id — it cannot be shown to belong to audit '$expected_audit'" >&2
      return 3
    fi
    if [[ "$got_audit" != "$expected_audit" ]]; then
      echo "aid-test-profile: '$instance' belongs to audit '$got_audit', not '$expected_audit' — refusing to read another audit's measurement as this one's evidence" >&2
      return 3
    fi
  fi

  # The evidence log sits beside the receipt, under the name the receipt gives.
  log_name="$(jq -r '.evidence_log' "$instance")"
  log_path="$(dirname "$instance")/${log_name}"
  if [[ ! -f "$log_path" ]]; then
    echo "aid-test-profile: '$instance' cites evidence log '$log_name', which is not present beside it — a receipt without its evidence is a claim, not a measurement" >&2
    return 3
  fi
  recorded_sha="$(jq -r '.evidence_log_sha256' "$instance")"
  actual_sha="$(sha256sum "$log_path" | cut -d' ' -f1)"
  if [[ "$recorded_sha" != "$actual_sha" ]]; then
    echo "aid-test-profile: the evidence log for '$instance' does not hash to what the receipt recorded (${recorded_sha:0:12}… vs ${actual_sha:0:12}…) — the log was changed after the run" >&2
    return 3
  fi
  return 0
}

# test_profile_validate_dir <dir> [expected_audit_id] — every *.json in the
# directory must be a valid, correctly bound receipt. There is deliberately NO
# "skip the ones that do not look like profiles" branch: a foreign file in the
# profiles directory means the caller passed the wrong directory, and guessing
# which files were meant is how an audit ends up silently profiling nothing.
test_profile_validate_dir() {
  local dir="$1" expected_audit="${2:-}" rc=0 f this
  [[ -d "$dir" ]] || {
    echo "aid-test-profile: profiles directory '$dir' does not exist" >&2
    return 3
  }
  while IFS= read -r -d '' f; do
    # `test_profile_validate "$f"; this=$?` and NOT `if ! test_profile_validate`:
    # `!` inverts the status, so `$?` read inside the branch is 0 and every
    # detected violation silently downgrades to success. The exact bug this
    # library exists to prevent, in the library that prevents it.
    test_profile_validate "$f"; this=$?
    if [[ "$this" -ne 0 ]]; then
      [[ "$this" -gt "$rc" ]] && rc="$this"
      continue
    fi
    test_profile_bindings "$f" "$expected_audit"; this=$?
    if [[ "$this" -ne 0 ]]; then
      [[ "$this" -gt "$rc" ]] && rc="$this"
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null | sort -z)
  return "$rc"
}
