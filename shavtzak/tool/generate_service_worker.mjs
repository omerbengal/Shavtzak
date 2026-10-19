// Pins build/web/sw.js to this build: writes {path: sha256} of every file the
// app loads into the worker's precache manifest (see web/sw.js). Also writes
// the Firebase JS SDK preloads into build/web/index.html.
//
// Run after `flutter build web`, from shavtzak/:
//   node tool/generate_service_worker.mjs [build/web]
// Fails (non-zero) rather than deploy a worker that would cache nothing or
// the wrong thing.

import {createHash} from 'node:crypto';
import {readFileSync, readdirSync, statSync, writeFileSync} from 'node:fs';
import {join, relative, resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = process.argv[2] ?? 'build/web';

// Never precached: the workers themselves, the OAuth popup page (a separate
// navigation), files the page never requests, and the self-hosted CanvasKit
// copies (the app loads CanvasKit from the CDN; sw.js caches it from there).
const EXCLUDED = [
  /^sw\.js$/,
  /^flutter_service_worker\.js$/,
  /^oauth-callback\.html$/,
  /^\.last_build_id$/,
  /^version\.json$/,
  /^canvaskit\//,
  /^assets\/NOTICES$/,
  /^icons\/Icon-maskable-/,
  /^icons\/Icon-512\.png$/,
  /^favicon\.png$/,
  /\.symbols$/,
  /\.map$/,
  /\.info\.json$/,
];

// firebase_core_web imports these SDK modules from the CDN only after
// main.dart.js has run; index.html preloads them so they arrive with it.
// The version is the one the resolved firebase_core_web pins.
const FIREBASE_SERVICES = ['app', 'auth', 'firestore'];

function firebaseSdkVersion() {
  const config = JSON.parse(readFileSync('.dart_tool/package_config.json', 'utf8'));
  const pkg = config.packages.find((p) => p.name === 'firebase_core_web');
  if (!pkg) throw new Error('firebase_core_web not in package_config.json');
  const root = fileURLToPath(new URL(pkg.rootUri.endsWith('/') ? pkg.rootUri : pkg.rootUri + '/',
    pathToFileURL(resolve('.dart_tool') + '/')));
  const src = readFileSync(join(root, 'lib/src/firebase_sdk_version.dart'), 'utf8');
  const version = src.match(/supportedFirebaseJsSdkVersion\s*=\s*'([0-9.]+)'/)?.[1];
  if (!version) throw new Error('supportedFirebaseJsSdkVersion not found');
  return version;
}

function preloadFirebaseSdk() {
  const indexPath = join(root, 'index.html');
  const marker = '<!-- __FIREBASE_SDK_MODULEPRELOAD__ -->';
  const html = readFileSync(indexPath, 'utf8');
  if (!html.includes(marker)) throw new Error(`${marker} missing in ${indexPath}`);
  const version = firebaseSdkVersion();
  const links = FIREBASE_SERVICES.map((s) =>
    `<link rel="modulepreload" href="https://www.gstatic.com/firebasejs/${version}/firebase-${s}.js">`);
  writeFileSync(indexPath, html.replace(marker, links.join('\n  ')));
  return version;
}

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

// Before hashing: this rewrites index.html.
const firebaseVersion = preloadFirebaseSdk();

const files = {};
for (const full of walk(root).sort()) {
  const path = relative(root, full).split(sep).join('/');
  if (EXCLUDED.some((re) => re.test(path))) continue;
  files[path] = createHash('sha256').update(readFileSync(full)).digest('hex');
}

for (const required of ['index.html', 'flutter_bootstrap.js', 'main.dart.js']) {
  if (!files[required]) throw new Error(`${required} missing from ${root}`);
}

const bootstrap = readFileSync(join(root, 'flutter_bootstrap.js'), 'utf8');
const engine = bootstrap.match(/"engineRevision":"([0-9a-f]+)"/)?.[1];
if (!engine) throw new Error('engineRevision not found in flutter_bootstrap.js');

const build = createHash('sha256')
  .update(JSON.stringify(files))
  .digest('hex')
  .slice(0, 16);

const swPath = join(root, 'sw.js');
const placeholder = '/* __PRECACHE_MANIFEST__ */ null';
const sw = readFileSync(swPath, 'utf8');
if (!sw.includes(placeholder)) throw new Error(`placeholder missing in ${swPath}`);
writeFileSync(
  swPath,
  sw.replace(placeholder, JSON.stringify({build, engine, files})),
);

const bytes = Object.keys(files)
  .reduce((sum, p) => sum + statSync(join(root, p)).size, 0);
console.log(`sw.js pinned to build ${build}: ${Object.keys(files).length} files, ` +
  `${(bytes / 1e6).toFixed(1)} MB, engine ${engine.slice(0, 10)}, ` +
  `Firebase JS SDK ${firebaseVersion} preloaded`);
