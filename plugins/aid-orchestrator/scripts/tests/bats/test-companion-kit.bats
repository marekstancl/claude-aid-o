#!/usr/bin/env bats
# aid-tier: t2
# aid-subject: scripts/aid-companion.sh
# The companion kit: the agent writes variants and three data files, scripts/aid-companion.sh does the
# rest. These cases run the REAL server (lib/brainstorm-server/index.js), a real copy of a sample app
# with a stand-in dev server (python's http.server — any command with {port} is a dev server to the kit),
# and a real browser. Defects they catch: the server that did not start from 2.118.0 to 3.6.0 (its tests
# replaced index.js), PM notes and sends that never reached the agent, a page the agent had to build.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  KIT="$AID_PLUGIN_PATH/scripts/aid-companion.sh"
  command -v node >/dev/null || skip "node not installed"
  export AID_COMPANION_BIND=127.0.0.1 AID_COMPANION_URL_HOST=127.0.0.1
  P="$(mktemp -d)"; git -C "$P" init -q; git -C "$P" config user.email t@t; git -C "$P" config user.name t
  echo '.aid-o/' > "$P/.gitignore"
  cp -r "$AID_PLUGIN_PATH/scripts/tests/fixtures/companion-kit/app" "$P/ui"
  git -C "$P" add -A; git -C "$P" commit -qm base
  mkdir -p "$P/ui/node_modules" "$P/.aid-o/work/brainstorm/P900" "$P/.aid-o/config"
  printf 'plan_id: P900\ntopic_kind: ui\n' > "$P/.aid-o/work/brainstorm/P900/state.yaml"
  cat > "$P/.aid-o/config/project.yaml" <<'EOF'
ui:
  responsive: true
  dir: ui
  components: ui/src/components/shared
  dev_cmd: ["python3", "-m", "http.server", "{port}", "--bind", "127.0.0.1"]
  ready_path: /index.html
  api_prefix: /api/
