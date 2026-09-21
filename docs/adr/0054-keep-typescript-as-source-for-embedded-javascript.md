---
status: accepted
---

# Keep TypeScript as the source for embedded JavaScript

Den Browser embeds JavaScript resources in the Xcode application bundle, but editing those resources directly makes type and native integration errors easy to miss. Keep the TypeScript files under `scripts/embedded-js/src/` as the editable source, and generate the JavaScript resources during the Xcode build directly into the application bundle.

## Considered Options

- Continue editing the JavaScript resources directly and rely on syntax checks.
- Keep TypeScript as the source and use a separate bundler with native build dependencies.
- Keep TypeScript as the source and use the locked TypeScript compiler CLI to transpile the standalone scripts in an Xcode build phase.

The third option keeps the existing resource boundaries and avoids a native bundler dependency. Node and pnpm versions remain managed by mise, while TypeScript remains a project dependency because the build phase invokes its compiler CLI. Dependency installation remains outside the build phase and does not use the network.

## Consequences

Developers edit only `scripts/embedded-js/src/**/*.ts`. Xcode generates the JavaScript resources into the application bundle for every build, so generated JavaScript is not committed and cannot become stale independently of its TypeScript source.
