# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,` (customizable). The titlebar indicates `DEN MODE` or `SHEET INPUT`. `Escape` returns to Sheet Input.

The nine primary navigation shortcuts (toggling Den Mode and Board Rail, desk switching, board focus, and board movement) can be customized in Settings > Shortcuts. The complete in-app guide is available via `?` in Den Mode or the Den menu, and supports search by action, category, or key.

---

## App and Sheet Input

Open Board and the Current Sheet URL field accept local paths starting with `/` or `~/` and open them as `file://` URLs. Spaces and filename characters are preserved; `~/` expands to the user's home directory.

Available globally or while focused in a Sheet.

When the Profile panel is open, type to filter Profiles, use `Up` / `Down` to select one, press `Return` to open it, or press `Escape` to close the panel.

In Open Board, remove an individual Recent Item with the trash icon to the right of its Essential control or with **Remove from Recent** in its context menu, without confirmation. **Clear** beside the Recent heading asks for confirmation before removing all Recent Items from the Profile. Both actions leave existing Boards and Essentials unchanged.

| Shortcut | Action |
| --- | --- |
| `Control` + `Command` + `P` | Open Profile panel |
| `Shift` + `Command` + `N` | Open Private Den |
| `Command` + `T` | Open Board panel (URL, search, `:tutorial`, `:terminal`, `:zellij`, `:zmx`) |
| `Command` + `P` | Universal Search (Boards, Desks, Profiles, Essentials, creation, commands) |
| `Command` + `Shift` + `P` | Universal Search with `> ` prefilled (commands only) |
| `Command` + `S` | Toggle Board Rail |
| `Command` + `L` | Edit Focused Board Link |
| `Command` + `W` | Remove Focused Board (or discard selected Drawer item) |
| `Shift` + `Command` + `W` | Close Profile window |
| `Command` + `R` | Reload Current Sheet |
| `Shift` + `Command` + `R` | Hard reload Current Sheet (bypass cache) |
| `Shift` + `Option` + `Command` + `R` | Reload Focused Desk sheets |
| `Command` + `+` / `-` | Increase / decrease Current Sheet size (Web scale or Terminal font size) |
| `Command` + `0` | Reset Current Sheet size |
| `Shift` + `Escape` | Toggle Board Activity monitor |
| `Command` + `Q` | Quit Den Browser |
| `Control` + `Tab` | Next Desk |
| `Control` + `Shift` + `Tab` | Previous Desk |
| `Option` + `Command` + `Tab` | Return to Previous Desk |
| `Command` + `Option` + `Left` / `Right` | Focus previous / next Board |
| `Shift` + `Command` + `Option` + `Left` / `Right` | Move Focused Board left / right |
| `Command` + `Option` + `1`–`9`, `0` | Focus Desk 1–10 |

---

## Den Mode

Toggle with `Control` + `,`. Press `Escape` to exit to Sheet Input.

### Navigation and Workspace

| Shortcut | Action |
| --- | --- |
| `Escape` | Exit Den Mode |
| `Left` / `Right` or `h` / `l` | Focus previous / next Board |
| `Up` / `Down` or `j` / `k` | Focus previous / next Desk |
| `Shift` + movement key | Move Focused Board in that direction |
| `<` / `>` | Browse Boards without changing focus (`c` to re-center) |
| `/` | Filter Boards in Focused Desk by label or URL |
| `1`–`9`, `0` | Focus Desk 1–10 |
| `Shift` + digit | Move Focused Board to Desk 1–10 |
| `n` / `Space` | Open Board panel |
| `:` | Universal Search |
| `v` | Open Board from clipboard |
| `Shift` + `N` | New Desk panel |
| `p` | Save Desk as Preset |
| `Shift` + `P` | Replace Desk from Preset |
| `Control` + `P` | Manage Desk Presets |
| `Tab` | Toggle Drawer |
| `o` | Toggle Overview |
| `i` | Show Notifications (`Up` / `Down` to select, `Return` to open) |
| `g`, then Essential key | Start that Essential Board input directly |
| After `g`: `Up` / `Down`, then `Return` | Focus an Essential and start it; focus wraps at either end |
| `,` | Open Settings |
| `?` | Show Keyboard Shortcuts guide |
| `z` | Toggle Zen View (hide titlebar and chrome) |
| `Shift` + `F` | Toggle Focus Mode (blur other Boards) |

