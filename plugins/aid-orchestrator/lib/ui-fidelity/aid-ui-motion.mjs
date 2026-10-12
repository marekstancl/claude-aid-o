// aid-ui-motion.mjs — observe the motion of a page at runtime: what animates, where, on what.
//   node aid-ui-motion.mjs <url> <out.json> [--max-hover 60] [--dir-sha256 <sha>] [--settle-ms 8000] [--pages N]
//   --pages N: after the start page, up to N same-site sub-pages (the first N distinct paths linked from
//   nav, header, footer, then anywhere; PM 11. 10. 2026, 2B: the motion of the whole reference, not only its
//   home) get the load, scroll and hover scenarios too; every item carries `pages` = where it was seen.
//   node aid-ui-motion.mjs --dir <folder> <out.json> [--max-hover 60] [--settle-ms 8000]
//     (serves the folder itself on a free loopback port and records its sha: a prototype, a build)
// One tool for three subjects: the PM's reference site (step 4), each direction prototype
// (step 5) and the built site (step 6, the gate's motion_fidelity row). Nothing is read off
// the CSS of a foreign site and guessed: every item below was SEEN to run, in a scenario the
// tool drove, on an element whose position it measured. What it could not see is listed under
// `coverage`, never invented.
// Scenarios, in this order, in one browser context (Chromium 1440x900, DPR 1):
//   load       the first navigation; everything that starts within --settle-ms (default 8 s)
//              or until 1 s passes with no new animation
//   load2      a reload in the same context: an animation seen at load but not here is
//              frequency "first_load_only" (sessionStorage/cookie gated), else "every_load"
//   scroll     scroll down one window at a time to the end, 600 ms standing each
//   hover      hover, then focus, each visible link, button, role=button, submit and
//              cursor:pointer element (first viewport, then after scrolling), max --max-hover
//   page       click the first same-site link to another path: motion libraries in globals
//              (barba, swup, taxi), what animated while leaving, what animated on arrival
// Events: animationstart and transitionrun on the window (capture phase), from an init script
// installed before any page script, so the page's own early animations are not missed.
// Each item: name (keyframes) or property (transition), selector = tag#id.cls (3 classes),
// where = hero (top edge within the first viewport at the time it started) | below | overlay
// (position:fixed covering >= 90 % of the window), duration/delay/iteration from the computed
// style of the element at that moment, scenario, and for keyframes the frequency.
// Identity: keyframes by name; transitions by (property, scenario) — the same canonical key
// the inventory (aid-ui-motion.py) uses.
// Exit: 0 written, 1 the page did not load, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import http from 'node:http';

