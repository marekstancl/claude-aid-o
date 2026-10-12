#!/usr/bin/env bats
# aid-tier: t1
# P108 motion inventory — scripts/aid-ui-motion.py: the inventory from the picked reference's
# record, the check against an observed record (every adopt/replace seen in its scenario and
# place, reasons and labels where the rules want them, dir sha bound), summary and dirsha.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; MP="$SC/aid-ui-motion.py"
  FXR="$BATS_TEST_DIRNAME/../fixtures/aid-ui/motion-record.json"
  P="$BATS_TEST_TMPDIR/proj"; mkdir -p "$P/docs/design" "$P/.aid-ui/refs"
  echo '{"refs":[{"id":"fx","url":"http://127.0.0.1:39931/index.html","picked":true}]}' > "$P/docs/design/brand-state.json"
}

fill() {   # every item adopt with its own name as target
  python3 - "$P/.aid-ui/motion.json" <<'PY'
import json, sys
p = sys.argv[1]; inv = json.load(open(p))
for i in inv["items"]:
    i["disposition"] = "adopt"; i["target"] = i.get("name") or i.get("property") or "leave,arrive"
json.dump(inv, open(p, "w"), ensure_ascii=False)
PY
}

@test "inventory: needs the picked reference's record of the same url and the schema; one item per keyframe, transition group, page; never overwrites dispositions without --force" {
  run python3 "$MP" inventory "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"no motion record of the picked reference"* ]]
  jq '.url = "http://jiny.example/"' "$FXR" > "$P/.aid-ui/refs/fx.motion.json"
  run python3 "$MP" inventory "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"the picked reference is"* ]]
  jq 'del(.coverage)' "$FXR" > "$P/.aid-ui/refs/fx.motion.json"
  run python3 "$MP" inventory "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"breaks motion-record.schema.json"* ]]
  cp "$FXR" "$P/.aid-ui/refs/fx.motion.json"
  run python3 "$MP" inventory "$P"
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.items[].id] | join(" ")' "$P/.aid-ui/motion.json")" == "kf:leave kf:pop kf:fadeup kf:spin tr:background-color@hover tr:color@hover tr:background-color@focus tr:color@focus page" ]
  [ "$(jq -r '.items[] | select(.id == "kf:spin") | .source.where[0], .source.iteration' "$P/.aid-ui/motion.json" | paste -sd' ')" == "below infinite" ]
  [ "$(jq -r '[.items[] | .disposition] | unique | join(",")' "$P/.aid-ui/motion.json")" == "" ]
  fill
  run python3 "$MP" inventory "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"already has dispositions"* ]]
  python3 "$MP" inventory "$P" --force >/dev/null
  [ "$(jq -r '[.items[] | .disposition] | unique | join(",")' "$P/.aid-ui/motion.json")" == "" ]
}

@test "check: passes against the record it came from; names a missing keyframe, a motion seen only above the fold, a lost second-load run; replace and omit need reason and label; extra needs a reason and must be seen; summary counts" {
  cp "$FXR" "$P/.aid-ui/refs/fx.motion.json"; python3 "$MP" inventory "$P" >/dev/null
  run python3 "$MP" check "$P" --observed "$FXR"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:leave: disposition missing"* ]]
  fill
  run python3 "$MP" check "$P" --observed "$FXR" --write "$P/chk.json"
  [ "$status" -eq 0 ]; [[ "$output" == "PASS: z 9 pohybů vzoru: 9 převzato, 0 nahrazeno, 0 vynecháno" ]]
  [ "$(jq -r '.ok, .counts.total, (.inventory_sha256 | length)' "$P/chk.json" | paste -sd' ')" == "true 9 64" ]
  jq '.keyframes |= map(select(.name != "spin")) | .keyframes |= map(if .name == "fadeup" then .where = ["hero"] elif .name == "pop" then .frequency = "first_load_only" else . end)' "$FXR" > "$P/obs.json"
  jq '(.items[] | select(.id == "kf:pop") | .frequency) = "every_load" | (.items[] | select(.id == "kf:pop") | .source.frequency) = "every_load"' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$P/obs.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kf:spin: keyframes 'spin' never ran"* && "$output" == *"kf:fadeup: 'fadeup' was never seen below"* && "$output" == *"kf:pop: 'pop' did not run on the second load"* ]]
  # replace / omit / extra rules
  jq '(.items[] | select(.id == "kf:spin")) |= (.disposition = "omit" | .reason = "" | .label = "")
      | (.items[] | select(.id == "tr:color@hover")) |= (.disposition = "replace" | .target = "background-color" | .reason = "jen pozadí" | .label = "")
      | .extra = [{"id": "extra:glow", "target": "glow", "reason": ""}]' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$FXR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kf:spin: omit without a reason"* && "$output" == *"kf:spin: omit without a label"* && "$output" == *"tr:color@hover: replace without a label"* ]]
  [[ "$output" == *"extra:glow: extra motion without a reason"* && "$output" == *"extra 'glow' never ran"* ]]
  jq '(.items[] | select(.id == "kf:spin")) |= (.reason = "ordinace pečeť nemá" | .label = "otáčení pečeti")
      | (.items[] | select(.id == "tr:color@hover")) |= (.label = "barva odkazu při najetí")
      | (.items[] | select(.id == "kf:pop")) |= (.frequency = "first_load_only" | .source.frequency = "first_load_only")
      | .extra = [{"id": "extra:pop", "target": "pop", "reason": "jemné objevení názvu"}]' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$FXR"
  [ "$status" -eq 0 ]; [[ "$output" == "PASS: z 9 pohybů vzoru: 7 převzato, 1 nahrazeno, 1 vynecháno, 1 navíc" ]]
  # adopt with another motion's name is a hidden replace: refused
  jq '(.items[] | select(.id == "kf:fadeup")) |= (.target = "pop")' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$FXR"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:fadeup: adopt must keep the reference's name/property 'fadeup'"* ]]
  jq '(.items[] | select(.id == "kf:fadeup")) |= (.target = "fadeup")' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  [ "$(python3 "$MP" summary "$P" | jq -r '.exceptions | map(.label) | join(";")')" == "otáčení pečeti;barva odkazu při najetí" ]
}

