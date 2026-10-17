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
      the marker (a built page is kept) and moves any page whose entry left the structure to
      .aid-ui/skeleton/removed/<path>. Redirects of the old site (`redirects: [{from, to}]` in structure.json, the
      inventory of struktura-postup.md bod 2) go to .aid-ui/skeleton/redirects.csv; none -> no file.
  check <project>
      Exit 1 when a redirect target is not a page of the tree (fix 74), a skeleton page has not exactly one H1
      (aid-ui-seo-check.py, its h1 findings) or shows a phone, price, time, count or e-mail the register does not
      cover (the gate's facts_match logic, lib/ui-fidelity/aid-ui-facts.mjs unknownClaims). No redirects file ->
      "bez starého webu".

structure.json: {pages: [{id, url, h1, title, sections: [{id, says, action?, facts?: [keys]}], legal?}],
nav?: [page ids], header?: {brand_key?, phone_key?, cta?: {label, url}}, footer?: {legal_keys?: [keys]},
redirects?: [{from, to}]}. Without nav the page order is the navigation (with a warning).
"""
import csv, html, json, os, re, shutil, subprocess, sys, unicodedata

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


def build(p):
    s, facts = load(p)
    site = os.path.join(p, "site")
    os.makedirs(site, exist_ok=True)
    if not s.get("nav"):
        warn("structure.json has no nav: the page order is the navigation")
    lang = s.get("lang") or "cs"
    want, missing, kept, written = set(), set(), [], []
    for pg in s["pages"]:
        f = page_file(site, pg.get("url") or "/")
        want.add(os.path.realpath(f))
        if os.path.isfile(f) and MARK not in open(f, encoding="utf-8", errors="replace").read(4000):
            kept.append(os.path.relpath(f, site))   # a built page: the skeleton never overwrites it
            continue
        os.makedirs(os.path.dirname(f), exist_ok=True)
        open(f, "w", encoding="utf-8").write(render(s, facts, pg, lang, missing))
        written.append(os.path.relpath(f, site))
    removed = []
    for root, _, files in os.walk(site):
        if "index.html" in files and os.path.realpath(os.path.join(root, "index.html")) not in want:
            rel = os.path.relpath(os.path.join(root, "index.html"), site)
            dst = os.path.join(p, ".aid-ui", "skeleton", "removed", rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(os.path.join(root, "index.html"), dst)
            removed.append(rel)
    rd = os.path.join(p, ".aid-ui", "skeleton")
    os.makedirs(rd, exist_ok=True)
    rf = os.path.join(rd, "redirects.csv")
    if s.get("redirects"):
        with open(rf, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["from", "to"])
            for r in s["redirects"]:
                w.writerow([r.get("from", ""), r.get("to", "")])
    elif os.path.exists(rf):
        os.remove(rf)
    for k in sorted(missing):
        warn(f"fact {k} is not in docs/content/facts.yaml: shown as čeká na klienta")
    print(json.dumps({"written": written, "kept": kept, "removed": removed, "missing_facts": sorted(missing)}, ensure_ascii=False))


def check(p):
    s, facts = load(p)
    site = os.path.join(p, "site")
    tree = {href(x.get("url") or "/") for x in s["pages"]}
    bad = []
    rf = os.path.join(p, ".aid-ui", "skeleton", "redirects.csv")
    if os.path.isfile(rf):
        for r in csv.DictReader(open(rf, encoding="utf-8")):
            to = (r.get("to") or "").split("#")[0]
            if href(to) not in tree:
                bad.append(f"redirect {r.get('from')} -> {r.get('to')}: target is not a page of the tree")
    else:
        print("redirects: bez starého webu")
    pages = [os.path.join(r, "index.html") for r, _, fs in os.walk(site) if "index.html" in fs]
    sk = [f for f in pages if MARK in open(f, encoding="utf-8", errors="replace").read(4000)]
    for f in sk:   # one H1 per page: the SEO gate's own check
        n = len(re.findall(r"<h1[\s>]", open(f, encoding="utf-8").read(), re.I))
        r = subprocess.run([sys.executable, os.path.join(HERE, "..", "aid-ui-seo-check.py"), f], capture_output=True, text=True)
        h1 = [ln for ln in (r.stdout + r.stderr).splitlines() if re.search(r"\bh1\b|H1", ln) and re.search(r"BLOCKER|WARN", ln)]
        if n != 1 or h1:
            bad.append(f"{os.path.relpath(f, site)}: {n} H1" + (f" ({h1[0].strip()[:120]})" if h1 else ""))
    if sk:   # claims outside the register: the gate's facts_match logic over the visible text
        texts = {os.path.relpath(f, site): re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"<(style|script)\b.*?</\1>", " ", open(f, encoding="utf-8").read(), flags=re.S | re.I)))) for f in sk}
        js = ("import {unknownClaims} from %s; const [t, f] = JSON.parse(require('fs').readFileSync(0, 'utf8'));"
              "const out = {}; for (const [k, v] of Object.entries(t)) { const u = unknownClaims(v, f); if (u.length) out[k] = u; } console.log(JSON.stringify(out));")
        mod = json.dumps("file://" + os.path.realpath(os.path.join(HERE, "..", "..", "lib", "ui-fidelity", "aid-ui-facts.mjs")))
        r = subprocess.run(["node", "--input-type=module", "-e", "import {createRequire} from 'module'; const require = createRequire(import.meta.url); " + js % mod],
                           input=json.dumps([texts, facts], default=str), capture_output=True, text=True)
        if r.returncode:
            die("facts check could not run: " + (r.stderr or "")[-300:])
        for k, u in (json.loads(r.stdout or "{}") or {}).items():
            bad.append(f"{k}: not in facts.yaml: {', '.join(u)}")
    for b in bad:
        print("FAIL " + b)
    if bad:
        sys.exit(1)
    print(f"skeleton-check: OK ({len(sk)} skeleton pages, {len(tree)} pages in the tree)")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "check"):
        die("usage: aid-ui-skeleton.py build|check <project>", 2)
    (build if sys.argv[1] == "build" else check)(os.path.abspath(sys.argv[2]))
