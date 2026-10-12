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
  cp "$FX/project/DESIGN.md" "$PROJ/"
  cp -r "$FX/site" "$SITE"
  "$SC/aid-ui-state.sh" init "$PROJ" >/dev/null
  "$SC/aid-ui-state.sh" method "$PROJ" build >/dev/null   # P108: build-record wants the build method receipt
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
  # H1 (12. 10. 2026): a section faded until a script reveals it on scroll - hidden without JS and at first paint
  for c in content_without_js first_paint_visible; do
    [ "$(st $c index.html)" == fail ] || { echo "$c index: $(st $c index.html)"; return 1; }
    [ "$(st $c o-nas/index.html)" == pass ] || { echo "$c o-nas: $(st $c o-nas/index.html)"; return 1; }
  done
  jq -e '[.rows[] | select(.check == "content_without_js" and .page == "index.html") | .detail] | all(contains("Pečeme od čtyř"))' "$RES" >/dev/null
  jq -e '[.rows[] | select(.check == "first_paint_visible" and .page == "index.html") | .detail] | all(contains("faded"))' "$RES" >/dev/null
  # H3: a mailto form fails; a script-sent form with a live status, a locked button and a clickable phone passes
  [ "$(st form_states index.html)" == fail ]; [ "$(st form_states o-nas/index.html)" == pass ]
  jq -e '[.rows[] | select(.check == "form_states" and .page == "index.html") | .detail] | all(contains("mailto"))' "$RES" >/dev/null
  # FB-29 task test (P113a): one row; the price of a loaf is not on the planted site, an invented text is named,
  # hours and booking are found within two steps at both widths
  [ "$(jq '[.rows[] | select(.check == "task_test")] | length' "$RES")" -eq 1 ]; [ "$(st task_test index.html)" == fail ]
  d="$(jq -r '.rows[] | select(.check == "task_test") | .detail' "$RES")"
  for c in "price at 1440 px: not found" "price at 390 px: not found" '"Doprava zdarma" is not in the facts register' "hours 1440: index.html (0)" "booking 390: index.html (0)"; do
    [[ "$d" == *"$c"* ]] || { echo "task_test misses $c: $d"; return 1; }; done
  # FB-30 photo slots (P113a, PM 1A): o-nas keeps its slot through a test photo; the home page's slot is unlisted and carries text
  [ "$(st photo_slots o-nas/index.html)" == pass ]; [ "$(st photo_slots index.html)" == fail ]
  d="$(jq -r '[.rows[] | select(.check == "photo_slots" and .page == "index.html") | .detail][0]' "$RES")"
  for c in "slot pekar is not in photos.yaml" ; do [[ "$d" == *"$c"* ]] || { echo "photo_slots misses $c: $d"; return 1; }; done
  # P113a AC8: forms on the site but no receiver for the preview: form_delivery names it
  [ "$(st form_delivery index.html)" == fail ]; jq -e '.rows[] | select(.check == "form_delivery") | .detail | contains("no .aid-ui/form.json")' "$RES" >/dev/null
  # P108: invented count, percentage, years and e-mail are named in facts_match
  d="$(jq -r '[.rows[] | select(.check == "facts_match" and .page == "index.html") | .detail][0]' "$RES")"
  for c in "200 klientům" "40 %" "15 let" "info@neexistuje.cz"; do [[ "$d" == *"$c"* ]] || { echo "facts_match misses $c: $d"; return 1; }; done
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

# measured — the fixture design standard names the build just recorded (as `measure --build` would)
measured() {
  local id; id="$(jq -r .build.id "$PROJ/docs/design/brand-state.json")"
  sed -i "/^Měřeno na buildu/d; 0,/^## Značka/s//Měřeno na buildu \`$id\`.\n\n## Značka/" "$PROJ/docs/design/design-standard.md"
}