EOF
  D="$P/.aid-o/work/companion/P900"
}
teardown() {
  bash "$KIT" down --plan P900 --project-dir "$P" >/dev/null 2>&1 || true
  rm -rf "$P"
}
_k() { bash "$KIT" "$1" --plan P900 --project-dir "$P" "${@:2}"; }
# _ws <port> <json events…> — send page events as the companion page does (own Origin)
_ws() {
  local port="$1"; shift
  (cd "$AID_PLUGIN_PATH/lib/brainstorm-server" && node -e '
    const W = require("ws"); const [port, ...ev] = process.argv.slice(1);
    const w = new W("ws://127.0.0.1:" + port, { origin: "http://127.0.0.1:" + port });
    w.on("open", () => { for (const e of ev) w.send(e); setTimeout(() => process.exit(0), 300); });
    w.on("error", e => { console.error(e.message); process.exit(1); });' "$port" "$@")
}

@test "AC1 up/answers/down: the real server starts, keeps every choice, note and send, is reused while it runs and keeps the answers over a restart" {
  run _k up; echo "$output"; [ "$status" -eq 0 ]
  local port pid; port="$(jq -r .port <<< "$output")"; pid="$(jq -r .pid <<< "$output")"
  _ws "$port" '{"type":"choice","kolo":1,"bod":"1","volba":"B"}' '{"type":"choice","kolo":1,"bod":"1","volba":"A"}' \
    '{"type":"note","kolo":1,"bod":"2","text":"je to hnus"}' '{"type":"confirm","kolo":1,"selected":[{"bod":"1","volba":"B"}]}' '{"type":"confirm","kolo":1,"selected":[{"bod":"1","volba":"A"}],"event_id":"forged"}'
  run _k answers; echo "$output"
  [ "$(jq -r '.volby["1"]' <<< "$output")" = A ]; [ "$(jq -r '.poznamky["2"]' <<< "$output")" = "je to hnus" ]
  [ "$(jq -r '.odeslano.type' <<< "$output")" = confirm ]; [ "$(jq -r '.odeslano.event_id' <<< "$output")" != forged ]
  [ "$(jq -r '.odeslano.selected[0].volba' <<< "$output")" = A ]   # the later of two sends
  run _k answers --history; [ "$(wc -l <<< "$output")" -eq 5 ]
  # a second round: its own latest state, the first round still readable, the history holds both
  _ws "$port" '{"type":"choice","kolo":2,"bod":"1","volba":"B"}'
  run _k answers; [ "$(jq -r .kolo <<< "$output")" = 2 ]; [ "$(jq -r '.volby["1"]' <<< "$output")" = B ]
  run _k answers --kolo 1; [ "$(jq -r '.volby["1"]' <<< "$output")" = A ]
  run _k answers --history; [ "$(wc -l <<< "$output")" -eq 6 ]
  run _k up; [ "$(jq -r .reused <<< "$output")" = true ]; [ "$(jq -r .pid <<< "$output")" = "$pid" ]
  _k down
  run _k up; [ "$(jq -r .reused <<< "$output")" = false ]; [ "$(jq -r .pid <<< "$output")" != "$pid" ]
  [ "$(wc -l < "$D/answers.jsonl")" -eq 6 ]
}

@test "AC1 security: a page of another origin cannot open the websocket (no planted answers)" {
  run _k up; local port; port="$(jq -r .port <<< "$output")"
  run bash -c "cd '$AID_PLUGIN_PATH/lib/brainstorm-server' && node -e '
    const W = require(\"ws\"); const w = new W(\"ws://127.0.0.1:$port\", { origin: \"http://evil.example\" });
    w.on(\"open\", () => { console.log(\"open\"); process.exit(0); }); w.on(\"error\", e => { console.log(e.message); process.exit(0); });'"
  [[ "$output" == *401* ]]
  # the same host on another port is another site too (Codex 19. 10. 2026)
  run bash -c "cd '$AID_PLUGIN_PATH/lib/brainstorm-server' && node -e '
    const W = require(\"ws\"); const w = new W(\"ws://127.0.0.1:$port\", { origin: \"http://127.0.0.1:1\" });
    w.on(\"open\", () => { console.log(\"open\"); process.exit(0); }); w.on(\"error\", e => { console.log(e.message); process.exit(0); });'"
  [[ "$output" == *401* ]]
}

@test "AC5 proto: a missing key is refused with the YAML to add; the copy runs outside the repository, and down stops only its own group" {
  yq -i 'del(.ui.dev_cmd)' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"ui.dev_cmd"*"dev_cmd: ["* ]]
  yq -i '.ui.dev_cmd = ["python3", "-m", "http.server", "{port}", "--bind", "127.0.0.1"]' "$P/.aid-o/config/project.yaml"
  run _k proto; echo "$output"; [ "$status" -eq 0 ]
  local url pg; url="$(jq -r .url <<< "$output")"; pg="$(jq -r .pgid <<< "$output")"
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/index.html")" = 200 ]
  [ -d "$D/proto/node_modules" ] && [ ! -L "$D/proto/node_modules" ] && [ -w "$D/proto/node_modules" ]   # the dev server writes its caches there
  [ -f "$D/proto-manifest.json" ]
  [ -z "$(git -C "$P" status --porcelain)" ]
  sleep 300 & local foreign=$!
  _k down
  # a link out of ui.dir cannot be copied (an edit in the copy would change it)
  rm -rf "$D/proto" "$D/proto-manifest.json"; ln -s /etc/hostname "$P/ui/src/outside.txt"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"outside.txt is a link to"*"outside"* ]]; rm "$P/ui/src/outside.txt"
  ! kill -0 -- "-$pg" 2>/dev/null
  kill -0 "$foreign"; kill "$foreign"
}

