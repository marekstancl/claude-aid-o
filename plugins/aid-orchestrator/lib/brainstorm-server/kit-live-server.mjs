// kit-live-server.mjs — the live preview of aid-companion.sh live (3.17.0): the PM opens the real application
// (the plan's copy, its dev server on a loopback port) in his own browser, on his own screen, on dev data, with a
// small AID panel on top to switch variants, choose, note and send. No captures.
//
//   node kit-live-server.mjs <screen_dir> <listen_host> <listen_port> <plan>   (token in AID_LIVE_TOKEN, the
//   allowed /@fs/ roots in AID_LIVE_FS_ROOTS, ':'-separated)
//
// ACCESS: the port is reachable from the network, the app shows dev data (real names in WAN), so nothing passes
// without the run's token: the PM's address carries ?aid_t=<token>, the proxy turns it into an HttpOnly SameSite
// cookie and every request (websocket too) without it is 403. /@fs/ (the dev server's file reader) passes only under
// the copy and its node_modules; /__open-in-editor never. HTML gets a CSP connect-src 'self': the page reaches the
// proxy alone, whatever a variant's code would call. The copy's port is read from proto.json on every request.
//
// Everything but /__aid/* is passed to 127.0.0.1:<proto_port> (websocket upgrades too, so the dev server's
// reload works). An HTML response gets window.AID_VARIANT (from ?v=, remembered in the aid_v cookie) after
// <head> and the panel script before </body>; every other response passes byte for byte. The panel posts to
// /__aid/answer, accepted only from a page this server served (Origin host:port == Host): rows land in
// <screen_dir>/answers.jsonl in the companion page's own shape, so `aid-companion.sh answers` reads them.
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const [DIR, HOST, PORT, PLAN] = process.argv.slice(2);
const TOKEN = process.env.AID_LIVE_TOKEN || '';
if (!/^[0-9a-f]{32,}$/.test(TOKEN)) { console.error('kit-live-server: AID_LIVE_TOKEN (32+ hex) is required'); process.exit(2); }
const FS_ROOTS = (process.env.AID_LIVE_FS_ROOTS || '').split(':').filter(Boolean).map(r => path.resolve(r) + path.sep);
const require = createRequire(import.meta.url);
const ANSWERS = require('./answers.js');
const protoPort = () => { try { return JSON.parse(fs.readFileSync(path.join(DIR, 'proto.json'), 'utf8')).port; } catch { return null; } };
const tokenOk = req => {
  const m = /(?:^|;\s*)aid_t=([0-9a-f]+)/.exec(req.headers.cookie || '');
  const got = (m && m[1]) || new URL(req.url, 'http://x').searchParams.get('aid_t') || '';
  return got.length === TOKEN.length && crypto.timingSafeEqual(Buffer.from(got), Buffer.from(TOKEN));
};
const pathOk = pathname => {
  let p; try { p = decodeURIComponent(pathname); } catch { return false; }
  if (p.startsWith('/__open-in-editor')) return false;
  if (p.startsWith('/@fs/')) { const f = path.resolve(p.slice(4)); return FS_ROOTS.some(r => (f + path.sep).startsWith(r) || f.startsWith(r)); }
  return true;
};
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PANEL = fs.readFileSync(path.join(HERE, 'kit-live-panel.js'), 'utf8');
const VKEY = /^[A-Za-z0-9_-]{1,32}$/;

const liveSpec = () => { try { return JSON.parse(fs.readFileSync(path.join(DIR, 'live.json'), 'utf8')); } catch { return null; } };
// a variant is one of live.json's keys, nothing else reaches the page
const keys = () => new Set(((liveSpec() || {}).body || []).flatMap(b => (b.varianty || []).map(v => String(v.klic))));
const variantOf = req => {
  const u = new URL(req.url, 'http://x'), q = u.searchParams.get('v');
  const m = /(?:^|;\s*)aid_v=([A-Za-z0-9_-]{1,32})/.exec(req.headers.cookie || '');
  const v = q !== null ? q : (m ? m[1] : null);
  return v !== null && VKEY.test(v) && keys().has(v) ? v : null;
};

function answer(req, res) {
  if (req.method !== 'POST' || !ANSWERS.ownRequest(req)) { res.writeHead(403, { 'content-type': 'application/json' }); return res.end('{"error":"foreign origin or host"}'); }
  let body = '';
  req.on('data', c => { body += c; if (body.length > 20000) req.destroy(); });
  req.on('end', () => {
    let ev; try { ev = JSON.parse(body); } catch { res.writeHead(400); return res.end('{"error":"not JSON"}'); }
    const spec = liveSpec() || {};
    const clean = { type: ev.type, bod: ev.bod ?? null, volba: ev.volba ?? null, text: typeof ev.text === 'string' ? ev.text.slice(0, 4000) : null,
      cesta: typeof ev.cesta === 'string' ? ev.cesta.slice(0, 500) : null, viewport: typeof ev.viewport === 'string' ? ev.viewport.slice(0, 40) : null };
    if (!ANSWERS.appendAnswer(DIR, clean, { plan: PLAN, kolo: spec.kolo ?? null, page: 'live', zdroj: 'live' })) { res.writeHead(400); return res.end('{"error":"type is choice, note or confirm"}'); }
    res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"ok":true}');
  });
}