# copy_reviewed [verdict] — a recorded copy review of every page of the recorded build (as
# aid-ui-state.sh copy-record stores it after an independent review), for the current text,
# facts and product context
copy_reviewed() {
  mkdir -p "$PROJ/docs/content"; [ -f "$PROJ/docs/content/product-context.md" ] || printf '# Produkt\nStav: vyplněno\n' > "$PROJ/docs/content/product-context.md"
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subject.json" >/dev/null
  jq --slurpfile sub "$T/subject.json" --arg f "$(sha256sum "$PROJ/docs/content/facts.yaml" | cut -d' ' -f1)" \
     --arg c "$(sha256sum "$PROJ/docs/content/product-context.md" | cut -d' ' -f1)" --arg v "${1:-pass}" \
    '.copy_review.pages = ($sub[0].pages | map_values({subject_sha256: .sha256, facts_sha256: $f, context_sha256: $c,
       verdict: $v, blocking: (if $v == "pass" then [] else ["persona cílový zákazník: skóre 3"] end), provider: "codex", at: "2026-10-04T00:00:00Z"}))' \
    "$PROJ/docs/design/brand-state.json" > "$T/s.json" && mv "$T/s.json" "$PROJ/docs/design/brand-state.json"
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
  # the customer tasks without the invented one (FB-29): the fixed site shows the 65 Kč loaf
  printf -- '- {id: hours, task: "Kdy", expect: ["7:00 až 18:00"]}\n- {id: price, task: "Bochník", expect: ["Bochník", "65 Kč"]}\n- {id: booking, task: "Objednat", form: true}\n' > "$PROJ/docs/content/tasks.yaml"
  # the preview's form receiver (AC8): o-nas sends its telephone to /api/zprava
  echo '{"endpoint": "/api/zprava", "required": ["tel"], "honeypot": "website"}' > "$PROJ/.aid-ui/form.json"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  measured
  copy_reviewed
  # step 7b: the first run has only the customer page open (not made yet), then the page, then the gate again
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(jq -c '[.rows[] | select(.status != "pass") | [.check, .status]] | unique' "$RES")" == '[["customer_page","not_covered"]]' ] \
    || { echo "$output"; jq -c '.rows[] | select(.status != "pass")' "$RES" | head; return 1; }
  python3 "$SC/aid-ui-customer-page.py" "$PROJ" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 0 ] || { echo "$output"; jq -c '.rows[] | select(.status != "pass")' "$RES" | head; return 1; }
  [ "$(jq '[.rows[] | select(.status != "pass")] | length' "$RES")" -eq 0 ]
  # the real send went through and the test messages are gone again; the log names no value
  jq -e '.rows[] | select(.check == "form_delivery") | .detail | startswith("delivered and removed again")' "$RES" >/dev/null
  [ -z "$(ls -A "$PROJ/.aid-ui/inbox" 2>/dev/null)" ]
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

@test "brand_package: one row on the home page; a missing part fails it with its name" {
  cp -r "$FX/fixed/." "$SITE/"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(jq '[.rows[] | select(.check == "brand_package")] | length' "$RES")" -eq 1 ]
  jq -e '.rows[] | select(.check == "brand_package") | .page == "index.html" and .status == "pass"' "$RES" >/dev/null
  rm "$PROJ/docs/design/brand-package/icons/favicon.ico" "$PROJ/docs/design/brand-package/icons/favicon.svg"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 3 ]
  jq -e '.rows[] | select(.check == "brand_package") | .status == "fail" and (.detail | contains("favicon"))' "$RES" >/dev/null
}

@test "design_standard_doc: one row; a missing section fails it; a broken DESIGN.md is not_covered, never a pass" {
  cp -r "$FX/fixed/." "$SITE/"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  sed -i 's/^## Vynucení$/## Jinak/' "$PROJ/docs/design/design-standard.md"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(jq '[.rows[] | select(.check == "design_standard_doc")] | length' "$RES")" -eq 1 ]
  jq -e '.rows[] | select(.check == "design_standard_doc") | .status == "fail" and (.detail | contains("Vynucení"))' "$RES" >/dev/null
  printf -- '---\n[nejde: yaml\n---\n' >"$PROJ/DESIGN.md"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "design_standard_doc") | .status == "not_covered"' "$RES" >/dev/null
}

