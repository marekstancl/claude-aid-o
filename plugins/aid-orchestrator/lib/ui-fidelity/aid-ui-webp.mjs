// aid-ui-webp.mjs — convert a PNG/JPEG/WebP to WebP through Chrome's canvas encoder.
//   node aid-ui-webp.mjs <src> <out.webp> <width px> [quality 0-1, default 0.8]
// Prints "<out> <bytes>". The caller checks the size limit (aid-ui-tool.sh webp --max-kb).
// Exit: 0 written, 1 failure, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';

const [src, out, width, q = '0.8'] = process.argv.slice(2);
const w = Number(width), quality = Number(q);
if (!src || !out || !(w > 0) || !(quality > 0 && quality <= 1)) {
  console.error('usage: aid-ui-webp.mjs <src> <out.webp> <width> [quality 0-1]');
  process.exit(2);
}
const mime = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' }[src.slice(src.lastIndexOf('.')).toLowerCase()];
if (!mime) { console.error(`ERROR: unsupported source type: ${src}`); process.exit(2); }
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const page = await browser.newPage();
const data = `data:${mime};base64,` + fs.readFileSync(src).toString('base64');
const url = await page.evaluate(async ([d, w, q]) => {
  const i = new Image(); i.src = d; await i.decode();
  const c = document.createElement('canvas'); c.width = w; c.height = Math.round(i.height * w / i.width);
  c.getContext('2d').drawImage(i, 0, 0, c.width, c.height);
  return c.toDataURL('image/webp', q);
}, [data, w, quality]);
await browser.close();
if (!url.startsWith('data:image/webp')) { console.error('ERROR: this Chrome cannot encode WebP'); process.exit(1); }
fs.writeFileSync(out, Buffer.from(url.split(',')[1], 'base64'));
console.log(out, fs.statSync(out).size);
