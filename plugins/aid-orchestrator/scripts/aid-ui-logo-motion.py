#!/usr/bin/env python3
"""aid-ui-logo-motion.py - the motion of a finished mark (P113 step 8; references/local/pohyb-znacky.md).

  python3 aid-ui-logo-motion.py <spec.json> <out-dir>

Input (JSON): {viewBox: "0 0 256 256", parts: [{id, d, fill?, strokes: [{d, width, delay, dur}]}],
name?: {text, x, y, size?, family?, fill?}, web_ms?: 900, video_ms?: 2500, overlap?: 14, ease?}.
`parts` are the approved mark split into its pieces (their union is the approved SVG); each part is revealed by its
pen strokes (a CSS mask: a stroke drawn along `d` with stroke-dasharray), in the order and relative timing of
`delay`/`dur` (any unit; scaled). Writes:
  logo-animace.html        the web version: the whole mark drawn within web_ms (at most 1000 ms), the name and
                           subtitle readable from the first frame (never animated), nothing running after it
  logo-animace-video.html  the video/presentation version: the same drawing in video_ms (2000-3000 ms), the end held
  logo-motion.css          the shared animation rules
  motion.json              the computed timing per version (draw end, name animated: false) for the gate and the roles
Seamless end (fix 63): every mask stroke is `overlap` units wider than its stroke and has square caps, so the masks
overrun the straight ends of the shape; when a version ends every mask is switched off (`mask: none`), leaving
exactly the approved paths. Without JavaScript or with prefers-reduced-motion the final state shows at once (the
animation runs only under html.anim, which an inline script sets). No browser needed; no absolute paths written.
Exit 0 written, 1 invalid spec, 2 usage.
"""
import html, json, os, re, sys

WEB_MAX, VIDEO_MIN, VIDEO_MAX = 1000, 2000, 3000
EASE = "cubic-bezier(.35,.15,.25,1)"   # fast start, long settle; no spring (pohyb-znacky.md, tempo)


def die(msg, code=1):
    print("ERROR: aid-ui-logo-motion.py: " + msg, file=sys.stderr)
    sys.exit(code)


def check(spec):
    if not re.fullmatch(r"-?[\d.]+ -?[\d.]+ [\d.]+ [\d.]+", str(spec.get("viewBox", ""))):
        die("viewBox must be 'x y w h'")
    parts = spec.get("parts")
    if not isinstance(parts, list) or not parts:
        die("parts: at least one part of the mark")
    for p in parts:
        if not (isinstance(p.get("id"), str) and re.fullmatch(r"[A-Za-z][\w-]*", p["id"]) and isinstance(p.get("d"), str) and p["d"].strip()):
            die(f"part {p.get('id')!r}: needs an id (letters, digits, -) and its path d")
        ss = p.get("strokes")
        if not isinstance(ss, list) or not ss:
            die(f"part {p['id']}: needs at least one pen stroke")
        for s in ss:
            if not (isinstance(s.get("d"), str) and all(isinstance(s.get(k), (int, float)) and s[k] >= 0 for k in ("width", "delay", "dur")) and s["dur"] > 0):
                die(f"part {p['id']}: a stroke needs d, width, delay >= 0 and dur > 0")
    web, video = spec.get("web_ms", 900), spec.get("video_ms", 2500)
    if not (0 < web <= WEB_MAX):
        die(f"web_ms {web}: the web version draws within {WEB_MAX} ms (PM F6, pohyb-znacky.md limits)")
    if not (VIDEO_MIN <= video <= VIDEO_MAX):
        die(f"video_ms {video}: the video version runs {VIDEO_MIN}-{VIDEO_MAX} ms")
    return web, video


def timing(parts, total):
    """Stroke delays and durations scaled so the last stroke ends exactly at total ms."""
    end = max(s["delay"] + s["dur"] for p in parts for s in p["strokes"])
    k = total / end
    return [[(round(s["delay"] * k), round(s["dur"] * k)) for s in p["strokes"]] for p in parts]


