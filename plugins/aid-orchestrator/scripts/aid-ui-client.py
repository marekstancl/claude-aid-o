#!/usr/bin/env python3
"""aid-ui-client.py - the client agent and the critic of /aid-ui (P113a, 12. 10. 2026).

  answer <project> --studio <url> [--once] [--dry] [--watch <seconds>]
      The client agent answers the studio's open questions as the paying owner would. Logs in with a one-time
      code (.aid-ui/studio.code -> session cookie), reads /state, and for the first open question screenshots
      the studio, the card previews and the live pages the cards link to, asks the model (role from
      skills/ui-design/critic/client-template.md + the type's persona), validates the JSON and POSTs /answer.
      A refused answer goes back once with the studio's reason. Every turn: .aid-ui/client/turns/<q>-<n>/
      (prompt.md, images, turn.json); feedback for the tool: .aid-ui/client/feedback.jsonl. --watch loops every
      <seconds> until .aid-ui/client/stop exists (one loop per project, flock).
  critic <project> --web <url> [--audit] [--out <dir>]
      One rating of the web by the frozen critic (aid-ui-critic.py prompt; freeze first). The critic gets a
      bundle and nothing else: a copy of site/ as its working directory, full-page shots of every page (1440
      and 390), the live URL; no history, no earlier scores, no fixes - the same for --audit (a closing blind
      rating). The answer is validated with aid-ui-critic.py score. Record: <out>/run.json {kind, web,
      site_sha, frozen_sha, prompt_sha256, images, provider, attempts, score}; default out
      .aid-ui/critic/runs/<time>-<kind>/. Exit 0 rated, 1 no valid answer from any provider, 2 usage.
  costs <project>
      The project's cost book in one JSON line (aid_ui_costs.summary).

Providers (H2, PM 12. 10. 2026): Codex on the subscription first (OPENAI_API_KEY, ANTHROPIC_API_KEY and
ANTHROPIC_AUTH_TOKEN removed from every text process: text never goes over a paid API); a refusal (usage/rate limit, failed run, no answer) or an invalid answer
twice hands the same prompt and images, in the same working directory, to an independent Claude Code (clean
context, read-only tools, AID_UI_STANDIN_MODEL, default sonnet). Both failing: answer writes
.aid-ui/client/stop and stops; critic exits 1. AID_UI_STANDIN=off disables the stand-in. Every call is
written to the cost book (.aid-ui/costs.jsonl) at its list-price equivalent.
"""
import hashlib, http.cookiejar, json, os, re, secrets, shutil, subprocess, sys, tempfile, time
import urllib.error, urllib.request
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")
sys.path.insert(0, os.path.join(HERE, "lib"))
import aid_ui_costs as costs   # noqa: E402

CRITIC = os.path.join(HERE, "aid-ui-critic.py")
TOOL = os.environ.get("AID_UI_TOOL") or os.path.join(HERE, "aid-ui-tool.sh")
TIMEOUT = int(os.environ.get("AID_UI_CLIENT_TIMEOUT", "1800"))
REFUSED = re.compile(r"usage limit|quota|rate limit|\b429\b|exceeded|insufficient_quota", re.I)
MAX_IMAGES, MAX_PAGES, MAX_ROUNDS_HINT = 12, 8, 4


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def die(msg, code=1):
    print("ERROR: aid-ui-client.py: " + msg, file=sys.stderr)
    sys.exit(code)


