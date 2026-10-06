#!/usr/bin/env bats
# aid-tier: t0
# 2.114.0 — lib/brainstorm-server/start-server.sh installs its own dependencies
# when a plugin update replaced the directory without node_modules, and says
# the exact command when the install fails. node and npm are stubs: the test is
# about the script's decisions, not express.

setup() {
  LIB="$(cd "$BATS_TEST_DIRNAME/../../../lib/brainstorm-server" && pwd)"
  T="$(mktemp -d)"; S="$T/server"; mkdir -p "$S" "$T/bin" "$T/proj"
  cp "$LIB/start-server.sh" "$S/"
  # index.js stand-in: prints what the real server prints and stays up
  printf 'console.log(JSON.stringify({type:"server-started",port:3910,url:"http://x:3910"}));\nsetInterval(()=>{},1000);\n' > "$S/index.js"
  cat > "$T/bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "npm $*" >> "${NPM_LOG}"
[[ "${NPM_FAIL:-0}" == 1 ]] && { echo "npm ERR! network" >&2; exit 1; }
mkdir -p "$(pwd)/node_modules/express"
NPM
  chmod +x "$T/bin/npm"
  export NPM_LOG="$T/npm.log" PATH="$T/bin:$PATH"
}
teardown() {
  for p in "$T"/proj/.aid-o/work/companion/*/.server.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  rm -rf "$T"
}

@test "node_modules missing: npm install runs once, the log says so, the server starts" {
  run bash "$S/start-server.sh" --project-dir "$T/proj"
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *'"server-started"'* ]]
  grep -q 'npm install --no-audit --no-fund' "$NPM_LOG"
  [ -d "$S/node_modules/express" ]
  grep -q 'node_modules missing' "$T"/proj/.aid-o/work/companion/*/.server.log
  # present now: a second start does not install again
  run bash "$S/start-server.sh" --project-dir "$T/proj"
  [ "$status" -eq 0 ]; [ "$(grep -c 'npm install' "$NPM_LOG")" -eq 1 ]
}

@test "npm install fails: the JSON names the command and the log, nothing starts" {
  NPM_FAIL=1 run bash "$S/start-server.sh" --project-dir "$T/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"npm install failed"* && "$output" == *"cd $S && npm install"* ]]
  [ ! -f "$T"/proj/.aid-o/work/companion/*/.server.pid ] || [ ! -s "$T"/proj/.aid-o/work/companion/*/.server.pid ]
}
