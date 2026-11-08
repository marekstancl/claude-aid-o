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
    .tools{display:flex;gap:6px;margin-bottom:6px} .tools button{border:1px solid #c7c7cc;background:#f5f5f7;border-radius:8px;padding:4px 8px;cursor:pointer}
    .tools button.on{background:#ff9f0a;border-color:#ff9f0a;color:#fff}
    .marks{border-top:1px solid #e5e5ea;margin-top:8px;padding-top:6px} .mk{display:flex;gap:6px;align-items:flex-start;margin:3px 0}
    .mk .n{background:#ff9f0a;color:#fff;border-radius:999px;min-width:18px;height:18px;text-align:center;font-size:11px;line-height:18px;font-weight:700}
    .mk .t{flex:1;white-space:pre-wrap;word-break:break-word} .mk .gone{color:#6e6e73;font-style:italic}
    #layer{position:fixed;inset:0;pointer-events:none}
    .pin{position:fixed;transform:translate(-50%,-50%);background:#ff9f0a;color:#fff;border:2px solid #fff;border-radius:999px;min-width:22px;height:22px;font-size:12px;font-weight:700;line-height:18px;text-align:center;box-shadow:0 2px 6px rgba(0,0,0,.3);pointer-events:auto;cursor:default}
    .area{position:fixed;border:2px solid #ff9f0a;background:rgba(255,159,10,.12);border-radius:4px;pointer-events:none}
    .hl{position:fixed;outline:2px solid rgba(10,132,255,.9);outline-offset:1px;background:rgba(10,132,255,.07);border-radius:3px;pointer-events:none;transition:all .06s}
    .hl span{position:absolute;left:-2px;top:-20px;background:#0a84ff;color:#fff;font-size:11px;line-height:16px;padding:1px 6px;border-radius:4px;white-space:nowrap}
    .drag{position:fixed;border:2px dashed #ff9f0a;background:rgba(255,159,10,.1);pointer-events:none}
    .bubble{position:fixed;width:min(280px,calc(100vw - 24px));background:#fff;border:1px solid #c7c7cc;border-radius:10px;box-shadow:0 8px 24px rgba(0,0,0,.2);padding:8px;pointer-events:auto}
    .bubble .row{margin:6px 0 0;justify-content:flex-end}
    .save{border:1px solid #34c759;background:#34c759;color:#fff;border-radius:8px;padding:4px 10px;cursor:pointer;font-weight:600}
  </style><div class="wrap" id="w"></div><div id="layer"></div>`;
  const w = root.getElementById('w');
  let body = [];

  function draw() {
    store('aid_panel_open', open);
    const cur = window.AID_VARIANT || null;
    if (!open) { w.innerHTML = `<button class="tab" id="t" title="Návrh AID">AID${cur ? ' · ' + esc(cur) : ''}</button>`; root.getElementById('t').onclick = () => { open = true; draw(); }; return; }
    w.innerHTML = `<div class="box"><div class="head"><b>Návrh AID</b><button class="x" id="min" title="Skrýt">skrýt ✕</button></div>
      <div class="tools"><button id="kom" class="${commenting ? 'on' : ''}">${commenting ? 'Komentuji… (Esc)' : 'Komentovat'}</button>
        <button id="vis">${showMarks ? 'Skrýt značky' : 'Ukázat značky'}</button></div>
      ${body.map((b, i) => {
        const vs = b.varianty || [], shown = vs.find(v => v.klic === cur), pick = chosen[b.bod];
        return `<div class="bod"><div class="q">${esc(b.otazka)}</div>
          <div class="seg">${vs.map(v => `<button class="${v.klic === cur ? 'on' : ''}" data-i="${i}" data-k="${esc(v.klic)}" title="${esc(v.popis)}">${esc(v.klic)}</button>`).join('')}</div>
          <div class="desc">${shown ? 'Vidíš: <b>' + esc(shown.klic) + '</b> — ' + esc(shown.popis) : 'Vidíš dnešní stav. Přepni variantu nahoře.'}</div>
          <div class="row">${pick ? `<span class="picked">✓ vybráno: ${esc(pick)}</span>` : '<span class="none">zatím nevybráno</span>'}
            ${shown && pick !== shown.klic ? `<button class="pick" data-b="${esc(b.bod)}" data-k="${esc(shown.klic)}">Vybrat ${esc(shown.klic)}</button>` : ''}</div>
          <textarea data-b="${esc(b.bod)}" placeholder="Poznámka (uloží se sama)">${esc(store('aid_note_' + b.bod) || '')}</textarea></div>`;
      }).join('')}
      <div class="marks" id="mlist"></div>
      <button class="send" id="send">Odeslat volby</button><div id="st" class="st"></div></div>`;
    root.getElementById('min').onclick = () => { open = false; draw(); };
    root.getElementById('kom').onclick = () => setCommenting(!commenting);
    root.getElementById('vis').onclick = () => { showMarks = !showMarks; store('aid_marks_show', showMarks); place(); draw(); };
    drawMarks();
    root.querySelectorAll('.seg button').forEach(btn => btn.onclick = () => {
      const v = (body[+btn.dataset.i].varianty || []).find(x => x.klic === btn.dataset.k) || {};
      const sameScreen = !v.cesta || new URL(v.cesta, location.origin).pathname === location.pathname;
      show(btn.dataset.k, sameScreen ? null : v.cesta);
    });
    w.querySelectorAll('button.pick').forEach(btn => btn.onclick = async () => {
      if (await post({ type: 'choice', bod: btn.dataset.b, volba: btn.dataset.k })) { chosen[btn.dataset.b] = btn.dataset.k; store('aid_chosen', chosen); draw(); }
    });
    w.querySelectorAll('textarea').forEach(t => {   // the panel's notes only, never the mark bubble in the layer
      t.oninput = () => store('aid_note_' + t.dataset.b, t.value);
      t.onblur = async () => {   // a note is never lost to a forgotten "Odeslat": it is sent when the PM leaves the field
        const v = t.value.trim(); if (!v || store('aid_note_sent_' + t.dataset.b) === v) return;
        if (await post({ type: 'note', bod: t.dataset.b, text: v })) store('aid_note_sent_' + t.dataset.b, v);
      };
    });
    root.getElementById('send').onclick = async () => {
      for (const t of w.querySelectorAll('textarea')) await t.onblur();
      const ok = await post({ type: 'confirm', selected: chosen });
      root.getElementById('st').textContent = ok ? 'Odesláno. Agent to uvidí.' : 'Nepodařilo se odeslat, zkus to znovu.';
    };
  }
  window.addEventListener('popstate', () => {   // back / forward in the browser: the variant follows the address
    const v = new URL(location.href).searchParams.get('v');
    if (v && v !== window.AID_VARIANT && body.some(b => (b.varianty || []).some(x => x.klic === v))) { window.AID_VARIANT = v; draw(); }
  });
  // ── 3.18.0 marks: the PM points at an element (click) or an area (mouse drag) and writes a note ──────────────
  const layer = root.getElementById('layer');
  // pins are redrawn every frame in their own box; the highlight, the drag frame and the note bubble are single nodes
  // shown and hidden (a node rebuilt each frame would steal the bubble's focus and pile up on every mouse move)
  const pins = document.createElement('div'), hlNode = document.createElement('div'), dragNode = document.createElement('div');
  hlNode.className = 'hl'; dragNode.className = 'drag'; hlNode.hidden = dragNode.hidden = true;
  layer.append(pins, hlNode, dragNode);
  let marks = [], showMarks = store('aid_marks_show') !== false, commenting = false, drag = null, bubble = null;
  const ours = e => e.composedPath().includes(host);
  const VAL = /^[A-Za-z][A-Za-z_-]{0,60}$/;   // no digits: an id like row-12345 carries a record, mui-17 changes on reload
  const sel = el => {   // an id, a data-testid or an aria-label anchors the path; nth-of-type below it; no data values
    const parts = [];
    for (let n = el; n && n.nodeType === 1 && n !== document.documentElement; n = n.parentElement) {
      if (n.id && VAL.test(n.id)) { parts.unshift('#' + CSS.escape(n.id)); break; }
      const t = n.getAttribute('data-testid'); if (t && VAL.test(t)) { parts.unshift(`[data-testid="${CSS.escape(t)}"]`); break; }
      let i = 1; for (let p = n.previousElementSibling; p; p = p.previousElementSibling) if (p.tagName === n.tagName) i++;
      parts.unshift(`${n.tagName.toLowerCase()}:nth-of-type(${i})`);
      if (n === document.body) { parts[0] = 'body'; break; }
    }
    return parts.join(' > ');   // from an anchor or from body: never a path that could match elsewhere
  };
  const prvekOf = el => {
    let label = el.getAttribute('aria-label') || null;
    if (!label && el.id) { const l = document.querySelector(`label[for="${CSS.escape(el.id)}"]`); if (l) label = l.textContent.trim(); }
    return { tag: el.tagName.toLowerCase(), role: el.getAttribute('role'), label: label && label.slice(0, 120), placeholder: el.getAttribute('placeholder') };
  };
  const at = (d, r) => { Object.assign(d.style, { left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' }); return d; };
  const box = (cls, r) => { const d = document.createElement('div'); d.className = cls; return at(d, r); };
  const closeBubble = () => { if (bubble) bubble.node.remove(); bubble = null; };
  const pct = (v, a, b) => Math.max(0, Math.min(100, b ? ((v - a) / b) * 100 : 0));

  // placement on demand (scroll anywhere, resize, DOM change, a new list) in one frame; nodes reused; all geometry
  // read first, then written (one layout per frame, not one per mark)
  const nodes = new Map();
  let queued = false;
  const schedule = () => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; place(); }); } };
  function place() {
    const want = showMarks ? marks : [];
    for (const [id, n] of nodes) if (!want.some(m => m.id === id)) { n.pin.remove(); if (n.area) n.area.remove(); nodes.delete(id); }
    const geo = want.map(m => { let el = null; try { el = document.querySelector(m.kotva.selector); } catch {} return el ? el.getBoundingClientRect() : null; });
    let goneChanged = false;
    want.forEach((m, i) => {
      const r = geo[i], gone = !r; if (gone !== !!m.gone) { m.gone = gone; goneChanged = true; }
      let n = nodes.get(m.id);
      if (!n) { n = { pin: document.createElement('div'), area: m.druh === 'oblast' ? document.createElement('div') : null };
        n.pin.className = 'pin'; n.pin.title = m.text; if (n.area) { n.area.className = 'area'; pins.appendChild(n.area); } pins.appendChild(n.pin); nodes.set(m.id, n); }
      n.pin.textContent = String(i + 1); n.pin.hidden = gone; if (n.area) n.area.hidden = gone;
      if (gone) return;
      const x = r.left + r.width * m.kotva.x / 100, y = r.top + r.height * m.kotva.y / 100;
      Object.assign(n.pin.style, { left: x + 'px', top: y + 'px' });
      if (n.area) at(n.area, { left: x, top: y, width: r.width * m.kotva.w / 100, height: r.height * m.kotva.h / 100 });
    });
    if (goneChanged) drawMarks();
  }
  window.addEventListener('scroll', schedule, true); window.addEventListener('resize', schedule);
  new MutationObserver(m => { if (marks.length && showMarks && m.some(x => !host.contains(x.target))) schedule(); })
    .observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style', 'hidden'] });

  let loadSeq = 0;
  async function loadMarks() {   // only the latest answer counts: a fast switch of screens must not draw another's marks
    const seq = ++loadSeq; let got;
    try { got = await (await fetch(`/__aid/marks?p=${encodeURIComponent(location.pathname)}&v=${encodeURIComponent(window.AID_VARIANT || '')}`)).json(); } catch { got = []; }
    if (seq !== loadSeq) return;
    marks = Array.isArray(got) ? got : []; place(); drawMarks();
  }
  function drawMarks() {
    const host2 = root.getElementById('mlist'); if (!host2) return;
    host2.replaceChildren();
    const head = document.createElement('div'); head.className = 'q'; head.textContent = `Značky na této obrazovce (${marks.length})`; host2.appendChild(head);
    marks.forEach((m, i) => {
      const row = document.createElement('div'); row.className = 'mk';
      const n = document.createElement('span'); n.className = 'n'; n.textContent = String(i + 1);
      const t = document.createElement('span'); t.className = 't'; t.textContent = m.text;   // the PM's words, as text only
      if (m.gone) { const g = document.createElement('div'); g.className = 'gone'; g.textContent = 'prvek už na stránce není'; t.appendChild(g); }
      const x = document.createElement('button'); x.className = 'x'; x.textContent = '×'; x.title = 'Smazat značku';
      x.onclick = async () => { if (await post({ type: 'mark', smazano: true, id: m.id })) loadMarks(); };
      row.append(n, t, x); host2.appendChild(row);
    });
  }

  function ask(druh, el, kotva, rect, at) {   // the note bubble next to the point
    const node = document.createElement('div'); node.className = 'bubble';
    Object.assign(node.style, { left: Math.min(at.x + 12, innerWidth - 300) + 'px', top: Math.min(at.y + 12, innerHeight - 140) + 'px' });
    const ta = document.createElement('textarea'); ta.placeholder = druh === 'bod' ? 'Co tady?' : 'Co s touto oblastí?';
    const row = document.createElement('div'); row.className = 'row';
    const ok = document.createElement('button'); ok.className = 'save'; ok.textContent = 'Uložit';   // not .pick: draw() binds every .pick to a choice
    const no = document.createElement('button'); no.className = 'x'; no.textContent = 'Zrušit';
    row.append(no, ok); node.append(ta, row);
    closeBubble(); hlNode.hidden = true; bubble = { node }; layer.appendChild(node); ta.focus();
    no.onclick = closeBubble;
    ok.onclick = async () => {
      const text = ta.value.trim(); if (!text) return ta.focus();
      const r = await fetch('/__aid/answer', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({
        type: 'mark', druh, text, varianta: window.AID_VARIANT || null, cesta_path: location.pathname, kotva, rect, prvek: prvekOf(el),
        cesta: location.pathname + location.search, viewport: `${innerWidth}x${innerHeight}` }) });
      if (r.ok) { closeBubble(); await loadMarks(); } else { ok.textContent = 'Nepovedlo se — znovu'; }
    };
  }
  // 3.18.0 (PM: "the picking is twitchy"): not the deepest node under the pointer but the nearest thing one talks about
  // (a button, a field, a cell, a row, a heading, an image, a card); icons, bits of text and tiny wrappers are skipped.
  // The wheel climbs to the enclosing whole and back (`up` levels above that element).
  const KIND = [['button,[role=button]', 'tlačítko'], ['a[href]', 'odkaz'], ['input,select,textarea,[contenteditable=true]', 'pole'],
    ['label', 'popisek'], ['th,td,[role=cell],[role=gridcell]', 'buňka'], ['tr,[role=row]', 'řádek'], ['li,[role=listitem]', 'položka seznamu'],
    ['h1,h2,h3,h4,h5,h6', 'nadpis'], ['img,picture,video,canvas', 'obrázek'], ['table,[role=table],[role=grid]', 'tabulka'],
    ['nav', 'navigace'], ['header', 'hlavička'], ['form', 'formulář'], ['dialog,[role=dialog]', 'okno'], ['section,article,aside', 'oddíl'], ['p', 'odstavec']];
  const kindOf = el => { for (const [q, n] of KIND) if (el.matches(q)) return n; return null; };
  const card = el => { const cs = getComputedStyle(el), r = el.getBoundingClientRect();   // a box with its own frame reads as a card
    return r.width >= 120 && r.height >= 40 && (parseFloat(cs.borderTopWidth) > 0 || cs.boxShadow !== 'none' || (cs.backgroundColor !== 'rgba(0, 0, 0, 0)' && cs.backgroundColor !== getComputedStyle(el.parentElement || el).backgroundColor)); };
  const meaningful = el => {
    for (let n = el; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
      const r = n.getBoundingClientRect();
      if (r.width < 16 || r.height < 12) continue;
      if (kindOf(n) || card(n)) return n;
    }
    return el;
  };
  let up = 0, lastBase = null;
  const lift = el => { let n = el; for (let i = 0; i < up && n.parentElement && n.parentElement !== document.body; i++) { n = n.parentElement; while (n.parentElement && n.parentElement !== document.body && !(kindOf(n) || card(n))) n = n.parentElement; } return n; };
  const target = e => { const raw = document.elementFromPoint(e.clientX, e.clientY); if (!raw || raw === host) return null;
    const base = meaningful(raw); if (base !== lastBase) { lastBase = base; up = 0; } return lift(base); };
  const label = el => kindOf(el) || (card(el) ? 'karta' : el.tagName.toLowerCase());
  const swallow = e => { if (!commenting || ours(e)) return; e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };
  const handlers = {
    pointermove: e => { if (ours(e)) return; const el = target(e); if (drag && e.pointerType === 'mouse') {
        const x = Math.min(drag.x, e.clientX), y = Math.min(drag.y, e.clientY), w = Math.abs(e.clientX - drag.x), h = Math.abs(e.clientY - drag.y);
        dragNode.hidden = !(w > 8 || h > 8); at(dragNode, { left: x, top: y, width: w, height: h }); }
      hlNode.hidden = !el || !!bubble; if (el && !bubble) { at(hlNode, el.getBoundingClientRect());
        if (!hlNode.firstChild) hlNode.appendChild(document.createElement('span')); hlNode.firstChild.textContent = label(el) + (up ? ' (o ' + up + ' výš)' : ''); } },
    wheel: e => { if (ours(e) || bubble) return; e.preventDefault(); e.stopImmediatePropagation(); up = Math.max(0, up + (e.deltaY < 0 ? 1 : -1));
      const el = target(e); hlNode.hidden = !el; if (el) { at(hlNode, el.getBoundingClientRect()); hlNode.firstChild && (hlNode.firstChild.textContent = label(el) + (up ? ' (o ' + up + ' výš)' : '')); } },
    pointerdown: e => { swallow(e); if (ours(e) || bubble || e.button !== 0) return; drag = { x: e.clientX, y: e.clientY }; },
    pointerup: e => { swallow(e); if (ours(e) || !drag || bubble) return; const d = drag; drag = null; dragNode.hidden = true;
      const x0 = Math.min(d.x, e.clientX), y0 = Math.min(d.y, e.clientY), w = Math.abs(e.clientX - d.x), h = Math.abs(e.clientY - d.y);
      const sx = scrollX, sy = scrollY;
      if (e.pointerType === 'mouse' && (w > 8 || h > 8)) {   // an area: anchored to the element at its centre
        let el = document.elementFromPoint(x0 + w / 2, y0 + h / 2); if (!el || el === host) return;
        const inside = n => { const q = n.getBoundingClientRect(); return q.left <= x0 && q.top <= y0 && q.right >= x0 + w && q.bottom >= y0 + h; };
        while (el.parentElement && el !== document.body && !inside(el)) el = el.parentElement;   // the smallest element holding the whole area
        const r = el.getBoundingClientRect();
        ask('oblast', el, { selector: sel(el), x: pct(x0, r.left, r.width), y: pct(y0, r.top, r.height), w: pct(x0 + w, x0, r.width), h: pct(y0 + h, y0, r.height) },
            { x: Math.round(x0 + sx), y: Math.round(y0 + sy), w: Math.round(w), h: Math.round(h) }, { x: e.clientX, y: e.clientY });
      } else {   // a point (a click, or a tap)
        const el = target(e); if (!el) return; const r = el.getBoundingClientRect();
        ask('bod', el, { selector: sel(el), x: pct(e.clientX, r.left, r.width), y: pct(e.clientY, r.top, r.height) },
            { x: Math.round(e.clientX + sx), y: Math.round(e.clientY + sy), w: 0, h: 0 }, { x: e.clientX, y: e.clientY });
      } },
    mousedown: swallow, mouseup: swallow, click: swallow, dblclick: swallow, contextmenu: swallow, dragstart: swallow, selectstart: swallow,
    pointercancel: () => { drag = null; dragNode.hidden = true; },
    // Esc leaves the mode wherever the focus is (the note bubble too) and never reaches the app (a dialog stays open)
    keydown: e => { if (commenting && e.key === 'Escape') { e.preventDefault(); e.stopImmediatePropagation(); setCommenting(false); } }
  };
  function setCommenting(on) {   // outside the mode no listener and no layer catches anything of the app
    commenting = on; drag = null; hlNode.hidden = dragNode.hidden = true; if (!on) closeBubble();
    // passive: false — the wheel climbs levels in the mode instead of scrolling the page
    for (const [k, f] of Object.entries(handlers)) on ? window.addEventListener(k, f, { capture: true, passive: false }) : window.removeEventListener(k, f, { capture: true });
    document.documentElement.style.cursor = on ? 'crosshair' : '';
    place(); draw();
  }
  const reloadOnMove = (() => { let last = location.pathname + '|' + (window.AID_VARIANT || ''); return () => {
    const now = location.pathname + '|' + (window.AID_VARIANT || ''); if (now !== last) { last = now; loadMarks(); } }; })();
  for (const f of ['pushState', 'replaceState']) { const o = history[f]; history[f] = function (...a) { const r = o.apply(this, a); setTimeout(reloadOnMove); return r; }; }
  window.addEventListener('popstate', () => setTimeout(reloadOnMove));
  window.addEventListener('aid-variant', () => setTimeout(reloadOnMove));
  window.__AID_MARKS__ = { setCommenting, loadMarks, get marks() { return marks; } };   // for the kit's own browser test

  fetch('/__aid/live.json').then(r => r.json()).then(spec => { body = Array.isArray(spec.body) ? spec.body : []; draw(); loadMarks(); })
    .catch(() => { w.innerHTML = '<div class="box">AID: návrh se nenačetl (live.json).</div>'; });
})();
