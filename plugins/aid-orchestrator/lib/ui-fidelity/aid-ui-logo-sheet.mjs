// aid-ui-logo-sheet.mjs — every logo direction shown where it will live (step 1i, Rozcestník):
// per direction one card PNG (web header with the lockup, browser tab at 16 px, phone icon, round
// avatar, business card in black) and one overview PNG of all directions side by side with the
// competitors' logos underneath (the shelf test the adopted logo-design skill asks for).
//   node aid-ui-logo-sheet.mjs --spec <sheet.json> [--root <project>]
// sheet.json (paths relative to --root, default the current directory):
//   {"name": "Coufal Clinic",
//    "fonts": ["https://fonts.googleapis.com/css2?family=…&display=swap"],   // optional stylesheets
//    "out_dir": ".aid-ui/studio",                       // PNGs go here: logo-<id>.png, logo-prehled.png
//    "recommend": "b",                                   // id of the first (recommended) direction
//    "directions": [{"id": "a", "title": "A · Nápis", "note": "one sentence",
//                    "lockup": "…/a-lockup.svg", "symbol": "…/a-symbol.svg", "small": "…/a-small.svg"}],
//    "competitors": [{"name": "Dental Machine", "image": ".aid-ui/refs/competitors/dm.png"}]}
// `small` (the 16 px cut) is optional and falls back to `symbol`. Symbols and competitor images are
// embedded as data URIs; a lockup SVG is inlined into the page, so its <text> may use a family from
// `fonts` (exploration only; the kit sets the name in outlines through aid-ui-tool.sh wordmark).
// Prints one line per written file. Exit: 0, 1 a file cannot be read, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const opt = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
const specPath = opt('--spec');
const contactDir = opt('--contact');
if (!specPath && !contactDir) { console.error('usage: aid-ui-logo-sheet.mjs --spec <sheet.json> [--root <project>] | --contact <dir of concept PNGs> --out <png> [--root <project>]'); process.exit(2); }
const root = path.resolve(opt('--root') || '.');
if (contactDir) {   // the curation contact sheet (step 1i phase 4b): every concept PNG with its name, large and at 32 px
  const dir = path.resolve(root, contactDir);
  const outFile = path.resolve(root, opt('--out') || path.join(contactDir, 'kontakt.png'));
  let files;
  try { files = fs.readdirSync(dir).filter((f) => /\.png$/i.test(f) && !/^kontakt/.test(f)).sort(); } catch (e) { console.error(`ERROR: ${contactDir}: ${e.message}`); process.exit(1); }
  if (!files.length) { console.error(`ERROR: ${contactDir}: no PNG concepts`); process.exit(1); }
  // the page is written next to the PNGs and loaded from file://, so thirty 1 MB concepts are not inlined
  const cell = (f) => { const u = encodeURIComponent(f);
    return `<div class="c"><div class="big"><img src="${u}"></div><div class="row"><span class="s32"><img src="${u}"></span><span class="s16"><img src="${u}"></span><b>${f.replace(/\.png$/i, '')}</b></div></div>`; };
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#fff;font:12px system-ui}
  .g{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;padding:12px;width:1500px;box-sizing:border-box}
  .c{border:1px solid #ddd;border-radius:8px;padding:8px;background:#fff}.big{width:220px;height:220px;background:#fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Crect width='8' height='8' fill='%23eee'/%3E%3Crect x='8' y='8' width='8' height='8' fill='%23eee'/%3E%3C/svg%3E")}
  .big img{width:220px;height:220px}.row{display:flex;align-items:center;gap:8px;margin-top:6px}.s32 img{width:32px;height:32px}.s16 img{width:16px;height:16px}
  .s32,.s16{display:inline-flex;padding:2px;background:#fff;border:1px solid #eee}</style></head><body><div class="g">${files.map(cell).join('')}</div></body></html>`;
  const htmlFile = path.join(dir, 'kontakt.html');
  fs.writeFileSync(htmlFile, html);
  const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
  const page = await browser.newPage({ viewport: { width: 1500, height: 900 } });
  await page.goto('file://' + htmlFile);
  await page.waitForFunction(() => [...document.images].every((i) => i.complete));
  await page.screenshot({ path: outFile, fullPage: true });
  await browser.close();
  fs.unlinkSync(htmlFile);
  console.log(`${path.relative(root, outFile)} (${files.length} concepts)`);
  process.exit(0);
}
let spec;
try { spec = JSON.parse(fs.readFileSync(path.resolve(root, specPath), 'utf8')); }
catch (e) { console.error(`ERROR: ${specPath}: ${e.message}`); process.exit(1); }
if (!spec.name || !Array.isArray(spec.directions) || !spec.directions.length || !spec.out_dir) {
  console.error('ERROR: sheet.json needs name, out_dir and a non-empty directions list'); process.exit(2);
}
const MIME = { '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' };
function uri(p, invert = false, vectorOnly = false) {
  const full = path.resolve(root, p);
  const mime = MIME[path.extname(full).toLowerCase()];
  if (!mime) { console.error(`ERROR: ${p}: not an svg/png/jpg/webp`); process.exit(1); }
  let buf;
  try { buf = fs.readFileSync(full); } catch (e) { console.error(`ERROR: ${p}: ${e.message}`); process.exit(1); }
  // a symbol the PM sees is a vector: never a raster, never an SVG that merely wraps one
  if (vectorOnly && (mime !== 'image/svg+xml' || /<image|<foreignObject|<script|href=|<text/i.test(buf.toString('utf8')))) {
    console.error(`ERROR: ${p}: a symbol must be plain vector SVG (no image, text, script, links)`); process.exit(1);
  }
  if (invert && mime === 'image/svg+xml') buf = Buffer.from(buf.toString('utf8').replace(/#111(?![0-9a-fA-F])|#111111|#000(?![0-9a-fA-F])|#000000|black/g, '#fff'));
  return `data:${mime};base64,${buf.toString('base64')}`;
}
function conceptOk(d) {   // the concept PNG must be one the generation record (gen.json next to it) received
  const full = path.resolve(root, d.lockup);
  let rec;
  try { rec = JSON.parse(fs.readFileSync(path.join(path.dirname(full), 'gen.json'), 'utf8')); } catch (e) { rec = null; }
  const listed = rec && Object.values(rec.slots || {}).some((s) => (s.files || []).some((f) => path.resolve(root, f) === full));
  if (!listed) { console.error(`ERROR: ${d.lockup}: a concept card needs a PNG that the gen.json next to it lists as received`); process.exit(1); }
}

function inlineSvg(p, cls) {
  const full = path.resolve(root, p);
  if (path.extname(full).toLowerCase() !== '.svg') return `<img class="${cls}" src="${uri(p)}">`;
  let svg;
  try { svg = fs.readFileSync(full, 'utf8'); } catch (e) { console.error(`ERROR: ${p}: ${e.message}`); process.exit(1); }
  if (/<script|on[a-z]+=|<foreignObject|href="(?!#)/i.test(svg)) { console.error(`ERROR: ${p}: a lockup must be plain SVG (no script, handlers, foreignObject or links)`); process.exit(1); }
  return svg.replace(/<\?xml[^>]*>/, '').replace(/<svg\b/, `<svg class="${cls}"`);
}
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const head = `<meta charset="utf-8">${(spec.fonts || []).map((u) => `<link rel="stylesheet" href="${esc(u)}">`).join('')}
<style>body{margin:0;font:13px/1.4 system-ui,sans-serif;color:#222;background:#fff}
.card{width:1200px;display:grid;grid-template-columns:1fr 1fr;gap:18px;padding:18px;box-sizing:border-box}
.ctx{border:1px solid #e3e3e3;border-radius:10px;padding:14px;background:#fafafa;position:relative}
.ctx .l{position:absolute;left:14px;bottom:8px;font-size:11px;color:#777}
.hero{grid-column:1/3;background:#fff;height:250px;display:flex;flex-direction:column}
.bar{display:flex;align-items:center;justify-content:space-between;padding:14px 28px;border-bottom:1px solid #eee}
.bar img,.bar svg{height:48px;width:auto}.bar nav{display:flex;gap:22px;color:#444;font-size:14px}.bar b{background:#222;color:#fff;padding:8px 14px;border-radius:8px;font-weight:600}
.heroin{flex:1;display:flex;align-items:center;padding:0 28px;gap:40px}.heroin h1{font-size:30px;margin:0;max-width:520px;line-height:1.2}
.tab{height:150px}.tabbar{background:#dee1e6;border-radius:10px 10px 0 0;padding:8px 10px 0;display:flex;gap:6px}
.tabbar span{background:#fff;border-radius:8px 8px 0 0;padding:8px 14px;display:flex;align-items:center;gap:8px;font-size:12px}
.tabbar img{width:16px;height:16px}.phone{height:150px;background:#2b3340;color:#fff}
.phone .grid{display:flex;gap:16px;align-items:flex-start;padding:6px}.phone .app{width:58px;text-align:center;font-size:10px}
.phone .app i{display:block;width:58px;height:58px;border-radius:14px;background:#4a5568;margin-bottom:4px;display:flex;align-items:center;justify-content:center}
.phone .app i.me{background:#fff}.phone .app i img{width:40px;height:40px}
.avatar{height:150px;display:flex;align-items:center;gap:20px}.avatar i{width:96px;height:96px;border-radius:50%;background:#fff;border:1px solid #ddd;display:flex;align-items:center;justify-content:center;overflow:hidden}
.avatar i img{width:64px;height:64px}.avatar .dark{background:#111}
.card .bc{height:150px;display:flex;align-items:center}.bc div{width:300px;height:170px;transform:scale(.72);transform-origin:left center;background:#fff;border:1px solid #ccc;border-radius:6px;padding:18px;box-sizing:border-box;filter:grayscale(1)}
.bc img,.bc svg{height:34px;width:auto}.bc p{margin:30px 0 0;font-size:12px;color:#333}
.ov{width:1600px;padding:28px;box-sizing:border-box;background:#f7f7f5}.ov h1{font-size:24px;margin:0 0 4px}.ov .sub{color:#666;margin:0 0 18px}
.row{display:grid;gap:16px}.dir{background:#fff;border:1px solid #e3e3e3;border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:10px;min-height:280px}
.dir.rec{border:2px solid #222}.dir .lk{height:96px;display:flex;align-items:center}.dir .lk img,.dir .lk svg{max-height:96px;max-width:100%;height:96px;width:auto}
.dir .sy{display:flex;align-items:flex-end;gap:14px}.dir .sy img{width:48px;height:48px}.dir .sy img.s{width:16px;height:16px}
.dir h2{font-size:17px;margin:0}.dir .rc{font-size:11px;letter-spacing:.08em;color:#222;font-weight:700}.dir p{margin:0;color:#444}
.shelf{margin-top:22px;background:#fff;border:1px solid #e3e3e3;border-radius:12px;padding:16px}.shelf h3{margin:0 0 10px;font-size:13px;color:#666;letter-spacing:.06em}
.shelf .r{display:flex;gap:18px;align-items:center;flex-wrap:wrap}.shelf .r div{text-align:center;font-size:11px;color:#666}.shelf .r img{height:44px;max-width:180px;object-fit:contain;display:block;margin:0 auto 4px}
</style>`;

function card(d) {
  if (d.concept) {   // a complete composition from the image model (mode full): shown as it is, flagged as a concept;
                     // tab, phone and avatar come from the chosen direction once it is rebuilt as a vector
    conceptOk(d);
    const L = uri(d.lockup);
    // a two-step run also has the mark alone (the icon): show it in the tab, on the phone and as the avatar
    const M = d.symbol ? uri(d.symbol) : null;
    const icons = M ? `
  <div class="ctx tab"><div class="tabbar"><span><img src="${M}">${esc(spec.name)}</span><span style="opacity:.6">Nová karta</span></div><span class="l">záložka prohlížeče, 16 px (symbol od modelu)</span></div>
  <div class="ctx phone"><div class="grid"><div class="app"><i></i>app</div><div class="app"><i class="me"><img src="${M}"></i>${esc(spec.name)}</div><div class="app"><i></i>app</div><div class="app"><i></i>app</div></div><span class="l" style="color:#bbb">ikona na telefonu</span></div>
  <div class="ctx avatar" style="grid-column:1/3"><i><img src="${M}"></i><span class="l">avatar (Google profil, najdizubara)</span></div>` : '';
    return `<!doctype html><html><head>${head}</head><body><div class="card">
  <div class="ctx hero" style="height:auto"><div class="bar"><img src="${L}" style="height:110px"><nav><span>Služby</span><span>Cenník</span><span>Kontakt</span><b>Objednať sa</b></nav></div>
    <div class="heroin" style="padding:24px 28px"><h1>${esc(spec.hero || spec.name)}</h1></div><span class="l">hlavička a hero webu</span></div>${icons}
  <div class="ctx" style="grid-column:1/3;display:flex;gap:24px;align-items:center;background:#fff"><img src="${L}" style="width:560px;height:560px;object-fit:contain"><div style="font-size:13px;color:#555;max-width:520px"><b style="display:inline-block;background:#fde68a;color:#222;padding:2px 8px;border-radius:6px;font-size:11px;letter-spacing:.06em">KONCEPT OD OBRAZOVÉHO MODELU</b><p>Tak, jak ho model nakreslil. Po volbě se přestaví do skutečného souboru: symbol jako vektor, název skutečným písmem, barvy z obrázku; teprve pak ikona v prohlížeči, na telefonu a avatar.</p></div></div>
  <div class="ctx bc" style="grid-column:1/3"><div><img src="${L}" style="height:48px"><p>${esc(spec.name)}<br>${esc(spec.address || '')}</p></div><span class="l">vizitka, černobíle</span></div>
  </div></body></html>`;
  }
  const L = inlineSvg(d.lockup, 'lk'), S = uri(d.symbol, false, true), Sm = uri(d.small || d.symbol, false, true), Sw = uri(d.small || d.symbol, true, true);
  return `<!doctype html><html><head>${head}</head><body><div class="card">
  <div class="ctx hero"><div class="bar">${L}<nav><span>Služby</span><span>Cenník</span><span>Kontakt</span><b>Objednať sa</b></nav></div>
    <div class="heroin"><h1>${esc(spec.hero || spec.name)}</h1></div><span class="l">hlavička a hero webu</span></div>
  <div class="ctx tab"><div class="tabbar"><span><img src="${Sm}">${esc(spec.name)}</span><span style="opacity:.6">Nová karta</span></div><span class="l">záložka prohlížeče, 16 px</span></div>
  <div class="ctx phone"><div class="grid"><div class="app"><i></i>app</div><div class="app"><i class="me"><img src="${S}"></i>${esc(spec.name)}</div><div class="app"><i></i>app</div><div class="app"><i></i>app</div></div><span class="l" style="color:#bbb">ikona na telefonu</span></div>
  <div class="ctx avatar"><i><img src="${S}"></i><i class="dark"><img src="${Sw}"></i><span class="l">avatar (Google profil, najdizubara)</span></div>
  <div class="ctx bc"><div>${L}<p>${esc(spec.name)}<br>${esc(spec.address || '')}</p></div><span class="l">vizitka, černobíle</span></div>
  </div></body></html>`;
}
function overview() {
  const n = spec.directions.length;
  const dirs = spec.directions.map((d) => `<div class="dir${d.id === spec.recommend ? ' rec' : ''}">
    ${d.concept ? `<div class="lk" style="height:200px"><img src="${uri(d.lockup)}" style="max-height:200px"></div><div style="font-size:10px;color:#92400e;letter-spacing:.06em">KONCEPT OD MODELU</div>`
                : `<div class="lk">${inlineSvg(d.lockup, 'lk')}</div><div class="sy"><img src="${uri(d.symbol, false, true)}"><img class="s" src="${uri(d.small || d.symbol, false, true)}"></div>`}
    <h2>${esc(d.title)}</h2>${d.id === spec.recommend ? '<div class="rc">DOPORUČENO</div>' : ''}<p>${esc(d.note || '')}</p></div>`).join('');
  const comp = (spec.competitors || []).map((c) => `<div><img src="${uri(c.image)}">${esc(c.name)}</div>`).join('');
  return `<!doctype html><html><head>${head}</head><body><div class="ov"><h1>${esc(spec.name)} - směry loga</h1><p class="sub">${esc(spec.subtitle || '')}</p>
  <div class="row" style="grid-template-columns:repeat(${Math.min(n, 5)},1fr)">${dirs}</div>
  ${comp ? `<div class="shelf"><h3>VEDLE KONKURENCE (jejich dnešní loga)</h3><div class="r">${comp}</div></div>` : ''}</div></body></html>`;
}

const out = path.resolve(root, spec.out_dir);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
let page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
async function shoot(html, file, width, scale = 1) {
  await page.close().catch(() => {}); page = await browser.newPage({ viewport: { width, height: 900 }, deviceScaleFactor: scale });
  await page.setContent(html, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => [...document.images].every((i) => i.complete) && document.fonts.status === 'loaded');
  await page.screenshot({ path: file, fullPage: true });
  console.log(path.relative(root, file));
}
for (const d of spec.directions) {
  if (!/^[A-Za-z0-9-]+$/.test(String(d.id)) || !d.lockup || (!d.symbol && !d.concept) || !d.title) { console.error(`ERROR: direction needs id [A-Za-z0-9-], title, lockup and symbol (or concept: true): ${JSON.stringify(d.id)}`); process.exit(2); }
  if (d.concept) {   // the thumbnail is the contexts card, rendered at 2x so the header logo stays crisp; the plain logo is the second picture
    conceptOk(d);
    await shoot(card(d), path.join(out, `logo-${d.id}.png`), 1200, 2);
    fs.copyFileSync(path.resolve(root, d.lockup), path.join(out, `logo-${d.id}-logo.png`));
    console.log(path.relative(root, path.join(out, `logo-${d.id}-logo.png`)));
  } else {
    await shoot(card(d), path.join(out, `logo-${d.id}.png`), 1200);
  }
}
await shoot(overview(), path.join(out, 'logo-prehled.png'), 1600);
await browser.close();
