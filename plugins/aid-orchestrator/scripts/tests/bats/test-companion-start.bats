#!/usr/bin/env bats
# aid-tier: t0
# 2.114.0 — lib/brainstorm-server/start-server.sh: installs its own dependencies
# after a plugin update, takes a fixed companion slot from the AID range off
# loopback (the VPN passes those, a random high port does not), never takes a
# running session over, and serves a brainstorm run only when the run says what
# it is (topic_kind) and, for a screen, has its basis built from the
# application. node and npm are stubs: the test is about the script's
# decisions. The stub node LISTENS, so "busy" is real.

setup() {
  LIB="$(cd "$BATS_TEST_DIRNAME/../../../lib/brainstorm-server" && pwd)"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  T="$(mktemp -d)"; S="$T/plugin/lib/brainstorm-server"; mkdir -p "$S" "$T/plugin" "$T/bin" "$T/proj/.aid-o/work/brainstorm/P5"
  cp "$LIB/start-server.sh" "$LIB/stop-server.sh" "$S/"
  ln -s "$AID_PLUGIN_PATH/scripts" "$T/plugin/scripts"          # the real libraries, a stub server
  # index.js stand-in: prints what the real server prints and listens on the port it was given
  cat > "$S/index.js" <<'JS'
const net = require('net'); const port = Number(process.env.BRAINSTORM_PORT || 40000 + Math.floor(Math.random()*20000));
const host = process.env.BRAINSTORM_HOST || '127.0.0.1';
const srv = net.createServer(s => { s.on('error', () => {}); s.end('HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok'); });   // a probe that connects and drops is not a crash
srv.listen(port, host, () => console.log(JSON.stringify({type:'server-started', port, host, url_host: process.env.BRAINSTORM_URL_HOST || 'localhost', url: `http://${process.env.BRAINSTORM_URL_HOST || 'localhost'}:${port}`, basis: process.env.BRAINSTORM_BASIS || null})));
JS
  cat > "$T/bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "npm $*" >> "${NPM_LOG}"
[[ "${NPM_FAIL:-0}" == 1 ]] && { echo "npm ERR! network" >&2; exit 1; }
mkdir -p "$(pwd)/node_modules/express"
NPM
  chmod +x "$T/bin/npm"
  export NPM_LOG="$T/npm.log" PATH="$T/bin:$PATH"
  export AID_COMPANION_PORTS="3990 3992"        # test slots inside the AID range; the real ones are 3910 3912 and may be busy on this host
  printf 'plan_id: "P5"\nscope: "user_visible"\ntopic_kind: "other"\ntopic_kind_reason: "alert texts, no screen"\n' > "$T/proj/.aid-o/work/brainstorm/P5/state.yaml"
}
teardown() {
  for p in "$T"/proj/.aid-o/work/companion/*/.server.pid /tmp/brainstorm-*/.server.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  rm -rf "$T"
}
_start() { run bash "$S/start-server.sh" "$@"; }

@test "node_modules missing: npm install runs once, the log says so, the server starts; present: no second install" {
  _start --project-dir "$T/proj" --plan P5
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *'"server-started"'* ]]
  grep -q 'npm install --no-audit --no-fund' "$NPM_LOG"; [ -d "$S/node_modules/express" ]
  grep -q 'node_modules missing' "$T"/proj/.aid-o/work/companion/*/.server.log
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 0 ]; [ "$(grep -c 'npm install' "$NPM_LOG")" -eq 1 ]
}

@test "npm install fails: the JSON names the command and the log, nothing starts" {
  NPM_FAIL=1 _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"npm install failed"* && "$output" == *"cd $S && npm install"* ]]
}

@test "off loopback: the first free slot, then the second; a third start names the holders and takes nothing over; outside the range refused; loopback keeps a random port" {
  _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1
  echo "$output"; [ "$status" -eq 0 ]; [ "$(jq -r .port <<<"$output")" = 3990 ]; [ "$(jq -r .bind_host <<<"$output")" = 0.0.0.0 ]
  [[ "$(jq -r .hint <<<"$output")" == *"VPN"* ]]
  _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1
  [ "$status" -eq 0 ]; [ "$(jq -r .port <<<"$output")" = 3992 ]
  _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1
  [ "$status" -eq 1 ]; [[ "$output" == *"every companion slot is in use"* && "$output" == *"3990: pid "*"node"*"running"*"stop-server.sh $T/proj/.aid-o/work/companion/"* && "$output" == *"--stale"* ]]
  AID_COMPANION_PORTS="3990 45000" _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1
  [ "$status" -eq 1 ]; [[ "$output" == *"AID_COMPANION_PORTS has '45000'"* ]]
  [ "$(ls -d "$T"/proj/.aid-o/work/companion/*/ | wc -l)" -eq 2 ]      # the two running ones, untouched
  _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1 --port 50000
  [ "$status" -eq 1 ]; [[ "$output" == *"outside the AID range"* ]]
  _start --project-dir "$T/proj" --plan P5 --port 3990                    # loopback: no range rule, but a held port is still refused
  [ "$status" -eq 1 ]; [[ "$output" == *"in use by"* ]]
  _start --project-dir "$T/proj" --plan P5
  echo "loopback: status=$status output=$output"; [ "$status" -eq 0 ]; local p; p="$(tail -1 <<<"$output" | jq -r .port)"; (( p > 40000 ))
}

