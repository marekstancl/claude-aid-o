#!/usr/bin/env python3
"""aid-ui-logo-route.py - the logo decision tree of step 1i (Rozcestník), computed from the project
state, never asked of the PM (PM 7. 10. 2026: "to musí říkat ten skill").

  aid-ui-logo-route.py <project> [--write]      prints the route as JSON; --write also stores it as
                                                <project>/.aid-ui/logo/route.json (the studio checks
                                                the identity question's cards against it)

Inputs, in this order of authority:
  docs/design/brand-state.json   variant.type (web | webapp | pwa), variant.brand (new | existing),
                                 options.identity (false | "new" | "package")
  .aid-ui/old-site/*/fetch.json  an old site was fetched (status 200 on at least one page) -> the
                                 project rebuilds an existing site
  .aid-ui/logo/dnesni-logo.*     the current logo saved by the agent from the old site or the sources:
                                 usable = .svg, or .png/.jpg at least 400 px wide (header read here,
                                 no image library); anything else = reference-only
  docs/design/brief-logo-favicon.md   the "Kde bude značka žít" list -> project contexts
  docs/content/facts.yaml        recenzie_pocet (int) and rok_jmena (int) -> continuity bonus eligible
                                 (reviews >= 20 or the name >= 3 years old); missing = not_evidenced

Situations (first match wins):
  assets    options.identity == "package"                          0 directions: the existing symbol, kit only
  app       variant.type in (webapp, pwa)                           3 directions, symbol first
  redesign  variant.type == web and an old site was fetched         5 directions
  established  a redesign whose current logo is usable and whose continuity is evidenced (reviews >= 20 or the
            name >= 3 years): 3 revivals (R, RD, RB) + 2 new (WC, WP) (P113, fix 69)
  new       variant.type == web, no old site                        3 directions
Every slot has a fixed id (stable; the display order is the recommendation) and a construction kind
that no other slot may use. `local` (variant.local) adds the category-sign slot's rule "in a fresh form".
Exit: 0, 1 no state or an unknown variant, 2 usage.
"""
import glob, json, os, re, struct, sys

SLOTS = {
    "new": [
        {"id": "W", "kind": "wordmark", "text": "nápis názvu vlastním písmem s jedním vlastním detailem, bez symbolu; mikroznačka pro ikony odvozená z iniciál (označená jako odvozená)"},
        {"id": "WC", "kind": "name+sign", "text": "nápis + znak vepsaný do písmene nebo negativního prostoru (u místní služby oborový znak v nové formě, jinak znak z vize)"},
        {"id": "WP", "kind": "name+pictorial", "text": "nápis + samostatný obrazový symbol z metafory slovní mapy (ne oborové klišé, ne iniciála)"},
    ],
    "redesign": [
        {"id": "R", "kind": "revitalization", "text": "oživení dnešního loga: audit hodnoty (redesign.md), zachované prvky vyjmenované, zpřesněná stavba, ikony doplněné", "needs_logo": True},
        {"id": "W", "kind": "wordmark", "text": "nápis názvu vlastním písmem s jedním vlastním detailem, bez symbolu; mikroznačka pro ikony odvozená z iniciál (označená jako odvozená)"},
        {"id": "WC", "kind": "name+sign", "text": "nápis + oborový znak v nové formě vepsaný do písmene nebo negativního prostoru (u místní služby povinně oborový)"},
        {"id": "WM", "kind": "name+monogram", "text": "nápis + monogram nebo písmeno z iniciál jako samostatný symbol (letterform = jedna iniciála, monogram = dvě a víc)"},
        {"id": "WP", "kind": "name+pictorial", "text": "nápis + obrazový symbol z metafory slovní mapy bez oborového znaku a bez iniciály"},
    ],
    "app": [
        {"id": "L", "kind": "letterform|monogram", "text": "jedna iniciála (letterform) u jednoslovného názvu, jinak monogram ze dvou a víc znaků; symbol první, nápis vedle"},
        {"id": "S", "kind": "abstract", "text": "abstraktní glyf produktu (jev: spojení, rychlost, bezpečí) bez písmen; symbol první"},
        {"id": "P", "kind": "pictorial", "text": "obrazový symbol z metafory slovní mapy; symbol první"},
    ],
    "assets": [],
    # P113 (fix 69, logo-postup.md bod 1): an established mark - a redesign with a usable current logo and continuity
    # evidenced - gets three revivals (each its own construction) and two new directions
    "established": [
        {"id": "R", "kind": "revitalization", "text": "oživení blízké dnešku: zavedený motiv zachovaný a poznávaný, zpřesněná stavba, slabiny z auditu odstraněné", "needs_logo": True},
        {"id": "RD", "kind": "revitalization+detail", "text": "oživení s vlastním detailem: zavedený motiv + jeden nový prvek navázaný na fakt podniku (ne jen čistší kresba)", "needs_logo": True},
        {"id": "RB", "kind": "revitalization+bold", "text": "odvážné oživení: zavedený motiv v nové stavbě (kompozice, kontejner), poznávaný na první pohled", "needs_logo": True},
        {"id": "WC", "kind": "name+sign", "text": "nový směr: nápis + znak z vize nebo oboru v nové formě (jen s důvodem z auditu nebo zadání)"},
        {"id": "WP", "kind": "name+pictorial", "text": "nový směr: nápis + obrazový symbol z metafory slovní mapy bez oborového klišé"},
    ],
}
# the test contexts every direction is shown in, by situation (the brief's own list is added)
TEST_CONTEXTS = {
    "new": ["hlavička webu", "záložka prohlížeče 16 px", "avatar v kroužku", "tisk černobíle"],
    "redesign": ["hlavička webu", "záložka prohlížeče 16 px", "avatar v kroužku", "tisk černobíle"],
    "established": ["hlavička webu", "záložka prohlížeče 16 px", "avatar v kroužku", "tisk černobíle"],
    "app": ["ikona aplikace", "záložka prohlížeče 16 px", "hlavička aplikace", "avatar v kroužku"],
    "assets": [],
}
CRITERIA = ["clarity", "distinction", "simplicity", "relevance", "small_size"]   # 0-4 each, skill phase 3
WEIGHTS = {"new": {"relevance": 2}, "redesign": {"relevance": 2}, "established": {"relevance": 2}, "app": {"small_size": 2}, "assets": {}}
BRIEF_CONTEXTS = [  # phrase in the brief's list -> context the sheet shows
    (r"hlavičk|hero|web", "hlavička webu"), (r"favicon|záložk|prohlížeč", "záložka prohlížeče 16 px"),
    (r"telefon|ploch|aplikac|pwa", "ikona na telefonu"), (r"avatar|profil", "avatar v kroužku"),
    (r"tisk|vizitk|cedul|dokument", "tisk černobíle"), (r"e-mail|email|podpis", "podpis v e-mailu"),
]


