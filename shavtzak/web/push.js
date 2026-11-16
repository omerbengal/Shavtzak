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

  window.shavtzakPush = {
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
      const asked = Notification.permission === 'granted'
        ? Promise.resolve('granted')
        : Notification.requestPermission();
      if ((await asked) !== 'granted') return null;
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

  // A tap on a notification while the app is open (sw.js): go to the task.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      const data = event.data || {};
      if (data.type === 'shavtzak-open' && typeof data.path === 'string' && data.path) {
        window.location.hash = '#' + data.path;
      }
    });
  }
})();
