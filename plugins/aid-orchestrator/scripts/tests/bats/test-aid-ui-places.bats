#!/usr/bin/env bats
# aid-tier: t1
# T1 because it runs aid-ui-critic.py freeze (behaviour); AID's T0 holds static checks only.
# P113 step 1 - the rubrics and gates of the six decision places: every gate names a criterion of its rubric, the
# motion metrics are the four the check measures, every frozen role prompt carries the evaluator's memory, nothing
# of the workshop's trial business is in the plugin, and every place freezes.

setup() {
  SC="$BATS_TEST_DIRNAME/../.."
  C="$SC/aid-ui-critic.py"; K="$SC/../skills/ui-design/critic"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/docs/content" "$P/site"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><body>x</body></html>' > "$P/site/index.html"
}

PLACES="sdeleni logo pohyb struktura vzhled web"

@test "places: every place freezes for both roles; the gates go with the roles, never into a prompt" {
  for p in $PLACES; do
    run python3 "$C" freeze "$P" --type web-local --place "$p"; [ "$status" -eq 0 ] || { echo "$p: $output"; return 1; }
    f="$P/.aid-ui/critic/frozen/$p.json"; [ "$p" != web ] || f="$P/.aid-ui/critic/frozen.json"
    jq -e --arg p "$p" '.place == $p and (.roles.owner.gates | length) >= 1 and (.roles.tech.gates | length) >= 1' "$f" >/dev/null
    for r in owner tech; do
      out="$(python3 "$C" prompt "$P" --role $r --place "$p")"
      # no gate's reason and no threshold of a gate file reaches the role
      while IFS= read -r why; do [ -z "$why" ] || ! grep -qF "$why" <<<"$out" || { echo "$p $r: gate text in the prompt: $why"; return 1; }; done \
        < <(yq -r '.gates[]?.why, .metrics[]?.why' "$K/web-local.$r.$p.gates.yaml")
      ! grep -qE 'weighted_min|median_min' <<<"$out"
    done
  done
  # web is rated with the look and the structure rubrics too
  jq -e '[.roles.tech.rubrics[].key] == ["web","vzhled","struktura"]' "$P/.aid-ui/critic/frozen.json" >/dev/null
}

@test "places: every gate names a criterion of its rubric; when, any_of and weighted_min have their shapes" {
  for g in "$K"/web-local.*.*.gates.yaml; do
    b="$(basename "$g" .gates.yaml)"; rub="$K/$b.yaml"; [[ "$b" != *.web ]] || rub="$K/${b%.web}.yaml"
    [ -f "$rub" ] || { echo "no rubric for $g"; return 1; }
    ids="$(yq -r '.criteria[].id' "$rub")"
    for id in $(yq -r '.gates[]? | (.criterion // empty), (.any_of[]? // empty)' "$g"); do
      grep -qx "$id" <<<"$ids" || { echo "$(basename "$g"): $id is not a criterion of $(basename "$rub")"; return 1; }
    done
    for w in $(yq -r '.gates[]?.when // empty' "$g"); do [[ "$w" =~ ^(nove|oziveni|zavedeny_motiv)$ ]] || { echo "$g: when $w"; return 1; }; done
    [ "$(yq -r '[.gates[]? | select((.min | type) != "!!int" and (.min | type) != "!!float")] | length' "$g")" = 0 ]
    [ "$(yq -r '.role' "$g")" = "$(yq -r '.role' "$rub")" ] || [[ "$b" == *.web ]]
  done
  [ "$(ls "$K"/web-local.*.*.gates.yaml | wc -l)" -eq 12 ]
}

@test "places: the motion gates measure only the four metrics the check writes" {
  for r in owner tech; do
    for m in $(yq -r '.metrics[].metric' "$K/web-local.$r.pohyb.gates.yaml"); do
      [[ "$m" =~ ^(web_logo_draw_ms|web_logo_name_visible_ms|web_motion_running_after_ms|final_frame_diff_px)$ ]] || { echo "$r: $m"; return 1; }
    done
    [ "$(yq -r '.gates | length' "$K/web-local.$r.pohyb.gates.yaml")" -ge 1 ]   # criterion gates beside the metrics
  done
}

@test "places: every frozen role prompt carries the evaluator's memory" {
  for p in $PLACES; do
    python3 "$C" freeze "$P" --type web-local --place "$p" --force >/dev/null
    for r in owner tech; do
      out="$(python3 "$C" prompt "$P" --role $r --place "$p")"
      grep -qF "# Paměť hodnotitele" <<<"$out" && grep -qF "drobnost skóre nesnižuje" <<<"$out" && grep -qF "opraveno | castecne | neopraveno" <<<"$out" ||
        { echo "$p $r: no evaluator memory"; return 1; }
    done
    python3 "$C" prompt "$P" --role owner --place "$p" | grep -qF "jedna role na všech místech"
  done
}

