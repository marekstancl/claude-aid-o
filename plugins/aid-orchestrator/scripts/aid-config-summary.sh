#!/usr/bin/env bash
# aid-config-summary.sh — the one read-only rendering of the effective AID
# configuration, presented verbatim by BOTH `/aid-init` (as its closing output)
# and `/aid-setup` (before its module menu).
#
# WHY THIS EXISTS: init and setup each used to describe the resulting
# configuration in their own prose, from their own reads, and the two
# descriptions drifted — most visibly around `active_preset`, where a fresh
# workspace reads `autonomous` next to `autonomous_mode: false` and each
# surface improvised its own wording. One script, one wording, two callers.
#
# READ-ONLY CONTRACT — this script NEVER writes. No redirection to a file, no
# `yq -i`, no `sed -i`, no temp file, no `mkdir`. A missing workspace, a missing
# config file, an unparseable config file are all REPORT LINES, not errors: a
# summary must be able to summarize a broken configuration rather than crash on
# it. The only side effect permitted is stdout (the report) and stderr (the
# roots lib's own resolution failure).
#
# Usage:
#   aid-config-summary.sh            # render the summary for the resolved state root
#   aid-config-summary.sh --help
#
# Exit codes (repo convention):
#   0  rendered — INCLUDING "no workspace here", which is a finding, not a fault
#   2  usage error (unknown argument)
#   3  state root unresolvable — propagates `aid_state_root`'s loud failure
#      (outside a git repository); its error text is left on stderr untouched.
#
# Output is a FIXED-ORDER plain-text block, one `label: value` per line. The
# order and the labels are part of the contract (fixture tests assert them).
# No value is ever empty — every absence renders as an explicit word.
#
# **Last Updated:** 2026-08-11
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-roots.sh"

PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: aid-config-summary.sh [--help]

Prints the effective AID configuration for this project (read-only).

Exit: 0 = rendered, 2 = usage, 3 = state root unresolvable.
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) echo "ERROR: unknown argument '$1'" >&2; usage; exit 2 ;;
esac

# ── state root ───────────────────────────────────────────────────────────
# aid_state_root returns 2 outside a git repository after printing its own
# error; this script's contract maps that to exit 3 and does not restate it.
ROOT=""
if ! ROOT="$(aid_state_root)"; then
  exit 3
fi

AID_O="${ROOT}/.aid-o"
EXECUTION_YAML="${AID_O}/config/execution.yaml"
PERMISSIONS_YAML="${AID_O}/config/permissions.yaml"
ORCHESTRATION_YAML="${AID_O}/config/orchestration.yaml"
PLUGIN_YAML="${AID_O}/config/plugin.yaml"
POLICY_YAML="${AID_O}/config/policies/plan-boundary-policy.yaml"
DEFAULT_ORCHESTRATION="${PLUGIN_ROOT}/defaults/orchestration.yaml"
DEFAULT_POLICY="${PLUGIN_ROOT}/defaults/policies/plan-boundary-policy.yaml"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
MANIFEST_DIR="${ROOT}/.aid-lifecycle/manifests"

# _short <path> — the path relative to the state root when it is inside it,
# so the rendered source names stay readable and machine-stable.
_short() {
  local p="$1"
  printf '%s' "${p#"${ROOT}/"}"
}

# _yq_err <file> — first line of yq's parse error for <file>, empty when the
# file parses. Read-only: yq is never given -i.
_yq_err() {
  local f="$1" err=""
  [[ -f "$f" ]] || return 0
  err="$(yq -o=yaml '.' "$f" 2>&1 >/dev/null)" || {
    # First line only, without a pipeline (no SIGPIPE race under pipefail).
    printf '%s' "${err%%$'\n'*}"
    return 0
  }
  printf ''
}

# _unparseable <file> <err> — the canonical broken-config rendering.
_unparseable() {
  printf 'unparseable (%s; yq: %s)' "$(_short "$1")" "$2"
}

