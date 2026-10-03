#!/usr/bin/env bats
# aid-tier: t0
# P103 extension K1b - aid-ui-vision-check.py: docs/product-vision.md carries the parts of the
# product-vision template, FAKT labels, an owner and a date (the gate's vision_doc row).

setup() {
  S="$BATS_TEST_DIRNAME/../../aid-ui-vision-check.py"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/docs"
  cat >"$P/docs/product-vision.md" <<'V'
# Pekárna - jádro vize
Vlastník: Jana Nováková. Datum: 3. 10. 2026.
**Elevator pitch:** kváskový chleba pro Brno.
## Problém, pro koho, dnešní náhrada
- **FAKT (zadání):** lidé chtějí chleba bez přísad.
## Podle čeho se pozná úspěch
## Klíčové funkce
## Ekosystém
## Konkurence
## Legislativa
## Hranice
V
}

@test "a vision with every part passes" {
  run python3 "$S" "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a missing part, no FAKT label, no owner or no date is MISSING" {
  sed -i '/^## Hranice/d; s/FAKT/fakt/; s/^Vlastník: Jana Nováková. Datum: 3. 10. 2026./Jana./' "$P/docs/product-vision.md"
  run python3 "$S" "$P"
  [ "$status" -eq 1 ]
  for w in "part: boundaries" "at least one claim marked FAKT" "owner" "date"; do [[ "$output" == *"MISSING vision $w"* ]] || { echo "$w"; return 1; }; done
}

@test "no vision file is MISSING; no argument is a usage error" {
  rm "$P/docs/product-vision.md"
  run python3 "$S" "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING vision docs/product-vision.md"* ]]
  run python3 "$S"
  [ "$status" -eq 2 ]
}
