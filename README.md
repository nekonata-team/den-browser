[English](./README.md) | [日本語](./README.ja.md) | [Website](https://den.nekonata.dev/)

# Den Browser

**Web and terminal work, the Niri way.** — [den.nekonata.dev](https://den.nekonata.dev/)

Den Browser is a keyboard-first spatial browser for long-running web and terminal work. It
keeps parallel tasks as persistent work surfaces instead of growing tab and terminal-window lists,
so research, AI chats, development, writing, and documentation stay easy to
revisit.

> **Status:** macOS companion browser under active development.

Den Browser complements Safari, Chrome, or another general-purpose browser. It
is for work that benefits from spatial memory and long-lived context, not for
replacing everyday browsing.

## Installation

Den Browser requires macOS 26 or later.

```sh
brew install --cask nekonata-team/tap/den-browser
```

Upgrade with `brew upgrade --cask den-browser`.

### Agent Skill

Coding agents (Claude Code, Cursor, etc.) can drive adjacent Web Boards via the bundled CLI:

```sh
npx skills add nekonata-team/den-browser --skill den
```

From a Terminal Board, the bundled `den` CLI can inspect and control the
adjacent Web Board:

```sh
den board list
den sheet snapshot -i
den sheet text
```

### Ghostty configuration

Terminal Boards read your Ghostty configuration from the standard XDG and macOS
locations. Choose only the settings you want, for example:

```ini
theme = dark:Catppuccin Mocha,light:Catppuccin Latte
copy-on-select = clipboard
```

Den resolves theme names from its bundled catalog. See [Ghostty's configuration reference](https://ghostty.org/docs/config/reference).

## Core model

- **Profile**: An isolated web identity with its own sign-ins, site data, and
  Den.
- **Den**: The complete work environment for one Profile.
- **Desk**: A broad work context containing Boards in a horizontal work area.
- **Board**: A persistent work surface containing Web Sheets, a Terminal Session, a Zellij Session, or a zmx Session.
- **Sheet**: A web screen held within a Board.

Den Browser draws loosely on [Niri](https://github.com/niri-wm/niri)'s spatial
window management. Its paper-workspace model is designed around web tasks,
navigation history, and restoration. See [CONTEXT.md](./CONTEXT.md) for the
complete product language.

## What Den Browser provides

- Persistent spatial organization across multiple Desks.
- Web, Terminal, Zellij, and zmx Boards side by side in one Desk.
- Keyboard-first navigation and Board management, with pointer controls where
  useful.
- Profile-isolated sign-ins and website data, with Den state restored after
  relaunch.
- A Drawer shared across the Den for material whose Desk or Board context is not
  settled.
- Optional first-party Vim-style Sheet Navigation for content inside the
  Current Sheet.

See [docs/shortcuts.md](./docs/shortcuts.md) for complete keyboard controls.

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
- [docs/shortcuts.md](./docs/shortcuts.md): keyboard and pointer controls
- [docs/cli.md](./docs/cli.md): CLI reference and agent skill integration
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md): bundled software licenses

See [AGENTS.md](./AGENTS.md) for internal architecture, testing, and developer documentation.

## License

Den Browser's original source code is licensed under the [Mozilla Public License, version 2.0](./LICENSE).
Copyright (c) 2026 nekonata.
