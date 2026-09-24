#!/usr/bin/env bats
# aid-tier: t0
# P101 Step 1 — aid-ui-design-to-css.sh maps DESIGN.md tokens to CSS variables
# and never overwrites a previous tokens.css on failure.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh"
  FIX="$BATS_TEST_DIRNAME/../fixtures/aid-ui"
  OUT="$BATS_TEST_TMPDIR/tokens.css"
}

@test "converts colors, typography, rounded and spacing with exact names" {
  run "$SCRIPT" "$FIX/DESIGN.md" "$OUT"
  [ "$status" -eq 0 ]
  [ "$(head -n1 "$OUT")" = ":root {" ]
  grep -qxF '  --color-paper: #fcfcfa;' "$OUT"
  grep -qxF '  --color-print: #2456c8;' "$OUT"
  grep -qxF '  --font-display-family: Archivo, sans-serif;' "$OUT"
  grep -qxF '  --font-display-size: clamp(2.6rem, 5.6vw, 5.5rem);' "$OUT"
  grep -qxF '  --font-display-weight: 700;' "$OUT"
  grep -qxF '  --font-display-line-height: 0.98;' "$OUT"
  grep -qxF '  --font-display-letter-spacing: -0.02em;' "$OUT"
  grep -qxF '  --radius-box: 2px;' "$OUT"
  grep -qxF '  --space-sheet: clamp(40px, 6vw, 72px);' "$OUT"
  ! grep -q -e variation -e button "$OUT"
}

@test "no tokens: exit 1 and a pre-existing tokens.css stays byte-identical" {
  printf ':root {\n  --color-old: #000;\n}\n' > "$OUT"
  cp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  run "$SCRIPT" "$FIX/DESIGN-no-tokens.md" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == ERROR:*DESIGN-no-tokens.md* ]]
  cmp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  [ "$(ls "$BATS_TEST_TMPDIR")" = "$(printf 'before.css\ntokens.css')" ]
}

@test "no frontmatter: exit 1 and no output file" {
  printf '# Just prose\n' > "$BATS_TEST_TMPDIR/plain.md"
  run "$SCRIPT" "$BATS_TEST_TMPDIR/plain.md" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == ERROR:* ]]
  [ ! -e "$OUT" ]
}

@test "no arguments: exit 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
