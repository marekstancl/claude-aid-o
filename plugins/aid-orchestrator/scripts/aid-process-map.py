#!/usr/bin/env python3
"""aid-process-map.py — process maps (AID 3.15.0, P118).

The map file (docs/procesy/<name>.mapa.yaml) says WHAT: steps, transitions, ends, labels.
This builder decides WHERE (a deterministic left-to-right layout written as BPMN DI) and checks it;
lib/process-map/style.json is the only source of HOW it looks. Standard: /ecosystem/specs/procesni-mapy.

  check <mapa.yaml>                       schema + rules, one line per finding
  build <mapa.yaml> [--no-render] [--out DIR]   drawing (+ picture and page, Step 3)

Exit: 0 ok, 1 findings / refused, 2 usage or unreadable input.
Input boundary: the map file is text the agent or a person wrote. It is validated against the schema
(additionalProperties false everywhere, ids by pattern) before anything reads it; `proti` may only name a
sibling file (the schema's pattern has no slash), and every written text is XML-escaped.
"""
import json
import os
import re
import subprocess
import sys
from xml.sax.saxutils import escape, quoteattr

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SCHEMA = os.path.join(PLUGIN, "defaults", "schemas", "process-map.schema.json")
STYLE = os.path.join(PLUGIN, "lib", "process-map", "style.json")
SUFFIX = ".mapa.yaml"


class Refused(Exception):
    """A finding that stops the command: printed as-is, exit 1."""


def load_style():
    with open(STYLE, encoding="utf-8") as f:
        return json.load(f)


def map_name(path):
    base = os.path.basename(path)
    name = base[: -len(SUFFIX)] if base.endswith(SUFFIX) else ""
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        raise Refused(f"{path}: name: a map file is <name>{SUFFIX} with <name> matching [a-z0-9][a-z0-9-]*")
    return name


