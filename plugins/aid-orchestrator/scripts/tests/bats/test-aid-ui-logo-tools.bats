#!/usr/bin/env bats
# aid-tier: t2
# T2 because the direction cards render through Chromium, which the merge-path CI jobs do not install.
# P113 step 8 - the logo tools: the roles' direction cards (aid-ui-tool.sh logo-sheet --cards: one card per direction
# with the small and mid cuts and the brief's contexts) and the motion of a finished mark (aid-ui-logo-motion.py: the
# web version within 1 s with the name readable from the first frame, a 2-3 s video version, a seamless end).

setup() {
  PLUG="$BATS_TEST_DIRNAME/../../.."
  TOOL="$PLUG/scripts/aid-ui-tool.sh"; MOT="$PLUG/scripts/aid-ui-logo-motion.py"
  T="$BATS_TEST_TMPDIR"; P="$T/p"; mkdir -p "$P/marks"
  command -v node >/dev/null || skip "node missing"
  ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome >/dev/null 2>&1 || [[ -n "${CHROME:-}" ]] || skip "no Chromium"
  for d in a b; do
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path d="M40 200 L128 40 L216 200 Z"/></svg>' > "$P/marks/$d-symbol.svg"
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 200"><path d="M60 180 L128 60 L196 180 Z"/></svg>' > "$P/marks/$d-mid.svg"   # non-square: accepted
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect x="64" y="64" width="128" height="128"/></svg>' > "$P/marks/$d-small.svg"
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 120"><path d="M10 110 L60 10 L110 110 Z"/><path d="M140 20 h400 v80 h-400 Z"/></svg>' > "$P/marks/$d-lockup.svg"
  done
  cat > "$T/motion.json" <<'J'
{"viewBox": "0 0 256 256", "web_ms": 900, "video_ms": 2500,
 "parts": [{"id": "stena", "d": "M40 200 L40 100 L60 100 L60 200 Z", "strokes": [{"d": "M50 210 L50 90", "width": 20, "delay": 0, "dur": 300}]},
           {"id": "strecha", "d": "M30 110 L128 40 L226 110 L210 120 L128 62 L46 120 Z", "strokes": [{"d": "M30 115 L128 50 L226 115", "width": 18, "delay": 200, "dur": 500}]}],
 "name": {"text": "Pekárna U Mlýna", "x": 20, "y": 245, "size": 22}}
J
}

teardown() { [[ -z "${SRV:-}" ]] || kill "$SRV" 2>/dev/null || true; }

@test "logo-tools: one direction card per direction with the mark, the cuts 48/32/16 and the brief's contexts; none of the studio's reasoning" {
  echo '{"name": "Pekárna U Mlýna", "contexts": ["záložka prohlížeče", "vizitka", "cedule u vchodu"], "directions": [
    {"id": "a", "title": "A", "note": "VNITŘNÍ ÚVAHA STUDIA", "lockup": "marks/a-lockup.svg", "symbol": "marks/a-symbol.svg", "mid": "marks/a-mid.svg", "small": "marks/a-small.svg"},
    {"id": "b", "title": "B", "lockup": "marks/b-lockup.svg", "symbol": "marks/b-symbol.svg"}]}' > "$P/sheet.json"
  run bash "$TOOL" logo-sheet --cards "$P/sheet.json" --root "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -s "$P/.aid-ui/logo/cards/a.png" ] && [ -s "$P/.aid-ui/logo/cards/b.png" ]
  [ "$(ls "$P/.aid-ui/logo/cards" | wc -l)" -eq 2 ]
  python3 -c 'import struct,sys; w,h=struct.unpack(">II",open(sys.argv[1],"rb").read(24)[16:24]); assert w==1400 and h>600,(w,h)' "$P/.aid-ui/logo/cards/a.png"
  # the card page carries the cuts and every context, never the note
  run node -e 'process.exit(0)'   # node present
  ! grep -rq "VNITŘNÍ ÚVAHA" "$P/.aid-ui/logo/cards"
}

