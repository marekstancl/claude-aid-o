#!/usr/bin/env bats
# aid-tier: t2
# Nightly since 3.4.0 (15. 10. 2026): over the T1 budget, the dearest suites outside the core go nightly (standard).
# Step 1i, concepts by an image model (PM 7. 10. 2026): aid-ui-logo-gen.py sends only the fixed
# constraints plus the slot's concept, never without the key, never over the caps; --dry-run writes
# plan.json and sends nothing; aid-ui-tool.sh vectorize turns a concept PNG into one plain black
# SVG symbol and refuses a speck; the sheet refuses a raster or a raster-wrapping SVG as a symbol.

setup() {
  PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  GEN="$PLUGIN/scripts/aid-ui-logo-gen.py"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.aid-ui/logo" "$P/.aid-ui/studio"
  echo '{"situation":"new","slots":[{"id":"W","kind":"wordmark"},{"id":"WC","kind":"name+sign"},{"id":"WP","kind":"name+pictorial"}]}' > "$P/.aid-ui/logo/route.json"
  spec() { printf '{"mode": "mark", "n": %s, "slots": %s}' "$1" "$2" > "$P/.aid-ui/logo/gen.json"; }
  unset OPENAI_API_KEY
}

@test "gen: --dry-run writes plan.json with the constraints, the mark type and the concept per slot; sends nothing; gen.json untouched" {
  spec 2 '{"WC": "a C whose counter is a tooth crown", "WP": "a roof over two figures"}'
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$P/.aid-ui/logo/gen/plan.json" ]; [ ! -e "$P/.aid-ui/logo/gen/gen.json" ]
  pr="$(jq -r '.slots.WC.prompt' "$P/.aid-ui/logo/gen/plan.json")"
  [[ "$pr" == *"single solid pure black"* && "$pr" == *"transparent background"* && "$pr" == *"No text"* ]]
  [[ "$pr" == *"Mark type: name+sign."* && "$pr" == *"Concept: a C whose counter is a tooth crown"* ]]
  [ "$(jq -r '.requested' "$P/.aid-ui/logo/gen/plan.json")" -eq 4 ]
  [ "$(jq -r '.status + " " + .price_list' "$P/.aid-ui/logo/gen/plan.json")" = "planned $(python3 -c "import re;print(re.search(r'PRICE_LIST = \"([^\"]+)\"', open('$GEN').read()).group(1))")" ]
  # full mode (the default): the complete logo in colour with the name, tagline and palette in the prompt; name required
  printf '{"n": 1, "name": "Firma s.r.o.", "tagline": "pekárna · Brno", "palette": "warm ochre", "slots": {"WC": "a loaf as a letter F"}}' > "$P/.aid-ui/logo/gen.json"
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pr="$(jq -r '.slots.WC.prompt' "$P/.aid-ui/logo/gen/plan.json")"
  [[ "$pr" == *'company "Firma s.r.o."'* && "$pr" == *'tagline "pekárna · Brno"'* && "$pr" == *"(warm ochre)"* && "$pr" == *"pure white"* ]]
  [ "$(jq -r .mode "$P/.aid-ui/logo/gen/plan.json")" = full ]
  printf '{"n": 1, "slots": {"WC": "x"}}' > "$P/.aid-ui/logo/gen.json"
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 2 ]; [[ "$output" == *"needs name"* ]]
  # two steps (the mark first, then the lockup around exactly that mark): two prompts per slot, typography and colours in the lockup prompt
  printf '{"n": 1, "two_step": true, "name": "Firma", "tagline": "pekárna · Brno", "typography": "a warm serif", "colors": "ochre #C08A2E, ink #222", "slots": {"WC": "a loaf as a letter F"}}' > "$P/.aid-ui/logo/gen.json"
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  m="$(jq -r '.slots.WC.prompt.mark' "$P/.aid-ui/logo/gen/plan.json")"; l="$(jq -r '.slots.WC.prompt.lockup' "$P/.aid-ui/logo/gen/plan.json")"
  [[ "$m" == "Brand mark only"* && "$m" == *"a loaf as a letter F"* && "$m" == *"16 px"* && "$m" == *"ochre #C08A2E"* && "$m" == *"No text"* ]]
  [[ "$l" == "Using the attached brand mark exactly as it is"* && "$l" == *'wordmark "Firma"'* && "$l" == *"a warm serif"* && "$l" == *'tagline "pekárna · Brno"'* ]]
}

@test "gen: no key -> exit 1 naming the variable; a slot outside the route, n over 10, n x slots over 60, a bad model -> exit 2" {
  spec 2 '{"WC": "x"}'
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json; [ "$status" -eq 1 ]; [[ "$output" == *"OPENAI_API_KEY"* ]]
  spec 2 '{"ZZ": "x"}'; run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 2 ]; [[ "$output" == *"not in route.json"* ]]
  spec 11 '{"WC": "x"}'; run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 2 ]
  echo '{"situation":"x","slots":[{"id":"A","kind":"k"},{"id":"B","kind":"k"},{"id":"C","kind":"k"},{"id":"D","kind":"k"},{"id":"E","kind":"k"},{"id":"F","kind":"k"},{"id":"G","kind":"k"}]}' > "$P/.aid-ui/logo/route.json"
  spec 10 '{"A":"x","B":"x","C":"x","D":"x","E":"x","F":"x","G":"x"}'
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 2 ]; [[ "$output" == *"<= 60"* ]]
  printf '{"model": "dall-e-9", "mode": "mark", "slots": {"A": "x"}}' > "$P/.aid-ui/logo/gen.json"
  run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --dry-run; [ "$status" -eq 2 ]; [[ "$output" == *"not wired"* ]]
  # with a key but an unreachable API host the run fails cleanly, records the error without the key, exit 1
  spec 1 '{"A": "x"}'
  OPENAI_API_KEY=sk-test-secret-0000 run python3 "$GEN" "$P" --spec .aid-ui/logo/gen.json --max-cost 0.001
  [ "$status" -eq 1 ]; [[ "$output" == *"cost cap"* ]]; ! grep -rq "sk-test-secret" "$P/.aid-ui/logo/gen/"
}