### Board Actions

| Shortcut | Action |
| --- | --- |
| `[` / `]` | Back / forward in Sheet stack |
| `Shift` + `[` / `Shift` + `]` | Jump to First / latest Sheet |
| `-` / `=` | Narrow / widen Focused Board |
| `w`, then `-` / `=` / `1`–`9` | Resize all Boards (adjust by 80pt or fit to window width) |
| `f` | Toggle maximized Focused Board |
| `c` | Center Focused Board |
| `m` | Set / clear Anchor Board for Focused Desk |
| `Shift` + `M` | Jump to Anchor Board / return to origin |
| `Return` | Duplicate Focused Board (Web, Shell, Zellij, or zmx) |
| `Shift` + `Return` | Shell: start a fresh Terminal Session in the same Working Directory; Zellij: open another Board on the same Session; zmx: duplicate as before; Web: open from the First Sheet |
| `e` | Edit Focused Board Link |
| `r` | Rename Focused Board |
| `b` | Save Focused Board as Essential |
| `d` | Remove Focused Board and focus next Board |
| `x` | Remove Focused Board and focus previous Board |
| `u` | Restore recently removed Board |
| `Shift` + `D` | Delete Focused Desk (or discard all Drawer items in Drawer mode) |
| `Shift` + `R` | Rename Focused Desk |
| `a` | Keep Current Sheet in Drawer |
| `s` | Capture screenshot of Current Sheet to file |
| `Control` + `s` | Copy screenshot of Current Sheet to clipboard |
| `y` | Copy Focused Board URL, working directory, or session name |
| `Shift` + `Y` | Copy Focused Board ID |
| `t` | Pause / resume Sheet Navigation for Focused Board |

- Sheet navigation, reload, and screenshot commands do not apply to Terminal Boards.
- Terminal Board removal or running `exit` ends its process; restoring starts a new shell or reconnects to Zellij/zmx.

---

## zmx Sessions

Open from the Den menu, a zmx Board's context menu, or `:zmx` in the Open Board panel.

| Shortcut | Action |
| --- | --- |
| `Up` / `Down` or `k` / `j` | Focus the previous / next Session |
| `Space` | Mark / unmark the Focused Session |
| `Command` + `A` | Mark all visible Sessions |
| `Return` | Open the Focused Session as a Board |
| `x` / `Delete` / `Backspace` | End marked Sessions, or the Focused Session |
| `r` | Refresh Sessions while preserving focus and marks |
| `/` | Activate Session filtering |
| `Escape` | Exit filtering, clear marks or the query, then close the panel |

Mouse clicks can focus or mark individual Sessions. Ending a Session closes its attached Board, which can be restored from Recently Removed Boards; child Sessions remain running unless they are also marked.

---

## Drawer and Overview

### Drawer Controls

Open with `Tab` in Den Mode.

| Shortcut | Action |
| --- | --- |
| `Tab` | Close Drawer in Den Mode |
| `Control` + `Escape` | Close Drawer |
| `/` | Search / filter Drawer items |
| `Up` / `Down` or `k` / `j` | Select Drawer item |
| `Return` | Toggle expanded Preview |
| `p` | Place selected item as a Board |
| `x` | Discard item and focus previous |
| `d` or `Delete` | Discard item and focus next |
| `Command` + `W` | Discard selected item |
| `u` | Restore newest discarded item (up to 10) |
| `f` | Toggle presentation style (floating card vs. bottom sheet) |
| `Shift` + `D` | Discard all Drawer items (with confirmation) |
| `Escape` | Clear filter or exit Drawer |

### Overview Controls

Open with `o` in Den Mode.

