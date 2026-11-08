// kit-live-panel.js — the AID panel over the live application (aid-companion.sh live, 3.17.0). Inside a shadow
// root, so neither the app's styles nor the panel's leak. It reads /__aid/live.json (the agent's points and variants),
// switches a variant by opening its path with ?v=<klic>, and posts choice / note / confirm to /__aid/answer.
(() => {
  if (window.__AID_LIVE_PANEL__) return; window.__AID_LIVE_PANEL__ = true;
  const host = document.createElement('div'); host.id = 'aid-live-panel';
  host.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647';
  const root = host.attachShadow({ mode: 'open' });
  document.body.appendChild(host);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = ev => fetch('/__aid/answer', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...ev, cesta: location.pathname + location.search, viewport: `${innerWidth}x${innerHeight}` }) }).then(r => r.ok);
  const cur = window.AID_VARIANT || null;
  const open = sessionStorage.getItem('aid_panel_open') !== '0';
  const chosen = JSON.parse(sessionStorage.getItem('aid_chosen') || '{}');
  root.innerHTML = `<style>
    :host{all:initial} *{box-sizing:border-box;font:13px/1.4 system-ui,sans-serif;color:#1d1d1f}
    .box{width:min(340px,calc(100vw - 32px));max-height:70vh;overflow:auto;background:#fff;border:1px solid #c7c7cc;border-radius:12px;box-shadow:0 8px 28px rgba(0,0,0,.18);padding:12px}
    .tab{background:#1d1d1f;color:#fff;border:0;border-radius:999px;padding:8px 14px;cursor:pointer;font-weight:600}
    h3{margin:0 0 8px;font-weight:700;font-size:14px} .bod{border-top:1px solid #e5e5ea;padding-top:8px;margin-top:8px}
    .q{font-weight:600;margin-bottom:6px} .row{display:flex;gap:6px;align-items:center;margin:4px 0;flex-wrap:wrap}
    button{border:1px solid #c7c7cc;background:#f5f5f7;border-radius:8px;padding:4px 8px;cursor:pointer}
    button.on{background:#0a84ff;border-color:#0a84ff;color:#fff} button.pick{background:#fff}
    button.picked{background:#34c759;border-color:#34c759;color:#fff}
    textarea{width:100%;min-height:44px;border:1px solid #c7c7cc;border-radius:8px;padding:6px;resize:vertical}
    .send{width:100%;margin-top:10px;background:#1d1d1f;color:#fff;border:0;padding:8px;font-weight:600}
    .muted{color:#6e6e73;font-size:12px} .ok{color:#248a3d}
  </style><div id="w"></div>`;
  const w = root.getElementById('w');
  fetch('/__aid/live.json').then(r => r.json()).then(spec => {
    const body = Array.isArray(spec.body) ? spec.body : [];
    const draw = isOpen => {
      sessionStorage.setItem('aid_panel_open', isOpen ? '1' : '0');
      if (!isOpen) { w.innerHTML = `<button class="tab" id="t">AID návrh${cur ? ' · ' + esc(cur) : ''}</button>`; root.getElementById('t').onclick = () => draw(true); return; }
      w.innerHTML = `<div class="box"><div class="row" style="justify-content:space-between"><h3>Návrh${spec.kolo ? ' · kolo ' + esc(spec.kolo) : ''}</h3><button id="min">skrýt</button></div>
        <div class="muted">Prohlížíš živou aplikaci${cur ? ', varianta <b>' + esc(cur) + '</b>' : ''}. Přepni variantu, vyber, napiš poznámku, pak odešli.</div>
        ${body.map((b, i) => `<div class="bod"><div class="q">${esc(b.bod)}. ${esc(b.otazka)}</div>
          ${(b.varianty || []).map(v => `<div class="row"><button class="go${v.klic === cur ? ' on' : ''}" data-i="${i}" data-k="${esc(v.klic)}">${esc(v.klic)}</button>
            <span>${esc(v.popis)}</span><button class="pick${chosen[b.bod] === v.klic ? ' picked' : ''}" data-b="${esc(b.bod)}" data-k="${esc(v.klic)}">${chosen[b.bod] === v.klic ? 'vybráno' : 'vybrat'}</button></div>`).join('')}
          <textarea data-b="${esc(b.bod)}" placeholder="Poznámka k bodu ${esc(b.bod)}"></textarea></div>`).join('')}
        <button class="send" id="send">Odeslat volby</button><div id="st" class="muted"></div></div>`;
      root.getElementById('min').onclick = () => draw(false);
      root.querySelectorAll('button.go').forEach(btn => btn.onclick = () => {
        const v = (body[+btn.dataset.i].varianty || []).find(x => x.klic === btn.dataset.k) || {};
        const u = new URL(v.cesta || location.pathname, location.origin); u.searchParams.set('v', btn.dataset.k); location.href = u.pathname + u.search;
      });
      root.querySelectorAll('button.pick').forEach(btn => btn.onclick = async () => {
        if (await post({ type: 'choice', bod: btn.dataset.b, volba: btn.dataset.k })) { chosen[btn.dataset.b] = btn.dataset.k; sessionStorage.setItem('aid_chosen', JSON.stringify(chosen)); draw(true); }
      });
      root.getElementById('send').onclick = async () => {
        for (const t of root.querySelectorAll('textarea')) if (t.value.trim()) await post({ type: 'note', bod: t.dataset.b, text: t.value.trim() });
        const ok = await post({ type: 'confirm', volby: chosen });
        root.getElementById('st').innerHTML = ok ? '<span class="ok">Odesláno. Agent to uvidí.</span>' : 'Nepodařilo se odeslat — zkus to znovu.';
      };
    };
    draw(open);
  }).catch(() => { w.innerHTML = '<div class="box muted">AID: návrh se nenačetl (live.json).</div>'; });
})();
