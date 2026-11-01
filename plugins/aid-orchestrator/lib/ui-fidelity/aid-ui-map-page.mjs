// aid-ui-map-page.mjs — drive a built process-map page like the PM does (P118, t2 test driver).
//   node aid-ui-map-page.mjs <page.html> <out.json> <step id>
// Opens the page from the file with every other request aborted (and recorded), gives it a stub of share's
// runtime with exactly the shapes of share/static/share-runtime.js (claude.use("db"|"user"), user.me(),
// db.collection(path).add/get), clicks the step, marks it, and writes {requests, detail, records} as JSON.
// Exit: 0 written, 1 the page did not behave, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const [pagePath, out, step] = process.argv.slice(2);
if (!pagePath || !out || !step) { console.error('usage: aid-ui-map-page.mjs <page.html> <out.json> <step id>'); process.exit(2); }
const url = 'file://' + path.resolve(pagePath);
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
try {
  const page = await browser.newPage();
  const requests = [];
  await page.route('**/*', r => {
    const u = r.request().url();
    if (u === url || u.startsWith('data:')) return r.continue();
    requests.push(u); return r.abort();
  });
  await page.addInitScript(() => {
    const records = [];
    window.__records = records;
    const col = p => ({
      add: rec => { records.push({ path: p + '/' + records.length, data: rec }); return Promise.resolve({ id: String(records.length) }); },
      get: () => Promise.resolve({ docs: records.filter(r => r.path.startsWith(p + '/')).map(r => ({ id: r.path, data: () => r.data })) }),
    });
    window.claude = { use: name => Promise.resolve(
      name === 'db' ? { collection: col } : name === 'user' ? { me: () => Promise.resolve({ id: 'u_test', name: 'PM' }) } : null) };
  });
  await page.goto(url);
  await page.waitForFunction(() => window.__processMapReady === true);
  await page.click(`[data-step="${step}"]`);
  const detail = await page.textContent('#detail h2');
  await page.click('text=Označit tento krok');
  await page.fill('#ftext', 'Zkouška označení');
  await page.click('#fsave');
  await page.waitForFunction(() => window.__records.length > 0 && !document.getElementById('form').classList.contains('on'));
  await page.waitForFunction(() => document.querySelectorAll('#flags .f').length > 0);
  const records = await page.evaluate(() => window.__records);
  fs.writeFileSync(out, JSON.stringify({ requests, detail, records }, null, 1));
  console.log(out);
} catch (e) {
  console.error(`map_page_failed: ${e.message}`);
  process.exit(1);
} finally {
  await browser.close();
}
