#!/usr/bin/env bash
# =============================================================================
# aid-ui-coverage.sh — which items of the ecosystem standards /aid-ui applies,
# waives or leaves to someone, and the proof for each (P103 Step 2).
#
# The list of standard files is skills/ui-design/coverage/sources.yaml (docs-root-relative paths). They are read
# from the docs tree the PROJECT declares: three directories above the standards map `aid_standards_map_file`
# returns (<root>/ecosystem/specs/standards-map.md) - the project's own data. A project without a declared map is
# checked against the plugin's copies (skills/ui-design/references/standards/, SOURCES maps each docs path to its
# copy), with "WARN: projekt nemá mapu standardů" on stderr and the exit code of the check (P113: nothing is read
# from a docs tree the project did not declare).
#
#   extract [<project>]   one line per item: <id> TAB <text>. An item is a list entry
#                         or a table row (not the header row), or a paragraph that opens in
#                         bold (rules written as prose: **UA-2 Chyba validace.** ...); id =
#                         <file>#<heading path>#<sha8 of whitespace-normalised text>,
#                         a repeated text under one heading gets -2, -3 by order.
#   check [<project>]     every item has a map entry, every entry still exists, every
#                         disposition is valid and every script:<name> is in checks.yaml.
#                         Exit 1 map gap or invalid entry, 2 a standard (or the docs root)
#                         cannot be read, 3 only standard text changed or an item moved
#                         under another heading (same text) since the map; items listed.
#   report <project>      each item applicable to the variant in brand-state.json gets its
#                         status from its own evidence:
#                           script:<check>  rows of that check in .aid-ui/verify/result.json,
#                                           only when its build_id is the state's build.id
#                           pm:<kind>       an answer of that kind decided approve|choose
#                           agent:<what>    an attestation of the item id ("ověřil agent")
#                           na:<reason>     "nepoužito, protože <reason>"
#                         no evidence -> "neověřeno". Writes docs/design/soulad-se-standardy.md
#                         and docs/design/soulad-summary.json.
#
# Map entry: {id, text, do}; `do` is a disposition string for every variant, or a
# mapping variant (web|webapp|pwa) -> disposition; a variant left out of the mapping
# does not have the item (the report omits it).
# Tests: AID_UI_COVERAGE_SOURCES and AID_UI_COVERAGE_MAP point at fixtures; checks.yaml
# is read next to the map.
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COV="$DIR/../skills/ui-design/coverage"
# shellcheck source=lib/aid-standards-map.sh
source "$DIR/lib/aid-standards-map.sh"

usage() { echo "ERROR: aid-ui-coverage.sh: ${1:-usage}; see the header of this script" >&2; exit 2; }

VERB="${1:-}"; PROJECT="${2:-$PWD}"
case "$VERB" in extract|check) ;; report) (( $# >= 2 )) || usage "report needs <project>" ;; *) usage ;; esac
command -v yq >/dev/null || { echo "ERROR: aid-ui-coverage.sh: yq is missing" >&2; exit 2; }

rc=0; map_md="$(aid_standards_map_file "$PROJECT")" || rc=$?
case "$rc" in
  0) DOCS="$(dirname "$(dirname "$(dirname "$map_md")")")" ;;
  1) DOCS="" ; echo "WARN: projekt nemá mapu standardů: standardy čteny z kopií pluginu (skills/ui-design/references/standards/)" >&2 ;;
  *) echo "ERROR: aid-ui-coverage.sh: the standards map of $PROJECT cannot be read" >&2; exit 2 ;;
esac
COPIES="$DIR/../skills/ui-design/references/standards"
if [[ -n "$DOCS" ]]; then [[ -d "$DOCS" && -r "$DOCS" ]] || { echo "ERROR: aid-ui-coverage.sh: docs root $DOCS cannot be read" >&2; exit 2; }
else [[ -r "$COPIES/SOURCES" ]] || { echo "ERROR: aid-ui-coverage.sh: the plugin's copies of the standards are missing ($COPIES/SOURCES)" >&2; exit 2; }; fi

