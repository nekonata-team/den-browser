# Den Browser

Den Browser is a macOS-first companion browser for long-running parallel web work. It is not trying to replace a general-purpose browser; it is a personal work den for sessions that benefit from spatial memory, keyboard navigation, and long-lived context.

The first MVP focuses on AI chat workflows because they naturally involve multiple independent web sessions that stay open for a long time. Den Browser should eventually support research, development, writing, documentation work, and other web-heavy workflows.

## Concept

Den Browser uses a paper-workspace metaphor instead of conventional browser tabs.

- **Den**: the full personal work environment.
- **Desk**: a broad work context within the den.
- **Board**: a user-created work surface for one focused task context.
- **Sheet**: a web screen held within a board.
- **Sheet Stack**: the back-forward sequence of sheets within one board.

The detailed project language lives in [CONTEXT.md](./CONTEXT.md).

## Product Principles

- Den operations are keyboard-first; pointer interactions are supporting tools.
- Boards are intentional task contexts, not automatic byproducts of navigation.
- Browser-like back and forward history stays inside a board as a sheet stack.
- Desks and boards preserve spatial memory instead of reordering themselves by recency.
- The MVP targets macOS 26 or later and uses Liquid Glass for Den controls, not for sheet content.
- The MVP uses one shared persistent web profile; profile separation is a later feature.

## MVP Direction

The first implementation is a macOS desktop PoC using SwiftUI, AppKit bridges, and WKWebView.

Core PoC goals:

- Keep AI chat logins after app restart.
- Open multiple boards at once.
- Navigate desks and boards from the keyboard.
- Preserve board labels, widths, order, focused state, and current sheet URLs.
- Verify Liquid Glass controls remain readable over live WKWebView content.

See [docs/poc.md](./docs/poc.md) for the current PoC criteria.
See [docs/testing.md](./docs/testing.md) for automated checks and the human PoC harness.

## Decisions

Architecture and product decisions are recorded as ADRs in [docs/adr](./docs/adr):

- Den Browser is a companion browser, not a browser replacement.
- Den Browser uses a paper workspace metaphor inspired by Niri-style spatial window management.
- Den operations are keyboard-first.
- The MVP is a macOS-first desktop app.
- The MVP uses one shared web profile.
- The MVP PoC uses WKWebView.
- The app is SwiftUI-first with AppKit bridges.
- Persisted Den state is separate from live WebView runtime objects.
