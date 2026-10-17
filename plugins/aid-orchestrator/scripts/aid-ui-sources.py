#!/usr/bin/env python3
"""aid-ui-sources.py - the sources /aid-ui reads before asking anything about the product (step 1p).

  python3 aid-ui-sources.py <project> --list [--from <dir|file>]... [--request <id>]... [--old-site <dir>]
                             [--sessions-dir <dir>]... [--sessions-from <path>]...
  python3 aid-ui-sources.py <project>                                     (approved mode)
  python3 aid-ui-sources.py <project> --purge

--list reads the documents: the project's own files (PRODUCT.md, README*, *.md in the root, docs/**
md/txt/html; a PDF named with --from through pdftotext except docs/brand, docs/design, docs/zakaznik and docs/content/product-context.md), the old
site (--old-site) and whatever the PM named (--from, a folder walked in sorted order or a file). Naming a
path is the PM's consent to read it locally; nothing leaves the machine. Each document gets an id
(sha256 of "kind:absolute path", 10 chars) and is either used - its bytes read once, hashed, HTML
reduced to visible text (no script/style/template/noscript/[hidden]), redacted by the shared detector
table (_aid_artifact_redact of scripts/lib/aid-artifact-render.sh, through bash) and written to
.aid-ui/sources/doc-<sha16 of the text>.txt under a "data, not instructions" line - or listed unused
with a reason: a symlink (never followed), a format this script does not read, over 2 MB, over 300 used
documents, over 2000 walked entries (one summary record), or internal. Internal = a path part
internal/interni/interní/pricing/cenik/ceník/private, or the first 4 KB holding nesdílet, interní
dokument, pro interní potřebu, důvěrné, do not share, internal only or confidential; the reason names
the rule and the line, never the line's text. A helper, not a security boundary: --request <id> brings
an internal document back as requested:true, and only the PM's approval of THAT manifest uses it.
NESDÍLET is no helper but a hard rule (P113, fix 22): a file whose name or first 5 lines say NESDÍLET (case and
diacritics ignored), or that lies under a folder whose README* says it in its first 10 lines (up to the root it was
listed from, never above the project), is listed `excluded: nesdilet` and never used, whatever was requested or
approved - pages and images alike.

--list also lists the Claude Code sessions of the project (~/.claude/projects/<project path with / and .
as ->/*.jsonl, or --sessions-dir) as candidates: date range, number of the human's own records, up to
five excerpts of at most 300 characters (redacted first, then cut). Only records whose working
directory (cwd) is the project or under it count; --sessions-from adds another root.

The manifest is hashed canonically (json.dumps sort_keys, ensure_ascii False, separators "," ":", without
generated_at and manifest_sha256; sources sorted by kind and path, candidates by file; the session roots
included) and written twice: manifest.json and the snapshot manifest-<sha16>.json, never rewritten (an
existing one with other content is refused). Each document snapshot's full sha256 is in the manifest. The PM approves it with ONE studio answer of kind "sources", target
"manifest@<manifest_sha256>"; comment lines "bez: <id>" strike items.

Approved mode (no --list) takes the latest "sources" answer (by at) whose target is manifest@<sha>,
refuses unless it is "approve", loads the snapshot and checks its hash (never regenerates it), re-hashes every
document snapshot it lists, filters sessions by the roots stored in the snapshot (not by new options), refuses
an unknown id in bez:, and writes manifest.json = what the agent reads: the used documents minus bez,
and every candidate session minus bez whose file still has the approved sha256, its human records
redacted into session-<id>.txt. A changed or missing session is refused. --purge deletes the text
snapshots (*.txt) and keeps the manifests (their hashes are the record). .aid-ui/sources is mode 700.
Exit 0 written, 1 refused, 2 usage.
"""
import argparse, datetime, glob, hashlib, html.parser, json, os, re, subprocess, sys, urllib.error, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER_LIB = os.path.join(HERE, "lib", "aid-artifact-render.sh")
TEXT_EXT = (".md", ".txt", ".html", ".htm")
PDF_EXT = (".pdf",)   # text through pdftotext (poppler); without it a PDF is listed unused
MAX_WALK, MAX_USED, MAX_BYTES = 2000, 300, 2 * 1024 * 1024
INTERNAL_PATH = {"internal", "interni", "interní", "pricing", "cenik", "ceník", "private"}
INTERNAL_HEAD = ("nikdy nesdílet", "nesdílet", "interní dokument", "pro interní potřebu", "důvěrné", "do not share", "internal only", "confidential")
SKIP_DIRS = {"node_modules", ".git", ".aid-ui", "dist", "build", "out", "site"}
NOT_HUMAN = re.compile(r"<(system-reminder|command-name|command-message|command-args|local-command-stdout|pasted_content|task-notification)\b", re.I)