const argv = process.argv.slice(2);
const opt = { maxHover: 60, dirSha: null, settle: 8000, dir: null };
for (let i = 0; i < argv.length;) {
  if (argv[i] === '--max-hover') { opt.maxHover = parseInt(argv[i + 1], 10); argv.splice(i, 2); }
  else if (argv[i] === '--dir-sha256') { opt.dirSha = argv[i + 1]; argv.splice(i, 2); }
  else if (argv[i] === '--dir') { opt.dir = argv[i + 1]; argv.splice(i, 2); }
  else if (argv[i] === '--settle-ms') { opt.settle = parseInt(argv[i + 1], 10); argv.splice(i, 2); }
  else if (argv[i] === '--pages') { opt.pages = Math.max(0, parseInt(argv[i + 1], 10) || 0); argv.splice(i, 2); }
  else i++;
}
// --dir <folder>: the tool serves the folder itself on a free loopback port and records the folder's
// sha (the same digest aid-ui-motion.py dirsha prints), so the record is bound to what was observed;
// the url argument is then omitted (a direction prototype, a built site)
let url, out, served = null;
if (opt.dir) {
  const dir = path.resolve(opt.dir);
  if (!fs.statSync(dir, { throwIfNoEntry: false })?.isDirectory()) { console.error(`aid-ui-motion: no directory ${opt.dir}`); process.exit(2); }
  out = argv[0];
  if (!out) { console.error('usage: aid-ui-motion.mjs --dir <folder> <out.json> [--max-hover N] [--settle-ms N]'); process.exit(2); }
  const h = crypto.createHash('sha256');
  // the same order as os.walk in aid-ui-motion.py dirsha: a folder's files (sorted), then its subfolders (sorted)
  const walk = d => { const es = fs.readdirSync(d, { withFileTypes: true }).filter(e => !e.isSymbolicLink()).sort((a, b) => a.name < b.name ? -1 : 1);
    for (const e of es) if (e.isFile()) { const p = path.join(d, e.name); h.update(path.relative(dir, p).split(path.sep).join('/') + '\0' + crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex') + '\n'); }
    for (const e of es) if (e.isDirectory()) walk(path.join(d, e.name)); };
  walk(dir); opt.dirSha = h.digest('hex');
  const MIME = { html: 'text/html; charset=utf-8', css: 'text/css', js: 'text/javascript', mjs: 'text/javascript', json: 'application/json', svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif', ico: 'image/x-icon', woff2: 'font/woff2', woff: 'font/woff', txt: 'text/plain', xml: 'application/xml', webmanifest: 'application/manifest+json' };
  served = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
    const f = path.resolve(dir, '.' + p);
    if (!f.startsWith(dir + path.sep) && f !== dir) { res.writeHead(403); return res.end(); }
    let st = fs.statSync(f, { throwIfNoEntry: false });
    let file = f; if (st?.isDirectory()) { file = path.join(f, 'index.html'); st = fs.statSync(file, { throwIfNoEntry: false }); }
    if (!st?.isFile()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).slice(1).toLowerCase()] || 'application/octet-stream', 'Content-Length': st.size });
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(r => served.listen(0, '127.0.0.1', r));
  url = `http://127.0.0.1:${served.address().port}/`;
} else {
  [url, out] = argv;
  if (!url || !out || !/^https?:\/\//.test(url)) { console.error('usage: aid-ui-motion.mjs <url> <out.json> [--max-hover N] [--dir-sha256 <sha>] [--settle-ms N]  |  --dir <folder> <out.json>'); process.exit(2); }
}

const VW = 1440, VH = 900;
const INIT = () => {
  // runs before any page script, in every document of the context
  window.__aidScenario = window.__aidScenario || 'load';
  window.__aidEvents = [];
  const sel = e => {
    if (!(e instanceof Element)) return e === document.documentElement ? 'html' : 'window';
    const cls = [...e.classList].slice(0, 3).map(c => '.' + c).join('');
    return e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + cls;
  };
  const ms = v => { const parts = String(v || '0s').split(','); return Math.max(0, ...parts.map(x => { x = x.trim(); return x.endsWith('ms') ? parseFloat(x) : parseFloat(x) * 1000; })); };
  const where = e => {
    if (!(e instanceof Element)) return 'unknown';
    const cs = getComputedStyle(e), r = e.getBoundingClientRect();
    if (cs.position === 'fixed' && r.width >= innerWidth * 0.9 && r.height >= innerHeight * 0.9) return 'overlay';
    let top = 0, n = e; while (n && n instanceof HTMLElement) { top += n.offsetTop; n = n.offsetParent; }
    if (!(e instanceof HTMLElement)) top = r.top + scrollY;   // svg and friends: the viewport rect
    if (!isFinite(top)) return 'unknown';
    return top < innerHeight ? 'hero' : 'below';
  };
  const rec = (kind, ev) => {
    const e = ev.target; const cs = e instanceof Element ? getComputedStyle(e) : null;
    const item = { kind, scenario: window.__aidScenario, page: location.pathname, selector: sel(e), where: where(e), t: Math.round(performance.now()),
      intro: e instanceof Element && e.hasAttribute('data-aid-intro') };
    if (kind === 'keyframes') {
      item.name = ev.animationName;
      if (cs) { const names = cs.animationName.split(',').map(s => s.trim()); const i = Math.max(0, names.indexOf(ev.animationName));
        const pick = v => (String(v).split(',')[i] || String(v).split(',')[0] || '').trim();
        item.duration_ms = ms(pick(cs.animationDuration)); item.delay_ms = ms(pick(cs.animationDelay));
        const it = pick(cs.animationIterationCount); item.iteration = it === 'infinite' ? 'infinite' : Number(it) || 1; }
    } else { item.property = ev.propertyName; if (cs) item.duration_ms = ms(cs.transitionDuration); }
    window.__aidEvents.push(item);
  };
  window.addEventListener('animationstart', ev => rec('keyframes', ev), true);
  window.addEventListener('transitionrun', ev => rec('transition', ev), true);
  // motion a script drives by hand (barba, gsap): inline style changes of opacity/transform/clip
  const seen = new Map();
  const mo = new MutationObserver(ms => { for (const m of ms) {
    const e = m.target; if (!(e instanceof Element)) continue;
    const st = e.getAttribute('style') || ''; const prop = /transform/.test(st) ? 'transform' : /opacity/.test(st) ? 'opacity' : /clip-path/.test(st) ? 'clip-path' : null;
    if (!prop) continue;
    const key = window.__aidScenario + '|' + prop + '|' + sel(e); const n = (seen.get(key) || 0) + 1; seen.set(key, n);
    if (n === 1) window.__aidEvents.push({ kind: 'js', scenario: window.__aidScenario, page: location.pathname, selector: sel(e), where: where(e), property: prop, t: Math.round(performance.now()) });
  } });
  const start = () => mo.observe(document.documentElement, { attributes: true, attributeFilter: ['style'], subtree: true });
  if (document.documentElement) start(); else document.addEventListener('DOMContentLoaded', start, { once: true });
};

const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1, reducedMotion: 'no-preference' });
await ctx.addInitScript(INIT);
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(`pageerror: ${String(e.message).slice(0, 160)}`));

