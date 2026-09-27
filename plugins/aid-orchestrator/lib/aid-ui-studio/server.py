#!/usr/bin/env python3
"""aid-ui studio server (P103 Step 3): the one page where the PM makes every
/aid-ui choice and approval. Python stdlib only.

usage: server.py --project <dir> --host <h> --port <p> --token-file <path>

Payload: <project>/.aid-ui/studio/payload.json, written by the agent and re-read
on every request, so the agent opens a round by rewriting it:
  {"steps":     [{"id", "title", "status": "done|current|todo"}],
   "questions": [{"id", "kind", "target", "opened_at": ISO-8601, "title", "prompt", "body"}],
   "cards":     [{"id", "question", "title", "preview", "thesis", "palette": [css colours],
                  "risk", "uniqueness"}]}
A card's `preview` is a file under <project>/.aid-ui/studio/; until it exists
GET /preview answers 404 and the page shows the pending slot.

Answers live in this process's memory only (the confirm-store rule: never read
back from a file the agent can write). A restart forgets an unrecorded answer and
its question is open again.

Routes (every request must pass ours(): Host is this server; Origin/Referer, when
sent, name the same origin; else 403):
  GET  /                      studio.html with the session token embedded
  GET  /state                 [X-AID-Token] payload + per-question `answered`
  GET  /preview?question=&card=  the card's preview file, 404 while pending
  GET  /report                <project>/docs/design/soulad-se-standardy.md, escaped
  GET  /licence               Impeccable NOTICE (the page pattern's source)
  POST /answer                [X-AID-Token] JSON {question, kind, target, decision,
                              choice, comment}; kind and target must be the open
                              question's own (a stale page gets 409).
                              200 recorded; 409 = question closed, superseded
                              (not in the payload), not yet open (opened_at in the
                              future) or already answered; 422 = malformed answer.
  GET  /answer?question=<id>  [X-AID-Token] {question, kind, target, decision,
                              choice, comment, at}, only for an answer given after
                              the question's current opened_at with its current
                              kind and target; a re-roll adds `next_question`.
                              404 unknown or unanswered.
A re-roll (reroll_safer|reroll_bolder, steer text in `comment`) closes its
question and opens a new one in memory: id `<base>.r<n+1>`, same kind and target,
opened_at now; the agent lists that id in the payload with the new cards.
Missing or wrong token: 403 {"error": "token"}.
"""
import argparse, html, json, os, re, sys, threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

KINDS = {"variant", "vision", "identity", "seo_brief", "structure", "task_map",
         "content_plan", "defer_content", "facts", "references", "direction",
         "approve_page", "exception", "coverage_drift", "design_standard"}
DECISIONS = {"approve", "choose", "return", "reroll_safer", "reroll_bolder"}
# Previews are raster images only: an .html/.svg preview would run script on this origin.
IMAGES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
          ".webp": "image/webp", ".gif": "image/gif", ".avif": "image/avif"}
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
with open(args.token_file) as f:
    TOKEN = f.read().strip()
if not re.fullmatch(r"[A-Za-z0-9]{16,}", TOKEN):
    sys.exit("server.py: token file must hold at least 16 alphanumeric characters")
OWN = {"%s:%d" % (h, PORT) for h in (args.host, "127.0.0.1", "localhost")}

ANSWERS = {}   # question id -> answer dict
REROLLED = {}  # question id opened by a re-roll -> question dict (until restart)
LOCK = threading.Lock()


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
    with LOCK:
        qs = qs + [dict(q) for i, q in REROLLED.items() if i not in seen]
    return {"steps": steps, "questions": qs, "cards": cards}


def valid_answer(q):
    """The stored answer to q if it was given for q as it stands now."""
    a = ANSWERS.get(q["id"])
    if a and a["kind"] == q["kind"] and a["target"] == q["target"] \
            and parse_time(a["at"]) > parse_time(q["opened_at"]):
        return a
    return None


def next_id(qid):
    m = re.fullmatch(r"(.*)\.r(\d+)", qid)
    return "%s.r%d" % (m.group(1), int(m.group(2)) + 1) if m else qid + ".r1"


class Studio(BaseHTTPRequestHandler):
    def ours(self):   # Host is us; Origin/Referer, when sent, name the same origin
        h = self.headers.get("Host")
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

    def gate(self, token):
        if not self.ours():
            self.send(403, {"error": "request not addressed to this studio"})
            return False
        if token and self.headers.get("X-AID-Token") != TOKEN:
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
            if not self.gate(False):
                return
            with open(os.path.join(HERE, "studio.html"), encoding="utf-8") as f:
                self.send(200, f.read().replace("__AID_TOKEN__", TOKEN), "text/html; charset=utf-8")
        elif u.path == "/state":
            if not self.gate(True) or (p := self.payload()) is None:
                return
            with LOCK:
                for x in p["questions"]:
                    x["answered"] = valid_answer(x) is not None
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
            a = {"question": qid, "kind": cur["kind"], "target": cur["target"], "decision": d,
                 "choice": choice if d == "choose" else None, "comment": comment, "at": iso(t)}
            if d.startswith("reroll_"):
                n = next_id(qid)
                a["next_question"] = n
                REROLLED[n] = {"id": n, "kind": cur["kind"], "target": cur["target"],
                               "opened_at": iso(t), "title": cur.get("title"),
                               "prompt": cur.get("prompt"), "rerolled_from": qid}
            ANSWERS[qid] = a
        self.log_message("answer %s: %s", qid, d)
        self.send(200, a)


ThreadingHTTPServer((args.host, PORT), Studio).serve_forever()
