#!/usr/bin/env python3
"""aid_roadmap_page.py — the progress page of a roadmap (AID 3.14.0; PM wish 30. 10. 2026: every roadmap has one, and
every plan and /aid-do on the same thing refreshes it). Called by scripts/aid-roadmap-page.sh, aid-plan-lint.sh and
plan-close; one place holds the path boundary, the data schema, the rendering and the record.

  init     <project> <state> <doc> --title T          marker line in the document, the data file, first publish
  publish  <project> <state> <doc> (--plan P<n> | --aid-do)
  check    <project> <doc>                            for the lint: exit 0 ok, 1 no page (marker or data), 2 bad path
  refreshed <project> <state> <doc> <plan> <rev>...   for plan-close: exit 0 when <plan> published the data as they are
                                                      in one of <rev> (its merge, the target's tip), 1 not, 2 bad path

The document lives in the project (docs/plans/<x>.md); its data <x>.prubeh.json beside it (versioned, the agent
writes only this); the rendered page and the record in the state root (.aid-o/work/roadmap-pages/<id>/, runtime).
"""
import datetime, hashlib, html, json, os, re, secrets, subprocess, sys
from zoneinfo import ZoneInfo

MARK = re.compile(r'^<!-- aid-roadmap-page: id=([a-z0-9][a-z0-9-]{0,48}-[0-9a-f]{8}) -->$', re.M)
# the page's fixed structure (AID 3.14.1, PM 1. 11. 2026: every roadmap page has the same parts, in the same order):
# where we are in one sentence + overall progress, what waits for the PM, the stages, what is being done, the numbers,
# what is missing from whom, the risks, what is done per stage, the history of changes (from the record, not the data)
ITEM = {'ceka_na_tebe': ('co',), 'etapy': ('nazev', 'kdy', 'co_prinese', 'stav'), 'ted': ('co', 'kdo', 'kdy'),
        'cisla': ('co', 'hodnota'), 'chybi': ('co', 'od_koho', 'od_kdy'), 'rizika': ('co',), 'hotovo': ('etapa', 'lidsky')}
OPTIONAL = {'ceka_na_tebe': ('doporuceni',), 'rizika': ('overi',)}
COUNTS = {'etapy': ('polozky_hotovo', 'polozky_celkem')}
TOP = {'nazev', 'stav_k', 'jednou_vetou', 'stav', *ITEM, 'posledni_zmena'}
STAV = {'na_ceste': 'Na cestě', 'stoji': 'Stojí', 'hotovo': 'Hotovo'}
ETAPA = {'hotovo': ('Hotovo', 'done'), 'ted': ('Teď', 'run'), 'ceka': ('Čeká', 'wait')}


class Refused(Exception):
    def __init__(self, code, msg):
        super().__init__(msg); self.code = code


def inside(root, rel, what, must_exist=True):
    """<rel> under <root>: no absolute path, no "..", no component (the last included, a dangling one too) a link."""
    if not isinstance(rel, str) or not rel or os.path.isabs(rel) or '\0' in rel:
        raise Refused(2, f'{what} {rel!r} is not a path relative to {root}')
    norm = os.path.normpath(rel)
    if norm.startswith('..') or norm == '.' or '..' in norm.split(os.sep):
        raise Refused(2, f'{what} {rel} leads out of {root}')
    if os.path.islink(root) or not os.path.isdir(root):
        raise Refused(2, f'{root} is not a plain directory')
    cur = root
    for part in norm.split(os.sep):
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            raise Refused(2, f'{what} {rel}: {cur} is a link — the roadmap page reads and writes no links')
    if must_exist and not os.path.isfile(cur):
        raise Refused(2, f'{what} {rel} is not a file in {root}')
    return cur


def write_no_follow(path, data):
    """write through a temporary file in the same directory, renamed over the target (never through a link)"""
    tmp = f'{path}.tmp-{os.getpid()}'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, 'wb') as f:
        f.write(data if isinstance(data, bytes) else data.encode())
    os.replace(tmp, path)


