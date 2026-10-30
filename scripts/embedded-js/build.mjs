import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const packageRoot = resolve(import.meta.dirname);
const outputFlagIndex = process.argv.indexOf('--output-dir');
const outputDir = outputFlagIndex === -1 ? null : process.argv[outputFlagIndex + 1];

if (!outputDir) {
  throw new Error('Usage: bun build.mjs --output-dir <directory>');
}

// Bun transpilation does not check types. Keep the pinned compiler as the gate.
const check = Bun.spawnSync([
  process.execPath, resolve(packageRoot, 'node_modules/typescript/bin/tsc'),
  '--project', resolve(packageRoot, 'tsconfig.json'), '--pretty', 'false',
], { stdout: 'inherit', stderr: 'inherit' });
if (check.exitCode !== 0) process.exit(check.exitCode || 1);

const license = `/* Turndown and turndown-plugin-gfm; includes collapse-whitespace\nCopyright (c) 2014 Luc Thevenard <lucthevenard@gmail.com>\n${await readFile(resolve(packageRoot, 'node_modules/turndown/LICENSE'), 'utf8')}*/`;
const entries = [
  {
    entry: 'src/sheet-dom/entry.ts',
    output: 'SheetDOM.js',
  },
  {
    entry: 'src/sheet-navigation/entry.ts',
    output: 'SheetNavigation.js',
  },
  {
    entry: 'src/picture-in-picture/browser.ts',
    output: 'PictureInPicture.js',
  },
  {
    entry: 'src/inspection/entry.ts',
    output: 'InspectionAgent.js',
  },
  {
    entry: 'src/sheet-read/browser.ts',
    output: 'SheetRead.js',
    banner: license,
  },
];

await mkdir(resolve(outputDir), { recursive: true });
for (const { entry, output, ...options } of entries) {
  const result = await Bun.build({
    entrypoints: [resolve(packageRoot, entry)],
    target: 'browser',
    format: 'iife',
    ...options,
  });
  if (!result.success) throw new AggregateError(result.logs, `${output} bundle failed`);
  await writeFile(resolve(outputDir, output), await result.outputs[0].text());
}

console.log(`Embedded JavaScript built (${entries.length} resources)`);