@test "kit F (P117): ui.copy_extra copies repository files beside the copy and refuses secrets and outside paths; a scrolling container is captured whole; the first-shot limit is 1..120 s" {
  mkdir -p "$P/shared"; echo "body{}" > "$P/shared/base.css"; echo "SECRET=1" > "$P/.env.local"
  yq -i '.ui.copy_extra = [".env.local"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"looks like a secret"* ]]; rm -rf "$D/proto" "$D/proto-manifest.json"
  mkdir -p "$P/.env.d" "$P/credentials/aws"; echo x > "$P/.env.d/production.txt"; echo x > "$P/credentials/aws/config.json"
  for e in .env.d/production.txt credentials/aws/config.json; do
    yq -i ".ui.copy_extra = [\"$e\"]" "$P/.aid-o/config/project.yaml"
    run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"looks like a secret"* ]]; rm -rf "$D/proto" "$D/proto-manifest.json"
  done
  # a link inside the companion directory never steers the copy (onto the kit's own files or out of it)
  mkdir -p "$D"; ln -s "$D" "$D/shared"; yq -i '.ui.copy_extra = ["shared/base.css"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"is a link"* ]]; rm -rf "$D/proto" "$D/proto-manifest.json" "$D/shared"
  yq -i '.ui.copy_extra = ["../etc/hostname"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; rm -rf "$D/proto" "$D/proto-manifest.json"
  yq -i '.ui.copy_extra = ["shared/base.css"]' "$P/.aid-o/config/project.yaml"
  # a container that scrolls: 100 px tall, 600 px of content
  sed -i 's|</body>|<div id="list" style="height:100px;overflow:auto"><div style="height:600px">dlouhy seznam</div></div></body>|' "$P/ui/index.html"
  run _k proto; echo "$output"; [ "$status" -eq 0 ]
  [ "$(cat "$D/shared/base.css")" = "body{}" ]                                   # ../shared/base.css from the copy
  ! jq -e '.files | keys | any(test("base.css"))' "$D/proto-manifest.json" >/dev/null 2>&1   # not part of the copy's own files
  echo '[{"method": "GET", "path": "/api/**", "status": 204, "body": ""}]' > "$D/mocks.json"
  echo '{"base": "proto", "shots": [{"name": "seznam", "path": "/index.html", "capture": {"scroll": {"css": "#list"}}}]}' > "$D/shots.json"
  run _k shots; echo "$output"; [ "$status" -eq 0 ]
  [ "$(node -e 'const b=require("fs").readFileSync(process.argv[1]);console.log(b.readUInt32BE(20))' "$D/shots/desktop/seznam.png")" -ge 590 ]
  # the first shot's wait follows the setting: 2 s for a text that never comes fails in seconds, not 15
  yq -i '.ui.first_shot_timeout_s = 2' "$P/.aid-o/config/project.yaml"
  echo '{"base": "proto", "shots": [{"name": "nic", "path": "/index.html", "steps": [{"wait": {"for": {"text": "nikdy"}}}]}]}' > "$D/shots.json"
  local t0=$SECONDS; run _k shots; [ "$status" -ne 0 ]; (( SECONDS - t0 < 12 ))
  yq -i '.ui.first_shot_timeout_s = 500' "$P/.aid-o/config/project.yaml"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"first_shot_timeout_s must be whole seconds from 1 to 120"* ]]
}

@test "AC5 down: a recorded prototype whose identity does not match (pid reused) is not killed" {
  sleep 300 & local other=$!
  jq -n --argjson p "$other" '{pid: $p, pgid: $p, starttime: "1", cmd: "python3", port: 1, url: "x"}' > "$D/proto.json" 2>/dev/null || { mkdir -p "$D"; jq -n --argjson p "$other" '{pid: $p, pgid: $p, starttime: "1", cmd: "python3", port: 1, url: "x"}' > "$D/proto.json"; }
  run _k down; echo "$output"
  [[ "$output" == *"not the one we started"* ]]
  kill -0 "$other"; kill "$other"
}

