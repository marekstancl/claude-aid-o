#!/usr/bin/env bats
# aid-tier: t0
# P103 extension K4 - aid-ui-design-standard.py: the project design standard in the WAN
# structure, written from DESIGN.md + a measurement of the built site, checked for its sections,
# DESIGN.md colour tokens and platform rows. A working document: nothing goes to Docusaurus.

setup() {
  S="$BATS_TEST_DIRNAME/../../aid-ui-design-standard.py"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/docs/design/brand-package"
  echo '{"variant":{"type":"web"},"exceptions":[]}' >"$P/docs/design/brand-state.json"
  printf -- '- **Ochranná zóna:** čtvrtina šířky symbolu.\n- **Reverz:** bílá verze na tmavém;\n  nikdy modrá na modré.\n\nOdstavec.\n' >"$P/docs/design/brand-package/brand-brief.md"
  mkdir -p "$P/.aid-ui"; echo '{"items":[{"id":"kf:a","kind":"keyframes","name":"fade-in","source":{"scenarios":["load"],"where":["hero"],"duration_ms":1200},"disposition":"adopt"},{"id":"tr:x","kind":"transition","property":"color","scenario":"hover","source":{"scenarios":["hover"],"where":["nav"],"duration_ms":300},"disposition":"omit"}]}' >"$P/.aid-ui/motion.json"
  cat >"$P/DESIGN.md" <<'D'
---
name: Pekárna
colors:
  ink: "#1a1a1a"
  flour: "#faf6ee"
typography:
  body:
    fontFamily: "'Geist', system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  control: "4px"
---

## Komponenty
- **Tlačítko** - jedna role.

## Písmo
Geist, licence SIL OFL.

## Kontext provozu
Pekárna v Brně.

## Vzory
- **Formulář** - jeden sloupec.

## Pravidla textů
- Vykání.

## Platformní kontrakt
| | Mobil | Počítač | Tablet |
|---|---|---|---|
| Předěl | jeden sloupec | dva | jako počítač |
| Navigace | pod logem | vpravo | jako počítač |
| Dotyk/kurzor | 44 px | najetí | dotyk |
| Formuláře | jeden sloupec | jeden | jako počítač |
| Systémové okraje | žádné | - | - |
| Gesta | žádná | žádné | - |

Komponenty (tlačítko) se liší jen podle tabulky.
D
  cat >"$BATS_TEST_TMPDIR/m.json" <<'M'
{"pages":["index.html"],"controls":[{"role_key":"x","background":"rgb(26, 26, 26)","color":"rgb(250, 246, 238)","border":"none",
 "radius":"4px","height":{"390":48,"1440":44},"font":{"390":"600 15px","1440":"600 16px"},"count":3,"pages":["index.html"],"examples":["Objednat"],
 "states":{"hover":"rgb(250, 246, 238) / rgb(26, 26, 26)","focus":"rgb(26, 26, 26) / rgb(250, 246, 238) / obrys 2px rgb(26, 26, 26)","disabled":"odkaz"}}],
 "fields":[{"tag":"input[email]","border":"1px rgb(26, 26, 26)","radius":"4px","height":{"390":50,"1440":50},"background":"rgb(250, 246, 238)"}],
 "type":{"p":{"family":"Geist","size":"16px","weight":"400","line":"24px","spacing":"normal"}},"breakpoints":["max-width: 760px"],
 "max_widths":[],"transitions":[],"zindex":[],"reduced_motion_moves":false}
M
}

