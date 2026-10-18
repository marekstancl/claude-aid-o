#!/usr/bin/env python3
"""aid-ui-package.py - the handover package between the /aid-ui studio and plan/run (P115).

The studio ends with one package, docs/ui/predani.json (+ the readable predani.md, never read by code), in the shape
of skills/ui-design/references/handover-package.schema.json (version 1). The package is never edited after the
handover: the deployment writes its own docs/ui/nasazeni.json.

  build <project> [--dry]
      Reads docs/design/brand-state.json (.gate, .build, .open_items, .place_verdicts, .handover, .chapters),
      .aid-ui/launch.json (aid-ui-launch.py), docs/content/tasks.yaml and the type's launch_only
      (skills/ui-design/critic/<type>.yaml) and writes the package atomically. Refused (exit 1, nothing written) with
      `package: chybí <part>` or `package: zastaralý (<what changed>)`: no recorded gate or a gate without its checked
      customer page; the site's build id now differs from the recorded build or from the gate's build_id; the gate's
      result file or the customer page changed since gate-record; no chapter to hand over. --dry: every check, nothing
      written (aid-ui-state.sh chapter-all runs it before the PM's answer is used; chapters in navrh or schvaleno).
      Without --dry the handover must be recorded (.handover, not vratit) and the chapters are the schvaleno ones;
      run alone it rewrites the package of a recorded handover (a retry after a write failure).
  check <package> [--project <dir>]
      The package against the schema; with --project also against the project now: stale when the site's build id
      or dirsha, the recorded gate (run_at, result sha, build id) or the customer page differ. Exit 0, or 1 and why.
  zadani <package> --plan-id P<NNN> [--out <file>]
      The deployment brief in the six sections of defaults/templates/zadani.md, written to
      <project>/.aid-o/plans/P<NNN>-zadani.md (project = the directory holding docs/ui/predani.json) or --out.
      Points of "done", each with owner (run|client|pm), whether it blocks the launch and a verification_pattern:
      one per customer task; one per launch input of the package that no open item carries (an input the client's
      confirmation turned into an open item is that item's point, never twice); the rows of
      skills/ui-design/references/local/spusteni.md but the launch rating (deploy exactly the package, https,
      headers, 404, sensitive files, DNS, catalogues, redirects of the inventory); one per open item (critical ones
      block); the launch rating last. Frontmatter ui_package + ui_package_sha256: the plan must carry them
      (aid-plan-lint.sh ui_package_lost) and the run gate check_ui_handover reads them. Refused (exit 1, nothing written):
      the package fails check (against the project when it has docs/design/brand-state.json); the project's
      .aid-o/config/execution.yaml does not define the gate check_ui_handover or a profile lacks it ("spusť /aid-init");
      the brief file exists; the written brief fails aid-plan-lint.sh --zadani (it is removed, the lint's lines shown).

Exit: 0 ok, 1 refused, 2 usage.
"""
import datetime, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "ui-design")
SCHEMA = os.path.join(SKILL, "references", "handover-package.schema.json")
STATE_SH = os.path.join(HERE, "aid-ui-state.sh")
CHAPTERS = "produkt podklady vize logo barvy typografie smer komponenty platformy ukazky seo struktura obsah kvalita schvaleni".split()


class Refused(Exception):
    pass


def die(msg, code=1):
    print("ERROR: aid-ui-package.py: " + msg, file=sys.stderr)
    sys.exit(code)


def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def site_files(d):
    """Every file of the site (symlinks skipped, as the dirsha rule does), sorted by path."""
    out = []
    for root, dirs, files in os.walk(d):
        dirs.sort()
        for fn in sorted(files):
            p = os.path.join(root, fn)
            if not os.path.islink(p):
                out.append({"path": os.path.relpath(p, d).replace(os.sep, "/"), "sha256": sha_file(p)})
    return out


def run(*cmd):
    r = subprocess.run(list(cmd), capture_output=True, text=True)
    if r.returncode != 0:
        raise Refused((r.stderr or r.stdout).strip().splitlines()[-1] if (r.stderr or r.stdout).strip() else " ".join(cmd))
    return r.stdout.strip()


def dirsha(d):
    return run(sys.executable, os.path.join(HERE, "aid-ui-motion.py"), "dirsha", d)


def build_id(d):
    return run("bash", STATE_SH, "build-id", d)


