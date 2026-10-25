#!/usr/bin/env python3
"""aid-ui-critic.py - the two roles at the six decision places: frozen roles, scores, gates and the place verdict
(P113a 12./13. 10. 2026; places and gates P113, 17. 10. 2026).

Two roles rate every decision place (PM 13./14. 10. 2026): the CLIENT (the owner: does it fit my business, would I
pay for it, would I sign it) and the EXPERT (the technician: craft, facts, law, what the client cannot judge). Each
rubric was written from its role brief by its own author and reviewed (critic/AUTHORS.yaml, critic/role-briefs/).

Places (PLACES): sdeleni (message), logo, pohyb (motion), struktura (structure), vzhled (look), web (finished web).
A place has a rubric and a gate file per role: skills/ui-design/critic/<type>.<role>.<place>.yaml and
<type>.<role>.<place>.gates.yaml; `web` keeps the P113a rubrics <type>.<role>.yaml and also rates with the rubrics of
vzhled and struktura (their criteria carry the prefix `vzhled.` / `struktura.`, their gates are those places' gates),
so `web` has six scores. Without --place every command means `web`.

  freeze <project> --type <type> [--place <p>] [--phase build|launch] [--force]
      Builds both roles of the place (persona, criteria with weights summing to 100, anchors) with the project's context
      (docs/content/product-context.md, docs/product-vision.md, docs/seo/brief.md) and stores the gates with them (never
      in a prompt). Phase build (default): the type's launch_only criteria are left out of `web`. Writes
      .aid-ui/critic/frozen/<place>.json (`web`: .aid-ui/critic/frozen.json) {type, place, phase, rubric, roles: {owner|tech:
      {rubrics, gates, role, sha256}}, schema, sha256, at}. Never rewritten without --force, never while the place's loop
      has rounds; a context line that mentions scores or acceptance is dropped (the roles are blind to both).
  prompt <project> --role owner|tech [--place <p>]
      The role's prompt: the frozen role only - no gate, no threshold.
  score <project> <answer.json> --role owner|tech [--place <p>] [--metrics-dir <dir>]
      Validates the role's answer (references/critic-retro.schema.json; every criterion answered once per direction,
      anchors consistent with scores) and prints the P113a fields of the main rubric of the first direction
      (quality_score, criteria, min_criterion, accepted, findings_by_owner, readiness) and per direction and rubric
      {direction, rubric, weighted, weighted_now, gates, metrics, status accepted|reservation|failed, reservation}.
      reservation = every failing gate is held only by what the client must supply: the criterion's studio_score meets
      it and to_ten.client names the client's part (D1); a `volba` finding on it never makes a reservation.
      A criterion the role could not assess holds no gate (no photos yet), except a gate with `required: true` (the
      gates over facts and law, IMP-702): there it fails, never a reservation.
      accepted = no rubric of the direction failed.
  verdict <project> --role owner|tech [--place <p>] <answer.json> x3
      Three blind ratings of one place by one role (the closing audit): the `audit` block of the place's gate file
      (median_min, any_min, criterion_median_min). Exit 0 accepted, 3 not accepted, 1 invalid answer.
  place-verdict <project> --place <p> --score <score.json>... [--pm-choice <direction> --reason <t>] [--pm-veto <t>] [--supplied]
                [--fixed-in <round>]  (a fact or law finding of that round no longer returns the place once it was accepted,
                fixed and the independent verifier saw the fix over the version now)
      The place's decision from every score of the place (one per role): facts and law > the expert's craft defect >
      the client's choice (D5). A `fakt`/`zakon` finding returns the place (on one direction: that direction is out); a
      direction is out when any of its scores failed or the expert has a blocking `remeslo` finding on it; among the
      rest the client's `choice` wins (D2; --pm-choice in manual mode, the client's pick kept); --pm-veto returns it;
      --supplied rates the one mark the PM supplied. Prints {place, status accepted|accepted_with_reservation|returned,
      chosen, chosen_by, blocked_by, answers, scores, target, upstream, options}. Exit 0 decided, 1 refused, 3 the
      client chose a direction that did not pass.
  place-check <project> --place <p> <verdict.json>
      What aid-ui-state.sh place-record runs: the verdict must be derived from the place's last round (the answers of
      .aid-ui/critic/rounds[/<place>]/<n>/<role>/answer.json, re-scored and re-decided with the recorded options) and
      its target must be the current bundle sha; a hand-made verdict is refused. Prints the verdict to record.
  bundle-files <project> --place <p>  /  bundle-sha <project> --place <p>
      The files a place's roles rate (PLACE_FILES) and their sha (the dirsha rule of aid-ui-motion.py over that list).
      A web's struktura holds the served pure skeleton .aid-ui/skeleton/site/ too (IMP-700: a rebuild that changes a
      page voids the verdict); an app's does not (its model is in the bundle, approving it changes the pages).
      A missing required input exits 1 naming it.
"""
import glob, hashlib, json, os, re, statistics, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from aid_ui_memory import critic_dir   # noqa: E402  (P115: the launch rating's own directory)

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")
CRIT = os.path.join(SKILL, "critic")
RATINGS = 3   # blind closing ratings of one place
# what a role must not read: scores, thresholds, acceptance (the context docs are written by the agent)
LEAK = re.compile(r"\b\d{1,2}(?:[.,]\d)?\s*/\s*10\b|quality_score|akcept|accept|threshold|\bprah|\bpráh|\bznámk", re.I)   # \b: not "Poznámky"
ROLES = ("owner", "tech")   # the client (owner) and the expert (tech)
PLACES = ("sdeleni", "logo", "pohyb", "struktura", "vzhled", "web")
LABEL = {"sdeleni": "sdělení", "logo": "logo", "pohyb": "pohyb", "struktura": "struktura", "vzhled": "vzhled", "web": "hotový web"}
WHAT = {
    "sdeleni": "Dokument o podniku (positioning, teze, publikum, hlas zákazníka, námitky, nabídka, důkazy, tón, Ke kontrole), "
               "pět sloganů a čistopis pro klienta - soubory v `podklady/` pracovního adresáře.",
    "logo": "Směry loga, které ti studio předkládá: karta každého směru (značka, logo s názvem, malé řezy, kontexty), zadání "
            "značky, audit dnešního loga a loga konkurence - v `podklady/`.",
    "pohyb": "Varianty pohybu značky: stránka s animací každé varianty (`logo-animace.html`) v `podklady/`; otevři ji a pusť.",
    "struktura": "Strom webu (`structure.json`) a živá kostra na stálé adrese níže: proklikej ji jako zákazník.",
    "vzhled": "Směry vzhledu jako skutečné stránky v kostře webu (každý směr ve vlastní složce v `podklady/`), na počítači i mobilu.",
    "web": "Hotový web, který ti studio ukázalo: živé stránky na počítači a na mobilu (snímky celé stránky v příloze, odkazy na "
           "živý web) a soubory webu v pracovním adresáři (jen ke čtení).",
}
# (glob relative to the project, required) - what each place's roles rate; directions come from the first entry
PLACE_FILES = {
    "sdeleni": [("docs/content/product-context.md", True), ("docs/content/cistopis.md", False),
                ("docs/content/otazky-klientovi.md", False), ("docs/product-vision.md", False)],
    "logo": [(".aid-ui/logo/cards/*.png", True), ("docs/design/brand-brief.md", False), (".aid-ui/logo/audit.md", False),
             (".aid-ui/critic/competitors/logos/*", False)],
    "pohyb": [(".aid-ui/motion/*/logo-animace.html", True), (".aid-ui/motion/*/logo-motion.css", False)],
    # IMP-700: the served skeleton too (it is built from the facts register and the builder as well): a rebuild that
    # changes a page voids the verdict; an app's skeleton is not here - its model is, and approving it changes the pages
    "struktura": [(".aid-ui/structure.json", True), (".aid-ui/skeleton/redirects.csv", False), (".aid-ui/skeleton/site/**", False)],
    "vzhled": [(".aid-ui/directions/*/**", True)],
    "web": [("site/**", True)],
}
# P116: a web application's places - the type decides which exist (aplikace-postup.md): struktura (screens and tasks),
# vzhled and web (the finished app); logo only for a new brand; sdeleni and pohyb are skipped with their reason
APP_WHAT = {
    "struktura": "Model obrazovek a úloh aplikace (`podklady/screens.json`: obrazovky s akcemi a stavy, úlohy se sedmi stavy, výsledkem "
                 "a cestami selhání) a proklikávací kostra na stálé adrese níže: proklikej každou úlohu jako uživatel, přepínej stavy (?stav=).",
    "vzhled": "Tři směry vzhledu nad kostrou aplikace (každý ve vlastní složce v `podklady/`): hlavní obrazovka, obrazovka úlohy a její stavy, "
              "na počítači i telefonu.",
    "web": "Hotová aplikace (nebo ověřovací stavba studia) na stálé adrese, výsledky brány studia (`podklady/overenie.json`: app_flows, "
           "app_states, keyboard_flows, task_recovery, axe) a soubory aplikace v pracovním adresáři (jen ke čtení).",
}
APP_FILES = {"web": [("site/**", True), (".aid-ui/verify/result.json", False)],   # the built app and the gate's result
             "struktura": [("docs/design/screens.json", True), (".aid-ui/precheck/result.json", False), (".aid-ui/baseline/tasks.json", False), ("zadani.md", False),
                           ("docs/plans/roadmap.md", False)]}
