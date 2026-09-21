# Embedded JavaScript

The TypeScript files under `src/` are the source of truth for Den Browser's embedded JavaScript.

Edit these files:

```text
scripts/embedded-js/src/**/*.ts
```

Xcode's `Generate embedded JavaScript` build phase runs the TypeScript compiler and writes the generated files directly into the app bundle's Resources directory. The generated JavaScript is a build artifact and is not stored in Git.

The build phase requires the locked Node and pnpm toolchain from `mise.toml` and an installed `scripts/embedded-js/node_modules` directory. Install dependencies during project setup; the build phase does not access the network.

Build the app with `just build` or Xcode. Do not edit generated JavaScript directly.

The decision is recorded in [ADR 0054](../../docs/adr/0054-keep-typescript-as-source-for-embedded-javascript.md).
