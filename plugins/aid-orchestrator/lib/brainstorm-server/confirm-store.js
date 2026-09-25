// Confirms of companion screens, one per screen file, kept only in the server's
// memory. aid-ui-state.sh await-choice reads them through GET /aid/confirmed, so a
// PM choice never comes from a file the agent could write. No dependencies.
// ponytail: lost on a server restart; the PM confirms again (the round stays open).
const store = new Map();

// record(screen, event, originHost, requestHost) — false when refused: the page's
// Origin host differs from the request's Host (another site's page), or the screen
// is not a plain .html file name.
function record(screen, event, originHost, requestHost) {
  if (!originHost || originHost !== requestHost) return false;
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
