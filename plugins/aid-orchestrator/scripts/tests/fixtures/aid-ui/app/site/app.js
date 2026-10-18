// Fixture app of P116 (aid-ui-verify app-gate): a small note app BUILT from docs/design/screens.json - its own markup,
// keeping the contract of the build: data-aid-screen, data-aid-action, data-aid-confirm-yes, and in test mode
// (?aid-test=1) ?stav=<state>. Notes live in localStorage; a fresh browser gets one sample note. Lines marked
// "aid-break:" are what the failing cases of test-aid-ui-verify.bats change, one thing each.
(function () {
  var q = new URLSearchParams(location.search), test = q.get('aid-test') === '1';
  var notes = JSON.parse(localStorage.getItem('poznamky') || 'null') || [{ id: 1, nazev: 'Ukázková poznámka' }];
  var save = function () { localStorage.setItem('poznamky', JSON.stringify(notes)); };
  var main = document.querySelector('[data-aid-screen]'), screen = main.dataset.aidScreen;
  var show = function (st) { main.querySelectorAll('[data-aid-state]').forEach(function (e) { e.hidden = e.dataset.aidState !== st; }); };
  var want = test && q.get('stav');
  show(want || (screen === 'seznam' && !notes.length ? 'empty' : 'filled'));
  if (screen === 'seznam') {
    var ul = main.querySelector('[data-list]');
    notes.forEach(function (n, i) {
      var li = document.createElement('li'), a = document.createElement('a');
      a.href = '/detail/?id=' + n.id; a.textContent = 'Otevřít: ' + n.nazev;
      if (i === 0) a.setAttribute('data-aid-action', 'seznam.otevrit');
      li.appendChild(a); ul.appendChild(li);
    });
    if (q.get('smazano')) main.querySelector('[data-zprava]').textContent = 'Poznámka smazána';
  }
  if (screen === 'formular') {
    var form = main.querySelector('form'), err = main.querySelector('[data-aid-error]'), val = main.querySelector('[data-validace]');
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      var nazev = form.nazev.value.trim();
      if (!nazev) { val.hidden = false; form.nazev.focus(); return; }
      var b = ev.submitter; if (b) b.disabled = true; form.setAttribute('aria-busy', 'true');
      fetch('/api/ulozit.json', { cache: 'no-store' }).then(function (r) {
        if (!r.ok) throw new Error(r.status);
        var id = Date.now(); notes.push({ id: id, nazev: nazev }); save();
        location.href = '/detail/?id=' + id;
      }).catch(function () {
        if (b) b.disabled = false; form.removeAttribute('aria-busy');
        /* aid-break: lost-input */
        err.hidden = false; err.focus();
      });
    });
  }
  if (screen === 'detail') {
    var id = Number(q.get('id')), n = notes.find(function (x) { return x.id === id; }) || notes[notes.length - 1];
    main.querySelector('[data-nazev]').textContent = n ? n.nazev : ''; // aid-break: result
    var d = main.querySelector('dialog'), del = main.querySelector('[data-aid-action="detail.smazat"]');
    del.addEventListener('click', function () { d.showModal(); });
    d.querySelector('[data-ne]').addEventListener('click', function () { d.close(); del.focus(); });
    d.querySelector('[data-aid-confirm-yes]').addEventListener('click', function () {
      fetch('/api/smazat.json', { cache: 'no-store' }).then(function (r) {
        if (!r.ok) throw new Error(r.status);
        notes = notes.filter(function (x) { return !n || x.id !== n.id; }); save();
        location.href = '/seznam/?smazano=1';
      }).catch(function () { d.close(); main.querySelector('[data-aid-error]').hidden = false; });
    });
  }
})();
