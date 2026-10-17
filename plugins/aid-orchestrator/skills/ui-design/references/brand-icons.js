// brand-icons.js - /aid-ui step 1i: re-renders favicon-32.png and favicon-48.png from the
// MEDIUM cut of the symbol through the Playwright MCP
// (mcp__plugin_playwright_playwright__browser_run_code_unsafe), no node_modules.
// P113: the rest of the web icon set (16 px from the small cut, apple-touch, 192, 512, maskable,
// site.webmanifest, head-snippet.html) comes from the adopted
//   export_variants.py <symbol.svg> --web-icons --icon-bg <brand colour> --favicon-source <small.svg>
// which this snippet does not repeat; it only replaces the two sizes the medium cut is drawn for.
//
// Use: copy this file to <project>/.aid-ui/brand-icons.js, fill ONLY the two path
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
// Writes into OUT (the export_variants.py output folder): favicon-32.png and favicon-48.png.
// A non-square or missing viewBox is refused. Then:
// python3 aid-ui-ico.py OUT/favicon.ico OUT/favicon-{16,32,48}.png and
// python3 aid-ui-ico.py --verify OUT.
async (page) => {
  const MEDIUM_FILE = '__ABSOLUTE_MEDIUM_SVG__'; // <medium cut>.checked.svg for 32-48 px, text already as paths
  const OUT = '__ABSOLUTE_ICONS_DIR__';

  const PLAIN = /^\/[A-Za-z0-9._/-]+$/;
  for (const p of [MEDIUM_FILE, OUT]) {
    if (!PLAIN.test(p) || p.includes('..')) throw new Error('refused: not a plain absolute path: ' + JSON.stringify(p));
  }
  for (const p of [MEDIUM_FILE]) {
    if (!p.endsWith('.checked.svg')) throw new Error('refused: not a .checked.svg from aid-ui-ico.py --check-svg: ' + p);
  }
  // Read as inert text: route, empty same-origin page, fetch(). Never goto the SVG.
  const FILES = { '/medium': MEDIUM_FILE };
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
  const MEDIUM_SVG = await read('medium');

  for (const svg of [MEDIUM_SVG]) {
    const vb = /viewBox\s*=\s*["']\s*([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)/.exec(svg);
    if (!vb) throw new Error('refused: the SVG has no viewBox');
    if (Number(vb[3]) !== Number(vb[4])) throw new Error(`refused: viewBox ${vb[3]}x${vb[4]} is not square`);
  }

  // The cut as an <img> filling a size x size tile.
  // Rendering goes through an encoded data URL in <img>, where an SVG runs no script.
  const render = async (svg, size, file) => {
    const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    const html = `<!doctype html><html><body style="margin:0">
      <div id="t" style="width:${size}px;height:${size}px">
      <img src="${src}" style="display:block;width:100%;height:100%"></div></body></html>`;
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(html);
    await page.screenshot({ path: `${OUT}/${file}`, omitBackground: true, scale: 'css' });
    return file;
  };

  const written = [
    await render(MEDIUM_SVG, 32, 'favicon-32.png'),
    await render(MEDIUM_SVG, 48, 'favicon-48.png'),
  ];
  return 'written to ' + OUT + ': ' + written.join(' ');
}
