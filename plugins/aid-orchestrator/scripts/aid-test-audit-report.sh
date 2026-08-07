#!/usr/bin/env bash
# aid-test-audit-report.sh — the ONE report page every full audit produces.
#
# WHY A FIXED FORM
#   Four days of audits produced fragments: a count here, a cost there, a
#   parallel number somewhere else — each shown only when the owner complained
#   about its absence. The owner's requirement is the opposite: one page, all
#   sections, every time, whether or not the data behind a section is complete.
#   A section with no data still renders, saying what is missing and why —
#   because "we do not know yet" is a finding, and an absent section reads as
#   "nothing to see here".
#
# THE CANONICAL SECTIONS (never omit one):
#   1. Hlavní čísla        — totals: units, examined vs not, measured cost, parallel
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

AUDIT_DIR="$audit_dir" CATALOG="$catalog" OUTPUT="$output" python3 - <<'PY'
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

cat_units, cat_safe = [], set()
try:
    import yaml
    c = yaml.safe_load(open(CAT))
    cat_units = c.get("run_units", [])
    cat_safe = {u["run_unit_id"] for u in cat_units
                if (u.get("parallel") or {}).get("status") == "safe"}
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

measured = [m for m in meas if m.get("duration_ms")]
total_s = sum(m["duration_ms"] for m in measured) / 1000
censored = [m for m in meas if m.get("state") == "timed_out"]
top = sorted(measured, key=lambda m: -m["duration_ms"])[:10]

# structural groups: runner + directory of the unit id
def gkey(uid):
    kind, _, rest = uid.partition(":")
    parts = rest.split("/")
    return (kind, "/".join(parts[:-1]) if len(parts) > 1 else "(kořen)")
groups = collections.defaultdict(lambda: {"n": 0, "cost": 0.0, "par": 0, "to": 0})
for e in inv:
    uid = e["run_unit_id"]
    g = groups[gkey(uid)]
    g["n"] += 1
    if uid in cat_safe: g["par"] += 1
    m = by_unit_meas.get(uid)
    if m and m.get("duration_ms"):
        g["cost"] += m["duration_ms"] / 1000
        if m.get("state") == "timed_out": g["to"] += 1

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

safe_cost = sum((by_unit_meas.get(u["run_unit_id"], {}).get("duration_ms") or 0)
                for u in cat_units
                if u["run_unit_id"] in cat_safe) / 1000

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
html{background:var(--paper);color:var(--ink);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;}
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
H.append(f'<div class="stat bad"><b>{n_unexamined}</b><span>zatím neprověřeno do hloubky</span></div>')
H.append(f'<div class="stat"><b>{total_s/60:.0f}&nbsp;min</b><span>změřená cena ({len(measured)} sad)</span></div>')
H.append(f'<div class="stat good"><b>{len(cat_safe)}</b><span>smí běžet paralelně</span></div>')
H.append('</div>')

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
             '<th class="num">Sad</th><th class="num">Cena</th><th class="num">Paralelně</th>'
             '<th class="num">Utnuto</th></tr>')
    for (kind, d), g in sorted(groups.items(), key=lambda x: -x[1]["cost"]):
        H.append(f'<tr><td><b>{esc(kind)}</b> · {esc(d)}</td>'
                 f'<td class="num">{g["n"]}</td>'
                 f'<td class="num">{g["cost"]/60:.1f}&nbsp;min</td>'
                 f'<td class="num">{g["par"]}</td>'
                 f'<td class="num">{g["to"] or "—"}</td></tr>')
    H.append('</table></div>')
    H.append('<p class="legend">Skupiny jsou strukturální (typ běžce a adresář). '
             'Pojmenování podle účelu doplňuje průvodce auditem při prezentaci.</p>')
else:
    H.append('<p class="empty">Inventura chybí — bez ní nejde portfolio seskupit.</p>')

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
if cat_safe and safe_cost > 0:
    est = safe_cost * (1 - 1/4)
    H.append(f'<tr><td><b>Paralelismus</b></td><td>{len(cat_safe)} sad v poolu; '
             f'sériově stojí {safe_cost/60:.0f} min</td>'
             f'<td class="num">~{est/60:.0f} min/běh</td><td>odhad při 4 bězích vedle sebe</td></tr>')
else:
    H.append('<tr><td><b>Paralelismus</b></td><td class="empty">žádná sada zatím nemá důkaz '
             'o bezpečném souběhu</td><td class="num">—</td><td>—</td></tr>')
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
    dup = sc.get("duplicate_test_cases", [])
    if dup:
        d0 = dup[0]
        H.append(f'<tr><td><span class="pill info">duplicitní testy</span></td><td class="num">{len(dup)} dvojic</td>'
                 f'<td>např. {d0["shared_cases"]}× shodný test: <code>{esc(d0["file_a"].split("/")[-1])}</code> ↔ '
                 f'<code>{esc(d0["file_b"].split("/")[-1])}</code></td></tr>')
    else:
        H.append('<tr><td><span class="pill ok">duplicitní testy</span></td><td class="num">0</td><td class="dim">žádná shoda názvů napříč soubory</td></tr>')
    wk = sc.get("weak_oracle", [])
    real_wk = [w for w in wk if not w.get("likely_legitimate")]
    H.append(f'<tr><td><span class="pill {"warn" if real_wk else "ok"}">slabá orákula</span></td>'
             f'<td class="num">{len(real_wk)}{" (+" + str(len(wk)-len(real_wk)) + " validátorů, kde je exit kód legitimní)" if len(wk)>len(real_wk) else ""}</td>'
             f'<td>{esc(", ".join(w["file"].split("/")[-1] for w in real_wk[:3])) or "—"}</td></tr>')
    unref = sc.get("unreferenced_tests", [])
    H.append(f'<tr><td><span class="pill {"crit" if unref else "ok"}">nespouštěné soubory</span></td>'
             f'<td class="num">{len(unref)}</td>'
             f'<td>{esc(", ".join(u["file"].split("/")[-1] for u in unref[:3])) or "každý soubor na disku někdo spouští"}</td></tr>')
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

# 7 — akce a plán
H.append(sec("7 · Akce a plán", "Co udělat, v pořadí"))
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

# 8 — nedokázáno
H.append(sec("8 · Nedokázáno", "Co zůstává neprokázané, a jaký je další krok"))
if unresolved:
    H.append('<div class="tablewrap"><table><tr><th>Jednotka</th><th>Proč</th><th>Další krok</th></tr>')
    for u in unresolved:
        H.append(f'<tr><td>{esc(nm(u.get("run_unit_id", "?")))}</td>'
                 f'<td class="dim">{esc(u.get("missing_proof", ""))}</td>'
                 f'<td>{esc((u.get("next_measurement") or "")[:180])}</td></tr>')
    H.append('</table></div>')
else:
    H.append('<p class="empty">Rozhodnutí neeviduje žádné nedokázané body.</p>')

# 9 — zdroje
H.append(sec("9 · Zdroje", "Odkud každé číslo je"))
H.append('<p class="legend">inventura: <code>inventory.json</code> · měření: '
         '<code>measurements.jsonl</code> · verdikty analytiků: <code>agents/*.json</code> · '
         'nálezy: <code>consolidated-findings.json</code> · akce a nedokázané: '
         '<code>decision.json</code> · paralelismus: schválený katalog '
         '<code>.aid-o/config/test-catalog.yaml</code>. Vše v adresáři auditu; '
         'nic v tomto reportu nevzniklo mimo tyto soubory.</p>')

with open(OUT, "w") as f:
    f.write("\n".join(H))
print(OUT)
PY
