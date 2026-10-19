const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const basisMod = require('./basis');   // 2.114.0: the real screen a UI brainstorm's proposal stands beside
const lifetime = require('./lifetime');  // 2.114.0: ends itself when idle, unless kept; always after 60 days

const PORT = process.env.BRAINSTORM_PORT || (49152 + Math.floor(Math.random() * 16383));
const HOST = process.env.BRAINSTORM_HOST || '127.0.0.1';
const URL_HOST = process.env.BRAINSTORM_URL_HOST || (HOST === '127.0.0.1' ? 'localhost' : HOST);
// Hostnames the keep button may be posted from (the port may differ behind a port forward).
const CONFIRM_HOSTS = ['localhost', '127.0.0.1', '::1', HOST, URL_HOST];
const SCREEN_DIR = process.env.BRAINSTORM_DIR || '/tmp/brainstorm';
const BASIS = basisMod.load(process.env.BRAINSTORM_BASIS || '');   // throws on a broken basis: no server over a wrong one
const META = { plan: process.env.BRAINSTORM_PLAN || '', project: process.env.BRAINSTORM_PROJECT || '' };
const LIFE = lifetime.create({ screenDir: SCREEN_DIR, idleMs: process.env.BRAINSTORM_IDLE_MS, maxMs: process.env.BRAINSTORM_MAX_MS });

if (!fs.existsSync(SCREEN_DIR)) {
  fs.mkdirSync(SCREEN_DIR, { recursive: true });
}

// Load frame template and helper script once at startup
const frameTemplate = fs.readFileSync(path.join(__dirname, 'frame-template.html'), 'utf-8');
const helperScript = fs.readFileSync(path.join(__dirname, 'helper.js'), 'utf-8');
const helperInjection = `<script>\n${helperScript}\n</script>`;

// Detect whether content is a full HTML document or a bare fragment
function isFullDocument(html) {
  const trimmed = html.trimStart().toLowerCase();
  return trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');
}

// Wrap a content fragment in the frame template
function wrapInFrame(content) {
  return frameTemplate.replace('<!-- CONTENT -->', content);
}

// Find the newest .html file in the directory by mtime
function getNewestScreen() {
  const files = fs.readdirSync(SCREEN_DIR)
    .filter(f => f.endsWith('.html'))
    .map(f => ({
      name: f,
      path: path.join(SCREEN_DIR, f),
      mtime: fs.statSync(path.join(SCREEN_DIR, f)).mtime.getTime()
    }))
    .sort((a, b) => b.mtime - a.mtime);

  return files.length > 0 ? files[0].path : null;
}

const WAITING_PAGE = `<!DOCTYPE html>
<html>
<head>
  <title>Brainstorm Companion</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 2rem; max-width: 800px; margin: 0 auto; }
    h1 { color: #333; }
    p { color: #666; }
  </style>
</head>
<body>
  <h1>Brainstorm Companion</h1>
  <p>Waiting for Claude to push a screen...</p>
</body>
</html>`;

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const clients = new Set();

wss.on('connection', (ws, req) => {
  clients.add(ws); LIFE.connected();
  ws.on('close', () => { clients.delete(ws); LIFE.disconnected(); });

  ws.on('message', (data) => {
    let event;
    try { event = JSON.parse(data.toString()); } catch (e) { return; }
    console.log(JSON.stringify({ source: 'user-event', ...event }));
    // Write user events to .events file for Claude to read (the old screens' file, emptied per new screen)
    if (event.choice) {
      const eventsFile = path.join(SCREEN_DIR, '.events');
      fs.appendFileSync(eventsFile, JSON.stringify(event) + '\n');
    }
    // Every page event, appended and never cleared: what `aid-companion.sh answers` reads.
    // An agent can write this file too, so it is the agent's input, never proof of a PM choice.
    if (['choice', 'note', 'confirm'].includes(event.type)) {
      const row = { v: 1, plan: META.plan || null, kolo: event.kolo ?? null, page: event.page || event.screen || null,
        event_id: crypto.randomUUID(), at: new Date().toISOString(), ...event };
      fs.appendFileSync(path.join(SCREEN_DIR, 'answers.jsonl'), JSON.stringify(row) + '\n');
    }
  });
});

// The AID tab icon, shared with the studio (lib/aid-ui-studio/aid-icon.svg)
const ICON_FILE = path.join(__dirname, '..', 'aid-ui-studio', 'aid-icon.svg');
const ICON_LINK = '<link rel="icon" href="/favicon.svg" type="image/svg+xml">';
app.get('/favicon.svg', (req, res) => { res.type('image/svg+xml').send(fs.readFileSync(ICON_FILE)); });

