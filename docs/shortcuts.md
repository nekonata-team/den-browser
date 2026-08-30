# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,`. The titlebar identifies the current keyboard context as `DEN MODE` or `SHEET INPUT` during ordinary Board work; it shows only the Profile name while a temporary context is open or no Board is focused. Escape returns to Sheet Input.

The eight app-wide shortcuts for toggling Den Mode, moving between Desks, returning to the Previous Desk, focusing the previous or next Board, and moving the Focused Board left or right can be recorded in Settings > Shortcuts. Each action accepts one logical key plus Control, Option, or Command. Desk and Board shortcuts may be cleared; Toggle Den Mode always retains a binding. Conflicts are rejected, changes apply immediately, and each shortcut or the complete set can be reset. If stored shortcut data cannot be read, Den Browser removes it and uses the default.

The complete in-app guide is available from Settings, the Den menu, and `?` in Den Mode. It uses the current customized bindings.

Board Activity is available from the View menu or with `Shift` + `Escape`. While open, it samples CPU and memory once per second. Web Boards report their WebKit content process and identify shared processes; Terminal Boards report the current foreground process group. Shared WebKit, background Terminal, Network, and GPU work is not assigned to individual Boards.

Essentials are app-wide named Board inputs configured in Settings > Essentials. In Den Mode, `g` opens the Essentials Prefix; press `g` followed by an Essential's case-sensitive key to start its Web, Terminal, Zellij, or zmx Board input in the active Profile window. Hold Shift for an uppercase key. Escape cancels the prefix, and an unregistered second key shows a warning Toast before returning to Den Mode.

