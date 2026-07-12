# Den Browser agent guide

## Project

Den Browser is a macOS-first companion browser for long-running web work. It is a SwiftUI app with AppKit bridges and `WKWebView`.

Read [CONTEXT.md](./CONTEXT.md) before changing product behavior or user-visible wording. It defines project terms such as Den, Desk, Board, and Sheet; do not replace them with browser-tab language.

## Implementation flow

1. Read `CONTEXT.md`, relevant ADRs in `docs/adr/`, and affected code/tests.
2. Keep persisted `DenState` separate from live `BoardRuntime`/`WKWebView` objects.
3. Add or update focused unit tests for stable `DenStore` behavior.
4. Swift code, Xcode settings, or validation tasks changed: run `just check` before handoff. For UI/WebKit changes, also perform applicable steps in `docs/poc.md`.
5. Update `backlog.md` only when acting as manager; implementers leave it unchanged.

## Commands

Use `just build`, `just test`, and `just check` from repository root. They disable code signing and write build output to `.derived-data`.

## Docs

- `README.md`: product and PoC overview
- `CONTEXT.md`: required domain language
- `DESIGN.md`: UI design rules
- `docs/testing.md`: automated and exploratory validation
