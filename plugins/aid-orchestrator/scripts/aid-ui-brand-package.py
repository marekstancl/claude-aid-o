#!/usr/bin/env python3
"""aid-ui-brand-package.py - is the project's brand package complete for what the project uses?

  python3 aid-ui-brand-package.py <project> [--json out.json]

The required list is derived, never fixed (design-system standard, "Brand balíček": only what
the project really uses; brand-brief template part 2), from docs/design/brand-state.json and
the logo brief docs/design/brief-logo-favicon.md:
  - variant.brand "none" (an internal tool): a favicon only (icons/favicon.svg or .ico); the
    name is the build's business, not the package's;
  - otherwise (options.identity "new" or "package", or variant.brand "existing"): symbol/
    color, black, white, on-dark (SVG); icons/ favicon.svg, favicon.ico holding 16, 32 and
    48 px, apple-touch-icon 180, a 192 and a 512 px PNG; brand-brief.md; README.md; logo/ with
    the name in colour (SVG and PNG) for every web, webapp and PWA (a product with a public
    face), on-dark too for a web or PWA; source/ an editable master whose SVG keeps live
    <text> (the logo's name) and beside it a version in outlines (no <text>);
  - contexts of use (section "Kontexty použití" / "Kde bude značka žít" of the brief, up to the
    next heading of the same level) only add: print, fax, stamp, business card -> the black
    logo; PWA or an installation context -> maskable icon and lockup/ light and dark;
  - brand work without the brief or without that section is itself MISSING.
Variants are told by whole name tokens of the path under the part (lockup/a/dark/x.svg is
dark), never by substrings ("mobile" is not white).
A PM waiver (aid-ui-state.sh brand-waive, an exception answer whose target names exactly the
missing parts) makes the result WAIVED when the missing list is exactly the waived one.
Output lines `MISSING|OK|WAIVED <part> <what>`; --json writes {required, present, missing,
waived, files, per_folder}; exit 0 complete or waived, 1 a required part missing, 2 usage or
an inconsistent state (brand "none" with identity work).
"""
import argparse, json, os, re, struct, sys

TOKENS = {"color": {"color", "colour", "barevne", "barevny", "barva", "full"},
          "black": {"black", "cerne", "cerny", "mono"},
          "white": {"white", "bile", "bily", "inverse"},
          "dark": {"dark", "tmave", "tmavy", "ondark"}}
OUTLINE = {"outline", "outlines", "outlined", "krivky", "krivkach", "curves", "paths"}
PRINT_CTX = r"\b(tisk\w*|print\w*|fax\w*|raz[ií]tk\w*|vizitk\w*)\b"
PWA_CTX = r"\b(pwa|instalac\w*|nainstalovan\w*)\b"


def tokens(rel):
    """whole lower-case tokens of a path, accents dropped, 'on-dark' also as 'ondark'"""
    s = rel.lower().translate(str.maketrans("áčďéěíňóřšťúůýž", "acdeeinorstuuyz"))
    toks = [t for t in re.split(r"[-_./\s]+", os.path.splitext(s)[0]) if t]
    return set(toks) | {a + b for a, b in zip(toks, toks[1:])}


def variant_of(rel):
    t = tokens(rel)
    if t & TOKENS["dark"]:
        return "dark"
    for v in ("black", "white", "color"):
        if t & TOKENS[v]:
            return v
    return None


def pick(fs, part, ext, want=None, extra=None):
    """the first file under part/ with this extension whose variant is `want` (None = any)
    and, when given, whose tokens include one of `extra`"""
    for f in fs:
        if not f.startswith(part + "/") or not f.lower().endswith(ext):
            continue
        sub = f[len(part) + 1:]
        if want and variant_of(sub) != want:
            continue
        if extra and not tokens(sub) & extra:
            continue
        return f
    return None


def ico_sizes(path):
    try:
        with open(path, "rb") as fh:
            head = fh.read(6)
            _, kind, n = struct.unpack("<HHH", head)
            return {(fh.read(16)[0] or 256) for _ in range(n)} if kind == 1 else set()
    except (OSError, struct.error):
        return set()


def contexts(project):
    try:
        text = open(os.path.join(project, "docs/design/brief-logo-favicon.md"), encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"^(#+)\s*(Kontexty použití|Kde bude značka žít).*$", text, re.M | re.I)
    if not m:
        return None
    rest = text[m.end():]
    end = re.search(r"^#{1,%d}\s" % len(m.group(1)), rest, re.M)
    return (rest[:end.start()] if end else rest).lower()


