#!/usr/bin/env bats
# aid-tier: t0
# test-aid-config-summary.bats — scripts/aid-config-summary.sh, the shared
# read-only configuration summary presented by /aid-init and /aid-setup.
#
# Provenance: P080 EPIC 2 step 7.
#
# What is actually asserted here (each case can fail — the values are read from
# real fixture files, not restated constants):
#   - a fresh repo with no workspace still renders, exit 0
#   - a configured fixture renders ITS preset and ITS gate profile names
#   - the two canonical permission display strings, byte-identical to
#     commands/aid-init.md and skills/setup/permissions.md
#   - the same output from the primary checkout and from a linked worktree
#   - broken YAML is summarized, not crashed on
#   - no line ever renders an empty value
#   - the script writes NOTHING: proven by a full before/after tree snapshot
#     AND by running it against a write-protected tree

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-config-summary.sh"
  export SCRIPT
  # The resolver honours AID_PROJECT_ROOT; a value inherited from the outer
  # dogfood session would point every fixture at the real repository.
  unset AID_PROJECT_ROOT
  # setup_test_evidence_dir seeds an evidence dir; these fixtures decide their
  # own workspace shape, so start from a bare repo.
  rm -rf "$TEST_PROJECT_ROOT/.aid-o"
}

teardown() {
  [[ -n "${TEST_PROJECT_ROOT:-}" && -d "$TEST_PROJECT_ROOT" ]] && chmod -R u+w "$TEST_PROJECT_ROOT" 2>/dev/null || true
  teardown_test_evidence_dir
}

# ─── fixture helpers ─────────────────────────────────────────────────────

# write_configured_workspace — a workspace with a custom preset and two
# custom-named gate profiles, so an assertion on those names cannot pass by
# accident against the plugin defaults.
write_configured_workspace() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" <<'EOF'
gates:
  lint:
    command: "true"
gate_profiles:
  fixture_alpha:
    include: [lint]
  fixture_beta:
    include: [lint]
EOF
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml" <<'EOF'
active_preset: fixture_cautious
autonomous_mode: true
EOF
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml" <<'EOF'
default_mode: plan_branch
EOF
}

# line_for <label> — the single rendered line for a label.
line_for() {
  printf '%s\n' "$output" | grep -m1 "^$1: "
}

# tree_snapshot — path/type/size/MODE/mtime of every entry under the project root.
# Mode and mtime are in the tuple because CP2 walked a `chmod 777` past the earlier
# path/type/size version: a permission change alters nothing the old tuple recorded,
# and the file's owner may chmod even a file the write-protection case made read-only.
# mtime catches a rewrite that happens to preserve length.
tree_snapshot() {
  find "$TEST_PROJECT_ROOT" -mindepth 1 -printf '%P|%y|%s|%m|%T@\n' 2>/dev/null | sort
}

# ─── rendering ───────────────────────────────────────────────────────────

@test "fresh repo without a workspace renders workspace: absent and exits 0" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workspace: absent"* ]]
  [[ "$output" == *"gate profiles: absent"* ]]
  [[ "$output" == *"permissions: absent"* ]]
  [[ "$output" == *"plan manifests: absent"* ]]
  # No gate_profiles table anywhere -> the ceiling is refused, with the reason.
  [[ "$output" == *"plan mode default: legacy_epic_release_mode (plan_branch_unavailable: no_gate_profiles)"* ]]
}

@test "state root line points at the fixture repository root" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local expected; expected="$(cd "$TEST_PROJECT_ROOT" && pwd -P)"
  [[ "$(line_for 'state root')" == "state root: $expected" ]]
}

@test "configured fixture renders its own preset and its own gate profile names" {
  write_configured_workspace
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'workspace')" == "workspace: present" ]]
  [[ "$(line_for 'gate profiles')" == "gate profiles: fixture_alpha, fixture_beta" ]]
  [[ "$(line_for 'permissions')" == "permissions: fixture_cautious (preset) — autonomous_mode: true" ]]
  [[ "$(line_for 'plan mode default')" == "plan mode default: plan_branch (policy_default)" ]]
}

@test "canonical string when active_preset is absent from an existing permissions.yaml" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'autonomous_mode: false\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'permissions')" == "permissions: autonomous (implicit — key missing, will be written on first change)" ]]
}

