#!/usr/bin/env bats
# aid-tier: t2
# P102 Step 7 — aid-ui-seo-check.py, the technical SEO gate of /aid-ui step 6.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../../aid-ui-seo-check.py"
  SITE="$BATS_TEST_TMPDIR/site"
  cp -r "$BATS_TEST_DIRNAME/../fixtures/aid-ui/seo-site" "$SITE"
  # titles and descriptions inside the 50-60 / 150-160 bounds
  sed -i -e 's|<title>.*</title>|<title>Pekárna U Mlýna - kváskový chleba a pečivo z Brna.</title>|' \
      -e 's|name="description" content="[^"]*"|name="description" content="Kváskový chleba a pečivo z Brna, pečené každé ráno z mouky od místního mlynáře. Otevřeno denně od šesti, objednávky dortů přijímáme i telefonicky. Těšíme se."|' "$SITE/index.html"
  sed -i -e 's|<title>.*</title>|<title>O nás - kdo peče chleba v Pekárně U Mlýna v Brně!!</title>|' \
      -e 's|name="description" content="[^"]*"|name="description" content="Kdo peče váš chleba a proč jen z kvásku: tři pekaři, jedna pec a mouka z mlýna za městem. Přečtěte si, jak u nás vzniká každý bochník a proč pečeme jen v noci."|' "$SITE/o-nas/index.html"
}

# JSON-LD block replacing the fixture's Bakery block in index.html
ld() { sed -i "/Bakery/s|<script type=\"application/ld+json\">.*</script>|$1|" "$SITE/index.html"; }

fix_site() {
  sed -i '/name="robots"/d' "$SITE/o-nas/index.html"
  sed -i 's|<img src="pekar.jpg">|<img src="pekar.jpg" alt="Pekař">|' "$SITE/o-nas/index.html"
}

@test "fixture reports exactly the planted blocker and warning, exit 1" {
  run python3 "$CHECK" "$SITE" --base-url https://example.cz
  [ "$status" -eq 1 ]
  [ "$(grep -c '^BLOCKER ' <<<"$output")" -eq 1 ]
  [ "$(grep -c '^WARN ' <<<"$output")" -eq 1 ]
  [ "${lines[0]}" = "BLOCKER o-nas/index.html noindex noindex set" ]
  grep -qx 'WARN o-nas/index.html img-alt 1 img without alt' <<<"$output"
}

@test "the fixed copy exits 0 with no blocker or warning" {
  fix_site
  run python3 "$CHECK" "$SITE" --base-url https://example.cz --json "$BATS_TEST_TMPDIR/out.json"
  [ "$status" -eq 0 ]
  ! grep -qE '^(BLOCKER|WARN) ' <<<"$output"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d and all(x["level"]=="OK" for x in d)' "$BATS_TEST_TMPDIR/out.json"
}

@test "an inline SVG with its own <title> in the body does not replace the document title (Coufal 12. 10. 2026)" {
  fix_site
  sed -i 's|<body>|<body><svg role="img"><title>WC-symbol-v1</title><path d="M0 0"/></svg>|' "$SITE/index.html" "$SITE/o-nas/index.html"
  run python3 "$CHECK" "$SITE" --base-url https://example.cz
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q "WC-symbol" <<<"$output"
}

@test "404.html with noindex absent from the sitemap is OK" {
  fix_site
  sed -e 's|<title>.*</title>|<title>Stránka nenalezena</title>|' \
      -e 's|<link rel="canonical"[^>]*>|<meta name="robots" content="noindex"><link rel="canonical" href="https://example.cz/404">|' \
      "$SITE/index.html" >"$SITE/404.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -q '^OK 404.html noindex not-found page, noindex expected' <<<"$output"
  ! grep -q '404.html in-sitemap' <<<"$output"
}

@test "a JSON-LD block with a syntax error is a BLOCKER" {
  fix_site
  sed -i 's|"@type": "Bakery",|"@type": "Bakery"|' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 1 ]
  grep -q '^BLOCKER index.html json-ld block 1:' <<<"$output"
}

