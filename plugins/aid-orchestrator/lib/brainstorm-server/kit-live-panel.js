// kit-live-panel.js — the AID panel over the live application (aid-companion.sh live). Inside a shadow root, so
// neither the app's styles nor the panel's leak. It reads /__aid/live.json (the agent's points and variants).
// 3.17.1 (PM 8. 11. 2026, the first live try on WAN): a variant switches WITHOUT reloading the app (3-5 s each time):
// window.AID_VARIANT, the aid_v_<port> cookie and ?v= are set, the address changes by history.pushState and a
// popstate event makes the app's router render again; an 'aid-variant' event goes to code that listens for it.
// One choice per point: "Vybrat" takes the variant on screen; the chosen one is marked apart from the one shown.
// The panel stays out of the way: a small tab when hidden, see-through until the pointer is over it.
(() => {
  if (window.__AID_LIVE_PANEL__) return; window.__AID_LIVE_PANEL__ = true;
  const host = document.createElement('div'); host.id = 'aid-live-panel';
  host.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:2147483647';
  const root = host.attachShadow({ mode: 'open' });
  document.body.appendChild(host);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = ev => fetch('/__aid/answer', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...ev, cesta: location.pathname + location.search, viewport: `${innerWidth}x${innerHeight}` }) }).then(r => r.ok, () => false);
  const store = (k, v) => { try { if (v === undefined) return JSON.parse(sessionStorage.getItem(k) || 'null'); sessionStorage.setItem(k, JSON.stringify(v)); } catch { return null; } };
  const chosen = store('aid_chosen') || {};
  let open = store('aid_panel_open'); if (open === null) open = true;

  function show(klic, cesta) {
    window.AID_VARIANT = klic;
    document.cookie = `aid_v_${location.port || (location.protocol === 'https:' ? 443 : 80)}=${klic}; Path=/; SameSite=Strict`;
    const u = new URL(cesta || location.pathname + location.search, location.origin);
    if (!cesta) { const cur = new URL(location.href); cur.searchParams.forEach((v, k) => { if (k !== 'v') u.searchParams.set(k, v); }); }
    u.searchParams.set('v', klic);
    history.pushState(history.state, '', u.pathname + u.search + u.hash);
    window.dispatchEvent(new PopStateEvent('popstate', { state: history.state }));   // the app's router renders again
    window.dispatchEvent(new CustomEvent('aid-variant', { detail: klic }));
    draw();
  }

  root.innerHTML = `<style>
    :host{all:initial} *{box-sizing:border-box;font:13px/1.4 system-ui,sans-serif;color:#1d1d1f}
    .wrap{opacity:.55;transition:opacity .15s} .wrap:hover,.wrap:focus-within{opacity:1}
    .box{width:min(320px,calc(100vw - 24px));max-height:60vh;overflow:auto;background:#fff;border:1px solid #c7c7cc;border-radius:12px;box-shadow:0 6px 22px rgba(0,0,0,.16);padding:10px 12px}
    .tab{background:#1d1d1f;color:#fff;border:0;border-radius:999px;padding:6px 12px;cursor:pointer;font-weight:600}
    .head{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:6px}
    .head b{font-size:13px} .bod{border-top:1px solid #e5e5ea;padding-top:8px;margin-top:8px}
    .q{font-weight:600;margin-bottom:6px} .seg{display:flex;gap:4px;flex-wrap:wrap;margin-bottom:6px}
    .seg button{border:1px solid #c7c7cc;background:#f5f5f7;border-radius:8px;padding:4px 10px;cursor:pointer}
    .seg button.on{background:#0a84ff;border-color:#0a84ff;color:#fff}
    .desc{color:#3a3a3c;margin-bottom:6px} .row{display:flex;gap:8px;align-items:center;justify-content:space-between;margin-bottom:6px}
    .pick{border:1px solid #34c759;background:#fff;color:#248a3d;border-radius:8px;padding:4px 10px;cursor:pointer;font-weight:600}
    .picked{color:#248a3d;font-weight:600} .none{color:#6e6e73}
    textarea{width:100%;min-height:40px;border:1px solid #c7c7cc;border-radius:8px;padding:6px;resize:vertical}
    .send{width:100%;margin-top:8px;background:#1d1d1f;color:#fff;border:0;border-radius:8px;padding:7px;font-weight:600;cursor:pointer}
    .x{border:0;background:none;cursor:pointer;color:#6e6e73} .st{font-size:12px;color:#6e6e73;margin-top:4px}
  </style><div class="wrap" id="w"></div>`;
  const w = root.getElementById('w');
  let body = [];

  function draw() {
    store('aid_panel_open', open);
    const cur = window.AID_VARIANT || null;
    if (!open) { w.innerHTML = `<button class="tab" id="t" title="Návrh AID">AID${cur ? ' · ' + esc(cur) : ''}</button>`; root.getElementById('t').onclick = () => { open = true; draw(); }; return; }
    w.innerHTML = `<div class="box"><div class="head"><b>Návrh AID</b><button class="x" id="min" title="Skrýt">skrýt ✕</button></div>
      ${body.map((b, i) => {
        const vs = b.varianty || [], shown = vs.find(v => v.klic === cur), pick = chosen[b.bod];
        return `<div class="bod"><div class="q">${esc(b.otazka)}</div>
          <div class="seg">${vs.map(v => `<button class="${v.klic === cur ? 'on' : ''}" data-i="${i}" data-k="${esc(v.klic)}" title="${esc(v.popis)}">${esc(v.klic)}</button>`).join('')}</div>
          <div class="desc">${shown ? 'Vidíš: <b>' + esc(shown.klic) + '</b> — ' + esc(shown.popis) : 'Vidíš dnešní stav. Přepni variantu nahoře.'}</div>
          <div class="row">${pick ? `<span class="picked">✓ vybráno: ${esc(pick)}</span>` : '<span class="none">zatím nevybráno</span>'}
            ${shown && pick !== shown.klic ? `<button class="pick" data-b="${esc(b.bod)}" data-k="${esc(shown.klic)}">Vybrat ${esc(shown.klic)}</button>` : ''}</div>
          <textarea data-b="${esc(b.bod)}" placeholder="Poznámka (uloží se sama)">${esc(store('aid_note_' + b.bod) || '')}</textarea></div>`;
      }).join('')}
      <button class="send" id="send">Odeslat volby</button><div id="st" class="st"></div></div>`;
    root.getElementById('min').onclick = () => { open = false; draw(); };
    root.querySelectorAll('.seg button').forEach(btn => btn.onclick = () => {
      const v = (body[+btn.dataset.i].varianty || []).find(x => x.klic === btn.dataset.k) || {};
      const sameScreen = !v.cesta || new URL(v.cesta, location.origin).pathname === location.pathname;
      show(btn.dataset.k, sameScreen ? null : v.cesta);
    });
    root.querySelectorAll('button.pick').forEach(btn => btn.onclick = async () => {
      if (await post({ type: 'choice', bod: btn.dataset.b, volba: btn.dataset.k })) { chosen[btn.dataset.b] = btn.dataset.k; store('aid_chosen', chosen); draw(); }
    });
    root.querySelectorAll('textarea').forEach(t => {
      t.oninput = () => store('aid_note_' + t.dataset.b, t.value);
      t.onblur = async () => {   // a note is never lost to a forgotten "Odeslat": it is sent when the PM leaves the field
        const v = t.value.trim(); if (!v || store('aid_note_sent_' + t.dataset.b) === v) return;
        if (await post({ type: 'note', bod: t.dataset.b, text: v })) store('aid_note_sent_' + t.dataset.b, v);
      };
    });
    root.getElementById('send').onclick = async () => {
      for (const t of root.querySelectorAll('textarea')) await t.onblur();
      const ok = await post({ type: 'confirm', selected: chosen });
      root.getElementById('st').textContent = ok ? 'Odesláno. Agent to uvidí.' : 'Nepodařilo se odeslat, zkus to znovu.';
    };
  }
  window.addEventListener('popstate', () => {   // back / forward in the browser: the variant follows the address
    const v = new URL(location.href).searchParams.get('v');
    if (v && v !== window.AID_VARIANT && body.some(b => (b.varianty || []).some(x => x.klic === v))) { window.AID_VARIANT = v; draw(); }
  });
  fetch('/__aid/live.json').then(r => r.json()).then(spec => { body = Array.isArray(spec.body) ? spec.body : []; draw(); })
    .catch(() => { w.innerHTML = '<div class="box">AID: návrh se nenačetl (live.json).</div>'; });
})();
