# Den Browser agent guide

## Project

Den Browser is a macOS-first companion browser for long-running web and terminal work. It is a SwiftUI app with AppKit bridges and `WKWebView`.

Read [CONTEXT.md](./CONTEXT.md) when changing product behavior or user-visible wording. Do not replace project terms (Den, Desk, Board, Sheet) with browser-tab language.

## Platform baseline

The minimum supported platform is macOS 26.0 for the app and its tests. Do not add availability checks or fallback paths for earlier versions.
Runtime capability checks for private or optional APIs, such as `responds(to:)`, require a concrete reason.

## Commands

Run `just --list` when choosing a project task.

## Validation

Run `just check` before requesting review for Swift source, Xcode settings, or test and validation configuration changes.
Otherwise, run focused validation that exercises the changed behavior.

## Docs

- `README.md`: English public product entry point
- `README.ja.md`: Japanese public product entry point
- `CONTEXT.md`: required domain language
- `DESIGN.md`: UI design rules
- `docs/shortcuts.md`: complete keyboard and pointer controls
- `docs/keyboard-input.md`: keyboard routing, commands, shortcut recording, and diagnostics
- `docs/desk-presets.md`: desk preset behavior and state
- `docs/vim.md`: Vim-style sheet navigation
- `docs/persistence.md`: local persistence and preference schema
- `docs/architecture.md`: package structure, dependency boundaries, and state/runtime ownership
- `docs/adr/`: architecture and product decision records
- `scripts/embedded-js/README.md`: TypeScript sources and generated JavaScript resource workflow
- `docs/cli.md`: CLI specification and agent integration
- `docs/mcp.md`: MCP server interface and tool reference
- `docs/testing.md`: automated and exploratory validation, including XCUITest admission rules
- `docs/releasing.md`: signed release and publishing workflow
- `web/README.md`: public website and deployment
- `skills/den`: end-user agent skill; limit to discovery and pointers without project paths

## Documentation operation

- Use the `domain-modeling` skill and follow the [ADR template](./.agents/skills/domain-modeling/ADR-FORMAT.md) when changing domain terms, their meanings, or architectural decisions in `CONTEXT.md` or ADRs.
- Keep `docs/architecture.md` limited to current architectural contracts and diagrams. Put decision rationale in ADRs; omit refactor history and prose that duplicates code.
- Keep `README.md` and `README.ja.md` aligned in structure and product facts, focused on public product information and doc links. Write natural copy in each language.
- Before requesting review, check changed documentation links and inspect the final diff for duplicated or stale claims.