@test "places: nothing of the workshop's trial business or its paths is under critic/; AUTHORS records every new file by sha" {
  ! grep -rliw -e hirt "$K"
  ! grep -rl '/home/claude' "$K"
  python3 - "$K" <<'PY'
import glob, hashlib, os, sys, yaml
k = sys.argv[1]; a = yaml.safe_load(open(os.path.join(k, "AUTHORS.yaml")))
bad = [os.path.basename(f) for f in glob.glob(os.path.join(k, "web-local.*.*.yaml")) + glob.glob(os.path.join(k, "webapp*.yaml"))
       if (a.get(os.path.basename(f)) or {}).get("sha256") != hashlib.sha256(open(f, "rb").read()).hexdigest()]
sys.exit("AUTHORS sha of " + ", ".join(bad) if bad else 0)
PY
}

# ---------------------------------------------------------------- P116: the places of a web application
app_places_project() {
  mkdir -p "$P/docs/design"
  echo '{"variant": {"type": "webapp", "brand": "none", "local": false}}' > "$P/docs/design/brand-state.json"
  cp "$BATS_TEST_DIRNAME/../fixtures/aid-ui/app/docs/design/screens.json" "$P/docs/design/"
  printf '# Poznámky\nAplikace na poznámky pro jednoho uživatele.\n' > "$P/zadani.md"
  printf 'from fastapi import FastAPI\napp = FastAPI()\n@app.get("/api/poznamky")\ndef x(): pass\n' > "$P/main.py"
}

@test "places: webapp - struktura, vzhled and the finished app freeze for both roles with the app's context; the gates stay out of the prompt" {
  app_places_project
  for p in struktura vzhled web; do
    run python3 "$C" freeze "$P" --type webapp --place "$p"; [ "$status" -eq 0 ] || { echo "$p: $output"; return 1; }
    f="$P/.aid-ui/critic/frozen/$p.json"; [ "$p" != web ] || f="$P/.aid-ui/critic/frozen.json"
    jq -e '.type == "webapp" and (.roles.owner.gates | length) >= 1 and (.roles.tech.gates | length) >= 1' "$f" >/dev/null
    for r in owner tech; do
      out="$(python3 "$C" prompt "$P" --role $r --place "$p")"
      g="$K/webapp.$r.$p.gates.yaml"
      while IFS= read -r why; do [ -z "$why" ] || ! grep -qF "$why" <<<"$out" || { echo "$p $r: gate text in the prompt: $why"; return 1; }; done < <(yq -r '.gates[]?.why' "$g")
      ! grep -qE 'weighted_min|median_min' <<<"$out"
      [[ "$out" == *"Zadání projektu"* ]] && [[ "$out" == *"/api/poznamky"* ]]   # the client and expert know the app from its brief and code
    done
  done
  [[ "$(python3 "$C" prompt "$P" --role owner --place struktura)" == *"Model obrazovek a úloh"* ]]
  # the struktura bundle of an app is its model
  [ "$(python3 "$C" bundle-files "$P" --place struktura | tr '\n' ' ')" = "docs/design/screens.json zadani.md " ]
}

@test "places: webapp - every gate names a criterion of its rubric; the skipped places do not exist; no zadani.md, no client" {
  for g in "$K"/webapp.*.*.gates.yaml; do
    b="$(basename "$g" .gates.yaml)"; rub="$K/$b.yaml"; [[ "$b" != *.web ]] || rub="$K/${b%.web}.yaml"
    ids="$(yq -r '.criteria[].id' "$rub")"
    for id in $(yq -r '.gates[]? | (.criterion // empty), (.any_of[]? // empty)' "$g"); do grep -qx "$id" <<<"$ids" || { echo "$g: $id"; return 1; }; done
    yq -e '.weighted_min' "$g" >/dev/null
  done
  [ "$(ls "$K"/webapp.*.*.gates.yaml | wc -l)" -eq 6 ]
  app_places_project
  for p in sdeleni pohyb logo; do
    run python3 "$C" freeze "$P" --type webapp --place "$p"; [ "$status" -eq 2 ]; [[ "$output" == *"does not exist for a web application"* ]]
    run python3 "$C" place-guard "$P" --place "$p"; [ "$status" -eq 0 ]; [[ "$output" == *"N/A pro aplikaci"* ]]
  done
  # a new brand keeps the logo place
  jq '.variant.brand = "new"' "$P/docs/design/brand-state.json" > "$P/s" && mv "$P/s" "$P/docs/design/brand-state.json"
  run python3 "$C" place-guard "$P" --place logo; [ "$status" -eq 1 ]; [[ "$output" == *"place_verdict_missing"* ]]
  rm "$P/zadani.md"
  run python3 "$C" freeze "$P" --type webapp --place struktura --force
  [ "$status" -eq 1 ]; [[ "$output" == *"no zadani.md"* ]]
}
