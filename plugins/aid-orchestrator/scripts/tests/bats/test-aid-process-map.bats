#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-process-map.py
# Process maps: the map file's check, the deterministic layout and the drawing (P118, standard
# /ecosystem/specs/procesni-mapy). Defects it catches: a broken map accepted, two builds that differ,
# a line or a label drawn across a box, a lost added/removed marker. Files only — no browser, no network.

bats_require_minimum_version 1.5.0

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PM="$AID_PLUGIN_PATH/scripts/aid-process-map.sh"
  FX="$AID_PLUGIN_PATH/scripts/tests/fixtures/process-map"
  D="$BATS_TEST_TMPDIR/procesy"; mkdir -p "$D"
}

_measure() {
  python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"bpmn": "http://www.omg.org/spec/BPMN/20100524/MODEL", "bpmndi": "http://www.omg.org/spec/BPMN/20100524/DI",
      "dc": "http://www.omg.org/spec/DD/20100524/DC", "di": "http://www.omg.org/spec/DD/20100524/DI"}
t = ET.parse(sys.argv[1]).getroot()
proc = t.find("bpmn:process", ns)
src = {f.get("id"): (f.get("sourceRef"), f.get("targetRef")) for f in proc.findall("bpmn:sequenceFlow", ns)}
src.update({a.get("id"): (a.get("sourceRef"), a.get("targetRef")) for a in proc.findall("bpmn:association", ns)})
box = {}
for s in t.iter("{%s}BPMNShape" % ns["bpmndi"]):
    b = s.find("dc:Bounds", ns); box[s.get("bpmnElement")] = tuple(float(b.get(k)) for k in ("x", "y", "width", "height"))
def hit(a, b): return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]
bad = []
ks = sorted(box)
for i, a in enumerate(ks):
    for b in ks[i + 1:]:
        if hit(box[a], box[b]): bad.append(("box", a, b))
for e in t.iter("{%s}BPMNEdge" % ns["bpmndi"]):
    own = set(src[e.get("bpmnElement")])
    pts = [(float(w.get("x")), float(w.get("y"))) for w in e.findall("di:waypoint", ns)]
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        for k, (rx, ry, rw, rh) in box.items():
            if k in own: continue
            if x1 == x2 and rx < x1 < rx + rw and min(y1, y2) < ry + rh and ry < max(y1, y2): bad.append(("line", e.get("bpmnElement"), k))
            if y1 == y2 and ry < y1 < ry + rh and min(x1, x2) < rx + rw and rx < max(x1, x2): bad.append(("line", e.get("bpmnElement"), k))
    lb = e.find("bpmndi:BPMNLabel/dc:Bounds", ns)
    if lb is not None:
        r = tuple(float(lb.get(k)) for k in ("x", "y", "width", "height"))
        bad += [("label", e.get("bpmnElement"), k) for k, b in box.items() if hit(r, b)]
for s in t.iter("{%s}BPMNShape" % ns["bpmndi"]):
    lb = s.find("bpmndi:BPMNLabel/dc:Bounds", ns)
    if lb is not None:
        r = tuple(float(lb.get(k)) for k in ("x", "y", "width", "height"))
        bad += [("shape-label", s.get("bpmnElement"), k) for k, b in box.items() if k != s.get("bpmnElement") and hit(r, b)]
        if r[0] < 0: bad.append(("negative-x", s.get("bpmnElement"), r[0]))
ids = [el.get("id") for el in t.iter() if el.get("id")]
bad += [("duplicate-id", i) for i in sorted(set(ids)) if ids.count(i) > 1]
print(bad); sys.exit(1 if bad else 0)
PY
}

# _variant <fixture> <name> <python expression on m> — a changed copy of a fixture
_variant() {
  python3 - "$FX/$1.mapa.yaml" "$D/$2.mapa.yaml" "$3" <<'PY'
import sys, yaml
m = yaml.safe_load(open(sys.argv[1])); exec(sys.argv[3]); yaml.safe_dump(m, open(sys.argv[2], "w"), allow_unicode=True, sort_keys=False)
PY
}

@test "check: both fixtures pass" {
  run bash "$PM" check "$FX/zivot-planu.mapa.yaml"; [ "$status" -eq 0 ]
  run bash "$PM" check "$FX/objednavka.mapa.yaml"; [ "$status" -eq 0 ]
}

