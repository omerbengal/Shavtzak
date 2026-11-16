// A tap on "שובצת למשימה" must open the task, also on an iPhone where the
// home-screen app was closed: there WebKit opens the app at its start page and
// ignores the URL given to clients.openWindow (WebKit bug 263687), and a
// message posted to a window that is still starting can be lost.
//
// Runs web/sw.js and web/push.js in node with fake browser objects:
//   node --test tool/test/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const WEB = new URL('../../web/', import.meta.url);
const SW_SOURCE = readFileSync(new URL('sw.js', WEB), 'utf8');
const PUSH_SOURCE = readFileSync(new URL('push.js', WEB), 'utf8');
const ORIGIN = 'https://shavtzak.example';
const BASE = ORIGIN + '/Shavtzak/';
const TASK_PATH = '/team-tasks?task=a';

/** Cache Storage shared by the worker and the page, as in a browser. */
function fakeCaches() {
  const stores = new Map();
  const key = (r) => (typeof r === 'string' ? r : r.url);
  return {
    async open(name) {
      if (!stores.has(name)) stores.set(name, new Map());
      const store = stores.get(name);
      return {
        async put(request, response) {
          store.set(key(request), await response.text());
        },
        async match(request) {
          const body = store.get(key(request));
          return body === undefined ? undefined : new Response(body);
        },
        async delete(request) {
          return store.delete(key(request));
        },
        async keys() {
          return [...store.keys()].map((url) => ({url}));
        },
      };
    },
    async keys() {
      return [...stores.keys()];
    },
    async delete(name) {
      return stores.delete(name);
    },
  };
}

/** Loads sw.js; returns a function that taps a notification carrying [path]. */
function loadWorker({caches, windows, opened}) {
  const listeners = {};
  const self = {
    location: new URL(BASE + 'sw.js'),
    registration: {scope: BASE},
    addEventListener: (type, fn) => {
      listeners[type] = fn;
    },
    clients: {
      async matchAll() {
        return windows;
      },
      // iPhone, app closed: the app starts at its start page whatever the URL.
      async openWindow(url) {
        opened.push(url);
        return null;
      },
      claim: async () => {},
    },
    skipWaiting: async () => {},
  };
  self.self = self;
  vm.runInNewContext(SW_SOURCE, {self, caches, URL, Response, console, Date, JSON, Promise});
  return async (path, {now} = {}) => {
    let done;
    const event = {
      notification: {data: {path}, close() {}},
      waitUntil(p) {
        done = p;
      },
    };
    const realNow = Date.now;
    if (now !== undefined) Date.now = () => now;
    try {
      listeners.notificationclick(event);
      await done;
    } finally {
      Date.now = realNow;
    }
  };
}

/** Loads push.js into a page whose address is [hash]; returns the page. */
function loadPage({caches, hash = '#/whoami'}) {
  const docListeners = {};
  const location = {
    origin: ORIGIN,
    hash,
    hashSets: [],
  };
  // A script assigning location.hash moves the route (and Flutter follows).
  const locationProxy = new Proxy(location, {
    set(target, prop, value) {
      if (prop === 'hash') target.hashSets.push(value);
      target[prop] = value;
      return true;
    },
  });
  const window = {
    location: locationProxy,
    caches,
    matchMedia: () => ({matches: true}),
    history: {
      replaceState(_state, _title, url) {
        location.hash = url.slice(url.indexOf('#'));
      },
    },
  };
  const document = {
    visibilityState: 'visible',
    baseURI: BASE,
    addEventListener: (type, fn) => {
      docListeners[type] = fn;
    },
  };
  const navigator = {
    userAgent: 'iPhone',
    standalone: true,
    serviceWorker: {addEventListener() {}},
  };
  window.window = window;
  vm.runInNewContext(PUSH_SOURCE, {
    window,
    document,
    navigator,
    location: locationProxy,
    history: window.history,
    caches,
    URL,
    Response,
    Date,
    JSON,
    Promise,
    console,
    PushManager: function () {},
    Notification: {permission: 'granted'},
    atob,
    setTimeout,
  });
  return {
    window,
    location,
    async comeBack() {
      await docListeners.visibilitychange();
    },
  };
}

test('closed app on iPhone: the tap opens the task, not the home screen', async () => {
  const caches = fakeCaches();
  const opened = [];
  const tap = loadWorker({caches, windows: [], opened});

  await tap(TASK_PATH);
  assert.equal(opened.length, 1);

  // WebKit started the app at its start page; index.html sent it to "#/whoami".
  const page = loadPage({caches, hash: '#/whoami'});
  assert.ok(page.window.shavtzakPendingOpen, 'push.js exposes the pending-open check');
  await page.window.shavtzakPendingOpen;
  assert.equal(page.location.hash, '#' + TASK_PATH);
});

test('the task opens once: a second start goes home as usual', async () => {
  const caches = fakeCaches();
  const tap = loadWorker({caches, windows: [], opened: []});
  await tap(TASK_PATH);

  const first = loadPage({caches});
  await first.window.shavtzakPendingOpen;
  const second = loadPage({caches});
  await second.window.shavtzakPendingOpen;
  assert.equal(second.location.hash, '#/whoami');
});

test('open app whose message got lost: coming to the front opens the task', async () => {
  const caches = fakeCaches();
  const page = loadPage({caches, hash: '#/admin'});
  await page.window.shavtzakPendingOpen;
  // The window is found but the message never reaches the page.
  const lost = {url: BASE + '#/admin', postMessage() {}, focus: async () => {}};
  const tap = loadWorker({caches, windows: [lost], opened: []});

  await tap(TASK_PATH);
  await page.comeBack();
  assert.equal(page.location.hash, '#' + TASK_PATH);
});

test('an old tap is not replayed on a later start', async () => {
  const caches = fakeCaches();
  const tap = loadWorker({caches, windows: [], opened: []});
  await tap(TASK_PATH, {now: Date.now() - 10 * 60 * 1000});

  const page = loadPage({caches});
  await page.window.shavtzakPendingOpen;
  assert.equal(page.location.hash, '#/whoami');
});
