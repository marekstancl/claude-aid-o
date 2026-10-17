#!/usr/bin/env bats
# aid-tier: t2
# aid-ui-state.sh — P103 Step 4: every PM decision is a studio answer taken through
# record-answer (real server.py on a free port) and used once, for its own kind and
# target; finish needs a gate of the current build over the full matrix, per-page
# approvals and a live exception for every fail|not_covered row.
# P102 Step 1 (kept): state in docs/design/brand-state.json, chapter bodies, fonts,
# migration from docs/brand/state.json.

load aid-ui-places
setup_file() { places_template; }

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-state.sh"
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/coverage"
  T="$BATS_TEST_TMPDIR"
  PROJ="$T/proj"
  mkdir -p "$PROJ/docs/brand"
  cp "$PAGE/index.html" "$PROJ/docs/brand/"
  "$SCRIPT" init "$PROJ" >/dev/null
  places_copy "$PROJ"   # P113: the place verdicts a build and the place questions stand on
  "$SCRIPT" method "$PROJ" build >/dev/null   # P108: build-record wants the build method receipt
  STATE="$PROJ/docs/design/brand-state.json"
  HTML="$PROJ/docs/brand/index.html"
  # coverage on fixtures: a docs root with the two fixture standards, map and checks
  SPECS="$T/docs/ecosystem/specs"
  mkdir -p "$SPECS" "$PROJ/.aid-o/config" "$T/cov"
  cp "$FX/a.md" "$FX/b.md" "$SPECS/"
  touch "$SPECS/standards-map.md"
  printf 'standards:\n  map_path: %s\n' "$SPECS/standards-map.md" > "$PROJ/.aid-o/config/project.yaml"
  cp "$FX/map.yaml" "$FX/checks.yaml" "$T/cov/"
  export AID_UI_COVERAGE_MAP="$T/cov/map.yaml" AID_UI_COVERAGE_SOURCES="$FX/sources.yaml"
  # P113: gate-record makes the customer page itself; the fixture has no web to describe, so a python3 shim on this
  # test's PATH answers for aid-ui-customer-page.py (AID_UI_TEST_CP_RC=1: the gate is not green, nothing made)
  mkdir -p "$BATS_TEST_TMPDIR/cpbin"
  cat > "$BATS_TEST_TMPDIR/cpbin/customer-page.py" <<'PY'
import os, sys
a = sys.argv[1:]
out = a[a.index("--out") + 1] if "--out" in a else os.path.join(a[0], "docs/zakaznik")
if os.environ.get("AID_UI_TEST_CP_RC") == "1": sys.exit("ERROR: the gate is not green")
if "--check" in a: sys.exit(0 if os.path.isfile(os.path.join(out, "index.html")) else 3)
os.makedirs(out, exist_ok=True); open(os.path.join(out, "index.html"), "w").write(os.environ.get("AID_UI_TEST_CP_TEXT", "<p>zakaznik</p>") + "\n")
PY
  real="$(command -v python3)"
  printf '#!/usr/bin/env bash\ncase "$1" in */aid-ui-customer-page.py) shift; exec "%s" "%s" "$@";; esac\nexec "%s" "$@"\n' \
    "$real" "$BATS_TEST_TMPDIR/cpbin/customer-page.py" "$real" > "$BATS_TEST_TMPDIR/cpbin/python3"
  chmod +x "$BATS_TEST_TMPDIR/cpbin/python3"; export PATH="$BATS_TEST_TMPDIR/cpbin:$PATH"
  # a two-page site
  SITE="$T/site"
  mkdir -p "$SITE"
  echo '<html><link href="style.css" rel="stylesheet"><a href="kontakt.html">k</a></html>' > "$SITE/index.html"
  echo '<html><img src="/logo.webp"></html>' > "$SITE/kontakt.html"
  echo 'body{}' > "$SITE/style.css"; echo 'L' > "$SITE/logo.webp"
  echo 'User-agent: *' > "$SITE/robots.txt"; echo '<html>404</html>' > "$SITE/404.html"
  RES="$PROJ/.aid-ui/verify/result.json"
}

teardown() {
  [[ -z "${LINK_PID:-}" ]] || kill "$LINK_PID" 2>/dev/null || true
  [[ -z "${CUST_PID:-}" ]] || kill "$CUST_PID" 2>/dev/null || true
  [[ -z "${SPID:-}" ]] || kill "$SPID" 2>/dev/null || true
  [[ -z "${STUDIO_PID:-}" ]] || kill "$STUDIO_PID" 2>/dev/null || true
}

jqw() { jq "$@" "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"; }

# studio — the real studio server for this test (started once), with an empty payload
studio() {
  [[ -z "${STUDIO_PID:-}" ]] || return 0
  STOKEN=0123456789abcdef0123456789abcdef
  mkdir -p "$PROJ/.aid-ui/studio"; echo "$STOKEN" > "$PROJ/.aid-ui/studio.token"
  echo '{"questions": [], "cards": []}' > "$PROJ/.aid-ui/studio/payload.json"
  # the method receipts the studio wants before a question of these kinds opens (ans opens them now)
  local k; for k in references structure content_plan vision product_context identity facts; do
    "$SCRIPT" method "$PROJ" "$k" >/dev/null
  done
  # the logo route of this project: one slot, so an identity question carries one card with slot W
  mkdir -p "$PROJ/.aid-ui/logo"; echo '{"situation":"new","slots":[{"id":"W","kind":"wordmark"}]}' > "$PROJ/.aid-ui/logo/route.json"
  local port; port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  export AID_UI_STUDIO_URL="http://127.0.0.1:$port"
  python3 "$BATS_TEST_DIRNAME/../../../lib/aid-ui-studio/server.py" --project "$PROJ" --host 127.0.0.1 --port "$port" \
    --token-file "$PROJ/.aid-ui/studio.token" >"$T/studio.log" 2>&1 3>&- &
  STUDIO_PID=$!
  local i; for i in $(seq 1 50); do curl -s -o /dev/null "$AID_UI_STUDIO_URL/" && break; sleep 0.1; done
  # the PM's page session (P113: only an answer through it is the PM's; the token is an agent's)
  echo pmcode0123456789abcdef > "$PROJ/.aid-ui/studio.code"
  PCOOKIE="$(curl -s -o /dev/null -D - "$AID_UI_STUDIO_URL/?k=pmcode0123456789abcdef" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\).*/\1/p' | head -1)"
  [[ -n "$PCOOKIE" ]]
}

# ans <id> <kind> <target> [decision] [cards] — the PM answers question <id> on the real
# studio and the agent records it (record-answer); cards = the question's cards shown
# (a JSON array, default [{"id":"x"}]); the PM picks card x
ans() {
  studio
  local p="$PROJ/.aid-ui/studio/payload.json" d="${4:-approve}" c='[{"id":"x"}]'
  # a facts question names its part and offers three sourced answers (the studio's rule)
  [[ "$2" != facts ]] || c='[{"id":"x","source":"odhad"},{"id":"y","source":"podklady"},{"id":"z","source":"registr"}]'
  # a handover question carries the links the PM opens (links.json) and the three verdict cards (P108)
  local hb='[]'; [[ "$2" != handover ]] || { c='[{"id":"x","value":"prevzit"},{"id":"y","value":"vyhrada"},{"id":"z","value":"vratit"}]'
    [[ ! -f "$PROJ/.aid-ui/links.json" ]] || hb="$(jq -c '[("Web: " + .web), ("Co jste dostali: " + .customer)]' "$PROJ/.aid-ui/links.json")"; }
  [[ -z "${5:-}" ]] || c="$5"
  # the method before the output: the question opens now, after the receipts studio() wrote; every card says its method
  jq --arg q "$1" --arg k "$2" --arg t "$3" --argjson c "$c" --argjson hb "$hb" --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
    '.questions += [{id: $q, kind: $k, target: $t, opened_at: $o} + (if $k == "facts" then {part: "obsah"} elif $k == "handover" then {body: $hb} else {} end)]
    | .cards += [$c[] | .question = $q | .method = (.method // "SKILL.md, 4-references.md") | (if $k == "identity" then .slot = "W" else . end)]' "$p" > "$p.t" && mv "$p.t" "$p"
  curl -sf -o /dev/null -H "Cookie: $PCOOKIE" -H "Referer: $AID_UI_STUDIO_URL/" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg q "$1" --arg k "$2" --arg t "$3" --arg d "$d" \
          '{question: $q, kind: $k, target: $t, decision: $d, choice: "x", comment: "PM"}')" "$AID_UI_STUDIO_URL/answer"
  # P113: an accepting answer of a place's question needs the place's verdict (the gates' own cases are below)
  if [[ "$d" == approve || "$d" == choose ]] && [[ -z "${NO_PLACE_OK:-}" ]]; then
    case "$2" in handover) place_ok "$PROJ" web ;; identity|vision) place_ok "$PROJ" sdeleni ;; esac
  fi
  "$SCRIPT" record-answer "$PROJ" --question "$1" >/dev/null
}

# forge <id> <kind> <target> — an answer written straight into the state and
# .aid-ui/answers/, never given on the studio
forge() {
  mkdir -p "$PROJ/.aid-ui/answers"
  printf '{"question":"%s","kind":"%s","decision":"%s","comment":"PM"}\n' "$1" "$2" "${4:-approve}" > "$PROJ/.aid-ui/answers/$1.json"
  jqw --arg q "$1" --arg k "$2" --arg t "$3" --arg d "${4:-approve}" \
    --arg sha "$(sha256sum "$PROJ/.aid-ui/answers/$1.json" | cut -d' ' -f1)" \
    '.answers[$q] = {kind: $k, target: $t, decision: $d, choice: null, comment: "PM", answer_file: ".aid-ui/answers/\($q).json",
                     answer_sha256: $sha, opened_at: "2020-01-01T00:00:00Z", at: "2020-01-02T00:00:00Z"}'
}
# cards_of <refs json> — the studio cards the refs step shows for these refs
cards_of() { jq -c '[.[] | {id, url, thesis: .why}]' <<<"$1"; }
sha_of() { printf 'sha256:%s' "$(jq -S -c -j . <<<"$1" | sha256sum | cut -d' ' -f1)"; }
fp() { jq -r --arg p "$1" '.build.fingerprints[$p]' "$STATE"; }
approve() { ans "ap-$1-$2" approve_page "$1@$(fp "$1")"; "$SCRIPT" approve-page "$PROJ" "$1" --answer "ap-$1-$2" >/dev/null; }
# approve_chapter <id> <kind> <question id> — the PM approves the chapter's current body on the studio
approve_chapter() { ans "$3" "$2" "$("$SCRIPT" chapter-target "$PROJ" "$1")"; "$SCRIPT" chapter "$PROJ" "$1" schvaleno --by PM --answer "$3"; }

