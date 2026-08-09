#!/usr/bin/env bash
# =============================================================================
# aid-env-name-denylist.sh — ONE definition of "an env var name AID will never
# hand to a child", and the two places that need it both read it from here.
#
# WHY THIS FILE EXISTS AT ALL
# The per-run allocated port is exported into the environment of every service
# start, probe and stop command, and of every gate command. So the NAME of that
# variable is a capability: `port_env: PATH` sets PATH to a port number for the
# whole run and nothing resolves a binary again; `BASH_ENV`, `LD_PRELOAD`,
# `NODE_OPTIONS` or `GIT_SSH_COMMAND` point a code-loading hook at whatever the
# value happens to be.
#
# The check exists at TWO altitudes on purpose:
#   * DECLARATION time — `_svc_denied_port_env` in aid-run-gates.sh, so a bad
#     declaration is refused in the same sweep as every other shape rule;
#   * EXPORT time — `_aid_svc_export_port` in lib/aid-service.sh, the one place
#     that actually performs the export, so a caller that skipped validation
#     still cannot get the name past the export.
# Two altitudes, but ONE list — a second enumeration is a list that drifts, and
# it did: the export-time copy was missing the interpreter-hook and git families
# for one commit and advertised protection it did not provide.
#
# MIRRORED BY: defaults/schemas/service-declaration.schema.json
# (`$defs.service.properties.port_env.allOf`) — keep the entries and their order
# identical. `test-service-declaration.bats` fails if the three drift apart.
#
# MATCHING is EXACT and CASE-SENSITIVE for the enumerated names, and
# case-sensitive PREFIX for the open-ended families (`LD_`, `DYLD_`,
# `BASH_FUNC_`, `AID_`). Case-sensitive because environment variables are:
# `Path` is not `PATH` and nothing on the system honours it, so refusing the
# case variant would be a false refusal that buys no safety. Prefix only where
# the family is genuinely open-ended and libc/shell-version dependent
# (LD_PRELOAD, LD_AUDIT, LD_LIBRARY_PATH, …), so an enumeration would go stale.
# =============================================================================

[[ -n "${_AID_ENV_NAME_DENYLIST_LOADED:-}" ]] && return 0
_AID_ENV_NAME_DENYLIST_LOADED=1

# aid_env_name_denied <name> — rc 0 when the name must NEVER be exported.
aid_env_name_denied() {
  case "${1-}" in
    # Open-ended families: dynamic loaders, bash's exported-function channel,
    # and AID's own runtime namespace.
    LD_*|DYLD_*|BASH_FUNC_*|AID_*) return 0 ;;
    # Command lookup, shell parsing/startup, and the process's idea of where it is.
    PATH|CDPATH|IFS|PS4|ENV|BASH_ENV|SHELLOPTS|BASHOPTS|SHELL|HOME|PWD|OLDPWD|TMPDIR|TMP|TEMP|GLIBC_TUNABLES) return 0 ;;
    # Interpreter hooks — each one changes what a child interpreter loads or runs.
    PYTHONPATH|PYTHONHOME|PYTHONSTARTUP|PERL5LIB|PERL5OPT|NODE_OPTIONS|NODE_PATH|RUBYOPT|RUBYLIB|GEM_HOME|GEM_PATH|CLASSPATH|JAVA_TOOL_OPTIONS|_JAVA_OPTIONS) return 0 ;;
    # git's own exec hooks and repository resolution — the runner shells out to git.
    GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_SSH|GIT_SSH_COMMAND|GIT_EXTERNAL_DIFF|GIT_PAGER) return 0 ;;
  esac
  return 1
}