@test "check: a duplicate step id is refused" {
  _variant objednavka dup 'm["kroky"].append(dict(m["kroky"][1]))'
  run bash "$PM" check "$D/dup.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"duplicate_id: ZAPLACENA"* ]]
}

@test "check: a transition to an unknown step is refused" {
  _variant objednavka unk 'm["prechody"].append({"z": "NOVA", "do": "NIKDE", "popis": "x"})'
  run bash "$PM" check "$D/unk.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"unknown_step"*"NIKDE"* ]]
}

@test "check: a branch without a label is refused" {
  _variant objednavka lbl 'del m["prechody"][0]["popis"]'
  run bash "$PM" check "$D/lbl.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"branch_without_label: NOVA -> ZAPLACENA"* ]]
}

@test "check: an unreachable step is refused, an odevsad target is reached" {
  _variant objednavka unr 'm["kroky"].append({"id": "SIROTEK", "jmeno": "Sirotek", "co": "Nikam nevede.", "konec": "bad"})'
  run bash "$PM" check "$D/unr.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"unreachable_step: SIROTEK"* ]]
  _variant objednavka ods 'm["kroky"].append({"id": "CHYBA", "jmeno": "Chyba", "co": "Selhání.", "konec": "bad"}); m["odevsad"] = [{"do": "CHYBA", "popis": "selhání"}]'
  run bash "$PM" check "$D/ods.mapa.yaml"; [ "$status" -eq 0 ]
}

@test "check: a dead end and an end with a drawn exit are refused; an odevsad from ends is not an exit" {
  _variant objednavka dead 'm["kroky"][3]["konec"] = "none"; m["prechody"] = [t for t in m["prechody"] if t["z"] != "NEZAPLACENA"]; m["prechody"].append({"z": "NOVA", "do": "STORNO", "popis": "zrušil"}); m["prechody"][0]["popis"]="platba"'
  run bash "$PM" check "$D/dead.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"dead_end: NEZAPLACENA"* ]]
  _variant objednavka exit 'm["prechody"].append({"z": "ODESLANA", "do": "NOVA"})'
  run bash "$PM" check "$D/exit.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"end_with_exit: ODESLANA"* ]]
  _variant objednavka endsok 'm["kroky"].append({"id": "CHYBA", "jmeno": "Chyba", "co": "Selhání.", "konec": "bad"}); m["odevsad"] = [{"do": "CHYBA", "popis": "selhání", "vcetne_koncu": True}]'
  run bash "$PM" check "$D/endsok.mapa.yaml"; [ "$status" -eq 0 ]
}

@test "check: a map from code without zdroj, a missing proti, a wrong name and unreadable YAML" {
  _variant zivot-planu src 'del m["zdroj"]'
  run bash "$PM" check "$D/src.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"schema: (root): 'zdroj' is a required property"* ]]
  _variant objednavka pro 'm["proti"] = "neni.mapa.yaml"'
  run bash "$PM" check "$D/pro.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"proti_missing: neni.mapa.yaml"* ]]
  _variant objednavka cesta 'm["proti"] = "../x.mapa.yaml"'
  run bash "$PM" check "$D/cesta.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"schema"*"proti"* ]]
  cp "$FX/objednavka.mapa.yaml" "$D/.mapa.yaml"
  run bash "$PM" check "$D/.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"name:"* ]]
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.yaml"
  run bash "$PM" check "$D/objednavka.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *".mapa.yaml"* ]]
  printf 'kroky: [\n' > "$D/rozbita.mapa.yaml"
  run bash "$PM" check "$D/rozbita.mapa.yaml"; [ "$status" -eq 2 ]
}

@test "check: a colour or a coordinate in the map file is refused (the look lives in style.json)" {
  _variant objednavka barva 'm["kroky"][0]["barva"] = "#ff0000"'
  run bash "$PM" check "$D/barva.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"schema"*"barva"* ]]
}

@test "build: two builds give the same bytes for both fixtures" {
  for f in zivot-planu objednavka; do
    run bash "$PM" build "$FX/$f.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/a-$f"; [ "$status" -eq 0 ]
    run bash "$PM" build "$FX/$f.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/b-$f"; [ "$status" -eq 0 ]
    diff -r "$BATS_TEST_TMPDIR/a-$f" "$BATS_TEST_TMPDIR/b-$f"
  done
  [ -s "$BATS_TEST_TMPDIR/a-zivot-planu/drawing.bpmn" ] && [ -s "$BATS_TEST_TMPDIR/a-objednavka/drawing.mmd" ]
}

