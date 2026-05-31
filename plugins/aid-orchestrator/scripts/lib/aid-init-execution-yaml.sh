#!/usr/bin/env bash
# aid-init-execution-yaml.sh — Stack auto-detect + execution.yaml composer.
#
# Sourced by:
#   - commands/aid-init.md flow (eager generation at workspace init)
#   - scripts/aid-fsm.sh::cmd_init (auto-recovery if missing on EPIC init)
#
# Functions exported:
#   detect_stacks <project_root>
#       Echo stack names (one per line) detected by marker files.
#       Markers: pyproject.toml/requirements.txt/setup.py → python
#                package.json                              → typescript
#                go.mod                                    → go
#                Cargo.toml                                → rust
#                > 5 .sh files within depth 3              → bash
#
#   compose_execution_yaml <project_root> <output_file> [stack ...]
#       Render execution.yaml at <output_file> from per-stack template
#       fragments under defaults/execution-stacks/<stack>.yaml.
#
# Plugin path resolution order:
#   1. $AID_PLUGIN_PATH env var (worktree dev workflow)
#   2. $HOME/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator
#   3. Self-locate via this script's BASH_SOURCE (../..)

# Self-locate so callers don't need to pass $AID_PLUGIN_PATH.
_AID_INIT_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_INIT_SELF_PLUGIN_DIR="$(cd "${_AID_INIT_HELPER_DIR}/../.." && pwd)"

_resolve_plugin_dir() {
  if [[ -n "${AID_PLUGIN_PATH:-}" && -d "${AID_PLUGIN_PATH}/defaults/execution-stacks" ]]; then
    echo "${AID_PLUGIN_PATH}"
    return 0
  fi
  local fallback="${HOME}/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator"
  if [[ -d "${fallback}/defaults/execution-stacks" ]]; then
    echo "${fallback}"
    return 0
  fi
  if [[ -d "${_AID_INIT_SELF_PLUGIN_DIR}/defaults/execution-stacks" ]]; then
    echo "${_AID_INIT_SELF_PLUGIN_DIR}"
    return 0
  fi
  return 1
}

