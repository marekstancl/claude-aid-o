// aid-ui-glyph-check.mjs — which font did Chrome really render each text element with?
// A web font that lacks a glyph (e.g. Czech ř) makes Chrome fall back to a system font
// for that glyph; CDP CSS.getPlatformFontsForNode shows the mix.
//
//   node aid-ui-glyph-check.mjs <url>...                 every url must answer HTTP 2xx/3xx first
//   node aid-ui-glyph-check.mjs --sample "<family>" "<text>"   a Google Fonts candidate (latin-ext)
//
// Output: "BLOCKER <label> <element> :: <font>=<glyphs>, ..." per mixed element or per element
// rendered by system fonts only (the web font / sample family never loaded), then OK|FAIL.
// A page where no text element could be observed is a FAIL, never OK.
// <family> must match ^[A-Za-z0-9 _-]{1,64}$ (else exit 2); family and text reach the page
// only through the DOM/CSSOM (textContent, style.fontFamily), never by string interpolation.
// Exit: 0 no fallback, 1 fallback, system-only text, nothing observed or HTTP error, 2 usage.
// Ceiling: checks the listed text selectors at one 1440x900 viewport, not every node.
// Browser: $CHROME when set, else Playwright's own (aid-ui-tool.sh sets CHROME).
import { chromium } from '@playwright/test';

const args = process.argv.slice(2);
if (!args.length || (args[0] === '--sample' && args.length !== 3)) {
  console.error('usage: aid-ui-glyph-check.mjs <url>... | --sample <family> <text>');
  process.exit(2);
}
if (args[0] === '--sample' && !/^[A-Za-z0-9 _-]{1,64}$/.test(args[1])) {
  console.error('aid-ui-glyph-check.mjs: --sample family must match ^[A-Za-z0-9 _-]{1,64}$');
  process.exit(2);
}
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const cdp = await page.context().newCDPSession(page);
await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
let bad = 0;

// checkPage(label) — every text element must be rendered by a web font only; returns how
// many elements it could observe (0 = the check saw nothing, counted as a failure).
async function checkPage(label) {
  let seen = 0;
  await page.evaluate(() => document.fonts.ready);
  const { root } = await cdp.send('DOM.getDocument', { depth: -1 });
  const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: 'h1,h2,h3,h4,h5,h6,p,a,button,li,span,label,td,th,figcaption,small,strong,em,blockquote,dt,dd' });
  for (const id of nodeIds) {
    let fonts;
    try { ({ fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId: id })); } catch { continue; }
    if (!fonts || !fonts.length) continue;
    seen++;
    if (fonts.some(f => !f.isCustomFont)) {
      const { outerHTML } = await cdp.send('DOM.getOuterHTML', { nodeId: id });
      bad++;
      const why = fonts.some(f => f.isCustomFont) ? '' : ' (no web font rendered)';
      console.log(`BLOCKER${why} ${label} ${outerHTML.slice(0, 80).replace(/\s+/g, ' ')} :: ${fonts.map(f => `${f.familyName}${f.isCustomFont ? '' : '(system)'}=${f.glyphCount}`).join(', ')}`);
    }
  }
  if (!seen) { bad++; console.log(`BLOCKER ${label} no text element could be observed`); }
}

if (args[0] === '--sample') {
  const [, family, text] = args;
  const css = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family)}:wght@400;700&display=block&subset=latin-ext`;
  await page.setContent('<link rel="stylesheet"><h1></h1><p style="font-weight:400"></p>');
  await page.evaluate(async ({ css, family, text }) => {
    const link = document.querySelector('link');
    await new Promise(ok => { link.onload = link.onerror = ok; link.href = css; });
    for (const el of document.querySelectorAll('h1,p')) {
      el.textContent = text;
      el.style.fontFamily = `${JSON.stringify(family)}, monospace`;
    }
    for (const w of [400, 700]) await document.fonts.load(`${w} 16px ${JSON.stringify(family)}`, text).catch(() => {});
  }, { css, family, text });
  await checkPage(`sample:${family}`);
  console.log(bad ? `FAIL ${family} lacks glyphs of the sample or did not load` : `OK ${family}`);
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
