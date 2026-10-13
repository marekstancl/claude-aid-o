#!/usr/bin/env bats
# aid-tier: t1
# P113a (PM 13. 10. 2026) - aid-ui-photos.py: the old site's own photos become the client's choice for each photo
# slot: candidates from fetch.json, the agent marks who is on them before any question, cards closest to the
# slot's shape plus "keep the frame", one answer places the photo (WebP, src/src_from/alt in photos.yaml).

setup() {
  PH="$BATS_TEST_DIRNAME/../../aid-ui-photos.py"; T="$BATS_TEST_TMPDIR"; P="$T/p"
  O="$P/.aid-ui/old-site/www.example.sk"; mkdir -p "$O/img" "$P/docs/content" "$P/docs/design" "$T/bin"
  for f in a b c; do echo "$f" > "$O/img/$f.jpg"; done
  cat > "$O/fetch.json" <<'J'
{"images": [{"url": "https://cdn.example/ordinacia.jpg", "page": "https://www.example.sk/", "alt": "Ordinácia", "file": "img/a.jpg", "width": 1920, "height": 1440},
 {"url": "https://cdn.example/recepcia.jpg", "page": "https://www.example.sk/o-nas/", "alt": "", "file": "img/b.jpg", "width": 1920, "height": 1440},
 {"url": "https://cdn.example/pruh.jpg", "page": "https://www.example.sk/", "alt": "", "file": "img/c.jpg", "width": 700, "height": 233},
 {"url": "https://cdn.example/ikona.png", "page": "https://www.example.sk/", "status": "too small or unreadable"}]}
J
  printf -- '- {id: ambulancia, page: index.html, where: "Úvod", what: "ordinácia bez ľudí", shape: rect, ratio: "4:3", min_px: "1600x1200"}\n' > "$P/docs/content/photos.yaml"
  echo '{"answers": {}}' > "$P/docs/design/brand-state.json"
  # the image tool: webp <src> <out> <width> [q] -> a small file
  printf '#!/usr/bin/env bash\n[[ "$1" == webp ]] || exit 2; echo "webp $4" > "$3"\n' > "$T/bin/tool"; chmod +x "$T/bin/tool"
  export AID_UI_TOOL="$T/bin/tool"
}
answer() { jq --arg q "$1" --arg c "$2" --arg t "$3" '.answers[$q] = {kind: "photos", decision: "choose", choice: $c, target: $t}' "$P/docs/design/brand-state.json" > "$T/s" && mv "$T/s" "$P/docs/design/brand-state.json"; }

@test "candidates, marks before any question, cards by shape with keep, one answer places the photo" {
  run python3 "$PH" candidates "$P"; [ "$status" -eq 0 ]; [ "$(jq '.candidates | length' "$P/.aid-ui/photos/candidates.json")" -eq 3 ]
  run python3 "$PH" question "$P" ambulancia; [ "$status" -eq 1 ]; [[ "$output" == *"look at the photos first"* ]]
  python3 "$PH" mark "$P" c1 --people no >/dev/null; python3 "$PH" mark "$P" c2 --people yes --note "recepčná" >/dev/null
  # c3 (700 px) is under half of min_px 1600: never offered, so it needs no mark
  run python3 "$PH" question "$P" ambulancia; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  q="$output"
  jq -e '.question.kind == "photos" and .question.part == "obsah" and (.question.target | startswith("photo@ambulancia@"))
         and ([.cards[].id] == ["c1", "c2", "keep"]) and (.cards[1].risk | contains("súhlasom")) and (.cards[0].risk | not)
         and (.cards[0].preview | startswith("previews/"))' <<<"$q" >/dev/null
  [ -f "$P/.aid-ui/studio/previews/photo-ambulancia-c1.webp" ]
  # a rerun keeps the marks
  python3 "$PH" candidates "$P" >/dev/null; jq -e '.candidates[1].people == true and .candidates[1].note == "recepčná"' "$P/.aid-ui/photos/candidates.json" >/dev/null
  t="$(jq -r .question.target <<<"$q")"
  answer old c1 "photo@ambulancia@0000"; run python3 "$PH" apply "$P" --answer old; [ "$status" -eq 1 ]; [[ "$output" == *"another question"* ]]
  answer a1 c1 "$t"; run python3 "$PH" apply "$P" --answer a1; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$P/docs/content/photos/ambulancia.webp" ]
  yq -e '.[0].src == "docs/content/photos/ambulancia.webp" and .[0].src_from == "https://cdn.example/ordinacia.jpg" and .[0].alt == "ordinácia bez ľudí"' "$P/docs/content/photos.yaml" >/dev/null
  run python3 "$PH" apply "$P" --answer a1; [ "$status" -eq 1 ]; [[ "$output" == *"already used"* ]]
  # keep: nothing changes
  answer k1 keep "$t"; sed -i 's|src: docs/content/photos/ambulancia.webp|src: x|' "$P/docs/content/photos.yaml"
  python3 "$PH" apply "$P" --answer k1 >/dev/null; yq -e '.[0].src == "x"' "$P/docs/content/photos.yaml" >/dev/null
}
