# shellcheck shell=bash
# aid-measure-env.sh — the environment a point is measured in (P110 isolation, P117 one verification_env):
# sourced by aid-plan-diff.sh (the step, the plan_diff gate, produce) and by plan-run, which asks the same
# probe before the first step (P117 (2): a run that cannot measure stops at its start, not at its close).
# Needs STATE_ROOT (the state root, whose .aid-o/config/execution.yaml is the project rule).
#
# aid_measure_isolation_check — prints "PD_NET<TAB>PD_NEXT"; exit 0 when a point can be measured
# (host via verification_env, or unshare), 1 otherwise.

# ── isolation (P110, --isolated) ────────────────────────────────────────────
# PD_NET: unshare | host | none | env_stripped:<VAR> | verification_env_unset:<VAR>
PD_NET="" PD_NET_LABEL="null" PD_ENV=() PD_ENV_KEYS="[]" PD_NEXT=""  # shellcheck disable=SC2034
# <timeout> <cmd file> — the namespace prefix: loopback up as root, then back to
# the caller's uid. Its own pid namespace too: whatever the point starts in the
# background (a listener) dies with it instead of outliving the measurer.
_pd_ns_run() {
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" \
    unshare -rn --pid --fork sh -c 'ip link set lo up 2>/dev/null; exec unshare --map-user="$1" --map-group="$2" timeout "$3" bash "$4"' \
    _ "$(id -u)" "$(id -g)" "$1" "$2"
}
# _pd_env_load — the project's verification_env (.aid-o/config/execution.yaml) into PD_ENV / PD_ENV_KEYS:
# ONE reader for the step measurement, the gates and produce (P117; WAN P110/P112: a step measured without
# it saw `absent` in 130 ms while the tests passed). Returns 1 when the map is empty, 2 on an unset ${VAR}.
_pd_env_load() {
  local map key val var
  map="$(yq -o=json '.verification_env // {}' "${STATE_ROOT}/.aid-o/config/execution.yaml" 2>/dev/null || echo '{}')"
  [[ -n "$map" && "$map" != null ]] || map='{}'
  [[ "$(jq 'length' <<< "$map")" -gt 0 ]] || return 1
  PD_ENV_KEYS="$(jq -c 'keys' <<< "$map")"
  while IFS=$'\t' read -r key val; do
    if [[ "$val" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]; then
      var="${BASH_REMATCH[1]}"
      [[ -n "${!var+x}" ]] || { PD_NET="verification_env_unset: ${var}"; PD_NEXT="next: set ${var} in the environment that runs the measurement, or give ${key} a literal value in verification_env"; return 2; }
      val="${!var}"
    fi
    PD_ENV+=("${key}=${val}")
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$map")
  return 0
}
_pd_isolation_init() {
  local var probe rc=0
  _pd_env_load || rc=$?
  if (( rc == 0 )); then PD_NET=host; PD_NET_LABEL="host (verification_env)"; return 0; fi
  (( rc == 2 )) && return 0
  # a service address a test suite reads (ASISTENT_TEST_DATABASE_URL), not any
  # name with TEST in it (BATS_TEST_TMPDIR)
  var="$(compgen -e | grep -E '^[A-Za-z0-9_]*(DATABASE_URL|REDIS_URL|_TEST_[A-Za-z0-9_]*(URL|DSN))$' | head -1)" || true
  if [[ -n "$var" ]]; then
    PD_NET="env_stripped: ${var}"
    PD_NEXT="next: declare ${var} in verification_env (.aid-o/config/execution.yaml) or unset it — a suite that reads it would skip its database tests silently"
    return 0
  fi
  probe="$(mktemp)"; echo true > "$probe"
  if command -v unshare >/dev/null 2>&1 && _pd_ns_run 10 "$probe" >/dev/null 2>&1; then
    PD_NET=unshare; PD_NET_LABEL=unshare
    command -v ip >/dev/null 2>&1 || PD_NET_LABEL="unshare (no loopback)"
  else
    PD_NET=none
    PD_NEXT="next: install util-linux >= 2.38 (unshare --map-user) and allow user namespaces (sysctl kernel.unprivileged_userns_clone=1); until then no point is measured"
  fi
  rm -f "$probe"
}

aid_measure_isolation_check() {
  PD_NET="" PD_NEXT="" PD_ENV=() PD_ENV_KEYS="[]"
  _pd_isolation_init
  printf '%s\t%s\n' "$PD_NET" "$PD_NEXT"
  [[ "$PD_NET" == host || "$PD_NET" == unshare ]]
}
