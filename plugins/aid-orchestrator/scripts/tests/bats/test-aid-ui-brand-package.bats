#!/usr/bin/env bats
# aid-tier: t1
# P103 extension K3 - aid-ui-brand-package.py: the brand package holds every part the project
# uses, derived from variant.brand/type, options.identity and the contexts of use in the logo
# brief; variants told by whole path tokens; a PM waiver covers exactly the waived missing list.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../../aid-ui-brand-package.py"
  P="$BATS_TEST_TMPDIR/p"; B="$P/docs/design/brand-package"
  mkdir -p "$B"/{symbol,icons,source,logo,lockup}
}

state() {   # state <type> <brand> <identity json> [extra json fields]
  echo "{\"variant\":{\"type\":\"$1\",\"brand\":\"$2\"},\"options\":{\"identity\":$3}${4:+,$4}}" >"$P/docs/design/brand-state.json"
}
contexts() { printf '# Zadání\n\n## Kontexty použití\n\n%s\n\n### Detail\n- hlavička jen jako příklad\n\n## Možné motivy\n- tisk jen jako motiv\n' "$1" >"$P/docs/design/brief-logo-favicon.md"; }
ico() {   # a real ICO directory with 16, 32 and 48 px entries (no image data needed)
  python3 -c 'import struct,sys; d=struct.pack("<HHH",0,1,3)+b"".join(struct.pack("<BBBBHHII",s,s,0,0,1,32,0,0) for s in (16,32,48)); open(sys.argv[1],"wb").write(d)' "$1"
}
full() {   # every part a public web needs
  for f in symbol/s-color.svg symbol/s-black.svg symbol/s-white.svg symbol/s-color-on-dark.svg \
           icons/favicon.svg icons/apple-touch-icon.png icons/icon-192.png icons/icon-512.png brand-brief.md README.md \
           logo/logo-color.svg logo/logo-color.png logo/logo-color-on-dark.svg logo/logo-color-on-dark.png; do
    touch "$B/$f"
  done
  ico "$B/icons/favicon.ico"
  echo '<svg><text>Pekárna</text></svg>' >"$B/source/logo-master.svg"
  echo '<svg><path d="M0 0"/></svg>' >"$B/source/logo-master-outlines.svg"
  web_parts
}
web_parts() {   # P113: what a web links from its <head>, the social preview with an absolute address, the logo motion
  mkdir -p "$B/motion"
  touch "$B/icons/og-image.png" "$B/icons/site.webmanifest" "$B/motion/logo-animace.html"
  echo '<link rel="manifest" href="/site.webmanifest"><meta property="og:image" content="https://pekarna.cz/og-image.png">' >"$B/icons/head-snippet.html"
}

@test "an internal tool (brand none) needs a favicon only; brand none with identity work is exit 2" {
  state webapp none false
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING icons favicon (svg or ico)"* ]]
  touch "$B/icons/favicon.ico"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 0 ]; [ "$(grep -c '^OK ' <<<"$output")" -eq 1 ]
  state webapp none '"new"'
  run python3 "$CHECK" "$P"
  [ "$status" -eq 2 ]; [[ "$output" == *"brand is 'none'"* ]]
}

@test "a public web always needs the logo with the name in colour and on dark, even when no context names it" {
  state web new '"new"'
  contexts '1. Favicon.'
  full
  run python3 "$CHECK" "$P" --json "$BATS_TEST_TMPDIR/b.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.missing == [] and .required == .present and .per_folder.logo == 4 and .waived == false' "$BATS_TEST_TMPDIR/b.json" >/dev/null
  rm "$B"/logo/logo-color-on-dark.*
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING logo logo with the name, dark (SVG)"* ]]
  # print only under '### Detail' of the contexts section counts; under 'Možné motivy' it does not
  ! grep -q 'MISSING logo .*black' <<<"$output"
}

