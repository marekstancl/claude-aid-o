#!/usr/bin/env bats
# aid-tier: t1
# P103 extension K5 — aid-ui-customer-page.py: the customer page is made only after a green
# gate of this build, every number follows its source, the SEO tiles are always visible, no
# internal word reaches the customer, and --check (the gate row customer_page) tells a missing,
# stale or hand-edited page apart.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GEN="$SC/aid-ui-customer-page.py"
  P="$BATS_TEST_TMPDIR/proj"; V="$P/.aid-ui/verify"; OUT="$P/docs/zakaznik/index.html"
  mkdir -p "$V/shots/chromium/1440" "$V/shots/chromium/390" "$P/docs/design/brand-package/"{symbol,logo,icons} \
    "$P/docs/content" "$P/docs/seo" "$P/docs/brand/fonts" "$P/site"
  : >"$V/shots/chromium/1440/index.html.png"; : >"$V/shots/chromium/390/index.html.png"
  for f in symbol-color symbol-color-on-dark symbol-black; do echo '<svg/>' >"$P/docs/design/brand-package/symbol/$f.svg"; done
  echo '<svg/>' >"$P/docs/design/brand-package/logo/pekarna-logo-color.svg"
  : >"$P/docs/design/brand-package/icons/favicon-32.png"; : >"$P/docs/design/brand-package/icons/icon-512.png"
  echo '@font-face{font-family:"Geist"}' >"$P/docs/brand/fonts/fonts.css"
  cat >"$P/DESIGN.md" <<'EOF'
---
name: Pekárna
description: Mouka - teplé barvy a velké písmo
colors:
  ink: "#1a1a1a"
  flour: "#faf6ee"
typography:
  body:
    fontFamily: "Geist, sans-serif"
    fontWeight: 400
  heading:
    fontFamily: "Geist, sans-serif"
    fontWeight: 800
---
EOF
  cat >"$P/docs/content/facts.yaml" <<'EOF'
brand: {value: Pekárna U Mlýna, source: x}
audience: {value: sousedé z Brna, source: x}
place: {value: "Brno, Jihomoravský kraj", source: x}
domain: {value: "https://pekarna-mlyn.cz", source: x}
EOF
  echo '{"shared":{"x":1},"home.hero":"a","home.o":"b","o-nas.text":"c"}' >"$P/docs/content/copy.json"
  printf '| URL | H1 | hlavní dotaz |\n|---|---|---|\n| / | Pekárna | kváskový chleba brno (odhad) |\n| /o-nas | O nás | — |\n\n## Politika AI robotů\n- vyhledávání a citace: povolit\n- trénink: zakázat\n' >"$P/docs/seo/brief.md"
  cat >"$P/docs/design/design-standard.md" <<'EOF'
## Komponenty

### Tlačítka

| role | plocha |
|---|---|
| 1 | `#1a1a1a` |

### Pole formuláře

| pole | rámeček |
|---|---|
| input[text] | 1px |

- **Tlačítko** - jedna akce.
- **Patička** - IČO.
- **Tlačítko:** stavy (not a component name).

## Vzory

- **Formulář:** jeden sloupec.

## Platformní kontrakt

- WCAG 2.1 AA: kontrast.

| | Mobil (pod 760 px) | Počítač | Tablet |
|---|---|---|---|
| Předěl | a | b | c |
EOF
  rows='[{"check":"http_200","page":"index.html","viewport":"390","browser":"chromium","status":"pass"},
         {"check":"http_200","page":"index.html","viewport":"1440","browser":"chromium","status":"pass"},
         {"check":"http_200","page":"o-nas/index.html","viewport":"1440","browser":"webkit","status":"pass"},
         {"check":"glyph_coverage","page":"index.html","viewport":"1440","browser":"chromium","status":"warn"},
         {"check":"safe_area","page":"index.html","viewport":"390","browser":"chromium","status":"pass","detail":"N/A: not a PWA"},
         {"check":"customer_page","page":"index.html","viewport":"1440","browser":"chromium","status":"not_covered"}]'
  jq -n --argjson r "$rows" '{build_id:"B1", rows:$r, matrix:[$r[0,1,2] | {page,viewport,browser}]}' >"$V/result.json"
  echo '{"indexable_pages":2,"pages_with_jsonld":2,"jsonld_types":["Bakery","WebPage"],"seo":{"OK":40,"WARN":1,"BLOCKER":0},"ai":{"OK":9,"WARN":0,"BLOCKER":0},"ai_policy":{"ai_search":true,"training":false},"llms_txt":false}' >"$V/seo-summary.json"
  echo '[{"level":"OK","page":"index.html","check":"title"},{"level":"OK","page":"o-nas/index.html","check":"title"},
         {"level":"OK","page":"index.html","check":"meta-description"},{"level":"OK","page":"o-nas/index.html","check":"meta-description"},
         {"level":"OK","page":"index.html","check":"canonical"},{"level":"OK","page":"index.html","check":"ai-content"},
         {"level":"OK","page":"site","check":"sitemap"},{"level":"OK","page":"site","check":"robots"}]' >"$V/seo.json"
  jq -n --arg rf "$V/result.json" '{build:{id:"B1"}, gate:{result_file:$rf}, variant:{type:"web",local:true},
    structure:{pages:[{id:"home",url:"/",h1:"Chleba z kvásku"},{id:"o-nas",url:"/o-nas",h1:"O nás"},{id:"404",url:"/404",h1:"Nenalezeno"}]},
    content_plan:[{id:"a",need:"text",status:"confirmed_client"},{id:"b",need:"fotka pekaře (ráno u pece)",status:"deferred_by_pm"}]}' \
    >"$P/docs/design/brand-state.json"
}

