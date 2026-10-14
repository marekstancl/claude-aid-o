#!/usr/bin/env python3
"""aid-ui-photos.py - the client's own photos (P113a, PM 13. 10. 2026: the old site had five good photos of the
clinic and nobody saw them, because only its text was fetched).

  candidates <project>
      Every photo the sources step fetched from the old site (.aid-ui/old-site/*/fetch.json images with a file)
      into .aid-ui/photos/candidates.json {id c1.., file, url, page, alt, width, height, people: null}.
      Kept marks survive a rerun (same file). The same picture in a smaller size (a CDN size segment such as
      /700/ in the path) is dropped for the largest.
  mark <project> <candidate> --people yes|no [--note <t>] [--describe <what is on it>] | --skip
      (--skip: not a photo, e.g. a logo or a graphic; never offered)
      The agent LOOKED at the photo: is a recognisable person on it (consent needed)? A question shows only
      candidates the agent has looked at.
  question <project> <slot id>
      The studio question (kind photos, part obsah) for one slot of docs/content/photos.yaml: up to five
      candidates closest to the slot's ratio (and not smaller than half its min_px), each a card with a preview,
      size and page, a person on it named as the risk; plus the card "keep" (keep the frame, a new photo
      follows). target = photo@<slot>@<sha of the cards>. Writes the previews into .aid-ui/studio/previews/.
  apply <project> --answer <question id>
      The client's answer (brand-state.json answers, kind photos, this question's target). choose <candidate>:
      the photo becomes docs/content/photos/<slot>.webp (at most 1600 px, 200 kB, aid-ui-tool.sh webp) and
      <slot>-800.webp for phones (srcset), and every
      photos.yaml entry of the slot gets src, src_from and alt (the agent's --describe of what is on the photo, else
      the old site's alt; neither = refused: the brief's "what" is not a description of the photo). The description is
      registered in docs/content/facts.yaml as foto_<slot> (the photo's address, chosen by the client) - it is copy. choose keep: nothing changes. An answer
      is used once.
Exit 0 done, 1 refused, 2 usage.
"""
import hashlib, json, os, re, subprocess, sys, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.environ.get("AID_UI_TOOL") or os.path.join(HERE, "aid-ui-tool.sh")


def die(msg, code=1):
    print("ERROR: aid-ui-photos.py: " + msg, file=sys.stderr)
    sys.exit(code)


def cpath(p):
    return os.path.join(p, ".aid-ui", "photos", "candidates.json")


def load(p):
    try:
        return json.load(open(cpath(p), encoding="utf-8"))
    except (OSError, ValueError):
        return {"candidates": [], "used_answers": []}


def save(p, d):
    os.makedirs(os.path.dirname(cpath(p)), exist_ok=True)
    tmp = cpath(p) + ".part"
    json.dump(d, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.replace(tmp, cpath(p))


SLOT_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,40}$")


def yq_set(path, expr, **env):
    """yq -i with every value passed through the environment (strenv/env), never pasted into the expression."""
    subprocess.run(["yq", "-i", expr, path], check=True, env={**os.environ, **{k: str(v) for k, v in env.items()}})


def yq(path):
    r = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
    if r.returncode:
        die("cannot read %s: %s" % (path, r.stderr.strip()))
    return json.loads(r.stdout or "null")


def candidates(p):
    old = {c["file"]: c for c in load(p)["candidates"]}
    base = os.path.join(p, ".aid-ui", "old-site")
    out = []
    for site in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        fj = os.path.join(base, site, "fetch.json")
        if not os.path.isfile(fj):
            continue
        for im in json.load(open(fj, encoding="utf-8")).get("images") or []:
            if not im.get("file"):
                continue
            f = os.path.join(base, site, im["file"])
            keep = old.get(f, {})
            out.append({"file": f, "url": im["url"], "page": im.get("page"), "alt": im.get("alt") or "", "describe": keep.get("describe"),
                        "width": im["width"], "height": im["height"], "people": keep.get("people"), "note": keep.get("note"),
                        "skip": keep.get("skip")})
    # the same picture in a smaller size (a CDN size segment such as /700/ in its path): only the largest stays
    same = lambda c: re.sub(r"/\d{2,4}(?=/)", "", urllib.parse.urlsplit(c["url"]).path)
    big = {}
    for c in out:
        k = same(c)
        if k not in big or c["width"] * c["height"] > big[k]["width"] * big[k]["height"]:
            big[k] = c
    out = [c for c in out if big[same(c)] is c]
    for i, c in enumerate(out, 1):
        c["id"] = "c%d" % i
    d = load(p)
    d["candidates"] = out
    save(p, d)
    for c in out:
        print("%-4s %5dx%-5d people=%-5s%s %s" % (c["id"], c["width"], c["height"], c["people"], " SKIP" if c.get("skip") else "", c["url"][-60:]))
    if not out:
        print("no photos from the old site (fetch the old site with aid-ui-sources.py --fetch-site)")


