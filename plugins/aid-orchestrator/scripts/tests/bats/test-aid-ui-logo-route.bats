#!/usr/bin/env bats
# aid-tier: t2
# Nightly since 3.4.0 (15. 10. 2026): the merge path overran its 10 min and the /aid-ui studio is the
# dearest area outside the core; no plan run passes through it, so a regression here shows the next morning.
# Step 1i Rozcestník (PM 7. 10. 2026: "to musí říkat ten skill"): aid-ui-logo-route.py decides the
# situation, the direction slots, the contexts and the scoring from the project state alone; the
# studio refuses an identity question whose cards are not one per slot; aid-ui-tool.sh logo-sheet
# renders every direction where it will live plus the overview with the competitors.

setup() {
  PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  ROUTE="$PLUGIN/scripts/aid-ui-logo-route.py"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/docs/design" "$P/.aid-ui/studio"
}

state() { printf '{"variant":%s,"options":{"identity":%s},"answers":{}}' "$1" "$2" > "$P/docs/design/brand-state.json"; }
old_site() { mkdir -p "$P/.aid-ui/old-site/www.x.sk"; echo '{"pages":[{"url":"https://www.x.sk/","status":200,"file":"index.html"}]}' > "$P/.aid-ui/old-site/www.x.sk/fetch.json"; }
png() {   # png <file> <width>: a PNG header only, width in IHDR
  python3 - "$1" "$2" <<'PY'
import struct, sys
w = int(sys.argv[2])
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", w, 100) + b"\x08\x06\x00\x00\x00")
PY
}

@test "route: package -> assets (0), webapp/pwa -> app (3), web with an old site -> redesign (5), web alone -> new (3); first match wins" {
  state '{"type":"web","brand":"new"}' '"package"'; old_site
  [ "$(python3 "$ROUTE" "$P" | jq -r '.situation + " " + (.direction_count|tostring)')" = "assets 0" ]
  state '{"type":"pwa","brand":"new"}' '"new"'
  [ "$(python3 "$ROUTE" "$P" | jq -r '.situation + " " + ([.slots[].id] | join(","))')" = "app L,S,P" ]
  state '{"type":"web","brand":"new","local":true}' '"new"'
  [ "$(python3 "$ROUTE" "$P" | jq -r '.situation + " " + ([.slots[].id] | join(","))')" = "redesign R,W,WC,WM,WP" ]
  rm -r "$P/.aid-ui/old-site"
  [ "$(python3 "$ROUTE" "$P" | jq -r '.situation + " " + ([.slots[].id] | join(","))')" = "new W,WC,WP" ]
  # an unknown variant type or no state: exit 1
  state '{"type":"desktop"}' '"new"'; run python3 "$ROUTE" "$P"; [ "$status" -eq 1 ]
  rm "$P/docs/design/brand-state.json"; run python3 "$ROUTE" "$P"; [ "$status" -eq 1 ]
}

@test "route: every slot kind is unique; the current logo decides slot R (usable svg or raster >= 400 px, else wordmark-continuity); local adds the category rule" {
  state '{"type":"web","brand":"new","local":true}' '"new"'; old_site
  r="$(python3 "$ROUTE" "$P")"
  [ "$(jq -r '[.slots[].kind] | length == (unique | length)' <<<"$r")" = true ]
  [ "$(jq -r '.slots[0].kind' <<<"$r")" = "wordmark-continuity" ]          # no current logo
  [ "$(jq -r '.inputs.current_logo.state' <<<"$r")" = absent ]
  grep -q 'místní služba' <<<"$(jq -r '.slots[] | select(.kind == "name+sign") | .text' <<<"$r")"
  mkdir -p "$P/.aid-ui/logo"; png "$P/.aid-ui/logo/dnesni-logo.png" 300
  [ "$(python3 "$ROUTE" "$P" | jq -r '.inputs.current_logo.state + " " + .slots[0].kind')" = "reference-only wordmark-continuity" ]
  png "$P/.aid-ui/logo/dnesni-logo.png" 1200
  [ "$(python3 "$ROUTE" "$P" | jq -r '.inputs.current_logo.state + " " + .slots[0].kind')" = "usable revitalization" ]
  state '{"type":"web","brand":"new","local":false}' '"new"'
  ! grep -q 'místní služba' <<<"$(python3 "$ROUTE" "$P" | jq -r '.slots[] | select(.kind == "name+sign") | .text')"
}

@test "route: contexts = the situation's test contexts plus the brief's list; continuity bonus only when evidenced; --write stores route.json" {
  state '{"type":"web","brand":"new","local":true}' '"new"'; old_site
  r="$(python3 "$ROUTE" "$P")"
  [ "$(jq -c '.contexts' <<<"$r")" = '["hlavička webu","záložka prohlížeče 16 px","avatar v kroužku","tisk černobíle"]' ]
  [ "$(jq -r '.scoring.continuity_bonus.eligible' <<<"$r")" = null ]     # no facts: not_evidenced
  printf '## Kde bude značka žít\n\n1. Web - hlavička.\n2. Ikona na ploše telefonu.\n3. E-mailový podpis.\n\n## Dál\n' > "$P/docs/design/brief-logo-favicon.md"
  mkdir -p "$P/docs/content"; printf 'recenzie_pocet: {value: 47, source: "x"}\nrok_jmena: {value: 2019, source: "x"}\n' > "$P/docs/content/facts.yaml"
  r="$(python3 "$ROUTE" "$P" --write)"
  [ "$(jq -c '.contexts' <<<"$r")" = '["hlavička webu","záložka prohlížeče 16 px","avatar v kroužku","tisk černobíle","ikona na telefonu","podpis v e-mailu"]' ]
  [ "$(jq -r '.scoring.continuity_bonus.eligible' <<<"$r")" = true ]
  printf 'recenzie_pocet: {value: 3, source: "x"}\nrok_jmena: {value: 2025, source: "x"}\n' > "$P/docs/content/facts.yaml"
  [ "$(python3 "$ROUTE" "$P" | jq -r '.scoring.continuity_bonus.eligible')" = false ]
  [ "$(jq -r '.situation' "$P/.aid-ui/logo/route.json")" = redesign ]
  [ "$(jq -r '.scoring.weights.relevance' "$P/.aid-ui/logo/route.json")" = 2 ]
  state '{"type":"webapp"}' '"new"'; [ "$(python3 "$ROUTE" "$P" | jq -r '.scoring.weights.small_size')" = 2 ]
}