def sha_file(f):
    with open(f, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def wj(p, obj):
    with open(p, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)


def parse_json(text):
    t = (text or "").strip()
    m = re.match(r"^```(?:json)?\s*(.*?)\s*```$", t, re.S)
    t = m.group(1) if m else t
    m = re.search(r"\{.*\}", t, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except ValueError:
        return None


# ---------------------------------------------------------------- providers

PAID_KEYS = ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN")


def text_env():
    return {k: v for k, v in os.environ.items() if k not in PAID_KEYS}   # text never on a paid API, only subscriptions


def codex(prompt, images, cwd, out):
    cmd = ["codex", "exec", "--skip-git-repo-check", "-C", cwd, "-s", "read-only", "--json", "-c", "model_reasoning_effort=high"]
    if os.environ.get("AID_UI_CODEX_MODEL"):
        cmd += ["-m", os.environ["AID_UI_CODEX_MODEL"]]
    for i in images:
        cmd += ["-i", i]
    try:
        r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, env=text_env(), timeout=TIMEOUT)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return {"provider": "codex", "rc": 127, "text": "", "usage": {}, "log": "codex not found" if isinstance(e, FileNotFoundError) else "codex timed out", "refused": False, "commands": []}
    text, usage, cmds, err = "", {}, [], ""
    with open(os.path.join(out, "events.jsonl"), "a", encoding="utf-8") as ev:
        for line in (r.stdout or "").splitlines():
            if not line.strip().startswith("{"):
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            ev.write(json.dumps(e, ensure_ascii=False) + "\n")
            it = e.get("item") or {}
            if e.get("type") == "item.completed" and it.get("type") == "agent_message":
                text = it.get("text") or text
            if e.get("type") == "item.completed" and it.get("type") == "command_execution":
                cmds.append(it.get("command", ""))
            if e.get("type") == "turn.completed":
                usage = e.get("usage") or {}
            if e.get("type") in ("error", "turn.failed"):
                err += json.dumps(e)[:400]
    logtxt = (r.stderr or "")[-1500:] + err
    return {"provider": "codex", "rc": r.returncode, "text": text, "commands": cmds, "log": logtxt,
            "refused": bool(REFUSED.search(logtxt + (r.stdout or "")[-2000:])),
            "usage": {"input": usage.get("input_tokens"), "cached": usage.get("cached_input_tokens"), "output": usage.get("output_tokens")}}


def claude(prompt, images, cwd, out):
    model = os.environ.get("AID_UI_STANDIN_MODEL", "sonnet")
    p = prompt + ("\n\n# Obrázky\nPřiložené obrázky si přečti nástrojem Read, každý zvlášť:\n" + "\n".join("- " + i for i in images) if images else "")
    cmd = ["claude", "-p", "--output-format", "json", "--model", model, "--allowedTools", "Read", "Glob", "Grep",
           "--add-dir", cwd, "--add-dir", out]
    try:
        r = subprocess.run(cmd, input=p, cwd=cwd, capture_output=True, text=True, env=text_env(), timeout=TIMEOUT)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return {"provider": "claude", "model": model, "rc": 127, "text": "", "usage": {}, "log": "claude not found" if isinstance(e, FileNotFoundError) else "claude timed out"}
    text, usage, usd = "", {}, None
    try:
        j = json.loads(r.stdout or "{}")
        text, usage, usd = j.get("result") or "", j.get("usage") or {}, j.get("total_cost_usd")
    except ValueError:
        text = r.stdout or ""
    return {"provider": "claude", "model": model, "rc": r.returncode, "text": text, "log": (r.stderr or "")[-1500:], "usd": usd,
            "usage": {"input": (usage.get("input_tokens") or 0) + (usage.get("cache_read_input_tokens") or 0),
                      "cached": usage.get("cache_read_input_tokens"), "output": usage.get("output_tokens")}}


def ask(project, prompt, images, cwd, out, valid, purpose):
    """Codex first; an invalid answer once more with the reason; then the Claude stand-in on the same bundle.
    valid(text) -> (answer, error). Returns (answer or None, record)."""
    rec = {"prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(), "attempts": []}

    def run(fn, p):
        r = fn(p, images, cwd, out)
        costs.tokens(project, r["provider"], r.get("model"), r["usage"], purpose, r.get("usd"))
        a, err = valid(r["text"]) if (r["text"] and not r["rc"]) else (None, None)
        rec["attempts"].append({"provider": r["provider"], "rc": r["rc"], "refused": r.get("refused", False),
                                "error": err, "prompt_sha256": hashlib.sha256(p.encode()).hexdigest(), "log_tail": r["log"][-300:]})
        return r, a, err

    p, why = prompt, None
    for n in (1, 2):
        r, a, err = run(codex, p)
        if a is not None:
            rec.update(provider="codex", commands=r.get("commands", []))
            return a, rec
        if r["refused"] or r["rc"] or not r["text"]:
            why = "limit" if r["refused"] else ("rc %d" % r["rc"] if r["rc"] else "no answer")
            break
        why = "invalid answer twice: " + str(err)
        p = prompt + "\n\nPředchozí odpověď nebyla platná (%s). Vrať jen JSON podle zadání." % err
    rec["stand_in_reason"] = why
    if os.environ.get("AID_UI_STANDIN", "on") == "off":
        rec["provider"] = None
        return None, rec
    log("Codex refused (%s); the Claude stand-in takes the same bundle" % why)
    r, a, err = run(claude, prompt)
    rec["provider"] = "claude" if a is not None else None
    return a, rec


# ---------------------------------------------------------------- screenshots

def shots(out, urls, cookie=None, studio=None):
    args = [out] + (["--cookie", cookie, "--studio", studio] if cookie and studio else []) + urls
    r = subprocess.run(["bash", TOOL, "shot"] + args, capture_output=True, text=True, timeout=900)
    try:
        files = json.loads(r.stdout.strip().splitlines()[-1])["files"]
    except (ValueError, IndexError, KeyError):
        log("shots failed:", (r.stderr or "")[-300:])
        return []
    for f in files:
        if f.startswith("ERR"):
            log("shot:", f)
    return [f for f in files if not f.startswith("ERR") and os.path.exists(f)]


def to_png(files):
    webp = [f for f in files if f.endswith(".webp")]
    conv = {}
    if webp:
        r = subprocess.run(["bash", TOOL, "shot", "convert"] + webp, capture_output=True, text=True, timeout=300)
        try:
            conv = dict(zip(webp, json.loads(r.stdout.strip().splitlines()[-1])["files"]))
        except (ValueError, IndexError, KeyError):
            pass
    return [conv.get(f, f) for f in files]


def image_meta(images):
    return [{"file": os.path.basename(i), "sha256": sha_file(i), "bytes": os.path.getsize(i)} for i in images]


# ---------------------------------------------------------------- critic

def site_pages(site):
    pages = []
    for root, _, files in os.walk(site):
        if "index.html" in files:
            rel = os.path.relpath(root, site)
            pages.append("" if rel == "." else rel.replace(os.sep, "/") + "/")
    return sorted(pages, key=lambda p: (p != "", p))


def site_sha(site):
    h = hashlib.sha256()
    for root, dirs, files in os.walk(site):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            h.update(os.path.relpath(p, site).encode() + b"\0" + sha_file(p).encode() + b"\n")
    return h.hexdigest()


def critic(project, web, audit, out):
    r = subprocess.run([sys.executable, CRITIC, "prompt", project], capture_output=True, text=True)
    if r.returncode:
        die("no usable frozen critic: " + (r.stderr or r.stdout).strip())
    role = r.stdout
    frozen = json.load(open(os.path.join(project, ".aid-ui", "critic", "frozen.json"), encoding="utf-8"))
    site = os.path.join(project, "site")
    if not os.path.isdir(site):
        die(f"no site directory {site}")
    kind = "audit" if audit else "critic"
    out = out or os.path.join(project, ".aid-ui", "critic", "runs", time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + kind)
    os.makedirs(out, exist_ok=True)
    bundle = os.path.join(out, "bundle")
    shutil.copytree(site, os.path.join(bundle, "site"), dirs_exist_ok=True)   # the critic's whole world: the web
    pages = site_pages(site)
    base = web.rstrip("/") + "/"
    # the address must serve this site: its home page is byte for byte site/index.html (or the rating would be
    # of another web than the one recorded and audited)
    try:
        with urllib.request.urlopen(base, timeout=30) as resp:
            live = hashlib.sha256(resp.read()).hexdigest()
    except (urllib.error.URLError, OSError, ValueError) as e:
        die(f"{base} does not answer ({e}); serve the site (aid-ui-serve.sh) first")
    if live != sha_file(os.path.join(site, "index.html")):
        die(f"{base} does not serve {site}: its home page differs from site/index.html")
    urls = [base + p for p in pages[:MAX_PAGES]]
    images = shots(os.path.join(out, "shots"), urls)
    names = {os.path.basename(i) for i in images}
    want = [(re.sub(r"[^a-z0-9]+", "-", p.strip("/"), flags=re.I) or "index") + "-%d.png" % w for p in pages[:MAX_PAGES] for w in (1440, 390)]
    if [n for n in want if n not in names]:   # the critic rates the live web on both widths, never from files alone
        wj(os.path.join(out, "run.json"), {"kind": kind, "web": base, "pages": urls, "at": now(), "error": "missing shots",
                                          "missing": [n for n in want if n not in names]})
        die("no rating without a desktop and a mobile shot of every page; missing: " + ", ".join(n for n in want if n not in names))
    prompt = (role + "\n\n# Hodnocený web\n\nŽivý web: " + base + "\nStránky:\n" + "\n".join("- " + u for u in urls)
              + "\n\nSoubory webu máš v pracovním adresáři v `site/` (jen ke čtení; texty, titulky, popisy). Nic mimo"
                " pracovní adresář nečti.\n\n# Přiložené snímky (celá stránka; 1440 = počítač, 390 = mobil)\n"
              + "\n".join("- " + os.path.basename(i) for i in images))
    with open(os.path.join(out, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)

    def valid(text):
        a = parse_json(text)
        if not isinstance(a, dict):
            return None, "not JSON"
        with tempfile.NamedTemporaryFile("w", suffix=".json", dir=out, delete=False, encoding="utf-8") as f:
            json.dump(a, f, ensure_ascii=False)
        s = subprocess.run([sys.executable, CRITIC, "score", project, f.name], capture_output=True, text=True)
        os.unlink(f.name)
        if s.returncode:
            return None, (s.stderr or s.stdout).strip().replace("ERROR: aid-ui-critic.py: ", "")[:300]
        return {"answer": a, "score": json.loads(s.stdout)}, None

    got, rec = ask(project, prompt, images, bundle, out, valid, "critic:" + kind)
    run = {"kind": kind, "web": base, "site_sha": site_sha(site), "frozen_sha": frozen["sha256"], "images": image_meta(images),
           "pages": urls, "at": now(), **rec}
    if got:
        wj(os.path.join(out, "answer.json"), got["answer"])
        run["score"] = got["score"]
    wj(os.path.join(out, "run.json"), run)
    if not got:
        die(f"no valid rating from any provider ({rec.get('stand_in_reason')}); record in {out}/run.json")
    print(json.dumps({"out": out, "provider": rec["provider"], **got["score"]}, ensure_ascii=False))


# ---------------------------------------------------------------- studio answers

class Studio:
    def __init__(self, project, url):
        self.project, self.url = project, url.rstrip("/")
        self.dir = os.path.join(project, ".aid-ui", "client")
        self.turns, self.cookie_f = os.path.join(self.dir, "turns"), os.path.join(self.dir, "cookie.txt")
        os.makedirs(self.turns, exist_ok=True)

    def cookie(self):
        return open(self.cookie_f).read().strip() if os.path.exists(self.cookie_f) else ""

    def req(self, path, body=None, raw=False):
        r = urllib.request.Request(self.url + path, data=json.dumps(body).encode() if body is not None else None,
                                   headers={"Cookie": self.cookie(), "Content-Type": "application/json", "Referer": self.url + "/"},
                                   method="POST" if body is not None else "GET")
        try:
            with urllib.request.urlopen(r, timeout=30) as resp:
                data = resp.read()
                return resp.status, (data if raw else json.loads(data or b"null"))
        except urllib.error.HTTPError as e:
            data = e.read()
            if raw:
                return e.code, data
            try:
                return e.code, json.loads(data or b"null")
            except ValueError:
                return e.code, data.decode("utf-8", "replace")[:300]

    def login(self):
        code = secrets.token_hex(16)
        cf = os.path.join(self.project, ".aid-ui", "studio.code")
        fd = os.open(cf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.write(fd, (code + "\n").encode())
        os.close(fd)
        cj = http.cookiejar.CookieJar()
        try:
            urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj)).open(self.url + "/?k=" + code, timeout=30)
        except urllib.error.HTTPError:
            pass
        c = next((f"{c.name}={c.value}" for c in cj if c.name.startswith("aid_studio_")), "")
        if not c:
            die("no session cookie from the studio")
        fd = os.open(self.cookie_f, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.write(fd, c.encode())
        os.close(fd)

    def state(self):
        st, d = self.req("/state")
        if st == 403:
            self.login()
            st, d = self.req("/state")
        if st != 200:
            die("/state %s %s" % (st, str(d)[:200]))
        return d

    def preview(self, q, c, n, out):
        if "_file" in c:   # a card read from the payload: its own preview file, or nothing when the path left the studio
            if n == 2 or not c["_file"]:
                return None
            dst = os.path.join(out, "card-%s%s" % (c["id"], os.path.splitext(c["_file"])[1]))
            try:
                shutil.copy(c["_file"], dst)
                return dst
            except OSError:
                return None
        st, data = self.req("/preview?question=%s&card=%s%s" % (q["id"], c["id"], "&n=2" if n == 2 else ""), raw=True)
        if st != 200 or not isinstance(data, bytes):
            return None
        ext = ".webp" if data[:4] == b"RIFF" else ".png" if data[:4] == b"\x89PNG" else ".jpg"
        f = os.path.join(out, "card-%s%s%s" % (c["id"], "-2" if n == 2 else "", ext))
        with open(f, "wb") as fh:
            fh.write(data)
        return f


def client_role(project):
    import yaml
    fz = os.path.join(project, ".aid-ui", "critic", "frozen.json")
    if os.path.isfile(fz):
        rub = json.load(open(fz, encoding="utf-8"))["rubric"]
    else:
        rub = yaml.safe_load(open(os.path.join(SKILL, "critic", os.environ.get("AID_UI_CLIENT_TYPE", "web-local") + ".yaml"), encoding="utf-8"))
    lang = "sk"
    try:
        m = re.search(r'<html[^>]*\blang="([a-z]{2})', open(os.path.join(project, "site", "index.html"), encoding="utf-8").read(4000))
        lang = m.group(1) if m else lang
    except OSError:
        pass
    t = open(os.path.join(SKILL, "critic", "client-template.md"), encoding="utf-8").read()
    p = rub["persona"]
    return t.format(persona_who=p["who"], persona_wants=p["wants"], persona_rules="\n".join("- " + r for r in p["rules"]), lang=lang)


def card_text(c):
    keep = ("id", "title", "eyebrow", "thesis", "uniqueness", "risk", "source", "method", "honours", "url", "palette", "tags", "preview2_label")
    return {k: c[k] for k in keep if c.get(k) not in (None, "", [])}


def question_cards(s, d, q):
    cards = [c for c in d.get("cards") or [] if c.get("question") == q["id"]]
    if cards:
        return cards
    try:   # with several open questions the studio lists one's cards; read this one's from the payload
        pq = [x for x in json.load(open(os.path.join(s.project, ".aid-ui/studio/payload.json")))["questions"] if x["id"] == q["id"]]
        sd = os.path.realpath(os.path.join(s.project, ".aid-ui", "studio"))
        inside = lambda p: p if p.startswith(sd + os.sep) and os.path.isfile(p) else None   # a preview path never leaves the studio folder
        return [dict(c, question=q["id"], _file=inside(os.path.realpath(os.path.join(sd, str(c.get("preview") or "")))))
                for c in (pq[0].get("cards") or [])] if pq else []
    except (OSError, ValueError, KeyError):
        return []


def answer_one(s, role, dry):
    d = s.state()
    qs = [q for q in d["questions"] if not q.get("answered") and not q.get("done")]
    if not qs:
        return False
    q = qs[0]
    cards = question_cards(s, d, q)
    n = 1 + sum(1 for x in os.listdir(s.turns) if x.startswith(q["id"] + "-"))
    out = os.path.join(s.turns, "%s-%d" % (q["id"], n))
    os.makedirs(out, exist_ok=True)
    host = urlsplit(s.url).hostname   # parsed, not a string prefix: "http://<host>@elsewhere/" goes elsewhere
    urls = [c["url"] for c in cards if isinstance(c.get("url"), str) and urlsplit(c["url"]).scheme in ("http", "https")
            and urlsplit(c["url"]).hostname == host][:3]
    images = shots(out, urls, s.cookie_f, s.url + "/")
    for c in cards:
        for k in (1, 2):
            f = s.preview(q, c, k, out)
            if f:
                images.append(f)
    images = [i for i in to_png(images) if i and os.path.exists(i)][:MAX_IMAGES]
    qtext = {k: q.get(k) for k in ("id", "kind", "part", "title", "body", "prompt", "eyebrow", "next", "outcome") if q.get(k)}
    links = d.get("links") or {}
    prompt = (role + "\n\n# Otázka ze studia\n\n" + json.dumps(qtext, ensure_ascii=False, indent=1)
              + ("\n\n# Tvoje dřívější volba, na kterou otázka navazuje\n" + json.dumps(q["prior"], ensure_ascii=False) if q.get("prior") else "")
              + ("\n\n# Karty (náhledy jsou v přiložených obrázcích; živé stránky karet jsou nafocené na počítači i mobilu)\n"
                 + json.dumps([card_text(c) for c in cards], ensure_ascii=False, indent=1) if cards else "\n\n(otázka bez karet: rozhodnutí approve nebo return)")
              + ("\n\n# Odkazy, které studio ukazuje\n" + json.dumps(links, ensure_ascii=False) if links else "")
              + "\n\n# Přiložené obrázky\n" + "\n".join("- " + os.path.basename(i) + (" (snímek studia, jak ho vidíš)" if "studio-" in i else "") for i in images)
              + "\n\nProjekt máš v pracovním adresáři jen ke čtení a jen tyto části: docs/, site/, .aid-ui/sources/, .aid-ui/old-site/."
                " Nic mimo ně nečti. Vrať jen JSON podle zadání."
              + ("\n\nToto je už %d. kolo téže otázky. Rozhodni teď (choose/approve) s nejlepší dostupnou možností a do comment napiš, co ti pořád chybí." % n
                 if n >= MAX_ROUNDS_HINT else ""))
    with open(os.path.join(out, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    rec = {"question": qtext, "target": q.get("target"), "cards": [card_text(c) for c in cards], "images": image_meta(images), "round": n, "at": now()}
    if dry:
        rec["dry"] = True
        wj(os.path.join(out, "turn.json"), rec)
        log("DRY: prompt (%d chars) and %d images for %s" % (len(prompt), len(images), q["id"]))
        return False

    def valid(text):
        a = parse_json(text)
        if not isinstance(a, dict) or not isinstance(a.get("answer"), dict) or not a["answer"].get("decision"):
            return None, "no answer.decision in the JSON"
        return a, None

    p = prompt
    for attempt in (1, 2):
        a, mrec = ask(s.project, p, images, s.project, out, valid, "client")
        rec.update(model=mrec, attempt=attempt)
        if a is None:
            wj(os.path.join(out, "turn.json"), rec)
            with open(os.path.join(s.dir, "stop"), "w") as f:
                f.write("no usable answer from Codex nor the Claude stand-in for %s at %s\n" % (q["id"], now()))
            log("STOP: no usable answer for %s (%s); question left open" % (q["id"], mrec.get("stand_in_reason")))
            return False
        ans = a["answer"]
        body = {"question": q["id"], "kind": q["kind"], "target": q.get("target"), "decision": ans.get("decision"),
                "choice": ans.get("choice") or None, "comment": str(ans.get("comment") or "").strip()}
        st, resp = s.req("/answer", body)
        rec.update(answer=ans, feedback=a.get("feedback"), post_status=st, post_resp=resp)
        wj(os.path.join(out, "turn.json"), rec)
        if st == 200:
            with open(os.path.join(s.dir, "feedback.jsonl"), "a", encoding="utf-8") as f:
                f.write(json.dumps({"at": rec["at"], "question": q["id"], "kind": q["kind"], "title": q.get("title"), "round": n,
                                    "decision": body["decision"], "choice": body["choice"], "comment": body["comment"],
                                    "feedback": a.get("feedback"), "provider": mrec.get("provider"), "turn": os.path.basename(out)}, ensure_ascii=False) + "\n")
            log("answered %s: %s %s | %s" % (q["id"], body["decision"], body["choice"] or "", body["comment"][:80]))
            return True
        log("studio refused the answer (%s): %s" % (st, resp))
        p = prompt + "\n\nStudio odmítlo odpověď: %s. Oprav ji (dodrž pravidla rozhodnutí) a vrať jen JSON." % json.dumps(resp, ensure_ascii=False)
    log("gave up on %s this round" % q["id"])
    return False


def answer(project, url, once, dry, watch):
    s = Studio(project, url)
    stop = os.path.join(s.dir, "stop")
    role = client_role(project)
    import fcntl
    lock = open(os.path.join(s.dir, ".lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        die("another client loop runs for this project")
    while True:
        if os.path.exists(stop):
            die("stopped: " + open(stop).read().strip() + f" (remove {stop} to go on)")
        while answer_one(s, role, dry) and not once:
            if os.path.exists(stop):
                break
        if not watch or dry or once:
            return
        time.sleep(watch)


def main(a):
    if len(a) >= 2 and a[0] == "costs":
        print(json.dumps(costs.summary(os.path.abspath(a[1])), ensure_ascii=False))
        return
    opt = lambda k: a[a.index(k) + 1] if k in a and a.index(k) + 1 < len(a) else None
    if len(a) >= 2 and a[0] == "critic" and opt("--web"):
        return critic(os.path.abspath(a[1]), opt("--web"), "--audit" in a, opt("--out"))
    if len(a) >= 2 and a[0] == "answer" and opt("--studio"):
        w = opt("--watch")
        return answer(os.path.abspath(a[1]), opt("--studio"), "--once" in a, "--dry" in a, int(w) if w else 0)
    die("usage: answer <project> --studio <url> [--once] [--dry] [--watch <s>] | critic <project> --web <url> [--audit] [--out <dir>] | costs <project>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
