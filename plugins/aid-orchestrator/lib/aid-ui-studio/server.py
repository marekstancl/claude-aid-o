#!/usr/bin/env python3
"""aid-ui studio server (P103 Step 3): the one page where the PM makes every
/aid-ui choice and approval. Python stdlib only.

usage: server.py --project <dir> --host <h> --port <p> --token-file <path>

Payload: <project>/.aid-ui/studio/payload.json, written by the agent and re-read
on every request, so the agent opens a round by rewriting it:
  {"now":       {"title", "text"}   (what the agent is doing right now; optional),
   "steps":     [{"id", "title", "status": "done|current|todo", "description"}],
   "questions": [{"id", "kind", "target", "opened_at": ISO-8601, "title", "prompt", "body",
                  "next" (what the agent does after approval), "eyebrow" (heading override)}],
   "cards":     [{"id", "question", "title", "preview", "thesis", "palette": [css colours],
                  "risk", "uniqueness", "url"}],
   "overview":  {"site_url": "http(s)://…", "todo": [{"what", "how", "blocking": bool, "question": <open question id>}]}
                (optional: the web at a glance on the studio's home view; the page derives the
                status itself; a wrong type or a non-http(s) site_url makes the payload invalid)}
A question may also carry "outcome": the decision in one sentence, shown once it is answered.
Every card has a non-empty string id and a string question, and ids are unique per
question (else the payload is invalid: 422, logged).
A card's `preview` is a file under <project>/.aid-ui/studio/; until it exists
GET /preview answers 404 and the page shows the pending slot.

Answers live in this process's memory only (the confirm-store rule: never read
back from a file the agent can write). A restart forgets an unrecorded answer and
its question is open again.

Routes (every request must pass ours(): Host is this server; Origin/Referer, when
sent, name the same origin; else 403. GET / alone checks only the Host: the PM opens
the link from another app, whose Referer is foreign):
  GET  /?k=<code>             the one-time PM link: a k equal to <token dir>/studio.code
                              (written by aid-ui-serve.sh, removed here on use) sets
                              an HttpOnly SameSite=Strict session cookie and redirects
                              to /; a used or wrong code gets the no-access page, which reloads /
                              same-site once (a signed-in PM clicking the link again from another
                              app gets the studio: the Strict cookie is sent only on that reload)
  GET  /                      studio.html with a session cookie; without one a page
                              "Otevřete odkaz ze zprávy agenta" (no token, no state)
  GET  /state                 [auth] payload + per-question `answered` and, when answered,
                              `answer` = {decision, choice, choice_title, comment}; `project` =
                              the project directory's name (the page header)
  GET  /preview?question=&card=  the card's preview file, 404 while pending
  GET  /report                <project>/docs/design/soulad-se-standardy.md, escaped
  GET  /licence               Impeccable NOTICE (the page pattern's source)
  GET  /history               [auth] every answered question as the studio showed it: the question,
                              its cards (previews copied aside) and the answer, oldest first, from
                              <project>/.aid-ui/studio/history.jsonl (display only; decisions stay the
                              in-memory answers above)
  GET  /history/preview?question=&card=  a card preview kept with the history
  GET  /brand/<file>          [auth] the project's brand page (<project>/docs/brand/): index.html,
                              top-level *.css, assets/ and fonts/ only (what aid-ui-serve.sh brand
                              serves), no scripts (CSP); the studio's "Značka a produkt" link
  POST /answer                [auth] JSON {question, kind, target, decision,
                              choice, comment}; kind and target must be the open
                              question's own (a stale page gets 409).
                              200 recorded; 409 = question closed, superseded
                              (not in the payload), not yet open (opened_at in the
                              future) or already answered; 422 = malformed answer.
  GET  /answer?question=<id>  [auth] {question, kind, target, decision,
                              choice, comment, at, cards, cards_sha256}, only for an answer given after
                              the question's current opened_at with its current
                              kind and target; a re-roll adds `next_question`.
                              404 unknown or unanswered.
`cards` = the question's cards as served when the answer was accepted,
[{id, title, url, thesis, preview, palette, risk, uniqueness, preview_sha256 (of the
preview file then, null while pending)}] sorted by id (a missing field is null), held in memory
with the answer; `cards_sha256` = sha256 of their JSON with keys sorted, no
whitespace. Editing payload.json afterwards never changes them.
A re-roll (reroll|reroll_safer|reroll_bolder, steer text in `comment`) closes its
question and opens a new one in memory: id `<base>.r<n+1>`, same kind and target,
opened_at now; the agent lists that id in the payload with the new cards.
[auth] = the X-AID-Token header (the agent) or the session cookie (the PM's page).
Neither: 403 {"error": "token"}.
"""
import argparse, hashlib, hmac, html, json, os, re, secrets, sys, threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

