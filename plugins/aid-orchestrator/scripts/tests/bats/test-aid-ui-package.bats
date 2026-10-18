#!/usr/bin/env bats
# aid-tier: t1
# aid-ui-package.py — P115: the handover package between the studio and plan/run (docs/ui/predani.json).
# package:  the handover writes it, an incomplete or stale one refuses the handover and leaves the answer unused.
# Real studio and answers through the helpers of test-aid-ui-state.bats (aid-ui-state-helpers.bash); no model.

load aid-ui-places
setup_file() { places_template; }
load aid-ui-state-helpers

setup() {
  state_setup
  PKG="$BATS_TEST_DIRNAME/../../aid-ui-package.py"
  FIXP="$BATS_TEST_DIRNAME/../fixtures/aid-ui/package"
  OUTP="$PROJ/docs/ui/predani.json"
  mkdir -p "$PROJ/docs/content"
  printf -- '- {id: hours, task: "Kdy máte otevřeno", expect: ["7:00"]}\n- {id: booking, task: "Objednej se", form: true}\n' > "$PROJ/docs/content/tasks.yaml"
}
teardown() { state_teardown; }

# handed_over — a recorded gate, two chapters and the PM's handover answer h1 (not yet used)
handed_over() {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
}

@test "package: the handover writes predani.json and predani.md; the package passes check, also against the project" {
  handed_over
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ] && [ -f "$PROJ/docs/ui/predani.md" ]
  [ "$(jq -r .version "$OUTP")" = 1 ]
  [ "$(jq -r '[.chapters[].id] | join(",")' "$OUTP")" = "vize,barvy" ]
  [ "$(jq -r '[.customer_tasks[].id] | join(",")' "$OUTP")" = "hours,booking" ]
  [ "$(jq -r .site.build_id "$OUTP")" = "$(jq -r .build.id "$STATE")" ]
  [ "$(jq '.site.files | length' "$OUTP")" = "$(find "$SITE" -type f | wc -l)" ]
  run python3 "$PKG" check "$OUTP" --project "$PROJ"
  [ "$status" -eq 0 ]
  run python3 "$PKG" check "$FIXP/docs/ui/predani.json"
  [ "$status" -eq 0 ]
  # a file list that lies (one entry dropped, or a path out of the site) fails, though build id and dirsha match
  jq '.site.files |= .[1:]' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json" --project "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"soubory nejsou ty z balíku"* ]]
  jq '.site.files[0].path = "../etc/passwd"' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"nebezpečná"* ]]
}

@test "package: no recorded gate refuses the package naming the gate" {
  "$SCRIPT" chapter "$PROJ" vize navrh
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: chybí brána"* ]]
  [ ! -e "$OUTP" ]
}

@test "package: a site changed after the gate is stale; a package missing a part fails check naming it" {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: zastaralý"* ]]
  jq 'del(.gate)' "$FIXP/docs/ui/predani.json" > "$T/bad.json"
  run python3 "$PKG" check "$T/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'gate' is a required property"* ]]
}

@test "package: a refused package leaves the handover answer unused and the state unchanged; fixed, the same answer hands over" {
  handed_over
  cp "$SITE/kontakt.html" "$T/kontakt.orig"
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  before="$(sha256sum "$HTML" "$STATE")"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"answer h1 not used"* ]]
  [[ "$output" == *"zastaralý"* ]]
  [ "$(sha256sum "$HTML" "$STATE")" = "$before" ]
  [ ! -e "$OUTP" ]
  cp "$T/kontakt.orig" "$SITE/kontakt.html"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ]
}

@test "package: a standalone build after a recorded handover rewrites the package; before a handover it is refused" {
  handed_over
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chybí převzetí"* ]]
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  want="$(jq -c 'del(.created_at)' "$OUTP")"
  rm -f "$OUTP" "$PROJ/docs/ui/predani.md"
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'del(.created_at)' "$OUTP")" = "$want" ]
  [ -f "$PROJ/docs/ui/predani.md" ]
}

