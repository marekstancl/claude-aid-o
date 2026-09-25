// brand-icons.js - /aid-ui step 1i: renders the brand icon set through the Playwright
// MCP (mcp__plugin_playwright_playwright__browser_run_code_unsafe), no node_modules.
//
// Use: copy this file to <project>/.aid-ui/brand-icons.js, fill ONLY the three path
// constants below, then call browser_run_code_unsafe with `filename` pointing at the
// copy. The tool calls the function with `page` only.
// Never paste SVG markup into this file. The MCP sandbox has no Node API (no require,
// process or dynamic import, only `page`), so the snippet reads each file through a
// Playwright route: http://svg.local/<name> is fulfilled from the file as text/plain
// and fetched as a string from an empty routed page. The SVG is never navigated to
// (never a live document); it is rendered only as a data: URL in <img>, where an SVG
// runs no script and loads nothing. Defence in depth: only files named *.checked.svg
// are read, the output of
//   python3 aid-ui-ico.py --check-svg <symbol.svg> <symbol.checked.svg>
// (the shape allowlist: no script, event handler, DOCTYPE, remote reference). The
// sandbox cannot see whether a path is a symlink or a renamed unchecked file, so the
// name gate is not a guarantee; the <img>-only rendering is. Each path must be a
// plain absolute path matching ^/[A-Za-z0-9._/-]+$ (no quotes, backticks, `${`,
// spaces or newlines); the snippet re-checks and refuses anything else.
//
// Writes into OUT: favicon-16/32/48.png, apple-touch-icon.png (180), icon-192.png,
// icon-512.png, icon-maskable-512.png (mark inset to a 60 % safe zone, 20 % padding
// each side, on a solid BG - the rule of cockpit/packages/aid-gui/bin/gen-icons.cjs).
// A non-square or missing viewBox is refused. Then: cp SYMBOL_FILE OUT/favicon.svg,
// python3 aid-ui-ico.py OUT/favicon.ico OUT/favicon-{16,32,48}.png and
// python3 aid-ui-ico.py --verify OUT.
async (page) => {
  const SYMBOL_FILE = '__ABSOLUTE_SYMBOL_SVG__'; // <symbol>.checked.svg, text already as paths
  const MICRO_FILE = '';                         // optional <micro>.checked.svg for 16/32 px
  const OUT = '__ABSOLUTE_ICONS_DIR__';
  const BG = '#0a0a0f';                          // solid background of the maskable icon

  const PLAIN = /^\/[A-Za-z0-9._/-]+$/;
  for (const p of [SYMBOL_FILE, MICRO_FILE, OUT].filter(Boolean)) {
    if (!PLAIN.test(p) || p.includes('..')) throw new Error('refused: not a plain absolute path: ' + JSON.stringify(p));
  }
  for (const p of [SYMBOL_FILE, MICRO_FILE].filter(Boolean)) {
    if (!p.endsWith('.checked.svg')) throw new Error('refused: not a .checked.svg from aid-ui-ico.py --check-svg: ' + p);
  }
  // Read as inert text: route, empty same-origin page, fetch(). Never goto the SVG.
  const FILES = { '/symbol': SYMBOL_FILE, '/micro': MICRO_FILE };
  const ORIGIN = 'http://svg.local';
  await page.route(ORIGIN + '/**', (route) => {
    const path = route.request().url().slice(ORIGIN.length);
    return Object.hasOwn(FILES, path) && FILES[path]
      ? route.fulfill({ path: FILES[path], contentType: 'text/plain' })
      : route.fulfill({ body: '', contentType: 'text/html' });
  });
  await page.goto(ORIGIN + '/blank.html');
  const read = (name) => page.evaluate((u) => fetch(u).then((r) => {
    if (!r.ok) throw new Error('refused: could not read ' + u + ' (' + r.status + ')');
    return r.text();
  }), ORIGIN + '/' + name);
  const SYMBOL_SVG = await read('symbol');
  const MICRO_SVG = MICRO_FILE ? await read('micro') : '';

  for (const svg of [SYMBOL_SVG, MICRO_SVG].filter(Boolean)) {
    const vb = /viewBox\s*=\s*["']\s*([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)/.exec(svg);
    if (!vb) throw new Error('refused: the SVG has no viewBox');
    if (Number(vb[3]) !== Number(vb[4])) throw new Error(`refused: viewBox ${vb[3]}x${vb[4]} is not square`);
  }

  // The symbol as an <img> filling a size x size tile; maskable = 60 % mark on BG.
  // Rendering goes through an encoded data URL in <img>, where an SVG runs no script.
  const render = async (svg, size, file, maskable = false) => {
    const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    const inset = maskable ? Math.round(size * 0.2) : 0;
    const html = `<!doctype html><html><body style="margin:0">
      <div id="t" style="width:${size}px;height:${size}px;${maskable ? `background:${BG};` : ''}box-sizing:border-box;padding:${inset}px">
      <img src="${src}" style="display:block;width:100%;height:100%"></div></body></html>`;
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(html);
    await page.screenshot({ path: `${OUT}/${file}`, omitBackground: true, scale: 'css' });
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
  return 'written to ' + OUT + ': ' + written.join(' ');
}
