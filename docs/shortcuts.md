# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,`. The titlebar shows when Den Mode is active; Escape returns to Sheet Input.

The five app-wide shortcuts for toggling Den Mode, focusing the previous or next Board, and moving the Focused Board left or right can be recorded in Settings > Shortcuts. Each action accepts one logical key plus Control, Option, or Command. Board focus and movement shortcuts may be cleared; Toggle Den Mode always retains a binding. Conflicts are rejected, changes apply immediately, and each shortcut or the complete set can be reset. If stored shortcut data cannot be read, Den Browser removes it and uses the default.

The complete in-app guide is available from Settings, the Den menu, and `?` in Den Mode. It uses the current customized bindings.

| Shortcut | Action | Notes |
| --- | --- | --- |
| Control + Command + `P` | Open Profile panel | Searches Profiles and opens their existing Den window or creates it if closed. |
| Command + `T` | New Board panel | Available in every keyboard context. |
| Command + `Q` | Quit Den Browser | Restores a Held Board before exit. |
| Command + Option + Left / Right | Previous / next board | Available in Sheet Input and Den Mode. |
| Shift + Command + Option + Left / Right | Move focused board | Moves left or right without entering Den Mode. |
| `Control` + `,` | Toggle Den Mode | Captures subsequent keys while active. |
| Escape | Restore Held Board / exit Den Mode | Restores a Held Board first; otherwise enters Sheet Input. |
| Left / Right or `h` / `l` | Previous / next board | Board navigation. |
| Up / Down or `j` / `k` | Previous / next desk | Desk navigation. |
| Shift + movement key | Move focused board | Moves in the same spatial direction. |
| `1` through `9` | Focus desk 1 through 9 | Missing desks are a no-op. |
| `0` | Focus desk 10 | Missing desk is a no-op. |
| Shift + digit | Move focused board to desk | Places it after that desk's focused board, then focuses it. |
| `n` / Space | New Board panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| Shift + `n` | New Desk panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| `o` | Toggle overview | Overview is temporary within Den Mode. |
| `?` | Keyboard Shortcuts | Opens the complete guide; `?` or Escape closes it. |
| `z` | Toggle Zen View | Hides the Desk switcher and Profile control for this window; the titlebar remains visible. |
| `[` / `]` | Back / forward in sheet stack | Uses focused board. |
| `-` / `=` | Narrow / widen focused board | |
| `f` | Toggle maximized focused board | Uses the available Den width without changing its persisted Board Width. |
| `c` | Center focused board | Uses edge space to center the first and last Board too. |
| Return | Duplicate current sheet | Creates board to right, focuses it, then enters sheet input. |
| `x` | Hold focused board | One Held Board only. |
| `p` | Place Held Board right | Places it to right of focused board. |
| Shift + `p` | Place Held Board left | Places it to left of focused board. |
| `u` | Restore Held Board | Restores former placement. |
| `d` | Permanently close focused board | Does not request site-provided confirmation in the MVP. |
| Shift + `d` | Delete focused desk | Available only for an empty desk when another desk remains. |
| Command + `R` | Reload current sheet | Available outside Den Mode. |

## Overview

Overview accepts only movement, Shift plus movement, Return, and Escape. Movement changes the Overview Selection; Shift moves its board. Return makes the selection the Focused Board. Escape closes overview back to Den Mode.
