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
      (Step 2) the deployment brief.

Exit: 0 ok, 1 refused, 2 usage.
"""
import datetime, hashlib, json, os, subprocess, sys

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
    }


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
    die("usage: aid-ui-package.py build <project> [--dry] | check <package> [--project <dir>]", 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
