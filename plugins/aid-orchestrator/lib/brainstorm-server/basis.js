// basis.js — the proposal basis a UI brainstorm's companion composes over
// (2.114.0). Dependency-free: `compose` and `load` run in plain node (the
// suite tests them without express); `routes` takes the express app.
//
// WHY: the PM kept receiving proposals drawn from memory — other buttons,
// other spacing, forbidden icons — because the rule "current state first" was
// prose in a long skill and the gate (aid-brainstorm-state.sh enter-phase
// design) was a command the agent had to call. A marker in the screen's HTML
// would prove nothing either. So the SERVER composes the page: left, the real
// screenshot of the application at its real width (proposal.json, basis
// live-screen); right, the agent's screen at the same width. The agent cannot
// leave the current state out. A design-system basis (no screen could be
// captured) shows its NO LIVE BASELINE banner with the reason instead.
'use strict';
const fs = require('fs');
const path = require('path');

// load(proposalPath) → {basis, marked, viewports: [{name, width, height, baseline}]} or null
function load(proposalPath) {
  if (!proposalPath) return null;
  const raw = JSON.parse(fs.readFileSync(proposalPath, 'utf-8'));
  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.viewports)) {
    throw new Error(`basis: ${proposalPath} is not a proposal (no viewports array)`);
  }
  if (raw.basis !== 'live-screen' && raw.basis !== 'design-system') {
    throw new Error(`basis: ${proposalPath} has basis '${raw.basis}', neither live-screen nor design-system`);
  }
  const viewports = raw.viewports.map(v => ({
    name: String(v.name), width: Number(v.width), height: Number(v.height),
    baseline: v.baseline ? path.resolve(path.dirname(proposalPath), String(v.baseline)) : null,
    // the page as rendered (ui-capture.mjs <target>.html): the agent's starting file
    page: v.page && fs.existsSync(path.resolve(path.dirname(proposalPath), String(v.page))) ? path.resolve(path.dirname(proposalPath), String(v.page)) : null,
  }));
  if (raw.basis === 'live-screen') {
    for (const v of viewports) {
      if (!v.baseline || !fs.existsSync(v.baseline) || fs.statSync(v.baseline).size === 0) {
        throw new Error(`basis: the ${v.name} viewport has no baseline capture — a live-screen basis without its screenshot`);
      }
    }
  }
  return { basis: raw.basis, marked: raw.marked ? String(raw.marked) : '', viewports, file: proposalPath };
}

// A viewport name is a path segment: letters, digits, dash, underscore only.
function safeName(name) { return /^[A-Za-z0-9_-]+$/.test(name); }

// routes(app, basis) — GET /basis/<viewport>/baseline.png serves the capture.
function routes(app, basis) {
  if (!basis) return;
  app.get('/basis/:vp/baseline.png', (req, res) => {
    const vp = req.params.vp;
    const v = safeName(vp) ? basis.viewports.find(x => x.name === vp) : null;
    if (!v || !v.baseline) return res.status(404).type('text').send('no baseline for this viewport');
    res.type('png').sendFile(v.baseline);
  });
  // GET /basis/<viewport>/page.html — the page as rendered, to copy and edit
  app.get('/basis/:vp/page.html', (req, res) => {
    const vp = req.params.vp;
    const v = safeName(vp) ? basis.viewports.find(x => x.name === vp) : null;
    if (!v || !v.page) return res.status(404).type('text').send('no rendered page for this viewport');
    res.type('html').sendFile(v.page);
  });
}

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

// compose(basis, screenUrl, {plan, project}) → the page at "/": today (the real capture) beside
// the proposal (the agent's screen in an iframe at the viewport's width), one
// tab per viewport the project owes. The agent's screen itself stays at
// screenUrl ("/screen"), untouched, so clicks, confirms and the reload socket
// work as before — inside the frame.
function compose(basis, screenUrl, meta) {
  const vps = basis.viewports;
  const first = vps[0];
  const label = meta && (meta.plan || meta.project) ? [meta.plan, meta.project].filter(Boolean).join(' · ') + ' — ' : '';
  const tabs = vps.length > 1
    ? `<nav class="vp-tabs">${vps.map((v, i) => `<button type="button" data-vp="${esc(v.name)}" data-w="${v.width}" class="${i === 0 ? 'on' : ''}">${esc(v.name)} ${v.width}×${v.height}</button>`).join('')}</nav>`
    : '';
  const banner = basis.basis === 'design-system'
    ? `<div class="basis-banner">${esc(basis.marked || 'NO LIVE BASELINE — this proposal is built from the application\'s design system, not from a screenshot of the running application.')}</div>`
    : '';
  const left = basis.basis === 'live-screen'
    ? `<section class="pane pane-today"><h2>Dnes (skutečný stav aplikace)</h2><img id="baseline" src="/basis/${esc(first.name)}/baseline.png" alt="skutečný stav aplikace, ${esc(first.name)}" style="width:${first.width}px;max-width:100%"></section>`
    : '';
  return `<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="utf-8">
<title>${esc(label)}dnes → návrh</title>
<style>
  body { margin: 0; font-family: system-ui, sans-serif; background: #f3f4f6; color: #111; }
  .vp-tabs { display: flex; gap: .5rem; padding: .5rem 1rem; background: #fff; border-bottom: 1px solid #ddd; }
  .vp-tabs button { border: 1px solid #ccc; background: #fafafa; padding: .25rem .75rem; border-radius: .25rem; cursor: pointer; }
  .vp-tabs button.on { background: #111; color: #fff; border-color: #111; }
  .basis-banner { background: #fde68a; color: #78350f; padding: .75rem 1rem; font-weight: 600; border-bottom: 1px solid #f59e0b; }
  .split { display: flex; gap: 1rem; padding: 1rem; align-items: flex-start; overflow-x: auto; }
  .pane { background: #fff; border: 1px solid #ddd; border-radius: .25rem; padding: .5rem; flex: 0 0 auto; }
  .pane h2 { margin: 0 0 .5rem; font-size: .9rem; color: #555; font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
  .pane img { display: block; border: 1px solid #eee; }
  .pane iframe { display: block; border: 1px solid #eee; background: #fff; }
</style>
</head>
<body data-basis="${esc(basis.basis)}">
${tabs}${banner}
<div class="split">
${left}
<section class="pane pane-proposal"><h2>Návrh (ve stejné šířce)</h2><iframe id="proposal" src="${esc(screenUrl)}" style="width:${first.width}px;height:${Math.max(first.height, 480)}px" title="návrh"></iframe></section>
</div>
<script>
  // viewport tabs: swap the baseline and resize the frame, nothing else
  document.querySelectorAll('.vp-tabs button').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.vp-tabs button').forEach(function (x) { x.classList.remove('on'); });
      b.classList.add('on');
      var w = b.getAttribute('data-w'), vp = b.getAttribute('data-vp');
      var img = document.getElementById('baseline'); if (img) { img.src = '/basis/' + encodeURIComponent(vp) + '/baseline.png'; img.style.width = w + 'px'; }
      var f = document.getElementById('proposal'); if (f) { f.style.width = w + 'px'; }
    });
  });
</script>
</body>
</html>`;
}

module.exports = { load, routes, compose };
