#!/usr/bin/env python3
"""aid-ui-design-standard.py - the project design standard, in the structure of the WAN design
standard, as a working document in the project (docs/design/design-standard.md). Published to
Docusaurus only after the PM approves it (P103 extension K4) - this script never writes there.

  aid-ui-design-standard.py write <project> --measure <measure.json> [--out docs/design/design-standard.md]
  aid-ui-design-standard.py check <project> [--file docs/design/design-standard.md]

write composes the document from:
  - DESIGN.md: the frontmatter tokens (read with `yq`, exactly as aid-ui-design-to-css.sh reads
    them for the build's CSS - the binding source) and every `##` prose section, mapped to the
    WAN headings; a section no heading takes lands under "Ostatní z DESIGN.md", never dropped;
  - <measure.json> from `aid-ui-tool.sh measure`: control roles with their hover/focus/disabled
    states, fields, type, breakpoints, layers, icons, motion - what the built site really uses;
  - docs/design/brand-package/brand-brief.md and brand-state.json (variant, flows and their
    states for an app, gate exceptions); the enforcement list from checks.yaml.
  Patterns, terminology and exceptions cannot be measured: they are the agent's text from DESIGN.md
  and the PM approves the whole document (design_standard question, step 7 bod 4).
check (the gate's design_standard_doc row):
  - the sections Značka, Tokeny (with Barvy, Typografie, Rozměry, Pohyb, Ikony, Vrstvy),
    Komponenty, Vzory, Obsah a terminologie, Platformní kontrakt, Výjimky, Vynucení; for
    webapp/pwa also "Stavy úloh" naming every flow of the state;
  - every DESIGN.md token (colours, typography roles, rounded, spacing) with its value in the
    document, at least one token, and no colour in the document's table that DESIGN.md dropped;
  - a measured buttons table in Komponenty with at least one role, and every measured control
    or field colour is a DESIGN.md colour;
  - the platform table rows Předěl, Navigace, Dotyk/kurzor, Formuláře, Systémové okraje, Gesta
    (and Okna for an app), and every component named in DESIGN.md's components section
    (a bold **name**) named again in the Platformní kontrakt section.
Output of check: `MISSING|OK <part> <what>`; exit 0 complete, 1 something missing, 2 usage or an
unreadable input (never a silent pass).
"""
import argparse, json, os, re, subprocess, sys
from datetime import date

SECTIONS = ["Značka", "Tokeny", "Komponenty", "Vzory", "Obsah a terminologie", "Platformní kontrakt", "Výjimky", "Vynucení"]
TOKEN_SUBS = ["Barvy", "Typografie", "Rozměry", "Pohyb", "Ikony", "Vrstvy"]
PLATFORM_ROWS = ["Předěl", "Navigace", "Dotyk/kurzor", "Formuláře", "Systémové okraje", "Gesta"]
# where a DESIGN.md prose section goes (first match wins); anything else -> "Ostatní z DESIGN.md"
ROUTE = [("tokeny", r"^tokeny"), ("tokeny", r"^písmo|^font"), ("tokeny", r"^ikony"), ("komponenty", r"^komponent"),
         ("vzory", r"^vzory|^princip"), ("obsah", r"^(pravidla )?text|^obsah|^terminolog"),
         ("platformy", r"^platform"), ("platformy", r"^přístupnost")]


def die(msg, code=2):
    print(f"ERROR: aid-ui-design-standard.py: {msg}", file=sys.stderr)
    sys.exit(code)


def design(project):
    """(frontmatter dict, [(heading, text)]) of DESIGN.md; the frontmatter read by yq"""
    try:
        text = open(os.path.join(project, "DESIGN.md"), encoding="utf-8").read()
    except OSError as e:
        die(f"no DESIGN.md: {e}")
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        die("DESIGN.md has no frontmatter")
    r = subprocess.run(["yq", "-o=json", "."], input=m.group(1), capture_output=True, text=True)
    try:
        fm = json.loads(r.stdout) if r.returncode == 0 else None
    except ValueError:
        fm = None
    if not isinstance(fm, dict):
        die("DESIGN.md frontmatter is not a YAML mapping")
    secs = [(h.strip(), t.strip()) for h, t in re.findall(r"^##\s+(.+?)\s*$(.*?)(?=^##\s|\Z)", text[m.end():], re.M | re.S)]
    return fm, secs