# result [jq filter] — a gate result of the recorded build: every check x page x
# viewport x browser (+ flow x state x role for apps) passing, then the filter
result() {
  mkdir -p "${RES%/*}"
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --slurpfile ck <(yq -o=json . "$T/cov/checks.yaml") '.build as $b | ($ck[0]) as $c
    | ([.build.fingerprints | keys[] | select(. != "_site") | {page: ., role: "", state: ""}]
       + (if (.variant.type // "web") != "web" then [.structure.flows[] as $f | $f.states[] as $s
          | (.structure.roles // [""])[] as $r
          | {page: $f.id, role: ($r | if type == "object" then .id else . end), state: ($s | if type == "object" then .id else . end)}] else [] end)) as $combos
    | {run_at: $now, build_id: $b.id, fingerprints: $b.fingerprints,
       rows: ([$c.checks | keys[] as $k | select((($c.applies // {})[$k].scope // "") != "project")
               | $combos[] as $m | $c.viewports[] as $v | $c.browsers[] as $br
               | $m + {check: $k, viewport: $v, browser: $br, status: "pass"}]
              # a project-scope check (customer_page): one row - the home page, the last viewport, the first browser
              + [$c.checks | keys[] as $k | select((($c.applies // {})[$k].scope // "") == "project")
                 | ($combos | map(select(.page == "index.html")) | first // $combos[0]) + {check: $k, viewport: ($c.viewports | last), browser: $c.browsers[0], status: "pass"}])}' "$STATE" | jq "${1:-.}" > "$RES"
}

# ready — every finish condition met for a web variant with two pages
ready() {
  ans v1 variant "$(sha_of '{"type":"web","brand":"new","local":false}')" choose
  "$SCRIPT" set "$PROJ" variant '{"type":"web","brand":"new","local":false}' --answer v1 >/dev/null
  cp='[{"id":"hero","page":"index.html","status":"confirmed_client"}]'
  ans c1 content_plan "$(sha_of "$cp")"
  "$SCRIPT" set "$PROJ" content-plan "$cp" --answer c1 >/dev/null
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  approve index.html 1; approve kontakt.html 1
  result
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  end_order   # P108: the customer page the gate checked and a coverage report after the gate
  serve_200; "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
}
# gate_ready — a recorded gate with the end-order artifacts and the links (what chapter-all wants, P108)
gate_ready() {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  result; "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  end_order
  serve_200; "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
}
# end_order — the artifacts chapter-all wants in order: the customer page older than the gate result, the
# coverage report not older than it (the fixture result passes every row, customer_page included)
end_order() {
  mkdir -p "$PROJ/docs/zakaznik"; [[ -f "$PROJ/docs/zakaznik/index.html" ]] || echo '<p>zakaznik</p>' > "$PROJ/docs/zakaznik/index.html"
  jqw --arg s "$(sha256sum "$PROJ/docs/zakaznik/index.html" | cut -d' ' -f1)" '.gate.customer_page_sha256 = $s'
  jq -n --arg g "$(jq -r .gate.run_at "$STATE")" '{counts: {}, gate_run_at: $g}' > "$PROJ/docs/design/soulad-summary.json"
}
# serve_200 — the recorded build and the project's docs served locally (links binds the web link to the
# build's index.html and the customer link to docs/zakaznik/index.html); LINK_URL = web, CUST_URL = customer
serve_200() {
  [[ -z "${LINK_PID:-}" ]] || { kill "$LINK_PID" 2>/dev/null || true; wait "$LINK_PID" 2>/dev/null || true; }
  [[ -z "${CUST_PID:-}" ]] || { kill "$CUST_PID" 2>/dev/null || true; wait "$CUST_PID" 2>/dev/null || true; }
  local port; port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$SITE" >/dev/null 2>&1 &
  LINK_PID=$!; LINK_URL="http://127.0.0.1:$port/"
  local p2; p2="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  mkdir -p "$PROJ/docs/zakaznik"; [[ -f "$PROJ/docs/zakaznik/index.html" ]] || echo '<p>zakaznik</p>' > "$PROJ/docs/zakaznik/index.html"
  python3 -m http.server "$p2" --bind 127.0.0.1 --directory "$PROJ/docs" >/dev/null 2>&1 &
  CUST_PID=$!; CUST_URL="http://127.0.0.1:$p2/zakaznik/index.html"
  local i; for i in $(seq 1 30); do curl -sf -o /dev/null "$LINK_URL" && curl -sf -o /dev/null "$CUST_URL" && return 0; sleep 0.1; done; return 1
}

@test "set product_type writes without an answer; set direction exit 2" {
  run "$SCRIPT" set "$PROJ" product_type '"eshop"'
  [ "$status" -eq 0 ]
  [ "$(jq -r .product_type "$STATE")" = eshop ]
  run "$SCRIPT" set "$PROJ" direction '{}'
  [ "$status" -eq 2 ]
}

@test "set refs needs a references answer choosing a shown card; picked comes from the choice" {
  refs='[{"id":"x","url":"https://x.example","why":"písmo"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  run "$SCRIPT" set "$PROJ" refs "$refs"
  [ "$status" -eq 1 ]; [[ "$output" == *'needs --answer'* ]]
  ans r0 variant "$(sha_of "$refs")" choose                     # another kind, same target
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer r0
  [ "$status" -eq 1 ]; [[ "$output" == *'not references'* ]]
  ans r1 references "$(sha_of '[{"id":"x","url":"https://x.example","why":"písmo"}]')" choose   # other JSON
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer r1
  [ "$status" -eq 1 ]; [[ "$output" == *'is for'* ]]
  ans r2 references "$(sha_of "$refs")" approve "$(cards_of "$refs")"   # approve: no card chosen
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer r2
  [ "$status" -eq 1 ]; [[ "$output" == *'not one or more of the shown cards'* ]]
  [ "$(jq -c .refs "$STATE")" = '[]' ]
  ans r3 references "$(sha_of "$refs")" choose "$(cards_of "$refs")"   # the PM chose card x
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer r3
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.refs[] | [.id, .picked]]' "$STATE")" = '[["x",true],["y",false]]' ]
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer r3             # used once
  [ "$status" -eq 1 ]; [[ "$output" == *'already used'* ]]
}

@test "roles writes var() aliases; unknown color exit 1" {
  "$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh" "$BATS_TEST_DIRNAME/../fixtures/aid-ui/DESIGN.md" "$PROJ/docs/brand/tokens.css"
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=print,accent=print,display=display,body=display
  [ "$status" -eq 0 ]
  grep -qF -- '--brand-bg: var(--color-paper);' "$PROJ/docs/brand/roles.css"
  grep -qF -- '--brand-body-family: var(--font-display-family);' "$PROJ/docs/brand/roles.css"
  [ "$(jq -r .roles.accent "$STATE")" = print ]
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=ghost,accent=print,display=display,body=display
  [ "$status" -eq 1 ]
  [[ "$output" == *ghost* ]]
}

@test "roles aliases only the font suffixes tokens.css defines" {
  "$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh" "$BATS_TEST_DIRNAME/../fixtures/aid-ui/DESIGN.md" "$PROJ/docs/brand/tokens.css"
  printf ':root {\n  --font-text-family: Inter, sans-serif;\n  --font-text-size: 1rem;\n}\n' >> "$PROJ/docs/brand/tokens.css"
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=print,accent=print,display=display,body=text
  [ "$status" -eq 0 ]
  grep -qF -- '--brand-body-family: var(--font-text-family);' "$PROJ/docs/brand/roles.css"
  grep -qF -- '--brand-body-size: var(--font-text-size);' "$PROJ/docs/brand/roles.css"
  ! grep -q -- '--brand-body-letter-spacing' "$PROJ/docs/brand/roles.css" || false
  grep -qF -- '--brand-display-letter-spacing: var(--font-display-letter-spacing);' "$PROJ/docs/brand/roles.css"
}

@test "chapter writes state.json and index.html together" {
  run approve_chapter barvy design_standard q1
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.answer "$STATE")" = q1 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = schvaleno ]
  [ "$(jq -r .chapters.barvy.by "$STATE")" = PM ]
  grep -q '<section id="barvy" data-status="schvaleno">.*<p class="status"><!-- status:barvy -->[0-9-]* · PM<!-- /status:barvy --></p>' "$PROJ/docs/brand/index.html"
  grep -q '<section id="logo" data-status="ceka">' "$PROJ/docs/brand/index.html"
}

@test "brand page: the client's favicon from the brand package is copied next to the page and linked on the next rewrite" {
  approve_chapter barvy design_standard q1
  ! grep -q 'rel="icon"' "$HTML"; [ ! -e "$PROJ/docs/brand/favicon.svg" ]
  mkdir -p "$PROJ/docs/design/brand-package/icons"; echo '<svg id="client"/>' > "$PROJ/docs/design/brand-package/icons/favicon.svg"
  approve_chapter typografie design_standard q2
  [ "$(cat "$PROJ/docs/brand/favicon.svg")" = '<svg id="client"/>' ]
  [ "$(grep -c '<link rel="icon" href="favicon.svg" type="image/svg+xml">' "$HTML")" -eq 1 ]
  approve_chapter komponenty design_standard q3   # rewritten again: still one link
  [ "$(grep -c 'rel="icon"' "$HTML")" -eq 1 ]
}

@test "H5: payload-check refuses cards nested inside a question (they belong in the top-level cards[])" {
  studio
  pl="$PROJ/.aid-ui/studio/payload.json"; mkdir -p "$PROJ/.aid-ui/studio"
  o="$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)"
  jq -n --arg o "$o" '{now:{title:"x",text:"y",at:$o,part:"technicka"},questions:[{id:"q-e",kind:"exception",part:"technicka",target:"{\"check\":\"axe\",\"page\":\"*\"}",opened_at:$o,title:"Výjimka?",body:["b"],next:"n",outcome:"Výjimka zapsána.",cards:[{id:"a",title:"A"}]}],cards:[]}' > "$pl"
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"carries its own \"cards\""* ]]
  jq 'del(.questions[0].cards)' "$pl" > "$pl.t" && mv "$pl.t" "$pl"
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "payload-check: the rebuilt-logo question (target logo:rebuilt:<slot>, 1i mode full) carries exactly one card of that slot; other identity questions still one card per slot" {
  studio
  echo '{"situation":"redesign","slots":[{"id":"W","kind":"wordmark"},{"id":"WC","kind":"name+sign"}]}' > "$PROJ/.aid-ui/logo/route.json"
  pl="$PROJ/.aid-ui/studio/payload.json"; mkdir -p "$PROJ/.aid-ui/studio"
  mk() { jq -n --arg t "$1" --argjson cards "$2" --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
    '{now:{title:"x",text:"y",at:$o,part:"logo"},questions:[{id:"q-l2",kind:"identity",part:"logo",target:$t,opened_at:$o,title:"Logo?",body:["b"],next:"n",outcome:"Logo schváleno."}],
      cards:($cards|map(.question="q-l2"|.method="process.md fáze 7 (kit)"|.thesis="t"|.risk="r"|.uniqueness="u"|.source="podklady"|.preview=null))}' > "$pl"; }
  mk "logo:rebuilt:WC" '[{"id":"WC","slot":"WC","title":"WC"}]'
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  mk "logo:rebuilt:WC" '[{"id":"W","slot":"W","title":"W"}]'
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"exactly one card of that slot (WC)"* ]]
  mk "logo:rebuilt:WC" '[{"id":"W","slot":"W","title":"W"},{"id":"WC","slot":"WC","title":"WC"}]'
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 1 ]
  mk "logo:route:redesign" '[{"id":"WC","slot":"WC","title":"WC"}]'
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"one card per slot"* ]]
}

@test "reset-approvals turns schvaleno into navrh" {
  approve_chapter barvy design_standard q1
  run "$SCRIPT" reset-approvals "$PROJ" barvy typografie
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = navrh ]
  [ "$(jq -r .chapters.typografie.status "$STATE")" = ceka ]
  grep -q '<section id="barvy" data-status="navrh">' "$PROJ/docs/brand/index.html"
}

@test "chapter-all: one handover answer approves every chapter in navrh or schvaleno, once" {
  gate_ready
  "$SCRIPT" chapter "$PROJ" barvy navrh
  "$SCRIPT" chapter "$PROJ" vize navrh
  approve_chapter logo identity q0
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  for id in vize logo barvy; do
    [ "$(jq -r --arg i "$id" '.chapters[$i].status' "$STATE")" = schvaleno ]
    [ "$(jq -r --arg i "$id" '.chapters[$i].answer' "$STATE")" = h1 ]
  done
  [ "$(jq -r .chapters.typografie.status "$STATE")" = ceka ]
  grep -q '<section id="barvy" data-status="schvaleno">' "$HTML"
  [ "$(jq '[.consumed[] | select(. == "h1")] | length' "$STATE")" = 1 ]
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"already used"* ]]
}

@test "chapter-all: a chapter changed after the question was asked refuses the answer" {
  gate_ready
  echo '<p>a</p>' > "$BATS_TEST_TMPDIR/a.html"
  echo '<p>b</p>' > "$BATS_TEST_TMPDIR/b.html"
  "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/a.html"
  "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
  "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/b.html"
  run "$SCRIPT" chapter-all "$PROJ" --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"answer h1 is for"* ]]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = navrh ]
}

@test "chapter-all: needs a handover answer; nothing ready is an error" {
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to hand over"* ]]
  "$SCRIPT" chapter "$PROJ" barvy navrh
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"no gate recorded"* ]]   # P108: the handover comes after the final gate
  gate_ready
  ans d1 design_standard "$("$SCRIPT" chapter-all-target "$PROJ")"
  run "$SCRIPT" chapter-all "$PROJ" --answer d1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not handover"* ]]
  run "$SCRIPT" chapter-all "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --answer"* ]]
}

@test "chapter-all: a chapter that cannot be written leaves every chapter and the answer untouched" {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
  sed -i 's/<!-- status:barvy -->/<!-- statux:barvy -->/' "$HTML"
  before="$(sha256sum "$HTML" "$STATE")"
  run "$SCRIPT" chapter-all "$PROJ" --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing changed"* ]]
  [ "$(sha256sum "$HTML" "$STATE")" = "$before" ]
  [ "$(jq -r .chapters.vize.status "$STATE")" = navrh ]
  [ "$(jq '[.consumed[]? | select(. == "h1")] | length' "$STATE")" = 0 ]
}

@test "every question kind the studio server accepts has a Czech label on the studio page" {
  kinds="$(python3 -c "import ast,re,sys; s=open(sys.argv[1]).read(); print(' '.join(sorted(ast.literal_eval(re.search(r'KINDS = (\{[^}]*\})', s).group(1)))))" "$BATS_TEST_DIRNAME/../../../lib/aid-ui-studio/server.py")"
  for k in $kinds; do grep -q "[ {]$k: \"" "$BATS_TEST_DIRNAME/../../../lib/aid-ui-studio/studio.html" || { echo "no label: $k"; false; }; done
}

@test "unknown chapter id: exit 2" {
  run "$SCRIPT" chapter "$PROJ" nope navrh
  [ "$status" -eq 2 ]
  run "$SCRIPT" reset-approvals "$PROJ" nope
  [ "$status" -eq 2 ]
}

# --- P102 Step 1 -----------------------------------------------------------

@test "body replaces only its section and is idempotent" {
  echo '<p>Vize projektu</p>' > "$BATS_TEST_TMPDIR/b.html"
  before_logo="$(grep -o '<section id="logo".*</section>' "$HTML")"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/b.html"
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><p>Vize projektu</p>' "$HTML"
  [ "$(grep -o '<section id="logo".*</section>' "$HTML")" = "$before_logo" ]
  cp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/b.html"
  cmp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  [ -z "$(ls -A "$PROJ/docs/brand" | grep -v '^index.html$')" ]
}

@test "body refuses script, onclick, section and a marker; unknown id exit 2" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<script>x()</script>' '<a href="#" onclick="x()">a</a>' '<section id="x"></section>' '<!-- status:logo -->'; do
    printf '%s\n' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*vize* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  run "$SCRIPT" body "$PROJ" nope --file "$BATS_TEST_TMPDIR/bad.html"
  [ "$status" -eq 2 ]
}

@test "body refuses an entity-encoded, split or vbscript/data URL scheme" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<a href="jav&#x61;script:alert(1)">a</a>' '<a href="&#106;avascript:alert(1)">a</a>' \
             $'<a href="java\tscript:alert(1)">a</a>' '<a href="javascript&colon;alert(1)">a</a>' \
             '<a href="vbscript:x">a</a>' '<a href="&#100;ata:text/html,x">a</a>'; do
    printf '%s\n' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*vize*refused* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
}

@test "body is an allowlist: glued handler, style, svg and an unfinished tag refused" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<img src="x"onerror="alert(1)">' '<p style="x">' '<svg onload=1>' \
             '<img alt=">" onerror=1 ' '<p class="a status">' '<!DOCTYPE html>' \
             '<span style="background:url(x)"></span>' '<p style="color:red">x</p>' \
             '<p style="background: var(--x) ; behavior: y">x</p>'; do
    printf '%s\n' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*"body of section vize refused"* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
}

@test "body refuses a marker smuggled in an attribute; the next write leaves no handler" {
  printf '%s\n' '<p title="<!-- /body:vize --><img src=x onerror=alert(1)>">x</p>' > "$BATS_TEST_TMPDIR/bad.html"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
  [ "$status" -eq 1 ]
  [[ "$output" == ERROR:*"body of section vize refused"* ]]
  echo '<p>ok</p>' > "$BATS_TEST_TMPDIR/ok.html"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/ok.html"
  [ "$status" -eq 0 ]
  ! grep -q onerror "$HTML" || false
  # defence in depth: a page that already carries a duplicate end marker is not written
  sed -i 's|<!-- /body:vize -->|&<!-- /body:vize -->|' "$HTML"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/ok.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than once"* ]]
}

@test "body refuses an end tag with attributes (parser/browser differential)" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<p>x</p a="> <p title="> <img src=x onerror=alert(1)> ">' \
             "<p>x</p a='> <p title='> <img src=x onerror=alert(1)> '>" \
             '<b>x</b title="><i title="><img src=x onerror=alert(1)>">'; do
    printf '%s' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*"body of section vize refused"*"end tag"* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
}

@test "body writes a re-serialization, not the raw input" {
  printf '%s\n' '<P CLASS=lead>a &lt;script&gt; &amp; b < c<br/><a href="https://example.com?a=1&amp;b=2">x</a></P >' > "$BATS_TEST_TMPDIR/ok.html"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/ok.html"
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><p class="lead">a &lt;script&gt; &amp; b &lt; c<br><a href="https://example.com?a=1&amp;b=2">x</a></p>' "$HTML"
}

@test "body is written balanced; a stray end tag is refused" {
  w() { printf '%s' "$1" > "$BATS_TEST_TMPDIR/b.html"; run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/b.html"; }
  w '<div><table><tr><td>x'
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><div><table><tr><td>x</td></tr></table></div><!-- /body:vize -->' "$HTML"
  w '<p/>x'
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><p></p>x<!-- /body:vize -->' "$HTML"
  w '<p>a &#xZZ; <b>b</b></p>'
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><p>a &amp;#xZZ; <b>b</b></p><!-- /body:vize -->' "$HTML"
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  w '</div></div>'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unbalanced end tag </div>"* ]]
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
}

@test "body refuses li/dt/dd outside their list; accepts proper lists" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<ul><li><div><li>x' '<ul><li><div><li>x</li></div></li></ul>' \
             '<dl><dt><div><dt>x</dt></div></dt></dl>' '<dl><dd><div><dd>x' '<li>a<li>b'; do
    printf '%s' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refused"*"outside a"* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for ok in '<ul><li>a</li><li>b</li></ul>' '<dl><dt>a</dt><dd>b</dd></dl>'; do
    printf '%s' "$ok" > "$BATS_TEST_TMPDIR/ok.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/ok.html"
    [ "$status" -eq 0 ]
    grep -qF "<!-- body:vize -->$ok<!-- /body:vize -->" "$HTML"
  done
}

