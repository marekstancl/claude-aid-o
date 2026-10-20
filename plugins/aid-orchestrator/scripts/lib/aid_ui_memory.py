"""aid_ui_memory - the evaluator's memory of the two roles (P113, pamet-hodnotitele.md).

Derived every time from what exists, never stored twice: a role's rounds at a place (its findings, what the studio
did with them, its scores and path to 10 per round, since the place's last reopen) and, for the client, its answers in
the studio (.aid-ui/studio/history.jsonl, by: client) beside the PM's decisions (by: pm, shown as the PM's). The
expert remembers one place; the client every place. The blind audit reads none of it.
"""
import json, os, re

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


# ---------------------------------------------------------------- what the client supplies (P116, PM 19. 10. 2026)
# A role's finding with owner "client" and its readiness items ("the client must supply") go to the client role, which
# answers from the project's files (aid-ui-client.py supply): a fact with its source and the quoted text, an owner's
# choice of an allowed kind with its reason, or "missing" (left for the PM). Records per place in
# .aid-ui/client/supplied/<place>.json (in the place's bundle, so the roles see them and the bundle sha moves).
SUPPLY_KINDS = ("naming", "default", "priority", "choice")   # what the owner may decide without a fact in the files


def supply_file(p, place):
    return os.path.join(p, ".aid-ui", "client", "supplied", place + ".json")


def supply_items(p, place):
    """The client's items of the last round of the build loop at the place (an audit round too; never the launch
    loop): its findings with owner client and the round's readiness. Each item's key hashes the place, the round,
    the kind, the finding id and the text, so a new round or a changed text asks again."""
    import hashlib
    d = os.path.join(p, ".aid-ui", "critic", "rounds", *([] if place == "web" else [place]))
    ns = sorted(int(x) for x in os.listdir(d) if x.isdigit() and os.path.isfile(os.path.join(d, x, "round.json"))) if os.path.isdir(d) else []
    if not ns:
        return []
    r = json.load(open(os.path.join(d, str(ns[-1]), "round.json"), encoding="utf-8"))
    items = [{"kind": "finding", "id": f["id"], "role": f.get("role"), "text": f["text"]} for f in r.get("findings") or [] if f.get("owner") == "client"]
    items += [{"kind": "readiness", "id": None, "role": None, "text": t} for t in r.get("readiness") or []]
    for it in items:
        it["round"] = r["n"]
        it["key"] = hashlib.sha256(json.dumps([place, r["n"], it["kind"], it["id"], it["text"]], ensure_ascii=False).encode()).hexdigest()
    return items


STUDIO_OUT = (".aid-ui/", "docs/design/", "docs/ui/", "site/")   # what the studio writes is never the client's source
CLIENT_IN = (".aid-ui/sources/", ".aid-ui/old-site/")


def source_ok(project, src, quote):
    """None when <file>:<line>[-<line>] is a regular file of the project (no symlink on its path, not the studio's own
    output) and the quote stands on those lines (whitespace folded); else why not."""
    m = re.fullmatch(r"(\S+?):([1-9][0-9]*)(?:-([1-9][0-9]*))?", src or "")
    if not m:
        return "source %r is not <file>:<line> or <file>:<from>-<to>" % src
    rel, a = m.group(1), int(m.group(2))
    b = int(m.group(3) or a)
    if os.path.isabs(rel) or os.path.normpath(rel) != rel or rel.startswith(".." + os.sep) or b < a or b - a > 40:   # ./site, a//b: not normal
        return "source %s: a relative path in the project and at most 40 lines" % src
    if rel.startswith(STUDIO_OUT) and not rel.startswith(CLIENT_IN):
        return "source %s is what the studio wrote, not a fact of the client's files" % src
    root = os.path.realpath(project)
    f = os.path.join(root, rel)
    if os.path.realpath(f) != os.path.normpath(f) or not os.path.isfile(f):
        return "source %s is no regular file of the project" % src
    try:
        lines = open(f, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError):
        return "source %s is not a text file" % src
    if b > len(lines):
        return "source %s: the file has %d lines" % (src, len(lines))
    q = " ".join(str(quote or "").split())
    if len(q) < 8:
        return "source %s needs the quoted text (at least 8 characters) in quote" % src
    if q not in " ".join(" ".join(lines[a - 1:b]).split()):
        return "the quote is not on %s" % src
    return None