function inject(html, variant) {
  const v = `<script>window.AID_VARIANT=${JSON.stringify(variant)};</script>`;
  const p = '<script src="/__aid/panel.js" defer></script>';
  html = /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, m => m + v) : v + html;
  return /<\/body>/i.test(html) ? html.replace(/<\/body>/i, m => p + m) : html + p;
}

const deny = (res, code, msg) => { res.writeHead(code, { 'content-type': 'text/plain; charset=utf-8' }); res.end(msg); };
const server = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (!tokenOk(req)) return deny(res, 403, 'AID živý náhled: chybí přístupový klíč — otevři adresu, kterou poslal agent (s ?aid_t=…).');
  if (u.searchParams.has('aid_t')) {   // the token becomes a cookie and leaves the address (history, a shared screenshot)
    u.searchParams.delete('aid_t');
    res.writeHead(302, { location: u.pathname + (u.search || ''), 'set-cookie': `aid_t=${TOKEN}; Path=/; HttpOnly; SameSite=Strict` });
    return res.end();
  }
  if (!pathOk(u.pathname)) return deny(res, 403, 'AID živý náhled: tahle cesta dev serveru se ven nepouští.');
  const PROTO_PORT = protoPort();
  if (!PROTO_PORT) return deny(res, 502, `AID živý náhled: kopie aplikace neběží — aid-companion.sh proto --plan ${PLAN} --live`);
  if (u.pathname === '/__aid/panel.js') { res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'no-store' }); return res.end(PANEL); }
  if (u.pathname === '/__aid/live.json') { res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }); return res.end(JSON.stringify(liveSpec() || {})); }
  if (u.pathname === '/__aid/answer') return answer(req, res);
  const variant = variantOf(req);
  const headers = { ...req.headers, host: `127.0.0.1:${PROTO_PORT}`, 'accept-encoding': 'identity' };
  delete headers.origin; delete headers.referer;   // the dev server sees its own loopback origin (allowedHosts stays as it is)
  const up = http.request({ host: '127.0.0.1', port: +PROTO_PORT, method: req.method, path: req.url, headers }, pr => {
    const type = String(pr.headers['content-type'] || '');
    const out = { ...pr.headers };
    // the app's cookies (a login through the dev API) on the PM's http://<ip>:<port>: no Domain, no Secure
    if (out['set-cookie']) out['set-cookie'] = [].concat(out['set-cookie']).map(c => c.replace(/;\s*Domain=[^;]*/ig, '').replace(/;\s*Secure/ig, ''));
    if (u.searchParams.has('v') && variant) out['set-cookie'] = [].concat(out['set-cookie'] || [], `aid_v=${variant}; Path=/; SameSite=Strict`);
    if (!type.includes('text/html')) { res.writeHead(pr.statusCode, out); return pr.pipe(res); }
    const chunks = []; pr.on('data', c => chunks.push(c));
    pr.on('end', () => {
      const html = inject(Buffer.concat(chunks).toString('utf8'), variant);
      delete out['content-length']; delete out['content-encoding'];
      out['content-security-policy'] = "connect-src 'self'";
      res.writeHead(pr.statusCode, out); res.end(html);
    });
  });
  up.on('error', e => { res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' }); res.end(`AID živý náhled: kopie aplikace neodpovídá (${e.code || e.message}) — aid-companion.sh proto --plan ${PLAN} --live`); });
  req.pipe(up);
});

// websocket and any other upgrade: the raw request head, then both directions as they are
server.on('upgrade', (req, sock, head) => {
  const PROTO_PORT = protoPort();
  if (!tokenOk(req) || !PROTO_PORT) { sock.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return; }
  const up = net.connect(+PROTO_PORT, '127.0.0.1', () => {
    const lines = [`${req.method} ${req.url} HTTP/${req.httpVersion}`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      if (/^host$/i.test(k)) lines.push(`Host: 127.0.0.1:${PROTO_PORT}`);
      else if (/^origin$/i.test(k)) lines.push(`Origin: http://127.0.0.1:${PROTO_PORT}`);
      else lines.push(`${k}: ${req.rawHeaders[i + 1]}`);
    }
    up.write(lines.join('\r\n') + '\r\n\r\n'); if (head && head.length) up.write(head);
    sock.pipe(up).pipe(sock);
  });
  up.on('error', () => sock.destroy()); sock.on('error', () => up.destroy());
});

server.listen(+PORT, HOST, () => console.log(JSON.stringify({ type: 'live-started', port: +PORT, host: HOST })));