def yaml_json(path):
    r = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise Refused(f"chybí {os.path.basename(path)} (nečitelný: {r.stderr.strip()[:200]})")
    return json.loads(r.stdout or "null")


def load_json(p, what):
    try:
        return json.load(open(p, encoding="utf-8"))
    except FileNotFoundError:
        raise Refused(f"chybí {what}")
    except ValueError as e:
        raise Refused(f"chybí {what} (nečitelný JSON: {e})")


def stale_reasons(proj, state, site_dir, bid):
    """What changed between the recorded gate and the project now (empty = current)."""
    why = []
    g = state.get("gate") or {}
    b = state.get("build") or {}
    if b.get("id") != bid:
        why.append(f"web se změnil od build-record (build id {bid[:12]}, zaznamenaný {str(b.get('id'))[:12]})")
    if g.get("build_id") != bid:
        why.append(f"brána běžela nad jiným webem (build id brány {str(g.get('build_id'))[:12]}, web teď {bid[:12]})")
    res = g.get("result_file") or ""
    if not os.path.isfile(res) or sha_file(res) != g.get("result_sha256"):
        why.append(f"výsledek brány {res} chybí nebo se změnil od gate-record")
    page = os.path.join(proj, "docs", "zakaznik", "index.html")
    if not os.path.isfile(page) or sha_file(page) != g.get("customer_page_sha256"):
        why.append("docs/zakaznik/index.html chybí nebo není stránka, nad kterou brána běžela")
    return why


def chapter_target(proj, cid):
    return run("bash", STATE_SH, "chapter-target", proj, cid)


def launch_only_of(proj, launch):
    typ = (launch or {}).get("type")
    if not typ:
        fr = os.path.join(proj, ".aid-ui", "critic", "frozen.json")
        if os.path.isfile(fr):
            typ = (load_json(fr, ".aid-ui/critic/frozen.json") or {}).get("type")
    if not typ:
        return []
    f = os.path.join(SKILL, "critic", typ + ".yaml")
    if not os.path.isfile(f):
        return []
    lo = (yaml_json(f) or {}).get("launch_only") or {}
    return sorted(f"{role}.{c}" for role, cs in lo.items() for c in (cs or []))


def handover_of(state):
    hv = state.get("handover") or {}
    a = (state.get("answers") or {}).get(hv.get("answer") or "") or {}
    return {"verdict": hv.get("verdict"), "rating": hv.get("rating"), "answer": hv.get("answer"), "comment": a.get("comment") or ""}


def make(proj, dry):
    proj = os.path.realpath(proj)
    state = load_json(os.path.join(proj, "docs", "design", "brand-state.json"), "docs/design/brand-state.json")
    g = state.get("gate") or {}
    for k in ("run_at", "result_file", "result_sha256", "build_id", "customer_page_sha256"):
        if not g.get(k):
            raise Refused(f"chybí brána (gate.{k}); převzetí přichází po poslední bráně a gate-record")
    if g.get("customer_page") != "pass":
        raise Refused("chybí zkontrolovaná stránka zákazníka (gate.customer_page)")
    site_dir = (state.get("build") or {}).get("dir") or ""
    if not os.path.isdir(site_dir):
        raise Refused(f"chybí web (build.dir {site_dir or '-'})")
    bid = build_id(site_dir)
    why = stale_reasons(proj, state, site_dir, bid)
    if why:
        raise Refused("zastaralý (" + "; ".join(why) + ")")
    if not dry:
        hv = (state.get("handover") or {}).get("verdict")
        if not hv:
            raise Refused("chybí převzetí (handover); balík píše chapter-all")
        if hv == "vratit":
            raise Refused("chybí převzetí (PM web vrátil)")
    ok = ("navrh", "schvaleno") if dry else ("schvaleno",)
    ids = [c for c in CHAPTERS if ((state.get("chapters") or {}).get(c) or {}).get("status") in ok]
    if not ids:
        raise Refused("chybí kapitoly (žádná ke schválení)")
    chapters = [{"id": c, "target": chapter_target(proj, c)} for c in ids]
    places = [{"place": k, "status": v.get("status") or "", "target": v.get("chosen")}
              for k, v in sorted((state.get("place_verdicts") or {}).items()) if isinstance(v, dict)]
    tf = os.path.join(proj, "docs", "content", "tasks.yaml")
    tasks = []
    for t in (yaml_json(tf) if os.path.isfile(tf) else None) or []:
        if not isinstance(t, dict) or not t.get("id") or not (t.get("task") or t.get("text")):
            raise Refused(f"chybí úkol zákazníka v docs/content/tasks.yaml (položka bez id nebo textu: {json.dumps(t, ensure_ascii=False)[:120]})")
        x = {"id": str(t["id"]), "text": str(t.get("task") or t.get("text")), "page": t.get("page")}
        if "form" in t:
            x["form"] = bool(t["form"])
        tasks.append(x)
    ois = []
    for o in state.get("open_items") or []:
        miss = [k for k in ("id", "text", "owner", "status") if not (isinstance(o, dict) and str(o.get(k) or "").strip())]
        if miss:
            raise Refused(f"chybí {', '.join(miss)} otevřeného bodu {json.dumps(o, ensure_ascii=False)[:120]}")
        ois.append({"id": o["id"], "text": o["text"], "owner": o["owner"], "due": o.get("due"),
                    "critical": bool(o.get("critical")), "status": o["status"], "evidence": o.get("evidence")})
    lf = os.path.join(proj, ".aid-ui", "launch.json")
    launch = load_json(lf, ".aid-ui/launch.json") if os.path.isfile(lf) else {}
    inputs = [dict(i, critical=bool(i.get("critical"))) for i in (launch.get("items") or []) if isinstance(i, dict)]
    return {
        "version": 1,
        "project": os.path.basename(proj),
        "created_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "site": {"dir": site_dir, "build_id": bid, "sha256": dirsha(site_dir), "files": site_files(site_dir)},
        "gate": {k: g[k] for k in ("run_at", "result_file", "result_sha256", "build_id", "customer_page", "customer_page_sha256")},
        "chapters": chapters,
        "places": places,
        "customer_tasks": tasks,
        "open_items": ois,
        "launch_inputs": inputs,
        "launch_only": launch_only_of(proj, launch),
    } | ({} if dry else {"handover": handover_of(state)})


