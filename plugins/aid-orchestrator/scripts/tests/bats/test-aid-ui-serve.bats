#!/usr/bin/env bats
# aid-tier: t2
# test-aid-ui-serve.bats — aid-ui-serve.sh (P101 Step 2, P103 Step 3): the
# studio page and the brand page run as aid-job.sh jobs and stop independently.
# t2: it starts processes and binds ports 39915-39918 (39918: the P113 skeleton).

setup() {
  SERVE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-ui-serve.sh"
  export AID_UI_HOST=127.0.0.1 AID_UI_STUDIO_PORT=39915 AID_UI_BRAND_PORT=39916 AID_UI_SKELETON_PORT=39918
  export AID_UI_JOBS_DIR="$BATS_TEST_TMPDIR/jobs" AID_UI_PROJECT="$BATS_TEST_TMPDIR"
  export AID_UI_STATE_DIR="$BATS_TEST_TMPDIR/state"
  FOREIGN_PIDS=()
  BRAND="$BATS_TEST_TMPDIR/proj/docs/brand" BRAND2="$BATS_TEST_TMPDIR/proj2/docs/brand"
  mkdir -p "$BRAND" "$BRAND2" "$BATS_TEST_TMPDIR/page"
  echo brand-ok > "$BRAND/index.html"
  echo brand2-ok > "$BRAND2/index.html"
  touch "$BRAND/tokens.css" "$BRAND2/tokens.css"
  echo page-ok > "$BATS_TEST_TMPDIR/page/index.html"
}

teardown() {
  "$SERVE" stop studio || true
  "$SERVE" stop brand || true
  "$SERVE" stop skeleton 2>/dev/null || true
  local p; for p in "${FOREIGN_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}

# A server the test owns (not a job of ours); fd 3 closed so bats is not held.
foreign_server() {   # <port> <dir>
  python3 -m http.server "$1" --bind 127.0.0.1 --directory "$2" >/dev/null 2>&1 3>&- &
  FOREIGN_PIDS+=("$!")
  local i; for i in $(seq 1 50); do
    [[ -n "$(ss -ltnH "sport = :$1")" ]] && return 0; sleep 0.1
  done
  return 1
}

get() { curl -sf --max-time 3 "http://127.0.0.1:$1/"; }

@test "studio serves the page on the studio port with a fresh token in the project" {
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 0 ]
  code="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.code")"
  [[ "$code" =~ ^[0-9a-f]{32}$ ]]
  [[ "$output" == *"URL: http://127.0.0.1:39915/?k=$code"* ]]
  [[ "$output" == *"JOB: aid-ui-studio-39915"* ]]
  tok="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")"
  [[ "$tok" =~ ^[0-9a-f]{32}$ ]]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" = 600 ]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.code")" = 600 ]
  ! get 39915                                   # no link, no page
  curl -s --max-time 3 "http://127.0.0.1:39915/" | grep -q "Otevřete odkaz ze zprávy agenta"
  curl -s --max-time 3 -L -c "$BATS_TEST_TMPDIR/jar" -b "$BATS_TEST_TMPDIR/jar" "http://127.0.0.1:39915/?k=$code" | grep -q "AID studio"
  ! grep -rq "$tok" <(curl -s --max-time 3 -b "$BATS_TEST_TMPDIR/jar" "http://127.0.0.1:39915/")
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "X-AID-Token: $tok" http://127.0.0.1:39915/state)" = 200 ]
}

@test "studio twice keeps the server and its token; studio after stop studio gets a new token" {
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  tok="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")"
  code1="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.code")"
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" = "$tok" ]
  code2="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.code")"
  [ "$code2" != "$code1" ]
  [[ "$output" == *"URL: http://127.0.0.1:39915/?k=$code2"* ]]
  curl -s --max-time 3 -L -c "$BATS_TEST_TMPDIR/jar" -b "$BATS_TEST_TMPDIR/jar" "http://127.0.0.1:39915/?k=$code2" | grep -q "AID studio"
  run "$SERVE" stop studio
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" != "$tok" ]
  curl -s --max-time 3 -L -c "$BATS_TEST_TMPDIR/jar2" -b "$BATS_TEST_TMPDIR/jar2" "http://127.0.0.1:39915/?k=$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.code")" | grep -q "AID studio"
  ls -d "$AID_UI_JOBS_DIR"/aid-ui-studio-39915.superseded-*
}