@test "an empty-string active_preset renders the same canonical implicit string" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'active_preset: ""\nautonomous_mode: false\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'permissions')" == "permissions: autonomous (implicit — key missing, will be written on first change)" ]]
}

@test "a permissions.yaml without autonomous_mode still renders an explicit word" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'active_preset: fixture_cautious\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'permissions')" == "permissions: fixture_cautious (preset) — autonomous_mode: absent" ]]
}

@test "the two canonical strings are byte-identical to the documented surfaces" {
  # If either surface is reworded, this fails and forces one decision instead
  # of three drifting phrasings.
  grep -qF '`<preset> (preset) — autonomous_mode: <value>`' "$AID_PLUGIN_PATH/commands/aid-init.md"
  grep -qF '`autonomous (implicit — key missing, will be written on first change)`' "$AID_PLUGIN_PATH/commands/aid-init.md"
  grep -qF '`<preset> (preset) — autonomous_mode: <value>`' "$AID_PLUGIN_PATH/skills/setup/permissions.md"
  grep -qF '`autonomous (implicit — key missing, will be written on first change)`' "$AID_PLUGIN_PATH/skills/setup/permissions.md"
  grep -qF '${preset} (preset) — autonomous_mode: ${auto}' "$SCRIPT"
  grep -qF 'autonomous (implicit — key missing, will be written on first change)' "$SCRIPT"
  # aid-setup.md is the THIRD documented surface and was missing from this guard,
  # so a fourth phrasing could have appeared there with the suite still green —
  # which is the precise failure this case exists to prevent.
  grep -qF '`<preset> (preset) — autonomous_mode: <value>`' "$AID_PLUGIN_PATH/commands/aid-setup.md"
  grep -qF '`autonomous (implicit — key missing, will be written on first change)`' "$AID_PLUGIN_PATH/commands/aid-setup.md"
}

@test "autonomous_mode: false renders false, never 'absent'" {
  # The bug this pins: yq's `//`, like jq's, fires on false as well as null, so
  # `.autonomous_mode // ""` returned empty for a deliberate `false` and the value
  # was relabelled `absent`. `absent` is this script's own word for "key missing",
  # and the sibling canonical string tells the reader a missing key means
  # implicitly AUTONOMOUS — so a workspace that switched autonomy OFF displayed as
  # one that never set it. The safe state wearing the permissive state's face, on
  # the single line a PM reads this block for.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'active_preset: autonomous\nautonomous_mode: false\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permissions: autonomous (preset) — autonomous_mode: false"* ]]
  [[ "$output" != *"autonomous_mode: absent"* ]]
}

@test "autonomous_mode: true renders true, and a missing key still renders absent" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'active_preset: custom\nautonomous_mode: true\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run bash "$SCRIPT"
  [[ "$output" == *"permissions: custom (preset) — autonomous_mode: true"* ]]

  printf 'active_preset: custom\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run bash "$SCRIPT"
  [[ "$output" == *"permissions: custom (preset) — autonomous_mode: absent"* ]]
}

@test "the dispatch source is one the runtime actually reads" {
  # aid-fsm.sh:2423-2427 consults exactly two: the project's plugin.yaml and the
  # PLUGIN's defaults/orchestration.yaml. A workspace orchestration.yaml is read by
  # nothing, so naming it as the source would be a confident wrong answer with a
  # citation attached.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'dispatch:\n  mode: inline\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/orchestration.yaml"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *".aid-o/config/orchestration.yaml"* ]]
  [[ "$output" != *"dispatch mode: inline"* ]]
}

# ─── gate profiles / plan mode edge cases ────────────────────────────────

@test "an empty gate_profiles key renders 'none defined' and refuses the plan_branch ceiling" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'gate_profiles:\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  printf 'default_mode: plan_branch\n' > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'gate profiles')" == "gate profiles: none defined" ]]
  [[ "$(line_for 'plan mode default')" == "plan mode default: legacy_epic_release_mode (plan_branch_unavailable: no_gate_profiles)" ]]
}

@test "a completely empty execution.yaml renders 'none defined', not an empty value" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  : > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'gate profiles')" == "gate profiles: none defined" ]]
}

@test "an unknown default_mode is named rather than guessed" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'default_mode: banana\n' > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'plan mode default')" == "plan mode default: legacy_epic_release_mode (unknown_policy_default: banana)" ]]
}