# fixture_project — the fixture package's project copied to $FX with an execution.yaml defining check_ui_handover in every profile
fixture_project() {
  FX="$T/fx"; mkdir -p "$FX"; cp -r "$FIXP/." "$FX/"
  mkdir -p "$FX/.aid-o/config" "$FX/.aid-o/work/plan-state"
  printf 'gates:\n  check_ui_handover:\n    command: "bash x"\ngate_profiles:\n  standard:\n    include: [tests_pass, check_ui_handover]\n  release:\n    include: [check_ui_handover]\n' > "$FX/.aid-o/config/execution.yaml"
}
# plan_from_brief <brief> <plan> [drop] — a minimal strict plan carrying the brief's points; drop = without ui_package
plan_from_brief() {
  local b="$1" p="$2" n
  n="$(grep -c '^- \[ \] AC[0-9]*:' "$b")"
  { echo "---"; echo "id: P001"; echo "type: regular"; echo "lifecycle_strict: true"
    echo "zadani: ${b#"$FX/"}"; echo "zadani_verze: 1"; echo "zadani_sha256: $(sha256sum "$b" | cut -d' ' -f1)"
    [[ "${3:-}" == drop ]] || grep -E '^ui_package(_sha256)?:' "$b"
    echo "---"; echo; echo "# Plan: P001"; echo; echo "### Step 1: deploy"; echo
    echo "**Zavírá:** $(seq -s, 1 "$n" | sed 's/\([0-9]*\)/AC\1/g; s/,/, /g')"; echo
    echo "## Acceptance Criteria"; echo; sed -n '/^## 6\. Hotovo, když/,$p' "$b" | tail -n +2; } > "$p"
}

@test "package-zadani: the brief from the package passes the lint, one point per task, launch item, open item and the rating" {
  fixture_project
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  B="$FX/.aid-o/plans/P001-zadani.md"
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" --zadani "$B"
  [ "$status" -eq 0 ]
  rows="$(grep -E '^\| [a-z_0-9]+ \| ' "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/local/spusteni.md" | grep -vc '^| id |')"
  tasks="$(jq '.customer_tasks | length' "$FX/docs/ui/predani.json")"
  ois="$(jq '.open_items | length' "$FX/docs/ui/predani.json")"
  inputs="$(jq '[.launch_inputs[] | select(.item == null)] | length' "$FX/docs/ui/predani.json")"
  # the launch checklist, named here and not read from the table (a row dropped from both would pass otherwise)
  [ "$(grep -E '^\| [a-z_0-9]+ \| ' "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/local/spusteni.md" | grep -v '^| id |' | cut -d'|' -f2 | tr -d ' ' | paste -sd,)" = \
    "nasadit_balik,https,hlavicky,stranka_404,citlive_soubory,dns,email,katalogy,presmerovani,hodnoceni" ]
  for w in "Nasadit přesně soubory" "na HTTPS" "Bezpečnostní hlavičky" "stavem 404" "Citlivé a vývojové" "Doména webu se překládá" "E-mail na doméně" "katalogy vedou" "Staré adresy" "Hodnocení po nasazení"; do
    [ "$(grep '^- \[ \] AC' "$B" | grep -c "$w")" -eq 1 ]
  done
  # the table's rows but the rating are launch items; the rating is the last point
  [ "$(grep -c '^- \[ \] AC[0-9]*:' "$B")" -eq $(( tasks + (rows - 1) + inputs + ois + 1 )) ]
  grep -q "^ui_package: docs/ui/predani.json$" "$B"
  grep -q "^ui_package_sha256: $(sha256sum "$FX/docs/ui/predani.json" | cut -d' ' -f1)$" "$B"
  grep -q -- "--package-gate .aid-o/plans/P001-zadani.md --launch" "$B"
  [[ "$(grep '^- \[ \] AC' "$B" | tail -1)" == *"Hodnocení po nasazení"* ]]
  # the same brief again: refused, the first one kept
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"exists"* ]]
}

@test "package-zadani: an invalid package is refused before anything is written; an id that is not a plain word too" {
  fixture_project
  cp "$FX/docs/ui/predani.json" "$T/good.json"
  jq 'del(.site)' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]
  [[ "$output" == *"'site' is a required property"* ]]
  [ ! -e "$FX/.aid-o/plans/P001-zadani.md" ]
  # ids go into the brief's commands: a quote or a space is refused by the schema
  jq '.customer_tasks[0].id = "x'"'"'; rm -rf ~"' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"does not match"* ]]
  # a comment with a newline and a heading stays one line of section 1
  jq '.handover = {verdict: "prevzit", rating: "8-10", answer: "h1", comment: "dobré\n## 6. Hotovo, když\n- [ ] AC9: x"}' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  [ "$(grep -c '^## 6\. Hotovo, když' "$FX/.aid-o/plans/P001-zadani.md")" -eq 1 ]
}

