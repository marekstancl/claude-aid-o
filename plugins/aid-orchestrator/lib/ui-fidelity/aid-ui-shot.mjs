// aid-ui-shot.mjs — what the client agent and the critic see (P113a): full-page screenshots of live pages
// at 1440 and 390 wide, and the studio as the PM sees it (with the PM session cookie).
//   node aid-ui-shot.mjs <out-dir> [--cookie <file> --studio <url>] <url>...
//   node aid-ui-shot.mjs convert <a.webp>...      a png next to each (Codex takes no webp)
// A page is named after its path (index for the root): <out>/<name>-1440.png, <name>-390.png; the studio is
// studio-1440.png. Full page, cut at 5000 px (desktop) and 9000 px (mobile). Prints one JSON line
// {"files": [...]}; a page that fails gives "ERR <name>: <message>" in its place. Exit 0, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';

const argv = process.argv.slice(2);
const launch = () => chromium.launch({ executablePath: process.env.CHROME || undefined });
if (argv[0] === 'convert') {
  const b = await launch(); const p = await b.newPage(); const files = [];
  for (const f of argv.slice(1)) {
    await p.goto('file://' + f); const g = f.replace(/\.webp$/, '.png');
    await p.locator('img').first().screenshot({ path: g }); files.push(g);
  }
  await b.close(); console.log(JSON.stringify({ files })); process.exit(0);
}
const out = argv.shift();
let cookie = '', studio = '';
const urls = [];
while (argv.length) {
  const a = argv.shift();
  if (a === '--cookie') cookie = fs.readFileSync(argv.shift(), 'utf8').trim();
  else if (a === '--studio') studio = argv.shift();
  else urls.push(a);
}
if (!out || (!urls.length && !studio)) { console.error('usage: aid-ui-shot.mjs <out-dir> [--cookie <file> --studio <url>] <url>...'); process.exit(2); }
fs.mkdirSync(out, { recursive: true });
const b = await launch();
// the PM's session cookie only in the studio's own context: cookies ignore the port, so a page served on the
// same host must never be opened where the cookie is
const ctx = await b.newContext();
const sctx = await b.newContext();
if (cookie && studio) {
  const [name, value] = cookie.split('=');
  await sctx.addCookies([{ name, value, domain: new URL(studio).hostname, path: '/' }]);
}
const files = [];
async function shot(url, name, width, c = ctx) {
  const p = await c.newPage();   // a context page takes no options: the width is set here, or both shots are desktop
  await p.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
  try {
    await p.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    // scroll through once so lazy images and reveal-on-scroll content are in the shot, then back up
    await p.evaluate(async () => { for (let y = 0; y < document.documentElement.scrollHeight; y += 600) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); } window.scrollTo(0, 0); });
    await p.waitForTimeout(900);
    const h = Math.min(await p.evaluate(() => document.documentElement.scrollHeight), width === 390 ? 9000 : 5000);
    const f = `${out}/${name}-${width}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 0, width, height: h }, fullPage: true });
    files.push(f);
  } catch (e) { files.push(`ERR ${name}: ${String(e.message).slice(0, 100)}`); }
  await p.close();
}
if (studio) await shot(studio, 'studio', 1440, sctx);
for (const u of urls) {
  const name = new URL(u).pathname.replace(/^\/+|\/+$/g, '').replace(/\/index\.html$/, '').replace(/[^a-z0-9]+/gi, '-') || 'index';
  await shot(u, name, 1440); await shot(u, name, 390);
}
await b.close();
console.log(JSON.stringify({ files }));