# _get <file> <expr> — a scalar read that never fails the script and never
# yields an empty-looking "null".
# _sanitise — one line, printable, bounded.
#
# WHY: both `/aid-init` and `/aid-setup` are instructed to present this output
# VERBATIM to the PM. A value is workspace YAML that any contributor can edit, so
# without this a block scalar in `active_preset` writes its own extra report lines —
# CP3 produced a convincing fake `permissions: autonomous (implicit)` and a fake
# `plan mode default: plan_branch (policy_default)` that way. Carriage returns
# repaint the line in a terminal and ANSI escapes recolour or erase it. The fixed
# label set is a contract; a value that can forge a label breaks it.
#
# Newlines and tabs become a visible marker rather than disappearing: a value that
# was multi-line should LOOK wrong, not look tidy.
_sanitise() {
  local v="$1"
  v="${v//$'\r'/}"
  v="$(printf '%s' "$v" | tr '\n\t' '␞␞' 2>/dev/null || printf '%s' "$v")"
  # Strip ANSI CSI/OSC sequences.
  v="$(printf '%s' "$v" | sed -E $'s/\033\\[[0-9;?]*[A-Za-z]//g; s/\033\\][^\a]*(\a|\033\\\\)//g')"
  # Remaining control characters -> a dot; an invisible byte must not stay invisible.
  v="$(printf '%s' "$v" | tr -c '[:print:]␞' '.' 2>/dev/null || printf '%s' "$v")"
  # Bounded: a megabyte value must not push the rest of the report off screen.
  if [[ "${#v}" -gt 200 ]]; then v="${v:0:200}…(truncated)"; fi
  printf '%s' "$v"
}

_get() {
  local f="$1" expr="$2" v=""
  [[ -f "$f" ]] || { printf ''; return 0; }
  v="$(yq -r "$expr" "$f" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  _sanitise "$v"
}

# yq presence is not enough — it has to be the RIGHT yq. Two incompatible tools
# share the name: mikefarah's Go implementation (what this repo depends on) and the
# Python wrapper around jq. Under the Python one every expression here fails, so the
# summary would report the entire configuration as unparseable — including the
# plugin's own shipped files — and still exit 0. A confident "everything is broken"
# is as bad as a confident wrong value, and it points the reader at the wrong repo.
have_yq=1
if ! command -v yq >/dev/null 2>&1; then
  have_yq=0
  yq_flavour="not installed"
elif ! yq --version 2>&1 | grep -qi 'mikefarah\|yq (https://github.com/mikefarah/yq'; then
  have_yq=0
  yq_flavour="wrong flavour ($(yq --version 2>&1 | head -1 | tr -d '\n' | cut -c1-60)); this report needs mikefarah/yq"
fi

# ── 1. state root ────────────────────────────────────────────────────────
printf 'state root: %s\n' "$ROOT"

# ── 2. workspace ─────────────────────────────────────────────────────────
workspace="absent"
if [[ -d "$AID_O" ]]; then
  if [[ -d "${AID_O}/config" ]]; then
    workspace="present"
  else
    workspace="present (v1 layout — run /aid-init --upgrade)"
  fi
fi
printf 'workspace: %s\n' "$workspace"

# ── 3. plan mode default ─────────────────────────────────────────────────
# Same two inputs and the same wording as the runtime resolver
# (`_pfsm_default_mode` in aid-plan-fsm.sh): the policy `default_mode` is a
# CEILING granted only when a non-empty gate_profiles table exists.
policy_file="$DEFAULT_POLICY"
[[ -f "$POLICY_YAML" ]] && policy_file="$POLICY_YAML"

exec_err=""; policy_err=""
if [[ "$have_yq" == "1" ]]; then
  exec_err="$(_yq_err "$EXECUTION_YAML")"
  policy_err="$(_yq_err "$policy_file")"
fi

# gate profile names — also decides the plan-mode ceiling below.
gate_profiles_state="absent"   # absent | none | listed | broken
gate_profiles_value="absent"
if [[ ! -f "$EXECUTION_YAML" ]]; then
  gate_profiles_value="absent"
elif [[ "$have_yq" != "1" ]]; then
  gate_profiles_state="unknown"
  gate_profiles_value="unknown (yq: ${yq_flavour})"
elif [[ -n "$exec_err" ]]; then
  gate_profiles_state="broken"
  gate_profiles_value="$(_unparseable "$EXECUTION_YAML" "$exec_err")"