@test "check: replace from a second reference is proven in that reference's record (PM saw it, record exists, motion ran there) and in the build" {
  cp "$FXR" "$P/.aid-ui/refs/fx.motion.json"; python3 "$MP" inventory "$P" >/dev/null; fill
  # the build carries `glow` instead of the reference's `spin`, taken from reference `alt`
  jq '.keyframes += [(.keyframes[] | select(.name == "spin") | .name = "glow")]' "$FXR" > "$P/build.json"
  jq '(.items[] | select(.id == "kf:spin")) |= (.disposition = "replace" | .target = "glow" | .from = "alt" | .reason = "jemnější než otáčení" | .label = "záře pečeti")' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$P/build.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:spin: from 'alt' is not one of the references the PM saw"* ]]
  echo '{"refs":[{"id":"fx","url":"http://127.0.0.1:39931/index.html","picked":true},{"id":"alt","url":"http://alt.example/"}]}' > "$P/docs/design/brand-state.json"
  run python3 "$MP" check "$P" --observed "$P/build.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:spin: from 'alt': no record .aid-ui/refs/alt.motion.json"* ]]
  jq '.url = "http://alt.example/"' "$FXR" > "$P/.aid-ui/refs/alt.motion.json"
  run python3 "$MP" check "$P" --observed "$P/build.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:spin: replace from 'alt': 'glow' never ran in that reference"* ]]
  jq '.url = "http://alt.example/" | .keyframes += [(.keyframes[] | select(.name == "spin") | .name = "glow")]' "$FXR" > "$P/.aid-ui/refs/alt.motion.json"
  run python3 "$MP" check "$P" --observed "$P/build.json"
  [ "$status" -eq 0 ]; [[ "$output" == "PASS: z 9 pohybů vzoru: 8 převzato, 1 nahrazeno, 0 vynecháno" ]]
  [ "$(python3 "$MP" summary "$P" | jq -r '.exceptions[0].from')" == alt ]
  # `from` on adopt is refused; the build without glow fails as before
  jq '(.items[] | select(.id == "kf:spin")) |= (.disposition = "adopt" | .target = "spin")' "$P/.aid-ui/motion.json" > "$P/m.t" && mv "$P/m.t" "$P/.aid-ui/motion.json"
  run python3 "$MP" check "$P" --observed "$P/build.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"kf:spin: \`from\` is only for replace"* ]]
}

@test "check --dir: the record must carry the directory's current sha; dirsha changes with content" {
  cp "$FXR" "$P/.aid-ui/refs/fx.motion.json"; python3 "$MP" inventory "$P" >/dev/null; fill
  D="$P/.aid-ui/directions/1"; mkdir -p "$D"; echo '<p>a</p>' > "$D/index.html"
  s1="$(python3 "$MP" dirsha "$D")"; [ "${#s1}" -eq 64 ]
  run python3 "$MP" check "$P" --observed "$FXR" --dir "$D"
  [ "$status" -eq 1 ]; [[ "$output" == *"was not observed over the directory as it is now"* ]]
  jq --arg s "$s1" '.dir_sha256 = $s | .url = "https://cizi.example/"' "$FXR" > "$P/obs.json"
  run python3 "$MP" check "$P" --observed "$P/obs.json" --dir "$D"
  [ "$status" -eq 1 ]; [[ "$output" == *"not at a locally served copy of the directory"* ]]
  jq --arg s "$s1" '.dir_sha256 = $s' "$FXR" > "$P/obs.json"
  run python3 "$MP" check "$P" --observed "$P/obs.json" --dir "$D"
  [ "$status" -eq 0 ]
  echo '<p>b</p>' > "$D/index.html"
  [ "$(python3 "$MP" dirsha "$D")" != "$s1" ]
  run python3 "$MP" check "$P" --observed "$P/obs.json" --dir "$D"
  [ "$status" -eq 1 ]
}
