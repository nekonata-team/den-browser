# PoC Decision

## Question

Can a macOS `WKWebView` implementation support Den's interaction model for long-running web work?

This document defines outcome-level PoC criteria. Validation procedures belong in tests or exploratory sessions.

## Success criteria

- ChatGPT, Gemini, and Claude logins remain available after app restart.
- Two Profiles can stay signed into different identities on the same site, and both identities survive restart.
- Each Profile restores its own Den without duplicating windows or mixing state.
- Multiple Boards can remain open while keyboard input, focus changes, and Board navigation stay usable.
- Moving between Boards or Desks preserves each Board's live Sheet state, including in-progress text.
- The core Den workflow—opening a Board, selecting and moving between Boards and Desks, focusing its Sheet, and removing a Board—can be completed with pointer-only input and keyboard-only input.
- App restart restores Desks, Board order, Board labels, Board widths, Current Sheet URLs, and focused Board.
- Back and forward navigation can be treated as a Sheet stack.
- Web, Terminal, and Zellij Boards can coexist with the same Den lifecycle and persistence model.
- The Drawer, Desk, and Profile boundaries remain reliable during ordinary long-running work.
- Focus Mode keeps the Focused Board readable while visually de-emphasizing other Board content without breaking Board focus or input.

## Constraints

- Den controls must remain usable while a Sheet has WebKit focus.
- Persisted `DenState` must remain separate from live `BoardRuntime` and `WKWebView` objects.
- WebKit-specific behavior, authentication, IME, rendering, and resource use require exploratory validation in addition to automated tests.
- Focus Mode rendering across Web and Terminal Boards, accessibility, and resource use require exploratory validation.

## Evidence

- Stable state transitions, persistence, parsing, and lifecycle behavior are covered by unit tests.
- Native SwiftUI workflows are covered by focused UI tests.
- WebKit integration, external authentication, visual behavior, IME, and long-running resource use are checked exploratorily.
- The test responsibilities and validation boundaries are defined in [testing.md](./testing.md).

## Fail conditions

- AI chat logins cannot be kept across app restarts.
- Den shortcuts cannot work reliably while web content has focus.
- WebKit constraints create a major hole in the core Desk, Board, or Sheet experience.
- Multiple Boards make ordinary interaction clearly unusable.
- Liquid Glass overlays cannot remain legible or accessible over embedded WebKit content.
- Focus Mode makes non-focused Board content unreadable, breaks direct manipulation, or causes unacceptable rendering or resource regressions.

## Decision

Status: In progress.

Continue the PoC while the success criteria hold. Revisit the interaction model when a fail condition affects the core Den experience.