KINDS = {"variant", "vision", "identity", "seo_brief", "structure", "task_map",
         "content_plan", "defer_content", "facts", "references", "direction",
         "approve_page", "exception", "coverage_drift", "design_standard", "handover"}
# Card fields the page shows (a step may turn any into state); snapshotted with the answer.
CARD_FIELDS = ("id", "title", "url", "thesis", "preview", "palette", "risk", "uniqueness")
DECISIONS = {"approve", "choose", "return", "reroll", "reroll_safer", "reroll_bolder"}
# Previews are raster images only: an .html/.svg preview would run script on this origin.
IMAGES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
          ".webp": "image/webp", ".gif": "image/gif", ".avif": "image/avif"}
BRAND_TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
               ".svg": "image/svg+xml", ".woff2": "font/woff2", ".woff": "font/woff",
               ".ico": "image/x-icon", **IMAGES}
HERE = os.path.dirname(os.path.abspath(__file__))
NOTICE = os.path.join(HERE, "..", "..", "skills", "ui-design", "references",
                      "LICENSES", "NOTICE-impeccable.txt")

ap = argparse.ArgumentParser()
for a in ("--project", "--host", "--port", "--token-file"):
    ap.add_argument(a, required=True)
args = ap.parse_args()
PORT = int(args.port)
PROJECT = os.path.realpath(args.project)
STUDIO = os.path.join(PROJECT, ".aid-ui", "studio")
CODE_FILE = os.path.join(os.path.dirname(os.path.abspath(args.token_file)), "studio.code")
with open(args.token_file) as f:
    TOKEN = f.read().strip()
if not re.fullmatch(r"[A-Za-z0-9]{16,}", TOKEN):
    sys.exit("server.py: token file must hold at least 16 alphanumeric characters")
OWN = {"%s:%d" % (h, PORT) for h in (args.host, "127.0.0.1", "localhost")}

ANSWERS = {}   # question id -> answer dict
REROLLED = {}  # question id opened by a re-roll -> question dict (until restart)
SESSIONS = set()  # session cookie values handed out through a one-time code
LOCK = threading.Lock()
NO_ACCESS = ('<!doctype html><meta charset="utf-8"><meta name="viewport" '
             'content="width=device-width,initial-scale=1"><title>Studio</title>'
             '<p style="font:18px/1.5 system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem">'
             'Otevřete odkaz ze zprávy agenta.</p>')
# A used or wrong code: the same page, but it reloads "/" once from this origin. A click from
# another app (chat, editor) is cross-site, so the SameSite=Strict cookie of a PM who is already
# signed in was not sent; the same-site reload sends it. Without a cookie "/" is NO_ACCESS (no loop).
USED_CODE = NO_ACCESS.replace('<title>', '<meta http-equiv="refresh" content="0;url=/"><title>', 1)


def take_code(k):
    """True once for the code in CODE_FILE; the file is removed on use."""
    with LOCK:
        try:
            with open(CODE_FILE) as f:
                code = f.read().strip()
        except OSError:
            return False
        if not (k and code and hmac.compare_digest(k, code)):
            return False
        os.remove(CODE_FILE)
        return True


def now():
    return datetime.now(timezone.utc)


def iso(t):
    return t.isoformat(timespec="microseconds").replace("+00:00", "Z")