def die(msg, code=1):
    print("ERROR: aid-ui-logo-route.py: %s" % msg, file=sys.stderr)
    sys.exit(code)


def image_width(path):
    """Width of a PNG or JPEG from its header; None when unreadable."""
    try:
        with open(path, "rb") as f:
            head = f.read(26)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                return struct.unpack(">I", head[16:20])[0]
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    marker = f.read(2)
                    if len(marker) < 2 or marker[0] != 0xFF:
                        return None
                    if marker[1] in (0xC0, 0xC1, 0xC2):
                        f.read(3)
                        _, w = struct.unpack(">HH", f.read(4))
                        return w
                    seg = struct.unpack(">H", f.read(2))[0]
                    f.seek(seg - 2, 1)
    except OSError:
        return None
    return None


def current_logo(project):
    for p in sorted(glob.glob(os.path.join(project, ".aid-ui", "logo", "dnesni-logo.*"))):
        ext = os.path.splitext(p)[1].lower()
        if ext == ".svg":
            return {"file": os.path.relpath(p, project), "state": "usable"}
        if ext in (".png", ".jpg", ".jpeg"):
            w = image_width(p)
            return {"file": os.path.relpath(p, project), "state": "usable" if w and w >= 400 else "reference-only", "width": w}
    return {"file": None, "state": "absent"}


def brief_contexts(project):
    path = os.path.join(project, "docs", "design", "brief-logo-favicon.md")
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return []
    m = re.search(r"^## Kde bude značka žít.*?$(.*?)^## ", text, re.S | re.M)
    if not m:
        return []
    out = []
    for line in m.group(1).splitlines():
        if not re.match(r"\s*(\d+\.|-)\s", line):
            continue
        for pat, ctx in BRIEF_CONTEXTS:
            if re.search(pat, line, re.I) and ctx not in out:
                out.append(ctx)
    return out


def facts(project):
    """recenzie_pocet and rok_jmena from facts.yaml - a plain `key: 2014` or `key: {value: 2014, ...}` (fix 6)."""
    path = os.path.join(project, "docs", "content", "facts.yaml")
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return out
    for key in ("recenzie_pocet", "rok_jmena", "brand"):
        m = re.search(r"^%s:\s*(?:\{\s*value:\s*)?\"?([^,\"}\n#]+?)\"?\s*(?:[,}].*)?(?:#.*)?$" % key, text, re.M)
        if m:
            v = m.group(1).strip()
            out[key] = int(v) if v.isdigit() else v
    return out


