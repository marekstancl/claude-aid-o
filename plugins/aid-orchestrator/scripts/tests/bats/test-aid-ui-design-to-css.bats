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

@test "unsafe token name or value: exit 1 naming it, tokens.css untouched" {
  printf ':root {\n  --color-old: #000;\n}\n' > "$OUT"
  cp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  printf -- '---\ncolors:\n  ok: "#fff"\n  evil: "red; } body { background: url(http://x/y)"\n---\n' > "$BATS_TEST_TMPDIR/v.md"
  run "$SCRIPT" "$BATS_TEST_TMPDIR/v.md" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--color-evil"* ]]
  cmp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  printf -- '---\ncolors:\n  "a:b{": "#fff"\nspacing:\n  s: "@IMPORT x"\n---\n' > "$BATS_TEST_TMPDIR/n.md"
  run "$SCRIPT" "$BATS_TEST_TMPDIR/n.md" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--color-a:b{"* ]]
  cmp "$OUT" "$BATS_TEST_TMPDIR/before.css"
}

@test "CSS escape or resource function in a value: exit 1 naming the token, tokens.css untouched" {
  printf ':root {\n  --color-old: #000;\n}\n' > "$OUT"
  cp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  local v
  for v in '\\75 rl(http://x/y)' 'IMAGE-SET("x.png" 1x)' 'Image(x.png)' 'eXpression(alert(1))'; do
    printf -- '---\ncolors:\n  ok: "#fff"\n  evil: %s\n---\n' "'$v'" > "$BATS_TEST_TMPDIR/e.md"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/e.md" "$OUT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--color-evil"* ]]
    cmp "$OUT" "$BATS_TEST_TMPDIR/before.css"
  done
}
