// aid-ui-verify.mjs — the /aid-ui gate checks (P103 Step 7); run through aid-ui-verify.sh.
//
//   node aid-ui-verify.mjs --state <brand-state.json> --checks <checks.json> --site <dir>
//        --base <url> --out <dir> --seo <aid-ui-seo-check.py> [--project <dir>] [--facts <facts.json>]
//
// Matrix = pages (the keys of state.build.fingerprints but _site) x checks.viewports x
// checks.browsers, role and state ""; for variant webapp|pwa also structure.flows[].id (as
// page) x its states x structure.roles (or "") x viewports x browsers; checks.applies narrows a
// check (browsers subset, flows false) and no row is written outside it. One function per
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
// Exit: 0 result written, 1 run error, 2 usage.
import { chromium, webkit } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2), opt = {};
for (let i = 0; i < argv.length; i += 2) {
  if (!argv[i].startsWith('--') || argv[i + 1] === undefined) usage();
  opt[argv[i].slice(2)] = argv[i + 1];
}
function usage(m) { console.error('usage: aid-ui-verify.mjs --state <f> --checks <f> --site <dir> --base <url> --out <dir> --seo <py> [--project <dir>] [--facts <f>]' + (m ? `\n${m}` : '')); process.exit(2); }
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
// every string/number leaf of facts.yaml, whitespace-normalised
function factLeaves() {
  if (!opt.facts) return null;
  const acc = [];
  const walk = v => { if (v && typeof v === 'object') Object.values(v).forEach(walk); else if (v !== null && v !== undefined) acc.push(norm(String(v))); };
  walk(readJson(opt.facts));
  return acc;
}
const norm = s => s.replace(/[\s  ]+/g, ' ').trim().toLowerCase();
const digits = s => s.replace(/\D/g, '');
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
    o.privacyLink = [...document.querySelectorAll('a[href]')].some(a => /osobn[ií]ch údaj|zpracování údaj|ochrana údaj|GDPR|soukromí|privacy/i.test(a.textContent + ' ' + a.getAttribute('href')));
    return o;
  });
}
// ponytail: one fixed page budget (bytes transferred incl. fonts and images); a per-project budget when a site needs it
const PAGE_BUDGET = 1024 * 1024;
const PLACEHOLDER = /lorem ipsum|\bTODO\b|\bXXX\b|example\.(com|org|cz)|\.invalid\b|\+420 ?000|doplní se|fiktivn/gi;
const PLACEHOLDER_IMG = /placeholder|placehold\.|picsum\.|dummyimage/i;
// ponytail: facts = phone numbers, prices and times in the visible text; other claims need the reviewer
const FACT_RE = /(\+?\d[\d ]{7,}\d)|(\d[\d  ]*(?:[.,]\d+)?\s?(?:Kč|CZK|€|EUR))|(\b\d{1,2}[:.]\d{2}\b)/g;

async function pageRows(ctx, url, key, role, state, run, facts, brand) {
  const page = await ctx.newPage();
  const bad = [], imgs = [];
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
  await scrollAll(page);
  const o = await inPage(page);
  res.no_overflow = o.overflow ? ['fail', 'the page scrolls sideways'] : ['pass', ''];
  res.one_line_controls = o.wrapped.length ? ['fail', `wraps: ${o.wrapped.join(' | ')}`] : ['pass', ''];
  const ph = [...(o.text.match(PLACEHOLDER) || []), ...o.hrefs.filter(h => PLACEHOLDER.test(h)), ...o.imgs.filter(i => PLACEHOLDER_IMG.test(i.src)).map(i => i.src)];
  PLACEHOLDER.lastIndex = 0;
  res.no_placeholders = ph.length ? ['fail', `placeholders: ${[...new Set(ph)].join(', ')}`] : ['pass', ''];
  if (!facts) res.facts_match = ['not_covered', 'no docs/content/facts.yaml'];
  else {
    const unknown = [...o.text.matchAll(FACT_RE)].map(m => m[0].trim()).filter(t => {
      const n = norm(t), d = digits(t);
      return !facts.some(f => f.includes(n) || (d.length >= 7 && digits(f).includes(d)));
    });
    res.facts_match = unknown.length ? ['fail', `not in facts.yaml: ${[...new Set(unknown)].join(', ')}`] : ['pass', ''];
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
  res.html = await page.content();
  await page.close();
  return res;
}

// ---- matrix -------------------------------------------------------------------------
const CHECKS = ['http_200', 'glyph_coverage', 'no_overflow', 'one_line_controls', 'no_placeholders', 'facts_match',
  'brand_assets', 'links_resources', 'required_files', 'axe', 'image_weight', 'lighthouse_mobile', 'seo',
  'app_task_states', 'screenshots_reviewed', 'no_overlap', 'brand_consistency', 'page_weight', 'business_minimum', 'ai_search',
  'brand_package'];
const named = Object.keys(ck.checks || {});
const extra = CHECKS.filter(c => !named.includes(c)), unimpl = named.filter(c => !CHECKS.includes(c));
if (unimpl.length) usage(`checks without an implementation: ${unimpl.join(', ')}`);
// a fixture checks.yaml may name a subset; rows are written only for the named checks
const want = c => named.includes(c);

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
const brandPkg = want('brand_package') ? (project ? runBrandPackage() : ['not_covered', 'no --project']) : null;
const glyphs = {}, lhs = {};
for (const p of pages) {
  if (want('glyph_coverage') && BRS.some(b => applies('glyph_coverage', { browser: b }))) glyphs[p] = glyph(urlOf(p));
  if (want('lighthouse_mobile')) lhs[p] = await lighthouse(urlOf(p));
}
let creds = {};
if (project && fs.existsSync(path.join(project, '.aid-ui/test-credentials.json'))) creds = readJson(path.join(project, '.aid-ui/test-credentials.json'));

const PAGE_CHECKS = ['http_200', 'no_overflow', 'one_line_controls', 'no_placeholders', 'facts_match', 'brand_assets', 'links_resources', 'axe', 'image_weight', 'screenshots_reviewed',
  'no_overlap', 'page_weight', 'business_minimum'];
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
      const r = await pageRows(ctx, flow ? base : urlOf(m.page), key, m.role, m.state, run, facts, brand);
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
