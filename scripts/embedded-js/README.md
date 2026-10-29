# Embedded JavaScript

The TypeScript files under `src/` are the source of truth for Den Browser's embedded JavaScript.

Edit these files:

```text
scripts/embedded-js/src/**/*.ts
```

Xcode's `Generate embedded JavaScript` build phase compiles the TypeScript sources and writes the generated files directly into the app bundle's Resources directory. `SheetRead.js` bundles Turndown and its GFM plugin with esbuild; other resources use the TypeScript compiler. The generated JavaScript is a build artifact and is not stored in Git.

The build phase requires the locked Node and pnpm toolchain from `mise.toml` and an installed `scripts/embedded-js/node_modules` directory. Install dependencies during project setup; the build phase does not access the network.

Build the app with `just build` or Xcode. Do not edit generated JavaScript directly.

Run `pnpm --dir scripts/embedded-js typecheck` for a standalone TypeScript check.

The decision is recorded in [ADR 0054](../../docs/adr/0054-keep-typescript-as-source-for-embedded-javascript.md).
