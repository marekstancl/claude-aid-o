// aid-ui-glyph-check.mjs — which font did Chrome really render each text element with?
// A web font that lacks a glyph (e.g. Czech ř) makes Chrome fall back to a system font
// for that glyph; CDP CSS.getPlatformFontsForNode shows the mix.
//
//   node aid-ui-glyph-check.mjs <url>...                 every url must answer HTTP 2xx/3xx first
//   node aid-ui-glyph-check.mjs --sample "<family>" "<text>"   a Google Fonts candidate (latin-ext)
//
// Output: "BLOCKER <label> <element> :: <font>=<glyphs>, ..." per mixed element, then OK|FAIL.
// Exit: 0 no fallback, 1 fallback or HTTP error, 2 usage.
// Ceiling: checks the listed text selectors at one 1440x900 viewport, not every node.
// Browser: $CHROME when set, else Playwright's own (aid-ui-tool.sh sets CHROME).
import { chromium } from '@playwright/test';

const args = process.argv.slice(2);
if (!args.length || (args[0] === '--sample' && args.length !== 3)) {
  console.error('usage: aid-ui-glyph-check.mjs <url>... | --sample <family> <text>');
  process.exit(2);
}
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const cdp = await page.context().newCDPSession(page);
await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
let bad = 0;

async function checkPage(label) {
  await page.evaluate(() => document.fonts.ready);
  const { root } = await cdp.send('DOM.getDocument', { depth: -1 });
  const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: 'h1,h2,h3,h4,h5,h6,p,a,button,li,span,label,td,th,figcaption,small,strong,em,blockquote,dt,dd' });
  for (const id of nodeIds) {
    let fonts;
    try { ({ fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId: id })); } catch { continue; }
    if (!fonts || fonts.length < 2) continue;
    if (fonts.some(f => f.isCustomFont) && fonts.some(f => !f.isCustomFont)) {
      const { outerHTML } = await cdp.send('DOM.getOuterHTML', { nodeId: id });
      bad++;
      console.log(`BLOCKER ${label} ${outerHTML.slice(0, 80).replace(/\s+/g, ' ')} :: ${fonts.map(f => `${f.familyName}${f.isCustomFont ? '' : '(system)'}=${f.glyphCount}`).join(', ')}`);
    }
  }
}

if (args[0] === '--sample') {
  const [, family, text] = args;
  const esc = s => s.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
  const css = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family)}:wght@400;700&display=block&subset=latin-ext`;
  const fam = esc(family);
  await page.setContent(`<link rel="stylesheet" href="${esc(css)}"><h1 style="font-family:'${fam}',monospace">${esc(text)}</h1><p style="font-family:'${fam}',monospace;font-weight:400">${esc(text)}</p>`, { waitUntil: 'networkidle' });
  await checkPage(`sample:${family}`);
  console.log(bad ? `FAIL ${family} lacks glyphs of the sample` : `OK ${family}`);
} else {
  for (const url of args) {
    let r = null;
    try { r = await page.goto(url, { waitUntil: 'networkidle' }); } catch (e) { /* reported below */ }
    if (!r || r.status() >= 400) { bad++; console.log(`BLOCKER ${url} HTTP ${r ? r.status() : 'none'}`); continue; }
    await checkPage(url);
  }
  console.log(bad ? `FAIL ${bad} element(s) fall back to a system font` : 'OK no fallback glyphs');
}
await browser.close();
process.exit(bad ? 1 : 0);
