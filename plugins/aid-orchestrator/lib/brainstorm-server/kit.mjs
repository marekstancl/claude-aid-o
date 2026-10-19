// kit.mjs — the steps of scripts/aid-companion.sh that need node: show, proto, shots.
// Environment from aid-companion.sh: AID_COMPANION_DIR (the plan's directory), AID_COMPANION_PLAN,
// AID_COMPANION_PROJECT (project root), AID_COMPANION_STATE (state root), AID_COMPANION_VIEWPORTS
// ("desktop 1280 720,mobile 390 844"), AID_COMPANION_UI (project.yaml `ui` as JSON), AID_PLUGIN_ROOT.
// Every refusal names the field or file and exits 1; nothing is guessed.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ENV = process.env;
const DIR = ENV.AID_COMPANION_DIR, PLAN = ENV.AID_COMPANION_PLAN, PROJECT = ENV.AID_COMPANION_PROJECT;
const VIEWPORTS = (ENV.AID_COMPANION_VIEWPORTS || 'desktop 1280 720,mobile 390 844').split(',')
  .map(s => s.trim().split(/\s+/)).map(([name, w, h]) => ({ name, width: +w, height: +h }));
const UI = JSON.parse(ENV.AID_COMPANION_UI || '{}') || {};
const errors = [];
const fail = m => { errors.push(m); };
const stop = () => { if (errors.length) { for (const e of errors) console.error('aid-companion: ' + e); process.exit(1); } };
const die = m => { console.error('aid-companion: ' + m); process.exit(1); };
const readJson = (f, what) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { die(`${what} (${f}) is not readable JSON: ${e.message}`); } };
const SAFE = /^[A-Za-z0-9][\w.-]*$/;               // a shot name: no slash, no "..", no leading dot

