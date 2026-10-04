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
  await scrollAll(page);
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

// ---- matrix -------------------------------------------------------------------------
const CHECKS = ['http_200', 'glyph_coverage', 'no_overflow', 'one_line_controls', 'no_placeholders', 'facts_match',
  'brand_assets', 'links_resources', 'required_files', 'axe', 'image_weight', 'lighthouse_mobile', 'seo',
  'app_task_states', 'screenshots_reviewed', 'no_overlap', 'brand_consistency', 'page_weight', 'business_minimum', 'ai_search',
  'brand_package', 'design_standard_doc', 'token_usage', 'sticky_panels', 'keyboard', 'reduced_motion', 'touch_targets',
  'safe_area', 'privacy_before_consent', 'vision_doc', 'coverage', 'customer_page'];
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
// customer_page: the page the customer gets exists, is from this build, has no internal word (exit 3 = not made yet)
const customerPage = !want('customer_page') ? null : !project ? ['not_covered', 'no --project'] : (() => {
  const r = spawnSync('python3', [path.join(HERE, '../../scripts/aid-ui-customer-page.py'), project, '--check'], { encoding: 'utf8' });
  const say = ((r.stdout || '') + (r.stderr || '')).trim().split('\n').slice(0, 3).join(' | ').slice(0, 300);
  return r.status === 0 ? ['pass', ''] : r.status === 1 ? ['fail', say] : ['not_covered', r.status === 3 ? 'made after a green gate (step 7b), then the gate again' : `aid-ui-customer-page.py exit ${r.status}: ${say}`];
})();
const brandPkg = want('brand_package') ? (project ? runBrandPackage() : ['not_covered', 'no --project']) : null;
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
      if (designDoc) put(m, 'design_standard_doc', ...designDoc);
      if (visionDoc) put(m, 'vision_doc', ...visionDoc);
      if (coverageRow) put(m, 'coverage', ...coverageRow);
      if (customerPage) put(m, 'customer_page', ...customerPage);
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