@test "--brief naming a missing page is a BLOCKER; matching pages and H1 are OK" {
  fix_site
  printf '| URL | H1 | dotaz |\n|---|---|---|\n| / | Pekárna U Mlýna | pekárna brno |\n| /o-nas | O nás | odhad |\n| /kontakt | Kontakt | odhad |\n' >"$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^BLOCKER ' <<<"$output")" -eq 1 ]
  grep -qx 'BLOCKER /kontakt brief-page confirmed page not built' <<<"$output"
  grep -qx 'OK /o-nas brief-h1 O nás' <<<"$output"
}

@test "canonical pointing elsewhere is a BLOCKER; malformed HTML and unreadable paths do not crash" {
  fix_site
  sed -i 's|https://example.cz/o-nas|https://example.cz/|' "$SITE/o-nas/index.html"
  run python3 "$CHECK" "$SITE" --base-url https://example.cz
  [ "$status" -eq 1 ]
  grep -q '^BLOCKER o-nas/index.html canonical' <<<"$output"
  printf '<html><h1>a</h1><h1>b<<</p></div><title>x' >"$BATS_TEST_TMPDIR/bad.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/bad.html" "$BATS_TEST_TMPDIR/nope.html"
  [ "$status" -eq 1 ]
  grep -q '^WARN .*bad.html h1 2 h1' <<<"$output"
  grep -q '^BLOCKER .*nope.html readable' <<<"$output"
}

@test "no arguments is a usage error, exit 2" {
  run python3 "$CHECK"
  [ "$status" -eq 2 ]
}

@test "--brief reads the page table exactly as 1s-seo.md prescribes it" {
  fix_site
  sed -n '/^ *| URL | H1 |/,/^ *$/p' "$BATS_TEST_DIRNAME/../../../skills/ui-design/steps/1s-seo.md" >"$BATS_TEST_TMPDIR/brief.md"
  [ "$(grep -c '| /' "$BATS_TEST_TMPDIR/brief.md")" -ge 1 ]
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  grep -qx 'OK / brief-h1 Pekárna U Mlýna' <<<"$output"
  grep -q '^WARN / brief-title ' <<<"$output"
  sed -i 's/| Pekárna U Mlýna | Pekárna U Mlýna -/| Pekárna Mlýn | Pekárna U Mlýna -/' "$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 1 ]
  grep -q "^BLOCKER / brief-h1 expected 'Pekárna Mlýn'" <<<"$output"
}

@test "--brief checks only the | URL | H1 | page table; a redirects table is ignored" {
  fix_site
  printf '## Přesměrování\n\n| stará URL | nová URL |\n|---|---|\n| /stara-url | /o-nas |\n| /kontakt-old | /kontakt |\n\n| URL | H1 | dotaz |\n|---|---|---|\n| / | Pekárna U Mlýna | odhad |\n| /o-nas | O nás | odhad |\n' >"$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  ! grep -q '^BLOCKER ' <<<"$output"
  ! grep -q 'stara-url\|kontakt' <<<"$output"
  grep -qx 'OK /o-nas brief-h1 O nás' <<<"$output"
}

@test "--brief with no | URL | H1 | page table is a BLOCKER" {
  fix_site
  printf '| stará URL | nová URL |\n|---|---|\n| /stara-url | /o-nas |\n' >"$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 1 ]
  grep -q '^BLOCKER .*brief.md brief no page table' <<<"$output"
}

@test "a directory with no HTML pages is a BLOCKER" {
  mkdir "$BATS_TEST_TMPDIR/empty"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 1 ]
  grep -q '^BLOCKER .*empty pages no pages found' <<<"$output"
}

@test "decorative alt=\"\" and a bare alt attribute are OK; an img without alt is a WARN" {
  fix_site
  sed -i 's|<img src="pekar.jpg" alt="Pekař">|<img src="a.jpg" alt=""><img src="b.jpg" alt><img src="c.jpg" ALT="">|' "$SITE/o-nas/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -qx 'OK o-nas/index.html img-alt 0 img without alt' <<<"$output"
  sed -i 's|<img src="c.jpg" ALT="">|<img src="c.jpg" title="x">|' "$SITE/o-nas/index.html"
  run python3 "$CHECK" "$SITE"
  grep -qx 'WARN o-nas/index.html img-alt 1 img without alt' <<<"$output"
}

