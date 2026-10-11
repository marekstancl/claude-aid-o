// aid-ui-measure.mjs — measure what the built site really uses, for the project design standard.
//   node aid-ui-measure.mjs [--storage-state <state.json>] [--build <build id>] <base url> <out.json> <page>...
// --build records which build was measured (aid-ui-state.sh build-id <site dir>); the design
// standard check refuses a document measured on another build.
// Pages are relative to the base (index.html, kontakt/index.html); --storage-state is a Playwright
// storage state of a logged-in test account, for an app behind a login.
// At 390 and 1440 px in Chrome, per page: every on-screen control (<button>, [role=button],
// input[type=submit|button|reset], a link with a background or a padded border; nothing under
// 2 px, nothing parked off screen) with computed background, text colour, border, radius,
// height, font; per role group one element is hovered, focused and (if a button) disabled to
// record those states; form fields; h1-h3 and body type; media-query widths (nested rules too);
// transitions over 10 ms; z-index of positioned elements (hidden ones too); icons (svg/img up to
// 48 px, not a logo); whether anything moves under prefers-reduced-motion (first page only).
// Groups = background + colour + border (one group = one role candidate; the font and height are
// recorded per viewport, since a responsive control changes size but not its role).
// A page that fails to load is listed under errors, not fatal.
// Exit: 0 written, 1 failure, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';

const argv = process.argv.slice(2);
let storageState, build = null;
while (argv[0] === '--storage-state' || argv[0] === '--build') {
  if (argv[0] === '--storage-state') storageState = argv[1]; else build = argv[1];
  argv.splice(0, 2);
}
const [base, out, ...pages] = argv;
if (!base || !out || !pages.length) { console.error('usage: aid-ui-measure.mjs [--storage-state <f>] [--build <id>] <base url> <out.json> <page>...'); process.exit(2); }
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const groups = new Map(), fields = new Map(), type = {}, bps = new Set(), trans = new Set(), z = new Set(), errors = [];
let moves = false, icons = 0;

const COLLECT = () => {
  const cs = e => getComputedStyle(e);
  const vis = e => { const b = e.getBoundingClientRect(); return b.width >= 2 && b.height >= 2 && b.bottom + scrollY > 0 && b.right > 0 && cs(e).visibility !== 'hidden'; };
  const transparent = c => c === 'rgba(0, 0, 0, 0)' || c === 'transparent';
  const ms = v => Math.max(0, ...String(v).split(',').map(x => parseFloat(x) * (x.trim().endsWith('ms') ? 1 : 1000)));
  let id = 0;
  const controls = [...document.querySelectorAll('button, [role=button], input[type=submit], input[type=button], input[type=reset], a')].filter(vis).filter(e => {
    if (e.tagName !== 'A' || e.getAttribute('role') === 'button') return true;
    const s = cs(e);
    return !transparent(s.backgroundColor) || (parseFloat(s.borderTopWidth) > 0 && s.borderTopStyle !== 'none' && parseFloat(s.paddingLeft) >= 8);
  }).map(e => { const s = cs(e); const tag = `m${id++}`; e.setAttribute('data-aid-measure', tag); return {
    tag, button: e.tagName === 'BUTTON' || e.tagName === 'INPUT',
    key: [s.backgroundColor, s.color, s.borderTopWidth !== '0px' ? `${s.borderTopWidth} ${s.borderTopColor}` : 'none'].join(' | '),
    background: s.backgroundColor, color: s.color, border: s.borderTopWidth !== '0px' ? `${s.borderTopWidth} ${s.borderTopStyle} ${s.borderTopColor}` : 'none',
    radius: s.borderTopLeftRadius, height: Math.round(e.getBoundingClientRect().height), font: `${s.fontWeight} ${s.fontSize}`,
    text: (e.innerText || e.value || e.getAttribute('aria-label') || '').trim().slice(0, 40) }; });
  const fields = [...document.querySelectorAll('input:not([type=submit]):not([type=button]):not([type=reset]):not([type=hidden]), textarea, select')].filter(vis)
    .map(e => { const s = cs(e); return { tag: e.tagName.toLowerCase() + (e.type ? `[${e.type}]` : ''), border: `${s.borderTopWidth} ${s.borderTopColor}`,
      radius: s.borderTopLeftRadius, height: Math.round(e.getBoundingClientRect().height), background: s.backgroundColor }; });
  const t = {};
  // p: the most common visible paragraph style, not the first one (a lead paragraph is bigger and the
  // standard then contradicts DESIGN.md's body size - Coufal 11. 10. 2026)
  const common = sel => { const n = new Map(); for (const e of [...document.querySelectorAll(sel)].filter(vis)) { const k = cs(e).fontSize + cs(e).fontWeight; n.set(k, [(n.get(k)?.[0] || 0) + 1, e]); }
    return [...n.values()].sort((a, b) => b[0] - a[0])[0]?.[1]; };
  for (const sel of ['h1', 'h2', 'h3', 'p']) { const e = sel === 'p' ? common('p') : [...document.querySelectorAll(sel)].find(vis); if (e) { const s = cs(e);
    t[sel] = { family: s.fontFamily, size: s.fontSize, weight: s.fontWeight, line: s.lineHeight, spacing: s.letterSpacing }; } }
  const bps = [];
  const walk = rules => { for (const r of rules) {
    if (r.media) for (const m of r.media) for (const x of m.matchAll(/((?:min|max)-width:\s*[\d.]+(?:px|rem|em))|(width\s*[<>]=?\s*[\d.]+(?:px|rem|em))/g)) bps.push(x[0]);
    if (r.cssRules) walk(r.cssRules);
    if (r.styleSheet) { try { walk(r.styleSheet.cssRules); } catch { /* cross-origin */ } } } };
  for (const sh of document.styleSheets) { try { walk(sh.cssRules); } catch { /* cross-origin */ } }
  const all = [...document.querySelectorAll('body *')];
  const shown = all.filter(vis);
  const trans = shown.map(e => cs(e).transitionDuration).filter(v => ms(v) > 10);
  const anim = shown.some(e => cs(e).animationName !== 'none' && ms(cs(e).animationDuration) > 10);
  const z = all.filter(e => cs(e).position !== 'static' && cs(e).zIndex !== 'auto')
    .map(e => `${cs(e).zIndex} ${e.tagName.toLowerCase()}${typeof e.className === 'string' && e.className ? '.' + e.className.split(' ')[0] : ''}`);
  const icons = shown.filter(e => (e.tagName === 'svg' || e.tagName === 'IMG') && !/logo|brand|znack/i.test((e.className?.baseVal ?? e.className ?? '') + (e.getAttribute('alt') || '') + (e.closest('a[href="/"], header .logo') ? 'logo' : ''))
    && e.getBoundingClientRect().width <= 48 && e.getBoundingClientRect().height <= 48).length;
  return { controls, fields, t, bps, trans, anim, z, icons };
};

