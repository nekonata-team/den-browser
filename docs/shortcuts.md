# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a sheet has keyboard focus. Enter it with `Control` + `.`. The titlebar shows when Den Mode is active; Escape returns to sheet input.

| Shortcut | Action | Notes |
| --- | --- | --- |
| Command + `T` | New Board panel | Available in every keyboard context. |
| `Control` + `.` | Enter Den Mode | Captures subsequent keys. |
| Escape | Exit Den Mode | When overview or a panel is not open. |
| Left / Right or `h` / `l` | Previous / next board | Board navigation. |
| Up / Down or `j` / `k` | Previous / next desk | Desk navigation. |
| Shift + movement key | Move focused board | Moves in the same spatial direction. |
| `1` through `9` | Focus desk 1 through 9 | Missing desks are a no-op. |
| `0` | Focus desk 10 | Missing desk is a no-op. |
| Shift + digit | Move focused board to desk | Places it after that desk's focused board, then focuses it. |
| `n` | New Board panel | Creating enters sheet input; Escape returns to Den Mode. |
| Shift + `n` | New Desk panel | Creating enters sheet input; Escape returns to Den Mode. |
| `o` | Toggle overview | Overview is temporary within Den Mode. |
| `[` / `]` | Back / forward in sheet stack | Uses focused board. |
| `-` / `=` | Narrow / widen focused board | |
| Return | Duplicate current sheet | Creates board to right, focuses it, then enters sheet input. |
| `x` | Cut focused board | One Cut Board only. |
| `p` | Place Cut Board | Places it to right of focused board. |
| `u` | Restore Cut Board | Restores former placement. |
| `d` | Permanently close focused board | Does not request site-provided confirmation in the MVP. |
| Shift + `d` | Delete focused desk | Available only for an empty desk when another desk remains. |
| Command + `R` | Reload current sheet | Available outside Den Mode. |

## Overview

Overview accepts only movement, Shift plus movement, Return, and Escape. Movement changes the Overview Selection; Shift moves its board. Return makes the selection the Focused Board. Escape closes overview back to Den Mode.