@test "print in the contexts (also under a ### subheading) requires the black logo; a webapp needs colour only" {
  state web new '"new"'
  contexts $'1. Hlavička webu.\n### Tiskoviny\n2. Vizitky.'
  full
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING logo logo with the name, black (SVG)"* ]]
  state webapp new '"new"'
  contexts '1. Favicon.'
  rm "$B"/logo/logo-color-on-dark.*
  run python3 "$CHECK" "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the master keeps live <text>, the outlines version has none; a missing brief section is MISSING" {
  state web new '"new"'
  contexts '1. Favicon.'
  full
  echo '<svg><text>x</text></svg>' >"$B/source/logo-master-outlines.svg"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING source the same in outlines"* ]]
  full
  printf '# Zadání\n\n## Pro koho\n- firmy\n' >"$P/docs/design/brief-logo-favicon.md"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING brief docs/design/brief-logo-favicon.md with a 'Kontexty použití' section"* ]]
}

@test "variants are whole tokens of the path: mobile is not white, concern not black, lockup/a/dark/x is dark" {
  state pwa existing '"package"'
  contexts '1. Instalace na telefon.'
  full
  rm "$B"/symbol/s-white.svg "$B"/symbol/s-black.svg
  touch "$B/symbol/s-mobile-color.svg" "$B/symbol/s-concern.svg" "$B/icons/icon-maskable-512.png"
  mkdir -p "$B/lockup/direction-a/dark" "$B/lockup/direction-a/light"
  touch "$B/lockup/direction-a/dark/lockup.svg" "$B/lockup/direction-a/light/lockup.svg"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING symbol symbol white (SVG)"* ]]
  [[ "$output" == *"MISSING symbol symbol black (SVG)"* ]]
  [[ "$output" == *"OK lockup lockup dark: lockup/direction-a/dark/lockup.svg"* ]]
  [[ "$output" == *"OK lockup lockup light: lockup/direction-a/light/lockup.svg"* ]]
}

@test "favicon.ico must hold 16, 32 and 48 px" {
  state web new '"new"'
  contexts '1. Favicon.'
  full
  : >"$B/icons/favicon.ico"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING icons favicon.ico with 16, 32 and 48 px"* ]]
}

@test "a PM waiver covers exactly the waived missing list; one more missing part voids it" {
  state web existing '"package"' '"brand_package_waiver":{"missing":["source: the same in outlines, no <text> (SVG, named *outlines*)"],"answer":"q-ex"}'
  contexts '1. Favicon.'
  full
  rm "$B/source/logo-master-outlines.svg"
  run python3 "$CHECK" "$P" --json "$BATS_TEST_TMPDIR/b.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"WAIVED source the same in outlines"*"(PM waiver, answer q-ex)"* ]]
  jq -e '.waived == true' "$BATS_TEST_TMPDIR/b.json" >/dev/null
  rm "$B/logo/logo-color.png"
  run python3 "$CHECK" "$P"
  [ "$status" -eq 1 ]; ! grep -q WAIVED <<<"$output"
}

@test "no readable state is a usage error (exit 2)" {
  run python3 "$CHECK" "$P"
  [ "$status" -eq 2 ]; [[ "$output" == *"brand-state.json"* ]]
}

# ---------------------------------------------------------------- P113 step 8
@test "p113: package - a web needs og-image.png, site.webmanifest and a head snippet whose og:image is an absolute address" {
  state web new '"new"'; contexts '1. Hlavička webu.'; full
  run python3 "$CHECK" "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # a relative og:image is not shown by the networks
  echo '<meta property="og:image" content="/og-image.png">' >"$B/icons/head-snippet.html"
  run python3 "$CHECK" "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"MISSING icons head-snippet.html with og:image as an absolute https address"* ]]
  # attribute order and quotes do not matter; an address without a host or with a space in it does not count
  echo "<meta content='https://pekarna.cz/og-image.png' property='og:image'>" >"$B/icons/head-snippet.html"
  run python3 "$CHECK" "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for bad in 'https:///og-image.png' 'https://peka rna.cz/og-image.png' 'https://pekarna.cz/og-image.png.jpg' 'ftp://pekarna.cz/og-image.png'; do
    echo "<meta property=\"og:image\" content=\"$bad\">" >"$B/icons/head-snippet.html"
    run python3 "$CHECK" "$P"; [ "$status" -eq 1 ] || { echo "accepted: $bad"; return 1; }
  done
  web_parts; rm "$B/icons/og-image.png" "$B/icons/site.webmanifest"
  run python3 "$CHECK" "$P"; [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING icons og-image.png"* ]]; [[ "$output" == *"MISSING icons site.webmanifest"* ]]
  # a webapp is not asked for them
  web_parts; rm "$B/icons/og-image.png"; state webapp new '"new"'
  run python3 "$CHECK" "$P"; ! [[ "$output" == *"og-image"* ]]
}

@test "p113: package - the logo motion is required for a web, waived only by the PM's place pohyb without record" {
  state web new '"new"'; contexts '1. Hlavička webu.'; full; rm "$B/motion/logo-animace.html"
  run python3 "$CHECK" "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"MISSING motion logo-animace.html"* ]]
  # a pohyb verdict that is not "without" does not waive it
  state web new '"new"' '"place_verdicts":{"pohyb":{"place":"pohyb","status":"accepted","chosen":"a"}}'
  run python3 "$CHECK" "$P"; [ "$status" -eq 1 ]
  state web new '"new"' '"place_verdicts":{"pohyb":{"place":"pohyb","status":"accepted","without":"q-bez","chosen":null}}'
  run python3 "$CHECK" "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! [[ "$output" == *"logo-animace"* ]]
}

@test "p113: package - contexts as a numbered heading, a bold line or a plain label are read (print asks for the black logo); the main symbol is the largest colour one" {
  state web new '"new"'; full
  for brief in $'# Zadání\n## 3. Kontexty použití\n- vizitky\n## 4. Motivy\n' $'**Kontexty použití:** web a razítko\n**Barvy:** modrá\n' $'Kontexty použití: fax\n\n# Další\n'; do
    printf '%s' "$brief" >"$P/docs/design/brief-logo-favicon.md"
    run python3 "$CHECK" "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"MISSING logo logo with the name, black"* ]] || { echo "not read: $brief"; return 1; }
  done
  # a context after the section is not part of it
  printf '**Kontexty použití:** web\n**Barvy:** tisk modrou\n' >"$P/docs/design/brief-logo-favicon.md"
  run python3 "$CHECK" "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # the 16 px cut first by name, the full mark larger: the main symbol is the full one
  rm "$B/symbol/s-color.svg"
  echo '<svg viewBox="0 0 16 16"></svg>' >"$B/symbol/a-color-16.svg"; echo "<svg viewBox='0 0 5.12e2 512' width='1em'></svg>" >"$B/symbol/b-color.svg"
  run python3 "$CHECK" "$P"; [[ "$output" == *"OK symbol symbol color (SVG), the main one = the largest colour variant: symbol/b-color.svg"* ]]
  # no viewBox: width x height, with a px unit
  echo '<svg width="600px" height="600"></svg>' >"$B/symbol/c-color.svg"
  run python3 "$CHECK" "$P"; [[ "$output" == *"largest colour variant: symbol/c-color.svg"* ]]
}
