#!/usr/bin/env bats
# aid-tier: t2
# test-service-declaration.bats — P076 Step 8: the OPTIONAL `services:` block
# in execution.yaml.
#
# There are deliberately TWO authorities for the shape of a service
# declaration, and the whole point of this suite is that they cannot drift:
#
#   • defaults/schemas/service-declaration.schema.json — documentation + test
#     authority.
#   • `_validate_services_config` in aid-run-gates.sh — runtime enforcement,
#     run at run-all entry before any service or gate action.
#
# So the case table below is a SHARED FIXTURE SET: one YAML source per case,
# fed to BOTH validators (the JSON the schema sees is derived from that same
# YAML by yq, so there is no second hand-written copy to fall out of sync).
# Each case declares the verdict it expects from each authority. Where those
# verdicts differ, the difference is named in the table and asserted, not
# glossed over — see `dup_port_env`, the one constraint JSON Schema cannot
# express across sibling properties.
#
# Cases:
#   1. Shared fixture set — the bash validator agrees with the table.
#   2. Shared fixture set — the JSON Schema agrees with the table.
#   3. Drift guard — the two authorities agree on every case the schema CAN
#      express, and the ONE documented divergence is exactly that one.
#   4. A missing probe_cmd fails naming the field (the plan's named case).
#   5. Duplicate port_env is refused, naming both services and the env var.
#   6. GOLDEN — an execution.yaml with no services block is byte-identical to
#      the committed pre-P076 report (EPIC-1 fixture, reused verbatim).
#   7. The REAL runner refuses a malformed services block before any gate
#      command is spawned.
#   8. The shipped template documents the block with ZERO active services.
#   9. port_env may not name a variable the runner's own children depend on
#      (PATH, LD_*, …) — refused by service, field and variable; the case
#      variant is accepted, on purpose.
#  10. start_cmd may not carry an obvious backgrounding form, and the refusal
#      states the limit of that syntactic check.
#  11. Fail-closed: "I could not look" (missing file, missing yq, unparsable)
#      is exit 2 and is distinguishable from "there is nothing to validate"
#      (exit 0, silent).
#  12. A service name containing a newline is refused for BEING one, not blamed
#      on some other field.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  export RUN_GATES
  SCHEMA="$PLUGIN_ROOT/defaults/schemas/service-declaration.schema.json"
  export SCHEMA
  TEMPLATE="$PLUGIN_ROOT/defaults/execution.yaml"
  export TEMPLATE
  GOLDEN="$PLUGIN_ROOT/scripts/tests/fixtures/p076/golden-gates-report.json"
  export GOLDEN

  WORK="$(mktemp -d)"
  export WORK
  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
}

teardown() {
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# ── the shared fixture set ───────────────────────────────────────────────────
#
# svc_fixture_yaml <case> emits the `services:` block for that case. It is the
# SINGLE source: the bash validator reads it as YAML, the schema reads the JSON
# yq derives from it.
svc_fixture_yaml() {
  case "$1" in
    valid_full) cat <<'YAML'
services:
  postgres:
    start_cmd: "docker compose up postgres"
    probe_cmd: "pg_isready -h 127.0.0.1"
    stop_cmd: "docker compose stop postgres"
    startup_deadline_seconds: 60
    max_lifetime_seconds: 3600
    log_hint: "docker compose logs postgres"
    restart_authorized: true
    port_env: PGPORT_E2E
  shared_db:
    start_cmd: "true"
    probe_cmd: "true"
    startup_deadline_seconds: 5
YAML
      ;;
    valid_minimal) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "curl -sf localhost:3000/health"
    startup_deadline_seconds: 30
YAML
      ;;
    missing_probe_cmd) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    startup_deadline_seconds: 30
YAML
      ;;
    missing_start_cmd) cat <<'YAML'
services:
  api:
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    missing_deadline) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
YAML
      ;;
    unknown_field) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    healthcheck_cmd: "true"
YAML
      ;;
    bad_restart_authorized) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    restart_authorized: "yes"
YAML
      ;;
    deadline_zero) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 0
