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
#       generic `default_profile`/`gate_profiles` block (P061 E1 Step 5,
#       list model since P097 Step 4)
#       derived ONLY from gate names each stack fragment actually defines —
#       never references self-host names like bats_fsm/bats_all (D3 isolation).
#
#   render_gate_profiles_block [stack ...]
#       P061 E1 Step 6: echo JUST the `default_profile`/`gate_profiles`
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
#   execution_yaml_default_when_paths
#       P097 Step 3: the glob list a `full` profile's `when_paths` gets — the
#       one copy of the classifier's high-risk patterns (see the function).
#
#   execution_yaml_upgrade <path> [--confirm-upgrade <hash>] [--default-profile <name>]
#       P097 Step 3: the hash-confirmed upgrade that removes the dead keys
#       and adds `default_profile` + `when_paths`. Also the in-library main:
#       `bash …/lib/aid-init-execution-yaml.sh upgrade <project root|file> …`
#       (exit 0 nothing to do or applied, 3 diff printed, 2 bad input).
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
#   `default_profile:` + `gate_profiles:` YAML block, to stdout.
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

  # P097 Step 4: the profiles are an ORDERED list, narrowest first — the
  # declaration index is the rank (lib/aid-gate-profile-select.sh). No
  # `quick` (an empty include[] is a run that can only skip, which the
  # resolver refuses) and no `gate_profile_defaults` (dead since 2.102.0).
  # `default_profile: standard` is what an EPIC run gets when no when_paths
  # matches; `full` carries the when_paths (execution_yaml_default_when_paths,
  # the one copy of the high-risk list); `release` is the plan-final
  # boundary's explicit name and is never auto-selected, so it has none.
  # `standard`, `full` and `release` reuse the same set rather than inventing
  # a gate-selection heuristic this stack data cannot ground.
  local targeted_csv full_csv when_paths_yaml=""
  targeted_csv="$(IFS=', '; echo "${targeted_gate_names[*]}")"
  full_csv="$(IFS=', '; echo "${full_gate_names[*]}")"
  local wp
  while IFS= read -r wp; do when_paths_yaml+="      - \"${wp}\""$'\n'; done < <(execution_yaml_default_when_paths)
  cat <<EOF
# Profiles are an ordered list, narrowest first: the declaration index is the
# rank the GATES:DONE floor compares. A run gets the LAST profile whose
# when_paths matches a changed path, else default_profile.
default_profile: standard

gate_profiles:
  targeted:
    include: [${targeted_csv}]
  standard:
    include: [${full_csv}]
  full:
    include: [${full_csv}]
    when_paths:
${when_paths_yaml%$'\n'}
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

  mkdir -p "$(dirname "${output_file}")" || {
    echo "[ERROR] Cannot create directory for ${output_file}" >&2
    return 1
  }

  {
    cat <<EOF
# AUTO-GENERATED by aid-init at ${now_iso}
# Detected stacks: ${stacks_label}
# Review and customize commands; remove sections for stacks you don't use.

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
    # Alerts go through the ecosystem's shared send_alert() (lib/aid-alert.sh);
    # there is no bot to enable and no chat to pick. The one key read here:
    alert_on_compliance_recovery: true  # P042: emit ✅ recovery alert when a previously-blocked EPIC clears
EOF

  } > "${output_file}" || {
    echo "[ERROR] Cannot write to ${output_file} — check permissions or run /aid-init first." >&2
    return 1
  }
}