def doc_paths(project, doc):
    project = os.path.realpath(project)
    rel = os.path.relpath(os.path.abspath(doc), project) if os.path.isabs(doc) else doc
    d = inside(project, rel, 'the roadmap document', must_exist=False)
    if not os.path.isfile(d):
        raise Refused(1, f'the roadmap document {rel} does not exist')
    if not d.endswith('.md'):
        raise Refused(2, f'the roadmap document {rel} is not a .md file')
    return project, rel, d, d[:-3] + '.prubeh.json', rel[:-3] + '.prubeh.json'


def marker(doc_abs):
    with open(doc_abs, encoding='utf-8') as f:
        m = MARK.search(f.read())
    return m.group(1) if m else None


def validate(raw, where):
    try:
        d = json.loads(raw)
    except ValueError as e:
        raise Refused(1, f'{where} is not JSON: {e}')
    errs = []
    if not isinstance(d, dict):
        raise Refused(1, f'{where} must be an object')
    for k in sorted(set(d) - TOP):
        errs.append(f'unknown field {k}')
    for k in sorted(TOP - set(d)):
        errs.append(f'missing field {k}')
    txt = lambda v: isinstance(v, str) and v.strip() != ''
    if 'nazev' in d and not (txt(d['nazev']) and len(d['nazev']) <= 60):
        errs.append('nazev must be a text of 1-60 characters')
    if 'stav_k' in d:
        try:
            datetime.date.fromisoformat(d['stav_k']) if re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(d['stav_k'])) else 1 / 0
        except (ValueError, ZeroDivisionError):
            errs.append('stav_k must be a date RRRR-MM-DD')
    if 'jednou_vetou' in d and not txt(d['jednou_vetou']):
        errs.append('jednou_vetou must be a non-empty text')
    if 'stav' in d and not (isinstance(d['stav'], str) and d['stav'] in STAV):
        errs.append(f'stav must be one of {", ".join(STAV)}')
    for k, fields in ITEM.items():
        if k not in d:
            continue
        if not isinstance(d[k], list):
            errs.append(f'{k} must be a list (it may be empty)'); continue
        for i, it in enumerate(d[k]):
            allowed = set(fields) | set(OPTIONAL.get(k, ())) | set(COUNTS.get(k, ()))
            if not isinstance(it, dict):
                errs.append(f'{k}[{i}] must be an object'); continue
            for f in fields:
                if not txt(it.get(f)):
                    errs.append(f'{k}[{i}].{f} must be a non-empty text')
            for f in sorted(set(it) - allowed):
                errs.append(f'{k}[{i}]: unknown field {f}')
            for f in OPTIONAL.get(k, ()):
                if f in it and not txt(it[f]):
                    errs.append(f'{k}[{i}].{f} must be a non-empty text when present')
            nums = [it.get(f) for f in COUNTS.get(k, ())]
            if nums and not (all(isinstance(n, int) and not isinstance(n, bool) and n >= 0 for n in nums) and nums[0] <= nums[1]):
                errs.append(f'{k}[{i}]: polozky_hotovo and polozky_celkem must be whole numbers, hotovo <= celkem')
    if isinstance(d.get('etapy'), list):
        if not d['etapy']:
            errs.append('etapy must name at least one stage')
        for i, it in enumerate(d['etapy']):
            if isinstance(it, dict) and not (isinstance(it.get('stav'), str) and it['stav'] in ETAPA):
                errs.append(f'etapy[{i}].stav must be one of {", ".join(ETAPA)}')
        named = [it['nazev'] for it in d['etapy'] if isinstance(it, dict) and isinstance(it.get('nazev'), str)]
        names = set(named)
        if len(names) != len(named):
            errs.append('etapy: every stage needs its own nazev (hotovo is grouped by it)')
        for i, it in enumerate(d.get('hotovo') if isinstance(d.get('hotovo'), list) else []):
            if isinstance(it, dict) and not (isinstance(it.get('etapa'), str) and it['etapa'] in names):
                errs.append(f'hotovo[{i}].etapa {it.get("etapa")!r} is not the nazev of a stage in etapy')
    pz = d.get('posledni_zmena')
    if 'posledni_zmena' in d:
        if not (isinstance(pz, dict) and set(pz) == {'kdo', 'co'} and isinstance(pz.get('kdo'), str)
                and re.fullmatch(r'P\d+|aid-do|init', pz['kdo']) and txt(pz.get('co'))):
            errs.append('posledni_zmena must be {kdo: P<n>|aid-do|init, co: <text>}')
    if errs:
        raise Refused(1, f'{where}: ' + '; '.join(errs))
    return d


