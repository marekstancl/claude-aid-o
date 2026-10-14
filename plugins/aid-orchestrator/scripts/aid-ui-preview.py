#!/usr/bin/env python3
"""aid-ui-preview.py <port> <host> <site dir> [<project>] - the preview of the built site, and its form receiver
(P113a step 6, FB-28 / AC8, 12. 10. 2026).

Static: the site directory as is; no dotfile but .well-known, no directory listing.

Form receiver (only with <project>/.aid-ui/form.json {endpoint, required: [field...], honeypot, max_field}):
  POST <endpoint> (urlencoded, multipart or JSON, at most 32 kB)
  - honeypot field filled      -> 200 {"ok": true}, nothing delivered (spam, said only in the log)
  - a required field empty, a field over max_field -> 422 {"error": "...", "field": "<name>"}
  - the same message again within 10 minutes -> 200 {"ok": true, "duplicate": true}, delivered once
  - otherwise delivered: <project>/.aid-ui/inbox/<utc>-<id>.json (mode 600) -> 200 {"ok": true, "id": "<id>"}
  No or a bad Content-Length -> 411/413 (the body is never read to its end); a full inbox (500) -> 503; more than
  20 messages a minute from one address -> 429; a stalled body times out after 10 s.
  Any other POST -> 404. The log (stderr) carries the status and the message id, never a field value.
This receiver is the preview's only. On the client's domain the form posts to the hosting's receiver; that one is
checked after the deployment (out of P113a's scope), until then it is a critical open item (FB-28).
"""
import email.parser, email.policy, functools, hashlib, http.server, json, os, secrets, sys, threading, time, urllib.parse

MAX_BODY, DUP_SECONDS, MAX_INBOX = 32 * 1024, 600, 500   # a preview inbox never grows past MAX_INBOX messages
RATE = 20   # messages per address and minute
_seen, _lock, _hits = {}, threading.Lock(), {}


def form_cfg(project):
    try:
        with open(os.path.join(project, ".aid-ui", "form.json"), encoding="utf-8") as f:
            c = json.load(f)
        return c if isinstance(c, dict) and str(c.get("endpoint", "")).startswith("/") else None
    except (OSError, ValueError, TypeError):
        return None


def fields_of(ctype, body):
    if ctype.startswith("application/json"):
        d = json.loads(body or b"{}")
        return {str(k): str(v) for k, v in d.items()} if isinstance(d, dict) else {}
    if ctype.startswith("multipart/form-data"):
        msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + body)
        out = {}
        for part in msg.iter_parts():
            name = part.get_param("name", header="content-disposition")
            if name and not part.get_filename():
                out[name] = part.get_content() if isinstance(part.get_content(), str) else ""
        return out
    return {k: v[0] for k, v in urllib.parse.parse_qs(body.decode("utf-8", "replace"), keep_blank_values=True).items()}


class H(http.server.SimpleHTTPRequestHandler):
    project = None
    timeout = 10   # a client that stops sending mid-body does not hold a thread

    def log_message(self, fmt, *args):   # no query strings or bodies in the log
        sys.stderr.write("%s %s\n" % (self.command, args[1] if len(args) > 1 else ""))

    def send_head(self):
        segs = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path).split("/")
        if any(x.startswith(".") and x != ".well-known" for x in segs):
            self.send_error(404)
            return None
        return super().send_head()

    def list_directory(self, path):
        self.send_error(404)
        return None

    def reply(self, code, obj, note):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
        sys.stderr.write("FORM %d %s\n" % (code, note))

    def do_POST(self):
        cfg = form_cfg(self.project) if self.project else None
        if not cfg or urllib.parse.urlsplit(self.path).path != cfg["endpoint"]:
            return self.send_error(404)
        ip, now0 = self.client_address[0], time.time()
        with _lock:
            _hits[ip] = [t for t in _hits.get(ip, []) if now0 - t < 60] + [now0]
            if len(_hits[ip]) > RATE:
                return self.reply(429, {"error": "too many"}, "rate limited")
        try:
            n = int(self.headers.get("Content-Length") or "")
        except ValueError:
            return self.reply(411, {"error": "length required"}, "no length")   # chunked or missing: never read to EOF
        if n < 0 or n > MAX_BODY:
            return self.reply(413, {"error": "too long"}, "too long")
        try:
            f = fields_of(self.headers.get("Content-Type") or "", self.rfile.read(n))
        except (ValueError, UnicodeDecodeError):
            return self.reply(400, {"error": "unreadable"}, "unreadable")
        hp = cfg.get("honeypot")
        if hp and (f.get(hp) or "").strip():
            return self.reply(200, {"ok": True}, "spam dropped")
        for k in cfg.get("required") or []:
            if not (f.get(k) or "").strip():
                return self.reply(422, {"error": "missing", "field": k}, "missing " + k)
        mx = int(cfg.get("max_field") or 2000)
        for k, v in f.items():
            if len(v) > mx:
                return self.reply(422, {"error": "too long", "field": k}, "too long " + k)
        f.pop(hp, None) if hp else None
        key = hashlib.sha256(json.dumps(f, sort_keys=True).encode()).hexdigest()
        now = time.time()
        mid = secrets.token_hex(4)
        box = os.path.join(self.project, ".aid-ui", "inbox")
        with _lock:   # the duplicate check, the capacity and the write are one step; a failed write marks nothing as seen
            for k in [k for k, t in _seen.items() if now - t > DUP_SECONDS]:
                del _seen[k]
            if key in _seen:
                return self.reply(200, {"ok": True, "duplicate": True}, "duplicate")
            try:
                os.makedirs(box, mode=0o700, exist_ok=True)
                if len(os.listdir(box)) >= MAX_INBOX:
                    return self.reply(503, {"error": "inbox full"}, "inbox full")
                p = os.path.join(box, "%s-%s.json" % (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), mid))
                fd = os.open(p + ".part", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as fh:
                    json.dump({"id": mid, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "fields": f}, fh, ensure_ascii=False)
                os.rename(p + ".part", p)
            except OSError as e:
                return self.reply(500, {"error": "not delivered"}, "write failed: %s" % e.__class__.__name__)
            _seen[key] = now
        self.reply(200, {"ok": True, "id": mid}, "delivered " + mid)


if __name__ == "__main__":
    port, host, site = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    H.project = os.path.realpath(sys.argv[4]) if len(sys.argv) > 4 else None
    http.server.ThreadingHTTPServer((host, port), functools.partial(H, directory=site)).serve_forever()