const take = async () => { try { return await page.evaluate(() => { const e = window.__aidEvents; window.__aidEvents = []; return e; }); } catch { return []; } };
// a runtime snapshot of document.getAnimations(): Web Animations the page drives by script (no CSS
// event fires for them) land under js_motion with property `waapi`; a CSS animation's real
// duration/iterations come from here too when the computed style could not say
const snapshot = async scenario => { try { return await page.evaluate(sc => {
  const sel = e => { if (!(e instanceof Element)) return 'window'; const cls = [...e.classList].slice(0, 3).map(c => '.' + c).join(''); return e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + cls; };
  const out = [];
  for (const a of document.getAnimations()) {
    const tg = a.effect && a.effect.target; const tm = a.effect && a.effect.getTiming ? a.effect.getTiming() : {};
    const kind = a.constructor && a.constructor.name;
    if (kind === 'Animation') out.push({ kind: 'js', scenario: sc, page: location.pathname, selector: sel(tg), where: 'unknown', property: 'waapi', duration_ms: typeof tm.duration === 'number' ? tm.duration : null, iteration: tm.iterations === Infinity ? 'infinite' : tm.iterations });
    else if (kind === 'CSSAnimation' && a.animationName) out.push({ kind: 'timing', name: a.animationName, duration_ms: typeof tm.duration === 'number' ? tm.duration : null, iteration: tm.iterations === Infinity ? 'infinite' : tm.iterations });
  }
  return out; }, scenario); } catch { return []; } };
const timings = new Map();   // keyframe name -> {duration_ms, iteration} from getAnimations()
const absorb = snap => { for (const s of snap) { if (s.kind === 'timing') { if (!timings.has(s.name)) timings.set(s.name, s); } else all.push(s); } };
const setScenario = async s => { try { await page.evaluate(x => { window.__aidScenario = x; }, s); } catch { /* navigating */ } };
// wait until the budget passed, or 1 s with no new event (whichever first), collecting
const settle = async (budget, whole = false) => {
  const got = []; let quiet = 0; const t0 = Date.now();
  while (Date.now() - t0 < budget) {
    await page.waitForTimeout(250);
    const e = await take(); if (e.length) { got.push(...e); quiet = 0; } else quiet += 250;
    if (!whole && quiet >= 1000 && Date.now() - t0 >= 1500) break;
  }
  return got;
};
const goto = async (u, scenario) => {
  await ctx.addInitScript(s => { window.__aidScenario = s; }, scenario);
  const r = await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
  if (!r || r.status() >= 400) throw new Error(`HTTP ${r ? r.status() : 'none'} for ${u}`);
};

let loadEvents, load2Events;
const all = [];
try {
  await goto(url, 'load');
  loadEvents = await settle(opt.settle, true); all.push(...loadEvents); absorb(await snapshot('load'));
  await goto(url, 'load2');
  load2Events = await settle(opt.settle, true); all.push(...load2Events); absorb(await snapshot('load2'));
} catch (e) { console.error(`aid-ui-motion: ${e.message}`); await browser.close(); process.exit(1); }

