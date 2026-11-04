# Embedded JavaScript

The TypeScript files under `src/` are the source of truth for Den Browser's embedded JavaScript.

Edit these files:

```text
scripts/embedded-js/src/**/*.ts
```

Xcode's `Generate embedded JavaScript` build phase compiles the TypeScript sources and writes the generated files directly into the app bundle's Resources directory. All six resources are bundled as IIFEs with Bun. `DenAPI.js` supplies the injected `window.den` API described in [Den JavaScript API](../../docs/den-api.md). `SheetRead.js` includes Turndown and its GFM plugin and exposes `denSheetRead.read`. `PictureInPicture.js` exposes `denPictureInPicture.run(mode)`, whose result is explicitly awaited by the native caller. The pinned TypeScript compiler checks all sources before generation. The generated JavaScript is a build artifact and is not stored in Git.

The build phase requires mise and the pinned Bun version from `mise.toml`. It installs the locked dependencies before generation; the first build may need network access. The `web/` site uses Vite+ (`vp`).

Build the app with `just build` or Xcode. Do not edit generated JavaScript directly.

Run `just embedded-js-typecheck` for a standalone TypeScript check.

To check generated resource contracts independently of Xcode:

```sh
bun run --cwd scripts/embedded-js build --output-dir /tmp/den-embedded-js
DEN_EMBEDDED_JS_OUTPUT_DIR=/tmp/den-embedded-js bun run --cwd scripts/embedded-js verify
```

The verification command reports resource syntax, public API, license, and PictureInPicture completion tests separately. Set `DEN_EMBEDDED_JS_OUTPUT_DIR` to another output directory to check a different build.

The TypeScript source-of-truth decision is recorded in [ADR 0054](../../docs/adr/0054-keep-typescript-as-source-for-embedded-javascript.md).
