#!/usr/bin/env bash
# aid-audit-tests-cli-parse.sh — P066 Step 8.
#
# The real, deterministic argument parser/validator commands/aid-audit-tests.md
# instructs the controller to invoke FIRST — the command file documents the
# contract; it performs no validation itself. Every malformed input fails
# loudly with a distinct exit code, never silently defaulted.
#
# Usage:
#   aid-audit-tests-cli-parse.sh [scope] [--mode static|measure|full]
#     [--budget-minutes N] [--max-agents N] [--repeat N] [--write-plan]
#     [--resume <audit-id>] [--project-root <path>]
#
# scope: "repo" (default), "path:<path>", or "runner:<id>". <path> is checked
# for existence and <id> against the real scanner's discovered runner
# families — both require --project-root (defaults to cwd).
#
# Exit codes:
#   0  success — prints the parsed/validated arguments as JSON to stdout
#   2  unknown option
#   3  nonexistent path: scope
#   4  --mode full given without --budget-minutes (hard error, never a default)
#   5  --max-agents is not a positive integer
#   6  runner:<id> matches no discovered family (lists the real families as a hint)
#   7  --budget-minutes is not a positive integer
#   8  --repeat is not a positive integer
#   9  --mode is not one of static|measure|full
#   10 --project-root does not exist (or is not a directory) — checked
#      regardless of scope, since every later step (scanner, dispatch,
#      measurement) resolves paths against it
#   12 disposable-clone precondition: the target is a checkout of the SAME
#      repository (identified by shared root commit, not by origin URL) but
#      has no .aid-o/config/execution.yaml — the clone was made without the
#      gitignored config, so every declared-command gate would silently
#      vanish. Names the exact copy that fixes it. Downgradeable with
#      --allow-missing-config.
#   13 .aid-o/config/execution.yaml exists but cannot be read — distinct from
#      12 on purpose: "cannot read" and "not there" call for different
#      operator actions, and a broken symlink must not read as "absent"
#      (An unrelated or un-initialized target only WARNS: auditing a project
#      that has no gates is legitimate, and a hard failure there would break
#      every audit of a bare fixture or a consumer project.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-adapter-bats.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-bats.sh"

_die() {
  local code="$1" msg="$2"
  echo "aid-audit-tests: $msg" >&2
  exit "$code"
}

scope="repo"
mode="static"
budget_minutes=""
max_agents=""
repeat=""
write_plan="false"
resume_id=""
project_root="$(pwd)"
allow_missing_config="false"

positional_seen=0
# Every value-taking option checks `$# -ge 2` before consuming an operand —
# `shift 2` on a missing operand fails bash's own arity check under
# `set -e` and would otherwise exit silently with no diagnostic, violating
# this script's own "every malformed input fails loudly" contract.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || _die 2 "--mode requires a value"
      mode="$2"
      shift 2
      ;;
    --budget-minutes)
      [[ $# -ge 2 ]] || _die 2 "--budget-minutes requires a value"
      budget_minutes="$2"
      shift 2
      ;;
    --max-agents)
      [[ $# -ge 2 ]] || _die 2 "--max-agents requires a value"
      max_agents="$2"
      shift 2
      ;;
    --repeat)
      [[ $# -ge 2 ]] || _die 2 "--repeat requires a value"
      repeat="$2"
      shift 2
      ;;
    --write-plan)
      write_plan="true"
      shift
      ;;
    --resume)
      [[ $# -ge 2 ]] || _die 2 "--resume requires a value"
      resume_id="$2"
      shift 2
      ;;
    --allow-missing-config)
      allow_missing_config="true"; shift ;;
    --project-root)
      [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"
      project_root="$2"
      shift 2
      ;;
    repo|path:*|runner:*)
      [[ "$positional_seen" -eq 0 ]] || _die 2 "unknown option '$1' (scope already given as a positional argument)"
      scope="$1"
      positional_seen=1
      shift
      ;;
    -h|--help)
      echo "Usage: aid-audit-tests-cli-parse.sh [repo|path:<p>|runner:<id>] [--mode static|measure|full] [--budget-minutes N] [--max-agents N] [--repeat N] [--write-plan] [--resume <id>] [--project-root <path>]"
      exit 0
      ;;
    *)
      _die 2 "unknown option '$1'"
      ;;
  esac