def required(project, state, root):
    """[(part, what, test)]: test(files) -> matching file or None; raises ValueError when the
    state is inconsistent."""
    variant, ident = state.get("variant") or {}, (state.get("options") or {}).get("identity")
    vtype, brand = variant.get("type"), variant.get("brand")
    if brand == "none" and ident:
        raise ValueError(f"variant.brand is 'none' (no brand) but options.identity is {ident!r}")
    if brand == "none" or (not ident and brand != "existing"):
        return [("icons", "favicon (svg or ico)",
                 lambda fs: pick(fs, "icons", ".svg", extra={"favicon"}) or pick(fs, "icons", ".ico", extra={"favicon"}))]
    req = [("symbol", f"symbol {v} (SVG)", lambda fs, v=v: pick(fs, "symbol", ".svg", v))
           for v in ("color", "black", "white", "dark")]
    req.append(("icons", "favicon.svg", lambda fs: pick(fs, "icons", ".svg", extra={"favicon"})))

    def ico(fs):
        f = pick(fs, "icons", ".ico", extra={"favicon"})
        return f if f and {16, 32, 48} <= ico_sizes(os.path.join(root, f)) else None
    req.append(("icons", "favicon.ico with 16, 32 and 48 px", ico))
    for what, extra in (("apple-touch-icon 180 px", {"apple", "180"}), ("icon 192 px", {"192"}), ("icon 512 px", {"512"})):
        req.append(("icons", what, lambda fs, extra=extra: pick(fs, "icons", ".png", extra=extra)))
    req.append(("brand-brief.md", "rules of use", lambda fs: "brand-brief.md" if "brand-brief.md" in fs else None))
    req.append(("README.md", "what is in the package", lambda fs: "README.md" if "README.md" in fs else None))
    ctx = contexts(project)
    if ctx is None:
        req.append(("brief", "docs/design/brief-logo-favicon.md with a 'Kontexty použití' section", lambda fs: None))
        ctx = ""
    logo = ["color"] + (["dark"] if vtype in ("web", "pwa") else []) + (["black"] if re.search(PRINT_CTX, ctx) else [])
    for v in logo:
        for ext in (".svg", ".png"):
            req.append(("logo", f"logo with the name, {v} ({ext[1:].upper()})", lambda fs, v=v, ext=ext: pick(fs, "logo", ext, v)))

    def live(fs, outlined):
        for f in fs:
            if f.startswith("source/") and f.lower().endswith(".svg") and bool(tokens(f[7:]) & OUTLINE) == outlined:
                try:
                    has_text = "<text" in open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                if has_text != outlined:
                    return f
        return None
    req.append(("source", "editable master with the name as live <text> (SVG)", lambda fs: live(fs, False)))
    req.append(("source", "the same in outlines, no <text> (SVG, named *outlines*)", lambda fs: live(fs, True)))
    if vtype == "pwa" or re.search(PWA_CTX, ctx):
        req.append(("icons", "maskable icon (PNG)", lambda fs: pick(fs, "icons", ".png", extra={"maskable"})))
        for v in ("light", "dark"):
            req.append(("lockup", f"lockup {v}", lambda fs, v=v: next(
                (f for f in fs if f.startswith("lockup/") and f.endswith(".svg") and (variant_of(f[7:]) == "dark") == (v == "dark")), None)))
    return req


def main():
    ap = argparse.ArgumentParser(description="brand package completeness for what the project uses")
    ap.add_argument("project")
    ap.add_argument("--json")
    a = ap.parse_args()
    try:
        state = json.load(open(os.path.join(a.project, "docs/design/brand-state.json"), encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"ERROR: aid-ui-brand-package.py: no readable docs/design/brand-state.json: {e}", file=sys.stderr)
        return 2
    root = os.path.join(a.project, "docs/design/brand-package")
    fs = sorted(os.path.relpath(os.path.join(b, n), root) for b, _, ns in os.walk(root) for n in ns if not n.startswith("."))
    try:
        req = required(a.project, state, root)
    except ValueError as e:
        print(f"ERROR: aid-ui-brand-package.py: {e}", file=sys.stderr)
        return 2
    out, missing = [], []
    for part, what, test in req:
        hit = test(fs)
        out.append(["OK" if hit else "MISSING", part, f"{what}: {hit}" if hit else what])
        if not hit:
            missing.append(f"{part}: {what}")
    waiver = state.get("brand_package_waiver") or {}
    waived = bool(missing) and sorted(waiver.get("missing") or []) == sorted(missing)
    if waived:
        for line in out:
            if line[0] == "MISSING":
                line[0] = "WAIVED"
                line[2] += f" (PM waiver, answer {waiver.get('answer')})"
    out.sort(key=lambda x: x[0] == "OK")
    for line in out:
        print(" ".join(line))
    if a.json:
        per = {}
        for x in fs:
            k = x.split("/")[0] if "/" in x else "."
            per[k] = per.get(k, 0) + 1
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"required": len(out), "present": len(out) - len(missing), "missing": missing,
                       "waived": waived, "files": len(fs), "per_folder": per}, f, ensure_ascii=False, indent=1)
    return 0 if not missing or waived else 1


if __name__ == "__main__":
    sys.exit(main())
