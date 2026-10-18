#!/usr/bin/env bats
# aid-tier: t1
# aid-ui-package.py — P115: the handover package between the studio and plan/run (docs/ui/predani.json).
# package:  the handover writes it, an incomplete or stale one refuses the handover and leaves the answer unused.
# Real studio and answers through the helpers of test-aid-ui-state.bats (aid-ui-state-helpers.bash); no model.

load aid-ui-places
setup_file() { places_template; }
load aid-ui-state-helpers

setup() {
  state_setup
  PKG="$BATS_TEST_DIRNAME/../../aid-ui-package.py"
  FIXP="$BATS_TEST_DIRNAME/../fixtures/aid-ui/package"
  OUTP="$PROJ/docs/ui/predani.json"
  mkdir -p "$PROJ/docs/content"
  printf -- '- {id: hours, task: "Kdy máte otevřeno", expect: ["7:00"]}\n- {id: booking, task: "Objednej se", form: true}\n' > "$PROJ/docs/content/tasks.yaml"
}
teardown() { state_teardown; }

# handed_over — a recorded gate, two chapters and the PM's handover answer h1 (not yet used)
handed_over() {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
}

@test "package: the handover writes predani.json and predani.md; the package passes check, also against the project" {
  handed_over
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ] && [ -f "$PROJ/docs/ui/predani.md" ]
  [ "$(jq -r .version "$OUTP")" = 1 ]
  [ "$(jq -r '[.chapters[].id] | join(",")' "$OUTP")" = "vize,barvy" ]
  [ "$(jq -r '[.customer_tasks[].id] | join(",")' "$OUTP")" = "hours,booking" ]
  [ "$(jq -r .site.build_id "$OUTP")" = "$(jq -r .build.id "$STATE")" ]
  [ "$(jq '.site.files | length' "$OUTP")" = "$(find "$SITE" -type f | wc -l)" ]
  run python3 "$PKG" check "$OUTP" --project "$PROJ"
  [ "$status" -eq 0 ]
  run python3 "$PKG" check "$FIXP/docs/ui/predani.json"
  [ "$status" -eq 0 ]
  # a file list that lies (one entry dropped, or a path out of the site) fails, though build id and dirsha match
  jq '.site.files |= .[1:]' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json" --project "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"soubory nejsou ty z balíku"* ]]
  jq '.site.files[0].path = "../etc/passwd"' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"nebezpečná"* ]]
}

@test "package: no recorded gate refuses the package naming the gate" {
  "$SCRIPT" chapter "$PROJ" vize navrh
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: chybí brána"* ]]
  [ ! -e "$OUTP" ]
}

@test "package: a site changed after the gate is stale; a package missing a part fails check naming it" {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: zastaralý"* ]]
  jq 'del(.gate)' "$FIXP/docs/ui/predani.json" > "$T/bad.json"
  run python3 "$PKG" check "$T/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'gate' is a required property"* ]]
}

@test "package: a refused package leaves the handover answer unused and the state unchanged; fixed, the same answer hands over" {
  handed_over
  cp "$SITE/kontakt.html" "$T/kontakt.orig"
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  before="$(sha256sum "$HTML" "$STATE")"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"answer h1 not used"* ]]
  [[ "$output" == *"zastaralý"* ]]
  [ "$(sha256sum "$HTML" "$STATE")" = "$before" ]
  [ ! -e "$OUTP" ]
  cp "$T/kontakt.orig" "$SITE/kontakt.html"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ]
}

@test "package: a standalone build after a recorded handover rewrites the package; before a handover it is refused" {
  handed_over
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chybí převzetí"* ]]
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  want="$(jq -c 'del(.created_at)' "$OUTP")"
  rm -f "$OUTP" "$PROJ/docs/ui/predani.md"
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'del(.created_at)' "$OUTP")" = "$want" ]
  [ -f "$PROJ/docs/ui/predani.md" ]
}