def parse_time(s):
    t = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def load():
    """Payload with in-memory re-roll questions merged in; raises ValueError."""
    try:
        with open(os.path.join(STUDIO, "payload.json")) as f:
            p = json.load(f)
    except FileNotFoundError:
        p = {}
    except (OSError, json.JSONDecodeError) as e:
        raise ValueError("payload.json: %s" % e)
    if not isinstance(p, dict):
        raise ValueError("payload.json: top level must be an object")
    steps, qs, cards = p.get("steps", []), p.get("questions", []), p.get("cards", [])
    if not all(isinstance(x, list) for x in (steps, qs, cards)):
        raise ValueError("payload.json: steps, questions and cards must be arrays")
    seen = set()
    for q in qs:
        if not isinstance(q, dict) or not isinstance(q.get("id"), str) or not q["id"]:
            raise ValueError("payload.json: every question needs a string id")
        if q["id"] in seen:
            raise ValueError("payload.json: question id %s twice" % q["id"])
        seen.add(q["id"])
        if q.get("kind") not in KINDS:
            raise ValueError("payload.json: question %s has unknown kind %r" % (q["id"], q.get("kind")))
        if "target" not in q:
            raise ValueError("payload.json: question %s has no target" % q["id"])
        try:
            parse_time(q.get("opened_at"))
        except (TypeError, ValueError):
            raise ValueError("payload.json: question %s has no valid opened_at" % q["id"])
    shown = set()  # (question, card id): a choice names exactly one card the PM saw
    for c in cards:
        if not (isinstance(c, dict) and isinstance(c.get("id"), str) and c["id"]
                and isinstance(c.get("question"), str)):
            raise ValueError("payload.json: every card needs a non-empty string id and a string question")
        if (c["question"], c["id"]) in shown:
            raise ValueError("payload.json: card id %s twice in question %s" % (c["id"], c["question"]))
        shown.add((c["question"], c["id"]))
    ov = p.get("overview")
    if ov is not None:   # the web at a glance, kept by the agent (see the header)
        if not isinstance(ov, dict):
            raise ValueError("payload.json: overview must be an object")
        u = ov.get("site_url")
        if u is not None and not (isinstance(u, str) and re.match(r"https?://[^\s\"'<>]+$", u)):
            raise ValueError("payload.json: overview.site_url must be an http(s) address")
        todo = ov.get("todo", [])
        if not isinstance(todo, list) or not all(
                isinstance(t, dict) and isinstance(t.get("what"), str) and t["what"].strip()
                and isinstance(t.get("how", ""), str) and isinstance(t.get("blocking", False), bool)
                and isinstance(t.get("question", ""), str) for t in todo):
            raise ValueError("payload.json: overview.todo must be a list of {what, how, blocking, question} with a non-empty what")
    with LOCK:
        qs = qs + [dict(q) for i, q in REROLLED.items() if i not in seen]
    return {"now": p.get("now"), "steps": steps, "questions": qs, "cards": cards, "overview": ov}


def valid_answer(q):
    """The stored answer to q if it was given for q as it stands now."""
    a = ANSWERS.get(q["id"])
    if a and a["kind"] == q["kind"] and a["target"] == q["target"] \
            and parse_time(a["at"]) > parse_time(q["opened_at"]):
        return a
    return None


