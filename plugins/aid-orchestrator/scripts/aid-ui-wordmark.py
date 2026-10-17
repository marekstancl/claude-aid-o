#!/usr/bin/env python3
"""aid-ui-wordmark.py - the logo with the name: symbol + name set in the brand font.
Run through `aid-ui-tool.sh wordmark` (it provides fontTools in ~/.cache/aid-ui/pyfont).

  aid-ui-wordmark.py --spec <wordmark.json> [--root <project>]

Paths in the spec are relative to --root (default: the current directory = the project root).
wordmark.json:
  {"package": "docs/design/brand-package",            the brand package directory
   "base": "needless-logo",                           file name stem, [a-z0-9-]+
   "name": "Needless",                                the name as set
   "font": ["docs/brand/fonts/x-latin.woff2",         one font file or a list; web fonts come split by
            "docs/brand/fonts/x-latin-ext.woff2"],    character range: each character is set from the
                                                      first file that has it
   "family": "Bricolage Grotesque", "weight": 800,    weight instantiates a variable font (required then)
   "licence": "SIL Open Font License 1.1",
   "symbol_to_cap": 1.3,                              symbol height = 1.3 x cap height (brief)
   "variants": [{"id": "color", "symbol": "symbol/symbol-color.svg", "text": "#16302b"},
                {"id": "color-on-dark", "symbol": "symbol/symbol-color-on-dark.svg", "text": "#f3efe6"}]}

Writes, under the package: source/<base>-master.svg (the first variant, the name as live
<text> with font family, weight and licence in a comment), source/<base>-master-outlines.svg
(the same with the name as paths, no <text>), and logo/<base>-<id>.svg per variant (outlines,
the distribution version). Layout: the symbol (nested <svg> keeping its own viewBox and root
attributes) H units high, a gap of H/4, the name's cap height = H / symbol_to_cap, capitals
centred on the symbol; the viewBox grows to the real outline bounds, so accents above capitals
and descenders (Ž, Á, g, y) are never cut. Pair kerning from the font's GPOS 'kern' feature
(or the legacy kern table) is applied to the outlines and written as dx on the live text, so
both versions set the same.
Optional (P113, logo-postup.md): "subtitle": {"text": "projekční kancelář", "font": [...] (default the name's), "weight",
"family" (default the name's), "size_to_cap": 0.45 (its cap height against the name's), "tracking_em": 0.12} - a second
line under the name, flush with its start, letter-spaced; the live master carries it as <text letter-spacing>.
No subtitle = the output as before.
Exit: 0 written, 1 a file cannot be read or the font lacks a glyph, 2 a bad spec.
"""
import argparse, json, os, re, sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

try:
    from fontTools.ttLib import TTFont
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.pens.boundsPen import BoundsPen
except ImportError:
    sys.exit("ERROR: aid-ui-wordmark.py: fontTools missing; run it through aid-ui-tool.sh wordmark")

H = 64.0  # symbol height in the output's units
attr = lambda s: escape(str(s), {'"': "&quot;"})
COLOR = re.compile(r"^#[0-9a-fA-F]{3,8}$")
STEM = re.compile(r"^[a-z0-9-]+$")


def die(msg, code=2):
    print(f"ERROR: aid-ui-wordmark.py: {msg}", file=sys.stderr)
    sys.exit(code)


def kerning(font):
    """{(left glyph, right glyph): x advance adjustment} from GPOS 'kern' pair positioning
    (formats 1 and 2, extension lookups included), else the legacy kern table."""
    pairs = {}
    if "GPOS" in font and font["GPOS"].table.FeatureList:
        g = font["GPOS"].table
        idx = {i for fr in g.FeatureList.FeatureRecord if fr.FeatureTag == "kern" for i in fr.Feature.LookupListIndex}
        for i in sorted(idx):
            for st in g.LookupList.Lookup[i].SubTable:
                st = getattr(st, "ExtSubTable", st)
                if getattr(st, "LookupType", 2) != 2 or not hasattr(st, "Format"):
                    continue
                cov = st.Coverage.glyphs
                if st.Format == 1:
                    for gi, ps in zip(cov, st.PairSet):
                        for pv in ps.PairValueRecord:
                            v = getattr(pv.Value1, "XAdvance", 0) if pv.Value1 else 0
                            if v:
                                pairs.setdefault((gi, pv.SecondGlyph), v)
                elif st.Format == 2:
                    c1, c2 = st.ClassDef1.classDefs, st.ClassDef2.classDefs
                    for gi in cov:
                        row = st.Class1Record[c1.get(gi, 0)]
                        for g2 in font.getGlyphOrder():
                            v = row.Class2Record[c2.get(g2, 0)].Value1
                            v = getattr(v, "XAdvance", 0) if v else 0
                            if v:
                                pairs.setdefault((gi, g2), v)
    elif "kern" in font:
        for t in font["kern"].kernTables:
            pairs.update(getattr(t, "kernTable", {}))
    return pairs