@test "build: measured from the written DI, no box, line segment or label crosses another box" {
  run bash "$PM" build "$FX/zivot-planu.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/o"; [ "$status" -eq 0 ]
  run _measure "$BATS_TEST_TMPDIR/o/drawing.bpmn"
  [ "$status" -eq 0 ]
}

@test "build: every self-loop is drawn and gateways follow branching steps" {
  run bash "$PM" build "$FX/zivot-planu.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/s"; [ "$status" -eq 0 ]
  grep -q 'sourceRef="PLAN_SYNC" targetRef="PLAN_SYNC"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
  grep -q 'exclusiveGateway id="GW-AWAITING_PM"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
  grep -q 'textAnnotation id="ANN-ABORTED"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
  # the self-loop does not go through the gateway: EPIC_INTEGRATION's gateway has exactly its two other exits
  [ "$(grep -c 'sourceRef="GW-EPIC_INTEGRATION"' "$BATS_TEST_TMPDIR/s/drawing.bpmn")" -eq 2 ]
  grep -q 'sourceRef="EPIC_INTEGRATION" targetRef="EPIC_INTEGRATION"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
}

@test "build: against proti, an added and a removed step and transition are marked" {
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.mapa.yaml"
  _variant objednavka objednavka-po 'm["proti"] = "objednavka.mapa.yaml"; m["kroky"] = [k for k in m["kroky"] if k["id"] != "NEZAPLACENA"]; m["prechody"] = [t for t in m["prechody"] if "NEZAPLACENA" not in (t["z"], t["do"])]; m["prechody"][0].pop("popis"); m["kroky"].insert(2, {"id": "BALENA", "jmeno": "Balí se", "co": "Sklad balí."}); m["prechody"] = [{"z": "NOVA", "do": "ZAPLACENA"}, {"z": "ZAPLACENA", "do": "BALENA"}, {"z": "BALENA", "do": "ODESLANA"}, {"z": "NOVA", "do": "STORNO", "popis": "x"}]; m["prechody"][0]["popis"] = "platba"'
  run bash "$PM" build "$D/objednavka-po.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/p"; [ "$status" -eq 0 ]
  run python3 -c "
import json; m = json.load(open('$BATS_TEST_TMPDIR/p/model.json'))
s = {x['id']: x['marker'] for x in m['steps']}; t = {(x['z'], x['do']): x['marker'] for x in m['transitions']}
assert s['BALENA'] == 'added' and s['NEZAPLACENA'] == 'removed' and s['NOVA'] is None, s
assert t[('ZAPLACENA', 'BALENA')] == 'added' and t[('ZAPLACENA', 'ODESLANA')] == 'removed', t"
  [ "$status" -eq 0 ]
}

@test "build: roles come from the map (ends, ceka) and from the drawing (a step the process goes back from)" {
  run bash "$PM" build "$FX/zivot-planu.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/r"; [ "$status" -eq 0 ]
  run python3 -c "
import json; r = {x['id']: x['role'] for x in json.load(open('$BATS_TEST_TMPDIR/r/model.json'))['steps']}
assert r['CLOSED'] == 'ok' and r['ABORTED'] == 'bad' and r['AWAITING_PM'] == 'pm' and r['PLAN_FIX'] == 'warn', r"
  [ "$status" -eq 0 ]
}

@test "check: proti is held to the schema too; an id smuggled through proti never reaches the drawing" {
  printf 'nazev: x\n' > "$D/stara.mapa.yaml"
  _variant objednavka nova 'm["proti"] = "stara.mapa.yaml"'
  run bash "$PM" check "$D/nova.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"proti_invalid: stara.mapa.yaml"* ]]
  _variant objednavka stara2 'm["kroky"][0]["id"] = "X\"/><bpmn:task id=\"EVIL"'
  _variant zivot-planu nova2 'm["proti"] = "stara2.mapa.yaml"'
  run bash "$PM" build "$D/nova2.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/inj"; [ "$status" -eq 1 ]
  [[ "$output" == *"proti_invalid"* ]]; [ ! -e "$BATS_TEST_TMPDIR/inj" ]
}

