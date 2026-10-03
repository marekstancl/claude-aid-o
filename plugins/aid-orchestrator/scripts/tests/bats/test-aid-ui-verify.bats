#!/usr/bin/env bats
# aid-tier: t2
# P103 Step 7 — the /aid-ui gate (aid-ui-verify.sh + lib/ui-fidelity/aid-ui-verify.mjs) on
# the fixture verify-site: planted defects under their check names, the fixed copy passes,
# a 404 page fails, lazy images reach the screenshot, an edited site is refused, the
# preview runs beside the brand page, and the checks match checks.yaml one to one.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB="$SC/../lib/ui-fidelity"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/verify-site"
  T="$BATS_TEST_TMPDIR"
  export AID_UI_HOST=127.0.0.1 AID_UI_PREVIEW_PORT=39927 AID_UI_BRAND_PORT=39926
  export AID_UI_STATE_DIR="$T/st"
  PROJ="$T/proj"; SITE="$T/site"; RES="$PROJ/.aid-ui/verify/result.json"
  mkdir -p "$PROJ/docs/brand"
  cp "$SC/../skills/ui-design/brand-page/index.html" "$PROJ/docs/brand/"
  cp -r "$FX/project/docs/." "$PROJ/docs/"
  cp -r "$FX/site" "$SITE"
  "$SC/aid-ui-state.sh" init "$PROJ" >/dev/null
}

teardown() {
  AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" stop preview >/dev/null 2>&1 || true
  AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" stop brand >/dev/null 2>&1 || true
  [[ -z "${HOLD:-}" ]] || kill "$HOLD" 2>/dev/null || true
}

# row status of <check> <page> over every viewport and browser, unique, comma-joined
st() { jq -r --arg c "$1" --arg p "$2" '[.rows[] | select(.check == $c and .page == $p) | .status] | unique | join(",")' "$RES"; }

@test "every name in checks.yaml has an implementation and none extra" {
  impl="$(sed -n "/^const CHECKS/,/\];/p" "$LIB/aid-ui-verify.mjs" | grep -o "'[a-z_0-9]*'" | tr -d "'" | sort -u)"
  named="$(yq -r '.checks | keys | .[]' "$SC/../skills/ui-design/coverage/checks.yaml" | sort)"
  [ -n "$impl" ]
  [ "$impl" == "$named" ] || { diff <(echo "$impl") <(echo "$named"); return 1; }
}

@test "planted defects are reported under their names, only on their page; seo BLOCKER fails; result carries build id and fingerprints; lazy image in the screenshot" {
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  # brand_assets: a hand-drawn inline SVG logo on index.html, a drawn <img> logo on o-nas
  [ "$(st brand_assets index.html)" == fail ]
  jq -e '[.rows[] | select(.check == "brand_assets" and .page == "index.html") | .detail] | all(contains("inline <svg> in a.znacka"))' "$RES" >/dev/null
  for c in no_overflow one_line_controls facts_match axe image_weight; do
    [ "$(st $c index.html)" == fail ] || { echo "$c index: $(st $c index.html)"; return 1; }
    [ "$(st $c o-nas/index.html)" == pass ] || { echo "$c o-nas: $(st $c o-nas/index.html)"; return 1; }
  done
  for c in glyph_coverage no_placeholders links_resources required_files seo; do
    [ "$(st $c o-nas/index.html)" == fail ] || { echo "$c o-nas: $(st $c o-nas/index.html)"; return 1; }
    [ "$(st $c index.html)" == pass ] || { echo "$c index: $(st $c index.html)"; return 1; }
  done
  jq -e '[.rows[] | select(.check == "seo" and .status == "fail") | .detail] | all(startswith("BLOCKER"))' "$RES" >/dev/null
  # definition-of-done rows 2, 6, 13: overlap on index, header differing from index on o-nas, no IČO on either
  [ "$(st no_overlap index.html)" == fail ] && [ "$(st no_overlap o-nas/index.html)" == pass ]
  [ "$(st brand_consistency o-nas/index.html)" == fail ] && [ "$(st brand_consistency index.html)" == pass ]
  [ "$(st business_minimum index.html)" == fail ] && [ "$(st business_minimum o-nas/index.html)" == fail ]
  [ "$(st page_weight index.html)" == pass ]
  # glyph applies to chromium only (checks.yaml applies): no webkit row
  [ "$(jq '[.rows[] | select(.check == "glyph_coverage" and .browser == "webkit")] | length' "$RES")" -eq 0 ]
  # build id and a fingerprint per page, equal to what aid-ui-state.sh computes
  [ "$(jq -r .build_id "$RES")" == "$("$SC/aid-ui-state.sh" build-id "$SITE")" ]
  jq -e '(.fingerprints | keys) as $k | [.matrix[].page] | unique | all(IN($k[]))' "$RES" >/dev/null
  jq -e '.fingerprints == input.build.fingerprints' "$RES" "$PROJ/docs/design/brand-state.json" >/dev/null
  # the red lazy image at the bottom of index.html is in the full-page screenshot
  shot="$PROJ/.aid-ui/verify/shots/chromium/390/index.html.png"
  [ -f "$shot" ]
  red="$(cd "$LIB" && node --input-type=module -e "
    import { PNG } from 'pngjs'; import fs from 'node:fs';
    const p = PNG.sync.read(fs.readFileSync('$shot')); let n = 0;
    for (let i = 0; i < p.data.length; i += 4) if (p.data[i] > 200 && p.data[i+1] < 40 && p.data[i+2] < 40) n++;
    console.log(n);")"
  [ "$red" -gt 10000 ] || { echo "red pixels: $red"; return 1; }
}