def load_fonts(spec, root):
    files = spec["font"] if isinstance(spec["font"], list) else [spec["font"]]
    fonts = []
    for f in files:
        try:
            ft = TTFont(os.path.join(root, f))
        except Exception as e:  # unreadable or not a font
            die(f"cannot read the font {f}: {e}", 1)
        if "fvar" in ft:
            if not spec.get("weight"):
                die(f"{f} is a variable font; give 'weight' so the outlines and the live text match")
            from fontTools.varLib import instancer
            ft = instancer.instantiateVariableFont(ft, {"wght": float(spec["weight"])})
        cap = getattr(ft["OS/2"], "sCapHeight", 0) or 0.7 * ft["head"].unitsPerEm
        fonts.append({"font": ft, "cmap": ft.getBestCmap(), "gs": ft.getGlyphSet(), "hmtx": ft["hmtx"], "cap": cap,
                      "kern": kerning(ft)})
    return fonts


def symbol_svg(path, x, y, size):
    """the symbol as a nested <svg> keeping its root attributes and viewBox, placed at x, y"""
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
        if re.search(r"<!(DOCTYPE|ENTITY)", raw, re.I):  # no entities: a client's file must not expand or fetch anything
            die(f"the symbol {path} has a DOCTYPE or ENTITY; remove it", 1)
        tree = ET.ElementTree(ET.fromstring(raw))
    except (OSError, ET.ParseError) as e:
        die(f"cannot read the symbol {path}: {e}", 1)
    r = tree.getroot()
    vb = r.get("viewBox")
    if not vb or len(re.split(r"[\s,]+", vb.strip())) != 4:
        die(f"the symbol {path} has no viewBox")
    for k in ("width", "height", "x", "y"):
        r.attrib.pop(k, None)
    r.set("x", f"{x:g}"); r.set("y", f"{y:g}"); r.set("width", f"{size:g}"); r.set("height", f"{size:g}")
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    return ET.tostring(r, encoding="unicode")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    try:
        spec = json.load(open(a.spec, encoding="utf-8"))
        pkg, base, name, variants = os.path.join(a.root, spec["package"]), spec["base"], spec["name"], spec["variants"]
        spec["family"], spec["font"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        die(f"bad spec {a.spec}: {e!r}")
    if not STEM.match(base) or not variants or any(not STEM.match(str(v.get("id", ""))) or not COLOR.match(str(v.get("text", ""))) for v in variants):
        die("base and variant ids must match [a-z0-9-]+ and every variant needs text = #rgb/#rrggbb")
    fonts = load_fonts(spec, a.root)
    missing = [c for c in name if not any(ord(c) in f["cmap"] for f in fonts)]
    if missing:
        die(f"no font file has a glyph for {''.join(missing)!r}; add the subset that has it to 'font'", 1)
    cap_px = H / float(spec.get("symbol_to_cap", 1.3))
    gap, baseline = H / 4, H / 2 + cap_px / 2

    def set_line(fonts, text, cap, x, base, track=0.0):
        """Outlines of one line: (paths, dx per glyph, end x, low y, high y); tracking in units added after each glyph."""
        paths, dx, prev, lo, hi = [], [], None, base, base
        for i, ch in enumerate(text):
            f = next(f for f in fonts if ord(ch) in f["cmap"])
            g, scale = f["cmap"][ord(ch)], cap / f["cap"]
            k = (f["kern"].get((prev[1], g), 0) * scale) if prev and prev[0] is f else 0.0
            x += k + (track if i else 0.0)
            dx.append(k)
            pen, bp = SVGPathPen(f["gs"]), BoundsPen(f["gs"])
            tr = (scale, 0, 0, -scale, x, base)
            f["gs"][g].draw(TransformPen(pen, tr))
            f["gs"][g].draw(TransformPen(bp, tr))
            if pen.getCommands():
                paths.append(pen.getCommands())
            if bp.bounds:
                lo, hi = min(lo, bp.bounds[1]), max(hi, bp.bounds[3])
            x += f["hmtx"][g][0] * scale
            prev = (f, g)
        return paths, dx, x, lo, hi

    paths, dx, x, lo, hi = set_line(fonts, name, cap_px, H + gap, baseline)
    lo, hi = min(0.0, lo), max(H, hi)
    sub = spec.get("subtitle") or None
    if sub:
        if not (isinstance(sub, dict) and isinstance(sub.get("text"), str) and sub["text"].strip()):
            die("subtitle needs text")
        sfonts = load_fonts(dict(spec, font=sub.get("font", spec["font"]), weight=sub.get("weight", spec.get("weight"))), a.root) if (sub.get("font") or sub.get("weight")) else fonts
        miss = [c for c in sub["text"] if not any(ord(c) in f["cmap"] for f in sfonts)]
        if miss:
            die(f"no subtitle font file has a glyph for {''.join(miss)!r}", 1)
        scap = cap_px * float(sub.get("size_to_cap", 0.45))
        strack = scap * float(sub.get("tracking_em", 0.12)) * sfonts[0]["font"]["head"].unitsPerEm / sfonts[0]["cap"]
        sbase = baseline + scap + cap_px * 0.5
        spaths, sdx, sx, slo, shi = set_line(sfonts, sub["text"], scap, H + gap, sbase, strack)
        paths += spaths
        x, lo, hi = max(x, sx), min(lo, slo), max(hi, shi)
        sfs = round(scap * sfonts[0]["font"]["head"].unitsPerEm / sfonts[0]["cap"], 3)
    lo, hi = lo - 1, hi + 1  # a hairline of air so antialiasing is not clipped either
    width, height = round(x + 1, 2), round(hi - lo, 2)
    fs = round(cap_px * fonts[0]["font"]["head"].unitsPerEm / fonts[0]["cap"], 3)
    weight = spec.get("weight", 400)
    note = re.sub(r"-{2,}", "-", f'{name}: font {spec["family"]} {weight}, licence {spec.get("licence", "?")}')

    def doc(v, outlined):
        sym = symbol_svg(os.path.join(pkg, v["symbol"]), 0, 0, H)
        if outlined:
            txt = f'<path fill="{attr(v["text"])}" d="{" ".join(paths)}"/>'
        else:
            kern = f' dx="{" ".join(f"{d:.2f}" for d in dx)}"' if any(dx) else ""
            txt = (f'<text x="{H + gap:g}" y="{baseline:g}"{kern} fill="{attr(v["text"])}" font-family="{attr(spec["family"])}" '
                   f'font-weight="{attr(weight)}" font-size="{fs:g}">{escape(name)}</text>')
            if sub:
                txt += (f'<text class="subtitle" x="{H + gap:g}" y="{sbase:g}" fill="{attr(v.get("subtitle_text", v["text"]))}" '
                        f'font-family="{attr(sub.get("family", spec["family"]))}" font-weight="{attr(sub.get("weight", weight))}" '
                        f'font-size="{sfs:g}" letter-spacing="{float(sub.get("tracking_em", 0.12)):g}em">{escape(sub["text"])}</text>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {lo:g} {width:g} {height:g}" width="{width * 2:g}" '
                f'height="{height * 2:g}" role="img" aria-label="{attr(name)}"><!-- {escape(note)}; '
                f'{"text converted to outlines" if outlined else "live text, editable master"} -->{sym}{txt}</svg>\n')

    written = []

    def write(rel, data):
        p = os.path.join(pkg, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(data)
        written.append(os.path.relpath(p, a.root))
    write(f"source/{base}-master.svg", doc(variants[0], False))
    write(f"source/{base}-master-outlines.svg", doc(variants[0], True))
    for v in variants:
        write(f"logo/{base}-{v['id']}.svg", doc(v, True))
    print("\n".join(written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
