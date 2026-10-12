#!/usr/bin/env python3
"""aid-ui-critic.py - the critic's frozen role and rubric, its score and the verdict (P113a, 12. 10. 2026).

  freeze <project> --type <type> [--force]
      Builds the critic's role from skills/ui-design/critic/<type>.yaml (persona, criteria with weights and
      anchors) and the project's own context (docs/content/product-context.md, docs/product-vision.md,
      docs/seo/brief.md), writes <project>/.aid-ui/critic/frozen.json {type, rubric, role, sha256, at}.
      A frozen role is never rewritten without --force: the rubric must not move during a quality loop.
  prompt <project>
      The prompt the critic gets: the frozen role only - no acceptance threshold, no earlier scores, no fixes.
  score <project> <retro.json>
      Validates the critic's answer (references/critic-retro.schema.json; every frozen criterion answered
      once, anchors consistent with scores) and prints {quality_score, criteria, min_criterion, accepted,
      findings_by_owner, readiness}. quality_score = weighted mean over the assessable criteria (weights
      re-normalised), one decimal. Exit 0 valid, 1 invalid answer, 2 usage.
  verdict <project> <retro.json>...
      Several blind ratings of one web (the closing audit): median quality_score and median per criterion,
      accepted when the median score >= ACCEPT, no single rating below ACCEPT_ANY and no criterion median
      below FLOOR. Exit 0 accepted, 3 not accepted, 1 invalid answer.

The threshold lives here and in nothing the critic reads (PM 12. 10. 2026: goal 10/10, smallest acceptable
8/10 'for now').
"""
import hashlib, json, os, re, statistics, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")
ACCEPT, ACCEPT_ANY, FLOOR = 8.0, 7.5, 7.0   # ponytail: one global threshold; per-type thresholds when a second type needs another


def die(msg, code=1):
    print("ERROR: aid-ui-critic.py: " + msg, file=sys.stderr)
    sys.exit(code)


def load_yaml(p):
    import yaml
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f)


def read(p, limit=12000):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()[:limit]
    except OSError:
        return ""


def frozen_path(proj):
    return os.path.join(proj, ".aid-ui", "critic", "frozen.json")


