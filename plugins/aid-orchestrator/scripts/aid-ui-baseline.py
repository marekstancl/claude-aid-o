#!/usr/bin/env python3
"""aid-ui-baseline.py - the baseline of an existing web application and its regression check (P116).

An existing app must keep every task that works today. The baseline is a list of named tasks of today's app
(.aid-ui/baseline/tasks.json), approved by the PM, played in a browser once (result.json, shots/); the new app's
model replaces each with a task of its own (`replaces` in docs/design/screens.json) that must end in the same result.

  list <project> --url <app>
      A draft of today's tasks from the app's navigation (every link of its <nav>: open it, the result is that
      page's heading) into .aid-ui/baseline/tasks.json - a draft for the agent to complete with inputs, actions and
      the results people rely on. Refused when the file exists (the list is never overwritten silently).
  capture <project> --url <app> [--login <storage.json>]
      Only the list the PM approved: the state's app_baseline.approved_sha (a PM answer of kind exception, target
      baseline@<sha>) must be the sha256 of tasks.json now - a draft or a list changed since is refused before any
      browser starts. Plays every task through lib/ui-fidelity/aid-ui-baseline.mjs (Playwright; the task's login, else
      --login, as storageState) and writes .aid-ui/baseline/result.json {captured_at, url, tasks_sha256, results:
      [{id, passed, url, why}]} and shots/<task>-<n>.png. A task that does not reach its result today (an expired
      login, a page gone) is named and the capture exits 1.
  compare <project> [--result <gate result.json>]
      The gate result read is .aid-ui/verify/result.json (the studio's gate), or --result (the run gate's live result in the
      project's code). aid-ui-package.py build runs it for an existing app: a failing compare refuses the handover.
      No tasks.json -> "bez výchozího stavu", exit 0. Otherwise refused (exit 1, every reason listed) when the list is
      not the approved one or not captured as it is, and for every baseline task that has no new task with
      `replaces` naming it which passed the last gate (every app_flows row of the task pass, of the model now) and
      whose done_when.expect contains the baseline result's expected text - unless the PM approved its removal (an
      answer by pm, kind exception, decision approve, target task@<id>). Two new tasks replacing one: either suffices.

tasks.json: [{id, title, steps: [{url?, action?, input?: {<label or name>: value}}], login: <file under
.aid-ui/baseline/storage/> | null, result: {url?, expect}}]. Exit: 0 ok, 1 refused, 2 usage.
"""
import datetime, hashlib, html.parser, json, os, re, subprocess, sys, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(HERE, "..", "lib", "ui-fidelity", "aid-ui-baseline.mjs")


def die(msg, code=1):
    print("ERROR: aid-ui-baseline.py: " + msg, file=sys.stderr)
    sys.exit(code)


def bdir(p):
    return os.path.join(p, ".aid-ui", "baseline")


def sha_file(f):
    return hashlib.sha256(open(f, "rb").read()).hexdigest()


def load(f, what):
    try:
        return json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"{what}: {e}")


def norm(t):
    return " ".join(str(t or "").split()).casefold()