def render(d, doc_rel, hist):
    """the fixed page (3.14.1). <hist>: the record's latest entries, newest first, each {at, kdo, co}"""
    e = html.escape
    done = sum(x['polozky_hotovo'] for x in d['etapy']); total = sum(x['polozky_celkem'] for x in d['etapy'])
    pct = round(100 * done / total) if total else 0
    def when(iso):   # the record is UTC; the PM reads Prague time
        try:
            t = datetime.datetime.strptime(iso, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).astimezone(ZoneInfo('Europe/Prague'))
        except (TypeError, ValueError):
            return ''
        except Exception:                 # no time zone database on this host: UTC as it is
            return f'{iso[8:10]}. {iso[5:7]}. {iso[11:16]} UTC'
        return f'{t.day}. {t.month}. {t:%H:%M}'
    date = f'{int(d["stav_k"][8:10])}. {int(d["stav_k"][5:7])}. {d["stav_k"][:4]}'
    ul = lambda items, f: '<ul>' + ''.join(f'<li>{f(x)}</li>' for x in items) + '</ul>'
    card = lambda title, body, cls='': f'<section class="card{cls}"><h2>{e(title)}</h2>{body}</section>'
    none = lambda t: f'<p class="m">{e(t)}</p>'
    if d['ceka_na_tebe']:
        you = ul(d['ceka_na_tebe'], lambda x: f'<b>{e(x["co"])}</b>' + (f' <span class="m">· doporučuji: {e(x["doporuceni"])}</span>' if x.get('doporuceni') else ''))
    else:
        you = '<p class="ok">Nic. Jede se bez tebe.</p>'
    def stage(x):
        label, cls = ETAPA[x['stav']]; t = x['polozky_celkem']; w = round(100 * x['polozky_hotovo'] / t) if t else 0
        return (f'<div class="ph{" now" if x["stav"] == "ted" else ""}"><span class="chip {cls}">{label}</span><div class="n">{e(x["nazev"])}</div>'
                f'<div class="d">{e(x["kdy"])}</div><p>{e(x["co_prinese"])}</p><div class="mini"><i style="width:{w}%"></i></div>'
                f'<div class="m">{x["polozky_hotovo"]} / {t}</div></div>')
    by_stage = ''
    for k, x in enumerate([x for x in reversed(d['etapy']) if any(h['etapa'] == x['nazev'] for h in d['hotovo'])]):
        items = [h for h in d['hotovo'] if h['etapa'] == x['nazev']]
        by_stage += f'<details{" open" if k == 0 else ""}><summary>{e(x["nazev"])} <span class="m">({e(x["kdy"])})</span></summary>' + ul(items, lambda h: e(h['lidsky'])) + '</details>'
    rows = lambda head, items, f: '<table><tr>' + ''.join(f'<th>{h}</th>' for h in head) + '</tr>' + ''.join('<tr>' + f(x) + '</tr>' for x in items) + '</table>'
    return f"""<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{e(d["nazev"])}</title><style>{CSS}</style></head><body>
<header><div class="w"><div class="kicker">Roadmapa · stav k {date}</div>
<h1>{e(d["nazev"])} <span class="pill">{STAV[d["stav"]]}</span></h1><p class="lead">{e(d["jednou_vetou"])}</p>
<div class="prog"><b>{done} / {total}</b><div class="bar"><i style="width:{pct}%"></i></div><span>položek hotovo</span></div></div></header>
<main><div class="w grid">
{card("Čeká na tebe", you, " you")}
{card("Etapy", '<div class="tl">' + ''.join(stage(x) for x in d['etapy']) + '</div>')}
<div class="two">{card("Teď se dělá", ul(d['ted'], lambda x: f'<b>{e(x["co"])}</b> <span class="m">· {e(x["kdo"])} · {e(x["kdy"])}</span>') if d['ted'] else none('Nic nerozpracovaného.'))}
{card("Kde jsme v číslech", '<div class="nums">' + ''.join(f'<div class="num"><b>{e(c["hodnota"])}</b><span>{e(c["co"])}</span></div>' for c in d['cisla']) + '</div>' if d['cisla'] else none('Bez čísel.'))}</div>
<div class="two">{card("Co chybí a od koho", rows(['Co', 'Od koho', 'Od kdy'], d['chybi'], lambda x: f'<td>{e(x["co"])}</td><td>{e(x["od_koho"])}</td><td class="m">{e(x["od_kdy"])}</td>') if d['chybi'] else none('Nic, na nikoho se nečeká.'))}
{card("Rizika", ul(d['rizika'], lambda x: e(x['co']) + (f' <span class="m">{e(x["overi"])}</span>' if x.get('overi') else '')) if d['rizika'] else none('Žádná známá.'))}</div>
{card("Hotovo", by_stage or none('Zatím nic.'))}
{card("Historie změn", rows(['Kdy', 'Co', 'Kdo'], hist, lambda h: f'<td class="m">{when(h.get("at"))}</td><td>{e(h.get("co") or "—")}</td><td class="m">{e(h.get("kdo") or "")}</td>'))}
<footer>Zdroj: {e(doc_rel)} · obnovuje každý plán roadmapy před uzávěrem a /aid-do nad její položkou</footer>
</div></main></body></html>
"""


