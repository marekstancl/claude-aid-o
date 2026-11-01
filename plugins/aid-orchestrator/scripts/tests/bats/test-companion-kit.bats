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

@test "kit F: ui.copy_extra copies repository files beside the copy and refuses secrets and outside paths; a scrolling container is captured whole; the first-shot limit is 1..120 s" {
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
  local t0=$SECONDS; run _k shots; [ "$status" -ne 0 ]; (( SECONDS - t0 < 12 )); [[ "$output" != *"taken again"* ]]   # not a network error: no retry
  yq -i '.ui.first_shot_timeout_s = 500' "$P/.aid-o/config/project.yaml"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"first_shot_timeout_s must be whole seconds from 1 to 120"* ]]
}

@test "AC5 down: a recorded prototype whose identity does not match (pid reused) is not killed and its record stays" {
  mkdir -p "$D"; setsid sleep 300 & local other=$!; sleep 0.2                 # a real group leader of its own
  jq -n --argjson p "$other" '{pid: $p, pgid: $p, starttime: "1", cmd: "sleep", port: 1, url: "x"}' > "$D/proto.json"
  run _k down; echo "$output"
  [[ "$output" == *"not the one we started"* ]]; [ "$status" -ne 0 ]; [ -e "$D/proto.json" ]
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
# _checks [<clipped json>] — a check record for every png in shots/, as the shots step writes it (K1): bound to the png,
# the viewport and the entry of shots.json; <clipped> (default []) for every shot
_checks() {
  (cd "$AID_PLUGIN_PATH/lib/brainstorm-server" && node --input-type=module -e '
    import fs from "node:fs"; import path from "node:path"; import { sha, shotSha } from "./kit-extra.mjs";
    const [D, clipped] = process.argv.slice(1); const spec = JSON.parse(fs.readFileSync(path.join(D, "shots.json"), "utf8"));
    const by = Object.fromEntries(spec.shots.map(x => [x.name, x]));
    for (const vp of fs.readdirSync(path.join(D, "shots"))) for (const f of fs.readdirSync(path.join(D, "shots", vp))) {
      if (!f.endsWith(".png")) continue; const n = f.slice(0, -4), png = path.join(D, "shots", vp, f);
      fs.writeFileSync(png.replace(/\.png$/, ".check.json"), JSON.stringify({ png_sha256: sha(png), viewport: vp,
        shot_sha256: by[n] ? shotSha(by[n]) : "none", mocks_missing: false, dialogs: 0, clipped: JSON.parse(clipped) }));
    }' "$D" "${1:-[]}")
}

_proposal() {
  _k proto >/dev/null
  mkdir -p "$D/shots/desktop" "$D/shots/mobile"
  local v s
  node -e 'const z=require("zlib"),fs=require("fs");const w=+process.argv[2],h=+process.argv[3];const raw=Buffer.alloc((w*3+1)*h,255);for(let y=0;y<h;y++)raw[y*(w*3+1)]=0;const c=t=>{let r=0xffffffff;for(const x of t){r^=x;for(let k=0;k<8;k++)r=r&1?(r>>>1)^0xedb88320:r>>>1}return (r^0xffffffff)>>>0};const ch=(t,d)=>{const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const cr=Buffer.alloc(4);cr.writeUInt32BE(c(td));return Buffer.concat([l,td,cr])};const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=2;fs.writeFileSync(process.argv[1],Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),ch("IHDR",ih),ch("IDAT",z.deflateSync(raw)),ch("IEND",Buffer.alloc(0))]))' "$D/shots/desktop/a.png" 1280 720
  for v in desktop mobile; do for s in dnes a b; do [[ "$v/$s" == desktop/a ]] || cp "$D/shots/desktop/a.png" "$D/shots/$v/$s.png"; done; done
  echo '{"base": "proto", "shots": [{"name": "dnes", "path": "/"}, {"name": "a", "path": "/?v=A"}, {"name": "b", "path": "/?v=B"}]}' > "$D/shots.json"
  _checks
  printf "import { Button } from '@/components/shared/Button';\nimport { Card } from '../components/shared';\nexport function Page() { return Button({ label: 'new' }) + Card({ title: 'x' }); }\n" > "$D/proto/src/pages/Page.tsx"
  printf "import { Card } from './shared';\nexport function Novy() { return Card({ title: 'n' }); }\n" > "$D/proto/src/components/Novy.tsx"
  cat > "$D/navrh.json" <<'EOF'
{"plan": "P900", "kolo": 1, "rozhodnuto": [], "prohlidka_snimku": "Každý snímek prohlédnut: řádek, blok i dnešní stav celé, nic neuříznuté.",
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

# a dev server as `npx vite` really runs: node renames itself to "npm exec vite" (a name with spaces) and serves from a
# child; <child> is "term" (stops on TERM) or "stubborn" (ignores TERM)
_renamed_dev() {
  yq -i ".ui.dev_cmd = [\"node\", \"-e\", \"process.title='npm exec vite'; const {spawn}=require('child_process'); spawn('python3', ['-c', 'import signal,sys,http.server as h; signal.signal(signal.SIGTERM, signal.SIG_IGN) if sys.argv[2]==\\\"stubborn\\\" else None; h.test(HandlerClass=h.SimpleHTTPRequestHandler, port=int(sys.argv[1]), bind=\\\"127.0.0.1\\\")', process.argv[1], '$1'], {stdio: 'inherit'}); setInterval(()=>{}, 1000)\", \"{port}\"]" "$P/.aid-o/config/project.yaml"
}
_gone() {  # <pgid> <port>: no member left and the port closed (a failing pgrep or ss is not "gone")
  local rc=0 out; pgrep -g "$1" >/dev/null || rc=$?; [ "$rc" -eq 1 ]
  out="$(ss -ltnH "sport = :$2")"; [ -z "$out" ]
}

@test "down stops a prototype whose leader renamed itself (npm exec vite) with its child, closes the port, spares another group" {
  _renamed_dev term
  run _k proto; echo "$output"; [ "$status" -eq 0 ]
  local pg port; pg="$(jq -r .pgid "$D/proto.json")"; port="$(jq -r .port "$D/proto.json")"
  [[ "$(cat /proc/$pg/cmdline | tr '\0' ' ')" == "npm exec vite"* ]]
  setsid sleep 60 & local other=$!
  run _k down; echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"prototype group ${pg} stopped"* ]]
  _gone "$pg" "$port"; [ ! -e "$D/proto.json" ]
  kill -0 "$other"; kill "$other"
}

@test "down kills a child that ignores TERM; a group whose leader is gone while a child serves keeps its record" {
  _renamed_dev stubborn
  run _k proto; [ "$status" -eq 0 ]
  local pg port; pg="$(jq -r .pgid "$D/proto.json")"; port="$(jq -r .port "$D/proto.json")"
  run _k down; echo "$output"; [ "$status" -eq 0 ]; _gone "$pg" "$port"
  # the leader dies, its child keeps serving: nothing can prove the group is ours, so nothing is signalled or forgotten
  run _k proto; [ "$status" -eq 0 ]; pg="$(jq -r .pgid "$D/proto.json")"; port="$(jq -r .port "$D/proto.json")"
  kill -KILL "$pg"; sleep 0.3
  run _k down; echo "$output"; [ "$status" -ne 0 ]; [ -e "$D/proto.json" ]; [[ "$output" == *"still"* ]]
  kill -KILL -- "-$pg"; sleep 0.3; _gone "$pg" "$port"
  run _k down; [ "$status" -eq 0 ]; [ ! -e "$D/proto.json" ]                  # nothing left: the stale record goes
}

@test "down keeps the record of a group that is gone while its port is still taken" {
  mkdir -p "$D"; python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); print(s.getsockname()[1], flush=True); time.sleep(60)' > "$BATS_TEST_TMPDIR/port" &
  local holder=$!; sleep 0.3; local port; port="$(cat "$BATS_TEST_TMPDIR/port")"
  jq -n --argjson port "$port" '{pid: 999999999, pgid: 999999999, starttime: "1", cmd: "x", port: $port, url: "x"}' > "$D/proto.json"
  run _k down; echo "$output"; [ "$status" -ne 0 ]; [ -e "$D/proto.json" ]; [[ "$output" == *"port ${port} is still open"* ]]
  kill "$holder"
}

@test "the copy carries the kit's .gitignore block after the app's own lines, an older copy gets it on the next proto, and it is no change of a variant" {
  printf 'secret.txt\n' > "$P/ui/.gitignore"
  run _k proto; [ "$status" -eq 0 ]
  head -1 "$D/proto/.gitignore" | grep -qx 'secret.txt'
  grep -qx '!\*/' "$D/proto/.gitignore"; grep -qx 'node_modules/' "$D/proto/.gitignore"
  _k down >/dev/null
  # a copy made before the block existed: the block comes with the next proto
  printf 'secret.txt\n' > "$D/proto/.gitignore"
  run _k proto; [ "$status" -eq 0 ]; grep -qx '!\*/' "$D/proto/.gitignore"
  _proposal; run _k show; echo "$output"; [ "$status" -eq 0 ]                 # the block is not an unlisted change
}

@test "copy_extra added, changed and removed after the first proto is brought in line; show refuses a foreign file beside an allowed one" {
  mkdir -p "$P/shared"; echo "a{}" > "$P/shared/base.css"; echo "b{}" > "$P/shared/other.css"
  run _k proto; [ "$status" -eq 0 ]; [ ! -e "$D/shared" ]
  yq -i '.ui.copy_extra = ["shared/base.css", "shared/other.css"]' "$P/.aid-o/config/project.yaml"
  run _k proto; echo "$output"; [ "$status" -eq 0 ]                            # reused: the running copy gets them
  [ "$(jq -r .reused <<< "$output")" = true ]; [ "$(cat "$D/shared/base.css")" = "a{}" ]
  echo "a2{}" > "$P/shared/base.css"; yq -i '.ui.copy_extra = ["shared/base.css"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -eq 0 ]
  [ "$(cat "$D/shared/base.css")" = "a2{}" ]; [ ! -e "$D/shared/other.css" ]   # changed copied again, removed taken away
  [ "$(jq -r '.extra[0].rel' "$D/proto-manifest.json")" = "shared/base.css" ]
  _proposal; run _k show; echo "$output"; [ "$status" -eq 0 ]                 # the file proto put there is the kit's
  echo x > "$D/shared/tool.sh"
  run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"shared/tool.sh is not one of the kit's files"* ]]
}