YAML
      ;;
    deadline_not_int) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: "30"
YAML
      ;;
    empty_start_cmd) cat <<'YAML'
services:
  api:
    start_cmd: ""
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    bad_port_env) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: "8080-PORT"
YAML
      ;;
    bad_service_name) cat <<'YAML'
services:
  Postgres Main:
    start_cmd: "true"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    not_a_map) cat <<'YAML'
services: "postgres"
YAML
      ;;
    denied_port_env_path) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: PATH
YAML
      ;;
    denied_port_env_ld) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: LD_PRELOAD
YAML
      ;;
    # The case variant is ACCEPTED, deliberately: env var names are
    # case-sensitive, `Path` is not `PATH`, and nothing honours it — refusing it
    # would be a false refusal. This row is what makes the denylist's
    # case-sensitivity a tested decision instead of an accident.
    allowed_port_env_case_variant) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: Path
YAML
      ;;
    background_start_cmd) cat <<'YAML'
services:
  api:
    start_cmd: "npm start &"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    nohup_start_cmd) cat <<'YAML'
services:
  api:
    start_cmd: "nohup npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    # Over-match guard: `&&` is a chain, not a background.
    chained_start_cmd) cat <<'YAML'
services:
  api:
    start_cmd: "npm run build && npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    # The row that actually pins the `(^|[^&])` half of the trailing-& rule: a
    # command ENDING in `&&`. Both authorities accept it, deliberately — it is a
    # shell syntax error for the shell to report, not a backgrounding form, and
    # this lint refuses to mis-blame it as one. Without this row, loosening the
    # rule to a bare `&$` would go unnoticed.
    trailing_double_amp) cat <<'YAML'
services:
  api:
    start_cmd: "npm start &&"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
      ;;
    dup_port_env) cat <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: APP_PORT
  worker:
    start_cmd: "npm run worker"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: APP_PORT
YAML
      ;;
    *) echo "unknown fixture: $1" >&2; return 1 ;;
  esac
}

# svc_cases — the table. Fields, tab-separated:
#   case | bash verdict | schema verdict | substrings the bash error must name
#
# `dup_port_env` is the ONE row where the two verdicts differ, and it differs
# for a stated reason: JSON Schema has no way to require uniqueness across
# sibling property VALUES, so the schema accepts it and the runtime validator
# refuses it. Naming it here is what keeps it a known, tested divergence
# instead of a silent hole.
svc_cases() {
  cat <<'TABLE'
valid_full	valid	valid
valid_minimal	valid	valid
missing_probe_cmd	invalid	invalid	api|probe_cmd|missing required field
missing_start_cmd	invalid	invalid	api|start_cmd|missing required field
missing_deadline	invalid	invalid	api|startup_deadline_seconds|missing required field
unknown_field	invalid	invalid	api|healthcheck_cmd|unknown field
bad_restart_authorized	invalid	invalid	api|restart_authorized|true or false
deadline_zero	invalid	invalid	api|startup_deadline_seconds|integer >= 1
deadline_not_int	invalid	invalid	api|startup_deadline_seconds|integer >= 1
empty_start_cmd	invalid	invalid	api|start_cmd|non-empty string
bad_port_env	invalid	invalid	api|port_env|environment variable name
denied_port_env_path	invalid	invalid	api|port_env|PATH|reserved variable
denied_port_env_ld	invalid	invalid	api|port_env|LD_PRELOAD|reserved variable
allowed_port_env_case_variant	valid	valid
background_start_cmd	invalid	invalid	api|start_cmd|FOREGROUND|trailing '&'
nohup_start_cmd	invalid	invalid	api|start_cmd|FOREGROUND|nohup
chained_start_cmd	valid	valid
trailing_double_amp	valid	valid
bad_service_name	invalid	invalid	Postgres Main|invalid service name
not_a_map	invalid	invalid	must be a map
dup_port_env	invalid	valid	api|worker|APP_PORT|one env var, one owner
TABLE
}

