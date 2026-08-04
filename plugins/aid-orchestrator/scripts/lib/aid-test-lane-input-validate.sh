#!/usr/bin/env bash
# aid-test-lane-input-validate.sh — P072 Step 18 (fail-closed lane inputs).
#
# Resource maps and pilot receipts decide whether test files are proposed to
# run concurrently. The consolidator used to select them with nothing more than
# a `schema_version` string match, which meant an artifact could be malformed,
# belong to another audit, describe another catalog revision, or claim
# `promotion: proposed` with an EMPTY `repetitions` array — and still promote a
# lane. Its own schema would have rejected the last one outright.
#
# That is a fail-open in the decision layer, and the same one the profile
# receipts already had closed. This closes it for the other two artifact kinds
# on the same terms:
#
#   * schema-valid, or the audit stops;
#   * bound to THIS audit, or the audit stops;
#   * for pilots, the repetition contract re-checked here rather than trusted,
#     because a producer and a reader that disagree is how an invalid artifact
#     gets used anyway.
#
# Exit codes: 0 valid · 3 invalid · 2 validator unavailable

set -uo pipefail

_TLIV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TLIV_MAP_SCHEMA="${_TLIV_LIB_DIR}/../../defaults/schemas/test-resource-map.schema.json"
_TLIV_PILOT_SCHEMA="${_TLIV_LIB_DIR}/../../defaults/schemas/test-parallel-pilot.schema.json"

_tliv_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# _tliv_validate <schema> <instance> <label>
_tliv_validate() {
  local schema="$1" instance="$2" label="$3"
  [[ -f "$schema" ]] || {
    echo "aid-test-lane-input: ${label} schema not found at '$schema' — refusing to treat an unvalidated artifact as valid" >&2
    return 2
  }
  if ! jq -e . "$instance" >/dev/null 2>&1; then
    echo "aid-test-lane-input: '$instance' is not parseable JSON — an unreadable ${label} is not 'no findings'" >&2
    return 3
  fi
  _tliv_have_jsonschema || {
    echo "aid-test-lane-input: validator unavailable (python3 + jsonschema required) — refusing to act on unvalidated ${label}s" >&2
    return 2
  }
  local errors
  errors="$(python3 - "$schema" "$instance" <<'PY'
import json, sys
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
try:
    inst = json.load(open(sys.argv[2]))
except Exception as exc:                       # noqa: BLE001
    print(f"unparseable: {exc}"); sys.exit(0)
v = Draft202012Validator(schema)
for err in sorted(v.iter_errors(inst), key=lambda e: list(e.path)):
    where = "/".join(str(p) for p in err.path) or "(root)"
    print(f"{where}: {err.message}")
PY
)" || {
    echo "aid-test-lane-input: the validator itself failed on '$instance'" >&2
    return 2
  }
  if [[ -n "$errors" ]]; then
    echo "aid-test-lane-input: ${label} '$instance' is not schema-valid:" >&2
    printf '  %s\n' "$errors" >&2
    return 3
  fi
  return 0
}

# test_lane_validate_resource_maps <dir> <known_ids_file> — every *.json must
# be a valid map for a unit THIS AUDIT is about. The audit's own inventory is
# the authority for that, not a catalog that may have moved since: a map for a
# unit the inventory never heard of describes something else.
test_lane_validate_resource_maps() {
  local dir="$1" known_file="${2:-}" rc=0 f this uid
  [[ -d "$dir" ]] || { echo "aid-test-lane-input: resource-map directory '$dir' does not exist" >&2; return 3; }

  local known=""
  [[ -n "$known_file" && -f "$known_file" ]] && known="$(cat "$known_file")"

  while IFS= read -r -d '' f; do
    _tliv_validate "$_TLIV_MAP_SCHEMA" "$f" "resource map"; this=$?
    if [[ "$this" -ne 0 ]]; then [[ "$this" -gt "$rc" ]] && rc="$this"; continue; fi
    if [[ -n "$known" ]]; then
      uid="$(jq -r '.run_unit_id' "$f")"
      if ! grep -qxF "$uid" <<<"$known"; then
        echo "aid-test-lane-input: resource map '$f' is for run unit '$uid', which this audit's inventory does not contain" >&2
        rc=3
      fi
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null | sort -z)
  return "$rc"
}

# test_lane_validate_pilots <dir> <audit_id> <known_ids_file>
test_lane_validate_pilots() {
  local dir="$1" expected_audit="${2:-}" known_file="${3:-}" rc=0 f this
  [[ -d "$dir" ]] || { echo "aid-test-lane-input: pilots directory '$dir' does not exist" >&2; return 3; }

  local known=""
  [[ -n "$known_file" && -f "$known_file" ]] && known="$(cat "$known_file")"

  while IFS= read -r -d '' f; do
    _tliv_validate "$_TLIV_PILOT_SCHEMA" "$f" "pilot receipt"; this=$?
    if [[ "$this" -ne 0 ]]; then [[ "$this" -gt "$rc" ]] && rc="$this"; continue; fi

    # Bound to this audit. A receipt left behind by an earlier one is not
    # evidence for this one, however valid it is in itself.
    if [[ -n "$expected_audit" ]]; then
      local got; got="$(jq -r '.audit_id // ""' "$f")"
      if [[ -n "$got" && "$got" != "$expected_audit" ]]; then
        echo "aid-test-lane-input: pilot '$f' belongs to audit '$got', not '$expected_audit'" >&2
        rc=3; continue
      fi
    fi

    # The membership hash must actually cover the membership it lists.
    local listed_sha recorded_sha
    recorded_sha="$(jq -r '.membership_sha256' "$f")"
    listed_sha="$(jq -r '.membership | sort | .[]' "$f" | tr '\n' '\0' | sha256sum | cut -d' ' -f1)"
    if [[ "$recorded_sha" != "$listed_sha" ]]; then
      echo "aid-test-lane-input: pilot '$f' records a membership hash that does not cover its own membership — the receipt cannot be shown to be about the set it names" >&2
      rc=3; continue
    fi

    # Every piloted unit must exist in the catalog being consolidated.
    if [[ -n "$known" ]]; then
      local u missing=""
      while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        grep -qxF "$u" <<<"$known" || missing="$missing $u"
      done < <(jq -r '.membership[]' "$f")
      if [[ -n "$missing" ]]; then
        echo "aid-test-lane-input: pilot '$f' pilots unit(s) this audit's inventory does not contain:${missing}" >&2
        rc=3; continue
      fi
    fi

    # The repetition contract, re-checked rather than trusted. A producer and
    # a reader that disagree is how an invalid artifact gets used anyway.
    if [[ "$(jq -r '.promotion' "$f")" == "proposed" ]]; then
      local n_reps want_reps bad
      n_reps="$(jq '.repetitions | length' "$f")"
      want_reps="$(jq -r '.repeat' "$f")"
      if [[ "$n_reps" -ne "$want_reps" ]]; then
        echo "aid-test-lane-input: pilot '$f' proposes a lane on ${n_reps} repetition(s) after asking for ${want_reps}" >&2
        rc=3; continue
      fi
      bad="$(jq '[.repetitions[] | select(.verdict != "match"
                 or .serial.exit_code != 0 or .parallel.exit_code != 0
                 or .serial.job_state != "terminal_pass" or .parallel.job_state != "terminal_pass")] | length' "$f")"
      if [[ "$bad" -ne 0 ]]; then
        echo "aid-test-lane-input: pilot '$f' proposes a lane while ${bad} of its repetitions did not cleanly match" >&2
        rc=3; continue
      fi
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null | sort -z)
  return "$rc"
}