@test "AC4 shots: every kind of step and selector on desktop and phone, login through localStorage, data from mocks, unmocked API calls listed and failing, a two-match selector refused" {
  _k proto >/dev/null
  cat > "$D/mocks.json" <<'EOF'
[{"method": "GET", "path": "/api/data", "body": {"text": "data z mocku"}}]
EOF
  cat > "$D/shots.json" <<'EOF'
{"base": "proto", "storage": {"localStorage": {"token": "falesny"}},
 "shots": [
  {"name": "seznam", "path": "/index.html", "steps": [{"wait": {"for": {"text": "data z mocku"}}}], "capture": {"element": {"text": "data z mocku"}}},
  {"name": "prihlaseny", "path": "/index.html", "capture": {"element": {"text": "Přihlášen: falesny"}}},
  {"name": "okno", "path": "/index.html", "steps": [
     {"fill": {"role": "textbox", "name": "Hledat"}, "value": "Nováková"}, {"select": {"css": "select"}, "value": "b"},
     {"hover": {"role": "button", "name": "Otevřít"}}, {"click": {"role": "button", "name": "Otevřít"}},
     {"press": "Tab"}, {"wait": "network"}, {"wait": 50}, {"wait": {"for": {"text": "Nováková"}}}], "capture": {"element": {"css": "#dialog.open"}}},
  {"name": "cela", "path": "/index.html", "capture": "full"}]}
EOF
  run _k shots; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"GET /api/missing"* ]]; [[ "$output" != *"/index.html"*"no mock"* ]]
  jq '. + [{"path": "/api/missing", "status": 204, "body": ""}]' "$D/mocks.json" > "$D/m" && mv "$D/m" "$D/mocks.json"
  run _k shots; echo "$output"; [ "$status" -eq 0 ]
  local v; for v in desktop mobile; do for s in seznam prihlaseny okno cela; do [ -s "$D/shots/$v/$s.png" ]; done; done
  # the phone layout differs: the full page is narrower and the desktop-only column is gone
  [ "$(node -e 'const b=require("fs").readFileSync(process.argv[1]);console.log(b.readUInt32BE(16))' "$D/shots/mobile/cela.png")" -eq 390 ]
  jq '.shots[0].capture = {"element": {"css": "div"}}' "$D/shots.json" > "$D/s" && mv "$D/s" "$D/shots.json"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"finds"*"elements, it must find exactly one"* ]]
  jq '.shots[0].capture = "viewport" | .shots[0].steps = [{"wait": {"for": {"css": "div"}}}]' "$D/shots.json" > "$D/s" && mv "$D/s" "$D/shots.json"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"it must find exactly one"* ]]
  [ "$(node -e 'const b=require("fs").readFileSync(process.argv[1]);console.log(b.readUInt32BE(16)+"x"+b.readUInt32BE(20))' "$D/shots/desktop/okno.png" 2>/dev/null)" != "" ]
  jq '.base = "https://acta.example.cz"' "$D/shots.json" > "$D/s" && mv "$D/s" "$D/shots.json"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"never a live application"* ]]
  # a path that would leave the prototype ("@host/", "//host") is refused (security review 19. 10. 2026)
  jq '.base = "proto" | .shots[0].path = "@example.com/"' "$D/shots.json" > "$D/s" && mv "$D/s" "$D/shots.json"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *'a path starts with one "/"'* ]]
  jq '.shots[0].path = "//example.com/"' "$D/shots.json" > "$D/s" && mv "$D/s" "$D/shots.json"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *'a path starts with one "/"'* ]]
}