# run_bash_validator <yaml_file> — the REAL function from the REAL script,
# reached through the script's documented source mode. Nothing re-implemented.
run_bash_validator() {
  bash -c '
    set -euo pipefail
    source "$1" >/dev/null 2>&1 || true
    _validate_services_config "$2"
  ' _ "$RUN_GATES" "$1"
}

_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# run_schema_validator <yaml_file> — the JSON the schema sees is DERIVED from
# the same YAML fixture by yq, so there is no second copy of any fixture.
run_schema_validator() {
  yq -o=json '.services' "$1" > "$WORK/svc.json"
  python3 - "$SCHEMA" "$WORK/svc.json" <<'PY'
import json, sys
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
errs = sorted(Draft202012Validator(schema).iter_errors(inst), key=lambda e: e.path)
for e in errs:
    print(f"{list(e.path)}: {e.message}")
sys.exit(1 if errs else 0)
PY
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: shared fixture set — the bash validator matches the table on every case" {
  local name want _schema_want subs failures="" n=0
  while IFS=$'\t' read -r name want _schema_want subs; do
    [[ -z "$name" ]] && continue
    n=$(( n + 1 ))
    svc_fixture_yaml "$name" > "$WORK/exec.yaml"

    if run_bash_validator "$WORK/exec.yaml" >"$WORK/out.txt" 2>"$WORK/err.txt"; then
      got="valid"
    else
      got="invalid"
    fi
    [[ "$got" == "$want" ]] || failures+="  ${name}: bash said ${got}, table says ${want}"$'\n'

    if [[ "$want" == "invalid" && -n "$subs" ]]; then
      local err; err="$(cat "$WORK/err.txt")"
      local IFS='|' s
      for s in $subs; do
        [[ "$err" == *"$s"* ]] || failures+="  ${name}: error does not name '${s}' (got: ${err})"$'\n'
      done
    fi
  done < <(svc_cases)

  # Vacuity guard: a table this loop never read would otherwise "pass".
  [ "$n" -eq 21 ]

  if [[ -n "$failures" ]]; then
    echo "bash validator disagreed with the shared fixture table:"
    echo "$failures"
    return 1
  fi
}

@test "case 2: shared fixture set — the JSON Schema matches the table on every case" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local name _bash_want want _subs failures="" n=0
  while IFS=$'\t' read -r name _bash_want want _subs; do
    [[ -z "$name" ]] && continue
    n=$(( n + 1 ))
    svc_fixture_yaml "$name" > "$WORK/exec.yaml"

    if run_schema_validator "$WORK/exec.yaml" >"$WORK/schema-out.txt" 2>&1; then
      got="valid"
    else
      got="invalid"
    fi
    [[ "$got" == "$want" ]] || \
      failures+="  ${name}: schema said ${got}, table says ${want} ($(cat "$WORK/schema-out.txt"))"$'\n'
  done < <(svc_cases)

  [ "$n" -eq 21 ]

  if [[ -n "$failures" ]]; then
    echo "JSON Schema disagreed with the shared fixture table:"
    echo "$failures"
    return 1
  fi
}

@test "case 3: drift guard — exactly one documented divergence between the two authorities" {
  local name bwant swant _subs diverged=()
  while IFS=$'\t' read -r name bwant swant _subs; do
    [[ -z "$name" ]] && continue
    [[ "$bwant" == "$swant" ]] || diverged+=("$name")
  done < <(svc_cases)

  # If a future edit makes the schema and the validator disagree on anything
  # else, this fails — which is the whole reason the table carries BOTH
  # verdicts instead of one.
  [ "${#diverged[@]}" -eq 1 ]
  [ "${diverged[0]}" = "dup_port_env" ]

  # And the schema file says so, in the field that carries the constraint.
  run jq -r '.["$defs"].service.properties.port_env.description' "$SCHEMA"
  [[ "$output" == *"not expressible in JSON Schema"* ]]
  [[ "$output" == *"_validate_services_config"* ]]
}

