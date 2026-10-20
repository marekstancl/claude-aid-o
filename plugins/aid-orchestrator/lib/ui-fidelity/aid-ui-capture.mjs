// aid-ui-capture.mjs - what a person sees on each address, as text (P118: the verifier reads the built version, not a
// claim about it). Usage: node aid-ui-capture.mjs <list.json> <out.json> [workers]
// list.json: [{key, url}] - every screen of the version in every mode and state; out.json: {key: visible text}.
// The text is document.body.innerText after the page settled (hidden blocks are not in it). One browser, a pool of
// contexts (default 8); the order of out.json is the list's.
import fs from 'node:fs';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('@playwright/test');

const [listFile, outFile, w] = process.argv.slice(2);
if (!listFile || !outFile) { console.error('usage: aid-ui-capture.mjs <list.json> <out.json> [workers]'); process.exit(2); }
const list = JSON.parse(fs.readFileSync(listFile, 'utf8'));
const workers = Math.max(1, Math.min(16, Number(w) || 8));
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
const got = new Map();
let next = 0;
await Promise.all(Array.from({ length: Math.min(workers, list.length) }, async () => {
  while (next < list.length) {
    const it = list[next++];
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await ctx.newPage();
    try {
      const r = await page.goto(it.url, { waitUntil: 'networkidle', timeout: 20000 });
      await page.waitForTimeout(450);   // the state announcement and mode switches run on load
      got.set(it.key, r && r.status() < 400 ? await page.evaluate(() => document.body.innerText) : `HTTP ${r ? r.status() : 'no response'}`);
    } catch (e) { got.set(it.key, `could not open: ${String(e.message).split('\n')[0].slice(0, 160)}`); }
    await ctx.close();
  }
}));
await browser.close();
fs.writeFileSync(outFile, JSON.stringify(Object.fromEntries(list.map(it => [it.key, got.get(it.key)])), null, 1));
console.log(`CAPTURE: ${list.length} addresses -> ${outFile}`);
