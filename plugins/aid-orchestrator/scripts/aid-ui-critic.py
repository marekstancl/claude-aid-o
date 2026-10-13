#!/usr/bin/env python3
"""aid-ui-critic.py - the two critics' frozen roles and rubrics, their scores and the verdict (P113a, 12./13. 10. 2026).

Two roles rate every web (PM 13. 10. 2026): the OWNER (a demanding business owner: impression, uniqueness against
the competition, photos, selling texts, trust, price and booking as seen) and the TECHNICIAN (search, structured
data, speed, accessibility, mobile, form delivery, launch readiness - what the owner cannot judge). Each rubric was
written from its role brief by its own author and reviewed by the other (critic/AUTHORS.yaml, critic/role-briefs/).

  freeze <project> --type <type> [--force]
      Builds both roles from skills/ui-design/critic/<type>.owner.yaml and <type>.tech.yaml (persona, criteria with
      weights summing to 100 and anchors) and the project's context (docs/content/product-context.md,
      docs/product-vision.md, docs/seo/brief.md); the type's common part (<type>.yaml: task_test, launch_inputs,
      components) is stored as `rubric` with the owner's persona (the client agent plays the owner). Writes
      <project>/.aid-ui/critic/frozen.json {type, rubric, roles: {owner|tech: {rubric, role, sha256}}, schema, sha256, at}.
      Never rewritten without --force, and never while a loop has rounds; a context line that mentions scores or
      acceptance is dropped (the critics are blind to both). A frozen critic without roles is refused.
  prompt <project> --role owner|tech
      The role's prompt: the frozen role only - no acceptance threshold, no earlier scores.
  score <project> <retro.json> --role owner|tech
      Validates the role's answer (references/critic-retro.schema.json; every criterion of the role answered once,
      anchors consistent with scores) and prints {quality_score, criteria, min_criterion, accepted,
      findings_by_owner, readiness}. quality_score = weighted mean over the assessable criteria (weights
      re-normalised), one decimal; accepted = quality_score >= ACCEPT and no criterion under FLOOR.
  verdict <project> --role owner|tech <retro.json> x3
      Three blind ratings of one web by one role (the closing audit): accepted when the median >= ACCEPT, no rating
      below ACCEPT_ANY and no criterion median below FLOOR. Readiness items never lower the verdict; they come back
      as publish_blocked_by. Exit 0 accepted, 3 not accepted, 1 invalid answer.

The thresholds live here and in nothing the critics read (PM 13. 10. 2026: owner and technician each 8.5; at most
three repair rounds - aid-ui-quality.py).
"""
import hashlib, json, os, re, statistics, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")
ACCEPT, ACCEPT_ANY, FLOOR = 8.5, 8.0, 7.0   # PM 13. 10. 2026: owner and tech each 8.5; ponytail: one threshold for every type
RATINGS = 3   # blind closing ratings of one web
# what the critic must not read: scores, thresholds, acceptance (the context docs are written by the agent)
LEAK = re.compile(r"\b\d{1,2}(?:[.,]\d)?\s*/\s*10\b|quality_score|akcept|accept|threshold|\bprah|\bpráh|známk", re.I)


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


ROLES = ("owner", "tech")   # the owner (impression, uniqueness, photos, texts) and the technician (search, speed, access, form)