@test "case 3b: the port_env denylist has ONE definition and both consumers read it" {
  local DENYLIST="$PLUGIN_ROOT/scripts/lib/aid-env-name-denylist.sh"
  [ -f "$DENYLIST" ]

  # Every exact name the schema enumerates must be denied by the shared list.
  # This is the drift guard that matters now that the runtime check exists at
  # two altitudes: declaration time (aid-run-gates.sh) and export time
  # (lib/aid-service.sh). One list, or it drifts — and it did.
  cat > "$WORK/deny-probe.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
source "$1"; shift
for v in "$@"; do
  if aid_env_name_denied "$v"; then printf '%s DENIED\n' "$v"; else printf '%s ALLOWED\n' "$v"; fi
done
EOS
  mapfile -t enumerated < <(jq -r '.["$defs"].service.properties.port_env.allOf[]?.not.enum[]?' "$SCHEMA")
  [ "${#enumerated[@]}" -ge 30 ]

  run bash "$WORK/deny-probe.sh" "$DENYLIST" "${enumerated[@]}" \
      LD_PRELOAD DYLD_INSERT_LIBRARIES BASH_FUNC_x%% AID_ANYTHING \
      SVC_PORT APP_PORT Path
  [ "$status" -eq 0 ]
  local v
  for v in "${enumerated[@]}"; do
    [[ "$output" == *"$v DENIED"* ]] || { echo "not denied: $v"; return 1; }
  done
  for v in LD_PRELOAD DYLD_INSERT_LIBRARIES 'BASH_FUNC_x%%' AID_ANYTHING; do
    [[ "$output" == *"$v DENIED"* ]] || { echo "family not denied: $v"; return 1; }
  done
  # ... and the names that must still be usable, including the case variant the
  # table deliberately accepts.
  for v in SVC_PORT APP_PORT Path; do
    [[ "$output" == *"$v ALLOWED"* ]] || { echo "false refusal: $v"; return 1; }
  done

  # Neither consumer may carry an enumeration of its own.
  run grep -c 'PYTHONSTARTUP' "$RUN_GATES"
  [ "$output" = "0" ]
  run grep -c 'PYTHONSTARTUP' "$PLUGIN_ROOT/scripts/lib/aid-service.sh"
  [ "$output" = "0" ]
  run grep -c 'aid_env_name_denied' "$RUN_GATES"
  [ "$output" -ge 1 ]
  run grep -c 'aid_env_name_denied' "$PLUGIN_ROOT/scripts/lib/aid-service.sh"
  [ "$output" -ge 1 ]
}

@test "case 4: a service missing probe_cmd fails validation naming the field" {
  svc_fixture_yaml missing_probe_cmd > "$WORK/exec.yaml"

  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"service 'api'"* ]]
  [[ "$output" == *"probe_cmd"* ]]

  _have_jsonschema || skip "python3 + jsonschema unavailable (schema half only)"
  run run_schema_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"probe_cmd"* ]]
}

@test "case 5: two services declaring the same port_env are refused, naming both and the var" {
  svc_fixture_yaml dup_port_env > "$WORK/exec.yaml"

  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"APP_PORT"* ]]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"worker"* ]]
  [[ "$output" == *"one env var, one owner"* ]]
}

@test "case 6: GOLDEN — an execution.yaml with no services block is byte-identical to the pre-P076 report" {
  [ -f "$GOLDEN" ]
  GPROJ="$WORK/golden"
  mkdir -p "$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates"
  git -C "$GPROJ" init -q
  git -C "$GPROJ" config user.email golden@example.com
  git -C "$GPROJ" config user.name Golden
  printf 'golden fixture\n' > "$GPROJ/README.md"
  printf '.aid-o/\n' > "$GPROJ/.gitignore"
  git -C "$GPROJ" add README.md .gitignore
  git -C "$GPROJ" commit -qm "golden fixture base"
  cat > "$GPROJ/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: true
    timeout_seconds: 30
  beta:
    command: "printf 'beta-ok'"
    required: false
    timeout_seconds: 30
  gamma:
    command: "echo gamma-broke >&2; exit 1"
    required: false
    timeout_seconds: 30
  delta_nocmd:
    required: false
YAML

  ( cd "$GPROJ" && "$RUN_GATES" run-all exec.yaml E-P076 R-1 \
      --report-file ".aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" \
      >/dev/null 2>"$WORK/golden.err" ) || true

  [ -f "$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" ]
  jq -S '
      .completed_at = "NORMALIZED"
    | ._generated_at = "NORMALIZED"
    | .revision.head_sha = "NORMALIZED"
    | .gates |= with_entries(
        if (.value | type) == "object" then
          .value |= (
              (if has("duration_ms") then .duration_ms = 0 else . end)
            | (if (.runtime_baseline | type) == "object"
               then .runtime_baseline.p95_ms = 0 else . end)
          )
        else . end)
    | ._command_log |= map(.duration_ms = 0)
  ' "$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" > "$WORK/golden-actual.json"

  run diff -u "$GOLDEN" "$WORK/golden-actual.json"
  [ "$status" -eq 0 ]
}

