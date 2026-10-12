// aid-ui-verify.mjs — the /aid-ui gate checks (P103 Step 7); run through aid-ui-verify.sh.
//
//   node aid-ui-verify.mjs --state <brand-state.json> --checks <checks.json> --site <dir>
//        --base <url> --out <dir> --seo <aid-ui-seo-check.py> [--project <dir>] [--facts <facts.json>]
//
// Matrix = pages (the keys of state.build.fingerprints but _site) x checks.viewports x
// checks.browsers, role and state ""; for variant webapp|pwa also structure.flows[].id (as
// page) x its states x structure.roles (or "") x viewports x browsers; checks.applies narrows a
// check (browsers / viewports subsets, flows false, scope project = one row on the home page)
// and no row is written outside it. One function per
// name in checks.checks (CHECKS below); a name without one, or one without a name, exits 2.
// Every row: {check, page, viewport, browser, role, state, status, detail};
// status pass | fail | warn (warn_only checks) | not_covered (could not run; reason in detail).
// Result <out>/result.json = {run_at, build_id, matrix, rows, fingerprints}: build id and
// fingerprints are the recorded build's, which aid-ui-verify.sh has just recomputed with
// `aid-ui-state.sh build-id` (same files -> same digests). Screenshots: <out>/shots/.
// Browsers: chromium ($CHROME, else Playwright's), webkit (Playwright's); a launch failure
// -> that browser's rows not_covered with the install hint.
// App flows: <project>/.aid-ui/scenarios/<flow id>.mjs, default export
// async ({page, base, role, state, credentials}) that drives the screen into that state and
// throws on failure; credentials = <project>/.aid-ui/test-credentials.json[role] (test
// accounts only). No script -> not_covered.
// SEO (checks seo and ai_search): aid-ui-seo-check.py over the site once, with the project's
// docs/seo/brief.md (page table, AI robot policy), --facts (brand, IČO, domain as --base-url),
// --local when state.variant.local, and --ai --state when state.options.seo (else ai_search is
// N/A); its ai-* findings are the ai_search row (site-wide ones on the home page only), the rest
// the seo row. <out>/seo-summary.json holds the numbers the customer page shows.
// --copy-subject <out.json> (P108): only the copy of every page (copyOf: blocks by kind at 1440 px,
// then what 390 px adds; lang; legal from structure.pages[].legal; sha256 over the block texts) for the copy
// review; no row is written and no result.
// Exit: 0 result written, 1 run error, 2 usage.
import { chromium, webkit } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { unknownClaims } from './aid-ui-facts.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2), opt = {};
for (let i = 0; i < argv.length; i += 2) {
  if (!argv[i].startsWith('--') || argv[i + 1] === undefined) usage();
  opt[argv[i].slice(2)] = argv[i + 1];
}
function usage(m) { console.error('usage: aid-ui-verify.mjs --state <f> --checks <f> --site <dir> --base <url> --out <dir> --seo <py> [--project <dir>] [--facts <f>] [--copy-subject <out.json>]' + (m ? `\n${m}` : '')); process.exit(2); }
for (const k of ['state', 'checks', 'site', 'base', 'out', 'seo']) if (!opt[k]) usage(`missing --${k}`);

const readJson = f => JSON.parse(fs.readFileSync(f, 'utf8'));
const st = readJson(opt.state), ck = readJson(opt.checks);
const site = path.resolve(opt.site), out = path.resolve(opt.out), project = opt.project ? path.resolve(opt.project) : null;
const base = opt.base.endsWith('/') ? opt.base : opt.base + '/';
const fps = st.build?.fingerprints || {};
const pages = Object.keys(fps).filter(p => p !== '_site').sort();
const home = pages.find(p => /^index\.html$/.test(p)) || pages[0];
const VPS = (ck.viewports || []).map(String), BRS = (ck.browsers || []).map(String);
const HEIGHT = { 390: 844, 768: 1024 };
fs.mkdirSync(out, { recursive: true });

// page key -> URL: a/index.html -> /a/, index.html -> /, x.html -> /x.html
const urlOf = p => new URL(p === 'index.html' ? '' : p.endsWith('/index.html') ? p.slice(0, -10) : p, base).href;
const sha = f => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const inside = (root, f) => { const r = path.resolve(root, f); return r === root || r.startsWith(root + path.sep) ? r : null; };
// site file behind a same-origin URL, or null (outside the site or not a file)
function siteFile(u) {
  let x; try { x = new URL(u, base); } catch { return null; }
  if (x.origin !== new URL(base).origin) return null;
  let rel = decodeURIComponent(x.pathname).replace(/^\/+/, '');
  if (rel === '' || rel.endsWith('/')) rel += 'index.html';
  const f = inside(site, rel);
  return f && fs.existsSync(f) && fs.statSync(f).isFile() ? f : null;
}

