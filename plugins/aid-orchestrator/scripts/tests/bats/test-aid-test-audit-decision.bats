#!/usr/bin/env bats
# aid-tier: t1
# test-aid-test-audit-decision.bats — P072 Step 2.
#
# Every "cannot" in the decision contract gets a case that ATTEMPTS it and
# asserts a non-zero exit with the documented code. A rule asserted only in
# prose is a rule nobody enforces.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../../.." && pwd)"
  LIB="${REPO_ROOT}/plugins/aid-orchestrator/scripts/lib/aid-test-audit-decision.sh"
  # shellcheck source=/dev/null
  source "$LIB"
  TMP="$(mktemp -d)"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# A minimal artifact that satisfies every rule — the baseline every negative
# case mutates exactly one field of, so a failure is attributable.
valid_decision() {
  cat <<'JSON'
{
  "schema_version": "aid-test-audit-decision-v1",
  "audit_id": "audit-20260802-070629",
  "audit_status": "complete",
  "current_runtime": {
    "kind": "measured",
    "duration_ms": 147000,
    "scope": ["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"]
  },
  "actions": [
    {
      "action": "fix",
      "targets": ["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"],
      "priority": "high",
      "reason": "setup/teardown accumulation dominates the measured runtime",
      "evidence_refs": ["profiles/test-aid-fsm.json"],
      "impact": { "kind": "measured", "before_ms": 147000, "after_ms": 44790, "assumptions": [] }
    }
  ],
  "unresolved": [],
  "portfolio_coverage": {
    "inventory_count": 1,
    "assigned_count": 1,
    "disposition_count": 1,
    "missing_run_unit_ids": [],
    "duplicate_run_unit_ids": []
  },
  "portfolio_change": {
    "current_run_units": 1,
    "proposed_run_units": 1,
    "keep": ["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"],
    "rewrite_unit": [],
    "merge_groups": [],
    "remove": [],
    "runtime_before_ms": 147000,
    "runtime_after_ms": 44790,
    "impact_kind": "measured"
  }
}
JSON
}

# mutate <jq-filter> — the baseline with one field changed.
mutate() { valid_decision | jq -c "$1"; }

@test "baseline: a fully valid artifact writes and reads back" {
  run aid_test_audit_decision_write "$(valid_decision)" "$TMP/decision.json"
  [ "$status" -eq 0 ]
  [ -f "$TMP/decision.json" ]

  run aid_test_audit_decision_read "$TMP/decision.json"
  [ "$status" -eq 0 ]

  run aid_test_audit_decision_status "$TMP/decision.json"
  [ "$status" -eq 0 ]
  [ "$output" = "complete" ]
}

@test "an unknown top-level field is rejected" {
  run aid_test_audit_decision_write "$(mutate '. + {sneaky: "value"}')" "$TMP/d.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"sneaky"* ]]
}

@test "a failed validation writes NO file at all" {
  run aid_test_audit_decision_write "$(mutate '. + {sneaky: "value"}')" "$TMP/d.json"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/d.json" ]
}

@test "impact.kind measured with a null before_ms is rejected" {
  run aid_test_audit_decision_write "$(mutate '.actions[0].impact.before_ms = null')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "impact.kind estimated with an empty assumptions[] is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"estimated", before_ms:1000, after_ms:500, assumptions:[]}')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "impact.kind estimated WITH assumptions is accepted" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"estimated", before_ms:1000, after_ms:500, assumptions:["assumes 4 workers"]}')" \
    "$TMP/d.json"
  [ "$status" -eq 0 ]
}

@test "impact.kind unknown claiming a numeric saving is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"unknown", before_ms:1000, after_ms:500, assumptions:[]}')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "audit_status complete with a non-empty missing_run_unit_ids is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.portfolio_coverage.missing_run_unit_ids = ["bats:orphan"]')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "audit_status complete with a duplicate run unit is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.portfolio_coverage.duplicate_run_unit_ids = ["bats:dup"]')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "audit_status incomplete without a reason is rejected" {
  run aid_test_audit_decision_write "$(mutate '.audit_status = "incomplete"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "audit_status incomplete WITH a controlled reason is accepted" {
  run aid_test_audit_decision_write \
    "$(mutate '.audit_status = "incomplete" | .incomplete_reason = "unresolved_fraction_exceeded"')" \
    "$TMP/d.json"
  [ "$status" -eq 0 ]
  run aid_test_audit_decision_status "$TMP/d.json"
  [ "$output" = "incomplete" ]
}

@test "a free-text incomplete_reason outside the vocabulary is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.audit_status = "incomplete" | .incomplete_reason = "it felt wrong"')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "current_runtime.kind unknown with a duration is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.current_runtime.kind = "unknown"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "an empty actions[] is legal and is NOT conflated with incomplete" {
  run aid_test_audit_decision_write "$(mutate '.actions = []')" "$TMP/d.json"
  [ "$status" -eq 0 ]
  run aid_test_audit_decision_status "$TMP/d.json"
  [ "$output" = "complete" ]
}

