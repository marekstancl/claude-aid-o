// aid-ui-motion-measure.mjs — the limits of a logo animation, measured (P113 step 7; pohyb-znacky.md limits; the
// `metrics` gates of critic/web-local.*.pohyb.gates.yaml read the result).
//   node aid-ui-motion.mjs measure <url or .html file> --variant <id> [--out-dir <dir>]   (aid-ui-tool.sh motion measure)
// Writes <out-dir>/metrics-pohyb-<id>.json (default out-dir .aid-ui/critic):
//   web_logo_draw_ms            when the last animation inside the mark (svg.mark, .mark, [data-aid-logo]) ends
//   web_logo_name_visible_ms    the first moment the name (.name, [data-aid-logo-name] or the mark's <text>) is visible
//                               with every animation held at that moment; 0 = readable from the first frame
//   web_motion_running_after_ms when the last finite animation of the page ends (an infinite one: 999999)
//   final_frame_diff_px         pixels that differ between the final frame and the same frame with every mask
//                               switched off - a seam left by the masks shows here (fix 63)
// Time is read from the animations themselves (paused and set to each moment), never from the machine's speed.
// A page with no animation writes {"not_applicable": true}: only the motion place's `without` record waives it.
// Exit 0 written, 1 the page did not load, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

export default async function measure(args) {
  const opt = (k) => { const i = args.indexOf(k); if (i < 0) return undefined; const v = args[i + 1]; args.splice(i, 2); return v; };
  const variant = opt('--variant'), outDir = opt('--out-dir') || '.aid-ui/critic';
  const target = args[0];
  if (!target || !variant || !/^[A-Za-z0-9_-]+$/.test(variant)) { console.error('usage: aid-ui-motion.mjs measure <url or .html file> --variant <id> [--out-dir <dir>]'); process.exit(2); }
  const url = /^https?:\/\//.test(target) ? target : 'file://' + path.resolve(target);
  const b = await chromium.launch({ executablePath: process.env.CHROME || undefined });
  const page = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  try { await page.goto(url, { waitUntil: 'load', timeout: 30000 }); } catch (e) { console.error(`ERROR: ${target}: ${e.message}`); await b.close(); process.exit(1); }
  const info = await page.evaluate(() => {
    const anims = document.getAnimations().filter(a => a.effect);
    const inMark = a => { const t = a.effect.target; return !!(t && t.closest && t.closest('svg.mark, .mark, [data-aid-logo]')); };
    const end = a => { const ct = a.effect.getComputedTiming(); return ct.endTime === Infinity ? 999999 : ct.endTime; };
    return { n: anims.length, mark: Math.max(0, ...anims.filter(inMark).map(end)), all: Math.max(0, ...anims.map(end)),
             name: !!document.querySelector('svg.mark .name, .mark .name, [data-aid-logo-name], svg.mark text, [data-aid-logo] text') };
  });
  let rec;
  if (!info.n) rec = { not_applicable: true };
  else {
    const hold = (t) => page.evaluate(ms => document.getAnimations().forEach(a => { a.pause(); a.currentTime = ms; }), t);
    const nameVisible = () => page.evaluate(() => {
      const e = document.querySelector('svg.mark .name, .mark .name, [data-aid-logo-name], svg.mark text, [data-aid-logo] text');
      if (!e) return false;
      for (let n = e; n && n.nodeType === 1; n = n.parentElement) {
        const s = getComputedStyle(n);
        if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) < 0.95 || (n !== e && n.tagName !== 'svg' && s.mask !== 'none' && s.mask !== '')) return false;
      }
      const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0;
    });
    let nameMs = null;
    if (info.name) {
      for (let t = 0; t <= Math.min(info.all, 10000); t += 50) { await hold(t); if (await nameVisible()) { nameMs = t; break; } }
    }
    await hold(Math.min(info.all, 999998));
    await page.waitForTimeout(50);
    const a = await page.screenshot();
    await page.addStyleTag({ content: '.mark *, [data-aid-logo] *, svg.mark *{mask:none!important;-webkit-mask:none!important}' });
    await page.waitForTimeout(50);
    const bshot = await page.screenshot();
    const diff = await page.evaluate(async ([x, y]) => {
      const img = src => new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = 'data:image/png;base64,' + src; });
      const [p, q] = await Promise.all([img(x), img(y)]);
      const c = document.createElement('canvas'); c.width = p.width; c.height = p.height; const g = c.getContext('2d');
      g.drawImage(p, 0, 0); const d1 = g.getImageData(0, 0, c.width, c.height).data;
      g.clearRect(0, 0, c.width, c.height); g.drawImage(q, 0, 0); const d2 = g.getImageData(0, 0, c.width, c.height).data;
      let n = 0; for (let i = 0; i < d1.length; i += 4) if (Math.abs(d1[i] - d2[i]) + Math.abs(d1[i + 1] - d2[i + 1]) + Math.abs(d1[i + 2] - d2[i + 2]) > 48) n++;
      return n;
    }, [a.toString('base64'), bshot.toString('base64')]);
    rec = { web_logo_draw_ms: Math.round(info.mark || info.all), web_logo_name_visible_ms: nameMs, web_motion_running_after_ms: Math.round(info.all),
            final_frame_diff_px: diff, measured_at: new Date().toISOString(), page: target };
  }
  await b.close();
  fs.mkdirSync(outDir, { recursive: true });
  const f = path.join(outDir, `metrics-pohyb-${variant}.json`);
  fs.writeFileSync(f, JSON.stringify(rec, null, 1) + '\n');
  console.log(JSON.stringify({ file: f, ...rec }));
}