function playwright() {
  const req = createRequire(path.join(ENV.AID_PLUGIN_ROOT, 'lib/ui-fidelity/package.json'));
  return req('@playwright/test');
}
async function browser() {
  const { chromium } = playwright();
  return chromium.launch({ executablePath: ENV.CHROME || undefined, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
}

// ── navrh.json ───────────────────────────────────────────────────────────────
const str = (v, where) => { if (typeof v !== 'string' || !v.trim()) fail(`${where} must be a non-empty text`); return v; };
const arr = (v, where, opt = true) => { if (v === undefined && opt) return []; if (!Array.isArray(v)) { fail(`${where} must be a list`); return []; } return v; };

function shotFiles(name, where, only) {
  if (typeof name !== 'string' || !SAFE.test(name)) { fail(`${where}: shot '${name}' is not a plain shot name (letters, digits, . _ -)`); return {}; }
  const out = {};
  for (const vp of VIEWPORTS) {
    const f = path.join(DIR, 'shots', vp.name, name + '.png');
    if (fs.existsSync(f)) out[vp.name] = `shots/${vp.name}/${name}.png`;
    else if (!only || only.includes(vp.name)) fail(`${where}: shot '${name}' has no ${vp.name} capture (${f}) — run: aid-companion.sh shots --plan ${PLAN}`);
  }
  return out;
}

function validate(n, shotsOnly) {
  if (n.plan !== PLAN) fail(`plan must be "${PLAN}" (got ${JSON.stringify(n.plan)})`);
  if (!Number.isInteger(n.kolo) || n.kolo < 1) fail('kolo must be a whole number from 1');
  const rozhodnuto = arr(n.rozhodnuto, 'rozhodnuto'); rozhodnuto.forEach((t, i) => str(t, `rozhodnuto[${i}]`));
  const spolecne = arr(n.spolecne, 'spolecne');
  const body = arr(n.body, 'body', false);
  if (!body.length) fail('body must have at least one point');
  const ids = new Set();
  const seen = new Map();   // file -> owner (for "listed by two options")
  for (const f of spolecne) seen.set(f, 'spolecne');
  const out = body.map((b, i) => {
    const w = `body[${i}]`;
    const id = b.id === undefined ? String(i + 1) : String(b.id);
    if (ids.has(id)) fail(`${w}.id '${id}' is used twice`); ids.add(id);
    const moznosti = arr(b.moznosti, `${w}.moznosti`, false);
    if (!moznosti.length) fail(`${w}.moznosti must have at least one option`);
    const keys = moznosti.map(m => m.klic);
    keys.forEach((k, j) => { if (k !== String.fromCharCode(65 + j)) fail(`${w}.moznosti[${j}].klic must be "${String.fromCharCode(65 + j)}" — options are A, B, C… from A in every round (got ${JSON.stringify(k)})`); });
    if (!keys.includes(b.doporuceni)) fail(`${w}.doporuceni '${b.doporuceni}' is not the key of one of its options (${keys.join(', ')})`);
    const minule = arr(b.minule, `${w}.minule`).map((s, k) => ({ popisek: str(s.popisek, `${w}.minule[${k}].popisek`), soubory: shotFiles(s.shot, `${w}.minule[${k}]`, shotsOnly[s.shot]) }));
    const pravidla = arr(b.soulad_s_pravidly, `${w}.soulad_s_pravidly`).map((r, k) => ({ pravidlo: str(r.pravidlo, `${w}.soulad_s_pravidly[${k}].pravidlo`), jak: str(r.jak, `${w}.soulad_s_pravidly[${k}].jak`) }));
    return {
      id, title: str(b.title, `${w}.title`), otazka: str(b.otazka, `${w}.otazka`), doporuceni: b.doporuceni,
      proc: str(b.proc, `${w}.proc`), soulad_s_pravidly: pravidla, minule,
      moznosti: moznosti.map((m, j) => {
        const mw = `${w}.moznosti[${j}]`;
        const soubory = arr(m.soubory, `${mw}.soubory`);
        for (const f of soubory) {
          if (typeof f !== 'string' || f.startsWith('/') || f.split('/').includes('..')) fail(`${mw}.soubory: '${f}' must be a path inside proto/ (no leading /, no ..)`);
          else if (seen.has(f)) fail(`${mw}.soubory: '${f}' is also listed by ${seen.get(f)} — a file belongs to one option, or to spolecne`);
          else seen.set(f, `${w} option ${m.klic}`);
        }
        const nove = arr(m.nove, `${mw}.nove`).map((x, k) => ({ komponenta: str(x.komponenta, `${mw}.nove[${k}].komponenta`), duvod: str(x.duvod, `${mw}.nove[${k}].duvod`) }));
        return {
          klic: m.klic, nazev: str(m.nazev, `${mw}.nazev`), popis: str(m.popis, `${mw}.popis`), soubory,
          postaveno_z: arr(m.postaveno_z, `${mw}.postaveno_z`).map((c, k) => str(c, `${mw}.postaveno_z[${k}]`)), nove,
          snimky: arr(m.snimky, `${mw}.snimky`).map((s, k) => ({ popisek: str(s.popisek, `${mw}.snimky[${k}].popisek`), shot: s.shot, soubory: shotFiles(s.shot, `${mw}.snimky[${k}]`, shotsOnly[s.shot]) })),
        };
      }),
    };
  });
  return { plan: PLAN, kolo: n.kolo, rozhodnuto, spolecne, body: out };
}

// ── the copy of the app: which files the variants touched, and what they import ──
const RUNTIME = [/(^|\/)node_modules(\/|$)/, /(^|\/)dist(\/|$)/, /(^|\/)dev-dist(\/|$)/, /(^|\/)coverage(\/|$)/, /(^|\/)\.vite(\/|$)/, /(^|\/)vite-cache(\/|$)/, /(^|\/)\.next(\/|$)/, /(^|\/)\.turbo(\/|$)/, /\.log$/, /\.tsbuildinfo$/, /(^|\/)\.git(\/|$)/];
const isRuntime = rel => RUNTIME.some(r => r.test(rel));
function walk(root, rel = '', out = []) {
  for (const e of fs.readdirSync(path.join(root, rel), { withFileTypes: true })) {
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (isRuntime(r) || e.isSymbolicLink()) continue;
    if (e.isDirectory()) walk(root, r, out); else if (e.isFile()) out.push(r);
  }
  return out;
}
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
export function manifest(root) { return Object.fromEntries(walk(root).map(r => [r, sha(path.join(root, r))])); }

function changedFiles(protoDir, man) {
  const now = manifest(protoDir), out = [];
  for (const [r, h] of Object.entries(now)) if (man[r] !== h) out.push({ file: r, kind: man[r] ? 'changed' : 'added' });
  for (const r of Object.keys(man)) if (!(r in now)) out.push({ file: r, kind: 'deleted' });
  return out;
}

// path aliases from tsconfig.json / jsconfig.json compilerOptions.paths (+ baseUrl)
function aliases(protoDir) {
  for (const f of ['tsconfig.app.json', 'tsconfig.json', 'jsconfig.json']) {
    const p = path.join(protoDir, f);
    if (!fs.existsSync(p)) continue;
    let j; try { j = JSON.parse(fs.readFileSync(p, 'utf8').replace(/\/\*[\s\S]*?\*\/|(^|[^:])\/\/.*$/gm, '$1').replace(/,\s*([}\]])/g, '$1')); } catch { continue; }
    const co = j.compilerOptions || {}, base = path.join(protoDir, co.baseUrl || '.');
    const map = Object.entries(co.paths || {}).map(([k, v]) => ({ from: k.replace(/\*$/, ''), to: path.join(base, String(v[0] || '').replace(/\*$/, '')) }));
    if (map.length) return map;
  }
  return [];
}
const EXT = ['', '.tsx', '.ts', '.jsx', '.js', '.vue', '.svelte', '/index.tsx', '/index.ts', '/index.jsx', '/index.js'];
function resolveImport(spec, fromFile, protoDir, al) {
  let base = null;
  if (spec.startsWith('.')) base = path.resolve(path.dirname(fromFile), spec);
  else { const a = al.find(x => spec.startsWith(x.from)); if (a) base = path.join(a.to, spec.slice(a.from.length)); }
  if (!base) return null;
  for (const e of EXT) { const f = base + e; if (fs.existsSync(f) && fs.statSync(f).isFile()) return f; }
  return null;
}
// static ESM imports: names → resolved file (default and named; `import X, { A as B } from '…'`)
function imports(file, protoDir, al) {
  const src = fs.readFileSync(file, 'utf8'), out = [];
  const re = /import\s+(?:type\s+)?([\w$]+)?\s*,?\s*(?:\{([^}]*)\})?\s*from\s*['"]([^'"]+)['"]/g;
  for (let m; (m = re.exec(src));) {
    const target = resolveImport(m[3], file, protoDir, al);
    const names = [];
    if (m[1]) names.push(m[1]);
    if (m[2]) for (const part of m[2].split(',')) { const p = part.trim().replace(/^type\s+/, ''); if (p) names.push((p.split(/\s+as\s+/)[1] || p).trim()); }
    for (const n of names) out.push({ name: n, spec: m[3], target });
  }
  return out;
}