@test "body accepts allowed tags, safe links and a relative image" {
  for ok in '<a href="https://example.com">ok</a>' '<img src="assets/logo.svg" alt="logo">' \
            '<p>Text <strong>tučně</strong> a &lt;script&gt;</p>' \
            '<span class="swatch" style="background: var(--color-primary)"></span>' \
            '<p style="font-family: var(--font-display); font-size: var(--text-xl); font-weight: var(--weight-bold)">Aa</p>'; do
    printf '%s\n' "$ok" > "$BATS_TEST_TMPDIR/ok.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/ok.html"
    [ "$status" -eq 0 ]
    grep -qF "<!-- body:vize -->$ok" "$HTML"
  done
}

@test "a later chapter call leaves a written body byte-identical" {
  printf '<div class="swatch">a</div>\n<p class="note">b</p>\n' > "$BATS_TEST_TMPDIR/b.html"
  "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/b.html"
  body() { sed -n '/<!-- body:barvy -->/,/<!-- \/body:barvy -->/p' "$HTML" | sed -e 's/.*<!-- body:barvy -->//' -e 's/<!-- \/body:barvy -->.*//'; }
  b1="$(body)"
  run approve_chapter barvy design_standard q1
  [ "$status" -eq 0 ]
  [ "$(body)" = "$b1" ]
  grep -q '<section id="barvy" data-status="schvaleno">' "$HTML"
}

@test "body changed after schvaleno clears the approval; an identical body keeps it" {
  echo '<p>a</p>' > "$BATS_TEST_TMPDIR/a.html"
  echo '<p>b</p>' > "$BATS_TEST_TMPDIR/b.html"
  "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/a.html"
  approve_chapter barvy design_standard q1
  run "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/a.html"
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = schvaleno ]
  [[ "$output" != *"approval cleared"* ]]
  run "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/b.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approval cleared"* ]]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = navrh ]
  [ "$(jq -r '.chapters.barvy.by // ""' "$STATE")" = "" ]
  grep -q '<section id="barvy" data-status="navrh">' "$HTML"
}

@test "chapter vize accepted" {
  run "$SCRIPT" chapter "$PROJ" vize navrh
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.vize.status "$STATE")" = navrh ]
  grep -q '<section id="vize" data-status="navrh">' "$HTML"
}

# A P101 project: old state.json, old index.html without vize/seo and markers, a written body.
p101_project() {
  rm -rf "$PROJ"; mkdir -p "$PROJ/docs/brand"
  git -C "$BATS_TEST_DIRNAME" show b095ba7f:plugins/aid-orchestrator/skills/ui-design/brand-page/index.html > "$HTML" 2>/dev/null \
    || sed -e 's/<!-- \/\?\(body\|status\):[a-z]* -->//g' -e '/<!-- \/\?fonts -->/d' -e '/id="vize"\|id="seo"\|#vize\|#seo/d' "$PAGE/index.html" > "$HTML"
  sed -i 's|<section id="barvy" data-status="ceka"><h2>Barvy</h2><p class="status"></p><div class="body"></div>|<section id="barvy" data-status="navrh"><h2>Barvy</h2><p class="status">2026-09-24</p><div class="body"><div class="swatch">x</div></div>|' "$HTML"
  jq '.step = 2 | del(.chapters.vize, .chapters.seo, .options, .finished)' "$PAGE/state.template.json" > "$PROJ/docs/brand/state.json"
}

@test "init migrates an old state.json and index.html, keeps bodies" {
  p101_project
  ! grep -q 'id="vize"' "$HTML" || false
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq .step "$STATE")" = 2 ]
  [ "$(jq -r .chapters.seo.status "$STATE")" = ceka ]
  [ "$(jq -c .options "$STATE")" = '{"vision":false,"identity":false,"seo":false,"images":false}' ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ -f "$PROJ/.aid-ui/state.json.migrated" ]
  [ "$(grep -c '<section ' "$HTML")" -eq 15 ]
  grep -qF '<div class="body"><!-- body:barvy --><div class="swatch">x</div><!-- /body:barvy --></div>' "$HTML"
  grep -qF '<p class="status"><!-- status:barvy -->2026-09-24<!-- /status:barvy --></p>' "$HTML"
  grep -qF '<!-- fonts -->' "$HTML"
  grep -qF '<li><a href="#seo">SEO</a></li>' "$HTML"
  cp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  "$SCRIPT" init "$PROJ"
  cmp "$HTML" "$BATS_TEST_TMPDIR/once.html"
}

@test "retry after an interrupted migration (new file present, markers missing) adds the markers" {
  p101_project
  jq -s '.[0] * .[1]' "$PAGE/state.template.json" "$PROJ/docs/brand/state.json" > "$BATS_TEST_TMPDIR/new.json"
  mkdir -p "$PROJ/docs/design"; mv "$BATS_TEST_TMPDIR/new.json" "$STATE"
  rm "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize -->' "$HTML"
  grep -qF '<!-- status:schvaleni -->' "$HTML"
}

@test "both files present: the new one wins, the old one is renamed" {
  "$SCRIPT" step "$PROJ" 3
  echo '{"step": 1}' > "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq .step "$STATE")" = 3 ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ "$(jq .step "$PROJ/.aid-ui/state.json.migrated")" = 1 ]
}

@test "init with the new file, no index.html and an old state.json moves the old file" {
  rm -rf "$PROJ/.aid-ui" "$HTML"
  echo '{"step": 1}' > "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ "$(jq .step "$PROJ/.aid-ui/state.json.migrated")" = 1 ]
}

@test "fonts refuses foreign hosts and paths outside docs/brand/fonts; writes a Google Fonts link idempotently" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in https://evil.example/ https://fonts.googleapis.com.evil.example/css http://fonts.googleapis.com/css \
             https://fonts.googleapis.com@evil.example/ docs/brand/tokens.css ../x.css; do
    run "$SCRIPT" fonts "$PROJ" "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  url='https://fonts.googleapis.com/css2?family=Gloock&family=Inter:wght@400;700&display=swap'
  run "$SCRIPT" fonts "$PROJ" "$url"
  [ "$status" -eq 0 ]
  "$SCRIPT" fonts "$PROJ" "$url"
  [ "$(grep -c 'rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Gloock&amp;family=Inter' "$HTML")" -eq 1 ]
  mkdir -p "$PROJ/docs/brand/fonts"; echo '@font-face{}' > "$PROJ/docs/brand/fonts/local.css"
  run "$SCRIPT" fonts "$PROJ" docs/brand/fonts/local.css
  [ "$status" -eq 0 ]
  grep -qF '<link rel="stylesheet" href="fonts/local.css">' "$HTML"
  ! grep -q 'googleapis' "$HTML" || false
}


@test "chapter schvaleno needs the chapter kind's answer for the stored body; navrh and ceka need none" {
  echo '<p>a</p>' > "$T/a.html"; echo '<p>b</p>' > "$T/b.html"
  "$SCRIPT" body "$PROJ" vize --file "$T/a.html"
  run "$SCRIPT" chapter "$PROJ" vize schvaleno --by PM
  [ "$status" -eq 1 ]; [[ "$output" == *'needs --answer'* ]]
  tgt="$("$SCRIPT" chapter-target "$PROJ" vize)"
  [[ "$tgt" =~ ^sha256:[0-9a-f]{64}$ ]]
  ans w1 identity "$tgt"                                          # logo's kind, not vize's
  run "$SCRIPT" chapter "$PROJ" vize schvaleno --answer w1
  [ "$status" -eq 1 ]; [[ "$output" == *'not vision'* ]]
  ans w2 vision "$tgt"
  "$SCRIPT" body "$PROJ" vize --file "$T/b.html"                  # body changed after the question
  run "$SCRIPT" chapter "$PROJ" vize schvaleno --answer w2
  [ "$status" -eq 1 ]; [[ "$output" == *'is for'* ]]
  [ "$(jq -r .chapters.vize.status "$STATE")" = ceka ]
  run approve_chapter vize vision w3
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.vize.status "$STATE")" = schvaleno ]
  grep -q '<section id="vize" data-status="schvaleno">' "$HTML"
  run approve_chapter struktura design_standard w4                # struktura is a structure answer
  [ "$status" -eq 1 ]; [[ "$output" == *'not structure'* ]]
  run "$SCRIPT" chapter "$PROJ" struktura navrh
  [ "$status" -eq 0 ]
  run "$SCRIPT" chapter-target "$PROJ" nope
  [ "$status" -eq 2 ]
}

@test "two chapters with identical bodies: an answer for one does not approve the other" {
  echo '<p>stejné</p>' > "$T/s.html"
  "$SCRIPT" body "$PROJ" barvy --file "$T/s.html"
  "$SCRIPT" body "$PROJ" typografie --file "$T/s.html"
  tb="$("$SCRIPT" chapter-target "$PROJ" barvy)"; tt="$("$SCRIPT" chapter-target "$PROJ" typografie)"
  [ "$tb" != "$tt" ]
  ans x1 design_standard "$tb"                                    # the PM approved barvy
  run "$SCRIPT" chapter "$PROJ" typografie schvaleno --answer x1
  [ "$status" -eq 1 ]; [[ "$output" == *'is for'* ]]
  [ "$(jq -r .chapters.typografie.status "$STATE")" = ceka ]
  "$SCRIPT" body "$PROJ" komponenty --file "$T/s.html"
  run "$SCRIPT" chapter "$PROJ" komponenty schvaleno --answer x1  # a third chapter, same body
  [ "$status" -eq 1 ]
  run "$SCRIPT" chapter "$PROJ" barvy schvaleno --answer x1
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = schvaleno ]
  # the target is sha256 of "<id>\n" + the stored body, not of the body alone
  [ "$tb" = "$(python3 -c 'import hashlib,sys; t=open(sys.argv[1]).read(); a="<!-- body:barvy -->"; b=t[t.find(a)+len(a):t.find("<!-- /body:barvy -->")]; print("sha256:"+hashlib.sha256(("barvy\n"+b).encode()).hexdigest())' "$HTML")" ]
}

@test "set refs: duplicate or empty card ids exit 1, nothing written, no answer consumed" {
  dup='[{"id":"x","url":"https://x.example","why":"a"},{"id":"x","url":"https://evil.example","why":"b"}]'
  ans d1 references "$(sha_of "$dup")" choose
  run "$SCRIPT" set "$PROJ" refs "$dup" --answer d1
  [ "$status" -eq 1 ]; [[ "$output" == *'non-empty and unique'* ]]
  [ "$(jq -c .refs "$STATE")" = '[]' ]
  [ "$(jq -c .consumed "$STATE")" = '[]' ]
  dup3='[{"id":"x","url":"https://x.example","why":"a"},{"id":"y","url":"https://y.example","why":"b"},{"id":"x","url":"https://z.example","why":"c"}]'
  ans d2 references "$(sha_of "$dup3")" choose
  run "$SCRIPT" set "$PROJ" refs "$dup3" --answer d2
  [ "$status" -eq 1 ]; [ "$(jq -c .refs "$STATE")" = '[]' ]
  empty='[{"id":"","url":"https://x.example","why":"a"},{"id":"y","url":"https://y.example","why":"b"}]'
  ans d3 references "$(sha_of "$empty")" choose
  run "$SCRIPT" set "$PROJ" refs "$empty" --answer d3
  [ "$status" -eq 1 ]; [ "$(jq -c .refs "$STATE")" = '[]' ]
  [ "$(jq -c .consumed "$STATE")" = '[]' ]
}

@test "set refs: the refs must be exactly the cards the studio showed for the answer's question" {
  refs='[{"id":"x","url":"https://x.example","why":"písmo"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  shown="$(cards_of "$refs")"
  # the reviewer's example: card x shown with one URL, the refs carry another
  evil='[{"id":"x","url":"https://evil.example","why":"písmo"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  ans m1 references "$(sha_of "$evil")" choose "$shown"
  run "$SCRIPT" set "$PROJ" refs "$evil" --answer m1
  [ "$status" -eq 1 ]; [[ "$output" == *'not the cards shown for question m1'* ]]
  # the why differs from the card's thesis
  why='[{"id":"x","url":"https://x.example","why":"jiné"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  ans m2 references "$(sha_of "$why")" choose "$shown"
  run "$SCRIPT" set "$PROJ" refs "$why" --answer m2
  [ "$status" -eq 1 ]
  # a shown card left out of the refs (count differs)
  one='[{"id":"x","url":"https://x.example","why":"písmo"}]'
  ans m3 references "$(sha_of "$one")" choose "$shown"
  run "$SCRIPT" set "$PROJ" refs "$one" --answer m3
  [ "$status" -eq 1 ]
  # an id no card of this question has; cards of another question do not count
  other='[{"id":"x","url":"https://x.example","why":"písmo"},{"id":"z","url":"https://y.example","why":"barvy"}]'
  ans m4 references "$(sha_of "$other")" choose "$shown"
  run "$SCRIPT" set "$PROJ" refs "$other" --answer m4
  [ "$status" -eq 1 ]
  # a card without url (the payload) never matches
  ans m5 references "$(sha_of "$refs")" choose '[{"id":"x","thesis":"písmo"},{"id":"y","url":"https://y.example","thesis":"barvy"}]'
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer m5
  [ "$status" -eq 1 ]
  # an extra key is refused before any answer is looked at
  run "$SCRIPT" set "$PROJ" refs '[{"id":"x","url":"https://x.example","why":"a","picked":true}]' --answer m1
  [ "$status" -eq 2 ]
  [ "$(jq -c .refs "$STATE")" = '[]' ]; [ "$(jq -c .consumed "$STATE")" = '[]' ]
  # matching, in another order: accepted
  ans m6 references "$(sha_of "$refs")" choose "$(jq -c 'reverse' <<<"$shown")"
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer m6
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.refs[] | [.id, .url, .picked]]' "$STATE")" = '[["x","https://x.example",true],["y","https://y.example",false]]' ]
}

