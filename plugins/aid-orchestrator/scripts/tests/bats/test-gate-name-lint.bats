#!/usr/bin/env bats
# aid-tier: t0
#
# Proves aid-gate-name-lint.sh is a control and not a comment.
#
# Provenance: 2026-08-11. A gate named `bats_all` had run only T0+T1 since the
# tier pilot; the PM read its failure as "an agent is running the whole
# portfolio before every merge" and lost half a day. These cases pin the four
# rules that would have caught it, and — the case that matters most — that the
# allowlist grandfathers old names without ever excusing a new one.

setup() {
  LINT="${BATS_TEST_DIRNAME}/../../aid-gate-name-lint.sh"
  TMP="$(mktemp -d)"
  ALLOW="$TMP/allow.txt"
  : > "$ALLOW"
}

teardown() { rm -rf "$TMP"; }

# Writes a config with a single gate: $1 = name, $2 = command
_cfg() {
  cat > "$TMP/execution.yaml" <<EOF
gates:
  $1:
    command: "$2"
    required: false
EOF
  printf '%s' "$TMP/execution.yaml"
}

_run_lint() {
  AID_GATE_NAME_ALLOWLIST="$ALLOW" bash "$LINT" --config "$1"
}

@test "a compliant name passes" {
  cfg="$(_cfg tests_merge_path 'run-all-tests.sh --tier t0')"
  run _run_lint "$cfg"
  [ "$status" -eq 0 ]
}

@test "a tool name in the gate is refused" {
  cfg="$(_cfg bats_fsm 'bats test-aid-fsm.bats')"
  run _run_lint "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nastroje"* ]]
}

@test "a totality word is refused when the command only runs a subset" {
  cfg="$(_cfg tests_all 'run-all-tests.sh --tier t0')"
  run _run_lint "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uplnosti"* ]]
}

@test "a totality word is ALLOWED when the command really runs everything" {
  cfg="$(_cfg tests_full_portfolio 'run-all-tests.sh --include-delegated')"
  run _run_lint "$cfg"
  [ "$status" -eq 0 ]
}

@test "an outcome word is refused" {
  cfg="$(_cfg tests_pass 'run-all-tests.sh --include-delegated')"
  run _run_lint "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vysledku"* ]]
}

@test "a missing kind prefix is refused" {
  cfg="$(_cfg plan_diff 'aid-plan-diff.sh --plan x')"
  run _run_lint "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"druhem"* ]]
}

@test "an allowlisted name is advisory, not a failure" {
  cfg="$(_cfg bats_all 'run-all-tests.sh --tier t0')"
  echo "bats_all" > "$ALLOW"
  run _run_lint "$cfg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADVISORY"* ]]
}

@test "--strict turns a grandfathered name into a failure" {
  cfg="$(_cfg bats_all 'run-all-tests.sh --tier t0')"
  echo "bats_all" > "$ALLOW"
  run env AID_GATE_NAME_ALLOWLIST="$ALLOW" bash "$LINT" --config "$cfg" --strict
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
}

@test "a missing allowlist means NO exceptions, never allow-everything" {
  cfg="$(_cfg bats_all 'run-all-tests.sh --tier t0')"
  run env AID_GATE_NAME_ALLOWLIST="$TMP/does-not-exist.txt" bash "$LINT" --config "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
}

@test "the repository's own two configs lint clean today" {
  root="${BATS_TEST_DIRNAME}/../../../../.."
  run bash "$LINT" --config "$root/.aid-o/config/execution.yaml"
  [ "$status" -eq 0 ]
  run bash "$LINT" --config "$root/plugins/aid-orchestrator/defaults/execution.yaml"
  [ "$status" -eq 0 ]
}