function codeChecks(v) {
  const protoDir = path.join(DIR, 'proto'), manFile = path.join(DIR, 'proto-manifest.json');
  if (!fs.existsSync(manFile)) {
    for (const b of v.body) for (const m of b.moznosti) if (m.soubory.length || m.postaveno_z.length || m.nove.length)
      fail(`body ${b.id} option ${m.klic} names files or components, but there is no copy of the app to check them against — run: aid-companion.sh proto --plan ${PLAN}`);
    return;
  }
  const man = readJson(manFile, 'proto-manifest.json');
  const components = path.resolve(PROJECT, UI.components || UI.dir || '.');
  const compRel = path.relative(path.resolve(PROJECT, UI.dir || '.'), components);   // ui.components inside the copy
  const compInProto = path.join(protoDir, compRel);
  const owner = new Map();
  for (const f of v.spolecne) owner.set(f, null);
  for (const b of v.body) for (const m of b.moznosti) for (const f of m.soubory) owner.set(f, { b, m });
  for (const c of changedFiles(protoDir, man)) {
    if (!owner.has(c.file)) { fail(`proto/${c.file} is ${c.kind} but no option lists it in soubory and it is not in spolecne`); continue; }
    const o = owner.get(c.file);
    if (o && c.kind === 'added' && /\.(tsx|jsx|vue|svelte)$/.test(c.file) && !o.m.nove.some(n => n.komponenta === c.file))
      fail(`body ${o.b.id} option ${o.m.klic}: proto/${c.file} is a new component file — list it in nove[] (komponenta: "${c.file}", duvod: why no shared component fits)`);
  }
  const al = aliases(protoDir);
  for (const b of v.body) for (const m of b.moznosti) {
    if (!m.postaveno_z.length) continue;
    const found = new Map();
    // the option's own files and the shared ones: variants of ONE existing page live in that page behind ?v=
    // (spolecne), and their components are imported there (AC9 19. 10. 2026: the rules could not both hold)
    for (const f of [...m.soubory, ...v.spolecne]) {
      const abs = path.join(protoDir, f);
      if (!fs.existsSync(abs) || !/\.(tsx|ts|jsx|js|vue|svelte)$/.test(f)) continue;
      for (const im of imports(abs, protoDir, al)) if (!found.has(im.name) || im.target) found.set(im.name, im);
    }
    for (const c of m.postaveno_z) {
      const im = found.get(c);
      if (!im) fail(`body ${b.id} option ${m.klic}: postaveno_z names ${c}, but no file of the option or of spolecne imports it (soubory: ${m.soubory.join(', ') || 'none'})`);
      else if (!im.target) fail(`body ${b.id} option ${m.klic}: ${c} is imported from '${im.spec}', which does not resolve to a file (relative paths, tsconfig/jsconfig paths and index files are followed)`);
      else if (!path.resolve(im.target).startsWith(path.resolve(compInProto) + path.sep)) fail(`body ${b.id} option ${m.klic}: ${c} comes from ${path.relative(protoDir, im.target)}, which is not under ui.components (${compRel || '.'})`);
    }
  }
}

