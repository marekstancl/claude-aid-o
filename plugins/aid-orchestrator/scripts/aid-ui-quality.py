#!/usr/bin/env python3
"""aid-ui-quality.py - the quality loop of /aid-ui (P113a step 3, 12. 10. 2026; two roles 13. 10. 2026).

The loop: the OWNER and the TECHNICIAN rate the web at once (aid-ui-client.py critic --role, each with the memory
of its own findings) -> the agent triages every finding -> fixes what it accepted -> rebuild, gate (and the copy
review when texts changed) -> the next round. A round is accepted when both roles reach 8.5 with no criterion under
7 (aid-ui-critic.py holds the threshold, the critics never see it); then the repairs stop and the accepted web is
audited. At most three repair rounds. Everything lives in <project>/.aid-ui/critic/: rounds/<n>/round.json,
rounds/<n>/{owner,tech}/ (the ratings), rounds/<n>/history-<role>.json (the memory each got), audits/<site sha>/a1..a3/
{owner,tech}/, loop.json (the summary the studio shows, with every round's cost and time), verdict.json.

  round <project> --web <url>
      One round on the current site. Refused while the previous round has a finding without a state, an accepted
      finding without --evidence, or the site fails `aid-ui-state.sh gate-check` (also for round 1), or when status
      says stop/audit. Books the agent's own work since the last round first (aid_ui_costs.book_agent: the Claude
      Code transcript of CLAUDE_CODE_SESSION_ID and its subagents). Findings get ids r<n>-<role>-<id>; findings a
      role gave the owner (client) start as blocked "client supplies it" (readiness, not the agent's).
  triage <project> <finding> <state> [--reason <t>] [--expected <t>] [--of <id>] [--conflict-with <id>]
      accepted (--expected: what it should raise), rejected_with_reason (--reason), duplicate (--of, also across the
      roles), blocked (--reason; with --conflict-with <id> the loop stops for the PM: fixing one makes the other
      worse - the gate always wins), superseded (--reason).
  fixed <project> <finding> --evidence <t> --method <t>
      An accepted finding is fixed; the evidence names what changed and where (the role sees it next round), the
      method which procedure made it (a step, an adopted skill) or "z hlavy: <why none>" - the round report to the PM.
  status <project>
      {decision, why, rounds, repair_rounds, scores, best} with decision one of
      triage | fix | round | close | audit | stop:conflict | stop:stagnation | stop:round_cap | done.
      Round 1 is the first rating, rounds 2-4 the repair rounds (ROUND_CAP 3); an audit is no round. The best round:
      the higher lower-role score, then the lowest criterion, then the mean (best_key). Accepted, or the rounds
      spent with an accepted web -> `close` first asks to set accepted findings not fixed yet to superseded, then
      the audit. A web whose audit failed is never the target again. Spent without acceptance -> stop:round_cap.
  reopen <project> --reason <why>
      A done loop opened again on purpose: the verdict goes to verdicts/, the reason to loop-reopened.json; the next
      round rates the changed web; the counts and the memory start again from the reopen.
  audit <project> --web <url>
      The closing check: the site must be the best accepted round's web; three blind ratings per role, both roles at
      once and without memory (aid-ui-client.py critic --audit), aid-ui-critic.py verdict per role -> verdict.json
      {accepted = both roles accepted, roles}. A failed rating decides nothing (exit 1). Not accepted: the auditors'
      findings become an audit round to triage (not counted as a repair round). Exit 0 accepted, 3 not, 1 refused.
"""
import hashlib, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT, CRITIC = (os.path.join(HERE, x) for x in ("aid-ui-client.py", "aid-ui-critic.py"))
STATE = os.environ.get("AID_UI_STATE_SH") or os.path.join(HERE, "aid-ui-state.sh")
ROUND_CAP = 3   # PM 13. 10. 2026: at most three repair rounds, or both roles at 8.5
ROLES = ("owner", "tech")
PLACE = "web"   # P113: the decision place this run works on (--place); the P113a loop is the place `web`
PLACES = ("sdeleni", "logo", "pohyb", "struktura", "vzhled", "web")
sys.path.insert(0, os.path.join(HERE, "lib"))
import aid_ui_costs as costs   # noqa: E402
import aid_ui_memory as memory   # noqa: E402
LABEL_URL = {"web": "finished web", "struktura": "structure"}
STATES = ("accepted", "rejected_with_reason", "duplicate", "blocked", "superseded")



