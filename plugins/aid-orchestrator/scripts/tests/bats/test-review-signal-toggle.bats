#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 6 — _aid_read_toggle must not fail open when it cannot evaluate a
# toggle. The original implementation used `grep -qP` twice; on any grep
# without PCRE support both calls exit 2 and the surrounding `if` silently
# read that as "enabled" — a fail-open on production library code. Rewritten
# in bash's own `[[ =~ ]]`, with no external grep dependency for this check
# at all, so a grep lacking `-P` cannot make this fail open again.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SIGNALS="$AID_PLUGIN_PATH/scripts/lib/aid-review-signals.sh"
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  RELEASE_POLICY="$AID_PLUGIN_PATH/scripts/aid-release-policy.sh"
  export SIGNALS FSM RELEASE_POLICY
}

teardown() {
  teardown_test_evidence_dir
}

# _read_toggle <exec_yaml> <section> — echoes "0"/"1"/"2" (the function's own
# exit code) via `run`, isolated from the parent shell.
_read_toggle() {
  run bash -c 'source "$1"; _aid_read_toggle "$2" "$3"' aid-review-signals "$SIGNALS" "$1" "$2"
}

# A stub grep in PATH that exits 2 on -P (simulates a grep built without
# PCRE support) and delegates every other invocation to the real grep. If
# _aid_read_toggle called grep -P anywhere, it would now fail open exactly
# as the pre-fix implementation did; this proves it does not.
_stub_grep_no_pcre() {
  local stub_dir="$TEST_TMPDIR/stub-bin"
  mkdir -p "$stub_dir"
  local real_grep; real_grep="$(command -v grep)"
  cat > "$stub_dir/grep" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    -*P*) exit 2 ;;
  esac
done
exec "$real_grep" "\$@"
EOF
  chmod +x "$stub_dir/grep"
  export PATH="$stub_dir:$PATH"
}

@test "enabled: false disables, even with a grep that rejects -P in PATH" {
  _stub_grep_no_pcre
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  enabled: false
EOF
  _read_toggle "$exec_yaml" "simplifier"
  [ "$status" -eq 1 ]
}

@test "enabled: true enables, even with a grep that rejects -P in PATH" {
  _stub_grep_no_pcre
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  enabled: true
EOF
  _read_toggle "$exec_yaml" "simplifier"
  [ "$status" -eq 0 ]
}

@test "an unparseable enabled value fails with a named message, never resolving to enabled" {
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  enabled: maybe
EOF
  _read_toggle "$exec_yaml" "simplifier"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not 'true' or 'false'"* ]]
  [[ "$output" == *"$exec_yaml"* ]]
  [[ "$output" == *"simplifier"* ]]
}

@test "an unreadable file fails with a named message, never resolving to enabled" {
  [[ "$EUID" -eq 0 ]] && skip "root bypasses file permissions — chmod 000 stays readable"
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  enabled: false
EOF
  chmod 000 "$exec_yaml"
  _read_toggle "$exec_yaml" "simplifier"
  local rc="$status"
  chmod 644 "$exec_yaml"   # restore so teardown can clean up
  [ "$rc" -eq 2 ]
}

@test "toggle absent entirely applies the documented default (enabled)" {
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
some_other_section:
  enabled: false
EOF
  _read_toggle "$exec_yaml" "simplifier"
  [ "$status" -eq 0 ]
}

@test "section present with no enabled key applies the default (enabled)" {
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  some_other_key: value
EOF
  _read_toggle "$exec_yaml" "simplifier"
  [ "$status" -eq 0 ]
}

@test "missing execution.yaml applies the default (enabled), byte-identical to before" {
  _read_toggle "$TEST_TMPDIR/does-not-exist.yaml" "simplifier"
  [ "$status" -eq 0 ]
}

# ─── Call-site contract: unreadable must survive as a DISTINCT state ──────

@test "aid-fsm.sh call site: an unreadable toggle fails CLOSED (does not disable a plan-boundary check)" {
  # fsm_eval_simplifier_present treats rc=1 (disabled) as null/N-A. An
  # unreadable toggle (rc=2) must NOT also read as null — it falls through
  # and the measurement runs as if enabled.
  local exec_yaml="$TEST_TMPDIR/execution.yaml"
  local evidence_dir="$TEST_TMPDIR/evidence"
  mkdir -p "$evidence_dir"
  touch "$evidence_dir/ca-review-complete"
  cat > "$exec_yaml" <<'EOF'
simplifier:
  enabled: maybe
EOF
  run bash -c '
    source "'"$FSM"'"
    project_root="'"$TEST_TMPDIR"'"
    fsm_eval_simplifier_present "E-test" "'"$evidence_dir"'" "'"$TEST_TMPDIR"'"
  '
  [ "$status" -eq 0 ]
  # Not null (which would mean "disabled, not applicable") — falls through
  # to the normal file-existence measurement (false: report missing).
  [ "$output" = "false" ]
}

@test "aid-release-policy.sh call sites: both compute_reporter and compute_simplifier report toggle_unreadable, guarded on rc==2" {
  # aid-release-policy.sh runs `main "$@"` unconditionally at file scope (no
  # source guard), so its functions cannot be unit-tested by sourcing — this
  # asserts the wiring statically: both call sites branch on the toggle's
  # rc==2 case and report a status distinct from "disabled", rather than
  # exercising the full aggregator (which needs a heavyweight fixture pack —
  # see test-release-policy.bats for that harness).
  run grep -c 'toggle_unreadable' "$RELEASE_POLICY"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
  run grep -c '_toggle_rc" -eq 2' "$RELEASE_POLICY"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}
