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

MARK = re.compile(r'^<!-- aid-roadmap-page: id=([a-z0-9][a-z0-9-]{0,48}-[0-9a-f]{8}) -->$', re.M)
ITEM = {'hotovo': ('co', 'lidsky', 'kde'), 'dal': ('co',), 'cisla': ('co', 'hodnota'), 'chybi': ('co', 'od_koho')}
OPTIONAL = {'dal': ('kdy',)}
TOP = {'nazev', 'stav_k', 'jednou_vetou', 'hotovo', 'dal', 'cisla', 'chybi', 'posledni_zmena'}


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
    for k, fields in ITEM.items():
        if k not in d:
            continue
        if not isinstance(d[k], list):
            errs.append(f'{k} must be a list (it may be empty)'); continue
        for i, it in enumerate(d[k]):
            allowed = set(fields) | set(OPTIONAL.get(k, ()))
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
    pz = d.get('posledni_zmena')
    if 'posledni_zmena' in d:
        if not (isinstance(pz, dict) and set(pz) == {'kdo', 'co'} and isinstance(pz.get('kdo'), str)
                and re.fullmatch(r'P\d+|aid-do|init', pz['kdo']) and txt(pz.get('co'))):
            errs.append('posledni_zmena must be {kdo: P<n>|aid-do|init, co: <text>}')
    if errs:
        raise Refused(1, f'{where}: ' + '; '.join(errs))
    return d


def render(d, doc_rel):
    e = html.escape
    def section(title, items, fmt):
        body = ''.join(f'<li>{fmt(i)}</li>' for i in items) or '<li class="empty">nic</li>'
        return f'<section><h2>{e(title)}</h2><ul>{body}</ul></section>'
    cisla = ''.join(f'<div class="n"><b>{e(c["hodnota"])}</b><span>{e(c["co"])}</span></div>' for c in d['cisla'])
    return f'''<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{e(d["nazev"])}</title><style>
:root{{--bg:#fbfaf7;--fg:#1d1d1b;--mut:#6b6a66;--line:#e4e1da;--acc:#2f5d50}}
@media (prefers-color-scheme:dark){{:root{{--bg:#191917;--fg:#ecebe6;--mut:#a3a19b;--line:#33322e;--acc:#7fb7a4}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif}}
main{{max-width:760px;margin:0 auto;padding:24px 16px 48px}}
h1{{font-size:24px;margin:0 0 4px}} .k{{color:var(--mut);font-size:14px}} .v{{font-size:18px;margin:16px 0 24px}}
h2{{font-size:15px;text-transform:uppercase;letter-spacing:.04em;color:var(--acc);margin:28px 0 8px}}
ul{{margin:0;padding-left:20px}} li{{margin:6px 0}} li.empty{{color:var(--mut);list-style:none;margin-left:-20px}}
.m{{color:var(--mut);font-size:14px}} .nums{{display:flex;flex-wrap:wrap;gap:12px}}
.n{{border:1px solid var(--line);border-radius:8px;padding:10px 14px;min-width:120px}} .n b{{display:block;font-size:20px}}
.n span{{color:var(--mut);font-size:14px}} footer{{margin-top:32px;color:var(--mut);font-size:13px}}
</style></head><body><main>
<h1>{e(d["nazev"])}</h1><div class="k">Stav k {e(d["stav_k"])}</div>
<p class="v">{e(d["jednou_vetou"])}</p>
{('<section><h2>Kde jsme v číslech</h2><div class="nums">' + cisla + '</div></section>') if d['cisla'] else ''}
{section("Hotovo", d["hotovo"], lambda i: f'{e(i["lidsky"])} <span class="m">· {e(i["co"])} · {e(i["kde"])}</span>')}
{section("Co je dál", d["dal"], lambda i: e(i["co"]) + (f' <span class="m">· {e(i["kdy"])}</span>' if i.get("kdy") else ''))}
{section("Co chybí a od koho", d["chybi"], lambda i: f'{e(i["co"])} <span class="m">· {e(i["od_koho"])}</span>')}
<footer>Poslední změna: {e(d["posledni_zmena"]["kdo"])} — {e(d["posledni_zmena"]["co"])}. Zdroj: {e(doc_rel)}</footer>
</main></body></html>
'''


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
    write_no_follow(page, render(d, rel))
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
    entry = {'kdo': 'init' if any_author else kdo, 'data_sha256': digest, 'dokument': rel, 'at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
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
                'hotovo': [], 'dal': [], 'cisla': [], 'chybi': [], 'posledni_zmena': {'kdo': 'init', 'co': 'založení stránky'}}
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
