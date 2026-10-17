#!/usr/bin/env python3
"""aid-ui-skeleton.py - the live skeleton of a web from its structure (P113 step 6; struktura-postup.md).

  build <project>
      Writes one page per entry of .aid-ui/structure.json into <project>/site/ (url "/" -> site/index.html,
      "/sluzby/" -> site/sluzby/index.html, a slug with diacritics normalised to ascii), each marked
      <html data-aid-skeleton>: header (brand and phone from the facts register, the navigation, the call to
      action), the page's H1 and its sections as described blocks, the facts a section names (`facts: [keys]`)
      and the footer (`footer.legal_keys`). A fact the register holds as open (under `otevrene`/`open`, or with
      `status: open`) renders "čeká na klienta"; a key the register lacks renders the same with a warning; nothing
      else is written as content. Every page has `meta viewport`. A rebuild rewrites only pages that still carry
      the marker (a built page is kept); a page the skeleton wrote before (.aid-ui/skeleton/manifest.json) whose entry
      left the structure moves to .aid-ui/skeleton/removed/<path>[.<n>] - a page the skeleton never wrote is never
      touched. A symlink anywhere under site/ or .aid-ui/skeleton/, or two urls that normalise to one file, stop the
      build before anything is written; every file is written to a temporary file and renamed. Redirects of the old site (`redirects: [{from, to}]` in structure.json, the
      inventory of struktura-postup.md bod 2) go to .aid-ui/skeleton/redirects.csv; none -> no file.
  check <project>
      Exit 1 when a redirect target is not a page of the tree (fix 74), a skeleton page has not exactly one H1
      (aid-ui-seo-check.py --json, its h1 rows; the checker failing to run fails the check) or the gate's facts_match
      row alone (aid-ui-tool.sh verify with a checks file naming only facts_match, over the skeleton pages served on
      a free local port) does not pass. No redirects file ->
      "bez starého webu".

structure.json: {pages: [{id, url, h1, title, sections: [{id, says, action?, facts?: [keys]}], legal?}],
nav?: [page ids], header?: {brand_key?, phone_key?, cta?: {label, url}}, footer?: {legal_keys?: [keys]},
redirects?: [{from, to}]}. Without nav the page order is the navigation (with a warning).
"""
import csv, html, json, os, re, shutil, subprocess, sys, unicodedata, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "data-aid-skeleton"
OPEN_KEYS = ("otevrene", "open", "ke_kontrole")


def die(msg, code=1):
    print("ERROR: aid-ui-skeleton.py: " + msg, file=sys.stderr)
    sys.exit(code)


def warn(msg):
    print("WARN: " + msg, file=sys.stderr)