@test "studio on a port held by a foreign server: exit 1 naming the port, foreign alive" {
  foreign_server 39915 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port 39915 in use"* ]]
  [ "$(get 39915)" = page-ok ]
}

@test "studio of a path that is not a directory: exit 2" {
  run "$SERVE" studio "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == ERROR:* ]]
}

@test "stop studio leaves the brand server answering" {
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  "$SERVE" brand "$BRAND"
  run "$SERVE" stop studio
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "brand serves a directory" {
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39916/"* ]]
  [ "$(get 39916)" = brand-ok ]
}

@test "brand twice returns the same URL; brand after stop brand answers again" {
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]; first="$output"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  "$SERVE" stop brand
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "stop brand from outside the project stops the server it started" {
  "$SERVE" brand "$BRAND"
  [ "$(get 39916)" = brand-ok ]
  run env -u AID_UI_JOBS_DIR -u AID_UI_PROJECT bash -c 'cd / && "$0" stop brand' "$SERVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped the brand server of project $(realpath "$BATS_TEST_TMPDIR")"* ]]
  for i in $(seq 1 50); do [[ -z "$(ss -ltnH "sport = :39916")" ]] && break; sleep 0.1; done
  [ -z "$(ss -ltnH "sport = :39916")" ]
}

@test "stop brand from another project refuses to stop this project's server, naming both" {
  "$SERVE" brand "$BRAND"
  other="$BATS_TEST_TMPDIR/proj2"; me="$(realpath "$BATS_TEST_TMPDIR")"
  run env AID_UI_PROJECT="$other" AID_UI_JOBS_DIR="$other/.aid-ui/jobs" "$SERVE" stop brand
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to project $me, not $(realpath "$other")"* ]]
  git init -q "$other"   # cwd inside a git project, no AID_UI_PROJECT
  run env -u AID_UI_JOBS_DIR -u AID_UI_PROJECT bash -c 'cd "$1/docs" && "$0" stop brand' "$SERVE" "$other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to project $me, not $(realpath "$other")"* ]]
  [ "$(get 39916)" = brand-ok ]
}

@test "a port held by a foreign http.server: exit 1 naming the port, foreign alive" {
  foreign_server 39916 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 1 ]
  [[ "$output" == *"39916"* ]]
  kill -0 "${FOREIGN_PIDS[0]}"
  [ "$(get 39916)" = page-ok ]
}

@test "stop brand with no job of ours leaves a foreign listener alive, exit 0" {
  foreign_server 39916 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" stop brand
  [ "$status" -eq 0 ]
  kill -0 "${FOREIGN_PIDS[0]}"
  [ "$(get 39916)" = page-ok ]
}