def svg(spec, ver, times):
    vb, ov = spec["viewBox"], spec.get("overlap", 14)
    masks, paths = [], []
    for p, ts in zip(spec["parts"], times):
        ms = "".join(f'<path class="pen" d="{html.escape(s["d"])}" pathLength="1" stroke="#fff" fill="none" stroke-linecap="square" '
                     f'stroke-linejoin="round" stroke-width="{s["width"] + ov}" style="--delay:{d}ms;--dur:{u}ms"/>'
                     for s, (d, u) in zip(p["strokes"], ts))
        masks.append(f'<mask id="m-{ver}-{p["id"]}" maskUnits="userSpaceOnUse">{ms}</mask>')
        paths.append(f'<path class="part" data-part="{p["id"]}" d="{html.escape(p["d"])}" fill="{html.escape(p.get("fill", "currentColor"))}" mask="url(#m-{ver}-{p["id"]})"/>')
    nm = spec.get("name") or {}
    name = (f'<text class="name" x="{nm.get("x", 0)}" y="{nm.get("y", 0)}" font-size="{nm.get("size", 24)}" '
            f'font-family="{html.escape(nm.get("family", "system-ui, sans-serif"))}" fill="{html.escape(nm.get("fill", "currentColor"))}">{html.escape(nm["text"])}</text>'
            if nm.get("text") else "")
    return (f'<svg class="mark" viewBox="{vb}" role="img" aria-label="{html.escape(nm.get("text", "logo"))}" xmlns="http://www.w3.org/2000/svg">'
            f'<defs>{"".join(masks)}</defs>{"".join(paths)}{name}</svg>')


CSS = """/* aid-ui-logo-motion.py: the mark is drawn by masks; the name is never animated */
.mark .pen{stroke-dasharray:1 1;stroke-dashoffset:0}
html.anim .mark .pen{stroke-dashoffset:1;animation:aid-draw var(--dur) %(ease)s var(--delay) forwards}
html.anim .mark .part{animation:aid-unmask 0s linear var(--end) forwards}
@keyframes aid-draw{to{stroke-dashoffset:0}}
@keyframes aid-unmask{to{mask:none;-webkit-mask:none}}
@media (prefers-reduced-motion:reduce){html.anim .mark .pen{animation:none;stroke-dashoffset:0}html.anim .mark .part{animation:none;mask:none}}
.mark .name{animation:none}
"""


def page(spec, ver, times, end):
    return ("<!doctype html>\n<html lang=\"cs\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            f"<title>Logo - {'web' if ver == 'web' else 'video'}</title><link rel=\"stylesheet\" href=\"logo-motion.css\">"
            f"<style>body{{margin:0;display:grid;place-items:center;min-height:100vh}}.mark{{width:min(80vw,640px);--end:{end}ms}}</style>"
            "<script>document.documentElement.classList.add('anim')</script></head>\n"
            f"<body>{svg(spec, ver, times)}</body></html>\n")


def main(a):
    if len(a) != 2:
        die("usage: aid-ui-logo-motion.py <spec.json> <out-dir>", 2)
    try:
        spec = json.load(open(a[0], encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"{a[0]}: {e}")
    web, video = check(spec)
    out = a[1]
    os.makedirs(out, exist_ok=True)
    rec = {}
    for ver, total, fn in (("web", web, "logo-animace.html"), ("video", video, "logo-animace-video.html")):
        times = timing(spec["parts"], total)
        with open(os.path.join(out, fn), "w", encoding="utf-8") as f:
            f.write(page(spec, ver, times, total))
        rec[ver] = {"file": fn, "draw_end_ms": max(d + u for ts in times for d, u in ts), "name_animated": False,
                    "strokes": sum(len(ts) for ts in times), "overlap": spec.get("overlap", 14)}
    with open(os.path.join(out, "logo-motion.css"), "w", encoding="utf-8") as f:
        f.write(CSS % {"ease": spec.get("ease", EASE)})
    with open(os.path.join(out, "motion.json"), "w", encoding="utf-8") as f:
        json.dump(rec, f, ensure_ascii=False, indent=1)
    print(json.dumps(rec, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
