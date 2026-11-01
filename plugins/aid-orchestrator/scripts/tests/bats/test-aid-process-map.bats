#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-process-map.py
# Process maps: the map file's check, the deterministic layout and the drawing (P118, standard
# /ecosystem/specs/procesni-mapy). Defects it catches: a broken map accepted, two builds that differ,
# a line or a label drawn across a box, a lost added/removed marker. Files only — no browser, no network.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PM="$AID_PLUGIN_PATH/scripts/aid-process-map.sh"
  FX="$AID_PLUGIN_PATH/scripts/tests/fixtures/process-map"
  D="$BATS_TEST_TMPDIR/procesy"; mkdir -p "$D"
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
  run bash "$PM" check "$D/src.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"zdroj"* ]]
  _variant objednavka pro 'm["proti"] = "neni.mapa.yaml"'
  run bash "$PM" check "$D/pro.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"proti_missing: neni.mapa.yaml"* ]]
  _variant objednavka cesta 'm["proti"] = "../x.mapa.yaml"'
  run bash "$PM" check "$D/cesta.mapa.yaml"; [ "$status" -eq 1 ]; [[ "$output" == *"schema"*"proti"* ]]
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
  run python3 - "$BATS_TEST_TMPDIR/o/drawing.bpmn" <<'PY'
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
print(bad); sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}

@test "build: every self-loop is drawn and gateways follow branching steps" {
  run bash "$PM" build "$FX/zivot-planu.mapa.yaml" --no-render --out "$BATS_TEST_TMPDIR/s"; [ "$status" -eq 0 ]
  grep -q 'sourceRef="PLAN_SYNC" targetRef="PLAN_SYNC"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
  grep -q 'exclusiveGateway id="GW_AWAITING_PM"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
  grep -q 'textAnnotation id="ANN_ABORTED"' "$BATS_TEST_TMPDIR/s/drawing.bpmn"
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
