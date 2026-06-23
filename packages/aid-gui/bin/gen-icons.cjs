#!/usr/bin/env node
/**
 * One-shot PWA icon generator (Step 34).
 * Rasterizes the brand mark from public/favicon.svg into the three required
 * PWA icons plus a PNG favicon, using the Playwright Chromium that ships with
 * @playwright/test (no sharp / imagemagick on the host).
 *
 * Standard icons: brand mark fills the tile (matches favicon framing).
 * Maskable icon: brand mark inset to a ~60% safe zone (~20% padding each side)
 * on a full-bleed background so platform masks never clip the glyph.
 */
const path = require('path');
const { chromium } = require('@playwright/test');

const PUBLIC = path.resolve(__dirname, '..', 'public');

// Brand mark redrawn at viewBox scale; mirrors favicon.svg (dark tile, violet
// "A", green status dot). Kept inline so the generator is self-contained.
function markSvg({ size, maskable }) {
  // For maskable: shrink the mark to ~60% and centre it; fill the rest with the
  // tile colour so the safe zone is solid background.
  const inset = maskable ? Math.round(size * 0.2) : 0;
  const inner = size - inset * 2;
  const radius = maskable ? 0 : Math.round(size * 0.1875); // ~6/32 of favicon
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" rx="${radius}" fill="#0a0a0f"/>
  <g transform="translate(${inset},${inset})">
    <svg width="${inner}" height="${inner}" viewBox="0 0 32 32">
      <rect width="32" height="32" rx="6" fill="#0a0a0f"/>
      <text x="16" y="22" font-family="system-ui,sans-serif" font-size="16" font-weight="bold" fill="#a78bfa" text-anchor="middle">A</text>
      <circle cx="24" cy="8" r="3" fill="#22c55e"/>
    </svg>
  </g>
</svg>`;
}

async function render(page, svg, size, outFile) {
  const html = `<!doctype html><html><head><style>*{margin:0;padding:0}</style></head><body>${svg}</body></html>`;
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(html, { waitUntil: 'networkidle' });
  const el = await page.$('svg');
  await el.screenshot({ path: outFile, omitBackground: true });
  console.log('wrote', outFile);
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || undefined,
  });
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await render(page, markSvg({ size: 192, maskable: false }), 192, path.join(PUBLIC, 'icon-192.png'));
  await render(page, markSvg({ size: 512, maskable: false }), 512, path.join(PUBLIC, 'icon-512.png'));
  await render(page, markSvg({ size: 512, maskable: true }), 512, path.join(PUBLIC, 'icon-512-maskable.png'));
  await render(page, markSvg({ size: 192, maskable: false }), 192, path.join(PUBLIC, 'favicon.png'));
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