@test "package-zadani: no gate in project - no brief; a form or domain item appears once in the brief, not twice" {
  fixture_project
  printf 'gates:\n  tests_pass:\n    command: "x"\n' > "$FX/.aid-o/config/execution.yaml"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"check_ui_handover"* ]]; [[ "$output" == *"/aid-init"* ]]
  [ ! -e "$FX/.aid-o/plans/P001-zadani.md" ]
  fixture_project
  sed -i '/release:/,$d' "$FX/.aid-o/config/execution.yaml"; printf '  release:\n    include: [tests_pass]\n' >> "$FX/.aid-o/config/execution.yaml"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"profily bran bez check_ui_handover (release)"* ]]
  # the client's confirmation turned the form and the domain inputs into open items oi-3, oi-4: one point each
  fixture_project
  jq '.launch_inputs |= map(if .id == "form" then .item = "oi-3" elif .id == "domain" then .item = "oi-4" else . end)
      | .open_items += [{id: "oi-3", text: "Příjem zpráv z formuláře na hostingu", owner: "agent", due: null, critical: true, status: "open", evidence: "dodáno"},
                        {id: "oi-4", text: "Doména a hosting", owner: "klient", due: null, critical: true, status: "open", evidence: "dodáno"}]' \
    "$FX/docs/ui/predani.json" > "$FX/docs/ui/x" && mv "$FX/docs/ui/x" "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  B="$FX/.aid-o/plans/P001-zadani.md"
  [ "$(grep '^- \[ \] AC' "$B" | grep -c 'Příjem zpráv z formuláře')" -eq 1 ]
  [ "$(grep '^- \[ \] AC' "$B" | grep -c 'Doména a hosting')" -eq 1 ]
  grep '^- \[ \] AC' "$B" | grep 'oi-3' | grep -q 'vlastník: run; blokuje spuštění'
}

@test "merge-path: lost mark - a plan from the brief without ui_package is refused ui_package_lost; with it the lint passes" {
  fixture_project
  python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001 >/dev/null
  plan_from_brief "$FX/.aid-o/plans/P001-zadani.md" "$FX/.aid-o/plans/P001-plan.md"
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" "$FX/.aid-o/plans/P001-plan.md" --only zadani
  [ "$status" -eq 0 ]
  plan_from_brief "$FX/.aid-o/plans/P001-zadani.md" "$FX/.aid-o/plans/P001-plan.md" drop
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" "$FX/.aid-o/plans/P001-plan.md" --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"ui_package_lost"* ]]
}