def tokens(fm):
    """[(group, name, value)] of every scalar token, the way aid-ui-design-to-css.sh exports them"""
    out = []
    for g in ("colors", "rounded", "spacing"):
        v = fm.get(g)
        if isinstance(v, dict):
            out += [(g, k, str(x)) for k, x in v.items() if x is not None and not isinstance(x, (dict, list))]
    ty = fm.get("typography")
    if isinstance(ty, dict):
        for role, props in ty.items():
            if isinstance(props, dict):
                out += [("typography", f"{role}.{k}", str(x)) for k, x in props.items() if x is not None and not isinstance(x, (dict, list))]
    return out


def rgb_hex(c):
    m = re.match(r"rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)", c or "")
    if not m:
        return c
    if m.group(4) is not None and float(m.group(4)) == 0:
        return "průhledné"
    return "#%02x%02x%02x" % tuple(int(m.group(i)) for i in (1, 2, 3))


def colours_in(text, names):
    def one(m):
        h = rgb_hex(m.group(0))
        return f"`{h}`" + (f" ({names[h]})" if h in names else "")
    return re.sub(r"rgba?\([^)]*\)", one, text or "")


def font_of(c):
    f = c.get("font")
    return " / ".join(f"{f.get(w, '-')}" for w in ("390", "1440")) if isinstance(f, dict) else str(f)