@test "the fixed copy passes every row" {
  cp -r "$FX/fixed/." "$SITE/"
  # the SEO brief: page table (H1 as built) and the PM's AI robot policy the fixed robots.txt follows
  mkdir -p "$PROJ/docs/seo"
  printf '| URL | H1 |\n|---|---|\n| / | Pekárna U Mlýna |\n| /o-nas | O nás |\n\n## Politika AI robotů\n- vyhledávání a citace: povolit\n- trénink: zakázat\n' >"$PROJ/docs/seo/brief.md"
  # SEO is part of the project and the PM approved exactly this brief (step 1s)
  sha="$(sha256sum "$PROJ/docs/seo/brief.md" | cut -d' ' -f1)"
  jq --arg t "docs/seo/brief.md@$sha" '.options.seo = true | .answers["q-seo"] = {kind: "seo_brief", decision: "approve", target: $t}' \
    "$PROJ/docs/design/brand-state.json" >"$T/s.json" && mv "$T/s.json" "$PROJ/docs/design/brand-state.json"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 0 ] || { echo "$output"; jq -c '.rows[] | select(.status != "pass")' "$RES" | head; return 1; }
  [ "$(jq '[.rows[] | select(.status != "pass")] | length' "$RES")" -eq 0 ]
  jq -e '.gate.build_id' "$PROJ/docs/design/brand-state.json" >/dev/null
  # ai_search ran (not N/A) and its findings stay out of the seo row
  [ "$(jq '[.rows[] | select(.check == "ai_search")] | length' "$RES")" -gt 0 ]
  ! jq -r '.rows[] | select(.check == "ai_search") | .detail' "$RES" | grep -q 'N/A'
  ! jq -r '.rows[] | select(.check == "seo") | .detail' "$RES" | grep -q 'ai-'
  jq -e '.indexable_pages == 2 and .pages_with_jsonld == 2 and .ai.BLOCKER == 0' "$PROJ/.aid-ui/verify/seo-summary.json" >/dev/null
}

@test "ai_search: N/A without options.seo; with it a missing policy fails the home page only, page findings on their page" {
  cp -r "$FX/fixed/." "$SITE/"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st ai_search index.html)" == pass ]
  jq -r '.rows[] | select(.check == "ai_search") | .detail' "$RES" | grep -q 'N/A: SEO is not part of this project'
  jq '.options.seo = true' "$PROJ/docs/design/brand-state.json" >"$T/s.json" && mv "$T/s.json" "$PROJ/docs/design/brand-state.json"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 3 ]
  [ "$(st ai_search index.html)" == fail ]
  jq -r '.rows[] | select(.check == "ai_search" and .page == "index.html") | .detail' "$RES" | grep -q 'ai-policy'
  ! jq -r '.rows[] | select(.check == "ai_search" and .page == "o-nas/index.html") | .detail' "$RES" | grep -q 'ai-policy'
  [ "$(jq '[.rows[] | select(.check == "ai_search" and .browser == "webkit")] | length' "$RES")" -eq 0 ]
  ! jq -r '.rows[] | select(.check == "seo") | .detail' "$RES" | grep -q 'ai-'
}