@test "brand of a directory that is not a brand page: exit 2, nothing served" {
  run "$SERVE" brand "$BATS_TEST_TMPDIR/page"
  [ "$status" -eq 2 ]
  [[ "$output" == ERROR:* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand outside a docs/brand dir, even with index.html and tokens.css or via a docs/brand symlink: exit 2" {
  cp -r "$BRAND" "$BATS_TEST_TMPDIR/elsewhere"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/elsewhere"
  [ "$status" -eq 2 ]; [[ "$output" == ERROR:* ]]
  mkdir -p "$BATS_TEST_TMPDIR/proj3/docs"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/proj3/docs/brand"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/proj3/docs/brand"
  [ "$status" -eq 2 ]; [[ "$output" == ERROR:* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of a folder holding state.json: exit 2 naming it, nothing served" {
  echo '{}' > "$BRAND/state.json"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BRAND/state.json"*"state.json must not be served"* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of a folder with a leftover temp file or a foreign file: exit 2 naming it" {
  mkdir -p "$BRAND/assets" "$BRAND/fonts"
  touch "$BRAND/assets/a.png" "$BRAND/fonts/f.woff2" "$BRAND/base.css"
  for f in index.html.Ab3xZ9 assets/x.tmp notes.md sub/y.css; do
    mkdir -p "$(dirname "$BRAND/$f")"; touch "$BRAND/$f"
    run "$SERVE" brand "$BRAND"
    [ "$status" -eq 2 ]
    [[ "$output" == *"$BRAND/$f"* ]]
    rm "$BRAND/$f"
  done
  run get 39916; [ "$status" -ne 0 ]
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
}

@test "brand of a folder holding a symlink: exit 2 naming it, nothing served" {
  mkdir -p "$BRAND/assets"
  echo secret > "$BATS_TEST_TMPDIR/secret"
  ln -s "$BATS_TEST_TMPDIR/secret" "$BRAND/assets/x.png"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BRAND/assets/x.png is a symlink"* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of another directory while one is served: restarts on the new one" {
  "$SERVE" brand "$BRAND"
  run "$SERVE" brand "$BRAND2"
  [ "$status" -eq 0 ]
  [ "$(get 39916)" = brand2-ok ]
}

@test "stop without a role exits 2" {
  run "$SERVE" stop
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------- P113 step 6: the live skeleton at a fixed address
skel_project() {   # skel_project <dir>: a structure of two pages, the facts register with one open fact
  local p="$1"; mkdir -p "$p/.aid-ui" "$p/docs/content"
  cat > "$p/.aid-ui/structure.json" <<'J'
{"lang": "cs", "pages": [
  {"id": "home", "url": "/", "h1": "Pekárna v Brně", "title": "Úvod", "sections": [{"id": "hero", "says": "Hlavní sdělení", "action": "Objednat", "facts": ["since"]}]},
  {"id": "sluzby", "url": "/služby/", "h1": "Služby", "title": "Služby", "sections": [{"id": "seznam", "says": "Seznam služeb", "facts": ["cena_chleba"]}]}],
 "nav": ["home", "sluzby"], "header": {"phone_key": "telephone", "cta": {"label": "Objednat", "url": "/sluzby/"}}, "footer": {"legal_keys": ["company"]},
 "redirects": [{"from": "/stare-sluzby/", "to": "/sluzby/"}]}
J
  cat > "$p/docs/content/facts.yaml" <<'Y'
brand: {value: "Pekárna U Mlýna", source: PM}
telephone: {value: "+420 777 123 456", source: PM}
company: {value: "Pekárna U Mlýna s.r.o.", source: PM}
since: {value: "peče od roku 1998", source: PM}
otevrene:
  cena_chleba: {value: "45 Kč", source: starý web}
Y
}

@test "skeleton: builds every page of the structure with navigation, header and footer, each marked and with meta viewport" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"
  run "$SERVE" skeleton "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"URL: http://127.0.0.1:39918/"* ]]
  for f in "$P/site/index.html" "$P/site/sluzby/index.html"; do   # the slug with diacritics normalised
    grep -q 'data-aid-skeleton' "$f"; grep -q 'name="viewport"' "$f"
    grep -q 'href="/sluzby/"' "$f"; grep -q 'href="tel:+420777123456"' "$f"; grep -q 'Pekárna U Mlýna s.r.o.' "$f"
  done
  [ "$(curl -sf --max-time 3 http://127.0.0.1:39918/sluzby/ | grep -c '<h1>Služby</h1>')" -eq 1 ]
  "$SERVE" stop skeleton
}

@test "skeleton: facts come only from the register - an open or missing fact waits for the client, a stray claim fails the check" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"
  python3 - "$P" <<'PY'
import json, sys; p = sys.argv[1] + "/.aid-ui/structure.json"; s = json.load(open(p)); s["pages"][1]["sections"][0]["facts"].append("nikde"); json.dump(s, open(p, "w"))
PY
  run python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P"; [ "$status" -eq 0 ]; [[ "$output" == *"fact nikde is not in docs/content/facts.yaml"* ]]
  ! grep -q '45 Kč' "$P/site/sluzby/index.html"   # the open price is not shown
  [ "$(grep -o 'čeká na klienta' "$P/site/sluzby/index.html" | wc -l)" -eq 2 ]
  grep -q 'peče od roku 1998' "$P/site/index.html"
  run "$SERVE" skeleton-check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  sed -i 's#<h1>Služby</h1>#<h1>Služby</h1><p>Volejte 602 111 222</p>#' "$P/site/sluzby/index.html"
  run "$SERVE" skeleton-check "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"not in facts.yaml: 602 111 222"* ]]
}

@test "skeleton: a rebuild keeps built pages and moves a page whose entry left the structure aside" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"
  python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P" >/dev/null
  echo '<!doctype html><html lang="cs"><head><meta name="viewport" content="width=device-width"><title>Úvod</title></head><body><h1>Postaveno</h1></body></html>' > "$P/site/index.html"
  python3 - "$P" <<'PY'
import json, sys; p = sys.argv[1] + "/.aid-ui/structure.json"; s = json.load(open(p)); s["pages"] = s["pages"][:1]; s["nav"] = ["home"]; s["redirects"] = []; json.dump(s, open(p, "w"))
PY
  run python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'Postaveno' "$P/site/index.html"; jq -e '.kept == ["index.html"] and .removed == ["sluzby/index.html"]' <<<"${lines[-1]}" >/dev/null
  [ -f "$P/.aid-ui/skeleton/removed/sluzby/index.html" ]; [ ! -e "$P/site/sluzby/index.html" ]
  [ ! -e "$P/.aid-ui/skeleton/redirects.csv" ]
  run "$SERVE" skeleton-check "$P"; [[ "$output" == *"bez starého webu"* ]]
}

@test "skeleton: the address survives a gate preview start and stop" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"
  "$SERVE" skeleton "$P" >/dev/null
  get 39918 | grep -q 'data-aid-skeleton'
  export AID_UI_PREVIEW_PORT=39919   # not 39917: the Coufal pilot's preview may hold it on this host
  "$SERVE" preview "$BATS_TEST_TMPDIR/page" >/dev/null; get 39919 | grep -q page-ok
  "$SERVE" stop preview
  get 39918 | grep -q 'data-aid-skeleton'   # still there
  run "$SERVE" skeleton "$P"; [ "$status" -eq 0 ]; [[ "$output" == *"JOB: aid-ui-skeleton-39918"* ]]   # idempotent
  "$SERVE" stop skeleton
  ! get 39918
}

@test "skeleton: a redirect target outside the tree is refused; 160 pages build in under 10 s" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"
  python3 - "$P" <<'PY'
import json, sys; p = sys.argv[1] + "/.aid-ui/structure.json"; s = json.load(open(p)); s["redirects"].append({"from": "/x/", "to": "/neni/"}); json.dump(s, open(p, "w"))
PY
  python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P" >/dev/null
  run "$SERVE" skeleton-check "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"redirect /x/ -> /neni/: target is not a page of the tree"* ]]
  Q="$BATS_TEST_TMPDIR/big"; skel_project "$Q"
  python3 - "$Q" <<'PY'
import json, sys; p = sys.argv[1] + "/.aid-ui/structure.json"; s = json.load(open(p))
s["pages"] += [{"id": "z%d" % i, "url": "/zakazky/z-%d/" % i, "h1": "Zakázka %d" % i, "title": "Zakázka", "sections": [{"id": "a", "says": "Popis zakázky"}]} for i in range(158)]
json.dump(s, open(p, "w"))
PY
  s=$(date +%s); python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$Q" >/dev/null; e=$(( $(date +%s) - s ))
  [ "$(find "$Q/site" -name index.html | wc -l)" -eq 160 ]; [ "$e" -lt 10 ]
}

@test "skeleton: a page the skeleton never wrote is never moved; a symlink or two urls on one file stop the build before any write" {
  P="$BATS_TEST_TMPDIR/sk"; skel_project "$P"; mkdir -p "$P/site/vlastni"; echo '<html><h1>Ruční</h1></html>' > "$P/site/vlastni/index.html"
  python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P" >/dev/null
  [ -f "$P/site/vlastni/index.html" ]; [ ! -e "$P/.aid-ui/skeleton/removed/vlastni" ]   # foreign: stays
  O="$BATS_TEST_TMPDIR/outside"; mkdir -p "$O"; echo puvodni > "$O/index.html"
  rm -r "$P/site/sluzby"; ln -s "$O" "$P/site/sluzby"
  run python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$P"; [ "$status" -eq 2 ]; [[ "$output" == *"is a symlink"* ]]
  [ "$(cat "$O/index.html")" = puvodni ]
  run "$SERVE" skeleton "$P"; [ "$status" -eq 2 ]
  rm "$P/site/sluzby"; Q="$BATS_TEST_TMPDIR/sk2"; skel_project "$Q"
  python3 - "$Q" <<'PY'
import json, sys; p = sys.argv[1] + "/.aid-ui/structure.json"; s = json.load(open(p)); s["pages"].append(dict(s["pages"][1], id="dup", url="/sluzby/")); json.dump(s, open(p, "w"))
PY
  run python3 "$(dirname "$SERVE")/lib/aid-ui-skeleton.py" build "$Q"; [ "$status" -eq 2 ]; [[ "$output" == *"both become sluzby/index.html"* ]]; [ ! -e "$Q/site" ]
}

# ---------------------------------------------------------------- P116: the app skeleton from the model of screens
app_skel() {   # app_skel <dir>: a webapp project with the fixture model (not approved)
  local p="$1"; mkdir -p "$p/.aid-ui" "$p/docs/design"
  cp "$BATS_TEST_DIRNAME/../fixtures/aid-ui/app/docs/design/screens.json" "$p/docs/design/"
  echo '{"type": "webapp", "brand": "none", "local": false}' > "$p/.aid-ui/variant.json"
}
# states_seen <url> - the data-aid-state blocks a browser shows at <url> (JS on), comma-joined
states_seen() {
  local js="$BATS_TEST_TMPDIR/states.mjs"
  cat > "$js" <<J
import { createRequire } from 'module';
const { chromium } = createRequire('$(cd "$BATS_TEST_DIRNAME/../../../lib/ui-fidelity" && pwd)/x.mjs')('@playwright/test');
const b = await chromium.launch(); const pg = await b.newPage(); await pg.goto(process.argv[2]);
console.log((await pg.\$\$eval('[data-aid-state]', es => es.filter(e => !e.hidden && e.offsetParent !== null).map(e => e.dataset.aidState))).join(','));
await b.close();
J
  node "$js" "$1"
}

@test "app-skeleton: every screen at the fixed address with the navigation and its actions leading to their target screens" {
  P="$BATS_TEST_TMPDIR/app"; app_skel "$P"
  run "$SERVE" skeleton "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"URL: http://127.0.0.1:39918/"* ]]
  for s in seznam formular detail; do
    curl -sf --max-time 3 "http://127.0.0.1:39918/$s/" > "$BATS_TEST_TMPDIR/$s.html"
    grep -q "data-aid-screen=\"$s\"" "$BATS_TEST_TMPDIR/$s.html"
    grep -q '<nav aria-label="Aplikace"><ul><li><a href="/seznam/"' "$BATS_TEST_TMPDIR/$s.html"   # nav: only nav screens
    ! grep -q 'aria-label="Aplikace"><ul>.*href="/detail/"' "$BATS_TEST_TMPDIR/$s.html"
  done
  grep -q 'href="/formular/" data-aid-action="seznam.novy"' "$BATS_TEST_TMPDIR/seznam.html"
  grep -q 'href="/detail/" data-aid-action="seznam.otevrit"' "$BATS_TEST_TMPDIR/seznam.html"
  grep -q 'formaction="/detail/" data-aid-action="formular.ulozit"' "$BATS_TEST_TMPDIR/formular.html"
  grep -q '<input name="nazev">' "$BATS_TEST_TMPDIR/formular.html"
  grep -q 'data-aid-result="zalozit">Nákup na sobotu' "$BATS_TEST_TMPDIR/detail.html"   # where the task ends, its result
  [ "$(curl -sf --max-time 3 http://127.0.0.1:39918/ | grep -c 'data-aid-screen="seznam"')" -eq 1 ]   # home = first nav screen
  "$SERVE" stop skeleton
}

@test "app-skeleton: each screen shows its four states - one at a time by ?stav=, all of them without JavaScript" {
  P="$BATS_TEST_TMPDIR/app"; app_skel "$P"
  "$SERVE" skeleton "$P" >/dev/null
  for s in seznam formular detail; do
    [ "$(grep -o 'data-aid-state="[a-z]*"' "$P/site/$s/index.html" | tr '\n' ' ')" = 'data-aid-state="empty" data-aid-state="loading" data-aid-state="error" data-aid-state="filled" ' ]   # the model's order
    ! grep -qE 'data-aid-state="[a-z]+"[^>]*hidden' "$P/site/$s/index.html"   # hidden only by the script: without JS all show
  done
  [ "$(states_seen http://127.0.0.1:39918/seznam/)" = filled ]
  [ "$(states_seen 'http://127.0.0.1:39918/seznam/?stav=empty')" = empty ]
  [ "$(states_seen 'http://127.0.0.1:39918/detail/?stav=error')" = error ]
  [ "$(states_seen 'http://127.0.0.1:39918/detail/?stav=nesmysl')" = filled ]
  "$SERVE" stop skeleton
}

@test "app-skeleton: a destructive action stands behind its confirm question; the draft banner goes once the PM approved this model" {
  P="$BATS_TEST_TMPDIR/app"; app_skel "$P"
  "$SERVE" skeleton "$P" >/dev/null
  grep -q '<button type="button" data-aid-action="detail.smazat" aria-haspopup="dialog">Smazat</button><dialog open class="potvrzeni" data-aid-confirm="detail.smazat"' "$P/site/detail/index.html"
  grep -q '<a href="/seznam/" data-aid-confirm-yes="detail.smazat">Potvrdit</a>' "$P/site/detail/index.html"
  ! grep -q 'data-aid-action="detail.smazat" href' "$P/site/detail/index.html"   # never a plain link
  # in a browser: the action opens the dialog (closed before), Potvrdit leads to the target screen
  cat > "$BATS_TEST_TMPDIR/del.mjs" <<J
import { createRequire } from 'module';
const { chromium } = createRequire('$(cd "$BATS_TEST_DIRNAME/../../../lib/ui-fidelity" && pwd)/x.mjs')('@playwright/test');
const b = await chromium.launch(); const pg = await b.newPage(); await pg.goto('http://127.0.0.1:39918/detail/');
const before = await pg.locator('[data-aid-confirm-yes="detail.smazat"]').isVisible();
await pg.click('[data-aid-action="detail.smazat"]'); await pg.click('[data-aid-confirm-yes="detail.smazat"]'); await pg.waitForLoadState();
console.log(before + ' ' + await pg.getAttribute('main', 'data-aid-screen')); await b.close();
J
  [ "$(node "$BATS_TEST_TMPDIR/del.mjs")" = "false seznam" ]
  for s in seznam formular detail; do grep -q 'data-aid-draft' "$P/site/$s/index.html"; done
  # approved: the state names this model's sha -> no banner; a changed model -> the banner again
  sha="$(sha256sum "$P/docs/design/screens.json" | cut -d' ' -f1)"
  echo "{\"variant\": {\"type\": \"webapp\"}, \"app\": {\"approved_model_sha\": \"$sha\"}}" > "$P/docs/design/brand-state.json"
  "$SERVE" skeleton "$P" >/dev/null
  ! grep -q 'data-aid-draft' "$P/site/detail/index.html"
  jq '.tasks[0].title = "Jinak"' "$P/docs/design/screens.json" > "$P/m.json" && mv "$P/m.json" "$P/docs/design/screens.json"
  "$SERVE" skeleton "$P" >/dev/null
  grep -q 'data-aid-draft' "$P/site/detail/index.html"
  "$SERVE" stop skeleton
}

@test "app-skeleton: a screen removed from the model leaves the fixed address; a page the build replaced is kept" {
  P="$BATS_TEST_TMPDIR/app"; app_skel "$P"
  "$SERVE" skeleton "$P" >/dev/null
  echo '<html><main data-aid-screen="seznam">postaveno</main></html>' > "$P/site/seznam/index.html"
  jq '(.screens[0].actions) |= map(select(.id != "otevrit")) | del(.screens[2]) | .tasks = [.tasks[0] | .done_when = {screen: "formular", expect: "x"} | .steps[1].action = "zpet" | .steps |= .[:1] | .done_when.screen = "formular" | .failure_paths = [] | .states.failure = "nenastává, protože bez odeslání"]
      | (.screens[1].actions) |= map(select(.to != "detail"))' "$P/docs/design/screens.json" > "$P/m.json" && mv "$P/m.json" "$P/docs/design/screens.json"
  run python3 "$BATS_TEST_DIRNAME/../../aid-ui-screens.py" check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run "$SERVE" skeleton "$P"
  [ "$status" -eq 0 ]; [[ "$output" == *"built pages kept without the draft banner"*"seznam/index.html"* ]]   # the model is not approved
  [ ! -e "$P/site/detail/index.html" ]; [ -f "$P/.aid-ui/skeleton/removed/detail/index.html" ]
  grep -q postaveno "$P/site/seznam/index.html"
  "$SERVE" stop skeleton
}