# a proposal over the sample app: option A edits Page.tsx through the alias, B adds a component through the barrel
_proposal() {
  _k proto >/dev/null
  mkdir -p "$D/shots/desktop" "$D/shots/mobile"
  local v s
  node -e 'const z=require("zlib"),fs=require("fs");const w=+process.argv[2],h=+process.argv[3];const raw=Buffer.alloc((w*3+1)*h,255);for(let y=0;y<h;y++)raw[y*(w*3+1)]=0;const c=t=>{let r=0xffffffff;for(const x of t){r^=x;for(let k=0;k<8;k++)r=r&1?(r>>>1)^0xedb88320:r>>>1}return (r^0xffffffff)>>>0};const ch=(t,d)=>{const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const cr=Buffer.alloc(4);cr.writeUInt32BE(c(td));return Buffer.concat([l,td,cr])};const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=2;fs.writeFileSync(process.argv[1],Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),ch("IHDR",ih),ch("IDAT",z.deflateSync(raw)),ch("IEND",Buffer.alloc(0))]))' "$D/shots/desktop/a.png" 1280 720
  for v in desktop mobile; do for s in dnes a b; do [[ "$v/$s" == desktop/a ]] || cp "$D/shots/desktop/a.png" "$D/shots/$v/$s.png"; done; done
  printf "import { Button } from '@/components/shared/Button';\nimport { Card } from '../components/shared';\nexport function Page() { return Button({ label: 'new' }) + Card({ title: 'x' }); }\n" > "$D/proto/src/pages/Page.tsx"
  printf "import { Card } from './shared';\nexport function Novy() { return Card({ title: 'n' }); }\n" > "$D/proto/src/components/Novy.tsx"
  cat > "$D/navrh.json" <<'EOF'
{"plan": "P900", "kolo": 1, "rozhodnuto": [],
 "body": [{"id": "1", "title": "Řádek", "otazka": "Jak má řádek vypadat?", "doporuceni": "A", "proc": "Je kratší.",
   "soulad_s_pravidly": [{"pravidlo": "ui/CLAUDE.md#Komponenty", "jak": "jen sdílené komponenty"}],
   "minule": [{"popisek": "Dnes", "shot": "dnes"}],
   "moznosti": [
     {"klic": "A", "nazev": "Upravený řádek", "popis": "Tlačítko a karta.", "soubory": ["src/pages/Page.tsx"], "postaveno_z": ["Button", "Card"], "snimky": [{"popisek": "Řádek", "shot": "a"}]},
     {"klic": "B", "nazev": "Nová komponenta", "popis": "Vlastní blok.", "soubory": ["src/components/Novy.tsx"], "postaveno_z": ["Card"], "nove": [{"komponenta": "src/components/Novy.tsx", "duvod": "žádná sdílená neumí dva řádky"}], "snimky": [{"popisek": "Blok", "shot": "b"}]}]},
  {"id": "2", "title": "Textová otázka", "otazka": "Má se seznam řadit podle data?", "doporuceni": "A", "proc": "Tak to čte obchodník.",
   "moznosti": [{"klic": "A", "nazev": "Ano", "popis": "Nejnovější nahoře."}, {"klic": "B", "nazev": "Ne", "popis": "Podle jména."}]}]}
EOF
}

@test "AC2/AC6 show: a valid proposal builds the page, the page checks itself (fits, controls reachable), and proposal.json passes the brainstorm's check" {
  _proposal
  run _k up; [ "$status" -eq 0 ]
  run _k show; echo "$output"; [ "$status" -eq 0 ]
  [ -s "$D/navrh-1.html" ] && [ -s "$D/check-1440x900.png" ] && [ -s "$D/check-390x844.png" ]
  grep -q 'Agent uvádí, z jakých pravidel vychází' "$D/navrh-1.html"
  ! grep -q 'data:image/png;base64' "$D/navrh-1.html"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-proposal.sh' && aid_ui_proposal_check '$P/.aid-o/work/brainstorm/P900/proposal.json' '$P'"
  echo "$output"; [ "$status" -eq 0 ]
  # and the check the design gate itself runs on it (aid-brainstorm-state.sh gate --phase design)
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-proposal.sh' && aid_ui_proposal_basis_check '$P/.aid-o/work/brainstorm/P900/proposal.json' '$P'"
  echo "$output"; [ "$status" -eq 0 ]
  local url; url="$(jq -r .url "$D/server.json")"
  [[ "$(curl -s "$url/")" == *"P900 · kolo 1"* ]]
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/shots/desktop/a.png")" = 200 ]
}