@test "set refs: compared with the cards the studio showed at answer time, never with a later payload.json" {
  refs='[{"id":"x","url":"https://x.example","why":"písmo"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  p="$PROJ/.aid-ui/studio/payload.json"
  # the reviewer's example: after the answer the chosen card's url is rewritten in payload.json
  evil='[{"id":"x","url":"https://evil.example","why":"písmo"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  ans s1 references "$(sha_of "$evil")" choose "$(cards_of "$refs")"
  jq '(.cards[] | select(.question == "s1" and .id == "x")).url = "https://evil.example"' "$p" > "$p.t" && mv "$p.t" "$p"
  run "$SCRIPT" set "$PROJ" refs "$evil" --answer s1
  [ "$status" -eq 1 ]; [[ "$output" == *'not the cards shown for question s1'* ]]
  [ "$(jq -c .refs "$STATE")" = '[]' ]; [ "$(jq -c .consumed "$STATE")" = '[]' ]
  [ "$(jq -c '.answers.s1.cards | map(.url)' "$STATE")" = '["https://x.example","https://y.example"]' ]
  # the thesis rewritten after the answer
  why='[{"id":"x","url":"https://x.example","why":"jiné"},{"id":"y","url":"https://y.example","why":"barvy"}]'
  ans s2 references "$(sha_of "$why")" choose "$(cards_of "$refs")"
  jq '(.cards[] | select(.question == "s2" and .id == "x")).thesis = "jiné"' "$p" > "$p.t" && mv "$p.t" "$p"
  run "$SCRIPT" set "$PROJ" refs "$why" --answer s2
  [ "$status" -eq 1 ]
  # a card added to payload.json after the answer
  more="$(jq -c '. + [{"id":"z","url":"https://z.example","why":"nové"}]' <<<"$refs")"
  ans s3 references "$(sha_of "$more")" choose "$(cards_of "$refs")"
  jq '.cards += [{question: "s3", id: "z", url: "https://z.example", thesis: "nové", method: "4-references.md"}]' "$p" > "$p.t" && mv "$p.t" "$p"
  run "$SCRIPT" set "$PROJ" refs "$more" --answer s3
  [ "$status" -eq 1 ]
  [ "$(jq -c .refs "$STATE")" = '[]' ]; [ "$(jq -c .consumed "$STATE")" = '[]' ]
  # the recorded snapshot digest altered in the state: the live studio disagrees
  ans s4 references "$(sha_of "$refs")" choose "$(cards_of "$refs")"
  jqw '.answers.s4.cards_sha256 = "0000"'
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer s4
  [ "$status" -eq 1 ]; [[ "$output" == *'differs from the recorded one'* ]]
  # refs matching the snapshot are accepted although payload.json now says otherwise
  ans s5 references "$(sha_of "$refs")" choose "$(cards_of "$refs")"
  jq '(.cards[] | select(.question == "s5" and .id == "x")).url = "https://evil.example"' "$p" > "$p.t" && mv "$p.t" "$p"
  run "$SCRIPT" set "$PROJ" refs "$refs" --answer s5
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.refs[] | [.id, .url, .picked]]' "$STATE")" = '[["x","https://x.example",true],["y","https://y.example",false]]' ]
}

@test "set options: validated, needs a variant answer for exactly this JSON, refused after step 0" {
  run "$SCRIPT" set "$PROJ" options '{"vision":true,"colour":true}'
  [ "$status" -eq 2 ]
  run "$SCRIPT" set "$PROJ" options '{"identity":true}'
  [ "$status" -eq 2 ]
  opts='{"vision":true,"identity":"package","seo":false}'
  run "$SCRIPT" set "$PROJ" options "$opts"
  [ "$status" -eq 1 ]; [[ "$output" == *'needs --answer'* ]]
  ans o0 references "$(sha_of "$opts")"                          # another kind
  run "$SCRIPT" set "$PROJ" options "$opts" --answer o0
  [ "$status" -eq 1 ]; [[ "$output" == *'not variant'* ]]
  ans o1 variant "$(sha_of '{"vision":false}')"                  # another options JSON
  run "$SCRIPT" set "$PROJ" options "$opts" --answer o1
  [ "$status" -eq 1 ]; [[ "$output" == *'is for'* ]]
  [ "$(jq .options.vision "$STATE")" = false ]
  ans o2 variant "$(sha_of "$opts")"
  run "$SCRIPT" set "$PROJ" options "$opts" --answer o2
  [ "$status" -eq 0 ]
  [ "$(jq -c .options "$STATE")" = '{"vision":true,"identity":"package","seo":false,"images":false}' ]
  "$SCRIPT" step "$PROJ" 1
  run "$SCRIPT" set "$PROJ" options '{"vision":false}'
  [ "$status" -eq 1 ]
  [ "$(jq .options.vision "$STATE")" = true ]
}

@test "set variant|options with a value on every card: the PM's card decides, not only the recommended one" {
  a='{"vision":true,"identity":"package","seo":true}'; b='{"vision":false,"identity":"new","seo":true}'
  cards="$(jq -nc --argjson a "$a" --argjson b "$b" '[{id: "x", value: $b}, {id: "y", value: $a}]')"
  ans c1 variant "$(sha_of "$(jq -nc --argjson a "$a" --argjson b "$b" '{x: $b, y: $a}')")" choose "$cards"   # the PM chose x
  run "$SCRIPT" set "$PROJ" options "$a" --answer c1                # the card the PM did not choose
  [ "$status" -eq 1 ]; [[ "$output" == *'its value is not this JSON'* ]]
  [ "$(jq -r .options.identity "$STATE")" = false ]
  run "$SCRIPT" set "$PROJ" options "$b" --answer c1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(jq -r .options.identity "$STATE")" = new ]
  # a target that is not the map of the shown cards is refused (the old one-JSON target does not pass)
  v='{"type":"web","brand":"new","local":true}'; w='{"type":"web","brand":"existing","local":true}'
  ans c3 variant "$(sha_of "$v")" choose "$(jq -nc --argjson v "$v" '[{id: "x", value: $v}]')"
  run "$SCRIPT" set "$PROJ" variant "$v" --answer c3
  [ "$status" -eq 1 ]; [[ "$output" == *'is for'* ]]
  # one card without a value does not switch the binding off
  ans c4 variant "$(sha_of "$w")" choose "$(jq -nc --argjson v "$v" '[{id: "x", value: $v}, {id: "y"}]')"
  run "$SCRIPT" set "$PROJ" variant "$w" --answer c4
  [ "$status" -eq 1 ]; [[ "$output" == *'every card needs'* ]]
  # the card the PM chose (x) decides the variant; the map hash is the same whatever the card order
  ans c5 variant "$(sha_of "$(jq -nc --argjson v "$v" --argjson w "$w" '{y: $w, x: $v}')")" choose "$(jq -nc --argjson v "$v" --argjson w "$w" '[{id: "y", value: $w}, {id: "x", value: $v}]')"
  run "$SCRIPT" set "$PROJ" variant "$w" --answer c5
  [ "$status" -eq 1 ]
  run "$SCRIPT" set "$PROJ" variant "$v" --answer c5
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(jq -r .variant.brand "$STATE")" = new ]
}

# --- P103 Step 4: answers, builds, gate, finish ----------------------------

@test "record-answer against the real studio: pending before the answer and when unreachable, recorded after" {
  SERVER="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/lib/aid-ui-studio/server.py"
  TOKEN=0123456789abcdef0123456789abcdef
  mkdir -p "$PROJ/.aid-ui/studio"; echo "$TOKEN" > "$PROJ/.aid-ui/studio.token"
  cat > "$PROJ/.aid-ui/studio/payload.json" <<'JSON'
{"questions": [{"id": "q1", "kind": "approve_page", "target": "index.html@abc", "opened_at": "2020-01-01T00:00:00Z"},
               {"id": "q2", "kind": "variant", "target": "sha256:x", "opened_at": "2020-01-01T00:00:00Z"}]}
JSON
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  export AID_UI_STUDIO_URL="http://127.0.0.1:$PORT"
  python3 "$SERVER" --project "$PROJ" --host 127.0.0.1 --port "$PORT" --token-file "$PROJ/.aid-ui/studio.token" \
    >"$T/server.log" 2>&1 3>&- &
  SPID=$!
  for i in $(seq 1 50); do curl -s -o /dev/null "$AID_UI_STUDIO_URL/" && break; sleep 0.1; done
  run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 1 ]
  [[ "$output" == *pending* ]]
  [ "$(jq '.answers | length' "$STATE")" = 0 ]
  run "$SCRIPT" record-answer "$PROJ" --question nope
  [ "$status" -eq 1 ]
  curl -s -o /dev/null -H "X-AID-Token: $TOKEN" -H 'Content-Type: application/json' \
    -d '{"question":"q1","kind":"approve_page","target":"index.html@abc","decision":"approve"}' "$AID_UI_STUDIO_URL/answer"
  run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 0 ]
  [ "$(jq -c '.answers.q1 | [.kind, .target, .decision, .opened_at]' "$STATE")" = '["approve_page","index.html@abc","approve","2020-01-01T00:00:00Z"]' ]
  [ "$(jq -r .answers.q1.answer_sha256 "$STATE")" = "$(sha256sum "$PROJ/.aid-ui/answers/q1.json" | cut -d' ' -f1)" ]
  kill "$SPID"; wait "$SPID" 2>/dev/null || true
  run "$SCRIPT" record-answer "$PROJ" --question q2
  [ "$status" -eq 1 ]
  [[ "$output" == *unreachable* ]]
  [ "$(jq '.answers | keys' -c "$STATE")" = '["q1"]' ]
}

@test "every PM mutation without --answer or with an unknown answer: exit 1, nothing written" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  cp "$STATE" "$T/before.json"
  for a in "" "--answer nope"; do
    for m in "set $PROJ variant {\"type\":\"web\",\"brand\":\"new\",\"local\":false}" "set $PROJ structure {\"pages\":[]}" \
             "set $PROJ content-plan []" "approve-page $PROJ index.html" "exception $PROJ --check axe"; do
      run "$SCRIPT" $m $a
      [ "$status" -eq 1 ]
    done
  done
  cmp "$STATE" "$T/before.json"
}

@test "an answer of another kind, another page, an old fingerprint, a return decision or a used answer: exit 1" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  ans v1 variant "index.html@$(fp index.html)"
  run "$SCRIPT" approve-page "$PROJ" index.html --answer v1
  [ "$status" -eq 1 ]; [[ "$output" == *"not approve_page"* ]]
  ans a1 approve_page "index.html@$(fp index.html)"
  run "$SCRIPT" approve-page "$PROJ" kontakt.html --answer a1
  [ "$status" -eq 1 ]; [[ "$output" == *"is for"* ]]
  ans r1 approve_page "index.html@$(fp index.html)" return
  run "$SCRIPT" approve-page "$PROJ" index.html --answer r1
  [ "$status" -eq 1 ]; [[ "$output" == *"decided return"* ]]
  run "$SCRIPT" approve-page "$PROJ" index.html --answer a1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.approvals["index.html"].answer' "$STATE")" = a1 ]
  run "$SCRIPT" approve-page "$PROJ" index.html --answer a1
  [ "$status" -eq 1 ]; [[ "$output" == *"already used"* ]]
  old="$(fp index.html)"
  echo 'body{color:red}' > "$SITE/style.css"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  [ "$(fp index.html)" != "$old" ]
  ans a2 approve_page "index.html@$old"
  run "$SCRIPT" approve-page "$PROJ" index.html --answer a2
  [ "$status" -eq 1 ]
  # a site edited after build-record: approval refused even with a matching answer
  ans a3 approve_page "index.html@$(fp index.html)"
  echo x >> "$SITE/index.html"
  run "$SCRIPT" approve-page "$PROJ" index.html --answer a3
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since build-record"* ]]
}

@test "set variant|structure|content-plan need the answer for exactly that JSON; defer-content marks the item" {
  s='{"pages":[{"id":"home","route":"/","sections":[]}]}'
  ans s1 structure "$(sha_of '{"pages":[]}')" choose
  run "$SCRIPT" set "$PROJ" structure "$s" --answer s1
  [ "$status" -eq 1 ]
  ans s2 structure "$(sha_of "$s")" choose
  run "$SCRIPT" set "$PROJ" structure "$s" --answer s2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.structure.pages[0].id' "$STATE")" = home ]
  run "$SCRIPT" set "$PROJ" variant '{"type":"blog"}' --answer s2
  [ "$status" -eq 2 ]
  cp='[{"id":"hero","status":"missing"},{"id":"about","status":"draft"}]'
  ans c1 content_plan "$(sha_of "$cp")"
  "$SCRIPT" set "$PROJ" content-plan "$cp" --answer c1
  ans d1 defer_content about
  run "$SCRIPT" defer-content "$PROJ" hero --answer d1
  [ "$status" -eq 1 ]
  run "$SCRIPT" defer-content "$PROJ" about --answer d1
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.content_plan[] | .status]' "$STATE")" = '["missing","deferred_by_pm"]' ]
  [ "$(jq -c .consumed "$STATE")" = '["s2","c1","d1"]' ]
}

@test "P108: confirm-content takes the approved copy verdict for the text items, a facts answer bound to one item; finish then passes" {
  ans v1 variant "$(sha_of '{"type":"web","brand":"new","local":false}')" choose
  "$SCRIPT" set "$PROJ" variant '{"type":"web","brand":"new","local":false}' --answer v1 >/dev/null
  cp='[{"id":"hero","status":"draft","source":"docs/content/copy.json"},{"id":"about","status":"missing","source":"docs/content/copy.json"},{"id":"shared.ico","need":"IČO do pätičky","status":"missing"},{"id":"foto","need":"fotka","status":"missing"}]'
  ans c1 content_plan "$(sha_of "$cp")"
  "$SCRIPT" set "$PROJ" content-plan "$cp" --answer c1 >/dev/null
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  approve index.html 1; approve kontakt.html 1
  result; "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  end_order; serve_200; "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"content item hero is draft"* ]]
  before="$(jq -c '[.content_plan[] | .status], .consumed' "$STATE")"
  run "$SCRIPT" confirm-content "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"needs --answer"* ]]
  mkdir -p "$PROJ/.aid-ui/copy"; echo '{"pages":[]}' > "$PROJ/.aid-ui/copy/subject.json"
  sub="copy@$(sha256sum "$PROJ/.aid-ui/copy/subject.json" | cut -d' ' -f1)"
  ans t0 copy_verdict "copy@0000"
  run "$SCRIPT" confirm-content "$PROJ" --answer t0
  [ "$status" -eq 1 ]; [[ "$output" == *"is for"* ]]
  ans tc copy_verdict "$sub" choose
  run "$SCRIPT" confirm-content "$PROJ" --answer tc
  [ "$status" -eq 1 ]; [[ "$output" == *"not an approve"* ]]
  run "$SCRIPT" confirm-content "$PROJ" --answer c1       # another kind, and already used
  [ "$status" -eq 1 ]
  [ "$(jq -c '[.content_plan[] | .status], .consumed' "$STATE")" = "$before" ]
  ans t1 copy_verdict "$sub"
  run "$SCRIPT" confirm-content "$PROJ" --answer t1
  [ "$status" -eq 0 ]; [[ "$output" == *"CONFIRMED: 2 text items"* ]]
  [ "$(jq -c '[.content_plan[] | .status]' "$STATE")" = '["confirmed_client","confirmed_client","missing","missing"]' ]
  run "$SCRIPT" confirm-content "$PROJ" --answer t1       # used once
  [ "$status" -eq 1 ]; [[ "$output" == *"already used"* ]]
  # one item: the facts answer must be about the registry as it is now, and the item must name the fact
  mkdir -p "$PROJ/docs/content"; printf 'ico: {value: "52123723", source: PM}\n' > "$PROJ/docs/content/facts.yaml"
  ans f0 facts "docs/content/facts.yaml@stale" choose
  run "$SCRIPT" confirm-content "$PROJ" --item shared.ico --fact ico --answer f0
  [ "$status" -eq 1 ]; [[ "$output" == *"is for"* ]]
  ans f1 facts "docs/content/facts.yaml@$(sha256sum "$PROJ/docs/content/facts.yaml" | cut -d' ' -f1)" choose
  run "$SCRIPT" confirm-content "$PROJ" --item foto --fact ico --answer f1
  [ "$status" -eq 1 ]; [[ "$output" == *"does not name the fact"* ]]
  run "$SCRIPT" confirm-content "$PROJ" --item shared.ico --fact phone --answer f1
  [ "$status" -eq 1 ]; [[ "$output" == *"no fact phone"* ]]
  run "$SCRIPT" confirm-content "$PROJ" --item shared.ico --answer f1
  [ "$status" -eq 2 ]
  [ "$(jq -r '.content_plan[2].status' "$STATE")" = missing ]
  run "$SCRIPT" confirm-content "$PROJ" --item shared.ico --fact ico --answer f1
  [ "$status" -eq 0 ]; [[ "$output" == *"CONFIRMED: shared.ico (fact ico)"* ]]
  ans d1 defer_content foto
  "$SCRIPT" defer-content "$PROJ" foto --answer d1 >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
}

