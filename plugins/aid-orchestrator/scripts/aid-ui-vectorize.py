#!/usr/bin/env python3
"""aid-ui-vectorize.py - a generated raster concept (step 1i) as a clean black SVG symbol.
Run through `aid-ui-tool.sh vectorize` (it provides vtracer in ~/.cache/aid-ui/pyvec).
  aid-ui-vectorize.py <in.png> <out.svg> [--speckle N] [--corner N] [--length F] [--size N]
vtracer (binary mode, splines) traces the dark shape; the result is rewritten as one <svg> with
viewBox 0 0 <size> <size> (default 256), the paths scaled into it with a 6 % margin, fill #111,
no stroke, a <title>, nothing else (vtracer's own colours, transforms and metadata are dropped).
A raster is a concept: this vector is what the card, the audit and the 16 px test use.
Exit: 0, 1 unreadable input or no shape found, 2 usage.
"""
import os, re, sys, tempfile
try:
    import vtracer
except ImportError:
    sys.exit("ERROR: aid-ui-vectorize.py: vtracer missing; run it through aid-ui-tool.sh vectorize")


def die(msg, code=1):
    print("ERROR: aid-ui-vectorize.py: %s" % msg, file=sys.stderr)
    sys.exit(code)


def main():
    a = sys.argv[1:]
    opts = {"speckle": 8, "corner": 60, "length": 4.0, "size": 256}
    pos = []
    i = 0
    while i < len(a):
        if a[i].startswith("--") and a[i][2:] in opts and i + 1 < len(a):
            k = a[i][2:]
            try:
                opts[k] = float(a[i + 1]) if k == "length" else int(a[i + 1])
            except ValueError:
                die("bad value for --%s" % k, 2)
            i += 2
        else:
            pos.append(a[i]); i += 1
    if len(pos) != 2 or not pos[1].lower().endswith(".svg"):
        die("usage: aid-ui-vectorize.py <in.png> <out.svg> [--speckle N] [--corner N] [--length F] [--size N]", 2)
    src, dst = pos
    if not os.path.isfile(src):
        die("no input %s" % src)
    tmp = tempfile.NamedTemporaryFile(suffix=".svg", delete=False).name
    bw = tempfile.NamedTemporaryFile(suffix=".png", delete=False).name
    try:
        # the model's PNG (transparent or any background) becomes pure black on white first: alpha is
        # composited on white, luminance thresholded at 128 - vtracer's binary mode then sees only the mark
        from PIL import Image
        im = Image.open(src).convert("RGBA")
        base = Image.new("RGBA", im.size, (255, 255, 255, 255))
        base.alpha_composite(im)
        base.convert("L").point(lambda v: 0 if v < 128 else 255, "1").save(bw)
        vtracer.convert_image_to_svg_py(bw, tmp, colormode="binary", mode="spline", filter_speckle=opts["speckle"],
                                        corner_threshold=opts["corner"], length_threshold=opts["length"],
                                        splice_threshold=45, path_precision=2)
        raw = open(tmp, encoding="utf-8").read()
    except Exception as e:   # vtracer raises plain exceptions on bad images
        die("vtracer failed on %s: %s" % (src, e))
    finally:
        for t in (tmp, bw):
            try:
                os.remove(t)
            except OSError:
                pass
    vb = re.search(r'viewBox="([^"]+)"', raw)
    w = h = None
    if vb:
        _, _, w, h = (float(x) for x in vb.group(1).split())
    else:
        mw, mh = re.search(r'width="([\d.]+)', raw), re.search(r'height="([\d.]+)', raw)
        if mw and mh:
            w, h = float(mw.group(1)), float(mh.group(1))
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"', raw)
    paths = [d for d in paths if not _is_background(d, w, h)]
    if not paths or not w or not h:
        die("no shape found in %s" % src)
    # bounds of all path points (vtracer writes absolute coordinates with M/L/C/Q)
    nums = [float(x) for d in paths for x in re.findall(r"-?\d+\.?\d*", d)]
    xs, ys = nums[0::2], nums[1::2]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    side = max(maxx - minx, maxy - miny) or 1.0
    if side < 0.2 * max(w, h):
        die("the shape found spans only %.0f%% of the image - a speck, not a mark (%s)" % (100 * side / max(w, h), src))
    size = opts["size"]
    scale = size * 0.88 / side
    tx = (size - (maxx - minx) * scale) / 2 - minx * scale
    ty = (size - (maxy - miny) * scale) / 2 - miny * scale
    body = "".join('  <path fill="#111" fill-rule="evenodd" d="%s"/>\n' % d for d in paths)
    out = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-labelledby="t">\n'
           '  <title id="t">%s</title>\n  <!-- aid-ui-vectorize: vtracer binary/spline speckle=%d corner=%d length=%s from %s -->\n'
           '  <g transform="translate(%.2f %.2f) scale(%.5f)">\n%s  </g>\n</svg>\n'
           % (size, size, size, size, os.path.splitext(os.path.basename(dst))[0], opts["speckle"], opts["corner"], opts["length"],
              os.path.basename(src), tx, ty, scale, body))
    with open(dst, "w", encoding="utf-8") as f:
        f.write(out)
    print("%s: %d path(s), %d points, from %s" % (dst, len(paths), len(xs), src))


def _is_background(d, w, h):
    """vtracer's first path is often the white page rectangle; drop a path that spans the whole image."""
    if not w or not h:
        return False
    nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", d)]
    if len(nums) < 8:
        return False
    xs, ys = nums[0::2], nums[1::2]
    return min(xs) <= 1 and min(ys) <= 1 and max(xs) >= w - 1 and max(ys) >= h - 1


if __name__ == "__main__":
    main()
