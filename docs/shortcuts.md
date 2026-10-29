# Den Browser Shortcuts

Vim-style commands for the Current Sheet are documented in [vim.md](./vim.md).

Den Mode makes Den operations available while a Sheet has keyboard focus. Toggle it with `Control` + `,` (customizable). The titlebar indicates `DEN MODE` or `SHEET INPUT`. `Escape` returns to Sheet Input.

The nine primary navigation shortcuts (toggling Den Mode and Board Rail, desk switching, board focus, and board movement) can be customized in Settings > Shortcuts. The complete in-app guide is available via `?` in Den Mode or the Den menu, and supports search by action, category, or key.

---

## App and Sheet Input

Open Board and the Current Sheet URL field accept local paths starting with `/` or `~/` and open them as `file://` URLs. Spaces and filename characters are preserved; `~/` expands to the user's home directory.

Available globally or while focused in a Sheet.

`Command` + `M` is unassigned by the app. Minimize remains available from the Window menu.

When the Profile panel is open, type to filter Profiles, use `Up` / `Down` to select one, press `Return` to open it, or press `Escape` to close the panel.

In Essentials, **Option + an Essential key** opens that Essential in Drawer; Shift preserves uppercase keys. **Option + Return** opens the selected Essential, and **Option-click** opens the clicked one in Drawer. URLs, searches and Terminal commands are supported; tutorials and the unnamed zmx session picker require a Board. The panel shows each Essential’s input and changes its destination hint while Option is held.

In Open Board, **Option + Return** opens the typed URL, search, Terminal command, or selected Recent Item in a new Drawer Peek without adding a Board. `:terminal [path]`, `:zellij [session]` and `:zmx <session>` use the same validation as opening a Board. `:tutorial` and unnamed `:zmx` show a validation message instead. Return continues to open a Board. Option-clicking a Recent Item also opens it in Drawer.

Universal Search behavior is documented in [universal-search.md](./universal-search.md).

In Open Board, remove an individual Recent Item with the trash icon to the right of its Essential control or with **Remove from Recent** in its context menu, without confirmation. **Clear** beside the Recent heading asks for confirmation before removing all Recent Items from the Profile. Both actions leave existing Boards and Essentials unchanged.

| Shortcut | Action |
| --- | --- |
| `Control` + `Command` + `P` | Open Profile panel |
| `Shift` + `Command` + `N` | Open Private Den |
| `Command` + `T` | Open Board panel (URL, search, `:tutorial`, `:terminal`, `:zellij`, `:zmx`) |
| `Command` + `P` | Universal Search (Boards, Desks, Profiles, Essentials, Recent, creation, commands) |
| `Command` + `Shift` + `P` | Universal Search with `> ` prefilled (commands only) |
| `Command` + `S` | Toggle Board Rail |
| `Command` + `L` | Edit Focused Board Link |
| `Command` + `D` | Create or focus a Terminal Side Board for the focused Terminal Board (both input modes) |
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

A new Terminal Side Board uses its Primary Board's Working Directory. A zmx Primary Board creates an independent zmx session under the same root; other Terminal Boards create a Shell.

---

## Den Mode

Toggle with `Control` + `,`. Press `Escape` to exit to Sheet Input.

### Navigation and Workspace

| Shortcut | Action |
| --- | --- |
| `Escape` | Exit Den Mode |
| `Left` / `Right` or `h` / `l` | Focus previous / next Board |
| `Up` / `Down` or `j` / `k` | Focus previous / next Desk |
| `Shift` + `Left` / `Right` or `H` / `L` | Move Focused Board left / right |
| `Shift` + `Up` / `Down` or `K` / `J` | Move Focused Desk one position earlier / later |
| `<` / `>` | Browse Boards without changing focus (`c` to re-center) |
| `/` | Filter Boards in Focused Desk by label or URL |
| `1`–`9`, `0` | Focus Desk 1–10 |
| `Shift` + digit | Move Focused Board to Desk 1–10 |
| `n` / `Space` | Open Board panel |
| `:` | Universal Search |
| `v` | Open Board from clipboard |
| `Option` + `V` | Open clipboard URL, search or Terminal command in Drawer |
| `Shift` + `N` | New Desk panel |
| `p` | Save Desk as Preset |
| `Shift` + `P` | Replace Desk from Preset |
| `Control` + `P` | Manage Desk Presets |
| `Tab` | Toggle Drawer |
| `o` | Toggle Overview |
| `i` | Show Notifications (`Up` / `Down` to select, `Return` to open) |
| `g`, then Essential key | Start that Essential Board input directly |
| `g`, then `Option` + Essential key | Open that Essential in Drawer |
| After `g`: `Up` / `Down`, then `Return` | Focus an Essential and start it; focus wraps at either end |
| `,` | Open Settings |
| `?` | Show Keyboard Shortcuts guide |
| `z` | Toggle Zen View (hide titlebar and chrome) |
| `Shift` + `F` | Toggle Focus Mode (blur other Boards) |