@test "check: a self-loop on an end is an exit" {
  _variant objednavka endloop 'm["prechody"].append({"z": "ODESLANA", "do": "ODESLANA"})'
  run bash "$PM" check "$D/endloop.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"end_with_exit: ODESLANA -> ODESLANA"* ]]
}

@test "build: generated ids can never collide with step ids (GW_A, F0 and friends are plain steps)" {
  _variant objednavka kolize 'm["kroky"][1]["id"] = "GW_NOVA"; m["kroky"][3]["id"] = "F0"; m["druh"] = "bpmn"
for t in m["prechody"]:
    t["z"] = {"ZAPLACENA": "GW_NOVA", "NEZAPLACENA": "F0"}.get(t["z"], t["z"]); t["do"] = {"ZAPLACENA": "GW_NOVA", "NEZAPLACENA": "F0"}.get(t["do"], t["do"])'
  run bash "$PM" build "$D/kolize.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/k"; [ "$status" -eq 0 ]
  run _measure "$BATS_TEST_TMPDIR/k/drawing.bpmn"; [ "$status" -eq 0 ]
  grep -q '<bpmn:task id="GW_NOVA"' "$BATS_TEST_TMPDIR/k/drawing.bpmn"
}

@test "build: an odevsad target that is not an end stays a task (a pause the process resumes from)" {
  _variant objednavka pauza 'm["druh"] = "bpmn"; m["kroky"].insert(1, {"id": "PAUZA", "jmeno": "Pozastaveno", "co": "Čeká na zákazníka."}); m["prechody"].append({"z": "PAUZA", "do": "NOVA", "popis": "pokračuje"}); m["odevsad"] = [{"do": "PAUZA", "popis": "pauza"}]'
  run bash "$PM" build "$D/pauza.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/pz"; [ "$status" -eq 0 ]
  grep -q '<bpmn:task id="PAUZA"' "$BATS_TEST_TMPDIR/pz/drawing.bpmn"
  run _measure "$BATS_TEST_TMPDIR/pz/drawing.bpmn"; [ "$status" -eq 0 ]
}

@test "build: long names (36 chars) and a fan of five branches with 24-char labels lay out without overlap" {
  _variant objednavka siroka 'm["druh"] = "bpmn"; m["kroky"][0]["jmeno"] = "S" * 36; m["kroky"][2]["jmeno"] = "K" * 36
m["kroky"] += [{"id": f"T{i}", "jmeno": f"Větev {i}", "co": "x", "konec": "ok"} for i in range(5)]
m["prechody"] += [{"z": "ZAPLACENA", "do": f"T{i}", "popis": chr(65 + i) * 24} for i in range(5)]
m["prechody"] = [t for t in m["prechody"] if not (t["z"] == "ZAPLACENA" and t["do"] == "ODESLANA")]
m["prechody"].append({"z": "ZAPLACENA", "do": "ODESLANA", "popis": "Z" * 24})'
  run bash "$PM" build "$D/siroka.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/w"; [ "$status" -eq 0 ]
  run _measure "$BATS_TEST_TMPDIR/w/drawing.bpmn"; [ "$status" -eq 0 ]
}

@test "build: a one-step map and two steps with the same name build" {
  printf 'nazev: Jeden\ndruh: bpmn\nstav: dnes\npuvod: rozhovor\nkroky:\n  - {id: A, jmeno: Jediný, co: Hotovo hned., konec: ok}\nprechody: []\n' > "$D/jeden.mapa.yaml"
  run bash "$PM" build "$D/jeden.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/j"; [ "$status" -eq 0 ]
  _variant objednavka stejne 'm["kroky"][1]["jmeno"] = m["kroky"][3]["jmeno"]'
  run bash "$PM" build "$D/stejne.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/st"; [ "$status" -eq 0 ]
}

