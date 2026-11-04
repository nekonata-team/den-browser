import { describe, expect, test } from 'bun:test';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import vm from 'node:vm';

const outputDir = process.env.DEN_EMBEDDED_JS_OUTPUT_DIR;
if (!outputDir) throw new Error('Set DEN_EMBEDDED_JS_OUTPUT_DIR to the generated resource directory');
const source = name => readFile(resolve(outputDir, name), 'utf8');
const names = ['DenAPI.js', 'InspectionAgent.js', 'PictureInPicture.js', 'SheetDOM.js', 'SheetNavigation.js', 'SheetRead.js'];

describe('generated resources', () => {
  test('generates the embedded resources', async () => {
    expect((await readdir(outputDir)).sort()).toEqual(names);
  });

  test.each(names)('%s is a classic script', async name => {
    const script = await source(name);
    expect(() => new vm.Script(script)).not.toThrow();
  });
});

describe('public API', () => {
  test('Den Toast defaults to info and forwards an explicit severity', async () => {
    const messages = [];
    const context = vm.createContext({
      window: {},
      denAPITransport: { postMessage: async message => { messages.push(message); } },
    });
    vm.runInContext(await source('DenAPI.js'), context);
    await vm.runInContext('window.den.toast.show("Saved")', context);
    await vm.runInContext('window.den.toast.show("Could not save", { severity: "error" })', context);
    expect(JSON.parse(JSON.stringify(messages))).toEqual([
      { action: 'toast.show', message: 'Saved', severity: 'info' },
      { action: 'toast.show', message: 'Could not save', severity: 'error' },
    ]);
  });

  test('Den API forwards Board focus and propagates native errors', async () => {
    const messages = [];
    const context = vm.createContext({
      window: {},
      denAPITransport: { postMessage: async message => {
        messages.push(message);
        if (message.boardId === 'missing') throw new Error('Board not found');
        return null;
      } },
    });
    vm.runInContext(await source('DenAPI.js'), context);
    await vm.runInContext('window.den.boards.focus("board-id")', context);
    expect(JSON.parse(JSON.stringify(messages))).toEqual([{ action: 'board.focus', boardId: 'board-id' }]);
    await expect(vm.runInContext('window.den.boards.focus("missing")', context)).rejects.toThrow('Board not found');
  });

  test('publishes read without a module loader and supports repeated evaluation', async () => {
    const script = await source('SheetRead.js');
    const context = vm.createContext({ document: {} });
    for (let i = 0; i < 2; i++) {
      vm.runInContext(script, context);
      expect(vm.runInContext('typeof denSheetRead.read', context)).toBe('function');
      expect(vm.runInContext('denSheetRead.text()', context)).toBe('');
      expect(() => vm.runInContext('denSheetRead.read(null)', context)).toThrow(/HTML body/);
    }
  });

  test('publishes the SheetDOM ref resolver', async () => {
    const context = vm.createContext({ window: {} });
    vm.runInContext(await source('SheetDOM.js'), context);
    expect(vm.runInContext('typeof window.__denSheetDOM.denResolveRef', context)).toBe('function');
  });
});

describe('licenses', () => {
  test.each(['turndown', 'turndown-plugin-gfm'])('includes the full %s license', async dependency => {
    const license = await readFile(new URL(`./node_modules/${dependency}/LICENSE`, import.meta.url), 'utf8');
    expect(await source('SheetRead.js')).toContain(license);
  });

  test('retains the collapse-whitespace attribution and GFM identification', async () => {
    const script = await source('SheetRead.js');
    expect(script).toContain('Copyright (c) 2014 Luc Thevenard');
    expect(script).toContain('turndown-plugin-gfm');
  });
});

// Mirror the native call: install the bundle, then explicitly await the public function.
async function pip(mode, document) {
  const script = await source('PictureInPicture.js');
  const value = vm.runInNewContext(`(function () { ${script}\nreturn denPictureInPicture.run(mode); })()`, { document, mode });
  expect(typeof value?.then).toBe('function');
  return await value;
}

describe('PictureInPicture completion', () => {
  test('enter reports no playing video', async () => {
    expect(await pip('enter', { querySelectorAll: () => [] })).toBe('no-playing-video');
  });

  test('toggle rejects when there is no video', async () => {
    await expect(pip('toggle', { querySelectorAll: () => [] })).rejects.toThrow(/NO_VIDEO/);
  });

  test('enter requests standard PiP and returns its result', async () => {
    let entered = false;
    const video = { paused: false, ended: false, readyState: 2, requestPictureInPicture: async () => { entered = true; } };
    expect(await pip('enter', { querySelectorAll: () => [video], pictureInPictureEnabled: true })).toBe('entered-standard');
    expect(entered).toBe(true);
  });

  test('exit leaves PiP and returns its result', async () => {
    let exited = false;
    const video = {};
    const document = { querySelectorAll: () => [video], pictureInPictureElement: video, exitPictureInPicture: async () => { exited = true; } };
    expect(await pip('exit', document)).toBe('exited');
    expect(exited).toBe(true);
  });
});