@test "P108 build: build-record wants a fresh build method receipt and, with a picked reference, the PM's direction choice over the inventory as it is and a motion check of the site as it is" {
  MP="$BATS_TEST_DIRNAME/../../aid-ui-motion.py"; FXR="$BATS_TEST_DIRNAME/../fixtures/aid-ui/motion-record.json"
  rm "$PROJ/.aid-ui/method/build.json"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"no method receipt for build"* ]]
  "$SCRIPT" method "$PROJ" build >/dev/null
  jq '.at = "2020-01-01T00:00:00.000000Z"' "$PROJ/.aid-ui/method/build.json" > "$PROJ/r.t" && mv "$PROJ/r.t" "$PROJ/.aid-ui/method/build.json"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"receipt is"*"h old"* ]]
  "$SCRIPT" method "$PROJ" build >/dev/null
  jq '.files[0].sha256 = "0000"' "$PROJ/.aid-ui/method/build.json" > "$PROJ/r.t" && mv "$PROJ/r.t" "$PROJ/.aid-ui/method/build.json"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not cover the current"* ]]
  "$SCRIPT" method "$PROJ" build >/dev/null
  run "$SCRIPT" build-record "$PROJ" "$SITE"     # no reference picked: nothing about motion
  [ "$status" -eq 0 ]
  # a picked reference: inventory, the PM's direction choice over it, the site observed as it is
  ans r1 references "$(sha_of '[{"id":"fx","url":"http://127.0.0.1:39931/index.html","why":"pohyb"}]')" choose
  jqw '.refs = [{"id":"fx","url":"http://127.0.0.1:39931/index.html","why":"pohyb","picked":true}]'
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"no .aid-ui/motion.json"* ]]
  mkdir -p "$PROJ/.aid-ui/refs"; cp "$FXR" "$PROJ/.aid-ui/refs/fx.motion.json"
  python3 "$MP" inventory "$PROJ" >/dev/null
  python3 - "$PROJ/.aid-ui/motion.json" <<'PY'
import json, sys
p = sys.argv[1]; inv = json.load(open(p))
for i in inv["items"]:
    i["disposition"] = "adopt"; i["target"] = i.get("name") or i.get("property") or "leave,arrive"
json.dump(inv, open(p, "w"), ensure_ascii=False)
PY
  msha="$(sha256sum "$PROJ/.aid-ui/motion.json" | cut -d' ' -f1)"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"no recorded direction choice for the inventory as it is now"* ]]
  forge d1 direction "smer:$msha" choose
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"no .aid-ui/build.motion.json"* ]]
  jq --arg s "$(python3 "$MP" dirsha "$SITE")" '.dir_sha256 = $s | .keyframes |= map(select(.name != "spin"))' "$FXR" > "$PROJ/.aid-ui/build.motion.json"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not carry the reference's motion"* && "$output" == *"'spin' never ran"* ]]
  jq --arg s "$(python3 "$MP" dirsha "$SITE")" '.dir_sha256 = $s' "$FXR" > "$PROJ/.aid-ui/build.motion.json"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 0 ]; [[ "$output" == *"BUILD: "*"PASS: z 9 pohybů vzoru"* ]]
  [ -f "$PROJ/.aid-ui/build.motion.check.json" ]
  echo '<p>změna</p>' >> "$SITE/index.html"
  run "$SCRIPT" build-record "$PROJ" "$SITE"
  [ "$status" -eq 1 ]; [[ "$output" == *"was not observed over the directory as it is now"* ]]
}

@test "P108 end: links binds the web to the recorded build and the customer link to the customer page; chapter-all refuses before the final gate's page and report and a returned web; finish re-checks the links and writes the verdict" {
  ready
  run "$SCRIPT" links "$PROJ" --web "http://127.0.0.1:9/" --customer "$CUST_URL"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not answer 200"* ]]
  run "$SCRIPT" links "$PROJ" --web "${LINK_URL}kontakt.html" --customer "$CUST_URL"      # answers 200, but it is not the home page of the build
  [ "$status" -eq 1 ]; [[ "$output" == *"does not serve the recorded build's index.html"* ]]
  run "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "${LINK_URL}index.html"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not serve docs/zakaznik/index.html"* ]]
  "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
  [ "$(jq -r .web "$PROJ/.aid-ui/links.json")" == "$LINK_URL" ]
  # the end in order: the page the gate ran over (sha), the coverage report of that gate
  "$SCRIPT" chapter "$PROJ" barvy navrh
  echo '<p>jiná</p>' > "$PROJ/docs/zakaznik/index.html"
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"not the page the recorded gate ran over"* ]]
  echo '<p>zakaznik</p>' > "$PROJ/docs/zakaznik/index.html"
  jq '.gate_run_at = "2020-01-01T00:00:00Z"' "$PROJ/docs/design/soulad-summary.json" > "$PROJ/s.t" && mv "$PROJ/s.t" "$PROJ/docs/design/soulad-summary.json"
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"not from the recorded gate"* ]]
  # P113: a customer_page pass row the result brings is not trusted - gate-record writes the row itself
  # a refused record (a row missing) leaves the page of the recorded gate in place; nothing new is moved over it
  before="$(cat "$PROJ/docs/zakaznik/index.html")"
  result '.rows |= .[1:]'; AID_UI_TEST_CP_TEXT='<p>nová</p>' run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 1 ]; [ "$(cat "$PROJ/docs/zakaznik/index.html")" == "$before" ]; [ ! -e "$PROJ/.aid-ui/customer-page.new" ]
  result; AID_UI_TEST_CP_RC=1 "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  jq -e '.gate.customer_page == "not_covered"' "$STATE" >/dev/null
  jq -e '[.rows[] | select(.check == "customer_page")] | length == 1 and .[0].status == "not_covered" and (.[0].detail | contains("not made: the gate is not green"))' "$RES" >/dev/null
  end_order
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"has no checked customer page"* ]]
  result; "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null; end_order
  [ ! -f "$PROJ/.aid-ui/finish.json" ]
  run "$SCRIPT" chapter-all-target "$PROJ"
  [ "$status" -eq 0 ]
  # a returned web is no handover
  ans h0 handover "$("$SCRIPT" chapter-all-target "$PROJ")" choose '[{"id":"a","value":"prevzit"},{"id":"b","value":"vyhrada"},{"id":"x","value":"vratit"}]'
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h0
  [ "$status" -eq 1 ]; [[ "$output" == *"the PM returned the web"* ]]
  [ "$(jq -r '.chapters.barvy.status' "$STATE")" == navrh ]
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")" choose
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  [ "$(jq -r '.handover.verdict, .handover.rating' "$STATE" | paste -sd' ')" == "prevzit 8-10" ]
  # finish: links must still answer; the verdict lands in finish.json; a new build forgets it
  rm "$PROJ/.aid-ui/links.json"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"no .aid-ui/links.json"* ]]
  "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
  kill "$LINK_PID"; wait "$LINK_PID" 2>/dev/null || true; LINK_PID=""
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"no longer answers 200"* ]]
  serve_200; "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]; [[ "$output" == *"verdict prevzit (8-10/10)"* ]]
  [ "$(jq -r '.web, .verdict, .rating' "$PROJ/.aid-ui/finish.json" | paste -sd' ')" == "$LINK_URL prevzit 8-10" ]
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  [ ! -f "$PROJ/.aid-ui/finish.json" ] && [ ! -f "$PROJ/.aid-ui/links.json" ]
}

@test "P108 migration: a restored answer without a live record is taken only when the studio's migrated cards hash equals the one recorded live" {
  ans v1 variant "$(sha_of '{"type":"web","brand":"new","local":false}')" choose
  # the studio restarts without its in-memory answer and with a history line from before the hash was kept
  kill "$STUDIO_PID"; wait "$STUDIO_PID" 2>/dev/null || true
  python3 - "$PROJ/.aid-ui/studio/history.jsonl" <<'PY'
import json, sys
p = sys.argv[1]; lines = [json.loads(l) for l in open(p) if l.strip()]
out = []
for e in lines:
    if e.get("question", {}).get("id") == "v1": e.pop("cards_sha256", None)
    out.append(json.dumps(e, ensure_ascii=False))
open(p, "w").write("\n".join(out) + "\n")
PY
  cp "$PROJ/.aid-ui/studio/payload.json" "$T/payload.keep"
  STUDIO_PID=""; studio; cp "$T/payload.keep" "$PROJ/.aid-ui/studio/payload.json"   # studio() resets the payload; the question stays listed
  run "$SCRIPT" set "$PROJ" variant '{"type":"web","brand":"new","local":false}' --answer v1
  [ "$status" -eq 0 ]
  # the same, with the cards changed in the payload since: the migrated hash differs, refused
  ans v2 variant "$(sha_of '{"type":"web","brand":"new","local":true}')" choose
  kill "$STUDIO_PID"; wait "$STUDIO_PID" 2>/dev/null || true
  python3 - "$PROJ/.aid-ui/studio/history.jsonl" "$PROJ/.aid-ui/studio/payload.json" <<'PY'
import json, sys
p = sys.argv[1]; lines = [json.loads(l) for l in open(p) if l.strip()]
open(p, "w").write("\n".join(json.dumps({k: v for k, v in e.items() if not (e.get("question", {}).get("id") == "v2" and k == "cards_sha256")}, ensure_ascii=False) for e in lines) + "\n")
q = sys.argv[2]; pl = json.load(open(q))
for c in pl["cards"]:
    if c["question"] == "v2": c["title"] = "jiná karta"
json.dump(pl, open(q, "w"))
PY
  cp "$PROJ/.aid-ui/studio/payload.json" "$T/payload.keep"
  STUDIO_PID=""; studio; cp "$T/payload.keep" "$PROJ/.aid-ui/studio/payload.json"
  run "$SCRIPT" set "$PROJ" variant '{"type":"web","brand":"new","local":true}' --answer v2
  [ "$status" -eq 1 ]; [[ "$output" == *"differs from the recorded one"* ]]
}

@test "P108 open items: add and done need shape; the PM's own items come from the studio history once each; the customer page lists what stays open" {
  run "$SCRIPT" open-item "$PROJ" add --text "" --owner PM
  [ "$status" -eq 2 ]
  run "$SCRIPT" open-item "$PROJ" add --text "Fotka lékaře" --owner nekdo
  [ "$status" -eq 2 ]
  run "$SCRIPT" open-item "$PROJ" add --text "Fotka lékaře" --owner klient --due 2026-11-01
  [ "$status" -eq 0 ]; [[ "$output" == "OPEN ITEM: oi-1" ]]
  "$SCRIPT" open-item "$PROJ" add --text "Doména" --owner PM >/dev/null
  [ "$(jq -c '[.open_items[] | [.id, .owner, .due, .status]]' "$STATE")" == '[["oi-1","klient","2026-11-01","open"],["oi-2","PM",null,"open"]]' ]
  "$SCRIPT" open-item "$PROJ" done oi-2
  [ "$(jq -r '.open_items[1].status' "$STATE")" == done ]
  run "$SCRIPT" open-item "$PROJ" done oi-9
  [ "$status" -eq 1 ]
  mkdir -p "$PROJ/.aid-ui/studio"
  printf '{"by":"pm","kind":"open_item","text":"Právník zkontroluje text","at":"2026-10-10T08:00:00.123456Z"}\n{"by":"pm","kind":"open_item","text":"x","at":"nic"}\nnot json\n' >> "$PROJ/.aid-ui/studio/history.jsonl"
  run "$SCRIPT" open-items-sync "$PROJ"
  [ "$status" -eq 0 ]; [[ "$output" == "SYNC: 1 new open item(s) from the PM" ]]
  run "$SCRIPT" open-items-sync "$PROJ"
  [[ "$output" == "SYNC: 0 new open item(s) from the PM" ]]
  [ "$(jq -c '[.open_items[] | select(.by == "pm") | .id]' "$STATE")" == '["pm-20261010080000123456"]' ]
}

@test "H7: a critical open item does not stop finish but blocks publication in finish.json; only done with evidence clears it" {
  ready
  "$SCRIPT" open-item "$PROJ" add --text "IČO do patičky" --owner klient --critical --evidence "IČO na každé stránce" >/dev/null
  "$SCRIPT" open-item "$PROJ" add --text "Vizitka" --owner agent >/dev/null
  run "$SCRIPT" open-item "$PROJ" add --text "Doména" --owner agent --critical; [ "$status" -eq 2 ]; [[ "$output" == *"needs --evidence"* ]]
  jq -e '.open_items | (.[0].critical == true and .[0].evidence == "IČO na každé stránce" and .[1].critical == false)' "$STATE" >/dev/null
  run "$SCRIPT" finish "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"PUBLISH BLOCKED by 1 critical open item(s): oi-1"* ]]
  jq -e '.publish_blocked_by == [{"id":"oi-1","text":"IČO do patičky","owner":"klient"}]' "$PROJ/.aid-ui/finish.json" >/dev/null
  # no way to un-mark it; done without evidence is refused, done with evidence clears the block
  "$SCRIPT" open-item "$PROJ" critical oi-1 --off >/dev/null; jq -e '.open_items[0].critical == true' "$STATE" >/dev/null
  run "$SCRIPT" open-item "$PROJ" done oi-1; [ "$status" -eq 1 ]; [[ "$output" == *"blocks publication"* ]]
  "$SCRIPT" open-item "$PROJ" done oi-1 --evidence "IČO 12345678 v patičce všech stránek" >/dev/null
  run "$SCRIPT" finish "$PROJ"; [ "$status" -eq 0 ]; [[ "$output" != *"PUBLISH BLOCKED"* ]]
  jq -e '.publish_blocked_by == []' "$PROJ/.aid-ui/finish.json" >/dev/null
}