@test "a noindex 404 needs no canonical and no length bounds; an indexable 404 or a normal page does" {
  fix_site
  printf '<html lang="cs"><head><title>Nenalezeno</title><meta name="description" content="Tady nic není."><meta name="robots" content="noindex"></head><body><h1>Nenalezeno</h1></body></html>' >"$SITE/404.html"
  sed 's|<meta name="robots" content="noindex">||' "$SITE/404.html" >"$SITE/not-found.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -qx 'OK 404.html canonical not needed on a noindex not-found page' <<<"$output"
  grep -qx 'OK 404.html title 10 chars' <<<"$output"
  ! grep -q '^WARN 404.html' <<<"$output"
  grep -qx 'WARN not-found.html canonical missing' <<<"$output"
  grep -qx 'WARN not-found.html title 10 chars, 50-60 expected' <<<"$output"
  sed -i 's|<link rel="canonical"[^>]*>||' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  grep -qx 'WARN index.html canonical missing' <<<"$output"
}

@test "title under 50 and description under 150 chars are a WARN; the bounds themselves are OK" {
  fix_site
  sed -i 's|pečivo z Brna.</title>|pečivo z Brna</title>|; s|Těšíme se."|Těšíme s"|' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -qx 'WARN index.html title 49 chars, 50-60 expected' <<<"$output"
  grep -qx 'OK o-nas/index.html title 50 chars' <<<"$output"
  grep -qx 'OK index.html meta-description 155 chars' <<<"$output"
  sed -i 's|Těšíme s"|"|' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  grep -q '^WARN index.html meta-description 14[0-9] chars, 150-160 expected' <<<"$output"
}

@test "duplicate title and description among indexable pages of one language are a WARN on the later page" {
  fix_site
  mkdir "$SITE/kontakt" "$SITE/en" "$SITE/skryta"
  cp "$SITE/index.html" "$SITE/kontakt/index.html"
  sed 's|lang="cs"|lang="en"|' "$SITE/index.html" >"$SITE/en/index.html"
  sed 's|<head>|<head><meta name="robots" content="noindex">|' "$SITE/index.html" >"$SITE/skryta/index.html"
  run python3 "$CHECK" "$SITE"
  grep -qx 'WARN kontakt/index.html duplicate-title same as index.html' <<<"$output"
  grep -qx 'WARN kontakt/index.html duplicate-description same as index.html' <<<"$output"
  [ "$(grep -c ' duplicate-' <<<"$output")" -eq 2 ]
}

@test "--brief compares title and description (dash and spacing style ignored); a brief without descriptions skips with a note" {
  fix_site
  printf '| URL | H1 | title | meta description |\n|---|---|---|---|\n| / | Pekárna U Mlýna | Pekárna U Mlýna – kváskový  chleba a pečivo z Brna. | Jiný popis. |\n' >"$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  grep -q '^OK / brief-title ' <<<"$output"
  grep -q "^WARN / brief-description expected 'Jiný popis.'" <<<"$output"
  grep -q '^OK .*brief.md brief-json-ld no json-ld column, comparison skipped' <<<"$output"
  printf '| URL | H1 | title |\n|---|---|---|\n| / | Pekárna U Mlýna | Pekárna |\n' >"$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  grep -q '^OK .*brief.md brief-description no meta description column, comparison skipped' <<<"$output"
  grep -q "^WARN / brief-title expected 'Pekárna'" <<<"$output"
}