// ── the page itself ──────────────────────────────────────────────────────────
function render(v) {
  const page = `navrh-${v.kolo}.html`;
  const data = { ...v, page, zobrazeni: VIEWPORTS.map(x => x.name) };
  const tpl = fs.readFileSync(path.join(HERE, 'kit-page.html'), 'utf8');
  const html = tpl.replace('__TITLE__', `${PLAN} · kolo ${v.kolo}`.replace(/[<&]/g, ''))
    .replace('__DATA__', () => JSON.stringify(data).replace(/</g, '\\u003c'));
  fs.writeFileSync(path.join(DIR, page), html);
  return page;
}

async function pageCheck(page) {
  const b = await browser();
  try {
    const url = 'file://' + path.join(DIR, page);
    for (const [w, h, full] of [[1440, 900, true], [390, 844, false]]) {
      const p = await b.newPage({ viewport: { width: w, height: h } });
      await p.goto(url); await p.waitForTimeout(150);
      const r = await p.evaluate((full) => {
        const se = document.scrollingElement, bad = [];
        if (se.scrollWidth > innerWidth + 1) bad.push(`the page is ${se.scrollWidth}px wide in a ${innerWidth}px window (scrolls sideways)`);
        if (full && se.scrollHeight > innerHeight + 1) bad.push(`the page is ${se.scrollHeight}px tall in a ${innerHeight}px window (the page itself scrolls; only a column may)`);
        if (full) for (const sel of ['#nav .nav', '.opt', '#send', '#note', '#prev', '#next']) {
          for (const el of document.querySelectorAll(sel)) {
            const q = el.getBoundingClientRect(); if (!q.width || !q.height) { bad.push(`${sel} is not visible`); continue; }
            const host = el.closest('.rs,.l') || document.body; const hr = host.getBoundingClientRect();
            if (q.top < hr.top - 1 || q.top > hr.bottom) continue;   // scrolled away inside its column is fine
            const at = document.elementFromPoint(q.left + Math.min(q.width / 2, 20), q.top + Math.min(q.height / 2, 10));
            if (at && !el.contains(at) && !at.contains(el)) bad.push(`${sel} is covered by ${at.tagName.toLowerCase()}${at.id ? '#' + at.id : ''}`);
          }
        }
        const img = document.getElementById('img');
        if (img && !img.hidden && !(img.complete && img.naturalWidth)) bad.push(`the preview image ${img.getAttribute('src')} does not load`);
        return bad;
      }, full);
      r.forEach(x => fail(`page ${w}x${h}: ${x}`));
      await p.screenshot({ path: path.join(DIR, `check-${w}x${h}.png`) });
      await p.close();
    }
  } finally { await b.close(); }
}

