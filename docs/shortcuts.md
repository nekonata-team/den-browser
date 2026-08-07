# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,`. Outside Zen View, the titlebar shows when Den Mode is active; Escape returns to Sheet Input.

The eight app-wide shortcuts for toggling Den Mode, moving between Desks, returning to the Previous Desk, focusing the previous or next Board, and moving the Focused Board left or right can be recorded in Settings > Shortcuts. Each action accepts one logical key plus Control, Option, or Command. Desk and Board focus and movement shortcuts may be cleared; Toggle Den Mode always retains a binding. Conflicts are rejected, changes apply immediately, and each shortcut or the complete set can be reset. If stored shortcut data cannot be read, Den Browser removes it and uses the default.

The complete in-app guide is available from Settings, the Den menu, and `?` in Den Mode. It uses the current customized bindings.

| Shortcut | Action | Notes |
| --- | --- | --- |
| Control + Command + `P` | Open Profile panel | Searches Profiles and opens their existing Den window or creates it if closed. |
| Command + `T` | New Board panel | Available in every keyboard context. |
| Command + `L` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Available in every keyboard context. |
| Command + `W` | Remove focused Board | Available in every keyboard context. |
| Shift + Command + `W` | Close Profile window | Settings and other non-Den windows retain Command + `W`. |
| Command + `Q` | Quit Den Browser | |
| Control + Tab | Next Desk | Available in Sheet Input and Den Mode. |
| Control + Shift + Tab | Previous Desk | Available in Sheet Input and Den Mode. |
| Option + Command + Tab | Return to Previous Desk | Toggles between the two most recently focused Desks. Available in Sheet Input and Den Mode. |
| Command + Option + Left / Right | Previous / next board | Available in Sheet Input and Den Mode. |
| Shift + Command + Option + Left / Right | Move focused board | Moves left or right without entering Den Mode. |
| Command + Option + `1` through `9`, `0` | Focus Desk 1 through 10 | Available in Sheet Input. The modifier combination is configurable in Settings > Shortcuts; Shift alone is not allowed. |
| `Control` + `,` | Toggle Den Mode | Captures subsequent keys while active. |
| Escape | Exit Den Mode | Enters Sheet Input. |
| Left / Right or `h` / `l` | Previous / next board | Board navigation. |
| Up / Down or `j` / `k` | Previous / next desk | Desk navigation. |
| Shift + movement key | Move focused board | Moves in the same spatial direction. |
| `/` | Filter Boards in Focused Desk | Filters by Board Label or Current Sheet URL. Return confirms the query; Left / Right or `h` / `l` selects a match; Return enters it. Escape cancels. |
| `1` through `9` | Focus desk 1 through 9 | Missing desks are a no-op. |
| `0` | Focus desk 10 | Missing desk is a no-op. |
| Shift + digit | Move focused board to desk | Places it after that desk's focused board, then focuses it. |
| `n` / Space | New Board panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| Shift + `n` | New Desk panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| `p` | Save Desk as Preset panel | Available when the Focused Desk contains a Board. |
| Shift + `p` | Replace Focused Desk from a Desk Preset | Empty Preset is excluded; replacing an empty Desk applies immediately. |
| Tab | Toggle Drawer | Available in Den Mode. Opening an expanded Preview enters Sheet Input and focuses its Sheet; opening a Drawer without a Preview keeps Den Mode. The Den Mode Toggle remains available inside the Drawer: entering Den Mode preserves the Preview and returns focus to Drawer Items, while returning to Sheet Input focuses the Preview again. In Den Mode, `/` starts filtering Drawer Items by title or URL. Return first confirms the query; Up / Down or `k` / `j` then selects a visible Item, and a second Return expands or collapses its Preview. Escape clears the filter. `p` places the selected Item as a Board, and `x`, `d`, or Delete discards it. Discarding the expanded Preview opens the next visible Drawer Item's Preview, or the previous visible Item when the discarded Item was last. In Sheet Input, Drawer Items accept only standard arrow, Return, Delete, and Escape controls; a focused Preview keeps its web and Vim-style Sheet Navigation keys, including Escape. |
| `o` | Toggle overview | Overview is temporary within Den Mode. |
| `?` | Keyboard Shortcuts | Opens the complete guide; `?` or Escape closes it. |
| `,` | Open Settings | Available in Den Mode. |
| `z` | Toggle Zen View | Hides the native titlebar, Desk switcher, and Profile control for this window. Press `z` again to restore them. |
| `[` / `]` | Back / forward in sheet stack | Uses focused board. |
| Shift + `[` / Shift + `]` | First / latest Sheet | Shift + `[` loads the Focused Board's persisted First Sheet URL when present; Shift + `]` jumps to the latest Sheet retained in the live Sheet Stack. A Board without a First Sheet does nothing. |
| `-` / `=` | Narrow / widen focused board | |
| `w`, then `-` / `=` or `1` through `9` | Resize all Boards | `-` and `=` adjust every Board in the Focused Desk by 80pt and keep the panel open. Digits persistently resize every Board to fit the current window width. Escape or `w` cancels. |
| `f` | Toggle maximized focused board | Uses the available Den width without changing its persisted Board Width. |
| `c` | Center focused board | Uses edge space to center the first and last Board too. |
| `t` | Pause / resume Sheet Navigation for focused Board | Persists independently for each Board. |
| `s` | Capture Current Sheet screenshot | Captures the visible web content in the Focused Board and opens a macOS save panel for a PNG. |
| Shift + `s` | Capture Focused Desk screenshot | Captures every Board's visible Current Sheet, preserving Board order and relative widths in one PNG. |
| `a` | Keep Current Sheet in Drawer | Keeps the Focused Board's Current Sheet in the Drawer without changing the Current Sheet. |
| Return | Duplicate current sheet | Creates board to right, focuses it, then enters sheet input. |
| `e` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Escape returns to Den Mode. |
| `r` | Rename focused Board | Opens the Rename Board panel; Return confirms, Escape returns to Den Mode. |
| `x` / `d` | Remove focused Board | Releases its live Sheet runtime. Key repeat is ignored. |
| `u` | Restore Recently Removed Board | Available for the current app run. Key repeat is ignored. |
| Shift + `d` | Discard all Drawer items / Delete focused desk | In Drawer Den Mode, opens confirmation to discard every Drawer Item. In other Den Mode contexts, deletes an empty desk immediately; a desk with Boards requires confirmation. Unavailable for the last desk. Key repeat is ignored. |
| Shift + `r` | Rename focused Desk | Opens the Rename Desk panel; Return confirms, Escape returns to Den Mode. |
| Command + `R` | Reload current sheet | Available outside Den Mode. |
| Shift + Command + `R` | Hard reload current sheet | Reloads the Current Sheet with end-to-end cache revalidation. Available in Sheet Input and Den Mode. |
| Shift + Option + Command + `R` | Reload Focused Desk sheets | Reloads every Board's Current Sheet in the Focused Desk. Available in Sheet Input and Den Mode. |