@test "case 7: the REAL runner refuses a malformed services block before any gate command is spawned" {
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.aid-o/work/evidence/E-SVC/R-1/gates"
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email svc@example.com
  git -C "$PROJ" config user.name Svc
  printf 'svc fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  git -C "$PROJ" add README.md .gitignore
  git -C "$PROJ" commit -qm "svc fixture base"

  # `early` would leave a marker if it ever ran. The bad declaration is in a
  # block the runner reaches BEFORE gates, so nothing must be spawned.
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  early:
    command: "touch '$WORK/early-ran'"
    required: false
    timeout_seconds: 30
services:
  api:
    start_cmd: "npm start"
    startup_deadline_seconds: 30
YAML

  run bash -c "cd '$PROJ' && '$RUN_GATES' run-all exec.yaml E-SVC R-1 \
      --report-file '.aid-o/work/evidence/E-SVC/R-1/gates/gates_report.json' 2>&1"
  [ "$status" -ne 0 ]
  [ ! -f "$WORK/early-ran" ]
  [ ! -f "$PROJ/.aid-o/work/evidence/E-SVC/R-1/gates/gates_report.json" ]
  [[ "$output" == *"service 'api'"* ]]
  [[ "$output" == *"probe_cmd"* ]]
}

@test "case 8: the shipped template documents services as commentary with ZERO active services" {
  [ -f "$TEMPLATE" ]

  # (a) No active services block at all — the parsed document has no key.
  run yq 'has("services")' "$TEMPLATE"
  [ "$output" = "false" ]

  # (b) The commentary IS there, and carries a complete worked example.
  run grep -c '^# services:' "$TEMPLATE"
  [ "$output" -eq 1 ]
  for field in start_cmd probe_cmd stop_cmd startup_deadline_seconds \
               max_lifetime_seconds log_hint restart_authorized port_env; do
    run grep -q "^#.*${field}" "$TEMPLATE"
    [ "$status" -eq 0 ]
  done

  # (c) Every line of the block is a comment — nothing there can ever start.
  run bash -c "sed -n '/^# ─── Services/,/^# ─── Retry/p' '$TEMPLATE' | grep -vc '^\(#\|\$\)'"
  [ "$output" -eq 0 ]

  # (d) Uncommenting the worked example yields a declaration BOTH authorities
  #     accept — documentation that does not validate is not documentation.
  sed -n '/^# services:/,/^#     port_env:/p' "$TEMPLATE" | sed 's/^# \{0,1\}//' > "$WORK/example.yaml"
  run run_bash_validator "$WORK/example.yaml"
  [ "$status" -eq 0 ]
  run yq '.services | keys | length' "$WORK/example.yaml"
  [ "$output" -eq 1 ]
}

@test "case 9: port_env may not name a runtime-significant variable, and the case variant still may" {
  # Exact, case-sensitive denial — the refusal names service, field and variable.
  svc_fixture_yaml denied_port_env_path > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"service 'api'"* ]]
  [[ "$output" == *"port_env"* ]]
  [[ "$output" == *"PATH"* ]]

  # Prefix denial — LD_PRELOAD is not enumerated anywhere, LD_ is.
  svc_fixture_yaml denied_port_env_ld > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"LD_PRELOAD"* ]]

  # An unenumerated member of the same family is denied too — that is the whole
  # reason the family is a prefix and not a list.
  cat > "$WORK/exec.yaml" <<'YAML'