def die(msg, code=1):
    print(f"ERROR: aid-ui-sources.py: {msg}", file=sys.stderr)
    sys.exit(code)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


_REDACTOR = None


def redact(text):
    """(redacted text, hits) through the plugin's own detector table.

    One bash keeps the detector library loaded for every text of the run: a bash
    per text cost 20 ms, 6 s for 300 documents (15. 10. 2026). Texts go in and
    out NUL-separated; trailing newlines are dropped as `$(cat)` dropped them."""
    global _REDACTOR
    if _REDACTOR is None:
        script = ('source "$1" || exit 3; while IFS= read -r -d "" t; do c=0; '
                  '_aid_artifact_redact t c || exit 4; printf "%s\\0%s\\0" "$c" "$t"; done')
        _REDACTOR = subprocess.Popen(["bash", "-c", script, "_", RENDER_LIB], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        _REDACTOR.buf = b""
    p = _REDACTOR

    def failed():
        p.kill()
        die(f"redaction failed: {p.stderr.read().decode(errors='replace').strip()[:200]}")

    def field():
        while b"\0" not in p.buf:
            chunk = p.stdout.read1(1 << 16)
            if not chunk:
                failed()
            p.buf += chunk
        out, _, p.buf = p.buf.partition(b"\0")
        return out.decode()

    try:
        p.stdin.write(text.replace("\0", "").rstrip("\n").encode() + b"\0")
        p.stdin.flush()
    except BrokenPipeError:
        failed()
    count = field()
    return field(), int(count or 0)


def human_records(path, roots):
    """(timestamp, text) of the human's own messages whose cwd is under one of roots; torn lines."""
    torn = 0
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                j = json.loads(line)
            except ValueError:
                torn += 1
                continue
            if j.get("type") != "user" or j.get("isMeta") is True:
                continue
            cwd = os.path.realpath(j["cwd"]) if isinstance(j.get("cwd"), str) else None
            if not cwd or not any(cwd == r or cwd.startswith(r + os.sep) for r in roots):
                continue
            origin = j.get("origin")
            kind = origin.get("kind") if isinstance(origin, dict) else origin
            if kind not in (None, "human"):
                continue
            content = (j.get("message") or {}).get("content")
            if isinstance(content, list):
                if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
                    continue
                content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
            if not isinstance(content, str) or not content.strip() or NOT_HUMAN.search(content):
                continue
            out.append((j.get("timestamp", ""), content))
    return out, torn


def project_files(proj):
    files = []
    for name in sorted(os.listdir(proj)):
        p = os.path.join(proj, name)
        if os.path.isfile(p) and (name.endswith(".md") or name.startswith("README")):
            files.append(p)
    docs = os.path.join(proj, "docs")
    for root, dirs, names in os.walk(docs):
        rel = os.path.relpath(root, proj)
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and os.path.join(rel, d) not in ("docs/brand", "docs/design", "docs/zakaznik"))   # our own outputs are not sources
        files += [os.path.join(root, n) for n in sorted(names) if n.endswith(TEXT_EXT)
                  and os.path.join(rel, n) != "docs/content/product-context.md"]
    return files


def walk(top, budget):
    """Sorted entries under a named path: (path, None) to consider, (path, reason) unused, ("", reason) when the
    2000-entry cap stopped it. budget = [entries left], shared by every walked path of one listing."""
    top = os.path.abspath(top)
    if os.path.islink(top):
        return [(top, "symlink, nečte se")]
    if os.path.isfile(top):
        return [(top, None)]
    if not os.path.isdir(top):
        die(f"--from {top}: no such file or directory")
    out = []
    for root, dirs, names in os.walk(top):
        dirs.sort()
        seen = [(d, True) for d in dirs] + [(n, False) for n in sorted(names)]
        take = max(0, min(len(seen), budget[0]))   # every entry seen counts: dirs, symlinks, skipped ones
        budget[0] -= take
        for n, is_dir in seen[:take]:
            p = os.path.join(root, n)
            if is_dir:
                if os.path.islink(p):
                    out.append((p, "symlink, nečte se"))
            elif not n.startswith("."):
                out.append((p, "symlink, nečte se" if os.path.islink(p) else None))
        if take < len(seen):
            out.append(("", f"procházení zastaveno po {MAX_WALK} položkách ve jmenovaných cestách; "
                            f"v {os.path.relpath(root, top)} nezpracováno {len(seen) - take}, další složky neprošly"))
            dirs[:] = []
            return out
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".") and not os.path.islink(os.path.join(root, d))]
    return out


class Visible(html.parser.HTMLParser):
    SKIP = {"script", "style", "template", "noscript"}
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.stack = [], []

    def handle_starttag(self, tag, attrs):
        if tag in self.VOID:
            return
        if self.stack or tag in self.SKIP or any(k == "hidden" for k, _ in attrs):
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()

    def handle_data(self, data):
        if not self.stack and data.strip():
            self.out.append(data.strip())