## Overview

Overview accepts movement, Shift plus movement, `/` (search/filter), Return, and Escape. Movement changes the Overview Selection; Shift moves its board. Pressing `/` enters Search Mode to dynamically filter desks and boards (Return confirms the query to allow navigation, Escape cancels and clears the query). Return in Normal Mode makes the selection the Focused Board. Escape in Normal Mode clears the query if active, or closes overview back to Den Mode.
When no Desk or Board matches the query, Overview shows a no-results state.

## Focused Desk filter

In Den Mode, `/` opens a floating filter over the current Board strip. It dynamically matches Board Labels and Current Sheet URLs without changing the Focused Board. Return confirms text input; Left / Right or `h` / `l` moves the temporary selection among matching Boards; Return enters the selection and returns to Sheet Input. Escape clears the filter and keeps Den Mode active. Other Den commands remain suspended while the filter is visible.

## Pointer Board actions

Drag a Board header's label or empty area to reorder it within the Focused Desk. Header buttons remain ordinary controls. Dropping outside the Board strip cancels the move; moving near the strip's horizontal edges scrolls it. Keyboard Board movement and Overview remain available without pointer input.

Right-click or Control-click anywhere in a Board header to focus that Board and open its native context menu. The menu can keep a copy of the Current Sheet in the Drawer, duplicate or reload it, maximize or center the Board, move it left, right, or to another numbered Desk, and remove it. Movement at a Desk edge remains visible but disabled. Right-clicking inside a Sheet continues to use the web content's own context menu.

## Pointer Desk actions

Drag a Desk button in the Desk switcher to reorder Desks. Clicking still focuses that Desk, and its context menu remains available. Dropping outside the switcher cancels the move; moving near its horizontal edges scrolls it. Desk reordering has no keyboard shortcut.
