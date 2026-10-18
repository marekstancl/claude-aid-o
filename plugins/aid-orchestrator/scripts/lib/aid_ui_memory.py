"""aid_ui_memory - the evaluator's memory of the two roles (P113, pamet-hodnotitele.md).

Derived every time from what exists, never stored twice: a role's rounds at a place (its findings, what the studio
did with them, its scores and path to 10 per round, since the place's last reopen) and, for the client, its answers in
the studio (.aid-ui/studio/history.jsonl, by: client) beside the PM's decisions (by: pm, shown as the PM's). The
expert remembers one place; the client every place. The blind audit reads none of it.
"""
import json, os

PLACES = ("sdeleni", "logo", "pohyb", "struktura", "vzhled", "web")
LAUNCH_DIR = os.path.join(".aid-ui", "critic", "launch")


def critic_dir(p):
    """Where a loop keeps its frozen roles, rounds, runs and verdict: .aid-ui/critic, or the launch rating's own
    .aid-ui/critic/launch when AID_UI_CRITIC_DIR says so (P115: aid-ui-quality.py --launch sets it for every script
    it starts, so the rating after the deployment never touches the build's). The competitors stay in .aid-ui/critic."""
    v = os.environ.get("AID_UI_CRITIC_DIR") or ""
    if v and v != LAUNCH_DIR:   # one value only: never a path a stray environment could point anywhere
        raise SystemExit("ERROR: AID_UI_CRITIC_DIR may only be %s (the launch rating), not %r" % (LAUNCH_DIR, v))
    return os.path.join(p, v or os.path.join(".aid-ui", "critic"))


def rounds_dir(p, place):
    return os.path.join(critic_dir(p), "rounds", *([] if place == "web" else [place]))


def reopened_at(p, place):
    f = os.path.join(critic_dir(p), "loop-reopened.json") if place == "web" else os.path.join(rounds_dir(p, place), "reopened.json")
    try:
        return json.load(open(f, encoding="utf-8"))[-1]["at"]
    except (OSError, ValueError, IndexError, KeyError):
        return ""


def rounds(p, place):
    d = rounds_dir(p, place)
    ns = sorted(int(x) for x in os.listdir(d) if x.isdigit()) if os.path.isdir(d) else []
    return [json.load(open(os.path.join(d, str(n), "round.json"), encoding="utf-8")) for n in ns
            if os.path.isfile(os.path.join(d, str(n), "round.json"))]


def place_memory(p, role, place):
    """{place, findings, ratings} of one role at one place since its reopen; None when the role has not rated it."""
    since = reopened_at(p, place)
    rs = [r for r in rounds(p, place) if r.get("at", "") >= since and not r.get("audit")]
    if not rs:
        return None
    finds = [{"id": f["id"], "round": r["n"], "criterion": f["criterion"], "where": f.get("where"), "text": f["text"],
              "state": "fixed" if f.get("state") == "accepted" and f.get("evidence") else f.get("state"),
              "reason": f.get("reason"), "evidence": f.get("evidence")}
             for r in rs for f in r.get("findings") or [] if f.get("role") == role]
    return {"place": place, "findings": finds,
            "ratings": [{"round": r["n"], "scores": {k.split(".", 1)[1]: v for k, v in ((r.get("score") or {}).get("criteria") or {}).items() if k.startswith(role + ".")},
                         "to_ten": (r.get("to_ten") or {}).get(role) or {}} for r in rs]}


def studio_answers(p):
    """(the client's own answers, the PM's decisions) from the studio history; a line that is not JSON stops with its
    number (a silent empty memory would let the client forget what it said)."""
    f = os.path.join(p, ".aid-ui", "studio", "history.jsonl")
    own, pm = [], []
    try:
        lines = open(f, encoding="utf-8").read().splitlines()
    except OSError:
        return own, pm
    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            e = json.loads(line)
        except ValueError:
            raise ValueError("%s line %d is not JSON: the client's memory cannot be read" % (f, i))
        if not isinstance(e, dict) or e.get("by") not in ("client", "pm") or not isinstance(e.get("answer"), dict) or not isinstance(e.get("question"), dict):
            continue
        q, a = e["question"], e["answer"]
        row = {"question": q.get("id"), "kind": q.get("kind"), "title": q.get("title"), "step": e.get("step"),
               "decision": a.get("decision"), "choice": a.get("choice"), "comment": a.get("comment"), "at": a.get("at")}
        (own if e["by"] == "client" else pm).append(row)
    return own, pm


def role_memory(p, role, place):
    """What the role sees as podklady/historie.json at `place`: the expert its own place; the client every place it rated
    (this one first), its studio answers and, apart, the PM's decisions."""
    here = place_memory(p, role, place) or {"place": place, "findings": [], "ratings": []}
    if role != "owner":
        return here
    here["other_places"] = {pl: m for pl in PLACES if pl != place for m in [place_memory(p, role, pl)] if m}
    here["my_studio_answers"], here["pm_decisions"] = studio_answers(p)
    return here
