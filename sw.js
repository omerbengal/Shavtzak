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
// "refresh" button waits for the new build first (index.html,
// `shavtzakReloadToLatest`).
//
// KILL SWITCH: if this worker ever misbehaves, replace this file's contents
// with a worker that calls `self.registration.unregister()` on activate and
// deploy — every browser re-fetches it on the next open.
//
// Without a manifest (a debug run, or the generator did not run) the worker
// does nothing and every request goes to the network as if it were absent.

const PRECACHE = {"build":"b702f2bd4698359f","engine":"42d3d75a56efe1a2e9902f52dc8006099c45d937","files":{"assets/AssetManifest.bin":"855218d4d4c31e0ed6dfd47d13e059def9ec52a6c48540d1f09d646eb24ca070","assets/AssetManifest.bin.json":"b42d6901c94518f1f3fa675c557b3a33e950a22b3adb65a2f5931ec04860b26f","assets/FontManifest.json":"02388f3989ac2c6a29232afaa44a45f523e1bda5db2056b269deee4bc364593b","assets/assets/fonts/Rubik-Bold.ttf":"2fb105e3a66c3540e2308321e7c5bd786ce98a232930cd31c62e20d47747ad20","assets/assets/fonts/Rubik-Medium.ttf":"f8a3689e56c32d880491b0e11c0a1c16ab51f6bd010cfbf7ffe6da52ae6737bd","assets/assets/fonts/Rubik-Regular.ttf":"6b94e23adedab4522e1b65d21158e83c75f377fc99f916c58f8ec40ecc7dd035","assets/assets/images/google_maps.png":"e928c17cbbf120cd16e67a5457c48f6d4f5764901eb7eaed0f1c28e9d238160a","assets/assets/images/waze.png":"7e73c66dcd256055bc778672179e46a1d9c0852be9475cea0de752d1c3f3ce26","assets/fonts/MaterialIcons-Regular.otf":"bef1e53aba0f08fc59a4056a6010d82e02c51be10f1bddcb4d7d3a98082df4eb","assets/packages/cupertino_icons/assets/CupertinoIcons.ttf":"3d90c370aa4cf00dc57ee2b902f6652147c0f81e03e483df584a9c08b1687c9d","assets/packages/flutter_map/lib/assets/flutter_map_logo.png":"6051ae42fb505931a833e58f9209a9f96669a4d0e4b3f06f6d82cde12a0e0401","assets/shaders/ink_sparkle.frag":"5aee0e4ff369c0559eaa7af6d64dce812bab67afd9888d1d7d27046293b39ab5","assets/shaders/stretch_effect.frag":"c723fbb5b9a3456b101073825ab5d34de312a39f32bf5de42aae0cda605d0a1a","favicon.svg":"44eb446793436021dcfe3fd9012e1e6cfe3db1d2a5c0e71f2d15ba9e8d03d4f5","flutter.js":"a483fd28f51ed2fadd0da3fade5b672eba56310d549d736ce62eabf624a6a578","flutter_bootstrap.js":"911f7f378ee81de48757bfc31a2631918a61e76f735e7c3d7384eaefd14b2a29","icons/Icon-192.png":"9c66da8cff41a56fe9a555b6e54a2a05827df3855c6fdc59088bc02384120821","icons/icon-192.svg":"2d91155692fd2ee650af858a98e72942786c81a00abb2f628230e87af4cd9ead","icons/icon-512.svg":"1deaa9eb989f2535747b15fa55afaa81b426a2c082f16547a28126fd88fe601b","index.html":"107b0049508521ba8c0365eca6194361f30540f1aa7aefc74fb704066a0e557a","main.dart.js":"2796239feacbb0cdf74041045bb36e3435dc5358c2eafc1a2016c40d4bf31461","manifest.json":"099bd7c9bc4d298e547dbc9260a70c05e85e60aeb8166fb97014a1e9796faf39"}};

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

