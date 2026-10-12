#!/usr/bin/env python3
"""aid-ui-customer-page.py - the page the customer gets at the end of /aid-ui: what they received
(web, brand, visibility on Google and AI search, rules for further development, content;
marketing "připravujeme"). Each area shows its highlights, the rest under <details>; the SEO
tiles are always visible.

  python3 aid-ui-customer-page.py <project> [--out <dir>]     (default <project>/docs/zakaznik)
  python3 aid-ui-customer-page.py <project> --check [--out <dir>]

Every number and fact comes from a machine source, nothing is written by hand:
  docs/design/brand-state.json   structure.pages, variant, content_plan, gate.result_file, build.id
  <gate result>/result.json      rows (pass count without customer_page), matrix (pages, widths, browsers)
  <gate result>/seo-summary.json, seo.json   what the gate's SEO run wrote (no second run)
  DESIGN.md                      description (direction), colors, typography
  docs/content/facts.yaml        brand, audience, place, domain (.value)
  docs/content/copy.json         text parts (without "shared")
  docs/seo/brief.md              the page table (search questions)
  docs/design/design-standard.md components, patterns, platform columns, the WCAG line
  docs/design/brand-package/     symbol/*, logo/*, icons/* (sizes from file names)
  docs/brand/fonts/              the brand font for the sample (copied; missing = system font)
The generator runs only after a green gate: no fail and no not_covered except the customer_page
row, and the result's build id equals the state's build.id. Otherwise exit 1, nothing written.
The data the page was made from is embedded as <script type="application/json" id="customer-data">.

--check (the gate row customer_page): the page exists, its build_id is the gate's build and the
visible text holds no internal word (whole words, case-sensitive). Output `OK|MISSING|FAIL ...`;
exit 0 pass, 1 fail, 3 no page yet (the gate reports not_covered), 2 usage.
"""
import argparse, glob, hashlib, html, json, os, re, shutil, subprocess, sys

INTERNAL = ["PM", "AID", "EPIC", "agent", "agenta", "agentem", "agenti", "agentů", "kapitola", "kapitoly", "kapitolu",
            "kapitole", "kapitol", "schváleno", "SCHVÁLENO", "schválení", "brána", "brány", "bránu", "bráně", "bránou",
            "gate", "Gate", "GATE", "Claude"]
HERE = os.path.dirname(os.path.abspath(__file__))
CRAWLERS = os.path.join(HERE, "../skills/ui-design/coverage/ai-crawlers.json")
E = html.escape


