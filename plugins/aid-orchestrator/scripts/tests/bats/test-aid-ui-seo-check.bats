#!/usr/bin/env bats
# aid-tier: t0
# P102 Step 7 — aid-ui-seo-check.py, the technical SEO gate of /aid-ui step 6.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../../aid-ui-seo-check.py"
  SITE="$BATS_TEST_TMPDIR/site"
  cp -r "$BATS_TEST_DIRNAME/../fixtures/aid-ui/seo-site" "$SITE"
}

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
  [ "$(grep -c '| /' "$BATS_TEST_TMPDIR/brief.md")" -eq 2 ]
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  grep -qx 'OK / brief-h1 Pekárna U Mlýna' <<<"$output"
  grep -qx 'OK /o-nas brief-h1 O nás' <<<"$output"
  sed -i 's/| O nás |/| O pekárně |/' "$BATS_TEST_TMPDIR/brief.md"
  run python3 "$CHECK" "$SITE" --brief "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 1 ]
  grep -q "^BLOCKER /o-nas brief-h1 expected 'O pekárně'" <<<"$output"
}