@test "all conditions met: finish succeeds; a backward step clears finished" {
  ready
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .finished "$STATE")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  "$SCRIPT" step "$PROJ" 7
  [ "$(jq -r .finished "$STATE")" != null ]
  "$SCRIPT" step "$PROJ" 5
  [ "$(jq .finished "$STATE")" = null ]
  run "$SCRIPT" step "$PROJ" 8
  [ "$status" -eq 2 ]
}

@test "build-record writes nothing into the site; build-id matches; a site file edited after it: finish refuses" {
  before="$(cd "$SITE" && find . -type f | sort)"
  ready
  [ "$(cd "$SITE" && find . -type f | sort)" = "$before" ]
  [ "$("$SCRIPT" build-id "$SITE")" = "$(jq -r .build.id "$STATE")" ]
  [ "$(jq -r .id "$PROJ/.aid-ui/build.json")" = "$(jq -r .build.id "$STATE")" ]
  echo 'Disallow: /' >> "$SITE/robots.txt"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since build-record"* ]]
  run "$SCRIPT" build-record "$PROJ" "$PROJ/.."
  [ "$status" -eq 1 ]
}

@test "a rebuild after the gate refuses; a page added after the gate refuses" {
  ready
  echo 'User-agent: x' > "$SITE/robots.txt"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"gate result is for build"* ]]
  # only _site changed: both page approvals still hold
  [[ "$output" != *"not approved"* ]]
  echo '<html>new</html>' > "$SITE/cenik.html"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"page cenik.html is not approved"* ]]
}

@test "a result with no webkit rows: gate-record and finish refuse" {
  ready
  jqw '.gate = null'
  result '.rows |= map(select(.browser != "webkit"))'
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing row: http_200 index.html/390/webkit"* ]]
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"no gate result"* ]]
  # a result edited after gate-record
  result
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  result '.rows |= map(select(.browser != "webkit"))'
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed or is missing since gate-record"* ]]
}

@test "an app result missing a flow state: gate-record refuses; with it the gate records" {
  ready
  st='{"pages":[{"id":"home"}],"roles":["admin"],"flows":[{"id":"checkout","steps":["a"],"states":["normal","empty"]}]}'
  ans s1 structure "$(sha_of "$st")"; "$SCRIPT" set "$PROJ" structure "$st" --answer s1 >/dev/null
  ans v2 variant "$(sha_of '{"type":"webapp","brand":"new","local":false}')"
  "$SCRIPT" set "$PROJ" variant '{"type":"webapp","brand":"new","local":false}' --answer v2 >/dev/null
  # the recorded web result has no flow rows at all
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing row: axe checkout/390/chromium/admin/normal"* ]]
  result '.rows |= map(select(.state != "empty"))'
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing row: axe checkout/1440/webkit/admin/empty"* ]]
  result
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 0 ]
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
}

@test "roles and flow states given as objects {id, …}: the gate rows use their ids" {
  ready
  st='{"pages":[{"id":"home"}],"roles":[{"id":"admin","name":"Správce"}],"flows":[{"id":"checkout","states":[{"id":"normal","how":"a"},{"id":"empty","how":"b"}]}]}'
  ans s1 structure "$(sha_of "$st")"; "$SCRIPT" set "$PROJ" structure "$st" --answer s1 >/dev/null
  ans v2 variant "$(sha_of '{"type":"webapp","brand":"new","local":false}')"
  "$SCRIPT" set "$PROJ" variant '{"type":"webapp","brand":"new","local":false}' --answer v2 >/dev/null
  result
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 0 ] || { echo "$output" | head -3; return 1; }
}

@test "not_covered webkit rows: refused without exception; one browser=webkit page=* answer covers all; another viewport does not" {
  ready
  result '.rows |= map(if .browser == "webkit" and .check == "axe" then .status = "not_covered" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"not_covered row without a live exception: axe index.html/390/webkit"* ]]
  ans e1 exception '{"check":"axe","page":"*","viewport":"390","browser":"webkit","role":"*","state":"*"}'
  run "$SCRIPT" exception "$PROJ" --check axe --viewport 390 --browser webkit --answer e1
  [ "$status" -eq 0 ]
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"axe kontakt.html/768/webkit"* ]]; [[ "$output" != *"/390/webkit"* ]]
  # the answer's target is a selector compared as JSON: key order does not matter
  ans e2 exception '{"browser":"webkit","check":"axe","page":"*","role":"*","state":"*","viewport":"*"}'
  run "$SCRIPT" exception "$PROJ" --check axe --browser webkit --page '*' --answer e2
  [ "$status" -eq 0 ]
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
}

@test "P108: an exception answer may leave out the selector keys that are *, as step 7 says (Coufal 9. 10.)" {
  ready
  result '.rows |= map(if .page == "kontakt.html" and .check == "axe" then .status = "fail" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  ans e1 exception '{"check":"axe","page":"kontakt.html"}'
  run "$SCRIPT" exception "$PROJ" --check axe --page kontakt.html --answer e1
  [ "$status" -eq 0 ]
  # a different page is still a different selector
  ans e2 exception '{"check":"axe","page":"index.html"}'
  run "$SCRIPT" exception "$PROJ" --check axe --page kontakt.html --answer e2
  [ "$status" -eq 1 ]; [[ "$output" == *"is for"* ]]
}

@test "a changed page fingerprint voids its approval and its exception, not the other page's" {
  ready
  result '.rows |= map(if .page == "kontakt.html" and .check == "axe" then .status = "fail" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  ans e1 exception '{"check":"axe","page":"kontakt.html","viewport":"*","browser":"*","role":"*","state":"*"}'
  "$SCRIPT" exception "$PROJ" --check axe --page kontakt.html --answer e1 >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
  echo '<html><img src="/logo.webp"><p>nové</p></html>' > "$SITE/kontakt.html"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  result '.rows |= map(if .page == "kontakt.html" and .check == "axe" then .status = "fail" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"page kontakt.html is not approved"* ]]
  [[ "$output" == *"fail row without a live exception: axe kontakt.html"* ]]
  [[ "$output" != *"page index.html"* ]]
}

@test "H4: a change to the shared inline style voids only the _shared approval; a page-* exception holds while the row fails for the same reason" {
  echo '<html><style>.b{color:red}</style><link href="style.css" rel="stylesheet"><a href="kontakt.html">k</a></html>' > "$SITE/index.html"
  echo '<html><style>.b{color:red}</style><img src="/logo.webp"></html>' > "$SITE/kontakt.html"
  ready
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "critical color-contrast (2)" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  ans e1 exception '{"check":"axe","page":"*"}'
  run "$SCRIPT" exception "$PROJ" --check axe --answer e1; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.exceptions[0].reasons == ["critical color-contrast"]' "$STATE" >/dev/null
  shared="$(jq -r .build.shared "$STATE")"; [ -n "$shared" ] && [ "$shared" != null ]
  ans s1 approve_page "_shared@$shared"; "$SCRIPT" approve-page "$PROJ" _shared --answer s1 >/dev/null
  run "$SCRIPT" finish "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # the shared style changes on both pages: page approvals hold, _shared is void, the exception still covers
  sed -i 's/color:red/color:blue/' "$SITE/index.html" "$SITE/kontakt.html"
  run "$SCRIPT" build-record "$PROJ" "$SITE"; [[ "$output" == *"APPROVALS VOID"*"_shared"* ]]; [[ "$output" != *"index.html"* ]]
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "critical color-contrast (5)" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"; [ "$status" -eq 1 ]
  [[ "$output" == *"shared look"* ]]; [[ "$output" != *"page index.html is not approved"* ]]; [[ "$output" != *"without a live exception"* ]]
  # the same reason with other spacing is still the same reason
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "critical   color-contrast  (7)" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"; [[ "$output" != *"without a live exception"* ]]
  # a new reason on the same check is not excused
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "serious image-alt (1)" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"; [[ "$output" == *"fail row without a live exception: axe"* ]]
  # a page that drops the shared block changes its own fingerprint (the block is a marker, not nothing)
  echo '<html><img src="/logo.webp"></html>' > "$SITE/kontakt.html"; echo '<html><style>.b{color:blue}</style><p>x</p></html>' > "$SITE/tretí.html"
  run "$SCRIPT" build-record "$PROJ" "$SITE"; [[ "$output" == *"APPROVALS VOID"*"kontakt.html"* ]]; [[ "$output" != *"index.html"* ]]
}

@test "H4: an old page-* exception without reasons is migrated once to the reasons of the next recorded gate, visibly" {
  ready
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "critical color-contrast (2)" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  ans e1 exception '{"check":"axe","page":"*"}'
  "$SCRIPT" exception "$PROJ" --check axe --answer e1 >/dev/null
  jq '.exceptions[0] |= del(.reasons)' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"   # as written before 12. 10. 2026
  result '.rows |= map(if .check == "axe" then .status = "fail" | .detail = "critical color-contrast (3)" else . end)'
  run "$SCRIPT" gate-record "$PROJ" "$RES"; [[ "$output" == *"MIGRATED page-* exception(s) to their reasons"*"critical color-contrast"* ]]
  jq -e '.exceptions[0].reasons == ["critical color-contrast"] and .exceptions[0].reasons_migrated == true' "$STATE" >/dev/null
}

@test "an exception whose check passes at the next gate is kept as resolved and covers no more" {
  ready
  result '.rows |= map(if .browser == "webkit" then .status = "not_covered" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  ans e1 exception '{"check":"http_200","page":"*","viewport":"*","browser":"webkit","role":"*","state":"*"}'
  "$SCRIPT" exception "$PROJ" --check http_200 --browser webkit --answer e1 >/dev/null
  result '.rows |= map(if .browser == "webkit" and .check != "http_200" then .status = "not_covered" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  [ "$(jq -r '.exceptions[0].resolved' "$STATE")" = "$(jq -r .run_at "$RES")" ]
  result '.rows |= map(if .browser == "webkit" then .status = "not_covered" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"not_covered row without a live exception: http_200"* ]]
}

@test "an answer file edited after use: finish refuses" {
  ready
  echo '{"decision":"approve","forged":true}' > "$PROJ/.aid-ui/answers/ap-index.html-1.json"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"answer file of ap-index.html-1 changed"* ]]
}

@test "coverage exit 3: refused without a coverage_drift answer naming exactly the changed items" {
  ready
  sed -i 's/The owner approves every page./The owner approves each page./' "$SPECS/a.md"
  new="$(bash "$BATS_TEST_DIRNAME/../../aid-ui-coverage.sh" extract "$PROJ" | grep -F 'approves each page' | cut -f1)"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"no coverage_drift answer"* ]]
  ans d1 coverage_drift "$new,other"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]
  ans d2 coverage_drift "$new"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
  # a map gap (exit 1) refuses whatever was answered
  printf -- '- A brand new rule.\n' >> "$SPECS/b.md"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"exited 1"* ]]
}

@test "a content item still missing: finish refuses" {
  ready
  cp='[{"id":"hero","status":"confirmed_client"},{"id":"team","status":"missing"}]'
  ans c2 content_plan "$(sha_of "$cp")"; "$SCRIPT" set "$PROJ" content-plan "$cp" --answer c2 >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"content item team is missing"* ]]
}

@test "P113a gate-check: the build and the gate only - a missing content item passes it, a site edited after the gate does not" {
  ready
  cp='[{"id":"hero","status":"confirmed_client"},{"id":"team","status":"missing"}]'
  ans c2 content_plan "$(sha_of "$cp")"; "$SCRIPT" set "$PROJ" content-plan "$cp" --answer c2 >/dev/null
  run "$SCRIPT" gate-check "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }; [[ "$output" == "GATE OK: build "* ]]
  echo 'User-agent: x' > "$SITE/robots.txt"; "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  run "$SCRIPT" gate-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"gate result is for build"* ]]
}

@test "attest records {note, at} only for an agent: item of the coverage map" {
  run "$SCRIPT" attest "$PROJ" 'ecosystem/specs/a.md#Standard A > Rules#0ec58950' --note "prošel jsem klávesnicí"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.attestations["ecosystem/specs/a.md#Standard A > Rules#0ec58950"] | keys | join(",")' "$STATE")" = at,note ]
  run "$SCRIPT" attest "$PROJ" 'ecosystem/specs/a.md#Standard A > Rules#923b9432' --note x
  [ "$status" -eq 1 ]
  run "$SCRIPT" attest "$PROJ" 'ecosystem/specs/a.md#Standard A > Rules#0ec58950'
  [ "$status" -eq 2 ]
}

@test "no verb of the removed Impeccable and companion rounds is left" {
  for v in await-direction await-choice pending-direction require-direction spend; do
    run "$SCRIPT" "$v" "$PROJ"
    [ "$status" -eq 2 ]
  done
}

# --- P103 Step 4 review round 1 --------------------------------------------

@test "a row status outside pass|fail|warn|not_covered: gate-record and finish refuse" {
  ready
  for s in '"error"' '"skipped"' null; do
    result ".rows[0].status = $s"
    run "$SCRIPT" gate-record "$PROJ" "$RES"
    [ "$status" -eq 1 ]; [[ "$output" == *"row with status $s"* ]]
  done
  # finish checks again: a result recorded by hand past gate-record
  result '.rows[0].status = "error"'
  jqw --arg sha "$(sha256sum "$RES" | cut -d' ' -f1)" '.gate.result_sha256 = $sha'
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *'row with status "error"'* ]]
}

@test "warn blocks like fail unless the check is warn_only" {
  ready
  result '.rows |= map(if .check == "axe" and .page == "index.html" then .status = "warn" else . end)'
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"warn row without a live exception: axe index.html"* ]]
  echo 'warn_only: [axe]' >> "$T/cov/checks.yaml"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
}

@test "record-answer: a foreign studio URL is refused; an answer for another target is not recorded; the token is never on argv" {
  mkdir -p "$PROJ/.aid-ui/studio" "$T/fake" "$T/bin"
  echo 0123456789abcdef > "$PROJ/.aid-ui/studio.token"
  echo '{"questions": [{"id": "q1", "kind": "approve_page", "target": "index.html@abc", "opened_at": "2020-01-01T00:00:00Z"}]}' \
    > "$PROJ/.aid-ui/studio/payload.json"
  AID_UI_STUDIO_URL=http://evil.example:3915 run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 1 ]; [[ "$output" == *"studio URL refused"* ]]
  # any HTTP server serving a file the agent wrote (python -m http.server ignores the query)
  echo '{"question":"q1","kind":"approve_page","target":"kontakt.html@abc","decision":"approve","at":"2026-01-01T00:00:00Z","cards":[],"cards_sha256":"x"}' > "$T/fake/answer"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/fake" >/dev/null 2>&1 3>&- &
  SPID=$!
  for i in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/answer" && break; sleep 0.1; done
  AID_UI_STUDIO_URL="http://127.0.0.1:$PORT" run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 1 ]; [[ "$output" == *"not the listed question"* ]]
  [ "$(jq '.answers | length' "$STATE")" = 0 ]
  # an answer without the studio's card snapshot is malformed
  echo '{"question":"q1","kind":"approve_page","target":"index.html@abc","decision":"approve","at":"2026-01-01T00:00:00Z"}' > "$T/fake/answer"
  AID_UI_STUDIO_URL="http://127.0.0.1:$PORT" run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 1 ]; [[ "$output" == *"malformed answer"* ]]
  [ "$(jq '.answers | length' "$STATE")" = 0 ]
  # a curl stub records its argv and stdin
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > %s/argv; cat > %s/stdin; printf 404\n' "$T" "$T" > "$T/bin/curl"; chmod +x "$T/bin/curl"
  AID_UI_STUDIO_URL=http://localhost:1 PATH="$T/bin:$PATH" run "$SCRIPT" record-answer "$PROJ" --question q1
  [ "$status" -eq 1 ]
  ! grep -q 0123456789abcdef "$T/argv" || false
  grep -qx 'X-AID-Token: 0123456789abcdef' "$T/stdin"
}

