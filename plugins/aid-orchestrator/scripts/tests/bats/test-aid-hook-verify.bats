#!/usr/bin/env bats
# aid-tier: t0
# test-aid-hook-verify.bats — the canary (P086 Step 2).
#
# THE GROUNDED FAILURE MODE: both harnesses fail silently and in opposite
# directions. Codex skips an unapproved hook without a word; Claude Code runs a
# hook that crashed and carries on. So "the hook file is in place" is never
# evidence, and a layer that claims enforcement on that basis is claiming
# something nobody checked.
#
# HOW THE TOOLS ARE STOOD IN FOR: a `claude` / `codex` shim on PATH, not an
# environment switch inside the code under test. The shims speak the two real
# protocols — Claude Code's `--include-hook-events` stream, and the
# `codex app-server` JSON-RPC that answers `hooks/list` — so what is exercised
# is the parsing that will meet the real tools, and the Codex path runs the
# actual trust helper rather than a stand-in for it.
#
# WHAT IS NOT PROVED HERE: that a real Claude Code or a real Codex calls AID.
# Nothing offline can prove that — it is the very question the canary exists to
# ask at deployment time.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  VERIFY="$PLUGIN_ROOT/scripts/aid-hook-verify.sh"
  TMP="$(mktemp -d)"
  BIN="$TMP/bin"; mkdir -p "$BIN"
  TRUST="$TMP/trust.json"
  export AID_HOOK_TRUST_FILE="$TRUST"
  export AID_SESSION_STORE="$TMP/state"
  export CODEX_HOME="$TMP/codex-home"; mkdir -p "$CODEX_HOME"
  PATH_BEFORE="$PATH"
}

teardown() {
  export PATH="$PATH_BEFORE"
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

# fake_claude <version> <hook_outcome> <leaves_audit_line> [audit_outcome]
#   <leaves_audit_line> "yes" writes the line AID's dispatcher would write for
#   its canary rule; [audit_outcome] overrides what that line records, so a
#   canary that RAN AND CRASHED can be told apart from one that did its job.
fake_claude() {
  cat > "$BIN/claude" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "--version" ]] && { echo "$1 (Claude Code)"; exit 0; }
echo '{"type":"system","subtype":"hook_started","hook_name":"SessionStart"}'
echo '{"type":"system","subtype":"hook_response","hook_name":"SessionStart","exit_code":0,"outcome":"$2"}'
if [[ "$3" == "yes" && -n "\${AID_HOOK_AUDIT:-}" ]]; then
  printf '{"ts":"now","event":"SessionStart","rule":"hook_canary","outcome":"${4:-skip}"}\n' >> "\$AID_HOOK_AUDIT"
fi
exit 0
EOF
  chmod +x "$BIN/claude"
  export PATH="$BIN:$PATH_BEFORE"
  export AID_HOOK_TOOL=claude-code
}

# fake_codex <version> <trust_status> <leaves_audit_line>
#   `app-server` answers hooks/list over JSON-RPC; `exec` runs the session.
fake_codex() {
  cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "codex-cli $1"; exit 0 ;;
  app-server) exec python3 "$TMP/app-server.py" ;;
  exec)
    if [[ "$3" == "yes" && -n "\${AID_HOOK_AUDIT:-}" ]]; then
      printf '{"ts":"now","event":"SessionStart","rule":"hook_canary","outcome":"${4:-skip}"}\n' >> "\$AID_HOOK_AUDIT"
    fi
    echo ok; exit 0 ;;
esac
exit 0
EOF
  # `--version` is matched before the positional rewrite above, so print it plainly.
  sed -i "s|echo \"codex-cli \$1\"|echo \"codex-cli $1\"|" "$BIN/codex"
  cat > "$TMP/app-server.py" <<EOF
import json, sys
for line in sys.stdin:
    try: msg = json.loads(line)
    except ValueError: continue
    if msg.get("method") == "hooks/list":
        print(json.dumps({"jsonrpc":"2.0","id":2,"result":{"data":[
            {"hooks":[{"key":"$CODEX_HOME/config.toml:session_start:0:0",
                       "currentHash":"sha256:abc","eventName":"SessionStart",
                       "command":"aid-hook.sh SessionStart","isManaged":False,
                       "trustStatus":"$2"}]}]}}), flush=True)
        break
EOF
  chmod +x "$BIN/codex"
  export PATH="$BIN:$PATH_BEFORE"
  export AID_HOOK_TOOL=codex
}

@test "AC5: the canary passes only when AID's own rule really ran" {
  fake_claude 2.1.226 success yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 0 ]
  [ "$(jq -r .verified "$TRUST")" = "true" ]
  [ "$(jq -r .state "$TRUST")" = "verified" ]
}

@test "AC5: hooks that run without AID among them are NOT a pass" {
  fake_claude 2.1.226 success no
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .verified "$TRUST")" = "false" ]
  [ "$(jq -r .state "$TRUST")" = "not_covered" ]
  [[ "$(jq -r .detail "$TRUST")" == *"not loaded"* ]]
}

@test "a hook that ran and errored is not counted as a successful one" {
  fake_claude 2.1.226 error no
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "not_covered" ]
}

@test "AC5: a canary rule that RAN AND CRASHED is not a pass — the line alone proves nothing" {
  # The dispatcher audits a broken rule too. Counting audit lines rather than
  # successful ones would let a broken hook layer certify itself.
  fake_claude 2.1.226 success yes error
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "not_covered" ]
}

