#!/usr/bin/env bash
# aid-audit-independence.sh — detect the actually-achieved audit independence level (D2/D8)
#
# Exit: 0=available (required level achieved and confirmed), 2=unverifiable, 1=usage error
#
# Usage:
#   aid-audit-independence.sh detect --required <level> [--verbose]
#
#   <level> ∈ {context_only, cross_model, cross_provider} — the level demanded by
#   c3-audit-policy.yaml risk_profiles.<profile>.required_independence_level for the
#   current run's risk profile. The caller (Orchestrator, pipeline.md producer hook)
#   passes exactly the required level; this script answers "is that level achievable
#   and confirmed right now", never "what is the best level available" — matching
#   D8's fail-closed intent (an unconfirmed higher level never silently satisfies a
#   lower requirement, and a requirement is never silently downgraded).
#
# Levels:
#   context_only    — baseline. No external dependency. Always available (exit 0).
#   cross_model     — requires a concrete, explicit signal that a second model is
#                     configured for independent audit dispatch (env var
#                     AID_AUDIT_ALT_MODEL, compared against the auditor agent's own
#                     configured model in agents/auditor.md frontmatter). No existing
#                     "alternate model" convention was found elsewhere in this repo
#                     (grepped for ANTHROPIC_MODEL/AID_MODEL/alternate_model/etc. —
#                     no hits), so this env var is a new, minimal, conservative
#                     convention: absent/empty/equal-to-current → unverifiable. Never
#                     assumed available just because multiple agents in this repo use
#                     different models for different roles (agents/*.md `model:` is a
#                     per-role fixed assignment, not an "alternate available for THIS
#                     dispatch" signal).
#   cross_provider  — requires ALL 4 of: (1) codex binary in PATH, (2) codex exec
#                     --help sanity invocation succeeds, (3) codex CLI reports an
#                     authenticated login (`codex login status`), (4) codex exec
#                     --help output exposes the --json/--output-schema flags this
#                     integration would depend on for structured output. Auth (3) is
#                     confirmed ONLY on a clear "Logged in" signal — any other output,
#                     non-zero exit, or missing subcommand is treated as unconfirmed,
#                     never as "assume logged in because the binary exists" (per D8).
#
# Absolute bans (D7):
#   - This script NEVER asks an LLM/agent to self-report which model or provider is
#     executing it. All signals here are static: env vars, frontmatter fields, and
#     codex CLI status/help output.
#   - This script NEVER invokes `codex exec` with a real prompt/dispatch. Only
#     `--help` and `login status` — detection only, never a real audit run.
#
# Degrades gracefully: if `codex`, `jq`, or `git` are unavailable, checks that depend
# on them simply fail closed (unverifiable) rather than the script erroring out hard.
#
# Env:
#   AID_PLUGIN_PATH     — plugin root (defaults to two levels up from this file's
#                         lib/ dir); used to locate agents/auditor.md for cross_model.
#   AID_AUDIT_ALT_MODEL — see cross_model above.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

VERBOSE=false

_trace() {
  # Verbose trace line — only printed with --verbose. Not part of the stable
  # machine-readable status contract (the final "aid-audit-independence:" line is).
  [[ "$VERBOSE" == "true" ]] && echo "aid-audit-independence: trace: $*"
  return 0
}

usage() {
  cat >&2 <<'EOF'
Usage: aid-audit-independence.sh detect --required <level> [--verbose]

  <level>: context_only | cross_model | cross_provider

Exit codes: 0=available, 2=unverifiable, 1=usage error
EOF
}

_valid_level() {
  case "$1" in
    context_only|cross_model|cross_provider) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# cross_model detection
# ---------------------------------------------------------------------------
_detect_cross_model() {
  local alt_model="${AID_AUDIT_ALT_MODEL:-}"
  local auditor_md="${PLUGIN_ROOT}/agents/auditor.md"
  local current_model=""

  _trace "cross_model check 1/2 (alt-model signal): AID_AUDIT_ALT_MODEL=${alt_model:-<unset>}"

  if [[ -z "$alt_model" ]]; then
    echo "aid-audit-independence: cross_model unavailable — AID_AUDIT_ALT_MODEL not set (no concrete alternate-model signal; not assumed)"
    return 1
  fi

  if [[ ! -f "$auditor_md" ]]; then
    echo "aid-audit-independence: cross_model unverifiable — cannot locate ${auditor_md} to compare against"
    return 1
  fi

  current_model="$(grep -m1 '^model:' "$auditor_md" | sed 's/^model:[[:space:]]*//' | tr -d '[:space:]')"
  _trace "cross_model check 2/2 (current model): agents/auditor.md model=${current_model:-<unknown>}"

  if [[ -z "$current_model" ]]; then
    echo "aid-audit-independence: cross_model unverifiable — agents/auditor.md has no model: frontmatter field"
    return 1
  fi

  if [[ "$alt_model" == "$current_model" ]]; then
    echo "aid-audit-independence: cross_model unavailable — AID_AUDIT_ALT_MODEL (${alt_model}) equals auditor's own model (${current_model}); not an independence signal"
    return 1
  fi

  echo "aid-audit-independence: cross_model available — alternate model '${alt_model}' configured (auditor default: '${current_model}')"
  return 0
}