done

case "$mode" in
  static|measure|full) ;;
  *) _die 9 "--mode must be one of static|measure|full, got '$mode'" ;;
esac

if [[ "$mode" == "full" && -z "$budget_minutes" ]]; then
  _die 4 "--mode full requires --budget-minutes (hard error, never a default)"
fi

if [[ -n "$budget_minutes" ]]; then
  [[ "$budget_minutes" =~ ^[1-9][0-9]*$ ]] || _die 7 "--budget-minutes must be a positive integer, got '$budget_minutes'"
fi

if [[ -n "$max_agents" ]]; then
  [[ "$max_agents" =~ ^[1-9][0-9]*$ ]] || _die 5 "--max-agents must be a positive integer, got '$max_agents'"
fi

if [[ -n "$repeat" ]]; then
  [[ "$repeat" =~ ^[1-9][0-9]*$ ]] || _die 8 "--repeat must be a positive integer, got '$repeat'"
fi

# PM-confirmed blocker: project_root existence was previously checked only
# for path:/runner: scopes, so `--project-root /nonexistent` with the
# DEFAULT "repo" scope silently succeeded — leaving the controller with no
# guarantee about which (possibly nonexistent) project the scanner/dispatch
# would then run against. Checked and canonicalized here, unconditionally,
# regardless of scope.
resolved_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 10 "--project-root '$project_root' does not exist (or is not a directory)"
project_root="$resolved_root"

# ─── Disposable-clone precondition (P072 Step 8) ────────────────────────────
#
# `.aid-o/` is gitignored, so a clone made for a disposable audit carries no
# config unless someone copied it. Without it every declared-command gate
# disappears from discovery and the audit reports a smaller portfolio than the
# project has — confidently, with nothing to show anything is missing.
#
# The check is deliberately NARROW. "The invoking directory is configured and
# the target is not" is NOT enough to conclude a clone: auditing an unrelated,
# un-initialized project from inside your own AID project is an ordinary thing
# to do, and failing it hard would break that. The hard error fires only when
# the target is plausibly a CLONE OF THIS project — same git origin, or the
# invoker's toplevel reachable as the clone's origin path — because that is
# the case where the missing config is an accident rather than a fact about
# the project. Everything else warns.
_target_exec="${project_root%/}/.aid-o/config/execution.yaml"
_target_cfg_dir="${project_root%/}/.aid-o/config"

# The invoking project's root comes from git, not from `pwd`: running the
# audit from a subdirectory is ordinary, and `pwd` would then look for the
# config in the wrong place and compare the wrong worktree.
_invoking_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_invoking_exec="${_invoking_root}/.aid-o/config/execution.yaml"

# _audit_same_repo — 0 when the target is a checkout of the SAME repository as
# the invoking one.
#
# Identity is the ROOT COMMIT, not the origin URL. Comparing URLs is wrong in
# both directions: `git@host:o/r` and `https://host/o/r` are the same
# repository and would compare unequal, while a relative or `file://` remote
# needs resolving against the target's own gitdir before it means anything. A
# root commit is the same sha in every checkout, however it was cloned, and it
# needs no parsing, no network and no `cd` onto a value that came out of a
# config file.
_audit_same_repo() {
  command -v git >/dev/null 2>&1 || return 1
  local t_root i_root
  t_root="$(git -C "$project_root" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1 || true)"
  [[ -n "$t_root" ]] || return 1
  i_root="$(git -C "$_invoking_root" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1 || true)"
  [[ -n "$i_root" ]] || return 1
  [[ "$t_root" == "$i_root" ]]
}

# _audit_path_unreadable — 0 when the config path cannot even be examined
# because an ancestor is not traversable. Both `-e` and `-L` are false in that
# case, so without this the directory would be misreported as "no config" and
# the operator told to copy one in, which a permission problem will not fix.
_audit_path_unreadable() {
  [[ -d "$_target_cfg_dir" && ! -x "$_target_cfg_dir" ]] && return 0
  local parent="${project_root%/}/.aid-o"
  [[ -d "$parent" && ! -x "$parent" ]] && return 0
  return 1
}

if _audit_path_unreadable; then
  _die 13 "'$_target_exec' cannot be examined — an ancestor directory is not traversable. This is a permissions problem, not a missing config; copying a config in will not fix it."