def load(p):
    st = os.path.join(p, ".aid-ui", "structure.json")
    try:
        s = json.load(open(st, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"no readable {st} ({e}): the skeleton is built from the approved structure")
    if not isinstance(s.get("pages"), list) or not s["pages"]:
        die(f"{st} has no pages")
    facts = {}
    fy = os.path.join(p, "docs", "content", "facts.yaml")
    if os.path.isfile(fy):
        import yaml
        facts = yaml.safe_load(open(fy, encoding="utf-8")) or {}
    return s, facts


def fact(facts, key):
    """(value, confirmed): open facts and missing keys are not shown, only marked as waiting for the client."""
    for ok in OPEN_KEYS:
        if isinstance(facts.get(ok), dict) and key in facts[ok]:
            return None, False
    v = facts.get(key)
    if v is None:
        return None, None
    if isinstance(v, dict):
        if str(v.get("status", "")).lower() in ("open", "unconfirmed", "ke_kontrole", "ceka"):
            return None, False
        v = v.get("value")
    return (str(v) if v is not None else None), v is not None


def slug(url):
    u = unicodedata.normalize("NFKD", url).encode("ascii", "ignore").decode().lower()
    parts = [re.sub(r"[^a-z0-9]+", "-", x).strip("-") for x in u.strip("/").split("/") if x.strip()]
    return "/".join(x for x in parts if x)


def page_file(site, url):
    s = slug(url)
    return os.path.join(site, s, "index.html") if s else os.path.join(site, "index.html")


def href(url):
    s = slug(url)
    return "/" + (s + "/" if s else "")


def esc(t):
    return html.escape(str(t or ""), quote=True)


def waiting(key):
    return f'<span class="ceka" data-fact="{esc(key)}">čeká na klienta</span>'


def fact_html(facts, key, missing):
    v, ok = fact(facts, key)
    if ok:
        return f'<span data-fact="{esc(key)}">{esc(v)}</span>'
    if ok is None:
        missing.add(key)
    return waiting(key)


def render(s, facts, pg, lang, missing):
    pages = {x["id"]: x for x in s["pages"]}
    nav_ids = s.get("nav") or [x["id"] for x in s["pages"]]
    hd, ft = s.get("header") or {}, s.get("footer") or {}
    brand = fact_html(facts, hd.get("brand_key", "brand"), missing)
    phone_v, phone_ok = fact(facts, hd["phone_key"]) if hd.get("phone_key") else (None, None)
    phone = (f'<a class="tel" href="tel:{esc(re.sub(r"[^+0-9]", "", phone_v))}" data-fact="{esc(hd["phone_key"])}">{esc(phone_v)}</a>' if phone_ok
             else fact_html(facts, hd["phone_key"], missing) if hd.get("phone_key") else "")
    cta = hd.get("cta") or {}
    nav = "".join(f'<li><a href="{esc(href(pages[i]["url"]))}">{esc(pages[i].get("title") or pages[i]["id"])}</a></li>' for i in nav_ids if i in pages)
    secs = []
    for sc in pg.get("sections") or []:
        fs = "".join(f"<p>{fact_html(facts, k, missing)}</p>" for k in sc.get("facts") or [])
        act = f'<p class="akce">Akce: {esc(sc["action"])}</p>' if sc.get("action") else ""
        secs.append(f'<section class="blok" id="{esc(sc.get("id"))}"><p class="popis">{esc(sc.get("says"))}</p>{fs}{act}</section>')
    legal = "".join(f"<li>{fact_html(facts, k, missing)}</li>" for k in ft.get("legal_keys") or [])
    return (f'<!doctype html>\n<html lang="{esc(lang)}" {MARK}>\n<head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f'<title>{esc(pg.get("title") or pg.get("h1") or pg["id"])}</title>'
            '<style>body{font:16px/1.5 system-ui,sans-serif;margin:0}header,main,footer{padding:16px;max-width:1100px;margin:auto}'
            'nav ul{display:flex;flex-wrap:wrap;gap:12px;list-style:none;padding:0}.blok{border:1px solid #888;padding:12px;margin:12px 0}'
            '.ceka{border:1px dashed #a60;padding:0 4px;color:#a60}a{min-height:44px;display:inline-block}</style></head>\n<body>\n'
            f'<header><p class="znacka">{brand}</p><nav><ul>{nav}</ul></nav>{phone}'
            + (f' <a class="cta" href="{esc(cta.get("url", "#"))}">{esc(cta.get("label"))}</a>' if cta.get("label") else "")
            + f'</header>\n<main><h1>{esc(pg.get("h1") or pg.get("title") or pg["id"])}</h1>{"".join(secs)}</main>\n'
            f'<footer><ul>{legal}</ul></footer>\n</body>\n</html>\n')


def no_symlinks(p, *dirs):
    """Refuse before any write: a symlink as site/, .aid-ui/skeleton/ or anywhere under them could lead a write or a
    move out of the project."""
    for d in dirs:
        full = os.path.join(p, d)
        if os.path.islink(full):
            die(f"{full} is a symlink: the skeleton writes only inside the project", 2)
        for root, ds, fs in os.walk(full):
            for x in ds + fs:
                if os.path.islink(os.path.join(root, x)):
                    die(f"{os.path.join(root, x)} is a symlink: the skeleton writes only inside the project", 2)


def write_atomic(f, text):
    tmp = f + ".part-%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, f)


def build(p):
    s, facts = load(p)
    site = os.path.join(p, "site")
    no_symlinks(p, "site", ".aid-ui/skeleton")
    files = {}
    for pg in s["pages"]:   # two urls normalised to one file would overwrite each other silently
        f = page_file(site, pg.get("url") or "/")
        if f in files:
            die(f"urls {files[f]} and {pg.get('url')} both become {os.path.relpath(f, site)}", 2)
        files[f] = pg.get("url")
        if not isinstance(pg.get("url"), str) or not pg["url"].startswith("/"):
            die(f"page {pg.get('id')}: url must be a site path starting with / (got {pg.get('url')!r})", 2)
    for r in s.get("redirects") or []:
        if not (isinstance(r, dict) and isinstance(r.get("from"), str) and r["from"].strip() and isinstance(r.get("to"), str) and r["to"].startswith("/")):
            die(f"redirect {r!r}: needs from (non-empty) and to (a site path starting with /)", 2)
    os.makedirs(site, exist_ok=True)
    real = os.path.realpath(site)
    if not s.get("nav"):
        warn("structure.json has no nav: the page order is the navigation")
    lang = s.get("lang") or "cs"
    want, missing, kept, written = set(), set(), [], []
    for pg in s["pages"]:
        f = page_file(site, pg.get("url") or "/")
        if not os.path.realpath(os.path.dirname(f)).startswith(real) and os.path.exists(os.path.dirname(f)):
            die(f"{f} resolves outside {site}", 2)
        want.add(os.path.relpath(f, site))
        if os.path.isfile(f) and MARK not in open(f, encoding="utf-8", errors="replace").read(4000):
            kept.append(os.path.relpath(f, site))   # a built page: the skeleton never overwrites it
            continue
        os.makedirs(os.path.dirname(f), exist_ok=True)
        write_atomic(f, render(s, facts, pg, lang, missing))
        written.append(os.path.relpath(f, site))
    rd = os.path.join(p, ".aid-ui", "skeleton")
    os.makedirs(rd, exist_ok=True)
    mf = os.path.join(rd, "manifest.json")
    try:
        before = set(json.load(open(mf, encoding="utf-8")).get("pages") or [])
    except (OSError, ValueError):
        before = set()
    removed = []
    for rel in sorted(before - want):   # only what the skeleton wrote itself; a foreign page stays where it is
        src = os.path.join(site, rel)
        if not os.path.isfile(src):
            continue
        dst = os.path.join(rd, "removed", rel)
        n = 1
        while os.path.exists(dst):   # an older removed version is kept, never overwritten
            dst = os.path.join(rd, "removed", rel + ".%d" % n); n += 1
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.replace(src, dst)
        removed.append(rel)
    write_atomic(mf, json.dumps({"pages": sorted(want)}, ensure_ascii=False))
    rf = os.path.join(rd, "redirects.csv")
    if s.get("redirects"):
        import io
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["from", "to"])
        for r in s["redirects"]:
            w.writerow([r["from"], r["to"]])
        write_atomic(rf, buf.getvalue())
    elif os.path.exists(rf):
        os.remove(rf)
    for k in sorted(missing):
        warn(f"fact {k} is not in docs/content/facts.yaml: shown as čeká na klienta")
    print(json.dumps({"written": written, "kept": kept, "removed": removed, "missing_facts": sorted(missing)}, ensure_ascii=False))


