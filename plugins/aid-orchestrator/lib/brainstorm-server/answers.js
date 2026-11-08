// answers.js — the ONE writer of <screen_dir>/answers.jsonl, shared by the companion page (index.js) and the live
// preview (kit-live-server.mjs). The page sends type/bod/volba/text; the server fields come last so a page cannot set
// them. The file is the agent's input, never proof of a PM choice (anyone with the file can write it).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// types: what this caller may write — the companion page only choice/note/confirm, the live preview also `mark`
// (3.18.0). Returns the written row (its event_id is the mark's id), or null.
function appendAnswer(dir, event, meta, types = ['choice', 'note', 'confirm']) {
  if (!types.includes(event.type)) return null;
  const row = { ...event, v: 1, plan: meta.plan || null, kolo: event.kolo ?? meta.kolo ?? null,
    page: meta.page || event.page || event.screen || null, zdroj: meta.zdroj || 'page',
    event_id: crypto.randomUUID(), at: new Date().toISOString() };
  fs.appendFileSync(path.join(dir, 'answers.jsonl'), JSON.stringify(row) + '\n');
  return row;
}

// marks(dir) — the live marks: `mark` rows folded by id (a row with `id` and `smazano: true` removes the one it names)
function marks(dir) {
  let lines = []; try { lines = fs.readFileSync(path.join(dir, 'answers.jsonl'), 'utf8').split('\n'); } catch { return []; }
  const out = new Map();
  for (const l of lines) {
    let r; try { r = JSON.parse(l); } catch { continue; }
    if (!r || r.type !== 'mark') continue;
    if (r.smazano && r.id) out.delete(r.id); else if (!r.smazano) out.set(r.event_id, r);
  }
  return [...out.values()];
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

module.exports = { appendAnswer, ownRequest, marks };