CSS = """:root{--bg:#eeeae1;--card:#fffdf8;--ink:#1c2321;--mut:#68716d;--line:#ddd6c8;--band:#17322b;--band2:#21463c;--acc:#2f8f6f;--warn:#c27a12;--warnbg:#fbf0dc;--prog:#e8e2d4}
@media (prefers-color-scheme:dark){:root{--bg:#141816;--card:#1d2321;--ink:#e9ece8;--mut:#9aa39e;--line:#2d3532;--band:#0f2a23;--band2:#173a31;--acc:#5cc39c;--warn:#e3a33d;--warnbg:#2c2416;--prog:#2a312e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
header{background:linear-gradient(135deg,var(--band),var(--band2));color:#f3f6f2;padding:28px 16px 32px}.w{max-width:960px;margin:0 auto}
.kicker{font-size:12px;letter-spacing:.08em;text-transform:uppercase;opacity:.75}h1{font-size:28px;margin:6px 0 10px;line-height:1.2}
.lead{font-size:17px;max-width:680px;opacity:.95;margin:0 0 20px}.prog{display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.bar{flex:1;min-width:220px;height:12px;background:rgba(255,255,255,.18);border-radius:99px;overflow:hidden}.bar i{display:block;height:100%;background:#7fe0b6;border-radius:99px}
.prog b{font-size:22px}.prog span{opacity:.8;font-size:14px}
.pill{display:inline-block;font-size:12px;font-weight:600;padding:3px 10px;border-radius:99px;background:rgba(127,224,182,.2);color:#9ff0cb;margin-left:8px;vertical-align:middle}
main{padding:0 16px 48px}.grid{display:grid;gap:16px;margin-top:-16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px 20px}
h2{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--mut);margin:0 0 12px}
.you{border-color:var(--warn);background:var(--warnbg)}.you h2{color:var(--warn)}.ok{color:var(--acc);font-weight:600;margin:0}
.tl{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}
.ph{border:1px solid var(--line);border-radius:10px;padding:12px;background:var(--card)}.ph.now{border-color:var(--acc);box-shadow:0 0 0 2px color-mix(in srgb,var(--acc) 25%,transparent)}
.ph .n{font-weight:700}.ph .d{color:var(--mut);font-size:13px}.ph p{margin:6px 0 8px;font-size:14px}
.chip{font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;padding:2px 8px;border-radius:99px;display:inline-block}
.done{background:color-mix(in srgb,var(--acc) 18%,transparent);color:var(--acc)}.run{background:color-mix(in srgb,var(--warn) 20%,transparent);color:var(--warn)}.wait{background:var(--prog);color:var(--mut)}
.mini{height:6px;background:var(--prog);border-radius:99px;overflow:hidden}.mini i{display:block;height:100%;background:var(--acc)}
.nums{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}.num{border:1px solid var(--line);border-radius:10px;padding:12px}.num b{font-size:24px;display:block}.num span{color:var(--mut);font-size:13px}
table{width:100%;border-collapse:collapse;font-size:14px}td,th{text-align:left;padding:8px 6px;border-top:1px solid var(--line);vertical-align:top}th{color:var(--mut);font-weight:600;font-size:12px;border-top:0;white-space:nowrap}
ul{margin:0;padding-left:18px}li{margin:4px 0}.m{color:var(--mut);font-size:13px}.two{display:grid;grid-template-columns:1fr 1fr;gap:16px}
@media (max-width:720px){.two{grid-template-columns:1fr}h1{font-size:23px}}details summary{cursor:pointer;font-weight:600}footer{color:var(--mut);font-size:12px;margin-top:20px}"""


