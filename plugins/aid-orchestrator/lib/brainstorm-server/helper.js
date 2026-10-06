(function() {
  const WS_URL = 'ws://' + window.location.host;
  let ws = null;
  let eventQueue = [];

  function connect() {
    ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      eventQueue.forEach(e => ws.send(JSON.stringify(e)));
      eventQueue = [];
    };

    ws.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      if (data.type === 'reload') {
        window.location.reload();
      }
    };

    ws.onclose = () => {
      setTimeout(connect, 1000);
    };
  }

  function sendEvent(event) {
    event.timestamp = Date.now();
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(event));
    } else {
      eventQueue.push(event);
    }
  }

  // "Držet" (2.114.0): a small fixed button on every screen; the PM decides
  // whether this companion survives the idle shutdown (12 h without a browser
  // and without a new screen). Kept or not, it ends 60 days after it started;
  // the screens stay on disk.
  function keepButton() {
    if (window.top !== window.self && window.parent.document.getElementById('aid-keep')) return;   // one button per page, in the frame's parent when composed
    var b = document.createElement('button');
    b.id = 'aid-keep'; b.type = 'button';
    b.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:99999;padding:6px 12px;border-radius:6px;border:1px solid #999;background:#fff;color:#111;font:13px system-ui,sans-serif;cursor:pointer;opacity:.9';
    function render(kept) { b.textContent = kept ? 'Držím (zruš podržení)' : 'Držet (nevypínat po 12 h)'; b.style.background = kept ? '#fde68a' : '#fff'; b.dataset.kept = kept ? '1' : '0'; }
    fetch('/aid/keep').then(function (r) { return r.json(); }).then(function (j) { render(!!j.kept); }).catch(function () { render(false); });
    b.addEventListener('click', function () {
      fetch('/aid/keep', { method: 'POST' }).then(function (r) { return r.json(); }).then(function (j) { render(!!j.kept); });
    });
    (document.body || document.documentElement).appendChild(b);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', keepButton); else keepButton();

  // A data-confirm button sends the current selection (and the optional
  // data-confirm-text field, e.g. the PM's own slogan) as the PM's answer.
  document.addEventListener('click', (e) => {
    const button = e.target.closest('[data-confirm]');
    if (!button) return;
    const selected = Array.from(document.querySelectorAll('[data-choice].selected')).map(el => el.dataset.choice);
    const field = document.querySelector('[data-confirm-text]');
    const text = field ? field.value.trim() : '';
    sendEvent(Object.assign({ type: 'confirm', screen: window.AID_SCREEN || '', selected }, text ? { text } : {}));
    const indicator = document.getElementById('indicator-text');
    if (indicator) indicator.textContent = 'Potvrzeno (' + selected.length + ') - vrať se do terminálu';
  });

  // Capture clicks on choice elements
  document.addEventListener('click', (e) => {
    const target = e.target.closest('[data-choice]');
    if (!target) return;

    sendEvent({
      type: 'click',
      text: target.textContent.trim(),
      choice: target.dataset.choice,
      id: target.id || null
    });

    // Update indicator bar (defer so toggleSelect runs first)
    setTimeout(() => {
      const indicator = document.getElementById('indicator-text');
      if (!indicator) return;
      const container = target.closest('.options') || target.closest('.cards');
      const selected = container ? container.querySelectorAll('.selected') : [];
      if (selected.length === 0) {
        indicator.textContent = 'Click an option above, then return to the terminal';
      } else if (selected.length === 1) {
        const label = selected[0].querySelector('h3, .content h3, .card-body h3')?.textContent?.trim() || selected[0].dataset.choice;
        indicator.innerHTML = '<span class="selected-text">' + label + ' selected</span> — return to terminal to continue';
      } else {
        indicator.innerHTML = '<span class="selected-text">' + selected.length + ' selected</span> — return to terminal to continue';
      }
    }, 0);
  });

  // Frame UI: selection tracking
  window.selectedChoice = null;

  window.toggleSelect = function(el) {
    const container = el.closest('.options') || el.closest('.cards');
    const multi = container && container.dataset.multiselect !== undefined;
    if (container && !multi) {
      container.querySelectorAll('.option, .card').forEach(o => o.classList.remove('selected'));
    }
    if (multi) {
      el.classList.toggle('selected');
    } else {
      el.classList.add('selected');
    }
    window.selectedChoice = el.dataset.choice;
  };

  // Expose API for explicit use
  window.brainstorm = {
    send: sendEvent,
    choice: (value, metadata = {}) => sendEvent({ type: 'choice', value, ...metadata })
  };

  connect();
})();
