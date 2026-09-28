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
