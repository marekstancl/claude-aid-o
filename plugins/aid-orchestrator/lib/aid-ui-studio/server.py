#!/usr/bin/env python3
"""aid-ui studio server (P103 Step 3): the one page where the PM makes every
/aid-ui choice and approval. Python stdlib only.

usage: server.py --project <dir> --host <h> --port <p> --token-file <path>

Payload: <project>/.aid-ui/studio/payload.json, written by the agent and re-read
on every request, so the agent opens a round by rewriting it:
  {"now":       {"title", "text", "at"}   (what the agent is doing right now; optional; the page shows
                it only while `at` is newer than the PM's last answer),
   "steps":     [{"id", "title", "status": "done|current|todo", "description"}],
   "questions": [{"id", "kind", "part" (id from skills/ui-design/sections.json; required for facts and for
                  a kind several parts share, else derived), "target", "opened_at": ISO-8601, "title", "prompt", "body",
                  "next" (what the agent does after approval), "eyebrow" (heading override)}],
   "cards":     [{"id", "question", "title", "preview", "thesis", "palette": [css colours],
                  "risk", "uniqueness", "url", "source" (key of sections.json sources)}]}
POST /change {question} [auth]: the PM changes an answered question still listed in the payload (an
answer held now, or "done": true set by the agent - display only, it decides nothing: the change only opens
the same question again for the PM; a question no longer in the payload cannot be changed): a new open question <root>.c<n> with the same kind, target, part, text and card copies,
held in memory like a re-roll; a second change of the same root while one is open -> 409. /state marks
the original with "changed_to" and answers carry "at".
A facts question needs at least 3 cards, each with a source from the map (first = recommended).
/state also returns "sections": the map's six steps and their parts with a status each (skipped,
current, done, waiting) computed from docs/design/brand-state.json and the open questions; the
server refuses to start when the map is malformed.
A question may also carry "outcome": the decision in one sentence (a string of at most 120
characters, else the payload is invalid), kept in the history line of its answer.
Every card has a non-empty string id and a string question, and ids are unique per
question (else the payload is invalid: 422, logged).
A card's `preview` is a file under <project>/.aid-ui/studio/; until it exists
GET /preview answers 404 and the page shows the pending slot.

Answers live in this process's memory and, after a restart, come back from the studio's own
history.jsonl (the entries this server wrote, latest by `at`) - never from the state script's files
(the confirm-store rule: never read
back from a file the agent can write). A restart forgets an unrecorded answer and
its question is open again.

Routes (every request must pass ours(): Host is this server; Origin/Referer, when
sent, name the same origin; else 403. GET / alone checks only the Host: the PM opens
the link from another app, whose Referer is foreign):
  GET  /?k=<code>             the one-time PM link: a k equal to <token dir>/studio.code (kept, not
                              removed, once .aid-ui/finish.json exists: the finished run is revisited)
                              (written by aid-ui-serve.sh, removed here on use) sets
                              an HttpOnly SameSite=Strict session cookie and redirects
                              to /; a used or wrong code gets the no-access page, which reloads /
                              same-site once (a signed-in PM clicking the link again from another
                              app gets the studio: the Strict cookie is sent only on that reload)
  GET  /                      studio.html with a session cookie; without one a page
                              "Otevřete odkaz ze zprávy agenta" (no token, no state)
  GET  /state                 [auth] payload + per-question `answered` and, when answered,
                              `answer` = {decision, choice, choice_title, comment}; `project` =
                              the project directory's name (the page header); `history_lines` =
                              the lines of history.jsonl now (the page refetches
                              /history when it changes)
  GET  /preview?question=&card=[&n=2]  the card's preview file (n=2: its preview2, the contexts), 404 while pending
  GET  /report                <project>/docs/design/soulad-se-standardy.md, escaped
  GET  /licence               Impeccable NOTICE (the page pattern's source)
  GET  /history               [auth] the lines of <project>/.aid-ui/studio/history.jsonl in file order:
                              every answered question as the studio showed it ({by: "pm", question,
                              cards (previews copied aside), step, answer}) and every decision the
                              agent recorded with `aid-ui-state.sh decide` ({by: "agent", step,
                              event, cards: [], answer: {decision: "decided", at}}); a line that is
                              not JSON is skipped (and still counted in /state history_lines).
                              Display only; decisions stay the in-memory answers above
  GET  /history/preview?question=&card=  a card preview kept with the history
  GET  /brand/<file>          [auth] the project's brand page (<project>/docs/brand/): index.html,
                              top-level *.css, assets/ and fonts/ only (what aid-ui-serve.sh brand
                              serves), no scripts (CSP); the studio's "Značka a produkt" link
  POST /open-item             [auth] JSON {text}: the PM's own open point -> history.jsonl (by pm,
                              kind open_item); aid-ui-state.sh open-items-sync takes it into the state
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
import argparse, fcntl, hashlib, hmac, html, json, os, re, secrets, sys, threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

KINDS = {"variant", "vision", "identity", "seo_brief", "structure", "task_map",
         "content_plan", "defer_content", "facts", "references", "direction",
         "approve_page", "exception", "coverage_drift", "design_standard", "handover", "notifications",
         "sources", "product_context", "copy_verdict", "no_method", "launch_inputs", "photos"}   # launch_inputs: P113a step 7
# Card fields the page shows (a step may turn any into state); snapshotted with the answer.
CARD_FIELDS = ("id", "title", "url", "thesis", "preview", "preview2", "preview2_label", "palette", "risk", "uniqueness", "value", "method", "slot", "honours")
# A question that builds on what the PM chose earlier carries that choice and the PM's words (`prior`), and every
# card says how it honours them (`honours`) - the studio checks both against the recorded answer (PM 9. 10. 2026:
# the chosen reference and "I like its animations" were dropped by the next step).
PRIOR = {"direction": "references"}
STEP_METHODS = {"build"}   # P108: the build has a method and a receipt (aid-ui-state.sh build-record), no question
RECEIPT_AGE = 12 * 3600   # a method receipt serves questions opened within this many seconds after it
STANDARDS = "/opt/eco/docs/docs/ecosystem/"   # the only place a method file may live outside the plugin (read live)
WAIVERS = ("pm", "without")   # no_method card values that let the kind be asked without a method
DECISIONS = {"approve", "choose", "return", "reroll", "reroll_safer", "reroll_bolder"}
# Previews are raster images only: an .html/.svg preview would run script on this origin.
IMAGES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
          ".webp": "image/webp", ".gif": "image/gif", ".avif": "image/avif"}
BRAND_TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
               ".svg": "image/svg+xml", ".woff2": "font/woff2", ".woff": "font/woff",
               ".ico": "image/x-icon", **IMAGES}
HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.normpath(os.path.join(HERE, "..", ".."))
NOTICE = os.path.join(HERE, "..", "..", "skills", "ui-design", "references",
                      "LICENSES", "NOTICE-impeccable.txt")

ap = argparse.ArgumentParser()
ap.add_argument("--check", action="store_true", help="only validate <project>/.aid-ui/studio/payload.json as load() does, then exit")
for a in ("--project", "--host", "--port", "--token-file"):
    ap.add_argument(a)
args = ap.parse_args()
if not args.project or not (args.check or (args.host and args.port and args.token_file)):
    ap.error("--project, --host, --port and --token-file are required (--check needs only --project)")
PORT = int(args.port or 0)
PROJECT = os.path.realpath(args.project)
STUDIO = os.path.join(PROJECT, ".aid-ui", "studio")
TOKEN = CODE_FILE = None
if not args.check:
    CODE_FILE = os.path.join(os.path.dirname(os.path.abspath(args.token_file)), "studio.code")
    with open(args.token_file) as f:
        TOKEN = f.read().strip()
    if not re.fullmatch(r"[A-Za-z0-9]{16,}", TOKEN):
        sys.exit("server.py: token file must hold at least 16 alphanumeric characters")
OWN = {"%s:%d" % (h, PORT) for h in (args.host, "127.0.0.1", "localhost")}

ANSWERS = {}   # question id -> answer dict
REROLLED = {}  # question id opened by a re-roll -> question dict (until restart)
CHANGED = {}   # question id opened by the PM's "Změnit" -> question dict (until restart)
CHANGED_CARDS = {}   # that question id -> copies of the original question's cards
SESSIONS = set()  # session cookie values handed out through a one-time code
LOCK = threading.Lock()
NO_ACCESS = ('<!doctype html><meta charset="utf-8"><meta name="viewport" '
             'content="width=device-width,initial-scale=1"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><title>Studio</title>'
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
        # after finish the PM comes back to Hotovo as often as he likes: the code stays (PM 11. 10. 2026)
        if not os.path.isfile(os.path.join(PROJECT, ".aid-ui", "finish.json")):
            os.remove(CODE_FILE)
        return True


def now():
    return datetime.now(timezone.utc)


def iso(t):
    return t.isoformat(timespec="microseconds").replace("+00:00", "Z")


def parse_time(s):
    t = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def load_sections():
    """The map of steps and parts (skills/ui-design/sections.json), checked once at start."""
    path = os.path.join(HERE, "..", "..", "skills", "ui-design", "sections.json")
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    parts, kinds = {}, set()
    if not isinstance(m.get("steps"), list) or len(m["steps"]) != 6:
        raise ValueError("steps must be the six studio steps")

    def done_ok(c):
        if not isinstance(c, dict) or len(c) != 1:
            return False
        (k, v), = c.items()
        if k == "all":
            return isinstance(v, list) and bool(v) and all(done_ok(x) for x in v)
        return k in ("state", "chapter", "answer") and isinstance(v, str) and bool(v)
    for n, st in enumerate(m["steps"], 1):
        if st.get("n") != n or not all(isinstance(st.get(k), str) and st[k] for k in ("title", "why", "goal", "feeds")):
            raise ValueError("step %d needs n=%d, title, why, goal and feeds" % (n, n))
        if not isinstance(st.get("parts"), list) or not st["parts"]:
            raise ValueError("step %d has no parts" % n)
        for p in st["parts"]:
            if not all(isinstance(p.get(k), str) and p[k] for k in ("id", "title", "why", "goal", "feeds", "you")):
                raise ValueError("a part of step %d needs id, title, why, goal, feeds and you" % n)
            if p["id"] in parts or not isinstance(p.get("kinds"), list) or not done_ok(p.get("done")):
                raise ValueError("part %s: duplicate id, no kinds list, or done not one of state|chapter|answer|all" % p["id"])
            if [k for k in p["kinds"] if k not in KINDS]:
                raise ValueError("part %s: unknown kinds %s" % (p["id"], [k for k in p["kinds"] if k not in KINDS]))
            if not (isinstance(p.get("files"), list) and p["files"] and all(isinstance(x, str) and x for x in p["files"])):
                raise ValueError("part %s: files must name the step files" % p["id"])
            if n == 6 and not (isinstance(p.get("section"), str) and p["section"]):
                raise ValueError("part %s: a part of step 6 names its section of 7-verify.md" % p["id"])
            if p.get("when") not in (None, "options.vision", "options.identity", "options.seo"):
                raise ValueError("part %s: unknown when %r" % (p["id"], p["when"]))
            parts[p["id"]] = dict(p, step=n)
            kinds.update(p["kinds"])
    if KINDS - {"no_method"} - kinds:   # no_method is asked in whichever part lacks a method
        raise ValueError("kinds in no part: %s" % ", ".join(sorted(KINDS - {"no_method"} - kinds)))
    if not isinstance(m.get("sources"), dict) or not m["sources"] or \
            not all(isinstance(k, str) and k and isinstance(v, str) and v for k, v in m["sources"].items()):
        raise ValueError("sources must be a non-empty map of id to description")
    # the method before the output: every kind names the files the agent reads first, or null (no method)
    ms = m.get("methods")
    # STEP_METHODS: methods of steps that have no studio question (the build), read before the output too
    if not isinstance(ms, dict) or set(ms) != (KINDS - {"no_method"}) | STEP_METHODS:
        raise ValueError("methods must name every question kind but no_method, once (missing: %s, extra: %s)"
                         % (", ".join(sorted(KINDS - {"no_method"} - set(ms or {}))), ", ".join(sorted(set(ms or {}) - KINDS))))
    for k, v in ms.items():
        if v is None:
            continue
        if not (isinstance(v, dict) and set(v) == {"files", "receipt"} and isinstance(v["receipt"], bool)
                and isinstance(v["files"], list) and v["files"] and all(isinstance(x, str) and x for x in v["files"])):
            raise ValueError("methods.%s must be null or {files: [...], receipt: true|false}" % k)
        if len(set(v["files"])) != len(v["files"]):
            raise ValueError("methods.%s names a file twice" % k)
        for x in v["files"]:
            if x.startswith(STANDARDS):   # a standard read live: checked when read, not here
                if os.path.normpath(x) != x or os.path.islink(x) or (os.path.exists(x) and not os.path.isfile(x)):
                    raise ValueError("methods.%s: %s is not a plain file path" % (k, x))
                continue
            full = os.path.join(PLUGIN, x)
            if os.path.isabs(x) or os.path.normpath(x) != x or x.startswith("..") \
                    or os.path.islink(full) or not os.path.isfile(full) or not os.path.realpath(full).startswith(PLUGIN + os.sep):
                raise ValueError("methods.%s names a file that is not a plain file of the plugin: %s" % (k, x))
    return m, parts


try:
    SECTIONS, PARTS = load_sections()
except (OSError, ValueError, KeyError, TypeError) as e:
    sys.exit("ERROR: aid-ui studio: skills/ui-design/sections.json: %s" % e)


def part_of(q):
    """The question's part: its own `part`, or the one part its kind belongs to; raises ValueError."""
    if "part" in q:
        p = PARTS.get(q["part"])
        if not p:
            raise ValueError("question %s names unknown part %r" % (q["id"], q["part"]))
        if q["kind"] not in p["kinds"] and q["kind"] != "no_method":
            raise ValueError("question %s: kind %s does not belong to part %s" % (q["id"], q["kind"], q["part"]))
        return q["part"]
    owners = [i for i, p in PARTS.items() if q["kind"] in p["kinds"]]
    if len(owners) != 1:
        raise ValueError("question %s (kind %s) must name its part: one of %s" % (q["id"], q["kind"], ", ".join(owners) or "any"))
    return owners[0]