@test "--brief JSON-LD column: each type on the page is checked, over two blocks and @graph" {
  fix_site
  sed -i 's|</head>|<script type="application/ld+json">{"@context": "https://schema.org", "@type": "BreadcrumbList"}</script></head>|' "$SITE/index.html"
  b() { printf '| URL | H1 | JSON-LD |\n|---|---|---|\n| / | Pekárna U Mlýna | %s |\n' "$1" >"$BATS_TEST_TMPDIR/brief.md"; }
  b 'Bakery, BreadcrumbList'
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  grep -qx 'OK / brief-json-ld Bakery, BreadcrumbList' <<<"$output"
  b 'Bakery'
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  grep -qx 'WARN / brief-json-ld not in brief BreadcrumbList' <<<"$output"
  b 'LocalBusiness, BreadcrumbList'
  ld '<script type="application/ld+json">{"@context": "https://schema.org", "@graph": [{"@type": "Bakery"}]}</script>'
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  grep -qx 'WARN / brief-json-ld missing LocalBusiness; not in brief Bakery' <<<"$output"
}

@test "meta keywords and self-serving aggregateRating are a WARN; a rating on a Product is not" {
  fix_site
  sed -i 's|</head>|<meta name="keywords" content="chleba, pekárna"></head>|' "$SITE/o-nas/index.html"
  ld '<script type="application/ld+json">[{"@context": "https://schema.org", "@type": "Bakery", "aggregateRating": {"ratingValue": 5}}, {"@context": "https://schema.org", "@type": "Product", "aggregateRating": {"ratingValue": 4}}]</script>'
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -q '^WARN o-nas/index.html meta-keywords present' <<<"$output"
  grep -qx 'WARN index.html aggregate-rating self-serving on Bakery' <<<"$output"
  [ "$(grep -c 'aggregate-rating' <<<"$output")" -eq 1 ]
  ld '<script type="application/ld+json">{"@context": "https://schema.org", "@graph": [{"@type": ["Organization", "Store"], "aggregateRating": {}}]}</script>'
  run python3 "$CHECK" "$SITE"
  grep -qx 'WARN index.html aggregate-rating self-serving on Organization/Store' <<<"$output"
}

@test "NAP in JSON-LD must be in the visible text: spacing ignored, hidden text does not count, a wrong phone is a BLOCKER" {
  fix_site
  nap='{"@context": "https://schema.org", "@type": "Bakery", "name": "Pekárna U Mlýna", "telephone": "+420 777 123 456", "address": {"@type": "PostalAddress", "streetAddress": "Mlýnská 5", "postalCode": "60200", "addressLocality": "Brno"}}'
  ld "<script type=\"application/ld+json\">$nap</script>"
  sed -i 's|</body>|<p>Mlýnská\&nbsp;5, 602 00 Brno, tel. 777 123 456</p></body>|' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 0 ]
  grep -qx 'OK index.html nap JSON-LD matches visible text' <<<"$output"
  sed -i 's|777 123 456</p>|777 123 457</p>|' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 1 ]
  grep -qx 'BLOCKER index.html nap not in visible text: telephone' <<<"$output"
  sed -i -e 's|<p>Mlýnská&nbsp;5, 602 00 Brno, tel. 777 123 457</p>|<p>602 00 Brno, tel. 777 123 456</p>|' \
      -e 's|<title>|<title>Mlýnská 5 |' "$SITE/index.html"
  run python3 "$CHECK" "$SITE"
  [ "$status" -eq 1 ]
  grep -qx 'BLOCKER index.html nap not in visible text: streetAddress' <<<"$output"
}

@test "Letokruh trial site: no WARN for decorative alt or for canonical on the noindex 404" {
  run python3 "$CHECK" "$BATS_TEST_DIRNAME/../fixtures/aid-ui/letokruh-site"
  [ "$status" -eq 0 ]
  ! grep -qE '^WARN .* (img-alt|canonical) ' <<<"$output"
  grep -qx 'OK 404.html canonical not needed on a noindex not-found page' <<<"$output"
}

