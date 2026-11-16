// Shavtzak's service worker: keeps the app itself on the device so a load
// never waits on GitHub Pages or the Flutter/Firebase CDNs.
//
// - The build's own files are PRECACHED, pinned to the exact bytes of one
//   build. `tool/generate_service_worker.mjs` replaces the null below with
//   {path: sha256} after `flutter build web`; each deploy therefore changes
//   this file, the browser notices (it always re-fetches the worker script,
//   see `updateViaCache: 'none'` in index.html) and installs the new build in
//   the background. A page is always served ONE build, never a mix.
// - Versioned CDN files (CanvasKit, the Firebase JS SDK, the Roboto fallback)
//   never change under a URL, so they are kept forever on first use.
//
// The trade-off: the first open after a deploy still shows the previous build
// (served instantly); the new one is ready from the next open. The in-app
// "refresh" button wipes this worker and its caches and downloads the new
// build fresh, with a progress screen (web/app_refresh.js).
//
// KILL SWITCH: if this worker ever misbehaves, replace this file's contents
// with a worker that calls `self.registration.unregister()` on activate and
// deploy — every browser re-fetches it on the next open.
//
// Without a manifest (a debug run, or the generator did not run) the worker
// does nothing and every request goes to the network as if it were absent.

const PRECACHE = /* __PRECACHE_MANIFEST__ */ null;

const PRECACHE_PREFIX = 'shavtzak-app-';
const CDN_CACHE = 'shavtzak-cdn-v1';
const CDN_PREFIXES = [
  'https://www.gstatic.com/flutter-canvaskit/',
  'https://www.gstatic.com/firebasejs/',
  'https://fonts.gstatic.com/',
];

const BASE = new URL('./', self.registration.scope).href;

function precacheName() {
  return PRECACHE_PREFIX + PRECACHE.build;
}

