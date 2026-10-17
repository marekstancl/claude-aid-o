// aid-ui-shot.mjs — what the client agent and the critic see (P113a): full-page screenshots of live pages
// at 1440 and 390 wide, and the studio as the PM sees it (with the PM session cookie).
//   node aid-ui-shot.mjs <out-dir> [--cookie <file> --studio <url>] <url>...
//   node aid-ui-shot.mjs convert <a.webp>...      a png next to each (Codex takes no webp)
//   node aid-ui-shot.mjs <out-dir> --name <n> [--header] <url>...   (P113) free shots named <n>-<width>.png, made
//        unique by a counter (<n>-2-1440.png) when the name is taken (two shots in one second never overwrite);
//        --header adds <n>-header-1440.png, the first 240 px (a competitor's logo on the shelf)
//   node aid-ui-shot.mjs strip <out-dir> <url> [--every <ms>] [--until <ms>] [--width <px>]   (P113) frames of an
//        animation every <ms> (default 40) up to <ms> (default 3000): every animation of the page is paused and set
//        to that time (independent of the machine's speed); frame-<ms>.png
//   node aid-ui-shot.mjs video <out-dir> <url> [--until <ms>] [--width <px>]   (P113) a recording of the page from
//        load for <ms> (default 3000) as video.webm
// A page is named after its path (index for the root): <out>/<name>-1440.png, <name>-390.png; the studio is
// studio-1440.png. Full page, cut at 5000 px (desktop) and 9000 px (mobile). Prints one JSON line
// {"files": [...]}; a page that fails gives "ERR <name>: <message>" in its place. Exit 0, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';

const argv = process.argv.slice(2);
const launch = () => chromium.launch({ executablePath: process.env.CHROME || undefined });
const optOf = (args, k, d) => { const i = args.indexOf(k); if (i < 0) return d; const v = args[i + 1]; args.splice(i, 2); return v; };
if (argv[0] === 'strip' || argv[0] === 'video') {
  const mode = argv.shift();
  const every = Number(optOf(argv, '--every', 40)), until = Number(optOf(argv, '--until', 3000)), width = Number(optOf(argv, '--width', 1440));
  const [dir, url] = argv;
  if (!dir || !url || !(every > 0) || !(until > 0)) { console.error(`usage: aid-ui-shot.mjs ${mode} <out-dir> <url> [--every ms] [--until ms] [--width px]`); process.exit(2); }
  fs.mkdirSync(dir, { recursive: true });
  const b = await launch(); const files = [];
  if (mode === 'video') {
    const c = await b.newContext({ viewport: { width, height: width <= 430 ? 844 : 900 }, recordVideo: { dir, size: { width, height: width <= 430 ? 844 : 900 } } });
    const p = await c.newPage(); await p.goto(url, { waitUntil: 'load' }); await p.waitForTimeout(until);
    const v = p.video(); await c.close(); const src = await v.path(); const dst = `${dir}/video.webm`; fs.renameSync(src, dst); files.push(dst);
  } else {
    const p = await b.newPage({ viewport: { width, height: width <= 430 ? 844 : 900 } });
    await p.goto(url, { waitUntil: 'load' });
    await p.evaluate(() => document.getAnimations().forEach(a => a.pause()));
    for (let ms = 0; ms <= until; ms += every) {
      await p.evaluate(t => document.getAnimations().forEach(a => { a.pause(); a.currentTime = t; }), ms);
      const f = `${dir}/frame-${String(ms).padStart(5, '0')}.png`; await p.screenshot({ path: f }); files.push(f);
    }
  }
  await b.close(); console.log(JSON.stringify({ files })); process.exit(0);
}
if (argv[0] === 'convert') {
  const b = await launch(); const p = await b.newPage(); const files = [];
  for (const f of argv.slice(1)) {
    await p.goto('file://' + f); const g = f.replace(/\.webp$/, '.png');
    await p.locator('img').first().screenshot({ path: g }); files.push(g);
  }
  await b.close(); console.log(JSON.stringify({ files })); process.exit(0);
}
const out = argv.shift();
let cookie = '', studio = '', fixed = '', header = false;
const urls = [];
while (argv.length) {
  const a = argv.shift();
  if (a === '--cookie') cookie = fs.readFileSync(argv.shift(), 'utf8').trim();
  else if (a === '--studio') studio = argv.shift();
  else if (a === '--name') fixed = argv.shift().replace(/[^a-z0-9_-]+/gi, '-');
  else if (a === '--header') header = true;
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
    if (header && width === 1440) { const hf = `${out}/${name}-header-1440.png`; await p.screenshot({ path: hf, clip: { x: 0, y: 0, width, height: 240 } }); files.push(hf); }
  } catch (e) { files.push(`ERR ${name}: ${String(e.message).slice(0, 100)}`); }
  await p.close();
}
if (studio) await shot(studio, 'studio', 1440, sctx);
const free = n => { if (!fs.existsSync(`${out}/${n}-1440.png`)) return n; let k = 2; while (fs.existsSync(`${out}/${n}-${k}-1440.png`)) k++; return `${n}-${k}`; };
for (const u of urls) {
  const name = fixed ? free(fixed) : (new URL(u).pathname.replace(/^\/+|\/+$/g, '').replace(/\/index\.html$/, '').replace(/[^a-z0-9]+/gi, '-') || 'index');
  await shot(u, name, 1440); await shot(u, name, 390);
}
await b.close();
console.log(JSON.stringify({ files }));
