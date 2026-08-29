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
#       fragments under defaults/execution-stacks/<stack>.yaml. Also emits a
#       generic `gate_profile_defaults`/`gate_profiles` block (P061 E1 Step 5)
#       derived ONLY from gate names each stack fragment actually defines —
#       never references self-host names like bats_fsm/bats_all (D3 isolation).
#
#   render_gate_profiles_block [stack ...]
#       P061 E1 Step 6: echo JUST the `gate_profile_defaults`/`gate_profiles`
#       YAML block (or its "no stacks detected" comment fallback) for the
#       given stacks — the same derivation compose_execution_yaml uses
#       internally, factored out so the existing-project upgrade path (below)
#       and the fresh-init path can never drift from each other.
#
#   execution_yaml_has_gate_profiles <file>
#       P061 E1 Step 6: exit 0 iff <file> already has BOTH top-level
#       `gate_profile_defaults` and `gate_profiles` keys; exit 1 otherwise
#       (including when <file> does not exist). Read-only — makes no changes.
#
#   append_gate_profiles_block <file> <block_text>
#       P061 E1 Step 6 (D9 — non-destructive existing-project upgrade): append
#       a blank line + <block_text> to the END of <file> in pure append mode
#       (`>>`, never a read-parse-rewrite). Every byte already in <file> —
#       including hand-edited `gates:` `command:` values — is left untouched;
#       this is what makes the upgrade byte-preserving by construction rather
#       than by a promise about a round-trip YAML rewrite.
#
#   render_targeted_tests_gate_block
#       Renders the `targeted_tests:` gate entry (2-space indented, meant to
#       be embedded inside an existing `gates:` mapping). P069 Step 12
#       originally paired this with a test_audit.scheduler block; P078
#       removed the scheduler (parallelism cancelled by PM 2026-08-09) and
#       the targeted selector — which is stack-independent and has nothing
#       to do with parallel execution — stays.
render_targeted_tests_gate_block() {
  cat <<'EOF'
  targeted_tests:
    command: "{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    # exit 2 = the selector is INACTIVE in this repository (its mapping covers
    # only the plugin's own tree) — recorded as skip, never as pass. Map this
    # project's production surface before trusting this gate.
    pass_criteria: "exit code 0; exit 2 = no test mapping for this repository (skip)"
EOF
}
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

# stack_gate_names <frag_file>
#   P061 E1 Step 5: echo the top-level gate names (one per line, in file
#   order) a stack's execution-stacks/<stack>.yaml fragment actually defines,
#   by reading the file itself rather than hardcoding a per-stack name list.
#   This keeps the generic gate_profiles substrate self-updating if a stack
#   fragment ever adds/renames/removes a gate (GEN-007 — no ad-hoc drift).
#   Fragment shape (see defaults/execution-stacks/*.yaml):
#     gates:
#     ts_test:
#       command: "..."
#       required_when: "..."
#     ts_lint:
#       ...
#   i.e. after the first "gates:" line, gate names are the flush-left
#   "<name>:" keys (their command/required_when lines are indented).
stack_gate_names() {
  local frag_file="$1"
  [[ -f "$frag_file" ]] || return 0
  tail -n +2 "$frag_file" | grep -E '^[A-Za-z0-9_]+:' | sed 's/:.*$//'
}