MAP="${AID_UI_COVERAGE_MAP:-$COV/map.yaml}"
exec python3 - "$VERB" "$PROJECT" "$DOCS" "${AID_UI_COVERAGE_SOURCES:-$COV/sources.yaml}" "$MAP" "$(dirname "$MAP")/checks.yaml" "$COPIES" <<'PY'
import datetime, hashlib, json, os, re, subprocess, sys

verb, project, docs, sources_f, map_f, checks_f, copies = sys.argv[1:]

def source_path(rel):
    """The file of a docs-root-relative standard: in the declared docs tree, else the plugin's copy (SOURCES)."""
    if docs:
        return os.path.join(docs, rel)
    for ln in open(os.path.join(copies, "SOURCES"), encoding="utf-8"):
        p = ln.split()
        if len(p) == 2 and not ln.startswith("#") and p[1] == rel:
            return os.path.join(copies, p[0])
    return os.path.join(copies, "(no copy of %s)" % rel)
VARIANTS = ("web", "webapp", "pwa")

def die(msg, code):
    print("ERROR: aid-ui-coverage.sh: " + msg, file=sys.stderr)
    sys.exit(code)

def yaml(path):
    try:
        out = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True, check=True).stdout
        return json.loads(out or "null")
    except (subprocess.CalledProcessError, ValueError, OSError) as e:
        die("cannot read %s: %s" % (path, getattr(e, "stderr", "") or e), 1)

LIST = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$")
SEP = re.compile(r"^\s*\|?(\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*\|?\s*$")
HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")

def norm(s):
    return " ".join(s.split())

# ponytail: a list item continues only on indented lines right under it; a lazy
# (unindented) continuation starts no item and is not part of any.
def extract_file(rel):
    try:
        lines = open(source_path(rel), encoding="utf-8").read().split("\n")
    except OSError as e:
        die("standard %s cannot be read: %s" % (rel, e), 2)
    items, heads, fence, cur = [], [], None, None
    i = 0
    if lines and lines[0].strip() == "---":   # front matter
        i = next((k + 1 for k in range(1, len(lines)) if lines[k].strip() == "---"), 0)
    for k in range(i, len(lines)):
        line = lines[k]
        f = re.match(r"^\s*(```|~~~)\s*(\w*)", line)
        if f:
            if fence is None and f.group(2) in ("markdown", "md"):
                fence = "md" + f.group(1)   # a template written as markdown: its items count
            elif fence is None:
                fence = f.group(1)
            elif fence.endswith(f.group(1)) and not f.group(2):
                fence = None
            cur = None
            continue
        if fence and not fence.startswith("md"):
            continue
        h = HEAD.match(line)
        if h:
            lvl = len(h.group(1)) + (6 if fence else 0)   # template headings nest under the outer one
            heads = [x for x in heads if x[0] < lvl] + [(lvl, re.sub(r"\s*\{#[^}]*\}$", "", h.group(2)))]
            cur = None
            continue
        path = " > ".join(t for _, t in heads)
        m = LIST.match(line)
        if line.lstrip().startswith("|") and not SEP.match(line):
            nxt = lines[k + 1] if k + 1 < len(lines) else ""
            if not SEP.match(nxt):   # the row above a separator is the header
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                items.append([path, " | ".join(cells)])
            cur = None
        elif m:
            cur = [path, m.group(2)]
            items.append(cur)
        elif line.startswith("**") and not cur:   # a rule written as a paragraph: **FB-18 Varianty.** ...
            cur = [path, line, "para"]
            items.append(cur)
        elif cur and line.strip() and (line[:1] in " \t" or len(cur) == 3):
            cur[1] += " " + line.strip()
        else:
            cur = None
    out, seen = [], {}
    for path, text, *_ in items:
        text = norm(text)
        if not text:
            continue
        sha = hashlib.sha256(text.encode()).hexdigest()[:8]
        key = (path, sha)
        seen[key] = seen.get(key, 0) + 1
        suffix = "" if seen[key] == 1 else "-%d" % seen[key]
        out.append({"id": "%s#%s#%s%s" % (rel, path, sha, suffix), "file": rel, "head": path, "sha": sha, "text": text})
    return out