# ── ui-gate: the run gate check_ui_handover (aid-ui-verify.sh --package-gate) ─────────────────────────────────
# deployed — a handed-over project without the studio server: build, gate and handover recorded by hand where they
# need no PM, the package built, the project a git repo with plan P001 from the package, the web copied to $LIVE and
# served by a small server (POST answers $FORM_STATUS, default 200), docs/ui/nasazeni.json written; the studio's rows
# over the live address are a stub (AID_UI_TOOL) that passes, so no browser runs on the merge path
deployed() {
  echo '<html><form action="/odeslat" method="post"><input name="jmeno"><input type="email" name="mail"><button>Odeslat</button></form></html>' > "$SITE/kontakt.html"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  result; "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null
  end_order
  "$SCRIPT" chapter "$PROJ" vize navrh
  jqw '.chapters.vize.status = "schvaleno" | .handover = {verdict: "prevzit", rating: "8-10", answer: "h1"}'
  python3 "$PKG" build "$PROJ" >/dev/null
  git -C "$PROJ" init -q
  PLAN="$PROJ/.aid-o/plans/P001-plan.md"; mkdir -p "${PLAN%/*}"
  printf -- '---\nid: P001\nui_package: docs/ui/predani.json\nui_package_sha256: %s\n---\n# Plan\n' "$(sha256sum "$OUTP" | cut -d' ' -f1)" > "$PLAN"
  LIVE="$T/live"; mkdir -p "$LIVE"; cp -r "$SITE/." "$LIVE/"
  cat > "$T/srv.py" <<'PY'
import http.server, os, sys
class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.send_response(int(os.environ.get("FORM_STATUS", "200"))); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), lambda *a: H(*a, directory=sys.argv[2])).serve_forever()
PY
  local port; port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  FORM_STATUS="${FORM_STATUS:-200}" python3 "$T/srv.py" "$port" "$LIVE" 3>&- & SPID=$!
  LIVE_URL="http://127.0.0.1:$port"
  local i; for i in $(seq 1 50); do curl -sf -o /dev/null "$LIVE_URL/index.html" && break; sleep 0.1; done
  jq -n --arg u "$LIVE_URL" --arg r "$LIVE" '{url: $u, listing: {type: "local", root: $r}}' > "$PROJ/docs/ui/nasazeni.json"
  printf '#!/usr/bin/env bash\nwhile (( $# )); do [[ "$1" == --out ]] && o="$2"; shift; done\necho %s > "$o/result.json"\n' \
    "'{\"rows\":[{\"check\":\"task_test\",\"status\":\"pass\",\"detail\":\"hours 1440: index.html (0); hours 390: index.html (0)\"}]}'" > "$T/tool.sh"
  export AID_UI_TOOL="$T/tool.sh"
}
GATE_SH() { run bash "$BATS_TEST_DIRNAME/../../aid-ui-verify.sh" --package-gate "$@"; }

@test "ui-gate: a plan without ui_package is skipped with the reason; a plan from a package without the package fails" {
  mkdir -p "$PROJ/.aid-o/plans"; git -C "$PROJ" init -q
  printf -- '---\nid: P002\n---\n# Plan\n' > "$PROJ/.aid-o/plans/P002-plan.md"
  GATE_SH "$PROJ/.aid-o/plans/P002-plan.md"
  [ "$status" -eq 0 ]; [[ "$output" == *"přeskočeno: bez balíku"* ]]
  GATE_SH null
  [ "$status" -eq 0 ]; [[ "$output" == *"přeskočeno: bez plánu"* ]]
  printf -- '---\nid: P003\nui_package: docs/ui/predani.json\nui_package_sha256: abc\n---\n' > "$PROJ/.aid-o/plans/P003-plan.md"
  GATE_SH "$PROJ/.aid-o/plans/P003-plan.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"balík docs/ui/predani.json chybí"* ]]
}

@test "ui-gate: clean passes - the deployed files are the package's, the form is accepted, the live rows pass" {
  deployed
  GATE_SH "$PLAN" --launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"souborů shodných s balíkem"* ]]
  [[ "$output" == *"form_live: 1 formulářů"* ]]
  [[ "$output" == *"PASS"* ]]
  [ "$(jq -r .url "$PROJ/.aid-ui/verify-live/live.json")" = "$LIVE_URL" ]
  # the brief's task point reads that live result
  (cd "$PROJ" && python3 "$PKG" live-row docs/ui/predani.json task_test --detail 'hours 1440:' --detail 'hours 390:')
}

@test "ui-gate: before the deployment the gate checks the package and says so; --launch without nasazeni.json fails" {
  deployed
  rm "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"
  [ "$status" -eq 0 ]; [[ "$output" == *"před nasazením"* ]]
  GATE_SH "$PLAN" --launch
  [ "$status" -eq 1 ]; [[ "$output" == *"--launch bez docs/ui/nasazeni.json"* ]]
}

@test "ui-gate: a stale package (site changed after the handover) fails; a package edited after the handover fails" {
  deployed
  cp "$OUTP" "$T/pkg.orig"
  jq '.created_at = "2026-01-01T00:00:00Z"' "$T/pkg.orig" > "$OUTP"
  GATE_SH "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"se změnil od zadání"* ]]
  cp "$T/pkg.orig" "$OUTP"
  echo '<html>jiný</html>' > "$SITE/index.html"
  GATE_SH "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"zastaralý"* ]]
}