# render_gate_profiles_block [stack ...]
#   P061 E1 Step 6: standalone version of the gate_profiles derivation that
#   used to live inline in compose_execution_yaml (P061 E1 Step 5). Echoes
#   either the "no stacks detected" comment line, or the full
#   `gate_profile_defaults:` + `gate_profiles:` YAML block, to stdout.
#   compose_execution_yaml (fresh-init) and append_gate_profiles_block callers
#   (existing-project upgrade) both call this — one derivation, no drift.
render_gate_profiles_block() {
  local stacks=("$@")

  local plugin_dir
  if ! plugin_dir=$(_resolve_plugin_dir); then
    echo "[ERROR] Plugin path not resolvable. Set AID_PLUGIN_PATH or install plugin via /plugin install." >&2
    return 1
  fi
  local stacks_dir="${plugin_dir}/defaults/execution-stacks"

  local clean_stacks=() s
  for s in "${stacks[@]:-}"; do
    [[ -n "$s" ]] && clean_stacks+=("$s")
  done

  # P083 Step 7 (the second consumer): render_gate_profiles_block also feeds
  # the /aid-init EXISTING-project upgrade path (commands/aid-init.md, off-
  # limits to this step), which appends this output VERBATIM to a PM's
  # hand-authored execution.yaml whose `gates:` mapping this stack-fragment
  # derivation never wrote. Naming a gate the target file does not define is
  # a hard `exit 1` in aid-run-gates.sh. Both callers pass stacks alone, so a
  # new positional parameter would break the fixed upgrade-caller invocation
  # and the target is discovered here instead. The upgrade caller
  # (commands/aid-init.md) always runs with CWD == project root and always
  # targets the ONE conventional path, so that stays the default — but
  # compose_execution_yaml (below, in THIS file) is parameterized by an
  # arbitrary `output_file` that need not equal the CWD-relative default
  # (whole-diff Codex review finding: test-init-idempotency.sh composes into
  # an arbitrary tmpdir path while CWD is the bats runner's own directory,
  # which would have silently filtered against the wrong file — or nothing
  # at all). compose_execution_yaml sets _AID_GATE_PROFILES_TARGET_FILE to
  # its own $output_file immediately before calling this function; every
  # other caller leaves it unset and gets the CWD-relative default.
  # Keyed on a NON-EMPTY `gates:` mapping, never on the file merely existing:
  # compose_execution_yaml's fresh-init path truncates this exact path to
  # zero bytes BEFORE this function runs, so an existence-only probe would
  # see an empty file on the compose path and emit a degenerate ladder. No
  # such mapping (fresh init, or an upgrade target with no `gates:` yet) →
  # no filtering, i.e. the unfiltered stack-derived set.
  local target_file="${_AID_GATE_PROFILES_TARGET_FILE:-.aid-o/config/execution.yaml}"
  local filter_active=0 dg
  local -A defined_gates=()
  if [[ -f "$target_file" ]] && command -v yq >/dev/null 2>&1; then
    local gates_json yq_rc=0
    gates_json="$(yq -o=json '.gates // {}' "$target_file" 2>/dev/null)" || yq_rc=$?
    if (( yq_rc != 0 )); then
      # P083 Step 7 (Codex review finding): a PARSE FAILURE is not the same
      # as "no gates: mapping present" — the target file may define gates
      # perfectly well elsewhere and be broken only in an unrelated section.
      # Refusing to filter would fall back to the UNFILTERED stack-derived
      # set and risk naming a gate the (unreadable) target does not define —
      # exactly what this step exists to prevent. Fail toward the emptiest
      # safe output instead: filter_active stays 1 with an EMPTY
      # defined_gates, so every profile below ends up with no gates at all
      # rather than a possibly-wrong unfiltered list.
      echo "[WARN] ${target_file} did not parse as YAML — gate_profiles will be emitted with empty include[] rather than risk naming an undefined gate. Fix the file's YAML syntax and rerun." >&2
      filter_active=1
    else
      while IFS= read -r dg; do
        [[ -n "$dg" ]] && defined_gates["$dg"]=1
      done < <(jq -r 'keys[]?' <<<"$gates_json" 2>/dev/null)
      (( ${#defined_gates[@]} > 0 )) && filter_active=1
    fi
  fi

  local targeted_gate_names=() full_gate_names=()
  local p_stack p_frag p_names_str p_name p_first
  for p_stack in "${clean_stacks[@]:-}"; do
    p_frag="${stacks_dir}/${p_stack}.yaml"
    [[ -f "${p_frag}" ]] || continue
    p_names_str="$(stack_gate_names "${p_frag}")"
    [[ -z "${p_names_str}" ]] && continue
    p_first=1
    while IFS= read -r p_name; do
      [[ -z "${p_name}" ]] && continue
      # Filtered upgrade case: a gate the target file does not define is
      # omitted from every profile, never named-and-undefined.
      if (( filter_active == 1 )) && [[ -z "${defined_gates[${p_name}]:-}" ]]; then
        continue
      fi
      full_gate_names+=("${p_name}")
      if (( p_first == 1 )); then
        targeted_gate_names+=("${p_name}")
        p_first=0
      fi
    done <<< "${p_names_str}"
  done

  if (( ${#full_gate_names[@]} == 0 )); then
    echo "# gate_profiles: no stacks detected — add gate definitions above, then define profiles manually."
    return 0
  fi

  # P069 Step 12: targeted_tests is stack-independent (aid-select-tests.sh's
  # own routing table, not a per-stack gate) — added to the `targeted`
  # profile's include[] only, never `full` (mirrors this repo's own
  # self-host execution.yaml exception: targeted_tests is a SELECTOR that
  # only ever picks a subset of what full/release already runs
  # unconditionally, so including it there would add zero new coverage).
  # P083 Step 7: subject to the SAME filter as every other gate — the upgrade
  # flow does not add a targeted_tests definition to the hand-edited file's
  # `gates:` mapping, so naming it unfiltered would be exactly the
  # undefined-gate hazard this step closes for every other name.
  if (( filter_active == 0 )) || [[ -n "${defined_gates[targeted_tests]:-}" ]]; then
    targeted_gate_names+=("targeted_tests")
  fi

  # P083 Step 7: the full canonical ladder (quick < targeted < standard <
  # full < release, per gate_profile_rank), composed from the SAME two
  # derivations above — targeted and full are unchanged. `quick` is
  # deliberately empty (the fastest possible check: nothing beyond whatever
  # the caller runs unconditionally); `standard` and `release` reuse `full`'s
  # set rather than inventing a third gate-selection heuristic this stack
  # data cannot ground — "release includes what exists", not a fixed
  # membership distinct from `full`.
  local targeted_csv full_csv
  targeted_csv="$(IFS=', '; echo "${targeted_gate_names[*]}")"
  full_csv="$(IFS=', '; echo "${full_gate_names[*]}")"
  cat <<EOF
gate_profile_defaults:
  step: targeted
  epic: full

gate_profiles:
  quick:
    include: []
  targeted:
    include: [${targeted_csv}]
  standard:
    include: [${full_csv}]
  full:
    include: [${full_csv}]
  release:
    include: [${full_csv}]
EOF
}

# execution_yaml_has_gate_profiles <file>
#   P061 E1 Step 6: read-only check — exit 0 iff <file> already defines
#   at least ONE of the top-level `gate_profile_defaults` or `gate_profiles`
#   keys (a non-null value). Exit 1 if neither is present, or <file> is absent.
#   Option (a) / partial-key handling: if a PM has manually started
#   configuring by adding just `gate_profile_defaults` or `gate_profiles` (but
#   not both yet), we treat this as "has profiles" / no-op — the upgrade path
#   MUST NOT touch partial configurations. This prevents duplicate-key
#   shadowing (the HIGH finding from CP2 Step 6). Never writes.
execution_yaml_has_gate_profiles() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  command -v yq >/dev/null 2>&1 || {
    echo "[ERROR] yq not found — cannot inspect ${file} for gate_profiles." >&2
    return 1
  }
  local has_defaults has_profiles
  has_defaults="$(yq '.gate_profile_defaults != null' "$file" 2>/dev/null)"
  has_profiles="$(yq '.gate_profiles != null' "$file" 2>/dev/null)"
  # If EITHER key is already present, treat as "has profiles" / no-op.
  # Prevents upgrade-path from appending and shadowing a partial PM edit.
  [[ "$has_defaults" == "true" || "$has_profiles" == "true" ]]
}

# append_gate_profiles_block <file> <block_text>
#   P061 E1 Step 6 (D9): additive-only upgrade write. Appends a blank line
#   then <block_text> to the END of <file> using `>>` (pure append) — never
#   reads, parses, or rewrites any byte already in <file>. This is the
#   mechanism that makes hand-edited `gates:` `command:` values byte-identical
#   before and after the upgrade: nothing before the appended block is ever
#   touched.
append_gate_profiles_block() {
  local file="$1"
  local block_text="$2"
  [[ -f "$file" ]] || {
    echo "[ERROR] ${file} does not exist — nothing to append the gate_profiles block to." >&2
    return 1
  }
  [[ -n "$block_text" ]] || {
    echo "[ERROR] Empty block_text passed to append_gate_profiles_block — refusing to append nothing." >&2
    return 1
  }
  {
    echo ""
    printf '%s\n' "$block_text"
  } >> "$file"
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

    # P069 Step 12: stack-independent targeted_tests gate — added
    # unconditionally (including the zero-detected-stacks case above), since
    # aid-select-tests.sh's own routing table is independent of any detected
    # language stack.
    echo "  # === Targeted test selector (P069 Step 12) ==="
    render_targeted_tests_gate_block

    # P061 E1 Step 5/6: generic gate_profiles substrate — only gate names the
    # stacks above actually defined go into include[]; empty when no stack
    # matched (nothing to profile yet). Delegated to render_gate_profiles_block
    # (P061 E1 Step 6) so the fresh-init path here and the existing-project
    # upgrade path (append_gate_profiles_block callers) share one derivation.
    echo ""
    # P083 Step 7: point the target-file discovery at THIS call's actual
    # output_file, not the CWD-relative default — output_file need not be
    # `.aid-o/config/execution.yaml` relative to CWD (e.g. tests composing
    # into an arbitrary tmpdir path).
    _AID_GATE_PROFILES_TARGET_FILE="$output_file" render_gate_profiles_block "${clean_stacks[@]:-}"

    cat <<'EOF'
notifications:
  telegram:
    enabled: false               # default off; set true after svc-mcp-tg-bot deployed
    chat_id: null                # null → use TELEGRAM_ALERT_DEFAULT_CHAT_ID from server env
    alert_on_repeated_precondition_fail: true
    alert_on_compliance_recovery: true  # P042: emit ✅ recovery alert when a previously-blocked EPIC clears
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

export -f detect_stacks compose_execution_yaml resolve_cp4_production_paths \
  stack_gate_names render_gate_profiles_block execution_yaml_has_gate_profiles \
  append_gate_profiles_block render_targeted_tests_gate_block