def preview_sha(c):
    """sha256 of the card's preview file as served now, None while pending."""
    f = os.path.realpath(os.path.join(STUDIO, str(c.get("preview") or "")))
    if not (c.get("preview") and f.startswith(STUDIO + os.sep) and os.path.isfile(f)):
        return None
    with open(f, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


HISTORY = os.path.join(STUDIO, "history.jsonl")
HISTORY_DIR = os.path.join(STUDIO, "history")
SAFE = re.compile(r"[^A-Za-z0-9._-]+")


def keep_history(q, cards, answer, steps):
    """Append the answered question as shown (question, full cards, answer, current step) to
    history.jsonl; each raster preview is copied under history/<question>/ so a later payload
    or preview change does not alter what the PM saw. Display only, never read as a decision."""
    qdir = os.path.join(HISTORY_DIR, SAFE.sub("_", q["id"]))
    kept = []
    for c in cards:
        c = dict(c)
        src = os.path.realpath(os.path.join(STUDIO, str(c.get("preview") or "")))
        ext = os.path.splitext(src)[1].lower()
        if c.get("preview") and src.startswith(STUDIO + os.sep) and os.path.isfile(src) and ext in IMAGES:
            os.makedirs(qdir, exist_ok=True)
            dst = os.path.join(qdir, SAFE.sub("_", str(c.get("id"))) + ext)
            with open(src, "rb") as fi, open(dst, "wb") as fo:
                fo.write(fi.read())
            c["preview"] = os.path.relpath(dst, STUDIO)
        else:
            c["preview"] = None
        kept.append(c)
    cur = next((x for x in steps or [] if isinstance(x, dict) and x.get("status") == "current"), None)
    entry = {"question": {k: v for k, v in q.items() if k not in ("answered", "answer")},
             "cards": kept, "step": (cur or {}).get("title"),
             "answer": {k: answer.get(k) for k in ("decision", "choice", "comment", "at")}}
    with open(HISTORY, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def read_history():
    try:
        with open(HISTORY, encoding="utf-8") as fh:
            return [json.loads(l) for l in fh if l.strip()]
    except (OSError, ValueError):
        return []


def next_id(qid):
    m = re.fullmatch(r"(.*)\.r(\d+)", qid)
    return "%s.r%d" % (m.group(1), int(m.group(2)) + 1) if m else qid + ".r1"


class Studio(BaseHTTPRequestHandler):
    def ours(self, nav=False):   # Host is us; Origin/Referer, when sent, name the same origin
        h = self.headers.get("Host")
        if nav:   # opening the page (GET /, the link from the chat): a click from another app
            return h in OWN   # carries its Referer; only the Host (DNS rebinding) is checked
        o, r = self.headers.get("Origin"), self.headers.get("Referer")
        return (h in OWN and (o is None or o == "http://" + h)
                and (r is None or r == "http://" + h or r.startswith("http://" + h + "/")))

    def send(self, code, body, ctype="application/json; charset=utf-8", csp="frame-ancestors 'none'"):
        if not isinstance(body, bytes):
            body = (json.dumps(body, ensure_ascii=False) if ctype.startswith("application/json")
                    else body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", csp)
        self.end_headers()
        self.wfile.write(body)

    def session(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "aid_studio" and v in SESSIONS:
                return True
        return False

    def authed(self):
        return hmac.compare_digest(self.headers.get("X-AID-Token") or "", TOKEN) or self.session()

    def gate(self, token, nav=False):
        if not self.ours(nav):
            self.send(403, {"error": "request not addressed to this studio"})
            return False
        if token and not self.authed():
            self.send(403, {"error": "token"})
            return False
        return True

    def payload(self):
        try:
            return load()
        except ValueError as e:
            self.log_message("invalid payload: %s", e)
            self.send(422, {"error": str(e)})
            return None

    def do_GET(self):
        u = urlsplit(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        if u.path == "/":
            if not self.gate(False, nav=True):
                return
            if "k" in q:
                if not take_code(q["k"]):
                    self.send(403, USED_CODE, "text/html; charset=utf-8")
                    return
                sid = secrets.token_hex(32)
                with LOCK:
                    SESSIONS.add(sid)
                self.send_response(303)
                self.send_header("Location", "/")
                self.send_header("Set-Cookie", "aid_studio=%s; HttpOnly; SameSite=Strict; Path=/" % sid)
                self.send_header("Content-Length", "0")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            if not self.session():
                self.send(403, NO_ACCESS, "text/html; charset=utf-8")
                return
            with open(os.path.join(HERE, "studio.html"), encoding="utf-8") as f:
                self.send(200, f.read(), "text/html; charset=utf-8")
        elif u.path == "/state":
            if not self.gate(True) or (p := self.payload()) is None:
                return
            with LOCK:
                for x in p["questions"]:
                    a = valid_answer(x)
                    x["answered"] = a is not None
                    if a:   # what the PM decided, for the page's confirmation
                        x["answer"] = {"decision": a["decision"], "choice": a["choice"], "comment": a["comment"],
                                       "choice_title": next((c["title"] for c in a["cards"]
                                                             if c["id"] == a["choice"]), None)}
            p["project"] = os.path.basename(PROJECT)
            self.send(200, p)
        elif u.path == "/answer":
            if not self.gate(True) or (p := self.payload()) is None:
                return
            qid = q.get("question", "")
            cur = next((x for x in p["questions"] if x["id"] == qid), None)
            with LOCK:
                # A question no longer listed keeps the answer it was given.
                a = valid_answer(cur) if cur else ANSWERS.get(qid)
            self.send(200, a) if a else self.send(404, {"error": "no answer to %s" % qid})
        elif u.path == "/preview":
            if not self.gate(False) or (p := self.payload()) is None:
                return
            c = next((c for c in p["cards"] if isinstance(c, dict) and c.get("question") == q.get("question")
                      and c.get("id") == q.get("card")), None)
            f = os.path.realpath(os.path.join(STUDIO, str((c or {}).get("preview") or "")))
            if not c or not f.startswith(STUDIO + os.sep) or not os.path.isfile(f):
                self.send(404, {"error": "preview pending"})
                return
            ctype = IMAGES.get(os.path.splitext(f)[1].lower())
            if not ctype:
                self.send(415, {"error": "a preview must be a png, jpeg, webp, gif or avif image"})
                return
            with open(f, "rb") as fh:
                self.send(200, fh.read(), ctype, "sandbox; default-src 'none'; frame-ancestors 'none'")
        elif u.path == "/history":
            if not self.gate(True):
                return
            self.send(200, read_history())
        elif u.path == "/history/preview":
            if not self.gate(True):
                return
            e = next((h for h in read_history() if h.get("question", {}).get("id") == q.get("question")), None)
            c = next((c for c in (e or {}).get("cards") or [] if c.get("id") == q.get("card")), None)
            f = os.path.realpath(os.path.join(STUDIO, str((c or {}).get("preview") or "")))
            ctype = IMAGES.get(os.path.splitext(f)[1].lower())
            if not c or not f.startswith(HISTORY_DIR + os.sep) or not ctype or not os.path.isfile(f):
                self.send(404, {"error": "no such preview"})
                return
            with open(f, "rb") as fh:
                self.send(200, fh.read(), ctype, "sandbox; default-src 'none'; frame-ancestors 'none'")
        elif u.path == "/brand" or u.path.startswith("/brand/"):
            if not self.gate(True):
                return
            if u.path == "/brand":
                self.send_response(303)
                self.send_header("Location", "/brand/")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            rel = u.path[len("/brand/"):] or "index.html"
            root = os.path.realpath(os.path.join(PROJECT, "docs", "brand"))
            f = os.path.realpath(os.path.join(root, rel))
            parts = os.path.relpath(f, root).split(os.sep)
            allowed = (f.startswith(root + os.sep) and not any(x.startswith(".") for x in parts)
                       and (parts == ["index.html"] or (len(parts) == 1 and f.endswith(".css"))
                            or (len(parts) > 1 and parts[0] in ("assets", "fonts"))))
            ctype = BRAND_TYPES.get(os.path.splitext(f)[1].lower())
            if not allowed or not ctype or not os.path.isfile(f):
                self.send(404, {"error": "not found"})
                return
            with open(f, "rb") as fh:
                data = fh.read()
            if parts == ["index.html"]:   # the studio's tab bar; the page itself stays client-clean
                data = data.replace(b"<body>", b'<body><nav class="studio-tabs" aria-label="Studio">'
                                    b'<a href="/">Studio</a><a href="/brand/" aria-current="page">'
                                    b'Zna\xc4\x8dka a produkt</a></nav>', 1)
            self.send(200, data, ctype, "default-src 'none'; style-src 'self' 'unsafe-inline'; "
                      "img-src 'self' data:; font-src 'self'; frame-ancestors 'none'")
        elif u.path in ("/report", "/licence"):
            if not self.gate(False):
                return
            f = os.path.join(PROJECT, "docs", "design", "soulad-se-standardy.md") if u.path == "/report" else NOTICE
            try:
                with open(f, encoding="utf-8") as fh:
                    text = fh.read()
            except OSError:
                self.send(404, {"error": "%s not found" % os.path.basename(f)})
                return
            # ponytail: <pre>, no markdown rendering; a heading/table renderer if the PM wants it.
            self.send(200, '<!doctype html><meta charset="utf-8"><meta name="viewport" '
                      'content="width=device-width,initial-scale=1"><title>%s</title>'
                      '<pre style="white-space:pre-wrap;font:14px/1.5 ui-monospace,monospace;'
                      'max-width:60rem;margin:2rem auto;padding:0 1rem">%s</pre>'
                      % (html.escape(os.path.basename(f)), html.escape(text)), "text/html; charset=utf-8")
        else:
            self.send(404, {"error": "not found"})

    def do_POST(self):
        if urlsplit(self.path).path != "/answer":
            self.send(404, {"error": "not found"})
            return
        if not self.gate(True) or (p := self.payload()) is None:
            return
        try:
            b = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
        except (ValueError, json.JSONDecodeError):
            b = None
        if not isinstance(b, dict) or b.get("decision") not in DECISIONS:
            self.send(422, {"error": "answer needs a decision: " + ", ".join(sorted(DECISIONS))})
            return
        qid = b.get("question")
        cur = next((x for x in p["questions"] if x["id"] == qid), None)
        if cur is None:
            self.send(409, {"error": "question %s is closed or superseded" % qid})
            return
        if b.get("kind") != cur["kind"] or b.get("target") != cur["target"]:
            self.send(409, {"error": "question %s changed; reload the page" % qid})
            return
        t = now()
        if t <= parse_time(cur["opened_at"]):
            self.send(409, {"error": "question %s is not open yet" % qid})
            return
        d, choice, comment = b["decision"], b.get("choice"), str(b.get("comment") or "").strip()
        if d == "choose" and not any(isinstance(c, dict) and c.get("question") == qid
                                     and c.get("id") == choice for c in p["cards"]):
            self.send(422, {"error": "choose needs the id of one of this question's cards"})
            return
        if d == "return" and not comment:
            self.send(422, {"error": "return needs a comment"})
            return
        with LOCK:
            if valid_answer(cur):
                self.send(409, {"error": "question %s is already answered" % qid})
                return
            # The cards as this server shows them now, kept in memory with the answer: a
            # later payload.json edit cannot change what the PM's choice refers to.
            cards = sorted((dict({k: c.get(k) for k in CARD_FIELDS}, preview_sha256=preview_sha(c))
                            for c in p["cards"] if c.get("question") == qid), key=lambda c: c["id"])
            a = {"question": qid, "kind": cur["kind"], "target": cur["target"], "decision": d,
                 "choice": choice if d == "choose" else None, "comment": comment, "at": iso(t),
                 "cards": cards, "cards_sha256": hashlib.sha256(json.dumps(
                     cards, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()}
            if d.startswith("reroll"):
                n = next_id(qid)
                a["next_question"] = n
                REROLLED[n] = {"id": n, "kind": cur["kind"], "target": cur["target"],
                               "opened_at": iso(t), "title": cur.get("title"),
                               "prompt": cur.get("prompt"), "rerolled_from": qid}
            ANSWERS[qid] = a
            try:
                keep_history(cur, [c for c in p["cards"] if isinstance(c, dict) and c.get("question") == qid], a, p.get("steps"))
            except OSError as e:   # the history is a record for the PM, never a reason to lose the answer
                self.log_message("history not written: %s", e)
        self.log_message("answer %s: %s", qid, d)
        self.send(200, a)


ThreadingHTTPServer((args.host, PORT), Studio).serve_forever()