@test "an evidence_ref escaping via an embedded .. exits 5" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].evidence_refs = ["profiles/../../../etc/passwd"]')" "$TMP/d.json"
  [ "$status" -eq 5 ]
  [[ "$output" == *".."* ]]
  [ ! -f "$TMP/d.json" ]
}

@test "an evidence_ref with a leading ../ is caught earlier, by the schema" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].evidence_refs = ["../../etc/passwd"]')" "$TMP/d.json"
  [ "$status" -eq 3 ]
  [ ! -f "$TMP/d.json" ]
}

@test "an absolute evidence_ref is rejected by the schema" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].evidence_refs = ["/etc/passwd"]')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "an absolute path smuggled into a reason field is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "see /opt/eco/projects/secret/notes for context"')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "read re-validates: an artifact edited after writing is refused" {
  aid_test_audit_decision_write "$(valid_decision)" "$TMP/d.json"
  [ -f "$TMP/d.json" ]

  jq '. + {tampered: true}' "$TMP/d.json" > "$TMP/d.tmp" && mv "$TMP/d.tmp" "$TMP/d.json"

  run aid_test_audit_decision_read "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "status returns non-zero rather than defaulting when the artifact is invalid" {
  echo '{"schema_version":"aid-test-audit-decision-v1"}' > "$TMP/d.json"
  run aid_test_audit_decision_status "$TMP/d.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ] || [[ "$output" != "complete" && "$output" != "incomplete" ]]
}

@test "a missing artifact exits 2, distinct from an invalid one" {
  run aid_test_audit_decision_read "$TMP/nope.json"
  [ "$status" -eq 2 ]
}

@test "a wrong schema_version is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.schema_version = "aid-test-audit-decision-v2"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "a decision artifact without an audit_id is rejected (it could not be bound to its audit)" {
  run aid_test_audit_decision_write "$(mutate 'del(.audit_id)')" "$TMP/d.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"audit_id"* ]]
}

# ─── Public-safe reason text: named credential shapes ───────────────────────
#
# The contract claims a NARROW, enumerated list — not general secret
# detection. These cases pin both halves of that claim: the shapes it does
# reject, and the ordinary prose it must NOT reject, since a reason field that
# fires on the word "token" would push authors into vaguer reasons.

@test "an AWS access key id in a reason is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "credentials leaked: AKIAIOSFODNN7EXAMPLE"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "a GitHub token in a reason is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "use ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "a Slack token in a reason is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "slack xoxb-1234567890-abcdefghij"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "a PEM private-key header in a reason is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "found -----BEGIN RSA PRIVATE KEY----- in the fixture"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "an inline credential assignment with a substantial value is rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "api_key=sk_live_51H8xQ2eZvKYlo2C"')" "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "ordinary prose mentioning api_key or token is NOT rejected" {
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "the api_key is unset in this fixture"')" "$TMP/d.json"
  [ "$status" -eq 0 ]

  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].reason = "token handling is covered by the auth suite"')" "$TMP/d.json"
  [ "$status" -eq 0 ]
}

@test "the credential list is documented as narrow, not as general secret detection" {
  # The contract must not reappear as an unkeepable promise. If someone
  # broadens the wording, this fails and they have to broaden the checks too.
  run jq -r '.["$defs"].bounded_text["$comment"]' \
    "${REPO_ROOT}/plugins/aid-orchestrator/defaults/schemas/test-audit-decision.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deliberately narrow"* ]]
  [[ "$output" == *"not general secret detection"* ]]
}

@test "impact.kind unknown MAY carry a before_ms — a current cost is not a claimed saving" {
  # An unfinished profile's only real measurement is a lower bound. Forbidding
  # both numbers forced the alternative of dropping it, which would have made
  # the honest answer ("it costs at least this much, and I cannot say what it
  # would cost after") unrepresentable.
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"unknown", before_ms:60010, after_ms:null,
       assumptions:["the run did not finish — this is a lower bound on current cost, not a measured total"]}')" \
    "$TMP/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.actions[0].impact.before_ms' "$TMP/d.json")" = "60010" ]
}

@test "impact.kind unknown with a BARE before_ms is refused — the number must say what it is" {
  # `before_ms: 60010` on an unfinished run reads as a measured total unless it
  # is qualified. Permitting the number without the qualifier reintroduces the
  # overstatement that allowing the number at all was meant to avoid.
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"unknown", before_ms:60010, after_ms:null, assumptions:[]}')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "impact.kind unknown with NO number carries no assumptions either" {
  # Nothing to qualify, so a qualifier would be clutter dressed as rigour.
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"unknown", before_ms:null, after_ms:null, assumptions:["something"]}')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}

@test "impact.kind unknown still cannot carry an after_ms — no delta may be implied" {
  # With no after value there is no saving to infer; supplying one is exactly
  # the smuggled benefit this rule exists to stop.
  run aid_test_audit_decision_write \
    "$(mutate '.actions[0].impact = {kind:"unknown", before_ms:60010, after_ms:1000, assumptions:[]}')" \
    "$TMP/d.json"
  [ "$status" -eq 3 ]
}
