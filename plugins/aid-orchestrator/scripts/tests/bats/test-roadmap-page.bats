#!/usr/bin/env bats
# aid-tier: t2
# Moved from t1 for the T1 budget (1. 11. 2026, 6.2 s): returns to t1 once the core is faster (IMP-711).
# aid-subject: scripts/aid-roadmap-page.sh
# The progress page of a roadmap (AID 3.14.0, PM 30. 10. 2026: every roadmap has one, every plan and /aid-do on the
# same thing refreshes it). Defects it catches: a page nobody refreshes, a page claiming somebody else's change, data
# that leaks markup into the page, a path out of the project or through a link, a copied page line taking over another
# roadmap's page, a failed publish counted as done, a later plan's refresh hiding an earlier plan's.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  RP="$AID_PLUGIN_PATH/scripts/aid-roadmap-page.sh"; PY="$AID_PLUGIN_PATH/scripts/lib/aid_roadmap_page.py"
  export AID_PM_PAGE_PUBLISHER="" AID_PM_PAGE_PUBLISHER_SUBCOMMAND="" AID_PM_PAGES=""
  R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R/docs/plans" "$R/.aid-o/work"; git -C "$R" init -q
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  DOC=docs/plans/2026-11-01-x-roadmapa.md; printf '# Roadmapa X\n\ntext\n' > "$R/$DOC"
  DATA="$R/docs/plans/2026-11-01-x-roadmapa.prubeh.json"
}
_rp() { (cd "$R" && bash "$RP" "$@"); }
_data() { jq "$1" "$DATA" > "$DATA.t" && mv "$DATA.t" "$DATA"; }
_hist() { cat "$R"/.aid-o/work/roadmap-pages/*/history.jsonl; }
# a publisher that answers with a link (or fails with FAIL=1), as the share does
_publisher() {
  cat > "$BATS_TEST_TMPDIR/pub" <<'P'
#!/usr/bin/env bash
[[ -n "${FAIL:-}" ]] && { echo "share is down" >&2; exit 3; }
cat > "$BATS_TEST_TMPDIR/published.html"; echo "https://share.example/p/x#k=secret"
P
  chmod +x "$BATS_TEST_TMPDIR/pub"; export AID_PM_PAGE_PUBLISHER="$BATS_TEST_TMPDIR/pub" BATS_TEST_TMPDIR
}

@test "init writes the page line and the data once; publish records the plan's change; data text is escaped on the page" {
  run _rp init "$DOC" --title "X kde jsme"; echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == "local "* ]]
  local id; id="$(grep -oE 'id=[a-z0-9-]+' "$R/$DOC" | cut -d= -f2)"; [[ "$id" =~ ^x-roadmapa-[0-9a-f]{8}$ ]]
  [ "$(sed -n 2p "$R/$DOC")" = "<!-- aid-roadmap-page: id=${id} -->" ]
  local before; before="$(sha256sum "$R/$DOC" "$DATA")"
  run _rp init "$DOC" --title "jiný"; [ "$status" -eq 0 ]; [[ "$output" == "kept ${id}"* ]]; [ "$(sha256sum "$R/$DOC" "$DATA")" = "$before" ]
  _data '.posledni_zmena = {kdo: "P900", co: "<script>alert(1)</script>"} | .chybi = [{co: "<img src=x onerror=1>", od_koho: "jednatel", od_kdy: "1. 11."}]'
  run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -eq 0 ]
  local page="$R/.aid-o/work/roadmap-pages/${id}/page.html"
  ! grep -q '<script>alert' "$page"; ! grep -q '<img src=x' "$page"; grep -q '&lt;script&gt;alert(1)&lt;/script&gt;' "$page"
  [ "$(_hist | tail -1 | jq -r '"\(.kdo) \(.vysledek)"')" = "P900 local" ]
  [ "$(_hist | tail -1 | jq -r .data_sha256)" = "$(sha256sum < "$DATA" | cut -d' ' -f1)" ]
}

@test "publish refuses a page that would claim somebody else's change, a data file outside the schema, and a copied page line" {
  _rp init "$DOC" --title "X" >/dev/null
  run _rp publish "$DOC" --plan P901; [ "$status" -ne 0 ]; [[ "$output" == *"posledni_zmena.kdo is init, not P901"* ]]
  run _rp publish "$DOC" --aid-do; [ "$status" -ne 0 ]; [[ "$output" == *"not aid-do"* ]]
  run _rp publish "$DOC"; [ "$status" -eq 2 ]
  _data '.navic = 1 | .stav_k = "1. 11." | .hotovo = [{co: "x"}]'
  run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -ne 0 ]
  [[ "$output" == *"unknown field navic"* && "$output" == *"stav_k must be a date"* && "$output" == *"hotovo[0].lidsky"* ]]
  git -C "$R" checkout -q -- . 2>/dev/null || true
  _data '.navic = null | del(.navic) | .stav_k = "2026-11-01" | .hotovo = [] | .posledni_zmena.kdo = "P900"'
  local other=docs/plans/jina.md; { echo '# Jiná'; grep 'aid-roadmap-page' "$R/$DOC"; } > "$R/$other"
  cp "$DATA" "$R/docs/plans/jina.prubeh.json"
  run _rp publish "$DOC" --plan P900; [ "$status" -eq 0 ]
  run _rp publish "$other" --plan P900; echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"copied marker line"* ]]
  run _rp init "$other" --title X; [ "$status" -ne 0 ]; [[ "$output" == *"copied marker line"* ]]
}

@test "a path out of the project, through a link or a dangling link is refused and nothing outside changes; odd names work" {
  local out="$BATS_TEST_TMPDIR/outside"; mkdir -p "$out"; printf '# venku\n' > "$out/r.md"
  local snap; snap="$(ls -la "$out"; sha256sum "$out/r.md")"
  run _rp init ../outside/r.md --title X; [ "$status" -eq 2 ]
  run _rp init "$out/r.md" --title X; [ "$status" -eq 2 ]
  ln -s "$out" "$R/docs/plans/odkaz"; run _rp init docs/plans/odkaz/r.md --title X; [ "$status" -eq 2 ]; [[ "$output" == *"is a link"* ]]
  ln -s "$out/r.md" "$R/docs/plans/link.md"; run _rp init docs/plans/link.md --title X; [ "$status" -eq 2 ]
  printf '# y\n' > "$R/docs/plans/d.md"; ln -s "$out/nic.json" "$R/docs/plans/d.prubeh.json"   # dangling data link
  run _rp init docs/plans/d.md --title X; echo "$output"; [ "$status" -ne 0 ]; [ ! -e "$out/nic.json" ]
  [ "$(ls -la "$out"; sha256sum "$out/r.md")" = "$snap" ]
  local odd='docs/plans/a b $x;`y`.md'; printf '# odd\n' > "$R/$odd"
  run _rp init "$odd" --title "Odd"; echo "$output"; [ "$status" -eq 0 ]; [ -f "$R/docs/plans/a b \$x;\`y\`.prubeh.json" ]
}

@test "the lint: roadmapa_dokument without a page or out of the project is an error; a free-text roadmapa: of an older brief passes" {
  local B="$R/.aid-o/plans/P900-zadani.md"; mkdir -p "$R/.aid-o/plans"
  printf -- '---\nroadmapa_dokument: %s\n---\n' "$DOC" > "$B"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-roadmap.sh"
  run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 1 ]; [[ "$output" == "ERROR roadmap_page_missing:"*"next:"* ]]
  printf -- '---\nroadmapa_dokument: ../venku.md\n---\n' > "$B"
  run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 1 ]; [[ "$output" == "ERROR roadmap_path_invalid:"* ]]
  _rp init "$DOC" --title X >/dev/null
  printf -- '---\nroadmapa_dokument: %s\n---\n' "$DOC" > "$B"; run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 0 ]; [ -z "$output" ]
  printf -- '---\nroadmapa: navazuje na %s (fáze 2)\n---\n' "$DOC" > "$B"
  run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 0 ]; [[ "$output" == "WARN roadmap_document_unnamed:"* ]]
  # the free-text roadmapa: of the briefs P113, P114 and P117 (their real lines): a path to a document without a page
  # and plain text bind nothing and say nothing
  local l; for l in '.aid-o/work/P113-stav-a-plan-2026-10-14.md kapitola 10 (P113 = studio podle dílny; napojení na plán a běh, hosting, aplikace = P115 a dál)' \
                   'docs/plans/2026-10-09-roadmapa-p109.md (vydání 3b – poslední plán sady po experimentu P014; mazání EPIC cesty, které roadmapa vedla jako „P112 — maže“)' \
                   'navazuje na 3.7.0 (companion + 20 oprav); vstup = záznamy WAN P109–P112 z 19.–20. 10. 2026'; do
    printf -- '---\nroadmapa: %s\n---\n' "$l" > "$B"; run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 0 ]; [ -z "$output" ]
  done
  # the page line without its data is a missing page, not a bad path; through the lint itself (aid-plan-lint.sh --zadani)
  mv "$DATA" "$DATA.bak"; printf -- '---\nroadmapa_dokument: %s\n---\n' "$DOC" > "$B"
  run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 1 ]; [[ "$output" == "ERROR roadmap_page_missing:"*"no data"* ]]
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" --zadani "$B"; [ "$status" -ne 0 ]; [[ "$output" == *"roadmap_page_missing"* ]]
  mv "$DATA.bak" "$DATA"
  printf -- '---\nroadmapa_dokument: docs/plans/nic.md\n---\n' > "$B"
  run aid_roadmap_brief_check "$B" "$R"; [ "$status" -eq 1 ]; [[ "$output" == "ERROR roadmap_page_missing:"*"does not exist"* ]]
}

@test "published also with AID_PM_PAGES=off (the other pages are not); a failing publisher is failed, never local; the link is not stored" {
  _publisher; export AID_PM_PAGES=off
  run _rp init "$DOC" --title X; echo "$output"; [ "$status" -eq 0 ]; [ "$output" = "link https://share.example/p/x#k=secret" ]
  [ "$(_hist | tail -1 | jq -r .vysledek)" = link ]; ! grep -rq 'k=secret' "$R/.aid-o/work/roadmap-pages"
  echo '<p>x</p>' > "$BATS_TEST_TMPDIR/plan.html"
  run bash "$AID_PLUGIN_PATH/scripts/aid-pm-page-publish.sh" "$BATS_TEST_TMPDIR/plan.html" --plan P900 --kind plan --title T --project-root "$R"
  [[ "$output" == "none "* ]]
  _data '.posledni_zmena = {kdo: "P900", co: "x"}'
  FAIL=1 run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -ne 0 ]
  [ "$(_hist | tail -1 | jq -r '"\(.vysledek) \(.duvod)"')" = "failed aid-pm-page-publish: the publisher refused the page (exit 3): share is down" ]
  # a failed first publish: the next init publishes; an error text carrying the link never stores it
  rm -rf "$R/.aid-o/work/roadmap-pages"; FAIL=1 run _rp publish "$DOC" --plan P900
  run _rp init "$DOC" --title X; echo "$output"; [[ "$output" == "link "* ]]
  [ "$(_hist | tail -1 | jq -r .kdo)" = init ]                                   # init's republish is never a plan's refresh
  printf '#!/usr/bin/env bash\necho "published https://share.example/p/x#k=secret but the record failed" >&2; exit 1\n' > "$BATS_TEST_TMPDIR/pub"
  run _rp publish "$DOC" --plan P900; [ "$status" -ne 0 ]; ! grep -rq 'k=secret' "$R/.aid-o/work/roadmap-pages"
  grep -q '<link>' "$R"/.aid-o/work/roadmap-pages/*/history.jsonl
}