@test "a v1 workspace without config/ is reported as such" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'workspace')" == "workspace: present (v1 layout — run /aid-init --upgrade)" ]]
}

@test "lifecycle manifests are counted and split by declared mode" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  printf 'plan_id: P001\nmode: plan_branch\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P001.yaml"
  printf 'plan_id: P002\nmode: plan_branch\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P002.yaml"
  printf 'plan_id: P003\nmode: legacy_epic_release_mode\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P003.yaml"
  printf 'plan_id: P004\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P004.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'plan manifests')" == "plan manifests: 4 (plan_branch: 2, legacy_epic_release_mode: 1, mode absent: 1)" ]]
}

# ─── dispatch mode ───────────────────────────────────────────────────────

@test "dispatch mode falls back to the plugin default file and names it" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local expected
  expected="$(yq -r '.dispatch.mode' "$AID_PLUGIN_PATH/defaults/orchestration.yaml")"
  [[ "$(line_for 'dispatch mode')" == "dispatch mode: $expected (source: plugin default orchestration.yaml)" ]]
}

@test "a project orchestration.yaml is IGNORED, because the runtime ignores it" {
  # This case previously asserted the opposite and locked in a wrong answer.
  # aid-fsm.sh:2423-2427 reads exactly two sources — the project's plugin.yaml and
  # the PLUGIN's defaults/orchestration.yaml. Nothing anywhere reads a workspace
  # orchestration.yaml, so reporting `inline (source: .aid-o/config/orchestration.yaml)`
  # for a project whose runtime is really running `agent_tool` was a confident wrong
  # answer with a citation attached — worse than no answer, and the exact defect
  # class the deviation it came from was meant to fix.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'dispatch:\n  mode: inline\n' > "$TEST_PROJECT_ROOT/.aid-o/config/orchestration.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'dispatch mode')" != *"inline"* ]]
  [[ "$(line_for 'dispatch mode')" != *".aid-o/config/orchestration.yaml"* ]]
}

@test "a plugin.yaml dispatch_mode override wins over orchestration.yaml" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'dispatch:\n  mode: inline\n' > "$TEST_PROJECT_ROOT/.aid-o/config/orchestration.yaml"
  printf 'plugin_path: "/nowhere"\ndispatch_mode: subagent\n' > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'dispatch mode')" == "dispatch mode: subagent (source: .aid-o/config/plugin.yaml)" ]]
}

# ─── plugin version ──────────────────────────────────────────────────────

@test "plugin version matches .claude-plugin/plugin.json" {
  local expected
  expected="$(yq -p json -o=yaml -r '.version' "$AID_PLUGIN_PATH/.claude-plugin/plugin.json")"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'plugin version')" == "plugin version: $expected" ]]
}

# ─── broken configuration ────────────────────────────────────────────────

@test "unparseable execution.yaml is summarized, not crashed on" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'gate_profiles: [oops\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'gate profiles')" == *"unparseable (.aid-o/config/execution.yaml; yq: "* ]]
}

@test "unparseable permissions.yaml is summarized, not crashed on" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'active_preset: [oops\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'permissions')" == *"unparseable (.aid-o/config/permissions.yaml; yq: "* ]]
}

@test "no rendered line ever has an empty value" {
  write_configured_workspace
  printf 'active_preset: [oops\n' > "$TEST_PROJECT_ROOT/.aid-o/config/permissions.yaml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # every line is "label: value" with a non-blank value
  run bash -c "'$SCRIPT' | grep -nE ':[[:space:]]*$' || true"
  [ -z "$output" ]
}

@test "every rendered line is a label: value pair and the label set is fixed" {
  write_configured_workspace
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local labels
  labels="$(printf '%s\n' "$output" | sed 's/:.*//' | tr '\n' '|')"
  [[ "$labels" == "state root|workspace|plan mode default|gate profiles|permissions|dispatch mode|plan manifests|plugin version|" ]]
}

# ─── invocation topology ─────────────────────────────────────────────────

