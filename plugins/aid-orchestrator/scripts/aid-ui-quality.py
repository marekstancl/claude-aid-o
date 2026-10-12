#!/usr/bin/env python3
"""aid-ui-quality.py - the quality loop of /aid-ui (P113a step 3, 12. 10. 2026).

The loop: the critic rates the web -> the agent triages every finding -> fixes what it accepted -> rebuild, gate
(and the copy review when texts changed) -> the next round. Goal 10/10; smallest acceptable 8/10 (aid-ui-critic.py
holds the threshold, the critic never sees it). Everything lives in <project>/.aid-ui/critic/:
rounds/<n>/round.json, rounds/<n>/critic/ (the rating), audits/<site sha>/a1..a3/, loop.json (the summary the
studio shows), verdict.json (the closing audit).

  round <project> --web <url>
      One critic round on the current site. Refused while the previous round has a finding without a state, an
      accepted finding without --evidence, or the site fails `aid-ui-state.sh gate-check` (the regression check
      after fixes; also for round 1), or when status says stop/audit. Findings get ids r<n>-<id>; findings the
      critic gave the owner (client) start as blocked "client supplies it" (readiness, not the agent's).
  triage <project> <finding> <state> [--reason <t>] [--expected <t>] [--of <id>] [--conflict-with <id>]
      accepted (--expected: what it should raise), rejected_with_reason (--reason), duplicate (--of),
      blocked (--reason; with --conflict-with <id> the loop stops for the PM: fixing one makes the other worse),
      superseded (--reason).
  fixed <project> <finding> --evidence <t>
      An accepted finding is fixed; the evidence names what changed and where (checked again by the next round).
  status <project>
      {decision, why, rounds, repair_rounds, scores, best} with decision one of
      triage | fix | round | audit | stop:conflict | stop:stagnation | stop:round_cap | done.
      Rules: repair rounds at most ROUND_CAP (5); improvement = quality_score +0.3 or fewer blocking+major
      findings with no criterion lower; two repair rounds in a row without improvement = stop:stagnation (or
      audit when the last round is accepted); after acceptance the loop goes on toward 10 while it improves.
  audit <project> --web <url>
      The closing check (not a repair round): three blind ratings (aid-ui-client.py critic --audit) of the same
      site, aid-ui-critic.py verdict -> verdict.json. Exit 0 accepted, 3 not accepted, 1 refused/failed.
"""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT, CRITIC = (os.path.join(HERE, x) for x in ("aid-ui-client.py", "aid-ui-critic.py"))
STATE = os.environ.get("AID_UI_STATE_SH") or os.path.join(HERE, "aid-ui-state.sh")
ROUND_CAP, GAIN = 5, 0.3
STATES = ("accepted", "rejected_with_reason", "duplicate", "blocked", "superseded")


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


def rounds(p):
    d = os.path.join(cdir(p), "rounds")
    ns = sorted(int(x) for x in os.listdir(d) if x.isdigit()) if os.path.isdir(d) else []
    return [json.load(open(os.path.join(d, str(n), "round.json"), encoding="utf-8")) for n in ns
            if os.path.isfile(os.path.join(d, str(n), "round.json"))]


def save_round(p, r):
    wj(os.path.join(cdir(p), "rounds", str(r["n"]), "round.json"), r)


def heavy(r):
    return sum(1 for f in r["findings"] if f["severity"] in ("blocking", "major"))


def improved(prev, cur):
    if cur["score"]["quality_score"] >= prev["score"]["quality_score"] + GAIN - 1e-9:
        return True
    lower = any(cur["score"]["criteria"].get(k, 99) < v for k, v in prev["score"]["criteria"].items())
    return heavy(cur) < heavy(prev) and not lower