@test "K1b page checks: an off-token colour, a small control, a third-party request, a tall sticky panel and motion are each reported" {
  cp -r "$FX/fixed/." "$SITE/"
  sed -i 's|</main>|<p style="color:#ff0000">Akce</p><button style="width:30px;height:30px;padding:0;background:#1a1a1a;color:#faf6ee">x</button>\
<aside style="position:sticky;top:0;height:3000px;background:#faf6ee">panel</aside>\
<div style="animation:spin 2s infinite;width:10px;height:10px;background:#1a1a1a"></div><style>@keyframes spin{to{transform:rotate(1turn)}}</style>\
<img src="https://tracker.invalid/p.gif" alt="" width="1" height="1"></main>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 3 ]
  jq -e '.rows[] | select(.check == "token_usage" and .page == "index.html") | .status == "fail" and (.detail | contains("#ff0000"))' "$RES" >/dev/null
  jq -e '.rows[] | select(.check == "token_usage" and .page == "o-nas/index.html") | .status == "pass"' "$RES" >/dev/null
  jq -e '[.rows[] | select(.check == "touch_targets" and .page == "index.html") | .status] | unique == ["fail"]' "$RES" >/dev/null
  jq -e '.rows[] | select(.check == "privacy_before_consent" and .page == "index.html") | .status == "fail" and (.detail | contains("tracker.invalid"))' "$RES" >/dev/null
  jq -e '[.rows[] | select(.check == "sticky_panels" and .page == "index.html") | .status] | unique == ["fail"]' "$RES" >/dev/null
  jq -e '[.rows[] | select(.check == "sticky_panels" and .page == "o-nas/index.html") | .detail] | all(startswith("N/A"))' "$RES" >/dev/null
  jq -e '.rows[] | select(.check == "reduced_motion" and .page == "index.html") | .status == "fail"' "$RES" >/dev/null
  # project rows: vision N/A without options.vision, the coverage map matches the standards
  jq -e '.rows[] | select(.check == "vision_doc") | .status == "pass" and (.detail | startswith("N/A"))' "$RES" >/dev/null
  jq -e '.rows[] | select(.check == "coverage") | .status == "pass"' "$RES" >/dev/null
}

