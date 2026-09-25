#!/usr/bin/env python3
"""aid-ui-ico.py - favicon.ico packer and icon-package check for /aid-ui step 1i.

  python3 aid-ui-ico.py <out.ico> <png>...   packs PNG images into an ICO (PNG-in-ICO
                                             entries); a non-PNG or a side above 256 -> exit 1
  python3 aid-ui-ico.py --verify <dir>       reports every expected icon file with its
                                             pixel size; exit 1 when one is missing or wrong.
                                             favicon.svg must use only allowed shape elements and
                                             attributes (SVG_ELEMENTS / SVG_ATTRS below) and have
                                             a square viewBox; no DOCTYPE or PI, UTF-8, at most
                                             512 KB and 64 levels deep

Exit: 0 ok, 1 refused / check failed, 2 usage. Python stdlib only.
"""
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

PNG_SIG = b"\x89PNG\r\n\x1a\n"
# What references/brand-icons.js writes, with the exact side in pixels.
EXPECTED_PNG = {
    "favicon-16.png": 16, "favicon-32.png": 32, "favicon-48.png": 48,
    "apple-touch-icon.png": 180, "icon-192.png": 192, "icon-512.png": 512,
    "icon-maskable-512.png": 512,
}
EXPECTED_ICO = [16, 32, 48]


