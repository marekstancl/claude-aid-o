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
import json, os, re, sys

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
    modes = {x.get("id") for x in m.get("modes") or [] if isinstance(x, dict)}
    vals = m.get("values") or {}
    def refs(text, where):   # every {key} of a text is a named value of the model: one number, one place
        for k in re.findall(r"\{([a-z][a-z0-9_]*)\}", str(text or "")):
            if k not in vals:
                out.append(f"{where}: {{{k}}} není pojmenovaná hodnota modelu (values)")
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
            if a["kind"] == "destructive" and not (a.get("confirm") and a.get("confirm_yes") and a.get("confirm_no")):
                out.append(f"{at}: destruktivní akce {s['id']}.{a['id']} bez potvrzení (confirm, confirm_yes, confirm_no: otázka a tlačítka, která jmenují akci)")
            for md in a.get("modes") or []:
                if md not in modes:
                    out.append(f"{at}/modes: režim {md} model nezná (modes)")
            if a.get("after") and a["after"] not in {t.get("id") for t in m["tasks"] if isinstance(t, dict)}:
                out.append(f"{at}/after: úloha {a['after']} v modelu není (akce {s['id']}.{a['id']} se ukáže po ní)")
            if a.get("external") and a["kind"] != "navigate":
                out.append(f"{at}/external: vnější adresu má jen akce navigate")
            if "item" in a and a["item"] >= len(s.get("sample") or []):
                out.append(f"{at}: akce {s['id']}.{a['id']} patří k řádku ukázky {a['item']}, obrazovka má {len(s.get('sample') or [])} řádků (sample)")
            if a.get("modes") and not a.get("disabled_reason"):
                out.append(f"{at}: akce {s['id']}.{a['id']} jde jen v některých režimech, ale neříká proč jinak ne (disabled_reason)")
    if sum(1 for s in m["screens"] if isinstance(s, dict) and s.get("shell") is True) > 1:
        out.append("/screens: lišta (shell: true) je jen jedna")
    if not any(isinstance(s, dict) and s.get("nav") is True and not s.get("shell") for s in m["screens"]):
        out.append("/screens: žádná obrazovka není v navigaci (nav: true)")
    for i, s in good_s:
        for k, txt in [("purpose", s["purpose"])] + [("states/" + x, y) for x, y in s["states"].items()] + [(f"sample/{j}", x) for j, x in enumerate(s.get("sample") or [])] \
                + [(f"tables/{j}/caption", tb["caption"]) for j, tb in enumerate(s.get("tables") or [])] \
                + [(f"tables/{j}/columns/{c}", x) for j, tb in enumerate(s.get("tables") or []) for c, x in enumerate(tb["columns"])] \
                + [(f"tables/{j}/rows/{r}/{c}", x) for j, tb in enumerate(s.get("tables") or []) for r, row in enumerate(tb["rows"]) for c, x in enumerate(row)]:
            refs(txt, f"/screens/{i}/{k}")
        for md, rows in (s.get("mode_sample") or {}).items():
            if md not in modes:
                out.append(f"/screens/{i}/mode_sample: režim {md} model nezná (modes)")
            for j, x in enumerate(rows):
                refs(x, f"/screens/{i}/mode_sample/{md}/{j}")
        for j, tb in enumerate(s.get("tables") or []):
            if any(len(row) != len(tb["columns"]) for row in tb["rows"]):
                out.append(f"/screens/{i}/tables/{j}: řádek tabulky {tb['caption']} nemá tolik buněk, kolik je sloupců")
        for j, a in enumerate(s["actions"]):
            for k in ("label", "confirm", "confirm_yes", "confirm_no", "disabled_reason"):
                refs(a.get(k), f"/screens/{i}/actions/{j}/{k}")
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
        if t.get("then_mode") and t["then_mode"] not in modes:
            out.append(f"{at}/then_mode: režim {t['then_mode']} model nezná (modes)")
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
            if screens[st["screen"]].get("shell"):   # the bar stands on every screen: a step on it follows any screen
                submits = submits or a["kind"] == "submit"
                lead = a["to"]
                continue
            if lead and st["screen"] != lead:
                out.append(f"{sa}/screen: úloha {t['id']} krok {k + 1} stojí na {st['screen']}, předchozí akce vede na {lead}")
            submits = submits or a["kind"] == "submit"
            if a["kind"] == "submit" and "item" not in a:   # the screen's form sends its required fields too (P116 pilot: zmenit-paku)
                own = {n for tt in m["tasks"] if isinstance(tt, dict) for x in tt.get("steps") or [] if isinstance(x, dict) and x.get("screen") == st["screen"]
                       and "item" in (acts.get((st["screen"], x.get("action"))) or {}) for n in x.get("input") or {}}
                need = [f["name"] for f in screens[st["screen"]].get("fields") or [] if f.get("required") and f["name"] not in own]
                miss = [n for n in need if n not in (st.get("input") or {})]
                if miss:
                    out.append(f"{sa}/input: úloha {t['id']} krok {k + 1} odešle formulář {st['screen']} bez povinného pole {', '.join(miss)}")
            lead = a["to"]
        if t.get("mode") and t["mode"] not in modes:
            out.append(f"{at}/mode: režim {t['mode']} model nezná (modes)")
        refs(t["done_when"]["expect"], f"{at}/done_when/expect")
        for k, txt in t["states"].items():
            refs(txt, f"{at}/states/{k}")
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
    rids = set()
    for i, r in enumerate(m.get("requirements") or []):   # the trace: every requirement covered by the model or out of scope
        at = f"/requirements/{i}"
        if r["id"] in rids:
            out.append(f"{at}/id: požadavek {r['id']} je ve stopě dvakrát")
        rids.add(r["id"])
        if bool(r.get("covered_by")) == bool(r.get("out_of_scope")):
            out.append(f"{at}: požadavek {r['id']} má buď covered_by (kde ho model pokrývá), nebo out_of_scope (proč ne), právě jedno")
        for ref in r.get("covered_by") or []:
            kind, rid = ref.split(":", 1)
            if rid not in (tids if kind == "task" else ids):
                out.append(f"{at}/covered_by: {ref} není {'úloha' if kind == 'task' else 'obrazovka'} modelu")
        f = r["source"].rsplit(":", 1)
        full = os.path.realpath(os.path.join(proj, f[0]))
        if not full.startswith(os.path.realpath(proj) + os.sep) or not os.path.isfile(full) \
                or not 1 <= int(f[1]) <= len(open(full, encoding="utf-8", errors="replace").read().splitlines()):
            out.append(f"{at}/source: {r['source']} není soubor:řádek v projektu")
    # P118: the facts of an existing app (aid-ui-client.py facts): no open question, no quote that left its source
    facts_ids = None
    ff = os.path.join(proj, "docs", "design", "app-facts.json") if proj else None
    if ff and os.path.isfile(ff):
        sys.path.insert(0, os.path.join(HERE, "lib"))
        import aid_ui_memory as mem
        try:
            fd = json.load(open(ff, encoding="utf-8"))
        except ValueError as e:
            fd = {}; out.append(f"/app-facts: docs/design/app-facts.json není čitelný JSON ({e})")
        facts_ids = {x.get("id") for x in fd.get("facts") or [] if isinstance(x, dict)}
        if fd.get("open"):
            out.append(f"/app-facts: {len(fd['open'])} otevřených otázek (oba vytěžovače se neshodly): " + ", ".join(str(o.get("fact", {}).get("id")) for o in fd["open"][:6])
                       + " - aid-ui-client.py facts --focus, nebo --drop <id> --reason")
        for x in fd.get("facts") or []:
            for so in x.get("sources") or []:
                e = mem.source_ok(proj, so.get("source"), so.get("quote"))
                if e:
                    out.append(f"/app-facts/{x.get('id')}: zdroj zestárl ({e}) - vytěž fakta znovu")
    # P118 lint: the classes of findings the roles kept raising in the P116 pilot, decided by code before any gate
    KEY = re.compile(r"\{[a-z][a-z0-9_]*\}")
    UNIT = re.compile(r"(?<![\w{])[+−-]?[$€]?\d[\d\u00a0 ,.]*\s?(?:USDT|USD|EUR|CZK|Kč|R|%|×|x)(?![\w])|[$€]\s?\d[\d\u00a0 ,.]*")
    DIGIT = re.compile(r"(?<![A-Za-z\d])\d")   # a digit that is not part of a code like F1 or R12
    def lit(txt, where):   # an amount, R, percent or leverage written out instead of a named value: two places can disagree
        for x in UNIT.findall(KEY.sub("", str(txt or ""))):
            out.append(f"{where}: číslo s jednotkou „{x.strip()}“ napsané přímo - patří do values a sem jako {{klíč}} (jedno číslo, jedno místo)")
    for i, s in good_s:
        if DIGIT.search(KEY.sub("", s["purpose"])):
            out.append(f"/screens/{i}/purpose: účel obrazovky nese číslo („{s['purpose'][max(0, DIGIT.search(KEY.sub('', s['purpose'])).start() - 15):][:40]}…“) - čísla, časy a pravidla patří do ukázky, stavu nebo values")
        lit(s["title"], f"/screens/{i}/title")
        for j, x in enumerate(s.get("sample") or []):
            lit(x, f"/screens/{i}/sample/{j}")
        for md, rows in (s.get("mode_sample") or {}).items():
            for j, x in enumerate(rows):
                lit(x, f"/screens/{i}/mode_sample/{md}/{j}")
        for j, tb in enumerate(s.get("tables") or []):
            lit(tb["caption"], f"/screens/{i}/tables/{j}/caption")
            for r, row in enumerate(tb["rows"]):
                for c, x in enumerate(row):
                    lit(x, f"/screens/{i}/tables/{j}/rows/{r}/{c}")
        for k, x in s["states"].items():
            lit(x, f"/screens/{i}/states/{k}")
        for j, f in enumerate(s.get("fields") or []):
            for k in ("label", "hint", "error"):
                lit(f.get(k), f"/screens/{i}/fields/{j}/{k}")
        for j, d in enumerate(s.get("data") or []):
            for k in ("what", "freshness"):   # source names files and lines: not checked
                lit(d.get(k), f"/screens/{i}/data/{j}/{k}")
        for j, a in enumerate(s["actions"]):
            for k in ("label", "confirm", "confirm_yes", "confirm_no", "disabled_reason"):
                lit(a.get(k), f"/screens/{i}/actions/{j}/{k}")
    for j, g in enumerate(m.get("glossary") or []):
        lit(g.get("meaning") if isinstance(g, dict) else None, f"/glossary/{j}/meaning")
    for j, x in enumerate(m.get("out_of_scope") or []):
        if isinstance(x, dict):
            lit(x.get("what"), f"/out_of_scope/{j}/what"); lit(x.get("why"), f"/out_of_scope/{j}/why")
    for i, t in good_t:
        lit(t["title"], f"/tasks/{i}/title")
        for k, x in t["states"].items():
            lit(x, f"/tasks/{i}/states/{k}")
        lit(t["done_when"]["expect"], f"/tasks/{i}/done_when/expect")
        for j, fp in enumerate(t["failure_paths"]):
            lit(fp.get("text"), f"/tasks/{i}/failure_paths/{j}/text")
        wsteps = [n for n, st in enumerate(t["steps"], 1) if (acts.get((st["screen"], st["action"])) or {}).get("kind") in ("submit", "destructive")]
        if t.get("local"):   # writes in the browser only: said by the model's flag, and then no failure can reach a server
            if not str(t["states"]["failure"]).strip().lower().startswith("nenastává"):
                out.append(f"/tasks/{i}/local: úloha {t['id']} je označená jako jen v prohlížeči, stav selhání pak musí být „nenastává, protože …“")
            continue
        if not wsteps:
            continue
        if facts_ids is not None:   # an existing app: the task's behaviour rests on agreed facts of what the app does
            miss = [x for x in t.get("facts") or [] if x not in facts_ids]
            if not t.get("facts"):
                out.append(f"/tasks/{i}/facts: úloha {t['id']} zapisuje, ale neodkazuje na fakta appky (app-facts.json), o která se její chování opírá")
            elif miss:
                out.append(f"/tasks/{i}/facts: {', '.join(miss)} není dohodnutý fakt v app-facts.json")
        perm = str(t["states"]["permission"]).strip()
        if perm.lower().startswith(("nenastává", "nenastane")) or len(perm) < 20:
            out.append(f"/tasks/{i}/states/permission: úloha {t['id']} zapisuje - stav oprávnění říká, kdo nesmí a co uvidí (ne „nenastává“ ani prázdná věta)")
        for n in wsteps:   # every writing step: a dropped connection and a refusal, each with what the person sees
            at = [fp for fp in t["failure_paths"] if fp["at_step"] == n]
            for need, kinds in (("sítě (network)", {"network"}), ("odmítnutí serverem (server nebo validation)", {"server", "validation"})):
                hit = [fp for fp in at if fp["kind"] in kinds]
                if not hit:
                    out.append(f"/tasks/{i}/failure_paths: úloha {t['id']} krok {n} zapisuje - chybí cesta selhání {need}")
                elif not any(str(fp.get("text") or "").strip() for fp in hit):
                    out.append(f"/tasks/{i}/failure_paths: úloha {t['id']} krok {n} - cesta selhání {need} nemá text (co člověk uvidí a co udělá)")
    return out


