// Confirms of companion screens, one per screen file, kept only in the server's
// memory. aid-ui-state.sh await-choice reads them through GET /aid/confirmed, so a
// PM choice never comes from a file the agent could write. No dependencies.
// ponytail: lost on a server restart; the PM confirms again (the round stays open).
const store = new Map();

// Host header "h:p" / "[::1]:p" / "h" -> lowercase hostname without port or brackets; "" when malformed.
function hostname(host) {
  const m = /^(?:\[([^\]]+)\]|([^:\[\]]+))(?::\d+)?$/.exec(String(host || '').toLowerCase());
  return m ? (m[1] || m[2]) : '';
}

// record(screen, event, originHost, requestHost, allowedHosts) — false when refused:
// the page's Origin host differs from the request's Host (another site's page), the
// Host's hostname is not one the server answers as (allowedHosts, port ignored —
// DNS rebinding sends Origin == Host == the attacker's name), or the screen is not a
// plain .html file name.
function record(screen, event, originHost, requestHost, allowedHosts) {
  if (!originHost || originHost !== requestHost) return false;
  const name = hostname(requestHost);
  if (!name || !(allowedHosts || []).some((h) => String(h).toLowerCase().replace(/^\[(.*)\]$/, '$1') === name)) return false;
  if (typeof screen !== 'string' || !/^[\w.-]+\.html$/.test(screen)) return false;
  const selected = Array.isArray(event.selected) ? event.selected.map(String) : [];
  const entry = { screen, selected, at: new Date().toISOString() };
  if (typeof event.text === 'string' && event.text.trim()) entry.text = event.text.trim();
  store.set(screen, entry);
  return true;
}

function clear(screen) { store.delete(screen); }

function get(screen) { return store.get(screen) || null; }

module.exports = { record, clear, get };
