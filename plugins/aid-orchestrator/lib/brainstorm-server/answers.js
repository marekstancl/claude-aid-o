// answers.js — the ONE writer of <screen_dir>/answers.jsonl, shared by the companion page (index.js) and the live
// preview (kit-live-server.mjs). The page sends type/bod/volba/text; the server fields come last so a page cannot set
// them. The file is the agent's input, never proof of a PM choice (anyone with the file can write it).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function appendAnswer(dir, event, meta) {
  if (!['choice', 'note', 'confirm'].includes(event.type)) return false;
  const row = { ...event, v: 1, plan: meta.plan || null, kolo: event.kolo ?? meta.kolo ?? null,
    page: meta.page || event.page || event.screen || null, zdroj: meta.zdroj || 'page',
    event_id: crypto.randomUUID(), at: new Date().toISOString() };
  fs.appendFileSync(path.join(dir, 'answers.jsonl'), JSON.stringify(row) + '\n');
  return true;
}

// a request from a page this server served: the Origin's host:port is the request's Host (a page of another port on
// the same host is another site), and the name is one of the allowed ones when a list is given
function ownRequest(req, names) {
  let o = ''; try { o = new URL(req.headers.origin).host; } catch { return false; }
  if (!o || o !== String(req.headers.host || '')) return false;
  if (!names) return true;
  const h = o.replace(/:\d+$/, '').replace(/^\[|\]$/g, '');
  return names.includes(h);
}

module.exports = { appendAnswer, ownRequest };