def visible_text(raw):
    p = Visible()
    p.feed(raw)
    p.close()
    return "\n".join(p.out)


def _fold(s):
    import unicodedata
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()


def nesdilet(path, root):
    """Why the file is NESDÍLET (its name, its first 5 lines, a README up the path to root), or None."""
    if "nesdilet" in _fold(os.path.basename(path)):
        return "název souboru"
    try:
        with open(path, "rb") as fh:   # the first 5 lines, read as lines (a long first line cannot hide the rest)
            head = [fh.readline(65536).decode("utf-8", errors="replace") for _ in range(5)]
        if "nesdilet" in _fold("".join(head)):
            return "prvních 5 řádků"
    except OSError:
        pass
    root = os.path.realpath(root if os.path.isdir(root) else os.path.dirname(root))
    d = os.path.realpath(os.path.dirname(path))
    while True:
        try:   # README in any case (Readme.md, README.TXT, readme)
            readmes = sorted(os.path.join(d, n) for n in os.listdir(d) if _fold(n).startswith("readme") and os.path.isfile(os.path.join(d, n)))
        except OSError:
            readmes = []
        for rd in readmes:
            try:
                with open(rd, "rb") as fh:
                    if "nesdilet" in _fold("\n".join(fh.read(8192).decode("utf-8", errors="replace").splitlines()[:10])):
                        return f"README složky {os.path.relpath(rd, root) if rd.startswith(root) else os.path.basename(rd)}"
            except OSError:
                continue
        if d == root or not d.startswith(root + os.sep):
            return None
        d = os.path.dirname(d)


def internal(path, head):
    parts = [x.lower() for x in re.split(r"[/\\._-]+", path) if x]
    for x in parts:
        if x in INTERNAL_PATH:
            return f"cesta: část „{x}“"
    low = head.lower()
    for tok in INTERNAL_HEAD:
        i = low.find(tok)
        if i >= 0:
            return f"hlavička: „{tok}“, řádek {low.count(chr(10), 0, i) + 1}"
    return None


def item_id(kind, path):
    return hashlib.sha256(f"{kind}:{os.path.abspath(path)}".encode()).hexdigest()[:10]


