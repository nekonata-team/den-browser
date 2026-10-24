# Den Browser agent guide

## Project

Den Browser is a macOS-first companion browser for long-running web and terminal work. It is a SwiftUI app with AppKit bridges and `WKWebView`.

Read [CONTEXT.md](./CONTEXT.md) when changing product behavior or user-visible wording. It defines project terms such as Den, Desk, Board, and Sheet; do not replace them with browser-tab language.

## Platform baseline

The minimum supported platform is macOS 26.0 for the app and its tests.

- Do not add availability annotations, checks, or fallback paths made unnecessary by the macOS 26.0 deployment target.
- Runtime capability checks for private or optional APIs, such as `responds(to:)`, are separate and require a concrete reason.
- If the minimum macOS version changes, update this rule and the related architecture decision before adding compatibility paths.

## Commands

Run `just --list` when choosing a project task; reuse the result while the justfile is unchanged.

## Validation

Run `just check` before handoff for Swift source, Xcode settings, or test and validation configuration changes.
Otherwise, run focused validation that exercises the changed behavior.
Reuse successful checks when the final diff does not affect what they cover.

## Docs

- `README.md`: English public product entry point
- `README.ja.md`: Japanese public product entry point
- `CONTEXT.md`: required domain language
- `DESIGN.md`: UI design rules
- `docs/shortcuts.md`: complete keyboard and pointer controls
- `docs/keyboard-input.md`: keyboard implementation contract and diagnostic path; read before changing keyboard routing, Commands, shortcut recording, or local key handling
- `docs/desk-presets.md`: desk preset behavior and state
- `docs/vim.md`: Vim-style sheet navigation
- `docs/persistence.md`: local persistence and preference schema
- `docs/architecture.md`: package structure, dependency direction, responsibility boundaries, and state/runtime ownership; read before implementation changes
  Keep its text and Mermaid diagrams consistent.
- `docs/adr/`: reasons and trade-offs behind architecture and product decisions; read relevant ADRs when changing architectural boundaries
- `scripts/embedded-js/README.md`: TypeScript sources and generated JavaScript resource workflow
- `docs/cli.md`: command-line interface specification and agent integration
- `docs/mcp.md`: MCP server interface and tool reference
- `docs/testing.md`: automated and exploratory validation; read before test changes and follow its XCUITest admission rule
- `docs/releasing.md`: signed release and publishing workflow
- `web/README.md`: public website and deployment
- `.agents/skills/den`: limit this end-user agent skill to capability discovery and pointers to command `--help` or reference material. Do not include the project path.

## Documentation operation

- Use the `domain-modeling` skill when changing domain terms, their meanings, or architectural decisions in `CONTEXT.md` or ADRs.
- Before editing ADRs, read and follow the [ADR template](./.agents/skills/domain-modeling/ADR-FORMAT.md).
- Keep `docs/architecture.md` limited to current architectural contracts. Put decision rationale in ADRs;
  omit refactor history, change justification, and source-level wiring explanations.
- Before adding architecture prose, check the existing graph, responsibility table, and owning section.
  Update the existing statement in place; omit prose that only repeats those representations or the code.
- Do not commit agent notes, work logs, or unsettled plans.
- Keep README focused on public product information and documentation links.
- Keep detailed behavior and implementation contracts in their owning documents.
- Update existing documentation when a change makes its content inaccurate.
- Update affected tests when behavior changes.
- Keep `README.md` and `README.ja.md` aligned in structure and product facts.
  Write natural copy in each language.
- Before handoff, check changed documentation links and inspect the final diff
  for duplicated or stale product claims.

@RTK.md
