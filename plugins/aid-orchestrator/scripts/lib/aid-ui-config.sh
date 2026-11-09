#!/usr/bin/env bash
# aid-ui-config.sh — the `ui` keys of project.yaml the companion kit needs (scripts/aid-companion.sh),
# detected from the repository so /aid-init PROPOSES them (written only on the PM's yes).
#
#   aid_ui_config_detect <project_root>   prints a `ui:` YAML block, or a comment why there is none
#
# Vite (vite.config.*) and Next (next.config.*) are recognised; the components directory is the first of
# src/components/{shared,ui} or src/components that exists; api_prefix is proposed only when the sources
# call a path under /api/. Anything not found is left out with a comment, never guessed.
#
#   aid_ui_live_detect <project_root> <ui_dir>   prints `ui:` with only `live:` (3.18.1) — for a project whose ui.dir
#                                                is already set (/aid-init on an existing project), never re-detected
#
# ui.live (the live preview, 3.17.0) is proposed from the address the app's OWN server forwards its API to: a Vite
# `server.proxy` `target:` or a Next `rewrites` `destination:` written as `process.env.X ?? '<url>'` (or `||`). Only
# that shape: the browser of the live copy may reach its own origin only (CSP connect-src 'self'), so an API the
# page calls directly could not work anyway. The default URL is proposed only when it resolves from this host and
# carries no credentials and no query; allowed_api = the addresses it resolves to (IPv6 in brackets, as the kit reads them). Otherwise a comment with the
# variable for the PM to give the dev API's address — never a guessed address. Written only on the PM's yes.