@test "a project companion names its run: no --plan, an unknown run, a run with no topic_kind — each refused with the command to run" {
  _start --project-dir "$T/proj"
  [ "$status" -eq 1 ]; [[ "$output" == *"--project-dir needs --plan"* ]]
  _start --project-dir "$T/proj" --plan P6
  [ "$status" -eq 1 ]; [[ "$output" == *"no brainstorm run P6"* ]]
  printf 'plan_id: "P5"\nscope: "roadmap"\ntopic_kind: ""\n' > "$T/proj/.aid-o/work/brainstorm/P5/state.yaml"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"topic-kind P5 ui"* && "$output" == *"topic-kind P5 other --reason"* ]]
  printf 'plan_id: "P5"\nscope: "roadmap"\ntopic_kind: "other"\ntopic_kind_reason: ""\n' > "$T/proj/.aid-o/work/brainstorm/P5/state.yaml"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"other without a reason"* ]]
  printf 'plan_id: "P5"\nscope: "roadmap"\ntopic_kind: "sketch"\n' > "$T/proj/.aid-o/work/brainstorm/P5/state.yaml"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"neither ui nor other"* ]]
}

@test "a server that prints no url, or one whose url does not answer, is a failure and nothing is left running" {
  printf 'console.log(JSON.stringify({type:"server-started"})); setInterval(()=>{},1000);\n' > "$S/index.js"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"printed no url"* ]]
  [ -z "$(cat "$T"/proj/.aid-o/work/companion/*/.server.pid 2>/dev/null)" ] || ! kill -0 "$(cat "$T"/proj/.aid-o/work/companion/*/.server.pid)" 2>/dev/null
  printf 'console.log(JSON.stringify({type:"server-started", port: 3993, url: "http://127.0.0.1:3993"})); setInterval(()=>{},1000);\n' > "$S/index.js"   # claims a port it does not listen on
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"does not answer from this host"* ]]
}

@test "a UI run without its basis is refused naming aid_ui_proposal_build; with a live-screen basis the server gets it; a basis missing a screenshot is refused" {
  printf 'plan_id: "P5"\nscope: "user_visible"\ntopic_kind: "ui"\n' > "$T/proj/.aid-o/work/brainstorm/P5/state.yaml"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"no proposal basis"* && "$output" == *"aid_ui_proposal_build"* ]]
  local d="$T/proj/.aid-o/work/brainstorm/P5"; mkdir -p "$d/desktop" "$d/mobile"; printf 'PNG' > "$d/desktop/baseline.png"
  jq -n --arg b "$d/desktop/baseline.png" '{basis: "live-screen", live_baseline: true, responsive: true, viewports: [{name: "desktop", width: 1280, height: 720, baseline: $b, proposed: null}, {name: "mobile", width: 390, height: 844, baseline: null, proposed: null}]}' > "$d/proposal.json"
  _start --project-dir "$T/proj" --plan P5
  [ "$status" -eq 1 ]; [[ "$output" == *"mobile viewport has no baseline capture"* ]]
  printf 'PNG' > "$d/mobile/baseline.png"
  jq --arg b "$d/mobile/baseline.png" '.viewports[1].baseline = $b' "$d/proposal.json" > "$d/p.tmp" && mv "$d/p.tmp" "$d/proposal.json"
  _start --project-dir "$T/proj" --plan P5
  echo "$output"; [ "$status" -eq 0 ]; [ "$(tail -1 <<<"$output" | jq -r .basis)" = "$d/proposal.json" ]
}

@test "--list names every running companion of the project with its plan, port, age and kept state" {
  _start --project-dir "$T/proj" --plan P5 --host 0.0.0.0 --url-host 127.0.0.1; [ "$status" -eq 0 ]
  run bash "$S/stop-server.sh" --list --project-dir "$T/proj"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .plan <<<"$output")" = P5 ]; [ "$(jq -r .project <<<"$output")" = proj ]; [ "$(jq -r .port <<<"$output")" = 3990 ]; [ "$(jq -r .kept <<<"$output")" = false ]
  [[ "$(jq -r .screen_dir <<<"$output")" == "$T/proj/.aid-o/work/companion/"* ]]
  touch "$(jq -r .screen_dir <<<"$output")/.keep"
  run bash "$S/stop-server.sh" --list --project-dir "$T/proj"; [ "$(jq -r .kept <<<"$output")" = true ]
  run bash "$S/stop-server.sh" --stale 0 --project-dir "$T/proj"                     # kept: left alone, named
  [ "$(jq -r .stopped <<<"$output")" = 0 ]; [[ "$(jq -r .left_running_not_a_companion <<<"$output")" == *"kept by the PM"* ]]
}

@test "--stale stops only this project's companions older than N hours and leaves a PID that is not a companion, naming it" {
  _start --project-dir "$T/proj" --plan P5; [ "$status" -eq 0 ]
  local d1; d1="$(ls -d "$T"/proj/.aid-o/work/companion/*/ | head -1)"
  # a foreign long-running process recorded in a session dir
  mkdir -p "$T/proj/.aid-o/work/companion/foreign"; sleep 600 & echo $! > "$T/proj/.aid-o/work/companion/foreign/.server.pid"
  run bash "$S/stop-server.sh" --stale 0 --project-dir "$T/proj"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .stopped <<<"$output")" = 1 ]; [[ "$(jq -r .left_running_not_a_companion <<<"$output")" == *"sleep"* ]]
  [ ! -f "$d1/.server.pid" ]
  kill "$(cat "$T/proj/.aid-o/work/companion/foreign/.server.pid")" 2>/dev/null || true
  run bash "$S/stop-server.sh" --stale 24
  [ "$status" -eq 1 ]
}