Reordering a Desk preserves the focused Desk and Board and keeps Den Mode active. It stops at either end without wrapping. The new order is saved and changes the Desk positions used by number shortcuts. Use Shift + digit to move a Board to another Desk.

### Board Actions

| Shortcut | Action |
| --- | --- |
| `[` / `]` | Back / forward in Sheet stack |
| `Shift` + `[` / `Shift` + `]` | Jump to First / latest Sheet |
| `-` / `=` | Narrow / widen Focused Board |
| `w`, then `-` / `=` / `1`–`9` | Resize all Primary Boards (adjust by 80pt or fit to window width) |
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
| `q` | zmx: confirm and end its Session; other Boards: remove and focus previous Board |
| `u` | Undo the latest Board move, Drawer placement, or removal |
| `Shift` + `D` | Delete Focused Desk (or discard all Drawer items in Drawer mode) |
| `Shift` + `R` | Rename Focused Desk |
| `a` | Move a Web or Terminal Primary Board without a Side Board to Drawer |
| `s` | Capture screenshot of Current Sheet to file |
| `Control` + `s` | Copy screenshot of Current Sheet to clipboard |
| `y` | Copy Focused Board URL, working directory, or session name |
| `Shift` + `Y` | Copy Focused Board ID |
| `t` | Pause / resume Sheet Navigation for Focused Board |

When saving a Board or Recent Item as an Essential, an assigned key asks for confirmation before replacing its Essential's name and input. Cancel keeps the save panel open with its input intact. Replacement preserves the Essential's position and leaves existing Boards unchanged.

- Sheet navigation, reload, and screenshot commands do not apply to Terminal Boards.
- Terminal Board removal or running `exit` ends its process; restoring starts a new shell or reconnects to Zellij/zmx.
- Den Mode `q` ends only the focused zmx Board's Session after confirmation, then closes its attached Boards. Child Sessions remain running. If ending the Session fails, its Boards remain open and an error is shown. `u` can restore a removed Board, but cannot restore terminated processes. For Zellij, `q` only removes the Board and leaves its Session running, like `x`.

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

### Board Undo

Den Mode and Overview use `u` for one Profile-shared history of Board moves between Desks,
moves into Drawer, placements from Drawer, and Board removals. UI and CLI operations enter
the same history. Up to twenty operations are retained during the current app run; relaunching
clears the history. Undo does not record another operation, and there is no Redo.

Undo returns a Board to its original Desk and position, or an Item to its original Drawer
position. A Board Group moves together. Live Web and Terminal state continues through moves;
Undo does not rewind navigation, input, or commands. Removal restoration starts a new Shell
or reconnects to Zellij/zmx; it cannot revive terminated processes.

Focus changes, Desk switching, same-Desk reordering, Board creation, width and label changes,
Desk operations, and Drawer Item discard are outside this history. Drawer discard restoration
remains available through **Drawer > Restore Discarded Drawer Item**.

Undo preserves Den Mode. Outside Overview it focuses a returned Board on its Desk; in Overview
it keeps the Overview open and selects the returned Board without changing the presented Desk.
Outside Overview, returning to Drawer opens it and expands the returned Item; returning a Board
to a Desk closes Drawer even when other Items remain. In Overview, returning to Drawer leaves
Overview open and reports the destination. A missing Board, original Desk, or
incompatible Board Group prevents Undo and leaves both state and history unchanged.

### Drawer Controls

Open with `Tab` in Den Mode.

Click **Add to Drawer** (+) in the Drawer header, enter a URL, search, or Terminal command, and press Return. Recent Items also open in Drawer from this panel. Drawer and its Peek remain visible behind the input panel; only the input panel accepts interaction until it closes. Escape returns to the same Drawer selection and filter.

| Shortcut | Action |
| --- | --- |
| `Tab` | Close Drawer in Den Mode |
| `n` / `Space` | Open Add to Drawer in Den Mode (outside filtering) |
| `Control` + `Escape` | Close Drawer |
| `/` | Search / filter Drawer items |
| `Up` / `Down` or `k` / `j` | Select Drawer item |
| `Return` | Toggle expanded Peek |
| `p` | Place selected item as a Board |
| `x` | Discard item and focus previous |
| `d` or `Delete` | Discard item and focus next |
| `Command` + `W` | Discard selected item |
| `u` | Undo the latest Board move, Drawer placement, or removal (Den Mode) |
| `f` | Toggle presentation style (floating card vs. bottom sheet) |
| `Shift` + `D` | Discard all Drawer items (with confirmation) |
| `Escape` | Clear filter or exit Drawer |

External links enter the receiving Profile's Drawer by default; the External Links setting can instead create a Board beside the Focused Board.
Den Mode `a` and the Web/Terminal Board header menu’s **Move to Drawer** remove the Primary Board from its Desk and retain its live Sheet Stack or Terminal Session. The Item keeps the Board ID, Drawer stays closed, and Den Mode remains active when invoked there. Boards in a group with a Side Board, Inspection Boards and Tutorials cannot move. Moving does not add a Board to removal history.
Option-clicking a supported HTTP, HTTPS, or local file link captures it without changing the Current Sheet or Desk layout.
New Drawer Items appear first, and duplicate URLs remain separate.