// coverage: what the tool cannot see
const coverage = await page.evaluate(() => {
  const sheets = []; for (const sh of document.styleSheets) { let ok = true; try { void sh.cssRules; } catch { ok = false; } sheets.push({ href: sh.href || 'inline', readable: ok }); }
  const iframes = [...document.querySelectorAll('iframe')].map(f => f.src || 'inline');
  let shadow = 0; for (const e of document.querySelectorAll('*')) if (e.shadowRoot) shadow++;
  const scripts = [...document.scripts].map(s => s.src).filter(Boolean).map(s => s.split('/').pop().split('?')[0]);
  const libs = [...new Set(scripts.filter(n => /gsap|scrolltrigger|lenis|locomotive|aos|swiper|anime|framer|motion|lottie|barba|swup|taxi|smooth/i.test(n)))];
  const globals = ['gsap', 'ScrollTrigger', 'Lenis', 'LocomotiveScroll', 'AOS', 'Swiper', 'anime', 'lottie', 'barba', 'Swup', 'taxi'].filter(g => g in window);
  if (document.querySelector('[data-scroll-container], .c-scrollbar, html.has-scroll-smooth') && !globals.includes('LocomotiveScroll')) globals.push('locomotive-scroll (DOM)');
  if (document.querySelector('html.lenis') && !globals.includes('Lenis')) globals.push('lenis (DOM)');
  if (document.querySelector('[data-barba]') && !globals.includes('barba')) globals.push('barba (DOM)');
  return { stylesheets_unreadable: sheets.filter(s => !s.readable).map(s => s.href), stylesheets: sheets.length, iframes_skipped: iframes, shadow_roots_not_traversed: shadow, libs, globals,
    height: document.documentElement.scrollHeight };
});

// scroll: by the wheel, a viewport at a time, to the end (smooth-scroll libraries see real wheel events)
const scrollPass = async () => {
  await setScenario('scroll');
  const h = await page.evaluate(() => document.documentElement.scrollHeight);
  const n = Math.min(80, Math.ceil(h / VH));
  await page.mouse.move(VW / 2, VH / 2);
  for (let i = 1; i <= n; i++) { await page.mouse.wheel(0, VH); await page.waitForTimeout(600); }
  all.push(...await take()); absorb(await snapshot('scroll'));
  await page.mouse.wheel(0, -VH * n); await page.evaluate(() => scrollTo(0, 0)); await page.waitForTimeout(600); await take();
  return n;
};
// hover + focus over sampled targets (half above the fold, the rest spread below)
const hoverPass = async max => {
const targets = await page.evaluate(max => {
  const vis = e => { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); return r.width >= 2 && r.height >= 2 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
  const els = [...document.querySelectorAll('a, button, [role=button], input[type=submit], input[type=button], [tabindex]')];
  for (const e of document.querySelectorAll('body *')) if (getComputedStyle(e).cursor === 'pointer' && !els.includes(e)) els.push(e);
  // over the cap: half from the first viewport, the rest spread evenly over the page below it, so motion
  // below the fold (footer links, cards) is hovered too
  const seen = els.filter(vis); const top = seen.filter(e => e.getBoundingClientRect().top + scrollY < innerHeight), below = seen.filter(e => !top.includes(e));
  let pick = seen;
  if (seen.length > max) { const nt = Math.min(top.length, Math.ceil(max / 2)); const nb = max - nt; const step = Math.max(1, below.length / Math.max(1, nb));
    pick = top.slice(0, nt).concat(below.filter((_, i) => Math.floor(i % step) === 0).slice(0, nb)); }
  const tags = pick.map((e, n) => { const t = `h${n}`; e.setAttribute('data-aid-hover', t); return t; });
  return tags;
}, max);
for (const t of targets) {
  const loc = page.locator(`[data-aid-hover="${t}"]`).first();
  try {
    await loc.scrollIntoViewIfNeeded({ timeout: 2000 });
    await setScenario('hover'); await loc.hover({ timeout: 2000, force: true }); await page.waitForTimeout(350);
    await page.mouse.move(0, 0); await page.waitForTimeout(250);
    await setScenario('focus'); await loc.focus({ timeout: 1000 }); await page.waitForTimeout(300);
  } catch { /* detached or covered: skipped */ }
}
await page.keyboard.press('Tab').catch(() => {});
all.push(...(await take()).filter(e => e.scenario === 'hover' || e.scenario === 'focus')); absorb(await snapshot('hover'));
return targets;
};
const steps = await scrollPass();
const targets = await hoverPass(opt.maxHover);