@test "AC7: the verdict carries the tool version" {
  fake_claude 2.1.226 success yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$(jq -r .version "$TRUST")" = "2.1.226" ]
  [ "$(jq -r .tool "$TRUST")" = "claude-code" ]
  [ "$(jq -r .unmeasured_version "$TRUST")" = "false" ]
}

@test "a version the ecosystem never measured is flagged, not silently trusted" {
  fake_claude 9.9.9 success yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 0 ]
  [ "$(jq -r .unmeasured_version "$TRUST")" = "true" ]
  run bash "$VERIFY" --status
  [[ "$output" == *"NOT the one the ecosystem sheet was measured on"* ]]
}

@test "the verdict names the configuration sources this installation reads" {
  fake_claude 2.1.226 success yes
  run bash "$VERIFY" --canary --timeout 10
  run jq -e '.config_sources | type == "array"' "$TRUST"
  [ "$status" -eq 0 ]
}

@test "AC6: Codex 'untrusted' is refused" {
  fake_codex 0.146.0 untrusted yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "untrusted" ]
  [[ "$(jq -r .detail "$TRUST")" == *"silently skip"* ]]
}

@test "AC6: Codex 'modified' is refused too — approving only 'untrusted' lets an edited hook through" {
  fake_codex 0.146.0 modified yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "modified" ]
}

@test "a trusted Codex hook that leaves no record is not a pass either" {
  fake_codex 0.146.0 trusted no
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "not_covered" ]
}

@test "a trusted Codex hook that leaves its record passes" {
  fake_codex 0.146.0 trusted yes
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 0 ]
  [ "$(jq -r .verified "$TRUST")" = "true" ]
}

@test "no tool on PATH is a verdict, not a crash" {
  # A PATH with the usual tools but neither harness on it — emptying PATH
  # entirely would test that `bash` is missing, which is a different story.
  export PATH="/usr/bin:/bin"
  export AID_HOOK_TOOL=auto
  run bash "$VERIFY" --canary --timeout 10
  [ "$status" -eq 1 ]
  [ "$(jq -r .state "$TRUST")" = "tool_missing" ]
  [[ "$(jq -r .detail "$TRUST")" == *"no fail-closed rule is in force"* ]]
}

@test "--seed-trust writes the approval in its own table, and does it idempotently" {
  # The two measured traps of the ecosystem sheet, both of which stop Codex from
  # starting: trusted_hash written INSIDE the hook's group grants nothing, and
  # appending on a changed hook produces a duplicate key.
  fake_codex 0.146.0 untrusted yes
  printf 'model = "gpt"\n' > "$CODEX_HOME/config.toml"
  run bash "$VERIFY" --seed-trust
  [ "$status" -eq 0 ]
  grep -q '^\[hooks.state\.' "$CODEX_HOME/config.toml"
  grep -q '^trusted_hash = "sha256:abc"' "$CODEX_HOME/config.toml"
  [ "$(grep -c '^\[hooks.state\.' "$CODEX_HOME/config.toml")" = "1" ]
  grep -q '^model = "gpt"' "$CODEX_HOME/config.toml"

  # Twice must not double the table — that duplicate key is what breaks Codex.
  run bash "$VERIFY" --seed-trust
  [ "$status" -eq 0 ]
  [ "$(grep -c '^\[hooks.state\.' "$CODEX_HOME/config.toml")" = "1" ]
  [ "$(grep -c '^model = "gpt"' "$CODEX_HOME/config.toml")" = "1" ]
}

@test "--seed-trust leaves config.toml intact when Codex cannot be asked" {
  printf 'model = "gpt"\n' > "$CODEX_HOME/config.toml"
  cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$BIN/codex"
  export PATH="$BIN:$PATH_BEFORE"
  run bash "$VERIFY" --seed-trust
  [ "$status" -ne 0 ]
  [ "$(cat "$CODEX_HOME/config.toml")" = 'model = "gpt"' ]
}

@test "--status with no verdict at all says so and exits non-zero" {
  run bash "$VERIFY" --status
  [ "$status" -eq 1 ]
  [[ "$output" == *"never run here"* ]]
}

@test "the dispatcher acts on the verdict: a negative one degrades fail-closed rules" {
  # The binding is the whole point of Step 2 — this asserts the wiring, not
  # the wording.
  fake_claude 2.1.226 success no
  run bash "$VERIFY" --canary --timeout 10
  [ "$(jq -r .verified "$TRUST")" = "false" ]

  cat > "$TMP/rules.sh" <<'RULES'
rule_deny() { cat > /dev/null; echo "refused" >&2; exit 2; }
RULES
  cat > "$TMP/registry.yaml" <<YAML
version: 1
defaults: { timeout_s: 5 }
budget: { total_s: 15 }
rules:
  - id: closed_one
    event: Stop
    owner: any
    degree: 2
    failure: closed
    lib: ${TMP}/rules.sh
    handler: rule_deny
    description: fixture
YAML
  run bash -c "printf '{\"session_id\":\"s\"}' | AID_HOOK_REGISTRY='$TMP/registry.yaml' AID_HOOK_AUDIT='$TMP/a.jsonl' bash '$PLUGIN_ROOT/scripts/aid-hook.sh' Stop"
  [ "$status" -eq 0 ]
  grep -q '"outcome":"degraded"' "$TMP/a.jsonl"
}
