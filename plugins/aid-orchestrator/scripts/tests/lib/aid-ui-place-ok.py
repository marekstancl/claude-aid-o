#!/usr/bin/env python3
"""Test helper (P113): give a fixture project an accepted verdict of the named places the honest way - a frozen
critic, a round of both roles (every criterion 9) in the place's rounds folder, aid-ui-critic.py place-verdict and
aid-ui-state.sh place-record. Places are done in order with their upstream places first (web needs all five).
Missing inputs of a place get a minimal synthetic file; the project's context gets one line when it has none.

  aid-ui-place-ok.py <project> <place>...      prints PLACE <p>: accepted for each
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SC = os.path.join(HERE, "..", "..")
CRITIC, STATE = os.path.join(SC, "aid-ui-critic.py"), os.path.join(SC, "aid-ui-state.sh")
UP = {"sdeleni": [], "logo": ["sdeleni"], "pohyb": ["logo"], "struktura": [], "vzhled": ["struktura", "logo", "pohyb"],
      "web": ["vzhled", "struktura", "logo", "pohyb", "sdeleni"]}
INPUT = {"sdeleni": "docs/content/product-context.md", "logo": ".aid-ui/logo/cards/a.png",
         "pohyb": ".aid-ui/motion/a/logo-animace.html", "struktura": ".aid-ui/structure.json", "vzhled": ".aid-ui/directions/a/index.html",
         "web": "site/index.html"}


def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("place_ok: %s failed: %s" % (" ".join(cmd[:3]), (r.stderr or r.stdout).strip()))
    return r.stdout


def write(p, rel, text):
    f = os.path.join(p, rel)
    if not os.path.exists(f):
        os.makedirs(os.path.dirname(f), exist_ok=True)
        open(f, "w", encoding="utf-8").write(text)


def answer(rec, role, dirs, s=9):
    idx = []
    for e in rec["roles"][role]["rubrics"]:
        pre = "" if e["key"] == rec["place"] else e["key"] + "."
        idx += [pre + c["id"] for c in e["rubric"]["criteria"]]
    crit = [{"id": i, "score": s, "anchor": 8, "evidence": "fixture: celé místo prošlé", "missing_for_next": "detail",
             "to_ten": {"studio": ["fixture: doplnit poslední detail na celém místě"], "client": []}} for i in idx]
    a = {"findings": [], "readiness": [], "summary": "Fixture: místo prošlo."}
    if dirs == ["main"]:
        a["criteria"] = crit
    else:
        a["directions"] = [{"id": d, "rezim": "nove", "zavedeny_motiv": "ne", "criteria": crit} for d in dirs]
        if role == "owner":
            a["choice"] = dirs[0]
    return a


def current(p, place):
    return subprocess.run([sys.executable, CRITIC, "place-guard", p, "--place", place], capture_output=True).returncode == 0


def place_ok(p, place, done, asked=True):
    if place in done or (not asked and current(p, place)):   # an upstream place already decided over its current files stays
        return
    for u in UP[place]:
        place_ok(p, u, done, False)
    write(p, "docs/content/product-context.md", "# Fixture\nPodnik pro testy.\n")
    write(p, INPUT[place], {"pohyb": "<html><body>logo</body></html>", "struktura": '{"pages": []}'}.get(place, "x"))
    fz = os.path.join(p, ".aid-ui", "critic", "frozen.json" if place == "web" else "frozen/%s.json" % place)
    if not os.path.isfile(fz):
        run(sys.executable, CRITIC, "freeze", p, "--type", "web-local", "--place", place)
    rec = json.load(open(fz, encoding="utf-8"))
    dirs = json.loads(run(sys.executable, CRITIC, "bundle-directions", p, "--place", place))
    if place == "pohyb":
        for d in dirs:
            json.dump({"web_logo_draw_ms": 800, "web_logo_name_visible_ms": 0, "web_motion_running_after_ms": 500, "final_frame_diff_px": 0},
                      open(os.path.join(p, ".aid-ui", "critic", "metrics-pohyb-%s.json" % d), "w"))
    rd = os.path.join(p, ".aid-ui", "critic", "rounds", *([] if place == "web" else [place]))
    n = max([int(x) for x in os.listdir(rd) if x.isdigit()] or [0]) + 1 if os.path.isdir(rd) else 1
    scores = []
    for role in ("owner", "tech"):
        d = os.path.join(rd, str(n), role)
        os.makedirs(d, exist_ok=True)
        json.dump(answer(rec, role, dirs), open(os.path.join(d, "answer.json"), "w", encoding="utf-8"), ensure_ascii=False)
        s = os.path.join(d, "score.json")
        open(s, "w").write(run(sys.executable, CRITIC, "score", p, os.path.join(d, "answer.json"), "--role", role, "--place", place))
        scores += ["--score", s]
    json.dump({"n": n, "at": "2026-10-17T00:00:00Z", "place": place, "findings": [], "score": {"accepted": True}},
              open(os.path.join(rd, str(n), "round.json"), "w"))
    v = os.path.join(rd, str(n), "verdict.json")
    open(v, "w").write(run(sys.executable, CRITIC, "place-verdict", p, "--place", place, *scores))
    print(run("bash", STATE, "place-record", p, "--place", place, v).strip())
    done.add(place)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    done = set()
    for pl in sys.argv[2:]:
        place_ok(os.path.abspath(sys.argv[1]), pl, done)