// page transition: the first same-site link to another path
const link = await page.evaluate(() => {
  const here = new URL(location.href);
  for (const a of document.querySelectorAll('a[href]')) {
    let u; try { u = new URL(a.getAttribute('href'), location.href); } catch { continue; }
    if (u.origin !== here.origin || u.pathname === here.pathname || u.hash || /^(mailto|tel):/.test(u.protocol)) continue;
    const r = a.getBoundingClientRect(); if (r.width < 2 || r.height < 2) continue;
    a.setAttribute('data-aid-page', '1'); return u.href;
  }
  return null;
});
const pageT = { link, libs: coverage.globals.filter(g => /barba|swup|taxi/i.test(g)), leave: [], arrive: [], arrived_at: null };
if (link) {
  await setScenario('page');
  // the next document (if a real navigation happens) records under page-arrive
  await ctx.addInitScript(s => { window.__aidScenario = s; }, 'page-arrive');
  try {
    await page.evaluate(() => scrollTo(0, 0));
    const nav = page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 8000 }).catch(() => null);
    await page.locator('[data-aid-page="1"]').first().click({ timeout: 3000, force: true });
    // poll across the navigation: what the leaving document recorded under `page`, what the
    // arriving one recorded under `page-arrive` (a library may route without a navigation)
    const t0 = Date.now(); const got = [];
    while (Date.now() - t0 < 3500) { got.push(...await take()); await page.waitForTimeout(100); }
    await nav;
    got.push(...await settle(1500)); got.push(...await snapshot('page-arrive'));
    pageT.leave = got.filter(x => x.scenario === 'page');
    pageT.arrive = got.filter(x => x.scenario === 'page-arrive');
    pageT.arrived_at = await page.evaluate(() => location.href).catch(() => null);
  } catch (e) { errors.push(`page: ${String(e.message).slice(0, 120)}`); }
}

// sub-pages (--pages N): load, scroll and hover on each; the record says which page saw what
const subpages = [];
if (opt.pages > 0) {
  try { await goto(url, 'load'); await settle(1500); await take(); } catch (e) { errors.push(`pages: ${String(e.message).slice(0, 120)}`); }
  const links = await page.evaluate(max => {
    const here = new URL(location.href); const seen = new Set([here.pathname]); const out = [];
    for (const a of document.querySelectorAll('nav a[href], header a[href], footer a[href], a[href]')) {
      let u; try { u = new URL(a.getAttribute('href'), location.href); } catch { continue; }
      if (u.origin !== here.origin || seen.has(u.pathname) || u.hash || /^(mailto|tel|javascript):/.test(u.protocol)) continue;
      seen.add(u.pathname); out.push(u.origin + u.pathname); if (out.length >= max) break;
    }
    return out;
  }, opt.pages).catch(() => []);
  for (const sub of links) {
    const rec = { url: sub, ok: false, keyframes: 0, transitions: 0, error: null };
    try {
      await goto(sub, 'load'); const ev = await settle(opt.settle, true); all.push(...ev); absorb(await snapshot('load'));
      rec.keyframes = ev.filter(e => e.kind === 'keyframes').length; rec.transitions = ev.filter(e => e.kind === 'transition').length;
      await scrollPass(); await hoverPass(Math.min(opt.maxHover, 20)); rec.ok = true;
    } catch (e) { rec.error = String(e.message).slice(0, 120); }
    subpages.push(rec);
  }
}

await browser.close();
if (served) served.close();

// canonical items
const first = new Set(loadEvents.filter(e => e.kind === 'keyframes').map(e => e.name));
// (js items are kept in `all` too and summarised below)
const second = new Set(load2Events.filter(e => e.kind === 'keyframes').map(e => e.name));
const kf = new Map();
for (const e of all.filter(e => e.kind === 'keyframes')) {
  const k = kf.get(e.name) || { name: e.name, scenarios: new Set(), wheres: new Set(), selectors: new Set(), pages: new Set(), duration_ms: 0, delay_ms: 0, iteration: 1, intro: false, count: 0 };
  k.scenarios.add(e.scenario === 'load2' ? 'load' : e.scenario); k.wheres.add(e.where); k.selectors.add(e.selector); k.pages.add(e.page || '/'); k.count++;
  k.duration_ms = Math.max(k.duration_ms, e.duration_ms || 0); k.delay_ms = Math.max(k.delay_ms, e.delay_ms || 0);
  if (e.iteration === 'infinite') k.iteration = 'infinite'; else if (k.iteration !== 'infinite') k.iteration = Math.max(k.iteration, e.iteration || 1);
  k.intro = k.intro || e.intro; kf.set(e.name, k);
}
const keyframes = [...kf.values()].map(k => ({ name: k.name, scenarios: [...k.scenarios].sort(), where: [...k.wheres].sort(), selectors: [...k.selectors].slice(0, 6), pages: [...k.pages].sort(),
  duration_ms: k.duration_ms || (timings.get(k.name) || {}).duration_ms || 0, delay_ms: k.delay_ms,
  iteration: k.iteration === 1 && timings.has(k.name) && timings.get(k.name).iteration ? timings.get(k.name).iteration : k.iteration, intro: k.intro, count: k.count,
  frequency: k.scenarios.has('load') ? (first.has(k.name) && !second.has(k.name) ? 'first_load_only' : (first.has(k.name) ? 'every_load' : 'unknown')) : null }))
  .sort((a, b) => a.scenarios.join() < b.scenarios.join() ? -1 : a.scenarios.join() > b.scenarios.join() ? 1 : a.name < b.name ? -1 : 1);
