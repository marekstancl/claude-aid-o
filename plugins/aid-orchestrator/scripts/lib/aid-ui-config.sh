#!/usr/bin/env bash
# aid-ui-config.sh — the `ui` keys of project.yaml the companion kit needs (scripts/aid-companion.sh),
# detected from the repository so /aid-init PROPOSES them (written only on the PM's yes).
#
#   aid_ui_config_detect <project_root>   prints a `ui:` YAML block, or a comment why there is none
#
# Vite (vite.config.*) and Next (next.config.*) are recognised; the components directory is the first of
# src/components/{shared,ui} or src/components that exists; api_prefix is proposed only when the sources
# call a path under /api/. Anything not found is left out with a comment, never guessed.

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
}