def schema_errors(pkg):
    from jsonschema.validators import Draft202012Validator
    v = Draft202012Validator(json.load(open(SCHEMA, encoding="utf-8")))
    return ["/".join(str(x) for x in e.absolute_path) + ": " + e.message for e in v.iter_errors(pkg)]


def markdown(pkg):
    L = [f"# Předání webu {pkg['project']}", "",
         f"Vytvořeno {pkg['created_at']} při převzetí ve studiu /aid-ui. Kód čte jen `predani.json`; tenhle soubor je pro lidi.", "",
         "## Web", "", f"- složka: `{pkg['site']['dir']}`", f"- souborů: {len(pkg['site']['files'])}, otisk `{pkg['site']['sha256'][:16]}…`",
         f"- brána: {pkg['gate']['run_at']}", "", "## Schválené kapitoly", ""]
    L += [f"- {c['id']}" for c in pkg["chapters"]]
    L += ["", "## Místa rozhodnutí", ""] + ([f"- {p['place']}: {p['status']}" for p in pkg["places"]] or ["- žádná (studio před P113)"])
    L += ["", "## Úkoly zákazníka", ""] + ([f"- {t['id']}: {t['text']}" for t in pkg["customer_tasks"]] or ["- žádné"])
    L += ["", "## Otevřené body", ""] + ([f"- {o['id']} ({o['owner']}{', kritický' if o['critical'] else ''}, {o['status']}): {o['text']}"
                                          for o in pkg["open_items"]] or ["- žádné"])
    L += ["", "## Podklady ke spuštění", ""] + ([f"- {i['id']}: {i['name']} ({i['status']})" for i in pkg["launch_inputs"]] or ["- žádné"])
    L += ["", "## Hodnotí se až po nasazení", ""] + ([f"- {x}" for x in pkg["launch_only"]] or ["- nic"])
    return "\n".join(L) + "\n"


def write_pair(files):
    """Both files written to .part first, then renamed: a write failure leaves the previous pair."""
    for path, text in files:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".part", "w", encoding="utf-8") as f:
            f.write(text)
    for path, _ in files:
        os.replace(path + ".part", path)