def load_map(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError) as e:
        print(f"{path}: unreadable: {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print(f"{path}: unreadable: the map is not a mapping", file=sys.stderr)
        sys.exit(2)
    return data


def schema_errors(data):
    from jsonschema.validators import Draft202012Validator
    with open(SCHEMA, encoding="utf-8") as f:
        v = Draft202012Validator(json.load(f))
    return sorted(("/".join(str(x) for x in e.absolute_path) or "(root)") + ": " + e.message
                  for e in v.iter_errors(data))


# --------------------------------------------------------------------------- rules

def is_end(step):
    return step.get("konec", "none") in ("ok", "bad")


def check_rules(path, data):
    """Every finding as 'file: rule: detail'; schema first (the rules assume a valid shape)."""
    errs = schema_errors(data)
    if errs:
        return [f"{path}: schema: {e}" for e in errs]
    out = []
    steps = data["kroky"]
    ids = [s["id"] for s in steps]
    seen = set()
    for i in ids:
        if i in seen:
            out.append(f"{path}: duplicate_id: {i}")
        seen.add(i)
    known = set(ids)
    by_id = {s["id"]: s for s in steps}
    trans = data["prechody"]
    for t in trans:
        for end in ("z", "do"):
            if t[end] not in known:
                out.append(f"{path}: unknown_step: prechod {t['z']} -> {t['do']} names {t[end]}")
    for o in data.get("odevsad", []):
        if o["do"] not in known:
            out.append(f"{path}: unknown_step: odevsad names {o['do']}")
    for q in data.get("otazky", []):
        if q["cil"] not in known:
            out.append(f"{path}: unknown_step: otazka names {q['cil']}")
    if out:
        return out
    outgoing = {i: [t for t in trans if t["z"] == i and t["do"] != i] for i in ids}
    for i in ids:
        if len(outgoing[i]) > 1:
            for t in outgoing[i]:
                if not t.get("popis"):
                    out.append(f"{path}: branch_without_label: {t['z']} -> {t['do']}")
    targets = {o["do"] for o in data.get("odevsad", [])}
    reached, todo = {ids[0]}, [ids[0]]
    while todo:
        n = todo.pop()
        for t in outgoing[n]:
            if t["do"] not in reached:
                reached.add(t["do"]); todo.append(t["do"])
    reached |= targets
    changed = True
    while changed:   # what an odevsad target leads to is reached too
        changed = False
        for n in list(reached):
            for t in outgoing.get(n, []):
                if t["do"] not in reached:
                    reached.add(t["do"]); changed = True
    for i in ids:
        if i not in reached:
            out.append(f"{path}: unreachable_step: {i}")
    for i in ids:
        s = by_id[i]
        if is_end(s):
            exits = [t for t in trans if t["z"] == i]   # a self-loop on an end is an exit too
            if exits:
                out.append(f"{path}: end_with_exit: {i} -> {exits[0]['do']}")
        elif not outgoing[i] and not (targets - {i}):
            out.append(f"{path}: dead_end: {i}")
    if data.get("proti"):
        other = os.path.join(os.path.dirname(os.path.abspath(path)), data["proti"])
        if not os.path.isfile(other):
            out.append(f"{path}: proti_missing: {data['proti']}")
        else:
            odata = load_map(other)
            out += [f"{path}: proti_invalid: {data['proti']}: {e}" for e in schema_errors(odata)]
    return out


# --------------------------------------------------------------------------- comparison

def compare(data, other):
    """Markers against the `proti` map: added (only here), removed (only there, drawn dashed)."""
    if other is None:
        return {}, {}, [], []
    mine_s = {s["id"] for s in data["kroky"]}
    theirs = {s["id"]: s for s in other["kroky"]}
    step_marks = {i: "added" for i in mine_s - set(theirs)}
    removed_steps = [s for s in other["kroky"] if s["id"] not in mine_s]
    for s in removed_steps:
        step_marks[s["id"]] = "removed"
    key = lambda t: (t["z"], t["do"])
    mine_t = {key(t) for t in data["prechody"]}
    theirs_t = {key(t) for t in other["prechody"]}
    trans_marks = {k: "added" for k in mine_t - theirs_t}
    removed_trans = [t for t in other["prechody"] if key(t) not in mine_t]
    for t in removed_trans:
        trans_marks[key(t)] = "removed"
    return step_marks, trans_marks, removed_steps, removed_trans


# --------------------------------------------------------------------------- layout

def _size(kind, st):
    sz = st["sizes"]
    return tuple(sz["task"] if kind == "task" else sz["gateway"] if kind == "gateway" else sz["event"])


def layout(data, st, removed_steps=(), removed_trans=()):
    """Nodes with integer boxes, edges with orthogonal waypoints, labels, annotations — see the standard."""
    sz = st["sizes"]
    steps = list(data["kroky"]) + list(removed_steps)
    order = {s["id"]: n for n, s in enumerate(steps)}
    by_id = {s["id"]: s for s in steps}
    targets = {o["do"]: o for o in data.get("odevsad", [])}
    trans = [t for t in list(data["prechody"]) + list(removed_trans) if t["z"] in by_id and t["do"] in by_id]
    first = steps[0]["id"]

    # nodes: steps; a gateway after a step with more than one non-self exit
    nodes = {}
    for s in steps:
        kind = "start" if s["id"] == first else ("end" if is_end(s) else "task")
        nodes[s["id"]] = {"id": s["id"], "kind": kind, "order": order[s["id"]] * 2}
    edges, selfloops = [], []
    for s in steps:
        outs = [t for t in trans if t["z"] == s["id"] and t["do"] != s["id"]]
        selfloops += [t for t in trans if t["z"] == s["id"] and t["do"] == s["id"]]
        if len(outs) > 1:
            gw = "GW-" + s["id"]
            nodes[gw] = {"id": gw, "kind": "gateway", "order": order[s["id"]] * 2 + 1}
            edges.append({"src": s["id"], "dst": gw, "label": "", "trans": None})
            edges += [{"src": gw, "dst": t["do"], "label": t.get("popis", ""), "trans": t} for t in outs]
        else:
            edges += [{"src": s["id"], "dst": t["do"], "label": t.get("popis", ""), "trans": t} for t in outs]
    adj = {n: [e for e in edges if e["src"] == n] for n in nodes}

    # back edges: an edge to a node on the depth-first stack, in file order
    state, back = {}, set()
    def dfs(n):
        state[n] = 1
        for i, e in enumerate(adj[n]):
            d = e["dst"]
            if state.get(d) == 1:
                back.add(id(e))
            elif d not in state:
                dfs(d)
        state[n] = 2
    sys.setrecursionlimit(10000)
    dfs(first)
    for n in sorted(nodes, key=lambda k: nodes[k]["order"]):
        if n not in state:
            dfs(n)
    fwd = [e for e in edges if id(e) not in back]

    # ranks: longest path over forward edges; ends and odevsad targets share the last column
    rank = {n: 0 for n in nodes}
    for _ in range(len(nodes)):
        moved = False
        for e in fwd:
            if nodes[e["dst"]]["kind"] == "end" or e["dst"] in targets or e["src"] in targets:
                continue
            if rank[e["dst"]] < rank[e["src"]] + 1:
                rank[e["dst"]] = rank[e["src"]] + 1; moved = True
        if not moved:
            break
    lastcol = lambda n: nodes[n]["kind"] == "end" or n in targets   # ends and odevsad targets share the last column
    last = max([rank[n] for n in nodes if not lastcol(n)] + [0]) + 1
    for n in nodes:
        if lastcol(n):
            rank[n] = last
    used = sorted(set(rank.values()))   # no empty column, whatever the ranks skipped
    rank = {n: used.index(r) for n, r in rank.items()}
    ncols = len(used)
    cols = [sorted([n for n in nodes if rank[n] == c], key=lambda k: nodes[k]["order"]) for c in range(ncols)]
    row = {n: r for c in cols for r, n in enumerate(c)}

    # routing: neighbouring columns = straight (same row) or an elbow inside the gap; a forward edge that skips
    # columns runs on a track ABOVE the drawing, an edge going back on a track BELOW it (one track each)
    def adjacent(e):
        return rank[e["dst"]] == rank[e["src"]] + 1
    def straight(e):
        return adjacent(e) and row[e["dst"]] == row[e["src"]]
    is_back = lambda e: rank[e["dst"]] <= rank[e["src"]]
    lanes = {}   # gap index (after column g; -1 = left margin) -> count
    def take(g):
        lanes[g] = lanes.get(g, 0) + 1
        return lanes[g] - 1
    for e in edges:
        if straight(e):
            continue
        if adjacent(e):
            e["route"] = "elbow"; e["gap_out"] = rank[e["src"]]; e["gap_out_lane"] = take(e["gap_out"])
        else:
            e["route"] = "below" if is_back(e) else "above"
            e["gap_out"], e["gap_in"] = rank[e["src"]], rank[e["dst"]] - 1
            e["gap_out_lane"], e["gap_in_lane"] = take(e["gap_out"]), take(e["gap_in"])
    cw = sz["char_width"]
    def gap_width(g):
        need = [sz["column_gap"], 20 + lanes.get(g, 0) * sz["lane_step"] + 10]
        for e in edges:
            if adjacent(e) and rank[e["src"]] == g and e["label"]:
                lane = e.get("gap_out_lane", 0) if e.get("route") == "elbow" else 0
                start = 20 + lane * sz["lane_step"] + 4 if e.get("route") == "elbow" else 4
                need.append(start + len(e["label"]) * cw + sz["label_padding"])
        return max(need)
    def name_w(n):
        return len(by_id[n]["jmeno"]) * cw if n in by_id else 0
    def node_w(n):
        w = _size("task" if nodes[n]["kind"] == "task" else nodes[n]["kind"], st)[0]
        return max(w, name_w(n)) if nodes[n]["kind"] in ("start", "end") else w
    colw = [max(node_w(n) for n in c) for c in cols]
    left = max(sz["left"], 20 + lanes.get(-1, 0) * sz["lane_step"] + 10, (name_w(first) - _size("event", st)[0]) // 2 + 10)
    colx, x = [], left
    for c in range(ncols):
        colx.append(x)
        x += colw[c] + gap_width(c)
    n_above = sum(1 for e in edges if e.get("route") == "above")
    n_below = sum(1 for e in edges if e.get("route") == "below")
    top = sz["top"] + (sz["track_margin"] + n_above * sz["track_step"] if n_above else 0)
    band = sz["row_height"] + sz["row_gap"]
    for n, node in nodes.items():
        w, h = _size("task" if node["kind"] == "task" else node["kind"], st)
        c = rank[n]
        node["x"] = colx[c] + (colw[c] - w) // 2
        node["y"] = top + row[n] * band + (sz["row_height"] - h) // 2
        node["w"], node["h"] = w, h
    maxrows = max(len(c) for c in cols)
    bottom = top + maxrows * band - sz["row_gap"]
    cx = lambda n: nodes[n]["x"] + nodes[n]["w"] // 2
    cy = lambda n: nodes[n]["y"] + nodes[n]["h"] // 2
    right = lambda n: nodes[n]["x"] + nodes[n]["w"]
    lft = lambda n: nodes[n]["x"]

    def lane_x(g, lane):
        start = (colx[g] + colw[g]) if g >= 0 else 0
        return start + 20 + lane * sz["lane_step"]

    labels = []
    lh = sz["label_height"]
    k_above = k_below = 0
    for e in edges:
        s, d = e["src"], e["dst"]
        if straight(e):
            e["wp"] = [(right(s), cy(s)), (lft(d), cy(d))]
            if e["label"]:
                labels.append({"edge": e, "x": right(s) + 4, "y": cy(s) - lh - 2, "w": len(e["label"]) * cw, "h": lh})
        elif e["route"] == "elbow":
            xg = lane_x(e["gap_out"], e["gap_out_lane"])
            e["wp"] = [(right(s), cy(s)), (xg, cy(s)), (xg, cy(d)), (lft(d), cy(d))]
            if e["label"]:
                labels.append({"edge": e, "x": xg + 4, "y": cy(d) - lh - 2, "w": len(e["label"]) * cw, "h": lh})
        else:
            if e["route"] == "above":
                ty = top - sz["track_margin"] - k_above * sz["track_step"]; k_above += 1
            else:
                ty = bottom + sz["track_margin"] + k_below * sz["track_step"]; k_below += 1
            xo = lane_x(e["gap_out"], e["gap_out_lane"])
            xi = lane_x(e["gap_in"], e["gap_in_lane"])
            e["wp"] = [(right(s), cy(s)), (xo, cy(s)), (xo, ty), (xi, ty), (xi, cy(d)), (lft(d), cy(d))]
            if e["label"]:
                labels.append({"edge": e, "x": min(xo, xi) + 4, "y": ty - lh, "w": len(e["label"]) * cw, "h": lh})
    for t in selfloops:
        n = t["z"]
        e = {"src": n, "dst": n, "label": t.get("popis", ""), "trans": t, "self": True}
        a, b, top = cx(n) - 15, cx(n) + 15, nodes[n]["y"]
        e["wp"] = [(a, top), (a, top - 15), (b, top - 15), (b, top)]
        if e["label"]:
            labels.append({"edge": e, "x": b + 4, "y": top - 15 - lh, "w": len(e["label"]) * cw, "h": lh})
        edges.append(e)
    for n, node in nodes.items():   # external names of events, as bpmn-js draws them
        if node["kind"] in ("start", "end"):
            name = by_id[n]["jmeno"]
            w = max(len(name) * cw, node["w"])   # the column is at least this wide (node_w)
            labels.append({"node": n, "x": cx(n) - w // 2, "y": node["y"] + node["h"] + 2, "w": w, "h": lh})
    annotations = []
    aw, ah = sz["annotation"]
    for k, (tid, o) in enumerate(sorted(targets.items(), key=lambda kv: order[kv[0]])):
        text = st["texts"]["odevsad_ends" if o.get("vcetne_koncu") else "odevsad"]
        ax = colx[-1] + colw[-1] + 30
        ay = nodes[tid]["y"] + nodes[tid]["h"] // 2 - ah // 2
        annotations.append({"id": "ANN-" + tid, "target": tid, "x": ax, "y": ay, "w": aw, "h": ah,
                            "text": f"{o['popis']}: {text}", "wp": [(ax, ay + ah // 2), (right(tid), cy(tid))]})
    warn = {e["src"][3:] if e["src"].startswith("GW-") else e["src"] for e in edges if e.get("route") == "below"}
    return {"nodes": nodes, "edges": edges, "labels": labels, "annotations": annotations, "back": back,
            "warn": warn, "width": max([a["x"] + a["w"] for a in annotations] + [x]) + 20,
            "height": bottom + sz["track_margin"] + n_below * sz["track_step"] + 20}


# --------------------------------------------------------------------------- overlap check

def _rect_hit(ax, ay, aw, ah, bx, by, bw, bh):
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def _seg_hits_rect(p, q, r):
    (x1, y1), (x2, y2) = p, q
    rx, ry, rw, rh = r
    if x1 == x2:
        lo, hi = sorted((y1, y2))
        return rx < x1 < rx + rw and lo < ry + rh and ry < hi
    lo, hi = sorted((x1, x2))
    return ry < y1 < ry + rh and lo < rx + rw and rx < hi


def overlaps(lay):
    """Every pair where a shape, a line segment or a label crosses another shape; [] means none."""
    shapes = [(n["id"], (n["x"], n["y"], n["w"], n["h"])) for n in lay["nodes"].values()]
    shapes += [(a["id"], (a["x"], a["y"], a["w"], a["h"])) for a in lay["annotations"]]
    out = []
    for i, (a, ra) in enumerate(shapes):
        for b, rb in shapes[i + 1:]:
            if _rect_hit(*ra, *rb):
                out.append((a, b))
    for e in lay["edges"]:
        own = {e["src"], e["dst"]}
        for p, q in zip(e["wp"], e["wp"][1:]):
            for sid, r in shapes:
                if sid not in own and _seg_hits_rect(p, q, r):
                    out.append((f"{e['src']}->{e['dst']}", sid))
    for a in lay["annotations"]:
        for sid, r in shapes:
            if sid not in (a["id"], a["target"]) and _seg_hits_rect(a["wp"][0], a["wp"][1], r):
                out.append((a["id"], sid))
    labs = lay["labels"]
    for i, a in enumerate(labs):
        for b in labs[i + 1:]:
            if _rect_hit(a["x"], a["y"], a["w"], a["h"], b["x"], b["y"], b["w"], b["h"]):
                na = a.get("node") or f"{a['edge']['src']}->{a['edge']['dst']}"
                nb = b.get("node") or f"{b['edge']['src']}->{b['edge']['dst']}"
                out.append((f"label {na}", f"label {nb}"))
    for l in lay["labels"]:
        own = {l.get("node")}
        for sid, r in shapes:
            if sid not in own and _rect_hit(l["x"], l["y"], l["w"], l["h"], *r):
                name = l.get("node") or f"{l['edge']['src']}->{l['edge']['dst']}"
                out.append((f"label {name}", sid))
    return sorted(set(out))


# --------------------------------------------------------------------------- writers

def _role(step, lay):
    if step.get("konec") == "ok":
        return "ok"
    if step.get("konec") == "bad":
        return "bad"
    if step.get("ceka"):
        return "pm"
    if step["id"] in lay["warn"]:
        return "warn"
    return "default"


def write_bpmn(data, lay):
    """BPMN 2.0 XML with DI; fixed element order, integer coordinates, no timestamp."""
    by_id = {s["id"]: s for s in data["kroky"]}
    by_id.update({s["id"]: s for s in lay.get("removed_steps", [])})
    nodes = sorted(lay["nodes"].values(), key=lambda n: n["order"])
    flows = []
    for k, e in enumerate(lay["edges"]):
        e["fid"] = f"F-{k}"
        flows.append(e)
    inc = {n["id"]: [f["fid"] for f in flows if f["dst"] == n["id"]] for n in nodes}
    out_ = {n["id"]: [f["fid"] for f in flows if f["src"] == n["id"]] for n in nodes}
    L = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" '
         'xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" '
         'xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Definitions-" targetNamespace="aid:process-map">',
         f'  <bpmn:process id="Process-" name={quoteattr(data["nazev"])} isExecutable="false">']
    tag = {"start": "startEvent", "end": "endEvent", "task": "task", "gateway": "exclusiveGateway"}
    for n in nodes:
        name = "" if n["kind"] == "gateway" else f' name={quoteattr(by_id[n["id"]]["jmeno"])}'
        L.append(f'    <bpmn:{tag[n["kind"]]} id="{n["id"]}"{name}>')
        L += [f"      <bpmn:incoming>{f}</bpmn:incoming>" for f in inc[n["id"]]]
        L += [f"      <bpmn:outgoing>{f}</bpmn:outgoing>" for f in out_[n["id"]]]
        L.append(f'    </bpmn:{tag[n["kind"]]}>')
    for f in flows:
        name = f' name={quoteattr(f["label"])}' if f["label"] else ""
        L.append(f'    <bpmn:sequenceFlow id="{f["fid"]}" sourceRef="{f["src"]}" targetRef="{f["dst"]}"{name} />')
    for a in lay["annotations"]:
        L.append(f'    <bpmn:textAnnotation id="{a["id"]}"><bpmn:text>{escape(a["text"])}</bpmn:text></bpmn:textAnnotation>')
        L.append(f'    <bpmn:association id="AS-{a["target"]}" sourceRef="{a["id"]}" targetRef="{a["target"]}" />')
    L.append("  </bpmn:process>")
    L.append('  <bpmndi:BPMNDiagram id="Diagram-"><bpmndi:BPMNPlane id="Plane-" bpmnElement="Process-">')
    lab = {l["node"]: l for l in lay["labels"] if "node" in l}
    elab = {id(l["edge"]): l for l in lay["labels"] if "edge" in l}
    for n in nodes:
        L.append(f'    <bpmndi:BPMNShape id="{n["id"]}-di" bpmnElement="{n["id"]}">'
                 f'<dc:Bounds x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" />')
        if n["id"] in lab:
            l = lab[n["id"]]
            L.append(f'      <bpmndi:BPMNLabel><dc:Bounds x="{l["x"]}" y="{l["y"]}" width="{l["w"]}" height="{l["h"]}" /></bpmndi:BPMNLabel>')
        L.append("    </bpmndi:BPMNShape>")
    for f in flows:
        L.append(f'    <bpmndi:BPMNEdge id="{f["fid"]}-di" bpmnElement="{f["fid"]}">')
        L += [f'      <di:waypoint x="{x}" y="{y}" />' for x, y in f["wp"]]
        if id(f) in elab:
            l = elab[id(f)]
            L.append(f'      <bpmndi:BPMNLabel><dc:Bounds x="{l["x"]}" y="{l["y"]}" width="{l["w"]}" height="{l["h"]}" /></bpmndi:BPMNLabel>')
        L.append("    </bpmndi:BPMNEdge>")
    for a in lay["annotations"]:
        L.append(f'    <bpmndi:BPMNShape id="{a["id"]}-di" bpmnElement="{a["id"]}">'
                 f'<dc:Bounds x="{a["x"]}" y="{a["y"]}" width="{a["w"]}" height="{a["h"]}" /></bpmndi:BPMNShape>')
        L.append(f'    <bpmndi:BPMNEdge id="AS-{a["target"]}-di" bpmnElement="AS-{a["target"]}">'
                 + "".join(f'<di:waypoint x="{x}" y="{y}" />' for x, y in a["wp"]) + "</bpmndi:BPMNEdge>")
    L.append("  </bpmndi:BPMNPlane></bpmndi:BPMNDiagram>")
    L.append("</bpmn:definitions>")
    return "\n".join(L) + "\n"


def _mm(text):
    return text.replace('"', "'").replace("\n", " ").replace(":", " -")


def write_mermaid(data, st, lay):
    """Mermaid stateDiagram-v2; ids prefixed s_ and classes r_ (Mermaid keywords cannot collide);
    a note as a block (a colon inside a one-line note breaks the parser); deterministic."""
    steps = list(data["kroky"]) + list(lay.get("removed_steps", []))
    sid = lambda i: "s_" + i
    L = ["stateDiagram-v2", "  direction LR"]
    for s in steps:
        L.append(f'  state "{_mm(s["jmeno"])}" as {sid(s["id"])}')
    L.append(f"  [*] --> {sid(steps[0]['id'])}")
    for t in list(data["prechody"]) + list(lay.get("removed_trans", [])):
        lbl = f" : {_mm(t['popis'])}" if t.get("popis") else ""
        L.append(f"  {sid(t['z'])} --> {sid(t['do'])}{lbl}")
    for s in steps:
        if is_end(s):
            L.append(f"  {sid(s['id'])} --> [*]")
    for o in data.get("odevsad", []):
        text = st["texts"]["odevsad_ends" if o.get("vcetne_koncu") else "odevsad"]
        L += [f"  note right of {sid(o['do'])}", f"    {_mm(o['popis'])} - {text}", "  end note"]
    roles = st["roles"]
    for r in ("default", "ok", "bad", "warn", "pm"):
        L.append(f"  classDef r_{r} fill:{roles[r]['fill']},stroke:{roles[r]['stroke']}")
    for s in steps:
        L.append(f"  class {sid(s['id'])} r_{_role(s, lay)}")
    return "\n".join(L) + "\n"


def model_json(data, st, lay, step_marks, trans_marks):
    """What the page reads: names, sentences, roles, markers, questions — no geometry."""
    steps = list(data["kroky"]) + list(lay.get("removed_steps", []))
    trans = list(data["prechody"]) + list(lay.get("removed_trans", []))
    m = {"nazev": data["nazev"], "druh": data["druh"], "stav": data["stav"],
         "steps": [], "transitions": [], "odevsad": data.get("odevsad", []), "otazky": data.get("otazky", []),
         "legend": [{"role": r, "label": v["label"], "fill": v.get("fill"), "stroke": v["stroke"]}
                    for r, v in st["roles"].items()]}
    for s in steps:
        m["steps"].append({"id": s["id"], "jmeno": s["jmeno"], "co": s["co"], "kod": s.get("kod", []),
                           "role": _role(s, lay), "marker": step_marks.get(s["id"])})
    for t in trans:
        m["transitions"].append({"z": t["z"], "do": t["do"], "popis": t.get("popis", ""),
                                 "marker": trans_marks.get((t["z"], t["do"]))})
    return json.dumps(m, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


# --------------------------------------------------------------------------- commands

def work_dir(path, name, out=None):
    """Build output: --out, else <repo root>/.aid-o/work/process-maps/<name>/ (never committed)."""
    if out:
        return out
    d = os.path.dirname(os.path.abspath(path))
    try:
        root = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        root = d
    return os.path.join(root, ".aid-o", "work", "process-maps", name)


def cmd_check(path):
    data = load_map(path)
    try:
        map_name(path)
    except Refused as e:
        print(e); return 1
    errs = check_rules(path, data)
    for e in errs:
        print(e)
    return 1 if errs else 0


def build_drawing(path, data, st):
    other = None
    if data.get("proti"):
        other = load_map(os.path.join(os.path.dirname(os.path.abspath(path)), data["proti"]))
    step_marks, trans_marks, rs, rt = compare(data, other)
    lay = layout(data, st, rs, rt)
    lay["removed_steps"], lay["removed_trans"] = rs, rt
    hits = overlaps(lay) if data["druh"] == "bpmn" else []   # Mermaid lays out a state diagram itself
    if hits:
        raise Refused("\n".join(f"{path}: layout_overlap: {a} {b}" for a, b in hits))
    drawing = write_bpmn(data, lay) if data["druh"] == "bpmn" else write_mermaid(data, st, lay)
    return drawing, model_json(data, st, lay, step_marks, trans_marks), lay


def cmd_build(path, out=None, render=True):
    data = load_map(path)
    try:
        name = map_name(path)
    except Refused as e:
        print(e); return 1
    errs = check_rules(path, data)
    if errs:
        for e in errs:
            print(e)
        return 1
    st = load_style()
    try:
        drawing, model, _ = build_drawing(path, data, st)
    except Refused as e:
        print(e); return 1
    wd = work_dir(path, name, out)
    os.makedirs(wd, exist_ok=True)
    ext = "bpmn" if data["druh"] == "bpmn" else "mmd"
    for fname, text in ((f"drawing.{ext}", drawing), ("model.json", model)):
        with open(os.path.join(wd, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print(os.path.join(wd, f"drawing.{ext}"))
    return 0


def main(argv):
    if len(argv) < 2 or argv[0] not in ("check", "build"):
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    cmd, path, rest = argv[0], argv[1], argv[2:]
    if cmd == "check":
        if rest:
            print(f"aid-process-map: check takes one map file, got extra: {' '.join(rest)}", file=sys.stderr)
            return 2
        return cmd_check(path)
    out, render = None, True
    while rest:
        a = rest.pop(0)
        if a == "--no-render":
            render = False
        elif a == "--out" and rest:
            out = rest.pop(0)
        else:
            print(f"aid-process-map: unknown argument {a}", file=sys.stderr)
            return 2
    return cmd_build(path, out, render)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
