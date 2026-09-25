#!/usr/bin/env bats
# aid-tier: t0
# P101 Step 3 — neutral brand page template: chapters (eleven since P102), fixed --brand-*
# names only, print rules, empty token/role placeholders, state template shape.

setup() {
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh"
  FIX="$BATS_TEST_DIRNAME/../fixtures/aid-ui"
}

@test "all eleven chapter ids present with data-status=ceka, body and status markers" {
  for id in produkt vize logo barvy typografie smer komponenty platformy ukazky seo schvaleni; do
    grep -qF "<section id=\"$id\" data-status=\"ceka\">" "$PAGE/index.html"
    grep -qF "<p class=\"status\"><!-- status:$id --><!-- /status:$id --></p>" "$PAGE/index.html"
    grep -qF "<div class=\"body\"><!-- body:$id --><!-- /body:$id --></div>" "$PAGE/index.html"
    grep -qF "<li><a href=\"#$id\">" "$PAGE/index.html"
  done
  [ "$(grep -c '<section ' "$PAGE/index.html")" -eq 11 ]
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

@test "base.css reads only --brand-* with fallbacks and has print rules" {
  # `|| false`: bats does not fail a test on a mid-test `! cmd`
  ! grep -q -- '--color-' "$PAGE/base.css" || false
  # every var() read is a --brand-* name with a fallback
  run grep -oE 'var\([^)]*\)' "$PAGE/base.css"
  [ "$status" -eq 0 ]
  ! grep -vE '^var\(--brand-[a-z-]+, [^)]+\)$' <<<"$output" || false
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

@test "state template has the required keys including direction" {
  jq -e '.step == 0 and .product_type == "" and has("direction") and .direction == null
    and (.chapters | keys | length == 11) and all(.chapters[]; .status == "ceka")
    and .options == {vision: false, identity: false, seo: false, images: false}
    and .choices == {} and .choice_pending == null and .image_spend == [] and .finished == null
    and (.refs | type == "array") and (.decisions | type == "array")
    and (.impeccable | has("product") and has("design") and has("surface_brief") and has("seed_key"))' \
    "$PAGE/state.template.json"
}

@test "Step 1 script into a copy of brand-page defines --color-paper" {
  cp -R "$PAGE" "$BATS_TEST_TMPDIR/brand"
  run "$SCRIPT" "$FIX/DESIGN.md" "$BATS_TEST_TMPDIR/brand/tokens.css"
  [ "$status" -eq 0 ]
  grep -q -- '--color-paper:' "$BATS_TEST_TMPDIR/brand/tokens.css"
}