def cmd_build(proj, dry):
    try:
        pkg = make(proj, dry)
    except Refused as e:
        die("package: " + str(e))
    errs = schema_errors(pkg)
    if errs:
        die("package: chybí " + "; ".join(errs[:5]))
    if dry:
        print(f"PACKAGE OK (--dry, nic nezapsáno): {len(pkg['site']['files'])} souborů, {len(pkg['chapters'])} kapitol")
        return 0
    out = os.path.join(os.path.realpath(proj), "docs", "ui", "predani.json")
    write_pair([(out[:-5] + ".md", markdown(pkg)), (out, json.dumps(pkg, ensure_ascii=False, indent=1) + "\n")])
    print(f"PACKAGE: {out} ({len(pkg['site']['files'])} souborů, sha256 {sha_file(out)})")
    return 0


def check(path, proj=None):
    """Reasons the package is not valid (empty = valid)."""
    try:
        pkg = load_json(path, path)
    except Refused as e:
        return [str(e)]
    errs = schema_errors(pkg)
    if errs:
        return errs
    paths = [f["path"] for f in pkg["site"]["files"]]
    bad = [x for x in paths if x.startswith("/") or "\\" in x or ".." in x.split("/") or "" in x.split("/")]
    if bad or len(set(paths)) != len(paths):
        return [f"site.files: nebezpečná nebo opakovaná cesta {(bad or sorted(x for x in paths if paths.count(x) > 1))[0]}"]
    if not proj:
        return []
    try:
        state = load_json(os.path.join(proj, "docs", "design", "brand-state.json"), "docs/design/brand-state.json")
        d = pkg["site"]["dir"]
        if not os.path.isdir(d):
            return [f"zastaralý (web {d} chybí)"]
        bid = build_id(d)
        why = stale_reasons(os.path.realpath(proj), state, d, bid)
        if bid != pkg["site"]["build_id"] or dirsha(d) != pkg["site"]["sha256"] or site_files(d) != pkg["site"]["files"]:
            why.append("web se změnil od předání (soubory nejsou ty z balíku)")
        g = state.get("gate") or {}
        if any(g.get(k) != pkg["gate"][k] for k in ("run_at", "result_sha256", "build_id", "customer_page_sha256")):
            why.append("zaznamenaná brána není ta z předání")
        return ["zastaralý (" + "; ".join(why) + ")"] if why else []
    except Refused as e:
        return [str(e)]


LAUNCH_TABLE = os.path.join(SKILL, "references", "local", "spusteni.md")
OWNER = {"klient": "client", "PM": "pm", "agent": "run"}


def q(cmd):
    """A YAML double-quoted scalar of one line (the verification grammar unescapes \\" and \\\\ only)."""
    return '"' + cmd.replace("\\", "\\\\").replace('"', '\\"') + '"'


def launch_rows():
    rows = []
    for line in open(LAUNCH_TABLE, encoding="utf-8"):
        if not line.startswith("| ") or line.startswith("| id ") or line.startswith("|---"):
            continue
        cells = [c.strip().replace("\\|", "|") for c in __import__("re").split(r"(?<!\\)\|", line.strip())[1:-1]]
        if len(cells) != 5:
            die(f"{LAUNCH_TABLE}: a row needs 5 cells: {line.strip()[:80]}")
        rid, what, owner, blocks, ver = cells
        rows.append({"id": rid, "text": what, "owner": owner, "blocks": blocks == "ano", "cmd": ver.strip("`")})
    return rows


def redirect_note(proj):
    rf = os.path.join(proj, ".aid-ui", "skeleton", "redirects.csv")
    n = sum(1 for _ in open(rf, encoding="utf-8")) - 1 if os.path.isfile(rf) else 0
    return f"{n} starých adres" if n > 0 else "bez starého webu"


def live_url(proj):
    """The url of docs/ui/nasazeni.json, or exit 1 naming why."""
    try:
        u = json.load(open(os.path.join(proj, "docs", "ui", "nasazeni.json"), encoding="utf-8")).get("url") or ""
    except (OSError, ValueError) as e:
        die(f"no readable docs/ui/nasazeni.json ({e})")
    if not re.fullmatch(r"https?://[^\s/]+(/\S*)?", u):
        die(f"docs/ui/nasazeni.json url is not an http(s) address: {u!r}")
    return u.rstrip("/")


