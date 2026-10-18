"""aid_ui_costs - the project's cost book <project>/.aid-ui/costs.jsonl (P113a, 12. 10. 2026).

One JSON line per model call: at, provider, model, billing (api = paid per call | subscription = list-price
equivalent of a call on a subscription), purpose, units, unit prices with the price list and its date, usd.
Paid API is only ever the image model (PM 12. 10. 2026); its total over the whole project is capped by
image_budget() (AID_UI_IMAGE_BUDGET_USD, default 2.00) and checked before every image is sent.
"""
import fcntl, functools, json, os, subprocess, sys, time

LIB = os.path.dirname(os.path.abspath(__file__))


@functools.lru_cache(maxsize=None)
def price_table(project=""):
    """(path, parsed YAML) of the ONE price table AID's revisions read (P115): aid_review_prices_file of
    lib/aid-review-summary.sh - AID_REVIEW_PRICES, else <project>/.aid-o/config/prices.yaml, else defaults/prices.yaml.
    (None, {}) when there is none."""
    import yaml
    r = subprocess.run(["bash", "-c", 'source "$1/aid-review-summary.sh" && aid_review_prices_file "$2"', "_", LIB, project or ""],
                       capture_output=True, text=True, stdin=subprocess.DEVNULL)
    f = r.stdout.strip()
    if r.returncode or not f:
        return None, {}
    with open(f, encoding="utf-8") as fh:
        return f, yaml.safe_load(fh) or {}


def token_prices(provider, model, project=""):
    """USD per 1M tokens {input, cached, output, list} of a call, from the shared table: Codex by its model name, Claude
    by the table's own names (opus, sonnet - what the revisions price the Agent tool's calls by; a model id names its
    family, claude-opus-5-5 is opus). None, with a warning, when it is not listed - never another model's price."""
    f, t = price_table(project)
    m = (model or "").lower()
    key = model if provider == "codex" else ("sonnet" if "sonnet" in m else "opus" if "opus" in m or m in ("", "default") else m)
    row = ((t.get("models") or {}).get(key) or {}) if t else {}
    if not all(isinstance(row.get(k), (int, float)) for k in ("input", "output", "cache_read")):
        print("WARN: aid_ui_costs: no price for %s %s in %s; the cost row says usd null" % (provider, key, f or "the price table"), file=sys.stderr)
        return None
    return {"input": row["input"], "cached": row["cache_read"], "output": row["output"],
            "list": "%s: %s, as of %s" % (os.path.basename(f), key, row.get("as_of", "?"))}


def image_prices(project=""):
    """{model: {quality: USD per image}}, ref_usd and the list line of the images: section. The image budget is a cap on
    real money, so a price is a finite number above zero and a project's table (or AID_REVIEW_PRICES) can only RAISE
    the plugin's own price, never lower it (a zero price would let every image past the cap)."""
    import math, yaml
    f, t = price_table(project)
    with open(os.path.join(LIB, "..", "..", "defaults", "prices.yaml"), encoding="utf-8") as fh:
        base = (yaml.safe_load(fh) or {}).get("images") or {}
    im = (t or {}).get("images") or {}
    ok = lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and x > 0
    out = {}
    for src in (base, im):
        for m, qs in (src.get("models") or {}).items():
            for q, v in (qs or {}).items() if isinstance(qs, dict) else ():
                if ok(v):
                    out.setdefault(m, {})[q] = max(v, out.get(m, {}).get(q, 0))
    ref = max([x for x in (base.get("ref_usd"), im.get("ref_usd")) if ok(x)] or [0])
    return out, ref, "%s: images, as of %s" % (os.path.basename(f or "prices.yaml"), im.get("as_of") or base.get("as_of", "?"))


def image_budget():
    return float(os.environ.get("AID_UI_IMAGE_BUDGET_USD", "2.0"))


def path(project):
    return os.path.join(project, ".aid-ui", "costs.jsonl")


def rows(project):
    try:
        with open(path(project), encoding="utf-8") as f:
            return [json.loads(x) for x in f if x.strip()]
    except OSError:
        return []


