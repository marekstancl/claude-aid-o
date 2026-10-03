#!/usr/bin/env python3
"""aid-ui-vision-check.py - does docs/product-vision.md carry the parts of the ecosystem template
(templates/product-vision-prompt.md, layer 1) and its honesty rules? The gate's vision_doc row.

  python3 aid-ui-vision-check.py <project>

Checked (case-insensitive, in headings or bold labels of the document): the problem; for whom;
the change of behaviour or how success is recognised; the elevator pitch; the boundaries (what
the product does not do); key functions; the ecosystem; competition or differentiators;
legislation; at least one FAKT (the FAKT/ODHAD/HYPOTÉZA labelling); an owner and a date. Whether the vision is true and well written is the PM's
approval of the vision chapter, not this script.
Output `MISSING|OK vision <what>`; exit 0 complete, 1 something missing, 2 usage.
"""
import os, re, sys

PARTS = [("problem", r"probl[ée]m"), ("for whom", r"pro koho|z[áa]kazn[íi]k|c[íi]lov"),
         ("change of behaviour / success", r"zm[ěe]na chov[áa]n[íi]|[úu]sp[ěe]ch"), ("elevator pitch", r"elevator pitch"),
         ("boundaries", r"hranice|ned[ěe]l[áa]"), ("key functions", r"kl[íi][čc]ov[ée] funkce|funkce|slu[žz]by"),
         ("ecosystem", r"ekosyst[ée]m"), ("competition or differentiators", r"konkurenc|diferenc|[čc][íi]m se li[šs]"),
         ("legislation", r"legislativ|gdpr|norm")]


def main():
    if len(sys.argv) != 2:
        print("usage: aid-ui-vision-check.py <project>", file=sys.stderr)
        return 2
    try:
        text = open(os.path.join(sys.argv[1], "docs/product-vision.md"), encoding="utf-8").read()
    except OSError as e:
        print(f"MISSING vision docs/product-vision.md ({e.strerror})")
        return 1
    heads = " \n".join(re.findall(r"^#+\s+(.+)$", text, re.M) + re.findall(r"\*\*([^*]{2,60})\*\*", text)).lower()
    res = [(bool(re.search(p, heads)), f"part: {n}") for n, p in PARTS]
    res.append((bool(re.search(r"\bFAKT\b", text)), "at least one claim marked FAKT"))
    res.append((bool(re.search(r"vlastn[íi]k\s*:", text, re.I)), "owner (Vlastník:)"))
    res.append((bool(re.search(r"datum\s*:\s*\d{1,2}\.\s*\d{1,2}\.\s*\d{4}|\d{4}-\d{2}-\d{2}", text, re.I)), "date"))
    for ok, what in sorted(res, key=lambda x: x[0]):
        print("OK" if ok else "MISSING", "vision", what)
    return 0 if all(r[0] for r in res) else 1


if __name__ == "__main__":
    sys.exit(main())
