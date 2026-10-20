#!/usr/bin/env python3
"""aid-ui-skeleton.py - the live skeleton of a web from its structure (P113 step 6; struktura-postup.md), or of a web
application from its model of screens and tasks (P116, build_app; aplikace-postup.md) - one builder, a branch on the
kind (variant.type webapp in docs/design/brand-state.json, else .aid-ui/variant.json).

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
    if app_kind(p):
        return build_app(p)
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
    if not s.get("nav"):
        warn("structure.json has no nav: the page order is the navigation")
    lang = s.get("lang") or "cs"
    missing = set()
    out = write_pages(p, site, [(page_file(site, pg.get("url") or "/"), lambda pg=pg: render(s, facts, pg, lang, missing)) for pg in s["pages"]])
    rd = os.path.join(p, ".aid-ui", "skeleton")
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
    print(json.dumps(out | {"missing_facts": sorted(missing)}, ensure_ascii=False))


def write_pages(p, site, entries):
    """Write [(file, render)] under site/: a page without the skeleton's mark is a built page and kept; a page the
    skeleton wrote before (manifest) that is no longer wanted moves to .aid-ui/skeleton/removed/. Shared by the web
    and the app skeleton (P116)."""
    os.makedirs(site, exist_ok=True)
    real = os.path.realpath(site)
    want, kept, written = set(), [], []
    for f, render_page in entries:
        if not os.path.realpath(os.path.dirname(f)).startswith(real) and os.path.exists(os.path.dirname(f)):
            die(f"{f} resolves outside {site}", 2)
        want.add(os.path.relpath(f, site))
        if os.path.isfile(f) and MARK not in open(f, encoding="utf-8", errors="replace").read(4000):
            kept.append(os.path.relpath(f, site))   # a built page: the skeleton never overwrites it
            continue
        os.makedirs(os.path.dirname(f), exist_ok=True)
        write_atomic(f, render_page())
        written.append(os.path.relpath(f, site))
    rd = os.path.join(p, ".aid-ui", "skeleton")
    os.makedirs(rd, exist_ok=True)
    mf = os.path.join(rd, "manifest.json")
    try:
        before = set(json.load(open(mf, encoding="utf-8")).get("pages") or [])
    except (OSError, ValueError):
        before = set()
    removed = []
    removed_root = os.path.realpath(os.path.join(rd, "removed"))
    for rel in sorted(before - want):   # only what the skeleton wrote itself; a foreign page stays where it is
        # an entry of the shape the skeleton writes, inside site/ - a hand-edited manifest moves nothing else
        if (not isinstance(rel, str) or os.path.isabs(rel) or ".." in rel.split("/") or not (rel == "index.html" or rel.endswith("/index.html"))
                or page_file(site, "/" + rel[:-len("index.html")]) != os.path.join(site, rel)):
            warn(f"manifest entry {rel!r} is not a skeleton page path: skipped")
            continue
        src = os.path.join(site, rel)
        if not os.path.isfile(src) or os.path.islink(src) or not os.path.realpath(src).startswith(real + os.sep):
            continue
        dst = os.path.join(rd, "removed", rel)
        n = 1
        while os.path.exists(dst):   # an older removed version is kept, never overwritten
            dst = os.path.join(rd, "removed", rel + ".%d" % n); n += 1
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.realpath(os.path.dirname(dst)).startswith(removed_root):
            die(f"{dst} resolves outside {removed_root}", 2)
        os.replace(src, dst)
        removed.append(rel)
    write_atomic(mf, json.dumps({"pages": sorted(want)}, ensure_ascii=False))
    return {"written": written, "kept": kept, "removed": removed}


# --- P116: the skeleton of a web application, from docs/design/screens.json -------------------------------------
STATES = (("empty", "Prázdno"), ("loading", "Načítání"), ("error", "Chyba"), ("filled", "Naplněno"))   # the model's order
APP_JS = """(function(){function failFor(k,e){if(!k)return null;var kind=(e&&/^[0-9]+$/.test(e.message))?'server':'network';   // an HTTP status vs a dropped connection
return document.querySelector('[data-aid-fail-for="'+k+'"][data-aid-fail-kind="'+kind+'"]')||document.querySelector('[data-aid-fail-for="'+k+'"]:not([data-aid-fail-kind])');}
var q=new URLSearchParams(location.search),st=q.get('stav')||'filled',ok=false,done=(q.get('vysledek')||'').split(',');
document.querySelectorAll('main [data-aid-state]').forEach(function(e){if(e.dataset.aidState===st)ok=true;});
if(!ok)st='filled';document.querySelectorAll('main [data-aid-state]').forEach(function(e){e.hidden=e.dataset.aidState!==st;});
document.querySelectorAll('[data-aid-stav-link]').forEach(function(a){if(a.dataset.aidStavLink===st)a.setAttribute('aria-current','true');});
document.querySelectorAll('[data-aid-back]').forEach(function(a){a.addEventListener('click',function(ev){if(document.referrer&&new URL(document.referrer).origin===location.origin){ev.preventDefault();history.back();}});});
var main=document.querySelector('main');if(st==='loading')main.setAttribute('aria-busy','true');
var ts=q.get('stav')||'';document.querySelectorAll('[data-aid-task-state]').forEach(function(e){e.hidden=e.dataset.aidTaskState!==ts;});
document.querySelectorAll('[data-aid-retry]').forEach(function(a){var x=new URL(location.href);x.searchParams.delete('stav');a.setAttribute('href',x.pathname+x.search);});   // the same screen and its id, without the error
var rz=q.get('rezim');try{if(rz)sessionStorage.setItem('aid-rezim',rz);rz=sessionStorage.getItem('aid-rezim');}catch(e){}
var modes=document.querySelector('[data-aid-modes-list]');if(modes){var all=modes.dataset.aidModesList.split(' ');if(all.indexOf(rz)<0)rz=all[0];
document.querySelectorAll('[data-aid-rezim-link]').forEach(function(a){if(a.dataset.aidRezimLink===rz)a.setAttribute('aria-current','true');});
document.querySelectorAll('[data-aid-mode-is]').forEach(function(e){e.hidden=e.dataset.aidModeIs!==rz;});
document.querySelectorAll('[data-aid-modes]').forEach(function(b){var off=b.dataset.aidModes.split(' ').indexOf(rz)<0;b.toggleAttribute('disabled',off);b.setAttribute('aria-disabled',off?'true':'false');
if(b.tagName==='A'){if(off&&b.hasAttribute('href')){b.dataset.href=b.getAttribute('href');b.removeAttribute('href');}else if(!off&&b.dataset.href)b.setAttribute('href',b.dataset.href);}
var r=document.getElementById(b.dataset.aidReason);if(r)r.hidden=!off;});}
var an=document.querySelector('[data-aid-stav-oznameni]');if(an&&q.get('stav'))setTimeout(function(){an.textContent='Zobrazen stav: '+(document.querySelector('[data-aid-stav-link="'+st+'"]')||{}).textContent;},400);   // after load: a reader announces it
document.querySelectorAll('[data-aid-after]').forEach(function(e){e.hidden=done.indexOf(e.dataset.aidAfter)<0;});
document.querySelectorAll('[data-aid-draft]').forEach(function(i){var k='aid-draft:'+location.pathname+':'+i.id;try{var v=localStorage.getItem(k);if(v!==null&&!i.value)i.value=v;}catch(e){}
i.addEventListener('input',function(){try{localStorage.setItem(k,i.value);}catch(e){}});});
document.querySelectorAll('[data-aid-result]').forEach(function(e){e.hidden=done.indexOf(e.dataset.aidResult)<0;});
document.querySelectorAll('dialog[data-aid-confirm]').forEach(function(d){d.close();var b=document.querySelector('[data-aid-action="'+d.dataset.aidConfirm+'"]');
if(b)b.addEventListener('click',function(){d.showModal();d.querySelector('[data-aid-confirm-no]').focus();});
d.querySelector('[data-aid-confirm-no]').addEventListener('click',function(){d.close();if(b)b.focus();});
var y=d.querySelector('[data-aid-confirm-yes]'),ge=document.querySelector('[data-aid-error-global]');
y.setAttribute('role','button');y.addEventListener('keydown',function(ev){if(ev.key===' '){ev.preventDefault();y.click();}});y.addEventListener('click',function(ev){ev.preventDefault();
fetch(y.href).then(function(r){if(!r.ok)throw new Error(r.status);location.href=y.href;}).catch(function(e){d.close();var fe=failFor(d.dataset.aidConfirm,e)||ge;fe.hidden=false;fe.focus();});});});
document.querySelectorAll('a[data-aid-checked]').forEach(function(a){a.addEventListener('click',function(ev){if(!a.href)return;ev.preventDefault();var ge=document.querySelector('[data-aid-error-global]');
fetch(a.href).then(function(r){if(!r.ok)throw new Error(r.status);location.href=a.href;}).catch(function(e){var fe=failFor(a.dataset.aidAction,e)||ge;if(fe){fe.hidden=false;fe.focus();}});});});
document.querySelectorAll('form[data-aid-form]').forEach(function(f){var err=f.querySelector('[data-aid-error]');
f.addEventListener('submit',function(ev){ev.preventDefault();var bad=null;f.querySelectorAll('input,select').forEach(function(i){var e=document.getElementById(i.id+'-chyba');
if(e)e.hidden=i.checkValidity();if(!i.checkValidity()){i.setAttribute('aria-invalid','true');bad=bad||i;}else i.removeAttribute('aria-invalid');});
if(bad){bad.focus();return;}var b=ev.submitter,to=(b&&b.getAttribute('formaction'))||f.getAttribute('action'),d=new URLSearchParams(new FormData(f));
if(b&&b.name)d.set(b.name,b.value);var x=new URL(to,location.href);d.forEach(function(v,k){x.searchParams.set(k,v);});var u=x.pathname+x.search;f.setAttribute('aria-busy','true');if(b)b.disabled=true;
fetch(u).then(function(r){if(!r.ok)throw new Error(r.status);f.querySelectorAll('[data-aid-draft]').forEach(function(i){try{localStorage.removeItem('aid-draft:'+location.pathname+':'+i.id);}catch(e){}});location.href=u;}).catch(function(e){f.removeAttribute('aria-busy');if(b)b.disabled=false;
var fe=(b&&failFor(b.dataset.aidAction,e))||err;fe.hidden=false;fe.focus();});});});})();"""


def app_kind(p):
    """True for a webapp project: the recorded variant, else the studio's .aid-ui/variant.json."""
    for f, key in ((os.path.join(p, "docs", "design", "brand-state.json"), "variant"), (os.path.join(p, ".aid-ui", "variant.json"), None)):
        try:
            d = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        v = d.get(key) if key else d
        if isinstance(v, dict) and v.get("type"):
            return v["type"] == "webapp"
    return False