def add(project, row):
    row = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **row}
    os.makedirs(os.path.dirname(path(project)), exist_ok=True)
    with open(path(project), "a", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
    return row


def api_spent(project):
    return round(sum(r.get("usd") or 0 for r in rows(project) if r.get("billing") == "api"), 4)


def image_room(project, unit):
    """None when one more image of `unit` USD fits the project's budget, else the reason it does not."""
    spent, cap = api_spent(project), image_budget()
    if spent + unit > cap + 1e-9:
        return "image budget %.2f USD for the project reached (spent %.2f, next image %.3f)" % (cap, spent, unit)
    return None


def reserve(project, row):
    """Book one paid call of row['usd'] before it is sent, atomically: the read, the budget check and the append
    happen under one exclusive lock, so two generators never both pass on the same spend. None = booked, else why not."""
    os.makedirs(os.path.dirname(path(project)), exist_ok=True)
    with open(path(project), "a+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        spent = round(sum((json.loads(x).get("usd") or 0) for x in f if x.strip() and json.loads(x).get("billing") == "api"), 4)
        cap = image_budget()
        if spent + row["usd"] > cap + 1e-9:
            return "image budget %.2f USD for the project reached (spent %.2f, next image %.3f)" % (cap, spent, row["usd"])
        f.write(json.dumps({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "billing": "api", **row}, ensure_ascii=False) + "\n")
    return None


def tokens(project, provider, model, usage, purpose, reported_usd=None):
    """A subscription call at its list-price equivalent; usage {input, cached, output} in tokens (input incl. cached)."""
    p = token_prices(provider, model, project)
    inp, cached, out = (int(usage.get(k) or 0) for k in ("input", "cached", "output"))
    est = round((max(inp - cached, 0) * p["input"] + cached * p["cached"] + out * p["output"]) / 1e6, 4) if p else None
    return add(project, {"provider": provider, "model": model or "default", "billing": "subscription", "purpose": purpose,
                         "units": {"input": inp, "cached": cached, "output": out},
                         "unit_usd_per_1m": {k: p[k] for k in ("input", "cached", "output")} if p else None,
                         "price_list": p["list"] if p else "not in the price table",
                         "usd": est, **({"reported_usd": reported_usd} if reported_usd is not None else {})})


def summary(project):
    rs = rows(project)
    by = {}
    for r in rs:
        k = "%s %s %s" % (r.get("billing"), r.get("provider"), r.get("purpose"))
        by[k] = round(by.get(k, 0) + (r.get("usd") or 0), 4)
    spent = api_spent(project)
    return {"calls": len(rs), "by": by, "api_usd": spent, "image_budget_usd": image_budget(),
            "image_budget_left_usd": round(image_budget() - spent, 4),
            "subscription_usd_equiv": round(sum(r.get("usd") or 0 for r in rs if r.get("billing") == "subscription"), 4)}


def ts(s):
    """An ISO UTC time ('...Z', with or without fractions) as epoch seconds; '' -> 0."""
    import calendar
    if not s:
        return 0.0
    base, _, frac = s.rstrip("Z").partition(".")
    return calendar.timegm(time.strptime(base, "%Y-%m-%dT%H:%M:%S")) + (float("0." + frac) if frac else 0.0)


def iso_now():
    t = time.time()
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


def agent_transcripts(session=None):
    """The controlling Claude Code session's transcript and its subagents' (CLAUDE_CODE_SESSION_ID), or []."""
    import glob
    sid = session or os.environ.get("CLAUDE_CODE_SESSION_ID")
    if not sid:
        return []
    base = os.path.expanduser(os.environ.get("AID_UI_CLAUDE_PROJECTS", "~/.claude/projects"))
    return glob.glob(os.path.join(base, "*", sid + ".jsonl")) + glob.glob(os.path.join(base, "*", sid, "subagents", "*.jsonl"))


def book_agent(project, purpose, session=None):
    """The agent's own work since the last agent row of this project (or the first row of the book) up to now,
    one row per model, at list-price equivalent. None when no transcript is known (then status says 'neměřeno')."""
    files = agent_transcripts(session)
    if not files:
        return None
    rs = rows(project)
    since = max([r.get("until") for r in rs if r.get("provider") == "agent" and r.get("until")] or [rs[0]["at"] if rs else ""], key=ts)
    until = iso_now()
    t0, t1 = ts(since), ts(until)
    seen, use = set(), {}
    for fp in files:
        with open(fp, encoding="utf-8", errors="replace") as f:
            for ln in f:
                try:
                    e = json.loads(ln)
                except ValueError:
                    continue
                m = e.get("message") if isinstance(e, dict) and e.get("type") == "assistant" else None
                if not m or not m.get("usage") or m.get("id") in seen or not (t0 <= ts(e.get("timestamp") or "") < t1):
                    continue
                seen.add(m.get("id"))
                u, mod = m["usage"], m.get("model") or "opus"
                a = use.setdefault(mod, {"input": 0, "cached": 0, "output": 0})
                a["cached"] += u.get("cache_read_input_tokens") or 0
                a["input"] += (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                a["output"] += u.get("output_tokens") or 0
    out = []
    for mod, u in use.items():
        p = token_prices("claude", mod, project)
        est = round(((u["input"] - u["cached"]) * p["input"] + u["cached"] * p["cached"] + u["output"] * p["output"]) / 1e6, 4) if p else None
        out.append(add(project, {"provider": "agent", "model": mod, "billing": "subscription", "purpose": purpose, "since": since,
                                 "until": until, "units": u, "unit_usd_per_1m": {k: p[k] for k in ("input", "cached", "output")} if p else None,
                                 "price_list": (p["list"] + " (estimate; cache writes at input price)") if p else "not in the price table", "usd": est}))
    if not out:   # an empty interval still moves the mark
        out.append(add(project, {"provider": "agent", "model": None, "billing": "subscription", "purpose": purpose, "since": since,
                                 "until": until, "units": {}, "usd": 0.0}))
    return out