@test "vectorize: a concept PNG becomes one plain black SVG symbol with viewBox 256 that the audit passes; a speck is refused" {
  V="${AID_UI_PYVEC:-$HOME/.cache/aid-ui/pyvec}"
  [ -x "$V/bin/python" ] || skip "vectorizer venv not installed here (first use installs it)"
  "$V/bin/python" - "$P/c.png" "$P/speck.png" <<'PY'
import sys
from PIL import Image, ImageDraw
im = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse((200, 200, 824, 824), fill=(0, 0, 0, 255)); d.ellipse((380, 380, 644, 644), fill=(0, 0, 0, 0)); d.rectangle((512, 460, 900, 564), fill=(0, 0, 0, 0))
im.save(sys.argv[1])
s = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255)); ImageDraw.Draw(s).ellipse((500, 500, 520, 520), fill=(0, 0, 0, 255)); s.save(sys.argv[2])
PY
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" vectorize "$P/c.png" "$P/c.svg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'viewBox="0 0 256 256"' "$P/c.svg"; grep -q 'fill="#111"' "$P/c.svg"; ! grep -qiE '<image|<text|href=' "$P/c.svg"
  grep -q 'aid-ui-vectorize: vtracer' "$P/c.svg"
  # P113a: the C (a ring cut on the right) mirrors top-bottom: measured, above 0.92
  [[ "$output" == *"SYMMETRY"* ]]; jq -e '.symmetry.tb > 0.95 and .symmetry.axis == "horizontal"' "$P/c.svg.json" >/dev/null
  run python3 "$PLUGIN/skills/ui-design/references/adopted/logo-design/scripts/svg_audit.py" "$P/c.svg"
  [ "$status" -eq 0 ]; ! grep -q 'FAIL' <<<"$output"
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" vectorize "$P/speck.png" "$P/speck.svg"; [ "$status" -eq 1 ]; [[ "$output" == *"speck"* ]]
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" vectorize "$P/missing.png" "$P/x.svg"; [ "$status" -eq 1 ]
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" vectorize "$P/c.png" "$P/x.txt"; [ "$status" -eq 2 ]
}

@test "logo-sheet: a symbol that is a PNG or an SVG wrapping a raster is refused; the lockup may carry live text" {
  command -v node >/dev/null || skip "node not installed"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><circle cx="128" cy="128" r="100" fill="#111"/></svg>' > "$P/.aid-ui/logo/ok.svg"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><text x="10" y="100" font-family="Manrope">Firma</text></svg>' > "$P/.aid-ui/logo/lock.svg"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><image href="data:image/png;base64,iVBORw0KGgo=" width="256" height="256"/></svg>' > "$P/.aid-ui/logo/wrap.svg"
  printf '\x89PNG\r\n\x1a\n' > "$P/.aid-ui/logo/raster.png"
  sheet() { printf '{"name":"F","out_dir":".aid-ui/studio","directions":[{"id":"a","title":"A","lockup":".aid-ui/logo/lock.svg","symbol":"%s"}]}' "$1" > "$P/.aid-ui/logo/sheet.json"; bash "$PLUGIN/scripts/aid-ui-tool.sh" logo-sheet --spec .aid-ui/logo/sheet.json --root "$P"; }
  run sheet .aid-ui/logo/wrap.svg; [ "$status" -eq 1 ]; [[ "$output" == *"plain vector SVG"* ]]
  run sheet .aid-ui/logo/raster.png; [ "$status" -eq 1 ]
  run sheet .aid-ui/logo/ok.svg; [ "$status" -eq 0 ] || { echo "$output"; return 1; }; [ -s "$P/.aid-ui/studio/logo-a.png" ]
  # P113a: a symbol measured as asymmetric stops the sheet unless the direction states why
  echo '{"symmetry": {"lr": 0.58, "tb": 0.82, "best": 0.82, "axis": "horizontal"}}' > "$P/.aid-ui/logo/ok.svg.json"
  run sheet .aid-ui/logo/ok.svg; [ "$status" -eq 1 ]; [[ "$output" == *"only 0.82 symmetric"* ]]
  printf '{"name":"F","out_dir":".aid-ui/studio","directions":[{"id":"a","title":"A","asymmetry":"zub v otvore C, zámerne","lockup":".aid-ui/logo/lock.svg","symbol":".aid-ui/logo/ok.svg"}]}' > "$P/.aid-ui/logo/sheet.json"
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" logo-sheet --spec .aid-ui/logo/sheet.json --root "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