def criteria_to_ten(a):
    """{criterion: to_ten} of one answer; a place with directions (logo, vzhled) carries its criteria per direction -
    then keyed <direction>:<criterion> when there is more than one (P113, Coufal: the logo round crashed on it)."""
    dirs = a.get("directions") or []
    crits = a.get("criteria") or [dict(c, id=c["id"] if len(dirs) == 1 else "%s:%s" % (d.get("id"), c["id"]))
                                  for d in dirs for c in d.get("criteria") or []]
    return {c["id"]: c["to_ten"] for c in crits if c.get("to_ten") and (c["to_ten"].get("studio") or c["to_ten"].get("client"))}

def die(msg, code=1):
    print("ERROR: aid-ui-quality.py: " + msg, file=sys.stderr)
    sys.exit(code)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def cdir(p):
    return os.path.join(p, ".aid-ui", "critic")


def wj(path, obj):
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def rdir(p):
    """Rounds of the current place: .aid-ui/critic/rounds/<n> for `web` (the P113a loop), rounds/<place>/<n> for the rest."""
    return os.path.join(cdir(p), "rounds", *([] if PLACE == "web" else [PLACE]))


def rounds(p):
    d = rdir(p)
    ns = sorted(int(x) for x in os.listdir(d) if x.isdigit()) if os.path.isdir(d) else []
    return [json.load(open(os.path.join(d, str(n), "round.json"), encoding="utf-8")) for n in ns
            if os.path.isfile(os.path.join(d, str(n), "round.json"))]


def save_round(p, r):
    os.makedirs(os.path.join(rdir(p), str(r["n"])), exist_ok=True)
    wj(os.path.join(rdir(p), str(r["n"]), "round.json"), r)


def site_sha(p):
    if PLACE != "web":   # a place's bundle (aid-ui-critic.py bundle-sha), the web keeps the site's sha of P113a
        r = subprocess.run([sys.executable, CRITIC, "bundle-sha", p, "--place", PLACE], capture_output=True, text=True)
        if r.returncode:
            die((r.stderr or r.stdout).strip())
        return r.stdout.strip()
    sys.path.insert(0, HERE)
    import importlib.util
    spec = importlib.util.spec_from_file_location("aid_ui_client", CLIENT)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.site_sha(os.path.join(p, "site"))