const tr = new Map();
for (const e of all.filter(e => e.kind === 'transition')) {
  const sc = e.scenario === 'load2' ? 'load' : e.scenario;   // the second load is the load scenario too
  const key = `${e.property}@${sc}`;
  const t = tr.get(key) || { property: e.property, scenario: sc, selectors: new Set(), wheres: new Set(), pages: new Set(), duration_ms: 0, count: 0 };
  t.selectors.add(e.selector); t.wheres.add(e.where); t.pages.add(e.page || '/'); t.duration_ms = Math.max(t.duration_ms, e.duration_ms || 0); t.count++; tr.set(key, t);
}
const transitions = [...tr.values()].map(t => ({ property: t.property, scenario: t.scenario, selectors: [...t.selectors].slice(0, 6), where: [...t.wheres].sort(), pages: [...t.pages].sort(), duration_ms: t.duration_ms, count: t.count }))
  .sort((a, b) => (a.scenario + a.property) < (b.scenario + b.property) ? -1 : 1);
const js = new Map();
for (const e of [...all, ...pageT.leave, ...pageT.arrive].filter(e => e.kind === 'js')) {
  const sc = e.scenario === 'load2' ? 'load' : e.scenario; const key = `${e.property}@${sc}`;
  const j = js.get(key) || { property: e.property, scenario: sc, selectors: new Set(), wheres: new Set(), pages: new Set(), count: 0 };
  j.selectors.add(e.selector); j.wheres.add(e.where); j.pages.add(e.page || '/'); j.count++; js.set(key, j);
}
const js_motion = [...js.values()].map(j => ({ property: j.property, scenario: j.scenario, selectors: [...j.selectors].slice(0, 6), where: [...j.wheres].sort(), pages: [...j.pages].sort(), count: j.count }))
  .sort((a, b) => (a.scenario + a.property) < (b.scenario + b.property) ? -1 : 1);
const tag = e => e.kind === 'keyframes' ? `keyframes:${e.name}@${e.selector}` : e.kind === 'js' ? `js:${e.property}@${e.selector}` : `transition:${e.property}@${e.selector}`;
const pageItem = { link: pageT.link, libs: pageT.libs, arrived_at: pageT.arrived_at, leave: [...new Set(pageT.leave.map(tag))], arrive: [...new Set(pageT.arrive.map(tag))] };
pageItem.observed = Boolean(pageT.libs.length || pageItem.leave.length || pageItem.arrive.length);

const record = { tool: 'aid-ui-motion', version: 1, url, observed_at: new Date().toISOString(), viewport: { width: VW, height: VH, dpr: 1 },
  settle_ms: opt.settle, dir_sha256: opt.dirSha, keyframes, transitions, js_motion, page: pageItem, pages: subpages, libs: [...new Set([...coverage.libs, ...coverage.globals])],
  coverage: { stylesheets: coverage.stylesheets, stylesheets_unreadable: coverage.stylesheets_unreadable, iframes_skipped: coverage.iframes_skipped,
    shadow_roots_not_traversed: coverage.shadow_roots_not_traversed, hover_targets: targets.length, hover_cap: opt.maxHover, scroll_steps: steps,
    pages: subpages.filter(s => s.ok).length, pages_requested: opt.pages, errors } };
record.sha256 = crypto.createHash('sha256').update(JSON.stringify({ ...record, observed_at: null })).digest('hex');
fs.writeFileSync(out + '.tmp', JSON.stringify(record, null, 1)); fs.renameSync(out + '.tmp', out);   // atomic: never a half record
console.log(JSON.stringify({ keyframes: keyframes.length, transitions: transitions.length, page: pageItem.observed, pages: subpages.length, libs: record.libs, below: keyframes.filter(k => k.where.includes('below')).length, hover: transitions.filter(t => t.scenario === 'hover').length + keyframes.filter(k => k.scenarios.includes('hover')).length }));
