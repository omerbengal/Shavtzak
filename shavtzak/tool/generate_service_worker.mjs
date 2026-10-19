// Pins build/web/sw.js to this build: writes {path: sha256} of every file the
// app loads into the worker's precache manifest (see web/sw.js).
//
// Run after `flutter build web`, from shavtzak/:
//   node tool/generate_service_worker.mjs [build/web]
// Fails (non-zero) rather than deploy a worker that would cache nothing or
// the wrong thing.

import {createHash} from 'node:crypto';
import {readFileSync, readdirSync, statSync, writeFileSync} from 'node:fs';
import {join, relative, sep} from 'node:path';

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
];

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

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
  `${(bytes / 1e6).toFixed(1)} MB, engine ${engine.slice(0, 10)}`);