# ---------------------------------------------------------------------------
# cross_provider detection — EXACTLY 4 checks, all must pass. Detection only:
# never invokes `codex exec` with a real prompt.
# ---------------------------------------------------------------------------
_detect_cross_provider() {
  local check1=false check2=false check3=false check4=false
  local help_output="" login_output="" login_exit=0

  # Check 1: binary present in PATH
  if command -v codex &>/dev/null; then
    check1=true
  fi
  _trace "cross_provider check 1/4 (command -v codex): $([[ "$check1" == "true" ]] && echo PASS || echo FAIL)"

  if [[ "$check1" != "true" ]]; then
    echo "aid-audit-independence: cross_provider unverifiable — codex binary not found in PATH (check 1/4 failed)"
    return 1
  fi

  # Check 2: sanity invocation succeeds (--help, never a real dispatch)
  help_output="$(codex exec --help 2>&1)"
  if [[ $? -eq 0 ]]; then
    check2=true
  fi
  _trace "cross_provider check 2/4 (codex exec --help sanity): $([[ "$check2" == "true" ]] && echo PASS || echo FAIL)"

  if [[ "$check2" != "true" ]]; then
    echo "aid-audit-independence: cross_provider unverifiable — 'codex exec --help' sanity invocation failed (check 2/4 failed)"
    return 1
  fi

  # Check 3: auth — confirmed ONLY on an explicit "Logged in" signal. Any other
  # result (non-zero exit, unexpected output, missing subcommand) is unconfirmed
  # by default — never assume authenticated just because the binary exists.
  login_output="$(codex login status 2>&1)"
  login_exit=$?
  if [[ $login_exit -eq 0 ]] && grep -qi '^Logged in' <<<"$login_output"; then
    check3=true
  fi
  _trace "cross_provider check 3/4 (codex login status auth): $([[ "$check3" == "true" ]] && echo PASS || echo "FAIL (exit=${login_exit}, output='${login_output}')")"

  if [[ "$check3" != "true" ]]; then
    echo "aid-audit-independence: cross_provider unverifiable — codex auth unconfirmed (check 3/4 failed; exit=${login_exit}, output='${login_output}')"
    return 1
  fi

  # Check 4: output-shape/schema sanity — confirm the installed codex exposes the
  # structured-output flags this integration would rely on (--json / --output-schema).
  # Structural check only; does not invoke a real dispatch.
  if grep -q -- '--json' <<<"$help_output" && grep -q -- '--output-schema' <<<"$help_output"; then
    check4=true
  fi
  _trace "cross_provider check 4/4 (output-schema shape): $([[ "$check4" == "true" ]] && echo PASS || echo FAIL)"

  if [[ "$check4" != "true" ]]; then
    echo "aid-audit-independence: cross_provider unverifiable — 'codex exec --help' missing expected --json/--output-schema flags (check 4/4 failed)"
    return 1
  fi

  echo "aid-audit-independence: cross_provider available — all 4 checks passed (command, sanity, auth, output-schema)"
  return 0
}

# ---------------------------------------------------------------------------
# detect subcommand
# ---------------------------------------------------------------------------
cmd_detect() {
  local required=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --required)
        [[ $# -lt 2 ]] && { echo "aid-audit-independence: --required requires a level argument" >&2; usage; exit 1; }
        required="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      *)
        echo "aid-audit-independence: unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$required" ]]; then
    echo "aid-audit-independence: --required <level> is mandatory" >&2
    usage
    exit 1
  fi

  if ! _valid_level "$required"; then
    echo "aid-audit-independence: invalid --required level '${required}' (expected context_only|cross_model|cross_provider)" >&2
    usage
    exit 1
  fi

  case "$required" in
    context_only)
      # Baseline — no external dependency, always available.
      echo "aid-audit-independence: status=available level=context_only reason=baseline-no-external-dependency"
      exit 0
      ;;
    cross_model)
      if _detect_cross_model; then
        echo "aid-audit-independence: status=available level=cross_model"
        exit 0
      else
        echo "aid-audit-independence: status=unverifiable level=cross_model"
        exit 2
      fi
      ;;
    cross_provider)
      if _detect_cross_provider; then
        echo "aid-audit-independence: status=available level=cross_provider"
        exit 0
      else
        echo "aid-audit-independence: status=unverifiable level=cross_provider"
        exit 2
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local subcommand="$1"
  shift

  case "$subcommand" in
    detect)
      cmd_detect "$@"
      ;;
    *)
      echo "aid-audit-independence: unknown subcommand: ${subcommand}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
