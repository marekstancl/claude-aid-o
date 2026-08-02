#!/usr/bin/env bash
# aid-test-audit-decision.sh — P072 Step 2.
#
# Writer/reader/validator for the consolidated decision artifact
# (defaults/schemas/test-audit-decision.schema.json). Sourced, never executed
# directly.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention); an
# unguarded non-zero return here must never kill the caller's shell.
#
# Exit-code contract (every consumer branches on these, so they are part of
# the interface, not an implementation detail):
#   0  ok
#   2  schema file missing / validator unavailable
#   3  instance failed schema validation
#   4  cross-lane invariant violated (a run_unit_id in two lanes)
#   5  evidence_ref escapes the audit directory
#
# Why 4 and 5 are enforced here rather than in the schema: JSON Schema cannot
# express disjointness ACROSS array items, and it cannot resolve a path
# against a root it does not know. Both are real fail-closed rules, so they
# live in the one function every consumer already calls.

_TAD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TAD_SCHEMA="${_TAD_LIB_DIR}/../../defaults/schemas/test-audit-decision.schema.json"

# _tad_have_jsonschema — same idiom as aid-test-audit-config.sh.
_tad_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# _tad_schema_validate <instance_file> — 0 valid, 3 invalid, 2 unavailable.
# Fails CLOSED when the validator is missing: a validator that cannot find
# its schema must not report success, or the whole fail-closed chain this
# artifact anchors becomes decorative.
_tad_schema_validate() {
  local instance_file="$1"

  [[ -f "$_TAD_SCHEMA" ]] || {
    echo "aid-test-audit-decision: schema not found at '$_TAD_SCHEMA' — refusing to treat an unvalidated artifact as valid" >&2
    return 2
  }
  _tad_have_jsonschema || {
    echo "aid-test-audit-decision: validator unavailable (python3 + jsonschema required) — refusing to act on an unvalidated decision artifact" >&2
    return 2
  }

  local errors
  errors="$(python3 - "$_TAD_SCHEMA" "$instance_file" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
try:
    schema = json.load(open(sys.argv[1]))
    inst = json.load(open(sys.argv[2]))
except json.JSONDecodeError as e:
    print("not valid JSON: %s" % e)
    sys.exit(0)
for err in sorted(Draft202012Validator(schema).iter_errors(inst), key=lambda e: list(e.path)):
    pointer = "/" + "/".join(str(p) for p in err.path) if err.path else "(root)"
    print("%s: %s" % (pointer, err.message))
PY
)" || {
    echo "aid-test-audit-decision: validator itself failed to run" >&2
    return 2
  }

  [[ -z "$errors" ]] && return 0
  printf 'aid-test-audit-decision: schema validation failed:\n%s\n' "$errors" >&2
  return 3
}

# _tad_check_lane_disjointness <instance_file> — 0 ok, 4 on overlap.
# Reports the FIRST offending unit with BOTH lane ids, because naming only
# one lane leaves the reader to find the other by hand.
_tad_check_lane_disjointness() {
  local instance_file="$1" dup
  dup="$(jq -r '
    [ .parallelization.lanes[]? as $lane
      | $lane.run_unit_ids[]? | { unit: ., lane: $lane.lane_id } ]
    | group_by(.unit)
    | map(select(length > 1))
    | .[0] // empty
    | "\(.[0].unit)\t\(map(.lane) | join(", "))"
  ' "$instance_file" 2>/dev/null)"

  [[ -z "$dup" ]] && return 0
  echo "aid-test-audit-decision: run_unit '${dup%%$'\t'*}' appears in more than one lane (${dup#*$'\t'}) — lanes must be disjoint" >&2
  return 4
}

# _tad_check_evidence_refs <instance_file> — 0 ok, 5 on escape.
# The schema already anchors a ref to a non-'/' first character; this closes
# the remaining hole, a relative ref that climbs out via '..'.
_tad_check_evidence_refs() {
  local instance_file="$1" bad
  bad="$(jq -r '
    [ (.actions[]?.evidence_refs[]?),
      (.parallelization.lanes[]?.evidence_refs[]?) ]
    | map(select(test("(^|/)\\.\\.(/|$)")))
    | .[0] // empty
  ' "$instance_file" 2>/dev/null)"

  [[ -z "$bad" ]] && return 0
  echo "aid-test-audit-decision: evidence_ref '$bad' escapes the audit directory via '..' — refused" >&2
  return 5
}

