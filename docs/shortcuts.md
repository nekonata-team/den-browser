# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,` (customizable). The titlebar indicates `DEN MODE` or `SHEET INPUT`. `Escape` returns to Sheet Input.

The eight primary navigation shortcuts (toggling Den Mode, desk switching, board focus, and board movement) can be customized in Settings > Shortcuts. The complete in-app guide is available via `?` in Den Mode or the Den menu.

---

## App and Sheet Input

Available globally or while focused in a Sheet.

When the Profile panel is open, type to filter Profiles, use `Up` / `Down` to select one, press `Return` to open it, or press `Escape` to close the panel.

| Shortcut | Action |
| --- | --- |
| `Control` + `Command` + `P` | Open Profile panel |
| `Command` + `T` | Open Board panel (URL, search, `:terminal`, `:zellij`, `:zmx`) |
| `Command` + `L` | Edit Focused Board Link |
| `Command` + `W` | Remove Focused Board (or discard selected Drawer item) |
| `Shift` + `Command` + `W` | Close Profile window |
| `Command` + `R` | Reload Current Sheet |
| `Shift` + `Command` + `R` | Hard reload Current Sheet (bypass cache) |
| `Shift` + `Option` + `Command` + `R` | Reload Focused Desk sheets |
| `Command` + `+` / `-` | Increase / decrease Focused Board content size (Sheet scale or Terminal font size) |
| `Command` + `0` | Reset Focused Board content size |
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
| `v` | Open Board from clipboard |
| `Shift` + `N` | New Desk panel |
| `p` | Save Desk as Preset |
| `Shift` + `P` | Replace Desk from Preset |
| `Tab` | Toggle Drawer |
| `o` | Toggle Overview |
| `i` | Show Notifications (`Up` / `Down` to select, `Return` to open) |
| `g`, then Essential key | Start Essential Board input |
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
| `Shift` + `Return` | New Board from First Sheet (or duplicate zmx with numeric suffix) |
| `e` | Edit Focused Board Link |
| `r` | Rename Focused Board |
| `b` | Save Focused Board as Essential |
| `d` | Remove Focused Board and focus next Board |
| `x` | Remove Focused Board and focus previous Board |
| `u` | Restore recently removed Board |
| `Shift` + `D` | Delete Focused Desk (or discard all Drawer items in Drawer mode) |
| `Shift` + `R` | Rename Focused Desk |
| `a` | Keep Current Sheet in Drawer |
| `s` / `Shift` + `S` | Capture screenshot of Sheet / Desk to file |
| `Control` + `s` / `Control` + `Shift` + `S` | Copy screenshot of Sheet / Desk to clipboard |
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

| Shortcut | Action |
| --- | --- |
| `Left` / `Right` or `h` / `l` | Select Board |
| `Up` / `Down` or `j` / `k` | Select Desk |
| `Shift` + movement | Move selected Board |
| `/` | Search / filter Desks and Boards (`Return` confirms, `Escape` clears) |
| `Return` | Enter selection as Focused Board |
| `Escape` | Clear search or return to Den Mode |

---

## Pointer Controls

- **Board Content**:
  - Pinch in or out over a Web Board to adjust the Current Sheet's scale for that Board.
  - Pinch in or out over a Terminal Board to adjust its font size for that Board.
- **Board Headers**:
  - Double-click to focus and center the Board.
  - Drag label or empty area to reorder within the Desk.
  - Right-click or Control-click for context menu (copy ID, keep in Drawer, duplicate, reload, adjust or reset content size, center, maximize, move to Desk, remove).
- **Board Resize**:
  - Drag the gap after a Board to resize it. Hold `Shift` to resize it with the next Board while keeping the pair's outer edges fixed.
- **Desk Switcher**:
  - Click `+` after the last Desk to create a new Desk.
  - Drag Desk button to reorder Desks.
  - Right-click for context menu (copy ID, open in new window, rename, delete, save preset, export).
- **Overview**:
  - Drag Board cards to reposition within or across Desks.
  - Click selects; double-click opens that Desk and Board. Hover card shows close button.
- **Terminal Links**:
  - `Command`-click HTTP/HTTPS link to open adjacent Web Board without adding to Drawer.
  - `Command`-click `file://` or file path to open in default macOS application.
