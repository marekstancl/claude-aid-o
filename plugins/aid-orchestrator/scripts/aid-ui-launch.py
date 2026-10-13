#!/usr/bin/env python3
"""aid-ui-launch.py - what the web needs before it can go live, asked once right after the brief (P113a step 7).

  card <project> [--type web-local]
      .aid-ui/launch.json from the type's launch_inputs (skills/ui-design/critic/<type>.yaml): every item with its
      status - found (a public lookup recorded with source and date), needed (public, not looked up yet) or client
      (only the client can supply it). Keeps what was recorded before. Prints the items.
  record <project> <item> --value <text> --source <url or file> --date <YYYY-MM-DD>
      A public fact the agent looked up (register, old web, profile): kept with its source and date. Not yet a fact
      of the web: it reaches docs/content/facts.yaml only after the client confirmed it (confirm).
  question <project>
      The studio question (kind launch_inputs, part podklady) to put in payload.json: what was found with its
      source, what the client supplies, which items block publishing. target = launch@<sha256 of the items>, so an
      answer to an older list does not count.
  confirm <project> --answer <question id>
      The client's answer (recorded in brand-state.json answers, kind launch_inputs, this list's target).
      approve: found items become confirmed and go into docs/content/facts.yaml as launch_<id> {value, source, read_at,
      confirmed_by: klient, confirmed_at, answer},
      and every item still missing becomes an open item with its owner, a due date (14 days) and its brief;
      critical ones block publishing (aid-ui-state.sh open-item --critical) but not the quality loop.
      return: nothing changes; the comment says what to fix. An answer is used once.
  A fact nobody confirmed is never published: it stays an open item, the gate's facts_match keeps the web to
  facts.yaml.
"""
import datetime, hashlib, json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")


def die(msg, code=1):
    print("ERROR: aid-ui-launch.py: " + msg, file=sys.stderr)
    sys.exit(code)


def lpath(p):
    return os.path.join(p, ".aid-ui", "launch.json")


def load(p):
    try:
        return json.load(open(lpath(p), encoding="utf-8"))
    except (OSError, ValueError):
        return None