def record_dir(state, rid):
    state = os.path.realpath(state)
    rel = os.path.join('.aid-o', 'work', 'roadmap-pages', rid)
    # checked for links before the directories are made (nothing is created through a link) and again after
    inside(state, rel, 'the record directory', must_exist=False)
    os.makedirs(os.path.join(state, rel), exist_ok=True)
    return inside(state, rel, 'the record directory', must_exist=False)


def claim(project, rel, rid, rdir):
    """a page id belongs to one document: another document still carrying it (a copied line) is refused"""
    cur = os.path.join(rdir, 'current.json')
    if os.path.isfile(cur) and not os.path.islink(cur):
        other = json.load(open(cur)).get('dokument')
        if other and other != rel and os.path.isfile(os.path.join(project, other)) and marker(os.path.join(project, other)) == rid:
            raise Refused(1, f'{rel} carries the page id {rid} of {other} (a copied marker line) — remove the line and run init')


def published_ok(state, rid):
    hist = os.path.join(os.path.realpath(state), '.aid-o', 'work', 'roadmap-pages', rid, 'history.jsonl')
    if not os.path.isfile(hist) or os.path.islink(hist):
        return False
    for ln in open(hist, encoding='utf-8'):
        try:
            if json.loads(ln).get('vysledek') in ('link', 'local'):
                return True
        except ValueError:
            pass
    return False