@test "proto says how stale the copy is; --refresh stops it, sets the copy, manifest and shots aside, twice without collision, and show works after" {
  _proposal; run _k up; [ "$status" -eq 0 ]
  echo "/* changed */" >> "$P/ui/index.html"
  run _k proto; echo "$output"; [ "$status" -eq 0 ]; [ "$(jq -r .stale <<< "$output")" = 1 ]; [[ "$(jq -r .refresh <<< "$output")" == *"--refresh"* ]]
  local pg; pg="$(jq -r .pgid "$D/proto.json")"
  run _k proto --refresh; echo "$output"; [ "$status" -eq 0 ]
  local rc=0; pgrep -g "$pg" >/dev/null || rc=$?; [ "$rc" -eq 1 ]             # the old group is gone
  [ "$(ls "$D/old" | wc -l)" -eq 1 ]; local o; o="$D/old/$(ls "$D/old")"
  [ -f "$o/proto/src/pages/Page.tsx" ] && [ -f "$o/proto-manifest.json" ] && [ -d "$o/shots" ]
  [ "$(tail -1 <<< "$output" | jq -r .stale)" = 0 ]; cmp "$P/ui/src/pages/Page.tsx" "$D/proto/src/pages/Page.tsx"   # a fresh copy of the app
  run _k proto --refresh; [ "$status" -eq 0 ]; [ "$(ls "$D/old" | wc -l)" -eq 2 ]
  _proposal; run _k show; echo "$output"; [ "$status" -eq 0 ]                 # old/ does not block the kit
}