@test "logo-tools: the inverted panel shows the brand's light variant when named (a colour mark on black is not its inverse)" {
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path fill="#17463A" d="M40 200 L128 40 L216 200 Z"/></svg>' > "$P/marks/c-symbol.svg"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path fill="#ffffff" d="M40 200 L128 40 L216 200 Z"/></svg>' > "$P/marks/c-white.svg"
  echo '{"name": "X", "directions": [{"id": "c", "title": "C", "lockup": "marks/a-lockup.svg", "symbol": "marks/c-symbol.svg"}]}' > "$P/s0.json"
  bash "$TOOL" logo-sheet --cards "$P/s0.json" --root "$P" >/dev/null; cp "$P/.aid-ui/logo/cards/c.png" "$T/without.png"
  echo '{"name": "X", "directions": [{"id": "c", "title": "C", "lockup": "marks/a-lockup.svg", "symbol": "marks/c-symbol.svg", "inverse": "marks/c-white.svg"}]}' > "$P/s1.json"
  bash "$TOOL" logo-sheet --cards "$P/s1.json" --root "$P" >/dev/null
  ! cmp -s "$T/without.png" "$P/.aid-ui/logo/cards/c.png"
  # the brand's one-colour lockup for the black-and-white panel and each context as the real mark (tab, tile, avatar,
  # door plate, business card, signature) render
  cp "$P/.aid-ui/logo/cards/c.png" "$T/with-inverse.png"
  echo '{"name": "X", "contexts": ["záložka prohlížeče", "ikona na ploše telefonu", "avatar Google profilu", "dveře ambulance", "vizitka", "e-mailový podpis", "hlavička webu"], "directions": [{"id": "c", "title": "C", "lockup": "marks/a-lockup.svg", "symbol": "marks/c-symbol.svg", "inverse": "marks/c-white.svg", "mono": "marks/b-lockup.svg", "lockup_sub": "marks/b-lockup.svg", "tile": "#EEF1EF"}]}' > "$P/s2.json"
  run bash "$TOOL" logo-sheet --cards "$P/s2.json" --root "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! cmp -s "$T/with-inverse.png" "$P/.aid-ui/logo/cards/c.png"
}

@test "logo-tools: a direction without lockup or symbol, or with a raster symbol, is refused" {
  echo '{"name": "X", "directions": [{"id": "a", "title": "A", "lockup": "marks/a-lockup.svg"}]}' > "$P/s1.json"
  run bash "$TOOL" logo-sheet --cards "$P/s1.json" --root "$P"; [ "$status" -eq 2 ]
  printf 'png' > "$P/marks/r.png"
  echo '{"name": "X", "directions": [{"id": "a", "title": "A", "lockup": "marks/a-lockup.svg", "symbol": "marks/r.png"}]}' > "$P/s2.json"
  run bash "$TOOL" logo-sheet --cards "$P/s2.json" --root "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"plain vector SVG"* ]]
}

@test "logo-tools: motion durations - the web version ends within 1 s, the video within 2-3 s; a longer web version is refused" {
  run python3 "$MOT" "$T/motion.json" "$T/m"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.web.draw_end_ms == 900 and .video.draw_end_ms == 2500' "$T/m/motion.json" >/dev/null
  python3 - "$T/m/logo-animace.html" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
ends = [int(a) + int(b) for a, b in re.findall(r"--delay:(\d+)ms;--dur:(\d+)ms", t)]
assert ends and max(ends) <= 1000, ends
PY
  jq '.web_ms = 1500' "$T/motion.json" > "$T/long.json"
  run python3 "$MOT" "$T/long.json" "$T/m2"; [ "$status" -eq 1 ]; [[ "$output" == *"within 1000 ms"* ]]
  jq '.video_ms = 4000' "$T/motion.json" > "$T/long2.json"; run python3 "$MOT" "$T/long2.json" "$T/m3"; [ "$status" -eq 1 ]
}