def cmd_live_redirects(csv_path):
    """Every row of the inventory's redirects.csv answers 301/302/307/308 on the live address with Location = its
    target; no file or no rows = no old site, exit 0. Run from the project root."""
    import csv, http.client, urllib.parse
    if not os.path.isfile(csv_path) or os.path.getsize(csv_path) == 0:
        print("redirects: bez starého webu")
        return 0
    base = urllib.parse.urlsplit(live_url("."))
    bad, n = [], 0
    for r in csv.DictReader(open(csv_path, encoding="utf-8")):
        n += 1
        f = urllib.parse.urlsplit(r.get("from") or "")
        path = (base.path.rstrip("/") + (f.path or "/")) + ("?" + f.query if f.query else "")
        conn = (http.client.HTTPSConnection if base.scheme == "https" else http.client.HTTPConnection)(base.netloc, timeout=20)
        try:
            conn.request("GET", path)
            resp = conn.getresponse()
            status, raw = resp.status, resp.getheader("Location") or ""
        except OSError as e:
            bad.append(f"{path}: {e}")
            continue
        finally:
            conn.close()
        loc = urllib.parse.urlsplit(raw)
        if status not in (301, 302, 307, 308) or (loc.netloc and loc.netloc != base.netloc) or loc.path.rstrip("/") != (base.path.rstrip("/") + (r.get("to") or "")).rstrip("/"):
            bad.append(f"{path}: {status} -> {raw!r}, want {r.get('to')!r}")
    if bad:
        die("redirects: " + "; ".join(bad))
    print(f"redirects: {n} OK")
    return 0


def gate_in_project(proj):
    ex = os.path.join(proj, ".aid-o", "config", "execution.yaml")
    if not os.path.isfile(ex):
        return f"projekt nemá {ex}; spusť /aid-init (vytvoří ho i s bránou check_ui_handover)"
    d = yaml_json(ex) or {}
    if not isinstance((d.get("gates") or {}).get("check_ui_handover"), dict):
        return "execution.yaml projektu nemá bránu check_ui_handover; spusť /aid-init, upgrade ji přidá"
    profs = d.get("gate_profiles") or {}
    lack = [n for n, pr in profs.items() if "check_ui_handover" not in ((pr or {}).get("include") or [])] if isinstance(profs, dict) else ["gate_profiles"]
    if not profs or lack:
        return f"profily bran bez check_ui_handover ({', '.join(lack) or 'žádný profil'}); spusť /aid-init, upgrade bránu doplní"
    return ""


def points(pkg, proj, brief_rel):
    plugin = os.path.realpath(os.path.join(HERE, ".."))
    sub = lambda c: c.replace("@PLUGIN@", plugin).replace("@BRIEF@", brief_rel)
    pts = []   # {text, owner, blocks, cmd, timeout?}
    rows = launch_rows()
    for r in rows:
        if r["id"] == "hodnoceni":
            continue
        cmd, text = sub(r["cmd"]), r["text"]
        if r["id"] == "presmerovani":
            text = f"{text}: {redirect_note(proj)}"
        pts.append({"text": text, "owner": r["owner"], "blocks": r["blocks"], "cmd": cmd,
                    "timeout": 900 if r["id"] == "nasadit_balik" else None, "kind": "launch"})
    carried = {o["id"] for o in pkg["open_items"]}
    for i in pkg["launch_inputs"]:
        if i.get("item") in carried:
            continue   # the client's confirmation made it an open item: that item's point
        jq = f'.items[] | select(.id == "{i["id"]}") | .status == "confirmed" or (.item != null)'
        pts.append({"text": f"Podklad ke spuštění „{i['name']}“ potvrzený klientem nebo zapsaný jako otevřený bod (aid-ui-launch.py confirm)",
                    "owner": "client", "blocks": bool(i["critical"]), "cmd": f"jq -e '{jq}' .aid-ui/launch.json", "kind": "launch"})
    for t in pkg["customer_tasks"]:
        pts.append({"text": f"Úkol zákazníka „{t['text']}“ jde na ostré adrese splnit do dvou kroků z úvodu, na počítači i mobilu",
                    "owner": "run", "blocks": True, "kind": "task",
                    "cmd": f"python3 {plugin}/scripts/aid-ui-package.py live-row docs/ui/predani.json task_test --detail '{t['id']} 1440:' --detail '{t['id']} 390:'"})
    links = {i.get("item"): i["name"] for i in pkg["launch_inputs"] if i.get("item")}
    for o in pkg["open_items"]:
        done = '.status == "done"' + (' and ((.done_evidence // "") != "")' if o["critical"] else "")
        src = f" (podklad ke spuštění „{links[o['id']]}“)" if o["id"] in links else ""
        pts.append({"text": f"Otevřený bod {o['id']} uzavřený{' s dokladem' if o['critical'] else ''}: {o['text']}{src}",
                    "owner": OWNER.get(o["owner"], "pm"), "blocks": o["critical"], "kind": "open_item",
                    "cmd": f"jq -e '.open_items[] | select(.id == \"{o['id']}\") | {done}' docs/design/brand-state.json"})
    r = next(x for x in rows if x["id"] == "hodnoceni")
    pts.append({"text": r["text"], "owner": r["owner"], "blocks": r["blocks"], "cmd": sub(r["cmd"]), "kind": "rating"})
    return pts