else
  names="$(yq -r '.gate_profiles // {} | keys | .[]' "$EXECUTION_YAML" 2>/dev/null || true)"
  if [[ -z "$names" ]]; then
    gate_profiles_state="none"
    gate_profiles_value="none defined"
  else
    gate_profiles_state="listed"
    joined=""
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      if [[ -z "$joined" ]]; then joined="$n"; else joined="${joined}, ${n}"; fi
    done <<< "$names"
    gate_profiles_value="$joined"
  fi
fi

want_mode=""
if [[ "$have_yq" == "1" && -z "$policy_err" ]]; then
  want_mode="$(_get "$policy_file" '.default_mode // ""')"
fi
[[ -z "$want_mode" ]] && want_mode="legacy_epic_release_mode"

case "$want_mode" in
  plan_branch)
    if [[ "$gate_profiles_state" == "listed" ]]; then
      plan_mode="plan_branch (policy_default)"
    else
      plan_mode="legacy_epic_release_mode (plan_branch_unavailable: no_gate_profiles)"
    fi
    ;;
  legacy_epic_release_mode)
    plan_mode="legacy_epic_release_mode (policy_default)"
    ;;
  *)
    plan_mode="legacy_epic_release_mode (unknown_policy_default: ${want_mode})"
    ;;
esac
if [[ "$have_yq" == "1" && -n "$policy_err" ]]; then
  plan_mode="$(_unparseable "$policy_file" "$policy_err")"
fi
printf 'plan mode default: %s\n' "$plan_mode"

# ── 4. gate profiles ─────────────────────────────────────────────────────
printf 'gate profiles: %s\n' "$gate_profiles_value"

# ── 5. permissions ───────────────────────────────────────────────────────
# The two canonical display strings — defined once in commands/aid-init.md
# ("How the pair is displayed") and skills/setup/permissions.md, used here
# byte-identically. There is deliberately NO third phrasing.
permissions="absent"
if [[ -f "$PERMISSIONS_YAML" ]]; then
  perm_err=""
  [[ "$have_yq" == "1" ]] && perm_err="$(_yq_err "$PERMISSIONS_YAML")"
  if [[ "$have_yq" != "1" ]]; then
    permissions="unknown (yq: ${yq_flavour})"
  elif [[ -n "$perm_err" ]]; then
    permissions="$(_unparseable "$PERMISSIONS_YAML" "$perm_err")"
  else
    preset="$(_get "$PERMISSIONS_YAML" '.active_preset // ""')"
    # `// ""` is WRONG for a boolean. yq's alternative operator, like jq's, fires
    # on false as well as on null — so `autonomous_mode: false` came back empty and
    # was relabelled `absent`. That is a safety inversion on the one line a PM reads
    # this block for: `absent` is this script's own word for "key missing", and the
    # sibling canonical string tells the reader a missing key means IMPLICITLY
    # AUTONOMOUS. A workspace that deliberately switched autonomy OFF therefore
    # displayed as one that never set it — the safe state wearing the permissive
    # state's face. The type tag separates the two: `!!null` only when truly absent.
    if [[ "$(_get "$PERMISSIONS_YAML" '.autonomous_mode | tag')" == "!!null" ]]; then
      auto="absent"
    else
      auto="$(_get "$PERMISSIONS_YAML" '.autonomous_mode')"
    fi
    if [[ -n "$preset" ]]; then
      permissions="${preset} (preset) — autonomous_mode: ${auto}"
    else
      # An empty-string active_preset is the same lived situation as a missing
      # one: nothing selected, and the next change writes it.
      permissions="autonomous (implicit — key missing, will be written on first change)"
    fi
  fi
fi
printf 'permissions: %s\n' "$permissions"

