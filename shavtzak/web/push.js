// Web Push for the app ("שובצת למשימה"): the browser half, called from Dart
// (lib/core/web/web_push_web.dart). sw.js shows the pushes and handles the
// tap; the API stores the subscriptions and sends (functions/src/push.ts).
//
// iPhone: notifications exist only in the app added to the home screen
// (iOS 16.4+), and permission may be asked only inside a tap, so subscribe()
// asks for it before anything else it awaits.
(function () {
  'use strict';

  function supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  function isIos() {
    const ua = navigator.userAgent || '';
    // iPadOS reports itself as a Mac with a touch screen.
    return /iPhone|iPad|iPod/.test(ua) ||
      (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  }

  function isStandalone() {
    return navigator.standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches;
  }

  function urlBase64ToUint8Array(base64) {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function registration() {
    // The page registers sw.js after its first frame (index.html); registering
    // again is harmless and covers a tap that comes earlier.
    await navigator.serviceWorker.register('sw.js', {updateViaCache: 'none'});
    return navigator.serviceWorker.ready;
  }

  // Faster than this = the browser answered without asking the person.
  const NO_WINDOW_MS = 1000;
  let noWindow = false;

  window.shavtzakPush = {
    // The last subscribe() was refused by the browser without its window
    // (not on iPhone, whose settings are elsewhere).
    askedWithoutWindow() {
      return noWindow;
    },

    // iPhone / iPad in the browser rather than the home-screen app.
    iosNotInstalled() {
      return isIos() && !isStandalone();
    },

    // 'default' | 'granted' | 'denied' | 'unsupported'
    permission() {
      if (!supported()) return 'unsupported';
      return Notification.permission;
    },

    // Asks for permission (when not granted yet) and subscribes this device.
    // The subscription as JSON, or null when permission was not given.
    async subscribe(publicKey) {
      if (!supported()) return null;
      noWindow = false;
      const startedAt = Date.now();
      const asked = Notification.permission === 'granted'
        ? Promise.resolve('granted')
        : Notification.requestPermission();
      const answer = await asked;
      if (answer !== 'granted') {
        // No person answers in under a second: the browser refused without
        // showing its window (Chrome stops asking a site whose window was
        // closed a few times, and its site settings then say "no
        // permission"). Seen on Android, 17/11/2026.
        noWindow = !isIos() && Date.now() - startedAt < NO_WINDOW_MS;
        console.warn('push: permission not granted:', answer, noWindow ? '(no window shown)' : '');
        return null;
      }
      const reg = await registration();
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(publicKey),
        });
      }
      return JSON.stringify(sub.toJSON());
    },

    // This device's subscription as JSON, or null; never asks for anything.
    async current() {
      if (!supported()) return null;
      const reg = await navigator.serviceWorker.getRegistration();
      if (!reg) return null;
      const sub = await reg.pushManager.getSubscription();
      return sub ? JSON.stringify(sub.toJSON()) : null;
    },

    // Drops this device's subscription; its endpoint, or null if it had none.
    async unsubscribe() {
      if (!supported()) return null;
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = reg ? await reg.pushManager.getSubscription() : null;
      if (!sub) return null;
      const endpoint = sub.endpoint;
      await sub.unsubscribe();
      return endpoint;
    },
  };

  // Where a notification tap asked to go (sw.js leaves it, same names there):
  // taken once, and only when recent, so a later start goes home as usual.
  const PENDING_OPEN_CACHE = 'shavtzak-pending-open';
  const PENDING_OPEN_KEY = location.origin + '/__shavtzak-pending-open';
  const PENDING_OPEN_MAX_AGE_MS = 2 * 60 * 1000;

  async function takePendingOpen() {
    try {
      if (typeof caches === 'undefined') return null;
      const cache = await caches.open(PENDING_OPEN_CACHE);
      const hit = await cache.match(PENDING_OPEN_KEY);
      if (!hit) return null;
      await cache.delete(PENDING_OPEN_KEY);
      const data = await hit.json();
      const age = Date.now() - (data && data.at);
      if (!data || typeof data.path !== 'string' || !data.path.startsWith('/')) return null;
      if (!(age >= 0 && age <= PENDING_OPEN_MAX_AGE_MS)) return null;
      return data.path;
    } catch (_) {
      return null;
    }
  }

  // A running app follows a hash change (Flutter listens to it).
  function goTo(path) {
    if (window.location.hash !== '#' + path) window.location.hash = '#' + path;
  }

  // On start, before Flutter reads the address (index.html waits for this):
  // the iPhone started the app at its start page instead of at the task.
  // replaceState, so "back" does not return to the start page.
  window.shavtzakPendingOpen = takePendingOpen().then((path) => {
    if (path) history.replaceState(history.state, '', '#' + path);
  });

  // Back to the front after a tap whose message never arrived.
  document.addEventListener('visibilitychange', async () => {
    if (document.visibilityState !== 'visible') return;
    const path = await takePendingOpen();
    if (path) goTo(path);
  });

  // A tap on a notification while the app is open (sw.js): go to the task.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', async (event) => {
      const data = event.data || {};
      if (data.type === 'shavtzak-open' && typeof data.path === 'string' && data.path) {
        await takePendingOpen(); // handled here; do not replay it later
        goTo(data.path);
      }
    });
  }
})();