@test "AC2 page: the template's fixed behaviour — the page never scrolls (a 3x longer text scrolls its column), previews no larger than life, viewport switch, keys, counter, past round, a text-only point" {
  _proposal
  jq '.body[0].proc = (.body[0].proc * 120)' "$D/navrh.json" > "$D/n" && mv "$D/n" "$D/navrh.json"
  run _k show; echo "$output"; [ "$status" -eq 0 ]
  run node --input-type=module -e "
    import { createRequire } from 'node:module';
    const { chromium } = createRequire('$AID_PLUGIN_PATH/lib/ui-fidelity/package.json')('@playwright/test');
    const b = await chromium.launch({ executablePath: process.env.CHROME || undefined }); const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
    await p.goto('file://$D/navrh-1.html'); const r = {};
    r.pageScroll = await p.evaluate(() => document.scrollingElement.scrollHeight > innerHeight);
    r.columnScroll = await p.evaluate(() => { const c = document.querySelector('.rs'); return c.scrollHeight > c.clientHeight; });
    r.imgMax = await p.evaluate(() => getComputedStyle(document.getElementById('img')).maxWidth);
    r.count = await p.textContent('#count');
    r.past = await p.locator('.tab.past').count();
    r.badge = await p.evaluate(() => { const b = [...document.querySelectorAll('.opt[data-k=B] .badge.new')]; return b.length; });
    await p.click('[data-view=mobile]'); r.phone = await p.evaluate(() => document.getElementById('pv').className);
    r.phoneMax = await p.evaluate(() => getComputedStyle(document.getElementById('img')).maxWidth);
    await p.keyboard.press('ArrowDown'); r.title = await p.textContent('#title');
    r.textOnly = await p.evaluate(() => document.getElementById('ap').classList.contains('text'));
    await p.click('.opt[data-k=B]'); r.counter2 = await p.textContent('#count');
    await p.keyboard.press('ArrowUp'); await p.click('[data-view=desktop]'); await p.click('#img');
    r.real = await p.evaluate(() => document.getElementById('pv').classList.contains('real') && getComputedStyle(document.getElementById('img')).maxWidth === 'none');
    r.pinned = await p.evaluate(() => { const f = document.querySelector('.rf').getBoundingClientRect(); return Math.abs(f.bottom - innerHeight) <= 1; });
    console.log(JSON.stringify(r)); await b.close();"
  echo "$output"
  [ "$(jq -r .pageScroll <<< "$output")" = false ]; [ "$(jq -r .columnScroll <<< "$output")" = true ]
  [ "$(jq -r .imgMax <<< "$output")" = "min(100%, 960px)" ]
  [ "$(jq -r .count <<< "$output")" = "Zvoleno 2 z 2" ]; [ "$(jq -r .past <<< "$output")" = 1 ]
  [ "$(jq -r .counter2 <<< "$output")" = "Zvoleno 2 z 2" ]; [ "$(jq -r .badge <<< "$output")" -ge 1 ]; [ "$(jq -r .phoneMax <<< "$output")" = "min(100%, 390px)" ]
  [[ "$(jq -r .phone <<< "$output")" == *"pv m"* ]]
  [ "$(jq -r .title <<< "$output")" = "Textová otázka" ]; [ "$(jq -r .textOnly <<< "$output")" = true ]
  [ "$(jq -r .real <<< "$output")" = true ]; [ "$(jq -r .pinned <<< "$output")" = true ]
}