APP_SKIP = {"sdeleni": "aplikace slogan ani hlavní sdělení nepotřebuje (aplikace-postup.md, oddíl 0)",
            "pohyb": "aplikace pohyb značky nemá, dokud o něj PM výslovně nepožádá",
            "logo": "značka existuje nebo jde o interní nástroj (brand existing|none)"}


def variant_of(proj):
    try:
        return json.load(open(os.path.join(proj, "docs/design/brand-state.json"), encoding="utf-8")).get("variant") or {}
    except (OSError, ValueError):
        return {}


def skipped_place(proj, place):
    """The reason a place does not exist for this project's type, or '' (P116: only a webapp skips places)."""
    v = variant_of(proj)
    if v.get("type") != "webapp" or place not in APP_SKIP or (place == "logo" and v.get("brand") == "new"):
        return ""
    return APP_SKIP[place]


UPSTREAM = {"sdeleni": [], "logo": ["sdeleni"], "pohyb": ["logo"], "struktura": [], "vzhled": ["struktura", "logo", "pohyb"],
            "web": ["vzhled", "struktura", "logo", "pohyb", "sdeleni"]}
EXTRA = {"web": ("vzhled", "struktura")}   # the finished web is rated with these places' rubrics too (F6 1a)
METRICS = ("web_logo_draw_ms", "web_logo_name_visible_ms", "web_motion_running_after_ms", "final_frame_diff_px")
WHEN = ("nove", "oziveni", "zavedeny_motiv")


def die(msg, code=1):
    print("ERROR: aid-ui-critic.py: " + msg, file=sys.stderr)
    sys.exit(code)


def load_yaml(p):
    import yaml
    with open(p, encoding="utf-8") as f:
        return json.loads(json.dumps(yaml.safe_load(f), default=str))   # dates as text


def read(p, limit=12000):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()[:limit]
    except OSError:
        return ""