// Serve newest screen with helper.js injected. With a basis (a UI brainstorm),
// "/" is the composed page — today beside the proposal — and the agent's screen
// itself moves to "/screen" (the frame inside the composed page loads it).
basisMod.routes(app, BASIS);
function serveScreen(req, res) {
  const screenFile = getNewestScreen();
  let html;

  if (!screenFile) {
    html = WAITING_PAGE;
  } else {
    const raw = fs.readFileSync(screenFile, 'utf-8');
    html = isFullDocument(raw) ? raw : wrapInFrame(raw);
  }

  // A page without its own tab icon gets the AID one
  if (!/rel=["']?(shortcut )?icon/i.test(html)) {
    html = /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, m => `${m}\n${ICON_LINK}`) : ICON_LINK + html;
  }

  // Inject the helper script
  if (html.includes('</body>')) {
    html = html.replace('</body>', () => `${helperInjection}\n</body>`);
  } else {
    html += helperInjection;
  }

  res.type('html').send(html);
}
// The kit's captures (aid-companion.sh shots): only <screen_dir>/shots, the page refers to them relatively.
app.use('/shots', express.static(path.join(SCREEN_DIR, 'shots'), { dotfiles: 'deny', index: false }));
app.get('/screen', serveScreen);
app.get('/', BASIS ? (req, res) => res.type('html').send(basisMod.compose(BASIS, '/screen', META)) : serveScreen);

// "Držet" (keep): the PM decides on the page whether this companion survives
// the idle shutdown. POST toggles, GET reads. Same-origin only (Host must be
// one of the server's own names), like a confirm.
// Host AND Origin must both be one of the server's own names (a foreign page
// posting to the allowed address is refused, like a confirm; no Origin = refused).
// Host part of an Origin header ("http://h:p" -> "h:p"); "" when absent or malformed.
function originHost(origin) {
  try { return new URL(origin).host; } catch (e) { return ''; }
}
function hostName(v) { return String(v || '').replace(/:\d+$/, '').replace(/^\[|\]$/g, ''); }
function ownRequest(req) {
  const o = originHost(req.headers.origin);
  return !!o && CONFIRM_HOSTS.includes(hostName(o)) && CONFIRM_HOSTS.includes(hostName(req.headers.host));
}
app.get('/aid/keep', (req, res) => res.json({ kept: LIFE.isKept(), ...LIFE.state() }));
app.post('/aid/keep', (req, res) => {
  if (!ownRequest(req)) return res.status(403).json({ error: 'foreign origin or host' });
  const kept = LIFE.isKept() ? LIFE.unkeep() : LIFE.keep('pm');
  console.log(JSON.stringify({ type: kept ? 'kept' : 'unkept', screen_dir: SCREEN_DIR }));
  res.json({ kept });
});
setInterval(() => {
  const why = LIFE.check();
  if (!why) return;
  console.log(JSON.stringify({ type: 'server-exit', reason: why, screen_dir: SCREEN_DIR, ...LIFE.state() }));
  server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000).unref();
}, Number(process.env.BRAINSTORM_LIFE_TICK_MS || 60000)).unref();

// Watch for new or changed .html files
chokidar.watch(SCREEN_DIR, { ignoreInitial: true })
  .on('add', (filePath) => {
    if (filePath.endsWith('.html')) {
      // Clear events from previous screen
      const eventsFile = path.join(SCREEN_DIR, '.events');
      if (fs.existsSync(eventsFile)) fs.unlinkSync(eventsFile);
      console.log(JSON.stringify({ type: 'screen-added', file: filePath })); LIFE.touch();
      clients.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'reload' }));
        }
      });
    }
  })
  .on('change', (filePath) => {
    if (filePath.endsWith('.html')) {
      console.log(JSON.stringify({ type: 'screen-updated', file: filePath })); LIFE.touch();
      clients.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'reload' }));
        }
      });
    }
  });

server.listen(PORT, HOST, () => {
  console.log(JSON.stringify({
    type: 'server-started',
    port: PORT,
    host: HOST,
    url_host: URL_HOST,
    url: `http://${URL_HOST}:${PORT}`,
    screen_dir: SCREEN_DIR,
    basis: BASIS ? BASIS.basis : null,
    plan: META.plan || null,
    project: META.project || null
  }));
});