// ---- site-level runs (once per gate) ------------------------------------------------
function runSeo() {
  const json = path.join(out, 'seo.json');
  const args = [opt.seo, site, '--json', json, '--summary', path.join(out, 'seo-summary.json')];
  const brief = project && path.join(project, 'docs/seo/brief.md');
  if (brief && fs.existsSync(brief)) args.push('--brief', brief);
  if (want('ai_search') && st.options?.seo) args.push('--ai', '--state', opt.state);
  if (opt.facts) {
    args.push('--facts', opt.facts);
    const f = readJson(opt.facts), domain = Array.isArray(f) ? null : f?.domain;
    const d = typeof domain === 'object' ? domain?.value : domain;
    if (typeof d === 'string' && /^https?:\/\//.test(d)) args.push('--base-url', d);
  }
  if (st.variant?.local) args.push('--local');
  const r = spawnSync('python3', args, { encoding: 'utf8' });
  // exit 1 is "a BLOCKER found" only when the report exists; a crash also exits 1
  if ((r.status !== 0 && r.status !== 1) || !fs.existsSync(json))
    return { error: `aid-ui-seo-check.py exit ${r.status}: ${(r.stderr || '').trim().split('\n').pop().slice(0, 200)}` };
  return { findings: readJson(json) };
}
// brand_package: aid-ui-brand-package.py over the project once (required parts derived from the
// variant, options.identity and the contexts of use); one row on the home page, like ai_search.
function runBrandPackage() {
  const json = path.join(out, 'brand-package.json');
  const r = spawnSync('python3', [path.join(HERE, '../../scripts/aid-ui-brand-package.py'), project || '.', '--json', json], { encoding: 'utf8' });
  if ((r.status !== 0 && r.status !== 1) || !fs.existsSync(json))
    return ['not_covered', `aid-ui-brand-package.py exit ${r.status}: ${(r.stderr || '').trim().split('\n').pop().slice(0, 200)}`];
  const b = readJson(json);
  if (b.waived) return ['pass', `PM waiver for: ${b.missing.join('; ')}`];
  return b.missing.length ? ['fail', `missing: ${b.missing.join('; ')}`] : ['pass', `${b.present}/${b.required} required parts, ${b.files} files`];
}
// motion_fidelity (P108): the built site carries the motion of the PM's reference. The gate observes the
// home page itself (aid-ui-motion.mjs: load, second load, scroll, hover, page) and aid-ui-motion.py
// checks the observation against .aid-ui/motion.json (the inventory the PM saw with the directions).
// No picked reference = N/A; a picked reference without an inventory = fail.
function runMotionFidelity() {
  if (!(st.refs || []).some(r => r && r.picked)) return NA('no reference picked: no motion to carry');
  if (!fs.existsSync(path.join(project, '.aid-ui/motion.json'))) return ['fail', 'no .aid-ui/motion.json (aid-ui-motion.py inventory) although a reference is picked'];
  const rec = path.join(out, 'motion.json');
  const home = pages.includes('index.html') ? 'index.html' : pages[0];
  const r1 = spawnSync('node', [path.join(HERE, 'aid-ui-motion.mjs'), urlOf(home), rec, '--settle-ms', '8000'], { encoding: 'utf8' });
  if (r1.status !== 0 || !fs.existsSync(rec)) return ['not_covered', `aid-ui-motion.mjs exit ${r1.status}: ${(r1.stderr || '').trim().split('\n').pop().slice(0, 200)}`];
  const r2 = spawnSync('python3', [path.join(HERE, '../../scripts/aid-ui-motion.py'), 'check', project, '--observed', rec, '--write', path.join(out, 'motion-check.json')], { encoding: 'utf8' });
  const lines = (r2.stdout || '').trim().split('\n');
  if (r2.status === 0) return ['pass', lines[0] || ''];
  if (r2.status === 1) return ['fail', lines.join(' | ').slice(0, 400)];
  return ['not_covered', `aid-ui-motion.py exit ${r2.status}: ${(r2.stderr || '').trim().split('\n').pop().slice(0, 200)}`];
}
// design_standard_doc: aid-ui-design-standard.py check over docs/design/design-standard.md (sections
// of the WAN structure, every DESIGN.md colour token, the platform rows, a measured button role)
function runDesignDoc() {
  const r = spawnSync('python3', [path.join(HERE, '../../scripts/aid-ui-design-standard.py'), 'check', project], { encoding: 'utf8' });
  const miss = (r.stdout || '').split('\n').filter(l => l.startsWith('MISSING')).map(l => l.slice(8));
  // a crash also exits 1: only a run that names what is missing is a result
  if (r.status !== 0 && !(r.status === 1 && miss.length))
    return ['not_covered', `aid-ui-design-standard.py exit ${r.status}: ${(r.stderr || '').trim().split('\n').pop().slice(0, 200)}`];
  return miss.length ? ['fail', `missing: ${miss.join('; ')}`] : ['pass', 'every section, token and platform row present'];
}
function brandFiles() {
  const dir = project && path.join(project, 'docs/design/brand-package');
  if (!dir || !fs.existsSync(dir)) return null;
  const set = new Set(), svgs = new Set();
  const walk = d => { for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name);
    if (e.isDirectory()) { walk(f); continue; }
    set.add(sha(f));
    if (/\.svg$/i.test(e.name)) svgs.add(svgShape(fs.readFileSync(f, 'utf8')));
  } };
  walk(dir);
  return { has: h => set.has(h), svgs };
}
// the drawing of an SVG: viewBox + each shape element with its geometry attributes, in order;
// whitespace, ids, classes and colours do not count.
// ponytail: regex over the markup, no transforms/<use>/<g> resolution; a moved group reads as a different logo
const GEOM = ['d', 'cx', 'cy', 'r', 'rx', 'ry', 'x', 'y', 'width', 'height', 'points', 'x1', 'y1', 'x2', 'y2'];
function svgShape(markup) {
  const num = v => v.trim().replace(/\s*,\s*|\s+/g, ' ');
  const attr = (a, n) => { const m = a.match(new RegExp(`(?:^|\\s)${n}\\s*=\\s*["']([^"']*)["']`, 'i')); return m ? num(m[1]) : ''; };
  const root = markup.match(/<svg\b([^>]*)>/i);
  const parts = [`viewBox=${root ? attr(root[1], 'viewBox') : ''}`];
  for (const m of markup.matchAll(/<(path|circle|rect|ellipse|polygon|polyline|line)\b([^>]*)>/gi)) {
    parts.push(`${m[1].toLowerCase()}(${GEOM.map(n => attr(m[2], n)).join('|')})`);
  }
  return parts.join(';');
}
// the facts register as read (mapping or list); aid-ui-facts.mjs reads its entries and keys
function factLeaves() {
  return opt.facts ? readJson(opt.facts) : null;
}
function glyph(url) {
  const r = spawnSync('node', [path.join(HERE, 'aid-ui-glyph-check.mjs'), url], { encoding: 'utf8', env: process.env });
  if (r.status === 0) return { status: 'pass', detail: 'checked at 1440 px' };
  if (r.status === 1) return { status: 'fail', detail: r.stdout.split('\n').filter(l => l.startsWith('BLOCKER')).slice(0, 5).join(' | ') };
  return { status: 'not_covered', detail: `glyph check exit ${r.status}: ${(r.stderr || '').slice(0, 200)}` };
}
async function lighthouse(url) {
  try {
    const { default: lh } = await import('lighthouse');
    const cl = await import('chrome-launcher');
    const chrome = await cl.launch({ chromePath: process.env.CHROME || chromium.executablePath(), chromeFlags: ['--headless=new', '--no-sandbox'] });
    try {
      // fixed profile: Lighthouse's default mobile emulation and simulated throttling
      const r = await lh(url, { port: chrome.port, output: 'json', logLevel: 'error', onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'] });
      const sc = Object.fromEntries(Object.entries(r.lhr.categories).map(([k, c]) => [k, Math.round((c.score ?? 0) * 100)]));
      const low = Object.values(sc).some(v => v < 90);
      return { status: low ? 'warn' : 'pass', detail: `mobile ${JSON.stringify(sc)}` };
    } finally { await chrome.kill(); }
  } catch (e) { return { status: 'not_covered', detail: `Lighthouse could not run: ${String(e.message || e).slice(0, 200)}` }; }
}
function requiredFiles(pageHtml) {
  const miss = [];
  const nf = path.join(site, '404.html');
  if (!fs.existsSync(nf)) miss.push('404.html missing');
  else if (!/<html[^>]*\blang=/i.test(fs.readFileSync(nf, 'utf8'))) miss.push('404.html is not localised (no lang)');
  for (const f of ['favicon.ico', 'favicon.svg', 'apple-touch-icon.png']) if (!fs.existsSync(path.join(site, f))) miss.push(`${f} missing`);
  const og = pageHtml.match(/<meta[^>]+property=["']og:image["'][^>]*>/i);
  const c = og && og[0].match(/content=["']([^"']+)["']/i);
  if (!c) miss.push('no og:image');
  else if (!/^https?:/i.test(c[1]) && !siteFile(new URL(c[1], base).href)) miss.push(`og:image ${c[1]} is not in the site`);
  return miss;
}

// ---- per loaded page (every browser x viewport) ----------------------------------------
async function scrollAll(page) {
  await page.evaluate(async () => {
    for (let y = 0; y < document.body.scrollHeight; y += 400) { scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); }
    scrollTo(0, 0);
  });
  await page.waitForLoadState('networkidle').catch(() => {});
}
async function inPage(page) {
  return page.evaluate(() => {
    const vis = e => !!(e.offsetParent || e.getClientRects().length);
    const o = { overflow: document.documentElement.scrollWidth > innerWidth };
    o.wrapped = [...document.querySelectorAll('button, a.btn, a.button, [role=button], nav a, input[type=submit]')].filter(vis).map(e => {
      const rg = document.createRange(); rg.selectNodeContents(e);
      return new Set([...rg.getClientRects()].filter(r => r.width > 0).map(r => Math.round(r.top))).size > 1 ? e.textContent.trim() : null;
    }).filter(Boolean);
    o.text = document.body.innerText;
    o.hrefs = [...document.querySelectorAll('a[href]')].map(a => a.href);
    // a logo: inside the home link or an element named logo/brand
    const ctx = 'a[href="/"], a[href="./"], a[href="index.html"], a[rel~=home], [class*=logo i], [id*=logo i], [aria-label*=logo i], [class*=brand i], [id*=brand i], [aria-label*=brand i]';
    o.imgs = [...document.querySelectorAll('img')].map(i => ({ logo: !!i.closest(ctx), src: i.currentSrc || i.src, alt: i.getAttribute('alt'), cls: `${i.className} ${i.id} ${i.alt}` }));
    o.svgLogos = [...document.querySelectorAll('svg')].map(sv => {
      const c = sv.closest(ctx);
      if (!c) return null;
      const name = `${c.tagName.toLowerCase()}${c.id ? '#' + c.id : ''}${typeof c.className === 'string' && c.className ? '.' + c.className.trim().split(/\s+/).join('.') : ''}${c.getAttribute('aria-label') ? `[aria-label="${c.getAttribute('aria-label')}"]` : ''}`;
      return { name, markup: sv.outerHTML };
    }).filter(Boolean);
    o.icons = [...document.querySelectorAll('link[rel~=icon], link[rel=apple-touch-icon]')].map(l => l.href);
    // no_overlap: visible elements that paint their own text, controls and images; two that are not
    // nested and whose boxes intersect (by more than 2 px each way) overlap. Off-screen parking (skip links) is skipped.
    const own = e => [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    const boxes = [...document.querySelectorAll('body *')].filter(e => vis(e) && getComputedStyle(e).visibility !== 'hidden'
      && (own(e) || /^(IMG|SVG|BUTTON|INPUT|TEXTAREA|SELECT|VIDEO)$/i.test(e.tagName)))
      .map(e => ({ e, r: e.getBoundingClientRect() })).filter(x => x.r.width > 1 && x.r.height > 1 && x.r.right > 0 && x.r.left < document.documentElement.scrollWidth && x.r.bottom + scrollY > 0);
    const name = e => `${e.tagName.toLowerCase()}${e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\s+/)[0] : ''} "${(e.textContent || e.getAttribute('alt') || '').trim().slice(0, 30)}"`;
    o.overlaps = [];
    // ponytail: O(n^2) over leaf boxes; fine for pages of a few hundred elements
    for (let i = 0; i < boxes.length && o.overlaps.length < 5; i++) for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j];
      if (a.e.contains(b.e) || b.e.contains(a.e)) continue;
      // inside one photo slot (FB-30) the icon over the brand mark is the slot's decoration, not an overlap
      const sa = a.e.closest('[data-aid-photo]'); if (sa && sa === b.e.closest('[data-aid-photo]')) continue;
      const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left), h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      if (w > 2 && h > 2) { o.overlaps.push(`${name(a.e)} x ${name(b.e)}`); if (o.overlaps.length >= 5) break; }
    }
    // brand_consistency: the first family of every text element is a webfont the site declares
    const declared = new Set([...document.fonts].map(f => f.family.replace(/["']/g, '').toLowerCase()));
    o.fontFamilies = [...new Set([...document.querySelectorAll('body *')].filter(e => vis(e) && own(e))
      .map(e => getComputedStyle(e).fontFamily.split(',')[0].replace(/["']/g, '').trim()))];
    o.undeclaredFonts = o.fontFamilies.filter(f => !declared.has(f.toLowerCase()));
    const shape = el => el ? el.outerHTML.replace(/\s+aria-current="[^"]*"/g, '').replace(/\s+/g, ' ') : '';
    o.header = shape(document.querySelector('body > header, header'));
    o.footer = shape(document.querySelector('body > footer, footer'));
    // page_weight: render-blocking scripts in <head>, large raster images without srcset
    o.blocking = [...document.querySelectorAll('head script[src]')].filter(x => !x.async && !x.defer && x.type !== 'module').map(x => x.src);
    o.noSrcset = [...document.querySelectorAll('img')].filter(i => i.naturalWidth > 800 && !i.srcset && !/\.svg(\?|$)/i.test(i.currentSrc || i.src)
      && !i.closest('picture source[srcset]')).map(i => i.currentSrc || i.src);
    // business_minimum: seller identification (IČO/IČ + 8 digits) and, next to a form, a link about personal data
    o.ico = /\bI[ČC]O?\s*:?\s*\d{8}\b/.test(document.body.innerText.replace(/\u00a0/g, ' '));
    o.form = !!document.querySelector('form input:not([type=hidden]), form textarea');
    o.privacyLink = [...document.querySelectorAll('a[href]')].some(a => /osobn(?:[ií]ch|[ýy]ch)\s+[úu]daj|osobnych[-_ ]udaj|zpracov[áa]n[íi]\s+[úu]daj|sprac[úu]van|ochrana\s+[úu]daj|ochrana[-_ ]osobn|GDPR|soukrom[íi]|s[úu]krom|privacy/i.test(a.textContent + ' ' + a.getAttribute('href')));
    return o;
  });
}
// ponytail: one fixed page budget (bytes transferred incl. fonts and images); a per-project budget when a site needs it
const PAGE_BUDGET = 1024 * 1024;
const PLACEHOLDER = /lorem ipsum|\bTODO\b|\bXXX\b|example\.(com|org|cz)|\.invalid\b|\+420 ?000|doplní se|fiktivn/gi;
const PLACEHOLDER_IMG = /placeholder|placehold\.|picsum\.|dummyimage/i;
// facts_match: phones, prices, times, percentages, counted numbers and e-mails (aid-ui-facts.mjs);
// names and references need the copy reviewer

async function pageRows(ctx, url, key, role, state, run, facts, brand, applies = () => true) {
  const page = await ctx.newPage();
  const bad = [], imgs = [], requested = [];
  page.on('request', r => requested.push(r.url()));
  // a web is measured as a first visit (privacy_before_consent); an app keeps its logged-in session
  if (st.variant?.type === 'web' || !st.variant?.type) await ctx.clearCookies();
  // a request the page itself cancelled by navigating away (a redirect to the login screen) is not a broken resource
  page.on('requestfailed', r => { if (!/ABORTED|cancel/i.test(r.failure()?.errorText || '')) bad.push(`failed ${r.url()}`); });
  let bytes = 0;
  page.on('response', async r => {
    bytes += Number(r.headers()['content-length'] || (await r.body().catch(() => Buffer.alloc(0))).length) || 0;
    if (r.status() >= 400 && r.url() !== url) bad.push(`${r.status()} ${r.url()}`);
    if (r.request().resourceType() === 'image') {
      const len = Number(r.headers()['content-length'] || (await r.body().catch(() => Buffer.alloc(0))).length);
      // a 304 from the cache carries no content-type: the file extension stands in
      const ext = { webp: 'image/webp', avif: 'image/avif', svg: 'image/svg+xml', ico: 'image/x-icon', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif' };
      const type = r.headers()['content-type'] || ext[(new URL(r.url()).pathname.match(/\.([a-z0-9]+)$/i) || [])[1]?.toLowerCase()] || '';
      imgs.push({ url: r.url(), type, len });
    }
  });
  const res = {};
  let resp;
  try {
    resp = await page.goto(url, { waitUntil: 'networkidle' });
    if (run) resp = (await run(page)) || resp;
  } catch (e) {
    await page.close();
    return { error: String(e.message || e).slice(0, 200) };
  }
  res.http_200 = resp && resp.status() === 200 ? ['pass', ''] : ['fail', `HTTP ${resp ? resp.status() : 'no response'} for ${url}`];
  await page.evaluate(() => document.fonts.ready).catch(() => {});
  const settled = await settleMotion(page);
  await scrollAll(page);
  // reveals fire while scrolling: settle again before anything is measured or photographed
  const settled2 = settled.ok ? await settleMotion(page) : settled;
  res.motion_settled = settled2.ok ? ['pass', `settled after ${settled.ms} ms, ${settled2.ms} ms after scrolling`] : ['fail', settled2.why];
  // H1 (12. 10. 2026, klient-Codex retro): what the visitor sees without scripts and before any scroll
  {
    const vp = page.viewportSize();
    res.content_without_js = applies('content_without_js') ? await contentWithoutJs(ctx.browser(), url, vp, await page.evaluate(READABLE_JS, 'texts'))
      : NA('runs at the viewport and browser of its row only');
    res.first_paint_visible = applies('first_paint_visible') ? await firstPaintVisible(ctx.browser(), url, vp)
      : NA('runs at the viewport and browser of its row only');
    res.form_states = applies('form_states') ? await formStates(ctx.browser(), url, vp) : NA('runs at the viewport and browser of its row only');
    res.photo_slots = applies('photo_slots') ? await photoSlots(ctx.browser(), url, vp) : NA('runs at the viewport and browser of its row only');
  }
  const o = await inPage(page);
  res.no_overflow = o.overflow ? ['fail', 'the page scrolls sideways'] : ['pass', ''];
  res.one_line_controls = o.wrapped.length ? ['fail', `wraps: ${o.wrapped.join(' | ')}`] : ['pass', ''];
  const ph = [...(o.text.match(PLACEHOLDER) || []), ...o.hrefs.filter(h => PLACEHOLDER.test(h)), ...o.imgs.filter(i => PLACEHOLDER_IMG.test(i.src)).map(i => i.src)];
  PLACEHOLDER.lastIndex = 0;
  res.no_placeholders = ph.length ? ['fail', `placeholders: ${[...new Set(ph)].join(', ')}`] : ['pass', ''];
  if (!facts) res.facts_match = ['not_covered', 'no docs/content/facts.yaml'];
  else {
    const unknown = unknownClaims(o.text, facts);
    res.facts_match = unknown.length ? ['fail', `not in facts.yaml: ${unknown.join(', ')}`] : ['pass', ''];
  }
  if (!brand) res.brand_assets = ['not_covered', 'no docs/design/brand-package/'];
  else {
    const drawn = [];
    if (!o.icons.length) drawn.push('no favicon link');
    for (const u of [...o.icons, ...o.imgs.filter(i => i.logo || /logo/i.test(i.cls) || /logo/i.test(i.src)).map(i => i.src)]) {
      const f = siteFile(u);
      if (!f || !brand.has(sha(f))) drawn.push(u.replace(base, '/'));
    }
    for (const l of o.svgLogos) if (!brand.svgs.has(svgShape(l.markup))) drawn.push(`inline <svg> in ${l.name}`);
    res.brand_assets = drawn.length ? ['fail', `not from the brand package: ${drawn.join(', ')}`] : ['pass', ''];
  }
  const broken = [...bad];
  for (const h of new Set(o.hrefs.map(h => h.split('#')[0]).filter(h => h.startsWith(new URL(base).origin)))) {
    const r = await page.request.get(h).catch(() => null);
    if (!r || r.status() >= 400) broken.push(`link ${h.replace(base, '/')} ${r ? r.status() : 'failed'}`);
  }
  res.links_resources = broken.length ? ['fail', [...new Set(broken)].join(', ')] : ['pass', ''];
  try {
    const ax = await new AxeBuilder({ page }).analyze();
    const v = ax.violations.filter(x => x.impact === 'serious' || x.impact === 'critical');
    res.axe = v.length ? ['fail', v.map(x => `${x.impact} ${x.id} (${x.nodes.length})`).join(', ')] : ['pass', ''];
  } catch (e) { res.axe = ['not_covered', `axe could not run: ${String(e.message).slice(0, 150)}`]; }
  const heavy = imgs.filter(i => !/image\/(webp|avif|svg\+xml|x-icon|vnd\.microsoft\.icon)/.test(i.type) && !/favicon|apple-touch-icon/.test(i.url))
    .map(i => `${i.url.replace(base, '/')} is ${i.type || 'unknown type'}`)
    .concat(imgs.filter(i => i.len > 200 * 1024).map(i => `${i.url.replace(base, '/')} is ${Math.round(i.len / 1024)} kB`));
  res.image_weight = heavy.length ? ['fail', heavy.join(', ')] : ['pass', ''];
  res.no_overlap = o.overlaps.length ? ['fail', `overlaps: ${o.overlaps.join(' | ')}`] : ['pass', ''];
  res.brand_consistency = o.undeclaredFonts.length ? ['fail', `fonts not from the site's own @font-face: ${o.undeclaredFonts.join(', ')}`] : ['pass', `fonts: ${o.fontFamilies.join(', ')}`];
  res.header = o.header; res.footer = o.footer;
  const heavyPage = [];
  if (bytes > PAGE_BUDGET) heavyPage.push(`page transfers ${Math.round(bytes / 1024)} kB (budget ${PAGE_BUDGET / 1024} kB)`);
  if (o.blocking.length) heavyPage.push(`render-blocking scripts: ${o.blocking.map(u => u.replace(base, '/')).join(', ')}`);
  if (o.noSrcset.length) heavyPage.push(`large images without srcset: ${o.noSrcset.map(u => u.replace(base, '/')).join(', ')}`);
  res.page_weight = heavyPage.length ? ['fail', heavyPage.join('; ')] : ['pass', `${Math.round(bytes / 1024)} kB`];
  const biz = [];
  if (!o.ico) biz.push('no seller identification (IČO with 8 digits) on the page');
  if (o.form && !o.privacyLink) biz.push('a form without a link to how personal data are processed');
  res.business_minimum = biz.length ? ['fail', biz.join('; ')] : ['pass', ''];
  const shot = inside(path.join(out, 'shots'), path.join(...key));
  if (!shot) throw new Error(`screenshot path ${key.join('/')} leaves the output directory`);
  fs.mkdirSync(path.dirname(shot), { recursive: true });
  await page.screenshot({ path: shot, fullPage: true });
  res.screenshots_reviewed = ['pass', `screenshot ${path.relative(out, shot)}; the PM's review is approve-page`];
  Object.assign(res, await moreRows(page, url, requested, applies));   // after the screenshot: these move focus and media
  res.html = await page.content();
  await page.close();
  return res;
}

// ---- P103 extension K1b: checks the coverage map now gives to the gate ----------------
// tokens: the colours of DESIGN.md (frontmatter `colors`, read by yq like the CSS), as #rrggbb
const TOKENS = (() => {
  const f = project && path.join(project, 'DESIGN.md');
  if (!f || !fs.existsSync(f)) return null;
  const m = /^---\n([\s\S]*?)\n---\n/.exec(fs.readFileSync(f, 'utf8'));
  const r = m && spawnSync('yq', ['-o=json', '{"colors": (.colors // {}), "typography": (.typography // {})}'], { input: m[1], encoding: 'utf8' });
  try {
    const j = JSON.parse(r.stdout);
    const fonts = Object.values(j.typography || {}).map(t => String(t?.fontFamily || '').split(',')[0].replace(/["']/g, '').trim().toLowerCase()).filter(Boolean);
    return { colors: Object.values(j.colors || {}).map(String), fonts };
  } catch { return null; }
})();
// the project's own hosts: the preview, the domain of the facts register and its subdomains
const OWN_HOSTS = (() => {
  try { const d = readJson(opt.facts)?.domain; const v = typeof d === 'object' ? d?.value : d; return v ? [new URL(v).hostname.replace(/^www\./, '')] : []; } catch { return []; }
})();
const NA = why => ['pass', `N/A: ${why}`];
// motion_settled (P108): the page is measured once its motion has settled - every finite animation
// ended, 500 ms with no new one, and the intro overlay (the element marked data-aid-intro, the one
// contract for an intro) gone from the document or display:none; 10 s cap. Infinite animations are
// left alone. Until then a mid-animation sample would fail contrast for text that is still arriving.
async function settleMotion(page) {
  const t0 = Date.now(); let quiet = 0, last = -1;
  while (Date.now() - t0 < 10000) {
    const s = await page.evaluate(() => {
      const anims = document.getAnimations();
      const running = anims.filter(a => a.playState === 'running' && !(a.effect && a.effect.getTiming && a.effect.getTiming().iterations === Infinity)).length;
      const intro = [...document.querySelectorAll('[data-aid-intro]')].filter(e => e.isConnected && getComputedStyle(e).display !== 'none').length;
      return { running, started: anims.length, intro };
    }).catch(() => ({ running: 0, started: 0, intro: 0 }));
    if (s.running === 0 && s.intro === 0) { quiet = s.started === last ? quiet + 250 : 0; if (quiet >= 500) return { ok: true, ms: Date.now() - t0 }; }
    else quiet = 0;
    last = s.started; await page.waitForTimeout(250);
  }
  return { ok: false, why: 'the intro or a finite animation did not end within 10 s (data-aid-intro still shown, or an animation still running)' };
}
// applies(check) for this row of the matrix: the expensive checks run only where their row is written
async function moreRows(page, url, requested, applies) {
  const res = {}, vw = page.viewportSize()?.width || 0;
  const o = await page.evaluate(tokens => {
    const cs = e => getComputedStyle(e);
    const vis = e => { const b = e.getBoundingClientRect(); return b.width >= 2 && b.height >= 2 && cs(e).visibility !== 'hidden' && cs(e).display !== 'none'; };
    // every CSS colour (hex, rgb, oklch, color-mix, names) as sRGB #rrggbb through a canvas; null = transparent or unreadable
    const cv = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const srgb = c => {
      if (!c || c === 'transparent') return null;
      // rgb()/rgba(): the channels as written, alpha ignored (a translucent token is still the token)
      const m = /^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/.exec(c);
      if (m) return m[4] !== undefined && +m[4] === 0 ? null : '#' + m.slice(1, 4).map(x => (+x).toString(16).padStart(2, '0')).join('');
      cv.clearRect(0, 0, 1, 1); cv.fillStyle = '#010203'; cv.fillStyle = c;
      if (cv.fillStyle === '#010203' && c.replace(/\s/g, '').toLowerCase() !== '#010203') return undefined;
      cv.fillRect(0, 0, 1, 1); const d = cv.getImageData(0, 0, 1, 1).data;
      return d[3] === 0 ? null : '#' + [0, 1, 2].map(i => d[i].toString(16).padStart(2, '0')).join('');
    };
    const tokenSet = new Set((tokens?.colors || []).map(srgb).filter(Boolean));
    const shown = [...document.querySelectorAll('body *')].filter(vis);
    const own = e => [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    const colours = {}, unreadable = new Set(), fonts = {};
    const add = c => { const h = srgb(c); if (h === undefined) unreadable.add(c); else if (h) colours[h] = (colours[h] || 0) + 1; };
    for (const e of shown) {
      if (e.closest('svg') || e.tagName === 'IMG') continue;   // drawings and images carry their own colours (brand_assets)
      const s = cs(e);
      if (own(e)) { add(s.color); const f = s.fontFamily.split(',')[0].replace(/["']/g, '').trim().toLowerCase(); fonts[f] = (fonts[f] || 0) + 1; }
      add(s.backgroundColor);
      if (parseFloat(s.borderTopWidth) > 0 && s.borderTopStyle !== 'none') add(s.borderTopColor);
    }
    const offTokens = Object.entries(colours).filter(([c]) => !tokenSet.has(c));
    const offFonts = Object.entries(fonts).filter(([f]) => !(tokens?.fonts || []).includes(f));
    // sticky: only a panel whose content overflows its box (or the window) must scroll itself; decorative layers are skipped
    const sticky = shown.filter(e => /sticky|fixed/.test(cs(e).position) && e.getBoundingClientRect().height > 40
        && cs(e).pointerEvents !== 'none' && !(parseInt(cs(e).zIndex) < 0) && !e.closest('[aria-hidden="true"]'))
      .map(e => ({ name: e.tagName.toLowerCase() + (e.id ? '#' + e.id : ''),
        // overflow = a visible descendant below the panel, or a panel taller than the window (hidden dropdowns do not count)
        overflows: e.getBoundingClientRect().height > innerHeight + 1
          || [...e.querySelectorAll('*')].some(d => vis(d) && cs(d).opacity !== '0' && d.getBoundingClientRect().bottom > e.getBoundingClientRect().bottom + 1),
        scroll: /auto|scroll/.test(cs(e).overflowY), contain: /contain|none/.test(cs(e).overscrollBehaviorY),
        edge: e.getBoundingClientRect().bottom >= innerHeight - 1 || e.getBoundingClientRect().top <= 0 }));
    const inlineLink = e => e.tagName === 'A' && cs(e).display === 'inline' && [...e.parentElement.childNodes].some(n => n !== e && n.nodeType === 3 && n.textContent.trim());
    // controls a visitor reaches by Tab: honeypots (tabindex=-1, aria-hidden, inert) and all radios of a group but one are out;
    // an iframe only with a tabindex (an embed with nothing focusable is no tab stop)
    const radios = new Set();
    const interactive = shown.filter(e => e.matches('a[href], button, input:not([type=hidden]), select, textarea, [role=button], [tabindex]')
      && e.getAttribute('tabindex') !== '-1' && !e.closest('[aria-hidden="true"], [inert]') && !e.disabled)
      .filter(e => !(e.type === 'radio' && e.name) || (!radios.has(e.name) && radios.add(e.name)));
    const look = e => { const s = cs(e); return [s.outlineStyle !== 'none' ? `${s.outlineWidth} ${s.outlineColor}` : '', s.boxShadow, s.backgroundColor, s.borderColor, s.textDecorationLine, s.color].join('|'); };
    interactive.forEach((e, i) => {
      // every radio of a group carries the group's number: Tab lands on the checked one, not always the first
      const group = e.type === 'radio' && e.name ? [...document.querySelectorAll('input[type=radio]')].filter(r => r.name === e.name && r.form === e.form) : [e];
      for (const g of group) { g.setAttribute('data-aid-k', String(i)); g.setAttribute('data-aid-rest', look(g)); } });
    // touch: the larger of the control and its label (a checkbox inside a 44 px label is fine)
    const small = interactive.filter(e => !inlineLink(e) && e.tagName !== 'IFRAME').map(e => {
      let r = e.getBoundingClientRect();
      for (const l of e.labels || []) { const b = l.getBoundingClientRect(); if (b.width * b.height > r.width * r.height) r = b; }
      return { e, r };
    }).filter(x => x.r.width < 44 || x.r.height < 44)
      .map(x => `${x.e.tagName.toLowerCase()} "${(x.e.innerText || x.e.getAttribute('aria-label') || x.e.name || '').trim().slice(0, 25)}" ${Math.round(x.r.width)}×${Math.round(x.r.height)}`);
    let safe = false;
    for (const sh of document.styleSheets) { try { for (const r of sh.cssRules) if (/safe-area-inset/.test(r.cssText)) safe = true; } catch { /* cross-origin */ } }
    const cover = shown.filter(e => /fixed|sticky/.test(cs(e).position) && /cookie|consent|souhlas/i.test(e.id + ' ' + e.className + ' ' + (e.innerText || '').slice(0, 200)))
      .map(e => e.getBoundingClientRect()).map(r => (r.width * r.height) / (innerWidth * innerHeight));
    return { offTokens, unreadable: [...unreadable], offFonts, ncolours: Object.keys(colours).length, sticky, small, safe, cover, tabbable: interactive.length };
  }, TOKENS);
  if (!TOKENS) res.token_usage = ['not_covered', 'no DESIGN.md tokens'];
  else if (!TOKENS.fonts.length) res.token_usage = ['not_covered', 'DESIGN.md has no typography fontFamily: the fonts cannot be checked'];
  else if (o.unreadable.length) res.token_usage = ['not_covered', `colours the browser cannot read: ${o.unreadable.slice(0, 4).join(', ')}`];
  else {
    const bad = [];
    if (o.offTokens.length) bad.push(`colours outside DESIGN.md tokens: ${o.offTokens.sort((a, b) => b[1] - a[1]).slice(0, 6).map(([c, n]) => `${c} (${n}×)`).join(', ')}`);
    if (o.offFonts.length) bad.push(`fonts outside DESIGN.md typography: ${o.offFonts.map(([f, n]) => `${f} (${n}×)`).join(', ')}`);
    res.token_usage = bad.length ? ['fail', bad.join('; ')] : ['pass', `${o.ncolours} colours, all tokens`];
  }
  const broken = o.sticky.filter(x => x.overflows && (!x.scroll || !x.contain));
  res.sticky_panels = !o.sticky.length ? NA('no sticky or fixed panel') : broken.length
    ? ['fail', broken.map(x => `${x.name}: ${!x.scroll ? 'content overflows without its own scroll' : 'scroll spills into the page (overscroll-behavior)'}`).join('; ')]
    : ['pass', `${o.sticky.length} panel(s) follow the scroll contract`];
  // keyboard: Tab reaches every control; the focused look differs from the resting look
  if (!applies('keyboard')) res.keyboard = NA('runs at the viewport and browser of its row only');
  else if (!o.tabbable) res.keyboard = NA('no control on the page');
  else {
    const seen = new Set(), invisible = [];
    // transitions off for the walk: a focus style that fades in would still read as the resting look
    await page.evaluate(() => { const t = document.createElement('style'); t.id = 'aid-no-transition';
      t.textContent = '*,*::before,*::after{transition:none!important}'; document.head.append(t);
      document.activeElement?.blur(); window.scrollTo(0, 0); });
    const read = () => page.evaluate(() => { const e = document.activeElement; if (!e || e === document.body) return null;
      const s = getComputedStyle(e), now = [s.outlineStyle !== 'none' ? `${s.outlineWidth} ${s.outlineColor}` : '', s.boxShadow, s.backgroundColor, s.borderColor, s.textDecorationLine, s.color].join('|');
      return { id: e.getAttribute('data-aid-k'), iframe: e.tagName === 'IFRAME', changed: now !== e.getAttribute('data-aid-rest'),
        name: `${e.tagName.toLowerCase()} "${(e.innerText || e.getAttribute('aria-label') || '').trim().slice(0, 25)}"` }; });
    for (let i = 0; i < o.tabbable * 3 + 40 && seen.size < o.tabbable; i++) {
      await page.keyboard.press('Tab');
      let f = await read();
      if (!f || f.id === null) continue;
      if (seen.has(f.id)) break;
      seen.add(f.id);
      if (f.iframe) {   // a frame keeps the focus inside: move on to the next control after it and check that one
        const moved = await page.evaluate(id => { const n = document.querySelector(`[data-aid-k="${Number(id) + 1}"]`); if (n) n.focus(); return !!n; }, f.id);
        if (!moved) continue;
        f = await read();
        if (!f || f.id === null || seen.has(f.id)) continue;
        seen.add(f.id);
      }
      if (!f.iframe && !f.changed) invisible.push(f.name);
    }
    await page.evaluate(() => document.getElementById('aid-no-transition')?.remove());
    res.keyboard = seen.size < o.tabbable ? ['fail', `Tab reaches ${seen.size} of ${o.tabbable} controls`]
      : invisible.length ? ['fail', `focus not visible (no change from the resting look) on: ${invisible.slice(0, 5).join(', ')}`]
      : ['pass', `${seen.size} controls, focus visible`];
  }
  if (!applies('reduced_motion')) res.reduced_motion = NA('runs at the viewport and browser of its row only');
  else {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const moving = await page.evaluate(() => [...document.querySelectorAll('body *')].filter(e => {
      const s = getComputedStyle(e), ms = v => Math.max(0, ...String(v).split(',').map(x => parseFloat(x) * (x.trim().endsWith('ms') ? 1 : 1000)));
      return (s.animationName !== 'none' && ms(s.animationDuration) > 10) || ms(s.transitionDuration) > 10; }).length);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    res.reduced_motion = moving ? ['fail', `${moving} element(s) still animate under prefers-reduced-motion`] : ['pass', ''];
  }
  res.touch_targets = vw > 430 ? NA(`desktop width ${vw}`) : o.small.length ? ['fail', `under 44 px: ${o.small.slice(0, 6).join(', ')}`] : ['pass', ''];
  const edge = o.sticky.filter(x => x.edge);
  res.safe_area = st.variant?.type !== 'pwa' ? NA('not a PWA') : !edge.length ? NA('no fixed panel at a screen edge')
    : o.safe ? ['pass', 'env(safe-area-inset-*) used'] : ['fail', `fixed panels at a screen edge without env(safe-area-inset-*): ${edge.map(x => x.name).join(', ')}`];
  // privacy: own = the preview's origin and the site's domain with its subdomains
  const origin = new URL(url).origin;
  const own = h => h === new URL(url).hostname || OWN_HOSTS.some(d => h === d || h.endsWith('.' + d));
  const third = [...new Set(requested.filter(u => /^https?:/.test(u) && new URL(u).origin !== origin && !own(new URL(u).hostname)).map(u => new URL(u).host))];
  const cookies = st.variant?.type === 'web' || !st.variant?.type ? (await page.context().cookies(url)).map(c => c.name) : [];
  const priv = [];
  if (third.length) priv.push(`third-party requests before consent: ${third.join(', ')}`);
  if (cookies.length) priv.push(`cookies set on load: ${cookies.join(', ')}`);
  if (o.cover.some(a => a > 0.3)) priv.push('a consent banner covers more than 30 % of the screen');
  res.privacy_before_consent = priv.length ? ['fail', priv.join('; ')] : ['pass', ''];
  return res;
}

// ---- H1: content without JS, first paint (12. 10. 2026) ---------------------------------
// One visibility rule for both checks (Codex review 12. 10.): a content element (p, li, h1-h3, td, dt, dd,
// summary, blockquote) with text of its own is readable when no ancestor hides it (display none, visibility
// hidden, content-visibility hidden), its effective opacity (product over ancestors) is at least 0.5 and its box
// overlaps the document on both axes (or, for first paint, the viewport). Full text is compared; it is cut only
// for the message.
const READABLE_JS = (mode) => {
  const SEL = 'p, li, h1, h2, h3, td, dt, dd, summary, blockquote';
  const own = e => [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' ').replace(/\s+/g, ' ').trim();
  const hidden = e => { for (let n = e; n && n.nodeType === 1; n = n.parentElement) { const c = getComputedStyle(n);
      if (c.display === 'none' || c.visibility === 'hidden' || c.visibility === 'collapse' || c.contentVisibility === 'hidden') return true; } return false; };
  const opac = e => { let o = 1; for (let n = e; n && n.nodeType === 1; n = n.parentElement) o *= parseFloat(getComputedStyle(n).opacity); return o; };
  const W = Math.max(document.documentElement.scrollWidth, innerWidth), H = Math.max(document.documentElement.scrollHeight, innerHeight);
  const box = (e, vp) => { const r = e.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false;
    return vp ? (r.right > 0 && r.left < innerWidth && r.bottom > 0 && r.top < innerHeight)
              : (r.right + scrollX > 0 && r.left + scrollX < W && r.bottom + scrollY > 0 && r.top + scrollY < H); };
  // an answer folded in a closed <details> is collapsed on purpose (the visitor opens it), not hidden by motion
  const all = [...document.body.querySelectorAll(SEL)].filter(e => !e.closest('script, style, noscript, template, svg, nav, header, footer, form, [data-aid-intro], [aria-hidden="true"]')
      && !(e.closest('details:not([open])') && !e.matches('summary')))
    .map(e => ({ e, t: own(e) })).filter(x => x.t.length >= 3);
  const ok = (e, vp) => !hidden(e) && opac(e) >= 0.5 && box(e, vp);
  const name = e => `${e.tagName.toLowerCase()} "${own(e).slice(0, 40)}"`;
  if (mode === 'texts') return all.filter(x => ok(x.e, false)).map(x => x.t);
  if (mode === 'faded') return all.filter(x => !ok(x.e, false)).map(x => name(x.e));          // the whole document
  // first paint: the h1 and the first content block in document order must be readable in the viewport
  const h1 = all.find(x => x.e.tagName === 'H1'), first = all.find(x => x.e.tagName !== 'H1');
  const fadedInView = all.filter(x => { const r = x.e.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth && !ok(x.e, true); }).map(x => name(x.e));
  return { h1: h1 ? ok(h1.e, true) : null, first: first ? ok(first.e, true) : null, firstName: first ? name(first.e) : '', fadedInView };
};
const loaded = async (p, url) => { await p.goto(url, { waitUntil: 'load', timeout: 30000 }); await p.evaluate(() => document.fonts.ready).catch(() => {}); await p.waitForTimeout(400); };
// content_without_js: with scripts off the page shows every content text the scripted page shows after its motion
// settled and a scroll (a multiset: a repeated text counts each time)
async function contentWithoutJs(browser, url, viewport, withJs) {
  const ctx = await browser.newContext({ viewport, javaScriptEnabled: false });
  try {
    const p = await ctx.newPage();
    await loaded(p, url);   // page.evaluate runs even with the page's scripts off
    const left = new Map(); for (const t of await p.evaluate(READABLE_JS, 'texts')) left.set(t, (left.get(t) || 0) + 1);
    const missing = []; for (const t of withJs) { const n = left.get(t) || 0; if (n) left.set(t, n - 1); else missing.push(t); }
    return missing.length ? ['fail', `${missing.length} text(s) only a script shows (hidden or missing without JS): ${missing.slice(0, 4).map(t => `"${t.slice(0, 50)}"`).join(', ')}`]
      : ['pass', `${withJs.length} content texts visible without JS`];
  } catch (e) { return ['fail', `no-JS load failed: ${String(e.message || e).slice(0, 120)}`]; } finally { await ctx.close(); }
}
// first_paint_visible: after load and fonts, no scroll: the h1 and the first content block are readable in the
// viewport and nothing readable in the viewport is faded. An entrance that finishes on its own within 1.5 s counts
// as motion (the hero of a reference runs 1 s): only what stays hidden after that fails. Under prefers-reduced-motion
// no content text anywhere in the document stays faded.
async function firstPaintVisible(browser, url, viewport) {
  const ctx = await browser.newContext({ viewport });
  try {
    const p = await ctx.newPage();
    await loaded(p, url);
    let a = await p.evaluate(READABLE_JS, 'first');
    for (let t = 400; t < 1500 && (a.h1 === false || a.first === false || a.fadedInView.length); t += 250) { await p.waitForTimeout(250); a = await p.evaluate(READABLE_JS, 'first'); }
    await p.emulateMedia({ reducedMotion: 'reduce' });
    await loaded(p, url);
    const b = await p.evaluate(READABLE_JS, 'faded');
    const why = [];
    if (a.h1 === null) why.push('no h1');
    else if (!a.h1) why.push('h1 not readable in the first screen');
    if (a.first === null) why.push('no content block');
    else if (!a.first) why.push(`first content block not readable in the first screen: ${a.firstName}`);
    if (a.fadedInView.length) why.push(`${a.fadedInView.length} element(s) in the first screen faded or hidden before any scroll: ${a.fadedInView.slice(0, 3).join(', ')}`);
    if (b.length) why.push(`under prefers-reduced-motion ${b.length} element(s) stay faded or hidden: ${b.slice(0, 3).join(', ')}`);
    return why.length ? ['fail', why.join('; ')] : ['pass', 'h1 and first block readable at first paint, nothing faded under reduced motion'];
  } catch (e) { return ['fail', `first-paint load failed: ${String(e.message || e).slice(0, 120)}`]; } finally { await ctx.close(); }
}

// form_states (H3, 12. 10. 2026): a form on the page never posts to mailto:; sent by script it shows its state in a
// live region (role status/alert or aria-live): while sending the submit button is locked (no double send), a failed
// send (the endpoint answers 404) shows an error with a clickable tel: or mailto: contact, a successful one (200)
// a different message; an empty required form sends nothing; a double click sends once. Every non-GET request the
// page makes is taken as the send and stubbed (404, then 200); whether the endpoint exists on the host is the open item.
async function formStates(browser, url, viewport) {
  const ctx = await browser.newContext({ viewport });
  try {
    const p = await ctx.newPage();
    await p.goto(url, { waitUntil: 'load', timeout: 30000 });
    const f = await p.evaluate(() => { const fm = [...document.querySelectorAll('form')].find(x => x.querySelector('input:not([type=hidden]):not([tabindex="-1"]), textarea'));
      return fm ? { action: fm.getAttribute('action') || '', required: !!fm.querySelector('[required]') } : null; });
    if (!f) return NA('no form on the page');
    if (/^mailto:/i.test(f.action)) return ['fail', `the form posts to ${f.action.slice(0, 40)}: it opens the visitor's mail app instead of sending (FB-28)`];
    const origin = new URL(url).origin;
    // every non-GET request the page makes is the send (whatever URL the script uses): stubbed, never real, counted
    let sends = 0, status = 404;
    await p.route(r => true, async route => {
      const rq = route.request();
      if (rq.method() === 'GET' || rq.isNavigationRequest() && rq.method() === 'GET') return route.continue();
      sends += 1;
      if (rq.isNavigationRequest()) return route.fulfill({ status: 200, contentType: 'text/html', body: '<p>posted</p>' });
      await new Promise(r => setTimeout(r, 600));
      return route.fulfill({ status, contentType: 'application/json', body: status === 200 ? '{"ok":true}' : '{"error":"x"}' });
    });
    const btn = () => p.locator('form button[type=submit], form input[type=submit]').first();
    const live = () => p.evaluate(() => { const r = [...document.querySelectorAll('[role=status], [role=alert], [aria-live]')].filter(e => {
        const b = e.getBoundingClientRect(), c = getComputedStyle(e); return b.width > 0 && b.height > 0 && c.visibility !== 'hidden' && (e.innerText || '').trim(); });
      return { text: r.map(e => e.innerText.trim()).join(' | '), links: r.flatMap(e => [...e.querySelectorAll('a[href]')].map(a => a.getAttribute('href'))) }; });
    const fill = () => p.evaluate(() => { const fm = [...document.querySelectorAll('form')].find(x => x.querySelector('input:not([type=hidden]), textarea'));
      for (const el of fm.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]), textarea')) {
        if (el.tabIndex === -1 || el.closest('[aria-hidden="true"]')) continue;
        el.value = el.type === 'email' ? 'test@example.org' : el.type === 'tel' ? '+420777123456' : 'Test zprávy'; }
      for (const el of fm.querySelectorAll('input[type=checkbox][required]')) el.checked = true; });
    const why = [];
    // empty: a form with required fields sends nothing
    if (f.required) { await btn().click({ timeout: 5000 }); await p.waitForTimeout(400); if (sends) why.push('an empty form with required fields was sent'); }
    const submit = async (st) => {
      status = st; sends = 0;
      await p.goto(url, { waitUntil: 'load' }); await fill();
      await btn().click({ timeout: 5000 });
      await btn().click({ timeout: 2000, force: true }).catch(() => {});   // a second click while sending
      await p.waitForTimeout(150);
      const sending = await live();
      await p.waitForTimeout(1500);
      const stayed = p.url().split('#')[0].startsWith(origin) && !(await p.content()).includes('<p>posted</p>');
      return { sends, stayed, sending: sending.text, ...(stayed ? await live() : { text: '', links: [] }) };
    };
    const err = await submit(404);
    const ok = await submit(200);
    if (!err.stayed || !ok.stayed) why.push('the form leaves the page on submit (a native post): no state is shown');
    if (err.sends > 1 || ok.sends > 1) why.push(`a double click sent the form ${Math.max(err.sends, ok.sends)}×`);
    if (err.stayed && !err.sending) why.push('nothing says the form is being sent');
    if (err.stayed && !err.text) why.push('a failed send shows no message in a live region');
    else if (err.stayed && !err.links.some(h => /^(tel|mailto):/i.test(h || ''))) why.push('the error message offers no clickable phone or e-mail');
    if (ok.stayed && (!ok.text || ok.text === err.text)) why.push('a successful send shows no message of its own');
    return why.length ? ['fail', why.join('; ')] : ['pass', `error: "${err.text.slice(0, 50)}" · sent: "${ok.text.slice(0, 50)}"`];
  } catch (e) { return ['fail', `form check failed: ${String(e.message || e).slice(0, 120)}`]; } finally { await ctx.close(); }
}

// form_delivery (P113a step 6, AC8): the site's form, sent for real through the preview's receiver
// (.aid-ui/form.json; aid-ui-preview.py): filled the way a visitor fills it at 390 px and sent with its own button,
// it shows a message and the message lands in .aid-ui/inbox (the test message is removed again); the receiver
// refuses an incomplete message (422), drops a filled spam trap without delivering, delivers a repeated message
// once; the preview's log holds none of the sent values. Through the real form too: a double click delivers once, a
// filled spam trap delivers nothing. No receiver (no form.json, or the endpoint down) = the form delivers nothing and
// the row fails. No form on the site = N/A. The client's domain receiver is checked after deployment (not here).
async function formDelivery(browser) {
  const withForm = [];
  for (const p of pages) { try { if (/<form[\s>]/i.test(fs.readFileSync(path.join(site, p), 'utf8'))) withForm.push(p); } catch { /* not a file */ } }
  if (!withForm.length) return NA('no form on the site');
  if (!project) return ['not_covered', 'no --project'];
  let cfg; try { cfg = readJson(path.join(project, '.aid-ui/form.json')); } catch { return ['fail', 'no .aid-ui/form.json: the preview has no receiver (endpoint, required, honeypot)'] }
  const okName = x => typeof x === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(x);
  if (!(typeof cfg?.endpoint === 'string' && cfg.endpoint.startsWith('/') && Array.isArray(cfg.required) && cfg.required.length && cfg.required.every(okName)
        && okName(cfg.honeypot) && !(cfg.max_field !== undefined && !(Number.isInteger(cfg.max_field) && cfg.max_field > 0))))
    return ['fail', '.aid-ui/form.json needs endpoint "/…", required [field names], honeypot (a field name) and max_field > 0 if given'];
  const box = path.join(project, '.aid-ui/inbox'), inbox = () => { try { return fs.readdirSync(box); } catch { return []; } };
  const token = `AIDTEST${Date.now().toString(36)}`, mail = `${token.toLowerCase()}@example.invalid`, tel = '+421900000999';
  const why = [], ctx = await browser.newContext({ viewport: { width: 390, height: HEIGHT[390] } });
  try {
    const p = await ctx.newPage();
    await loaded(p, urlOf(withForm[0]));
    const before = inbox();
    const form = p.locator('form').first();
    const live = () => p.evaluate(() => [...document.querySelectorAll('[role=status], [role=alert], [aria-live]')].map(e => (e.innerText || '').trim()).filter(Boolean).join(' | '));
    const shown = await live();   // what the live regions say before the send: the success message must be new
    for (const el of await form.locator('input, textarea, select').all()) {
      const t = ((await el.getAttribute('type')) || '').toLowerCase(), name = await el.getAttribute('name'), tag = await el.evaluate(e => e.tagName);
      if (['hidden', 'submit', 'button', 'reset', 'file'].includes(t) || (cfg.honeypot && name === cfg.honeypot) || !(await el.isVisible())) continue;
      if (t === 'checkbox' || t === 'radio') { if (await el.evaluate(e => e.required)) await el.check(); continue; }
      if (tag === 'SELECT') { const v = await el.evaluate(e => [...e.options].map(o => o.value).find(x => x)); if (v) await el.selectOption(v); continue; }
      await el.fill(t === 'email' ? mail : t === 'tel' ? tel : t === 'date' ? '2030-01-15' : t === 'number' ? '1' : `${token} test`);
    }
    await form.locator('button:not([type=button]), input[type=submit]').first().dblclick();   // a double click: one message
    await p.waitForFunction(old => { const t = [...document.querySelectorAll('[role=status], [role=alert], [aria-live]')].map(e => (e.innerText || '').trim()).filter(Boolean).join(' | ');
      return t && t !== old && !/odosiel|odesíl|sending/i.test(t); }, shown, { timeout: 12000 }).catch(() => {});
    const msg = await live();
    const fresh = inbox().filter(x => !before.includes(x));
    const mine = fresh.filter(x => { const m = fs.readFileSync(path.join(box, x), 'utf8'); return [token, mail, tel].some(v => m.includes(v)); });
    if (!mine.length) why.push(`a filled form sent with its button delivered nothing (message on the page: "${msg.slice(0, 80)}")`);
    else if (mine.length > 1) why.push(`a double click delivered ${mine.length} messages`);
    else if (!msg || msg === shown) why.push('delivered, but the page shows no new message');
    // the spam trap through the real form: filled by a bot (a hidden field), the message is not delivered
    if (cfg.honeypot) {
      await loaded(p, urlOf(withForm[0]));
      const n0 = inbox().length;
      for (const el of await form.locator('input:not([type=hidden]):not([type=checkbox]):not([type=radio]), textarea').all())
        if (await el.isVisible()) await el.fill(((await el.getAttribute('type')) || '') === 'email' ? mail : ((await el.getAttribute('type')) || '') === 'tel' ? tel + '1' : `${token} bot`).catch(() => {});
      const trap = await p.evaluate(n => { const f = document.forms[0], e = f && f.elements[n]; if (!e) return false; e.value = 'http://spam.example'; return true; }, cfg.honeypot);
      if (!trap) why.push(`the form has no spam trap field "${cfg.honeypot}"`);
      else { await form.locator('button:not([type=button]), input[type=submit]').first().click(); await p.waitForTimeout(1500);
        if (inbox().length !== n0) why.push('a form with its spam trap filled was delivered'); }
    }
    for (const x of mine) fs.rmSync(path.join(box, x), { force: true });   // the test message is not the client's
    // the receiver itself: an incomplete message, a filled spam trap, the same message twice
    const send = body => p.evaluate(async ({ ep, body }) => { const r = await fetch(ep, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      return { status: r.status, json: await r.json().catch(() => ({})) }; }, { ep: cfg.endpoint, body });
    const full = Object.fromEntries((cfg.required || []).map(k => [k, `${token} ${k}`]));
    const empty = await send({});
    if ((cfg.required || []).length && empty.status !== 422) why.push(`an empty message got ${empty.status}, not 422`);
    if (cfg.honeypot) {
      const n0 = inbox().length, spam = await send({ ...full, [cfg.honeypot]: 'http://spam.example' });
      if (spam.status !== 200 || inbox().length !== n0) why.push('a filled spam trap was delivered or refused visibly');
    } else why.push('no honeypot field in .aid-ui/form.json (spam trap)');
    const n1 = inbox().length, a = await send({ ...full, note: token + 'dup' }), b = await send({ ...full, note: token + 'dup' });
    const dup = inbox().filter(x => fs.readFileSync(path.join(box, x), 'utf8').includes(token + 'dup'));
    if (a.status !== 200 || b.status !== 200 || dup.length !== 1 || !b.json.duplicate) why.push(`the same message twice: ${a.status}/${b.status}, delivered ${dup.length}×`);
    for (const x of inbox().filter(x => fs.readFileSync(path.join(box, x), 'utf8').includes(token))) fs.rmSync(path.join(box, x), { force: true });
    if (opt['preview-log']) {
      const logText = fs.readFileSync(opt['preview-log'], 'utf8');
      if ([token, mail, tel].some(v => logText.includes(v))) why.push('the preview log holds a sent value (personal data in the log)');
    } else why.push('no --preview-log: the log was not checked for personal data');
    return why.length ? ['fail', why.join('; ')] : ['pass', `delivered and removed again; page said "${msg.slice(0, 60)}"; empty 422, spam dropped, a repeat delivered once, log clean`];
  } catch (e) { return ['fail', `form delivery check failed: ${String(e.message || e).slice(0, 120)}`]; } finally { await ctx.close(); }
}

// photo_slots (P113a, FB-30, PM 1A 12. 10. 2026): a photo the client still owes has a slot of its exact shape and
// ratio (docs/content/photos.yaml: {id, page, where, what, shape rect|round, ratio "w:h", min_px "WxH"}),
// marked data-aid-photo="<id>". Empty: aria-hidden="true", a camera icon (svg), no text, nothing focusable.
// Filled: <img> with alt (unless the slot stays aria-hidden), object-fit cover. A test photo of another shape
// put into each empty slot the standard way (absolutely over the slot, cover) must keep the slot's size and
// the page's height, and cover the slot exactly - the photo is only put in, nothing is redesigned.
const PHOTO_TOL = 0.02;
async function photoSlots(browser, url, viewport) {
  const specs = opt.photos ? readJson(opt.photos) : null;
  const key = keyOfUrl(new URL(url).pathname.slice(new URL(base).pathname.length - 1));
  const ctx = await browser.newContext({ viewport });
  try {
    const p = await ctx.newPage();
    await loaded(p, url);
    const slots = await p.evaluate(() => [...document.querySelectorAll('[data-aid-photo]')].map(e => {
      const r = e.getBoundingClientRect(), s = getComputedStyle(e), img = e.querySelector('img');
      const FOC = 'a[href],button,input,select,textarea,iframe,audio[controls],video[controls],[contenteditable]:not([contenteditable="false"]),[tabindex]:not([tabindex="-1"])';
      return { id: e.dataset.aidPhoto, w: r.width, h: r.height, radius: s.borderTopLeftRadius, hidden: e.getAttribute('aria-hidden') === 'true',
        text: (e.innerText || '').trim(), focusable: e.matches(FOC) || !!e.querySelector(FOC), svg: !!e.querySelector('svg[data-aid-icon="camera"]'),
        img: img ? { alt: (img.getAttribute('alt') || '').trim(), fit: getComputedStyle(img).objectFit, hidden: !!img.closest('[aria-hidden="true"]') } : null };
    }));
    const mine = Array.isArray(specs) ? specs.filter(x => x && x.page === key) : [];
    const incomplete = mine.filter(x => !['id', 'where', 'what', 'shape', 'ratio', 'min_px'].every(k => String(x[k] || '').trim()) || !/^\d+x\d+$/.test(String(x.min_px)));
    if (!slots.length && !mine.length) return NA('no photo on this page');
    if (!Array.isArray(specs)) return ['fail', `${slots.length} photo slot(s) but no docs/content/photos.yaml`];
    const why = incomplete.map(x => `photos.yaml ${x.id || '?'}: needs id, where, what, shape, ratio and min_px as WxH`);
    for (const x of mine) if (!slots.some(y => y.id === x.id)) why.push(`photo ${x.id} (${x.where || ''}) has no slot on the page`);
    for (const x of slots) {
      const sp = mine.find(y => y.id === x.id);
      if (!sp) { why.push(`slot ${x.id} is not in photos.yaml for ${key}`); continue; }
      const [a, b] = String(sp.ratio || '').split(':').map(Number);
      if (!(a > 0 && b > 0)) { why.push(`${x.id}: ratio "${sp.ratio}" is not w:h`); continue; }
      if (!(x.w > 0 && x.h > 0)) { why.push(`${x.id}: the slot has no size`); continue; }
      if (Math.abs(x.w / x.h - a / b) > (a / b) * PHOTO_TOL) why.push(`${x.id}: ${Math.round(x.w)}×${Math.round(x.h)} is not ${sp.ratio}`);
      const rad = x.radius.endsWith('%') ? parseFloat(x.radius) * Math.min(x.w, x.h) / 100 : parseFloat(x.radius) || 0;
      if (!['rect', 'round'].includes(sp.shape)) why.push(`${x.id}: shape "${sp.shape}" is not rect or round`);
      else if (sp.shape === 'round' && rad < Math.min(x.w, x.h) / 2 - 1) why.push(`${x.id}: the slot is not round`);
      else if (sp.shape === 'rect' && rad >= Math.min(x.w, x.h) / 4) why.push(`${x.id}: a rectangular photo's slot is rounded like a circle`);
      if (!x.img) {
        if (!x.hidden) why.push(`${x.id}: an empty slot needs aria-hidden="true"`);
        if (x.text) why.push(`${x.id}: an empty slot carries text ("${x.text.slice(0, 30)}")`);
        if (x.focusable) why.push(`${x.id}: an empty slot is focusable`);
        if (!x.svg) why.push(`${x.id}: an empty slot shows no camera icon (svg data-aid-icon="camera")`);
      } else {
        if (!x.img.alt) why.push(`${x.id}: the photo has no alt text`);
        if (x.hidden || x.img.hidden) why.push(`${x.id}: the delivered photo is hidden from screen readers (aria-hidden)`);
        if (x.img.fit !== 'cover') why.push(`${x.id}: the photo is not object-fit: cover`);
      }
    }
    const swap = await p.evaluate(async () => {
      const height = () => document.documentElement.scrollHeight, before = height(), moved = [];
      // every element outside the slots: where it is before the photos go in (a shift of any of them is a layout shift)
      // fixed panels (a scroll progress bar) and anything that moves on its own (motion still running) are left out:
      // the baseline is taken twice, and an element that moved between the two is not the photo's doing
      const at = e => { const b = e.getBoundingClientRect(); return [b.left + scrollX, b.top + scrollY, b.width, b.height]; };
      const differs = (a, b) => a.some((v, k) => Math.abs(v - b[k]) > 1);
      let others = [...document.body.querySelectorAll('*')].filter(e => !e.closest('[data-aid-photo]')
        && ![e, ...(function* up(x) { while ((x = x.parentElement)) yield x; })(e)].some(x => ['fixed', 'sticky'].includes(getComputedStyle(x).position))).slice(0, 2000);
      const p0 = others.map(at);
      await new Promise(r => setTimeout(r, 300));
      const keep = others.map((e, i) => !differs(at(e), p0[i]));
      others = others.filter((e, i) => keep[i]);
      const pos = others.map(at);
      const c = document.createElement('canvas'); c.width = 300; c.height = 97;
      for (const e of document.querySelectorAll('[data-aid-photo]')) {
        if (e.querySelector('img')) continue;
        const r0 = e.getBoundingClientRect();
        const img = new Image(); img.alt = ''; img.src = c.toDataURL();
        img.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;object-fit:cover';
        e.replaceChildren(img); await img.decode().catch(() => {}); await new Promise(r => requestAnimationFrame(r));
        const r1 = e.getBoundingClientRect(), ri = img.getBoundingClientRect();
        if (Math.abs(r1.width - r0.width) > 1 || Math.abs(r1.height - r0.height) > 1) moved.push(`${e.dataset.aidPhoto}: the slot changes ${Math.round(r0.width)}×${Math.round(r0.height)} -> ${Math.round(r1.width)}×${Math.round(r1.height)}`);
        else if (Math.abs(ri.width - r1.width) > 1 || Math.abs(ri.height - r1.height) > 1 || Math.abs(ri.top - r1.top) > 1 || Math.abs(ri.left - r1.left) > 1)
          moved.push(`${e.dataset.aidPhoto}: the photo does not cover the slot (the slot needs position: relative)`);
        else if (getComputedStyle(e).overflow === 'visible' && getComputedStyle(e).borderTopLeftRadius !== '0px') moved.push(`${e.dataset.aidPhoto}: a rounded slot does not clip the photo (overflow: hidden)`);
      }
      const shifted = others.filter((e, i) => differs(at(e), pos[i]));
      if (shifted.length) moved.push(`putting the photos in moves ${shifted.length} other element(s), first ${shifted[0].tagName.toLowerCase()}${shifted[0].className ? '.' + String(shifted[0].className).split(' ')[0] : ''}`);
      return { moved, grew: height() - before };
    });
    why.push(...swap.moved);
    if (Math.abs(swap.grew) > 1) why.push(`putting the photos in changes the page height by ${swap.grew} px`);
    return why.length ? ['fail', why.join('; ')] : ['pass', `${slots.length} slot(s): ${slots.map(x => x.id).join(', ')}`];
  } catch (e) { return ['fail', `photo slot check failed: ${String(e.message || e).slice(0, 120)}`]; } finally { await ctx.close(); }
}

// task_test (P113a, 12. 10. 2026): what a customer comes for is found within two steps from the home page, at 1440
// and at 390 px. docs/content/tasks.yaml lists the tasks: {id, task, expect: [texts]} (one visible element on a
// page holds every text, case and spacing ignored) or {id, task, form: true} (a visible form with a field and a
// submit control). Every expect text must be in the facts register, so a task cannot be made easy by inventing
// it; the task ids of the project's frozen critic rubric (.aid-ui/critic/frozen.json task_test) must all be there.
// Steps = links followed from the home page (ponytail: every same-site link counts, also one inside a closed
// menu on the phone; a click that opens the menu is not counted). Detail: per task and width the page and steps.
const TASK_HOPS = 2;
async function taskTest(browser) {
  if (isApp) return NA('an application: its tasks are the flows (app_task_states)');
  if (!opt.tasks) return ['fail', 'no docs/content/tasks.yaml (step 3: what a customer comes for, from the facts)'];
  const tasks = readJson(opt.tasks);
  if (!Array.isArray(tasks) || !tasks.length) return ['fail', 'docs/content/tasks.yaml is not a list of tasks'];
  const why = [];
  const factsText = opt.facts ? JSON.stringify(readJson(opt.facts)).toLowerCase() : '';
  const norm = x => String(x || '').replace(/[\s\u00a0]+/g, ' ').trim().toLowerCase();
  const ok = [];   // a task with a bad definition is named and not searched for
  // the shape of the required tasks: a price names the service and the amount, hours at least the day, booking is a form
  const SHAPE = { price: t => !t.form && (t.expect || []).length >= 2, hours: t => !t.form && (t.expect || []).length >= 1, booking: t => t.form === true };
  for (const t of tasks) {
    if (!t?.id || !(t.form === true || (Array.isArray(t.expect) && t.expect.length))) { why.push(`task ${t?.id || '?'} needs expect texts or form: true`); continue; }
    if (SHAPE[t.id] && !SHAPE[t.id](t)) { why.push(`task ${t.id}: ${t.id === 'booking' ? 'is form: true' : t.id === 'price' ? 'expects the service and its price (two texts)' : 'expects the day and its hours'}`); continue; }
    const bad = (t.expect || []).filter(e => !factsText.includes(norm(e).replace(/"/g, '\\"')));
    for (const e of bad) why.push(`task ${t.id}: "${e}" is not in the facts register`);
    if (!bad.length) ok.push(t);
  }
  // required ids: the frozen critic's rubric when the loop has one, else those of a local-service web (web-local.yaml)
  let need = ['price', 'hours', 'booking'];
  const fzp = project && path.join(project, '.aid-ui/critic/frozen.json');
  if (fzp && fs.existsSync(fzp)) {
    try { need = (readJson(fzp).rubric?.task_test || []).map(x => x.id); } catch { return ['fail', '.aid-ui/critic/frozen.json is unreadable'] }
  }
  for (const id of need) if (!tasks.some(t => t?.id === id)) why.push(`task ${id} is missing`);
  const found = {};
  for (const w of [1440, 390]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: HEIGHT[w] || 900 } });
    const p = await ctx.newPage();
    const seen = new Map([[home, 0]]), queue = [home];
    try {
      while (queue.length) {
        const key = queue.shift(), hops = seen.get(key);
        await loaded(p, urlOf(key));
        await p.evaluate(async () => { document.querySelectorAll('details').forEach(d => { d.open = true; });
          for (let y = 0; y < document.documentElement.scrollHeight; y += 600) { scrollTo(0, y); await new Promise(r => setTimeout(r, 40)); } scrollTo(0, 0); });
        await p.waitForTimeout(1500);   // entrance motion settles, as content_without_js waits
        // a closed menu (a button with aria-expanded="false") is opened first: on the phone its links are the way on
        for (const b of await p.$$('button[aria-expanded="false"]')) await b.click().catch(() => {});
        await p.waitForTimeout(200);
        const r = await p.evaluate(async ({ tasks }) => {
          const n = x => (x || '').replace(/[\s\u00a0]+/g, ' ').trim().toLowerCase();
          // seen = laid out, not transparent, inside the page and not covered at its centre once scrolled to
          const seen = async e => { const s = getComputedStyle(e); if (s.visibility === 'hidden' || Number(s.opacity) <= 0.5) return false;
            e.scrollIntoView({ block: 'center' }); await new Promise(r => requestAnimationFrame(r));
            const b = e.getBoundingClientRect(); if (!(b.width > 0 && b.height > 0) || b.right < 0 || b.bottom < 0 || b.left > innerWidth) return false;
            const top = document.elementFromPoint(Math.min(Math.max(b.left + b.width / 2, 0), innerWidth - 1), Math.min(Math.max(b.top + b.height / 2, 0), innerHeight - 1));
            return !!top && (e.contains(top) || top.contains(e)); };
          const hit = {};
          for (const t of tasks) {
            if (t.form) { hit[t.id] = false; for (const f of document.forms) if (f.querySelector('input:not([type=hidden]), textarea, select') && f.querySelector('button:not([type=button]), input[type=submit]') && await seen(f)) { hit[t.id] = true; break; } continue; }
            // one short block holds every text (a table row, a list item, a paragraph): the price beside its service
            const want = t.expect.map(n);
            const blocks = [...document.body.querySelectorAll('*')].filter(e => { const x = n(e.innerText); return x.length <= 300 && want.every(w => x.includes(w)); });
            hit[t.id] = false; for (const e of blocks) if (await seen(e)) { hit[t.id] = true; break; }
          }
          const links = [];
          for (const a of document.querySelectorAll('a[href]')) if (await seen(a)) links.push(a.href);   // only links a visitor can see and press
          scrollTo(0, 0);
          return { hit, links };
        }, { tasks: ok });
        for (const [id, ok] of Object.entries(r.hit)) if (ok && !(found[`${id}@${w}`])) found[`${id}@${w}`] = { page: key, hops };
        if (hops >= TASK_HOPS) continue;
        for (const h of r.links) {
          let u; try { u = new URL(h); } catch { continue; }
          if (u.origin !== new URL(base).origin) continue;
          const k = keyOfUrl(u.pathname.slice(new URL(base).pathname.length - 1));
          if (pages.includes(k) && !seen.has(k)) { seen.set(k, hops + 1); queue.push(k); }
        }
      }
    } catch (e) { why.push(`${w} px: ${String(e.message || e).slice(0, 100)}`); } finally { await ctx.close(); }
  }
  const say = [];
  for (const t of ok) for (const w of [1440, 390]) {
    const f = found[`${t.id}@${w}`];
    if (!f) why.push(`${t.id} at ${w} px: not found within ${TASK_HOPS} steps from the home page`);
    else say.push(`${t.id} ${w}: ${f.page} (${f.hops})`);
  }
  return why.length ? ['fail', why.join('; ') + (say.length ? `; found: ${say.join('; ')}` : '')] : ['pass', say.join('; ')];
}

// ---- matrix -------------------------------------------------------------------------
const CHECKS = ['http_200', 'glyph_coverage', 'no_overflow', 'one_line_controls', 'no_placeholders', 'facts_match',
  'brand_assets', 'links_resources', 'required_files', 'axe', 'image_weight', 'lighthouse_mobile', 'seo',
  'app_task_states', 'screenshots_reviewed', 'no_overlap', 'brand_consistency', 'page_weight', 'business_minimum', 'ai_search',
  'brand_package', 'design_standard_doc', 'token_usage', 'sticky_panels', 'keyboard', 'reduced_motion', 'touch_targets',
  'safe_area', 'privacy_before_consent', 'vision_doc', 'coverage', 'customer_page', 'copy_review', 'motion_settled', 'motion_fidelity',
  'content_without_js', 'first_paint_visible', 'form_states', 'task_test', 'photo_slots', 'form_delivery'];
const named = Object.keys(ck.checks || {});
const extra = CHECKS.filter(c => !named.includes(c)), unimpl = named.filter(c => !CHECKS.includes(c));
if (unimpl.length) usage(`checks without an implementation: ${unimpl.join(', ')}`);
// a fixture checks.yaml may name a subset; rows are written only for the named checks
const want = c => named.includes(c);

// ---- P108: the copy of a page, as the copy review and the copy_review row read it ------------
// COPY_JS — in the browser, document order: title, description, og texts; headings h1-h3; text
// blocks (p, li not wrapping a p or heading, td, th, dt, dd, figcaption, blockquote, caption,
// legend, summary); calls to action (buttons, button-like links); navigation and footer links;
// form labels, placeholders and the selected option; validation messages present in the DOM
// (shown or not); alt and aria-label texts; and any other visible element's own text (a div or
// span with text of its own) as "text". Visible elements only, except validation messages; an element
// pushed wholly off the page (left or top, e.g. a spam-trap field) is not visible.
// Limits: text generated by CSS (::before content) is not read; a container taken as "text" takes
// its nested text with it (the text is in the subject, as one block).
const COPY_JS = () => {
  // pushed wholly off the page to the left or top (a spam trap at left:-9999px) is not seen; a 1px
  // clipped screen-reader text inside the page is, and stays copy; a fixed element is measured against
  // the viewport (no scroll added). Limit: text moved out of its own box (text-indent) is still read
  // the intro overlay (data-aid-intro, FB-25) is decoration that leaves within seconds: its letters are not copy
  const vis = e => { const r = e.getBoundingClientRect(), s = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !e.closest('[data-aid-intro]')
      && r.right + (s.position === 'fixed' ? 0 : scrollX) > 0 && r.bottom + (s.position === 'fixed' ? 0 : scrollY) > 0; };
  const clean = x => (x || '').replace(/\s+/g, ' ').trim();
  const out = [], taken = new Set();
  const add = (kind, text, e) => { text = clean(text); if (text) out.push({ kind, text }); if (e) taken.add(e); };
  add('title', document.title);
  add('description', document.querySelector('meta[name="description"]')?.content);
  add('og', document.querySelector('meta[property="og:title"]')?.content);
  add('og', document.querySelector('meta[property="og:description"]')?.content);
  const KIND = [
    ['h1', 'h1'], ['h2', 'h2'], ['h3', 'h3'],
    ['error', '[role="alert"], .error, [data-error]'],
    ['cta', 'button, [role="button"], input[type="submit"], a.btn, a[class*="button"]'],
    ['nav', 'nav a, footer a'],
    ['label', 'label, legend, summary'],
    ['p', 'p, td, th, dt, dd, figcaption, blockquote, caption'],
    ['li', 'li'],
  ];
  const kindOf = e => (KIND.find(([, sel]) => e.matches(sel)) || [])[0];
  for (const e of document.body.querySelectorAll('*')) {
    if (e.closest('script, style, noscript, template, svg')) continue;
    const kind = kindOf(e);
    const err = kind === 'error';
    if (!err && !vis(e)) continue;
    if ([...taken].some(t => t.contains(e))) continue;   // inside a block already taken
    if (e.tagName === 'IMG') { add('alt', e.getAttribute('alt')); continue; }
    if ((e.tagName === 'INPUT' || e.tagName === 'TEXTAREA') && e.placeholder) add('label', e.placeholder);
    if (e.tagName === 'INPUT' && e.type === 'submit') { add('cta', e.value, e); continue; }
    if (e.tagName === 'SELECT') { add('label', e.selectedOptions[0]?.textContent, e); continue; }
    if (kind === 'li' && e.querySelector('p, h1, h2, h3')) continue;
    // an aria-label different from the visible text is copy too (screen readers say it)
    const aria = clean(e.getAttribute('aria-label'));
    if (aria && aria !== clean(e.innerText)) add('alt', aria);
    if (kind) { add(kind, err ? (e.getAttribute('data-error') || e.textContent) : (e.innerText || e.getAttribute('aria-label')), e); continue; }
    if (aria && !clean(e.innerText)) { taken.add(e); continue; }
    const own = [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' ');
    if (clean(own)) add('text', e.innerText, e);
  }
  return { lang: document.documentElement.lang || '', blocks: out };
};
// copyOf — the blocks at 1440 px in order, then those 390 px shows more often (a multiset: a
// repeated block counts each time); sha256 over the ordered block texts only
async function copyOf(browser, url) {
  const runs = [];
  let lang = '';
  for (const w of [1440, 390]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: HEIGHT[w] || 900 } });
    const page = await ctx.newPage();
    await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    await page.waitForTimeout(300);
    // a closed <details> hides its answer, and a reviewer that sees ten questions and no answers fails the
    // page for text it never read (Coufal 11. 10. 2026): open every one before reading
    await page.evaluate(() => document.querySelectorAll('details').forEach(d => { d.open = true; }));
    const r = await page.evaluate(COPY_JS);
    lang = lang || r.lang;
    runs.push(r.blocks);
    await ctx.close();
  }
  const blocks = [...runs[0]], have = new Map();
  for (const b of runs[0]) { const k = b.kind + '\u0000' + b.text; have.set(k, (have.get(k) || 0) + 1); }
  for (const b of runs[1]) {
    const k = b.kind + '\u0000' + b.text;
    if ((have.get(k) || 0) > 0) have.set(k, have.get(k) - 1); else blocks.push(b);
  }
  const hash = createHash('sha256').update(JSON.stringify(blocks.map(b => b.text))).digest('hex');
  return { lang: lang.slice(0, 2).toLowerCase(), sha256: hash, blocks: blocks.map((b, i) => ({ id: `b${i + 1}`, ...b })) };
}
// structure page URL -> build key ("/" -> index.html, "/o-nas" -> o-nas/index.html)
const keyOfUrl = u => { const x = String(u || '').replace(/^\/+|\/+$/g, ''); return x === '' ? 'index.html' : (x.endsWith('.html') ? x : `${x}/index.html`); };
const LEGAL = new Set((st.structure?.pages || []).filter(p => p?.legal === true).map(p => keyOfUrl(p.url)));
if (opt['copy-subject']) {
  const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
  const subject = { build_id: st.build?.id || null, pages: {} };
  for (const p of pages) subject.pages[p] = { legal: LEGAL.has(p), ...(await copyOf(browser, urlOf(p))) };
  await browser.close();
  fs.writeFileSync(path.resolve(opt['copy-subject']), JSON.stringify(subject, null, 1));
  console.log(`copy subject: ${Object.keys(subject.pages).length} pages -> ${opt['copy-subject']}`);
  process.exit(0);
}

const isApp = ['webapp', 'pwa'].includes(st.variant?.type);
const flows = isApp ? (st.structure?.flows || []) : [];
const roles = (st.structure?.roles || []).map(r => String(r?.id ?? r));
const matrix = [];
for (const p of pages) for (const v of VPS) for (const b of BRS) matrix.push({ page: p, viewport: v, browser: b, role: '', state: '' });
for (const f of flows) for (const s of f.states || []) for (const r of (roles.length ? roles : [''])) for (const v of VPS) for (const b of BRS)
  matrix.push({ page: String(f.id), viewport: v, browser: b, role: r, state: String(s?.id ?? s) });

const rows = [];
const AP = ck.applies || {};
// applies.<check>: browsers / viewports subsets, flows false, scope project = one row (home page,
// last viewport, first browser left), the same rule as combos() in aid-ui-state.sh finish
const applies = (check, m) => { const a = AP[check] || {};
  const brs = a.browsers ? BRS.filter(b => a.browsers.map(String).includes(b)) : BRS;
  const vps = a.viewports ? VPS.filter(v => a.viewports.map(String).includes(v)) : VPS;
  // a partial m (only a browser: "does the check run in this browser at all?") is not narrowed further
  if (!brs.includes(m.browser) || (m.viewport !== undefined && !vps.includes(m.viewport)) || (a.flows === false && m.state)) return false;
  return a.scope !== 'project' || m.page === undefined
    || (m.page === home && m.viewport === vps[vps.length - 1] && m.browser === brs[0] && !m.state); };
const put = (m, check, status, detail) => { if (want(check) && applies(check, m)) rows.push({ check, ...m, status, detail: detail || '' }); };
const facts = factLeaves(), brand = brandFiles();
const seo = want('seo') || want('ai_search') ? runSeo() : null;
// ai: false -> the seo row (every finding not named ai-*), true -> the ai_search row. Site-wide
// ai-* findings (brief, robots.txt, llms.txt) go to the home page's rows only, not to every page.
const seoRow = (p, ai = false) => {
  if (seo.error) return ['not_covered', seo.error];
  if (ai && !st.options?.seo) return ['pass', 'N/A: SEO is not part of this project (options.seo false)'];
  const mine = seo.findings.filter(f => f.check.startsWith('ai-') === ai
    && (f.page === p || (!pages.includes(f.page) && (!ai || p === home || p === '_site'))));
  const bl = mine.filter(f => f.level === 'BLOCKER'), wn = mine.filter(f => f.level === 'WARN');
  const txt = xs => xs.map(f => `${f.check}: ${f.detail}`).join('; ');
  return bl.length ? ['fail', `BLOCKER ${txt(bl)}`] : ['pass', wn.length ? `WARN ${txt(wn)}` : ''];
};
function runPy(script, args, label) {
  const r = spawnSync('python3', [path.join(HERE, '../../scripts', script), ...args], { encoding: 'utf8' });
  const miss = (r.stdout || '').split('\n').filter(l => l.startsWith('MISSING')).map(l => l.slice(8));
  if (r.status !== 0 && !(r.status === 1 && miss.length)) return ['not_covered', `${label} exit ${r.status}: ${(r.stderr || '').trim().split('\n').pop().slice(0, 200)}`];
  return miss.length ? ['fail', `missing: ${miss.join('; ')}`] : ['pass', ''];
}
// vision_doc: docs/product-vision.md has the template's parts (only with options.vision)
const visionDoc = !want('vision_doc') ? null : !project ? ['not_covered', 'no --project']
  : !st.options?.vision ? NA('no product vision in this project (options.vision false)') : runPy('aid-ui-vision-check.py', [project], 'aid-ui-vision-check.py');
// coverage: the coverage map still matches the standards (aid-ui-coverage.sh check exit 0)
const coverageRow = !want('coverage') ? null : (() => {
  if (!project) return ['not_covered', 'no --project'];
  const r = spawnSync('bash', [path.join(HERE, '../../scripts/aid-ui-coverage.sh'), 'check', project], { encoding: 'utf8' });
  return r.status === 0 ? ['pass', ''] : r.status === 2 ? ['not_covered', `aid-ui-coverage.sh check could not read the standards: ${(r.stderr || '').trim().split('\n').pop().slice(0, 200)}`] : ['fail', `aid-ui-coverage.sh check exit ${r.status}: ${((r.stdout || '') + (r.stderr || '')).trim().split('\n').slice(0, 3).join(' | ').slice(0, 300)}`];
})();
// copy_review (P108): the page's copy now, the facts and the approved context now, against the review
// stored by aid-ui-state.sh copy-record; the gate never calls a model
const fileSha = f => (fs.existsSync(f) ? sha(f) : null);
const COPY_REC = st.copy_review?.pages || {};
const copyNow = project ? { facts: fileSha(path.join(project, 'docs/content/facts.yaml')), context: fileSha(path.join(project, 'docs/content/product-context.md')) } : null;
async function copyRow(browser, p) {
  if (!project) return ['not_covered', 'no --project'];
  const rec = COPY_REC[p];
  if (!rec) return ['not_covered', 'kontrola textů neproběhla (krok 7 bod 1a)'];
  const cur = await copyOf(browser, urlOf(p));
  const why = [];
  if (rec.subject_sha256 !== cur.sha256) why.push('text se změnil po kontrole');
  if (rec.facts_sha256 !== copyNow.facts) why.push('fakta se změnila po kontrole textů');
  if (rec.context_sha256 !== copyNow.context) why.push('podklady se změnily po kontrole textů');
  if (why.length) return ['fail', why.join('; ')];
  return rec.verdict === 'pass' ? ['pass', `${rec.provider || '?'} ${rec.at || ''}`.trim()] : ['fail', (rec.blocking || []).slice(0, 4).join('; ') || 'kontrola textů neprošla'];
}
// customer_page: the page the customer gets exists, is from this build, has no internal word (exit 3 = not made yet)
const customerPage = !want('customer_page') ? null : !project ? ['not_covered', 'no --project'] : (() => {
  const r = spawnSync('python3', [path.join(HERE, '../../scripts/aid-ui-customer-page.py'), project, '--check'], { encoding: 'utf8' });
  const say = ((r.stdout || '') + (r.stderr || '')).trim().split('\n').slice(0, 3).join(' | ').slice(0, 300);
  return r.status === 0 ? ['pass', ''] : r.status === 1 ? ['fail', say] : ['not_covered', r.status === 3 ? 'made after a green gate (step 7b), then the gate again' : `aid-ui-customer-page.py exit ${r.status}: ${say}`];
})();
const brandPkg = want('brand_package') ? (project ? runBrandPackage() : ['not_covered', 'no --project']) : null;
const motionFid = want('motion_fidelity') ? (project ? runMotionFidelity() : ['not_covered', 'no --project']) : null;
const designDoc = want('design_standard_doc') ? (project ? runDesignDoc() : ['not_covered', 'no --project']) : null;
const glyphs = {}, lhs = {};
for (const p of pages) {
  if (want('glyph_coverage') && BRS.some(b => applies('glyph_coverage', { browser: b }))) glyphs[p] = glyph(urlOf(p));
  if (want('lighthouse_mobile')) lhs[p] = await lighthouse(urlOf(p));
}
let creds = {};
if (project && fs.existsSync(path.join(project, '.aid-ui/test-credentials.json'))) creds = readJson(path.join(project, '.aid-ui/test-credentials.json'));

const PAGE_CHECKS = ['http_200', 'no_overflow', 'one_line_controls', 'no_placeholders', 'facts_match', 'brand_assets', 'links_resources', 'axe', 'image_weight', 'screenshots_reviewed',
  'token_usage', 'sticky_panels', 'keyboard', 'reduced_motion', 'touch_targets', 'safe_area', 'privacy_before_consent',
  'no_overlap', 'page_weight', 'business_minimum', 'motion_settled', 'content_without_js', 'first_paint_visible', 'form_states', 'photo_slots'];
// brand_consistency also compares header and footer with the first page loaded in the same browser and viewport
const firstShape = {};
for (const b of BRS) {
  const type = { chromium, webkit }[b];
  let browser = null, why = '';
  try {
    browser = type ? await type.launch(b === 'chromium' ? { executablePath: process.env.CHROME || undefined } : {}) : null;
    if (!type) why = `unknown browser ${b}`;
  } catch (e) {
    why = `${b} could not launch (${String(e.message).split('\n')[0].slice(0, 120)}); install it: cd lib/ui-fidelity && npx playwright install ${b} (system libraries: sudo npx playwright install-deps ${b})`;
  }
  for (const v of VPS) {
    const ms = matrix.filter(m => m.browser === b && m.viewport === v);
    if (!browser) { for (const m of ms) for (const c of named) put(m, c, 'not_covered', why); continue; }
    const ctx = await browser.newContext({ viewport: { width: Number(v), height: HEIGHT[v] || 900 } });
    for (const m of ms) {
      const flow = flows.find(f => String(f.id) === m.page && m.state);
      let run = null;
      if (flow) {
        // flow ids come from the project's state: allowlisted, and the module must resolve inside .aid-ui/scenarios
        if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(m.page)) { for (const c of named) put(m, c, 'not_covered', `refused flow id ${JSON.stringify(m.page)}: must match ^[a-z0-9][a-z0-9-]{0,63}$; no scenario imported`); continue; }
        const scen = project && path.join(project, '.aid-ui/scenarios');
        let script = scen && inside(scen, `${m.page}.mjs`);
        // a symlinked scenario must not lead outside the scenarios directory either
        if (script && fs.existsSync(script)) script = fs.statSync(script).isFile() && inside(fs.realpathSync(scen), path.basename(script)) === fs.realpathSync(script) ? script : null;
        if (!script || !fs.existsSync(script)) { for (const c of named) put(m, c, 'not_covered', `no scenario .aid-ui/scenarios/${m.page}.mjs`); continue; }
        const { default: scenario } = await import(pathToFileURL(script).href);
        run = async page => scenario({ page, base, role: m.role, state: m.state, credentials: creds[m.role] || null });
      }
      // page, role and state come from the project's state: one filename segment, no path separators or leading dots
      const key = [b, v, `${m.page}${m.role ? '.' + m.role : ''}${m.state ? '.' + m.state : ''}.png`.replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^\.+/, '_')];
      const r = await pageRows(ctx, flow ? base : urlOf(m.page), key, m.role, m.state, run, facts, brand, c => applies(c, m));
      if (r.error) {
        for (const c of named) put(m, c, flow && c === 'app_task_states' ? 'fail' : 'not_covered', `${flow ? 'scenario' : 'page'} failed: ${r.error}`);
        continue;
      }
      for (const c of PAGE_CHECKS) put(m, c, ...r[c]);
      if (!flow) {
        const k = `${b}/${v}`, f0 = firstShape[k] || (firstShape[k] = { page: m.page, header: r.header, footer: r.footer });
        const diff = [r.header !== f0.header && 'header', r.footer !== f0.footer && 'footer'].filter(Boolean);
        put(m, 'brand_consistency', ...(r.brand_consistency[0] === 'fail' || !diff.length ? r.brand_consistency
          : ['fail', `${diff.join(' and ')} differ from page ${f0.page}`]));
      } else put(m, 'brand_consistency', ...r.brand_consistency);
      put(m, 'app_task_states', 'pass', flow ? `scenario ${m.page} / ${m.state} passed` : (isApp ? 'a page, not a task' : 'not an application'));
      if (flow) {
        put(m, 'glyph_coverage', 'not_covered', 'checks.yaml applies it to flow states; the gate runs it on pages only');
        put(m, 'lighthouse_mobile', 'not_covered', 'checks.yaml applies it to flow states; the gate runs it on pages only');
        const site = requiredFiles(r.html).filter(x => !x.startsWith('no og') && !x.startsWith('og:'));
        put(m, 'required_files', site.length ? 'fail' : 'pass', site.join(', '));
        put(m, 'seo', ...(seo ? seoRow('_site') : ['pass', '']));
        put(m, 'ai_search', ...(seo ? seoRow('_site', true) : ['pass', '']));
        continue;
      }
      if (b !== 'chromium') put(m, 'glyph_coverage', 'not_covered', 'the font check reads Chrome DevTools data; Chromium only');
      // ponytail: aid-ui-glyph-check.mjs renders at 1440 px only; the result stands for every viewport
      else if (glyphs[m.page]) put(m, 'glyph_coverage', glyphs[m.page].status, `${glyphs[m.page].detail}${m.viewport === '1440' ? '' : '; the 1440 px result, copied to this viewport'}`);
      if (want('lighthouse_mobile')) put(m, 'lighthouse_mobile', lhs[m.page].status, `${lhs[m.page].detail} (fixed mobile profile, one run per page, copied to every viewport)`);
      const miss = requiredFiles(r.html);
      put(m, 'required_files', miss.length ? 'fail' : 'pass', miss.join(', '));
      if (seo) { put(m, 'seo', ...seoRow(m.page)); put(m, 'ai_search', ...seoRow(m.page, true)); }
      if (brandPkg) put(m, 'brand_package', ...brandPkg);
      if (motionFid) put(m, 'motion_fidelity', ...motionFid);
      if (designDoc) put(m, 'design_standard_doc', ...designDoc);
      if (visionDoc) put(m, 'vision_doc', ...visionDoc);
      if (coverageRow) put(m, 'coverage', ...coverageRow);
      if (customerPage) put(m, 'customer_page', ...customerPage);
      if (want('task_test') && applies('task_test', m)) put(m, 'task_test', ...(await taskTest(browser)));
      if (want('form_delivery') && applies('form_delivery', m)) put(m, 'form_delivery', ...(await formDelivery(browser)));
      if (want('copy_review') && applies('copy_review', m)) put(m, 'copy_review', ...(await copyRow(browser, m.page)));
    }
    await ctx.close();
  }
  if (browser) await browser.close();
}

const result = { run_at: new Date().toISOString(), build_id: st.build?.id, matrix, rows, fingerprints: fps };
fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(result, null, 1));
const count = rows.reduce((a, r) => (a[r.status] = (a[r.status] || 0) + 1, a), {});
console.log(`VERIFY: ${JSON.stringify(count)} -> ${path.join(out, 'result.json')}`);
if (extra.length) console.log(`note: checks not named in this checks.yaml, not run: ${extra.join(', ')}`);
