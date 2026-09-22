import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const packageRoot = resolve(import.meta.dirname);
const outputFlagIndex = process.argv.indexOf('--output-dir');
const outputDir = outputFlagIndex === -1 ? null : process.argv[outputFlagIndex + 1];

if (!outputDir) {
  throw new Error('Usage: node build.mjs --output-dir <directory>');
}

const tempRoot = await mkdtemp(resolve(tmpdir(), 'den-embedded-js-'));

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
    entry: 'src/picture-in-picture/entry.ts',
    output: 'PictureInPicture.js',
  },
];

try {
  await mkdir(resolve(outputDir), { recursive: true });

  for (const { entry, output } of entries) {
    let result;
    try {
      result = await execFileAsync('tsc', [
        '--ignoreConfig',
        '--target',
        'ES2022',
        '--lib',
        'DOM,ES2022',
        '--skipLibCheck',
        '--strict',
        '--removeComments',
        'false',
        '--outDir',
        tempRoot,
        '--rootDir',
        packageRoot,
        resolve(packageRoot, 'globals.d.ts'),
        resolve(packageRoot, entry),
      ]);
    } catch (error) {
      process.stderr.write(error.stdout || error.stderr || `${error.message}\n`);
      throw error;
    }
    const { stderr } = result;
    if (stderr) process.stderr.write(stderr);

    const generatedPath = resolve(tempRoot, entry).replace(/\.ts$/, '.js');
    await writeFile(
      resolve(outputDir, output),
      await readFile(generatedPath),
    );
  }
} finally {
  await rm(tempRoot, { force: true, recursive: true });
}

console.log(`Embedded JavaScript built (${entries.length} resources)`);