def publish(project, state, doc, who, aid_do=False, any_author=False):
    project, rel, d_abs, data_abs, data_rel = doc_paths(project, doc)
    rid = marker(d_abs)
    if not rid:
        raise Refused(1, f'{rel} has no page — aid-roadmap-page.sh init {rel} --title "<topic>"')
    inside(project, data_rel, 'the data file')
    with open(data_abs, 'rb') as f:
        raw = f.read()          # read ONCE: hashed, rendered and published from these bytes
    d = validate(raw.decode('utf-8', 'replace'), data_rel)
    kdo = d['posledni_zmena']['kdo']
    if any_author:
        pass
    elif aid_do and kdo != 'aid-do':
        raise Refused(1, f'{data_rel}: posledni_zmena.kdo is {kdo}, not aid-do — say what this /aid-do changed there first')
    if not aid_do and not any_author and who != kdo:
        raise Refused(1, f'{data_rel}: posledni_zmena.kdo is {kdo}, not {who} — the page would claim a change of somebody else')
    digest = hashlib.sha256(raw).hexdigest()
    rdir = record_dir(state, rid)
    claim(project, rel, rid, rdir)
    cur = os.path.join(rdir, 'current.json')
    page = os.path.join(rdir, 'page.html')
    hist_file = os.path.join(rdir, 'history.jsonl')
    past = []
    if os.path.isfile(hist_file) and not os.path.islink(hist_file):
        for ln in open(hist_file, encoding='utf-8'):
            try:
                x = json.loads(ln)
            except ValueError:
                continue
            if x.get('vysledek') in ('link', 'local'):
                past.append(x)
    now_at = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    shown = [{'at': now_at, 'kdo': 'init' if any_author else kdo, 'co': d['posledni_zmena']['co']}] + past[::-1][:4]
    write_no_follow(page, render(d, rel, shown))
    pub = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'aid-pm-page-publish.sh')
    p = subprocess.run(['bash', pub, page, '--kind', 'roadmap', '--roadmap', rid, '--title', d['nazev'], '--project-root', state],
                       capture_output=True, text=True)
    line = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else ''
    if p.returncode == 0 and line.startswith('link '):
        result, link = 'link', line[5:]
    elif p.returncode == 0 and line.startswith('artifact '):
        result, link = 'local', None
    else:
        result, link = 'failed', None
    # a republish by init records init as its author: it never counts as a plan's refresh (plan-close reads kdo)
    entry = {'kdo': 'init' if any_author else kdo, 'co': d['posledni_zmena']['co'], 'data_sha256': digest, 'dokument': rel, 'at': now_at,
             'vysledek': result}
    if result == 'failed':
        # the link carries the PM's key: never into a file, even inside an error text
        entry['duvod'] = re.sub(r'https?://\S+', '<link>', (p.stderr.strip().splitlines() or ['the publisher failed'])[-1])[:300]
    hist = os.path.join(rdir, 'history.jsonl')
    if os.path.islink(hist):
        raise Refused(2, f'{hist} is a link')
    fd = os.open(hist, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, 'a') as f:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    write_no_follow(cur, json.dumps({'id': rid, 'dokument': rel, **{k: entry[k] for k in ('kdo', 'data_sha256', 'at', 'vysledek')}}, ensure_ascii=False, indent=1))
    if result == 'failed':
        sys.stderr.write(p.stderr)
        raise Refused(1, f'the page of {rel} was not published: {entry["duvod"]}')
    print(f'link {link}' if link else f'local {page}')


def init(project, state, doc, title):
    project, rel, d_abs, data_abs, data_rel = doc_paths(project, doc)
    rid = marker(d_abs)
    if not rid:
        base = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', os.path.basename(rel)[:-3]).lower()
        slug = re.sub(r'[^a-z0-9]+', '-', base).strip('-')[:40] or 'roadmapa'
        rid = f'{slug}-{secrets.token_hex(4)}'
        with open(d_abs, encoding='utf-8') as f:
            lines = f.read().split('\n')
        at = 1 if lines and lines[0].startswith('# ') else 0
        lines.insert(at, f'<!-- aid-roadmap-page: id={rid} -->')
        write_no_follow(d_abs, '\n'.join(lines))
    claim(project, rel, rid, record_dir(state, rid))         # a copied page line is refused before anything is written
    if not os.path.lexists(os.path.join(project, data_rel)):
        if not isinstance(title, str) or not title.strip() or len(title) > 60:
            raise Refused(1, '--title must be a text of 1-60 characters')
        inside(project, data_rel, 'the data file', must_exist=False)
        data = {'nazev': title, 'stav_k': datetime.date.today().isoformat(), 'jednou_vetou': 'Roadmapa má stránku průběhu; první plán ji naplní.',
                'stav': 'na_ceste', 'ceka_na_tebe': [],
                'etapy': [{'nazev': 'Etapa 1', 'kdy': 'doplní první plán', 'co_prinese': 'doplní první plán', 'stav': 'ted', 'polozky_hotovo': 0, 'polozky_celkem': 1}],
                'ted': [], 'cisla': [], 'chybi': [], 'rizika': [], 'hotovo': [], 'posledni_zmena': {'kdo': 'init', 'co': 'založení stránky'}}
        write_no_follow(os.path.join(project, data_rel), json.dumps(data, ensure_ascii=False, indent=1) + '\n')
        publish(project, state, rel, 'init')
    else:
        inside(project, data_rel, 'the data file')       # an existing one is a plain file in the project, not a link
        if not published_ok(state, rid):                  # the first publish failed: init tries again
            return publish(project, state, rel, None, any_author=True)
        print(f'kept {rid} {data_rel}')


