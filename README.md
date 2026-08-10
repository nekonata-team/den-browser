[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Web and terminal work, the Niri way.**

Den Browser is a keyboard-first spatial browser for long-running web and terminal work. It
keeps parallel tasks as persistent work surfaces instead of growing tab and terminal-window lists,
so research, AI chats, development, writing, and documentation stay easy to
revisit.

> **Status:** Functional macOS proof of concept under active development.

Den Browser complements Safari, Chrome, or another general-purpose browser. It
is for work that benefits from spatial memory and long-lived context, not for
replacing everyday browsing.

## Installation

Den Browser requires macOS 26 or later.

```sh
brew tap nekonata-team/tap
brew install --cask den-browser
```

Upgrade with `brew upgrade --cask den-browser`.

## Core model

- **Profile**: An isolated web identity with its own sign-ins, site data, and
  Den.
- **Den**: The complete work environment for one Profile.
- **Desk**: A broad work context containing Boards in a horizontal work area.
- **Board**: A persistent work surface containing Web Sheets or a Terminal Session.
- **Sheet**: A web screen held within a Board.

Den Browser draws loosely on [Niri](https://github.com/niri-wm/niri)'s spatial
window management. Its paper-workspace model is designed around web tasks,
navigation history, and restoration. See [CONTEXT.md](./CONTEXT.md) for the
complete product language.

## What Den Browser provides

- Persistent spatial organization across multiple Desks.
- Web and Terminal Boards side by side in one Desk.
- Keyboard-first navigation and Board management, with pointer controls where
  useful.
- Profile-isolated sign-ins and website data, with Den state restored after
  relaunch.
- A Drawer shared across the Den for material whose Desk or Board context is not
  settled.
- Optional first-party Vim-style Sheet Navigation for content inside the
  Current Sheet.

See [docs/shortcuts.md](./docs/shortcuts.md) for complete keyboard controls and
[docs/poc.md](./docs/poc.md) for current acceptance criteria and exploratory
checks.

## Development

Den Browser is a macOS app built with SwiftUI, AppKit bridges, `WKWebView`, and
libghostty. Terminal Boards run with the user's normal macOS permissions; the
app is not App Sandboxed.

```sh
mise install
just build
just test
just check
```

These commands disable code signing. Run `just --list` for the available tasks.

## Documentation

- [CONTEXT.md](./CONTEXT.md): product language and domain model
- [DESIGN.md](./DESIGN.md): visual and interaction rules
- [docs/shortcuts.md](./docs/shortcuts.md): Den Mode keyboard commands
- [docs/desk-presets.md](./docs/desk-presets.md): Desk Preset behavior
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/architecture.md](./docs/architecture.md): source organization and boundaries
- [docs/testing.md](./docs/testing.md): automated and exploratory validation
- [docs/releasing.md](./docs/releasing.md): signed release workflow
- [docs/adr](./docs/adr): product and architecture decisions
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md): bundled software licenses
