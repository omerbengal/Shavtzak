// TEMP DIAGNOSTIC (preview only, removed before merge).
// - A small badge at the top-left, always: the page's build tag, the tag of
//   the service worker that answers (the one that will handle a notification
//   tap), and whether that worker's Cache Storage is the page's. "sw: none"
//   = an older sw.js is still the active one.
// - After a tap on a notification (within 10 minutes), a box at the bottom
//   shows what sw.js and push.js saw and where the address went. Tapping the
//   badge opens the box any time.
// Shown only off GitHub Pages (the preview's *.web.app).
(function () {
  'use strict';
  if (/github\.io$/.test(location.hostname)) return;

  const PAGE_TAG = 'diag-3';
  const bootAt = Date.now();
  // All state first: add() below renders at once.
  const sw = {tag: '?', cache: '?', reg: '?'};
  let swLog = [];
  let badge = null;
  let box = null;
  let closed = false;
  let forced = false;
  const pageDiag = (window.shavtzakPushDiag = window.shavtzakPushDiag || []);
  const add = (entry) => {
    pageDiag.push(Object.assign({t: Date.now()}, entry));
    render();
  };

  add({ev: 'info', page: PAGE_TAG,
    standalone: navigator.standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches,
    ctrl: !!(navigator.serviceWorker && navigator.serviceWorker.controller),
    ref: document.referrer || ''});
  window.addEventListener('hashchange', (e) =>
    add({ev: 'hash', from: (e.oldURL.split('#')[1] || ''), to: (e.newURL.split('#')[1] || '')}));
  window.addEventListener('popstate', () => add({ev: 'pop', hash: location.hash}));
  document.addEventListener('visibilitychange', () =>
    add({ev: 'vis', state: document.visibilityState, hash: location.hash}));
  window.addEventListener('flutter-first-frame', () =>
    add({ev: 'firstFrame', hash: location.hash}));
  [2000, 5000, 10000].forEach((ms) =>
    setTimeout(() => add({ev: 'at' + ms / 1000 + 's', hash: location.hash}), ms));

  // ------------------------------------------------------------ worker check
  let nonce = 0;
  async function pingWorker() {
    if (!('serviceWorker' in navigator)) { sw.tag = 'unsupported'; renderBadge(); return; }
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      if (!reg) { sw.reg = 'noReg'; sw.tag = 'none'; renderBadge(); return; }
      sw.reg = [reg.active ? 'A' : '-', reg.waiting ? 'W' : '-', reg.installing ? 'I' : '-'].join('');
      const target = reg.active;
      if (!target) { sw.tag = 'noActive'; renderBadge(); return; }
      const mine = ++nonce;
      sw.tag = 'asking';
      renderBadge();
      target.postMessage({type: 'shavtzak-diag-ping', nonce: mine});
      setTimeout(async () => {
        if (sw.tag === 'asking') sw.tag = 'none (old sw.js)';
        try {
          const cache = await caches.open('shavtzak-push-diag');
          const hit = await cache.match(location.origin + '/__diag-ping');
          const data = hit ? await hit.json() : null;
          sw.cache = data && data.nonce === mine ? 'shared' : (data ? 'stale' : 'empty');
        } catch (e) {
          sw.cache = 'err';
        }
        renderBadge();
      }, 1500);
    } catch (e) {
      sw.tag = 'err ' + e;
      renderBadge();
    }
  }
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      const data = event.data || {};
      if (data.type === 'shavtzak-diag-pong') {
        sw.tag = data.tag;
        renderBadge();
      } else {
        setTimeout(refresh, 300);
      }
    });
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      add({ev: 'controllerchange'});
      setTimeout(pingWorker, 500);
    });
  }

  function renderBadge() {
    if (!document.body) return;
    if (!badge) {
      badge = document.createElement('div');
      badge.style.cssText = 'position:fixed;left:4px;top:4px;z-index:2147483647;' +
        'background:rgba(0,0,0,.8);color:#0f0;font:10px/1.3 monospace;padding:2px 5px;' +
        'border-radius:4px;direction:ltr;pointer-events:auto;';
      badge.addEventListener('click', () => { forced = true; closed = false; refresh(); });
      document.body.appendChild(badge);
    }
    badge.textContent = 'page ' + PAGE_TAG + ' | sw ' + sw.tag + ' | cache ' + sw.cache + ' | ' + sw.reg;
  }

  // ------------------------------------------------------------ tap log box
  async function readSw() {
    try {
      const cache = await caches.open('shavtzak-push-diag');
      const hit = await cache.match(location.origin + '/__diag-sw');
      swLog = hit ? await hit.json() : [];
    } catch (e) {
      swLog = [{t: Date.now(), ev: 'readFailed ' + e}];
    }
  }

  const time = (t) => new Date(t).toTimeString().slice(0, 8) + '.' + String(t % 1000).padStart(3, '0');
  const line = (e) => {
    const rest = Object.assign({}, e);
    delete rest.t;
    return time(e.t) + ' ' + JSON.stringify(rest);
  };

  function render() {
    renderBadge();
    const lastClick = swLog.filter((e) => e.ev === 'click').pop();
    const recent = lastClick && Date.now() - lastClick.t <= 10 * 60 * 1000;
    if (closed || !(recent || forced)) return;
    if (!document.body) return;
    if (!box) {
      box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:4px;right:4px;bottom:4px;max-height:55vh;' +
        'overflow:auto;z-index:2147483647;background:rgba(0,0,0,.88);color:#0f0;' +
        'font:10px/1.35 monospace;padding:6px;border-radius:6px;direction:ltr;' +
        'text-align:left;white-space:pre-wrap;word-break:break-all;';
      box.addEventListener('click', () => { closed = true; forced = false; box.remove(); box = null; });
      document.body.appendChild(box);
    }
    const shown = recent ? swLog.filter((e) => e.t >= lastClick.t - 1000) : swLog.slice(-10);
    box.textContent = 'PUSH DIAG (tap to close) boot ' + time(bootAt) + '\n' +
      'sw ' + sw.tag + ' cache ' + sw.cache + ' reg ' + sw.reg + '\n' +
      '-- sw.js --\n' + shown.map(line).join('\n') + '\n' +
      '-- page --\n' + pageDiag.map(line).join('\n') + '\n' +
      'now ' + location.hash;
  }
  window.shavtzakPushDiagChanged = render;

  async function refresh() {
    await readSw();
    render();
  }
  refresh();
  pingWorker();
  // Keep reading for a while: the tap may land after the page started.
  let n = 0;
  const timer = setInterval(() => {
    refresh();
    if (++n >= 30) clearInterval(timer);
  }, 1000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setTimeout(refresh, 300);
      setTimeout(pingWorker, 300);
    }
  });
  window.addEventListener('flutter-first-frame', () => setTimeout(pingWorker, 3000));
})();