@test "logo-tools: the name is readable from the first frame and never animated; without JavaScript the final state shows at once" {
  python3 "$MOT" "$T/motion.json" "$T/m" >/dev/null
  grep -q '<text class="name"' "$T/m/logo-animace.html"; ! grep -q 'class="name"[^>]*mask=' "$T/m/logo-animace.html"
  grep -q '\.mark \.name{animation:none}' "$T/m/logo-motion.css"
  grep -q "classList.add('anim')" "$T/m/logo-animace.html"; grep -q 'html.anim .mark .pen' "$T/m/logo-motion.css"
  # in a real browser at the first frame the name has its full opacity and is laid out
  mkdir -p "$T/srv"; cp "$T/m/"* "$T/srv/"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/srv" >/dev/null 2>&1 & SRV=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/logo-animace.html" && break; sleep 0.1; done
  run bash "$TOOL" strip "$T/frames" "http://127.0.0.1:$PORT/logo-animace.html" --every 450 --until 900; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! cmp -s "$T/frames/frame-00000.png" "$T/frames/frame-00900.png"   # the mark is drawn between the first and the last frame
}

@test "logo-tools: a seamless end - every mask stroke overruns its shape with square caps, and the masks switch off when it ends" {
  python3 "$MOT" "$T/motion.json" "$T/m" >/dev/null
  python3 - "$T/m/logo-animace.html" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
pens = re.findall(r'<path class="pen"[^>]*>', t)
assert len(pens) == 2, pens
for p in pens:
    assert 'stroke-linecap="square"' in p, p
widths = [float(w) for w in re.findall(r'stroke-width="([\d.]+)"', " ".join(pens))]
assert widths == [34.0, 32.0], widths   # 20 + 14 and 18 + 14: the overlap of fix 63
assert "--end:900ms" in t
PY
  grep -q '@keyframes aid-unmask{to{mask:none' "$T/m/logo-motion.css"
  jq '.overlap = 0' "$T/motion.json" > "$T/o0.json"; run python3 "$MOT" "$T/o0.json" "$T/m4"; [ "$status" -eq 1 ]; [[ "$output" == *"overlap"* ]]
  jq 'del(.name)' "$T/motion.json" > "$T/nn.json"; run python3 "$MOT" "$T/nn.json" "$T/m5"; [ "$status" -eq 1 ]; [[ "$output" == *"name"* ]]
}

@test "logo-tools: a logo moved by a script (no browser animation) is measured as motion - its end, and null where nothing can be read" {
  printf '<!doctype html><html><body><svg id="l" viewBox="0 0 100 100"><rect id="r" width="0" height="10"/></svg><script>var s=null;function f(t){if(s===null)s=t;var p=Math.min((t-s)/1500,1);document.getElementById("r").setAttribute("width",(100*p).toFixed(1));if(p<1)requestAnimationFrame(f)}requestAnimationFrame(f)</script></body></html>' > "$T/script.html"
  run bash "$TOOL" motion measure "$T/script.html" --variant s --out-dir "$T/m"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.script_driven == true and .web_logo_draw_ms > 1000 and .web_logo_draw_ms < 3000 and .web_logo_name_visible_ms == null and (.not_applicable | not)' "$T/m/metrics-pohyb-s.json" >/dev/null || { cat "$T/m/metrics-pohyb-s.json"; return 1; }
}

@test "logo-tools: a name set in outlines (paths + transform) is drawn as the brand's paths, never animated; other markup in it is refused" {
  jq '.name = {text: "Pekárna", paths: ["M0 0 L10 0 L10 10 Z", "M20 0 h5 v5 z"], transform: "translate(20 230) scale(0.5)", fill: "#17463A"}' "$T/motion.json" > "$T/m2.json"
  run python3 "$MOT" "$T/m2.json" "$T/o2"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '<g class="name" transform="translate(20 230) scale(0.5)" fill="#17463A"><path d="M0 0 L10 0 L10 10 Z"/>' "$T/o2/logo-animace.html"
  ! grep -q '<text class="name"' "$T/o2/logo-animace.html"
  jq '.name.paths = ["M0 0\"/><script>alert(1)</script>"]' "$T/m2.json" > "$T/m3.json"
  run python3 "$MOT" "$T/m3.json" "$T/o3"; [ "$status" -eq 1 ]; [[ "$output" == *"name.paths"* ]]
  jq '.name.transform = "url(javascript:1)"' "$T/m2.json" > "$T/m4.json"
  run python3 "$MOT" "$T/m4.json" "$T/o4"; [ "$status" -eq 1 ]; [[ "$output" == *"name.transform"* ]]
}
