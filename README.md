[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Web work, the Niri way.**

A keyboard-first spatial browser for people working across multiple web tasks.

> **Status:** Functional macOS proof of concept under active development.

Den Browser is built for web work that stays open for a long time: AI chats, research, development, writing, documentation, and other workflows with several ongoing contexts. Instead of collecting those contexts in a tab list, Den Browser arranges them as persistent work surfaces that you can navigate and organize from the keyboard.

Den Browser complements Safari, Chrome, or another general-purpose browser rather than replacing one. Use your usual browser for everyday browsing and Den Browser for work that benefits from spatial memory and long-lived context.

## Inspired by Niri

Den Browser applies ideas from [Niri](https://github.com/niri-wm/niri)'s spatial window management to web work. Niri workspaces map loosely to Desks, and Niri windows map loosely to Boards. The mapping is intentionally not exact: Den Browser uses a paper-workspace model designed around web tasks, navigation history, and restoration.

## Work model

- **Den**: Your full personal work environment.
- **Desk**: A broad work context containing Boards in a horizontal work area.
- **Board**: An intentional work surface for one focused task context.
- **Sheet**: A web screen held within a Board.
- **Sheet Stack**: The back-forward sequence of Sheets within a Board.

See [CONTEXT.md](./CONTEXT.md) for the complete product language.

## Current features

- Arrange Boards spatially across multiple Desks.
- Navigate, move, resize, duplicate, cut, place, restore, and close Boards from Den Mode.
- See and reorganize Boards across Desks in Overview.
- Keep browser-like back-forward navigation inside each Board as a Sheet Stack.
- Restore Desk and Board labels, order, widths, focus, and current Sheet URLs after relaunching the app.
- Keep sign-ins across app launches with one shared persistent web profile across Sheets.
- Optionally enable first-party Vim-style Sheet Navigation for scrolling, link hints, find, Sheet Stack navigation, and URL actions.

## Keyboard operation

Press `Control` + `.` to enter Den Mode. Den Mode receives Desk and Board commands independently of keyboard focus inside the Current Sheet. Press `Escape` to return to Sheet input.

See [docs/shortcuts.md](./docs/shortcuts.md) for the complete Den Mode shortcut map.

Vim-style Sheet Navigation is a separate optional Feature. It controls content inside the Current Sheet and is disabled by default. See [docs/vim.md](./docs/vim.md) for supported commands.

## Current scope

- Requires macOS 26 or later.
- Uses one shared persistent web profile; profile separation is not yet supported.
- Focuses on long-running parallel web work, not the full feature set of a general-purpose browser.
- Remains a proof of concept while WebKit compatibility, performance, accessibility, and visual behavior receive further validation.

The current acceptance criteria and exploratory checks live in [docs/poc.md](./docs/poc.md).

## Development

Den Browser is a macOS app built with SwiftUI, AppKit bridges, and `WKWebView`.

```sh
just build
just test
just check
```

These commands disable code signing and write build output to `.derived-data`.

## Project documentation

- [CONTEXT.md](./CONTEXT.md): product language and domain model
- [DESIGN.md](./DESIGN.md): visual and interaction rules
- [docs/shortcuts.md](./docs/shortcuts.md): Den Mode keyboard commands
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/poc.md](./docs/poc.md): proof-of-concept criteria
- [docs/testing.md](./docs/testing.md): automated and exploratory validation
- [docs/adr](./docs/adr): product and architecture decisions
