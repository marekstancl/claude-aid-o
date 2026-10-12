// aid-ui-png.mjs — render an SVG to a PNG of a given width (transparent background) in Chrome.
//   node aid-ui-png.mjs <src.svg> <out.png> <width px>
// Prints "<out> <width>x<height>". Exit: 0 written, 1 failure, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';

const [src, out, width] = process.argv.slice(2);
const w = Number(width);
if (!src || !out || !(w > 0) || !src.toLowerCase().endsWith('.svg')) {
  console.error('usage: aid-ui-png.mjs <src.svg> <out.png> <width>');
  process.exit(2);
}
const svg = fs.readFileSync(src, 'utf8');
const vb = /viewBox=["']([^"']+)["']/.exec(svg);
const [, , vw, vh] = vb ? vb[1].trim().split(/[\s,]+/).map(Number) : [];
if (!(vw > 0 && vh > 0)) { console.error(`ERROR: ${src} has no usable viewBox`); process.exit(1); }
const h = Math.round(w * vh / vw);
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const page = await browser.newPage({ viewport: { width: w, height: h } });
await page.setContent(`<html><body style="margin:0;background:transparent">
  <img src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" width="${w}" height="${h}" style="display:block"></body></html>`);
await page.waitForFunction(() => document.images[0]?.complete);
await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
await browser.close();
console.log(out, `${w}x${h}`);
