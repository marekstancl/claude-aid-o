#!/usr/bin/env python3
"""aid-ui-seo-check.py - technical SEO gate over built pages, /aid-ui step 6.

  python3 aid-ui-seo-check.py <dir-or-html>... [--base-url URL] [--brief docs/seo/brief.md] [--json out.json]

A directory is a site root: every *.html under it is a page, and robots.txt and
sitemap.xml are checked there. A single .html file gets the page checks only.
BLOCKER = what the SEO standard calls a blocker (noindex, canonical elsewhere,
robots.txt blocking the site, an unreadable page) plus a broken JSON-LD block and
a brief page that is missing or has another H1; everything else is WARN.
--brief reads the page list from table rows whose cell starts with "/" (the URL)
followed by the H1 cell: `| /o-nas | O nás | ... |`.

Output lines `BLOCKER|WARN|OK <page> <check> <detail>`, blockers first.
Exit: 0 no blocker, 1 blocker, 2 usage. Python stdlib only.
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from urllib.parse import urlparse

NOT_FOUND = re.compile(r"(^|/)(404|_?not-found)(/index)?\.html$")


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.title = None
        self.desc = None
        self.canonical = None
        self.robots = []
        self.h1 = []
        self.img_no_alt = 0
        self.jsonld = []
        self._in = None  # "title" | "h1" | "jsonld"
        self._buf = []

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "html":
            self.lang = a.get("lang", "").strip() or None
        elif tag == "meta":
            name = a.get("name", "").lower()
            if name == "description":
                self.desc = a.get("content", "").strip()
            elif name in ("robots", "googlebot"):
                self.robots.append(a.get("content", "").lower())
        elif tag == "link" and "canonical" in a.get("rel", "").lower().split():
            self.canonical = a.get("href", "").strip()
        elif tag == "img" and not a.get("alt", "").strip():
            self.img_no_alt += 1
        elif tag in ("title", "h1") or (tag == "script" and a.get("type", "").lower() == "application/ld+json"):
            self._in, self._buf = ("jsonld" if tag == "script" else tag), []
            if tag == "h1":
                self.h1.append("")  # counted at the start tag, so an unclosed <h1> still counts

    def handle_data(self, data):
        if self._in:
            self._buf.append(data)

    def handle_endtag(self, tag):
        if self._in and tag == ("script" if self._in == "jsonld" else self._in):
            text = "".join(self._buf).strip()
            if self._in == "title":
                self.title = text
            elif self._in == "h1":
                self.h1[-1] = " ".join(text.split())
            else:
                self.jsonld.append(text)
            self._in = None


def url_path(p):
    """Normalized URL path: /, /o-nas, /blog/clanek (no index.html, .html or trailing /)."""
    p = "/" + p.lstrip("/")
    p = re.sub(r"(^|/)index\.html$", r"\1", p)
    p = re.sub(r"\.html$", "", p)
    return p.rstrip("/") or "/"


def check_page(out, path, rel, base_url):
    name = rel or path
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            src = f.read()
    except OSError as e:
        out.append(("BLOCKER", name, "readable", str(e)))
        return None
    pg = Page()
    try:
        pg.feed(src)
        pg.close()
    except Exception as e:  # malformed HTML never crashes the check
        out.append(("WARN", name, "parse", str(e)))
    nf = bool(NOT_FOUND.search("/" + (rel or os.path.basename(path))))

    def r(ok, check, detail, bad="WARN"):
        out.append(("OK" if ok else bad, name, check, detail))

    t = pg.title
    r(bool(t) and len(t) <= 60, "title", "missing" if not t else f"{len(t)} chars")
    d = pg.desc
    r(bool(d) and len(d) <= 160, "meta-description", "missing" if not d else f"{len(d)} chars")
    r(len(pg.h1) == 1, "h1", f"{len(pg.h1)} h1")
    r(bool(pg.lang), "lang", pg.lang or "missing on <html>")
    noindex = any("noindex" in c for c in pg.robots)
    if nf:
        r(True, "noindex", "not-found page, noindex expected" if noindex else "not-found page")
    else:
        r(not noindex, "noindex", "noindex set" if noindex else "indexable", "BLOCKER")
    if not pg.canonical:
        r(False, "canonical", "missing")
    elif base_url and rel is not None:
        cu = urlparse(pg.canonical)
        self_ref = pg.canonical.startswith(base_url.rstrip("/")) and url_path(cu.path) == url_path(rel)
        r(self_ref, "canonical", pg.canonical, "BLOCKER")
    else:
        r(True, "canonical", pg.canonical)
    r(pg.img_no_alt == 0, "img-alt", f"{pg.img_no_alt} img without alt")
    for i, block in enumerate(pg.jsonld, 1):
        try:
            data = json.loads(block)
            items = data if isinstance(data, list) else [data]
            ok = all(isinstance(x, dict) and "@context" in x and "@type" in x for x in items)
            r(ok, "json-ld", f"block {i}" + ("" if ok else ": @context or @type missing"), "BLOCKER")
        except ValueError as e:
            r(False, "json-ld", f"block {i}: {e}", "BLOCKER")
    return pg, nf


def check_site(out, root, pages):
    robots = os.path.join(root, "robots.txt")
    if os.path.isfile(robots):
        # ponytail: only the "User-agent: * / Disallow: /" case, not per-path rule matching
        agent, blocked = None, False
        for line in open(robots, encoding="utf-8", errors="replace"):
            k, _, v = line.split("#")[0].partition(":")
            k, v = k.strip().lower(), v.strip()
            if k == "user-agent":
                agent = v
            elif k == "disallow" and agent == "*" and v == "/":
                blocked = True
        out.append(("BLOCKER" if blocked else "OK", "robots.txt", "robots", "Disallow: / for *" if blocked else "present"))
    else:
        out.append(("WARN", "robots.txt", "robots", "missing"))
    sitemap = os.path.join(root, "sitemap.xml")
    try:
        locs = {url_path(urlparse(e.text.strip()).path)
                for e in ET.parse(sitemap).iter() if e.tag.endswith("loc") and e.text}
    except (OSError, ET.ParseError) as e:
        out.append(("WARN", "sitemap.xml", "sitemap", "missing" if isinstance(e, OSError) else f"unparsable: {e}"))
        return
    out.append(("OK", "sitemap.xml", "sitemap", f"{len(locs)} url"))
    for rel, nf in pages:
        if not nf:
            listed = url_path(rel) in locs
            out.append(("OK" if listed else "WARN", rel, "in-sitemap", "listed" if listed else "not in sitemap.xml"))


def check_brief(out, brief, found):
    try:
        lines = open(brief, encoding="utf-8").read().splitlines()
    except OSError as e:
        out.append(("BLOCKER", brief, "brief", str(e)))
        return
    rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in lines if ln.lstrip().startswith("|")]
    for cells in rows:
        i = next((n for n, c in enumerate(cells) if c.strip("`").startswith("/")), None)
        if i is None or i + 1 >= len(cells):
            continue
        url, h1 = url_path(cells[i].strip("`")), cells[i + 1]
        pg = found.get(url)
        if pg is None:
            out.append(("BLOCKER", url, "brief-page", "confirmed page not built"))
        else:
            ok = h1 in pg.h1
            out.append(("OK" if ok else "BLOCKER", url, "brief-h1", h1 if ok else f"expected '{h1}', got {pg.h1}"))


def main():
    ap = argparse.ArgumentParser(description="technical SEO gate over built pages")
    ap.add_argument("targets", nargs="+")
    ap.add_argument("--base-url")
    ap.add_argument("--brief")
    ap.add_argument("--json")
    a = ap.parse_args()  # usage error -> exit 2
    out, found = [], {}
    for t in a.targets:
        if os.path.isdir(t):
            pages = []
            for d, _, files in os.walk(t):
                for fn in sorted(files):
                    if fn.endswith(".html"):
                        rel = os.path.relpath(os.path.join(d, fn), t).replace(os.sep, "/")
                        res = check_page(out, os.path.join(d, fn), rel, a.base_url)
                        if res:
                            found[url_path(rel)] = res[0]
                            pages.append((rel, res[1]))
            check_site(out, t, pages)
        elif t.endswith(".html") or os.path.exists(t):
            check_page(out, t, None, a.base_url)
        else:
            out.append(("BLOCKER", t, "readable", "no such file or directory"))
    if a.brief:
        check_brief(out, a.brief, found)
    order = {"BLOCKER": 0, "WARN": 1, "OK": 2}
    out.sort(key=lambda x: order[x[0]])  # stable: keeps page order inside a level
    for line in out:
        print(" ".join(line))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump([dict(zip(("level", "page", "check", "detail"), x)) for x in out], f, ensure_ascii=False, indent=1)
    return 1 if any(x[0] == "BLOCKER" for x in out) else 0


if __name__ == "__main__":
    sys.exit(main())