# ---- P103 extension K2: --ai (the gate's ai_search row) and the site-level WARN checks ----
LOREM="Pečeme kváskový chleba každou noc z mouky od mlynáře za městem. Recept se nemění třicet let a každý bochník kyne přes noc, aby měl chuť a vydržel celý týden čerstvý. Otevřeno denně od šesti."
ai_page() {   # ai_page <dir> <title> <jsonld or ''> [extra head] [body]
  mkdir -p "$1"
  cat >"$1/index.html" <<HTML
<!doctype html><html lang="cs"><head><title>$2</title>$4
${3:+<script type="application/ld+json">$3</script>}</head>
<body><main>${5:-<h1>$2</h1><p>$LOREM</p><p><a href="/kontakt/">Kontakt</a> <a href="/">Úvod</a></p>}</main></body></html>
HTML
}
ORG='{"@context":"https://schema.org","@graph":[{"@type":"Bakery","@id":"#org","name":"Pekárna","identifier":"12345678"},{"@type":"WebPage","publisher":{"@id":"#org"},"dateModified":"2026-10-01"}]}'
ai_site() {
  S="$BATS_TEST_TMPDIR/ai"; mkdir -p "$S"
  ai_page "$S" "Kváskový chleba z Brna - Pekárna" "$ORG"
  ai_page "$S/kontakt" "Kontakt - Pekárna" "$ORG"
  cat >"$S/robots.txt" <<R
User-agent: *
Allow: /
R
  for b in OAI-SearchBot ChatGPT-User Claude-SearchBot Claude-User PerplexityBot Perplexity-User; do printf 'User-agent: %s\nAllow: /\n\n' "$b" >>"$S/robots.txt"; done
  for b in GPTBot Google-Extended ClaudeBot CCBot; do printf 'User-agent: %s\nDisallow: /\n\n' "$b" >>"$S/robots.txt"; done
  echo '{"brand":{"value":"Pekárna"},"ico":{"value":"12345678"}}' >"$BATS_TEST_TMPDIR/facts.json"
  printf '| URL | H1 |\n|---|---|\n\n## Politika AI robotů\n- vyhledávání a citace: povolit\n- trénink: zakázat\n' >"$BATS_TEST_TMPDIR/brief.md"
}
ai() { run python3 "$CHECK" "$S" --ai --facts "$BATS_TEST_TMPDIR/facts.json" --brief "$BATS_TEST_TMPDIR/brief.md" "$@"; }

@test "K2 --ai: a site that follows the policy has no ai-* blocker; the summary counts it" {
  ai_site
  ai --summary "$BATS_TEST_TMPDIR/sum.json"
  ! grep -E '^BLOCKER .* ai-' <<<"$output"
  grep -q "^OK index.html ai-entity IČO in identifier" <<<"$output"
  grep -q '^OK robots.txt ai-robots GPTBot: blocked' <<<"$output"
  grep -q '^OK robots.txt ai-robots OAI-SearchBot: allowed' <<<"$output"
  jq -e '.indexable_pages == 2 and .pages_with_jsonld == 2 and .ai_policy == {"ai_search": true, "training": false} and .ai.BLOCKER == 0' "$BATS_TEST_TMPDIR/sum.json" >/dev/null
}

@test "K2 --ai: no policy in the brief, a robot without its own group, a blocked search engine or a policy mismatch is a BLOCKER" {
  ai_site
  printf '| URL | H1 |\n|---|---|\n' >"$BATS_TEST_TMPDIR/brief.md"
  ai; [ "$status" -eq 1 ]; grep -q '^BLOCKER brief ai-policy' <<<"$output"
  ai_site
  sed -i '/User-agent: CCBot/,+1d' "$S/robots.txt"
  ai; grep -q '^BLOCKER robots.txt ai-robots CCBot: allowed, no own User-agent group' <<<"$output"
  ai_site
  printf 'User-agent: Googlebot\nDisallow: /\n' >>"$S/robots.txt"
  ai; grep -q '^BLOCKER robots.txt ai-robots Googlebot blocked' <<<"$output"
  ai_site
  sed -i 's/- trénink: zakázat/- trénink: povolit/' "$BATS_TEST_TMPDIR/brief.md"
  ai; grep -q '^BLOCKER robots.txt ai-robots GPTBot: blocked; the policy says allow' <<<"$output"
}

