#!/usr/bin/env python3
"""aid-ui-seo-check.py - technical SEO gate over built pages, /aid-ui step 6.

  python3 aid-ui-seo-check.py <dir-or-html>... [--base-url URL] [--brief docs/seo/brief.md] [--json out.json]
        [--ai --facts facts.json [--local] [--crawlers ai-crawlers.json] [--summary summary.json]]

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

Also on a site root (WARN, from the coverage map, P103 extension K1/K2): the brand stands
after the topic in the title (needs --facts brand); with --facts place, every page but the legal ones names the
place in its description (description-place, P113a); every indexable page links to the contact
page or a mailto:/tel:; two pages whose text differs only a little (a city swapped, the
doorway pattern); text hidden by an inline style (not the hidden attribute: menus, dialogs); a page further than
3 clicks from the home page or not linked at all; on a site with pages in more than one
language, a page without <link rel="alternate" hreflang>.

--ai adds the checks named ai-* (the gate's ai_search row; BLOCKER unless said otherwise):
  ai-policy    docs/seo/brief.md has the section "Politika AI robotů" with the lines
               "vyhledávání a citace: povolit|zakázat" and "trénink: povolit|zakázat"; with
               --state the brief must be the one the PM approved (an seo_brief answer whose target
               is docs/seo/brief.md@<sha256 of the file>); the agent never decides it (SEO standard)
  ai-robots    robots.txt: the search engines of --crawlers (default ../skills/ui-design/coverage/
               ai-crawlers.json) are not blocked; every ai_search and training robot has its own
               User-agent group and the group follows the policy (Disallow: / = blocked)
  ai-llms      no llms.txt unless the brief says "llms.txt: ano" (SEO standard: never by default)
  breadcrumbs  WARN: an indexable nested page has no BreadcrumbList in its JSON-LD
  ai-jsonld    every indexable page has JSON-LD with a WebPage-like node whose publisher (inline
               or by @id anywhere on the site) names the organisation
  ai-entity    that publisher matches --facts (mapping keys brand, ico, email, telephone, domain;
               a key the register lacks is not compared, brand/ico missing = WARN): name = brand,
               the IČO in `identifier`, never in `taxID` (that is the DIČ); a street address only
               with --local. Other organisations on the page (clients, partners) are not compared.
  ai-content   the page's main text (<main>, else <body>) is in the HTML itself: at least 50
               characters (a page rendered by JavaScript has almost none)
  ai-snippet   no nosnippet / noai / noimageai / max-snippet:0 / data-nosnippet unless the policy
               section says "- úryvky: zakázat"
  ai-date      a date of publication or change on the page (JSON-LD datePublished/dateModified or
               <time>); WARN
--summary writes the numbers the customer page shows (pages, checks OK/WARN/BLOCKER, JSON-LD
types, the AI policy) as JSON; every number there comes from this run.

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
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
HERE = os.path.dirname(os.path.abspath(__file__))
CRAWLERS = os.path.join(HERE, "..", "skills", "ui-design", "coverage", "ai-crawlers.json")
WEBPAGE = {"WebPage", "AboutPage", "ContactPage", "CollectionPage", "FAQPage", "ItemPage", "ProfilePage",
           "QAPage", "SearchResultsPage", "MedicalWebPage", "CheckoutPage", "RealEstateListing"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.nf = False
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
        self.links = []  # href of every <a>
        self.hreflang = []  # hreflang of every <link rel="alternate">
        self.main = []  # text inside <main>
        self.hidden_text = []  # text inside an element hidden by style or the hidden attribute
        self.nosnippet = False
        self.has_time = False
        self._main = 0
        self._styled = []  # stack of open tags hidden by style / hidden attribute
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
        elif tag == "link" and "alternate" in a.get("rel", "").lower().split() and a.get("hreflang"):
            self.hreflang.append(a["hreflang"].strip().lower())
        elif tag == "img" and "alt" not in a:  # alt="" marks a decorative image
            self.img_no_alt += 1
        if tag == "a" and a.get("href"):
            self.links.append(a["href"].strip())
        if "data-nosnippet" in a:
            self.nosnippet = True
        if tag == "time":
            self.has_time = True
        if tag == "main":
            self._main += 1
        style = re.sub(r"\s", "", a.get("style", "").lower())
        if tag not in VOID and ("display:none" in style or "visibility:hidden" in style):
            self._styled.append(tag)
        elif self._styled and tag == self._styled[-1] and tag not in VOID:
            self._styled.append(tag)
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
            if self._main:
                self.main.append(data)
            if self._styled:
                self.hidden_text.append(data)

    def handle_endtag(self, tag):
        if tag == "main":
            self._main = max(0, self._main - 1)
        if self._styled and tag == self._styled[-1]:
            self._styled.pop()
        if tag in HIDDEN:
            self._hidden = max(0, self._hidden - 1)
        if self._in and tag == ("script" if self._in == "jsonld" else self._in):
            text = "".join(self._buf).strip()
            if self._in == "title":
                if self.title is None:   # the document's title is the first one; an inline SVG's <title> later is not it (Coufal 12. 10. 2026)
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
    nf = pg.nf = bool(NOT_FOUND.search("/" + (rel or os.path.basename(path))))

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
    if rel and rel.replace("\\", "/") != "index.html" and not pg.noindex and not nf:   # a nested page of a site says where it is (step 6, Coufal 13. 10.)
        def walk(x):
            if isinstance(x, dict):
                yield x
                for v in x.values():
                    yield from walk(v)
            elif isinstance(x, list):
                for v in x:
                    yield from walk(v)
        crumbs = [i for i in walk(pg.items) if "BreadcrumbList" in types(i)]   # also WebPage -> breadcrumb -> BreadcrumbList
        good = [c for c in crumbs if isinstance(c.get("itemListElement"), list) and len(c["itemListElement"]) >= 2]
        r(bool(good), "breadcrumbs", "BreadcrumbList" if good else ("BreadcrumbList with fewer than two items" if crumbs
          else "nested page without BreadcrumbList in its JSON-LD"))
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


def resolve(rel, href):
    """Site-relative path of an internal link from page `rel`, or None (external, anchor, mail)."""
    u = urlparse(href)
    if u.scheme or u.netloc or not u.path:
        return None
    base = "/" + os.path.dirname(rel or "")
    return url_path(os.path.normpath(os.path.join(base, u.path)) if not u.path.startswith("/") else u.path)


LEGAL_PATH = re.compile(r"ochrana|osobn|gdpr|privacy|cookie|podmienk|podmink|terms|impressum|imprint", re.I)


def check_site_extras(out, parsed, brand, place=""):
    """WARN-level checks over the whole site (title order, contact path, near-duplicates,
    hidden text, click depth). parsed = [(rel, Page)]."""
    from difflib import SequenceMatcher
    idx = [(rel, pg) for rel, pg in parsed if not pg.noindex and not pg.nf]
    paths = {url_path(rel): (rel, pg) for rel, pg in idx}
    contact = next((p for p in paths if re.search(r"kontakt|contact", p)), None)
    for rel, pg in idx:
        if brand and pg.title and brand.lower() in pg.title.lower():
            first = pg.title.lower().find(brand.lower()) == 0 and url_path(rel) != "/"
            out.append(("WARN" if first else "OK", rel, "title-brand-order",
                        "brand first; topic and place belong before it" if first else "topic before brand"))
        links = [resolve(rel, h) for h in pg.links]
        to_contact = any(h.startswith(("mailto:", "tel:")) for h in pg.links) or (contact and contact in links)
        if url_path(rel) != contact:
            out.append(("OK" if to_contact else "WARN", rel, "contact-path",
                        "links to the contact page" if to_contact else "no link to the contact page, mailto: or tel:"))
        # a local business: every page but the legal ones names the place in its description (P113a, Coufal critic)
        if place and pg.desc is not None and not LEGAL_PATH.search(rel):
            stem = place.lower()[:max(3, len(place) - 1)]   # Trenčín/Trenčíne, Brno/Brně; ponytail: Praha/Praze needs a declension table
            has = stem in pg.desc.lower()
            out.append(("OK" if has else "WARN", rel, "description-place", f"names {place}" if has else f"the description does not name {place}"))
        hidden = " ".join(" ".join(pg.hidden_text).split())
        out.append(("WARN" if len(hidden) > 30 else "OK", rel, "hidden-text",
                    f"{len(hidden)} characters hidden by style: {hidden[:60]}" if len(hidden) > 30 else "none"))
    langs = {(pg.lang or "").split("-")[0].lower() for _, pg in idx if pg.lang}
    if len(langs) > 1:  # a multilingual site: every page names its language versions
        for rel, pg in idx:
            out.append(("OK" if pg.hreflang else "WARN", rel, "hreflang",
                        ", ".join(pg.hreflang) if pg.hreflang else f"site has {len(langs)} languages, no hreflang alternates"))
    texts = {rel: " ".join(" ".join(pg.main or pg.text).split())[:4000] for rel, pg in idx}
    rels = sorted(texts)
    for i, a in enumerate(rels):
        for b in rels[i + 1:]:
            if len(texts[a]) > 200 and SequenceMatcher(None, texts[a], texts[b]).quick_ratio() > 0.9 \
                    and SequenceMatcher(None, texts[a], texts[b]).ratio() > 0.9:
                out.append(("WARN", b, "near-duplicate", f"text differs from {a} by less than 10 %"))
    if "/" in paths:
        depth, todo = {"/": 0}, ["/"]
        while todo:
            p = todo.pop(0)
            rel, pg = paths[p]
            for h in pg.links:
                q = resolve(rel, h)
                if q in paths and q not in depth:
                    depth[q] = depth[p] + 1
                    todo.append(q)
        for p, (rel, _) in paths.items():
            d = depth.get(p)
            ok = d is not None and d <= 3
            out.append(("OK" if ok else "WARN", rel, "click-depth",
                        f"{d} clicks from home" if d is not None else "not linked from the site"))


def policy_section(brief_text):
    """The text of the brief's 'Politika AI robotů' section (up to the next heading of the same
    or a higher level), '' when there is none."""
    m = re.search(r"^(#+)\s*Politika AI robot[ůu].*$", brief_text, re.M | re.I)
    if not m:
        return ""
    rest = brief_text[m.end():]
    end = re.search(r"^#{1,%d}\s" % len(m.group(1)), rest, re.M)
    return rest[:end.start()] if end else rest


def ai_policy(brief_text):
    """{'ai_search': True|False, 'training': True|False} from the brief, None when either is missing."""
    sec = policy_section(brief_text)
    if not sec:
        return None
    pol = {}
    for key, label in (("ai_search", r"vyhled[áa]v[áa]n[íi] a citace"), ("training", r"tr[ée]nink")):
        m = re.search(label + r"\s*:\s*(povolit|zak[áa]zat)", sec, re.I)
        if not m:
            return None
        pol[key] = m.group(1).lower() == "povolit"
    return pol


def robots_groups(path):
    groups, cur, agents_open = [], None, False
    for raw in open(path, encoding="utf-8-sig", errors="replace"):
        line = raw.split("#", 1)[0].strip()
        if ":" not in line:
            continue
        k, v = (x.strip() for x in line.split(":", 1))
        k = k.lower()
        if k == "user-agent":
            if not agents_open:
                cur = {"agents": [], "rules": []}
                groups.append(cur)
            cur["agents"].append(v.lower())
            agents_open = True
        elif k in ("allow", "disallow") and cur is not None:
            cur["rules"].append((k, v))
            agents_open = False
        else:
            agents_open = False
    return groups


def robot_state(groups, bot):
    """(explicit group?, blocked from the site root?)"""
    own = [g for g in groups if bot.lower() in g["agents"]]
    use = own or [g for g in groups if "*" in g["agents"]]
    rules = [r for g in use for r in g["rules"]]
    blocked = any(r in rules for r in (("disallow", "/"), ("disallow", "/*"))) and ("allow", "/") not in rules
    return bool(own), blocked


def check_ai_site(out, root, brief_text, crawlers, approved):
    """approved: None (no --state given), else whether the state holds the PM's seo_brief answer
    for exactly this brief file (target docs/seo/brief.md@<sha256>, decision approve)."""
    pol = ai_policy(brief_text)
    out.append(("OK" if pol else "BLOCKER", "brief", "ai-policy",
                (f"AI vyhledávání {'povoleno' if pol['ai_search'] else 'zakázáno'}, trénink "
                 f"{'povolen' if pol['training'] else 'zakázán'}") if pol else
                "no 'Politika AI robotů' section with 'vyhledávání a citace:' and 'trénink:' (the PM decides, step 1s)"))
    if pol and approved is not None:
        out.append(("OK" if approved else "BLOCKER", "brief", "ai-policy",
                    "the PM approved this brief (seo_brief)" if approved else
                    "the brief is not the one the PM approved (no seo_brief answer for its sha256); ask again in step 1s"))
    robots = os.path.join(root, "robots.txt")
    if not os.path.isfile(robots):
        out.append(("BLOCKER", "robots.txt", "ai-robots", "missing; the AI policy cannot be stated"))
    else:
        groups = robots_groups(robots)
        for bot in crawlers.get("search_engines", []):
            _, blocked = robot_state(groups, bot)
            out.append(("BLOCKER" if blocked else "OK", "robots.txt", "ai-robots",
                        f"{bot} blocked: the search engine must crawl the site" if blocked else f"{bot} allowed"))
        if pol:
            for group in ("ai_search", "training"):
                for bot in crawlers.get(group, []):
                    explicit, blocked = robot_state(groups, bot)
                    want_allowed = pol[group]
                    ok = explicit and blocked != want_allowed
                    out.append(("OK" if ok else "BLOCKER", "robots.txt", "ai-robots",
                                f"{bot}: {'allowed' if not blocked else 'blocked'}" + ("" if explicit else ", no own User-agent group")
                                + ("" if ok else f"; the policy says {'allow' if want_allowed else 'block'}")))
    llms = os.path.isfile(os.path.join(root, "llms.txt"))
    agreed = bool(re.search(r"llms\.txt\s*:\s*ano", policy_section(brief_text), re.I))
    out.append(("BLOCKER" if llms and not agreed else "OK", "llms.txt", "ai-llms",
                "present without 'llms.txt: ano' in the brief" if llms and not agreed else ("present, agreed" if llms else "none")))
    return pol


def nodes(items):
    """Every JSON-LD object on the page, nested ones included (publisher, author, …)."""
    out, todo = [], list(items)
    while todo:
        x = todo.pop()
        if isinstance(x, dict):
            out.append(x)
            todo += [v for k, v in x.items() if k != "@context"]
        elif isinstance(x, list):
            todo += x
    return out


def site_ids(parsed):
    """@id -> the fullest node with that id across the whole site."""
    ids = {}
    for _, pg in parsed:
        for n in nodes(pg.items):
            i = n.get("@id")
            if isinstance(i, str) and len(n) > len(ids.get(i, {})):
                ids[i] = n
    return ids


def deref(x, ids):
    if isinstance(x, list):
        x = x[0] if x else None
    if isinstance(x, dict) and set(x) <= {"@id"} and x.get("@id") in ids:
        return ids[x["@id"]]
    return x if isinstance(x, dict) else None


def check_ai_page(out, rel, pg, facts, local, policy_text, ids):
    if pg.noindex or pg.nf:  # the not-found page is never a search result
        return

    def r(ok, check, detail, bad="BLOCKER"):
        out.append(("OK" if ok else bad, rel, check, detail))
    every = nodes(pg.items)
    all_types = set().union(*map(types, every)) if every else set()
    r(bool(pg.items), "ai-jsonld", ", ".join(sorted(all_types)) or "no JSON-LD block")
    page = next((n for n in every if types(n) & WEBPAGE), None)
    org = deref(page.get("publisher"), ids) if page else None
    r(bool(page), "ai-jsonld", "WebPage-like node" if page else "no WebPage-like node (WebPage, AboutPage, ContactPage …)")
    if page:
        r(bool(org and org.get("name")), "ai-jsonld", "publisher: " + str((org or {}).get("name"))
          if org and org.get("name") else "the WebPage has no publisher that names the organisation")
    if org:  # only the site's own organisation (the publisher) is compared with the facts
        missing = [k for k in ("brand", "ico") if not facts.get(k)]
        if missing:
            r(False, "ai-entity", "organisation not checked: the facts register has no " + ", ".join(missing), "WARN")
        brand, ico = (facts.get("brand") or "").strip(), re.sub(r"\D", "", str(facts.get("ico") or ""))
        name = org.get("name")
        if brand:
            ok = isinstance(name, str) and squash(name) == squash(brand)
            r(ok, "ai-entity", f"organisation name {name!r}" + ("" if ok else f", facts say {brand!r}"))
        if ico:
            tax = re.sub(r"\D", "", str(org.get("taxID") or ""))
            ident = re.sub(r"\D", "", json.dumps(org.get("identifier", ""), ensure_ascii=False))
            r(tax != ico, "ai-entity", "IČO not in taxID" if tax != ico else "the IČO is in taxID, which is the DIČ; put it in identifier")
            r(ico in ident, "ai-entity", "IČO in identifier" if ico in ident else "the IČO is not in identifier")
        for key, field, norm in (("email", "email", lambda v: str(v).lower().removeprefix("mailto:")),
                                 ("telephone", "telephone", lambda v: re.sub(r"\D", "", str(v))[-9:]),
                                 ("domain", "url", lambda v: str(v).rstrip("/").lower())):
            if facts.get(key) and org.get(field):
                got, want = norm(org[field]), norm(facts[key])
                ok = got == want or (field == "url" and got.startswith(want))
                r(ok, "ai-entity", f"{field} {org[field]}" + ("" if ok else f", facts say {facts[key]}"))
        addr = org.get("address")
        if isinstance(addr, dict) and addr.get("streetAddress") and not local:
            r(False, "ai-entity", "street address in JSON-LD although the business is not local", "WARN")
    main = " ".join(" ".join(pg.main or pg.text).split())
    r(len(main) >= 50, "ai-content", f"{len(main)} characters of main text in the HTML"
      + ("" if len(main) >= 50 else "; the content is probably rendered by JavaScript"))
    bad = [c for c in pg.robots if re.search(r"nosnippet|noai|noimageai|max-snippet:\s*0", c)]
    if pg.nosnippet:
        bad.append("data-nosnippet")
    agreed = bool(re.search(r"^\s*-\s*úryvky\s*:\s*zakázat", policy_text, re.M | re.I))
    r(not bad or agreed, "ai-snippet", "; ".join(bad) + (" (agreed in the brief)" if bad and agreed else "") if bad else "none")
    dated = pg.has_time or any(k in n for n in every for k in ("dateModified", "datePublished"))
    r(dated, "ai-date", "date on the page" if dated else "no datePublished/dateModified and no <time>", "WARN")


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
        if len(cells) != len(header):   # a "|" inside a cell shifts every later column (Coufal 13. 10.: the description became "Coufal Clinic")
            out.append(("BLOCKER", url_path(cells[0]), "brief-row", f"{len(cells)} cells, the header has {len(header)} (a '|' inside a cell?)"))
            continue
        url, h1 = url_path(cells[0]), cells[1]
        pg = found.get(url)
        if pg is None:
            out.append(("BLOCKER", url, "brief-page", "confirmed page not built"))
            continue
        # P113 (the workshop's V12): every H1 of the page is the brief's - a second H1 that promises something else
        # ("rychle a levně") is not covered by the right one beside it
        ok = bool(pg.h1) and all(x == h1 for x in pg.h1)
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
    ap.add_argument("--ai", action="store_true")
    ap.add_argument("--facts")
    ap.add_argument("--local", action="store_true")
    ap.add_argument("--crawlers", default=CRAWLERS)
    ap.add_argument("--summary")
    ap.add_argument("--state")
    a = ap.parse_args()  # usage error -> exit 2
    out, found = [], {}
    facts = {}
    if a.facts:
        with open(a.facts, encoding="utf-8") as f:
            raw = json.load(f)
        # facts.yaml is a mapping {key: {value, source}} (the skill's register) or, in older
        # projects, a list of {claim, value, source}; only the mapping names brand and ico
        if isinstance(raw, dict):
            facts = {k: (v.get("value") if isinstance(v, dict) else v) for k, v in raw.items() if not isinstance(v, list)}
    brief_text = ""
    if a.brief and os.path.isfile(a.brief):
        brief_text = open(a.brief, encoding="utf-8").read()
    pol, site_pages = None, []
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
            check_site_extras(out, parsed, (facts.get("brand") or "").strip(), str(facts.get("place") or "").strip())
            site_pages += parsed
            if a.ai:
                with open(a.crawlers, encoding="utf-8") as f:
                    crawlers = json.load(f)
                approved = None
                if a.state:
                    import hashlib
                    st = json.load(open(a.state, encoding="utf-8"))
                    sha = hashlib.sha256(open(a.brief, "rb").read()).hexdigest() if brief_text else ""
                    # approve, or a card chosen on the question bound to exactly this brief (the agent rewrites the
                    # brief and asks anew when a card changes it, so a choose on this sha is the brief as shown; 9. 10. 2026)
                    approved = bool(sha) and any(
                        isinstance(v, dict) and v.get("kind") == "seo_brief" and v.get("decision") in ("approve", "choose")
                        and str(v.get("target", "")).endswith("@" + sha) for v in (st.get("answers") or {}).values())
                pol = check_ai_site(out, t, brief_text, crawlers, approved)
                ids = site_ids(parsed)
                for rel, pg in parsed:
                    check_ai_page(out, rel, pg, facts, a.local, policy_section(brief_text), ids)
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
    if a.summary:
        idx = [(rel, pg) for rel, pg in site_pages if not pg.noindex and not pg.nf]
        count = lambda pred: {lv: sum(1 for x in out if x[0] == lv and pred(x[2])) for lv in ("OK", "WARN", "BLOCKER")}
        with open(a.summary, "w", encoding="utf-8") as f:
            json.dump({"indexable_pages": len(idx),
                       "pages_with_jsonld": sum(1 for _, pg in idx if pg.items),
                       "jsonld_types": sorted(set().union(*(types(i) for _, pg in idx for i in pg.items)) if idx else set()),
                       "seo": count(lambda c: not c.startswith("ai-")), "ai": count(lambda c: c.startswith("ai-")),
                       "ai_policy": pol, "llms_txt": any(x[2] == "ai-llms" and x[3].startswith("present") for x in out)},
                      f, ensure_ascii=False, indent=1)
    return 1 if any(x[0] == "BLOCKER" for x in out) else 0


if __name__ == "__main__":
    sys.exit(main())