for (const [w, h] of [[390, 844], [1440, 900]]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, storageState });
  const page = await ctx.newPage();
  for (const p of pages) {
    try {
      await page.goto(new URL(p, base).href, { waitUntil: 'load', timeout: 20000 });
      await page.waitForTimeout(300);
    } catch (e) { errors.push(`${p} @${w}: ${String(e.message).split('\n')[0]}`); continue; }
    const r = await page.evaluate(COLLECT);
    for (const c of r.controls) {
      let g = groups.get(c.key);
      if (!g) {
        g = { role_key: c.key, background: c.background, color: c.color, border: c.border, radius: c.radius, font: {}, height: {}, count: 0, pages: new Set(), examples: new Set(), states: null };
        groups.set(c.key, g);
      }
      g.n = g.n || {}; g.n[w] = (g.n[w] || 0) + 1; g.count = Math.max(...Object.values(g.n));   // a mobile-only control (Menu) counts too
      g.pages.add(p); if (g.examples.size < 4 && c.text) g.examples.add(c.text);
      g.height[w] = Math.max(g.height[w] || 0, c.height); g.font[w] = g.font[w] || c.font;
      if (!g.states) {   // one element per role: hover, focus, disabled - at the first width that shows it (Menu exists only on mobile)
        // a state is read at the END of its transition (finish() every running one), or a 0.5 s colour
        // change is measured half-way and the standard shows a colour no token has (Coufal 11. 10. 2026)
        const sel = `[data-aid-measure="${c.tag}"]`, look = () => page.$eval(sel, e => { e.getAnimations().forEach(a => { try { a.finish(); } catch {} }); const s = getComputedStyle(e);
          return `${s.backgroundColor} / ${s.color}${s.outlineStyle !== 'none' && s.outlineWidth !== '0px' ? ` / obrys ${s.outlineWidth} ${s.outlineColor}` : ''}`; });
        g.states = {};
        try { await page.hover(sel, { timeout: 2000 }); g.states.hover = await look(); } catch { g.states.hover = '-'; }
        try { await page.mouse.move(0, 0); await page.keyboard.press('Tab'); await page.focus(sel); g.states.focus = await look(); } catch { g.states.focus = '-'; }
        if (c.button) {
          try { await page.$eval(sel, e => { e.disabled = true; }); g.states.disabled = await look(); await page.$eval(sel, e => { e.disabled = false; }); } catch { g.states.disabled = '-'; }
        } else g.states.disabled = 'odkaz';
      }
    }
    for (const f of r.fields) { const k = `${f.tag} ${f.border} ${f.radius}`; const g = fields.get(k) || { ...f, height: {} }; g.height[w] = Math.max(g.height[w] || 0, f.height); fields.set(k, g); }
    if (w === 1440) { Object.assign(type, Object.fromEntries(Object.entries(r.t).filter(([k]) => !type[k]))); icons += r.icons; }
    r.bps.forEach(b => bps.add(b)); r.trans.forEach(t => trans.add(t)); r.z.forEach(v => z.add(v));
  }
  await ctx.close();
}
try {   // prefers-reduced-motion: the first page is enough to see whether anything still moves
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce', storageState });
  const page = await ctx.newPage();
  await page.goto(new URL(pages[0], base).href, { waitUntil: 'load', timeout: 20000 });
  const r = await page.evaluate(COLLECT);
  moves = r.anim || r.trans.length > 0;
  await ctx.close();
} catch (e) { errors.push(`reduced motion: ${String(e.message).split('\n')[0]}`); }
await browser.close();
const res = { build, pages, controls: [...groups.values()].sort((a, b) => b.count - a.count).map(g => ({ ...g, pages: [...g.pages], examples: [...g.examples] })),
  fields: [...fields.values()], type, breakpoints: [...bps].sort(), transitions: [...trans].sort(), zindex: [...z].sort(), icons,
  reduced_motion_moves: moves, errors };
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(out, `${res.controls.length} control groups, ${res.fields.length} field kinds, ${res.breakpoints.length} breakpoints${errors.length ? `, ${errors.length} errors` : ''}`);