# _tad_validate_all <instance_file> — schema, then the two invariants the
# schema cannot express. Order matters: a structurally invalid artifact is
# reported as such rather than as a lane violation found in garbage.
_tad_validate_all() {
  local instance_file="$1" rc
  _tad_schema_validate "$instance_file" || return $?
  _tad_check_lane_disjointness "$instance_file" || { rc=$?; return $rc; }
  _tad_check_evidence_refs "$instance_file" || { rc=$?; return $rc; }
  return 0
}

# aid_test_audit_decision_write <decision_json> <output_path>
#
# Validates FIRST, writes only on success, and writes atomically
# (tmp-then-mv, the same discipline as aid-test-inventory.sh). A validation
# failure leaves no file at all — a partially valid decision artifact must
# never land on disk, because a later reader cannot tell it apart from a
# complete one.
aid_test_audit_decision_write() {
  local decision_json="$1" output_path="$2" rc

  [[ -n "$output_path" ]] || {
    echo "aid_test_audit_decision_write: output path is required" >&2
    return 2
  }

  local tmp_instance
  tmp_instance="$(mktemp)" || return 2
  printf '%s' "$decision_json" > "$tmp_instance"

  # `_tad_validate_all ...; rc=$?` and NOT `if ! _tad_validate_all`: `!`
  # inverts the status, so `$?` inside the branch would read 0 and this
  # function would return success on every rejection.
  _tad_validate_all "$tmp_instance"; rc=$?
  if (( rc != 0 )); then
    rm -f "$tmp_instance"
    return $rc
  fi

  local out_dir; out_dir="$(dirname "$output_path")"
  [[ -d "$out_dir" ]] || mkdir -p "$out_dir" || { rm -f "$tmp_instance"; return 2; }

  local tmp_out="${output_path}.tmp.$$"
  if ! jq -S '.' "$tmp_instance" > "$tmp_out" 2>/dev/null; then
    rm -f "$tmp_instance" "$tmp_out"
    echo "aid_test_audit_decision_write: could not normalise the artifact for writing" >&2
    return 2
  fi
  rm -f "$tmp_instance"
  mv -f "$tmp_out" "$output_path" || { rm -f "$tmp_out"; return 2; }
  return 0
}

# aid_test_audit_decision_read <path>
#
# Re-validates on READ and echoes the artifact only when it still satisfies
# every rule. This is what makes a hand-edited artifact unusable rather than
# merely discouraged — the write-time check alone would not survive someone
# opening the file afterwards.
aid_test_audit_decision_read() {
  local path="$1" rc

  [[ -f "$path" ]] || {
    echo "aid_test_audit_decision_read: no decision artifact at '$path'" >&2
    return 2
  }

  _tad_validate_all "$path"; rc=$?
  (( rc == 0 )) || return $rc

  cat "$path"
}

# aid_test_audit_decision_status <path>
#
# Echoes `complete` or `incomplete`. Returns non-zero (never a defaulted
# status) when the artifact does not validate — an unreadable status is
# treated as no authorization, never as authorization.
aid_test_audit_decision_status() {
  local path="$1" rc
  local body
  body="$(aid_test_audit_decision_read "$path")" || { rc=$?; return $rc; }
  jq -r '.audit_status' <<<"$body"
}

# aid_test_audit_decision_lane_units <path>
#
# Echoes the union of every lane's run_unit_ids, one per line, sorted. Used
# by the consolidator's own cross-checks.
aid_test_audit_decision_lane_units() {
  local path="$1" rc
  local body
  body="$(aid_test_audit_decision_read "$path")" || { rc=$?; return $rc; }
  jq -r '[.parallelization.lanes[]?.run_unit_ids[]?] | unique | .[]' <<<"$body"
}