Overview opens around the Focused Board at a scale that leaves room for its Desk
and the neighboring Desk above and below, without an initial scrolling animation.
When zoomed-out content fits in the viewport, it is centered in both directions.
Zoom ranges from 20% to 300% of the base Board size across all input methods.
Search centers the selected result after the filtered layout updates. The canvas
controls group the zoom level, zoom buttons, and Return to current Desk. Returning
to the current Desk clears search, selects its Focused Board, and restores the
initial scale without leaving Overview.
The canvas extends to the panel edges with hidden scroll bars; scroll or drag its
background to pan. Right-drag anywhere on the canvas, including over a Board,
to pan without moving Boards.

Board sizes and Desk order remain visible on a canvas. Previously viewed Web and
Terminal Boards show a small, memory-only snapshot when available; Overview does
not load unvisited Boards to obtain one. Captures are suppressed for 30 seconds
after a successful capture, and the last image remains available afterwards.
Snapshots are requested when a surface is hidden or removed, without a fixed delay
after appearing. Terminal snapshots are captured before hiding; Web snapshots are
asynchronous and skip loading pages. Retained thumbnail rasters share a 64 MiB cache budget.

| Shortcut | Action |
| --- | --- |
| `Left` / `Right` or `h` / `l` | Select Board |
| `Up` / `Down` or `j` / `k` | Select Desk |
| `Shift` + movement | Move selected Board |
| `x` / `d` | Remove selected Board and select previous / next (Overview stays open) |
| `u` | Restore the most recently removed Board and select it (Overview stays open) |
| `=` / `+` / `-` | Zoom Overview in / out (plain keys remain text while searching) |
| `Command` + `+` / `-` | Zoom Overview in / out |
| `0` / `Command` + `0` | Reset Overview to its initial scale and center the selection (`0` remains text while searching) |
| `/` | Search / filter Desks and Boards (`Return` confirms, `Escape` clears) |
| `Return` | Enter selection as Focused Board |
| `Escape` | Clear search or return to Den Mode |

---

## Pointer Controls

- **Sheets**:
  - Pinch in or out over a Web Board to adjust the Current Sheet's scale for that Board.
  - Pinch in or out over a Terminal Board to adjust its font size for that Board.
- **Board Headers**:
  - Double-click to focus and center the Board.
  - Drag label or empty area to reorder within the Desk. Dragging either a Primary Board or its Side Board moves the whole Board Group together.
  - Web, Terminal, and Inspection Board headers provide context menus with actions appropriate to their Board kind. Web Board actions include copying the Current Sheet URL or Board ID, keeping the Sheet in Drawer, duplicating, reloading, adjusting Sheet size, centering, maximizing, moving to a Desk, and removing. Tutorial Board headers have no context menu.
- **BoardRail**:
  - Right-click or Control-click a Board for its context menu (set or clear Anchor, rename, duplicate, move to Desk, copy Current Sheet URL for Web Boards, remove). Opening the menu does not change focus.
- **Board Resize**:
  - Drag the gap after a Board to resize it. Hold `Shift` to resize it with the next Board while keeping the pair's outer edges fixed.
- **Desk Switcher**:
  - Click `+` after the last Desk to create a new Desk.
  - Drag Desk button to reorder Desks.
  - Right-click for context menu (copy ID, open in new window, rename, delete, save preset, export).
- **Overview**:
  - Scroll in either direction or drag the background to pan. Right-drag anywhere on the canvas, including over a Board,
to pan without moving Boards.
  - Pinch to zoom around the gesture's starting position.
  - Hold `Command` while scrolling vertically over the canvas to zoom around the pointer.
  - Drag Board cards to reposition within or across Desks.
  - Click selects; double-click opens that Desk and Board. Hover card shows close button.
- **Web Popups**:
  - `window.open()` calls and links targeting a new browsing context open as adjacent Web Boards. They receive focus by default; hold `Command` to open in the background, or `Command` + `Shift` to focus the new Board.
- **Terminal Links**:
  - `Command`-click HTTP/HTTPS link to open adjacent Web Board without adding to Drawer.
  - `Command`-click `file://` or file path to open in default macOS application.
