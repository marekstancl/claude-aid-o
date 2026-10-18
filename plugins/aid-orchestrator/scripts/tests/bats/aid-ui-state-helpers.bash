# aid-ui-state.sh test helpers (moved out of test-aid-ui-state.bats for P115, so the handover package suite
# uses the same real studio, answers and gate): state_setup / state_teardown, studio, ans, forge, result, ready,
# gate_ready, end_order, serve_200. Needs `load aid-ui-places` and `setup_file() { places_template; }` first.
state_setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-state.sh"
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/coverage"
  T="$BATS_TEST_TMPDIR"
  PROJ="$T/proj"
  mkdir -p "$PROJ/docs/brand"
  cp "$PAGE/index.html" "$PROJ/docs/brand/"
  "$SCRIPT" init "$PROJ" >/dev/null
  places_copy "$PROJ"   # P113: the place verdicts a build and the place questions stand on
  # P115: the launch inputs the type web-local asks after the brief (the handover package refuses without them)
  echo '{"type": "web-local", "items": [{"id": "domain", "name": "Doména a hosting", "status": "client", "critical": true}], "used_answers": []}' > "$PROJ/.aid-ui/launch.json"
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

state_teardown() {
  [[ -z "${LINK_PID:-}" ]] || kill "$LINK_PID" 2>/dev/null || true
  [[ -z "${CUST_PID:-}" ]] || kill "$CUST_PID" 2>/dev/null || true
  [[ -z "${SPID:-}" ]] || kill "$SPID" 2>/dev/null || true
  [[ -z "${STUDIO_PID:-}" ]] || kill "$STUDIO_PID" 2>/dev/null || true
  [[ ! -f "$T/studio.pids" ]] || while read -r p; do kill "$p" 2>/dev/null || true; done < "$T/studio.pids"
  # P113: a studio a command started through aid-ui-serve.sh - only this case's project (the pointer names it)
  AID_UI_PROJECT="$PROJ" bash "$BATS_TEST_DIRNAME/../../aid-ui-serve.sh" stop studio >/dev/null 2>&1 || true
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
  echo "$STUDIO_PID" >> "$T/studio.pids"   # P113: `run ans` starts it in a subshell, whose STUDIO_PID teardown never sees
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