@test "studio: an identity question needs route.json and exactly one card per slot, each with its slot" {
  SERVER="$PLUGIN/lib/aid-ui-studio/server.py"
  echo 0123456789abcdef0123456789abcdef > "$P/.aid-ui/studio.token"
  state '{"type":"web","brand":"new","local":true}' '"new"'; old_site
  mkdir -p "$P/.aid-ui/method"
  python3 - "$SERVER" "$P/.aid-ui/method/identity.json" <<'PY'
import hashlib, json, os, sys
plug = os.path.normpath(os.path.join(os.path.dirname(sys.argv[1]), "..", ".."))
m = json.load(open(os.path.join(plug, "skills", "ui-design", "sections.json")))["methods"]["identity"]
files = [{"path": x, "sha256": hashlib.sha256(open(os.path.join(plug, x), "rb").read()).hexdigest()} for x in m["files"]]
json.dump({"kind": "identity", "files": files, "at": "2020-01-01T00:00:00Z"}, open(sys.argv[2], "w"))
PY
  pay() { printf '{"questions":[{"id":"i","kind":"identity","target":"t","opened_at":"2020-01-01T01:00:00Z"}],"cards":[%s]}' "$1" > "$P/.aid-ui/studio/payload.json"; python3 "$SERVER" --check --project "$P" 2>&1; }
  c() { printf '{"id":"%s","question":"i","method":"mark-types.md","slot":"%s"}' "$1" "$2"; }
  run pay "$(c a R)"; [ "$status" -eq 1 ]; [[ "$output" == *"no .aid-ui/logo/route.json"* ]]
  python3 "$ROUTE" "$P" --write >/dev/null
  run pay "$(c a R),$(c b W),$(c c WC)"; [ "$status" -eq 1 ]; [[ "$output" == *"one card per slot"* ]]
  run pay "$(c a R),$(c b W),$(c c WC),$(c d WM),$(c e WM)"; [ "$status" -eq 1 ]
  run pay "$(c a R),$(c b W),$(c c WC),$(c d WM),$(c e WP)"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  rm -r "$P/.aid-ui/old-site"; python3 "$ROUTE" "$P" --write >/dev/null   # three slots now
  run pay "$(c a W),$(c b WC),$(c c WP)"; [ "$status" -eq 0 ]
}

@test "logo-sheet: one card PNG per direction and the overview with the competitors; a missing file or a bad id refuses" {
  command -v node >/dev/null || skip "node not installed"
  mkdir -p "$P/.aid-ui/logo" "$P/.aid-ui/refs/competitors"
  for f in a-lockup a-symbol b-lockup b-symbol comp; do
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><circle cx="128" cy="128" r="100" fill="#111"/></svg>' > "$P/.aid-ui/logo/$f.svg"
  done
  cat > "$P/.aid-ui/logo/sheet.json" <<'JSON'
{"name": "Firma", "out_dir": ".aid-ui/studio", "recommend": "b",
 "directions": [{"id": "a", "title": "A · Nápis", "note": "jedna věta", "lockup": ".aid-ui/logo/a-lockup.svg", "symbol": ".aid-ui/logo/a-symbol.svg"},
                {"id": "b", "title": "B · Znak", "note": "jedna věta", "lockup": ".aid-ui/logo/b-lockup.svg", "symbol": ".aid-ui/logo/b-symbol.svg"}],
 "competitors": [{"name": "Konkurent", "image": ".aid-ui/logo/comp.svg"}]}
JSON
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" logo-sheet --spec .aid-ui/logo/sheet.json --root "$P"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for f in logo-a.png logo-b.png logo-prehled.png; do [ -s "$P/.aid-ui/studio/$f" ] || { echo "no $f"; return 1; }; done
  # the overview is 1600 wide, a card 1200 (PNG IHDR)
  w() { python3 -c "import struct,sys; print(struct.unpack('>I', open(sys.argv[1],'rb').read(24)[16:20])[0])" "$1"; }
  [ "$(w "$P/.aid-ui/studio/logo-prehled.png")" -eq 1600 ]; [ "$(w "$P/.aid-ui/studio/logo-a.png")" -eq 1200 ]
  jq '.directions[0].symbol = ".aid-ui/logo/missing.svg"' "$P/.aid-ui/logo/sheet.json" > "$P/.aid-ui/logo/bad.json"
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" logo-sheet --spec .aid-ui/logo/bad.json --root "$P"; [ "$status" -eq 1 ]
  jq '.directions[0].id = "A B"' "$P/.aid-ui/logo/sheet.json" > "$P/.aid-ui/logo/bad.json"
  run bash "$PLUGIN/scripts/aid-ui-tool.sh" logo-sheet --spec .aid-ui/logo/bad.json --root "$P"; [ "$status" -eq 2 ]
}