services:
  api:
    start_cmd: "npm start"
    probe_cmd: "true"
    startup_deadline_seconds: 30
    port_env: LD_AUDIT
YAML
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"LD_AUDIT"* ]]

  # And the case variant is ACCEPTED: `Path` is not `PATH`, nothing honours it,
  # so refusing it would cost a false refusal and buy nothing.
  svc_fixture_yaml allowed_port_env_case_variant > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -eq 0 ]

  _have_jsonschema || skip "python3 + jsonschema unavailable (schema half only)"
  svc_fixture_yaml denied_port_env_path > "$WORK/exec.yaml"
  run run_schema_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  svc_fixture_yaml allowed_port_env_case_variant > "$WORK/exec.yaml"
  run run_schema_validator "$WORK/exec.yaml"
  [ "$status" -eq 0 ]
}

@test "case 10: start_cmd backgrounding is refused, and the refusal states what the check cannot see" {
  svc_fixture_yaml background_start_cmd > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"service 'api'"* ]]
  [[ "$output" == *"start_cmd"* ]]
  [[ "$output" == *"FOREGROUND"* ]]
  # Honesty clause: the message must not imply the check is complete.
  [[ "$output" == *"syntactic"* ]]
  [[ "$output" == *"daemonises internally"* ]]

  svc_fixture_yaml nohup_start_cmd > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nohup"* ]]

  # setsid / disown are caught by the same word check.
  local form
  for form in "setsid npm start" "npm start; disown x"; do
    cat > "$WORK/exec.yaml" <<YAML
services:
  api:
    start_cmd: "$form"
    probe_cmd: "true"
    startup_deadline_seconds: 30
YAML
    run run_bash_validator "$WORK/exec.yaml"
    [ "$status" -ne 0 ]
  done

  # Over-match guard: `&&` is a chain, not a background.
  svc_fixture_yaml chained_start_cmd > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -eq 0 ]

  # And the documented limit is documented where a reader will meet it: the
  # schema's own start_cmd description says what the lint cannot see.
  run jq -r '.["$defs"].service.properties.start_cmd.description' "$SCHEMA"
  [[ "$output" == *"SYNTACTIC"* ]]
  [[ "$output" == *"daemonises INSIDE itself"* ]]
  [[ "$output" == *"TERMINAL job whose probe still reports healthy"* ]]
}

@test "case 11: fail-closed — 'could not look' is exit 2, 'nothing to validate' is a silent exit 0" {
  # Nothing to validate: exit 0, no output, no work.
  printf 'gates: {}\n' > "$WORK/nosvc.yaml"
  run run_bash_validator "$WORK/nosvc.yaml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # An empty services block is still "nothing to validate".
  printf 'services:\n' > "$WORK/emptysvc.yaml"
  run run_bash_validator "$WORK/emptysvc.yaml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Could not look, three ways — each one is 2, none of them is 0.
  run run_bash_validator "$WORK/does-not-exist.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"file not found"* ]]

  printf 'services:\n  api:\n   - [unbalanced\n' > "$WORK/broken.yaml"
  run run_bash_validator "$WORK/broken.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot parse"* ]]

  # yq unavailable: sourced with a normal PATH, then invoked without one.
  run bash -c '
    set -euo pipefail
    source "$1" >/dev/null 2>&1 || true
    PATH=/nonexistent-aid-path
    _validate_services_config "$2"
  ' _ "$RUN_GATES" "$WORK/nosvc.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"yq is not available"* ]]
}

@test "case 12: a service name containing a newline is refused for being one" {
  printf 'services:\n  "api\\nevil":\n    start_cmd: "true"\n    probe_cmd: "true"\n    startup_deadline_seconds: 30\n' \
    > "$WORK/exec.yaml"
  run run_bash_validator "$WORK/exec.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"service name contains a newline"* ]]
  # The old, misleading diagnosis must be gone.
  [[ "$output" != *"declaration must be a map"* ]]
}
