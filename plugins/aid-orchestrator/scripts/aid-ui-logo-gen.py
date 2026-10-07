#!/usr/bin/env python3
"""aid-ui-logo-gen.py - logo concepts drawn by an image model (step 1i, PM 7. 10. 2026: the marks the
language model drew as SVG coordinates were "a joke"; the process stays, the hand changes).

  aid-ui-logo-gen.py <project> --spec .aid-ui/logo/gen.json [--dry-run] [--max-cost USD] [--force]

gen.json:
  {"model": "gpt-image-2.5-sunburst",           (default; gpt-image-2, gpt-image-1 also wired)
   "references": [".aid-ui/refs/inspirace/a.jpg", ...],   optional, up to 16: real logos the agent
                                                found for the level of craft (never copied); sent as
                                                image inputs through /v1/images/edits
   "quality": "medium", "n": 6,                 per slot; n <= 10, n x slots <= 60
   "mode": "full",                              full (default): the complete logo in colour - symbol +
                                                name + optional tagline, white background (PM 8. 10.
                                                2026: black marks alone were app icons); mark: a single
                                                black symbol on a transparent background
   "name": "Coufal Clinic", "tagline": "zubná ambulancia · Trenčín",   full mode: what the logo says
   "palette": "deep navy and light blue",       full mode, optional: the colour direction in words
   "slots": {"WC": "one-sentence concept of the direction", ...}}   every key a slot of
                                                .aid-ui/logo/route.json (id [A-Z]{1,3})
The prompt = the mode's fixed constraints + the slot's mark type + the concept sentence (+ name,
tagline and palette in full mode). Only that text leaves the machine: write the concept from the
brief in your own words (the brand name, the category and the town at most, never facts, prices,
people or anything from the sources).
Output .aid-ui/logo/gen/<slot>-<n>.png (1024x1024 PNG, transparent background, checked by
signature and size) and .aid-ui/logo/gen/gen.json (version, run id, model, price list, prompts,
requested / received per slot and status succeeded | partial | failed, UTC times, estimated cost);
--dry-run writes .aid-ui/logo/gen/plan.json (the prompts, nothing sent) and leaves gen.json alone.
The key comes only from the environment variable OPENAI_API_KEY (never from a project file, never
written anywhere; it is redacted from every message). No retry: a timeout is recorded as
"unknown (may have been billed)" and the slot goes on. --max-cost (default 3.00 USD, from PRICE)
stops before the request that would exceed it. Existing files are never overwritten without
--force. A raster from here is a concept: the card the PM sees carries the vector made from it
(aid-ui-tool.sh vectorize), never the PNG; delete gen/*.png after the identity answer is recorded,
gen.json stays as the record.
Exit: 0 every slot succeeded, 1 no key / no route / a slot partial or failed / cost cap hit, 2 usage.
"""
import base64, json, os, re, struct, sys, time, urllib.error, urllib.request

CONSTRAINTS = ("Flat vector-style logo mark: a single solid pure black (#000000) shape, isolated on a transparent "
               "background, nothing else in the image. No text, no letters unless the concept names one, no gradients, "
               "no shadows, no 3D, no texture, no outline strokes, no frame, no background shape. Centred, square "
               "composition, generous margin, simple geometry that still reads at 16 px, professional brand identity "
               "design, one idea only.")
CONSTRAINTS_FULL = ("Logo design presentation by a top brand identity studio, award-winning contemporary quality, for the "
                    "company \"%s\": one original, memorable brand mark paired with a refined, custom-feeling wordmark "
                    "\"%s\"%s. Flat vector look, impeccable typography and letter spacing, generous negative space, "
                    "balanced horizontal lockup centred on pure white, at most two brand colours%s plus a neutral. "
                    "No mockups, no frame, no photo, no gradients, no shadows, no extra icon versions, no other text; "
                    "every word spelled exactly as given. The mark must still read at small size. One clear idea, "
                    "unique, not a stock clipart. If reference images are attached, use them only as the measure of craft "
                    "and restraint - never copy their shapes or names.")