@test "a crashed SEO check (exit 1, no report) is not_covered, not a pass" {
  mkdir -p "$T/out"
  echo '{"viewports":[390],"browsers":["chromium"],"checks":{"seo":"x","ai_search":"x"}}' > "$T/ck.json"
  echo '{"build":{"id":"x","fingerprints":{"index.html":"a","_site":"c"}},"options":{"seo":true}}' > "$T/state.json"
  printf 'import sys\nsys.stderr.write("Traceback: boom\\n")\nsys.exit(1)\n' > "$T/crash.py"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  run bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" \
    --base "$url" --out "$T/out" --seo "$T/crash.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  RES="$T/out/result.json"
  [ "$(st seo index.html)" == not_covered ]
  [ "$(st ai_search index.html)" == not_covered ]
  jq -r '.rows[] | select(.check == "seo") | .detail' "$RES" | grep -q 'exit 1: Traceback: boom'
}

@test "an inline SVG logo passes only with the brand package's drawing; colour, whitespace and ids do not count" {
  cp -r "$FX/fixed/." "$SITE/"
  # ok*: brand logo.svg geometry recoloured/reformatted; bad*: one coordinate moved, an extra
  # shape, another viewBox, a hand-drawn mark; deco: an SVG outside any logo context is not a logo
  sed -i 's#<nav>#<a href="/" id="ok1"><svg viewBox="0 0 120 32"><circle id="c" class="k" cx="16"  cy="16" r="14" fill="red"/><rect x="36" y="10" width="80" height="12" stroke="blue"/></svg></a>\
<span class="brand-mark" id="ok2"><svg viewBox=" 0 0  120 32 "><circle cx="16" cy="16" r="14"></circle><rect height="12" width="80" y="10" x="36"></rect></svg></span>\
<span aria-label="Logo" id="bad1"><svg viewBox="0 0 120 32"><circle cx="17" cy="16" r="14"/><rect x="36" y="10" width="80" height="12"/></svg></span>\
<span class="logo-x" id="bad2"><svg viewBox="0 0 120 32"><circle cx="16" cy="16" r="14"/><rect x="36" y="10" width="80" height="12"/><path d="M0 0L1 1"/></svg></span>\
<span id="brand3"><svg viewBox="0 0 64 32"><circle cx="16" cy="16" r="14"/><rect x="36" y="10" width="80" height="12"/></svg></span>\
<a rel="home" href="/o-nas/" id="bad4"><svg viewBox="0 0 64 64"><path d="M8 8h48v48z"/></svg></a>\
<svg viewBox="0 0 10 10" width="10" height="10" aria-hidden="true"><circle cx="5" cy="5" r="4"/></svg>\
<nav>#' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st brand_assets index.html)" == fail ] || { echo "$output"; return 1; }
  d="$(jq -r '[.rows[] | select(.check == "brand_assets" and .page == "index.html") | .detail][0]' "$RES")"
  for id in bad1 bad2 brand3 bad4; do [[ "$d" == *"#$id"* ]] || { echo "missing $id: $d"; return 1; }; done
  [[ "$d" != *ok1* && "$d" != *ok2* ]] || { echo "brand drawing refused: $d"; return 1; }
  [ "$(grep -o 'inline <svg>' <<<"$d" | wc -l)" -eq 4 ] || { echo "$d"; return 1; }
  [ "$(st brand_assets o-nas/index.html)" == pass ]
}

@test "a site edited after build-record is refused" {
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  echo '<!-- edit -->' >> "$SITE/index.html"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since build-record"* ]]
  [ ! -f "$RES" ]
}

@test "a page answering 404 is an http_200 failure" {
  mkdir -p "$T/out"
  echo '{"viewports":[390],"browsers":["chromium"],"checks":{"http_200":"x"}}' > "$T/ck.json"
  echo '{"build":{"id":"x","fingerprints":{"index.html":"a","gone.html":"b","_site":"c"}}}' > "$T/state.json"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  run bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" \
    --base "$url" --out "$T/out" --seo "$SC/aid-ui-seo-check.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  RES="$T/out/result.json"
  [ "$(st http_200 gone.html)" == fail ]
  [ "$(st http_200 index.html)" == pass ]
  jq -e '.rows[] | select(.page == "gone.html") | .detail | contains("HTTP 404")' "$RES" >/dev/null
}

