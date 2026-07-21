# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,`. The titlebar shows when Den Mode is active; Escape returns to Sheet Input.

The five app-wide shortcuts for toggling Den Mode, focusing the previous or next Board, and moving the Focused Board left or right can be recorded in Settings > Shortcuts. Each action accepts one logical key plus Control, Option, or Command. Board focus and movement shortcuts may be cleared; Toggle Den Mode always retains a binding. Conflicts are rejected, changes apply immediately, and each shortcut or the complete set can be reset. If stored shortcut data cannot be read, Den Browser removes it and uses the default.

The complete in-app guide is available from Settings, the Den menu, and `?` in Den Mode. It uses the current customized bindings.

| Shortcut | Action | Notes |
| --- | --- | --- |
| Control + Command + `P` | Open Profile panel | Searches Profiles and opens their existing Den window or creates it if closed. |
| Command + `T` | New Board panel | Available in every keyboard context. |
| Command + `L` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Available in every keyboard context. |
| Command + `W` | Remove focused Board | Available in every keyboard context. |
| Shift + Command + `W` | Close Profile window | Settings and other non-Den windows retain Command + `W`. |
| Command + `Q` | Quit Den Browser | |
| Command + Option + Left / Right | Previous / next board | Available in Sheet Input and Den Mode. |
| Shift + Command + Option + Left / Right | Move focused board | Moves left or right without entering Den Mode. |
| `Control` + `,` | Toggle Den Mode | Captures subsequent keys while active. |
| Escape | Exit Den Mode | Enters Sheet Input. |
| Left / Right or `h` / `l` | Previous / next board | Board navigation. |
| Up / Down or `j` / `k` | Previous / next desk | Desk navigation. |
| Shift + movement key | Move focused board | Moves in the same spatial direction. |
| `1` through `9` | Focus desk 1 through 9 | Missing desks are a no-op. |
| `0` | Focus desk 10 | Missing desk is a no-op. |
| Shift + digit | Move focused board to desk | Places it after that desk's focused board, then focuses it. |
| `n` / Space | New Board panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| Shift + `n` | New Desk panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| `p` | Save Desk as Preset panel | Available when the Focused Desk contains a Board. |
| Shift + `p` | Manage Personal Desk Presets | Available even when the Focused Desk is empty. |
| `o` | Toggle overview | Overview is temporary within Den Mode. |
| `?` | Keyboard Shortcuts | Opens the complete guide; `?` or Escape closes it. |
| `z` | Toggle Zen View | Hides the Desk switcher and Profile control for this window; the titlebar remains visible. |
| `[` / `]` | Back / forward in sheet stack | Uses focused board. |
| `-` / `=` | Narrow / widen focused board | |
| `w`, then `1` through `9` | Resize all Boards to fit | Persistently resizes every Board in the Focused Desk using the current window width. Escape or `w` cancels. |
| `f` | Toggle maximized focused board | Uses the available Den width without changing its persisted Board Width. |
| `c` | Center focused board | Uses edge space to center the first and last Board too. |
| Return | Duplicate current sheet | Creates board to right, focuses it, then enters sheet input. |
| `e` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Escape returns to Den Mode. |
| `r` | Rename focused Board | Opens the Rename Board panel; Return confirms, Escape returns to Den Mode. |
| `x` / `d` | Remove focused Board | Releases its live Sheet runtime. Key repeat is ignored. |
| `u` | Restore Recently Removed Board | Available for the current app run. Key repeat is ignored. |
| Shift + `d` | Delete focused desk | Deletes an empty desk immediately. A desk with Boards requires confirmation. Unavailable for the last desk. |
| Shift + `r` | Rename focused Desk | Opens the Rename Desk panel; Return confirms, Escape returns to Den Mode. |
| Command + `R` | Reload current sheet | Available outside Den Mode. |

## Overview

Overview accepts movement, Shift plus movement, `/` (search/filter), Return, and Escape. Movement changes the Overview Selection; Shift moves its board. Pressing `/` enters Search Mode to dynamically filter desks and boards (Return confirms the query to allow navigation, Escape cancels and clears the query). Return in Normal Mode makes the selection the Focused Board. Escape in Normal Mode clears the query if active, or closes overview back to Den Mode.

## Pointer Board actions

Drag a Board header's label or empty area to reorder it within the Focused Desk. Header buttons remain ordinary controls. Dropping outside the Board strip cancels the move; moving near the strip's horizontal edges scrolls it. Keyboard Board movement and Overview remain available without pointer input.

Right-click or Control-click anywhere in a Board header to focus that Board and open its native context menu. The menu can duplicate or reload the Current Sheet, maximize or center the Board, move it left, right, or to another numbered Desk, and remove it. Movement at a Desk edge remains visible but disabled. Right-clicking inside a Sheet continues to use the web content's own context menu.