# ── 6. dispatch mode ─────────────────────────────────────────────────────
# Resolution order is the FSM's own, and it is EXACTLY TWO SOURCES
# (aid-fsm.sh:2423-2427): the project's `.aid-o/config/plugin.yaml → dispatch_mode`,
# then the PLUGIN's own `defaults/orchestration.yaml → dispatch.mode`, then the
# built-in `agent_tool`.
#
# `.aid-o/config/orchestration.yaml` is DELIBERATELY NOT CONSULTED. Nothing in the
# plugin reads it. An earlier version of this block did, and named it as the source
# — so a project carrying `dispatch.mode: inline` there would have been told
# "inline (source: .aid-o/config/orchestration.yaml)" while the FSM actually ran
# `agent_tool`. A confident wrong answer with a citation attached is worse than no
# answer, and it is the same defect the plan's own deviation was correcting, only
# pointing the other way. This summary reports what the runtime does, not what a
# file that nobody reads would suggest.
dispatch="agent_tool"
dispatch_src="built-in fallback"
orch_file=""
[[ -f "$DEFAULT_ORCHESTRATION" ]] && orch_file="$DEFAULT_ORCHESTRATION"

if [[ "$have_yq" != "1" ]]; then
  dispatch="unknown"; dispatch_src="yq: ${yq_flavour}"
else
  if [[ -n "$orch_file" ]]; then
    orch_err="$(_yq_err "$orch_file")"
    if [[ -n "$orch_err" ]]; then
      dispatch=""; dispatch_src=""
      dispatch_line="$(_unparseable "$orch_file" "$orch_err")"
    else
      v="$(_get "$orch_file" '.dispatch.mode // ""')"
      if [[ -n "$v" ]]; then
        dispatch="$v"
        # The plugin's own default file is named as such — its absolute path
        # depends on where the plugin is installed and would make the report
        # differ between two copies of the same plugin.
        if [[ "$orch_file" == "$DEFAULT_ORCHESTRATION" ]]; then
          dispatch_src="plugin default orchestration.yaml"
        else
          dispatch_src="$(_short "$orch_file")"
        fi
      fi
    fi
  fi
  if [[ -f "$PLUGIN_YAML" && -z "${dispatch_line:-}" ]]; then
    plug_err="$(_yq_err "$PLUGIN_YAML")"
    if [[ -z "$plug_err" ]]; then
      v="$(_get "$PLUGIN_YAML" '.dispatch_mode // ""')"
      if [[ -n "$v" ]]; then
        dispatch="$v"
        dispatch_src="$(_short "$PLUGIN_YAML")"
      fi
    fi
  fi
fi
if [[ -n "${dispatch_line:-}" ]]; then
  printf 'dispatch mode: %s\n' "$dispatch_line"
else
  printf 'dispatch mode: %s (source: %s)\n' "$dispatch" "$dispatch_src"
fi

# ── 7. plan lifecycle manifests ──────────────────────────────────────────
manifests="absent"
if [[ -d "$MANIFEST_DIR" ]]; then
  count=0; pb=0; legacy=0; other=0
  for m in "$MANIFEST_DIR"/*.yaml; do
    [[ -e "$m" ]] || continue
    count=$((count + 1))
    mode=""
    [[ "$have_yq" == "1" ]] && mode="$(_get "$m" '.mode // ""')"
    case "$mode" in
      plan_branch) pb=$((pb + 1)) ;;
      legacy_epic_release_mode) legacy=$((legacy + 1)) ;;
      *) other=$((other + 1)) ;;
    esac
  done
  if [[ "$count" -eq 0 ]]; then
    manifests="none"
  else
    # `mode absent` is a real state, not a read failure: manifests written
    # before the mode key existed carry no declaration at all.
    manifests="${count} (plan_branch: ${pb}, legacy_epic_release_mode: ${legacy}, mode absent: ${other})"
  fi
fi
printf 'plan manifests: %s\n' "$manifests"

# ── 8. plugin version ────────────────────────────────────────────────────
version="absent"
if [[ -f "$PLUGIN_JSON" ]]; then
  if [[ "$have_yq" != "1" ]]; then
    version="unknown (yq: ${yq_flavour})"
  else
    v="$(yq -p json -o=yaml -r '.version // ""' "$PLUGIN_JSON" 2>/dev/null || true)"
    [[ "$v" == "null" ]] && v=""
    if [[ -n "$v" ]]; then
      version="$v"
    else
      version="unreadable (${PLUGIN_JSON##*/})"
    fi
  fi
fi
printf 'plugin version: %s\n' "$version"

exit 0