@test "preview runs while the brand page is served; a port held by another process is named" {
  touch "$PROJ/docs/brand/tokens.css"
  AID_UI_PROJECT="$PROJ" run bash "$SC/aid-ui-serve.sh" brand "$PROJ/docs/brand"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  AID_UI_PROJECT="$PROJ" run bash "$SC/aid-ui-serve.sh" preview "$SITE"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"URL: http://127.0.0.1:39927/"* ]]
  curl -sf "http://127.0.0.1:39926/" >/dev/null
  curl -sf "http://127.0.0.1:39927/" | grep -q 'Pekárna U Mlýna'
  AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" stop preview >/dev/null
  # another process on the preview port: the gate refuses and names it
  python3 -m http.server 39927 --bind 127.0.0.1 --directory "$T" >/dev/null 2>&1 & HOLD=$!
  for _ in $(seq 50); do [[ -n "$(ss -ltnH 'sport = :39927')" ]] && break; sleep 0.1; done
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"port 39927 in use"*python3* ]]
}

@test "flow ids that are not an allowlisted name are refused and nothing is imported; a symlinked scenario is refused; role/state cannot move a screenshot" {
  mkdir -p "$T/out" "$PROJ/.aid-ui/scenarios"
  echo '{"viewports":[390],"browsers":["chromium"],"checks":{"http_200":"x","app_task_states":"x"}}' > "$T/ck.json"
  for f in "$PROJ/x.mjs" "$PROJ/.aid-ui/x.mjs" "$T/evil.mjs"; do
    echo "import fs from 'node:fs'; fs.writeFileSync('$T/imported', '$f'); export default async () => {};" > "$f"
  done
  ln -s "$T/evil.mjs" "$PROJ/.aid-ui/scenarios/evil.mjs"
  echo "export default async ({ page, base }) => { await page.goto(base); };" > "$PROJ/.aid-ui/scenarios/ok.mjs"
  jq -n '{variant:{type:"webapp"},build:{id:"x",fingerprints:{"index.html":"a"}},
    structure:{roles:["../../../../esc"],flows:[{id:"../../x",states:["s"]},{id:"a/../../x",states:["s"]},{id:"X",states:["s"]},
      {id:"evil",states:["s"]},{id:"ok",states:["../../../../esc2"]}]}}' > "$T/state.json"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  run bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" \
    --base "$url" --out "$T/out" --project "$PROJ" --seo "$SC/aid-ui-seo-check.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  RES="$T/out/result.json"
  [ ! -e "$T/imported" ] || { echo "imported: $(cat "$T/imported")"; return 1; }
  for p in ../../x a/../../x X; do
    jq -e --arg p "$p" '[.rows[] | select(.page == $p)] | length > 0 and all(.status == "not_covered" and (.detail | startswith("refused flow id")))' "$RES" >/dev/null || { echo "$p"; return 1; }
  done
  [ "$(st app_task_states evil)" == not_covered ]
  [ "$(st app_task_states ok)" == pass ] || { jq -c '.rows[] | select(.page == "ok")' "$RES"; return 1; }
  [ -z "$(find "$T" -name '*esc*' -not -path "$T/out/shots/*")" ]
  [ -n "$(find "$T/out/shots" -name '*esc*.png')" ]
}

@test "preview serves no dotfiles and no directory listings; .well-known is served" {
  mkdir -p "$SITE/.git" "$SITE/.well-known" "$SITE/nolist"
  echo SECRET > "$SITE/.env"; echo '[core]' > "$SITE/.git/config"; echo 'Contact: x' > "$SITE/.well-known/security.txt"
  echo x > "$SITE/nolist/a.txt"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  for p in .env .git/config %2Eenv .git/ o-nas/../.env nolist/; do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "${url}$p")" == 404 ] || { echo "$p served"; return 1; }
  done
  curl -sf "${url}.well-known/security.txt" | grep -q Contact
  curl -sf "${url}o-nas/" >/dev/null
}