| Shortcut | Action | Notes |
| --- | --- | --- |
| Control + Command + `P` | Open Profile panel | Searches Profiles and opens their existing Den window or creates it if closed. |
| Command + `T` | New Board panel | Enter a URL/search for a Web Board, `:terminal [path]` for an ordinary Terminal Board, `:zellij [session]` for a Zellij Board, or `:zmx [session]` for a zmx Board. Without a session, Zellij's Welcome screen is shown; `:zmx` opens zmx Sessions, and Escape returns here. Up / Down selects a visible Recent Item; Right copies it into the input. Available in every keyboard context. |
| `/`, Up / Down, Return, `x`, Delete / Backspace, `r` | zmx Sessions | `/` focuses filtering. Outside filtering, selects a Session, opens it, requests deletion, or reloads the list. Escape clears filtering, then closes the list. |
| Command + `L` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Available in every keyboard context. |
| Command + `W` | Remove focused Board | Available in every keyboard context. |
| Shift + Command + `W` | Close Profile window | Settings and other non-Den windows retain Command + `W`. |
| Shift + Escape | Board Activity | Shows live Web and Terminal Board state across the Den. Press Escape to close it. |
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
| `<` / `>` | Browse Boards without changing focus | Den Mode shortcut. Moves the Board view to the previous or next Board; repeat to browse continuously. The Focused Board stays selected. `c` returns it to center. |
| `/` | Filter Boards in Focused Desk | Filters by Board Label or Current Sheet URL. Return confirms the query; Left / Right or `h` / `l` selects a match; Return enters it. Escape cancels. |
| `1` through `9` | Focus desk 1 through 9 | Missing desks are a no-op. |
| `0` | Focus desk 10 | Missing desk is a no-op. |
| Shift + digit | Move focused board to desk | Places it after that desk's focused board, then focuses it. |
| `i` | Show Notifications | Opens the session's notification list. Its trash button clears all Notifications after confirmation. |
| Up / Down | Select notification | When the notification list is open; Return opens the selected notification and Escape closes the list. |
| `n` / Space | New Board panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| `v` | Open Board from clipboard | Creates a Board from copied URL, search, or command input to the right of the Focused Board and enters Sheet Input. Available in Den Mode. |
| Shift + `n` | New Desk panel | Creating enters Sheet Input; Escape returns to Den Mode. |
| `p` | Save Desk as Preset panel | Available when the Focused Desk contains a Board. |
| Shift + `p` | Replace Focused Desk from a Desk Preset | Empty Preset is excluded; replacing an empty Desk applies immediately. |
| Tab | Toggle Drawer | Available in Den Mode. Opening an expanded Preview enters Sheet Input and focuses its Sheet; opening a Drawer without a Preview keeps Den Mode. The Den Mode Toggle remains available inside the Drawer: entering Den Mode preserves the Preview and returns focus to Drawer Items, while returning to Sheet Input focuses the Preview again. In Den Mode, `/` starts filtering Drawer Items by title or URL. Return first confirms the query; Up / Down or `k` / `j` then selects a visible Item, and a second Return expands or collapses its Preview. Escape clears the filter. `p` places the selected Item as a Board. `x` discards the selected Item and focuses the previous visible Item, falling back to the next; `d` or Delete focuses the next visible Item, falling back to the previous. `u` restores the newest discarded Drawer Item and keeps Den Mode active; repeated use restores older items from the current app run, up to ten retained items. Discarding the expanded Preview opens that focused Item's Preview. In Sheet Input, Drawer Items accept only standard arrow, Return, Delete, and Escape controls; a focused Preview keeps its web and Vim-style Sheet Navigation keys, including Escape. |
| `o` | Toggle overview | Overview is temporary within Den Mode. |
| `?` | Keyboard Shortcuts | Opens the complete guide; `?` or Escape closes it. |
| `,` | Open Settings | Available in Den Mode. |
| `g`, then Essential key | Start an Essential | Opens the configured Board input. Available in Den Mode. |
| `z` | Toggle Zen View | Hides the native titlebar, Desk switcher, and Profile control for this window. Press `z` again to restore them. |
| Shift + `f` | Toggle Focus Mode | Keeps the Focused Board's Sheet or Terminal surface clear and softly blurs other Board content. Remains active until toggled off. |
| `[` / `]` | Back / forward in sheet stack | Uses focused board. |
| Shift + `[` / Shift + `]` | First / latest Sheet | Shift + `[` loads the Focused Board's persisted First Sheet URL when present; Shift + `]` jumps to the latest Sheet retained in the live Sheet Stack. A Board without a First Sheet does nothing. |
| `-` / `=` | Narrow / widen focused board | |
| `w`, then `-` / `=` or `1` through `9` | Resize all Boards | `-` and `=` adjust every Board in the Focused Desk by 80pt and keep the panel open. Digits persistently resize every Board to fit the current window width. Escape or `w` cancels. |
| `f` | Toggle maximized focused board | Uses the available Den width without changing its persisted Board Width. |
| `c` | Center focused board | Uses edge space to center the first and last Board too. |
| `t` | Pause / resume Sheet Navigation for focused Board | Persists independently for each Board. |
| `s` | Capture Current Sheet screenshot | Captures the visible web content in the Focused Board and opens a macOS save panel for a PNG. |
| Shift + `s` | Capture Focused Desk screenshot | Captures every Board's visible Current Sheet, preserving Board order and relative widths in one PNG. |
| Control + `s` | Copy Current Sheet screenshot | Copies the visible web content in the Focused Board to the clipboard as a PNG without opening a save panel. |
| Control + Shift + `s` | Copy Focused Desk screenshot | Copies the Focused Desk screenshot to the clipboard as a PNG without opening a save panel. |
| `a` | Keep Current Sheet in Drawer | Keeps the Focused Board's Current Sheet in the Drawer without changing the Current Sheet. |
| Return | Duplicate focused Board | Web Boards duplicate the Current Sheet. Ordinary Terminal Boards start a new Shell from the saved Working Directory. Zellij Boards reconnect to the same session or show Welcome. zmx Boards open a suffix panel and create an independent session in the same Working Directory; the root session name is used for the new name (`den` + `vi` → `den-vi`). Suffixes accept letters, numbers, `-`, `_`, and `.`; leaving the suffix empty uses an automatic number. |
| Shift + Return | New Board from First Sheet | Creates a Board to the right from the Focused Board's persisted First Sheet URL, focuses it, then enters Sheet Input. A non-zmx Board without a First Sheet does nothing. For zmx Boards, duplicates immediately with an automatic numeric suffix and no input panel. |
| `e` | Edit Focused Board Link panel | Replaces the Current Sheet with a URL or search on Return. Escape returns to Den Mode. |
| `r` | Rename focused Board | Opens the Rename Board panel; Return confirms, Escape returns to Den Mode. |
| `d` | Remove focused Board and focus the next Board | If no next Board exists, focuses the previous Board. Releases its live Sheet runtime. Key repeat is ignored. |
| `x` | Remove focused Board and focus the previous Board | If no previous Board exists, focuses the next Board. Releases its live Sheet runtime. Key repeat is ignored. |
| `u` | Restore Recently Removed Board | Restores the newest retained Board; repeat to restore older retained Boards. Available for the current app run. Key repeat is ignored. |
| Shift + `d` | Discard all Drawer items / Delete focused desk | In Drawer Den Mode, opens confirmation to discard every Drawer Item. In other Den Mode contexts, deletes an empty desk immediately; a desk with Boards requires confirmation. Unavailable for the last desk. Key repeat is ignored. |
| Shift + `r` | Rename focused Desk | Opens the Rename Desk panel; Return confirms, Escape returns to Den Mode. |
| Command + `R` | Reload current sheet | Available outside Den Mode. |
| Shift + Command + `R` | Hard reload current sheet | Reloads the Current Sheet with end-to-end cache revalidation. Available in Sheet Input and Den Mode. |
| Shift + Option + Command + `R` | Reload Focused Desk sheets | Reloads every Board's Current Sheet in the Focused Desk. Available in Sheet Input and Den Mode. |