def parts(item_id):
    f, rest = item_id.split("#", 1)
    head, sha = rest.rsplit("#", 1)
    return f, head, sha.split("-")[0]

sources = (yaml(sources_f) or {}).get("sources") or []
if not sources:
    die("%s lists no sources" % sources_f, 1)
items = [it for rel in sources for it in extract_file(rel)]

if verb == "extract":
    for it in items:
        print("%s\t%s" % (it["id"], it["text"]))
    sys.exit(0)

entries = (yaml(map_f) or {}).get("items") or []
checks = set(((yaml(checks_f) or {}).get("checks") or {}).keys())

def dispositions(e):
    d = e.get("do")
    if isinstance(d, str):
        return {v: d for v in VARIANTS}
    return d if isinstance(d, dict) else {}

def validate(e):
    d = e.get("do")
    if not (isinstance(d, str) or (isinstance(d, dict) and d)):
        return "no disposition"
    for v, disp in dispositions(e).items():
        if v not in VARIANTS:
            return "unknown variant %s" % v
        kind, _, arg = str(disp).partition(":")
        if kind not in ("script", "pm", "agent", "na") or not arg.strip():
            return "disposition %r needs script:|pm:|agent:|na: and a non-empty value" % disp
        if kind == "script" and arg.strip() not in checks:
            return "script:%s is not a check in %s" % (arg.strip(), checks_f)
    return None

if verb == "check":
    bad = [(e.get("id"), validate(e)) for e in entries]
    bad = [(i, why) for i, why in bad if why]
    ids = {it["id"] for it in items}
    mapped = {e.get("id") for e in entries}
    unmapped = [it for it in items if it["id"] not in mapped]
    stale = [e["id"] for e in entries if e.get("id") not in ids]
    changed, gaps = [], []
    for it in unmapped:
        f, h, s = it["file"], it["head"], it["sha"]
        old = next((x for x in stale if parts(x)[0] == f and parts(x)[2] == s), None)
        why = "moved"
        if old is None:
            old = next((x for x in stale if parts(x)[:2] == (f, h)), None)
            why = "changed"
        if old is None:
            gaps.append("missing in map: %s  (%s)" % (it["id"], it["text"][:80]))
        else:
            stale.remove(old)
            changed.append("%s: %s -> %s  (%s)" % (why, old, it["id"], it["text"][:80]))
    gaps += ["no longer in the standard: %s" % x for x in stale]
    gaps += ["invalid entry %s: %s" % (i, why) for i, why in bad]
    for line in gaps + changed:
        print(line)
    if gaps:
        sys.exit(1)
    if changed:
        sys.exit(3)
    print("coverage ok: %d items, %d map entries" % (len(items), len(entries)))
    sys.exit(0)

# report
def load(path, default):
    try:
        return json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (OSError, ValueError) as e:
        die("cannot read %s: %s" % (path, e), 1)

state = load(os.path.join(project, "docs/design/brand-state.json"), None)
if state is None:
    die("no docs/design/brand-state.json in %s" % project, 1)
variant = (state.get("variant") or {}).get("type")
if variant not in VARIANTS:
    die("brand-state.json records no variant.type (web|webapp|pwa)", 1)
gate = load(os.path.join(project, ".aid-ui/verify/result.json"), {})
build = (state.get("build") or {}).get("id")
rows = (gate.get("rows") or []) if build and gate.get("build_id") == build else []
answers = (state.get("answers") or {}).values()
attest = state.get("attestations") or {}
# PM exceptions still standing (a changed page fingerprint voids one; resolved ones do not count)
excs = [x for x in state.get("exceptions") or [] if isinstance(x, dict) and not x.get("resolved")]
AXES = ("check", "page", "viewport", "browser", "role", "state")
def excused(r):
    for x in excs:
        sel = x.get("selector") or {}
        if all(sel.get(k, "*") in ("*", str(r.get(k, ""))) for k in AXES):
            return x
    return None