# ─── P097 Step 3: the configuration upgrade ─────────────────────────────────
#
# execution_yaml_default_when_paths
#   Echo the glob patterns (one per line) a `full` profile's `when_paths`
#   gets when the upgrade adds it. THE one copy of the classifier's high-risk
#   list: each `case` arm of the old classifier's gate_profile_is_high_risk_path
#   (the pre-P097 profile library, deleted by Step 9) appears here verbatim, so a path the old
#   classifier calls high-risk matches one of these through
#   _aid_ancillary_glob_match (a bash `case` glob, the same engine) and a path
#   it does not, matches none. Read by this upgrade and by the composer; the
#   resolver reads `when_paths` from the file and never needs this list.
execution_yaml_default_when_paths() {
  cat <<'EOF'
aid-fsm.sh
*/aid-fsm.sh
aid-run-gates.sh
*/aid-run-gates.sh
aid-release-policy.sh
*/aid-release-policy.sh
aid-evidence-verify.sh
*/aid-evidence-verify.sh
defaults/schemas/*
*/defaults/schemas/*
defaults/policies/*
*/defaults/policies/*
agents/*.md
*/agents/*.md
EOF
}

# Dead keys: written by earlier composers, read by nothing since 2.102.0.
# The same name is dead at the top level and inside a gate row.
_EYU_DEAD_KEY_RE='^(required_when|needs_services|services|gate_profile_defaults|baseline|baseline_[a-z0-9_]+|runtime_baseline|quarantine)$'
# Gate-row keys the composer writes (defaults/execution-stacks/*.yaml); any
# other surviving key is project-added and gets a printed note, never a removal.
_EYU_ROW_KEY_RE='^(command|required|timeout_seconds|description|pass_criteria|type|max_retries)$'

# _eyu_locate <file> <key path a.b.c>
#   Print "<key line> <block end line>" for the FIRST occurrence of a block
#   mapping key reached by the dotted path, or nothing. A key's block ends at
#   the last following non-blank line indented deeper than the key (comments
#   included); a blank line ends it. Line-based on purpose: a yq rewrite
#   reflows comments and quoting in every project file (measured: 2-252 noise
#   lines per file), and the diff must show nothing but the upgrade.
#   ponytail: block-style mappings with plain keys only — flow mappings
#   (`{a: 1}`) and quoted keys are not found; every project file uses neither.
_eyu_locate() {
  awk -v want="$2" '
    function indent(s,  m) { match(s, /^ */); return RLENGTH }
    BEGIN { n = split(want, seg, "."); depth = 1; need = 0; found = 0 }
    {
      if (found) {
        if ($0 ~ /^[ \t]*$/) { exit }
        if (indent($0) > kind) { last = NR; next }
        exit
      }
      if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) next
      ind = indent($0)
      if (depth > 1 && ind <= pind) exit
      if (depth > 1 && need < 0) need = ind
      if (ind == need && $0 ~ ("^ *" seg[depth] ":")) {
        if (depth == n) { found = 1; start = NR; kind = ind; last = NR; next }
        pind = ind; need = -1; depth++
      }
    }
    END { if (found) print start, last }
  ' "$1"
}

