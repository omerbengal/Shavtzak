// TEMP DIAGNOSTIC (preview only, removed before merge): an on-screen log of
// what happens when "הפעל התראות" is tapped (Android: no permission window).
// A badge at the top-left shows the device's state; a box at the bottom
// opens on the tap and lists every step. Tap the badge to open/close it.
// Shown only off GitHub Pages (the preview's *.web.app).
(function () {
  'use strict';
  if (/github\.io$/.test(location.hostname)) return;
  const TAG = 'diag-android-1';
  const lines = [];
  let badge = null;
  let box = null;
  let open = false;
  const state = {sw: '?', permQuery: '?'};

  const time = () => new Date().toTimeString().slice(0, 8);
  function log(text, data) {
    lines.push(time() + ' ' + text + (data ? ' ' + JSON.stringify(data) : ''));
    open = true;
    render();
  }
  window.shavtzakPushDiag = log;

  function standalone() {
    return navigator.standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches;
  }

  async function refreshState() {
    try {
      if (!('serviceWorker' in navigator)) { state.sw = 'no-sw-api'; }
      else {
        const reg = await navigator.serviceWorker.getRegistration();
        state.sw = reg ? [reg.active ? 'A' : '-', reg.waiting ? 'W' : '-',
          reg.installing ? 'I' : '-'].join('') + (navigator.serviceWorker.controller ? '+ctrl' : '') : 'noReg';
      }
    } catch (e) { state.sw = 'err ' + e; }
    try {
      if (navigator.permissions && navigator.permissions.query) {
        const st = await navigator.permissions.query({name: 'notifications'});
        state.permQuery = st.state;
        st.onchange = () => { state.permQuery = st.state; log('permission changed', {to: st.state}); };
      } else state.permQuery = 'n/a';
    } catch (e) { state.permQuery = 'err'; }
    render();
  }

  function render() {
    if (!document.body) return;
    if (!badge) {
      badge = document.createElement('div');
      badge.style.cssText = 'position:fixed;left:4px;top:4px;z-index:2147483647;' +
        'background:rgba(0,0,0,.85);color:#0f0;font:11px/1.3 monospace;padding:3px 6px;' +
        'border-radius:4px;direction:ltr;max-width:80vw;';
      badge.addEventListener('click', () => { open = !open; refreshState(); });
      document.body.appendChild(badge);
    }
    const perm = ('Notification' in window) ? Notification.permission : 'NO-Notification-API';
    badge.textContent = TAG + ' | perm ' + perm + '/' + state.permQuery + ' | sw ' + state.sw +
      ' | ' + (standalone() ? 'installed' : 'browser') + ' | push ' + ('PushManager' in window);
    if (!box) {
      box = document.createElement('pre');
      box.style.cssText = 'position:fixed;left:4px;right:4px;bottom:4px;z-index:2147483647;' +
        'max-height:45vh;overflow:auto;margin:0;background:rgba(0,0,0,.9);color:#fff;' +
        'font:11px/1.35 monospace;padding:6px;border-radius:6px;direction:ltr;' +
        'white-space:pre-wrap;word-break:break-all;';
      document.body.appendChild(box);
    }
    box.style.display = open ? 'block' : 'none';
    box.textContent = lines.join('\n') || '(no taps yet)';
  }

  log('page loaded', {ua: navigator.userAgent, installed: standalone(),
    perm: ('Notification' in window) ? Notification.permission : 'NO-Notification-API'});
  open = false;
  window.addEventListener('load', () => { refreshState(); });
  setInterval(refreshState, 3000);
  window.addEventListener('error', (e) => log('page error', {msg: String(e.message)}));
  window.addEventListener('unhandledrejection', (e) => log('unhandled rejection', {err: String(e.reason)}));
})();
