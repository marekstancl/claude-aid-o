// kit-shots.mjs — `aid-companion.sh shots`: every shot of <P>/shots.json on every viewport the project
// owes, over invented data from <P>/mocks.json. Only API requests (ui.api_prefix, ui.api_origins) are
// answered from the mocks; the prototype's modules and assets load as they are. An API call with no mock
// gets 404 and is listed; any such call fails the step, so a shot never shows an empty screen by accident.
import fs from 'node:fs';
import path from 'node:path';

const STEPS = new Set(['goto', 'click', 'fill', 'select', 'hover', 'press', 'wait']);

function globRe(g) {   // a glob on a pathname: ** = any depth, * = one segment
  const re = g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*');
  return new RegExp('^' + re + '$');
}

export async function run({ DIR, PLAN, UI, VIEWPORTS, die, browser }) {
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
  try {
    for (const vp of VIEWPORTS) {
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
      const page = await ctx.newPage();
      fs.mkdirSync(path.join(DIR, 'shots', vp.name), { recursive: true });
      for (const s of shots) {
        if (s.only && !s.only.includes(vp.name)) continue;
        const where = `shot '${s.name}' (${vp.name})`;
        await page.goto(at(s.path || '/', where), { waitUntil: 'networkidle' });
        for (const [k, stp] of (s.steps || []).entries()) {
          const w = `${where} step ${k + 1}`;
          if ('goto' in stp) await page.goto(at(stp.goto, w), { waitUntil: 'networkidle' });
          else if ('click' in stp) await (await one(page, stp.click, w)).click();
          else if ('fill' in stp) await (await one(page, stp.fill, w)).fill(String(stp.value ?? ''));
          else if ('select' in stp) await (await one(page, stp.select, w)).selectOption(String(stp.value ?? ''));
          else if ('hover' in stp) await (await one(page, stp.hover, w)).hover();
          else if ('press' in stp) await page.keyboard.press(String(stp.press));
          else if ('wait' in stp) {
            if (typeof stp.wait === 'number') await page.waitForTimeout(stp.wait);
            else if (stp.wait === 'network') await page.waitForLoadState('networkidle');
            else if (stp.wait && stp.wait.for) { await loc(page, stp.wait.for, w).first().waitFor({ timeout: 15000 }); await one(page, stp.wait.for, w); }
          }
        }
        await page.waitForTimeout(300);
        const file = path.join(DIR, 'shots', vp.name, `${s.name}.png`);
        const cap = s.capture || 'viewport';
        if (cap && typeof cap === 'object' && cap.element) await (await one(page, cap.element, `${where} capture`)).screenshot({ path: file });
        else await page.screenshot({ path: file, fullPage: cap === 'full' });
        written.push(file);
      }
      await ctx.close();
    }
  } catch (e) {
    await b.close(); die(`shots: ${e.message}`);
  }
  await b.close();
  if (unknown.size) die(`shots: API calls with no mock (answered 404, the screen may be empty): ${[...unknown].join(', ')} — add them to mocks.json and run shots again`);
  console.log(JSON.stringify({ shots: written.length, dir: path.join(DIR, 'shots'), next: `write navrh.json (shot names: ${[...names].join(', ')}) and run: aid-companion.sh show --plan ${PLAN}` }));
}
