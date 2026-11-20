// Renders one story into the app's site: shavtzak/web/stories/<id>.mp4
// (a <Composition>) or <id>.png (a <Still>, with --image).
//
//   npm run render -- tagging
//   npm run render -- some-screen --image
//
// Checks what the app expects: a video at most 30 s, portrait 1080 x 1920,
// H.264 (plays on every phone, iPhone included), no audio track.
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, statSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [id, ...flags] = process.argv.slice(2);
if (!id) {
  console.error('usage: npm run render -- <story id> [--image]');
  process.exit(1);
}
const image = flags.includes('--image');
const outDir = resolve(here, '../shavtzak/web/stories');
mkdirSync(outDir, {recursive: true});
const out = join(outDir, `${id}.${image ? 'png' : 'mp4'}`);
const cli = join(here, 'node_modules/.bin/remotion');
const shell = process.platform === 'win32';

const run = (args) => execFileSync(cli, args, {cwd: here, stdio: 'inherit', shell});

if (image) {
  run(['still', 'src/index.ts', id, out, '--image-format=png']);
} else {
  // A row of `remotion compositions`: "tagging  30  1080x1920  420 (14.00 sec)"
  const listing = execFileSync(cli, ['compositions', 'src/index.ts'], {cwd: here, shell})
    .toString()
    .replace(/\u001b\[[0-9;]*m/g, '');
  const row = listing
    .split(/\r?\n/)
    .map((line) => line.trim().split(/\s+/))
    .find((cells) => cells[0] === id);
  if (!row) throw new Error(`no composition "${id}" in src/Root.tsx`);
  const fps = Number(row[1]);
  const [width, height] = row[2].split('x').map(Number);
  const seconds = Number(row[3]) / fps;
  if (seconds > 30) throw new Error(`"${id}" is ${seconds} s; a story is at most 30 s`);
  if (width !== 1080 || height !== 1920) throw new Error(`"${id}" must be 1080 x 1920`);
  run(['render', 'src/index.ts', id, out, '--codec=h264', '--crf=24', '--pixel-format=yuv420p', '--muted']);
  console.log(`${seconds.toFixed(1)} s`);
}
if (!existsSync(out)) throw new Error(`nothing written to ${out}`);
console.log(`${out}  ${(statSync(out).size / 1024 / 1024).toFixed(2)} MB`);