def die(msg, code=1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def rj(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def yq(path, expr):
    r = subprocess.run(["yq", "-o=json", expr, path], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"yq {expr} {path}: {r.stderr.strip()}", 2)
    return json.loads(r.stdout or "null")


def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}
    r = subprocess.run(["yq", "-o=json", "."], input=m.group(1), capture_output=True, text=True)
    return json.loads(r.stdout or "{}") or {}


def section(text, title, level=2):
    m = re.search(r"^%s %s\s*$(.*?)(?=^#{1,%d} |\Z)" % ("#" * level, re.escape(title), level), text, re.M | re.S)
    return m.group(1) if m else ""


def fact(facts, key):
    v = facts.get(key)
    return str(v.get("value") if isinstance(v, dict) else v) if v not in (None, "") else ""


def gather(proj):
    st = rj(os.path.join(proj, "docs/design/brand-state.json"))
    gate = st.get("gate") or {}
    res_file = gate.get("result_file") or ""
    if not res_file or not os.path.exists(res_file):
        die("no gate result yet: the page is made after the gate (step 7)")
    res = rj(res_file)
    # a row the PM accepted by an exception (the same test finish uses) does not stop the page; it is listed
    cov = subprocess.run(["bash", os.path.join(HERE, "aid-ui-state.sh"), "exception-covered", proj, res_file], capture_output=True, text=True)
    if cov.returncode != 0:
        die(f"cannot read the PM's exceptions: {cov.stderr.strip()[:200]}")
    covered = [json.loads(l) for l in cov.stdout.splitlines() if l.strip()]
    key = lambda r: tuple(str(r.get(k) or "") for k in ("check", "page", "viewport", "browser", "role", "state"))
    cov_keys = {key(c["row"]) for c in covered}
    ckf = os.path.join(os.path.dirname(res_file), "checks.json")
    warn_only = set((rj(ckf).get("warn_only") or []) if os.path.isfile(ckf) else [])
    is_open = lambda r: r.get("status") in ("fail", "not_covered") or (r.get("status") == "warn" and r.get("check") not in warn_only)
    open_rows = [r for r in res.get("rows", []) if is_open(r) and r.get("check") != "customer_page" and key(r) not in cov_keys]
    for c in covered:   # the PM's reason is shown to the customer: it must be customer words
        bad = [w for w in INTERNAL if re.search(r"(?<![\wÀ-ž-])%s(?![\wÀ-ž-])" % re.escape(w), str(c.get("reason") or ""))]
        if bad:
            die(f"the PM's reason of the exception for {c['row']['check']} {c['row'].get('page')} contains {', '.join(bad)}; "
                "it is shown on the customer page: ask the PM to word it for the customer (a new exception answer)")
    if open_rows:
        die(f"the gate is not green: {len(open_rows)} open rows (first: {open_rows[0].get('check')} {open_rows[0].get('page')})")
    if gate.get("result_sha256") and hashlib.sha256(open(res_file, "rb").read()).hexdigest() != gate["result_sha256"]:
        die("the gate result changed after it was recorded: run the gate again")
    build = (st.get("build") or {}).get("id")
    if not build or res.get("build_id") != build:
        die("the gate result is not from the current build: run the gate again")
    vdir = os.path.dirname(res_file)
    seo_sum = rj(os.path.join(vdir, "seo-summary.json")) if os.path.exists(os.path.join(vdir, "seo-summary.json")) else None
    seo_rows = rj(os.path.join(vdir, "seo.json")) if os.path.exists(os.path.join(vdir, "seo.json")) else []
    fm = frontmatter(os.path.join(proj, "DESIGN.md"))
    fp = os.path.join(proj, "docs/content/facts.yaml")
    facts = yq(fp, ".") if os.path.exists(fp) else {}
    facts = facts if isinstance(facts, dict) else {}   # an older list-shaped register names no brand fields
    pages = (st.get("structure") or {}).get("pages") or []
    matrix = res.get("matrix") or []
    D = {"build_id": build}

    # web
    desc = str(fm.get("description") or "")
    dname, _, dtext = desc.partition(" - ")
    D["web"] = {"pages": len(pages), "h1": [p.get("h1") or p.get("id") for p in pages],
                # a row that does not apply ("N/A: …") was not run: it is not a passed check
                "checks_passed": sum(1 for r in res.get("rows", []) if r.get("status") == "pass" and r.get("check") != "customer_page"
                                     and not str(r.get("detail", "")).startswith("N/A")),
                "shots": [wd for wd in (1440, 390) if os.path.exists(os.path.join(os.path.dirname(res_file), f"shots/chromium/{wd}/index.html.png"))],
                "checked_pages": len({m["page"] for m in matrix}), "widths": sorted({int(m["viewport"]) for m in matrix}),
                "browsers": sorted({m["browser"] for m in matrix}), "direction": dname.strip(), "direction_text": dtext.strip(),
                "exceptions": sorted({(CHECK_WORDS.get(c["row"]["check"], "technická kontrola webu"), str(c["row"].get("page") or ""),
                                       str(c.get("reason") or "")) for c in covered})}

    # brand
    bp = os.path.join(proj, "docs/design/brand-package")
    home = next((p for p in pages if p.get("url") == "/" or p.get("id") == "home"), pages[0] if pages else {})
    colors = fm.get("colors") or {}
    fams, weights = [], set()
    for t in (fm.get("typography") or {}).values():
        if isinstance(t, dict) and t.get("fontFamily"):
            f = str(t["fontFamily"]).split(",")[0].strip().strip("'\"")
            if f not in fams:
                fams.append(f)
            try:
                weights.add(int(float(t.get("fontWeight"))))
            except (TypeError, ValueError):
                pass   # "bold" or missing: no weight listed
    icons = sorted({int(n) for f in glob.glob(os.path.join(bp, "icons/*")) for n in re.findall(r"(\d+)", os.path.basename(f))})
    D["brand"] = {"name": fact(facts, "brand"), "audience": fact(facts, "audience"), "place": fact(facts, "place"),
                  "domain": fact(facts, "domain"), "slogan": home.get("h1") or "",
                  "symbols": sorted(os.path.basename(f) for f in glob.glob(os.path.join(bp, "symbol/*.svg"))),
                  "logos": sorted(os.path.basename(f) for f in glob.glob(os.path.join(bp, "logo/*.svg"))),
                  # the sample: the logo with the name in colour on light and on dark, else the symbol
                  "logo_sample": sample_pair(glob.glob(os.path.join(bp, "logo/*.svg"))) or sample_pair(glob.glob(os.path.join(bp, "symbol/*.svg"))),
                  "colors": {k: str(v) for k, v in colors.items()}, "fonts": fams, "weights": sorted(weights), "icon_sizes": icons,
                  "favicon": os.path.isfile(os.path.join(bp, "icons/favicon.svg"))}

    # visibility: what the gate's SEO run wrote
    # pages the gate checked (the 404 page is outside the matrix and outside "N / indexable")
    ok = lambda check: {r["page"] for r in seo_rows if r.get("check") == check and r.get("level") == "OK"} & {m["page"] for m in matrix}
    site_ok = lambda check: any(r.get("check") == check and r.get("level") == "OK" for r in seo_rows)
    brief = os.path.join(proj, "docs/seo/brief.md")
    questions = []
    if os.path.exists(brief):
        rows = [l for l in open(brief, encoding="utf-8").read().splitlines() if l.startswith("|")]
        if rows:
            head = [c.strip().lower() for c in rows[0].strip("|").split("|")]
            qi = next((i for i, c in enumerate(head) if "dotaz" in c or "otázk" in c), None)
            for l in rows[2:]:
                cells = [c.strip() for c in l.strip("|").split("|")]
                if qi is not None and qi < len(cells):
                    q = re.sub(r"\s*\((odhad|fakt)\)\s*$", "", cells[qi]).strip()
                    if q and q not in ("—", "-"):
                        questions.append(q)
    crawlers = rj(CRAWLERS)
    pol = (seo_sum or {}).get("ai_policy")
    D["visibility"] = None if seo_sum is None else {
        "indexable": seo_sum.get("indexable_pages", 0), "jsonld_pages": seo_sum.get("pages_with_jsonld", 0),
        "jsonld_types": seo_sum.get("jsonld_types", []), "seo_ok": seo_sum.get("seo", {}).get("OK", 0),
        "seo_warn": seo_sum.get("seo", {}).get("WARN", 0), "title_desc_ok": len(ok("title") & ok("meta-description")),
        "canonical_ok": len(ok("canonical")), "no_js_ok": len(ok("ai-content")), "ai_policy": pol, "llms_txt": bool(seo_sum.get("llms_txt")),
        "sitemap": site_ok("sitemap"), "robots": site_ok("robots"),
        "local": D["brand"]["place"] if (st.get("variant") or {}).get("local") else "",
        "ai_allowed": (crawlers.get("ai_search", []) if pol and pol.get("ai_search") else [])
                      + (crawlers.get("training", []) if pol and pol.get("training") else []),
        "ai_denied": (crawlers.get("ai_search", []) if pol and not pol.get("ai_search") else [])
                     + (crawlers.get("training", []) if pol and not pol.get("training") else []),
        "questions": questions}

    # rules for further development
    ds_path = os.path.join(proj, "docs/design/design-standard.md")
    ds = open(ds_path, encoding="utf-8").read() if os.path.exists(ds_path) else ""
    comp = [m.strip() for m in re.findall(r"^- \*\*([^*:]+)\*\*", section(ds, "Komponenty"), re.M)]
    pat = [m.strip() for m in re.findall(r"^- \*\*([^*]+?):?\*\*", section(ds, "Vzory"), re.M)]
    plat = []
    tbl = re.search(r"^\|\s*\|(.+)\|\s*$", section(ds, "Platformní kontrakt"), re.M)
    if tbl:
        plat = [re.sub(r"\s*\(.*?\)", "", c).strip() for c in tbl.group(1).split("|") if c.strip()]
    wcag = re.search(r"WCAG\s*[\d.]+\s*A{1,3}", ds)
    D["rules"] = {"present": bool(ds.strip()), "components": comp, "patterns": pat, "platforms": plat, "wcag": wcag.group(0) if wcag else "",
                  "button_roles": len(re.findall(r"^\| \d+ \|", section(section(ds, "Komponenty"), "Tlačítka", 3), re.M)),
                  "field_kinds": max(0, len(re.findall(r"^\|", section(section(ds, "Komponenty"), "Pole formuláře", 3), re.M)) - 2)}

    # content
    cp = os.path.join(proj, "docs/content/copy.json")
    copy = rj(cp) if os.path.exists(cp) else {}
    parts = [k for k in copy if not k.startswith("shared")]
    copy_rows = [r for r in res.get("rows", []) if r.get("check") == "copy_review"]
    copy_pages = {r.get("page") for r in copy_rows}
    # a page counts as passed only when every copy_review row of it passed (a covered fail is not passed)
    D["content"] = {"parts": len(parts), "pages": len({k.split(".")[0] for k in parts}),
                    "copy_reviewed": len(copy_pages),
                    "copy_passed": sum(1 for p in copy_pages if all(r.get("status") == "pass" for r in copy_rows if r.get("page") == p)),
                    "pending": list(dict.fromkeys(re.split(r"\s*\(", str(c.get("need", "")))[0].strip() for c in st.get("content_plan") or []
                                if c.get("status") in ("deferred_by_pm", "missing")))}

    # where the web is today (P108, PM 11. 10. 2026: the domain button led nowhere before the launch):
    # the preview from .aid-ui/links.json until the site is deployed; the domain stays as the future address
    lp = os.path.join(proj, ".aid-ui/links.json")
    try:
        links = rj(lp) if os.path.exists(lp) else {}
    except ValueError:
        links = {}
    D["links"] = {"web": str(links.get("web") or ""), "customer": str(links.get("customer") or ""), "brand": str(links.get("brand") or "")}

    # open and decided (P108, PM 10. 10. 2026): what stays open after the run (the agent's and the PM's own
    # items, deferred content with the PM's words, the exceptions the PM granted) and what was decided
    # (every answered question's outcome from the studio history, plus the agent's recorded decisions)
    answers = st.get("answers") or {}
    deferred = [{"need": re.split(r"\s*\(", str(c.get("need", "")))[0].strip(),
                 "words": str((answers.get(c.get("answer")) or {}).get("comment") or "")}
                for c in st.get("content_plan") or [] if c.get("status") == "deferred_by_pm"]
    deferred = [dict(x) for x in {json.dumps(d, sort_keys=True): d for d in deferred}.values()]
    exc = [{"check": CHECK_WORDS.get((e.get("selector") or {}).get("check"), "technická kontrola webu"),
            "page": str((e.get("selector") or {}).get("page") or "").replace("*", ""), "reason": str(e.get("reason") or "")}
           for e in st.get("exceptions") or [] if not e.get("resolved")]
    if st.get("brand_package_waiver"):
        exc.append({"check": "balíček značky", "page": "", "reason": str(st["brand_package_waiver"].get("reason") or "")})
    # the customer reads "zadavateľ" where the state says PM; an outcome written for the PM loses its internal word
    OWNER = {"PM": "zadavateľ", "klient": "klient", "agent": "zhotoviteľ"}
    def customer_words(s):
        return re.sub(r"(?<![\wÀ-ž-])(schváleno|SCHVÁLENO)(?![\wÀ-ž-])", "odsúhlasené", re.sub(r"(?<![\wÀ-ž-])schválení(?![\wÀ-ž-])", "odsúhlasenie", re.sub(r"(?<![\wÀ-ž-])PM(?![\wÀ-ž-])", "zadavateľ", str(s))))
    opened = [{"text": customer_words(i.get("text") or ""), "owner": OWNER.get(str(i.get("owner") or ""), str(i.get("owner") or "")), "due": str(i.get("due") or ""),
               "critical": i.get("critical") is True}
              for i in st.get("open_items") or [] if isinstance(i, dict) and i.get("status") != "done"]
    known = {str(i.get("id")) for i in st.get("open_items") or [] if isinstance(i, dict)}
    decided = []
    hist = os.path.join(proj, ".aid-ui/studio/history.jsonl")
    if os.path.exists(hist):
        with open(hist, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    h = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(h, dict) or h.get("by") != "pm":
                    continue
                if h.get("kind") == "open_item" and isinstance(h.get("text"), str) and re.match(r"\d{4}-\d{2}-\d{2}T", str(h.get("at") or "")):
                    hid = "pm-" + re.sub(r"[^0-9]", "", str(h.get("at")))[:20]
                    if hid not in known:   # the PM's point not yet synced into the state: listed all the same
                        opened.append({"text": customer_words(h["text"][:500]), "owner": "zadavateľ", "due": ""}); known.add(hid)
                    continue
                q, a = h.get("question") or {}, h.get("answer") or {}
                if isinstance(q.get("outcome"), str) and q["outcome"].strip() and a.get("decision") in ("approve", "choose"):
                    decided.append({"at": str(a.get("at") or "")[:10], "outcome": customer_words(q["outcome"].strip())})
    for d in st.get("decisions") or []:
        if isinstance(d, dict) and (d.get("outcome") or d.get("title")):
            decided.append({"at": str(d.get("at") or "")[:10], "outcome": customer_words(d.get("outcome") or d.get("title"))})
    decided = [dict(x) for x in {json.dumps(d, sort_keys=True): d for d in decided}.values()]
    D["zbyva"] = {"open": opened, "deferred": deferred, "exceptions": exc, "decided": decided}
    # FB-30 (P113a): the photos the client still owes, each with where, what, shape, ratio and smallest size
    pf = os.path.join(proj, "docs/content/photos.yaml")
    ph = yq(pf, ".") if os.path.exists(pf) else []
    D["photos"] = [{k: str(x.get(k) or "") for k in ("id", "page", "where", "what", "shape", "ratio", "min_px")}
                   for x in (ph if isinstance(ph, list) else []) if isinstance(x, dict)]
    for x in D["photos"]:   # the client gets every part of each photo's brief, or the page is not made
        if not all(x[k].strip() for k in x) or x["shape"] not in ("rect", "round") or not re.fullmatch(r"\d+:\d+", x["ratio"]) \
                or not re.fullmatch(r"\d+x\d+", x["min_px"]):
            die(f"docs/content/photos.yaml {x['id'] or '?'}: needs id, page, where, what, shape rect|round, ratio W:H and min_px WxH")
    return D, res_file


# check id -> words for the customer (an exception the PM accepted is named on the page)
# every gate check has words here (test-aid-ui-customer-page.bats compares the keys with the gate's CHECKS)
CHECK_WORDS = {"http_200": "dostupnost stránek", "glyph_coverage": "písmo a diakritika", "no_overflow": "šířka stránky",
               "one_line_controls": "tlačítka na jeden řádek", "no_placeholders": "žádné zástupné texty",
               "facts_match": "údaje na stránce", "brand_assets": "logo a ikony", "links_resources": "odkazy a soubory",
               "required_files": "povinné soubory webu", "axe": "přístupnost", "image_weight": "velikost obrázků",
               "lighthouse_mobile": "rychlost na mobilu", "seo": "hledání na Googlu", "app_task_states": "stavy úloh v aplikaci",
               "screenshots_reviewed": "kontrola vzhledu stránek", "no_overlap": "nic se nepřekrývá",
               "brand_consistency": "jednotný vzhled značky", "page_weight": "velikost stránky", "business_minimum": "povinné údaje firmy",
               "ai_search": "AI vyhledávače", "brand_package": "balíček značky", "design_standard_doc": "pravidla vzhledu webu",
               "token_usage": "barvy a písma podle návrhu", "sticky_panels": "přilepené panely", "keyboard": "ovládání klávesnicí",
               "reduced_motion": "omezení pohybu", "touch_targets": "velikost ovládacích prvků na mobilu",
               "safe_area": "okraje displeje telefonu", "privacy_before_consent": "soukromí před souhlasem",
               "vision_doc": "vize produktu", "coverage": "soulad se standardy", "customer_page": "stránka pro zákazníka",
               "copy_review": "kontrola textů", "motion_settled": "doběhnutí animací před měřením", "motion_fidelity": "pohyb podle vzoru",
               "content_without_js": "obsah viditelný i bez skriptu", "first_paint_visible": "obsah viditelný hned po načtení", "form_states": "odeslání formuláře a jeho stavy", "task_test": "zákazník najde cenu, otevírací dobu a objednání do dvou kroků", "photo_slots": "místa pro fotky v přesném tvaru", "form_delivery": "zpráva z formuláře opravdu dojde"}


def cz(n, one, few, many):
    return one if n == 1 else few if 2 <= n <= 4 else many


def render(D):
    w, b, v, r, c = D["web"], D["brand"], D["visibility"], D["rules"], D["content"]
    name = b["name"] or "Web"
    dom = re.sub(r"^https?://", "", b["domain"]).rstrip("/")

    def li(num, text):
        return f'<li><span class="cislo">{E(str(num))}</span><span class="co">{E(text)}</span></li>'

    def kpi(big, small, cls=""):
        return f'<div class="kpi{(" " + cls) if cls else ""}"><strong>{E(big)}</strong><span>{E(small)}</span></div>'

    def more(title, items):
        items = [i for i in items if i]
        return f'<details><summary>Vše ostatní {E(title)}</summary><ul>{"".join(f"<li>{E(i)}</li>" for i in items)}</ul></details>' if items else ""

    widths, browsers = len(w["widths"]), len(w["browsers"])
    areas = []   # (id, title, subtitle in the list, list class, lead, body); an area without content is left out

    def ul(items):
        items = [i for i in items if i]
        return f'<ul class="body">{"".join(items)}</ul>' if items else ""

    # web
    shots = "".join(f'<figure{" class=" + chr(34) + "mobil" + chr(34) if wd == 390 else ""}><img src="www/ukazka-{wd}.png" alt="Úvodní stránka na {"mobilu" if wd == 390 else "počítači"}" loading="lazy">'
                    f'<figcaption>{"Mobil" if wd == 390 else "Počítač"}</figcaption></figure>' for wd in (1440, 390) if wd in w["shots"])
    chk = (f"kontrol prošlo na {widths} {cz(widths, 'šířce', 'šířkách', 'šířkách')} obrazovky "
           f"ve {browsers} {cz(browsers, 'prohlížeči', 'prohlížečích', 'prohlížečích')}")
    areas.append(("web", "Web", f"{w['pages']} {cz(w['pages'], 'stránka', 'stránky', 'stránek')}, mobil i počítač", "",
                  f"Hotový web ve vzhledu „{w['direction']}“: {w['direction_text']}" if w["direction"] else "Hotový web.",
                  ul([li(w["pages"], cz(w["pages"], "stránka", "stránky", "stránek")), li(w["checks_passed"], chk)])
                  + (f'<div class="nahled">{shots}</div>' if shots else "")
                  + more("k webu", [f"Stránky: {', '.join(w['h1'])}." if w["h1"] else "",
                                    f"Kontrola: {w['checked_pages']} × {widths} ({', '.join(str(x) for x in w['widths'])} px) × {browsers} ({', '.join(w['browsers'])}), {w['checks_passed']} kontrol prošlo; kontroly, které se stránky netýkají, se nepočítají.",
                                    ("Výjimky schválené zadavatelem: " + "; ".join(f"{c} ({p or 'celý web'}): {why or 'bez důvodu'}" for c, p, why in w["exceptions"]) + ".") if w["exceptions"] else ""])))
    # brand: only what the package really has
    lum = sorted((h for h in b["colors"].values() if re.fullmatch(r"#[0-9a-fA-F]{6}", h)), key=lambda h: sum(int(h[i:i + 2], 16) for i in (1, 3, 5)))
    bg_dark, bg_light = (lum[0], lum[-1]) if lum else ("#111111", "#ffffff")
    sample = b["logo_sample"]
    logo_html = "".join(f'<div style="background:{bg_dark if "on-dark" in f or "white" in f else bg_light}"><img src="www/{E(f)}" alt="Logo {E(name)}"></div>' for f in sample)
    font = b["fonts"][0] if b["fonts"] else ""
    nsym, nlogo, ncol = len(b["symbols"]), len(b["logos"]), len(b["colors"])
    body = ul([li(nlogo, cz(nlogo, "varianta loga se jménem", "varianty loga se jménem", "variant loga se jménem")) if nlogo else "",
               li(nsym, cz(nsym, "varianta symbolu", "varianty symbolu", "variant symbolu")) if nsym else "",
               li(ncol, cz(ncol, "barva s pevným názvem", "barvy s pevnými názvy", "barev s pevnými názvy")) if ncol else "",
               li(len(b["fonts"]), f"písmo: {', '.join(b['fonts'])}") if font else ""])
    vz = (f'<div class="vz vz-logo">{logo_html}</div>' if logo_html else "")
    if font:
        vz += (f'<div class="vz vz-pismo" style="font-family:{css_font(font)}, system-ui, sans-serif"><div class="velke">{E(b["slogan"])}</div>'
               f'<p>{E(font)}' + (f' – řezy {", ".join(str(x) for x in b["weights"])}' if b["weights"] else "") + '.</p></div>')
    if ncol:
        vz += '<div class="vz barvy">' + "".join(f'<div style="background:{h};color:{"#fff" if dark(h) else "#111"}"><b>{E(k)}</b>{E(h)}</div>'
                                                 for k, h in b["colors"].items() if re.fullmatch(r"#[0-9a-fA-F]{3,8}", h)) + '</div>'
    if body or vz:
        subs = [x for x, ok in (("logo", nlogo or nsym), ("barvy", ncol), ("písmo", font)) if ok]
        areas.append(("znacka", "Značka", ", ".join(subs), "", (b["slogan"] + (f" Pro: {b['audience']}." if b["audience"] else "")).strip(),
                      body + (f'<div class="vzorky">{vz}</div>' if vz else "")
                      + more("ke značce", [f"Ikony a favicony: {', '.join(str(x) for x in b['icon_sizes'])} px." if b["icon_sizes"] else "",
                                           ("Barvy: " + ", ".join(f"{k} {h}" for k, h in b["colors"].items()) + ".") if ncol else ""])))
    # visibility: the tiles are always visible; a project without SEO says so
    if v:
        n = v["indexable"]
        pol = v["ai_policy"]
        if pol:
            ai_big = "AI připraveno" if pol.get("ai_search") else "AI vyhledávače zakázány"
            ai_small = ("AI vyhledávače smí web číst a citovat" if pol.get("ai_search") else "AI vyhledávače web nečtou") + \
                       (", trénink modelů povolen" if pol.get("training") else ", trénink modelů zakázán")
        else:
            ai_big, ai_small = "AI nenastaveno", "politika pro AI roboty zatím není určená"
        tiles = [kpi(f"{v['seo_ok']}", f"kontrol SEO v pořádku, {v['seo_warn']} varování"),
                 kpi(f"{v['title_desc_ok']} / {n}", "stránek s titulkem a popisem v doporučené délce"),
                 kpi(f"{v['jsonld_pages']} / {n}", "stránek se strukturovanými daty" + (f" ({', '.join(v['jsonld_types'])})" if v["jsonld_types"] else "")),
                 kpi(ai_big, ai_small, "ai"),
                 kpi(f"{v['no_js_ok']} / {n}", "stránek čitelných bez JavaScriptu"),
                 kpi(f"{v['canonical_ok']} / {n}", "stránek s kanonickou adresou"),
                 kpi("Mapa webu" if v["sitemap"] else "Bez mapy webu", "sitemap.xml" + (" a robots.txt pro vyhledávače" if v["robots"] else "")),
                 kpi("llms.txt", "soubor pro AI asistenty") if v["llms_txt"] else ""]
        if v["local"]:
            tiles.append(kpi(v["local"].split(",")[0], f"lokální SEO: {v['local']}"))
        areas.append(("viditelnost", "Viditelnost na Googlu a v AI vyhledávačích", "Google a AI vyhledávače", "seo",
                      "Aby vás našli lidé, kteří hledají přesně to, co děláte" + (f" – {v['local']}." if v["local"] else "."),
                      f'<div class="kpis">{"".join(tiles)}</div>'
                      + more("k viditelnosti", [f"Hledané otázky: {', '.join(v['questions'])}." if v["questions"] else "",
                                                f"AI roboti smí číst a citovat: {', '.join(v['ai_allowed'])}." if v["ai_allowed"] else "",
                                                f"AI roboti zakázaní: {', '.join(v['ai_denied'])}." if v["ai_denied"] else "",
                                                "" if v["llms_txt"] else "Soubor llms.txt pro AI asistenty není součástí webu."])))
    else:
        areas.append(("viditelnost", "Viditelnost na Googlu a v AI vyhledávačích", "není součástí zakázky", "seo",
                      "Optimalizace pro vyhledávače není součástí této zakázky.", ""))
    # rules: only with a design standard
    if r["present"]:
        rb = ul([li(len(r["components"]), cz(len(r["components"]), "hotová komponenta", "hotové komponenty", "hotových komponent")) if r["components"] else "",
                 li(len(r["platforms"]), f"{cz(len(r['platforms']), 'platforma', 'platformy', 'platforem')}: {', '.join(p.lower() for p in r['platforms'])}") if r["platforms"] else "",
                 li(r["wcag"].split()[-1], f"přístupnost podle {r['wcag'].rsplit(' ', 1)[0]}") if r["wcag"] else ""])
        measured = (f"Změřeno na hotovém webu: {r['button_roles']} {cz(r['button_roles'], 'role', 'role', 'rolí')} tlačítek, "
                    f"{r['field_kinds']} {cz(r['field_kinds'], 'druh', 'druhy', 'druhů')} polí formuláře.") if r["button_roles"] or r["field_kinds"] else ""
        areas.append(("pravidla", "Pravidla rozvoje", "design standard webu", "",
                      "Design standard: podle něj se web dál rozšiřuje, aniž by se rozpadl vzhled.",
                      rb + more("k pravidlům", [f"Komponenty: {', '.join(r['components'])}." if r["components"] else "",
                                               f"Vzory: {', '.join(r['patterns'])}." if r["patterns"] else "", measured])))
    # content
    if c["parts"] or c.get("copy_reviewed"):
        cb = ul([li(c["parts"], cz(c["parts"], "část textu", "části textu", "částí textu")) if c["parts"] else "",
                 li(c["pages"], cz(c["pages"], "stránka s texty", "stránky s texty", "stránek s texty")) if c["parts"] else "",
                 li(f"{c['copy_passed']}/{c['copy_reviewed']}", "stránek prošlo nezávislou kontrolou textů") if c.get("copy_reviewed") else ""])
        if c["pending"]:
            cb += f'<div class="zbyva"><b>Před spuštěním zbývá:</b> {E(", ".join(c["pending"]))}.</div>'
        areas.append(("obsah", "Obsah", (f"texty: {c['parts']} {cz(c['parts'], 'část', 'části', 'částí')}" if c['parts'] else "kontrola textů"), "", "Texty všech stránek.", cb))
    # what stays open and what was decided (P108)
    z = D.get("zbyva") or {}
    rows = []
    crit = [i for i in z.get("open", []) if i.get("critical")]
    for i in sorted(z.get("open", []), key=lambda i: not i.get("critical")):
        rows.append(f'<li>{"<b>Blokuje zveřejnění:</b> " if i.get("critical") else ""}{E(i["text"])}{(" · " + E(i["owner"])) if i.get("owner") else ""}{(" · do " + E(i["due"])) if i.get("due") else ""}</li>')
    for d in z.get("deferred", []):
        rows.append(f'<li>{E(d["need"])} - doplní se po dodání{(" („" + E(d["words"]) + "“)") if d.get("words") else ""}</li>')
    for e in z.get("exceptions", []):
        rows.append(f'<li>Výjimka zadavatele: {E(e["check"])}{(" (" + E(e["page"]) + ")") if e.get("page") else ""}{(" - " + E(e["reason"])) if e.get("reason") else ""}</li>')
    dec = "".join(f'<li>{E(d["at"])}: {E(d["outcome"])}</li>' for d in z.get("decided", []))
    zb = (f'<div class="zbyva"><b>Publikace blokovaná</b>, dokud nejsou splněny body označené „Blokuje zveřejnění“ ({len(crit)}).</div>' if crit else "") + \
         (f'<ul class="zbyva-list">{"".join(rows)}</ul>' if rows else '<p style="margin:0">Nic otevřeného.</p>') + \
         (f'<details><summary>Přijatá rozhodnutí ({len(z.get("decided", []))})</summary><ul>{dec}</ul></details>' if dec else "")
    photos = D.get("photos") or []
    if photos:   # a frame of the photo's exact shape beside its brief: the client sees what to bring
        def frame(x):
            w, h = (x["ratio"].split(":") + ["1"])[:2] if ":" in x["ratio"] else ("1", "1")
            rad = "50%" if x["shape"] == "round" else "6px"
            return (f'<span aria-hidden="true" style="display:inline-block;width:56px;aspect-ratio:{E(w)}/{E(h)};border-radius:{rad};'
                    'border:1.5px dashed currentColor;vertical-align:middle"></span>')
        trs = "".join(f'<tr><td>{frame(x)}</td><td>{E(x["where"] or x["page"])}</td><td>{E(x["what"])}</td>'
                      f'<td>{"kulatá" if x["shape"] == "round" else "obdélník"} {E(x["ratio"])}</td><td>{E(x["min_px"])} px</td></tr>' for x in photos)
        zb += (f'<h3 style="margin:18px 0 6px">Fotky, které dodáte ({len(photos)})</h3><p style="margin:0 0 8px">Na webu je pro každou '
               f'místo v přesném tvaru; fotka se jen vloží.</p><table class="fotky"><thead><tr><th></th><th>Kde</th><th>Co na ní</th>'
               f'<th>Tvar</th><th>Nejmenší rozměr</th></tr></thead><tbody>{trs}</tbody></table>')
    n_open = len(rows)
    areas.append(("zbyva", "Co zbývá a co bylo rozhodnuto", f"{n_open} {cz(n_open, 'otevřený bod', 'otevřené body', 'otevřených bodů')}, {len(z.get('decided', []))} {cz(len(z.get('decided', [])), 'rozhodnutí', 'rozhodnutí', 'rozhodnutí')}", "",
                  "Co ještě přijde a kdo to dodá; pod tím každé rozhodnutí zadavatele s datem.", zb))
    areas.append(("marketing", "Marketing", '<span class="stitek">připravujeme</span>', "pozdeji", "",
                  '<p style="margin:0;color:var(--muted)">Tahle část ještě není hotová.</p>'))
    # each area points into the brand book's chapter that holds the detail (PM 11. 10. 2026, 3A): the book
    # is the one source of detail, this page the short way in
    CHAPTER = {"web": "smer", "znacka": "logo", "viditelnost": "seo", "pravidla": "komponenty", "obsah": "obsah", "zbyva": "schvaleni"}
    brand = (D.get("links") or {}).get("brand") or ""
    out = []
    for i, (pid, title, _, _, lead, body) in enumerate(areas):
        lead_html = '<span class="stitek">připravujeme</span>' if pid == "marketing" else E(lead)
        detail = f'<p class="kniha"><a href="{E(brand.rstrip("/"))}/#{CHAPTER[pid]}" target="_blank" rel="noopener">Detail v knize značky →</a></p>' if brand and pid in CHAPTER else ""
        out.append(f'<section class="panel" id="{pid}"><div class="hlava"><span class="n">{i + 1:02d}</span><h2>{E(title)}</h2>'
                   f'<p>{lead_html}</p></div><div class="telo">{body}{detail}</div></section>')
    short = {"viditelnost": "Viditelnost"}
    soupis = [(pid, short.get(pid, t), sub, cls) for pid, t, sub, cls, _, _ in areas]
    items = "".join(f'<li{f" class={chr(34)}{cls}{chr(34)}" if cls else ""}><a href="#{pid}"><span class="n">{i + 1:02d}</span><strong>{E(t)}</strong>'
                    f'<span>{sub if pid == "marketing" else E(sub)}</span></a></li>' for i, (pid, t, sub, cls) in enumerate(soupis))
    data = json.dumps(D, ensure_ascii=False).replace("</", "<\\/")
    fonts = '<link rel="stylesheet" href="www/fonts/fonts.css">' if font else ""
    if D["brand"].get("favicon"):   # the client's own tab icon (brand package), copied to www/ by main()
        fonts = '<link rel="icon" href="www/favicon.svg" type="image/svg+xml">' + fonts
    return f"""<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{E(name)} – co jste dostali</title>
{fonts}
<style>{CSS}  .kniha{{margin:14px 0 0;font-size:.95rem}}.kniha a{{text-decoration:underline;text-underline-offset:.15em}}
</style>
</head>
<body>
<div class="wrap">
<header class="top"><b>/aid-ui · {E(name)}</b>{(f'<a class="btn" href="{E(D["links"]["web"])}" target="_blank" rel="noopener">Otevřít web</a>' + (f'<span class="muted" style="margin-left:10px">bude na {E(dom)}</span>' if dom else '')) if D.get("links", {}).get("web") else (f'<a class="btn" href="https://{E(dom)}">{E(dom)}</a>' if dom else '')}</header>
<div class="hero"><h1>Nedostáváte jen vzhled webu.</h1>
<p>Web, značku, místo na Googlu i v AI vyhledávačích, pravidla pro další rozvoj a texty. Tady je všechno pohromadě, u každé části to nejdůležitější a zbytek pod rozbalením.</p></div>
<ol class="soupis" aria-label="Co jste dostali">{items}</ol>
{"".join(out)}
<footer>/aid-ui · {E(name)}{f" · {E(dom)}" if dom else ""}</footer>
</div>
<script type="application/json" id="customer-data">{data}</script>
</body>
</html>
"""


def sample_pair(files):
    """[light, dark] file names: a colour variant and its on-dark twin (white as the dark fallback)."""
    names = sorted(os.path.basename(f) for f in files)
    light = next((f for f in names if "color" in f and "dark" not in f), None)
    darkf = next((f for f in names if "on-dark" in f), None) or next((f for f in names if "white" in f), None)
    return [f for f in (light, darkf) if f]


def css_font(name):
    """A font family as a CSS string, safe inside a style attribute."""
    return '"%s"' % re.sub(r'[^\w \-]', '', name)


def dark(h):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", h.strip())
    if not m:
        return False
    r, g, b = (int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 140


CSS = """
:root{--paper:#f7f7f7;--ink:#090909;--patina:#007b7f;--gold:#f6b20f;--line:rgba(9,9,9,.12);--muted:#5b5b5b;--panel:#fdfdfd;
--shadow:0 1px 2px rgba(9,9,9,.06),0 2px 8px rgba(9,9,9,.05)}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:1152px;margin:0 auto;padding:0 16px}
@media (min-width:720px){.wrap{padding:0 32px}}
img{max-width:100%;display:block}
a{color:var(--patina)}
header.top{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:18px 0;border-bottom:1px solid var(--line)}
.btn{display:inline-block;padding:8px 14px;background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:6px;box-shadow:var(--shadow);font-size:14px;font-weight:600;text-decoration:none;white-space:nowrap}
.hero{display:grid;gap:16px;padding:28px 0 24px}
.hero h1{margin:0;font-size:clamp(40px,7.4vw,76px);line-height:1;letter-spacing:-.035em;font-weight:800}
.hero p{margin:0;color:var(--muted);max-width:34ch}
@media (min-width:900px){.hero{grid-template-columns:1fr 300px;align-items:start}.hero p{padding-top:10px}}
.soupis{list-style:none;margin:0 0 40px;padding:0;display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(160px,1fr))}
.soupis a{display:block;height:100%;padding:14px 16px;background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);color:var(--ink);text-decoration:none}
.soupis a:hover{border-color:var(--patina)}
.soupis .n{font-size:12px;color:var(--patina);font-weight:700;letter-spacing:.08em}
.soupis strong{display:block;font-size:17px;margin:2px 0}
.soupis span:last-child{font-size:13px;color:var(--muted)}
.soupis .seo a{border-color:var(--patina)}
.soupis .pozdeji a{background:transparent;box-shadow:none;border-style:dashed}
.soupis .pozdeji strong{color:var(--muted)}
.stitek{display:inline-block;font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;background:var(--gold);color:var(--ink);padding:1px 6px;border-radius:3px}
section.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:20px;margin-bottom:20px;display:grid;gap:20px;scroll-margin-top:16px}
@media (min-width:900px){section.panel{grid-template-columns:240px 1fr;padding:28px;gap:32px}}
.hlava .n{font-size:12px;color:var(--patina);font-weight:700;letter-spacing:.08em}
.hlava h2{margin:4px 0 6px;font-size:24px;letter-spacing:-.01em}
.hlava p{margin:0;color:var(--muted);font-size:14px}
.telo{min-width:0}
.body{list-style:none;margin:0;padding:0;display:grid;gap:0;background:var(--panel);border:1px solid var(--line);border-radius:6px;overflow:hidden;grid-template-columns:repeat(auto-fit,minmax(190px,1fr))}
.body li{padding:14px 16px;box-shadow:1px 0 0 var(--line),0 1px 0 var(--line)}
.body .cislo{display:block;font-size:28px;font-weight:800;line-height:1.1;letter-spacing:-.02em}
.body .co{display:block;font-size:14px;color:var(--muted)}
details{margin-top:18px;border:1px solid var(--line);border-radius:8px;background:var(--paper)}
summary{cursor:pointer;list-style:none;display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 16px;font-weight:700;font-size:14px;min-height:44px}
summary::-webkit-details-marker{display:none}
summary::after{content:"Detail ▾";flex:none;font-size:13px;font-weight:600;color:var(--patina)}
details[open] summary::after{content:"Skrýt ▴"}
details ul{margin:0;padding:0 16px 14px 34px;font-size:14px;color:#222}
details li{margin:4px 0;overflow-wrap:anywhere}
.vzorky{display:grid;gap:12px;margin-top:16px;grid-template-columns:1fr}
@media (min-width:720px){.vzorky{grid-template-columns:1fr 1fr}}
.vz{border-radius:6px;overflow:hidden;border:1px solid var(--line)}
.vz-logo{display:grid;grid-template-columns:1fr 1fr}
.vz-logo div{display:grid;place-items:center;padding:28px 12px}
.vz-logo img{height:56px;width:auto;max-width:100%}
.vz-pismo{padding:20px}
.vz-pismo .velke{font-weight:800;font-size:34px;line-height:1;letter-spacing:-.02em}
.vz-pismo p{margin:10px 0 0;color:var(--muted);font-size:14px}
.barvy{grid-column:1/-1;display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr))}
.barvy div{padding:40px 10px 8px;font-size:12px;line-height:1.3}
.barvy b{display:block;font-size:13px}
.nahled{display:grid;gap:12px;margin-top:16px;grid-template-columns:1fr;align-items:start}
@media (min-width:720px){.nahled{grid-template-columns:1fr 150px}}
.nahled figure{margin:0;border:1px solid var(--line);border-radius:6px;overflow:hidden}
.nahled img{width:100%;aspect-ratio:1440/900;object-fit:cover;object-position:top}
.nahled .mobil img{aspect-ratio:390/700}
.nahled figcaption{font-size:12px;color:var(--muted);padding:6px 10px;border-top:1px solid var(--line)}
#viditelnost{border-color:var(--patina);box-shadow:inset 0 4px 0 var(--patina),var(--shadow)}
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
@media (max-width:900px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}
.kpi{padding:14px;border-radius:8px;background:var(--paper);border:1px solid var(--line)}
.kpi strong{display:block;font-size:26px;letter-spacing:-.03em;line-height:1.1;overflow-wrap:anywhere}
.kpi span{font-size:13px;color:var(--muted);line-height:1.35;display:block;margin-top:4px}
.kpi.ai{border-color:var(--patina)}.kpi.ai strong{color:var(--patina);font-size:22px;overflow-wrap:normal;hyphens:none}
.zbyva{margin-top:16px;padding:12px 14px;border:1px solid #f0d58a;border-radius:8px;background:#fff8e6;font-size:14px}
#marketing{background:transparent;box-shadow:none;border-style:dashed}
#marketing .hlava h2{color:var(--muted)}
footer{border-top:1px solid var(--line);margin-top:40px;padding:18px 0 40px;font-size:13px;color:var(--muted)}
@media (max-width:520px){.kpi strong{font-size:20px}.kpi.ai strong{font-size:18px}.kpi span{overflow-wrap:anywhere}}
"""


def visible_text(page):
    t = re.sub(r"<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->", " ", page, flags=re.S)
    alts = " ".join(re.findall(r'\balt="([^"]*)"', t))   # alt text is read aloud: it counts
    return html.unescape(re.sub(r"<[^>]+>", " ", t) + " " + alts)


def check(proj, out):
    p = os.path.join(out, "index.html")
    if not os.path.exists(p):
        print(f"MISSING customer page {os.path.relpath(p, proj)} (made after the gate, step 7)")
        return 3
    page = open(p, encoding="utf-8").read()
    m = re.search(r'<script type="application/json" id="customer-data">(.*?)</script>', page, re.S)
    bad = []
    try:
        data = json.loads(m.group(1).replace("<\\/", "</")) if m else None
    except ValueError:
        data = None
    st = rj(os.path.join(proj, "docs/design/brand-state.json"))
    build = (st.get("build") or {}).get("id")
    if not data:
        bad.append("no customer-data (not made by aid-ui-customer-page.py)")
    elif data.get("build_id") != build:
        bad.append("made from another build: generate it again after the gate")
    text = visible_text(page)
    words = sorted({w for w in INTERNAL if re.search(r"(?<![\wÀ-ž-])%s(?![\wÀ-ž-])" % re.escape(w), text)})
    if words:
        bad.append("internal words in the text: " + ", ".join(words))
    for b in bad:
        print("FAIL customer page", b)
    if not bad:
        print("OK customer page")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    proj = os.path.abspath(a.project)
    out = os.path.abspath(a.out or os.path.join(proj, "docs/zakaznik"))
    if a.check:
        return check(proj, out)
    st = rj(os.path.join(proj, "docs/design/brand-state.json"))
    site = os.path.join(proj, (st.get("build") or {}).get("site") or "site")   # a relative site is the project's
    if os.path.commonpath([out, os.path.abspath(site)]) == os.path.abspath(site):
        die("--out points into the website folder: the page would change the build", 2)
    D, res_file = gather(proj)
    page = render(D)
    www = os.path.join(out, "www")
    os.makedirs(www, exist_ok=True)
    shots = os.path.join(os.path.dirname(res_file), "shots/chromium")
    for wd in ("1440", "390"):
        src = os.path.join(shots, wd, "index.html.png")
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(www, f"ukazka-{wd}.png"))
    for f in D["brand"]["logo_sample"]:
        for part in ("logo", "symbol"):
            src = os.path.join(proj, "docs/design/brand-package", part, f)
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(www, f))
                break
    fav = os.path.join(proj, "docs/design/brand-package/icons/favicon.svg")
    if os.path.isfile(fav):
        shutil.copyfile(fav, os.path.join(www, "favicon.svg"))
    fonts = os.path.join(proj, "docs/brand/fonts")
    if os.path.isdir(fonts):
        shutil.copytree(fonts, os.path.join(www, "fonts"), dirs_exist_ok=True)
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write(page)
    print(os.path.join(out, "index.html"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