# execution_yaml_upgrade <path> [--confirm-upgrade <hash>] [--default-profile <name>]
#   Print the diff that removes the dead keys, drops an empty `quick`, adds
#   `default_profile` (when gate_profiles exists) and `when_paths` on `full`;
#   write it only when <hash> matches the printed one. Exit 0 nothing to do or
#   applied, 3 diff printed and not applied, 2 bad input or a choice the
#   operator must make (no profile named standard, a stale hash, a file that
#   does not parse). Never touches gates.<id>.command or a non-empty include[].
execution_yaml_upgrade() {
  local file="${1:-}"; shift || true
  local confirm="" default_profile=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm-upgrade) [[ $# -ge 2 ]] || { echo "[ERROR] --confirm-upgrade requires a value" >&2; return 2; }; confirm="$2"; shift 2 ;;
      --default-profile) [[ $# -ge 2 ]] || { echo "[ERROR] --default-profile requires a value" >&2; return 2; }; default_profile="$2"; shift 2 ;;
      *) echo "[ERROR] unknown option '$1'" >&2; return 2 ;;
    esac
  done
  [[ -f "$file" ]] || { echo "[ERROR] no execution.yaml at '${file}'" >&2; return 2; }
  command -v yq >/dev/null 2>&1 || { echo "[ERROR] yq not found" >&2; return 2; }
  local parse_err
  if ! parse_err="$(yq '.' "$file" 2>&1 >/dev/null)"; then
    echo "[ERROR] ${file} does not parse: ${parse_err}" >&2
    return 2
  fi
  if (( $(grep -c '^gates:' "$file" || true) > 1 )); then
    echo "[ERROR] ${file} has more than one top-level 'gates:' line — resolve the duplicate by hand first" >&2
    return 2
  fi

  local -a del_from=() del_to=() ins_after=() ins_text=() notes=()
  local loc key id path
  _eyu_del() {  # <key path> → queue its block for removal, if present
    loc="$(_eyu_locate "$file" "$1")"
    [[ -n "$loc" ]] || return 1
    del_from+=("${loc% *}"); del_to+=("${loc#* }")
    notes+=("- removed ${1}")
  }

  # Top-level dead keys, then the same names inside every gate row.
  while IFS= read -r key; do
    [[ "$key" =~ $_EYU_DEAD_KEY_RE ]] && { _eyu_del "$key" || true; }
  done < <(yq 'keys | .[]' "$file")
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    while IFS= read -r key; do
      if [[ "$key" =~ $_EYU_DEAD_KEY_RE ]]; then
        _eyu_del "gates.${id}.${key}" || true
        # `required_when: "<glob> exists"` was the gate's only "required" claim
        # in every generated project (every expression is static stack
        # detection, true for the project it was written for): dropping it
        # alone leaves a gate `required: false` and a profile with no required
        # gate, which the resolver refuses. Found by P097 Step 6.
        if [[ "$key" == required_when ]] \
           && [[ "$(g="$id" yq '.gates[strenv(g)] | has("required")' "$file")" == "false" ]]; then
          local rw_pad
          rw_pad="$(sed -n "${loc% *}p" "$file" | sed -E 's/^( *).*/\1/')"
          ins_after+=("${loc#* }"); ins_text+=("${rw_pad}required: true")
          notes+=("- gates.${id}: required_when replaced by required: true")
        fi
      elif [[ ! "$key" =~ $_EYU_ROW_KEY_RE ]]; then
        notes+=("- note: gates.${id}.${key} is not a key the composer writes; left in place")
      fi
    done < <(g="$id" yq '.gates[strenv(g)] | select(type == "!!map") | keys | .[]' "$file")
  done < <(yq '.gates | select(type == "!!map") | keys | .[]' "$file")

  # An empty quick profile.
  if [[ "$(yq '.gate_profiles | has("quick")' "$file")" == "true" \
     && "$(yq '.gate_profiles.quick.include // [] | length' "$file")" == "0" ]]; then
    _eyu_del "gate_profiles.quick" || true
  fi

  # notifications.telegram: every key but the one that is read.
  local -a tg_keys=() tg_dead=()
  mapfile -t tg_keys < <(yq '.notifications.telegram | select(type == "!!map") | keys | .[]' "$file")
  for key in "${tg_keys[@]}"; do
    [[ "$key" == "alert_on_compliance_recovery" ]] || tg_dead+=("$key")
  done
  if (( ${#tg_dead[@]} > 0 )); then
    if (( ${#tg_dead[@]} == ${#tg_keys[@]} )); then
      # Nothing would remain under telegram: drop the empty parents too.
      if [[ "$(yq '.notifications | keys | length' "$file")" == "1" ]]; then
        _eyu_del "notifications" || true
      else
        _eyu_del "notifications.telegram" || true
      fi
    else
      for key in "${tg_dead[@]}"; do _eyu_del "notifications.telegram.${key}" || true; done
    fi
  fi

  # default_profile and when_paths — only when a profile table exists.
  local -a profiles=()
  if [[ "$(yq '.gate_profiles | type' "$file")" == "!!map" ]]; then
    mapfile -t profiles < <(yq '.gate_profiles | keys | .[]' "$file")
    if [[ "$(yq 'has("default_profile")' "$file")" == "false" ]]; then
      local name="${default_profile:-standard}"
      if [[ ! " ${profiles[*]} " == *" ${name} "* ]]; then
        echo "[ERROR] ${file}: no profile named '${name}' to be default_profile; declared: ${profiles[*]}. Choose one and re-run with --default-profile <name>" >&2
        return 2
      fi
      loc="$(_eyu_locate "$file" "gate_profiles")"
      ins_after+=("$(( ${loc% *} - 1 ))"); ins_text+=("default_profile: ${name}")
      notes+=("- added default_profile: ${name}")
    fi
    if [[ " ${profiles[*]} " == *" full "* ]]; then
      if [[ "$(yq '.gate_profiles.full | has("when_paths")' "$file")" == "false" ]]; then
        loc="$(_eyu_locate "$file" "gate_profiles.full")"
        local pad text
        pad="$(sed -n "${loc% *}p" "$file" | sed -E 's/^( *).*/\1/')  "
        text="${pad}when_paths:"
        while IFS= read -r path; do text+=$'\n'"${pad}  - \"${path}\""; done < <(execution_yaml_default_when_paths)
        ins_after+=("${loc#* }"); ins_text+=("$text")
        notes+=("- added when_paths on gate_profiles.full (the classifier's high-risk list)")
      fi
    else
      notes+=("- note: no profile named full — no when_paths added; no profile is auto-selected until one declares when_paths")
    fi
    # Informational: declared order is the rank, narrowest first.
    local prev=-1 n order_ok=1
    for name in "${profiles[@]}"; do
      n="$(p="$name" yq '.gate_profiles[strenv(p)].include // [] | length' "$file")"
      (( n < prev )) && order_ok=0
      prev=$n
    done
    (( order_ok )) || notes+=("- note: gate_profiles are not declared narrowest-first (${profiles[*]}); the declared order is the rank — reorder by hand if that is not intended")
  fi

  if (( ${#del_from[@]} == 0 && ${#ins_after[@]} == 0 )); then
    echo "nothing to upgrade: ${file}"
    return 0
  fi

  # Apply: one awk pass over the original lines.
  local spec="" i tmp
  for i in "${!del_from[@]}"; do spec+="D ${del_from[$i]} ${del_to[$i]}"$'\n'; done
  for i in "${!ins_after[@]}"; do spec+="I ${ins_after[$i]} ${ins_text[$i]//$'\n'/$'\x01'}"$'\n'; done
  tmp="$(mktemp)"
  awk -v spec="$spec" '
    BEGIN {
      m = split(spec, rows, "\n")
      for (r = 1; r <= m; r++) {
        if (rows[r] == "") continue
        kind = substr(rows[r], 1, 1); rest = substr(rows[r], 3)
        if (kind == "D") { split(rest, ab, " "); for (l = ab[1]; l <= ab[2]; l++) del[l] = 1 }
        else {
          sp = index(rest, " "); at = substr(rest, 1, sp - 1); t = substr(rest, sp + 1); gsub(/\001/, "\n", t)
          if (at in ins) ins[at] = ins[at] "\n" t; else ins[at] = t
        }
      }
      if (0 in ins) print ins[0]
    }
    { if (!(NR in del)) print; if (NR in ins) print ins[NR] }
  ' "$file" > "$tmp"

  if ! parse_err="$(yq '.' "$tmp" 2>&1 >/dev/null)"; then
    echo "[ERROR] the upgraded file would not parse (${parse_err}); nothing written — report this with the file" >&2
    rm -f "$tmp"; return 2
  fi
  local hash
  hash="sha256:$(cat <(sha256sum "$file" | cut -d' ' -f1) "$tmp" | sha256sum | cut -d' ' -f1)"

  if [[ -n "$confirm" && "$confirm" == "$hash" ]]; then
    # Atomic rename, never `cat > $file`: a killed process must not leave a
    # project's execution.yaml half-written, and a rename is the only write the
    # readers can see either side of. The temp file is a sibling so the rename
    # stays on one filesystem; permissions are carried over from the original.
    local swap="${file}.aid-upgrade.$$"
    cat "$tmp" > "$swap" || { rm -f "$tmp" "$swap"; echo "[ERROR] could not stage the upgraded ${file}; nothing written" >&2; return 2; }
    chmod --reference="$file" "$swap" 2>/dev/null || true
    mv -f "$swap" "$file" || { rm -f "$tmp" "$swap"; echo "[ERROR] could not replace ${file}; nothing written" >&2; return 2; }
    rm -f "$tmp"
    echo "upgraded ${file} (${hash})"
    return 0
  fi
  local rc=3
  if [[ -n "$confirm" ]]; then
    echo "[ERROR] --confirm-upgrade hash does not match the current diff (stale or wrong); nothing written. Current diff:" >&2
    rc=2
  fi
  echo "Proposed upgrade of ${file}:"
  diff -u --label current --label proposed "$file" "$tmp" || true
  rm -f "$tmp"
  echo ""
  printf '%s\n' "${notes[@]}"
  echo ""
  echo "diff_hash: ${hash}"
  echo "To apply exactly this diff, re-run with: --confirm-upgrade ${hash}"
  return $rc
}

export -f detect_stacks compose_execution_yaml \
  stack_gate_names render_gate_profiles_block execution_yaml_has_gate_profiles \
  append_gate_profiles_block render_targeted_tests_gate_block \
  execution_yaml_default_when_paths execution_yaml_upgrade _eyu_locate

# In-library main: `bash …/lib/aid-init-execution-yaml.sh upgrade <project root|file>
# [--confirm-upgrade <hash>] [--default-profile <name>]` — the command every
# refusal names, so a human can run it without a source step.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    upgrade)
      shift
      target="${1:-}"; shift || true
      [[ -n "$target" ]] || { echo "usage: $0 upgrade <project root|execution.yaml> [--confirm-upgrade <hash>] [--default-profile <name>]" >&2; exit 2; }
      [[ -f "$target" ]] || target="${target}/.aid-o/config/execution.yaml"
      execution_yaml_upgrade "$target" "$@"
      exit $?
      ;;
    *)
      echo "usage: $0 upgrade <project root|execution.yaml> [--confirm-upgrade <hash>] [--default-profile <name>]" >&2
      exit 2
      ;;
  esac
fi