def method_sha(path):
    """sha256 of a method file: a plugin path, or an absolute one (a standard read live)."""
    with open(path if os.path.isabs(path) else os.path.join(PLUGIN, path), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def prior_answer(kind):
    """The latest recorded choose/approve answer of `kind` in the state: (question id, answer) or None."""
    best = None
    for qid, a in (read_state().get("answers") or {}).items():
        if isinstance(a, dict) and a.get("kind") == kind and a.get("decision") in ("choose", "approve") and a.get("at"):
            if best is None or str(a["at"]) > str(best[1]["at"]):
                best = (qid, a)
    return best


def check_prior(q, cards):
    """A `direction` question (PRIOR) must carry `prior` = {question, choice, comment} equal to the latest recorded
    references answer, and every card an `honours` text (1-300 chars) naming that choice. Without a recorded
    references answer nothing is required (a run that never asked for references). Done questions are not
    checked. Raises ValueError."""
    kind = PRIOR.get(q["kind"])
    if not kind or q.get("done") is True:
        return
    found = prior_answer(kind)
    who = "question %s (%s)" % (q["id"], q["kind"])
    if not found:
        held = [i for i, a in ANSWERS.items() if a.get("kind") == kind and a.get("decision") in ("choose", "approve")]
        if held:   # the PM answered the references question here, the state script has not recorded it yet
            raise ValueError("%s: the PM's %s answer %s is not recorded in the state yet; run aid-ui-state.sh record-answer first" % (who, kind, held[0]))
        return
    qid, a = found
    if not a.get("choice"):
        raise ValueError("%s: the recorded %s answer %s names no choice; a card question is expected there" % (who, kind, qid))
    want = {"question": qid, "choice": a.get("choice"), "comment": a.get("comment") or ""}
    if q.get("prior") != want:
        raise ValueError("%s: `prior` must repeat the PM's recorded %s answer exactly: %s" % (who, kind, json.dumps(want, ensure_ascii=False)))
    for c in cards:
        h = c.get("honours")
        if not (isinstance(h, str) and 0 < len(h) <= 300 and str(want["choice"]) in h):
            raise ValueError("%s: card %s needs `honours` (1-300 characters) saying how it honours the PM's choice %r%s"
                             % (who, c.get("id"), want["choice"], (" and the words %r" % want["comment"]) if want["comment"] else ""))


MOTION_KINDS = {"direction"}


def motion_module():
    """scripts/aid-ui-motion.py loaded as a module (summary_of, dirsha, sha_file)."""
    import importlib.util
    path = os.path.join(HERE, "..", "..", "scripts", "aid-ui-motion.py")
    spec = importlib.util.spec_from_file_location("aid_ui_motion", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check_motion(q, cards):
    """A `direction` question carries the reference's motion inventory (P108, 10. 10. 2026): its target is
    smer:<sha256 of <project>/.aid-ui/motion.json>, its `motion` block repeats the inventory's summary
    (sentence + every replace/omit with label and reason, so the PM's choice is also the PM's consent to
    them), and every card names its prototype `dir` under .aid-ui/directions/ whose motion was observed
    at runtime (<dir>.motion.json beside the directory, carrying the directory's sha) and checked here
    against the inventory by the server itself (a hand-written check file proves nothing). Only when the
    state has a picked reference; a run that never chose one carries no motion. A done question must
    have a recorded answer whose target is smer:<sha>. Raises ValueError."""
    if q["kind"] not in MOTION_KINDS:
        return
    # the inventory follows the reference: a run without a picked reference has no motion to carry
    state = read_state()
    refs = state.get("refs") or []
    if not any(isinstance(r, dict) and r.get("picked") for r in refs):
        return
    who = "question %s (%s)" % (q["id"], q["kind"])
    if q.get("done") is True:   # closed: its recorded answer must have been about an inventory
        a = (state.get("answers") or {}).get(q["id"]) or {}
        if not str(a.get("target", "")).startswith("smer:"):
            raise ValueError("%s: done, but its recorded answer's target is not smer:<inventory sha>; a direction chosen without the motion inventory does not count" % who)
        return
    inv = os.path.join(PROJECT, ".aid-ui", "motion.json")
    if not os.path.isfile(inv):
        raise ValueError("%s: no .aid-ui/motion.json (aid-ui-motion.py inventory): the reference's motion must be listed before directions" % who)
    mod = motion_module()
    sha = mod.sha_file(inv)
    if q.get("target") != "smer:" + sha:
        raise ValueError("%s: target must be smer:%s (the sha256 of .aid-ui/motion.json as it is now)" % (who, sha))
    try:
        with open(inv, encoding="utf-8") as f:
            summ = mod.summary_of(json.load(f))
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise ValueError("%s: .aid-ui/motion.json unreadable: %s" % (who, e))
    want = {"sha256": sha, "sentence": summ["sentence"], "exceptions": summ["exceptions"]}
    if q.get("motion") != want:
        raise ValueError("%s: `motion` must repeat the inventory: %s" % (who, json.dumps(want, ensure_ascii=False)[:300]))
    for c in cards:
        d = c.get("dir")
        if not (isinstance(d, str) and re.fullmatch(r"[A-Za-z0-9._-]+", d)):
            raise ValueError("%s: card %s needs `dir` = its prototype directory name under .aid-ui/directions/" % (who, c.get("id")))
        ddir = os.path.join(PROJECT, ".aid-ui", "directions", d)
        obs = os.path.join(PROJECT, ".aid-ui", "directions", d + ".motion.json")
        if not os.path.isdir(ddir):
            raise ValueError("%s: card %s: no directory .aid-ui/directions/%s" % (who, c.get("id"), d))
        if not os.path.isfile(obs):
            raise ValueError("%s: card %s: no .aid-ui/directions/%s.motion.json (aid-ui-tool.sh motion over the prototype, --dir-sha256 of its directory)" % (who, c.get("id"), d))
        # the server runs the check itself over the observed record: a hand-written check file proves nothing
        try:
            r = mod.check(PROJECT, obs, ddir)
        except ValueError as e:
            raise ValueError("%s: card %s: %s" % (who, c.get("id"), e))
        if not r["ok"]:
            raise ValueError("%s: card %s: the motion check of %s did not pass: %s" % (who, c.get("id"), d, "; ".join(r["failures"][:3])))


def check_handover(q, cards):
    """A `handover` question (P108): the PM sees where the web is before taking it over. .aid-ui/links.json
    (aid-ui-state.sh links) must exist and both its addresses must appear in the body; the question
    carries three cards with value prevzit (8-10/10), vyhrada (6-7/10, a comment is required with it)
    and vratit, in that order, so the PM's verdict is a number. Done questions are not checked."""
    if q["kind"] != "handover" or q.get("done") is True:
        return
    who = "question %s (handover)" % q["id"]
    lf = os.path.join(PROJECT, ".aid-ui", "links.json")
    try:
        with open(lf, encoding="utf-8") as f:
            links = json.load(f)
    except (OSError, ValueError):
        raise ValueError("%s: no .aid-ui/links.json (aid-ui-state.sh links --web --customer): the PM must see the web before handing it over" % who)
    body = " ".join(str(x) for x in (q.get("body") or []))
    for k in ("web", "customer"):
        u = links.get(k)
        if not (isinstance(u, str) and u in body):
            raise ValueError("%s: the body must carry the %s link from links.json (%s)" % (who, k, u))
    if [c.get("value") for c in cards] != ["prevzit", "vyhrada", "vratit"]:
        raise ValueError("%s: exactly three cards with value prevzit, vyhrada, vratit in that order (the PM's verdict)" % who)


def check_method(q, cards):
    """The method before the output (PM 7. 10. 2026): an open question of a kind whose method carries a
    receipt was written after the agent read that method - <project>/.aid-ui/method/<kind>.json, written
    by aid-ui-state.sh method, names the current method files with their sha256 and is at most
    RECEIPT_AGE old when the question opened; every card says what of the method it applies (`method`).
    A kind without a method needs the PM's no_method answer in the receipt (`waived`). Done questions
    and no_method itself are not checked. Raises ValueError."""
    m = SECTIONS["methods"].get(q["kind"])
    who = "question %s (%s)" % (q["id"], q["kind"])
    if q["kind"] == "no_method":   # the question about a missing method: its own shape, no method of its own
        kind = str(q.get("target", ""))[len("no_method@"):]
        if not str(q.get("target", "")).startswith("no_method@") or SECTIONS["methods"].get(kind, 0) is not None:
            raise ValueError("%s: target must be no_method@<kind> for a kind whose method is null in the map" % who)
        if sorted(str(c.get("value")) for c in cards) != ["adopt", "pm", "without"] or any("method" in c for c in cards):
            raise ValueError("%s: exactly three cards with value adopt, pm and without, none with `method`" % who)
        return
    answers = read_state().get("answers") or {}
    if q.get("done") is True and isinstance(answers.get(q["id"]), dict):   # recorded, not merely flagged
        return
    if m and not m["receipt"]:
        return
    fix = "run: aid-ui-state.sh method <project> %s, then open the question anew (new opened_at)" % q["kind"]
    path = os.path.join(PROJECT, ".aid-ui", "method", q["kind"] + ".json")
    try:
        with open(path, encoding="utf-8") as f:
            r = json.load(f)
        at, files = parse_time(r["at"]), r["files"]
    except (OSError, ValueError, KeyError, TypeError):
        raise ValueError("%s: no method receipt .aid-ui/method/%s.json; %s" % (who, q["kind"], fix))
    age = (parse_time(q["opened_at"]) - at).total_seconds()
    if not 0 <= age <= RECEIPT_AGE:
        raise ValueError("%s: the method receipt (%s) is not from the 12 hours before the question opened (%s); %s"
                         % (who, r["at"], q["opened_at"], fix))
    if m is None:   # no method: the PM's no_method answer, checked here as a whole, not trusted from the receipt
        w = r.get("waived")
        a = answers.get(w) if isinstance(w, str) else None
        chosen = next((c for c in (a or {}).get("cards") or [] if isinstance(c, dict) and c.get("id") == a.get("choice")), None) \
            if isinstance(a, dict) else None
        mode = chosen.get("value") if isinstance(chosen, dict) else None
        if not (isinstance(a, dict) and a.get("kind") == "no_method" and a.get("target") == "no_method@" + q["kind"]
                and a.get("decision") == "choose" and mode in WAIVERS and r.get("mode") == mode):
            raise ValueError("%s: this kind has no method and the receipt names no no_method answer of the PM for it "
                             "(target no_method@%s, choose, card pm or without); ask that question first" % (who, q["kind"]))
        if mode == "pm":   # the PM supplies the output: every card rests on the PM's material
            bad = [c["id"] for c in cards if c.get("source") != "podklady"]
            if bad:
                raise ValueError("%s: the PM supplies this output (no_method answer %s): card %s must have source podklady"
                                 % (who, w, ", ".join(bad)))
        return
    try:
        want = [{"path": x, "sha256": method_sha(x)} for x in m["files"]]
    except OSError as e:
        raise ValueError("%s: a method file cannot be read: %s" % (who, e))
    if files != want:
        raise ValueError("%s: the method receipt is not for the current method files (%s); %s"
                         % (who, ", ".join(m["files"]), fix))
    if q["kind"] == "identity":   # the Rozcestník decided the directions: one card per slot, each naming its slot
        rpath = os.path.join(PROJECT, ".aid-ui", "logo", "route.json")
        try:
            with open(rpath, encoding="utf-8") as f:
                slots = [x["id"] for x in json.load(f)["slots"]]
        except (OSError, ValueError, KeyError, TypeError):
            raise ValueError("%s: no .aid-ui/logo/route.json; run: aid-ui-logo-route.py <project> --write (step 1i Rozcestník)" % who)
        have = sorted(str(c.get("slot")) for c in cards)
        rebuilt = str(q.get("target") or "").startswith("logo:rebuilt:")   # the second identity question of 1i (mode full):
        if rebuilt:                                                        # the chosen direction rebuilt (vector, real type) - ONE card of that slot
            want = q["target"].split(":", 2)[2]
            if have != [want] or want not in slots:
                raise ValueError("%s: a rebuilt-logo question (target logo:rebuilt:<slot>) carries exactly one card of that slot (%s); the cards name %s"
                                 % (who, want, ", ".join(have) or "none"))
        elif have != sorted(slots):
            raise ValueError("%s: the route has slots %s, the cards name %s - one card per slot, `slot` on every card"
                             % (who, ", ".join(slots), ", ".join(have) or "none"))
    names = [os.path.basename(x) for x in m["files"]]
    bad = [c["id"] for c in cards if not (isinstance(c.get("method"), str) and 0 < len(c["method"]) <= 300
                                          and any(n in c["method"] for n in names))]
    if bad:
        raise ValueError("%s: card %s needs `method` (at most 300 characters naming one of the method files - %s - and what "
                         "of it the card applies: formula, mark type, page framework)" % (who, ", ".join(bad), ", ".join(names)))


def read_state():
    try:
        with open(os.path.join(PROJECT, "docs", "design", "brand-state.json"), encoding="utf-8") as f:
            st = json.load(f)
        return st if isinstance(st, dict) else {}
    except (OSError, ValueError):
        return {}


def is_done(cond, st):
    if "all" in cond:
        return all(is_done(c, st) for c in cond["all"])
    if "state" in cond:
        return st.get(cond["state"]) not in (None, "", {}, [])
    if "chapter" in cond:
        ch = (st.get("chapters") or {}).get(cond["chapter"])
        status = ch.get("status") if isinstance(ch, dict) else ch
        return status in ("navrh", "schvaleno")
    if "answer" in cond:
        return any(isinstance(a, dict) and a.get("kind") == cond["answer"] and a.get("decision") in ("approve", "choose")
                   for a in (st.get("answers") or {}).values())
    return False


def sections_view(questions):
    """The map with each part's status: skipped, open (a question waits), done, current (first not done), waiting."""
    st = read_state()
    # the options are the PM's only once step 1 is answered (a new state carries all of them as false)
    opts = st.get("options") if isinstance(st.get("options"), dict) and st.get("variant") else None
    open_parts = {q.get("part") for q in questions if not q.get("answered")}
    steps, first = [], None
    for s in SECTIONS["steps"]:
        out = []
        for p in s["parts"]:
            if p.get("when") and opts is not None and not opts.get(p["when"].split(".")[1]):
                status = "skipped"
            elif p["id"] in open_parts:
                status = "current"
            elif is_done(p["done"], st):
                status = "done"
            else:
                status = "waiting"
            out.append({k: p.get(k) for k in ("id", "title", "why", "goal", "feeds", "you", "text")} | {"status": status})
        steps.append({k: s[k] for k in ("n", "title", "why", "goal", "feeds")} | {"parts": out})
    if not open_parts:   # nothing waits for the PM: the first unfinished part is where the work is
        for s in steps:
            for p in s["parts"]:
                if first is None and p["status"] == "waiting":
                    p["status"], first = "current", p
    for s in steps:
        ps = [p["status"] for p in s["parts"] if p["status"] != "skipped"]
        s["status"] = "done" if ps and all(x == "done" for x in ps) else ("current" if "current" in ps else "waiting")
    return {"steps": steps, "sources": SECTIONS["sources"]}


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
        o = q.get("outcome")
        if o is not None and not (isinstance(o, str) and len(o) <= 120):
            raise ValueError("payload.json: question %s outcome must be a string of at most 120 characters" % q["id"])
        try:
            parse_time(q.get("opened_at"))
        except (TypeError, ValueError):
            raise ValueError("payload.json: question %s has no valid opened_at" % q["id"])
        if q["kind"] in ("facts", "no_method") and "part" not in q:
            raise ValueError("payload.json: question %s (%s) must name its part" % (q["id"], q["kind"]))
        try:
            q["part"] = part_of(q)
        except ValueError as e:
            raise ValueError("payload.json: %s" % e)
    shown = set()  # (question, card id): a choice names exactly one card the PM saw
    for c in cards:
        if not (isinstance(c, dict) and isinstance(c.get("id"), str) and c["id"]
                and isinstance(c.get("question"), str)):
            raise ValueError("payload.json: every card needs a non-empty string id and a string question")
        if (c["question"], c["id"]) in shown:
            raise ValueError("payload.json: card id %s twice in question %s" % (c["id"], c["question"]))
        shown.add((c["question"], c["id"]))
    for q in qs:   # a question on facts offers three answers, each saying what it rests on
        if q["kind"] != "facts":
            continue
        own = [c for c in cards if c["question"] == q["id"]]
        if len(own) < 3:
            raise ValueError("payload.json: question %s (facts) needs at least 3 cards, the first recommended" % q["id"])
        bad = [c["id"] for c in own if c.get("source") not in SECTIONS["sources"]]
        if bad:
            raise ValueError("payload.json: question %s: card %s needs a source from sections.json sources (%s)"
                             % (q["id"], ", ".join(bad), ", ".join(SECTIONS["sources"])))
    for q in qs:   # H5 (12. 10. 2026): cards nested in a question were silently dropped; they belong in cards[]
        if "cards" in q:
            raise ValueError("payload.json: question %s carries its own \"cards\"; cards go in the top-level cards[] with \"question\": \"%s\"" % (q["id"], q["id"]))
    for q in qs:   # the method before the output, and the PM's earlier choice carried into the next question
        try:
            check_method(q, [c for c in cards if c["question"] == q["id"]])
            check_prior(q, [c for c in cards if c["question"] == q["id"]])
            check_motion(q, [c for c in cards if c["question"] == q["id"]])
            check_handover(q, [c for c in cards if c["question"] == q["id"]])
        except ValueError as e:
            raise ValueError("payload.json: %s" % e)
    with LOCK:
        qs = qs + [dict(q) for i, q in REROLLED.items() if i not in seen]
        qs = qs + [dict(q) for i, q in CHANGED.items() if i not in seen]
        # once the agent lists a change in the payload, the payload's question and cards are the ones
        cards = cards + [dict(c) for i, cs in CHANGED_CARDS.items() if i not in seen for c in cs]
    return {"now": p.get("now"), "steps": steps, "questions": qs, "cards": cards}


def root_of(qid):
    return re.sub(r"(\.c\d+)+$", "", qid)


def open_change(p, root):
    """The id of an unanswered change of the root question, if one is open."""
    return next((q["id"] for q in p["questions"] if q.get("changed_from") == root and not valid_answer(q)), None)


def valid_answer(q):
    """The stored answer to q if it was given for q as it stands now. After a restart the memory is empty:
    the studio's own history (history.jsonl, written by this server for every answer it accepted) is
    read back, never the state script's record - `set --answer` checks the studio as the independent
    side, so the studio must not echo what the script wrote (security review 9. 10. 2026)."""
    a = ANSWERS.get(q["id"]) or answer_from_history(q["id"])
    try:
        if a and a["kind"] == q["kind"] and a["target"] == q["target"] \
                and parse_time(a["at"]) > parse_time(q["opened_at"]):
            return a
    except (TypeError, ValueError):
        return None
    return None


def payload_cards_sha(qid):
    """The sha256 of qid's cards as payload.json lists them now (the same hashing POST /answer uses), or
    None: for a history line written before 9. 10. 2026 (no cards_sha256). The state script accepts
    the restored answer only when this equals the hash it recorded live - the cards did not change."""
    try:
        with open(os.path.join(STUDIO, "payload.json"), encoding="utf-8") as f:
            p = json.load(f)
        cards = sorted((dict({k: c.get(k) for k in CARD_FIELDS}, preview_sha256=preview_sha(c))
                        for c in p.get("cards", []) if isinstance(c, dict) and c.get("question") == qid), key=lambda c: c["id"])
    except (OSError, ValueError, TypeError, KeyError):
        return None
    return hashlib.sha256(json.dumps(cards, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def answer_from_history(qid):
    """The latest answer the PM gave to qid as this studio recorded it in history.jsonl (by: pm,
    with cards_sha256 - or, for a line from before 9. 10. 2026 without it, with the hash of the
    question's cards as the payload lists them now, marked migrated); None when there is none or
    the file cannot be read."""
    found = None   # the latest by answer.at, not the last line (a stale later line must not shadow it)
    try:
        with open(HISTORY, encoding="utf-8") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if not (isinstance(e, dict) and e.get("by") == "pm" and isinstance(e.get("question"), dict)
                        and e["question"].get("id") == qid and isinstance(e.get("answer"), dict)):
                    continue
                migrated = False
                if not e.get("cards_sha256"):   # a line from before the hash was kept: the payload's cards stand in
                    sha = payload_cards_sha(qid)
                    if not sha:
                        continue
                    e["cards_sha256"] = sha
                    migrated = True
                qq, an = e["question"], e["answer"]
                try:
                    parse_time(an.get("at"))
                except (TypeError, ValueError):
                    continue
                if found and str(an.get("at")) <= str(found["at"]):
                    continue
                found = {"question": qid, "kind": qq.get("kind"), "target": qq.get("target"), "decision": an.get("decision"),
                         "choice": an.get("choice"), "comment": an.get("comment"), "at": an.get("at"),
                         "cards": e.get("cards") or [], "cards_sha256": e["cards_sha256"], "migrated": migrated}
    except OSError:
        return None
    return found


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
    or preview change does not alter what the PM saw. Display, and after a restart the studio's own
    memory of what it accepted (answer_from_history); the agent never reads it as a decision."""
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
    entry = {"by": "pm", "question": {k: v for k, v in q.items() if k not in ("answered", "answer")},
             "cards": kept, "cards_sha256": answer.get("cards_sha256"), "step": (cur or {}).get("title"),
             "answer": {k: answer.get(k) for k in ("decision", "choice", "comment", "at")}}
    # One line, appended under the same exclusive lock `aid-ui-state.sh decide` takes (flock on
    # the file), so a PM answer and an agent decision never interleave.
    with open(HISTORY, "a", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
        fh.flush()


def read_history():
    """(parsed lines in file order, number of lines in the file, lines skipped); a line that is
    not a JSON object (a torn or foreign write) is skipped, never empties the whole history."""
    try:
        with open(HISTORY, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return [], 0, 0
    out, bad = [], 0
    for l in lines:
        if not l.strip():
            continue
        try:
            e = json.loads(l)
        except ValueError:
            e = None
        if isinstance(e, dict):
            out.append(e)
        else:
            bad += 1
    return out, len(lines), bad


def next_id(qid):
    m = re.fullmatch(r"(.*)\.r(\d+)", qid)
    return "%s.r%d" % (m.group(1), int(m.group(2)) + 1) if m else qid + ".r1"


class Studio(BaseHTTPRequestHandler):
    def change(self):
        """The PM changes an answer: a new open question <root>.c<n> with the same kind, target, part,
        text and copies of the cards. Allowed for a question in the payload that the PM answered
        (an answer held now, or one the agent marked done after recording it)."""
        if not self.gate(True) or (p := self.payload()) is None:
            return
        try:
            b = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
        except (ValueError, json.JSONDecodeError):
            b = None
        qid = b.get("question") if isinstance(b, dict) else None
        cur = next((x for x in p["questions"] if x["id"] == qid), None)
        if cur is None:
            self.send(404, {"error": "no question %s" % qid})
            return
        with LOCK:
            if not (valid_answer(cur) or cur.get("done") is True):
                self.send(409, {"error": "question %s has no answer to change" % qid})
                return
            root = root_of(qid)
            if open_change(p, root):
                self.send(409, {"error": "a change of %s is already open; answer it first" % root})
                return
            taken = {x["id"] for x in p["questions"]} | set(CHANGED)
            n = 1 + max([int(m.group(1)) for i in taken if (m := re.fullmatch(re.escape(root) + r"\.c(\d+)", i))] or [0])
            new = "%s.c%d" % (root, n)
            q = {k: v for k, v in cur.items() if k not in ("id", "opened_at", "answered", "answer", "done", "answer_title", "changed_to")}
            CHANGED[new] = dict(q, id=new, opened_at=iso(now()), changed_from=root)
            CHANGED_CARDS[new] = [dict(c, question=new) for c in p["cards"] if c.get("question") == qid]
        self.send(200, {"next_question": new})

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
            if k == "aid_studio_%d" % self.server.server_port and v in SESSIONS:   # one cookie per port: two studios on one host do not log each other out
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
        if u.path == "/favicon.svg":   # the AID tab icon (lib/aid-ui-studio/aid-icon.svg); public, nothing of the project in it
            with open(os.path.join(HERE, "aid-icon.svg"), "rb") as f:
                self.send(200, f.read(), "image/svg+xml")
            return
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
                self.send_header("Set-Cookie", "aid_studio_%d=%s; HttpOnly; SameSite=Strict; Path=/" % (self.server.server_port, sid))
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
                    x["answered"] = a is not None or x.get("done") is True   # done: the agent recorded it
                    if a:   # what the PM decided, for the page's confirmation
                        x["answer"] = {"decision": a["decision"], "choice": a["choice"], "comment": a["comment"], "at": a["at"],
                                       "choice_title": next((c["title"] for c in a["cards"]
                                                             if c["id"] == a["choice"]), None)}
            p["project"] = os.path.basename(PROJECT)
            p["history_lines"] = read_history()[1]
            # P108: where the web is, whether the run finished, and what stays open (the state's items
            # plus the PM's own from the history, not yet synced)
            for name, rel in (("links", "links.json"), ("finish", "finish.json"), ("quality", "critic/loop.json")):   # quality: P113a loop
                try:
                    with open(os.path.join(PROJECT, ".aid-ui", rel), encoding="utf-8") as f:
                        p[name] = json.load(f)
                except (OSError, ValueError):
                    p[name] = None
            st = read_state()
            items = [i for i in (st.get("open_items") or []) if isinstance(i, dict)]
            seen = {i.get("id") for i in items}
            for h in read_history()[0]:
                if isinstance(h, dict) and h.get("by") == "pm" and h.get("kind") == "open_item" and isinstance(h.get("text"), str) \
                        and re.match(r"\d{4}-\d{2}-\d{2}T", str(h.get("at") or "")):
                    hid = "pm-" + re.sub(r"[^0-9]", "", str(h.get("at")))[:20]
                    if hid not in seen:
                        items.append({"id": hid, "text": h["text"][:500], "owner": "PM", "by": "pm", "at": h.get("at"), "status": "open"})
            p["open_items"] = items
            p["sections"] = sections_view(p["questions"])
            with LOCK:
                for x in p["questions"]:   # the original shows that the PM is changing it
                    ch = open_change(p, root_of(x["id"]))
                    if ch and ch != x["id"]:
                        x["changed_to"] = ch
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
            which = "preview2" if q.get("n") == "2" else "preview"   # n=2: the card's second picture (contexts)
            f = os.path.realpath(os.path.join(STUDIO, str((c or {}).get(which) or "")))
            if not c or not (c.get(which) or "") or not f.startswith(STUDIO + os.sep) or not os.path.isfile(f):
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
            lines, _, bad = read_history()
            if bad:
                self.log_message("history: %d line(s) not a JSON object, skipped", bad)
            self.send(200, lines)
        elif u.path == "/history/preview":
            if not self.gate(True):
                return
            e = next((h for h in read_history()[0] if h.get("question", {}).get("id") == q.get("question")), None)
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

    def open_item(self):
        """POST /open-item {text}: the PM adds an open point (what still has to happen) from the page; the
        same protection as /answer (session cookie or token, same-site), text 1-500 characters; one
        line in history.jsonl (by pm, kind open_item) that aid-ui-state.sh open-items-sync takes over."""
        if not self.gate(True):
            return
        try:
            b = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
        except (ValueError, json.JSONDecodeError):
            b = None
        text = str((b or {}).get("text") or "").strip() if isinstance(b, dict) else ""
        if not text or len(text) > 500:
            self.send(422, {"error": "open-item needs text (1-500 characters)"})
            return
        entry = {"by": "pm", "kind": "open_item", "text": text, "at": iso(now())}
        try:
            with open(HISTORY, "a", encoding="utf-8") as fh:
                fcntl.flock(fh, fcntl.LOCK_EX)
                fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
                fh.flush()
        except OSError as e:
            self.send(500, {"error": "history not written: %s" % e})
            return
        self.log_message("open item: %s", text[:60])
        self.send(200, entry)

    def do_POST(self):
        path = urlsplit(self.path).path
        if path == "/change":
            return self.change()
        if path == "/open-item":
            return self.open_item()
        if path != "/answer":
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
        if d == "choose" and cur["kind"] == "handover" and not comment and any(
                isinstance(c, dict) and c.get("question") == qid and c.get("id") == choice and c.get("value") == "vyhrada" for c in p["cards"]):
            self.send(422, {"error": "a handover with a reservation (vyhrada) needs a comment saying what"})
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
                               "prompt": cur.get("prompt"), "part": cur.get("part"), "rerolled_from": qid}
            ANSWERS[qid] = a
        try:   # outside LOCK: waiting for the file lock must not stall the other requests
            keep_history(cur, [c for c in p["cards"] if isinstance(c, dict) and c.get("question") == qid], a, p.get("steps"))
        except OSError as e:   # the history is a record for the PM, never a reason to lose the answer
            self.log_message("history not written: %s", e)
        self.log_message("answer %s: %s", qid, d)
        self.send(200, a)


if args.check:
    try:
        load()
    except ValueError as e:
        sys.exit("ERROR: %s" % e)
    print("payload OK: %s/payload.json" % STUDIO)
    sys.exit(0)
ThreadingHTTPServer((args.host, PORT), Studio).serve_forever()