@test "build-record refuses a site in <project>/docs or one holding .aid-ui/" {
  run "$SCRIPT" build-record "$PROJ" "$PROJ/docs"
  [ "$status" -eq 1 ]; [[ "$output" == *"build-record refused"* ]]
  mkdir -p "$PROJ/.aid-ui/site" "$T/other/.aid-ui"
  run "$SCRIPT" build-record "$PROJ" "$PROJ/.aid-ui/site"
  [ "$status" -eq 1 ]
  run "$SCRIPT" build-record "$PROJ" "$T/other"
  [ "$status" -eq 1 ]
  [ "$(jq .build "$STATE")" = null ]
}

# --- P103 EPIC review round 1 ----------------------------------------------

@test "a state-file answer the studio never gave, one that differs from the studio's, or no studio: the mutation refuses" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  studio
  forge f1 approve_page "index.html@$(fp index.html)"
  cp "$STATE" "$T/before.json"
  run "$SCRIPT" approve-page "$PROJ" index.html --answer f1
  [ "$status" -eq 1 ]; [[ "$output" == *"studio does not hold answer f1"* ]]
  cmp "$STATE" "$T/before.json"
  # the PM returned the page; the agent rewrites the recorded decision to approve
  ans r1 approve_page "index.html@$(fp index.html)" return
  jqw '.answers.r1.decision = "approve"'
  run "$SCRIPT" approve-page "$PROJ" index.html --answer r1
  [ "$status" -eq 1 ]; [[ "$output" == *"differs from the recorded one"* ]]
  # a genuine answer, but the studio is gone at mutation time
  ans a1 approve_page "index.html@$(fp index.html)"
  kill "$STUDIO_PID"; wait "$STUDIO_PID" 2>/dev/null || true
  run "$SCRIPT" approve-page "$PROJ" index.html --answer a1
  [ "$status" -eq 1 ]; [[ "$output" == *"studio unreachable"* ]]
  [ "$(jq '.approvals | length' "$STATE")" = 0 ]
}

@test "two concurrent approve-page with the same answer: exactly one succeeds" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  ans a1 approve_page "index.html@$(fp index.html)"
  "$SCRIPT" approve-page "$PROJ" index.html --answer a1 >"$T/o1" 2>&1 3>&- & p1=$!
  "$SCRIPT" approve-page "$PROJ" index.html --answer a1 >"$T/o2" 2>&1 3>&- & p2=$!
  r1=0; wait "$p1" || r1=$?
  r2=0; wait "$p2" || r2=$?
  [ $(( (r1 == 0) + (r2 == 0) )) -eq 1 ]
  cat "$T/o1" "$T/o2" | grep -q "already used"
  [ "$(jq -c .consumed "$STATE")" = '["a1"]' ]
}

@test "a brand-state.json.lock symlink to a file outside the project is never written" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  echo victim >"$T/victim"
  ln -s "$T/victim" "$STATE.lock"
  ans a1 approve_page "index.html@$(fp index.html)"
  "$SCRIPT" approve-page "$PROJ" index.html --answer a1 >/dev/null
  [ "$(cat "$T/victim")" = victim ]
  [ "$(jq -c .consumed "$STATE")" = '["a1"]' ]
}

@test "checks.yaml applies: no glyph rows on webkit pass gate-record; missing glyph on chromium is refused" {
  yq -i '.checks.glyph_coverage = "glyphs" | .applies.glyph_coverage = {"browsers": ["chromium"], "flows": false}' "$T/cov/checks.yaml"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  result '.rows |= map(select(.check != "glyph_coverage" or .browser != "webkit"))'
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  result '.rows |= map(select(.check != "glyph_coverage" or .browser != "chromium" or .page != "index.html"))'
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing row: glyph_coverage index.html/390/chromium"* ]]
}

# P106 Step 1 — decide: the agent's own decision as one history line
decide_payload() {
  mkdir -p "$PROJ/.aid-ui/studio"
  # no steps[]: decide takes the six steps from sections.json
  echo '{"questions": [], "cards": []}' \
    > "$PROJ/.aid-ui/studio/payload.json"
  H="$PROJ/.aid-ui/studio/history.jsonl"
}

@test "P106 decide: appends one agent line, prints its at, matches --step by title and by id" {
  decide_payload
  run "$SCRIPT" decide "$PROJ" --step "Zadání a obsah" --title "Doba odpovědi" --outcome "odpovím do dvou pracovních dnů" \
    --why "PM řekl vyber ty" --source docs/content/facts.yaml
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]]
  [ "$(wc -l < "$H")" -eq 1 ]
  jq -e --arg at "$output" '.by == "agent" and .step == "Zadání a obsah" and .event.title == "Doba odpovědi"
    and .event.outcome == "odpovím do dvou pracovních dnů" and .event.why == "PM řekl vyber ty"
    and .event.source == "docs/content/facts.yaml" and .cards == [] and .answer.decision == "decided"
    and .answer.at == $at and (has("reconstructed") | not)' "$H" >/dev/null
  run "$SCRIPT" decide "$PROJ" --step s2 --title "Návštěva" --outcome "Jen po domluvě" --why "z webu"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.event.title == "Návštěva") | .step' "$H")" = "Zadání a obsah" ]
}

@test "P106 decide: refuses an unknown step, an empty field, 121 characters and --at without --reconstructed (exit 2)" {
  decide_payload
  run "$SCRIPT" decide "$PROJ" --step "Nope" --title t --outcome o --why w
  [ "$status" -eq 2 ]; [[ "$output" == *'"Nope"'* ]]
  run "$SCRIPT" decide "$PROJ" --step "zadání a obsah" --title t --outcome o --why w   # case differs: not normalised
  [ "$status" -eq 2 ]
  run "$SCRIPT" decide "$PROJ" --step s2 --title "  " --outcome o --why w
  [ "$status" -eq 2 ]; [[ "$output" == *"--title"* ]]
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome "$(printf 'ž%.0s' $(seq 1 121))" --why w
  [ "$status" -eq 2 ]; [[ "$output" == *"120"* ]]
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w --at 2026-09-28T18:05:00Z
  [ "$status" -eq 2 ]; [[ "$output" == *"--reconstructed"* ]]
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w --reconstructed --at "28. 9. 2026"
  [ "$status" -eq 2 ]
  [ ! -s "$H" ]
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome "$(printf 'ž%.0s' $(seq 1 120))" --why w
  [ "$status" -eq 0 ]
}

@test "P106 decide: the same step, title and outcome twice is one event; the second run prints the first at" {
  decide_payload
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w
  first="$output"
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why "jiný důvod"
  [ "$status" -eq 0 ]; [ "$output" = "$first" ]
  [ "$(wc -l < "$H")" -eq 1 ]
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome "jiný výsledek" --why w
  [ "$(wc -l < "$H")" -eq 2 ]
}

@test "P106 decide: --reconstructed --at stores that at and the mark" {
  decide_payload
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w --reconstructed --at 2026-09-28T18:05:00Z
  [ "$status" -eq 0 ]; [ "$output" = 2026-09-28T18:05:00Z ]
  jq -e '.answer.at == "2026-09-28T18:05:00Z" and .reconstructed == true' "$H" >/dev/null
}

@test "P106 decide: exit 1 without payload.json, and while another process holds the history lock" {
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w
  [ "$status" -eq 1 ]; [[ "$output" == *"not initialised"* ]]
  decide_payload
  touch "$H"
  flock -x "$H" sleep 15 3>&- &
  holder=$!
  sleep 0.3
  run "$SCRIPT" decide "$PROJ" --step s2 --title t --outcome o --why w
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 1 ]; [[ "$output" == *"locked"* ]]
  [ ! -s "$H" ]
}

# P103 extension K3 - project scope in the required matrix; the brand package waiver
@test "K3 checks.yaml applies scope: project needs one row (home, last viewport, first browser); viewports subset" {
  yq -i '.checks.brand_package = "pkg" | .applies.brand_package = {"scope": "project"} | .checks.ai_search = "ai" | .applies.ai_search = {"browsers": ["chromium"], "viewports": [1440]}' "$T/cov/checks.yaml"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  vl="$(yq -r '.viewports[-1]' "$T/cov/checks.yaml")"; b0="$(yq -r '.browsers[0]' "$T/cov/checks.yaml")"
  result ".rows |= map(select((.check != \"brand_package\" or (.page == \"index.html\" and .viewport == $vl and .browser == \"$b0\")) and (.check != \"ai_search\" or (.browser == \"chromium\" and .viewport == 1440))))"
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  result '.rows |= map(select(.check != "brand_package"))'
  run "$SCRIPT" gate-record "$PROJ" "$RES"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing row: brand_package index.html/$vl/$b0"* ]]
}

@test "K3 brand-waive: the target names exactly what is missing; the answer stores the waiver; an answer for another list does not fit" {
  jqw '.variant = {"type": "web", "brand": "existing"} | .options.identity = "package"'
  mkdir -p "$PROJ/docs/design/brand-package/icons"
  printf '## Kontexty použití\n1. Favicon.\n' >"$PROJ/docs/design/brief-logo-favicon.md"
  run "$SCRIPT" brand-waive-target "$PROJ"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  target="$output"
  jq -e '.check == "brand_package" and (.missing | length) > 5 and .missing == (.missing | sort)' <<<"$target" >/dev/null
  ans w1 exception "$target"
  run "$SCRIPT" brand-waive "$PROJ" --answer w1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e --argjson t "$target" '.brand_package_waiver.missing == $t.missing and .brand_package_waiver.answer == "w1" and (.consumed | index("w1"))' "$STATE" >/dev/null
  run python3 "$BATS_TEST_DIRNAME/../../aid-ui-brand-package.py" "$PROJ"
  [ "$status" -eq 0 ]; grep -q '^WAIVED ' <<<"$output"
  # an answer for another missing list does not fit
  ans w2 exception '{"check":"brand_package","missing":["icons: favicon.svg"]}'
  run "$SCRIPT" brand-waive "$PROJ" --answer w2
  [ "$status" -eq 1 ]; [[ "$output" == *"answer w2 is for"* ]]
}

@test "P108: context-check refuses no file, no approval and a changed file; passes the approved one" {
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"run step 1p"* ]]
  mkdir -p "$PROJ/docs/content"; printf '# Produkt\nStav: vyplněno\n' > "$PROJ/docs/content/product-context.md"
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"has not approved"* ]]
  # an approval of another kind or another file does not count
  ans q-other facts "docs/content/product-context.md@$(sha256sum "$PROJ/docs/content/product-context.md" | cut -d' ' -f1)"
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]
  ans q-ctx product_context "docs/content/product-context.md@$(sha256sum "$PROJ/docs/content/product-context.md" | cut -d' ' -f1)"
  # the online research must have been put to the PM - a no counts as much as a yes
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"online research"* ]]
  forge q-onl0 sources "online@$(basename "$PROJ")" reroll              # neither yes nor no does not count
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]
  ans q-online sources "online@$(basename "$PROJ")" return
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo "změna" >> "$PROJ/docs/content/product-context.md"
  run "$SCRIPT" context-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"changed since the PM approved"* ]]
}

@test "P108: chapter podklady exists in a page made before it and is approved by a product_context answer" {
  # an old brand page without the podklady section gets it on init, after produkt
  sed -i '/id="podklady"/d; /href="#podklady"/d' "$HTML"
  ! grep -q 'id="podklady"' "$HTML"
  "$SCRIPT" init "$PROJ" >/dev/null
  grep -q '<section id="podklady"' "$HTML"
  awk '/<section id="produkt"/{p=NR} /<section id="podklady"/{k=NR} END{exit !(p && k == p + 1)}' "$HTML"
  echo '<p>zdroje</p>' > "$T/pk.html"; "$SCRIPT" body "$PROJ" podklady --file "$T/pk.html" >/dev/null
  "$SCRIPT" chapter "$PROJ" podklady navrh >/dev/null
  # a design_standard answer (the old default kind) is refused, a product_context one approves
  run approve_chapter podklady design_standard q-pk1; [ "$status" -ne 0 ]
  approve_chapter podklady product_context q-pk2 >/dev/null
  [ "$(jq -r .chapters.podklady.status "$STATE")" = schvaleno ]
}

@test "P108: exception-covered prints a covered fail row with the PM's reason, not an uncovered one" {
  jq '.build = {id: "B1", fingerprints: {"index.html": "F1", "kontakt.html": "F2"}}
      | .exceptions = [{selector: {check:"axe", page:"index.html", viewport:"*", browser:"*", role:"*", state:"*"}, fingerprints: {"index.html":"F1"}, reason: "PM přijal"},
                       {selector: {check:"axe", page:"kontakt.html", viewport:"*", browser:"*", role:"*", state:"*"}, fingerprints: {"kontakt.html":"STARÝ"}, reason: "x"}]' \
     "$STATE" > "$T/s" && mv "$T/s" "$STATE"
  echo '{"rows":[{"check":"axe","page":"index.html","viewport":"390","browser":"chromium","role":"","state":"","status":"fail"},
                 {"check":"axe","page":"kontakt.html","viewport":"390","browser":"chromium","role":"","state":"","status":"fail"},
                 {"check":"seo","page":"index.html","viewport":"390","browser":"chromium","role":"","state":"","status":"fail"}]}' > "$T/res.json"
  run "$SCRIPT" exception-covered "$PROJ" "$T/res.json"
  [ "$status" -eq 0 ]; [ "$(wc -l <<<"$output")" -eq 1 ]
  jq -e '.row.check == "axe" and .row.page == "index.html" and .reason == "PM přijal"' <<<"$output" >/dev/null
}

