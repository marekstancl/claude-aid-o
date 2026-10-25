#!/usr/bin/env bats
# aid-tier: t0
# aid-subject: scripts/tests/lib/opt-value-guard.py
# An option given without its value. Defect it catches: `shift 2` with one argument left shifts nothing and
# returns 1; a script without `set -e` then loops forever on 100 % CPU (aid-plan-check.sh --json, WAN P115,
# 25. 10. 2026: 11 minutes), one with `set -u` dies on `$2: unbound variable` with no word on what is missing.
# The guard has to stand BEFORE the value is read, so these tests call real scripts, not only grep them.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
}

@test "every shift 2 in the plugin's scripts has a two-argument check before it" {
  run python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$AID_PLUGIN_PATH"
  [ "$status" -eq 0 ] || { echo "$output"; echo "fix: python3 scripts/tests/lib/opt-value-guard.py <plugin> --fix"; false; }
}

@test "the checker finds an unguarded site and --fix guards it before the value is read" {
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/scripts/lib"
  printf '#!/usr/bin/env bash\nset -u\nwhile [[ $# -gt 0 ]]; do\n  case "$1" in\n    --out) OUT="$2"; shift 2 ;;\n    *) shift ;;\n  esac\ndone\necho "out=$OUT"\n' > "$P/scripts/x.sh"
  run python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"UNGUARDED scripts/x.sh:5"* ]]
  python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$P" --fix
  run timeout 5 bash "$P/scripts/x.sh" --out
  [ "$status" -eq 2 ]; [[ "$output" == *"--out needs a value"* ]]
  run bash "$P/scripts/x.sh" --out f
  [ "$status" -eq 0 ]; [ "$output" = "out=f" ]
}

@test "the checker does not accept a read before the guard, an unlisted '|| true' or a stale exception" {
  P="$BATS_TEST_TMPDIR/q"; mkdir -p "$P/scripts"
  printf '#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do\n  case "$1" in\n    --a) A="$2"; [[ $# -ge 2 ]] || exit 2; shift 2 ;;\n    --b) B="${2:-}"; shift 2 || true ;;\n    --c) C="${2:-}"; shift 2 2>/dev/null ;;\n    *) shift ;;\n  esac\ndone\n' > "$P/scripts/y.sh"
  run python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNGUARDED scripts/y.sh:4"* ]]
  [[ "$output" == *"UNGUARDED scripts/y.sh:5"* ]]
  [[ "$output" == *"UNGUARDED scripts/y.sh:6"* ]]
}

@test "an inserted guard with any other action than return-or-exit is reported" {
  P="$BATS_TEST_TMPDIR/r"; mkdir -p "$P/scripts"
  printf '#!/usr/bin/env bash\ng() {\n  case "$1" in\n    --x) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; exit 2; }; X="$2"; shift 2 ;;\n  esac\n}\n' > "$P/scripts/z.sh"
  run python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"WRONG-ACTION scripts/z.sh:4"* ]]
}

@test "aid-review-round.sh (no set -e, guards at top level) stops with code 2 instead of looping" {
  cd "$BATS_TEST_TMPDIR"
  run timeout 5 bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" x --plan
  [ "$status" -eq 2 ]; [[ "$output" == *"--plan needs a value"* ]]; [[ "$output" != *"can only"* ]]
}

@test "aid-plan-check.sh --json without a value stops at once with code 2 and names the option" {
  cd "$BATS_TEST_TMPDIR"
  run timeout 5 bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" /dev/null --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"--json needs a value"* ]]
}

@test "a set -u script reading a bare \$2 says which option needs a value (not 'unbound variable')" {
  cd "$BATS_TEST_TMPDIR"
  run timeout 5 bash "$AID_PLUGIN_PATH/scripts/aid-job.sh" run --id
  [ "$status" -eq 2 ]
  [[ "$output" == *"--id needs a value"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "a guarded library exits 2 when run as a program and returns 2 to a caller that sourced it" {
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/scripts/lib"
  printf '#!/usr/bin/env bash\nset -u\nf() {\n  while [[ $# -gt 0 ]]; do\n    case "$1" in\n      --k) K="$2"; shift 2 ;;\n      *) shift ;;\n    esac\n  done\n}\nwhile [[ $# -gt 0 ]]; do\n  case "$1" in\n    --top) T="$2"; shift 2 ;;\n    *) shift ;;\n  esac\ndone\n' > "$P/scripts/lib/l.sh"
  python3 "$AID_PLUGIN_PATH/scripts/tests/lib/opt-value-guard.py" "$P" --fix
  run timeout 5 bash "$P/scripts/lib/l.sh" --top
  [ "$status" -eq 2 ]; [[ "$output" == *"--top needs a value"* ]]
  run bash -c "source '$P/scripts/lib/l.sh'; f --k; echo \"rc=\$? caller alive\""
  [ "$status" -eq 0 ]; [[ "$output" == *"--k needs a value"* ]]; [[ "$output" == *"rc=2 caller alive"* ]]
}

@test "a library function with two required arguments returns 2 and its caller goes on" {
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh"; log_event only-one; echo "rc=$? caller alive"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs 2 arguments"* ]]
  [[ "$output" == *"rc=2 caller alive"* ]]
}