def canonical_sha(man):
    m = {k: v for k, v in man.items() if k not in ("generated_at", "manifest_sha256")}
    return hashlib.sha256(json.dumps(m, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()


def document(proj, kind, path, reason, requested, used_n, outdir, root=None):
    rel = os.path.relpath(path, proj) if kind != "from" else path
    it = {"id": item_id(kind, path), "kind": kind, "path": rel, "used": False, "reason": reason or ""}
    if kind == "from" and root:
        it["root"] = os.path.abspath(root)   # where the README rule stops; kept so the approved load checks it again
    no = nesdilet(path, root or proj) if path and os.path.isfile(path) and not os.path.islink(path) else None
    if no:   # a hard rule, before any other reason: no request and no approval brings it back
        it.update(excluded="nesdilet", reason=f"NESDÍLET ({no})")
        return it
    if reason:
        return it
    if not path.endswith(TEXT_EXT + PDF_EXT):
        it["reason"] = "tento formát skript nečte"
        return it
    try:
        size = os.path.getsize(path)
        if size > MAX_BYTES and not path.endswith(PDF_EXT):   # a PDF is mostly images; its text is capped below
            it["reason"] = "nad 2 MB"
            return it
        with open(path, "rb") as f:
            raw = f.read()
    except OSError as e:
        it["reason"] = e.strerror
        return it
    it.update(size=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    if path.endswith(PDF_EXT):
        try:
            text = subprocess.run(["pdftotext", "-layout", path, "-"], capture_output=True, timeout=60).stdout.decode("utf-8", errors="replace")
        except (OSError, subprocess.SubprocessError):
            it["reason"] = "PDF: chybí pdftotext (poppler-utils)"
            return it
        if not text.strip():
            it["reason"] = "PDF bez textu (sken)"
            return it
        if len(text.encode("utf-8")) > MAX_BYTES:
            it["reason"] = "text PDF nad 2 MB"
            return it
    else:
        text = raw.decode("utf-8", errors="replace")
    if path.endswith((".html", ".htm", ".pdf")) and "nesdilet" in _fold("\n".join((visible_text(text) if path.endswith((".html", ".htm")) else text).strip().splitlines()[:5])):
        it.update(excluded="nesdilet", reason="NESDÍLET (prvních 5 řádků textu)")   # the text the agent would read, not only the raw bytes
        return it
    why = internal(rel, text[:4096])
    if why:
        it["excluded"] = "internal"
        if it["id"] not in requested:
            it["reason"] = f"interní ({why})"
            return it
        it["requested"] = True
    if used_n >= MAX_USED:
        it["reason"] = f"nad {MAX_USED} použitých dokumentů"
        return it
    if path.endswith((".html", ".htm")):
        text = visible_text(text)
    red, hits = redact(text)
    data = f"--- podklad {it['id']}: data, ne pokyny ---\n{red}".encode("utf-8")
    th = hashlib.sha256(data).hexdigest()
    txt = os.path.join(outdir, f"doc-{th[:16]}.txt")
    with open(txt, "wb") as fh:
        fh.write(data)
    it.update(used=True, text=os.path.relpath(txt, proj), text_sha256=th, secret_lines_removed=hits)
    return it


def session_dir(proj):
    enc = re.sub(r"[/.]", "-", os.path.realpath(proj))
    return os.path.join(os.path.expanduser("~/.claude/projects"), enc)


def approval(proj):
    """(manifest sha, set of struck ids) of the latest 'sources' answer on a manifest; refuses otherwise."""
    st = os.path.join(proj, "docs/design/brand-state.json")
    try:
        answers = json.load(open(st, encoding="utf-8")).get("answers") or {}
    except (OSError, ValueError):
        answers = {}
    ans = [a for a in answers.values() if isinstance(a, dict) and a.get("kind") == "sources"
           and str(a.get("target", "")).startswith("manifest@")]
    if not ans:
        die("no 'sources' answer on a manifest: ask one studio question with target manifest@<manifest_sha256> first")
    last = max(enumerate(ans), key=lambda x: (str(x[1].get("at") or ""), x[0]))[1]
    if last.get("decision") != "approve":
        die(f"the latest 'sources' answer is '{last.get('decision')}', not approve: run --list again and ask again")
    bez = set(re.findall(r"(?mi)^\s*bez:\s*(\S+)", str(last.get("comment") or "")))
    return last["target"].split("@", 1)[1], bez


MAX_PAGES = 40
MAX_IMAGES, MAX_IMAGE_BYTES, MIN_IMAGE_PX = 40, 8 * 1024 * 1024, 600   # photos worth showing the client


def image_size(data):
    """(width, height) of a JPEG, PNG or WebP from its bytes, or None."""
    import struct
    try:
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", data[16:24])
        if data[:2] == b"\xff\xd8":
            i = 2
            while i + 9 < len(data):
                if data[i] != 0xFF:
                    return None
                m, ln = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
                if m in (0xC0, 0xC1, 0xC2, 0xC3):
                    h, w = struct.unpack(">HH", data[i + 5:i + 9])
                    return w, h
                i += 2 + ln
        if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            k = data[12:16]
            if k == b"VP8 ":
                return struct.unpack("<HH", data[26:30])[0] & 0x3FFF, struct.unpack("<HH", data[26:30])[1] & 0x3FFF
            if k == b"VP8L":
                b = int.from_bytes(data[21:25], "little")
                return (b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1
            if k == b"VP8X":
                return int.from_bytes(data[24:27], "little") + 1, int.from_bytes(data[27:30], "little") + 1
    except Exception:  # noqa: BLE001 - an unreadable header is just no size
        return None
    return None


class Deadline:
    """--max-seconds: one monotonic deadline for the whole fetch, pages and images alike; a request gets at most
    30 s and never more than what is left, and none starts after the deadline."""
    def __init__(self, seconds):
        import time as _t
        self.t, self.end, self.hit = _t, _t.monotonic() + seconds, False

    def over(self):
        if self.t.monotonic() >= self.end:
            self.hit = True
        return self.hit

    def timeout(self):
        left = self.end - self.t.monotonic()
        if left <= 0.05:
            self.hit = True
            return None
        return min(30.0, left)


def fetch_images(outdir, found, allow_local, dl=None):
    """The old site's images (any public host - photos often sit on a CDN), each at most 8 MB, image/* only, no
    redirect into a private network; kept when at least MIN_IMAGE_PX on the longer side. Saved as img/<sha8>.<ext>.
    Returns the list for fetch.json: url, page, alt, file, bytes, width, height (or status when not kept)."""
    out, done = [], set()
    imgdir = os.path.join(outdir, "img")
    os.makedirs(imgdir, mode=0o700, exist_ok=True)
    for url, page, alt in found:
        if url in done or len([x for x in out if x.get("file")]) >= MAX_IMAGES:
            continue
        done.add(url)
        rec = {"url": url, "page": page, "alt": alt, "description": alt or ""}   # fix 23: the agent describes what alt does not
        to = dl.timeout() if dl else 30
        if to is None:
            out.append(rec | {"status": "nedoměřeno: strop času"}); continue
        try:
            k = site_key(url, allow_local)
            opener = urllib.request.build_opener(_SameSite(k, allow_local))
            with opener.open(urllib.request.Request(url, headers={"User-Agent": "aid-ui-sources"}), timeout=to) as r:
                ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
                if not ctype.startswith("image/") or ctype == "image/svg+xml":
                    out.append(rec | {"status": "skipped (%s)" % (ctype or "unknown type")}); continue
                data = b""
                while len(data) <= MAX_IMAGE_BYTES:
                    if dl and dl.over():
                        raise TimeoutError("nedoměřeno: strop času")
                    chunk = r.read1(65536) if hasattr(r, "read1") else r.read(65536)   # what has arrived, so the deadline is checked between chunks
                    if not chunk:
                        break
                    data += chunk
            if len(data) > MAX_IMAGE_BYTES:
                out.append(rec | {"status": "over 8 MB"}); continue
            size = image_size(data)
            if not size or max(size) < MIN_IMAGE_PX:
                out.append(rec | {"status": "too small or unreadable", "width": size[0] if size else None, "height": size[1] if size else None}); continue
            ext = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}.get(ctype, "img")
            sha8 = hashlib.sha256(data).hexdigest()[:8]
            name = "img/%s.%s" % (sha8, ext)
            if any(x.get("file") == name for x in out):   # the same picture under another address
                continue
            with _open_new(os.path.join(outdir, name)) as fh:
                fh.write(data)
            out.append(rec | {"file": name, "bytes": len(data), "width": size[0], "height": size[1], "sha256": hashlib.sha256(data).hexdigest()})
        except Exception as e:  # noqa: BLE001 - a failed image is a listed image, not a crash
            out.append(rec | {"status": str(e)[:160]})
    return out


class _Links(html.parser.HTMLParser):
    """href values of <a> and <base> - a parser, not a regex, so case, quoting and entities do not matter -
    and the images of the page (P113a, 13. 10. 2026: the old site's own photos were never fetched): <img> src and
    the largest srcset entry with its alt, og:image, and url(...) in inline styles."""
    def __init__(self):
        super().__init__(); self.hrefs = []; self.base = None; self.images = []
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == "a" and d.get("href"):
            self.hrefs.append(d["href"])
        elif tag == "base" and d.get("href") and self.base is None:
            self.base = d["href"]
        if tag == "img":
            src = d.get("src") or d.get("data-src")
            if d.get("srcset"):   # the widest candidate
                best = max(((p.strip().split() + ["0w"])[:2] for p in d["srcset"].split(",") if p.strip()),
                           key=lambda x: int(re.sub(r"\D", "", x[1]) or 0), default=None)
                src = best[0] if best else src
            if src:
                self.images.append((src, d.get("alt") or ""))
        if tag == "meta" and (d.get("property") or "").lower() == "og:image" and d.get("content"):
            self.images.append((d["content"], ""))
        for m in re.finditer(r"url\(['\"]?([^'\")]+)['\"]?\)", d.get("style") or ""):
            self.images.append((m.group(1), ""))


def site_key(url, allow_local):
    """(scheme, host, port) of a URL the fetcher may touch: http(s), no credentials, a public address
    (loopback and private ranges only with --allow-local, for tests and intranets). Raises ValueError.
    Known limit: the address is checked here and resolved again by urllib when it connects, so a DNS
    name that changes its answer between the two (rebinding) is not caught; the fetcher runs on the
    agent's host for a URL the PM named, not as a service for strangers (IMP-690)."""
    import ipaddress, socket
    u = urllib.parse.urlparse(url)
    if u.scheme not in ("http", "https"):
        raise ValueError("jen http(s)")
    if u.username or u.password:
        raise ValueError("adresa s přihlašovacími údaji")
    host = (u.hostname or "").lower()
    if not host or not re.fullmatch(r"[a-z0-9.-]+", host):
        raise ValueError("neplatný název hosta")
    port = u.port or (443 if u.scheme == "https" else 80)
    if not allow_local:
        try:
            infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
        except socket.gaierror:
            raise ValueError("host nejde přeložit")
        for info in infos:
            ip = ipaddress.ip_address(info[4][0])
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
                raise ValueError("adresa vede do vnitřní sítě (%s)" % ip)
    return u.scheme, host, port


class _SameSite(urllib.request.HTTPRedirectHandler):
    """Redirects stay on the site being fetched (host and port), at most five, never to a local address."""
    def __init__(self, key, allow_local):
        super().__init__(); self.key = key; self.allow_local = allow_local; self.hops = 0
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.hops += 1
        if self.hops > 5:
            raise urllib.error.HTTPError(newurl, code, "příliš mnoho přesměrování", headers, fp)
        k = site_key(newurl, self.allow_local)
        if k[1:] != self.key[1:]:
            raise urllib.error.HTTPError(newurl, code, "přesměrování mimo web (%s)" % k[1], headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_page(url, key, allow_local, timeout=30, dl=None):
    """(status, content type, bytes, final url) of one page; the body is read in chunks up to MAX_BYTES, and the
    deadline is checked between chunks (a server dripping bytes cannot hold the read past it)."""
    handler = _SameSite(key, allow_local)
    opener = urllib.request.build_opener(handler)
    with opener.open(urllib.request.Request(url, headers={"User-Agent": "aid-ui-sources"}), timeout=timeout) as r:
        ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype not in ("text/html", "application/xhtml+xml"):
            return r.status, ctype, b"", r.geturl()
        chunks, total = [], 0
        while True:
            if dl and dl.over():
                raise TimeoutError("nedoměřeno: strop času")
            chunk = r.read1(65536) if hasattr(r, "read1") else r.read(65536)   # what has arrived, so the deadline is checked between chunks
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_BYTES:
                raise ValueError("stránka nad 2 MB")
            chunks.append(chunk)
        return r.status, ctype, b"".join(chunks), r.geturl()


def _open_new(path):
    """A regular file created fresh under a directory the tool made: no symlink is followed, nothing is overwritten."""
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb")


def fetch_site(proj, url, allow_local=False, max_seconds=180):
    """--fetch-site <url>: the home page and the same-site pages it links to (one level, up to MAX_PAGES)
    into .aid-ui/old-site/<host>/, with fetch.json (url, final url, fetched_at, pages) - the record that
    the old site was read live, when, and what exactly. Fails when the home page is not an HTML page."""
    try:
        key = site_key(url, allow_local)
    except ValueError as e:
        die(f"--fetch-site {url}: {e}", 2)
    base = os.path.realpath(os.path.join(proj, ".aid-ui/old-site"))
    os.makedirs(base, mode=0o700, exist_ok=True)
    outdir = os.path.join(base, key[1] + ("" if key[2] in (80, 443) else "-%d" % key[2]))
    if os.path.islink(base) or os.path.islink(outdir) or os.path.commonpath([base, os.path.realpath(outdir)]) != base:
        die(f"--fetch-site: {outdir} is not a plain directory under .aid-ui/old-site", 1)
    os.makedirs(outdir, mode=0o700, exist_ok=True)
    for old in os.listdir(outdir):   # a fresh download replaces the last one; only the tool's own files go
        f = os.path.join(outdir, old)
        if os.path.isfile(f) and not os.path.islink(f):
            os.remove(f)
    imgold = os.path.join(outdir, "img")
    if os.path.isdir(imgold) and not os.path.islink(imgold):
        for old in os.listdir(imgold):
            f = os.path.join(imgold, old)
            if os.path.isfile(f) and not os.path.islink(f):
                os.remove(f)
    seen, queue, pages, names, found = set(), [url], [], set(), []
    home = None
    dl = Deadline(max_seconds)
    while queue and len(pages) < MAX_PAGES:
        u = queue.pop(0).split("#")[0]
        if u in seen:
            continue
        seen.add(u)
        to = dl.timeout()
        if to is None:   # the deadline: what was fetched stays, the rest is listed as not fetched
            pages.append({"url": u, "status": "nedoměřeno: strop času", "file": None})
            break
        try:
            site_key(u, allow_local)
            status, ctype, raw, final = fetch_page(u, key, allow_local, to, dl)
        except Exception as e:  # noqa: BLE001 - every failure is a listed page, not a crash
            pages.append({"url": u, "status": str(e)[:160], "file": None})
            continue
        if not raw:
            pages.append({"url": u, "status": "skipped (%s)" % (ctype or "unknown type"), "file": None})
            continue
        slug = re.sub(r"[^A-Za-z0-9._-]+", "-", urllib.parse.urlparse(u).path.strip("/") or "index")[:60].strip("-.") or "index"
        name = "%s-%s.html" % (slug, hashlib.sha256(u.encode()).hexdigest()[:8])
        if name in names:
            continue
        names.add(name)
        with _open_new(os.path.join(outdir, name)) as fh:
            fh.write(raw)
        pages.append({"url": u, "final_url": final, "status": status, "file": name, "sha256": hashlib.sha256(raw).hexdigest()})
        ip = _Links()   # the images of every page
        try:
            ip.feed(raw.decode("utf-8", errors="replace"))
        except Exception:  # noqa: BLE001
            pass
        iroot = urllib.parse.urljoin(final, ip.base) if ip.base else final
        found += [(urllib.parse.urljoin(iroot, src.replace("&amp;", "&")), u, alt) for src, alt in ip.images]
        if home is None:   # links from the home page only
            home = final
            parser = _Links()
            charset = "utf-8"
            m = re.search(rb'charset=["\']?([A-Za-z0-9_-]+)', raw[:4096])
            if m:
                charset = m.group(1).decode("ascii", "replace")
            try:
                parser.feed(raw.decode(charset, errors="replace"))
            except LookupError:
                parser.feed(raw.decode("utf-8", errors="replace"))
            root = urllib.parse.urljoin(final, parser.base) if parser.base else final
            for href in parser.hrefs:
                full = urllib.parse.urljoin(root, href).split("#")[0]
                try:
                    k = site_key(full, allow_local)
                except ValueError:
                    continue
                if k[1:] == key[1:] and full not in seen and full not in queue:
                    queue.append(full)
    if home is None:
        die(f"--fetch-site {url}: the home page was not fetched as HTML ({pages[0]['status'] if pages else 'no response'})", 1)
    rec = {"version": 1, "url": url, "final_url": home, "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "pages": pages,
           "images": fetch_images(outdir, found, allow_local, dl), "max_seconds": max_seconds}
    rec["truncated"] = dl.over()
    with _open_new(os.path.join(outdir, "fetch.json")) as fh:
        fh.write(json.dumps(rec, ensure_ascii=False, indent=1).encode("utf-8"))
    return outdir


def site_origin(dirpath):
    """What an --old-site folder is: a live download the tool made (when, from where), a backup the PM
    gave (no fetch.json), or a folder whose fetch.json is not the tool's (treated as a backup, said so)."""
    f = os.path.join(dirpath, "fetch.json")
    if not os.path.isfile(f):
        return "záloha (složka %s) - ne živý web" % os.path.basename(os.path.normpath(dirpath))
    try:
        rec = json.load(open(f, encoding="utf-8"))
        ok = rec.get("version") == 1 and isinstance(rec.get("url"), str) and isinstance(rec.get("fetched_at"), str) \
            and re.fullmatch(r"\d{4}-\d{2}-\d{2}T.*", rec["fetched_at"]) and isinstance(rec.get("pages"), list) \
            and any(isinstance(x, dict) and x.get("file") for x in rec["pages"])
    except (OSError, ValueError, AttributeError):
        ok = False
    if not ok:
        return "záloha (složka %s, fetch.json není záznam nástroje) - ne živý web" % os.path.basename(os.path.normpath(dirpath))
    return "staženo %s z %s" % (rec["fetched_at"][:10], re.sub(r"[^\x20-\x7e\u00a0-\uffff]", "", rec["url"])[:120])


def listing(proj, a, outdir):
    requested = set(a.request)
    budget = [MAX_WALK]
    entries = [("project", p, None, proj) for p in project_files(proj)]
    if a.old_site:
        root_rec = os.path.realpath(os.path.join(a.old_site, "fetch.json"))
        imgdir = os.path.realpath(os.path.join(a.old_site, "img")) + os.sep   # photos: fetch.json lists them, they are no text
        entries += [("old_site", p, r, a.old_site) for p, r in walk(a.old_site, budget)
                    if not (p and (os.path.realpath(p) == root_rec or os.path.realpath(p).startswith(imgdir)))]
        origin = site_origin(a.old_site)
    for f in a.from_:
        entries += [("from", p, r, f) for p, r in walk(f, budget)]
    docs, used_n, stopped = [], 0, 0
    for kind, p, r, root in entries:
        if not p:
            stopped += 1
            docs.append({"id": f"stop{stopped}", "kind": kind, "path": "", "used": False, "reason": r} | ({"origin": origin} if kind == "old_site" else {}))
            continue
        it = document(proj, kind, p, r, requested, used_n, outdir, root)
        if kind == "old_site":
            it["origin"] = origin   # live download (when, from where) or a backup - the PM sees which
        used_n += it["used"]
        docs.append(it)
    unknown = requested - {d["id"] for d in docs if d.get("excluded") == "internal"}
    if unknown:
        die(f"--request {', '.join(sorted(unknown))}: no internal document with that id")
    roots = [os.path.realpath(proj)] + sorted({os.path.realpath(x) for x in a.sessions_from})
    cands, secrets = [], sum(d.get("secret_lines_removed", 0) for d in docs)
    files = sorted({f for sd in (a.sessions_dir or [session_dir(proj)]) for f in glob.glob(os.path.join(os.path.abspath(sd), "*.jsonl"))})
    for f in files:
        recs, torn = human_records(f, roots)
        if not recs:
            continue   # no record of this project: never shown
        excerpts = []
        for _, t in recs[:5]:
            red, hits = redact(t)   # the whole record first, then cut: a secret never straddles the cut
            secrets += hits
            excerpts.append(" ".join(red.split())[:300])
        cands.append({"id": item_id("session", f), "file": f, "sha256": sha(f), "records_human": len(recs), "torn_lines": torn,
                      "first_at": recs[0][0], "last_at": recs[-1][0], "excerpts": excerpts})
    docs.sort(key=lambda d: (d["kind"], d["path"], d["id"]))
    cands.sort(key=lambda c: c["file"])
    man = {"sources": docs, "candidates": cands, "roots": roots, "secrets_removed": secrets}
    h = canonical_sha(man)
    man.update(generated_at=now(), manifest_sha256=h)
    snap = os.path.join(outdir, f"manifest-{h[:16]}.json")
    if os.path.exists(snap):
        try:
            same = canonical_sha(json.load(open(snap, encoding="utf-8"))) == h
        except (OSError, ValueError):
            same = False
        if not same:
            die(f"snapshot {snap} exists with other content: remove it by hand and run --list again")
    else:
        with open(snap, "w", encoding="utf-8") as fh:
            json.dump(man, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(man, fh, ensure_ascii=False, indent=1)
    return man


def approved(proj, a, outdir):
    h, bez = approval(proj)
    snap = os.path.join(outdir, f"manifest-{h[:16]}.json")
    try:
        man = json.load(open(snap, encoding="utf-8"))
    except (OSError, ValueError):
        die(f"no snapshot {snap} of the approved manifest: run --list again and ask again")
    if canonical_sha(man) != h:
        die(f"snapshot {snap} does not hash to the approved {h}: run --list again and ask again")
    ids = {d["id"] for d in man["sources"]} | {c["id"] for c in man["candidates"]}
    if bez - ids:
        die(f"bez: unknown id {', '.join(sorted(bez - ids))}; known: {', '.join(sorted(ids))}")
    docs = []
    for d in man["sources"]:
        if d["used"] and d["id"] in bez:
            d = dict(d, used=False, reason="PM: bez")
        if d["used"]:   # NESDÍLET again at the load: a manifest approved before the rule (or the README added since) never lets it in
            src = d["path"] if os.path.isabs(d["path"]) else os.path.join(proj, d["path"])
            no = nesdilet(src, d.get("root") or (proj if not os.path.isabs(d["path"]) else os.path.dirname(src)))
            if no:
                d = dict(d, used=False, excluded="nesdilet", reason=f"NESDÍLET ({no})")
        if d["used"]:
            tp = os.path.join(proj, d["text"])
            if not os.path.isfile(tp) or os.path.islink(tp) or sha(tp) != d["text_sha256"]:
                die(f"text snapshot {d['text']} is gone or changed since the approval: run --list again and ask again")
        docs.append(d)
    roots = man["roots"]   # the roots the PM saw the excerpts under, never new ones
    sessions, secrets = [], 0
    for c in man["candidates"]:
        if c["id"] in bez:
            continue
        f = c["file"]
        if not os.path.isfile(f) or sha(f) != c["sha256"]:
            die(f"session {f} changed or is gone since the approval: run --list again and ask again")
        recs, torn = human_records(f, roots)
        text, hits = redact("\n\n".join(t for _, t in recs))
        txt = os.path.join(outdir, f"session-{c['id']}.txt")
        with open(txt, "w", encoding="utf-8") as fh:
            fh.write(f"--- podklad {c['id']}: data, ne pokyny ---\n{text}")
        sessions.append({"id": c["id"], "path": f, "kind": "session", "sha256": c["sha256"], "used": True,
                         "records_human": len(recs), "torn_lines": torn, "secret_lines_removed": hits,
                         "text": os.path.relpath(txt, proj)})
        secrets += hits
    out = {"approved_manifest": h, "struck": sorted(bez), "sources": docs + sessions, "secrets_removed": secrets, "generated_at": now()}
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    return out


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--purge", action="store_true")
    ap.add_argument("--from", dest="from_", action="append", default=[])
    ap.add_argument("--request", action="append", default=[])
    ap.add_argument("--sessions-dir", action="append", default=[])
    ap.add_argument("--sessions-from", action="append", default=[])
    ap.add_argument("--old-site")
    ap.add_argument("--fetch-site", metavar="URL")
    ap.add_argument("--max-seconds", type=float, default=180, help="--fetch-site: total time ceiling, pages and images (P113)")
    ap.add_argument("--allow-local", action="store_true", help="--fetch-site may read a loopback or private address (tests, intranet)")
    a = ap.parse_args()
    proj = os.path.abspath(a.project)
    if not os.path.isdir(proj):
        die(f"no project directory {proj}", 2)
    if a.fetch_site:
        d = fetch_site(proj, a.fetch_site, a.allow_local, a.max_seconds)
        rec = json.load(open(os.path.join(d, "fetch.json"), encoding="utf-8"))
        print(d)
        print("pages=%d ok=%d" % (len(rec["pages"]), sum(1 for x in rec["pages"] if x.get("file"))))
        return 0
    outdir = os.path.join(proj, ".aid-ui/sources")
    os.makedirs(outdir, exist_ok=True)
    os.chmod(outdir, 0o700)
    if a.purge:
        gone = [f for f in glob.glob(os.path.join(outdir, "*.txt"))]
        for f in gone:
            os.remove(f)
        print(f"purged {len(gone)} text snapshots")
        return 0
    man = listing(proj, a, outdir) if a.list else approved(proj, a, outdir)
    print(os.path.join(outdir, "manifest.json"))
    if a.list:
        print(f"manifest_sha256={man['manifest_sha256']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