@test "write composes the WAN structure from DESIGN.md and the measurement; check passes" {
  run python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  D="$P/docs/design/design-standard.md"
  for h in Značka Tokeny Komponenty Vzory "Obsah a terminologie" "Platformní kontrakt" Výjimky Vynucení; do grep -qx "## $h" "$D" || { echo "$h"; return 1; }; done
  grep -q '| `ink` | `#1a1a1a` |' "$D"
  grep -q "| body | \`'Geist', system-ui, sans-serif\` |" "$D"        # quotes inside the value survive
  for h in Barvy Typografie Rozměry Pohyb Ikony Vrstvy Tlačítka "Pole formuláře"; do grep -qx "### $h" "$D" || { echo "$h"; return 1; }; done
  grep -q 'Geist, licence SIL OFL' "$D"                                 # "Písmo" lands under Tokeny
  grep -qx '## Ostatní z DESIGN.md' "$D"; grep -q 'Pekárna v Brně' "$D"  # an unrouted section is never dropped
  grep -q '600 15px / 600 16px' "$D"
  grep -q '`#faf6ee` (flour) / `#1a1a1a` (ink)' "$D"                    # hover state named by tokens
  grep -q '| 1 | `#1a1a1a` (ink) | `#faf6ee` (flour) |' "$D"          # measured role named by its tokens
  grep -q '`signal`\|`design_standard_doc`' "$D"                       # enforcement lists the gate checks
  grep -q '1px `#1a1a1a` (ink)' "$D"
  grep -q 'Ochranná zóna' "$D"
  grep -q '^- \*\*Reverz:\*\* bílá verze na tmavém; nikdy modrá na modré.$' "$D"   # a wrapped bullet is one rule
  ! grep -q '^Odstavec' "$D"
  grep -q '^| fade-in | načtení | 1.2 s |$' "$D"; ! grep -q 'tr:x\|color (transition)' "$D"   # motion by element, adopted only
  grep -q 'Do Docusauru se publikuje až po schválení PM' "$D"
  run python3 "$S" check "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "check: a missing section, a token not as in DESIGN.md, a missing platform row are MISSING; an app needs Okna" {
  python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json" >/dev/null
  D="$P/docs/design/design-standard.md"
  sed -i 's/^## Vynucení$/## Jinak/; s/`#faf6ee` |$/`#ffffff` |/; /^| Gesta/d' "$D"
  run python3 "$S" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING section Vynucení"* ]]
  [[ "$output" == *"MISSING token colors flour = #faf6ee as in DESIGN.md"* ]]
  [[ "$output" == *"MISSING platform row Gesta"* ]]
  python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json" >/dev/null
  echo '{"variant":{"type":"webapp"},"exceptions":[]}' >"$P/docs/design/brand-state.json"
  run python3 "$S" check "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING platform row Okna"* ]]
}

@test "check without the document is MISSING (exit 1); write without --measure is a usage error" {
  run python3 "$S" check "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING docs/design/design-standard.md"* ]]
  run python3 "$S" write "$P"
  [ "$status" -eq 2 ]
}

@test "check: a measured colour that is no token, a component missing in the platform section, an app's flows; a crash is never a pass" {
  python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json" >/dev/null
  D="$P/docs/design/design-standard.md"
  sed -i 's/| 1 | `#1a1a1a` (ink)/| 1 | `#123456`/' "$D"
  sed -i 's/Komponenty (tlačítko) se liší jen podle tabulky./Liší se jen podle tabulky./' "$P/DESIGN.md"
  python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json" >/dev/null
  sed -i 's/| 1 | `#1a1a1a` (ink)/| 1 | `#123456`/' "$D"
  run python3 "$S" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING components measured colour #123456 is a DESIGN.md colour"* ]]
  [[ "$output" == *"MISSING platform component Tlačítko named in Platformní kontrakt"* ]]
  echo '{"variant":{"type":"webapp"},"structure":{"flows":[{"id":"objednavka","states":["prazdny","chyba"]}]},"exceptions":[]}' >"$P/docs/design/brand-state.json"
  python3 "$S" write "$P" --measure "$BATS_TEST_TMPDIR/m.json" >/dev/null
  grep -q '| objednavka | prazdny, chyba |' "$D"
  echo '{"variant":"web"}' >"$P/docs/design/brand-state.json"   # a broken state: exit 2, never a pass
  run python3 "$S" check "$P"
  [ "$status" -eq 2 ]
  printf -- '---\ncolors: none\n---\n' >"$P/DESIGN.md"; echo '{"variant":{"type":"web"}}' >"$P/docs/design/brand-state.json"
  run python3 "$S" check "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"MISSING token DESIGN.md defines at least one token"* ]]
}