def refreshed(project, state, doc, plan, *revs):
    project = os.path.realpath(project)
    d_abs = inside(project, doc, 'the roadmap document', must_exist=False)    # read from the commits, not the disk
    rel, data_rel = os.path.normpath(doc), os.path.normpath(doc)[:-3] + '.prubeh.json'
    if not rel.endswith('.md'):
        return 2
    # the page id as the committed document says (the working copy may be on another branch), else as it is on disk
    rid = None
    for rev in revs:
        shown = subprocess.run(['git', '-C', project, 'show', f'{rev}:{rel}'], capture_output=True, text=True)
        m = MARK.search(shown.stdout) if shown.returncode == 0 else None
        if m:
            rid = m.group(1); break
    rid = rid or (marker(d_abs) if os.path.isfile(d_abs) else None)
    if not rid:
        return 1
    want = set()
    for rev in revs:
        blob = subprocess.run(['git', '-C', project, 'show', f'{rev}:{data_rel}'], capture_output=True)
        if blob.returncode == 0:
            want.add(hashlib.sha256(blob.stdout).hexdigest())
    hist = os.path.join(os.path.realpath(state), '.aid-o', 'work', 'roadmap-pages', rid, 'history.jsonl')
    if not os.path.isfile(hist) or os.path.islink(hist):
        return 1
    for ln in open(hist, encoding='utf-8'):
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if e.get('kdo') == plan and e.get('data_sha256') in want and e.get('vysledek') in ('link', 'local'):
            return 0
    return 1


def main(a):
    try:
        if a[:1] == ['init'] and len(a) == 6 and a[4] == '--title':
            return init(a[1], a[2], a[3], a[5]) or 0
        if a[:1] == ['publish'] and len(a) in (5, 6):
            if a[4] == '--aid-do' and len(a) == 5:
                return publish(a[1], a[2], a[3], None, aid_do=True) or 0
            if a[4] == '--plan' and len(a) == 6 and re.fullmatch(r'P\d+', a[5]):
                return publish(a[1], a[2], a[3], a[5]) or 0
        if a[:1] == ['check'] and len(a) == 3:
            project, rel, d_abs, data_abs, data_rel = doc_paths(a[1], a[2])
            if not marker(d_abs):
                raise Refused(1, f'{rel} has no page line — aid-roadmap-page.sh init {rel} --title "<topic>"')
            if not os.path.lexists(data_abs):
                raise Refused(1, f'{rel} has its page line but no data {data_rel} — aid-roadmap-page.sh init {rel} --title "<topic>"')
            inside(project, data_rel, 'the data file')
            print(marker(d_abs)); return 0
        if a[:1] == ['refreshed'] and len(a) >= 6:
            return refreshed(*a[1:])
    except Refused as r:
        sys.stderr.write(f'aid-roadmap-page: {r}\n'); return r.code
    sys.stderr.write('usage: aid-roadmap-page.sh init <doc> --title "<topic>" | publish <doc> (--plan P<n> | --aid-do)\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