Open Board and Current Sheet URL input removes line breaks from pasted URLs. Line breaks in pasted search input become spaces.

Sheet navigation, Drawer placement, reload, PiP, and screenshot commands do nothing when the Focused Board is a Terminal Board. Cmd-clicking a supported link in a Terminal Board creates a background Web Board without adding a Drawer Item. Clicking a link in a Board does not trigger automatic Board centering; other pointer focus and keyboard focus retain the configured centering behavior. Removing a Terminal Board or running `exit` ends its process. Restoring an ordinary Terminal Board starts a new Shell; restoring a Zellij Board reconnects to its named session or shows Welcome; restoring a zmx Board reconnects to its named session.

## Overview

Overview accepts movement, Shift plus movement, `/` (search/filter), Return, and Escape. Movement changes the Overview Selection; Shift moves its board. Pressing `/` enters Search Mode to dynamically filter desks and boards (Return confirms the query to allow navigation, Escape cancels and clears the query). Return in Normal Mode makes the selection the Focused Board. Clicking selects a Board; double-clicking enters its Desk and Board. Double-clicking an empty Desk enters that Desk. Escape in Normal Mode clears the query if active, or closes overview back to Den Mode.
When no Desk or Board matches the query, Overview shows a no-results state.

## Focused Desk filter

In Den Mode, `/` opens a floating filter over the current Board strip. It dynamically matches Board Labels and Current Sheet URLs without changing the Focused Board. Return confirms text input; Left / Right or `h` / `l` moves the temporary selection among matching Boards; Return enters the selection and returns to Sheet Input. Escape clears the filter and keeps Den Mode active. Other Den commands remain suspended while the filter is visible.

## Pointer Board actions

Drag a Board header's label or empty area to reorder it within the Focused Desk. Header buttons remain ordinary controls. Dropping outside the Board strip cancels the move; moving near the strip's horizontal edges scrolls it. Keyboard Board movement and Overview remain available without pointer input.

Right-click or Control-click anywhere in a Board header to focus that Board and open its native context menu. The menu can keep a copy of the Current Sheet in the Drawer, duplicate or reload it, maximize or center the Board, move it left, right, or to another numbered Desk, and remove it. zmx Board menus also open zmx Sessions with their Session highlighted. Duplicating a zmx Board opens the same suffix panel as Return. Movement at a Desk edge remains visible but disabled. Right-clicking inside a Sheet continues to use the web content's own context menu.

While Overview is open without a search query, drag a Board card to another position or Desk. Dropping on the left or right half of a Board inserts before or after it; dropping in a Desk row's empty area appends it. Overview remains open with the moved Board selected. Board dragging is disabled while filtering. Board cards use proportional widths and show Web or Terminal identity with an icon, label, and semantic type tint. Hovering a Board card shows a close button to remove it.

## Pointer Desk actions

Click the plus button after the last Desk button in the Desk switcher to open the New Desk panel. Drag a Desk button in the Desk switcher to reorder Desks. Clicking still focuses that Desk, and its context menu remains available. Dropping outside the switcher cancels the move; moving near its horizontal edges scrolls it. Desk reordering has no keyboard shortcut.