def supply_records(p, place):
    """{key: record} of the place that still hold: written by a client run (its turn's answer has the same status,
    answer, source and quote for the key) and, for a fact, the quote still on the cited lines. A file or record that
    is broken, typed in or out of date is no record: the loop asks the client again."""
    try:
        d = json.load(open(supply_file(p, place), encoding="utf-8"))
        items = d.get("items") or {}
    except (OSError, ValueError, AttributeError):
        return {}
    out, turns = {}, {}
    for k, v in items.items() if isinstance(items, dict) else []:
        t = str((v or {}).get("turn") or "") if isinstance(v, dict) else ""
        if not re.fullmatch(r"\.aid-ui/client/turns/supply-[a-z]+-r[0-9]+-[0-9]+", t) or v.get("status") not in ("supplied", "decided", "missing"):
            continue
        if t not in turns:
            try:
                turns[t] = {x.get("key"): x for x in (json.load(open(os.path.join(p, t, "turn.json"), encoding="utf-8")).get("answer") or {}).get("items") or [] if isinstance(x, dict)}
            except (OSError, ValueError, AttributeError):
                turns[t] = {}
        x = turns[t].get(k)
        if not x or any(str(x.get(f) or "").strip() != str(v.get(f) or "") for f in ("status", "answer", "source", "quote", "decided_kind", "reason", "missing")):
            continue
        if v["status"] == "supplied" and source_ok(p, v.get("source"), v.get("quote")):
            continue
        out[k] = v
    return out


def unsupplied(p, place):
    rec = supply_records(p, place)
    return [i for i in supply_items(p, place) if i["key"] not in rec]


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


# ---------------------------------------------------------------- verify records (P118)
# What the independent verifier saw over one version (artifact = the place's bundle sha, the web's site sha) is kept
# outside the project, signed with a key outside it (HMAC): the producer hands in inputs, never the result. It stops
# a slip, not an attack by someone who can read the key.

def verify_home(p):
    import hashlib
    base = os.path.expanduser(os.environ.get("AID_UI_VERIFY_HOME") or "~/.local/state/aid-ui/verify")
    return os.path.join(base, hashlib.sha256(os.path.realpath(p).encode()).hexdigest()[:16])


def _verify_key():
    import secrets
    f = os.path.expanduser(os.environ.get("AID_UI_VERIFY_KEY") or "~/.config/aid-ui/verify.key")
    if not os.path.isfile(f):
        os.makedirs(os.path.dirname(f), mode=0o700, exist_ok=True)
        fd = os.open(f, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(fd, secrets.token_bytes(32)); os.close(fd)
    return open(f, "rb").read()


def _verify_sig(rec):
    import hashlib, hmac
    body = json.dumps({k: v for k, v in rec.items() if k != "sig"}, sort_keys=True, ensure_ascii=False).encode()
    return hmac.new(_verify_key(), body, hashlib.sha256).hexdigest()


def verify_append(p, place, rec):
    d = verify_home(p)
    os.makedirs(d, mode=0o700, exist_ok=True)
    rec = dict(rec, place=place)
    rec["sig"] = _verify_sig(rec)
    with open(os.path.join(d, place + ".jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return rec


def verify_records(p, place, artifact):
    """Every signed record of the place over this artifact, oldest first; an unsigned or altered line is no record."""
    import hmac
    out = []
    try:
        lines = open(os.path.join(verify_home(p), place + ".jsonl"), encoding="utf-8").read().splitlines()
    except OSError:
        return out
    for line in lines:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict) and r.get("artifact") == artifact and r.get("place") == place and hmac.compare_digest(str(r.get("sig") or ""), _verify_sig(r)):
            out.append(r)
    return out