@test "K2 --ai: a page without JSON-LD, the IČO in taxID, another brand name, JS-only content and nosnippet are BLOCKERs" {
  ai_site
  ai_page "$S/kontakt" "Kontakt - Pekárna" ""
  ai; grep -q '^BLOCKER kontakt/index.html ai-jsonld no JSON-LD block' <<<"$output"
  ai_site
  # the publisher inline (nested), another name and the IČO in taxID; a client organisation is not compared
  ai_page "$S" "Kváskový chleba z Brna - Pekárna" '{"@context":"https://schema.org","@graph":[{"@type":"WebPage","publisher":{"@type":"Bakery","name":"Jiná","taxID":"12345678"}},{"@type":"Organization","name":"Klient s.r.o.","identifier":"99999999"}]}'
  ai; grep -q 'ai-entity the IČO is in taxID' <<<"$output"
  grep -q "ai-entity organisation name 'Jiná', facts say 'Pekárna'" <<<"$output"
  ! grep -q "Klient" <<<"$output"
  ai_site
  ai_page "$S" "Kváskový chleba z Brna - Pekárna" '{"@context":"https://schema.org","@type":"Bakery","name":"Pekárna","identifier":"12345678"}'
  ai; grep -q '^BLOCKER index.html ai-jsonld no WebPage-like node' <<<"$output"
  ai_site
  ai_page "$S/kontakt" "Kontakt - Pekárna" "$ORG" "" '<div id="app"></div><a href="/">Úvod</a>'
  ai; grep -q '^BLOCKER kontakt/index.html ai-content' <<<"$output"
  ai_page "$S/kontakt" "Kontakt - Pekárna" "$ORG" "" '<h1>Kontakt</h1><p>Zavolejte nebo napište, odpovíme do druhého dne.</p><a href="/">Úvod</a>'
  ai; grep -q '^OK kontakt/index.html ai-content' <<<"$output"   # a short real page is fine
  ai_site
  ai_page "$S/kontakt" "Kontakt - Pekárna" "$ORG" '<meta name="robots" content="nosnippet">'
  ai; grep -q '^BLOCKER kontakt/index.html ai-snippet nosnippet' <<<"$output"
}

@test "K2 --ai: llms.txt needs 'llms.txt: ano' in the brief; build without --ai runs no ai-* check" {
  ai_site
  echo "# Pekárna" >"$S/llms.txt"
  ai; grep -q '^BLOCKER llms.txt ai-llms present without' <<<"$output"
  echo '- llms.txt: ano' >>"$BATS_TEST_TMPDIR/brief.md"
  ai; grep -q '^OK llms.txt ai-llms present, agreed' <<<"$output"
  run python3 "$CHECK" "$S"
  ! grep -q ' ai-' <<<"$output"
}

@test "K2 site WARN: hidden text, a page not linked, near-duplicate pages, brand first in a title, missing hreflang" {
  ai_site
  ai_page "$S/praha" "Kváskový chleba Praha - Pekárna" "$ORG"
  ai_page "$S/schovane" "Pekárna - schovaná stránka" "$ORG" "" "<h1>x</h1><p>$LOREM</p><a href=\"/kontakt/\">k</a><div style=\"display: none\">Levný chleba Brno levný chleba Praha levný</div>"
  run python3 "$CHECK" "$S" --facts "$BATS_TEST_TMPDIR/facts.json"
  grep -q '^WARN schovane/index.html hidden-text' <<<"$output"
  grep -q '^WARN schovane/index.html click-depth not linked from the site' <<<"$output"
  grep -q 'near-duplicate text differs from' <<<"$output"
  grep -q '^WARN schovane/index.html title-brand-order brand first' <<<"$output"
  ! grep -q ' hreflang ' <<<"$output"
  sed -i 's/lang="cs"/lang="en"/' "$S/praha/index.html"
  run python3 "$CHECK" "$S"
  grep -q '^WARN praha/index.html hreflang site has 2 languages' <<<"$output"
}