// The path of [url] relative to the app root, as the manifest lists it; the
// app root itself is index.html.
function appPath(url) {
  if (!url.startsWith(BASE)) return null;
  const path = url.slice(BASE.length).split(/[?#]/)[0];
  return path === '' ? 'index.html' : path;
}

async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// Fetch [path] as the manifest pins it. The HTTP cache usually already holds
// it (the page just loaded it), so try that first and only re-download when
// its bytes are not the pinned ones.
async function fetchPinned(path, hash) {
  const url = BASE + path;
  for (const mode of ['default', 'reload']) {
    const response = await fetch(url, {cache: mode});
    if (!response.ok) continue;
    const body = await response.clone().arrayBuffer();
    if ((await sha256Hex(body)) === hash) return response;
  }
  throw new Error('no copy of ' + path + ' matches this build');
}

self.addEventListener('install', (event) => {
  if (!PRECACHE) {
    self.skipWaiting();
    return;
  }
  event.waitUntil((async () => {
    const cache = await caches.open(precacheName());
    // Reuse identical files from the build already on the device.
    const previous = (await caches.keys())
      .filter((k) => k.startsWith(PRECACHE_PREFIX) && k !== precacheName());
    const old = await Promise.all(previous.map((k) => caches.open(k)));
    await Promise.all(Object.entries(PRECACHE.files).map(async ([path, hash]) => {
      if (await cache.match(BASE + path)) return;
      for (const c of old) {
        const hit = await c.match(BASE + path);
        if (hit && (await sha256Hex(await hit.clone().arrayBuffer())) === hash) {
          await cache.put(BASE + path, hit);
          return;
        }
      }
      await cache.put(BASE + path, await fetchPinned(path, hash));
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keep = PRECACHE ? precacheName() : null;
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((k) => k.startsWith(PRECACHE_PREFIX) && k !== keep)
      .map((k) => caches.delete(k)));
    if (PRECACHE) {
      // CanvasKit is pinned to the engine; drop other engines' copies.
      const cdn = await caches.open(CDN_CACHE);
      for (const request of await cdn.keys()) {
        if (request.url.startsWith(CDN_PREFIXES[0]) &&
            !request.url.includes(PRECACHE.engine)) {
          await cdn.delete(request);
        }
      }
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!PRECACHE || request.method !== 'GET') return;

  const url = request.url;
  if (CDN_PREFIXES.some((p) => url.startsWith(p))) {
    event.respondWith(cdnFirst(request));
    return;
  }

  const path = appPath(url);
  if (path === null || !(path in PRECACHE.files)) return;
  event.respondWith((async () => {
    const cache = await caches.open(precacheName());
    const hit = await cache.match(BASE + path);
    return hit || fetch(request);
  })());
});

async function cdnFirst(request) {
  const cache = await caches.open(CDN_CACHE);
  const hit = await cache.match(request);
  if (hit) return hit;
  const response = await fetch(request);
  // Opaque (no-cors) responses are kept too: these URLs are immutable.
  if (response.ok || response.type === 'opaque') {
    cache.put(request, response.clone()).catch(() => {});
  }
  return response;
}


// ---------------------------------------------------------------------------
// Web Push ("שובצת למשימה"; the API sends it, functions/src/push.ts). Works
// with or without a manifest, so a branch preview gets it too.
//
// Every push shows a notification: Safari takes the permission back after a
// few pushes that showed none.
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {body: event.data ? event.data.text() : ''};
  }
  const title = data.title || 'שבצק';
  diag({ev: 'push', path: data.path || ''});
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || '',
    tag: data.tag || undefined,
    icon: BASE + 'icons/Icon-192.png',
    badge: BASE + 'icons/Icon-192.png',
    dir: 'rtl',
    lang: 'he',
    data: {path: data.path || ''},
  }));
});

// Where a notification tap asked to go, for the page to take (web/push.js,
// same names there). iPhone, home-screen app closed: WebKit starts the app at
// its start page and ignores the URL given to openWindow (WebKit bug 263687),
// so the task was lost and the app opened home; a message posted to a window
// that is still starting can be lost too. The page takes this on start and
// whenever it comes to the front, once, and only if it is recent.
const PENDING_OPEN_CACHE = 'shavtzak-pending-open';
const PENDING_OPEN_KEY = self.location.origin + '/__shavtzak-pending-open';

// TEMP DIAGNOSTIC (preview only, removed before merge): what the tap did,
// read and shown by web/push_debug.js.
const DIAG_TAG = 'diag-3';
async function diag(entry) {
  try {
    const cache = await caches.open('shavtzak-push-diag');
    const key = self.location.origin + '/__diag-sw';
    const hit = await cache.match(key);
    const log = hit ? await hit.json() : [];
    log.push(Object.assign({t: Date.now(), sw: DIAG_TAG}, entry));
    await cache.put(key, new Response(JSON.stringify(log.slice(-20)),
      {headers: {'Content-Type': 'application/json'}}));
  } catch (_) {}
}

// TEMP DIAGNOSTIC: the page asks which worker runs (push_debug.js badge); the
// answer also proves the worker's Cache Storage is the page's.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'shavtzak-diag-ping') return;
  event.waitUntil((async () => {
    try {
      const cache = await caches.open('shavtzak-push-diag');
      await cache.put(self.location.origin + '/__diag-ping', new Response(
        JSON.stringify({tag: DIAG_TAG, at: Date.now(), nonce: data.nonce})));
    } catch (_) {}
    if (event.source) event.source.postMessage({type: 'shavtzak-diag-pong', tag: DIAG_TAG, nonce: data.nonce});
  })());
});

async function rememberOpen(path) {
  try {
    const cache = await caches.open(PENDING_OPEN_CACHE);
    await cache.put(PENDING_OPEN_KEY, new Response(
      JSON.stringify({path, at: Date.now()}),
      {headers: {'Content-Type': 'application/json'}}));
  } catch (_) {
    // Best effort: the URL and the message below still try.
  }
}

// A tap opens the task: an open window of the app is brought forward and told
// where to go (web/push.js moves its hash route); with none, a new one opens
// there. Both also find it in [rememberOpen].
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const path = (event.notification.data && event.notification.data.path) || '';
  event.waitUntil((async () => {
    await diag({ev: 'click', path});
    if (path) await rememberOpen(path);
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    await diag({ev: 'windows', n: windows.length,
      list: windows.map((c) => [c.url, c.visibilityState, c.focused])});
    const app = windows.find((client) => client.url.startsWith(BASE));
    if (app) {
      app.postMessage({type: 'shavtzak-open', path});
      try {
        await app.focus();
        await diag({ev: 'focused', url: app.url});
      } catch (e) {
        await diag({ev: 'focusFailed', err: String(e)});
        // Some browsers refuse focus(); the page still moves.
      }
      return;
    }
    try {
      const opened = await self.clients.openWindow(BASE + (path ? '#' + path : ''));
      await diag({ev: 'openWindow', url: opened ? opened.url : null});
    } catch (e) {
      await diag({ev: 'openWindowFailed', err: String(e)});
    }
  })());
});