aid_ui_config_detect() {
  local root="${1:?aid_ui_config_detect: project root required}" cfg dir rel kind="" comp="" c api=""
  cfg="$(cd "$root" && find . -maxdepth 3 \( -name node_modules -o -name .git -o -name .aid-worktrees \) -prune -o \
          \( -name 'vite.config.*' -o -name 'next.config.*' \) -type f -print 2>/dev/null | sort | head -1)"
  if [[ -z "$cfg" ]]; then
    echo "# ui: no vite.config.* or next.config.* found — the companion kit needs ui.dir and ui.dev_cmd by hand (skills/visual-companion/SKILL.md)"
    return 0
  fi
  dir="$(dirname "${cfg#./}")"; [[ "$dir" == "." ]] && rel="." || rel="$dir"
  [[ "$(basename "$cfg")" == vite.config.* ]] && kind=vite || kind=next
  for c in src/components/shared src/components/ui src/components; do
    [[ -d "$root/$rel/$c" ]] && { comp="$c"; break; }
  done
  grep -rqsE "['\"\`]/api/" "$root/$rel/src" 2>/dev/null && api="/api/"
  echo "ui:"
  echo "  dir: ${rel}"
  if [[ -n "$comp" ]]; then echo "  components: ${rel%/.}/${comp}" | sed 's|^  components: \./|  components: |'
  else echo "  # components: <the directory of the shared components> — none of src/components/{shared,ui} exists"; fi
  if [[ "$kind" == vite ]]; then echo '  dev_cmd: ["npx", "vite", "--port", "{port}", "--host", "127.0.0.1", "--strictPort"]'
  else echo '  dev_cmd: ["npx", "next", "dev", "-p", "{port}", "-H", "127.0.0.1"]'; fi
  echo "  ready_path: /"
  if [[ -n "$api" ]]; then echo "  api_prefix: ${api}"
  else echo "  # api_prefix: <the path prefix of the app's API calls> — no call under /api/ found in ${rel}/src"; fi
  _aid_ui_live_lines "$root" "$rel"
}

aid_ui_live_detect() {
  local root="${1:?aid_ui_live_detect: project root required}" dir="${2:?aid_ui_live_detect: ui.dir required}"
  echo "ui:"; _aid_ui_live_lines "$root" "$dir"
}

# the `  live:` lines under ui: (or one comment line why not)
_aid_ui_live_lines() {
  local root="$1" dir="$2" cfgs=() f cands n var url host ips a
  for f in "$root/$dir"/vite.config.* "$root/$dir"/next.config.*; do [[ -f "$f" ]] && cfgs+=("$f"); done
  # only a config that has a proxy (Vite server.proxy) or rewrites (Next); comment lines are not code
  # ponytail: a text match, not a parse — a target: in an unrelated object of the same config is still a candidate;
  # the PM confirms the address before it is written
  cands=""
  if (( ${#cfgs[@]} )) && grep -qE '(proxy|rewrites)' "${cfgs[@]}"; then
    cands="$(grep -vhE '^[[:space:]]*(//|\*|/\*)' "${cfgs[@]}" \
      | { grep -oE "(target|destination)[\"']?[[:space:]]*:[[:space:]]*process\.env\.[A-Za-z_][A-Za-z0-9_]*([[:space:]]*(\?\?|\|\|)[[:space:]]*['\"\`][^'\"\`]*['\"\`])?" || true; } \
      | sed -E "s/^.*process\.env\.([A-Za-z_][A-Za-z0-9_]*)([^'\"\`]*['\"\`]([^'\"\`]*))?.*$/\1 \3/" | sort -u)"
  fi
  n="$(grep -c . <<< "$cands" || true)"
  if [[ "$n" -eq 0 ]]; then
    echo "  # live: <the live preview> — ${dir} forwards no API from process.env — the live copy is pointed at the dev API only through a variable: the proxy target as process.env.X ?? '<url>' in the app, then ui.live (skills/visual-companion/SKILL.md)"; return 0
  fi
  if [[ "$(cut -d' ' -f1 <<< "$cands" | sort -u | grep -c .)" -gt 1 ]]; then
    echo "  # live: <the live preview> — ${dir} forwards its API from several variables ($(cut -d' ' -f1 <<< "$cands" | sort -u | paste -sd, -)); ask the PM which one is the dev API and its address"; return 0
  fi
  read -r var url <<< "$(head -1 <<< "$cands")"
  if [[ "$var" =~ (KEY|TOKEN|SECRET|PASS|CREDENTIAL|AUTH) ]]; then
    echo "  # live: <the live preview> — the API variable ${var} looks like a secret; the live copy takes none (declare ui.live by hand)"; return 0
  fi
  # the URL as the kit reads it (node's URL, kit-proto.mjs liveEnv): one whole http/ws URL, no user:password@,
  # no ?query or #fragment; the host normalised (127.1 → 127.0.0.1) so the allowlist matches what the kit resolves
  host=""
  [[ -n "$url" ]] && host="$(AID_U="$url" node -e 'try { const u = new URL(process.env.AID_U);
    if (/^(https?|wss?):$/.test(u.protocol) && !u.username && !u.password && !u.search && !u.hash && !/\s/.test(process.env.AID_U))
      console.log(u.hostname.replace(/^\[|\]$/g, "")) } catch {}' 2>/dev/null || true)"
  if [[ -z "$host" ]]; then
    echo "  # live: <the live preview> — ${dir} reads its API from ${var}; ask the PM for the DEV API's address (env: {${var}: http://<host>:<port>}, allowed_api: [<host>])"; return 0
  fi
  if [[ "$host" =~ ^[0-9.]+$ || "$host" == *:* ]]; then ips="$host"
  else ips="$(timeout 3 getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd' ' - || true)"; fi
  if [[ -z "$ips" ]]; then
    echo "  # live: <the live preview> — ${var} defaults to ${url}, which does not resolve from this host (a container name?); ask the PM for the DEV API's address (env: {${var}: http://<host>:<port>}, allowed_api: [<host>])"; return 0
  fi
  echo "  live:                        # the live preview: the copy against the DEV API — confirm ${url} IS the dev API before yes"
  echo "    env:"
  echo "      ${var}: ${url}"
  printf '    allowed_api: [%s]\n' "$(for a in $ips; do [[ "$a" == *:* ]] && a="[$a]"; printf '"%s", ' "$a"; done | sed 's/, $//')"
}