def freeze(proj, typ, force):
    out = frozen_path(proj)
    if os.path.exists(out) and not force:
        die(f"{out} exists: the rubric does not move during a loop (--force to rebuild it)")
    rp = os.path.join(SKILL, "critic", f"{typ}.yaml")
    if not os.path.isfile(rp):
        die(f"no rubric for type {typ} ({rp})", 2)
    rub = json.loads(json.dumps(load_yaml(rp)))   # the JSON form (anchor keys as strings) is what is stored and re-hashed
    ctx_parts = [("Kontext produktu", "docs/content/product-context.md"), ("Vize", "docs/product-vision.md"),
                 ("Zadání pro vyhledávání", "docs/seo/brief.md")]
    ctx = "\n\n".join(f"## {t}\n\n{read(os.path.join(proj, p))}" for t, p in ctx_parts if read(os.path.join(proj, p)))
    if not ctx:
        die("no project context (docs/content/product-context.md, docs/product-vision.md): the critic must know the business")
    lang = "sk"
    try:
        st = json.load(open(os.path.join(proj, "docs/design/brand-state.json"), encoding="utf-8"))
        lang = ((st.get("variant") or {}).get("lang")) or st.get("lang") or lang
    except (OSError, ValueError):
        pass
    m = re.search(r'<html[^>]*\blang="([a-z]{2})', read(os.path.join(proj, "site", "index.html"), 4000))
    lang = m.group(1) if m else lang
    crit = "\n\n".join(f"### {c['id']} - {c['name']}\n" + "\n".join(f"- {k}: {v}" for k, v in sorted(c["anchors"].items(), key=lambda x: int(x[0])))
                       for c in rub["criteria"])
    schema = read(os.path.join(SKILL, "references", "critic-retro.schema.json"))
    role = read(os.path.join(SKILL, "critic", "role-template.md")).format(
        persona_who=rub["persona"]["who"], persona_wants=rub["persona"]["wants"],
        persona_rules="\n".join("- " + r for r in rub["persona"]["rules"]),
        criteria=crit, context=ctx, lang=lang, schema=schema)
    rec = {"type": typ, "rubric": rub, "role": role, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    rec["sha256"] = hashlib.sha256(json.dumps({"rubric": rub, "role": role}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(rec, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"FROZEN {typ} {rec['sha256'][:12]} -> {out}")


def frozen(proj):
    p = frozen_path(proj)
    if not os.path.isfile(p):
        die(f"no frozen critic in {p} (freeze first)")
    rec = json.load(open(p, encoding="utf-8"))
    sha = hashlib.sha256(json.dumps({"rubric": rec["rubric"], "role": rec["role"]}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    if sha != rec.get("sha256"):
        die("the frozen critic was edited after freezing (sha mismatch)")
    return rec


def check(rec, ans):
    from jsonschema.validators import Draft202012Validator
    schema = json.load(open(os.path.join(SKILL, "references", "critic-retro.schema.json"), encoding="utf-8"))
    errs = sorted(Draft202012Validator(schema).iter_errors(ans), key=lambda e: list(e.path))
    if errs:
        e = errs[0]
        return f"schema at {'/'.join(map(str, e.path)) or '(root)'}: {e.message}"
    want = [c["id"] for c in rec["rubric"]["criteria"]]
    got = [c["id"] for c in ans["criteria"]]
    if sorted(got) != sorted(want):
        return f"criteria answered {sorted(got)}, the rubric has {sorted(want)}"
    for c in ans["criteria"]:
        if c["score"] is None:
            if not (c.get("not_assessable") or "").strip():
                return f"{c['id']}: no score and no reason (not_assessable)"
            continue
        if c["anchor"] is None or not (c["anchor"] <= c["score"] <= c["anchor"] + 1 or c["score"] < 4):
            return f"{c['id']}: score {c['score']} does not sit on its anchor {c['anchor']} (anchor or one above it)"
    for f in ans["findings"]:
        if f["criterion"] not in want:
            return f"finding {f['id']}: unknown criterion {f['criterion']}"
    return None


def score(rec, ans):
    w = {c["id"]: c["weight"] for c in rec["rubric"]["criteria"]}
    sc = {c["id"]: c["score"] for c in ans["criteria"] if c["score"] is not None}
    tot = sum(w[k] for k in sc)
    q = round(sum(sc[k] * w[k] for k in sc) / tot, 1) if tot else 0.0
    mn = min(sc.values()) if sc else 0
    owners = {"agent": 0, "client": 0}
    for f in ans["findings"]:
        owners[f["owner"]] += 1
    return {"quality_score": q, "criteria": sc, "min_criterion": mn,
            "accepted": q >= ACCEPT and mn >= FLOOR, "findings_by_owner": owners,
            "readiness": [r["item"] for r in ans["readiness"]]}


def load_answer(p):
    try:
        t = open(p, encoding="utf-8").read().strip()
        m = re.match(r"^```(?:json)?\s*(.*?)\s*```$", t, re.S)
        return json.loads(m.group(1) if m else t)
    except (OSError, ValueError) as e:
        die(f"{p}: not readable JSON ({e})")


def main(a):
    if not a:
        die("usage: freeze|prompt|score|verdict (see the header)", 2)
    cmd = a[0]
    if cmd == "freeze" and len(a) >= 4 and a[2] == "--type":
        return freeze(os.path.abspath(a[1]), a[3], "--force" in a)
    if cmd == "prompt" and len(a) == 2:
        print(frozen(os.path.abspath(a[1]))["role"])
        return
    if cmd == "score" and len(a) == 3:
        rec = frozen(os.path.abspath(a[1]))
        ans = load_answer(a[2])
        bad = check(rec, ans)
        if bad:
            die(bad)
        print(json.dumps(score(rec, ans), ensure_ascii=False))
        return
    if cmd == "verdict" and len(a) >= 3:
        rec = frozen(os.path.abspath(a[1]))
        runs = []
        for p in a[2:]:
            ans = load_answer(p)
            bad = check(rec, ans)
            if bad:
                die(f"{p}: {bad}")
            runs.append(score(rec, ans))
        med = statistics.median(r["quality_score"] for r in runs)
        ids = sorted({k for r in runs for k in r["criteria"]})
        crit = {k: statistics.median([r["criteria"][k] for r in runs if k in r["criteria"]]) for k in ids}
        low = min(r["quality_score"] for r in runs)
        ok = med >= ACCEPT and low >= ACCEPT_ANY and (min(crit.values()) if crit else 0) >= FLOOR
        print(json.dumps({"ratings": len(runs), "median_quality_score": med, "lowest_rating": low,
                          "criteria_median": crit, "accepted": ok}, ensure_ascii=False))
        sys.exit(0 if ok else 3)
    die("usage: freeze <project> --type <type> [--force] | prompt <project> | score <project> <retro.json> | verdict <project> <retro.json>...", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