@test "a later plan's refresh does not hide an earlier plan's; a failed publish does not count; the data as merged or as on the target count" {
  _rp init "$DOC" --title X >/dev/null
  _data '.posledni_zmena = {kdo: "P900", co: "a"}'; git -C "$R" add -A; git -C "$R" commit -qm p900; local m900; m900="$(git -C "$R" rev-parse HEAD)"
  _rp publish "$DOC" --plan P900 >/dev/null
  _data '.posledni_zmena = {kdo: "P901", co: "b"}'; git -C "$R" add -A; git -C "$R" commit -qm p901
  _rp publish "$DOC" --plan P901 >/dev/null
  run python3 -I "$PY" refreshed "$R" "$R" "$DOC" P900 "$m900" HEAD; [ "$status" -eq 0 ]
  run python3 -I "$PY" refreshed "$R" "$R" "$DOC" P901 "$m900" HEAD; [ "$status" -eq 0 ]       # on the target now
  run python3 -I "$PY" refreshed "$R" "$R" "$DOC" P902 HEAD; [ "$status" -eq 1 ]
  _publisher; _data '.posledni_zmena = {kdo: "P903", co: "c"}'; git -C "$R" add -A; git -C "$R" commit -qm p903
  FAIL=1 run _rp publish "$DOC" --plan P903; [ "$status" -ne 0 ]
  run python3 -I "$PY" refreshed "$R" "$R" "$DOC" P903 HEAD; [ "$status" -eq 1 ]
}