def facts_row(p, site, pages, facts, tmp):
    """aid-ui-tool.sh verify with a checks file naming only facts_match (1440, Chromium) over the skeleton pages,
    served for the run on a free local port; [] when every row passes."""
    import socket, http.server, threading, functools
    ck = {"viewports": [1440], "browsers": ["chromium"], "warn_only": [], "applies": {}, "checks": {"facts_match": "skeleton-check"}}
    st = {"build": {"fingerprints": {os.path.relpath(f, site): "skeleton" for f in pages}}}
    json.dump(ck, open(os.path.join(tmp, "checks.json"), "w"))
    json.dump(st, open(os.path.join(tmp, "state.json"), "w"))
    json.dump(facts, open(os.path.join(tmp, "facts.json"), "w"), default=str)
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=site)
    h.log_message = lambda *a: None
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        r = subprocess.run(["bash", os.path.join(HERE, "..", "aid-ui-tool.sh"), "verify", "--state", os.path.join(tmp, "state.json"),
                            "--checks", os.path.join(tmp, "checks.json"), "--site", site, "--base", "http://127.0.0.1:%d/" % srv.server_address[1],
                            "--out", os.path.join(tmp, "out"), "--seo", os.path.join(HERE, "..", "aid-ui-seo-check.py"),
                            "--facts", os.path.join(tmp, "facts.json")], capture_output=True, text=True, timeout=600)
    finally:
        srv.shutdown()
    try:
        rows = json.load(open(os.path.join(tmp, "out", "result.json"), encoding="utf-8"))["rows"]
    except (OSError, ValueError, KeyError):
        die("the gate's facts_match row did not run: " + (r.stderr or r.stdout)[-300:])
    rows = [x for x in rows if x.get("check") == "facts_match"]
    if len(rows) < len(pages):
        die(f"the gate's facts_match row covered {len(rows)} of {len(pages)} skeleton pages: " + (r.stderr or "")[-200:])
    return [f"{x.get('page')}: {x.get('detail')}" for x in rows if x.get("status") != "pass"]


