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

1. Read `CONTEXT.md`, `docs/architecture.md`, relevant ADRs in `docs/adr/`, and affected code/tests. Read `docs/testing.md` before choosing a test strategy or adding/updating UI tests. For every XCUITest, record the native UI boundary it protects and why a unit test cannot observe the failure; ordinary Button clicks do not qualify. Read `docs/keyboard-input.md` before changing keyboard routing, Commands, shortcut recording, or local key handling.
2. Keep persisted `DenState` separate from live `BoardRuntime`/`WKWebView` objects.
3. Add or update focused unit tests for stable `DenStore` behavior.
4. Choose validation in proportion to the change. Run `just check` before handoff for Swift source, Xcode settings, or test and validation configuration changes. Otherwise, run focused validation that exercises the changed behavior.

## Commands

Run `just --list`. These commands are preferred for use in this project.

## Release

Read `docs/releasing.md`, then use `just release prepare X.Y.Z` and, after
manual candidate verification, `just release publish X.Y.Z`.

## Docs

- `README.md`: English public product entry point
- `README.ja.md`: Japanese public product entry point
- `CONTEXT.md`: required domain language
- `DESIGN.md`: UI design rules
- `docs/shortcuts.md`: complete keyboard and pointer controls
- `docs/keyboard-input.md`: keyboard implementation contract and diagnostic path
- `docs/poc.md`: current acceptance criteria and exploratory checks
- `docs/architecture.md` and `docs/adr/`: architecture and product decisions
- `docs/testing.md`: automated and exploratory validation
- `docs/releasing.md`: signed release and publishing workflow

## Documentation operation

- Use the `domain-modeling` skill when creating or updating `CONTEXT.md` or ADRs.
- Keep README focused on product positioning, target work, status, requirements,
  installation, core concepts, a short feature summary, and entry-point links.
- Do not add exhaustive feature lists, shortcut maps, implementation details, or
  PoC test cases to README. Put them in their owning document above.
- When behavior changes, update the owning source-of-truth document and affected
  tests. Update README only when public positioning, status, requirements,
  installation, core concepts, or documentation entry points change.
- Keep `README.md` and `README.ja.md` aligned in structure and product facts.
  Write natural copy in each language; do not translate feature inventories
  mechanically.
- Before handoff, check changed documentation links and inspect the final diff
  for duplicated or stale product claims.

@RTK.md
