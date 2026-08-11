#!/usr/bin/env bats
# aid-tier: t2
# test-run-mode-field.bats — P076 Step 1: the `run_mode` configuration field.
#
# Step 1 creates the LANDING FIELD only. The runner-side read/validation lives
# in Step 2 (aid-run-gates.sh); this suite therefore asserts the FIELD contract
# at the configuration layer:
#
#   1. A gate that omits `run_mode` resolves to foreground (the unchanged
#      default — a consumer config that predates the field behaves identically).
#   2. Explicit `foreground` and explicit `background` both parse to themselves.
#   3. An invalid value fails LOUDLY, naming the gate and BOTH accepted forms —
#      never a silent foreground fallback that would mask a typo (`backgroud`).
#   4. The shipped template documents the key, and ZERO template gates set it
#      (nothing auto-flips for consumer projects).
#
# Deliberate design note for Step 2: the resolver and the validator are
# indirected through resolve_run_mode()/validate_run_mode() below. When Step 2
# lands the real implementation in aid-run-gates.sh, these two helpers are
# repointed at the runner and every case survives unchanged.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  TEMPLATE="$PLUGIN_ROOT/defaults/execution.yaml"
  export TEMPLATE
  WORK="$(mktemp -d)"
  export WORK
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# resolve_run_mode <yaml_file> <gate_name>
#   The exact resolver expression Step 2 wires into aid-run-gates.sh:
#   absent/null -> "foreground".
resolve_run_mode() {
  local file="$1" gate="$2"
  yq ".gates.\"${gate}\".run_mode // \"foreground\"" "$file"
}

# validate_run_mode <yaml_file> <gate_name>
#   Mirrors the accepted-values rule Step 2 enforces BEFORE any command is
#   spawned. Prints the resolved value on success; on failure prints an error
#   naming the gate, the offending value and both accepted forms, exit 1.
validate_run_mode() {
  local file="$1" gate="$2" mode
  mode="$(resolve_run_mode "$file" "$gate")"
  case "$mode" in
    foreground|background)
      printf '%s\n' "$mode"
      return 0
      ;;
    *)
      printf 'ERROR: gate %s has invalid run_mode: %s (accepted values: foreground, background)\n' \
        "$gate" "$mode" >&2
      return 1
      ;;
  esac
}

write_fixture() {
  cat >"$WORK/execution.yaml" <<'YAML'
gates:
  no_key_gate:
    command: "true"
    timeout_seconds: 60
  explicit_fg_gate:
    command: "true"
    run_mode: foreground
  explicit_bg_gate:
    command: "true"
    run_mode: background
  typo_gate:
    command: "true"
    run_mode: backgroud
YAML
}

@test "case 1: a gate without run_mode resolves to foreground (unchanged default)" {
  write_fixture
  run resolve_run_mode "$WORK/execution.yaml" no_key_gate
  [ "$status" -eq 0 ]
  [ "$output" = "foreground" ]

  # And it validates cleanly — an absent key is legal, not an error.
  run validate_run_mode "$WORK/execution.yaml" no_key_gate
  [ "$status" -eq 0 ]
  [ "$output" = "foreground" ]
}

@test "case 2: explicit foreground and explicit background both parse to themselves" {
  write_fixture

  run validate_run_mode "$WORK/execution.yaml" explicit_fg_gate
  [ "$status" -eq 0 ]
  [ "$output" = "foreground" ]

  run validate_run_mode "$WORK/execution.yaml" explicit_bg_gate
  [ "$status" -eq 0 ]
  [ "$output" = "background" ]
}

@test "case 3: an invalid run_mode fails loudly naming the gate and both accepted forms" {
  write_fixture

  run validate_run_mode "$WORK/execution.yaml" typo_gate
  [ "$status" -ne 0 ]
  # Never silently degraded to the default.
  [[ "$output" != "foreground" ]]
  # The failure names the gate, the offending value, and BOTH accepted forms.
  [[ "$output" == *"typo_gate"* ]]
  [[ "$output" == *"backgroud"* ]]
  [[ "$output" == *"foreground"* ]]
  [[ "$output" == *"background"* ]]
}

@test "case 4: shipped template documents run_mode and zero template gates set it" {
  [ -f "$TEMPLATE" ]

  # (a) The documentation block is present and shows both values plus the
  #     crash-re-attach behaviour and the advisory event cross-reference.
  run grep -c 'run_mode' "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  grep -q 'run_mode: foreground|background' "$TEMPLATE"
  grep -q 'default: foreground' "$TEMPLATE"
  grep -q 'aid-job.sh' "$TEMPLATE"
  grep -q 'RE-ATTACH' "$TEMPLATE"
  grep -q 'gate_run_mode_advice' "$TEMPLATE"

  # (b) Every mention of run_mode in the template is a COMMENT line — no
  #     template gate sets the key, so nothing auto-flips for a consumer.
  run bash -c "grep -n 'run_mode' '$TEMPLATE' | grep -v '^[0-9]*:[[:space:]]*#' || true"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # (c) Structural proof via yq: no gate in the template has run_mode set.
  run yq -r '[.gates[] | select(has("run_mode"))] | length' "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # (d) And the template still parses as valid YAML with its gates intact.
  run yq -r '.gates | keys | length' "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}