def check(p):
    s, facts = load(p)
    site = os.path.join(p, "site")
    tree = {href(x.get("url") or "/") for x in s["pages"]}
    bad = []
    rf = os.path.join(p, ".aid-ui", "skeleton", "redirects.csv")
    if os.path.isfile(rf):
        for r in csv.DictReader(open(rf, encoding="utf-8")):
            u = urllib.parse.urlsplit(r.get("to") or "")
            if u.scheme or u.netloc or href(u.path) not in tree:
                bad.append(f"redirect {r.get('from')} -> {r.get('to')}: target is not a page of the tree")
    else:
        print("redirects: bez starého webu")
    pages = [os.path.join(r, "index.html") for r, _, fs in os.walk(site) if "index.html" in fs]
    sk = [f for f in pages if MARK in open(f, encoding="utf-8", errors="replace").read(4000)]
    import tempfile
    tmp = tempfile.mkdtemp(prefix="aid-ui-skeleton-check-")
    for f in sk:   # one H1 per page: the SEO gate's own check, read from its JSON; a checker that fails, fails here
        rel = os.path.relpath(f, site)
        js = os.path.join(tmp, re.sub(r"[^a-z0-9]+", "-", rel) + ".json")
        r = subprocess.run([sys.executable, os.path.join(HERE, "..", "aid-ui-seo-check.py"), f, "--json", js], capture_output=True, text=True)
        try:
            rows = json.load(open(js, encoding="utf-8"))
        except (OSError, ValueError):
            die(f"the SEO check did not run on {rel}: {(r.stderr or r.stdout)[-300:]}")
        rows = rows.get("rows", rows) if isinstance(rows, dict) else rows
        h1 = [x for x in rows if isinstance(x, dict) and x.get("check") == "h1" and x.get("level") in ("BLOCKER", "WARN")]
        n = len(re.findall(r"<h1[\s>]", open(f, encoding="utf-8").read(), re.I))
        if n != 1 or h1:
            bad.append(f"{rel}: {n} H1" + (f" ({str(h1[0].get('detail') or h1[0])[:120]})" if h1 else ""))
    if sk:   # claims outside the register: the gate's facts_match row alone, over the served skeleton pages
        bad += facts_row(p, site, sk, facts, tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    for b in bad:
        print("FAIL " + b)
    if bad:
        sys.exit(1)
    print(f"skeleton-check: OK ({len(sk)} skeleton pages, {len(tree)} pages in the tree)")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "check"):
        die("usage: aid-ui-skeleton.py build|check <project>", 2)
    (build if sys.argv[1] == "build" else check)(os.path.abspath(sys.argv[2]))