def route(project):
    try:
        with open(os.path.join(project, "docs", "design", "brand-state.json"), encoding="utf-8") as f:
            st = json.load(f)
    except (OSError, ValueError) as e:
        die("no readable docs/design/brand-state.json in %s (%s); run step 0 first" % (project, e))
    v = st.get("variant") or {}
    if v.get("type") not in ("web", "webapp", "pwa"):
        die("variant.type must be web, webapp or pwa (step 0); got %r" % v.get("type"))
    identity = (st.get("options") or {}).get("identity")
    old = [p for p in glob.glob(os.path.join(project, ".aid-ui", "old-site", "*", "fetch.json"))
           if _fetched_ok(p)]
    if identity == "package":
        situation = "assets"
    elif v["type"] in ("webapp", "pwa"):
        situation = "app"
    elif old:
        situation = "redesign"
    else:
        situation = "new"
    logo = current_logo(project)
    fx = facts(project)
    cont = None
    if "recenzie_pocet" in fx or "rok_jmena" in fx:
        import datetime
        age = datetime.date.today().year - fx["rok_jmena"] if isinstance(fx.get("rok_jmena"), int) else 0
        cont = (isinstance(fx.get("recenzie_pocet"), int) and fx["recenzie_pocet"] >= 20) or age >= 3
    if situation == "redesign" and logo["state"] == "usable" and cont:
        situation = "established"
    slots = [dict(s) for s in SLOTS[situation]]
    notes = []
    for s in slots:
        if s.pop("needs_logo", False) and logo["state"] != "usable":
            s.update(id="R", kind="wordmark-continuity",
                     text="nápis názvu navazující na dnešní značku barvou a tvarem písma (dnešní logo není použitelné: %s)" % logo["state"])
            notes.append("slot R: no usable current logo (%s) -> wordmark-continuity" % logo["state"])
    local = bool(v.get("local"))
    if local:
        for s in slots:
            if s["kind"] == "name+sign":
                s["text"] += "; místní služba: znak oboru povinný, v nové formě (zásada 4 skillu), kreslené klišé zakázáno"
    contexts = list(TEST_CONTEXTS[situation])
    for c in brief_contexts(project):
        if c not in contexts:
            contexts.append(c)
    return {
        "situation": situation,
        "inputs": {"variant": v, "identity": identity, "old_site": [os.path.relpath(p, project) for p in old],
                   "current_logo": logo, "facts": fx},
        "direction_count": len(slots),
        "slots": slots,
        "contexts": contexts,
        "scoring": {"criteria": CRITERIA, "scale": "0-4 each, rubric in 1i Rozcestník", "weights": WEIGHTS[situation],
                    "continuity_bonus": {"slot": "R", "value": 1, "eligible": cont,
                                         "rule": "only slot R, only with kept elements listed; eligible = reviews >= 20 or name >= 3 years; null = not_evidenced, no bonus"},
                    "gates_before_scoring": ["svg_audit without FAIL", "16 px test judged pass", "full pair (lockup + symbol + small cut)",
                                             "slot kind met", "no untransformed category cliché", "font licence and latin-ext checked"],
                    "tie_break": ["higher distinction", "fewer anchors (svg_audit)", "slot order"]},
        "fonts": {"candidates": 3, "source": "Google Fonts, OFL, latin-ext", "check": "aid-ui-tool.sh glyph --sample <family> <name and every letter the site's language uses>"},
        "notes": notes,
    }


def _fetched_ok(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return False
    pages = d.get("pages") if isinstance(d, dict) else None
    if isinstance(pages, list):
        return any(isinstance(p, dict) and p.get("status") == 200 for p in pages)
    return isinstance(d, dict) and d.get("status") == 200


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        die("usage: aid-ui-logo-route.py <project> [--write]", 2)
    project = os.path.realpath(args[0])
    r = route(project)
    out = json.dumps(r, ensure_ascii=False, indent=1)
    if "--write" in sys.argv:
        os.makedirs(os.path.join(project, ".aid-ui", "logo"), exist_ok=True)
        with open(os.path.join(project, ".aid-ui", "logo", "route.json"), "w", encoding="utf-8") as f:
            f.write(out + "\n")
    print(out)


if __name__ == "__main__":
    main()
