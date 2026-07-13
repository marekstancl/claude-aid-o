#!/usr/bin/env bats
# test-lifecycle.bats — IMP-232 v2.58.0 canonical plan-level closure model.
# Covers lib/aid-lifecycle.sh + aid-lifecycle.sh CLI: repo identity (stable +
# immutable + schema-valid), strict legacy EPIC parser (required/backlog/
# ambiguous), state resolver (all states), and the public-safe + schema
# validation gate. FSM D1 gate behavior is covered in test-aid-fsm.bats.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CLI="$AID_PLUGIN_PATH/scripts/aid-lifecycle.sh"
  SCHEMAS="$AID_PLUGIN_PATH/defaults/schemas"
  TEST_DIR="$(mktemp -d)"
  (
    cd "$TEST_DIR"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email t@t.io; git config user.name T
    echo seed > seed; git add -A; git commit -q -m seed
  )
  cd "$TEST_DIR"
}
teardown() { rm -rf "$TEST_DIR"; }

# ── repo identity ────────────────────────────────────────────────────────────
@test "repo-id: creates a UUID, stable + immutable across calls" {
  run "$CLI" repo-id .
  [ "$status" -eq 0 ]
  local id1="$output"
  run "$CLI" repo-id .
  [ "$output" = "$id1" ]
  # file exists + not regenerated (same content)
  [ -f .aid-lifecycle/repo-identity.yaml ]
  [ "$(yq -r '.repo_id' .aid-lifecycle/repo-identity.yaml)" = "$id1" ]
}

@test "repo-id: identity file passes its schema" {
  "$CLI" repo-id . >/dev/null
  run "$CLI" validate .aid-lifecycle/repo-identity.yaml plan-lifecycle-identity.schema.json
  [ "$status" -eq 0 ]
}

@test "repo-id: does NOT regenerate when identity already exists" {
  "$CLI" repo-id . >/dev/null
  local before; before="$(cat .aid-lifecycle/repo-identity.yaml)"
  "$CLI" repo-id . >/dev/null
  [ "$(cat .aid-lifecycle/repo-identity.yaml)" = "$before" ]
}

# ── strict legacy EPIC parser ────────────────────────────────────────────────
@test "parse-legacy: required + backlog grammar, deterministic IDs" {
  mkdir -p .aid-o/plans
  cat > .aid-o/plans/P061-x.md <<'MD'
**EPIC 1: first (Steps 1-2)**
**EPIC 2: second (Steps 3-4)**
**EPIC 3 / Backlog: follow-up**
MD
  run "$CLI" parse-legacy P061 .aid-o/plans/P061-x.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"E-061-1_3 required"* ]]
  [[ "$output" == *"E-061-2_3 required"* ]]
  [[ "$output" == *"E-061-3_3 backlog"* ]]
}

@test "parse-legacy: ambiguous form => rc 2 (legacy-unverifiable, never a guess)" {
  mkdir -p .aid-o/plans
  cat > .aid-o/plans/P070-x.md <<'MD'
**EPIC 1 something odd without colon**
MD
  run "$CLI" parse-legacy P070 .aid-o/plans/P070-x.md
  [ "$status" -eq 2 ]
}

@test "parse-legacy: non-contiguous numbering => rc 2" {
  mkdir -p .aid-o/plans
  cat > .aid-o/plans/P071-x.md <<'MD'
**EPIC 1: a**
**EPIC 3: c**
MD
  run "$CLI" parse-legacy P071 .aid-o/plans/P071-x.md
  [ "$status" -eq 2 ]
}

# ── state resolver ───────────────────────────────────────────────────────────
@test "state: absent plan => not_found (a plan-number gap has no meaning)" {
  run "$CLI" state P064 .
  [ "$output" = "not_found" ]
}

@test "state: legacy plan with pending required EPICs => active" {
  mkdir -p .aid-o/plans
  cat > .aid-o/plans/P061-x.md <<'MD'
**EPIC 1: a (Steps 1-1)**
**EPIC 2: b (Steps 2-2)**
MD
  run "$CLI" state P061 .
  [ "$output" = "active" ]
}

@test "state: manifest with all required delivered+reviewed, no receipt => delivered-but-unreconciled" {
  mkdir -p .aid-lifecycle/manifests
  cat > .aid-lifecycle/manifests/P900.yaml <<'YML'
schema_version: aid-lifecycle-1.0
repo_id: t
plan_id: P900
declared_epics:
  - {id: E-900-1_1, scope: required}
depends_on_plans: []
deliveries:
  E-900-1_1: {reviewed_verdict: pass, unresolved_blockers: 0, delivery_sha: d1}
YML
  run "$CLI" state P900 .
  [ "$output" = "delivered-but-unreconciled" ]
}

@test "state: staged receipt (uncommitted) => closing_pending_commit; committed => closed" {
  mkdir -p .aid-lifecycle/receipts
  cat > .aid-lifecycle/receipts/P900.yaml <<'YML'
schema_version: aid-lifecycle-receipt-1.0
repo_id: t
plan_id: P900
plan_manifest_sha: sha256:abc
state: closed
YML
  run "$CLI" state P900 .
  [ "$output" = "closing_pending_commit" ]
  git add .aid-lifecycle/receipts/P900.yaml; git commit -q -m "receipt P900"
  run "$CLI" state P900 .
  [ "$output" = "closed" ]
}

@test "state: backlog EPIC does NOT block closing (required-only denominator)" {
  # P900 declares 1 required (delivered) + 1 backlog (no delivery) -> delivered-but-unreconciled
  mkdir -p .aid-lifecycle/manifests
  cat > .aid-lifecycle/manifests/P900.yaml <<'YML'
schema_version: aid-lifecycle-1.0
repo_id: t
plan_id: P900
declared_epics:
  - {id: E-900-1_2, scope: required}
  - {id: E-900-2_2, scope: backlog}
depends_on_plans: []
deliveries:
  E-900-1_2: {reviewed_verdict: pass, unresolved_blockers: 0, delivery_sha: d1}
YML
  run "$CLI" state P900 .
  [ "$output" = "delivered-but-unreconciled" ]
}

# ── public-safe + schema gate ────────────────────────────────────────────────
@test "validate: unknown field rejected (additionalProperties:false)" {
  cat > m.yaml <<'YML'
schema_version: v1
repo_id: t
plan_id: P900
declared_epics: [{id: E-900-1_1, scope: required}]
sneaky: x
YML
  run "$CLI" validate m.yaml plan-lifecycle-manifest.schema.json
  [ "$status" -ne 0 ]
}

@test "publicsafe: rejects absolute path, secret token, and free-text keys" {
  printf 'repo_id: t\nx: /home/user/secret.txt\n' > abs.yaml
  run "$CLI" publicsafe abs.yaml
  [ "$status" -ne 0 ]
  printf 'repo_id: t\napi_key: sk-abcdef\n' > sec.yaml
  run "$CLI" publicsafe sec.yaml
  [ "$status" -ne 0 ]
  printf 'repo_id: t\nwaiver_reason: because I said so\n' > wr.yaml
  run "$CLI" publicsafe wr.yaml
  [ "$status" -ne 0 ]
}

@test "publicsafe: accepts a clean technical receipt" {
  cat > ok.yaml <<'YML'
schema_version: aid-lifecycle-receipt-1.0
repo_id: 0ee29e7e-9daa
plan_id: P900
plan_manifest_sha: sha256:abc
state: closed
YML
  run "$CLI" publicsafe ok.yaml
  [ "$status" -eq 0 ]
}

@test "target-branch: reads config, default main" {
  run "$CLI" target-branch
  [ "$output" = "main" ]
}
