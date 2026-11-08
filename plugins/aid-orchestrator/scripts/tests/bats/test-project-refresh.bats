#!/usr/bin/env bats
# aid-tier: t1
# test-project-refresh.bats — lib/aid-project-refresh.sh: a project's git hooks and plugin.yaml follow the installed
# plugin (3.16.0; all five projects ran hooks from July-October, plugin.yaml pointed at deleted versions).
# Proves: an old block is replaced and the rest of the hook kept; a newer block is never lowered; a development
# plugin changes nothing; a hook without markers is only warned about; plugin_path is moved off a missing version.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TEST_DIR="$(mktemp -d)"; R="$TEST_DIR/repo"
  git init -q -b main "$R"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-project-refresh.sh"
  VER="$(aid_plugin_version_loaded)"
  H="$R/.git/hooks"
  # an installed hook from an older plugin: a user line before the block, an older block body, a user line after it
  { echo '#!/usr/bin/env bash'; echo 'echo user-before'
    echo '# AID-ORCHESTRATOR-HOOK-START (do not edit this block manually)'; echo 'echo old-aid-body'
    echo '# AID-ORCHESTRATOR-HOOK-END'; echo 'echo user-after'; } > "$H/pre-commit"
  chmod 750 "$H/pre-commit"
  # pre-push: the block carries nested release-scope markers in the plugin's own file
  { echo '#!/usr/bin/env bash'; echo '# AID-ORCHESTRATOR-PREPUSH-START (do not edit this block manually)'; echo 'echo old'
    echo '# AID-ORCHESTRATOR-PREPUSH-END'; } > "$H/pre-push"; chmod 755 "$H/pre-push"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "hooks: an older block is replaced by the plugin's, versioned; the lines around it and the mode stay" {
  AID_REFRESH_TRUST_PLUGIN=1 run aid_hooks_refresh "$R"; echo "$output"
  [[ "$output" == *"pre-commit refreshed to the plugin's ${VER} block"* ]]
  grep -qx 'echo user-before' "$H/pre-commit" && grep -qx 'echo user-after' "$H/pre-commit"
  ! grep -q 'old-aid-body' "$H/pre-commit"
  grep -qx "# aid-hook-version: ${VER}" "$H/pre-commit"
  grep -q '_aid_path_covers' "$H/pre-commit"
  [ "$(stat -c %a "$H/pre-commit")" = 750 ]
  grep -q 'AID-RELEASE-SCOPE-PORTABLE-START' "$H/pre-push" && grep -q 'AID-RELEASE-SCOPE-PORTABLE-END' "$H/pre-push"
  [ "$(grep -c 'AID-ORCHESTRATOR-PREPUSH-END' "$H/pre-push")" = 1 ]
  # a second run changes nothing
  local before; before="$(sha256sum "$H/pre-commit")"
  AID_REFRESH_TRUST_PLUGIN=1 run aid_hooks_refresh "$R"; [ -z "$output" ]
  [ "$(sha256sum "$H/pre-commit")" = "$before" ]
}

@test "hooks: a block of a newer version is never lowered" {
  sed -i 's|^echo old-aid-body$|# aid-hook-version: 999.0.0\necho newer-body|' "$H/pre-commit"
  AID_REFRESH_TRUST_PLUGIN=1 run aid_hooks_refresh "$R"
  grep -qx 'echo newer-body' "$H/pre-commit"
}

@test "hooks: a plugin that is not the installed one (a development checkout) refreshes nothing" {
  export AID_INSTALLED_PLUGINS_JSON="$TEST_DIR/none.json"; echo '{}' > "$AID_INSTALLED_PLUGINS_JSON"
  run aid_hooks_refresh "$R"; [ -z "$output" ]
  grep -qx 'echo old-aid-body' "$H/pre-commit"
}

@test "hooks: an AID hook without its markers is warned about, not rewritten" {
  printf '#!/bin/sh\necho "AID HOOK: old style"\n' > "$H/pre-commit"
  AID_REFRESH_TRUST_PLUGIN=1 run aid_hooks_refresh "$R"
  [[ "$output" == *"without its block markers"* ]]
  grep -q 'old style' "$H/pre-commit"
}

@test "plugin.yaml: a plugin_path that is not on disk moves to the installed plugin; an existing newer pin stays" {
  mkdir -p "$R/.aid-o/config" "$TEST_DIR/cache/9.9.9/.claude-plugin"
  echo '{"version": "9.9.9"}' > "$TEST_DIR/cache/9.9.9/.claude-plugin/plugin.json"
  jq -n --arg p "$TEST_DIR/cache/9.9.9" '{plugins: {"aid-orchestrator@claude-aid-o": [{scope: "user", installPath: $p, version: "9.9.9"}]}}' > "$TEST_DIR/inst.json"
  export AID_INSTALLED_PLUGINS_JSON="$TEST_DIR/inst.json"
  printf '# a comment that stays\nplugin_path: "/gone/2.117.0"\n' > "$R/.aid-o/config/plugin.yaml"
  run aid_plugin_path_refresh "$R"; echo "$output"
  [[ "$output" == *"(not on disk)"* ]]
  [ "$(yq -r .plugin_path "$R/.aid-o/config/plugin.yaml")" = "$TEST_DIR/cache/9.9.9" ]
  grep -q 'a comment that stays' "$R/.aid-o/config/plugin.yaml"
  mkdir -p "$TEST_DIR/cache/10.0.0/.claude-plugin"; echo '{"version": "10.0.0"}' > "$TEST_DIR/cache/10.0.0/.claude-plugin/plugin.json"
  P="$TEST_DIR/cache/10.0.0" yq -i '.plugin_path = strenv(P)' "$R/.aid-o/config/plugin.yaml"
  run aid_plugin_path_refresh "$R"; [ -z "$output" ]
}