@test "the page has its fixed parts: every part required, stages counted into the progress, done grouped by stage, history from the record" {
  _rp init "$DOC" --title "X kde jsme" >/dev/null
  _data 'del(.rizika) | .etapy = [] | .stav = "jede"'
  run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -ne 0 ]
  [[ "$output" == *"missing field rizika"* && "$output" == *"etapy must name at least one stage"* && "$output" == *"stav must be one of"* ]]
  _data '.rizika = [] | .stav = [] | .etapy = [{nazev: ["x"], kdy: "1", co_prinese: "a", stav: {}, polozky_hotovo: 0, polozky_celkem: 1}] | .hotovo = [{etapa: {}, lidsky: "x"}]'
  run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -eq 1 ]; [[ "$output" != *Traceback* ]]
  [[ "$output" == *"stav must be one of"* && "$output" == *"etapy[0].stav must be one of"* && "$output" == *"hotovo[0].etapa"* ]]
  _data '.etapy = [{nazev: "1.0", kdy: "1", co_prinese: "a", stav: "ted", polozky_hotovo: 0, polozky_celkem: 1}, {nazev: "1.0", kdy: "2", co_prinese: "b", stav: "ceka", polozky_hotovo: 0, polozky_celkem: 1}] | .hotovo = [] | .stav = "na_ceste"'
  run _rp publish "$DOC" --plan P900; [ "$status" -eq 1 ]; [[ "$output" == *"own nazev"* ]]
  _data '.rizika = [{co: "první plán", overi: "P900"}] | .stav = "na_ceste" | .posledni_zmena = {kdo: "P900", co: "etapy doplněny"}
    | .etapy = [{nazev: "1.0", kdy: "1. 11.", co_prinese: "základ", stav: "hotovo", polozky_hotovo: 3, polozky_celkem: 3},
                {nazev: "1.1", kdy: "2. 11.", co_prinese: "zbytek", stav: "ted", polozky_hotovo: 1, polozky_celkem: 5}]
    | .hotovo = [{etapa: "1.9", lidsky: "nic"}]'
  run _rp publish "$DOC" --plan P900; [ "$status" -ne 0 ]; [[ "$output" == *"hotovo[0].etapa '1.9' is not the nazev of a stage"* ]]
  _data '.hotovo = [{etapa: "1.0", lidsky: "Základ stojí"}] | .etapy[1].polozky_hotovo = 6'
  run _rp publish "$DOC" --plan P900; [ "$status" -ne 0 ]; [[ "$output" == *"hotovo <= celkem"* ]]
  _data '.etapy[1].polozky_hotovo = 1'
  run _rp publish "$DOC" --plan P900; echo "$output"; [ "$status" -eq 0 ]
  local page; page="$(ls "$R"/.aid-o/work/roadmap-pages/*/page.html)"
  grep -q '<b>4 / 8</b>' "$page"; grep -q 'width:50%' "$page"                       # 3+1 of 3+5, computed
  grep -q 'Nic. Jede se bez tebe.' "$page"; grep -q 'Základ stojí' "$page"; grep -q '<span class="pill">Na cestě</span>' "$page"
  grep -q 'etapy doplněny' "$page"; grep -q 'založení stránky' "$page"                # this change and the earlier one
  local p; for p in "Čeká na tebe" "Etapy" "Teď se dělá" "Kde jsme v číslech" "Co chybí a od koho" "Rizika" "Hotovo" "Historie změn"; do grep -q "<h2>$p</h2>" "$page"; done
}