// proposal.json for the brainstorm's design gate (aid_ui_proposal_check): today = the first point's
// minule shot, proposed = its recommended option's first shot, per owed viewport.
function proposal(v) {
  const st = path.join(ENV.AID_COMPANION_STATE, '.aid-o/work/brainstorm', PLAN);
  if (!fs.existsSync(st)) return null;
  const withShots = v.body.find(b => b.moznosti.some(m => m.snimky.length));
  if (!withShots) return null;
  const rec = withShots.moznosti.find(m => m.klic === withShots.doporuceni) || withShots.moznosti[0];
  const today = withShots.minule[0], abs = rel => rel ? path.join(DIR, rel) : null;
  const live = !!today && VIEWPORTS.every(vp => today.soubory[vp.name]);
  const out = {
    basis: live ? 'live-screen' : 'design-system', live_baseline: live,
    marked: live ? null : 'NO LIVE BASELINE — the proposal has no capture of today (a new screen, or the first round shows no current state)',
    screen: null, fixture_data: fs.existsSync(path.join(DIR, 'mocks.json')) ? path.join(DIR, 'mocks.json') : null,
    production_data_used: false, responsive: VIEWPORTS.length > 1,
    viewports: VIEWPORTS.map(vp => ({ name: vp.name, width: vp.width, height: vp.height,
      baseline: live ? abs(today.soubory[vp.name]) : null, page: null,
      proposed: abs((rec.snimky.find(s => s.soubory[vp.name]) || { soubory: {} }).soubory[vp.name]) })),
    design_system: {}, brief: null, companion_kit: { navrh: path.join(DIR, 'navrh.json'), kolo: v.kolo },
    created_at: new Date().toISOString(),
  };
  fs.writeFileSync(path.join(st, 'proposal.json'), JSON.stringify(out, null, 2));
  return path.join(st, 'proposal.json');
}

async function show() {
  const f = path.join(DIR, 'navrh.json');
  if (!fs.existsSync(f)) die(`no ${f} — write it (the format is in skills/visual-companion/SKILL.md)`);
  const shotsSpec = fs.existsSync(path.join(DIR, 'shots.json')) ? readJson(path.join(DIR, 'shots.json'), 'shots.json') : { shots: [] };
  const only = Object.fromEntries((shotsSpec.shots || []).filter(s => s.only).map(s => [s.name, s.only]));
  const v = validate(readJson(f, 'navrh.json'), only); stop();
  codeChecks(v); stop();
  const page = render(v);
  await pageCheck(page); stop();
  const prop = proposal(v);
  let url = null;
  try { url = JSON.parse(fs.readFileSync(path.join(DIR, 'server.json'), 'utf8')).url; } catch {}
  console.log(JSON.stringify({ page: path.join(DIR, page), url: url ? `${url}/` : null, proposal: prop,
    check: [path.join(DIR, 'check-1440x900.png'), path.join(DIR, 'check-390x844.png')],
    next: url ? 'give the PM the url; then aid-companion.sh answers --plan ' + PLAN : 'start the server: aid-companion.sh up --plan ' + PLAN }));
}

const step = process.argv[2];
if (step === 'show') await show();
else if (step === 'proto' || step === 'shots') { const m = await import('./kit-' + step + '.mjs'); await m.run({ DIR, PLAN, PROJECT, UI, VIEWPORTS, die, playwright, browser, manifest }); }
else die(`kit.mjs: unknown step ${step}`);