@test "the kit never writes or removes through a link or a crafted path: a linked .gitignore, a dangling extra target, a recorded ../ path, a reserved name" {
  printf 'keep.txt\n' > "$P/ui/.gitignore"; local app_gi; app_gi="$(sha256sum < "$P/ui/.gitignore")"
  run _k proto; [ "$status" -eq 0 ]; _k down >/dev/null
  rm "$D/proto/.gitignore"; ln -s "$P/ui/.gitignore" "$D/proto/.gitignore"          # the copy's .gitignore points at the app's
  sed -i '/aid-companion/d' "$P/ui/.gitignore"
  run _k proto; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"is a link"* ]]; [ "$(sha256sum < "$P/ui/.gitignore")" = "$app_gi" ]
  rm "$D/proto/.gitignore"; printf 'keep.txt\n' > "$D/proto/.gitignore"
  mkdir -p "$P/shared" "$BATS_TEST_TMPDIR/out"; echo "a{}" > "$P/shared/a.css"
  mkdir -p "$D/shared"; ln -s "$BATS_TEST_TMPDIR/out/a.css" "$D/shared/a.css"     # a dangling link where the extra lands
  yq -i '.ui.copy_extra = ["shared/a.css"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"is a link"* ]]; [ ! -e "$BATS_TEST_TMPDIR/out/a.css" ]
  rm "$D/shared/a.css"; run _k proto; [ "$status" -eq 0 ]; _k down >/dev/null
  jq '.extra += [{rel: "shared/../proto/src/pages/Page.tsx", sha256: "x"}]' "$D/proto-manifest.json" > "$BATS_TEST_TMPDIR/m" && cp "$BATS_TEST_TMPDIR/m" "$D/proto-manifest.json"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"not a plain relative path"* ]]; [ -f "$D/proto/src/pages/Page.tsx" ]
  jq '.extra |= map(select(.rel == "shared/a.css"))' "$D/proto-manifest.json" > "$BATS_TEST_TMPDIR/m" && cp "$BATS_TEST_TMPDIR/m" "$D/proto-manifest.json"
  echo x > "$P/navrh-1.html"; yq -i '.ui.copy_extra = ["navrh-1.html"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -ne 0 ]; [[ "$output" == *"the kit's own navrh-1.html"* ]]
}