def png_size(path):
    """(width, height) from the IHDR chunk, or None when the file is not a PNG."""
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != PNG_SIG or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def ico_sizes(path):
    """Entry sides of an ICO file (0 in the directory means 256), or None when not an ICO."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 6:
        return None
    reserved, kind, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or kind != 1 or len(data) < 6 + 16 * count:
        return None
    return [data[6 + 16 * i] or 256 for i in range(count)]


# favicon.svg is an allowlist: plain shapes and paint only. No <a>, animation, <style>,
# <text> (a symbol is drawn with curves), no style attribute, no remote url().
SVG_ELEMENTS = {
    "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs",
    "lineargradient", "radialgradient", "stop", "clippath", "mask", "symbol", "use",
    "title", "desc", "metadata",
}
SVG_ATTRS = {
    "id", "class", "d", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry",
    "width", "height", "points", "viewbox", "fill", "fill-rule", "fill-opacity", "stroke",
    "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
    "stroke-dasharray", "stroke-opacity", "opacity", "transform", "offset", "stop-color",
    "stop-opacity", "gradientunits", "gradienttransform", "spreadmethod", "fx", "fy",
    "clip-path", "clip-rule", "mask", "clippathunits", "maskunits", "preserveaspectratio",
    "version", "xmlns",
}
FRAGMENT = re.compile(r"#[A-Za-z_][\w.-]*")
URL_FRAGMENT = re.compile(r"url\(#[A-Za-z_][\w.-]*\)")
TRANSFORM = re.compile(r"\s*(?:(?:matrix|translate|scale|rotate|skewX|skewY)\s*\([-+0-9.eE,\s]*\)[\s,]*)+")
# ET.parse drops processing instructions and the DOCTYPE, and expat and a browser's libxml2
# disagree on DTDs, so both are refused on the raw text before parsing.
XML_DECL = re.compile(r"<\?xml\s[^?>]*\?>")
MARKUP_DECL = re.compile(r"<!(?:DOCTYPE|ENTITY|ATTLIST|ELEMENT)", re.I)
SVG_MAX_BYTES = 512 * 1024
SVG_MAX_DEPTH = 64


def svg_depth(el, depth=1):
    """True when the tree under el stays within SVG_MAX_DEPTH levels."""
    return depth <= SVG_MAX_DEPTH and all(svg_depth(c, depth + 1) for c in el)


def svg_problem(path):
    """Why the SVG is unsafe or not square, or None when it is fine."""
    try:
        with open(path, "rb") as f:
            raw = f.read(SVG_MAX_BYTES + 1)
    except OSError as e:
        return f"not readable ({e})"
    if len(raw) > SVG_MAX_BYTES:
        return f"larger than {SVG_MAX_BYTES // 1024} KB"
    try:
        text = raw.removeprefix(b"\xef\xbb\xbf").decode("utf-8")
    except UnicodeDecodeError:
        return "not UTF-8"
    decl = XML_DECL.match(text)
    if "\0" in text or (decl and re.search(r"encoding\s*=\s*[\"'](?!utf-8[\"'])", decl.group(), re.I)):
        return "not UTF-8"
    rest = text[decl.end():] if decl else text
    if "<?" in rest:
        return "has a processing instruction (only a leading <?xml ...?> is allowed)"
    if MARKUP_DECL.search(text):
        return "has a DOCTYPE or DTD declaration"
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        return f"not valid XML ({e})"
    if not svg_depth(root):
        return f"nested deeper than {SVG_MAX_DEPTH} elements"
    if root.tag.split("}")[-1] != "svg":
        return "root element is not <svg>"
    for el in root.iter():  # comments and PIs are not in the tree (PIs refused above)
        tag = el.tag.split("}")[-1].lower()
        if tag not in SVG_ELEMENTS:
            return f"contains <{tag}>, not an allowed shape element"
        if tag == "metadata" and len(el):
            return "<metadata> may hold text only"
        for k, v in el.attrib.items():
            k = k.split("}")[-1].lower()
            if k == "href":
                if tag != "use" or not FRAGMENT.fullmatch(v.strip()):
                    return f"<{tag}> has href {v[:60]}; only <use href=\"#id\"> is allowed"
                continue
            if k not in SVG_ATTRS:
                return f"<{tag}> has the attribute {k}, not an allowed one"
            if "\\" in v:  # presentation attributes parse as CSS: u\72l( is url(
                return f"<{tag}> {k} has a backslash escape"
            if "(" in v and not URL_FRAGMENT.fullmatch(v.strip()) and not (
                    k in ("transform", "gradienttransform") and TRANSFORM.fullmatch(v)):
                return f"<{tag}> {k}={v[:60]} is neither url(#id) nor a plain transform"
    vb = re.split(r"[\s,]+", root.get("viewBox", "").strip())
    try:
        w, h = float(vb[2]), float(vb[3])
    except (IndexError, ValueError):
        return "no viewBox"
    return None if len(vb) == 4 and w == h > 0 else f"viewBox {' '.join(vb)} is not square"


def pack(out, pngs):
    images = []
    for p in pngs:
        size = png_size(p)
        if size is None:
            sys.exit(f"ERROR: not a PNG: {p}")
        if max(size) > 256:
            sys.exit(f"ERROR: {p} is {size[0]}x{size[1]}; an ICO entry is at most 256 px")
        with open(p, "rb") as f:
            images.append((size, f.read()))
    offset = 6 + 16 * len(images)
    header = struct.pack("<HHH", 0, 1, len(images))
    entries = b""
    for (w, h), data in images:
        entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    with open(out, "wb") as f:
        f.write(header + entries + b"".join(d for _, d in images))
    print(f"wrote {out}: " + ", ".join(f"{w}x{h}" for (w, h), _ in images))


def verify(d):
    bad = 0
    for name, side in EXPECTED_PNG.items():
        p = os.path.join(d, name)
        size = png_size(p) if os.path.isfile(p) else None
        if size == (side, side):
            print(f"OK      {name} {side}x{side}")
        else:
            got = "missing" if not os.path.isfile(p) else ("not a PNG" if size is None else f"{size[0]}x{size[1]}")
            print(f"WRONG   {name} expected {side}x{side}, got {got}")
            bad += 1
    p = os.path.join(d, "favicon.ico")
    sizes = ico_sizes(p) if os.path.isfile(p) else None
    if sizes is not None and sorted(sizes) == EXPECTED_ICO:
        print("OK      favicon.ico " + "/".join(map(str, EXPECTED_ICO)))
    else:
        print(f"WRONG   favicon.ico expected {'/'.join(map(str, EXPECTED_ICO))}, got "
              + ("missing" if not os.path.isfile(p) else "not an ICO" if sizes is None else "/".join(map(str, sizes))))
        bad += 1
    p = os.path.join(d, "favicon.svg")
    problem = svg_problem(p) if os.path.isfile(p) else "missing"
    if problem is None:
        print("OK      favicon.svg")
    else:
        print(f"WRONG   favicon.svg {problem}")
        bad += 1
    return 1 if bad else 0


def main(argv):
    if len(argv) == 2 and argv[0] == "--verify":
        return verify(argv[1])
    if len(argv) >= 2 and not argv[0].startswith("-"):
        pack(argv[0], argv[1:])
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
