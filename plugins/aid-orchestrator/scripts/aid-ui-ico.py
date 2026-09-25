#!/usr/bin/env python3
"""aid-ui-ico.py - favicon.ico packer and icon-package check for /aid-ui step 1i.

  python3 aid-ui-ico.py <out.ico> <png>...   packs PNG images into an ICO (PNG-in-ICO
                                             entries); a non-PNG or a side above 256 -> exit 1
  python3 aid-ui-ico.py --verify <dir>       reports every expected icon file with its
                                             pixel size; exit 1 when one is missing or wrong

Exit: 0 ok, 1 refused / check failed, 2 usage. Python stdlib only.
"""
import os
import struct
import sys

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
    if os.path.isfile(p) and os.path.getsize(p) > 0:
        print("OK      favicon.svg")
    else:
        print("WRONG   favicon.svg missing or empty")
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