@test "the last extra removed takes its empty directory, --refresh keeps the record so a dropped extra still goes, a fresh copy is not stale, and an older copy's .gitignore is no change" {
  mkdir -p "$P/shared" "$P/ui/storybook-static"; echo "a{}" > "$P/shared/a.css"; echo x > "$P/ui/storybook-static/s.js"
  ln -s index.html "$P/ui/alias.html"                                              # a link inside ui.dir is copied as content
  printf 'keep.txt\n' > "$P/ui/.gitignore"
  yq -i '.ui.copy_extra = ["shared/a.css"]' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -eq 0 ]; run _k proto; [ "$(tail -1 <<< "$output" | jq -r .stale)" = 0 ]    # fresh: not stale
  yq -i '.ui.copy_extra = []' "$P/.aid-o/config/project.yaml"
  run _k proto; [ "$status" -eq 0 ]; [ ! -e "$D/shared" ]
  yq -i '.ui.copy_extra = ["shared/a.css"]' "$P/.aid-o/config/project.yaml"; run _k proto; [ -f "$D/shared/a.css" ]
  yq -i '.ui.copy_extra = []' "$P/.aid-o/config/project.yaml"
  run _k proto --refresh; echo "$output"; [ "$status" -eq 0 ]; [ ! -e "$D/shared" ]       # dropped while refreshing: still removed
  # a copy made before 3.14.0: a flat manifest that hashed .gitignore byte for byte
  _k down >/dev/null
  jq --arg h "$(sha256sum < "$D/proto/.gitignore" | cut -d' ' -f1)" '.files + {".gitignore": $h}' "$D/proto-manifest.json" > "$BATS_TEST_TMPDIR/m"
  sed -i '/aid-companion: begin/,/aid-companion: end/d' "$D/proto/.gitignore"
  jq --arg h "$(sha256sum < "$D/proto/.gitignore" | cut -d' ' -f1)" '. + {".gitignore": $h}' "$BATS_TEST_TMPDIR/m" > "$D/proto-manifest.json"
  run _k proto; echo "$output"; [ "$status" -eq 0 ]; [ "$(tail -1 <<< "$output" | jq -r .stale)" = null ]
  _proposal; run _k show; echo "$output"; [ "$status" -eq 0 ]
}