detect_stacks() {
  local project_root="$1"
  local stacks=()

  if [[ -f "${project_root}/pyproject.toml" \
     || -f "${project_root}/requirements.txt" \
     || -f "${project_root}/setup.py" ]]; then
    stacks+=("python")
  fi
  if [[ -f "${project_root}/package.json" ]]; then
    stacks+=("typescript")
  fi
  if [[ -f "${project_root}/go.mod" ]]; then
    stacks+=("go")
  fi
  if [[ -f "${project_root}/Cargo.toml" ]]; then
    stacks+=("rust")
  fi

  # Bash threshold: > 5 shell scripts within depth 3 (excludes utility/tooling noise).
  local sh_count
  sh_count=$(find "${project_root}" -maxdepth 3 -name "*.sh" \
               -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
  if (( sh_count > 5 )); then
    stacks+=("bash")
  fi

  # Avoid `printf '%s\n'` with empty array — it would emit a single newline,
  # which `mapfile -t` consumes as a 1-element array containing "".
  if (( ${#stacks[@]} > 0 )); then
    printf '%s\n' "${stacks[@]}"
  fi
}

# resolve_cp4_production_paths <project_root> [stack ...]
#   P040 Component C: derive a project-specific production-code path glob from
#   detected stack signatures. Pipe-separated regex alternation, matched as a
#   left-anchored prefix against `git diff --name-only` output by the FSM CP4
#   enforcement (fsm_check_cp4_curator_validation).
#
#   Layout signatures (most specific → least):
#     - AID plugin self     → plugins/|scripts/|src/|lib/|api/
#     - Payload/Next CMS     → src/apps/|src/payload\.config\.ts|src/collections/
#     - Node/TS monorepo     → apps/|services/|packages/|src/
#     - Python service       → src/|app/|api/|services/
#     - Zero match           → AID-self default + WARNING comment (caller emits)
#
#   Writes results to GLOBALS (not stdout) so the caller reads both the glob and
#   the no-match flag without a command-substitution subshell (which would drop
#   the flag): sets _CP4_GLOB to the resolved alternation and _CP4_NO_MATCH=1
#   when no signature matched, so compose_execution_yaml can emit the verify-me
#   warning comment.
resolve_cp4_production_paths() {
  local project_root="$1"; shift
  local stacks=("$@")
  _CP4_NO_MATCH=0
  _CP4_GLOB=""

  # AID plugin self — the orchestrator repo itself.
  if [[ -f "${project_root}/.claude-plugin/marketplace.json" \
     || -d "${project_root}/plugins/aid-orchestrator" ]]; then
    _CP4_GLOB="plugins/|scripts/|src/|lib/|api/"
    return 0
  fi

  # Payload/Next CMS — payload.config.ts under src/ or a collections/ dir.
  if [[ -f "${project_root}/src/payload.config.ts" \
     || -d "${project_root}/src/collections" ]]; then
    _CP4_GLOB='src/apps/|src/payload\.config\.ts|src/collections/'
    return 0
  fi

  # Node/TS monorepo — apps/ or packages/ workspace layout.
  if [[ -d "${project_root}/apps" || -d "${project_root}/packages" ]]; then
    _CP4_GLOB="apps/|services/|packages/|src/"
    return 0
  fi

  # Stack-based fallback (no special layout directory matched).
  local s
  for s in "${stacks[@]:-}"; do
    case "$s" in
      typescript) _CP4_GLOB="apps/|services/|packages/|src/"; return 0 ;;
      python)     _CP4_GLOB="src/|app/|api/|services/";       return 0 ;;
    esac
  done

  # Zero stacks / layouts matched — caller emits a verify-me warning.
  _CP4_NO_MATCH=1
  _CP4_GLOB="plugins/|scripts/|src/|lib/|api/"
  return 0
}

compose_execution_yaml() {
  local project_root="$1"
  local output_file="$2"
  shift 2
  local detected_stacks=("$@")

  local plugin_dir
  if ! plugin_dir=$(_resolve_plugin_dir); then
    echo "[ERROR] Plugin path not resolvable. Set AID_PLUGIN_PATH or install plugin via /plugin install." >&2
    return 1
  fi

  # Defensive: filter empty strings in case caller's mapfile picked up a stray
  # empty line. Recompute count from the cleaned array.
  local clean_stacks=() s
  for s in "${detected_stacks[@]:-}"; do
    [[ -n "$s" ]] && clean_stacks+=("$s")
  done

  local stacks_dir="${plugin_dir}/defaults/execution-stacks"
  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local stacks_label="${clean_stacks[*]:-none}"

  # P040 Component C: resolve project-specific production-code glob for CP4 enforcement.
  # Call directly (no command substitution) so _CP4_GLOB / _CP4_NO_MATCH globals survive.
  local _CP4_GLOB="" _CP4_NO_MATCH=0
  resolve_cp4_production_paths "$project_root" "${clean_stacks[@]:-}"
  local cp4_glob="$_CP4_GLOB"

  mkdir -p "$(dirname "${output_file}")" || {
    echo "[ERROR] Cannot create directory for ${output_file}" >&2
    return 1
  }

  {
    cat <<EOF
# AUTO-GENERATED by aid-init at ${now_iso}
# Detected stacks: ${stacks_label}
# Review and customize commands; remove sections for stacks you don't use.

version: "1.0"
generated_by: "aid-init v2.16.0"

gates:
EOF

    if (( ${#clean_stacks[@]} == 0 )); then
      echo "  # No stacks detected — add gate definitions manually."
    else
      local stack frag
      for stack in "${clean_stacks[@]}"; do
        frag="${stacks_dir}/${stack}.yaml"
        if [[ ! -f "${frag}" ]]; then
          echo "  # WARN: template missing for stack '${stack}' (looked for ${frag})"
          continue
        fi
        # Capitalize first letter for section header (e.g., "python" → "Python").
        local label="${stack^}"
        echo "  # === ${label} (auto-detected) ==="
        # Strip top-level "gates:" line, indent rest by 2 spaces.
        tail -n +2 "${frag}" | sed 's/^/  /'
        echo
      done
    fi

    cat <<'EOF'
notifications:
  telegram:
    enabled: false               # default off; set true after svc-mcp-tg-bot deployed
    chat_id: null                # null → use TELEGRAM_ALERT_DEFAULT_CHAT_ID from server env
    alert_on_repeated_precondition_fail: true
    alert_threshold: 3
EOF

    # P040 Component C: production-code path glob for CP4 enforcement trigger.
    echo ""
    echo "# P040 Component C: production-code path glob for CP4 enforcement trigger."
    echo "# Format: pipe-separated regex alternation; matched as left-anchored prefix"
    echo "# against \`git diff --name-only\` output."
    if (( ${_CP4_NO_MATCH:-0} == 1 )); then
      echo "# WARNING: stack auto-detect produced no match — verify cp4_production_paths reflects your project's production-code layout"
    fi
    echo "cp4_production_paths: \"${cp4_glob}\""
  } > "${output_file}" || {
    echo "[ERROR] Cannot write to ${output_file} — check permissions or run /aid-init first." >&2
    return 1
  }
}

export -f detect_stacks compose_execution_yaml resolve_cp4_production_paths