elif [[ -e "$_target_exec" || -L "$_target_exec" ]]; then
  # `-e` FOLLOWS a symlink, so a broken link reads as absent and would be
  # reported as the copy-the-config case. `-L` catches the link itself, which
  # is what makes "present but unusable" distinguishable from "not there" —
  # they need different fixes.
  [[ -r "$_target_exec" && -f "$_target_exec" ]] \
    || _die 13 "'$_target_exec' exists but cannot be read as a file (broken symlink, a directory, or permissions) — this is not the same as a missing config; fix the file rather than copying over it"
elif [[ "$allow_missing_config" == "true" ]]; then
  echo "aid-audit-tests-cli-parse.sh: WARNING — '$project_root' has no .aid-o/config/execution.yaml; every declared-command gate will be ABSENT from this audit, and its portfolio will be smaller than the project's. Continuing because --allow-missing-config was given." >&2
elif [[ -f "$_invoking_exec" ]] && _audit_same_repo; then
  _die 12 "'$project_root' is a checkout of this same repository but has no .aid-o/config/execution.yaml — .aid-o/ is gitignored, so every declared-command gate would silently vanish from this audit. Fix with:
    mkdir -p '${project_root%/}/.aid-o' && cp -r '${_invoking_root}/.aid-o/config' '${project_root%/}/.aid-o/config'
Or pass --allow-missing-config to audit without declared gates on purpose."
fi
# An unrelated or un-initialized target is SILENT on purpose. Auditing a
# project that has no declared gates is ordinary, and a warning on every such
# run is noise that teaches people to ignore warnings — including the two that
# matter above. The audit's own report states the portfolio it found; it does
# not need this stage to speculate about what a different project might have.

case "$scope" in
  path:*)
    scope_path="${scope#path:}"
    abs_scope_path="${project_root%/}/${scope_path}"
    [[ -d "$abs_scope_path" ]] || _die 3 "scope path '$scope_path' does not exist (or is not a directory) under project root '$project_root'"
    # Canonicalize both sides and require the resolved scope to be a real
    # subdirectory STRICTLY inside project_root — never the project root
    # itself, and never a `path:../sibling` escape outside it (Codex
    # review: a `-e` check alone accepted files, the project root, and
    # sibling directories outside the project).
    resolved_scope="$(cd "$abs_scope_path" 2>/dev/null && pwd -P)" || _die 3 "scope path '$scope_path' could not be resolved"
    [[ "$resolved_scope" != "$project_root" && "$resolved_scope" == "$project_root"/* ]] \
      || _die 3 "scope path '$scope_path' resolves outside project root '$project_root'"
    ;;
  runner:*)
    runner_id="${scope#runner:}"
    discovered_json="$(bats_adapter_discover "$project_root" 2>/dev/null || echo '[]')"
    discovered_families="$(jq -r '[.[].runner] | unique | join(", ")' <<<"$discovered_json" 2>/dev/null || echo "")"
    if ! jq -e --arg r "$runner_id" 'any(.[]; .runner == $r)' <<<"$discovered_json" >/dev/null 2>&1; then
      _die 6 "runner:'$runner_id' matches no discovered family — discovered: [${discovered_families}]"
    fi
    ;;
esac

# project_root is returned CANONICAL in every result — the command contract
# (commands/aid-audit-tests.md) states every later step (scanner, dispatch,
# measurement) uses exactly this value, never re-resolves its own.
jq -n \
  --arg scope "$scope" \
  --arg mode "$mode" \
  --arg budget_minutes "$budget_minutes" \
  --arg max_agents "$max_agents" \
  --arg repeat "$repeat" \
  --arg write_plan "$write_plan" \
  --arg resume_id "$resume_id" \
  --arg project_root "$project_root" \
  '{
    scope: $scope,
    mode: $mode,
    budget_minutes: (if $budget_minutes == "" then null else ($budget_minutes | tonumber) end),
    max_agents: (if $max_agents == "" then null else ($max_agents | tonumber) end),
    repeat: (if $repeat == "" then null else ($repeat | tonumber) end),
    write_plan: ($write_plan == "true"),
    resume_id: (if $resume_id == "" then null else $resume_id end),
    project_root: $project_root
  }'
