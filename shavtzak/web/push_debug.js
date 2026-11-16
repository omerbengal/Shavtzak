// TEMP DIAGNOSTIC (preview only, removed before merge): after a tap on a
// notification, a box at the bottom of the screen shows what sw.js and
// push.js saw and where the address went, so one screenshot says where the
// task got lost. Shown only off GitHub Pages (the preview's *.web.app) and
// only within 10 minutes of a tap.
(function () {
  'use strict';
  if (/github\.io$/.test(location.hostname)) return;

  const PAGE_TAG = 'diag-2';
  const bootAt = Date.now();
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

  let swLog = [];
  async function readSw() {
    try {
      const cache = await caches.open('shavtzak-push-diag');
      const hit = await cache.match(location.origin + '/__diag-sw');
      swLog = hit ? await hit.json() : [];
    } catch (e) {
      swLog = [{t: Date.now(), ev: 'readFailed ' + e}];
    }
  }

  let box = null;
  let closed = false;
  const time = (t) => new Date(t).toTimeString().slice(0, 8) + '.' + String(t % 1000).padStart(3, '0');
  const line = (e) => {
    const rest = Object.assign({}, e);
    delete rest.t;
    return time(e.t) + ' ' + JSON.stringify(rest);
  };

  function render() {
    const lastClick = swLog.filter((e) => e.ev === 'click').pop();
    if (closed || !lastClick || Date.now() - lastClick.t > 10 * 60 * 1000) return;
    if (!document.body) return;
    if (!box) {
      box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:4px;right:4px;bottom:4px;max-height:55vh;' +
        'overflow:auto;z-index:2147483647;background:rgba(0,0,0,.88);color:#0f0;' +
        'font:10px/1.35 monospace;padding:6px;border-radius:6px;direction:ltr;' +
        'text-align:left;white-space:pre-wrap;word-break:break-all;';
      box.addEventListener('click', () => { closed = true; box.remove(); });
      document.body.appendChild(box);
    }
    const sw = swLog.filter((e) => e.t >= lastClick.t - 1000);
    box.textContent = 'PUSH DIAG (tap to close) boot ' + time(bootAt) + '\n' +
      '-- sw.js --\n' + sw.map(line).join('\n') + '\n' +
      '-- page --\n' + pageDiag.map(line).join('\n') + '\n' +
      'now ' + location.hash;
  }
  window.shavtzakPushDiagChanged = render;

  async function refresh() {
    await readSw();
    render();
  }
  refresh();
  // Keep reading for a while: the tap may land after the page started.
  let n = 0;
  const timer = setInterval(() => {
    refresh();
    if (++n >= 30) clearInterval(timer);
  }, 1000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') setTimeout(refresh, 300);
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', () => setTimeout(refresh, 300));
  }
})();
