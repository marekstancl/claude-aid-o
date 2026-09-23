#!/usr/bin/env bats
# aid-tier: t0
# test-codex-transport.bats — lib/aid-codex-transport.sh: the one way AID talks
# to the Codex CLI. What its callers rely on and nothing asserts elsewhere: the
# process is read-only and rooted in the project, the prompt arrives whole on
# stdin, the effort is configurable, the exit code is the CLI's, and sourcing the file changes nothing in the caller's shell.

setup() {
  LIB="$(cd "$BATS_TEST_DIRNAME/../../lib" && pwd)/aid-codex-transport.sh"
  T="$(mktemp -d)"; mkdir -p "$T/bin" "$T/project"
  cat > "$T/bin/codex" <<'SPY'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && { echo "codex-cli 9.9.9"; exit 0; }
printf '%s\n' "$@" > "$SPY_ARGS"
cat > "$SPY_STDIN"
echo '{"type":"turn.completed"}'
exit "${SPY_RC:-0}"
SPY
  chmod +x "$T/bin/codex"
  export AID_CODEX_BIN="$T/bin/codex" SPY_ARGS="$T/args" SPY_STDIN="$T/stdin"
  echo "say hi" > "$T/prompt.md"
}
teardown() { [[ -n "${T:-}" ]] && find "$T" -delete; }

@test "one read-only process rooted in the project, with the configured model and effort and the prompt on stdin" {
  head -c 200000 /dev/zero | tr '\0' 'x' > "$T/prompt.md"
  run bash -c "source '$LIB'; CODEX_MODEL=test-model CODEX_EFFORT=low; _run_codex_isolated '$T/project' '$T/prompt.md' '$T/events' '$T/err' '$T/last'"
  [ "$status" -eq 0 ]
  grep -qx -- "--sandbox" "$SPY_ARGS"; grep -qx "read-only" "$SPY_ARGS"
  grep -qx -- "--cd" "$SPY_ARGS";      grep -qx "$T/project" "$SPY_ARGS"
  grep -qx "test-model" "$SPY_ARGS";   grep -qx 'model_reasoning_effort=low' "$SPY_ARGS"
  [ "$(tail -n1 "$SPY_ARGS")" = "-" ]; cmp -s "$T/prompt.md" "$SPY_STDIN"
  ! grep -q -- "--output-schema" "$SPY_ARGS"
  grep -q turn.completed "$T/events"
}

@test "the CLI's exit code is returned, and sourcing sets no shell option and no SCRIPT_DIR" {
  SPY_RC=7 run bash -c "source '$LIB'; _run_codex_isolated '$T/project' '$T/prompt.md' '$T/events' '$T/err' '$T/last'"
  [ "$status" -eq 7 ]
  run bash -c "before=\$(set +o); source '$LIB'; [[ \"\$before\" == \"\$(set +o)\" && -z \"\${SCRIPT_DIR:-}\" && -z \"\${PLUGIN_ROOT:-}\" ]]"
  [ "$status" -eq 0 ]
}