def save(p, d):
    os.makedirs(os.path.dirname(lpath(p)), exist_ok=True)
    tmp = lpath(p) + ".part"
    json.dump(d, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.replace(tmp, lpath(p))


def target(d):
    return "launch@" + hashlib.sha256(json.dumps(d["items"], sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def card(p, typ):
    import yaml
    rp = os.path.join(SKILL, "critic", typ + ".yaml")
    if not os.path.isfile(rp):
        die("no type " + typ, 2)
    spec = yaml.safe_load(open(rp, encoding="utf-8")).get("launch_inputs") or []
    old = {i["id"]: i for i in (load(p) or {}).get("items", [])}
    items = []
    for s in spec:
        o = old.get(s["id"], {})
        it = {**s, "status": o.get("status") or ("needed" if s.get("public") else "client")}
        for k in ("value", "source", "date", "item"):
            if k in o:
                it[k] = o[k]
        items.append(it)
    d = {"type": typ, "items": items, "used_answers": (load(p) or {}).get("used_answers", [])}
    save(p, d)
    for i in items:
        print("%-8s %-9s %s%s" % (i["id"], i["status"], i["name"], " · blokuje zveřejnění" if i.get("critical") else ""))


def need(p):
    d = load(p)
    if not d:
        die("no .aid-ui/launch.json; run card first")
    return d


def record(p, iid, value, source, date):
    d = need(p)
    it = next((i for i in d["items"] if i["id"] == iid), None)
    if not it:
        die("no item " + iid)
    if not it.get("public"):
        die("%s is supplied by the client, not looked up" % iid)
    if not (value or "").strip() or not (source or "").strip():
        die("record needs --value and --source", 2)
    try:
        datetime.date.fromisoformat(date or "")
    except ValueError:
        die("--date is YYYY-MM-DD (when the source was read)", 2)
    it.update(status="found", value=value.strip(), source=source.strip(), date=date)
    save(p, d)
    print("%s found: %s (%s, %s)" % (iid, value.strip(), source.strip(), date))


def question(p):
    d = need(p)
    found = [i for i in d["items"] if i["status"] == "found"]
    rest = [i for i in d["items"] if i["status"] in ("needed", "client")]
    lines = ["Dohledali jsme (potvrďte, že platí):"] + ["- %s: %s (zdroj %s, %s)" % (i["name"], i["value"], i["source"], i["date"]) for i in found] \
        + ["", "Dodáte vy (nebo vám s tím pomůžeme):"] + ["- %s%s%s" % (i["name"], " - " + i["brief"] if i.get("brief") else "",
                                                                       " (bez toho web nezveřejníme)" if i.get("critical") else "") for i in rest]
    q = {"id": "launch-inputs", "kind": "launch_inputs", "part": "podklady", "target": target(d),
         "title": "Co potřebujeme ke spuštění webu", "body": "\n".join(lines),
         "prompt": "Platí dohledané údaje a souhlasíte s tím, co dodáte vy? Schválením vzniknou otevřené body s termínem."}
    print(json.dumps(q, ensure_ascii=False, indent=1))


def confirm(p, qid):
    d = need(p)
    try:
        st = json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        die("no docs/design/brand-state.json")
    a = (st.get("answers") or {}).get(qid)
    if not a:
        die("no recorded answer %s (aid-ui-state.sh record-answer --question %s)" % (qid, qid))
    if a.get("kind") != "launch_inputs" or a.get("target") != target(d):
        die("answer %s is not for this list (kind %s, target %s)" % (qid, a.get("kind"), str(a.get("target"))[:20]))
    if qid in d["used_answers"]:
        die("answer %s is already used" % qid)
    d["used_answers"].append(qid)
    if a.get("decision") != "approve":
        save(p, d)
        print("returned: %s" % (a.get("comment") or ""))
        return
    due = (datetime.date.today() + datetime.timedelta(days=14)).isoformat()
    facts = os.path.join(p, "docs", "content", "facts.yaml")
    for i in d["items"]:
        if i["status"] == "found":
            # into the facts register: the public source and the day it was read stay; the client's confirmation
            # is its own field (never a replacement of the source)
            entry = {"value": i["value"], "source": i["source"], "read_at": i["date"], "confirmed_by": "klient",
                     "confirmed_at": datetime.date.today().isoformat(), "answer": qid}
            os.makedirs(os.path.dirname(facts), exist_ok=True)
            if not os.path.exists(facts):
                open(facts, "w").write("{}\n")
            r = subprocess.run(["yq", "-i", '.[strenv(AID_KEY)] = env(AID_VAL)', facts], capture_output=True, text=True,   # values via the environment
                               env={**os.environ, "AID_KEY": "launch_" + i["id"], "AID_VAL": json.dumps(entry, ensure_ascii=False)})
            if r.returncode:
                die("cannot write %s to docs/content/facts.yaml (a mapping register): %s" % (i["id"], r.stderr.strip()))
            i["status"] = "confirmed"
            continue
        if i["status"] in ("needed", "client") and not i.get("item"):
            cmd = ["bash", os.path.join(HERE, "aid-ui-state.sh"), "open-item", p, "add", "--text", i["name"] + (": " + i["brief"] if i.get("brief") else ""),
                   "--owner", i.get("owner") or "klient", "--due", due]
            if i.get("critical"):
                cmd += ["--critical", "--evidence", "dodáno: " + i["name"]]
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode:
                die("open-item for %s failed: %s" % (i["id"], (r.stderr or r.stdout).strip()))
            i["item"] = r.stdout.strip().split()[-1]
    save(p, d)
    for i in d["items"]:
        print("%-8s %-9s %s" % (i["id"], i["status"], i.get("item") or ""))


def main(a):
    opt = lambda k, dflt=None: a[a.index(k) + 1] if k in a and a.index(k) + 1 < len(a) else dflt
    if len(a) >= 2 and a[0] == "card":
        return card(os.path.abspath(a[1]), opt("--type", "web-local"))
    if len(a) >= 3 and a[0] == "record":
        return record(os.path.abspath(a[1]), a[2], opt("--value"), opt("--source"), opt("--date"))
    if len(a) == 2 and a[0] == "question":
        return question(os.path.abspath(a[1]))
    if len(a) >= 2 and a[0] == "confirm" and opt("--answer"):
        return confirm(os.path.abspath(a[1]), opt("--answer"))
    die("usage: card <p> [--type t] | record <p> <item> --value v --source s --date d | question <p> | confirm <p> --answer <qid>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