data() { sed -n 's|.*<script type="application/json" id="customer-data">\(.*\)</script>.*|\1|p' "$OUT" | sed 's|<\\/|</|g' | jq -r "$1"; }
# the visible text: scripts and tags out
text() { python3 -c 'import re,sys,html;t=open(sys.argv[1]).read();t=re.sub(r"<script\b.*?</script>|<style\b.*?</style>","",t,flags=re.S);print(html.unescape(re.sub(r"<[^>]+>"," ",t)))' "$OUT"; }

@test "every number follows its source; warn, N/A and customer_page rows are not counted" {
  run python3 "$GEN" "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(data .web.pages)" -eq 3 ]
  [ "$(data .web.checks_passed)" -eq 3 ]
  [ "$(data .web.checked_pages)" -eq 2 ]
  [ "$(data '.web.widths | join(",")')" == "390,1440" ]
  [ "$(data .web.direction)" == "Mouka" ]
  [ "$(data '.brand.symbols | length')" -eq 3 ]
  [ "$(data '.brand.colors | length')" -eq 2 ]
  [ "$(data '.brand.fonts | join(",")')" == "Geist" ]
  [ "$(data '.brand.icon_sizes | join(",")')" == "32,512" ]
  [ "$(data .content.parts)" -eq 3 ] && [ "$(data .content.pages)" -eq 2 ]
  [ "$(data '.content.pending | join(",")')" == "fotka pekaře" ]
  [ "$(data '.rules.components | join(",")')" == "Tlačítko,Patička" ]
  [ "$(data '.rules.platforms | join(",")')" == "Mobil,Počítač,Tablet" ]
  [ "$(data .rules.wcag)" == "WCAG 2.1 AA" ]
  [ "$(data '.visibility.questions | join(",")')" == "kváskový chleba brno" ]
  [ "$(data .visibility.title_desc_ok)" -eq 2 ] && [ "$(data .visibility.canonical_ok)" -eq 1 ]
  [ -f "$P/docs/zakaznik/www/ukazka-1440.png" ] && [ -f "$P/docs/zakaznik/www/pekarna-logo-color.svg" ] && [ -f "$P/docs/zakaznik/www/fonts/fonts.css" ]
  # a source changes, the page follows: one more text part, one more colour
  echo '{"shared":{},"home.hero":"a","home.o":"b","o-nas.text":"c","o-nas.dal":"d"}' >"$P/docs/content/copy.json"
  sed -i 's|  flour: "#faf6ee"|  flour: "#faf6ee"\n  crust: "#8a5a2b"|' "$P/DESIGN.md"
  python3 "$GEN" "$P" >/dev/null
  [ "$(data .content.parts)" -eq 4 ] && [ "$(data '.brand.colors | length')" -eq 3 ]
  text | grep -qE "4 +části textu"
}