def resolved(m):
    """The model with every {key} of its texts replaced by the named value (values): the one reading of the numbers the
    skeleton, the scenarios and the package all use."""
    vals = {k: v["value"] for k, v in (m.get("values") or {}).items()}
    def walk(x):
        if isinstance(x, str):
            return re.sub(r"\{([a-z][a-z0-9_]*)\}", lambda g: vals.get(g.group(1), g.group(0)), x)
        if isinstance(x, list):
            return [walk(y) for y in x]
        if isinstance(x, dict):
            return {a: walk(b) for a, b in x.items()}
        return x
    return walk(m)


def task_state_url(m, t):
    """Where a task's states show: the screen of its first step (the home screen when that is the bar)."""
    scr = {s["id"]: s for s in m["screens"]}
    first = scr[t["steps"][0]["screen"]]
    if first.get("shell"):
        first = next(s for s in m["screens"] if s["nav"] and not s.get("shell"))
    return screen_url(first), first["id"]


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
    for t in m["tasks"]:   # every task's six non-path states can be shown (?stav=<task>.<state>) and are checked
        u, sid = task_state_url(m, t)
        rows += [{"page": "task:" + t["id"], "state": k, "check": "app_states", "url": u, "screen": sid}
                 for k in ("validation", "empty", "loading", "failure", "permission", "recovery")]
    for s in m["screens"]:
        if s.get("shell"):   # the bar has no page of its own: it is checked on every screen's page
            continue
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