@test "K1b edge cases: invisible focus fails; honeypot, checked radio, frame, fading focus, label, translucent token, hidden dropdown, decorative layer do not; a cookie on load fails privacy" {
  cp -r "$FX/fixed/." "$SITE/"
  # a button whose focus looks like rest; a honeypot (tabindex -1 in aria-hidden); one radio group of
  # three; a checkbox in a 44 px label; token colours written as oklch and color-mix; a tall fixed
  # decorative layer (pointer-events none, z -1); a cookie written on load; a focus outline that fades in;
  # a frame with nothing focusable; a translucent token colour; a sticky header with a hidden dropdown
  sed -i 's|</main>|<style>button{font:inherit}#fade{transition:all .4s;outline:none;background:#faf6ee;color:#1a1a1a;border:0;min-width:44px;min-height:44px}#fade:focus{outline:3px solid #1a1a1a}</style><button id="fade">Plynule</button>\
<iframe style="border:0" srcdoc="<p>mapa</p>" width="120" height="60" title="mapa"></iframe>\
<p style="color:rgba(26,26,26,.6)">Tlumené</p>\
<div style="position:sticky;top:0;height:50px;background:#ffffff">Lišta<ul style="position:absolute;top:50px;visibility:hidden;margin:0"><li>a</li><li>b</li><li>c</li></ul></div>\
<button id="nofocus" style="outline:none;min-width:44px;min-height:44px;background:#1a1a1a;color:#ffffff;border:0">Koupit</button>\
<p class="hp" aria-hidden="true"><input name="website" tabindex="-1" style="border:1px solid #1a1a1a"></p>\
<fieldset style="border:0"><label style="display:inline-block;min-width:44px;min-height:44px"><input type="radio" name="r" value="1">a</label><label style="display:inline-block;min-width:44px;min-height:44px"><input type="radio" name="r" value="2" checked>b</label><label style="display:inline-block;min-width:44px;min-height:44px"><input type="radio" name="r" value="3">c</label></fieldset>\
<label style="display:block;min-height:44px"><input type="checkbox"> Souhlasím s podmínkami</label>\
<p style="color:oklch(0.2 0 0 / 1);background:color-mix(in srgb, #ffffff 100%, black)">Barvy</p>\
<div style="position:fixed;inset:0;height:3000px;z-index:-1;pointer-events:none;background:#faf6ee"></div>\
<script>document.cookie="sid=1; path=/"</script></main>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  d="$(jq -r '[.rows[] | select(.check == "keyboard" and .page == "index.html" and .status == "fail") | .detail][0]' "$RES")"
  [[ "$d" == *"focus not visible"*"Koupit"* ]] || { echo "keyboard: $d"; return 1; }
  [[ "$d" != *website* && "$d" != *Plynule* ]] || { echo "honeypot or fading focus counted: $d"; return 1; }
  [ "$(st touch_targets index.html)" == pass ]
  # oklch(0.2 0 0) is not exactly #1a1a1a: only that colour is reported, the color-mix white is a token
  t="$(jq -r '[.rows[] | select(.check == "token_usage" and .page == "index.html") | .detail][0]' "$RES")"
  [[ "$t" == "colours outside DESIGN.md tokens: #"??????" (1×)" ]] || { echo "token_usage: $t"; return 1; }
  [ "$(st sticky_panels index.html)" == pass ]
  jq -e '.rows[] | select(.check == "privacy_before_consent" and .page == "index.html") | .status == "fail" and (.detail | contains("sid"))' "$RES" >/dev/null
  [ "$(st privacy_before_consent o-nas/index.html)" == pass ]
}

@test "K1b keyboard: a control that keeps Tab (a trap) leaves the rest unreached" {
  cp -r "$FX/fixed/." "$SITE/"
  sed -i 's|<nav>|<input aria-label="past" style="min-height:44px" onkeydown="if(event.key===\x27Tab\x27)event.preventDefault()"><nav>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "keyboard" and .page == "index.html") | .status == "fail" and (.detail | test("Tab reaches [0-9]+ of [0-9]+"))' "$RES" >/dev/null
}