PRICE_LIST = "OpenAI image pricing, read 2026-10-07, USD per 1024x1024 image"
PRICE = {"gpt-image-1": {"low": 0.011, "medium": 0.042, "high": 0.167},
         # token-billed models: estimate per 1024x1024 output (30 USD per 1M image-output tokens; measured
         # 2026-10-08: sunburst high 1756 tokens, gpt-image-2 high 7024 tokens) + ~0.006 USD per reference image
         "gpt-image-2": {"low": 0.06, "medium": 0.12, "high": 0.21},
         "gpt-image-2.5-sunburst": {"low": 0.02, "medium": 0.04, "high": 0.06},
         "gpt-image-2.5-flare": {"low": 0.02, "medium": 0.03, "high": 0.05}}
REF_USD = 0.006
MAX_PER_SLOT, MAX_RUN, MAX_BODY = 10, 60, 8 * 1024 * 1024
SLOT_ID = re.compile(r"^[A-Z]{1,3}$")


def die(msg, code=1):
    print("ERROR: aid-ui-logo-gen.py: %s" % msg, file=sys.stderr)
    sys.exit(code)


def utc():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def generate(key, model, prompt, quality, mode="full", refs=()):
    """One PNG from the API; raises urllib errors, TimeoutError or ValueError (bad response).
    With reference images the call goes to /v1/images/edits as multipart (image[] = the references)."""
    body = {"model": model, "prompt": prompt, "n": 1, "size": "1024x1024", "quality": quality, "output_format": "png"}
    if mode == "mark":
        body["background"] = "transparent"
    if refs:
        import uuid
        b = uuid.uuid4().hex
        parts = []
        for k, v in body.items():
            parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (b, k, v)).encode("utf-8"))
        for path in refs:
            with open(path, "rb") as f:
                data = f.read()
            ext = os.path.splitext(path)[1].lower()
            mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}[ext.lstrip(".")]
            parts.append(("--%s\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                          % (b, os.path.basename(path), mime)).encode("utf-8") + data + b"\r\n")
        parts.append(("--%s--\r\n" % b).encode("utf-8"))
        req = urllib.request.Request("https://api.openai.com/v1/images/edits", data=b"".join(parts),
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "multipart/form-data; boundary=" + b}, method="POST")
    else:
        req = urllib.request.Request(
            "https://api.openai.com/v1/images/generations",
            data=json.dumps(body).encode("utf-8"),
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=180) as r:
        body = r.read(MAX_BODY + 1)
    if len(body) > MAX_BODY:
        raise ValueError("response over %d bytes" % MAX_BODY)
    d = json.loads(body.decode("utf-8"))
    png = base64.b64decode(d["data"][0]["b64_json"])
    if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (1024, 1024):
        raise ValueError("not a 1024x1024 PNG")
    return png


def main():
    args = sys.argv[1:]
    dry, force = "--dry-run" in args, "--force" in args
    max_cost = 3.0
    if "--max-cost" in args:
        i = args.index("--max-cost")
        try:
            max_cost = float(args[i + 1])
        except (IndexError, ValueError):
            die("--max-cost needs a number (USD)", 2)
        del args[i:i + 2]
    args = [a for a in args if a not in ("--dry-run", "--force")]
    if len(args) != 3 or args[1] != "--spec":
        die("usage: aid-ui-logo-gen.py <project> --spec <gen.json> [--dry-run] [--max-cost USD] [--force]", 2)
    project = os.path.realpath(args[0])
    spec_path = args[2] if os.path.isabs(args[2]) else os.path.join(project, args[2])
    try:
        with open(spec_path, encoding="utf-8") as f:
            spec = json.load(f)
        with open(os.path.join(project, ".aid-ui", "logo", "route.json"), encoding="utf-8") as f:
            route = json.load(f)
    except (OSError, ValueError) as e:
        die("spec or .aid-ui/logo/route.json unreadable: %s" % e)
    slots = {s["id"]: s for s in route.get("slots", []) if isinstance(s, dict) and SLOT_ID.match(str(s.get("id", "")))}
    model = spec.get("model", "gpt-image-2.5-sunburst")
    quality = spec.get("quality", "medium")
    mode = spec.get("mode") or ("mark" if route.get("situation") == "app" else "full")   # app: the symbol first
    if mode not in ("full", "mark"):
        die("mode must be full or mark", 2)
    if route.get("situation") == "assets":
        die("situation assets: the existing symbol is used, nothing is generated (route.json)", 2)
    if mode == "full" and not (isinstance(spec.get("name"), str) and spec["name"].strip()):
        die("full mode needs name (and optionally tagline, palette)", 2)
    n = spec.get("n", 6)
    if model not in PRICE or quality not in PRICE[model]:
        die("model/quality not wired: %s/%s (known: %s)" % (model, quality, json.dumps(PRICE)), 2)
    if not isinstance(spec.get("slots"), dict) or not spec["slots"] or \
            not all(isinstance(v, str) and v.strip() for v in spec["slots"].values()):
        die("spec.slots must map slot id -> one-sentence concept", 2)
    bad = [k for k in spec["slots"] if k not in slots]
    if bad:
        die("slots not in route.json: %s (route has %s)" % (", ".join(bad), ", ".join(slots) or "none"), 2)
    if not isinstance(n, int) or not 1 <= n <= MAX_PER_SLOT or n * len(spec["slots"]) > MAX_RUN:
        die("n must be an integer 1..%d and n x slots <= %d" % (MAX_PER_SLOT, MAX_RUN), 2)
    refs = spec.get("references") or []
    if not isinstance(refs, list) or len(refs) > 16 or not all(isinstance(r, str) for r in refs):
        die("references must be a list of at most 16 image paths", 2)
    refs = [r if os.path.isabs(r) else os.path.join(project, r) for r in refs]
    for r in refs:
        if not os.path.isfile(r) or os.path.splitext(r)[1].lower() not in (".png", ".jpg", ".jpeg", ".webp"):
            die("reference not a png/jpg/webp file: %s" % r)
    unit = PRICE[model][quality] + REF_USD * len(refs)
    out = os.path.join(project, ".aid-ui", "logo", "gen")
    os.makedirs(out, exist_ok=True)
    if os.path.islink(out) or not os.path.realpath(out).startswith(project + os.sep):
        die("gen directory must be a plain directory under the project")
    log = {"version": 1, "run_id": time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), "model": model, "quality": quality,
           "n": n, "mode": mode, "references": [os.path.relpath(r, project) for r in refs], "price_list": PRICE_LIST,
           "unit_usd": unit, "max_cost_usd": max_cost, "dry_run": dry,
           "started": utc(), "constraints": constraints_for(spec), "slots": {}, "requested": 0, "received": 0,
           "estimated_usd": 0.0, "status": "planned" if dry else "running"}
    spec["mode"] = mode
    if dry:
        for slot, concept in spec["slots"].items():
            log["slots"][slot] = {"concept": concept, "prompt": prompt_for(slots[slot], concept, spec), "requested": n}
        log["requested"] = n * len(spec["slots"])
        log["finished"] = utc()
        with open(os.path.join(out, "plan.json"), "w", encoding="utf-8") as f:
            json.dump(log, f, ensure_ascii=False, indent=1)
        print("plan.json: %d prompt(s) for %d slot(s), ~%.2f USD if run; nothing sent" % (len(spec["slots"]), len(spec["slots"]), log["requested"] * unit))
        return
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        die("OPENAI_API_KEY is not set in the environment (export it from services/.env for this call; never store it)")
    if not force:
        clash = [p for s in spec["slots"] for i in range(1, n + 1) for p in [os.path.join(out, "%s-%d.png" % (s, i))] if os.path.exists(p)]
        if clash:
            die("%d file(s) already exist in .aid-ui/logo/gen (first: %s); use --force to overwrite" % (len(clash), os.path.basename(clash[0])))
    capped = False
    for slot, concept in spec["slots"].items():
        prompt = prompt_for(slots[slot], concept, spec)
        rec = {"concept": concept, "prompt": prompt, "requested": n, "received": 0, "files": [], "errors": [], "status": "running"}
        for i in range(1, n + 1):
            if log["estimated_usd"] + unit > max_cost + 1e-9:
                rec["errors"].append("cost cap %.2f USD reached before variant %d" % (max_cost, i))
                capped = True
                break
            log["requested"] += 1
            log["estimated_usd"] = round(log["estimated_usd"] + unit, 3)   # counted when sent, billed or not
            try:
                png = generate(key, model, prompt, quality, mode, refs)
            except TimeoutError:
                rec["errors"].append("variant %d: timeout - unknown (may have been billed); not retried" % i)
                continue
            except urllib.error.HTTPError as e:
                try:
                    msg = "HTTP %d: %s" % (e.code, e.read(300).decode("utf-8", "replace"))
                except OSError:
                    msg = "HTTP %d" % e.code
                rec["errors"].append("variant %d: %s" % (i, msg.replace(key, "<key>")))
                if e.code in (401, 403, 429):
                    break
                continue
            except (urllib.error.URLError, ValueError, KeyError, OSError) as e:
                msg = str(getattr(e, "reason", e)).replace(key, "<key>")
                rec["errors"].append("variant %d: %s" % (i, "offline: " + msg if isinstance(e, urllib.error.URLError) else msg))
                if isinstance(e, urllib.error.URLError) and "timed out" in msg:
                    rec["errors"][-1] += " - unknown (may have been billed); not retried"
                continue
            path = os.path.join(out, "%s-%d.png" % (slot, i))
            tmp = path + ".part"
            with open(tmp, "wb") as f:
                f.write(png)
            os.replace(tmp, path)
            rec["files"].append(os.path.relpath(path, project))
            rec["received"] += 1
            log["received"] += 1
        rec["status"] = "succeeded" if rec["received"] == n else ("partial" if rec["received"] else "failed")
        log["slots"][slot] = rec
        print("%s: %d/%d received%s" % (slot, rec["received"], n, "; " + rec["errors"][-1] if rec["errors"] else ""))
        if capped:
            for other in spec["slots"]:
                if other not in log["slots"]:
                    log["slots"][other] = {"concept": spec["slots"][other], "requested": n, "received": 0, "files": [], "errors": ["cost cap reached"], "status": "failed"}
            break
    log["finished"] = utc()
    log["status"] = "succeeded" if all(s["status"] == "succeeded" for s in log["slots"].values()) else \
        ("failed" if log["received"] == 0 else "partial")
    tmp = os.path.join(out, "gen.json.part")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(log, f, ensure_ascii=False, indent=1)
    os.replace(tmp, os.path.join(out, "gen.json"))
    print("gen.json: %s, %d/%d received, ~%.2f USD" % (log["status"], log["received"], log["requested"], log["estimated_usd"]))
    if log["status"] != "succeeded":
        sys.exit(1)


def constraints_for(spec):
    if spec.get("mode", "full") == "mark":
        return CONSTRAINTS
    tag = spec.get("tagline")
    pal = spec.get("palette")
    name = spec.get("name", "").strip()
    return CONSTRAINTS_FULL % (name, name,
                               (' and a small tagline "%s" under it' % tag.strip()) if isinstance(tag, str) and tag.strip() else "",
                               (" (%s)" % pal.strip()) if isinstance(pal, str) and pal.strip() else "")


def prompt_for(slot, concept, spec=None):
    spec = dict(spec or {})
    spec.setdefault("mode", "full" if spec.get("name") else "mark")
    return "%s Mark type: %s. Concept: %s" % (constraints_for(spec), slot["kind"], concept.strip())


if __name__ == "__main__":
    main()