@test "the SEO tiles are outside <details>; the AI tile follows the policy; no internal word" {
  python3 "$GEN" "$P" >/dev/null
  # the visibility panel up to its own <details>
  vis="$(python3 -c 'import re,sys;s=open(sys.argv[1]).read();p=re.search(r"id=\"viditelnost\".*?</section>",s,re.S).group(0);print(p.split("<details>")[0])' "$OUT")"
  for s in "40" "2 / 2" "AI připraveno" "trénink modelů zakázán" "Mapa webu" "Brno"; do
    [[ "$vis" == *"$s"* ]] || { echo "not visible: $s"; return 1; }
  done
  grep -q "GPTBot" "$OUT"   # the training robots, named under the details
  # the generator's own internal-word list (robot names like Claude-SearchBot are product names)
  python3 "$GEN" "$P" --check
  # no policy in the gate's summary -> "AI nenastaveno", never "připraveno"
  jq '.ai_policy = null' "$V/seo-summary.json" >"$V/s" && mv "$V/s" "$V/seo-summary.json"
  python3 "$GEN" "$P" >/dev/null
  text | grep -q "AI nenastaveno"
  ! text | grep -q "AI připraveno"
}

@test "refused without a green gate of this build; nothing written; --out into the site refused" {
  jq '.rows[0].status = "fail"' "$V/result.json" >"$V/r" && mv "$V/r" "$V/result.json"
  run python3 "$GEN" "$P"
  [ "$status" -eq 1 ] && [[ "$output" == *"not green"* ]]
  [ ! -f "$OUT" ]
  jq '.rows[0].status = "pass" | .build_id = "OLD"' "$V/result.json" >"$V/r" && mv "$V/r" "$V/result.json"
  run python3 "$GEN" "$P"
  [ "$status" -eq 1 ] && [[ "$output" == *"current build"* ]]
  jq '.build_id = "B1"' "$V/result.json" >"$V/r" && mv "$V/r" "$V/result.json"
  run python3 "$GEN" "$P" --out "$P/site/zakaznik"
  [ "$status" -eq 2 ] && [ ! -d "$P/site/zakaznik" ]
}

@test "--check: missing = 3, fresh = 0, an internal word or another build = 1" {
  run python3 "$GEN" "$P" --check
  [ "$status" -eq 3 ] && [[ "$output" == MISSING* ]]
  python3 "$GEN" "$P" >/dev/null
  run python3 "$GEN" "$P" --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  sed -i 's|<h1>Nedostáváte jen vzhled webu.</h1>|<h1>Schválil PM</h1>|' "$OUT"
  run python3 "$GEN" "$P" --check
  [ "$status" -eq 1 ] && [[ "$output" == *"internal words"*"PM"* ]]
  python3 "$GEN" "$P" >/dev/null
  jq '.build.id = "B2"' "$P/docs/design/brand-state.json" >"$V/s" && mv "$V/s" "$P/docs/design/brand-state.json"
  run python3 "$GEN" "$P" --check
  [ "$status" -eq 1 ] && [[ "$output" == *"another build"* ]]
}

@test "a project without SEO, design standard, brand package or texts: no invented zeros, SEO said honestly" {
  rm -rf "$V/seo-summary.json" "$V/seo.json" "$P/docs/design/design-standard.md" "$P/docs/design/brand-package" "$P/docs/content/copy.json"
  sed -i '/^colors:/,/^typography:/{/^typography:/!d}' "$P/DESIGN.md"
  run python3 "$GEN" "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q 'id="pravidla"' "$OUT"
  ! grep -q 'id="obsah"' "$OUT"
  text | grep -q "není součástí této zakázky"
  ! text | grep -qE '(^|[^0-9])0 +(variant|barev|částí|rolí)'
  # the brand area keeps what exists (the font), the list numbers areas without gaps
  grep -q 'id="znacka"' "$OUT"
  [ "$(grep -o '<span class="n">0[0-9]</span>' "$OUT" | sort -u | wc -l)" -eq 4 ]
  # a font weight that is not a number is skipped, not a crash
  sed -i 's/fontWeight: 400/fontWeight: bold/' "$P/DESIGN.md"
  run python3 "$GEN" "$P"
  [ "$status" -eq 0 ]
}

@test "a gate result edited after it was recorded is refused" {
  sha="$(sha256sum "$V/result.json" | cut -d' ' -f1)"
  jq --arg s "$sha" '.gate.result_sha256 = $s' "$P/docs/design/brand-state.json" >"$V/s" && mv "$V/s" "$P/docs/design/brand-state.json"
  python3 "$GEN" "$P" >/dev/null
  jq '.rows[0].detail = "edited"' "$V/result.json" >"$V/r" && mv "$V/r" "$V/result.json"
  run python3 "$GEN" "$P"
  [ "$status" -eq 1 ] && [[ "$output" == *"changed after it was recorded"* ]]
}