@test "K1b safe_area: a PWA panel fixed at the bottom needs env(safe-area-inset-*); a web is N/A" {
  mkdir -p "$T/out"
  echo '{"viewports":[390],"browsers":["chromium"],"checks":{"safe_area":"x"}}' > "$T/ck.json"
  echo '{"variant":{"type":"pwa"},"build":{"id":"x","fingerprints":{"index.html":"a","_site":"c"}}}' > "$T/state.json"
  sed -i 's|</main>|<nav id="dole" style="position:fixed;bottom:0;left:0;right:0;height:56px;background:#fff">menu</nav></main>|' "$SITE/index.html"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  verify() { bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" \
    --base "$url" --out "$T/out" --seo "$SC/aid-ui-seo-check.py" >/dev/null; }
  verify; RES="$T/out/result.json"
  jq -e '.rows[] | select(.check == "safe_area") | .status == "fail" and (.detail | contains("nav#dole"))' "$RES" >/dev/null
  sed -i 's|</main>|<style>#dole{padding-bottom:env(safe-area-inset-bottom)}</style></main>|' "$SITE/index.html"
  verify; [ "$(st safe_area index.html)" == pass ]
  echo '{"variant":{"type":"web"},"build":{"id":"x","fingerprints":{"index.html":"a","_site":"c"}}}' > "$T/state.json"
  verify; jq -e '.rows[] | select(.check == "safe_area") | .detail | startswith("N/A")' "$RES" >/dev/null
}

@test "FB-30 photo_slots: ratio, round shape, text, screen reader, icon, focus, a photo that moves the page; the right slot passes" {
  mkdir -p "$T/out"
  echo '{"viewports":[390,1440],"browsers":["chromium"],"checks":{"photo_slots":"x"}}' > "$T/ck.json"
  echo '{"variant":{"type":"web"},"build":{"id":"x","fingerprints":{"index.html":"a","_site":"c"}}}' > "$T/state.json"
  w='"where":"Úvod","what":"x","min_px":"1200x1200"'
  echo "[{\"id\":\"a\",\"page\":\"index.html\",\"ratio\":\"4:5\",\"shape\":\"rect\",$w},{\"id\":\"b\",\"page\":\"index.html\",\"ratio\":\"1:1\",\"shape\":\"round\",$w},{\"id\":\"c\",\"page\":\"index.html\",\"ratio\":\"3:2\",\"shape\":\"rect\",$w},{\"id\":\"d\",\"page\":\"index.html\",\"ratio\":\"1:1\",\"shape\":\"rect\",$w}]" > "$T/photos.json"
  cam='<svg data-aid-icon="camera" viewBox="0 0 24 24" width="40" height="40"><path d="M4 7h16v12H4z"/></svg>'
  sed -i "s|</main>|<div data-aid-photo=\"a\" style=\"aspect-ratio:1/1;width:200px\">Foto lékaře</div><div data-aid-photo=\"b\" aria-hidden=\"true\" style=\"position:relative;aspect-ratio:1/1;width:120px\">$cam</div><div data-aid-photo=\"c\" aria-hidden=\"true\" style=\"width:300px;height:200px\"><a href=\"/\">x</a>$cam</div><div data-aid-photo=\"d\" aria-hidden=\"true\" style=\"width:150px\">$cam</div></main>|" "$SITE/index.html"
  url="$(AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" | sed -n 's/^URL: //p')"
  verify() { bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" \
    --base "$url" --out "$T/out" --seo "$SC/aid-ui-seo-check.py" --photos "$T/photos.json" >/dev/null; }
  verify; RES="$T/out/result.json"
  d="$(jq -r '[.rows[] | select(.check == "photo_slots")][0].detail' "$RES")"
  for c in "a: 200×200 is not 4:5" 'a: an empty slot needs aria-hidden' 'a: an empty slot carries text' 'a: an empty slot shows no camera icon' \
           'b: the slot is not round' 'c: an empty slot is focusable' 'c: the photo does not cover the slot' 'd: 150×' ; do
    [[ "$d" == *"$c"* ]] || { echo "missing: $c in $d"; return 1; }; done
  # the right slots: exact ratio, round, aria-hidden, icon only, position relative; a photo put in moves nothing
  cp "$FX/fixed/index.html" "$SITE/index.html"
  sed -i "s|</main>|<div data-aid-photo=\"a\" aria-hidden=\"true\" style=\"position:relative;overflow:hidden;aspect-ratio:4/5;width:200px\">$cam</div><div data-aid-photo=\"b\" aria-hidden=\"true\" style=\"position:relative;overflow:hidden;aspect-ratio:1/1;width:120px;border-radius:50%\">$cam</div><div data-aid-photo=\"c\" aria-hidden=\"true\" style=\"position:relative;aspect-ratio:3/2;width:300px\">$cam</div><div data-aid-photo=\"d\" aria-hidden=\"true\" style=\"position:relative;aspect-ratio:1/1;width:150px\">$cam</div></main>|" "$SITE/index.html"
  verify; [ "$(st photo_slots index.html)" == pass ] || { jq -c '.rows[] | select(.check == "photo_slots")' "$RES"; return 1; }
  # no photos register but a slot on the page: fail; no slot and no register: N/A
  bash "$SC/aid-ui-tool.sh" verify --state "$T/state.json" --checks "$T/ck.json" --site "$SITE" --base "$url" --out "$T/out" --seo "$SC/aid-ui-seo-check.py" >/dev/null
  jq -e '[.rows[] | select(.check == "photo_slots")][0] | .status == "fail" and (.detail | contains("no docs/content/photos.yaml"))' "$RES" >/dev/null
}

@test "P108: copy_review: not_covered without a record, pass with one, fail after a text, facts or context change or a failed review" {
  cp -r "$FX/fixed/." "$SITE/"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st copy_review index.html)" = not_covered ]
  [ "$(jq '[.rows[] | select(.check == "copy_review")] | length' "$RES")" -eq 2 ]   # chromium 1440, one row per page
  copy_reviewed
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st copy_review index.html)" = pass ] && [ "$(st copy_review o-nas/index.html)" = pass ]
  # a text change of one page: that page fails, the other stays
  sed -i 's|Kváskový chleba pečeme každé ráno.|Kváskový chleba pečeme každý den.|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "copy_review" and .page == "index.html") | .status == "fail" and (.detail | contains("text se změnil"))' "$RES" >/dev/null
  [ "$(st copy_review o-nas/index.html)" = pass ]
  copy_reviewed
  printf -- '- claim: nový fakt\n  value: "1"\n  source: PM\n' >> "$PROJ/docs/content/facts.yaml"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "copy_review" and .page == "index.html") | .detail | contains("fakta se změnila")' "$RES" >/dev/null
  copy_reviewed; echo "doplněno" >> "$PROJ/docs/content/product-context.md"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "copy_review" and .page == "index.html") | .detail | contains("podklady se změnily")' "$RES" >/dev/null
  copy_reviewed fail
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '.rows[] | select(.check == "copy_review" and .page == "index.html") | .status == "fail" and (.detail | contains("skóre 3"))' "$RES" >/dev/null
}

