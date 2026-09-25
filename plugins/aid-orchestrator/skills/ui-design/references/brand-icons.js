// brand-icons.js - /aid-ui step 1i: renders the brand icon set through the Playwright
// MCP (mcp__plugin_playwright_playwright__browser_run_code_unsafe), no node_modules.
//
// Use: copy this file to <project>/.aid-ui/brand-icons.js, fill ONLY the three path
// constants below, then call browser_run_code_unsafe with `filename` pointing at the
// copy. The tool calls the function with `page` only.
// Never paste SVG markup into this file: the snippet reads the SVG files itself with
// Node fs and hands them to the page as data. Each path must be a plain absolute path
// matching ^/[A-Za-z0-9._/-]+$ (no quotes, backticks, `${`, spaces or newlines) -
// check that before filling it in; the snippet re-checks and refuses anything else.
//
// Writes into OUT: favicon-16/32/48.png, apple-touch-icon.png (180), icon-192.png,
// icon-512.png, icon-maskable-512.png (mark inset to a 60 % safe zone, 20 % padding
// each side, on a solid BG - the rule of cockpit/packages/aid-gui/bin/gen-icons.cjs)
// and favicon.svg (a byte copy of SYMBOL_FILE). A non-square or missing viewBox is refused.
// Then: python3 aid-ui-ico.py OUT/favicon.ico OUT/favicon-{16,32,48}.png and
// python3 aid-ui-ico.py --verify OUT (it also refuses an unsafe favicon.svg).
async (page) => {
  const SYMBOL_FILE = '__ABSOLUTE_SYMBOL_SVG__'; // the chosen symbol, text already as paths
  const MICRO_FILE = '';                         // optional thickened micro-variant for 16/32 px
  const OUT = '__ABSOLUTE_ICONS_DIR__';
  const BG = '#0a0a0f';                          // solid background of the maskable icon

  const PLAIN = /^\/[A-Za-z0-9._/-]+$/;
  for (const p of [SYMBOL_FILE, MICRO_FILE, OUT].filter(Boolean)) {
    if (!PLAIN.test(p) || p.includes('..')) throw new Error('refused: not a plain absolute path: ' + JSON.stringify(p));
  }
  const fs = typeof require === 'function' ? require('fs') : await import('node:fs');
  const SYMBOL_SVG = fs.readFileSync(SYMBOL_FILE, 'utf8');
  const MICRO_SVG = MICRO_FILE ? fs.readFileSync(MICRO_FILE, 'utf8') : '';

  for (const svg of [SYMBOL_SVG, MICRO_SVG].filter(Boolean)) {
    const vb = /viewBox\s*=\s*["']\s*([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)/.exec(svg);
    if (!vb) throw new Error('refused: the SVG has no viewBox');
    if (Number(vb[3]) !== Number(vb[4])) throw new Error(`refused: viewBox ${vb[3]}x${vb[4]} is not square`);
  }

  // The symbol as an <img> filling a size x size tile; maskable = 60 % mark on BG.
  // The SVG only ever travels as an encoded data URL, never as code.
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
  fs.writeFileSync(`${OUT}/favicon.svg`, SYMBOL_SVG);
  written.push('favicon.svg');
  return written;
}