# a dev server that answers the first request for /flaky.html with bytes that are no HTTP (the browser fails it with a
# net::ERR_ error and does not repeat it, as a dropped connection would be repeated) and every
# request for /broken.html; set.html stores a value, flaky.html shows what storage holds
_flaky_dev() {
  cat > "$P/ui/server.py" <<'PY'
import http.server, sys
seen = {}
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        p = self.path.split('?')[0]
        seen[p] = seen.get(p, 0) + 1
        if p == '/broken.html' or (p in ('/flaky.html', '/flaky2.html') and seen[p] == 1):
            self.wfile.write(b'garbage that is no HTTP\r\n\r\n'); self.close_connection = True; return
        return super().do_GET()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
  echo '<html><body><script>localStorage.setItem("x","1"); document.cookie="c=1"</script>set</body></html>' > "$P/ui/set.html"
  echo '<html><body><p id="v"></p><script>document.getElementById("v").textContent = "x=" + (localStorage.getItem("x") || "none") + " c=" + (document.cookie.includes("c=1") ? "1" : "none")</script></body></html>' > "$P/ui/flaky.html"
  cp "$P/ui/flaky.html" "$P/ui/broken.html"
  echo '<html><body><script>localStorage.setItem("n", String(+(localStorage.getItem("n") || 0) + 1))</script>bump</body></html>' > "$P/ui/bump.html"
  echo '<html><body><p id="v"></p><script>document.getElementById("v").textContent = "n=" + localStorage.getItem("n") + " s=" + localStorage.getItem("s")</script></body></html>' > "$P/ui/flaky2.html"
  yq -i '.ui.dev_cmd = ["python3", "server.py", "{port}"] | .ui.ready_path = "/index.html"' "$P/.aid-o/config/project.yaml"
  mkdir -p "$D"; echo '[]' > "$D/mocks.json"
}

@test "a shot that fails on a network error is taken again once in a fresh context; a second failure stops the set; --only takes just the named shots" {
  _flaky_dev; run _k proto; [ "$status" -eq 0 ]
  cat > "$D/shots.json" <<'J'
{"base": "proto", "shots": [{"name": "nastav", "path": "/set.html"},
  {"name": "flaky", "path": "/flaky.html", "only": ["desktop"], "steps": [{"wait": {"for": {"text": "x=none c=none"}}}]}]}
J
  run _k shots; echo "$output"; [ "$status" -eq 0 ]                          # retried, and nothing of shot 1 carried over
  [ -s "$D/shots/desktop/flaky.png" ]
  echo '{"base": "proto", "shots": [{"name": "broken", "path": "/broken.html"}]}' > "$D/shots.json"
  run _k shots; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"net::ERR_"* ]]
  [ "$(grep -c 'taken again' <<< "$output")" -eq 1 ]                           # once, not twice
  # a step of the same shot changed storage before the failing navigation: the retry starts from shots.json's storage
  cat > "$D/shots.json" <<'J'
{"base": "proto", "storage": {"localStorage": {"s": "spec"}}, "shots": [{"name": "kroky", "path": "/bump.html", "only": ["desktop"],
  "steps": [{"goto": "/flaky2.html"}, {"wait": {"for": {"text": "n=1 s=spec"}}}]}]}
J
  run _k shots; echo "$output"; [ "$status" -eq 0 ]; [ "$(grep -c 'taken again' <<< "$output")" -eq 1 ]
  cat > "$D/shots.json" <<'J'
{"base": "proto", "shots": [{"name": "nastav", "path": "/set.html"}, {"name": "flaky", "path": "/flaky.html"}]}
J
  local before nastav; before="$(stat -c %Y "$D/shots/desktop/flaky.png")"; nastav="$(stat -c %Y "$D/shots/desktop/nastav.png")"; sleep 1
  run _k shots --only nastav; echo "$output"; [ "$status" -eq 0 ]
  [ "$(stat -c %Y "$D/shots/desktop/flaky.png")" = "$before" ]                # the other shot is untouched
  [ "$(stat -c %Y "$D/shots/desktop/nastav.png")" -gt "$nastav" ]              # the named one is taken again
  run _k shots --only nikdo; [ "$status" -ne 0 ]; [[ "$output" == *"no such shot"* ]]
}

