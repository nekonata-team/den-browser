---
status: accepted
---

# Keep TypeScript as the source for embedded JavaScript

Den Browser embeds JavaScript resources in the Xcode application bundle, but editing those resources directly makes type and native integration errors easy to miss. Keep the TypeScript files under `scripts/embedded-js/src/` as the editable source, and generate the JavaScript resources during the Xcode build directly into the application bundle.

## Considered Options

- Continue editing the JavaScript resources directly and rely on syntax checks.
- Keep TypeScript as the source and use a separate bundler with native build dependencies.
- Keep TypeScript as the source and use the locked TypeScript compiler CLI to transpile the standalone scripts in an Xcode build phase.
- Keep TypeScript as the source, use Bun for dependency management and all resource bundles, and retain the locked TypeScript compiler for type checking.

The fourth option keeps the existing resource boundaries while using a Bun version pinned by mise for dependency management and bundling. TypeScript remains a project dependency for type checking before generation. Dependency installation remains outside the build phase; generation uses installed dependencies without network access.

## Consequences

Developers edit only `scripts/embedded-js/src/**/*.ts`. Xcode regenerates the JavaScript resources in the application bundle when the declared inputs change; generated JavaScript is not committed.

All resources use IIFE bundles to isolate their internal variables. Native callers use explicitly published functions and await asynchronous results, so those results do not depend on the generated script layout.