def freeze(proj, typ, force):
    out = frozen_path(proj)
    if os.path.exists(out) and not force:
        die(f"{out} exists: the rubric does not move during a loop (--force to rebuild it)")
    rounds = os.path.join(proj, ".aid-ui", "critic", "rounds")
    if force and os.path.isdir(rounds) and os.listdir(rounds):
        die(f"a quality loop has rounds in {rounds}: the rubric cannot change under it (archive the rounds to start a new loop)")
    paths = {r: os.path.join(SKILL, "critic", f"{typ}.{r}.yaml") for r in ("",) + ROLES}
    paths[""] = os.path.join(SKILL, "critic", f"{typ}.yaml")
    miss = [p for p in paths.values() if not os.path.isfile(p)]
    if miss:
        die(f"no rubric for type {typ} ({', '.join(miss)})", 2)
    authors = json.loads(json.dumps(load_yaml(os.path.join(SKILL, "critic", "AUTHORS.yaml")) or {}, default=str))   # dates as text
    for r in ROLES:   # a rubric changed after its authors' record is not the reviewed one
        a = authors.get(os.path.basename(paths[r])) or {}
        if not (a.get("author") and a.get("reviewer")) or a.get("sha256") != hashlib.sha256(open(paths[r], "rb").read()).hexdigest():
            die(f"{os.path.basename(paths[r])}: not the rubric critic/AUTHORS.yaml records (author, reviewer, sha256); "
                "a changed rubric needs its author and a review first")
    common = json.loads(json.dumps(load_yaml(paths[""])))   # task_test, launch_inputs, components: the type's, both roles'
    ctx_parts = [("Kontext produktu", "docs/content/product-context.md"), ("Vize", "docs/product-vision.md"),
                 ("Zadání pro vyhledávání", "docs/seo/brief.md")]
    ctx = "\n\n".join(f"## {t}\n\n{read(os.path.join(proj, p))}" for t, p in ctx_parts if read(os.path.join(proj, p)))
    if not ctx:
        die("no project context (docs/content/product-context.md, docs/product-vision.md): the critic must know the business")
    leak = [ln.strip() for ln in ctx.splitlines() if LEAK.search(ln)]
    if leak:   # dropped, not refused: a loop must not stop on an old audit score in the vision
        ctx = "\n".join(ln for ln in ctx.splitlines() if not LEAK.search(ln))
        print(f"DROPPED {len(leak)} context line(s) about scores or acceptance: " + " | ".join(x[:80] for x in leak[:3]), file=sys.stderr)
    lang = "sk"
    try:
        st = json.load(open(os.path.join(proj, "docs/design/brand-state.json"), encoding="utf-8"))
        lang = ((st.get("variant") or {}).get("lang")) or st.get("lang") or lang
    except (OSError, ValueError):
        pass
    m = re.search(r'<html[^>]*\blang="([a-z]{2})', read(os.path.join(proj, "site", "index.html"), 4000))
    lang = m.group(1) if m else lang
    schema = read(os.path.join(SKILL, "references", "critic-retro.schema.json"), 10 ** 6)
    tpl = read(os.path.join(SKILL, "critic", "role-template.md"))
    roles = {}
    for r in ROLES:
        rub = json.loads(json.dumps(load_yaml(paths[r])))
        if sum(c["weight"] for c in rub["criteria"]) != 100 or any(not re.fullmatch(r"[a-z0-9_]+", c["id"]) for c in rub["criteria"]):
            die(f"{paths[r]}: weights must sum to 100 and ids be ascii snake_case")
        crit = "\n\n".join(f"### {c['id']} - {c['name']}\n" + "\n".join(f"- {k}: {v}" for k, v in sorted(c["anchors"].items(), key=lambda x: int(x[0])))
                           for c in rub["criteria"])
        role = tpl.format(persona_who=rub["persona"]["who"], persona_wants=rub["persona"]["wants"],
                          persona_rules="\n".join("- " + x for x in rub["persona"]["rules"]), criteria=crit, context=ctx, lang=lang, schema=schema)
        roles[r] = {"rubric": rub, "role": role, "authors": authors[os.path.basename(paths[r])]}
        roles[r]["sha256"] = digest({"rubric": rub, "role": role, "schema": json.loads(schema)})
    rec = {"type": typ, "rubric": dict(common, persona=roles["owner"]["rubric"]["persona"]),   # the client agent plays the owner
           "roles": roles, "schema": json.loads(schema), "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    rec["sha256"] = digest(rec)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(rec, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"FROZEN {typ} {rec['sha256'][:12]} -> {out} (owner {roles['owner']['sha256'][:12]}, tech {roles['tech']['sha256'][:12]})")


def digest(rec):
    return hashlib.sha256(json.dumps({k: rec[k] for k in ("rubric", "role", "roles", "schema") if k in rec}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def frozen(proj):
    p = frozen_path(proj)
    if not os.path.isfile(p):
        die(f"no frozen critic in {p} (freeze first)")
    rec = json.load(open(p, encoding="utf-8"))
    if "schema" not in rec or "roles" not in rec or digest(rec) != rec.get("sha256"):
        die("the frozen critic was edited after freezing, or predates the two roles (sha mismatch or no roles; archive the rounds and freeze again)")
    return rec


def of_role(rec, role):
    if role not in ROLES:
        die("--role must be one of " + ", ".join(ROLES), 2)
    return {"rubric": rec["roles"][role]["rubric"], "role": rec["roles"][role]["role"], "schema": rec["schema"]}


def check(rec, ans):
    from jsonschema.validators import Draft202012Validator
    errs = sorted(Draft202012Validator(rec["schema"]).iter_errors(ans), key=lambda e: list(e.path))
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
        want_anchor = None if c["score"] < 4 else max(a for a in (4, 6, 8, 10) if a <= c["score"])
        if c["anchor"] != want_anchor:
            return f"{c['id']}: score {c['score']} does not sit on its anchor {c['anchor']} (1-3 null, 4-5 4, 6-7 6, 8-9 8, 10 10)"
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
    role = a[a.index("--role") + 1] if "--role" in a and a.index("--role") + 1 < len(a) else None
    if role:
        i = a.index("--role"); a = a[:i] + a[i + 2:]
    if cmd != "freeze" and not role:
        die("--role owner|tech", 2)
    if cmd == "freeze" and len(a) >= 4 and a[2] == "--type":
        return freeze(os.path.abspath(a[1]), a[3], "--force" in a)
    if cmd == "prompt" and len(a) == 2:
        print(of_role(frozen(os.path.abspath(a[1])), role)["role"])
        return
    if cmd == "score" and len(a) == 3:
        rec = of_role(frozen(os.path.abspath(a[1])), role)
        ans = load_answer(a[2])
        bad = check(rec, ans)
        if bad:
            die(bad)
        print(json.dumps(score(rec, ans), ensure_ascii=False))
        return
    if cmd == "verdict" and len(a) >= 3:
        if len(a) - 2 != RATINGS:
            die(f"the closing verdict takes exactly {RATINGS} blind ratings, got {len(a) - 2}")
        rec = of_role(frozen(os.path.abspath(a[1])), role)
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
        ready = sorted({i for r in runs for i in r["readiness"]})
        text = ("přijato" + (", zveřejnění blokuje: " + "; ".join(ready) if ready else ", připraveno ke zveřejnění")) if ok else "nepřijato"
        print(json.dumps({"role": role, "ratings": len(runs), "median_quality_score": med, "lowest_rating": low, "criteria_median": crit,
                          "accepted": ok, "publish_blocked_by": ready, "verdict": text}, ensure_ascii=False))
        sys.exit(0 if ok else 3)
    die("usage: freeze <project> --type <type> [--force] | prompt|score|verdict <project> --role owner|tech [<retro.json>...]", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