@test "AC3 show refuses, each named: a missing field, a recommendation that is no option, keys not from A, a missing shot, a path out of the plan's dir, a component not imported from ui.components, an unresolved import, a new component file without nove, an unlisted change, a file of two options" {
  _proposal
  _bad() { jq "$1" "$D/navrh.json" > "$P/bad.json"; cp "$D/navrh.json" "$P/ok.json"; cp "$P/bad.json" "$D/navrh.json"
           run _k show; cp "$P/ok.json" "$D/navrh.json"; [ "$status" -ne 0 ] || { echo "accepted: $1"; return 1; }
           [[ "$output" == *"$2"* ]] || { echo "for $1 expected '$2' in: $output"; return 1; }; }
  _bad 'del(.body[0].otazka)' 'body[0].otazka must be'
  _bad '.body[0].doporuceni = "C"' 'is not the key of one of its options'
  _bad '.body[0].moznosti[1].klic = "C"' 'must be "B"'
  _bad '.body[0].moznosti[0].snimky[0].shot = "chybi"' "shot 'chybi' has no desktop capture"
  _bad '.body[0].moznosti[0].snimky[0].shot = "../x"' 'is not a plain shot name'
  _bad '.body[0].moznosti[0].soubory = ["../etc/passwd"]' 'must be a path inside proto/'
  _bad '.spolecne = ["/etc/passwd"]' 'spolecne[0]'
  _bad '.spolecne = [3]' 'spolecne[0]'
  _bad '.body[0].moznosti[1].nove[0].komponenta = "../x.tsx"' 'nove[0].komponenta'
  _bad '.body[0].moznosti[1].klic = "A"' 'must be "B"'   # a duplicate key is a key out of the A, B, C order
  _bad '.body[0].moznosti[0].postaveno_z += ["Table"]' 'names Table, but no file of the option or of spolecne imports it'
  _bad '.body[0].moznosti[1].nove = []' 'is a new component file'
  _bad '.body[0].moznosti[1].soubory = []' 'no option lists it in soubory'
  _bad '.body[0].moznosti[1].soubory += ["src/pages/Page.tsx"]' 'is also listed by'
  # a tool of the agent's own in the plan's directory
  echo 'x' > "$D/gen_page.py"; run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"gen_page.py is not one of the kit's files"* ]]; rm "$D/gen_page.py"
  # a name the barrel does not export
  printf "import { Card, Ghost } from '../components/shared';\nimport { Button } from '@/components/shared/Button';\nexport function Page() { return Button({ label: Ghost }) + Card({}); }\n" > "$D/proto/src/pages/Page.tsx"
  _bad '.body[0].moznosti[0].postaveno_z = ["Button", "Ghost"]' "does not export it"
  # variants of one existing page: the page in spolecne, its imports count for every option (AC9 19. 10.)
  jq '.spolecne = ["src/pages/Page.tsx"] | .body[0].moznosti[0].soubory = []' "$D/navrh.json" > "$D/n" && mv "$D/n" "$D/navrh.json"
  run _k show; echo "$output"; [ "$status" -eq 0 ]
  # files a dev server generates (dev-dist/) are no change of the variants
  mkdir -p "$D/proto/dev-dist"; echo x > "$D/proto/dev-dist/sw.js"
  run _k show; [ "$status" -eq 0 ]
  printf "import { Gone } from '@/components/shared/Gone';\nimport { Button } from '@/components/shared/Button';\nexport function Page() { return Button({ label: Gone }); }\n" > "$D/proto/src/pages/Page.tsx"
  _bad '.body[0].moznosti[0].postaveno_z = ["Button", "Gone"]' "Gone is imported from '@/components/shared/Gone', which does not resolve"
}