@test "build: the Mermaid drawing avoids keywords, uses block notes and no reserved class name" {
  _variant objednavka klic 'm["kroky"].append({"id": "note", "jmeno": "Poznámka: x", "co": "x", "konec": "bad"}); m["odevsad"] = [{"do": "note", "popis": "chyba: y"}]'
  run bash "$PM" build "$D/klic.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/m"; [ "$status" -eq 0 ]
  f="$BATS_TEST_TMPDIR/m/drawing.mmd"
  run ! grep -q 'classDef default' "$f"; ! grep -Eq '^  note .*:' "$f"; grep -q 'end note' "$f"
  run ! grep -Eq '^  state "[^"]*" as [^s]' "$f"; ! grep -Eq ' : [^\n]*:' "$f"
}

@test "build: when the layout check finds an overlap, build exits 1 and writes nothing" {
  run python3 - "$AID_PLUGIN_PATH/scripts" "$FX/zivot-planu.mapa.yaml" "$BATS_TEST_TMPDIR/ov" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("apm", sys.argv[1] + "/aid-process-map.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
two = {"nodes": {"A": {"id": "A", "x": 0, "y": 0, "w": 50, "h": 50}, "B": {"id": "B", "x": 10, "y": 10, "w": 50, "h": 50}}, "edges": [], "labels": [], "annotations": []}
assert m.overlaps(two) == [("A", "B")], m.overlaps(two)
m.overlaps = lambda lay: [("X", "Y")]
rc = m.cmd_build(sys.argv[2], sys.argv[3])
sys.exit(0 if rc == 1 else 3)
PY
  [ "$status" -eq 0 ]; [[ "$output" == *"layout_overlap: X Y"* ]]; [ ! -e "$BATS_TEST_TMPDIR/ov" ]
}

@test "page-static: the page from the fixture picture carries nothing share refuses, no outside reference, no placeholder" {
  run bash "$PM" page "$FX/zivot-planu.mapa.yaml" --svg "$FX/zivot-planu.svg" --out "$BATS_TEST_TMPDIR/pg"; [ "$status" -eq 0 ]
  f="$BATS_TEST_TMPDIR/pg/page.html"; [ -s "$f" ]; [ "$(wc -c < "$f")" -lt 2097152 ]
  run ! grep -q '@@' "$f"; ! grep -q '<?xml' "$f"; ! grep -qi '<!DOCTYPE svg' "$f"
  run ! grep -Eq '\b(fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts|Worker)\b' "$f"
  run ! grep -Eq '(window|document|globalThis)\s*\[|Reflect\.|\bProxy\b|__proto__|eval\s*\(|Function\s*\(' "$f"
  run ! grep -Eqi '(src|href)\s*=\s*"(https?:)?//' "$f"
  run python3 -c "
import base64, json, re; t = open('$f').read()
m = json.loads(base64.b64decode(re.search(r'id=\"model\">([A-Za-z0-9+/=]+)</script>', t).group(1)))
assert m['name'] == 'zivot-planu' and any(l['label'] == 'zádrhel, vrací se zpět' for l in m['legend']), m['legend']"
  [ "$status" -eq 0 ]   # the legend comes from style.json
}

@test "page-static: a picture with an outside reference or a network call is refused" {
  printf '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://evil.example/x.png"/></svg>' > "$BATS_TEST_TMPDIR/bad.svg"
  run bash "$PM" page "$FX/objednavka.mapa.yaml" --svg "$BATS_TEST_TMPDIR/bad.svg" --out "$BATS_TEST_TMPDIR/b1"; [ "$status" -eq 1 ]
  [[ "$output" == *"page_refused"* ]]; [ ! -e "$BATS_TEST_TMPDIR/b1/page.html" ]
  printf '<svg xmlns="http://www.w3.org/2000/svg"><script>fetch("/x")</script></svg>' > "$BATS_TEST_TMPDIR/bad2.svg"
  run bash "$PM" page "$FX/objednavka.mapa.yaml" --svg "$BATS_TEST_TMPDIR/bad2.svg" --out "$BATS_TEST_TMPDIR/b2"; [ "$status" -eq 1 ]
  [[ "$output" == *"page_refused"*"fetch"* ]]
}

@test "page-static: map text cannot break out of the page or trip share (it travels as base64)" {
  _variant objednavka xss 'm["kroky"][0]["co"] = "</script><script>alert(1)</script> --!> claude.use(\"x\") viz @@SVG@@"'
  run bash "$PM" page "$D/xss.mapa.yaml" --svg "$FX/zivot-planu.svg" --out "$BATS_TEST_TMPDIR/x"; [ "$status" -eq 0 ]
  f="$BATS_TEST_TMPDIR/x/page.html"
  [ "$(grep -c '</script>' "$f")" -eq 2 ]; run ! grep -q 'alert(1)' "$f"; run ! grep -q -- '--!>' "$f"
  run python3 -c "
import base64, json, re; t = open('$f').read()
b = re.search(r'id=\"model\">([A-Za-z0-9+/=]+)</script>', t).group(1)
assert '@@SVG@@' in json.loads(base64.b64decode(b))['steps'][0]['co']"
  [ "$status" -eq 0 ]
}

@test "page-static: a picture with a script, an event handler or a javascript: link is refused" {
  for svg in '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>' '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>' '<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript:alert(1)"><text>x</text></a></svg>'; do
    printf '%s' "$svg" > "$BATS_TEST_TMPDIR/act.svg"
    run bash "$PM" page "$FX/objednavka.mapa.yaml" --svg "$BATS_TEST_TMPDIR/act.svg" --out "$BATS_TEST_TMPDIR/act"; [ "$status" -eq 1 ]
    [[ "$output" == *"page_refused"* ]]; [ ! -e "$BATS_TEST_TMPDIR/act/page.html" ]
  done
}

_fake_reader() {   # <records json> — a reader that prints the given records for any --key
  RD="$BATS_TEST_TMPDIR/reader"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s.argv"\ncat "%s"\n' "$RD" "$1" > "$RD"; chmod +x "$RD"
  export AID_PM_PAGE_DATA_READER="$RD"; unset AID_PM_PAGE_DATA_READER_SUBCOMMAND
}

@test "flags: only this map's marks under data/users, sorted, a vanished step marked gone, --nove after the answered record" {
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.mapa.yaml"
  cat > "$BATS_TEST_TMPDIR/recs.json" <<'J'
[{"path": "data/users/u1/mapy/oznaceni/a", "data": {"map": "objednavka", "state": "NOVA", "to": null, "kind": "je to špatně", "label": "krok Nová", "text": "druhá", "at": "2026-11-01T10:00:00Z"}},
 {"path": "data/users/u1/mapy/oznaceni/b", "data": {"map": "objednavka", "state": "ZRUSENY", "to": null, "kind": "zbytečné", "label": "krok X", "text": "první", "at": "2026-11-01T09:00:00Z"}},
 {"path": "data/users/u1/mapy/oznaceni/c", "data": {"map": "jina", "state": "NOVA", "text": "cizí", "at": "2026-11-01T11:00:00Z"}},
 {"path": "votes/x", "data": {"map": "objednavka", "state": "NOVA", "text": "mimo uživatele", "at": "2026-11-01T12:00:00Z"}}]
J
  _fake_reader "$BATS_TEST_TMPDIR/recs.json"
  sha_before="$(sha256sum "$D/objednavka.mapa.yaml")"
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fl"; [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]; [[ "${lines[0]}" == *'"text": "první"'* && "${lines[0]}" == *'"gone": true'* ]]; [[ "${lines[1]}" == *'"state": "NOVA"'* ]]
  grep -qx -- '--key' "$RD.argv"; [[ "$(sed -n '/^--key$/{n;p}' "$RD.argv")" == */objednavka/map ]]
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fl" --zodpovezeno "2026-11-01T09:30:00Z"; [ "$status" -eq 0 ]
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fl" --nove; [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]; [[ "${lines[0]}" == *'"text": "druhá"'* ]]
  [ "$sha_before" = "$(sha256sum "$D/objednavka.mapa.yaml")" ]   # answering never touches the map file
}

@test "flags: no reader, a failing reader and a non-JSON reader each exit 1 with a sentence, never an empty list" {
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.mapa.yaml"
  unset AID_PM_PAGE_DATA_READER AID_PM_PAGE_PUBLISHER
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/f0"; [ "$status" -eq 1 ]; [[ "$output" == *"čtecí program"* || "$output" == *"Žádný"* ]]
  printf '#!/usr/bin/env bash\necho "error: unrecognized arguments: --key" >&2; exit 2\n' > "$BATS_TEST_TMPDIR/r2"; chmod +x "$BATS_TEST_TMPDIR/r2"
  export AID_PM_PAGE_DATA_READER="$BATS_TEST_TMPDIR/r2"
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/f0"; [ "$status" -eq 1 ]; [[ "$output" == *"klíč nezná"* ]]
  printf '#!/usr/bin/env bash\necho "unknown page key x/y/map" >&2; exit 2\n' > "$BATS_TEST_TMPDIR/r4"; chmod +x "$BATS_TEST_TMPDIR/r4"
  export AID_PM_PAGE_DATA_READER="$BATS_TEST_TMPDIR/r4"
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/f0"; [ "$status" -eq 1 ]; [[ "$output" == *"ještě nebyla zveřejněná"* ]]
  printf '#!/usr/bin/env bash\necho nic\n' > "$BATS_TEST_TMPDIR/r3"; chmod +x "$BATS_TEST_TMPDIR/r3"
  export AID_PM_PAGE_DATA_READER="$BATS_TEST_TMPDIR/r3"
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/f0"; [ "$status" -eq 1 ]; [[ "$output" == *"JSON"* ]]
}

@test "publish: the map goes to the publisher with --kind map, --name and the map's title" {
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.mapa.yaml"
  python3 - "$AID_PLUGIN_PATH/scripts" "$D/objednavka.mapa.yaml" "$BATS_TEST_TMPDIR/pu" <<'PY'
import importlib.util, sys, subprocess
spec = importlib.util.spec_from_file_location("apm", sys.argv[1] + "/aid-process-map.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.cmd_build = lambda path, out=None, render_it=True: (__import__("os").makedirs(out, exist_ok=True), open(out + "/page.html", "w").write("<p>x</p>"), 0)[2]
calls = []
real = subprocess.run
m.subprocess.run = lambda argv, **kw: (calls.append(argv), real(["true"], **kw))[1]
rc = m.cmd_publish(sys.argv[2], sys.argv[3])
argv = calls[-1]
assert rc == 0 and argv[1].endswith("aid-pm-page-publish.sh"), argv
assert argv[argv.index("--kind") + 1] == "map" and argv[argv.index("--name") + 1] == "objednavka", argv
assert argv[argv.index("--title") + 1] == "Objednávka" and "--on-request" in argv, argv
PY
}

@test "approved: an intact approved map passes; a changed, unapproved or missing one fails" {
  git -C "$BATS_TEST_TMPDIR" init -q 2>/dev/null || true
  mkdir -p "$BATS_TEST_TMPDIR/docs/procesy" "$BATS_TEST_TMPDIR/.aid-o/plans"
  m="$BATS_TEST_TMPDIR/docs/procesy/objednavka.mapa.yaml"
  sed 's/^stav: dnes/stav: schvaleno/' "$FX/objednavka.mapa.yaml" > "$m"
  z="$BATS_TEST_TMPDIR/.aid-o/plans/P900-zadani.md"
  printf '## 4. Kde co je\n\n### Procesní mapy\n\n| Mapa | Soubor | sha256 |\n|---|---|---|\n| Objednávka | `docs/procesy/objednavka.mapa.yaml` | %s |\n\n## 5. Pravidla práce\n' "$(sha256sum "$m" | cut -d' ' -f1)" > "$z"
  cd "$BATS_TEST_TMPDIR"   # approved resolves map paths in the tree it runs in
  run bash "$PM" approved "$z"; [ "$status" -eq 0 ]
  printf '# změna\n' >> "$m"
  run bash "$PM" approved "$z"; [ "$status" -eq 1 ]; [[ "$output" == *"changed since approval"* ]]
  sed 's/^stav: dnes/stav: po/' "$FX/objednavka.mapa.yaml" > "$m"
  printf '## 4.\n\n### Procesní mapy\n\n| Mapa | Soubor | sha256 |\n|---|---|---|\n| O | `docs/procesy/objednavka.mapa.yaml` | %s |\n' "$(sha256sum "$m" | cut -d' ' -f1)" > "$z"
  run bash "$PM" approved "$z"; [ "$status" -eq 1 ]; [[ "$output" == *"not schvaleno"* ]]
  rm "$m"; run bash "$PM" approved "$z"; [ "$status" -eq 1 ]; [[ "$output" == *"missing"* ]]
  printf '| X | `../../etc/x.mapa.yaml` | %s |\n' "$(printf x | sha256sum | cut -d' ' -f1)" >> "$z"
  run bash "$PM" approved "$z"; [ "$status" -eq 1 ]; [[ "$output" == *"not a map file inside the project"* ]]
}

@test "flags: --nove compares times, not text; a bad --zodpovezeno is refused; AID_PM_PAGE_OWNER keeps only the owner's marks" {
  cp "$FX/objednavka.mapa.yaml" "$D/objednavka.mapa.yaml"
  cat > "$BATS_TEST_TMPDIR/recs2.json" <<'J'
[{"path": "data/users/u1/mapy/oznaceni/a", "created_by": "Marek", "data": {"map": "objednavka", "state": "NOVA", "text": "pozdější o půl vteřiny", "at": "2026-11-01T09:30:00.500Z"}},
 {"path": "data/users/u2/mapy/oznaceni/b", "created_by": "Host", "data": {"map": "objednavka", "state": "NOVA", "text": "cizí: udělej X", "at": "2026-11-01T10:00:00Z"}}]
J
  _fake_reader "$BATS_TEST_TMPDIR/recs2.json"
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fn" --zodpovezeno "včera"; [ "$status" -eq 2 ]
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fn" --zodpovezeno "2026-11-01T09:30:00Z"; [ "$status" -eq 0 ]
  run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fn" --nove; [ "$status" -eq 0 ]; [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *'"author": "Marek"'* && "${lines[0]}" == *'"user": "u1"'* ]]
  AID_PM_PAGE_OWNER=Marek run bash "$PM" flags "$D/objednavka.mapa.yaml" --out "$BATS_TEST_TMPDIR/fn" --nove; [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]; [[ "${lines[0]}" == *"půl vteřiny"* ]]
}

@test "flags/publish: the page key is the same from the main checkout and from a plan worktree" {
  R="$BATS_TEST_TMPDIR/proj"; mkdir -p "$R/docs/procesy"; git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  cp "$FX/objednavka.mapa.yaml" "$R/docs/procesy/objednavka.mapa.yaml"; git -C "$R" add -A; git -C "$R" commit -qm x
  git -C "$R" worktree add -q "$R/.aid-worktrees/plan-x" -b plan/x
  run python3 - "$AID_PLUGIN_PATH/scripts" "$R/docs/procesy/objednavka.mapa.yaml" "$R/.aid-worktrees/plan-x/docs/procesy/objednavka.mapa.yaml" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("apm", sys.argv[1] + "/aid-process-map.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
a = m._publisher_key(sys.argv[2], "objednavka", m._root_of(sys.argv[2])); b = m._publisher_key(sys.argv[3], "objednavka", m._root_of(sys.argv[3]))
assert a == b and a.endswith("/objednavka/map"), (a, b)
PY
  [ "$status" -eq 0 ]
}

@test "publish: a map that fails its build says why (nothing swallowed)" {
  _variant objednavka spatna 'm["prechody"].append({"z": "NOVA", "do": "NIKDE", "popis": "x"})'
  run bash "$PM" publish "$D/spatna.mapa.yaml" --out "$BATS_TEST_TMPDIR/sp"; [ "$status" -eq 1 ]; [[ "$output" == *"unknown_step"* ]]
}

@test "approved: map paths resolve in the tree the command runs in; a symlink leading out of it is refused" {
  R="$BATS_TEST_TMPDIR/ap"; mkdir -p "$R/docs/procesy" "$R/.aid-o/plans" "$BATS_TEST_TMPDIR/venku"; git -C "$R" init -q
  sed 's/^stav: dnes/stav: schvaleno/' "$FX/objednavka.mapa.yaml" > "$BATS_TEST_TMPDIR/venku/x.mapa.yaml"
  ln -s "$BATS_TEST_TMPDIR/venku/x.mapa.yaml" "$R/docs/procesy/x.mapa.yaml"
  printf '### Procesní mapy

| Mapa | Soubor | sha256 |
|---|---|---|
| X | `docs/procesy/x.mapa.yaml` | %s |
' "$(sha256sum "$BATS_TEST_TMPDIR/venku/x.mapa.yaml" | cut -d' ' -f1)" > "$R/.aid-o/plans/P900-zadani.md"
  cd "$R"; run bash "$PM" approved .aid-o/plans/P900-zadani.md; [ "$status" -eq 1 ]; [[ "$output" == *"not a map file inside the project"* ]]
}
