"""aid_ui_costs - the project's cost book <project>/.aid-ui/costs.jsonl (P113a, 12. 10. 2026).

One JSON line per model call: at, provider, model, billing (api = paid per call | subscription = list-price
equivalent of a call on a subscription), purpose, units, unit prices with the price list and its date, usd.
Paid API is only ever the image model (PM 12. 10. 2026); its total over the whole project is capped by
image_budget() (AID_UI_IMAGE_BUDGET_USD, default 2.00) and checked before every image is sent.
"""
import fcntl, json, os, time

# USD per 1M tokens. ponytail: list prices typed in by hand; update the table and its date when a price moves
TOKEN_PRICES = {
    "codex": {"input": 1.25, "cached": 0.125, "output": 10.0, "list": "OpenAI gpt-5 list price, read 2026-10-08 (Codex default model, estimate)"},
    "claude:sonnet": {"input": 3.0, "cached": 0.3, "output": 15.0, "list": "Anthropic Sonnet list price, read 2026-10-12"},
    "claude:opus": {"input": 5.0, "cached": 0.5, "output": 25.0, "list": "Anthropic Opus list price, read 2026-10-12"},
}


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
    key = "codex" if provider == "codex" else "claude:" + ("opus" if "opus" in (model or "") else "sonnet")
    p = TOKEN_PRICES[key]
    inp, cached, out = (int(usage.get(k) or 0) for k in ("input", "cached", "output"))
    est = round((max(inp - cached, 0) * p["input"] + cached * p["cached"] + out * p["output"]) / 1e6, 4)
    return add(project, {"provider": provider, "model": model or "default", "billing": "subscription", "purpose": purpose,
                         "units": {"input": inp, "cached": cached, "output": out},
                         "unit_usd_per_1m": {k: p[k] for k in ("input", "cached", "output")}, "price_list": p["list"],
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
