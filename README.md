[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Web work, the Niri way.**

A keyboard-first spatial browser for people working across multiple web tasks.

> **Status:** Functional macOS proof of concept under active development.

Den Browser is built for web work that stays open for a long time: AI chats, research, development, writing, documentation, and other workflows with several ongoing contexts. Instead of collecting those contexts in a tab list, Den Browser arranges them as persistent work surfaces that you can navigate and organize from the keyboard.

Den Browser complements Safari, Chrome, or another general-purpose browser rather than replacing one. Use your usual browser for everyday browsing and Den Browser for work that benefits from spatial memory and long-lived context.

## Installation

Den Browser requires macOS 26 or later.

```sh
brew tap nekonata-team/tap
brew install --cask den-browser
```

Upgrade with `brew upgrade --cask den-browser`.

## Inspired by Niri

Den Browser applies ideas from [Niri](https://github.com/niri-wm/niri)'s spatial window management to web work. Niri workspaces map loosely to Desks, and Niri windows map loosely to Boards. The mapping is intentionally not exact: Den Browser uses a paper-workspace model designed around web tasks, navigation history, and restoration.

## Work model

- **Profile**: An isolated web identity with its own Den, sign-ins, and site data.
- **Den**: The full work environment for one Profile.
- **Desk**: A broad work context containing Boards in a horizontal work area.
- **Desk Preset**: A reusable starting arrangement for creating a Desk.
- **Board**: An intentional work surface for one focused task context.
- **Sheet**: A web screen held within a Board.
- **Sheet Stack**: The back-forward sequence of Sheets within a Board.

See [CONTEXT.md](./CONTEXT.md) for the complete product language.

## Current features

- Arrange Boards spatially across multiple Desks.
- Create named, color-coded Profiles, each with one Den window and isolated website data.
- See the current Profile in the titlebar, and open or find Profiles from the top-right icon, Profile menu, or `Control` + `Command` + `P`.
- Navigate between neighboring Boards with `Command` + `Option` + Left / Right, add Shift to reorder them, remove the Focused Board with `Command` + `W`, and use Den Mode for the full set of Board operations. `Shift` + `Command` + `W` closes the Profile window. Pointer controls support Sheet Stack navigation, Board Removal, same-Desk header dragging, and a Board action menu from any Board header.
- Customize the five app-wide Den and Board shortcuts in Settings, reset them individually or together, and open the complete shortcut guide from Settings, the Den menu, or `?` in Den Mode.
- Choose whether Den follows the macOS motion setting, uses Standard Motion, or uses Reduced Motion in Appearance settings.
- Toggle Zen View with `z` in Den Mode to hide the Desk switcher and Profile control without hiding the titlebar.
- Resize every Board in the Focused Desk to fit a chosen count across the current window, using `w` then `1` through `9` in Den Mode or the Den menu.
- Restore the most Recently Removed Board with `u` during the current app run.
- See and reorganize Boards across Desks in Overview.
- Delete empty Desks immediately, or delete a Desk containing Boards after confirming the permanent removal.
- Save the Focused Desk as a Profile-owned Personal Desk Preset, then use keyboard-first fuzzy search to choose and preview a preset before naming another Desk. Presets can also be replaced or deleted, with direct management available through Shift + `p` in Den Mode. Built-in Empty, ChatGPT, and Gemini presets provide ready-made starting points.
- Keep browser-like back-forward navigation inside each Board as a Sheet Stack.
- Restore Desk and Board labels, order, widths, focus, and current Sheet URLs after relaunching the app, showing the Focused Board immediately without a scroll animation.
- Keep sign-ins across app launches while isolating them between Profiles.
- Optionally enable first-party Vim-style Sheet Navigation for scrolling, link hints, find, Sheet Stack navigation, and URL actions.

## Keyboard operation

Press `Control` + `,` to toggle Den Mode. Den Mode receives Desk and Board commands independently of keyboard focus inside the Current Sheet. `n` or `Space` opens a Board, `p` saves the Focused Desk as a Desk Preset, `w` then a digit resizes all Boards in the Focused Desk to fit the current window, `x` or `d` removes the Focused Board, `u` restores the Recently Removed Board, `?` opens the shortcut guide, and `z` toggles Zen View. Escape returns to Sheet Input.

See [docs/shortcuts.md](./docs/shortcuts.md) for the complete shortcut map.

Vim-style Sheet Navigation is a separate optional Feature. It controls content inside the Current Sheet and is disabled by default. See [docs/vim.md](./docs/vim.md) for supported commands.

## Current scope

- Requires macOS 26 or later.
- Stores Profile and Den state locally under Application Support; app preferences remain shared across Profiles.
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

These commands disable code signing.

For optional Neovim SourceKit-LSP support:

```sh
brew install xcode-build-server
just lsp-config
```

Build the project in Xcode first so SourceKit-LSP can use its build log and index.

## Project documentation

- [CONTEXT.md](./CONTEXT.md): product language and domain model
- [DESIGN.md](./DESIGN.md): visual and interaction rules
- [docs/shortcuts.md](./docs/shortcuts.md): Den Mode keyboard commands
- [docs/desk-presets.md](./docs/desk-presets.md): Desk Preset behavior and scope
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/poc.md](./docs/poc.md): proof-of-concept criteria
- [docs/testing.md](./docs/testing.md): automated and exploratory validation
- [docs/releasing.md](./docs/releasing.md): signed release and Homebrew Tap workflow
- [docs/adr](./docs/adr): product and architecture decisions
