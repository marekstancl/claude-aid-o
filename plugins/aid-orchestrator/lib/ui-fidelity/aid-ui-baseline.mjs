// aid-ui-baseline.mjs - plays the approved baseline tasks of an existing app (P116; run by aid-ui-baseline.py capture).
//
//   node aid-ui-baseline.mjs --tasks <tasks.json> --base <url> --root <.aid-ui/baseline> --out <dir> [--login <storage.json>]
//
// Every task in a fresh browser context with its login (task.login under --root, else --login) as Playwright
// storageState: each step opens step.url (relative to --base), fills step.input (by label, else by name) and
// clicks step.action (a button or link of that accessible name); the task passed when result.expect is visible
// (and the page is at result.url when given). <out>/results.json [{id, passed, url, why}] and <out>/shots/<task>-<n>.png
// (one per step and one of the result). A step that cannot be done is the task's failure, named; the run never
// stops at one task. Exit: 0 results written, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2), opt = {};
for (let i = 0; i < argv.length; i += 2) opt[argv[i].replace(/^--/, '')] = argv[i + 1];
for (const k of ['tasks', 'base', 'root', 'out']) if (!opt[k]) { console.error(`usage: aid-ui-baseline.mjs --tasks <f> --base <url> --root <dir> --out <dir> [--login <f>] (missing --${k})`); process.exit(2); }
const tasks = JSON.parse(fs.readFileSync(opt.tasks, 'utf8'));
const base = opt.base.endsWith('/') ? opt.base : opt.base + '/';
const shots = path.join(opt.out, 'shots');
fs.mkdirSync(shots, { recursive: true });
const safe = s => String(s).replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^\.+/, '_');
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const results = [];
for (const t of tasks) {
  const login = t.login ? path.join(opt.root, t.login) : (opt.login || null);
  const ctx = await browser.newContext(login ? { storageState: login } : {});
  const page = await ctx.newPage();
  let n = 0, why = '';
  const shot = async () => page.screenshot({ path: path.join(shots, `${safe(t.id)}-${++n}.png`), fullPage: true }).catch(() => {});
  try {
    for (const [i, st] of (t.steps || []).entries()) {
      const at = `krok ${i + 1}`;
      if (st.url) {   // only the app's own addresses: a task never leads the browser (and its login) elsewhere
        const u = new URL(String(st.url).replace(/^\/+/, ''), base);
        if (u.origin !== new URL(base).origin) throw new Error(`${at}: ${st.url} není adresa aplikace (${new URL(base).origin})`);
        const r = await page.goto(u.href, { waitUntil: 'networkidle' });
        if (!r || r.status() >= 400) throw new Error(`${at}: ${st.url} odpověděl ${r ? r.status() : 'nic'}`);
      }
      for (const [k, v] of Object.entries(st.input || {})) {
        const byLabel = page.getByLabel(k, { exact: true }), byName = page.locator(`[name="${k.replace(/"/g, '')}"]`);
        const el = (await byLabel.count()) ? byLabel.first() : byName.first();
        await el.fill(String(v), { timeout: 5000 }).catch(() => { throw new Error(`${at}: pole ${k} nejde vyplnit`); });
      }
      if (st.action) {
        const el = page.getByRole('button', { name: st.action }).or(page.getByRole('link', { name: st.action })).first();
        await el.click({ timeout: 5000 }).catch(() => { throw new Error(`${at}: akce „${st.action}“ nejde provést`); });
        await page.waitForLoadState('networkidle').catch(() => {});
      }
      await shot();
    }
    const exp = t.result?.expect;
    const seen = exp && await page.getByText(exp).first().waitFor({ state: 'visible', timeout: 5000 }).then(() => true, () => false);
    if (!seen) why = `výsledek „${exp}“ není vidět${login ? '' : ' (bez přihlášení)'}`;
    else if (new URL(page.url()).origin !== new URL(base).origin) why = `úloha skončila mimo aplikaci (${new URL(page.url()).origin})`;
    else if (t.result?.url && new URL(page.url()).pathname !== new URL(String(t.result.url).replace(/^\/+/, ''), base).pathname)
      why = `úloha skončila na ${new URL(page.url()).pathname}, ne na ${t.result.url}`;
    await shot();
  } catch (e) {
    why = String(e.message || e).split('\n')[0].slice(0, 200);
  }
  results.push({ id: t.id, passed: !why, url: page.url(), why });
  await ctx.close();
}
await browser.close();
fs.writeFileSync(path.join(opt.out, 'results.json'), JSON.stringify(results, null, 1));
console.log(`baseline: ${results.filter(r => r.passed).length}/${results.length} úloh došlo k výsledku`);
