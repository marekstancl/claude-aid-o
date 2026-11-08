// kit-shots.mjs — `aid-companion.sh shots`: every shot of <P>/shots.json on every viewport the project
// owes, over invented data from <P>/mocks.json. Only API requests (ui.api_prefix, ui.api_origins) are
// answered from the mocks; the prototype's modules and assets load as they are. An API call with no mock
// gets 404 and is listed; any such call fails the step, so a shot never shows an empty screen by accident.
import fs from 'node:fs';
import path from 'node:path';
import { safeTarget, sha, shotSha, kitWrite } from './kit-extra.mjs';

const STEPS = new Set(['goto', 'click', 'fill', 'select', 'hover', 'press', 'wait']);

function globRe(g) {   // a glob on a pathname: ** = any depth, * = one segment
  const re = g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*');
  return new RegExp('^' + re + '$');
}

export async function run({ DIR, PLAN, UI, VIEWPORTS, die, browser }) {
  // 3.17.0: a copy running live (ui.live.env, dev data with real people in it) is never photographed — captures
  // land in the plan's files; the live preview is looked at, not stored
  try { if (JSON.parse(fs.readFileSync(path.join(DIR, 'proto.json'), 'utf8')).live_env) die('shots: the running copy is the live preview (dev data) — no captures of it; for captures run proto without --live (on mocks) after down'); } catch (e) { if (e && e.code !== 'ENOENT' && !(e instanceof SyntaxError)) throw e; }
  const read = (f, what) => { try { return JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8')); } catch (e) { die(`shots: ${what} (${path.join(DIR, f)}) is not readable JSON: ${e.message}`); } };
  const spec = read('shots.json', 'shots.json');
  const mocks = fs.existsSync(path.join(DIR, 'mocks.json')) ? read('mocks.json', 'mocks.json') : [];
  if (!Array.isArray(mocks)) die('shots: mocks.json must be a list of {method?, path, query?, status?, body, headers?}');
  const compiled = mocks.map((m, i) => {
    if (typeof m.path !== 'string') die(`shots: mocks[${i}].path must be a glob on the pathname, e.g. "/api/v1/clients/*"`);
    return { ...m, re: globRe(m.path), method: m.method ? String(m.method).toUpperCase() : null };
  });
  if (!UI.api_prefix && !(UI.api_origins || []).length) die('shots: project.yaml has no ui.api_prefix (e.g. "/api/") — the step must know which requests are the API');
  let base = spec.base || 'proto';
  if (base === 'proto') {
    try { base = JSON.parse(fs.readFileSync(path.join(DIR, 'proto.json'), 'utf8')).url; } catch { die(`shots: base "proto" but no prototype runs — aid-companion.sh proto --plan ${PLAN}`); }
  }
  // the FINAL base, parsed: http on loopback, no credentials — the kit photographs invented data only
  let origin;
  try { const u = new URL(base); if (u.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(u.hostname) || u.username || u.password) throw 0; origin = u.origin; }
  catch { die(`shots: base "${base}" is not the prototype or a loopback address — the kit photographs invented data only, never a live application`); }
  base = origin;
  // every page address is built on that origin and must stay on it ("@host/" or "//host" would leave it)
  const at = (p, where) => {
    if (typeof p !== 'string' || !p.startsWith('/') || p.startsWith('//')) die(`shots: ${where}: a path starts with one "/" (got ${JSON.stringify(p)})`);
    const u = new URL(p, origin); if (u.origin !== origin) die(`shots: ${where}: ${p} leaves the prototype`);
    return u.href;
  };
  const shots = Array.isArray(spec.shots) ? spec.shots : die('shots: shots.json needs "shots": [...]');
  const names = new Set();
  shots.forEach((s, i) => {
    if (typeof s.name !== 'string' || !/^[A-Za-z0-9][\w.-]*$/.test(s.name)) die(`shots: shots[${i}].name must be a plain name (letters, digits, . _ -)`);
    if (names.has(s.name)) die(`shots: shot name '${s.name}' is used twice`); names.add(s.name);
    (s.steps || []).forEach((st, k) => {
      const kind = Object.keys(st).filter(x => STEPS.has(x));
      if (kind.length !== 1) die(`shots: shots[${i}].steps[${k}] must be exactly one of ${[...STEPS].join(', ')} — a new window, an iframe or a file upload is not supported; write the case to aid-plugin-issues.md`);
    });
  });
  const isApi = u => (UI.api_origins || []).some(o => u.origin === new URL(o).origin) || (u.origin === new URL(base).origin && UI.api_prefix && u.pathname.startsWith(UI.api_prefix));
  const unknown = new Set();
  const b = await browser();
  const loc = (page, sel, where) => {
    if (!sel || typeof sel !== 'object') die(`shots: ${where} needs a selector {role, name} | {testid} | {text} | {css}`);
    if (sel.role) return page.getByRole(sel.role, sel.name ? { name: sel.name, exact: true } : {});
    if (sel.testid) return page.getByTestId(sel.testid);
    if (sel.text) return page.getByText(sel.text, { exact: true });
    if (sel.css) return page.locator(sel.css);
    die(`shots: ${where}: unknown selector ${JSON.stringify(sel)}`);
  };
  const one = async (page, sel, where) => {
    const l = loc(page, sel, where), n = await l.count();
    if (n !== 1) throw new Error(`${where}: the selector ${JSON.stringify(sel)} finds ${n} elements, it must find exactly one`);
    return l;
  };
  const written = [];
  // the first page of a run waits longer: a dev server compiles on its first request (P117 (20), WAN P112)
  const first = UI.first_shot_timeout_s === undefined ? 15 : Number(UI.first_shot_timeout_s);
  if (!Number.isInteger(first) || first < 1 || first > 120) die(`shots: ui.first_shot_timeout_s must be whole seconds from 1 to 120 (got ${UI.first_shot_timeout_s})`);
  let isFirst = true;
  // --only <a,b> (C7): just the named shots; the others and their files stay as they are
  const only = (process.env.AID_COMPANION_ONLY || '').split(',').filter(Boolean);
  for (const n of only) if (!names.has(n)) die(`shots: --only ${n}: no such shot in shots.json (${[...names].join(', ')})`);
  const newContext = async vp => {
    const ctx = await b.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const st = spec.storage || {};
    if (st.localStorage) await ctx.addInitScript(o => { for (const [k, v] of Object.entries(o)) localStorage.setItem(k, typeof v === 'string' ? v : JSON.stringify(v)); }, st.localStorage);
    if (Array.isArray(st.cookies) && st.cookies.length) await ctx.addCookies(st.cookies.map(c => ({ url: base, ...c })));
    await ctx.route('**/*', route => {
      const req = route.request(), u = new URL(req.url());
      if (req.isNavigationRequest() && u.origin !== origin) { unknown.add(`navigation to ${u.origin} (another origin)`); return route.abort(); }
      if (!isApi(u)) {
        // a data request to another origin would reach a live service: refused and listed like an unmocked call
        if (u.origin !== new URL(base).origin && ['xhr', 'fetch'].includes(req.resourceType())) { unknown.add(`${req.method()} ${u.origin}${u.pathname} (another origin)`); return route.abort(); }
        return route.continue();
      }
      const q = Object.fromEntries(u.searchParams);
      const m = compiled.find(x => (!x.method || x.method === req.method()) && x.re.test(u.pathname)
        && (!x.query || Object.entries(x.query).every(([k, v]) => q[k] === String(v))));
      if (!m) { unknown.add(`${req.method()} ${u.pathname}${u.search}`); return route.fulfill({ status: 404, contentType: 'application/json', body: '{"detail":"no mock"}' }); }
      return route.fulfill({ status: m.status || 200, headers: m.headers || {}, contentType: 'application/json', body: typeof m.body === 'string' ? m.body : JSON.stringify(m.body ?? null) });
    });
    return ctx;
  };
  // the page's own layout changed for the capture and put back in `finally`, also when the capture fails (C4):
  // a full page sets fixed/sticky elements static (a pinned bar is otherwise printed in the middle of the long
  // shot, WAN P117, P119); a scrolling container is opened to its full height together with every ancestor that
  // clips it (overflow hidden or a fixed height: WAN AdminLayout h-[100dvh] overflow-hidden)
  const unpin = page => page.evaluate(() => {
    const saved = [];
    // an open dialog and its overlay stay where the user sees them
    const dlg = [...document.querySelectorAll('[role=dialog],[role=alertdialog],dialog[open]')];
    for (const el of document.querySelectorAll('*')) {
      const p = getComputedStyle(el).position;
      if ((p === 'fixed' || p === 'sticky') && !dlg.some(d => el.contains(d) || d.contains(el))) { saved.push([el, el.getAttribute('style')]); el.style.setProperty('position', 'static', 'important'); }
    }
    window.__aidSaved = saved;
  });
  const openUp = el => el.evaluate(n => {
    const saved = [];
    const open = (x, own) => { saved.push([x, x.getAttribute('style')]);
      x.style.setProperty('max-height', 'none', 'important'); x.style.setProperty('overflow', 'visible', 'important');
      x.style.setProperty('height', own ? x.scrollHeight + 'px' : 'auto', 'important'); };
    const need = n.scrollHeight;
    open(n, true);
    for (let a = n.parentElement; a && a !== document.documentElement; a = a.parentElement) {
      const cs = getComputedStyle(a);
      if (cs.overflowY !== 'visible' || cs.maxHeight !== 'none' || a.clientHeight < need) open(a, false);
    }
    window.__aidSaved = saved;
  });
  const restore = page => page.evaluate(() => {
    for (const [el, st] of (window.__aidSaved || []).reverse()) { if (st === null) el.removeAttribute('style'); else el.setAttribute('style', st); }
    window.__aidSaved = [];
  }).catch(() => {});
  // K1 (PM 31. 10. 2026, WAN P119: a proposal went to the PM with a dialog cut off on the right): measured in the page
  // as it will be captured, BEFORE the capture changes any style; visible elements only, 1 px tolerance, horizontal
  const measure = page => page.evaluate(() => {
    const vis = el => { const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && cs.display !== 'none' && cs.visibility !== 'hidden'; };
    const name = el => (el.getAttribute('role') ? `[role=${el.getAttribute('role')}]` : el.tagName.toLowerCase())
      + (el.getAttribute('aria-label') ? ` "${el.getAttribute('aria-label').slice(0, 40)}"` : '')
      + (el.id ? `#${el.id}` : '') + (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.') : '');
    const out = [], se = document.scrollingElement;
    if (se.scrollWidth > innerWidth + 1) out.push({ pravidlo: 'page_wider_than_window', prvek: 'page', presah_px: se.scrollWidth - innerWidth });
    const dialogs = [...document.querySelectorAll('[role=dialog],[role=alertdialog],dialog[open]')].filter(vis);
    for (const d of dialogs) {
      const dr = d.getBoundingClientRect();
      const off = Math.max(0, dr.right - innerWidth, -dr.left);
      if (off > 1) out.push({ pravidlo: 'dialog_off_screen', prvek: name(d), presah_px: Math.round(off) });
      for (const el of d.querySelectorAll('*')) {
        if (!vis(el)) continue;
        // inside a scroller of its own (overflow-x auto|scroll) the content scrolls on purpose
        let own = false;
        for (let a = el.parentElement; a; a = a.parentElement) { if (/(auto|scroll)/.test(getComputedStyle(a).overflowX)) { own = true; break; } if (a === d) break; }
        const r = el.getBoundingClientRect(), over = Math.max(r.right - dr.right, dr.left - r.left);
        if (!own && over > 1) out.push({ pravidlo: 'beyond_dialog_edge', prvek: name(el), presah_px: Math.round(over) });
        const cs = getComputedStyle(el);
        if (/(hidden|clip)/.test(cs.overflowX) && el.scrollWidth > el.clientWidth + 1
            && !(cs.textOverflow === 'ellipsis' && cs.whiteSpace === 'nowrap'))
          out.push({ pravidlo: 'content_clipped', prvek: name(el), presah_px: el.scrollWidth - el.clientWidth });
      }
    }
    // one entry per element and rule (a clipped parent also lists its children; the first 20 say enough)
    const seen = new Set();
    return { dialogs: dialogs.length, clipped: out.filter(c => { const k = c.pravidlo + c.prvek; if (seen.has(k)) return false; seen.add(k); return true; }).slice(0, 20) };
  });
  // a shot's files go through the kit's path check; written to a temporary name and renamed into place
  const shotPath = (vp, s, ext) => safeTarget(DIR, `shots/${vp.name}/${s.name}${ext}`, die, { kit: true });
  const dropShot = (vp, s) => { for (const ext of ['.png', '.check.json']) { try { fs.rmSync(shotPath(vp, s, ext)); } catch {} } };
  // the shots of a run with an unmocked API call may show an empty screen: their checks say so and show refuses them
  // (K1) — also when the run then stops on another error
  const markMocksMissing = () => {
    for (const w of written) {
      const rel = `shots/${w.vp.name}/${w.s.name}.check.json`;
      try { kitWrite(DIR, rel, JSON.stringify({ ...JSON.parse(fs.readFileSync(path.join(DIR, rel), 'utf8')), mocks_missing: true }, null, 1), die); } catch {}
    }
  };
  const takeShot = async (page, s, vp) => {
    const where = `shot '${s.name}' (${vp.name})`;
    // the first shot waits ui.first_shot_timeout_s for what it waits on (a page load never less than the
    // browser's 30 s: the setting lengthens the first wait, it never shortens a load)
    const wait = isFirst ? first * 1000 : 15000, nav = isFirst ? Math.max(first * 1000, 30000) : 30000;
    // only a failed navigation may be taken again (K3): its error is marked here
    const go = (u, w) => page.goto(at(u, w), { waitUntil: 'networkidle', timeout: nav }).catch(e => { e.aidNavigation = true; throw e; });
    await go(s.path || '/', where);
    for (const [k, stp] of (s.steps || []).entries()) {
      const w = `${where} step ${k + 1}`;
      if ('goto' in stp) await go(stp.goto, w);
      else if ('click' in stp) await (await one(page, stp.click, w)).click();
      else if ('fill' in stp) await (await one(page, stp.fill, w)).fill(String(stp.value ?? ''));
      else if ('select' in stp) await (await one(page, stp.select, w)).selectOption(String(stp.value ?? ''));
      else if ('hover' in stp) await (await one(page, stp.hover, w)).hover();
      else if ('press' in stp) await page.keyboard.press(String(stp.press));
      else if ('wait' in stp) {
        if (typeof stp.wait === 'number') await page.waitForTimeout(stp.wait);
        else if (stp.wait === 'network') await page.waitForLoadState('networkidle');
        else if (stp.wait && stp.wait.for) { await loc(page, stp.wait.for, w).first().waitFor({ timeout: wait }); await one(page, stp.wait.for, w); }
      }
    }
    await page.waitForTimeout(300);
    const check = await measure(page);
    const file = shotPath(vp, s, `.tmp-${process.pid}.png`);   // the capture names its format by the extension
    const cap = s.capture || 'viewport';
    try {
      if (cap && typeof cap === 'object' && cap.element) await (await one(page, cap.element, `${where} capture`)).screenshot({ path: file });
      else if (cap && typeof cap === 'object' && cap.scroll) {
        const el = await one(page, cap.scroll, `${where} capture`);
        await openUp(el); await el.screenshot({ path: file });
      } else {
        if (cap === 'full') await unpin(page);
        await page.screenshot({ path: file, fullPage: cap === 'full' });
      }
    } finally { await restore(page); }
    fs.renameSync(file, shotPath(vp, s, '.png'));
    const rec = { png_sha256: sha(shotPath(vp, s, '.png')), viewport: vp.name, shot_sha256: shotSha(s), mocks_missing: false, ...check };
    kitWrite(DIR, `shots/${vp.name}/${s.name}.check.json`, JSON.stringify(rec, null, 1), die);
    return { vp, s, file: shotPath(vp, s, '.png') };
  };
  try {
    for (const vp of VIEWPORTS) {
      const ctx = await newContext(vp);
      const page = await ctx.newPage();
      safeTarget(DIR, `shots/${vp.name}`, die, { kit: true });
      fs.mkdirSync(path.join(DIR, 'shots', vp.name), { recursive: true });
      safeTarget(DIR, `shots/${vp.name}`, die, { kit: true });
      for (const s of shots) {
        if (s.only && !s.only.includes(vp.name)) continue;
        if (only.length && !only.includes(s.name)) continue;
        const before = new Set(unknown);
        let file;
        dropShot(vp, s);                         // an old shot never outlives a failed new one (K1)
        try { file = await takeShot(page, s, vp); }
        catch (e) {
          // one retry of this shot on this viewport, for a network error of the browser only (C7, WAN P113: a
          // changing network failed the whole set) — in a new context with the storage of shots.json, so nothing
          // the first try changed (a cookie, local storage) carries over; the unmocked calls it listed are dropped
          if (!e.aidNavigation || !/net::ERR_/.test(e.message)) throw e;
          console.error(`aid-companion: shot '${s.name}' (${vp.name}) taken again after ${e.message.split('\n')[0]}`);
          unknown.clear(); for (const x of before) unknown.add(x);
          const ctx2 = await newContext(vp);
          try { file = await takeShot(await ctx2.newPage(), s, vp); } finally { await ctx2.close(); }
        }
        isFirst = false;
        written.push(file);
      }
      await ctx.close();
    }
  } catch (e) {
    await b.close(); if (unknown.size) markMocksMissing(); die(`shots: ${e.message}`);
  }
  await b.close();
  if (unknown.size) {
    markMocksMissing();
    die(`shots: API calls with no mock (answered 404, the screen may be empty): ${[...unknown].join(', ')} — add them to mocks.json and run shots again`);
  }
  console.log(JSON.stringify({ shots: written.length, dir: path.join(DIR, 'shots'), next: `write navrh.json (shot names: ${[...names].join(', ')}) and run: aid-companion.sh show --plan ${PLAN}` }));
}