def one_line(x):
    """Package text inside the brief: one line, so it cannot open a heading, a fence or a criterion."""
    return " ".join(str(x or "").split()).replace("```", "'''")


def brief_text(pkg, pkg_rel, pkg_sha, plan_id, pts):
    today = datetime.date.today().isoformat()
    hv = pkg.get("handover") or {}
    say = one_line(hv.get("comment")) or "(bez komentáře)"
    proj_name = one_line(pkg["project"])
    L = ["---", f"zadani: {plan_id}", "verze: 1", f"datum: {today}", "autor: PM + AI (z předávacího balíku studia)",
         "roadmapa: " + json.dumps(f"nasazení webu {proj_name} po převzetí ve studiu /aid-ui", ensure_ascii=False), f"ui_package: {pkg_rel}", f"ui_package_sha256: {pkg_sha}", "---", "",
         f"# {plan_id} - nasazení webu {proj_name} z předávacího balíku", "", "## 1. Co PM chce", "",
         f"> Převzetí ve studiu {pkg['created_at'][:10]} ({hv.get('verdict') or 'převzato'}{', ' + hv['rating'] + '/10' if hv.get('rating') else ''}): „{say}“",
         "> PM 17. 10. 2026 (P115, 2A): hosting jen jako body plánu nasazení, žádný generátor v pluginu.", "",
         f"Jak jsem to pochopil: nasadit na doménu přesně ten web, který klient ve studiu převzal (balík `{pkg_rel}`), dořešit, co ke "
         "spuštění chybí, a pustit ho, až každý bod níže platí na ostré adrese.", "",
         "**Co je v sázce:** Web na doméně klienta, který není ten převzatý, nebo spuštěný s otevřeným kritickým bodem (IČO, právní "
         "texty, nefunkční formulář), zaplatí klient chybným webem pod svým jménem a PM ruční kontrolou a dalším kolem; zprávy z formuláře, "
         "které nikam nedojdou, jsou ztracení zákazníci.", "", "## 2. Změřený výchozí stav", "",
         f"(z balíku `{pkg_rel}`, sha256 {pkg_sha})", "",
         f"- web: `{pkg['site']['dir']}`, {len(pkg['site']['files'])} souborů, otisk {pkg['site']['sha256']}",
         f"- brána studia: {pkg['gate']['run_at']} nad build id {pkg['site']['build_id']}",
         f"- schválené kapitoly: {', '.join(c['id'] for c in pkg['chapters'])}",
         f"- místa rozhodnutí: {', '.join(p['place'] + ' ' + p['status'] for p in pkg['places']) or 'žádná (studio před P113)'}",
         f"- úkoly zákazníka: {len(pkg['customer_tasks'])}; otevřené body: {len(pkg['open_items'])} (kritických {sum(o['critical'] for o in pkg['open_items'])})",
         f"- hodnotí se až po nasazení: {', '.join(pkg['launch_only']) or 'nic'}", "", "## 3. Co udělat", "",
         "**(1) Nasadit přesně balík.** Soubory webu beze změny na hosting, nic navíc; zapsat `docs/ui/nasazeni.json`.",
         "**(2) Připravit spuštění.** HTTPS, hlavičky, 404, citlivé soubory, DNS, katalogy, přesměrování starých adres (body níže).",
         "**(3) Uzavřít otevřené body a podklady ke spuštění.** Kritické s dokladem.",
         "**(4) Hodnocení po nasazení.** `aid-ui-quality.py launch` nad ostrou adresou.", "",
         "**Co do tohohle zadání nepatří:** změna webu (jiný web = nové převzetí ve studiu a nový balík); generátor konfigurace hostingu.", "",
         "## 4. Kde co je", "", "| Co | Kde |", "|---|---|",
         f"| předávací balík | `{pkg_rel}` (čte ho brána check_ui_handover, nikdy se nemění) |",
         "| záznam nasazení | `docs/ui/nasazeni.json` (`url`, `listing` {type ssh/sftp/local, host, root}) |",
         "| stav studia a otevřené body | `docs/design/brand-state.json` |", "| ruční doklady | `docs/ui/dukazy.md` (řádek `<id>: <doklad>`) |", "",
         "## 5. Pravidla práce", "",
         "- Web se nemění: soubory jdou na hosting tak, jak jsou v balíku (hosting, který je přepisuje, je překážka spuštění).",
         "- Brána běhu `check_ui_handover` hlídá plán z balíku; plán musí nést `ui_package` a `ui_package_sha256` z tohoto zadání.",
         "- Bod s vlastníkem client nebo pm čeká na doklad od něj; agent ho nevyplňuje sám.", "", "## 6. Hotovo, když", ""]
    for n, p in enumerate(pts, 1):
        L.append(f"- [ ] AC{n}: {one_line(p['text'])} (vlastník: {p['owner']}; {'blokuje spuštění' if p['blocks'] else 'neblokuje spuštění'})")
        L += ["  ```yaml", "  verification_pattern:", "    type: cmd", f"    cmd: {q(p['cmd'])}", "    expected_exit: 0"]
        if p.get("timeout"):
            L.append(f"    timeout: {p['timeout']}")
        L.append("  ```")
    return "\n".join(L) + "\n"


