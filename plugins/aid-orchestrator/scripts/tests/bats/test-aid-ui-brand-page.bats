#!/usr/bin/env bats
# aid-tier: t2
# P101 Step 3 — neutral brand page template: chapters (fourteen since P103, fifteen since P108: podklady), fixed --brand-*
# names only, print rules, empty token/role placeholders, state template shape.
# P103 Step 6 — kvalita summary written through aid-ui-state.sh body; studio links /report.

setup() {
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh"
  FIX="$BATS_TEST_DIRNAME/../fixtures/aid-ui"
}

@test "all fifteen chapter ids present with data-status=ceka, body and status markers" {
  for id in produkt podklady vize logo barvy typografie smer komponenty platformy ukazky seo struktura obsah kvalita schvaleni; do
    grep -qF "<section id=\"$id\" data-status=\"ceka\">" "$PAGE/index.html"
    grep -qF "<p class=\"status\"><!-- status:$id --><!-- /status:$id --></p>" "$PAGE/index.html"
    grep -qF "<div class=\"body\"><!-- body:$id --><!-- /body:$id --></div>" "$PAGE/index.html"
    grep -qF "<li><a href=\"#$id\">" "$PAGE/index.html"
  done
  [ "$(grep -c '<section ' "$PAGE/index.html")" -eq 15 ]
  # page order = aid-ui-state.sh CHAPTERS order
  chapters="$(sed -n 's/^CHAPTERS=" \(.*\) "$/\1/p' "$BATS_TEST_DIRNAME/../../aid-ui-state.sh")"
  [ "$(grep -o '<section id="[a-z]*"' "$PAGE/index.html" | cut -d'"' -f2 | tr '\n' ' ')" = "$chapters " ]
}

@test "kvalita: summary numbers from soulad-summary.json land in the chapter via aid-ui-state.sh body" {
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/docs/brand" "$P/docs/design"
  cp "$PAGE/index.html" "$P/docs/brand/"
  "$BATS_TEST_DIRNAME/../../aid-ui-state.sh" init "$P" >/dev/null
  # fresh chapter: no summary yet -> čeká
  grep -qF '<section id="kvalita" data-status="ceka">' "$P/docs/brand/index.html"
  cat > "$P/docs/design/soulad-summary.json" <<'JSON'
{"generated_at": "2026-09-28", "variant": "web", "build_id": "b1", "total": 9,
 "counts": {"použito, ověřil skript": 4, "použito, rozhodl PM": 1, "ověřil agent": 1, "nepoužito": 2, "nesplněno (skript)": 1},
 "by_standard": {}}
JSON
  jq -r '.counts as $c | ([$c | to_entries[] | select(.key | startswith("použito") or . == "ověřil agent") | .value] | add) as $a
    | "<dl><dt>Použito</dt><dd>\($a)</dd><dt>Nepoužito s důvodem</dt><dd>\($c["nepoužito"] // 0)</dd>"
    + "<dt>Kontrola</dt><dd>\(.generated_at)</dd></dl>"' "$P/docs/design/soulad-summary.json" > "$BATS_TEST_TMPDIR/kvalita.html"
  run "$BATS_TEST_DIRNAME/../../aid-ui-state.sh" body "$P" kvalita --file "$BATS_TEST_TMPDIR/kvalita.html"
  [ "$status" -eq 0 ]
  body="$(tr -d '\n' < "$P/docs/brand/index.html" | sed -n 's/.*<!-- body:kvalita -->\(.*\)<!-- \/body:kvalita -->.*/\1/p')"
  [[ "$body" == *"<dt>Použito</dt><dd>6</dd>"* ]]
  [[ "$body" == *"<dt>Nepoužito s důvodem</dt><dd>2</dd>"* ]]
  [[ "$body" == *"<dd>2026-09-28</dd>"* ]]
  # other chapters untouched
  grep -qF '<!-- body:obsah --><!-- /body:obsah -->' "$P/docs/brand/index.html"
}

@test "fonts markers inside head" {
  sed -n '/<head>/,/<\/head>/p' "$PAGE/index.html" | grep -qx '<!-- fonts -->'
  sed -n '/<head>/,/<\/head>/p' "$PAGE/index.html" | grep -qx '<!-- /fonts -->'
}

@test "tokens.css, roles.css, base.css linked in that order" {
  run grep -o 'href="[a-z]*\.css"' "$PAGE/index.html"
  [ "$status" -eq 0 ]
  [ "$output" = $'href="tokens.css"\nhref="roles.css"\nhref="base.css"' ]
}

@test "base.css reads only its own frame tokens or --brand-* with fallbacks and has print rules" {
  # `|| false`: bats does not fail a test on a mid-test `! cmd`
  ! grep -q -- '--color-' "$PAGE/base.css" || false
  # every var() read is the frame's own --p-* (defined in base.css) or a --brand-* name with a fallback
  run grep -oE 'var\([^)]*\)' "$PAGE/base.css"
  [ "$status" -eq 0 ]
  ! grep -vE '^var\(--brand-[a-z-]+, [^)]+\)$|^var\(--p-[a-z]+\)$' <<<"$output" || false
  for v in $(grep -oE 'var\(--p-[a-z]+\)' "$PAGE/base.css" | sort -u | sed 's/var(\(.*\))/\1/'); do
    grep -q -- "^  $v:" "$PAGE/base.css"
  done
  grep -q '@media print' "$PAGE/base.css"
  grep -q 'break-before: page' "$PAGE/base.css"
  # print block caps image height so a full-page screenshot fits one A4 page
  sed -n '/@media print/,/^}/p' "$PAGE/base.css" | grep -qE 'img \{[^}]*max-height: 100mm'
}

@test "shipped tokens.css and roles.css define no custom property" {
  # a definition is `--name:`; the comments may mention names in prose
  ! grep -qE -- '--[a-z-]+ *:' "$PAGE/tokens.css" || false
  ! grep -qE -- '--[a-z-]+ *:' "$PAGE/roles.css" || false
}

@test "state template has the Data Model keys and no Impeccable fields" {
  jq -e '.step == 0 and .product_type == "" and .variant == null and .structure == null
    and .content_plan == [] and .answers == {} and .consumed == [] and .attestations == {}
    and .build == null and .approvals == {} and .gate == null and .exceptions == []
    and (.chapters | keys | length == 15) and all(.chapters[]; .status == "ceka")
    and (.chapters | has("kvalita") and has("struktura") and has("obsah"))
    and .options == {vision: false, identity: false, seo: false, images: false}
    and .finished == null and (.refs | type == "array") and (.decisions | type == "array")
    and (has("impeccable") or has("image_spend") or has("direction") or has("choices") | not)' \
    "$PAGE/state.template.json"
}

@test "Step 1 script into a copy of brand-page defines --color-paper" {
  cp -R "$PAGE" "$BATS_TEST_TMPDIR/brand"
  run "$SCRIPT" "$FIX/DESIGN.md" "$BATS_TEST_TMPDIR/brand/tokens.css"
  [ "$status" -eq 0 ]
  grep -q -- '--color-paper:' "$BATS_TEST_TMPDIR/brand/tokens.css"
}
