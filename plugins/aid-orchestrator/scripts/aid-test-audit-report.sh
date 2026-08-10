#!/usr/bin/env bash
# aid-test-audit-report.sh — the ONE report page every full audit produces.
#
# WHY A FIXED FORM
#   Four days of audits produced fragments: a count here, a cost there, a
#   a number somewhere else — each shown only when the owner complained
#   about its absence. The owner's requirement is the opposite: one page, all
#   sections, every time, whether or not the data behind a section is complete.
#   A section with no data still renders, saying what is missing and why —
#   because "we do not know yet" is a finding, and an absent section reads as
#   "nothing to see here".
#
# THE CANONICAL SECTIONS (never omit one):
#   1. Hlavní čísla        — totals: units, examined vs not, measured cost
#   2. Prověřenost         — how many units anyone actually examined
#   3. Skupiny             — the portfolio grouped so a human can hold it
#   4. Co žere čas         — top costs and every timeout-censored unit
#   5. Kolik ušetříme čím  — the levers, each labeled measured/estimated/unknown
#   6. Kvalita             — duplicates, weak oracles, uncollected tests
#   7. Akce a plán         — ranked actions with effort and risk, and the goal
#   8. Nedokázáno          — what remains unproved, with the named next step
#   9. Zdroje              — which artifacts every number came from
#
# Usage:
#   aid-test-audit-report.sh --audit-dir <dir> --project-root <root> \
#     [--catalog <approved catalog>] [--output <report.html>]
#
# Output defaults to <audit-dir>/report.html. Exit 0 with the path on stdout.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_die() { echo "aid-test-audit-report.sh: $2" >&2; exit "$1"; }