def status(p):
    rs = rounds(p)
    out = {"rounds": len(rs), "repair_rounds": max(len(rs) - 1, 0), "scores": [r["score"]["quality_score"] for r in rs]}
    if rs:
        best = max(rs, key=lambda r: r["score"]["quality_score"])
        out["best"] = {"round": best["n"], "quality_score": best["score"]["quality_score"], "site_sha": best["site_sha"]}
    vf = os.path.join(cdir(p), "verdict.json")
    v = json.load(open(vf, encoding="utf-8")) if os.path.isfile(vf) else None
    if v and rs and v.get("site_sha") == rs[-1]["site_sha"] and v.get("accepted"):
        return dict(out, decision="done", why=v["verdict"])
    if not rs:
        return dict(out, decision="round", why="no round yet")
    last = rs[-1]
    conflict = [f for f in last["findings"] if f.get("state") == "blocked" and f.get("conflict_with")]
    if conflict:
        f = conflict[0]
        return dict(out, decision="stop:conflict", why="fixing %s (%s) makes %s worse: %s" % (f["id"], f["text"], f["conflict_with"], f.get("reason", "")))
    open_ = [f["id"] for f in last["findings"] if not f.get("state")]
    if open_:
        return dict(out, decision="triage", why="findings without a state: " + ", ".join(open_))
    acc = last["score"]["accepted"]
    audited = v and v.get("site_sha") == last["site_sha"]   # an audit that did not confirm this web: repair on
    fixing = any(f.get("evidence") for f in last["findings"])
    # the audit rates exactly the web of the last round, so it comes before any fix of that round
    if acc and not audited and not fixing and (len(rs) >= 2 and not improved(rs[-2], last) or out["repair_rounds"] >= ROUND_CAP
                                               or not any(f.get("state") == "accepted" for f in last["findings"])):
        return dict(out, decision="audit", why="accepted at %.1f and no further gain in reach; rate this web blind three times, change nothing"
                    % last["score"]["quality_score"])
    todo = [f["id"] for f in last["findings"] if f.get("state") == "accepted" and not f.get("evidence")]
    if todo:
        return dict(out, decision="fix", why="accepted findings not fixed yet: " + ", ".join(todo))
    flat = len(rs) >= 3 and not improved(rs[-2], rs[-1]) and not improved(rs[-3], rs[-2])
    if flat:
        return dict(out, decision="stop:stagnation", why="two repair rounds without improvement (scores %s)" % out["scores"][-3:])
    if out["repair_rounds"] >= ROUND_CAP:
        return dict(out, decision="stop:round_cap", why="%d repair rounds done, last %.1f, lowest criterion %s"
                    % (ROUND_CAP, last["score"]["quality_score"], last["score"]["min_criterion"]))
    if not any(f.get("state") == "accepted" for f in last["findings"]):
        return dict(out, decision="stop:stagnation", why="below acceptance and no finding accepted for a fix")
    return dict(out, decision="round", why="fixes recorded; rate again")


def write_loop(p):
    st = status(p)
    rs = rounds(p)
    st["history"] = [{"n": r["n"], "at": r["at"], "quality_score": r["score"]["quality_score"], "min_criterion": r["score"]["min_criterion"],
                      "accepted": r["score"]["accepted"], "provider": r.get("provider"), "usd_equiv": r.get("usd_equiv"),
                      "findings": [{k: f.get(k) for k in ("id", "criterion", "severity", "owner", "text", "state", "reason", "expected", "evidence")}
                                   for f in r["findings"]]} for r in rs]
    st["at"] = now()
    wj(os.path.join(cdir(p), "loop.json"), st)
    return st


def gate_ok(p):
    r = subprocess.run(["bash", STATE, "gate-check", p], capture_output=True, text=True)
    return r.returncode == 0, (r.stderr or r.stdout).strip()


def usd_since(p, at):
    try:
        rows = [json.loads(x) for x in open(os.path.join(p, ".aid-ui", "costs.jsonl"), encoding="utf-8") if x.strip()]
    except OSError:
        return 0.0
    return round(sum(r.get("usd") or 0 for r in rows if r.get("at", "") >= at), 4)