class Nav(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(); self.depth = 0; self.links = []; self.cur = None; self.h1 = None; self.in_h1 = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "nav":
            self.depth += 1
        elif tag == "a" and self.depth and a.get("href"):
            self.cur = [a["href"], ""]
        elif tag == "h1" and self.h1 is None:
            self.in_h1, self.h1 = True, ""

    def handle_endtag(self, tag):
        if tag == "nav" and self.depth:
            self.depth -= 1
        elif tag == "a" and self.cur:
            self.links.append((self.cur[0], " ".join(self.cur[1].split()))); self.cur = None
        elif tag == "h1":
            self.in_h1 = False

    def handle_data(self, d):
        if self.cur is not None:
            self.cur[1] += d
        if self.in_h1:
            self.h1 += d


def fetch(url):
    with urllib.request.urlopen(url, timeout=20) as r:
        return r.read().decode("utf-8", "replace")


def cmd_list(p, url):
    f = os.path.join(bdir(p), "tasks.json")
    if os.path.exists(f):
        die(f"{f} exists; the list is edited, never regenerated over itself (remove it to draft again)")
    try:
        n = Nav(); n.feed(fetch(url))
    except (OSError, ValueError) as e:
        die(f"list: the app at {url} does not answer ({e})")
    tasks, seen = [], set()
    for href, text in n.links:
        u = urllib.parse.urljoin(url, href)
        if urllib.parse.urlsplit(u)[:2] != urllib.parse.urlsplit(url)[:2] or u in seen:
            continue   # only the app's own pages, each once
        seen.add(u)
        try:
            h = Nav(); h.feed(fetch(u)); expect = " ".join((h.h1 or "").split())
        except (OSError, ValueError):
            expect = ""
        path = urllib.parse.urlsplit(u).path or "/"
        tid = re.sub(r"[^a-z0-9]+", "-", (text or path).lower().encode("ascii", "ignore").decode()).strip("-")[:60] or f"uloha-{len(tasks) + 1}"
        tasks.append({"id": tid, "title": text or path, "steps": [{"url": path}], "login": None,
                      "result": {"url": path, "expect": expect or "(doplň, co má být vidět)"}})
    os.makedirs(bdir(p), exist_ok=True)
    with open(f, "w", encoding="utf-8") as fh:
        json.dump(tasks, fh, ensure_ascii=False, indent=1)
    print(f"BASELINE DRAFT: {f} ({len(tasks)} úloh z navigace; doplň vstupy, akce a výsledky, pak schválení PM: exception baseline@{sha_file(f)})")


def approved(p):
    """(sha now, why not approved or '')"""
    f = os.path.join(bdir(p), "tasks.json")
    if not os.path.isfile(f):
        return None, "bez výchozího stavu"
    sha = sha_file(f)
    try:
        a = (json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8")).get("app_baseline") or {}).get("approved_sha")
    except (OSError, ValueError):
        a = None
    if not a:
        return sha, f"the PM has not approved the baseline list (exception baseline@{sha})"
    if a != sha:
        return sha, f".aid-ui/baseline/tasks.json changed since the PM approved it (now {sha[:12]}, approved {a[:12]}); ask again"
    return sha, ""


def cmd_capture(p, url, login):
    sha, why = approved(p)
    if why:
        die("capture refused: " + why)
    tasks = load(os.path.join(bdir(p), "tasks.json"), "tasks.json")
    if not isinstance(tasks, list) or not all(isinstance(t, dict) and t.get("id") and isinstance(t.get("result"), dict) and t["result"].get("expect") for t in tasks):
        die("capture refused: every task of tasks.json needs an id and result.expect")
    for t in tasks:   # a task's login is a file under .aid-ui/baseline/storage/, never a path out of it
        lg = t.get("login")
        if lg and (os.path.isabs(lg) or ".." in lg.split("/") or not os.path.isfile(os.path.join(bdir(p), lg))):
            die(f"capture refused: task {t['id']}: login {lg!r} is not a file under .aid-ui/baseline/")
    out = os.path.join(bdir(p), "capture.part")
    cmd = ["node", RUNNER, "--tasks", os.path.join(bdir(p), "tasks.json"), "--base", url, "--root", bdir(p), "--out", out]
    if login:
        cmd += ["--login", os.path.abspath(login)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    try:
        res = json.load(open(os.path.join(out, "results.json"), encoding="utf-8"))
    except (OSError, ValueError):
        die("capture: the browser run gave no results: " + (r.stderr or r.stdout)[-400:])
    shots = os.path.join(bdir(p), "shots")
    if os.path.isdir(os.path.join(out, "shots")):
        import shutil
        shutil.rmtree(shots, ignore_errors=True)   # the shots of this capture only
        os.replace(os.path.join(out, "shots"), shots)
    doc = {"captured_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "url": url,
           "tasks_sha256": sha, "results": res}
    with open(os.path.join(bdir(p), "result.json"), "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
    import shutil
    shutil.rmtree(out, ignore_errors=True)
    bad = [x for x in res if not x.get("passed")]
    for x in res:
        print(f"{'OK  ' if x.get('passed') else 'FAIL'} {x['id']}: {x.get('why') or x.get('url')}")
    if bad:
        die("capture: tasks that do not reach their result today: " + ", ".join(f"{x['id']} ({x.get('why')})" for x in bad))
    print(f"BASELINE CAPTURED: {len(res)} úloh ({bdir(p)}/result.json)")


def cmd_compare(p, result=None):
    sha, why = approved(p)
    if sha is None:
        print("compare: bez výchozího stavu")
        return 0
    bad = [why] if why else []
    base = load(os.path.join(bdir(p), "tasks.json"), "tasks.json")
    cap = None
    try:
        cap = json.load(open(os.path.join(bdir(p), "result.json"), encoding="utf-8"))
    except (OSError, ValueError):
        bad.append("the baseline is not captured (aid-ui-baseline.py capture)")
    if cap and cap.get("tasks_sha256") != sha:
        bad.append("the captured baseline is of another list than tasks.json now; capture again")
    try:
        m = json.load(open(os.path.join(p, "docs", "design", "screens.json"), encoding="utf-8"))
        msha = sha_file(os.path.join(p, "docs", "design", "screens.json"))
    except (OSError, ValueError) as e:
        die(f"compare: no readable docs/design/screens.json ({e})")
    try:
        gate = json.load(open(result or os.path.join(p, ".aid-ui", "verify", "result.json"), encoding="utf-8"))
    except (OSError, ValueError):
        gate = {}
    flows = {}
    for r in gate.get("rows") or []:
        if isinstance(r, dict) and r.get("check") == "app_flows":
            flows.setdefault(r.get("page"), []).append(r.get("status") == "pass" and r.get("model_sha256") == msha)
    passed = {k for k, v in flows.items() if v and all(v)}
    try:
        st = json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        st = {}
    removed = {a["target"][5:]: a.get("comment") or "" for a in (st.get("answers") or {}).values()
               if isinstance(a, dict) and a.get("kind") == "exception" and a.get("decision") == "approve"
               and a.get("by") == "pm" and str(a.get("target") or "").startswith("task@")}
    lines = []
    for b in base:
        bid, want = b.get("id"), norm((b.get("result") or {}).get("expect"))
        news = [t for t in m.get("tasks") or [] if t.get("replaces") == bid]
        ok = [t["id"] for t in news if t["id"] in passed and want and want in norm((t.get("done_when") or {}).get("expect"))]
        if ok:
            lines.append(f"OK   {bid}: nahrazena úlohou {', '.join(ok)} se stejným výsledkem")
        elif bid in removed:
            lines.append(f"ZRUŠENA {bid}: zrušení schválil PM ({removed[bid] or 'bez komentáře'})")
        else:
            why = ("žádná nová úloha ji nenahrazuje (replaces)" if not news else
                   "náhrada neprošla poslední bránou modelu teď" if not any(t["id"] in passed for t in news) else
                   "náhrada končí jiným výsledkem než dnešní úloha")
            lines.append(f"FAIL {bid}: {why}")
            bad.append(f"{bid}: {why}")
    for x in lines:
        print(x)
    if bad:
        die("compare: " + "; ".join(bad))
    print(f"compare: OK ({len(base)} úloh výchozího stavu)")
    return 0


def opt(a, name):
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else None


def main(a):
    if len(a) >= 2 and os.path.isdir(a[1]):
        p = os.path.abspath(a[1])
        if a[0] == "list" and opt(a, "--url") and len(a) == 4:
            return cmd_list(p, opt(a, "--url"))
        if a[0] == "capture" and opt(a, "--url") and len(a) in (4, 6) and (len(a) == 4 or opt(a, "--login")):
            return cmd_capture(p, opt(a, "--url"), opt(a, "--login"))
        if a[0] == "compare" and (len(a) == 2 or (len(a) == 4 and a[2] == "--result")):
            return cmd_compare(p, a[3] if len(a) == 4 else None)
    die("usage: aid-ui-baseline.py list <project> --url <app> | capture <project> --url <app> [--login <storage.json>] | compare <project> [--result <json>]", 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)
