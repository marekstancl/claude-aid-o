// brand-icons.js - /aid-ui step 1i: renders the brand icon set through the Playwright
// MCP (mcp__plugin_playwright_playwright__browser_run_code_unsafe), no node_modules.
//
// Use: copy this file to <project>/.aid-ui/brand-icons.js, fill the four constants
// below, then call browser_run_code_unsafe with `filename` pointing at the copy (or
// pass its text as `code`). The tool calls the function with `page` only.
//
// Writes into OUT: favicon-16/32/48.png, apple-touch-icon.png (180), icon-192.png,
// icon-512.png, icon-maskable-512.png (mark inset to a 60 % safe zone, 20 % padding
// each side, on a solid BG - the rule of cockpit/packages/aid-gui/bin/gen-icons.cjs)
// and favicon.svg. A non-square or missing viewBox is refused.
// Then: python3 aid-ui-ico.py OUT/favicon.ico OUT/favicon-{16,32,48}.png and
// python3 aid-ui-ico.py --verify OUT.
async (page) => {
  const SYMBOL_SVG = `__SYMBOL_SVG__`; // the chosen symbol, text already as paths
  const MICRO_SVG = ``;                // optional thickened micro-variant for 16/32 px
  const BG = '#0a0a0f';                // solid background of the maskable icon
  const OUT = '__ABSOLUTE_ICONS_DIR__';

  for (const svg of [SYMBOL_SVG, MICRO_SVG].filter(Boolean)) {
    const vb = /viewBox\s*=\s*["']\s*([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)/.exec(svg);
    if (!vb) throw new Error('refused: the SVG has no viewBox');
    if (Number(vb[3]) !== Number(vb[4])) throw new Error(`refused: viewBox ${vb[3]}x${vb[4]} is not square`);
  }

  // The symbol as an <img> filling a size x size tile; maskable = 60 % mark on BG.
  const render = async (svg, size, file, maskable = false) => {
    const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    const inset = maskable ? Math.round(size * 0.2) : 0;
    const html = `<!doctype html><html><body style="margin:0">
      <div id="t" style="width:${size}px;height:${size}px;${maskable ? `background:${BG};` : ''}box-sizing:border-box;padding:${inset}px">
      <img src="${src}" style="display:block;width:100%;height:100%"></div></body></html>`;
    await page.setViewportSize({ width: size, height: size });
    await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(html));
    await page.locator('#t').screenshot({ path: `${OUT}/${file}`, omitBackground: true, scale: 'css' });
    return file;
  };

  const small = MICRO_SVG || SYMBOL_SVG;
  const written = [
    await render(small, 16, 'favicon-16.png'),
    await render(small, 32, 'favicon-32.png'),
    await render(SYMBOL_SVG, 48, 'favicon-48.png'),
    await render(SYMBOL_SVG, 180, 'apple-touch-icon.png'),
    await render(SYMBOL_SVG, 192, 'icon-192.png'),
    await render(SYMBOL_SVG, 512, 'icon-512.png'),
    await render(SYMBOL_SVG, 512, 'icon-maskable-512.png', true),
  ];
  // favicon.svg through Node fs when the MCP server exposes it; otherwise the skill copies it.
  try {
    const fs = typeof require === 'function' ? require('fs') : await import('node:fs');
    fs.writeFileSync(`${OUT}/favicon.svg`, SYMBOL_SVG);
    written.push('favicon.svg');
  } catch (e) {
    written.push(`favicon.svg NOT written (${e.message}); copy the symbol SVG by hand`);
  }
  return written;
}
