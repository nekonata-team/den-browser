# Den Browser agent guide

## Project

Den Browser is a macOS-first companion browser for long-running web work. It is a SwiftUI app with AppKit bridges and `WKWebView`.

Read [CONTEXT.md](./CONTEXT.md) before changing product behavior or user-visible wording. It defines project terms such as Den, Desk, Board, and Sheet; do not replace them with browser-tab language.

## Platform baseline

The minimum supported platform is macOS 26.0 for the app and its tests.

- Do not add `#available` or `@available` branches for macOS versions below 26.0.
- Do not add availability checks whose condition is guaranteed by the 26.0 deployment target, such as `if #available(macOS 26.0, *)`.
- Do not keep fallback code for paths that cannot be reached on the supported platform.
- Runtime capability checks for private or optional APIs, such as `responds(to:)`, are separate and require a concrete reason.
- If the minimum macOS version changes, update this rule and the related architecture decision before adding compatibility paths.

## Implementation flow

1. Read `CONTEXT.md`, `docs/architecture.md`, relevant ADRs in `docs/adr/`, and affected code/tests.
2. Keep persisted `DenState` separate from live `BoardRuntime`/`WKWebView` objects.
3. Add or update focused unit tests for stable `DenStore` behavior.
4. Choose validation in proportion to the change. Run `just check` before handoff for Swift source, Xcode settings, or test and validation configuration changes. Otherwise, run focused validation that exercises the changed behavior.

## Commands

Run `just --list`. These commands are preferred for use in this project.

## Release

Read `docs/releasing.md`, then use `just release prepare X.Y.Z` and, after
manual candidate verification, `just release publish X.Y.Z`.

## Docs

- `README.md`: English product and PoC overview
- `README.ja.md`: Japanese product and PoC overview
- `CONTEXT.md`: required domain language
- `DESIGN.md`: UI design rules
- `docs/testing.md`: automated and exploratory validation

Keep `README.md` and `README.ja.md` aligned in structure and product facts. Update both when user-visible features, status, requirements, or documentation links change. Write natural copy in each language rather than translating literally.

@RTK.md