def verdict(p):
    if PLACE != "web":   # a place is decided by its place verdict (aid-ui-state.sh place-record), not by an audit
        try:
            v = (json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8")).get("place_verdicts") or {}).get(PLACE)
        except (OSError, ValueError):
            v = None
        return {"site_sha": v["target"], "accepted": v["status"] != "returned", "verdict": v["status"]} if v and v.get("target") else None
    vf = os.path.join(cdir(p), "verdict.json")
    return json.load(open(vf, encoding="utf-8")) if os.path.isfile(vf) else None


def reopen_file(p):
    return os.path.join(cdir(p), "loop-reopened.json") if PLACE == "web" else os.path.join(rdir(p), "reopened.json")


def reopened_at(p):
    try:
        return json.load(open(reopen_file(p), encoding="utf-8"))[-1]["at"]
    except (OSError, ValueError, IndexError, KeyError):
        return ""


def target_of(rs, since=""):
    """The web the audit rates: the best accepted repair round (the latest of equal scores); after a reopen, only
    rounds rated since then count (the reopened web is a new web)."""
    failed = {r["site_sha"] for r in rs if r.get("audit")}   # a web an audit did not confirm is no target again
    accs = [r for r in rs if not r.get("audit") and r["score"]["accepted"] and r["at"] >= since and r["site_sha"] not in failed]
    return max(accs, key=best_key) if accs else None


def best_key(r):
    """The better web: the higher of the two roles' lower score, then the lowest criterion, then their mean, then the later."""
    s = r["score"]
    return (s["quality_score"], s["min_criterion"], (s.get("owner", 0) + s.get("tech", 0)) / 2, r["n"])


def status(p):
    rs = rounds(p)
    since = reopened_at(p)
    # an audit's findings are triaged like a round but never count as one; after a reopen the changed web starts its
    # own count (stagnation and the round cap), the earlier rounds stay in the history
    reps = [r for r in rs if not r.get("audit") and r["at"] >= since]
    out = {"rounds": len(rs), "repair_rounds": max(len(reps) - 1, 0), "scores": [r["score"]["quality_score"] for r in rs]}
    target, v = target_of(rs, since), verdict(p)
    if target:
        out["best"] = {"round": target["n"], "quality_score": target["score"]["quality_score"], "owner": target["score"].get("owner"),
                       "tech": target["score"].get("tech"), "site_sha": target["site_sha"]}
    if v and target and v.get("site_sha") == target["site_sha"] and v.get("accepted"):
        return dict(out, decision="done", why=v["verdict"])
    if not rs:
        return dict(out, decision="round", why="no round yet")
    last = rs[-1]
    if since and last["at"] < since:
        return dict(out, decision="round", why="reopened %s: rate the changed web" % since)
    conflict = [f for f in last["findings"] if f.get("state") == "blocked" and f.get("conflict_with")]
    if conflict:
        f = conflict[0]
        return dict(out, decision="stop:conflict", why="fixing %s (%s) makes %s worse: %s" % (f["id"], f["text"], f["conflict_with"], f.get("reason", "")))
    open_ = [f["id"] for f in last["findings"] if not f.get("state")]
    if open_:
        return dict(out, decision="triage", why="findings without a state: " + ", ".join(open_))
    todo = [f["id"] for f in last["findings"] if f.get("state") == "accepted" and not f.get("evidence")]
    accepted_any = any(f.get("state") == "accepted" for f in last["findings"])
    cap = out["repair_rounds"] >= ROUND_CAP
    audited = bool(v and target and v.get("site_sha") == target["site_sha"])   # an audit that did not confirm it: repair on
    if target and not audited and (last["score"]["accepted"] or cap):
        if todo:   # the goal is reached (or the rounds are spent): what was accepted is closed explicitly, never skipped
            return dict(out, decision="close", why="%s (best: round %d, owner %.1f, tech %.1f); set %s superseded with the reason, then audit"
                        % ("both roles reached the goal" if last["score"]["accepted"] else "%d repair rounds done" % ROUND_CAP,
                           target["n"], target["score"]["owner"], target["score"]["tech"], ", ".join(todo)))
        if PLACE != "web":
            return dict(out, decision="verdict", why="place %s: decide it from round %d - aid-ui-critic.py place-verdict, then aid-ui-state.sh place-record"
                        % (PLACE, rs[-1]["n"]))
        return dict(out, decision="audit", why="audit the best accepted web: round %d (owner %.1f, tech %.1f); the site must be exactly that web - restore it if a later round changed it"
                    % (target["n"], target["score"]["owner"], target["score"]["tech"]))
    if cap:
        best = max([r for r in reps if not r.get("audit")], key=best_key)
        return dict(out, decision="stop:round_cap", why="%d repair rounds done without acceptance; best round %d: owner %.1f, tech %.1f, lowest criterion %s"
                    % (ROUND_CAP, best["n"], best["score"]["owner"], best["score"]["tech"], best["score"]["min_criterion"]))
    if todo:
        return dict(out, decision="fix", why="accepted findings not fixed yet: " + ", ".join(todo))
    if not accepted_any:
        return dict(out, decision="stop:stagnation", why=("the audit did not confirm the web and " if last.get("audit") else "below acceptance and ")
                    + "no finding was accepted for a fix")
    return dict(out, decision="round", why="fixes recorded; rate again")


def round_costs(p, rs):
    """Per round: list-price USD of everything booked from its start to the next round's start (critics, copy review,
    the agent's own work, images) and the wall time of that interval in minutes."""
    book = costs.rows(p)
    out = []
    for i, r in enumerate(rs):
        a, end = costs.ts(r["at"]), (costs.ts(rs[i + 1]["at"]) if i + 1 < len(rs) else time.time())
        # the agent's row is booked when the next round starts and covers the work after this one (the fixes)
        rows = [x for x in book if (a < costs.ts(x.get("until")) <= end + 1 if x.get("provider") == "agent" else a <= costs.ts(x.get("at")) < end)]
        by = {}
        for x in rows:
            k = "agent" if x.get("provider") == "agent" else (x.get("purpose") or "?").split(":")[0]
            by[k] = round(by.get(k, 0) + (x.get("usd") or 0), 4)
        out.append({"usd": round(sum(by.values()), 2), "by": by, "minutes": round((end - a) / 60),
                    "agent_measured": any(x.get("provider") == "agent" for x in rows)})
    return out


def write_loop(p):
    st = status(p)
    rs = rounds(p)
    cost = round_costs(p, rs)
    st["history"] = [{"n": r["n"], "at": r["at"], "audit": bool(r.get("audit")), "quality_score": r["score"]["quality_score"],
                      "owner": r["score"].get("owner"), "tech": r["score"].get("tech"), "owner_now": r["score"].get("owner_now"),
                      "tech_now": r["score"].get("tech_now"), "min_criterion": r["score"]["min_criterion"],
                      "accepted": r["score"]["accepted"], "provider": r.get("provider"), "cost": c,
                      "findings": [{k: f.get(k) for k in ("id", "role", "criterion", "severity", "owner", "text", "state", "reason", "expected", "evidence", "method")}
                                   for f in r["findings"]]} for r, c in zip(rs, cost)]
    st["cost_total_usd"] = round(sum(c["usd"] for c in cost), 2)
    first = costs.ts(rs[0]["at"]) if rs else None   # the build before the loop: not a round's cost, said apart
    st["cost_before_loop_usd"] = round(sum(x.get("usd") or 0 for x in costs.rows(p) if first is not None and
                                           costs.ts(x.get("until") if x.get("provider") == "agent" else x.get("at")) <= first), 2)
    st["at"] = now()
    wj(os.path.join(cdir(p), "loop.json"), st)
    return st


def gate_ok(p):
    r = subprocess.run(["bash", STATE, "gate-check", p], capture_output=True, text=True)
    return r.returncode == 0, (r.stderr or r.stdout).strip()


def task_row(p):
    """The gate's task_test row of the recorded gate (step 4): the task test of this build, as the round saw it."""
    try:
        st = json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8"))
        res = json.load(open(st["gate"]["result_file"], encoding="utf-8"))
        r = next((x for x in res.get("rows") or [] if x.get("check") == "task_test"), None)
        return {"status": r["status"], "detail": r.get("detail", "")} if r else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


def frozen_sha(p):
    try:
        return json.load(open(os.path.join(cdir(p), "frozen.json" if PLACE == "web" else os.path.join("frozen", PLACE + ".json")), encoding="utf-8"))["sha256"]
    except (OSError, ValueError, KeyError):
        die("no frozen critic of place %s (aid-ui-critic.py freeze --place %s first)" % (PLACE, PLACE))


def same_loop(p, web):
    """The whole loop runs on one frozen critic and one address; a round or an audit off either is refused."""
    rs = rounds(p)
    if not rs:
        return
    if frozen_sha(p) != rs[0]["frozen_sha"]:
        die("the frozen critic changed since round 1 (%s, the loop started with %s)" % (frozen_sha(p)[:12], rs[0]["frozen_sha"][:12]))
    if (web or "").rstrip("/") != (rs[0].get("web") or "").rstrip("/"):
        die("the loop rates %s; %s is another address" % (rs[0]["web"], web))


def usd_since(p, at):
    try:
        rows = [json.loads(x) for x in open(os.path.join(p, ".aid-ui", "costs.jsonl"), encoding="utf-8") if x.strip()]
    except OSError:
        return 0.0
    return round(sum(r.get("usd") or 0 for r in rows if r.get("at", "") >= at), 4)


def mark_client(f):
    if f["owner"] == "client":
        f.update(state="blocked", reason="client supplies it (readiness)")
    return f


def history(p, role):
    """The role's memory at this place (lib/aid_ui_memory.py, pamet-hodnotitele.md): its findings since the place's
    reopen and what the studio did with them, its previous scores and path to 10; the client also every other place
    it rated, its studio answers and the PM's decisions."""
    try:
        return memory.role_memory(p, role, PLACE)
    except ValueError as e:
        die(str(e))


def rate(p, web, d, audit=False, hist=None):
    """Both roles at once, each in its own directory; {role: (rc, out dir)}."""
    procs = {}
    for role in ROLES:
        out = os.path.join(d, role)
        cmd = [sys.executable, CLIENT, "critic", p, "--role", role, "--out", out, "--place", PLACE] + (["--web", web] if web else []) + (["--audit"] if audit else [])
        if hist is not None:
            hf = os.path.join(d, "history-%s.json" % role)
            os.makedirs(d, exist_ok=True)
            wj(hf, hist[role])
            cmd += ["--history", hf]
        procs[role] = (subprocess.Popen(cmd, text=True), out)
    return {role: (pr.wait(), out) for role, (pr, out) in procs.items()}


def bare(fid, ids):
    """The critic's own id without a round or role prefix it copied from its memory (Coufal 13. 10.:
    r2-owner-r2-owner-r2-01); kept as given when stripping would make two ids of one answer the same."""
    cut = lambda x: re.sub(r"^(?:(?:r\d+|a\d+|owner|tech)-)+", "", x) or x
    return cut(fid) if len({cut(x) for x in ids}) == len(set(ids)) else fid


def merge(runs):
    """The round's score from both roles: quality_score = the lower role score; accepted = both accepted. At a place
    with several directions: the best direction (the higher lower-role weighted score) and accepted when some
    direction passed every gate of both roles (the place verdict then decides by D5)."""
    sc = {role: runs[role]["score"] for role in ROLES}
    if PLACE != "web":
        dirs = sorted({x["direction"] for r in ROLES for x in sc[r].get("directions") or []})
        w = {(r, x["direction"]): x["weighted"] for r in ROLES for x in sc[r].get("directions") or [] if x["rubric"] == PLACE}
        ok = {d: all(x["status"] != "failed" for r in ROLES for x in sc[r]["directions"] if x["direction"] == d) for d in dirs}
        best = max(dirs, key=lambda d: (ok[d], min(w.get((r, d), 0) for r in ROLES))) if dirs else None
        crit = {"%s.%s" % (role, k): v for role in ROLES for k, v in sc[role]["criteria"].items()}
        return {"quality_score": min(w.get((r, best), 0) for r in ROLES) if best else 0, "owner": w.get(("owner", best), 0), "tech": w.get(("tech", best), 0),
                "owner_now": sc["owner"].get("quality_now"), "tech_now": sc["tech"].get("quality_now"), "best_direction": best,
                "directions": {d: {"accepted": ok[d], "owner": w.get(("owner", d)), "tech": w.get(("tech", d))} for d in dirs},
                "limited_by": sorted({i for r in ROLES for i in sc[r].get("limited_by") or []}), "criteria": crit,
                "min_criterion": min(crit.values()) if crit else 0, "accepted": any(ok.values()),
                "readiness": sorted({i for r in ROLES for i in sc[r]["readiness"]})}
    crit = {"%s.%s" % (role, k): v for role in ROLES for k, v in sc[role]["criteria"].items()}
    return {"quality_score": min(sc[r]["quality_score"] for r in ROLES), "owner": sc["owner"]["quality_score"], "tech": sc["tech"]["quality_score"],
            "owner_now": sc["owner"].get("quality_now"), "tech_now": sc["tech"].get("quality_now"),   # the web as it is, client items missing
            "limited_by": sorted({i for r in ROLES for i in sc[r].get("limited_by") or []}),
            "criteria": crit, "min_criterion": min(crit.values()) if crit else 0, "accepted": all(sc[r]["accepted"] for r in ROLES),
            "readiness": sorted({i for r in ROLES for i in sc[r]["readiness"]})}


def do_round(p, web):
    st = status(p)
    if st["decision"] != "round":
        die("no round now: %s (%s)" % (st["decision"], st["why"]))
    if PLACE in ("web", "struktura") and not web:
        die("--web <url>: the %s is rated live (%s)" % (LABEL_URL[PLACE], "the served site" if PLACE == "web" else "the skeleton address"), 2)
    same_loop(p, web)
    if PLACE == "web":   # the regression check guards the built site; earlier places have no build yet
        ok, msg = gate_ok(p)
        if not ok:
            die("the site does not pass the regression check (aid-ui-state.sh gate-check); rebuild, build-record and run the gate first:\n" + msg)
    n = st["rounds"] + 1
    d = os.path.join(rdir(p), str(n))
    os.makedirs(d, exist_ok=True)
    costs.book_agent(p, "agent:before-round-%d" % n)   # the agent's own work since the last round (fixes, rebuilds)
    at = now()
    res = rate(p, web, d, hist={role: history(p, role) for role in ROLES})
    bad = [role for role, (rc, _) in res.items() if rc]
    if bad:
        os.rename(d, d + "-failed-" + at.replace(":", ""))   # a failed rating is kept for the record but is no round
        die("no rating from %s (record in %s-failed-*/<role>/run.json)" % (", ".join(bad), d))
    runs = {role: json.load(open(os.path.join(out, "run.json"), encoding="utf-8")) for role, (_, out) in res.items()}
    if len({(x["site_sha"], x["frozen_sha"]) for x in runs.values()}) != 1:
        os.rename(d, d + "-failed-" + at.replace(":", ""))
        die("the roles rated different webs or critics (the site changed during the round?): " + ", ".join(
            "%s %s/%s" % (r, x["site_sha"][:12], x["frozen_sha"][:12]) for r, x in runs.items()))
    finds = []
    for role, (_, out) in res.items():
        ans = json.load(open(os.path.join(out, "answer.json"), encoding="utf-8"))
        finds += [mark_client(dict(f, id="r%d-%s-%s" % (n, role, bare(f["id"], [x["id"] for x in ans["findings"]])), role=role, state=None)) for f in ans["findings"]]
    score = merge(runs)
    shas = {role: hashlib.sha256(open(os.path.join(out, "answer.json"), "rb").read()).hexdigest() for role, (_, out) in res.items()}
    rec = {"n": n, "at": at, "place": PLACE, "answers": shas, "web": web, "site_sha": runs["owner"]["site_sha"], "frozen_sha": runs["owner"]["frozen_sha"],
           "provider": {r: runs[r].get("provider") for r in ROLES}, "score": score, "findings": finds, "readiness": score["readiness"],
           "task_test": task_row(p), "usd_equiv": usd_since(p, at)}
    save_round(p, rec)
    st = write_loop(p)
    top = {role: [f["text"] for f in finds if f["role"] == role and f["owner"] == "agent"][:3] for role in ROLES}   # the critics rank by impact
    to_ten = {}
    for role, (_, out) in res.items():
        a = json.load(open(os.path.join(out, "answer.json"), encoding="utf-8"))
        to_ten[role] = criteria_to_ten(a)
    prev = [r for r in rounds(p) if r["n"] < n]
    done = [{k: f.get(k) for k in ("id", "text", "evidence", "method")} for f in (prev[-1]["findings"] if prev else []) if f.get("evidence")]
    rec["to_ten"] = to_ten
    save_round(p, rec)
    print(json.dumps({"round": n, "place": PLACE, "best_direction": score.get("best_direction"), "owner": score["owner"], "tech": score["tech"], "owner_now": score["owner_now"], "tech_now": score["tech_now"],
                      "limited_by": score["limited_by"], "min_criterion": score["min_criterion"],
                      "findings": len(finds), "top3": top, "decision": st["decision"], "loop_usd": st["cost_total_usd"],
                      "loop_minutes": sum(h["cost"]["minutes"] for h in st["history"]),
                      "previous_round": st["history"][-2]["cost"] if len(st["history"]) > 1 else None,
                      "fixed_before": done, "to_ten": to_ten}, ensure_ascii=False))


def find(p, fid):
    rs = rounds(p)
    if not rs:
        die("no round yet")
    last = rs[-1]
    f = next((x for x in last["findings"] if x["id"] == fid), None)
    if not f:
        die("no finding %s in round %d (only the last round is triaged)" % (fid, last["n"]))
    return last, f


def triage(p, fid, state, opts):
    if state not in STATES:
        die("state must be one of " + ", ".join(STATES), 2)
    last, f = find(p, fid)
    need = {"accepted": "expected", "rejected_with_reason": "reason", "duplicate": "of", "blocked": "reason", "superseded": "reason"}[state]
    if not (opts.get(need) or "").strip():
        die("%s needs --%s" % (state, need), 2)
    ids = {x["id"] for x in last["findings"]}
    for k in ("of", "conflict-with"):
        if opts.get(k) and (opts[k] not in ids or opts[k] == fid):
            die("--%s %s: no other finding of round %d with that id" % (k, opts[k], last["n"]))
    if opts.get("conflict-with") and state != "blocked":
        die("--conflict-with goes with blocked only (the finding cannot be fixed without making the other worse)", 2)
    for k in ("reason", "expected", "of", "conflict_with", "evidence"):
        f.pop(k, None)
    f["state"] = state
    for k in ("reason", "expected", "of"):
        if opts.get(k):
            f[k] = opts[k].strip()
    if opts.get("conflict-with"):
        f["conflict_with"] = opts["conflict-with"]
    f["triaged_at"] = now()
    save_round(p, last)
    print("%s: %s -> %s" % (fid, state, write_loop(p)["decision"]))


def fixed(p, fid, evidence, method):
    last, f = find(p, fid)
    if f.get("state") != "accepted":
        die("%s is %s; only an accepted finding is fixed" % (fid, f.get("state")))
    if not (evidence or "").strip():
        die("fixed needs --evidence", 2)
    # PM 13. 10. 2026: every fix says which procedure made it, or that none did and why (the round report and the
    # gaps in the plugin's procedures come from this)
    m = (method or "").strip()
    why = m[len("z hlavy:"):].strip() if m.lower().startswith("z hlavy:") else None
    named = re.search(r"(steps/|adopted/|skills?/|references/|SKILL\.md|aid-ui-[a-z-]+)", m)
    if not ((why is not None and len(why) >= 10) or (why is None and named)):
        die('fixed needs --method "<step or skill, e.g. steps/6-build.md 3a | adopted/emil-skills/...>" or "z hlavy: <why there was no procedure>"', 2)
    f["evidence"], f["method"], f["fixed_at"] = evidence.strip(), m, now()
    save_round(p, last)
    print("%s fixed -> %s" % (fid, write_loop(p)["decision"]))


def audit(p, web):
    if PLACE != "web":
        die("the blind audit closes the finished web only; place %s is decided by aid-ui-critic.py place-verdict" % PLACE, 2)
    st = status(p)
    if st["decision"] != "audit":
        die("no audit now: %s (%s)" % (st["decision"], st["why"]))
    same_loop(p, web)
    rs = rounds(p)
    tgt = target_of(rs, reopened_at(p))
    cur = site_sha(p)
    if cur != tgt["site_sha"]:
        die("the site is not the best accepted web (round %d, %s; the site now %s): restore that web, rebuild, record and gate it, then audit"
            % (tgt["n"], tgt["site_sha"][:12], cur[:12]))
    ok, msg = gate_ok(p)
    if not ok:
        die("the site does not pass the regression check:\n" + msg)
    costs.book_agent(p, "agent:before-audit")
    d = os.path.join(cdir(p), "audits", tgt["site_sha"][:16] + "-" + now().replace(":", ""))
    files, answers = {r: [] for r in ROLES}, []
    for k in (1, 2, 3):   # three blind ratings per role, both roles at once; no memory
        for role, (rc, out) in rate(p, web, os.path.join(d, "a%d" % k), audit=True).items():
            if rc:
                die("audit rating %d (%s) failed (record in %s/run.json): the audit decides nothing" % (k, role, out))
            run = json.load(open(os.path.join(out, "run.json"), encoding="utf-8"))
            if run["site_sha"] != tgt["site_sha"] or run["frozen_sha"] != rs[0]["frozen_sha"]:
                die("audit rating %d (%s) rated another web or another critic (site %s, critic %s)" % (k, role, run["site_sha"][:12], run["frozen_sha"][:12]))
            files[role].append(os.path.join(out, "answer.json"))
            answers.append((k, role, json.load(open(files[role][-1], encoding="utf-8"))))
    vs = {}
    for role in ROLES:
        r = subprocess.run([sys.executable, CRITIC, "verdict", p, "--role", role] + files[role], capture_output=True, text=True)
        if r.returncode not in (0, 3):
            die("verdict (%s) failed: %s" % (role, (r.stderr or r.stdout).strip()))
        vs[role] = json.loads(r.stdout)
    ok = all(vs[r]["accepted"] for r in ROLES)
    try:   # a critical open item blocks publishing whatever the critics listed
        crit_items = [i["text"] for i in json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8")).get("open_items") or []
                      if i.get("status") == "open" and i.get("critical") is True]
    except (OSError, ValueError):
        crit_items = []
    ready = sorted({i for r in ROLES for i in vs[r]["publish_blocked_by"]} | set(crit_items))
    v = {"accepted": ok, "roles": vs, "median_quality_score": min(vs[r]["median_quality_score"] for r in ROLES),
         "publish_blocked_by": ready, "verdict": ("přijato" + (", zveřejnění blokuje: " + "; ".join(ready) if ready else ", připraveno ke zveřejnění")) if ok else "nepřijato",
         "site_sha": tgt["site_sha"], "round": tgt["n"], "at": now(), "ratings_dir": d}
    wj(os.path.join(cdir(p), "verdict.json"), v)
    if not ok:   # the auditors' findings become a round to triage; it is no repair round
        n = rs[-1]["n"] + 1
        crit = {"%s.%s" % (role, k): x for role in ROLES for k, x in vs[role]["criteria_median"].items()}
        finds = [mark_client(dict(f, id="r%d-a%d-%s-%s" % (n, k, role, bare(f["id"], [x["id"] for x in a["findings"]])), role=role, state=None)) for k, role, a in answers for f in a["findings"]]
        save_round(p, {"n": n, "at": v["at"], "web": web, "audit": True, "site_sha": tgt["site_sha"], "frozen_sha": rs[0]["frozen_sha"],
                       "score": {"quality_score": v["median_quality_score"], "owner": vs["owner"]["median_quality_score"], "tech": vs["tech"]["median_quality_score"],
                                 "criteria": crit, "min_criterion": min(crit.values()) if crit else 0, "accepted": False, "readiness": ready},
                       "findings": finds, "readiness": ready, "task_test": task_row(p), "usd_equiv": None})
    write_loop(p)
    print(json.dumps(v, ensure_ascii=False))
    sys.exit(0 if ok else 3)


def reopen(p, reason):
    """A done loop opened again on purpose (the PM wants more changes): the verdict is archived, the reason kept,
    the next round rates the changed web and only rounds from now on can be audited."""
    if not (reason or "").strip():
        die("reopen needs --reason", 2)
    if status(p)["decision"] not in ("done",) + (("stop:round_cap", "verdict") if PLACE != "web" else ()):
        die("only a done loop is reopened (now: %s)" % status(p)["decision"])
    at = now()
    if PLACE == "web":
        vf = os.path.join(cdir(p), "verdict.json")
        os.makedirs(os.path.join(cdir(p), "verdicts"), exist_ok=True)
        os.replace(vf, os.path.join(cdir(p), "verdicts", at.replace(":", "") + ".json"))
    os.makedirs(os.path.dirname(reopen_file(p)), exist_ok=True)
    lf = reopen_file(p)
    log = json.load(open(lf, encoding="utf-8")) if os.path.isfile(lf) else []
    log.append({"at": at, "reason": reason.strip()})
    wj(lf, log)
    print("reopened -> %s" % write_loop(p)["decision"])


def main(a):
    if len(a) < 2:
        die("usage: round|triage|fixed|status|audit <project> ... (see the header)", 2)
    global PLACE
    cmd, p = a[0], os.path.abspath(a[1])
    if "--place" in a:
        i = a.index("--place")
        PLACE = a[i + 1] if i + 1 < len(a) else ""
        a = a[:i] + a[i + 2:]
        if PLACE not in PLACES:
            die("--place must be one of " + ", ".join(PLACES), 2)
    opts, rest, i = {}, [], 2
    while i < len(a):
        if a[i].startswith("--") and i + 1 < len(a):
            opts[a[i][2:]] = a[i + 1]
            i += 2
        else:
            rest.append(a[i])
            i += 1
    if cmd == "status":
        print(json.dumps(write_loop(p) if rounds(p) else status(p), ensure_ascii=False))
    elif cmd == "round":
        do_round(p, opts.get("web"))
    elif cmd == "audit" and opts.get("web"):
        audit(p, opts["web"])
    elif cmd == "triage" and len(rest) == 2:
        triage(p, rest[0], rest[1], opts)
    elif cmd == "reopen":
        reopen(p, opts.get("reason"))
    elif cmd == "fixed" and len(rest) == 1:
        fixed(p, rest[0], opts.get("evidence"), opts.get("method"))
    else:
        die("usage: round <p> --web <url> | triage <p> <finding> <state> [--reason|--expected|--of|--conflict-with] | "
            "fixed <p> <finding> --evidence <t> --method <step|skill|z hlavy: why> | status <p> | audit <p> --web <url>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
