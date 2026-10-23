// aid-ui-capture.mjs - what a person sees on each address, as text (P118: the verifier reads the built version, not a
// claim about it). Usage: node aid-ui-capture.mjs <list.json> <out.json> [workers]
// list.json: [{key, url}] - every screen of the version in every mode and state; out.json: {key: visible text}.
// The text is document.body.innerText after the page settled (hidden blocks are not in it), with what text alone
// would hide said in words (H2, P118): a control that is off ("(neaktivní)"), what a field holds, and a confirm
// question that opens on a click - the verifier judged an off Uložit as offered and a closed dialog as missing. One browser, a pool of
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
      got.set(it.key, r && r.status() < 400 ? await page.evaluate(() => {
        const say = (el, t) => { const s = document.createElement('span'); s.textContent = t; el.after(s); };
        document.querySelectorAll('button:disabled, [aria-disabled="true"]').forEach(b => say(b, ' (neaktivní)'));
        document.querySelectorAll('input:not([type=hidden]), select, textarea').forEach(i => {
          const l = (i.labels && i.labels[0] && i.labels[0].innerText.trim()) || i.name;
          say(i, ` [pole ${l}: ${i.value ? '„' + i.value + '“' : 'prázdné'}]`); });
        document.querySelectorAll('dialog:not([open])').forEach(d => {   // only where its button can be pressed now
          const b = d.dataset.aidConfirm && document.querySelector(`[data-aid-action="${d.dataset.aidConfirm}"]`);
          if (b && (b.disabled || b.getAttribute('aria-disabled') === 'true' || !b.checkVisibility())) return;
          say(d, ` [po kliknutí se otevře potvrzení: ${d.textContent.trim().replace(/\s+/g, ' ')}]`); });
        return document.body.innerText; }) : `HTTP ${r ? r.status() : 'no response'}`);
    } catch (e) { got.set(it.key, `could not open: ${String(e.message).split('\n')[0].slice(0, 160)}`); }
    await ctx.close();
  }
}));
await browser.close();
fs.writeFileSync(outFile, JSON.stringify(Object.fromEntries(list.map(it => [it.key, got.get(it.key)])), null, 1));
console.log(`CAPTURE: ${list.length} addresses -> ${outFile}`);