@test "P113a site WARN: with --facts place, a description without the place is named; legal pages and pages naming it pass" {
  ai_site
  ai_page "$S/cennik" "Ceník chleba - Pekárna" "$ORG" '<meta name="description" content="Ceny chleba a pečiva Pekárny.">'
  ai_page "$S/onas" "O nás - Pekárna" "$ORG" '<meta name="description" content="Pekárna v Brně peče od roku 2015.">'
  ai_page "$S/ochrana-udaju" "Ochrana údajů - Pekárna" "$ORG" '<meta name="description" content="Jak zpracujeme osobní údaje.">'
  echo '{"brand":{"value":"Pekárna"},"ico":{"value":"12345678"},"place":{"value":"Brno"}}' >"$BATS_TEST_TMPDIR/facts.json"
  run python3 "$CHECK" "$S" --facts "$BATS_TEST_TMPDIR/facts.json"
  grep -q '^WARN cennik/index.html description-place the description does not name Brno' <<<"$output"
  grep -q '^OK onas/index.html description-place names Brno' <<<"$output"   # "Brně" counts
  ! grep -q 'ochrana-udaju/index.html description-place' <<<"$output"
}

@test "K2 --ai: the policy counts only when the PM approved this brief (--state seo_brief answer for its sha256)" {
  ai_site
  sha="$(sha256sum "$BATS_TEST_TMPDIR/brief.md" | cut -d' ' -f1)"
  echo "{\"answers\":{\"q-seo\":{\"kind\":\"seo_brief\",\"decision\":\"approve\",\"target\":\"docs/seo/brief.md@$sha\"}}}" >"$BATS_TEST_TMPDIR/state.json"
  ai --state "$BATS_TEST_TMPDIR/state.json"
  grep -q '^OK brief ai-policy the PM approved this brief' <<<"$output"
  # a card chosen on the question bound to this brief counts the same (the brief as shown; 9. 10. 2026)
  echo "{\"answers\":{\"q-seo\":{\"kind\":\"seo_brief\",\"decision\":\"choose\",\"choice\":\"a\",\"target\":\"docs/seo/brief.md@$sha\"}}}" >"$BATS_TEST_TMPDIR/state.json"
  ai --state "$BATS_TEST_TMPDIR/state.json"
  grep -q '^OK brief ai-policy the PM approved this brief' <<<"$output"
  echo "{\"answers\":{\"q-seo\":{\"kind\":\"seo_brief\",\"decision\":\"return\",\"target\":\"docs/seo/brief.md@$sha\"}}}" >"$BATS_TEST_TMPDIR/state.json"
  ai --state "$BATS_TEST_TMPDIR/state.json"
  grep -q '^BLOCKER brief ai-policy the brief is not the one the PM approved' <<<"$output"
  echo "- poznámka agenta" >>"$BATS_TEST_TMPDIR/brief.md"   # changed after the approval
  ai --state "$BATS_TEST_TMPDIR/state.json"
  grep -q '^BLOCKER brief ai-policy the brief is not the one the PM approved' <<<"$output"
}

@test "K2 --ai: robots.txt with a BOM and Disallow: /*, a ### subheading in the policy, an agreed snippet ban, facts without brand" {
  ai_site
  sed -i 's|^Disallow: /$|Disallow: /*|' "$S/robots.txt"
  printf '\xef\xbb\xbf' | cat - "$S/robots.txt" >"$S/r" && mv "$S/r" "$S/robots.txt"
  printf '| URL | H1 |\n|---|---|\n\n## Politika AI robotů\n### Proč\nText.\n- vyhledávání a citace: povolit\n- trénink: zakázat\n- úryvky: zakázat\n' >"$BATS_TEST_TMPDIR/brief.md"
  ai_page "$S/kontakt" "Kontakt - Pekárna" "$ORG" '<meta name="robots" content="nosnippet">'
  echo '{"ico":{"value":"12345678"}}' >"$BATS_TEST_TMPDIR/facts.json"
  ai
  ! grep -E '^BLOCKER .* ai-' <<<"$output"
  grep -q '^OK robots.txt ai-robots GPTBot: blocked' <<<"$output"
  grep -q '^OK kontakt/index.html ai-snippet nosnippet (agreed in the brief)' <<<"$output"
  grep -q '^WARN index.html ai-entity organisation not checked: the facts register has no brand' <<<"$output"
}
