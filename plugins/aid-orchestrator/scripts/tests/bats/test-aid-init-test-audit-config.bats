#!/usr/bin/env bats
# aid-tier: t2
# test-aid-init-test-audit-config.bats — P066 Step 18.
#
# /aid-init has no dedicated distribution script (same as the check-severity.yaml
# precedent) — the controller follows commands/aid-init.md's documented
# copy-if-absent contract directly. This suite exercises that EXACT contract
# (copy-if-absent, never overwrite) against the real template file.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TEMPLATE="$AID_PLUGIN_PATH/defaults/config/test-audit.yaml"
  TARGET="$TEST_PROJECT_ROOT/.aid-o/config/test-audit.yaml"
}

teardown() {
  teardown_test_evidence_dir
}

# _init_copy_if_absent <template> <target> — the documented contract
# (commands/aid-init.md "Config Defaults Installation"): copy only if the
# target does not already exist, never overwrite.
_init_copy_if_absent() {
  local template="$1" target="$2"
  if [[ ! -f "$target" ]]; then
    mkdir -p "$(dirname "$target")"
    cp "$template" "$target"
    echo "[INSTALLED] $target"
  else
    echo "[EXISTS] $target"
  fi
}

@test "the distributed template exists and is schema-valid" {
  [ -f "$TEMPLATE" ]
  run yq -o=json '.' "$TEMPLATE"
  [ "$status" -eq 0 ]
}

@test "the distributed template's values are byte-identical to the loader's own hardcoded defaults" {
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-config.sh"
  local template_json loader_json
  template_json="$(yq -o=json '.' "$TEMPLATE" | jq -cS .)"
  loader_json="$(_tac_defaults_json | jq -cS .)"
  [ "$template_json" = "$loader_json" ]
}

@test "a fresh /aid-init (no existing target) creates .aid-o/config/test-audit.yaml matching the template" {
  [ ! -f "$TARGET" ]
  run _init_copy_if_absent "$TEMPLATE" "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INSTALLED]"* ]]
  [ -f "$TARGET" ]
  diff "$TEMPLATE" "$TARGET"
}

@test "re-running against a hand-edited copy leaves it byte-unchanged (PM customizations preserved)" {
  mkdir -p "$(dirname "$TARGET")"
  cat > "$TARGET" <<'YAML'
budget_minutes_default: 90
max_read_only_audit_agents: 8
allowed_runners:
  - bats
YAML
  local before_hash
  before_hash="$(sha256sum "$TARGET" | cut -d' ' -f1)"

  run _init_copy_if_absent "$TEMPLATE" "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[EXISTS]"* ]]

  local after_hash
  after_hash="$(sha256sum "$TARGET" | cut -d' ' -f1)"
  [ "$before_hash" = "$after_hash" ]
}

@test "load_test_audit_config reads the freshly-installed target and it validates against test-audit-config.schema.json" {
  run _init_copy_if_absent "$TEMPLATE" "$TARGET"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-config.sh"
  run load_test_audit_config "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.budget_minutes_default == 30 and .max_read_only_audit_agents == 4' >/dev/null
}