@test "ui-gate: nasazeni.json with url but no listing, or listing but no url, is refused; a host with a shell metacharacter too" {
  deployed
  jq 'del(.listing)' "$PROJ/docs/ui/nasazeni.json" > "$T/n" && cp "$T/n" "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"potřebuje url i listing"* ]]
  jq -n --arg r "$LIVE" '{listing: {type: "local", root: $r}}' > "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"potřebuje url i listing"* ]]
  jq -n --arg u "$LIVE_URL" '{url: $u, listing: {type: "ssh", host: "web;touch /tmp/x", root: "/www"}}' > "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"listing.host"*"odmítnut"* ]]
  # a root that is not absolute (-delete would be an expression of the remote find) is refused before any call
  jq -n --arg u "$LIVE_URL" '{url: $u, listing: {type: "ssh", host: "web", root: "-delete"}}' > "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"listing.root"*"odmítnut"* ]]
}

@test "ui-gate: a swapped file on the live address fails naming it; an extra file on the hosting fails; a missing listing root fails nelze ověřit" {
  deployed
  echo 'body{color:red}' > "$LIVE/style.css"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"jiný soubor než v balíku: style.css"* ]]
  cp "$SITE/style.css" "$LIVE/style.css"; echo 'x' > "$LIVE/stary.html"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"navíc ['stary.html']"* ]]
  rm "$LIVE/stary.html"
  jq --arg r "$T/nikde" '.listing.root = $r' "$PROJ/docs/ui/nasazeni.json" > "$T/n" && cp "$T/n" "$PROJ/docs/ui/nasazeni.json"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"nelze ověřit"* ]]
}

@test "ui-gate: the live form answering 500 fails though the files are the package's" {
  FORM_STATUS=500 deployed
  GATE_SH "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"form_live"*"odpověděl 500"* ]]
}

@test "ui-gate: an open critical item fails; done with evidence the gate passes" {
  deployed
  "$SCRIPT" open-item "$PROJ" add --text "IČO do patičky" --owner klient --critical --evidence "IČO v patičce" >/dev/null
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"otevřený kritický bod: oi-1"* ]]
  # done without evidence (a hand edit of the state) still blocks
  jqw '.open_items[0].status = "done"'
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"otevřený kritický bod: oi-1"* ]]
  "$SCRIPT" open-item "$PROJ" done oi-1 --evidence "IČO 12345678 v patičce" >/dev/null
  GATE_SH "$PLAN"; [ "$status" -eq 0 ]
}

@test "ui-gate: a critical item of the package deleted from the live state fails" {
  "$SCRIPT" open-item "$PROJ" add --text "Právní texty" --owner klient --critical --evidence "texty od právníka" >/dev/null
  deployed
  jq -e '.open_items[0].critical' "$OUTP" >/dev/null
  jqw '.open_items = []'
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"kritický bod z balíku chybí ve stavu studia: oi-1"* ]]
  # un-marked in the state: the package still holds it critical
  "$SCRIPT" open-item "$PROJ" add --text "Právní texty" --owner klient >/dev/null
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"otevřený kritický bod: oi-1"* ]]
}

@test "ui-gate: a symlink on the hosting is an entry the package does not have" {
  deployed
  ln -s /etc/hostname "$LIVE/odkaz"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"navíc ['odkaz']"* ]]
}

@test "ui-gate: a form posting to another site is not posted by the gate and is named as not verified" {
  echo '<html><form action="https://formspree.example/f/abc" method="post"><input name="m"></form></html>' > "$SITE/index.html"
  deployed
  GATE_SH "$PLAN"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"neověřeno (odesílá mimo web): index.html -> formspree.example"* ]]
}

@test "ui-gate: the live rows failing fail the gate" {
  deployed
  printf '#!/usr/bin/env bash\nwhile (( $# )); do [[ "$1" == --out ]] && o="$2"; shift; done\necho %s > "$o/result.json"\n' \
    "'{\"rows\":[{\"check\":\"http_200\",\"status\":\"fail\",\"page\":\"index.html\",\"viewport\":\"390\",\"detail\":\"500\"}]}'" > "$T/tool.sh"
  GATE_SH "$PLAN"; [ "$status" -eq 1 ]; [[ "$output" == *"kontrola UI nad ostrou adresou neprošla"* ]]
}