@test "P108: registered facts make the planted counts pass in the real gate; only the unregistered price stays" {
  cat >> "$PROJ/docs/content/facts.yaml" <<'YML'
- claim: klienti
  value: "200"
  source: PM
- claim: úspora
  value: "40 %"
  source: PM
- claim: praxe
  value: "15 let"
  source: PM
- claim: e-mail
  value: "info@neexistuje.cz"
  source: PM
YML
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  d="$(jq -r '[.rows[] | select(.check == "facts_match" and .page == "index.html") | .detail][0]' "$RES")"
  [[ "$d" == *"999 Kč"* ]] || { echo "$d"; return 1; }
  for c in "200 klientům" "40 %" "15 let" "info@neexistuje.cz"; do [[ "$d" != *"$c"* ]] || { echo "still named $c: $d"; return 1; }; done
}

@test "P108: --copy-subject: union of 390 and 1440, lang and legal per page; CSS keeps the hash, text changes it" {
  cp -r "$FX/fixed/." "$SITE/"
  sed -i 's|</main>|<p class="jenmobil">Jen na mobilu</p><style>@media (min-width:700px){.jenmobil{display:none}}</style><p style="position:absolute;left:-9999px" aria-hidden="true"><label>PAST NA SPAM<input name="website"></label></p><p style="position:fixed;top:-500px">PAST NAHORE</p><p style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)">Jen pro čtečku</p></main>|' "$SITE/index.html"
  jq '.structure = {pages: [{id:"home", url:"/"}, {id:"o-nas", url:"/o-nas", legal: true}]}' "$PROJ/docs/design/brand-state.json" > "$T/s" && mv "$T/s" "$PROJ/docs/design/brand-state.json"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj1.json"
  [[ "$output" == *"BRÁNA NEBĚŽELA"* ]]   # P108: a texts-only run says so
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.pages["index.html"] | .lang == "cs" and .legal == false and ([.blocks[] | select(.text == "Jen na mobilu")] | length == 1)' "$T/subj1.json" >/dev/null
  jq -e '.pages["o-nas/index.html"].legal == true' "$T/subj1.json" >/dev/null
  # a spam trap pushed off the page is not copy; a clipped screen-reader text inside the page is
  ! grep -q "PAST NA SPAM\|PAST NAHORE" "$T/subj1.json"
  jq -e '[.pages["index.html"].blocks[] | select(.text == "Jen pro čtečku")] | length == 1' "$T/subj1.json" >/dev/null
  # the answer inside a closed <details> is copy (Coufal 11. 10. 2026: ten questions, no answers, page failed)
  sed -i 's|</main>|<details><summary>Bolí to?</summary><p>Odpověď schovaná v details</p></details></main>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj1.json" >/dev/null
  jq -e '[.pages["index.html"].blocks[] | select(.text == "Odpověď schovaná v details")] | length == 1' "$T/subj1.json" >/dev/null
  jq -e '[.pages["index.html"].blocks[].kind] | index("title") != null and index("h1") != null' "$T/subj1.json" >/dev/null
  [ ! -e "$RES" ]   # the subject mode writes no gate result
  # a CSS-only change keeps every page hash
  echo 'body{letter-spacing:.01em}' >> "$SITE/styl.css"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj2.json" >/dev/null
  [ "$(jq -r '.pages["index.html"].sha256' "$T/subj1.json")" = "$(jq -r '.pages["index.html"].sha256' "$T/subj2.json")" ]
  # a text change alters the hash of that page only
  sed -i 's|Kváskový chleba pečeme každé ráno.|Kváskový chleba pečeme každý den.|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj3.json" >/dev/null
  [ "$(jq -r '.pages["index.html"].sha256' "$T/subj2.json")" != "$(jq -r '.pages["index.html"].sha256' "$T/subj3.json")" ]
  [ "$(jq -r '.pages["o-nas/index.html"].sha256' "$T/subj2.json")" = "$(jq -r '.pages["o-nas/index.html"].sha256' "$T/subj3.json")" ]
  # text in a plain div is copy; a second copy of a block changes the hash; a tag change alone does not
  sed -i 's|</main>|<div class="pas">Pečeme od rána</div></main>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj4.json" >/dev/null
  jq -e '[.pages["index.html"].blocks[] | select(.text == "Pečeme od rána")] | length == 1' "$T/subj4.json" >/dev/null
  sed -i 's|<div class="pas">Pečeme od rána</div>|<div class="pas">Pečeme od rána</div><div class="pas">Pečeme od rána</div>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj5.json" >/dev/null
  [ "$(jq -r '.pages["index.html"].sha256' "$T/subj4.json")" != "$(jq -r '.pages["index.html"].sha256' "$T/subj5.json")" ]
  sed -i 's|<p>Kváskový chleba pečeme každý den.|<h2>Kváskový chleba pečeme každý den.|; s|456.</p>|456.</h2>|' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  bash "$SC/aid-ui-verify.sh" "$PROJ" --copy-subject "$T/subj6.json" >/dev/null
  [ "$(jq -r '.pages["index.html"].sha256' "$T/subj5.json")" = "$(jq -r '.pages["index.html"].sha256' "$T/subj6.json")" ]
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

@test "measure reads a hover state at the end of its transition, not half-way (Coufal 11. 10. 2026)" {
  cp -r "$FX/fixed/." "$SITE/"
  sed -i 's|</main>|<a class="btn pomalu" href="/x">Pomalu</a><style>.pomalu{display:inline-block;padding:12px;background:#183870;color:#fff;transition:background-color 3s linear}.pomalu:hover{background:#122a55}</style></main>|' "$SITE/index.html"
  AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" preview "$SITE" >/dev/null
  run bash "$SC/aid-ui-tool.sh" measure "http://127.0.0.1:39927" "$T/measure.json" /
  AID_UI_PROJECT="$PROJ" bash "$SC/aid-ui-serve.sh" stop preview >/dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '[.controls[] | select(.examples | index("Pomalu")) | .states.hover] | length == 1 and (.[0] | startswith("rgb(18, 42, 85)"))' "$T/measure.json" >/dev/null
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

@test "P108 motion rows: motion_settled passes once the intro (data-aid-intro) and finite animations ended and fails when they do not; motion_fidelity is N/A without a reference, fails on a missing inventory or a lost motion, passes with the motion seen" {
  MP="$SC/aid-ui-motion.py"; FXR="$BATS_TEST_DIRNAME/../fixtures/aid-ui/motion-record.json"; MS="$BATS_TEST_DIRNAME/../fixtures/aid-ui/motion-site"
  # the motion fixture as the site: its intro ends after 1.8 s, the reveals through opacity
  rm -rf "$SITE"; cp -r "$MS" "$SITE"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st motion_settled index.html)" == pass ] || { jq -c '.rows[] | select(.check == "motion_settled")' "$RES"; return 1; }
  jq -e '[.rows[] | select(.check == "motion_fidelity")] | length == 1 and all(.[]; .status == "pass" and (.detail | startswith("N/A: no reference picked")))' "$RES" >/dev/null
  # an intro that never ends: motion_settled fails within the cap
  sed -i 's/setTimeout(function(){intro.remove()},1800)/void 0/' "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  [ "$(st motion_settled index.html)" == fail ]
  jq -e '[.rows[] | select(.check == "motion_settled" and .page == "index.html") | .detail] | all(contains("did not end within 10 s"))' "$RES" >/dev/null
  cp "$MS/index.html" "$SITE/index.html"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  # a picked reference: without an inventory the row fails; with the inventory the gate observes the site itself
  jq '.refs = [{"id":"fx","url":"http://127.0.0.1:39931/index.html","picked":true}]' "$PROJ/docs/design/brand-state.json" > "$PROJ/s.t" && mv "$PROJ/s.t" "$PROJ/docs/design/brand-state.json"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '[.rows[] | select(.check == "motion_fidelity")] | all(.[]; .status == "fail" and (.detail | contains("no .aid-ui/motion.json")))' "$RES" >/dev/null || { jq -c '.rows[] | select(.check == "motion_fidelity")' "$RES"; return 1; }
  mkdir -p "$PROJ/.aid-ui/refs"; cp "$FXR" "$PROJ/.aid-ui/refs/fx.motion.json"
  python3 "$MP" inventory "$PROJ" >/dev/null
  python3 - "$PROJ/.aid-ui/motion.json" <<'PY'
import json, sys
p = sys.argv[1]; inv = json.load(open(p))
for i in inv["items"]:
    i["disposition"] = "adopt"; i["target"] = i.get("name") or i.get("property") or "leave,arrive"
json.dump(inv, open(p, "w"), ensure_ascii=False)
PY
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '[.rows[] | select(.check == "motion_fidelity")] | all(.[]; .status == "pass" and (.detail | startswith("PASS: z 9 pohybů vzoru: 9 převzato")))' "$RES" >/dev/null || { jq -c '.rows[] | select(.check == "motion_fidelity")' "$RES"; return 1; }
  # the build loses the spin: the gate names it (the build is re-recorded without the motion proof here:
  # build-record's own motion check is test-aid-ui-state's; the gate re-observes regardless)
  sed -i 's/animation:spin 8s linear infinite/animation:none/' "$SITE/index.html"
  jq '.refs = []' "$PROJ/docs/design/brand-state.json" > "$PROJ/s.t" && mv "$PROJ/s.t" "$PROJ/docs/design/brand-state.json"
  "$SC/aid-ui-state.sh" build-record "$PROJ" "$SITE" >/dev/null
  jq '.refs = [{"id":"fx","url":"http://127.0.0.1:39931/index.html","picked":true}]' "$PROJ/docs/design/brand-state.json" > "$PROJ/s.t" && mv "$PROJ/s.t" "$PROJ/docs/design/brand-state.json"
  run bash "$SC/aid-ui-verify.sh" "$PROJ"
  jq -e '[.rows[] | select(.check == "motion_fidelity")] | all(.[]; .status == "fail" and (.detail | contains("spin")))' "$RES" >/dev/null || { jq -c '.rows[] | select(.check == "motion_fidelity")' "$RES"; return 1; }
}
