// The in-app refresh ("רענון האפליקציה", WebHelper.reloadPage): a clean
// reinstall of the newest deployed build, like Cmd+Shift+R but lasting.
//
// 1. Read the newest sw.js from the server; its manifest lists every file of
//    the build with its sha256 and size (tool/generate_service_worker.mjs).
// 2. Wipe the copy of the app this device keeps (the app caches of sw.js)
//    and unregister the worker, so nothing old can be served any more.
// 3. Download every file fresh from the server (bypassing the browser's own
//    cache), check it against the manifest and store it as the new build's
//    cache. A full-screen download screen shows the progress, with the
//    salute animation (assets/animations/salute_loading.json, lottie-web).
// 4. Register sw.js again; its install finds every file already stored.
//    Then reload: the page comes up on the new build at once.
//
// A failed download (offline, or GitHub Pages still mid-deploy and serving
// files of two builds) stops on the screen with a retry button; it never
// reloads into a half-new app. Files already downloaded are kept.
//
// The animation (user rules): the salute always plays at least one whole
// loop — a quick download still waits for it before reloading — and on a
// failure the salute finishes its loop, then the crying takes over from the
// very picture the salute ends on (assets/animations/download_failed.json,
// tool/download_failed_gen.py).
//
// Without a manifest (`flutter run`: sw.js is not pinned) it just reloads.
// `?refreshdemo` in the address (or shavtzakRefreshDemo() in the console)
// shows the download screen with made-up progress, for looking at it;
// `?refreshdemo=failed` (shavtzakRefreshDemo('offline')) and
// `?refreshdemo=notready` (shavtzakRefreshDemo('notReady')) the failed screen
// (assets/animations/download_failed.json, tool/download_failed_gen.py).
(function () {
  const APP_CACHE_PREFIX = 'shavtzak-app-'; // sw.js PRECACHE_PREFIX
  // Both fetched when the screen opens: once the download fails the device's
  // copy is wiped and the network may be gone.
  const ANIMATIONS = {
    loading: 'assets/assets/animations/salute_loading.json',
    failed: 'assets/assets/animations/download_failed.json',
  };
  const LOTTIE = 'lottie/lottie_light.min.js';
  const PARALLEL = 4;
  const ATTEMPTS = 3;

  let running = false;

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ---------------------------------------------------------------- screen

  const CSS = `
    #app-refresh {
      position: fixed; inset: 0; z-index: 2147483647;
      display: flex; flex-direction: column; align-items: center;
      justify-content: center; gap: 0;
      background: #ffffff; direction: rtl; padding: 24px;
      box-sizing: border-box; text-align: center;
      font-family: Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      opacity: 0; transition: opacity .25s ease-out;
      touch-action: none; user-select: none; -webkit-user-select: none;
    }
    #app-refresh.shown { opacity: 1; }
    #app-refresh .ar-anim {
      width: min(68vw, 280px); height: min(68vw, 280px); margin-bottom: 8px;
    }
    #app-refresh .ar-title {
      font-size: 22px; font-weight: 700; color: rgba(0,0,0,.87);
      margin-bottom: 6px;
    }
    #app-refresh .ar-sub {
      font-size: 15px; color: #8a8a8a; margin-bottom: 22px; min-height: 1.3em;
    }
    #app-refresh .ar-track {
      position: relative; width: min(72vw, 280px); height: 10px;
      border-radius: 5px; background: #e3f2fd; overflow: hidden;
    }
    #app-refresh .ar-fill {
      position: absolute; top: 0; bottom: 0; right: 0; width: 0%;
      border-radius: 5px; background: linear-gradient(270deg, #64b5f6, #1e88e5);
      transition: width .3s ease-out;
    }
    #app-refresh .ar-pct {
      margin-top: 10px; font-size: 16px; font-weight: 600; color: #1e88e5;
      font-variant-numeric: tabular-nums; direction: ltr;
    }
    /* Always takes its room (hidden until a failure), so showing it never
       moves the animation or the text above it. */
    #app-refresh .ar-retry {
      visibility: hidden; opacity: 0; transition: opacity .3s ease-out;
      margin-top: 22px; padding: 12px 28px; border: 0;
      border-radius: 24px; background: #1e88e5; color: #fff;
      font: inherit; font-size: 16px; font-weight: 600; cursor: pointer;
    }
    #app-refresh.failed .ar-retry { visibility: visible; opacity: 1; }
    #app-refresh.failed .ar-fill { background: #ef9a9a; }
    #app-refresh.failed .ar-pct { color: #c62828; }
  `;

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      if (window.lottie) return resolve();
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  // Resolves once the screen is up and the animation (if it loaded) plays.
  // The animation is best effort: without it the screen still works.
  async function showScreen() {
    if (!document.getElementById('app-refresh-style')) {
      const style = document.createElement('style');
      style.id = 'app-refresh-style';
      style.textContent = CSS;
      document.head.appendChild(style);
    }
    document.getElementById('app-refresh')?.remove();
    const root = document.createElement('div');
    root.id = 'app-refresh';
    root.innerHTML = `
      <div class="ar-anim"></div>
      <div class="ar-title">מורידים את הגרסה החדשה</div>
      <div class="ar-sub">רק רגע…</div>
      <div class="ar-track"><div class="ar-fill"></div></div>
      <div class="ar-pct">0%</div>
      <button class="ar-retry" type="button">לנסות שוב</button>`;
    // Keep taps and keys from reaching the app underneath.
    for (const type of ['pointerdown', 'touchstart', 'keydown', 'wheel']) {
      root.addEventListener(type, (e) => e.stopPropagation());
    }
    document.body.appendChild(root);
    requestAnimationFrame(() => root.classList.add('shown'));

    const $ = (sel) => root.querySelector(sel);
    const animations = {}; // name → Lottie data, once loaded
    let playing = null;
    let loading = false; // the salute is the one playing
    let loops = 0; // salute loops completed since it started
    let loopEnded = []; // resolvers waiting for the salute's next loop end
    const play = (name) => {
      loading = false;
      if (!animations[name]) return;
      playing?.destroy();
      const data = animations[name];
      playing = window.lottie.loadAnimation({
        container: $('.ar-anim'),
        renderer: 'svg',
        loop: true,
        autoplay: name === 'loading',
        animationData: data,
      });
      if (name === 'loading') {
        loading = true;
        loops = 0;
        playing.addEventListener('loopComplete', () => {
          loops++;
          const waiting = loopEnded;
          loopEnded = [];
          waiting.forEach((resolve) => resolve());
        });
      } else {
        // The crying starts where the salute ends, plays its turn and first
        // cry once, then loops the cry (marker "loop", download_failed_gen.py).
        const loop = data.markers?.find((m) => m.cm === 'loop')?.tm;
        if (loop) {
          playing.playSegments([[0, loop], [loop, data.op]], true);
        } else {
          playing.play();
        }
      }
    };
    // The salute's next loop end (now, without a salute). Capped in case
    // the animation stalls; a loop is 8 s.
    const saluteLoopEnd = () => (loading
      ? Promise.race([new Promise((r) => loopEnded.push(r)), sleep(10000)])
      : Promise.resolve());
    const ui = {
      // 100% only once everything is in: until then at most 99.
      progress(fraction) {
        const pct = fraction >= 1 ? 100 : Math.min(99, Math.floor(fraction * 100));
        $('.ar-fill').style.width = pct + '%';
        $('.ar-pct').textContent = pct + '%';
      },
      text(title, sub) {
        $('.ar-title').textContent = title;
        $('.ar-sub').textContent = sub;
      },
      // Resolves once the salute has played at least one whole loop.
      async oneFullLoop() {
        if (loops < 1) await saluteLoopEnd();
      },
      // Waits for the salute to finish its loop (at least one whole loop
      // shown), then switches to the crying, which starts where it ends.
      // [why]: 'offline' or 'notReady' (see failureKind).
      async failed(why, onRetry) {
        await saluteLoopEnd();
        root.classList.add('failed');
        play('failed');
        ui.text(...FAILURE_TEXT[why]);
        $('.ar-retry').onclick = () => {
          root.classList.remove('failed');
          play('loading');
          ui.text('מורידים את הגרסה החדשה', 'רק רגע…');
          onRetry();
        };
      },
    };

    try {
      await Promise.all([
        Promise.race([loadScript(LOTTIE), sleep(4000).then(() => {
          throw new Error('lottie-web did not load');
        })]),
        ...Object.entries(ANIMATIONS).map(async ([name, url]) => {
          animations[name] = await (await fetch(url)).json();
        }),
      ]);
      play('loading');
    } catch (e) {
      console.warn('refresh animation unavailable:', e);
    }
    return ui;
  }

  // ------------------------------------------------------------- download

  // The server answered, but not with the newest build's file: an HTTP error,
  // or GitHub Pages mid-deploy serving a file of the other build.
  class NotReady extends Error {}

  const FAILURE_TEXT = {
    offline: ['אין חיבור לאינטרנט',
      'נסה/י לשפר את חיבור האינטרנט, ולחצו על "לנסות שוב"'],
    notReady: ['הגרסה החדשה עוד לא מוכנה',
      'כדאי לנסות שוב בעוד דקה, או לסגור ולפתוח מחדש'],
  };

  // A fetch that never got an answer rejects with a TypeError.
  function failureKind(error) {
    return !navigator.onLine || error instanceof TypeError ? 'offline' : 'notReady';
  }

  async function newestManifest() {
    const response = await fetch('sw.js', {cache: 'no-store'});
    if (!response.ok) throw new NotReady('sw.js: HTTP ' + response.status);
    const match = (await response.text()).match(/const PRECACHE = (\{.*\});/);
    return match ? JSON.parse(match[1]) : null;
  }

  // [keep]: the cache a retry continues filling, or null.
  async function wipeDeviceCopy(keep) {
    const regs = (await navigator.serviceWorker?.getRegistrations()) ?? [];
    await Promise.all(regs.map((r) => r.unregister()));
    const keys = await caches.keys();
    // The CDN cache (CanvasKit, Firebase SDK) is kept: those URLs never
    // change their content, and the new build may still use them.
    await Promise.all(keys
      .filter((k) => k.startsWith(APP_CACHE_PREFIX) && k !== keep)
      .map((k) => caches.delete(k)));
  }

  async function sha256Hex(buffer) {
    const digest = await crypto.subtle.digest('SHA-256', buffer);
    return Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  // Fresh bytes of [path] matching [hash]; [onBytes] reports each chunk.
  async function download(path, hash, onBytes) {
    let lastError;
    for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
      if (attempt > 0) await sleep(1500 * attempt);
      let received = 0;
      try {
        const response = await fetch(path, {cache: 'reload'});
        if (!response.ok) throw new NotReady(path + ': HTTP ' + response.status);
        const chunks = [];
        const reader = response.body.getReader();
        for (;;) {
          const {done, value} = await reader.read();
          if (done) break;
          chunks.push(value);
          received += value.byteLength;
          onBytes(value.byteLength);
        }
        const body = await new Blob(chunks).arrayBuffer();
        if ((await sha256Hex(body)) !== hash) {
          throw new NotReady(path + ': not the bytes of the newest build');
        }
        return new Response(body, {headers: {
          'Content-Type': response.headers.get('Content-Type') ?? '',
        }});
      } catch (e) {
        onBytes(-received); // this attempt's bytes no longer count
        lastError = e;
      }
    }
    throw lastError;
  }

  async function downloadBuild(manifest, ui) {
    const cache = await caches.open(APP_CACHE_PREFIX + manifest.build);
    const base = new URL('./', document.baseURI).href;
    const paths = Object.keys(manifest.files);
    // Older manifests have no sizes: then every file counts the same.
    const size = (p) => (manifest.sizes ? manifest.sizes[p] ?? 0 : 1);
    const total = paths.reduce((sum, p) => sum + size(p), 0) || 1;
    let done = 0;
    let streamed = 0;
    const report = () =>
      ui.progress(manifest.sizes ? (done + streamed) / total : done / total);

    const queue = [];
    for (const path of paths) {
      if (await cache.match(base + path)) {
        done += size(path); // kept from an earlier, interrupted try
      } else {
        queue.push(path);
      }
    }
    report();

    const worker = async () => {
      for (let path; (path = queue.shift()) !== undefined;) {
        let mine = 0;
        const response = await download(path, manifest.files[path], (n) => {
          if (!manifest.sizes) return;
          mine += n;
          streamed += n;
          report();
        });
        await cache.put(base + path, response);
        streamed -= mine;
        done += size(path);
        report();
      }
    };
    await Promise.all(Array.from({length: PARALLEL}, worker));
  }

  // sw.js again, so the reload is served from the cache just filled. Best
  // effort: without it the reload still gets the fresh files.
  async function reinstallWorker() {
    if (!('serviceWorker' in navigator)) return;
    try {
      const reg = await navigator.serviceWorker.register('sw.js', {updateViaCache: 'none'});
      const worker = reg.installing || reg.waiting;
      if (!worker) return;
      await Promise.race([
        new Promise((resolve) => worker.addEventListener('statechange', () => {
          if (worker.state === 'activated' || worker.state === 'redundant') resolve();
        })),
        sleep(15000),
      ]);
    } catch (e) {
      console.warn('sw.js re-registration failed:', e);
    }
  }

  // [resume]: a retry, which keeps what the failed try already downloaded.
  // The first try wipes everything, the current build's files included.
  async function run(ui, resume = false) {
    try {
      const manifest = await newestManifest();
      await wipeDeviceCopy(resume && manifest ? APP_CACHE_PREFIX + manifest.build : null);
      if (manifest) await downloadBuild(manifest, ui);
      ui.progress(1);
      ui.text('הגרסה החדשה מוכנה', 'פותחים אותה…');
      await Promise.all([manifest && reinstallWorker(), ui.oneFullLoop()]);
      location.reload();
    } catch (e) {
      console.warn('refresh failed:', e);
      await ui.failed(failureKind(e), () => run(ui, true));
    }
  }

  window.shavtzakReloadToLatest = async function () {
    if (running) return;
    running = true;
    let manifest;
    try {
      manifest = await newestManifest();
    } catch (e) {
      manifest = undefined; // unknown: show the screen, run() retries it
    }
    if (manifest === null) {
      // Not a pinned build (`flutter run`): nothing to download.
      location.reload();
      return;
    }
    run(await showScreen());
  };

  // [failed]: undefined (succeeds), 'offline' or 'notReady'.
  window.shavtzakRefreshDemo = async function (failed) {
    const ui = await showScreen();
    const restart = () => {
      document.getElementById('app-refresh')?.remove();
      window.shavtzakRefreshDemo(failed);
    };
    // made-up progress: about 3 s to 100% (to 62% when it is to fail)
    const end = failed ? 0.62 : 1;
    for (let p = 0; p < end; p += 0.01 + Math.random() * 0.02) {
      ui.progress(p);
      await sleep(60);
    }
    if (failed) {
      await ui.failed(failed, restart);
      return;
    }
    ui.progress(1);
    ui.text('הגרסה החדשה מוכנה', 'פותחים אותה…');
    await ui.oneFullLoop();
    await sleep(1500); // stands in for the reload
    restart();
  };

  // Flutter's hash routes may carry the flag too: /#/whoami?refreshdemo.
  const demo = (location.search + location.hash)
    .match(/[?&]refreshdemo(?:=(failed|notready))?\b/);
  if (demo) {
    const failed = {failed: 'offline', notready: 'notReady'}[demo[1]];
    window.addEventListener('flutter-first-frame',
      () => window.shavtzakRefreshDemo(failed), {once: true});
  }
})();
