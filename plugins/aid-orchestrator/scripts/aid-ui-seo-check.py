#!/usr/bin/env python3
"""aid-ui-seo-check.py - technical SEO gate over built pages, /aid-ui step 6.

  python3 aid-ui-seo-check.py <dir-or-html>... [--base-url URL] [--brief docs/seo/brief.md] [--json out.json]

A directory is a site root: every *.html under it is a page, and robots.txt and
sitemap.xml are checked there. A single .html file gets the page checks only.
BLOCKER = what the SEO standard calls a blocker (noindex, canonical elsewhere,
robots.txt blocking the site, an unreadable page) plus a broken JSON-LD block, a
JSON-LD business whose name, telephone or address (NAP) is not in the page's visible
text, and a brief page that is missing or has another H1; everything else is WARN.
Title 50-60 and description 150-160 chars, img without an alt attribute (alt="" is
decorative, OK), duplicate title/description among indexable pages of one language,
meta keywords, aggregateRating on a type that is not a rateable product/work
(self-serving). A noindex not-found page needs no canonical and no length bounds.
--brief reads the page list only from the table whose header row starts `| URL | H1 |`
(rows `| /o-nas | O nás | ... |`); other tables are ignored, no such table is a BLOCKER.
Optional columns `title`, `meta description` and `JSON-LD` (types, comma separated)
are compared with the page (WARN); a missing column skips that comparison with a note.
A directory with no *.html page is a BLOCKER.

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
# Types Google shows review stars for when a site rates *another* thing; aggregateRating
# on anything else (LocalBusiness, Organization, ...) is the site rating itself.
RATEABLE = {"Book", "Course", "CreativeWorkSeason", "CreativeWorkSeries", "Episode", "Event", "Game",
            "HowTo", "MediaObject", "Movie", "MusicPlaylist", "MusicRecording", "Product", "Recipe",
            "SoftwareApplication"}
HIDDEN = ("script", "style", "template", "title")


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
        self.keywords = False
        self.jsonld = []
        self.items = []  # parsed JSON-LD objects, @graph flattened
        self.text = []  # visible text
        self._hidden = 0
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
            elif name == "keywords":
                self.keywords = True
        elif tag == "link" and "canonical" in a.get("rel", "").lower().split():
            self.canonical = a.get("href", "").strip()
        elif tag == "img" and "alt" not in a:  # alt="" marks a decorative image
            self.img_no_alt += 1
        if tag in HIDDEN:
            self._hidden += 1
        if tag in ("title", "h1") or (tag == "script" and a.get("type", "").lower() == "application/ld+json"):
            self._in, self._buf = ("jsonld" if tag == "script" else tag), []
            if tag == "h1":
                self.h1.append("")  # counted at the start tag, so an unclosed <h1> still counts

    def handle_data(self, data):
        if self._in:
            self._buf.append(data)
        if not self._hidden:
            self.text.append(data)

    def handle_endtag(self, tag):
        if tag in HIDDEN:
            self._hidden = max(0, self._hidden - 1)
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


def squash(s):
    """Whitespace-free lower case, for 'is this value in the visible text'."""
    return re.sub(r"\s", "", str(s)).lower()


def same(a, b):
    """Brief vs page: whitespace and dash style do not count."""
    f = lambda s: " ".join(re.sub("[\u2013\u2014]", "-", s).split())
    return f(a) == f(b)


def types(item):
    t = item.get("@type", [])
    return {x for x in (t if isinstance(t, list) else [t]) if isinstance(x, str)}


def check_nap(r, pg):
    text = " ".join(pg.text)
    flat = squash(text)
    phones = [re.sub(r"\D", "", m) for m in re.findall(r"\+?\d[\d\s().-]{6,}\d", text)]
    for item in pg.items:
        if "address" not in item:  # ponytail: a business = an item with an address; nested ones not checked
            continue
        addr = item["address"]
        want = [("name", item.get("name"))]
        if isinstance(addr, dict):
            want += [(k, addr.get(k)) for k in ("streetAddress", "postalCode", "addressLocality")]
        else:
            want.append(("address", addr))
        miss = [k for k, v in want if isinstance(v, str) and v.strip() and squash(v) not in flat]
        tel = re.sub(r"\D", "", str(item.get("telephone", "")))[-9:]
        if tel and not any(p.endswith(tel) for p in phones):
            miss.append("telephone")
        r(not miss, "nap", "JSON-LD matches visible text" if not miss else "not in visible text: " + ", ".join(miss), "BLOCKER")


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

    noindex = pg.noindex = any("noindex" in c for c in pg.robots)
    quiet = nf and noindex  # not in search results: no length bounds, no canonical

    def length(check, v, lo, hi):
        ok = bool(v) and (quiet or lo <= len(v)) and len(v) <= hi
        r(ok, check, "missing" if not v else f"{len(v)} chars" + ("" if ok else f", {lo}-{hi} expected"))

    length("title", pg.title, 50, 60)
    length("meta-description", pg.desc, 150, 160)
    r(len(pg.h1) == 1, "h1", f"{len(pg.h1)} h1")
    r(bool(pg.lang), "lang", pg.lang or "missing on <html>")
    if nf:
        r(True, "noindex", "not-found page, noindex expected" if noindex else "not-found page")
    else:
        r(not noindex, "noindex", "noindex set" if noindex else "indexable", "BLOCKER")
    if not pg.canonical:
        r(quiet, "canonical", "not needed on a noindex not-found page" if quiet else "missing")
    elif base_url and rel is not None:
        cu = urlparse(pg.canonical)
        self_ref = pg.canonical.startswith(base_url.rstrip("/")) and url_path(cu.path) == url_path(rel)
        r(self_ref, "canonical", pg.canonical, "BLOCKER")
    else:
        r(True, "canonical", pg.canonical)
    r(pg.img_no_alt == 0, "img-alt", f"{pg.img_no_alt} img without alt")
    if pg.keywords:
        r(False, "meta-keywords", "present; search engines ignore it and the SEO standard forbids it")
    for i, block in enumerate(pg.jsonld, 1):
        try:
            data = json.loads(block)
            items = data if isinstance(data, list) else [data]
            ok = all(isinstance(x, dict) and "@context" in x and ("@type" in x or "@graph" in x) for x in items)
            r(ok, "json-ld", f"block {i}" + ("" if ok else ": @context or @type missing"), "BLOCKER")
        except ValueError as e:
            r(False, "json-ld", f"block {i}: {e}", "BLOCKER")
            continue
        for x in items:
            if isinstance(x, dict):
                pg.items += [g for g in x.get("@graph", []) if isinstance(g, dict)] or [x]
    for item in pg.items:
        if "aggregateRating" in item and not types(item) & RATEABLE:
            r(False, "aggregate-rating", f"self-serving on {'/'.join(sorted(types(item)))}")
    check_nap(r, pg)
    return pg, nf


def check_duplicates(out, pages):
    """Same title or description on two indexable pages of one language: WARN on the later one."""
    for check, attr in (("duplicate-title", "title"), ("duplicate-description", "desc")):
        seen = {}
        for rel, pg in pages:
            v = getattr(pg, attr)
            if v and not pg.noindex:
                first = seen.setdefault((pg.lang, v), rel)
                if first != rel:
                    out.append(("WARN", rel, check, f"same as {first}"))


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
    # Only the page table (header `| URL | H1 | ...`, as 1s-seo.md prescribes) counts;
    # other tables, e.g. redirects to keep, are ignored.
    rows, table, header = [], None, None
    for ln in lines + [""]:
        if not ln.lstrip().startswith("|"):
            table = None
            continue
        cells = [c.strip().strip("`") for c in ln.strip().strip("|").split("|")]
        if table is None:
            table = [x.lower() for x in cells[:2]] == ["url", "h1"]
            header = header or (table and [x.lower() for x in cells])
        elif table and not set("".join(cells)) <= set("-: "):
            rows.append(cells)
    if not header:
        out.append(("BLOCKER", brief, "brief", "no page table (header | URL | H1 |)"))
        return
    col = {}
    for check, names in (("brief-title", ("title",)), ("brief-description", ("meta description", "description")),
                         ("brief-json-ld", ("json-ld",))):
        col[check] = next((header.index(n) for n in names if n in header), None)
        if col[check] is None:
            out.append(("OK", brief, check, f"no {names[0]} column, comparison skipped"))
    for cells in rows:
        if len(cells) < 2 or not cells[0].startswith("/"):
            continue
        url, h1 = url_path(cells[0]), cells[1]
        pg = found.get(url)
        if pg is None:
            out.append(("BLOCKER", url, "brief-page", "confirmed page not built"))
            continue
        ok = h1 in pg.h1
        out.append(("OK" if ok else "BLOCKER", url, "brief-h1", h1 if ok else f"expected '{h1}', got {pg.h1}"))
        cell = lambda c: cells[col[c]] if col[c] is not None and col[c] < len(cells) else ""
        for check, got in (("brief-title", pg.title), ("brief-description", pg.desc)):
            want = cell(check)
            if want:
                ok = same(want, got or "")
                out.append(("OK" if ok else "WARN", url, check, want if ok else f"expected '{want}', got '{got}'"))
        want = {t.strip() for t in cell("brief-json-ld").split(",") if t.strip()}
        if want:
            have = set().union(*map(types, pg.items)) if pg.items else set()
            miss, extra = sorted(want - have), sorted(have - want)
            detail = "; ".join(filter(None, [miss and "missing " + ", ".join(miss), extra and "not in brief " + ", ".join(extra)]))
            out.append(("WARN" if detail else "OK", url, "brief-json-ld", detail or ", ".join(sorted(want))))


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
            pages, parsed = [], []
            for d, _, files in os.walk(t):
                for fn in sorted(files):
                    if fn.endswith(".html"):
                        rel = os.path.relpath(os.path.join(d, fn), t).replace(os.sep, "/")
                        res = check_page(out, os.path.join(d, fn), rel, a.base_url)
                        if res:
                            found[url_path(rel)] = res[0]
                            pages.append((rel, res[1]))
                            parsed.append((rel, res[0]))
            if not pages:
                out.append(("BLOCKER", t, "pages", "no pages found"))
            check_duplicates(out, parsed)
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
