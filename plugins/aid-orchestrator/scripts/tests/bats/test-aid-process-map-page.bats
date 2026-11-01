#!/usr/bin/env bats
# aid-tier: t2
# aid-subject: scripts/aid-process-map.py
# The process-map page as the PM meets it, end to end in a headless browser (P118): both kinds really rendered
# once by bpmn-js / Mermaid, the page opened with the network cut off, a click, a mark stored through a stub of
# share's runtime, and that very record read back by `flags`. t2 because a browser start exceeds the t1
# per-case limit. Defects it catches: a page that requests anything, a step that cannot be clicked, a mark the
# reader cannot match back to its step.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PM="$AID_PLUGIN_PATH/scripts/aid-process-map.sh"; TOOL="$AID_PLUGIN_PATH/scripts/aid-ui-tool.sh"
  FX="$AID_PLUGIN_PATH/scripts/tests/fixtures/process-map"
  D="$BATS_TEST_TMPDIR/procesy"; mkdir -p "$D"
}

_roundtrip() {   # <fixture> <step id> <expected detail title>
  cp "$FX/$1.mapa.yaml" "$D/$1.mapa.yaml"
  run bash "$PM" build "$D/$1.mapa.yaml" --out "$BATS_TEST_TMPDIR/$1"; [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/$1/picture.svg" ] && [ -s "$BATS_TEST_TMPDIR/$1/page.html" ]
  run bash "$TOOL" map-page "$BATS_TEST_TMPDIR/$1/page.html" "$BATS_TEST_TMPDIR/$1.json" "$2"; [ "$status" -eq 0 ]
  run python3 -c "
import json; r = json.load(open('$BATS_TEST_TMPDIR/$1.json'))
assert r['requests'] == [], r['requests']
assert r['detail'] == '$3', r['detail']
assert len(r['records']) == 1 and r['records'][0]['path'].startswith('data/users/u_test/mapy/oznaceni/'), r['records']
d = r['records'][0]['data']; assert d['map'] == '$1' and d['state'] == '$2' and d['text'] == 'Zkouška označení', d
json.dump(r['records'], open('$BATS_TEST_TMPDIR/$1-records.json', 'w'))"
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$BATS_TEST_TMPDIR/$1-records.json" > "$BATS_TEST_TMPDIR/reader"; chmod +x "$BATS_TEST_TMPDIR/reader"
  AID_PM_PAGE_DATA_READER="$BATS_TEST_TMPDIR/reader" run bash "$PM" flags "$D/$1.mapa.yaml" --out "$BATS_TEST_TMPDIR/$1"
  [ "$status" -eq 0 ]; [ "${#lines[@]}" -eq 1 ]; [[ "${lines[0]}" == *"\"state\": \"$2\""* ]]
}

@test "page: the BPMN map renders, makes no request, a click shows the step and its mark comes back through flags" {
  _roundtrip zivot-planu PLAN_FIX "Oprava nálezů"
}

@test "page: the state map (Mermaid) renders, makes no request, a click shows the state and its mark comes back through flags" {
  _roundtrip objednavka NEZAPLACENA "Nezaplacená"
}
