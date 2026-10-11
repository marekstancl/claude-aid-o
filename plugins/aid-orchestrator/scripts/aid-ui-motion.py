#!/usr/bin/env python3
"""aid-ui-motion.py — the motion inventory: what of the reference's motion the directions and
the build carry, proven against what aid-ui-tool.sh motion SAW run (P108, 10. 10. 2026).

  aid-ui-motion.py inventory <project> [--force]
      From the picked reference's record (<project>/.aid-ui/refs/<picked>.motion.json, written by
      aid-ui-tool.sh motion, valid against motion-record.schema.json, url = the picked card's url)
      write <project>/.aid-ui/motion.json: one item per keyframe (by name), per transition group
      (property, scenario), per script-driven motion group (property, scenario) and one `page`
      item. Dispositions are empty: the agent fills adopt | replace | omit with a reason where the
      rules below want one; items are never invented (only `extra` may be added, with a reason).
      Refuses to overwrite a filled inventory without --force.
  aid-ui-motion.py check <project> --observed <record.json> [--dir <dir>] [--write <out.json>]
      Prove the inventory against a record of a direction prototype or of the built site:
        every item has a disposition; replace | omit carry a reason and a label (what the PM calls
        the motion); extra carries a reason; first_load_only carries a reason when the reference
        runs it every load; for adopt | replace the target was OBSERVED in the record in the item's
        scenario (keyframes: a keyframe named target; transition: a transition of that property in
        that scenario (target `property`, or `property@selector` to pin the element); js: a
        script-driven change of that property in that scenario; page: target names what carries it
        (library, leave, arrive); extra: the target observed anywhere); a `below` item must have
        been seen below; an every_load item must have run on the second load too.
        `replace` may carry `from` = the id of ANOTHER reference the PM saw (brand-state refs) whose
        record <project>/.aid-ui/refs/<from>.motion.json shows the target: the motion is taken from
        a second reference (PM 11. 10. 2026, 2B), proven on both sides - in that record and in the build.
      With --dir the record must carry dir_sha256 = the directory's sha (aid-ui-motion.py dirsha).
      Prints the summary sentence and every failure; exit 0 pass, 1 fail, 2 usage. --write stores
      {ok, failures, summary, inventory_sha256, observed_sha256, dir_sha256, checked_at}.
  aid-ui-motion.py summary <project>
      The sentence and the named replace/omit items as JSON (for the direction question's `motion`).
  aid-ui-motion.py dirsha <dir>
      sha256 over the sorted relative paths and contents of a directory (prototype or site).
  aid-ui-motion.py sha <file>
      sha256 of a file (the inventory's otisk the direction question carries in its target).
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "skills", "ui-design", "references")
DISPOSITIONS = ("adopt", "replace", "omit")
SCENARIO_OF = {"load": "load", "scroll": "scroll", "hover": "hover", "focus": "focus", "page": "page", "page-arrive": "page-arrive"}


def die(msg, code=1):
    print(f"ERROR: aid-ui-motion.py: {msg}", file=sys.stderr)
    sys.exit(code)


def rj(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def dirsha(d):
    h = hashlib.sha256()
    for root, dirs, files in os.walk(d):
        dirs.sort()
        for fn in sorted(files):
            p = os.path.join(root, fn)
            if os.path.islink(p):
                continue
            rel = os.path.relpath(p, d).replace(os.sep, "/")
            h.update(rel.encode() + b"\0" + sha_file(p).encode() + b"\n")
    return h.hexdigest()


def validate_record(rec):
    try:
        from jsonschema.validators import Draft202012Validator
    except ImportError:
        raise ValueError("python3 jsonschema is not installed (pip install jsonschema); the record cannot be validated")
    schema = rj(os.path.join(REF, "motion-record.schema.json"))
    errs = sorted(Draft202012Validator(schema).iter_errors(rec), key=lambda e: list(e.path))
    if errs:
        e = errs[0]
        return f"{'/'.join(str(x) for x in e.path) or '<root>'}: {e.message[:120]}"
    return None


def picked_ref(project):
    st = rj(os.path.join(project, "docs", "design", "brand-state.json"))
    refs = st.get("refs") or []
    picked = [r for r in refs if r.get("picked")]
    if len(picked) != 1:
        die("no single picked reference in brand-state.json (aid-ui-state.sh set refs --answer)")
    return picked[0]


def items_from_record(rec):
    items = []
    for k in rec.get("keyframes", []):
        items.append({"id": f"kf:{k['name']}", "kind": "keyframes", "name": k["name"],
                      "source": {"scenarios": k["scenarios"], "where": k["where"], "duration_ms": k.get("duration_ms"),
                                 "iteration": k.get("iteration"), "frequency": k.get("frequency"), "selectors": k.get("selectors", [])[:3],
                                 "pages": k.get("pages", [])},
                      "disposition": "", "reason": "", "label": "", "target": "", "frequency": k.get("frequency") if "load" in k["scenarios"] else None})
    for t in rec.get("transitions", []):
        items.append({"id": f"tr:{t['property']}@{t['scenario']}", "kind": "transition", "property": t["property"], "scenario": t["scenario"],
                      "source": {"scenarios": [t["scenario"]], "where": t.get("where", []), "duration_ms": t.get("duration_ms"), "selectors": t.get("selectors", [])[:3],
                                 "pages": t.get("pages", [])},
                      "disposition": "", "reason": "", "label": "", "target": ""})
    for j in rec.get("js_motion", []) or []:
        items.append({"id": f"js:{j['property']}@{j['scenario']}", "kind": "js", "property": j["property"], "scenario": j["scenario"],
                      "source": {"scenarios": [j["scenario"]], "where": j.get("where", []), "selectors": j.get("selectors", [])[:3], "pages": j.get("pages", [])},
                      "disposition": "", "reason": "", "label": "", "target": ""})
    pg = rec.get("page") or {}
    if pg.get("observed"):
        items.append({"id": "page", "kind": "page", "source": {"libs": pg.get("libs", []), "leave": pg.get("leave", [])[:4], "arrive": pg.get("arrive", [])[:4]},
                      "disposition": "", "reason": "", "label": "", "target": ""})
    order = {"load": 0, "scroll": 1, "hover": 2, "focus": 3, "page": 4, "page-arrive": 5}
    items.sort(key=lambda i: (order.get((i["source"].get("scenarios") or ["page"])[0], 9), "below" in i["source"].get("where", []), i["id"]))
    return items


def cmd_inventory(project, force):
    ref = picked_ref(project)
    path = os.path.join(project, ".aid-ui", "refs", f"{ref['id']}.motion.json")
    if not os.path.isfile(path):
        die(f"no motion record of the picked reference: {path} (aid-ui-tool.sh motion <url> <that file>)")
    rec = rj(path)
    err = validate_record(rec)
    if err:
        die(f"{path} breaks motion-record.schema.json at {err}")
    want = (ref.get("url") or "").rstrip("/")
    if want and rec.get("url", "").rstrip("/") != want:
        die(f"the record is of {rec.get('url')}, the picked reference is {ref.get('url')}")
    out = os.path.join(project, ".aid-ui", "motion.json")
    if os.path.isfile(out) and not force:
        old = rj(out)
        if any(i.get("disposition") for i in old.get("items", [])):
            die(f"{out} already has dispositions; --force overwrites")
    inv = {"tool": "aid-ui-motion-inventory", "version": 1,
           "reference": {"id": ref["id"], "url": ref.get("url"), "record": os.path.relpath(path, project), "record_sha256": rec.get("sha256")},
           "coverage": rec.get("coverage", {}), "items": items_from_record(rec), "extra": []}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(inv, f, ensure_ascii=False, indent=1)
    print(f"INVENTORY: {len(inv['items'])} items of {ref['id']} -> {out} (fill disposition / reason / target)")


def load_inventory(project):
    path = os.path.join(project, ".aid-ui", "motion.json")
    if not os.path.isfile(path):
        die(f"no {path} (aid-ui-motion.py inventory)")
    inv = rj(path)
    if inv.get("tool") != "aid-ui-motion-inventory" or not isinstance(inv.get("items"), list):
        die(f"{path} is not an inventory")
    return inv, path


def summary_of(inv):
    items = inv["items"]
    n = {"adopt": 0, "replace": 0, "omit": 0}
    named = []
    for i in items:
        d = i.get("disposition")
        if d in n:
            n[d] += 1
        if d in ("replace", "omit"):
            named.append({"id": i["id"], "label": i.get("label", ""), "disposition": d, "reason": i.get("reason", ""),
                          **({"from": i["from"]} if i.get("from") else {})})
    extra = [e for e in inv.get("extra", [])]
    sent = (f"z {len(items)} pohybů vzoru: {n['adopt']} převzato, {n['replace']} nahrazeno, {n['omit']} vynecháno"
            + (f", {len(extra)} navíc" if extra else ""))
    return {"sentence": sent, "counts": {**n, "extra": len(extra), "total": len(items)}, "exceptions": named}


def observed_index(rec):
    kf = {k["name"]: k for k in rec.get("keyframes", [])}
    tr = {(t["property"], t["scenario"]): t for t in rec.get("transitions", [])}
    js = {(j["property"], j["scenario"]): j for j in rec.get("js_motion", []) or []}
    return kf, tr, js


def second_reference(project, frm, cache):
    """The record of another reference the PM saw: (kf, tr, js) indexes, or a failure string."""
    if frm in cache:
        return cache[frm]
    try:
        st = rj(os.path.join(project, "docs", "design", "brand-state.json"))
        ids = {r.get("id") for r in (st.get("refs") or [])}
    except (OSError, ValueError):
        ids = set()
    path = os.path.join(project, ".aid-ui", "refs", f"{frm}.motion.json")
    if frm not in ids:
        res = f"from '{frm}' is not one of the references the PM saw (brand-state refs)"
    elif not os.path.isfile(path):
        res = f"from '{frm}': no record .aid-ui/refs/{frm}.motion.json (aid-ui-tool.sh motion <url> <that file>)"
    else:
        rec2 = rj(path)
        err = validate_record(rec2)
        res = f"from '{frm}': its record breaks motion-record.schema.json at {err}" if err else observed_index(rec2)
    cache[frm] = res
    return res


def seen_in(kind, target, scenario, kf, tr, js):
    if kind == "keyframes":
        return target in kf
    prop = target.partition("@")[0]
    return (prop, scenario) in tr or (prop, scenario) in js


def check_item(i, kf, tr, js, rec, failures, project=None, cache=None):
    d = i.get("disposition")
    iid = i.get("id", "?")
    if d not in DISPOSITIONS:
        failures.append(f"{iid}: disposition missing (adopt | replace | omit)")
        return
    if d in ("replace", "omit") and not (i.get("reason") or "").strip():
        failures.append(f"{iid}: {d} without a reason")
    if d in ("replace", "omit") and not (i.get("label") or "").strip():
        failures.append(f"{iid}: {d} without a label (what the PM calls this motion, e.g. 'otáčení pečeti')")
    if i.get("frequency") == "first_load_only" and i["source"].get("frequency") == "every_load" and not (i.get("reason") or "").strip():
        failures.append(f"{iid}: first_load_only without a reason (the reference runs it every load)")
    if d == "omit":
        return
    target = (i.get("target") or "").strip()
    if not target:
        failures.append(f"{iid}: {d} without a target")
        return
    kind = i.get("kind")
    src_sc = i["source"].get("scenarios") or []
    want_below = "below" in (i["source"].get("where") or [])
    frm = (i.get("from") or "").strip()
    if frm:
        if d != "replace":
            failures.append(f"{iid}: `from` is only for replace (the motion of a second reference)")
            return
        if kind == "page":
            failures.append(f"{iid}: `from` does not apply to the page transition")
            return
        r2 = second_reference(project or ".", frm, cache if cache is not None else {})
        if isinstance(r2, str):
            failures.append(f"{iid}: {r2}")
            return
        if not seen_in(kind, target, i.get("scenario"), *r2):
            failures.append(f"{iid}: replace from '{frm}': '{target}' never ran in that reference")
            return
    # adopt = the reference's motion under its own name; another target is a replace the PM must see
    if d == "adopt":
        own = i.get("name") if kind == "keyframes" else i.get("property") if kind in ("transition", "js") else None
        if own is not None and target.partition("@")[0] != own:
            failures.append(f"{iid}: adopt must keep the reference's name/property '{own}' as target (another target is a replace, which the PM sees)")
            return
    if kind == "keyframes":
        k = kf.get(target)
        if not k:
            failures.append(f"{iid}: keyframes '{target}' never ran in the observed page")
            return
        if src_sc and not set(src_sc) & set(k["scenarios"]):
            failures.append(f"{iid}: '{target}' ran in {k['scenarios']}, the reference's in {src_sc}")
        if want_below and "below" not in k["where"]:
            failures.append(f"{iid}: '{target}' was never seen below the first viewport (the reference's is)")
        if "load" in src_sc and i.get("frequency") == "every_load" and k.get("frequency") != "every_load":
            failures.append(f"{iid}: '{target}' did not run on the second load (frequency {k.get('frequency')}, inventory says every_load)")
    elif kind in ("transition", "js"):
        sc = i.get("scenario")
        prop, _, sel = target.partition("@")   # `property` or `property@selector` (the selector as the observer writes it, or a substring)
        hit = (tr if kind == "transition" else js).get((prop, sc))
        if not hit:
            # a transition the build does by script, or the other way round, still counts as the motion
            hit = (js if kind == "transition" else tr).get((prop, sc))
        if not hit:
            failures.append(f"{iid}: no {prop} {'transition' if kind == 'transition' else 'script motion'} seen in scenario {sc}")
            return
        if sel and not any(sel in s for s in hit.get("selectors") or []):
            failures.append(f"{iid}: {prop}@{sc} seen, but not on '{sel}' (seen on {', '.join((hit.get('selectors') or [])[:4])})")
        if want_below and "below" not in (hit.get("where") or []):
            failures.append(f"{iid}: {prop}@{sc} never seen below the first viewport")
    elif kind == "page":
        pg = rec.get("page") or {}
        wants = [w.strip() for w in target.split(",") if w.strip()]
        if not set(wants) <= {"library", "leave", "arrive"}:
            failures.append(f"{iid}: target must name what carries the page transition: library, leave, arrive (comma-separated)")
            return
        if "library" in wants and not pg.get("libs"):
            failures.append(f"{iid}: no page-transition library seen")
        if "leave" in wants and not pg.get("leave"):
            failures.append(f"{iid}: nothing animated while leaving the page")
        if "arrive" in wants and not pg.get("arrive"):
            failures.append(f"{iid}: nothing animated on arrival")
    else:
        failures.append(f"{iid}: unknown kind {kind}")


def check_extra(e, kf, tr, js, failures):
    iid = e.get("id", "extra")
    if not (e.get("reason") or "").strip():
        failures.append(f"{iid}: extra motion without a reason")
    target = (e.get("target") or "").strip()
    seen = target in kf or any(p == target for p, _ in tr) or any(p == target for p, _ in js)
    if not seen:
        failures.append(f"{iid}: extra '{target}' never ran in the observed page")


def check(project, observed, dir_=None):
    """The check as a function (the studio server calls it): the result dict, or raises ValueError
    when the inventory or the record cannot be read."""
    path = os.path.join(project, ".aid-ui", "motion.json")
    if not os.path.isfile(path):
        raise ValueError(f"no {path} (aid-ui-motion.py inventory)")
    inv = rj(path)
    if inv.get("tool") != "aid-ui-motion-inventory" or not isinstance(inv.get("items"), list):
        raise ValueError(f"{path} is not an inventory")
    if not os.path.isfile(observed):
        raise ValueError(f"no observed record {observed}")
    rec = rj(observed)
    err = validate_record(rec)
    if err:
        raise ValueError(f"{observed} breaks motion-record.schema.json at {err}")
    return check_records(inv, path, rec, dir_, project)


def cmd_check(project, observed, dir_, write):
    try:
        res = check(project, observed, dir_)
    except ValueError as e:
        die(str(e))
    if write:
        with open(write, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
    print(("PASS" if res["ok"] else "FAIL") + f": {res['summary']}")
    for fl in res["failures"]:
        print(f"  - {fl}")
    sys.exit(0 if res["ok"] else 1)


def check_records(inv, inv_path, rec, dir_, project=None):
    failures = []
    cache = {}
    if project is None:
        project = os.path.dirname(os.path.dirname(os.path.abspath(inv_path)))   # <project>/.aid-ui/motion.json
    if dir_:
        if not os.path.isdir(dir_):
            raise ValueError(f"no directory {dir_}")
        host = (rec.get("url") or "").split("//", 1)[-1].split("/", 1)[0].split(":")[0]
        if host not in ("127.0.0.1", "localhost", "[::1]"):
            failures.append(f"the record was observed at {rec.get('url')}, not at a locally served copy of the directory (aid-ui-tool.sh motion --dir)")
        ds = dirsha(dir_)
        if rec.get("dir_sha256") != ds:
            failures.append(f"the record was not observed over the directory as it is now (dir_sha256 {str(rec.get('dir_sha256'))[:12]} vs {ds[:12]}); observe again")
    kf, tr, js = observed_index(rec)
    for i in inv["items"]:
        check_item(i, kf, tr, js, rec, failures, project, cache)
    for e in inv.get("extra", []):
        check_extra(e, kf, tr, js, failures)
    summ = summary_of(inv)
    return {"ok": not failures, "failures": failures, "summary": summ["sentence"], "counts": summ["counts"],
            "inventory_sha256": sha_file(inv_path), "observed_sha256": rec.get("sha256"), "observed_url": rec.get("url"),
            "dir_sha256": rec.get("dir_sha256"), "checked_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat()}


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    cmd = argv[0]
    if cmd == "inventory":
        cmd_inventory(argv[1], "--force" in argv[2:])
    elif cmd == "check":
        project = argv[1]
        observed = dir_ = write = None
        rest = argv[2:]
        while rest:
            if rest[0] == "--observed" and len(rest) > 1:
                observed = rest[1]; rest = rest[2:]
            elif rest[0] == "--dir" and len(rest) > 1:
                dir_ = rest[1]; rest = rest[2:]
            elif rest[0] == "--write" and len(rest) > 1:
                write = rest[1]; rest = rest[2:]
            else:
                die(f"unknown option {rest[0]}", 2)
        if not observed:
            die("check needs --observed <record.json>", 2)
        cmd_check(project, observed, dir_, write)
    elif cmd == "summary":
        inv, _ = load_inventory(argv[1])
        print(json.dumps(summary_of(inv), ensure_ascii=False))
    elif cmd == "dirsha":
        if not os.path.isdir(argv[1]):
            die(f"no directory {argv[1]}", 2)
        print(dirsha(argv[1]))
    elif cmd == "sha":
        print(sha_file(argv[1]))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