One Item at a time expands into a live Peek in each Profile window.
Closing the Drawer retains that window's expanded Peek selection for reopening. Closing, collapsing or switching a Peek retains its live web state; unopened Items do not load.
Opening the same Item in another Profile window moves its presentation there and collapses the previous window's Peek.
Discarding an Item releases its live state. Opened Items consume resources until discarded, placed or the last Profile window closes.
Opening a Drawer with an expanded Peek enters Sheet Input; without one it keeps Den Mode.
Toggling Den Mode while the Drawer is open moves keyboard focus between its Items and the expanded Peek without collapsing it.
Links opening a new browsing context in a Peek become Drawer Items; Command-click or middle-click keeps the current Peek, while adding Shift opens the new Item.
Discarding an expanded Item opens the next visible Item's Peek, or the previous one when it was last; discarding a collapsed Item leaves the current Peek unchanged.
Restoration selects and expands the Item, preserving Den Mode when invoked there; its ten-Item history lasts only for the current app run.
Placement focuses the new Board, removes the Item, and closes the Drawer; it transfers the Item's retained live state without reloading, including when the Item is collapsed or was last shown in another window.
Web URLs, Terminal session configuration and titles persist; expanded Peek identity and live Web or Terminal state do not.
A hidden Terminal Peek stops rendering while its process continues. Discard ends its runtime; restoring an ordinary Shell Item starts a new Shell in its saved Working Directory. Terminal desktop notifications appear as feedback linking to the Item; the Board notification list applies after placement.

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
Terminal Boards show a small snapshot when available. Snapshots fit inside Board
previews without cropping and retain their aspect ratio. Overview does not load
unvisited Boards to obtain one. Captures are suppressed for 30 seconds
after a successful capture, and the last image remains available afterwards.
Snapshots are requested when a surface is hidden or removed, without a fixed delay
after appearing. Terminal snapshots are captured before hiding; Web snapshots are
asynchronous and skip loading pages. Retained Board Facing rasters share a 64 MiB memory
budget. Ordinary Profiles retain compressed snapshots across restarts in a separate
128 MiB disk cache; Private Den keeps snapshots only in memory.

| Shortcut | Action |
| --- | --- |
| `Left` / `Right` or `h` / `l` | Select Board |
| `Up` / `Down` or `j` / `k` | Select Desk |
| `Shift` + movement | Move selected Board |
| `x` / `d` | Remove selected Board and select previous / next (Overview stays open) |
| `u` | Undo the latest Board move, Drawer placement, or removal (Overview stays open) |
| `=` / `+` / `-` | Zoom Overview in / out (plain keys remain text while searching) |
| `Command` + `+` / `-` | Zoom Overview in / out |
| `0` / `Command` + `0` | Reset Overview to its initial scale and center the selection (`0` remains text while searching) |
| `/` | Search / filter Desks and Boards (`Return` confirms, `Escape` clears) |
| `Return` | Enter selection as Focused Board |
| `Escape` | Clear search or return to Den Mode |

---

## Pointer Controls

- **Sheets**:
  - Release the primary mouse button after clicking or dragging on a Sheet to focus its Board.
  - Pinch in or out over a Web Board to adjust the Current Sheet's scale for that Board.
  - Pinch in or out over a Terminal Board to adjust its font size for that Board.
- **Board Headers**:
  - Double-click to focus and center the Board.
  - Drag label or empty area to reorder within the Desk. Dragging either a Primary Board or its Side Board moves the whole Board Group together.
  - Web, Terminal, and Inspection Board headers provide context menus with actions appropriate to their Board kind. Web Board actions include copying the Current Sheet URL or Board ID, moving to Drawer, duplicating, reloading, adjusting Sheet size, centering, maximizing, moving to a Desk, and removing. Tutorial Board headers have no context menu.
- **BoardRail**:
  - Right-click or Control-click a Board for its context menu (set or clear Anchor, rename, duplicate, move to Desk, copy Current Sheet URL for Web Boards, remove). Opening the menu does not change focus.
- **Board Resize**:
  - Drag the gap after a Board to resize it. Hold `Shift` to resize it with the next Board while keeping the pair's outer edges fixed.
- **Desk Switcher**:
  - Click `+` after the last Desk to create a new Desk.
  - Drag Desk button to reorder Desks.
  - Right-click for context menu (copy ID, open in new window, rename, duplicate, delete, save preset, export). [Duplicate Desk](./desk-presets.md#duplicating-a-desk) creates a same-label copy immediately after the source and switches to it.
- **Overview**:
  - Click a Board to select and center it when the mouse button is released, including an already selected Board. Dragging keeps the current selection until release, then selects the dragged Board without centering the canvas. Overview stays open for both actions. Double-click to enter a Board.
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