def screens_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("aid_ui_screens", os.path.join(HERE, "..", "aid-ui-screens.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def gate_attrs(sid, a):
    """An action that goes only in some modes: its modes and the id of the sentence why not."""
    if not a.get("modes"):
        return "", ""
    rid = f"proc-{esc(sid)}-{esc(a['id'])}"
    return (f' data-aid-modes="{esc(" ".join(a["modes"]))}" data-aid-reason="{rid}" aria-describedby="{rid}"',
            f'<span id="{rid}" class="proc" hidden>{esc(a["disabled_reason"])}</span>')


def actions_html(m, scr, url, fields, ends, item=None):
    """The actions of one screen (data-aid-action) and the form of its submit actions. ends: action id -> the tasks it
    ends - a link, a submit button or a confirm carries ?vysledek=<tasks>, and the result shows only then. item None:
    the screen's actions without an item; item k: the actions of sample row k, with their own form holding the inputs
    the tasks give those actions."""
    sid = scr["id"]
    mine = [a for a in scr["actions"] if a.get("item") == item]
    own = {n for t in m["tasks"] for st in t["steps"] if st["screen"] == sid and any(a["id"] == st["action"] and "item" in a for a in scr["actions"])
           for n in st.get("input") or {}}   # inputs that go with an item's action live in that item's form
    if item is None:
        fields = [n for n in fields if n not in own]
    else:
        fields = [n for t in m["tasks"] for st in t["steps"] if st["screen"] == sid and any(a["id"] == st["action"] for a in mine) for n in st.get("input") or {}]
        fields = list(dict.fromkeys(fields))
    then = {t["id"]: t["then_mode"] for t in m["tasks"] if t.get("then_mode")}
    def after_mode(a):   # the mode a task this action ends leaves the app in (STOP -> pozastaveno)
        return next((then[t] for t in ends.get(a["id"]) or [] if t in then), None)
    def tail(a):   # the target's parameters: a deep link (query), the tasks the action ends (vysledek), the mode after them
        ps = ([a["query"]] if a.get("query") else []) + ([f"vysledek={','.join(ends[a['id']])}"] if ends.get(a["id"]) else []) \
            + ([f"rezim={after_mode(a)}"] if after_mode(a) else [])
        return esc("?" + "&".join(ps)) if ps else ""
    # a link whose failure the model names (failure_paths at its step) checks the way first and stays on error (P116 pilot:
    # a plain link that fails lands on the browser's error page, the screen and the way back are gone)
    risky = {t["steps"][fp["at_step"] - 1]["action"] for t in m["tasks"] for fp in t["failure_paths"]
             if fp["at_step"] <= len(t["steps"]) and t["steps"][fp["at_step"] - 1]["screen"] == sid}
    acts, btns = [], []
    for a in mine:
        da = f'data-aid-action="{esc(sid)}.{esc(a["id"])}"' + (f' data-aid-after="{esc(a["after"])}" hidden' if a.get("after") else "")
        owner = next((t for t in m["tasks"] for x in t["steps"] if x["screen"] == sid and x["action"] == a["id"]), None)
        if owner and (a["kind"] != "navigate" or a["id"] in risky):   # the task's own failure text (not the screen's load error), per kind when the model says
            k = f'{esc(sid)}.{esc(a["id"])}'
            acts.append(f'<p class="chyba" role="alert" tabindex="-1" data-aid-fail-for="{k}" hidden>{esc(owner["states"]["failure"])}</p>'
                        + "".join(f'<p class="chyba" role="alert" tabindex="-1" data-aid-fail-for="{k}" data-aid-fail-kind="{"network" if fp["kind"] == "network" else "server"}" hidden>{esc(fp["text"])}</p>'
                                  for fp in owner["failure_paths"] if fp.get("text")))
        if a["kind"] == "navigate":
            back = " data-aid-back" if a.get("back") else ""
            ga, why = gate_attrs(sid, a)
            chk = " data-aid-checked" if a["id"] in risky and not a.get("back") else ""
            if a.get("external"):
                acts.append(f'<a class="akce" href="{esc(a["external"])}" target="_blank" rel="noopener" {da}{ga}>{esc(a["label"])} (otevře se v nové kartě)</a>{why}')
            else:
                acts.append(f'<a class="akce" href="{esc(url[a["to"]])}{tail(a)}" {da}{back}{chk}{ga}>{esc(a["label"])}</a>{why}')
        elif a["kind"] == "submit":
            v = f' name="vysledek" value="{esc(",".join(ends[a["id"]]))}"' if ends.get(a["id"]) else ""
            ga, why = gate_attrs(sid, a)
            q = "&".join(([esc(a["query"])] if a.get("query") else []) + ([f"rezim={esc(after_mode(a))}"] if after_mode(a) else []))
            q = f"?{q}" if q else ""
            btns.append(f'<button type="submit" formaction="{esc(url[a["to"]])}{q}"{v} {da}{ga}>{esc(a["label"])}</button>{why}')
        else:   # destructive: the button opens its confirm dialog (the focus on Zrušit); without JS it stands open under it
            k = f'{esc(sid)}.{esc(a["id"])}'
            ga, why = gate_attrs(sid, a)
            acts.append(f'<button type="button" {da} aria-haspopup="dialog"{ga}>{esc(a["label"])}</button>{why}'
                        f'<dialog open class="potvrzeni" data-aid-confirm="{k}" aria-label="{esc(a["confirm"])}"><p>{esc(a["confirm"])}</p>'
                        f'<a href="{esc(url[a["to"]])}{tail(a)}" data-aid-confirm-yes="{k}">{esc(a.get("confirm_yes") or "Potvrdit")}</a> '
                        f'<button type="button" data-aid-confirm-no>{esc(a.get("confirm_no") or "Zrušit")}</button></dialog>')
    form = ""
    if btns:
        spec = {f["name"]: f for f in scr.get("fields") or []}
        def field(n):
            f = spec.get(n) or {"name": n, "label": n}
            hid, fid = f"h-{esc(sid)}-{esc(n)}", f"f-{esc(sid)}-{esc(n)}"
            hint = f' aria-describedby="{hid} {fid}-chyba"' if f.get("hint") else f' aria-describedby="{fid}-chyba"'
            note = f'<span id="{hid}" class="napoveda">{esc(f["hint"])}</span>' if f.get("hint") else ""
            note += f'<span id="{fid}-chyba" class="chyba-pole" role="alert" hidden>{esc(f.get("error") or "Zkontrolujte hodnotu.")}</span>'
            lim = (" required" if f.get("required") else "") + (" data-aid-draft" if f.get("draft") else "") + (f' maxlength="{f["maxlength"]}"' if f.get("maxlength") else "")
            if "min" in f or "max" in f:
                lim += ' type="number" step="any"' + (f' min="{f["min"]}"' if "min" in f else "") + (f' max="{f["max"]}"' if "max" in f else "")
            if f.get("choices"):
                opts = "".join(f'<option value="{esc(c["value"])}">{esc(c["label"])}</option>' for c in f["choices"])
                return f'<p><label for="f-{esc(sid)}-{esc(n)}">{esc(f["label"])}</label> <select id="f-{esc(sid)}-{esc(n)}" name="{esc(n)}"{hint}>{opts}</select> {note}</p>'
            return f'<p><label for="{fid}">{esc(f["label"])}</label> <input id="{fid}" name="{esc(n)}"{hint}{lim}> {note}</p>'
        inputs = "".join(field(n) for n in fields)
        first = next(a for a in mine if a["kind"] == "submit")
        form = (f'<form method="get" action="{esc(url[first["to"]])}" data-aid-form novalidate>{inputs}'
                f'<p class="chyba" role="alert" tabindex="-1" data-aid-error hidden>{esc(scr["states"]["error"])}</p>{"".join(btns)}</form>')
    return form + (f'<div class="akce">{"".join(acts)}</div>' if acts else "")


STATE_NAMES = (("validation", "chyba validace"), ("empty", "prázdno"), ("loading", "načítání"), ("failure", "selhání"),
               ("permission", "oprávnění"), ("recovery", "obnova po přerušení"))


def app_page(m, scr, approved, fields, results, ends, shell):
    sid = scr["id"]
    url = {x["id"]: (x.get("url") or f"/{x['id']}/") for x in m["screens"]}
    cur = ' aria-current="page"'
    nav = "".join(f'<li><a href="{esc(url[x["id"]])}"{cur if x["id"] == sid else ""}>{esc(x["title"])}</a></li>'
                  for x in m["screens"] if x["nav"] and not x.get("shell"))
    mo = m.get("modes") or []
    msw = ("" if not mo else f'<p class="rezimy" data-aid-modes-list="{esc(" ".join(x["id"] for x in mo))}">Režim (ukázka): '
           + " ".join(f'<a href="?rezim={esc(x["id"])}" data-aid-rezim-link="{esc(x["id"])}" title="{esc(x.get("text") or "")}">{esc(x["label"])}</a>' for x in mo) + "</p>")
    bar = msw + "".join(f'<div class="lista" role="group" data-aid-screen="{esc(x["id"])}" aria-label="{esc(x["title"])}">'
                  + ("" if not mo else '<p class="lista-rezim" role="status">' + "".join(   # the mode now, with what it means (P116 pilot: the bar said Demo běží in every mode)
                      f'<span data-aid-mode-is="{esc(md["id"])}"{"" if i == 0 else " hidden"}>{esc(md["label"])}' + (f': {esc(md["text"])}' if md.get("text") else "") + '</span>'
                      for i, md in enumerate(mo)) + "</p>")
                  + f'<p class="lista-stav" role="status">{esc(x["states"]["filled"])}</p>'   # what the bar shows, not only its buttons
                  f'{actions_html(m, x, url, shell[x["id"]][0], shell[x["id"]][1])}</div>' for x in m["screens"] if x.get("shell"))
    switch = "".join(f'<a href="?stav={k}" data-aid-stav-link="{k}">{t}</a> ' for k, t in STATES)
    res = "".join(f'<p class="vysledek" role="status" data-aid-result="{esc(t)}">{esc(e)}</p>' for t, e in results)
    retry = f'<p><a class="akce" href="{esc(url[sid])}" data-aid-retry>Zkusit znovu</a></p>'
    tables = "".join(f'<table><caption>{esc(tb["caption"])}</caption><thead><tr>' + "".join(f'<th scope="col">{esc(c)}</th>' for c in tb["columns"])
                     + "</tr></thead><tbody>" + "".join("<tr>" + "".join(f"<td>{esc(c)}</td>" for c in row) + "</tr>" for row in tb["rows"]) + "</tbody></table>"
                     for tb in scr.get("tables") or [])
    first_mode = (m.get("modes") or [{}])[0].get("id")
    sample = ("" if not (scr.get("sample") or scr.get("mode_sample") or tables) else '<figure class="ukazka"><figcaption>Ukázka (ne skutečná data)</figcaption>'
              + ("" if not (scr.get("sample") or scr.get("mode_sample")) else "<ul>" + "".join(f"<li>{esc(x)}" + (f'<div class="polozka-akce">{actions_html(m, scr, url, fields, ends, k)}</div>' if any(a.get("item") == k for a in scr["actions"]) else "")
                                                               + "</li>" for k, x in enumerate(scr.get("sample") or []))
                 + "".join(f'<li data-aid-mode-is="{esc(md)}"{"" if md == first_mode else " hidden"}>{esc(x)}</li>' for md, rows in (scr.get("mode_sample") or {}).items() for x in rows)
                 + "</ul>") + tables + "</figure>")
    states = "".join(f'<section class="stav" data-aid-state="{k}"><h2>{t}</h2><p>{esc(scr["states"][k])}</p>{sample if k == "filled" else ""}'
                     f'{retry if k == "error" and not scr["states"][k].lower().startswith("nenastává") else ""}</section>' for k, t in STATES)
    mine = [t for t in m["tasks"] if any(st["screen"] == sid for st in t["steps"])]
    mod = screens_module()
    tstates = "".join(f'<section class="stav-ulohy" role="status" data-aid-task-state="{esc(t["id"])}.{k}" hidden><h2>{esc(t["title"])}: {n}</h2><p>{esc(t["states"][k])}</p></section>'
                      for t in m["tasks"] if mod.task_state_url(m, t)[1] == sid for k, n in STATE_NAMES)
    tasks = ("" if not mine else '<details class="ulohy"><summary>Stavy úloh na této obrazovce</summary>' + "".join(
        f'<h3>{esc(t["title"])}</h3><ul>' + "".join(f"<li>{n}: {esc(t['states'][k])}</li>" for k, n in STATE_NAMES) + "</ul>" for t in mine)
        + "</details>")
    data = ("" if not scr.get("data") else '<details class="data"><summary>Odkud jsou data na obrazovce</summary><ul>' + "".join(
        f'<li>{esc(d["what"])}: {esc(d["source"])}; {esc(d["freshness"])}</li>' for d in scr["data"]) + "</ul></details>")
    li = lambda xs: "<ul>" + "".join(f"<li>{x}</li>" for x in xs) + "</ul>"
    foot = "".join(f'<details><summary>{t}</summary>{li(xs)}</details>' for t, xs in (
        ("Slovník pojmů", [f"<b>{esc(g['term'])}</b>: {esc(g['meaning'])}" for g in m.get("glossary") or []]),
        ("Odkud jsou čísla v ukázkách", [f"<b>{esc(v['value'])}</b>: {esc(v['source'])}" for v in (m.get("values") or {}).values()]),
        ("Co aplikace záměrně nedělá", [f"{esc(o['what'])}: {esc(o['why'])}" for o in m.get("out_of_scope") or []]),
        ("Stopa požadavků", [f"{esc(r['id'])} ({esc(r['source'])}): {esc(r['text'])} → " + esc(", ".join(r.get("covered_by") or []) or "mimo rozsah: " + str(r.get("out_of_scope")))
                             for r in m.get("requirements") or []])) if xs)
    banner = "" if approved else '<p class="navrh" role="status" data-aid-draft>Návrh: model čeká na schválení vlastníkem.</p>'
    return (f'<!doctype html>\n<html lang="cs" {MARK} data-aid-app>\n<head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1"><title>{esc(scr["title"])} · {esc(m.get("app") or "aplikace")}</title>'
            '<style>[hidden]{display:none!important}table{display:block;max-width:100%;overflow-x:auto}body{font:16px/1.5 system-ui,sans-serif;margin:0}header,main,footer{padding:16px;max-width:1100px;margin:auto}'
            'nav ul{display:flex;flex-wrap:wrap;gap:12px;list-style:none;padding:0}.stav{border:1px solid #888;padding:12px;margin:12px 0}'
            '.navrh{background:#fe9;padding:8px 16px;margin:0}.chyba{border:2px solid #b00;padding:8px}.lista{border-bottom:2px solid #333;padding:8px 0}'
            'a,button,summary,input{min-height:44px}a,button{display:inline-block;margin:4px 8px 4px 0}'
            ':focus-visible{outline:3px solid #06c;outline-offset:2px}</style></head>\n<body>\n'
            f'{banner}<header><p class="znacka">{esc(m.get("app") or "")}</p>{bar}<nav aria-label="Aplikace"><ul>{nav}</ul></nav></header>\n'
            f'<main data-aid-screen="{esc(sid)}"><h1>{esc(scr["title"])}</h1><p class="ucel">{esc(scr["purpose"])}</p>'
            f'<nav class="stavy" aria-label="Stav obrazovky">{switch}</nav><p class="oznameni" role="status" aria-live="polite" data-aid-stav-oznameni></p>{res}{tstates}{states}<p class="chyba" role="alert" tabindex="-1" data-aid-error-global hidden>{esc(scr["states"]["error"])}</p>{actions_html(m, scr, url, fields, ends)}{data}{tasks}</main>\n'
            + (f'<footer>{foot}</footer>\n' if foot else "") + f'<script>{APP_JS}</script>\n</body>\n</html>\n')


def build_app(p):
    """One page per screen at site/<screen>/index.html (site/index.html = the first screen in the navigation): the
    navigation, the screen's four states (?stav=, all visible without JS), its actions with data-aid-action, the
    submit actions in one form whose fields are the inputs the model's tasks give there (sent with fetch: a failing
    request shows the error state and keeps the input), destructive actions behind their confirm question, and on the
    screen where a task ends the text its done_when expects. A model not approved by the PM (or changed since) is
    built with the draft banner on every page."""
    mf = os.path.join(p, "docs", "design", "screens.json")
    if not os.path.isfile(mf):
        die("no docs/design/screens.json: the app skeleton is built from the model of screens and tasks "
            "(step Obrazovky a úlohy, references/local/aplikace-postup.md)", 2)
    mod = screens_module()
    try:
        m = mod.load(p)
    except ValueError as e:
        die(f"docs/design/screens.json is not JSON ({e})", 2)
    bad = mod.violations(m, p)
    if bad:
        die("the model fails aid-ui-screens.py check:\n" + "\n".join("screens: " + b for b in bad), 2)
    m = mod.resolved(m)   # the named values in every text: one number, one place
    site = os.path.join(p, "site")
    no_symlinks(p, "site", ".aid-ui/skeleton")
    import hashlib
    sha = hashlib.sha256(open(mf, "rb").read()).hexdigest()
    try:
        approved = (json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8")).get("app") or {}).get("approved_model_sha") == sha
    except (OSError, ValueError):
        approved = False
    fields = {x["id"]: [f["name"] for f in x.get("fields") or []] for x in m["screens"]}   # every field the screen declares
    for t in m["tasks"]:
        for st in t["steps"]:
            for n in st.get("input") or {}:
                fields.setdefault(st["screen"], [])
                if n not in fields[st["screen"]]:
                    fields[st["screen"]].append(n)
    results, ends = {}, {}
    for t in m["tasks"]:
        results.setdefault(t["done_when"]["screen"], []).append((t["id"], t["done_when"]["expect"]))
        last = t["steps"][-1]   # the actions that end the task: its last step's, and a recover of a failure at that step
        acts = [last["action"]] + [fp["recover"] for fp in t["failure_paths"] if fp["at_step"] == len(t["steps"])]
        for a in acts:
            ends.setdefault(last["screen"], {}).setdefault(a, [])
            if t["id"] not in ends[last["screen"]][a]:
                ends[last["screen"]][a].append(t["id"])
    shell = {x["id"]: (fields.get(x["id"], []), ends.get(x["id"], {})) for x in m["screens"] if x.get("shell")}
    home = next(x for x in m["screens"] if x["nav"] and not x.get("shell"))
    files = {}
    for x in m["screens"]:   # two screens on one address would overwrite each other silently; the shell has no page
        if x.get("shell"):
            continue
        f = page_file(site, mod.screen_url(x))
        if f in files:
            die(f"screens {files[f]} and {x['id']} both become {os.path.relpath(f, site)}", 2)
        files[f] = x["id"]
    entries = [(page_file(site, mod.screen_url(x)),
                lambda x=x: app_page(m, x, approved, fields.get(x["id"], []), results.get(x["id"], []), ends.get(x["id"], {}), shell))
               for x in m["screens"] if not x.get("shell")]
    if os.path.join(site, "index.html") not in files:   # no screen at "/": the home page is the first screen in the navigation
        entries.append((os.path.join(site, "index.html"), lambda: app_page(m, home, approved, fields.get(home["id"], []), results.get(home["id"], []),
                                                                         ends.get(home["id"], {}), shell)))
    out = write_pages(p, site, entries)
    if not approved and out["kept"]:   # a built page is never rewritten: it cannot carry the banner; the gate refuses the model
        warn("built pages kept without the draft banner (the model is not approved): " + ", ".join(out["kept"])
             + "; the gate refuses until the PM approves this model")
    print(json.dumps(out | {"model_sha256": sha, "approved": approved}, ensure_ascii=False))


def facts_row(p, site, pages, facts, tmp):
    """aid-ui-tool.sh verify with a checks file naming only facts_match (1440, Chromium) over the skeleton pages,
    served for the run on a free local port; [] when every row passes."""
    import socket, http.server, threading, functools
    ck = {"viewports": [1440], "browsers": ["chromium"], "warn_only": [], "applies": {}, "checks": {"facts_match": "skeleton-check"}}
    st = {"build": {"fingerprints": {os.path.relpath(f, site): "skeleton" for f in pages}}}
    json.dump(ck, open(os.path.join(tmp, "checks.json"), "w"))
    json.dump(st, open(os.path.join(tmp, "state.json"), "w"))
    json.dump(facts, open(os.path.join(tmp, "facts.json"), "w"), default=str)
    served = os.path.join(tmp, "site")   # only the skeleton pages, copied: nothing else of the project is served
    for f in pages:
        dst = os.path.join(served, os.path.relpath(f, site))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(f, dst)
    site = served
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=served)
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
    if app_kind(p):   # P116: an app's skeleton stands on its model; the web's tree, H1 and facts rows do not apply
        mod = screens_module()
        bad = mod.violations(mod.load(p), p) if os.path.isfile(os.path.join(p, "docs", "design", "screens.json")) else ["no docs/design/screens.json"]
        for b in bad:
            print("FAIL " + b)
        if bad:
            sys.exit(1)
        print("skeleton-check: OK (aplikace: model obrazovek a úloh prošel kontrolou)")
        return
    s, facts = load(p)
    site = os.path.join(p, "site")
    no_symlinks(p, "site", ".aid-ui/skeleton")
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