@test "invocation from a linked worktree resolves to the primary checkout" {
  write_configured_workspace
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local primary_output="$output"

  git -C "$TEST_PROJECT_ROOT" add -A
  git -C "$TEST_PROJECT_ROOT" commit -q -m "fixture"
  git -C "$TEST_PROJECT_ROOT" worktree add -q "$TEST_TMPDIR/wt" -b fixture-wt
  # A divergent local copy inside the worktree must be IGNORED — the state root
  # is the primary checkout. Without this the next two assertions could pass on
  # a cwd-relative read.
  printf 'active_preset: worktree_fork\nautonomous_mode: false\n' \
    > "$TEST_TMPDIR/wt/.aid-o/config/permissions.yaml"
  cd "$TEST_TMPDIR/wt"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Same root, same everything — a worktree must not fork the report.
  [[ "$(line_for 'state root')" == "state root: $(cd "$TEST_PROJECT_ROOT" && pwd -P)" ]]
  [[ "$output" != *"worktree_fork"* ]]
  [[ "$output" == "$primary_output" ]]
}

@test "invocation from a subdirectory gives byte-identical output" {
  write_configured_workspace
  run "$SCRIPT"
  local from_root="$output"
  mkdir -p "$TEST_PROJECT_ROOT/deep/deeper"
  cd "$TEST_PROJECT_ROOT/deep/deeper"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "$from_root" ]]
}

@test "outside a git repository it exits 3 with the roots lib error text" {
  cd "$TEST_TMPDIR"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not inside a git repository — AID needs a repo root"* ]]
}

@test "an unknown argument is a usage error (exit 2)" {
  run "$SCRIPT" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: aid-config-summary.sh"* ]]
}

@test "--help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: aid-config-summary.sh"* ]]
}

# ─── read-only proof ─────────────────────────────────────────────────────

@test "the script changes nothing under the project root (full tree snapshot)" {
  write_configured_workspace
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  printf 'plan_id: P001\nmode: plan_branch\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P001.yaml"
  local before after
  before="$(tree_snapshot)"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  after="$(tree_snapshot)"
  [[ "$before" == "$after" ]]
}

@test "the script renders normally against a write-protected tree" {
  write_configured_workspace
  chmod -R a-w "$TEST_PROJECT_ROOT/.aid-o"
  run "$SCRIPT"
  chmod -R u+w "$TEST_PROJECT_ROOT/.aid-o"
  [ "$status" -eq 0 ]
  [[ "$(line_for 'permissions')" == "permissions: fixture_cautious (preset) — autonomous_mode: true" ]]
}

@test "the script leaves no temp files behind in TMPDIR" {
  write_configured_workspace
  local tmp="$TEST_TMPDIR/scratch"
  mkdir -p "$tmp"
  TMPDIR="$tmp" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$tmp")" ]
}

@test "the source carries no write operation" {
  # Comment lines are stripped first: the header DESCRIBES the forbidden
  # constructs, and a checker fooled by its own documentation is worthless.
  local code="$TEST_TMPDIR/code.sh"
  grep -v '^[[:space:]]*#' "$SCRIPT" > "$code"

  # Categorical writers: none of these may appear at all.
  #
  # `--inplace` and `--in-place` are listed beside `-i`: CP2 got a real write past
  # the earlier pattern using yq's long form, which `yq +-i` does not match. A
  # checker that only knows the short spelling of a flag checks the spelling, not
  # the behaviour.
  #
  # `chmod`/`chown` are here because the tree snapshot cannot see them: it records
  # `%P|%y|%s` — path, type, size — so a permission change is invisible to it, and
  # the owner may chmod even a file made read-only by the write-protection case.
  # That combination let a `chmod 777` slip through all four mechanisms.
  run grep -nE '>>|yq +-i|yq +--in-?place|sed +-i|\btee\b|\bmktemp\b|\bmkdir\b|\btouch\b|\brm\b|\bcp\b|\bmv\b|\bchmod\b|\bchown\b|\bln\b|\bdd\b|\btruncate\b' "$code"
  [ "$status" -ne 0 ]

  # Every remaining redirection must target /dev/null or an existing fd —
  # a redirection to a PATH would be a write, however it is spelled.
  # Trailing shell punctuation (`)`, `;`, quotes) is not part of the target.
  run bash -c "grep -oE '[0-9]?>[^ ]*' '$code' | grep -vE '^[0-9]?>(/dev/null|&1|&2)[);\"'\\''|]*\$' || true"
  [ -z "$output" ]
}
