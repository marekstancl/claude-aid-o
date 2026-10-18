#!/usr/bin/env python3
"""aid-ui-screens.py - the model of screens and tasks of a web application (P116).

docs/design/screens.json is to an app what docs/design/structure.json is to a web: the skeleton
(lib/aid-ui-skeleton.py), the flow scenarios (aid-ui-flows.py), the gate and the handover package
(aid-ui-package.py) all read it. Shape: skills/ui-design/references/screens.schema.json; the seven states of a task
follow UA-1 of references/standards/webapp-tasks-states-standard.md (normal path = steps, the other six in states,
each a text or "nenastává, protože …").

  check <project>
      The model against the schema, then the cross rules the schema cannot say: every action's `to` and every step's
      `screen` is a screen of the model; a step's action belongs to its screen; the next step stands on the screen the
      previous action leads to and done_when.screen is where the last action leads; a destructive action carries
      `confirm`; a failure path's step exists and its `recover` is an action of that step's screen; a task with a
      submit action has a failure path or states.failure "nenastává, protože …"; `replaces` names a task of
      .aid-ui/baseline/tasks.json (no baseline = nothing to replace). Exit 0, 1 with every violation and its path,
      2 unreadable JSON or usage.

  matrix <project>
      (the model passing check) {model_sha256, rows}: the app rows of the gate - every task x normal (check
      app_flows), keyboard (keyboard_flows) and its failure variants fail-<n> (task_recovery: the model's failure
      paths, else one generated network failure on the last submit of a submitting task), every screen x empty,
      loading, error, filled (page "screen:<id>", check app_states, url = the screen's url or /<id>/).

Other scripts import load(), violations(), failure_variants() and matrix() from here (importlib), so there is one
reading of the model.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(HERE, "..", "skills", "ui-design", "references", "screens.schema.json")
NOT_HAPPENING = "nenastává, protože"


def model_path(proj):
    return os.path.join(proj, "docs", "design", "screens.json")


def load(proj):
    """The parsed model; raises OSError (missing) or ValueError (not JSON)."""
    with open(model_path(proj), encoding="utf-8") as f:
        return json.load(f)


def not_happening(text):
    t = " ".join(str(text or "").split()).lower()
    return t.startswith(NOT_HAPPENING) and len(t) > len(NOT_HAPPENING) + 2


def baseline_ids(proj):
    """(ids of .aid-ui/baseline/tasks.json, why it cannot be read); no file = no baseline, nothing to replace."""
    p = os.path.join(proj, ".aid-ui", "baseline", "tasks.json")
    if not os.path.exists(p):
        return set(), ""
    try:
        d = json.load(open(p, encoding="utf-8"))
        if not isinstance(d, list):
            raise ValueError("není seznam úloh")
        return {t.get("id") for t in d if isinstance(t, dict)}, ""
    except (OSError, ValueError) as e:
        return set(), f".aid-ui/baseline/tasks.json nejde přečíst ({e})"


def violations(m, proj):
    from jsonschema.validators import Draft202012Validator
    v = Draft202012Validator(json.load(open(SCHEMA, encoding="utf-8")))
    raw = list(v.iter_errors(m))
    out = ["/" + "/".join(str(x) for x in e.absolute_path) + ": " + e.message for e in raw]
    if not (isinstance(m, dict) and isinstance(m.get("screens"), list) and isinstance(m.get("tasks"), list)):
        return out   # no lists to cross-check
    # the cross rules run over every screen and task the schema accepted; a broken one is reported above only
    broken = {(list(e.absolute_path)[0], list(e.absolute_path)[1]) for e in raw if len(e.absolute_path) >= 2}
    sid = lambda x: x.get("id") if isinstance(x, dict) and isinstance(x.get("id"), str) else None
    ids = {sid(x) for x in m["screens"]} - {None}
    good_s = [(i, s) for i, s in enumerate(m["screens"]) if ("screens", i) not in broken]
    good_t = [(i, t) for i, t in enumerate(m["tasks"]) if ("tasks", i) not in broken]
    unsure = {sid(x) for i, x in enumerate(m["screens"]) if ("screens", i) in broken} - {None}
    screens = {}
    for i, s in good_s:
        if s["id"] in screens:
            out.append(f"/screens/{i}/id: obrazovka {s['id']} je v modelu dvakrát")
        screens[s["id"]] = s
        seen = set()
        for j, a in enumerate(s["actions"]):
            at = f"/screens/{i}/actions/{j}"
            if a["id"] in seen:
                out.append(f"{at}/id: akce {s['id']}.{a['id']} je na obrazovce dvakrát")
            seen.add(a["id"])
            if a["to"] not in ids:
                out.append(f"{at}/to: akce {s['id']}.{a['id']} vede na neexistující obrazovku {a['to']}")
            if a["kind"] == "destructive" and not a.get("confirm"):
                out.append(f"{at}: destruktivní akce {s['id']}.{a['id']} bez potvrzení (confirm)")
    if not any(isinstance(s, dict) and s.get("nav") is True for s in m["screens"]):
        out.append("/screens: žádná obrazovka není v navigaci (nav: true)")
    acts = {(s["id"], a["id"]): a for _, s in good_s for a in s["actions"]}
    base, bwhy = baseline_ids(proj)
    if bwhy:
        out.append("/tasks: " + bwhy)
    tids = set()
    for i, t in good_t:
        at = f"/tasks/{i}"
        if t["id"] in tids:
            out.append(f"{at}/id: úloha {t['id']} je v modelu dvakrát")
        tids.add(t["id"])
        lead = None   # the screen the previous action leads to
        submits = False
        for k, st in enumerate(t["steps"]):
            sa = f"{at}/steps/{k}"
            if st["screen"] in unsure:
                lead = None   # its screen failed the schema: reported there
                continue
            if st["screen"] not in screens:
                out.append(f"{sa}/screen: úloha {t['id']} krok {k + 1} stojí na neexistující obrazovce {st['screen']}")
                lead = None
                continue
            a = acts.get((st["screen"], st["action"]))
            if not a:
                out.append(f"{sa}/action: akce {st['action']} není na obrazovce {st['screen']} (úloha {t['id']}, krok {k + 1})")
                lead = None
                continue
            if lead and st["screen"] != lead:
                out.append(f"{sa}/screen: úloha {t['id']} krok {k + 1} stojí na {st['screen']}, předchozí akce vede na {lead}")
            submits = submits or a["kind"] == "submit"
            lead = a["to"]
        dw = t["done_when"]
        if dw["screen"] in unsure:
            pass
        elif dw["screen"] not in screens:
            out.append(f"{at}/done_when/screen: výsledek úlohy {t['id']} na neexistující obrazovce {dw['screen']}")
        elif lead and dw["screen"] != lead:
            out.append(f"{at}/done_when/screen: úloha {t['id']} končí na {lead}, výsledek čeká na {dw['screen']}")
        for k, fp in enumerate(t["failure_paths"]):
            fa = f"{at}/failure_paths/{k}"
            if fp["at_step"] > len(t["steps"]):
                out.append(f"{fa}/at_step: úloha {t['id']} nemá krok {fp['at_step']}")
                continue
            scr = t["steps"][fp["at_step"] - 1]["screen"]
            if scr not in unsure and (scr, fp["recover"]) not in acts:
                out.append(f"{fa}/recover: obnova {fp['recover']} není akce obrazovky {scr} (úloha {t['id']})")
        if submits and not t["failure_paths"] and not not_happening(t["states"]["failure"]):
            out.append(f"{at}/states/failure: úloha {t['id']} odesílá data, ale nemá cestu selhání (failure_paths) ani \"{NOT_HAPPENING} …\"")
        if "replaces" in t and not bwhy and t["replaces"] not in base:
            out.append(f"{at}/replaces: úloha výchozího stavu {t['replaces']} neexistuje"
                       + ("" if base else " (projekt nemá .aid-ui/baseline/tasks.json)"))
    return out


def screen_url(s):
    return s.get("url") or f"/{s['id']}/"


def failure_variants(m, t):
    """The failure variants of a task: its model's failure paths, else - for a task with a submit action - one generated
    network failure on its last submit, recovered by the same action. [{state, at_step, kind, recover, generated}]"""
    if t["failure_paths"]:
        return [dict(fp, state=f"fail-{i}", generated=False) for i, fp in enumerate(t["failure_paths"], 1)]
    kinds = {(s["id"], a["id"]): a["kind"] for s in m["screens"] for a in s["actions"]}
    subs = [k for k, st in enumerate(t["steps"], 1) if kinds.get((st["screen"], st["action"])) == "submit"]
    if not subs:
        return []
    k = subs[-1]
    return [{"state": "fail-1", "at_step": k, "kind": "network", "keeps_input": True, "recover": t["steps"][k - 1]["action"], "generated": True}]


def matrix(m):
    """The app rows of the gate (one source for aid-ui-flows.py, aid-ui-verify.mjs and aid-ui-state.sh): every task x
    normal | keyboard | its failure variants, every screen x its four states (page "screen:<id>")."""
    rows = []
    for t in m["tasks"]:
        rows += [{"page": t["id"], "state": "normal", "check": "app_flows"}, {"page": t["id"], "state": "keyboard", "check": "keyboard_flows"}]
        rows += [{"page": t["id"], "state": v["state"], "check": "task_recovery"} for v in failure_variants(m, t)]
    for s in m["screens"]:
        rows += [{"page": "screen:" + s["id"], "state": k, "check": "app_states", "url": screen_url(s)} for k in ("empty", "loading", "error", "filled")]
    return rows


def cmd_check(proj):
    try:
        m = load(proj)
    except OSError:
        print(f"ERROR: aid-ui-screens.py: chybí {model_path(proj)} (píše ho krok Obrazovky a úlohy)", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"ERROR: aid-ui-screens.py: {model_path(proj)} není JSON ({e})", file=sys.stderr)
        return 2
    errs = violations(m, proj)
    if errs:
        for e in errs:
            print("screens: " + e, file=sys.stderr)
        print(f"ERROR: aid-ui-screens.py: model má {len(errs)} chyb", file=sys.stderr)
        return 1
    print(f"SCREENS OK: {len(m['screens'])} obrazovek, {len(m['tasks'])} úloh")
    return 0


def main(a):
    if len(a) == 2 and a[0] == "check" and os.path.isdir(a[1]):
        return cmd_check(a[1])
    if len(a) == 2 and a[0] == "matrix" and os.path.isdir(a[1]):
        rc = cmd_check(a[1]) if not os.path.isfile(model_path(a[1])) else 0
        if rc:
            return rc
        m = load(a[1])
        bad = violations(m, a[1])
        if bad:
            print("ERROR: aid-ui-screens.py: matrix: the model fails check: " + "; ".join(bad[:3]), file=sys.stderr)
            return 1
        import hashlib
        print(json.dumps({"model_sha256": hashlib.sha256(open(model_path(a[1]), "rb").read()).hexdigest(), "rows": matrix(m)}, ensure_ascii=False))
        return 0
    print("usage: aid-ui-screens.py check|matrix <project>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
