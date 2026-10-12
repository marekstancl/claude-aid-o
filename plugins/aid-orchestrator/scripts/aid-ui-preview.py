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
  Any other POST -> 404. The log (stderr) carries the status and the message id, never a field value.
On the client's domain the form posts to the hosting's receiver instead; only the endpoint in DESIGN.md / form.json
changes and the same gate row (form_delivery) checks it.
"""
import email.parser, email.policy, functools, hashlib, http.server, json, os, secrets, sys, threading, time, urllib.parse

MAX_BODY, DUP_SECONDS = 32 * 1024, 600
_seen, _lock = {}, threading.Lock()


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
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
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
        with _lock:
            for k in [k for k, t in _seen.items() if now - t > DUP_SECONDS]:
                del _seen[k]
            if key in _seen:
                return self.reply(200, {"ok": True, "duplicate": True}, "duplicate")
            _seen[key] = now
        mid = secrets.token_hex(4)
        box = os.path.join(self.project, ".aid-ui", "inbox")
        os.makedirs(box, mode=0o700, exist_ok=True)
        p = os.path.join(box, "%s-%s.json" % (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), mid))
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"id": mid, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "fields": f}, fh, ensure_ascii=False)
        self.reply(200, {"ok": True, "id": mid}, "delivered " + mid)


if __name__ == "__main__":
    port, host, site = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    H.project = os.path.realpath(sys.argv[4]) if len(sys.argv) > 4 else None
    http.server.ThreadingHTTPServer((host, port), functools.partial(H, directory=site)).serve_forever()