@test "P108: exception-covered counts open rows like finish: blocking warn and not_covered yes, a warn_only warn no" {
  jq '.build = {id: "B1", fingerprints: {"index.html": "F1"}}
      | .exceptions = [{selector: {check:"*", page:"index.html", viewport:"*", browser:"*", role:"*", state:"*"}, fingerprints: {"index.html":"F1"}, reason: "r"}]' \
     "$STATE" > "$T/s" && mv "$T/s" "$STATE"
  mkdir -p "$T/g"; echo '{"warn_only":["glyph_coverage"]}' > "$T/g/checks.json"
  # the selector's check must match exactly, so give each row its own exception
  jq '.exceptions = [ ("axe","seo","glyph_coverage") as $c | {selector: {check:$c, page:"index.html", viewport:"*", browser:"*", role:"*", state:"*"}, fingerprints: {"index.html":"F1"}, reason: $c} ]' \
     "$STATE" > "$T/s" && mv "$T/s" "$STATE"
  echo '{"rows":[{"check":"axe","page":"index.html","viewport":"390","browser":"chromium","role":"","state":"","status":"warn"},
                 {"check":"seo","page":"index.html","viewport":"390","browser":"chromium","role":"","state":"","status":"not_covered"},
                 {"check":"glyph_coverage","page":"index.html","viewport":"390","browser":"chromium","role":"","state":"","status":"warn"}]}' > "$T/g/result.json"
  run "$SCRIPT" exception-covered "$PROJ" "$T/g/result.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .row.check <<<"$output" | sort | tr '\n' ' ')" = "axe seo " ] || { echo "$output"; return 1; }
}

@test "P108 method: prints the method files, writes the receipt; the live studio and payload-check refuse a question opened before it" {
  run "$SCRIPT" method "$PROJ" identity; [ "$status" -eq 0 ]
  n="$(jq '.methods.identity.files | length' "$BATS_TEST_DIRNAME/../../../skills/ui-design/sections.json")"; [ "$n" -ge 15 ]   # P113a + P113: the logo procedure and rubrics too
  [ "$(grep -c '^===== ' <<<"$output")" -eq "$n" ]
  grep -q '^===== skills/ui-design/references/adopted/logo-design/SKILL.md' <<<"$output"
  grep -q 'Phase 3 — Concepts' <<<"$output"                    # the text itself was printed, not just named
  R="$PROJ/.aid-ui/method/identity.json"
  [ "$(jq -r '.files | length' "$R")" -eq "$n" ]
  [ "$(jq -r '.files[0].sha256' "$R")" = "$(sha256sum "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/adopted/logo-design/SKILL.md" | cut -d' ' -f1)" ]
  run "$SCRIPT" method "$PROJ" nonsense; [ "$status" -eq 2 ]
  studio   # fresh receipts now
  jq '.questions += [{id:"i1",kind:"identity",target:"t",opened_at:"2020-01-01T00:00:00Z"}] | .cards += [{id:"x",question:"i1",method:"mark-types.md: letterform",slot:"W"}]' \
    "$PROJ/.aid-ui/studio/payload.json" > "$T/p.t" && mv "$T/p.t" "$PROJ/.aid-ui/studio/payload.json"
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"not from the 12 hours"* ]]
  run "$SCRIPT" record-answer "$PROJ" --question i1; [ "$status" -eq 1 ]; [[ "$output" == *"HTTP 422"* ]]   # the studio refuses the payload
  # opened at the receipt's own moment, never by the clock (P113: `now | todate` drops the milliseconds, so within the
  # same second the question opened "before" its receipt and the case failed on a fast machine)
  jq --arg at "$(jq -r .at "$PROJ/.aid-ui/method/identity.json")" '.questions[-1].opened_at = $at' "$PROJ/.aid-ui/studio/payload.json" > "$T/p.t" && mv "$T/p.t" "$PROJ/.aid-ui/studio/payload.json"
  run "$SCRIPT" payload-check "$PROJ"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "P108 method: a kind with null in the map refuses until the PM's no_method answer, then writes the waiver with its mode" {
  D="$T/plug"; mkdir -p "$D/scripts" "$D/skills/ui-design" "$D/lib/aid-ui-studio"
  cp "$SCRIPT" "$D/scripts/"; cp -r "$PAGE" "$D/skills/ui-design/brand-page"; cp "$BATS_TEST_DIRNAME/../../../lib/aid-ui-studio/server.py" "$D/lib/aid-ui-studio/"
  jq '.methods.vision = null' "$BATS_TEST_DIRNAME/../../../skills/ui-design/sections.json" > "$D/skills/ui-design/sections.json"
  run "$D/scripts/aid-ui-state.sh" method "$PROJ" vision; [ "$status" -eq 1 ]; [[ "$output" == *"no_method@vision"* ]]
  [ ! -e "$PROJ/.aid-ui/method/vision.json" ]
  forge w1 no_method no_method@vision choose                       # choose, but which card is not known
  run "$D/scripts/aid-ui-state.sh" method "$PROJ" vision; [ "$status" -eq 1 ]
  jqw '.answers.w1.choice = "a" | .answers.w1.cards = [{id:"a",value:"adopt"},{id:"c",value:"without"}]'
  run "$D/scripts/aid-ui-state.sh" method "$PROJ" vision; [ "$status" -eq 1 ]   # adopt: take the method over first
  jqw '.answers.w1.choice = "c"'
  run "$D/scripts/aid-ui-state.sh" method "$PROJ" vision; [ "$status" -eq 0 ]; [[ "$output" == *"waived by the PM's answer w1 (without)"* ]]
  [ "$(jq -r '.waived + " " + .mode + " " + (.files | length | tostring)' "$PROJ/.aid-ui/method/vision.json")" = "w1 without 0" ]
}

@test "P113a bod 8: a milestone answer is recorded with its items; each approved item is used once with --answer-item, a returned one never" {
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  studio
  it="$(jq -nc --arg a "index.html@$(fp index.html)" --arg b "kontakt.html@$(fp kontakt.html)" \
    '[{id: "index.html", title: "Úvod", target: $a}, {id: "kontakt.html", title: "Kontakt", target: $b}]')"
  sha="$(jq -cS '[.[] | {id, kind: "approve_page", target}] | sort_by(.id)' <<<"$it" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
  p="$PROJ/.aid-ui/studio/payload.json"
  jq --argjson it "$it" --arg t "items@$sha" --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
    '.questions += [{id: "m1", kind: "approve_page", target: $t, opened_at: $o, items: $it}]' "$p" > "$p.t" && mv "$p.t" "$p"
  curl -sf -o /dev/null -H "X-AID-Token: $STOKEN" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg t "items@$sha" '{question: "m1", kind: "approve_page", target: $t, decision: "return", items: {"kontakt.html": "telefón hore"}}')" "$AID_UI_STUDIO_URL/answer"
  run "$SCRIPT" record-answer "$PROJ" --question m1; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e --arg s "$sha" '.answers.m1 | .items_sha256 == $s and (.items | length) == 2' "$STATE" >/dev/null
  run "$SCRIPT" approve-page "$PROJ" index.html --answer m1; [ "$status" -eq 1 ]; [[ "$output" == *"--answer-item"* ]]
  run "$SCRIPT" approve-page "$PROJ" index.html --answer m1 --answer-item index.html; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.approvals["index.html"] | .answer == "m1" and .item == "index.html"' "$STATE" >/dev/null
  jq -e '.consumed | index("m1#index.html") != null and index("m1") == null' "$STATE" >/dev/null
  run "$SCRIPT" approve-page "$PROJ" index.html --answer m1 --answer-item index.html; [ "$status" -eq 1 ]; [[ "$output" == *"already used"* ]]
  run "$SCRIPT" approve-page "$PROJ" kontakt.html --answer m1 --answer-item kontakt.html; [ "$status" -eq 1 ]; [[ "$output" == *"decided return"* ]]
  run "$SCRIPT" approve-page "$PROJ" kontakt.html --answer m1 --answer-item index.html; [ "$status" -eq 1 ]; [[ "$output" == *"is for"* ]]
  run "$SCRIPT" approve-page "$PROJ" index.html --answer m1 --answer-item nic; [ "$status" -eq 1 ]; [[ "$output" == *"has no item nic"* ]]
  # a single answer takes no item
  ans a1 approve_page "kontakt.html@$(fp kontakt.html)"
  run "$SCRIPT" approve-page "$PROJ" kontakt.html --answer a1 --answer-item kontakt.html; [ "$status" -eq 1 ]; [[ "$output" == *"has no items"* ]]
  # a returned item turned into an approval in the state is refused against the studio (the decisions are compared, not only the sha)
  jq '.answers.m1.items[1].decision = "approve"' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  run "$SCRIPT" approve-page "$PROJ" kontakt.html --answer m1 --answer-item kontakt.html; [ "$status" -eq 1 ]; [[ "$output" == *"differs from the recorded one"* ]]
}

# ---------------------------------------------------------------- P113 step 2: the place verdict guards the decisions
@test "gates: decision without verdict - no verdict of the place refuses the accepting answer; a reroll passes" {
  jqw 'del(.place_verdicts.struktura)'
  NO_PLACE_OK=1 run ans s1 structure "sha256:abc"; [ "$status" -ne 0 ]; [[ "$output" == *"place_verdict_missing"* ]]
  jq -e '.answers.s1 == null' "$STATE" >/dev/null
  NO_PLACE_OK=1 run ans s2 structure "sha256:abc" reroll; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  NO_PLACE_OK=1 run ans s3 structure "sha256:abc" return; [ "$status" -eq 0 ]
}

@test "gates: decision without verdict - a verdict over an older target refuses (the structure changed after it)" {
  echo '{"pages": [{"slug": "nova"}]}' > "$PROJ/.aid-ui/structure.json"
  NO_PLACE_OK=1 run ans s1 structure "sha256:abc"; [ "$status" -ne 0 ]; [[ "$output" == *"decided over another bundle"* ]]
}

@test "gates: decision without verdict - an upstream file changed after its verdict refuses the places standing on it" {
  echo zmena >> "$PROJ/.aid-ui/logo/cards/a.png"
  studio; "$SCRIPT" method "$PROJ" direction >/dev/null
  NO_PLACE_OK=1 run ans d1 direction "smer:abc" choose; [ "$status" -ne 0 ]; [[ "$output" == *"logo changed after its verdict"* ]]
  run "$SCRIPT" build-record "$PROJ" "$SITE"; [ "$status" -ne 0 ]; [[ "$output" == *"logo changed after its verdict"* ]]
}

@test "gates: decision without verdict - a hand-made verdict is refused by place-record" {
  V="$PROJ/.aid-ui/critic/rounds/struktura/1/verdict.json"; [ -f "$V" ]
  run "$SCRIPT" place-record "$PROJ" --place struktura "$V"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }   # the real one records
  jq '.chosen = "jiny"' "$V" > "$T/v1.json"
  run "$SCRIPT" place-record "$PROJ" --place struktura "$T/v1.json"; [ "$status" -ne 0 ]; [[ "$output" == *"place_verdict_handmade"* ]]
  jq '.target = "0000"' "$V" > "$T/v2.json"
  run "$SCRIPT" place-record "$PROJ" --place struktura "$T/v2.json"; [ "$status" -ne 0 ]; [[ "$output" == *"older bundle"* ]]
  # a returned place made "accepted" by hand
  jq '.findings = [{"id":"x","criterion":"ukoly_zakaznika","severity":"major","owner":"agent","kind":"fakt","text":"vymyšlená služba","fix":"smazat","where":"strom"}]' \
    "$PROJ/.aid-ui/critic/rounds/struktura/1/tech/answer.json" > "$T/a.json" && mv "$T/a.json" "$PROJ/.aid-ui/critic/rounds/struktura/1/tech/answer.json"
  run "$SCRIPT" place-record "$PROJ" --place struktura "$V"; [ "$status" -ne 0 ]; [[ "$output" == *"place_verdict_handmade"* ]]
}

@test "gates: decision without verdict - build-record without the motion verdict refuses" {
  jqw 'del(.place_verdicts.pohyb)'
  run "$SCRIPT" build-record "$PROJ" "$SITE"; [ "$status" -ne 0 ]; [[ "$output" == *"place_verdict_missing"* ]]; [[ "$output" == *"pohyb"* ]]
  jq -e '.build == null or .build.id == null' "$STATE" >/dev/null
}

@test "gates: without - the PM's exception answer for pohyb@without lets build-record and the later places pass" {
  jqw 'del(.place_verdicts.pohyb)'; rm -rf "$PROJ/.aid-ui/motion"
  ans m1 exception "pohyb@without"
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without m1; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.place_verdicts.pohyb.without == "m1" and .place_verdicts.pohyb.status == "accepted" and (.consumed | index("m1")) != null' "$STATE" >/dev/null
  [ -f "$PROJ/.aid-ui/critic/pohyb-without.json" ]
  run "$SCRIPT" build-record "$PROJ" "$SITE"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  place_ok "$PROJ" vzhled   # the look is decided over the without record
  "$SCRIPT" method "$PROJ" direction >/dev/null
  NO_PLACE_OK=1 run ans d1 direction "smer:abc" choose; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "gates: without - a bare flag or an unknown answer is refused" {
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without; [ "$status" -ne 0 ]
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without nope; [ "$status" -ne 0 ]; [[ "$output" == *"not one"* ]]
  ans x1 exception '{"check":"motion_settled","page":"*","viewport":"*","browser":"*","role":"*","state":"*"}'
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without x1; [ "$status" -ne 0 ]   # another exception
  run "$SCRIPT" place-record "$PROJ" --place logo --without x1; [ "$status" -eq 2 ]
}

@test "gates: without - an answer the client agent gave is refused" {
  studio
  local p="$PROJ/.aid-ui/studio/payload.json"
  jq --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" '.questions += [{id: "c1", kind: "exception", target: "pohyb@without", opened_at: $o}] | .cards += [{id: "x", question: "c1", method: "SKILL.md"}]' "$p" > "$p.t" && mv "$p.t" "$p"
  curl -sf -o /dev/null -H "X-AID-Token: $STOKEN" -H "X-AID-Role: client" -H 'Content-Type: application/json' \
    -d '{"question":"c1","kind":"exception","target":"pohyb@without","decision":"approve","comment":"klient"}' "$AID_UI_STUDIO_URL/answer"
  "$SCRIPT" record-answer "$PROJ" --question c1 >/dev/null
  jq -e '.answers.c1.by == "client"' "$STATE" >/dev/null
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without c1; [ "$status" -ne 0 ]; [[ "$output" == *"by pm"* ]]
  # the agent token without the role header is an agent's answer, never the PM's (positive attribution)
  jq --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" '.questions += [{id: "c2", kind: "exception", target: "pohyb@without", opened_at: $o}] | .cards += [{id: "x", question: "c2", method: "SKILL.md"}]' "$p" > "$p.t" && mv "$p.t" "$p"
  curl -sf -o /dev/null -H "X-AID-Token: $STOKEN" -H 'Content-Type: application/json' \
    -d '{"question":"c2","kind":"exception","target":"pohyb@without","decision":"approve","comment":"agent"}' "$AID_UI_STUDIO_URL/answer"
  "$SCRIPT" record-answer "$PROJ" --question c2 >/dev/null
  jq -e '.answers.c2.by == "agent"' "$STATE" >/dev/null
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without c2; [ "$status" -ne 0 ]
}

@test "gates: without - a return decision is refused" {
  ans r1 exception "pohyb@without" return
  run "$SCRIPT" place-record "$PROJ" --place pohyb --without r1; [ "$status" -ne 0 ]; [[ "$output" == *"not one"* ]]
}