def find(d, cid):
    c = next((x for x in d["candidates"] if x["id"] == cid), None)
    if not c:
        die("no candidate %s (run candidates)" % cid)
    return c


def mark(p, cid, people, note, skip=False, describe=None):
    if people not in ("yes", "no") and not skip:
        die("--people yes|no, or --skip (not a photo: a logo, a graphic)", 2)
    d = load(p)
    c = find(d, cid)
    if skip:
        c["skip"], c["people"] = True, False
    else:
        c["people"], c["skip"] = people == "yes", None
    c["note"] = (note or "").strip() or None
    if describe is not None:
        c["describe"] = describe.strip() or None
    save(p, d)
    print("%s people=%s" % (cid, c["people"]))


def slot_spec(p, slot):
    if not SLOT_ID.match(slot or ""):
        die("slot id %r is not [a-z0-9_-]" % slot, 2)
    ph = yq(os.path.join(p, "docs", "content", "photos.yaml"))
    entries = [x for x in (ph or []) if isinstance(x, dict) and x.get("id") == slot]
    if not entries:
        die("no slot %s in docs/content/photos.yaml" % slot)
    return entries


def ratio(s):
    a, b = (float(x) for x in str(s).split(":"))
    return a / b


def question(p, slot):
    spec = slot_spec(p, slot)[0]
    want = ratio(spec["ratio"])
    minw, minh = (int(x) for x in str(spec["min_px"]).split("x"))
    d = load(p)
    fit = [c for c in d["candidates"] if max(c["width"], c["height"]) >= max(minw, minh) / 2 and not c.get("skip")]
    unseen = [c["id"] for c in fit if c["people"] is None]
    if unseen:
        die("look at the photos first and mark them (mark <candidate> --people yes|no): " + ", ".join(unseen))
    fit.sort(key=lambda c: (abs(c["width"] / c["height"] - want), -c["width"]))
    fit = fit[:5]
    prev = os.path.join(p, ".aid-ui", "studio", "previews")
    os.makedirs(prev, exist_ok=True)
    cards = []
    for c in fit:
        out = os.path.join(prev, "photo-%s-%s.webp" % (slot, c["id"]))
        r = subprocess.run(["bash", TOOL, "webp", c["file"], out, "640", "0.8"], capture_output=True, text=True)
        if r.returncode:
            die("preview of %s failed: %s" % (c["id"], (r.stderr or r.stdout).strip()[-200:]))
        page = urllib.parse.urlsplit(c.get("page") or "").path.strip("/").rsplit("/", 1)[-1] or "úvod"
        cards.append({"id": c["id"], "question": "photo-" + slot, "title": "Fotka zo starého webu (%s)" % page,
                      "thesis": "%d×%d px%s" % (c["width"], c["height"], " · " + c["alt"] if c["alt"] else ""),
                      "preview": os.path.relpath(out, os.path.join(p, ".aid-ui", "studio")),
                      **({"risk": "Na fotke je človek: použijeme ju len s jeho súhlasom" + (" (%s)" % c["note"] if c.get("note") else "")} if c["people"] else {})})
    cards.append({"id": "keep", "question": "photo-" + slot, "title": "Ponechať rámček, dodám novú fotku",
                  "thesis": "Na webe zostane miesto v presnom tvare (%s, aspoň %s px); fotka sa len vloží." % (spec["ratio"], spec["min_px"])})
    target = "photo@%s@%s" % (slot, hashlib.sha256(json.dumps(cards, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16])
    q = {"id": "photo-" + slot, "kind": "photos", "part": "obsah", "target": target,
         "title": "Fotka: %s" % spec["where"], "body": "Čo na nej má byť: %s. Tvar %s." % (spec["what"], spec["ratio"]),
         "prompt": "Ktorú fotku sem dáme? Prvé sú tie, ktoré tvarom sedia najlepšie."}
    d.setdefault("questions", {})[slot] = {"target": target, "cards": [c["id"] for c in cards]}
    save(p, d)
    print(json.dumps({"question": q, "cards": cards}, ensure_ascii=False, indent=1))


def apply(p, qid):
    st = json.load(open(os.path.join(p, "docs", "design", "brand-state.json"), encoding="utf-8"))
    a = (st.get("answers") or {}).get(qid)
    if not a or a.get("kind") != "photos":
        die("no recorded photos answer %s" % qid)
    d = load(p)
    slot = next((s for s, q in (d.get("questions") or {}).items() if q["target"] == a.get("target")), None)
    if not slot:
        die("answer %s is for another question (target %s)" % (qid, a.get("target")))
    if qid in d["used_answers"]:
        die("answer %s is already used" % qid)
    if a.get("decision") != "choose" or a.get("choice") not in d["questions"][slot]["cards"]:
        die("answer %s did not choose a card of the question" % qid)
    d["used_answers"].append(qid)
    if a["choice"] == "keep":
        save(p, d)
        print("%s: the frame stays" % slot)
        return
    c = find(d, a["choice"])
    out = os.path.join(p, "docs", "content", "photos", slot + ".webp")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    r = None
    for w in ("1600", "1280", "1024"):   # the gate wants WebP within 200 kB (image_weight)
        r = subprocess.run(["bash", TOOL, "webp", c["file"], out, w, "0.78"], capture_output=True, text=True)
        if r.returncode == 0:
            break
    if r.returncode:
        die("the photo did not fit 200 kB as WebP: " + (r.stderr or r.stdout).strip()[-200:])
    small = os.path.join(os.path.dirname(out), slot + "-800.webp")   # the phone's size: the gate wants a srcset (page_weight)
    r = subprocess.run(["bash", TOOL, "webp", c["file"], small, "800", "0.78"], capture_output=True, text=True)
    if r.returncode:
        die("the 800 px photo did not fit 200 kB as WebP: " + (r.stderr or r.stdout).strip()[-200:])
    spec = slot_spec(p, slot)[0]
    rel = os.path.relpath(out, p)
    alt = c.get("describe") or c.get("alt")
    if not alt:
        die("%s has no description for screen readers: mark %s --describe '<what is on the photo>' first" % (c["id"], c["id"]))
    for k, v in (("src", rel), ("src_800", os.path.relpath(small, p)), ("src_from", c["url"]), ("alt", alt)):
        yq_set(os.path.join(p, "docs", "content", "photos.yaml"), '(.[] | select(.id == strenv(AID_SLOT)))[strenv(AID_KEY)] = strenv(AID_VAL)',
               AID_SLOT=slot, AID_KEY=k, AID_VAL=v)
    # the description is a claim on the web (alt): the client's own photo, chosen by the client, is its fact
    facts = os.path.join(p, "docs", "content", "facts.yaml")
    if os.path.isfile(facts):
        entry = {"value": alt, "source": c["url"], "confirmed_by": "klient", "answer": qid}
        yq_set(facts, '.[strenv(AID_KEY)] = env(AID_VAL)', AID_KEY="foto_" + slot, AID_VAL=json.dumps(entry, ensure_ascii=False))
    save(p, d)
    print("%s: %s -> %s" % (slot, c["id"], rel))


def main(a):
    opt = lambda k: a[a.index(k) + 1] if k in a and a.index(k) + 1 < len(a) else None
    if len(a) == 2 and a[0] == "candidates":
        return candidates(os.path.abspath(a[1]))
    if len(a) >= 3 and a[0] == "mark":
        return mark(os.path.abspath(a[1]), a[2], opt("--people"), opt("--note"), "--skip" in a, opt("--describe"))
    if len(a) == 3 and a[0] == "question":
        return question(os.path.abspath(a[1]), a[2])
    if len(a) >= 2 and a[0] == "apply" and opt("--answer"):
        return apply(os.path.abspath(a[1]), opt("--answer"))
    die("usage: candidates <p> | mark <p> <c> --people yes|no [--note t] | question <p> <slot> | apply <p> --answer <qid>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
