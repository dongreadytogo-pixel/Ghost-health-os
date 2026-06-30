/**
 * Build a single, self-contained HTML file: the bundled JS and the sprite atlas
 * are inlined (atlas as a base64 data URI), so the result runs from a file://
 * URL or an inline preview with no external requests. Output: dist/standalone.html
 */
import { build } from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';

const res = await build({
  entryPoints: ['src/main.ts'],
  bundle: true,
  format: 'esm',
  minify: true,
  write: false,
});
const js = res.outputFiles[0].text;

const html = await readFile('index.html', 'utf8');
const png = await readFile('assets/0x72_dungeon.png');
const dataUri = `data:image/png;base64,${png.toString('base64')}`;

const inlined = html.replace(
  '<script type="module" src="./app.js"></script>',
  `<script>window.__ATLAS__=${JSON.stringify(dataUri)};</script>\n<script type="module">${js}</script>`,
);

await mkdir('dist', { recursive: true });
await writeFile('dist/standalone.html', inlined);
console.log('dist/standalone.html', (inlined.length / 1024).toFixed(1) + 'kb');
