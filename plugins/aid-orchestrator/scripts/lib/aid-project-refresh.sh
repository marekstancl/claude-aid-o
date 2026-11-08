#!/usr/bin/env bash
# =============================================================================
# lib/aid-project-refresh.sh — a project runs the plugin's CURRENT git hooks and plugin path
#
#   aid_hooks_refresh <repo>             replace the AID block of pre-commit / pre-push when it is older
#   aid_plugin_path_refresh <state root> point .aid-o/config/plugin.yaml at the installed plugin
#
# WHY (3.16.0, rozbor plugin issues 8. 11. 2026): /aid-init installs the hooks once and nothing updates them.
# All five projects ran hooks from July-October; the trailing-slash fix of 3.9.1 never reached any of them.
# plugin.yaml pins a cache path; aidlab-apps and agents pointed at versions no longer on disk, silently — such a
# path moves to the installed plugin, an existing pin stays.
#
# Rules: only the installed plugin (a cache path, never a development AID_PLUGIN_PATH) refreshes; a block of a
# newer version is never lowered; only the block between the markers changes, the rest of the hook and its mode
# stay; a hook without the block is left alone (warning). Every change is one stderr line. Called by plan-start and
# plan-run (aid-plan-fsm.sh) when they create a working copy, in the plan's repository and each foreign one.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_PROJECT_REFRESH_SH_LOADED:-}" ]] && return 0
_AID_PROJECT_REFRESH_SH_LOADED=1
_AID_PRF_PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${_AID_PRF_PLUGIN}/scripts/lib/aid-plugin-version.sh"

# _aid_prf_installed_path — the installed plugin's directory (installed_plugins.json), or nothing.
_aid_prf_installed_path() {
  local f="${AID_INSTALLED_PLUGINS_JSON:-${HOME}/.claude/plugins/installed_plugins.json}"
  jq -r '(.plugins["aid-orchestrator@claude-aid-o"] // []) as $i
         | (($i | map(select(.scope == "user")) | .[0]) // $i[0] // {}) | .installPath // empty' "$f" 2>/dev/null
}

# _aid_prf_is_installed — 0 when this code runs from the installed plugin (a test points AID_INSTALLED_PLUGINS_JSON
# at its own record; there is no switch around this check).
_aid_prf_is_installed() {
  local p; p="$(_aid_prf_installed_path)"
  [[ -n "$p" && "$(realpath -m -- "$p")" == "$(realpath -m -- "$_AID_PRF_PLUGIN")" ]]
}

# _aid_prf_ver_lt <a> <b> — 0 when version a < b.
_aid_prf_ver_lt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

# _aid_prf_block <file> <start> <end> — the lines from start to end marker, inclusive.
_aid_prf_block() { awk -v s="$2" -v e="$3" 'index($0, s) { on = 1 } on { print } on && index($0, e) { exit }' "$1"; }

aid_hooks_refresh() {
  local repo="$1" hooks ver; hooks="$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" || return 0
  _aid_prf_is_installed || return 0
  ver="$(aid_plugin_version_loaded)"; [[ -n "$ver" ]] || return 0
  local pair name start end hook src want have hver tmp
  for pair in "pre-commit AID-ORCHESTRATOR-HOOK-START AID-ORCHESTRATOR-HOOK-END" \
              "pre-push AID-ORCHESTRATOR-PREPUSH-START AID-ORCHESTRATOR-PREPUSH-END"; do
    read -r name start end <<< "$pair"
    hook="${hooks}/${name}"; src="${_AID_PRF_PLUGIN}/defaults/hooks/${name}"
    [[ -f "$hook" && -f "$src" ]] || continue
    # a hook the repository tracks (core.hooksPath into the tree) or a link to a shared script is not ours to rewrite
    if [[ -L "$hook" ]] || git -C "$repo" ls-files --error-unmatch -- "$hook" >/dev/null 2>&1; then
      echo "WARNING: ${hook} is a symlink or a file the repository tracks — AID does not rewrite it; update its AID block by hand from ${src}" >&2
      continue
    fi
    if grep -qF "$start" "$hook" && [[ "$(grep -cF "$start" "$hook")" != 1 || "$(grep -cF "$end" "$hook")" != 1 ]] \
       || { grep -qF "$start" "$hook" && ! awk -v s="$start" -v e="$end" 'index($0, s) { a = NR } index($0, e) { b = NR } END { exit !(a && b > a) }' "$hook"; }; then
      echo "WARNING: ${hook} does not have exactly one AID block (one start marker, one end marker after it) — not refreshed; run /aid-init" >&2
      continue
    fi
    if ! grep -qF "$start" "$hook"; then
      grep -q 'aid-orchestrator\|AID HOOK' "$hook" 2>/dev/null \
        && echo "WARNING: ${hook} is an AID hook without its block markers — not refreshed; run /aid-init to replace it" >&2
      continue
    fi
    # the plugin's block with its version line right after the start marker
    want="$(_aid_prf_block "$src" "$start" "$end" | awk -v v="# aid-hook-version: ${ver}" 'NR == 1 { print; print v; next } { print }')"
    have="$(_aid_prf_block "$hook" "$start" "$end")"
    [[ "$have" == "$want" ]] && continue
    hver="$(sed -n 's/^# aid-hook-version: //p' <<< "$have" | head -1)"
    if [[ -n "$hver" ]] && ! _aid_prf_ver_lt "$hver" "$ver"; then continue; fi   # never lowered, never rewritten at the same version
    tmp="$(mktemp "${hook}.XXXXXX")" || continue
    WANT="$want" awk -v s="$start" -v e="$end" '
      index($0, s) && !done { print ENVIRON["WANT"]; skip = 1; next }
      skip { if (index($0, e)) { skip = 0; done = 1 } ; next }
      { print }' "$hook" > "$tmp" \
      && chmod --reference="$hook" "$tmp" 2>/dev/null && mv -f "$tmp" "$hook" \
      || { rm -f "$tmp"; echo "WARNING: could not refresh ${hook}" >&2; continue; }
    echo "AID: ${hook} refreshed to the plugin's ${ver} block (was ${hver:-older, unversioned}); runs of this repository commit under it from now on" >&2
  done
  return 0
}

aid_plugin_path_refresh() {
  local root="$1" f cur want; f="${root}/.aid-o/config/plugin.yaml"
  [[ -f "$f" ]] || return 0
  want="$(_aid_prf_installed_path)"; [[ -n "$want" && -d "$want" ]] || return 0
  cur="$(yq -r '.plugin_path // ""' "$f" 2>/dev/null)"
  [[ "$cur" == "$want" ]] && return 0
  # a pinned path that still exists stays (a deliberate pin, a testbed comparing versions): only a gone one moves
  [[ -n "$cur" && -d "$cur" ]] && return 0
  WANT="$want" yq -i '.plugin_path = strenv(WANT)' "$f" 2>/dev/null || { echo "WARNING: could not update ${f}" >&2; return 0; }
  echo "AID: ${f} plugin_path ${cur:-<none>}$( [[ -n "$cur" && ! -d "$cur" ]] && echo ' (not on disk)') → ${want} (the installed plugin)" >&2
}