@test "AC7 the old mode: a fragment is wrapped in the frame, a full page is served as it is, /screen serves it too, and a start without a project still works" {
  local out port d
  out="$(bash "$AID_PLUGIN_PATH/lib/brainstorm-server/start-server.sh" --host 127.0.0.1)"; port="$(jq -r .port <<< "$out")"; d="$(jq -r .screen_dir <<< "$out")"
  echo '<div class="options"><div class="option" data-choice="a">A</div></div>' > "$d/frag.html"; sleep 0.5
  [[ "$(curl -s "http://127.0.0.1:$port/")" == *'data-choice="a"'*'</html>'* ]]
  [[ "$(curl -s "http://127.0.0.1:$port/screen")" == *'data-choice="a"'* ]]
  printf '<!doctype html><html><body><p id="mine">full</p></body></html>' > "$d/full.html"; sleep 0.5
  [[ "$(curl -s "http://127.0.0.1:$port/")" == *'<p id="mine">full</p>'* ]]
  # the helper's data-confirm still answers: the old .events and the new answers.jsonl
  printf '<div class="options"><div class="option selected" data-choice="b">B</div></div><button data-confirm>OK</button>' > "$d/confirm.html"; sleep 0.5
  run node --input-type=module -e "
    import { createRequire } from 'node:module';
    const { chromium } = createRequire('$AID_PLUGIN_PATH/lib/ui-fidelity/package.json')('@playwright/test');
    const b = await chromium.launch({ executablePath: process.env.CHROME || undefined }); const p = await b.newPage();
    await p.goto('http://127.0.0.1:$port/'); await p.click('[data-choice=b]'); await p.click('button[data-confirm]'); await p.waitForTimeout(500); await b.close();"
  grep -q '"choice":"b"' "$d/.events"
  grep -q '"type":"confirm"' "$d/answers.jsonl"
  bash "$AID_PLUGIN_PATH/lib/brainstorm-server/stop-server.sh" "$d" >/dev/null 2>&1 || true
}

@test "AC7 the guide: one procedure, short, and every kit step it names is a step the script has (and back)" {
  local g="$AID_PLUGIN_PATH/skills/visual-companion/SKILL.md"
  [ "$(wc -l < "$g")" -le 200 ]
  local named have
  named="$(grep -oE 'aid-companion\.sh [a-z]+|\$K [a-z]+' "$g" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  have="$(sed -n '/^case "\$step" in/,/^esac/p' "$KIT" | grep -oE '^\s+[a-z|]+\)' | tr -d ' )' | tr '|' '\n' | sort -u | tr '\n' ' ')"
  [ "$named" = "$have" ] || { echo "guide names: $named / script has: $have"; false; }
  ! grep -q 'baseline.html' "$g"   # the copied-page path of 2.114.0 is gone
  # P117 (20): Vite with a config outside ui.dir runs through the config runner, the copy is never rewritten
  grep -q -- '"--configLoader", "runner"' "$g"; grep -q 'copy_extra' "$g"; grep -q '{"scroll": <selector>}' "$g"; grep -q 'first_shot_timeout_s' "$g"
}

@test "AC8 /aid-init proposes the kit's ui keys for a Vite project, and says what it cannot find" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-ui-config.sh"
  touch "$P/ui/vite.config.ts"; printf "fetch('/api/data')\n" > "$P/ui/src/api.ts"
  run aid_ui_config_detect "$P"; echo "$output"
  [ "$(yq '.ui.dir' <<< "$output")" = ui ]; [ "$(yq '.ui.components' <<< "$output")" = ui/src/components/shared ]
  [ "$(yq -o=json -I=0 '.ui.dev_cmd' <<< "$output")" = '["npx","vite","--port","{port}","--host","127.0.0.1","--strictPort"]' ]
  [ "$(yq '.ui.ready_path' <<< "$output")" = / ]; [ "$(yq '.ui.api_prefix' <<< "$output")" = /api/ ]
  rm "$P/ui/vite.config.ts"
  run aid_ui_config_detect "$P"; [[ "$output" == "# ui: no vite.config"* ]]
}