@test "a full-page shot prints a pinned bar once, where it sits in the page, not over the content" {
  echo '<html><body style="margin:0"><div style="position:fixed;bottom:0;left:0;right:0;height:40px;background:#ff0000"></div><div style="height:3000px;background:#ffffff">dlouhy obsah</div></body></html>' > "$P/ui/long.html"
  run _k proto; [ "$status" -eq 0 ]; mkdir -p "$D"; echo '[]' > "$D/mocks.json"
  echo '{"base": "proto", "shots": [{"name": "dlouha", "path": "/long.html", "capture": "full"}]}' > "$D/shots.json"
  run _k shots; echo "$output"; [ "$status" -eq 0 ]
  run node -e '
    const { createRequire } = require("module"); const r = createRequire(process.argv[2]);
    const { PNG } = r("pngjs"); const p = PNG.sync.read(require("fs").readFileSync(process.argv[1]));
    const red = []; for (let y = 0; y < p.height; y++) { const i = (y * p.width + 5) * 4; if (p.data[i] > 200 && p.data[i + 1] < 60) red.push(y); }
    console.log(red.length, red[0], p.height);' "$D/shots/desktop/dlouha.png" "$AID_PLUGIN_PATH/lib/ui-fidelity/package.json"
  echo "$output"; read -r n first h <<< "$output"
  [ "$n" -ge 35 ] && [ "$n" -le 45 ]; [ "$first" -le 5 ]                       # once, at the top of the page's flow
  # the page's styles are put back: a next shot in the same page (only the #hash changes, no reload) sees the bar pinned
  echo '{"base": "proto", "shots": [{"name": "dlouha", "path": "/long.html", "capture": "full"}, {"name": "okno", "path": "/long.html#dole", "only": ["desktop"]}]}' > "$D/shots.json"
  run _k shots; [ "$status" -eq 0 ]
  run node -e '
    const { createRequire } = require("module"); const r = createRequire(process.argv[2]);
    const { PNG } = r("pngjs"); const p = PNG.sync.read(require("fs").readFileSync(process.argv[1]));
    const i = ((p.height - 10) * p.width + 5) * 4; console.log(p.data[i] > 200 && p.data[i + 1] < 60 ? "pinned" : "gone");' "$D/shots/desktop/okno.png" "$AID_PLUGIN_PATH/lib/ui-fidelity/package.json"
  [ "$output" = pinned ]
}

@test "a scrolling container is captured whole also when an ancestor clips it (overflow hidden, a fixed height)" {
  echo '<html><body style="margin:0"><div id="shell" style="height:200px;overflow:hidden"><div id="list" style="height:100px;overflow:auto"><div style="height:600px;background:#00ff00">obsah</div></div></div></body></html>' > "$P/ui/shell.html"
  run _k proto; [ "$status" -eq 0 ]; echo '[]' > "$D/mocks.json"
  echo '{"base": "proto", "shots": [{"name": "seznam", "path": "/shell.html", "only": ["desktop"], "capture": {"scroll": {"css": "#list"}}}]}' > "$D/shots.json"
  run _k shots; echo "$output"; [ "$status" -eq 0 ]
  run node -e '
    const { createRequire } = require("module"); const r = createRequire(process.argv[2]);
    const { PNG } = r("pngjs"); const p = PNG.sync.read(require("fs").readFileSync(process.argv[1])); let g = 0;
    for (let y = 0; y < p.height; y++) { const i = (y * p.width + 5) * 4; if (p.data[i + 1] > 200 && p.data[i] < 60) g++; } console.log(g);' "$D/shots/desktop/seznam.png" "$AID_PLUGIN_PATH/lib/ui-fidelity/package.json"
  [ "$output" -ge 590 ]                                                        # the whole 600 px of content, not the 200 the shell shows
}

# pages with dialogs: one that fits, a hidden one with overflowing content, a table that scrolls inside its dialog on
# purpose, a dialog whose content is cut off at its edge, and a page wider than the phone
_dialog_pages() {
  local dlg='position:fixed;top:40px;left:40px;width:300px;height:200px;overflow:hidden;background:#fff;border:1px solid #000'
  echo "<html><body><div role=dialog aria-label=Ok style='$dlg'><p>vejde se</p></div></body></html>" > "$P/ui/ok.html"
  echo "<html><body><div role=dialog style='$dlg;display:none'><div style='width:900px'>skryte</div></div></body></html>" > "$P/ui/hidden.html"
  echo "<html><body><div role=dialog style='$dlg'><div style='overflow-x:auto'><table style='width:900px'><tr><td>siroka tabulka</td></tr></table></div></div></body></html>" > "$P/ui/scroll.html"
  echo "<html><body><div role=dialog aria-label=Prevod style='$dlg'><div class=paticka style='width:520px'>tlacitko uriznute</div></div></body></html>" > "$P/ui/clip.html"
  echo "<html><body style='margin:0'><div style='width:600px'>siroka stranka</div></body></html>" > "$P/ui/wide.html"
}
_navrh() {  # <minule shot> <option A shot> [vady json]
  cat > "$D/navrh.json" <<J
{"plan": "P900", "kolo": 1, "prohlidka_snimku": "Prohlédl jsem všechny snímky.", "vady_aplikace": ${3:-[]},
 "body": [{"id": "1", "title": "Okno", "otazka": "Jak?", "doporuceni": "A", "proc": "Proto.",
   "minule": [{"popisek": "Dnes", "shot": "$1"}],
   "moznosti": [{"klic": "A", "nazev": "A", "popis": "a", "snimky": [{"popisek": "A", "shot": "$2"}]}]}]}
J
}

