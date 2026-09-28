#!/usr/bin/env bash
# =============================================================================
# lib/aid-plugin-version.sh — is this session running the installed AID?
#
#   aid_plugin_version_loaded      the version of the plugin this code runs from
#   aid_plugin_version_installed   the version installed_plugins.json records
#   aid_plugin_version_notice_handler  SessionStart / UserPromptSubmit handler
#
# WHY: a session keeps the plugin it loaded at its start — its hooks, its agent
# cards — while the marketplace installs a newer one underneath it. P103 (28. 9.
# 2026) ran 2.108.0 agent cards while 2.109.0 was installed, so its fixer never
# got the "fix the class" rule and every review round found a sibling hole. The
# hooks run from the LOADED plugin, so comparing their own version with the
# installed one tells the controller exactly when to run /reload-plugins.
#
# A notice, never a refusal; silent when the versions agree or cannot be read.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_PLUGIN_VERSION_SH_LOADED:-}" ]] && return 0
_AID_PLUGIN_VERSION_SH_LOADED=1
_AID_PV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aid_plugin_version_loaded() {
  jq -r '.version // empty' "${_AID_PV_LIB_DIR}/../../.claude-plugin/plugin.json" 2>/dev/null
}

# The user-scope installation is the one sessions load; a project-scope one is
# taken only when no user-scope record exists.
aid_plugin_version_installed() {
  local f="${AID_INSTALLED_PLUGINS_JSON:-${HOME}/.claude/plugins/installed_plugins.json}"
  jq -r '(.plugins["aid-orchestrator@claude-aid-o"] // []) as $i
         | (($i | map(select(.scope == "user")) | .[0]) // $i[0] // {}) | .version // empty' "$f" 2>/dev/null
}

aid_plugin_version_notice_handler() {
  cat >/dev/null   # the event is not needed
  local loaded installed
  loaded="$(aid_plugin_version_loaded)"; installed="$(aid_plugin_version_installed)"
  if [[ -z "$loaded" || -z "$installed" ]]; then
    echo "plugin version unreadable (loaded '${loaded}', installed '${installed}')" >&2; return 3
  fi
  if [[ "$loaded" == "$installed" ]]; then
    echo "loaded ${loaded} is the installed version" >&2; return 0
  fi
  echo "AID: this session runs plugin ${loaded}, but ${installed} is installed — its hooks and agent cards are the old ones. Run /reload-plugins before dispatching any agent."
  echo "loaded ${loaded}, installed ${installed}" >&2
  return 0
}