def cmd_zadani(pkg_path, plan_id, out):
    import re
    if not re.fullmatch(r"P[0-9]{3,}", plan_id or ""):
        die("zadani needs --plan-id P<NNN>", 2)
    pkg_path = os.path.realpath(pkg_path)
    proj = os.path.dirname(os.path.dirname(os.path.dirname(pkg_path)))
    has_state = os.path.isfile(os.path.join(proj, "docs", "design", "brand-state.json"))
    why = check(pkg_path, proj if has_state else None)
    if why:
        die("zadani refused: package: " + "; ".join(why))
    g = gate_in_project(proj)
    if g:
        die("zadani refused: " + g)
    out = os.path.realpath(out) if out else os.path.join(proj, ".aid-o", "plans", f"{plan_id}-zadani.md")
    if os.path.exists(out):
        die(f"zadani refused: {out} exists; name another file with --out")
    pkg = json.load(open(pkg_path, encoding="utf-8"))
    rel = lambda x: os.path.relpath(x, proj)
    pts = points(pkg, proj, rel(out))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write_pair([(out, brief_text(pkg, rel(pkg_path), sha_file(pkg_path), plan_id, pts))])
    r = subprocess.run(["bash", os.path.join(HERE, "aid-plan-lint.sh"), "--zadani", out], capture_output=True, text=True)
    if r.returncode != 0:
        os.remove(out)
        die("zadani refused: the brief fails aid-plan-lint.sh --zadani (removed):\n" + (r.stdout + r.stderr).strip())
    kinds = {k: sum(p["kind"] == k for p in pts) for k in ("task", "launch", "open_item", "rating")}
    print(f"ZADANI: {out} ({len(pts)} bodů: úkoly {kinds['task']}, spuštění {kinds['launch']}, otevřené body {kinds['open_item']}, hodnocení {kinds['rating']})")
    return 0


def main(a):
    if not a:
        die("usage: aid-ui-package.py build <project> [--dry] | check <package> [--project <dir>] | zadani <package> --plan-id P<NNN> [--out <file>]", 2)
    cmd = a[0]
    if cmd == "build" and len(a) in (2, 3) and (len(a) == 2 or a[2] == "--dry"):
        if not os.path.isdir(a[1]):
            die(f"build: no project directory {a[1]}", 2)
        return cmd_build(a[1], len(a) == 3)
    if cmd == "check" and len(a) in (2, 4) and (len(a) == 2 or a[2] == "--project"):
        why = check(a[1], a[3] if len(a) == 4 else None)
        if why:
            die("package: " + "; ".join(why))
        print("PACKAGE OK")
        return 0
    if cmd == "live-redirects" and len(a) == 2:
        return cmd_live_redirects(a[1])
    if cmd == "zadani" and len(a) in (4, 6) and a[2] == "--plan-id" and (len(a) == 4 or a[4] == "--out"):
        return cmd_zadani(a[1], a[3], a[5] if len(a) == 6 else None)
    die("usage: aid-ui-package.py build <project> [--dry] | check <package> [--project <dir>] | zadani <package> --plan-id P<NNN> [--out <file>]", 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