def sha_file(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def place_of(a):
    p = a[a.index("--place") + 1] if "--place" in a and a.index("--place") + 1 < len(a) else "web"
    if p not in PLACES:
        die("--place must be one of " + ", ".join(PLACES), 2)
    return p


def frozen_path(proj, place="web"):
    return os.path.join(critic_dir(proj), "frozen.json" if place == "web" else os.path.join("frozen", place + ".json"))


def rounds_dir(proj, place="web"):
    return os.path.join(critic_dir(proj), "rounds", *([] if place == "web" else [place]))


def rubric_file(typ, role, key, place):
    """The rubric a role rates with at a place: `web` keeps <type>.<role>.yaml; an extra rubric is its place's. A web
    application with a new brand rates its logo with the web's logo rubrics (P116: an app has none of its own)."""
    typ = "web-local" if (typ, key) == ("webapp", "logo") else typ
    return os.path.join(CRIT, f"{typ}.{role}.yaml" if key == "web" else f"{typ}.{role}.{key}.yaml")


def gates_file(typ, role, key):
    typ = "web-local" if (typ, key) == ("webapp", "logo") else typ
    return os.path.join(CRIT, f"{typ}.{role}.{key}.gates.yaml")


def load_gates(path, rubric_ids):
    if not os.path.isfile(path):
        die(f"no gate file {path}: every rubric of a place has its gates", 2)
    g = load_yaml(path) or {}
    for x in g.get("gates") or []:
        ids = x.get("any_of") or [x.get("criterion")]
        bad = [i for i in ids if i not in rubric_ids]
        if bad or not isinstance(x.get("min"), (int, float)):
            die(f"{os.path.basename(path)}: gate {x} names {bad or 'no min'}, not criteria of its rubric", 2)
        if "required" in x and not isinstance(x["required"], bool):
            die(f"{os.path.basename(path)}: gate {x.get('criterion') or x.get('any_of')}: required is true or false, not {x['required']!r}", 2)
        if x.get("when") is not None and x["when"] not in WHEN:
            die(f"{os.path.basename(path)}: when {x['when']} is not one of {', '.join(WHEN)}", 2)
    for m in g.get("metrics") or []:
        if m.get("metric") not in METRICS or not any(k in m for k in ("max", "min")):
            die(f"{os.path.basename(path)}: metric {m} is not one of {', '.join(METRICS)} with max or min", 2)
    return {k: g[k] for k in ("gates", "weighted_min", "metrics", "audit") if k in g}


def freeze(proj, typ, force, phase="build", place="web"):
    out = frozen_path(proj, place)
    if os.path.exists(out) and not force:
        die(f"{out} exists: the rubric does not move during a loop (--force to rebuild it)")
    rd = rounds_dir(proj, place)
    has_rounds = os.path.isdir(rd) and any(x.isdigit() or (place == "web" and x.startswith("r")) for x in os.listdir(rd))
    if force and has_rounds:
        die(f"a quality loop has rounds in {rd}: the rubric cannot change under it (archive the rounds to start a new loop)")
    if phase not in ("build", "launch"):
        die("--phase is build (before the deployment) or launch", 2)
    if (typ == "webapp") != (variant_of(proj).get("type") == "webapp"):   # the bundle follows the variant: they must agree
        die(f"--type {typ} but the project's recorded variant is {variant_of(proj).get('type') or 'none'} (docs/design/brand-state.json)", 2)
    if typ == "webapp" and skipped_place(proj, place):
        die(f"place {place} does not exist for a web application: {skipped_place(proj, place)}", 2)
    common_p = os.path.join(CRIT, f"{typ}.yaml")
    keys = (place,) + EXTRA.get(place, ())
    files = {(r, k): rubric_file(typ, r, k, place) for r in ROLES for k in keys}
    miss = [p for p in [common_p] + list(files.values()) if not os.path.isfile(p)]
    if miss:
        die(f"no rubric for type {typ} at {place} ({', '.join(miss)})", 2)
    authors = load_yaml(os.path.join(CRIT, "AUTHORS.yaml")) or {}
    for p in files.values():   # a rubric changed after its authors' record is not the reviewed one
        a = authors.get(os.path.basename(p)) or {}
        if not (a.get("author") and a.get("reviewer")) or a.get("sha256") != sha_file(p):
            die(f"{os.path.basename(p)}: not the rubric critic/AUTHORS.yaml records (author, reviewer, sha256); "
                "a changed rubric needs its author and a review first")
    common = load_yaml(common_p)   # task_test, launch_inputs, components: the type's, both roles'
    ctx_parts = [("Kontext produktu", "docs/content/product-context.md"), ("Vize", "docs/product-vision.md"),
                 ("Zadání pro vyhledávání", "docs/seo/brief.md")]
    ctx = "\n\n".join(f"## {t}\n\n{read(os.path.join(proj, p))}" for t, p in ctx_parts if read(os.path.join(proj, p)))
    leak = [ln.strip() for ln in ctx.splitlines() if LEAK.search(ln)]
    if leak:   # dropped, not refused: a loop must not stop on an old audit score in the vision
        ctx = "\n".join(ln for ln in ctx.splitlines() if not LEAK.search(ln))
        print(f"DROPPED {len(leak)} context line(s) about scores or acceptance: " + " | ".join(x[:80] for x in leak[:3]), file=sys.stderr)
    if typ == "webapp":   # P116: the project's own brief and code, never filtered - its thresholds are the app's, not the studio's
        if not read(os.path.join(proj, "zadani.md")):
            die("no zadani.md in the project: the client role of an app stands on the project's brief and code (aplikace-postup.md)")
        own = "\n\n".join(f"## {t}\n\n{read(os.path.join(proj, p))}" for t, p in (("Zadání projektu", "zadani.md"), ("Plán projektu", "docs/plans/roadmap.md"))
                           if read(os.path.join(proj, p)))
        if api_routes(proj):
            own += "\n\n## Cesty API v kódu projektu (co aplikace umí)\n\n" + "\n".join("- " + r for r in api_routes(proj))
        ctx = own + ("\n\n" + ctx if ctx else "")
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
    schema = read(os.path.join(SKILL, "references", "critic-retro.schema.json"), 10 ** 6)
    tpl = read(os.path.join(CRIT, "role-template.md"))
    multi = place in ("logo", "pohyb", "vzhled")
    roles = {}
    for r in ROLES:
        rubrics, gates, sections = [], {}, []
        for k in keys:
            rub = load_yaml(files[(r, k)])
            if sum(c["weight"] for c in rub["criteria"]) != 100 or any(not re.fullmatch(r"[a-z0-9_]+", c["id"]) for c in rub["criteria"]):
                die(f"{files[(r, k)]}: weights must sum to 100 and ids be ascii snake_case")
            if k == "web":
                unknown = [x for x in (common.get("launch_only") or {}).get(r) or [] if x not in [c["id"] for c in rub["criteria"]]]
                if unknown:   # a typo would quietly bring a launch criterion back into the score
                    die(f"{os.path.basename(common_p)}: launch_only.{r} names {unknown}, not criteria of {os.path.basename(files[(r, k)])}")
                held = (common.get("launch_only") or {}).get(r) or [] if phase == "build" else []
                rub["criteria"] = [c for c in rub["criteria"] if c["id"] not in held]   # judged after the deployment only
            gates[k] = load_gates(gates_file(typ, r, k), [c["id"] for c in rub["criteria"]] + [c for c in ((common.get("launch_only") or {}).get(r) or []) if k == "web"])
            pre = "" if k == place else k + "."
            if k != place:
                sections.append(f"## Měřítko místa {LABEL[k]} (id kritérií s předponou `{pre}`)")
            sections += [f"### {pre}{c['id']} - {c['name']}\n" + "\n".join(f"- {a}: {v}" for a, v in sorted(c["anchors"].items(), key=lambda x: int(x[0])))
                         for c in rub["criteria"]]
            rubrics.append({"key": k, "rubric": rub})
        main = rubrics[0]["rubric"]
        persona_rules = list(main["persona"]["rules"]) + [x for e in rubrics[1:] for x in e["rubric"]["persona"]["rules"]]
        directions_rule = ("Studio ti předkládá víc směrů (variant). Hodnotíš **každý směr zvlášť** v `directions` (id směru = jméno "
                           "jeho karty, složky nebo varianty), každý všemi kritérii; nálezy k jednomu směru nesou `direction`."
                           if multi else "Hodnotíš jeden výsledek: kritéria dej do `criteria`.")
        if multi and r == "owner":
            directions_rule += " Jako klient vyber v `choice` směr, který bys zaplatil a použil (id směru)."
        client_memory = ("\nJako klient jsi jedna role na všech místech rozhodnutí: v `podklady/historie.json` máš i svá hodnocení a "
                         "odpovědi z dřívějších míst a rozhodnutí PM (označená jako jeho). Drž se toho, co jsi řekl, a změnu názoru "
                         "zdůvodni.\n" if r == "owner" else "")
        role = tpl.format(persona_who=main["persona"]["who"], persona_wants=main["persona"]["wants"],
                          place_name="hotová aplikace" if typ == "webapp" and place == "web" else LABEL[place],
                          place_what=(APP_WHAT if typ == "webapp" else WHAT).get(place, WHAT[place]), directions_rule=directions_rule, client_memory=client_memory,
                          persona_rules="\n".join("- " + x for x in persona_rules), criteria="\n\n".join(sections), context=ctx,
                          lang=lang, schema=schema)
        if phase == "build" and place == "web":
            role += ("\n\n# Fáze: stavba (před nasazením)\n\nWeb ještě není nasazený na hosting klienta. Co se dá ověřit až po nasazení"
                     " (HTTPS a přesměrování, hlavičky serveru, chybová stránka a zákazy na serveru, ostrý příjem formuláře,"
                     " doména), teď nehodnotíš: nepiš k tomu nálezy, nesnižuj kvůli tomu žádné kritérium a nedávej to do cesty k 10."
                     " Chce-li kotva něco z toho (např. přesměrování, kompresi a cache na serveru, ostré doručení), tu část kotvy"
                     " v této fázi nepočítáš a kritérium hodnotíš podle zbytku. Doručení formuláře doložené kontrolou studia na"
                     " náhledu (`podklady/overenie.json`, form_delivery) je v této fázi plný důkaz doručení.")
        roles[r] = {"rubric": main, "rubrics": rubrics, "gates": gates, "role": role,
                    "authors": {os.path.basename(files[(r, k)]): authors[os.path.basename(files[(r, k)])] for k in keys}}
        roles[r]["sha256"] = digest({"rubric": rubrics, "role": role, "roles": gates, "schema": json.loads(schema)})
    rec = {"type": typ, "place": place, "phase": phase, "rubric": dict(common, persona=roles["owner"]["rubric"]["persona"]),   # the client plays the owner
           "roles": roles, "schema": json.loads(schema), "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    rec["sha256"] = digest(rec)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(rec, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"FROZEN {typ} {place} {rec['sha256'][:12]} -> {out} (owner {roles['owner']['sha256'][:12]}, tech {roles['tech']['sha256'][:12]})")


def api_routes(proj, limit=80):
    """The HTTP routes the project's code declares (FastAPI/Flask decorators, Express calls): what the app can do."""
    out = []
    pat = re.compile(r"""@(?:\w+\.)?(?:get|post|put|patch|delete|route)\(\s*["']([^"']+)["']|\b(?:app|router)\.(get|post|put|patch|delete)\(\s*["']([^"']+)["']""")
    for root, dirs, files in os.walk(proj):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv", ".aid-ui", ".aid-o", "site", "__pycache__")]
        for f in sorted(files):
            if f.endswith((".py", ".js", ".ts")):
                for m in pat.finditer(read(os.path.join(root, f), 200000)):
                    r = m.group(1) or m.group(3)
                    out.append(f"{r}  ({os.path.relpath(os.path.join(root, f), proj)})")
                    if len(out) >= limit:
                        return out
    return out


def digest(rec):
    return hashlib.sha256(json.dumps({k: rec[k] for k in ("rubric", "role", "roles", "schema") if k in rec}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def frozen(proj, place="web"):
    p = frozen_path(proj, place)
    if not os.path.isfile(p):
        die(f"no frozen critic in {p} (freeze --place {place} first)")
    rec = json.load(open(p, encoding="utf-8"))
    if "schema" not in rec or "roles" not in rec or digest(rec) != rec.get("sha256"):
        die("the frozen critic was edited after freezing, or predates the two roles (sha mismatch or no roles; archive the rounds and freeze again)")
    if place == "web" and any("gates" not in rec["roles"][r] for r in ROLES):   # a 3.4.0 loop: its own rubrics, today's web gates
        typ = rec.get("type", "web-local")
        for r in ROLES:
            x = rec["roles"][r]
            x["rubrics"] = [{"key": "web", "rubric": x["rubric"]}]
            x["gates"] = {"web": load_gates(gates_file(typ, r, "web"), [c["id"] for c in x["rubric"]["criteria"]])}
        rec["place"] = "web"
    rec.setdefault("place", place)
    return rec


def of_role(rec, role):
    if role not in ROLES:
        die("--role must be one of " + ", ".join(ROLES), 2)
    x = rec["roles"][role]
    return {"role_id": role, "place": rec.get("place", "web"), "rubric": x["rubric"], "rubrics": x["rubrics"], "gates": x["gates"],
            "role": x["role"], "schema": rec["schema"]}


def criteria_of(rec):
    """{qualified id: (rubric key, criterion)}; an extra rubric's ids carry its place as prefix."""
    out = {}
    for e in rec["rubrics"]:
        pre = "" if e["key"] == rec["place"] else e["key"] + "."
        for c in e["rubric"]["criteria"]:
            out[pre + c["id"]] = (e["key"], c)
    return out


def directions(ans):
    if ans.get("directions"):
        return ans["directions"]
    return [{"id": "main", "criteria": ans.get("criteria") or []}]


def check(rec, ans):
    from jsonschema.validators import Draft202012Validator
    errs = sorted(Draft202012Validator(rec["schema"]).iter_errors(ans), key=lambda e: list(e.path))
    if errs:
        e = errs[0]
        return f"schema at {'/'.join(map(str, e.path)) or '(root)'}: {e.message}"
    if bool(ans.get("criteria")) == bool(ans.get("directions")):
        return "the answer has either criteria (one result) or directions (several), not both and not neither"
    want = sorted(criteria_of(rec))
    dirs = directions(ans)
    ids = [d["id"] for d in dirs]
    if len(set(ids)) != len(ids):
        return f"direction ids repeat: {ids}"
    for d in dirs:
        got = [c["id"] for c in d["criteria"]]
        if sorted(got) != want:
            return f"{d['id']}: criteria answered {sorted(got)}, the rubric has {want}"
        for c in d["criteria"]:
            if c["score"] is None:
                if not (c.get("not_assessable") or "").strip():
                    return f"{c['id']}: no score and no reason (not_assessable)"
                continue
            for sk, ak in (("score", "anchor"), ("studio_score", "studio_anchor")):
                if c.get(sk) is None:
                    continue
                want_anchor = None if c[sk] < 4 else max(a for a in (4, 6, 8, 10) if a <= c[sk])
                if c[ak] != want_anchor:
                    return f"{c['id']}: {sk} {c[sk]} does not sit on its anchor {c[ak]} (1-3 null, 4-5 4, 6-7 6, 8-9 8, 10 10)"
            if c.get("studio_score") is not None and c["studio_score"] < c["score"]:
                return f"{c['id']}: studio_score {c['studio_score']} under score {c['score']} (the studio's part is never worse than the whole)"
            if c["score"] < 10 and not (c["to_ten"]["studio"] or c["to_ten"]["client"]):
                return f"{c['id']}: score {c['score']} and no step to 10 (to_ten)"
            if c["score"] == 10 and (c["to_ten"]["studio"] or c["to_ten"]["client"]):
                return f"{c['id']}: score 10 with steps to 10 (to_ten must be empty)"
            if c.get("studio_score") is not None and not c["to_ten"]["client"]:   # what holds it down is named as the client's part
                return f"{c['id']}: studio_score without what the client supplies (to_ten.client)"
    for f in ans["findings"]:
        if rec.get("role_id") == "tech" and "blocking" not in f and f.get("severity") in ("blocking", "major", "minor"):
            f["blocking"] = f["severity"] == "blocking"   # the expert's own severity says it (Trading 22. 10.: two answers lost on a missing flag)
        if rec.get("role_id") == "tech" and not isinstance(f.get("blocking"), bool):   # D5: the expert says it, never implied
            return f"finding {f['id']}: the expert's finding needs blocking true|false"
        if f["criterion"] not in want:
            return f"finding {f['id']}: unknown criterion {f['criterion']}"
        if f.get("direction") is not None and f["direction"] not in ids:
            return f"finding {f['id']}: unknown direction {f['direction']}"
    if ans.get("choice") is not None and ans["choice"] not in ids:
        return f"choice {ans['choice']}: not a direction of the answer ({', '.join(ids)})"
    return None


def apply_gates(g, crits, d, findings, metrics):
    """One direction, one rubric: [{gate, ok, value}], [{metric, ok, value}], status, reservation ids."""
    rows, mrows, held = [], [], []
    now = {k: c["score"] for k, c in crits.items() if c["score"] is not None}
    studio = {k: (c.get("studio_score") or c["score"]) for k, c in crits.items() if c["score"] is not None}
    volba = {f["criterion"].split(".")[-1] for f in findings if f.get("kind") == "volba" and f.get("direction") in (None, d["id"])}

    def client_part(k):   # D1: held only by what the client supplies (P113a studio_score / to_ten.client), never by a choice
        c = crits.get(k) or {}
        return bool(c.get("studio_score") is not None and (c.get("to_ten") or {}).get("client")) and k not in volba

    for x in g.get("gates") or []:
        name = ("any_of " + "|".join(x["any_of"]) if x.get("any_of") else x["criterion"]) + " >= %s" % x["min"] + (" when " + x["when"] if x.get("when") else "")
        if x.get("when"):
            field = d.get("zavedeny_motiv") if x["when"] == "zavedeny_motiv" else d.get("rezim")
            if field is None:
                rows.append({"gate": name, "ok": False, "value": None, "why": "role neuvedla režim"})
                continue
            if (x["when"] == "zavedeny_motiv" and field != "ano") or (x["when"] != "zavedeny_motiv" and field != x["when"]):
                continue   # the gate does not apply to this direction
        ids = x["any_of"] if x.get("any_of") else [x["criterion"]]
        have = [k for k in ids if k in now]
        if not have:
            if x.get("required"):   # IMP-702: a gate over facts or law is never skipped by "nejde posoudit"
                rows.append({"gate": name, "ok": False, "value": None, "why": "kritérium nešlo posoudit; tuto bránu nejde přeskočit"})
            elif x.get("any_of"):
                rows.append({"gate": name, "ok": False, "value": None, "why": "žádné kritérium nešlo posoudit"})
            # else a criterion the role marks not_assessable does not hold its gate (by design: no photos yet)
            continue
        ok = any(now[k] >= x["min"] for k in have)
        row = {"gate": name, "ok": ok, "value": max(now[k] for k in have)}
        if not ok:
            row["reservation"] = [k for k in have if studio[k] >= x["min"] and client_part(k)][:1]
            if not row["reservation"]:
                row.pop("reservation")
        rows.append(row)
    w = {k: c["_w"] for k, c in crits.items()}
    tot = sum(w[k] for k in studio)
    mean = lambda dd: round(sum(dd[k] * w[k] for k in dd) / tot, 2) if tot else 0.0
    weighted, weighted_now = mean(studio), mean(now)
    if g.get("weighted_min") is not None:
        ok = weighted_now >= g["weighted_min"]
        row = {"gate": "weighted >= %s" % g["weighted_min"], "ok": ok, "value": weighted_now}
        if not ok and weighted >= g["weighted_min"] and any(client_part(k) for k in crits):
            row["reservation"] = [k for k in crits if client_part(k)]
        rows.append(row)
    for m in g.get("metrics") or []:
        v = (metrics or {}).get(m["metric"]) if isinstance(metrics, dict) else None
        if metrics is None:
            mrows.append({"metric": m["metric"], "ok": False, "value": None, "why": "nezměřeno"})
        elif metrics.get("not_applicable"):
            mrows.append({"metric": m["metric"], "ok": False, "value": "not_applicable", "why": "bez pohybu: jen záznam místa bez pohybu (place-record --without)"})
        elif not isinstance(v, (int, float)):
            mrows.append({"metric": m["metric"], "ok": False, "value": None, "why": "nezměřeno"})
        else:
            mrows.append({"metric": m["metric"], "ok": (v <= m["max"]) if "max" in m else (v >= m["min"]), "value": v})
    failing = [r for r in rows if not r["ok"]] + [r for r in mrows if not r["ok"]]
    if not failing:
        status, res = "accepted", []
    elif all(r.get("reservation") for r in failing):
        status, res = "reservation", sorted({k for r in failing for k in r["reservation"]})
    else:
        status, res = "failed", []
    for r in rows:
        r.pop("reservation", None)
    return {"weighted": weighted, "weighted_now": weighted_now, "gates": rows, "metrics": mrows, "status": status, "reservation": res}


def score(rec, ans, metrics_dir=None, answer_sha=None):
    """P113a fields of the main rubric of the first direction (the loop's measure: the studio's work, a criterion held
    down only by an open client item counts with its studio_score) + the gated result per direction and rubric."""
    idx = criteria_of(rec)
    place = rec["place"]
    out_dirs = []
    for d in directions(ans):
        given = {c["id"]: c for c in d["criteria"]}
        mets = None
        if place == "pohyb":
            mf = os.path.join(metrics_dir or "", "metrics-pohyb-%s.json" % d["id"])
            try:
                mets = json.load(open(mf, encoding="utf-8"))
            except (OSError, ValueError):
                mets = None
            # P113 whole review: a measurement of another file than the direction's animation now is no measurement
            page = os.path.join(os.path.dirname(os.path.abspath(metrics_dir or ".")), "motion", d["id"], "logo-animace.html")   # .aid-ui/critic -> .aid-ui/motion
            if isinstance(mets, dict) and mets.get("page_sha256") and os.path.isfile(page) and mets["page_sha256"] != sha_file(page):
                mets = None
        for e in rec["rubrics"]:
            pre = "" if e["key"] == place else e["key"] + "."
            crits = {c["id"]: dict(given[pre + c["id"]], _w=c["weight"]) for c in e["rubric"]["criteria"]}
            fs = [dict(f, criterion=f["criterion"][len(pre):]) for f in ans["findings"] if f["criterion"].startswith(pre) and (pre or "." not in f["criterion"])]
            r = apply_gates(rec["gates"][e["key"]], crits, d, fs, mets)
            out_dirs.append(dict(r, direction=d["id"], rubric=e["key"]))
    first = directions(ans)[0]
    main_key = rec["rubrics"][0]["key"]
    w = {c["id"]: c["weight"] for c in rec["rubric"]["criteria"]}
    given = {c["id"]: c for c in first["criteria"] if c["id"] in w}
    now = {k: c["score"] for k, c in given.items() if c["score"] is not None}
    sc = {k: (c.get("studio_score") or c["score"]) for k, c in given.items() if c["score"] is not None}
    tot = sum(w[k] for k in sc)
    mean = lambda dd: round(sum(dd[k] * w[k] for k in dd) / tot, 1) if tot else 0.0
    owners = {"agent": 0, "client": 0}
    for f in ans["findings"]:
        owners[f["owner"]] += 1
    mine = [x for x in out_dirs if x["direction"] == first["id"]]
    return {"place": place, "quality_score": mean(sc), "quality_now": mean(now), "criteria": sc, "criteria_now": now,
            "min_criterion": min(sc.values()) if sc else 0,
            "limited_by": sorted({i for d in directions(ans) for c in d["criteria"] for i in c.get("limited_by") or []}),
            "accepted": all(x["status"] != "failed" for x in mine), "status": next((x["status"] for x in mine if x["rubric"] == main_key), None),
            "findings_by_owner": owners, "readiness": [r["item"] for r in ans["readiness"]], "directions": out_dirs,
            "findings": [{k: f.get(k) for k in ("id", "criterion", "severity", "owner", "kind", "blocking", "direction", "text")} for f in ans["findings"]],
            "choice": ans.get("choice"), "answer_sha256": answer_sha}


def load_answer(p):
    try:
        t = open(p, encoding="utf-8").read().strip()
        m = re.match(r"^```(?:json)?\s*(.*?)\s*```$", t, re.S)
        return json.loads(m.group(1) if m else t)
    except (OSError, ValueError) as e:
        die(f"{p}: not readable JSON ({e})")


def scored(proj, place, role, path, metrics_dir=None):
    rec = of_role(frozen(proj, place), role)
    ans = load_answer(path)
    bad = check(rec, ans)
    if bad:
        die(f"{path}: {bad}" if path else bad)
    want, got = bundle_directions(proj, place), sorted(d["id"] for d in directions(ans))
    if got != want:   # every direction of the bundle rated, none made up
        die(f"{path}: the answer rates the directions {got}, the {place} bundle has {want}")
    return dict(score(rec, ans, metrics_dir or os.path.join(proj, ".aid-ui", "critic"), sha_file(path)), role=role)


# ---------------------------------------------------------------- bundles

def bundle_files(proj, place, need=True):
    """Project-relative files the place's roles rate; a missing required input dies naming it. A motion place with a
    `without` record (no motion in this project) has the record as its bundle."""
    if place == "pohyb":
        w = place_state(proj).get("pohyb") or {}
        if w.get("without"):
            return [".aid-ui/critic/pohyb-without.json"] if os.path.isfile(os.path.join(proj, ".aid-ui/critic/pohyb-without.json")) else []
    out = []
    files = APP_FILES.get(place, PLACE_FILES[place]) if variant_of(proj).get("type") == "webapp" else PLACE_FILES[place]
    for pat, req in files:
        root = os.path.realpath(proj)   # P113 whole review: no file reached through a symlink anywhere on its path
        hits = sorted(os.path.relpath(f, proj) for f in glob.glob(os.path.join(proj, pat), recursive=True)
                      if os.path.isfile(f) and os.path.realpath(f) == os.path.join(root, os.path.relpath(f, proj)))
        if req and not hits and need:
            die(f"{place}: missing input {pat} (the place's roles rate it; it is not replaced by site/)")
        out += hits
    sup = os.path.join(".aid-ui", "client", "supplied", place + ".json")   # P116: what the client supplied for this place
    if os.path.isfile(os.path.join(proj, sup)) and os.path.realpath(os.path.join(proj, sup)) == os.path.join(os.path.realpath(proj), sup):
        out.append(sup)
    return sorted(set(out))


def bundle_sha(proj, place):
    files = bundle_files(proj, place)
    h = hashlib.sha256()   # the dirsha rule of aid-ui-motion.py, over the place's file list
    for rel in files:
        h.update(rel.replace(os.sep, "/").encode() + b"\0" + sha_file(os.path.join(proj, rel)).encode() + b"\n")
    return h.hexdigest()


def bundle_directions(proj, place):
    files = bundle_files(proj, place)
    if place == "logo":
        return sorted({os.path.splitext(os.path.basename(f))[0] for f in files if f.startswith(".aid-ui/logo/cards/")})
    if place in ("pohyb", "vzhled"):
        base = ".aid-ui/motion/" if place == "pohyb" else ".aid-ui/directions/"
        return sorted({f[len(base):].split("/")[0] for f in files if f.startswith(base)})
    return ["main"]


def place_state(proj):
    try:
        return json.load(open(os.path.join(proj, "docs/design/brand-state.json"), encoding="utf-8")).get("place_verdicts") or {}
    except (OSError, ValueError):
        return {}


# ---------------------------------------------------------------- the place verdict

def fixed_and_seen(proj, place, n):
    """{finding id}: the findings of round n of the place that were accepted and fixed (evidence) and whose fix the
    independent verifier saw (verdict overeno) over the place's version now - a fact a role found stops returning the
    place only then (run 5, 22. 10. 2026: every round found a new sample-number nit and the place never closed)."""
    import aid_ui_memory as memory
    try:
        rnd = json.load(open(os.path.join(critic_dir(proj), "rounds", place, str(n), "round.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    fixed = {f["id"] for f in rnd.get("findings") or [] if f.get("state") == "accepted" and f.get("evidence")}
    seen = {k for r in memory.verify_records(proj, place, bundle_sha(proj, place)) if r.get("round") == n
            for k, v in (r.get("fixes") or {}).items() if isinstance(v, dict) and v.get("verdict") == "overeno"}
    return fixed & seen


def decide(proj, place, scores, pm_choice=None, reason=None, pm_veto=None, supplied=False, resolved=None, rnd=None):
    expect = {(r, k) for r in ROLES for k in (place,) + EXTRA.get(place, ())}
    have = {(s["role"], x["rubric"]) for s in scores for x in s["directions"]}
    sets = {(s["role"], x["rubric"]): None for s in scores for x in s["directions"]}
    for s in scores:
        for k in {x["rubric"] for x in s["directions"]}:
            sets[(s["role"], k)] = sorted(x["direction"] for x in s["directions"] if x["rubric"] == k)
    want_dirs = bundle_directions(proj, place)
    bad = {"%s/%s" % k: v for k, v in sets.items() if v != want_dirs}
    if bad:
        die(f"incomplete_place: every role rates every direction of the {place} bundle {want_dirs}; got {bad}")
    if any(s.get("place") != place for s in scores) or len({s["role"] for s in scores}) != len(scores):
        die(f"incomplete_place: one score per role of place {place} (got {[(s.get('role'), s.get('place')) for s in scores]})")
    if have != expect:
        die(f"incomplete_place: {place} needs every score {sorted(expect)}; missing {sorted(expect - have)}")
    dirs = sorted({x["direction"] for s in scores for x in s["directions"]})
    if supplied and len(dirs) != 1:
        die("--supplied rates the one mark the PM supplied; the scores rate %d directions" % len(dirs))
    blocked, out = [], {}
    seen = set()
    for s in scores:   # facts and law first (D5); both roles reporting one fact count once
        for f in s["findings"]:
            if f.get("kind") in ("fakt", "zakon") and ({f"r{rnd}-{s['role']}-{f['id']}", f["id"]} & (resolved or set())):
                continue   # fixed, and the verifier saw the fix in the version now
            if f.get("kind") in ("fakt", "zakon"):
                key = (f["kind"], f.get("direction"), re.sub(r"\W+", " ", (f.get("text") or "").lower()).strip())   # the roles' criteria differ
                if key in seen:
                    continue
                seen.add(key)
                blocked.append({"kind": f["kind"], "role": s["role"], "finding": f["id"], "direction": f.get("direction"), "text": f.get("text")})
                if f.get("direction"):
                    out.setdefault(f["direction"], "fakt nebo zákon")
            if s["role"] == "tech" and f.get("kind") == "remeslo" and f.get("blocking") is True:
                for d in ([f["direction"]] if f.get("direction") else dirs):
                    out.setdefault(d, "blokující vada řemesla (%s)" % f["id"])
                blocked.append({"kind": "remeslo", "role": "tech", "finding": f["id"], "direction": f.get("direction"), "text": f.get("text")})
        for x in s["directions"]:
            if x["status"] == "failed":
                out.setdefault(x["direction"], "%s nesplnil brány (%s)" % (s["role"], x["rubric"]))
    general_fact = [b for b in blocked if b["kind"] in ("fakt", "zakon") and not b.get("direction")]
    passing = [d for d in dirs if d not in out]
    owner = next(s for s in scores if s["role"] == "owner")
    client_pick = owner.get("choice") or (dirs[0] if len(dirs) == 1 else None)
    if pm_choice:
        if not (reason or "").strip():
            die("--pm-choice needs --reason (manual mode: the PM chooses, the client's pick is kept)", 2)
        chosen, by = pm_choice, "pm"
    elif supplied:
        chosen, by = dirs[0], "pm"
    else:
        chosen, by = client_pick, "client"
    if chosen is None and passing:
        best = {x["direction"]: x["weighted"] for x in owner["directions"] if x["rubric"] == place and x["direction"] in passing}
        chosen = max(passing, key=lambda d: (best.get(d, 0), d))
    status = "returned"
    if pm_veto:
        blocked.append({"kind": "veto", "role": "pm", "finding": None, "text": pm_veto})
    elif general_fact or not passing:
        pass
    elif chosen not in passing:
        if by == "client" and not supplied:
            print(json.dumps({"place": place, "error": "client_choice_failed", "chosen": chosen, "why": out.get(chosen, "není směr místa"),
                              "passing": passing}, ensure_ascii=False))
            sys.exit(3)
        blocked.append({"kind": "choice", "role": by, "finding": None, "direction": chosen, "text": out.get(chosen, "není směr místa")})
    else:
        mine = [x for s in scores for x in s["directions"] if x["direction"] == chosen]
        status = "accepted_with_reservation" if any(x["status"] == "reservation" for x in mine) else "accepted"
    st = place_state(proj)
    v = {"place": place, "status": status, "chosen": chosen if status != "returned" or chosen in dirs else None, "chosen_by": by,
         "client_choice": client_pick, "passing": passing, "out": out, "blocked_by": blocked,
         "answers": {s["role"]: s.get("answer_sha256") for s in scores},
         "scores": [hashlib.sha256(json.dumps(s, sort_keys=True, ensure_ascii=False).encode()).hexdigest() for s in scores],
         "target": bundle_sha(proj, place),
         "upstream": {u: (st.get(u) or {}).get("target") for u in UPSTREAM[place]},
         "options": {"pm_choice": pm_choice, "reason": reason, "pm_veto": pm_veto, "supplied": bool(supplied)},
         "supplied": bool(supplied), "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if pm_veto:
        v["pm_veto"] = pm_veto
    return v


def last_round(proj, place):
    d = rounds_dir(proj, place)
    ns = sorted(int(x) for x in os.listdir(d) if x.isdigit()) if os.path.isdir(d) else []
    ns = [n for n in ns if not (json.load(open(os.path.join(d, str(n), "round.json"), encoding="utf-8")) if os.path.isfile(os.path.join(d, str(n), "round.json")) else {}).get("audit")]
    if not ns:
        die(f"place_verdict_handmade: no round of place {place} in {d} (a verdict comes from the place's last round)")
    return os.path.join(d, str(ns[-1]))


def place_check(proj, place, vfile):
    try:
        v = json.load(open(vfile, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"{vfile}: not readable JSON ({e})")
    if v.get("place") != place:
        die(f"the verdict is of place {v.get('place')}, not {place}")
    rd = last_round(proj, place)
    rnd = json.load(open(os.path.join(rd, "round.json"), encoding="utf-8"))
    scores = []
    for r in ROLES:
        a = os.path.join(rd, r, "answer.json")
        if not os.path.isfile(a):
            die(f"place_verdict_handmade: the last round {rd} has no answer of {r}")
        if (rnd.get("answers") or {}).get(r) != sha_file(a):   # the rating the round recorded, not a file edited since
            die(f"place_verdict_handmade: {r}'s answer of round {rnd.get('n')} is not the one the round recorded")
        scores.append(scored(proj, place, r, a))
    o = v.get("options") or {}
    n = rnd.get("n")   # the last round's facts that were fixed and that the verifier saw no longer return it (as place-verdict --fixed-in)
    again = decide(proj, place, scores, o.get("pm_choice"), o.get("reason"), o.get("pm_veto"), o.get("supplied"), fixed_and_seen(proj, place, n), n)
    for k in ("status", "chosen", "chosen_by", "answers", "scores", "target"):
        if again[k] != v.get(k):
            die(f"place_verdict_handmade: {k} of the verdict ({v.get(k)}) is not what the place's last round gives ({again[k]})"
                if k != "target" else "place_verdict_handmade: the verdict is over an older bundle (target %s, now %s)" % (str(v.get(k))[:12], again[k][:12]))
    print(json.dumps(again, ensure_ascii=False))


def place_guard(proj, place):
    """What aid-ui-state.sh checks before an accepting answer of the place's question (or build-record for pohyb):
    a current accepted verdict of the place, standing on the CURRENT bundles of its upstream places."""
    st = place_state(proj)
    why = skipped_place(proj, place)
    if why:
        print(f"PLACE {place}: N/A pro aplikaci ({why})")
        return
    v = st.get(place)
    if not v:
        die(f"place_verdict_missing: place {LABEL[place]} ({place}) has no verdict; rate it (aid-ui-quality.py round --place {place}),"
            f" decide it (aid-ui-critic.py place-verdict) and record it (aid-ui-state.sh place-record)")
    if v.get("status") not in ("accepted", "accepted_with_reservation"):
        die(f"place_verdict_missing: place {place} is {v.get('status')} ({'; '.join(str(b.get('text')) for b in v.get('blocked_by') or [])[:300]})")
    cur = bundle_sha(proj, place)
    if v.get("target") != cur:
        die(f"place_verdict_missing: place {place} was decided over another bundle (verdict {str(v.get('target'))[:12]}, now {cur[:12]}); rate it again")
    for u in [x for x in UPSTREAM[place] if not skipped_place(proj, x)]:
        uv = st.get(u) or {}
        if uv.get("status") not in ("accepted", "accepted_with_reservation"):
            die(f"place_verdict_missing: place {place} stands on {u}, which has no accepted verdict")
        now_u = bundle_sha(proj, u)
        if uv.get("target") != now_u:
            die(f"place_verdict_missing: place {u} changed after its verdict (verdict {str(uv.get('target'))[:12]}, now {now_u[:12]}); rate {u} again, then {place}")
        if (v.get("upstream") or {}).get(u) != now_u:
            die(f"place_verdict_missing: place {place} was decided over another {u} ({str((v.get('upstream') or {}).get(u))[:12]}, now {now_u[:12]}); rate {place} again")
    print(f"PLACE {place}: {v['status']} ({v.get('chosen')})")


def place_without(proj, qid, reason):
    """No motion in this project: the PM's recorded exception answer (target pohyb@without, checked and consumed by
    aid-ui-state.sh) becomes the motion place's record, and that record is the place's bundle."""
    rel = ".aid-ui/critic/pohyb-without.json"
    os.makedirs(os.path.join(proj, os.path.dirname(rel)), exist_ok=True)
    with open(os.path.join(proj, rel), "w", encoding="utf-8") as f:
        json.dump({"answer": qid, "reason": reason, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}, f, ensure_ascii=False)
    h = hashlib.sha256()
    h.update(rel.encode() + b"\0" + sha_file(os.path.join(proj, rel)).encode() + b"\n")
    st = place_state(proj)
    print(json.dumps({"place": "pohyb", "status": "accepted", "without": qid, "chosen": None, "chosen_by": "pm", "blocked_by": [],
                      "target": h.hexdigest(), "upstream": {u: (st.get(u) or {}).get("target") for u in UPSTREAM["pohyb"]},
                      "reason": reason, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}, ensure_ascii=False))


# ---------------------------------------------------------------- command line

def main(a):
    if not a:
        die("usage: freeze|prompt|score|verdict|place-verdict|place-check|bundle-files|bundle-sha (see the header)", 2)
    cmd = a[0]
    opt = lambda k: a[a.index(k) + 1] if k in a and a.index(k) + 1 < len(a) else None
    place = place_of(a)
    role = opt("--role")
    pos = []
    i = 1
    while i < len(a):
        if a[i] in ("--role", "--place", "--type", "--phase", "--metrics-dir", "--score", "--pm-choice", "--reason", "--pm-veto", "--fixed-in"):
            i += 2
        elif a[i] in ("--force", "--supplied"):
            i += 1
        else:
            pos.append(a[i]); i += 1
    if cmd in ("prompt", "score", "verdict") and not role:
        die("--role owner|tech", 2)
    if cmd == "freeze" and pos and opt("--type"):
        return freeze(os.path.abspath(pos[0]), opt("--type"), "--force" in a, opt("--phase") or "build", place)
    if cmd == "prompt" and len(pos) == 1:
        print(of_role(frozen(os.path.abspath(pos[0]), place), role)["role"])
        return
    if cmd == "score" and len(pos) == 2:
        print(json.dumps(scored(os.path.abspath(pos[0]), place, role, pos[1], opt("--metrics-dir")), ensure_ascii=False))
        return
    if cmd == "verdict" and len(pos) >= 2:
        proj = os.path.abspath(pos[0])
        if len(pos) - 1 != RATINGS:
            die(f"the closing verdict takes exactly {RATINGS} blind ratings, got {len(pos) - 1}")
        rec = of_role(frozen(proj, place), role)
        au = (rec["gates"][place].get("audit") or {})
        if not all(k in au for k in ("median_min", "any_min", "criterion_median_min")):
            die(f"the gate file of {place} ({role}) has no audit block (median_min, any_min, criterion_median_min)", 2)
        runs = [scored(proj, place, role, p) for p in pos[1:]]
        med = statistics.median(r["quality_score"] for r in runs)
        ids = sorted({k for r in runs for k in r["criteria"]})
        crit = {k: statistics.median([r["criteria"][k] for r in runs if k in r["criteria"]]) for k in ids}
        low = min(r["quality_score"] for r in runs)
        extra = all(x["status"] != "failed" for r in runs for x in r["directions"] if x["rubric"] != place)   # the other places' rubrics at web
        ok = med >= au["median_min"] and low >= au["any_min"] and (min(crit.values()) if crit else 0) >= au["criterion_median_min"] and extra
        ready = sorted({i for r in runs for i in r["readiness"]})
        text = ("přijato" + (", zveřejnění blokuje: " + "; ".join(ready) if ready else ", připraveno ke zveřejnění")) if ok else "nepřijato"
        print(json.dumps({"role": role, "place": place, "ratings": len(runs), "median_quality_score": med,
                          "median_quality_now": statistics.median(r["quality_now"] for r in runs), "lowest_rating": low, "criteria_median": crit,
                          "other_rubrics_ok": extra, "accepted": ok, "publish_blocked_by": ready, "verdict": text}, ensure_ascii=False))
        sys.exit(0 if ok else 3)
    if cmd == "place-verdict" and len(pos) == 1 and "--place" in a:
        files = [a[j + 1] for j in range(len(a) - 1) if a[j] == "--score"]
        scores = []
        for f in files:
            try:
                scores.append(json.load(open(f, encoding="utf-8")))
            except (OSError, ValueError) as e:
                die(f"{f}: not readable JSON ({e})")
        rn = opt("--fixed-in")   # the round whose fixed and verified facts no longer return the place
        res = fixed_and_seen(os.path.abspath(pos[0]), place, int(rn)) if rn and rn.isdigit() else set()
        print(json.dumps(decide(os.path.abspath(pos[0]), place, scores, opt("--pm-choice"), opt("--reason"), opt("--pm-veto"), "--supplied" in a,
                                res, int(rn) if rn and rn.isdigit() else None), ensure_ascii=False))
        return
    if cmd == "place-check" and len(pos) == 2 and "--place" in a:
        return place_check(os.path.abspath(pos[0]), place, pos[1])
    if cmd in ("bundle-files", "bundle-sha") and len(pos) == 1:
        proj = os.path.abspath(pos[0])
        print("\n".join(bundle_files(proj, place)) if cmd == "bundle-files" else bundle_sha(proj, place))
        return
    if cmd == "place-without" and len(pos) == 3:
        return place_without(os.path.abspath(pos[0]), pos[1], pos[2])
    if cmd == "place-guard" and len(pos) == 1 and "--place" in a:
        return place_guard(os.path.abspath(pos[0]), place)
    if cmd == "bundle-directions" and len(pos) == 1:
        print(json.dumps(bundle_directions(os.path.abspath(pos[0]), place)))
        return
    die("usage: freeze <project> --type <type> [--place p] [--force] | prompt|score|verdict <project> --role owner|tech [--place p] [<answer.json>...]"
        " | place-verdict <project> --place p --score <s.json>... | place-check <project> --place p <verdict.json> | bundle-files|bundle-sha <project> --place p", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