@test "ui-gate: upgraded project has the check_ui_handover definition and every profile names it; a fresh composition too" {
  E="$T/e.yaml"
  printf 'gates:\n  py_test:\n    command: "pytest"\n    required: true\ndefault_profile: standard\ngate_profiles:\n  targeted:\n    include: [py_test]\n  standard:\n    include:\n      - py_test\n' > "$E"
  L="$BATS_TEST_DIRNAME/../../lib/aid-init-execution-yaml.sh"
  h="$(bash "$L" upgrade "$E" | sed -n 's/^diff_hash: //p')"
  bash "$L" upgrade "$E" --confirm-upgrade "$h" >/dev/null
  [ "$(yq '.gates.check_ui_handover.command' "$E")" = 'bash {plugin_path}/scripts/aid-ui-verify.sh --package-gate {plan_path}' ]
  [ "$(yq -o=json -I0 '[.gate_profiles[].include | any_c(. == "check_ui_handover")] | all' "$E")" = true ]
  run bash "$L" upgrade "$E"; [[ "$output" == *"nothing to upgrade"* ]]
  # a commented flow include keeps its comment; a flow-style or empty gates: is refused, not guessed
  printf 'gates:\n  a:\n    command: "x"\ngate_profiles:\n  standard:\n    include: [a]   # rank 1\n' > "$T/f.yaml"
  h="$(bash "$L" upgrade "$T/f.yaml" | sed -n 's/^diff_hash: //p')"; bash "$L" upgrade "$T/f.yaml" --confirm-upgrade "$h" >/dev/null
  grep -q 'include: \[a, check_ui_handover\]  # rank 1' "$T/f.yaml"
  printf 'gates: {}\ngate_profiles:\n  standard:\n    include: [a]\n' > "$T/g.yaml"
  run bash "$L" upgrade "$T/g.yaml"; [ "$status" -eq 2 ]; [[ "$output" == *"add gates.check_ui_handover by hand"* ]]
  bash -c "source '$L'; compose_execution_yaml '$T' '$T/c.yaml' python" >/dev/null
  [ "$(yq '.gates | has("check_ui_handover")' "$T/c.yaml")" = true ]
  [ "$(yq -o=json -I0 '[.gate_profiles[].include | any_c(. == "check_ui_handover")] | all' "$T/c.yaml")" = true ]
}

@test "merge-path: stale launch verdict - the brief's rating point refuses a verdict of another address or another web" {
  Q="$BATS_TEST_DIRNAME/../../aid-ui-quality.py"; L="$PROJ/.aid-ui/critic/launch"; mkdir -p "$L" "$PROJ/docs/ui"
  sha="$(printf a%.0s {1..64})"
  echo "{\"site\": {\"sha256\": \"$sha\"}}" > "$PROJ/docs/ui/predani.json"
  echo '{"url": "https://web.example/"}' > "$PROJ/docs/ui/nasazeni.json"
  echo "{\"url\": \"https://web.example\", \"site_sha256\": \"$sha\", \"accepted\": true, \"owner\": 9, \"tech\": 9}" > "$L/launch-verdict.json"
  run python3 "$Q" launch-status "$PROJ" --package "$PROJ/docs/ui/predani.json"; [ "$status" -eq 0 ]
  echo '{"url": "https://jinde.example/"}' > "$PROJ/docs/ui/nasazeni.json"
  run python3 "$Q" launch-status "$PROJ" --package "$PROJ/docs/ui/predani.json"; [ "$status" -eq 1 ]
  echo '{"url": "https://web.example/"}' > "$PROJ/docs/ui/nasazeni.json"
  echo "{\"site\": {\"sha256\": \"$(printf b%.0s {1..64})\"}}" > "$PROJ/docs/ui/predani.json"
  run python3 "$Q" launch-status "$PROJ" --package "$PROJ/docs/ui/predani.json"; [ "$status" -eq 1 ]
  jq '.accepted = false' "$L/launch-verdict.json" > "$L/x" && mv "$L/x" "$L/launch-verdict.json"
  run python3 "$Q" launch-status "$PROJ"; [ "$status" -eq 1 ]
}