by_id = {e.get("id"): e for e in entries}
opts = state.get("options") or {}
OFF = [(k, "nepoužito, protože PM v kroku 0 vynechal " + {"vision": "vizi", "seo": "SEO", "identity": "nové logo"}[k]
        + " (důvod v kapitole " + {"vision": "Vize", "seo": "SEO", "identity": "Logo"}[k] + ")")
       for k in ("vision", "seo", "identity") if opts.get(k) is False]

def status(it):
    e = by_id.get(it["id"])
    if e is None:
        return None, "neověřeno (chybí v mapě)"
    disp = dispositions(e).get(variant)
    if disp is None:
        return False, None
    kind, _, arg = disp.partition(":")
    arg = arg.strip()
    # a part the PM left out in step 0 (options false) is waived for its own items; script checks keep their rows
    if kind != "script":
        for part, why in OFF:
            if part == "vision" and ("product-vision" in it["file"] or disp == "pm:vision"):
                return disp, why
            if part == "seo" and ("/seo" in it["file"] or "seo-audit" in it["file"] or disp == "pm:seo_brief"):
                return disp, why
            if part == "identity" and disp == "pm:identity":
                return disp, why
    if kind == "na":
        return disp, "nepoužito, protože " + arg
    if kind == "script":
        mine = [r for r in rows if r.get("check") == arg]
        if mine and all(r.get("status") == "pass" for r in mine):
            return disp, "použito, ověřil skript"
        bad = [r for r in mine if r.get("status") != "pass"]
        if bad and all(excused(r) for r in bad):
            return disp, "výjimka PM: " + (excused(bad[0]).get("reason") or "bez důvodu")
        if any(r.get("status") == "fail" for r in mine):
            return disp, "nesplněno (skript)"
        return disp, "neověřeno"
    if kind == "pm":
        ok = any(isinstance(a, dict) and a.get("kind") == arg and a.get("decision") in ("approve", "choose") for a in answers)
        return disp, "použito, rozhodl PM" if ok else "neověřeno"
    return disp, "ověřil agent" if it["id"] in attest else "neověřeno"

rows_out, counts, per_file = [], {}, {}
for it in items:
    disp, st = status(it)
    if disp is False:
        continue
    rows_out.append((it, disp or "-", st))
    key = "nepoužito" if st.startswith("nepoužito") else "výjimka PM" if st.startswith("výjimka PM") else st   # one count per kind
    counts[key] = counts.get(key, 0) + 1
    pf = per_file.setdefault(it["file"], {})
    pf[key] = pf.get(key, 0) + 1

def cell(s):
    return s.replace("|", "\\|").replace("\n", " ")

today = datetime.date.today().isoformat()
md = ["# Soulad se standardy", "",
      "Interní přehled, %s. Varianta: %s, build: %s. Položek: %d." % (today, variant, build or "-", len(rows_out)), "",
      "| Stav | Počet |", "|---|---:|"]
md += ["| %s | %d |" % (k, v) for k, v in sorted(counts.items())]
for f in sources:
    mine = [r for r in rows_out if r[0]["file"] == f]
    if not mine:
        continue
    md += ["", "## " + f, "", "| Položka | Oddíl | Způsob | Stav |", "|---|---|---|---|"]
    md += ["| %s | %s | %s | %s |" % (cell(it["text"]), cell(it["head"]), cell(d), cell(st)) for it, d, st in mine]
out_dir = os.path.join(project, "docs/design")
os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, "soulad-se-standardy.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
json.dump({"generated_at": today, "gate_run_at": (state.get("gate") or {}).get("run_at") if isinstance(state, dict) else None,
           "variant": variant, "build_id": build, "total": len(rows_out),
           "counts": counts, "by_standard": per_file},
          open(os.path.join(out_dir, "soulad-summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("report: %d items -> docs/design/soulad-se-standardy.md, soulad-summary.json" % len(rows_out))
PY