audit_dir="" project_root="" catalog="" output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-dir)    [[ $# -ge 2 ]] || _die 2 "--audit-dir requires a value"; audit_dir="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --catalog)      [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog="$2"; shift 2 ;;
    --output)       [[ $# -ge 2 ]] || _die 2 "--output requires a value"; output="$2"; shift 2 ;;
    *) _die 2 "unknown argument '$1'" ;;
  esac
done
[[ -n "$audit_dir" && -d "$audit_dir" ]] || _die 2 "--audit-dir is required and must exist"
[[ -n "$project_root" ]] || _die 2 "--project-root is required"
[[ -n "$catalog" ]] || catalog="${project_root%/}/.aid-o/config/test-catalog.yaml"
[[ -n "$output" ]] || output="${audit_dir%/}/report.html"

command -v python3 >/dev/null 2>&1 || _die 2 "python3 is required to assemble the report"

AUDIT_DIR="$audit_dir" CATALOG="$catalog" OUTPUT="$output" PROJECT_ROOT="$project_root" python3 - <<'PY'
import json, os, glob, html, collections, datetime

D = os.environ["AUDIT_DIR"].rstrip("/")
OUT = os.environ["OUTPUT"]
CAT = os.environ["CATALOG"]

def jload(p, default):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return default

def esc(x): return html.escape(str(x))

# ── data ────────────────────────────────────────────────────────────────────
inv = jload(f"{D}/inventory.json", {}).get("entries", [])
dec = jload(f"{D}/decision.json", {})
meas = []
try:
    with open(f"{D}/measurements.jsonl") as f:
        meas = [json.loads(l) for l in f if l.strip()]
except Exception: pass
disp = []
for f in glob.glob(f"{D}/agents/*.json"):
    disp += jload(f, {}).get("dispositions") or []
findings = jload(f"{D}/consolidated-findings.json", {}).get("findings", [])
scan = jload(f"{D}/content-scan.json", {})
sc = scan.get("checks", {})
# previous round, for the trend line
prev = {}
parent = os.path.dirname(D)
try:
    sibs = sorted(d for d in glob.glob(parent + "/*/round-summary.json")
                  if os.path.dirname(d) != D)
    if sibs: prev = jload(sibs[-1], {})
except Exception: pass

cat_units = []
try:
    import yaml
    c = yaml.safe_load(open(CAT))
    cat_units = c.get("run_units", [])
except Exception:
    pass

by_unit_meas = {m.get("run_unit_id"): m for m in meas}
audit_id = (dec.get("audit_id")
            or jload(f"{D}/audit-state.json", {}).get("audit_id")
            or os.path.basename(D))

# ── derived, honestly ───────────────────────────────────────────────────────
n_units = len(inv)
examined = [d for d in disp
            if not (d.get("disposition") == "keep"
                    and (d.get("falsification") or {}).get("method") == "unproved")]
n_examined = len(examined)
n_unexamined = max(0, len(disp) - n_examined)

# per UNIT, last record wins — a re-measurement appended after a timed-out
# first attempt must replace it, not add to the totals next to it
_unit_meas = list(by_unit_meas.values())
measured = [m for m in _unit_meas if m.get("duration_ms")]
total_s = sum(m["duration_ms"] for m in measured) / 1000
censored = [m for m in _unit_meas if m.get("state") == "timed_out"]
top = sorted(measured, key=lambda m: -m["duration_ms"])[:10]

# structural groups: runner + directory of the unit id
def gkey(uid):
    kind, _, rest = uid.partition(":")
    parts = rest.split("/")
    return (kind, "/".join(parts[:-1]) if len(parts) > 1 else "(kořen)")
_cc = sc.get("case_counts") or {}
_all_cases = {c["file"]: c["cases"] for c in (_cc.get("files") or _cc.get("top") or [])}
groups = collections.defaultdict(lambda: {"n": 0, "cost": 0.0, "to": 0, "cases": 0})
for e in inv:
    uid = e["run_unit_id"]
    g = groups[gkey(uid)]
    g["n"] += 1
    m = by_unit_meas.get(uid)
    if m and m.get("duration_ms"):
        g["cost"] += m["duration_ms"] / 1000
        if m.get("state") == "timed_out": g["to"] += 1
    _kind, _, _rest = uid.partition(":")
    # gate unit ids are gate NAMES, not file paths — substring-matching them
    # against test files produces accidental hits, never a real mapping
    if _kind == "gate":
        continue
    for _cf, _cn in _all_cases.items():
        if _rest and _rest in _cf:
            g["cases"] += _cn
            break

actions = dec.get("actions", [])
prio_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
acts = sorted([a for a in actions],
              key=lambda a: (prio_order.get(a.get("priority"), 9),))
unresolved = dec.get("unresolved", [])

def nm(uid):
    return uid.split("/")[-1] if "/" in uid else uid

# quality findings buckets
qual = collections.defaultdict(list)
for f in findings:
    qual[f.get("category", "ostatní")].append(f)

# ── html ────────────────────────────────────────────────────────────────────
CSS = """
:root{--paper:#FAFAF7;--ink:#1C2126;--muted:#5C6672;--line:#D8DAD4;--accent:#2E5E7E;
--crit:#B3352B;--ok:#2E7D4F;--warn:#9A6B15;--soft:#F0F1EC;}
@media (prefers-color-scheme: dark){:root{--paper:#14181C;--ink:#E8EAE6;--muted:#98A1AB;
--line:#2C333A;--accent:#7FAECB;--crit:#E07A6E;--ok:#6FBF8B;--warn:#D3A24C;--soft:#1C2228;}}
:root[data-theme="dark"]{--paper:#14181C;--ink:#E8EAE6;--muted:#98A1AB;--line:#2C333A;
--accent:#7FAECB;--crit:#E07A6E;--ok:#6FBF8B;--warn:#D3A24C;--soft:#1C2228;}
:root[data-theme="light"]{--paper:#FAFAF7;--ink:#1C2126;--muted:#5C6672;--line:#D8DAD4;
--accent:#2E5E7E;--crit:#B3352B;--ok:#2E7D4F;--warn:#9A6B15;--soft:#F0F1EC;}
html,body{background:var(--paper);color:var(--ink);}
html{font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;}
body{max-width:56rem;margin:0 auto;padding:2.5rem 1.25rem 5rem;}
h1{font-size:1.85rem;line-height:1.15;margin:.2rem 0 .3rem;letter-spacing:-.015em;text-wrap:balance;}
.sub{color:var(--muted);margin:0 0 2rem;}
.eyebrow{font-size:.72rem;font-weight:600;letter-spacing:.09em;text-transform:uppercase;
color:var(--accent);margin:2.4rem 0 .4rem;}
h2{font-size:1.22rem;margin:.1rem 0 .7rem;letter-spacing:-.01em;}
p{max-width:65ch;margin:.5rem 0;}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(11rem,1fr));gap:1px;
background:var(--line);border:1px solid var(--line);}
.stat{background:var(--paper);padding:.85rem 1rem;}
.stat b{display:block;font-size:1.65rem;font-variant-numeric:tabular-nums;letter-spacing:-.02em;}
.stat span{color:var(--muted);font-size:.84rem;}
.stat.bad b{color:var(--crit);} .stat.good b{color:var(--ok);}
.tablewrap{overflow-x:auto;}
table{border-collapse:collapse;width:100%;font-size:.92rem;}
th{font-size:.72rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);
font-weight:600;text-align:left;padding:.42rem .7rem .42rem 0;border-bottom:1px solid var(--ink);}
td{padding:.48rem .7rem .48rem 0;border-bottom:1px solid var(--line);vertical-align:top;}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;}
td.dim{color:var(--muted);}
.pill{display:inline-block;font-size:.72rem;font-weight:600;padding:.08rem .45rem;
border:1px solid currentColor;border-radius:2px;}
.pill.crit{color:var(--crit);} .pill.warn{color:var(--warn);}
.pill.ok{color:var(--ok);} .pill.info{color:var(--accent);}
.note{background:var(--soft);border-left:3px solid var(--accent);padding:.75rem 1rem;
margin:.9rem 0;max-width:65ch;}
.note.crit{border-left-color:var(--crit);}
.legend{color:var(--muted);font-size:.83rem;max-width:65ch;}
code{font:.88em ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--soft);
padding:.08em .3em;border-radius:2px;}
ol{max-width:65ch;padding-left:1.3rem;} ol li{margin:.4rem 0;}
.empty{color:var(--muted);font-style:italic;}
"""

def sec(eyebrow, title):
    return f'<div class="eyebrow">{esc(eyebrow)}</div>\n<h2>{esc(title)}</h2>\n'

H = []
H.append(f"<title>Audit testů — {esc(audit_id)}</title>\n<style>{CSS}</style>")
H.append(f"<h1>Audit testovacího portfolia</h1>")
H.append(f'<p class="sub">Audit <code>{esc(audit_id)}</code> · sestaveno '
         f'{datetime.date.today().strftime("%-d. %-m. %Y")} · každé číslo níže má u sebe '
         f'svůj zdroj a míru jistoty; sekce bez dat zůstává a říká, co chybí.</p>')

# 1 — hlavní čísla
H.append(sec("1 · Hlavní čísla", "Portfolio v kostce"))
H.append('<div class="stats">')
H.append(f'<div class="stat"><b>{n_units}</b><span>testovacích sad</span></div>')
cases_total = (scan.get("counts") or {}).get("total_cases_countable")
if cases_total:
    fc = ((sc.get("case_counts") or {}).get("files_counted")) or 0
    br = ((sc.get("case_counts") or {}).get("by_runner")) or {}
    parts = [f"{lbl} {br[k]}" for k, lbl in
             (("py", "pytest"), ("bats", "bats"), ("ts", "js/ts")) if br.get(k)]
    detail = " · ".join(parts) if len(parts) > 1 else f"spočítáno v {fc} souborech"
    H.append(f'<div class="stat"><b>{cases_total}</b><span>testovacích případů ({detail})</span></div>')
H.append(f'<div class="stat bad"><b>{n_unexamined}</b><span>zatím neprověřeno do hloubky</span></div>')
H.append(f'<div class="stat"><b>{total_s/60:.0f}&nbsp;min</b><span>změřená cena ({len(measured)} sad)</span></div>')
_unref_n = len(sc.get("unreferenced_tests") or [])
_files_n = sum((sc.get("scope") or {}).get(k) or 0
               for k in ("bats_files", "py_test_files", "ts_test_files"))
if _unref_n and _files_n:
    H.append(f'<div class="stat bad"><b>{_unref_n}</b><span>test. souborů (z {_files_n}) žádná brána nespouští</span></div>')
H.append('</div>')
_ci_top = sc.get("ci") or {}
if _ci_top.get("workflows") and not _ci_top.get("runs_tests"):
    H.append('<div class="note crit"><b>CI nespouští žádné testy.</b> Workflow na main kontroluje '
             'jen lint a formality — merge neprověří ani jeden test. Detail v sekci 6.</div>')
if cases_total and (((sc.get("case_counts") or {}).get("by_runner")) or {}).get("py"):
    H.append('<p class="legend">Počet pytest případů je statická spodní mez — '
             'parametrizované testy se za běhu násobí, skutečný počet je vyšší.</p>')
if prev:
    d_ex = n_examined - prev.get("examined", 0)
    d_cost = total_s/60 - prev.get("measured_min", 0)
    H.append(f'<p class="legend"><b>Trend od minulého kola</b> ({esc(prev.get("audit_id","?"))}): '
             f'prověřeno {"+" if d_ex>=0 else ""}{d_ex}, '
             f'změřená cena {"+" if d_cost>=0 else ""}{d_cost:.0f} min, '
             f'utnuto {prev.get("censored","?")} → {len(censored)}.</p>')
else:
    H.append('<p class="legend">Trend: první kolo se záznamem — příští report ukáže rozdíl.</p>')

# 2 — prověřenost
H.append(sec("2 · Prověřenost", "Kolik sad někdo doopravdy otevřel"))
if disp:
    H.append(f'<p><b>{n_examined}</b> prověřeno s důkazem, <b>{n_unexamined}</b> dostalo '
             f'jen štítek „keep — neprověřeno“. Ten štítek <b>není</b> potvrzení kvality; '
             f'znamená „na tuhle sadu se zatím nedostalo“. Cíl je toto číslo každým kolem snižovat.</p>')
else:
    H.append('<p class="empty">Tento běh nevydal žádné dispozice — prověřenost nelze vyčíslit.</p>')

# 3 — skupiny
H.append(sec("3 · Skupiny", "Z čeho se portfolio skládá"))
if groups:
    H.append('<div class="tablewrap"><table><tr><th>Skupina (typ · umístění)</th>'
             '<th class="num">Sad</th><th class="num">Případů</th><th class="num">Cena</th><th class="num">s/případ</th>'
             '<th class="num">Utnuto</th></tr>')
    for (kind, d), g in sorted(groups.items(), key=lambda x: -x[1]["cost"]):
        _per = f'{g["cost"]/g["cases"]:.2f}' if g["cases"] and g["cost"] else "—"
        H.append(f'<tr><td><b>{esc(kind)}</b> · {esc(d)}</td>'
                 f'<td class="num">{g["n"]}</td>'
                 f'<td class="num">{g["cases"] or "—"}</td>'
                 f'<td class="num">{g["cost"]/60:.1f}&nbsp;min</td>'
                 f'<td class="num">{_per}</td>'
                 f'<td class="num">{g["to"] or "—"}</td></tr>')
    H.append('</table></div>')
    _unmapped = cases_total and all(g["cases"] == 0 for g in groups.values())
    H.append('<p class="legend">Skupiny jsou strukturální (typ běžce a adresář). '
             'Pojmenování podle účelu doplňuje průvodce auditem při prezentaci.'
             + (' Případy na jednotlivé brány nejdou mechanicky přiřadit (brány volají '
                'testy přes wrapper) — celkový počet případů je v sekci 1.' if _unmapped else '')
             + '</p>')
else:
    H.append('<p class="empty">Inventura chybí — bez ní nejde portfolio seskupit.</p>')

# 3b — sady jmenovitě: k čemu každá je
_gov = sc.get("gate_overview") or []
if _gov:
    H.append(sec("3b · Sady jmenovitě", "K čemu každá sada je a proč ji máme"))
    H.append('<div class="tablewrap"><table><tr><th>Sada</th><th>K čemu je (podle obsahu)</th>'
             '<th class="num">Souborů</th><th class="num">Případů</th><th>Profily</th><th>Poznámka</th></tr>')
    for g in sorted(_gov, key=lambda x: -x["cases"]):
        notes = []
        if g.get("noop"):
            notes.append('příkaz <code>true</code> — nemůže spadnout, nic neověřuje')
        if g.get("codename") and g.get("suggested_name"):
            notes.append(f'kódové jméno z EPICu — návrh: <code>{esc(g["suggested_name"])}</code>')
        if g.get("required") and not g.get("profiles"):
            notes.append('required, ale není v žádném profilu — nikdy se nespustí')
        topics = ", ".join(g.get("topics") or [])
        H.append(f'<tr><td><code>{esc(g["gate"])}</code></td>'
                 f'<td>{esc(topics) or "<span class=dim>—</span>"}</td>'
                 f'<td class="num">{g["files"] or "—"}</td>'
                 f'<td class="num">{g["cases"] or "—"}</td>'
                 f'<td class="dim">{esc(", ".join(g.get("profiles") or [])) or "žádný"}</td>'
                 f'<td>{" · ".join(notes) or ""}</td></tr>')
    H.append('</table></div>')
    H.append('<p class="legend">„K čemu je“ odvozeno mechanicky z názvů souborů, které sada spouští — '
             'témata jsou nejčastější slova po odstranění test-prefixů. Návrhy jmen nahrazují '
             'kódová jména EPICů (p070…), která po merge nikomu nic neřeknou.</p>')

# 4 — co žere čas
H.append(sec("4 · Co žere čas", "Deset nejdražších a všechno utnuté"))
if measured:
    H.append('<div class="tablewrap"><table><tr><th class="num">Sekundy</th><th>Sada</th><th></th></tr>')
    for m in top:
        cut = m.get("state") == "timed_out"
        note = '<span class="pill warn">utnuto — skutečná cena vyšší</span>' if cut else ""
        H.append(f'<tr><td class="num">{m["duration_ms"]/1000:.0f}{"+" if cut else ""}</td>'
                 f'<td>{esc(nm(m["run_unit_id"]))}</td><td>{note}</td></tr>')
    H.append('</table></div>')
    if censored:
        H.append(f'<p><b>{len(censored)} sad měření uřízlo</b> — jejich skutečná cena je neznámá '
                 f'a dokud se nedoměří s vyšším limitem, celková cena portfolia je jen spodní mez.</p>')
else:
    H.append('<p class="empty">Tento běh nic neměřil (režim static) — ceny doplní běh v režimu full.</p>')

# 5 — páky
H.append(sec("5 · Kolik ušetříme čím", "Páky podle výnosu"))
H.append('<div class="tablewrap"><table><tr><th>Páka</th><th>Stav</th><th class="num">Úspora</th><th>Jistota</th></tr>')
if censored:
    H.append(f'<tr><td><b>Obří sady</b></td><td>{len(censored)}× utnuto — nejdřív doměřit, pak dělit</td>'
             f'<td class="num">neznámo</td><td>nutné doměřit</td></tr>')
ovl = sc.get("gate_overlap", [])
if ovl:
    ex = ovl[0]
    H.append(f'<tr><td><b>Dvojité běhy bran</b></td>'
             f'<td>{len(ovl)} kandidátů — např. <code>{esc(ex.get("file","?").split("/")[-1])}</code> '
             f'běží pod {esc(ex.get("gate_direct"))} i {esc(ex.get("gate_pool"))}</td>'
             f'<td class="num">až celé druhé spuštění</td><td>mechanický sken</td></tr>')
elif scan:
    H.append('<tr><td><b>Dvojité běhy bran</b></td><td class="empty">sken žádný překryv nenašel</td>'
             '<td class="num">0</td><td>mechanický sken</td></tr>')
else:
    H.append('<tr><td><b>Dvojité běhy bran</b></td><td class="empty">content-scan.json chybí — '
             'sken tento běh neproběhl</td><td class="num">—</td><td>—</td></tr>')
H.append('</table></div>')
H.append('<p class="legend">Páka bez čísla není zamlčená — má u sebe napsáno, proč číslo zatím neexistuje.</p>')

# 6 — kvalita
H.append(sec("6 · Kvalita", "Co o testech víme z jejich obsahu"))
if scan:
    H.append('<div class="tablewrap"><table><tr><th>Mechanická kontrola</th><th class="num">Nálezů</th><th>Detail</th></tr>')
    scope = sc.get("scope") or {}
    bats_n = scope.get("bats_files", None)
    _ci = sc.get("ci") or {}
    if _ci.get("workflows"):
        if not _ci.get("runs_tests"):
            _co = _ci.get("commented_out") or []
            H.append(f'<tr><td><span class="pill crit">CI bez testů</span></td><td class="num">{_ci["workflows"]} workflow</td>'
                     f'<td>žádný CI workflow nespouští jediný test — merge do main neprověří nic'
                     f'{" (test. krok je zakomentovaný: " + esc(_co[0]) + ")" if _co else ""}</td></tr>')
        else:
            _ev = _ci.get("evidence") or []
            H.append(f'<tr><td><span class="pill ok">CI spouští testy</span></td><td class="num">{len(_ev)}</td>'
                     f'<td>např. {esc(_ev[0]) if _ev else ""}</td></tr>')
    fab = sc.get("fabricated_measured") or []
    if fab:
        f0 = fab[0]
        H.append(f'<tr><td><span class="pill crit">vymyšlená „měření“</span></td><td class="num">{len(fab)}</td>'
                 f'<td>dispozice tvrdí „measured“ a účtenka nesouhlasí — např. '
                 f'{esc(nm(f0.get("run_unit_id","?")))}: tvrzeno {f0.get("claimed_ms")} ms, '
                 f'reálně {f0.get("actual_ms") if f0.get("actual_ms") is not None else "žádné měření"}</td></tr>')
    dup = sc.get("duplicate_test_cases", [])
    if bats_n == 0:
        # A green zero over a project with no bats files reads as "checked and
        # clean"; an independent review called exactly this contradiction out.
        H.append('<tr><td><span class="pill info">duplicitní testy (bats)</span></td><td class="num">—</td>'
                 '<td class="dim">nehodnoceno — projekt nemá bats soubory; duplicity jiných runnerů zatím neumíme mechanicky</td></tr>')
        H.append('<tr><td><span class="pill info">slabá orákula (bats)</span></td><td class="num">—</td>'
                 '<td class="dim">nehodnoceno — totéž</td></tr>')
    elif dup:
        d0 = dup[0]
        H.append(f'<tr><td><span class="pill info">duplicitní testy</span></td><td class="num">{len(dup)} dvojic</td>'
                 f'<td>např. {d0["shared_cases"]}× shodný test: <code>{esc(d0["file_a"].split("/")[-1])}</code> ↔ '
                 f'<code>{esc(d0["file_b"].split("/")[-1])}</code></td></tr>')
    else:
        H.append('<tr><td><span class="pill ok">duplicitní testy</span></td><td class="num">0</td><td class="dim">žádná shoda názvů napříč soubory</td></tr>')
    wk = sc.get("weak_oracle", []) if bats_n != 0 else []
    real_wk = [w for w in wk if not w.get("likely_legitimate")]
    if bats_n != 0:
        H.append(f'<tr><td><span class="pill {"warn" if real_wk else "ok"}">slabá orákula</span></td>'
             f'<td class="num">{len(real_wk)}{" (+" + str(len(wk)-len(real_wk)) + " validátorů, kde je exit kód legitimní)" if len(wk)>len(real_wk) else ""}</td>'
             f'<td>{esc(", ".join(w["file"].split("/")[-1] for w in real_wk[:3])) or "—"}</td></tr>')
    unref = sc.get("unreferenced_tests", [])
    nm_ = sc.get("naming") or {}
    outl = nm_.get("outlier_count", 0)
    dom = ", ".join(f'{d["prefix"]} ({d["files"]}x)' for d in (nm_.get("dominant_prefixes") or [])[:3])
    H.append(f'<tr><td><span class="pill {"warn" if outl else "ok"}">konvence názvů</span></td>'
             f'<td class="num">{outl} mimo vzor</td>'
             f'<td>převažuje: {esc(dom) or "žádný vzor"} — návrh: sjednotit, seznam v content-scan.json</td></tr>')
    H.append(f'<tr><td><span class="pill {"crit" if unref else "ok"}">nespouštěné soubory</span></td>'
             f'<td class="num">{len(unref)}</td>'
             f'<td>{esc(", ".join(u["file"].split("/")[-1] for u in unref[:3])) or "každý soubor na disku někdo spouští"}'
             f'{" — kandidáti: brány s neprůhledným wrapperem se nedají přečíst, ověř vzorek" if unref else ""}</td></tr>')
    H.append('</table></div>')
else:
    H.append('<p class="empty">Mechanický sken obsahu tento běh neproběhl (content-scan.json chybí) — '
             'duplicity, orákula a nespouštěné soubory nejsou ověřeny.</p>')
if findings:
    H.append('<div class="tablewrap"><table><tr><th>Kategorie</th><th class="num">Nálezů</th><th>Nejzávažnější příklad</th></tr>')
    sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    for catg, fl in sorted(qual.items(), key=lambda x: min(sev_order.get(f.get("severity"), 9) for f in x[1])):
        worst = sorted(fl, key=lambda f: sev_order.get(f.get("severity"), 9))[0]
        pill = {"critical": "crit", "high": "warn"}.get(worst.get("severity"), "info")
        H.append(f'<tr><td><span class="pill {pill}">{esc(worst.get("severity"))}</span> {esc(catg)}</td>'
                 f'<td class="num">{len(fl)}</td>'
                 f'<td>{esc(nm(worst.get("run_unit_id", "")))}'
                 f'{" — " + esc((worst.get("finding") or "")[:110]) if worst.get("finding") else ""}</td></tr>')
    H.append('</table></div>')
else:
    H.append('<p class="empty">Žádné kvalitativní nálezy — u portfolia s '
             f'{n_unexamined} neprověřenými sadami to znamená „nehledalo se“, ne „nic tam není“.</p>')

# 7 — rizika: co není pokryté
H.append(sec("7 · Rizika", "Co v produkci žádný test nereferencuje"))
unt = sc.get("untested_surfaces", [])
if unt:
    hot = [u for u in unt if u.get("changes_90d", 0) > 0]
    H.append(f'<p><b>{scan.get("counts",{}).get("untested_surfaces","?")} zdrojových souborů</b> '
             f'nereferencuje žádný test, z toho <b>{len(hot)}</b> se za posledních 90 dní měnilo. '
             f'„Nereferencováno“ je nutná podmínka nepokrytí, ne důkaz — ale soubor, který se mění '
             f'týdně a nesahá na něj žádný test, je největší riziko v tomhle reportu.</p>')
    H.append('<div class="tablewrap"><table><tr><th class="num">Změn/90 d</th><th>Soubor</th></tr>')
    for u in unt[:10]:
        H.append(f'<tr><td class="num">{u.get("changes_90d",0)}</td><td><code>{esc(u["file"])}</code></td></tr>')
    H.append('</table></div>')
elif scan:
    H.append('<p class="empty">Sken nenašel žádný zdrojový soubor bez referencujícího testu.</p>')
else:
    H.append('<p class="empty">Sken rizik tento běh neproběhl (content-scan.json chybí).</p>')

# 8 — spolehlivost
H.append(sec("8 · Spolehlivost", "Jak často věci reálně procházejí"))
gs = sc.get("gate_stability", [])
# gates that still exist — history of a DELETED gate measures an artifact, not
# a broken gate; an independent review caught "0 % / dead" over a renamed one.
current_gates = set()
try:
    import yaml as _y4
    _ey2 = _y4.safe_load(open(os.path.join(os.environ.get("PROJECT_ROOT","."), ".aid-o/config/execution.yaml"))) or {}
    current_gates = set((_ey2.get("gates") or {}).keys())
except Exception:
    pass
this_run = {}
for m in meas:
    uid = m.get("run_unit_id") or ""
    if uid.startswith("gate:"):
        this_run[uid[5:]] = m.get("state")
if current_gates:
    removed = [g for g in gs if g["gate"] not in current_gates]
    gs = [g for g in gs if g["gate"] in current_gates]
else:
    removed = []
if gs:
    bad = sorted(gs, key=lambda g: g.get("pass_rate", 1))
    H.append('<div class="tablewrap"><table><tr><th>Brána</th><th class="num">Úspěšnost</th><th class="num">Běhů</th><th></th></tr>')
    for g in bad[:8]:
        pr = g.get("pass_rate", 0)
        pill = "crit" if pr < 0.5 else ("warn" if pr < 0.9 else "ok")
        note = "nikdy neprošla — mrtvá nebo rozbitá" if pr == 0 else ("" if pr >= 0.9 else "nestabilní")
        tr = this_run.get(g["gate"])
        tr_txt = {"terminal_pass": "prošla", "terminal_fail": "SPADLA", "timed_out": "utnuta"}.get(tr, "neběžela")
        if tr == "terminal_fail": note = (note + " · v TOMTO běhu spadla").strip(" ·")
        H.append(f'<tr><td>{esc(g["gate"])}</td>'
                 f'<td class="num"><span class="pill {pill}">{pr*100:.0f} %</span></td>'
                 f'<td class="num">{g.get("samples","?")}</td>'
                 f'<td class="dim">{tr_txt} · {note}</td></tr>')
    H.append('</table></div>')
    if removed:
        H.append(f'<p class="legend">Mimo tabulku: {len(removed)} bran s historií, které v aktuální '
                 f'konfiguraci už neexistují ({esc(", ".join(r["gate"] for r in removed[:4]))}'
                 f'{"…" if len(removed) > 4 else ""}) — jejich čísla měří artefakt, ne dnešní stav.</p>')
    H.append('<p class="legend">Zdroj: historie skutečných běhů bran. Flakiness jednotlivých sad '
             'zůstává neznámá — vyžaduje opakované běhy (<code>--repeat</code>), které se zatím '
             'nevešly do rozpočtu; to je pojmenovaná mezera, ne opomenutí.</p>')
else:
    H.append('<p class="empty">Žádná historie běhů — spolehlivost nelze vyčíslit, dokud brány neběží opakovaně.</p>')

# 9 — akce a plán
H.append(sec("9 · Akce a plán", "Co udělat, v pořadí"))
if acts:
    H.append('<div class="tablewrap"><table><tr><th></th><th>Akce</th><th>Cíl</th>'
             '<th>Pracnost</th><th>Riziko</th></tr>')
    for a in acts[:15]:
        pill = {"critical": "crit", "high": "warn", "medium": "info", "low": "ok"}.get(a.get("priority"), "info")
        eff = (a.get("effort") or {}).get("bucket") or "—"
        risk = a.get("risk") or "—"
        H.append(f'<tr><td><span class="pill {pill}">{esc(a.get("priority"))}</span></td>'
                 f'<td><b>{esc(a.get("action"))}</b> {esc(nm((a.get("targets") or ["?"])[0]))}'
                 f'<br><span class="legend">{esc((a.get("change") or a.get("reason") or "")[:160])}</span></td>'
                 f'<td class="dim">{esc((a.get("reason") or "")[:60])}</td>'
                 f'<td>{esc(eff)}</td><td class="dim">{esc(str(risk)[:80])}</td></tr>')
    H.append('</table></div>')
    if len(acts) > 15:
        H.append(f'<p class="legend">… a {len(acts)-15} dalších v decision.json.</p>')
    H.append('<div class="note"><b>Cíl:</b> každé kolo auditu sníží „neprověřeno“ a odškrtne akce '
             'odshora. Plán oprav z tohoto seznamu vygeneruje odpověď '
             '<code>vytvoř plán oprav</code>.</div>')
else:
    H.append('<p class="empty">Tento běh nevydal žádné akce. Pokud zároveň existují nálezy, '
             'je to chyba auditu, ne stav portfolia.</p>')

# 10 — nedokázáno
H.append(sec("10 · Nedokázáno", "Co zůstává neprokázané, a jaký je další krok"))
if unresolved:
    H.append('<div class="tablewrap"><table><tr><th>Jednotka</th><th>Proč</th><th>Další krok</th></tr>')
    for u in unresolved:
        H.append(f'<tr><td>{esc(nm(u.get("run_unit_id", "?")))}</td>'
                 f'<td class="dim">{esc(u.get("missing_proof", ""))}</td>'
                 f'<td>{esc((u.get("next_measurement") or "")[:180])}</td></tr>')
    H.append('</table></div>')
else:
    H.append('<p class="empty">Rozhodnutí neeviduje žádné nedokázané body.</p>')

# 11 — zdroje
H.append(sec("11 · Zdroje", "Odkud každé číslo je"))
cat_note = ("schválený katalog <code>.aid-o/config/test-catalog.yaml</code>" if cat_units
            else "SCHVÁLENÝ KATALOG NEEXISTUJE — skupiny a počty jsou z návrhu, ne ze schváleného stavu")
H.append('<p class="legend">inventura: <code>inventory.json</code> · měření: '
         '<code>measurements.jsonl</code> · verdikty analytiků: <code>agents/*.json</code> · '
         'nálezy: <code>consolidated-findings.json</code> · akce a nedokázané: '
         '<code>decision.json</code> · mechanický sken (duplicity, rizika, stabilita): '
         '<code>content-scan.json</code> · katalog: ' + cat_note + '. Vše v adresáři auditu; '
         'nic v tomto reportu nevzniklo mimo tyto soubory.</p>')

with open(OUT, "w") as f:
    f.write("\n".join(H))
# the round summary the NEXT report diffs against — the trend has a collector too
with open(f"{D}/round-summary.json", "w") as f:
    json.dump({"audit_id": audit_id, "units": n_units, "examined": n_examined,
               "unexamined": n_unexamined, "measured_min": round(total_s/60, 1),
               "censored": len(censored),
               "actions": len(actions)}, f, indent=1)
print(OUT)
PY