def do_round(p, web):
    st = status(p)
    if st["decision"] not in ("round",):
        die("no round now: %s (%s)" % (st["decision"], st["why"]))
    ok, msg = gate_ok(p)
    if not ok:
        die("the site does not pass the regression check (aid-ui-state.sh gate-check); rebuild, build-record and run the gate first:\n" + msg)
    n = st["rounds"] + 1
    d = os.path.join(cdir(p), "rounds", str(n))
    os.makedirs(d, exist_ok=True)
    at = now()
    r = subprocess.run([sys.executable, CLIENT, "critic", p, "--web", web, "--out", os.path.join(d, "critic")], text=True)
    if r.returncode:
        os.rmdir(d) if not os.listdir(d) else None
        die("the critic gave no rating (record in %s/critic/run.json)" % d)
    run = json.load(open(os.path.join(d, "critic", "run.json"), encoding="utf-8"))
    ans = json.load(open(os.path.join(d, "critic", "answer.json"), encoding="utf-8"))
    finds = []
    for f in ans["findings"]:
        f = dict(f, id="r%d-%s" % (n, f["id"]), state=None)
        if f["owner"] == "client":
            f.update(state="blocked", reason="client supplies it (readiness)")
        finds.append(f)
    rec = {"n": n, "at": at, "web": web, "site_sha": run["site_sha"], "frozen_sha": run["frozen_sha"], "provider": run.get("provider"),
           "score": run["score"], "findings": finds, "readiness": run["score"]["readiness"], "usd_equiv": usd_since(p, at)}
    save_round(p, rec)
    st = write_loop(p)
    print(json.dumps({"round": n, "quality_score": rec["score"]["quality_score"], "min_criterion": rec["score"]["min_criterion"],
                      "findings": len(finds), "decision": st["decision"]}, ensure_ascii=False))


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
    if opts.get("conflict-with") and not any(x["id"] == opts["conflict-with"] for x in last["findings"]):
        die("no finding %s to conflict with" % opts["conflict-with"])
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


def fixed(p, fid, evidence):
    last, f = find(p, fid)
    if f.get("state") != "accepted":
        die("%s is %s; only an accepted finding is fixed" % (fid, f.get("state")))
    if not (evidence or "").strip():
        die("fixed needs --evidence", 2)
    f["evidence"], f["fixed_at"] = evidence.strip(), now()
    save_round(p, last)
    print("%s fixed -> %s" % (fid, write_loop(p)["decision"]))


def audit(p, web):
    st = status(p)
    if st["decision"] != "audit":
        die("no audit now: %s (%s)" % (st["decision"], st["why"]))
    ok, msg = gate_ok(p)
    if not ok:
        die("the site does not pass the regression check:\n" + msg)
    last = rounds(p)[-1]
    d = os.path.join(cdir(p), "audits", last["site_sha"][:16])
    files = []
    for k in (1, 2, 3):
        out = os.path.join(d, "a%d" % k)
        r = subprocess.run([sys.executable, CLIENT, "critic", p, "--web", web, "--audit", "--out", out], text=True)
        if r.returncode:
            die("audit rating %d failed (record in %s/run.json)" % (k, out))
        run = json.load(open(os.path.join(out, "run.json"), encoding="utf-8"))
        if run["site_sha"] != last["site_sha"]:
            die("the site changed during the audit (rating %d rated %s, the round %s)" % (k, run["site_sha"][:12], last["site_sha"][:12]))
        files.append(os.path.join(out, "answer.json"))
    r = subprocess.run([sys.executable, CRITIC, "verdict", p] + files, capture_output=True, text=True)
    if r.returncode not in (0, 3):
        die("verdict failed: " + (r.stderr or r.stdout).strip())
    v = dict(json.loads(r.stdout), site_sha=last["site_sha"], round=last["n"], at=now(), ratings_dir=d)
    wj(os.path.join(cdir(p), "verdict.json"), v)
    write_loop(p)
    print(json.dumps(v, ensure_ascii=False))
    sys.exit(0 if v["accepted"] else 3)


def main(a):
    if len(a) < 2:
        die("usage: round|triage|fixed|status|audit <project> ... (see the header)", 2)
    cmd, p = a[0], os.path.abspath(a[1])
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
    elif cmd == "round" and opts.get("web"):
        do_round(p, opts["web"])
    elif cmd == "audit" and opts.get("web"):
        audit(p, opts["web"])
    elif cmd == "triage" and len(rest) == 2:
        triage(p, rest[0], rest[1], opts)
    elif cmd == "fixed" and len(rest) == 1:
        fixed(p, rest[0], opts.get("evidence"))
    else:
        die("usage: round <p> --web <url> | triage <p> <finding> <state> [--reason|--expected|--of|--conflict-with] | "
            "fixed <p> <finding> --evidence <t> | status <p> | audit <p> --web <url>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