@test "every shot is checked for a cut-off dialog and a page wider than the window; show refuses one in an option, shows one of today's app as its defect" {
  _dialog_pages; run _k proto; [ "$status" -eq 0 ]; run _k up; [ "$status" -eq 0 ]; echo '[]' > "$D/mocks.json"
  echo '{"base": "proto", "shots": [{"name": "ok", "path": "/ok.html"}, {"name": "hidden", "path": "/hidden.html"}, {"name": "scroll", "path": "/scroll.html"}, {"name": "clip", "path": "/clip.html"}, {"name": "wide", "path": "/wide.html"}]}' > "$D/shots.json"
  run _k shots; echo "$output"; [ "$status" -eq 0 ]
  local c=$D/shots
  [ "$(jq -c '[(.clipped|length), .dialogs]' "$c/desktop/ok.check.json")" = "[0,1]" ]
  [ "$(jq '.clipped|length' "$c/desktop/hidden.check.json")" = 0 ]
  [ "$(jq '.clipped|length' "$c/desktop/scroll.check.json")" = 0 ]
  jq -e '.clipped[] | select(.pravidlo == "beyond_dialog_edge" and (.prvek | test("paticka")))' "$c/desktop/clip.check.json"
  [ "$(jq '.clipped|length' "$c/desktop/wide.check.json")" = 0 ]
  jq -e '.clipped[] | select(.pravidlo == "page_wider_than_window")' "$c/mobile/wide.check.json"
  _navrh ok clip; run _k show; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"option A snimky[0]: shot 'clip' (desktop) is cut off — beyond_dialog_edge"* ]]
  _navrh clip ok; run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"list it in vady_aplikace"* ]]
  _navrh clip ok '[{"snimek": "clip", "popis": "Okno převodu klienta je širší než panel, patička je uříznutá."}]'
  run _k show; echo "$output"; [ "$status" -eq 0 ]; [[ "$(jq -r '.look[0]' <<< "$output")" == *"shots/desktop/clip.png" ]]
  grep -q 'Vada dnešní aplikace' "$D/navrh-1.html"; grep -q 'patička je uříznutá' "$D/navrh-1.html"
  jq 'del(.prohlidka_snimku)' "$D/navrh.json" > "$D/n.t" && mv "$D/n.t" "$D/navrh.json"
  run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"prohlidka_snimku"* ]]
}

@test "show refuses a shot without its check, one whose png or shots.json entry changed since, and the shots of a run with an unmocked call" {
  _dialog_pages; run _k proto; [ "$status" -eq 0 ]; echo '[]' > "$D/mocks.json"
  echo '{"base": "proto", "shots": [{"name": "ok", "path": "/ok.html"}, {"name": "scroll", "path": "/scroll.html"}]}' > "$D/shots.json"
  run _k shots; [ "$status" -eq 0 ]; _navrh ok scroll; run _k show; echo "$output"; [ "$status" -eq 0 ]
  rm "$D/shots/mobile/scroll.check.json"
  run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"shot 'scroll' (mobile) has no check record"* ]]
  run _k shots; [ "$status" -eq 0 ]; cp "$D/shots/desktop/ok.png" "$D/shots/desktop/scroll.png"
  run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"shot 'scroll' (desktop) changed since it was checked"* ]]
  run _k shots; [ "$status" -eq 0 ]; jq '.shots[1].path = "/scroll.html?x=1"' "$D/shots.json" > "$D/s.t" && mv "$D/s.t" "$D/shots.json"
  run _k show; [ "$status" -ne 0 ]; [[ "$output" == *"changed since it was checked"* ]]
  echo "<html><body><script>fetch('/api/nic')</script><div role=dialog style='width:100px'>x</div></body></html>" > "$D/proto/scroll.html"
  run _k shots; [ "$status" -ne 0 ]; [[ "$output" == *"no mock"* ]]
  run _k show; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"API calls without a mock"* ]]
}