def state(project):
    try:
        st = json.load(open(os.path.join(project, "docs/design/brand-state.json"), encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"no readable docs/design/brand-state.json: {e}")
    if not isinstance(st, dict) or not isinstance(st.get("variant") or {}, dict):
        die("brand-state.json: variant must be an object")
    return st


def write(project, measure_path, out_rel):
    fm, secs = design(project)
    st = state(project)
    try:
        meas = json.load(open(measure_path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"cannot read {measure_path}: {e}")
    vtype = (st.get("variant") or {}).get("type") or "web"
    colors = fm.get("colors") if isinstance(fm.get("colors"), dict) else {}
    names = {str(v).lower(): k for k, v in colors.items()}
    routed = {}
    for h, t in secs:
        if not t:
            continue
        key = next((k for k, p in ROUTE if re.search(p, h, re.I)), "ostatni")
        routed.setdefault(key, []).append(f"*Z DESIGN.md, „{h}“:*\n\n{t}")
    take = lambda k: "\n\n".join(routed.get(k, []))
    name = fm.get("name") or os.path.basename(os.path.abspath(project))
    L = [f"# {name} - design standard", "",
         f"*Pracovní verze z {date.today().strftime('%-d. %-m. %Y')} (/aid-ui, krok 7). Do Docusauru se publikuje až po schválení PM. "
         "Tokeny jsou z `DESIGN.md` (z nich se generuje CSS webu), komponenty změřené na postaveném webu, "
         "vzory a texty sepsané z postaveného webu a schválené PM.*", ""]
    brief = os.path.join(project, "docs/design/brand-package/brand-brief.md")
    L += ["## Značka", "", "Zdroj: brand balíček `docs/design/brand-package/` (symbol, logo s názvem, ikony, zdroje)."]
    if os.path.exists(brief):
        L += ["Zásady použití (`brand-brief.md`):", ""] + [l for l in open(brief, encoding="utf-8").read().splitlines() if l.startswith("- ")]
    L += ["", "- Logo se nikdy neskládá z textu, vždy soubor z balíčku.", ""]
    L += ["## Tokeny", "", "Jediný zdroj: frontmatter `DESIGN.md` → CSS proměnné (`aid-ui-design-to-css.sh`).", "",
          "### Barvy", "", "| token | hodnota |", "|---|---|"] + [f"| `{k}` | `{v}` |" for k, v in colors.items()]
    ty = fm.get("typography") if isinstance(fm.get("typography"), dict) else {}
    L += ["", "### Typografie", "", "| role | písmo | velikost | tučnost | řádkování | prostrkání |", "|---|---|---|---|---|---|"]
    L += [f"| {r} | `{v.get('fontFamily', '')}` | `{v.get('fontSize', '')}` | `{v.get('fontWeight', '')}` | `{v.get('lineHeight', '')}` | `{v.get('letterSpacing', '')}` |"
          for r, v in ty.items() if isinstance(v, dict)]
    mt = meas.get("type") or {}
    if mt:
        L += ["", "Změřeno na 1440 px: " + "; ".join(f"{k} {v['size']} / {v['weight']}" for k, v in mt.items()) + "."]
    L += ["", "### Rozměry", ""]
    L += [f"- `{g}.{k}`: `{v}`" for g, k, v in tokens(fm) if g in ("rounded", "spacing")]
    L += [f"- zlomy šířky (změřeno v CSS): {', '.join(meas.get('breakpoints') or ['žádné'])}"]
    L += ["", "### Pohyb", "", "- přechody (změřeno, nad 10 ms): " + (", ".join(meas.get("transitions") or []) or "žádné"),
          f"- při `prefers-reduced-motion` se {'něco hýbe - opravit' if meas.get('reduced_motion_moves') else 'nic nehýbe'} (změřeno)"]
    L += ["", "### Ikony", "", f"- ikon na webu (změřeno: `svg`/`img` do 48 px mimo logo): {meas.get('icons', 'neměřeno')}"]
    L += ["", "### Vrstvy", "", "- prvky s `z-index` (změřeno, i skryté): " + (", ".join(meas.get("zindex") or []) or "žádné")]
    if take("tokeny"):
        L += ["", take("tokeny")]
    L += ["", "## Komponenty", "", "### Tlačítka", "", "Role změřené na webu (tlačítka, `[role=button]` a odkazy s plochou nebo rámečkem; stav najetí, zaměření a zakázaný změřen na jednom prvku role):", "",
          "| role | plocha | text | rámeček | zaoblení | výška 390 / 1440 px | písmo 390 / 1440 px | najetí | zaměření | zakázané | výskyty | příklady |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, c in enumerate(meas.get("controls") or [], 1):
        stt = c.get("states") or {}
        L.append(f"| {i} | {colours_in(c['background'], names)} | {colours_in(c['color'], names)} | {colours_in(c['border'], names)} | {c['radius']} | "
                 f"{c['height'].get('390', '-')} / {c['height'].get('1440', '-')} | {font_of(c)} | {colours_in(stt.get('hover', '-'), names)} | "
                 f"{colours_in(stt.get('focus', '-'), names)} | {colours_in(stt.get('disabled', '-'), names)} | {c['count']} | {', '.join(c['examples'])} |")
    if meas.get("fields"):
        L += ["", "### Pole formuláře", "", "| pole | rámeček | zaoblení | plocha | výška 390 / 1440 px |", "|---|---|---|---|---|"]
        L += [f"| {f['tag']} | {colours_in(f['border'], names)} | {f['radius']} | {colours_in(f['background'], names)} | "
              f"{f['height'].get('390', '-')} / {f['height'].get('1440', '-')} |" for f in meas["fields"]]
    if take("komponenty"):
        L += ["", take("komponenty")]
    if vtype in ("webapp", "pwa"):
        flows = (st.get("structure") or {}).get("flows") or []
        L += ["", "## Stavy úloh", "", "Podle `webapp-tasks-states-standard`, z mapy úloh projektu:", "",
              "| úloha | stavy |", "|---|---|"]
        L += [f"| {f.get('id')} | {', '.join(str(s.get('id') if isinstance(s, dict) else s) for s in f.get('states') or [])} |" for f in flows if isinstance(f, dict)]
    L += ["", "## Vzory", "", take("vzory") or "*Doplní agent z postaveného webu, schválí PM.*"]
    L += ["", "## Obsah a terminologie", "", take("obsah") or "*Doplní agent, schválí PM.*"]
    L += ["", "## Platformní kontrakt", "", take("platformy") or "*Tabulka chybí: doplní agent.*"]
    ex = [e for e in st.get("exceptions") or [] if isinstance(e, dict) and not e.get("resolved")]
    L += ["", "## Výjimky", ""] + ([f"- `{e['selector'].get('check')}` {e['selector'].get('page', '*')}: {e.get('reason', '')}" for e in ex]
                                  or ["- žádné (brána /aid-ui bez otevřených výjimek)"])
    ck = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills", "ui-design", "coverage", "checks.yaml")
    r = subprocess.run(["yq", "-r", ".checks | keys | .[]", ck], capture_output=True, text=True)
    checks = r.stdout.split() if r.returncode == 0 else []
    L += ["", "## Vynucení", "",
          "- Každý build projde bránou /aid-ui (`aid-ui-verify.sh`), kontroly: " + (", ".join(f"`{c}`" for c in checks) or "viz checks.yaml") + ".",
          "- Hodnoty jen z tokenů `DESIGN.md`; nová varianta komponenty se nejdřív zapíše sem a do `DESIGN.md`.",
          "- Po každé větší úpravě vzhledu se web znovu změří (`aid-ui-tool.sh measure`) a tento dokument se vygeneruje znovu.",
          f"- Druh projektu: {vtype}."]
    if take("ostatni"):
        L += ["", "## Ostatní z DESIGN.md", "", take("ostatni")]
    out = os.path.join(project, out_rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(re.sub(r"\n{3,}", "\n\n", "\n".join(L)) + "\n")
    print(out)
    return 0


def section(doc, head, level=2):
    m = re.search(r"^%s\s+%s\s*$(.*?)(?=^#{1,%d}\s|\Z)" % ("#" * level, re.escape(head), level), doc, re.M | re.S)
    return m.group(1) if m else None


def check(project, rel):
    try:
        doc = open(os.path.join(project, rel), encoding="utf-8").read()
    except OSError as e:
        print(f"MISSING {rel} {e}")
        return 1
    fm, secs = design(project)
    st = state(project)
    vtype = (st.get("variant") or {}).get("type")
    res = []
    for s in SECTIONS + (["Stavy úloh"] if vtype in ("webapp", "pwa") else []):
        res.append((section(doc, s) is not None, "section", s))
    tok = section(doc, "Tokeny") or ""
    for s in TOKEN_SUBS:
        res.append((re.search(r"^###\s+%s\s*$" % s, tok, re.M) is not None, "section", f"Tokeny / {s}"))
    tl = tokens(fm)
    res.append((bool(tl), "token", "DESIGN.md defines at least one token"))
    for g, k, v in tl:
        if g == "colors":
            ok = f"| `{k}` | `{v}` |" in doc
        elif g == "typography":
            ok = f"`{v}`" in tok
        else:
            ok = f"`{g}.{k}`: `{v}`" in doc
        res.append((ok, "token", f"{g} {k} = {v} as in DESIGN.md"))
    keep = {k for g, k, _ in tl if g == "colors"}
    colors = {str(v).lower() for g, k, v in tl if g == "colors"}
    for k in re.findall(r"^\| `([\w-]+)` \| `#[0-9a-fA-F]{3,8}` \|$", section(doc, "Barvy", 3) or "", re.M):
        res.append((k in keep, "token", f"colour {k} in the document is still in DESIGN.md"))
    btn = section(doc, "Tlačítka", 3) or ""
    res.append((bool(re.search(r"^\| 1 \|", btn, re.M)), "components", "buttons table with at least one measured role"))
    for h in sorted(set(re.findall(r"`(#[0-9a-f]{6})`", btn + (section(doc, "Pole formuláře", 3) or "")))):
        res.append((h in colors, "components", f"measured colour {h} is a DESIGN.md colour"))
    plat = section(doc, "Platformní kontrakt") or ""
    rows = PLATFORM_ROWS + (["Okna"] if vtype in ("webapp", "pwa") else [])
    for r_ in rows:
        res.append((bool(re.search(r"^\|\s*\**" + re.escape(r_.split("/")[0]), plat, re.M | re.I)), "platform", f"row {r_}"))
    names = [n for h, t in secs if re.search(r"^komponent", h, re.I) for n in re.findall(r"^\s*-\s*\*\*([^*]+?)\*\*", t, re.M)]
    for n in names:
        word = re.split(r"[\s(]", n.strip())[0].lower()
        res.append((word[:5] in plat.lower(), "platform", f"component {n.strip()} named in Platformní kontrakt"))
    if vtype in ("webapp", "pwa"):
        flows = section(doc, "Stavy úloh") or ""
        for f in (st.get("structure") or {}).get("flows") or []:
            if isinstance(f, dict):
                res.append((f"| {f.get('id')} |" in flows, "flows", f"flow {f.get('id')} with its states"))
    for ok, part, what in sorted(res, key=lambda x: x[0]):
        print(("OK" if ok else "MISSING"), part, what)
    return 0 if all(r[0] for r in res) else 1


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("write"); w.add_argument("project"); w.add_argument("--measure", required=True)
    w.add_argument("--out", default="docs/design/design-standard.md")
    c = sub.add_parser("check"); c.add_argument("project"); c.add_argument("--file", default="docs/design/design-standard.md")
    a = ap.parse_args()
    return write(a.project, a.measure, a.out) if a.cmd == "write" else check(a.project, a.file)


if __name__ == "__main__":
    sys.exit(main())
